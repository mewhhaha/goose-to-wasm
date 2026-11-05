# Goose to Wasm

A [Goose](https://github.com/aardappel/goose) compiler written entirely in Goose. It emits WebAssembly directly and uses native C as a portable bootstrap backend. **Conformance is partial: 204 of 5,118 contract rows fail.**

## Benchmarks

**2026-11-05 · AMD Ryzen 7 3800X pinned to CPU 7 · lower is better.** Five-sample medians for ten examples using snapshot 41. Cold direct Wasm builds took 54.2–150.0 ms; native C builds took 263.8–2011.9 ms. [Results and method](bench/results/2026-11-05/storage-and-captures/README.md)

![Goose compiler cold build times for ten examples](bench/charts/goose-examples-compilation.svg)

Runtime measures process launch through exit, including startup and output. The panels compare compilation on launch, full precompiled Wasmtime, and minimal AOT. Preparation is measured separately.

![Goose example process times by runtime mode](bench/charts/goose-examples-runtime.svg)

![Wasmtime preparation times for ten examples](bench/charts/goose-host-preparation.svg)

Sorting took 195.7 ms with minimal AOT and 123.4 ms natively. The native column uses this compiler's C backend. Snapshot 40 was measured separately; these runs do not establish a matched runtime improvement.

## How it was built

The compiler implements loading, parsing, checking, specialization, optimization and code generation in Goose. Bootstrap builds a frozen C seed with a native C compiler, then uses it to build the compiler. Snapshot 41 passed C-only fixed-point verification; its final two generated C outputs match. Snapshot 41 adds canonical variable and runtime-limited images, byte-cursor copy and iteration, aggregate compound-assignment ordering, full-width free integer and stopping arguments, canonical stack diagnostics and stats, captured-specialization environment tracking, and delayed fixed Ref/Slice bindings.

With Python 3, a native C compiler and Node for Wasm execution:

```sh
python3 scripts/bootstrap.py --verify
python3 scripts/goose_wasm.py build examples/squares.goose -o build/squares.wasm
node scripts/run_wasm.mjs build/squares.wasm
```

Snapshot 41 passed 4,914 of 5,118 frozen source and output contracts; 204 failed. Against snapshot 40, 41 of 5,043 shared checks improved and none regressed. All 75 new source-authored checks passed. The curated Wasm corpus passed 1,993/1,993 checks each in Wasmtime and V8; all 34 curated native controls also passed. Remaining gaps include 38 accepted invalid programs and 166 runtime contracts that fail to compile or execute. Lifetimes, control flow and native image operations remain incomplete. [Qualification](selfhost/results/2026-11-05/storage-and-captures/summary.json)

[Compiler and bootstrap](selfhost/README.md) · [Guide](docs/GUIDE.md) · [Examples](examples/README.md) · [Conformance runner](tests/conformance.py)
