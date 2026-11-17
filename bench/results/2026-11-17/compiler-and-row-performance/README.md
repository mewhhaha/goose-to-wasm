# Compiler and native row performance · 2026-11-17

## Lifetime analysis

The checker reuses the reach it computed while recording an effect when stamping the associated read. Array shrink checks dispatch directly to the array handler, and construct-read validation scans the held values that can conflict with a replacement.

Seven paired self-checks took **3.131 → 3.054 s CPU** at the median, 2.4% less. Every pair favored the candidate. Both development builds used Clang 23.1.5 `-std=gnu11 -O2`, eight C units and no profile. They checked the same compiler sources frozen at `90d4d19` on CPU 7. [Raw pairs](runs/lifetime-timing.json) · [Parent build](runs/lifetime-parent-build.json) · [Candidate build](runs/lifetime-candidate-build.json)

The independently instrumented builds produced identical state at every pass boundary in the self-check and across 4,355 corpus inputs, including 11,589 fingerprint records. The frozen Blot2 input exercised the class-keyed analysis at its ordinary threshold. Its state records, exit and 38 diagnostics matched. [Corpus summary](runs/lifetime-corpus.json) · [Self-check](runs/lifetime-selfcheck.txt) · [Blot2](runs/lifetime-blot2.txt) · [Proof identities](runs/lifetime-state-proof.json)

The current parent profile puts 88% of self-check samples in lifetime analysis. Effect reach was 5.9% and array shrink was 3.7%. The Wasm emission profile assigned 10.8% to local reuse. [Self-check profile](runs/parent-check-profile.txt) · [Wasm profile](runs/parent-wasm-profile.txt)

## Compiler construction

With both native executables cached, the opt-in local bootstrap took **36.19 → 8.42 s wall** across three interleaved pairs on an edited source. It verifies its starting executable's checksum, builds the result and exercises the new compiler for the fixed point. [Options, measurements and controls](../local-bootstrap/README.md)

## Wasm local allocation

The allocator remembers the busy prefix for each Wasm local type until a slot in that prefix is free. It still chooses the first eligible slot. Replaying optimized self-compilation bodies took **543 → 491 ms**, and the overlapping-span stress case took **241 → 31 ms**. Local tables and instruction bytes matched throughout. The tiny-body control added about 70 ns per call. [Allocation replay and rejected alternative](../wasm-slot-prefix/README.md)

## Native rows

Stable native row scans validate the committed run once and carry a byte cursor. Counted loops that append a single independently constructed record validate the existing prefix on entry and check each finished row before publishing it. Both changes preserve the bounded image layout. [Paired timings and runtime controls](../native-row-scans/README.md)

## Release measurements

The release parent (`94c6428f4d20…`, from `90d4d19`) and candidate (`6dc908de22b4…`) used Clang 23.1.5 `-O2`, one C unit and no profile. Across eleven programs, the geometric means of candidate/parent median CPU time were **1.000× for direct Wasm** and **0.992× for C emission**. All 44 cells passed output validation after 31 paired rounds on CPU 7. [Compiler samples](compiler-comparison.json) · [Chart data](runs/compiler-chart.json) · [Release identity](runs/bootstrap.json)

The five-pair release self-compile measured 3.36 → 3.66 s CPU for check, 5.67 → 5.44 s for Wasm and 4.75 → 4.97 s for C. The two self-emission artifacts were byte-identical. Check ratios ranged from 0.86× to 1.11× under contention. In nine fresh pairs on CPU 5, check medians were **3.240 → 3.236 s**. These runs establish a flat release self-check within the spread. [Release samples](runs/self-compile.json) · [Check replicate](runs/self-check-replicate.json)

The ten-example refresh used five complete builds and five process samples per cell on CPU 6, with Wasmtime 50.0.1. The Mandelbrot complete-build chart uses this compiler. Its artifacts matched all 30 preceding builds, preserving the separately collected resident runtime measurements. [Examples](examples.json) · [Wasmtime host](host.json) · [Mandelbrot builds](langbench-build.json) · [Artifact match](runs/langbench-artifacts.json) · [Resident measurements](../compiler-iteration/langbench-hot.json)

## Qualification

The release compiler reached a C fixed point. The default, memory64 and split-native suites passed 10,689/10,793, 4,765/4,773 and 5,924/6,020 rows respectively, matching the recorded gaps. The first default run timed out on the upstream level-zero sort. Its C matched the parent's, and it passed a focused replay at 15 s and a full replay with a 30 s limit. The native runtime passed 54 steps. The unit suite ran 79 tests with one optional host skip, and the bounded-row regression passed separately. [Initial qualification](runs/qualification-first.json) · [Focused sort replay](runs/sort-retry.txt) · [Full replay](runs/conformance-retry.txt) · [Unit tests](runs/unit-tests.txt)

Of the 10,049 compiler outputs compared, 26 native artifacts changed. The isolated row compiler reproduced every change, including the exact C used in the paired row measurements. The local bootstrap route also produced the canonical release executable and passed a live fixed-point check. [Artifact comparison](../native-row-scans/equivalence.json) · [Local bootstrap receipt](runs/reused-toolchain.json)
