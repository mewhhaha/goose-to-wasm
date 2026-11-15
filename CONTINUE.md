# Continue here

Where the work stands on 2026-11-15 and how to pick it up. The standing rules are in [AGENTS.md](AGENTS.md).

## Rules in force

- Push qualified batches straight to `origin/main`, with no pull request, and check the remote head with `git ls-remote origin main`.
- A performance change keeps every output byte-identical. `scripts/qualify.py` proves this against a compiler built from the previous sources. For the lifetime pass, also compare the analysis state (see Commands).
- Keep rejected experiments and their tradeoffs in the dated evidence. Keep the README's benchmark text and charts in step with that evidence.
- The C++ reference compiler has been removed, so all work is on the Goose compiler. Upstream Goose is the reference, used read-only.
- ../blot2 is a workload; don't edit it. Copy its sources before measuring, because its checkout keeps moving.

## Where it stands

- **Seed.** The bootstrap seed is snapshot 63: seed C `28f1af08…`, profiled executable `10ade9d5…` ([snapshot 63](selfhost/results/2026-11-14/snapshot-63/README.md)). Main has the export-root commit, the nine lifetime commits of 2026-11-14 and the eight of 2026-11-15 on top of it, none of which is frozen into a snapshot yet.
- **Conformance.** 10,689 of 10,793 rows pass. The 104 failures are the recorded gaps in [known-gaps.json](tests/conformance/known-gaps.json), each with its cause.
- **Upstream features.** Features added upstream since the contracts were pinned are tracked in [docs/FEATURES.md](docs/FEATURES.md).
- **The compiler checking itself.** 7.0 s, down from 24.7 s before the 2026-11-15 commits, with the same analysis state ([evidence](bench/results/2026-11-15/lifetime-walks-and-memos/README.md)). The lifetime pass is still 6.7 s of it.
- **Small programs.**
  - Snapshot 63 compiles the eleven benchmark programs in 1.04–1.06× snapshot 61's time ([campaign](bench/results/2026-11-14/compiler-throughput-63/README.md)).
  - The lifetime commits since then are within noise both times: 1.009 and 1.014 on 2026-11-14 against a null run's 1.010 (one binary timed against its own copy), and 0.990 and 0.987 on 2026-11-15 against a null run's 0.973, with the same page faults.

## Current frontier: blot2's compiler

The owner asked (2026-11-14) for two of the four things that stand between this compiler and ../blot2's `compiler-goose` (450 modules, 120,000 lines):
1. Exported functions as lifetime roots. **Done** in `9806f0e`. blot2's only entry is `export "blot_goose_main" fn mainEntry()`, so before this commit the lifetime pass skipped the whole program.
2. The lifetime pass finishing on that program. **Not done, and making the present pass faster or smaller will not do it** (measured 2026-11-15, below).

**Command.** From a copy of `compiler-goose/src`, run:

```sh
goose main.goose --stdlib <this repo>/stdlib --reachable-program --expansion-node-limit 1000000 --check
```

Parsing and type checking take about 12 s. The lifetime pass runs after that.

**Where it stops.** In discovery pass 1, at 93,000 call contexts (frames), with `goose runtime error: data stack overflow`: the alternatives' 2 GiB region is full, 77.9 M alternatives where 79.5 M fit. The eight commits of 2026-11-15 get it there in 102 s instead of 605 s on the same machine, with the same state at every point compared, but they make no fewer alternatives, so it stops at the same place. [Evidence, profiles and rejected ideas](bench/results/2026-11-15/lifetime-walks-and-memos/README.md) · [2026-11-14](bench/results/2026-11-14/blot2-lifetimes/README.md)

**How far that is.** At the stop the pass has entered 2,854 of the program's 27,923 reached functions, about a tenth, at 33 frames per function entered. An exploration build with 16 GiB regions went on to 168,000 frames before it was stopped at 12 GiB resident, and those 75,000 further frames entered 91 more functions. Pass 1 has not ended; later passes revisit every frame and validation follows.

**Why.** A frame is made for every set of *concrete* argument roots a function is called with. Two things multiply them in blot2:
- Each level of a recursive tree walker (`pattern` and `bindPattern`, `coreCaptures` and `corePattern`) has its own locals, and everything they are passed to gets a frame per level and per context the recursion is entered from. At 90,000 frames, 18 functions held 36,700 of them.
- A reference read out of a container may point into any of about 2,600 globals, bounded by the container's depth. Each depth is another 2,601-alternative set and another frame of each callee.

Upstream keys a specialization by the *class* of each argument's root, its outlives rank among the call's arguments plus a few flags (`GetOrCreateSpec` in `typecheck_calls.h`, `RootArg` in `ast.h`, at `32a4f44`), checks the body once per key against class roots, and maps the record onto each call's arguments. This pass has upstream's rules but not that key: it looks for a class-equal frame only among the active ones, to find recursion.

**The decision this needs.** Finishing blot2 takes frames keyed by argument classes, with a callee's summary mapped onto each caller's roots. That is a redesign of `checker_lifetimes.goose`, and it changes which contexts are analyzed: the state comparison used for every lifetime commit so far cannot hold, so the contracts (10,793 rows, 560 of them upstream-differential) would carry the equivalence instead. It is the owner's call, like the precision patches below.

**If the present pass is pushed further anyway,** memory is what stops it, and time no longer is:
- **Reclaim unreachable lists.** Worth about 2.3× in alternatives. Set IDs live in locals throughout an evaluation, so the safe points are activation exits, and each one needs a scan of all persistent state.
- **Fewer summary merges.** They made 29% of all alternatives; an entry's every size is a separate list.
- **Pack effects and summaries** into 32-bit fields (153 and 108 bytes each now; 5.8 M of each at the stop).
- **A larger region for the compiler itself.** `-DGS_STACK_RESERVE` on the compiler's own C changes only that binary; the runtime text it emits for programs keeps the default. Real memory then decides: 7.5 GiB resident at the stop, 12 GiB at 168,000 frames.

**Where the time is now.**
- blot2, 102 s to the stop: building sets and finding that they exist 34%, read-backs through local containers 10%, `life_effect` 9%.
- The self-check, 7.0 s: `life_effect` 54%, nearly all of it the first replay of each summary entry into each new activation. Passes four and five change almost nothing and cost as much as the third: every pass evaluates every frame again.

**Reference points on the same copy** (2026-11-14, on the owner's machine).
- Plain upstream `32a4f44` doesn't finish within 1,200 s either.
- Upstream with blot2's patches 01–11 stops after 66 s, at its first lifetime error. Upstream stops at the first error it meets; this pass reports errors only after a whole discovery pass.
- blot2's own build, patches 01–29, checks it without errors in 435 s, with a peak RSS of 17.9 GiB. That build includes the precision patches, which cut work this analysis has to do.
- The builds are in `../blot2/build/goose-port/upstream-32a4f44/`. blot2 kept its patches in `compiler-goose/tools/upstream-32a4f44/`; they left its checkout on 2026-11-14 but are in its history at `93c8fa8`.

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
