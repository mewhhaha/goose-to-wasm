# Langbench Mandelbrot trial

This local, single-thread trial adapts one workload from [langbench](https://github.com/leroyguillaume/langbench), pinned at `f00181bd514606b140bf76ac461694a438c88270`. It is not the standard Docker campaign. The profiles use 512×512 pixels and 500 iterations, 1024×1024 and 1000, and the official 2048×2048 and 1000; the official checksum is `1038538536`.

The unchanged upstream C workload is built with GCC and Clang. The same Goose port is compiled to native C by this compiler and by upstream Goose `2e2bedef5b980bf013cac5aaa0095bfea64e5569`, then built with GCC; this compiler also emits Wasm for V8 and Wasmtime. The C reference uses `-std=c11 -O3 -march=x86-64-v3 -ffp-contract=off -fno-fast-math`; generated Goose C adds `-fno-strict-aliasing`. Goose `-O2` sets frontend optimization, not the downstream C optimization level.

All runs use one thread and validate their checksum. The C program includes a pthread spawn and join and an atomic row queue inside the timed region; the scalar Goose port has neither. Comparisons within the Goose group have the closest source match; C comparisons also reflect the port difference.

Each fresh process computes once between monotonic clocks, excluding input, output, and startup. V8 may tier during that computation, so this is not warmed throughput. Process launch through exit is also measured; subtracting kernel time from process time does not isolate startup. Inputs arrive through C arguments or Goose stdin outside the timed region.

The recorded trial uses five uncached workload builds per artifact and seven runtime samples per cell and profile, plus one discarded whole-process warmup. Build and run order are shuffled. Build times exclude constructing the compilers and toolchains; filesystem caches remain enabled. Results were collected on CPU 7 of a Ryzen 7 3800X with sibling CPU 15 and the schedutil governor on a shared host. Background load and frequency changes limit interpretation of small gaps. Exact commands, identities, checksums, samples, and observed host state are in the [dated report](../results/2026-11-07/langbench-trial/report.json).

## Reproduce

Install GCC, Clang, Python, Node and the Python Wasmtime bindings, and build this project's compiler and standard library. Build upstream Goose from the pinned revision and point to its compiler and matching `stdlib`. The recorded clean build recipe and compiler identity are preserved with the dated results. From the repository root, on a machine where CPU 7 is available:

```sh
source build/performance-env.sh
python3 bench/langbench.py \
  --upstream-goose build/langbench-native/goose \
  --upstream-stdlib build/langbench-goose-source/stdlib \
  --cpu 7 --samples 7 --compile-samples 5 \
  --output-dir build/langbench-repeat
```

Choose an unused output directory and an available CPU for another machine. The report marks failed builds or checksums; use only qualified rows for comparisons.
