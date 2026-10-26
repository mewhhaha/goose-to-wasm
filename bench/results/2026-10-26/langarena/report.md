# LangArena qualification and measurements

Status: **passed-with-explicit-whole-suite-refusals**.

Upstream pin: `aab9b14998231ba905523b5ba3990ee03c46f64d`. Catalog: **50 tasks**. Adapted entrypoints: **7 tasks**, including six storage adaptations.

Mode: `measure`. Machine: AMD EPYC 9V74 (KVM guest, 9 logical CPUs, 9.7 GiB RAM).
Compiler SHA-256: `ec5eee733cff680e730a7ff6e7b1fc80aabe868b0140c9bc696cbfc5bef75060`.

## Measurement contract

Whole-suite results use all original Goose kernel sources. The only staging patch changes the marker destination from `/tmp/recompile_marker` to a relative file inside the isolated run directory. The original checkout is hash-verified and never edited. Whole-suite compile times include all 50 tasks.

The adapted track uses the same seven port sources across native C, direct Wasm, and C-Wasm. Six ports replace growable storage; Fannkuch keeps its original fixed-array kernel. Official test/run inputs and checksums are unchanged. Preparation stays outside the clock; warmups mutate the same state used for measurement; the deterministic RNG is reset before measured iterations. Existing checksum work retains its original placement.

Cold builds and marker-edit builds launch fresh driver/compiler processes with `--no-cache`. OS caches and installed compiler/system-library caches are retained. A port marker edit changes its exit status from 0 to 1 after its two output lines, and the edited executable must retain the official checksum. Whole-suite edits change the actual marker file contents. Source bytes are restored in all cases. Optional unchanged cache hits are a separate phase. Edited sources still rerun the complete frontend.

The official whole-suite timer prints milliseconds; adapted ports print integer nanoseconds. Timed regions exclude process startup and preparation. Process wall time is retained separately. Sample counts below five are preliminary estimates; raw values and MAD are provided. These are local comparisons, not LangArena leaderboard scores or claims of complete direct-backend language support.

## Whole-suite compilation

| Backend | Phase | Samples | Median ms | MAD ms | Artifact bytes |
| --- | --- | ---: | ---: | ---: | ---: |
| native | cold | 3 | 10379.576 | 502.448 | 352344 |
| native | marker-edit | 3 | 9024.814 | 71.314 | 352344 |

- **direct unavailable:** /workspace/scratch/ac45bbbd0688/goose-to-wasm/build/bin/stdlib/os.goose:57: error: wasm-direct: only fixed-size owned arrays are supported; resizable arrays require the C oracle target. Full diagnostic is in the raw report. No successful compile-time score is assigned.

- **c-wasm unavailable:** WebAssembly target does not support threads or typed queues; this target uses one isolated linear memory. Full diagnostic is in the raw report. No successful compile-time score is assigned.

## Original-source correctness and runtime

