# Forwarded array-result adaptation qualification

Implementation: `39f0611`.
Release compiler SHA-256: `98d51a46c4f67ec5f05132166c9d72ec9b7931fa7b7b4620815c4b172bfd8356`.
Debug compiler SHA-256: `f56e3ae4b2f92d6440286d9c1af26e78dec82f3235d97fde86bf314cde688785`.
Prepared Release headers match that implementation commit byte-for-byte.

- Full native/C-Wasm/direct differential suite: **1273/1273 observations** at
  O0/O2 on V8 and Wasmtime, including three explicit compile refusals.
- Focused Debug dynamic suite: **108/108** observations.
- Resource tests: **20/20 suites** on both engines at O0/O2, including two owned
  receiving regions reused across 10,000 exported fixed/slice forwarding calls.
- Release backend extensions **100/100**; static-data tests **4/4**; compiler
  sessions **11/11** on both builds; scalar-cache tests **13/13** on Release;
  boundary tests **3/3** on both builds.

Tests cover fixed-array, slice, reference-to-array and reference-to-slice sources,
mixed owned/fixed/scalar results, shallow aliases inside fixed elements, and later
result expressions that mutate a slice's source or rebind its referenced slot.
All results are captured using their natural ABI types before ordinal adaptation.
Astra reviewed this handling read-only.

Boundary checks also reject an inlined runtime-capacity literal received by a
growable owner; its capacity expression and checks must not silently disappear.
Reports/logs use `build/result-adaptation-*`. General anonymous owner temporaries,
variable elements and runtime limited capacity remain subsequent work.
