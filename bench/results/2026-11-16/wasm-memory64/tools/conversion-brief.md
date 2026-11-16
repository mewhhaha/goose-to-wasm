# Brief: converting one stretch of selfhost/codegen.goose to 64-bit memory

`selfhost/codegen.goose` is the direct WebAssembly backend of a compiler written in Goose (a small systems
language; the file is the only documentation of its syntax you need). It emits raw Wasm bytes. Today it emits
wasm32 only. We are adding a second mode, 64-bit memory (`cg_wide == true`), behind a switch. The first 800
lines are converted already. You convert one stretch of the rest. Other agents convert the other stretches at
the same time, each in a private copy, so the rules below are what make the pieces fit.

## The two rules that cannot bend

1. **Narrow output must not change by one byte.** With `cg_wide == false` every code path must emit exactly
   the bytes it emits now. So convert only by replacing an emission with a helper that emits the identical
   bytes in narrow mode, or by `if cg_wide { new } else { the original, untouched }`. Never reorder, merge
   or drop an emission on the narrow path. Do not change the order in which locals are created
   (`cg_local`, `cg_save` number them) or frame space is taken (`cg_frame`) on the narrow path.
2. **Edit only inside your stretch** (first function to last function, given in your task), in your copy.
   If you need a new helper, define it immediately above your stretch's first function, with a name that
   starts with the prefix given in your task. Do not touch anything else, in any file.

## The emitter

- `wb_byte(out, b)` one byte (an opcode without immediates). `wb_u(out, n)` / `wb_s(out, n)` LEB128.
- `wb_op(out, opcode, n)` opcode with one unsigned immediate (0x20 local.get, 0x21 local.set, 0x22 local.tee,
  0x23 global.get, 0x24 global.set, 0x10 call, 0x0c br, 0x0d br_if, 0x3f memory.size, 0x40 memory.grow).
- `wb_i32(out, v)` i32.const, `wb_i64(out, v)` i64.const. `wb_mem(out, opcode, align, offset)` a load or store.
- `wb_copy(out)` memory.copy, `wb_fill(out)` memory.fill.
- `f.code` is the body being written. `cg_local(f, type)` makes a local and returns its index;
  `cg_save(f, type)` makes one and pops the stack into it; `cg_get(f, local)`, `cg_set(f, local)`.
- `cg_begin(f, 0x02 block | 0x03 loop | 0x04 if, blocktype)`, `cg_end(f)`; blocktype 0x40 is empty, otherwise a
  value type. Value types: 0x7f i32, 0x7e i64, 0x7d f32, 0x7c f64, 0x7b v128.
- i32 opcodes you will meet: 0x45 eqz, 0x46 eq, 0x47 ne, 0x48 lt_s, 0x49 lt_u, 0x4a gt_s, 0x4b gt_u, 0x4c le_s,
  0x4d le_u, 0x4e ge_s, 0x4f ge_u, 0x67 clz, 0x68 ctz, 0x6a add, 0x6b sub, 0x6c mul, 0x6d div_s, 0x6e div_u,
  0x6f rem_s, 0x70 rem_u, 0x71 and, 0x72 or, 0x73 xor, 0x74 shl, 0x75 shr_s, 0x76 shr_u. The i64 ones are
  0x50 eqz, 0x51..0x5a comparisons, 0x7c add, 0x7d sub, 0x7e mul, 0x80 div_u, 0x83 and, 0x84 or, 0x86 shl,
  0x88 shr_u. 0xa7 i32.wrap_i64, 0xac i64.extend_i32_s, 0xad i64.extend_i32_u. Loads: 0x28 i32, 0x29 i64,
  0x2d i32 8_u, 0x2f i32 16_u, 0x31 i64 8_u, 0x33 i64 16_u, 0x35 i64 32_u. Stores: 0x36 i32, 0x37 i64, 0x3a i32 8,
  0x3b i32 16, 0x3c i64 8, 0x3d i64 16, 0x3e i64 32. 0x1a drop, 0x1b select.

## What 64-bit memory changes in Wasm

The address operand of every load and store, the operand and result of memory.grow, the result of
memory.size, and all three operands of memory.copy (destination, source, count) are i64; memory.fill takes
(i64 destination, i32 value, i64 count). Offsets in load/store immediates are unchanged. Comparison results
and conditions are still i32.

