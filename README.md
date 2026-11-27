# Goose to Wasm

**A fast, self-hosted [Goose](https://github.com/aardappel/goose) compiler built for rapid edit-compile-run development.**

Compile Goose directly to **WebAssembly in milliseconds** — with no C compiler in your dev loop — and compile the exact same code to **native binaries or C libraries** when you ship.

**[Latest release: `v2026.4-6`](https://github.com/mewhhaha/goose-to-wasm/releases/tag/v2026.4-6)** (tracks upstream Goose `v2026.4`) · **[Play all 9 official Goose examples in your browser](https://mewhhaha.github.io/goose-to-wasm/)** (WebGL2 + Web Audio + JSPI) · **[Compatibility tracker](docs/FEATURES.md)**

| Metric | `goosew` (`v2026.4-6`, benchmarks on `v2026.4-5`) | Upstream C++ Goose |
|---|---|---|
| **Everyday `-O2` dev builds** | **`2–7 ms`** (Direct Wasm) | `51–177 ms` (**23×–26× slower**) |
| **Multi-core throughput (`--jobs`)** | **`2.01–2.32M LOC/s`** wall (bit-identical across threads) | Single-threaded |
| **Self-compilation (`selfhost/`, 47.4k LOC)** | **`0.26–0.28 s`** (`0.23–0.26 s` PGO) | `4.38–4.71 s` (**17×–19× slower**) |
| **Blot2 turnaround (`79.0k LOC`, edit → run)** | **`1.98 s`** cold · **`0.93 s`** edited (`.life` + Winch) | `30.6 s` Clang `-O0` · `98.8 s` `-O2` |
| **Upstream conformance** | **`10,792 / 10,801`** (`0` unexpected · `4` post-pin upstream deltas) | Sole language reference (no dialect fork) |

---

## Quick Start

### Option 1: Download a prebuilt release (`v2026.4-6`)

Every archive from [Releases](https://github.com/mewhhaha/goose-to-wasm/releases/tag/v2026.4-6) includes `goosew`, `stdlib`, `stdlib-web`, and `host/web`:

| Platform | Archive |
|---|---|
| Linux x64 | `goose-to-wasm-v2026.4-6-linux-x64.tar.gz` |
| macOS Apple Silicon | `goose-to-wasm-v2026.4-6-macos-arm64.tar.gz` |
| macOS Intel | `goose-to-wasm-v2026.4-6-macos-x64.tar.gz` |
| Windows x64 | `goose-to-wasm-v2026.4-6-windows-x64.zip` |
| Portable Wasm64 | `goose-to-wasm-v2026.4-6-wasm.tar.gz` · `goosew-v2026.4-6-wasm64.wasm` |

```sh
# Linux / macOS
tar -xzf goose-to-wasm-v2026.4-6-linux-x64.tar.gz
export PATH="$PWD/goose-to-wasm-v2026.4-6-linux-x64/bin:$PATH"
goosew --version
# goose-to-wasm v2026.4-6 (Goose v2026.4)
```

```powershell
# Windows (PowerShell)
Expand-Archive goose-to-wasm-v2026.4-6-windows-x64.zip -DestinationPath .
$env:PATH = "$PWD\goose-to-wasm-v2026.4-6-windows-x64\bin;$env:PATH"
goosew --version
```

```sh
# Portable Wasm64 compiler (runs anywhere Wasmtime runs)
python3 scripts/run_wasmtime.py goosew-v2026.4-6-wasm64.wasm -- --version
```

> **Binary name (`goosew`):** Named `goosew` so it does not collide with upstream C++ `goose` on your `PATH`. Symlink or rename it if you prefer `goose`.

### Option 2: Build from source (~41 s)

Requires Python 3 and a C compiler (`clang` default, or `gcc`), plus Node, Wasmtime, or [`host/wtime`](host/wtime/README.md) to run `.wasm` output.

```sh
python3 scripts/bootstrap.py --verify
export PATH="$PWD/build/bin:$PATH"
```

### Everyday commands

```sh
# 0. Built-in Goose language & CLI cheatsheet (for humans and coding agents)
goosew guide                  # or `goosew guide --cheatsheet`, `goosew guide --list`, `goosew guide <topic>`

# 1. Fast type & lifetime check (--error-format=json & --color supported)
goosew --check examples/sorting.goose

# 2. Instant dev compile & run via Direct Wasm (2–7 ms, no C toolchain)
goosew examples/squares.goose -O2 -o squares.wasm
node scripts/run_wasm.mjs squares.wasm
# sum=140

# 3. Ship a native binary (via C)
goosew examples/squares.goose --target c -O2 --run

# 4. Embed in a C/C++/Rust host (exports + C header, no -rdynamic/-ldl)
goosew --emit-runtime goose_runtime.c
goosew app.goose --header app.h -O2 -o app.c
```

See [docs/GUIDE.md](docs/GUIDE.md) for `--cache-dir`, `--jobs`, `--wasm-memory64`, `--library`, `--shared`, `--stack-reserve`, and Binaryen compaction.

---

## Benchmarks

### 1. Everyday dev loop

Skipping the C compiler and linker turns `-O2` builds on everyday Goose programs into single-digit milliseconds (`2–7 ms` vs `51–177 ms` upstream):

![Everyday dev loop: Goose to Wasm Direct Wasm vs upstream C++ Goose](bench/results/2026-11-25/release-v2026.4-5/everyday_dev_loop.svg)

### 2. Large real-world codebases

Combining `--jobs`, `--cache-dir` (whole-build + edited-file `.life` lifetime certificates), compacted Direct Wasm64, and [`goose-wasmtime --fast-jit`](host/rust/README.md) (Wasmtime 50.0.1 **Winch** baseline with automatic Cranelift fallback) turns half-minute to minute-and-a-half C rebuilds into **under 2 seconds cold** and **under 1 second on edits**:

![Large real-world Goose codebases: our own compiler and mewhhaha/blot2](bench/results/2026-11-27/four-levers-campaign/large_codebase_turnaround.svg)

| Codebase & scenario (`--jobs 8`, Ryzen 7 7800X3D) | Unprofiled | Fresh PGO\* | vs Upstream C++ |
|---|---:|---:|---|
| **`selfhost/`** (`47.4k LOC`) — `--check` | **`0.26 s`** | **`0.23 s`** | **16.9×–19.4×** vs `4.38 s` |
| **`selfhost/`** (`47.4k LOC`) — `-O0` / `-O2` Wasm64 | **`0.28 / 0.31 s`** | **`0.26 / 0.28 s`** | **15.1×–18.1×** vs `4.71 s` C |
| **`blot2`** (`79.0k LOC`) — cold `-O0` + Winch `--fast-jit` + run | **`1.98 s`** (`1.65 + 0.33 s`) | **`1.87 s`** (`1.54 + 0.33 s`) | **15×–53×** vs `30.6 / 98.8 s` |
| **`blot2`** (`79.0k LOC`) — edited `--cache-dir` + Winch + run | **`0.93–0.98 s`** | **`0.89–0.95 s`** | **31×–111×** vs `30.6 / 98.8 s` |
| **`blot2`** (`79.0k LOC`) — `--check` (cold / edited / unchanged) | **`1.51 s / 0.52 s / 43 ms`** | **`1.41 s / 0.50 s`** | **7.1×–21.5×** vs `10.73 s` |
| **`blot2`** (`79.0k LOC`) — warm `.cwasm` / safe-Rust `wtime` | **`71–135 ms`** / `1.83 s` | — | **16/16** `.blot` SHA-256 exact |

Blot2 emits **`8.34 MiB`** at `-O0` (`-62%` vs Nov 25, `332 MiB` Winch RSS) and **`12.79 MiB`** at `-O2` (`2.45 s` / `2.11 s` PGO cold turnaround). `selfhost/` also self-checks in `1.11–1.39 s` and self-compiles bit-identically in `1.78 s` as portable Wasm64.

```sh
# Compile Blot2 directly to Wasm64 (1.65 s cold · 0.59 s edited .life hit · 74 ms unchanged)
goosew compiler-goose/src/main.goose --stdlib blot-stdlib \
  --target wasm-direct --wasm-memory64 --wasm-max-pages 65536 \
  --library --reachable-program --expansion-node-limit 1000000 \
  --cache-dir build/goose-cache -O0 -o blot2.wasm

# Run via goose-wasmtime (0.33 s cold Winch --fast-jit + run · 71–135 ms warm .cwasm)
host/rust/target/release/goose-wasmtime --fast-jit blot2.wasm \
  --entry blot_goose_main --cache blot2.cwasm -- \
  build-project benchmarks/idiomatic/fibonacci.blot fib.wasm \
  --std-root std --prelude std/prelude.blot
```

### 3. Multi-core compiler throughput

`goosew` packs its AST into cache-line structures (`32 B Token`, `64 B Node`) and parallelizes I/O, parsing, typechecking, pure lifetimes, optimization, and Wasm/C emission (`--jobs auto` default) with **100% SHA-256 bit-identical output** across thread counts (`--jobs 1..16`):

![Compiler throughput: multi-core LOC/s scaling and real large codebases](bench/results/2026-11-26/compiler-throughput/compiler_throughput.svg)

| Workload (Ryzen 7 7800X3D, matched unprofiled Clang 23 `-O2`) | Wall Time | Throughput | Peak RSS |
|---|---:|---:|---|
| Procedural multi-file → Direct Wasm `-O0` (`98.7k` / `246.8k LOC`) | **`49.2 / 106.1 ms`** | **`2.01–2.32M LOC/s`** (`2.59M` compile) | **-36% to -55%** vs `v2026.4-3` |
| Procedural multi-file → Native C (`98.7k` / `246.8k LOC`, `--jobs auto`) | **`73.4 / 187.5 ms`** | **`1.32–1.35M LOC/s`** (**4.7×–4.9×**) | **-45% to -50%** on `selfhost` |
| `selfhost` (`47.4k`) & `blot2` (`79.0k`) Wasm64 vs `v2026.4-3` | `0.58 s` / `2.54 s` | **7.5×** (`selfhost`) · **6.4×** Wasm backend | Up to **-57%** lower peak RSS |

### 4. Production runtime speed

Fast dev builds do not trade away production speed. Native `-O2` binaries match or edge out upstream C++ Goose (all bit-exact), and Direct Wasm runs near-native in Wasmtime or ahead-of-time via [`wtime-aot`](https://github.com/mewhhaha/wtime) (`4.7–16.4 ms` zero-LLVM `x64` builds beating native `-O2` on `life`, `sieve`, and `maze`):

![Compiled program runtime: Goose to Wasm Native -O2, Wasmtime, and wtime-aot vs upstream C++ Goose](bench/results/2026-11-25/runtime-with-wtime/runtime_speed.svg)

*\*Separate fresh Clang-23 PGO reference runs are labeled explicitly. Full methodology, pinned SHAs, raw JSON, and preserved rejected experiments live in the [2026-11-27 four-levers report](bench/results/2026-11-27/four-levers-campaign/README.md), [compiler throughput study](bench/results/2026-11-26/compiler-throughput/README.md), [runtime study](bench/results/2026-11-25/runtime-with-wtime/README.md), and the [archive](#benchmark--evidence-archive) below.*

---

## Choosing a Target

| | Direct Wasm (`--target wasm-direct`, default) | Native C (`--target c` / `--backend native`) |
|---|---|---|
| **Best for** | Instant edit-run dev loops, large-project iteration, browsers/sandboxes | Production binaries, servers, maximum single-thread speed, C libraries |
| **Build time (examples)** | **2–7 ms** (no C compiler needed) | `135–440 ms` (cached runtime + Clang/GCC) |
| **Build time (32k LOC)** | **0.57 s** | **`0.62 s`** C emit + parallel C compile |
| **Runtime** | Near-native in Wasmtime (`host/rust`), safe-Rust `wtime` (`host/wtime`), or browsers | Matches or edges out upstream C++ Goose `-O2` |
| **Features** | Core language, root structs, `reusable[]` slice pools, `defer`, `const if`, `env.*` imports, memory32 & memory64 | Everything in Direct Wasm plus threads, stdlib `slice_pool` C externs, `--header`, `--shared` |

---

## Foreign C Functions as Wasm Host Imports

Goose `extern fn` declarations lower directly to standard WebAssembly imports in module **`"env"`** (`(import "env" "<name>" (func ...))`), so C-backed projects like [`mewhhaha/blot2`](https://github.com/mewhhaha/blot2) run in Wasm without changing Goose source:

```goose
extern fn host_add(a: i64, b: i64) -> i64;
export fn compute(x: i64) -> i64 { return host_add(x, 7) * 3; }
fn main() {}
```

```js
const noop = () => {};
const { instance } = await WebAssembly.instantiate(wasmBytes, {
  goose: new Proxy({}, { get: () => noop }),
  env: { host_add: (a, b) => a + b },
});
console.log(instance.exports.compute(5n)); // 36n
```

Supported Wasm ABI types: numerics (`i8`–`i64`, `u8`–`u64`, `f32`, `f64`), `bool`, slices (`T[:]`), and references (`T&` / `const T&`, including growable `u8[>..]&` via `goose.reserve`). Aggregates can be passed by `const T&`, `T[:]`, or out-reference `T&`.

---

## Diagnostics

Diagnostics include source snippets, `^~~~` carets, `--error-format=text|json`, `--color=auto|always|never`, generic/stdlib instantiation backtraces, consolidated missing `match` variants and struct fields, typo suggestions, and lifetime call stacks:

```text
app.goose:3:19: error: no overload matches this call's argument types and count: `add(i64, const u8[:])`
   3 | fn main() { print(add(1, "oops")); }
     |                   ^~~
  note: candidate `fn add(a: f64, b: f64) -> f64` at app.goose:2:4 (argument 2 `b`: got `const u8[:]`, expected `f64`)
  note: candidate `fn add(a: i64, b: i64) -> i64` at app.goose:1:4 (argument 2 `b`: got `const u8[:]`, expected `i64`)
```

---

## Compatibility & Documentation

Releases are versioned **`v<goose-version>-<n>`** (currently **`v2026.4-6`**) and strictly track upstream [Goose](https://github.com/aardappel/goose) as the sole language reference (`10,792 / 10,801` conformance rows passing, `0` unexpected failures, `6,017 / 6,022` native — all `4` post-pin upstream language/stdlib deltas documented in `tests/conformance/known-gaps.json`).

| Topic | Documentation |
|---|---|
| CLI flags, `--cache-dir`, targets & compaction | [docs/GUIDE.md](docs/GUIDE.md) |
| Native Rust Wasmtime host (Winch `--fast-jit`, `.cwasm`, Blot2 imports) | [host/rust/README.md](host/rust/README.md) |
| Safe-Rust `wtime` host (`#![forbid(unsafe_code)]`, Wasm32/Wasm64) | [host/wtime/README.md](host/wtime/README.md) |
| Browser runtime & drop-in `stdlib-web` (WebGL2, Audio, JSPI) | [host/web/README.md](host/web/README.md) · [stdlib-web/README.md](stdlib-web/README.md) |
| Upstream Goose & Blot2 compatibility tracker | [docs/FEATURES.md](docs/FEATURES.md) |
| Self-hosted compiler, Snapshot 75 seed & bootstrap | [selfhost/README.md](selfhost/README.md) |
| Conformance, qualification & runnable examples | [tests/README.md](tests/README.md) · [examples/README.md](examples/README.md) |
| Contributing, Code of Conduct & Security | [CONTRIBUTING.md](CONTRIBUTING.md) · [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) · [SECURITY.md](SECURITY.md) |

### Benchmark & evidence archive

<details><summary>All dated compiler, runtime, and Blot2 studies under <code>bench/results/</code></summary>

- [Four-levers optimization campaign — 1.87–1.98 s cold / 0.89–0.98 s edited Blot2 turnaround, `-62%` Wasm64 & Winch `--fast-jit` (2026-11-27)](bench/results/2026-11-27/four-levers-campaign/README.md)
- [Lifetime optimization campaign — 2.17–2.36 s Blot2 turnaround, 1.56–1.75 s emit & 0.24–0.26 s selfhost (2026-11-27)](bench/results/2026-11-27/lifetime-campaign/README.md)
- [Blot2 `98f277f2` turnaround campaign — 2.63–2.79 s total (`--fast-jit`, -57% Wasm64, parallel lifetimes & `--cache-dir`) (2026-11-27)](bench/results/2026-11-27/blot2-turnaround/README.md)
- [Multi-core compiler throughput campaign — 2.32M LOC/s wall, 2.59M LOC/s compile, 6.9× C backend & 7.5×–8.2× selfhost (2026-11-26)](bench/results/2026-11-26/compiler-throughput/README.md)
- [Production runtime speed with `wtime-aot` `v0.1.5` (`x64` & safe Rust) (2026-11-25)](bench/results/2026-11-25/runtime-with-wtime/README.md)
- [Release `v2026.4-5` qualification & chart provenance (2026-11-25)](bench/results/2026-11-25/release-v2026.4-5/README.md)
- [Blot2 HEAD `98f277f2` Direct Wasm64 + fast `goose-wasmtime` & `goose-wtime` turnaround (2026-11-25)](bench/results/2026-11-25/blot2-head-98f277f2/README.md)
- [Release `v2026.4-4` head-to-head vs `v2026.4-3` & upstream C++ Goose (2026-11-25)](bench/results/2026-11-25/release-v2026.4-4/README.md)
- [Direct Wasm64 codegen speedups & preserved rejected experiments (2026-11-25)](bench/results/2026-11-25/wasm64-codegen/README.md)
- [Direct Wasm64 Blot2 (`cb1e9e15`) on pure-Rust `wtime` — 18/18 bit-exact (2026-11-25)](bench/results/2026-11-25/blot2-wtime-wasm64/README.md)
- [Release `v2026.4-3` head-to-head vs `v2026.4-2` & upstream C++ Goose (2026-11-25)](bench/results/2026-11-25/release-v2026.4-3/README.md)
- [Blot2 lifetime checker algorithmic redesign — 7 rounds & ablations (2026-11-25)](bench/results/2026-11-25/blot2-lifetime-algo/README.md)
- [Release `v2026.4-2` head-to-head vs `v2026.4-1` & upstream C++ Goose (2026-11-24)](bench/results/2026-11-24/release-v2026.4-2/README.md)
- [Release `v2026.4-1` head-to-head vs upstream C++ Goose (2026-11-24)](bench/results/2026-11-24/release-v2026.4-1/README.md)
- [Blot2 class-keyed lifetime checker speedups (2026-11-24)](bench/results/2026-11-24/blot2-lifetime-speed/README.md)
- [Blot2 `l.alts` compaction & default-2 GiB `6ad5fbb` native build (2026-11-24)](bench/results/2026-11-24/blot2-alts-compaction-and-6ad5fbb/README.md)
- [C-host library interface & native Blot2 `cb1e9e15` build (2026-11-24)](bench/results/2026-11-24/blot2-chost-and-native-build/README.md)
- [Wasm compaction, dead mark elimination & `wtime-aot` evaluation (2026-11-23)](bench/results/2026-11-23/wasm-peephole-wtime-aot-and-refresh/README.md)
- [Native C codegen gap closed vs upstream C++ Goose (2026-11-23)](bench/results/2026-11-23/native-c-codegen-gap/README.md)

</details>
