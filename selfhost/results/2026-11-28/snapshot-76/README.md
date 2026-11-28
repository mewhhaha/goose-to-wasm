# Snapshot 76 · 2026-11-28 (`v2026.4-7`)

The checked-in C bootstrap seed and Clang 23 PGO profile are frozen at the fixed point of the `v2026.4-7` release (`selfhost/driver.goose`: `GOOSE_TO_WASM_VERSION = "v2026.4-7"`, replacing Snapshot 75 `98d7e817…`, 2026-11-27).

Changes from Snapshot 75 to Snapshot 76:
- **`wtime-aot` standalone targets, hosted `goose-wtime-aot`, and `--runner` selection (`e0d95bd`, `36ba051`, `1fae285`):**
  - `selfhost/driver.goose`: added `--target aot-x64`, `--target aot-aarch64`, `--runner auto|wasmtime|winch|wtime-aot|wtime-aot-fast|wtime|node`, allowed `--cache-dir` with `--target wasm-direct --run`, and auto-wired `--inc-cache <cache-dir>/wtime-aot-inc` into `goose-wtime-aot` O2 runs (including on full artifact cache hits).
  - `host/wtime-aot/`: added native zero-LLVM x86-64 `wtime-aot-host` (`StoreCdylib`) runner supporting full 84-import Blot2 and 24-import `selfhost`, with `--fast`, `--cache`, `--inc-cache DIR` per-function incremental caching, and `--timing-json`.
- **Direct Wasm codegen, local-reuse peephole, stronger BCE & `cg_slice` check elision (`7a97826`, `1fae285`):**
  - `selfhost/codegen.goose`, `selfhost/wasm.goose`, `selfhost/optimizer.goose`: emitted constant fixed scalar arrays (`len >= 4`, e.g. `stdlib/std.goose` Ryu tables) into deduplicated static data segments copied via `memory.copy` (`-33%` to `-69%` smaller `-O2` `.wasm`), dropped redundant shift masks and constant-divisor trap guards, lowered clean loop `if`/`guard` exits directly to `br_if`, hoisted publication marks, deleted post-slot-reuse self-copies/self-tees, strengthened `A_FIXED` and `while`/slice-alias BCE, and elided tautological `cg_slice` checks (`xs[..]`, `xs[..end]`, `xs[start..]`).
- **Sub-second Blot2 `.life` caching & `LifeFp` compaction (`6c61872`):**
  - `selfhost/driver.goose`, `selfhost/checker_lifetimes.goose`: restored `.life` lifetime certificate writes when non-fatal warnings are present (keeping whole-artifact writes gated on zero warnings), always emitted `"life_cache_hit"` in `--wasm-stats`, compacted `LifeFp` node-indexed arrays (`-23 MiB` peak working set on Blot2), packed sponge fields (`GOOSEW_LIFE_FP_V2`), skipped redundant inert-effect walks, and used O(1) `l.type_flags` on `.life` hits (`12×` faster Blot2 lifetimes: `1,238 → 102 ms`; end-to-end edited Blot2 → O2 native x64 run `0.74–0.86 s`).
- **Release packaging & documentation (`v2026.4-7`):**
  - `selfhost/driver.goose`: bump `GOOSE_TO_WASM_VERSION` from `"v2026.4-6"` to `"v2026.4-7"`.
  - `.github/workflows/release.yml`, `.github/ISSUE_TEMPLATE/bug_report.yml`, `README.md`, `selfhost/README.md`, `host/wtime-aot/README.md`: update release references to `v2026.4-7` and Snapshot 76, plus dated report & SVG charts in [`bench/results/2026-11-28/blot2-subsecond-and-wtime-aot/`](../../../bench/results/2026-11-28/blot2-subsecond-and-wtime-aot/README.md).

| Item | Identity |
| --- | --- |
| Seed C | `c58238e3b83131e9ea0638da7d026e1644b2ae5ab0d53cb2ed9ee3be14be0f90` (`39,267,575 B`, fixed point from Snapshot 75's seed `98d7e817…`) |
| Compressed seed | `seed.c.gz` (`6,145,580 B`) |
| Profile | Clang 23, `x86_64-pc-linux-gnu`, data `a2d496b422f4d613ea22f3eb63f8fd2eff734f5e92530bb8e873845e0f7bdffc` (`1,023,832 B`) |
| Executable with profile | `fea9dcc69116f119f5ff655a0c9eaaa1ec11c3c6d171b69b12fdd76d3a2ba200` |
| Executable without profile | `2f45ad7bc9e733e1e8acc80649e578fde293525d0cdb872596dcdca1ab2c82fc` |

**Profile.** Trained with the `_Exit`-wrapped instrumentation protocol (`-fprofile-instr-generate`, `-Wl,--wrap=_Exit`, Clang 23) using non-timed compiler workloads only: self-compiling `selfhost/main.goose` (`--target native -O2`, `--target wasm-direct --wasm-memory64 -O2`, `--target wasm-direct --wasm-bundled-host -O2`, `--check`) plus 4 positive contract fixtures (`literal-parameters/adapt`, `root-struct/owner`, `slice-pool/spans` native, `defer/forms`) weighted 32 each. None of the timed benchmark programs or Blot2 snapshots was used in training.

**Public roots.** `scripts/bootstrap.py --verify` ran twice without caching: with defaults (`55.4 s`) and with explicit options (`47.1 s`). Both report `seed_matches_sources: true`, `fixed_point: true`, and `profile_used: true`, and both build `fea9dcc6…` (`goose-to-wasm v2026.4-7 (Goose v2026.4)`). [Explicit](bootstrap-explicit.json) · [Default](bootstrap-default.json)

**Qualification.** `scripts/qualify.py --output-dir build/qualify-release-v2026.4-7 --baseline build/qualify-slice-and-inc/bootstrap/bin/goosew` passed all stages in `159.0 s` using the profiled executable `fea9dcc6…` (`bootstrap` `52.8 s`, `profile_used: true`, `10,790/10,801` conformance with `0` unexpected failures, `4,771/4,779` memory64 with `0` unexpected failures, `54/54` native checks, `10,061/10,061` equivalence with `0` differing, all unit tests exit 0). [Summary](qualification.json)
