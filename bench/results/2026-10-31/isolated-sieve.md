# Isolated original Sieve kernel

The pinned LangArena `goose/src/sieve.goose` is copied byte for byte. It retains
its growable array. A replacement entrypoint supplies runtime parameters, and
an unused configuration stub avoids importing the whole benchmark driver.
This is separate from qualification of the original 50-task entrypoint.

| Profile | Limit | Measured iterations | Warmup iterations | Checksum |
| --- | ---: | ---: | ---: | ---: |
| Official small | 1,000 | 3 | 1 | 4,660 |
| Official production | 3,000,000 | 270 | 54 | 1,042,248,060 |

All **20 observations** pass: both profiles at O0/O2 on native C, C-Wasm on
V8/Wasmtime, and direct Wasm on V8/Wasmtime. The checksum includes warmups,
matching the original benchmark. No performance improvement is claimed.

Reproduce with `python bench/langarena.py fetch`, then
`python bench/qualify_sieve.py --profiles test run`. The adjacent JSON retains
compiler/kernel/engine pins, harness identities, commands and artifact hashes.