## The helpers (read lines 201-262 of the file first, then the converted functions `cg_load_fixed`,
## `cg_store`, `cg_convert`, `cg_pack_view`, `cg_field_place`, `cg_address`, `cg_copy` as worked examples)

- `wa()` value type of an address (0x7f narrow, 0x7e wide). `ws()` value type of a slice (0x7e narrow, 0x7b wide).
- `wa_const(out, v)` address-sized constant. `wa_op(out, i32_opcode)` the i32 instruction on addresses (emits
  the i64 one of the same name in wide mode; covers 0x45..0x4f and 0x67..0x78). `wa_add(out, offset)` adds a
  constant, nothing when it is 0 (use it only where the original also emitted nothing for 0; otherwise write
  `wa_const` + `wa_op(out, 0x6a)`).
- `wa_load(out, offset)` / `wa_store(out, offset)` load and store an address-sized word.
- `wa_bytes()` 4 or 8. `ww(k)` = k address-sized words in bytes.
- `wc_load(out, word)` / `wc_store(out, word)` word k of a growable array's control. `wc_bytes()` its size.
- `wa_wrap(out)` i64 to address (0xa7 narrow, nothing wide). `wa_extend(out)` address to i64, unsigned (0xad
  narrow, nothing wide). `wa_extend_s(out)` the signed one (0xac). `wa_from_i32(out)` a true i32 to
  address-sized (nothing narrow, 0xad wide). `wa_to_i32(out)` the reverse (nothing narrow, 0xa7 wide).
- `wa_truth(out)` an address as an i32 condition (nothing narrow; `i64.eqz; i32.eqz` wide). Needed wherever
  an address or address-sized number is the operand of `if`, `br_if`, `select`'s condition, or i32.eqz/and/or
  logic. For "is zero" use `wa_op(out, 0x45)`.
- `ws_ptr(out)` slice to its pointer as an address. `ws_count(out)` slice to its count as an i64.
  `ws_len(out)` slice to its count address-sized. `ws_load(out, offset)` / `ws_store(out, offset)` a slice in
  memory. `ws_pack(f)` makes a slice from (pointer as i64, count as i64) on the stack; the pointer gets
  `wa_extend` first.

## Types on the Wasm stack and in locals

A value that narrow mode holds as an i32 is one of two kinds, and you must decide which for every local,
constant and operation:

- **Address-sized** (`wa()`, i64 in wide mode): pointers, references, the frame pointer, cursors, limits,
  bases, anything loaded from a control or another word structure, **and every byte count, element count,
  length, capacity, index, size and offset that takes part in address arithmetic or comes from one**. This
  includes a limited array's inline length: `cg_length_load` leaves an address-sized count and
  `cg_length_store` takes one. `cg_owner_read_length`, `cg_owner_read_base`, `cg_owner_read_capacity`,
  `cg_array_length`, `cg_array_pointer` leave address-sized values. A function that returns "a local
  holding an address or a count" returns a `wa()` local; a function that takes one expects a `wa()` local.
- **True i32** (stays 0x7f): Goose `bool` and integer values of 32 bits or fewer (what `cg_wasm_type` gives
  0x7f for), conditions and comparison results, enum tags held as Goose values, the region index
  (global 3) and the region count (global 8), source line numbers, function numbers and table indices,
  the i32 length and line arguments of the host calls `write(pointer, length i32)` (CG_WRITE) and
  `abort(pointer, length i32, line i32)`, a byte value for memory.fill.

Goose `i64` values are i64 in both modes. Where narrow mode wraps a Goose integer to an address or count
(0xa7) use `wa_wrap`; where it extends an address or count to a Goose i64 (0xad / 0xac) use `wa_extend` /
`wa_extend_s`. Where an address-sized number meets a true i32 (multiply a count by an i32 tag, pass a length
to `write`), convert with `wa_from_i32` / `wa_to_i32` at the meeting point; these emit nothing in narrow mode.
An i64 that narrow mode compares or adds as i64 after extending stays as it is.

Take care with `if`/`block` results: `cg_begin(f, 0x04, 0x7f)` that yields an address is `cg_begin(f, 0x04, wa())`.
Take care with `wb_i32(f.code, 0)` used as a null address or zero count: `wa_const`.

## Globals (wide types)

