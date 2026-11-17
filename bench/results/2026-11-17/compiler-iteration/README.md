# Compiler iteration · 2026-11-17

## Building the compiler

Warm verified bootstrap took **52.05 → 5.80 s wall** and **50.18 → 5.50 s CPU**, medians of three interleaved pairs on CPU 2. Both arms used the same Clang 23.1.5 `-O2` recipe and already had both native executables cached. The workload was the compiler source at `9551a58`. The new cache reused the first emission from the seed and ran the built compiler for the fixed-point check every time. Generated C and the release executable matched byte for byte. [Samples](runs/bootstrap-warm.json) · [Reproduction](tools/bootstrap.md)

Clang took 197 s to build the release candidate from emitted C during qualification. A separate cold-seed experiment used three units for the intermediate seed while reusing the final release executable in both arms. Its single run took 121 s versus 189 s wall and used 16% more CPU under different host load. Release construction uses one unit. [Cold-seed experiment](runs/bootstrap-cold-probe.json)

## Compiling programs

Both backends build one symbol-owner index per program, in symbol order. The Wasm emitter reuses its slot table and visits only assigned frame addresses in each prelude. The C emitter visits the current function's symbols for local declarations and cleanup, and checks for self-relative runs once per module.

| Eleven programs, candidate / parent | Median CPU geomean | Median wall geomean |
| --- | ---: | ---: |
| Direct Wasm | 0.969× | 0.926× |
| C emission | 0.973× | 0.969× |

Both compilers were built with Clang 23.1.5 `-std=gnu11 -O2` in one unit without a profile. The parent was `9551a58` (`e5cf838d7572985a3…`), and the candidate was the [qualified bootstrap](runs/bootstrap.json) (`94c6428f4d203a2c…`). Each cell had 31 balanced, shuffled measurements on logical CPU 7 after warmup. Timings end when Goose writes the artifact. Golden-output validation ran afterwards, with 44 of 44 cells passing. All 22 CPU time medians fell. Wall times varied more on the shared host, with the largest increase on sudoku C emission (13% wall, 1.3% less CPU). [Samples](compiler-comparison.json) · [Chart data](runs/compiler-chart.json)

Five interleaved pairs on CPU 7 compiled the frozen `9551a58` compiler sources with matching options and identical outputs. Phase times are wall medians. Both sides ran on an active shared host. [Samples](runs/self-compile.json) · [Timer](tools/measure-selfhost.py)

| Self-compilation | CPU before → after | Backend wall before → after |
| --- | ---: | ---: |
| Check | 4.60 → 4.78 s | |
| Direct Wasm | 11.55 → 8.64 s | 6.30 → 3.84 s |
| C emission | 7.64 → 6.69 s | 2.53 → 1.54 s |

Paired self-check CPU ratios ranged from 0.88× to 1.08×. Every emission pair favored the candidate.

## Running emitted Wasm

Stable varint loops carry a byte cursor across iterations. The former prefix walk decoded the first `i` elements to reach element `i`. The final proof covers top-level reductions on immutable incoming slice parameters. The timing, deterministic fuel counts, memory32 and memory64 coverage, and mutation and aliasing controls are in the [varint run](../varint-foreach/README.md).

## Examples and Mandelbrot

The ten examples ran on CPU 6 with five complete builds and five full-process samples per cell. The host preparation and AOT timings use separately built full and minimal Wasmtime 50.0.1 hosts. The emitted examples matched the parent byte for byte at both Wasm widths. [Examples](examples.json) · [Wasmtime host](host.json) · [Artifact controls](../varint-foreach/controls.json)

The independent Mandelbrot run used seven resident samples per cell and checked every checksum. The runtime cohort used artifacts with identical hashes to all 30 final-candidate build samples. The complete build chart uses the final compiler; the runtime chart uses the separately timed instances. [Complete builds](langbench-build.json) · [Resident run](langbench-hot.json) · [Identity proof](runs/langbench-artifacts.json)

## Qualification

The release compiler reached a C fixed point. Conformance passed 10,689 of 10,793 default rows and 4,765 of 4,773 memory64 rows. Native runtime checks passed all 54 steps. The initial three-unit native run timed out once on the upstream sort at level zero. Its emitted C matched the parent's. The focused retry passed both levels with the original 15 s limit. The full split-unit retry used a 30 s per-program limit and passed 5,924 of 6,020 rows, exactly the recorded gaps.

Output comparison covered 10,049 cases. The 10 differing outputs were Wasm artifacts and matched the isolated cursor change. The unit suite ran 76 tests with one optional host skip. The final focused suite passed all five loop tests, including the alias regression and the load-independent fuel bound. [Initial qualification](runs/qualification-first.json) · [Sort retry](runs/sort-retry.json) · [Full native retry](runs/native-units-retry.txt) · [Unit tests](runs/unit-tests.txt) · [Loop tests](runs/loop-ordinals.txt) · [Wasm equivalence](../varint-foreach/README.md)

## Experiments

- A preorder index for lifetime scope lookups had paired self-check CPU ratios of 1.000, 1.074 and 0.935. The shipped checker keeps the existing scope walk. [Trial](runs/initial-emitter-trial.json) · [Patch](tools/scope-ranges.patch.gz)
- Buffering only relevant Wasm instructions during local reuse did not improve whole-compile time. Streaming liveness saved a median 150 ms in the backend across five pairs, with flat end-to-end CPU and noisy controls. Both variants kept their outputs byte-identical. [Trials](runs/local-reuse-trials.json) · [Filtered patch](tools/filtered.patch) · [Streaming patch](tools/streaming.patch)

The parent profile puts 87% of sampled self-check time in lifetime analysis, led by body evaluation and effect replay. Cold native build time is concentrated in downstream C optimization. Varint loops with changing inputs still rewalk their prefixes. [Self-check profile](runs/parent-check-profile.txt) · [Wasm profile](runs/parent-wasm-profile.txt) · [C profile](runs/parent-c-profile.txt)
