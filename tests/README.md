# Source and output contracts

```sh
source build/performance-env.sh
python scripts/bootstrap.py --verify
python tests/conformance.py --compiler build/bin/goose \
  --output-dir build/conformance --levels 0 2
```

Use a fresh output directory. The suite contains 3,469 cases and 5,021 expanded checks: frozen source, input, expected output, exit status and failure phase. It never runs a reference compiler or regenerates expectations from the candidate.

Parsing failures, typing failures and runtime failures are distinct contracts. Typing failures must parse successfully. External signatures can be checked without supplying an external implementation. Runtime checks compare output and exit status; a crash is not an expected language error.

Use `--filter corpus/`, `--levels 0`, `--engine v8` or `--frontend-only` for focused runs. Rows run concurrently on every CPU by default; `--jobs N` sets the count. Results keep manifest order, and each execution is still a fresh process. Most of the time goes to compiling native C, so expect close to linear scaling. `--known-gaps tests/conformance/known-gaps.json` exits 0 only when the failures are exactly the recorded open gaps. `--native-cache DIR` reuses successful native builds across runs. Entries are keyed by the C compiler's identity, its flags and the bytes of every input file; a hit links the stored binary and replays the original compiler output, and the report marks it. `--prune-native-cache` drops entries the run did not use. CI keeps this directory between runs. The default Wasm engine is Wasmtime; native cases compile emitted C with GCC. `--cc` selects another C compiler. Every execution starts a fresh process.

`report.json` records commands, observations, failures and input hashes. The upstream source archive includes its pinned revision and license; local fixtures and captured observations retain their provenance in `conformance/`.
