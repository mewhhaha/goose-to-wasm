# Goose to Wasm

A [Goose](https://github.com/aardappel/goose) compiler written entirely in Goose. It emits WebAssembly directly and uses native C as a portable bootstrap backend. **Conformance is partial: 166 of 5,677 contract rows fail.**

## Benchmarks

**2026-11-05 · AMD Ryzen 7 3800X pinned to CPU 7 · lower is better.** Five-sample medians for ten examples using snapshot 43. Cold direct Wasm builds took 52.0–141.8 ms; native C builds took 262.1–1909.2 ms. [Results and method](bench/results/2026-11-05/readonly-numbers-and-static-views/README.md)

![Goose compiler cold build times for ten examples](bench/charts/goose-examples-compilation.svg)

Runtime measures process launch through exit, including startup and output. The panels compare compilation on launch, full precompiled Wasmtime, and minimal AOT. Preparation is measured separately.

![Goose example process times by runtime mode](bench/charts/goose-examples-runtime.svg)

![Wasmtime preparation times for ten examples](bench/charts/goose-host-preparation.svg)

Sorting took 190.7 ms with minimal AOT and 122.0 ms natively. The native column uses this compiler's C backend. Snapshot 42 was measured separately; these runs do not establish a matched runtime improvement. A separate matched numeric/identity checker guard measured a 2.13% peak-RSS increase; shared-machine CPU results do not establish a speedup.

## How it was built

The compiler implements loading, parsing, checking, specialization, optimization and code generation in Goose. Bootstrap builds a frozen C seed with a native C compiler, then uses it to build the compiler. Snapshot 43 passed C-only fixed-point verification; its final two generated C outputs match (C2 = C3). This batch corrects numeric and identity checks, literal borrowing, loop counts, initializer order and worker snapshots.

With Python 3, a native C compiler and Node for Wasm execution:

```sh
python3 scripts/bootstrap.py --verify
python3 scripts/goose_wasm.py build examples/squares.goose -o build/squares.wasm
node scripts/run_wasm.mjs build/squares.wasm
```

Snapshot 43 passed 5,511 of 5,677 frozen source and output contracts; 166 failed. Against snapshot 42, 13 of 5,300 shared checks improved and none regressed. All 377 new source-authored checks passed. The curated Wasm corpus passed 2,272/2,272 checks each in Wasmtime and V8; all 314 curated native controls also passed. The remaining failures are 28 accepted invalid programs and 138 runtime contracts rejected during Goose compilation. Every runtime check that reached execution passed. [Qualification](selfhost/results/2026-11-05/readonly-numbers-and-static-views/summary.json)

[Compiler and bootstrap](selfhost/README.md) · [Guide](docs/GUIDE.md) · [Examples](examples/README.md) · [Conformance runner](tests/conformance.py)
