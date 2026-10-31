# Active variable enum image qualification

Implementation: `b7e6b32`.
Release compiler SHA-256: `89c437259079b2bb7c7289fc870c3a1d54fa6ed73a404a589a1d307b9334073f`.
Debug compiler SHA-256: `a56774b0fd607657e36912dd91399284034dd21d09da113dbbf2acf3f86e47ae`.
Both final prepared header trees match the implementation byte for byte.

- Full Release matrix **5513/5513**: native/C-Wasm/direct, O0/O2,
  V8 and Wasmtime, including three compile refusals.
- Debug full direct suite **2207/2207**, focused image matrix **230/230**.
- Active enum byte/cursor/view checks **5/5**, compact tag checks **3/3**,
  record-image checks **5/5**, resources **87/87**, sessions **11/11**,
  capture/enum boundaries **6/6 each**, variant/owned-struct/dynamic boundaries
  **4/4 each**, packed-layout boundaries **3/3**, array-image/sparse checks
  **3/3 each**, on both final builds.
- Release extensions **100/100**, scalar-cache checks **13/13**, static-data
  checks **4/4**.

Variable-mode enums store a compact tag and active payload only. Aligned owner
envelopes retain a separate persistent control slot for each nonfixed variant;
old typed views keep their own record offsets across replacement. Inactive
alternatives reserve no data. Constructors use private physical producer controls,
while logical views stay anchored at the receiving image. Copies move active
bytes, including Limited capacity. Normal results and tuple adapters finish
original receivers after complete return-value capture, without another data lease.
Variable-to-fixed conversions use fixed snapshots rather than reusing a short
Empty image as a maximum-sized fixed union.

Native inspection found and the final candidate fixes four adaptation boundaries:
final expression annotations control single-call tag preparation; ordinary and
inline construction have different opening rules; contextual plain-Variant
references prepare tags before arguments while explicit copy evaluates its source
first; fixed enums and borrowed ADT tuple results construct in private image stages
before landing. Permanent fixtures include the pinned optimizer's distinct O0/O2
outputs. Cross-inline cases requiring actual enum effect targets remain qualified
at O2 only; O0 target admission is a separate checkpoint.

Astra independently checked old views, global borrows, copies, sparse mapping,
fixed/variable conversions, contextual calls, tuple effects and cancellation.
The final 7-comparison borrowed-result review passed. Earlier candidates exposed
real mismatches and are superseded; their reports are not final qualification.

Internal layout 7 records active payload images. External scalar ABI 1 and
24-byte terminal headers remain unchanged; control-envelope bytes are separately
budgeted. Reference widths and other field representations remain target-specific.
General serialization, unproved overlap shapes and actual enum nonlocal targets
are not claimed by this checkpoint. See [enum images](../VARIABLE_ENUMS.md).

Reports in the enum-value worktree:
`build/enum-values-borrowed-release-qualified/report.json`,
`build/enum-values-borrowed-dev-direct/report.json`,
`build/enum-values-borrowed-dev-focused/report.json`,
`build/enum-values-borrowed-release-extensions/report.json`.
Auxiliary logs: `/tmp/enum-values-borrowed-{dev,release}-*.log`.
