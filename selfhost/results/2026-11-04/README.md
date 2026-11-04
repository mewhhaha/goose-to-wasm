# Verification evidence: 2026-11-04

The final candidate contains 11 Goose files (9,292 lines). `summary.json` records the results and identities; `SHA256.json` inventories the evidence. `evidence.tar.gz` contains the working evidence, seed, pinned oracle and host under `work/` and `tools/`.

| Sweep | Result |
| --- | --- |
| Basic, O0/O2 | 18/18 valid runtime matches; one invalid fixture refused at both levels; 4/18 byte-exact Wasm outputs (empty and arithmetic at both levels) |
| Ten examples, O0/O2 | 20/20 runtime, golden and diagnostic matches; 0/20 byte-exact, so the default strict gate fails |
| Differential corpus, O0 | 950 rows; 409 full behavior passes, 372 candidate refusals and 165 runtime differences. All 950 were accepted by the oracle; 578 by the candidate. Four additional rows matched runtime and golden output but failed diagnostic wording. No timeouts. 28 cases were excluded by their declared levels. |
| Native, O0/O2 | 84/88 matching exit status and stdout, including two expected overflows; four explicit unsupported debug refusals are not parity |
| Float focus | 6/6 valid rows match on the final candidate |

The candidate parses its own full source. Its native-target self-typecheck completes with 16 diagnostics, so self-hosting remains unverified. The next work is return inference, constness and root tracking. Grammar and 1,055 numeric literal checks are separately pinned earlier-build references, not final-candidate reruns.

The archive includes candidate binaries, generated C, Wasm, command logs and available source snapshots. Early failed writing checks have logs but no complete pre-fix source snapshots. System libraries and toolchains are identified rather than bundled. Original absolute paths remain in the logs.
