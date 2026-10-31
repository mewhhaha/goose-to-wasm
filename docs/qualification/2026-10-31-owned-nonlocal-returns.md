# Single growable nonlocal return qualification

Implementation: `870f69f`.
Release compiler SHA-256: `156482cafd146bd11ad7e40c43c82efb43c8872eb145cb7f3fd14277dd65afd9`.
Debug compiler SHA-256: `4a1ecabdc95df852e399310b541f85aea46bcbfaf805b19c2cd85e31328c2599`.
Both prepared header trees matched the implementation byte for byte.

- Full Release differential suite: **3943/3943**, native/C-Wasm/direct,
  O0/O2, V8 and Wasmtime, including three compile refusals.
- Debug focused native/direct matrix: **360/360**; full direct suite:
  **1579/1579**.
- Resources **71/71**, compiler sessions **11/11**, capture boundaries **4/4**,
  enum boundaries **6/6**, variant/owned-struct/dynamic boundaries **4/4 each**,
  on both builds.
- Release backend extensions **100/100**, scalar-cache checks **13/13** and
  static-data checks **4/4**.

A single growable target constructs its escape behind existing data using a
private activation control. The catch lands the complete physical suffix and
publishes the winning logical length without allocating a staging data region.
Cancellation retains committed physical bytes. Normal return landing follows
syntactically open construction scopes, including inline and early-block exits.
Named returns retain their native shortcut.

Tests cover recursive target frames, local source slices, argument mutation,
canceled escapes followed by literal/copy/forwarded returns, selected optimizer
order differences, and coexistence with earlier record/enum behavior. Receiving
Grow lengths and Frame prefixes/base/length remain visible during interrupted
normal construction. Frame literals publish terminal base and zero length before
tail initializer arguments; array producers receive a length-only channel.
Repeated small-memory tests preserve neighboring canaries and distinguish
replaced/dying owners from surviving published extents. Compiler-session tests
compare all registered fixture modules with fresh builds across repeated requests.

The source admission remains conservative: supported reads/copies or closed
ordinary producers with qualified arguments. Variable/capacity-limited,
record/enum and mixed/multiple owned nonlocal targets remain gated in this
implementation. Existing ordinary Frame receiving paths are covered; Frame-valued
nonlocal targets are a subsequent extension. See [the contract](../NONLOCAL_RETURNS.md).

Astra reviewed the source/catch protocol, publication channels, construction
scope baselines and cleanup. Only the final artifacts above are counted;
exploratory and superseded candidate runs are excluded.

Reports: `build/owned-landing-release-qualified/report.json`,
`build/owned-landing-debug-final-matrix/report.json`,
`build/owned-landing-debug-final-full/report.json`,
`build/owned-landing-release-extensions/report.json`.
Auxiliary logs: `build/owned-landing-release-*.log` and
`build/owned-landing-debug-final-check-*.log`.