| Task | Backend / engine | Profile | Samples | Region median ms | MAD ms | Process median ms |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Base64::Decode | native / native | run | 3 | 1965.000 | 6.000 | 2362.177 |
| Base64::Decode | native / native | test | 1 | 0.000 | 0.000 | 3.564 |
| Base64::Encode | native / native | run | 3 | 2267.000 | 118.000 | 2744.966 |
| Base64::Encode | native / native | test | 1 | 0.000 | 0.000 | 3.715 |
| Binarytrees::Arena | native / native | run | 3 | 297.000 | 35.000 | 384.511 |
| Binarytrees::Arena | native / native | test | 1 | 0.000 | 0.000 | 3.662 |
| Binarytrees::Obj | native / native | run | 3 | 222.000 | 2.000 | 277.241 |
| Binarytrees::Obj | native / native | test | 1 | 0.000 | 0.000 | 3.435 |
| Brainfuck::Array | native / native | run | 3 | 1462.000 | 11.000 | 1468.242 |
| Brainfuck::Array | native / native | test | 1 | 0.000 | 0.000 | 3.272 |
| Brainfuck::Recursion | native / native | run | 3 | 1711.000 | 37.000 | 1718.792 |
| Brainfuck::Recursion | native / native | test | 1 | 0.000 | 0.000 | 4.454 |
| CLBG::Fannkuchredux | native / native | run | 3 | 1427.000 | 17.000 | 1744.471 |
| CLBG::Fannkuchredux | native / native | test | 1 | 0.000 | 0.000 | 3.846 |
| CLBG::Mandelbrot | native / native | run | 3 | 1329.000 | 19.000 | 1589.811 |
| CLBG::Mandelbrot | native / native | test | 1 | 0.000 | 0.000 | 4.378 |
| CLBG::Nbody | native / native | run | 3 | 1575.000 | 38.000 | 1892.734 |
| CLBG::Nbody | native / native | test | 1 | 0.000 | 0.000 | 2.990 |
| CLBG::Spectralnorm | native / native | run | 3 | 1380.000 | 24.000 | 1669.013 |
| CLBG::Spectralnorm | native / native | test | 1 | 0.000 | 0.000 | 4.134 |
| CSV::Parse | native / native | run | 3 | 492.000 | 2.000 | 634.823 |
| CSV::Parse | native / native | test | 1 | 0.000 | 0.000 | 3.106 |
| Calculator::Ast | native / native | run | 3 | 201.000 | 6.000 | 244.362 |
| Calculator::Ast | native / native | test | 1 | 0.000 | 0.000 | 2.957 |
| Calculator::Interpreter | native / native | run | 3 | 481.000 | 15.000 | 604.829 |
| Calculator::Interpreter | native / native | test | 1 | 0.000 | 0.000 | 3.361 |
| Compress::ArithDecode | native / native | run | 3 | 939.000 | 2.000 | 1158.532 |
| Compress::ArithDecode | native / native | test | 1 | 0.000 | 0.000 | 3.489 |
| Compress::ArithEncode | native / native | run | 3 | 1122.000 | 119.000 | 1339.321 |
| Compress::ArithEncode | native / native | test | 1 | 0.000 | 0.000 | 3.060 |
| Compress::BWTDecode | native / native | run | 3 | 629.000 | 40.000 | 1047.949 |
| Compress::BWTDecode | native / native | test | 1 | 0.000 | 0.000 | 2.692 |
| Compress::BWTEncode | native / native | run | 3 | 522.000 | 12.000 | 619.881 |
| Compress::BWTEncode | native / native | test | 1 | 0.000 | 0.000 | 2.957 |
| Compress::HuffDecode | native / native | run | 3 | 749.000 | 66.000 | 919.965 |
| Compress::HuffDecode | native / native | test | 1 | 0.000 | 0.000 | 3.647 |
| Compress::HuffEncode | native / native | run | 3 | 663.000 | 53.000 | 802.617 |
| Compress::HuffEncode | native / native | test | 1 | 0.000 | 0.000 | 3.323 |
| Compress::LZWDecode | native / native | run | 3 | 189.000 | 14.000 | 412.704 |
| Compress::LZWDecode | native / native | test | 1 | 0.000 | 0.000 | 3.074 |
| Compress::LZWEncode | native / native | run | 3 | 634.000 | 21.000 | 786.416 |
| Compress::LZWEncode | native / native | test | 1 | 0.000 | 0.000 | 3.623 |
| Distance::Jaro | native / native | run | 3 | 1104.000 | 24.000 | 1334.540 |
| Distance::Jaro | native / native | test | 1 | 0.000 | 0.000 | 2.909 |
| Distance::NGram | native / native | run | 3 | 361.000 | 27.000 | 440.186 |
| Distance::NGram | native / native | test | 1 | 0.000 | 0.000 | 3.185 |
| Etc::CacheSimulation | native / native | run | 3 | 1700.000 | 4.000 | 2058.437 |
| Etc::CacheSimulation | native / native | test | 1 | 0.000 | 0.000 | 3.670 |
| Etc::GameOfLife | native / native | run | 3 | 732.000 | 6.000 | 899.972 |
| Etc::GameOfLife | native / native | test | 1 | 0.000 | 0.000 | 4.220 |
| Etc::LogParser | native / native | run | 3 | 206.000 | 11.000 | 266.027 |
| Etc::LogParser | native / native | test | 1 | 0.000 | 0.000 | 2.952 |
| Etc::NeuralNet | native / native | run | 3 | 1134.000 | 9.000 | 1382.357 |
| Etc::NeuralNet | native / native | test | 1 | 1.000 | 0.000 | 4.651 |
| Etc::Sieve | native / native | run | 3 | 1968.000 | 8.000 | 2300.116 |
| Etc::Sieve | native / native | test | 1 | 0.000 | 0.000 | 3.013 |
| Etc::TextRaytracer | native / native | run | 3 | 1534.000 | 24.000 | 1851.856 |
| Etc::TextRaytracer | native / native | test | 1 | 1.000 | 0.000 | 5.507 |
| Etc::Words | native / native | run | 3 | 608.000 | 50.000 | 733.331 |
| Etc::Words | native / native | test | 1 | 0.000 | 0.000 | 3.677 |
| Graph::AStar | native / native | run | 3 | 1059.000 | 93.000 | 2703.612 |
| Graph::AStar | native / native | test | 1 | 0.000 | 0.000 | 2.957 |
| Graph::BFS | native / native | run | 3 | 1837.000 | 126.000 | 3560.565 |
| Graph::BFS | native / native | test | 1 | 0.000 | 0.000 | 3.937 |
| Graph::DFS | native / native | run | 3 | 1529.000 | 0.000 | 3165.286 |
| Graph::DFS | native / native | test | 1 | 0.000 | 0.000 | 4.099 |
| Hash::CRC32 | native / native | run | 3 | 1576.000 | 9.000 | 1895.980 |
| Hash::CRC32 | native / native | test | 1 | 0.000 | 0.000 | 3.801 |
| Hash::SHA256 | native / native | run | 3 | 613.000 | 2.000 | 745.715 |
| Hash::SHA256 | native / native | test | 1 | 0.000 | 0.000 | 3.019 |
| Json::Generate | native / native | run | 3 | 367.000 | 4.000 | 444.816 |
| Json::Generate | native / native | test | 1 | 0.000 | 0.000 | 3.145 |
| Json::ParseDom | native / native | run | 3 | 156.000 | 0.000 | 191.266 |
| Json::ParseDom | native / native | test | 1 | 0.000 | 0.000 | 4.194 |
| Json::ParseMapping | native / native | run | 3 | 460.000 | 37.000 | 558.263 |
| Json::ParseMapping | native / native | test | 1 | 0.000 | 0.000 | 3.640 |
| Matmul::Single | native / native | run | 3 | 7692.000 | 193.000 | 9266.861 |
| Matmul::Single | native / native | test | 1 | 0.000 | 0.000 | 3.860 |
| Matmul::T16 | native / native | run | 3 | 1400.000 | 8.000 | 1772.189 |
| Matmul::T16 | native / native | test | 1 | 0.000 | 0.000 | 13.588 |
| Matmul::T4 | native / native | run | 3 | 2475.000 | 40.000 | 2986.465 |
| Matmul::T4 | native / native | test | 1 | 0.000 | 0.000 | 6.165 |
| Matmul::T8 | native / native | run | 3 | 1365.000 | 11.000 | 1681.522 |
| Matmul::T8 | native / native | test | 1 | 2.000 | 0.000 | 13.713 |
| Maze::AStar | native / native | run | 3 | 1497.000 | 22.000 | 1987.846 |
| Maze::AStar | native / native | test | 1 | 0.000 | 0.000 | 10.856 |
| Maze::BFS | native / native | run | 3 | 552.000 | 11.000 | 845.101 |
| Maze::BFS | native / native | test | 1 | 0.000 | 0.000 | 3.867 |
| Maze::Generator | native / native | run | 3 | 514.000 | 7.000 | 785.183 |
| Maze::Generator | native / native | test | 1 | 0.000 | 0.000 | 3.861 |
| Sort::Merge | native / native | run | 3 | 1843.000 | 45.000 | 2216.001 |
| Sort::Merge | native / native | test | 1 | 15.000 | 0.000 | 27.311 |
| Sort::Quick | native / native | run | 3 | 1446.000 | 65.000 | 1768.924 |
| Sort::Quick | native / native | test | 1 | 15.000 | 0.000 | 27.229 |
| Sort::Self | native / native | run | 3 | 479.000 | 18.000 | 577.186 |
| Sort::Self | native / native | test | 1 | 5.000 | 0.000 | 11.554 |
| Template::Parse | native / native | run | 3 | 918.000 | 14.000 | 1199.518 |
| Template::Parse | native / native | test | 1 | 0.000 | 0.000 | 3.214 |
| Template::Regex | native / native | run | 3 | 1479.000 | 127.000 | 1829.361 |
| Template::Regex | native / native | test | 1 | 0.000 | 0.000 | 3.455 |

