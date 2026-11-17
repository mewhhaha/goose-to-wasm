# The lifetime pass holds a read in 32 bytes, 2026-11-17

Since `a787c63` the compiler checks its own source in 0.64 of the CPU time it took at `9151d87` this morning and in 0.34 of what it took at `ddbbe23` yesterday, with a peak of 306 MiB instead of 568. It compiles itself in 0.72 to 0.75 of the time. The analysis reads the same thing: the same lists in the same order in every frame, on the self-check, on 4,355 conformance sources and on blot2, and all 10,049 outputs are byte for byte the previous compiler's.

As a Wasm module it now runs under V8 on its own source without a region profile, which it needed until today.

This follows [the read memos](../lifetime-read-memos/README.md) of the same day, whose "Not done" named both things done here: validation, and a summary entry for every read in every frame.

## What was measured

- **Source and compilers:** "before" is `9151d87`, "validation" `e5e8dc6` (the first three steps below) and "after" `a787c63`, each the bootstrapped compiler of its qualification (executables `135f9f8f33ce…`, `01b9eebb1484…` and `aa1547c396e4…`; [validation](runs/qualification-validation.json), [after](runs/qualification.json)). The step table uses development builds ([tools/mk.sh](tools/mk.sh): the generated C as eight units, `clang -O2`).
- **Workload:** `selfhost/main.goose` at `a787c63` (31,126 lines in `selfhost/`), as `--check`, to 32-bit Wasm (`-O2 --wasm-max-pages 65535`) and to C (`-O2`).
- **Machine:** 4 cores, 16 GiB, Linux, clang 18.1.3. Seven interleaved runs each, pinned to one core; CPU seconds (user + system) and peak RSS of each run, all in [native.json](runs/native.json) ([tools/native.py](tools/native.py)).

## Result

| the compiler, on its own source | before | validation | after | after / before | peak RSS, before → after | same output |
| --- | ---: | ---: | ---: | ---: | --- | --- |
| check | 6.95 s | 6.08 s | 4.42 s | 0.64 | 568 → 306 MiB | |
| to 32-bit Wasm | 9.88 s | 9.02 s | 7.09 s | 0.72 | 714 → 452 MiB | yes |
| to C | 9.61 s | 8.70 s | 7.19 s | 0.75 | 677 → 414 MiB | yes |

Medians of seven. The check ranged over 6.5 to 7.9 s, 5.8 to 6.4 s and 3.5 to 4.6 s.

**Against yesterday.** The three delivered compilers in one run, five interleaved checks each ([since-ddbbe23.txt](runs/since-ddbbe23.txt)): `ddbbe23` 11.46 s and 503 MiB, `9151d87` 6.51 s and 568 MiB, `a787c63` 3.86 s and 306 MiB. That is 0.34 of yesterday's time.

**Small programs** are where they were. `--check`, minimum CPU time of 60 runs and page faults ([small-programs.txt](runs/small-programs.txt), [tools/small.py](tools/small.py)):

| | before | after |
| --- | --- | --- |
| an empty `main` | 3.36 ms, 233 faults | 3.15 ms, 230 faults |
| `examples/squares.goose` | 3.00 ms, 273 faults | 3.01 ms, 269 faults |
| `examples/tour.goose` | 5.82 ms, 499 faults | 5.66 ms, 478 faults |

**As a Wasm module under Wasmtime** 50.0.1 (`host/rust`), the sources before and after each built as a 64-bit module, three interleaved runs ([hosted-pair.json](runs/hosted-pair.json), [tools/hosted_pair.py](tools/hosted_pair.py)):

| the module, on the compiler's source | before | after | ratio |
| --- | ---: | ---: | ---: |
| check | 19.9 to 21.2 s | 12.8 to 13.6 s | 0.64 |
| to 32-bit Wasm | 29.0 to 30.5 s | 21.9 to 22.7 s | 0.75 |

**Under V8** 12.4 (Node v22.23.4; [v8.txt](runs/v8.txt), [tools/v8.sh](tools/v8.sh)):

| the new module under V8 | check | compile itself |
| --- | --- | --- |
| 64-bit, 16 GiB, equal regions (no profile) | 15.4 s, three runs | 28.5 s, its own bytes |
| 32-bit, 4 GiB, equal regions | stops at once: `data region exhausted (line 277)` | |
| 32-bit, 4 GiB, regions by a profile | 13.2 to 14.0 s | 25.1 s, its own bytes |

