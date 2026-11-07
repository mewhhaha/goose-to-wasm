# Goose to Wasm

A [Goose](https://github.com/aardappel/goose) compiler written entirely in Goose. It emits WebAssembly directly and uses native C as a portable bootstrap backend. **Conformance is partial: 118 of 7,121 contract rows fail.**

## Benchmarks

**2026-11-07 · AMD Ryzen 7 3800X pinned to CPU 7 · lower is better.** Five-sample medians for ten examples using snapshot 48. Cold direct Wasm builds took 49.1–130.9 ms; native C builds took 247.3–1803.8 ms. [Results and method](bench/results/2026-11-07/exact-nonlocal-targets/README.md)

![Goose compiler cold build times for ten examples](bench/charts/goose-examples-compilation.svg)

Runtime measures process launch through exit, including startup and output. The panels compare compilation on launch, full precompiled Wasmtime, and minimal AOT. Preparation is measured separately.

![Goose example process times by runtime mode](bench/charts/goose-examples-runtime.svg)

![Wasmtime preparation times for ten examples](bench/charts/goose-host-preparation.svg)

Sorting took 179.0 ms with minimal AOT and 113.9 ms natively. The native column uses this compiler's C backend. Sorting's Wasm module is unchanged from snapshot 47; minimal AOT samples ranged 162.2–181.0 ms. Snapshot 47 was measured separately; no matched runtime improvement is established.

## How it was built

The compiler implements loading, parsing, checking, specialization, optimization and code generation in Goose. Bootstrap builds a frozen C seed with a native C compiler, then uses it to build the compiler. Snapshot 48 passed C-only fixed-point verification; its final two generated C outputs match. This batch checks exact nonlocal targets through cached and recursive calls, replacing the old context walk. Native controls that always return no longer allocate an unused result.

With Python 3, a native C compiler and Node for Wasm execution:

```sh
python3 scripts/bootstrap.py --verify
python3 scripts/goose_wasm.py build examples/squares.goose -o build/squares.wasm
node scripts/run_wasm.mjs build/squares.wasm
```

Snapshot 48 passed 7,003 of 7,121 frozen source and output contracts; 118 failed. Against snapshot 47, 12 of 6,997 shared checks improved and none regressed. All 124 new source-authored checks passed. The curated Wasm corpus passed 2,970/2,970 checks each in Wasmtime and V8; all 1,060 curated native controls also passed. The remaining failures are 6 accepted invalid programs and 112 runtime contracts rejected during Goose compilation. Every runtime check that reached execution passed. [Qualification](selfhost/results/2026-11-07/exact-nonlocal-targets/summary.json)

[Compiler and bootstrap](selfhost/README.md) · [Guide](docs/GUIDE.md) · [Examples](examples/README.md) · [Conformance runner](tests/conformance.py)
