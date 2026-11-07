# Langbench Mandelbrot trial

This local, single-thread trial adapts one workload from [langbench](https://github.com/leroyguillaume/langbench), pinned at `f00181bd514606b140bf76ac461694a438c88270`. It is not the standard Docker campaign. Profiles use 512×512 pixels and 500 iterations, 1024×1024 and 1000, and the official 2048×2048 and 1000; the official checksum is `1038538536`.

The upstream C workload is built with GCC and Clang. The same Goose port is compiled to native C by this compiler and upstream Goose `2e2bedef5b980bf013cac5aaa0095bfea64e5569`, then built with GCC; this compiler also emits Wasm for V8 and Wasmtime. The C reference uses `-std=c11 -O3 -march=x86-64-v3 -ffp-contract=off -fno-fast-math`; generated Goose C adds `-fno-strict-aliasing`. Goose `-O2` sets frontend optimization, not downstream C optimization.

All runs validate their checksum. C includes a pthread spawn and join and an atomic row queue inside the timed region; the scalar Goose port has neither. Comparisons within the Goose group have the closest source match; C comparisons also reflect the port difference.

## Resident execution

The recommended [resident trial](../results/2026-11-07/langbench-hot/README.md) reuses the artifacts from the [original trial](../results/2026-11-07/langbench-trial/README.md). Wasmtime deserializes a locally compiled, verified module once into a persistent Python engine; each request gets a fresh store, instance and imports. A persistent Node process constructs one V8 module, warms its functions with default tiering, and creates a fresh instance per request. Native controls use fresh processes and their internal clocks. After one full-kernel warmup per profile, seven measurements per cell and profile are interleaved.

The source-level computation timer excludes engine compilation, startup, instantiation, input, output and IPC. Request wall time is recorded separately and is not process launch through exit for resident engines. The original fresh-process computation timer also excluded preparation, so differences between trials cannot be attributed simply to charging startup. V8's default tiering does not guarantee that an active long-running call switches to optimized code. The separately collected original build timings remain the compilation reference; the resident trial does not rebuild workloads.

## Reproduce

Install Python, Node and the Python Wasmtime bindings. In a fresh checkout, restore the original trial's cached artifacts without overwriting source files, then run the resident trial from the repository root:

```sh
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r requirements.txt -r bench/requirements.txt
tar -xzf bench/results/2026-11-07/langbench-trial/reproduction.tar.gz \
  build/langbench-trial-2026-11-07/builds
python3 bench/langbench_hot.py \
  --reference-report bench/results/2026-11-07/langbench-trial/report.json \
  --artifacts-dir build/langbench-trial-2026-11-07/builds \
  --output-dir build/langbench-hot-repeat --cpu 7 --samples 7
```

Artifacts and runtime identities are machine-specific; on another environment, build a new qualified original reference and point `--reference-report` and `--artifacts-dir` at it instead of assuming the archived native code or Python hash is portable. Choose an available CPU and unused output directory. The reports mark failed checks; use only qualified rows for comparisons. Shared-host load, SMT contention and CPU frequency can affect small differences.
