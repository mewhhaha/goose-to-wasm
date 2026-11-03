# Performance campaign · November 2–3, 2026

The delivered compiler is SHA-256 `9bfbd591fe0785bfa5d9eedaabf04d1620cc9d23fcf5b3b36539e68858456d46`; the baseline is commit `5706abf` and compiler `73005d231e1a6e3c380dbe1a9440206198f7ac5eb887a32b784e2f9005586689`. The shared machine is an AMD Ryzen 7 3800X. Goose upstream is `2e2bedef5b980bf013cac5aaa0095bfea64e5569`; engines are Wasmtime 50.0.1 and Node 24.22.1 / V8 13.6.233.17-node.58. The native host uses the full static Wasmtime SDK; the Python bindings use different library bytes at the same version. Exact source, compiler, artifact and environment identities are in the reports and manifest.

The delivery window ran from November 2 23:49 UTC to November 3 00:12 UTC. The folder retains the campaign start date. Nine fresh paired warmed rounds cover all ten workloads on each engine; reference artifacts were built earlier and executed freshly in the Wasmtime blocks. The example cohort has 1,600 observations; the host cohort has 1,440 runtime observations and 200 preparations; the seven-port LangArena cohort has 315 observations. Builds, preparation and warmed execution have distinct timing boundaries.

| Evidence | Contents |
| --- | --- |
| [final-warmed.json](final-warmed.json), [final-v8.json](final-v8.json) | Paired baseline and delivered compiler samples, Wasmtime references and V8 controls |
| [examples.json](examples.json), [host.json](host.json), [cohort.json](cohort.json) | Fresh example, host and adapted LangArena measurements |
| [references.json](references.json), [compiler-identity.json](compiler-identity.json) | Frozen reference selections and compiler identities |
| [qualification.json](qualification.json), [differential.json](differential.json), [host-qualification.json](host-qualification.json) | Focused, differential and host qualification |
| [campaign.json](campaign.json), [archives.json.gz](archives.json.gz) | Experiment dispositions and retained experiment archive index |
| [verification.json](verification.json) | Evidence verification |

Nine-pair baseline/delivered warmed speedups for Life, Sorting, custom hash and Sudoku were 1.797×, 5.203×, 2.786× and 1.128× on Wasmtime, and 1.163×, 5.386×, 3.637× and 1.065× on V8. Wasmtime Quicksort, Merge and CRC were 0.985×, 0.973× and 0.981×; a separate 15-pair Wasmtime Fannkuch trial showed a 0.4% cost with outliers. These figures describe these workloads and this machine, not a performance ceiling.

The [campaign tracker](../../../../docs/FULL_PERFORMANCE_CAMPAIGN.md) records all 24 families and their rejected or proof-limited work. The [runtime targets](../../../../docs/RUNTIME_TARGETS.md) explain the fixed reference selections and adapter boundaries. The selected native CRC uses AVX2 across benchmark repetitions; that execution strategy does not quantify the whole native gap.

Older benchmark results copied inside frozen source snapshots are retained as hashed historical context. Their old claims are not requalified by this campaign; campaign reports and measured guest artifacts are checked by the package verifier.
