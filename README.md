# Goose to Wasm

A [Goose](https://github.com/aardappel/goose) compiler written entirely in Goose. It emits WebAssembly directly and uses native C as a portable bootstrap backend. **Conformance is partial: 100 of 7,787 contract rows fail.**

## Benchmarks

**Langbench Mandelbrot · 2026-11-07.** On the official single-thread input, median timed computation for the same Goose port was 2.50 s native, 37.96 s in Wasmtime and 54.78 s in V8. The local trial also compares upstream Goose native and C. [Results and method](bench/results/2026-11-07/langbench-trial/README.md)

![Langbench Mandelbrot timed computation](bench/charts/langbench-runtime.svg)

![Langbench Mandelbrot workload build times](bench/charts/langbench-compilation.svg)

The upstream C workload includes thread setup and a row queue; the Goose port is scalar. V8 uses default tiering; this is not warmed throughput. This shared-host trial covers one workload, not the standard Docker campaign; small differences are inconclusive.

**2026-11-07 · AMD Ryzen 7 3800X pinned to CPU 7 · lower is better.** Five-sample medians for ten examples using snapshot 56. Cold direct Wasm builds took 50.9–137.2 ms; native C builds took 263.6–1853.6 ms. [Results and method](bench/results/2026-11-07/lifetime-containment-index/README.md)

![Goose compiler cold build times for ten examples](bench/charts/goose-examples-compilation.svg)

Runtime measures process launch through exit, including startup and output. The panels compare compilation on launch, full precompiled Wasmtime, and minimal AOT. Preparation is measured separately.

![Goose example process times by runtime mode](bench/charts/goose-examples-runtime.svg)

![Wasmtime preparation times for ten examples](bench/charts/goose-host-preparation.svg)

Sorting took 172.7 ms with minimal AOT and 119.3 ms natively. Paired comparisons with snapshot 55 remain in the [dated evidence](bench/results/2026-11-07/lifetime-containment-index/README.md).

## Construction and contracts

The compiler implements loading, parsing, checking, specialization, optimization and code generation in Goose. Bootstrap builds a frozen C seed with a native C compiler, then uses it to build the compiler. Snapshot 56 passed C-only fixed-point verification; its final two generated C outputs match.

With Python 3, a native C compiler and Node for Wasm execution:

```sh
python3 scripts/bootstrap.py --verify
python3 scripts/goose_wasm.py build examples/squares.goose -o build/squares.wasm
node scripts/run_wasm.mjs build/squares.wasm
```

Snapshot 56 passed 7,687 of 7,787 frozen source and output contracts; 100 failed. Against snapshot 55, 0 of 7,779 prior checks improved and none regressed. All 8 new source-authored checks passed. The curated Wasm corpus passed 3,286/3,286 checks each in Wasmtime and V8; all 1,410 curated native controls also passed. The remaining failures are 6 accepted invalid programs and 94 runtime contracts rejected during Goose compilation. All selected runtime checks that reached execution passed. Conformance and bootstrap used no C++ oracle. [Qualification](selfhost/results/2026-11-07/lifetime-containment-index/summary.json)

[Compiler and bootstrap](selfhost/README.md) · [Guide](docs/GUIDE.md) · [Examples](examples/README.md) · [Conformance runner](tests/conformance.py)
