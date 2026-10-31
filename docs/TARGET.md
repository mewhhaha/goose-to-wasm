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

Internal functions can return fixed arrays, structs, enums and variant payloads, including recursion and
mixed scalar/aggregate multiple results. The caller reserves each owned result's
storage and passes a hidden i32 destination parameter. The callee captures result
expressions in order and copies owned results before releasing its frame. The
ordinary i32 result is the caller-owned address. Aggregate extern/public exports
remain refused until an explicit host ABI is provided.

Static-capacity limited arrays `T[..k]` are fixed owned values with a u32 live
length, padding to the element alignment and inline storage for `k` elements.
Capacity is part of the type. Their views contain the element address and live
length; copying/assignment/parameters/results retain the existing fixed-value
ownership rules. Mutations evaluate the receiver once before their arguments,
then read its current length. Capacity/count/fill checks precede writes, and
`append` supports overlapping views. `push` returns a stable element reference.
Limited arrays can nest in other supported fixed values. This is a direct-target
layout, not the packed C image layout.

Sequence loops retain their location recipe: index expressions and calls on
the path run once, while reference/slice links and live lengths are reread as
iteration proceeds. Replacing a limited-array or slice slot can shorten the
remaining iteration. Bounds expressions on an index/slice capture their view
before side effects, following the pinned emitter's ordering. Indexing an outer
slice pins its element base as the native emitter does; the indexed row's live
length still changes when that slot is replaced.

Fixed-mode enums use a u32 tag at offset zero and a payload region aligned to
the most strictly aligned variant. The total size accommodates the largest
payload and is rounded to the enum's alignment. Standalone variant values hold
only their payload. Variant-to-enum conversion initializes fresh tagged storage
and copies the payload; it does not reinterpret a payload pointer as an enum.
These layouts are specific to this target, rather than the C backend's ABI.

Fixed enums and variants have the same owned parameter/result and snapshot
rules as other aggregates. Matches evaluate the scrutinee once and copy a
selected payload into its by-value binding before executing the arm. References
to fixed enums may be matched, but references into replaceable fixed-enum
payloads are prohibited by the frontend. A fixed standalone variant can be used
even when another variant of its enum requires unsupported dynamic storage.

## Initial supported fragment

- Signed/unsigned integer widths, narrow wrapping, masked shifts, arithmetic,
  comparisons, booleans, f32/f64 operations, and checked conversions.
  Floating `%` and `%=` follow `fmod`/`fmodf`: the result retains the dividend's
  sign, including signed zero. Invalid operands yield NaN. Binary scaling and
  exact subtraction run inside Wasm, without a host math import or a potentially
  overflowing quotient. Their loops are bounded by the IEEE exponent range.
- Functions, recursion, scalar/fixed-aggregate multi-return, globals, and declared scalar
  externs; specialization and ordinary upstream optimizations remain in use.
- If/while/count/range/array loops, break/continue, integer matches, value blocks,
  and supported optimized inline returns.
- Fixed arrays, fixed struct fields, slices, and supported plain/nullable
  references, with checked indexed access and activation-local storage.
- Static-capacity limited arrays, including len/cap/index_of, push/append,
  pop/pop_n/resize/clear, slices, nested storage and owned results.
- Fixed-mode enums and fixed variant payloads, including generic/nested types,
  constructors/defaults, arrays, owned returns, and exhaustive/list/wildcard
  matches with by-value payload bindings.
- Scalar/string and supported fixed-array rendering, including argument
  evaluation and snapshot ordering.

The executable differential suite is the authority for qualified behavior.

## Explicit refusals and remaining work

The current backend refuses growable arrays, variable arrays and construction-time
limited capacity; variable-mode enums;
enum rendering and comparison;
relative and pool references;
non-inlined captured environments and dynamic nonlocal
returns; threads/queues; binary framing/serialization; custom formatters and
unsupported aggregate rendering; and explicit packed padding.
Unsupported nodes fail with a source diagnostic. There is no C fallback.

Pinned Goose function values are static and nonescaping. Runtime-selected
function pointers and heap closures are outside that language contract; the
remaining direct-target work concerns static specialization and environments.

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
