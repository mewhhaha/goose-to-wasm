# Direct target contract

## Engines and features

The qualified engines are V8 13.6.233.17-node.58 through Node 24.22.1, and Wasmtime
through Python package 50.0.1. `scripts/check_engines.py` assembles and executes
feature probes in both engines. It checks numeric operations, sign extension,
multi-value, bulk memory, SIMD, tail calls, memory64, multi-memory, and standard
exception handling (`try_table`). Engine support does not imply that every Goose
construct has a corresponding lowering in this backend.

The direct emitter currently uses numeric wasm32, sign extension, multi-value,
and bulk-memory operations. The C oracle's standalone profile uses memory64.
The compiler has no need to preserve compatibility with older browser engines.

## Representations and host ABI

The direct target uses i32/i64/f32/f64 numeric values. References are i32 linear
memory addresses; slices are an i64 containing a pointer in the low 32 bits and an
element count in the high 32 bits. Fixed structs and arrays use target-specific
layouts with natural alignment. This is a semantic target, not binary-layout
compatibility with Goose's packed 64-bit C ABI. Explicit padding, relative/pool
references, and binary serialization are refused until their target semantics
are implemented and qualified.

Address-taken locals and fixed aggregates live in checked activation frames in
linear memory. Each recursive call receives its own frame. Temporary storage
and frames grow memory when necessary, within the module's declared maximum,
and are restored when their scope/function exits. Initial memory defaults to
16 pages (1 MiB), maximum memory to 256 pages (16 MiB). Driver options
`--initial-pages` and `--maximum-pages` configure them; one page is 64 KiB. These
limits are independent of the C oracle's 16 MiB per data stack profile.

The module defines fresh, zero-initialized memory. Static allocations retain
their full logical size, but data segments contain only initialized nonzero
spans, coalescing zero gaps of at most 16 bytes. At most 1,024 segments are
emitted; further spans are merged into the final segment. Omitted zeros still
count toward static addresses, stack placement, initial pages, and maximum
memory checks. This reduces file size without reducing runtime memory use.

Modules export `memory` and `_start`. The host calls `_start` once to initialize
globals and run Goose's main function. Public scalar function exports may also
be used after initialization. Imports under module `goose` are:

| Function | Wasm signature | Meaning |
| --- | --- | --- |
| `write` | `(i32,i32) -> ()` | Write bytes from exported memory |
| `print_i64`, `print_u64` | `(i64) -> ()` | Decimal integer output |
| `print_f64` | `(f64) -> ()` | Goose-compatible float output |
| `print_f32` | `(f32) -> ()` | Goose-compatible float output |
| `print_bool` | `(i32) -> ()` | Boolean output |
| `newline` | `() -> ()` | End a print operation |
| `abort` | `(i32,i32,i32) -> ()` | Message pointer/length and source line; must terminate execution |
| `exit` | `(i32) -> ()` | Terminate with the requested exit status |

Scalar `extern fn` declarations ordinarily become imports under `env`, with their
C symbol names. Exact standard numeric signatures for `sqrt`/`gs_sqrt`, `floor`,
`ceil`, `trunc`, `fabs` (and their f32 forms), and `gs_clz(u64) -> i64` lower to
Wasm instructions instead. These operations do not call the host from numerical
loops. Ordinary Goose function bodies are not recognized by name; for example,
Goose's `abs` retains its existing negative-zero semantics.

Hosts must provide matching signatures and semantics for remaining imports. The supplied hosts
include input, timing, and barrier functions used by the tests and benchmarks.
Arbitrary external native libraries are not loaded into a Wasm module.

Internal functions can return fixed arrays and structs, including recursion and
mixed scalar/aggregate multiple results. The caller reserves each owned result's
storage and passes a hidden i32 destination parameter. The callee captures result
expressions in order and copies owned results before releasing its frame. The
ordinary i32 result is the caller-owned address. Aggregate extern/public exports
remain refused until an explicit host ABI is provided.

## Initial supported fragment

- Signed/unsigned integer widths, narrow wrapping, masked shifts, arithmetic,
  comparisons, booleans, f32/f64 operations, and checked conversions.
- Functions, recursion, scalar/fixed-aggregate multi-return, globals, and declared scalar
  externs; specialization and ordinary upstream optimizations remain in use.
- If/while/count/range/array loops, break/continue, integer matches, value blocks,
  and supported optimized inline returns.
- Fixed arrays, fixed struct fields, slices, and supported plain/nullable
  references, with checked indexed access and activation-local storage.
- Scalar/string and supported fixed-array rendering, including argument
  evaluation and snapshot ordering.

The executable differential suite is the authority for qualified behavior.

## Explicit refusals and remaining work

The current backend refuses variable/resizable arrays; enum/variant layouts;
relative and pool references; runtime function values;
non-inlined captured environments and dynamic nonlocal
returns; threads/queues; binary framing/serialization; custom formatters and
unsupported aggregate rendering; explicit packed padding; and floating remainder.
Unsupported nodes fail with a source diagnostic. There is no C fallback.

The generic frontend can understand more language features than this target can
lower. A successful ordinary Goose type check alone is not proof that a program
belongs to the direct target's supported fragment.

## Reference target

The pinned C backend is retained with the checked stable-stack runtime patch.
The `.mjs` profile uses Emscripten's JavaScript host and retains the earlier
wasm32-compatibility/memory64 options. The standalone `.wasm` profile uses true
memory64 and explicit LP64/WASI64 host adapters. Its supported host services are
documented by the runners, and it is not a drop-in WASI32 executable.

The direct and C targets have different internal layouts. Differential tests
compare language-visible results, errors, and side effects on the common
supported fragment. Binary C-ABI equivalence is not claimed.
