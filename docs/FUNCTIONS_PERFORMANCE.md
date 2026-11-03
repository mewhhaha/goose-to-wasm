# Functions performance

Eligible private aggregate parameters use the caller's existing value snapshot directly instead of copying it again on callee entry. The caller still snapshots each fixed value before evaluating the next argument. The optimization excludes dispatch, exports, captures, owners and reference exposure; other calls retain their existing path.

In Functions, `by_name` loses two static `memory.copy` instructions, its body shrinks from 776 to 735 bytes, and its frame from 64 to 16 bytes. The complete module shrinks from 39,363 to 39,322 bytes, with static copies falling from 256 to 254. These are static changes; they do not establish a process-time gain. The [earlier fresh-construction cohort](../bench/results/2026-11-03/fresh-construction/README.md) is a separate compiler comparison.

The prior compiler passed 73 focused gates, 9,573 differential executions and 11,484 host replays. [That cohort’s measurements and qualification](../bench/results/2026-11-03/runtime-stencil/README.md) cover the other runtime and compiler changes as well.
