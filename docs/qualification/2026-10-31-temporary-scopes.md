# Temporary scope foundation qualification

Implementation: `9e763bb`.
Release compiler SHA-256: `70c7997291651c9f592ff575687bfa4733b5957806255c307f0b1867781d200e`.
Debug compiler SHA-256: `b6488454bd926a2b5f5767444f9828b62006765c3bb6fe8dc74b29621daccfff`.
Prepared Release headers match that implementation commit byte-for-byte.

- Full native/C-Wasm/direct differential suite: **1283/1283 observations** at
  O0/O2 on V8 and Wasmtime, including three explicit compile refusals.
- Debug dynamic suite **108/108**; condition-exit regression **6/6**.
- Resource tests **20/20 suites** on both engines at O0/O2.
- Release backend extensions **100/100**; static-data tests **4/4**; compiler
  sessions **11/11** on both builds; scalar-cache tests **13/13** on Release;
  boundary tests **3/3**.

The new condition regression uses an ordinary block expression inside a while
condition nested in a for loop. Condition continue/break must select the while,
release its condition-local owner and preserve the global canary. Both targets
produce `3 15 81 100` at O0/O2.

The declaration split keeps receiver acquisition outside initializer cleanup.
Statements, tails, match arms, logical right operands, while conditions and
default-array iterations now restore runtime and compile-time state together.
Astra reviewed this foundation read-only. The capability predicate only saves a
watermark; it reserves no region before evaluation or recursive calls.

Reports/logs use `build/temporary-scopes-*`. Anonymous value producers remain
refused in this slice; their next steps are in `docs/ANONYMOUS_TEMPORARIES.md`.
