# Owned control-expression qualification

Implementation: `ef941dc`.
Release compiler SHA-256: `a385ae289e0ce6fe3cdb394c1142125c7fed849ce26d497a0533d957ad392260`.
Debug compiler SHA-256: `77a472de9260e42de08f5a92072c8e8e8ab0f64323219655b16f8d076d41d108`.
Prepared Release headers match that implementation commit byte-for-byte.
The separate Release build is `build/control-release/bin/goose`.

- Full native/C-Wasm/direct differential suite: **1223/1223 observations** at
  O0/O2 on V8 and Wasmtime, including three explicit compile refusals.
- Focused Debug native/direct dynamic suite: **78/78** observations.
- Resource tests: **16/16 suites** on both builds and engines at O0/O2, including
  10,000 exported calls through nested loop/match/early-block construction.
- Release backend extensions **100/100**; static-data tests **4/4**; compiler
  sessions **11/11**; checked scalar-cache tests **13/13**; boundary tests **2/2**.

Coverage includes break values constructed before scope cleanup, iteration-local
owners released on continue, early returns from divergent match arms, one-time
scrutinee effects, fixed enum payload bindings, and direct receiving declarations.
Astra reviewed the destination routing and cleanup read-only.

Reports/logs use `build/dynamic-control-*`. Reproduce with the test scripts'
`--goose build/control-release/bin/goose` option. Whole-owner assignment,
anonymous owner temporaries and fixed/slice-to-owned multi-result adaptation
remain subsequent work in this slice.
