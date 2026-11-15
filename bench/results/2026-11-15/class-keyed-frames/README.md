# Frames keyed by argument classes, 2026-11-15

The lifetime pass made a frame for every set of argument roots a function was called with. On blot2's compiler that never finished: the first discovery pass filled the alternatives' region at 93,000 frames with a tenth of the program entered ([earlier evidence](../lifetime-walks-and-memos/README.md)). The owner's order of the same day was to match upstream Goose in functionality and get to where blot2 compiles; upstream checks a function once per *class* of arguments. This is the record of doing that here.

## What was measured

- **Sources.** `selfhost/checker_lifetimes.goose` at three commits on main: `bc00c87`, `0f9ec7f` and `e13cd80`. The numbers below are for `e13cd80` unless a row says otherwise.
- **Compilers.** Experiment builds, not bootstrapped ones: the C that the development build of `86f7a18` emits for the sources, compiled as eight units with Clang 18.1.3 at `-O2` and no profile ([tools/mk.sh](tools/mk.sh)). "Progress build" means the same with [tools/progress.py](tools/progress.py) applied, which prints table sizes every 1,000 frames and adds nothing to the analysis.
- **blot2.** `compiler-goose/src` of `mewhhaha/blot2` at `6ad5fbb` (one file fewer than the `93c8fa8` copy of the earlier runs), checked with `goose main.goose --stdlib <this repo>/stdlib --reachable-program --expansion-node-limit 1000000 --check`.
- **The conformance corpus.** The 4,355 distinct sources of `tests/conformance/cases.json`, each run with `--target native --check` ([tools/fpcompare.py](tools/fpcompare.py)).
- **The self-check.** The compiler checking `selfhost/main.goose`.
- **Machine.** A cloud container: 4 cores, one 16 GiB memory limit, no swap, Linux 6.18.
- **Upstream reference, collected separately on the same machine.** `aardappel/goose` at `d92c4315`, built with CMake, run as `goose check main.goose --stdlib <its stdlib>`.

## Results

| | before (`fe05443`) | `e13cd80` |
| --- | --- | --- |
| blot2, first discovery pass | stops at 93,000 frames after 102 s: region full | ends after 50,725 frames, 247 s (progress build) |
| blot2, functions' frames keyed by classes | none | 45,280 of the 50,725 |
| blot2, alternatives at that point | 77.9 M of 79.5 M that fit | 57.8 M |
| blot2, what the pass reports | nothing: it never ended | 2,348 errors ([list](runs/blot2-diagnostics.txt)) |
| corpus, default build | | 0 of 4,355 sources differ in output, diagnostics or 11,589 state fingerprints |
| self-check, default build | 7.0 s | 7.0 s, the same state fingerprints |

- **The first pass ends, and the check does not.** The pass reports its errors after a whole discovery pass and stops there. 2,345 of the 2,348 are "stored reference does not outlive the storage that receives it", reported at a call whose callee stores something into storage the call's own arguments do not outlive; 3 are "returned reference points into this invocation's local or temporary storage". blot2's own patched upstream build (patches 01–29) checked this program without errors on 2026-11-14, so most of these are this analysis being less exact than that one, not blot2's code. They are not yet told apart one by one. See "What is not right yet".
- **Plain upstream does not get that far.** `d92c4315` on the same copy was stopped at 1,500 s with nothing printed ([run](runs/upstream-d92c431-blot2.json)), as blot2's own notes say of 25 minutes.
- **Small programs are not touched.** A call is keyed by classes only once the program has made 4,096 frames. The corpus's largest program makes 720 and its busiest function 63 ([per source](runs/corpus-frames.json)); the self-check makes 2,436. Below the limit every changed line is behind a test of "are class-keyed frames in use", and the state fingerprints say so.

### With every eligible call keyed by classes

Built with the limit at 0 ([tools/mkcls.sh](tools/mkcls.sh)), to see how far the new path is from the old one where both finish:

- **Corpus.** 150 of 4,355 sources differ ([sources](runs/corpus-every-call-class-keyed.json), [diagnostics both ways](runs/corpus-every-call-class-keyed-categories.json)):
  - 72 report the same messages at other places (a store is reported at the call that lands it, not inside the callee);
  - 22 report other messages;
  - 23 are accepted by the default path and rejected by this one, mostly "array shrink invalidates a reference or holder that is used afterward";
  - 33 are rejected by the default path and accepted by this one, 22 of them that same shrink error. These are errors this path misses.
- **Self-check.** 1.5 s instead of 7.0 s, with 58 errors where there are none: 47 "array shrink invalidates a reference or holder that is used afterward" and 11 "… a value still needed by the enclosing expression". Plain upstream rejects this compiler's source as well, at its first such place (`selfhost/checker.goose:1195`, "cannot call check_type, which may shrink p"), so the default path is more exact here than upstream is.

## How it works

In `selfhost/checker_lifetimes.goose`, from "Class-keyed frames" on. In short:

