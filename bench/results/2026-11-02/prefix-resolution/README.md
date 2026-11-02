# Prefix resolution — 2026-11-02

Sorting's baseline profile attributed 74.9% of samples to `resolve_prefix`: 401,711,695 calls checked 2,812,502,155 owner entries with no active mappings or remaps. Sorting still uses 20,000 insertion values; only its misleading header and manifest description changed.

The emitter tracks positive-prefix registrations and uses an identity helper if there are none, after emitting the start body to include global constructors. The checker-owned `Ast::structinsts` registry also proves when no frame-record type exists, allowing resolver calls to be omitted. A guard rejects registrations contradicting that proof. Positive-prefix frame modules retain the original resolver; header publication, ownership, bounds and unwind behavior remain intact. No runtime counters or globals were added.

## Measurements

On an AMD Ryzen 7 3800X shared desktop, seven interleaved pairs per cell measured fresh-process entry time, including initialization, output callbacks and lazy JIT work. Sorting improved from 4,282.184 to 162.647 ms on V8 (26.292× paired) and from 4,519.793 to 131.428 ms on Wasmtime (34.608×). Sudoku improved from 241.427 to 13.094 ms on V8 (18.439×) and 246.638 to 8.248 ms on Wasmtime (29.814×). Sorting Wasm shrank from 144,519 to 138,792 bytes and has no resolver callers.

Squares remained byte-identical with unchanged entry time; instrumented process time varied about 10%. Maze V8 showed no reliable change (0.966× paired, MAD 0.086); Maze Wasmtime improved 1.217× and Life Wasmtime 2.043×. These are workload-specific results, not a universal gain. The earlier identity-only stage and its five paired samples per cell are retained separately.

Entry probes write timing files and are distinct from ordinary launch-to-exit measurements. In the separate [ten-example cohort](../example-benchmarks/README.md), sorting took 262 ms direct versus 259 ms C-to-Wasm on V8, and 300 ms versus 268 ms on Wasmtime. The fresh [seven-workload LangArena cohort](langarena.md) uses warmed computational regions; its direct modules are byte-identical to the previous cohort, so it does not establish a kernel speedup from this change. Direct uses memory32; C-to-Wasm uses memory64.

## Qualification and evidence

The differential matrix passed 9,453 observations, including 7,560 native stdout comparisons. Forty-three focused commands passed, including region and prefix cases, warm CLI fixture parity, and the 60-build/100-execution example matrix. [Qualification details](qualification.json), [differential observations](differential.json.gz) and the [final audit](review.json) are retained.

[Paired results](paired.json) · [Identity-only results](identity-only-paired.json) · [LangArena raw cohort](cohort.json) · [Compiler identities](compiler-identities.json) · [Artifact comparison](artifact-comparison.json) · [Input snapshots](inputs.tar.gz) · [Samples and logs](samples.tar.gz) · [Qualification logs](qualification-logs.tar.gz) · [Profile](profile.tar.gz) · [Identity-stage evidence](identity-stage.tar.gz) · [Compiler patch](compiler-changes.patch) · [Hashes](SHA256.json)

## Reproduce

The [paired harness](measure_pairs.py) expects to reside in `build/sorting-climb/` so its repository-root paths resolve. Copy it there, then supply qualified baseline (`8f4584a`) and candidate compiler installations, each with its standard library and `source.json`:

```sh
mkdir -p build/sorting-climb
cp bench/results/2026-11-02/prefix-resolution/measure_pairs.py build/sorting-climb/
python build/sorting-climb/measure_pairs.py --baseline /path/to/baseline/bin/goose --candidate /path/to/candidate/bin/goose --output build/sorting-pairs
```

The retained JSON configurations contain exact flags, identities and environment. Results depend on host load, engine tiering and these fixed inputs; startup and generated code size remain performance hills.