- Until today the 64-bit module needed a profile under V8: the effect list alone wanted 176 MB, and an equal share of 16 GiB is 147 MB. With a profile it took 24.7 to 25.5 s and 38.0 to 38.8 s this morning.
- The 32-bit module took 20.6 to 21.7 s and 34.8 to 36.3 s this morning. It still needs a profile.
- A profile of a self-compile now has 103 regions and 466 MB of peaks, the largest 110 MB. Yesterday's had 664 MB, the largest 176 MB.

**blot2** does the same work, and the delivered compiler takes 3 to 6% longer over it. Past 4,096 frames calls are keyed by classes, and the reads are ordinary entries again from there on.

- Two timed runs each ([blot2-time.txt](runs/blot2-time.txt), [tools/blot2time.py](tools/blot2time.py)): 302 and 304 s of CPU before, 320 and 313 s after, the same 38 diagnostic lines, peak RSS 7,383 and 7,393 MiB.
- Same work: timestamps every 1,000 frames ([before](runs/blot2-progress-before.txt), [after](runs/blot2-progress-after.txt)) show the same number of effects at every step from frame 5,000 on. The difference in that pair of builds is 4% at every step, from the first thousand frames; it is not located in any phase.
- A third pair of builds, for the sampler, went the other way: 79,112 samples before and 75,702 after ([profile](runs/blot2-profile-after.txt)).
- Why the delivered pair differs is not established. What the profile does show: 58% of blot2's check is one function this change does not touch, `life_reads`, walking syntax trees to see whether a body reads a captured binding, and nearly all of its time is cache misses on the nodes. That function is the next thing to do for blot2.

## Where the time was

**Validation**, 2.2 s of a 6 s check, by timers in a development build ([tools/timers.patch](tools/timers.patch), [tools/valcount.py](tools/valcount.py), [tools/shrinkcount.py](tools/shrinkcount.py)):

