# Completing the direct compiler

This execution plan follows an Astra xhigh review of the pinned Goose frontend,
C emitter, language specification and current direct backend. Completion means
qualified support for the pinned language and its supported host profile, with
explicit incremental-cache contracts. Engine feature probes or adapted benchmark
ports alone do not establish language parity.

The machine-readable [capability inventory](capabilities.json) enumerates every
pinned builtin, AST node and array kind, plus enum/reference/host/incremental
boundaries. `python scripts/check_capabilities.py` checks vocabulary coverage and
evidence paths. A `qualified_subset` entry records only its stated scope, not
whole-feature parity. Pending entries remain in the inventory denominator.

The existing C target remains the independent semantic oracle. Each implementation
slice receives differential tests and is pushed to `main` after validation. Cloud
environment configuration is not republished as part of this work.

## Invariants and architectural decisions

- Existing element references and slices must survive grow-only growth. Keep
  direct addresses stable using checked stack regions initially. Relocating a
  conventional vector under the current i32 reference ABI is incorrect.
- Separate fixed by-value storage, borrowed locations/views and owned dynamic
  construction. Dynamic owners cannot be introduced by merely assigning a fixed
  descriptor size and reusing shallow aggregate copies.
- Reuse frontend lifetime/effect decisions and port the pinned backend's data-stack
  allocation planner; physical region assignment is not a ready-made frontend AST
  annotation. Do not create a second weaker lifetime checker in the emitter.
- Pinned Goose function values are static and nonescaping. Remaining work concerns
  specialization, capture environments and nonlocal returns. Runtime-selected
  function pointers and heap closures are not additional language requirements.
- Current natural-alignment layouts are target-specific. Image serialization and
  zero-copy `bytes_of` require a versioned layout decision. Match the pinned C.2
  image rules for serializable values before claiming cross-backend byte parity.
- Cached state must own its data, use stable identities and revalidate semantic
  dependencies. No pointer into a previous request AST may survive destruction.

## Ordered implementation phases

| Phase | Deliverable | Dependencies | Acceptance gate |
| --- | --- | --- | --- |
| 1 | Static-capacity `T[..k]` arrays | Existing fixed aggregate ABI | Literal/default/copy/assignment, views/index/slices/loops, len/cap, mutation, owned returns, aliases and capacity errors agree with the oracle |
| 2 | Locations and construction destinations | Phase 1 | Explicit fixed-copy/view/owned-construction paths; nested/scoped cleanup and return snapshots preserve ownership |
| 3 | Stable checked data stacks and grow/shrink arrays | Phase 2 | Growth preserves refs/slices; multiple owners, recursion, scope exits, calls, globals, exhaustion and checked arithmetic work within configured limits |
| 4 | Variable-size values and enum modes | Phase 3 | `T[]`, runtime-capacity `T[..]`, variable fields and `E..` construct/copy/match/return without dangling storage or shallow-owner copies |
| 5 | Static function environments and effects | Phase 2; Phase 4 for nonfixed captures | Out-of-line captures, higher-order specialization, overload dispatch and nonlocal returns work at O0 as well as optimized builds |
| 6 | Image layout, relative references, pools and serialization | Phases 3–4 | Packed image layouts, explicit padding, relative/pool refs, varints, walkers, serialization and zero-copy bytes views match pinned rules |
| 7 | Rendering, comparison and standard-library builders | Phases 3–6 as required by value types | Struct/enum/nested rendering, escaping, snapshots, formatting, structural comparison and builders agree byte-for-byte with the oracle |
| 8 | Host boundaries and concurrency | Phases 3–6 | Versioned aggregate host ABI, supported host adapters, isolated worker stacks, thread/queue lifecycle and resource limits qualify on both engines |
| 9 | General checked-function reuse | Stable identities/dependency schema; expand alongside value support | Locals/control flow/calls/generics/overloads/globals/aggregates/refs reuse only with validated type, lifetime, effect and lookup dependencies |
| 10 | Relocatable function-output cache | Phase 9 dependency contracts plus symbolic emitter output | Calls/types/globals/literals/exports relocate safely; optimization and BCE invalidation are accounted for; cold and warm output behave identically |
| 11 | Original corpus qualification and measured defaults | All applicable phases | Original language and LangArena programs pass without semantic rewrites; reproducible latency/runtime/size evidence determines cache defaults |

## Phase 1: static-capacity arrays

Keep these values in the existing fixed aggregate ownership model. The initial
direct representation is a u32 runtime length, alignment padding and inline
capacity slots. The capacity comes from the type. Centralize owner-to-view
conversion so rendering, slices, loops, indexing and conversions use the live
length rather than capacity.

Evaluate mutation receivers once before their arguments. Evaluate each argument
once in source order, then read the receiver's current length: an argument may
mutate the same array. Check negative counts, growth without fill and capacity
before writes. Preserve push's element-reference result and overlapping append.
Exercise zero capacity, exact capacity and overflow, recursive/multiple returns,
reference parameters, nested fixed values, side effects and repeated loops.

## Phases 2–4: ownership and stable dynamic storage

