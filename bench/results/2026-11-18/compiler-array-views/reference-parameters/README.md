# Wasm reference parameters

Keeping an unexposed reference parameter in its incoming Wasm local reduced frozen self-check from **52.41 to 49.23 billion instructions** and self-emission from **77.43 to 73.42 billion**. The 17,219,071-byte compiler reproduced the released compiler’s 17,322,012-byte output. [Alternating runs](parameter-and-iterator-pairs.json)

| Independent default-memory64 screen | Check instructions, billions | Emit instructions, billions | Check CPU, s | Emit CPU, s |
| --- | ---: | ---: | ---: | ---: |
| Reference parameters, two rounds | 52.41 → 49.23 | 77.43 → 73.42 | 6.20 → 5.62 | 9.05 → 8.21 |
| Numeric iterator locals, same two rounds | 52.41 → 52.21 | 77.43 → 76.96 | 6.20 → 5.92 | 9.05 → 8.50 |
| Scalar pointer and count at owner indexes, one round | 52.42 → 53.38 | 77.43 → 78.48 | 6.09 → 6.13 | 8.65 → 8.21 |

The iterator experiment promoted numeric loop bindings whose addresses stayed private. Its instruction saving was below 1% in both phases. The scalar-index experiment split the ordinary control into pointer and count at each fixed-size index. It grew the compiler by 164,844 bytes and increased instructions in both phases. The reference-parameter measurements use its patch alone. The times are medians within each screen. [Iterator patch](iterator-locals.patch) · [Scalar-index patch](scalar-index.patch) · [Scalar-index run](scalar-index-screen.json)

## Storage and behavior

The emitter records the initial parameter store and direct pointer loads while generating a function. Any request for the parameter cell’s address preserves all those operations. A captured parameter, a reference rebound with `.=`, and an indirectly used cell keep their original storage. Writes through a parameter still update the pointee. Relative references, pointer forwarding and frame-prefix remapping retain the existing lowering. The function’s frame layout stays fixed. [Reference-parameter patch](reference-parameters.patch)

The frozen compiler was identical after moving the scratch list onto the module and marking every request for a slot address, including requests during parameter initialization. The four combinations of memory32/memory64 and O0/O2 exercised indexed writes through a reference, optional values, conditional rebinding and closure capture. Plain upstream Goose `d92c4315` and all four Wasmtime runs printed `8 5 [3, 7, 8]`. [Upstream run](upstream.json) [Regression fixture](../../../../../tests/fixtures/wasm_reference_parameters.goose) · [Wasmtime unit test](../../../../../tests/test_owner_view_host.py)

The larger control run matched stdout, stderr and exit status in all 24 executions. Sixteen modules changed. Four further compile attempts retained the same diagnostic for a relative reference into a variable image. Each fixture ran at both optimization levels and memory widths with a 256-page limit. [Control results and source hashes](controls.json)

## Reproduction

Build each patched emitter from a separate copy of `ac55de270cf6eff86125e94a0027813b5b902a5d` using the released native compiler. Run each resulting emitter on an **unchanged** copy of that revision to obtain the compiler module for measurement. Both steps use `selfhost/main.goose --stdlib stdlib --target wasm-direct -O2 --wasm-memory64 --wasm-max-pages 262144`.

Use the prepared comparison runner on source `90e086fe61f9ce019d6a6ef543212be63f6e1f57`, archive SHA-256 `c9474661210aed23044b05faa4aa19bacee7063aa64cd6bf3092b9af9a1fdf1d`. Pass `--cpu 4 --rounds 2` and set each expected emission to the release output with SHA-256 `d60c88511dec7c07af9cb9ca070ce03c951a63eb8f2e2bca269dcbcce19bd793`. Each sample uses a fresh instance of the prepared Wasmtime 50.0.1 module. JIT compilation is outside the timed interval. The JSON identifies the engine, modules, CPU and raw counters. [Comparison runner](../../compiler-record-access/tools/compare.py)
