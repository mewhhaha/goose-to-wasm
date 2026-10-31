# Record image nonlocal return and forwarding qualification

Implementation: `5d2cc26`.
Release compiler SHA-256: `8ac73c6e49953230a941d61f7c5be4b3ee65724e769d2311f54b84ae327cc7ca`.
Debug compiler SHA-256: `63937d35b06a08364644b66199f0f35df6444bf2b701a81db719d8031fcd12de`.
Both prepared header trees match the implementation byte for byte.

- Full Release matrix **5263/5263**: native/C-Wasm/direct, O0/O2,
  V8 and Wasmtime, including three compile refusals.
- Debug full direct suite **2107/2107**.
- Exact record image/retained reference checks **5/5**, resources **86/86**,
  sessions **11/11**, capture boundaries **6/6**, enum boundaries **6/6**,
  variant/owned-struct/dynamic boundaries **4/4 each**, packed-layout boundaries
  **3/3**, array-image checks **3/3**, sparse-image checks **3/3**, on both builds.
- Release extensions **100/100**, scalar-cache checks **13/13**, static-data
  checks **4/4**.

Single-tail non-frame record and standalone variant targets qualify with packed
integer fixed prefixes and qualified terminal Var/runtime-limited array images.
Entry fixes logical anchors without writing data. Private named/source controls
share receiving regions; catch copies complete successful physical suffixes to
saved entries and decodes their authoritative bytes. Aligned control offsets
remain distinct from packed image offsets for replaced-owner recognition.
Layout 5, 24-byte terminal controls and external scalar ABI 1 remain unchanged.

Fixtures cover canceled prefix fields and tails, nested records, standalone
variants, interleaved writes, sparse extents, heterogeneous multiple results,
Limited capacity and recursive activation identity. Resource tests run 10,000
calls per engine/level, enforce unchanged region counts, and preserve neighboring
canaries under data-region and activation exhaustion.

This also fixes an existing array-image bug: forwarding a tuple through an inner
actual nonlocal target reanchored the shared outer receiver. Tuple forwarding now
creates private image controls before arguments, captures every returned Wasm
value, then finishes the original receivers with the existing syntactic landing
choice. Tests retain Var and Limited array/record regressions, open construction,
argument cancellation, abandoned production and two image ordinals. Astra's
independent 20 native/direct comparisons passed; the original mismatches now
match at O0/O2. No additional data regions are leased.

Enclosing enum image effects, unproved aggregate layouts and unproved source
forms retain explicit gates. See [record image targets](../NONLOCAL_RETURNS.md#record-image-targets).

Reports in the record-return worktree:
`build/record-returns-release-qualified/report.json`,
`build/record-returns-dev-direct/report.json`,
`build/record-returns-release-extensions/report.json`.
Focused reports: `build/record-returns-dev-refocused/report.json`,
`build/record-returns-forward-focused/report.json`,
`build/record-returns-dev-forwarding/report.json`.
Auxiliary logs: `/tmp/record-returns-{dev,release}-*.log`.
