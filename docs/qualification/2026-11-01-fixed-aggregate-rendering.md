# Closed fixed aggregate rendering qualification

Implementation: `a3809e7`.
Release compiler SHA-256: `d03f359f5741ccfa91d0cee737f87f7195db05ec44e0c558ef2d3c05e4afe90d`.
Debug compiler SHA-256: `1bed6ad9945f3e45af1dcc1c468a57c4cc870c00b233bf1939f0af6cfb49e4b8`.
Both prepared compiler header trees match the implementation byte for byte.

- Complete direct matrices: Release **3071/3071**, Debug **3071/3071**,
  O0/O2 on V8 and Wasmtime.
- Focused Release native/C-Wasm/direct matrix **260/260**, with 13 programs
  in ordinary/debug modes and independently collected native oracles.
- On both builds: resources **111/111**, binary-output comparison **1/1**,
  rendering boundaries **3/3**, and every previous image, boundary, capture
  and compiler-session auxiliary suite.
- Release extensions **100/100**, scalar-cache **13/13**, static-data **4/4**.

Only direct-backend compiler files changed; shared frontend and C emitter
sources remain unchanged from the retained **6533/6533** Grow full matrix.
Fresh focused comparisons cover the new rendering behavior, while the complete
matrices above exercise the direct backend.

Closed fixed structs, variants and enums now render with native nominal names,
positional fields, pad omission and active fixed-tag routing. Arrays/slices of
these recursively fixed values retain independent snapshots. Nested bytes quote
and escape exactly the native five characters, passing other bytes unchanged.
Unescaped spans use bulk host writes. Mutation in later arguments cannot change
an earlier argument's captured value; nested print order agrees with native.

Tests cover generics, empty values, packed/padded fields, nested arrays, static
capacity, floats, ordinary/FV parameters, aliases, mutation snapshots and tags
through 257 variants. A binary comparison checks NUL and invalid UTF-8 bytes
against native C on both engines. Resource checks repeat 2 KiB snapshots 10,000
times without another data region, preserving a neighboring canary. Fixed
aggregates containing references/slices, variable images, optional references
and user formatters remain explicitly gated. The formatter gate also covers
nested values and arrays. Image layout and external scalar ABI are unchanged.

Reports in the aggregate-print worktree:
`build/aggregate-print-release-direct/report.json`,
`build/aggregate-print-debug-direct/report.json`,
`build/aggregate-print-release-focused/report.json`,
`build/aggregate-print-release-extensions/report.json`.
Auxiliary logs: `/tmp/aggregate-print-{debug,release}-*.log`.
