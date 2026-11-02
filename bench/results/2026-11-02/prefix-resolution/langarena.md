# LangArena qualification and measurements

Status: **passed**.

Upstream pin: `aab9b14998231ba905523b5ba3990ee03c46f64d`. Catalog: **50 tasks**. Adapted entrypoints: **7 tasks**, including six storage adaptations.

Mode: `measure`. Machine: AMD Ryzen 7 3800X, shared desktop host.
Compiler SHA-256: `67256d720a48e56ba7c1fade0b76af0ee2b6ac1f96d0da72cf141951b3dc39cc`.

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
| CLBG::Fannkuchredux | c-wasm | cold | 5 | 654.577 | 12.930 | 51975 |
| CLBG::Fannkuchredux | direct | cold | 5 | 75.888 | 3.670 | 4598 |
| CLBG::Fannkuchredux | native | cold | 5 | 337.777 | 13.350 | 22984 |
| CLBG::Mandelbrot | c-wasm | cold | 5 | 692.958 | 20.778 | 52049 |
| CLBG::Mandelbrot | direct | cold | 5 | 83.141 | 0.975 | 5194 |
| CLBG::Mandelbrot | native | cold | 5 | 284.762 | 6.385 | 23160 |
| Etc::Sieve | c-wasm | cold | 5 | 685.145 | 37.872 | 51593 |
| Etc::Sieve | direct | cold | 5 | 78.610 | 2.335 | 3655 |
| Etc::Sieve | native | cold | 5 | 305.888 | 18.574 | 23128 |
| Hash::CRC32 | c-wasm | cold | 5 | 652.659 | 3.769 | 51807 |
| Hash::CRC32 | direct | cold | 5 | 72.533 | 0.757 | 3664 |
| Hash::CRC32 | native | cold | 5 | 294.700 | 11.572 | 23008 |
| Hash::SHA256 | c-wasm | cold | 5 | 679.433 | 10.938 | 51815 |
| Hash::SHA256 | direct | cold | 5 | 87.730 | 11.131 | 6635 |
| Hash::SHA256 | native | cold | 5 | 337.231 | 15.292 | 23008 |
| Sort::Merge | c-wasm | cold | 5 | 666.907 | 18.203 | 52474 |
| Sort::Merge | direct | cold | 5 | 85.180 | 5.065 | 5798 |
| Sort::Merge | native | cold | 5 | 331.479 | 11.942 | 27416 |
| Sort::Quick | c-wasm | cold | 5 | 694.518 | 20.142 | 52033 |
| Sort::Quick | direct | cold | 5 | 81.738 | 8.436 | 4984 |
| Sort::Quick | native | cold | 5 | 306.157 | 1.153 | 23168 |

## Adapted workload runtime

