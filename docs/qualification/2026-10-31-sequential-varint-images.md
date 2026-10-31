# Sequential varint image qualification

Final implementation: `ee4a839`, including record walkers `4eac06c` and
immutable array walkers `b41bdff`.
Release compiler SHA-256: `c9c6f35b09ccbc5a0221698f3cc8ff191a73977ae52c4e07bd2c2882c0b34dc4`.
Debug compiler SHA-256: `8b5421b8dbad5b549d4e971302339110153b39396399c31edad41a92b4dcbb0b`.
Both prepared compiler header trees match the final implementation byte for byte.

- Full Release matrix **6173/6173**, native/C-Wasm/direct at O0/O2 on V8
  and Wasmtime, including three compile refusals.
- Full Debug direct matrix **2471/2471**, focused array matrix **260/260**.
- Resources **101/101**, sessions **11/11**, capture boundaries **8/8**,
  enum boundaries **6/6**, variant/owner/dynamic boundaries **4/4 each**,
  packed boundaries **3/3**, array/sparse checks **3/3 each**, record/enum
  images **5/5 each**, compact tags **3/3**, enum returns **2/2**, static
  capacity **5/5**, padding bytes/boundaries **5/5 each**, varint record bytes
  **3/3**, varint array bytes **4/4**, varint boundaries **7/7**, captured-alias
  boundary **1/1**, array boundaries **3/3**, on both final builds.
- Release extensions **100/100**, scalar-cache checks **13/13**, static-data
  checks **4/4**.

Flat varint-field records use one root control and sequential schema walks;
fixed fields after each varint follow its actual encoded width. Standalone
immutable Var arrays use fixed unsigned length metadata and sequential encoded
elements, with O(1) metadata views, whole slices and checked reference loop
bindings. Source rebinding seeks the current ordinal after checking current
length. Normal channels and exact tuple forwarding retain physical suffixes.
Array copies preserve encoded bytes, while rendering snapshots encoded extent
before later arguments. Host probes verify nonminimal byte copies, changed
field widths, authoritative counts and cursors. Layout 11 records these images;
owner controls remain 24 bytes and external scalar ABI remains 1.

Astra independently reviewed defaults, references, callbacks, casts, ordering,
normal channels, receiver rebinding, resources and alias/cancellation frontiers.
Optimized inline owned targets can expose overlong encodings after canceled
construction; final record/array gates refuse those paths consistently at O0/O2.
Named replacement later-observation/call gates cover direct and captured aliases.
Native unchecked shifts past 63 are not treated as a bounded decoding contract.
Grow elements, unsigned varint lengths, containing walkers, image effects and
serialization are separate checkpoints. Earlier candidates are superseded by
the final inline-gated source and binaries above.

Reports in the varint-arrays worktree:
`build/varint-images-inline-qualified/report.json`,
`build/varint-images-inline-direct/report.json`,
`build/varint-images-inline-focused/report.json`,
`build/varint-images-inline-extensions/report.json`.
Auxiliary logs: `/tmp/varint-images-inline-{debug,release}-*.log`.
