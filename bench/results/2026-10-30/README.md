# Sparse static data — 2026-10-30

The direct backend previously serialized every reserved byte of its static
region, including zero-filled globals. It now emits nonzero spans into fresh
zero-initialized Wasm memory. Logical allocations, addresses, stack placement,
memory limits, and runtime global initialization are unchanged.

These are exact file sizes for the same seven adapted LangArena sources at
`-O2`, using the pinned Goose frontend. The baseline is commit `b178d55`.

| Workload | Before (bytes) | After (bytes) | Reduction |
| --- | ---: | ---: | ---: |
| Fannkuch | 4,029 | 3,797 | 5.758% |
| CRC32 | 1,003,420 | 3,187 | 99.682% |
| Custom SHA256 workload | 1,005,526 | 5,293 | 99.474% |
| Mandelbrot | 2,405,955 | 4,377 | 99.818% |
| Sieve | 3,003,863 | 3,610 | 99.880% |
| Merge sort | 4,806,807 | 6,573 | 99.863% |
| Quicksort | 3,205,746 | 5,512 | 99.828% |

For each pair, independently decoding active data segments and overlaying them
onto zeroed initial memory produced identical bytes. Every section other than
the data section was byte-for-byte identical, including code, memory limits,
and the initial stack pointer. Both engines passed all seven official
small-input checksums: 14 executions total. These checks do not qualify the
unadapted 50-task suite or production-size inputs for this compiler revision.

The comparison measures artifact size. It does not establish faster execution,
lower peak memory, or a smaller runtime linear-memory requirement. The six
large workloads still reserve and initialize their declared arrays at runtime.

## Reproduce

Build the baseline compiler from `b178d55` and retain its `build/bin/goose`
outside the build output directory before building the updated compiler.
For each compiler, compile every entrypoint except `common.goose`:

```sh
for source in bench/langarena/ports/*.goose; do
  [ "$(basename "$source")" = common.goose ] && continue
  build/bin/goose "$source" --target wasm-direct -O2 --offline \
    -o "build/$(basename "$source" .goose).wasm"
done
```

Record the module sizes and hashes before replacing outputs. The
[raw comparison](static-data.json) retains source/compiler/module hashes,
commands, data-segment counts, initial-memory hashes, and the equality checks.

With the pinned Node and Python/Wasmtime environment active:

```sh
python tests/test_static_data.py
python tests/run_differential.py --engines v8 wasmtime --backends direct c-wasm native
python tests/test_backend_extensions.py
python tests/test_incremental.py
python bench/langarena.py fetch
python bench/langarena.py check --tracks adapted --backends direct \
  --engines v8 wasmtime --profiles test --skip-edits \
  --output-dir build/sparse-langarena
```

The standalone static-data tests cover empty and zero-only data, dense and
fragmented initialized bytes, embedded NULs, a large zero global, and logical
memory-limit rejection. The differential storage fixture checks runtime reads
and writes at both ends of a 1 MiB global, nonzero globals, and recursive local
storage against native and C-Wasm at O0/O2 on both Wasm engines.

Validation passed: 4 static-data tests, 483 differential observations, 88
backend-extension checks, 12 incremental checks, and the 14 LangArena
executions above. The raw comparison records their counts, pinned engine
versions, and the LangArena inputs and observed/expected checksums.
