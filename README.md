# Goose to Wasm

A [Goose](https://github.com/aardappel/goose) compiler written entirely in Goose. It emits WebAssembly directly and uses native C as a portable bootstrap backend. **Conformance is partial: 261 of 5,043 contract rows fail.**

## Benchmarks

**2026-11-05 · AMD Ryzen 7 3800X pinned to CPU 7 · lower is better.** Five-sample medians for ten examples using snapshot 39. Cold direct Wasm builds took 50.9–136.2 ms; native C builds took 255.4–1,744.3 ms. [Results and method](bench/results/2026-11-05/returns-and-contexts/README.md)

![Goose compiler cold build times for ten examples](bench/charts/goose-examples-compilation.svg)

Runtime measures process launch through exit, including startup and output. The panels compare compilation on launch, full precompiled Wasmtime, and minimal AOT. Preparation is measured separately.

![Goose example process times by runtime mode](bench/charts/goose-examples-runtime.svg)

![Wasmtime preparation times for ten examples](bench/charts/goose-host-preparation.svg)

The native column uses this compiler's C backend. Sorting took 168.9 ms with minimal AOT and 117.5 ms natively. Snapshot 38 was measured separately; these runs do not establish a matched runtime improvement.

## How it was built

The compiler implements loading, parsing, checking, specialization, optimization and code generation in Goose. Bootstrap builds a frozen C seed with a native C compiler, then uses it to build the compiler. Snapshot 39 passed C-only fixed-point verification. It fixes returned local construction, nonlocal target contexts and native lowering of divergent tails.

With Python 3, a native C compiler and Node for Wasm execution:

```sh
python3 scripts/bootstrap.py --verify
python3 scripts/goose_wasm.py build examples/squares.goose -o build/squares.wasm
node scripts/run_wasm.mjs build/squares.wasm
```

Snapshot 39 passed 4,782 of 5,043 frozen source and output contracts; 261 failed. Against snapshot 38, 10 of 5,043 shared checks improved and none regressed. The curated Wasm corpus passed 1,952/1,952 checks each in Wasmtime and V8. Remaining gaps include 47 accepted invalid programs and 214 runtime contracts that fail to compile or execute. Variable images, lifetimes and control flow remain incomplete. [Qualification](selfhost/results/2026-11-05/returns-and-contexts/summary.json)

[Compiler and bootstrap](selfhost/README.md) · [Guide](docs/GUIDE.md) · [Examples](examples/README.md) · [Conformance runner](tests/conformance.py)
