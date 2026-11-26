# Snapshot 72 · 2026-11-26 (`v2026.4-3`)

The checked-in C bootstrap seed and Clang 23 PGO profile are frozen at the fixed point of the `v2026.4-3` release (`selfhost/driver.goose`: `GOOSE_TO_WASM_VERSION = "v2026.4-3"`, replacing Snapshot 71 `e851b538…`, 2026-11-26).

Changes from Snapshot 71 to Snapshot 72:
- **Drop-in Web stdlib & browser runtime (`70defce`, `a46c7e2`, `23a1394`):**
  - `selfhost/sources.goose` & `selfhost/checker.goose`: `--stdlib`-first package resolution before blessed-package rejection and `embed_shader` builtin (`"GWEB\0<stage>\0<glsl>"` blobs for `.vert`/`.frag`/`.comp` and inline multi-part GLSL).
  - `stdlib-web/` & `host/web/`: zero-dependency pure-Web runtime (`MemoryFS`, `LocalStorageFS`, `OPFSAdapter`, Web Audio mixer, WebGL2 + GLSL 450→ES 3.00 transpiler + touch/pointer-lock/JSPI async frame loop, Canvas 2D immediate-mode `ui`, pure-JS 3D `physics`, and pure-Goose B+ span tree `slice_pool`).
- **GitHub Pages showcase (`site/`, `scripts/build_pages.py`, `.github/workflows/pages.yml`):**
  - Front page explaining unmodified compilation with `goosew --stdlib stdlib-web --target wasm-direct` and live autorun demos for all nine official Goose graphics samples (`aardappel/goose@1838de45`).
- **Release packaging (`v2026.4-3`):**
  - `selfhost/driver.goose`: bump `GOOSE_TO_WASM_VERSION` from `"v2026.4-2"` to `"v2026.4-3"`.
  - `.github/workflows/release.yml`: bundle `stdlib-web/` and `host/web/` into Linux x64, macOS arm64/x64, Windows x64, and portable Wasm64 release archives and smoke-test `--stdlib stdlib-web`.
  - `README.md` & `.github/ISSUE_TEMPLATE/bug_report.yml`: update prebuilt release links and version examples to `v2026.4-3`.

| Item | Identity |
| --- | --- |
| Seed C | `2cbb09661525e7bfd61a11d44bbcf7b7c624010fc137e9c6f01d8e0914e87394` (`26,160,279 B`, fixed point from Snapshot 71's seed `e851b538…`) |
| Compressed seed | `seed.c.gz` (`4,360,979 B`) |
| Profile | Clang 23, `x86_64-pc-linux-gnu`, data `01f20f632f0c5e79500de4394043d20cd0962f9afa41c160853500df6287563e` (`778,728 B`) |
| Executable with profile | `3a900d10d32c2471123ddb0f25ec590dcf0f90cad49650dfc6389af887f7bad6` |
| Executable without profile | `9842a7998d8475ca88c16bf3aeebf9f48532c2ce987347ba198544422d923ba6` |

**Profile.** Trained with the `_Exit`-wrapped instrumentation protocol (`-fprofile-instr-generate`, `-Wl,--wrap=_Exit`, Clang 23) using non-timed compiler workloads only: self-compiling `selfhost/main.goose` (`--target native -O2`, `--target wasm-direct --wasm-memory64 -O2`, `--target wasm-direct --wasm-bundled-host -O2`, `--check`) plus 4 positive contract fixtures (`literal-parameters/adapt`, `root-struct/owner`, `slice-pool/spans` native, `defer/forms`) weighted 32 each. None of the timed benchmark programs or Blot2 snapshots was used in training.

**Public roots.** `scripts/bootstrap.py --verify` ran twice without caching: with defaults (`30.3 s`) and with explicit options (`30.5 s`). Both report `seed_matches_sources: true`, `fixed_point: true`, and `profile_used: true`, and both build `3a900d10…` (`goose-to-wasm v2026.4-3 (Goose v2026.4)`). [Explicit](bootstrap-explicit.json) · [Default](bootstrap-default.json)

**Qualification.** `scripts/qualify.py --output-dir build/qualify-release-v2026.4-3` passed all stages in `111.9 s` using the profiled executable `3a900d10…` (`bootstrap` `4.6 s`, `profile_used: true`, `10,797/10,801` conformance with 0 unexpected failures, `4,773/4,779` memory64, `54/54` native checks, all 22 unit test suites exit 0). [Summary](qualification.json)
