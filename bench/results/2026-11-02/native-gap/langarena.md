# LangArena qualification and measurements

Status: **passed**.

Upstream pin: `aab9b14998231ba905523b5ba3990ee03c46f64d`. Catalog: **50 tasks**. Adapted entrypoints: **7 tasks**, including six storage adaptations.

Mode: `measure`. Machine: AMD Ryzen 7 3800X, shared desktop host.
Compiler SHA-256: `3316710bb9d2b3100e94c2023000f0cb1b7517010ef04076314b4703fdcfcbba`.

## Measurement contract

Whole-suite results use all original Goose kernel sources. The only staging patch changes the marker destination from `/tmp/recompile_marker` to a relative file inside the isolated run directory. The original checkout is hash-verified and never edited. Whole-suite compile times include all 50 tasks.

The adapted track uses the same seven port sources across native C, direct Wasm, and C-Wasm. Six ports replace growable storage; Fannkuch keeps its original fixed-array kernel. Official test/run inputs and checksums are unchanged. Preparation stays outside the clock; warmups mutate the same state used for measurement; the deterministic RNG is reset before measured iterations. Existing checksum work retains its original placement.

Cold builds and marker-edit builds launch fresh driver/compiler processes with `--no-cache`. OS caches and installed compiler/system-library caches are retained. A port marker edit changes its exit status from 0 to 1 after its two output lines, and the edited executable must retain the official checksum. Whole-suite edits change the actual marker file contents. Source bytes are restored in all cases. Optional unchanged cache hits are a separate phase. Edited sources still rerun the complete frontend.

The official whole-suite timer prints milliseconds; adapted ports print integer nanoseconds. Timed regions exclude process startup and preparation. Process wall time is retained separately. Sample counts below five are preliminary estimates; raw values and MAD are provided. These are local comparisons, not LangArena leaderboard scores or claims of complete direct-backend language support.

## Whole-suite compilation

| Backend | Phase | Samples | Median ms | MAD ms | Artifact bytes |
| --- | --- | ---: | ---: | ---: | ---: |

## Original-source correctness and runtime

| Task | Backend / engine | Profile | Samples | Region median ms | MAD ms | Process median ms |
| --- | --- | --- | ---: | ---: | ---: | ---: |

## Adapted workload compilation

| Task | Backend | Phase | Samples | Median ms | MAD ms | Artifact bytes |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| CLBG::Fannkuchredux | c-wasm | cold | 5 | 686.739 | 10.291 | 51971 |
| CLBG::Fannkuchredux | direct | cold | 5 | 79.535 | 3.088 | 4598 |
| CLBG::Fannkuchredux | native | cold | 5 | 327.459 | 12.600 | 22984 |
| CLBG::Mandelbrot | c-wasm | cold | 5 | 674.956 | 28.536 | 52047 |
| CLBG::Mandelbrot | direct | cold | 5 | 76.927 | 4.478 | 5194 |
| CLBG::Mandelbrot | native | cold | 5 | 326.149 | 10.359 | 23160 |
| Etc::Sieve | c-wasm | cold | 5 | 700.406 | 16.148 | 51590 |
| Etc::Sieve | direct | cold | 5 | 78.385 | 4.050 | 3655 |
| Etc::Sieve | native | cold | 5 | 316.923 | 7.356 | 23128 |
| Hash::CRC32 | c-wasm | cold | 5 | 655.233 | 9.269 | 51805 |
| Hash::CRC32 | direct | cold | 5 | 73.341 | 3.586 | 3664 |
| Hash::CRC32 | native | cold | 5 | 290.935 | 14.880 | 23008 |
| Hash::SHA256 | c-wasm | cold | 5 | 678.415 | 28.447 | 51815 |
| Hash::SHA256 | direct | cold | 5 | 73.978 | 4.793 | 6635 |
| Hash::SHA256 | native | cold | 5 | 308.403 | 14.268 | 23008 |
| Sort::Merge | c-wasm | cold | 5 | 706.988 | 28.992 | 52472 |
| Sort::Merge | direct | cold | 5 | 85.109 | 10.545 | 5798 |
| Sort::Merge | native | cold | 5 | 360.972 | 16.714 | 27416 |
| Sort::Quick | c-wasm | cold | 5 | 705.327 | 50.327 | 52031 |
| Sort::Quick | direct | cold | 5 | 74.226 | 5.002 | 4984 |
| Sort::Quick | native | cold | 5 | 335.031 | 10.393 | 23168 |

## Adapted workload runtime

