# Goose to Wasm

A [Goose](https://github.com/aardappel/goose) compiler written entirely in Goose. It emits WebAssembly directly and uses native C as a portable bootstrap backend. **Conformance is partial: 245 of 5,043 contract rows fail.**

## Benchmarks

**2026-11-05 · AMD Ryzen 7 3800X pinned to CPU 7 · lower is better.** Five-sample medians for ten examples using snapshot 40. Cold direct Wasm builds took 49.0–127.4 ms; native C builds took 241.8–1,663.4 ms. [Results and method](bench/results/2026-11-05/names-and-enums/README.md)

![Goose compiler cold build times for ten examples](bench/charts/goose-examples-compilation.svg)

Runtime measures process launch through exit, including startup and output. The panels compare compilation on launch, full precompiled Wasmtime, and minimal AOT. Preparation is measured separately.

![Goose example process times by runtime mode](bench/charts/goose-examples-runtime.svg)

![Wasmtime preparation times for ten examples](bench/charts/goose-host-preparation.svg)

The native column uses this compiler's C backend. Sorting took 161.7 ms with minimal AOT and 112.6 ms natively. Snapshot 39 was measured separately; these runs do not establish a matched runtime improvement.

## How it was built

The compiler implements loading, parsing, checking, specialization, optimization and code generation in Goose. Bootstrap builds a frozen C seed with a native C compiler, then uses it to build the compiler. Snapshot 40 passed C-only fixed-point verification. It separates global value, type and function names, and fixes enum storage checks and reference matches.

With Python 3, a native C compiler and Node for Wasm execution:

```sh
python3 scripts/bootstrap.py --verify
python3 scripts/goose_wasm.py build examples/squares.goose -o build/squares.wasm
node scripts/run_wasm.mjs build/squares.wasm
```

Snapshot 40 passed 4,798 of 5,043 frozen source and output contracts; 245 failed. Against snapshot 39, 16 of 5,043 shared checks improved and none regressed. The curated Wasm corpus passed 1,952/1,952 checks each in Wasmtime and V8. Remaining gaps include 41 accepted invalid programs and 204 runtime contracts that fail to compile or execute. Variable images, lifetimes and control flow remain incomplete. [Qualification](selfhost/results/2026-11-05/names-and-enums/summary.json)

[Compiler and bootstrap](selfhost/README.md) · [Guide](docs/GUIDE.md) · [Examples](examples/README.md) · [Conformance runner](tests/conformance.py)
