# Goose to Wasm

A [Goose](https://github.com/aardappel/goose) compiler written entirely in Goose. It emits WebAssembly directly and uses native C as a portable bootstrap backend. **Conformance is partial: 130 of 6,997 contract rows fail.**

## Benchmarks

**2026-11-07 · AMD Ryzen 7 3800X pinned to CPU 7 · lower is better.** Five-sample medians for ten examples using snapshot 47. Cold direct Wasm builds took 49.2–130.6 ms; native C builds took 248.2–1806.5 ms. [Results and method](bench/results/2026-11-07/pending-elements-and-payloads/README.md)

![Goose compiler cold build times for ten examples](bench/charts/goose-examples-compilation.svg)

Runtime measures process launch through exit, including startup and output. The panels compare compilation on launch, full precompiled Wasmtime, and minimal AOT. Preparation is measured separately.

![Goose example process times by runtime mode](bench/charts/goose-examples-runtime.svg)

![Wasmtime preparation times for ten examples](bench/charts/goose-host-preparation.svg)

Sorting took 161.9 ms with minimal AOT and 113.4 ms natively. The native column uses this compiler's C backend. Snapshot 46 was measured separately; these runs do not establish a matched runtime improvement.

## How it was built

The compiler implements loading, parsing, checking, specialization, optimization and code generation in Goose. Bootstrap builds a frozen C seed with a native C compiler, then uses it to build the compiler. Snapshot 47 passed C-only fixed-point verification; its final two generated C outputs match. This batch fixes pending-element completion, resizable variant bindings, overload ranking and untyped function arguments. Wasm resizable payloads retain their contents and stable field references across copies and replacement.

With Python 3, a native C compiler and Node for Wasm execution:

```sh
python3 scripts/bootstrap.py --verify
python3 scripts/goose_wasm.py build examples/squares.goose -o build/squares.wasm
node scripts/run_wasm.mjs build/squares.wasm
```

Snapshot 47 passed 6,867 of 6,997 frozen source and output contracts; 130 failed. Against snapshot 46, 4 of 6,537 shared checks improved and none regressed. All 460 new source-authored checks passed. The curated Wasm corpus passed 2,908/2,908 checks each in Wasmtime and V8; all 998 curated native controls also passed. The remaining failures are 8 accepted invalid programs and 122 runtime contracts rejected during Goose compilation. Every runtime check that reached execution passed. [Qualification](selfhost/results/2026-11-07/pending-elements-and-payloads/summary.json)

[Compiler and bootstrap](selfhost/README.md) · [Guide](docs/GUIDE.md) · [Examples](examples/README.md) · [Conformance runner](tests/conformance.py)
