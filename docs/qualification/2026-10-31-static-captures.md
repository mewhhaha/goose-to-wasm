# Static capture qualification

Implementation: `8e48659`.
Release compiler SHA-256: `e24790586db1e591d97d662d618f2273ccfee8fb856ef36133f519dee85a2365`.
Debug compiler SHA-256: `a3487f804e92e44ec1b665eb62b07c24211868a97b1f6f5ca9edf060e3afb06d`.
Both prepared source trees matched the implementation before subsequent work.

- Full Release differential suite **2773/2773 observations**, native/C-Wasm/direct,
  O0/O2, V8 and Wasmtime, including three compile refusals.
- New Debug cross-backend matrix **130/130**, normal/debug frontend modes.
- Resources **59/59**, sessions **11/11**, static-capture boundaries **3/3**,
  enum boundaries **6/6**, standalone-variant/owned-struct/dynamic boundaries
  **4/4 each**, on both builds.
- Release backend extensions **100/100**, scalar-cache checks **13/13** and
  static-data checks **4/4**.

Hidden binding addresses support final-body free variables, transitive and
recursive environments, function-value remapping and global initializer roots.
Mutable reference/slice bindings share their binding slots. Captured arrays,
frame records and enum owners borrow caller-owned storage without taking an
extra region. Repeated calls preserve stored results, and interrupted writes
still check the extent of a surviving captured owner.

Function-value natural results now come from their checked body type, rather
than contextual or empty call result metadata. Fixed results construct owned
receivers exactly once. Original fixture provenance and subset/O2 restrictions
are recorded in [STATIC_CAPTURES.md](../STATIC_CAPTURES.md).

Astra reviewed the capture propagation, address spilling, hidden argument order
and borrowing lifetimes. Owned callback parameters/results, out-of-line nonlocal
returns and overload dispatch remain subsequent slices. The 130 new observations
do not claim original-corpus or full function-value parity.

Reports/logs: `build/static-capture-release-*` and
`build/static-capture-debug-*`. Earlier exploratory Debug direct reports are not
used as evidence for this final binary.
