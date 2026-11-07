# Goose to Wasm

A [Goose](https://github.com/aardappel/goose) compiler written entirely in Goose. It emits WebAssembly directly and uses native C as a portable bootstrap backend. **Conformance is partial: 112 of 7,371 contract rows fail.**

## Benchmarks

**2026-11-07 · AMD Ryzen 7 3800X pinned to CPU 7 · lower is better.** Five-sample medians for ten examples using snapshot 50. Cold direct Wasm builds took 52.8–139.1 ms; native C builds took 264.2–1950.1 ms. [Results and method](bench/results/2026-11-07/plain-values-and-forwarded-views/README.md)

![Goose compiler cold build times for ten examples](bench/charts/goose-examples-compilation.svg)

Runtime measures process launch through exit, including startup and output. The panels compare compilation on launch, full precompiled Wasmtime, and minimal AOT. Preparation is measured separately.

![Goose example process times by runtime mode](bench/charts/goose-examples-runtime.svg)

![Wasmtime preparation times for ten examples](bench/charts/goose-host-preparation.svg)

Sorting took 167.1 ms with minimal AOT and 116.2 ms natively. An interleaved direct-build check gave snapshot 50/49 ratios of 0.993–1.005, with a median workload ratio of 1.000. The higher cold-build numbers in the separate full cohort did not reproduce in that paired check. No matched runtime speedup is claimed.

## Construction and contracts

The compiler implements loading, parsing, checking, specialization, optimization and code generation in Goose. Bootstrap builds a frozen C seed with a native C compiler, then uses it to build the compiler. Snapshot 50 passed C-only fixed-point verification; its final two generated C outputs match.

With Python 3, a native C compiler and Node for Wasm execution:

```sh
python3 scripts/bootstrap.py --verify
python3 scripts/goose_wasm.py build examples/squares.goose -o build/squares.wasm
node scripts/run_wasm.mjs build/squares.wasm
```

Snapshot 50 passed 7,259 of 7,371 frozen source and output contracts; 112 failed. Against snapshot 49, 2 of 7,235 shared checks improved and none regressed. All 136 new source-authored checks passed. The curated Wasm corpus passed 3,078/3,078 checks each in Wasmtime and V8; all 1,202 curated native controls also passed. The remaining failures are 6 accepted invalid programs and 106 runtime contracts rejected during Goose compilation. Every runtime check that reached execution passed. No C++ oracle was executed. [Qualification](selfhost/results/2026-11-07/plain-values-and-forwarded-views/summary.json)

[Compiler and bootstrap](selfhost/README.md) · [Guide](docs/GUIDE.md) · [Examples](examples/README.md) · [Conformance runner](tests/conformance.py)
