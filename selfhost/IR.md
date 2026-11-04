# Compiler contract

This is a Goose implementation, bootstrapped by the pinned C++ oracle in
`oracle.json`. The implementation must not invoke the oracle to compile user
programs. Verification may invoke both implementations independently.

The first writing pass covers the source-to-code pipeline together. Compilation,
oracle comparisons and self-compilation follow that pass. A written phase is not
evidence of language or output parity.

Tables in `model.goose` use stable integer IDs. Never retain a reference to a table
element across a push, recursive call or another mutation of that table. `Program`
borrows tables owned by the driver. `Type.kind` is a category (`TY_INT`), while
primitive IDs are `TYPE_I64` etc.; integer width is `Type.count` and signedness is
`TF_UNSIGNED`.

- `lex_source(p, source_id)` appends tokens and records source token bounds.
- `parse_source(p, source_id)` returns and stores an `N_MODULE` node.
- `check_program(p)` resolves declarations, specializes calls, assigns symbols and
  physical layouts, and sets `p.entry` to the checked main function node.
- `optimize_program(p)` transforms checked nodes according to `p.optimization`.
- `generate_wasm(p, out)` writes a standalone Wasm module into a byte builder.
- `generate_c(p, out)` writes native C source into a byte builder.

Lists use `first`/`last`/`next`. An AST node's `next` belongs to its parent list;
expression lowering must not accidentally evaluate it.

| Node | Payload |
| --- | --- |
| Module/namespace/block | `first`: declarations/statements |
| Function | `first`: parameters; `left`: result type list; `right`: body; `third`: generic parameters |
| Param/variable/field | `left`: type syntax; `right`: initializer; `token`: name |
| Struct/enum | `first`: fields/variants; `third`: generic parameters |
| Alias | `left`: underlying type syntax |
| Call | `left`: callee; `first`: argument list; `third`: trailing function-value block |
| Unary/cast/member | `left`: operand; `right`: cast type; member `token`: field name |
| Binary/assignment/index/range | `left`, `right`: operands; `integer`: operator token kind |
| Slice | `left`: array; `right`: start; `third`: end |
| If | `left`: condition; `right`: then; `third`: else |
| While | `left`: condition; `right`: body |
| For | `first`: bindings; `left`: iterable/range; `right`: body |
| Return | `first`: result expressions; `symbol`: target function when resolved |
| Match | `left`: scrutinee; `first`: arms |
| Arm | `left`: pattern; `right`: body; `third`: guard |
| Array/record | `first`: elements/field bindings; array `right`: repeat count; record `left`: type |
| Binding | `token`: field name; `right`: field initializer |

Checked expressions have `type_id`. Names refer to `Symbol` IDs in `symbol`.
Calls refer to their specialized function symbol. `Node.origin` records the
unspecialized declaration; `Node.captures` points to a list of `N_BINDING` nodes
whose `symbol` is the original captured symbol. Function `integer` is the optional
C/export symbol string token, or -1; qualified names use `aux` for token span
length. Field declarations carry byte
offsets in `integer`; member expressions carry the resolved field node in `symbol`.
Function symbols use `owner` for their enclosing function; local symbols use
`owner` for their defining function and `slot` for their emitted local index.
Aggregates retain by-value semantics, slices retain element type and length,
references retain constness/optionality. Backends must reject an unimplemented
lowering instead of silently emitting a default value.

`Program.pointer_bytes` is 4 for direct Wasm and 8 for native C. Wasm slices are
one packed i64 (pointer and length), references are i32, and owned array controls
are 24 bytes. Image layouts record `Type.storage` (0 raw, 1 variable integer),
`length_storage` (-1 absent, 0 ULEB, positive fixed byte width), `padding`, `pool`,
`index_type`, `prefix` and `tail`. Record offsets are packed and come from the
checked layout; backends cannot substitute host C alignment.

The driver loads transitive imports before semantic checking. `std` declarations
may be recognized as builtins; ordinary source modules are parsed and checked.
Diagnostics accumulate in `p.diagnostics`; any error prevents publication of code.

Import syntax stores its first path token in `integer`, final path token in `aux`,
and optional source string token (not a node) in `left`; `F_REFERENCE` marks a
relative import. Namespace declarations are leaf directives; following top-level
declarations preserve their namespace name token in `scope` until resolution.
Function `aux` preserves an extern library string token. Malformed retained syntax
uses `F_BROKEN` and always has an accompanying diagnostic.
