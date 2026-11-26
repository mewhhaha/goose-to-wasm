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
// The opening brace of a library function body whose text the lexer skipped; integer holds
// the offset of the matching closing brace.
let T_LAZY_BODY: i64 = 101;
let T_DEFER: i64 = 102;
let T_INVALID: i64 = 255;
let TOKEN_SOURCE_LIMIT: i64 = 65536;

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
let N_RESULT: i64 = 58;
// `defer` statement: right is its body block (upstream e1d95ed).
let N_DEFER: i64 = 59;
// `const if`: left condition, right branch fragments, third the else branch
// (another N_CONST_IF for `else const if`); integer is the fragment context,
// 0 statements, 1 initializers, 2 match arms (upstream e93d4fc).
let N_CONST_IF: i64 = 60;

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
let F_RETURN_MOVE: i64 = 1099511627776;
let F_RESULT_TEMP: i64 = 2199023255552;
// A library function body block whose tokens are parsed when the checker first reaches it.
let F_DEFERRED: i64 = 4398046511104;
// A `root struct` declaration: independently stored fields under one owner.
let F_ROOT: i64 = 8796093022208;
// An array-only branch join still awaiting a slice destination.
let F_ARRAY_JOIN: i64 = 17592186044416;
// Bits 45 and 46 are the Wasm print-analysis cache. This storage bit
// is omitted from the public IR dump.
let F_HAS_EXTRA: i64 = 140737488355328;
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
// A parameter a literal argument binds alone: a constant of unknown value
// that adapts where it is used (upstream §7.7).
let S_LITERAL: i64 = 256;

struct Source {
    path_start: i64 = 0, path_len: i64 = 0,
    text_start: i64 = 0, text_len: i64 = 0,
    token_start: i64 = 0, token_end: i64 = 0, root: i64 = -1, next_decl: i64 = -1,
    library: bool = false,
}
struct Token {
    integer: i64 = 0,
    start: i32 = 0, end: i32 = 0,
    text_start: i32 = 0, text_len: i32 = 0,
    line: i32 = 1,
    source: u16 = 0, kind: u8 = 0, flags: u8 = 0,
}
struct Node {
    integer: i64 = 0, flags: i64 = 0,
    kind: i32 = 0, token: i32 = -1,
    first: i32 = -1, last: i32 = -1, next: i32 = -1,
    left: i32 = -1, right: i32 = -1, third: i32 = -1,
    type_id: i32 = -1, symbol: i32 = -1,
    scope: i32 = -1, aux: i32 = -1,
}
struct NodeExtra {
    node: i32 = -1, origin: i32 = -1, captures: i32 = -1, named_results: i32 = -1,
    coerced_type: i32 = -1, expansion_binding: i32 = -1, wide_aux: i64 = -1,
}
struct TokenColumn { token: i32, column: i32 }

