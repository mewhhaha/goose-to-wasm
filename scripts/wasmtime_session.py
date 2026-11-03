#!/usr/bin/env python3
"""Reuse the native host's engine and modules with a fresh instance per run."""
from dataclasses import dataclass
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import threading

ROOT = Path(__file__).resolve().parents[1]
HEADER = struct.Struct('<IIQQQQ')


@dataclass(frozen=True)
class RunResult:
    returncode: int
    stdout: bytes
    stderr: bytes
    module_cache_hit: bool
    prepare_ns: int
    start_ns: int


class RuntimeSession:
    def __init__(self, host=ROOT/'build/bin/goose-wasmtime', *, cache=False, cache_config=None):
        command = [str(host), '--serve']
        if cache:
            command.append('--cache')
        else:
            command.append('--no-cache')
        if cache_config is not None:
            command += ['--cache-config', str(cache_config)]
        self._lock = threading.Lock()
        self._closed = False
        self._diagnostics = tempfile.TemporaryFile()
        try:
            self._process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                             stderr=self._diagnostics)
        except BaseException:
            self._diagnostics.close()
            raise
        try:
            if self._read(8) != b'GWRT\1\0\0\0':
                raise RuntimeError('unsupported native runtime protocol')
        except BaseException:
            self.close()
            raise

    def _read(self, size):
        result = bytearray()
        while len(result) < size:
            block = self._process.stdout.read(size-len(result))
            if not block:
                self._diagnostics.seek(0)
                diagnostic = self._diagnostics.read().decode(errors='replace')
                raise RuntimeError('native runtime closed its response stream: '+diagnostic)
            result.extend(block)
        return bytes(result)

    def run(self, module, stdin=b''):
        path = os.fsencode(Path(module).resolve())
        if isinstance(stdin, str):
            stdin = stdin.encode()
        if not isinstance(stdin, bytes):
            raise TypeError('stdin must be bytes or text')
        if b'\0' in path or len(path) > 65535:
            raise ValueError('module path exceeds the runtime protocol')
        if len(stdin) > 0xffffffff:
            raise ValueError('stdin exceeds the runtime protocol')
        with self._lock:
            if self._closed:
                raise RuntimeError('native runtime session is closed')
            try:
                self._process.stdin.write(struct.pack('<II', len(path), len(stdin)))
                self._process.stdin.write(path)
                self._process.stdin.write(stdin)
                self._process.stdin.flush()
                flags, code, stdout_size, stderr_size, prepare, start = HEADER.unpack(self._read(HEADER.size))
                if flags & ~1:
                    raise RuntimeError('unsupported native runtime response flags')
                return RunResult(code, self._read(stdout_size), self._read(stderr_size),
                                 bool(flags & 1), prepare, start)
            except BaseException:
                self._finish(kill=True)
                raise

    def _finish(self, *, kill=False):
        if self._closed:
            return
        self._closed = True
        try:
            if kill and self._process.poll() is None:
                self._process.kill()
            try:
                self._process.stdin.close()
            except OSError:
                pass
            try:
                self._process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self._process.kill()
                self._process.wait()
        finally:
            self._process.stdout.close()
            self._diagnostics.close()

    def close(self):
        with self._lock:
            self._finish()

    def __enter__(self):
        return self

    def __exit__(self, *exception):
        self.close()
