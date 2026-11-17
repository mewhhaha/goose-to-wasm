# WebAssembly local slot selection, 2026-11-17

The allocator scans slots in creation order for the first free slot with the
requested WebAssembly type. Once a scan skips a prefix, its same-type slots
stay busy through the earliest end recorded for that prefix. Cache that prefix
per type. A scan excludes the selected slot from its cache because assigning
the new span changes that slot's end.

Replaying the frozen optimized compiler captured 1,539 functions that reached
the allocator with at least two locals. Their 1,384,439 assigned spans visited
85,465,216 slots with the original search. The largest function assigned
24,145 spans, reached 1,234 slots, and visited slots 6,672,592 times.
[Distribution](receipts/distribution-self-opt.txt)

| Replay input | Original median | Prefix median | Change |
| --- | ---: | ---: | ---: |
| Frozen self, `-O2`, 1,539 bodies | 543.46 ms | 490.65 ms | −9.7% |
| Frozen self, default optimization, 1,491 bodies | 209.88 ms | 200.35 ms | −4.5% |
| Synthetic mixed types and 5,000–17,000 overlapping spans | 240.56 ms | 31.31 ms | −87.0% |
| 60,000 tiny bodies with 2–10 locals | 140.22 ms | 144.39 ms | +3.0% |

Every row emitted byte-identical remapped local tables and code. Times sum
the calls to `wb_reuse_locals` inside the replay process. Each variant ran six
times with alternating order. The tiny case adds about 70 ns per call at
the median. Control flow and opcode decoding still run in the measured
function. These figures describe the allocator replay and supply no
whole-compiler speedup estimate. [Raw receipts](receipts/)

The [release-event bitset](events.patch) also preserved bytes. It took
500.27 ms on optimized self versus its 543.23 ms baseline, and 35.68 ms on the
overlap stress workload versus its 243.62 ms baseline. The prefix cache gave
lower medians on both workloads and uses two fixed tables. The bitset adds a
release table indexed by instruction position and scans 64-slot bitset words.

## Reproduction

The capture uses compiler sources from
`90d4d19fe26337d0e777aec83cf0ab667b16e428` and the pinned one-unit,
unprofiled native compiler under `build/perf-next-1117/goose-parent`.
Its [hash, generated C hash, and input hashes](receipts/sha256.txt) identify
the run. Capture uses GDB 18.1 and the argument registers of
`g_fn259276` in this exact x86-64 binary. Timing uses Clang 23.1.5 at
`-std=gnu11 -O2` on CPU 4 of a shared Ryzen 7 3800X host
(Linux 7.3.4-1-cachyos). The raw pairs include shared-host outliers.

From the repository root, using the pinned compiler:

```sh
evidence="$PWD/bench/results/2026-11-17/wasm-slot-prefix"
scratch="$PWD/build/wasm-slot-allocation-2"
snapshot="$PWD/build/perf-next-1117/source"
compiler="$PWD/build/perf-next-1117/goose-parent"
mkdir -p "$scratch" "$snapshot"
git archive 90d4d19fe26337d0e777aec83cf0ab667b16e428 native selfhost stdlib |
  tar -xf - -C "$snapshot"

(
  cd "$snapshot"
  GOOSE_CAPTURE="$scratch/self-opt.bin" taskset -c 4 gdb --batch \
    -ex 'set debuginfod enabled off' -ex "source $evidence/capture.py" \
    -ex run -ex 'python output.close()' --args "$compiler" selfhost/main.goose \
    --target wasm-direct -O2 --wasm-max-pages 65535 --stdlib stdlib \
    --wasm-stats "$scratch/self-opt.json" -o "$scratch/self-opt.wasm"
)
GOOSE_CAPTURE_LIMIT=1491 GOOSE_CAPTURE="$scratch/default-complete.bin" \
  taskset -c 4 gdb --batch -ex 'set debuginfod enabled off' \
  -ex "source $evidence/capture.py" -ex run -ex 'python output.close()' \
  --args "$compiler" build/perf-next-1117/source/selfhost/main.goose \
  --stdlib build/perf-next-1117/source/stdlib --target wasm-direct \
  -o "$scratch/default.wasm"

python3 "$evidence/fixtures.py" "$scratch"
for variant in baseline prefix events; do
  work="build/wasm-slot-allocation-2/$variant"
  mkdir -p "$work"
  cp "$snapshot/selfhost/wasm.goose" "$work/wasm.goose"
  cp "$evidence/replay.goose" "$work/main.goose"
  if [ "$variant" != baseline ]; then
    patch "$work/wasm.goose" < "$evidence/$variant.patch"
  fi
  taskset -c 4 "$compiler" "$work/main.goose" --target native -O2 \
    --stdlib build/perf-next-1117/source/stdlib -o "$work/replay.c"
  taskset -c 4 clang-23 -std=gnu11 -O2 "$work/replay.c" -lm -ldl -pthread \
    -o "$work/replay"
done

taskset -c 4 python3 "$evidence/collect-spans.py" "$scratch/self-opt.bin"
taskset -c 4 python3 "$evidence/measure.py" "$scratch" self-opt baseline prefix
taskset -c 4 python3 "$evidence/measure.py" "$scratch" synthetic baseline prefix
taskset -c 4 python3 "$evidence/measure.py" "$scratch" tiny baseline prefix
taskset -c 4 python3 "$evidence/measure.py" "$scratch" default-complete baseline events prefix
```

Pass `baseline events` to replay the bitset on the optimized self and
synthetic inputs. Each timing row records the variant, allocator nanoseconds,
elapsed process nanoseconds, user seconds, system seconds, and output SHA-256.
