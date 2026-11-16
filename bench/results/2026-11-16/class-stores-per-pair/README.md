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

| *(after `d26f33c`)* each store effect carries the type stored and a summary keeps the set of them for its place, 8 at most | 1,680 errors (1,681), 65.3 M alternatives: no change. The source of this variant is not kept in the repository; it is described under "After `d26f33c`" |

| the design of "After `d26f33c`": reached type per store, summaries per place and type, the place filtered by it from what the argument's roots hold | 1,863 errors in 8 GiB regions, 155 M alternatives, 690 s. Its steps are in the table under "That design, built" |

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

### After `d26f33c`: what a store's destination should be

Two more runs on `d26f33c`, and one more reading of upstream, say where the remaining errors are decided.

- **Seen from the callee** ([table](runs/store-via-d26f33c.txt), [tools/dbgvia.py](tools/dbgvia.py); the instrument does not disturb this version, 1,720 refusals with and without it): the destination is a storage class in 1,509 of 1,720 refused stores, the untyped one in 1,059. The alternative that becomes the refused source is a storage class whose **target type is not known** in nearly every case: a struct copied out of a parameter's storage carries everything that storage holds, untyped, so the filter by target type has nothing to go by.
- **One set of reached types per place changes nothing**: 1,680 errors instead of 1,681, with the same alternatives. Each store effect carried the type stored, a summary kept the union for its place (8 types at most, else "any"), and a mapped place took the store only in roots that can hold one of them. The untyped storage class is the place of stores of every type, so its set is "any" at once. What helped in the per-type variant of "Tried and not kept" was that each type kept its own stored values, not the filter alone.
- **Upstream does not land a store in everything the argument's storage holds.** `ApplyCalleeStores` (`typecheck_builtins.h`, from 1788) takes, for a store through a reference read out of a parameter, `ShrinkTargets` of the argument's roots: **the argument's own root, as a bound**, and the candidates for the *reached* type, which is the type of the storage the slot lies in as the destination reached it (the pointee of the last reference crossed). And it checks depths at the call only for such a widened destination; for an exact one the body's check stands, because the key holds the classes' order by depth.

Here a storage class as a place maps to every root the argument's storage holds a reference to: for a struct of pooled tables, every global pool it has a slice of. A value that is not global is then refused against each of them. The design that follows from upstream:

1. A store effect into a class root carries the reached type, read off the destination expression (the element type of the innermost reference or slice the lvalue goes through; none where it goes through none). Summaries are kept per place and reached type, which is few types per place: every store into any field of a `Store` reached through a reference has reached type `Store`.
2. Where a call maps a storage class that is a store's place, the store lands in the argument's roots (as a place that only bounds, so reads through the argument see it) and in the roots the argument's storage holds *that can hold the reached type inline*, instead of in all of them. A pool of numbers or of other structs cannot hold a `Store`.

### That design, built: it does not remove the errors

It was built the same night, on `d26f33c`, and is not kept ([the patch](runs/reached-type-variant.patch), [run](runs/blot2-reached-type-variant-run.json), [progress](runs/blot2-reached-type-variant-progress.txt)). In the order it was put together, each step run on blot2:

| step | errors | alternatives |
| --- | --- | --- |
| `d26f33c` | 1,681 | 65.4 M |
| the reached type on each store into a class root, summaries per place and type, the mapped place filtered by it | 2,064 | 78.3 M |
| the place read from what the argument's roots hold with each global named, so that the filter has types to go by (a set of more than four globals is otherwise one alternative of no type) | 1,613 | 78.5 M |
| the same reach for a struct literal or a call's result built in an assignment's destination | region full at 49,000 frames; 1,985 in 8 GiB regions | 82.8 M |
| the reached type read correctly | 1,863 in 8 GiB regions, 690 s, 10.9 GiB resident | 155.1 M |

