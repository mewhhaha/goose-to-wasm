# blot2's compiler from its export root · 2026-11-14

`9806f0e` made exported functions lifetime roots, so blot2's compiler, whose only entry is `export "blot_goose_main" fn mainEntry()`, is now analyzed from that root instead of being skipped. Nine commits on top of it make the analysis's first discovery pass reach 20,000 call contexts (frames) 5–7 times sooner, and let its alternatives grow 1.9 times as far before their region fills. Every output is unchanged: after each commit 0 of 10,049 compilations differ from `9806f0e`'s compiler, and the whole analysis state matched `9806f0e`'s at every pass boundary on 4,355 conformance sources and at every 2,000 frames of blot2's first pass, as far as `9806f0e` got.

**It still does not finish.** The final build stopped after 884 s (824 s of CPU, peak RSS 2.82 GiB) with `goose runtime error: data stack overflow`: at 93,000 frames, still in discovery pass 1, its 77.9 M alternatives had filled their 2 GiB region (79.5 M fit). `9806f0e` reached 22,000 frames in 400 s, and the same analysis stopped at 31,000 frames after 996 s and 8.6 GiB in the separately collected 2026-11-14 run with a `main` harness ([set-sharing evidence](../lifetime-set-sharing/README.md)). Native emission and the diagnostics report were not reached. Where the cost is now, with measurements, is below.

## Workload

- blot2 commit `93c8fa828a8897d2369ad80c0a737767ca345c71`, `compiler-goose/src` copied before any run: 450 Goose sources and `parse/PORT_NOTES.md`, 451 files. The copy's identity, `find . -type f | sort | xargs sha256sum | sha256sum`, is `91598806dcaf0a5181ec6f575462e4067a30500705b4fe01d9a7a00ff3d20bc4`. blot2's checkout moved on during the work; the copy did not.
- 5.3 M nodes and 27,923 reached functions, parsed and type checked in about 12 s.
- From the copied directory: `goose main.goose --stdlib <worktree>/stdlib --reachable-program --expansion-node-limit 1000000 --check`, with our standard library at `9806f0e`.

## Compilers

All were built the way `scripts/bootstrap.py --jobs 8` builds a development compiler: C emitted at `-O2` by the `9806f0e` development compiler, then Clang 23 `-std=gnu11 -O2` as eight units, without a profile (`tools/mk.sh`). Progress builds add only `LIFEPROG` lines of table sizes (`tools/progress.py` reads state and changes nothing). Profile builds also keep frame pointers.

| Build | Sources | Executable sha256 |
| --- | --- | --- |
| baseline | `9806f0e` | `e5957443e9fa1854d3eb73d225bb427c5fe47251a8c4a5ef9b7c6b9953e0d655`, the same from `mk.sh` and from `bootstrap.py --jobs 8` |
| final | `be255ed` | `9b90416d728222a969b4bd1c6f1fc898a682df97c2021bcad74c8addb4e85d97` from `bootstrap.py --jobs 8` of `42637bb`, which differs from `be255ed` in one comment and emits the same C (`af198c33…`) |

The commits were made on a branch from `9806f0e` and then moved onto `d807027`, which changed only documentation; the hashes on this page are main's. File names under `runs/` and labels in the JSON reports keep the branch's hashes: `e232600` = `4663c09`, `bf393e1` = `f00c04f`, `c7b2ba7` = `5d29ab5`, `15985fd` = `d758739`, `f558402` = `3444750`, `f0eee87` = `a5671c5`, `0f5e6c7` = `d946517`, `04fd767` = `e6ee473`, and `9fa333d`, `8aa93dd` = `be255ed`.

## blot2, before and after

Seconds from the start of discovery pass 1 to each frame count. The machine was shared, at load 11–18 on 16 threads; only rows started together share their load.

| Run | 5k | 10k | 20k | 30k | 40k | Reached | Outcome |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `9806f0e` (profiled, load ~11) | 26 | 69 | 300 | | | 22,000 in 400 s | killed at 400 s |
| final, `r2-loads` (load ~15) | 5 | 15 | 42 | 84 | 155 | 49,000 in 250 s | killed at 250 s |
| final, run to its end (load 13–17) | 7 | 21 | 59 | 129 | 222 | 93,000 in 870 s | alternatives' region full after 884 s, 824 s CPU, 2.82 GiB |

The final run's tables at its end: 77.9 M alternatives (2.10 GB), 5.84 M effects and as many summaries (0.89 GB and 0.56 GB), 2.70 M sets, 132 M root-index slots (1.06 GB), 1.71 M roots and atoms, 0.94 M cells. Its peak RSS stayed low because the machine was swapping (724,000 major faults). [Progress lines](runs/)
## The commits

