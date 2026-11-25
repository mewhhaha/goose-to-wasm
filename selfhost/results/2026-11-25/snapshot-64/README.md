# Snapshot 64 · 2026-11-25

The checked-in C bootstrap seed and Clang 23 PGO profile are now frozen at the fixed point of `v2026.4-4` (`selfhost/` through `a44ed0f` + version bump to `v2026.4-4`), replacing Snapshot 63 (`28f1af08…`, 2026-11-14).

Major changes accumulated between Snapshot 63 and Snapshot 64:
- Batches 9–13 native C & Wasm codegen speedups (`-46%` smaller emitted C, from ~47 MB stage-1 / ~39 MB snapshot-63 down to **25.2 MB** uncompressed and **4.21 MB** gzipped vs Snapshot 63's **7.29 MB**, **−42.2%**).
- Full Blot2 compatibility milestones (class-keyed lifetime checker algorithmic redesign, C-host library build interface `--emit-runtime` / `--header` / `--shared` / `--standalone`, Direct Wasm `reusable[]` slice pools + flat `from_bytes` + O(1) page-bucketed forwarding resolver, `--library --reachable-program`).
- Solid diagnostics overhaul (`--error-format=text|json`, `--color`, generic/stdlib instantiation backtraces, opening-delimiter & prior-declaration notes, consolidated missing match/struct lists, `--run` relative-path fix).
- Conformance burn-down (`10,709 / 10,801` = 99.15%, 92 open gaps; `4,773 / 4,779` memory64, 6 open gaps).
- Direct Wasm64 `m.safe_refs` field-offset folding, inline small scalar clears/copies, and fast memory64 owner indexing.

| Item | Identity |
| --- | --- |
| Seed C | `a27c51ec448aa5107fec9630e5a18081218880cfa19664219ba04a50acfee9a6` (`25,235,728 B`, stage 2 = stage 3 from Snapshot 63's seed `28f1af08…`) |
| Compressed seed | `seed.c.gz` (`4,210,233 B`, down **−42.2%** from Snapshot 63's `7,286,000 B`) |
| Profile | Clang 23, `x86_64-pc-linux-gnu`, data `710dc7a7c3903993f18f413262f27b99466f68c71eaf865527e557ea834f5631` (`754,688 B`) |
| Executable with profile | `40409f9a212dd8b839efc63eb259d6d467218b8354c455eac382b874f9082112` |
| Executable without profile | `f981337450bc2365d4f5d4cfea122923688defd11352f09e2f1cf36cf257520f` |

**Profile.** Trained with Snapshot 58/63's `_Exit`-wrapped instrumentation protocol (`-fprofile-instr-generate`, `-Wl,--wrap=_Exit`, Clang 23.1.5) using non-timed compiler workloads only: self-compiling `selfhost/main.goose` (`--target native -O2`, `--target wasm-direct --wasm-memory64 -O2`, `--target wasm-direct --wasm-bundled-host -O2`, `--check`) plus 4 positive contract fixtures (`literal-parameters/adapt`, `root-struct/owner`, `slice-pool/spans`, `defer/forms`) weighted 32 each. None of the timed benchmark examples or Blot2 snapshots was used in training. Both the plain build and the profiled build reproduce `seed.c` bit-for-bit (`a27c51ec…`).

**Public roots.** `scripts/bootstrap.py --verify` ran twice without caching: with explicit options (`33.0 s`) and with defaults (`32.1 s`, down from `138.5 s` before Snapshot 64 — **4.3× faster**). Both report `seed_matches_sources: true`, `fixed_point: true`, and `profile_used: true`, and both build `40409f9a…`. [Explicit](bootstrap-explicit.json) · [Default](bootstrap-default.json)

**Qualification.** `scripts/qualify.py --output-dir build/qualify-v2026.4-4 --jobs 8` passed all stages in `170.0 s` using the profiled executable `40409f9a…` (`bootstrap` `29.0 s`, `profile_used: true`, `10,709/10,801` conformance, `4,773/4,779` memory64, `54/54` native checks, `21/21` unit test suites, plain upstream C++ Goose check exit 0). [Summary](qualification.json)
