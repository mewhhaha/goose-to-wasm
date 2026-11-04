#!/usr/bin/env python3
"""Process deadlines must preserve output and reap children without polling sleeps."""

import errno
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "bench"))
import process


def python(source):
    return [sys.executable, "-c", source]


def pidfd_available():
    try:
        descriptor = os.pidfd_open(os.getpid())
    except (AttributeError, OSError):
        return False
    os.close(descriptor)
    return True


PIDFD_AVAILABLE = pidfd_available()


class BenchmarkProcessTests(unittest.TestCase):
    def test_binary_empty_and_nonempty_input(self):
        for value in (b"", b"hello\x00\xff"):
            with self.subTest(value=value):
                result = process.run(python("import sys; sys.stdout.buffer.write(sys.stdin.buffer.read())"),
                                     input=value, capture_output=True, timeout=3, check=True)
                self.assertEqual(result.stdout, value)
                self.assertEqual(result.stderr, b"")
                self.assertEqual(result.returncode, 0)

    def test_text_encoding_and_merged_stderr(self):
        empty = process.run(python("import sys; print(sys.stdin.read(),end='')"), input="",
                            capture_output=True, text=True, timeout=3)
        self.assertEqual((empty.stdout, empty.stderr), ("", ""))
        result = process.run(python("import sys; print(sys.stdin.read(),end=''); print('err',file=sys.stderr)"),
                             input="héllo", text=True, encoding="utf-8", stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, timeout=3)
        self.assertIn("héllo", result.stdout)
        self.assertIn("err\n", result.stdout)
        self.assertIsNone(result.stderr)

    def test_nonzero_exit_and_check_preserve_output(self):
        command = python("import sys; print('out'); print('err',file=sys.stderr); sys.exit(7)")
        result = process.run(command, capture_output=True, text=True, timeout=3)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (7, "out\n", "err\n"))
        with self.assertRaises(subprocess.CalledProcessError) as caught:
            process.run(command, capture_output=True, text=True, timeout=3, check=True)
        self.assertEqual(caught.exception.returncode, 7)
        self.assertEqual(caught.exception.stdout, "out\n")
        self.assertEqual(caught.exception.stderr, "err\n")

    def test_argument_conflicts(self):
        for kwargs in ({"input": b"", "stdin": subprocess.PIPE},
                       {"capture_output": True, "stdout": subprocess.PIPE},
                       {"capture_output": True, "stderr": subprocess.PIPE}):
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                process.run(python("pass"), **kwargs)

    @unittest.skipUnless(PIDFD_AVAILABLE, "Linux pidfd")
    def test_closed_output_pipes_then_delayed_exit_never_poll_sleeps(self):
        # communicate sees EOF before process exit: this is exactly where the
        # stdlib's timed wait would poll WNOHANG and sleep for at least 1 ms.
        command = python("import os,time; os.close(1); os.close(2); time.sleep(.04)")
        with patch.object(subprocess.time, "sleep", side_effect=AssertionError("polling wait used")):
            result = process.run(command, input=b"", capture_output=True, timeout=3)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, b"", b""))

    def test_timeout_kills_reaps_and_preserves_partial_output(self):
        captured = []
        original = process.Process

        class TrackedProcess(original):
            def __init__(self, *args, **kwargs):
                super().__init__(*args, **kwargs)
                captured.append(self)

        command = python("import sys,time; print('out',flush=True); print('err',file=sys.stderr,flush=True); time.sleep(10)")
        with patch.object(process, "Process", TrackedProcess):
            with self.assertRaises(subprocess.TimeoutExpired) as caught:
                process.run(command, capture_output=True, text=True, timeout=.3)
        self.assertEqual(caught.exception.stdout, b"out\n")
        self.assertEqual(caught.exception.stderr, b"err\n")
        self.assertIsNotNone(captured[0].returncode)
        self.assertTrue(captured[0].stdout.closed)
        self.assertTrue(captured[0].stderr.closed)
        if os.name != "nt":
            with self.assertRaises(ChildProcessError):
                os.waitpid(captured[0].pid, os.WNOHANG)

    @unittest.skipUnless(PIDFD_AVAILABLE, "Linux pidfd")
    def test_wait_deadline_after_pipes_closed_closes_pidfd_and_can_reap(self):
        descriptors = []
        original = os.pidfd_open

        def opened(*args, **kwargs):
            descriptor = original(*args, **kwargs)
            descriptors.append(descriptor)
            return descriptor

        command = python("import os,time; os.close(1); os.close(2); time.sleep(10)")
        with process.Process(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as child:
            try:
                with patch.object(process.os, "pidfd_open", side_effect=opened):
                    with self.assertRaises(subprocess.TimeoutExpired):
                        child.communicate(timeout=.3)
                self.assertTrue(descriptors)
                for descriptor in descriptors:
                    with self.assertRaises(OSError):
                        os.fstat(descriptor)
            finally:
                child.kill()
                child.wait()

    @unittest.skipUnless(PIDFD_AVAILABLE, "Linux pidfd")
    def test_pidfds_closed_after_success_and_no_descriptor_leak(self):
        before = len(list(Path("/proc/self/fd").iterdir()))
        for _ in range(8):
            result = process.run(python("pass"), capture_output=True, timeout=3)
            self.assertEqual(result.returncode, 0)
        self.assertEqual(len(list(Path("/proc/self/fd").iterdir())), before)

    def test_unsupported_pidfd_falls_back_to_stdlib(self):
        with patch.object(process.os, "pidfd_open", create=True, side_effect=OSError(errno.ENOSYS, "unsupported")):
            result = process.run(python("print('ok')"), capture_output=True, timeout=3)
        self.assertEqual(result.stdout, b"ok\n")

    @unittest.skipUnless(PIDFD_AVAILABLE, "Linux pidfd")
    def test_pidfd_above_select_fd_limit(self):
        import fcntl
        import resource
        if resource.getrlimit(resource.RLIMIT_NOFILE)[0] <= 2048:
            self.skipTest("descriptor limit below high-fd probe")
        original = os.pidfd_open

        def high_descriptor(*args, **kwargs):
            descriptor = original(*args, **kwargs)
            try:
                return fcntl.fcntl(descriptor, fcntl.F_DUPFD_CLOEXEC, 2048)
            finally:
                os.close(descriptor)

        with patch.object(process.os, "pidfd_open", side_effect=high_descriptor):
            result = process.run(python("pass"), capture_output=True, timeout=3)
        self.assertEqual(result.returncode, 0)

    def test_communication_failure_kills_and_reaps(self):
        children = []
        original = process.Process

        class BrokenCommunication(original):
            def __init__(self, *args, **kwargs):
                super().__init__(*args, **kwargs)
                children.append(self)

            def communicate(self, *args, **kwargs):
                raise RuntimeError("communication failed")

        with patch.object(process, "Process", BrokenCommunication):
            with self.assertRaisesRegex(RuntimeError, "communication failed"):
                process.run(python("import time; time.sleep(10)"), capture_output=True, timeout=3)
        self.assertIsNotNone(children[0].returncode)
        self.assertTrue(children[0].stdout.closed)
        self.assertTrue(children[0].stderr.closed)

    def test_uncaptured_output_and_zero_deadline(self):
        result = process.run(python("pass"), timeout=3)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, None, None))
        with process.Process(python("import time; time.sleep(10)")) as child:
            try:
                with self.assertRaises(subprocess.TimeoutExpired):
                    child.wait(timeout=0)
            finally:
                child.kill()
                child.wait()

    @unittest.skipIf(os.name == "nt", "POSIX process groups")
    def test_process_remains_compatible_with_existing_group_cleanup(self):
        import langarena
        with tempfile.TemporaryDirectory(prefix="benchmark-process-") as directory:
            source = ("import subprocess,sys,time; "
                      "subprocess.Popen([sys.executable,'-c','import time; time.sleep(10)']); "
                      "print('descendant started',flush=True); time.sleep(10)")
            result = langarena.execute(python(source), Path(directory), cwd=ROOT, timeout=.3)
        self.assertEqual(result["returncode"], -1)
        self.assertIn("process group terminated", result["error"])
        self.assertIn("descendant started", result["stdout"])
        self.assertLess(result["wall_seconds"], 3)


if __name__ == "__main__":
    unittest.main()
