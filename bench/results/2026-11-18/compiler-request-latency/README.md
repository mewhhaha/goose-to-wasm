# Cold and hot builds with our Goose compiler

The native build of our compiler emitted its own Wasm in **2.67 s**. Running the same compiler in Wasmtime took **14.54 s** in a fresh process and **6.71 s** with the engine and compiled module already resident. Hot compilation after changing one line of compiler source took **6.93 s**.

![Seconds to emit the complete compiler in native and Wasmtime processes](latency.svg)

| End-to-end wall time | Unchanged source | One-line edit |
| --- | ---: | ---: |
| Native compiler, new process | 2.67 s | 2.59 s |
| Wasmtime, new process and empty compilation cache | 14.54 s | — |
| Wasmtime, same process and prepared module | 6.71 s | 6.93 s |

The input and compiler are both revision `4e9b78e`. Each row uses three observations on CPU 7 with warm filesystem pages. Cold Wasmtime includes starting the Python host, compiling the memory64 compiler module with Cranelift on one CPU, and writing the complete result. Each hot request starts a fresh guest instance and recompiles from source. The edit changes the compiler's command-line help text. Every unchanged build reproduced the original 8,873,765-byte compiler module. Every edited build matched a fresh native compile of the edited sources and differed from the original. Validation ran outside the timer. [Samples, source and artifact hashes](self-emit.json)

## Compiling Gdev

Gdev is written in Blot. To time it with our toolchain, we first need a working Blot compiler built from its Goose sources. We tried Blot `cb1e9e15`, the release that built Gdev `0e0d772`. All probes below used the Goose standard library selected by Blot's release build. The Blot sources came from a Git archive.

- **Reachable entry point.** Our native compiler rejected the exported Blot entry point and its dependencies with 33 lifetime diagnostics. Of these, 32 concern references written to longer-lived storage. The first occurs in `check/package_core.goose` at line 728. [Reachable diagnostics](blot-reachable.txt)
- **Whole library.** Native-C and direct-Wasm emission both stopped at the same 25 type-checking diagnostics, including 16 uses of `index_of` on slices. Neither produced a compiler. Blot exports its entry point for a C host. Using `--library` exercises additional functions beyond those in the reachable check. [Library diagnostics](blot-library.txt)
- **Our compiler inside Wasmtime.** The default memory64 compiler exhausted a region during whole-library emission. The experimental memory32 retry policy recovered enough space to reach the same 25 diagnostics. In the separate reachable check, it hit the eight-attempt limit. These failures precede Gdev compilation. [Commands, stdlib hashes and outcomes](blot-builds.json)

The 1.69 s experimental memory32 result measures parsing an earlier frozen Blot compiler. Gdev compilation and Wasm emission are separate workloads. [Parse benchmark](../compiler-region-recovery/README.md)

## Reproduce

From the repository root, build a frozen compiler stage at `4e9b78e` with the [self-host harness](../compiler-array-views/README.md#verification-and-reproduction). Supply that stage and a fresh output directory to the benchmark. It checks the frozen sources and module hashes before accepting timings.

```sh
.venv/bin/python bench/results/2026-11-18/compiler-request-latency/self_emit.py \
  . "$COMPILER_STAGE" build/self-emit-cold-hot
```

For the Blot probe, archive `compiler-goose/src` from Blot commit `cb1e9e15`, then from inside that directory run the native compiler on `main.goose` with `--stdlib "$BLOT_GOOSE_STDLIB" --reachable-program --expansion-node-limit 1000000 --check`. The recorded stdlib file hashes identify Blot's selected upstream precision build. The full-library runs add `--library` and select an output target in place of `--check`.
