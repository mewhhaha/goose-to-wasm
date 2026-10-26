# LangArena measurements — 2026-10-26

**All measured executions and source-edit checks passed.** The complete original 50-task Goose application passes both official input profiles on native C. Seven explicitly adapted workloads pass both profiles on native C, C-Wasm/V8, C-Wasm/Wasmtime, direct Wasm/V8, and direct Wasm/Wasmtime. The original whole application remains unavailable on both Wasm profiles: its direct build reaches unsupported dynamic storage, and its C-Wasm build reaches unsupported threads/typed queues. These refusals receive no successful compile-time score.

This is a local comparison of our compiler backends, not a LangArena leaderboard result. Fannkuch preserves its original fixed-array kernel. The other six ports replace growable storage with disclosed bounded backing arrays; all three backends compile the identical adapted source. Official production inputs, iteration counts, warmup state, RNG behavior, and expected checksums are retained. The original and adapted tracks must not be mixed.

## Environment and evidence

- Machine: AMD EPYC 9V74 KVM guest, 9 logical CPUs, 9.7 GiB RAM.
- Goose source pin: `2e2bedef5b980bf013cac5aaa0095bfea64e5569`.
- LangArena pin: `aab9b14998231ba905523b5ba3990ee03c46f64d`.
- GCC 13.3.0; Emscripten 6.0.13; Node 24.22.1 / V8 13.6.233.17-node.58; Wasmtime 50.0.1.
- Native and both Wasm paths use Goose O2. Native/C-Wasm additionally use their C compiler O2. Floating contraction is disabled. Direct uses memory32; the standalone C oracle uses LP64 memory64.
- Measured compiler SHA-256: `ec5eee733cff680e730a7ff6e7b1fc80aabe868b0140c9bc696cbfc5bef75060`.
- Three complete build samples and three production runtime samples per supported cell, with deterministically shuffled order and no competing benchmark/build work. These are preliminary medians from a VM; raw samples, MAD, quartiles, commands, tool versions, environment overrides, source hashes, and artifact hashes are retained.
- Final run: `2026-10-26T12:35:50.893528+00:00` to `2026-10-26T12:46:47.317976+00:00`; 582 observations: 132 successful builds, 448 successful executions, and 2 explicit whole-suite refusals. Source, compiler, and standard-library hashes stayed unchanged.
- A separate correctness pass completed 194 observations: 22 successful builds, 170 successful executions, and the same 2 explicit whole-suite refusals.

## Compilation

Values below are **milliseconds**, shown as **cold build / observable source-edit rebuild**. Both phases launch fresh driver/compiler processes with `--no-cache`; times include the Python wrapper, frontend, code generation, and any C compiler/linker. Installed dependencies and OS/system-library caches are retained.

| Adapted workload | C → native | C → Wasm | Direct Wasm |
| --- | ---: | ---: | ---: |
| Fannkuch | 380.8 / 335.5 | 860.5 / 624.6 | 73.2 / 63.0 |
| Mandelbrot | 436.7 / 310.7 | 937.5 / 725.0 | 83.2 / 71.4 |
| Sieve | 345.3 / 298.6 | 824.4 / 667.9 | 84.5 / 75.2 |
| CRC32 | 328.2 / 281.0 | 724.5 / 634.3 | 85.8 / 60.6 |
| Custom hash¹ | 372.0 / 415.9 | 764.4 / 650.6 | 74.5 / 64.5 |
| Merge sort | 398.0 / 347.1 | 836.6 / 650.4 | 93.9 / 76.7 |
| Quick sort | 414.3 / 313.7 | 1074.9 / 646.3 | 80.8 / 73.7 |

Direct cold builds were **8.4–13.3× faster than C-to-Wasm** for these same seven compilation units. This is not an estimate for compiling the full 50-task application.

| Original whole 50-task application | Cold build | Source-edit rebuild |
| --- | ---: | ---: |
| C → native | 10.380 s | 9.025 s |
| C → Wasm | Refused: reachable threads/typed queues | Unavailable |
| Direct Wasm | Refused: dynamic storage | Unavailable |

