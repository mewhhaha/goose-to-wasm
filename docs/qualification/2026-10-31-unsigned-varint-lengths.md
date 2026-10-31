# Unsigned varint length qualification

Implementation: `7407473`.
Release compiler SHA-256: `a20b802bae89dd2fbdea6b25b3001fadcd16dd12669321b937a6b5487841b808`.
Debug compiler SHA-256: `55626f6c48fefee4a585409defd5a687dfe41bffac4a4ad690a31f567a7e4320`.
Both prepared compiler header trees match the implementation byte for byte.

- Complete direct matrices: Release **2719/2719**, Debug **2719/2719**,
  O0/O2 on V8 and Wasmtime.
- Focused native/C-Wasm/direct matrices **260/260** on each final build,
  with ordinary/debug source modes and 13 independently collected oracles.
- On both builds: resources **106/106**, ULEB byte/authority checks **4/4**,
  ULEB boundaries **5/5**, and every previous image, boundary, capture and
  compiler-session auxiliary suite.
- Release extensions **100/100**, scalar-cache **13/13**, static-data **4/4**.

Only direct-backend compiler files changed from `fe77800`. The shared frontend
and C emitter are unchanged, so the **6533/6533** Grow full matrix supplies
the retained C baseline. Fresh focused comparisons qualify these new features
with each final binary. The redundant broader C-baseline rerun was stopped;
its partial log supplies no qualification credit.

Layout 13 adds standalone fixed-element `T[varint]` images with unsigned
ULEB128 counts. Known counts write their exact minimal prefix before elements.
Unknown ER/named Grow production reserves one untouched byte, then checks and
moves the complete physical suffix before patching on success. Control word 12
retains the original reservation width; public views decode current bytes and
prefix ends independently of producer cursors. Normal Value reprefixing,
strings, packed strides and receiver-width behavior retain their contracts.

Astra supplied the implementation plan and native oracles and identified a
later Grow alias that could overwrite an expanded prefix. The final candidate
conservatively gates those later observations and calls, including captured
aliases; final gate verification was local. Byte probes cover count boundaries,
nonminimal host prefixes, exact cursors and untouched reservations. Resource
checks cover 10,000 named results and canaries on exact-end expansion failure.
Actual encoded targets, containing/combined images, oversized static fills and
serialization/verification remain separate checkpoints.

Reports in the uleb-lengths worktree:
`build/uleb-lengths-release-direct/report.json`,
`build/uleb-lengths-candidate-direct/report.json`,
`build/uleb-lengths-release-focused/report.json`,
`build/uleb-lengths-final-focused/report.json`,
`build/uleb-lengths-release-extensions/report.json`.
Auxiliary logs: `/tmp/uleb-lengths-{final,release}-*.log`.