// Goose's as! converts floating-point values numerically. Use the byte image
// of one scalar to preserve its bits, including signed zero and NaN payloads.
fn float_bits(value: f64) -> i64 {
    let values: f64[1] = [value];
    let bytes = bytes_of(values);
    var bits: u64 = 0;
    for i in 0..8 { bits |= (bytes[i] as u64) << (i * 8); }
    return bits as! i64;
}
fn float_from_bits(bits: i64) -> f64 {
    // One eight-byte element in the growable array image format.
    var image: u8[9] = [8, 0, 0, 0, 0, 0, 0, 0, 0];
    let value = bits as! u64;
    for i in 0..8 { image[i + 1] = (value >> (i * 8)) as! u8; }
    let values, ok = from_bytes<f64[>..]>(image);
    assert(ok);
    return values[0];
}
inline fn token_float(t: const Token&) -> f64 { return float_from_bits(t.integer); }
inline fn set_token_float(t: Token&, value: f64) { t.integer = float_bits(value); }
inline fn node_float(n: const Node&) -> f64 { return float_from_bits(n.integer); }
inline fn set_node_float(n: Node&, value: f64) { n.integer = float_bits(value); }
// kind, element, count, flags and declaration identify a type for lookup
// (type_find): whoever changes one of them on an existing type reindexes it.
struct Type {
    kind: i64 = 0, element: i64 = -1, count: i64 = 0,
    declaration: i64 = -1, first: i64 = -1, flags: i64 = 0,
    name_token: i64 = -1, size: i64 = 0, align: i64 = 1,
    array_kind: i64 = 0,
    storage: i64 = 0, length_storage: i64 = -1, padding: i64 = 0,
    pool: i64 = -1, index_type: i64 = -1, prefix: i64 = -1, tail: i64 = -1,
    arguments: i64 = -1,
    length_explicit: bool = false,
    // Wasm emission's memoized layout predicates, keyed by this type's own ID so a
    // copied type never inherits them: (id + 1) << 16 | known/value bit pairs.
    codegen_memo: i64 = 0,
    // C emission's memoized layout predicates and sizes, keyed by this type's own ID.
    cc_memo_id: i32 = -1,
    cc_memo_flags: u32 = 0,
    cc_frame_size_cache: i64 = -1,
    cc_region_width_cache: i32 = -1,
}
struct Symbol {
    name_token: i64 = -1, type_id: i64 = -1, node: i64 = -1,
    scope: i64 = -1, slot: i64 = -1, flags: i64 = 0, next: i64 = -1,
    owner: i64 = -1, offset: i64 = 0, index: i64 = -1,
    provenance: i64 = -1,
    name_next: i64 = -1,
    // A named array component (`owner.field` in an index or relative
    // reference type): the global root owner and, once resolved, its field
    // node (upstream NamedArrayComponent).
    component_owner: i64 = -1, component: i64 = -1,
}
struct SymbolOwners { heads: i64[>..]&, next: i64[>..]& }
struct Diagnostic {
    source: i64 = 0, start: i64 = 0, end: i64 = 0,
    line: i64 = 1, column: i64 = 1,
    message_start: i64 = 0, message_len: i64 = 0, severity: i64 = 1,
}
// A type identity bucket (type_find): its chain in ascending type ID. Paired
// tables share an array, as each array costs a region.
struct TypeBucket { head: i64 = -1, tail: i64 = -1 }
// An indexed type's successor in its bucket's chain, and its bucket hash.
struct TypeLink { next: i64 = -1, hash: i64 = 0 }
// Library nodes the optimizer copied into the program's own code (upstream
// Inliner::AtCallSite), nodes first until end: a failed check at one reports
// the line of site, the program's call into the library (location_token).
struct InlineSite { first: i64 = 0, end: i64 = 0, site: i64 = -1 }
// Active generic/stdlib instantiation frames for diagnostics (upstream 2b509397).
struct InstantiationSite { decl_node: i64 = -1, call_token: i64 = -1 }
struct Program {
    text: u8[>..]&, messages: u8[>..]&, sources: Source[>..]&,
    tokens: Token[>..]&, nodes: Node[>..]&, types: Type[>..]&,
    node_extra_slots: i32[>..]&, node_extras: NodeExtra[>..]&,
    token_columns: TokenColumn[>..]&,
    symbols: Symbol[>..]&, diagnostics: Diagnostic[>..]&,
    // Memoized type properties (type * 8 + property, value + 1; 0 unknown)
    // and the builtin symbol of each builtin ID (-1 none yet).
    type_properties: i64[>..]&, builtin_symbols: i64[>..]&,
    // Type identity index (type_find): its buckets, each indexed type's link,
    // and how many types are indexed so far.
    type_buckets: TypeBucket[>..]&, type_links: TypeLink[>..]&,
    type_indexed: i64 = 0,
    // Per type, the type property scan that last queued it (check_type_property_scan).
    type_scan_marks: i64[>..]&, type_scan_stamp: i64 = 0,
    // Per type, life_holds_walk's answer (0 unknown, 1 no, 2 yes). Lifetime
    // analysis only adds types and nodes, so an answer stays valid.
    type_holds: i64[>..]&,
    entry: i64 = -1, first_decl_source: i64 = -1, initial_pages: i64 = 16, maximum_pages: i64 = 256,
    optimization: i64 = 0, jobs: i64 = 1, debug: bool = false,
    pointer_bytes: i64 = 4,
    // wide: the direct Wasm target with 64-bit memory (--wasm-memory64).
    // pointer_bytes is 8 there as on the native target; a growable array's
    // control is six address-sized words, control_bytes of them.
    wide: bool = false, control_bytes: i64 = 24, control_align: i64 = 4,
    library: bool = false,
    // c_host: --header or --shared C-host build (checks reachable exports/main/threads
    // without checking unreached functions; emits goose_init/goose_exit instead of main).
    c_host: bool = false, shared: bool = false, separate_runtime: bool = false,
    // check_only: --check or --parse, where a program that declares no main
    // is checked on its own (upstream nomain). reachable_program: unreached
    // functions are not checked (the reference checker's
    // GOOSE_REACHABLE_PROGRAM build, blot2 upstream-32a4f44 patch 03).
    check_only: bool = false, reachable_program: bool = false,
    dump_ir: bool = false,
    saw_inline_checkfree: bool = false, has_checked_checkfree: bool = false,
    // Time the lifetime pass took, reported apart from type checking.
    lifetime_ns: i64 = 0,
    // The program's total const for expansion size (upstream ExpansionClone,
    // whose reference build raises it to 1000000).
    expansion_limit: i64 = 100000,
    // --stack-reserve: the address space per data stack the generated C asks
    // for (GS_STACK_RESERVE), or 0 for the runtime's 2 GiB.
    stack_reserve: i64 = 0,
    // Code generation: a `defer` body may run while a nonlocal return passes
    // through its function (mark_unwinding_functions).
    unwinding: bool = false,
    // Native code generation: F_UNWINDS marks every function a return may
    // leave, with or without defers (marked when first needed).
    leaving_marked: bool = false,
    // Library code inlined into the program's code, in ascending first.
    inline_sites: InlineSite[>..]&,
    // Active generic/stdlib instantiation call stack for diagnostic notes.
    instantiation_stack: InstantiationSite[>..]&, instantiation_depth: i64 = 0,
    // Direct Wasm data regions: region_profile[i] is the bytes region i was
    // seen to need (--wasm-region-profile), the weight of its share of memory;
    // region_stats makes the module keep each region's high-water mark.
    region_profile: i64[>..]&, region_stats: bool = false, bundled_host: bool = false,
    // Interned T_IDENT lookup table: 1-based canonical token ID per slot (0 empty).
    ident_table: i32[>..]&, ident_count: i64 = 0,
}
fn index_symbol_owners(p: Program&, owners: SymbolOwners&) {
    // Owner -1 names the initializer. Keep every list in symbol order
    // for stable frame layout and emission.
    owners.heads.resize(p.nodes.len + 1, -1);
    owners.next.resize(p.symbols.len, -1);
    var index = p.symbols.len;
    while index > 0 {
        index--;
        let owner = p.symbols[index].owner + 1;
        owners.next[index] = owners.heads[owner];
        owners.heads[owner] = index;
    }
}
fn bytes_hash(bytes: u8[:]) -> i64 {
    var hash: u32 = 2166136261;
    for byte in bytes { hash = (hash ^ (byte as u32)) * 16777619; }
    return hash as i64;
}
fn intern_ident(p: Program&, token_id: i64, hash: u32) {
    let h = hash as i64;
    let tok: const Token& = p.tokens[token_id];
    let start = tok.start; let end = tok.end; let length = end - start;
    if 2 * (p.ident_count + 1) > p.ident_table.len {
        var new_size: i64 = 16384;
        if p.ident_table.len > 0 { new_size = p.ident_table.len * 2; }
        var old_reps: i32[>..] = [];
        for entry in p.ident_table { if entry > 0 { old_reps.push(entry); } }
        p.ident_table.clear();
        p.ident_table.resize(new_size, 0);
        let new_mask = new_size - 1;
        for rep_plus_one in old_reps {
            let rep = (rep_plus_one as i64) - 1;
            var slot = p.tokens[rep].integer & new_mask;
            while p.ident_table[slot] != 0 { slot = (slot + 1) & new_mask; }
            p.ident_table[slot] = rep_plus_one;
        }
    }
    let mask = p.ident_table.len - 1;
    var slot = h & mask;
    let text: const u8[:] = p.text;
    loop {
        let entry = p.ident_table[slot];
        if entry == 0 {
            let canonical = (token_id + 1) as i32;
            p.ident_table[slot] = canonical;
            p.ident_count += 1;
            p.tokens[token_id].integer = h;
            p.tokens[token_id].text_start = canonical;
            return;
        }
        let rep = (entry as i64) - 1;
        let rt: const Token& = p.tokens[rep];
        if rt.integer == h && rt.end - rt.start == length {
            var same = true;
            var rstart = rt.start;
            for i in 0..length {
                if text[rstart + i] != text[start + i] { same = false; break; }
            }
            if same {
                p.tokens[token_id].integer = h;
                p.tokens[token_id].text_start = entry;
                return;
            }
        }
        slot = (slot + 1) & mask;
    }
}
fn intern_ident_token(p: Program&, token_id: i64) {
    let t: const Token& = p.tokens[token_id];
    var h: u32 = 2166136261;
    for i in t.start..t.end { h = (h ^ (p.text[i] as u32)) * 16777619; }
    intern_ident(p, token_id, h);
}
inline fn token_hash(p: Program&, token: i64) -> i64 {
    if token < 0 || token >= p.tokens.len { return 2166136261; }
    let t: const Token& = p.tokens[token];
    if t.kind == T_IDENT && t.text_start > 0 { return t.integer; }
    return bytes_hash(p.text[t.start..t.end]);
}
inline fn same_bytes(a: u8[:], b: u8[:]) -> bool {
    if a.len != b.len { return false; }
    for c, i in a { if c != b[i] { return false; } }
    return true;
}
inline fn token_text(p: Program&, token: i64) -> u8[:] {
    if token < 0 || token >= p.tokens.len { return ""; }
    let t: const Token& = p.tokens[token];
    return p.text[t.start..t.end];
}
inline fn same_name(p: Program&, a: i64, b: i64) -> bool {
    if a == b { return true; }
    if a < 0 || a >= p.tokens.len || b < 0 || b >= p.tokens.len {
        return same_bytes(token_text(p, a), token_text(p, b));
    }
    let left: const Token& = p.tokens[a]; let right: const Token& = p.tokens[b];
    if left.kind == T_IDENT && right.kind == T_IDENT && left.text_start > 0 && right.text_start > 0 {
        return left.text_start == right.text_start;
    }
    return same_bytes(p.text[left.start..left.end], p.text[right.start..right.end]);
}
inline fn token_is(p: Program&, token: i64, text: u8[:]) -> bool {
    if token < 0 || token >= p.tokens.len { return same_bytes("", text); }
    let value: const Token& = p.tokens[token];
    return same_bytes(p.text[value.start..value.end], text);
}
fn format_token_location(p: Program&, token: i64, out: u8[>..]&) {
    if token < 0 || token >= p.tokens.len { out.append("<unknown>"); return; }
    let t: const Token& = p.tokens[token];
    if t.source < p.sources.len {
        let s: const Source& = p.sources[t.source];
        out.append(p.text[s.path_start..s.path_start + s.path_len]);
        var line: i64 = 1; var col: i64 = 1;
        for i in s.text_start..t.start {
            if p.text[i] == 10 { line += 1; col = 1; } else { col += 1; }
        }
        out.push(':'); out.format(line); out.push(':'); out.format(col);
    } else {
        out.append("<source>");
    }
}
fn push_instantiation(p: Program&, decl_node: i64, call_token: i64) {
    let site = InstantiationSite { decl_node: decl_node, call_token: call_token };
    if p.instantiation_depth < p.instantiation_stack.len { p.instantiation_stack[p.instantiation_depth] = site; }
    else { p.instantiation_stack.push(site); }
    p.instantiation_depth += 1;
}
fn pop_instantiation(p: Program&) {
    if p.instantiation_depth > 0 { p.instantiation_depth -= 1; }
}
fn diagnose_at(p: Program&, source: i64, start: i64, end: i64, message: const u8[:]) {
    var full: u8[>..] = [];
    full.append(message);
    if p.instantiation_depth > 0 {
        var shown: i64 = 0;
        var prev_tok: i64 = -1;
        var idx = p.instantiation_depth;
        while idx > 0 && shown < 8 {
            idx -= 1;
            let frame = p.instantiation_stack[idx];
            let ctok = frame.call_token;
            if ctok < 0 || ctok >= p.tokens.len || ctok == prev_tok { continue; }
            let ct = p.tokens[ctok];
            if ct.source == source && ct.start == start { continue; }
            prev_tok = ctok;
            full.append("\n  note: while instantiating ");
            var named = false;
            var is_type = false;
            if frame.decl_node >= 0 && frame.decl_node < p.nodes.len {
                let dn_kind = p.nodes[frame.decl_node].kind;
                let dn_tok = p.nodes[frame.decl_node].token;
                if dn_kind == N_STRUCT || dn_kind == N_ENUM { is_type = true; }
                if dn_kind == N_FUNCTION_VALUE {
                    full.append("function value"); named = true;
                } else if dn_tok >= 0 && dn_tok < p.tokens.len && p.tokens[dn_tok].kind == T_IDENT {
                    full.push('`'); full.append(token_text(p, dn_tok)); full.push('`');
                    named = true;
                }
            }
            if !named { full.append("declaration"); }
            if is_type { full.append(" referenced at "); } else { full.append(" called from "); }
            format_token_location(p, ctok, full);
            shown += 1;
        }
    }
    for d in p.diagnostics {
        if d.source == source && d.start == start &&
           same_bytes(p.messages[d.message_start..d.message_start + d.message_len], full) { return; }
    }
    var line = 1; var column = 1;
    if source >= 0 && source < p.sources.len {
        let origin = p.sources[source].text_start;
        for i in origin..start {
            if p.text[i] == 10 { line += 1; column = 1; } else { column += 1; }
        }
    }
    let at = p.messages.len;
    p.messages.append(full);
    p.diagnostics.push(Diagnostic { source: source, start: start, end: end,
        line: line, column: column, message_start: at, message_len: full.len });
}
fn diagnose(p: Program&, token: i64, message: const u8[:]) {
    if token >= 0 && token < p.tokens.len {
        let t = p.tokens[token];
        diagnose_at(p, t.source, t.start, t.end, message);
    } else { diagnose_at(p, 0, 0, 0, message); }
}
// Whether a node comes from a library module (resolved through --stdlib).
// Unreached library functions are neither prepared nor checked.
inline fn library_node(p: Program&, node: i64) -> bool {
    let token = p.nodes[node].token;
    return token >= 0 && token < p.tokens.len && p.sources[p.tokens[token].source].library;
}
inline fn library_token(p: Program&, token: i64) -> bool {
    return token >= 0 && token < p.tokens.len && p.sources[p.tokens[token].source].library;
}
// The token whose line a failed check at node reports: its own, or, for a
// library node an inline copied into the program's code, the program's call.
fn location_token(p: Program&, node: i64) -> i64 {
    if node < 0 || node >= p.nodes.len { return -1; }
    let token = p.nodes[node].token;
    if p.inline_sites.len == 0 || node < p.inline_sites[0].first || !library_token(p, token) { return token; }
    var low = 0; var high = p.inline_sites.len;
    while low < high {
        let middle = (low + high) / 2;
        if p.inline_sites[middle].first <= node { low = middle + 1; } else { high = middle; }
    }
    if low > 0 && node < p.inline_sites[low - 1].end { return p.inline_sites[low - 1].site; }
    return token;
}
// Code generation scratch on function nodes: the function takes the place
// where the program called the standard library as a hidden last parameter
// (upstream SpecInfo::located, 52282722). A failed check on one of its own
// library lines reports there, and its calls from those lines pass it on.
let F_LOCATED: i64 = 288230376151711744;
// The runtime entry points that report a failure where the program called
// the library (upstream SFunction::takesloc): the slice pool's span tree.
fn location_extern(p: Program&, function: i64) -> bool {
    let n = p.nodes[function]; var name = token_text(p, n.token);
    if n.integer >= 0 && n.integer < p.tokens.len && p.tokens[n.integer].kind == T_STRLIT {
        let t = p.tokens[n.integer]; name = p.text[t.text_start..t.text_start + t.text_len];
    }
    return same_bytes(name, "gs_slice_pool_place") || same_bytes(name, "gs_slice_pool_free") ||
        same_bytes(name, "gs_slice_pool_regrow") || same_bytes(name, "gs_slice_pool_trim");
}
// Marks the located functions: every checked function of a --stdlib module
// but its externs, and the location_extern externs wherever declared; not
// exports, main, thread functions or functions a function value names,
// which their callers reach without a location. A function value is a
// function's name or a function literal that code generation evaluates,
// so neither a direct call's callee nor the trailing block a call binds to
// a function parameter. Returns whether any function is located.
// Code generation scratch on function nodes: the function is used as a
// first-class function value (mark_located_functions).
let F_VALUE_USED: i64 = 1152921504606846976;

