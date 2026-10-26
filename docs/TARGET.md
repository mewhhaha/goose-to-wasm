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
memory addresses. ABI version **2** represents a slice as an i64: the high 32
bits hold its element count; the low 31 bits hold its first element's physical
address; bit 31 distinguishes chunked dynamic storage from contiguous storage.
The descriptor is copied by value. Indexed access to a tagged slice resolves
the logical position through a per-page owner map. Plain references keep stable
physical addresses when their owner's array grows.

Arrays and structs use target-specific naturally aligned layouts. Enums use an
i32 tag and an aligned payload union; standalone variants contain their payload
without the enum tag. Non-fixed owned arrays have a 64-byte owner descriptor,
including their length, chunk table, capacity information, and eight inline
chunk pointers. Fixed arrays embed their elements. This is a semantic target,
not binary compatibility with Goose's packed 64-bit C ABI. Explicit padding,
relative/pool references, and binary serialization remain refused.

Address-taken locals and aggregate descriptors live in checked activation
frames in linear memory. Each recursive call receives its own frame. The stack
grows upward; an allocator serves stable chunks from a downward-growing heap.
Both directions check their common frontier before allocating. Released heap
blocks are coalesced and reused. Array elements never relocate on growth.
Chunks have a 4 KiB minimum; many tiny arrays or strings can therefore have
substantial allocation overhead. The configured memory ceiling covers page
metadata, activation frames, chunk headers/tables and spare capacity as well as
logical payload.
Owned copies recursively copy storage; destruction follows the active enum tag
and recursively releases owned fields/elements. Returning an owned value copies
it into caller-owned storage before callee cleanup. References and slices remain
borrowed views, governed by Goose's frontend lifetime rules.

Limited arrays retain initialized slots and their addresses across `pop`,
`clear`, and shrinking operations. A same-type static-capacity whole-value copy
also replaces retained tail slots, including logical zeros where the source
has not materialized storage. Runtime-capacity assignment and adaptation from
another array/slice representation copy the live prefix and preserve the
receiver's capacity and retained tail. Only destruction of the owner releases
these stable slots and their nested owned values.

Initial memory defaults to 16 pages (1 MiB), maximum memory to 256 pages (16 MiB). Driver options
`--initial-pages` and `--maximum-pages` configure them; one page is 64 KiB. These
limits are independent of the C oracle's 16 MiB per data stack profile.
The permitted maximum is 32,768 pages (2 GiB), reserving the slice tag bit.
The first dynamic heap allocation grows the memory to its configured maximum;
this is an explicit memory reservation and initialization cost. Use a ceiling
appropriate to the workload. The page-owner map reserves four bytes per 4 KiB
of configured memory. Released array storage can be reused within the module,
but Wasm memory itself does not shrink.

Zero-initialized globals and the page map reserve addresses without adding
zero bytes to the module's data section. Only initialized string bytes are
serialized. This reduces artifact size and emitter work without reducing the
program's logical static-memory requirement. `static_memory_bytes`,
`initialized_data_bytes`, and `data_segments` distinguish those quantities in
compiler statistics.

Owned temporary slots are reused and destroyed before replacement. Function
exit releases the function's owners, including early returns. Some storage whose
lexical block has ended can remain allocated until the enclosing function exits;
this bounds repeated reuse of a static temporary but can increase peak memory.
Allocation failures terminate with a checked diagnostic. They do not silently
fall back to a native allocator or overrun the activation stack.

Modules export `memory` and `_start`. The host calls `_start` once to initialize
globals and run Goose's main function. Public scalar function exports may also
be used after initialization. Imports under module `goose` are:

| Function | Wasm signature | Meaning |
| --- | --- | --- |
| `write` | `(i32,i32) -> ()` | Write bytes from exported memory |
| `print_i64`, `print_u64` | `(i64) -> ()` | Decimal integer output |
| `print_f64` | `(f64) -> ()` | Goose-compatible float output |
| `print_f32` | `(f32) -> ()` | Goose-compatible float output |
| `format_f64` | `(f64,i32,i32) -> i32` | Render into a checked destination/capacity and return the byte count |
| `format_f32` | `(f32,i32,i32) -> i32` | f32 version of the bounded formatter |
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
Arbitrary external native libraries are not loaded into a Wasm module. A package
with a native C/CMake `.build` sidecar is rejected by the direct target instead
of silently omitting its native implementation. Supply a deliberate Wasm host
adapter for such functionality. The float-to-memory imports accept capacities
from 0 to 64, validate the complete range, and write neither truncation nor a
terminating NUL. Ship modules with matching ABI-2 hosts; the old ABI-1 hosts do
not implement the new imports.

Internal functions can return owned arrays, structs, enums, and variants,
including recursion and mixed scalar/aggregate multiple results. The caller reserves each owned result's
storage and passes a hidden i32 destination parameter. The callee captures result
expressions in order and copies owned results before releasing its frame. The
ordinary i32 result is the caller-owned address. Aggregate extern/public exports
remain refused until an explicit host ABI is provided.

## Supported target

- Signed/unsigned integer widths, narrow wrapping, masked shifts, arithmetic,
  comparisons, booleans, f32/f64 operations, and checked conversions.
- Functions, recursion, scalar/owned-aggregate multi-return, globals, and declared scalar
  externs; specialization and ordinary upstream optimizations remain in use.
- If/while/count/range/array loops, break/continue, integer and enum matches, value blocks,
  and supported optimized inline returns.
- Fixed, variable-length, capacity-limited, grow-only, and grow/shrink arrays;
  nested owned fields; structs, enum payloads and standalone variants; slices;
  supported plain/nullable references; checked indexing and stable growth.
- Array copy/append/truncate operations and string builders; scalar/string,
  nested array, struct and enum rendering; `str` and `format`, preserving
  argument evaluation and snapshot ordering.

The executable differential suite is the authority for qualified behavior.

## Explicit refusals and remaining work

The current backend refuses relative and pool references; reusable storage;
runtime function values;
non-inlined captured environments and dynamic nonlocal
returns; runtime overload dispatch; threads/queues; binary framing/serialization;
structural aggregate/slice equality; elementwise aggregate assignment;
custom formatters, optional-reference rendering before narrowing, and recursive
reference-graph rendering without an explicit nonrecursive view;
explicit packed padding; variable integer storage; and floating remainder.
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
