# Parsed-module reuse — 2026-10-30

Commit `131119a` implements optional reuse of pristine parsed modules; `d3e00cc`
adds configuration and import-probe validation for the whole-module artifact
cache. These measurements use the latter Release compiler and compare native
workers with and without parsed-module reuse.

Each run uses 32 generated functions, 15 samples, an edited root module, and
an unchanged imported `std` module. Local builds and qualification finished
before timing. The order is worker–syntax–syntax–worker at O0, then O2.
Every run independently verifies the final edited program's result.

| Level | Mode, in execution order | Edited median (ms) | MAD (ms) | Parse median (ms) | First uncached request (ms) |
| --- | --- | ---: | ---: | ---: | ---: |
| O0 | Worker | 14.180 | 0.830 | 1.896 | 81.897 |
| O0 | Syntax cache | 14.901 | 0.885 | 1.581 | 139.796 |
| O0 | Syntax cache | 14.567 | 1.573 | 1.500 | 105.477 |
| O0 | Worker | 15.654 | 1.856 | 1.754 | 106.994 |
| O2 | Worker | 13.491 | 1.567 | 1.764 | 90.476 |
| O2 | Syntax cache | 14.248 | 2.267 | 1.555 | 76.977 |
| O2 | Syntax cache | 14.594 | 1.163 | 1.588 | 79.902 |
| O2 | Worker | 14.216 | 1.274 | 1.934 | 95.468 |

Syntax reuse consistently reduces the measured parse phase in these runs, but
does **not establish an end-to-end edited-build latency improvement**. The
wall-time samples overlap and include scheduling noise. First-request timings
include Python server startup, native process startup, and a cold compilation;
their variation also prevents a reliable cold-build comparison. The cache
remains opt-in.

Every cached edit parsed one file and reused one template; worker-only edits
parsed two files. The syntax cache retained two files with a conservative
6,870,226-byte storage estimate. Resolution, checking/specialization,
optimization, bounds analysis, and emission all ran afresh. Type checking
accounted for roughly 2.1–3.0 ms and emission for 0.085–0.122 ms across the
edited phase medians. These small-program results do not establish behavior
for large module graphs or justify a claim of incremental semantic analysis.

The [records](syntax-cache.json) retain all timing samples, phase medians,
edited-build counters, first-request times, verified-output status, input hashes,
and platform metadata. Repeated per-function fingerprint arrays are omitted.
The compiler SHA-256 was unchanged across qualification and all eight runs.

That compiler passed 583 differential observations across native C, C-Wasm,
direct Wasm, V8 and Wasmtime, plus 99 backend checks, 22 dependency-input tests,
12 artifact-cache checks, 11 session tests, 10 syntax-cache tests, and 4
static-data tests. All 194 curated C-Wasm portability cases passed; these
qualify the reference pipeline, rather than additional direct language coverage.
The syntax importer was separately checked under AddressSanitizer and
UndefinedBehaviorSanitizer for 28 ownership cases in the implementation
milestone, including destruction of templates before checking and emission.
Local leak detection was disabled because LeakSanitizer cannot run under this
environment's process tracing; CI retains leak checking.

With the pinned Node and Python environment active, reproduce each pair in
worker–syntax–syntax–worker order:

```sh
python bench/incremental.py --samples 15 --functions 32 --native-worker \
  --optimization O0 --output build/syntax-worker-O0.json
python bench/incremental.py --samples 15 --functions 32 --native-worker \
  --syntax-cache --optimization O0 --output build/syntax-cached-O0.json
```

Repeat with `--optimization O2` and distinct output filenames.
