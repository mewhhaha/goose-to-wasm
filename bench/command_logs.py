"""Stream logical command-log files into one archive without creating raw files."""

from __future__ import annotations

import hashlib
import io
from pathlib import Path
import tarfile
from threading import RLock


class CommandLogs:
    def __init__(self, root):
        self.root = Path(root).resolve()
        self.path = self.root / "command-logs.tar.gz"
        self.root.mkdir(parents=True, exist_ok=True)
        self._archive = tarfile.open(self.path, "w|gz")
        self._lock = RLock()
        self._names = set()
        self._bytes = 0
        self._closed = False
        self._complete = False
        self._error = ""
        self._sha256 = None

    def write(self, path, data):
        """Keep exact bytes and reject duplicate or nonlocal logical paths."""
        path = Path(path)
        if path.is_absolute():
            path = path.relative_to(self.root)
        if not path.parts or any(part == ".." for part in path.parts):
            raise ValueError("command-log path must be relative to its output root")
        name = path.as_posix()
        if not isinstance(data, bytes):
            raise TypeError("command-log content must be bytes")
        with self._lock:
            if self._closed:
                raise ValueError("command-log archive is closed")
            if self._error:
                raise RuntimeError("command-log archive has failed: " + self._error)
            if name in self._names:
                raise ValueError("duplicate command-log path: " + name)
            entry = tarfile.TarInfo(name)
            entry.size = len(data)
            try:
                self._archive.addfile(entry, io.BytesIO(data))
            except BaseException as error:
                self._error = type(error).__name__ + ": " + str(error)
                raise
            self._names.add(name)
            self._bytes += len(data)

    def close(self, *, complete=True):
        with self._lock:
            if not self._closed:
                self._closed = True
                try:
                    self._archive.close()
                    value = hashlib.sha256()
                    with self.path.open("rb") as source:
                        for block in iter(lambda: source.read(1024 * 1024), b""):
                            value.update(block)
                    self._sha256 = value.hexdigest()
                    self._complete = complete and not self._error
                except BaseException as error:
                    self._error = type(error).__name__ + ": " + str(error)
                    raise
            return self.metadata()

    def metadata(self):
        # Callers save progress only between command completions. The lock also
        # makes snapshots safe while other host worker threads append entries.
        with self._lock:
            return {"format": "tar.gz", "path": str(self.path), "complete": self._complete,
                    "closed": self._closed, "sha256": self._sha256,
                    "files": len(self._names), "uncompressed_bytes": self._bytes,
                    "error": self._error}
