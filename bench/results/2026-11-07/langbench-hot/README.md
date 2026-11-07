# Langbench Mandelbrot resident execution · 2026-11-07

This local single-thread trial reuses the exact artifacts and snapshot 56 compiler from the [original trial](../langbench-trial/README.md), including direct Wasm artifact `b2338da428272b85fc4425bc24b9a0e80976530c25e8281fe85d53c49070fb76`. It covers one pinned langbench workload, not the standard Docker campaign. At the official 2048×2048, 1000-iteration input, median timed computation for the same Goose port was **2.42 s** native, **35.21 s** in Wasmtime and **42.54 s** in V8.

| Input | Backend | Kernel, ms (median ± MAD) | Request/process wall, ms (median) |
| --- | --- | ---: | ---: |
| 512² × 500 | C · GCC | 76.8 ± 0.1 | 77.9 |
| 512² × 500 | C · Clang | 82.7 ± 0.0 | 83.8 |
| 512² × 500 | Upstream Goose → GCC | 76.7 ± 0.1 | 78.1 |
| 512² × 500 | This compiler → GCC | 78.3 ± 0.1 | 79.8 |
| 512² × 500 | Resident Wasmtime | 1,129.0 ± 0.1 | 1,130.0 |
| 512² × 500 | Resident V8 | 1,365.8 ± 2.4 | 1,366.4 |
| 1024² × 1000 | C · GCC | 601.3 ± 1.2 | 602.6 |
| 1024² × 1000 | C · Clang | 649.0 ± 3.6 | 650.1 |
| 1024² × 1000 | Upstream Goose → GCC | 602.0 ± 0.7 | 603.2 |
| 1024² × 1000 | This compiler → GCC | 603.9 ± 0.3 | 605.5 |
| 1024² × 1000 | Resident Wasmtime | 8,803.0 ± 17.7 | 8,804.0 |
| 1024² × 1000 | Resident V8 | 10,653.6 ± 37.3 | 10,654.1 |
| 2048² × 1000 | C · GCC | 2,417.1 ± 6.8 | 2,418.5 |
| 2048² × 1000 | C · Clang | 2,603.7 ± 10.1 | 2,605.1 |
| 2048² × 1000 | Upstream Goose → GCC | 2,418.6 ± 2.4 | 2,419.9 |
| 2048² × 1000 | This compiler → GCC | 2,421.8 ± 8.1 | 2,423.3 |
| 2048² × 1000 | Resident Wasmtime | 35,206.5 ± 31.7 | 35,207.5 |
| 2048² × 1000 | Resident V8 | 42,542.7 ± 89.2 | 42,543.2 |

All **144 execution checks passed**: 126 measurements and 18 discarded warmups across 18 cells. The 20 focused tests passed. Wasmtime used PID `1684258` for every request, with one module compilation and one deserialization. V8 used PID `1684374` and one module construction; its optimization tier was not explicitly verified.

The compiler remains snapshot 56, SHA-256 `febb9bcacc2346ad0eb96daec2126cce74d23efc07a4bfe249f97aae068ef088`. Wasm and native executable hashes match the frozen reference; no workloads were rebuilt. Active runtimes were Wasmtime 50.0.1, Node 24.22.1 and V8 13.6.233.17-node.58; executable/library hashes, inherited flags and commands are in the report. SMT sibling CPU 15 was busy for 0.1% of this run. These are separately collected cohorts, so differences from the original trial are not a paired compiler speedup. The unchanged Wasm still has the [scalar storage and resolver overhead identified earlier](../langbench-trial/inspection-review.md).

| One-time module preparation, before warmup | Milliseconds |
| --- | ---: |
| Wasmtime engine creation | 0.168 |
| Wasmtime module compilation | 5.631 |
| Wasmtime serialization | 0.046 |
| Wasmtime artifact write/read/hash verification | 0.109 |
| Wasmtime deserialization | 0.063 |
| V8 initial module construction | 0.834 |

These module preparation intervals exclude host process startup; none enter the kernel score.

Wasmtime compiles and serializes a local trusted module, verifies and deserializes it once before warmup, and reuses it in a resident Python engine. Each request receives a fresh store, instance and imports outside the timed region. A persistent Node process constructs one WebAssembly module and warms functions using default V8 tiering, with a fresh instance per request. Native controls use fresh processes and their internal clocks. One full-kernel warmup per cell and profile (18 total) precedes seven interleaved measurements per cell and profile; all outputs are checked.

The source-level timer excludes engine compilation, startup, instantiation, input, output and IPC. Request wall time is reported separately and does not mean process launch through exit for resident engines. The original fresh-process computation timer also excluded preparation, so a change in timed results cannot be explained simply as removing startup. V8 tiering may continue as functions run; an active call does not necessarily switch to optimized code.

The C workload includes pthread spawn/join and an atomic row queue; the Goose port is scalar. The closest comparison is within the Goose group. This run used CPU 7 on a Ryzen 7 3800X, with SMT sibling 15 and the schedutil governor on a shared host; background load and frequency changes limit small comparisons. The original trial's five-sample workload build timings are a separately collected reference; no builds are measured here. Artifacts and runtime identities are machine-specific; on another environment, build a new qualified reference rather than assume the archived native code or Python hash is portable.

[Report](report.json) · [Metrics](metrics.json) · [Validation](validation.json) · [Chart verification](chart-verification.json) · [Reproduction archive](reproduction.tar.gz) · [Guide and reproduction](../../../langbench/README.md) · [Supplementary review](review.md)