- **Until the last step the reached type was unknown for nearly every store that mattered.** The checker writes a use of a reference variable as a dereference of it, so the base of `self_.items` is a dereference node of struct type, not a name of reference type, and the first version of `life_reached` found no reference on the path. 1,920 of 2,031 refused stores had no reached type; a tag on each effect of the code path and statement that first made it ([tools/dbgsite.py](tools/dbgsite.py)) showed them to be plain assignments, `self_.items = default<Entry[:]>()` and `buffer.storage = replacement` again.
- **With it read correctly the filter is in effect, and the cost is its own**: a summary per place and reached type is 6.4 M effects instead of 5.2 M, 8.8 M sets, 155 M alternatives. It does not fit the 2 GiB region, takes two and a half times as long, and the pass still ends with 1,863 errors.
- **So the destination's type is not what decides these errors either.** Three explanations have now each been built and measured (classes that alias, candidates carried in values, destinations of every type); each removed some hundreds and the rest reappeared, 1,600 to 2,000 every time.

**The count cannot tell why, and that is the lesson of the day.** A refused store does not land, so one refusal hides whatever else was merged into its summary entry; split the entries and the rest travels further up and is refused at other calls. The count of distinct calls with a refusal measures how the summaries are cut as much as what the analysis knows. What is needed is not another variant run on the whole program but small programs: a few dozen lines each, cut from a function blot2 is refused at, that plain upstream accepts and this compiler, built with every call class-keyed, refuses. On those a change is right or wrong, at once. `runs/blot2-diagnostics-d26f33c.txt` has the calls, `tools/dbgstore2.py` prints for each the callee, its place and its value, and `tools/mkcls.sh` builds the compiler that shows the error without the other 120,000 lines.

## The first small case: an argument that holds no reference (`952c916`)

Taking the smallest call blot2 was refused at, as the section above says to, paid at once ([qualification](runs/qualification-952c916.json)).

| | `d26f33c` | `952c916` |
| --- | --- | --- |
| corpus, default build | | 0 of 4,355 sources differ |
| corpus and self-check, every call class-keyed | 14 / 33 / 21 / 72, no error | the same |
| blot2, errors of the first pass | 1,681 | 425 ([list](runs/blot2-diagnostics-952c916.txt)) |
| blot2, frames / alternatives | 54,054 / 65.4 M | 53,794 / 56.6 M |
| blot2, bootstrapped compiler | 269 s, 7.3 GiB | 256 s, 6.9 GiB ([run](runs/blot2-run-952c916.json)) |

The call is `validate(proof, quantifier.a, payload)` in `check/package_contracts.goose:415`. `proof` is a local view struct that holds a reference to the function's own `Context` parameter and its `witnesses: const Id[:]` parameter. The refused store was of the `Context`, exactly, into "what the storage of `witnesses` holds". An array of `u32` holds no reference, so there is no such storage: every argument class had been given the classes of what its storage holds whatever its parameters point at. An argument class whose parameters point at one type that holds no reference now holds nothing (bytes aside, which may be a view of anything).

### What is left, and three things that did not move it

The 460 refused stores of an instrumented run on `952c916` ([by kind](runs/store-kinds-952c916.txt), [by first statement](runs/store-origins-952c916.txt)) are still mostly an argument class of the calling function, exactly, into global storage (187 into "something in global storage", 57 into an argument class that holds only globals).

- **Only two source lines in all of blot2 store, in a function body, something read out of a shorter-lived argument's storage into longer-lived storage** ([list](runs/deferred-stores-952c916.txt)): `eval/core_eval.goose:941`, `self_.constant_recorder .= outer`, the restore of a saved `Recorder?`; and `check/check.goose:1457`, the push of a `ProofContract` built from another parameter's header. Such a store is left to the calls to judge.
- **The first, in full** ([dump](runs/deferred-store-core_eval-941.txt)): `matchType(self_: Session&, ..., mappings: PooledMappings&, rows: PooledRows&)`. The `Session` argument is at depth 0. `outer`, read out of `self_.constant_recorder`, is found to be, among other things, "something reached from what `mappings`' storage holds" and "from what `rows`' storage holds". Those are slices of global pools. But a storage class has the depth of its argument class, and `mappings` is a local struct of some caller, so the restore looks like a shorter-lived value going into the session.

