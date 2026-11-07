# Goose to Wasm

A [Goose](https://github.com/aardappel/goose) compiler written entirely in Goose. It emits WebAssembly directly and uses native C as a portable bootstrap backend. **Conformance is partial: 106 of 7,503 contract rows fail.**

## Benchmarks

**2026-11-07 · AMD Ryzen 7 3800X pinned to CPU 7 · lower is better.** Five-sample medians for ten examples using snapshot 52. Cold direct Wasm builds took 50.3–133.1 ms; native C builds took 251.3–1844.2 ms. [Results and method](bench/results/2026-11-07/literal-array-inference/README.md)

![Goose compiler cold build times for ten examples](bench/charts/goose-examples-compilation.svg)

Runtime measures process launch through exit, including startup and output. The panels compare compilation on launch, full precompiled Wasmtime, and minimal AOT. Preparation is measured separately.

![Goose example process times by runtime mode](bench/charts/goose-examples-runtime.svg)

![Wasmtime preparation times for ten examples](bench/charts/goose-host-preparation.svg)

Sorting took 175.0 ms with minimal AOT and 119.5 ms natively. All ten Wasm modules are byte-identical to snapshot 51. Interleaved direct-build ratios for snapshot 52/51 were 0.999–1.005, with a median workload ratio of 1.002. Runtime process cohorts were collected separately; no matched runtime speedup is claimed.

## Construction and contracts

The compiler implements loading, parsing, checking, specialization, optimization and code generation in Goose. Bootstrap builds a frozen C seed with a native C compiler, then uses it to build the compiler. Snapshot 52 passed C-only fixed-point verification; its final two generated C outputs match.

With Python 3, a native C compiler and Node for Wasm execution:

```sh
python3 scripts/bootstrap.py --verify
python3 scripts/goose_wasm.py build examples/squares.goose -o build/squares.wasm
node scripts/run_wasm.mjs build/squares.wasm
```

Snapshot 52 passed 7,397 of 7,503 frozen source and output contracts; 106 failed. Against snapshot 51, 2 of 7,435 shared checks improved and none regressed. All 68 new source-authored checks passed. The curated Wasm corpus passed 3,144/3,144 checks each in Wasmtime and V8; all 1,268 curated native controls also passed. The remaining failures are 6 accepted invalid programs and 100 runtime contracts rejected during Goose compilation. Every runtime check that reached execution passed. No C++ oracle was executed. [Qualification](selfhost/results/2026-11-07/literal-array-inference/summary.json)

[Compiler and bootstrap](selfhost/README.md) · [Guide](docs/GUIDE.md) · [Examples](examples/README.md) · [Conformance runner](tests/conformance.py)
