# Unsigned array value image qualification

Implementation: `825f33a`.
Release compiler SHA-256: `df7289dbbfa5d59a9eac724b08e2f81beea0d1fc00578ac47174265d8f0a3039`.
Debug compiler SHA-256: `2a6b762d877dd7e6118bcb8b5ca32fb3d5a7a855f8fd94e2e85b00ba5858cb1b`.
Both prepared header trees matched the implementation byte for byte.

- Full Release matrix **4663/4663**: native/C-Wasm/direct, O0/O2,
  V8 and Wasmtime, including three compile refusals.
- Debug focused matrix **40/40**, full direct suite **1867/1867**.
- Resources **78/78**, compiler sessions **11/11**, capture boundaries **5/5**,
  enum boundaries **6/6**, variant/owned-struct/dynamic boundaries **4/4 each**,
  packed-layout boundaries **3/3**, array-image checks **3/3**, on both builds.
- Release extensions **100/100**, scalar-cache checks **13/13**, static-data
  checks **4/4**.

Internal layout 4 uses separately aligned 24-byte owner controls. Physical modes
separate raw element-run channels from Var values with unsigned length prefixes
and runtime-limited values with u32 capacity/length prefixes in their region.
Views read authoritative metadata and derive element bases. Normal result staging
preserves receiving anchors; copies initialize prefixes after capturing sources,
limited copies preserve capacity extents, and alternate returns preserve saved
reference observations. Actual image nonlocal targets remain gated in this slice.

Call adaptation distinguishes ordinary Grow-to-Var temporary/copy paths from
control-only Var element-run and no-element-run prefix adapters. The latter check
pending effects before sliding the complete suffix. New regression tests cover
copied fixed arrays, normal multi-result reprefix/slide paths that grow past 255,
and alternate limited named returns. Host inspection on both engines verifies
all unsigned prefix widths, packed three-byte element strides, capacity/length
bytes and authoritative metadata reads.

Astra independently reviewed the controls and call/return ordering, found three
issues addressed by the final regression fixtures, and checked related copies,
ordinals, aliases, spare capacity and interrupted construction at O0/O2. Earlier
candidate reports are excluded. Whole enclosing record/enum images, varints,
variable elements, serialization and image-target NLR remain separate extensions.
See [the array-image contract](../ARRAY_IMAGES.md).

Reports: `build/images-release-qualified/report.json`,
`build/images-third-focused/report.json`, `build/images-third-direct/report.json`,
`build/images-release-extensions/report.json` in the array-image worktree.
Auxiliary logs: `/tmp/images-third-*.log`, `/tmp/images-release-*.log`.
