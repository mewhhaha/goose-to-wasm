# Goose to Wasm

A [Goose](https://github.com/aardappel/goose) compiler written in Goose. It emits WebAssembly directly, without generating C or invoking LLVM. Its native C backend also provides a portable bootstrap path.

The compiler is a work in progress: frontend and runtime gaps remain. The checked-in C seed was produced by the Goose compiler. A three-generation C-only bootstrap of snapshot 23 reached identical second- and third-generation C output. Later fixes are not covered by that proof.

## Benchmarks

**Goose compiler measurements are pending.** The charts below are historical results from the earlier C++ compiler, not measurements of the current Goose compiler. New results need a recorded source revision, compiler and workload identities, engine versions and raw samples before they can replace these charts.

### Historical: LangArena

**2026-11-04 · AMD Ryzen 7 3800X · lower is better.** Medians of five samples for seven adapted LangArena workloads. Six use bounded arrays in place of growable storage; each backend compiles the same adapted source. This is not the full 50-task suite. Direct Wasm uses memory32; C-to-Wasm uses memory64.

![Historical C++ compiler cold build times by workload and backend](bench/charts/compilation.svg)

Complete uncached builds include Python driver startup. Direct builds took 65.6–74.8 ms versus 638.2–676.6 ms for C-to-Wasm on these inputs.

![Historical C++ compiler output runtime by workload, backend, and engine](bench/charts/runtime.svg)

Runtime is seconds per configured measured iteration count, excluding preparation, warmup and startup. These runs and the target runs were collected separately from the example cohort.

[Historical results and samples](bench/results/2026-11-04/leaf-and-loads/README.md) · [Method](bench/langarena/README.md)

### Historical: runtime targets

Pilot-selected Wasm and native references show attainable results for these workloads on this machine; they are not universal ceilings.

![Historical warmed runtime targets](bench/charts/runtime-targets.svg)

[Results and method](docs/RUNTIME_TARGETS.md)

### Historical: ten example programs

Each example uses the same constant inputs across backends and checks its output. Runtime measures process launch to exit, including startup and output; the LangArena chart measures warmed computation. Cold native-host runs disable the compilation cache; precompiled runs exclude preparation.

![Historical example cold build times by backend](bench/charts/examples-compilation.svg)

![Historical example process times with the native Wasmtime host and native C](bench/charts/examples-runtime.svg)

![Historical runtime lifecycle by mode](bench/charts/runtime-lifecycle.svg)

The lifecycle chart compares fresh processes with a resident worker that creates a fresh instance per request. The example runtime chart also includes an optional minimal AOT host; preparation is measured separately. In 201 paired Functions rounds its median paired time was 1.6% lower than the previous minimal host and 16.0% above native C.

[Method and results](bench/examples.md) · [Host comparison and preparation costs](bench/wasmtime-host.md)

Native C uses generic GCC `-O2`; [tuned controls](docs/NATIVE_PERFORMANCE.md) and the [Wasm audit](docs/WASM_AUDIT.md) document the historical comparisons.

## How it was built

The compiler implements source loading, parsing, checking, specialization, optimization and code generation in Goose. Bootstrap compiles a frozen C seed with a native C compiler, then uses the resulting compiler to build the Goose source. `--verify` checks the generated C across generations.

```sh
source build/performance-env.sh
python scripts/bootstrap.py --verify
python scripts/goose_wasm.py build examples/squares.goose -o build/squares.wasm
node scripts/run_wasm.mjs build/squares.wasm
```

Correctness is checked against frozen source and output contracts without running a reference compiler. The suite records expected output, exit status and failure phase, and reports failures rather than silently skipping them. Recent runs passed 2,014 of 2,468 upstream contract rows at O0 and 1,710 of 1,914 curated Wasm rows across O0 and O2. All ten native examples, all 20 Wasm example runs and 12 formatter contracts passed. These results identify remaining gaps; they are not a parity claim.

[Compiler and bootstrap](selfhost/README.md) · [Examples](examples/README.md) · [Conformance runner](tests/conformance.py)
