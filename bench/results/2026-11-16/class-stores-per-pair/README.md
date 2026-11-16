# Class-keyed frames: stores per pair of classes, 2026-11-16

The [class-keyed path of 2026-11-15](../../2026-11-15/class-keyed-frames/README.md) got the first discovery pass of blot2's compiler to end, with 2,348 errors that are mostly not blot2's. Its page named the largest known cause: everything a body stores through any class root was read back through every class root of the frame. This is the record of replacing that, of what it cost in memory, and of what the remaining errors turned out to be.

The short version: the class path is now exact enough that the compiler checks itself without a false error when every call is keyed by classes, and it rejects 14 corpus sources it should accept instead of 23. On blot2 it removed 167 of the 2,348 errors. The rest are not what the earlier page thought, and their count is not a measure of progress (see "What the remaining errors are").

## What was measured

- **Source.** `selfhost/checker_lifetimes.goose` at `f4d1d02` on main, against `e13cd80`.
- **Compilers.**
  - The bootstrapped compiler that `scripts/qualify.py` built from `f4d1d02` ([qualification](runs/qualification.json): fixed point, emitted C `e28eaa69…`, executable `1ba787be…`, no profile). The blot2 time, memory and diagnostics below are from it.
  - Experiment builds for everything else: the C that the development build of `86f7a18` emits for a source directory, compiled as eight units with Clang 18.1.3 at `-O2` ([tools/mk.sh](tools/mk.sh)). "Progress build" adds [tools/progress.py](tools/progress.py), which prints table sizes and changes nothing; "every call class-keyed" sets the 4,096-frame limit to 0 ([tools/mkcls.sh](tools/mkcls.sh)).
- **blot2.** `compiler-goose/src` of `mewhhaha/blot2` at `6ad5fbb`, checked with `goose main.goose --stdlib <this repo>/stdlib --reachable-program --expansion-node-limit 1000000 --check`.
- **The conformance corpus.** The 4,355 distinct sources of `tests/conformance/cases.json`, each run with `--target native --check` ([tools/corpus0.sh](tools/corpus0.sh)).
- **The self-check.** The compiler checking `selfhost/main.goose`.
- **Machine.** A cloud container: 4 cores, one 16 GiB memory limit, no swap, Linux 6.18. It ran about a tenth slower than on 2026-11-15: yesterday's compiler takes 7.7–8.1 s on the self-check today, 7.0 s then. Times on this page are today's.
- **Upstream.** Not rerun. The 2026-11-15 reference stands: plain `d92c4315` stopped at 1,500 s with nothing printed.

## Results

| | `e13cd80` | `f4d1d02` |
| --- | --- | --- |
| corpus, default build | | 0 of 4,355 sources differ in output, diagnostics or 11,589 state fingerprints ([report](runs/corpus-default-fingerprints.json)) |
| self-check, default build | 7.7–8.1 s | 7.5–8.1 s, the same state fingerprints |
| self-check, every call class-keyed | 58 false errors | no error, 2.3–2.4 s |
| corpus, every call class-keyed: accepted sources rejected | 23 | 14 |
| corpus, every call class-keyed: rejected sources accepted | 33 | 33 |
| corpus, every call class-keyed: other messages / same messages elsewhere | 22 / 72 | 21 / 71 ([all 139](runs/corpus-every-call-class-keyed-categories.json)) |
| blot2, first discovery pass | ends after 50,725 frames | ends after 51,757 frames |
| blot2, errors it reports | 2,348 | 2,181 ([list](runs/blot2-diagnostics.txt)) |
| blot2, sets / alternatives at that point | 7.1 M / 57.8 M | 5.3 M / 66.4 M of 79.5 M that fit ([progress](runs/blot2-progress.txt)) |
| blot2, time to that point | 247 s yesterday (progress build) | 267 s (progress build); 278 s wall, 269 s CPU, 7.2 GiB peak RSS with the bootstrapped compiler ([run](runs/blot2-run.json)) |

