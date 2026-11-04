# Direct imports in the minimal AOT host

The minimal AOT host binds imports directly and uses a numeric callback adapter. The full host retains its Linker; the compiler is unchanged. The minimal host continues to require trusted artifacts prepared for its matching profile.

## Measurements

On the shared AMD Ryzen 7 3800X, the primary CPU-pool comparison used 201 measured rounds, two warmups, five cells and two affinities (2,010 measured executions; 2,030 including warmups). The median paired final/previous-minimal ratio was **0.983831** (95% CI 0.978166–0.989110), a 1.6% reduction. The A/A ratio was 0.999349 (0.994714–1.002551). Final/native was 1.160369 (1.156479–1.167989), or 16.0% above native C. On CPU 2, final/previous was 0.986518 (0.980524–0.994035) and final/native was 1.213740 (1.206852–1.223422).

The 31-round screen across all ten examples found VM 3.4% slower on the pool (ratio CI 1.00004–1.09179). A bounded 201-round follow-up found VM 1.72% faster on the pool (ratio CI 0.977236–0.986360) and 1.61% faster on CPU 2 (0.979784–0.987642). Both results are retained.

The broad 15-sample example and host cohorts are separate from the paired rounds; their marginal medians reflect different host load and are not matched before/after results. Functions full AOT was 1.313 ms and minimal AOT was 1.480 ms in this cohort; these marginal medians do not demonstrate a minimal-versus-full speedup. The paired claim compares the previous and final minimal hosts only. LangArena and warmed target runs were collected separately with the same compiler. All ten direct Wasm example artifacts are byte-identical to the prior compiler output.

[Example samples](examples.json) · [Host samples and preparation](host.json) · [Lifecycle samples](lifecycle.json) · [Final Functions pairs](final-functions.json) · [All-ten screen](final-regression.json) · [VM follow-up](vm-confirmation.json)

## Qualification

The fresh qualification covered 91 unit test methods, 11,484 general-host runtime observations and 1,574 serialization preparations, plus 1,914 minimal-host direct runtime observations and 679 preparations. An earlier, separately collected compiler reference covered 9,573 observations across 978 cases, with 1,487 hash-verified inputs and 17 path aliases; it was not rerun for this batch.

Compiler SHA-256: `8c09c1a6bcc782de5b86dda621a91ae234acba8fbe108d146582113eb6a110b6`. Minimal host SHA-256: `51873433f6bf52b64462b21cc8e8fb5eecb85c3acdf87d9accbdccb58128f1bf`. Full host SHA-256: `93bc17c239c008d481ae6955f332d22472006700d27121d8986cac49d1553b50`.

## Rejected experiments

A leaf change reduced the module from 39,322 to 38,194 bytes, but its pool and CPU 2 paired confidence intervals crossed parity (ratios 0.99284 and 0.99752). A no-copy-on-write 1 MiB experiment regressed (pool ratio 1.6525, CPU 2 ratio 1.6157). Neither landed.

The complete example cohort had 1,600 observations before Btrfs ran out of space. The retained failed checkpoint and resumption verify the prior pins and report hash. Remaining host and lifecycle raw outputs and AOT preparation used RAM scratch. For the final pairs, the ten selected AOT artifacts were copied to regular Btrfs files so eviction and read normalization used the original filesystem; executables and native inputs also remained there. Compact logging retains 62,616 logical raw files in two archives.

## Remaining work

The minimal host still trails native C on Functions. The full host, other workloads, and compiler remain separate opportunities; this measurement is not a universal ceiling.

## Verify retained evidence

From the repository root, these checks read retained reports and archives without running guests or changing files:

```sh
python bench/results/2026-11-04/direct-imports/reproduction/verify.py bench/results/2026-11-04/direct-imports
python bench/results/2026-11-04/direct-imports/reproduction/audit_results.py bench/results/2026-11-04/direct-imports
```

The byte index retains source, toolchain, compiler, host, workload and guest identities, including rejected experiments. Exact historical objects are reused from the pinned immediate predecessor's physical archives; historical reference observations remain separately collected. The independent audit and final manifest record the checks and their limits.
