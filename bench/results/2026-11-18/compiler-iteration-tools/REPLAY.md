# Counting lifetime replay entries

The diagnostic compiler contains the lifetime checker from ba9dece and runs the f89ecf3 compiler project. The instrumented native and Wasm compilers agree on every count for a complete check and a complete memory64 emission. Both emitted the uninstrumented native control's 25 MiB module byte for byte. The control and both probes also rejected the same escaping reference with identical guest diagnostics. The Wasmtime CLI adds a newline when displaying guest stderr, which measure.py strips for the comparison.

Each visit starts when life_replay reaches one compact read or ordinary effect entry. Entries bypassed by a whole-chain hit have their own count. An applied visit grew the effect/read collection if it appended at least one LifeEffect or compact LifeReadEntry. An update requires an existing summary's or compact read's sets to change according to the checker's own semantic set comparison. One visit can update and append, and it can propagate across several frames. The mutually exclusive visit counters are summary-stamp skip, leaf-stamp skip, filtered and applied. Productive is a subset of applied. Cache writes, allocation of memo-table entries, unchanged offers, validation checks and changes affecting only live state are outside the productive count. Each effect application ran at replay depth one here. The frozen program visited no mapped replay entries. The counts do not estimate wall-time savings.

The negative fixture is a diagnostic compatibility check. It exits before the final probe printer. Native used Clang 23.1.5 with -O1 and ran on CPU 12. Wasmtime 50.0.1 ran the memory64 probe on CPU 4. These are counting instruments. The earlier timing baseline profiled a memory32 module.

| Frozen self-check or emission | Discovery | Validation | Total |
| --- | ---: | ---: | ---: |
| Visited entries | 7,997,929 | 2,537,335 | 10,535,264 |
| Skipped by an existing stamp | 5,279,250 | 1,879,873 | 7,159,123 |
| Added or changed at least one recorded effect | 647,965 | 32,262 | 680,227 |
| Newly appended effects and compact reads | 911,500 | 45,179 | 956,679 |
| Updates to an existing entry's sets | 2,832 | 0 | 2,832 |

The discovery chain cache bypassed 12,587,070 additional compact read entries at replay entry. Among the entries actually visited, 6,168,003 stamped construct reads belonged to uninterrupted runs of eight or more. That is 92.05% of leaf-stamp skips and 58.55% of all visits. Runs of 64 or more accounted for 3,941,362 visits.

A candidate experiment could try a group of eight consecutive reads in discovery, recording when every member has been offered in the current frame chain and recursion epoch. Invalidate on membership or value changes, preserve each interspersed non-read effect's position and use the existing per-entry replay on a miss. A first trial can retain the current validation and class-mapped paths in full. Each group's next entry still needs to obey the replay's rules for concurrent-by-construction list growth while processing its own effects. The histogram measures consecutive hits and does not establish how often a complete group would be reusable. Compare emitted output, lifetime-state fingerprints and whole-project CPU/instructions, including the maintenance cost of the grouping.

## Reproduction

From the repository root with the qualified 065aff3 compiler installed in build/bin, use the baseline native executable identified in bench/results/2026-11-18/lifetime-exit-index/matched.json. Copy the four [diagnostic scripts](tools/replay) into the scratch directory below.

```sh
repo=$PWD
stage=$repo/build/six-hills-1118/replay-probe
mkdir -p "$stage/compiler" "$stage/workload"
cp bench/results/2026-11-18/compiler-iteration-tools/tools/replay/*.py "$stage/"
git archive ba9dece selfhost native stdlib | tar -x -C "$stage/compiler"
git archive f89ecf3 selfhost native stdlib | tar -x -C "$stage/workload"
python "$stage/instrument.py" "$stage/compiler"
(cd "$stage/compiler" && taskset -c 4 "$repo/build/bin/goose" selfhost/main.goose --stdlib stdlib --target wasm-direct -O2 --wasm-memory64 --wasm-max-pages 262144 -o "$stage/probe.wasm")
(cd "$stage/compiler" && taskset -c 12 "$repo/build/bin/goose" selfhost/main.goose --stdlib stdlib --target native -O2 -o "$stage/probe.c")
(cd "$stage" && taskset -c 12 clang-23 -std=gnu11 -w -O1 probe.c -lm -ldl -pthread -o probe-native)
python "$stage/measure.py" baseline --stage "$stage" --repo "$repo" --cpu 4
python "$stage/measure.py" native --stage "$stage" --repo "$repo" --cpu 12
python "$stage/measure.py" wasm --stage "$stage" --repo "$repo" --cpu 4
"$repo/.venv/bin/python" "$stage/summarize.py" "$stage" "$repo"
```

The supplementary probe counts uninterrupted runs of already-stamped construct reads. A different effect kind, a filter, a visit that reaches application, or a replay boundary ends the run. Its seven length bins start at 1, 2, 4, 8, 16, 32 and 64. Each bin counts both runs and visits. It reproduces every primary self-check counter.

```sh
mkdir -p "$stage/runs-compiler/selfhost"
cp "$stage"/compiler/selfhost/*.goose "$stage/runs-compiler/selfhost/"
ln -s "$stage/compiler/native" "$stage/runs-compiler/native"
ln -s "$stage/compiler/stdlib" "$stage/runs-compiler/stdlib"
python "$stage/stamp_runs.py" "$stage/runs-compiler"
(cd "$stage/runs-compiler" && taskset -c 4 "$repo/build/bin/goose" selfhost/main.goose --stdlib stdlib --target wasm-direct -O2 --wasm-memory64 --wasm-max-pages 262144 -o "$stage/runs.wasm")
(cd "$stage/workload" && taskset -c 4 "$repo/.venv/bin/python" "$repo/scripts/run_wasmtime.py" "$stage/runs.wasm" --cache "$stage/runs.cwasm" -- selfhost/main.goose --stdlib stdlib --check >"$stage/runs.out" 2>"$stage/runs.err")
"$repo/.venv/bin/python" "$stage/summarize.py" "$stage" "$repo"
```
