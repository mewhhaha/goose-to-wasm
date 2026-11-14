# Native C units · 2026-11-14

Generated C now also builds as several translation units ([`native/units.h`](../../../../native/units.h)). Compiled as it is, the file is still one unit with the runtime embedded, and single-unit object code is unchanged: Tour, Functions and VM compile to identical Clang 23 `-O2` machine code with the base and branch compilers. With `-DG_RUNTIME_UNIT` it compiles only the vendored runtime body, which `scripts/goose_wasm.py` caches per runtime text, C compiler and flags. With `-DG_UNITS=n -DG_UNIT=k` it compiles program unit k: functions fall into 840 byte-balanced slices in emission order, unit 0 defines the shared state, and functions named only within their own unit stay static.

The compiler's own C now builds 6.1× faster with 16 units on this 8-core machine, at the cost of 2.4% more executed instructions in the resulting compiler. With the runtime object cached, the ten examples' C compiles 4–37% faster with GCC and 5–28% with Clang. The release bootstrap keeps one unit; its supplied profile no longer matches the changed C, as after any backend change, until the next snapshot retrains it.

## Identities

| Item | Identity |
| --- | --- |
| Base | `f3b4248` (`big-workload-parse`); compiler `d895e60309d7df038025c67cf852354d5ca5fb215e7db91b45dd6c6a118bc9fe`, C `ba40059e…81c4`, no profile |
| Branch | `feature/parallel-native-build`, rebased on `f3b4248`; compiler `98c29f823c65b5ff40485154b7b4224992bcba0baea5de77a92509b757c391bd`, fixed-point C `d039db12fb29443fa4c738128d495c9401936365e3cf85d76455ce48a768f64c`, no profile |
| Selfhost C | branch compiler, `selfhost/main.goose -O2`: 40,741,763 bytes, 1,337 functions, 2,422,372-byte prelude, SHA-256 `86ae33b930a2caba73f0144bfca7f94e20e8deeb9e107e6f3db95d9f13bcaf30` |
| C compilers | Clang 23.1.4 (`clang-23` `3e9abb62…036d`), GCC 16.2.1 (`b0b49531…a145`) |
| Machine | AMD Ryzen 7 3800X, 8 cores / 16 threads, Linux 7.3.0-4-cachyos |

Flags throughout are `-std=gnu11 -O2 -fno-strict-aliasing -ffp-contract=off`. Other agents shared the machine; each sample records the 1-minute load average at its start (3.5–11.8 for the published runs). Configurations ran in interleaved rounds, alternating order.

## Building the compiler's C

Three rounds with Clang. Unit builds compile the runtime unit alongside, uncached, then link; linking took 0.05–0.08 s. [Raw](selfhost-build.json)

| Units | Wall (s) | Median wall | Median user CPU | Speedup |
| --- | --- | ---: | ---: | ---: |
| 1 (today) | 99.7, 88.1, 97.9 | 97.9 s | 96.8 s | 1.0× |
| 4 | 30.4, 28.9, 32.2 | 30.4 s | 100.8 s | 3.2× |
| 8 | 19.0, 17.7, 19.3 | 19.0 s | 123.0 s | 5.2× |
| 16 | 16.1, 16.3, 16.0 | 16.1 s | 161.7 s | 6.1× |

The largest functions bound the wall time; user CPU grows past 8 units because two compilers share each core. `goose_wasm.py` picks one unit per 2 MiB of function C, at most one per CPU: 16 here.

## Running the split-built compiler

`goose selfhost/main.goose --stdlib stdlib --target native --check` on the frozen `f3b4248` sources, five rounds. Instructions and cycles are user-space counts from `perf_event_open`; instruction counts repeated exactly. [Raw](selfhost-runtime.json)

| Units | Median wall | Median user | Instructions | Paired median wall / user ratio |
| --- | ---: | ---: | ---: | ---: |
| 1 | 26.13 s | 25.98 s | 126.088 G | — |
| 4 | 28.09 s | 27.90 s | 129.014 G (+2.32%) | 1.015 / 1.015 |
| 8 | 28.04 s | 27.86 s | 129.065 G (+2.36%) | 1.029 / 1.031 |
| 16 | 28.66 s | 28.43 s | 129.070 G (+2.36%) | 1.016 / 1.015 |

Per-round ratios ranged from 0.81 to 1.37 as load changed, so the timings resolve no more than a few percent; the instruction counts put the cost at about 2.4% regardless of unit count.

## Example builds

`python3 scripts/goose_wasm.py build examples/X.goose --backend native`, median C compile and total milliseconds. *Before* is the base compiler and script; *one unit* is `--jobs 1`; *cold* is the default with an empty runtime cache, *warm* with the runtime object cached. GCC is the script's default C compiler: five rounds, load 4.3–7.5. Clang: three rounds, load 3.5–6.3. [GCC raw](examples-gcc.json) · [Clang raw](examples-clang.json)

