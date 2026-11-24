# Blot2 class-keyed lifetime precision and scalability · 2026-11-24

This batch resolves the class-keyed lifetime checker precision and scalability gaps blocking frozen Blot2 (`cb1e9e15` and `6ad5fbb`), bringing both frozen snapshots down to a single shared diagnostic (`makeReflectionOrder(self_.reflections)` — a sound §5.2 rejection where plain upstream C++ Goose `d5ae5bb` contains a confirmed Use-After-Free bug) while improving `forced0` conformance with zero regressions and cutting own-source `--check` wall time by **20.1%**.

## Environment and pinned inputs

- **Host:** `Linux cachyos-x8664 7.3.5-2-cachyos #1 SMP PREEMPT_DYNAMIC Fri, 20 Nov 2026 07:37:39 +0000 x86_64`
- **C compiler:** `clang version 23.1.5`
- **Baseline commit:** `92125b6be82d0b24b6b1a2517a21115e928569e9` (`build/dev/bin/goose`, 8-unit Clang `-O2`, SHA-256 `8aae291fc80d2cb0…`)
- **Language reference:** plain upstream C++ Goose (`build/native/goose`, `d5ae5bb`, SHA-256 `2bb184c84bc540b3…`; sources checked read-only under `build/upstream-d5ae5bb-src/`)
- **Frozen workloads (archived read-only from `../blot2`):**
  - Blot2 `cb1e9e156d73c87c873f15888cd4fb6d2a399576` (`compiler-goose/src`, tree SHA-256 `b0170a694961e558…`) with Blot's selected stdlib (`build/blot-stdlib`, tree SHA-256 `8dfee0f374dc020f…`)
  - Blot2 `6ad5fbbd921d8c272667b5955085f479a99f5834` (`compiler-goose/src`, tree SHA-256 `424c26aed9779da6…`) with repo `stdlib` (tree SHA-256 `3cab3c50ced0eb01…`)
- **Threshold policy:** `LIFE_CONCRETE_FRAMES = 4096` is kept unchanged until remaining forced-class upstream disagreements are resolved.

## Qualification gate

Command:

```sh
build/native/goose check selfhost/main.goose --stdlib stdlib < /dev/null
.venv/bin/python scripts/qualify.py --output-dir build/qualify-blot2-lifetimes --jobs 8 < /dev/null
```

| Stage | Outcome | Seconds | Notes |
|---|---:|---:|---|
| Plain upstream check (`build/native/goose`) | exit 0 | — | Own compiler source checks cleanly |
| `bootstrap` (`--verify`) | exit 0 | 149.8 | Fixed point `true`; generated C `0ed55897…`, executable `7a08e2ee…` |
| `conformance` (default, GCC) | exit 0 | 437.5 | `10,697/10,801` passed (`104` recorded gaps, `0` unexpected) |
| `conformance-memory64` (Wasm direct) | exit 0 | 161.0 | `4,771/4,779` passed (`8` recorded gaps, `0` unexpected) |
| `native-checks` | exit 0 | 10.9 | `54` steps ok |
| `unit-tests` | exit 0 | 54.9 | All passed, including 11 new positive/negative `ClassLifetimeChecks` cases |

## Forced-class (`LIFE_CONCRETE_FRAMES = 0`) audit

Measured on separate source copies with `LIFE_CONCRETE_FRAMES = 0` (`tests/conformance.py --frontend-only --jobs 8`):

| Build | Conformance failures (10,801 rows) | New failures vs `HEAD` | Fixed vs `HEAD` | Upstream sentinel error tests | Custom negative controls |
|---|---:|---:|---:|---:|---:|
| `HEAD` (`92125b6`, `forced0`) | 78 | — | — | — | — |
| Candidate (`forced0`) | **75** | **0** | **3** | **13/13 rejected** | **6/6 rejected** |

Three previously failing upstream `forced0` conformance rows now pass:
1. `upstream/errors_tc/shrink_slice_ref_explicit_callee` (previously a `forced0` false accept; now soundly rejected)
2. `upstream/errors_tc/shrink_slice_ref_loaded` (previously a `forced0` false accept; now soundly rejected)
3. `upstream/lifetimes/growshrink_unrelated_refs` (previously a `forced0` false reject; now accepted)