## Adapted workload compilation

| Task | Backend | Phase | Samples | Median ms | MAD ms | Artifact bytes |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| CLBG::Fannkuchredux | c-wasm | cold | 3 | 860.534 | 18.440 | 51983 |
| CLBG::Fannkuchredux | c-wasm | marker-edit | 3 | 624.635 | 16.653 | 51909 |
| CLBG::Fannkuchredux | direct | cold | 3 | 73.223 | 3.328 | 4029 |
| CLBG::Fannkuchredux | direct | marker-edit | 3 | 62.973 | 0.880 | 4035 |
| CLBG::Fannkuchredux | native | cold | 3 | 380.828 | 34.802 | 22792 |
| CLBG::Fannkuchredux | native | marker-edit | 3 | 335.509 | 16.754 | 22792 |
| CLBG::Mandelbrot | c-wasm | cold | 3 | 937.476 | 25.708 | 52059 |
| CLBG::Mandelbrot | c-wasm | marker-edit | 3 | 725.000 | 69.620 | 51987 |
| CLBG::Mandelbrot | direct | cold | 3 | 83.154 | 2.625 | 2405955 |
| CLBG::Mandelbrot | direct | marker-edit | 3 | 71.370 | 3.556 | 2405961 |
| CLBG::Mandelbrot | native | cold | 3 | 436.657 | 14.249 | 27184 |
| CLBG::Mandelbrot | native | marker-edit | 3 | 310.714 | 15.264 | 27184 |
| Etc::Sieve | c-wasm | cold | 3 | 824.399 | 12.721 | 51597 |
| Etc::Sieve | c-wasm | marker-edit | 3 | 667.906 | 26.645 | 51543 |
| Etc::Sieve | direct | cold | 3 | 84.535 | 0.920 | 3003863 |
| Etc::Sieve | direct | marker-edit | 3 | 75.202 | 3.147 | 3003869 |
| Etc::Sieve | native | cold | 3 | 345.337 | 52.039 | 22960 |
| Etc::Sieve | native | marker-edit | 3 | 298.569 | 26.954 | 22960 |
| Hash::CRC32 | c-wasm | cold | 3 | 724.512 | 8.860 | 51817 |
| Hash::CRC32 | c-wasm | marker-edit | 3 | 634.285 | 62.152 | 51766 |
| Hash::CRC32 | direct | cold | 3 | 85.837 | 12.512 | 1003420 |
| Hash::CRC32 | direct | marker-edit | 3 | 60.629 | 0.117 | 1003426 |
| Hash::CRC32 | native | cold | 3 | 328.236 | 9.688 | 22728 |
| Hash::CRC32 | native | marker-edit | 3 | 280.966 | 12.821 | 22728 |
| Hash::SHA256 | c-wasm | cold | 3 | 764.445 | 29.553 | 51826 |
| Hash::SHA256 | c-wasm | marker-edit | 3 | 650.577 | 42.800 | 51749 |
| Hash::SHA256 | direct | cold | 3 | 74.457 | 4.220 | 1005526 |
| Hash::SHA256 | direct | marker-edit | 3 | 64.489 | 2.114 | 1005532 |
| Hash::SHA256 | native | cold | 3 | 371.955 | 12.777 | 22728 |
| Hash::SHA256 | native | marker-edit | 3 | 415.877 | 54.792 | 22728 |
| Sort::Merge | c-wasm | cold | 3 | 836.571 | 22.725 | 52484 |
| Sort::Merge | c-wasm | marker-edit | 3 | 650.405 | 18.189 | 52434 |
| Sort::Merge | direct | cold | 3 | 93.925 | 10.191 | 4806807 |
| Sort::Merge | direct | marker-edit | 3 | 76.709 | 1.355 | 4806813 |
| Sort::Merge | native | cold | 3 | 398.036 | 4.443 | 27288 |
| Sort::Merge | native | marker-edit | 3 | 347.061 | 15.792 | 27328 |
| Sort::Quick | c-wasm | cold | 3 | 1074.947 | 81.923 | 52043 |
| Sort::Quick | c-wasm | marker-edit | 3 | 646.304 | 3.246 | 51991 |
| Sort::Quick | direct | cold | 3 | 80.834 | 3.914 | 3205746 |
| Sort::Quick | direct | marker-edit | 3 | 73.684 | 3.554 | 3205752 |
| Sort::Quick | native | cold | 3 | 414.291 | 86.356 | 23000 |
| Sort::Quick | native | marker-edit | 3 | 313.686 | 3.223 | 23032 |

