# Continue here

The current frontier is getting Blot2 through lifetime checking with upstream's behavior. The standing rules are in [AGENTS.md](AGENTS.md).

## Start here

1. Reproduce the first discovery pass on Blot2 `6ad5fbb` from a clean copy. The latest run reduced CPU time from 298–308 s to 122–124 s and ended with the same 38 lifetime errors. Later passes and native emission still need to run. [Evidence](bench/results/2026-11-17/blot2-captured-reads/README.md)
2. Reduce one rejected store to a small program and check it with plain upstream Goose `d92c4315`. Keep a nearby invalid case and exercise both with classes forced early. Compare the forced-class corpus before and after. The default corpus rarely reaches the class path.
3. Keep the default threshold at 4,096 frames while the class path accepts known invalid programs. The faster self-check at frame 64 changes two contract verdicts. Resolving those verdicts against upstream comes before adopting that threshold.

Build the current sources using the commands below. The checked-in seed is snapshot 63.

The class path now checks a replayed assignment to a slice variable and tracks its new backing storage. This restored 14 rejection verdicts confirmed with plain upstream across 4,355 forced-class checks. The default Blot2 run still ends with the same 38 errors. [Evidence](bench/results/2026-11-17/class-slice-slots/README.md)

The remaining speed leads are `life_effect` from construct reads after materialization (24% of the failed Blot2 run), type containment (15%) and set building and mapping (11%). The self-check's per-frame read table also reserves 5.4 M slots for 988 k entries. Reprofile after a successful Blot2 check because later passes add work.

## Rules in force

- **The owner's order (2026-11-15): match upstream Goose in functionality, get to where this compiler can compile blot2, and only then work on compiling it faster.** Plain upstream is the reference; blot2 builds its Goose port with `aardappel/goose` at `d92c4315`, unpatched.
- Push qualified batches straight to `origin/main`, with no pull request, and check the remote head with `git ls-remote origin main`. The owner said it again on 2026-11-15: merge everything straight to main.
- For a performance change, pass `--baseline` to `scripts/qualify.py` and require `equivalence/report.json` to have an empty `differing` array. Qualification reports differences separately from its exit status. For the lifetime pass, also compare the relevant analysis state (see Commands). Use `os.wait4` for each run's time and peak RSS.
- A change made to match upstream, such as keying the lifetime pass's frames by argument classes, changes what is analyzed, so the state comparison does not apply to it. The contracts carry it instead, together with the diagnostics of every conformance source against the previous compiler's (`fpcompare.py` compares them).
- Keep rejected experiments and their tradeoffs in the dated evidence. Keep the README's benchmark text and charts in step with that evidence.
- The C++ reference compiler has been removed, so all work is on the Goose compiler. Upstream Goose is the reference, used read-only.
- ../blot2 is a workload; don't edit it. Copy its sources before measuring, because its checkout keeps moving.

## Where it stands

- **Seed.** Snapshot 63 records seed C `28f1af08…` and profiled executable `10ade9d5…`. Bootstrap from that seed to use the newer compiler and Wasm host changes on main. [Snapshot 63](selfhost/results/2026-11-14/snapshot-63/README.md)
- **Conformance.** 10,689 of 10,793 rows pass. The 104 failures are the recorded gaps in [known-gaps.json](tests/conformance/known-gaps.json), each with its cause.
- **Upstream features.** Features added upstream since the contracts were pinned are tracked in [docs/FEATURES.md](docs/FEATURES.md).
- **The compiler checking itself.** 0.34 of the CPU time of `ddbbe23` since `a787c63` (2026-11-17: 11.5 s to 3.9 s in one run, peak RSS 503 to 306 MiB), in two deliveries that day: [read memos](bench/results/2026-11-17/lifetime-read-memos/README.md) (0.59) and [validation shortcuts and 32-byte reads](bench/results/2026-11-17/lifetime-compact-reads/README.md) (0.64 of that). Before them: 7.0 s from 24.7 s on 2026-11-15 ([evidence](bench/results/2026-11-15/lifetime-walks-and-memos/README.md)). Each time every frame's effects were the same. While no frame is class-keyed, a summary holds a construct read as a `LifeReadEntry` (leaf, last leaf taken, walk stamp, the chain it was sent up) found through a per-frame table; `life_reads_materialize` turns them into ordinary entries at the first class-keyed frame. The lifetime pass is still 80% of a self-check, but its profile is flat: nothing above 6% but evaluating bodies. blot2 got nothing from this (3 to 6% longer, cause not established). Then `ff912cd` answered `life_reads` for captured bindings body by body (`life_reads_captured`, `LifeBody.named`), which was 58% of blot2's check: 298–308 s to 122–124 s of CPU, same state and diagnostics ([evidence](bench/results/2026-11-17/blot2-captured-reads/README.md)). blot2's profile now: `life_effect` from construct reads 24% (past 4,096 frames reads are ordinary entries again; holding them by leaf for class-keyed frames is the next step), type containment 15%, set building and mapping 11%. With every eligible call keyed by classes it takes a third of the time and, since `f4d1d02`, reports no false error (58 before). The class path still misses 33 errors in the corpus, so it is not used below its 4,096-frame limit; with the limit at 64, two conformance sources change verdict (`stdlib_regex` accepted, `render_walks_around_overloads` rejected) and the self-check takes under half the time.
- **Small programs.**
  - Snapshot 63 compiles the eleven benchmark programs in 1.04–1.06× snapshot 61's time ([campaign](bench/results/2026-11-14/compiler-throughput-63/README.md)).
  - The lifetime commits since then are within noise both times: 1.009 and 1.014 on 2026-11-14 against a null run's 1.010 (one binary timed against its own copy), and 0.990 and 0.987 on 2026-11-15 against a null run's 0.973, with the same page faults.

