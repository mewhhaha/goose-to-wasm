# Native compiler session timings — 2026-10-30

Commit `32ddcf4` adds an opt-in persistent native compiler worker. Requests
still parse, resolve, check, optimize, and emit the complete program. The
worker saves process startup and accepts unsaved source buffers; it does not
cache parsed syntax or checked functions.

Four successive runs used the same Release compiler, 32 generated functions,
O0, and 15 samples per measurement. Other local validation had finished.
Each edited sample changes one function, and every run verified the final
program's output. Times include the Python server round trip and dependency
validation.

| Run, in execution order | Edited median (ms) | Edited MAD (ms) | Unchanged median (ms) |
| --- | ---: | ---: | ---: |
| Fresh native process 1 | 21.785 | 3.114 | 2.696 |
| Persistent native worker 1 | 14.736 | 2.503 | 2.778 |
| Persistent native worker 2 | 17.287 | 3.200 | 3.102 |
| Fresh native process 2 | 21.094 | 2.582 | 3.207 |

These are local observations on a shared host, not a general speed guarantee.
Scheduling noise remains visible, especially in the second fresh-process
run's raw compiler and new Python process samples. Unchanged requests use the
existing whole-module cache in both modes. An earlier concurrent pilot did
not show an edited-build improvement. The worker remains opt-in.

The first uncached worker requests took 79.893 and 84.490 ms, including Python
server startup, native worker startup, and a full compilation. These are not
isolated worker startup measurements.

The [timing records](native-session.json) retain every timing sample, phase
medians, edited-build counters, compiler/input hashes, and platform metadata.
Repeated per-function fingerprint arrays are omitted from that comparison.

With the pinned Node and Python environment active, reproduce each mode with:

```sh
python bench/incremental.py --samples 15 --functions 32 \
  --output build/native-session-driver.json
python bench/incremental.py --samples 15 --functions 32 --native-worker \
  --output build/native-session-worker.json
```

Run in driver–worker–worker–driver order to compare repeated observations.
