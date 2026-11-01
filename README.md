# Goose to Wasm

Compile [Goose](https://github.com/aardappel/goose) directly to WebAssembly for V8 and Wasmtime. The backend reuses Goose’s frontend and emits Wasm binaries without generating C or invoking LLVM. It supports a [defined subset](docs/TARGET.md) of Goose; unsupported programs fail to compile.

[Setup and guide](docs/GUIDE.md#quick-start-direct-compilation) · [Examples](examples/README.md) · [Next hills](docs/PERFORMANCE_PLAN.md)

## Benchmarks

**2026-11-01 · AMD Ryzen 7 3800X · lower is better.** Medians from five samples per cell, using seven adapted LangArena workloads. Six replace growable storage with bounded arrays; each backend compiles the same adapted source. These are not results for the full 50-task suite. Direct Wasm uses memory32; C-to-Wasm uses memory64.

![Cold build times by workload and backend](bench/charts/compilation.svg)

Complete uncached builds include Python driver startup. Direct builds took 73–82 ms, 8.0–9.0× faster than C-to-Wasm on these inputs.

![Runtime by workload, backend, and engine](bench/charts/runtime.svg)

Seconds per configured measured iteration count, excluding preparation, warmups, and startup. Runtime varies by workload and engine: direct Wasm trails C-to-Wasm on CRC32 and is close on custom hash.

[Full results and raw samples](bench/results/2026-11-01/lanes/README.md) · [Benchmark method](bench/langarena/README.md)

## How it was built

The direct backend is developed against Goose’s C backend as an oracle. Differential tests compile the same programs through direct Wasm, C-to-Wasm, and native C, then compare output, exit status, diagnostics, and independently calculated answers. Both Wasm paths run on V8 and Wasmtime. The [guide](docs/GUIDE.md#correctness-qualification) covers the tests and their limits.
