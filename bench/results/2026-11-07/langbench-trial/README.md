# Langbench Mandelbrot local trial · 2026-11-07

One single-thread Mandelbrot workload from langbench `f00181bd514606b140bf76ac461694a438c88270`, using the unchanged snapshot 56 compiler source (parent `db76`). This is a local trial, not the standard Docker campaign. The official 2048×2048, 1000-iteration input has checksum `1038538536`.

At the official input, median timed computation was **2.50 s** for this compiler's native output, **37.96 s** for direct Wasm in Wasmtime, and **54.78 s** in V8. These use the same Goose port. The C reference includes a pthread spawn/join and atomic row queue; Goose is scalar, so cross-language comparisons also include that implementation difference.

| Input | Backend | Computation, ms (median ± MAD) | Process, ms (median) |
| --- | --- | ---: | ---: |
| 512² × 500 | C · GCC | 79.5 ± 1.1 | 81.2 |
| 512² × 500 | C · Clang | 85.6 ± 0.5 | 87.1 |
| 512² × 500 | Upstream Goose → GCC | 79.2 ± 1.0 | 81.1 |
| 512² × 500 | This compiler → GCC | 81.0 ± 1.1 | 83.0 |
| 512² × 500 | Direct Wasm · Wasmtime | 1,209.2 ± 11.7 | 1,285.8 |
| 512² × 500 | Direct Wasm · V8 | 1,750.9 ± 14.8 | 1,782.1 |
| 1024² × 1000 | C · GCC | 626.6 ± 3.0 | 628.0 |
| 1024² × 1000 | C · Clang | 667.6 ± 5.0 | 669.5 |
| 1024² × 1000 | Upstream Goose → GCC | 624.3 ± 2.5 | 626.3 |
| 1024² × 1000 | This compiler → GCC | 624.4 ± 3.7 | 626.7 |
| 1024² × 1000 | Direct Wasm · Wasmtime | 9,496.6 ± 146.7 | 9,583.6 |
| 1024² × 1000 | Direct Wasm · V8 | 13,469.7 ± 71.7 | 13,500.2 |
| 2048² × 1000 | C · GCC | 2,498.3 ± 21.4 | 2,499.6 |
| 2048² × 1000 | C · Clang | 2,676.4 ± 16.5 | 2,678.2 |
| 2048² × 1000 | Upstream Goose → GCC | 2,517.3 ± 17.1 | 2,519.2 |
| 2048² × 1000 | This compiler → GCC | 2,504.9 ± 38.0 | 2,507.0 |
| 2048² × 1000 | Direct Wasm · Wasmtime | 37,955.6 ± 458.0 | 38,030.5 |
| 2048² × 1000 | Direct Wasm · V8 | 54,779.3 ± 407.5 | 54,811.3 |

| Build | Source → executable/module, ms (median ± MAD) |
| --- | ---: |
| C · GCC | 58.0 ± 0.2 |
| C · Clang | 65.9 ± 0.3 |
| Upstream Goose → GCC | 212.0 ± 1.0 |
| This compiler → GCC | 334.2 ± 0.4 |
| Direct Wasm (shared by both engines) | 22.5 ± 0.2 |

This cohort passed all **30 builds and 144 execution checks** (126 measured, 18 warmups). All 18 runtime cells qualified. Both engines execute byte-identical Wasm (`b2338da428272b85fc4425bc24b9a0e80976530c25e8281fe85d53c49070fb76`).

Compiler: snapshot 56, SHA-256 `febb9bcacc2346ad0eb96daec2126cce74d23efc07a4bfe249f97aae068ef088`. Upstream Goose: `2e2bedef5b980bf013cac5aaa0095bfea64e5569`, clean compiler SHA-256 `9e4d9ff8927c69c653031850f1b0911ce6827dc71648f1e11448ed06736b75e0`; all 4,085 upstream source blobs matched the pinned tree. Native toolchains were GCC 16.2.1 and Clang 23.1.4; engines were Wasmtime 50.0.1 and Node 24.22.1/V8 13.6.233.17-node.58. Exact hashes and commands are retained in the raw report. Sibling CPU 15 was busy for 6.1% of this cohort, so CPU pinning did not isolate a physical core.

Conformance and bootstrap used no C++ oracle. The clean upstream C++ compiler was run only as a benchmark competitor; it is excluded from the reproduction archive. The archive retains measured native/Wasm artifacts, this compiler, sources and host code. Rebuild the upstream compiler with the recorded recipe to repeat its compilation measurements.

Five uncached workload builds per artifact and seven fresh-process measurements per cell and profile follow one discarded whole-process warmup. All outputs are checked. Builds cover source to native executable or Wasm bytecode, excluding construction of compilers, toolchains and engine preparation. The timed region excludes input, output and startup; V8 uses default tiering; this is not warmed throughput. [V8 documents](https://v8.dev/docs/wasm-compilation-pipeline) that optimized Wasm code does not replace an active call, so a long one-shot function can remain in Liftoff. Process launch through exit is recorded separately; its difference from the timed region is not pure startup. Native C uses `-O3`; Goose `-O2` is a frontend setting. See the [trial guide](../../../langbench/README.md) for flags and workload details.

The run used CPU 7 on a Ryzen 7 3800X, with SMT sibling 15 and the schedutil governor on a shared host. Background load and frequency variation mean small gaps are inconclusive.

Inspection found 20 resolver calls and 20 linear-memory accesses per iteration in the Wasm loop; native GCC keeps the corresponding values in registers. There are no loop host imports. Unused growable-array types enable the resolver, although this module emits no forwarding global updates. Possible follow-ups are requiring emitted forwarding demand before enabling the resolver and promoting address-unobservable scalar bindings. This explains a structural difference, not an allocation of elapsed time or an intrinsic Wasmtime ceiling; no speedup is claimed without measurement. See [inspection review](inspection-review.md), [Wasm text](program.wat), and [inspection data](wasm-inspection.json).

[Raw report](report.json) · [Metrics](metrics.json) · [Validation](validation.json) · [Chart verification](chart-verification.json) · [Reproduction archive](reproduction.tar.gz) · [Upstream build record](upstream-build.json) · [Engine defaults](engine-defaults.json)

## Reproduce from a fresh checkout

Build this project's compiler and standard library first. Install Git, CMake, Ninja, GCC, Clang, Python, Node and the Python Wasmtime bindings. From the repository root:

```sh
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -r requirements.txt -r bench/requirements.txt
python3 scripts/bootstrap.py --verify
git init build/langbench-goose-source
git -C build/langbench-goose-source remote add origin https://github.com/aardappel/goose.git
git -C build/langbench-goose-source fetch --depth 1 origin 2e2bedef5b980bf013cac5aaa0095bfea64e5569
git -C build/langbench-goose-source checkout --detach FETCH_HEAD
cmake -S build/langbench-goose-source -B build/langbench-native -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=c++
cmake --build build/langbench-native -j 2
python3 bench/langbench.py \
  --upstream-goose build/langbench-native/goose \
  --upstream-stdlib build/langbench-goose-source/stdlib \
  --cpu 7 --samples 7 --compile-samples 5 \
  --output-dir build/langbench-repeat
python3 bench/langbench_charts.py build/langbench-repeat/report.json \
  --output-dir build/langbench-repeat/charts \
  --receipt build/langbench-repeat/chart-verification.json
```

Choose an available CPU and unused output directory. The upstream build record preserves the original machine's recipe and identities; a fresh build may differ in toolchain identity.
