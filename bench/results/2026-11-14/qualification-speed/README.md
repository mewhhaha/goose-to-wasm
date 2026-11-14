# Qualification speed · 2026-11-14

Qualifying a change used to take 27–30 minutes. It now takes 14.5 minutes from empty caches and 3.2 minutes on a rerun. The work is the same: bootstrap `--verify`, the contract suite as one translation unit per program and again as three program units, the native runtime checks, output equivalence against a baseline, and the unit tests. These are tooling changes. The compiler and its output did not change.

## Where the time went

Measured on the qualification runs of `9a9d627` and `9554d7c`, earlier the same day:

- **Bootstrap** took about 6 minutes. Three `clang -O2` builds of 40 MB of generated C (seed, first generation, second generation) took 81–94 s each, plus three emissions.
- **The suite as one unit** took about 7 minutes, and 90% of it was GCC. About 2,100 native programs each compiled the whole embedded runtime, about 1.1 s each under load, which is 2,267 of 2,511 command-seconds. The Goose compiler took about 200 s for all 8,400 compilations.
- **The suite as three units** took about 12 minutes. It reran every row, Wasm included. Each native program compiled the runtime unit and three program units.
- **Native checks and equivalence** took about 3 minutes, after the rest, one stage at a time.

For one typical 200 KB program, GCC `-O0` took 0.58 s for the whole file. The runtime unit alone took 0.42 s and the program unit alone 0.20 s. Between consecutive batches almost all emitted C is byte-identical: 20 of 7,685 outputs differed for the Wasm root struct batch.

## What changed

- **Cached builds.** `scripts/qualify.py` passes `--native-cache` to both suite passes. The cache was already in `tests/conformance.py`. Builds are content-addressed by the C compiler's identity, its flags and the bytes of their inputs, so a rerun compiles only C that changed. Cases with `native_sources` still rebuild every time.
- **Stable upstream paths.** Upstream sources were extracted into each run's own output directory. Their absolute path is in the emitted C at abort sites, so 935 of 2,118 native builds missed the cache on every run. They now compile from one shared extraction under `build/conformance-upstream/`, keyed by the archive and the standard library. Each program still runs in its own run's copy, so programs that write files cannot interfere across runs.
- **One runtime unit per run.** With `--native-units`, the runtime unit compiles once per runtime text, C compiler, flag and defines, and is cached with the builds. Every program links that object.
- **Native rows only.** The split-unit pass runs only native rows (`--targets native`), and only when native code generation, `native/` or the runner differ from `origin/main`.
- **Reused bootstrap executables.** `bootstrap.py --cache-dir` copies an executable built earlier from identical C, with the same C compiler and command, profile data included. The seed is rebuilt only when it changes.
- **Concurrent stages.** After bootstrap, the two suite passes, native checks, equivalence and unit tests run at once.

## Measurements

`python scripts/qualify.py --output-dir build/qz/{cold,warm} --cache-dir build/qz/cache --baseline <compiler of the same sources>` ran twice in a row. The first run had empty caches, the second reused them. The tree was `9554d7c` plus this change's runner, bootstrap and script edits, with the compiler sources unchanged. Machine: AMD Ryzen 7 3800X, 8 cores / 16 threads. GCC 16.2.1 compiled the conformance C and Clang 23.1.4 the bootstrap C. Load averages were 20–21 during the cold run and 16–21 during the warm one, from the qualification's own concurrent stages.

| Stage | Cold | Warm |
| --- | ---: | ---: |
| Bootstrap `--verify` | 331.5 s | 72.2 s (all three builds reused) |
| Suite, one unit (8,444 rows) | 459.4 s (9 of 2,118 builds reused) | 60.1 s (2,054 reused; the other 64 have `native_sources`) |
| Suite, native rows as three units (4,843 rows) | 536.0 s | 62.3 s (2,074 of 2,138 reused) |
| Native checks (54 steps) | 34.1 s | 30.4 s |
| Equivalence (7,685 outputs, 0 differing) | 192.9 s | 117.1 s |
| Unit tests | 57.1 s | 45.3 s |
| **Total** | **867.6 s** | **189.4 s** |

Both runs passed. The bootstrap reached its fixed point (`0d8a9802…`) and built the same executable (`ca853ebf…`). Both suite passes failed exactly the 92 recorded gaps, and equivalence found no difference from the baseline. [Cold summary](cold-summary.json) · [Warm summary](warm-summary.json)

The earlier conformance-only timings, at load 4–26, were 262 s for one unit cold, 279 s for the native rows as three units cold, and 204 s for one unit when only the local sources hit the cache.

## Limits

- A cold run is still bounded by GCC compiling every native program. The split-unit pass, at 536 s, is the longest stage; it no longer compiles the runtime per program, but it shares the CPUs with the other stages.
- A warm run is now bounded by equivalence, which runs both compilers on every output, and by bootstrap's emissions: about 37 s for the seed's and 24 s for each later generation.
- The seed is snapshot 61, whose C carries no unit marks, so bootstrap cannot split its first-generation build yet.
