import model;
import wasm;

// Direct binary lowering of checked Goose. IDs are the only links between
// compiler tables; no table element is borrowed across recursive lowering.
// Host imports retain the public direct-backend ABI and its ordering.
let CG_WRITE: i64 = 0;
let CG_PRINT_I64: i64 = 1;
let CG_PRINT_U64: i64 = 2;
let CG_PRINT_F64: i64 = 3;
let CG_PRINT_F32: i64 = 4;
let CG_PRINT_BOOL: i64 = 5;
let CG_NEWLINE: i64 = 6;
let CG_ABORT: i64 = 7;
let CG_EXIT: i64 = 8;
struct CgSignature { start: i64, count: i64 }
struct CgImport { symbol: i64 = -1, signature: i64 = 0, host: i64 = -1 }
struct CgFunction {
    node: i64, symbol: i64, signature: i64 = -1, index: i64 = -1,
    closure_signature: i64 = -1, thunk: i64 = -1,
    capture_first: i64 = 0, capture_count: i64 = 0,
}
struct CgCapture { function: i64, symbol: i64 }
struct CgSegment { address: i64, start: i64, count: i64 }
struct CgModule {
    functions: CgFunction[>..]&, captures: CgCapture[>..]&, imports: CgImport[>..]&,
    signatures: CgSignature[>..]&, signature_bytes: u8[>..]&,
    segments: CgSegment[>..]&, data: u8[>..]&, globals: i64[>..]&,
    next_data: i64 = 1024, stack_limit: i64 = 0,
    start: i64 = -1, allocator: i64 = -1, float_wrap: i64 = -1, scalar: bool = false,
}
struct CgExit { label: i64, again: i64 = -1, node: i64 = -1, result: i64 = -1, type_id: i64 = 0 }
struct CgBody {
    code: u8[>..]&, locals: i64[>..]&, slots: i64[>..]&, offsets: i64[>..]&,
    labels: i64[>..]&, exits: CgExit[>..]&, results: i64[>..]&, destinations: i64[>..]&, work: i64[>..]&,
    function: i64 = -1, params: i64 = 0, serial: i64 = 0,
    frame: i64 = -1, frame_bytes: i64 = 0, effect: i64 = 0, done: i64 = -1, frame_free: bool = false,
}
fn cg_align(value: i64, alignment: i64) -> i64 {
    if alignment <= 1 { return value; }
    return (value + alignment - 1) & (0 - alignment);
}
fn cg_fail(p: Program&, node: i64, message: u8[:]) {
    var token = -1;
    if node >= 0 && node < p.nodes.len { token = p.nodes[node].token; }
    diagnose(p, token, message);
}
fn cg_type_kind(p: Program&, id: i64) -> i64 {
    if id < 0 || id >= p.types.len { return TY_UNKNOWN; }
    return p.types[id].kind;
}
fn cg_aggregate(p: Program&, id: i64) -> bool {
    let kind = cg_type_kind(p, id);
    return kind == TY_ARRAY || kind == TY_STRUCT || kind == TY_ENUM;
}
fn cg_owner(p: Program&, id: i64) -> bool {
    if cg_type_kind(p, id) != TY_ARRAY { return false; }
    let kind = p.types[id].array_kind;
    return kind == A_VAR || kind == A_GROW || kind == A_GROWSHRINK || kind == A_LIMITED && p.types[id].count < 0;
}
fn cg_unsigned(p: Program&, id: i64) -> bool {
    if cg_type_kind(p, id) == TY_BOOL || cg_type_kind(p, id) == TY_REF { return true; }
    if id < 0 || id >= p.types.len { return false; }
    return (p.types[id].flags & TF_UNSIGNED) != 0;
}
fn cg_wasm_type(p: Program&, id: i64) -> i64 {
    let kind = cg_type_kind(p, id);
    if kind == TY_VOID { return 0x40; }
    if kind == TY_INT && p.types[id].count == 64 || kind == TY_SLICE || kind == TY_FN { return 0x7e; }
    if kind == TY_FLOAT && p.types[id].count == 32 { return 0x7d; }
    if kind == TY_FLOAT { return 0x7c; }
    if kind == TY_UNKNOWN || kind == TY_GENERIC || kind == TY_NAME || kind == TY_TUPLE { return 0; }
    return 0x7f;
}
fn cg_size(p: Program&, id: i64) -> i64 {
    if id < 0 || id >= p.types.len { return 0; }
    if cg_owner(p, id) { return 24; }
    if p.types[id].kind == TY_FN { return 8; }
    return p.types[id].size;
}
fn cg_normalize(p: Program&, out: u8[>..]&, id: i64) {
    if cg_type_kind(p, id) == TY_BOOL { wb_byte(out, 0x45); wb_byte(out, 0x45); return; }
    if cg_type_kind(p, id) != TY_INT { return; }
    let width = p.types[id].count;
    if width == 8 {
        if cg_unsigned(p, id) { wb_i32(out, 255); wb_byte(out, 0x71); }
        else { wb_byte(out, 0xc0); }
    }
    if width == 16 {
        if cg_unsigned(p, id) { wb_i32(out, 65535); wb_byte(out, 0x71); }
        else { wb_byte(out, 0xc1); }
    }
}
fn cg_load_fixed(p: Program&, out: u8[>..]&, id: i64, offset: i64) -> bool {
    if cg_aggregate(p, id) { if offset != 0 { wb_i32(out, offset); wb_byte(out, 0x6a); } return true; }
    let kind = cg_type_kind(p, id);
    if kind == TY_INT {
        let bits = p.types[id].count;
        if bits == 8 { var op = 0x2c; if cg_unsigned(p, id) { op = 0x2d; } wb_mem(out, op, 0, offset); return true; }
        if bits == 16 { var op = 0x2e; if cg_unsigned(p, id) { op = 0x2f; } wb_mem(out, op, 1, offset); return true; }
    }
    let w = cg_wasm_type(p, id);
    if kind == TY_BOOL { wb_mem(out, 0x2d, 0, offset); return true; }
    if w == 0x7f { wb_mem(out, 0x28, 2, offset); return true; }
    if w == 0x7e { wb_mem(out, 0x29, 3, offset); return true; }
    if w == 0x7d { wb_mem(out, 0x2a, 2, offset); return true; }
    if w == 0x7c { wb_mem(out, 0x2b, 3, offset); return true; }
    return false;
}
fn cg_store(p: Program&, out: u8[>..]&, id: i64, offset: i64) -> bool {
    if cg_aggregate(p, id) || p.types[id].storage == 1 { return false; }
    let kind = cg_type_kind(p, id);
    if kind == TY_BOOL || kind == TY_INT && p.types[id].count == 8 { wb_mem(out, 0x3a, 0, offset); return true; }
    if kind == TY_INT && p.types[id].count == 16 { wb_mem(out, 0x3b, 1, offset); return true; }
    let w = cg_wasm_type(p, id);
    if w == 0x7f { wb_mem(out, 0x36, 2, offset); return true; }
    if w == 0x7e { wb_mem(out, 0x37, 3, offset); return true; }
    if w == 0x7d { wb_mem(out, 0x38, 2, offset); return true; }
    if w == 0x7c { wb_mem(out, 0x39, 3, offset); return true; }
    return false;
}
fn cg_local(f: CgBody&, wasm_type: i64) -> i64 {
    let index = f.params + f.locals.len;
    f.locals.push(wasm_type);
    return index;
}
fn cg_save(f: CgBody&, wasm_type: i64) -> i64 {
    let slot = cg_local(f, wasm_type); wb_op(f.code, 0x21, slot); return slot;
}
fn cg_get(f: CgBody&, slot: i64) { wb_op(f.code, 0x20, slot); }
fn cg_set(f: CgBody&, slot: i64) { wb_op(f.code, 0x21, slot); }
fn cg_begin(f: CgBody&, opcode: i64, result: i64) -> i64 {
    wb_byte(f.code, opcode); wb_byte(f.code, result);
    f.serial++; f.labels.push(f.serial); return f.serial;
}
fn cg_end(f: CgBody&) { wb_byte(f.code, 0x0b); f.labels.pop(); }
fn cg_branch(p: Program&, f: CgBody&, label: i64, conditional: bool) {
    var at = f.labels.len;
    while at > 0 {
        at--;
        if f.labels[at] == label {
            var opcode = 0x0c; if conditional { opcode = 0x0d; }
            wb_op(f.code, opcode, f.labels.len - at - 1); return;
        }
    }
    cg_fail(p, f.function, "wasm: branch target is outside this function");
}
fn cg_zero(out: u8[>..]&, wasm_type: i64) {
    if wasm_type == 0x7f { wb_i32(out, 0); }
    else if wasm_type == 0x7e { wb_i64(out, 0); }
    else if wasm_type == 0x7d { wb_f32(out, 0.0); }
    else if wasm_type == 0x7c { wb_f64(out, 0.0); }
}
fn cg_frame(f: CgBody&, bytes: i64, align: i64) -> i64 {
    f.frame_bytes = cg_align(f.frame_bytes, align);
    let offset = f.frame_bytes;
    f.frame_bytes += bytes;
    return offset;
}
fn cg_frame_address(f: CgBody&, offset: i64) {
    cg_get(f, f.frame);
    if offset != 0 { wb_i32(f.code, offset); wb_byte(f.code, 0x6a); }
}
fn cg_temporary(p: Program&, f: CgBody&, id: i64) -> i64 {
    var bytes = cg_size(p, id); if bytes < 1 { bytes = 1; }
    let offset = cg_frame(f, bytes, p.types[id].align);
    cg_frame_address(f, offset); return cg_save(f, 0x7f);
}
fn cg_signature(m: CgModule&, args: u8[:], results: u8[:]) -> i64 {
    var encoded: u8[>..] = [];
    wb_signature(encoded, args, results);
    for sig, i in m.signatures {
        if same_bytes(encoded, m.signature_bytes[sig.start..sig.start + sig.count]) { return i; }
    }
    let at = m.signature_bytes.len;
    m.signature_bytes.append(encoded);
    let result = m.signatures.len;
    m.signatures.push(CgSignature { start: at, count: encoded.len });
    return result;
}
fn cg_data(m: CgModule&, bytes: u8[:]) -> i64 {
    for segment in m.segments {
        if same_bytes(bytes, m.data[segment.start..segment.start + segment.count]) { return segment.address; }
    }
    let address = m.next_data;
    let at = m.data.len;
    m.data.append(bytes); m.next_data += bytes.len;
    m.segments.push(CgSegment { address: address, start: at, count: bytes.len });
    return address;
}
fn cg_text(m: CgModule&, f: CgBody&, text: u8[:]) {
    wb_i32(f.code, cg_data(m, text)); wb_i32(f.code, text.len); wb_op(f.code, 0x10, CG_WRITE);
}
fn cg_abort(p: Program&, m: CgModule&, f: CgBody&, node: i64, text: u8[:]) {
    wb_i32(f.code, cg_data(m, text)); wb_i32(f.code, text.len);
    var line = 0;
    if node >= 0 && p.nodes[node].token >= 0 { line = p.tokens[p.nodes[node].token].line; }
    wb_i32(f.code, line); wb_op(f.code, 0x10, CG_ABORT); wb_byte(f.code, 0);
}
fn cg_trap_if(p: Program&, m: CgModule&, f: CgBody&, node: i64, text: u8[:]) {
    cg_begin(f, 0x04, 0x40); cg_abort(p, m, f, node, text); cg_end(f);
}
fn cg_function(m: CgModule&, symbol: i64) -> i64 {
    for item, i in m.functions { if item.symbol == symbol { return i; } }
    return -1;
}
fn cg_capture(m: CgModule&, function: i64, symbol: i64) -> bool {
    for item in m.captures { if item.function == function && item.symbol == symbol { return true; } }
    return false;
}
recursive fn cg_scan_captures(p: Program&, m: CgModule&, function: i64, node: i64) {
    if node < 0 { return; }
    let n = p.nodes[node];
    if (n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE) && node != function { return; }
    if n.kind == N_NAME && n.symbol >= 0 {
        let s = p.symbols[n.symbol];
        if (s.flags & (S_FUNCTION | S_GLOBAL | S_TYPE | S_BUILTIN)) == 0 && s.owner >= 0 && s.owner != function && !cg_capture(m, function, n.symbol) {
            m.captures.push(CgCapture { function: function, symbol: n.symbol });
        }
    }
    cg_scan_captures(p, m, function, n.left); cg_scan_captures(p, m, function, n.right); cg_scan_captures(p, m, function, n.third);
    var child = n.first;
    while child >= 0 { cg_scan_captures(p, m, function, child); child = p.nodes[child].next; }
}
fn cg_result_types(p: Program&, id: i64, out: i64[>..]&) {
    let kind = cg_type_kind(p, id);
    if kind == TY_VOID { return; }
    if kind == TY_TUPLE {
        var part = p.types[id].first;
        while part >= 0 { out.push(p.nodes[part].type_id); part = p.nodes[part].next; }
        return;
    }
    out.push(id);
}
fn cg_function_results(p: Program&, function: i64, out: i64[>..]&) {
    let symbol = p.nodes[function].symbol;
    if symbol < 0 { return; }
    let type_id = p.symbols[symbol].type_id;
    if cg_type_kind(p, type_id) != TY_FN { cg_fail(p, function, "wasm: function has no checked signature"); return; }
    cg_result_types(p, p.types[type_id].element, out);
}
fn cg_make_signature(p: Program&, m: CgModule&, function: i64, closure: bool) -> i64 {
    var args: u8[>..] = []; var results: u8[>..] = []; var types: i64[>..] = [];
    if closure { args.push(0x7f); }
    var param = p.nodes[function].first;
    while param >= 0 { args.push(cg_wasm_type(p, p.nodes[param].type_id) as u8); param = p.nodes[param].next; }
    if !closure {
        for capture in m.captures { if capture.function == function { args.push(0x7f); } }
    }
    cg_function_results(p, function, types);
    for id in types {
        if cg_aggregate(p, id) { args.push(0x7f); }
        results.push(cg_wasm_type(p, id) as u8);
    }
    return cg_signature(m, args, results);
}
recursive fn cg_convert(p: Program&, m: CgModule&, f: CgBody&, from: i64, to: i64, node: i64) {
    if from == to { return; }
    if cg_type_kind(p, from) == TY_REF && (p.types[from].flags & TF_OPTIONAL) != 0 && cg_type_kind(p, to) == TY_BOOL {
        wb_byte(f.code, 0x45); wb_byte(f.code, 0x45); return;
    }
    if cg_type_kind(p, from) == TY_REF && cg_type_kind(p, to) != TY_REF {
        let pointee = p.types[from].element;
        if (p.types[from].flags & TF_OPTIONAL) != 0 { cg_fail(p, node, "wasm: optional reference must be narrowed before reading"); return; }
        cg_load(p, m, f, pointee, 0); cg_convert(p, m, f, pointee, to, node); return;
    }
    if cg_type_kind(p, from) == TY_STRUCT && cg_type_kind(p, to) == TY_ENUM && p.types[from].pool == to {
        let source = cg_save(f, 0x7f); let destination = cg_temporary(p, f, to);
        cg_get(f, destination); wb_i32(f.code, 0); wb_i32(f.code, cg_size(p, to)); wb_fill(f.code);
        cg_get(f, destination); wb_i32(f.code, p.nodes[p.types[from].declaration].integer);
        if p.types[to].length_storage == 2 { wb_mem(f.code, 0x3b, 0, 0); } else { wb_mem(f.code, 0x3a, 0, 0); }
        cg_get(f, destination); wb_i32(f.code, p.types[to].length_storage); wb_byte(f.code, 0x6a); let payload = cg_save(f, 0x7f);
        cg_copy(p, m, f, from, payload, source, node); cg_get(f, destination); return;
    }
    if cg_type_kind(p, to) == TY_ARRAY && (cg_type_kind(p, from) == TY_SLICE || cg_type_kind(p, from) == TY_ARRAY) && from != to {
        if cg_type_kind(p, from) == TY_ARRAY { cg_pack_view(p, m, f, from, node); }
        cg_array_from_view(p, m, f, to, node); return;
    }
    let a = cg_wasm_type(p, from); let b = cg_wasm_type(p, to);
    if cg_type_kind(p, to) == TY_BOOL {
        if a == 0x7f { wb_byte(f.code, 0x45); wb_byte(f.code, 0x45); }
        else if a == 0x7e { wb_byte(f.code, 0x50); wb_byte(f.code, 0x45); }
        else if a == 0x7d { wb_f32(f.code, 0.0); wb_byte(f.code, 0x5c); }
        else if a == 0x7c { wb_f64(f.code, 0.0); wb_byte(f.code, 0x62); }
        return;
    }
    if a == b { cg_normalize(p, f.code, to); return; }
    if a == 0x7f && b == 0x7e {
        var op = 0xac; if cg_unsigned(p, from) { op = 0xad; } wb_byte(f.code, op);
    } else if a == 0x7e && b == 0x7f { wb_byte(f.code, 0xa7); }
    else if a == 0x7d && b == 0x7c { wb_byte(f.code, 0xbb); }
    else if a == 0x7c && b == 0x7d { wb_byte(f.code, 0xb6); }
    else if (a == 0x7d || a == 0x7c) && (b == 0x7f || b == 0x7e) {
        if a == 0x7d { wb_byte(f.code, 0xbb); }
        wb_op(f.code, 0x10, m.float_wrap);
        if b == 0x7f { wb_byte(f.code, 0xa7); }
    } else if (a == 0x7f || a == 0x7e) && (b == 0x7d || b == 0x7c) {
        var opcode = 0xb2;
        if a == 0x7e { opcode = 0xb4; }
        if b == 0x7c { opcode += 5; }
        if cg_unsigned(p, from) { opcode++; }
        wb_byte(f.code, opcode);
    } else { cg_fail(p, node, "wasm: unsupported checked value conversion"); return; }
    cg_normalize(p, f.code, to);
}
fn cg_numeric_opcode(op: i64, w: i64, unsigned: bool) -> i64 {
    if w == 0x7d || w == 0x7c {
        var arithmetic = 0x92; var compare = 0x5b;
        if w == 0x7c { arithmetic = 0xa0; compare = 0x61; }
        if op == T_PLUS { return arithmetic; } if op == T_MINUS { return arithmetic + 1; }
        if op == T_MUL { return arithmetic + 2; } if op == T_DIV { return arithmetic + 3; }
        if op == T_EQ { return compare; } if op == T_NEQ { return compare + 1; }
        if op == T_LT { return compare + 2; } if op == T_GT { return compare + 3; }
        if op == T_LTEQ { return compare + 4; } if op == T_GTEQ { return compare + 5; }
        return 0;
    }
    var arithmetic = 0x6a; var compare = 0x46;
    if w == 0x7e { arithmetic = 0x7c; compare = 0x51; }
    var sign = 0; if unsigned { sign = 1; }
    if op == T_PLUS { return arithmetic; } if op == T_MINUS { return arithmetic + 1; }
    if op == T_MUL { return arithmetic + 2; } if op == T_DIV { return arithmetic + 3 + sign; }
    if op == T_MOD { return arithmetic + 5 + sign; } if op == T_BITAND { return arithmetic + 7; }
    if op == T_BITOR { return arithmetic + 8; } if op == T_XOR { return arithmetic + 9; }
    if op == T_SHL { return arithmetic + 10; } if op == T_SHR { return arithmetic + 11 + sign; }
    if op == T_EQ || op == T_DOTEQ { return compare; } if op == T_NEQ || op == T_DOTNEQ { return compare + 1; }
    if op == T_LT { return compare + 2 + sign; } if op == T_GT { return compare + 4 + sign; }
    if op == T_LTEQ { return compare + 6 + sign; } if op == T_GTEQ { return compare + 8 + sign; }
    return 0;
}
fn cg_static_prefix(p: Program&, id: i64) -> i64 {
    if p.types[id].array_kind != A_LIMITED || cg_owner(p, id) { return 0; }
    if p.types[id].count < 256 { return 1; }
    if p.types[id].count < 65536 { return 2; }
    if p.types[id].count <= 4294967295 { return 4; }
    return 8;
}
fn cg_length_load(p: Program&, f: CgBody&, id: i64) {
    let bytes = cg_static_prefix(p, id);
    if bytes == 1 { wb_mem(f.code, 0x2d, 0, 0); }
    else if bytes == 2 { wb_mem(f.code, 0x2f, 0, 0); }
    else if bytes == 4 { wb_mem(f.code, 0x28, 0, 0); }
    else { wb_mem(f.code, 0x29, 0, 0); wb_byte(f.code, 0xa7); }
}
fn cg_length_store(p: Program&, f: CgBody&, id: i64) {
    let bytes = cg_static_prefix(p, id);
    if bytes == 1 { wb_mem(f.code, 0x3a, 0, 0); }
    else if bytes == 2 { wb_mem(f.code, 0x3b, 0, 0); }
    else if bytes == 4 { wb_mem(f.code, 0x36, 0, 0); }
    else { wb_byte(f.code, 0xad); wb_mem(f.code, 0x37, 0, 0); }
}
recursive fn cg_pack_view(p: Program&, m: CgModule&, f: CgBody&, id: i64, node: i64) {
    if cg_type_kind(p, id) == TY_SLICE { return; }
    if cg_type_kind(p, id) == TY_REF { cg_load(p, m, f, p.types[id].element, 0); cg_pack_view(p, m, f, p.types[id].element, node); return; }
    if cg_type_kind(p, id) != TY_ARRAY { cg_fail(p, node, "wasm: expected an array or slice"); return; }
    let base = cg_save(f, 0x7f);
    if cg_owner(p, id) {
        cg_owner_read_base(p, m, f, base, node); wb_byte(f.code, 0xad);
        cg_owner_read_length(p, m, f, base, node); wb_byte(f.code, 0xad);
    } else {
        cg_get(f, base); let prefix = cg_static_prefix(p, id);
        if prefix != 0 { wb_i32(f.code, prefix); wb_byte(f.code, 0x6a); }
        wb_byte(f.code, 0xad);
        if p.types[id].array_kind == A_FIXED { wb_i64(f.code, p.types[id].count); }
        else { cg_get(f, base); cg_length_load(p, f, id); wb_byte(f.code, 0xad); }
    }
    wb_i64(f.code, 32); wb_byte(f.code, 0x86); wb_byte(f.code, 0x84);
}
fn cg_symbol_address(p: Program&, m: CgModule&, f: CgBody&, symbol: i64, node: i64) {
    if symbol < 0 || symbol >= p.symbols.len { cg_fail(p, node, "wasm: unresolved storage symbol"); return; }
    if (p.symbols[symbol].flags & S_GLOBAL) != 0 {
        if symbol >= m.globals.len || m.globals[symbol] < 0 { cg_fail(p, node, "wasm: global storage was not assigned"); return; }
        wb_i32(f.code, m.globals[symbol]); return;
    }
    if symbol >= f.slots.len || f.slots[symbol] < 0 { cg_fail(p, node, "wasm: local or capture storage was not assigned"); return; }
    cg_get(f, f.slots[symbol]);
}
recursive fn cg_address(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    if node < 0 { cg_fail(p, node, "wasm: missing assignment location"); return; }
    let n = p.nodes[node];
    if n.kind == N_NAME { cg_symbol_address(p, m, f, n.symbol, node); return; }
    if n.kind == N_UNARY && (n.integer == T_MUL || n.integer == T_XOR) { cg_expr(p, m, f, n.left); return; }
    if n.kind == N_MEMBER {
        if n.symbol < 0 || n.symbol >= p.nodes.len || p.nodes[n.symbol].kind != N_FIELD { cg_fail(p, node, "wasm: member does not identify a stored field"); return; }
        cg_expr(p, m, f, n.left);
        var object_type = p.nodes[n.left].type_id;
        if cg_type_kind(p, object_type) == TY_REF { object_type = p.types[object_type].element; cg_load(p, m, f, object_type, 0); }
        let offset = p.nodes[n.symbol].integer;
        if offset < 0 { cg_fail(p, node, "wasm: variable record field requires an encoded field walker"); return; }
        if offset != 0 { wb_i32(f.code, offset); wb_byte(f.code, 0x6a); }
        return;
    }
    if n.kind == N_INDEX {
        cg_expr(p, m, f, n.left); cg_pack_view(p, m, f, p.nodes[n.left].type_id, node);
        let view = cg_save(f, 0x7e);
        cg_to(p, m, f, n.right, TYPE_U64); let index = cg_save(f, 0x7e);
        if (n.flags & F_BOUNDS_PROVEN) == 0 {
            cg_get(f, index); cg_get(f, view); wb_i64(f.code, 32); wb_byte(f.code, 0x88); wb_byte(f.code, 0x5a);
            cg_trap_if(p, m, f, node, "array index out of bounds");
        }
        var id = p.nodes[n.left].type_id; if cg_type_kind(p, id) == TY_REF { id = p.types[id].element; }
        let element = p.types[id].element;
        if p.types[element].storage == 1 {
            cg_get(f, view); wb_byte(f.code, 0xa7); let base = cg_save(f, 0x7f);
            let cursor = cg_walk_elements(p, m, f, base, index, node); cg_get(f, cursor); return;
        }
        cg_get(f, view); wb_byte(f.code, 0xa7); cg_get(f, index); wb_byte(f.code, 0xa7);
        wb_i32(f.code, cg_size(p, element)); wb_byte(f.code, 0x6c); wb_byte(f.code, 0x6a); return;
    }
    cg_fail(p, node, "wasm: expression has no addressable storage");
}
recursive fn cg_copy(p: Program&, m: CgModule&, f: CgBody&, id: i64, destination: i64, source: i64, node: i64) {
    if !cg_aggregate(p, id) {
        cg_get(f, destination); cg_get(f, source); cg_load(p, m, f, id, 0); cg_store(p, f.code, id, 0); return;
    }
    if cg_owner(p, id) {
        cg_get(f, source); cg_pack_view(p, m, f, id, node); cg_array_from_view(p, m, f, id, node);
        let snapshot = cg_save(f, 0x7f); cg_get(f, destination); cg_get(f, snapshot); wb_i32(f.code, 24); wb_copy(f.code); return;
    }

    if cg_byte_record(p, id) { cg_fail(p, node, "wasm: byte-record copying requires packed image landing"); return; }
    // Fixed records and arrays are packed. Their checked offsets include all
    // explicit padding. Copy the complete image before repairing owner fields.
    cg_get(f, destination); cg_get(f, source); wb_i32(f.code, cg_size(p, id)); wb_copy(f.code);
    if cg_type_kind(p, id) == TY_STRUCT {
        let declaration = p.types[id].declaration;
        var field = p.nodes[declaration].first;
        while field >= 0 {
            let type_id = p.nodes[field].type_id;
            if cg_aggregate(p, type_id) {
                cg_get(f, destination); wb_i32(f.code, p.nodes[field].integer); wb_byte(f.code, 0x6a); let dst = cg_save(f, 0x7f);
                cg_get(f, source); wb_i32(f.code, p.nodes[field].integer); wb_byte(f.code, 0x6a); let src = cg_save(f, 0x7f);
                cg_copy(p, m, f, type_id, dst, src, node);
            }
            field = p.nodes[field].next;
        }
    }
}
recursive fn cg_write_value(p: Program&, m: CgModule&, f: CgBody&, id: i64, destination: i64, node: i64) {
    let value = cg_save(f, cg_wasm_type(p, id));
    if cg_aggregate(p, id) { cg_copy(p, m, f, id, destination, value, node); return; }
    cg_get(f, destination); cg_get(f, value);
    if !cg_store(p, f.code, id, 0) { cg_fail(p, node, "wasm: unsupported stored value type"); }
}
recursive fn cg_to(p: Program&, m: CgModule&, f: CgBody&, node: i64, id: i64) {
    if node < 0 { cg_fail(p, node, "wasm: missing value expression"); return; }
    let from = p.nodes[node].type_id;
    if cg_type_kind(p, id) == TY_REF && cg_type_kind(p, from) != TY_REF {
        cg_address(p, m, f, node); return;
    }
    cg_expr(p, m, f, node);
    if cg_type_kind(p, from) == TY_ARRAY && cg_type_kind(p, id) == TY_SLICE { cg_pack_view(p, m, f, from, node); return; }
    cg_convert(p, m, f, from, id, node);
}
recursive fn cg_truth(p: Program&, m: CgModule&, f: CgBody&, node: i64) { cg_to(p, m, f, node, TYPE_BOOL); }
fn cg_drop_type(p: Program&, f: CgBody&, id: i64) {
    var types: i64[>..] = []; cg_result_types(p, id, types);
    for item in types { wb_byte(f.code, 0x1a); }
}
recursive fn cg_discard(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    if node < 0 { return; } cg_expr(p, m, f, node); cg_drop_type(p, f, p.nodes[node].type_id);
}
recursive fn cg_binary(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n = p.nodes[node]; let op = n.integer;
    if op == T_ANDAND || op == T_OROR {
        cg_truth(p, m, f, n.left); cg_begin(f, 0x04, 0x7f);
        if op == T_ANDAND { cg_truth(p, m, f, n.right); } else { wb_i32(f.code, 1); }
        wb_byte(f.code, 0x05);
        if op == T_OROR { cg_truth(p, m, f, n.right); } else { wb_i32(f.code, 0); }
        cg_end(f); return;
    }
    if (op == T_EQ || op == T_NEQ) && (p.nodes[n.left].kind == N_NULL || p.nodes[n.right].kind == N_NULL) {
        cg_expr(p, m, f, n.left); cg_expr(p, m, f, n.right);
        wb_byte(f.code, cg_numeric_opcode(op, 0x7f, true)); return;
    }
    var id = p.nodes[n.left].type_id;
    if cg_type_kind(p, id) == TY_REF && op != T_DOTEQ && op != T_DOTNEQ { id = p.types[id].element; }
    cg_to(p, m, f, n.left, id); cg_to(p, m, f, n.right, id);
    cg_numeric(p, m, f, op, id, node);
    if cg_type_kind(p, n.type_id) != TY_BOOL { cg_convert(p, m, f, id, n.type_id, node); }

}
fn cg_float_remainder(p: Program&, m: CgModule&, f: CgBody&, node: i64, w: i64) {
    let divisor = cg_save(f, w); let original = cg_save(f, w);
    cg_get(f, divisor); var abs_op = 0x8b; var mul_op = 0x94; var div_op = 0x95; var sub_op = 0x93; var copy_sign = 0x98;
    if w == 0x7c { abs_op = 0x99; mul_op = 0xa2; div_op = 0xa3; sub_op = 0xa1; copy_sign = 0xa6; }
    wb_byte(f.code, abs_op); let magnitude = cg_save(f, w);
    cg_get(f, original); wb_byte(f.code, abs_op); let value = cg_save(f, w);
    cg_get(f, magnitude); cg_zero(f.code, w); wb_byte(f.code, cg_numeric_opcode(T_EQ, w, false));
    cg_get(f, value); cg_get(f, value); wb_byte(f.code, cg_numeric_opcode(T_NEQ, w, false)); wb_byte(f.code, 0x72);
    cg_get(f, magnitude); cg_get(f, magnitude); wb_byte(f.code, cg_numeric_opcode(T_NEQ, w, false)); wb_byte(f.code, 0x72);
    cg_get(f, value); if w == 0x7d { wb_f32(f.code, 3.4028234663852886e38); } else { wb_f64(f.code, 1.7976931348623157e308); }
    wb_byte(f.code, cg_numeric_opcode(T_GT, w, false)); wb_byte(f.code, 0x72);
    cg_begin(f, 0x04, w); cg_zero(f.code, w); cg_zero(f.code, w); wb_byte(f.code, div_op);
    wb_byte(f.code, 0x05);
    let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
    cg_get(f, value); cg_get(f, magnitude); wb_byte(f.code, cg_numeric_opcode(T_GTEQ, w, false)); wb_byte(f.code, 0x45); cg_branch(p, f, done, true);
    cg_get(f, magnitude); let scale = cg_save(f, w);
    let scaled = cg_begin(f, 0x02, 0x40); let scaling = cg_begin(f, 0x03, 0x40);
    cg_get(f, scale); cg_get(f, value); if w == 0x7d { wb_f32(f.code, 2.0); } else { wb_f64(f.code, 2.0); }
    wb_byte(f.code, div_op); wb_byte(f.code, cg_numeric_opcode(T_GT, w, false)); cg_branch(p, f, scaled, true);
    cg_get(f, scale); if w == 0x7d { wb_f32(f.code, 2.0); } else { wb_f64(f.code, 2.0); }
    wb_byte(f.code, mul_op); cg_set(f, scale); cg_branch(p, f, scaling, false); cg_end(f); cg_end(f);
    cg_get(f, value); cg_get(f, scale); wb_byte(f.code, sub_op); cg_set(f, value); cg_branch(p, f, again, false); cg_end(f); cg_end(f);
    cg_get(f, value); cg_get(f, original); wb_byte(f.code, copy_sign); cg_end(f);
}
fn cg_effect_check(p: Program&, m: CgModule&, f: CgBody&, types: i64[:]) {
    var saved: i64[>..] = [];
    for id in types { saved.push(cg_local(f, cg_wasm_type(p, id))); }
    var at = saved.len;
    while at > 0 { at--; cg_set(f, saved[at]); }
    wb_op(f.code, 0x23, 2); cg_branch(p, f, f.done, true);
    for slot in saved { cg_get(f, slot); }
}
fn cg_intrinsic(p: Program&, function: i64) -> i64 {
    if (p.nodes[function].flags & F_EXTERN) == 0 { return 0; }
    var parameter = p.nodes[function].first;
    if parameter < 0 || p.nodes[parameter].next >= 0 { return 0; }
    let id = p.nodes[parameter].type_id; let w = cg_wasm_type(p, id);
    var name = token_text(p, p.nodes[function].token);
    if p.nodes[function].integer >= 0 && p.nodes[function].integer < p.tokens.len && p.tokens[p.nodes[function].integer].kind == T_STRLIT {
        let token = p.tokens[p.nodes[function].integer]; name = p.text[token.text_start..token.text_start + token.text_len];
    }
    if same_bytes(name, "gs_clz") && id == TYPE_U64 { return 0x79; }
    if w == 0x7d {
        if same_bytes(name, "sqrtf") || same_bytes(name, "gs_sqrtf") { return 0x91; }
        if same_bytes(name, "ceilf") { return 0x8d; } if same_bytes(name, "floorf") { return 0x8e; }
        if same_bytes(name, "truncf") { return 0x8f; } if same_bytes(name, "fabsf") { return 0x8b; }
    }
    if w == 0x7c {
        if same_bytes(name, "sqrt") || same_bytes(name, "gs_sqrt") { return 0x9f; }
        if same_bytes(name, "ceil") { return 0x9b; } if same_bytes(name, "floor") { return 0x9c; }
        if same_bytes(name, "trunc") { return 0x9d; } if same_bytes(name, "fabs") { return 0x99; }
    }
    return 0;
}
fn cg_closure(p: Program&, m: CgModule&, f: CgBody&, symbol: i64, node: i64) {
    let index = cg_function(m, symbol);
    if index < 0 { cg_fail(p, node, "wasm: function value has no concrete function"); return; }
    let item = m.functions[index];
    let offset = cg_frame(f, item.capture_count * 4, 4); cg_frame_address(f, offset); let environment = cg_save(f, 0x7f);
    var ordinal = 0;
    for capture in m.captures {
        if capture.function == item.node {
            cg_get(f, environment); cg_symbol_address(p, m, f, capture.symbol, node); wb_mem(f.code, 0x36, 2, ordinal * 4); ordinal++;
        }
    }
    wb_i64(f.code, index); cg_get(f, environment); wb_byte(f.code, 0xad); wb_i64(f.code, 32); wb_byte(f.code, 0x86); wb_byte(f.code, 0x84);
}
recursive fn cg_call(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n = p.nodes[node];
    if n.symbol >= 0 && (p.symbols[n.symbol].flags & S_BUILTIN) != 0 { cg_builtin(p, m, f, node, p.symbols[n.symbol].index); return; }
    var function = -1; var index = -1; var closure = -1;
    if n.symbol >= 0 && (p.symbols[n.symbol].flags & S_FUNCTION) != 0 {
        function = p.symbols[n.symbol].node; index = cg_function(m, n.symbol);
    }
    var callable_type = -1;
    if function < 0 {
        cg_expr(p, m, f, n.left); closure = cg_save(f, 0x7e); callable_type = p.nodes[n.left].type_id;
        if cg_type_kind(p, callable_type) != TY_FN { cg_fail(p, node, "wasm: indirect callee is not a function value"); return; }
    }
    var param = -1; var return_id = TYPE_VOID;
    if function >= 0 {
        param = p.nodes[function].first; let type_id = p.symbols[n.symbol].type_id;
        if cg_type_kind(p, type_id) == TY_FN { return_id = p.types[type_id].element; }
    } else {
        param = p.types[callable_type].first; return_id = p.types[callable_type].element;
        cg_get(f, closure); wb_i64(f.code, 32); wb_byte(f.code, 0x88); wb_byte(f.code, 0xa7);
    }
    var arg = n.first;
    while param >= 0 && arg >= 0 {
        let id = p.nodes[param].type_id; cg_to(p, m, f, arg, id);
        if cg_aggregate(p, id) {
            let source = cg_save(f, 0x7f); let snapshot = cg_temporary(p, f, id);
            cg_copy(p, m, f, id, snapshot, source, arg); cg_get(f, snapshot);
        }
        param = p.nodes[param].next; arg = p.nodes[arg].next;
    }
    if arg >= 0 || param >= 0 { cg_fail(p, node, "wasm: checked call argument arity mismatch"); return; }
    if function >= 0 {
        for capture in m.captures { if capture.function == function { cg_symbol_address(p, m, f, capture.symbol, node); } }
    }
    var results: i64[>..] = []; cg_result_types(p, return_id, results);
    for id in results { if cg_aggregate(p, id) { cg_get(f, cg_temporary(p, f, id)); } }
    if function >= 0 {
        let opcode = cg_intrinsic(p, function);
        if opcode != 0 { wb_byte(f.code, opcode); }
        else {
            var target = -1;
            if index >= 0 { target = m.functions[index].index; }
            else { for item, i in m.imports { if item.symbol == n.symbol { target = i; } } }
            if target < 0 { cg_fail(p, node, "wasm: call has no emitted function or import"); return; }
            wb_op(f.code, 0x10, target);
        }
    } else {
        var args: u8[>..] = [0x7f]; var returns: u8[>..] = [];
        param = p.types[callable_type].first;
        while param >= 0 { args.push(cg_wasm_type(p, p.nodes[param].type_id) as u8); param = p.nodes[param].next; }
        for id in results { if cg_aggregate(p, id) { args.push(0x7f); } returns.push(cg_wasm_type(p, id) as u8); }
        cg_get(f, closure); wb_byte(f.code, 0xa7); wb_op(f.code, 0x11, cg_signature(m, args, returns)); wb_u(f.code, 0);
    }
    cg_effect_check(p, m, f, results);
    if results.len == 1 && n.type_id != results[0] { cg_convert(p, m, f, results[0], n.type_id, node); }
}
recursive fn cg_array_literal(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n = p.nodes[node]; let id = n.type_id; let element = p.types[id].element;
    let destination = cg_temporary(p, f, id);
    cg_get(f, destination); wb_i32(f.code, 0); wb_i32(f.code, cg_size(p, id)); wb_fill(f.code);
    var count = 0; var child = n.first;
    while child >= 0 { count++; child = p.nodes[child].next; }
    var count_local = -1;
    if n.right >= 0 { cg_to(p, m, f, n.right, TYPE_U32); count_local = cg_save(f, 0x7f); }
    else { wb_i32(f.code, count); count_local = cg_save(f, 0x7f); }
    var base = destination;
    if cg_owner(p, id) {
        var capacity = count_local;
        if n.third >= 0 { cg_to(p, m, f, n.third, TYPE_U32); capacity = cg_save(f, 0x7f); cg_get(f, count_local); cg_get(f, capacity); wb_byte(f.code, 0x4b); cg_trap_if(p, m, f, node, "array capacity exceeded"); }
        base = cg_owner_image(p, m, f, id, destination, count_local, capacity, node);
    } else {
        cg_get(f, count_local); wb_i32(f.code, p.types[id].count); wb_byte(f.code, 0x4b); cg_trap_if(p, m, f, node, "array capacity exceeded");
        if p.types[id].array_kind == A_LIMITED {
            cg_get(f, destination); cg_get(f, count_local); cg_length_store(p, f, id);
            cg_get(f, destination); wb_i32(f.code, cg_static_prefix(p, id)); wb_byte(f.code, 0x6a); base = cg_save(f, 0x7f);
        }
    }
    if p.types[element].storage == 1 { cg_encoded_array_initializers(p, m, f, node, destination, base, count_local); cg_get(f, destination); return; }
    if n.right >= 0 && n.first >= 0 {
        cg_to(p, m, f, n.first, element); let value = cg_save(f, cg_wasm_type(p, element));
        wb_i32(f.code, 0); let counter = cg_save(f, 0x7f);
        let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
        cg_get(f, counter); cg_get(f, count_local); wb_byte(f.code, 0x4f); cg_branch(p, f, done, true);
        cg_get(f, base); cg_get(f, counter); wb_i32(f.code, cg_size(p, element)); wb_byte(f.code, 0x6c); wb_byte(f.code, 0x6a); let address = cg_save(f, 0x7f);
        cg_get(f, value); cg_write_value(p, m, f, element, address, node);
        cg_get(f, counter); wb_i32(f.code, 1); wb_byte(f.code, 0x6a); cg_set(f, counter); cg_branch(p, f, again, false); cg_end(f); cg_end(f);
    } else {
        child = n.first; var ordinal = 0;
        while child >= 0 {
            cg_get(f, base); wb_i32(f.code, ordinal * cg_size(p, element)); wb_byte(f.code, 0x6a); let address = cg_save(f, 0x7f);
            cg_to(p, m, f, child, element); cg_write_value(p, m, f, element, address, child);
            child = p.nodes[child].next; ordinal++;
        }
    }
    cg_get(f, destination);
}
recursive fn cg_record_literal(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n = p.nodes[node]; let id = n.type_id; let destination = cg_temporary(p, f, id);
    cg_get(f, destination); wb_i32(f.code, 0); wb_i32(f.code, cg_size(p, id)); wb_fill(f.code);
    if cg_type_kind(p, id) == TY_ENUM && n.symbol >= 0 {
        cg_get(f, destination); wb_i32(f.code, p.nodes[n.symbol].integer);
        if p.types[id].prefix == 2 { wb_mem(f.code, 0x3b, 0, 0); } else { wb_mem(f.code, 0x3a, 0, 0); }
    }
    var binding = n.first;
    while binding >= 0 {
        let field = p.nodes[binding].symbol;
        if field < 0 || field >= p.nodes.len { cg_fail(p, binding, "wasm: record initializer has no resolved field"); return; }
        let initializer = p.nodes[binding].right;
        if p.nodes[field].integer < 0 { cg_fail(p, binding, "wasm: byte-record construction requires sequential image packing"); return; }
        cg_get(f, destination); wb_i32(f.code, p.nodes[field].integer); wb_byte(f.code, 0x6a); let address = cg_save(f, 0x7f);
        if initializer >= 0 { cg_to(p, m, f, initializer, p.nodes[field].type_id); cg_write_value(p, m, f, p.nodes[field].type_id, address, binding); }
        binding = p.nodes[binding].next;
    }
    cg_get(f, destination);
}
recursive fn cg_set_values(p: Program&, m: CgModule&, f: CgBody&, first: i64, type_id: i64, first_slot: i64, node: i64) {
    let count = cg_result_count(p, type_id);
    if count == 0 { if first >= 0 { cg_discard(p, m, f, first); } return; }
    if first < 0 { cg_fail(p, node, "wasm: missing control result"); return; }
    if p.nodes[first].next < 0 && cg_type_kind(p, p.nodes[first].type_id) == TY_TUPLE {
        cg_expr(p, m, f, first); var at = count;
        while at > 0 { at--; cg_set(f, first_slot + at); } return;
    }
    var item = first; var ordinal = 0;
    while item >= 0 && ordinal < count {
        cg_to(p, m, f, item, cg_result_at(p, type_id, ordinal)); cg_set(f, first_slot + ordinal);
        item = p.nodes[item].next; ordinal++;
    }
    if item >= 0 || ordinal != count { cg_fail(p, node, "wasm: control result arity mismatch"); }
}
fn cg_result_type(p: Program&, function: i64) -> i64 {
    if function < 0 { return TYPE_VOID; }
    let symbol = p.nodes[function].symbol;
    if symbol < 0 { return TYPE_VOID; }
    return p.types[p.symbols[symbol].type_id].element;
}
recursive fn cg_emit_return(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n = p.nodes[node]; var target = f.function;
    if n.symbol >= 0 && n.symbol < p.symbols.len && (p.symbols[n.symbol].flags & S_FUNCTION) != 0 { target = p.symbols[n.symbol].node; }
    if target == f.function {
        var first_slot = -1; if f.results.len > 0 { first_slot = f.results[0]; }
        cg_set_values(p, m, f, n.first, cg_result_type(p, f.function), first_slot, node);
        cg_branch(p, f, f.done, false); return;
    }
    let target_type = cg_result_type(p, target); let count = cg_result_count(p, target_type);
    let first_slot = cg_control_slots(p, f, target_type);
    cg_set_values(p, m, f, n.first, target_type, first_slot, node);
    wb_op(f.code, 0x23, 4); let frame = cg_save(f, 0x7f);
    let found = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
    cg_get(f, frame); wb_byte(f.code, 0x45); cg_trap_if(p, m, f, node, "nonlocal return target is no longer active");
    cg_get(f, frame); wb_mem(f.code, 0x28, 2, 4); wb_i32(f.code, target + 1); wb_byte(f.code, 0x46); cg_branch(p, f, found, true);
    cg_get(f, frame); wb_mem(f.code, 0x28, 2, 0); cg_set(f, frame); cg_branch(p, f, again, false); cg_end(f); cg_end(f);
    var offset = 16;
    for i in 0..count {
        let id = cg_result_at(p, target_type, i);
        offset = cg_align(offset, 8); cg_get(f, frame); wb_i32(f.code, offset); wb_byte(f.code, 0x6a); let destination = cg_save(f, 0x7f);
        cg_get(f, first_slot + i); cg_write_value(p, m, f, id, destination, node);
        offset += cg_size(p, id);
    }
    cg_get(f, frame); wb_op(f.code, 0x24, 2); cg_branch(p, f, f.done, false);
}
fn cg_assignment_operator(op: i64) -> i64 {
    if op == T_PLUSEQ || op == T_INC { return T_PLUS; } if op == T_MINUSEQ || op == T_DEC { return T_MINUS; }
    if op == T_MULEQ { return T_MUL; } if op == T_DIVEQ { return T_DIV; } if op == T_MODEQ { return T_MOD; }
    if op == T_ANDEQ { return T_BITAND; } if op == T_OREQ { return T_BITOR; } if op == T_XOREQ { return T_XOR; }
    if op == T_SHLEQ { return T_SHL; } if op == T_SHREQ { return T_SHR; } return op;
}
recursive fn cg_assign(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n = p.nodes[node]; var id = p.nodes[n.left].type_id;
    if cg_type_kind(p, id) == TY_REF && n.integer != T_DOTASSIGN { cg_expr(p, m, f, n.left); id = p.types[id].element; }
    else { cg_address(p, m, f, n.left); }
    let address = cg_save(f, 0x7f);
    if n.integer != T_ASSIGN && n.integer != T_DOTASSIGN {
        cg_get(f, address); cg_load(p, m, f, id, 0);
        if n.integer == T_INC || n.integer == T_DEC {
            let w = cg_wasm_type(p, id);
            if w == 0x7d { wb_f32(f.code, 1.0); } else if w == 0x7c { wb_f64(f.code, 1.0); }
            else if w == 0x7e { wb_i64(f.code, 1); } else { wb_i32(f.code, 1); }
        } else { cg_to(p, m, f, n.right, id); }
        cg_numeric(p, m, f, cg_assignment_operator(n.integer), id, node);
    } else { cg_to(p, m, f, n.right, id); }
    if p.types[id].storage == 1 { cg_fail(p, node, "wasm: encoded element replacement requires a size-preserving image edit"); return; }
    cg_write_value(p, m, f, id, address, node);
}
recursive fn cg_declaration(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n = p.nodes[node];
    if n.first >= 0 {
        var binding = n.first; var first_slot = -1; var count = 0;
        while binding >= 0 {
            let slot = cg_local(f, cg_wasm_type(p, p.nodes[binding].type_id));
            if first_slot < 0 { first_slot = slot; } count++; binding = p.nodes[binding].next;
        }
        if n.right >= 0 && cg_type_kind(p, p.nodes[n.right].type_id) == TY_TUPLE {
            cg_expr(p, m, f, n.right); var at = count; while at > 0 { at--; cg_set(f, first_slot + at); }
        } else {
            var initializer = n.right; binding = n.first; var ordinal = 0;
            while binding >= 0 {
                if initializer >= 0 { cg_to(p, m, f, initializer, p.nodes[binding].type_id); initializer = p.nodes[initializer].next; }
                else { cg_zero(f.code, cg_wasm_type(p, p.nodes[binding].type_id)); }
                cg_set(f, first_slot + ordinal); ordinal++; binding = p.nodes[binding].next;
            }
        }
        binding = n.first; var ordinal = 0;
        while binding >= 0 {
            cg_symbol_address(p, m, f, p.nodes[binding].symbol, binding); let address = cg_save(f, 0x7f);
            if n.right < 0 { cg_get(f, address); wb_i32(f.code, 0); wb_i32(f.code, cg_size(p, p.nodes[binding].type_id)); wb_fill(f.code); }
            else { cg_get(f, first_slot + ordinal); cg_write_value(p, m, f, p.nodes[binding].type_id, address, binding); }
            binding = p.nodes[binding].next; ordinal++;
        }
        return;
    }
    let symbol = n.symbol;
    if symbol < 0 { cg_fail(p, node, "wasm: declaration has no symbol"); return; }
    cg_symbol_address(p, m, f, symbol, node); let address = cg_save(f, 0x7f);
    if n.right < 0 {
        cg_get(f, address); wb_i32(f.code, 0); wb_i32(f.code, cg_size(p, n.type_id)); wb_fill(f.code); return;
    }
    cg_to(p, m, f, n.right, n.type_id); cg_write_value(p, m, f, n.type_id, address, node);
}
recursive fn cg_break(p: Program&, m: CgModule&, f: CgBody&, node: i64, continuing: bool) {
    let n = p.nodes[node]; var at = f.exits.len;
    while at > 0 {
        at--; let exit = f.exits[at];
        if n.symbol >= 0 && exit.node != n.symbol { continue; }
        if continuing {
            if exit.again < 0 { continue; } cg_branch(p, f, exit.again, false); return;
        }
        if n.left >= 0 { cg_set_values(p, m, f, n.left, exit.type_id, exit.result, node); }
        cg_branch(p, f, exit.label, false); return;
    }
    cg_fail(p, node, "wasm: loop or block exit has no active target");
}
recursive fn cg_block_into(p: Program&, m: CgModule&, f: CgBody&, node: i64, id: i64, result: i64) {
    if node < 0 { return; }
    if p.nodes[node].kind != N_BLOCK {
        if cg_type_kind(p, p.nodes[node].type_id) == TY_VOID { cg_discard(p, m, f, node); }
        else { cg_set_values(p, m, f, node, id, result, node); }
        return;
    }
    let n = p.nodes[node]; var child = n.first;
    while child >= 0 {
        let item = p.nodes[child];
        if item.kind == N_EXPR_STMT && (item.flags & (F_TAIL | F_IMPLICIT_RETURN)) != 0 {
            if id == TYPE_VOID { cg_discard(p, m, f, item.left); }
            else { cg_set_values(p, m, f, item.left, id, result, child); }
        } else if item.next < 0 && (item.flags & F_TAIL) != 0 && item.kind != N_RETURN && item.kind != N_BREAK && item.kind != N_CONTINUE {
            if id == TYPE_VOID { cg_discard(p, m, f, child); } else { cg_set_values(p, m, f, child, id, result, child); }
        } else { cg_statement(p, m, f, child); }
        child = item.next;
    }
    if n.right >= 0 {
        if id == TYPE_VOID { cg_discard(p, m, f, n.right); } else { cg_set_values(p, m, f, n.right, id, result, node); }
    }
}
fn cg_control_slots(p: Program&, f: CgBody&, id: i64) -> i64 {
    var types: i64[>..] = []; cg_result_types(p, id, types); var first = -1;
    for type_id in types { let slot = cg_local(f, cg_wasm_type(p, type_id)); if first < 0 { first = slot; } }
    return first;
}
fn cg_control_get(p: Program&, f: CgBody&, id: i64, first: i64) {
    var types: i64[>..] = []; cg_result_types(p, id, types); for item, i in types { cg_get(f, first + i); }
}
recursive fn cg_loop(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n = p.nodes[node]; let result = cg_control_slots(p, f, n.type_id);
    let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
    if n.kind == N_WHILE { cg_truth(p, m, f, n.left); wb_byte(f.code, 0x45); cg_branch(p, f, done, true); }
    f.exits.push(CgExit { label: done, again: again, node: node, result: result, type_id: n.type_id });
    cg_block_into(p, m, f, n.right, TYPE_VOID, -1); f.exits.pop(); cg_branch(p, f, again, false);
    cg_end(f); cg_end(f); cg_control_get(p, f, n.type_id, result);
}
recursive fn cg_replayable(p: Program&, node: i64) -> bool {
    if node < 0 { return true; } let n = p.nodes[node];
    if n.kind == N_NAME || n.kind == N_INTEGER { return true; }
    if n.kind == N_MEMBER || n.kind == N_UNARY { return cg_replayable(p, n.left); }
    if n.kind == N_INDEX { return cg_replayable(p, n.left) && cg_replayable(p, n.right); }
    return false;
}
recursive fn cg_for(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n = p.nodes[node]; let iterable = p.nodes[n.left]; var type_id = iterable.type_id;
    if cg_type_kind(p, type_id) == TY_REF { type_id = p.types[type_id].element; }
    let sequence = cg_type_kind(p, type_id) == TY_ARRAY || cg_type_kind(p, type_id) == TY_SLICE;
    var binding = n.first; if binding < 0 { cg_fail(p, node, "wasm: for loop has no binding"); return; }
    let element_binding = p.nodes[binding].symbol; binding = p.nodes[binding].next;
    var ordinal_binding = -1; if binding >= 0 { ordinal_binding = p.nodes[binding].symbol; }
    var counter_type = type_id; if sequence { counter_type = TYPE_U64; }
    var view = -1;
    if sequence {
        cg_expr(p, m, f, n.left); cg_pack_view(p, m, f, iterable.type_id, node); view = cg_save(f, 0x7e); wb_i64(f.code, 0);
    } else if iterable.kind == N_RANGE { cg_to(p, m, f, iterable.left, counter_type); }
    else { cg_zero(f.code, cg_wasm_type(p, counter_type)); }
    let counter = cg_save(f, cg_wasm_type(p, counter_type));
    if sequence { cg_get(f, view); wb_i64(f.code, 32); wb_byte(f.code, 0x88); }
    else if iterable.kind == N_RANGE { cg_to(p, m, f, iterable.right, counter_type); }
    else { cg_to(p, m, f, n.left, counter_type); }
    let limit = cg_save(f, cg_wasm_type(p, counter_type)); wb_i64(f.code, 0); let ordinal = cg_save(f, 0x7e);
    let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
    if sequence && cg_replayable(p, n.left) {
        cg_expr(p, m, f, n.left); cg_pack_view(p, m, f, iterable.type_id, node); cg_set(f, view);
        cg_get(f, view); wb_i64(f.code, 32); wb_byte(f.code, 0x88); cg_set(f, limit);
    }
    cg_get(f, counter); cg_get(f, limit); var comparison = T_GTEQ;
    if iterable.kind == N_RANGE && (iterable.flags & F_INCLUSIVE) != 0 { comparison = T_GT; }
    wb_byte(f.code, cg_numeric_opcode(comparison, cg_wasm_type(p, counter_type), cg_unsigned(p, counter_type))); cg_branch(p, f, done, true);
    cg_symbol_address(p, m, f, element_binding, node); let place = cg_save(f, 0x7f);
    let binding_type = p.symbols[element_binding].type_id;
    if sequence {
        let element = p.types[type_id].element;
        cg_get(f, view); wb_byte(f.code, 0xa7); let sequence_base = cg_save(f, 0x7f);
        if p.types[element].storage == 1 { let cursor = cg_walk_elements(p, m, f, sequence_base, counter, node); cg_get(f, cursor); }
        else { cg_get(f, sequence_base); cg_get(f, counter); wb_byte(f.code, 0xa7); wb_i32(f.code, cg_size(p, element)); wb_byte(f.code, 0x6c); wb_byte(f.code, 0x6a); }
        if cg_type_kind(p, binding_type) != TY_REF || cg_type_kind(p, element) == TY_REF { cg_load(p, m, f, element, 0); cg_convert(p, m, f, element, binding_type, node); }
    } else { cg_get(f, counter); cg_convert(p, m, f, counter_type, binding_type, node); }
    cg_write_value(p, m, f, binding_type, place, node);
    if ordinal_binding >= 0 {
        cg_symbol_address(p, m, f, ordinal_binding, node); let destination = cg_save(f, 0x7f);
        cg_get(f, ordinal); cg_convert(p, m, f, TYPE_U64, p.symbols[ordinal_binding].type_id, node); cg_write_value(p, m, f, p.symbols[ordinal_binding].type_id, destination, node);
    }
    let step = cg_begin(f, 0x02, 0x40); f.exits.push(CgExit { label: done, again: step, node: node });
    cg_block_into(p, m, f, n.right, TYPE_VOID, -1); f.exits.pop(); cg_end(f);
    if iterable.kind == N_RANGE && (iterable.flags & F_INCLUSIVE) != 0 {
        cg_get(f, counter); cg_get(f, limit); wb_byte(f.code, cg_numeric_opcode(T_EQ, cg_wasm_type(p, counter_type), false)); cg_branch(p, f, done, true);
    }
    cg_get(f, counter); if cg_wasm_type(p, counter_type) == 0x7e { wb_i64(f.code, 1); } else { wb_i32(f.code, 1); }
    wb_byte(f.code, cg_numeric_opcode(T_PLUS, cg_wasm_type(p, counter_type), false)); cg_normalize(p, f.code, counter_type); cg_set(f, counter);
    cg_get(f, ordinal); wb_i64(f.code, 1); wb_byte(f.code, 0x7c); cg_set(f, ordinal);
    cg_branch(p, f, again, false); cg_end(f); cg_end(f);
}
recursive fn cg_pattern(p: Program&, m: CgModule&, f: CgBody&, pattern: i64, type_id: i64, value: i64) {
    let n = p.nodes[pattern];
    if n.kind == N_PATTERN {
        var alternative = n.first; var emitted = false;
        while alternative >= 0 {
            cg_pattern(p, m, f, alternative, type_id, value);
            if emitted { wb_byte(f.code, 0x72); } emitted = true; alternative = p.nodes[alternative].next;
        }
        if !emitted { wb_i32(f.code, 1); } return;
    }
    if n.kind == N_NAME && token_is(p, n.token, "_") { wb_i32(f.code, 1); return; }
    if n.kind == N_BINARY && n.integer == T_BITOR {
        cg_pattern(p, m, f, n.left, type_id, value); cg_pattern(p, m, f, n.right, type_id, value); wb_byte(f.code, 0x72); return;
    }
    if n.kind == N_RANGE {
        cg_get(f, value); cg_to(p, m, f, n.left, type_id); wb_byte(f.code, cg_numeric_opcode(T_GTEQ, cg_wasm_type(p, type_id), cg_unsigned(p, type_id)));
        cg_get(f, value); cg_to(p, m, f, n.right, type_id); var comparison = T_LT; if (n.flags & F_INCLUSIVE) != 0 { comparison = T_LTEQ; }
        wb_byte(f.code, cg_numeric_opcode(comparison, cg_wasm_type(p, type_id), cg_unsigned(p, type_id))); wb_byte(f.code, 0x71); return;
    }
    if n.symbol >= 0 && n.symbol < p.nodes.len && p.nodes[n.symbol].kind == N_VARIANT {
        cg_get(f, value); wb_i32(f.code, p.nodes[n.symbol].integer); wb_byte(f.code, 0x46); return;
    }
    cg_get(f, value); cg_to(p, m, f, pattern, type_id); wb_byte(f.code, cg_numeric_opcode(T_EQ, cg_wasm_type(p, type_id), false));
}
recursive fn cg_match(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n = p.nodes[node]; var id = p.nodes[n.left].type_id; cg_expr(p, m, f, n.left);
    if cg_type_kind(p, id) == TY_REF { id = p.types[id].element; cg_load(p, m, f, id, 0); }
    var base = -1;
    if cg_type_kind(p, id) == TY_ENUM {
        base = cg_save(f, 0x7f); cg_get(f, base);
        if p.types[id].length_storage == 2 { wb_mem(f.code, 0x2f, 0, 0); } else { wb_mem(f.code, 0x2d, 0, 0); }
        id = TYPE_U32;
    }
    let value = cg_save(f, cg_wasm_type(p, id)); let result = cg_control_slots(p, f, n.type_id); let done = cg_begin(f, 0x02, 0x40);
    var arm = n.first;
    while arm >= 0 {
        let item = p.nodes[arm]; cg_pattern(p, m, f, item.left, id, value); cg_begin(f, 0x04, 0x40);
        var binder = -1;
        if p.nodes[item.left].kind == N_PATTERN { binder = p.nodes[item.left].left; }
        if binder >= 0 && base >= 0 {
            let symbol = p.nodes[binder].symbol; cg_symbol_address(p, m, f, symbol, arm); let address = cg_save(f, 0x7f);
            cg_get(f, base); var enum_id = p.nodes[n.left].type_id; var prefix = 1;
            if cg_type_kind(p, enum_id) == TY_REF { enum_id = p.types[enum_id].element; }
            if cg_type_kind(p, enum_id) == TY_ENUM { prefix = p.types[enum_id].length_storage; }
            wb_i32(f.code, prefix); wb_byte(f.code, 0x6a); cg_write_value(p, m, f, p.symbols[symbol].type_id, address, arm);
        }
        if item.third >= 0 { cg_truth(p, m, f, item.third); cg_begin(f, 0x04, 0x40); }
        cg_block_into(p, m, f, item.right, n.type_id, result); cg_branch(p, f, done, false);
        if item.third >= 0 { cg_end(f); } cg_end(f); arm = item.next;
    }
    cg_abort(p, m, f, node, "non-exhaustive match"); cg_end(f); cg_control_get(p, f, n.type_id, result);
}
recursive fn cg_statement(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n = p.nodes[node];
    if n.kind == N_VARIABLE { cg_declaration(p, m, f, node); return; }
    if n.kind == N_MULTI_ASSIGN { cg_multi_assignment(p, m, f, node); return; }
    if n.kind == N_ASSIGN { cg_assign(p, m, f, node); return; }
    if n.kind == N_RETURN { cg_emit_return(p, m, f, node); return; }
    if n.kind == N_BREAK { cg_break(p, m, f, node, false); return; }
    if n.kind == N_CONTINUE { cg_break(p, m, f, node, true); return; }
    if n.kind == N_FUNCTION || n.kind == N_STRUCT || n.kind == N_ENUM || n.kind == N_ALIAS || n.kind == N_EMPTY || n.kind == N_IMPORT { return; }
    if n.kind == N_EXPR_STMT { cg_discard(p, m, f, n.left); return; }
    if n.kind == N_FOR { cg_for(p, m, f, node); return; }
    cg_discard(p, m, f, node);
}
recursive fn cg_print(p: Program&, m: CgModule&, f: CgBody&, id: i64, value: i64, node: i64, nested: bool) {
    let kind = cg_type_kind(p, id);
    if kind == TY_REF {
        if (p.types[id].flags & TF_OPTIONAL) != 0 { cg_fail(p, node, "wasm: printing an optional reference requires narrowing"); return; }
        cg_get(f, value); let element = p.types[id].element; cg_load(p, m, f, element, 0); let v = cg_save(f, cg_wasm_type(p, element)); cg_print(p, m, f, element, v, node, nested); return;
    }
    if kind == TY_INT {
        cg_get(f, value); var target = TYPE_I64; var host = CG_PRINT_I64;
        if cg_unsigned(p, id) { target = TYPE_U64; host = CG_PRINT_U64; }
        cg_convert(p, m, f, id, target, node); wb_op(f.code, 0x10, host); return;
    }
    if kind == TY_BOOL { cg_get(f, value); wb_op(f.code, 0x10, CG_PRINT_BOOL); return; }
    if kind == TY_FLOAT {
        cg_get(f, value); var host = CG_PRINT_F64; if p.types[id].count == 32 { host = CG_PRINT_F32; }
        wb_op(f.code, 0x10, host); return;
    }
    if kind == TY_ARRAY || kind == TY_SLICE {
        cg_get(f, value); cg_pack_view(p, m, f, id, node); let view = cg_save(f, 0x7e);
        cg_get(f, view); wb_byte(f.code, 0xa7); let pointer = cg_save(f, 0x7f);
        cg_get(f, view); wb_i64(f.code, 32); wb_byte(f.code, 0x88); wb_byte(f.code, 0xa7); let length = cg_save(f, 0x7f);
        let element = p.types[id].element;
        if element == TYPE_U8 && !nested { cg_get(f, pointer); cg_get(f, length); wb_op(f.code, 0x10, CG_WRITE); return; }
        if element == TYPE_U8 { cg_text(m, f, "\""); } else { cg_text(m, f, "["); }
        wb_i32(f.code, 0); let index = cg_save(f, 0x7f);
        let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
        cg_get(f, index); cg_get(f, length); wb_byte(f.code, 0x4f); cg_branch(p, f, done, true);
        if element == TYPE_U8 {
            cg_get(f, pointer); cg_get(f, index); wb_byte(f.code, 0x6a); wb_mem(f.code, 0x2d, 0, 0); let byte = cg_save(f, 0x7f);
            let emitted = cg_begin(f, 0x02, 0x40);
            for character in [34, 92, 10, 13, 9] {
                cg_get(f, byte); wb_i32(f.code, character); wb_byte(f.code, 0x46); cg_begin(f, 0x04, 0x40);
                if character == 34 { cg_text(m, f, "\\\""); } else if character == 92 { cg_text(m, f, "\\\\"); }
                else if character == 10 { cg_text(m, f, "\\n"); } else if character == 13 { cg_text(m, f, "\\r"); } else { cg_text(m, f, "\\t"); }
                cg_branch(p, f, emitted, false); cg_end(f);
            }
            cg_get(f, pointer); cg_get(f, index); wb_byte(f.code, 0x6a); wb_i32(f.code, 1); wb_op(f.code, 0x10, CG_WRITE); cg_end(f);
        } else {
            cg_get(f, index); cg_begin(f, 0x04, 0x40); cg_text(m, f, ", "); cg_end(f);
            if p.types[element].storage == 1 {
                cg_get(f, index); wb_byte(f.code, 0xad); let index64 = cg_save(f, 0x7e); let cursor = cg_walk_elements(p, m, f, pointer, index64, node); cg_get(f, cursor);
            } else { cg_get(f, pointer); cg_get(f, index); wb_i32(f.code, cg_size(p, element)); wb_byte(f.code, 0x6c); wb_byte(f.code, 0x6a); }
            cg_load(p, m, f, element, 0); let item = cg_save(f, cg_wasm_type(p, element)); cg_print(p, m, f, element, item, node, true);
        }
        cg_get(f, index); wb_i32(f.code, 1); wb_byte(f.code, 0x6a); cg_set(f, index); cg_branch(p, f, again, false); cg_end(f); cg_end(f);
        if element == TYPE_U8 { cg_text(m, f, "\""); } else { cg_text(m, f, "]"); } return;
    }
    if kind == TY_STRUCT {
        if cg_byte_record(p, id) || p.types[id].tail >= 0 { cg_fail(p, node, "wasm: variable-record rendering is unsupported by the direct backend"); return; }
        let declaration = p.types[id].declaration;
        let name = token_text(p, p.nodes[declaration].token); cg_text(m, f, name); cg_text(m, f, " { ");
        var field = p.nodes[declaration].first; var first = true;
        while field >= 0 {
            if (p.nodes[field].flags & F_PAD) == 0 {
                if !first { cg_text(m, f, ", "); } first = false;
                cg_get(f, value); wb_i32(f.code, p.nodes[field].integer); wb_byte(f.code, 0x6a); cg_load(p, m, f, p.nodes[field].type_id, 0);
                let item = cg_save(f, cg_wasm_type(p, p.nodes[field].type_id)); cg_print(p, m, f, p.nodes[field].type_id, item, node, true);
            }
            field = p.nodes[field].next;
        }
        cg_text(m, f, " }"); return;
    }
    if kind == TY_ENUM {
        cg_get(f, value); var load = 0x2d; if p.types[id].length_storage == 2 { load = 0x2f; }
        wb_mem(f.code, load, 0, 0); let tag = cg_save(f, 0x7f); let done = cg_begin(f, 0x02, 0x40);
        var variant = p.types[id].first;
        while variant >= 0 {
            cg_get(f, tag); wb_i32(f.code, p.nodes[variant].integer); wb_byte(f.code, 0x46); cg_begin(f, 0x04, 0x40);
            let payload = p.nodes[variant].type_id;
            if p.nodes[variant].first < 0 {
                cg_text(m, f, token_text(p, p.nodes[p.types[id].declaration].token)); cg_text(m, f, "."); cg_text(m, f, token_text(p, p.nodes[variant].token));
            } else {
                cg_get(f, value); wb_i32(f.code, p.types[id].length_storage); wb_byte(f.code, 0x6a); let pointer = cg_save(f, 0x7f);
                cg_print(p, m, f, payload, pointer, node, nested);
            }
            cg_branch(p, f, done, false); cg_end(f); variant = p.nodes[variant].next;
        }
        cg_abort(p, m, f, node, "invalid enum tag"); cg_end(f); return;
    }
    cg_fail(p, node, "wasm: this value cannot be rendered");
}
fn cg_array_length(p: Program&, m: CgModule&, f: CgBody&, id: i64, base: i64) {
    if cg_owner(p, id) { cg_owner_read_length(p, m, f, base, -1); }
    else { cg_get(f, base); cg_length_load(p, f, id); }
}
fn cg_array_set_length(p: Program&, m: CgModule&, f: CgBody&, id: i64, base: i64, length: i64) {
    if cg_owner(p, id) { cg_owner_set_length(p, m, f, base, length, -1); }
    else { cg_get(f, base); cg_get(f, length); cg_length_store(p, f, id); }
}
fn cg_array_pointer(p: Program&, m: CgModule&, f: CgBody&, id: i64, base: i64) {
    if cg_owner(p, id) { cg_owner_read_base(p, m, f, base, -1); }
    else { cg_get(f, base); wb_i32(f.code, cg_static_prefix(p, id)); wb_byte(f.code, 0x6a); }
}
fn cg_array_element(p: Program&, m: CgModule&, f: CgBody&, id: i64, base: i64, index: i64) {
    cg_array_pointer(p, m, f, id, base); cg_get(f, index); wb_i32(f.code, cg_size(p, p.types[id].element)); wb_byte(f.code, 0x6c); wb_byte(f.code, 0x6a);
}
fn cg_array_reserve(p: Program&, m: CgModule&, f: CgBody&, id: i64, base: i64, count: i64, node: i64) {
    if !cg_owner(p, id) {
        cg_get(f, count); wb_i32(f.code, p.types[id].count); wb_byte(f.code, 0x4b); cg_trap_if(p, m, f, node, "array capacity exceeded"); return;
    }
    cg_get(f, base); wb_mem(f.code, 0x28, 2, 12); let old_capacity = cg_save(f, 0x7f);
    cg_get(f, count); cg_get(f, old_capacity); wb_byte(f.code, 0x4b); cg_begin(f, 0x04, 0x40);
    if p.types[id].array_kind != A_GROW && p.types[id].array_kind != A_GROWSHRINK { cg_abort(p, m, f, node, "array capacity exceeded"); }
    cg_get(f, old_capacity); wb_byte(f.code, 0xad); wb_i64(f.code, 2); wb_byte(f.code, 0x7e); cg_get(f, count); wb_byte(f.code, 0xad);
    cg_get(f, old_capacity); wb_byte(f.code, 0xad); wb_i64(f.code, 2); wb_byte(f.code, 0x7e); cg_get(f, count); wb_byte(f.code, 0xad); wb_byte(f.code, 0x56); wb_byte(f.code, 0x1b);
    let capacity64 = cg_save(f, 0x7e);
    cg_get(f, capacity64); wb_i64(f.code, 4294967295); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array capacity overflow");
    cg_get(f, capacity64); wb_i64(f.code, cg_size(p, p.types[id].element)); wb_byte(f.code, 0x7e); let bytes64 = cg_save(f, 0x7e);
    cg_get(f, bytes64); wb_i64(f.code, 4294967295); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array byte size overflow");
    cg_get(f, bytes64); wb_byte(f.code, 0xa7); wb_op(f.code, 0x10, m.allocator); let pointer = cg_save(f, 0x7f);
    cg_get(f, pointer); cg_array_pointer(p, m, f, id, base); cg_array_length(p, m, f, id, base); wb_i32(f.code, cg_size(p, p.types[id].element)); wb_byte(f.code, 0x6c); wb_copy(f.code);
    cg_get(f, base); cg_get(f, pointer); wb_mem(f.code, 0x36, 2, 0);
    cg_get(f, base); cg_get(f, pointer); cg_get(f, bytes64); wb_byte(f.code, 0xa7); wb_byte(f.code, 0x6a); wb_mem(f.code, 0x36, 2, 8);
    cg_get(f, base); cg_get(f, capacity64); wb_byte(f.code, 0xa7); wb_mem(f.code, 0x36, 2, 12); cg_end(f);
}
recursive fn cg_array_builtin(p: Program&, m: CgModule&, f: CgBody&, node: i64, builtin: i64) {
    let n = p.nodes[node]; let receiver = n.first;
    if receiver < 0 { cg_fail(p, node, "wasm: array builtin has no receiver"); return; }
    var id = p.nodes[receiver].type_id; cg_expr(p, m, f, receiver);
    if cg_type_kind(p, id) == TY_REF { id = p.types[id].element; cg_load(p, m, f, id, 0); }
    let base = cg_save(f, 0x7f); let element = p.types[id].element; let arg = p.nodes[receiver].next;
    if builtin == 23 {
        cg_expr(p, m, f, arg); cg_array_pointer(p, m, f, id, base); wb_byte(f.code, 0x6b); wb_byte(f.code, 0xad);
        wb_i64(f.code, cg_size(p, element)); wb_byte(f.code, 0x80); cg_convert(p, m, f, TYPE_I64, n.type_id, node); return;
    }
    if !cg_owner(p, id) && p.types[id].array_kind != A_LIMITED { cg_fail(p, node, "wasm: array mutation requires bounded or growable storage"); return; }
    if p.types[element].storage == 1 { cg_varint_array_builtin(p, m, f, node, builtin, id, base, arg); return; }
    if builtin == 29 {
        wb_i32(f.code, 0); let zero = cg_save(f, 0x7f); cg_array_set_length(p, m, f, id, base, zero); return;
    }
    if builtin == 24 {
        cg_to(p, m, f, arg, element); let value = cg_save(f, cg_wasm_type(p, element));
        cg_array_length(p, m, f, id, base); let old = cg_save(f, 0x7f);
        cg_get(f, old); wb_i32(f.code, -1); wb_byte(f.code, 0x46); cg_trap_if(p, m, f, node, "array length overflow");
        cg_get(f, old); wb_i32(f.code, 1); wb_byte(f.code, 0x6a); let count = cg_save(f, 0x7f); cg_array_reserve(p, m, f, id, base, count, node);
        cg_array_element(p, m, f, id, base, old); let destination = cg_save(f, 0x7f); cg_get(f, value); cg_write_value(p, m, f, element, destination, node);
        cg_array_set_length(p, m, f, id, base, count);
        if n.type_id != TYPE_VOID {
            cg_get(f, destination); if cg_type_kind(p, element) == TY_REF { cg_load(p, m, f, element, 0); }
            else if cg_type_kind(p, n.type_id) != TY_REF { cg_load(p, m, f, element, 0); cg_convert(p, m, f, element, n.type_id, node); }
        }
        return;
    }
    if builtin == 26 {
        cg_array_length(p, m, f, id, base); let old = cg_save(f, 0x7f); cg_get(f, old); wb_byte(f.code, 0x45); cg_trap_if(p, m, f, node, "pop from empty array");
        cg_get(f, old); wb_i32(f.code, 1); wb_byte(f.code, 0x6b); let count = cg_save(f, 0x7f); cg_array_set_length(p, m, f, id, base, count);
        cg_array_element(p, m, f, id, base, count); cg_load(p, m, f, element, 0);
        if cg_aggregate(p, element) { let source = cg_save(f, 0x7f); let destination = cg_temporary(p, f, element); cg_copy(p, m, f, element, destination, source, node); cg_get(f, destination); }
        cg_convert(p, m, f, element, n.type_id, node); return;
    }
    if builtin == 25 {
        cg_expr(p, m, f, arg); cg_pack_view(p, m, f, p.nodes[arg].type_id, node); let view = cg_save(f, 0x7e);
        cg_get(f, view); wb_i64(f.code, 32); wb_byte(f.code, 0x88); wb_byte(f.code, 0xa7); let added = cg_save(f, 0x7f);
        cg_array_length(p, m, f, id, base); let old = cg_save(f, 0x7f);
        cg_get(f, old); cg_get(f, added); wb_byte(f.code, 0x6a); let count = cg_save(f, 0x7f);
        cg_get(f, count); cg_get(f, old); wb_byte(f.code, 0x49); cg_trap_if(p, m, f, node, "array length overflow"); cg_array_reserve(p, m, f, id, base, count, node);
        cg_array_element(p, m, f, id, base, old); cg_get(f, view); wb_byte(f.code, 0xa7); cg_get(f, added); wb_i32(f.code, cg_size(p, element)); wb_byte(f.code, 0x6c); wb_copy(f.code);
        cg_array_set_length(p, m, f, id, base, count); return;
    }
    cg_to(p, m, f, arg, TYPE_U64); let requested = cg_save(f, 0x7e);
    var fill_value = -1; let fill_node = p.nodes[arg].next;
    if fill_node >= 0 { cg_to(p, m, f, fill_node, element); fill_value = cg_save(f, cg_wasm_type(p, element)); }
    cg_array_length(p, m, f, id, base); let old = cg_save(f, 0x7f);
    if builtin == 27 {
        cg_get(f, requested); cg_get(f, old); wb_byte(f.code, 0xad); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "pop count out of bounds");
        cg_get(f, old); cg_get(f, requested); wb_byte(f.code, 0xa7); wb_byte(f.code, 0x6b); let count = cg_save(f, 0x7f); cg_array_set_length(p, m, f, id, base, count); return;
    }
    cg_get(f, requested); wb_i64(f.code, 4294967295); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array length overflow");
    cg_get(f, requested); wb_byte(f.code, 0xa7); let count = cg_save(f, 0x7f);
    cg_get(f, count); cg_get(f, old); wb_byte(f.code, 0x4b); cg_begin(f, 0x04, 0x40);
    if fill_value < 0 { cg_abort(p, m, f, node, "array resize growth requires a fill value"); }
    else {
        cg_array_reserve(p, m, f, id, base, count, node); cg_get(f, old); let index = cg_save(f, 0x7f);
        let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
        cg_get(f, index); cg_get(f, count); wb_byte(f.code, 0x4f); cg_branch(p, f, done, true);
        cg_array_element(p, m, f, id, base, index); let destination = cg_save(f, 0x7f); cg_get(f, fill_value); cg_write_value(p, m, f, element, destination, node);
        cg_get(f, index); wb_i32(f.code, 1); wb_byte(f.code, 0x6a); cg_set(f, index); cg_branch(p, f, again, false); cg_end(f); cg_end(f);
    }
    cg_end(f); cg_array_set_length(p, m, f, id, base, count);
}
recursive fn cg_builtin(p: Program&, m: CgModule&, f: CgBody&, node: i64, builtin: i64) {
    let n = p.nodes[node]; let arg = n.first;
    if builtin == 0 {
        let mark = f.work.len; var scratch_mark = -1;
        if m.scalar { wb_op(f.code, 0x23, 0); scratch_mark = cg_save(f, 0x7f); }
        var child = arg;
        while child >= 0 {
            var id = p.nodes[child].type_id; cg_expr(p, m, f, child);
            if cg_type_kind(p, id) == TY_REF { id = p.types[id].element; cg_load(p, m, f, id, 0); }
            var value = cg_save(f, cg_wasm_type(p, id));
            if cg_aggregate(p, id) { let snapshot = cg_temporary(p, f, id); cg_copy(p, m, f, id, snapshot, value, child); value = snapshot; }
            else if cg_type_kind(p, id) == TY_SLICE {
                cg_get(f, value); wb_i64(f.code, 32); wb_byte(f.code, 0x88); wb_byte(f.code, 0xa7); let length = cg_save(f, 0x7f);
                var bytes = -1;
                if p.types[p.types[id].element].storage == 1 {
                    cg_get(f, value); wb_byte(f.code, 0xa7); let base = cg_save(f, 0x7f); cg_get(f, length); wb_byte(f.code, 0xad); let count = cg_save(f, 0x7e); let end = cg_walk_elements(p, m, f, base, count, node);
                    cg_get(f, end); cg_get(f, base); wb_byte(f.code, 0x6b); bytes = cg_save(f, 0x7f);
                } else { cg_get(f, length); wb_i32(f.code, cg_size(p, p.types[id].element)); wb_byte(f.code, 0x6c); bytes = cg_save(f, 0x7f); }
                cg_get(f, bytes); wb_op(f.code, 0x10, m.allocator); let copy = cg_save(f, 0x7f);
                cg_get(f, copy); cg_get(f, value); wb_byte(f.code, 0xa7); cg_get(f, bytes); wb_copy(f.code);
                cg_get(f, copy); wb_byte(f.code, 0xad); cg_get(f, length); wb_byte(f.code, 0xad); wb_i64(f.code, 32); wb_byte(f.code, 0x86); wb_byte(f.code, 0x84); value = cg_save(f, 0x7e);
            }
            f.work.push(id); f.work.push(value); child = p.nodes[child].next;
        }
        let end = f.work.len; var at = mark;
        while at < end { let id = f.work[at]; let value = f.work[at + 1]; cg_print(p, m, f, id, value, node, false); at += 2; }
        f.work.resize(mark); wb_op(f.code, 0x10, CG_NEWLINE);
        if m.scalar { cg_get(f, scratch_mark); wb_op(f.code, 0x24, 0); } return;
    }
    if builtin == 3 { cg_truth(p, m, f, arg); wb_byte(f.code, 0x45); cg_trap_if(p, m, f, node, "assertion failed"); return; }
    if builtin == 4 {
        cg_expr(p, m, f, arg); cg_pack_view(p, m, f, p.nodes[arg].type_id, node); let view = cg_save(f, 0x7e);
        cg_get(f, view); wb_byte(f.code, 0xa7); cg_get(f, view); wb_i64(f.code, 32); wb_byte(f.code, 0x88); wb_byte(f.code, 0xa7);
        var line = 0; if n.token >= 0 { line = p.tokens[n.token].line; }
        wb_i32(f.code, line); wb_op(f.code, 0x10, CG_ABORT); wb_byte(f.code, 0); return;
    }
    if builtin == 5 { cg_to(p, m, f, arg, TYPE_I32); wb_op(f.code, 0x10, CG_EXIT); wb_byte(f.code, 0); return; }
    if builtin == 14 {
        if cg_aggregate(p, n.type_id) {
            let destination = cg_temporary(p, f, n.type_id); cg_get(f, destination); wb_i32(f.code, 0); wb_i32(f.code, cg_size(p, n.type_id)); wb_fill(f.code); cg_get(f, destination);
        } else { cg_zero(f.code, cg_wasm_type(p, n.type_id)); } return;
    }
    if builtin == 15 {
        cg_to(p, m, f, arg, n.type_id);
        if cg_aggregate(p, n.type_id) { let source = cg_save(f, 0x7f); let destination = cg_temporary(p, f, n.type_id); cg_copy(p, m, f, n.type_id, destination, source, node); cg_get(f, destination); }
        return;
    }
    if builtin == 21 {
        cg_expr(p, m, f, arg); cg_pack_view(p, m, f, p.nodes[arg].type_id, node); wb_i64(f.code, 32); wb_byte(f.code, 0x88); cg_convert(p, m, f, TYPE_U64, n.type_id, node); return;
    }
    if builtin == 22 {
        var id = p.nodes[arg].type_id; cg_expr(p, m, f, arg);
        if cg_type_kind(p, id) == TY_REF { id = p.types[id].element; cg_load(p, m, f, id, 0); }
        if cg_owner(p, id) { let header = cg_save(f, 0x7f); cg_owner_read_capacity(p, m, f, header); wb_byte(f.code, 0xad); }
        else { wb_byte(f.code, 0x1a); wb_i64(f.code, p.types[id].count); }
        cg_convert(p, m, f, TYPE_U64, n.type_id, node); return;
    }
    if builtin >= 23 && builtin <= 29 { cg_array_builtin(p, m, f, node, builtin); return; }
    if builtin == 16 || builtin == 17 {
        var id = p.nodes[arg].type_id;
        if cg_type_kind(p, id) == TY_SLICE || cg_type_kind(p, id) == TY_ARRAY {
            cg_expr(p, m, f, arg); cg_pack_view(p, m, f, id, node); let view = cg_save(f, 0x7e);
            cg_get(f, view); wb_i64(f.code, 4294967295); wb_byte(f.code, 0x83);
            cg_get(f, view); wb_i64(f.code, 32); wb_byte(f.code, 0x88); wb_i64(f.code, cg_size(p, p.types[id].element)); wb_byte(f.code, 0x7e); wb_i64(f.code, 32); wb_byte(f.code, 0x86); wb_byte(f.code, 0x84);
        } else {
            if cg_type_kind(p, id) == TY_REF { cg_expr(p, m, f, arg); id = p.types[id].element; }
            else { cg_address(p, m, f, arg); }
            wb_byte(f.code, 0xad); wb_i64(f.code, cg_size(p, id) << 32); wb_byte(f.code, 0x84);
        }
        return;
    }
    if builtin == 18 {
        cg_expr(p, m, f, arg); cg_pack_view(p, m, f, p.nodes[arg].type_id, node); let view = cg_save(f, 0x7e);
        var id = n.type_id; if cg_type_kind(p, id) == TY_REF { id = p.types[id].element; }
        cg_get(f, view); wb_i64(f.code, 32); wb_byte(f.code, 0x88); wb_i64(f.code, cg_size(p, id)); wb_byte(f.code, 0x54); cg_trap_if(p, m, f, node, "byte view is too short");
        cg_get(f, view); wb_byte(f.code, 0xa7); if cg_type_kind(p, n.type_id) != TY_REF { cg_load(p, m, f, id, 0); } return;
    }
    cg_fail(p, node, "wasm: builtin is unsupported by the direct Wasm execution environment");
}
recursive fn cg_slice(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n = p.nodes[node]; var id = p.nodes[n.left].type_id;
    if cg_type_kind(p, id) == TY_REF { id = p.types[id].element; }
    cg_expr(p, m, f, n.left); cg_pack_view(p, m, f, p.nodes[n.left].type_id, node); let view = cg_save(f, 0x7e);
    if n.right >= 0 {
        if (n.flags & F_FROM_END) != 0 { cg_get(f, view); wb_i64(f.code, 32); wb_byte(f.code, 0x88); }
        cg_to(p, m, f, n.right, TYPE_U64); if (n.flags & F_FROM_END) != 0 { wb_byte(f.code, 0x7d); }
    } else { wb_i64(f.code, 0); }
    let start = cg_save(f, 0x7e);
    if n.third >= 0 {
        if (n.flags & F_TO_END) != 0 { cg_get(f, view); wb_i64(f.code, 32); wb_byte(f.code, 0x88); }
        cg_to(p, m, f, n.third, TYPE_U64); if (n.flags & F_TO_END) != 0 { wb_byte(f.code, 0x7d); }
    }
    else { cg_get(f, view); wb_i64(f.code, 32); wb_byte(f.code, 0x88); }
    let end = cg_save(f, 0x7e);
    cg_get(f, start); cg_get(f, end); wb_byte(f.code, 0x56);
    cg_get(f, end); cg_get(f, view); wb_i64(f.code, 32); wb_byte(f.code, 0x88); wb_byte(f.code, 0x56); wb_byte(f.code, 0x72); cg_trap_if(p, m, f, node, "slice bounds out of range");
    if p.types[p.types[id].element].storage == 1 {
        cg_get(f, view); wb_byte(f.code, 0xa7); let base = cg_save(f, 0x7f); let pointer = cg_walk_elements(p, m, f, base, start, node); cg_get(f, pointer); wb_byte(f.code, 0xad);
    } else {
        cg_get(f, view); wb_byte(f.code, 0xa7); cg_get(f, start); wb_byte(f.code, 0xa7); wb_i32(f.code, cg_size(p, p.types[id].element)); wb_byte(f.code, 0x6c); wb_byte(f.code, 0x6a); wb_byte(f.code, 0xad);
    }
    cg_get(f, end); cg_get(f, start); wb_byte(f.code, 0x7d); wb_i64(f.code, 32); wb_byte(f.code, 0x86); wb_byte(f.code, 0x84);
}
recursive fn cg_cast(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n = p.nodes[node]; var from = p.nodes[n.left].type_id; let to = n.type_id;
    cg_expr(p, m, f, n.left);
    if cg_type_kind(p, from) == TY_REF && (p.types[from].flags & TF_OPTIONAL) != 0 && cg_type_kind(p, to) == TY_BOOL { cg_convert(p, m, f, from, to, node); return; }
    if cg_type_kind(p, from) == TY_REF && cg_type_kind(p, to) != TY_REF { from = p.types[from].element; cg_load(p, m, f, from, 0); }
    if cg_type_kind(p, from) == TY_ARRAY && cg_type_kind(p, to) == TY_SLICE { cg_pack_view(p, m, f, from, node); return; }
    let value = cg_save(f, cg_wasm_type(p, from));
    if cg_type_kind(p, to) == TY_INT && p.types[to].index_type >= 0 && (n.flags & F_BOUNDS_PROVEN) == 0 {
        let symbol = p.types[to].pool;
        if symbol < 0 || cg_type_kind(p, from) != TY_INT { cg_fail(p, node, "wasm: index cast requires an integer and a resolved array owner"); return; }
        cg_symbol_address(p, m, f, symbol, node); let owner_type = p.symbols[symbol].type_id; cg_load(p, m, f, owner_type, 0); cg_pack_view(p, m, f, owner_type, node);
        wb_i64(f.code, 32); wb_byte(f.code, 0x88); let length = cg_save(f, 0x7e);
        cg_get(f, value); cg_convert(p, m, f, from, TYPE_U64, node); cg_get(f, length); var comparison = 0x5a;
        if (p.types[to].flags & F_BOUND_TYPE) != 0 { comparison = 0x56; }
        wb_byte(f.code, comparison); cg_trap_if(p, m, f, node, "index type cast out of bounds");
    }
    if p.debug && (n.flags & F_UNSIGNED) == 0 && cg_type_kind(p, to) == TY_INT {
        let bits = p.types[to].count; let target_unsigned = cg_unsigned(p, to);
        if cg_type_kind(p, from) == TY_FLOAT {
            cg_get(f, value); if cg_wasm_type(p, from) == 0x7d { wb_byte(f.code, 0xbb); } let number = cg_save(f, 0x7c);
            var exponent = bits - 1; if target_unsigned { exponent = bits; }
            var high = 1.0; for i in 0..exponent { high *= 2.0; } var low = 0.0; if !target_unsigned { low = 0.0 - high; }
            cg_get(f, number); wb_f64(f.code, low); wb_byte(f.code, 0x66); cg_get(f, number); wb_f64(f.code, high); wb_byte(f.code, 0x63); wb_byte(f.code, 0x71); wb_byte(f.code, 0x45);
            cg_trap_if(p, m, f, node, "float-to-integer conversion out of range");
            cg_get(f, number); wb_byte(f.code, 0x9d); cg_get(f, number); wb_byte(f.code, 0x62); cg_trap_if(p, m, f, node, "float-to-integer conversion changes the value");
        } else if cg_type_kind(p, from) == TY_INT {
            let source_unsigned = cg_unsigned(p, from); cg_get(f, value); var wide_type = TYPE_I64; if source_unsigned { wide_type = TYPE_U64; }
            cg_convert(p, m, f, from, wide_type, node); let wide = cg_save(f, 0x7e);
            if !source_unsigned && target_unsigned { cg_get(f, wide); wb_i64(f.code, 0); wb_byte(f.code, 0x53); cg_trap_if(p, m, f, node, "integer cast out of range"); }
            if !target_unsigned {
                var minimum: i64 = -9223372036854775807 - 1; var maximum: i64 = 9223372036854775807;
                if bits < 64 { minimum = 0 - (1 << (bits - 1)); maximum = (1 << (bits - 1)) - 1; }
                if !source_unsigned { cg_get(f, wide); wb_i64(f.code, minimum); wb_byte(f.code, 0x53); cg_trap_if(p, m, f, node, "integer cast out of range"); }
                cg_get(f, wide); wb_i64(f.code, maximum); var opcode = 0x55; if source_unsigned { opcode = 0x56; }
                wb_byte(f.code, opcode); cg_trap_if(p, m, f, node, "integer cast out of range");
            } else if bits < 64 {
                cg_get(f, wide); wb_i64(f.code, (1 << bits) - 1); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "integer cast out of range");
            }
        }
    }
    cg_get(f, value); cg_convert(p, m, f, from, to, node);
}

