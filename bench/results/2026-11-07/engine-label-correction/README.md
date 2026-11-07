# Wasmtime labels in snapshots 51 and 52

The dated prose for snapshots 51 and 52 mislabeled Wasmtime as 51.0.1 and 52.0.1. Both were measured with **Wasmtime 50.0.1**, as recorded in their raw reports, charts and library fingerprints. No measurement changed; the frozen records remain intact.

| Snapshot | Incorrect prose label | Measured engine | Raw report |
| --- | --- | --- | --- |
| 51 | 51.0.1 | 50.0.1 | [host report](../contextual-enum-dispatch/host.json) |
| 52 | 52.0.1 | 50.0.1 | [host report](../literal-array-inference/host.json) |

The [audit receipt](audit.json) pins both records and measured engine binaries. Current version text is derived from the raw reports.
