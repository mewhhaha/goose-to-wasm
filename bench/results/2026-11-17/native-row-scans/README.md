# Native bounded Row construction and traversal

Building 8,008 self-relative rows fell from 238.68 ms to 0.363 ms. Summing their IDs through self links fell from 600.39 ms to 0.076 ms. Both loops now take linear time for this program. Every timed execution produced the expected checksum of 32,060,028 at that size. [Frozen workload](../varint-foreach/native_rows.goose)

| Rows | Construction before (ms) | Construction after (ms) | Foreach before (ms) | Foreach after (ms) |
| ---: | ---: | ---: | ---: | ---: |
| 1,001 | 3.81 | 0.051 | 9.52 | 0.010 |
| 2,002 | 16.28 | 0.127 | 40.71 | 0.027 |
| 4,004 | 65.32 | 0.200 | 160.87 | 0.040 |
| 8,008 | 238.68 | 0.363 | 600.39 | 0.076 |

Each cell is the median of seven runs after two warmups per binary and size. The executable order alternates. Every invocation runs in a fresh process on logical CPU 6 of a shared host with GCC 16.2.1 and Goose native `-O2`. The guest reads the monotonic clock around each loop, excluding startup and printing. At 8,008 rows the candidate construction samples span 0.341–0.530 ms and traversal 0.075–0.100 ms. The earlier single-sample run used a separate executable and is archived independently. [Raw timings, flags and hashes](results.json) · [Earlier run](../varint-foreach/native-rows.json)

A separate build counted entries to the bounded Row decoder inside the same intervals. At 8,008 rows, construction went from 64,128,064 calls to 8,008, and traversal from 160,340,180 to 24,024. Each completed push validates one Row. Each read-only visit accounts for three checks across the entire loop, including the initial full-span check, the cursor advance and the self-link dereference. [Counts at all four sizes](results.json)

The append proof applies to a numeric-count loop whose entire body pushes one literal Row into a named receiver. The proof reads explicit fields and defaults in declaration order. It admits literal self, strings, integers, booleans and simple numeric scalar reads. The first push validates existing rows. Each iteration enforces the open-writer and overflow checks, verifies the completed Row against its own end and publishes it to the receiver. General field expressions and other loop bodies retain full-prefix validation. [Native run contract](../../../../docs/NATIVE_RELATIVE_RUNS.md)

A foreach that can write only ordinary numeric locals of the current function may keep the next Row address after validating the whole count and span. Each view has its own checked end. Indirect assignments, rebinding and calls retain the live ordinal path. Comparing count and end alone would miss a same-size replacement with different element widths. The existing lifetime checker rejected a replacement inside a live borrowing loop. The committed control covers replacement between loops, append during foreach, row mutation, early exits, empty input and an effectful default initializer. The plain upstream runtime and both compilers agree at O0 and O2. The complete control went from 59,991 to 724 decoder calls at both levels. In separate native guard checks, increasing the committed count before the first push or before an early-exit foreach trapped at the original bounded extent. [Regression source](../../../../tests/fixtures/native_row_scans.goose) · [Control results](controls.json)

The baseline compiler was built at `90d4d19`. The runtime-only compiler `e7807a460611` and combined compiler `6dc908de22b4` produced the same benchmark C, SHA-256 `d2d31c0acbf4ba9fd8c9daebf8b6ac9401dfd293a6054ed6bcf6d877db00ee3d`. Across 10,049 output comparisons, all 26 changed artifacts use the bounded-row runtime. The isolated compiler reproduced the combined bytes for all thirteen programs at both native optimization levels. [Artifact hashes](equivalence.json)

Reproduce from the repository root with the baseline and candidate compiler paths.

```sh
source build/performance-env.sh
python bench/results/2026-11-17/native-row-scans/measure.py "$before" "$after" /tmp/native-rows.json
```
