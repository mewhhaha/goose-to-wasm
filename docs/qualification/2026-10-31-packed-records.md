# Packed fixed-record qualification

Implementation: `91c71bb`.
Release compiler SHA-256: `1cbdc497b7ef89f95d9e957c7dda631fed95ce03b00c2989eabb0144467a5969`.
Debug compiler SHA-256: `fc59c58ab34f57ae369c6bcfd8dffe8d4577b829492ca052a858569d5af6b7c7`.
Both prepared header trees matched the implementation byte for byte.

- Full Release matrix **4623/4623**: native/C-Wasm/direct, O0/O2,
  V8 and Wasmtime, including three compile refusals.
- Debug focused matrix **140/140**, full direct suite **1851/1851**.
- Resources **78/78**, compiler sessions **11/11**, capture boundaries **5/5**,
  enum boundaries **6/6**, variant/owned-struct/dynamic boundaries **4/4 each**,
  packed-layout boundaries **3/3**, on both builds.
- Release extensions **100/100**, scalar-cache checks **13/13**, static-data
  checks **4/4**.

Internal layout 3 packs fixed struct and variant fields recursively. Fixed
arrays use the packed element stride; owner controls retain their separate
alignment and the external scalar ABI remains version 1. The bounded enum
replacement proof now admits nonempty records, standalone variants and nonempty
fixed arrays whose leaves are fixed-width integers. Empty outer alternatives
remain valid. Empty embedded aggregates, bool/float/reference/header-bearing
fields, nested enums and explicit padding retain their separate boundaries.

Tests cover nested field offsets, generic three-byte strides, overwrite in both
directions, ordinary/inline results, saved references, by-value snapshots before
mutation, loops, index_of, growable storage and frame prefixes. The array-size
calculation now bounds counts before multiplication and checks aligned extents
before narrowing. Huge three-byte struct and variant arrays reject at O0/O2
without an emitted module. Zero-length record fields are confirmed invalid in
the pinned frontend, rather than classified as a backend layout limitation.

Astra independently audited the recursive packing proof, control alignment and
overflow guard, and reproduced all four huge-count refusals. Variable images,
compact metadata and serialization remain subsequent work; see
[the image layout contract](../IMAGE_LAYOUT.md).

Reports: `build/packed-release-qualified/report.json`,
`build/packed-debug-focused-final/report.json`, `build/packed-debug-direct/report.json`,
`build/packed-release-extensions/report.json` in the packed-record worktree.
Auxiliary logs: `/tmp/packed-{debug,release}-*.log`.
Only final artifacts above are counted.
