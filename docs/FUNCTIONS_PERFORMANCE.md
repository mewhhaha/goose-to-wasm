# Functions performance

The direct backend combines adjacent Wasm local set/get operations into `local.tee` and removes unused locals across a function. Parameters, types, producer traps and the public ABI are preserved; unknown raw instructions retain the conservative fallback. Functions shrank from 54,716 to 45,923 bytes (16.1%) and declared locals from 3,479 to 2,239 (35.6%); non-code payload is identical.

A post-qualification CPU 2 holdout compared 31 paired phases. V8 default first entry fell from 7.226 to 5.856 ms, a paired 1.220× speedup (MAD 0.045); first entry includes lazy JIT. Native Wasmtime compile/instantiate fell from 36.700 to 36.141 ms, 1.018× (MAD 0.007). Normal-pool whole-process timing was noisy and did not establish a broad Wasmtime gain.

In the fresh 15-sample process cohort, Functions took 19.526 ms with the ordinary native Wasmtime host, 1.698 ms with a precompiled artifact and 0.910 ms as native C; precompiled time excludes preparation. The C-to-Wasm host took 30.472 ms ordinary and 1.663 ms precompiled. The actual native-host entry itself is about 0.065–0.075 ms: compilation and engine startup dominate ordinary process time. The Python host's approximately 1.35 ms entry includes Python callbacks and is a different boundary.

Nine paired warmed rounds across ten workloads gave geometric mean baseline/current speedups of 1.012× on Wasmtime and 1.005× on V8; individual median costs remained below 1%. Winch could not compile this module with the pinned SDK configuration; disabling optimization and capping Rayon pools did not show a robust benefit.

The delivered compiler passed 66 focused gates, 9,573 differential executions and 11,484 host replays. [Measurements, identities and retained experiments](../bench/results/2026-11-03/functions/README.md) distinguish these fresh runs from the earlier [24-family campaign](FULL_PERFORMANCE_CAMPAIGN.md).
