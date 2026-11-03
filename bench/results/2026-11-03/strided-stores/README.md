# Guarded strided stores and byte scans

On November 3, 2026, nine paired warmed rounds on a shared AMD Ryzen 7 3800X measured the unchanged adapted Sieve port at 1,472.666 → 899.059 ms on Wasmtime, a paired 1.611× speedup (ratio MAD 0.028). V8 measured 1,320.857 → 846.565 ms, 1.561× (MAD 0.004). Times cover the configured iteration count, excluding preparation and startup. The selected native reference measured 919.335 ms in the Wasmtime rounds; the paired direct/native time ratio was 0.971 (MAD 0.029), roughly matching within observed variation. References were built and selected separately in an earlier pilot, then executed in these fresh rounds; they are not universal ceilings. [All ten workload results](../../../../docs/RUNTIME_TARGETS.md) and the [Wasmtime](final-warmed.json) and [V8](final-v8.json) reports retain samples and controls.

Eligible positive-stride constant stores group four ordered writes behind guards. Eligible byte-equality reductions count matching stride lanes and retain the last index with SIMD128. Scalar tails, failed guards and debug builds retain the original path. The Sieve port grows from 3,098 to 3,482 bytes (12.4%); full Sieve grows from 6,390 to 6,698 bytes (4.8%). The other nine warmed guests and other nine full examples are byte-identical. Full Sieve matches store grouping but its collector push loop does not match the scan. Fresh full-process measurements are separate cohorts and do not establish a paired compiler-change speedup. [Module analysis](module-analysis.json) records the comparison.

Five-round factorial screens preceded confirmation. Wasmtime baseline, grouping-only, count-only and combined medians were 1,409.192, 1,434.737, 973.782 and 874.092 ms; V8 medians were 1,365.013, 1,195.366, 1,011.216 and 872.323 ms. The combined effect exceeds either isolated change in these screens; the interaction does not establish a hardware cause. [Campaign data](campaign.json) retains the individual samples and tradeoffs.

## Identity and method

The selected compiler SHA-256 is `f76ea0f4bfa57949f5b04d42884f8316546a7eb50720b31e564afafcad9a0af8`; the baseline is `b53aaf097e0ea47b3f3efea158db3520aa03f9ab1fb1625efd21fff31d49319d`. Both use Goose revision `2e2bedef5b980bf013cac5aaa0095bfea64e5569`. [Compiler identity](compiler-identity.json) records source patches and header hashes; the warmed reports retain both frozen source snapshots and workload inputs. The seven adapted LangArena ports and three example adapters are described in [runtime targets](../../../../docs/RUNTIME_TARGETS.md). Direct Wasm uses memory32; C-to-Wasm uses memory64.

Wasmtime is 50.0.1; V8 is 13.6.233.17-node.58 in Node 24.22.1. The warmed Wasmtime host SHA-256 is `e0468623661130c89eec4902c287c1ec971928b75469a47303c3392733c51cd3`, linked to the Python package library. The fresh-process native host SHA-256 is `e303865d7661dc5d0dad1e1719753d1101bfe7f7e16d5b1eb2e174f416fbbf28`, linked to the static Wasmtime SDK; the Python library SHA-256 is `3127ca42fe7cdd3f0a43a358e79177dcfedd46c1746329826403b9d854de6178`. Host, callbacks and I/O differ. Emscripten is 6.0.13 and GCC is 16.2.1. [Host report](host.json) records library identities and preparation.

The six fresh cohorts comprise 550 warmed Wasmtime, 200 warmed V8, 1,600 example, 1,440 host, 315 LangArena and 960 lifecycle observations, plus 200 separate host preparations. [Examples](examples.json), [LangArena](readme.json), [host](host.json), and [lifecycle](lifecycle.json) reports retain their distinct boundaries; precompiled execution excludes preparation, and resident requests exclude process startup. Full-process examples use constant inputs and checked output. The build cohort has five uncached samples per cell; runtime process cells have one warmup and 15 samples.

## Qualification and reproduction

Qualification passed 76 focused commands, 978 cases, 9,573 differential executions including 7,656 native stdout comparisons, and 11,484 host replays across 1,574 unique Wasm modules. Worker qualification passed 3,001 observations derived from 3,828 aliases; 1,368 input pins passed. [Qualification summary](qualification-summary.json) and [campaign](campaign.json) record coverage and limitations.

Verify the retained package from the repository root:

```sh
python bench/results/2026-11-03/strided-stores/reproduction/verify.py
```

The [guide](../../../../docs/GUIDE.md) and [benchmark methods](../../../../bench/README.md) describe rebuilding and collecting fresh measurements. The earlier [merge-bounds cohort](../merge-bounds/README.md) remains a separate historical comparison.
