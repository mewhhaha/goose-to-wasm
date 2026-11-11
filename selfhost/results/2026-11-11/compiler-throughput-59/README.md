# Compiler throughput · snapshot 59

Snapshot 59 passed C-only fixed-point verification from snapshot 58's seed: the first generation of the new sources emitted C that compiled to a compiler reproducing `2e881d5667f95457427c1904bdac9d8586922082b810ff1b7b7b0ca37417d4c3` in its second and third generations. That C is the frozen seed. Two independent public output roots, one default and one with explicit options, then passed `--verify` with `profile_used: true` and produced executable SHA-256 `1306814006e915f95776d93f0a4daf9036fc449014438c06063a73c25517d73e`. Goose emission used `-O2`; native compilation used Clang 23, target `x86_64-pc-linux-gnu`, and `-std=gnu11 -O2 -lm -ldl -pthread`.

The IR profile SHA-256 is `be76be78eea90a8a392722acfa78ad2e32e65e53cd513e8280dc4148163da2b5`. It follows snapshot 58's protocol: the compiler compiling itself, plus two feature fixtures weighted 64, excluding the eleven timed programs. The plain and profiled builds each reproduce the seed C. [Training protocol](pgo/training-protocol.json) · [Script](pgo/pgo.sh)

## Contracts

The frozen suite passed 7,955 of 8,055 rows with GCC linking under `-Wl,--as-needed`, as Ubuntu's toolchain does by default. All 8,055 rows match a snapshot 58 run in status, phase, output, exit and diagnostic comparison, and `--known-gaps tests/conformance/known-gaps.json` accepts the run: the failures are exactly the 100 recorded gaps. Snapshot 58 failed two further rows under `--as-needed` (`fabs` and `fmod` externs), which CI reported. The curated corpus passed 4,780 checks on V8: 3,370 Wasm and 1,410 native. `native/storage.h` and the runtime headers are unchanged since these runs: all 45 native runtime checks passed. The 16 stack-guard profiles passed for both snapshot 58's and this `native/storage.h`; the fixture now expects `g_runtime_start` to read the main thread's stack bounds, and worker threads still read theirs on their first check. Forty-eight unit tests passed, including the known-gap gate. The ten examples ran correctly as Wasm under Node and as native executables.

Lexer token streams are byte-identical to snapshot 58's for 5,193 source files, including invalid programs.

## Behavior change

Modules resolved through `--stdlib` are libraries. Their function bodies are lexed and parsed when the checker first reaches them, their signatures are prepared on first lookup, and unreached library functions are no longer checked. An error inside an unused library function is therefore not reported; the previous C++ compiler and snapshot 58 report it. User sources, including unused user functions, are checked as before. No frozen contract row changed.

[Summary and identities](summary.json) · [Conformance](conformance.json.gz) · [V8 corpus](conformance-v8-corpus.json.gz) · [Snapshot 58 baseline run](conformance-parent-58.json.gz) · [Native checks](native-checks.json) · [Stack guards](stack-guard/report.json) · [Benchmark results and method](../../../../bench/results/2026-11-11/compiler-throughput-59/README.md)
