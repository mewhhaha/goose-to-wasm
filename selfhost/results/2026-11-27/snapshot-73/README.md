# Snapshot 73 · 2026-11-27 (`v2026.4-4`)

The checked-in C bootstrap seed and Clang 23 PGO profile are frozen at the fixed point of the `v2026.4-4` release (`selfhost/driver.goose`: `GOOSE_TO_WASM_VERSION = "v2026.4-4"`, replacing Snapshot 72 `2cbb0966…`, 2026-11-26).

Changes from Snapshot 72 to Snapshot 73:
- **Deterministic multi-core compiler pipeline (`322fb80`, `3d2782e`, `245f9d6`, `ca9e1b3`, `704ab25`, `f351a13`, `b7d0915`, `a5abb23`):**
  - `selfhost/parallel.goose` & `native/compiler_parallel.h`: deterministic `--jobs` native worker pool (`100%` `--jobs 1 == --jobs 8` SHA-256 bit-identity) across source I/O, lex/parse, checker, pure lifetimes, optimizer, direct Wasm emission, and Native C emission (`2.32M LOC/s` on 8 cores).
  - Compact 32 B `Token` and 64 B `Node` layout with lazy column tracking and sparse `NodeExtra`, plus elimination of `O(T^2)` per-type allocations in the C backend.
- **Direct Wasm de-bloating & runtime fast-JIT (`a0ff3b3`, `7970825`):**
  - `selfhost/wasm.goose`: cut Blot2 direct Wasm64 output size by `56.7%` at `-O0` (`21.84 → 9.45 MiB`) and `58.9%` at `-O2` (`31.84 → 13.07 MiB`) via compact zero-init loops, call-site helper deduplication, and slimmer Wasm emission.
  - `host/wtime` (`goose-wasmtime --fast-jit`): Winch/fast-JIT execution path cutting Blot2 Wasmtime compile-and-load from `3.30 s` to `0.62 s`.
- **Lifetime analysis & checker speedups (`8af72fa`, `a6a4574`, `7970825`, `a0ff3b3`, `8b3b865`):**
  - Bounded lifetime span & reachable future global caching (`7×` selfhost lifetime speedup), memoized `life_gs_holder`/`life_holder_views`, `SIGPROF`-guided lifetime/checker hot-path optimizations, and parallel `life_prepare_nodes` (cutting cold Blot2 `-O0` + `--fast-jit` turnaround from `6.24 s` to `2.79 s` unprofiled / `2.63 s` PGO; [dated evidence](../../../bench/results/2026-11-27/blot2-turnaround/README.md)).
- **Sound content-addressed incremental build cache (`e8a7ed1`):**
  - `selfhost/cache.goose`: `--cache-dir <dir>` SHA-256 keying across compiler binary identity, target/opt/flags, entry + transitive imports/embeds, and outputs (`40.6 ms` warm Blot2 `--check` hit, `71.0 ms` `-O0` hit; exact 24 Wasm64 imports preserved on `selfhost/main.goose`).
- **Release packaging (`v2026.4-4`):**
  - `selfhost/driver.goose`: bump `GOOSE_TO_WASM_VERSION` from `"v2026.4-3"` to `"v2026.4-4"`.
  - `README.md`, `.github/workflows/release.yml`, `.github/ISSUE_TEMPLATE/bug_report.yml`: update prebuilt release links and version examples to `v2026.4-4`.

| Item | Identity |
| --- | --- |
| Seed C | `e07b8af4086665ab031ac6612eac670d28f0b5611cb3b3460578cd530c43f35e` (`36,049,197 B`, fixed point from Snapshot 72's seed `2cbb0966…`) |
| Compressed seed | `seed.c.gz` (`5,570,488 B`) |
| Profile | Clang 23, `x86_64-pc-linux-gnu`, data `d3a5a1fb358f77ab1b747198992de8d87071e67070d5f8e00f127dabdeb48be8` (`967,968 B`) |
| Executable with profile | `bb3a5cb4f4d55b740609b5865fa5f6ae25ce81147c3728fab583a109ccc694aa` |
| Executable without profile | `2840e2865b3a773f68f00deea8b6033535148be5591aa04142832abe9e1427fc` |

**Profile.** Trained with the `_Exit`-wrapped instrumentation protocol (`-fprofile-instr-generate`, `-Wl,--wrap=_Exit`, Clang 23) using non-timed compiler workloads only: self-compiling `selfhost/main.goose` (`--target native -O2`, `--target wasm-direct --wasm-memory64 -O2`, `--target wasm-direct --wasm-bundled-host -O2`, `--check`) plus 4 positive contract fixtures (`literal-parameters/adapt`, `root-struct/owner`, `slice-pool/spans` native, `defer/forms`) weighted 32 each. None of the timed benchmark programs or Blot2 snapshots was used in training.

**Public roots.** `scripts/bootstrap.py --verify` ran twice without caching: with defaults (`35.2 s`: `34.6 s` C build + `0.56 s` self-host verify) and with explicit options (`36.2 s`: `35.6 s` C build + `0.61 s` self-host verify). Both report `seed_matches_sources: true`, `fixed_point: true`, and `profile_used: true`, and both build `bb3a5cb4…` (`goose-to-wasm v2026.4-4 (Goose v2026.4)`). Release smoke checks (including `--stdlib stdlib-web` and portable Wasm64 `goosew.wasm`, `6,173,036 B`, exact 24 Wasm64 imports) passed. [Explicit](bootstrap-explicit.json) · [Default](bootstrap-default.json)

**Qualification.** `scripts/qualify.py --output-dir build/qualify-release-v2026.4-4 --jobs 8` passed all stages in `100.5 s` using the profiled executable `bb3a5cb4…` (`bootstrap` `35.4 s`, `profile_used: true`, `10,797/10,801` conformance with 0 unexpected failures, `4,773/4,779` memory64 with 0 unexpected failures, `54/54` native checks, all 22 unit test suites exit 0). [Summary](qualification.json)