| Task | Backend / engine | Profile | Samples | Region median ms | MAD ms | Engine compile + instantiate ms | Process median ms | Checksum |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| CLBG::Fannkuchredux | c-wasm / v8 | run | 5 | 2341.666 | 40.049 | 0.640 | 2828.595 | 135762480 |
| CLBG::Fannkuchredux | c-wasm / v8 | test | 1 | 0.023 | 0.000 | 0.592 | 32.068 | 4428 |
| CLBG::Fannkuchredux | c-wasm / wasmtime | run | 5 | 1614.961 | 31.676 | 32.786 | 2065.781 | 135762480 |
| CLBG::Fannkuchredux | c-wasm / wasmtime | test | 1 | 0.061 | 0.000 | 27.953 | 141.975 | 4428 |
| CLBG::Fannkuchredux | direct / v8 | run | 5 | 1443.799 | 4.162 | 0.281 | 1761.994 | 135762480 |
| CLBG::Fannkuchredux | direct / v8 | test | 1 | 0.034 | 0.000 | 0.319 | 28.283 | 4428 |
| CLBG::Fannkuchredux | direct / wasmtime | run | 5 | 1491.655 | 17.902 | 4.797 | 1895.812 | 135762480 |
| CLBG::Fannkuchredux | direct / wasmtime | test | 1 | 0.029 | 0.000 | 5.856 | 102.021 | 4428 |
| CLBG::Fannkuchredux | native / native | run | 5 | 1431.712 | 16.821 | — | 1695.011 | 135762480 |
| CLBG::Fannkuchredux | native / native | test | 1 | 0.012 | 0.000 | — | 0.873 | 4428 |
| CLBG::Mandelbrot | c-wasm / v8 | run | 5 | 1016.090 | 11.819 | 0.628 | 1263.999 | 3455988829 |
| CLBG::Mandelbrot | c-wasm / v8 | test | 1 | 0.360 | 0.000 | 0.660 | 35.837 | 2236342953 |
| CLBG::Mandelbrot | c-wasm / wasmtime | run | 5 | 1130.210 | 23.445 | 27.107 | 1471.770 | 3455988829 |
| CLBG::Mandelbrot | c-wasm / wasmtime | test | 1 | 0.300 | 0.000 | 37.638 | 134.816 | 2236342953 |
| CLBG::Mandelbrot | direct / v8 | run | 5 | 1066.300 | 21.549 | 0.284 | 1349.774 | 3455988829 |
| CLBG::Mandelbrot | direct / v8 | test | 1 | 0.385 | 0.000 | 3.432 | 47.551 | 2236342953 |
| CLBG::Mandelbrot | direct / wasmtime | run | 5 | 1101.914 | 9.010 | 4.506 | 1422.620 | 3455988829 |
| CLBG::Mandelbrot | direct / wasmtime | test | 1 | 0.244 | 0.000 | 5.348 | 101.806 | 2236342953 |
| CLBG::Mandelbrot | native / native | run | 5 | 980.998 | 10.390 | — | 1186.074 | 3455988829 |
| CLBG::Mandelbrot | native / native | test | 1 | 0.179 | 0.000 | — | 3.260 | 2236342953 |
| Etc::Sieve | c-wasm / v8 | run | 5 | 6461.642 | 267.125 | 0.599 | 7837.879 | 1042248060 |
| Etc::Sieve | c-wasm / v8 | test | 1 | 0.021 | 0.000 | 0.657 | 34.610 | 4660 |
| Etc::Sieve | c-wasm / wasmtime | run | 5 | 5636.220 | 59.585 | 28.777 | 6846.891 | 1042248060 |
| Etc::Sieve | c-wasm / wasmtime | test | 1 | 0.058 | 0.000 | 37.270 | 147.402 | 4660 |
| Etc::Sieve | direct / v8 | run | 5 | 1452.030 | 19.258 | 0.228 | 1817.259 | 1042248060 |
| Etc::Sieve | direct / v8 | test | 1 | 0.018 | 0.000 | 0.311 | 48.239 | 4660 |
| Etc::Sieve | direct / wasmtime | run | 5 | 1594.830 | 27.664 | 3.969 | 2014.267 | 1042248060 |
| Etc::Sieve | direct / wasmtime | test | 1 | 0.027 | 0.000 | 4.013 | 113.581 | 4660 |
| Etc::Sieve | native / native | run | 5 | 947.543 | 5.667 | — | 1144.049 | 1042248060 |
| Etc::Sieve | native / native | test | 1 | 0.003 | 0.000 | — | 2.504 | 4660 |
| Hash::CRC32 | c-wasm / v8 | run | 5 | 492.269 | 4.527 | 0.597 | 629.116 | 2318723244 |
| Hash::CRC32 | c-wasm / v8 | test | 1 | 0.020 | 0.000 | 0.955 | 53.075 | 3031698216 |
| Hash::CRC32 | c-wasm / wasmtime | run | 5 | 436.457 | 3.333 | 26.811 | 644.144 | 2318723244 |
| Hash::CRC32 | c-wasm / wasmtime | test | 1 | 0.057 | 0.000 | 27.486 | 123.215 | 3031698216 |
| Hash::CRC32 | direct / v8 | run | 5 | 538.462 | 2.478 | 0.257 | 701.874 | 2318723244 |
| Hash::CRC32 | direct / v8 | test | 1 | 0.019 | 0.000 | 0.239 | 34.692 | 3031698216 |
| Hash::CRC32 | direct / wasmtime | run | 5 | 471.737 | 4.954 | 3.975 | 667.685 | 2318723244 |
| Hash::CRC32 | direct / wasmtime | test | 1 | 0.029 | 0.000 | 4.287 | 113.340 | 3031698216 |
| Hash::CRC32 | native / native | run | 5 | 1450.561 | 4.739 | — | 1742.791 | 2318723244 |
| Hash::CRC32 | native / native | test | 1 | 0.053 | 0.000 | — | 2.610 | 3031698216 |
| Hash::SHA256 | c-wasm / v8 | run | 5 | 1188.323 | 18.859 | 0.684 | 1503.006 | 2844672256 |
| Hash::SHA256 | c-wasm / v8 | test | 1 | 0.009 | 0.000 | 0.588 | 33.659 | 1036619072 |
| Hash::SHA256 | c-wasm / wasmtime | run | 5 | 1050.523 | 11.537 | 26.073 | 1390.090 | 2844672256 |
| Hash::SHA256 | c-wasm / wasmtime | test | 1 | 0.053 | 0.000 | 28.028 | 139.772 | 1036619072 |
| Hash::SHA256 | direct / v8 | run | 5 | 1069.308 | 9.716 | 0.285 | 1335.665 | 2844672256 |
| Hash::SHA256 | direct / v8 | test | 1 | 0.011 | 0.000 | 0.289 | 38.907 | 1036619072 |
| Hash::SHA256 | direct / wasmtime | run | 5 | 1026.241 | 5.356 | 5.138 | 1329.312 | 2844672256 |
| Hash::SHA256 | direct / wasmtime | test | 1 | 0.024 | 0.000 | 5.652 | 98.068 | 1036619072 |
| Hash::SHA256 | native / native | run | 5 | 649.407 | 2.587 | — | 785.050 | 2844672256 |
| Hash::SHA256 | native / native | test | 1 | 0.002 | 0.000 | — | 1.703 | 1036619072 |
| Sort::Merge | c-wasm / v8 | run | 5 | 1444.699 | 14.228 | 0.627 | 1774.866 | 61757772 |
| Sort::Merge | c-wasm / v8 | test | 1 | 13.888 | 0.000 | 0.672 | 61.352 | 2548773 |
| Sort::Merge | c-wasm / wasmtime | run | 5 | 2858.399 | 9.990 | 27.428 | 3545.136 | 61757772 |
| Sort::Merge | c-wasm / wasmtime | test | 1 | 25.435 | 0.000 | 27.681 | 181.168 | 2548773 |
| Sort::Merge | direct / v8 | run | 5 | 2161.812 | 14.055 | 0.294 | 2654.056 | 61757772 |
| Sort::Merge | direct / v8 | test | 1 | 22.141 | 0.000 | 0.411 | 104.178 | 2548773 |
| Sort::Merge | direct / wasmtime | run | 5 | 2208.636 | 13.843 | 4.833 | 2748.418 | 61757772 |
| Sort::Merge | direct / wasmtime | test | 1 | 21.715 | 0.000 | 4.931 | 137.257 | 2548773 |
| Sort::Merge | native / native | run | 5 | 1512.424 | 49.738 | — | 1822.248 | 61757772 |
| Sort::Merge | native / native | test | 1 | 25.649 | 0.000 | — | 43.668 | 2548773 |
| Sort::Quick | c-wasm / v8 | run | 5 | 1492.043 | 18.113 | 0.660 | 1828.735 | 61757772 |
| Sort::Quick | c-wasm / v8 | test | 1 | 15.736 | 0.000 | 0.556 | 56.276 | 2548773 |
| Sort::Quick | c-wasm / wasmtime | run | 5 | 1730.859 | 22.226 | 25.506 | 2185.487 | 61757772 |
| Sort::Quick | c-wasm / wasmtime | test | 1 | 17.973 | 0.000 | 29.851 | 156.235 | 2548773 |
| Sort::Quick | direct / v8 | run | 5 | 1483.430 | 13.016 | 0.292 | 1840.820 | 61757772 |
| Sort::Quick | direct / v8 | test | 1 | 15.328 | 0.000 | 0.303 | 61.016 | 2548773 |
| Sort::Quick | direct / wasmtime | run | 5 | 1791.856 | 13.093 | 4.495 | 2248.512 | 61757772 |
| Sort::Quick | direct / wasmtime | test | 1 | 19.821 | 0.000 | 4.873 | 131.680 | 2548773 |
| Sort::Quick | native / native | run | 5 | 1320.652 | 19.487 | — | 1587.221 | 61757772 |
| Sort::Quick | native / native | test | 1 | 25.112 | 0.000 | — | 42.023 | 2548773 |

## Qualification and limits

- Seven adapted entrypoints (six change storage, one changes only the harness) are a subset of the 50-task catalog; they do not establish unmodified whole-suite Wasm support.
- No local result is a LangArena leaderboard rank: source/compiler versions, target layout, host, flags, and coverage differ.
- Cold builds retain OS and compiler system-library caches; they are complete uncached driver builds, not disk-cold experiments.

The full 50-task coverage matrix, raw commands/output, source and artifact hashes, tool versions, input values, environment overrides (including `EM_NODE_JS`), and phase timings are in `report.json` and adjacent logs. `Hash::SHA256` retains LangArena's custom hash workload; it is not standard cryptographic SHA-256.