recursive fn cg_expr(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    if node < 0 { return; } let n = p.nodes[node]; let w = cg_wasm_type(p, n.type_id);
    if n.kind == N_INTEGER || n.kind == N_BOOL || n.kind == N_NULL {
        if w == 0x7e { wb_i64(f.code, n.integer); } else if w == 0x7d { wb_f32(f.code, n.integer); }
        else if w == 0x7c { wb_f64(f.code, n.integer); } else { wb_i32(f.code, n.integer); }
        return;
    }
    if n.kind == N_FLOAT { if w == 0x7d { wb_f32(f.code, n.float_value); } else { wb_f64(f.code, n.float_value); } return; }
    if n.kind == N_STRING {
        let token = p.tokens[n.token]; let bytes = p.text[token.text_start..token.text_start + token.text_len]; let address = cg_data(m, bytes);
        if cg_type_kind(p, n.type_id) == TY_SLICE { wb_i64(f.code, address | (bytes.len << 32)); return; }
        if cg_type_kind(p, n.type_id) == TY_ARRAY {
            let destination = cg_temporary(p, f, n.type_id);
            if cg_owner(p, n.type_id) {
                wb_i32(f.code, bytes.len); let count = cg_save(f, 0x7f);
                let buffer = cg_owner_image(p, m, f, n.type_id, destination, count, count, node);
                cg_get(f, buffer); wb_i32(f.code, address); wb_i32(f.code, bytes.len); wb_copy(f.code);
            } else {
                cg_get(f, destination); wb_i32(f.code, 0); wb_i32(f.code, cg_size(p, n.type_id)); wb_fill(f.code);
                if p.types[n.type_id].array_kind == A_LIMITED { cg_get(f, destination); wb_i32(f.code, bytes.len); cg_length_store(p, f, n.type_id); }
                cg_get(f, destination); wb_i32(f.code, cg_static_prefix(p, n.type_id)); wb_byte(f.code, 0x6a); wb_i32(f.code, address); wb_i32(f.code, bytes.len); wb_copy(f.code);
            }
            cg_get(f, destination); return;
        }
        cg_fail(p, node, "wasm: unsupported string representation"); return;
    }
    if n.kind == N_NAME {
        if n.symbol >= 0 && (p.symbols[n.symbol].flags & S_FUNCTION) != 0 { cg_closure(p, m, f, n.symbol, node); return; }
        cg_symbol_address(p, m, f, n.symbol, node);
        if !cg_load(p, m, f, p.symbols[n.symbol].type_id, 0) { cg_fail(p, node, "wasm: unresolved name value type"); }
        return;
    }
    if n.kind == N_FUNCTION_VALUE { cg_closure(p, m, f, n.symbol, node); return; }
    if n.kind == N_ARRAY || n.kind == N_FILL { cg_array_literal(p, m, f, node); return; }
    if n.kind == N_RECORD { cg_record_literal(p, m, f, node); return; }
    if n.kind == N_UNARY {
        if n.integer == T_BITAND { cg_address(p, m, f, n.left); return; }
        if n.integer == T_MUL || n.integer == T_XOR { cg_expr(p, m, f, n.left); cg_load(p, m, f, n.type_id, 0); return; }
        if n.integer == T_NOT { cg_truth(p, m, f, n.left); wb_byte(f.code, 0x45); return; }
        if n.integer == T_MINUS && (w == 0x7d || w == 0x7c) {
            cg_to(p, m, f, n.left, n.type_id); var opcode = 0x8c; if w == 0x7c { opcode = 0x9a; } wb_byte(f.code, opcode); return;
        }
        if n.integer == T_MINUS { cg_zero(f.code, w); cg_to(p, m, f, n.left, n.type_id); cg_numeric(p, m, f, T_MINUS, n.type_id, node); return; }
        if n.integer == T_BITNOT { cg_to(p, m, f, n.left, n.type_id); if w == 0x7e { wb_i64(f.code, -1); } else { wb_i32(f.code, -1); } wb_byte(f.code, cg_numeric_opcode(T_XOR, w, false)); cg_normalize(p, f.code, n.type_id); return; }
        cg_fail(p, node, "wasm: unsupported unary operation"); return;
    }
    if n.kind == N_BINARY { cg_binary(p, m, f, node); return; }
    if n.kind == N_MEMBER {
        if token_is(p, n.token, "len") || token_is(p, n.token, "cap") {
            cg_expr(p, m, f, n.left); var id = p.nodes[n.left].type_id;
            if cg_type_kind(p, id) == TY_REF { id = p.types[id].element; cg_load(p, m, f, id, 0); }
            if token_is(p, n.token, "cap") && cg_type_kind(p, id) == TY_ARRAY {
                if cg_owner(p, id) { let header = cg_save(f, 0x7f); cg_owner_read_capacity(p, m, f, header); wb_byte(f.code, 0xad); }
                else { wb_byte(f.code, 0x1a); wb_i64(f.code, p.types[id].count); }
            } else { cg_pack_view(p, m, f, id, node); wb_i64(f.code, 32); wb_byte(f.code, 0x88); }
            cg_convert(p, m, f, TYPE_U64, n.type_id, node); return;
        }
        if n.symbol >= 0 && n.symbol < p.nodes.len && p.nodes[n.symbol].kind == N_VARIANT {
            let destination = cg_temporary(p, f, n.type_id); cg_get(f, destination); wb_i32(f.code, 0); wb_i32(f.code, cg_size(p, n.type_id)); wb_fill(f.code); cg_get(f, destination); return;
        }
        cg_address(p, m, f, node); var id = n.type_id;
        if n.symbol >= 0 { id = p.nodes[n.symbol].type_id; }
        if cg_type_kind(p, n.type_id) == TY_REF && cg_type_kind(p, id) != TY_REF { return; }
        cg_load(p, m, f, id, 0); cg_convert(p, m, f, id, n.type_id, node); return;
    }
    if n.kind == N_INDEX {
        cg_address(p, m, f, node); var object_type = p.nodes[n.left].type_id;
        if cg_type_kind(p, object_type) == TY_REF { object_type = p.types[object_type].element; }
        let element = p.types[object_type].element;
        if cg_type_kind(p, n.type_id) == TY_REF && cg_type_kind(p, element) != TY_REF { return; }
        cg_load(p, m, f, element, 0); cg_convert(p, m, f, element, n.type_id, node); return;
    }
    if n.kind == N_SLICE { cg_slice(p, m, f, node); return; }
    if n.kind == N_CAST { cg_cast(p, m, f, node); return; }
    if n.kind == N_CALL { cg_call(p, m, f, node); return; }
    if n.kind == N_BLOCK {
        let result = cg_control_slots(p, f, n.type_id);
        if (n.flags & F_EARLY) != 0 {
            let done = cg_begin(f, 0x02, 0x40); f.exits.push(CgExit { label: done, node: node, result: result, type_id: n.type_id });
            cg_block_into(p, m, f, node, n.type_id, result); f.exits.pop(); cg_end(f);
        } else { cg_block_into(p, m, f, node, n.type_id, result); }
        cg_control_get(p, f, n.type_id, result); return;
    }
    if n.kind == N_IF || n.kind == N_GUARD {
        let result = cg_control_slots(p, f, n.type_id); cg_truth(p, m, f, n.left); cg_begin(f, 0x04, 0x40);
        cg_block_into(p, m, f, n.right, n.type_id, result);
        if n.third >= 0 { wb_byte(f.code, 0x05); cg_block_into(p, m, f, n.third, n.type_id, result); }
        cg_end(f); cg_control_get(p, f, n.type_id, result); return;
    }
    if n.kind == N_WHILE || n.kind == N_LOOP { cg_loop(p, m, f, node); return; }
    if n.kind == N_FOR { cg_for(p, m, f, node); return; }
    if n.kind == N_MATCH { cg_match(p, m, f, node); return; }
    if n.kind == N_RETURN || n.kind == N_BREAK || n.kind == N_CONTINUE || n.kind == N_ASSIGN || n.kind == N_VARIABLE || n.kind == N_EXPR_STMT { cg_statement(p, m, f, node); return; }
    if n.kind == N_EMPTY { return; }
    cg_fail(p, node, "wasm: checked AST node has no binary lowering");
}
fn cg_ensure_memory(p: Program&, m: CgModule&, f: CgBody&, top: i64, node: i64) {
    cg_get(f, top); wb_op(f.code, 0x3f, 0); wb_i32(f.code, 16); wb_byte(f.code, 0x74); wb_byte(f.code, 0x4b); cg_begin(f, 0x04, 0x40);
    cg_get(f, top); wb_i32(f.code, 16); wb_byte(f.code, 0x76);
    cg_get(f, top); wb_i32(f.code, 65535); wb_byte(f.code, 0x71); wb_byte(f.code, 0x45); wb_byte(f.code, 0x45); wb_byte(f.code, 0x6a);
    wb_op(f.code, 0x3f, 0); wb_byte(f.code, 0x6b); wb_op(f.code, 0x40, 0); wb_i32(f.code, -1); wb_byte(f.code, 0x46);
    cg_trap_if(p, m, f, node, "linear memory exhausted"); cg_end(f);
}
fn cg_body_tables(p: Program&, f: CgBody&) {
    for symbol in p.symbols { f.slots.push(-1); f.offsets.push(-1); }
}
fn cg_prepare_function(p: Program&, m: CgModule&, f: CgBody&, function: i64) {
    var param = -1; if function >= 0 { param = p.nodes[function].first; }
    while param >= 0 { f.params++; param = p.nodes[param].next; }
    for capture in m.captures { if capture.function == function { f.params++; } }
    var results: i64[>..] = []; if function >= 0 { cg_function_results(p, function, results); }
    let destination_start = f.params;
    for id in results { if cg_aggregate(p, id) { f.params++; } }
    f.frame = cg_local(f, 0x7f); cg_body_tables(p, f);
    var parameter_count = 0; param = -1; if function >= 0 { param = p.nodes[function].first; }
    while param >= 0 { parameter_count++; param = p.nodes[param].next; }
    var capture_param = parameter_count;
    for capture in m.captures {
        if capture.function == function { f.slots[capture.symbol] = capture_param; capture_param++; }
    }
    for symbol, i in p.symbols {
        if symbol.owner == function && function >= 0 && (symbol.flags & (S_FUNCTION | S_TYPE | S_GLOBAL | S_BUILTIN)) == 0 {
            let size = cg_size(p, symbol.type_id);
            if size <= 0 { cg_fail(p, symbol.node, "wasm: variable has no physical layout"); continue; }
            f.slots[i] = cg_local(f, 0x7f); f.offsets[i] = cg_frame(f, size, p.types[symbol.type_id].align);
        }
    }
    var destination = destination_start;
    for id in results {
        f.results.push(cg_local(f, cg_wasm_type(p, id)));
        if cg_aggregate(p, id) { f.destinations.push(destination); destination++; } else { f.destinations.push(-1); }
    }
    var mailbox_size = 16;
    for id in results { mailbox_size = cg_align(mailbox_size, 8) + cg_size(p, id); }
    if !m.scalar { f.effect = cg_frame(f, mailbox_size, 8); }
}
fn cg_emit_prelude(p: Program&, m: CgModule&, f: CgBody&) {
    if m.scalar { if !f.frame_free { wb_op(f.code, 0x23, 0); cg_set(f, f.frame); } return; }
    wb_op(f.code, 0x23, 0); cg_set(f, f.frame);
    cg_get(f, f.frame); wb_i32(f.code, cg_align(f.frame_bytes, 8)); wb_byte(f.code, 0x6a); let top = cg_save(f, 0x7f);
    cg_get(f, top); cg_get(f, f.frame); wb_byte(f.code, 0x49); cg_get(f, top); wb_i32(f.code, m.stack_limit); wb_byte(f.code, 0x4b); wb_byte(f.code, 0x72);
    cg_trap_if(p, m, f, f.function, "activation stack exhausted"); cg_ensure_memory(p, m, f, top, f.function);
    cg_get(f, top); wb_op(f.code, 0x24, 0);
    for offset, symbol in f.offsets {
        if offset >= 0 { cg_frame_address(f, offset); cg_set(f, f.slots[symbol]); }
    }
    cg_frame_address(f, f.effect); wb_op(f.code, 0x23, 4); wb_mem(f.code, 0x36, 2, 0);
    cg_frame_address(f, f.effect); wb_i32(f.code, f.function + 1); wb_mem(f.code, 0x36, 2, 4);
    cg_frame_address(f, f.effect); wb_op(f.code, 0x24, 4);
}
fn cg_parameter_copies(p: Program&, m: CgModule&, f: CgBody&) {
    if f.function < 0 { return; } var param = p.nodes[f.function].first; var index = 0;
    while param >= 0 {
        let symbol = p.nodes[param].symbol;
        if symbol < 0 { cg_fail(p, param, "wasm: parameter has no storage symbol"); return; }
        cg_get(f, index); cg_write_value(p, m, f, p.nodes[param].type_id, f.slots[symbol], param);
        param = p.nodes[param].next; index++;
    }
}
fn cg_emit_epilogue(p: Program&, m: CgModule&, f: CgBody&) {
    if m.scalar {
        if !f.frame_free { cg_get(f, f.frame); wb_op(f.code, 0x24, 0); }
        for result in f.results { cg_get(f, result); } wb_byte(f.code, 0x0b); return;
    }
    var results: i64[>..] = []; if f.function >= 0 { cg_function_results(p, f.function, results); }
    wb_op(f.code, 0x23, 2); cg_frame_address(f, f.effect); wb_byte(f.code, 0x46); cg_begin(f, 0x04, 0x40);
    var offset = 16;
    for id, i in results {
        offset = cg_align(offset, 8); cg_frame_address(f, f.effect + offset); cg_load(p, m, f, id, 0); cg_set(f, f.results[i]); offset += cg_size(p, id);
    }
    wb_i32(f.code, 0); wb_op(f.code, 0x24, 2); cg_end(f);
    cg_frame_address(f, f.effect); wb_mem(f.code, 0x28, 2, 0); wb_op(f.code, 0x24, 4);
    wb_op(f.code, 0x23, 2); wb_byte(f.code, 0x45); cg_begin(f, 0x04, 0x40);
    for id, i in results {
        if f.destinations[i] >= 0 { cg_copy(p, m, f, id, f.destinations[i], f.results[i], f.function); cg_get(f, f.destinations[i]); cg_set(f, f.results[i]); }
    }
    cg_end(f); cg_get(f, f.frame); wb_op(f.code, 0x24, 0);
    for result in f.results { cg_get(f, result); } wb_byte(f.code, 0x0b);
}
fn cg_emit_function(p: Program&, m: CgModule&, function: i64, out: u8[>..]&) {
    var code: u8[>..] = []; var locals: i64[>..] = []; var slots: i64[>..] = []; var offsets: i64[>..] = [];
    var labels: i64[>..] = []; var exits: CgExit[>..] = []; var results: i64[>..] = []; var destinations: i64[>..] = []; var work: i64[>..] = [];
    var f = CgBody { code: code, locals: locals, slots: slots, offsets: offsets, labels: labels, exits: exits, results: results, destinations: destinations, work: work, function: function };
    cg_prepare_function(p, m, f, function);
    if m.scalar && function >= 0 { f.frame_free = !cg_scalar_prints(p, p.nodes[function].right); }
    f.done = cg_begin(f, 0x02, 0x40);
    if function >= 0 {
        cg_parameter_copies(p, m, f); let id = cg_result_type(p, function); var first = -1; if f.results.len > 0 { first = f.results[0]; }
        cg_block_into(p, m, f, p.nodes[function].right, id, first);
    } else {
        for symbol in p.symbols { if (symbol.flags & S_GLOBAL) != 0 && symbol.node >= 0 { cg_declaration(p, m, f, symbol.node); } }
        if p.entry < 0 { if !p.library { cg_fail(p, -1, "wasm: program has no checked main function"); } }
        else {
            let symbol = p.nodes[p.entry].symbol; let index = cg_function(m, symbol);
            if index < 0 { cg_fail(p, p.entry, "wasm: main function is not emitted"); }
            else { wb_op(f.code, 0x10, m.functions[index].index); cg_drop_type(p, f, cg_result_type(p, p.entry)); }
        }
    }
    cg_end(f); cg_emit_epilogue(p, m, f);
    // Frame size includes literals and call snapshots discovered recursively.
    // Emit the reservation only after that size has become final.
    var body: u8[>..] = []; body.append(code); code.clear(); cg_emit_prelude(p, m, f); code.append(body);
    if m.scalar { wb_compact_body(out, locals, code, f.params); }
    else { wb_body(out, locals, code); }
}
fn cg_allocator_body(out: u8[>..]&) {
    // (bytes:i32)->i32. global 1 is the aligned persistent arena cursor.
    wb_u(out, 1); wb_u(out, 2); wb_byte(out, 0x7f);
    wb_op(out, 0x23, 1); wb_op(out, 0x21, 1);
    wb_op(out, 0x20, 1); wb_op(out, 0x20, 0); wb_byte(out, 0x6a); wb_i32(out, 7); wb_byte(out, 0x6a); wb_i32(out, -8); wb_byte(out, 0x71); wb_op(out, 0x22, 2);
    wb_op(out, 0x20, 1); wb_byte(out, 0x49); wb_byte(out, 0x04); wb_byte(out, 0x40); wb_byte(out, 0); wb_byte(out, 0x0b);
    wb_op(out, 0x20, 2); wb_op(out, 0x3f, 0); wb_i32(out, 16); wb_byte(out, 0x74); wb_byte(out, 0x4b); wb_byte(out, 0x04); wb_byte(out, 0x40);
    wb_op(out, 0x20, 2); wb_i32(out, 16); wb_byte(out, 0x76); wb_op(out, 0x20, 2); wb_i32(out, 65535); wb_byte(out, 0x71); wb_byte(out, 0x45); wb_byte(out, 0x45); wb_byte(out, 0x6a);
    wb_op(out, 0x3f, 0); wb_byte(out, 0x6b); wb_op(out, 0x40, 0); wb_i32(out, -1); wb_byte(out, 0x46); wb_byte(out, 0x04); wb_byte(out, 0x40); wb_byte(out, 0); wb_byte(out, 0x0b); wb_byte(out, 0x0b);
    wb_op(out, 0x20, 2); wb_op(out, 0x24, 1); wb_op(out, 0x20, 1); wb_byte(out, 0x0b);
}
fn cg_float_wrap_body(out: u8[>..]&) {
    // Exact IEEE-754 exponent/mantissa decomposition implements Goose casts,
    // including modulo 2^64 for huge finite values and zero for nonfinite ones.
    wb_u(out, 2); wb_u(out, 3); wb_byte(out, 0x7e); wb_u(out, 1); wb_byte(out, 0x7f);
    wb_op(out, 0x20, 0); wb_byte(out, 0xbd); wb_op(out, 0x21, 1);
    wb_op(out, 0x20, 1); wb_i64(out, 52); wb_byte(out, 0x88); wb_i64(out, 2047); wb_byte(out, 0x83); wb_byte(out, 0xa7); wb_i32(out, 1023); wb_byte(out, 0x6b); wb_op(out, 0x21, 4);
    wb_op(out, 0x20, 4); wb_i32(out, 0); wb_byte(out, 0x48); wb_op(out, 0x20, 4); wb_i32(out, 116); wb_byte(out, 0x4e); wb_byte(out, 0x72);
    wb_byte(out, 0x04); wb_byte(out, 0x7e); wb_i64(out, 0); wb_byte(out, 0x05);
    wb_op(out, 0x20, 1); wb_i64(out, 4503599627370495); wb_byte(out, 0x83); wb_i64(out, 4503599627370496); wb_byte(out, 0x84); wb_op(out, 0x21, 2);
    wb_op(out, 0x20, 4); wb_i32(out, 52); wb_byte(out, 0x48); wb_byte(out, 0x04); wb_byte(out, 0x7e);
    wb_op(out, 0x20, 2); wb_i32(out, 52); wb_op(out, 0x20, 4); wb_byte(out, 0x6b); wb_byte(out, 0xad); wb_byte(out, 0x88);
    wb_byte(out, 0x05); wb_op(out, 0x20, 2); wb_op(out, 0x20, 4); wb_i32(out, 52); wb_byte(out, 0x6b); wb_byte(out, 0xad); wb_byte(out, 0x86); wb_byte(out, 0x0b); wb_op(out, 0x21, 3);
    wb_op(out, 0x20, 1); wb_i64(out, 0); wb_byte(out, 0x53); wb_byte(out, 0x04); wb_byte(out, 0x7e); wb_i64(out, 0); wb_op(out, 0x20, 3); wb_byte(out, 0x7d);
    wb_byte(out, 0x05); wb_op(out, 0x20, 3); wb_byte(out, 0x0b); wb_byte(out, 0x0b); wb_byte(out, 0x0b);
}
fn cg_emit_thunk(p: Program&, m: CgModule&, function_index: i64, out: u8[>..]&) {
    let item = m.functions[function_index]; var code: u8[>..] = []; var no_locals: i64[>..] = [];
    var param = p.nodes[item.node].first; var count = 0;
    while param >= 0 { wb_op(code, 0x20, count + 1); count++; param = p.nodes[param].next; }
    var capture_offset = 0;
    for capture in m.captures {
        if capture.function == item.node { wb_op(code, 0x20, 0); wb_mem(code, 0x28, 2, capture_offset); capture_offset += 4; }
    }
    var results: i64[>..] = []; cg_function_results(p, item.node, results);
    var destination = count + 1;
    for id in results { if cg_aggregate(p, id) { wb_op(code, 0x20, destination); destination++; } }
    wb_op(code, 0x10, item.index); wb_byte(code, 0x0b); wb_body(out, no_locals, code);
}
recursive fn cg_propagate_captures(p: Program&, m: CgModule&, function: i64, node: i64) {
    if node < 0 { return; } let n = p.nodes[node];
    if (n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE) && node != function { return; }
    if (n.kind == N_CALL || n.kind == N_FUNCTION_VALUE || n.kind == N_NAME) && n.symbol >= 0 && (p.symbols[n.symbol].flags & S_FUNCTION) != 0 {
        let target = p.symbols[n.symbol].node; let count = m.captures.len;
        for i in 0..count {
            let capture = m.captures[i];
            if capture.function == target && p.symbols[capture.symbol].owner != function && !cg_capture(m, function, capture.symbol) {
                m.captures.push(CgCapture { function: function, symbol: capture.symbol });
            }
        }
    }
    cg_propagate_captures(p, m, function, n.left); cg_propagate_captures(p, m, function, n.right); cg_propagate_captures(p, m, function, n.third);
    var child = n.first; while child >= 0 { cg_propagate_captures(p, m, function, child); child = p.nodes[child].next; }
}
fn cg_host_signature(m: CgModule&, host: i64) -> i64 {
    var args: u8[>..] = []; var results: u8[>..] = [];
    if host == CG_WRITE { args.push(0x7f); args.push(0x7f); }
    else if host == CG_PRINT_I64 || host == CG_PRINT_U64 { args.push(0x7e); }
    else if host == CG_PRINT_F64 { args.push(0x7c); }
    else if host == CG_PRINT_F32 { args.push(0x7d); }
    else if host == CG_PRINT_BOOL || host == CG_EXIT { args.push(0x7f); }
    else if host == CG_ABORT { args.push(0x7f); args.push(0x7f); args.push(0x7f); }
    return cg_signature(m, args, results);
}
fn cg_host_name(host: i64) -> u8[:] {
    if host == CG_WRITE { return "write"; } if host == CG_PRINT_I64 { return "print_i64"; }
    if host == CG_PRINT_U64 { return "print_u64"; } if host == CG_PRINT_F64 { return "print_f64"; }
    if host == CG_PRINT_F32 { return "print_f32"; } if host == CG_PRINT_BOOL { return "print_bool"; }
    if host == CG_NEWLINE { return "newline"; } if host == CG_ABORT { return "abort"; } return "exit";
}
fn cg_external_name(p: Program&, function: i64) -> u8[:] {
    let token = p.nodes[function].integer;
    if token >= 0 && token < p.tokens.len && p.tokens[token].kind == T_STRLIT {
        let t = p.tokens[token]; return p.text[t.text_start..t.text_start + t.text_len];
    }
    return token_text(p, p.nodes[function].token);
}
fn cg_collect(p: Program&, m: CgModule&) {
    for host in 0..9 { m.imports.push(CgImport { signature: cg_host_signature(m, host), host: host }); }
    for symbol, i in p.symbols {
        m.globals.push(-1);
        if (symbol.flags & S_GLOBAL) != 0 && symbol.type_id >= 0 {
            m.next_data = cg_align(m.next_data, p.types[symbol.type_id].align); m.globals[i] = m.next_data; m.next_data += cg_size(p, symbol.type_id);
        }
    }
    for n, node in p.nodes {
        if n.kind != N_FUNCTION && n.kind != N_FUNCTION_VALUE || n.symbol < 0 || (n.flags & F_GENERIC) != 0 || (n.flags & F_CHECKED) == 0 { continue; }
        if (n.flags & F_THREAD) != 0 { cg_fail(p, node, "wasm: threads are unsupported by the direct host ABI"); }
        if (n.flags & F_EXTERN) != 0 {
            if n.aux >= 0 { cg_fail(p, node, "wasm: dynamic-library externs are unsupported"); }
            cg_exportable(p, node);
            if cg_intrinsic(p, node) == 0 { m.imports.push(CgImport { symbol: n.symbol, signature: cg_make_signature(p, m, node, false) }); }
        } else { m.functions.push(CgFunction { node: node, symbol: n.symbol }); }
    }
    for item in m.functions { cg_scan_captures(p, m, item.node, p.nodes[item.node].right); }
    loop {
        let count = m.captures.len;
        for item in m.functions { cg_propagate_captures(p, m, item.node, p.nodes[item.node].right); }
        if count == m.captures.len { break; }
    }
    for item, i in m.functions {
        var count = 0; for capture in m.captures { if capture.function == item.node { count++; } }
        m.functions[i].capture_count = count;
        m.functions[i].signature = cg_make_signature(p, m, item.node, false);
        m.functions[i].closure_signature = cg_make_signature(p, m, item.node, true);
        m.functions[i].index = m.imports.len + i;
    }
    m.start = m.imports.len + m.functions.len; m.allocator = m.start + 1; m.float_wrap = m.start + 2;
    for item, i in m.functions { m.functions[i].thunk = m.start + 3 + i; }
    if m.functions.len == 1 && m.imports.len == 9 && p.entry == m.functions[0].node && m.functions[0].capture_count == 0 {
        let entry = m.functions[0].node;
        var globals = false; for address in m.globals { if address >= 0 { globals = true; } }
        if !globals && (p.nodes[entry].flags & F_NONLOCAL) == 0 && p.nodes[entry].first < 0 && cg_result_type(p, entry) == TYPE_VOID && cg_scalar_body(p, entry, p.nodes[entry].right) { m.scalar = true; }
    }
}
fn cg_module_globals(p: Program&, m: CgModule&, out: u8[>..]&) {
    var count = 5; if m.scalar { count = 1; }
    wb_u(out, count);
    for index in 0..count {
        wb_byte(out, 0x7f); wb_byte(out, 1);
        var initial = 0; if index == 0 { initial = cg_align(m.next_data, 8); if m.scalar { initial = cg_align(m.next_data, 16); } } if index == 1 { initial = m.stack_limit; }
        wb_i32(out, initial); wb_byte(out, 0x0b);
    }
}
fn cg_exportable(p: Program&, function: i64) -> bool {
    var param = p.nodes[function].first;
    while param >= 0 {
        let kind = cg_type_kind(p, p.nodes[param].type_id);
        if kind != TY_INT && kind != TY_FLOAT && kind != TY_BOOL { cg_fail(p, function, "wasm: public exports accept numeric and bool values only"); return false; }
        param = p.nodes[param].next;
    }
    var results: i64[>..] = []; cg_function_results(p, function, results);
    for id in results { let kind = cg_type_kind(p, id); if kind != TY_INT && kind != TY_FLOAT && kind != TY_BOOL { cg_fail(p, function, "wasm: public exports return numeric and bool values only"); return false; } }
    return true;
}
fn generate_wasm(p: Program&, out: u8[>..]&) {
    if p.diagnostics.len > 0 { return; }
    if p.initial_pages < 1 || p.initial_pages > p.maximum_pages || p.maximum_pages > 65535 {
        cg_fail(p, -1, "wasm: linear memory requires 1 <= initial_pages <= maximum_pages <= 65535"); return;
    }
    if p.pointer_bytes != 4 { cg_fail(p, -1, "wasm: checked layout must use memory32 pointers"); return; }
    var functions: CgFunction[>..] = []; var captures: CgCapture[>..] = []; var imports: CgImport[>..] = [];
    var signatures: CgSignature[>..] = []; var signature_bytes: u8[>..] = []; var segments: CgSegment[>..] = []; var data: u8[>..] = []; var globals: i64[>..] = [];
    var m = CgModule { functions: functions, captures: captures, imports: imports, signatures: signatures, signature_bytes: signature_bytes, segments: segments, data: data, globals: globals,
        stack_limit: (p.maximum_pages * 65536 / 2) & -8 };
    cg_collect(p, m); if p.diagnostics.len > 0 { return; }
    var body_count = m.functions.len * 2 + 3; if m.scalar { body_count = m.functions.len + 1; }
    var code: u8[>..] = []; wb_u(code, body_count);
    var body: u8[>..] = [];
    for item in m.functions { body.clear(); cg_emit_function(p, m, item.node, body); wb_u(code, body.len); wb_raw(code, body); }
    body.clear(); cg_emit_function(p, m, -1, body); wb_u(code, body.len); wb_raw(code, body);
    if !m.scalar {
        body.clear(); cg_allocator_body(body); wb_u(code, body.len); wb_raw(code, body);
        body.clear(); cg_float_wrap_body(body); wb_u(code, body.len); wb_raw(code, body);
        for item, i in m.functions { body.clear(); cg_emit_thunk(p, m, i, body); wb_u(code, body.len); wb_raw(code, body); }
    }
    if m.next_data >= m.stack_limit { cg_fail(p, -1, "wasm: static storage overlaps the activation arena"); }
    if p.diagnostics.len > 0 { return; }
    var empty: u8[>..] = []; var one_i32: u8[>..] = [0x7f]; var one_i64: u8[>..] = [0x7e]; var one_f64: u8[>..] = [0x7c];
    let start_signature = cg_signature(m, empty, empty); var allocator_signature = -1; var wrap_signature = -1;
    if !m.scalar { allocator_signature = cg_signature(m, one_i32, one_i32); wrap_signature = cg_signature(m, one_f64, one_i64); }
    var module: u8[>..] = [0, 97, 115, 109, 1, 0, 0, 0]; var section: u8[>..] = [];
    wb_u(section, m.signatures.len);
    for sig in m.signatures { wb_raw(section, m.signature_bytes[sig.start..sig.start + sig.count]); } wb_section(module, 1, section); section.clear();
    wb_u(section, m.imports.len);
    for item in m.imports {
        if item.host >= 0 { wb_import(section, "goose", cg_host_name(item.host), item.signature); }
        else { wb_import(section, "env", cg_external_name(p, p.symbols[item.symbol].node), item.signature); }
    }
    wb_section(module, 2, section); section.clear();
    wb_u(section, body_count); for item in m.functions { wb_u(section, item.signature); }
    wb_u(section, start_signature);
    if !m.scalar { wb_u(section, allocator_signature); wb_u(section, wrap_signature); for item in m.functions { wb_u(section, item.closure_signature); } }
    wb_section(module, 3, section); section.clear();
    if !m.scalar { wb_u(section, 1); wb_byte(section, 0x70); wb_byte(section, 0); wb_u(section, m.functions.len); wb_section(module, 4, section); section.clear(); }
    var initial_pages = p.initial_pages; let static_pages = (m.next_data + 65535) / 65536;
    if initial_pages < static_pages { initial_pages = static_pages; }
    wb_u(section, 1); wb_byte(section, 1); wb_u(section, initial_pages); wb_u(section, p.maximum_pages); wb_section(module, 5, section); section.clear();
    cg_module_globals(p, m, section); wb_section(module, 6, section); section.clear();
    var export_count = 2; for item in m.functions { if (p.nodes[item.node].flags & F_EXPORT) != 0 { export_count++; } }
    wb_u(section, export_count); wb_export(section, "memory", 2, 0); wb_export(section, "_start", 0, m.start);
    for item in m.functions {
        if (p.nodes[item.node].flags & F_EXPORT) != 0 {
            if item.capture_count > 0 { cg_fail(p, item.node, "wasm: public entrypoints cannot capture local storage"); }
            cg_exportable(p, item.node); wb_export(section, cg_external_name(p, item.node), 0, item.index);
        }
    }
    wb_section(module, 7, section); section.clear();
    if !m.scalar {
        wb_u(section, 1); wb_u(section, 0); wb_i32(section, 0); wb_byte(section, 0x0b); wb_u(section, m.functions.len);
        for item in m.functions { wb_u(section, item.thunk); } wb_section(module, 9, section); section.clear();
    }
    wb_section(module, 10, code);
    wb_u(section, m.segments.len);
    for segment in m.segments {
        wb_u(section, 0); wb_i32(section, segment.address); wb_byte(section, 0x0b); wb_u(section, segment.count); wb_raw(section, m.data[segment.start..segment.start + segment.count]);
    }
    wb_section(module, 11, section); section.clear();
    if m.scalar { cg_scalar_metadata(p, m, module); }
    else if p.debug {
        wb_name(section, "name"); var names: u8[>..] = []; wb_u(names, m.imports.len + m.functions.len + 3);
        for item, i in m.imports { wb_u(names, i); if item.host >= 0 { wb_name(names, cg_host_name(item.host)); } else { wb_name(names, cg_external_name(p, p.symbols[item.symbol].node)); } }
        for item in m.functions { wb_u(names, item.index); wb_name(names, token_text(p, p.nodes[item.node].token)); }
        wb_u(names, m.start); wb_name(names, "_start"); wb_u(names, m.allocator); wb_name(names, "goose.allocate"); wb_u(names, m.float_wrap); wb_name(names, "goose.float_wrap");
        wb_byte(section, 1); wb_u(section, names.len); wb_raw(section, names); wb_section(module, 0, section);
    }
    if p.diagnostics.len == 0 { out.append(module); }
}

