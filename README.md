# Goose to Wasm

**A fast, self-hosted [Goose](https://github.com/aardappel/goose) compiler built for rapid edit-compile-run development.**

Goose to Wasm compiles Goose directly to **WebAssembly** in milliseconds — with no C compiler in your inner loop — and compiles the same code to **native binaries or C libraries** when you are ready to ship.

- **Version:** [`v2026.4-1`](https://github.com/mewhhaha/goose-to-wasm/releases/tag/v2026.4-1) (targets upstream Goose `v2026.4`, revision `1`)
- **Compatibility:** `10,697 / 10,801` conformance rows (`99.0%`) · [Feature & compatibility tracker](docs/FEATURES.md)
- **Turnaround vs upstream C++ Goose:** **10× faster** `--check` on a 30k-LOC codebase (`0.36 s` vs `3.61 s`), **24×–31× faster** `-O2` builds to runnable WebAssembly (`2.1–6.9 ms` vs `60–174 ms`), and native `-O2` binaries within **1–3%** of upstream C++ Goose runtime speed.

---

## Quick Start

### Option 1: Download a prebuilt release (`v2026.4-1`)

Grab the prebuilt bundle from [Releases](https://github.com/mewhhaha/goose-to-wasm/releases/tag/v2026.4-1):

- **Linux x64 (native compiler + stdlib):** `goose-to-wasm-v2026.4-1-linux-x64.tar.gz`
- **Portable WebAssembly (macOS / Windows / Linux via Node or Wasmtime):** `goose-to-wasm-v2026.4-1-wasm.tar.gz`

```sh
tar -xzf goose-to-wasm-v2026.4-1-linux-x64.tar.gz
export PATH="$PWD/goose-to-wasm-v2026.4-1-linux-x64/bin:$PATH"
goose --version
# goose-to-wasm v2026.4-1 (Goose v2026.4)
```

### Option 2: Build from source

Requires Python 3 and a C compiler (`clang` default, or `gcc`), plus Node or Wasmtime to run `.wasm` output.

```sh
python3 scripts/bootstrap.py --verify
export PATH="$PWD/build/bin:$PATH"
```

### Everyday development workflow

```sh
# 1. Fast type & lifetime check (no codegen)
goose --check examples/sorting.goose

# 2. Instant dev compile to WebAssembly (no C compiler needed, 2–7 ms)
goose examples/squares.goose -O2 -o squares.wasm
node scripts/run_wasm.mjs squares.wasm
# sum=140

# 3. Compile & run as a native executable (via C)
goose examples/squares.goose --target c -O2 --run
# or with parallel C units & cached runtime:
python3 scripts/goose_wasm.py build examples/squares.goose --backend native -O2 -o squares
./squares

# 4. Embed Goose in a C/C++/Rust host (exports + C header, no -rdynamic/-ldl)
goose --emit-runtime goose_runtime.c
goose app.goose --header app.h -O2 -o app.c
```

See the [full CLI & build guide](docs/GUIDE.md) for `--shared`, `--wasm-memory64`, `--reachable-program`, `--stack-reserve`, and optional Wasmtime host & Binaryen compaction (`scripts/goose_wasm.py compact`).

---

## Benchmarks vs Upstream C++ Goose

All measurements below compare qualified **`goose-to-wasm v2026.4-1`** (`139b06db…`) against plain upstream C++ Goose (`d5ae5bb`, `GOOSE_CC=clang`, pre-warmed `GOOSE_HOME` runtime cache) across 5 alternating rounds pinned to CPU 7 (`clang 23.1.5`, `wasmtime 50.0.1`, `node v26.5.0`). [Full methodology, scripts, and raw JSON](bench/results/2026-11-24/release-v2026.4-1/README.md)

### 1. Large-project compile & check speed

On the compiler's own ~30k-LOC codebase (`selfhost/main.goose`), `v2026.4-1` checks in **`0.36 s`** (**10.0× faster** than upstream C++ Goose's `3.61 s`), emits portable `-O2` WebAssembly in **`0.50 s`** (**8.2× faster** than upstream's `4.06 s` C emit), and emits `-O2` C in **`0.73 s`** (**5.6× faster**). Even running **as portable WebAssembly** inside Wasmtime, it checks in `1.09 s` (**3.3× faster**) and self-compiles in `1.47 s` (**2.8× faster**). On the much larger class-keyed Blot2 compiler snapshots (`cb1e9e15` and `6ad5fbb`), `v2026.4-1` completes lifetime checking inside the default 2 GiB stack reserve in **`22.8 s`** and **`81.9 s`**, while plain upstream C++ Goose timed out past `180 s` (`--header`) and `240 s` (`check`).

![Compiler turnaround: goose-to-wasm v2026.4-1 vs upstream C++ Goose](bench/results/2026-11-24/release-v2026.4-1/compile_turnaround_vs_goose.svg)

### 2. Everyday edit-compile turnaround (8 real programs)

Because Direct Wasm skips the C compiler and linker completely, compiling real Goose programs (`squares`, `sieve`, `sudoku`, `vm`, `life`, `tour`, `maze`, `sorting`) to optimized `-O2` runnable WebAssembly takes **`2.1–6.9 ms`** — **24×–31× faster** than upstream `goose build -O2` (`60–174 ms`). Type and lifetime checking alone takes **`1.6–4.3 ms`** vs `1.8–19.7 ms` upstream (up to **4.6× faster** on `sorting`).

![Everyday dev turnaround on 8 Goose programs: Direct Wasm vs upstream C++ Goose](bench/results/2026-11-24/release-v2026.4-1/dev_build_examples_vs_goose.svg)

### 3. Runtime performance of compiled programs

Fast compilation does not trade away production speed. Native `-O2` executables emitted by `v2026.4-1` match upstream C++ Goose within **1–3%** (`sorting` `35.4 ms` vs `35.5 ms`, `sieve` `2.05 ms` vs `2.09 ms`, `mandelbrot` `2.42 s` vs `2.36 s`, all bit-exact). Direct Wasm modules run near-native in Wasmtime (`46.5 ms` on `sorting`, **`1.97 s`** on `mandelbrot`).

![Compiled program runtime: goose-to-wasm v2026.4-1 vs upstream C++ Goose](bench/results/2026-11-24/release-v2026.4-1/runtime_vs_goose.svg)

---

## Choosing a Target

| | Direct Wasm (`--target wasm-direct`, default) | Native C (`--target c` / `--backend native`) |
|---|---|---|
| **Best for** | Instant edit-run dev loops, browser/sandboxed tools, portable distribution | Maximum runtime speed, CLI tools, servers, C-host libraries |
| **Build time (examples)** | **2–7 ms** (zero C toolchain required) | `140–450 ms` (cached runtime + Clang/GCC) |
| **Build time (30k LOC)** | **0.50 s** | `0.73 s` C emit + parallel C compile |
| **Runtime speed** | Near-native in Wasmtime / `wtime-aot`; runs anywhere with Node or a browser | Matches upstream C++ Goose `-O2` within ~1–3% |
| **Features** | Full core language, root structs, `defer`, `const if`, memory32 & memory64 | Everything in Direct Wasm plus threads, `slice_pool`, `--header`, `--shared` |

---

## Compatibility & Versioning

Releases are versioned as **`v<goose-version>-<n>`** (currently **`v2026.4-1`**) so you can see which upstream Goose release is tracked while we ship incremental compiler and performance updates (`-2`, `-3`, ...).

- **Reference:** Plain upstream C++ Goose (`aardappel/goose`) is the language reference.
- **What works:** Core Goose language, generics, root structs, `defer`, `const if`, lifetime checking, stdlib (`std`, `os`, `json`, `math`, `binary`, `base64`, `vec`, `mat`, `quat`, `ascii`, `slice_pool` native, threads native), and the C-host `--header` / `--shared` / `--emit-runtime` interface (used end-to-end to build the Blot2 compiler).
- **Known differences:** `104` recorded gaps on the `10,801`-row conformance suite (mostly native GUI/audio/physics packages, `format`/`lsp` CLI subcommands, and a small number of edge cases) plus intentional rejections of two upstream false-accept lifetime bugs. See [docs/FEATURES.md](docs/FEATURES.md) for the complete table.

## Documentation

- [Guide & CLI options](docs/GUIDE.md) — building, running, compacting Wasm, optional Wasmtime host
- [Compatibility tracker](docs/FEATURES.md) — feature-by-feature status vs upstream Goose & Blot2 compatibility
- [Self-hosted compiler & bootstrap](selfhost/README.md) — architecture and fixed-point verification
- [Conformance & qualification](tests/README.md) — how changes are tested and qualified
- [Examples](examples/README.md) — runnable Goose sample programs

<details><summary>Historical benchmark archive</summary>

All dated compiler, runtime, Wasmtime, `wtime-aot`, native C codegen, and Blot2 studies live under [`bench/results/`](bench/results/):

- [Release `v2026.4-1` head-to-head vs upstream C++ Goose (2026-11-24)](bench/results/2026-11-24/release-v2026.4-1/README.md)
- [Blot2 class-keyed lifetime checker speedups — 3.6× `cb1e9e15`, 2.7× `6ad5fbb` (2026-11-24)](bench/results/2026-11-24/blot2-lifetime-speed/README.md)
- [Blot2 `l.alts` compaction & default-2 GiB `6ad5fbb` native build (2026-11-24)](bench/results/2026-11-24/blot2-alts-compaction-and-6ad5fbb/README.md)
- [C-host library interface & native Blot2 `cb1e9e15` build (2026-11-24)](bench/results/2026-11-24/blot2-chost-and-native-build/README.md)
- [Wasm compaction, dead mark elimination & `wtime-aot` safe Rust evaluation (2026-11-23)](bench/results/2026-11-23/wasm-peephole-wtime-aot-and-refresh/README.md)
- [Native C codegen gap closed vs upstream C++ Goose (2026-11-23)](bench/results/2026-11-23/native-c-codegen-gap/README.md)

</details>
