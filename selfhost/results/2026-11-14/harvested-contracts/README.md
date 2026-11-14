# Harvested upstream-differential contracts · 2026-11-14

The `tests/test_*.py` modules written for the C++ compiler asserted that compiler's internals: its `--offline` option, `--wasm-stats` fields, `goose.regions` sections. They never ran on the Goose compiler. Their generated programs are now contracts whose expected output comes from plain upstream, and the modules are removed.

## Programs

Each module ran under unittest with its compiler calls recorded and its assertions disabled ([capture](reproduction/capture_run.py)). Each unique source then ran with plain upstream `32a4f44` (`goose run` at `-O0`, `-O1` and `-O2`, and `goose check`, with upstream's stdlib; executable SHA-256 `93159a89…`) ([survey](reproduction/survey.py)). Upstream printed the same at all three levels for every program.

| | Programs |
| --- | ---: |
| Captured source files, from 66 modules | 672 |
| Unique sources | 637 |
| Contracted | 560 |
| Excluded | 77 |

The 560 contracted programs make 1,120 rows in `tests/conformance/cases.json`, one per backend, each at levels 0 and 2: 2,240 checks. 534 programs run and compare stdout and exit status. 24 that upstream rejects are type-error rows naming our diagnostic, and 2 that upstream accepts stay rejected, as [FEATURES.md](../../../../docs/FEATURES.md#differences-found-by-the-upstream-differential-run) lists that false accept. Six programs state a larger direct-Wasm memory (`maximum_pages`). 163 of the run programs have an empty `main`. 112 of those export functions that the old tests called through a host, so their rows check compilation, global initialization and startup only.

Exclusions, each with its reason and, where upstream is wrong, the spec's value and our backends' output in the [manifest](../../../../tests/fixtures/contracts/upstream-differential/harvest/manifest.json):

| Reason | Programs |
| --- | ---: |
| Needs a host import (`prepared`, `callback`, `probe`, `forge`, `foreign`, `bench_input`) | 44 |
| Upstream reads aliased or corrupt bytes | 16 |
| Upstream's region-top leftovers (layer 2) | 9 |
| Byte-identical to an existing fixture | 4 |
| Upstream's TinyCC rejects its own C | 3 |
| An existing contract's program apart from comments | 1 |

In 15 of the 16 aliased programs, a multiple-result return builds its first value over a returned local while a later value still reads or writes that local. §7.3 (**Named results**) copies such a local. Native C reads the aliased bytes too in 5 of them, and direct Wasm in 12.

## Gaps

12 rows fail and are recorded, with their causes, in [known-gaps.json](../../../../tests/conformance/known-gaps.json).

| Cause | Rows | New |
| --- | ---: | --- |
| A fill `[v; n]` whose count the backend cannot hold aborts before `v`'s exit is taken | 6 | yes |
| Native C rejects a struct larger than the direct-Wasm memory size | 2 | yes |
| Direct Wasm builds a multiple-result return over a returned local that a later result reads | 2 | yes |
| Direct Wasm's message for an overflowing runtime-capacity push | 2 | no |

## Tests

Under unittest with `GOOSE_COMPILER` set, 21 of the 94 modules passed. [Classification](tests.json)

- 64 of the 66 whose programs were harvested failed on `--offline`; `test_root_struct_backends` and `test_slice_pool_backends` pass. With that option dropped ([shim](reproduction/drop-offline.sh)), 9 passed and 55 failed on the C++ compiler's internals.
- 2 more failed on C++ internals: `test_local_tee` builds C++ against `compiler/wasm_binary.h`, and `test_backend_extensions` passes `--offline` to the driver.
- 6, with `bench/incremental.py`, tested the C++ compiler's session mode.
- `test_command_logs` errors in one test: it reads a `BACKENDS` list that `bench/qualify_compiler.py` no longer has. It is kept. `tests/run_differential.py`, a script, passes `--offline` to the driver and fails every observation. It is kept, since `bench/` imports its cases.

The 72 in the first three groups are removed. 22 modules remain.

## Qualification

`scripts/qualify.py --baseline <qualified compiler of af2de30> --jobs 10` ran on commit `385ba33`. The commit that adds this directory changes only documentation. [Summary](summary.json)

| Stage | Exit | Seconds | Result |
| --- | ---: | ---: | --- |
| bootstrap | 0 | 42.7 | Fixed point: generated C `b78b8c8c…`, executable `da0aecd2…`, without profile |
| conformance | 0 | 283.8 | 10,685 of 10,789 rows pass; exactly the 104 recorded gaps fail |
| native-checks | 0 | 21.5 | 54 steps ok |
| equivalence | 0 | 193.0 | 0 of 10,045 outputs differ |
| unit-tests | 0 | 32.4 | ok |

- The compiler is unchanged: its executable is the baseline's, `da0aecd2…`. Equivalence now also covers the harvest fixtures, which adds 2,240 outputs.
- Native code generation did not change, so the three-unit pass did not run.
- Conformance needed 3,216 native programs and found 1,802 in the shared cache. All 1,066 for the new rows were there, from the runs that checked them. The 1,414 misses are earlier rows; other sessions use the same cache, so the stage time is not a warm baseline.

Native rows build with GCC 16.2.1. Direct-Wasm rows run on the Wasmtime host `goose-wasmtime` (`b1b3bddd…`); on V8 (Node 24.12.0), as CI also runs them, the same 1,120 checks pass except the 8 recorded direct-Wasm gaps.

Alone, at the 5 jobs that qualification gives the conformance stage, the 2,240 new checks take 138.9 s cold, compiling 1,066 native programs, and 5.8 s warm.
