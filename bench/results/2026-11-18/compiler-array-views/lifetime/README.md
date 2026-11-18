# Caching reads through exact local storage

On the frozen compiler project, the lifetime checker examined **981,237 candidate references**, down from **4,345,925**. A diagnostic compiler recomputed all 114,857 cached answers and got the same interned set ID every time. The adaptive table reached 8,192 entries, or 384 KiB of entry storage. It starts with 16 entries and grows on misses, up to 16,384. [Counters and compiler identities](counts.json) · [Diagnostic instrumentation](instrument.py)

| Independent screen on default memory64 | Check instructions, billions | Emit instructions, billions | Check CPU, s | Emit CPU, s |
| --- | ---: | ---: | ---: | ---: |
| Exact local reads, adaptive table | 52.41 → 48.44 | 77.43 → 73.46 | 6.24 → 5.66 | 8.76 → 8.82 |
| Exact local reads, fixed 4,096 entries | 52.41 → 48.34 | 77.43 → 73.35 | 5.85 → 5.41 | 8.23 → 8.01 |
| Inline type containment, one bit row per queried owner | 52.41 → 51.36 | 77.43 → 76.38 | 5.77 → 5.61 | 8.09 → 8.31 |
| Last interned singleton list per root | 52.41 → 51.66 | 77.43 → 76.67 | 6.50 → 6.31 | 9.01 → 8.60 |

Each row used its own two alternating pairs on CPU 2, Wasmtime 50.0.1, compiler sources `ac55de2`, and frozen project `90e086f`. CPU time includes instantiation. The runs overlapped other jobs on a shared workstation, with substantial descheduling in the later pairs. Every emission matched the same 17,322,012-byte native reference. The adaptive read cache reduced instructions by 7.6% for checking and 5.1% for emission. [Adaptive pairs](adaptive-pairs.json) · [Fixed pairs](fixed-4096-pairs.json) · [Containment pairs](containment-pairs.json) · [Singleton pairs](singleton-list-pairs.json)

Three alternating native pairs on CPU 2 with Clang 23.1.5, eight C units and `-O2` reduced check instructions from 19.51 to 17.96 billion (7.9%) and emission from 29.38 to 27.83 billion (5.3%). Median CPU time went from 2.41 to 2.39 s checking and 3.59 to 3.37 s emitting. The third pair ran under heavier contention. [Native pairs](adaptive-native-pairs.json) · [Native build](native-build.json)

The adaptive version reserves 768 bytes on its first eligible read. The fixed version reserves 192 KiB immediately. The containment trial computed the transitive inline-storage graph once per requested owner and indexed canonical pointee types in a bitset. It retained the pairwise walker above 8,192 types and while types were changing. The singleton trial kept one i32 in every root to avoid rebuilding a single-entry list with the same alternative. These last two trials made smaller differences in instructions. The batch uses the adaptive read cache. [Adaptive patch](adaptive.patch) · [Fixed patch](fixed-4096.patch) · [Containment patch](containment.patch) · [Singleton patch](singleton-list.patch)

## When an answer can be reused

A read qualifies after type synthesis ends, when exactly one alternative names an exact place owned by a positive frame, the requested pointee exists, and no class-keyed frame has been created. Pool-relative references return earlier. The lookup checks the complete place-set ID, requested type, current frame, stored contents-set ID and the revision of the current frame’s parameter references.

- A root receives its frame, type and depth at construction. Published sets keep the same alternatives. A change in the root’s stored references replaces its contents-set ID. The read consults the root’s accumulated contents during both discovery and validation.
- A newly created parameter cell has the empty reference set. It cannot make the queried root reachable or add a candidate. Every later write to a cell’s reference set goes through `life_set_refs`, which advances the owning frame’s parameter revision when that cell is a parameter.
- A singleton root with a positive owner frame cannot be global. Ordinary globals that occur inside its contents contribute their fixed root types and alternative flags. The synthetic root for folded globals is created only after the first class-keyed frame. The class-frame count only grows, so the local cache is inaccessible from that point on.
- An index collision, frame change, contents change or parameter revision change takes the full readback path. The type and full place-set checks keep distinct pointees and projections separate.

## State verification

The probes fingerprint roots, cell contents, frame results, summary and validation effects, and ordered exits at discovery and validation boundaries. The two compilers matched 11,596 fingerprint lines, exit status, stdout and diagnostics across 4,357 corpus sources. Seven more matching fingerprints covered five discovery passes and validation in the compiler self-check. A second fixture lowered the ordinary-frame threshold to 64 to exercise the transition to class-keyed checking and produced 96 exits. [Probe results](state.json) · [Per-source comparisons](corpus.json.gz)

## Reproduction

Make separate copies of `selfhost`, `stdlib` and `native` from compiler commit `ac55de2` and apply one patch per copy with `patch -p1`. Emit each compiler using the native executable identified in the counter report and `selfhost/main.goose --stdlib stdlib --target wasm-direct -O2 --wasm-memory64 --wasm-max-pages 262144`. Prepare the frozen `90e086f` stage with `bench/selfhost_comparison.py`, then run the prepared-module comparison on CPU 2 for two alternating rounds of checking and emission. Supply an expected-output override for each case using the native baseline’s emission on the frozen project. Set a 256 MiB stack limit for native compiler runs. [Paired runner](../../compiler-record-access/tools/compare.py)

For operation counts, run `instrument.py SOURCE MODE` on separate copies before building. Use mode `baseline` on the unmodified compiler and modes `adaptive` and `shadow` on the adaptive copy. Run the resulting modules on the frozen project with Node’s `--stack-size=65500`, `scripts/run_wasm.mjs`, and guest arguments `selfhost/main.goose --stdlib stdlib --check`. Shadow mode runs the full computation before returning every cached answer, compares the set ID, and leaves cache writes on exactly the same misses as the normal candidate. The count of alternatives measures the iterations of the inner readback filter. List-intern counts cover the entire analysis.

To reproduce the state comparison, apply the logical fingerprint helper and ordered-exit extension to independent baseline and adaptive source copies. Build both native probes for the corpus and both memory64 probes for the compiler self-check. Build another pair with `LIFE_CONCRETE_FRAMES` reduced from 4,096 to 64 for the exit fixture. [Fingerprint helper](../../../2026-11-17/lifetime-compact-reads/tools/logicalfp.py) · [Ordered-exit extension](../../lifetime-exit-index/tools/exitfp.py) · [Corpus comparison](../../../2026-11-17/lifetime-compact-reads/tools/fpcompare.py) · [Exit fixture](class-exits.goose)
