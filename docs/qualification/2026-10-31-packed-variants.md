# Packed fixed-variant field qualification

Implementation: `bdfce17`.
Release compiler SHA-256: `511bd56f5260afb058707c85a90f3ad98c0550976a8385af3ff369d86bda4f76`.
Debug compiler SHA-256: `4ddb1e5decf2e38b26e5b3a85498096b8993e701715654ef4a0cd8d0b7eaa265`.
Prepared Release headers match the implementation commit byte-for-byte.

- Full Release differential suite **2643/2643 observations**, native/C-Wasm/direct,
  O0/O2, V8 and Wasmtime, including three compile refusals.
- Debug full direct suite **1059/1059**, plus new cross-backend matrix **60/60**.
- Release resources **55/55**; Debug resources **54/54** plus the added packed-
  element suite **1/1**. Repeated/canary cases run on both engines at O0/O2.
- Sessions **11/11**, enum boundaries **6/6**, standalone-variant/owned-struct/
  dynamic boundaries **4/4 each**, on both builds.
- Release backend extensions **100/100**, scalar-cache checks **13/13** and
  static-data checks **4/4**.

Fixed variant fields are adjacent, with alignment one and no trailing padding;
each field retains its existing representation. The producer marker declares
`abi=1;layout=2;variant-payloads=packed-fields`; its emitted value was inspected.
The external scalar ABI and owner control header remain unchanged.

Integer-only enums now reproduce packed replacement overlap through saved named-
payload references. Tests cover both overwrite directions, signed and unsigned
widths, ordinary/inline calls and unaligned loads. A nine-byte u8+i64 variant is
exercised in fixed arrays, containing structs, owned parameters/results, retained
field references, copies, index_of and growable append. Repeated calls preserve
neighboring canaries, while the first element exceeding floor(region_bytes/9)
fails before a neighboring write. The first resource draft used resize with a
live reference, which the frontend correctly rejected; the final test uses
permitted grow-only append.

Astra reviewed the size/alignment propagation and the narrow compatibility
proof. Reference-containing replacement observations remain explicitly refused.
Bool/float/aggregate byte overlap, recursively packed fixed records, compact
metadata and full variable images remain subsequent layout slices.

Reports/logs: `build/packed-variant-release-*`,
`build/packed-variant-debug-*` and `build/packed-variant-debug-direct-qualified`.
