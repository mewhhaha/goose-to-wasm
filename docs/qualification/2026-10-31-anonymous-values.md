# Scoped growable-temporary qualification

Implementation: `57d0e08`.
Release compiler SHA-256: `10cd632b72e3262f3cf59d1e8f0f5e37245d1af87ef43ffcbb0c7ea6f6f9b55d`.
Debug compiler SHA-256: `f998bfc384192b2ed9110d6acc11ed37392a991dc7acb8e1e95f5ea3e701b1a4`.
Prepared Release headers match that implementation commit byte-for-byte.

- Full native/C-Wasm/direct differential suite: **1303/1303 observations** at
  O0/O2 on V8 and Wasmtime, including three explicit compile refusals.
- Debug temporary fixture **12/12**; existing dynamic suite **108/108**.
- Resource tests **25/25 suites** on both engines at O0/O2, with 10,000 repeated
  exported calls through mixed owned/borrowed and nested inline arguments,
  control-expression views, loop sequences, conditions, defaults and interrupted
  later arguments. Completed temporary statements release regions before recursion.
- Release backend extensions **100/100**; static-data tests **4/4**; compiler
  sessions **11/11** on both builds; scalar-cache tests **13/13** on Release;
  boundary tests **4/4**.
- Unchanged isolated Sieve kernel, official small profile: **10/10** observations
  across native, C-Wasm and direct O0/O2 on both engines. This is a correctness
  smoke check, not a new runtime-performance claim or full LangArena qualification.

Coverage includes immediate length/indexing/rendering, discarded copies, append
sources, raw-view adaptation, temporary arrays/strings, preserved named receivers
and frontend rejection of views escaping an inner block or statement.
Astra reviewed materialization and argument lifetime handling read-only.

Reports/logs use `build/anonymous-values-*`. Multiple-result anonymous calls,
function-value ownership and variable elements remain subsequent work in this slice.