## Current frontier: blot2's compiler

The owner's order is to get to where this compiler compiles ../blot2's `compiler-goose` (450 modules, 120,000 lines), and to make that fast afterwards. Four things stood in the way:
1. Exported functions as lifetime roots. **Done** in `9806f0e`.
2. The lifetime pass finishing on that program. **Its first discovery pass ends** (since 2026-11-15, `e13cd80`); the check as a whole does not yet. This is the work in hand.
3. A root to emit from and the C host interface. See [After lifetime checking succeeds](#after-lifetime-checking-succeeds).

**Reproduce.** From the Goose-to-Wasm root, with the development compiler built as below:

```sh
repo=$PWD
workload=$(mktemp -d "$repo/build/blot2-6ad5fbb.XXXXXX")
git -C ../blot2 archive 6ad5fbb -- compiler-goose/src | tar -x -C "$workload"
cd "$workload/compiler-goose/src"
"$repo/build/dev-X/bin/goose" main.goose --stdlib "$repo/stdlib" \
  --reachable-program --expansion-node-limit 1000000 --check
```

Keep the workload revision with the result. A new copy of the sibling checkout is a separate workload. The earlier profile put parsing and type checking at about 12 s before lifetime analysis.

**What changed.** Past 4,096 frames, a call of a top-level function is checked by the *classes* of its arguments, as upstream's specializations are: one frame per key, evaluated on its own (an "island"), its effects and result mapped onto each call's roots. Two evidence pages hold the design, the numbers and everything tried and dropped: [the path itself](bench/results/2026-11-15/class-keyed-frames/README.md) (2026-11-15) and [stores per pair of classes](bench/results/2026-11-16/class-stores-per-pair/README.md) (2026-11-16). The code is `selfhost/checker_lifetimes.goose` from "Class-keyed frames" on, with a comment at each piece.

**Where it stands on Blot2 `6ad5fbb`.**
- Pass 1 ends after 52,877 frames: 256 s on that build, about 120 s since `ff912cd`, with 49.3 M alternatives of the 79.5 M that fit and a peak RSS of 7.1 GiB.
- It ends with 38 "stored reference does not outlive the storage that receives it" errors at calls. The trace found 237 distinct call sites where replay first paired a value with a shallower destination. The patched upstream build accepted an earlier Blot2 revision. Use a reduced program and plain upstream to establish whether a rejection on this revision is wrong.
- Plain upstream `d92c4315` on the same copy: stopped at 1,500 s, nothing printed.

**Compare specific verdicts and store origins.** Moving a deferred store changes which callers report it, so the top-level count can move in either direction. Use the forced-class self-check and corpus to catch changes. Compare each changed verdict with upstream. [Earlier differences](bench/results/2026-11-16/class-stores-per-pair/runs/corpus-every-call-class-keyed-categories-c72e198.json)

**Exercise both paths.** The earlier corpus's largest program made 720 frames and the self-check 2,436. Compare the default-path diagnostics and output, and force classes in separate builds to check class behavior. `ClassLifetimeChecks` in `tests/test_cli_outputs.py` also exercises the normal threshold using 4,200 distinct roots.

**Next, in order.**
1. **Follow one replay to its producer.** The fresh trace puts 195 of 237 newly deferred pairs in `check/check.goose`. Start with `importedBinding` at `1643:520`. The input summary names the same untyped storage class for the place and one source. Find the actual store before pruning the pair: removing all such exact alternatives previously accepted invalid programs. Compare `ApplyCalleeStores`, `FitsAt`, `ShrinkTargets` and `RecordStore` at upstream `d92c4315`. [Fresh trace](bench/results/2026-11-17/class-slice-slots/README.md#blot2) · [Earlier experiments](bench/results/2026-11-16/class-stores-per-pair/README.md)
2. **Resolve the remaining forced-class differences.** Upstream rejects 18 of the 19 remaining cases that the forced path accepts and the default path rejects. `stdlib_regex` is the exception and should pass. For the new mixed-depth slice case, preserve each callee source through mapping. Checking every resulting root separately would reject the valid caller-side case. [Paired controls](bench/results/2026-11-17/class-slice-slots/README.md#remaining-slice-case)
3. **Then the passes after the first.** Their cost on blot2 is unmeasured. The validation effect lists are not merged by kind as the discovery summaries are, and will be large.
4. **Memory.** The first pass holds about 49 M alternatives. Lifting the typed-class cap reached 234 M a third of the way through a prior experiment. If later passes hit the 2 GiB per-region `GS_STACK_RESERVE`, use `--stack-reserve 8G` when emitting a development compiler and record the memory needed before changing the seed.

**Done on 2026-11-16, for the record of what not to redo.** A read-out reference's value no longer carries its candidates (`d26f33c`): they are a mask on the storage class, asked for by the alias rules and by a store or shrink through the reference. Dropping them outright loses upstream's `store_reached_table` and `construct_use_bound_holder_ref`; stripping them from stored values loses `shrink_class_copy_kept_own`. A fold of many typed classes into the untyped one loses `emptied_callee_shrink_first`. All four are on the page.

**Trace helpers.** The [class-store tools](bench/results/2026-11-16/class-stores-per-pair/tools/) record the original experiments. `dbgstore2.py` shows refused stores, `dbgdefer.py` records the first inversion per call site, and `dbgwatch.py` follows a selected pair. Update their source anchors on an isolated copy as the checker changes. Check that the instrumented compiler reproduces the uninstrumented diagnostics before following a trace.

**Known gaps of the class path**, all listed with their cause on the evidence page: stores through storage only known to outlive a class root; a callee's shrink against values the callee cannot tell apart; `index_of` and slice-pool checks through class roots.

**Reference points on the earlier copy** (`93c8fa8`, 2026-11-14, on the owner's machine).
- Upstream with blot2's patches 01–11 stops after 66 s, at its first lifetime error. Upstream stops at the first error it meets; this pass reports errors only after a whole discovery pass.
- blot2's own build, patches 01–29, checks it without errors in 435 s, with a peak RSS of 17.9 GiB. That build includes the precision patches.
- blot2 kept its patches in `compiler-goose/tools/upstream-32a4f44/`; they left its checkout on 2026-11-14 but are in its history at `93c8fa8`. blot2 has since parked this port and builds with plain upstream.

**The old path's limits**, for the record: [what stopped it and why](bench/results/2026-11-15/lifetime-walks-and-memos/README.md) (a frame per set of concrete roots; 18 functions held 36,700 of 90,000 frames).

### After lifetime checking succeeds

- **Precision patches 12–17.** These patches make upstream accept code it otherwise rejects, so adopting any of them is the owner's decision. Expect the first error that patches 01–11 report: `reuse/code_expectation.goose:40`, "returning a reference rooted in n, which dies with this function (§9.2)".
- **A root to emit from.** `--target native` needs `fn main()`. `--library` instead type checks every function, and on blot2 it reports 135 errors in code nothing reaches. The fix is either a `main` that calls `blot_main::mainEntry()`, or a `--library` that is limited to what `--reachable-program` reaches.
- **The C host.** Blot2's build uses `--emit-runtime` and `--header`. Its native entry calls `goose_init(argc, argv)` and `blot_goose_main()`. `gs_runtime_observer_install` is a weak symbol for allocation telemetry.

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
- Build the Rust host with `cargo build --release` in `host/rust`. The hosted compiler tests use it when available. Conformance uses the Python runner for memory64 unless given `--host`. The legacy C++ host can still run 32-bit rows.

**Next, in order.**
1. **Region sizing.** Record which region fills on the intended workload before adjusting weights. A profile shifts capacity between regions and a larger input can outgrow it. Retry experiments belong on checks where the guest has no external side effects.
2. **Speed of the module.** Under Wasmtime it is three times the native compiler (self-check 13 s against 4.4 s since `a787c63`); the host is not the reason (Rust and Python hosts take the same time). Under V8 the self-check takes 15 s. Not looked into: frames in linear memory, bounds checks.
3. **The Rust host in the harnesses**: conformance (`--host` expects the C++ host's command line), benchmarks, `scripts/qualify.py` building it. `host/wasmtime.cpp` still lacks the `os` imports.
4. **64-bit memory cost.** On the recorded Wasmtime setup, `recursive_fibonacci` took 99 ms with 32-bit memory and 123 ms with 64-bit memory. The diagnostic run with Spectre hardening off took 106 ms. Measure other workloads with the same engine configuration before generalizing.
5. The published V8 runs used Node 22. Record the actual Node and V8 versions for new runs.

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
- **Lifetime state.** Apply [`logicalfp.py`](bench/results/2026-11-17/lifetime-compact-reads/tools/logicalfp.py) to separate baseline and candidate source copies. `fingerprint` hashes ordered effects at pass boundaries and `fpframes` adds samples every 2,000 frames. Build each copy with `scripts/bootstrap.py --source-dir ... --jobs 8` and compare on the same workload. For an early-class comparison, set `LIFE_CONCRETE_FRAMES` in each copy before building. The dated shell scripts record the original runs and refer to cloud-local paths, executables and helpers from several runs.
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