struct CgDecoded { value: i64, cursor: i64 }
fn cg_read_uleb(p: Program&, m: CgModule&, f: CgBody&, address: i64, node: i64) -> CgDecoded {
    cg_get(f, address); let cursor = cg_save(f, 0x7f); wb_i64(f.code, 0); let value = cg_save(f, 0x7e); wb_i32(f.code, 0); let shift = cg_save(f, 0x7f);
    let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
    cg_get(f, cursor); wb_byte(f.code, 0xad); wb_op(f.code, 0x3f, 0); wb_byte(f.code, 0xad); wb_i64(f.code, 65536); wb_byte(f.code, 0x7e); wb_byte(f.code, 0x5a);
    cg_trap_if(p, m, f, node, "truncated varint image");
    cg_get(f, cursor); wb_mem(f.code, 0x2d, 0, 0); let byte = cg_save(f, 0x7f);
    cg_get(f, shift); wb_i32(f.code, 63); wb_byte(f.code, 0x4b);
    cg_get(f, shift); wb_i32(f.code, 63); wb_byte(f.code, 0x46); cg_get(f, byte); wb_i32(f.code, 254); wb_byte(f.code, 0x71); wb_byte(f.code, 0x45); wb_byte(f.code, 0x45); wb_byte(f.code, 0x71); wb_byte(f.code, 0x72);
    cg_trap_if(p, m, f, node, "varint image exceeds 64 bits");
    cg_get(f, value); cg_get(f, byte); wb_i32(f.code, 127); wb_byte(f.code, 0x71); wb_byte(f.code, 0xad); cg_get(f, shift); wb_byte(f.code, 0xad); wb_byte(f.code, 0x86); wb_byte(f.code, 0x84); cg_set(f, value);
    cg_get(f, cursor); wb_i32(f.code, 1); wb_byte(f.code, 0x6a); cg_set(f, cursor);
    cg_get(f, byte); wb_i32(f.code, 128); wb_byte(f.code, 0x71); wb_byte(f.code, 0x45); cg_branch(p, f, done, true);
    cg_get(f, shift); wb_i32(f.code, 7); wb_byte(f.code, 0x6a); cg_set(f, shift); cg_branch(p, f, again, false); cg_end(f); cg_end(f);
    return CgDecoded { value: value, cursor: cursor };
}
fn cg_load(p: Program&, m: CgModule&, f: CgBody&, id: i64, offset: i64) -> bool {
    if id < 0 || id >= p.types.len { return false; }
    if p.types[id].storage == 1 {
        if offset != 0 { wb_i32(f.code, offset); wb_byte(f.code, 0x6a); }
        let address = cg_save(f, 0x7f); let decoded = cg_read_uleb(p, m, f, address, -1);
        cg_get(f, decoded.value); wb_i64(f.code, 1); wb_byte(f.code, 0x88);
        wb_i64(f.code, 0); cg_get(f, decoded.value); wb_i64(f.code, 1); wb_byte(f.code, 0x83); wb_byte(f.code, 0x7d); wb_byte(f.code, 0x85); return true;
    }
    return cg_load_fixed(p, f.code, id, offset);
}
fn cg_write_uleb(p: Program&, f: CgBody&, address: i64, value: i64) -> i64 {
    cg_get(f, address); let cursor = cg_save(f, 0x7f); cg_get(f, value); let remaining = cg_save(f, 0x7e);
    let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
    cg_get(f, remaining); wb_byte(f.code, 0xa7); wb_i32(f.code, 127); wb_byte(f.code, 0x71); let byte = cg_save(f, 0x7f);
    cg_get(f, remaining); wb_i64(f.code, 7); wb_byte(f.code, 0x88); cg_set(f, remaining);
    cg_get(f, remaining); wb_i64(f.code, 0); wb_byte(f.code, 0x52); cg_begin(f, 0x04, 0x40); cg_get(f, byte); wb_i32(f.code, 128); wb_byte(f.code, 0x72); cg_set(f, byte); cg_end(f);
    cg_get(f, cursor); cg_get(f, byte); wb_mem(f.code, 0x3a, 0, 0); cg_get(f, cursor); wb_i32(f.code, 1); wb_byte(f.code, 0x6a); cg_set(f, cursor);
    cg_get(f, remaining); wb_byte(f.code, 0x50); cg_branch(p, f, done, true); cg_branch(p, f, again, false); cg_end(f); cg_end(f); return cursor;
}
fn cg_write_varint(p: Program&, f: CgBody&, address: i64, value: i64) -> i64 {
    cg_get(f, value); wb_i64(f.code, 1); wb_byte(f.code, 0x86); cg_get(f, value); wb_i64(f.code, 63); wb_byte(f.code, 0x87); wb_byte(f.code, 0x85);
    let encoded = cg_save(f, 0x7e); return cg_write_uleb(p, f, address, encoded);
}
fn cg_walk_elements(p: Program&, m: CgModule&, f: CgBody&, base: i64, count: i64, node: i64) -> i64 {
    cg_get(f, base); let cursor = cg_save(f, 0x7f); wb_i64(f.code, 0); let index = cg_save(f, 0x7e);
    let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
    cg_get(f, index); cg_get(f, count); wb_byte(f.code, 0x5a); cg_branch(p, f, done, true);
    let decoded = cg_read_uleb(p, m, f, cursor, node); cg_get(f, decoded.cursor); cg_set(f, cursor);
    cg_get(f, index); wb_i64(f.code, 1); wb_byte(f.code, 0x7c); cg_set(f, index); cg_branch(p, f, again, false); cg_end(f); cg_end(f); return cursor;
}
recursive fn cg_array_from_view(p: Program&, m: CgModule&, f: CgBody&, to: i64, node: i64) {
    let view = cg_save(f, 0x7e); let destination = cg_temporary(p, f, to); let element = p.types[to].element;
    cg_get(f, view); wb_i64(f.code, 32); wb_byte(f.code, 0x88); wb_byte(f.code, 0xa7); let count = cg_save(f, 0x7f);
    cg_get(f, destination); wb_i32(f.code, 0); wb_i32(f.code, cg_size(p, to)); wb_fill(f.code);
    var pointer = destination;
    if cg_owner(p, to) { pointer = cg_owner_image(p, m, f, to, destination, count, count, node);
    } else {
        cg_get(f, count); wb_i32(f.code, p.types[to].count); wb_byte(f.code, 0x4b); cg_trap_if(p, m, f, node, "array capacity exceeded");
        if p.types[to].array_kind == A_LIMITED { cg_get(f, destination); cg_get(f, count); cg_length_store(p, f, to); }
        cg_get(f, destination); wb_i32(f.code, cg_static_prefix(p, to)); wb_byte(f.code, 0x6a); pointer = cg_save(f, 0x7f);
    }
    cg_get(f, view); wb_byte(f.code, 0xa7); let source = cg_save(f, 0x7f);
    var bytes = -1;
    if p.types[element].storage == 1 {
        cg_get(f, count); wb_byte(f.code, 0xad); let count64 = cg_save(f, 0x7e); let end = cg_walk_elements(p, m, f, source, count64, node);
        cg_get(f, end); cg_get(f, source); wb_byte(f.code, 0x6b); bytes = cg_save(f, 0x7f);
    } else { cg_get(f, count); wb_i32(f.code, cg_size(p, element)); wb_byte(f.code, 0x6c); bytes = cg_save(f, 0x7f); }
    cg_get(f, pointer); cg_get(f, source); cg_get(f, bytes); wb_copy(f.code);
    if cg_owner(p, to) && p.types[to].array_kind != A_VAR { cg_get(f, destination); cg_get(f, pointer); cg_get(f, bytes); wb_byte(f.code, 0x6a); wb_mem(f.code, 0x36, 2, 16); }
    cg_get(f, destination);
}
recursive fn cg_multi_assignment(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n = p.nodes[node]; let mark = f.work.len; var target = n.first;
    while target >= 0 {
        cg_address(p, m, f, target); let address = cg_save(f, 0x7f); let id = p.nodes[target].type_id; let value = cg_local(f, cg_wasm_type(p, id));
        f.work.push(address); f.work.push(id); f.work.push(value); target = p.nodes[target].next;
    }
    let end = f.work.len; cg_expr(p, m, f, n.right); var at = end;
    while at > mark { at -= 3; cg_set(f, f.work[at + 2]); }
    at = mark;
    while at < end { let id = f.work[at + 1]; let address = f.work[at]; let value = f.work[at + 2]; cg_get(f, value); cg_write_value(p, m, f, id, address, node); at += 3; }
    f.work.resize(mark);
}
fn cg_uleb_width(p: Program&, f: CgBody&, value: i64) -> i64 {
    cg_get(f, value); let remaining = cg_save(f, 0x7e); wb_i32(f.code, 1); let width = cg_save(f, 0x7f);
    let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
    cg_get(f, remaining); wb_i64(f.code, 128); wb_byte(f.code, 0x54); cg_branch(p, f, done, true);
    cg_get(f, remaining); wb_i64(f.code, 7); wb_byte(f.code, 0x88); cg_set(f, remaining);
    cg_get(f, width); wb_i32(f.code, 1); wb_byte(f.code, 0x6a); cg_set(f, width); cg_branch(p, f, again, false); cg_end(f); cg_end(f); return width;
}
fn cg_owner_read_length(p: Program&, m: CgModule&, f: CgBody&, header: i64, node: i64) {
    cg_get(f, header); wb_mem(f.code, 0x28, 2, 20); let mode = cg_save(f, 0x7f);
    cg_get(f, header); wb_mem(f.code, 0x28, 2, 4); let result = cg_save(f, 0x7f);
    let done = cg_begin(f, 0x02, 0x40);
    for selected in 1..7 {
        cg_get(f, mode); wb_i32(f.code, selected); wb_byte(f.code, 0x46); cg_begin(f, 0x04, 0x40);
        cg_get(f, header); wb_mem(f.code, 0x28, 2, 16); let image = cg_save(f, 0x7f);
        if selected == 6 {
            let decoded = cg_read_uleb(p, m, f, image, node); cg_get(f, decoded.value); wb_i64(f.code, 4294967295); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array image length exceeds wasm32 range");
            cg_get(f, decoded.value); wb_byte(f.code, 0xa7);
        } else {
            cg_get(f, image);
            if selected == 1 { wb_mem(f.code, 0x2d, 0, 0); } else if selected == 2 { wb_mem(f.code, 0x2f, 0, 0); }
            else if selected == 3 { wb_mem(f.code, 0x28, 0, 0); } else if selected == 5 { wb_mem(f.code, 0x28, 0, 4); }
            else {
                wb_mem(f.code, 0x29, 0, 0); let value = cg_save(f, 0x7e); cg_get(f, value); wb_i64(f.code, 4294967295); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array image length exceeds wasm32 range"); cg_get(f, value); wb_byte(f.code, 0xa7);
            }
        }
        cg_set(f, result); cg_branch(p, f, done, false); cg_end(f);
    }
    cg_end(f); cg_get(f, result);
}
fn cg_owner_read_base(p: Program&, m: CgModule&, f: CgBody&, header: i64, node: i64) {
    cg_get(f, header); wb_mem(f.code, 0x28, 2, 20); let mode = cg_save(f, 0x7f);
    cg_get(f, header); wb_mem(f.code, 0x28, 2, 0); let result = cg_save(f, 0x7f);
    let done = cg_begin(f, 0x02, 0x40);
    for selected in 1..7 {
        cg_get(f, mode); wb_i32(f.code, selected); wb_byte(f.code, 0x46); cg_begin(f, 0x04, 0x40);
        cg_get(f, header); wb_mem(f.code, 0x28, 2, 16); let image = cg_save(f, 0x7f);
        if selected == 6 { let decoded = cg_read_uleb(p, m, f, image, node); cg_get(f, decoded.cursor); }
        else { cg_get(f, image); var width = 1; if selected == 2 { width = 2; } if selected == 3 { width = 4; } if selected == 4 || selected == 5 { width = 8; } wb_i32(f.code, width); wb_byte(f.code, 0x6a); }
        cg_set(f, result); cg_branch(p, f, done, false); cg_end(f);
    }
    cg_end(f); cg_get(f, result);
}
fn cg_owner_read_capacity(p: Program&, m: CgModule&, f: CgBody&, header: i64) {
    cg_get(f, header); wb_mem(f.code, 0x28, 2, 20); wb_i32(f.code, 5); wb_byte(f.code, 0x46); cg_begin(f, 0x04, 0x7f);
    cg_get(f, header); wb_mem(f.code, 0x28, 2, 16); wb_mem(f.code, 0x28, 0, 0);
    wb_byte(f.code, 0x05); cg_get(f, header); wb_mem(f.code, 0x28, 2, 12); cg_end(f);
}
fn cg_owner_image(p: Program&, m: CgModule&, f: CgBody&, id: i64, header: i64, count: i64, capacity: i64, node: i64) -> i64 {
    let element = p.types[id].element; var stride = cg_size(p, element); if p.types[element].storage == 1 { stride = 10; }
    var mode = 0; var prefix_bytes = 0;
    if p.types[id].array_kind == A_VAR {
        let bytes = p.types[id].length_storage;
        if bytes == 0 { mode = 6; }
        else if bytes == 1 { mode = 1; prefix_bytes = 1; }
        else if bytes == 2 { mode = 2; prefix_bytes = 2; }
        else if bytes == 4 { mode = 3; prefix_bytes = 4; }
        else { mode = 4; prefix_bytes = 8; }
    }
    if p.types[id].array_kind == A_LIMITED { mode = 5; prefix_bytes = 8; }
    var prefix = -1;
    if mode == 6 { cg_get(f, count); wb_byte(f.code, 0xad); let length64 = cg_save(f, 0x7e); prefix = cg_uleb_width(p, f, length64); }
    else { wb_i32(f.code, prefix_bytes); prefix = cg_save(f, 0x7f); }
    cg_get(f, capacity); wb_byte(f.code, 0xad); wb_i64(f.code, stride); wb_byte(f.code, 0x7e); cg_get(f, prefix); wb_byte(f.code, 0xad); wb_byte(f.code, 0x7c); let bytes = cg_save(f, 0x7e);
    cg_get(f, bytes); wb_i64(f.code, 4294967295); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array image byte size overflow");
    cg_get(f, bytes); wb_byte(f.code, 0xa7); wb_op(f.code, 0x10, m.allocator); let image = cg_save(f, 0x7f);
    cg_get(f, image); cg_get(f, prefix); wb_byte(f.code, 0x6a); let pointer = cg_save(f, 0x7f);
    cg_get(f, header); cg_get(f, pointer); wb_mem(f.code, 0x36, 2, 0);
    cg_get(f, header); cg_get(f, count); wb_mem(f.code, 0x36, 2, 4);
    cg_get(f, header); cg_get(f, image); cg_get(f, bytes); wb_byte(f.code, 0xa7); wb_byte(f.code, 0x6a); wb_mem(f.code, 0x36, 2, 8);
    cg_get(f, header); if mode == 6 { cg_get(f, prefix); } else { cg_get(f, capacity); } wb_mem(f.code, 0x36, 2, 12);
    cg_get(f, header); cg_get(f, image); wb_mem(f.code, 0x36, 2, 16); cg_get(f, header); wb_i32(f.code, mode); wb_mem(f.code, 0x36, 2, 20);
    if mode == 6 { cg_get(f, count); wb_byte(f.code, 0xad); let length = cg_save(f, 0x7e); cg_write_uleb(p, f, image, length); }
    else if mode != 0 {
        cg_get(f, image);
        if mode == 5 { cg_get(f, capacity); wb_mem(f.code, 0x36, 0, 0); cg_get(f, image); cg_get(f, count); wb_mem(f.code, 0x36, 0, 4); }
        else { cg_get(f, count); if mode == 1 { wb_mem(f.code, 0x3a, 0, 0); } else if mode == 2 { wb_mem(f.code, 0x3b, 0, 0); } else if mode == 3 { wb_mem(f.code, 0x36, 0, 0); } else { wb_byte(f.code, 0xad); wb_mem(f.code, 0x37, 0, 0); } }
    }
    return pointer;
}
fn cg_owner_set_length(p: Program&, m: CgModule&, f: CgBody&, header: i64, count: i64, node: i64) {
    cg_get(f, header); cg_get(f, count); wb_mem(f.code, 0x36, 2, 4);
    cg_get(f, header); wb_mem(f.code, 0x28, 2, 20); let mode = cg_save(f, 0x7f); let done = cg_begin(f, 0x02, 0x40);
    for selected in 1..7 {
        cg_get(f, mode); wb_i32(f.code, selected); wb_byte(f.code, 0x46); cg_begin(f, 0x04, 0x40);
        cg_get(f, header); wb_mem(f.code, 0x28, 2, 16); let image = cg_save(f, 0x7f);
        if selected == 6 {
            cg_get(f, count); wb_byte(f.code, 0xad); let value = cg_save(f, 0x7e); let width = cg_uleb_width(p, f, value);
            cg_get(f, width); cg_get(f, header); wb_mem(f.code, 0x28, 2, 12); wb_byte(f.code, 0x47); cg_trap_if(p, m, f, node, "immutable array length changed its prefix width"); cg_write_uleb(p, f, image, value);
        } else {
            cg_get(f, image); cg_get(f, count);
            if selected == 1 { wb_mem(f.code, 0x3a, 0, 0); } else if selected == 2 { wb_mem(f.code, 0x3b, 0, 0); } else if selected == 3 { wb_mem(f.code, 0x36, 0, 0); }
            else if selected == 5 { wb_mem(f.code, 0x36, 0, 4); } else { wb_byte(f.code, 0xad); wb_mem(f.code, 0x37, 0, 0); }
        }
        cg_branch(p, f, done, false); cg_end(f);
    }
    cg_end(f);
}
recursive fn cg_encoded_array_initializers(p: Program&, m: CgModule&, f: CgBody&, node: i64, header: i64, pointer: i64, count: i64) {
    let n = p.nodes[node]; cg_get(f, pointer); let cursor = cg_save(f, 0x7f);
    if n.right >= 0 && n.first >= 0 {
        cg_to(p, m, f, n.first, TYPE_I64); let value = cg_save(f, 0x7e); wb_i32(f.code, 0); let index = cg_save(f, 0x7f);
        let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
        cg_get(f, index); cg_get(f, count); wb_byte(f.code, 0x4f); cg_branch(p, f, done, true);
        let end = cg_write_varint(p, f, cursor, value); cg_get(f, end); cg_set(f, cursor);
        cg_get(f, index); wb_i32(f.code, 1); wb_byte(f.code, 0x6a); cg_set(f, index); cg_branch(p, f, again, false); cg_end(f); cg_end(f);
    } else {
        var child = n.first;
        while child >= 0 {
            cg_to(p, m, f, child, TYPE_I64); let value = cg_save(f, 0x7e); let end = cg_write_varint(p, f, cursor, value);
            cg_get(f, end); cg_set(f, cursor); child = p.nodes[child].next;
        }
    }
    if p.types[n.type_id].array_kind != A_VAR { cg_get(f, header); cg_get(f, cursor); wb_mem(f.code, 0x36, 2, 16); }
}
recursive fn cg_varint_array_builtin(p: Program&, m: CgModule&, f: CgBody&, node: i64, builtin: i64, id: i64, header: i64, arg: i64) {
    if p.types[id].array_kind != A_GROW || builtin != 24 && builtin != 25 && builtin != 29 {
        cg_fail(p, node, "wasm: varint growables support push, append and clear only"); return;
    }
    if builtin == 29 {
        cg_get(f, header); cg_owner_read_base(p, m, f, header, node); wb_mem(f.code, 0x36, 2, 16);
        cg_get(f, header); wb_i32(f.code, 0); wb_mem(f.code, 0x36, 2, 4); return;
    }
    var value = -1; var source = -1; var added = -1; var source_bytes = -1;
    if builtin == 24 { cg_to(p, m, f, arg, TYPE_I64); value = cg_save(f, 0x7e); wb_i32(f.code, 1); added = cg_save(f, 0x7f); }
    else {
        cg_expr(p, m, f, arg); cg_pack_view(p, m, f, p.nodes[arg].type_id, node); let view = cg_save(f, 0x7e);
        cg_get(f, view); wb_byte(f.code, 0xa7); source = cg_save(f, 0x7f); cg_get(f, view); wb_i64(f.code, 32); wb_byte(f.code, 0x88); let count64 = cg_save(f, 0x7e);
        cg_get(f, count64); wb_byte(f.code, 0xa7); added = cg_save(f, 0x7f); let end = cg_walk_elements(p, m, f, source, count64, node);
        cg_get(f, end); cg_get(f, source); wb_byte(f.code, 0x6b); source_bytes = cg_save(f, 0x7f);
    }
    cg_owner_read_length(p, m, f, header, node); let old = cg_save(f, 0x7f);
    cg_get(f, old); cg_get(f, added); wb_byte(f.code, 0x6a); let count = cg_save(f, 0x7f);
    cg_get(f, count); cg_get(f, old); wb_byte(f.code, 0x49); cg_trap_if(p, m, f, node, "array length overflow");
    cg_owner_read_base(p, m, f, header, node); let base = cg_save(f, 0x7f);
    cg_get(f, old); wb_byte(f.code, 0xad); let old64 = cg_save(f, 0x7e); let end = cg_walk_elements(p, m, f, base, old64, node);
    cg_get(f, end); cg_get(f, base); wb_byte(f.code, 0x6b); let old_bytes = cg_save(f, 0x7f);
    cg_get(f, old_bytes); if source_bytes >= 0 { cg_get(f, source_bytes); } else { wb_i32(f.code, 10); } wb_byte(f.code, 0x6a); let capacity = cg_save(f, 0x7f);
    cg_get(f, capacity); wb_op(f.code, 0x10, m.allocator); let copy = cg_save(f, 0x7f);
    cg_get(f, copy); cg_get(f, base); cg_get(f, old_bytes); wb_copy(f.code);
    cg_get(f, copy); cg_get(f, old_bytes); wb_byte(f.code, 0x6a); let destination = cg_save(f, 0x7f); var finish = -1;
    if builtin == 24 { finish = cg_write_varint(p, f, destination, value); }
    else {
        cg_get(f, destination); cg_get(f, source); cg_get(f, source_bytes); wb_copy(f.code); cg_get(f, destination); cg_get(f, source_bytes); wb_byte(f.code, 0x6a); finish = cg_save(f, 0x7f);
    }
    cg_get(f, header); cg_get(f, copy); wb_mem(f.code, 0x36, 2, 0); cg_get(f, header); cg_get(f, count); wb_mem(f.code, 0x36, 2, 4);
    cg_get(f, header); cg_get(f, copy); cg_get(f, capacity); wb_byte(f.code, 0x6a); wb_mem(f.code, 0x36, 2, 8); cg_get(f, header); cg_get(f, finish); wb_mem(f.code, 0x36, 2, 16);
    if builtin == 24 && p.nodes[node].type_id != TYPE_VOID { cg_get(f, destination); }
}
fn cg_const_integer(f: CgBody&, w: i64, value: i64) { if w == 0x7e { wb_i64(f.code, value); } else { wb_i32(f.code, value); } }
recursive fn cg_numeric(p: Program&, m: CgModule&, f: CgBody&, op: i64, id: i64, node: i64) {
    let w = cg_wasm_type(p, id); let unsigned = cg_unsigned(p, id);
    if w == 0x7d || w == 0x7c {
        if op == T_MOD { cg_float_remainder(p, m, f, node, w); return; }
        let opcode = cg_numeric_opcode(op, w, false);
        if opcode == 0 { cg_fail(p, node, "wasm: unsupported floating-point operation"); return; }
        wb_byte(f.code, opcode); return;
    }
    if op == T_SHL || op == T_SHR {
        var bits = 32; if cg_type_kind(p, id) == TY_INT { bits = p.types[id].count; }
        cg_const_integer(f, w, bits - 1); wb_byte(f.code, cg_numeric_opcode(T_BITAND, w, false));
        wb_byte(f.code, cg_numeric_opcode(op, w, unsigned)); cg_normalize(p, f.code, id); return;
    }
    let checked = p.debug && !unsigned && cg_type_kind(p, id) == TY_INT && (op == T_PLUS || op == T_MINUS || op == T_MUL);
    if op != T_DIV && op != T_MOD && !checked {
        let opcode = cg_numeric_opcode(op, w, unsigned);
        if opcode == 0 { cg_fail(p, node, "wasm: unsupported arithmetic or comparison"); return; }
        wb_byte(f.code, opcode);
        if op == T_PLUS || op == T_MINUS || op == T_MUL || op == T_BITAND || op == T_BITOR || op == T_XOR { cg_normalize(p, f.code, id); }
        return;
    }
    let b = cg_save(f, w); let a = cg_save(f, w);
    if op == T_DIV || op == T_MOD {
        cg_get(f, b); if w == 0x7e { wb_byte(f.code, 0x50); } else { wb_byte(f.code, 0x45); }
        cg_trap_if(p, m, f, node, "division by zero");
    }
    if !unsigned && w == 0x7e && (op == T_DIV || checked && op == T_MUL) {
        cg_get(f, a); wb_i64(f.code, -9223372036854775807 - 1); wb_byte(f.code, 0x51); cg_get(f, b); wb_i64(f.code, -1); wb_byte(f.code, 0x51); wb_byte(f.code, 0x71);
        if checked {
            cg_get(f, b); wb_i64(f.code, -9223372036854775807 - 1); wb_byte(f.code, 0x51); cg_get(f, a); wb_i64(f.code, -1); wb_byte(f.code, 0x51); wb_byte(f.code, 0x71); wb_byte(f.code, 0x72);
        }
        cg_trap_if(p, m, f, node, "signed integer overflow");
    }
    var calculation = w; if !unsigned && w == 0x7f { calculation = 0x7e; }
    cg_get(f, a); if calculation != w { wb_byte(f.code, 0xac); }
    cg_get(f, b); if calculation != w { wb_byte(f.code, 0xac); }
    wb_byte(f.code, cg_numeric_opcode(op, calculation, unsigned)); let result = cg_save(f, calculation);
    if op == T_MOD && !unsigned {
        cg_get(f, result); wb_i64(f.code, 0); wb_byte(f.code, 0x53); cg_begin(f, 0x04, 0x40);
        cg_get(f, result); cg_get(f, b); if calculation != w { wb_byte(f.code, 0xac); } let divisor = cg_save(f, 0x7e);
        cg_get(f, divisor); wb_i64(f.code, 0); wb_byte(f.code, 0x53); cg_begin(f, 0x04, 0x7e);
        wb_i64(f.code, 0); cg_get(f, divisor); wb_byte(f.code, 0x7d); wb_byte(f.code, 0x05); cg_get(f, divisor); cg_end(f);
        wb_byte(f.code, 0x7c); cg_set(f, result); cg_end(f);
    }
    if !unsigned && calculation != w && (checked || op == T_DIV && p.debug) {
        let bits = p.types[id].count; let minimum = 0 - (1 << (bits - 1)); let maximum = (1 << (bits - 1)) - 1;
        cg_get(f, result); wb_i64(f.code, minimum); wb_byte(f.code, 0x53); cg_get(f, result); wb_i64(f.code, maximum); wb_byte(f.code, 0x55); wb_byte(f.code, 0x72); cg_trap_if(p, m, f, node, "signed integer overflow");
    }
    if checked && w == 0x7e {
        if op == T_PLUS {
            cg_get(f, a); cg_get(f, result); wb_byte(f.code, 0x85); cg_get(f, b); cg_get(f, result); wb_byte(f.code, 0x85); wb_byte(f.code, 0x83); wb_i64(f.code, 0); wb_byte(f.code, 0x53); cg_trap_if(p, m, f, node, "signed integer overflow");
        } else if op == T_MINUS {
            cg_get(f, a); cg_get(f, b); wb_byte(f.code, 0x85); cg_get(f, a); cg_get(f, result); wb_byte(f.code, 0x85); wb_byte(f.code, 0x83); wb_i64(f.code, 0); wb_byte(f.code, 0x53); cg_trap_if(p, m, f, node, "signed integer overflow");
        } else if op == T_MUL {
            cg_get(f, b); wb_i64(f.code, 0); wb_byte(f.code, 0x52); cg_begin(f, 0x04, 0x40);
            cg_get(f, result); cg_get(f, b); wb_byte(f.code, 0x7f); cg_get(f, a); wb_byte(f.code, 0x52); cg_trap_if(p, m, f, node, "signed integer overflow"); cg_end(f);
        }
    }
    cg_get(f, result); if calculation != w { wb_byte(f.code, 0xa7); } cg_normalize(p, f.code, id);
}
fn cg_byte_record(p: Program&, id: i64) -> bool {
    if cg_type_kind(p, id) != TY_STRUCT { return false; }
    let declaration = p.types[id].declaration; if declaration < 0 { return false; }
    var field = p.nodes[declaration].first;
    while field >= 0 {
        let type_id = p.nodes[field].type_id;
        if type_id >= 0 && p.types[type_id].storage == 1 { return true; }
        field = p.nodes[field].next;
    }
    return false;
}

