# Lifetime walks, replays and lookups · 2026-11-15

Eight commits stop the lifetime analysis from repeating work that changes nothing. The compiler checks itself in 7.0 s instead of 24.7 s, and the first discovery pass on blot2's compiler reaches the point where it stops, 93,000 call contexts (frames), after 102 s instead of 605 s. Every output is unchanged, and so is the analysis state: after each commit it matched `86f7a18`'s at every pass boundary on 4,355 conformance sources and on the self-check, and the final sources match at every 2,000 frames of blot2's first pass as far as the baseline was run (76,000 frames).

**blot2 still does not finish, and this page measures how far from finishing it is.** When the alternatives' 2 GiB region fills, the pass has entered 2,854 of the program's 27,923 reached functions. It makes a frame for every set of concrete argument roots a function is called with, where upstream checks a function once per class of them, and recursive tree walkers multiply that. [How far the first pass is](#how-far-the-first-pass-is)

## Workloads and machine

- **Self-check.** The compiler checking a frozen copy of its own final sources (`selfhost/` at `fe05443`: 28,228 lines, 35 files with the standard library, 1,421 functions): `goose main.goose --target native --check --stdlib stdlib`. It runs five discovery passes and validation over 2,437 frames. The walk, offer and replay counts quoted below are from the same check of `86f7a18`'s sources (2,429 frames), where they were measured.
- **blot2.** blot2 commit `93c8fa828a8897d2369ad80c0a737767ca345c71`, `compiler-goose/src`, 451 files: the copy of the [2026-11-14 run](../../2026-11-14/blot2-lifetimes/README.md), taken again with `git archive`. Its identity, `find . -type f | sort | xargs sha256sum | sha256sum`, is `91598806…` as recorded there when `sort` runs under `en_US.UTF-8`, and `47674ec6…` under the `C` locale this machine defaults to. Command: `goose main.goose --stdlib <repo>/stdlib --reachable-program --expansion-node-limit 1000000 --check`.
- **Machine.** A cloud container with 4 cores and 16 GiB shared by every process, no swap, otherwise idle during the timed runs: Linux 6.18, Clang 18.1.3, GCC 13.3, Python 3.13, Node 22. It is not the machine of the 2026-11-14 page, so times are compared only within this page. The baseline's counters (frames, effects, sets, alternatives) are the ones recorded there.

## Compilers

Two kinds of build, neither with a profile (the supplied one is for Clang 23):

- **Bootstrapped**, by `scripts/bootstrap.py --verify` inside `scripts/qualify.py`: one C unit, `clang -std=gnu11 -O2`. The self-check result, the small programs and the eleven benchmark programs use these.
- **Progress builds**, as the 2026-11-14 page built them (`tools/mk.sh`): the same C plus `LIFEPROG` lines of table sizes, as eight units. The per-commit rows and the blot2 times use these, since the lines time pass 1.

| Build | Sources | Generated C sha256 | Bootstrapped executable |
| --- | --- | --- | --- |
| baseline | `86f7a18` | `af198c33cfdef2621988d5a0190fa2962739995b79d732f5f088af5c87a3036a`, the C recorded for these sources on 2026-11-14 | `0053a47c…` |
| final | `fe05443` (`a26e011` has the same `selfhost/`) | `6b004c516d8dfdf379df51cd0d000b927cf821a8b4d6460c63e47aa582c2ce1c` | `b4a27b02…` |

## Result

| Workload | `86f7a18` | final | Ratio | Peak RSS |
| --- | ---: | ---: | ---: | --- |
| Self-check, wall | 24.7 s | 7.0 s | 0.29 | 443 → 456 MiB |
| Self-check, lifetime pass (`--wasm-stats`) | 24.4 s | 6.7 s | 0.27 | |
| blot2, pass 1 to 93,000 frames | 605 s | 102 s | 0.17 | 7,721 → 7,474 MiB |
| blot2, whole run (it ends with `data stack overflow`) | 621 s | 116 s | | |

Self-check values are medians of five interleaved runs of the bootstrapped compilers, pinned to one core ([rows](selfcheck-bootstrap.json)); blot2 runs are of the progress builds, one at a time ([records](runs.jsonl)). The bootstrapped final compiler's blot2 run took 117 s with the same 7,474 MiB. Both builds stop blot2 at the same place with the same tables: 93,000 frames, 5,835,111 effects, 2,697,493 sets, 77,920,313 alternatives of the 79.5 M that fit, 558,012 activations.

## The commits

Seconds are the self-check's lifetime pass (median of five interleaved runs) and blot2's pass 1 from its start to 93,000 frames, each on a progress build of that commit; blot2 was run on six of the nine builds. One build differs from the next by about a second on the self-check, and two on blot2, for reasons the work done does not explain: `b411c7f` without its 32-bit fields measured 10.1 s, and `fe05443` only moves a counter. [Self-check rows](selfcheck-stages.json) · [blot2 progress lines](runs/)

| Commit | What it stops repeating | Self-check | blot2 |
| --- | --- | ---: | ---: |
| `86f7a18` | | 22.7 | 605 |
| `60871b7` | Walks up the chain that every frame has already taken | 12.3 | 511 |
| `826e892` | A call's chain walks and scans of the globals' cells | 11.8 | |
| `48c4cf4` | Replays of a summary entry into the same activation | 10.3 | 444 |
| `b411c7f` | A load's contents and tail; chains of cells and temporaries | 11.3 | 129 |
| `f96470c` | Read-backs through globals; scans of a function's frames | 10.8 | 100 |
| `2cc4840` | Walks of everything a function reaches, for its captured and global reads | 9.3 | |
| `a7ac66b` | Reference types that cannot reach a shrunk array | 7.4 | |
| `fe05443` | (the active-frame count moves from an array per node to the newest frame) | 6.3 | 102 |

What each does:

- **Walks.** An effect whose places lie outside a frame is offered to every frame up the chain of active frames, and each takes it into a summary entry. Almost every offer finds each entry already holding the same sets. An entry now records the activation in which an offer of its last sets went on up the chain. The chain above a frame does not change during its activation, so the same sets offered there again have nothing to add further up, except at a recursive frame, which also takes an effect by what its parameters may reach. The walk therefore stops at the first such entry and goes straight to the recursive frames at or above the outermost frame that holds one of the places. How far up that frame is comes from a chain position kept on each frame instead of a walk per place. Validation's lists have the same mark for the effects that are compared by content. On the self-check the discovery walk took 196.3 M steps before and 24.9 M after; validation's 26.4 M and 2.7 M.
- **Calls.** A call walked the whole chain looking for the frame of the callee's enclosing function, which a top-level function does not have; searched the chain for an active frame of the callee when none was active; and scanned every cell of frame 0, all the globals, for a live root deeper than depth 0, once for the call and once per parameter. Frame 0 now keeps the few cells that can be deeper (locals of global initializers).
- **Replays.** A call to a frame already checked in the pass replays its summary, and a recursive call replays the active frame's. On the self-check those replays were 19.6 M of the 19.9 M discovery offers. An entry now remembers the activation it was last replayed into; replaying the same sets into it again only repeats offers and joins that changed nothing the first time, unless one of its places is in a recursive frame of the chain. 12.0 M offers remain.
- **Loads.** What a load reads through its places (`life_contents`) is the same set as long as no root among them has had its contents changed, and each root keeps a stamp of its last change; the mutable globals and slot flags a load then adds depend only on two sets. On blot2, 97.6% of `life_contents` calls and 97.5% of those tails recomputed an answer whose inputs had not changed (measured to 40,000 frames, with no mismatch against recomputation in 953,101 hits). A read-back through global containers likewise depends only on its type, its places and the global cells, which already carry an epoch.
- **Lookups.** A symbol's cell and a node's temporary in the current frame were found by walking a chain over every frame that has one, and a call's frame by trying every frame of the function. They are hashed: cells and temporaries by frame, frames by what `life_arguments_equal` compares and by caller and call node. A function whose frames have arguments of differing kinds, which a dispatched call can produce, keeps the scan.
- **Summaries of reads.** Whether a function's body may read a captured binding, and which globals it may read, were found by walking every node the function can reach through calls, once per function. Each body's own nodes are now scanned once, and a walk goes from body to body.
- **Shrinks.** Validation asks of every live holder whether a reference it holds may point into an array being shrunk, by trying every reference type in the holder against every alternative it holds. A reference type that can neither point into the array's elements nor lead on to further holders is skipped unless a byte view is among the alternatives.

## Equivalence

- **Qualification.** `scripts/qualify.py` on 2026-11-15, on the final tree (`d645d99e…`, as commit `86f0f01`), against the compiler bootstrapped from `86f7a18`: bootstrap at a fixed point (C `6b004c51…`, executable `b4a27b02…`; no profile, since the supplied one is for Clang 23); 10,689 of 10,793 conformance rows passed, and the only failures were the 104 recorded gaps; the native rows again as three program units, because `tests/conformance.py` changed, 5,924 of 6,020 with only recorded gaps failing; 54 of 54 native checks passed; the unit tests passed; and 0 of 10,049 outputs differ. [Summary](qualification.json)
- **Analysis state at pass boundaries.** [`instrument.py fingerprint`](../../2026-11-14/blot2-lifetimes/tools/instrument.py) hashes the state at the start of every discovery pass, after discovery and after validation: every set reachable from roots, cells, frames, effects, summaries, items and exits, by its ordered alternatives. A build of each commit printed the same 7 fingerprints as the baseline on the self-check and the same 11,589 on 4,355 conformance sources (3,128 reach the pass), with the same stdout and diagnostics. [Log](runs/stagecheck.txt)
- **Analysis state inside blot2's first pass.** The `fpframes` build adds a fingerprint every 2,000 frames. The baseline printed 39 in 1,500 s, up to 76,000 frames; the final build printed the same 39 and went on to 80,000 before it was stopped. [Baseline](runs/fpframes-86f7a18.txt) · [Final](runs/fpframes-final.txt)
- **Counters.** Each blot2 run in the table above ends with the same frames, effects, sets, alternatives, cells, roots, items and activations.
- **The replaced searches, run side by side.** [`tools/xcheck.py`](tools/xcheck.py) makes a build that repeats the linear frame searches after the indexed ones and the node-by-node walks beside the body summaries, and reports any difference. None on the self-check (146,082 frame searches, 1,398 capture walks, 1,398 global walks), on the conformance sources (83,113 searches, 15,463 capture walks and 2,151 global walks in the 2,872 sources that complete the pass), or on blot2 to its stop. [Corpus result](runs/xcheck-corpus.json)
- **Paths the corpus does not reach.** [`tools/pathcorpus.py`](tools/pathcorpus.py) counts how often each new path runs on the conformance sources ([counts](runs/paths-corpus.json)): settled walks in 290 sources and 876 in validation, replay skips in 102, offers with a place in a recursive frame in 145, remembered contents, loads and read-backs in 261, 425 and 135, deep cells of frame 0 in 14, byte views among held alternatives in 19. Two paths never run there. No source has a function whose frames have arguments of differing kinds, so [`mixed-kinds.goose`](runs/mixed-kinds.goose) was written to have one: by-value overloads called both dispatched and directly. It takes the scan path 6 times; its fingerprints and emitted C are the baseline's, and the cross-check build finds no difference. No source enters a frame that is its own lexical frame, where a parameter's reach is still computed per parameter as before.

## How far the first pass is

`tools/coverage.py` counts, on each progress line, the functions that have at least one frame.

| Frames | Functions entered | Frames per function | Deepest chain |
| ---: | ---: | ---: | ---: |
| 10,000 | 1,679 | 6.0 | 39 |
| 20,000 | 2,191 | 9.1 | 68 |
| 30,000 | 2,308 | 13.0 | 70 |
| 40,000 | 2,500 | 16.0 | 77 |
| 50,000 | 2,657 | 18.8 | 100 |
| 60,000 | 2,677 | 22.4 | 100 |
| 70,000 | 2,695 | 26.0 | 100 |
| 80,000 | 2,737 | 29.2 | 100 |
| 90,000 | 2,772 | 32.5 | 100 |
| 93,000, where the 2 GiB region is full | 2,854 | 32.6 | 100 |
| 110,000 | 2,854 | 38.5 | 106 |
| 130,000 | 2,859 | 45.5 | 106 |
| 150,000 | 2,912 | 51.5 | 106 |
| 168,000, stopped at 12 GiB resident | 2,945 | 57.0 | 106 |

The program has 27,923 reached functions. The rows past 93,000 are from an exploration build of the final sources whose own regions are 16 GiB (`-DGS_STACK_RESERVE` on the compiler's own C; the C it emits for a program, checked on `examples/sorting.goose`, is byte-identical). It ran 244 s into pass 1 and was stopped at 12 GiB resident, under this machine's 16: 168,000 frames, 142.3 M alternatives, 12.9 M effects. The 75,000 frames past the old stopping point entered 91 more functions. Pass 1 has not ended there either; later passes revisit every frame, and validation follows. [Coverage lines](runs/coverage-final.txt) · [Exploration](runs/explore-16g.txt)

Where the frames go, at 90,000 ([dump](runs/dump-90000.txt), and [at 30,000](runs/dump-30000.txt)): 1,426 functions have one frame, and 18 functions have 36,700 of the 90,000 between them. The largest are `bind` (4,012), an operator function (3,800), `append` (3,777), `aggregate` (3,777), `corePattern` (2,880), `hasName` (2,536), `pattern` and `bindPattern` (1,485 each). Their frames differ in two ways:

- **A local of each recursion level.** `aggregate`'s frames all have the same first argument and a third that is `children` of one `bindPattern` frame or another, at depths 51, 53, 59, 67. `pattern` calls `bindPattern` calls `pattern`, each level has its own `nested` and `children`, and everything those are passed to gets a frame per level and per context the recursion is entered from. `hasName` is called with up to twelve levels' `locals` at once.
- **The depth a reference was read at.** A reference read out of a container may point into any of about 2,600 globals, bounded by the container's depth. The operator function's frames have two arguments of 2,601 alternatives each that differ in that bound (19, 26, 28, 40, …), so each depth is another 2,601-alternative set, twice, and another frame.

Upstream does not do this. A specialization's key is, per reference or holder argument, the class of its root: its outlives rank among the call's arguments and some flags (`GetOrCreateSpec` in `typecheck_calls.h` and `RootArg` in `ast.h` at `32a4f44`). The body is checked once per key against class roots, and each call maps the record onto its own arguments. This pass ports upstream's rules but keys a frame by the concrete root sets. It searches for a class-equal frame only among the active ones, to find recursion.

So the remaining distance is not a constant factor. From 50,000 to 168,000 frames the pass entered 288 functions, about 400 frames for each; the other 25,000 would take millions of frames at that rate, where the present tables hold 93,000. Finishing blot2 needs frames keyed by argument classes with the callee's summary mapped onto each caller, as upstream does. That changes which contexts are analyzed, so the state comparison above would no longer apply and the contracts would have to carry the equivalence.

## Where the cost is now

**Self-check** (7.0 s, of which the lifetime pass is 6.7 s; [profile](runs/profile-self-final.txt)). Five discovery passes of about 1.1 s and a validation of 1.4 s.

| Function | Self | Note |
| --- | ---: | --- |
| `life_effect` | 54% | 48% is construct reads offered from replays: the first replay of each entry into each new activation still looks its entry up in the current frame and often the next |
| `life_replay` | 9% | the loop over entries, including the ones it skips |
| `life_held_into` | 6% | validation's shrink check |

Passes four and five change almost nothing and cost as much as the third. What repeats now is across activations, not within one: every frame is evaluated again in every pass, and every entry is offered again the first time.

**blot2** (102 s to the stop, 85.6% of samples in `life_*`; [profile](runs/profile-blot2-final.txt)).

| Function | Self | Note |
| --- | ---: | --- |
| builds (`life_list_set`, `life_build_slot`, `_push`, `_add_alt`, `_order`, `_open`) | 34% | read-backs through containers that are not all global, and joins; `life_list_set` alone is 10%, hashing and comparing a list to find it already exists |
| `life_readback` | 10% | the candidates of a local container: every live cell |
| `life_effect` | 9% | |
| `life_find` | 5% | subset tests before joins |
| `life_eval_body`, `life_contains` | 5%, 4% | |

`life_function`, 13.6% of samples on 2026-11-14, is 1.3%. `life_cell` and `life_temporary`, 6.6% and 6.0% before `b411c7f`, are under 1%.

## Rejected and not kept

- **A mark only for offers with a place outside the chain.** The first version recorded a walk only when a place was outside every frame, where every frame takes the offer. On the self-check 260 of 19.9 M discovery offers are like that: places are almost always in a frame near the top of the chain. No change in time. The kept version covers places in frames of the chain.
- **Stopping only when no frame above is recursive.** The second version stopped at a marked entry unless a recursive frame was above it, and otherwise walked on as before. The compiler's own chains nearly always contain a recursive frame: 113.9 M of 118.5 M marked entries had to walk on, and steps fell only from 196.3 M to 121.6 M. The kept version visits just the recursive frames.
- **Remembering a whole replay per caller activation.** 13,011 of 21,920 replays per pass on the self-check go into an activation that replayed the same frame before, but only 2,529 of them with no recursive frame on the chain, and a recursive call's target is still growing. The kept memo is per entry, with the recursion test per offer.
- **A better bucket hash for summary entries.** A merge call still passes 0.7 entries of other keys on its way. The hash was left alone: a store's entry is found only among entries whose places list begins with the same root, because that root is part of the bucket, and any other hash would let two entries with the same places in different orders meet and merge. That changes which entries exist.
- **A small direct-mapped memo for `life_gs_contains`.** 256 entries keyed by owner and pointee thrashed on blot2, where one store asks about one pointee for the types of 2,600 sources; the walk stayed at 4% of samples. The kept memo holds the last answer per owner type, as `life_contains_memo` does.
- **32-bit marks without a guard.** The activation numbers in the marks are 32 bits to keep a summary at 108 bytes. A count past 2^30 would wrap, so the marks switch themselves off there. No run here comes within a factor of a thousand of it.
- **Not attempted: memory.** Nothing here makes fewer alternatives, so blot2 stops where it did: the repeated builds these commits skip made no new lists, because an equal list is found and shared. Peak RSS at the stop is 7,474 MiB, against 7,721 before: the root index halved, and the new tables took back about half of that. The 2026-11-14 page's candidates stand (a collector for unreachable lists, about 2.3×; lazier summary joins; effects and summaries packed into 32-bit fields), but with the first pass a tenth of the way through the program's functions they would move the stopping point, not reach the end.

## Small programs

Small programs compile in the same time, with the same page faults.

`small.py` timed the two bootstrapped compilers in 41 interleaved rounds, pinned to one core, each run a fresh process. The table gives median wall time, and minor page faults (median, baseline / final). [Rows](small-programs.json)

| Compile | `86f7a18` | final | Page faults |
| --- | ---: | ---: | --- |
| empty `fn main() {}`, `--check` | 2.97 ms | 2.90 ms | 218 / 218 |
| sorting, `--check` | 10.59 ms | 10.24 ms | 1,196 / 1,197 |
| sorting, native `-O2` | 20.84 ms | 20.74 ms | 1,738 / 1,729 |

`bench/compare_compilers.py` over the eleven benchmark programs gave these geometric means, final / `86f7a18`, 31 samples per cell. [Reports](compiler-comparison.json)

| Run | CPU · seed | Wasm | C | All 22 cells | Cell range |
| --- | --- | ---: | ---: | ---: | --- |
| primary | 3 · 900701 | 0.985 | 0.995 | 0.990 | 0.94–1.05 |
| replicate | 2 · 900702 | 0.978 | 0.995 | 0.987 | 0.92–1.02 |
| null: `86f7a18` against a copy of itself | 3 · 900703 | 0.977 | 0.968 | 0.973 | 0.89–1.02 |

The null run spreads further than the real ones, so the difference is within this machine's noise.

Across the 10,049 compilations of the equivalence run, which include the compiler compiling itself three ways, the baseline compiler spent 322 s and the final one 188 s.

## Tools

`tools/` holds what this page added to the [2026-11-14 tools](../../2026-11-14/blot2-lifetimes/tools/), which were used with their paths changed: `tab.py` (progress lines as a table), `coverage.py` (functions entered, and the frame dump), `cnt2.py` (walk, merge and replay counters), `xcheck.py` and `xcorpus.py` (the side-by-side searches), `pathcorpus.py` (how often each new path runs), `stagecheck.sh` (fingerprints of one commit's build against the baseline), `phase2.sh` and `stagetable.py` (the timed runs and their table), `watch_rss.py` (stops a run at a resident size), `mk.sh` (an experiment build, four units at a time), `deinstrument.py`, and `prof.c` with `report.py`, a `SIGPROF` sampler loaded with `LD_PRELOAD` that records the interrupted function and two callers; `--wasm-stats` gives the function names of the `g_fnN` symbols. `runs/` holds the lines quoted here and `runs.jsonl` the wall, CPU and RSS of each run.
