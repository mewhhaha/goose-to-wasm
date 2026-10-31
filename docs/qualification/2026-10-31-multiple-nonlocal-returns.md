# Multiple owned nonlocal result qualification

Implementation: `0f560af`.
Release compiler SHA-256: `e5af4c21eadf32c3779db5ae654496c593a524254a1468cce1a4f641add84a62`.
Debug compiler SHA-256: `a6e211cda48b8395384960c970aca7e90c75904ba19173b2ed8cf72d1e93f8b9`.
Both prepared header trees matched the implementation byte for byte.

- Full Release matrix **4483/4483**: native/C-Wasm/direct, O0/O2,
  V8 and Wasmtime, including three compile refusals.
- Debug focused matrix **160/160**, generic add-on **20/20**, full direct
  suite **1795/1795**.
- Resources **78/78**, compiler sessions **11/11**, capture boundaries **5/5**,
  enum boundaries **6/6**, variant/owned-struct/dynamic boundaries **4/4 each**,
  on both builds.
- Release extensions **100/100**, scalar-cache checks **13/13**, static-data
  checks **4/4**.

Any number of supported Grow/GrowShrink and single-tail Frame results may appear
beside fixed results. Every receiving cursor snapshots before any source
expression; each owned ordinal has its own private construction state, mailbox
metadata and catch landing. All snapshots commit only after the entire source
succeeds. Pending effects remain active until every winning result has landed.
Exact natural-type tuples may forward through closed ordinary producers without
adding a staging data region or changing recursive reservation bounds.

The matrix covers source-order effects, Grow/Frame combinations, independent
copies of repeated sources, cancellation and nested replacement, twelve-deep
recursive forwarding, three heterogeneous owned results and generic scalar,
Grow and Frame instantiations. Low-memory tests repeat independent receiving
regions, preserve a separately live captured source canary, and exhaust recursive
activation storage without transient data-region growth.

Unsupported owned image kinds and whole-tuple function-value/dispatch or cross-kind
forwarding retain their explicit boundaries. See [the nonlocal result contract](../NONLOCAL_RETURNS.md).
Astra reviewed the independent snapshot, commit, cleanup and landing paths.

Reports: `build/multiple-release-qualified/report.json`,
`build/multiple-debug-focused/report.json`,
`build/multiple-debug-generic-final/report.json`,
`build/multiple-debug-direct/report.json`,
`build/multiple-release-extensions/report.json` in the multiple-result worktree.
Auxiliary logs: `/tmp/multiple-{debug,release}-*.log`.