| Task | Backend / engine | Profile | Samples | Region median ms | MAD ms | Engine compile + instantiate ms | Process median ms | Checksum |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| CLBG::Fannkuchredux | c-wasm / v8 | run | 5 | 2206.088 | 65.137 | 0.609 | 2661.483 | 135762480 |
| CLBG::Fannkuchredux | c-wasm / v8 | test | 1 | 0.020 | 0.000 | 0.755 | 29.408 | 4428 |
| CLBG::Fannkuchredux | c-wasm / wasmtime | run | 5 | 1502.140 | 18.937 | 24.468 | 1914.254 | 135762480 |
| CLBG::Fannkuchredux | c-wasm / wasmtime | test | 1 | 0.054 | 0.000 | 38.378 | 121.327 | 4428 |
| CLBG::Fannkuchredux | direct / v8 | run | 5 | 1294.543 | 6.565 | 0.255 | 1598.557 | 135762480 |
| CLBG::Fannkuchredux | direct / v8 | test | 1 | 0.033 | 0.000 | 0.292 | 26.293 | 4428 |
| CLBG::Fannkuchredux | direct / wasmtime | run | 5 | 1374.668 | 10.227 | 4.377 | 1738.143 | 135762480 |
| CLBG::Fannkuchredux | direct / wasmtime | test | 1 | 0.026 | 0.000 | 4.730 | 86.860 | 4428 |
| CLBG::Fannkuchredux | native / native | run | 5 | 1327.062 | 1.637 | — | 1576.351 | 135762480 |
| CLBG::Fannkuchredux | native / native | test | 1 | 0.022 | 0.000 | — | 1.112 | 4428 |
| CLBG::Mandelbrot | c-wasm / v8 | run | 5 | 964.395 | 3.220 | 0.582 | 1200.187 | 3455988829 |
| CLBG::Mandelbrot | c-wasm / v8 | test | 1 | 0.335 | 0.000 | 0.536 | 28.778 | 2236342953 |
| CLBG::Mandelbrot | c-wasm / wasmtime | run | 5 | 1073.862 | 7.668 | 24.595 | 1403.159 | 3455988829 |
| CLBG::Mandelbrot | c-wasm / wasmtime | test | 1 | 0.226 | 0.000 | 23.838 | 137.492 | 2236342953 |
| CLBG::Mandelbrot | direct / v8 | run | 5 | 976.369 | 11.449 | 0.275 | 1227.980 | 3455988829 |
| CLBG::Mandelbrot | direct / v8 | test | 1 | 0.528 | 0.000 | 0.320 | 47.688 | 2236342953 |
| CLBG::Mandelbrot | direct / wasmtime | run | 5 | 1026.748 | 12.854 | 4.048 | 1326.476 | 3455988829 |
| CLBG::Mandelbrot | direct / wasmtime | test | 1 | 0.196 | 0.000 | 4.894 | 119.653 | 2236342953 |
| CLBG::Mandelbrot | native / native | run | 5 | 938.233 | 7.099 | — | 1129.743 | 3455988829 |
| CLBG::Mandelbrot | native / native | test | 1 | 0.159 | 0.000 | — | 3.027 | 2236342953 |
| Etc::Sieve | c-wasm / v8 | run | 5 | 6569.380 | 736.707 | 0.560 | 7833.935 | 1042248060 |
| Etc::Sieve | c-wasm / v8 | test | 1 | 0.020 | 0.000 | 0.638 | 33.754 | 4660 |
| Etc::Sieve | c-wasm / wasmtime | run | 5 | 5529.660 | 21.703 | 24.510 | 6740.226 | 1042248060 |
| Etc::Sieve | c-wasm / wasmtime | test | 1 | 0.052 | 0.000 | 26.698 | 117.521 | 4660 |
| Etc::Sieve | direct / v8 | run | 5 | 1387.203 | 14.773 | 0.240 | 1737.142 | 1042248060 |
| Etc::Sieve | direct / v8 | test | 1 | 0.017 | 0.000 | 0.304 | 43.771 | 4660 |
| Etc::Sieve | direct / wasmtime | run | 5 | 1462.777 | 21.132 | 3.839 | 1838.146 | 1042248060 |
| Etc::Sieve | direct / wasmtime | test | 1 | 0.024 | 0.000 | 4.305 | 122.990 | 4660 |
| Etc::Sieve | native / native | run | 5 | 880.271 | 4.248 | — | 1057.543 | 1042248060 |
| Etc::Sieve | native / native | test | 1 | 0.005 | 0.000 | — | 5.231 | 4660 |
| Hash::CRC32 | c-wasm / v8 | run | 5 | 456.547 | 1.834 | 0.567 | 585.162 | 2318723244 |
| Hash::CRC32 | c-wasm / v8 | test | 1 | 0.014 | 0.000 | 0.699 | 27.866 | 3031698216 |
| Hash::CRC32 | c-wasm / wasmtime | run | 5 | 418.653 | 2.988 | 26.865 | 624.505 | 2318723244 |
| Hash::CRC32 | c-wasm / wasmtime | test | 1 | 0.055 | 0.000 | 26.671 | 109.386 | 3031698216 |
| Hash::CRC32 | direct / v8 | run | 5 | 510.057 | 3.928 | 0.251 | 658.649 | 2318723244 |
| Hash::CRC32 | direct / v8 | test | 1 | 0.019 | 0.000 | 0.276 | 30.587 | 3031698216 |
| Hash::CRC32 | direct / wasmtime | run | 5 | 431.003 | 1.472 | 3.974 | 610.101 | 2318723244 |
| Hash::CRC32 | direct / wasmtime | test | 1 | 0.027 | 0.000 | 3.662 | 94.776 | 3031698216 |
| Hash::CRC32 | native / native | run | 5 | 1371.960 | 9.100 | — | 1667.960 | 2318723244 |
| Hash::CRC32 | native / native | test | 1 | 0.056 | 0.000 | — | 2.599 | 3031698216 |
| Hash::SHA256 | c-wasm / v8 | run | 5 | 1056.056 | 13.710 | 0.610 | 1324.533 | 2844672256 |
| Hash::SHA256 | c-wasm / v8 | test | 1 | 0.008 | 0.000 | 0.714 | 27.755 | 1036619072 |
| Hash::SHA256 | c-wasm / wasmtime | run | 5 | 986.298 | 5.689 | 26.353 | 1306.758 | 2844672256 |
| Hash::SHA256 | c-wasm / wasmtime | test | 1 | 0.050 | 0.000 | 26.000 | 141.626 | 1036619072 |
| Hash::SHA256 | direct / v8 | run | 5 | 958.510 | 9.738 | 0.291 | 1195.841 | 2844672256 |
| Hash::SHA256 | direct / v8 | test | 1 | 0.010 | 0.000 | 0.283 | 37.415 | 1036619072 |
| Hash::SHA256 | direct / wasmtime | run | 5 | 942.694 | 3.417 | 4.675 | 1226.283 | 2844672256 |
| Hash::SHA256 | direct / wasmtime | test | 1 | 0.021 | 0.000 | 7.234 | 122.858 | 1036619072 |
| Hash::SHA256 | native / native | run | 5 | 601.741 | 14.974 | — | 729.180 | 2844672256 |
| Hash::SHA256 | native / native | test | 1 | 0.002 | 0.000 | — | 1.726 | 1036619072 |
| Sort::Merge | c-wasm / v8 | run | 5 | 1320.284 | 5.006 | 0.601 | 1625.455 | 61757772 |
| Sort::Merge | c-wasm / v8 | test | 1 | 12.339 | 0.000 | 0.644 | 52.955 | 2548773 |
| Sort::Merge | c-wasm / wasmtime | run | 5 | 2748.800 | 29.760 | 24.098 | 3397.409 | 61757772 |
| Sort::Merge | c-wasm / wasmtime | test | 1 | 25.925 | 0.000 | 25.944 | 149.133 | 2548773 |
| Sort::Merge | direct / v8 | run | 5 | 2020.398 | 16.877 | 0.265 | 2468.011 | 61757772 |
| Sort::Merge | direct / v8 | test | 1 | 18.913 | 0.000 | 0.394 | 80.574 | 2548773 |
| Sort::Merge | direct / wasmtime | run | 5 | 2078.524 | 18.289 | 3.840 | 2582.898 | 61757772 |
| Sort::Merge | direct / wasmtime | test | 1 | 19.892 | 0.000 | 4.691 | 119.400 | 2548773 |
| Sort::Merge | native / native | run | 5 | 1400.020 | 10.370 | — | 1684.653 | 61757772 |
| Sort::Merge | native / native | test | 1 | 13.570 | 0.000 | — | 22.987 | 2548773 |
| Sort::Quick | c-wasm / v8 | run | 5 | 1427.804 | 7.414 | 0.565 | 1748.996 | 61757772 |
| Sort::Quick | c-wasm / v8 | test | 1 | 14.470 | 0.000 | 0.627 | 60.372 | 2548773 |
| Sort::Quick | c-wasm / wasmtime | run | 5 | 1652.878 | 5.111 | 25.473 | 2097.646 | 61757772 |
| Sort::Quick | c-wasm / wasmtime | test | 1 | 16.256 | 0.000 | 26.319 | 138.657 | 2548773 |
| Sort::Quick | direct / v8 | run | 5 | 1426.005 | 6.926 | 0.251 | 1751.097 | 61757772 |
| Sort::Quick | direct / v8 | test | 1 | 14.379 | 0.000 | 0.268 | 56.507 | 2548773 |
| Sort::Quick | direct / wasmtime | run | 5 | 1742.159 | 91.802 | 4.175 | 2161.140 | 61757772 |
| Sort::Quick | direct / wasmtime | test | 1 | 15.653 | 0.000 | 3.881 | 110.697 | 2548773 |
| Sort::Quick | native / native | run | 5 | 1226.460 | 6.745 | — | 1477.348 | 61757772 |
| Sort::Quick | native / native | test | 1 | 11.934 | 0.000 | — | 20.458 | 2548773 |

## Qualification and limits

- Seven adapted entrypoints (six change storage, one changes only the harness) are a subset of the 50-task catalog; they do not establish unmodified whole-suite Wasm support.
- No local result is a LangArena leaderboard rank: source/compiler versions, target layout, host, flags, and coverage differ.
- Cold builds retain OS and compiler system-library caches; they are complete uncached driver builds, not disk-cold experiments.

The full 50-task coverage matrix, raw commands/output, source and artifact hashes, tool versions, input values, environment overrides (including `EM_NODE_JS`), and phase timings are in `report.json` and adjacent logs. `Hash::SHA256` retains LangArena's custom hash workload; it is not standard cryptographic SHA-256.