All 13 upstream lifetime sentinel error tests (`store_class_view_reached`, `class_store_view_outlived`, `store_reached_alias`, `store_class_view_reached_call`, `cycle_read_through_two_pools`, `emptied_callee_call_between`, `emptied_callee_derived_store`, `store_reached_table`, `construct_use_bound_holder_ref`, `shrink_class_copy_kept_own`, `emptied_callee_shrink_first`, `cycle_holder_growshrink`, `byteview_holder_param_reuse`) reject under `forced0`, and `selfhost/main.goose` checks cleanly under `forced0`.

## Blot2 and own-source measurements (solo runs)

Commands:

```sh
# Blot2 cb1e9e15 (default 2 GiB --stack-reserve)
<compiler> --check --stdlib build/blot-stdlib --reachable-program --expansion-node-limit 1000000 \
  build/blot2-cb1e9e15/compiler-goose/src/main.goose < /dev/null

# Blot2 6ad5fbb (--stack-reserve 8G for candidate; default 2 GiB stops on 6ad5fbb's l.alts growth)
<compiler> --check --stdlib stdlib --reachable-program --expansion-node-limit 1000000 \
  build/blot2-6ad5fbb/compiler-goose/src/main.goose < /dev/null
```

| Workload | Compiler | Stack reserve | Diagnostics | Elapsed | Max RSS | Outcome |
|---|---|---:|---:|---:|---:|---|
| Blot2 `cb1e9e15` | `HEAD` (`92125b6`, 8-unit dev) | 2 GiB | 11 | 7.48 s | — | Stopped at discovery pass 1 (`package_core.goose` deferred store failures) |
| Blot2 `cb1e9e15` | Qualified release (`7a08e2ee…`) | 2 GiB | **1** | **73.50 s** | 5.21 GiB | Completed all discovery + validation passes; sole diagnostic is `check.goose:3422:86` |
| Blot2 `6ad5fbb` | `HEAD` (`92125b6`, 8-unit dev) | 2 GiB | 11 | 30.46 s | — | Stopped at discovery pass 1 (`package_core.goose` deferred store failures) |
| Blot2 `6ad5fbb` | Candidate (`exp-ae-8g`, 8-unit dev) | 8 GiB | **1** | **215.51 s** | 10.40 GiB | Completed all discovery + validation passes; sole diagnostic is `check.goose:3179:86` |
| Own source `--check` (5 alternating rounds) | `HEAD` (`92125b6`, 8-unit dev) | 2 GiB | 0 | 0.412 s median | — | `[0.413, 0.412, 0.404, 0.407, 0.413]` |
| Own source `--check` (5 alternating rounds) | Candidate (`exp-ae`, 8-unit dev) | 2 GiB | 0 | **0.329 s** median | — | `[0.331, 0.329, 0.329, 0.326, 0.324]` (**−20.1%** vs `HEAD-dev8`) |
| Own source `--check` (5 alternating rounds) | Qualified release (`7a08e2ee…`) | 2 GiB | 0 | **0.324 s** median | — | `[0.323, 0.324, 0.327, 0.330, 0.314]` |

Note: `6ad5fbb` still exceeds the default 2 GiB data-stack reservation for `l.alts` during full validation (`exp-ad` hit 2 GiB at 49.86 s); tightening `rlim` under `LIFE_TYPED_PRESSURE` to `64` or `32` did not fit `6ad5fbb` inside 2 GiB and regressed `cb1e9e15` precision (`3` diagnostics at `rlim=64`, `7` at `rlim=32`). `cb1e9e15` fits comfortably inside the default 2 GiB reserve.

## Summary of sound changes in `selfhost/checker_lifetimes.goose`

