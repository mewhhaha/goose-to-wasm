# Goose to Wasm

A [Goose](https://github.com/aardappel/goose) compiler written in Goose. It emits WebAssembly directly or native executables through C. It passes 10,689 of 10,793 conformance rows. [Compatibility tracker](docs/FEATURES.md)

## Benchmarks

**Compiler speed.** On 2026-11-17, the candidate took 0.969× the parent compiler's CPU time to emit Wasm and 0.973× to emit C. These are geometric means of medians across eleven programs, with 31 measurements per cell. C emission excludes C compilation and linking. In a separate 2026-11-11 campaign, snapshot 59 took 0.58× the earlier C++ compiler's time for Wasm and 0.53× for C. [Current measurements](bench/results/2026-11-17/compiler-iteration/README.md) · [Snapshot 59](bench/results/2026-11-11/compiler-throughput-59/README.md)

![Compiler execution time for eleven programs](bench/charts/compiler-comparison.svg)

**Large programs.** On 2026-11-17 the compiler's self-check went from 11.5 s to 3.9 s of CPU time and from 503 to 306 MiB peak memory in an interleaved run. A later run of five pairs compiling frozen compiler sources reduced CPU time from 11.55 s to 8.64 s for Wasm and from 7.64 s to 6.69 s for C, with identical artifacts. Self-check was flat under that run's shared load. A separate change reduced Blot2's first pass from 298–308 s to 122–124 s of CPU time. That pass ends with 38 lifetime diagnostics. [Self-check](bench/results/2026-11-17/lifetime-compact-reads/README.md) · [Compiler iteration](bench/results/2026-11-17/compiler-iteration/README.md) · [Blot2](bench/results/2026-11-17/blot2-captured-reads/README.md)

**Native builds.** Sixteen parallel C units built the compiler in 16.1 s instead of 97.9 s with Clang `-O2` on eight cores. The resulting compiler executes 2.4% more instructions. Release bootstraps use one unit. [Method and results](bench/results/2026-11-14/native-units/README.md)

**Bootstrap iteration.** A warm verified bootstrap of the frozen compiler sources fell from 52.05 s to 5.80 s wall time across three paired repetitions, with native executables already cached. The generated C and compiler executable were identical. The build used Clang 23.1.5 with `-O2` and one C unit. [Measurements](bench/results/2026-11-17/compiler-iteration/README.md)

**The compiler as Wasm.** It checked itself in 13–14 s and compiled itself in 22–23 s under Wasmtime on 2026-11-17. Under V8 in Node 22 the 64-bit module took 15 s and 28 s respectively. The 32-bit module took 13–14 s and 25 s. Outputs match the native compiler byte for byte. [Measurements](bench/results/2026-11-17/lifetime-compact-reads/README.md)

**Example programs.** On an active shared host, median cold builds for ten examples took 165–275 ms for direct Wasm and 1.07–6.62 s for native executables, including C compilation and linking. Full process times include launch and exit. Sorting took 669 ms with minimal Wasmtime AOT and 442 ms native. [Method and results](bench/results/2026-11-17/compiler-iteration/README.md)

![Example program build times](bench/charts/goose-examples-compilation.svg)

![Example program process times](bench/charts/goose-examples-runtime.svg)

![Wasmtime preparation times for ten examples](bench/charts/goose-host-preparation.svg)

**Mandelbrot.** A separate hot run on the official input took 2.94 s native, 3.33 s in Wasmtime and 3.02 s in V8. The GCC C and upstream Goose native controls took 2.92 s and 3.02 s. Hot runtime excludes compilation, startup and instantiation. [Method and results](bench/results/2026-11-17/compiler-iteration/README.md)

![Mandelbrot runtime by engine](bench/charts/langbench-hot-runtime.svg)

![Mandelbrot complete workload build times](bench/charts/langbench-compilation.svg)

**Varint traversal.** A checksum loop over 8,008 mixed-width values fell from 161.61 ms to 0.129 ms in resident Wasmtime with 32-bit memory. The compiler advances a bounded cursor for proven top-level loops on immutable incoming slices. [Method and results](bench/results/2026-11-17/varint-foreach/README.md)

## How it was built

The frontend, optimizer and backends are written in Goose. A C++ reference guided the initial port. Frozen source and output contracts now check behavior. A checked-in C seed bootstraps the compiler, and `--verify` compares consecutive generated C outputs. [Compiler and bootstrap](selfhost/README.md) · [Contracts](tests/README.md) · [Guide](docs/GUIDE.md) · [Examples](examples/README.md)

With Python 3, a C compiler and Node installed, build and run the first example.

```sh
python3 scripts/bootstrap.py --verify
python3 scripts/goose_wasm.py build examples/squares.goose -o build/squares.wasm
node scripts/run_wasm.mjs build/squares.wasm
```
