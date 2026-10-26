# Goose backend benchmark

Status: **passed**.

These are measurements from this machine and workload set, not universal speed claims.

CPU: unknown. Platform: Linux-6.18.55-x86_64-with-glibc2.39. Wasmtime: 50.0.1.
Supplied machine description: AMD EPYC 9V74 (KVM guest, 9 logical CPUs, 9.7 GiB RAM).
Compiler SHA-256: `91d00fc48027f694e015c4c4fcac72cb3acba1aff98639b1433590ee9446af6a`.

## Measurement contract

All backends use the same Goose source and `-O2` semantic passes. Direct emits binary Wasm without LLVM; native C and C-Wasm additionally use their C compiler's `-O2`. Direct uses memory32. The C-Wasm profile preserves Goose's LP64 C layout in one standalone memory64 binary, run unchanged on V8 and Wasmtime through the same WASI64 service contract. These memory-layout differences are part of the compared targets.

Cold-build wall time includes driver startup, Goose frontend/emission, and any C compilation/linking. `--no-cache` disables the content cache. OS file caches are retained; this is a complete fresh-process build, not a disk-cold experiment. Emscripten's installed system-library cache is reused. Sample order is deterministically shuffled.

Each runtime process performs 2 untimed kernel executions before one timed execution. The timed region excludes process startup, Wasm compilation/instantiation, input parsing, and output formatting. It includes two scalar FFI barriers and the clock-call boundary. Process wall time includes all warmup kernels and startup. Outer warmup processes prime system caches only.

Inputs arrive at runtime through stdin; a volatile C barrier or Wasm host import makes them opaque to optimizers. A sink consumes every computed result before the end timestamp. Each sample must match the independent Python reference checksum. There are no Python callbacks inside computational loops.

## Complete cold builds

Times are median milliseconds; dispersion is median absolute deviation (MAD).

| Workload | Backend | Samples | Median ms | MAD ms | Module / executable bytes |
| --- | --- | ---: | ---: | ---: | ---: |
| array_updates | c-wasm | 5 | 635.553 | 35.861 | 45568 |
| array_updates | direct | 5 | 58.469 | 2.020 | 1902 |
| array_updates | native | 5 | 246.696 | 7.088 | 22368 |
| float_recurrence | c-wasm | 5 | 592.047 | 33.253 | 45380 |
| float_recurrence | direct | 5 | 56.387 | 2.243 | 1313 |
| float_recurrence | native | 5 | 257.515 | 9.913 | 22488 |
| integer_mod | c-wasm | 5 | 663.045 | 19.727 | 45055 |
| integer_mod | direct | 5 | 56.773 | 3.384 | 1295 |
| integer_mod | native | 5 | 250.819 | 16.078 | 22368 |
| recursive_fibonacci | c-wasm | 5 | 638.294 | 40.325 | 44722 |
| recursive_fibonacci | direct | 5 | 58.211 | 3.874 | 953 |
| recursive_fibonacci | native | 5 | 276.576 | 8.459 | 22440 |

## Runtime

| Workload | Backend / engine | Samples | Timed region median ms | MAD ms | Process median ms | Checksum |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| array_updates | c-wasm / v8 | 7 | 41.764 | 4.549 | 171.087 | 309459781 |
| array_updates | c-wasm / wasmtime | 7 | 35.522 | 0.787 | 218.895 | 309459781 |
| array_updates | direct / v8 | 7 | 64.585 | 2.118 | 230.054 | 309459781 |
| array_updates | direct / wasmtime | 7 | 32.327 | 0.615 | 193.232 | 309459781 |
| array_updates | native / native | 7 | 25.328 | 2.413 | 80.055 | 309459781 |
| float_recurrence | c-wasm / v8 | 7 | 48.978 | 0.658 | 197.383 | 5731374 |
| float_recurrence | c-wasm / wasmtime | 7 | 46.809 | 1.093 | 262.635 | 5731374 |
| float_recurrence | direct / v8 | 7 | 66.951 | 0.761 | 239.949 | 5731374 |
| float_recurrence | direct / wasmtime | 7 | 47.420 | 1.814 | 238.424 | 5731374 |
| float_recurrence | native / native | 7 | 44.256 | 1.110 | 137.684 | 5731374 |
| integer_mod | c-wasm / v8 | 7 | 56.756 | 2.220 | 206.529 | 405595776 |
| integer_mod | c-wasm / wasmtime | 7 | 50.963 | 1.334 | 270.211 | 405595776 |
| integer_mod | direct / v8 | 7 | 59.302 | 1.953 | 215.936 | 405595776 |
| integer_mod | direct / wasmtime | 7 | 48.643 | 1.941 | 242.545 | 405595776 |
| integer_mod | native / native | 7 | 42.102 | 1.222 | 129.850 | 405595776 |
| recursive_fibonacci | c-wasm / v8 | 7 | 24.428 | 1.231 | 121.300 | 9227465 |
| recursive_fibonacci | c-wasm / wasmtime | 7 | 37.516 | 1.616 | 238.650 | 9227465 |
| recursive_fibonacci | direct / v8 | 7 | 25.094 | 0.609 | 120.041 | 9227465 |
| recursive_fibonacci | direct / wasmtime | 7 | 37.897 | 1.156 | 202.070 | 9227465 |
| recursive_fibonacci | native / native | 7 | 0.193 | 0.015 | 2.978 | 9227465 |

## Qualification and limits

- The direct backend supports a documented fragment of Goose. Results do not establish full-language parity or compilation of arbitrary programs.
- Native and C-Wasm use different C compilers; engine tiering, host-call costs, machine load, and CPU frequency can affect results.
- recursive_fibonacci/native/native timed region is below 10 ms; fixed overhead is material.

Raw samples, min/max, quartiles, tool versions, commands, checksums, fixture hashes, and driver phase timings are in `report.json` and the adjacent per-sample logs. Unchanged-build and edited-source latency are measured separately by `bench/incremental.py`.

## Retained evidence

The [native Fibonacci audit](fibonacci-audit.md) verifies the unexpectedly short native timing against the exact measured executable, checks the runtime call order in disassembly, and confirms varied stdin inputs produce the expected results. Its short-duration qualification remains in the table above.

[Per-sample logs](logs.tar.gz) retain the exact commands, stdout, stderr, and driver statistics for all builds and runtime executions. The archive excludes executables and Wasm binaries; artifact hashes are recorded in the raw report.