| variant, on `952c916` | errors | |
| --- | --- | --- |
| 16 typed classes a frame under pressure instead of 8 | 449 | 67.1 M alternatives |
| a struct copied out of storage, all of whose references point at one type, holds only what such a reference can be ([patch](runs/struct-copy-variant.patch)) | 426 | |
| a storage class is read back only as a pointee its own type can hold: a typed one by its pointee, an untyped one by what its argument's type holds a reference to ([patch](runs/storage-class-type-variant.patch)) | 424 | |
| a storage class is at depth 0 where the frame's first call shows that everything the argument's storage holds is, assumed of every call and taken back by one of which it is not true ([patch](runs/storage-depth-variant.patch)); upstream gives a view its own depth in the key | 447 | the body-level stores at `core_eval.goose:941` fall from 51 to 24 |

None is kept: none moves the count beyond what it wanders by, and none was run on the corpus. The last is the one upstream has and the trace above asks for; it wants a small case of its own before it goes in.

## Two stores found by where they first go wrong (`df28ece`)

"Fix the errors" was the request, with blot2 at 425. Committed as `df28ece`, [qualified](runs/qualification-df28ece.json).

| | `952c916` | `df28ece` |
| --- | --- | --- |
| corpus, default build | | 0 of 4,355 sources differ in output, diagnostics or 11,589 state fingerprints ([report](runs/corpus-default-fingerprints-df28ece.json)) |
| corpus, every call class-keyed | 14 accepted sources rejected, 33 rejected sources accepted, 21 other messages | the same 14, 33 and 21 sources ([list](runs/corpus-every-call-class-keyed-categories-df28ece.json)). 815 sources with the same messages and 1,502 accepted ones differ in state fingerprints only (72 before): the store records are other records now |
| self-check, every call class-keyed | no error | no error |
| blot2, errors of the first pass | 425 | 73 ([list](runs/blot2-diagnostics-df28ece.txt)) |
| blot2, frames / alternatives | 53,794 / 56.6 M | 52,972 / 45.7 M ([progress](runs/blot2-progress-df28ece.txt)) |
| blot2, bootstrapped compiler | 256 s, 6.9 GiB | 284 s wall, 272 s CPU, 6.8 GiB ([run](runs/blot2-run-df28ece.json)): 11% slower for the one pass |

Same machine and sources as above (4 cores, 16 GiB; blot2 `compiler-goose` at `6ad5fbb`, checked with `--reachable-program --expansion-node-limit 1000000 --check`; upstream at `d92c4315` read, and its tests run, not measured).

### How they were found

The count still says little (it went 425, 404, 114, 90, 123, 46, 25, 121, 134, 130, 73 through the day), so the work went by three other things:

- **Upstream's source, read again for one question: when does a call judge a store at all?** (`ApplyCalleeStores`, `FitsAt`, `ShrinkTargets`, `RootCandidates`, `RecordStore`.) Only where the container is one of the callee's classes and the store went through storage the class only leads to, or the argument is not one exact root, or the call is into a cycle. A store into a global is judged in the body and nowhere else. The targets are named by type: the argument's root, and every variable in scope or global whose own storage can hold what the destination was reached as. A value read out of a container and stored back into that container is no store; it only fills the container again where something emptied it. A class of a global argument has depth 0 in the key.
- **A trace of where a pair first appears** ([tools/dbgdefer.py](tools/dbgdefer.py)): a store of something rooted at a class into storage shallower than that class is put off to the callers here, and upstream accepts no program with one in a body. In blot2, 9 statements store such a pair in a body, and 18 store between two class storages at all; 4,237 calls first made one by mapping a callee's store. So the mapping made them, not the program.
- **The eleven upstream tests the last variants broke**, run on every build, with the self-check ([tools/cycle.sh](tools/cycle.sh)).

