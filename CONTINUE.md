# Continue here

Where the work stands on 2026-11-15 and how to pick it up. The standing rules are in [AGENTS.md](AGENTS.md).

## Rules in force

- **The owner's order (2026-11-15): match upstream Goose in functionality, get to where this compiler can compile blot2, and only then work on compiling it faster.** Plain upstream is the reference; blot2 builds its Goose port with `aardappel/goose` at `d92c4315`, unpatched.
- Push qualified batches straight to `origin/main`, with no pull request, and check the remote head with `git ls-remote origin main`. The owner said it again on 2026-11-15: merge everything straight to main.
- A performance change keeps every output byte-identical. `scripts/qualify.py` proves this against a compiler built from the previous sources. For the lifetime pass, also compare the analysis state (see Commands). Time and memory are each run's own (`os.wait4`), never `getrusage(RUSAGE_CHILDREN)`, whose peak RSS is the largest of every child so far.
- A change made to match upstream, such as keying the lifetime pass's frames by argument classes, changes what is analyzed, so the state comparison does not apply to it. The contracts carry it instead, together with the diagnostics of every conformance source against the previous compiler's (`fpcompare.py` compares them).
- Keep rejected experiments and their tradeoffs in the dated evidence. Keep the README's benchmark text and charts in step with that evidence.
- The C++ reference compiler has been removed, so all work is on the Goose compiler. Upstream Goose is the reference, used read-only.
- ../blot2 is a workload; don't edit it. Copy its sources before measuring, because its checkout keeps moving.

## Where it stands

- **Seed.** The bootstrap seed is snapshot 63: seed C `28f1af08…`, profiled executable `10ade9d5…` ([snapshot 63](selfhost/results/2026-11-14/snapshot-63/README.md)). Main has the export-root commit, the nine lifetime commits of 2026-11-14, the eight of 2026-11-15 and the seven class-keyed-frame commits (`bc00c87`, `0f9ec7f`, `e13cd80`, `f4d1d02`, `3ddf811`, `d26f33c`, `952c916`) and `--stack-reserve` (`707c546`) on top of it, none of which is frozen into a snapshot yet.
- **Conformance.** 10,689 of 10,793 rows pass. The 104 failures are the recorded gaps in [known-gaps.json](tests/conformance/known-gaps.json), each with its cause.
- **Upstream features.** Features added upstream since the contracts were pinned are tracked in [docs/FEATURES.md](docs/FEATURES.md).
- **The compiler checking itself.** 0.34 of the CPU time of `ddbbe23` since `a787c63` (2026-11-17: 11.5 s to 3.9 s in one run, peak RSS 503 to 306 MiB), in two deliveries that day: [read memos](bench/results/2026-11-17/lifetime-read-memos/README.md) (0.59) and [validation shortcuts and 32-byte reads](bench/results/2026-11-17/lifetime-compact-reads/README.md) (0.64 of that). Before them: 7.0 s from 24.7 s on 2026-11-15 ([evidence](bench/results/2026-11-15/lifetime-walks-and-memos/README.md)). Each time every frame's effects were the same. While no frame is class-keyed, a summary holds a construct read as a `LifeReadEntry` (leaf, last leaf taken, walk stamp, the chain it was sent up) found through a per-frame table; `life_reads_materialize` turns them into ordinary entries at the first class-keyed frame. The lifetime pass is still 80% of a self-check, but its profile is flat: nothing above 6% but evaluating bodies. With every eligible call keyed by classes it takes a third of the time and, since `f4d1d02`, reports no false error (58 before). The class path still misses 33 errors in the corpus, so it is not used below its 4,096-frame limit; with the limit at 64, two conformance sources change verdict (`stdlib_regex` accepted, `render_walks_around_overloads` rejected) and the self-check takes under half the time.
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

