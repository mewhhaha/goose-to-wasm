# Native Wasmtime host evidence · 2026-11-02

The host links the same Wasmtime 50.0.1 library bytes as the Python binding. Measurements use a shared AMD Ryzen 7 3800X Linux host, Goose revision `2e2bedef5b980bf013cac5aaa0095bfea64e5569` and compiler SHA-256 `3316710bb9d2b3100e94c2023000f0cb1b7517010ef04076314b4703fdcfcbba`. The ten examples reuse the qualified previous cohort's Wasm and native C artifact bytes; native C execution was freshly measured in the same shuffled runtime blocks. Direct Wasm is memory32, C-Wasm memory64.

The report records 200 fresh preparations (five per example, backend and compiler parallelism), 40 unique artifact/configuration qualifications, and 1,440 runtime observations (one warmup and 15 measured per 90 cells). All output bytes were checked. Preparation includes process launch, compilation, serialization and file writing; precompiled runtime excludes it. Serial compilation had partial wins but was rejected as a global default. All 20 serialized artifact SHA-256 values matched between parallel and serial preparation in both cohorts. The separate serial-AOT experiment uses its retained [harness](measure-serial-aot.py). Callback and I/O differences also affect host comparisons.

Full replay passed 11,340 executions over 3,780 retained case/backend/level combinations in normal default, normal serial and precompiled serial modes. Native and Python references were collected separately. Default precompiled mode additionally passed ten public WAT unit methods in four modes and twenty example artifacts; it was not included in that full replay. Numeric benchmark inputs are ASCII; arbitrary Python stdin Unicode parity is not established.

See the [comparison and reproduction instructions](../../../wasmtime-host.md) for charts, selected medians, preparation accounting and commands. Precompiled artifacts contain native code and are specific to the Wasmtime version and CPU; load trusted outputs only.

## Retained evidence

- [Main report](report.json), [serial-AOT experiment](serial-aot-experiment.json), and [host build](host-build.json).
- [Qualification summary](qualification-summary.json), [full report](qualification-report.json.gz), [boundary report](boundary-report.json), and [boundary test log](boundary-tests.log).
- [Source and guest inputs](source-and-guest-inputs.tar.gz), [benchmark samples](bench-samples.tar.gz), [qualification logs](qualification-logs.tar.gz), and [SDK headers](wasmtime-sdk-headers.tar.gz).
- [Archive map](archive-map.json.gz), [checksums](SHA256.json), and [review](review.json).

Example artifact binaries are deduplicated by SHA-256; the archive map records aliases. Full-replay Wasm and AOT binaries are omitted; their SHA-256 identities are in the qualification report. Source fixtures and compiler reproduction are in the preceding [native-gap evidence](../native-gap/README.md) and its source archives. Engine and compiler executables are omitted. The plain host ELF is retained for identity and contains an absolute library path; build from source for use.