fn mark_located_functions(p: Program&, mark_values: bool = false) -> bool {
    var candidates = false;
    var roots: i64[>..] = [];
    for id in 0..p.nodes.len {
        let n: const Node& = p.nodes[id];
        if n.kind != N_FUNCTION && n.kind != N_FUNCTION_VALUE { continue; }
        p.nodes[id].flags &= ~(F_LOCATED | F_VALUE_USED);
        if (n.flags & (F_CHECKED | F_GENERIC)) == F_CHECKED {
            roots.push(n.right);
            if library_node(p, id) || (n.flags & F_EXTERN) != 0 && location_extern(p, id) { candidates = true; }
        }
    }
    if !candidates && !mark_values { return false; }
    for s_id in 0..p.symbols.len {
        let s: const Symbol& = p.symbols[s_id];
        if (s.flags & S_GLOBAL) != 0 && s.node >= 0 { roots.push(p.nodes[s.node].right); }
    }
    var work: i64[>..] = [];
    for root in roots {
        if root < 0 { continue; }
        work.clear(); work.push(root);
        while work.len > 0 {
            let id = work.pop();
            let n: const Node& = p.nodes[id];
            if id != root && n.next >= 0 { work.push(n.next); }
            let kind = n.kind;
            if kind == N_FUNCTION || kind == N_IMPORT || kind == N_STRUCT || kind == N_ENUM || kind == N_ALIAS || kind == N_PATTERN { continue; }
            if kind == N_FUNCTION_VALUE { p.nodes[id].flags |= F_VALUE_USED; continue; }
            if kind == N_NAME && n.symbol >= 0 {
                let sym: const Symbol& = p.symbols[n.symbol];
                if (sym.flags & (S_FUNCTION | S_BUILTIN)) == S_FUNCTION && sym.node >= 0 {
                    p.nodes[sym.node].flags |= F_VALUE_USED;
                }
            }
            if kind == N_CALL && n.symbol >= 0 && ((n.flags & F_DISPATCH) != 0 || (p.symbols[n.symbol].flags & (S_FUNCTION | S_BUILTIN)) == S_FUNCTION) {
                if n.first >= 0 { work.push(n.first); }
                continue;
            }
            if n.first >= 0 { work.push(n.first); }
            if n.left >= 0 { work.push(n.left); }
            if n.right >= 0 { work.push(n.right); }
            if n.third >= 0 { work.push(n.third); }
        }
    }
    if !candidates { return false; }
    var located = false;
    for id in 0..p.nodes.len {
        let n: const Node& = p.nodes[id];
        if n.kind != N_FUNCTION && n.kind != N_FUNCTION_VALUE { continue; }
        if (n.flags & (F_CHECKED | F_GENERIC | F_VALUE_USED)) != F_CHECKED { continue; }
        if (n.flags & (F_EXPORT | F_THREAD)) != 0 || id == p.entry { continue; }
        if (n.flags & F_EXTERN) != 0 { if !location_extern(p, id) { continue; } }
        else if !library_node(p, id) { continue; }
        p.nodes[id].flags |= F_LOCATED; located = true;
    }
    return located;
}
// Code generation scratch on function nodes: a call to the function may
// leave through a nonlocal return in flight (mark_unwinding_functions).
let F_UNWINDS: i64 = 576460752303423488;
// Whether a function may be left by a return through it (§7.9): it holds a
// return to another function, or calls a function that may be, directly,
// through dispatch or through a function-typed value. Returns whether any
// emitted function holds a `defer` (§6.6) and any may be left so: only then
// do defer bodies run on the propagation path of such a return. With
// `without_defers`, marks the functions even where no `defer` is held and
// returns whether any may be left.
fn mark_unwinding_functions(p: Program&, without_defers: bool = false) -> bool {
    var functions: i64[>..] = []; var defers = false; var sites = false;
    for id in 0..p.nodes.len {
        let n: const Node& = p.nodes[id];
        if n.kind == N_DEFER && (n.flags & F_CHECKED) != 0 { defers = true; }
        if n.kind != N_FUNCTION && n.kind != N_FUNCTION_VALUE { continue; }
        p.nodes[id].flags &= ~F_UNWINDS;
        if (n.flags & (F_CHECKED | F_GENERIC)) == F_CHECKED && n.right >= 0 { functions.push(id); }
    }
    if !defers && !without_defers { return false; }
    var changed = true; var work: i64[>..] = [];
    while changed {
        changed = false;
        for function in functions {
            if (p.nodes[function].flags & F_UNWINDS) != 0 { continue; }
            let root = p.nodes[function].right; var unwinds = false;
            work.clear(); work.push(root);
            while work.len > 0 && !unwinds {
                let id = work.pop(); if id < 0 { continue; }
                let n: const Node& = p.nodes[id];
                if id != root && n.next >= 0 { work.push(n.next); }
                let kind = n.kind;
                if kind == N_FUNCTION || kind == N_FUNCTION_VALUE || kind == N_IMPORT || kind == N_STRUCT || kind == N_ENUM || kind == N_ALIAS || kind == N_PATTERN { continue; }
                if kind == N_RETURN && n.symbol >= 0 && n.symbol < p.symbols.len && p.symbols[n.symbol].node != function { unwinds = true; sites = true; }
                if kind == N_CALL && (n.flags & F_DISPATCH) != 0 {
                    var arm = n.third;
                    while arm >= 0 {
                        let symbol = p.nodes[arm].symbol;
                        if symbol >= 0 && p.symbols[symbol].node >= 0 && (p.nodes[p.symbols[symbol].node].flags & F_UNWINDS) != 0 { unwinds = true; }
                        arm = p.nodes[arm].next;
                    }
                } else if kind == N_CALL && n.symbol >= 0 {
                    let callee: const Symbol& = p.symbols[n.symbol];
                    if (callee.flags & (S_FUNCTION | S_BUILTIN)) == S_FUNCTION && callee.node >= 0 && (p.nodes[callee.node].flags & F_UNWINDS) != 0 { unwinds = true; }
                } else if kind == N_CALL && sites { unwinds = true; }
                if n.first >= 0 { work.push(n.first); }
                if n.left >= 0 { work.push(n.left); }
                if n.right >= 0 { work.push(n.right); }
                if n.third >= 0 { work.push(n.third); }
            }
            if unwinds { p.nodes[function].flags |= F_UNWINDS; changed = true; }
        }
    }
    return sites;
}
// A root struct: independently stored fields under one owner, never a
// fixed-size value (upstream docs/design/root_structs.md, SC_ROOT).
fn root_struct_type(p: Program&, ty: i64) -> bool {
    if ty < 0 { return false; }
    let t: const Type& = p.types[ty];
    return t.kind == TY_STRUCT && t.declaration >= 0 && p.nodes[t.declaration].kind == N_STRUCT && (p.nodes[t.declaration].flags & F_ROOT) != 0;
}
// Entries are stable by key even when a node is replaced. Only F_HAS_EXTRA
// makes its current entry live. Negative keys preserve checker syntax snapshots.
inline fn node_extra_bucket(id: i64, mask: i64) -> i64 {
    let hash = (id as! u64) * 11400714819323198485;
    return ((hash ^ (hash >> 32)) as! i64) & mask;
}
fn node_extra_slot(p: const Program&, id: i64) -> i64 {
    let mask = p.node_extra_slots.len - 1;
    var slot = node_extra_bucket(id, mask);
    loop {
        let entry = p.node_extra_slots[slot];
        if entry == 0 || p.node_extras[entry - 1].node == id { return slot; }
        slot = (slot + 1) & mask;
    }
}
fn node_extra_get(p: const Program&, id: i64) -> const NodeExtra& {
    return p.node_extras[p.node_extra_slots[node_extra_slot(p, id)] - 1];
}
fn node_extra_index(p: Program&, id: i64) -> i64 {
    if p.node_extra_slots.len > 0 {
        let entry = p.node_extra_slots[node_extra_slot(p, id)];
        if entry != 0 { return entry - 1; }
    }
    if p.node_extras.len * 2 >= p.node_extra_slots.len {
        let size = if p.node_extra_slots.len == 0 { 32 } else { p.node_extra_slots.len * 2 };
        for i in 0..p.node_extra_slots.len { p.node_extra_slots[i] = 0; }
        while p.node_extra_slots.len < size { p.node_extra_slots.push(0); }
        for extra, i in p.node_extras {
            p.node_extra_slots[node_extra_slot(p, extra.node)] = (i + 1) as i32;
        }
    }
    let index = p.node_extras.len;
    p.node_extra_slots[node_extra_slot(p, id)] = (index + 1) as i32;
    p.node_extras.push(NodeExtra { node: id as i32 });
    return index;
}
fn node_extra_put(p: Program&, id: i64, extra: NodeExtra) {
    let index = node_extra_index(p, id);
    p.node_extras[index] = extra;
    p.node_extras[index].node = id as i32;
}
fn node_extra_ensure(p: Program&, id: i64) -> i64 {
    let index = node_extra_index(p, id);
    if (p.nodes[id].flags & F_HAS_EXTRA) == 0 {
        p.node_extras[index] = NodeExtra { node: id as i32 };
        p.nodes[id].flags |= F_HAS_EXTRA;
    }
    return index;
}
inline fn node_copy_extra(p: Program&, dest: i64, source: i64, flags: i64) {
    if (flags & F_HAS_EXTRA) != 0 && dest != source {
        let extra = node_extra_get(p, source);
        node_extra_put(p, dest, extra);
    }
}
inline fn node_copy(p: Program&, dest: i64, source: i64) {
    let value = p.nodes[source];
    node_copy_extra(p, dest, source, value.flags);
    p.nodes[dest] = value;
}
inline fn node_origin(p: const Program&, id: i64) -> i32 {
    if (p.nodes[id].flags & F_HAS_EXTRA) == 0 { return -1; }
    return node_extra_get(p, id).origin;
}
inline fn set_node_origin(p: Program&, id: i64, value: i64) {
    if value == -1 && (p.nodes[id].flags & F_HAS_EXTRA) == 0 { return; }
    let index = node_extra_ensure(p, id);
    p.node_extras[index].origin = value as i32;
}
inline fn node_captures(p: const Program&, id: i64) -> i32 {
    if (p.nodes[id].flags & F_HAS_EXTRA) == 0 { return -1; }
    return node_extra_get(p, id).captures;
}
inline fn set_node_captures(p: Program&, id: i64, value: i64) {
    if value == -1 && (p.nodes[id].flags & F_HAS_EXTRA) == 0 { return; }
    let index = node_extra_ensure(p, id);
    p.node_extras[index].captures = value as i32;
}
inline fn node_named_results(p: const Program&, id: i64) -> i32 {
    if (p.nodes[id].flags & F_HAS_EXTRA) == 0 { return -1; }
    return node_extra_get(p, id).named_results;
}
inline fn set_node_named_results(p: Program&, id: i64, value: i64) {
    if value == -1 && (p.nodes[id].flags & F_HAS_EXTRA) == 0 { return; }
    let index = node_extra_ensure(p, id);
    p.node_extras[index].named_results = value as i32;
}
inline fn node_coerced_type(p: const Program&, id: i64) -> i32 {
    if (p.nodes[id].flags & F_HAS_EXTRA) == 0 { return -1; }
    return node_extra_get(p, id).coerced_type;
}
inline fn set_node_coerced_type(p: Program&, id: i64, value: i64) {
    if value == -1 && (p.nodes[id].flags & F_HAS_EXTRA) == 0 { return; }
    let index = node_extra_ensure(p, id);
    p.node_extras[index].coerced_type = value as i32;
}
inline fn node_expansion_binding(p: const Program&, id: i64) -> i32 {
    if (p.nodes[id].flags & F_HAS_EXTRA) == 0 { return -1; }
    return node_extra_get(p, id).expansion_binding;
}
inline fn set_node_expansion_binding(p: Program&, id: i64, value: i64) {
    if value == -1 && (p.nodes[id].flags & F_HAS_EXTRA) == 0 { return; }
    let index = node_extra_ensure(p, id);
    p.node_extras[index].expansion_binding = value as i32;
}
// Most aux values are IDs or ordinals. Layout offsets and explicit
// padding counts may also exceed i32 on the native and memory64 targets.
let NODE_WIDE_AUX: i64 = -2147483648;
inline fn node_layout_aux(p: const Program&, id: i64, aux: i32) -> i64 {
    if aux != NODE_WIDE_AUX { return aux; }
    return node_extra_get(p, id).wide_aux;
}
inline fn set_node_layout_aux(p: Program&, id: i64, value: i64) {
    if value > NODE_WIDE_AUX && value <= 2147483647 { p.nodes[id].aux = value as i32; return; }
    let index = node_extra_ensure(p, id);
    p.node_extras[index].wide_aux = value;
    p.nodes[id].aux = NODE_WIDE_AUX as i32;
}

