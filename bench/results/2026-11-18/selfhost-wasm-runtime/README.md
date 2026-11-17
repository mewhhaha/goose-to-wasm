# The compiler's Wasm execution gap · 2026-11-18

The self-check uses the same `selfhost/main.goose` workload, source archive at `38826b4` and compiler artifacts as the README chart. This is a separately timed follow-up. Wasmtime 50.0.1 prepares each module once and times `_start` in a fresh instance. Native timing includes process launch. The paired runs used CPU 6 of the shared Ryzen 7 3800X host. Linux user-space hardware counters ran without multiplexing. The counts include the small instantiation cost outside the Wasm wall-time window. [Chart benchmark](../../2026-11-17/compiler-selfhost-execution/README.md) · [Samples and identities](measurements.json)

## Where the cycles go

Native self-check took **2.90 s and 26.44 billion retired instructions**. The same program in resident 64-bit Wasmtime took **14.30 s and 113.30 billion instructions**. The Wasm run retired 4.29× as many instructions and took 4.93× as long.

Separate CPU profiles found lifetime analysis in 85.1% of 1,023 native samples, 85.8% of 6,731 Wasmtime samples and 88.2% of 5,043 V8 samples. In Wasmtime, 218 samples fell outside mapped Wasm functions. The sample totals cover different engines and sampling methods. [Profiles](profiles.json) · [Wasmtime samples](wasmtime-check-profile.json)

Astra mapped the sampled Wasmtime PCs back to original Wasm instructions after verifying identical native code bytes for the eight profiled bodies. The array base and length readers emit a six-mode dispatch at each access. Across the eight bodies, 551 of 2,408 samples mapped into these dispatches and 302 mapped to `memory.copy`. The shares include nearby instructions because sampling observes machine PCs. [Array readers](../../../../selfhost/codegen.goose#L4368) · [Address-map attribution](attribution.txt)

One concrete duplicate is in `life_eval_body`. A loop copies a 104-byte `LifeExit` before testing its node and frame, then the fixed-record lowering copies the 72-byte `LifeValue` field again at the same offset. Those two copies account for 115 of the 533 samples in that function. `cg_copy` already copies the full record before recursing into aggregate fields. Restricting the second pass to fields that require repair is a candidate for a Wasm conformance check and paired benchmark. [Loop](../../../../selfhost/checker_lifetimes.goose#L5507) · [Copy lowering](../../../../selfhost/codegen.goose#L679) · [Copy sites](copy-sites.txt)

## Memory width and traps

| Self-check | Median wall time | Observed range | Retired instructions |
| --- | ---: | ---: | ---: |
| Native via C and Clang | 2.90 s | 2.84–3.21 s | 26.44 B |
| Wasmtime memory64 with equal regions | 14.30 s | 13.94–14.47 s | 113.30 B |
| Wasmtime memory64 with profiled regions | 13.74 s | 13.49–13.77 s | 113.29 B |
| Wasmtime memory32 with profiled regions | 11.19 s | 10.28–11.21 s | 94.20 B |
| Same memory32 module with explicit traps | 14.42 s | 14.13–14.95 s | 147.64 B |

There are three interleaved check samples per row. With two emission pairs, switching from the equal-region memory64 module to profiled memory32 reduced the median from **20.93 to 15.64 s** and retired instructions from **175.94 B to 149.50 B**. All four emissions reproduced the original memory64 compiler byte for byte. The memory64 layout control changed little instruction work. Width also changes data representation, including pointer and slice sizes.

On the same memory32 bytes, disabling Wasmtime's signal-based traps forced explicit checks and raised median check time by 29%. The setting affects linear-memory bounds and other traps such as division by zero. The control shows that guard-page-based code generation matters for this workload. [Wasmtime trap configuration](https://docs.wasmtime.dev/api/wasmtime/struct.Config.html#method.signals_based_traps)

Equal-region memory32 exhausted a region on the same self-check. The measured memory32 variant uses the existing `--wasm-region-profile` option with high-water marks from a memory64 self-emission. The largest region held 110,663,360 bytes. A default memory32 build would need a layout that fits without a workload-specific profile. [Region peaks](regions.txt) · [Equal-region failure](equal32-check.log)

## Plain-array shortcut probe

The probe emits one early branch when an array header holds plain storage. On the original memory64 workload, two opposite-order Wasmtime pairs on CPU 1 reduced median time from **14.29 to 12.52 s**, instructions from **113.31 B to 95.83 B** and branches from **19.88 B to 11.02 B**. Both modules were prepared before timing. Coverage is limited to self-check and self-emission, which reproduced the original Wasm artifact. [Scratch patch](decoder-fast-path.patch) · [Wasmtime samples](decoder-wasmtime-pairs.jsonl) · [Emission proof](profiles.json)

Three V8 pairs on CPU 2 had median times of 14.19 s baseline and 13.31 s candidate. The candidate won two pairs and lost one under shared load. The sample spread limits the size of the V8 claim. [V8 samples](decoder-v8-pairs.jsonl)

## Reproduce the width comparison

Use the [chart benchmark's build inputs and flags](../../2026-11-17/compiler-selfhost-execution/README.md#reproduce) with a stage named `build/selfhost-comparison-2026-11-17`. The starting compiler SHA-256 is `6dc908de22b44263c36c7f8b31b6c44047df1e126cf465a71ee527116e7f1030`. The paired and profile scripts use Linux x86-64 performance events.

```sh
repo_dir=$PWD
input_dir=$repo_dir/build/selfhost-comparison-2026-11-17
probe_dir=$repo_dir/build/wasm-execution-gap-2026-11-18
mkdir -p "$probe_dir"
cp bench/results/2026-11-18/selfhost-wasm-runtime/tools/*.py "$probe_dir/"
cd "$input_dir/source"
"$input_dir/emitter" selfhost/main.goose --stdlib stdlib --target wasm-direct -O2 \
  --wasm-memory64 --wasm-max-pages 262144 --wasm-region-stats -o "$probe_dir/profile.wasm"
GOOSE_REGION_PROFILE="$probe_dir/regions.txt" python3 "$repo_dir/scripts/run_wasmtime.py" \
  "$probe_dir/profile.wasm" -- selfhost/main.goose --stdlib stdlib --target wasm-direct -O2 \
  --wasm-memory64 --wasm-max-pages 262144 -o "$probe_dir/region-emit.wasm"
"$input_dir/emitter" selfhost/main.goose --stdlib stdlib --target wasm-direct -O2 \
  --wasm-memory64 --wasm-max-pages 262144 --wasm-region-profile "$probe_dir/regions.txt" -o "$probe_dir/profiled64.wasm"
"$input_dir/emitter" selfhost/main.goose --stdlib stdlib --target wasm-direct -O2 \
  --wasm-max-pages 65535 --wasm-region-profile "$probe_dir/regions.txt" -o "$probe_dir/profiled32.wasm"
python3 "$probe_dir/measure.py"
python3 "$probe_dir/sample.py"
```
