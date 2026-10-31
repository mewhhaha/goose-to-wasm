# Fixed nonlocal return qualification

Implementation: `b7f1d47`.
Release compiler SHA-256: `df0f88eedd0005b318fddd60279ee0faff7f9f0e54e5271396bd6d38e61d1932`.
Debug compiler SHA-256: `c8e14f2a7f2fabb9f778132350ff8beebe647a57fd6b1bb01d77f549f15baba7`.
Prepared headers matched the implementation before subsequent landing work.

- Full Release differential suite **3343/3343 observations**, native/C-Wasm/direct,
  O0/O2, V8 and Wasmtime, including three compile refusals.
- New Debug nonlocal matrix **140/140**, plus full original callback program
  **20/20** at O0/O2, normal/debug frontend modes.
- Debug full direct suite **1339/1339**.
- Resources **68/68**, sessions **11/11**, callback boundaries **3/3**,
  enum boundaries **6/6**, standalone-variant/owned-struct/dynamic boundaries
  **4/4 each**, on both builds.
- Release backend extensions **100/100**, scalar-cache checks **13/13** and
  static-data checks **4/4**.

Per-activation mailboxes preserve innermost concrete target identity through
recursive and dispatched calls. Fixed aggregates snapshot before later mutations;
normal call publication is bypassed on propagation. Owner tables span frames and
recognize dying parameters, local owners and embedded enum headers. Surviving
global headers still fail their extent check before touching the neighbor.

Repeated interruption tests run under small memory limits on both engines.
Retained anonymous arguments survive early inline returns with logical cleanup
depths; construction cleanup preserves their later clear actions. Print scratch,
owned callback parameters, mixed fixed contracts and recursive target restoration
are covered. Three upstream programs are unchanged; the generic fixture excludes
only its final owned invocation block. The full original callback program now
qualifies at O0 as well as O2.

Astra reviewed target discovery, mailbox/global layouts, Wasm control flow,
cross-frame header recognition and cleanup positioning. Owned target results
remain an explicit staging/landing boundary in this implementation. See
[NONLOCAL_RETURNS.md](../NONLOCAL_RETURNS.md).

Reports/logs: `build/nonlocal-release-*`, `build/nonlocal-debug-qualified`,
`build/nonlocal-debug-original-fv-qualified`, `build/nonlocal-debug-direct-qualified`
and `build/nonlocal-debug-{resources,sessions,*boundaries}.log`.