1. **Grow-shrink indirect reachability (`life_points_into`, `life_shrink_array`):** For `A_GROWSHRINK` (`slot_safe = true`), only `TY_REF` to `TY_SLICE` reaches grow-shrink element references indirectly; non-ref non-tuple holders cannot hold grow-shrink element references (matching upstream `typecheck_builtins.h:1240-1244, 2716-2717, 3020-3042`).
2. **Grow-only and slot-read propagation (`life_eval_access`, `life_coerce`, `N_FOR`, `alloc_slice`/`realloc_slice`):** Preserve `slotread` on `TY_SLICE` indexing/slicing and `N_MEMBER` struct field projection (`life_member_interior` clears only `target_type`), and mark `slotread = true` via `life_grow_only_interior` when indexing, slicing, coercing, iterating, or allocating `A_GROW` (`T[>..]`) arrays.
3. **Class queries (`life_class_answer`):** Skip `a.slotread` for `query == 1`, and for `query == 0` when `!a.byteview` and `!life_gs_contains(cty, subject, flag)`.
4. **Shrink filtering and replay (`life_shrink_places`, `life_replay`):** Filter shrink `receiver.place` by `receiver.type_id`; apply `life_reached_places` for `k = 1, 2, 8` before mapping in `life_replay`.
5. **Holder copy & slot container reads (`life_coerce`, `life_held`, `life_root_is_slot_container`):** Mark `out.contents` `slotread = true` when copying a holder through `TY_REF`; mark `life_held` `slotread = true` for exact slot containers (concrete non-ref or global, typed non-ref storage class, non-ref argument class, or level ≥ 1 storage class) and preserve `a.slotread || life_root_is_slot_container(...)` on inexact alternatives.
6. **Type-containment shrink overlap & mapping (`life_ref_overlaps_array`, `life_map_onto`):** Filter exact non-byteview reference alternatives by type containment against the shrunk array/element; narrow `want >= 0` in `life_map_onto`.
7. **Static data handling (`life_classify_set`, `life_fold_slow`, `life_add_contents`, `life_overlay`):** Static data (`root == 0`) does not clear `all_slots`, never accumulates stored mutable roots (`if root == 0 { return; }` in `life_add_contents`, matching upstream `RecordStore: if (!container) return;`), and never pulls `globals_root`/`class_stored` in `life_overlay`.
8. **Global capture snapshot caching (`life_class_call`, `life_function`):** Check `span.count == 0` before `capture_inputs != -2` and snapshot `capture_inputs` eagerly (`-1` when `span.count == 0`) on first validation.
9. **Through-reference kill precision (`life_kill_matches_root`, `life_replay`, `life_effect`):** When assigning through a reference (`through == true`), only emit a whole-root `kind == 6` kill if the root's storage type matches `ty` (preventing element writes like `slot = Slot {}` from killing sibling elements and eliminating the `2^N` `[6, 4]` effect cascade on `6ad5fbb`); normalize kept kill alternatives to plain `LifeAlt { root: kr }` and match superseded kind-7 kills by root ID.
10. **Temporary aggregates in recursive cycles (`life_store`):** Match upstream `FitsAt` (`!((binding || owner.temporary) && owner.frame == l.frame)`) so temporary struct-literal call arguments in recursive calls pass while `let` bindings and §5.2 grow-shrink stores remain rejected.
11. **Reusable pool shrink filtering (`life_shrink_array`):** Only `A_GROW` pools matching `pa.byteview || life_same(p, symbol.type_id, receiver.type_id)` count as reusable pool shrink targets (matching upstream `ShrinkTargets`).
12. **Readback slot semantics (`life_readback`):** Global ref/slice variables are global slots (`!global` keeps `slotread = true`, matching upstream `typecheck_flow.h:559-560`); level-0 ref/slice argument classes (`class_pointee >= 0 && life_is_ref(p, class_pointee)`) keep `r.slotread` (`false`) so `T[:]&` views into grow-shrink arrays cannot escape or survive a shrink while holder parameters (`class_pointee == -2`, such as `fn view(self_: Store)`) still preserve `slotread = true` on struct field reads.
13. **Construct read & own-store precision (`life_check_construct_read`, `life_own_effects`, `life_own_store`):** Preserve `cr_val.place = value.place` for `TY_SLICE`; emit `code = -6` for interior `slotread` references into a typed storage class (`x.target_type != class_type`), clearing `h.target_type = -1` while keeping `h.slotread`.
14. **Recursive back-edge unkeyed static-parameter taint (`life_class_remap`, `life_class_call`):** When a recursive back edge passes non-static roots to a parameter whose frame key had only static data, taint holder results with an inexact non-slotread temporary of the call (matching upstream `typecheck_calls.h:3587-3610`).
15. **Typed class budget under pressure (`life_class_typed`):** Separate `pod_typed_count` (throttled to `LIFE_TYPED_FEW = 8` past `LIFE_TYPED_PRESSURE`) from reference-holding `typed_count` (kept at `LIFE_TYPED_CLASSES = 256`).

## Sole remaining diagnostic on both Blot2 snapshots (`makeReflectionOrder`)

