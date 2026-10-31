# Contiguous single-tail record image qualification

Implementation: `9171bca`.
Release compiler SHA-256: `b5c00dcfa92ba75d4d9c38edbaf041d617a1b74b58fba074115fdb0b233ffd36`.
Debug compiler SHA-256: `5ee929c8b8d93331f38048dd3dc764ed478fc47867c6c50183dbeb3c91e1eeda`.
Both prepared header trees match that implementation byte for byte.

- Full Release matrix **4963/4963**: native/C-Wasm/direct, O0/O2,
  V8 and Wasmtime, including three compile refusals.
- Debug full direct suite **1987/1987**, focused record-image matrix **60/60**.
- Exact image/retained reference tests **5/5**, resources **83/83**,
  sessions **11/11**, capture boundaries **6/6**, enum boundaries **6/6**,
  variant/owned-struct/dynamic boundaries **4/4 each**, packed-layout boundaries
  **3/3**, array-image checks **3/3**, sparse-image checks **3/3**, on both builds.
- Release extensions **100/100**, scalar-cache checks **13/13**, static-data
  checks **4/4**.

Non-frame single-tail records and standalone variants store their complete packed
fixed prefix and terminal array image in one region. Independent packed offsets
route typed prefix addresses into that image while whole/nested owner references
retain aligned controls. Private tail producers preserve logical anchors through
canceled physical writes. Same-type copies preserve the full logical image and
Limited capacity; normal results land complete suffixes when construction requires
it. Enum payloads place their record images after the existing control union.

The suite inspects exact bytes on both engines, retained global/nested prefix
references through churn, authoritative edited metadata, named tuple aliases,
callback cancellation and sparse logical tails. Astra independently compared 30
native/direct observations. Internal layout 5 records the changed representation;
external scalar ABI 1 is unchanged. See [record images](../RECORD_IMAGES.md).

This checkpoint does not admit whole-record nonlocal targets or compact the whole
enum image. A subsequent effect checkpoint covers those qualified record targets
and the newly discovered existing array tuple-forwarding anchor bug; the current
matrix does not establish general nonlocal-effect parity.

Reports in the record-image worktree:
`build/record-images-release-qualified/report.json`,
`build/record-images-dev-direct/report.json`,
`build/record-images-dev-focused/report.json`,
`build/record-images-release-extensions/report.json`.
Auxiliary logs: `/tmp/record-images-{dev,release}-*.log`; the final Debug image
unit log is `/tmp/record-images-first-layout-corrected.log`.
