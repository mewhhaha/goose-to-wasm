# Bootstrap construction timing

Freeze the compiler inputs at `9551a58`. Baseline and candidate use the same Clang and pinned seed profile, with normal single-unit release builds. The timing comparison starts with both native executables in the existing content cache, then primes the candidate's new emission cache once. The candidate and baseline timed commands are the same apart from the bootstrap script. Run the six trials sequentially on logical CPU 2, alternating which goes first across pairs. Every invocation runs the just-built release compiler's C fixed-point verification.

```sh
source build/performance-env.sh
mkdir -p build/construction-speed/frozen
git archive 9551a58 -- bootstrap native stdlib selfhost | tar x -C build/construction-speed/frozen
git show 9551a58:selfhost/bootstrap.py > build/construction-speed/bootstrap-before.py
cp selfhost/bootstrap.py build/construction-speed/bootstrap-final.py
```

Use these arguments with the revision-specific script. Prime the native executable cache with one baseline run and the seed C cache with one candidate run before measuring. Use fresh output directories each time.

```sh
taskset -c 2 .venv/bin/python build/construction-speed/bootstrap-final.py   --source-dir build/construction-speed/frozen/selfhost   --stdlib build/construction-speed/frozen/stdlib   --native-dir build/construction-speed/frozen/native   --seed-dir build/construction-speed/frozen/bootstrap   --verify --cc clang   --cache-dir build/construction-speed/final-cache   --output-dir build/construction-speed/final-1
```

The raw timings use a monotonic clock around each child process invocation and `getrusage(RUSAGE_CHILDREN)` for user and system CPU time. The report records the active compiler and all command timings. The native cache recipe and seed-generated C keys must hit in the candidate timed runs. Require the `verify-selfhost` command to run on both sides and the exact generated, verified and executable hashes to match.

The separate cold seed-leg probe starts both arms with only the final executable cache entry. Its candidate script changes `args.jobs` to 3 around just the seed's `build()` call and restores the original value before self-compilation. The fresh monolithic control builds the seed with the shipped profile. Both arms use physical cores 0, 1 and 3 and verify the same cached release executable. This measures the seed-build decision in isolation, with final C compilation excluded.
