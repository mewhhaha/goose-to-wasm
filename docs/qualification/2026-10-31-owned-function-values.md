# Owned callback qualification

Implementation: `bfbdd8f`.
Release compiler SHA-256: `aa1a2cdd16f364d6964703b185ccd2bb3b2b63eb205b33f605045d25652f6ec4`.
Debug compiler SHA-256: `6eb6982a51badf79a3c9c6d79df45d85a83d3e0c704dfe00c4ee196b0f60fe05`.
Both prepared source trees matched the implementation before later dispatch work.

- Full Release differential suite **2953/2953 observations**, native/C-Wasm/direct,
  O0/O2, V8 and Wasmtime, including three compile refusals.
- New Debug cross-backend matrix **180/180**, normal/debug frontend modes.
- Debug full direct suite **1183/1183**.
- Resources **61/61**, sessions **11/11**, callback boundaries **3/3**,
  enum boundaries **6/6**, standalone-variant/owned-struct/dynamic boundaries
  **4/4 each**, on both builds.
- Release backend extensions **100/100**, scalar-cache checks **13/13** and
  static-data checks **4/4**.

Callbacks now admit existing owned layouts for parameters and one natural result.
Result storage precedes arguments; exact forwarding preserves recursive bounds.
Owned parameters and callback tails copy independently, fixed arguments snapshot
before later mutations, and private storage releases after the body. Repeated
calls preserve earlier returned values and reclaim parameter/body regions.

The narrow-result matrix records the native distinction: exact append element
runs can omit the natural prefix check; cross-kind receivers first construct the
natural value. Variant-to-enum adaptation, limited capacity, frame/record copies,
multiple ordinary result channels and single evaluation are covered.

Astra reviewed destination policies, logical parameter depths, temporary retention
and return copying. Borrowed results that may reach callback-local bindings are
conservatively refused, including some safe external-view parameter pass-throughs.
Out-of-line nonlocal returns remain a later effect slice. See
[OWNED_FUNCTION_VALUES.md](../OWNED_FUNCTION_VALUES.md).

Reports/logs: `build/owned-fv-release-*`, `build/owned-fv-debug-final-*` and
`build/owned-fv-debug-direct-final-qualified`. Earlier exploratory runs are excluded.