- **Key.** Each reference or holder argument of one exactly named root is a class; two arguments share one only when they name the same root. Any other argument is one class as a whole. The key is each parameter's class and flags and the classes' order by depth (ranks, with 0 kept for depth 0, so "is a global" is always in the key). What the storage holds is not in the key.
- **Body.** The frame's body sees a class root per class: storage of no frame. What a class root's storage holds is a storage class: one for all of it (a holder copied out), and one per pointee type read out of it, made when first read and chained four reads deep. Past that it is "something read out of this".
- **Island.** The body is evaluated on its own: effects stop at its frame, and it sees no cell, hold or pending read of its callers. Frames of functions that cannot be keyed (nested functions, closures) are kept per island.
- **Call.** Each call replays the frame's effects and takes its result with class roots mapped to its own roots: an argument class is the argument; a storage class is what the argument's storage holds, picked by pointee as a read-back picks; anything deeper is whatever that storage leads to. A store that lands in the call's roots is checked against their depths there, reported at that call and then dropped.
- **Recursion.** A call to a function whose frame is open comes back to that frame whatever it passes, as upstream's back edges do. Where its key is another, the frame's classes are read by parameter position.
- **Questions.** What the body needs beyond the key (may this class point into grow-shrink elements, are these two argument classes the same storage) is asked of the call being evaluated and kept with the frame. A call that answers otherwise makes the answer the cautious one for good, and the body is checked again.
- **Global storage.** More than four global roots in one set are one alternative, "something in global storage" (upstream's globals bound). What an island stores of its class roots in a global stays with the island and is added to its own reads of globals.
- **Summaries.** A discovery summary is kept only where it is read: by an island's root frame and by a recursive frame. Its shrink, growth, read and replacement entries are merged by kind and type, as a validation pass already compares them.
- **Which functions.** A top-level function whose captured bindings, through every call, belong to functions its own body reaches.

## What is not right yet

- **Precision.** The 2,345 store errors on blot2. Known causes, largest first as far as they were looked at:
  - Everything a body stores through any class root is read back through every other class root of that frame (one set per frame). A reference to one parameter's storage put into a second parameter's struct then shows up in what a third parameter's storage "holds", and a callee that copies from the third into a global is refused.
  - Any two storage classes are taken to alias, and a storage class to alias every global.
  - A holder copied out of an argument's storage carries everything that storage holds, as the default path's per-root contents do.
- **Missed errors.** The 33 corpus sources above. A shrink inside a callee is checked against the callee's own values and, replayed, against the caller's; with classes the callee no longer sees which of its values the argument really names.
- **A store through storage that is only known to outlive a class root** lands in the roots the call names, not in whatever else that storage may be.
- **Validation was never reached on blot2**, so its cost and its effect lists (which are not merged by kind) are unmeasured.
- **Memory.** 57.8 M alternatives at the end of pass 1 of blot2, of 79.5 M that fit, with later passes still to come.

## Tried and not kept

Each was built and run; the numbers are from those runs.

- **A view per exactly named caller local, a class per root it holds, followed through everything those hold.** Exact, and each key carried the caller's whole reachable structure: 5,800 numbers per key and 1.15 M recorded questions after 1,000 frames of the self-check, the region full by 2,000.
- **The same, one level deep.** Keys then depended on what storage held at the moment of the call, which grows all through discovery: 74,000 class frames for the self-check's 1,409 functions before it was stopped.
- **Letting class roots sit in a global's contents while the island runs and stripping them at its end.** Nested islands read the pending ones, which made questions circular (a native stack overflow before queries were made cycle-safe) and rebuilt each global's contents at every exit. Replaced by the per-island set.
- **A class per alternative of a multi-alternative argument.** About 40 classes and 54 recorded questions per frame on blot2; the region full at 15,000 frames.
- **Folding global roots only above 32.** Sets of a dozen to thirty globals in every combination: 2 M mapped sets in 5,000 class frames. The limit is 4.
- **Reading a deep read back as a bound ("something that outlives X").** Every later read through it enumerates candidates: sets averaged 145 alternatives. Deep reads now map to what the storage leads to, sixteen storages wide at most.
- **Keeping lifetime bounds on alternatives in class mode.** The same roots under each caller's depth were 26 M of 79 M alternatives. Class ranks hold a read through a parameter instead.

## Tools

In [tools/](tools/): `mk.sh` builds an experiment compiler from a source directory; `mkcls.sh` the variant with every eligible call class-keyed; `progress.py`, `setsites.py`, `bigsets.py`, `effkinds.py` report table sizes, which function made the new sets, what large sets consist of and summary effects by kind; `dbgforeign2.py`, `dbgstore.py`, `dbgcycle.py`, `dbgshrink.py` trace a root of another island, a refused store, a circular question and a shrink conflict; `framestat.py` and `statcorpus.py` count frames per program; `fpcompare.py` and `diffcat.py` compare two compilers over the corpus and group the differences; `instrument.py` adds the state fingerprints.
