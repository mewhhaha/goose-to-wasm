# Reusing a verified local compiler · 2026-11-17

`python3 scripts/bootstrap.py --reuse-toolchain build/toolchain.json` uses the previous local compiler for the initial C emission. It checks the copied executable against the previous receipt, uses the standard C build recipe, and runs the new compiler to verify the C fixed point. The ordinary `--verify` invocation starts from the checked-in C seed.

Both starting points compiled the compiler sources at `90d4d19` with the `driver.goose` help text changed to `Goose-written compiler (iteration timing 1901)`. Both produced identical initial and next-generation C (`72942bf7e58f…`) and final executables (`4fe745f24fe6…`). The local starting point was the verified `94c6428f4d20…` release compiler. Its emission of unchanged `90d4d19` sources also matched the checked-in seed, with C hash `fc7fbbff3870…`.

With just the native executables cached, three interleaved pairs on CPU 0 took **36.19 → 8.42 s wall** and **35.16 → 8.26 s CPU** at the median. Every run emitted and verified fresh C for the edited sources. [Receipts](runs.json)

In a single prototype comparison with the checked-in seed's native executable already cached, a fresh release build and verification took 152.84 s from the checked-in seed and 124.18 s from the previous compiler. CPU time was 149.82 s and 122.86 s, respectively. These runs overlapped on distinct physical cores. The independently compiled release leg was approximately 115 s on both arms. [Receipts](runs.json)

The public installer independently rebuilt from the local toolchain in 122.42 s with an empty cache, then installed into that same toolchain directory. It recorded both the preceding receipt and executable checksums. The installed executable matched the canonical control and displayed the edited help text. [Receipt](runs.json)

## Reproduction

Use Clang 23.1.5 on x86-64 Linux and freeze the source and seed before timing. Set `trial` to a fresh absolute directory under `build`.

```sh
source build/performance-env.sh
trial="$PWD/build/repro-local-bootstrap"
mkdir -p "$trial/frozen"
git archive 90d4d19 -- bootstrap native stdlib selfhost | tar x -C "$trial/frozen"
cp -a "$trial/frozen/selfhost" "$trial/edited"
sed -i 's/Goose-written compiler (unverified rewrite)/Goose-written compiler (iteration timing 1901)/' "$trial/edited/driver.goose"

python scripts/bootstrap.py --verify --cc clang \
  --seed-dir "$trial/frozen/bootstrap" --stdlib "$trial/frozen/stdlib" \
  --native-dir "$trial/frozen/native" --source-dir "$trial/frozen/selfhost" \
  --build-dir "$trial/prior" --cache-dir "$trial/anchor-cache"
```

Compare `--verify` with `--reuse-toolchain "$trial/prior/toolchain.json"`, using the same `--seed-dir`, `--stdlib`, `--native-dir` and `--cc` arguments as above, `--source-dir "$trial/edited"`, and separate build and cache directories. Prime the checked-in native seed cache by copying the `build-seed` cache-key entry from `anchor-cache`. For a fresh release build, leave all other entries absent. To isolate changed-source emission, seed each cache with only the two native executable entries from the checked-in arm's completed cache. Alternate arm order across pairs on the same physical core. Check that `compile-goose` and `verify-selfhost` ran and both arms have the same `generated_c_sha256`, `next_generation_c_sha256` and `executable_sha256` in `bootstrap/report.json`.

## Cold seed experiments

Clang `-O1` built the checked-in intermediate seed in 89.64 s and emitted matching C in 38.36 s. The cached profiled seed emitted the same C in 33.61 s. Clang `-O0` built in 33.22 s and reached the native call stack limit with the default 8 MiB stack. The 64 MiB retry ran over 216 s without writing C and was stopped. GCC 16.2.1 `-O0` built in 161.03 s and reached the default stack limit. TinyCC 0.9.28rc failed to parse the seed's `__int128` declaration. [Receipts](runs.json)