Every edit changes reachable program behavior. Port revisions change the final exit status from 0 to 1 while retaining the official checksum. The original application writes a changed marker string into an isolated file. All **66 edited builds** changed artifact bytes and all **108 edited-artifact executions** verified the changed behavior. Source bytes were restored afterward.

**Edited programs still rerun the complete frontend and emitter.** There is no function-level incremental reuse in these measurements, and no unchanged cache hit is counted as an edit. The marker phase follows the runtime phase; differences from cold-build times can reflect cache warmth, CPU/VM conditions, and noise. The lower edit medians do not establish incremental compilation.

## Execution

Values are **seconds for each workload’s full configured measured iteration count**, excluding preparation and official warmups. They are not single-kernel-call times. Checksums retain the original cumulative warmup state. The full report also records engine compilation/instantiation, entry-function time, and process wall time.

| Adapted workload | Native C | C-Wasm / V8 | C-Wasm / Wasmtime | Direct / V8 | Direct / Wasmtime |
| --- | ---: | ---: | ---: | ---: | ---: |
| Fannkuch | 1.6594 | 2.3689 | 1.5687 | 1.4753 | 1.5973 |
| Mandelbrot | 1.2398 | 1.2732 | 1.3235 | 1.2500 | 1.1482 |
| Sieve | 1.5268 | 3.0162 | 1.8401 | 8.3569 | 2.1423 |
| CRC32 | 1.4812 | 0.4410 | 0.4684 | 8.5592 | 5.0441 |
| Custom hash¹ | 0.6216 | 1.1842 | 1.3707 | 7.9693 | 2.0866 |
| Merge sort | 1.9221 | 1.5992 | 2.4800 | 2.4128 | 2.2905 |
| Quick sort | 1.4928 | 1.5616 | 1.7436 | 1.5990 | 1.8793 |

¹ LangArena names this task `Hash::SHA256`, but its preserved algorithm is a custom eight-lane hash, not standard cryptographic SHA-256.

The direct backend is close to the reference paths on Fannkuch, Mandelbrot, and quicksort. CRC32 and the custom hash have substantial direct-backend gaps; sieve also shows a large difference between V8 and Wasmtime. These measurements identify where profiling and generated-code analysis should go next. They do not identify the responsible optimization pass by themselves.

All 50 original native tasks passed three production samples each; their individual medians and dispersion are in the full report. The sum of their individual medians is 58.860 seconds. That sum is descriptive only and is not a LangArena rank or a cross-backend score.

## Module size and startup

Direct modules currently materialize the ports’ large zero-initialized global arrays in data segments. The Fannkuch module is 4,029 bytes; the other six direct modules range from 1,003,420 to 4,806,807 bytes. Corresponding C-Wasm modules range from 51,597 to 52,484 bytes. These are uncompressed artifact sizes. This representation cost is visible in the reported artifact sizes and separate startup measurements; shrinking zero-filled data segments is a concrete follow-up independent of algorithm optimization.

## Reproduce and inspect

```sh
python bench/langarena.py fetch
python tests/test_langarena.py
python bench/langarena.py check --profiles test run --skip-edits \
  --emcc /path/to/emcc --output-dir build/langarena-qualification
python bench/langarena.py measure --emcc /path/to/emcc \
  --machine-label "observed machine description"
```

- [Complete measurement tables](report.md)
- [Raw measurement observations and identities](report.json)
- [Separate full-input checksum qualification](qualification.json)
- [Per-command logs, driver statistics, and engine timing records](raw-logs.tar.gz)
- [Harness, adaptations, and measurement contract](../../../langarena/README.md)
- [Fibonacci optimization follow-up](../fibonacci-followup/README.md)

The upstream configuration and adapted kernels retain the [LangArena MIT notice](../../../langarena/UPSTREAM_LICENSE). The compiler and upstream Goose source retain their corresponding repository licenses.
