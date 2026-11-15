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

- **Seed.** The bootstrap seed is snapshot 63: seed C `28f1af08…`, profiled executable `10ade9d5…` ([snapshot 63](selfhost/results/2026-11-14/snapshot-63/README.md)). Main has the export-root commit, the nine lifetime commits of 2026-11-14, the eight of 2026-11-15 and the three class-keyed-frame commits (`bc00c87`, `0f9ec7f`, `e13cd80`) on top of it, none of which is frozen into a snapshot yet.
- **Conformance.** 10,689 of 10,793 rows pass. The 104 failures are the recorded gaps in [known-gaps.json](tests/conformance/known-gaps.json), each with its cause.
- **Upstream features.** Features added upstream since the contracts were pinned are tracked in [docs/FEATURES.md](docs/FEATURES.md).
- **The compiler checking itself.** 7.0 s, down from 24.7 s before the 2026-11-15 commits, with the same analysis state ([evidence](bench/results/2026-11-15/lifetime-walks-and-memos/README.md)). The lifetime pass is still 6.7 s of it. With every eligible call keyed by classes it takes 1.5 s, and reports 58 shrink errors that are not there: the class path is not exact enough yet to be used below its 4,096-frame limit.
- **Small programs.**
  - Snapshot 63 compiles the eleven benchmark programs in 1.04–1.06× snapshot 61's time ([campaign](bench/results/2026-11-14/compiler-throughput-63/README.md)).
  - The lifetime commits since then are within noise both times: 1.009 and 1.014 on 2026-11-14 against a null run's 1.010 (one binary timed against its own copy), and 0.990 and 0.987 on 2026-11-15 against a null run's 0.973, with the same page faults.

## Current frontier: blot2's compiler

The owner's order is to get to where this compiler compiles ../blot2's `compiler-goose` (450 modules, 120,000 lines), and to make that fast afterwards. Four things stood in the way:
1. Exported functions as lifetime roots. **Done** in `9806f0e`.
2. The lifetime pass finishing on that program. **Its first discovery pass now ends** (2026-11-15, `e13cd80`); the check as a whole does not yet. This is the work in hand.
3. A root to emit from, and 4. the C-host interface: see "After the pass finishes".

**Command.** From a copy of `compiler-goose/src`, run:

```sh
goose main.goose --stdlib <this repo>/stdlib --reachable-program --expansion-node-limit 1000000 --check
```

Parsing and type checking take about 12 s. The lifetime pass runs after that.

**What changed.** Past 4,096 frames, a call of a top-level function is checked by the *classes* of its arguments, as upstream's specializations are: one frame per key, evaluated on its own (an "island"), its effects and result mapped onto each call's roots. The [evidence page](bench/results/2026-11-15/class-keyed-frames/README.md) has the design in a dozen lines, the numbers, and everything that was tried and dropped. The code is `selfhost/checker_lifetimes.goose` from "Class-keyed frames" on, with a comment at each piece.

**Where it stands on blot2** (`6ad5fbb`, a progress build, on a 4-core 16 GiB container):
- Pass 1 ends after 50,725 frames, 45,280 of them class-keyed, in 247 s, with 57.8 M alternatives of the 79.5 M that fit. Before, it stopped at 93,000 frames with a tenth of the functions entered.
- It ends with 2,348 errors, so no second pass and no validation has run yet. 2,345 are "stored reference does not outlive the storage that receives it" at a call. blot2's patched upstream build accepted this program, so treat them as this analysis's imprecision until shown otherwise.
- Plain upstream `d92c4315` on the same copy: stopped at 1,500 s, nothing printed.

**Small programs are untouched, and that is checked.** The corpus's largest program makes 720 frames and the self-check 2,436. Every commit so far keeps the state fingerprints of all 4,355 conformance sources and of the self-check (`fpcompare.py`, see Commands). Keep it so: anything new goes behind `l.class_frames > 0` or an island test.

**Next, in order.**
1. **The store errors.** Start from one: `tools/dbgstore.py` in the evidence directory prints, for a refused store, the callee's alternatives and what the call made of them (its patterns need refreshing against the current source). The largest known cause is `LifeFrame.class_stored`: everything a body stores through any class root is read back through every class root of the frame. Make it per pair instead: keep what was stored through each class root with that root, and at a read add only the stores of classes the call says may be the same storage (query 4 answered from the call's sets for storage classes too, which is now always "may alias"). The same answer will remove most of the 58 shrink errors the self-check gets with every call class-keyed.
2. **Then the passes after the first.** Their cost on blot2 is unmeasured. The validation effect lists are not merged by kind as the discovery summaries now are, and will be large.
3. **Then the 33 corpus sources where the class path misses an error** (build with the limit at 0: `tools/mkcls.sh`), before the limit is lowered for any program that matters.
4. **Memory.** Sets are never freed; 57.8 M alternatives after one pass leaves little room. Mapped sets are most of them.

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
