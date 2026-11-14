# Snapshot 63 · 2026-11-14

The bootstrap seed is now the fixed point of `29cc778`'s sources. Those are snapshot 62's sources with these changes:
- the fixes from the upstream differential run (`62e410b` to `7e73b73`);
- the native fix for abandoned destinations (`a81b239`);
- the lifetime offer table sized to the program (`4636310`);
- native unit names found with `find_pair` (`29cc778`).

The previous seed, snapshot 62 (`d1f489fb…`, executable `2d2c4a3d…`), took 1.36× snapshot 61's time on the eleven benchmark programs; snapshot 63 takes 1.04–1.05×. [Compiler campaign](../../../../bench/results/2026-11-14/compiler-throughput-63/README.md)

| Item | Identity |
| --- | --- |
| Seed C | `28f1af08daba0f4de86b6f5e2c5ef1adfd25f5ce2921162ea67fa5df78998970` (stage 1 = stage 2 from snapshot 62's seed) |
| Profile | Clang 23, `x86_64-pc-linux-gnu`, data `1ca21eb5334b98b50987b031fed5acf114a2ad69b999d811c93619e09f7017c3` |
| Executable with profile | `10ade9d54abd059038d05cb76d1f81f9c89b9254c2f3529794995e298518ab56` |
| Executable without profile | `0b7152271533086331cba220ed076f8d356c410fc6ef9580a6c38fee59f0a531` |

**Profile.** The profile was trained with snapshot 58's protocol (`build/redeliver63.sh`, adapted from snapshot 62's). An instrumented build of the seed compiled the compiler's own sources to native C. It also compiled two feature fixtures to direct Wasm, `leaf-properties` and `flow-prefilter`, weighted 64 each. None of the eleven timed programs was used. Both the plain build and the profiled build reproduce the seed C exactly.

**Public roots.** `scripts/bootstrap.py --verify` ran twice: with explicit options in the redelivery workspace, and with defaults in the checkout. Both report `seed_matches_sources`, `fixed_point` and `profile_used`, and both build `10ade9d5…`. [Explicit](bootstrap-explicit.json) · [Default](bootstrap-default.json)

**Qualification.** `scripts/qualify.py` ran on `69cba67`, whose compiler sources, stdlib and runtime are `29cc778`'s. Its compiler was the profiled executable `10ade9d5…`. [Summary](qualification.json)
- Bootstrap reached a fixed point.
- Conformance passed 10,685 of 10,789 rows. With the native rows as three units, it passed 5,922 of 6,018. Exactly the recorded gaps failed: 104 and 96.
- 54 of 54 native checks passed. The unit tests passed, including the six fast optimizer statistics modules.
- Against the compiler of the same sources built from snapshot 62's seed, 0 of 10,045 outputs differ.
