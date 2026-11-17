from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

directory = Path(sys.argv[1]).resolve()
optimization = sys.argv[2]
flags = ["clang-23", "-std=gnu11", optimization]
c_path = directory / "goose.c"
program = c_path.read_bytes()
runtime, _ = program.split(b"\n#else /* program units */\n", 1)
(directory / "runtime.c").write_bytes(runtime + b"\n#endif\n")
units = 8
objects = [f"unit{i}.o" for i in range(units)]
commands = [[*flags, "-DG_RUNTIME_UNIT", "-c", "runtime.c", "-o", "runtime.o"]]
for i, obj in enumerate(objects):
    commands.append([*flags, "-DG_UNITS=8", f"-DG_UNIT={i}", "-c", "goose.c", "-o", obj])
link = [*flags, "runtime.o", *objects, "-lm", "-ldl", "-pthread", "-o", "goose"]

def run(argv):
    started = time.monotonic()
    subprocess.run(argv, cwd=directory, check=True)
    return {"argv": argv, "seconds": time.monotonic() - started}

started = time.monotonic()
with ThreadPoolExecutor(len(os.sched_getaffinity(0))) as pool:
    records = list(pool.map(run, commands))
records.append(run(link))
meta = {"c_sha256": hashlib.sha256(program).hexdigest(),
        "elf_sha256": hashlib.sha256((directory / "goose").read_bytes()).hexdigest(),
        "seconds": time.monotonic() - started, "cpus": sorted(os.sched_getaffinity(0)),
        "commands": records}
(directory / "build.json").write_text(json.dumps(meta, indent=2) + "\n")
print(directory.name, meta["seconds"], meta["elf_sha256"], flush=True)
