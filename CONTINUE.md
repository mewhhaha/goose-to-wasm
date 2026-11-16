# Continue here

Where the work stands on 2026-11-15 and how to pick it up. The standing rules are in [AGENTS.md](AGENTS.md).

## Rules in force

- **The owner's order (2026-11-15): match upstream Goose in functionality, get to where this compiler can compile blot2, and only then work on compiling it faster.** Plain upstream is the reference; blot2 builds its Goose port with `aardappel/goose` at `d92c4315`, unpatched.
- Push qualified batches straight to `origin/main`, with no pull request, and check the remote head with `git ls-remote origin main`. The owner said it again on 2026-11-15: merge everything straight to main.
- A performance change keeps every output byte-identical. `scripts/qualify.py` proves this against a compiler built from the previous sources. For the lifetime pass, also compare the analysis state (see Commands).
- A change made to match upstream, such as keying the lifetime pass's frames by argument classes, changes what is analyzed, so the state comparison does not apply to it. The contracts carry it instead, together with the diagnostics of every conformance source against the previous compiler's (`fpcompare.py` compares them).
- Keep rejected experiments and their tradeoffs in the dated evidence. Keep the README's benchmark text and charts in step with that evidence.
- The C++ reference compiler has been removed, so all work is on the Goose compiler. Upstream Goose is the reference, used read-only.
- ../blot2 is a workload; don't edit it. Copy its sources before measuring, because its checkout keeps moving.

## Where it stands

- **Seed.** The bootstrap seed is snapshot 63: seed C `28f1af08…`, profiled executable `10ade9d5…` ([snapshot 63](selfhost/results/2026-11-14/snapshot-63/README.md)). Main has the export-root commit, the nine lifetime commits of 2026-11-14, the eight of 2026-11-15 and the six class-keyed-frame commits (`bc00c87`, `0f9ec7f`, `e13cd80`, `f4d1d02`, `3ddf811`, `d26f33c`) and `--stack-reserve` (`707c546`) on top of it, none of which is frozen into a snapshot yet.
- **Conformance.** 10,689 of 10,793 rows pass. The 104 failures are the recorded gaps in [known-gaps.json](tests/conformance/known-gaps.json), each with its cause.
- **Upstream features.** Features added upstream since the contracts were pinned are tracked in [docs/FEATURES.md](docs/FEATURES.md).
- **The compiler checking itself.** 7.0 s, down from 24.7 s before the 2026-11-15 commits, with the same analysis state ([evidence](bench/results/2026-11-15/lifetime-walks-and-memos/README.md)). The lifetime pass is still 6.7 s of it. With every eligible call keyed by classes it takes a third of the time and, since `f4d1d02`, reports no false error (58 before). The class path still misses 33 errors in the corpus, so it is not used below its 4,096-frame limit.
- **Small programs.**
  - Snapshot 63 compiles the eleven benchmark programs in 1.04–1.06× snapshot 61's time ([campaign](bench/results/2026-11-14/compiler-throughput-63/README.md)).
  - The lifetime commits since then are within noise both times: 1.009 and 1.014 on 2026-11-14 against a null run's 1.010 (one binary timed against its own copy), and 0.990 and 0.987 on 2026-11-15 against a null run's 0.973, with the same page faults.

## Current frontier: blot2's compiler

The owner's order is to get to where this compiler compiles ../blot2's `compiler-goose` (450 modules, 120,000 lines), and to make that fast afterwards. Four things stood in the way:
1. Exported functions as lifetime roots. **Done** in `9806f0e`.
2. The lifetime pass finishing on that program. **Its first discovery pass ends** (since 2026-11-15, `e13cd80`); the check as a whole does not yet. This is the work in hand.
3. A root to emit from, and 4. the C-host interface: see "After the pass finishes".

**Command.** From a copy of `compiler-goose/src`, run:

```sh
goose main.goose --stdlib <this repo>/stdlib --reachable-program --expansion-node-limit 1000000 --check
```

