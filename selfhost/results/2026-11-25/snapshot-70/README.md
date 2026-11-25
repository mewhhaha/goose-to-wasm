# Snapshot 70 · 2026-11-25 (`v2026.4-2`)

The checked-in C bootstrap seed and Clang 23 PGO profile are frozen at the fixed point of the `v2026.4-2` release bump (`selfhost/driver.goose`: `GOOSE_TO_WASM_VERSION = "v2026.4-2"`, replacing Snapshot 69 `4af0d23e…`, 2026-11-25).

Changes from Snapshot 69 to Snapshot 70:
- `selfhost/driver.goose`: bump `GOOSE_TO_WASM_VERSION` from `"v2026.4-1"` to `"v2026.4-2"`.
- `.github/workflows/release.yml`: extend Linux, macOS, and Windows release smoke tests to exercise default Direct Wasm `--run`, native `--run`, and Win32 UTF-16 (`café.txt`) file I/O.
- `README.md` & `.github/ISSUE_TEMPLATE/bug_report.yml`: update prebuilt release links and version examples to `v2026.4-2`.

| Item | Identity |
| --- | --- |
| Seed C | `ea29764add833d36d3a327e0d40023b692d1c06ce4b1921921b210c8d9597d3f` (`25,949,864 B`, stage 1 = stage 2 = stage 3 from Snapshot 69's seed `4af0d23e…`) |
| Compressed seed | `seed.c.gz` (`4,328,007 B`) |
| Profile | Clang 23, `x86_64-pc-linux-gnu`, data `313ecee509aaf9b88a079c81bdaa3da47f896ee8427542af7f626e2002486386` (`772,656 B`) |
| Executable with profile | `c420b2b5bf6230a946458255f3d9024ffc382a190367479f46ea205ae49ee9be` |
| Executable without profile | `6b3ff61ddacb35ab92efebf724cc0af0e3ea14501a2d493bd7c9fa224a6a395e` |

**Profile.** Trained with the `_Exit`-wrapped instrumentation protocol (`-fprofile-instr-generate`, `-Wl,--wrap=_Exit`, Clang 23) using non-timed compiler workloads only: self-compiling `selfhost/main.goose` (`--target native -O2`, `--target wasm-direct --wasm-memory64 -O2`, `--target wasm-direct --wasm-bundled-host -O2`, `--check`) plus 4 positive contract fixtures (`literal-parameters/adapt`, `root-struct/owner`, `slice-pool/spans` native, `defer/forms`) weighted 32 each. None of the timed benchmark programs or Blot2 snapshots was used in training.

**Public roots.** `scripts/bootstrap.py --verify` ran twice without caching: with defaults (`34.6 s`) and with explicit options (`33.3 s`). Both report `seed_matches_sources: true`, `fixed_point: true`, and `profile_used: true`, and both build `c420b2b5…` (`goose-to-wasm v2026.4-2 (Goose v2026.4)`). [Explicit](bootstrap-explicit.json) · [Default](bootstrap-default.json)

**Qualification.** `scripts/qualify.py --output-dir build/qualify-v2026.4-2 --jobs 8` passed all stages in `150.1 s` using the profiled executable `c420b2b5…` (`bootstrap` `35.5 s`, `profile_used: true`, `10,799/10,801` conformance, `4,773/4,779` memory64, `54/54` native checks, all 21 unit test suites exit 0, plain upstream C++ Goose check exit 0). [Summary](qualification.json)
