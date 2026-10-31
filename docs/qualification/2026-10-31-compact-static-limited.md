# Compact fixed-capacity array qualification

Implementation: `695c628`.
Release compiler SHA-256: `a936d2665e29ffdbd1d7feaef5c3c16b99b32f4fb43ce3c6112c03d143f3496a`.
Debug compiler SHA-256: `2d4da24bdee909761af6f5e21edee46ef5d667206bf1d6a60244fb101b178a06`.
Both prepared compiler header trees match the implementation byte for byte.

- Full Release matrix **5773/5773**, native/C-Wasm/direct at O0/O2 on
  V8 and Wasmtime, including three compile refusals.
- Debug baseline full direct matrix **2295/2295**. Two additional fixture-only
  cases then added wide and zero-capacity coverage. The final focused matrix
  **80/80** includes those cases and the earlier boundary/value cases, adding
  all 16 new direct observations without changing the compiler.
- Compact allocation/metadata tests **5/5**, resources **92/92**, sessions
  **11/11**, capture boundaries **8/8**, enum boundaries **6/6**,
  variant/owner/dynamic boundaries **4/4 each**, packed boundaries **3/3**,
  array/sparse checks **3/3 each**, record/enum image checks **5/5 each**,
  enum-return checks **2/2**, compact tags **3/3**, on both builds.
- Release extensions **100/100**, scalar-cache checks **13/13**, static-data
  checks **4/4**. Astra independently passed 24 native/direct comparisons.

Static `T[..k]` arrays use the minimum unsigned length width followed by packed
capacity slots. Shared width-aware accesses cover views, mutation, literals,
strings and conversions. Runtime-capacity images and aligned owner controls
remain unchanged. Extent checks divide before multiplying. Strings check actual
capacity rather than allocation size.

Standalone capacity-zero values retain the pinned C allocation's one dummy
element slot; that allocation is distinct from encoded image extent. The
frontend still rejects zero-capacity containing fields/elements. Byte tests
cover capacities 0/1/255/256/65535/65536, three-byte element strides, unaligned
u64 slots, adjacent canaries and host-edited authoritative lengths. The internal
marker advances to layout 8. This checkpoint does not widen spare-slot overlap,
owned image-effect or serialization proofs.

Reports in the static-images worktree:
`build/static-images-release-qualified/report.json`,
`build/static-images-dev-direct/report.json`,
`build/static-images-dev-final-focused/report.json`,
`build/static-images-release-extensions/report.json`.
Auxiliary logs: `/tmp/static-images-{dev,release}-*.log`.