| Commit | Idea | Measured on blot2 (discovery pass 1) |
| --- | --- | --- |
| `4663c09` | A list made again is the earlier set: no set IDs that mirror the old code's (`LifeSet.vid`) | sets at 20,000 frames 8.50 M → 1.70 M; the same alternatives and effects |
| `f00c04f` | Transformed alternatives go straight into builds, without an atom each (patch 29's idea) | at 20,000 frames: atoms 1.55 M → 0.35 M, sets → 0.54 M, alternatives 6.62 M → 5.40 M; 374 → 243 s |
| `5d29ab5` | Global read-back candidates kept per pointee type while no global cell changes (patch 23's idea) | 22,000 → 31,000 frames in 400 s |
| `d758739` | Joins of large sets remembered (sets never change) | side by side: 15,000 frames in 52 s against 90 s |
| `3444750` | A global container whose candidates are already in is skipped | side by side: 25,000 frames in 129 s against 179 s |
| `a5671c5` | Root indexes made when a set is first searched | root index slots at 34,000 frames 50.7 M → 27.7 M; same speed |
| `d946517` | An alternative packed into 27 bytes instead of 51 | the 2 GiB region holds 79.5 M alternatives instead of 42.1 M; same speed |
| `e6ee473` | Root classes of large sets compared through a hash of the class | side by side: 40,000 frames in 163 s against 210 s |
| `be255ed` | A load gathers contents only where its type keeps them | side by side: 40,000 frames in 155 s against 163 s; 4% fewer alternatives per frame |

"Side by side" runs started together under the same load (11–18 on 16 threads) and compare progress builds; every other row compares runs at different times, so only large ratios count. Each commit message has its numbers and the run's conditions.

## Equivalence

- `scripts/qualify.py` on 2026-11-15, on main's sources at `be255ed` (as commit `ea2d4d8`, with the same tree), against the `9806f0e` compiler: bootstrap at a fixed point (C `af198c33…`, executable `6fa0f811…`, no profile); 10,689 of 10,793 conformance rows passed, and the only failures were the 104 recorded gaps; 54 of 54 native checks passed; the unit tests passed; and 0 of 10,049 outputs differ. [Summary](qualification.json)
- `tests/output_equivalence.py` against the `9806f0e` compiler, after every commit: 0 of 10,049 compilations differ (`--check` of every conformance source, native `-O0`/`-O2` and Wasm `-O2` of every corpus source, and `--check` and native `-O0`/`-O2` of a frozen copy of the candidate's own sources, with `native/` beside it).
- The analysis state: `tools/instrument.py fingerprint` hashes it at the start of every discovery pass, after discovery and after validation: every set reachable from roots, cells, frames, effects, summaries, items and exits, by its ordered alternatives. It is the 2026-11-14 set-sharing tool with set IDs left out, since `4663c09` renumbers sets, and with the caches keyed by set ID (offers, atoms, bound and join memos, summaries' last-seen sets) left out. Baseline and candidate printed the same 5,313 fingerprints on 4,355 conformance sources (1,488 reach the pass) after every commit, and the same 7 on the compiler checking itself.
- On blot2 itself, the `fpframes` mode adds a fingerprint every 2,000 frames. The `3444750` build and the baseline printed the same 14, up to 28,000 frames, where the baseline stood after 14 minutes. The order of every list is part of each hash: which message a node reports can depend on it.

## Upstream patches, mapped

blot2's private patches to upstream `32a4f44` (`compiler-goose/tools/upstream-32a4f44/` at `93c8fa8`) list the speed and memory changes that keep output: 08–11, 18 and 20–29. Our pass ports upstream's algorithm, not its data structures, so each maps to an idea rather than to code:

| Patch | Upstream | Here |
| --- | --- | --- |
| 29 read-back candidates | ReadBackRoot adds distinct candidates directly | `f00c04f` (no atom per candidate) and `3444750` (a covered container adds nothing) |
| 23 root candidates index | RootCandidates joins candidates through an index | LifeBuild already joins through a root table (8694f1f); `5d29ab5` keeps the global list |
| 21 mapped roots in place | no copy per mapped root set | `f00c04f`: transforms add alternatives in place |
| 18 shared body snapshots | unchanged event chunks shared between records | `4663c09`: equal lists are one set |
| 27 tabled class params | a table of parameter classes during a replay | the class scans that cost here were argument-class comparisons: `8ea3034` |
| 08, 20 holder event index and scans | per-holder store events instead of whole-log scans | no program-wide store log here; the shrink and hold scans run in validation, which was not reached |
| 10 traversal buckets | bucketed visited types | type walks never showed in the profiles |
| 25 walk callbacks in place | no allocation per visited node | our walks use explicit stacks and memoized answers already |
| 11 shrink origins, 26 BCE facts, 22 and 28 code generation memos | diagnostics and other passes | nothing to port in this pass |

Patches 12–17 accept code upstream rejects and are not ported.

## Rejected and not kept

- **A whole-read-back memo** keyed by the place set, for places that are all globals. `3444750` covers most of the same cost exactly (two containers' work per read-back instead of all of them) without a cache to invalidate; not built.
- **A collector for unreachable lists.** At 40,000 frames 9.8 M of 23.0 M alternatives were reachable from the analysis state (43%; 60% at 5,000–15,000 frames, `tools/livestats.py`), so compaction would gain about 2.3×. Set IDs are held in locals all through an evaluation, so the only safe points are activation exits, with a scan of all persistent state each time. Not attempted.
- **Larger regions.** A build with 16 GiB regions (`-DGS_STACK_RESERVE`) is only an exploration tool: it changes the runtime every emitted program carries. It ran pass 1 for 1,157 s, to 95,000 frames, 86.6 M alternatives (64-byte), 6.0 M effects and 247 M root-index slots, and was stopped with the machine's swap nearly full. Pass 1 had not ended.
- **Hash-consing list suffixes.** A join lists the new roots before the old list reversed, so consecutive sets share no suffix; suffix sharing would need a different list representation everywhere a set is walked.
## Where the cost is now

**Memory.** The analysis keeps every set it makes in arenas that only grow, and the alternatives' 2 GiB region is the first to fill. 27-byte alternatives (`d946517`) raised what it holds from 42.1 M to 79.5 M. The final build made 0.8–1.1 M alternatives per 1,000 frames from 50,000 frames on, and more each 1,000 frames than the last near the end (70.9 M at 90,000, 77.9 M at 93,000). Somewhat more than half are garbage: at 40,000 frames 9.8 M of the 23.0 M alternatives were reachable from roots, cells, frames, effects, summaries, items and exits. Attributing the alternatives made by 49,000 frames to the function whose build or join made them (`tools/allocstats.py`, `tools/joinstats.py`, on the `3444750` build):

| Made by | Share |
| --- | ---: |
| joins (summary merges 29% of all; value merges 5%, small joins in builds 3%, root contents 2%) | 40% |
| `life_contents` (the contents of the places a load reads) | 17% |
| `life_load`, mutable globals added to a load's contents | 13% |
| read-backs | 7.5% |
| bounds, slot loads, interiors, atoms, parameter roots, stored roots | 3.5%, 3.2%, 3.0%, 2.8%, 2.0%, 1.9% |

Discovery records an effect on a global at every frame up the chain, and each summary entry grows by joins, so an entry's every size is a separate list. Effects (152 bytes each) and summaries (96 bytes) grew to 6.0 M each by 95,000 frames in the exploration run, inside their regions but 1.5 GB together.

**Time.** In the final build's profile on blot2 (200 s, `life_*` 74% of samples, type checking most of the rest):

| Function | Self | Note |
| --- | ---: | --- |
| `life_function` | 13.6% | finding a call's frame: the active chain, then every frame of the function, then every frame of the call site |
| `life_effect` | 10.1% | walking each offer up the frame chain; 64.8 M of 71.7 M summary merges by 21,000 frames were construction reads (kind 3) |
| builds (`life_build_slot`, `_push`, `_order`, `_open`, `_add_alt`) | 16% | read-back and contents builds of about 1,000 global roots |
| `life_list_set` | 5.4% | hashing and comparing each new list |
| `life_temporary` | 4.0% | a node's temporaries are one chain over every frame |

Summary-merge chains are short (71.8 M steps for 71.7 M merges, at most 3); their cost is the number of merges.

**How far.** Pass 1 had not ended at 95,000 frames and 1,157 s even with 16 GiB regions (above). Later passes revisit every frame, and validation runs once more after the last. The reference build that blot2 uses (patches 01–29) checks the whole program in 435 s with a peak RSS of 17.9 GiB on this copy (table below; blot2 recorded 9.5 GB for the same build), and its precision patches cut work this analysis must do.
## Native emission and diagnostics

Neither was reached. The lifetime pass reports its diagnostics only after discovery reaches a fixed point (failures found during discovery wait until then), and pass 1 did not end, so no diagnostic of this compiler on blot2 is known.

- `--target native -O0 -o out.c` needs a root this program does not have: without `main` the driver stops with "program requires fn main()". `--library`, the C-host mode, type checks every function, not what the export reaches. On this copy it reports 135 type errors in unreached code in 21 s, before the lifetime pass (93 "recursive cycle requires recursive declarations", 16 "index_of requires a fixed-stride array owner", 5 "unknown name", 5 implicit conversions, 4 definite assignment, 4 allocation pools, 2 record literals and 6 others), the same groups as the 2026-11-13 attempt minus its root-struct guard. Emitting blot2 will take either a `main` that calls `blot_main::mainEntry()` or `--library` limited to what `--reachable-program` reaches.
- What to expect once it runs: upstream with patches 01–11 stops at its first lifetime error, `reuse/code_expectation.goose:40`, "returning a reference rooted in n, which dies with this function (§9.2)", in `children`, which returns `view.extra[n.a..n.a + n.b]` for `let n = view.node(id)` ([stderr](runs/ref-patched-01-11.stderr.txt)). blot2's own build passes it with precision patches 12–17 (used-after frame skip, global empty facts, copied argument contents, finite copied globals, options roots, static-known contents). This analysis follows plain upstream, so it will likely report that site too; which of 12–17 accepts it was not determined (the patch files left blot2's checkout during the work).

## Reference builds on the same copy

`goose check main.goose --stdlib <its source>/stdlib`, in the copied directory, on blot2's builds of upstream `32a4f44` (compiled with `-DGOOSE_EXPANSION_NODE_LIMIT=1000000 -DGOOSE_REACHABLE_PROGRAM=1`, per the series header). Pinned to CPUs 0–5, while other work ran. [Records](runs.jsonl)

| Build | Patches | Result | Wall | CPU | Peak RSS |
| --- | --- | --- | ---: | ---: | ---: |
| plain upstream | none | killed by a 1,200 s timeout, unfinished | 1,200 s | 1,149 s | 0.78 GiB (400,626 major faults) |
| patched | 01–11 | stops at its first lifetime error, `reuse/code_expectation.goose:40` | 66 s | 58 s | 2.63 GiB |
| blot2's build | 01–29 | checks the whole program: exit 0, 395 warnings, no errors | 435 s | 400 s | 17.9 GiB |

The first two ran on 2026-11-14 at load 13–17. The run of blot2's build that day was cut off when the machine restarted, so it was run again on 2026-11-15 at load 8–9. The patched build's [stderr](runs/ref-patched-01-11.stderr.txt) is kept; the other two printed no errors.

## Small programs

Small programs compile in the same time as on `9806f0e`.

`tools/small.py` timed the baseline, the final build and every intermediate build in 41 interleaved rounds, pinned to CPU 7, each with a fresh process. The table gives median wall time per compile, and minor page faults (median, baseline / final). [All builds](small-programs.json)

| Compile | `9806f0e` | final | Page faults |
| --- | ---: | ---: | --- |
| empty `fn main() {}`, `--check` | 2.69 ms | 2.70 ms | 236 / 236 |
| sorting, `--check` | 15.67 ms | 15.66 ms | 1,213 / 1,210 |
| sorting, native `-O2` | 34.62 ms | 35.56 ms | 1,758 / 1,755 |

The native row is noise: across the ten builds its median ranges from 34.5 to 36.2 ms, in no order of the commits.

`bench/compare_compilers.py` over the eleven benchmark programs gave these geometric means, final / `9806f0e`. [Reports](compiler-comparison.json)

| Run | CPU · seed | Wasm | C | All 22 cells | Cell range |
| --- | --- | ---: | ---: | ---: | --- |
| primary | 7 · 900614 | 1.007 | 1.011 | 1.009 | 0.98–1.04 |
| replicate | 5 · 900615 | 1.009 | 1.018 | 1.014 | 0.97–1.05 |
| null: `9806f0e` against a copy of itself | 7 · 900616 | 1.009 | 1.012 | 1.010 | 0.98–1.05 |

The null run spreads as far as the real ones, so the final build is the same speed within noise.

## Tools

`tools/` holds the scripts used, written for the worktree's `build/tools/` (paths are absolute there): `mk.sh` (an experiment build), `run.py` (wall, CPU, peak RSS and faults of one child), `progress.py`, `instrument.py` (content fingerprints; `fpframes` mode for blot2), `fpcompare.py`, `small.py`, `tabulate.py`, and the diagnosis-only counters `rbstats.py`, `allocstats.py`, `joinstats.py`, `livestats.py` and `mergestats.py`, none of which is in a kept commit. `runs/` holds the `LIFEPROG`/`LIFEFP`/`LIFELIVE` lines of the runs quoted here; `runs.jsonl` their wall, CPU and RSS.
