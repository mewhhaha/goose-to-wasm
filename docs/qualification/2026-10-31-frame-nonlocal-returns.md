# Frame-valued nonlocal return qualification

Implementation: `d9a0ae2`.
Release compiler SHA-256: `bf44a865cdd0a8d03fa0c75206976db27c6b7f75d744015b503d40e32e6c0850`.
Debug compiler SHA-256: `4068d824eb16ae1e4b2fbee497e4e5a1f5d78e7c251b3910ac99b851b5fb0f10`.
Both prepared header trees matched the implementation byte for byte.

- Full Release matrix **4123/4123**: native/C-Wasm/direct, O0/O2,
  V8 and Wasmtime, including three compile refusals.
- Debug focused frame matrix **180/180**, full direct suite **1651/1651**.
- Resources **73/73**, compiler sessions **11/11**, capture boundaries **4/4**,
  enum boundaries **6/6**, variant/owned-struct/dynamic boundaries **4/4 each**,
  on both builds.
- Release extensions **100/100**, scalar-cache checks **13/13**, static-data
  checks **4/4**.

One frame target may nest fixed prefixes to a fixed-element Grow/GrowShrink tail.
Its private control snapshot shares the target's region. The catch moves the
entire suffix to the target-entry cursor, then publishes the prefix and length
and adjusts tail base by its offset within that suffix. Bounds validate the
winning length relative to its base. Resource limit remains with the receiver.

Tests cover literal and closed ordinary forwarding, an earlier argument push,
recursive sources, nested prefixes with ordered scalar effects, selected-case
propagation, canceled partial frames and grow/shrink mutation after landing.
Named-frame returns restore saved base as well as length, preserving the original
view after canceled in-flight construction. Repeated low-memory tests keep the
same receiving region, preserve a neighboring canary and discard an abandoned
oversized tail when a replacement return wins.

Source admission remains conservative. Variable/capacity-limited, enum/non-frame
record and mixed/multiple owned targets remain separate extensions. See
[the frame landing contract](../NONLOCAL_RETURNS.md#frame-valued-target-landing).

Astra reviewed mailbox alignment, cursor/base arithmetic, publication and cleanup;
independent native/direct probes confirmed both optimization levels. The final
artifacts above exclude exploratory candidates.

Reports: `build/frame-release-qualified/report.json`,
`build/frame-debug-focused/report.json`, `build/frame-debug-direct/report.json`,
`build/frame-release-extensions/report.json` in the frame worktree.
Auxiliary logs: `/tmp/frame-{debug,release}-*.log`.
