"""Local build-process, publication, and locking primitives.

These helpers are deliberately independent of the compiler frontend. A worker
never reuses an AST; a publication never exposes a partly written file.
"""
from __future__ import annotations

from contextlib import AbstractContextManager
import json
import os
from pathlib import Path
import queue
import signal
import subprocess
import tempfile
import threading
import time


class BuildError(Exception):
    pass


def terminate(process: subprocess.Popen) -> None:
    """Stop the process and, on POSIX, every child in its private process group."""
    if os.name == "posix":
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    elif process.poll() is None:
        process.kill()
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait()


def run_process(command: list[str], timeout: float) -> tuple[float, bytes, bytes]:
    started = time.perf_counter_ns()
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               start_new_session=os.name == "posix")
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        terminate(process)
        stdout, stderr = process.communicate()
        raise BuildError(f"{Path(command[0]).name} exceeded {timeout:g}s; process terminated")
    except BaseException:
        terminate(process)
        process.communicate()
        raise
    elapsed = (time.perf_counter_ns() - started) / 1_000_000
    if process.returncode:
        diagnostic = (stderr + stdout).decode("utf-8", errors="replace").strip()
        raise BuildError(f"{Path(command[0]).name} failed ({process.returncode}):\n{diagnostic}")
    return elapsed, stdout, stderr


class NativeSession:
    """One bounded, serial JSON-lines connection to a native compiler worker."""
    def __init__(self, compiler: Path, temporary_parent: Path, timeout: float):
        self.compiler = compiler
        self.request_count = 0
        self.responses: queue.Queue = queue.Queue()
        self.diagnostics = tempfile.TemporaryFile(dir=temporary_parent)
        self.process = None
        self.reader = None
        try:
            self.process = subprocess.Popen([str(compiler), "--wasm-server"],
                                            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                            stderr=self.diagnostics, start_new_session=os.name == "posix")
            self.reader = threading.Thread(target=self._read, name="goose-native-worker", daemon=True)
            self.reader.start()
            hello = self._response(timeout)
            if hello != {"protocol": "goose-native-session-v1"}:
                raise BuildError(f"unsupported native compiler worker handshake: {hello!r}")
        except BaseException:
            self.close()
            raise

    def _read(self) -> None:
        try:
            while True:
                line = self.process.stdout.readline(1_048_577)
                if not line:
                    self.responses.put(None)
                    return
                if len(line) > 1_048_576 or not line.endswith(b"\n"):
                    self.responses.put(BuildError("native compiler response exceeds 1 MiB or is incomplete"))
                    return
                self.responses.put(line)
        except (OSError, ValueError) as error:
            self.responses.put(error)

    def _diagnostic(self) -> str:
        self.diagnostics.seek(0)
        data = self.diagnostics.read(4_194_305)
        text = data[:4_194_304].decode("utf-8", errors="replace").strip()
        if len(data) > 4_194_304:
            text += "\n[diagnostics truncated at 4 MiB]"
        return text

    def _response(self, timeout: float) -> dict:
        try:
            response = self.responses.get(timeout=timeout)
        except queue.Empty:
            raise BuildError(f"native compiler worker exceeded {timeout:g}s") from None
        if response is None:
            raise BuildError("native compiler worker exited before replying:\n" + self._diagnostic())
        if isinstance(response, Exception):
            raise BuildError(f"native compiler worker protocol failed: {response}")
        try:
            result = json.loads(response)
            if not isinstance(result, dict):
                raise ValueError("response is not an object")
            return result
        except (ValueError, TypeError) as error:
            raise BuildError(f"invalid native compiler worker response: {error}") from error

    def compile(self, command: list[str], timeout: float) -> tuple[float, str, dict]:
        self.request_count += 1
        identifier = str(self.request_count)
        request = json.dumps({"id": identifier, "args": command[1:]}).encode() + b"\n"
        if len(request) > 1_048_576:
            raise BuildError("native compiler request exceeds 1 MiB")
        self.diagnostics.seek(0)
        self.diagnostics.truncate()
        started = time.perf_counter_ns()
        try:
            self.process.stdin.write(request)
            self.process.stdin.flush()
            response = self._response(timeout)
            if (response.get("id") != identifier or not isinstance(response.get("code"), int)
                    or not isinstance(response.get("request"), int)
                    or not isinstance(response.get("compile_ns"), int)):
                raise BuildError("native compiler worker response does not match its request")
        except BaseException:
            self.close()
            raise
        elapsed = (time.perf_counter_ns() - started) / 1_000_000
        diagnostic = self._diagnostic()
        if response["code"]:
            error = response.get("error", "")
            if response["code"] != 1:
                self.close()
            raise BuildError(f"native compiler failed ({response['code']}):\n{error}\n{diagnostic}".strip())
        return elapsed, diagnostic, response

    def close(self) -> None:
        process = getattr(self, "process", None)
        if process is not None:
            if process.poll() is None:
                try:
                    process.stdin.close()
                    process.wait(timeout=1)
                except (OSError, ValueError, subprocess.TimeoutExpired):
                    terminate(process)
            if process.stdin and not process.stdin.closed:
                process.stdin.close()
            if self.reader and self.reader.ident is not None:
                self.reader.join(timeout=2)
            if process.stdout:
                process.stdout.close()
        if not self.diagnostics.closed:
            self.diagnostics.close()


