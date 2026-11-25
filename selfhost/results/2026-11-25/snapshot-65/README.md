# Snapshot 65 · 2026-11-25

The checked-in C bootstrap seed and Clang 23 PGO profile are now frozen at the fixed point of `v2026.4-6` (`selfhost/` through `4dcbb5c` + version bump to `v2026.4-6`), replacing Snapshot 64 (`a27c51ec…`, 2026-11-25).

Major changes accumulated between Snapshot 64 and Snapshot 65:
- **100% pinned upstream Goose conformance parity (Batches A–C, `92 → 2` open gaps, `+90` rows fixed):**
  - `10,799 / 10,801` (`99.98%`) overall conformance, **`6,022 / 6,022` (`100.00%`)** split-unit native conformance, `1,800 / 1,800` `upstream/errors_tc/`, `252 / 252` `upstream/lifetimes/`, `46 / 46` `upstream/storage/`, `276 / 276` `upstream/codegen/`, `50 / 50` `upstream/stdlib/` (including `stdlib_regex`), and `154 / 154` `upstream/optimizer/`.
  - `forced0` (`LIFE_CONCRETE_FRAMES = 0`) soundness improved to `10,753 / 10,801` (**+74** fixes vs baseline, **0 regressions**).
- **Blot2 HEAD `98f277f2` Direct Wasm64 support:** multi-discard `_` bindings, folded-global class-mode shrink precision (`check/check.goose:1271`), and `goose-wasmtime` / `goose-wtime` host updates.

| Item | Identity |
| --- | --- |
| Seed C | `8f44f3da71d2d60c8a1c5c48c1e32ff6ec5e7e081238bba04c183fd44a658f02` (`25,806,194 B`, stage 2 = stage 3 from Snapshot 64's seed `a27c51ec…`) |
| Compressed seed | `seed.c.gz` (`4,306,800 B`) |
| Profile | Clang 23, `x86_64-pc-linux-gnu`, data `23f69d8c32f0b558a71db64d061413c7debc9a4f0469bafd549bc390598f054e` (`769,672 B`) |
| Executable with profile | `df50507c80c82f094637f6a2ae662a54aff0a03c4229b2bda69b62b2c7a1aa00` |
| Executable without profile | `58962a88b8de3c665c26dcca41b5dd5ff673be86aa5a5799854d7817ff4e6faa` |

**Profile.** Trained with Snapshot 58/63/64's `_Exit`-wrapped instrumentation protocol (`-fprofile-instr-generate`, `-Wl,--wrap=_Exit`, Clang 23.1.5) using non-timed compiler workloads only: self-compiling `selfhost/main.goose` (`--target native -O2`, `--target wasm-direct --wasm-memory64 -O2`, `--target wasm-direct --wasm-bundled-host -O2`, `--check`) plus 4 positive contract fixtures (`literal-parameters/adapt`, `root-struct/owner`, `slice-pool/spans`, `defer/forms`) weighted 32 each. None of the timed benchmark examples or Blot2 snapshots was used in training. Both the plain build and the profiled build reproduce `seed.c` bit-for-bit (`8f44f3da…`).

**Public roots.** `scripts/bootstrap.py --verify` ran twice without caching: with defaults (`29.1 s`) and with explicit options (`29.9 s`). Both report `seed_matches_sources: true`, `fixed_point: true`, and `profile_used: true`, and both build `df50507c…`. [Explicit](bootstrap-explicit.json) · [Default](bootstrap-default.json)

**Qualification.** `scripts/qualify.py --output-dir build/qualify-v2026.4-6 --jobs 8 --units-pass always` passed all stages in `131.6 s` using the profiled executable `df50507c…` (`bootstrap` `29.2 s`, `profile_used: true`, `10,799/10,801` conformance, `6,022/6,022` split-unit native, `4,773/4,779` memory64, `54/54` native checks, all unit tests exit 0, plain upstream C++ Goose check exit 0). [Summary](qualification.json)
