# Compile and rebuild latency — 2026-10-26

Machine: AMD EPYC 9V74; KVM guest, 9 logical CPUs, 9.7 GiB RAM. Python 3.12.14.

Compiler SHA-256: `91d00fc48027f694e015c4c4fcac72cb3acba1aff98639b1433590ee9446af6a`.

This synthetic input contains 32 small scalar functions plus main and emits 34 Wasm functions. All paths use Goose `-O0`. Each row has 15 samples. These numbers describe this input, not arbitrary projects.

| Invocation | Median ms | MAD ms | p90 ms |
| --- | ---: | ---: | ---: |
| Raw native compiler process | 8.844 | 0.745 | 10.262 |
| Uncached Python driver process | 59.890 | 2.499 | 65.561 |
| Fresh driver process, unchanged cache hit | 50.316 | 3.187 | 58.978 |
| Persistent server, unchanged cache hit | 2.116 | 0.206 | 2.519 |
| Persistent server, one-function source edit | 15.080 | 0.967 | 18.075 |

Fresh process times include process startup and file output. The server rows include the JSON request/response round trip and content validation. An unchanged output keeps its timestamp. Caches are warmed before hit measurements.

**Every edited build reruns the complete frontend and direct emitter.** In all 15 one-function edits, 33 of the 34 emitted function bodies retained their fingerprints and one changed. No function emission was skipped. The last edited executable was run on V8 with runtime input and checked against an independently computed answer.

## Raw compiler phase medians

| Phase | Median ms |
| --- | ---: |
| Parsing | 2.152 |
| Resolution | 0.171 |
| Type checking/specialization | 2.501 |
| Goose optimization | 0.041 |
| Bounds analysis | 0.083 |
| Direct Wasm emission | 0.086 |

On this input, parsing and type checking dominate the measured compiler phases. The persistent driver already removes most wrapper startup overhead. Persistent frontend state and dependency-based invalidation are the next opportunities; a function-output cache alone would address only the small emission phase in this particular program.

The [raw JSON](incremental.json) preserves every sample, phase medians, edit fingerprints, verification result, and compiler/driver/harness hashes. Reproduce with:

```sh
python bench/incremental.py --samples 15 --functions 32
```

See [the architecture](../../../docs/INCREMENTAL.md) for implemented behavior and remaining work.
