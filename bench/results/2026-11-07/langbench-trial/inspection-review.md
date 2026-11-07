# Snapshot 56 Mandelbrot inspection

Read-only inspection on 2026-11-07 while the seven-sample campaign was running. No compiler changes, builds, tests, or additional workload executions. This identifies emitted overhead; it does not measure its individual runtime contribution or promise a speedup.

Verified identities, matching the campaign's recorded artifact/source hashes:

| Artifact | SHA-256 |
| --- | --- |
| `build/langbench-trial-2026-11-07/builds/goose-wasm-wasmtime/4/program.wasm` (4,341 bytes) | `b2338da428272b85fc4425bc24b9a0e80976530c25e8281fe85d53c49070fb76` |
| `build/langbench-trial-2026-11-07/builds/goose-native/4/program` (32,584 bytes) | `33c3f00bd47e3726bbd2e63a8fb37ff893352c7bd4c6d97ffeba52c1e2bba931` |
| `build/langbench-trial-2026-11-07/builds/upstream-goose-native/4/program` (22,744 bytes) | `20594ad53b3647f84503562be0680a54632ab4dc82f0c254bd692d350ec844b8` |
| `selfhost/codegen.goose` | `c54e866326bff07e43060b8877676958e69ac3f8c6e1edc83f7dcd8588451e1b` |

The supplied disassembly `build/langbench-qualification/program.wat` hashes to `ce3397d666febf35f5a74eca6695e2ffacf76b5cf48da3c368cf745d0b04209b`. Its emission receipt is `wasm-inspection.json`.

The reachable, inlined inner loop is in function `$1`, WAT lines **1676–1844**. A completed recurrence step contains **20 resolver calls, 15 loads and 5 stores**, alongside eight floating-point arithmetic operations. These are static Wasm instructions before engine optimization; early-exit paths execute fewer. Do not count the duplicate helper body in function `$0` as additional hot-loop work. The loop has no host imports, so Python callbacks are not invoked per iteration.

The cause in lowering is concrete: `cg_prepare_function` assigns ordinary scalar bindings and parameters addressable linear-memory slots (`selfhost/codegen.goose:2820–2827`). Scalar reads and writes route through the module's pointer resolver (`3494–3497`, `576–582`). Resolver demand scans **all known types** for growable arrays (`3337–3339`), rather than emitted forwarding operations. In this module, forwarding-bound globals `$global$6` and `$global$7` are never written after initialization. Resolver `$5` therefore takes its no-forwarding return (`program.wat:2766–2783`); the emitted loop still pays the resolution machinery unless an engine removes it.

The corresponding native artifact has a register-only inner loop: `g_fn131.constprop.0`, addresses **0x40c0–0x40ee**, contains scalar floating-point arithmetic, comparison, counter update and branches, with no calls or data loads/stores. Verified with `objdump --disassemble=g_fn131.constprop.0 --no-show-raw-insn build/langbench-trial-2026-11-07/builds/goose-native/4/program`. This is a structural explanation for investigating the gap, not a measured attribution of the complete gap.

Future experiments, separately measured after publishing this baseline:

1. Gate resolver emission on reachable/emitted forwarding demand, or omit resolution for proven stable activation-local addresses. Preserve forwarding for growable arrays, moved views and aliases.
2. Promote address-unobservable, noncaptured scalar bindings to typed Wasm locals. Retain memory storage where references, closures or effects can observe addresses. Do not merely relax `m.scalar`: its current proof only accepts constant expressions/printing (`4705–4740`), and its prologue omits ordinary frame setup (`2854–2855`).
3. Require unchanged checksums at all three sizes on both engines, reference/capture/forwarding regression coverage, and paired runtime/build/startup measurements. Inspect whether the inner loop loses resolver calls and memory traffic before claiming a win.

Unused `std::parse_flt_pow10` initialization and retained helper/thunks are separate size/startup candidates; their initialization is outside the timed computation. Historical LangArena results cannot replace this fresh snapshot 56 trial: its Mandelbrot port produces and retains PBM bitmaps, uses a 50-iteration ceiling and internal warmups (`bench/langarena/ports/mandelbrot.goose`), unlike this iteration-sum workload.
