# The lifetime pass offers a read once, 2026-11-17

Since `9151d87` the compiler checks its own source in 0.59 of the CPU time it took and compiles itself in 0.65 to 0.68 of it. The analysis is the same: the same state at every pass boundary on the self-check and on 4,355 conformance sources, the same state every 2,000 frames on blot2, and all 10,049 outputs byte for byte the previous compiler's.

The time went where the [profile](#where-the-time-was) said it was: nine tenths of a self-check is the lifetime pass, and nearly half of that was one thing, re-offering array reads that every frame up the call chain already had.

## What was measured

- **Source and compilers:** "before" is `ddbbe23` and "after" `9151d87`, each the bootstrapped compiler of its qualification (executables `eadfec43889e…` and `135f9f8f33ce…`; [the after one](runs/qualification.json)). The step table uses development builds of the same sources (`tools/stepbench.sh`: the generated C as eight units, `clang -O2`).
- **Workload:** `selfhost/main.goose` at `9151d87` (30,915 lines with the standard library's share), as `--check`, to 32-bit Wasm (`-O2 --wasm-max-pages 65535`) and to C (`-O2`).
- **Machine:** 4 cores, 16 GiB, Linux, clang 18.1.3. Seven interleaved runs each, pinned to one core; CPU seconds (user + system), all in [native.json](runs/native.json) ([tools/native.py](tools/native.py)). The machine was about a third slower this day than on 2026-11-16, so times compare within this page only.

## Result

| the compiler, on its own source | before | after | ratio | same output |
| --- | ---: | ---: | ---: | --- |
| check | 11.15 s | 6.61 s | 0.59 | |
| to 32-bit Wasm | 14.83 s | 10.06 s | 0.68 | yes |
| to C | 14.24 s | 9.27 s | 0.65 | yes |

Medians of seven; the ranges are 10.7 to 13.1 s and 6.0 to 7.1 s for the check. Peak RSS is unchanged (567 MiB checking, 713 MiB compiling).

Small programs, as `--check`, minimum CPU time of 60 runs and page faults ([small-programs.txt](runs/small-programs.txt)):

| | before | after |
| --- | --- | --- |
| an empty `main` | 2.38 ms, 227 faults | 2.54 ms, 227 faults |
| `examples/squares.goose` | 2.75 ms, 266 faults | 2.56 ms, 265 faults |
| `examples/tour.goose` | 5.18 ms, 481 faults | 5.34 ms, 489 faults |

`tour` takes eight more pages, the new tables. The times are within what repeated runs of one binary differ by here; the 31-sample campaign of the earlier pages was not run.

**As a Wasm module** the compiler gains the same. Its sources before and after, each built as a 64-bit module and run under Wasmtime 50.0.1 through `host/rust`, three interleaved runs ([hosted-pair.json](runs/hosted-pair.json), [tools/hosted_pair.py](tools/hosted_pair.py)):

| the module, on the compiler's source | before | after | ratio |
| --- | ---: | ---: | ---: |
| check | 34.5 to 34.8 s | 20.6 to 21.3 s | 0.61 |
| to 32-bit Wasm | 41.0 to 42.8 s | 29.0 to 30.0 s | 0.70 |

Under V8 12.4 the new module checks itself in 24.7 to 25.5 s as a 64-bit module and 20.6 to 21.7 s as a 32-bit one, and compiles itself in 38.0 to 38.8 s and 34.8 to 36.3 s, every output the native compiler's ([hosted.json](runs/hosted.json), the script of the 2026-11-16 page). No V8 run of the old sources was made this day.

blot2's check takes the same six minutes (6 min 3 s and 6 min 6 s): past 4,096 frames calls are keyed by classes, and nothing here applies there.

## Where the time was

A sampling profile of the self-check (the `LD_PRELOAD` sampler of the 2026-11-15 page, [tools/profile.sh](tools/profile.sh)) put 45% of the whole run in two instructions: the two cache misses of one hash lookup, a summary merge.

The analysis keeps, for each call context (frame), a summary of the effects its callers must see. One kind of effect is the *construct read*: a read of an array element or of a value of variable size, recorded so that an assignment that reads its own target while building its replacement can be reported. Every indexing expression makes one. Counted with [tools/counters.py](tools/counters.py) ([before](runs/counters-before.txt), [after](runs/counters-after.txt)):

| in one self-check | before | after |
| --- | ---: | ---: |
| summary entries | 1,094,869 | the same |
| of them construct reads | 1,025,472 (94%) | the same |
| distinct reads among those (same node, same value) | | 23,610 |
| summary merges, five discovery passes | 16,708,941 | 2,732,775 |
| construct reads offered in discovery | 11,607,881 | 726,553 |
| new construct-read entries by pass | 626,682; 354,755; 5,957; 13; 0 | the same |
| live cells a shrink check asks | 10,126,753 | 778,504 |

A million entries name 23,610 reads because every frame above a read holds its own entry for it. When a frame is called a second time in a pass, its summary is replayed into the caller, entry by entry, and each entry is offered to every frame up the chain. 14.9 million of the 15.9 million merges that made found the entry already there. Passes 3, 4 and 5 add 5,957, 13 and no entries and did 3.6 million merges each.

## What changed

All in `selfhost/checker_lifetimes.goose`; [tools/lifememo.py](tools/lifememo.py) and [tools/holderrefs.py](tools/holderrefs.py) apply the steps one at a time to the `ddbbe23` source. CPU seconds for the check, median of seven, development builds ([steps.txt](runs/steps.txt)):

| step | check | of before |
| --- | ---: | ---: |
| before | 10.74 s | 1.00 |
| 1. A read is named by its node and value (a *leaf*) and offered once an activation | 9.68 s | 0.90 |
| 2. A replay passes a skipped entry without reading its 170-byte effect | 9.20 s | 0.86 |
| 3. A read a chain of frames was offered in an earlier pass is not offered to it again | 8.08 s | 0.75 |
| 4. A shrink check asks only the live cells whose type can hold a reference | 7.55 s | 0.70 |
| 5. A summary a chain of frames has replayed whole is replayed by its other entries | 6.73 s | 0.63 |
| 6. A holder type's reference types are listed once, not walked at every shrink check | 6.04 s | 0.58 |

The last row is from [a second run](runs/final-step.txt), in which before took 10.41 s and step 5 took 6.63 s.

What each relies on:

- **Once an activation (1).** In discovery a construct read does nothing but add itself to the summaries up the chain, and a summary keeps what it has. The existing memo knew this of one summary entry; a leaf says it of the read, whichever entry carries it. An offer from an activation nested in the current one also counts, as far up as it went: frames take an offer up to the outermost one that holds a place of it, and no further. The stamp on a leaf keeps that depth.
- **Across passes (3, 5).** The same frames in the same order are the same chain in every pass. A read offered to a chain went as far up it then as it would now. Frames may have become recursive since; that matters only to an offer with a place in such a frame, which is asked of the offer as it is now.
- **Shrinks (4, 6).** A cell whose type neither is nor holds a reference points into nothing. The reference types inside a type are a property of the type, unless one of the root's fields has been killed, when the walk is done as before.
- **Class-keyed frames.** An island's root frame takes its body's effects for every caller, so with them only the same activation counts and no chain is kept. That is blot2's whole run after its first 4,096 frames.

## What was checked

| check | result |
| --- | --- |
| analysis state at every pass boundary, self-check ([lines](runs/selfcheck-state-lines.txt)) | 7 of 7 lines the same |
| the same on every conformance source ([summary](runs/corpus-state.json)) | 4,355 sources, 11,589 lines, none differing |
| state every 2,000 frames on blot2, `6ad5fbb` copy ([record](runs/blot2-state.txt)) | 28 of 28 lines the same, and the same output |
| outputs against the previous compiler | 10,049 of 10,049 the same |
| bootstrap, conformance, 64-bit conformance, native checks, unit tests | fixed point; 10,689 of 10,793; 4,765 of 4,773; pass |

The state fingerprint is the one of `bench/results/2026-11-14/blot2-lifetimes/tools/instrument.py`: every set reachable from roots, cells, frames, effects and items by content, with the effect lists' order and the revision and activation counters.

**One guard no test exercises.** The first version of step 1 counted an offer from any nested activation. That is wrong when a place of the read is in a frame between the two: the offer stops there. Reasoning found it, not a test: with the depth check disabled the self-check and all 4,355 sources still give the same state. It can only matter where a reference to a callee's local reaches the caller, which the checker then rejects. The check stays.

## Not kept

| tried | result |
| --- | --- |
| step 1 with stamps restored from an undo log when an activation ends, instead of the nested rule | 0.89 against 0.86: fewer hits and more code |
| the leaf memo for the recording half of a construct read in validation | 6.76 s against 6.73 s: nothing |
| the same memo for growths and replacements, which discovery also only records | 0.687 against 0.691: nothing |
| within one shrink check, cells with equal type, place, references and contents asked once | 7.38 s against 7.40 s: nothing |
| a summary-level memo by nested activation, beside the one by chain | nothing |
| per-field lists of reference types for a root with killed fields (`tools/holderfields.py`) | natively 0.605 against 0.605; as a module under Wasmtime the check took 19.4 to 20.3 s against 19.9 to 20.6 s ([runs](runs/hosted-holder-fields.json)): nothing |

## Not done

After these the lifetime pass is still most of a self-check. Where its time is now, from the pass timers of a development build: about 1.1 s and 1.8 s in discovery passes 1 and 2, 0.4 to 0.7 s in each of passes 3 to 5, 2.7 to 3.0 s in validation.

- **Passes 1 and 2 are real work**: 981,437 construct-read entries made, each a hash insert. The entries are 94% construct reads of 23,610 distinct reads. Holding a frame's reads as a set of leaves instead of an entry each would remove most of it, and would change the state the fingerprint compares, so it needs another proof.
- **Validation**: 2.4 million construct reads are recorded there and checked against the holds in force; the shrink checks still make 389,733 holder walks over 6.8 million alternatives.
- **blot2** is untouched, and is where the larger times are.
- **The module's profile under V8 names `life_holder_scan`** for 11% of a self-check (the walk step 6 left for roots with a killed field; 4% natively). Removing that walk changed nothing measurable under Wasmtime (Not kept), so the V8 figure was not followed further.

## Tools

- `tools/lifememo.py FILE 5` and then `tools/holderrefs.py FILE` make the delivered source from `ddbbe23`'s. The script's steps 6 and 7 are two of the variants not kept (validation; growths and replacements).
- `tools/stepbench.sh`, `tools/selfbench.py`, `tools/native.py`: the timings.
- `tools/counters.py`, `tools/counters-after.py`: the counts.
- `tools/profile.sh`, `tools/hotlines.py`: the sampler run and the hottest instructions of a function.
- `tools/fpself.sh`, `tools/fpblot2.sh`: the state comparisons on the self-check and on blot2.
