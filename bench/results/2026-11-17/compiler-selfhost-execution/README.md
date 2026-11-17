# Building and running the Goose-to-Wasm compiler · 2026-11-17

The workload is `selfhost/main.goose` with the compiler modules, standard library and native support files frozen at `38826b425b68eebb6593ec9ff366a0de08723bf2`. The starting compiler is the qualified release executable with SHA-256 `6dc908de22b44263c36c7f8b31b6c44047df1e126cf465a71ee527116e7f1030`. [Release receipt](../compiler-and-row-performance/runs/bootstrap.json) · [Raw samples and identities](measurements.json) · [Chart values and hashes](chart.json)

## Build the compiler

Both builds start from the frozen source with a fresh output and use Goose `-O2`. The native path emits C, compiles eight program units and a runtime unit with Clang 23.1.5 `-O2`, and links an executable. It uses CPUs 1–5 and disables the runtime object cache. The direct path emits a memory64 module with a 262,144-page limit on CPU 6. The OS file cache stays warm.

| Build from source | Median wall time | Range |
| --- | ---: | ---: |
| Native via C and Clang | 32.10 s | 31.18–32.36 s |
| Direct Wasm | 4.24 s | 4.19–4.33 s |

The native build spent a median 3.71 s emitting C, 28.18 s compiling the units and 0.08 s linking. These phase medians are taken independently. All three interleaved pairs reproduced the same native, C and Wasm artifacts.

## Execute on the same project

The three paths run the same compiler sources on CPU 6 of a shared Ryzen 7 3800X host. Each does a warmup check, then three measured rounds rotate the engine order for each workload. Each native run starts a new executable process. Wasmtime 50.0.1 and V8 13.6.233.17-node.58 prepare the same module once and create a fresh instance for each run. The Wasm bars measure `_start`, including source reads, compiler work and any output writes.

| Workload | Native | Wasmtime | V8 |
| --- | ---: | ---: | ---: |
| Check project | 2.74 s | 13.09 s | 14.36 s |
| Emit `compiler.wasm` | 4.01 s | 19.44 s | 20.51 s |

These are medians of three wall times per cell. Wasmtime took about 4.8× the native time for both workloads. V8 took 5.1–5.2×. Every run succeeded with matching stdout and stderr. All nine self-compilations reproduced the 25,664,686-byte input module with SHA-256 `cee17ed5f2ada79ac52e7381d23456829281f27bf780601824cd3fb397c41e32`.

Wasmtime uses the hosted configuration with Cranelift speed optimization. V8 uses Node 24.22.1 with eager TurboFan compilation (`--no-liftoff --no-wasm-lazy-compilation`). One-time preparation took 41.89 s for Wasmtime on CPU 6 and 38.75 s for V8 on CPUs 1–5. The execution bars exclude preparation and instantiation. An initial one-CPU V8 preparation trial stopped after two minutes while it was still compiling. The execution samples come from the complete rerun after a tool session interrupted the first campaign.

## Upstream Goose

Plain upstream Goose at both `d92c4315` and `ee261a4` reached semantic checking and reported the same 31 lifetime errors on the frozen project. The first is at `checker.goose:1195`, where `check_type` may shrink `p` while the assignment still uses a projection into it. Both builds ended before producing a compiler executable. The native bars use the same Goose-to-Wasm compiler as the Wasm bars, built by its C backend. [Upstream invocations and diagnostics](upstream-native.json) · [Full compiler log](upstream-native.log)

## Reproduce

Run from the repository root with Python 3.14, Wasmtime 50.0.1 bindings, Node 24.22.1, Clang 23.1.5, Matplotlib and the pinned starting compiler. Choose CPU sets available on your machine.

```sh
python3 bench/selfhost_comparison.py build build/selfhost-replay \
  --commit 38826b425b68eebb6593ec9ff366a0de08723bf2 \
  --emitter build/bin/goose --cc clang-23 --build-cpus 1-5 --cpu 6 --jobs 8 --rounds 3
python3 bench/selfhost_comparison.py run build/selfhost-replay --cpu 6 --rounds 3
python3 bench/selfhost_charts.py build/selfhost-replay/measurements.json \
  --output-dir build/selfhost-replay --receipt build/selfhost-replay/chart.json
```
