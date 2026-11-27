# Snapshot 75 · 2026-11-27 (`v2026.4-6`)

The checked-in C bootstrap seed and Clang 23 PGO profile are frozen at the fixed point of the `v2026.4-6` release (`selfhost/driver.goose`: `GOOSE_TO_WASM_VERSION = "v2026.4-6"`, replacing Snapshot 74 `3d8886f9…`, 2026-11-27).

Changes from Snapshot 74 to Snapshot 75:
- **Built-in `goosew guide` cheatsheet & idioms reference (`dfbd5d5`, `28af4a8`, `b3bebf8`, `596d629`, `08f8035`):**
  - `selfhost/guide.goose`, `selfhost/driver.goose`: added version-matched `goosew guide [topic|--cheatsheet|--list]` covering top rules, types, structs/`root struct`/enums, refs/lifetimes, control flow/modules, stdlib, CLI workflows, and idiomatic Goose patterns (`goosew guide idioms`).
- **Direct Wasm `stdlib/slice_pool` externs & `os::trim_memory` (`b868afb`):**
  - `selfhost/codegen.goose`: lowered `gs_slice_pool_{place,free,regrow,trim}` to 11 checked internal Wasm B+ span-tree helpers (validating bounds, counts, height, and cycles, aborting `"slice pool span tree is corrupt"` at the caller's line via `F_LOCATED`, zeroing interior 4096-byte pages via `memory.fill` in `trim`) and lowered `os::trim_memory` (`gs_trim_memory`) inline as a Direct Wasm intrinsic returning `true` with zero extra host imports. All 20 single-threaded `stdlib_slice_pool*` tests, `codegen/root_defer`, `codegen/root_loaded_aliases`, and `runtime/trim_memory*` now pass on Direct Wasm across `-O0`, `-O2`, and `--wasm-memory64`.
- **Run-based `checkfree` judgment & upstream `1838de4` stdlib sync (`510bb71`):**
  - `selfhost/checker.goose`, `selfhost/checker_validation.goose`, `selfhost/optimizer.goose`: replaced the syntactic callee-annotation rule with transitive call-graph bounds-check judgment and call-chain diagnostics matching upstream `1838de4`, plus constant-range `for`-loop guards and array/string/`bytes_of` `LenMin` facts.
  - `stdlib/{mat,quat,binary,math,os,regex,std}.goose` & `stdlib-web/` mirrors: synced to upstream `1838de4` (keeping `stdlib/json.goose` at `2e2bede` for `host/wtime` compatibility), added inline Direct Wasm `copysign`/`copysignf` and `gs_byte_swap{16,32,64}` intrinsics, and wired `gs_os_random_bytes`, `gs_os_read_stdin_max`, `gs_f64_digits`, and the 8 `f32` math externs across native C and Wasm hosts (`scripts/run_wasm.mjs`, `scripts/run_wasmtime.py`, `host/rust/`).
- **Deprecation & decided-comparison warnings (`7c3dd24`):**
  - `selfhost/{model,parser,sources,checker,codegen,driver,guide}.goose`: added non-fatal `Program.warnings` (`severity = 0`) emitted in text and `--error-format=json` (exiting 0 on warning-only builds and bypassing whole-build `--cache-dir` writes when warnings are present); emits upstream `1838de4` diagnostics for `deprecated ["msg"]` calls/UFCS/all-deprecated function values (skipping stdlib call sites and indirect calls) and non-generic decided integer ordering comparisons. Replaced 8 deprecated `copy_into` calls in `selfhost/codegen.goose` with `copy_from` so self-compilation emits zero warnings.
- **Release packaging & documentation (`v2026.4-6`):**
  - `selfhost/driver.goose`: bump `GOOSE_TO_WASM_VERSION` from `"v2026.4-5"` to `"v2026.4-6"`.
  - `.github/workflows/release.yml`, `.github/ISSUE_TEMPLATE/bug_report.yml`, `README.md`, `docs/FEATURES.md`, `selfhost/README.md`: update release references to `v2026.4-6` and Snapshot 75.

| Item | Identity |
| --- | --- |
| Seed C | `98d7e8174bc8ea50dd9315bfd7d19ecd088c4038e550f30b35b0a223f65dd881` (`39,218,026 B`, fixed point from Snapshot 74's seed `3d8886f9…`) |
| Compressed seed | `seed.c.gz` (`6,144,325 B`) |
| Profile | Clang 23, `x86_64-pc-linux-gnu`, data `2b1711b311b762f44bf752e7f3b001714952fd9ecdb2d78feb511053df20829b` (`1,018,600 B`) |
| Executable with profile | `5be3bccd67a99b27afb0cf2bc289f3f09ad11f461e4d76518275f257f64160a6` |
| Executable without profile | `ed907022b67e689417058ba709bca1245e4ed1c749597c86b66d9e7919bf7d5e` |

**Profile.** Trained with the `_Exit`-wrapped instrumentation protocol (`-fprofile-instr-generate`, `-Wl,--wrap=_Exit`, Clang 23) using non-timed compiler workloads only: self-compiling `selfhost/main.goose` (`--target native -O2`, `--target wasm-direct --wasm-memory64 -O2`, `--target wasm-direct --wasm-bundled-host -O2`, `--check`) plus 4 positive contract fixtures (`literal-parameters/adapt`, `root-struct/owner`, `slice-pool/spans` native, `defer/forms`) weighted 32 each. None of the timed benchmark programs or Blot2 snapshots was used in training.

**Public roots.** `scripts/bootstrap.py --verify` ran twice without caching: with defaults (`57.6 s`: `56.93 s` C build + `0.64 s` self-host verify) and with explicit options (`55.9 s`: `55.24 s` C build + `0.64 s` self-host verify). Both report `seed_matches_sources: true`, `fixed_point: true`, and `profile_used: true`, and both build `5be3bccd…` (`goose-to-wasm v2026.4-6 (Goose v2026.4)`). Release smoke checks (including `goosew guide`, `--stdlib stdlib-web` demo, and 65536-page portable Wasm64 `goosew.wasm`, `6,856,850 B`, compiling `examples/squares.goose` -> `sum=140`) passed. [Explicit](bootstrap-explicit.json) · [Default](bootstrap-default.json)

**Qualification.** `scripts/qualify.py --output-dir build/qualify-release-v2026.4-6 --baseline build/qualify-warnings/bootstrap/bin/goosew` passed all stages in `171.4 s` using the profiled executable `5be3bccd…` (`bootstrap` `55.7 s`, `profile_used: true`, `10,792/10,801` conformance with 0 unexpected failures, `4,771/4,779` memory64 with 0 unexpected failures, `54/54` native checks, `10,061/10,061` equivalence with `0` differing, `164` unit tests exit 0). [Summary](qualification.json)
