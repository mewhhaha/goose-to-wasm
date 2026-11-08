# Compiler throughput · snapshot 58

Snapshot 58 passed C-only fixed-point verification in two independent public output roots, one default and one explicit, both with `profile_used: true`. Both generated C SHA-256 `191a6b540a7c59ccdd0de5ac32199eea958bb19121cd98a1bfe269c13fc2aea6` and executable SHA-256 `9a0450a452f6dcc0c6ad698fdeb9af6be599c7e8ffdb2437364a6f360145489d`. Goose emission used `-O2`; native compilation used Clang 23, target `x86_64-pc-linux-gnu`, and `-std=gnu11 -O2 -lm -ldl -pthread`.

The optional IR profile SHA-256 is `52cc8e39bede489dd8388bd9ffd5a095846076a484eba1cf39880b5b71b57927`. It was trained on the compiler and two feature fixtures, excluding the eleven timed programs. Bootstrap requires matching C hash, target triple, Clang major, C basename, base flags and profile checksum. Missing or mismatched data, or a failed profile compilation, causes a recorded fallback to plain `-O2`. A C++ reference guided the initial port but was not used in bootstrap or contracts.

The frozen suite passed 7,955 of 8,055 rows. All 184 new rows passed on both engines; all 7,871 prior results and failure phases matched. The 100 unchanged gaps comprise six accepted invalid programs and 94 runtime contracts rejected during compilation. The curated corpus passed 3,370 Wasm checks in each of Wasmtime and V8 plus 1,410 native controls. All 45 native runtime checks and 16 stack-guard profiles passed. These contracts cover selected programs and behaviors; actual Tiny C compiler coverage was unavailable.

[Summary and identities](summary.json) · [Reproduction capsule](reproduction.tar.gz) · [Benchmark results and method](../../../../bench/results/2026-11-08/compiler-throughput-58/README.md)

The capsule preserves qualification reports, source and compiler identities, accepted changes, rejected experiments and their tradeoffs. The native stack-position change retains its fallback on unsupported targets and preserves stack protection; the guard profiles cover Clang and GCC, optimization levels, sanitizers and forced fallback. Compiler construction timings were collected alongside parallel builds and do not establish isolated build-time comparisons.
