# Regions and contracts · 2026-11-05

Snapshot 27 passes C-only self-hosting: its last two C generations are byte-identical. The parent seed was itself produced and verified from the previously published snapshot 23 C seed. The reproduction archive retains that intermediate seed, its source bundle and proof.

The complete independent suite passed 4,360/5,021 checks and failed 661. Shared checks gained 140 passes with no regressions against snapshot 26. All 32 recovered fixture checks passed. The curated Wasm corpus passed 1,944/1,944 checks each in Wasmtime and V8. This is incomplete compatibility; failures are retained without exceptions or skipped contracts.

The separate ordinary-region stress uses identical source, Goose O0, Clang O2 and five alternating fresh processes on CPU 7. Its 20,000 temporary arrays took a median 134.731 ms with the snapshot 26 compiler’s C output and 5.426 ms with snapshot 27. Median wait4 peak RSS was 324,492 and 22,848 KiB; that measurement includes process-launch setup. This workload is separate from the ten example benchmarks.

`summary.json` records identities, gains and failure groups. Compressed reports retain every compiler/run command and observation. `ordinary-regions.json` records the matched stress. `reproduction.tar.gz` includes its source, measurement script, emitted C, binaries and intermediate bootstrap seed. The checked-in `bootstrap/` contains the final C seed and source bundle.