## Adapted workload runtime

| Task | Backend / engine | Profile | Samples | Region median ms | MAD ms | Engine compile + instantiate ms | Process median ms | Checksum |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| CLBG::Fannkuchredux | c-wasm / v8 | run | 3 | 2368.881 | 42.385 | 0.919 | 2864.949 | 135762480 |
| CLBG::Fannkuchredux | c-wasm / v8 | test | 1 | 0.024 | 0.000 | 1.486 | 50.469 | 4428 |
| CLBG::Fannkuchredux | c-wasm / wasmtime | run | 3 | 1568.674 | 28.939 | 24.821 | 2015.861 | 135762480 |
| CLBG::Fannkuchredux | c-wasm / wasmtime | test | 1 | 0.035 | 0.000 | 29.090 | 122.783 | 4428 |
| CLBG::Fannkuchredux | direct / v8 | run | 3 | 1475.269 | 33.423 | 0.681 | 1848.004 | 135762480 |
| CLBG::Fannkuchredux | direct / v8 | test | 1 | 0.025 | 0.000 | 0.625 | 37.342 | 4428 |
| CLBG::Fannkuchredux | direct / wasmtime | run | 3 | 1597.349 | 129.012 | 4.631 | 2044.485 | 135762480 |
| CLBG::Fannkuchredux | direct / wasmtime | test | 1 | 0.019 | 0.000 | 4.185 | 86.766 | 4428 |
| CLBG::Fannkuchredux | native / native | run | 3 | 1659.398 | 28.284 | — | 1952.746 | 135762480 |
| CLBG::Fannkuchredux | native / native | test | 1 | 0.013 | 0.000 | — | 2.509 | 4428 |
| CLBG::Mandelbrot | c-wasm / v8 | run | 3 | 1273.182 | 54.831 | 1.308 | 1632.494 | 3455988829 |
| CLBG::Mandelbrot | c-wasm / v8 | test | 1 | 0.516 | 0.000 | 0.848 | 42.211 | 2236342953 |
| CLBG::Mandelbrot | c-wasm / wasmtime | run | 3 | 1323.466 | 7.737 | 29.102 | 1715.105 | 3455988829 |
| CLBG::Mandelbrot | c-wasm / wasmtime | test | 1 | 0.255 | 0.000 | 27.332 | 126.019 | 2236342953 |
| CLBG::Mandelbrot | direct / v8 | run | 3 | 1249.955 | 11.719 | 2.946 | 1583.076 | 3455988829 |
| CLBG::Mandelbrot | direct / v8 | test | 1 | 0.416 | 0.000 | 2.844 | 49.097 | 2236342953 |
| CLBG::Mandelbrot | direct / wasmtime | run | 3 | 1148.172 | 22.612 | 7.940 | 1467.841 | 3455988829 |
| CLBG::Mandelbrot | direct / wasmtime | test | 1 | 0.182 | 0.000 | 7.058 | 115.484 | 2236342953 |
| CLBG::Mandelbrot | native / native | run | 3 | 1239.791 | 18.148 | — | 1481.330 | 3455988829 |
| CLBG::Mandelbrot | native / native | test | 1 | 0.165 | 0.000 | — | 12.238 | 2236342953 |
| Etc::Sieve | c-wasm / v8 | run | 3 | 3016.224 | 91.742 | 0.958 | 3640.258 | 1042248060 |
| Etc::Sieve | c-wasm / v8 | test | 1 | 0.012 | 0.000 | 0.858 | 39.782 | 4660 |
| Etc::Sieve | c-wasm / wasmtime | run | 3 | 1840.075 | 85.794 | 35.411 | 2390.983 | 1042248060 |
| Etc::Sieve | c-wasm / wasmtime | test | 1 | 0.042 | 0.000 | 29.075 | 123.919 | 4660 |
| Etc::Sieve | direct / v8 | run | 3 | 8356.902 | 281.897 | 3.677 | 10133.963 | 1042248060 |
| Etc::Sieve | direct / v8 | test | 1 | 0.023 | 0.000 | 3.007 | 44.845 | 4660 |
| Etc::Sieve | direct / wasmtime | run | 3 | 2142.250 | 55.328 | 9.467 | 2830.559 | 1042248060 |
| Etc::Sieve | direct / wasmtime | test | 1 | 0.051 | 0.000 | 9.721 | 107.846 | 4660 |
| Etc::Sieve | native / native | run | 3 | 1526.761 | 15.590 | — | 1818.805 | 1042248060 |
| Etc::Sieve | native / native | test | 1 | 0.005 | 0.000 | — | 4.513 | 4660 |
| Hash::CRC32 | c-wasm / v8 | run | 3 | 440.995 | 7.971 | 1.125 | 586.543 | 2318723244 |
| Hash::CRC32 | c-wasm / v8 | test | 1 | 0.016 | 0.000 | 0.831 | 44.198 | 3031698216 |
| Hash::CRC32 | c-wasm / wasmtime | run | 3 | 468.416 | 15.303 | 33.425 | 714.185 | 2318723244 |
| Hash::CRC32 | c-wasm / wasmtime | test | 1 | 0.036 | 0.000 | 33.661 | 122.970 | 3031698216 |
| Hash::CRC32 | direct / v8 | run | 3 | 8559.164 | 578.952 | 1.574 | 10285.707 | 2318723244 |
| Hash::CRC32 | direct / v8 | test | 1 | 0.179 | 0.000 | 1.416 | 45.687 | 3031698216 |
| Hash::CRC32 | direct / wasmtime | run | 3 | 5044.109 | 54.360 | 6.228 | 6072.298 | 2318723244 |
| Hash::CRC32 | direct / wasmtime | test | 1 | 0.089 | 0.000 | 5.720 | 98.866 | 3031698216 |
| Hash::CRC32 | native / native | run | 3 | 1481.173 | 48.932 | — | 1774.623 | 2318723244 |
| Hash::CRC32 | native / native | test | 1 | 0.027 | 0.000 | — | 2.974 | 3031698216 |
| Hash::SHA256 | c-wasm / v8 | run | 3 | 1184.158 | 71.595 | 1.078 | 1484.118 | 2844672256 |
| Hash::SHA256 | c-wasm / v8 | test | 1 | 0.008 | 0.000 | 4.271 | 54.620 | 1036619072 |
| Hash::SHA256 | c-wasm / wasmtime | run | 3 | 1370.662 | 4.949 | 36.354 | 1811.959 | 2844672256 |
| Hash::SHA256 | c-wasm / wasmtime | test | 1 | 0.026 | 0.000 | 27.381 | 125.295 | 1036619072 |
| Hash::SHA256 | direct / v8 | run | 3 | 7969.271 | 60.213 | 1.308 | 9599.962 | 2844672256 |
| Hash::SHA256 | direct / v8 | test | 1 | 0.064 | 0.000 | 1.727 | 39.965 | 1036619072 |
| Hash::SHA256 | direct / wasmtime | run | 3 | 2086.634 | 20.584 | 7.778 | 2615.121 | 2844672256 |
| Hash::SHA256 | direct / wasmtime | test | 1 | 0.015 | 0.000 | 9.254 | 104.386 | 1036619072 |
| Hash::SHA256 | native / native | run | 3 | 621.585 | 1.781 | — | 758.434 | 2844672256 |
| Hash::SHA256 | native / native | test | 1 | 0.001 | 0.000 | — | 2.857 | 1036619072 |
| Sort::Merge | c-wasm / v8 | run | 3 | 1599.219 | 105.738 | 1.456 | 1966.389 | 61757772 |
| Sort::Merge | c-wasm / v8 | test | 1 | 18.279 | 0.000 | 4.830 | 92.076 | 2548773 |
| Sort::Merge | c-wasm / wasmtime | run | 3 | 2479.971 | 122.231 | 34.916 | 3093.744 | 61757772 |
| Sort::Merge | c-wasm / wasmtime | test | 1 | 22.851 | 0.000 | 30.921 | 167.646 | 2548773 |
| Sort::Merge | direct / v8 | run | 3 | 2412.795 | 66.410 | 5.518 | 2934.486 | 61757772 |
| Sort::Merge | direct / v8 | test | 1 | 23.208 | 0.000 | 4.936 | 92.613 | 2548773 |
| Sort::Merge | direct / wasmtime | run | 3 | 2290.512 | 108.243 | 17.465 | 2900.482 | 61757772 |
| Sort::Merge | direct / wasmtime | test | 1 | 22.642 | 0.000 | 18.029 | 153.313 | 2548773 |
| Sort::Merge | native / native | run | 3 | 1922.053 | 1.130 | — | 2289.963 | 61757772 |
| Sort::Merge | native / native | test | 1 | 16.110 | 0.000 | — | 31.669 | 2548773 |
| Sort::Quick | c-wasm / v8 | run | 3 | 1561.625 | 48.685 | 1.023 | 1911.698 | 61757772 |
| Sort::Quick | c-wasm / v8 | test | 1 | 15.663 | 0.000 | 0.762 | 73.866 | 2548773 |
| Sort::Quick | c-wasm / wasmtime | run | 3 | 1743.608 | 34.853 | 30.435 | 2248.483 | 61757772 |
| Sort::Quick | c-wasm / wasmtime | test | 1 | 20.725 | 0.000 | 28.497 | 174.235 | 2548773 |
| Sort::Quick | direct / v8 | run | 3 | 1599.034 | 20.977 | 3.338 | 1974.881 | 61757772 |
| Sort::Quick | direct / v8 | test | 1 | 14.154 | 0.000 | 3.573 | 75.851 | 2548773 |
| Sort::Quick | direct / wasmtime | run | 3 | 1879.305 | 86.714 | 10.974 | 2331.321 | 61757772 |
| Sort::Quick | direct / wasmtime | test | 1 | 16.473 | 0.000 | 10.812 | 162.578 | 2548773 |
| Sort::Quick | native / native | run | 3 | 1492.795 | 26.653 | — | 1841.033 | 61757772 |
| Sort::Quick | native / native | test | 1 | 15.258 | 0.000 | — | 28.038 | 2548773 |

## Qualification and limits

- Seven adapted entrypoints (six change storage, one changes only the harness) are a subset of the 50-task catalog; they do not establish unmodified whole-suite Wasm support.
- No local result is a LangArena leaderboard rank: source/compiler versions, target layout, host, flags, and coverage differ.
- Cold builds retain OS and compiler system-library caches; they are complete uncached driver builds, not disk-cold experiments.
- At least one sample count is below five. Medians and dispersion are preliminary.

The full 50-task coverage matrix, raw commands/output, source and artifact hashes, tool versions, input values, environment overrides (including `EM_NODE_JS`), and phase timings are in `report.json` and adjacent logs. `Hash::SHA256` retains LangArena's custom hash workload; it is not standard cryptographic SHA-256.
