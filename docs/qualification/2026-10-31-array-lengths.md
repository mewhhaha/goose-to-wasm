# Unsigned variable-array length qualification

Implementation: `3d1c7c2`.
Release compiler SHA-256: `88a9f6da4231a9862acf64db14cd4591f3ecedb6536653613baf21bf7eee06e1`.
Debug compiler SHA-256: `93b7f135af7d142b1e3b8e8f7b5ca276bfb5488bda0e34d24d30b8e555bd3071`.
Prepared Release headers match the implementation commit byte-for-byte.

- Full Release differential suite **2233/2233 observations**, native/C-Wasm/direct,
  O0/O2, V8 and Wasmtime, including three compile refusals.
- Debug unsigned-length matrix **750/750**, plus runtime-limited regressions
  **64/64** on both direct engines.
- Resource suites **32/32**, sessions **11/11**, and boundaries **4/4** on both builds.
- Release backend extensions **100/100**, scalar-cache checks **13/13**, and
  static-data checks **4/4**.

Fixed-element arrays now support default/u8/u16/u32/u64 length contracts. Normal
and element-run forms preserve the native producer/receiver distinction, local
and owned-parameter checks, recursive forwarding, append/control/copy use and
mixed-result conversion order. Tests cover u8 255/256 and u16 65535/65536, u64,
fixed aggregate elements, both receiving result ordinals and growable producers
converted into narrow arrays. Repeated append/export calls release their temporary
regions and preserve their data under a three-page memory limit.

Forced inlining into limited receivers permits cases the native ordinary form
rejects. Optimization-specific cases explicitly record those pinned O0/O2 oracle
outcomes. The suite does not assume identical behavior across optimization levels.
Astra reviewed the forms, receiver checks, inline constraints and scope accounting
read-only. Both forms are emitted for eligible reachable specializations; their
maximum peaks and accumulated edges form a conservative bound, which can reserve
more regions than demand-driven emission. Varint images and variable containing
values remain outside this slice.

Reports/logs: `build/narrow-variable-*`.