- **Small programs are not touched.** Every changed line is behind "are class-keyed frames in use", and the fingerprints say so again.
- **The class path is now right about the compiler itself.** With every eligible call keyed by classes the self-check reported 58 shrink errors that are not there; it reports none, in a third of the default path's time. It still misses the same 33 errors in the corpus, so the limit stays where it is.
- **blot2 is not checked yet.** The pass ends with 2,181 errors and stops there, as before. 2,179 are "stored reference does not outlive the storage that receives it".
- **It is not faster on blot2, and holds more.** Keeping stores per class root and narrowing reads to typed classes makes more distinct sets of more alternatives; not interning the prefixes of a set under construction took most of that back in sets (7.1 M to 5.3 M) and not in alternatives (57.8 M to 66.4 M).

## What changed

All in the class-keyed part of `selfhost/checker_lifetimes.goose`.

- **Stores are kept with the class root they went through** (`LifeRoot.stored`), and a read through another class root adds them only where the call being evaluated says the two classes may be the same storage (`life_class_stores`; question 4, now answered from the call's own sets for storage classes too). Before, one set per frame held everything stored through any of them.
- **A read of what a class's storage holds, as one pointee type, is that pointee's storage class in three more places** (`life_class_narrow`: a holder copied out, the answer to an alias question, a typed read at a call).
- **A set built one alternative at a time no longer interns each prefix.** Below 16 alternatives a build joined as it went, so a set of k alternatives left k−1 sets behind that nothing reads. A sample of one in 2,503 new sets on blot2 past its first 5,000 frames, with the call stack of each, put 83% of them there ([stacks](runs/set-creation-stacks.txt), [tools/gdbstacks.py](tools/gdbstacks.py)). With class-keyed frames in use the build is opened at its second alternative. The default path keeps the old behaviour, to keep its state the same.
- **A frame makes at most 256 storage classes of one pointee type, and at most 8 once the program holds 4 M alternatives.** Without a limit a handful of blot2's functions made hundreds each, their sets were 400–600 alternatives long, and 50 M alternatives appeared within 150 frames. The self-check with every call class-keyed makes 173,000 alternatives in all, so only a program far past the 4,096-frame limit meets the smaller number.
- **A replayed store through "whatever this argument's storage holds" does not land in a root whose type holds no reference** (`life_can_take`). blot2's pooled buffers keep a slice of a global `u32[>..]` pool in a struct; a callee's store into what that struct's storage holds was landing in the pool.
- **At most 512 questions are recorded per class frame**, and past 24 class roots stored through, every one is taken to be any other. Both are cautious answers past a size.

## What the remaining errors are

A build that prints each refused store ([tools/dbgstore2.py](tools/dbgstore2.py)) was run on a variant of this source (the per-type filter of "Tried and not kept", 1,664 errors). All but 6 of its 1,708 refusals were first reported where a call replays a callee's store, and of a one-in-eight sample ([table](runs/store-error-sample.txt)):

- **81% store one of the calling function's own argument classes, exactly, into "something in global storage"**, the single alternative that more than four global roots are folded into;
- 6% store it into another of the function's argument classes, one that holds only globals.

What that means, traced on one case (`check/dictionary_contracts.goose:36`): a function builds a local view struct of references into its own parameter and passes it on. Some callee, levels down, stores what the view's storage holds into storage the view also holds. With classes, "what the view's storage holds" is one storage class (or one per pointee type), and at this call it stands for the parameter itself as well as for the pool slices the view really copies from; "storage the view holds" stands for every global pool the view has a slice of. The store of the one into the other is refused. In the default path the place and the value are concrete roots and the store is between two pools.

Two things follow.

1. **The count moves with how coarse the classes are, not with how right the analysis is.** A source that is a storage class or only "reached from" a class is not judged at this call but where the caller's own calls land it. Finer classes turn more sources into exact argument classes, which are judged at once: with 256 typed classes a frame and a fold (below) the count went *up*, to 3,069. So 2,181 against 2,348 is not much evidence either way. The corpus and the self-check with every call class-keyed are the measure that means something, and they improved.
2. **The fix is in what a place stands for, not in aliasing.** Telling classes apart by pair, which this batch did, was the earlier page's first cause and is not the main one. The store needs its place and its value narrowed together: by the type stored (which worked but cost too much as built, below), or by keeping a view struct's fields apart as upstream's view classes do for a reference to a holder.

## Tried and not kept

Each was built and run on blot2; "ends" means the first discovery pass ended.

| variant | result |
| --- | --- |
| stores per pair, no limit on typed classes | region full just past 6,300 frames: 6.8 M alternatives became 58 M within 50 frames |
| at most 32 typed classes a frame | region full at 19,000 frames |
| the same, without interning prefixes | region full at 26,000 frames |
| at most 8 typed classes a frame, without interning prefixes | ends: 1,904 errors, 66.2 M alternatives, 274 s. Self-check with every call class-keyed: 58 false errors again |
| + each store effect carries the type stored, summaries are kept per type, and a mapped place takes the store only where that type can be (upstream's `StoreEvent.reached`) | 1,664 errors, but 120.9 M alternatives: it does not fit the 2 GiB region (full at 41,000 frames) and was run with 8 GiB regions, `-DGS_STACK_RESERVE=8589934592ull`. Per-type summaries are per-type sets and per-type mappings |
| 256 typed classes a frame, and a set with more than 6 of them names the untyped class that covers them instead | 2,329 errors and 86 M alternatives when the fold widened deep reads to "anything reached"; 3,069 errors and 120.8 M when it kept the read depth. And it loses an error: the shrink check does not treat the untyped class as covering a typed one (`test/errors_tc/emptied_callee_shrink_first.goose` accepted). The source of this variant is kept as [runs/checker_lifetimes.fold-and-typed-filter.goose.txt](runs/checker_lifetimes.fold-and-typed-filter.goose.txt) |
| at most 8 typed classes, place filter by "holds no reference" only | ends: 1,890 errors, 61.8 M alternatives, 269 s; the same 58 false errors on the self-check with every call class-keyed. Kept, with the limit made 256 below 4 M alternatives |

| *(after `f4d1d02`)* no candidates for a read out of a class root | 1,566 errors. But `test/errors_tc/store_reached_table.goose` and `construct_use_bound_holder_ref.goose` are then accepted: both are upstream's tests of exactly this rule, for a destination and for a use while constructing |
| the same, with the argument-class type filter | 1,741 errors: the count moves by a few hundred with any change to what the limits cut off |
| candidates kept in the body and stripped from what a store stores, directly and where a call maps an argument | no change on blot2 (107 sets in 38,000 class frames had a recognizable candidate: a projection clears the mark), and `test/errors_tc/shrink_class_copy_kept_own.goose` is accepted, because the body's own shrink check needs the reference |
| no smaller limit on typed classes under pressure, 8 GiB regions | stopped at 12.8 GiB resident, 19,000 frames in: 234 M alternatives, 48 to a set. A root per pointee type cannot be how this program gets its types |

The last row against the committed one is the trade made: 291 fewer blot2 errors for 58 false errors on a program the class path can otherwise check exactly. Given point 1 above, exactness on programs where the answer is known won.

## Later the same day: filtering by type where a call maps (`3ddf811`)

Two more changes, qualified and pushed as `3ddf811` ([qualification](runs/qualification-3ddf811.json)), and what was learned getting to them.

| | `f4d1d02` | `3ddf811` |
| --- | --- | --- |
| corpus, default build | | 0 of 4,355 sources differ |
| corpus and self-check, every call class-keyed | 14 / 33 / 21 / 71, no error | the same |
| blot2, errors of the first pass | 2,181 | 1,992 ([list](runs/blot2-diagnostics-3ddf811.txt)) |
| blot2, frames / alternatives | 51,757 / 66.4 M | 54,307 / 68.3 M |
| blot2, bootstrapped compiler | 278 s, 7.2 GiB | 283 s, 7.4 GiB ([run](runs/blot2-run-3ddf811.json)) |

- **An argument class knows the type its parameters point at** (`LifeRoot.class_pointee`), and a read of one pointee type out of storage does not take an exact reference to an argument class whose type holds no such value. Upstream's `CanContain` decides the same for a binding root.
- **A reference read out of a class's storage carries the pointee it was read as, and a call maps it only onto what can hold one** (`life_map_onto`): the held reference's own pointee, the root's type or the argument class's parameter type must hold the value inline. This is the typed storage classes' filter without a root per type, so it also works where a frame is past its limit of typed classes.

### What upstream does, read from its source

`aardappel/goose` at `d92c4315`: `FitsAt` (`typecheck_exprs.h` 1086), `ShrinkTargets` (`typecheck_builtins.h` 2898), `RootCandidates` (`typecheck_types.h` 1349).

- A store through a reference that was read out of storage (an inexact root) may land in the root, **in every global that can hold the type the destination reached, and in every parameter's storage that can**, and the value must outlive each. So upstream does name other parameters and globals for a read-out reference, but as *destinations and aliases*, filtered by the reached type.
- The *value* of a read-out reference is rooted at its container's class, inexactly; no candidate is put into it. A store event carries the pointee and the reached type, and a call re-derives the rest from its own arguments.
- A store of something read out of a container back into that container is a permutation and records nothing.

Here a read-out reference's value carries the candidates themselves, as exact references to the other argument classes (`life_class_candidates`, the default path's rule). That is what the body's alias and shrink rules use, and two of upstream's own tests need it (below). It is also what makes most of blot2's errors: see next.

### Where the refused stores come from

Each store effect was tagged with the statement whose evaluation first made it, through every replay ([tools/dbgorigin.py](tools/dbgorigin.py)):

- **The 2,036 refused stores of that run go back to 43 statements, and five of them to 90%** ([table](runs/store-origins-3ddf811.txt)): the two assignments of `support/pooled_buffer.goose` that keep a buffer's slices (`buffer.storage = replacement`, `buffer.items = buffer.storage[..length]`), `self_.items = default<Entry[:]>()` in `reuse/epoch_resolution_cache.goose`, and the results of `none<T>()` and `someValue<T>()` in `support/option.goose`. A summary entry keeps the first statement that stored into its place, so these are the first stores into the places concerned, not necessarily the ones that carry the refused value.
- **By kind** ([table](runs/store-kinds-3ddf811.txt)): 1,436 store an argument class of the calling function, exactly, into "something in global storage"; 207 into another argument class that holds only globals.
- **Seen from the callee** (a run with [tools/dbgvia.py](tools/dbgvia.py), which maps each of the callee's alternatives alone; it disturbs the analysis, 1,911 refusals instead of 1,613 on the variant it was run on): the place is a storage class in 1,701 of 1,911 (untyped in 1,103), and the alternative that becomes the refused source is the callee's own argument class in 591, which is a reference the caller passed that carried a candidate with it.

So the pattern is: a function reads a reference out of its parameter and passes it on; the argument is the storage class *and* an exact candidate; a class of two alternatives is one class in the callee; everything the callee stores of that parameter maps back to both, and the candidate is the caller's own parameter, exactly. The pooled-buffer stores are simply the most common stores there are.

## That evening: candidates asked for, not carried (`d26f33c`)

The pattern above, fixed the way upstream has it ([qualification](runs/qualification-d26f33c.json)).

| | `3ddf811` | `d26f33c` |
| --- | --- | --- |
| corpus, default build | | 0 of 4,355 sources differ ([report](runs/corpus-default-fingerprints-d26f33c.json)) |
| corpus, every call class-keyed | 14 / 33 / 21 / 71 | 14 / 33 / 21 / 72 ([all 140](runs/corpus-every-call-class-keyed-categories-d26f33c.json)): one more source reports its same message at another place |
| self-check, every call class-keyed | no error | no error |
| blot2, errors of the first pass | 1,992 | 1,681 ([list](runs/blot2-diagnostics-d26f33c.txt)) |
| blot2, frames / alternatives | 54,307 / 68.3 M | 54,054 / 65.4 M |
| blot2, bootstrapped compiler | 283 s, 7.4 GiB | 269 s, 7.3 GiB ([run](runs/blot2-run-d26f33c.json)) |

- **Out of a class root, a read's candidates are noted on the storage class the value is** (`LifeRoot.class_mask`, a bit per argument class of the frame) and are no part of the value.
- **The alias rules answer from the mask** (`life_class_alias`): a reference read out as that storage class may be to those argument classes.
- **A store or a shrink through the reference adds them to where it may land** (`life_place_candidates`), so the body's checks and the effects it records for its callers see the destinations they saw.
- **A call the reference is passed to, a store of it and a result see only what the storage holds**, which each call maps to what its argument's storage really holds.

Upstream's three tests that pin the rule, `test/errors_tc/store_reached_table.goose`, `construct_use_bound_holder_ref.goose` and `shrink_class_copy_kept_own.goose`, report their errors as before.

What remains ([by first statement](runs/store-origins-d26f33c.txt), [by kind](runs/store-kinds-d26f33c.txt)): 1,351 of 1,725 refused stores still store an argument class of the calling function, exactly, into "something in global storage". These are no longer candidates. They are the case traced at the top of this page: a view struct that really holds a reference to the caller's parameter, and a callee's store of "what the view's storage holds" into "what the view's storage holds", which a call maps to every pair of the two. The reached-type filter on the place (in "Tried and not kept", too costly as built) is what tells those pairs apart.

## Not right yet

- **blot2's 1,681 errors** (`d26f33c`), as described above. The next step is the type a store reaches: a mapped store through "what this argument's storage holds" should land only where the reached type can be, with one summary per place and a small set of reached types on it rather than a summary per type.
- **The 33 corpus sources where the class path misses an error**, unchanged.
- **Memory.** 65.4 M alternatives of 79.5 M after one pass; later passes and validation have not run. The 2 GiB is `GS_STACK_RESERVE`, the address space the runtime reserves per region, and a C compiler flag raises it (the 8 GiB runs above). Upstream's compiler has `--stack-reserve` for this, and since `707c546` so has this one ([qualification](runs/qualification-707c546.json): the generated C is unchanged without the option; a program that resizes one array to 300 M `i64` overflows as built before and runs with `--stack-reserve 8G`). The compiler's own bootstrap still uses the default.
- **Peak RSS is 7.3 GiB** for the one pass.

## Tools

In [tools/](tools/), beside those of the earlier page: `corpus0.sh` builds a source directory with the state fingerprints at the default limit and at 0 and compares both with a baseline over the corpus; `catsum.py` counts the differing diagnostics; `variant.sh` builds the every-call-class-keyed compiler with one edit applied, for bisecting; `gdbhook.py`, `gdbcmds.txt` and `gdbstacks.py` sample the call stack of one in 2,503 new sets under gdb and aggregate them; `dbgstore2.py` describes refused stores and `dbgpool.py` what first stores a reference into one named global; `setsites.py` and `bigsets.py` are updated for the current source; `dbgorigin.py` tags each store with the statement that first made it and `origins.py` counts refused stores by it; `dbgvia.py` and `viacats.py` say which of the callee's alternatives became the refused source and the destination; `storecats.py` counts refused stores by kind.
