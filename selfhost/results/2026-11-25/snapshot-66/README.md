# Snapshot 66 · 2026-11-25

The checked-in C bootstrap seed and Clang 23 PGO profile are frozen at the fixed point of `v2026.4-1` with the renamed **`goosew`** compiler binary (`selfhost/driver.goose` updated to `goosew` + `v2026.4-1`, replacing Snapshot 65 `8f44f3da…`, 2026-11-25).

Changes from Snapshot 65 to Snapshot 66:
- Renamed the installed compiler binary from `goose` to **`goosew`** across `selfhost/driver.goose`, `scripts/bootstrap.py`, `selfhost/bootstrap.py`, `scripts/`, `.github/`, docs, benchmarks, and unit tests to avoid colliding with upstream C++ `goose` on `PATH`.
- Set `GOOSE_TO_WASM_VERSION` to `"v2026.4-1"` (`goose-to-wasm v2026.4-1 (Goose v2026.4)`) for the consolidated flagship `v2026.4-1` release.

| Item | Identity |
| --- | --- |
| Seed C | `cd4e43cfc9c0e04efad969be4681d21ea00f6e9843f3397c15e738591d67807d` (`25,806,310 B`, stage 2 = stage 3 from Snapshot 65's seed `8f44f3da…`) |
| Compressed seed | `seed.c.gz` (`4,306,845 B`) |
| Profile | Clang 23, `x86_64-pc-linux-gnu`, data `5ad722bdeb2e2471f4cf54ac25536677a9fffe0c641d15d1521190210b011ae2` (`769,672 B`) |
| Executable with profile | `b2378eb0ef167f5d1f14824b2e4927d3fd4d494aa4c12beae89e5c63dbe0980a` |
| Executable without profile | `b77b52102be27fb0fc3003db6ac3a45b65d39fed592d4c77a07a000ff5b824e3` |

**Profile.** Trained with Snapshot 58/63/64/65's `_Exit`-wrapped instrumentation protocol (`-fprofile-instr-generate`, `-Wl,--wrap=_Exit`, Clang 23.1.5) using non-timed compiler workloads only: self-compiling `selfhost/main.goose` (`--target native -O2`, `--target wasm-direct --wasm-memory64 -O2`, `--target wasm-direct --wasm-bundled-host -O2`, `--check`) plus 4 positive contract fixtures (`literal-parameters/adapt`, `root-struct/owner`, `slice-pool/spans` native, `defer/forms`) weighted 32 each. None of the timed benchmark examples or Blot2 snapshots was used in training. Both the plain build and the profiled build reproduce `seed.c` bit-for-bit (`cd4e43cf…`).

**Public roots.** `scripts/bootstrap.py --verify` ran twice without caching: with defaults (`29.9 s`) and with explicit options (`29.7 s`). Both report `seed_matches_sources: true`, `fixed_point: true`, and `profile_used: true`, and both build `b2378eb0…`. [Explicit](bootstrap-explicit.json) · [Default](bootstrap-default.json)

**Qualification.** `scripts/qualify.py --output-dir build/qualify-v2026.4-1-goosew --jobs 8 --units-pass always` passed all stages in `129.5 s` using the profiled executable `b2378eb0…` (`bootstrap` `30.6 s`, `profile_used: true`, `10,799/10,801` conformance, `6,022/6,022` split-unit native, `4,773/4,779` memory64, `54/54` native checks, all 21 unit test suites + 34 extra unit tests exit 0, plain upstream C++ Goose check exit 0). [Summary](qualification.json)
