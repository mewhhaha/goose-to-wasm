# Fixed-element variable-array qualification

Implementation: `a38ded0`.
Release compiler SHA-256: `e3dee02fd952eab49c3d5ef5dc6f4944e5788f61d320adce02c3f0d13a859412`.
Debug compiler SHA-256: `17217b254d0ddf3c264f71150f2798d59201e4d64ac49476324a1c1e0312eb4d`.
Prepared Release headers match the implementation commit byte-for-byte.

- Full Release differential suite: **1323/1323 observations**, native/C-Wasm/direct,
  O0/O2, V8 and Wasmtime, including three compile refusals.
- Debug variable-array cases: **10/10**, rerun after adding the Astra review's
  same-kind named-result alias and normalized-u32 forwarding checks.
- Resource suites: **28/28** on both builds; boundaries **4/4** and compiler
  sessions **11/11** on both builds.
- Release backend extensions **100/100**, static-data checks **4/4**, and
  scalar-cache checks **13/13**.

Qualified scope: supported fixed-layout elements in default/u32-length variable
arrays, owned construction, by-value arguments, mixed results, forwarding,
named-result aliases, views, indexing, loops, primitive rendering and temporary
release. Repeated exported calls preserve independent copies without exhausting
regions. Narrow/varint lengths remain explicitly refused.

Astra reviewed the default/u32 ownership diff read-only and found no blocker.
This target-specific control representation does not establish serialized-image
compatibility. Logs/reports: `build/variable-*`. Runtime capacity belongs to the
following slice and was excluded from this Release fixture inventory.