**Where it stands on blot2** (`6ad5fbb`, the bootstrapped compiler of `c72e198`, on a 4-core 16 GiB container):
- Pass 1 ends after 52,877 frames in 256 s, with 49.3 M alternatives of the 79.5 M that fit and a peak RSS of 7.1 GiB.
- It ends with 38 errors (425 on the morning of 2026-11-16, 2,348 on 2026-11-15), from 237 calls that first make a wrong pair (4,237 that morning), so no second pass and no validation has run yet. All are "stored reference does not outlive the storage that receives it" at a call. blot2's patched upstream build accepted this program, so treat them as this analysis's imprecision until shown otherwise.
- Plain upstream `d92c4315` on the same copy: stopped at 1,500 s, nothing printed.

**Do not steer by blot2's error count.** A stored value that is a storage class, or only "reached from" a class, is not judged at the call that replays the store but further up. Finer classes turn more of those into exact argument classes, which are judged at once, so a more exact variant reported 3,069 errors and a coarser one 1,890. Steer by the builds with every call class-keyed: the self-check (no error now) and the corpus (14 accepted sources rejected, 33 rejected sources accepted, `tools/corpus0.sh` in the 2026-11-16 evidence directory).

**Small programs are untouched, and that is checked.** The corpus's largest program makes 720 frames and the self-check 2,436. Every commit so far keeps the state fingerprints of all 4,355 conformance sources and of the self-check (`fpcompare.py`, see Commands). Keep it so: anything new goes behind `l.class_frames > 0` or an island test.

**Next, in order.**
1. **The next call the trace names.** 38 errors are left. Do not work from the count (it went 425, 404, 114, 90, 123, 46, 25, 121, 134, 130, 73, 84, 83, 52, 42, 42, 64, 64, 38 on 2026-11-16: a store no longer refused low in the call tree is judged at every caller above) but from where a wrong pair first appears (`tools/dbgdefer.py`'s `map` lines: 4,237, then 1,157 at `df28ece`, 509 at `e7cb7c9`, 237 at `c72e198`), as those commits were found (the 2026-11-16 page, "Two stores found by where they first go wrong" and "Types where a call lands a store"):
   - `tools/cycle.sh NAME` (2026-11-16 evidence directory; it expects the work copy in `build/work`) builds with every call class-keyed, runs the eleven upstream tests that the unsound variants broke and the self-check, then blot2. All eleven must report an error and the self-check none before a blot2 number means anything. Then `tools/corpus0.sh` for the whole corpus: 14 / 33 / 21 and no source differing on the default path.
   - `tools/dbgstore2.py DIR 1` prints each refused store with the callee, its place and its value; `tools/dbgdefer.py DIR` prints where a store of something class-rooted into shallower storage first appears (in a body, at a call whose callee had none, between two class storages, of one argument into another). Upstream accepts no program with such a pair in a body, so each first appearance at a call is the mapping's doing. Find the few calls, read the two functions, read what upstream does for that statement (`ApplyCalleeStores`, `FitsAt`, `ShrinkTargets`, `RootCandidates`, `RecordStore` in `build/upstream-d92c431/source/src`).
   - What upstream does, as far as it has been read: a call judges a store only where the container is one of the callee's classes and the store went through storage the class only leads to, or the argument is not one exact root, or the call is into a cycle; a store into a global is judged in the body alone; targets are named by type (every variable in scope or global whose own storage can hold what the destination was reached as); a value read out of its own container and stored back is no store; a class of a global argument has depth 0 in the key.
   - To follow one refusal down: `tools/dbgwatch.py` and `tools/watch.sh PLACE VALUE` (root numbers from a `DBGSTORE` line; one blot2 run a level, no rebuild), `tools/dbgintro.py` for where a storage-class alternative of one target type first enters global storage, `tools/trace.sh` for the tallies.
   - The likeliest next step: the contents of a struct copied out of a parameter's storage. 167 of the 237 calls store such a value, an untyped storage class alternative ("everything that storage holds"), into a storage class of one pointee type; neither side of the type test (`life_referable`) knows a type there. The struct's own type says what the copy can hold where it is made (`life_load` of a non-reference type, `life_stored_roots`), and typing the alternatives there by the struct's fields is the thing to try. Typing them where they land, by the single pointee of the storage they land in, changed nothing (`runs/single-pointee-narrowing-variant.py.txt`), and neither did 16 storage classes by pointee a frame instead of 8 (573 calls, 58.8 M alternatives).
   - Not yet in: a place that is not one exact alternative takes no reached type; 38,194 body statements store into an argument class with none (`tools/dbgwhy.py`), most of them a constructor filling its result.
   - Earlier leads, not looked at since: `eval/core_eval.goose:941` (`self_.constant_recorder .= outer`, `runs/storage-depth-variant.patch`) and `check/check.goose:1457`, the push of a `ProofContract` whose header came from another parameter. Both were among the 9 body-level stores of the trace.
   Things known to matter when reading the analysis: the checker writes a use of a reference variable as a dereference node (`N_UNARY`, `T_MUL`); a set of more than four global roots is one alternative of no type (`life_fold`), which since `df28ece` stands for a reference to a type only where a global holds one (`life_globals_contain`); a struct copied out of a parameter's storage carries everything that storage holds, with no target type; a store's place set is the root alone, its reached type is in `LifeEffect.value.type_id`; a store of a storage's own has `LifeEffect.field` -2 to -5 and no set; a call lands a pair only where the place's type holds a reference to the stored pointee (`life_referable`), which says nothing where either type is unknown.
2. **The 33 corpus sources where the class path misses an error.** These are the reason the limit cannot be lowered. The shrink check is where most are: it does not see that the class of everything a storage holds covers the class of one pointee type in it.
3. **Then the passes after the first.** Their cost on blot2 is unmeasured. The validation effect lists are not merged by kind as the discovery summaries are, and will be large.
4. **Memory.** Sets are never freed; 48.5 M alternatives after one pass leaves some room, and a root per pointee type is not affordable at all (234 M alternatives a third of the way in, with the limit on typed classes lifted). The 2 GiB is `GS_STACK_RESERVE`, the address space per region. Since `707c546` the driver has upstream's `--stack-reserve size`: a compiler emitted with `goose selfhost/main.goose --target native -O2 --stack-reserve 8G -o goose.c` has 8 GiB regions (the experiments that needed room were built with the same define on the C compiler's command line). The bootstrap still builds the compiler with the default: changing that changes the seed's C, so it belongs with the next snapshot, once a second pass on blot2 shows what is needed. `LifeAlt` is 28 bytes of which `bound` is unused with class-keyed frames in use.

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

