# Combined encoded array qualification

Implementation: `05e8074`, on unsigned lengths `7407473` and Grow elements
`fe77800`.
Release compiler SHA-256: `00c8ca2067513f0cc9a091c8795f3cf6c8688121f869dfbaa99bcf4463131231`.
Debug compiler SHA-256: `bb26282621d91d8d288d29a921d29140090838bd167db02e8669e9fd1bfbf1fd`.
Both prepared compiler header trees match the implementation byte for byte.

- Complete direct matrices: Release **2879/2879**, Debug **2879/2879**,
  O0/O2 on V8 and Wasmtime.
- Focused Release native/C-Wasm/direct matrix **400/400**, covering 20
  programs in ordinary and debug modes. Independently collected native
  outputs agree across O0/O2 and debug modes.
- On both builds: resources **108/108**, combined byte checks **3/3**,
  combined alias/effect boundaries **3/3**, and every prior image, boundary,
  capture and compiler-session auxiliary suite.
- Release extensions **100/100**, scalar-cache **13/13**, static-data **4/4**.

All compiler changes since the full Grow baseline are confined to
`compiler/direct_wasm*`; shared frontend and C emitter sources are unchanged.
The **6533/6533** Grow full matrix supplies the retained C baseline; the new
features receive focused cross-backend comparisons with the final binary.
These are separate suites, not a claim of a fresh full C matrix for this build.

Layout 14 combines an unsigned ULEB128 count with signed zigzag elements.
Known counts reserve a minimal prefix; unknown-count success moves the complete
physical suffix when expanding the original one-byte reservation. Array copies
normalize the count while preserving encoded element bytes. Metadata remains
byte-authoritative and independent of producer cursors. Tests cover count
boundaries, signed extrema, whole views, live rebinding, callbacks, cancellation,
normal/FV/dispatch and tuple channels, Grow conversions, nonminimal byte copies,
10,000 repeated named results and canaries on prefix-expansion exhaustion.
Frontend indexing restrictions, containing walkers, actual encoded targets,
unproved named Grow observations and cancelable Value-to-raw landings remain
explicit boundaries. This does not qualify serialization or verification.

Reports in the varint-combined worktree:
`build/combined-varint-release-direct/report.json`,
`build/combined-varint-debug-direct/report.json`,
`build/combined-varint-release-focused/report.json`,
`build/combined-varint-release-extensions/report.json`.
Auxiliary logs: `/tmp/combined-varint-{debug,release}-*.log`.
