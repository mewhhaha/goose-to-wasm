# Resident-engine execution review

Reviewed 2026-11-07. No remaining execution or timing blocker was found. This record was written while measurements were running; final sample qualification belongs to the completed `langbench-hot/report.json`. Review added no production changes, builds or workload runs.

The six executing-source hashes below match the active report's fingerprints. The test file is also pinned here:

| Source | SHA-256 |
| --- | --- |
| `bench/langbench_hot.py` | `a3f56bd400c6ceb70b6377f1df11dd27bdd346a8eb9d1a4934d32788967c395a` |
| `scripts/run_wasmtime.py` | `28861bacc2138406b85794be08af7d12b8b8499f04e02ece76f043d9cf0db2f1` |
| `scripts/run_wasm.mjs` | `8fffa7b611d1e4b3b02e742f536a69d6dfd69af46c573f00fd0d0a6a3aac1342` |
| `bench/langbench_hot_v8.mjs` | `5401b4d2d003309c4cf7a6b6ab3796f25618eb438cc8651c8967f428c66d9723` |
| `bench/langbench.py` | `cb753ad67095b16757dc501120eddc470ead9efd8af00d2b22e6fb6a85c247d5` |
| `bench/process.py` | `ded4f0856702001f29d1f80bc12c0e54407354fda5adae48ffbd896321ecef72` |
| `tests/test_langbench_hot.py` | `78e4a3f8049d11bd0eeeb97bc6173e328ca93021b65317d3a323f49b492679ae` |

- Wasmtime reuses one Engine and one deserialized Module. Each invocation creates fresh Store, Linker, Instance and callback state, then closes per-run resources after timing. Deserialization accepts only bytes compiled locally, written with exclusive creation and read back with a matching hash. There is no arbitrary serialized-artifact input path.
- V8 reuses one prepared WebAssembly.Module in one resident process and creates fresh instances/imports. Its bytes and prepared-module API branches are distinct and preserve the prior bytes API. PID, request ID, source hash and module-construction count are checked. Timeout/protocol failures kill and quarantine the worker before another cell runs.
- The prior qualified report supplies frozen compiler provenance. Exact archived executable/Wasm hashes and current workload sources are checked; old compilers and checkout paths are not execution prerequisites. The actual Node executable, Python executable and loaded Wasmtime library match the reference hashes. Runtime flags and loader overrides are recorded; this run has empty Node options, empty `execArgv`, and empty loader overrides.
- Internal source clocks exclude input, instance creation, compilation, engine startup and output. The kernel interval must fit inside its host execution interval. Native controls remain fresh processes with their internal clocks; C retains its thread creation/join and atomic queue. Resident-request wall times and native process wall times have different boundaries.
- One full-kernel warmup per profile/cell precedes seven interleaved measured rounds. Warmups remain recorded. The V8 optimization tier is **not verified**: one module construction does not establish one machine-code compilation or prove top-tier execution. Historical cold build times remain separately collected references.

Preflight reported before measurement: eight prepared-execution tests, three existing Python-host tests and nine cold-harness tests passed; all six archived artifacts returned 636 for the 8-by-8, 25-iteration smoke input. The reviewed tests cover fresh mutable guest/host state, no recompilation on prepared calls, mismatched source rejection, refusal to overwrite/deserialize foreign artifacts, relocated execution without old compilers, and timeout quarantine.

Both engines use Wasm SHA-256 `b2338da428272b85fc4425bc24b9a0e80976530c25e8281fe85d53c49070fb76`. The active preparation receipt records one Wasmtime compile (5.631 ms), one deserialize (0.063 ms), and one initial V8 module preparation (0.834 ms). These are single preparation observations, excluded from kernel samples, not distributions or evidence of a runtime speedup.
