# Compiler build and compile times

Three clean builds on a warm filesystem give these median wall times:

| Compiler build | Total | Components |
| --- | ---: | --- |
| C++ Release, Clang 23 `-O3`, two jobs | 60.673 s | 0.611 s configure, 60.069 s build |
| Goose, GCC 16 `-O0` (quick) | 2.336 s | 0.412 s Goose-to-C, 1.899 s GCC |
| Goose, GCC 16 `-O2` (optimized) | 9.465 s | 0.413 s Goose-to-C, 9.052 s GCC |

Component medians are independent and need not sum to the total. The C++ build includes JIT/TinyCC, shader, language server, and project features absent from the rewrite. The Goose build uses the frozen C++ compiler to bootstrap; it is not self-compilation, and native self-typechecking still reports 16 errors.

## Compiling examples

Median milliseconds to compile each example to direct Wasm at **source optimization `-O2`**. The Goose column labels refer instead to the GCC optimization used to build the compiler.

| Example | C++ | Goose quick | Goose optimized |
| --- | ---: | ---: | ---: |
| squares | 1.755 | 1.179 | 1.092 |
| tour | 3.689 | 3.031 | 1.746 |
| functions | 19.606 | 21.059 | 7.667 |
| errors | 8.248 | 9.177 | 3.741 |
| sieve | 6.104 | 6.584 | 2.869 |
| sorting | 25.033 | 24.421 | 8.885 |
| sudoku | 7.440 | 7.747 | 3.252 |
| maze | 10.335 | 9.960 | 3.952 |
| vm | 7.205 | 10.061 | 3.915 |
| life | 7.852 | 7.628 | 3.189 |

Across these examples, the optimized Goose compiler's geometric mean speedup over C++ is 2.24× at source `-O2` and 1.98× at `-O0`. The quick compiler is roughly level with C++ at source `-O2`. All 60 combinations of compiler, example and optimization level passed their runtime goldens. This is a limited comparison: Wasm bytes differ, the optimizers do different work, and the broader O0 corpus passed 409/950 full behavior checks.

Program measurements use 21 samples after two warmups, fresh compiler processes pinned to CPU 2, and a hot filesystem. They include startup, imports, checking, optimization, emission and output, but exclude the Python wrapper, engine preparation and execution. The final program cohort uses blocking waits with no timeout. Two earlier harness attempts were discarded for program timing; the completion audit found about 1 ms of timeout polling bias. The retained clean-build cohort has the same roughly 1 ms per-command bias, negligible at build times measured in seconds.

[Raw report](report.json) · [Evidence archive](evidence.tar.gz) · [SHA-256 inventory](SHA256.json)

Reproduce from the repository root with prepared tools and a fresh output directory:

```sh
source build/performance-env.sh
python selfhost/benchmark.py --output-dir /dev/shm/goose-compile-times-new
```
