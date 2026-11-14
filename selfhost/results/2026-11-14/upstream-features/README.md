# Upstream features · 2026-11-14

This qualifies the sources of `e8fe077`, which add five upstream Goose features on top of the indexed checker (`eb0c15d`):

- Root struct storage, lowered for native C; direct Wasm refuses it with a diagnostic.
- `defer`.
- `const if`.
- The `.check_length`, `.range_index` and `.move_from` array members.
- Literal generic parameters.

They also add the newer standard library's runtime externs and let a function and a namespace share a name. The features' status against upstream HEAD is tracked in [FEATURES.md](../../../../docs/FEATURES.md).

Qualification results:

- **Bootstrap.** `scripts/bootstrap.py --verify` reached a fixed point: the next- and third-generation C are both `954c5cd0…`. It used Clang 23 and Goose `-O2`, without a profile, because the snapshot 61 profile matches the old C. The executable's SHA-256 is `b42e927c1f0fe1b1c8a78ca1782ed1ec0cd8837b1f43ca0035162361a949e6fd`. [Report](bootstrap.json)
- **Conformance.** 8,288 of 8,384 rows pass at levels 0 and 2. The 96 failures are exactly the [recorded gaps](../../../../tests/conformance/known-gaps.json): 6 invalid programs accepted, 88 runtime contracts refused during compilation, and 2 that compile but print wrong output. No other row failed, and no recorded gap passed. [Report](conformance.json.gz)
  - New rows cover root structs, `defer`, `const if`, array ranges, literal parameters, constant constructs, a function and namespace sharing a name, runtime externs and unknown referenced types.
- **Native runtime contracts.** 49 of 49 pass.
- **Upstream HEAD `855f103`, native `-O0`.** 667 of 803 positive tests pass, up from 585. 2,041 of 2,055 invalid programs are rejected. 84 tests started passing and none regressed.

## Known limits

- `upstream/typing/named_constant_literals` now compiles but prints `false` for `HUGE > B`, a `u64.max` constant compared with an `i64` one. Snapshot 61 prints the same once the test's literal-parameter call is removed. It remains a recorded gap.
- `slice_pool` is still refused: its externs take `node[>..]&` by value. `slot_pool` aborts report the standard library's line instead of the caller's.
