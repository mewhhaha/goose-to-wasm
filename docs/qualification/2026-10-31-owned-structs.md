# Variable and runtime-limited tail struct qualification

Implementation: `dd88a7d`.
Release compiler SHA-256: `f5bb4fdf8679acd355ed4ba1225acae2f8bb44a5874321c6c8d99fb58f6e2583`.
Debug compiler SHA-256: `ddf456129f5d6cf8dae09daaa6697775def266394d49dee3a3b2b6029f75e2ea`.
Prepared Release headers match the implementation commit byte-for-byte.

- Full Release differential suite **2333/2333 observations**, native/C-Wasm/direct,
  O0/O2, V8 and Wasmtime, including three compile refusals.
- Debug containing-value matrix **100/100 observations**.
- Resource suites **36/36**, sessions **11/11**, owned-struct boundaries **4/4**
  and dynamic boundaries **4/4** on both builds.
- Release backend extensions **100/100**, scalar-cache checks **13/13** and
  static-data checks **4/4**.

The supported shape has fixed-layout prefix fields and one final fixed-element
variable or runtime-limited array. Tests cover generic fixed elements, global
defaults, independent copies and parameters, prefix references, declaration-order
effects, early returns from prefix/tail construction, control destinations,
narrow length checks, capacity-preserving field assignment and whole-object
named return aliasing. Repeated exported calls run under a three-page memory
limit; canaries verify that oversized tails preserve neighboring regions.

Nested owners, multiple variable fields, variable elements and growable-tail
frame objects remain outside this qualified slice. Packed images, rendering and
comparison need later work. The frontend continues to enforce frozen whole
variable structs and private parameter view lifetimes.

Reports/logs: `build/variable-struct-release-*` and
`build/variable-struct-debug-final-*`.
