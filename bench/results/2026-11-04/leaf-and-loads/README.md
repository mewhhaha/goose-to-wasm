# Leaf calls and byte loads

On November 4, 2026, nine paired warmed rounds on a shared AMD Ryzen 7 3800X measured Quicksort at 1,838.300 → 1,499.301 ms on Wasmtime, a paired 1.23× improvement (ratio MAD 0.044). Custom hash measured 354.228 → 280.279 ms, 1.25× (MAD 0.004). V8 paired ratios were 1.008× and 0.997× respectively, essentially flat at this scale. Times cover the configured iteration count, excluding preparation and startup. [Wasmtime](final-warmed.json) and [V8](final-v8.json) reports retain the samples; [runtime targets](../../../../docs/RUNTIME_TARGETS.md) include the other workloads and separately built references.

The direct emitter expands bounded straight-line void leaf calls in eligible recursive callers, snapshotting arguments before binding them. The width-eight byte recurrence uses one eight-byte load unpacked into two u32 vectors. Existing frontend stack-provenance guards remain in force. Quicksort grows from 4,356 to 4,480 bytes; custom hash shrinks from 6,611 to 6,598. The other eight warmed modules and all ten full example modules are byte-identical to the baseline. The separate process cohort does not establish a full-example code-generation speedup. [Module analysis](module-analysis.json) records the comparisons.

An isolated wide-load screen showed roughly 1% slower V8 custom hash; that exploratory result is distinct from the final paired cohort. Guarded SIMD sentinel scans and tail-recursion work remain open. [Campaign data](campaign.json) records the screens, eligibility and tradeoffs.

## Identity and method

The selected compiler SHA-256 is `8c09c1a6bcc782de5b86dda621a91ae234acba8fbe108d146582113eb6a110b6`; the baseline is `b431c62fdb28463c72a50c24fb41fa28ff71262fb515a527b9fa903e933ca8a0`. Both use Goose revision `2e2bedef5b980bf013cac5aaa0095bfea64e5569`. [Compiler identity](compiler-identity.json) records 37 headers and two patches. Direct Wasm uses memory32; C-to-Wasm uses memory64. Wasmtime is 50.0.1; V8 is 13.6.233.17-node.58 in Node 24.22.1. Emscripten is 6.0.13 and GCC is 16.2.1. The warmed cohort uses a native host dynamically linked to the Python Wasmtime library; the process and lifecycle cohorts use a separately built native host statically linked to the SDK. Both use Wasmtime 50.0.1. The [warmed](final-warmed.json) and [host](host.json) reports record their identities.

Six fresh cohorts provide 5,065 observations plus 200 separate host preparations. Warmed comparisons use nine paired rounds; fresh-process cells use 15 samples and one warmup; cold builds use five samples per cell. Precompiled execution excludes preparation, and resident requests exclude process startup. [Examples](examples.json), [LangArena](cohort.json), [host](host.json), and [lifecycle](lifecycle.json) retain their separate boundaries. Previously selected Wasm and native references were built separately and executed again in the paired warmed rounds.

The original coordinator exited with status 143 after four cohorts had passed; the cause is unconfirmed. Its LangArena report had 315 rows but no observed process exit, so none of those rows are primary results. LangArena was collected afresh, followed by lifecycle, under a detached coordinator with observed successful exits. The original evidence is retained.

## Qualification and reproduction

Qualification passed 77 focused commands, 978 cases, 9,573 differential executions including 7,656 native stdout comparisons, and 11,484 host replays across 1,574 unique Wasm modules. Worker qualification passed 3,001 observations derived from 3,828 aliases; 1,487 input pins and eight matched controls were checked. See the [qualification summary](qualification-summary.json) for coverage and limits.

Verify the retained package from the repository root:

```sh
python bench/results/2026-11-04/leaf-and-loads/reproduction/verify.py
```

The [guide](../../../../docs/GUIDE.md) and [benchmark methods](../../../README.md) describe rebuilding and collecting fresh measurements. The earlier [byte-scans campaign](../byte-scans/README.md) remains a separate historical comparison.