| Example | GCC before | one unit | cold | warm | Clang before | cold | warm |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| squares | 242 / 253 | 239 / 251 | 808 / 821 | 153 / 166 | 177 / 186 | 454 / 466 | 128 / 138 |
| tour | 978 / 992 | 979 / 994 | 807 / 823 | 768 / 783 | 550 / 561 | 456 / 470 | 414 / 427 |
| functions | 1,869 / 1,897 | 1,882 / 1,912 | 1,690 / 1,721 | 1,671 / 1,702 | 1,045 / 1,069 | 907 / 935 | 872 / 901 |
| errors | 790 / 806 | 788 / 804 | 799 / 817 | 700 / 717 | 387 / 401 | 459 / 475 | 340 / 354 |
| sieve | 408 / 421 | 406 / 419 | 801 / 815 | 314 / 328 | 276 / 287 | 456 / 468 | 221 / 233 |
| sorting | 2,110 / 2,137 | 2,124 / 2,157 | 2,049 / 2,081 | 2,025 / 2,057 | 1,097 / 1,123 | 1,058 / 1,086 | 1,041 / 1,071 |
| sudoku | 480 / 494 | 486 / 500 | 805 / 820 | 390 / 405 | 276 / 287 | 454 / 466 | 224 / 237 |
| maze | 828 / 845 | 831 / 849 | 801 / 819 | 733 / 751 | 444 / 458 | 451 / 468 | 398 / 414 |
| vm | 927 / 941 | 920 / 936 | 834 / 853 | 826 / 842 | 421 / 434 | 455 / 469 | 370 / 384 |
| life | 544 / 559 | 545 / 559 | 806 / 821 | 453 / 469 | 326 / 337 | 453 / 466 | 280 / 294 |

A warm build skips the runtime body, saving 85–210 ms with GCC and 46–173 ms with Clang; Tour and Functions save the most. The first build per C compiler, flags and runtime text compiles the runtime unit in parallel, about 0.8 s with GCC and 0.45 s with Clang, so it is slower for the smallest programs. `--no-cache`, which the benchmark campaigns use, keeps a program that needs one unit on the single-unit path, so their example artifacts are unchanged.

## What changed

- **Units in one file.** `units.h` defines the unit macros. Mutable state in `storage.h`, `threads.h`, the defer unwinding target and generated globals, queues and thread instances is `G_SHARED`: static in one unit, defined hidden by unit 0 and declared hidden elsewhere. `runtime.h`'s static `gs_gl` is renamed to one shared variable. Per-type helpers stay static in every unit.
- **Runtime unit.** It is `runtime.h` in its `GS_RUNTIME_OBJECT` configuration plus the runtime body, as `native/pack.py --section object` assembles it, but taken from the generated file's own text, so a program never links a runtime from another compiler. `runtime_unit.h` exposes what the body keeps static and program units use: the region registry, the span depth and `gs_float_digits`. The program side keeps its own `GS_NEED_THREADS`, so programs without threads keep non-thread-local state. The vendored runtime is byte-identical.
- **Tools.** `goose_wasm.py build --jobs N|auto`, `--cache-dir`; the driver's `--run` compiles C with at least two units' worth of functions as concurrent shell jobs; `scripts/bootstrap.py --jobs N` splits C that carries unit marks, without the profile, for development; `tests/conformance.py --native-units N`.

## Rejected experiments

Collected on 2026-11-13 before rebasing, with the `e6248ea` sources as the frozen `--check` workload, under load 15–34; instruction counts. [Data](experiments.json)

- **Every program function hidden extern.** 8 units executed 4.4% more instructions. Keeping functions named only within their own unit static (`G_LOCAL`) brought it to 3.1%, independent of 4, 8 or 16 units.
- **Static copies of small functions in each calling unit.** Functions up to 4 KiB of C, named across units, were compiled static in every unit between their first and last caller: 3.06–3.09% for 4–16 units, no gain over 3.10% without copies, while 63–180 functions compiled in more than one unit. Removed in `4007421`.
- **Where the rest goes.** One unit beside the runtime unit executes exactly as many instructions as today's single unit. One translation unit with all shared state non-static executes 2.41% more; with only the program's globals non-static, 0.81%; with only `storage.h`'s, none. The cost is the optimizer's lost knowledge of static state, which hidden linkage cannot restore; ThinLTO might, and was not tried.
- **Compiling the runtime unit from the whole file.** Skipping the 39 MB program text took 1.04 s against 0.76 s for the runtime prefix alone, so the tools compile the prefix.

## Validation

On the rebased branch: `scripts/bootstrap.py --verify` reached a fixed point (`d039db12…f64c`, next and third generations equal). The conformance suite at levels 0 and 2 passed 8,288 of 8,384 rows with GCC, failing exactly the 96 recorded gaps, both as one unit and with `--native-units 3`, where all 2,030 native builds compiled as a runtime unit and three program units. `native/tests/check.py` passed 50 of 50 checks, including the runtime unit against `pack.py`'s object section. `tests/test_native_units.py`, `test_driver_outputs.py`, `test_cli_outputs.py`, `test_conformance_runner.py` and `test_bootstrap_optimization.py` passed. The driver's `--run` built the compiler itself as 16 units and a runtime unit with GCC, and that compiler built and ran Squares correctly.
