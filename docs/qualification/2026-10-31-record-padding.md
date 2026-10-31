# Record padding qualification

Implementation: `74a304f`.
Release compiler SHA-256: `8339249dff8a676babf0e4f65e9c7dd5017a4bebe22fe5f8fefc0d3d298ba8c6`.
Debug compiler SHA-256: `d1592aaf6bdf8c734057599008731fe3f3afcf6bb7a75da2ddc397092b29f326`.
Both prepared header trees match the implementation byte for byte.

- Full Release matrix **5833/5833**, native/C-Wasm/direct at O0/O2 on
  V8 and Wasmtime, including three compile refusals.
- Full Debug direct matrix **2335/2335**, focused matrix **60/60**.
- Padding byte/copy checks **5/5**, padding boundaries **5/5**, resources
  **94/94**, sessions **11/11**, capture boundaries **8/8**, enum boundaries
  **6/6**, variant/owner/dynamic boundaries **4/4 each**, packed boundaries
  **3/3**, array/sparse checks **3/3 each**, record/enum images **5/5 each**,
  enum returns **2/2**, compact tags **3/3**, static-capacity checks **5/5**,
  on both builds.
- Release extensions **100/100**, scalar-cache checks **13/13**, static-data
  checks **4/4**. Astra independently passed 20 native/direct comparisons
  and low-memory repeated-cancellation/exhaustion probes on both engines.

Fixed structs and variants preserve pad declaration indices, add explicit sizes
and align bare pads using the native next-field PadAlign. Variable non-frame
prefixes instead commit explicit pad bytes at their declaration position and
ignore bare alignment pads. Whole copies preserve host-edited padding bytes.
Semantic EmptyLayout handles zero/bare pad-only enum alternatives without adding
an encoded placeholder. Checked extent arithmetic rejects oversized/cumulative
padding before narrowing. Internal layout 9 records this transition.

Permanent coverage includes leading/consecutive/trailing pads, generic fixed
fields, reference/slice alignment, callbacks, defaults, globals and pad-only
alternatives. Byte tests inspect persistent prefix references and physical cursor
sizes. Resources prove initializer-order exhaustion and repeated-call canaries.
Padded frames, suffix pads after owned tails and fixed-payload bare gaps in E..
remain explicit refusals. No overlap, image-effect or serialization proof widens.

Reports in the padding worktree:
`build/padding-release-qualified/report.json`,
`build/padding-dev-direct/report.json`,
`build/padding-dev-focused/report.json`,
`build/padding-release-extensions/report.json`.
Auxiliary logs: `/tmp/padding-{dev,release}-*.log`.