## Second frontier: the compiler as a Wasm module

The owner's test since 2026-11-16, beside blot2: compile this compiler to direct Wasm and run it. The owner's direction for it: the targets are Wasm 3.0 on V8 and Wasmtime, so 64-bit memory may be used, and a host for either engine may ship with the compiler.

**Where it stands** (evidence in `bench/results/2026-11-16/wasm-regions-locals/`; before it `wasm-memory64/` and `wasm-hosted-compiler/`):
- The compiler as a Wasm module compiles itself under all three hosts, with the native compiler's outputs: Wasmtime through the Rust host (`host/rust`) or the Python runner, and V8 through Node. `tests/test_cli_outputs.py` (`WasmMemory64`, `WasmHostedCompiler`) keeps that.
- `--wasm-memory64` builds for a 64-bit memory: address i64, slice one v128 (pointer, count), control six u64 words, element counts 64-bit. 32-bit is the default. `docs/TARGET.md` has the representations, the regions and the host interface.
- Data regions are sized from a table. Equal by default; `--wasm-region-profile FILE` weights them by what a run needed. V8 caps 64-bit memory at 16 GiB. The 32-bit module needs a profile for the compiler's own source (and the 64-bit one did until `a787c63`):

  ```sh
  goose selfhost/main.goose --stdlib stdlib --target wasm-direct -O2 --wasm-memory64 --wasm-region-stats --wasm-max-pages 4194304 -o stats.wasm
  GOOSE_REGION_PROFILE=goose.profile host/rust/target/release/goose-wasmtime stats.wasm --cache stats.cwasm -- selfhost/main.goose --stdlib stdlib --check
  goose selfhost/main.goose --stdlib stdlib --target wasm-direct -O2 --wasm-memory64 --wasm-max-pages 262144 --wasm-region-profile goose.profile -o goose-v8.wasm
  node scripts/run_wasm.mjs goose-v8.wasm -- selfhost/main.goose --stdlib stdlib --check
  ```
