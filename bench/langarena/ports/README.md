# Seven common LangArena workload ports

These sources adapt seven Goose workloads from
[kostya/LangArena at aab9b14998231ba905523b5ba3990ee03c46f64d](https://github.com/kostya/LangArena/tree/aab9b14998231ba905523b5ba3990ee03c46f64d/goose/src).
They preserve the upstream algorithms, configured data, random-number generator,
warmup state, timed work, and published checksums. The same port source is compiled
through native C, C-Wasm, and direct Wasm. This is a common supported subset of the
50-workload catalog, with the explicit storage and harness adaptations below.
It is not an unchanged build of the full LangArena application.

The imported code retains the original MIT license and
`Copyright (c) 2026 'Konstantin Makarchev'`; see [LICENSE](LICENSE).
[PROVENANCE.json](PROVENANCE.json) pins the upstream files and their SHA-256 hashes.
LangArena's own Docker configuration uses Goose
`ea1f368c109c083a2161580ff1d74c70200b6cc8`; these comparisons use this repository's
pinned compiler for all three backends, including its standard library.

## Input, output, and timing

Each executable reads whitespace-separated integers from stdin. Workload-specific
fields come first, followed by **measured iterations, then warmup iterations**.
The harness obtains these values from the pinned `test.json` or `run.json`.
The two stdout lines are the unsigned decimal checksum and elapsed nanoseconds.

| Source | Config fields | Supported bound | Test input | Test checksum |
| --- | --- | --- | --- | ---: |
| `fannkuch.goose` | `n` | 1–32 | `5 3 1` | 4428 |
| `sieve.goose` | `limit` | 2–3,000,000 | `1000 3 1` | 4660 |
| `sort_quick.goose` | `size` | 1–400,000 | `100000 2 1` | 2548773 |
| `sort_merge.goose` | `size` | 1–400,000 | `100000 2 1` | 2548773 |
| `hash_sha256.goose` | `size` | 1–1,000,000 | `1000 3 1` | 1036619072 |
| `hash_crc32.goose` | `size` | 1–1,000,000 | `1000 3 1` | 3031698216 |
| `mandelbrot.goose` | `w h` | Each 1–400; at most 120 total iterations | `30 30 3 1` | 2236342953 |

Every program requires a positive measured count and a nonnegative warmup count.
The upper bound for Fannkuch describes its array capacity, not a practical runtime
recommendation. The measured configurations are the upstream values below.

| Workload | Full production input | Full checksum |
| --- | --- | ---: |
| CLBG::Fannkuchredux | `8 700 140` | 135762480 |
| Etc::Sieve | `3000000 270 54` | 1042248060 |
| Sort::Quick | `400000 50 10` | 61757772 |
| Sort::Merge | `400000 50 10` | 61757772 |
| Hash::SHA256 | `1000000 1200 240` | 2844672256 |
| Hash::CRC32 | `1000000 150 30` | 2318723244 |
| CLBG::Mandelbrot | `400 400 100 20` | 3455988829 |

Preparation runs before warmup. Warmup mutates the same state used by measured
iterations: accumulated checksums and Mandelbrot images are retained. The RNG
resets before preparation and again immediately before the measured phase, as in
upstream `execute_with_warmup`. The loop iteration index starts at zero in each
phase. The runtime iteration count crosses `bench_barrier` before the start clock.
Only the repeated `run` calls lie between the two `bench_clock` calls. The final
checksum calculation, sink, printing, and revision check occur after timing.
There are no per-element host calls in these kernels.

The original JSON configuration/filtering, startup timestamp, human-readable
status lines, summary, and marker-file write are replaced by this scalar host
protocol. Configuration values remain runtime input. Input preparation still runs
in Goose; the host does not generate benchmark data or compute the checksum.
Engine compilation/instantiation and process startup are measured separately by
the surrounding harness.

## Explicit adaptations

| Port | Changes from the original Goose workload |
| --- | --- |
| Fannkuch | Numerical function and per-run accumulation unchanged. Initialize its small state directly; replace only configuration/timing plumbing. The three 32-element local arrays remain local. |
| Sieve | Replace the local growable byte array with a 3,000,001-byte global backing array. Fill the active prefix with ones on **every** run before clearing indices 0 and 1. All marking/counting work and square-root calculation remain inside each run. |
| Quick sort | Replace prepared/working growable arrays with two 400,000-element global i32 arrays. Prepare the same RNG data once. Copy the entire active prefix on every run with `copy_into`, retaining both RNG-selected checksum reads and the original recursive quicksort. |
| Merge sort | Same prepared/working arrays, plus a 400,000-element global temporary. Zero the active temporary on every run, as the original `resize(n, 0)` does. Retain the recursive merge sort and every per-merge `copy_into`. |
| Custom SHA256-named hash | Replace prepared growable bytes with a 1,000,000-byte global backing array. Preserve the original eight-lane hash function, its returned `u8[32]` aggregate, and `binary::read_u32le`. This is LangArena's custom digest, **not cryptographic SHA-256**. |
| CRC32 | Same prepared byte-buffer adaptation; retain the original bit-at-a-time CRC32 kernel unchanged. |
| Mandelbrot | Replace cumulative growable output with a 2,401,320-byte global backing array and logical length. Append the same PBM headers and bitmap bytes. Positive decimal dimension rendering uses a bounded digit buffer. Preserve every image, including warmups, and hash the complete stored output only after the end timestamp. |

Global backing storage avoids placing the large buffers in ordinary native C
function activation frames. Its maximum capacity is allocated/initialized before
the measured loop, including for smaller test inputs; algorithms touch only the
active prefixes during timed work. This changes allocation/lifetime costs from
the upstream growable representation. Sieve initialization, sort copies and
Merge's temporary initialization are still timed. These adaptations apply equally
to all three backends, so comparisons here measure the same port. They do not
measure the original growable allocator.

For full Mandelbrot inputs, each appended image is an 11-byte PBM header plus
20,000 bitmap bytes. All 120 warmup/measured images occupy exactly 2,401,320 bytes.
The original arithmetic order, 50-iteration limit, escape test, and partial-byte
row handling are unchanged. Floating contraction is disabled by the C build
drivers so the three backends share that arithmetic contract.

## Observable rebuild marker

Every entry file contains exactly `let ARENA_REVISION = 0;` and passes it to
`finish`. After printing its normal two result lines, a nonzero revision becomes
the process exit status. The compile-time harness edits this constant from 0 to 1,
rebuilds, verifies the expected exit status 1, and restores the original source.
Checksums stay unchanged. This is an observable source change, rather than a
comment edit or a no-op cache-hit measurement, and needs no extra host ABI.
