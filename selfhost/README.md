# Goose in Goose

This first-pass compiler is written in Goose, from source and import loading through parsing, checking, specialization, optimization, direct Wasm and native C emission, and the command-line driver. Its tables use stable IDs and growable Goose builders; the [IR contract](IR.md) describes the stage interfaces.

Bootstrap uses a SHA-pinned C++ compiler to generate native C, then GCC builds an independent compiler. That compiler does not delegate user programs to the oracle. This is not verified self-hosting or 1:1 parity. The original C++ compiler remains the production compiler and the source of the published benchmarks.

## Bootstrap

From the repository root, with the pinned oracle and its standard library, Python, and GCC available:

```sh
source build/performance-env.sh
python selfhost/bootstrap.py --output-dir /dev/shm/goose-selfhost-work/attempt-1
```

The default oracle is `build/next-runtime-hills/final/bin/goose`; `--oracle` selects another binary with the same SHA-256. `oracle.json` pins the binary and direct-backend sources. Bootstrap records its inputs, commands, generated C, executable, and logs in the output directory. Use a fresh directory for each attempt.

## Verification

The verifier compiles independently with the candidate and oracle, then compares acceptance, Wasm bytes, runtime output and exit status, golden output, and diagnostic categories. A shared refusal of a valid program is not parity. The default gate requires matching bytes; `--runtime-only` reports byte differences while gating on behavior.

```sh
source build/performance-env.sh
python selfhost/verify.py \
  --candidate /dev/shm/goose-selfhost-work/attempt-1/goose-selfhost \
  --output-dir /dev/shm/goose-selfhost-work/parity-1
```

The default sweep covers small programs at O0 and O2. `--examples` selects the full examples, `--full` selects the differential corpus, and `--filter` narrows either selection. Dated results and their recorded inputs are in [results/2026-11-04](results/2026-11-04/).

The final candidate matched runtime behavior on 18/18 valid basic runs and all 20 example runs at O0/O2; 4/18 basic Wasm outputs and 0/20 example outputs were byte-exact. On the O0 differential corpus, 409/950 rows passed the full behavior gate, with 372 candidate refusals and 165 runtime differences. The [evidence guide](results/2026-11-04/README.md) details the matrix, diagnostics, and native results. The compiler parses its own source, but self-hosting remains unverified.

## Gaps

Variable-byte images, root and lifetime analysis, specialization, native ABIs, and optimizer ordering need further work and differential verification. Native allocations are retained until exit, and native debug overflow checks are refused. Remote package retrieval, project build/package commands, JIT integration, and the language server are not ported. Source dump preserves the input verbatim, and dependency output is incomplete for caching.
