# Can a scheduler skip repeat lifetime checks?

The shadow predictor found **19 ms** of potentially avoidable work on the frozen Wasmtime rebuild before bookkeeping and replacement replay. The experiment needed **200 ms net** to proceed. A structural audit also found **four programs** where a predicted skip would have dropped a change to checker state. Every run still executed the entire checker. [Paired samples](frozen-timings.json) · [Output and tool hashes](verification.json)

## Where the time went

The three repeat discovery passes took **418 ms** in the control. Discovery grows the set of possible references and effects until the checker can validate the program. The probe predicted a skip when the same activation had the same caller, call site, context and destination and had left the tracked state unchanged in the previous round. After each evaluation it checked live-binding changes outside the activation, descendant frame assignments, recursion, new arena entries, revisions, effects and the result. Nested body timings were counted once. [Probe](tools/probe.py)

| Repeat discovery passes | Median time |
| --- | ---: |
| All pass work in the control | 417.8 ms |
| All bodies with no observed ordered changes to preserve, allowing free replay of other changes | 29.8 ms |
| Predicted skips that passed the timed state checks | 19.2 ms |

The hindsight estimate assumes advance knowledge and free replay of summaries. It describes this screen's opportunity. A design that records and reapplies ordered binding changes could reach a different set of bodies. The timed probe added a median **10.4 ms** to the three passes in paired runs. Layout and shared-host variation contribute to this difference, so the timings leave bookkeeping and replay costs unresolved. The gross estimate already misses the target.

A separate validation probe measured **19.1 ms** for 26,963 capture snapshots and **71.2 ms** for 24,046 effect replays. This attribution includes timer calls. Together those paths accounted for about **90 ms** in the instrumented run, below the 120 ms threshold the review proposed for a dedicated replay optimization. The next experiment can count how many syntax nodes the lifetime evaluator visits without doing reference work. That would size the opportunity for a compact representation used in every pass. [Validation samples](frozen-timings.json)

## Structural audit

The timed screen reported zero rejections among 1,666 predictions on the frozen rebuild. A separate audit checked a wider fingerprint before and after each predicted body, including the checker’s recorded roots, cells, frame results and exits. It matched all frozen predictions and reproduced the same emitted Wasm and pass-boundary fingerprints as the control. The existing epilogue clears the entered frame's live bits in both cases, so the audit excludes those bits. [Audit fields](tools/audit.inc) · [Frozen fingerprints and output hashes](verification.json)

| Contract corpus | Sources | Predictions | Predicted skips with changed state | Sources that reached the class path |
| --- | ---: | ---: | ---: | ---: |
| Ordinary threshold | 4,358 | 1,711 | 4 | 0 |
| Forced switch after 16 frames | 4,358 | 522 | 3 | 202 |

The forced run found three of the ordinary run’s four witnesses. The cases cover global or captured reference rebinding and fixed-payload copies. All **8,716** paired checks matched exit status, diagnostics, and recorded pass and final state because the shadow probe continued to evaluate every body. [Ordinary corpus](corpus-4096.json.gz) · [Forced corpus](corpus-16.json.gz)

## Reproducing the experiment

The compiler sources are `204ae57`, the frozen rebuild input is `9a6040a`, and the native bootstrap emitter came from `9dbeba3`. The timing probe used six rounds covering all six orders of three variants, after one warmup of each. Each used a fresh Wasmtime 50.0.1 process pinned to CPU 7 on a Ryzen 7 3800X with a primed cache. Every timed and audited frozen rebuild produced the same 7,378,033-byte portable memory64 module. The probe modules use the shared-emitter release’s layout profile and direct Wasm output. Treat the separately published **2.049 s** balanced-package rebuild as the release reference. [Release comparison](../shared-emitters/README.md#full-builds-on-a-frozen-project) · [Layout profile](../shared-emitters/training.profile)

From the repository root, set `GOOSE_EMITTER` to the pinned native emitter. The scripts default to the project's `host/rust/target/release/goose-wasmtime` runner. Override it with `WASMTIME_RUNNER` if needed.

```sh
report=bench/results/2026-11-21/lifetime-scheduler
work="$PWD/build/neon-shadow-scheduler"
mkdir -p "$work/workload" "$work/corpus-input/upstream"
cp "$report"/tools/* "$work/"
git archive 9a6040a ':(glob)selfhost/*.goose' stdlib native | tar -x -C "$work/workload"
export WORKLOAD_SOURCE="$work/workload"
bash "$work/build-probes.sh"
python3 "$work/measure.py"

git archive 204ae57 tests stdlib native examples | tar -x -C "$work/corpus-input"
tar -xf "$work/corpus-input/tests/conformance/upstream.tar.gz" -C "$work/corpus-input/upstream"
for limit in 4096 16; do
    for mode in control audit; do
        bash "$work/audit-build.sh" "$mode" "$limit"
    done
    taskset -c 1,2,3,4 python3 "$work/corpus.py" "$limit"
done
taskset -c 6 bash "$work/audit-frozen.sh"
```
