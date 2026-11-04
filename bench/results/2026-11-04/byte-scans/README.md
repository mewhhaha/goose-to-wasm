# Byte scan selection and width

On November 4, 2026, nine paired warmed rounds on a shared AMD Ryzen 7 3800X measured the unchanged adapted Sieve port at 883.190 → 765.352 ms on Wasmtime, a paired 1.158× speedup (ratio MAD 0.007). V8 measured 865.667 → 745.622 ms, 1.163× (MAD 0.003). Times cover the configured iteration count, excluding preparation and startup. The separately built and previously selected native profile measured 891.264 ms in the Wasmtime rounds; the paired direct/native time ratio was 0.861 (MAD 0.006), about 14% less time for direct Wasm in this workload and machine snapshot. The reference is not a universal ceiling. [All ten workload results](../../../../docs/RUNTIME_TARGETS.md) and the [Wasmtime](final-warmed.json) and [V8](final-v8.json) reports retain samples and controls.

Byte-equality scans select the last matching index without a branch and merge two SIMD128 vectors per 32-byte group, followed by at most one 16-byte vector and the original scalar tail. Eligibility, complete span guards and debug/failed-guard behavior remain unchanged. Sieve grows from 3,482 to 3,576 bytes (2.7%); the other nine warmed guests and all ten full example modules are byte-identical to the baseline. Separately collected full-process timings do not establish a compiler-change gain. [Module analysis](module-analysis.json) records the comparison.

In separate five-pair screens, branchless selection alone gained about 13% without module growth. Adding width observed a further 2.8% on Wasmtime and 4.0% on V8; V8 improved in three of five pairs. Width alone does not establish a 5% gain. [Campaign data](campaign.json) retains the samples and tradeoffs.

## Identity and method

The selected compiler SHA-256 is `b431c62fdb28463c72a50c24fb41fa28ff71262fb515a527b9fa903e933ca8a0`; the baseline is `f76ea0f4bfa57949f5b04d42884f8316546a7eb50720b31e564afafcad9a0af8`. Both use Goose revision `2e2bedef5b980bf013cac5aaa0095bfea64e5569`. [Compiler identity](compiler-identity.json) records source patches and headers; warmed reports retain frozen source snapshots and workload inputs. The seven adapted LangArena ports and three example adapters are described in [runtime targets](../../../../docs/RUNTIME_TARGETS.md). Direct Wasm uses memory32; C-to-Wasm uses memory64.

Wasmtime is 50.0.1; V8 is 13.6.233.17-node.58 in Node 24.22.1. The warmed Wasmtime host SHA-256 is `e0468623661130c89eec4902c287c1ec971928b75469a47303c3392733c51cd3`, linked to the Python package library. The fresh-process native host SHA-256 is `e303865d7661dc5d0dad1e1719753d1101bfe7f7e16d5b1eb2e174f416fbbf28`, linked to the static Wasmtime SDK; the Python library SHA-256 is `3127ca42fe7cdd3f0a43a358e79177dcfedd46c1746329826403b9d854de6178`. Host, callbacks and I/O differ. Emscripten is 6.0.13 and GCC is 16.2.1. [Host report](host.json) records library identities and preparation.

The clean collection ran November 4 UTC, 00:14:07–00:35:38. Its six fresh cohorts comprise 550 warmed Wasmtime, 200 warmed V8, 1,600 example, 1,440 host, 315 LangArena and 960 lifecycle observations, plus 200 separate host preparations. An initial timing attempt was discarded because post-release bookkeeping overlapped its window; none of its primary rows were used. Raw records are retained. [Examples](examples.json), [LangArena](cohort.json), [host](host.json), and [lifecycle](lifecycle.json) retain their distinct boundaries; precompiled execution excludes preparation, and resident requests exclude process startup. Full-process examples use constant inputs and checked output. The build cohort has five uncached samples per cell; runtime process cells have one warmup and 15 samples.

## Qualification and reproduction

Qualification passed 76 focused commands, 978 cases, 9,573 differential executions including 7,656 native stdout comparisons, and 11,484 host replays across 1,574 unique Wasm modules. Worker qualification passed 3,001 observations derived from 3,828 aliases; 1,368 input pins passed. The full six scan checks included 34,344 engine observations, 16,924 oracle comparisons and 120 body checks. [Qualification summary](qualification-summary.json) and [campaign](campaign.json) record coverage and limitations.

Verify the retained package from the repository root:

```sh
python bench/results/2026-11-04/byte-scans/reproduction/verify.py
```

The [guide](../../../../docs/GUIDE.md) and [benchmark methods](../../../../bench/README.md) describe rebuilding and collecting fresh measurements. The earlier [strided-stores cohort](../../2026-11-03/strided-stores/README.md) remains a separate historical comparison.
