// Shared tables for the Goose-written compiler. IDs remain valid as tables grow.
// Program is fixed: owners stay in the driver and each table is borrowed here.
import std;

let T_EOF: i64 = 0;
let T_IDENT: i64 = 1;
let T_INTLIT: i64 = 2;
let T_FLTLIT: i64 = 3;
let T_STRLIT: i64 = 4;
let T_LPAREN: i64 = 5;
let T_RPAREN: i64 = 6;
let T_LBRACKET: i64 = 7;
let T_RBRACKET: i64 = 8;
let T_LCURLY: i64 = 9;
let T_RCURLY: i64 = 10;
let T_COMMA: i64 = 11;
let T_SEMI: i64 = 12;
let T_COLON: i64 = 13;
let T_QUESTION: i64 = 14;
let T_COLONCOLON: i64 = 15;
let T_DOT: i64 = 16;
let T_DOTDOT: i64 = 17;
let T_DOTASSIGN: i64 = 18;
let T_DOTEQ: i64 = 19;
let T_DOTNEQ: i64 = 20;
let T_PLUS: i64 = 21;
let T_MINUS: i64 = 22;
let T_MUL: i64 = 23;
let T_DIV: i64 = 24;
let T_MOD: i64 = 25;
let T_PLUSEQ: i64 = 26;
let T_MINUSEQ: i64 = 27;
let T_MULEQ: i64 = 28;
let T_DIVEQ: i64 = 29;
let T_MODEQ: i64 = 30;
let T_ANDEQ: i64 = 31;
let T_OREQ: i64 = 32;
let T_XOREQ: i64 = 33;
let T_INC: i64 = 34;
let T_DEC: i64 = 35;
let T_ASSIGN: i64 = 36;
let T_EQ: i64 = 37;
let T_NEQ: i64 = 38;
let T_LT: i64 = 39;
let T_GT: i64 = 40;
let T_LTEQ: i64 = 41;
let T_GTEQ: i64 = 42;
let T_SHL: i64 = 43;
let T_SHR: i64 = 44;
let T_SHLEQ: i64 = 45;
let T_SHREQ: i64 = 46;
let T_NOT: i64 = 47;
let T_BITNOT: i64 = 48;
let T_BITAND: i64 = 49;
let T_BITOR: i64 = 50;
let T_XOR: i64 = 51;
let T_ANDAND: i64 = 52;
let T_OROR: i64 = 53;
let T_ARROW: i64 = 54;
let T_FATARROW: i64 = 55;
let T_IMPORT: i64 = 56;
let T_NAMESPACE: i64 = 57;
let T_STRUCT: i64 = 58;
let T_ENUM: i64 = 59;
let T_TYPE: i64 = 60;
let T_FN: i64 = 61;
let T_THREADFN: i64 = 62;
let T_EXPORT: i64 = 63;
let T_SIMD: i64 = 64;
let T_RECURSIVE: i64 = 65;
let T_LET: i64 = 66;
let T_VAR: i64 = 67;
let T_EXTERN: i64 = 68;
let T_CONST: i64 = 69;
let T_PAD: i64 = 70;
let T_REUSABLE: i64 = 71;
let T_IF: i64 = 72;
let T_ELSE: i64 = 73;
let T_WHILE: i64 = 74;
let T_FOR: i64 = 75;
let T_IN: i64 = 76;
let T_LOOP: i64 = 77;
let T_BLOCK: i64 = 78;
let T_GUARD: i64 = 79;
let T_MATCH: i64 = 80;
let T_RETURN: i64 = 81;
let T_BREAK: i64 = 82;
let T_CONTINUE: i64 = 83;
let T_AS: i64 = 84;
let T_TRUE: i64 = 85;
let T_FALSE: i64 = 86;
let T_NULLLIT: i64 = 87;
let T_SELF: i64 = 88;
let T_TBOOL: i64 = 89;
let T_TVARINT: i64 = 90;
let T_TI8: i64 = 91;
let T_TI16: i64 = 92;
let T_TI32: i64 = 93;
let T_TI64: i64 = 94;
let T_TU8: i64 = 95;
let T_TU16: i64 = 96;
let T_TU32: i64 = 97;
let T_TU64: i64 = 98;
let T_TF32: i64 = 99;
let T_TF64: i64 = 100;

