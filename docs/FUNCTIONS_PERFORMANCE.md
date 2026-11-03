# Functions performance

The direct backend forwards eligible tail-only identity wrappers into ordinary internal named calls. Original argument expressions enter the ordinary caller's snapshot path, preserving full first snapshots in source order and the callee's finish copies. It excludes captures, remaps, arguments requiring materialization, multiple returns, and non-fixed, reference, slice or mutable parameters.

Body memory-growth checks share a helper for actual growth; frame-prologue checks remain inline. The caller retains its fast guard, abort behavior, source attribution and reentry behavior. In Functions, 44 body sites share the helper.

Functions shrank from 42,296 to 39,702 bytes (6.13%); static `memory.copy` instructions fell from 317 to 267, and declared locals from 2,019 to 1,919. Public imports, memory, globals, exports and data are unchanged; internal type and function sections changed. The baseline includes the [earlier forwarding step](../bench/results/2026-11-03/functions-forwarding/README.md), measured in a separate cohort.

In a 31-pair CPU 2 diagnostic holdout, native Wasmtime compile and instantiate fell from 33.758 to 31.739 ms, a paired 1.060× speedup (MAD 0.015). Native first entry was 1.006× (MAD 0.126) and V8 first entry was 1.025× (MAD 0.140), both inconclusive. First entry includes initialization and callbacks; V8 also includes lazy JIT. CPU 2 pins inherited engine workers and is not the normal-pool process boundary. Its 61-pair ordinary process speedup was 1.059× (MAD 0.015).

The independent 61-pair normal-pool process holdout was noisy: paired ordinary native-host speedup was 1.039× (MAD 0.150), precompiled 0.943× (MAD 0.156), and V8 1.021× (MAD 0.159). The fresh 15-sample cohort measured Functions at 18.464 ms ordinary (MAD 1.164), 1.523 ms precompiled (MAD 0.155), and 1.223 ms native C (MAD 0.130); precompiled excludes preparation. C-to-Wasm took 29.377 ms ordinary (MAD 1.190) and 2.254 ms precompiled (MAD 0.306). These figures include process startup and are not paired with the prior cohort.

Nine paired warmed rounds across ten workloads gave geometric mean baseline/current speedups of 0.997× on Wasmtime (MAD 0.009) and 0.999× on V8 (MAD 0.001), with no established execution gain. Eight modules, including Sieve, were byte-identical; only Life and Sorting changed and both were flat.

An all-site growth helper was rejected after Sieve regressed about 20% despite identical hot instructions. A shifted loop crossing a 64-byte cache line is a plausible cause, not a proven one. During development a restored header retained an old timestamp and Ninja reused a stale prototype binary before qualification. Bootstrap now updates timestamps for changed bytes and preserves them for unchanged bytes; a real Ninja regression test covers the fix. All timings used the correct frozen compilers.

The compiler passed 69 focused gates, 9,573 differential executions and 11,484 host replays. [Measurements, identities and retained experiments](../bench/results/2026-11-03/functions-calls/README.md) record the boundaries and results.