### A storage's own, put back

`support/pooled_buffer.goose` ends `ensure` with `buffer.storage = replacement; buffer.items = replacement[..length];` and has `buffer.items = buffer.storage[..length]` in `resize` and `clear`. The second kind stores into `buffer` what was read out of `buffer`. It was on record as a store of the argument's storage class into the argument class, and each call above mapped it as any store, pair by pair: where `buffer` was `self_.scopes.buffer`, a reference read out of the caller's own parameter, every storage `self_` refers to took what every other held, global pools among them. Upstream records nothing for it (`RecordStore`: `from == container`, not `bound`).

Dropping it was not enough, and keeping it was too much:

| variant | blot2 | upstream tests |
| --- | --- | --- |
| before | 90 errors, 76.2 M alternatives | |
| such a store dropped ([patch scripts](runs/own-reads-dropped-variant.py.txt)) | 46, 38.8 M | `emptied_callee_call_between`, `emptied_callee_derived_store` and `emptied_callee_shrink_first` accepted: the store also said the container was filled again |
| dropped, with a record that the container is filled again | 25, 37.5 M | the same three: `s.refs.push(s.pool[0])` puts back a reference into the elements of what `s` held a reference to, another kind of reference, and the shrink rule needs it |
| kept as a store, landed in each root as what that root holds ([patch scripts](runs/own-stores-kept-variant.py.txt)) | region full at 46,000 frames, 78.7 M | all report |
| the same, dropped where the root's contents cover it | region full at 38,000 frames | two accepted: covered by the class's own general alternative in the callee is not "nothing new" for a caller whose storage holds something more particular |
| **on record without a set** | 121, 43.9 M | all report |

The last is what is committed. The store is a record of what kind of reference went back in (as the storage held it, one into what such a reference points at, a byte view, or both) and to what type, in `LifeEffect.field` and `value.type_id` (`life_own_reads`, `life_own_effects`). A call applies that to what each storage the class is there holds itself (`life_own_store`), and passes the record on. Half of the pass's sets were these stores mapped.

### The type a store reaches

With that, the trace named 11 calls in the whole program, nearly all in `check/capability_lifetimes.goose`:

```
fn pushExit(out:Exit[>..<]&,module:const Module&,target:CoreId,value:Id) {out.push(Exit{module:module,target:target,value:value});}
...
pushExit(self_.exits,module,n.b,result.value);
```

A reference to `module` goes into the array `self_.exits` points at, a local of the function that made the `Scan`. Upstream accepts it by type: no global can hold an `Exit[>..<]`, and `module` outlives `self_`. Here the store landed in the caller's storage class "whatever `self_`'s storage refers to" as a store into that root, and the calls above put it in everything `self_` refers to. Three things were each needed, and the count shows it only with the last:

| step | blot2 errors |
| --- | --- |
| a store into a storage class keeps the type its destination was reached as (`LifeEffect.value.type_id`; `life_reached` reads it off the destination's path, upstream's `Dest::reached`), and a call lands it only in what such a destination can lie in | 134 |
| "something in global storage" (the alternative more than four globals fold into) stands for a reference to a type only where some global's own storage holds one (`life_globals_contain`), on a read-back and where a call maps | 130 |
| the pointee type of a call's one reference to a root is kept beside the root (`map_types`): `self_.exits` had become one exact alternative with the step before, and the path for those took the type from the callee's side, which has none | 73 |

### Before those: what was only reached from an argument's storage

Two changes from the start of the day are part of the commit. Something only known to be reached from a storage class is mapped from what that class's roots hold, a level at a time (`life_class_deep`); mapped from the argument's roots it took in the class's own roots, and a store of it into that class made each hold itself (425 to 114 with the next). And a store into a class root of what was only reached from the same argument's storage is no store a call can place (`life_unpermuted`).

### Tried and not kept

