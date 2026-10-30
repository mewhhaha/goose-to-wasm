# Native build-server overhead — 2026-10-30

Commit `4d546f0` constructs the request parser once per server and skips
artifact-qualification work for unsaved overlays and `--no-cache`. Those builds
already disable artifact lookup/storage. They still collect and protect every
source/configuration/probe path before publishing outputs; unchecked snapshots
are marked incomplete and cannot validate as reusable artifacts.

This experiment uses one unchanged Release compiler (`dc3ec8f`) with syntax
and scalar-caller reuse enabled. The original 32-function chain changes `step0`
on every edit and reuses all 31 callers. The previous driver is the exact
`dc3ec8f` file; the optimized driver is `4d546f0`. Runs use 15 samples each in
previous–optimized–optimized–previous order at O0/O2, first with disk edits,
then with unsaved overlays. All local validation finished before timing.

All columns are median milliseconds except MAD, which describes edited
round-trip dispersion. Native request time includes worker communication,
compilation and its metadata/output handling. Outside-build time includes
request parsing, outer JSON handling, and the remaining round trip.

| Edits | Level | Driver, in order | Edited round trip | MAD | Native request | Outside build |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Disk | O0 | Previous | 14.205 | 1.384 | 8.105 | 1.569 |
| Disk | O0 | Optimized | 13.417 | 1.097 | 6.902 | 0.751 |
| Disk | O0 | Optimized | 12.594 | 1.965 | 6.408 | 0.641 |
| Disk | O0 | Previous | 13.440 | 1.364 | 6.500 | 1.574 |
| Disk | O2 | Previous | 13.929 | 1.076 | 7.120 | 1.466 |
| Disk | O2 | Optimized | 12.570 | 0.726 | 6.980 | 0.609 |
| Disk | O2 | Optimized | 13.099 | 1.079 | 7.098 | 0.614 |
| Disk | O2 | Previous | 14.079 | 0.353 | 7.762 | 1.633 |
| Overlay | O0 | Previous | 12.317 | 0.851 | 6.726 | 1.646 |
| Overlay | O0 | Optimized | 9.805 | 0.823 | 6.588 | 0.636 |
| Overlay | O0 | Optimized | 9.472 | 0.659 | 6.627 | 0.732 |
| Overlay | O0 | Previous | 13.228 | 1.414 | 6.636 | 1.495 |
| Overlay | O2 | Previous | 14.680 | 1.200 | 7.635 | 1.470 |
| Overlay | O2 | Optimized | 10.917 | 1.167 | 8.271 | 0.614 |
| Overlay | O2 | Optimized | 10.919 | 0.836 | 7.790 | 0.594 |
| Overlay | O2 | Previous | 12.957 | 0.554 | 7.354 | 1.599 |

Unsaved-edit medians fall from **12.3–14.7 ms to 9.5–10.9 ms** in these local
runs. Disk edits improve modestly, while retaining full artifact validation.
The outside-build component consistently falls by about 0.7–1.1 ms; overlays
also avoid additional dependency validation inside the driver build. Unchanged
persistent-server artifact-hit medians fall from 2.85–4.45 ms to 1.84–2.77 ms.

Compiler request and phase times still vary with shared-host scheduling. These
are driver improvements on one local workload, not a general compiler or
runtime speedup claim. The separate [caller comparison](checked-callers.md)
retains the earlier result: skipping caller body checks alone did not establish
an end-to-end improvement on this chain.

Every run verifies final output `12199049576607937` for runtime input `3`.
The [records](driver-overhead.json) retain all 240 edited timing samples, phase
and transport summaries, per-edit reuse counters, expected/actual output,
driver/input hashes, and platform metadata. Repeated function fingerprint
arrays are omitted. The compiler hash stayed identical across all runs and
matches its 603-observation, 99-backend-check, 194-reference-case qualification.

Driver validation passed 23 dependency tests, 12 artifact-cache checks, 11
session tests, 10 syntax-cache tests, 10 leaf-cache tests and 13 scalar-caller
tests, including publication guards, failed-request recovery, option isolation,
and rejection of unchecked snapshots for reuse. The compiler and its semantic
ownership sanitizer results are unchanged from the caller milestone.

To reproduce a pair, save the previous driver directly in `build/` so
its repository-root calculation remains valid:

```sh
git show dc3ec8f:scripts/goose_wasm.py > build/validated-driver.py
python bench/incremental.py --samples 15 --functions 32 --native-worker \
  --syntax-cache --checked-scalar-cache --optimization O0 --edit-source-mode overlay \
  --driver build/validated-driver.py --output build/overlay-previous.json
python bench/incremental.py --samples 15 --functions 32 --native-worker \
  --syntax-cache --checked-scalar-cache --optimization O0 --edit-source-mode overlay \
  --output build/overlay-optimized.json
```

Repeat in previous–optimized–optimized–previous order, using distinct output
files, and repeat with O2 and disk edits.
