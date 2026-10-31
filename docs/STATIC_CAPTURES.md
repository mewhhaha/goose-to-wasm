# Static function environments

Pinned Goose function values are compile-time specializations and cannot be
stored. The direct backend does not need heap closures or runtime function
pointers for this language rule.

Each reachable ordinary function receives hidden addresses after its runtime
parameters and before its result destinations. The addresses identify binding
storage in the current activation. Mutating a captured reference or slice binding
updates that binding, rather than a private copy. Captured owners borrow the
caller's header and region; the callee does not acquire or release their storage.
Public entrypoints have no non-global captures.

Capture analysis walks final checked/optimized bodies and global initializers,
then propagates called functions' requirements to a fixed point. It respects
function-value remapping and skips uninstantiated declaration bodies. The ordered
capture vectors determine signatures; sets only deduplicate membership. Captured
scalar/parameter bindings receive addressable frame storage. Compiler-session
requests recompute the environments from their own AST.

Function-value bodies execute at their call site. Their checked body type defines
the natural result, including when contextual adaptation requests an owned array.
A fixed result is evaluated once before constructing that receiver. Supported
owned parameters/results now use [receiving lifetimes](OWNED_FUNCTION_VALUES.md).
Out-of-line nonlocal returns now support [fixed target results](NONLOCAL_RETURNS.md).
The original full function-value capture program qualifies at O0 and O2.

The fixture provenance is pinned revision
`2e2bedef5b980bf013cac5aaa0095bfea64e5569`:

- `upstream_inline_nested_calls.goose` is the unchanged optimizer test.
- `upstream_nested_fn_scope.goose` is the unchanged nested-function scope test.
- `upstream_funval_captures_o2.goose` is the unchanged
  `test/codegen/funval_body_captures.goose`. Its historical filename records the
  initial O2-only slice; fixed nonlocal effects now also qualify O0.
- `upstream_funval_captures_subset.goose` removes only the final `find()` invocation
  from that program; its unused definition remains. This subset qualifies at O0/O2.
- `upstream_initializer_captures_subset.goose` retains G1/G3/G7/G8 unchanged from
  `test/codegen/initializer_nested_fns.goose` and supplies a smaller main. It does
  not claim qualification of the excluded initializers.

The cross-backend matrix checks native C, C-Wasm and direct output, normal/debug
frontend modes, V8 and Wasmtime. Resource tests separately exercise repeated
captures of arrays, frame/enum owners, callbacks constructed exactly once and
exhaustion checks on surviving caller-owned headers.

Case functions receive mapped captured addresses through
[runtime dispatch](FUNCTION_DISPATCH.md). Further work includes owned nonlocal
result landing and original-corpus qualification. Borrowed
callback results rooted in callback-owned storage also require care: the pinned
native emitter can release that storage before a later argument executes. Such
cases must not silently receive a different lifetime in the direct backend.