First introduce a typed location carrying the physical storage type and slot or
pinned address, a captured value distinguishing scalars/headers, borrowed object
addresses and owned fixed snapshots, and a construction destination carrying
storage class and lifetime. Migrate reads/writes/addressing and the repeated
argument/result/pop snapshots without changing the existing ABI. Then route fresh
literals, conversions and call results through destinations; assignment still
evaluates into a temporary before publishing to its pinned destination. Audit
every `Store`, `CaptureResult`, argument snapshot and aggregate return path.
Nonfixed values later construct into owned regions or travel as borrowed locations.
Use one fail-closed fixed-copy gate for snapshots and publication; a future
dynamic descriptor must never become an owned value through shallow byte copying.
Keep the iteration replay recipe distinct from a pinned assignment location.
Then introduce fresh construction destinations and a cleanup-action stack, initially
implementing the current scratch-top restorations on normal and nonlocal exits.
Keep conservative snapshots and the current return ABI throughout this refactor.

Port the `CodeGen::AllocStk`/`SaveBase` scope planner to assign stable regions,
with checked top/limit pairs and explicit scope watermarks. Partition sizes and total memory limits must be
observable configuration, not silent arbitrary array capacities. Reserve before
writing, reject arithmetic overflow before pointer arithmetic, and grow linear
memory without moving already assigned regions. Give globals lasting regions;
recursive activations and temporaries must release their regions on every exit.
Carry the pinned call-graph/SCC bounds into region planning, including checks on
recursive edges retaining local regions. Report region count and high-water usage.
Retain the option of a later handle ABI only as a separate measured migration.

Qualify scalar/fixed-element grow-only and grow/shrink arrays before variable
elements. Then add variable arrays, runtime limited capacity, variable fields,
variable enums and caller-destination returns. Test references across repeated
growth, nested calls and early exits, tail owners, overlapping copies, sibling
results, memory exhaustion and region-boundary canaries.

## Phases 5–8: remaining pinned-language behavior

Hidden captured binding locations now follow the current activation, including
transitive/recursive requirements and function-value remapping. Callback parameters
and single results support the admitted fixed/owned layouts, independent copies,
receiving destinations and scoped cleanup; see [static captures](STATIC_CAPTURES.md)
and [owned callbacks](OWNED_FUNCTION_VALUES.md). Borrowed callback-local results
remain conservatively gated. Runtime [case dispatch](FUNCTION_DISPATCH.md) now
shares argument snapshots, captured bindings and result destinations across its
checked arms. [Nonlocal-return effects](NONLOCAL_RETURNS.md) now cross ordinary
and dispatched calls for fixed target results, with recursive activation identity
and cross-frame cleanup. A growable-array or fixed-prefix frame result now supports staged construction
and landing beside fixed results; multiple owned results and variable/non-frame
record/enum targets remain the next extension.
Tests include O0 programs that cannot depend on optimizer inlining.

Before serialization, document the image ABI, pointer width/encoding and the
compatibility transition from the current direct representation. Implement
layout/cursor walkers once for constructing, validating, copying and accessing
variable images. Relative offsets must be measured from the correct slot/root;
pool identity, reuse and free-list invariants need runtime checks. Compare byte
fixtures and malformed/truncated images, not only round trips.

Build rendering/comparison recursively on these representations. Preserve eager
argument snapshot ordering, nested escaping, float edge behavior and formatter
effects. Add builders and standard-library dependencies as their underlying
runtime operations become available.

Specify aggregate host parameters/results, ownership and initialization before
exporting them. Threads require actual worker isolation, queue image transfer,
join/error propagation and host support in both V8 and Wasmtime. Count unsupported
platform services separately and name the resulting host profile precisely.

## Phases 9–10: reusable semantic and emitted work

Grow the existing opt-in scalar cache in bounded steps: locals and control flow;
computed call arguments; overload/generic selection; globals/constants; then
aggregate, reference, lifetime and nonlocal-effect environments. Use pointer-free
frozen IR with explicit identity/import mappings. Record both selected targets
and negative lookup facts, concrete type/layout versions, constants, effect
summaries and relevant configuration. Callee body edits can preserve callers
only when their checked contract remains valid.

For each expansion, compare cold/warm/mixed requests and diagnostics, source
positions, failed builds, eviction, worker restarts and adversarial invalidation.
Use sanitizers for ownership imports. Keep finite cache budgets and fallback
paths for incomplete dependencies.

Emit symbolic references before caching function output. Store relocation records
for calls, imports, signatures, globals, data and source diagnostics. Include
optimization inputs and inlining/BCE dependencies in keys; a previously valid
checked body does not alone validate optimized code. Resolve indices and publish
whole modules atomically in the current build. Fuzz reordered reachability and
literal placement. Measure end-to-end latency before enabling a cache by default.

## Phase 11: qualification and completion evidence

Maintain a feature-to-test matrix distinguishing implemented, qualified,
frontend-invalid and host-unavailable cases. Run O0/O2 and debug where meaningful
against native C, C-Wasm, direct V8 and direct Wasmtime. Extend input transcripts
to all embedded/package inputs before caching those builds.

Track original LangArena programs independently of bounded adapted ports; restore
original storage as each prerequisite lands. Include original threaded tasks
only after actual thread support passes. Run the pinned language corpus and
representative standard-library/sample programs with deterministic input, exit,
diagnostic and artifact identities. Retain failing/minimized cases rather than
counting refusal as semantic success.

Retain repeated cold/unchanged/edited build measurements, phase timings, memory
high-water marks, runtime and artifact size. Cache-hit counts demonstrate skipped
work; only controlled wall-time evidence establishes a speed improvement. Final
completion requires the applicable original corpus, documented host/ABI contracts
and no unexplained omissions in the feature matrix.