let N_MODULE: i64 = 0;
let N_IMPORT: i64 = 1;
let N_NAMESPACE: i64 = 2;
let N_FUNCTION: i64 = 3;
let N_PARAM: i64 = 4;
let N_STRUCT: i64 = 5;
let N_FIELD: i64 = 6;
let N_ENUM: i64 = 7;
let N_VARIANT: i64 = 8;
let N_ALIAS: i64 = 9;
let N_VARIABLE: i64 = 10;
let N_BLOCK: i64 = 11;
let N_INTEGER: i64 = 12;
let N_FLOAT: i64 = 13;
let N_STRING: i64 = 14;
let N_BOOL: i64 = 15;
let N_NULL: i64 = 16;
let N_NAME: i64 = 17;
let N_UNARY: i64 = 18;
let N_BINARY: i64 = 19;
let N_CALL: i64 = 20;
let N_MEMBER: i64 = 21;
let N_INDEX: i64 = 22;
let N_SLICE: i64 = 23;
let N_ARRAY: i64 = 24;
let N_FILL: i64 = 25;
let N_RECORD: i64 = 26;
let N_IF: i64 = 27;
let N_WHILE: i64 = 28;
let N_FOR: i64 = 29;
let N_LOOP: i64 = 30;
let N_MATCH: i64 = 31;
let N_ARM: i64 = 32;
let N_RETURN: i64 = 33;
let N_BREAK: i64 = 34;
let N_CONTINUE: i64 = 35;
let N_ASSIGN: i64 = 36;
let N_EXPR_STMT: i64 = 37;
let N_TYPE_NAME: i64 = 38;
let N_TYPE_ARRAY: i64 = 39;
let N_TYPE_REF: i64 = 40;
let N_TYPE_FN: i64 = 41;
let N_TYPE_PARAM: i64 = 42;
let N_FUNCTION_VALUE: i64 = 43;
let N_GUARD: i64 = 44;
let N_CAST: i64 = 45;
let N_RANGE: i64 = 46;
let N_EMPTY: i64 = 47;
let N_BINDING: i64 = 48;
let N_TYPE_ARG: i64 = 49;
let N_EXTERN: i64 = 50;
let N_MULTI_ASSIGN: i64 = 51;
let N_PATTERN: i64 = 52;
let N_CONST_FOR: i64 = 53;
let N_TUPLE: i64 = 54;
let N_TYPEOF: i64 = 55;
let N_TYPE_DEDUCED: i64 = 56;
let N_SELF: i64 = 57;

