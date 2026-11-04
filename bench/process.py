"""Benchmark subprocesses with event-driven Linux deadline waits."""

import math
import os
import select
import subprocess
import time


class Process(subprocess.Popen):
    def _wait(self, timeout):
        if timeout is None or self.returncode is not None or not hasattr(os, "pidfd_open"):
            return super()._wait(timeout)
        deadline = time.monotonic() + timeout
        try:
            descriptor = os.pidfd_open(self.pid)
        except OSError:
            return super()._wait(timeout)
        try:
            # pidfds wake at exit; poll also supports descriptors above FD_SETSIZE.
            ready = select.poll()
            ready.register(descriptor, select.POLLIN)
            remaining = max(0, deadline - time.monotonic())
            if not ready.poll(math.ceil(remaining * 1000)):
                raise subprocess.TimeoutExpired(self.args, timeout)
        finally:
            os.close(descriptor)
        return super()._wait(None)


def run(*args, input=None, capture_output=False, timeout=None, check=False, **kwargs):
    """Use subprocess.run semantics with Process's event-driven timed wait."""
    if input is not None:
        if kwargs.get("stdin") is not None:
            raise ValueError("stdin and input arguments may not both be used")
        kwargs["stdin"] = subprocess.PIPE
    if capture_output:
        if kwargs.get("stdout") is not None or kwargs.get("stderr") is not None:
            raise ValueError("stdout and stderr arguments may not be used with capture_output")
        kwargs["stdout"] = kwargs["stderr"] = subprocess.PIPE
    with Process(*args, **kwargs) as child:
        try:
            stdout, stderr = child.communicate(input, timeout=timeout)
        except subprocess.TimeoutExpired as error:
            child.kill()
            if os.name == "nt":
                error.stdout, error.stderr = child.communicate()
            else:
                child.wait()
            raise
        except BaseException:
            child.kill()
            raise
        code = child.poll()
        if check and code:
            raise subprocess.CalledProcessError(code, child.args, output=stdout, stderr=stderr)
    return subprocess.CompletedProcess(child.args, code, stdout, stderr)
