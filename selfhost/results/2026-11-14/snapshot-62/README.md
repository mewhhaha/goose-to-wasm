# Snapshot 62 · 2026-11-14

The bootstrap seed is now the fixed point of `8cec9bc`'s sources. The previous seed, snapshot 61 (`f65aba52…`, executable `25055855…`), predates these changes, which now ship in the seed and profile:
- the indexed checker and lifetime set sharing;
- parallel native units;
- root structs on both targets;
- `slice_pool` and stdlib abort sites;
- the range loop index fix.

| Item | Identity |
| --- | --- |
| Seed C | `d1f489fb3e417c1ebae5ef6f8cc5814d69e850d34143af23b64be30bc42e465d` (stage 1 = stage 2 from snapshot 61's seed) |
| Profile | Clang 23, `x86_64-pc-linux-gnu`, data `1e43f8e97ee52424a773d0556f670ac204ca97fd8cb67e999f860863417f5157` |
| Executable with profile | `2d2c4a3d677f47d1c512b39a8266c1c305c73cd3f1e219915cda3ee794fe5cbd` |
| Executable without profile | `5605af6a87c86b9249f46acf7ef5ba2351a1b8a7513cdbdfe29e6e9a4dbaa57f` |

**Profile.** The profile was trained with snapshot 58's protocol (`/var/tmp/goose-perf/redeliver.sh`). An instrumented build of the seed compiled the compiler's own sources to native C and two feature fixtures to direct Wasm: `leaf-properties` and `flow-prefilter`, weighted 64 each. None of the eleven timed programs was used. Both the plain build and the profiled build reproduce the seed C exactly.

**Public roots.**
- `scripts/bootstrap.py --verify` with explicit options and with defaults: the explicit run used options in the redelivery workspace, the default run used the checkout.
- Both report `seed_matches_sources`, `fixed_point` and `profile_used`, and both build `2d2c4a3d…`. [Explicit](bootstrap-explicit.json) · [Default](bootstrap-default.json)

**Qualification.** `scripts/qualify.py` ran on these sources. Its compiler was this seed built without the profile, `5605af6a…`, bit for bit the plain executable above. [Summary](qualification.json)
- Bootstrap reached a fixed point.
- Conformance passed 8,356 of 8,448 rows, both as one unit and with the native rows as three units. Exactly the 92 recorded gaps failed.
- 54 of 54 native checks passed, and the unit tests passed.
- Against the snapshot 62 compiler of `e7d04da` (`05d59e23…`), 4 of 7,689 outputs differ, all from the range index fix. The new contract `range-index/iterations` differs at native `-O0` and `-O2`. So does `tests/fixtures/codegen_loop_indices.goose`, whose contract was already written for the iteration count (`8`) but ran only on direct Wasm.

The compiler speed comparison with snapshot 61 is separate; it needs a quiet machine.