class OutputLocks(AbstractContextManager):
    """Cross-process locks for all named outputs, acquired in canonical order.

    Lock files intentionally persist. Unlinking a lock while another process is
    waiting would let a third writer acquire a different inode for the same name.
    """
    def __init__(self, paths: list[Path], timeout: float):
        self.paths = sorted(set(paths))
        self.timeout = timeout
        self.files = []

    def __enter__(self):
        deadline = time.monotonic() + self.timeout
        try:
            for path in self.paths:
                path.parent.mkdir(parents=True, exist_ok=True)
                handle = (path.parent / ("." + path.name + ".goose-lock")).open("a+b")
                self.files.append(handle)
                if os.name == "nt":
                    import msvcrt
                    if not handle.tell():
                        handle.write(b"\0")
                        handle.flush()
                    lock = lambda: msvcrt.locking(handle.fileno(), msvcrt.LK_NBLCK, 1)
                else:
                    import fcntl
                    lock = lambda: fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                while True:
                    handle.seek(0)
                    try:
                        lock()
                        break
                    except BlockingIOError:
                        pass
                    except OSError as error:
                        if os.name != "nt" or error.winerror not in (33, 36) and error.errno not in (13, 36):
                            raise
                    if time.monotonic() >= deadline:
                        raise BuildError(f"timed out waiting for output lock: {path}")
                    time.sleep(0.01)
            return self
        except BaseException:
            self.__exit__(None, None, None)
            raise

    def __exit__(self, *exc):
        for handle in reversed(self.files):
            handle.close()  # Closing releases either flock or the Windows byte lock.
        self.files.clear()


def publish_files(publications: dict[Path, tuple[bytes, bool]]) -> None:
    """Prepare all outputs before replacing any, and roll back ordinary failures.

    Each file is replaced atomically. OutputLocks coordinates writers of related
    files; an unrelated reader needs the report's digest to identify a matching
    generation. No filesystem promises an atomic rename of several paths.
    """
    staged: dict[Path, Path] = {}
    backups: dict[Path, Path | None] = {}
    installed = []
    preserve = set()
    try:
        for path, (data, executable) in publications.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            if (path.is_file() and path.read_bytes() == data
                    and (not executable or path.stat().st_mode & 0o111)):
                continue
            if path.exists() and not path.is_file():
                raise BuildError(f"output is not a regular file: {path}")
            fd, name = tempfile.mkstemp(prefix="." + path.name + ".new-", dir=path.parent)
            staged[path] = Path(name)
            with os.fdopen(fd, "wb") as stream:
                stream.write(data)
            if executable:
                os.chmod(name, 0o755)
            if path.exists():
                fd, backup = tempfile.mkstemp(prefix="." + path.name + ".old-", dir=path.parent)
                os.close(fd)
                backup_path = Path(backup)
                backups[path] = backup_path
                # Preserve the complete old file and its mode without reading
                # it through Python again; hard links are cheap where available.
                backup_path.unlink()
                try:
                    os.link(path, backup_path)
                except OSError:
                    import shutil
                    shutil.copy2(path, backup_path)
            else:
                backups[path] = None
        for path, temporary in staged.items():
            os.replace(temporary, path)
            installed.append(path)
    except BaseException:
        restore_errors = []
        for path in reversed(installed):
            try:
                old = backups[path]
                if old is None:
                    path.unlink()
                else:
                    os.replace(old, path)
            except OSError as error:
                if backups[path] is not None:
                    preserve.add(backups[path])
                restore_errors.append(f"{path}: {error}; previous file retained at {backups[path]}")
        if restore_errors:
            raise BuildError("output rollback failed: " + "; ".join(restore_errors))
        raise
    finally:
        for path in [*staged.values(), *(p for p in backups.values() if p is not None)]:
            if path not in preserve:
                path.unlink(missing_ok=True)