| variant | result |
| --- | --- |
| a store into a class root drops every storage class of the same argument from what is stored, exact ones too | 3 errors, 30.7 M alternatives, 222 s. But seven upstream error tests pass: `store_class_view_reached`, `class_store_view_outlived`, `store_reached_alias`, `store_class_view_reached_call`, `cycle_read_through_two_pools`, `emptied_callee_call_between`, `emptied_callee_derived_store`. A store between two things one argument refers to is judged at the call |
| where a call lands a store, each root takes only what its type holds a reference to, the globals unfolded up to 16 ([patch script](runs/pairwise-type-variant.py.txt)) | 123 errors (from 90), 77.5 M alternatives |
| what the globals hold and hold references to, by type, asked wherever the folded alternative is a place or a pointee ([patch script](runs/global-types-variant.py.txt)), before the own-store change | 90 errors, no change: blot2's globals are pools of nearly every type it stores. The part that asks what a global holds inline is in the commit, where the type of the destination now reaches it |

### What is left

73 calls, not traced yet with these changes in. The method stands: the trace of first appearances, one call at a time, upstream's rule for it read, the eleven tests and the corpus on what results.

## Types where a call lands a store (`e7cb7c9`)

The same request, continued from 73. Committed as `e7cb7c9`, [qualified](runs/qualification-e7cb7c9.json).

| | `df28ece` | `e7cb7c9` |
| --- | --- | --- |
| corpus, default build | | 0 of 4,355 sources differ ([report](runs/corpus-default-fingerprints-e7cb7c9.json)) |
| corpus, every call class-keyed | 14 / 33 / 21 | the same 14, 33 and 21 sources ([list](runs/corpus-every-call-class-keyed-categories-e7cb7c9.json)) |
| self-check and the eleven upstream tests, every call class-keyed | no error; all eleven report | the same |
| blot2: calls where a class-rooted value first meets shallower storage | 1,157 | 509 |
| blot2, errors of the first pass | 73 | 64 ([list](runs/blot2-diagnostics-e7cb7c9.txt)) |
| blot2, frames / alternatives | 52,972 / 45.7 M | 52,940 / 48.5 M ([progress](runs/blot2-progress-e7cb7c9.txt)) |
| blot2, bootstrapped compiler | 284 s wall, 6.8 GiB | 257 s wall, 246 s CPU, 7.0 GiB ([run](runs/blot2-run-e7cb7c9.json)) |

**The error count rose on the last step and that step is kept.** Each step below only takes pairs away from what a call lands, and the count went 73, 73, 84, 83, 52, 42, 42, 64. A refused store does not land and is reported once, at the call that refuses it; no longer refused there, it lands, is passed up, and is judged at every caller above. The count is of calls with a refusal, and a wrong pair removed low in the call tree can add callers to it. The number that fell with every step that did anything is the one `tools/dbgdefer.py` counts: the calls whose mapping first makes a pair of a class-rooted value and shallower storage (4,237 that morning, 1,157 at `df28ece`, 509 now).

### One refusal, followed down

`tools/dbgwatch.py` prints every store of one root into another, by their numbers (`DBG_WATCH=PLACE,VALUE` in the environment, no rebuild between runs), with the callee and the callee alternatives that became the value: one run of blot2 for each level down. `tools/dbgintro.py` prints where an exact storage-class alternative of one target type first enters global storage. From `quoteEffectsContextWorkspace` (`check/staging_core.goose:305`), refused for storing its `remaining: i64&` in global storage:

```
visit (263) <- handle (256) <- effectHandleProvider (257) <- ... <- loanCallback (178):
    var scoped=scopedNamed(self_,self_.locals,self_.loop_owner,owner,self_.active_calls,self_.decision_owner);
    let error=scoped.node(id,parameters,closed_rows,depth+1);
    publishNamed(self_,scoped);
```

At `scoped.node(...)` the callee's effect was "storage of type `ModuleRef` that `self_` refers to takes a reference to `i64` storage that `self_` refers to". `struct ModuleRef { value: const Module& }` cannot hold a reference to an `i64`. Both sides were "what the argument's storage holds", read as two pointee types, and a call maps each side to everything of that kind and lands the product. `scoped` is a local view whose fields were all read out of `self_`; its contents are one alternative at `self_`'s storage class, the target types of the fields merged away.