let TY_UNKNOWN: i64 = 0;
let TY_VOID: i64 = 1;
let TY_BOOL: i64 = 2;
let TY_INT: i64 = 3;
let TY_FLOAT: i64 = 4;
let TY_ARRAY: i64 = 5;
let TY_SLICE: i64 = 6;
let TY_REF: i64 = 7;
let TY_STRUCT: i64 = 8;
let TY_ENUM: i64 = 9;
let TY_FN: i64 = 10;
let TY_GENERIC: i64 = 11;
let TY_NAME: i64 = 12;
let TY_TUPLE: i64 = 13;
let TYPE_UNKNOWN: i64 = -1;
let TYPE_VOID: i64 = 0;
let TYPE_BOOL: i64 = 1;
let TYPE_I8: i64 = 2;
let TYPE_I16: i64 = 3;
let TYPE_I32: i64 = 4;
let TYPE_I64: i64 = 5;
let TYPE_U8: i64 = 6;
let TYPE_U16: i64 = 7;
let TYPE_U32: i64 = 8;
let TYPE_U64: i64 = 9;
let TYPE_F32: i64 = 10;
let TYPE_F64: i64 = 11;
let TYPE_STRING: i64 = 12;
let F_VAR: i64 = 1;
let F_CONST: i64 = 2;
let F_EXPORT: i64 = 4;
let F_EXTERN: i64 = 8;
let F_RECURSIVE: i64 = 16;
let F_REFERENCE: i64 = 32;
let F_TAIL: i64 = 64;
let F_GENERIC: i64 = 128;
let F_CHECKED: i64 = 256;
let F_UNSIGNED: i64 = 512;
let F_INCLUSIVE: i64 = 1024;
let F_IMPLICIT_RETURN: i64 = 2048;
let F_CAPTURE: i64 = 4096;
let F_REACHABLE: i64 = 8192;
let F_BOUNDS_PROVEN: i64 = 16384;
let F_SIMD: i64 = 32768;
let F_THREAD: i64 = 65536;
let F_REUSABLE: i64 = 131072;
let F_REUSABLE_SLICES: i64 = 262144;
let F_PAD: i64 = 524288;
let F_CHECKFREE: i64 = 1048576;
let F_INLINE: i64 = 2097152;
let F_NONLOCAL: i64 = 4194304;
let F_MULTI: i64 = 8388608;
let F_DEFAULT: i64 = 16777216;
let F_EARLY: i64 = 33554432;
let F_EXPLICIT_PARAMS: i64 = 67108864;
let F_INDEX_TYPE: i64 = 134217728;
let F_BOUND_TYPE: i64 = 268435456;
let F_FROM_END: i64 = 536870912;
let F_TO_END: i64 = 1073741824;
let F_VARIABLE_MODE: i64 = 2147483648;
let F_BROKEN: i64 = 4294967296;
let F_DISPATCH: i64 = 8589934592;
let F_SYNTHETIC: i64 = 17179869184;
let F_REFERENCE_CONTEXT: i64 = 34359738368;
let F_DIVERGES: i64 = 68719476736;
let F_RETURNS: i64 = 137438953472;
let F_FORMAT_RAW: i64 = 274877906944;
let F_PROPERTY: i64 = 549755813888;
let TF_UNSIGNED: i64 = 1;
let TF_OPTIONAL: i64 = 2;
let TF_CONST: i64 = 4;
let A_FIXED: i64 = 0;
let A_VAR: i64 = 1;
let A_LIMITED: i64 = 2;
let A_GROW: i64 = 3;
let A_GROWSHRINK: i64 = 4;
let A_SLICE: i64 = 5;
let S_FUNCTION: i64 = 1;
let S_GLOBAL: i64 = 2;
let S_PARAMETER: i64 = 4;
let S_MUTABLE: i64 = 8;
let S_TYPE: i64 = 16;
let S_EXTERN: i64 = 32;
let S_BUILTIN: i64 = 64;
let S_CAPTURE: i64 = 128;