0 stack top, 1 arena cursor, 2 the effect record of a nonlocal return in flight (0 = none), 4 effect chain,
5 forward mark, 6 region base, 7 bytes per region, 9 cursor table address, 10 stack limit, 11 publication
mark, and the pool global: all addresses, i64 in wide mode. 3 region index and 8 region count: i32 in both.
`m.stack_limit`, `m.stack_base` and data addresses (`cg_data`) are addresses: `wa_const`.

## Memory layouts

- Goose values keep the checker's layout: use `cg_size(p, id)`, `p.types[id].size/.align`, field offsets from
  the program. In wide mode a reference is 8 bytes, a slice 16 (pointer at +0, count at +8, one v128), a
  growable array's control 48 (the checker will say so; never write 24, 4 or 8 for these: `wc_bytes()`,
  `ww(1)`, `2 * ww(1)`). Integers, floats, bools, enums' tags keep their sizes.
- **Word structures**: anything the backend lays out itself as 4-byte words in narrow mode (a control's six
  words; an effect record: word 0 the previous chain, word 1 the function number, the result mailbox from
  byte 16 on, unchanged; effect metadata, three words per result, so the stride `12` is `ww(3)`; capture
  environments; the region cursor table; anchors and headers; publication records; whatever else you find)
  keeps its word order, and **every word becomes address-sized, also words that hold a small number such
  as a mode or a function number**: word k at `ww(k)`, loaded with `wa_load`, stored with `wa_store`,
  address-sized on the stack (`wa_from_i32` before storing a true i32, `wa_to_i32` after loading one, or
  compare it address-sized with `wa_const`). This rule is what lets a writer in one stretch and a reader in
  another agree without talking. If a structure mixes words with 8-byte Goose values at fixed byte offsets
  that would overlap in wide mode, or you find a layout where this rule cannot work, do what is right
  locally and put it in your report.
- A shift or multiply by the word size (`<< 2`, `* 4`) follows `wa_bytes()`.

## Slices and function values

A slice is one Wasm value in both modes (i64 narrow, v128 wide). Never take it apart with shifts or wraps:
use `ws_ptr`, `ws_count`, `ws_len`, `ws_pack`, `ws_load`, `ws_store`, and `ws()` for its locals and block
types. A zero slice is `cg_zero` (already converted). v128 cannot be compared with i64 opcodes: compare
pointer and count separately if narrow mode compared the packed i64 (branch on `cg_wide`).
Function values (`TY_FN`, closures) stay an i64 in both modes for now; if your stretch packs an address
into one (function index and environment pointer), leave it as it is and name the function in your report.

## What may stay narrow-only

If a function in your stretch is clearly only for a mode that stores 32-bit quantities in a packed format
of its own (the resolver mode `m.resolver >= 0`, scalar mode `m.scalar`, pools), and converting it means
redesigning the format, leave it and list it in your report. Everything else gets converted, including
enum and record images, as far as the rules above decide it.

## Working method

- Your copy is a directory with `selfhost/`, `stdlib`, `native`. Edit `selfhost/codegen.goose` there with
  exact-string edits. Read your whole stretch before editing; convert every function in it.
- After a batch of edits, check that it still compiles (8 seconds):
  `cd <your copy> && /home/user/goose-to-wasm/build/q-wasm1/bootstrap/bin/goose selfhost/main.goose --stdlib stdlib --check; echo rc=$?`
  Do not build the compiler and do not run anything heavier than this check: the machine is shared.
- When done, write the diff:
  `diff -u /tmp/claude-0/-home-user-goose-to-wasm/a6dda763-d5dc-55cc-a0f1-f5996d88c7d7/scratchpad/m64/base/selfhost/codegen.goose <your copy>/selfhost/codegen.goose > <your copy>.diff`
  and make sure every hunk is inside your stretch.
- Do not use git, do not touch /home/user/goose-to-wasm itself, do not install anything.

## Your report (short, facts only)

1. The diff path and that the check passes.
2. Every assumption you made about a function **outside** your stretch (what it leaves on the stack, the
   type of a local it takes or returns) that the rules above did not already fix.
3. Every structure layout you changed whose other readers or writers may be outside your stretch, with its
   wide layout.
4. Functions or code paths left narrow-only, and why.
5. Any place where you were unsure which of the two i32 kinds a value is, with the line and your choice.
