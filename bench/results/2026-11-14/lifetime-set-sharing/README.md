# Lifetime set sharing · 2026-11-14

Commit `37d9f56` changes how the lifetime analysis builds and stores alternative sets. Accumulations no longer copy their result at every join. Sets with equal lists share one list, and large sets are searched through a hashed root index. The analysis state is the same as before, and so is every output. Both compilers were built the same way: f3b4248's compiler emitted C at `-O2`, then Clang 23 compiled it with `-O2`, without a PGO profile. The baseline is `f3b4248`. [Metadata](metadata.json) · [Raw runs](timings.txt)

| Workload | Baseline user CPU | Candidate user CPU | Ratio | Max RSS |
|---|---|---|---|---|
| Compiler checks itself (32 sources, 1,359 reached functions) | 23.5 s | 23.1 s | 0.98 | 471 → 447 MiB |
| [blot2 compiler fixture](../../../fixtures/compiler-goose/manifest.json) (450 sources, 27,922 reached functions) | 14.5 s | 14.1 s | 0.97 | 2,935 → 2,865 MiB |
| The fixture with a main | stops after 100.6 s (pass 1, ~1,650 frames) | stops after 996 s (pass 1, 31,000 frames) | — | 4,842 → 8,655 MiB |

Each value is the median of three interleaved runs in fresh processes. The machine was shared, at load averages of 8–14 (the runs with a main ran one at a time, at about 12 and 17), so the ratios are what matter. The self-check reads a frozen copy of the candidate sources. The fixture is [blot2's compiler](../../../fixtures/compiler-goose/manifest.json) as checked on 2026-11-13. The fixture with a main is that fixture with `fn ::main() -> i32 { return blot_main::mainEntry(); }` added to `main.goose`. All three run with `--target native --check`, and the fixture rows add `--reachable-program --expansion-node-limit 1000000`.

## blot2 with a main

Discovery pass 1 visits a frame for each analyzed call context. The baseline ran out of the 2 GiB alternative region after about 1,650 frames. The candidate visits about 19 times as many frames and then fills the set region. The counts come from a build with progress counters (`instrument.py progress`, below). Every build here has the same analysis state, so the counts apply to the measured candidate as well.

| Frames | Baseline sets / alternatives | Candidate set IDs | Candidate sets / alternatives / atoms |
|---|---|---|---|
| 1,646 | 111,740 / 42.0 M (region full) | | |
| 3,000 | | 24.2 M | 0.68 M / 0.92 M / 0.32 M |
| 10,000 | | 121.6 M | 2.33 M / 2.99 M / 0.63 M |
| 20,000 | | 592.9 M | 8.50 M / 6.61 M / 1.55 M |
| 25,000 | | 951.4 M | 12.9 M / 8.62 M / 2.19 M |
| 31,000 | | 1,395 M | 38.0 M / 38.5 M / 23.7 M (set region full) |

"Set IDs" counts every set the old code would have made (the vids). The candidate keeps only the sets that outlive their build, and sets with equal lists share their alternatives.

## Equivalence

- `tests/output_equivalence.py` compared baseline and candidate on 7,621 compilations, and all were identical. The baseline was the bootstrapped compiler of `f3b4248`. The runs were `--check` for every conformance source, native `-O0` and `-O2` and direct Wasm `-O2` for each corpus source, and `--check` and native `-O0` and `-O2` for a frozen copy of the candidate sources. Each compared exit status, stdout, stderr and emitted bytes.
- The fixture's `--check` output is byte-identical: exit 0, no output.
- The analysis state is identical. [`instrument.py`](instrument.py) adds a fingerprint to a copy of `checker_lifetimes.goose`. At the start of each discovery pass, after discovery and after validation, it hashes every set reachable from roots, cells, frames, effects, summaries, atoms, items, exits and the offer memo, by ID with its ordered alternatives, together with the table sizes and counters. Baseline and candidate builds printed the same fingerprints on the self-check (7 per run), on the fixture, and with [`fpcompare.py`](fpcompare.py) on all 3,748 conformance sources (2,539 reach the pass, 9,532 fingerprints).
- `scripts/bootstrap.py --verify` reached a fixed point (generated C `0009adb4…`).
- Conformance at levels 0 and 2: 8,288 of 8,384 rows pass, and the 96 failures are exactly the open gaps: none unexpected, none fixed.

## What changed

- **Accumulations.** Read-backs, contents, bounds and similar walks build a set with `out = life_join(out, x)` once per alternative. A join that adds something copies `out`, so an n-root result cost about n²/2 alternatives. A `LifeBuild` replays exactly those joins in a hashed deque, because a join that adds lists the incoming new roots, last first, before `out` reversed. It makes only the last set.
- **Set IDs.** Every join that would make a set still takes the next ID, kept as `LifeSet.vid`. The offer memo hashes vids, so its slots and collisions are the baseline's. Every other use of a set ID is an equality test, and set IDs and vids map one to one.
- **Shared lists.** Sets never change after they are made, so a new set whose ordered list equals an earlier one shares it. That covers builds and small joins. Two sets on one list are equal, which `life_equal`, `life_subset` and the summary merge use. Lists of 16 or more alternatives get a hashed root index when they are made.
- **Read-backs.** The candidate set is read straight from its build and never made. `life_single` finds atoms through a table keyed by the whole alternative, instead of walking the root's chain: a popular global had thousands of atoms, one per reading place.
- **Live cells.** Live cells are a two-level bitset. The candidate scan, shrink checks and loop snapshots visit live cells only, in index order, and read dense per-cell keys.
- **Per-node spans.** There is one global read span per node, and each now has its own 16-byte struct instead of borrowing `LifeSet`.

## Limits

- blot2 with a main still does not finish. Each place that reads back through a non-exact reference makes one atom per candidate global, because the atom records the reading place as `from`. Atoms grew from 2.2 M to 23.7 M between frames 25,000 and 30,000. Read-backs, with one atom lookup per candidate, and the summary merges' subset tests lead the profile.
- Memory: checking the fixture with a main peaked at 8,655 MiB. The atom table alone is 1.6 GB by then (67 M 24-byte slots). Other runs that reached the same state peaked at 6.2–8.0 GiB, depending on the machine's memory pressure. The self-check and the fixture without a main use less memory than before.
- The candidate's sets are larger (56 bytes instead of 32), and an atom table and root indexes come on top. This costs little on the self-check because far fewer sets are kept.
