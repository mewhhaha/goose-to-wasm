# Source and output contracts

```sh
source build/performance-env.sh
python scripts/bootstrap.py --verify
python tests/conformance.py --compiler build/bin/goose \
  --output-dir build/conformance --levels 0 2
```

Use a fresh output directory. The suite contains 3,469 cases and 5,021 expanded checks: frozen source, input, expected output, exit status and failure phase. It never runs a reference compiler or regenerates expectations from the candidate.

Parsing failures, typing failures and runtime failures are distinct contracts. Typing failures must parse successfully. External signatures can be checked without supplying an external implementation. Runtime checks compare output and exit status; a crash is not an expected language error.

Use `--filter corpus/`, `--levels 0`, `--engine v8` or `--frontend-only` for focused runs. Rows run concurrently on every CPU by default; `--jobs N` sets the count. Results keep manifest order, and each execution is still a fresh process. Most of the time goes to compiling native C, so expect close to linear scaling. `--known-gaps tests/conformance/known-gaps.json` exits 0 only when the failures are exactly the recorded open gaps. `--native-cache DIR` reuses successful native builds across runs. Entries are keyed by the C compiler's identity, its flags and the bytes of direct input files; a hit links the stored binary and replays the original compiler output, and the report marks it. Cases with `native_sources` always rebuild because their transitive headers are not tracked. `--prune-native-cache` drops entries the run did not use. CI keeps this directory between runs. The default Wasm engine is Wasmtime; native cases compile emitted C with GCC. `--cc` selects another C compiler. Every execution starts a fresh process.

`--native-units N` builds native rows as N program units linked with the runtime unit's object (`native/units.h`), compiled once per runtime text, C compiler, flag and defines, and cached with the builds. `--targets native` selects rows by target. Upstream sources compile from one shared extraction under `build/conformance-upstream/`, keyed by the archive and standard library, so their emitted C, which names the source path at abort sites, is identical from run to run. Each program still runs in its own run's copy.

## Qualifying a change

```sh
python scripts/qualify.py --output-dir build/qualify-1 --baseline build/baselines/goose-PREVIOUS
```

This runs `bootstrap.py --verify`, then four stages at once: the suite with one translation unit per program; the native rows as three program units; `native/tests/check.py`; and output equivalence against the baseline compiler. It also runs the runner, bootstrap and backend unit tests. The split-unit pass runs only when native code generation, `native/` or the runner differ from `--since` (default `origin/main`); `--units-pass always` forces it. Native builds and bootstrap executables are cached by content under `build/qualify-cache`, so a rerun compiles only the C that changed. `summary.json` records each stage, the bootstrap hashes and cache use, and the exit status is nonzero if a stage fails. Equivalence differences are listed for review, not judged. On 2026-11-14 a cold run took 14.5 minutes and a warm one 3.2. [Measurements](../bench/results/2026-11-14/qualification-speed/README.md)

`report.json` records commands, observations, failures and input hashes. The upstream source archive includes its pinned revision and license; local fixtures and captured observations retain their provenance in `conformance/`.
