"""Repeat the paired compiler trial with CPU time alongside wall time and hardware counters."""
from pathlib import Path
import resource
import runpy
import subprocess
import sys
import time

root = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
sys.path[:0] = [str(root / "scripts"), str(root / "bench/results/2026-11-18/selfhost-wasm-runtime/tools")]
import measure

measure_call = measure.measured

def cpu_ns(child):
    if child:
        usage = resource.getrusage(resource.RUSAGE_CHILDREN)
        return round((usage.ru_utime + usage.ru_stime) * 1e9)
    return time.thread_time_ns()

def measured(call, child=False):
    before = cpu_ns(child)
    value, elapsed, counters = measure_call(call, child)
    counters["invocation_cpu_ns"] = cpu_ns(child) - before
    return value, elapsed, counters

measure.measured = measured
runpy.run_path(str(root / "bench/results/2026-11-18/compiler-iteration-tools/tools/slots.py"), run_name="__main__")
