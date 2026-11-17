"""Replay matching function bodies in alternating pairs on Linux."""

import hashlib
from pathlib import Path
import resource
import subprocess
import sys
import time

root = Path(sys.argv[1]).resolve()
workload = sys.argv[2]
variants = sys.argv[3:]
digest = None
for variant in [*variants, *reversed(variants)] * 3:
    output = root / variant / f'{workload}.out'
    command = [str(root / variant / 'replay'), str(root / f'{workload}.bin'), str(output)]
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    start = time.monotonic_ns()
    result = subprocess.run(command, capture_output=True, text=True, check=True)
    elapsed = time.monotonic_ns() - start
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    sha = hashlib.sha256(output.read_bytes()).hexdigest()
    if digest is None:
        digest = sha
    elif sha != digest:
        raise SystemExit(f'{variant}: differing remapped locals or code')
    print(variant, result.stdout.strip(), elapsed, after.ru_utime - before.ru_utime,
          after.ru_stime - before.ru_stime, sha, flush=True)
