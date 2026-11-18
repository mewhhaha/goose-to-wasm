# Wasm record copies and array reads · 2026-11-18

The direct Wasm backend copies an owner-free aggregate in one block when no forwarding resolver is active. Plain growable arrays now read their base and length without visiting the image-format dispatch. Both changes are in compiler source `f89ecf30aea76003e4536bcf6fa8f280efb287cc`. The release executable SHA-256 is `18b8113e3fc91d038882cdad8ab4b2e98971474f285f2dacc6756c047ceeb14d`. [Cause investigation](../selfhost-wasm-runtime/README.md) · [Bootstrap receipt](bootstrap.json)

## Same-source runtime comparison

The three memory64 modules compile the same project at `38826b4` with `-O2 --wasm-memory64 --wasm-max-pages 262144`. The copy-only and combined emitters are development executables built with Clang 23.1.5 at `-O0` in eight program units. They emit the frozen program with the requested `-O2` options. Wasmtime 50.0.1 compiles each module once. Three interleaved checks time `_start` on CPU 6 of the shared Ryzen 7 3800X. [Raw times and counters](frozen-runtime.json)

| Wasmtime self-check | Wall median | Observed range | Retired instructions |
| --- | ---: | ---: | ---: |
| Parent | 14.73 s | 11.46–14.77 s | 113.30 B |
| Single record copies | 13.80 s | 11.27–19.89 s | 111.54 B |
| Single copies and plain-array reads | 12.27 s | 11.01–15.97 s | 94.03 B |

The combined change retired 17.0% fewer instructions. The wall results varied under shared load. The single emission per module reduced retired instructions from 175.94 B to 147.77 B with the combined change. All three emitted the original compiler module byte for byte. [Trial driver](tools/trial.py)

## Qualification

The regression fixture copies a record whose last field has zero size. Plain upstream Goose `ee261a4` prints `2 17 34`, preserving the enclosing sentinel. The previous Wasm lowering printed `2 34 34` on both widths. The new case passes at `-O0` and `-O2` in both Wasmtime and V8 on memory32 and memory64. [Fixture](../../../../tests/fixtures/packed_copy_empty.goose) · [Focused results](packed-copy-contracts.json)

The release reached a C fixed point. Default conformance passed 10,691 of 10,795 rows and memory64 passed 4,767 of 4,775, with zero unexpected failures. All 54 native checks passed. The unit suite ran 80 tests with one optional skip. Qualification started with the source and fixture in the working tree and the release commit records that same input.

The output comparison reported 779 changes across 10,053 rows. Every changed output is a Wasm module whose differences fall entirely in the code section. Native C, diagnostics and compiler exit statuses matched. [Qualification summary](qualification.json) · [Stage log](qualification.log) · [Wasm section audit](equivalence-audit.json)

## README benchmarks

The eleven-program build catalog uses 31 paired samples per cell on CPU 7. Candidate-to-parent geometric means of median CPU time are 0.990× for Wasm emission and 1.008× for C emission. Wall-time bars show the same trial at the source-to-artifact boundary. [Catalog](compiler-comparison.json)

The ten-example build and process trials use five samples per cell on CPU 7. All 30 Mandelbrot build samples reproduced the previous release's artifacts byte for byte. Their executables and Wasm modules match the six artifacts recorded by the separate resident run. [Examples](examples.json) · [Wasmtime host](host.json) · [Mandelbrot builds](langbench-build.json) · [Artifact proof](langbench-artifacts.json)

The self-hosting chart builds and runs the project frozen at `f89ecf3`. The native build uses eight Clang program units on CPUs 1–5 with the runtime object cache disabled. The execution trial uses three rounds on CPU 6. Both Wasm engines reuse prepared modules and time `_start`. Every emission reproduced the same module. The native executable is this compiler's C build. Upstream Goose `d92c4315` and `ee261a4` both rejected these frozen sources during lifetime checking. [Self-hosting samples](measurements.json) · [Chart values](selfhost-chart.json) · [Upstream attempts](upstream-native.json)