### What was changed, in order

| step | errors | alternatives |
| --- | --- | --- |
| `df28ece` | 73 | 45.7 M |
| a reference argument remembers the type its expression reaches (`LifeValue.reached`, kept beside its class in `map_types`), for an argument that points at part of something read out, whose alternative has no type | 73 | 45.8 M |
| a store into an argument class keeps its reached type too; where the call's reference has a type of its own, that one is taken | 84 | 45.4 M |
| a literal's fields and a call's result built in an assignment's or a builtin's destination reach what that destination does (`dest_place`, `dest_reached`) | 83 | |
| **a stored reference of known pointee lands only in storage whose type holds a reference to such a pointee** (`life_refers`, `life_place_holds`, `life_referable`) | 52 | 45.4 M |
| what a storage class holds, taken as one pointee, is a reference to that pointee (`life_typed_held`) | 42 | 50.7 M |
| something only reached from storage of one pointee type is followed through what that type holds a reference to (`life_deep`) | 42 | 50.5 M |
| storage of a type that holds no reference takes no store and leads nowhere | 64 | 48.5 M |

Untyped stores into a class root recorded at a call went from 9,466 calls to 4,766 over these steps (`tools/dbgwhy.py`); in bodies, 38,194 statements still store into an argument class with no reached type, most of them a constructor filling its result.

### What is left

509 calls still first make a wrong pair, and the 64 errors are what becomes of them. What the traces show of them:

- **One class for everything an argument's storage refers to.** `self_`'s tables, its module, its locals and its counters are one root unless a storage class of their pointee type exists, and those are cut to 8 a frame once the pass holds 4 M alternatives. A store of a `u32[:]` parameter into a `Locals` that `self_` refers to is then held by "what `self_` refers to", and read back as what a `Module` holds, which has `u32[:]` tables of its own. Types cannot tell those apart; a class per pointee type would. There is room to try more of them now (48.5 M of 79.5 M alternatives).
- **13 of the 64** are calls of `node` in `check/staging_core.goose` whose value is "something reached from `Module`, `ModuleRef` or `i64` storage of `self_`": the last now leads nowhere, the other two reach everything through the untyped class.
- **Large view types.** `Module` and the type tables hold references to nearly every type, so "what this type can refer to" removes little there.

## The same test, tightened (`c72e198`)

Committed as `c72e198`, [qualified](runs/qualification-c72e198.json).

| | `e7cb7c9` | `c72e198` |
| --- | --- | --- |
| corpus, default build | | 0 of 4,355 sources differ ([report](runs/corpus-default-fingerprints-c72e198.json)) |
| corpus, every call class-keyed | 14 / 33 / 21 | the same 14, 33 and 21 sources ([list](runs/corpus-every-call-class-keyed-categories-c72e198.json)) |
| self-check and the eleven upstream tests, every call class-keyed | no error; all eleven report | the same |
| blot2: calls where a class-rooted value first meets shallower storage | 509 | 237 |
| blot2, errors of the first pass | 64 | 38 ([list](runs/blot2-diagnostics-c72e198.txt)) |
| blot2, frames / alternatives | 52,940 / 48.5 M | 52,877 / 49.3 M ([progress](runs/blot2-progress-c72e198.txt)) |
| blot2, bootstrapped compiler | 257 s wall, 7.0 GiB | 256 s wall, 246 s CPU, 7.1 GiB ([run](runs/blot2-run-c72e198.json)) |

In the order tried, each on `e7cb7c9`'s state plus the kept steps before it:

