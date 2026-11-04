Run from the repository root, retaining the referenced earlier evidence directories:

```sh
python bench/results/2026-11-04/minimal-aot/reproduction/verify.py bench/results/2026-11-04/minimal-aot
python bench/results/2026-11-04/minimal-aot/reproduction/audit_results.py
```

Both commands use only the Python standard library, read retained data, and run no compiler or guest. They create no bytecode caches. The first checks the manifest, archive members and byte identities; the second checks result matrices, medians, paired ratios, confidence intervals, qualification scope and report links.

There are six new archives and 24 referenced physical archives selected from the prior publication's exact 25-file allowlist. Reuse imports selected byte objects, not old alias namespaces or unrelated report trees. All declared input edges are retained; there are zero identity-only omissions. The two nested raw-log archives retain 68,900 files.

The 9,573 compiler observations are verified prior evidence. The semantic audit additionally hashes 1,010 historical native oracle binaries through physical member metadata in eight already-referenced archives; these are not fresh native corpus executions. The current ten native example programs were freshly executed. Fresh checks comprise 11,484 full-host replays, 1,914 direct-only minimal-host replays and 78 unit checks. The interrupted all-backend minimal attempt contributes no passing runtime rows. The 61-round paired comparison and the broader 15-sample cohort remain separate.

[Byte verification](verification.json) · [Semantic verification](semantic-verification.json) · [Independent final audit](final-archive-audit.json). `SHA256.json` covers every public file except itself and is written last.