Parsing and type checking take about 12 s. The lifetime pass runs after that.

**What changed.** Past 4,096 frames, a call of a top-level function is checked by the *classes* of its arguments, as upstream's specializations are: one frame per key, evaluated on its own (an "island"), its effects and result mapped onto each call's roots. Two evidence pages hold the design, the numbers and everything tried and dropped: [the path itself](bench/results/2026-11-15/class-keyed-frames/README.md) (2026-11-15) and [stores per pair of classes](bench/results/2026-11-16/class-stores-per-pair/README.md) (2026-11-16). The code is `selfhost/checker_lifetimes.goose` from "Class-keyed frames" on, with a comment at each piece.

**Where it stands on blot2** (`6ad5fbb`, the bootstrapped compiler of `d26f33c`, on a 4-core 16 GiB container):
- Pass 1 ends after 54,054 frames in 269 s, with 65.4 M alternatives of the 79.5 M that fit and a peak RSS of 7.3 GiB.
- It ends with 1,681 errors, so no second pass and no validation has run yet. 1,680 are "stored reference does not outlive the storage that receives it" at a call. blot2's patched upstream build accepted this program, so treat them as this analysis's imprecision until shown otherwise.
- Plain upstream `d92c4315` on the same copy: stopped at 1,500 s, nothing printed.

**Do not steer by blot2's error count.** A stored value that is a storage class, or only "reached from" a class, is not judged at the call that replays the store but further up. Finer classes turn more of those into exact argument classes, which are judged at once, so a more exact variant reported 3,069 errors and a coarser one 1,890. Steer by the builds with every call class-keyed: the self-check (no error now) and the corpus (14 accepted sources rejected, 33 rejected sources accepted, `tools/corpus0.sh` in the 2026-11-16 evidence directory).

**Small programs are untouched, and that is checked.** The corpus's largest program makes 720 frames and the self-check 2,436. Every commit so far keeps the state fingerprints of all 4,355 conformance sources and of the self-check (`fpcompare.py`, see Commands). Keep it so: anything new goes behind `l.class_frames > 0` or an island test.

**Next, in order.**
1. **Where a store through a read-out reference lands.** Four fifths of the refused stores (1,351 of 1,725 at `d26f33c`) store an argument class of the calling function, exactly, into "something in global storage". A storage class as a store's place maps, at a call, to every root the argument's storage holds a reference to: for a struct of pooled tables, every global pool it has a slice of, and a value that is not global is refused against each. Upstream (`ApplyCalleeStores`, `ShrinkTargets`) lands such a store in the argument's own root as a bound, and in the candidates for the *reached* type: the type of the storage the slot lies in as the destination reached it. The 2026-11-16 page has this under "After `d26f33c`". To build:
   - the reached type of a store, read off the destination expression in `life_eval` (the element type of the innermost reference or slice the lvalue goes through), passed to `life_store` and on to `life_add_contents`, and kept on the effect in `value.type_id` for a class-root place, so that summaries are per place and reached type (`life_summary_key` and `life_effect_merge` already tell entries apart by it);
   - in `life_map_set`, for a store's place at a storage class: the argument's roots, and of what the argument's storage holds only the roots that can hold the reached type inline (`life_can_take` with the type; a class root of the caller stays, with its `class_pointee` as its type where it has one).
   Two things already tried there, with their numbers on the page: the type *stored* instead of the type reached, per summary (it works, 1,664 errors, and doubles the alternatives: too many types per place), and one merged set of types per place (no change at all: the untyped storage class takes stores of every type).
