# Fixed and one-owned nonlocal result qualification

Implementation: `4f75b56`.
Release compiler SHA-256: `0130e1780a1eb55c7dd7241fd84e4f6a2889339c4c620860991b126ce278ed87`.
Debug compiler SHA-256: `1f772b69d45156e68783f99abeb3280761e8f7e9cd18a4f81b188eed2fcfc98f`.
Both prepared header trees matched the implementation byte for byte.

- Full Release matrix **4303/4303**: native/C-Wasm/direct, O0/O2,
  V8 and Wasmtime, including three compile refusals.
- Debug focused matrix **180/180**, full direct suite **1723/1723**.
- Resources **75/75**, compiler sessions **11/11**, capture boundaries **5/5**,
  enum boundaries **6/6**, variant/owned-struct/dynamic boundaries **4/4 each**,
  on both builds.
- Release extensions **100/100**, scalar-cache checks **13/13**, static-data
  checks **4/4**.

One Grow/GrowShrink or supported Frame result may appear at any ordinal beside
fixed/scalar/reference/slice results. Its receiving cursor is captured before
any source expression. Fixed aggregate values snapshot in order; all successful
values commit to the mailbox together. Exact-type tuples may forward through a
closed ordinary producer, evaluating arguments once and using the existing
receiving region. No staging data region or new recursive reservation is added.

Tests cover earlier scalar effects on the same region, Grow versus Frame base
behavior, aggregate snapshots before later mutation, cancellation and nested
replacement, owned positions first/middle/last, borrowed reference holders and
slice headers, and element-run variable-array producers with push arguments.
The cancellation fixture records distinct native O0/O2 outputs: optimized local
returns retain normal per-ordinal landing rather than the out-of-line attempt's
all-results commit. Repeated low-memory checks preserve canaries, reuse one
receiving region, and replace oversized abandoned Grow and Frame values.

Whole-tuple forwarding requires exact natural types and the closed-source proof.
Function-value/dispatch tuple sources, cross-kind tuple adaptation, multiple
owned results and unsupported owned image kinds remain separate extensions.
See [the mixed-result contract](../NONLOCAL_RETURNS.md#fixed-results-beside-one-owned-result).

Astra independently checked ordering, aliases, cancellation, ordinal placement
and forwarding at both optimization levels and reviewed the staging/catch paths.
Only final artifacts above are counted.

Reports: `build/mixed-release-qualified/report.json`,
`build/mixed-debug-focused-final/report.json`, `build/mixed-debug-direct/report.json`,
`build/mixed-release-extensions/report.json` in the mixed worktree.
Auxiliary logs: `/tmp/mixed-{debug,release}-*.log`.
