# Large-program checking · 2026-11-13

Commit `eb0c15d` indexes the type checker's whole-program lookups and stops re-offering identical effects in the lifetime analysis. Both workloads produce identical output before and after. Both compilers were built the same way: the installed compiler emitted C at `-O2`, then Clang 23 compiled it with `-O2 -g -fno-omit-frame-pointer`, without a PGO profile. The baseline is `e6248ea` with the same driver. [Metadata](metadata.json) · [Raw runs](timings.txt)

| Workload | Baseline user CPU | Candidate user CPU | Ratio | Max RSS |
|---|---|---|---|---|
| Compiler checks itself (32 sources, 1,245 reached functions) | 65.3 s | 43.3 s | 0.66 | 321 → 416 MiB |
| [blot2 compiler fixture](../../../fixtures/compiler-goose/manifest.json) (450 sources, 27,920 reached functions) | 54.1 s | 23.0 s | 0.43 | 2,437 → 2,908 MiB |

Each value is the median of three interleaved runs in fresh processes. On the fixture the lifetime analysis fell from 2.19 s to 0.82 s; the rest is type checking. Other workloads were running on this shared machine, with load averages of 21–25, so absolute times are higher than in quiet runs and the ratios are what matter. In an earlier, quieter set (load about 8), the lifetime analysis alone took 36.0 s at baseline and 27.3 s with the first two changes.

## Equivalence

`tests/output_equivalence.py` compared baseline and candidate on 7,365 compilations, and all were identical:

- `--check` for every conformance source.
- Native `-O0` and `-O2` and direct Wasm `-O2` for each corpus source.
- `--check` and native `-O0` and `-O2` for the compiler's own sources.

For each it compared the exit status, stdout, stderr and the emitted bytes. The fixture's `--check` output was also byte-identical.

## What changed

The profile came from an `LD_PRELOAD` SIGPROF sampler on frame-pointer builds. `--wasm-stats` now lists `function_names`, so native `g_fnN` symbols can be read as Goose functions.

**Fixture, type checking.**
- Each scope hashed its names into 16 buckets, so the global scope's chains held about 2,000 symbols each. Scopes now share one growable table keyed by scope and full name hash.
- Overload choice alternates between the candidate and argument lists. `check_list_at` keeps two cursors instead of rewalking a list on each switch.
- Return roots and effects are found through per-function indexes instead of whole-program scans.
- Type property scans queue each type once.

**Self-compile, lifetime analysis.**
- Discovery reaches its fixed point in five passes. From the second pass on, each pass offers about 27 million effects, and 99.6% of them change nothing.
- Each summary entry now remembers the sets last merged into it, so a repeated merge returns immediately.
- An identical offer within the same frame activation is skipped.
- Read queries go through a hashed table, a per-function captured-read filter and per-function global read sets.

## Limits

- The extra indexes cost memory: +95 MiB on the self-compile and +471 MiB on the fixture.
- With `--reachable-program` and no `main`, the fixture's lifetime analysis has no program root, so it analyzes little of the program. Adding a `main` that calls the entry exhausts the data stack in the lifetime analysis. That case is under investigation and is not measured here.
- Native C compilation is outside these timings.
