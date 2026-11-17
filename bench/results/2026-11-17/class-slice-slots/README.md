# Slice slot replay · 2026-11-17

A store through a reference to a slice carries its slot identity through class summaries. When replay reaches a whole slice variable, the checker finds that activation's binding and applies the usual depth and shrink checks. Field and element stores still update their containing storage.

On 4,355 sources with class frames forced at the first eligible call, 14 previously accepted programs now reject. Plain upstream `d92c4315` rejects each of them. The rest of that comparison had identical exit status, output and diagnostics. Of the remaining 19 accepts that differ from the default path, upstream rejects 18 and accepts `stdlib_regex`. A CLI regression crosses the normal threshold with 4,200 distinct roots and exercises a bad rebind, a valid rebind and a shrink after rebinding. [Forced comparison](runs/forced-class-comparison.json) · [CLI regression](../../../../tests/test_cli_outputs.py)

The bootstrap reached a C fixed point. Default conformance passed 10,689 of 10,793 rows and memory64 passed 4,765 of 4,773, each matching its recorded gaps. All 10,049 outputs match the previous compiler byte for byte. The first memory64 run selected the old local host and failed on its pointer signature. Both final conformance runs used the corrected runner, which defaults to the Python host for memory64. [Qualification](runs/qualification.json)

## Blot2

The check of `compiler-goose/src` at `6ad5fbb` still stops after the first discovery pass. Baseline `b629e34`, the candidate and the instrumented baseline report the same 38 diagnostics. The development builds used Clang 23.1.5 and eight C units. CPU and RSS are per-run observations, with shared host load during the baseline and trace. [Build and workload identities](runs/blot2-experiment.json) · [Before](runs/blot2-before.json) · [After](runs/blot2-after.json)

The trace reproduces 237 distinct calls that introduced a deferred depth inversion. Of those, 195 are in `check/check.goose`. One starting point is `importedBinding` at `check/check.goose:1643:520`, where the callee's summary names the same untyped storage class for a destination and a source. Follow that store back to the expression before changing copy representation. Dropping all same-class alternatives was already tried and accepted seven invalid programs. [Trace](runs/blot2-trace.txt) · [Instrumentation patch](runs/trace.patch) · [Prior experiments](../../2026-11-16/class-stores-per-pair/README.md)

## Remaining slice case

Plain upstream accepts a conditional slice merged [by the caller](controls/caller-merge.goose) and passed as one argument. It rejects [a conditional formed in the callee](controls/callee-merge.goose) when the arms carry roots at different depths. Our compilers accept both. Preserving each store source through mapping would let the checker distinguish the two. Testing every root of a mapped argument separately would reject the caller-side case.
