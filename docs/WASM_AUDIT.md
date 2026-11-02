# Example Wasm audit

The ten examples are not yet optimal. This inspection starts from compiler SHA-256 `82b14bd7e795864606042853b13994e0fa8e6bddb22f02f9eef19d87849043e8` and examines the generated modules, opcode inventory and disassembly. A candidate specializes array-image access when the closed module permits only raw images. It removes the mode dispatches in eight examples; Tour retains its general image paths, and Squares had no dispatch to remove. Public exports and nonintrinsic user imports exclude this specialization so host memory edits remain authoritative; pure math intrinsics are allowed.

| Example | Baseline bytes | Candidate bytes |
| --- | ---: | ---: |
| Squares | 1,367 | 1,367 |
| Tour | 40,589 | 40,589 |
| Functions | 73,346 | 55,269 |
| Errors | 37,229 | 27,101 |
| Sieve | 16,860 | 7,410 |
| Sorting | 96,689 | 65,038 |
| Sudoku | 15,116 | 12,415 |
| Maze | 50,993 | 21,474 |
| VM | 48,133 | 29,290 |
| Life | 31,790 | 15,740 |

The total falls from 412,112 to 275,693 bytes, or 33.1%. These are static module sizes, not execution speedups. Nine paired fresh-instance entry probes used final compiler SHA-256 `78178c171d7ed846ac20aec7b54f5e2e80ffb5a73bbf3551c44b73b27b373624`. Paired median baseline/candidate ratios for Functions, Sieve and Maze were 2.673×, 2.047× and 4.789× on V8, and 1.027×, 1.527× and 1.123× on Wasmtime. The sub-0.2 ms Wasmtime cells are noisy: Functions and Maze had ratio MADs of 0.091 and 0.490. Sorting measured 1.240× on V8 and 1.194× on Wasmtime. Life's Wasmtime ratio was 1.041× (MAD 0.237), establishing no clear gain. Tour was unchanged in module size but its V8 paired ratio was 0.857× (MAD 0.100); treat this control as noise rather than an attributed gain. Entry includes initialization, callbacks and potentially lazy JIT work; it is not a pure kernel timing. All ten final modules match the preliminary, paired and example artifacts byte for byte.

The fresh process cohort measured Sorting at 107.472 ms with ordinary native-host compilation, 88.994 ms precompiled, and 45.807 ms native C. The separately measured precompiled preparation median was 30.805 ms. The baseline and fresh process cohorts were collected separately and do not establish a paired improvement. [Results and qualification](../bench/results/2026-11-02/raw-array-images/README.md) retain the evidence.

Squares folds its calculation to 140; Tour genuinely needs prefix modes. Functions, Errors, VM and Maze contain substantial emitted code where first-call compilation matters, while Sieve exercises array loops. Sorting's already four-way-unrolled insertion loop is 825 bytes and 460 operations with no branch tables. Sudoku's `count_bits` is 319 bytes and 158 operations, retaining a Kernighan loop without `popcnt`. Life's 555-byte neighbour function has two signed remainder operations, lowered to two `idiv` sites in the final Wasmtime AOT disassembly. Literal printing also allocates scratch space and copies immutable bytes; avoiding that remains an opportunity. Each hill needs semantic proof and measurement across engines.

The final candidate passed 9,573 differential observations, including 7,656 native stdout comparisons, and 48 focused commands. Native-host replay passed 11,484 observations over 3,828 case/backend/level units in default and serial Wasm and serial precompiled modes. Default precompiled mode passed twenty example artifacts and ten WAT methods across four modes separately, not the full replay.
