# Snapshot 67 · 2026-11-25

The checked-in C bootstrap seed and Clang 23 PGO profile are frozen at the fixed point of the post-pin upstream parity batch (`selfhost/parser.goose`, `selfhost/checker.goose`, `selfhost/checker_validation.goose`, `selfhost/checker_lifetimes.goose`, replacing Snapshot 66 `cd4e43cf…`, 2026-11-25).

Changes from Snapshot 66 to Snapshot 67:
- `selfhost/parser.goose`: contextual `deprecated ["msg"]` function modifier (§7.15), keeping `deprecated` an ordinary identifier everywhere else and rejecting `defer deprecated fn`.
- `selfhost/checker.goose`: preserve original AST syntax in `check_function_syntax` for non-const `TY_SLICE`/`TY_REF` parameters so const-polymorphic specialization does not clobber trailing blocks (`stdlib_each_utf8`), and add two-pass generic nominal `format<T>` rendering hooks (`render_generic_overloads` / `render_generic_non_hooks`, including phantom generics like `Type<T>`).
- `selfhost/checker_validation.goose`: resolve pool-relative references into root-struct components (`P.items`) via `validation_pool_root` for `.index_of(...)` (`stdlib_slot_pool_builder_effects`).
- `selfhost/checker_lifetimes.goose`: static-only stores (`""`, `MessageView {}`) kill fields/contents without wiping `kind == 7` field kills (`emptied_static_fields`), and flow-sensitive local `live_contents` tracking in discovery avoids future-store contamination on local non-captured containers (`holder_param_stores_later`) while keeping loops, recursion, and `byteview_cycle_holder` sound.

| Item | Identity |
| --- | --- |
| Seed C | `2f1fb59a253b875e5f0032b6c9da6bcf241c6489813e43389b8410291acfc994` (`25,860,038 B`, stage 2 = stage 3 from Snapshot 66's seed `cd4e43cf…`) |
| Compressed seed | `seed.c.gz` (`4,316,057 B`) |
| Profile | Clang 23, `x86_64-pc-linux-gnu`, data `0a2c6ef269e282d8d66a0501343b1eeed2b856dd1ae920e1940d4b8ff5cfe4f2` (`771,568 B`) |
| Executable with profile | `8e6debac2e6a371164d6a1cfc3ecfa90e20cd5450ddb75b6a78cb3c8a3ce6423` |
| Executable without profile | `4d07489435bb4013cefb4ee5dda2d98911a7d3fcb0782e5c7504af98fa1590b0` |

**Profile.** Trained with the `_Exit`-wrapped instrumentation protocol (`-fprofile-instr-generate`, `-Wl,--wrap=_Exit`, Clang 23.1.5) using non-timed compiler workloads only: self-compiling `selfhost/main.goose` (`--target native -O2`, `--target wasm-direct --wasm-memory64 -O2`, `--target wasm-direct --wasm-bundled-host -O2`, `--check`) plus 4 positive contract fixtures (`literal-parameters/adapt`, `root-struct/owner`, `slice-pool/spans` native, `defer/forms`) weighted 32 each. Both plain and profiled builds reproduce `seed.c` bit-for-bit (`2f1fb59a…`).

**Public roots.** `scripts/bootstrap.py --verify` ran twice without caching: with defaults (`33.9 s`) and with explicit options (`92.8 s`). Both report `seed_matches_sources: true`, `fixed_point: true`, and `profile_used: true`, and both build `8e6debac…`. [Explicit](bootstrap-explicit.json) · [Default](bootstrap-default.json)

**Qualification.** `scripts/qualify.py --output-dir build/qualify-snapshot-67 --jobs 8 --units-pass always` passed all stages in `197.7 s` using the profiled executable `8e6debac…` (`bootstrap` `59.9 s`, `profile_used: true`, `10,799/10,801` conformance, `6,022/6,022` split-unit native, `4,773/4,779` memory64, `54/54` native checks, all unit test suites including `PostPinUpstreamParity` exit 0, plain upstream C++ Goose check exit 0). [Summary](qualification.json)
