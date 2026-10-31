# Whole growable-owner assignment qualification

Implementation: `66444ed`.
Release compiler SHA-256: `17dbe5a63f9b2359acbab4440bd15dce2b10767054601d7056071929b3f72d4d`.
Debug compiler SHA-256: `c0eb774a3db2e15b6c3639723f24e453ae5911c87912d8deaa4e7c1fd4948520`.
Prepared Release headers match that implementation commit byte-for-byte.

- Full native/C-Wasm/direct differential suite: **1243/1243 observations** at
  O0/O2 on V8 and Wasmtime, including three explicit compile refusals.
- Debug dynamic suite **90/90**, plus **12/12** for the added copy/slice checks.
- Resource tests **19/19 suites** on both engines at O0/O2, including oversized
  interrupted extents above UINT32_MAX, adjacent-region canaries, dying local and
  owned-parameter aliases, abandoned private named-result headers, and outer
  owners that survive break/continue.
- Release backend extensions **100/100**; static-data tests **4/4**; compiler
  sessions **11/11** on both builds; scalar-cache tests **13/13** on Release;
  boundary tests **3/3** on both builds.

The C oracle confirms producer-dependent length publication: an exit inside a
literal exposes its advertised length, while an exit in a call argument preserves
the old one. Other checks cover pinning before reference retargeting, mutable
owned parameters, independent copies, fixed/slice/conditional producers, globals
and repeated replacement. The frontend rejects direct and indirect RHS self-use.
Astra reviewed header lifetimes and abandonment checks read-only.

Reports/logs use `build/dynamic-assignment-*`. Anonymous owners,
fixed/slice-to-owned multi-result adaptation and variable elements remain later
work in this slice.