2. **The 33 corpus sources where the class path misses an error.** These are the reason the limit cannot be lowered. The shrink check is where most are: it does not see that the class of everything a storage holds covers the class of one pointee type in it.
3. **Then the passes after the first.** Their cost on blot2 is unmeasured. The validation effect lists are not merged by kind as the discovery summaries are, and will be large.
4. **Memory.** Sets are never freed; 65.4 M alternatives after one pass leaves little room, and a root per pointee type is not affordable at all (234 M alternatives a third of the way in, with the limit on typed classes lifted). The 2 GiB is `GS_STACK_RESERVE`, the address space per region. Since `707c546` the driver has upstream's `--stack-reserve size`: a compiler emitted with `goose selfhost/main.goose --target native -O2 --stack-reserve 8G -o goose.c` has 8 GiB regions (the experiments that needed room were built with the same define on the C compiler's command line). The bootstrap still builds the compiler with the default: changing that changes the seed's C, so it belongs with the next snapshot, once a second pass on blot2 shows what is needed. `LifeAlt` is 28 bytes of which `bound` is unused with class-keyed frames in use.

**Done on 2026-11-16, for the record of what not to redo.** A read-out reference's value no longer carries its candidates (`d26f33c`): they are a mask on the storage class, asked for by the alias rules and by a store or shrink through the reference. Dropping them outright loses upstream's `store_reached_table` and `construct_use_bound_holder_ref`; stripping them from stored values loses `shrink_class_copy_kept_own`. A fold of many typed classes into the untyped one loses `emptied_callee_shrink_first`. All four are on the page.

**Tools for this**, in `bench/results/2026-11-16/class-stores-per-pair/tools/`: `corpus0.sh NAME` builds `build/work` with the state fingerprints, at the default limit and with every call class-keyed, and compares both with the baseline over the corpus; `dbgstore2.py` prints each refused store with the callee's sets; `dbgorigin.py` and `origins.py` trace refused stores back to the statement that first made them; `dbgvia.py` and `viacats.py` say which of the callee's alternatives became the refused source; `dbgpool.py` finds what first puts a reference into one named global.

**Known gaps of the class path**, all listed with their cause on the evidence page: stores through storage only known to outlive a class root; a callee's shrink against values the callee cannot tell apart; `index_of` and slice-pool checks through class roots.

