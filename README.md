# Goose to Wasm

A [Goose](https://github.com/aardappel/goose) compiler written in Goose. It emits WebAssembly directly or native executables through C. It passes 10,689 of 10,793 conformance rows. [Compatibility tracker](docs/FEATURES.md)

## Benchmarks

**Compiler speed.** On 2026-11-14, snapshot 63 took 1.04× snapshot 61's time to emit Wasm and 1.06× to emit C. It took 0.78× snapshot 62's time. These are geometric means across eleven programs. C emission excludes C compilation and linking. In a separate campaign, snapshot 59 took 0.58× the earlier C++ compiler's time for Wasm and 0.53× for C. [Snapshot 63](bench/results/2026-11-14/compiler-throughput-63/README.md) · [Snapshot 59](bench/results/2026-11-11/compiler-throughput-59/README.md)

![Compiler execution time for eleven programs](bench/charts/compiler-comparison.svg)

**Large programs.** On 2026-11-17 the compiler's self-check went from 11.5 s to 3.9 s of CPU time and from 503 to 306 MiB peak memory in an interleaved run. A separate change reduced Blot2's first pass from 298–308 s to 122–124 s of CPU time. That pass ends with 38 lifetime diagnostics. [Self-check](bench/results/2026-11-17/lifetime-compact-reads/README.md) · [Blot2](bench/results/2026-11-17/blot2-captured-reads/README.md)

**Native builds.** Sixteen parallel C units built the compiler in 16.1 s instead of 97.9 s with Clang `-O2` on eight cores. The resulting compiler executes 2.4% more instructions. Release bootstraps use one unit. [Method and results](bench/results/2026-11-14/native-units/README.md)

**The compiler as Wasm.** It checked itself in 13–14 s and compiled itself in 22–23 s under Wasmtime on 2026-11-17. Under V8 in Node 22 the 64-bit module took 15 s and 28 s respectively. The 32-bit module took 13–14 s and 25 s. Outputs match the native compiler byte for byte. [Measurements](bench/results/2026-11-17/lifetime-compact-reads/README.md)

**Example programs.** In the snapshot 58 campaign, median cold builds for ten examples took 50–69 ms for direct Wasm and 253–1,924 ms for native executables, including C compilation and linking. Process times include launch and exit. Sorting took 177 ms with minimal Wasmtime AOT and 113 ms native. [Method and results](bench/results/2026-11-08/compiler-throughput-58/README.md)

![Example program build times](bench/charts/goose-examples-compilation.svg)

![Example program process times](bench/charts/goose-examples-runtime.svg)

![Wasmtime preparation times for ten examples](bench/charts/goose-host-preparation.svg)

**Mandelbrot.** In the same campaign, median computation on the official input took 2.40 s native, 2.57 s in Wasmtime and 2.50 s in V8. The native C and upstream Goose controls took 2.40 s and 2.39 s. Hot runtime excludes compilation, startup and instantiation.

![Mandelbrot runtime by engine](bench/charts/langbench-hot-runtime.svg)

![Mandelbrot complete workload build times](bench/charts/langbench-compilation.svg)

## How it was built

The frontend, optimizer and backends are written in Goose. A C++ reference guided the initial port. Frozen source and output contracts now check behavior. A checked-in C seed bootstraps the compiler, and `--verify` compares consecutive generated C outputs. [Compiler and bootstrap](selfhost/README.md) · [Contracts](tests/README.md) · [Guide](docs/GUIDE.md) · [Examples](examples/README.md)

With Python 3, a C compiler and Node installed, build and run the first example.

```sh
python3 scripts/bootstrap.py --verify
python3 scripts/goose_wasm.py build examples/squares.goose -o build/squares.wasm
node scripts/run_wasm.mjs build/squares.wasm
```
