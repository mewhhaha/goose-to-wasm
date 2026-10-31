# Terminal encoded record-tail qualification

Implementation: `5e1e669`.
Release compiler SHA-256: `de9e68b05de182c9eba6b9ad2595dce0a1f4d5c0520bcf3c2fe11b329d8dd512`.
Debug compiler SHA-256: `d2f85bee17da059bc74153abb2c8719503f4abccbe0cd113ec097b9363834640`.
Both prepared compiler header trees match the implementation byte for byte.

- Complete direct matrices: Release **2967/2967**, Debug **2967/2967**,
  O0/O2 on V8 and Wasmtime.
- Focused Release native/C-Wasm/direct matrix **220/220**, with 11 programs
  in ordinary/debug modes and native oracles stable across O0/O2.
- On both builds: resources **110/110**, new record-tail byte/authority
  checks **4/4**, record-tail boundaries **3/3**, and every previous image,
  boundary, capture and compiler-session auxiliary suite.
- Release extensions **100/100**, scalar-cache **13/13**, static-data **4/4**.

Shared frontend and C emitter sources remain unchanged from the retained Grow
full matrix, **6533/6533**. All intervening compiler changes are confined to
`compiler/direct_wasm*`; fresh focused cross-backend comparisons cover the
new behavior. The complete matrices above exercise the direct backend.

Layout 15 admits terminal varint-element, ULEB-count and combined arrays in
fixed-prefix non-frame records and standalone variants, including nested
single-tail records. Extents walk encoded elements and decode actual count
prefix ends. Record copies preserve the entire logical image, including
nonminimal prefix/element encodings, while normal result landing moves full
physical suffixes. Existing prefix references keep stable byte addresses.

Tests cover defaults, copies, nested prefixes, variants, normal/inline/FV/
dispatch and tuple channels, Grow-produced tails, callback cancellation,
authoritative host counts, saved prefix references and separate cursors.
Resource tests perform 10,000 recursive result forwards without another data
lease and preserve a neighbor canary on exact-end prefix expansion failure.
Actual encoded record targets, variable prefixes, frame varint tails,
enclosing variable enums and unproved named replacement observations remain
explicitly refused. Serialization and general variable-field references are
separate work. Host-edited byte probes are outside the verifier API.

Reports in the encoded-record-tails worktree:
`build/encoded-record-tails-release-direct/report.json`,
`build/encoded-record-tails-debug-direct/report.json`,
`build/encoded-record-tails-release-focused/report.json`,
`build/encoded-record-tails-release-extensions/report.json`.
Auxiliary logs: `/tmp/encoded-record-tails-{debug,release}-*.log`.
