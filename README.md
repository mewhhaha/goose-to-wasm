# Goose to Wasm

A [Goose](https://github.com/aardappel/goose) compiler written entirely in Goose. It emits WebAssembly directly and uses native C as a portable bootstrap backend. **Conformance is partial: 102 of 7,711 contract rows fail.**

## Benchmarks

**2026-11-07 · AMD Ryzen 7 3800X pinned to CPU 7 · lower is better.** Five-sample medians for ten examples using snapshot 54. Cold direct Wasm builds took 51.9–137.5 ms; native C builds took 250.7–1944.0 ms. [Results and method](bench/results/2026-11-07/temporary-region-retirement/README.md)

![Goose compiler cold build times for ten examples](bench/charts/goose-examples-compilation.svg)

Repeated 10,000-iteration temporary workloads, including str and to_bytes, now fit the same two-page Wasm limit. Thirty-two scalar startup initializers reuse one region instead of 33; an 8,192-byte main temporary then fits without increasing the limit. The guards also preserve live global owners and views and still reject a live value larger than the limit.

Runtime measures process launch through exit, including startup and output. The panels compare compilation on launch, full precompiled Wasmtime, and minimal AOT. Preparation is measured separately.

![Goose example process times by runtime mode](bench/charts/goose-examples-runtime.svg)

![Wasmtime preparation times for ten examples](bench/charts/goose-host-preparation.svg)

Sorting took 167.2 ms with minimal AOT and 115.4 ms natively. Paired minimal AOT process ratios versus snapshot 53 ranged 0.984–1.015, with a median workload ratio of 1.002; the native-control median was 1.003. These measurements do not establish a broad runtime speedup.

## Construction and contracts

The compiler implements loading, parsing, checking, specialization, optimization and code generation in Goose. Bootstrap builds a frozen C seed with a native C compiler, then uses it to build the compiler. Snapshot 54 passed C-only fixed-point verification; its final two generated C outputs match.

With Python 3, a native C compiler and Node for Wasm execution:

```sh
python3 scripts/bootstrap.py --verify
python3 scripts/goose_wasm.py build examples/squares.goose -o build/squares.wasm
node scripts/run_wasm.mjs build/squares.wasm
```

Snapshot 54 passed 7,609 of 7,711 frozen source and output contracts; 102 failed. All 7,595 prior checks retained their outcomes. All 116 new source-authored checks passed; these include bounded-memory contracts rather than recovered original-suite failures. The curated Wasm corpus passed 3,248/3,248 checks each in Wasmtime and V8; all 1,372 curated native controls also passed. The remaining failures are 6 accepted invalid programs and 96 runtime contracts rejected during Goose compilation. All selected runtime checks that reached execution passed. No C++ oracle was executed. [Qualification](selfhost/results/2026-11-07/temporary-region-retirement/summary.json)

[Compiler and bootstrap](selfhost/README.md) · [Guide](docs/GUIDE.md) · [Examples](examples/README.md) · [Conformance runner](tests/conformance.py)
