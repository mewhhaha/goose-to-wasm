# Independent final audit

Run both commands from the repository root:

```sh
python bench/results/2026-11-04/direct-imports/reproduction/verify.py bench/results/2026-11-04/direct-imports
python bench/results/2026-11-04/direct-imports/reproduction/audit_results.py bench/results/2026-11-04/direct-imports
```

Both passed independently with exit 0, empty stderr, no bytecode cache and no changes to evidence. [Final audit](final-archive-audit.json) records the actual results and raw-output digests. [Byte verification](verification.json) and [semantic verification](semantic-verification.json) preserve the producer's original pre-seal results; `sealed: false` in the former describes that earlier check. The independent byte check required the manifest.

The package retains 25,439 indexed input edges, 38 current documents and zero identity-only omissions across two new archives and exactly 30 pinned prior physical archives. No historical alias graph is traversed. This includes 1,010 historical native oracle artifacts, not fresh native corpus executions; the compiler's 9,573 observations are reused. Fresh checks comprise 91 unit tests, 11,484 general-host observations and 1,914 direct-only minimal-host observations. The two streamed log archives retain 62,616 logical files; another 5,880 older compacted logs remain available.

One post-capture provenance supplement preserves the exact current [host-chart renderer](reproduction/wasmtime_host_charts.py): logical source `bench/wasmtime_host_charts.py`, SHA-256 `51e83225a5d6d84ebcc79e9149f512eba38fa1ff6f25d68ad7ba7ec4132192da`. It is bound directly by the final manifest and audit, in addition to the indexed edges. All 24 producer files, including the index and archives, remain unchanged.

The audit independently checked 430 labels and 430 MAD whiskers across eight regenerated charts, their report provenance, current report pointers and the rounded host table. The three other charts retain separate historical cohorts. Paired Functions results support 1.6% lower time than the previous minimal host; the primary native comparison remains 16.0% slower. No guest, compiler, engine or benchmark was executed for this audit.

`SHA256.json` binds every public file except itself and was written after the audit. These supplemental audit records sit outside their own archives to avoid hash cycles.