**Reference points on the earlier copy** (`93c8fa8`, 2026-11-14, on the owner's machine).
- Upstream with blot2's patches 01–11 stops after 66 s, at its first lifetime error. Upstream stops at the first error it meets; this pass reports errors only after a whole discovery pass.
- blot2's own build, patches 01–29, checks it without errors in 435 s, with a peak RSS of 17.9 GiB. That build includes the precision patches.
- blot2 kept its patches in `compiler-goose/tools/upstream-32a4f44/`; they left its checkout on 2026-11-14 but are in its history at `93c8fa8`. blot2 has since parked this port and builds with plain upstream.

**The old path's limits**, for the record: [what stopped it and why](bench/results/2026-11-15/lifetime-walks-and-memos/README.md) (a frame per set of concrete roots; 18 functions held 36,700 of 90,000 frames).

### After the pass finishes (not requested yet)

- **Precision patches 12–17.** These patches make upstream accept code it otherwise rejects, so adopting any of them is the owner's decision. Expect the first error that patches 01–11 report: `reuse/code_expectation.goose:40`, "returning a reference rooted in n, which dies with this function (§9.2)".
- **A root to emit from.** `--target native` needs `fn main()`. `--library` instead type checks every function, and on blot2 it reports 135 errors in code nothing reaches. The fix is either a `main` that calls `blot_main::mainEntry()`, or a `--library` that is limited to what `--reachable-program` reaches.
- **The C-host interface** that blot2's `compiler-goose/build.py` uses:
  - `--emit-runtime runtime.c`;
  - `--header`;
  - `goose_init(argc, argv)` and `goose_exit`;
  - blot2's patch 19 hook, `gs_runtime_observer_install`.

  Externs resolve through `dlsym`, so the host must export them, for example with `-rdynamic`. docs/FEATURES.md lists `--shared`, `--header` and `goose_init` as missing.

## Other open work

- **Small-program costs**, each 0.1–0.5 ms ([Still open](bench/results/2026-11-14/compiler-throughput-63/README.md#still-open)):
  - lifetime list sharing on small sets;
  - `mark_located_functions`;
  - name lookups that rehash a token's text.
- **The 104 conformance gaps.**
- **Unsupported upstream features**, the `no` and `partial` rows in docs/FEATURES.md. Examples: upstream's newer `checkfree` rule, native packages, and the package build sidecars.

## Commands

- **Development compiler** (eight C units, no profile): `python3 scripts/bootstrap.py --build-dir build/dev-X --source-dir selfhost --jobs 8 --cache-dir build/qualify-cache/bootstrap`.
- **Qualification:**

  ```sh
  .venv/bin/python scripts/qualify.py --output-dir build/q-NAME --cache-dir build/qualify-cache --baseline <previous sources' compiler> --jobs 10
  ```

  It runs these stages:
  - bootstrap `--verify`;
  - conformance;
  - the native rows as three units, only when native code generation changed;
  - native checks;
  - output equivalence against the baseline;
  - unit tests.

  With a warm cache it takes about 15 minutes. It needs `.venv` for wasmtime.
- **Equivalence alone:** `tests/output_equivalence.py`. A frozen copy of `selfhost/` needs `native/` beside it, or its rows fail identically in both compilers.
- **Lifetime state:** `bench/results/2026-11-14/blot2-lifetimes/tools/instrument.py`. Its `fingerprint` mode hashes the analysis state at pass boundaries, and `fpframes` mode adds a hash every 2,000 frames on blot2. Compare two runs with `fpcompare.py`. The tools are written for an agent worktree's `build/tools/`, so adjust their absolute paths.
- **Replaced searches:** `bench/results/2026-11-15/lifetime-walks-and-memos/tools/xcheck.py` makes a build that runs the linear frame searches and node-by-node read walks beside the indexed ones and reports a difference; `xcorpus.py` runs it over the conformance sources. `coverage.py` reports how many functions the pass has entered.
- **Compiler speed:** `bench/compare_compilers.py --samples 31 --cpu N --seed S`, with charts from `bench/compiler_comparison_charts.py`. Also run a null comparison, of one binary against its own copy, to see the noise.
- **Freezing a snapshot:** the protocol is in the snapshot 63 README. The profile is trained on the self-compile plus the `leaf-properties` and `flow-prefilter` fixtures at weight 64, with Clang 23, and both public roots must verify. The script that ran it, `build/redeliver63.sh`, is local and untracked.
- **Profiling:** without `perf`, use the `LD_PRELOAD` sampler in `bench/results/2026-11-15/lifetime-walks-and-memos/tools/` (`prof.c`, `report.py`): it records the interrupted function and, in a build with `-fno-omit-frame-pointer`, two callers. `--wasm-stats FILE` reports phase times, node counts and the function names behind the `g_fnN` symbols.

## Gotchas

- **The machine is shared**, often at load 10–18 on 16 threads. Only interleaved or side-by-side runs give usable ratios, and they should be read against a null run.
- **Check small programs after a large-program speedup.** Time an empty `fn main() {}` with `--check` and count its page faults. A constant-size table can cost a small program more than its whole check, which is how snapshot 62 got 1.36× slower.
- **Close stdin for stages that run Node or wasmtime**, or they wait on it. `qualify.py` already does this.
- **blot2 needs `--expansion-node-limit 1000000`**, the same limit blot2's build uses.
- **The blot2 copy's identity hash depends on the locale `sort` runs in.** `91598806…` is under `en_US.UTF-8`; the `C` locale gives `47674ec6…` for the same files.
- **A cloud session** has 4 cores and one 16 GiB memory limit for every process, without swap. A blot2 analysis reaches 8 GiB, so run one at a time, and not beside a compiler build.
- **Field and variable names:** `recursive` is a keyword.