| in one self-check's validation | |
| --- | ---: |
| shrink checks of an array (replayed from a callee's effects, nearly all) | 21,384, in 1.0 s |
| live cells those ask whether they point into the array | 778,504 |
| of them references | 704,929 |
| of them asking what an earlier cell of the same check asked | 552,506 (71%) |
| cells that do point into the array | 1 |
| types looked at for index types at each shrink | 2,192 |
| construct reads replayed from callees' effects | 2,406,869, in 0.4 s |
| of them found in the first frame's list | 99.8% |

A shrink check asks every live cell that is or holds a reference whether it points into the shrunk array. Every frame up the stack has a cell for the same few references (the program, the analysis state), so most questions repeat within one check. A replayed construct read was read whole (170 bytes) to find, by a hash lookup, that the list had it.

**Discovery.** After this morning's memos a summary still held one entry for every read in every frame: 988,405 of them, each a 170-byte effect, a 128-byte summary record and a hash insert, for 23,695 distinct reads ([counters-before.txt](runs/counters-before.txt), [tools/disccount.py](tools/disccount.py)). Replays went through 6.1 million of those entries, one cache miss each, and a profile put 6% of the run in one instruction: the lookup of a set that said which chains of frames a read had been offered to.

## What changed

All in `selfhost/checker_lifetimes.goose`. [tools/valfast.py](tools/valfast.py) and then [tools/compactreads.py](tools/compactreads.py) make the delivered file from `9151d87`'s. CPU seconds for the check, median of seven, and peak RSS, development builds ([steps.txt](runs/steps.txt)):

| step | check | of before | peak RSS |
| --- | ---: | ---: | ---: |
| before | 6.42 s | 1.00 | 568 MiB |
| 1. The index types that name a pool are listed once | 6.44 s | 1.00 | 569 MiB |
| 2. A shrink check asks a question once | 5.76 s | 0.90 | 569 MiB |
| 3. Validation passes a replayed read the activation was offered, without reading its effect | 5.42 s | 0.84 | 569 MiB |
| 4. A summary holds a construct read as a 32-byte entry naming its leaf | 4.01 s | 0.62 | 346 MiB |
| 5. The set of reads offered to each chain of frames is dropped | 3.89 s | 0.61 | 307 MiB |
| 6. The offering frame's own entry remembers the chain it sent the read up | 3.77 s | 0.59 | 306 MiB |

Steps 1 to 3 are `e5e8dc6`; 4 to 6 are `a787c63`.

- **Index types (1).** The timer gives the scan 71 ms of a 6 s check; the run timing cannot show that. It is kept because the cost grows with the number of types and shrinks, not because it was measured here.
- **Asked once (2).** Whether a value points into an array depends on a reference's pointee type and referents, or on a holder's type, place and contents, and on nothing the loop over cells changes. The answers of one check are kept in a list of at most 64.
- **Replayed reads in validation (3).** There a construct read does two things: it is recorded in the effect lists up the chain, and it is checked against the values under construction. The first is this morning's stamp on the read's leaf, now kept in validation too. The second is skipped when no such value is held, which in the self-check is always.
- **Reads by leaf (4).** A leaf already named a read by its node and value. An entry is now its leaf, the leaf it last took, a walk stamp and two links; a small open-addressed table per frame finds a frame's entry for a node and type. One self-check ends with 107,847 ordinary entries where it had 1.14 million, plus 988,405 reads of 32 bytes and 5.4 million 4-byte table slots: 85 MB where 341 MB were ([counters-after.txt](runs/counters-after.txt)).
- **Kept the same in 4:** which offers reach which frames, the test against the sets an entry last took, the join when they differ (the entry's leaf becomes the leaf of the joined value), the revision count, and the order of every frame's list. A read remembers the frame's last entry of another kind when it was added, and a replay goes through the two lists as the one they were.
- **Class-keyed frames.** They merge effects by kind and map them call by call, as ordinary entries. When the first one is made, every frame's reads become ordinary entries in the order they were added. That is blot2 after its first 4,096 frames.
- **The chain's memo (5, 6).** The set of step 3 this morning saved a walk over 300-byte entries at the price of one lookup in a table of a million. After step 4 that one lookup was 10% of the run, and the walk it saved cost as much. The same knowledge fits in the entry the walk starts from: the chain that entry's frame last sent its read up.

## What was checked

Steps 1 to 3 leave the storage alone, and keep the fingerprint of the earlier pages, which hashes the effect arrays index by index:

| `e5e8dc6` against `9151d87` | result |
| --- | --- |
| state at every pass boundary, self-check ([lines](runs/selfcheck-exact-lines-validation.txt)) | 7 of 7 lines the same |
| the same on every conformance source ([summary](runs/corpus-exact-state-validation.json)) | 4,355 sources, 11,589 lines, none differing |
| state every 2,000 frames on blot2 ([record](runs/blot2-exact-state-validation.txt)) | 28 of 28 lines and 38 of 38 diagnostic lines the same |
| qualification | fixed point; 10,689 of 10,793; 64-bit 4,765 of 4,773; 10,049 of 10,049 outputs the same; tests pass |

Steps 4 to 6 store entries differently, so that fingerprint cannot be equal. [tools/logicalfp.py](tools/logicalfp.py) hashes what the analysis reads instead: for each frame, in order, its summary list and its validation list, each entry by kind, node, value, places, cell and field, sets by their alternatives; and roots, cells, frames, items, the revision, activation and recursion counters and the diagnostic count as before. It does not hash indexes, links, or the memo fields (walk stamps, the sets last taken). Built into both sources:

| `a787c63` against `9151d87`, logical state | result |
| --- | --- |
| at every pass boundary, self-check ([lines](runs/selfcheck-logical-lines.txt), [record](runs/logical-state.txt)) | 7 of 7 lines the same |
| on every conformance source, with stdout and stderr ([summary](runs/corpus-logical-state.json)) | 4,355 sources, 11,589 lines, none differing |
| with class-keyed frames from frame 64 in both, so that the conversion to ordinary entries runs early: self-check and every conformance source ([lines](runs/selfcheck-logical-lines-threshold-64.txt), [summary](runs/corpus-logical-state-threshold-64.json)) | 7 of 7; 4,355 sources, 11,590 lines, none differing |
| the same from frame 1,000: self-check ([lines](runs/selfcheck-logical-lines-threshold-1000.txt)) | 7 of 7 lines the same |
| every 2,000 frames on blot2, `6ad5fbb` copy ([record](runs/blot2-logical-state.txt)) | 28 of 28 lines and 38 of 38 diagnostic lines the same |
| outputs against the previous compiler | 10,049 of 10,049 the same |
| bootstrap, conformance, 64-bit conformance, native checks, unit tests | fixed point; 10,689 of 10,793; 4,765 of 4,773; pass |

**One rule no test exercises.** A replay of a frame that is on the chain can add to the list it is going through, and the old single list then ended at the entry that was its last when the replay reached it. With reads and other entries in two lists, an entry of another kind added while its reads are still to come would be missed; the replay looks again after those reads. With that rule removed, the self-check and all 4,355 sources still give the same logical state. It stays, on the argument.

## Not kept

| tried | result |
| --- | --- |
| a construct read looks at a hold's kind before anything else (`valfast.py` step 9) | 6.08 s against 6.11 s: nothing, and step 3 passes those reads anyway |
| the set of reads offered to each chain, kept beside the 32-byte entries ([tools/compactreads-chainset.py](tools/compactreads-chainset.py), step 4 as first built) | 4.01 s against 3.89 s without it, and 40 MiB more |
| a row of bits per frame, one bit a leaf | not built. A frame holds one entry per node and type, whose value is the join of what it took; a set of leaves does not say which leaf that is. The order of a frame's list would also be lost, and it decides the order of two errors from one replay |

## Not done

- **Starting class-keyed frames earlier.** Seen again while forcing the conversion: with class-keyed frames from frame 64 instead of 4,096 the fingerprinting build checks the compiler in 3.1 s where it takes 7.3 s, with no errors; from frame 1,000, 6.1 s. That is a change of the analysis, not of its speed, and `CONTINUE.md` has held it back since 2026-11-15 because the class path misses errors the concrete one reports. Today's count at 64, which only reaches the sources that make more than 64 frames: two of the 4,355 change verdict ([record](runs/threshold-64-verdicts.json)). `stdlib_regex`, a recorded gap, is accepted; `render_walks_around_overloads` is rejected with "whole assignment replaces a variable-size value while its parts are being rendered". It needs a decision on which analysis small programs get.
- **The profile is flat now.** Its largest shares in a self-check: evaluating bodies 12%, replay 6%, scope lookups 5%, the reads' table 4%, the walk of an offer 4%, how far an offer goes 4%, growth offers 3%.
- **Table slots.** A frame's table doubles and leaves the old one behind: 5.4 million slots for 988,405 entries, 21.6 MB where 8 would do.
- **blot2**: `life_reads` is 58% of its check (above). It answers each new question, whether the code below a node reads a captured binding, by walking every node the calls from there reach. The bodies' own lists (`life_body`) could answer it from body to body.
- **No V8 run of the old sources** was made today; the "this morning" figures are the earlier page's.

## A correction to this morning's page

[The read-memos page](../lifetime-read-memos/README.md) said peak RSS was unchanged at 567 MiB. It had risen: 503 MiB at `ddbbe23`, 568 MiB at `9151d87`, for the check, and 643 to 714 MiB compiling to Wasm. The timing tool read `getrusage(RUSAGE_CHILDREN)`, whose peak is the largest of every child so far, so the second compiler never showed less than the first. The tools here read each child's own usage (`os.wait4`), and that page now says so.

## Tools

- `tools/valfast.py FILE` (steps 1 to 3; `FILE 1,2,3,9` adds the variant not kept) and `tools/compactreads.py FILE` (steps 4 to 6) make the delivered source from `9151d87`'s.
- `tools/logicalfp.py`, `tools/fplogical.sh`, `tools/prove-final.sh`, `tools/fpblot2-logical.sh`, `tools/fpcompare.py`: the logical-state comparisons. `tools/fppair.sh`: the index-based one for steps 1 to 3. `tools/diagcompare.py`: verdicts of two compilers over the corpus.
- `tools/native.py`, `tools/selfbench.py`, `tools/small.py`, `tools/hosted_pair.py`, `tools/v8.sh`, `tools/blot2time.py`: the timings. `tools/progress.py`, `tools/progblot2.sh`, `tools/profblot2.sh`: blot2 by the thousand frames and under the sampler.
- `tools/timers.patch`, `tools/valcount.py`, `tools/shrinkcount.py`, `tools/disccount.py`, `tools/compactcount.py`: the timers and counts.
- `tools/profile.sh`, `tools/hotlines.py`: the sampler run and the hottest instructions of a function.