- Since `a787c63` the 64-bit module needs no profile for its own source under V8 (check 15 s, self-compile 28 s to its own bytes): the lifetime pass's largest table went from 176 MB to under an equal share. The 32-bit module still needs one (a profile of a self-compile: 103 regions, 466 MB).
- A host appends to a byte array through the exported `goose.reserve`; it knows nothing of regions.
- `wb_reuse_locals` (`selfhost/wasm.goose`) gives temporaries with disjoint spans one local index. It runs on every function body.
- Qualification has a `conformance-memory64` stage with its own gap record, `tests/conformance/known-gaps-memory64.json`.
- All backend address arithmetic goes through the helpers at the top of `selfhost/codegen.goose` (`wa_*` address, `wc_*` control word, `ws_*` slice, `ww(k)` k words, `wn_limit()` count limit). New backend code must use them: a raw `wb_i32`, `0x6a` or `wb_mem(…, 0x28, …)` on an address breaks 64-bit output. Check with `bench/results/2026-11-16/wasm-memory64/tools/` (`widecheck.sh`, `wasmcheck.py`; copies with local paths are in `build/tools/`, with `abcheck.sh`, which compares two compilers' modules by what they print).
- The Rust host is built by hand (`cargo build --release` in `host/rust`); the tests use it when the binary is there and the Python runner otherwise. The conformance runner and the benchmarks still use the Python runner.

**Next, in order.**
1. **A region profile is one run's need.** It is taken by hand and a larger input can outgrow it. Ideas not tried: shipping a profile of the compiler with the compiler, a host that keeps one beside the module and retries, weights from static information. No scheme that places regions without measurements can beat the equal split in the worst case, because arrays cannot move.
2. **Speed of the module.** Under Wasmtime it is three times the native compiler (self-check 13 s against 4.4 s since `a787c63`); the host is not the reason (Rust and Python hosts take the same time). Under V8 the self-check takes 15 s. Not looked into: frames in linear memory, bounds checks.
3. **The Rust host in the harnesses**: conformance (`--host` expects the C++ host's command line), benchmarks, `scripts/qualify.py` building it. `host/wasmtime.cpp` still lacks the `os` imports.
4. **64-bit memory costs** an explicit bounds check on every access (Wasmtime: 99 ms to 123 ms on `recursive_fibonacci`, 106 ms with Spectre hardening off). Fewer accesses is the backend's side of it.
5. The pinned Node 24 was never installed here; everything V8 was measured on Node 22.

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
  - the direct Wasm rows again with `--wasm-memory64` (`tests/conformance/known-gaps-memory64.json`);
  - the native rows as three units, only when native code generation changed;
  - native checks;
  - output equivalence against the baseline;
  - unit tests.

  With a warm cache it takes about 15 minutes. It needs `.venv` for wasmtime.
- **Equivalence alone:** `tests/output_equivalence.py`. A frozen copy of `selfhost/` needs `native/` beside it, or its rows fail identically in both compilers.
- **Lifetime state:** `bench/results/2026-11-14/blot2-lifetimes/tools/instrument.py`. Its `fingerprint` mode hashes the analysis state at pass boundaries, and `fpframes` mode adds a hash every 2,000 frames on blot2. Compare two runs with `fpcompare.py`. The tools are written for an agent worktree's `build/tools/`, so adjust their absolute paths. That fingerprint hashes the effect arrays index by index, so it only compares sources that store effects the same way. Since `a787c63` (construct reads held apart) use `bench/results/2026-11-17/lifetime-compact-reads/tools/logicalfp.py` for anything that touches how entries are stored: it hashes each frame's lists in order by content, and works on sources from both sides of that commit. `prove-final.sh` there runs the self-check, the corpus, and both again with class-keyed frames forced early.
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
