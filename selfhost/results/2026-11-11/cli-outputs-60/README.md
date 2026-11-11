# Output path checks · snapshot 60

Snapshot 60 refuses compiler outputs that would replace a source, an embedded file, or another output (issue #6). `-o`, `--wasm-stats` and `--wasm-deps` are compared against every loaded source and against each other before anything is written. Paths compare in the normalized form the compiler records sources in. An absolute spelling of a relative source path is not recognized, because the runtime has no `realpath` or `stat` primitive; `scripts/goose_wasm.py` also compares with `samefile`.

The C-only bootstrap from snapshot 59's seed reached a fixed point at C SHA-256 `740403169d5cb0a457d27b5a3d5ffa2da0451d192b67995fbe19d83f15e148f2`. The Clang 23 profile was retrained with snapshot 58's protocol (`31165bc6d449307d4d824c90b417d97d718cc9deef11757d4399b6797141922a`). The default and explicit-option public roots both passed `--verify` with `profile_used: true` and produced executable `1c9e0fab8cddc9fcc8ba9be0f26a9cca22b599050acf63dfa8e802543df94191`.

The frozen suite passed 7,955 of 8,055 rows with GCC under `--as-needed`. All 8,055 rows match the snapshot 58 run, and the known-gap gate passes. The V8 corpus passed 4,780 of 4,780. `tests/test_cli_outputs.py` covers the refusals.

Throughput was not re-measured. The check compares a few paths once, before writing; the [snapshot 59 campaign](../../../../bench/results/2026-11-11/compiler-throughput-59/README.md) remains the published measurement.

[Summary](summary.json) · [Conformance](conformance.json.gz) · [V8 corpus](conformance-v8-corpus.json.gz)