struct Source {
    path_start: i64 = 0, path_len: i64 = 0,
    text_start: i64 = 0, text_len: i64 = 0,
    token_start: i64 = 0, token_end: i64 = 0, root: i64 = -1,
}
struct Token {
    kind: i64 = 0, source: i64 = 0, start: i64 = 0, end: i64 = 0,
    line: i64 = 1, column: i64 = 1, integer: i64 = 0,
    float_value: f64 = 0.0, text_start: i64 = 0, text_len: i64 = 0,
    flags: i64 = 0,
}
struct Node {
    kind: i64 = 0, token: i64 = -1,
    first: i64 = -1, last: i64 = -1, next: i64 = -1,
    left: i64 = -1, right: i64 = -1, third: i64 = -1,
    type_id: i64 = -1, symbol: i64 = -1,
    integer: i64 = 0, float_value: f64 = 0.0, flags: i64 = 0,
    scope: i64 = -1, aux: i64 = -1,
    origin: i64 = -1, captures: i64 = -1,
    named_results: i64 = -1,
    coerced_type: i64 = -1,
    expansion_binding: i64 = -1,
}
struct Type {
    kind: i64 = 0, element: i64 = -1, count: i64 = 0,
    declaration: i64 = -1, first: i64 = -1, flags: i64 = 0,
    name_token: i64 = -1, size: i64 = 0, align: i64 = 1,
    array_kind: i64 = 0,
    storage: i64 = 0, length_storage: i64 = -1, padding: i64 = 0,
    pool: i64 = -1, index_type: i64 = -1, prefix: i64 = -1, tail: i64 = -1,
    arguments: i64 = -1,
    length_explicit: bool = false,
}
struct Symbol {
    name_token: i64 = -1, type_id: i64 = -1, node: i64 = -1,
    scope: i64 = -1, slot: i64 = -1, flags: i64 = 0, next: i64 = -1,
    owner: i64 = -1, offset: i64 = 0, index: i64 = -1,
    scope_next: i64 = -1,
    provenance: i64 = -1,
}
struct Diagnostic {
    source: i64 = 0, start: i64 = 0, end: i64 = 0,
    line: i64 = 1, column: i64 = 1,
    message_start: i64 = 0, message_len: i64 = 0, severity: i64 = 1,
}
struct Program {
    text: u8[>..]&, messages: u8[>..]&, sources: Source[>..]&,
    tokens: Token[>..]&, nodes: Node[>..]&, types: Type[>..]&,
    symbols: Symbol[>..]&, diagnostics: Diagnostic[>..]&,
    entry: i64 = -1, initial_pages: i64 = 16, maximum_pages: i64 = 256,
    optimization: i64 = 0, debug: bool = false,
    pointer_bytes: i64 = 4,
    library: bool = false,
}
fn same_bytes(a: u8[:], b: u8[:]) -> bool {
    if a.len != b.len { return false; }
    for c, i in a { if c != b[i] { return false; } }
    return true;
}
fn token_text(p: Program&, token: i64) -> u8[:] {
    if token < 0 || token >= p.tokens.len { return ""; }
    let t = p.tokens[token];
    return p.text[t.start..t.end];
}
fn same_name(p: Program&, a: i64, b: i64) -> bool {
    return same_bytes(token_text(p, a), token_text(p, b));
}
fn token_is(p: Program&, token: i64, text: u8[:]) -> bool {
    return same_bytes(token_text(p, token), text);
}
fn diagnose_at(p: Program&, source: i64, start: i64, end: i64, message: u8[:]) {
    var line = 1; var column = 1;
    if source >= 0 && source < p.sources.len {
        let origin = p.sources[source].text_start;
        for i in origin..start {
            if p.text[i] == 10 { line += 1; column = 1; } else { column += 1; }
        }
    }
    let at = p.messages.len;
    p.messages.append(message);
    p.diagnostics.push(Diagnostic { source: source, start: start, end: end,
        line: line, column: column, message_start: at, message_len: message.len });
}
fn diagnose(p: Program&, token: i64, message: u8[:]) {
    if token >= 0 && token < p.tokens.len {
        let t = p.tokens[token];
        diagnose_at(p, t.source, t.start, t.end, message);
    } else { diagnose_at(p, 0, 0, 0, message); }
}
fn new_node(p: Program&, kind: i64, token: i64) -> i64 {
    let id = p.nodes.len;
    p.nodes.push(Node { kind: kind, token: token });
    return id;
}
fn append_child(p: Program&, parent: i64, child: i64) {
    if child < 0 { return; }
    let tail = p.nodes[parent].last;
    if tail < 0 { p.nodes[parent].first = child; }
    else { p.nodes[tail].next = child; }
    var last = child;
    while p.nodes[last].next >= 0 { last = p.nodes[last].next; }
    p.nodes[parent].last = last;
}
fn add_type(p: Program&, ty: Type) -> i64 {
    let id = p.types.len; p.types.push(ty); return id;
}
fn initialize_types(p: Program&) {
    add_type(p, Type { kind: TY_VOID });
    add_type(p, Type { kind: TY_BOOL, count: 1, size: 1 });
    for bits in [8, 16, 32, 64] { add_type(p, Type { kind: TY_INT, count: bits, size: bits / 8 }); }
    for bits in [8, 16, 32, 64] { add_type(p, Type { kind: TY_INT, count: bits, flags: TF_UNSIGNED, size: bits / 8 }); }
    add_type(p, Type { kind: TY_FLOAT, count: 32, size: 4 });
    add_type(p, Type { kind: TY_FLOAT, count: 64, size: 8 });
    add_type(p, Type { kind: TY_SLICE, element: TYPE_U8, count: -1, flags: TF_CONST,
                       size: p.pointer_bytes * 2, align: p.pointer_bytes });
}
