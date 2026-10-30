# Lexer transition reuse — 2026-10-30

Commit `43cad8f` adds optional reuse of unchanged files' lexer transitions.
This experiment compares native workers with and without that cache. Both
modes construct a fresh AST and run the complete parser, resolver, type
checker, optimizer, bounds analysis, and emitter.

Four successive runs used the same Release compiler, 32 generated functions,
O0, and 15 samples. Each edited request changes one function in the root
module; its imported `std` module stays unchanged. Other local validation
had finished. Every run verified the final edited program's output.

| Run, in execution order | Edited median (ms) | Edited MAD (ms) | Parse phase median (ms) |
| --- | ---: | ---: | ---: |
| Worker without token cache 1 | 15.522 | 1.821 | 2.044 |
| Worker with token cache 1 | 15.147 | 1.756 | 2.810 |
| Worker with token cache 2 | 16.488 | 1.889 | 2.911 |
| Worker without token cache 2 | 20.139 | 3.811 | 2.822 |

These measurements do **not establish a latency improvement** from token
caching. Shared-host scheduling noise remains visible in the raw samples;
the cache's lookups, state restoration, and recording of changed tokens also
cost time. The mode remains opt-in. This does not alter the earlier
[native process retention comparison](native-session.md).

Each cached edited request reused 10,292 token transitions from the unchanged
import and scanned 695 tokens in the edited module. It parsed both files,
reported zero parsed-module cache hits, and retained an estimated 1,944,292
cache bytes across two files. These counters demonstrate scanner reuse, not
reuse of parsed syntax or checked functions. A syntax importer is the next
step toward avoiding parsing unchanged modules.

The [records](lexical-cache.json) retain every timing sample, phase summaries,
edited-build counters, compiler/input hashes, and platform metadata. Repeated
per-function fingerprint arrays are omitted. The final compiler passed 583
differential observations, 99 backend checks, 11 session tests, 12 incremental
checks, 4 static-data tests, and all 194 portability cases. The portability
run's compiler hashes before and after were identical.

The lexer harness compares cold and warm token state and diagnostics, seeded
token combinations, backtracking, source rebasing, individual state guards,
and bounded-cache behavior under AddressSanitizer and UndefinedBehaviorSanitizer.
Local execution disabled leak detection because LeakSanitizer cannot run
under the environment's process tracing; CI retains the default leak check.

With the pinned Node and Python environment active, reproduce the timings in
worker–cached–cached–worker order:

```sh
python bench/incremental.py --samples 15 --functions 32 --native-worker \
  --output build/lexical-worker.json
python bench/incremental.py --samples 15 --functions 32 --native-worker \
  --lexical-cache --output build/lexical-cached.json
```
