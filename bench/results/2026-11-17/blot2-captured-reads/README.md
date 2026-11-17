# blot2 checked in 2 minutes: a captured binding is looked for body by body, 2026-11-17

Since `ff912cd` the compiler checks blot2 (the 120,000-line, 450-module compiler of the earlier pages) in 122 to 124 s of CPU time instead of 298 to 308 s: 0.41 of it. The analysis is the same: the same lists in every frame every 2,000 frames, the same 38 diagnostic lines, the same state on the self-check and on 4,355 conformance sources, and all 10,049 outputs byte for byte the previous compiler's.

This follows [the 32-byte reads](../lifetime-compact-reads/README.md) of the same day, which found blot2's profile to be 58% one function.

## What was measured

- **Source and compilers:** "before" is `20fabe5` and "after" `ff912cd`, each the bootstrapped compiler of its qualification (executables `aa1547c396e4…` and `6fb88eeb7c50…`; [after](runs/qualification.json)).
- **Workload:** the blot2 copy at `6ad5fbb` (`build/blot2-head/compiler-goose/src`), `--reachable-program --expansion-node-limit 1000000 --check`, as on the earlier pages. It ends with 38 lifetime errors in its first discovery pass, also as before.
- **Machine:** 4 cores, 16 GiB, Linux, clang 18.1.3. CPU seconds and peak RSS of each run (`os.wait4`).

## Result

| | before | after | ratio |
| --- | ---: | ---: | ---: |
| blot2 check, CPU, two runs each in the order before, after, after, before ([blot2-time.txt](runs/blot2-time.txt)) | 308 s, 298 s | 124 s, 122 s | 0.41 |
| its peak RSS | 7,393 MiB | 7,394 MiB | |
| its diagnostics | 38 lines | the same 38 lines | |
| the compiler checking itself, median of five ([selfcheck.txt](runs/selfcheck.txt)) | 3.70 s | 3.59 s | 0.97 |

Small programs did not move: an empty `main` 2.42 against 2.35 ms, `squares` 3.01 against 3.06 ms, `tour` 5.50 against 5.52 ms, minimum of 60 ([small-programs.txt](runs/small-programs.txt)).

## What it was

`life_reads(node, symbol)` says whether the code below a node can read a binding: the lifetime pass asks it to decide which enclosing frame a nested function's call belongs to (a function may read a binding captured from any frame that encloses it), and whether a binding is used after a shrink. It walked every syntax node below the node and below every function a call there reaches, except the function that owns the binding, and kept the answer per (node, binding).

On blot2 it was asked 5,310 new questions, all about captured bindings, and answered yes to 114 ([counters-blot2.txt](runs/counters-blot2.txt), [tools/readscount.py](tools/readscount.py)). Each walk went over a good part of 5.3 million nodes: 34 ms a question, cache misses on the nodes nearly all of it, 58% of the whole check.

`life_body` already scanned, once per start node, what such a walk reaches without following calls: the globals named, the calls made, whether a captured binding is named, and the functions owning those. It was used for "does this body read any captured binding" and "does it read this global".

## What changed

All in `selfhost/checker_lifetimes.goose`; [tools/bodyreads.py](tools/bodyreads.py) makes it from `20fabe5`'s.

- A body also lists the captured bindings it names, sorted, each once (`LifeBody.named`, `body_captures`).
- `life_reads_captured` answers a question about a captured binding by going from body to body along the listed calls, skipping a call into the owner's body as the node walk did, and looking the binding up in each body's list. It reaches the same bodies the node walk reached nodes of, so it finds the binding exactly where that walk did. On blot2 the 5,310 answers went through 15 million bodies (27,827 different ones); the node walk went through billions of nodes.
- Other questions (about a global, or a local in the body) still walk the nodes: the self-check asks two, blot2 none of either kind.

## What was checked

| check | result |
| --- | --- |
| both answers computed side by side (`bodyreads.py FILE check`): every conformance source ([summary](runs/answers-corpus.json)) | 1,810 questions about a captured binding in 243 sources, none differing |
| the same on blot2 ([record](runs/answers-blot2.txt)) | 5,310 of 5,310 the same |
| logical state (each frame's lists by content, [tools/logicalfp.py](tools/logicalfp.py)) at every pass boundary of the self-check, and on every conformance source ([record](runs/logical-state.txt), [summary](runs/corpus-logical-state.json)) | 7 of 7 lines; 4,355 sources, 11,589 lines, none differing |
| logical state every 2,000 frames on blot2 ([lines](runs/blot2-logical-lines.txt)) | 28 of 28 lines and 38 of 38 diagnostic lines the same |
| outputs against the previous compiler | 10,049 of 10,049 the same |
| bootstrap, conformance, 64-bit conformance, native checks, unit tests | fixed point; 10,689 of 10,793; 4,765 of 4,773; pass |

## Where blot2's time is now

A sampling profile of the new build on blot2 ([blot2-profile-after.txt](runs/blot2-profile-after.txt), [tools/profblot2.sh](tools/profblot2.sh)), 31,372 samples where the old build took 75,702:

- `life_effect` called from `life_construct_read`: 24%. Past 4,096 frames a construct read is an ordinary entry merged by kind (the 32-byte entries stop at the first class-keyed frame), and an island's root takes the effects of its whole body. Holding reads by leaf there too is the next step.
- `life_contains` and `life_gs_contains_walk` (whether one type holds another): 15%.
- Building and mapping sets (`life_list_set`, `life_map_set`): 11%.
- Growth offers: 5%.

## Not done

- blot2's 38 errors are unchanged; this is speed only.
- Reads by leaf with class-keyed frames (above).

## Tools

- `tools/bodyreads.py FILE [check]`: the change; with `check`, a build that computes both answers and prints any difference.
- `tools/readscount.py`: the counts. `tools/blot2time.py`, `tools/selfbench.py`, `tools/small.py`: the timings. `tools/profblot2.sh`: the profile.
- `tools/logicalfp.py`, `tools/fplogical.sh`, `tools/fpblot2-logical.sh`, `tools/fpcompare.py`: the state comparisons (copies of the 32-byte reads page's).