fn cg_result_count(p: Program&, id: i64) -> i64 {
    if cg_type_kind(p, id) == TY_VOID { return 0; }
    if cg_type_kind(p, id) != TY_TUPLE { return 1; }
    var count = 0; var part = p.types[id].first;
    while part >= 0 { count++; part = p.nodes[part].next; } return count;
}
fn cg_result_at(p: Program&, id: i64, index: i64) -> i64 {
    if cg_type_kind(p, id) != TY_TUPLE { return id; }
    var part = p.types[id].first; var ordinal = 0;
    while part >= 0 { if ordinal == index { return p.nodes[part].type_id; } part = p.nodes[part].next; ordinal++; }
    return TYPE_UNKNOWN;
}

// A conservative feature proof. The general backend remains responsible for
// addressable values, closures, effects and owned construction. This proof
// permits omission only when none of those mechanisms can be observed.
fn cg_scalar_type(p: Program&, id: i64) -> bool {
    let kind = cg_type_kind(p, id);
    return kind == TY_VOID || kind == TY_BOOL || kind == TY_FLOAT || kind == TY_INT && p.types[id].storage == 0 && p.types[id].index_type < 0;
}
recursive fn cg_scalar_value(p: Program&, node: i64) -> bool {
    if node < 0 { return false; } let n = p.nodes[node];
    if !cg_scalar_type(p, n.type_id) || n.type_id == TYPE_VOID { return false; }
    if n.kind == N_INTEGER || n.kind == N_FLOAT || n.kind == N_BOOL { return true; }
    if n.kind == N_CAST { return cg_scalar_value(p, n.left); }
    if n.kind == N_UNARY {
        if n.integer != T_MINUS && n.integer != T_NOT && n.integer != T_BITNOT { return false; }
        return cg_scalar_value(p, n.left);
    }
    if n.kind == N_BINARY { return cg_scalar_value(p, n.left) && cg_scalar_value(p, n.right); }
    return false;
}
recursive fn cg_scalar_body(p: Program&, function: i64, node: i64) -> bool {
    if node < 0 { return true; } let n = p.nodes[node];
    if n.kind == N_BLOCK {
        var child = n.first;
        while child >= 0 { if !cg_scalar_body(p, function, child) { return false; } child = p.nodes[child].next; }
        return n.right < 0;
    }
    if n.kind == N_EXPR_STMT { return cg_scalar_body(p, function, n.left); }
    if n.kind == N_EMPTY { return true; }
    if n.kind == N_RETURN { return n.first < 0 && n.symbol == p.nodes[function].symbol; }
    if n.kind == N_CALL {
        if n.symbol < 0 || (p.symbols[n.symbol].flags & S_BUILTIN) == 0 || p.symbols[n.symbol].index != 0 { return false; }
        var arg = n.first;
        while arg >= 0 { if !cg_scalar_value(p, arg) { return false; } arg = p.nodes[arg].next; }
        return n.type_id == TYPE_VOID;
    }
    return cg_scalar_value(p, node);
}
recursive fn cg_scalar_prints(p: Program&, node: i64) -> bool {
    if node < 0 { return false; } let n = p.nodes[node];
    if n.kind == N_CALL { return true; }
    if cg_scalar_prints(p, n.left) || cg_scalar_prints(p, n.right) || cg_scalar_prints(p, n.third) { return true; }
    var child = n.first; while child >= 0 { if cg_scalar_prints(p, child) { return true; } child = p.nodes[child].next; }
    return false;
}
fn cg_scalar_metadata(p: Program&, m: CgModule&, module: u8[>..]&) {
    var section: u8[>..] = []; var names: u8[>..] = []; var name: u8[>..] = [];
    wb_name(section, "name"); wb_u(names, m.imports.len + m.functions.len + 1);
    for item, i in m.imports {
        name.clear(); name.append("goose."); name.append(cg_host_name(item.host)); wb_u(names, i); wb_name(names, name);
    }
    // The proof contains exactly the checked entry specialization, so its
    // discovery ordinal is zero. The symbol's spelling comes from the IR.
    for item in m.functions {
        name.clear(); name.append(token_text(p, p.symbols[item.symbol].name_token)); name.append("#0");
        wb_u(names, item.index); wb_name(names, name);
    }
    wb_u(names, m.start); wb_name(names, "_start"); wb_byte(section, 1); wb_u(section, names.len); wb_raw(section, names); wb_section(module, 0, section);
    section.clear(); wb_name(section, "goose.direct");
    wb_name(section, "abi=1;layout=15;encoded-record-tails=terminal;encoded-arrays=combined;array-lengths=unsigned-uleb;varint-elements=sequential-grow;varint-records=sequential;record-padding=fixed-alignment-variable-explicit;static-limited=compact-lengths;enum-tags=compact;variable-enums=active-payloads;record-values=packed-single-tail;owner-control=24;array-values=unsigned-prefixes;variant-payloads=packed-fields;fixed-records=packed-fields;memory=wasm32;slices=packed-ptr32-len32;features=bulk-memory,multi-value,sign-ext");
    wb_section(module, 0, section);
}
