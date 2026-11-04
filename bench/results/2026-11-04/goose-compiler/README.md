# Goose compiler examples · 2026-11-04

Ten examples were built with the Goose compiler and checked against their expected output. The example run recorded 410 observations; the separate host run recorded 360 runtime and 150 preparation observations. All passed. Each compile, runtime and preparation measurement uses five samples, with one runtime warmup. The machine was an AMD Ryzen 7 3800X, pinned to CPU 7; lower times are better.

The public source baseline is `505475c`, with the frozen snapshot 23 compiler inputs recorded in the reports. The C seed SHA-256 is `4514a74a0205bed3257a540129f21a328318772825ea5a3484164a207dce163d`; the installed compiler SHA-256 is `2e8f3e2d720d40fdfb64c5d6478b644054a8b13a4b6f20d85418ca889a10ff74`. Reports record source, standard library, workload, artifact and tool hashes. The host run used the example run's artifacts; it was collected separately.

Cold build times include Python driver startup. Direct builds emit Wasm; native builds emit C and compile it with GCC 16.2.1. Runtime measures fresh process launch to exit, including output. Wasmtime 50.0.1 host modes include compilation on launch, full precompiled artifacts and a minimal AOT profile. Preparation includes launch, compilation, serialization and writing; it is measured separately and excluded from precompiled runtime. The example report also records Node 24.22.1 / V8 13.6.233.17-node.58. The reports record exact commands and configuration.

Native results use this Goose compiler's C backend and include its overhead; they are not a general native ceiling. The earlier C++ compiler measurements are separate historical runs and are not a matched control for these numbers.

[Example report](examples.json) · [Host report](host.json) · [Summary](summary.json) · [Measurements and frozen inputs](measurements.tar.gz)
