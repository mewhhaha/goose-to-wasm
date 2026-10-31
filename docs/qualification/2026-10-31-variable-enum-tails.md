# Variable enum tail qualification

Implementation: `38775f8`.
Release compiler SHA-256: `e066ddc9150379030a87f0df960db33cce3a2c1b737ff6b37211439a254e89e8`.
Debug compiler SHA-256: `8d9fe45c4f841db8e195990a54b6e07157e119e7c28e788e21285b0f8318d4c7`.
Both prepared trees matched the implementation headers before qualification;
the retained Release tree was rechecked against the implementation commit.

- Full Release differential suite **2583/2583 observations**, native/C-Wasm/direct,
  O0/O2, V8 and Wasmtime, including three compile refusals.
- Debug enum matrix **120/120** (fixed and variable payloads).
- Resource suites **54/54**, sessions **11/11**, enum boundaries **6/6**,
  standalone-variant/owned-struct/dynamic boundaries **4/4 each**, on both builds.
- Release backend extensions **100/100**, scalar-cache checks **13/13** and
  static-data checks **4/4**.

Nonresizable enums now embed supported single-tail variable records in one
stable region. Preparing the control union checks its extent before deriving
the tail base. Active copies construct independent tails and preserve runtime
capacity. Natural variant results route directly into enum payload channels;
publication rebinds their pointers to the receiving outer enum. By-value match
binders acquire independent regions and release them even in simple read arms.

Coverage includes generic nested tails, u8 length boundaries, invalid capacities,
declared defaults, ordinary/inline/mixed/recursive/control results, copied and
borrowed matches, later mutation of a named runtime-limited result, and tag changes
during interrupted million-element fills. Repeated calls preserve neighboring
canaries, release private regions, and clear omitted active optional fields after
region reuse.

Astra found that clearing inactive bytes erased saved references during tag-only
replacement returns. Construction and copying now write active fields only;
literal and standalone-call tag-only replacements preserve earlier prefix and
element references. Differently shaped nonempty replacements can expose native
packed byte overlaps. This commit conservatively refuses those observed by later
results, using provenance-aware MayReachLocal; it does not disable native NRVO.
The narrower packed-layout migration is subsequent work. Resizable/multiple-owner
payloads, variable elements, containing E.. owners and serialization remain gated.

Reports/logs: `build/variable-enum-tail-release-*` and
`build/variable-enum-tail-debug-qualified*`.
