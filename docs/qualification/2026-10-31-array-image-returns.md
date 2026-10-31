# Array image nonlocal return qualification

Final implementation: `6bec760`, including scalar escape implementation `90630fc`.
Release compiler SHA-256: `78daec143ad8ac3cd7c5b5189c5a61d96000771fc97db6d8126e1b2b853f42ac`.
Debug compiler SHA-256: `7e029205139379cc6fb04cc80bba431953bf56fe62b889501001366cfc133a05`.
Both prepared header trees matched the final implementation byte for byte.

- Full Release matrix **4903/4903**: native/C-Wasm/direct, O0/O2,
  V8 and Wasmtime, including three compile refusals.
- Debug full direct suite **1963/1963**, packed/sparse focused matrix **100/100**.
  The scalar escape matrix **140/140** also passed before the sparse-extent fix;
  all its cases are included in the final full suites above.
- Resources **83/83**, sessions **11/11**, capture boundaries **6/6**,
  enum boundaries **6/6**, variant/owned-struct/dynamic boundaries **4/4 each**,
  packed-layout boundaries **3/3**, array-image checks **3/3**, sparse-image
  checks **3/3**, on both final builds.
- Release extensions **100/100**, scalar-cache checks **13/13**, static-data
  checks **4/4**.

Standalone Var arrays with unsigned prefixes and runtime-limited arrays support
nonlocal targets with scalar elements or recursively packed fixed-width integer
records, standalone variants and nonempty fixed arrays. Entry anchors are fixed
without writing bytes; named controls remain private and share data. All source
starts snapshot before any ordinal; snapshots commit together after success.
Catch moves the entire suffix and decodes the target prefix at the saved entry.
The existing tuple mailbox, public ABI 1 and layout 4 controls remain unchanged.

The matrix covers all unsigned widths, bool/float/signed data, cancellation before
named Var/Grow/Limited declarations, recursive activation identity, mixed images,
exact closed forwarding, generic three-byte cells, nested records/arrays,
standalone variants with nonfixed siblings, capacity copies and argument aliases.
Native optimization-specific results remain explicit: scalar argument mutation
returns lengths 3/2 at O0/O2; the packed counterpart returns 3/1. Earlier scalar
ordinals produce authoritative u64 lengths 259 and 262, rather than staged counts.

A canceled fill can advertise an extent larger than its committed suffix.
Validation now maps that whole in-region extent, including Limited capacity,
without moving the physical cursor. Var/Limited/packed tests read untouched bytes
beyond the prior mapped page under a three-page limit. This fixes a real native
versus Wasm out-of-bounds mismatch discovered after the scalar candidate passed
its original matrix. That candidate is superseded by the final artifacts above.

Astra reviewed the layout proof, anchors, private prefixes, aliases and catch
paths and independently compared native/direct cancellation, argument mutation,
variant and fixed-array cases. Whole-owner and escaping local element references
remain frontend-invalid; unsupported aggregate representations and enclosing
record/enum images retain explicit gates. See [the effect contract](../NONLOCAL_RETURNS.md#array-image-targets).

Reports: `build/packed-returns-extent-release-qualified/report.json`,
`build/packed-returns-extent-dev-direct/report.json`,
`build/packed-returns-extent-dev-focused/report.json`,
`build/packed-returns-extent-release-extensions/report.json` in the packed-return worktree.
Auxiliary logs: `/tmp/packed-returns-extent-{dev,release}-*.log`.
Earlier candidates are excluded from final qualification.
