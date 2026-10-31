# Compact enum tag qualification

Implementation: `719da82`.
Release compiler SHA-256: `83237dfe738b6b6df79ea49cb2022d22eb5b85159e2fe86733fbee5ff0037d6d`.
Debug compiler SHA-256: `daf1c6f7019184986dc8690401835d35a77c423d1089ff1a813d8ee57f05d406`.
Both prepared header trees match the implementation byte for byte.

- Full Release matrix **5283/5283**: native/C-Wasm/direct, O0/O2,
  V8 and Wasmtime, including three compile refusals.
- Debug full direct suite **2115/2115**, focused matrix **20/20**.
- Compact enum image checks **3/3** on both builds: exact packed strides,
  empty alternatives and the 256/257-variant tag-width boundary on both engines.
- Resources **86/86**, enum boundaries **6/6**, packed-layout boundaries **3/3**
  on both builds. Release also passed record-image checks **5/5**, sessions
  **11/11**, capture boundaries **6/6**, variant/owned-struct/dynamic boundaries
  **4/4 each**, array-image/sparse checks **3/3 each**, scalar-cache checks
  **13/13**, static-data checks **4/4**, and extensions **100/100**.

All enum tag readers/writers, including match, dispatch, conversions and cleanup
guards, use one byte through 256 variants and two bytes above that. Fixed-mode
enums concatenate the compact tag and maximum encoded payload without trailing
alignment. Empty alternatives contribute no payload bytes; standalone empty
variants retain their own one-byte placeholder. Empty conversion and by-value
binding avoid copying a nonexistent payload slot.

Internal layout 6 distinguishes compact tags from the variable enum's still
aligned control union. External scalar ABI 1 and 24-byte terminal owner controls
remain unchanged. Other field representations and integer-only overlap proof
boundaries are unchanged; general byte/serialization parity is not claimed.
Astra reviewed compact tag access, control alignment and empty alternatives.
See [the layout contract](../IMAGE_LAYOUT.md).

Reports in the enum-tag worktree:
`build/enum-tags-release-qualified/report.json`,
`build/enum-tags-dev-direct/report.json`,
`build/enum-tags-dev-corrected-focused/report.json`,
`build/enum-tags-release-extensions/report.json`.
Auxiliary logs: `/tmp/enum-tags-{dev,release}-*.log`.
The initial invalid empty-variant test fixture was corrected before these final
reports; its earlier failed focused report is excluded.
