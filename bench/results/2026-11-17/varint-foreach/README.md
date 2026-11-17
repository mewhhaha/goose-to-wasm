# Linear varint traversal in direct Wasm

A checksum loop over 8,008 mixed-width varints falls from 162 ms to 0.129 ms on Wasmtime and from 169 ms to 0.087 ms on V8 with 32-bit memory. The emitted loop previously found each value by decoding its entire prefix again. A top-level loop over an immutable incoming slice parameter can now keep its last encoded address. The preceding statements and the loop body can only write ordinary numeric locals belonging to the current function. The next iteration advances past that element after checking its live bound. Calls, slice rebinding, captured variables as write targets and indirect stores retain the ordinal lookup. [Source change](runtime.patch) · [workload](sum.goose)

| Engine and memory | 1,001 items, before → after (ms) | 4,004 items | 8,008 items |
| --- | ---: | ---: | ---: |
| Wasmtime 32 | 2.043 → 0.033 | 40.415 → 0.062 | 161.608 → 0.129 |
| V8 32 | 7.405 → 0.025 | 41.373 → 0.042 | 169.399 → 0.087 |
| Wasmtime 64 | 3.011 → 0.044 | 61.051 → 0.082 | 241.412 → 0.183 |
| V8 64 | 5.563 → 0.032 | 48.848 → 0.050 | 184.832 → 0.115 |

Each cell uses seven rounds with alternating compiler order, after two warmups at that count. The resident engines reuse each prepared module with a fresh instance per invocation. The guest reads a monotonic clock around the sum, after constructing the input and before checking output. Every result matched an independent sum. Shared host load introduced variation, including two 3–5 ms candidate samples for V8 memory64 at 8,008 items. The table gives separate medians. Node 24.22.1, V8 13.6.233.17-node.58 and Wasmtime 50.0.1 ran on CPU 6. [Raw pairs and tool hashes](results.json)

As a load-independent check, a separate Wasmtime run replaced the benchmark clock with guest fuel consumed. Growing from 201 to 1,608 elements increased the old 32-bit loop's cost from 2,841,848 to 180,426,353 fuel units (63.5×). The new loop took 65,187 to 520,754 units (8.0×). Memory64 measured 63.5× and 8.0×. The new modules shrink by 17 and 15 bytes respectively. [Fuel by input size](results.json)

The installed baseline is `9551a58` (`e5cf838d7572…`). Timings used an initial candidate (`cd6c6a2dbcda…`). It also optimized local slices, which was too broad. In the regression program a bounded reference reinterpretation makes an encoded slice over a local word. A write to that word changes the width of the first encoding. The broad cursor printed 6 where baseline prints 7. The retained compiler limits the proof to caller storage and checks the function prefix, so earlier calls or reference conversions cannot rebind the slice to callee locals. [Regression program](../../../../tests/fixtures/varint_cursor_alias.goose) · [final source patch](runtime.patch)

The final isolated compiler (`9352c9c3a485…`) and the combined build emit exactly the two timed modules. Both produce 7 on the alias regression and −24579 on the largest timed input. All ten full examples, langbench Mandelbrot, the existing growth/rebinding fixture and the alias regression produced identical bytes across baseline and both final compilers at both widths. The isolated compiler reproduced all ten changed modules from the combined compiler’s output-equivalence run. [Artifact hashes](controls.json) · [equivalence attribution](equivalence.json)

The loop tests cover skipped elements, early exit, an empty sequence and slice rebinding at O0 and O2, debug and release. The alias regression runs on both engines at both memory widths. Wasmtime fuel bounds the cost of a reduction in the test suite. [Loop tests](../../../../tests/test_loop_ordinals.py)

Native arrays of bounded self-relative rows retain a separate quadratic cost. Each push validates the committed prefix, and foreach revalidates and seeks from the start. With 1,001 → 8,008 rows, construction rose from 4.29 → 302.44 ms and traversal from 10.83 → 706.19 ms. This was one sample per size on the baseline compiler and GCC 16.2.1, with the checksum checked independently. [Native workload](native_rows.goose) · [commands, tool hashes and timings](native-rows.json)

From the repository root, activate the pinned tool environment and supply the compiler executables.

```sh
source build/performance-env.sh
trial=bench/results/2026-11-17/varint-foreach
python "$trial/measure.py" "$before" "$after" /tmp/varint-timings.json 6
python "$trial/controls.py" "$before" "$after" "$combined" /tmp/varint-controls.json
```
