# Native Fibonacci timing audit

The final seven-sample native Fibonacci measurement has a **0.193 ms median** and **0.015 ms MAD** for runtime input 35. The optimized program executes real input-dependent work inside the timed region. The short-duration qualification remains in the benchmark report.

## Evidence

The measured executable has SHA-256 `d221e4686310c0c4453fc8bd66efa1ab78d9d4a1f0242b6b7d129bae102eb4a7`. The [disassembly record](native-fibonacci-disassembly.txt) is from that exact artifact; [machine-readable audit data](native-fibonacci-audit.json) records the commands and input checks.

The native `main` function calls, in order:

1. `bench_clock`, taking the start timestamp.
2. `bench_barrier(input)`, obtaining the runtime workload through the opaque external function.
3. `kernel_g`, computing Fibonacci from that returned value.
4. `bench_sink`, consuming the computed result.
5. `bench_clock`, taking the end timestamp.

The kernel contains recursive calls, reused intermediate values, and a loop. GCC's generated code has transformed the source recursion substantially. The timed call remains between the two timestamps, and the source input still comes from stdin. These observations establish dynamic execution and explain why this workload is sensitive to compiler transformations.

The same executable was then run with several different stdin inputs. Each output matched an independent iterative Fibonacci calculation:

| Runtime input | Checksum | Reference match |
| ---: | ---: | --- |
| 20 | 6765 | Yes |
| 30 | 832040 | Yes |
| 35 | 9227465 | Yes |
| 40 | 102334155 | Yes |
| 45 | 1134903170 | Yes |

These additional runs are diagnostic checks, not new samples in the performance comparison. Their raw durations are retained in the audit JSON for transparency.

## Interpretation

The published Fibonacci rows compare complete optimized computations across targets. They should not be interpreted as isolated function-call overhead or as a universal native/Wasm speed ratio. The scalar input barriers and checksum validation prevent a constant result from replacing the entire workload; they intentionally allow each backend to optimize the computation.

The native measurement is below the harness's conservative 10 ms threshold. Keep its limited duration in view when interpreting fine percentage differences. The other workload timings and all raw samples remain available in [the full benchmark report](report.md) and [raw measurements](report.json).
