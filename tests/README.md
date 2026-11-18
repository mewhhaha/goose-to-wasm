# Source and output contracts

From the repository root, with a C compiler and Node installed:

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python scripts/bootstrap.py --verify
.venv/bin/python tests/conformance.py --compiler build/bin/goose \
  --output-dir build/conformance --known-gaps tests/conformance/known-gaps.json
```

Use a new output directory. The [manifest](conformance/cases.json) freezes the sources, inputs, output, exit statuses and failure phases. `--known-gaps` requires the observed failures to match the recorded gaps for the selected rows. Type errors must parse successfully. The suite runs only the compiler under test.

Use `--filter corpus/`, `--levels 0`, `--targets native`, `--engine v8` or `--frontend-only` for focused runs. `--jobs N` sets concurrency. Every case runs in a fresh process. The sort fixture gets 30 seconds. After the other workers finish, a timeout retries that execution once using the same module, input and limit. Cases that access files run once. Both attempts appear in the report. Wasmtime is the default Wasm engine. With `--wasm-memory64 --targets wasm-direct`, use [the memory64 gaps](conformance/known-gaps-memory64.json). Memory64 uses the [release Rust host](../host/rust/README.md) when built and falls back to Python. Select the reference with `--python-host` or another executable with `--host`.

`--native-cache DIR` reuses successful GCC builds keyed by tool, flags and direct inputs. Cases with `native_sources` rebuild because their transitive headers are untracked. `--native-units N` builds program units beside a reusable runtime unit. `--prune-native-cache` removes entries the run did not use.

## Qualifying a change

```sh
.venv/bin/python scripts/qualify.py --output-dir build/qualify-1 \
  --baseline build/baselines/goose-previous
```

This verifies bootstrap, runs the default and memory64 contracts, checks the native runtime and runs unit tests. The split native pass runs when native code generation, `native/` or the runner differ from `--since` (default `origin/main`). Use `--units-pass always` to force it. The bootstrap and native build caches live under `build/qualify-cache`.

When supplied, `--baseline` compares output against an executable built from the previous sources. Require an empty `differing` array in `equivalence/report.json` for a performance change. The qualification exit status does not judge equivalence differences. For lifetime optimizations, compare analysis state too. Apply [the logical fingerprint helper](../bench/results/2026-11-17/lifetime-compact-reads/tools/logicalfp.py) to separate baseline and candidate source copies, then check the same inputs. Use `fingerprint` for pass boundaries and `fpframes` for samples every 2,000 frames. Set `LIFE_CONCRETE_FRAMES` in the copies to exercise early class behavior.

`summary.json` records stage results. Contract reports record exact commands, observations and input hashes. `GOOSE_COMPILER` selects the compiler for unit tests that launch it.
