# Goose to Wasm

A [Goose](https://github.com/aardappel/goose) compiler written entirely in Goose. It emits WebAssembly directly and uses native C for bootstrap. **Conformance is partial: 100 of 7,871 contract rows fail.**

## Benchmarks

**Langbench Mandelbrot · 2026-11-08.** The official single-thread input computes 2,048 × 2,048 pixels with at most 1,000 iterations per pixel. Median timed computation: **2.45 s native, 2.64 s in resident Wasmtime and 2.57 s in resident V8**. Each profile has seven samples after one warmup; setup, compilation, deserialization and instantiation are outside the guest timer. The checksum is 1,038,538,536. [Results and method](bench/results/2026-11-08/scalar-wasm-locals/README.md)

![Mandelbrot runtime by engine](bench/charts/langbench-hot-runtime.svg)

![Mandelbrot complete workload build times](bench/charts/langbench-compilation.svg)

The workload build chart uses five fresh builds collected before the runtime run. Native bars include C compilation and linking; direct Wasm excludes engine preparation. The C reference uses one thread and a row queue; Goose uses a scalar port.

**Compiler execution · 2026-11-08.** Across eleven programs, Goose 57 took 3.00× the previous C++ compiler’s time for Wasm emission and 2.21× for C emission (geometric means).. The chart compares the prior optimized C++ compiler with Goose snapshots 56 and 57 across ten examples and Mandelbrot. It times source-to-Wasm and source-to-C with the same `-O2` input, using five samples after one warmup. Downstream C compilation and runtime validation happen after the timer. This measures running each compiler, not building the compiler itself. [Results and method](bench/results/2026-11-08/scalar-wasm-locals/README.md)

![Compiler execution time for eleven programs](bench/charts/compiler-comparison.svg)

**Example programs · 2026-11-08.** Five-sample medians on a shared Ryzen 7 3800X, CPU 7. Complete cold builds took 50.8–158.5 ms for direct Wasm and 257.0–1852.7 ms for native executables. Runtime bars measure fresh launch through exit, including startup and output; AOT preparation is separate.. [Results and method](bench/results/2026-11-08/scalar-wasm-locals/README.md)

![Example program build times](bench/charts/goose-examples-compilation.svg)

![Example program process times](bench/charts/goose-examples-runtime.svg)

![Wasmtime preparation times for ten examples](bench/charts/goose-host-preparation.svg)

The scalar Mandelbrot gain does not extend to every example: sorting still took 180.0 ms with minimal AOT versus 115.5 ms native. All results use a shared host; small gaps are inconclusive.

## Construction and contracts

The compiler implements loading, parsing, checking, specialization, optimization and code generation in Goose. Bootstrap builds a frozen C seed with a native C compiler, then uses it to build the compiler. Snapshot 57 passed C-only fixed-point verification; its final two generated C outputs match.

With Python 3, a native C compiler and Node for Wasm execution:

```sh
python3 scripts/bootstrap.py --verify
python3 scripts/goose_wasm.py build examples/squares.goose -o build/squares.wasm
node scripts/run_wasm.mjs build/squares.wasm
```

Snapshot 57 passed 7,771 of 7,871 frozen source and output contracts, with the same 100 gaps as snapshot 56; all 84 new rows passed. The curated corpus passed 3,370 Wasm checks in each of Wasmtime and V8 and 1,410 native controls. [Qualification](selfhost/results/2026-11-08/scalar-wasm-locals/summary.json)

[Compiler and bootstrap](selfhost/README.md) · [Guide](docs/GUIDE.md) · [Examples](examples/README.md) · [Conformance runner](tests/conformance.py)
