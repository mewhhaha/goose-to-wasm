# Lifetime exit lookup · 2026-11-18

The lifetime checker used to scan every recorded exit to find one for the active frame. Each appended exit now links into the head of its frame’s list. A lookup walks only that frame’s exits and checks the node before loading the value. Each frame and target node has at most one entry. A break looks up its target again after evaluating its operand. [Source](../../../../selfhost/checker_lifetimes.goose#L3892)

## Same-workload measurements

The comparison builds compiler sources `f89ecf3` and `ba9dece` and runs both on the same frozen `f89ecf3` project. The memory32 modules use the same region profile collected on that project. Wasmtime 50.0.1 prepares the modules before timing `_start`. The native binaries use Clang 23.1.5 `-O2` with eight program units. [Region profile](regions.txt) · [Wasm comparison](paired-wasm.json) · [Matched native and memory32](matched.json)

| Workload | Wasmtime memory32 instructions | Wasmtime memory64 instructions |
| --- | ---: | ---: |
| Self-check | 75.97 → 71.07 B (−6.5%) | 94.02 → 89.40 B (−4.9%) |
| Self-compile | 122.22 → 117.32 B (−4.0%) | 147.96 → 143.34 B (−3.1%) |

These are medians of two opposite-order pairs on CPU 6 under shared load. Every self-compilation reproduced the same frozen module.

On CPU 5, two further rounds compared the memory32 module with the optimized native build of the same compiler source. Native check instructions fell 3.7% and self-compile instructions fell 2.3% versus the parent native build.

| Workload | Optimized native | Profiled memory32 | Wasmtime/native |
| --- | ---: | ---: | ---: |
| Self-check | 3.48 s | 10.86 s | 3.12× |
| Self-compile | 4.89 s | 15.88 s | 3.25× |

The self-check pairs ranged from 2.95× to 3.32× under shared load. The medians put both workloads above the 3× target.

## Qualification

The state comparison matched 11,593 lifetime fingerprints across 4,356 corpus sources, and all eight fingerprints through validation on the frozen self-check. It includes the owning frame, node, destination, selected result and value of each exit in append order. The candidate checks that each entry has one owner, a valid backward link and a unique node in its frame. A 96-exit case exercised class-keyed frames at threshold 64. The native development probe reached its timeout on self-check. The completed self-check proof used both memory64 modules in V8. [Corpus proof](corpus-state-proof.json) · [Self-check and early-class proof](state-proof.json)

The release reached its C bootstrap fixed point and matched all 10,053 compiler outputs. The initial default suite timed out on the level-zero upstream sort after 15 seconds. Its C matched the parent’s byte for byte. Both sort levels passed a focused replay, and a full replay at 30 seconds passed 10,691 of 10,795 rows with the recorded gaps. Memory64 passed 4,767 of 4,775 with the recorded gaps. The native runtime passed all 54 checks, and the unit suite ran 80 tests with one optional skip. [Bootstrap](bootstrap.json) · [Initial qualification](qualification.json) · [Output comparison](equivalence.json) · [Replay results](replays.json)

## README benchmarks

The self-hosting chart measures the release compiler on its own sources at `ba9dece`. Native builds use eight C program units on CPUs 0, 1 and 4–6. Execution uses CPU 5. The two pinned upstream compilers each reported 31 lifetime errors on the frozen sources. The chart’s native control is this compiler’s C backend. [Self-hosting samples](measurements.json) · [Chart values](selfhost-chart.json) · [Upstream attempts](upstream-native.json)

The eleven-program catalog used 31 paired samples per cell on CPU 1. The candidate took 0.998× the parent’s CPU time for Wasm emission and 1.006× for C, with byte-identical artifacts in all 22 workload and target pairs. The refreshed example and host charts use CPU 1. All 30 Mandelbrot builds reproduced their previous artifacts, and their executables and modules match the separate resident run. [Compiler catalog](compiler-comparison.json) · [Examples](examples.json) · [Wasmtime host](host.json) · [Mandelbrot artifact proof](langbench-artifacts.json)

## Replay

Use the `f89ecf3` release executable as the starting emitter (SHA-256 `18b8113e3fc91d038882cdad8ab4b2e98971474f285f2dacc6756c047ceeb14d`). Compile both frozen compiler trees with `--target wasm-direct -O2`. Use `--wasm-memory64 --wasm-max-pages 262144` for the wide modules and `--wasm-max-pages 65535 --wasm-region-profile regions.txt` for the profiled modules. The native control uses `scripts/goose_wasm.py build --backend native --jobs 8 --no-cache --cc clang-23 -O2`. The sampler entry points expect these artifacts in their documented build directories and execute the same `f89ecf3` input. [Wasm sampler](tools/samples.py) · [Matched sampler](tools/match.py) · [Exit fingerprint extension](tools/exitfp.py)
