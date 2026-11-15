# Continue here

Where the work stands on 2026-11-15 and how to pick it up. The standing rules are in [AGENTS.md](AGENTS.md).

## Rules in force

- Push qualified batches straight to `origin/main`, with no pull request, and check the remote head with `git ls-remote origin main`.
- A performance change keeps every output byte-identical. `scripts/qualify.py` proves this against a compiler built from the previous sources. For the lifetime pass, also compare the analysis state (see Commands).
- Keep rejected experiments and their tradeoffs in the dated evidence. Keep the README's benchmark text and charts in step with that evidence.
- The C++ reference compiler has been removed, so all work is on the Goose compiler. Upstream Goose is the reference, used read-only.
- ../blot2 is a workload; don't edit it. Copy its sources before measuring, because its checkout keeps moving.

## Where it stands

- **Seed.** The bootstrap seed is snapshot 63: seed C `28f1af08…`, profiled executable `10ade9d5…` ([snapshot 63](selfhost/results/2026-11-14/snapshot-63/README.md)). Main has the export-root commit and the nine lifetime commits on top of it, none of which is frozen into a snapshot yet.
- **Conformance.** 10,689 of 10,793 rows pass. The 104 failures are the recorded gaps in [known-gaps.json](tests/conformance/known-gaps.json), each with its cause.
- **Upstream features.** Features added upstream since the contracts were pinned are tracked in [docs/FEATURES.md](docs/FEATURES.md).
- **Small programs.**
  - Snapshot 63 compiles the eleven benchmark programs in 1.04–1.06× snapshot 61's time ([campaign](bench/results/2026-11-14/compiler-throughput-63/README.md)).
  - The lifetime commits since then measured 1.009 and 1.014. A null run, one binary timed against its own copy, measured 1.010, so the difference is within noise.

## Current frontier: blot2's compiler

The owner asked (2026-11-14) for two of the four things that stand between this compiler and ../blot2's `compiler-goose` (450 modules, 120,000 lines):
1. Exported functions as lifetime roots. **Done** in `9806f0e`. blot2's only entry is `export "blot_goose_main" fn mainEntry()`, so before this commit the lifetime pass skipped the whole program.
2. The lifetime pass finishing on that program. **Not done.**

**Command.** From a copy of `compiler-goose/src`, run:

```sh
goose main.goose --stdlib <this repo>/stdlib --reachable-program --expansion-node-limit 1000000 --check
```

Parsing and type checking take about 12 s. The lifetime pass runs after that.

**Progress.** The nine lifetime commits on main make discovery pass 1 reach 20,000 call contexts (frames) 5–7 times sooner, and fit 1.9 times as many alternatives in memory. Every output is unchanged. The run still stops after 884 s at 93,000 frames, with `goose runtime error: data stack overflow`. At that point the alternatives' 2 GiB region is full: 77.9 M alternatives, where 79.5 M fit. Even an exploration build with 16 GiB regions had not finished pass 1 at 95,000 frames. [Evidence, profiles and rejected ideas](bench/results/2026-11-14/blot2-lifetimes/README.md)

**Where the cost is.**
- **Memory comes first.** Sets live in arenas that only grow, and more than half of the alternatives in them are garbage: at 40,000 frames, only 43% were reachable. Joins make 40% of all alternatives (summary merges alone make 29%), `life_contents` makes 17%, and the mutable globals added to loads make 13%.
- **Time.**
  - Builds: 16%.
  - `life_function`'s frame lookup: 13.6%. It searches the active chain, then every frame of the function, then every frame of the call site.
  - `life_effect` walking offers up the frame chain: 10.1%.

**Next steps, with what is known about each.**
- **Reclaim unreachable lists.** Worth about 2.3× in memory. Set IDs live in locals throughout an evaluation, so the safe points are activation exits, and each one needs a scan of all persistent state.
- **Fewer summary merges.** By 21,000 frames, 64.8 M of the 71.7 M merges were construction reads (kind 3).
- **Index `life_function`'s frame search.**
- **Port the remaining speed patches.** The evidence's "Upstream patches, mapped" table lists blot2's speed patches that have no counterpart here yet. Patches 08 and 20 matter only once validation runs.

**Reference points on the same copy.**
- Plain upstream `32a4f44` doesn't finish within 1,200 s either.
- Upstream with blot2's patches 01–11 stops after 66 s, at its first lifetime error.
- blot2's own build, patches 01–29, checks it without errors in 435 s, with a peak RSS of 17.9 GiB. That build includes the precision patches, which cut work this analysis has to do.
- The builds are in `../blot2/build/goose-port/upstream-32a4f44/`. blot2 kept its patches in `compiler-goose/tools/upstream-32a4f44/`, but they left its checkout on 2026-11-14.

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
  - the capture and global read summaries, which are computed per function rather than per shared callee;
  - `mark_located_functions`;
  - name lookups that rehash a token's text.
- **The 104 conformance gaps.**
- **Unsupported upstream features**, the `no` and `partial` rows in docs/FEATURES.md. Examples: upstream's newer `checkfree` rule, native packages, and the package build sidecars.

## Commands

- **Development compiler** (eight C units, no profile): `python3 scripts/bootstrap.py --build-dir build/dev-X --source-dir . --jobs 8 --cache-dir build/qualify-cache/bootstrap`.
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
- **Compiler speed:** `bench/compare_compilers.py --samples 31 --cpu N --seed S`, with charts from `bench/compiler_comparison_charts.py`. Also run a null comparison, of one binary against its own copy, to see the noise.
- **Freezing a snapshot:** the protocol is in the snapshot 63 README. The profile is trained on the self-compile plus the `leaf-properties` and `flow-prefilter` fixtures at weight 64, with Clang 23, and both public roots must verify. The script that ran it, `build/redeliver63.sh`, is local and untracked.
- **Profiling:** this host has no `perf` or `strace`. Use an `LD_PRELOAD` sampler (`build/perf-dce/prof.c`, local) and `--wasm-stats FILE`, which reports phase times, node counts and function names.

## Gotchas

- **The machine is shared**, often at load 10–18 on 16 threads. Only interleaved or side-by-side runs give usable ratios, and they should be read against a null run.
- **Check small programs after a large-program speedup.** Time an empty `fn main() {}` with `--check` and count its page faults. A constant-size table can cost a small program more than its whole check, which is how snapshot 62 got 1.36× slower.
- **Close stdin for stages that run Node or wasmtime**, or they wait on it. `qualify.py` already does this.
- **blot2 needs `--expansion-node-limit 1000000`**, the same limit blot2's build uses.
