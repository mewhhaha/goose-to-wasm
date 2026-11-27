# Direct target contract

## Engines and features

The qualified engines are V8 13.6.233.17-node.58 through Node 24.22.1, and Wasmtime
through Python package 50.0.1. The optional native C API host links the pinned
full static SDK by default; an explicit Python-shared-library fallback is available.
Both use Wasmtime 50.0.1 with different library builds. The C API host serves
32-bit direct output. The Python, Rust and Node runners also support direct
memory64 output.
`scripts/check_engines.py` assembles and executes
feature probes in both engines. It checks numeric operations, sign extension,
multi-value, bulk memory, SIMD, tail calls, memory64, multi-memory, and standard
exception handling (`try_table`). Engine support does not imply that every Goose
construct has a corresponding lowering in this backend.

The direct emitter currently uses numeric wasm32, sign extension, multi-value,
bulk-memory operations, and guarded standard SIMD128 integer lowerings. SIMD is
internal; the public Goose ABI remains numeric and boolean, with no user-facing
vector API implied. The direct emitter supports [64-bit memory](#64-bit-memory)
with `--wasm-memory64`.

## Representations and host ABI

The direct target uses i32/i64/f32/f64 numeric values. References are i32 linear
memory addresses; slices are an i64 containing a pointer in the low 32 bits and an
element count in the high 32 bits. Fixed structs and variants place fields next
to each other with alignment one; arrays use their element's allocation stride.
Other representations remain target-specific. The sections below describe
qualified layout and reference behavior.

Internal layout version 3 records packed fixed struct and variant fields,
without implicit inter-field/trailing alignment. Layout 9 adds fixed alignment
and explicit variable-prefix [padding](RECORD_PADDING.md). Each field keeps its own representation;
owner controls remain separately aligned. See
[the layout migration](IMAGE_LAYOUT.md) for its qualified byte-overlap subset.

Address-taken locals and fixed aggregates live in checked activation frames in
linear memory. Each recursive call receives its own frame. Temporary storage
and frames grow memory when necessary, within the module's declared maximum,
and are restored when their scope/function exits. Initial memory defaults to
16 pages (1 MiB), maximum memory to 256 pages (16 MiB). Driver options
`--wasm-initial-pages` and `--wasm-max-pages` configure them. One page is 64 KiB.

The backend keeps physical locations distinct from converted expression values.
All ordinary aggregate copies require the checked fixed size class; a dynamic
owner's control descriptor cannot be copied as an owned fixed value. Fresh
construction destinations retain the current activation-frame policy, and
assignment evaluates its complete RHS before publishing into its pinned target.
Exit targets record cleanup depth so scratch restorations preserve enclosing
operations that remain live. Stable regions use these same boundaries;
single growable results carry an explicit caller destination, while general
dynamic result destinations remain subsequent work.

Region-backed arrays use internal control ABI version 3: a separately aligned
24-byte control in frame/static storage. Its u32 words are base, raw length,
resource limit, raw capacity, image base and physical mode. Raw element runs use
the first four words. Variable-array values store their unsigned length prefix
in the data region; runtime-limited values store u32 capacity and length followed
by capacity slots. Views decode image metadata and derive element addresses from
the actual mode. Natural function types alone cannot identify an element-run
receiver's physical form. Owner references point to the control; element
references point directly into stable data regions. See [array images](ARRAY_IMAGES.md).
The header is never copied through the fixed-value ownership path. Initializers
construct into an acquired region, including implicit empty globals, literals,
fills, copies, slices and natural fixed-array function results.

Fixed-element variable arrays `T[]`, `T[u8/u16/u32/u64]` use the same region control
header and owned construction channels. Their size class remains variable;
their descriptor never enters the fixed-copy path. The frontend freezes their
length at construction while permitting element writes. Narrow value lengths
are checked before publication; default length storage normalizes to u32. Varint lengths,
variable elements remain refused. Supported containing structs are described below. Named-result binding
also shares a growable local's data with its variable-array result, matching
the pinned native emitter's element-run construction.

Eligible single variable-array functions have normal and element-run emission
forms. The run form omits the producer's prefix-width check and named-result
binding. Growable receivers/append, different-width variable receivers and
forwarded run requests select it; receiving value widths still check afterward.
Local and by-value parameter construction retains its own width check. Mixed
results keep natural checks and adapt receiving ordinals after all results return.
Inline bodies follow their receiving request, which can change narrow-width
behavior compared with ordinary calls, as in the pinned C oracle. Differential
cases record those O0/O2 outcomes separately.

Both forms are emitted for eligible reachable specializations. Region peaks
take their maximum and call edges are accumulated across forms. This is a
conservative bound: an unused form can increase the region count and reduce
per-region capacity compared with demand-driven emission.

Each growable result of an internal function receives an additional i32
destination-header parameter and returns that same header address. Its caller
acquires each region; the callee constructs into it before scoped cleanup.
Forwarded returns reuse the destination, including through recursive cycles.
The header/data ownership is never transferred by a shallow descriptor copy.
Mixed/multiple results preserve the existing fixed result parameter order.
Named-result locals selected by the pinned final-body analysis share their
destination's base and limit while retaining a private length header. Each
return position publishes its length at evaluation time; a later result can
mutate shared elements without changing a previously published result length.
Forwarded calls capture their natural result representations before adapting
them in order. Fixed-array/slice values and references to them can construct
owned receiving arrays without copying an owner descriptor.

Runtime-capacity limited named results instead alias their whole receiving
header, matching the native image semantics: later result expressions can change
an earlier result's live length as well as its elements. Cross-kind result
conversions involving runtime-limited arrays construct into a natural temporary
then copy into the receiving kind after capturing every returned value. Missing
owned channels for fixed receiving ordinals use natural temporaries and the
ordinary fixed-value conversion.

`T[..]` keeps its declared capacity independently of the physical region limit.
Same-type copies preserve spare capacity; construction from other array kinds
or slices chooses capacity equal to initial length. A `[..capacity]` literal
evaluates its expression once, checks the u32 range and reserves its extent with
length zero. Its effects and range check survive inline/branch optimization and
conversion to another array kind. Mutation checks both logical capacity and the
physical region limit. Assignment constructs the complete RHS into temporary
storage, copies live elements into the pinned receiver, and preserves its
capacity. Reads of the existing owner are allowed during that RHS; an early exit
before publication leaves its previous value intact apart from explicit RHS effects.

An internal by-value growable parameter receives the address of a private
header constructed by its caller. Each owned argument acquires a distinct region
before the next argument is evaluated. The caller retains these regions through
the call and then restores its argument watermark; interrupted construction
unwinds it as well. Fixed results and caller-owned dynamic result destinations
survive this cleanup. The frontend rejects escaping views into the parameter's
storage; ordinary reference/slice fields pointing to caller data preserve aliases.

Receiving regions also pass through conditionals, ordinary/early blocks,
value-producing loops and supported matches. Each exit target carries its own
channels. Break values construct before exited scopes release their regions;
loop iterations release body-local owners while retaining the receiving region.
Match scrutinees are evaluated once and divergent arms use their enclosing exit.

Whole-owner assignment reconstructs in the pinned header's existing region;
the frontend rejects RHS reads of the owner under reconstruction. Literals publish
their length before evaluating elements/fill values. Calls and control expressions
publish when their selected producer does. An exit from partial construction
checks/commits the advertised extent of headers that survive that exit. Logical
header lifetimes distinguish them from dying locals, owned parameters and private
named-result headers, even when the underlying region survives. Oversized
published counts saturate instead of wrapping before the resource check.

Named declaration receivers acquire their regions before the initializer's
temporary watermark. Explicit scopes cover statements, tails, match arms,
logical right operands, while conditions and generated default-array iterations.
Scopes restore both runtime watermarks and compile-time live-region counts.
While exits exist during condition evaluation, so condition break/continue
unwind to the current while loop.

Single owned growable expressions allocate temporary headers and regions at their
actual evaluation point. Their scope retains them through immediate views,
indexing, rendering and borrowed argument use. An owned control expression's
receiving temporary is allocated before its body. Inline argument declarations
execute outside body cleanup; borrowed argument temporaries survive that cleanup.
An argument group that materializes such an owner retains its regions until the
enclosing temporary scope ends. Fully owned argument copies keep short call
cleanup when no anonymous owner was created. No materialized value is cached by
AST identity.

Discarded mixed/multiple-result calls materialize a separate region for every
owned result. Ordinary calls evaluate value arguments before acquiring anonymous
result regions, so recursion in those arguments retains no result region.

The planner reserves dedicated global regions plus a call-graph/SCC bound on
simultaneously live transient owners. Scoped cleanup restores transient region
watermarks on normal exit, return, break and continue. Borrowed calls grow the
caller's region; growth does not relocate existing elements or slices.

Supported standalone variable structs have fixed-layout prefix fields and one
final fixed-element variable or runtime-capacity array. Their control layout
retains aligned reference/control storage and an embedded 24-byte tail control.
A separate packed image layout places prefix fields, array metadata and elements
in the owner's one data region. Typed field addresses derive from its immutable
logical tail anchor; prefix references point into region bytes. Construction
appends captured fixed fields in declaration order and uses private physical
producers for final owned fields. Copies transfer the full logical image,
including runtime capacity; normal landing moves the full physical suffix. Whole-object named-result aliasing makes prefix, length and element
mutations by later result expressions visible in an earlier result. Ordinary
and inline calls, by-value parameters and control results use owned destinations.
These objects retain `SC_VARIABLE` and never enter the fixed-copy path.
Standalone variable-size variant payloads use the same record walker, validated
independently of their siblings. Matching requires the same enum instance,
variant and enclosing enum mode. Their named returns alias the whole record;
resizable standalone variants remain outside this slice.
Final owner fields may nest recursively through fixed prefixes to the one
terminal array. Growable-tail frame structs use private prefix/length snapshots
and shared elements for named results, and support pinned whole reconstruction.
Interrupted initializers preserve fields whose positions have not been reached.

A root struct owner's frame places its components' own storage side by side,
as native C's does: each field takes the slot its type takes as a variable, so
a resizable component keeps its 24-byte control there, and an encoded integer
keeps its encoding in a 10-byte slot. The checked layout (one reference per
field) only describes the owner to the frontend; emission replaces it before
it starts. A declaration constructs each component in field order in its
place. Each component that owns storage acquires its own region, so components
grow, shrink and reach their limits independently: a local owner's regions are
transient and released with its scope, and a global owner takes one dedicated
region per such component. Owners pass by address and a field access is a
static offset. A named component (`owner.field` in an index or relative
reference type) is that field's static address in its global owner. Modules
that stay on the heap backend, for example because a component's elements own
storage, keep each component as its own heap image.

Regions partition the memory budget remaining after final static allocation.
For maximum bytes `M`, aligned static end `S` and region count `R > 0`, let
`B = align_down((M-S)/(R+1), 8)`. Activation frames and scratch occupy
`[S, M-R*B)`. The `R` stable regions divide the `R*B` bytes after it by weight.
Without a profile every weight is the same and each region is `B` bytes. With
`--wasm-region-profile FILE`, lines of `index bytes` that say what a region was
seen to need, region `i`'s weight is its bytes plus the mean of all of them, so
that a region the profile does not name still gets an average share. A
region's size is a documented per-owner resource limit, independent of
language array capacity. Increasing `--wasm-max-pages` increases these budgets.
Fixed-only modules retain the previous unpartitioned activation budget.

The region table is static data: `R+1` address-sized words, where each region
starts and, last, where memory ends. Global 9 holds its address. A region
closes with three address-sized words: its cursor, its start, and its
high-water mark. A control's limit, its third word, is the address of those
words, so the cursor of an array's region is one load away whatever the
region's size.

`--wasm-region-stats` makes the module keep the high-water marks and export
`goose.region_table` (the table's address) and `goose.region_count`. Both hosts
then print the largest with `GOOSE_REGION_STATS=1` and write all of them as a
profile with `GOOSE_REGION_PROFILE=path`. A profile says what one run needed:
take it from a run where memory is plentiful (Wasmtime, a large
`--wasm-max-pages`) and use it where it is not (V8's 16 GiB, or 32-bit).

Acquisition, growth, frames and scratch check their limits before writes;
successful `memory.grow` does not permit crossing a partition boundary. Released
regions are reused, while linear-memory pages remain allocated. Acquiring a
region grows memory to the region's end, where its three words are. The C++
compiler published the partition in a `goose.regions` custom section; this
compiler emits none.

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
| `format_f64` | `(i32,f64) -> i32` | Format a float into a caller-owned byte buffer |
| `format_f32` | `(i32,f32) -> i32` | Format a float into a caller-owned byte buffer |
| `print_bool` | `(i32) -> ()` | Boolean output |
| `newline` | `() -> ()` | End a print operation |
| `abort` | `(i32,i32,i32) -> ()` | Message pointer/length and source line; must terminate execution |
| `exit` | `(i32) -> ()` | Terminate with the requested exit status |

The `format_f32` and `format_f64` imports are emitted only when reachable string
formatting needs that width. The first argument points to 32 writable bytes in
exported memory. The host writes the same text as `print_f32` or `print_f64`,
without a terminator, and returns its byte length. Hosts check the full buffer
range before writing. Other modules retain their existing imports.

`extern fn` declarations ordinarily become imports under `env`, with their
C symbol names. Exact standard numeric signatures for `sqrt`/`gs_sqrt`, `floor`,
`ceil`, `trunc`, `fabs` (and their f32 forms), and `gs_clz`, `gs_ctz` and
`gs_popcount` `(u64) -> i64` lower to Wasm instructions instead. These operations do not call the host from numerical
loops. Ordinary Goose function bodies are not recognized by name; for example,
Goose's `abs` retains its existing negative-zero semantics.

The direct backend can load an ordinary growable array’s pointer and length together.
When the module could receive an encoded array header, the generated code checks its
storage mode and uses the image decoder as needed. In a closed program the backend
can omit this check when the checked types and casts rule out encoded controls.
Public exports, library builds and nonintrinsic user imports preserve host access
to image headers.

Use `--wasm-bundled-host` to compile a program specifically for the bundled
Wasmtime or Node host. It allows this specialization for a recognized subset of
their standard imports with matching signatures. They read values, return scalars
or fill byte arrays using `goose.reserve`. Other imports and public exports still
use the general representation. Use the default for custom host implementations
that can edit array headers.

For bundled programs with ordinary array headers, the backend records whether
any construction needs to forward updates to another header. Once all functions
and global initializers have been emitted, it can remove the forwarding calls
and saved list heads from modules that never register a destination.

An import takes numbers and booleans, and what the module holds a slice or a
reference as: a slice is the i64 of pointer and count, a reference an i32
address. It returns numbers and booleans. Other parameter and result types are
refused. An `extern "library" { ... }` declaration is an import like any other:
no library is loaded into a Wasm module, and the host stands for it.

A reference to a growable array is the address of its control. A host appends
to a growable byte array through it (the stdlib's `os.read_file`, `arg` and
`env` hand one over as their output) with the function a module that has such
an import exports: `goose.reserve(control, count) -> address`. It makes room
for `count` more bytes at the end of the array, as a `push` in the program
would (length, region cursor, memory, the same checks and the same runtime
errors), and returns where they go; the host copies them there. Control and
count are addresses: i32, or i64 with 64-bit memory. A host needs to know
nothing of controls or regions.

`hardware_threads()` is 1: the direct host ABI runs one thread of Goose code.

## 64-bit memory

`--wasm-memory64` builds the module for one 64-bit linear memory. The default
is still wasm32, and the option's existence changes none of its bytes. With
the option:

| | wasm32 | `--wasm-memory64` |
| --- | --- | --- |
| an address on the Wasm stack | i32 | i64 |
| a reference in memory | 4 bytes | 8 bytes |
| a slice on the stack | one i64: pointer in the low 32 bits, count in the high 32 | one v128: pointer in lane 0, count in lane 1, both i64 |
| a slice in memory | 8 bytes | 16 bytes: pointer at +0, count at +8 |
| a growable array's control | six u32 words, 24 bytes | the same six words as u64, 48 bytes |
| a runtime-limited array's image prefix | u32 capacity, u32 length | u64 capacity, u64 length |
| the region table and a region's three closing words | u32 | u64 |
| a function value | i64: function number low, environment address high | the same |
| `--wasm-max-pages` at most | 65,535 | 4,294,967,296 (2^48 bytes) |

Byte-length prefixes of 1, 2, 4 and 8 bytes, ULEB prefixes, enum tags and all
integer, float and bool layouts are the same in both. A function value keeps
its environment's address in 32 bits: environments live in activation frames,
and the stack is at the bottom of memory.

In [the emitter](../selfhost/codegen.goose), use `wa_*` for addresses, `wc_*`
for control words, `ws_*` for slices, `ww` for word sizes and `wn_limit` for
count limits. Check both memory widths when changing these operations.

The host interface follows the address type. `goose.write` and `goose.abort`
take the pointer as an i64 and the length (and line) as i32;
`goose.format_f32`/`format_f64` take the buffer as an i64. An import takes a
reference as an i64. A v128 cannot cross to a host, so an import takes a
slice as two i64 parameters, pointer then count. `goose.reserve` takes and
returns i64. The `goose.direct` section says `memory=wasm64`.

Engines: V8 needs `--experimental-wasm-memory64` before 13.3
(`scripts/run_wasm.mjs` sets it) and refuses a declared maximum above 262,144
pages, 16 GiB. Wasmtime has no such cap; `scripts/run_wasmtime.py` reserves
1 TiB of address space for a program given arguments, so that growing never
moves the memory. Data regions are shares of the declared maximum, which is
the reason to declare a large one where the engine allows it: only touched
pages cost memory. Where it does not, a region profile sizes the shares.

An array's element count is 64 bits too: `push`, `append`, `resize` and
literals with a repetition count check it against 2^62 - 1 instead of
2^32 - 1, and its product with the element size before it is formed. What an
array may hold is then its region's size.

Three hosts are supplied, and each takes either kind of module:
`scripts/run_wasm.mjs` (V8, through Node), `host/rust` (Wasmtime, a Rust
program; `cargo build --release` there gives
`host/rust/target/release/goose-wasmtime`) and `scripts/run_wasmtime.py`
(Wasmtime, through its Python package, which the test and benchmark harnesses
use). They provide the stdlib's `os` imports and pass the words after `--` to
the program as its arguments. The two Wasmtime hosts print the same bytes,
errors included; the Rust one starts in 0.04 s where Python takes 0.2 s.

```sh
goosew selfhost/main.goose --stdlib stdlib --target wasm-direct -O2 --wasm-memory64 --wasm-max-pages 4194304 -o goose64.wasm
host/rust/target/release/goose-wasmtime goose64.wasm --cache goose64.cwasm -- program.goose --stdlib stdlib -o program.wasm
```

`--cache` keeps Wasmtime's compiled module beside a mode-tagged SHA-256 of the module
it came from and reuses it for the same bytes. `--fast-jit` selects Wasmtime's Winch
baseline compiler (`Strategy::Winch`, automatically falling back to Cranelift
`OptLevel::None + SinglePass` for modules using exceptions, tail calls, or GC) for
~4–5× faster cold compilation on large `-O0` modules. The Rust host and the Python
runner each need a cache file of their own.

The recorded 64-bit self-check under V8 fit in 16 GiB with equal regions. The
32-bit module needed a region profile. [Measurements and profile](../bench/results/2026-11-17/lifetime-compact-reads/README.md)

```sh
build/bin/goosew selfhost/main.goose --stdlib stdlib --target wasm-direct -O2 \
  --wasm-memory64 --wasm-max-pages 262144 -o build/goose-v8.wasm
node scripts/run_wasm.mjs build/goose-v8.wasm -- selfhost/main.goose --stdlib stdlib --check
```

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
- Named fixed-element growable owners, stable views/references, initialization,
  borrowed calls, mutation, primitive rendering and scoped region reuse.
- Fixed-mode enums and fixed variant payloads, including generic/nested types,
  constructors/defaults, arrays, owned returns, and exhaustive/list/wildcard
  matches with by-value payload bindings.
- Nonresizable variable-mode enums with fixed or single-tail payloads, independent copies, internal owned
  parameters/results, mode conversion and by-value/by-reference payload matches.
- Scalar/string, closed fixed-record/variant/enum and nested fixed/limited-array
  rendering, including escaped nested byte sequences and argument snapshots;
  see [fixed aggregate rendering](FIXED_AGGREGATE_RENDERING.md).
- Struct images with direct varint fields and otherwise fixed-size fields,
  sequential field offsets, bounded decoding, copies, references and normal results;
  see [varint records](VARINT_RECORDS.md).
- Standalone immutable varint-element arrays with fixed unsigned or ULEB length metadata,
  whole slices, sequential loops, encoded copies and snapshots; see
  [varint arrays](VARINT_ARRAYS.md).
- Standalone growable varint elements with push/append/clear, whole assignment,
  stable references and private-count append forwarding; see [varint Grow](VARINT_GROW.md).
- Standalone fixed-element arrays with unsigned varint lengths, byte-authoritative
  views and successful-return prefix expansion; see [ULEB lengths](ULEB_LENGTHS.md).

- Fixed-prefix non-frame records and standalone variants with terminal encoded
  arrays, including nested single-tail records; see
  [encoded record tails](ENCODED_RECORD_TAILS.md).

The executable differential suite is the authority for qualified behavior.

## Explicit refusals and remaining work

The current backend refuses callback results that may borrow callback-local
storage, unsupported owned layouts and containing shapes (nonfinal owners, multiple variable fields and
containing variable-mode enums), variable-element
growables beyond scalar varints, encoded arrays after variable prefixes or inside variable enums, and unproved
encoded nonlocal targets; resizable/multiple-owner enum payloads;
unproven packed-overlap observations after nonempty named enum replacement;
variable enum rendering, indirect aggregate snapshots and structural comparison;
relative and pool references;
out-of-line nonlocal returns with unproven aggregate-element Var/runtime-limited arrays or unproved enum/record owned target results;
threads/queues; binary framing/serialization; custom formatters and
unsupported aggregate rendering; padded frame objects, suffix padding after
owned tails and ambiguous bare-pad fixed payloads in variable enums.
Unsupported nodes fail with a source diagnostic. There is no C fallback.

Pinned Goose function values are static and nonescaping. Runtime-selected
function pointers and heap closures are outside that language contract; the
remaining direct-target work concerns static specialization and environments.

The generic frontend can understand more language features than this target can
lower. A successful ordinary Goose type check alone is not proof that a program
belongs to the direct target's supported fragment.

## Historical C-to-Wasm profiles

The earlier C++ compiler's Emscripten and standalone memory64 outputs appear
in [dated measurements](../bench/wasmtime-host.md#historical-replay). The current
compiler emits Wasm directly or produces native C. Frozen contracts check
language-visible results and errors across targets.