// This table only records synthetic spellings appended outside their source.
// Their legacy IR column is inherited from the token that they replace.
fn remember_token_column(p: Program&, at: i64) {
    let column = token_column(p, at);
    p.token_columns.push(TokenColumn { token: p.tokens.len as i32, column: column as i32 });
}
fn token_column(p: const Program&, token: i64) -> i64 {
    let t: const Token& = p.tokens[token];
    let source: const Source& = p.sources[t.source];
    if t.end > source.text_start + source.text_len {
        var low = 0; var high = p.token_columns.len;
        while low < high {
            let mid = (low + high) / 2;
            if p.token_columns[mid].token < token { low = mid + 1; }
            else { high = mid; }
        }
        if low < p.token_columns.len && p.token_columns[low].token == token { return p.token_columns[low].column; }
    }
    // The error token for an unclosed block comment used the EOF column.
    let start: i64 = if t.kind == T_EOF { t.end } else { t.start };
    var at = start;
    while at > source.text_start && p.text[at - 1] != 10 { at--; }
    return start - at + 1;
}

fn new_node(p: Program&, kind: i64, token: i64) -> i64 {
    let id = p.nodes.len;
    p.nodes.push(Node { kind: kind as i32, token: token as i32 });
    return id;
}
fn append_child(p: Program&, parent: i64, child: i64) {
    if child < 0 { return; }
    let pnode: Node& = p.nodes[parent];
    let tail = pnode.last;
    if tail < 0 { pnode.first = child as i32; }
    else { p.nodes[tail].next = child as i32; }
    var last = child;
    var nxt = p.nodes[last].next;
    while nxt >= 0 { last = nxt; nxt = p.nodes[last].next; }
    pnode.last = last as i32;
}
fn add_type(p: Program&, ty: Type) -> i64 {
    let id = p.types.len; p.types.push(ty); return id;
}
// Type lookups find the lowest type ID whose fields match, as a scan of the
// whole table would, through buckets hashed over kind, element, count, flags
// and, except for arrays, declaration. Chains keep ascending ID order.
// Types are indexed lazily, whoever appended them; a change to one of those
// fields of an existing type must be followed by type_reindex.
fn type_hash(kind: i64, element: i64, count: i64, flags: i64, declaration: i64) -> i64 {
    var h: u64 = 1469598103934665603;
    var d = declaration; if kind == TY_ARRAY { d = -1; }
    h = (h ^ (kind as! u64)) * 1099511628211; h ^= h >> 29;
    h = (h ^ (element as! u64)) * 1099511628211; h ^= h >> 29;
    h = (h ^ (count as! u64)) * 1099511628211; h ^= h >> 29;
    h = (h ^ (flags as! u64)) * 1099511628211; h ^= h >> 29;
    h = (h ^ (d as! u64)) * 1099511628211; h ^= h >> 29;
    return (h >> 1) as i64;
}
fn type_hash_of(p: Program&, id: i64) -> i64 {
    let t: const Type& = p.types[id];
    return type_hash(t.kind, t.element, t.count, t.flags, t.declaration);
}
fn type_link(p: Program&, id: i64) {
    let bucket = p.type_links[id].hash & (p.type_buckets.len - 1);
    p.type_links[id].next = -1;
    let tail = p.type_buckets[bucket].tail;
    if tail < 0 { p.type_buckets[bucket].head = id; p.type_buckets[bucket].tail = id; return; }
    if tail < id { p.type_links[tail].next = id; p.type_buckets[bucket].tail = id; return; }
    // A reindexed type goes back to its place in ID order.
    var previous = -1; var at = p.type_buckets[bucket].head;
    while at >= 0 && at < id { previous = at; at = p.type_links[at].next; }
    p.type_links[id].next = at;
    if previous < 0 { p.type_buckets[bucket].head = id; } else { p.type_links[previous].next = id; }
}
fn type_index_sync(p: Program&) {
    if p.type_indexed == p.types.len { return; }
    // At most one type per bucket on average.
    if p.type_buckets.len < p.types.len {
        var size: i64 = 1024; while size < 2 * p.types.len { size <<= 1; }
        p.type_buckets.clear(); p.type_buckets.resize(size, TypeBucket {});
        for id in 0..p.type_indexed { type_link(p, id); }
    }
    while p.type_indexed < p.types.len {
        let id = p.type_indexed;
        p.type_links.push(TypeLink { next: -1, hash: type_hash_of(p, id) });
        type_link(p, id); p.type_indexed += 1;
    }
}
// The first type that may have these fields; follow type_links[id].next.
fn type_find(p: Program&, kind: i64, element: i64, count: i64, flags: i64, declaration: i64) -> i64 {
    type_index_sync(p);
    return p.type_buckets[type_hash(kind, element, count, flags, declaration) & (p.type_buckets.len - 1)].head;
}
fn type_reindex(p: Program&, id: i64) {
    if id < 0 || id >= p.type_indexed { return; }
    let hash = type_hash_of(p, id);
    if hash == p.type_links[id].hash { return; }
    let bucket = p.type_links[id].hash & (p.type_buckets.len - 1);
    var previous = -1; var at = p.type_buckets[bucket].head;
    while at >= 0 && at != id { previous = at; at = p.type_links[at].next; }
    if previous < 0 { p.type_buckets[bucket].head = p.type_links[id].next; } else { p.type_links[previous].next = p.type_links[id].next; }
    if p.type_buckets[bucket].tail == id { p.type_buckets[bucket].tail = previous; }
    p.type_links[id].hash = hash; type_link(p, id);
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
