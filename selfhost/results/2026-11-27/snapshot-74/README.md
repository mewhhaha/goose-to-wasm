# Snapshot 74 · 2026-11-27 (`v2026.4-5`)

The checked-in C bootstrap seed and Clang 23 PGO profile are frozen at the fixed point of the `v2026.4-5` release (`selfhost/driver.goose`: `GOOSE_TO_WASM_VERSION = "v2026.4-5"`, replacing Snapshot 73 `e07b8af4…`, 2026-11-27).

Changes from Snapshot 73 to Snapshot 74:
- **Lifetime analysis optimization campaign (`b75c334`, `9ca5ad7`, `b8a361e`):**
  - Lowered `LIFE_CONCRETE_FRAMES` (`4096 → 256`), added dense 64-bit holder-global bitsets (`holder_glob_idx`/`body_glob_bits` via Tarjan SCCs), future-global shrink caches, Discovery→Validation signature reuse, parallel `life_prepare_nodes` body scans, tightened clean checks, and adaptive-sized L1 caches (`256–512` slots / `≤ 16 KiB` for small programs so default 256-page portable Wasm64 `goosew.wasm` stays well within region bounds, full `2048–16384` slots for large codebases).
  - Cut `selfhost/` lifetime stage by `58–62%` (`1.68×–1.95×` faster total self-compile) and Blot2 lifetime stage by `22–25%` ([dated evidence](../../../bench/results/2026-11-27/lifetime-campaign/README.md)).
- **Non-lifetime typechecking speedups (`0e5e241`):**
  - `selfhost/checker.goose`: derived-type interning, slimmed effect/root tables, and fast overload selection cutting Blot2 non-lifetime typechecking by `30–35%` and compile peak RSS by `20–23%` (`1,047 → 833 MiB` `-O0`, `1,005 → 770 MiB` `--check`).
- **Sound edited-file incremental lifetime certificates (`0496493`):**
  - `selfhost/cache.goose`, `selfhost/checker_lifetimes.goose`, `selfhost/driver.goose`: content-addressed `l_<fp_hex>.life` lifetime certificates under `--cache-dir` keyed on a canonical edit-position-independent lifetime skeleton (`life_cache_hit` in `--wasm-stats`), cutting Blot2 edited-file lifetime analysis `~11×` (`1,147–1,232 → 104–123 ms`) and full edited-file `--check` to `0.50–0.52 s` while preserving exact 24 Wasm64 imports (`tests/test_incremental_cache.py`, 10/10 including adversarial soundness checks).
- **`-O0` Wasm64 helper compaction & Wasmtime Winch `--fast-jit` (`7c75334`, `f594513`):**
  - `selfhost/codegen.goose`: `4 B` `i64.const 0; i64x2.splat` for `v128` zeroing and `-O0` out-of-line aggregate resolve+copy & slice resolution helpers, cutting Blot2 `-O0` Wasm64 `9.45 → 8.34 MiB` (`-11.8%`, `-61.8%` vs Nov 25) and `-O2` `13.07 → 12.79 MiB`.
  - `host/rust/`: enabled Wasmtime 50.0.1 `Strategy::Winch` baseline compiler in `goose-wasmtime --fast-jit` with automatic Cranelift `OptLevel::None + SinglePass` fallback and separate `winch-fast-jit:` / `cranelift-fast-jit:` `.cwasm` stamps, dropping cold Blot2 `-O0` JIT + `fibonacci.blot` run `611 → 335 ms` (`332 MiB` RSS) — reaching **`1.87–1.98 s`** cold and **sub-second `0.89–0.98 s`** edited-file Blot2 turnaround with `18/18` `.blot` bit-exact parity ([dated evidence](../../../bench/results/2026-11-27/four-levers-campaign/README.md)).
- **Release packaging & documentation (`v2026.4-5`):**
  - `selfhost/driver.goose`: bump `GOOSE_TO_WASM_VERSION` from `"v2026.4-4"` to `"v2026.4-5"`.
  - `.github/workflows/release.yml`, `.github/ISSUE_TEMPLATE/bug_report.yml`, `README.md`, `docs/GUIDE.md`, `docs/FEATURES.md`, `docs/TARGET.md`, `selfhost/README.md`: update release links/examples to `v2026.4-5`, build portable `goosew-v2026.4-5-wasm64.wasm` with `--wasm-max-pages 65536`, and document `--cache-dir` `.life` certificates and Winch `--fast-jit`.

| Item | Identity |
| --- | --- |
| Seed C | `3d8886f91bbaae7314f13cfc32735eef689c3888c5409732ee78a35279e3a136` (`37,833,059 B`, fixed point from Snapshot 73's seed `e07b8af4…`) |
| Compressed seed | `seed.c.gz` (`5,903,868 B`) |
| Profile | Clang 23, `x86_64-pc-linux-gnu`, data `388e3f14817213903a4705f7650bda183eced296da0ce40b60112156b1ad7243` (`999,304 B`) |
| Executable with profile | `0f3db530e526d9b527c06c7714c3e318a493f075ea66f6dcafbdbd917404bf8a` |
| Executable without profile | `6eb3092d93357c6c86003030a632669b62d32f66117929bde6cbb78e748bf151` |

**Profile.** Trained with the `_Exit`-wrapped instrumentation protocol (`-fprofile-instr-generate`, `-Wl,--wrap=_Exit`, Clang 23) using non-timed compiler workloads only: self-compiling `selfhost/main.goose` (`--target native -O2`, `--target wasm-direct --wasm-memory64 -O2`, `--target wasm-direct --wasm-bundled-host -O2`, `--check`) plus 4 positive contract fixtures (`literal-parameters/adapt`, `root-struct/owner`, `slice-pool/spans` native, `defer/forms`) weighted 32 each. None of the timed benchmark programs or Blot2 snapshots was used in training.

**Public roots.** `scripts/bootstrap.py --verify` ran twice without caching: with defaults (`41.8 s`: `41.32 s` C build + `0.48 s` self-host verify) and with explicit options (`41.3 s`: `40.77 s` C build + `0.51 s` self-host verify). Both report `seed_matches_sources: true`, `fixed_point: true`, and `profile_used: true`, and both build `0f3db530…` (`goose-to-wasm v2026.4-5 (Goose v2026.4)`). Release smoke checks (including `--stdlib stdlib-web`, default 256-page portable Wasm64 smoke, and 65536-page portable Wasm64 `goosew.wasm`, `6,434,577 B`, exact 24 Wasm64 imports) passed. [Explicit](bootstrap-explicit.json) · [Default](bootstrap-default.json)

**Qualification.** `scripts/qualify.py --output-dir build/qualify-release-v2026.4-5 --baseline build/qualify-lever4/bootstrap/bin/goosew` passed all stages in `119.4 s` using the profiled executable `0f3db530…` (`bootstrap` `43.1 s`, `profile_used: true`, `10,797/10,801` conformance with 0 unexpected failures, `4,773/4,779` memory64 with 0 unexpected failures, `54/54` native checks, `10,061/10,061` equivalence with `0` differing, `158` unit tests exit 0). [Summary](qualification.json)