| step | errors | first appearances | alternatives | |
| --- | --- | --- | --- | --- |
| 16 storage classes by pointee a frame under pressure, not 8 | 57 | 573 | 58.8 M | not kept: more classes by order of first use do not separate what matters, and cost 10 M alternatives |
| a place only known to outlive a root keeps the type it was reached as, for the stores above it and for the type test (`life_place_holds`, `life_reached_places`) | 64 | 510 | 50.3 M | kept: the watch showed a store into "something `ModuleRef` storage leads to, reached as a `ModuleRef`" passing the test untested |
| **the test itself**: a slot's pointee type must be the stored reference's pointee type or a part of it (`life_refers`) | 38 | 237 | 49.3 M | kept |
| what an untyped storage class holds, landing in storage all of whose references point at one type, becomes a reference to that type ([patch script](runs/single-pointee-narrowing-variant.py.txt)) | 38 | | 49.1 M | not kept: no change |

**What the test had wrong.** `life_refers(holder, pointee)` asked, of each reference a `holder` holds inline, whether its pointee type holds the stored `pointee` or lies in it. Both directions were meant for a stored reference known only by the type of the root it points into. With the stored reference's own pointee type in hand (`i64`), "the slot's pointee type (`Module`) holds one" let a reference to a counter into every `const Module&`. The second direction is now taken only for an argument class, whose parameters' type may be a part of a larger value.

**Left: 237 calls, 38 errors.** 167 of the 237 are a store into a storage class of one pointee type of a value that is an untyped storage class, exactly: a struct copied out of a parameter's storage, which carries "everything that storage holds". Neither side of the test knows a type there. What the copy can hold is known where it is made (the struct's type), and is lost when its contents are read as roots.

## Not right yet

- **blot2's 38 errors** (`c72e198`), from 237 calls that first make a wrong pair. See "The same test, tightened", what is left.
- **The 33 corpus sources where the class path misses an error**, unchanged.
- **Memory.** 49.3 M alternatives of 79.5 M after one pass; later passes and validation have not run. The 2 GiB is `GS_STACK_RESERVE`, the address space the runtime reserves per region, and a C compiler flag raises it (the 8 GiB runs above). Upstream's compiler has `--stack-reserve` for this, and since `707c546` so has this one ([qualification](runs/qualification-707c546.json): the generated C is unchanged without the option; a program that resizes one array to 300 M `i64` overflows as built before and runs with `--stack-reserve 8G`). The compiler's own bootstrap still uses the default.
- **Peak RSS is 7.1 GiB** for the one pass, which takes 256 s.

## Tools

`trace.sh` builds a work copy with `dbgstore2.py`, `dbgdefer.py` and `dbgwhy.py` (where a store into a class root is recorded without a reached type) and prints their tallies for blot2. `dbgwatch.py`, `dbgintro.py` and `watch.sh PLACE VALUE` follow one store down the calls, as under "One refusal, followed down".

`cycle.sh NAME` builds a work copy with every call class-keyed and with the progress counters, runs the eleven upstream tests and the self-check, then blot2. `dbgdefer.py` (after `dbgstore2.py`) prints where a store of something class-rooted into shallower storage first appears: in a body, at a call whose callee had none, between two class storages in a body, of one argument into another.

In [tools/](tools/), beside those of the earlier page: `corpus0.sh` builds a source directory with the state fingerprints at the default limit and at 0 and compares both with a baseline over the corpus; `catsum.py` counts the differing diagnostics; `variant.sh` builds the every-call-class-keyed compiler with one edit applied, for bisecting; `gdbhook.py`, `gdbcmds.txt` and `gdbstacks.py` sample the call stack of one in 2,503 new sets under gdb and aggregate them; `dbgstore2.py` describes refused stores and `dbgpool.py` what first stores a reference into one named global; `setsites.py` and `bigsets.py` are updated for the current source; `dbgorigin.py` tags each store with the statement that first made it and `origins.py` counts refused stores by it; `dbgvia.py` and `viacats.py` say which of the callee's alternatives became the refused source and the destination; `storecats.py` counts refused stores by kind; `smallest.py` ranks the refused calls by the size of caller and callee, to pick the next small case; `dbgsite.py` tags store effects with the code path that made them.
