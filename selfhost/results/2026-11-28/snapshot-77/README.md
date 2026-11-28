# Snapshot 77 · 2026-11-28 (`v2026.4-8`)

The checked-in C bootstrap seed and Clang 23 PGO profile are frozen at the fixed point of the `v2026.4-8` release (`selfhost/driver.goose`: `GOOSE_TO_WASM_VERSION = "v2026.4-8"`, replacing Snapshot 76 `c58238e3…`, 2026-11-28).

Changes from Snapshot 76 to Snapshot 77:
- **`wtime v0.1.14` host integration (`host/wtime/`, `host/wtime-aot/`):**
  - Updated `host/wtime/Cargo.lock` and `host/wtime-aot/Cargo.lock` to [`wtime v0.1.14`](https://github.com/mewhhaha/wtime/releases/tag/v0.1.14), bringing merged `v0.1.13` GC safepoint table deduplication, cold allocation stubs, non-null analysis, zero-copy `WTMS0002` `mmap` deserialization, and warm semi-spaces together with `main`'s per-function x64 `--inc-cache`, standalone Goose OS/math/sandbox imports, and x64 loop/SIMD/FP codegen improvements.
- **README & report SVG presentation (`81d9791`, `f350466`):**
  - Split the wide two-panel Blot2 benchmark chart into two mobile-readable standalone SVGs (`blot2_subsecond_turnaround.svg` and `blot2_hosted_engines.svg`) and styled the stacked engine compile+run bar segments with white diagonal striping.
- **Release packaging & documentation (`v2026.4-8`):**
  - `selfhost/driver.goose`: bump `GOOSE_TO_WASM_VERSION` from `"v2026.4-7"` to `"v2026.4-8"`.
  - `.github/workflows/release.yml`, `.github/ISSUE_TEMPLATE/bug_report.yml`, `README.md`, `selfhost/README.md`: update release references to `v2026.4-8` and Snapshot 77.

| Item | Identity |
| --- | --- |
| Seed C | `8056c33fbc200c4a57d4c7c30ad04417642f4f15c81d44c24b671abcde916b7e` (`39,267,575 B`, fixed point from Snapshot 76's seed `c58238e3…`) |
| Compressed seed | `seed.c.gz` (`6,145,580 B`) |
| Profile | Clang 23, `x86_64-pc-linux-gnu`, data `66e4574f96fde13d7329fef66a15161b06b47deb20f88edaae5a114a91355bd3` (`1,023,832 B`) |
| Executable with profile | `847fc044bd4549f9d51d13db8f2d4e2f1eb08c5fba680655268953a844b36d34` |
| Executable without profile | `9d35b0598e0cf64fc0e9ba0eb853fe42229a83e69de19c280a323ba41dfc6ecc` |

**Profile.** Trained with the `_Exit`-wrapped instrumentation protocol (`-fprofile-instr-generate`, `-Wl,--wrap=_Exit`, Clang 23) using non-timed compiler workloads only: self-compiling `selfhost/main.goose` (`--target native -O2`, `--target wasm-direct --wasm-memory64 -O2`, `--target wasm-direct --wasm-bundled-host -O2`, `--check`) plus 4 positive contract fixtures (`literal-parameters/adapt`, `root-struct/owner`, `slice-pool/spans` native, `defer/forms`) weighted 32 each. None of the timed benchmark programs or Blot2 snapshots was used in training.

**Public roots.** `scripts/bootstrap.py --verify` ran twice without caching: with defaults (`61.8 s`) and with explicit options (`58.8 s`). Both report `seed_matches_sources: true`, `fixed_point: true`, and `profile_used: true`, and both build `847fc044…` (`goose-to-wasm v2026.4-8 (Goose v2026.4)`). [Explicit](bootstrap-explicit.json) · [Default](bootstrap-default.json)

**Qualification.** `scripts/qualify.py --output-dir build/qualify-release-v2026.4-8-clean --baseline /home/mewhhaha/src/goose-to-wasm/build/bin/goosew` passed all stages in `128.9 s` using the profiled executable `847fc044…` (`bootstrap` `1.1 s` cached / `58.8–61.8 s` uncached, `profile_used: true`, `10,790/10,801` conformance with `0` unexpected failures, `4,771/4,779` memory64 with `0` unexpected failures, `54/54` native checks, `10,061/10,061` equivalence with `0` differing, all 22 unit test modules exit `0` including `tests.test_wtime_host` against `wtime v0.1.14`). [Summary](qualification.json)
