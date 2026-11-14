# Abandoned destinations in native C · 2026-11-14

An exit that abandons part of a destination (§7.3 **Exits**) left its partial value in the destination in native C. After `return [11, stop()] from target`, `left` printed `[11, 2]`, where the spec, plain upstream and direct Wasm give `[1, 2]`. Native C now builds each growable-array, image and enum value of such an exit in a stage behind what the destination's region holds. Once the exit completes, it moves the stage into the destination. When a cancelled exit leaves an image stage, it moves the region's top back. A whole assignment from a literal or fill that an exit can leave is built in place (§4.4). Programs without such exits emit the same C. Later `push`, `pop` and `append` keep native's length-based semantics. Upstream's region-top leftovers (layer 2 in [FEATURES.md](../../../../docs/FEATURES.md#differences-found-by-the-upstream-differential-run)) are not emulated.

Contract: `corpus/contracts/upstream-differential/backends/abandoned-destination/{native,wasm-direct}`, levels 0 and 2. The expected output is from plain upstream `32a4f44` with `run`, which prints the same at `-O0`, `-O1` and `-O2`.

## Qualification

`scripts/qualify.py --baseline <qualified compiler of 6ea8540>` ran on the tree of commit `6605af3`, which is the delivered commit's tree (`91bcc130…`). [Summary](qualification.json)

- Bootstrap reached a fixed point: generated C `b78b8c8c…`, executable `da0aecd2…` without profile.
- Conformance passed 8,457 of 8,549 rows as one unit, and 4,806 of 4,898 native rows as three units. In both, exactly the 92 recorded gaps failed.
- 54 of 54 native checks passed, and the unit tests passed.
- Equivalence: 214 of 7,805 outputs differ, all native C. No Wasm output, `--check` result, exit code or stderr differs. [Classified](equivalence-classes.txt)
  - 210 contain the new stages; 98 of those also contain the rewind where a return is caught.
  - 4 are the in-place whole assignment (`varint_grow_assignment_cancel`, `dynamic_assignments`, at `-O0` and `-O2`).
  - The compiler's own C did not change, so the fixed point holds.

## Direct-Wasm-only fixtures

The 106 `nonlocal_*` and `varint_grow_*` fixtures have conformance rows only on direct Wasm. Each was run natively against its frozen expected output. [Results](wasm-only-fixtures.txt) The 10 that read `bench_input` used a native stand-in for the direct-Wasm host.

| Outcome | Fixtures |
| --- | ---: |
| Match | 51 |
| Differ only through layer 2 (upstream's region-top leftovers) | 44 |
| Differ through the open part of layer 1 (a cancelled whole assignment from a call) | 9 |
| Differ for reasons unrelated to exits | 2 |

At `42487ee`, before this change, 45 matched, 57 differed and 4 were refused natively.

## Still open

- **A cancelled whole assignment from a call** (`g = make() { … }`) keeps the old value, where upstream shows the length and frame fields the call published. Building it in place works at `-O0` for a plain growable array, but not at `-O2`, where the call is inlined, nor for `T[]` conversions or frame structs.
- **A break out of an inlined exit function inside an image construction** does not move the region's top back, so the image can keep a gap there.
- **Not staged:** an exit forwarding a single tuple-valued call (`return pair() from t`), self-relative runs, and growable arrays of `varint` elements.