Both `cb1e9e15` (`check/check.goose:3422:86`) and `6ad5fbb` (`check/check.goose:3179:86`) stop on the exact same pattern:

```goose
struct Engine { reflections: Reflection[>..<]& }
struct ReflectionOrder { items: Reflection[:] }
fn makeReflectionOrder(items: Reflection[:]) -> ReflectionOrder { return ReflectionOrder { items }; }
fn finishReflection(self_: Engine&) -> Error {
    var context = makeReflectionOrder(self_.reflections);
    ...
}
```

- **Why our checker rejects it:** Storing a slice into a grow-shrink array (`Reflection[>..<]&`) inside a struct field (`ReflectionOrder.items`) violates §5.2.
- **Why plain upstream `d5ae5bb` accepts it:** In `build/upstream-d5ae5bb-src/src/typecheck_calls.h:1351,1530`, `self_.reflections` is loaded with `slotread = true` (`SlotReadable(Reflection[>..<]&)`). When implicitly converted from `TY_ARRAY&` to `TY_SLICE` at a call argument, `LoadSliceArgs` only handles `TY_SLICE& → TY_SLICE`, leaving `ra.slotread = true` on the callee's parameter class. Plain upstream `build/native/goose` rejects `ReflectionOrder { items: self_.reflections }`, rejects `makeReflectionOrder(self_.reflections[..])`, and rejects `makeReflectionOrder(arr)`, yet **accepts** a direct Use-After-Free through `makeReflectionOrder(self_.reflections)` followed by `self_.reflections.clear(); return ctx.items[0].x;`.
- **Policy:** Consistent with `block-result-views-parameter` in [docs/FEATURES.md](../../../../docs/FEATURES.md#L154), we keep rejecting this unsound pattern and cover it with a negative regression test in `tests/test_cli_outputs.py`.

## Rejected experiments (preserved)

All of the following hypotheses were tested during the campaign and rejected because they introduced unsound false accepts under `forced0`, broke upstream sentinel tests, or degraded Blot2 precision/scalability:

1. Dropping `!place_exact` in `life_add_contents` — broke soundness on indirect container writes.
2. Propagating `as_type = reached` onto `class_parent >= 0` storage classes — lost interior type precision on typed storage classes.
3. Making `pod_typed_count` completely unbounded — caused alternative-arena blowup under pressure without precision gain over `LIFE_TYPED_FEW = 8`.
4. Applying `life_referable` in `life_load` for `!is_ref && holds` — falsely accepted invalid stored references.
5. Lowering `LIFE_CLASS_DEPTH` from `2` to `1` — caused false diagnostics on two-hop class paths in Blot2.
6. Dropping exact same-arg storage classes in `life_unpermuted` — lost alias distinctions between distinct call sites.
7. Replacing inexact mutable globals with `l.globals_root~` in `life_load` — collapsed global type filtering and regressed precision.
8. Filtering `life_class_stores` by depth or sibling-field heuristic — broke sound propagation across aliasing parameter classes.
9. Calling `life_reads_global` per global inside `life_shrink_array` — excessive runtime cost with no precision benefit over epoch tracking.
10. Eager `life_global_capture_span` snapshots on all class frames plus cumulative `out_contents = life_join` (`exp-m`) — broke validation convergence / over-invalidated summaries.
11. Skipping `root_struct_type` in `life_gs_contains` — falsely accepted grow-shrink element stores rooted in root-struct components.
12. Disabling `life_gs_value` for all holders — accepted invalid grow-shrink holder escapes.
13. Copying unnormalized `ka` (retaining `slotread`/`target_type`/`from`) into `kind == 6/7` replay places (`exp-z`) — broke `ke.places == effect.places` deduplication in `life_effect`.
14. Treating `class_pointee < 0` as `is_ref_slot` in `life_readback` (`exp-ac`/`exp-ad`) — falsely cleared `slotread` on holder parameters (`class_pointee == -2`), regressing `eval/type_evidence.goose:250:113` on Blot2 `6ad5fbb`.
15. Throttling reference-holding `rlim` under `LIFE_TYPED_PRESSURE` to `8`, `32`, or `64` (`exp-ad-rlim*`) — regressed `cb1e9e15` from `1` diagnostic to `6`/`7`/`3`, ran slower at `rlim=64` (`71.05 s` vs `65.67 s`), and still overflowed default 2 GiB on `6ad5fbb`.
