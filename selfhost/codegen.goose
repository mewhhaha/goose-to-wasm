import model;
import wasm;
import region_plan;

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
let CG_FORMAT_F32: i64 = 9;
let CG_FORMAT_F64: i64 = 10;
struct CgSignature { start: i64, count: i64 }
struct CgImport { symbol: i64 = -1, signature: i64 = 0, host: i64 = -1 }
struct CgFunction {
    node: i64, symbol: i64, signature: i64 = -1, index: i64 = -1,
    closure_signature: i64 = -1, thunk: i64 = -1,
    capture_first: i64 = 0, capture_count: i64 = 0, arena_local: bool = false, elements: bool = false,
}
struct CgCapture { function: i64, symbol: i64 }
struct CgText { data: i64, length: i64 }
struct CgSegment { address: i64, start: i64, count: i64 }
struct CgModule {
    functions: CgFunction[>..]&, captures: CgCapture[>..]&, imports: CgImport[>..]&,
    signatures: CgSignature[>..]&, signature_bytes: u8[>..]&,
    segments: CgSegment[>..]&, data: u8[>..]&, globals: i64[>..]&,
    global_regions: i64[>..]&, region_functions: RegionFunction[>..]&, region_calls: RegionCall[>..]&,
    next_data: i64 = 1024, stack_limit: i64 = 0,
    region_count: i64 = 0, global_region_count: i64 = 0, regions_enabled: bool = false,
    region_bytes: i64 = 0, region_cursor_address: i64 = 0,
    start: i64 = -1, allocator: i64 = -1, float_wrap: i64 = -1, scalar: bool = false, resolver: i64 = -1, header_helper: i64 = -1, prefix_helper: i64 = -1, pool_global: i64 = -1,
    format_f32: i64 = -1, format_f64: i64 = -1, raw_append: i64 = -1, raw_append_type: i64 = -1,
}
struct CgExit { label: i64, again: i64 = -1, node: i64 = -1, result: i64 = -1, type_id: i64 = 0, scratch: i64 = -1, regions: i64 = -1, publication: i64 = -1 }
let CG_TEMPORARY: i64 = 0;
let CG_BLOCK_OWNER: i64 = 1;
let CG_EXISTING: i64 = 2;
let CG_CALLER: i64 = 3;
let CG_STATIC: i64 = 4;
struct CgConstruction { open: i64 = 0 }
struct CgDestination {
    type_id: i64, header: i64, lifetime: i64,
    elements: bool = false, normal: bool = false, escape: bool = false,
    construction: i64 = -1, open0: i64 = 0, publication: i64 = -1, entry: i64 = -1, start: i64 = -1,
}
struct CgReceiving { slot: i64, ordinal: i64, destination: i64, symbol: i64 = -1, prefix: i64 = -1 }
struct CgResultPlan { producer: i64 = -1, receiving: i64 = -1, adaptation: i64 = 0 }
struct CgSequence {
    kind: i64, node: i64, parent: i64 = -1, saved: i64 = -1, index: i64 = -1, pointer: i64 = -1, address: bool = false,
}
struct CgBody {
    code: u8[>..]&, locals: i64[>..]&, slots: i64[>..]&, offsets: i64[>..]&,
    labels: i64[>..]&, exits: CgExit[>..]&, results: i64[>..]&, destinations: i64[>..]&, work: i64[>..]&, raw_slots: i64[>..]&, sequences: CgSequence[>..]&,
    constructions: CgConstruction[>..]&, construction_destinations: CgDestination[>..]&, receiving: CgReceiving[>..]&,
    function: i64 = -1, function_index: i64 = -1, params: i64 = 0, serial: i64 = 0,
    region_live: i64 = 0, region_peak: i64 = 0, region_mark: i64 = -1, publication_mark: i64 = -1,
    frame: i64 = -1, frame_bytes: i64 = 0, effect: i64 = 0, effect_metadata: i64 = -1, done: i64 = -1, frame_free: bool = false,
    diagnostic_line: i64 = -1, heap_mark: i64 = -1, forward_mark: i64 = -1, scratch: bool = false, elements: bool = false, raw_node: i64 = -1, active_node: i64 = -1, active_destination: i64 = -1,
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
fn cg_frame_owner(p: Program&, id: i64) -> bool {
    if cg_type_kind(p, id) != TY_STRUCT { return false; }
    var current = id;
    while cg_type_kind(p, current) == TY_STRUCT {
        if cg_byte_record(p, current) || p.types[current].tail < 0 { return false; }
        current = p.nodes[p.types[current].tail].type_id;
    }
    return cg_owner(p, current) && (p.types[current].array_kind == A_GROW || p.types[current].array_kind == A_GROWSHRINK);
}
fn cg_image_owner(p: Program&, id: i64) -> bool { return cg_byte_record(p, id) || cg_record_image(p, id); }
fn cg_region_value(p: Program&, id: i64) -> bool { return cg_owner(p, id) || cg_frame_owner(p, id) || cg_image_owner(p, id) || cg_enum_image(p, id); }
fn cg_frame_prefix(p: Program&, id: i64) -> i64 {
    var current = id; var offset = 0;
    while cg_type_kind(p, current) == TY_STRUCT && p.types[current].tail >= 0 {
        let field = p.types[current].tail; offset += p.nodes[field].integer; current = p.nodes[field].type_id;
    }
    return offset;
}
fn cg_frame_tail_type(p: Program&, id: i64) -> i64 {
    var current = id; while cg_type_kind(p, current) == TY_STRUCT && p.types[current].tail >= 0 { current = p.nodes[p.types[current].tail].type_id; } return current;
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
    if p.types[id].kind == TY_INT && p.types[id].storage == 1 { return 8; }
    if p.types[id].kind == TY_FN { return 8; }
    if cg_aggregate(p, id) && p.types[id].size == 0 { return 1; }
    return p.types[id].size;
}
fn cg_slot_size(p: Program&, id: i64) -> i64 {
    if cg_relative_type(p, id) && p.types[id].length_storage == 0 { return 10; }
    return cg_size(p, id);
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
    var bytes = cg_slot_size(p, id); if bytes < 1 { bytes = 1; }
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
    if f.diagnostic_line >= 0 { cg_get(f, f.diagnostic_line); } else { wb_i32(f.code, line); }
    wb_op(f.code, 0x10, CG_ABORT); wb_byte(f.code, 0);
}
fn cg_trap_if(p: Program&, m: CgModule&, f: CgBody&, node: i64, text: u8[:]) {
    cg_begin(f, 0x04, 0x40); cg_abort(p, m, f, node, text); cg_end(f);
}
fn cg_function(m: CgModule&, symbol: i64) -> i64 {
    for item, i in m.functions { if item.symbol == symbol { return i; } }
    return -1;
}
fn cg_region_call(m: CgModule&, f: CgBody&, callee: i64, node: i64) {
    if callee >= 0 { m.region_calls.push(RegionCall { caller: f.function_index, callee: callee, live: f.region_live, node: node }); }
}
fn cg_bound_regions(p: Program&, m: CgModule&) {
    var stack: i64[>..] = []; var members: i64[>..] = [];
    var graph = RegionGraph { functions: m.region_functions, calls: m.region_calls, stack: stack, members: members };
    let bound = region_bound(p, graph, m.global_region_count);
    if bound > 4294967295 { region_diagnose(p, -1, "data-region count exceeds wasm32 limits"); return; }
    m.region_count = bound;
}
fn cg_elements_function(m: CgModule&, symbol: i64) -> i64 {
    for item, index in m.functions { if item.symbol == symbol && item.elements { return index; } }
    return cg_function(m, symbol);
}
fn cg_elements_table(m: CgModule&) -> i64 {
    var bytes: u8[>..] = [];
    for item in m.functions {
        let target = cg_elements_function(m, item.symbol);
        for part in 0..4 { wb_byte(bytes, target >> (part * 8)); }
    }
    return cg_data(m, bytes);
}
fn cg_raw_value(f: CgBody&, node: i64) -> bool { return node >= 0 && f.raw_node == node; }
fn cg_raw_slot(f: CgBody&, slot: i64) -> bool {
    if f.elements && f.results.len == 1 && slot == f.results[0] { return true; }
    for result in f.raw_slots { if result == slot { return true; } } return false;
}
fn cg_capture(m: CgModule&, function: i64, symbol: i64) -> bool {
    for item in m.captures { if item.function == function && item.symbol == symbol { return true; } }
    return false;
}
fn cg_storage_binding(p: Program&, symbol: i64) -> bool {
    let node = p.symbols[symbol].node; if node < 0 { return false; }
    let kind = p.nodes[node].kind; return kind == N_VARIABLE || kind == N_BINDING || kind == N_PARAM;
}
recursive fn cg_scan_captures(p: Program&, m: CgModule&, function: i64, node: i64) {
    if node < 0 { return; }
    let n = p.nodes[node];
    if n.kind == N_PATTERN || (n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE) && node != function { return; }
    if n.kind == N_NAME && n.symbol >= 0 {
        let s = p.symbols[n.symbol];
        if (s.flags & (S_FUNCTION | S_GLOBAL | S_TYPE | S_BUILTIN)) == 0 && (s.owner >= 0 || cg_storage_binding(p, n.symbol)) && s.owner != function && !cg_capture(m, function, n.symbol) {
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
    if cg_type_kind(p, from) == TY_ARRAY && cg_type_kind(p, to) == TY_SLICE { cg_pack_view(p, m, f, from, node); return; }
    if cg_type_kind(p, to) == TY_ENUM && cg_enum_image(p, to) &&
       (cg_type_kind(p, from) == TY_ENUM && p.types[from].declaration == p.types[to].declaration ||
        cg_type_kind(p, from) == TY_STRUCT && p.types[from].pool >= 0 && p.types[p.types[from].pool].declaration == p.types[to].declaration) {
        let source = cg_save(f, 0x7f);
        if m.regions_enabled { let receiving = cg_temporary_destination(p, m, f, to, node); cg_construct_enum_captured(p, m, f, from, source, receiving, node); cg_get(f, f.construction_destinations[receiving].header); return; }
        let destination = cg_temporary(p, f, to);
        cg_enum_from_value(p, m, f, to, destination, from, source, node); cg_get(f, destination); return;
    }
    if cg_type_kind(p, from) == TY_ENUM && cg_enum_image(p, from) && cg_type_kind(p, to) == TY_ENUM && p.types[from].declaration == p.types[to].declaration {
        let source = cg_save(f, 0x7f); let bytes = cg_enum_image_bytes(p, m, f, from, source, node);
        cg_get(f, bytes); wb_i32(f.code, cg_size(p, to)); wb_byte(f.code, 0x4b); cg_trap_if(p, m, f, node, "enum payload exceeds fixed envelope");
        let destination = cg_temporary(p, f, to); cg_get(f, destination); wb_i32(f.code, 0); wb_i32(f.code, cg_size(p, to)); wb_fill(f.code);
        cg_get(f, destination); cg_get(f, source); wb_mem(f.code, 0x28, 2, 0); cg_get(f, bytes); wb_copy(f.code); cg_get(f, destination); return;
    }
    if cg_type_kind(p, from) == TY_STRUCT && cg_type_kind(p, to) == TY_ENUM && p.types[from].pool >= 0 && p.types[p.types[from].pool].declaration == p.types[to].declaration {
        let source = cg_save(f, 0x7f); let destination = cg_temporary(p, f, to);
        cg_get(f, destination); wb_i32(f.code, 0); wb_i32(f.code, cg_size(p, to)); wb_fill(f.code);
        cg_get(f, destination); wb_i32(f.code, p.nodes[p.types[from].declaration].integer);
        if p.types[to].length_storage == 2 { wb_mem(f.code, 0x3b, 0, 0); } else { wb_mem(f.code, 0x3a, 0, 0); }
        cg_get(f, destination); wb_i32(f.code, p.types[to].length_storage); wb_byte(f.code, 0x6a); let payload = cg_save(f, 0x7f);
        if p.types[from].first >= 0 { cg_copy(p, m, f, from, payload, source, node); }
        cg_get(f, destination); return;
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
    if cg_type_kind(p, id) == TY_SLICE {
        if m.resolver >= 0 {
            let view = cg_save(f, 0x7e); cg_get(f, view); wb_byte(f.code, 0xa7); cg_resolve_pointer(m, f); wb_byte(f.code, 0xad);
            cg_get(f, view); wb_i64(f.code, -4294967296); wb_byte(f.code, 0x83); wb_byte(f.code, 0x84);
        }
        return;
    }
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
fn cg_field_place(p: Program&, m: CgModule&, f: CgBody&, object_type: i64, node: i64, field_id: i64 = -1) {
    var selected = field_id; if selected < 0 { selected = p.nodes[node].symbol; }
    if cg_byte_record(p, object_type) {
        let header = cg_save(f, 0x7f); let address = cg_byte_field(p, m, f, object_type, header, selected, node); cg_get(f, address); return;
    }
    if cg_record_image(p, object_type) && !cg_frame_metadata(p, object_type) && selected != p.types[object_type].tail {
        let owner = cg_save(f, 0x7f); let image = cg_record_image_base(p, m, f, object_type, owner, node);
        var field = p.types[object_type].first; var offset = 0;
        while field >= 0 && field != selected {
        if (p.nodes[field].flags & F_PAD) != 0 { offset += p.nodes[field].aux; }
        else { offset += cg_size(p, p.nodes[field].type_id); }
        field = p.nodes[field].next;
        }
        cg_get(f, image); if offset != 0 { wb_i32(f.code, offset); wb_byte(f.code, 0x6a); } return;
    }
    let offset = p.nodes[selected].integer;
    if offset < 0 { cg_fail(p, node, "wasm: variable record field requires an encoded field walker"); return; }
    if offset != 0 { wb_i32(f.code, offset); wb_byte(f.code, 0x6a); }
    return;
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
        cg_field_place(p, m, f, object_type, node); cg_canonical_address(m, f, cg_size(p, p.nodes[n.symbol].type_id)); return;
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
    let into = cg_resolve_location(m, f, destination); let from = cg_resolve_location(m, f, source);
    if m.regions_enabled && (cg_frame_owner(p, id) || cg_image_owner(p, id) || cg_enum_image(p, id)) {
        let header = cg_region_acquire(p, m, f, id, into, -1, node); let entry = cg_region_cursor(f, header);
        let receiving = cg_destination(f, id, into, CG_TEMPORARY, false, false, false, entry, -1); if cg_enum_image(p, id) { cg_construct_enum_captured(p, m, f, id, from, receiving, node); }
        else if cg_image_owner(p, id) { cg_construct_image_captured(p, m, f, id, from, receiving, node); }
        else { cg_construct_frame_captured(p, m, f, id, from, receiving, node); } return;
    }
    if m.prefix_helper >= 0 && cg_aggregate(p, id) && !cg_has_owner(p, id) {
        cg_get(f, into); cg_canonical_address(m, f, cg_size(p, id)); cg_get(f, from); cg_canonical_address(m, f, cg_size(p, id)); wb_i32(f.code, cg_size(p, id)); wb_copy(f.code); return;
    }
    if !cg_aggregate(p, id) {
        cg_get(f, from); cg_load(p, m, f, id, 0); cg_write_value(p, m, f, id, into, node); return;
    }
    if cg_owner(p, id) {
        if p.types[id].array_kind == A_LIMITED { cg_copy_runtime_limited(p, m, f, id, into, from, node); return; }
        cg_get(f, from); cg_pack_view(p, m, f, id, node); cg_array_from_view(p, m, f, id, node);
        let snapshot = cg_save(f, 0x7f); cg_get(f, into); cg_get(f, snapshot); wb_i32(f.code, 24); wb_copy(f.code); return;
    }

    if cg_enum_image(p, id) { cg_enum_from_value(p, m, f, id, into, id, from, node); return; }
    if cg_byte_record(p, id) { cg_copy_byte_record(p, m, f, id, into, from, node); return; }
    if cg_record_image(p, id) { cg_copy_record_image(p, m, f, id, into, from, node); return; }
    // Fixed records and arrays are packed. Their checked offsets include all
    // explicit padding. Copy the complete image before repairing owner fields.
    cg_get(f, into); cg_get(f, from); wb_i32(f.code, cg_size(p, id)); wb_copy(f.code);
    if cg_type_kind(p, id) == TY_STRUCT {
        let declaration = p.types[id].declaration;
        var field = p.nodes[declaration].first;
        while field >= 0 {
            let type_id = p.nodes[field].type_id;
            if cg_aggregate(p, type_id) {
                cg_get(f, into); wb_i32(f.code, p.nodes[field].integer); wb_byte(f.code, 0x6a); let dst = cg_save(f, 0x7f);
                cg_get(f, from); wb_i32(f.code, p.nodes[field].integer); wb_byte(f.code, 0x6a); let src = cg_save(f, 0x7f);
                cg_copy(p, m, f, type_id, dst, src, node);
            }
            field = p.nodes[field].next;
        }
    }
}
recursive fn cg_write_value(p: Program&, m: CgModule&, f: CgBody&, id: i64, destination: i64, node: i64) {
    let value = cg_save(f, cg_wasm_type(p, id));
    if cg_aggregate(p, id) { cg_copy(p, m, f, id, destination, value, node); return; }
    if cg_relative_type(p, id) { cg_write_relative(p, m, f, id, destination, value, node); return; }
    cg_get(f, destination); cg_resolve_pointer(m, f); cg_canonical_address(m, f, cg_size(p, id)); cg_get(f, value);
    var storage = id; if p.types[id].kind == TY_INT && p.types[id].storage == 1 { storage = TYPE_I64; }
    if !cg_store(p, f.code, storage, 0) { cg_fail(p, node, "wasm: unsupported stored value type"); }
}
fn cg_callback_expression(p: Program&, node: i64) -> bool {
    let n = p.nodes[node];
    if n.kind == N_BLOCK && n.origin >= 0 { return p.nodes[n.origin].kind == N_FUNCTION_VALUE; }
    if n.kind != N_CALL { return false; }
    if n.symbol < 0 { return true; }
    return (p.symbols[n.symbol].flags & (S_FUNCTION | S_BUILTIN)) == S_FUNCTION &&
        p.symbols[n.symbol].node >= 0 && p.nodes[p.symbols[n.symbol].node].kind == N_FUNCTION_VALUE;
}
recursive fn cg_to(p: Program&, m: CgModule&, f: CgBody&, node: i64, id: i64) {
    if node < 0 { cg_fail(p, node, "wasm: missing value expression"); return; }
    let from = p.nodes[node].type_id;
    if cg_type_kind(p, id) == TY_REF && cg_type_kind(p, from) != TY_REF { cg_address(p, m, f, node); return; }
    let saved_raw = f.raw_node;
    if cg_type_kind(p, id) == TY_ARRAY && cg_type_kind(p, from) == TY_ARRAY && p.types[from].array_kind == A_VAR && !cg_callback_expression(p, node) {
        if p.types[id].array_kind == A_GROW || p.types[id].array_kind == A_GROWSHRINK ||
           p.types[id].array_kind == A_VAR && p.types[id].length_storage != p.types[from].length_storage ||
           p.types[id].array_kind == A_LIMITED && p.nodes[node].kind == N_BLOCK && p.nodes[node].origin >= 0 { f.raw_node = node; }
    }
    cg_expr(p, m, f, node); f.raw_node = saved_raw;
    if cg_diverges(p, node) { return; }
    cg_convert(p, m, f, from, id, node);
}
recursive fn cg_truth_scope(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    if !m.regions_enabled || !cg_may_region(p, node) { cg_truth(p, m, f, node); return; }
    let live = f.region_live; let mark = cg_mark_regions(f); cg_truth(p, m, f, node); cg_restore_regions(f, mark); f.region_live = live;
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
        cg_truth_scope(p, m, f, n.left); if cg_diverges(p, n.left) { return; } cg_begin(f, 0x04, 0x7f);
        if op == T_ANDAND { cg_truth(p, m, f, n.right); } else { wb_i32(f.code, 1); }
        wb_byte(f.code, 0x05);
        if op == T_OROR { cg_truth(p, m, f, n.right); } else { wb_i32(f.code, 0); }
        cg_end(f); return;
    }
    if op == T_DOTEQ || op == T_DOTNEQ || (op == T_EQ || op == T_NEQ) && (p.nodes[n.left].kind == N_NULL || p.nodes[n.right].kind == N_NULL) {
        cg_expr(p, m, f, n.left); if cg_diverges(p, n.left) { return; } cg_resolve_pointer(m, f); cg_expr(p, m, f, n.right); if cg_diverges(p, n.right) { return; } cg_resolve_pointer(m, f);
        wb_byte(f.code, cg_numeric_opcode(op, 0x7f, true)); return;
    }
    var id = p.nodes[n.left].type_id;
    if cg_type_kind(p, id) == TY_REF && op != T_DOTEQ && op != T_DOTNEQ { id = p.types[id].element; }
    let comparison = op == T_EQ || op == T_NEQ || op == T_LT || op == T_GT || op == T_LTEQ || op == T_GTEQ || op == T_DOTEQ || op == T_DOTNEQ;
    if !comparison && op != T_SHL && op != T_SHR { id = n.type_id; }
    if n.aux >= 0 && n.aux < p.types.len && (p.types[n.aux].kind == TY_INT || p.types[n.aux].kind == TY_FLOAT) { id = n.aux; }
    cg_to(p, m, f, n.left, id); if cg_diverges(p, n.left) { return; }
    cg_to(p, m, f, n.right, id); if cg_diverges(p, n.right) { return; }
    cg_numeric(p, m, f, op, id, node);
    if cg_type_kind(p, n.type_id) != TY_BOOL { cg_convert(p, m, f, id, n.type_id, node); }

}
fn cg_float_remainder(p: Program&, m: CgModule&, f: CgBody&, node: i64, w: i64) {
    let divisor = cg_save(f, w); let original = cg_save(f, w);
    var abs_op = 0x8b; var add_op = 0x92; var div_op = 0x95; var sub_op = 0x93; var copy_sign = 0x98;
    if w == 0x7c { abs_op = 0x99; add_op = 0xa0; div_op = 0xa3; sub_op = 0xa1; copy_sign = 0xa6; }
    cg_get(f, divisor); wb_byte(f.code, abs_op); let magnitude = cg_save(f, w);
    cg_get(f, original); wb_byte(f.code, abs_op); let value = cg_save(f, w);
    cg_get(f, magnitude); cg_zero(f.code, w); wb_byte(f.code, cg_numeric_opcode(T_EQ, w, false));
    cg_get(f, value); cg_get(f, value); wb_byte(f.code, cg_numeric_opcode(T_NEQ, w, false)); wb_byte(f.code, 0x72);
    cg_get(f, magnitude); cg_get(f, magnitude); wb_byte(f.code, cg_numeric_opcode(T_NEQ, w, false)); wb_byte(f.code, 0x72);
    cg_get(f, value); if w == 0x7d { wb_f32(f.code, 3.4028234663852886e38); } else { wb_f64(f.code, 1.7976931348623157e308); }
    wb_byte(f.code, cg_numeric_opcode(T_GT, w, false)); wb_byte(f.code, 0x72);
    cg_begin(f, 0x04, w); cg_zero(f.code, w); cg_zero(f.code, w); wb_byte(f.code, div_op);
    wb_byte(f.code, 0x05);
    cg_get(f, value); cg_get(f, magnitude); wb_byte(f.code, cg_numeric_opcode(T_LT, w, false));
    cg_begin(f, 0x04, w); cg_get(f, original); wb_byte(f.code, 0x05);
    cg_get(f, magnitude); let scale = cg_save(f, w);
    let scaled = cg_begin(f, 0x02, 0x40); let scaling = cg_begin(f, 0x03, 0x40);
    cg_get(f, scale); cg_get(f, scale); wb_byte(f.code, add_op); let twice = cg_save(f, w);
    cg_get(f, twice); cg_get(f, value); wb_byte(f.code, cg_numeric_opcode(T_GT, w, false)); cg_branch(p, f, scaled, true);
    cg_get(f, twice); cg_set(f, scale); cg_branch(p, f, scaling, false); cg_end(f); cg_end(f);
    let reducing = cg_begin(f, 0x03, 0x40);
    cg_get(f, value); cg_get(f, scale); wb_byte(f.code, cg_numeric_opcode(T_GTEQ, w, false)); cg_begin(f, 0x04, 0x40);
    cg_get(f, value); cg_get(f, scale); wb_byte(f.code, sub_op); cg_set(f, value); cg_end(f);
    cg_get(f, scale); if w == 0x7d { wb_f32(f.code, 2.0); } else { wb_f64(f.code, 2.0); }
    wb_byte(f.code, div_op); cg_set(f, scale);
    cg_get(f, scale); cg_get(f, magnitude); wb_byte(f.code, cg_numeric_opcode(T_GTEQ, w, false)); cg_branch(p, f, reducing, true); cg_end(f);
    cg_get(f, value); cg_get(f, original); wb_byte(f.code, copy_sign); cg_end(f); cg_end(f);
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
fn cg_direct_array_call(p: Program&, f: CgBody&, node: i64, destination: i64) -> bool {
    let n = p.nodes[node]; let target = f.construction_destinations[destination]; var natural = -1;
    if n.symbol >= 0 && (p.symbols[n.symbol].flags & S_BUILTIN) != 0 { return false; }
    var callback = false;
    if n.symbol >= 0 && (p.symbols[n.symbol].flags & S_FUNCTION) != 0 { let function = p.symbols[n.symbol].node; natural = cg_result_type(p, function); callback = p.nodes[function].kind == N_FUNCTION_VALUE; }
    else if n.left >= 0 && cg_type_kind(p, p.nodes[n.left].type_id) == TY_FN { natural = p.types[p.nodes[n.left].type_id].element; }
    if callback && cg_owner(p, natural) && !cg_named_array_mode(p, natural, target.type_id) { return false; }
    if cg_variant_result(p, natural, target.type_id) >= 0 { return true; }
    if cg_frame_owner(p, natural) || cg_frame_owner(p, target.type_id) || cg_image_owner(p, natural) || cg_image_owner(p, target.type_id) || cg_enum_image(p, natural) || cg_enum_image(p, target.type_id) { return natural == target.type_id; }
    if !cg_owner(p, natural) || !cg_owner(p, target.type_id) { return false; }
    let source = p.types[natural]; let receiving = p.types[target.type_id];
    if source.array_kind == A_VAR && n.symbol >= 0 && (p.symbols[n.symbol].flags & S_FUNCTION) != 0 && cg_nonlocal_target(p, p.symbols[n.symbol].node) &&
       (target.elements || receiving.array_kind == A_GROW || receiving.array_kind == A_GROWSHRINK || receiving.array_kind == A_VAR && receiving.length_storage != source.length_storage) { return false; }
    if target.elements {
        if source.array_kind == A_VAR && (n.flags & F_DISPATCH) != 0 { return false; }
        return source.array_kind != A_LIMITED;
    }
    if receiving.array_kind == A_LIMITED && target.lifetime == CG_EXISTING { return false; }
    if source.array_kind == receiving.array_kind {
        return source.array_kind != A_VAR || source.length_storage == receiving.length_storage;
    }
    return source.array_kind == A_VAR && (receiving.array_kind == A_GROW || receiving.array_kind == A_GROWSHRINK) && (n.flags & F_DISPATCH) == 0;
}
recursive fn cg_call(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n = p.nodes[node];
    if (n.flags & F_DISPATCH) != 0 { cg_dispatch(p, m, f, node); return; }
    if n.symbol >= 0 && (p.symbols[n.symbol].flags & S_BUILTIN) != 0 { cg_builtin(p, m, f, node, p.symbols[n.symbol].index); return; }
    if n.symbol < 0 && cg_diverges(p, node) {
        if cg_diverges(p, n.left) { cg_expr(p, m, f, n.left); return; }
        var child = n.first;
        while child >= 0 { cg_discard(p, m, f, child); if cg_diverges(p, child) { return; } child = p.nodes[child].next; }
        cg_fail(p, node, "wasm: divergent call has no checked evaluated prefix"); return;
    }
    var function = -1; var index = -1; var closure = -1;
    if n.symbol >= 0 && (p.symbols[n.symbol].flags & S_FUNCTION) != 0 {
        function = p.symbols[n.symbol].node; index = cg_function(m, n.symbol);
        if cg_raw_value(f, node) { index = cg_elements_function(m, n.symbol); }
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
    let variant_plans = f.work.len; let result_count = cg_result_count(p, return_id);
    for ordinal in 0..result_count {
        let natural = cg_result_at(p, return_id, ordinal); var requested = cg_receiving(f, -2 - node, ordinal); var producer = -1;
        if requested < 0 && result_count == 1 && f.active_node == node { requested = f.active_destination; }
        if m.regions_enabled && requested >= 0 && cg_variant_result(p, natural, f.construction_destinations[requested].type_id) >= 0 && (result_count == 1 || cg_region_value(p, natural)) { producer = cg_prepare_variant_result(p, m, f, natural, requested, node); }
        f.work.push(producer); f.work.push(requested);
    }
    var arg = n.first;
    while param >= 0 && arg >= 0 {
        let id = p.nodes[param].type_id;
        if m.regions_enabled && cg_region_value(p, id) {
            let receiving = cg_temporary_destination(p, m, f, id, arg); cg_construct_region(p, m, f, arg, receiving); if cg_diverges(p, arg) { return; } cg_get(f, f.construction_destinations[receiving].header);
        } else {
            cg_to(p, m, f, arg, id); if cg_diverges(p, arg) { return; }
            if cg_aggregate(p, id) {
                let source = cg_save(f, 0x7f); let snapshot = cg_temporary(p, f, id);
                cg_copy(p, m, f, id, snapshot, source, arg); cg_get(f, snapshot);
            }
        }
        param = p.nodes[param].next; arg = p.nodes[arg].next;
    }
    if arg >= 0 || param >= 0 { cg_fail(p, node, "wasm: checked call argument arity mismatch"); return; }
    if function >= 0 {
        for capture in m.captures { if capture.function == function { cg_symbol_address(p, m, f, capture.symbol, node); } }
    }
    var results: i64[>..] = []; cg_result_types(p, return_id, results); var plans: CgResultPlan[>..] = [];
    for id, ordinal in results {
        var plan = CgResultPlan {}; let requested = cg_receiving(f, -2 - node, ordinal);
        if f.work[variant_plans + ordinal * 2] >= 0 { plan.producer = f.work[variant_plans + ordinal * 2]; plan.receiving = f.work[variant_plans + ordinal * 2 + 1]; plan.adaptation = 3; }
        else if m.regions_enabled && requested >= 0 && cg_region_value(p, f.construction_destinations[requested].type_id) && !cg_region_value(p, id) { plan.receiving = requested; plan.adaptation = 2; }
        if cg_aggregate(p, id) && plan.adaptation == 3 { cg_get(f, f.construction_destinations[plan.producer].header); }
        else if cg_aggregate(p, id) {
            if m.regions_enabled && cg_region_value(p, id) {
                plan.receiving = requested;
                if requested >= 0 && f.construction_destinations[requested].type_id == id { plan.producer = requested; }
                else if requested >= 0 && (function < 0 || p.nodes[function].kind != N_FUNCTION_VALUE) && cg_value_array_adaptation(p, id, f.construction_destinations[requested]) {
                    plan.producer = cg_share_destination(p, m, f, requested, id, false, false, f.construction_destinations[requested].escape, node); plan.adaptation = 1;
                } else if requested >= 0 { plan.producer = cg_temporary_destination(p, m, f, id, node); plan.adaptation = 2; }
                else if results.len == 1 && f.active_node == node && f.active_destination >= 0 && cg_direct_array_call(p, f, node, f.active_destination) { plan.producer = f.active_destination; }
                else { plan.producer = cg_temporary_destination(p, m, f, id, node); }
                cg_get(f, f.construction_destinations[plan.producer].header);
            } else if requested >= 0 && f.construction_destinations[requested].type_id == id && cg_fixed_relative(p, id) { cg_get(f, f.construction_destinations[requested].header); }
            else { cg_get(f, cg_temporary(p, f, id)); }
        }
        plans.push(plan);
    }
    f.work.resize(variant_plans);
    if function >= 0 {
        let opcode = cg_intrinsic(p, function);
        if opcode != 0 { wb_byte(f.code, opcode); }
        else {
            var target = -1;
            if index >= 0 { target = m.functions[index].index; cg_region_call(m, f, index, node); }
            else { for item, i in m.imports { if item.symbol == n.symbol { target = i; } } }
            if target < 0 { cg_fail(p, node, "wasm: call has no emitted function or import"); return; }
            wb_op(f.code, 0x10, target);
        }
    } else {
        var args: u8[>..] = [0x7f]; var returns: u8[>..] = [];
        param = p.types[callable_type].first;
        while param >= 0 { args.push(cg_wasm_type(p, p.nodes[param].type_id) as u8); param = p.nodes[param].next; }
        for id in results { if cg_aggregate(p, id) { args.push(0x7f); } returns.push(cg_wasm_type(p, id) as u8); }
        cg_get(f, closure); wb_byte(f.code, 0xa7);
        if cg_raw_value(f, node) { wb_i32(f.code, 4); wb_byte(f.code, 0x6c); wb_i32(f.code, cg_elements_table(m)); wb_byte(f.code, 0x6a); wb_mem(f.code, 0x28, 0, 0); }
        let signature = cg_signature(m, args, returns);
        for item, candidate in m.functions { if item.closure_signature == signature { cg_region_call(m, f, candidate, node); } }
        wb_op(f.code, 0x11, signature); wb_u(f.code, 0);
    }
    cg_effect_check(p, m, f, results);
    var adapting = false; for plan in plans { if plan.adaptation != 0 { adapting = true; } }
    if adapting {
        var values: i64[>..] = []; for id in results { values.push(cg_local(f, cg_wasm_type(p, id))); }
        var ordinal = results.len; while ordinal > 0 { ordinal -= 1; cg_set(f, values[ordinal]); }
        for id, index in results {
            let plan = plans[index];
            if plan.adaptation == 1 { cg_finish_value_array(p, m, f, f.construction_destinations[plan.producer].header, plan.receiving, node); }
            else if plan.adaptation == 2 { cg_construct_captured(p, m, f, id, values[index], plan.receiving, node); }
            else if plan.adaptation == 3 { cg_publish_variant_result(p, m, f, id, values[index], plan.producer, plan.receiving, node); }
        }
        for id, index in results {
            let plan = plans[index];
            if plan.adaptation != 0 { cg_get(f, f.construction_destinations[plan.receiving].header); }
            else { cg_get(f, values[index]); }
        }
    }
    if results.len == 1 && n.type_id != results[0] && !cg_diverges(p, node) { cg_convert(p, m, f, results[0], n.type_id, node); }
}
recursive fn cg_array_literal(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n = p.nodes[node]; let id = n.type_id; let element = p.types[id].element;
    if cg_type_kind(p, id) == TY_SLICE && (n.flags & F_DEFAULT) != 0 && n.first < 0 { wb_i64(f.code, 0); return; }
    if m.regions_enabled && cg_region_value(p, id) {
        var receiving = -1;
        if f.active_node == node && f.active_destination >= 0 { receiving = f.active_destination; }
        else { receiving = cg_temporary_destination(p, m, f, id, node); }
        cg_construct_array(p, m, f, node, receiving); cg_get(f, f.construction_destinations[receiving].header); return;
    }
    let destination = cg_temporary(p, f, id);
    if !cg_owner(p, id) && cg_has_relative(p, element) {
        cg_literal_at(p, m, f, node, id, destination); cg_get(f, destination); return;
    }
    cg_get(f, destination); wb_i32(f.code, 0); wb_i32(f.code, cg_size(p, id)); wb_fill(f.code);
    var count = 0; var child = n.first;
    while child >= 0 { count++; child = p.nodes[child].next; }
    var count_local = -1;
    if n.right >= 0 {
        cg_to(p, m, f, n.right, TYPE_U64); let count64 = cg_save(f, 0x7e);
        cg_get(f, count64); wb_i64(f.code, 4294967295); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array repetition count out of range");
        cg_get(f, count64); wb_byte(f.code, 0xa7); count_local = cg_save(f, 0x7f);
    }
    else { wb_i32(f.code, count); count_local = cg_save(f, 0x7f); }
    cg_check_array_length(p, m, f, id, count_local, node);
    var fill_value = -1;
    if n.right >= 0 && n.first >= 0 && !cg_has_relative(p, element) {
        var value_type = element; if p.types[element].storage == 1 { value_type = TYPE_I64; }
        cg_to(p, m, f, n.first, value_type); fill_value = cg_save(f, cg_wasm_type(p, value_type));
    }
    var base = destination;
    if cg_owner(p, id) {
        var capacity = count_local;
        if n.third >= 0 {
            cg_to(p, m, f, n.third, TYPE_U64); let capacity64 = cg_save(f, 0x7e);
            cg_get(f, capacity64); wb_i64(f.code, 4294967295); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array capacity out of range");
            cg_get(f, capacity64); wb_byte(f.code, 0xa7); capacity = cg_save(f, 0x7f);
            cg_get(f, count_local); cg_get(f, capacity); wb_byte(f.code, 0x4b); cg_trap_if(p, m, f, node, "array capacity exceeded");
        }
        base = cg_owner_image(p, m, f, id, destination, count_local, capacity, node);
    } else {
        cg_get(f, count_local); wb_i32(f.code, p.types[id].count); wb_byte(f.code, 0x4b); cg_trap_if(p, m, f, node, "array capacity exceeded");
        if p.types[id].array_kind == A_LIMITED {
            cg_get(f, destination); cg_get(f, count_local); cg_length_store(p, f, id);
            cg_get(f, destination); wb_i32(f.code, cg_static_prefix(p, id)); wb_byte(f.code, 0x6a); base = cg_save(f, 0x7f);
        }
    }
    if cg_has_relative(p, element) {
        cg_literal_elements(p, m, f, node, element, base, count_local); cg_get(f, destination); return;
    }
    if p.types[element].storage == 1 { cg_encoded_array_initializers(p, m, f, node, destination, base, count_local, fill_value); cg_get(f, destination); return; }
    if n.right >= 0 && n.first >= 0 {
        let value = fill_value;
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
            cg_to(p, m, f, child, element); if cg_diverges(p, child) { return; } cg_write_value(p, m, f, element, address, child);
            child = p.nodes[child].next; ordinal++;
        }
    }
    cg_get(f, destination);
}
recursive fn cg_record_fields(p: Program&, m: CgModule&, f: CgBody&, id: i64, destination: i64, node: i64, captured: i64 = -1, in_place: bool = false) {
    let n = p.nodes[node];
    if cg_byte_record(p, id) { cg_construct_byte_record(p, m, f, id, destination, node); return; }
    if !in_place || n.first < 0 { cg_get(f, destination); wb_i32(f.code, 0); wb_i32(f.code, cg_size(p, id)); wb_fill(f.code); }
    var payload_offset = 0;
    if cg_type_kind(p, id) == TY_ENUM && n.symbol >= 0 {
        cg_get(f, destination); wb_i32(f.code, p.nodes[n.symbol].integer);
        if p.types[id].length_storage == 2 { wb_mem(f.code, 0x3b, 0, 0); } else { wb_mem(f.code, 0x3a, 0, 0); }
        payload_offset = p.types[id].length_storage;
    }
    var binding = n.first;
    while binding >= 0 {
        let field = p.nodes[binding].symbol;
        if field < 0 || field >= p.nodes.len { cg_fail(p, binding, "wasm: record initializer has no resolved field"); return; }
        let initializer = p.nodes[binding].right;
        if p.nodes[field].integer < 0 { cg_fail(p, binding, "wasm: byte-record construction requires sequential image packing"); return; }
        cg_get(f, destination); wb_i32(f.code, payload_offset + p.nodes[field].integer); wb_byte(f.code, 0x6a); let address = cg_save(f, 0x7f);
        if initializer >= 0 {
            if p.nodes[initializer].kind == N_SELF {
                cg_get(f, destination); if payload_offset != 0 { wb_i32(f.code, payload_offset); wb_byte(f.code, 0x6a); }
            } else if cg_relative_literal(p, initializer, p.nodes[field].type_id) {
                cg_literal_at(p, m, f, initializer, p.nodes[field].type_id, address, captured, in_place);
                if cg_diverges(p, initializer) { return; } binding = p.nodes[binding].next; continue;
            } else if captured < 0 && cg_fixed_relative(p, p.nodes[field].type_id) {
                cg_fixed_to(p, m, f, initializer, p.nodes[field].type_id, address);
                if cg_diverges(p, initializer) { return; } binding = p.nodes[binding].next; continue;
            } else if captured >= 0 { cg_get(f, cg_literal_saved(p, f, captured, initializer)); }
            else { cg_to(p, m, f, initializer, p.nodes[field].type_id); }
            if cg_diverges(p, initializer) { return; } cg_write_value(p, m, f, p.nodes[field].type_id, address, binding);
        } else if in_place { cg_get(f, address); wb_i32(f.code, 0); wb_i32(f.code, cg_size(p, p.nodes[field].type_id)); wb_fill(f.code); }
        binding = p.nodes[binding].next;
    }
    if cg_record_image(p, id) { cg_pack_record_image(p, m, f, id, destination, node); }
}
fn cg_has_relative(p: Program&, id: i64) -> bool {
    var pending: i64[>..] = [id]; var seen: i64[>..] = [];
    while pending.len > 0 {
        let current = pending.pop(); if current < 0 { continue; }
        var visited = false; for old in seen { if old == current { visited = true; break; } } if visited { continue; } seen.push(current);
        let t = p.types[current];
        if t.kind == TY_REF { if t.length_storage >= 0 { return true; } }
        else if t.kind == TY_ARRAY { pending.push(t.element); }
        else if t.kind == TY_STRUCT || t.kind == TY_ENUM {
            var field = t.first; while field >= 0 { if (p.nodes[field].flags & F_PAD) == 0 { pending.push(p.nodes[field].type_id); } field = p.nodes[field].next; }
        }
    }
    return false;
}
fn cg_relative_literal(p: Program&, node: i64, id: i64) -> bool {
    if node < 0 || !cg_aggregate(p, id) || cg_has_owner(p, id) || !cg_has_relative(p, id) { return false; }
    let kind = p.nodes[node].kind; return kind == N_RECORD || kind == N_ARRAY || kind == N_FILL;
}
fn cg_fixed_relative(p: Program&, id: i64) -> bool { return cg_aggregate(p, id) && !cg_has_owner(p, id) && cg_has_relative(p, id); }
recursive fn cg_fixed_to(p: Program&, m: CgModule&, f: CgBody&, node: i64, id: i64, destination: i64) {
    if cg_relative_literal(p, node, id) { cg_literal_at(p, m, f, node, id, destination, -1, true); return; }
    let kind = p.nodes[node].kind;
    if p.nodes[node].type_id == id && (kind == N_CALL || kind == N_RESULT || kind == N_BLOCK || kind == N_IF || kind == N_GUARD || kind == N_MATCH || kind == N_LOOP || kind == N_WHILE) {
        let mark = f.receiving.len; let receiving = cg_destination(f, id, destination, CG_EXISTING, false, false, false, -1, -1);
        f.receiving.push(CgReceiving { slot: -2 - node, ordinal: 0, destination: receiving }); cg_expr(p, m, f, node); f.receiving.resize(mark);
        if !cg_diverges(p, node) { wb_byte(f.code, 0x1a); } return;
    }
    cg_to(p, m, f, node, id); if !cg_diverges(p, node) { cg_write_value(p, m, f, id, destination, node); }
}
fn cg_literal_saved(p: Program&, f: CgBody&, captured: i64, node: i64) -> i64 {
    var at = captured;
    while at < f.work.len { if f.work[at] == node { return f.work[at + 1]; } at += 3; }
    cg_fail(p, node, "wasm: literal replay has no evaluated operand"); wb_i32(f.code, 0); return cg_save(f, 0x7f);
}
recursive fn cg_capture_literal(p: Program&, m: CgModule&, f: CgBody&, node: i64, id: i64) {
    if p.nodes[node].kind == N_SELF { return; }
    if cg_relative_literal(p, node, id) {
        let n = p.nodes[node];
        if n.kind == N_RECORD {
            var binding = n.first;
            while binding >= 0 {
                let field = p.nodes[binding].symbol; let value = p.nodes[binding].right;
                if value >= 0 { cg_capture_literal(p, m, f, value, p.nodes[field].type_id); if cg_diverges(p, value) { return; } }
                binding = p.nodes[binding].next;
            }
        } else {
            let element = p.types[id].element; var child = n.first;
            while child >= 0 { cg_capture_literal(p, m, f, child, element); if cg_diverges(p, child) { return; } child = p.nodes[child].next; }
            if n.right >= 0 {
                cg_to(p, m, f, n.right, TYPE_U64); if cg_diverges(p, n.right) { return; }
                let count = cg_save(f, 0x7e); f.work.push(-node - 1); f.work.push(count); f.work.push(TYPE_U64);
            }
        }
        return;
    }
    cg_to(p, m, f, node, id); if cg_diverges(p, node) { return; } var value = cg_save(f, cg_wasm_type(p, id));
    if cg_aggregate(p, id) { let snapshot = cg_temporary(p, f, id); cg_copy(p, m, f, id, snapshot, value, node); value = snapshot; }
    f.work.push(node); f.work.push(value); f.work.push(id);
}
recursive fn cg_literal_count(p: Program&, m: CgModule&, f: CgBody&, node: i64, captured: i64 = -1) -> i64 {
    let n = p.nodes[node];
    if n.right >= 0 {
        if captured >= 0 { cg_get(f, cg_literal_saved(p, f, captured, -node - 1)); }
        else { cg_to(p, m, f, n.right, TYPE_U64); }
        let wide = cg_save(f, 0x7e); cg_get(f, wide); wb_i64(f.code, 4294967295); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array repetition count out of range");
        cg_get(f, wide); wb_byte(f.code, 0xa7); return cg_save(f, 0x7f);
    }
    var count = 0; var child = n.first; while child >= 0 { count += 1; child = p.nodes[child].next; }
    wb_i32(f.code, count); return cg_save(f, 0x7f);
}
recursive fn cg_literal_elements(p: Program&, m: CgModule&, f: CgBody&, node: i64, element: i64, destination: i64, count: i64, captured: i64 = -1, in_place: bool = false) {
    let n = p.nodes[node]; let mark = f.work.len; var replay = captured;
    if n.right >= 0 && n.first >= 0 {
        if replay < 0 { replay = mark; cg_capture_literal(p, m, f, n.first, element); if cg_diverges(p, n.first) { f.work.resize(mark); return; } }
        wb_i32(f.code, 0); let index = cg_save(f, 0x7f); let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
        cg_get(f, index); cg_get(f, count); wb_byte(f.code, 0x4f); cg_branch(p, f, done, true);
        cg_get(f, destination); cg_get(f, index); wb_i32(f.code, cg_size(p, element)); wb_byte(f.code, 0x6c); wb_byte(f.code, 0x6a); let address = cg_save(f, 0x7f);
        cg_literal_at(p, m, f, n.first, element, address, replay, in_place);
        cg_get(f, index); wb_i32(f.code, 1); wb_byte(f.code, 0x6a); cg_set(f, index); cg_branch(p, f, again, false); cg_end(f); cg_end(f);
    } else {
        var child = n.first; var ordinal = 0;
        while child >= 0 {
            cg_get(f, destination); wb_i32(f.code, ordinal * cg_size(p, element)); wb_byte(f.code, 0x6a); let address = cg_save(f, 0x7f);
            cg_literal_at(p, m, f, child, element, address, replay, in_place); if cg_diverges(p, child) { break; } child = p.nodes[child].next; ordinal += 1;
        }
    }
    f.work.resize(mark);
}
recursive fn cg_literal_at(p: Program&, m: CgModule&, f: CgBody&, node: i64, id: i64, destination: i64, captured: i64 = -1, in_place: bool = false) {
    if cg_relative_literal(p, node, id) {
        let n = p.nodes[node];
        if n.kind == N_RECORD { cg_record_fields(p, m, f, id, destination, node, captured, in_place); }
        else {
            let count = cg_literal_count(p, m, f, node, captured); cg_check_array_length(p, m, f, id, count, node);
            cg_get(f, count); wb_i32(f.code, p.types[id].count); wb_byte(f.code, 0x4b); cg_trap_if(p, m, f, node, "array capacity exceeded");
            if !in_place { cg_get(f, destination); wb_i32(f.code, 0); wb_i32(f.code, cg_size(p, id)); wb_fill(f.code); } var data = destination;
            if p.types[id].array_kind == A_LIMITED { cg_get(f, destination); cg_get(f, count); cg_length_store(p, f, id); cg_get(f, destination); wb_i32(f.code, cg_static_prefix(p, id)); wb_byte(f.code, 0x6a); data = cg_save(f, 0x7f); }
            cg_literal_elements(p, m, f, node, p.types[id].element, data, count, captured, in_place);
        }
        return;
    }
    if captured >= 0 { cg_get(f, cg_literal_saved(p, f, captured, node)); }
    else { cg_to(p, m, f, node, id); }
    if !cg_diverges(p, node) { cg_write_value(p, m, f, id, destination, node); }
}
recursive fn cg_record_literal(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n = p.nodes[node]; let id = n.type_id;
    if m.regions_enabled && (cg_frame_owner(p, id) || cg_image_owner(p, id) || cg_enum_image(p, id)) {
        var receiving = -1; if f.active_node == node && f.active_destination >= 0 { receiving = f.active_destination; }
        else { receiving = cg_temporary_destination(p, m, f, id, node); }
        cg_construct_region(p, m, f, node, receiving); cg_get(f, f.construction_destinations[receiving].header); return;
    }
    let destination = cg_temporary(p, f, id);
    if cg_enum_image(p, id) {
        var variant = n.symbol; if variant < 0 { variant = p.types[id].first; }
        if variant < 0 { cg_fail(p, node, "wasm: enum construction has no variant"); return; }
        let payload_id = p.nodes[variant].type_id; let payload = cg_temporary(p, f, payload_id);
        cg_record_fields(p, m, f, payload_id, payload, node); cg_enum_variant_image(p, m, f, id, destination, variant, payload, node);
    } else { cg_record_fields(p, m, f, id, destination, node); }
    cg_get(f, destination);
}
fn cg_result_channels(p: Program&, node: i64) -> bool {
    let n = p.nodes[node];
    if n.kind == N_CALL { return (n.flags & F_DISPATCH) == 0 && (n.symbol < 0 || (p.symbols[n.symbol].flags & S_BUILTIN) == 0); }
    return n.kind == N_BLOCK || n.kind == N_IF || n.kind == N_GUARD || n.kind == N_MATCH || n.kind == N_LOOP || n.kind == N_WHILE;
}
fn cg_forward_result_channel(p: Program&, node: i64, ordinal: i64) -> bool {
    if !cg_result_channels(p, node) { return false; }
    if p.nodes[node].kind == N_CALL { return true; }
    return cg_region_value(p, cg_result_at(p, p.nodes[node].type_id, ordinal));
}
fn cg_fixed_result_channel(p: Program&, node: i64) -> bool {
    let n = p.nodes[node];
    if n.kind == N_CALL { return n.symbol < 0 || (p.symbols[n.symbol].flags & S_BUILTIN) == 0; }
    return cg_result_channels(p, node);
}
recursive fn cg_set_values(p: Program&, m: CgModule&, f: CgBody&, first: i64, type_id: i64, first_slot: i64, node: i64) {
    let count = cg_result_count(p, type_id);
    if count == 0 { if first >= 0 { cg_discard(p, m, f, first); } return; }
    if first < 0 { cg_fail(p, node, "wasm: missing control result"); return; }
    if p.nodes[first].next < 0 && cg_type_kind(p, p.nodes[first].type_id) == TY_TUPLE {
        let mark = f.work.len;
        for ordinal in 0..count {
            var id = cg_result_at(p, p.nodes[first].type_id, ordinal); let receiving = cg_receiving(f, first_slot, ordinal);
            if m.regions_enabled && cg_forward_result_channel(p, first, ordinal) && receiving >= 0 && cg_region_value(p, f.construction_destinations[receiving].type_id) { id = f.construction_destinations[receiving].type_id; }
            f.work.push(cg_local(f, cg_wasm_type(p, id)));
        }
        let receiving_mark = f.receiving.len; let delivery = f.work.len;
        for ordinal in 0..count {
            let receiving = cg_receiving(f, first_slot, ordinal); var stage = -1; var start = -1; var landing = 0;
            if m.regions_enabled && cg_forward_result_channel(p, first, ordinal) && receiving >= 0 {
                let target = f.construction_destinations[receiving]; let id = target.type_id; let natural = cg_result_at(p, p.nodes[first].type_id, ordinal);
                let image = cg_image_owner(p, id) || cg_enum_image(p, id) || cg_owner(p, id) && (p.types[id].array_kind == A_VAR && !target.elements || p.types[id].array_kind == A_LIMITED);
                if image {
                    let original = cg_region_header(p, f, id, target.header); start = cg_region_cursor(f, original);
                    if f.constructions[target.construction].open > target.open0 { landing = 1; }
                    stage = cg_share_destination(p, m, f, receiving, id, target.elements, false, true, first);
                    f.receiving.push(CgReceiving { slot: -2 - first, ordinal: ordinal, destination: stage });
                } else { f.receiving.push(CgReceiving { slot: -2 - first, ordinal: ordinal, destination: receiving }); }
            } else if receiving >= 0 && cg_fixed_result_channel(p, first) &&
                      cg_result_at(p, p.nodes[first].type_id, ordinal) == f.construction_destinations[receiving].type_id &&
                      cg_fixed_relative(p, f.construction_destinations[receiving].type_id) {
                f.receiving.push(CgReceiving { slot: -2 - first, ordinal: ordinal, destination: receiving });
            }
            f.work.push(stage); f.work.push(start); f.work.push(landing);
        }
        cg_expr(p, m, f, first); f.receiving.resize(receiving_mark); if cg_diverges(p, first) { f.work.resize(mark); return; } var at = count;
        while at > 0 { at--; cg_set(f, f.work[mark + at]); }
        for ordinal in 0..count {
            let stage = f.work[delivery + ordinal * 3];
            if stage >= 0 {
                let receiving = cg_receiving(f, first_slot, ordinal); let target = f.construction_destinations[receiving]; let start = f.work[delivery + ordinal * 3 + 1]; let land = f.work[delivery + ordinal * 3 + 2] != 0;
                if cg_enum_image(p, target.type_id) { cg_finish_enum(p, m, f, target.type_id, target.header, start, land, node); }
                else if cg_image_owner(p, target.type_id) { cg_finish_record_image(p, m, f, target.type_id, target.header, start, land, node); }
                else { cg_finish_region_array(p, m, f, target.header, f.construction_destinations[stage].header, start, target.type_id, target.elements, land, node); }
            }
        }
        for ordinal in 0..count {
            let from = cg_result_at(p, p.nodes[first].type_id, ordinal); let to = cg_result_at(p, type_id, ordinal);
            let receiving = cg_receiving(f, first_slot, ordinal);
            if receiving >= 0 && from == to && to == f.construction_destinations[receiving].type_id && cg_fixed_relative(p, to) {
                let target = f.construction_destinations[receiving];
                if !cg_fixed_result_channel(p, first) { cg_get(f, f.work[mark + ordinal]); cg_write_value(p, m, f, to, target.header, node); }
                cg_get(f, target.header);
            } else if m.regions_enabled && receiving >= 0 && cg_region_value(p, to) {
                if !cg_forward_result_channel(p, first, ordinal) { cg_construct_captured(p, m, f, from, f.work[mark + ordinal], receiving, node); }
                cg_get(f, f.construction_destinations[receiving].header);
            }
            else { cg_get(f, f.work[mark + ordinal]); cg_convert(p, m, f, from, to, node); }
            cg_set(f, first_slot + ordinal);
        }
        f.work.resize(mark); return;
    }
    var item = first; var ordinal = 0;
    while item >= 0 && ordinal < count {
        let id = cg_result_at(p, type_id, ordinal); let receiving = cg_receiving(f, first_slot, ordinal);
        if receiving >= 0 && cg_fixed_relative(p, f.construction_destinations[receiving].type_id) {
            let target = f.construction_destinations[receiving]; cg_fixed_to(p, m, f, item, target.type_id, target.header);
            if cg_diverges(p, item) { return; } cg_get(f, target.header); cg_set(f, first_slot + ordinal); item = p.nodes[item].next; ordinal += 1; continue;
        }
        if m.regions_enabled && receiving >= 0 && cg_region_value(p, f.construction_destinations[receiving].type_id) {
            var destination = receiving;
            if !f.construction_destinations[receiving].normal {
                var target = f.construction_destinations[receiving]; target.normal = true; destination = f.construction_destinations.len; f.construction_destinations.push(target);
            }
            cg_construct_region(p, m, f, item, destination); if cg_diverges(p, item) { return; }
            cg_get(f, f.construction_destinations[receiving].header); cg_set(f, first_slot + ordinal);
            item = p.nodes[item].next; ordinal += 1; continue;
        }
        let saved_raw = f.raw_node;
        if cg_raw_slot(f, first_slot) && ordinal == 0 { f.raw_node = item; }
        cg_to(p, m, f, item, id); f.raw_node = saved_raw;
        if cg_diverges(p, item) { return; }
        if cg_aggregate(p, id) && ordinal + 1 < count {
            let source = cg_save(f, 0x7f); let snapshot = cg_temporary(p, f, id);
            if cg_named_owner(p, f, item, id) {
                cg_get(f, snapshot); cg_get(f, source); wb_i32(f.code, cg_size(p, id)); wb_copy(f.code);
            } else { cg_copy(p, m, f, id, snapshot, source, item); }
            cg_get(f, snapshot);
        }
        cg_set(f, first_slot + ordinal);
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
fn cg_effect_values_end(p: Program&, type_id: i64) -> i64 {
    var offset = 16;
    for ordinal in 0..cg_result_count(p, type_id) { offset = cg_align(offset, 8) + cg_size(p, cg_result_at(p, type_id, ordinal)); }
    return offset;
}
fn cg_owned_effect_metadata(p: Program&, type_id: i64) -> i64 { return cg_align(cg_effect_values_end(p, type_id), 8); }
fn cg_fixed_relative_results(p: Program&, type_id: i64) -> bool {
    for ordinal in 0..cg_result_count(p, type_id) { if cg_fixed_relative(p, cg_result_at(p, type_id, ordinal)) { return true; } } return false;
}
let CG_EFFECT_SCANNED: i64 = 1152921504606846976;
let CG_EFFECT_TARGET: i64 = 2305843009213693952;
recursive fn cg_scan_effect_body(p: Program&, owner: i64, node: i64) {
    if node < 0 { return; } let n = p.nodes[node];
    if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE || n.kind == N_PATTERN { return; }
    if n.kind == N_RETURN && n.symbol >= 0 && (p.symbols[n.symbol].flags & S_FUNCTION) != 0 {
        let target = p.symbols[n.symbol].node;
        if target >= 0 && target != owner { p.nodes[target].flags |= CG_EFFECT_TARGET; p.nodes[node].flags |= F_NONLOCAL; }
    }
    cg_scan_effect_body(p, owner, n.left); cg_scan_effect_body(p, owner, n.right); cg_scan_effect_body(p, owner, n.third);
    var child = n.first; while child >= 0 { cg_scan_effect_body(p, owner, child); child = p.nodes[child].next; }
}
fn cg_scan_effect_targets(p: Program&) {
    for n, node in p.nodes { if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE { p.nodes[node].flags = (n.flags & ~CG_EFFECT_TARGET) | CG_EFFECT_SCANNED; } }
    for n, node in p.nodes {
        if (n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE) && (n.flags & F_CHECKED) != 0 && (n.flags & F_GENERIC) == 0 { cg_scan_effect_body(p, node, n.right); }
    }
}
fn cg_nonlocal_target(p: Program&, function: i64) -> bool { return function >= 0 && (p.nodes[function].flags & CG_EFFECT_TARGET) != 0; }
fn cg_effect_frame(p: Program&, m: CgModule&, f: CgBody&, target: i64, node: i64) -> i64 {
    wb_op(f.code, 0x23, 4); let frame = cg_save(f, 0x7f);
    let found = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
    cg_get(f, frame); wb_byte(f.code, 0x45); cg_trap_if(p, m, f, node, "nonlocal return target is no longer active");
    cg_get(f, frame); wb_mem(f.code, 0x28, 2, 4); wb_i32(f.code, target + 1); wb_byte(f.code, 0x46); cg_branch(p, f, found, true);
    cg_get(f, frame); wb_mem(f.code, 0x28, 2, 0); cg_set(f, frame); cg_branch(p, f, again, false); cg_end(f); cg_end(f); return frame;
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
    let frame = cg_effect_frame(p, m, f, target, node); let first_slot = cg_control_slots(p, f, target_type, node);
    let attempt_mark = f.work.len;
    for ordinal in 0..count {
        let id = cg_result_at(p, target_type, ordinal); var stage = -1; var start = -1;
        if m.regions_enabled && cg_region_value(p, id) {
            let metadata = cg_owned_effect_metadata(p, target_type) + ordinal * 12;
            cg_get(f, frame); wb_mem(f.code, 0x28, 2, metadata); let original = cg_save(f, 0x7f);
            let original_tail = cg_region_header(p, f, id, original); start = cg_region_cursor(f, original_tail);
            cg_get(f, frame); wb_mem(f.code, 0x28, 2, metadata + 8); let entry = cg_save(f, 0x7f);
            let receiver = cg_destination(f, id, original, CG_CALLER, false, false, false, entry, -1);
            let receiving = cg_share_destination(p, m, f, receiver, id, false, false, true, node); stage = f.construction_destinations[receiving].header;
            f.receiving.push(CgReceiving { slot: first_slot, ordinal: ordinal, destination: receiving });
        } else if cg_fixed_relative(p, id) {
            let metadata = cg_owned_effect_metadata(p, target_type) + ordinal * 12;
            cg_get(f, frame); wb_mem(f.code, 0x28, 2, metadata); let original = cg_save(f, 0x7f);
            let receiving = cg_destination(f, id, original, CG_CALLER, false, false, false, -1, -1);
            f.receiving.push(CgReceiving { slot: first_slot, ordinal: ordinal, destination: receiving });
        }
        f.work.push(stage); f.work.push(start);
    }
    cg_set_values(p, m, f, n.first, target_type, first_slot, node);
    var offset = 16;
    for ordinal in 0..count {
        let id = cg_result_at(p, target_type, ordinal); offset = cg_align(offset, 8);
        if cg_fixed_relative(p, id) { offset += cg_size(p, id); continue; }
        cg_get(f, frame); wb_i32(f.code, offset); wb_byte(f.code, 0x6a); let destination = cg_save(f, 0x7f);
        if f.work[attempt_mark + ordinal * 2] >= 0 { cg_get(f, destination); cg_get(f, f.work[attempt_mark + ordinal * 2]); wb_i32(f.code, cg_size(p, id)); wb_copy(f.code); }
        else { cg_get(f, first_slot + ordinal); cg_write_value(p, m, f, id, destination, node); }
        offset += cg_size(p, id);
    }
    for ordinal in 0..count {
        if f.work[attempt_mark + ordinal * 2 + 1] >= 0 { cg_get(f, frame); cg_get(f, f.work[attempt_mark + ordinal * 2 + 1]); wb_mem(f.code, 0x36, 2, cg_owned_effect_metadata(p, target_type) + ordinal * 12 + 4); }
    }
    f.work.resize(attempt_mark); cg_get(f, frame); wb_op(f.code, 0x24, 2); cg_branch(p, f, f.done, false);
}
fn cg_assignment_operator(op: i64) -> i64 {
    if op == T_PLUSEQ || op == T_INC { return T_PLUS; } if op == T_MINUSEQ || op == T_DEC { return T_MINUS; }
    if op == T_MULEQ { return T_MUL; } if op == T_DIVEQ { return T_DIV; } if op == T_MODEQ { return T_MOD; }
    if op == T_ANDEQ { return T_BITAND; } if op == T_OREQ { return T_BITOR; } if op == T_XOREQ { return T_XOR; }
    if op == T_SHLEQ { return T_SHL; } if op == T_SHREQ { return T_SHR; } return op;
}
recursive fn cg_region_limited_assignment(p: Program&, m: CgModule&, f: CgBody&, node: i64, id: i64, header: i64) {
    let temporary = cg_temporary_destination(p, m, f, id, node); cg_construct_array(p, m, f, p.nodes[node].right, temporary);
    if cg_diverges(p, p.nodes[node].right) { return; }
    let source = f.construction_destinations[temporary].header; cg_owner_read_length(p, m, f, source, node); let count = cg_save(f, 0x7f);
    cg_owner_read_capacity(p, m, f, header); let capacity = cg_save(f, 0x7f); cg_get(f, count); cg_get(f, capacity); wb_byte(f.code, 0x4b); cg_trap_if(p, m, f, node, "array capacity exceeded");
    cg_owner_read_base(p, m, f, source, node); let source_base = cg_save(f, 0x7f); cg_owner_read_base(p, m, f, header, node); let base = cg_save(f, 0x7f);
    let element = p.types[id].element; var bytes = -1;
    if p.types[element].storage == 1 {
        cg_get(f, count); wb_byte(f.code, 0xad); let wide = cg_save(f, 0x7e); let end = cg_walk_elements(p, m, f, source_base, wide, node);
        cg_get(f, end); cg_get(f, source_base); wb_byte(f.code, 0x6b); bytes = cg_save(f, 0x7f);
    } else { cg_get(f, count); wb_i32(f.code, cg_size(p, element)); wb_byte(f.code, 0x6c); bytes = cg_save(f, 0x7f); }
    cg_get(f, base); wb_byte(f.code, 0xad); cg_get(f, bytes); wb_byte(f.code, 0xad); wb_byte(f.code, 0x7c); let end = cg_save(f, 0x7e);
    cg_get(f, end); cg_get(f, header); wb_mem(f.code, 0x28, 2, 8); wb_byte(f.code, 0xad); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array image exceeds data region");
    cg_get(f, end); wb_byte(f.code, 0xa7); let copied_end = cg_save(f, 0x7f); cg_ensure_memory(p, m, f, copied_end, node);
    cg_get(f, base); cg_get(f, source_base); cg_get(f, bytes); wb_copy(f.code); cg_owner_set_length(p, m, f, header, count, node);
    if p.types[element].storage == 1 { cg_region_publish(f, header, copied_end); }
    else { cg_get(f, base); cg_get(f, capacity); wb_i32(f.code, cg_size(p, element)); wb_byte(f.code, 0x6c); wb_byte(f.code, 0x6a); let top = cg_save(f, 0x7f); cg_region_publish(f, header, top); }
}
recursive fn cg_assign(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n = p.nodes[node]; var id = p.nodes[n.left].type_id;
    if cg_type_kind(p, id) == TY_REF && n.integer != T_DOTASSIGN { cg_expr(p, m, f, n.left); id = p.types[id].element; }
    else { cg_address(p, m, f, n.left); }
    let address = cg_save(f, 0x7f);
    if (n.integer == T_ASSIGN || n.integer == T_DOTASSIGN) && cg_fixed_relative(p, id) {
        cg_fixed_to(p, m, f, n.right, id, address); return;
    }
    if m.regions_enabled && (n.integer == T_ASSIGN || n.integer == T_DOTASSIGN) && cg_region_value(p, id) {
        if cg_owner(p, id) && p.types[id].array_kind == A_LIMITED { cg_region_limited_assignment(p, m, f, node, id, address); return; }
        let header = cg_region_header(p, f, id, address);
        if cg_frame_owner(p, id) || p.types[id].array_kind == A_GROW || p.types[id].array_kind == A_GROWSHRINK {
            cg_owner_read_base(p, m, f, header, node); let base = cg_save(f, 0x7f); cg_region_publish(f, header, base);
        }
        let entry = cg_region_cursor(f, header); let receiving = cg_destination(f, id, address, CG_EXISTING, false, false, false, entry, -1);
        cg_construct_region(p, m, f, n.right, receiving); return;
    }
    if (n.integer == T_ASSIGN || n.integer == T_DOTASSIGN) && cg_owner(p, id) && p.types[id].array_kind == A_LIMITED {
        cg_expr(p, m, f, n.right); cg_pack_view(p, m, f, p.nodes[n.right].type_id, node); let view = cg_save(f, 0x7e);
        cg_get(f, view); wb_i64(f.code, 32); wb_byte(f.code, 0x88); wb_byte(f.code, 0xa7); let count = cg_save(f, 0x7f);
        cg_get(f, count); cg_owner_read_capacity(p, m, f, address); wb_byte(f.code, 0x4b); cg_trap_if(p, m, f, node, "array capacity exceeded");
        cg_owner_read_base(p, m, f, address, node); cg_get(f, view); wb_byte(f.code, 0xa7); cg_get(f, count); wb_i32(f.code, cg_size(p, p.types[id].element)); wb_byte(f.code, 0x6c); wb_copy(f.code);
        cg_owner_set_length(p, m, f, address, count, node); return;
    }
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
fn cg_mark_publications(m: CgModule&, f: CgBody&) -> i64 {
    if !m.regions_enabled { return -1; } wb_op(f.code, 0x23, 11); return cg_save(f, 0x7f);
}
fn cg_restore_publications(f: CgBody&, mark: i64) { if mark >= 0 { cg_get(f, mark); wb_op(f.code, 0x24, 11); } }
fn cg_publish_header(m: CgModule&, f: CgBody&, header: i64, word: i64) {
    if m.header_helper >= 0 { cg_get(f, header); wb_i32(f.code, word); wb_op(f.code, 0x10, m.header_helper); }
}
fn cg_canonical_address(m: CgModule&, f: CgBody&, bytes: i64) {
    if m.prefix_helper >= 0 && bytes > 0 { wb_i32(f.code, bytes); wb_op(f.code, 0x10, m.prefix_helper); }
}
fn cg_map_frame(p: Program&, m: CgModule&, f: CgBody&, source: i64, target: i64, prefix: i64) -> i64 {
    let previous = cg_mark_publications(m, f); let offset = cg_frame(f, 24, 4); cg_frame_address(f, offset); let entry = cg_save(f, 0x7f);
    cg_get(f, entry); cg_get(f, previous); wb_mem(f.code, 0x36, 2, 0);
    cg_get(f, entry); cg_get(f, source); wb_mem(f.code, 0x36, 2, 4);
    cg_get(f, entry); cg_get(f, target); wb_mem(f.code, 0x36, 2, 8);
    for word in [12, 16] { cg_get(f, entry); wb_i32(f.code, prefix); wb_mem(f.code, 0x36, 2, word); }
    cg_get(f, entry); wb_i32(f.code, 1); wb_mem(f.code, 0x36, 2, 20);
    cg_get(f, entry); wb_op(f.code, 0x24, 11); return previous;
}
fn cg_map_header(p: Program&, m: CgModule&, f: CgBody&, source: i64, target: i64) -> i64 {
    let previous = cg_map_frame(p, m, f, source, target, 0); wb_op(f.code, 0x23, 11); wb_i32(f.code, 0); wb_mem(f.code, 0x36, 2, 20); return previous;
}
fn cg_header_publish_body(out: u8[>..]&) {
    // (header,word)->void; follow scoped array/frame publication channels.
    wb_u(out, 1); wb_u(out, 2); wb_byte(out, 0x7f);
    wb_byte(out, 0x02); wb_byte(out, 0x40); wb_byte(out, 0x03); wb_byte(out, 0x40);
    wb_op(out, 0x23, 11); wb_op(out, 0x21, 2); wb_byte(out, 0x03); wb_byte(out, 0x40);
    wb_op(out, 0x20, 2); wb_byte(out, 0x45); wb_op(out, 0x0d, 2);
    wb_op(out, 0x20, 0); wb_op(out, 0x20, 2); wb_mem(out, 0x28, 2, 4); wb_op(out, 0x20, 2); wb_mem(out, 0x28, 2, 16); wb_byte(out, 0x6a); wb_byte(out, 0x46);
    wb_op(out, 0x20, 1); wb_i32(out, 4); wb_byte(out, 0x46);
    wb_op(out, 0x20, 1); wb_byte(out, 0x45); wb_op(out, 0x20, 2); wb_mem(out, 0x28, 2, 20); wb_byte(out, 0x71); wb_byte(out, 0x72); wb_byte(out, 0x71); wb_byte(out, 0x04); wb_byte(out, 0x40);
    wb_op(out, 0x20, 2); wb_mem(out, 0x28, 2, 8); wb_op(out, 0x20, 2); wb_mem(out, 0x28, 2, 16); wb_byte(out, 0x6a); wb_op(out, 0x21, 3);
    wb_op(out, 0x20, 3); wb_op(out, 0x20, 1); wb_byte(out, 0x6a); wb_op(out, 0x20, 0); wb_op(out, 0x20, 1); wb_byte(out, 0x6a); wb_mem(out, 0x28, 2, 0); wb_mem(out, 0x36, 2, 0);
    wb_op(out, 0x20, 3); wb_op(out, 0x21, 0); wb_op(out, 0x0c, 2); wb_byte(out, 0x0b);
    wb_op(out, 0x20, 2); wb_mem(out, 0x28, 2, 0); wb_op(out, 0x21, 2); wb_op(out, 0x0c, 0);
    wb_byte(out, 0x0b); wb_byte(out, 0x0b); wb_byte(out, 0x0b); wb_byte(out, 0x0b);
}
fn cg_prefix_mapping_body(out: u8[>..]&) {
    // (address,bytes)->address; a fixed access must fit the complete mapped prefix.
    wb_u(out, 1); wb_u(out, 2); wb_byte(out, 0x7f);
    wb_byte(out, 0x02); wb_byte(out, 0x40); wb_byte(out, 0x03); wb_byte(out, 0x40);
    wb_op(out, 0x23, 11); wb_op(out, 0x21, 2); wb_byte(out, 0x03); wb_byte(out, 0x40);
    wb_op(out, 0x20, 2); wb_byte(out, 0x45); wb_op(out, 0x0d, 2);
    wb_op(out, 0x20, 2); wb_mem(out, 0x28, 2, 12); wb_byte(out, 0x04); wb_byte(out, 0x40);
    wb_op(out, 0x20, 2); wb_mem(out, 0x28, 2, 4); wb_op(out, 0x21, 3);
    wb_op(out, 0x20, 0); wb_op(out, 0x20, 3); wb_byte(out, 0x4f);
    wb_op(out, 0x20, 0); wb_byte(out, 0xad); wb_op(out, 0x20, 1); wb_byte(out, 0xad); wb_byte(out, 0x7c);
    wb_op(out, 0x20, 3); wb_byte(out, 0xad); wb_op(out, 0x20, 2); wb_mem(out, 0x28, 2, 12); wb_byte(out, 0xad); wb_byte(out, 0x7c); wb_byte(out, 0x58); wb_byte(out, 0x71); wb_byte(out, 0x04); wb_byte(out, 0x40);
    wb_op(out, 0x20, 2); wb_mem(out, 0x28, 2, 8); wb_op(out, 0x20, 0); wb_op(out, 0x20, 3); wb_byte(out, 0x6b); wb_byte(out, 0x6a); wb_op(out, 0x21, 0); wb_op(out, 0x0c, 3);
    wb_byte(out, 0x0b); wb_byte(out, 0x0b);
    wb_op(out, 0x20, 2); wb_mem(out, 0x28, 2, 0); wb_op(out, 0x21, 2); wb_op(out, 0x0c, 0);
    wb_byte(out, 0x0b); wb_byte(out, 0x0b); wb_byte(out, 0x0b); wb_op(out, 0x20, 0); wb_byte(out, 0x0b);
}
fn cg_mark_regions(f: CgBody&) -> i64 { wb_op(f.code, 0x23, 3); return cg_save(f, 0x7f); }
fn cg_restore_regions(f: CgBody&, mark: i64) { if mark >= 0 { cg_get(f, mark); wb_op(f.code, 0x24, 3); } }
fn cg_named_result(p: Program&, function: i64, ordinal: i64) -> i64 {
    if function < 0 || p.nodes[function].kind == N_FUNCTION_VALUE { return -1; } var binding = p.nodes[function].named_results;
    while binding >= 0 { if p.nodes[binding].integer == ordinal { return p.nodes[binding].symbol; } binding = p.nodes[binding].next; } return -1;
}
fn cg_named_array_mode(p: Program&, from: i64, to: i64) -> bool {
    if cg_frame_owner(p, from) || cg_frame_owner(p, to) || cg_image_owner(p, from) || cg_image_owner(p, to) || cg_enum_image(p, from) || cg_enum_image(p, to) { return from == to; }
    if !cg_owner(p, from) || !cg_owner(p, to) || p.types[from].element != p.types[to].element { return false; }
    if (p.types[from].array_kind == A_GROW || p.types[from].array_kind == A_GROWSHRINK) && p.types[to].array_kind == A_VAR { return true; }
    if p.types[from].array_kind != p.types[to].array_kind { return false; }
    return p.types[from].array_kind != A_VAR || p.types[from].length_storage == p.types[to].length_storage;
}
fn cg_named_array_destination(p: Program&, f: CgBody&, symbol: i64) -> i64 {
    var binding = f.receiving.len;
    while binding > 0 { binding -= 1; let item = f.receiving[binding]; if item.slot == -1 && item.symbol == symbol { return item.destination; } }
    if f.function < 0 || f.elements || symbol < 0 || f.results.len == 0 { return -1; }
    let result = cg_result_type(p, f.function); let count = cg_result_count(p, result);
    for ordinal in 0..count {
        if cg_named_result(p, f.function, ordinal) == symbol && cg_named_array_mode(p, p.symbols[symbol].type_id, cg_result_at(p, result, ordinal)) { return cg_receiving(f, f.results[0], ordinal); }
    }
    return -1;
}
fn cg_same_destination(f: CgBody&, left: i64, right: i64) -> bool {
    if left < 0 || right < 0 { return false; }
    return f.construction_destinations[left].header == f.construction_destinations[right].header && f.construction_destinations[left].type_id == f.construction_destinations[right].type_id;
}
fn cg_bind_inline_results(p: Program&, f: CgBody&, node: i64, first_slot: i64) -> i64 {
    let mark = f.receiving.len;
    if p.nodes[node].origin >= 0 && p.nodes[p.nodes[node].origin].kind == N_FUNCTION_VALUE { return mark; }
    var binding = p.nodes[node].named_results;
    while binding >= 0 {
        let n = p.nodes[binding]; let receiving = cg_receiving(f, first_slot, n.integer);
        if receiving >= 0 && n.symbol >= 0 && cg_named_array_mode(p, p.symbols[n.symbol].type_id, f.construction_destinations[receiving].type_id) {
            let local = p.symbols[n.symbol].type_id;
            if f.construction_destinations[receiving].elements && cg_owner(p, local) && p.types[local].array_kind != A_GROW && p.types[local].array_kind != A_GROWSHRINK { binding = n.next; continue; }
            f.receiving.push(CgReceiving { slot: -1, ordinal: n.integer, destination: receiving, symbol: n.symbol });
        }
        binding = n.next;
    }
    return mark;
}
fn cg_named_prefix(f: CgBody&, symbol: i64) -> i64 {
    var at = f.receiving.len;
    while at > 0 { at -= 1; let binding = f.receiving[at]; if binding.symbol == symbol && binding.prefix >= 0 { return binding.prefix; } }
    return -1;
}
fn cg_prepare_named_prefix(p: Program&, m: CgModule&, f: CgBody&, node: i64, symbol: i64, named: i64) {
    let local = p.symbols[symbol].type_id; let target = f.construction_destinations[named]; let id = target.type_id;
    if !cg_owner(p, local) || !cg_owner(p, id) || target.elements || p.types[id].array_kind != A_VAR ||
       p.types[local].array_kind != A_GROW && p.types[local].array_kind != A_GROWSHRINK { return; }
    var prefix = target.header; var receiving = named;
    if cg_nonlocal_target(p, f.function) {
        prefix = cg_temporary(p, f, id); cg_get(f, prefix); wb_i32(f.code, 0); wb_i32(f.code, 24); wb_fill(f.code);
        for word in [0, 8] { cg_get(f, prefix); cg_get(f, target.header); wb_mem(f.code, 0x28, 2, word); wb_mem(f.code, 0x36, 2, word); }
        receiving = cg_destination(f, id, prefix, target.lifetime, false, false, false, target.entry, target.construction);
    }
    let saved_node = f.active_node; let saved_destination = f.active_destination; let saved_raw = f.raw_node;
    f.active_node = node; f.active_destination = receiving; f.raw_node = -1;
    wb_i32(f.code, 0); let zero = cg_save(f, 0x7f); cg_region_array_prefix(p, m, f, id, prefix, zero, zero, node);
    f.active_node = saved_node; f.active_destination = saved_destination; f.raw_node = saved_raw;
    f.receiving.push(CgReceiving { slot: -1, ordinal: 0, destination: named, symbol: symbol, prefix: prefix });
}
recursive fn cg_region_declaration(p: Program&, m: CgModule&, f: CgBody&, node: i64, binding: i64) {
    let n = p.nodes[node]; let symbol = p.nodes[binding].symbol; let id = p.symbols[symbol].type_id;
    cg_symbol_address(p, m, f, symbol, binding); let address = cg_save(f, 0x7f); let global = m.global_regions[symbol];
    let named = cg_named_array_destination(p, f, symbol); var receiving = -1;
    if named >= 0 {
        let target = f.construction_destinations[named]; f.constructions[target.construction].open += 1;
        cg_prepare_named_prefix(p, m, f, node, symbol, named);
        if (p.types[id].array_kind == A_VAR || p.types[id].array_kind == A_LIMITED || cg_image_owner(p, id) || cg_enum_image(p, id)) && !cg_nonlocal_target(p, f.function) {
            cg_get(f, target.header); cg_set(f, f.slots[symbol]); cg_get(f, target.header); cg_set(f, address);
        } else {
            let source_header = cg_region_header(p, f, id, target.header); let header = cg_region_header(p, f, id, address); let cursor = cg_region_cursor(f, source_header);
            cg_get(f, header); wb_i32(f.code, 0); wb_i32(f.code, 24); wb_fill(f.code);
            cg_get(f, header); cg_get(f, cursor); wb_mem(f.code, 0x36, 2, 0);
            cg_get(f, header); cg_get(f, source_header); wb_mem(f.code, 0x28, 2, 8); wb_mem(f.code, 0x36, 2, 8);
            if cg_enum_image(p, id) { cg_set_enum_anchor(f, address, cursor); }
            else if cg_image_owner(p, id) { cg_set_record_anchor(p, m, f, id, address, cursor, node); }
        }
        receiving = cg_destination(f, id, address, target.lifetime, false, false, false, target.entry, target.construction);
    } else {
        let header = cg_region_acquire(p, m, f, id, address, global, binding); let entry = cg_region_cursor(f, header);
        var lifetime = CG_BLOCK_OWNER; if global >= 0 { lifetime = CG_STATIC; }
        receiving = cg_destination(f, id, address, lifetime, false, false, false, entry, -1);
    }
    let keep = f.region_live; let mark = cg_mark_regions(f);
    if n.right >= 0 { cg_construct_region(p, m, f, n.right, receiving); }
    else if cg_frame_owner(p, id) || cg_image_owner(p, id) || cg_enum_image(p, id) { cg_construct_region(p, m, f, -1, receiving); }
    else {
        let saved_node = f.active_node; let saved_destination = f.active_destination; f.active_node = node; f.active_destination = receiving;
        wb_i32(f.code, 0); let count = cg_save(f, 0x7f); cg_region_owner_image(p, m, f, id, address, count, count, node);
        f.active_node = saved_node; f.active_destination = saved_destination;
    }
    cg_restore_regions(f, mark); f.region_live = keep;
}
fn cg_decl_diverges(p: Program&, node: i64) -> bool {
    if node < 0 { return false; } let n = p.nodes[node]; if cg_diverges(p, node) { return true; }
    var value = n.right; while value >= 0 { if cg_diverges(p, value) { return true; } value = p.nodes[value].next; } return false;
}
fn cg_dead_binding(p: Program&, binding: i64) -> bool {
    if binding < 0 { return false; }
    if cg_decl_diverges(p, binding) { return true; }
    for n, declaration in p.nodes {
        if n.kind == N_VARIABLE {
            var child = n.first;
            while child >= 0 { if child == binding { return cg_decl_diverges(p, declaration); } child = p.nodes[child].next; }
        }
    }
    return false;
}
recursive fn cg_divergent_declaration(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n = p.nodes[node]; var binding = node; if n.first >= 0 { binding = n.first; }
    let first = n.right;
    if first >= 0 && p.nodes[first].next < 0 && cg_diverges(p, first) {
        if m.regions_enabled && p.nodes[binding].symbol >= 0 && cg_region_value(p, p.symbols[p.nodes[binding].symbol].type_id) && (n.first < 0 || p.nodes[binding].next < 0) { cg_region_declaration(p, m, f, node, binding); }
        else { cg_expr(p, m, f, first); } return;
    }
    var value = first;
    while binding >= 0 && value >= 0 {
        if cg_diverges(p, value) { cg_expr(p, m, f, value); return; }
        let symbol = p.nodes[binding].symbol; cg_symbol_address(p, m, f, symbol, binding); let address = cg_save(f, 0x7f);
        cg_to(p, m, f, value, p.symbols[symbol].type_id); cg_write_value(p, m, f, p.symbols[symbol].type_id, address, binding);
        binding = p.nodes[binding].next; value = p.nodes[value].next;
    }
}
fn cg_binding_result_type(p: Program&, first: i64) -> i64 {
    var binding = first; var head = -1; var last = -1; var count = 0;
    while binding >= 0 {
        let argument = new_node(p, N_TYPE_ARG, p.nodes[binding].token); p.nodes[argument].type_id = p.nodes[binding].type_id;
        if last < 0 { head = argument; } else { p.nodes[last].next = argument; } last = argument; count += 1; binding = p.nodes[binding].next;
    }
    let result = p.types.len; p.types.push(Type { kind: TY_TUPLE, count: count, first: head }); return result;
}
recursive fn cg_region_multi_declaration(p: Program&, m: CgModule&, f: CgBody&, node: i64) -> i64 {
    let n = p.nodes[node]; let result_type = cg_binding_result_type(p, n.first); var binding = n.first; var first_slot = -1; var ordinal = 0;
    while binding >= 0 { let slot = cg_local(f, cg_wasm_type(p, p.nodes[binding].type_id)); if first_slot < 0 { first_slot = slot; } binding = p.nodes[binding].next; }
    binding = n.first;
    while binding >= 0 {
        let id = p.nodes[binding].type_id;
        if cg_region_value(p, id) {
            cg_symbol_address(p, m, f, p.nodes[binding].symbol, binding); let owner = cg_save(f, 0x7f); let header = cg_region_acquire(p, m, f, id, owner, -1, binding); let entry = cg_region_cursor(f, header);
            let receiving = cg_destination(f, id, owner, CG_BLOCK_OWNER, false, false, false, entry, -1); f.receiving.push(CgReceiving { slot: first_slot, ordinal: ordinal, destination: receiving });
        }
        ordinal += 1; binding = p.nodes[binding].next;
    }
    let live = f.region_live; let mark = cg_mark_regions(f); cg_set_values(p, m, f, n.right, result_type, first_slot, node);
    binding = n.first; ordinal = 0;
    while binding >= 0 {
        let id = p.nodes[binding].type_id;
        if !cg_region_value(p, id) { cg_symbol_address(p, m, f, p.nodes[binding].symbol, binding); let address = cg_save(f, 0x7f); cg_get(f, first_slot + ordinal); cg_write_value(p, m, f, id, address, binding); }
        ordinal += 1; binding = p.nodes[binding].next;
    }
    cg_restore_regions(f, mark); f.region_live = live; return 0;
}
recursive fn cg_declaration(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    cg_declaration_body(p, m, f, node);
    if m.pool_global < 0 || cg_decl_diverges(p, node) || (p.nodes[node].flags & F_REUSABLE) == 0 { return; }
    var binding = node; if p.nodes[node].first >= 0 { binding = p.nodes[node].first; }
    while binding >= 0 {
        let symbol = p.nodes[binding].symbol;
        if symbol >= 0 {
            cg_symbol_address(p, m, f, symbol, node); let header = cg_save(f, 0x7f); let state = cg_pool_state(p, m, f, header, node);
            cg_get(f, state); wb_i32(f.code, 0); wb_mem(f.code, 0x36, 2, 12);
        }
        if binding == node { break; } binding = p.nodes[binding].next;
    }
}
recursive fn cg_declaration_body(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n = p.nodes[node];
    if cg_decl_diverges(p, node) { cg_divergent_declaration(p, m, f, node); return; }
    if m.regions_enabled {
        if n.first >= 0 && p.nodes[n.first].next >= 0 { cg_region_multi_declaration(p, m, f, node); return; }
        var binding = node; if n.first >= 0 && p.nodes[n.first].next < 0 { binding = n.first; }
        let symbol = p.nodes[binding].symbol;
        if symbol >= 0 && cg_region_value(p, p.symbols[symbol].type_id) { cg_region_declaration(p, m, f, node, binding); return; }
    }
    if n.first >= 0 {
        var binding = n.first; var first_slot = -1;
        while binding >= 0 {
            let slot = cg_local(f, cg_wasm_type(p, p.nodes[binding].type_id));
            if first_slot < 0 { first_slot = slot; } binding = p.nodes[binding].next;
        }
        if n.right >= 0 && cg_type_kind(p, p.nodes[n.right].type_id) == TY_TUPLE {
            cg_set_values(p, m, f, n.right, cg_binding_result_type(p, n.first), first_slot, node);
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
            if n.right < 0 { cg_default_storage(p, m, f, p.nodes[binding].type_id, address, binding); }
            else { cg_get(f, first_slot + ordinal); cg_write_value(p, m, f, p.nodes[binding].type_id, address, binding); }
            binding = p.nodes[binding].next; ordinal++;
        }
        return;
    }
    let symbol = n.symbol;
    if symbol < 0 { cg_fail(p, node, "wasm: declaration has no symbol"); return; }
    cg_symbol_address(p, m, f, symbol, node); let address = cg_save(f, 0x7f);
    if n.right < 0 { cg_default_storage(p, m, f, n.type_id, address, node); return; }
    cg_to(p, m, f, n.right, n.type_id); cg_write_value(p, m, f, n.type_id, address, node);
}
recursive fn cg_break(p: Program&, m: CgModule&, f: CgBody&, node: i64, continuing: bool) {
    let n = p.nodes[node]; var at = f.exits.len;
    while at > 0 {
        at--; let exit = f.exits[at];
        if n.symbol >= 0 && exit.node != n.symbol { continue; }
        if continuing {
            if exit.again < 0 { continue; }
            if exit.scratch >= 0 { cg_get(f, exit.scratch); wb_op(f.code, 0x24, 0); }
            cg_restore_regions(f, exit.regions); cg_restore_publications(f, exit.publication);
            cg_branch(p, f, exit.again, false); return;
        }
        if n.left >= 0 { cg_set_values(p, m, f, n.left, exit.type_id, exit.result, node); }
        if exit.scratch >= 0 { cg_get(f, exit.scratch); wb_op(f.code, 0x24, 0); }
        cg_restore_regions(f, exit.regions); cg_restore_publications(f, exit.publication);
        cg_branch(p, f, exit.label, false); return;
    }
    cg_fail(p, node, "wasm: loop or block exit has no active target");
}
fn cg_inline_argument(p: Program&, node: i64) -> bool {
    if node < 0 { return false; } let n = p.nodes[node];
    return n.kind == N_VARIABLE && n.origin >= 0 && p.nodes[n.origin].kind == N_PARAM;
}
recursive fn cg_block_into(p: Program&, m: CgModule&, f: CgBody&, node: i64, id: i64, result: i64) {
    if node < 0 { return; }
    if p.nodes[node].kind == N_BLOCK && (p.nodes[node].flags & F_EARLY) != 0 {
        var entered = false; for exit in f.exits { if exit.node == node { entered = true; } }
        if !entered {
            if id == TYPE_VOID { cg_discard(p, m, f, node); }
            else { cg_set_values(p, m, f, node, id, result, node); }
            return;
        }
    }
    if p.nodes[node].kind != N_BLOCK {
        if cg_type_kind(p, p.nodes[node].type_id) == TY_VOID { cg_discard(p, m, f, node); }
        else { cg_set_values(p, m, f, node, id, result, node); }
        return;
    }
    let n = p.nodes[node]; var child = n.first;
    if (n.flags & F_EARLY) != 0 && n.origin >= 0 {
        while cg_inline_argument(p, child) { child = p.nodes[child].next; }
    }
    let live = f.region_live; var region_mark = -1;
    if m.regions_enabled { region_mark = cg_mark_regions(f); }
    while child >= 0 {
        let item = p.nodes[child];
        if item.kind == N_EXPR_STMT && (item.flags & (F_TAIL | F_IMPLICIT_RETURN)) != 0 {
            if id == TYPE_VOID { cg_discard(p, m, f, item.left); }
            else { cg_set_values(p, m, f, item.left, id, result, child); }
        } else if item.next < 0 && (item.flags & F_TAIL) != 0 && item.kind != N_RETURN && item.kind != N_BREAK && item.kind != N_CONTINUE {
            if id == TYPE_VOID { cg_discard(p, m, f, child); } else { cg_set_values(p, m, f, child, id, result, child); }
        } else { cg_statement(p, m, f, child); }
        if cg_terminal(p, child) { break; }
        child = item.next;
    }
    if n.right >= 0 {
        if id == TYPE_VOID { cg_discard(p, m, f, n.right); } else { cg_set_values(p, m, f, n.right, id, result, node); }
    }
    if m.regions_enabled { cg_restore_regions(f, region_mark); f.region_live = live; }
}
fn cg_control_slots(p: Program&, f: CgBody&, id: i64, node: i64) -> i64 {
    var types: i64[>..] = []; cg_result_types(p, id, types); var first = -1;
    for type_id, ordinal in types {
        var storage = type_id; let receiving = cg_receiving(f, -2 - node, ordinal);
        if receiving >= 0 { storage = f.construction_destinations[receiving].type_id; }
        else if types.len == 1 && f.active_node == node && f.active_destination >= 0 { storage = f.construction_destinations[f.active_destination].type_id; }
        let slot = cg_local(f, cg_wasm_type(p, storage)); if first < 0 { first = slot; }
    }
    if first >= 0 && cg_raw_value(f, node) { f.raw_slots.push(first); }
    for type_id, ordinal in types {
        var receiving = cg_receiving(f, -2 - node, ordinal);
        if receiving >= 0 {
            let n = p.nodes[node];
            if n.kind == N_BLOCK && (n.flags & F_EARLY) != 0 && n.origin >= 0 {
                var target = f.construction_destinations[receiving]; target.open0 = f.constructions[target.construction].open; target.escape = false;
                receiving = f.construction_destinations.len; f.construction_destinations.push(target);
            }
            f.receiving.push(CgReceiving { slot: first, ordinal: ordinal, destination: receiving });
        }
    }
    if first >= 0 && f.active_node == node && f.active_destination >= 0 && cg_receiving(f, -2 - node, 0) < 0 {
        var destination = f.active_destination; let n = p.nodes[node];
        if (n.flags & F_EARLY) != 0 || n.kind == N_LOOP || n.kind == N_WHILE {
            var target = f.construction_destinations[destination]; target.open0 = f.constructions[target.construction].open; target.escape = false;
            destination = f.construction_destinations.len; f.construction_destinations.push(target);
        }
        f.receiving.push(CgReceiving { slot: first, ordinal: 0, destination: destination });
    }
    return first;
}
fn cg_control_get(p: Program&, f: CgBody&, id: i64, first: i64) {
    var types: i64[>..] = []; cg_result_types(p, id, types); for item, i in types { cg_get(f, first + i); }
}
recursive fn cg_loop(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n = p.nodes[node]; let result = cg_control_slots(p, f, n.type_id, node);
    wb_op(f.code, 0x23, 0); let scratch = cg_save(f, 0x7f); var regions = -1; if m.regions_enabled { regions = cg_mark_regions(f); }
    let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
    f.exits.push(CgExit { label: done, again: again, node: node, result: result, type_id: n.type_id, scratch: scratch, regions: regions, publication: cg_mark_publications(m, f) });
    if n.kind == N_WHILE {
        cg_truth_scope(p, m, f, n.left);
        if cg_diverges(p, n.left) { f.exits.pop(); cg_end(f); cg_end(f); return; }
        wb_byte(f.code, 0x45); cg_branch(p, f, done, true);
    }
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
recursive fn cg_index_effects(p: Program&, node: i64) -> bool {
    if node < 0 { return false; } let n = p.nodes[node];
    if n.kind == N_CALL || n.kind == N_STRING || n.kind == N_BLOCK || n.kind == N_IF || n.kind == N_MATCH ||
       n.kind == N_LOOP || n.kind == N_WHILE || n.kind == N_FOR || n.kind == N_RETURN || n.kind == N_ASSIGN || n.kind == N_VARIABLE { return true; }
    if cg_index_effects(p, n.left) || cg_index_effects(p, n.right) || cg_index_effects(p, n.third) { return true; }
    var child = n.first; while child >= 0 { if cg_index_effects(p, child) { return true; } child = p.nodes[child].next; } return false;
}
recursive fn cg_pin_sequence(p: Program&, m: CgModule&, f: CgBody&, node: i64, address: bool) -> i64 {
    let n = p.nodes[node]; var item = CgSequence { kind: 0, node: node, address: address };
    if n.kind == N_NAME { item.kind = 1; }
    else if n.kind == N_MEMBER && n.symbol >= 0 && n.symbol < p.nodes.len && p.nodes[n.symbol].kind == N_FIELD {
        item.kind = 2; item.parent = cg_pin_sequence(p, m, f, n.left, false);
    } else if n.kind == N_INDEX {
        item.kind = 3; item.parent = cg_pin_sequence(p, m, f, n.left, false);
        var object = p.nodes[n.left].type_id; while cg_type_kind(p, object) == TY_REF { object = p.types[object].element; }
        if cg_index_effects(p, n.right) {
            cg_emit_sequence(p, m, f, item.parent); cg_pack_view(p, m, f, p.nodes[n.left].type_id, node); item.saved = cg_save(f, 0x7e);
        }
        cg_to(p, m, f, n.right, TYPE_U64); item.index = cg_save(f, 0x7e);
        if cg_type_kind(p, object) == TY_SLICE && item.saved < 0 {
            cg_emit_sequence(p, m, f, item.parent); cg_pack_view(p, m, f, p.nodes[n.left].type_id, node); wb_byte(f.code, 0xa7); item.pointer = cg_save(f, 0x7f);
        }
    } else if n.kind == N_UNARY && n.integer == T_BITAND && cg_type_kind(p, p.nodes[n.left].type_id) != TY_REF &&
              (p.nodes[n.left].kind == N_NAME || p.nodes[n.left].kind == N_MEMBER || p.nodes[n.left].kind == N_INDEX) {
        return cg_pin_sequence(p, m, f, n.left, true);
    } else {
        if address { cg_address(p, m, f, node); item.saved = cg_save(f, 0x7f); }
        else { cg_expr(p, m, f, node); item.saved = cg_save(f, cg_wasm_type(p, n.type_id)); }
    }
    let result = f.sequences.len; f.sequences.push(item); return result;
}
recursive fn cg_emit_sequence(p: Program&, m: CgModule&, f: CgBody&, recipe: i64) {
    let item = f.sequences[recipe]; let n = p.nodes[item.node];
    if item.kind == 0 { cg_get(f, item.saved); return; }
    if item.kind == 1 {
        let stored = p.symbols[n.symbol].type_id;
        cg_symbol_address(p, m, f, n.symbol, item.node);
        if item.address {
            if cg_type_kind(p, stored) == TY_REF && cg_type_kind(p, n.type_id) != TY_REF { cg_load(p, m, f, stored, 0); }
        } else if cg_type_kind(p, n.type_id) != TY_REF || cg_type_kind(p, stored) == TY_REF {
            if p.types[stored].storage == 1 { cg_load_fixed(p, f.code, TYPE_I64, 0); }
            else { cg_load(p, m, f, stored, 0); }
            cg_convert(p, m, f, stored, n.type_id, item.node);
        }
        return;
    }
    if item.kind == 2 {
        cg_emit_sequence(p, m, f, item.parent); var object = p.nodes[n.left].type_id;
        while cg_type_kind(p, object) == TY_REF { object = p.types[object].element; cg_load(p, m, f, object, 0); }
        cg_field_place(p, m, f, object, item.node); let field = p.nodes[n.symbol].type_id;
        if !item.address && (cg_type_kind(p, n.type_id) != TY_REF || cg_type_kind(p, field) == TY_REF) {
            cg_load(p, m, f, field, 0); cg_convert(p, m, f, field, n.type_id, item.node);
        }
        return;
    }
    if item.saved >= 0 { cg_get(f, item.saved); }
    else {
        cg_emit_sequence(p, m, f, item.parent); cg_pack_view(p, m, f, p.nodes[n.left].type_id, item.node);
        if item.pointer >= 0 { wb_i64(f.code, -4294967296); wb_byte(f.code, 0x83); cg_get(f, item.pointer); wb_byte(f.code, 0xad); wb_byte(f.code, 0x84); }
    }
    let view = cg_save(f, 0x7e);
    if (n.flags & F_BOUNDS_PROVEN) == 0 {
        cg_get(f, item.index); cg_get(f, view); wb_i64(f.code, 32); wb_byte(f.code, 0x88); wb_byte(f.code, 0x5a); cg_trap_if(p, m, f, item.node, "array index out of bounds");
    }
    var object = p.nodes[n.left].type_id; while cg_type_kind(p, object) == TY_REF { object = p.types[object].element; }
    let element = p.types[object].element;
    cg_get(f, view); wb_byte(f.code, 0xa7); cg_get(f, item.index); wb_byte(f.code, 0xa7); wb_i32(f.code, cg_size(p, element)); wb_byte(f.code, 0x6c); wb_byte(f.code, 0x6a);
    if !item.address && (cg_type_kind(p, n.type_id) != TY_REF || cg_type_kind(p, element) == TY_REF) {
        cg_load(p, m, f, element, 0); cg_convert(p, m, f, element, n.type_id, item.node);
    }
}
recursive fn cg_for(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n = p.nodes[node]; let iterable = p.nodes[n.left]; var type_id = iterable.type_id;
    if iterable.kind == N_RANGE {
        if cg_diverges(p, iterable.left) { cg_expr(p, m, f, iterable.left); return; }
        if cg_diverges(p, iterable.right) { cg_discard(p, m, f, iterable.left); cg_expr(p, m, f, iterable.right); return; }
    } else if cg_diverges(p, n.left) { cg_expr(p, m, f, n.left); return; }
    while cg_type_kind(p, type_id) == TY_REF { type_id = p.types[type_id].element; }
    let sequence = cg_type_kind(p, type_id) == TY_ARRAY || cg_type_kind(p, type_id) == TY_SLICE;
    var binding = n.first; if binding < 0 { cg_fail(p, node, "wasm: for loop has no binding"); return; }
    let element_binding = p.nodes[binding].symbol; binding = p.nodes[binding].next;
    var ordinal_binding = -1; if binding >= 0 { ordinal_binding = p.nodes[binding].symbol; }
    var counter_type = type_id; if sequence { counter_type = TYPE_U64; }
    var view = -1; var recipe = -1;
    if sequence {
        recipe = cg_pin_sequence(p, m, f, n.left, false); cg_emit_sequence(p, m, f, recipe); cg_pack_view(p, m, f, iterable.type_id, node); view = cg_save(f, 0x7e); wb_i64(f.code, 0);
    } else if iterable.kind == N_RANGE { cg_to(p, m, f, iterable.left, counter_type); }
    else { cg_zero(f.code, cg_wasm_type(p, counter_type)); }
    let counter = cg_save(f, cg_wasm_type(p, counter_type));
    if sequence { cg_get(f, view); wb_i64(f.code, 32); wb_byte(f.code, 0x88); }
    else if iterable.kind == N_RANGE { cg_to(p, m, f, iterable.right, counter_type); }
    else { cg_to(p, m, f, n.left, counter_type); }
    let limit = cg_save(f, cg_wasm_type(p, counter_type)); wb_i64(f.code, 0); let ordinal = cg_save(f, 0x7e);
    let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
    if sequence && !(cg_type_kind(p, type_id) == TY_ARRAY && p.types[type_id].array_kind == A_FIXED) {
        cg_emit_sequence(p, m, f, recipe); cg_pack_view(p, m, f, iterable.type_id, node); cg_set(f, view);
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
    wb_op(f.code, 0x23, 0); let scratch = cg_save(f, 0x7f); var regions = -1; if m.regions_enabled { regions = cg_mark_regions(f); }
    let step = cg_begin(f, 0x02, 0x40); f.exits.push(CgExit { label: done, again: step, node: node, scratch: scratch, regions: regions, publication: cg_mark_publications(m, f) });
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
    let n = p.nodes[node]; var id = p.nodes[n.left].type_id; cg_expr(p, m, f, n.left); if cg_diverges(p, n.left) { return; }
    if cg_type_kind(p, id) == TY_REF { id = p.types[id].element; cg_load(p, m, f, id, 0); }
    var base = -1;
    if cg_type_kind(p, id) == TY_ENUM {
        base = cg_save(f, 0x7f); cg_get(f, base);
        if cg_enum_image(p, id) { wb_mem(f.code, 0x28, 2, 0); }
        if p.types[id].length_storage == 2 { wb_mem(f.code, 0x2f, 0, 0); } else { wb_mem(f.code, 0x2d, 0, 0); }
        id = TYPE_U32;
    }
    let value = cg_save(f, cg_wasm_type(p, id)); let result = cg_control_slots(p, f, n.type_id, node); let done = cg_begin(f, 0x02, 0x40);
    var arm = n.first;
    while arm >= 0 {
        let item = p.nodes[arm]; cg_pattern(p, m, f, item.left, id, value); cg_begin(f, 0x04, 0x40);
        var binder = -1;
        if p.nodes[item.left].kind == N_PATTERN { binder = p.nodes[item.left].left; }
        if binder >= 0 && base >= 0 {
            let symbol = p.nodes[binder].symbol; cg_symbol_address(p, m, f, symbol, arm); let address = cg_save(f, 0x7f);
            var enum_id = p.nodes[n.left].type_id;
            if cg_type_kind(p, enum_id) == TY_REF { enum_id = p.types[enum_id].element; }
            var payload_type = p.symbols[symbol].type_id;
            if cg_type_kind(p, payload_type) == TY_REF { payload_type = p.types[payload_type].element; }
            let variant = p.types[payload_type].declaration;
            let payload = cg_enum_payload(p, m, f, enum_id, base, variant, arm);
            cg_get(f, payload); cg_write_value(p, m, f, p.symbols[symbol].type_id, address, arm);
        }
        if item.third >= 0 { cg_truth(p, m, f, item.third); cg_begin(f, 0x04, 0x40); }
        cg_block_into(p, m, f, item.right, n.type_id, result); cg_branch(p, f, done, false);
        if item.third >= 0 { cg_end(f); } cg_end(f); arm = item.next;
    }
    cg_abort(p, m, f, node, "non-exhaustive match"); cg_end(f); cg_control_get(p, f, n.type_id, result);
}
recursive fn cg_may_region(p: Program&, node: i64) -> bool {
    if node < 0 { return false; } let n = p.nodes[node];
    if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE || n.kind == N_STRUCT || n.kind == N_ENUM || n.kind == N_ALIAS || n.kind == N_PATTERN { return false; }
    var id = n.type_id; while cg_type_kind(p, id) == TY_REF { id = p.types[id].element; }
    if cg_has_owner(p, id) { return true; }
    if cg_may_region(p, n.left) || cg_may_region(p, n.right) || cg_may_region(p, n.third) { return true; }
    var child = n.first; while child >= 0 { if cg_may_region(p, child) { return true; } child = p.nodes[child].next; } return false;
}
recursive fn cg_statement(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    if !m.regions_enabled || p.nodes[node].kind == N_VARIABLE || !cg_may_region(p, node) { cg_statement_body(p, m, f, node); return; }
    let live = f.region_live; let mark = cg_mark_regions(f); cg_statement_body(p, m, f, node); cg_restore_regions(f, mark); f.region_live = live;
}
recursive fn cg_statement_body(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n = p.nodes[node];
    if n.kind == N_VARIABLE { cg_declaration(p, m, f, node); return; }
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
        let declaration = p.types[id].declaration;
        if p.nodes[declaration].kind == N_VARIANT && p.nodes[declaration].first < 0 && p.types[id].pool >= 0 {
            let enum_type = p.types[id].pool;
            cg_print_name(p, m, f, enum_type); cg_text(m, f, ".");
            cg_text(m, f, token_text(p, p.nodes[declaration].token)); return;
        }
        cg_print_name(p, m, f, id); cg_text(m, f, " { ");
        var field = p.types[id].first; var first = true;
        while field >= 0 {
            if (p.nodes[field].flags & F_PAD) == 0 {
                if !first { cg_text(m, f, ", "); } first = false;
                cg_get(f, value); cg_field_place(p, m, f, id, node, field); cg_load(p, m, f, p.nodes[field].type_id, 0);
                let item = cg_save(f, cg_wasm_type(p, p.nodes[field].type_id)); cg_print(p, m, f, p.nodes[field].type_id, item, node, true);
            }
            field = p.nodes[field].next;
        }
        cg_text(m, f, " }"); return;
    }
    if kind == TY_ENUM {
        cg_get(f, value); if cg_enum_image(p, id) { wb_mem(f.code, 0x28, 2, 0); } var load = 0x2d; if p.types[id].length_storage == 2 { load = 0x2f; }
        wb_mem(f.code, load, 0, 0); let tag = cg_save(f, 0x7f); let done = cg_begin(f, 0x02, 0x40);
        var variant = p.types[id].first;
        while variant >= 0 {
            cg_get(f, tag); wb_i32(f.code, p.nodes[variant].integer); wb_byte(f.code, 0x46); cg_begin(f, 0x04, 0x40);
            let payload = p.nodes[variant].type_id;
            if p.nodes[variant].first < 0 {
                cg_print_name(p, m, f, id); cg_text(m, f, "."); cg_text(m, f, token_text(p, p.nodes[variant].token));
            } else {
                let pointer = cg_enum_payload(p, m, f, id, value, variant, node);
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
fn cg_pool_state(p: Program&, m: CgModule&, f: CgBody&, header: i64, node: i64) -> i64 {
    if m.pool_global < 0 { cg_fail(p, node, "wasm: reusable pool state was not planned"); wb_i32(f.code, 0); return cg_save(f, 0x7f); }
    cg_get(f, header); cg_resolve_pointer(m, f); cg_canonical_address(m, f, 24); let owner = cg_save(f, 0x7f);
    wb_op(f.code, 0x23, m.pool_global); let cursor = cg_save(f, 0x7f); wb_i32(f.code, 0); let result = cg_save(f, 0x7f);
    let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
    cg_get(f, cursor); wb_byte(f.code, 0x45); cg_branch(p, f, done, true);
    cg_get(f, cursor); wb_mem(f.code, 0x28, 2, 4); cg_get(f, owner); wb_byte(f.code, 0x46); cg_begin(f, 0x04, 0x40);
    cg_get(f, cursor); cg_set(f, result); cg_branch(p, f, done, false); cg_end(f);
    cg_get(f, cursor); wb_mem(f.code, 0x28, 2, 0); cg_set(f, cursor); cg_branch(p, f, again, false); cg_end(f); cg_end(f);
    cg_get(f, result); wb_byte(f.code, 0x45); cg_begin(f, 0x04, 0x40);
    let scratch = f.scratch; f.scratch = false; wb_i32(f.code, 20); cg_allocate(p, m, f, node); f.scratch = scratch; cg_set(f, result);
    cg_get(f, result); wb_i32(f.code, 0); wb_i32(f.code, 20); wb_fill(f.code);
    cg_get(f, result); wb_op(f.code, 0x23, m.pool_global); wb_mem(f.code, 0x36, 2, 0);
    cg_get(f, result); cg_get(f, owner); wb_mem(f.code, 0x36, 2, 4); cg_get(f, result); wb_op(f.code, 0x24, m.pool_global); cg_end(f);
    return result;
}
fn cg_pool_reserve(p: Program&, m: CgModule&, f: CgBody&, state: i64, count: i64, node: i64) {
    cg_get(f, state); wb_mem(f.code, 0x28, 2, 16); let old = cg_save(f, 0x7f);
    cg_get(f, count); cg_get(f, old); wb_byte(f.code, 0x4b); cg_begin(f, 0x04, 0x40);
    cg_get(f, old); wb_byte(f.code, 0xad); wb_i64(f.code, 2); wb_byte(f.code, 0x7e); let capacity = cg_save(f, 0x7e);
    cg_get(f, capacity); cg_get(f, count); wb_byte(f.code, 0xad); cg_get(f, capacity); cg_get(f, count); wb_byte(f.code, 0xad); wb_byte(f.code, 0x56); wb_byte(f.code, 0x1b); cg_set(f, capacity);
    cg_get(f, capacity); wb_i64(f.code, 1073741823); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "reusable pool freelist exceeds wasm32 range");
    let scratch = f.scratch; f.scratch = false; cg_get(f, capacity); wb_i64(f.code, 4); wb_byte(f.code, 0x7e); wb_byte(f.code, 0xa7); cg_allocate(p, m, f, node); f.scratch = scratch; let data = cg_save(f, 0x7f);
    cg_get(f, data); cg_get(f, state); wb_mem(f.code, 0x28, 2, 8); cg_get(f, state); wb_mem(f.code, 0x28, 2, 12); wb_i32(f.code, 4); wb_byte(f.code, 0x6c); wb_copy(f.code);
    cg_get(f, state); cg_get(f, data); wb_mem(f.code, 0x36, 2, 8); cg_get(f, state); cg_get(f, capacity); wb_byte(f.code, 0xa7); wb_mem(f.code, 0x36, 2, 16); cg_end(f);
}
fn cg_message_bytes(f: CgBody&, cursor: i64, text: CgText) {
    cg_get(f, cursor); cg_get(f, text.data); cg_get(f, text.length); wb_copy(f.code);
    cg_get(f, cursor); cg_get(f, text.length); wb_byte(f.code, 0x6a); cg_set(f, cursor);
}
fn cg_message_literal(m: CgModule&, f: CgBody&, cursor: i64, text: u8[:]) {
    wb_i32(f.code, cg_data(m, text)); let data = cg_save(f, 0x7f); wb_i32(f.code, text.len); let length = cg_save(f, 0x7f);
    cg_message_bytes(f, cursor, CgText { data: data, length: length });
}
fn cg_abort_index(p: Program&, m: CgModule&, f: CgBody&, index: i64, length: i64, node: i64) {
    let frame = cg_frame(f, 96, 1); cg_frame_address(f, frame); let buffer = cg_save(f, 0x7f); cg_get(f, buffer); let cursor = cg_save(f, 0x7f);
    cg_message_literal(m, f, cursor, "index "); cg_message_bytes(f, cursor, cg_integer_text(p, f, TYPE_I64, index));
    cg_message_literal(m, f, cursor, " out of bounds (length "); cg_get(f, length); wb_byte(f.code, 0xad); let count = cg_save(f, 0x7e);
    cg_message_bytes(f, cursor, cg_integer_text(p, f, TYPE_U64, count)); cg_message_literal(m, f, cursor, ")");
    cg_get(f, buffer); cg_get(f, cursor); cg_get(f, buffer); wb_byte(f.code, 0x6b); var line = 0;
    if node >= 0 && p.nodes[node].token >= 0 { line = p.tokens[p.nodes[node].token].line; }
    wb_i32(f.code, line); wb_op(f.code, 0x10, CG_ABORT); wb_byte(f.code, 0);
}
recursive fn cg_pool_builtin(p: Program&, m: CgModule&, f: CgBody&, node: i64, builtin: i64) {
    let n = p.nodes[node]; let receiver = n.first; let argument = p.nodes[receiver].next; var id = p.nodes[receiver].type_id;
    cg_expr(p, m, f, receiver); if cg_type_kind(p, id) == TY_REF { id = p.types[id].element; cg_load(p, m, f, id, 0); }
    let header = cg_save(f, 0x7f); let element = p.types[id].element;
    if !cg_owner(p, id) || p.types[id].array_kind != A_GROW || cg_has_owner(p, element) || cg_size(p, element) <= 0 {
        cg_fail(p, node, "wasm: reusable slot pools require fixed-size growable elements"); return;
    }
    if builtin == 32 {
        cg_to(p, m, f, argument, TYPE_U64); if cg_diverges(p, argument) { return; } let index = cg_save(f, 0x7e);
        cg_array_length(p, m, f, id, header); let length = cg_save(f, 0x7f);
        cg_get(f, index); cg_get(f, length); wb_byte(f.code, 0xad); wb_byte(f.code, 0x5a); cg_begin(f, 0x04, 0x40); cg_abort_index(p, m, f, index, length, node); cg_end(f);
        let state = cg_pool_state(p, m, f, header, node); cg_get(f, state); wb_mem(f.code, 0x28, 2, 12); let old = cg_save(f, 0x7f);
        cg_get(f, old); wb_i32(f.code, -1); wb_byte(f.code, 0x46); cg_trap_if(p, m, f, node, "reusable pool freelist exceeds wasm32 range");
        cg_get(f, old); wb_i32(f.code, 1); wb_byte(f.code, 0x6a); let count = cg_save(f, 0x7f); cg_pool_reserve(p, m, f, state, count, node);
        cg_get(f, state); wb_mem(f.code, 0x28, 2, 8); cg_get(f, old); wb_i32(f.code, 4); wb_byte(f.code, 0x6c); wb_byte(f.code, 0x6a); cg_get(f, index); wb_byte(f.code, 0xa7); wb_mem(f.code, 0x36, 2, 0);
        cg_get(f, state); cg_get(f, count); wb_mem(f.code, 0x36, 2, 12); return;
    }
    let direct = cg_fixed_relative(p, element); var value = -1;
    if !direct {
        cg_to(p, m, f, argument, element); if cg_diverges(p, argument) { return; } value = cg_save(f, cg_wasm_type(p, element));
        if cg_aggregate(p, element) { let copy = cg_temporary(p, f, element); cg_copy(p, m, f, element, copy, value, argument); value = copy; }
    }
    let state = cg_pool_state(p, m, f, header, node); cg_array_length(p, m, f, id, header); let old = cg_save(f, 0x7f);
    cg_get(f, state); wb_mem(f.code, 0x28, 2, 12); let free_count = cg_save(f, 0x7f); cg_get(f, old); let index = cg_save(f, 0x7f); wb_i32(f.code, 0); let fresh = cg_save(f, 0x7f);
    cg_get(f, free_count); cg_begin(f, 0x04, 0x40);
    cg_get(f, free_count); wb_i32(f.code, 1); wb_byte(f.code, 0x6b); cg_set(f, free_count); cg_get(f, state); cg_get(f, free_count); wb_mem(f.code, 0x36, 2, 12);
    cg_get(f, state); wb_mem(f.code, 0x28, 2, 8); cg_get(f, free_count); wb_i32(f.code, 4); wb_byte(f.code, 0x6c); wb_byte(f.code, 0x6a); wb_mem(f.code, 0x28, 2, 0); cg_set(f, index);
    wb_byte(f.code, 0x05); wb_i32(f.code, 1); cg_set(f, fresh); cg_end(f);
    cg_get(f, fresh); cg_begin(f, 0x04, 0x40);
    cg_get(f, old); wb_i32(f.code, -1); wb_byte(f.code, 0x46); cg_trap_if(p, m, f, node, "array length overflow");
    cg_get(f, old); wb_i32(f.code, 1); wb_byte(f.code, 0x6a); let count = cg_save(f, 0x7f); cg_array_reserve(p, m, f, id, header, count, node); cg_end(f);
    cg_array_element(p, m, f, id, header, index); let destination = cg_save(f, 0x7f);
    if direct { cg_fixed_to(p, m, f, argument, element, destination); if cg_diverges(p, argument) { return; } }
    else { cg_get(f, value); cg_write_value(p, m, f, element, destination, node); }
    cg_get(f, fresh); cg_begin(f, 0x04, 0x40); cg_get(f, old); wb_i32(f.code, 1); wb_byte(f.code, 0x6a); let count = cg_save(f, 0x7f); cg_array_set_length(p, m, f, id, header, count); cg_end(f);
    if builtin == 30 { cg_get(f, index); wb_byte(f.code, 0xad); cg_convert(p, m, f, TYPE_I64, n.type_id, node); }
    else {
        cg_get(f, destination); if cg_type_kind(p, element) == TY_REF { cg_load(p, m, f, element, 0); cg_convert(p, m, f, element, n.type_id, node); }
        else if cg_type_kind(p, n.type_id) != TY_REF { cg_load(p, m, f, element, 0); cg_convert(p, m, f, element, n.type_id, node); }
    }
}
fn cg_array_reserve(p: Program&, m: CgModule&, f: CgBody&, id: i64, base: i64, count: i64, node: i64) {
    if !cg_owner(p, id) {
        cg_get(f, count); wb_i32(f.code, p.types[id].count); wb_byte(f.code, 0x4b); cg_trap_if(p, m, f, node, "array capacity exceeded"); return;
    }
    cg_owner_read_capacity(p, m, f, base); let old_capacity = cg_save(f, 0x7f);
    cg_get(f, count); cg_get(f, old_capacity); wb_byte(f.code, 0x4b); cg_begin(f, 0x04, 0x40);
    if p.types[id].array_kind != A_GROW && p.types[id].array_kind != A_GROWSHRINK { cg_abort(p, m, f, node, "array capacity exceeded"); }
    cg_get(f, old_capacity); wb_byte(f.code, 0xad); wb_i64(f.code, 2); wb_byte(f.code, 0x7e); cg_get(f, count); wb_byte(f.code, 0xad);
    cg_get(f, old_capacity); wb_byte(f.code, 0xad); wb_i64(f.code, 2); wb_byte(f.code, 0x7e); cg_get(f, count); wb_byte(f.code, 0xad); wb_byte(f.code, 0x56); wb_byte(f.code, 0x1b);
    let capacity64 = cg_save(f, 0x7e);
    cg_get(f, capacity64); wb_i64(f.code, 4294967295); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array capacity overflow");
    cg_get(f, capacity64); wb_i64(f.code, cg_size(p, p.types[id].element)); wb_byte(f.code, 0x7e); let bytes64 = cg_save(f, 0x7e);
    cg_get(f, bytes64); wb_i64(f.code, 4294967295); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array byte size overflow");
    cg_get(f, bytes64); wb_byte(f.code, 0xa7); cg_allocate(p, m, f, node); let pointer = cg_save(f, 0x7f);
    cg_array_pointer(p, m, f, id, base); let original = cg_save(f, 0x7f);
    cg_get(f, pointer); cg_get(f, original); cg_array_length(p, m, f, id, base); wb_i32(f.code, cg_size(p, p.types[id].element)); wb_byte(f.code, 0x6c); wb_copy(f.code);
    cg_get(f, old_capacity); wb_i32(f.code, cg_size(p, p.types[id].element)); wb_byte(f.code, 0x6c); let old_bytes = cg_save(f, 0x7f); cg_forward_span(p, m, f, original, old_bytes, pointer);
    cg_get(f, base); cg_get(f, pointer); wb_mem(f.code, 0x36, 2, 0);
    cg_get(f, base); cg_get(f, pointer); cg_get(f, bytes64); wb_byte(f.code, 0xa7); wb_byte(f.code, 0x6a); wb_mem(f.code, 0x36, 2, 8);
    cg_get(f, base); cg_get(f, capacity64); wb_byte(f.code, 0xa7); wb_mem(f.code, 0x36, 2, 12); cg_end(f);
}
fn cg_region_array_bytes(p: Program&, m: CgModule&, f: CgBody&, id: i64, count: i64, node: i64) -> i64 {
    cg_get(f, count); wb_byte(f.code, 0xad); wb_i64(f.code, cg_size(p, p.types[id].element)); wb_byte(f.code, 0x7e); return cg_save(f, 0x7e);
}
fn cg_region_rewind(p: Program&, m: CgModule&, f: CgBody&, header: i64, bytes: i64, node: i64) -> i64 {
    let cursor = cg_region_cursor(f, header); cg_get(f, cursor); wb_byte(f.code, 0xad); cg_get(f, header); wb_mem(f.code, 0x28, 2, 0); wb_byte(f.code, 0xad); cg_get(f, bytes); wb_byte(f.code, 0x7c); wb_byte(f.code, 0x54);
    cg_trap_if(p, m, f, node, "data region exhausted"); cg_get(f, cursor); cg_get(f, bytes); wb_byte(f.code, 0xa7); wb_byte(f.code, 0x6b); let top = cg_save(f, 0x7f); cg_region_publish(f, header, top); return top;
}
recursive fn cg_append_relative_literal(p: Program&, m: CgModule&, f: CgBody&, node: i64, id: i64, header: i64, literal: i64) {
    let element = p.types[id].element; let added = cg_literal_count(p, m, f, literal);
    cg_array_length(p, m, f, id, header); let old = cg_save(f, 0x7f);
    cg_get(f, old); wb_byte(f.code, 0xad); cg_get(f, added); wb_byte(f.code, 0xad); wb_byte(f.code, 0x7c); let wide = cg_save(f, 0x7e);
    cg_get(f, wide); wb_i64(f.code, 4294967295); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array length overflow"); cg_get(f, wide); wb_byte(f.code, 0xa7); let count = cg_save(f, 0x7f);
    let region = m.regions_enabled && cg_region_value(p, id);
    let grow = p.types[id].array_kind == A_GROW || p.types[id].array_kind == A_GROWSHRINK;
    var destination = -1; var top = -1;
    if region && grow {
        let bytes = cg_region_array_bytes(p, m, f, id, added, node); top = cg_region_reserve(p, m, f, header, bytes, node); destination = cg_region_cursor(f, header);
    } else {
        if region { cg_get(f, count); cg_owner_read_capacity(p, m, f, header); wb_byte(f.code, 0x4b); cg_trap_if(p, m, f, node, "array capacity exceeded"); }
        else { cg_array_reserve(p, m, f, id, header, count, node); }
        cg_array_element(p, m, f, id, header, old); destination = cg_save(f, 0x7f);
    }
    cg_literal_elements(p, m, f, literal, element, destination, added); if cg_diverges(p, literal) { return; }
    if region && grow { cg_region_publish(f, header, top); }
    cg_array_set_length(p, m, f, id, header, count);
}
recursive fn cg_region_array_builtin(p: Program&, m: CgModule&, f: CgBody&, node: i64, builtin: i64, id: i64, header: i64, arg: i64) {
    let element = p.types[id].element; let grow = p.types[id].array_kind == A_GROW || p.types[id].array_kind == A_GROWSHRINK;
    if builtin == 29 {
        wb_i32(f.code, 0); let zero = cg_save(f, 0x7f); cg_owner_set_length(p, m, f, header, zero, node);
        if grow { cg_owner_read_base(p, m, f, header, node); let base = cg_save(f, 0x7f); cg_region_publish(f, header, base); } return;
    }
    if builtin == 24 {
        let direct = cg_fixed_relative(p, element); var value = -1;
        if !direct { cg_to(p, m, f, arg, element); value = cg_save(f, cg_wasm_type(p, element)); }
        cg_owner_read_length(p, m, f, header, node); let old = cg_save(f, 0x7f);
        cg_get(f, old); wb_i32(f.code, -1); wb_byte(f.code, 0x46); cg_trap_if(p, m, f, node, "data region exhausted");
        cg_get(f, old); wb_i32(f.code, 1); wb_byte(f.code, 0x6a); let count = cg_save(f, 0x7f); var destination = -1; var top = -1;
        if grow {
            wb_i64(f.code, cg_size(p, element)); let bytes = cg_save(f, 0x7e); top = cg_region_reserve(p, m, f, header, bytes, node); destination = cg_region_cursor(f, header);
        } else {
            cg_get(f, count); cg_owner_read_capacity(p, m, f, header); wb_byte(f.code, 0x4b); cg_trap_if(p, m, f, node, "array capacity exceeded");
            cg_array_element(p, m, f, id, header, old); destination = cg_save(f, 0x7f);
        }
        if direct { cg_fixed_to(p, m, f, arg, element, destination); if cg_diverges(p, arg) { return; } }
        else { cg_get(f, value); cg_write_value(p, m, f, element, destination, node); }
        if grow { cg_region_publish(f, header, top); }
        cg_owner_set_length(p, m, f, header, count, node);
        if p.nodes[node].type_id != TYPE_VOID {
            cg_get(f, destination); if cg_type_kind(p, element) == TY_REF { cg_load(p, m, f, element, 0); }
            else if cg_type_kind(p, p.nodes[node].type_id) != TY_REF { cg_load(p, m, f, element, 0); cg_convert(p, m, f, element, p.nodes[node].type_id, node); }
        } return;
    }
    if builtin == 26 {
        cg_owner_read_length(p, m, f, header, node); let old = cg_save(f, 0x7f); cg_get(f, old); wb_byte(f.code, 0x45); cg_trap_if(p, m, f, node, "pop from empty array");
        cg_get(f, old); wb_i32(f.code, 1); wb_byte(f.code, 0x6b); let count = cg_save(f, 0x7f); var source = -1;
        if grow { wb_i64(f.code, cg_size(p, element)); let bytes = cg_save(f, 0x7e); source = cg_region_rewind(p, m, f, header, bytes, node); }
        else { cg_array_element(p, m, f, id, header, count); source = cg_save(f, 0x7f); }
        cg_owner_set_length(p, m, f, header, count, node); cg_get(f, source); cg_load(p, m, f, element, 0);
        if cg_aggregate(p, element) { let value = cg_save(f, 0x7f); let snapshot = cg_temporary(p, f, element); cg_copy(p, m, f, element, snapshot, value, node); cg_get(f, snapshot); }
        cg_convert(p, m, f, element, p.nodes[node].type_id, node); return;
    }
    if builtin == 25 {
        let saved_raw = f.raw_node; if grow { f.raw_node = arg; } cg_expr(p, m, f, arg); f.raw_node = saved_raw;
        cg_pack_view(p, m, f, p.nodes[arg].type_id, node); let view = cg_save(f, 0x7e); cg_get(f, view); wb_i64(f.code, 32); wb_byte(f.code, 0x88); wb_byte(f.code, 0xa7); let added = cg_save(f, 0x7f);
        cg_owner_read_length(p, m, f, header, node); let old = cg_save(f, 0x7f); cg_get(f, old); wb_byte(f.code, 0xad); cg_get(f, added); wb_byte(f.code, 0xad); wb_byte(f.code, 0x7c); let wide = cg_save(f, 0x7e);
        cg_get(f, wide); wb_i64(f.code, 4294967295); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "data region exhausted"); cg_get(f, wide); wb_byte(f.code, 0xa7); let count = cg_save(f, 0x7f);
        var destination = -1; var top = -1;
        if grow { let bytes = cg_region_array_bytes(p, m, f, id, added, node); top = cg_region_reserve(p, m, f, header, bytes, node); destination = cg_region_cursor(f, header); }
        else { cg_get(f, count); cg_owner_read_capacity(p, m, f, header); wb_byte(f.code, 0x4b); cg_trap_if(p, m, f, node, "array capacity exceeded"); cg_array_element(p, m, f, id, header, old); destination = cg_save(f, 0x7f); }
        cg_get(f, destination); cg_get(f, view); wb_byte(f.code, 0xa7); cg_get(f, added); wb_i32(f.code, cg_size(p, element)); wb_byte(f.code, 0x6c); wb_copy(f.code);
        if grow { cg_region_publish(f, header, top); } cg_owner_set_length(p, m, f, header, count, node); return;
    }
    cg_to(p, m, f, arg, TYPE_U64); let wide = cg_save(f, 0x7e);
    if !cg_unsigned(p, p.nodes[arg].type_id) { cg_get(f, wide); wb_i64(f.code, 0); wb_byte(f.code, 0x53); if builtin == 27 { cg_trap_if(p, m, f, node, "negative pop count"); } else { cg_trap_if(p, m, f, node, "negative array count"); } }
    var fill = -1; let fill_node = p.nodes[arg].next; if fill_node >= 0 { cg_to(p, m, f, fill_node, element); fill = cg_save(f, cg_wasm_type(p, element)); }
    cg_owner_read_length(p, m, f, header, node); let old = cg_save(f, 0x7f);
    if builtin == 27 {
        cg_get(f, wide); cg_get(f, old); wb_byte(f.code, 0xad); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "pop count out of bounds");
        if grow { cg_get(f, wide); wb_i64(f.code, cg_size(p, element)); wb_byte(f.code, 0x7e); let bytes = cg_save(f, 0x7e); cg_region_rewind(p, m, f, header, bytes, node); }
        cg_get(f, old); cg_get(f, wide); wb_byte(f.code, 0xa7); wb_byte(f.code, 0x6b); let count = cg_save(f, 0x7f); cg_owner_set_length(p, m, f, header, count, node); return;
    }
    cg_get(f, wide); wb_i64(f.code, 4294967295); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array length overflow"); cg_get(f, wide); wb_byte(f.code, 0xa7); let count = cg_save(f, 0x7f);
    cg_get(f, count); cg_get(f, old); wb_byte(f.code, 0x4b); cg_begin(f, 0x04, 0x40);
    if fill < 0 { cg_abort(p, m, f, node, "array resize growth requires a fill value"); }
    else {
        cg_get(f, count); cg_get(f, old); wb_byte(f.code, 0x6b); let added = cg_save(f, 0x7f); var destination = -1; var top = -1;
        if grow { let bytes = cg_region_array_bytes(p, m, f, id, added, node); top = cg_region_reserve(p, m, f, header, bytes, node); destination = cg_region_cursor(f, header); }
        else { cg_get(f, count); cg_owner_read_capacity(p, m, f, header); wb_byte(f.code, 0x4b); cg_trap_if(p, m, f, node, "array capacity exceeded"); cg_array_element(p, m, f, id, header, old); destination = cg_save(f, 0x7f); }
        wb_i32(f.code, 0); let index = cg_save(f, 0x7f); let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
        cg_get(f, index); cg_get(f, added); wb_byte(f.code, 0x4f); cg_branch(p, f, done, true);
        cg_get(f, destination); cg_get(f, index); wb_i32(f.code, cg_size(p, element)); wb_byte(f.code, 0x6c); wb_byte(f.code, 0x6a); let location = cg_save(f, 0x7f); cg_get(f, fill); cg_write_value(p, m, f, element, location, node);
        cg_get(f, index); wb_i32(f.code, 1); wb_byte(f.code, 0x6a); cg_set(f, index); cg_branch(p, f, again, false); cg_end(f); cg_end(f); if grow { cg_region_publish(f, header, top); }
    }
    wb_byte(f.code, 0x05);
    if grow { cg_get(f, old); cg_get(f, count); wb_byte(f.code, 0x6b); let removed = cg_save(f, 0x7f); let bytes = cg_region_array_bytes(p, m, f, id, removed, node); cg_region_rewind(p, m, f, header, bytes, node); }
    cg_end(f); cg_owner_set_length(p, m, f, header, count, node);
}
recursive fn cg_array_builtin(p: Program&, m: CgModule&, f: CgBody&, node: i64, builtin: i64) {
    let n = p.nodes[node]; let receiver = n.first;
    if receiver < 0 { cg_fail(p, node, "wasm: array builtin has no receiver"); return; }
    var id = p.nodes[receiver].type_id; cg_expr(p, m, f, receiver);
    if cg_type_kind(p, id) == TY_REF { id = p.types[id].element; cg_load(p, m, f, id, 0); }
    let base = cg_save(f, 0x7f); let element = p.types[id].element; let arg = p.nodes[receiver].next;
    if builtin == 23 {
        cg_expr(p, m, f, arg); cg_resolve_pointer(m, f); cg_array_pointer(p, m, f, id, base); wb_byte(f.code, 0x6b); wb_byte(f.code, 0xad);
        wb_i64(f.code, cg_size(p, element)); wb_byte(f.code, 0x80); cg_convert(p, m, f, TYPE_I64, n.type_id, node); return;
    }
    if !cg_owner(p, id) && p.types[id].array_kind != A_LIMITED { cg_fail(p, node, "wasm: array mutation requires bounded or growable storage"); return; }
    if builtin == 25 && arg >= 0 && (p.nodes[arg].kind == N_ARRAY || p.nodes[arg].kind == N_FILL) &&
       !cg_has_owner(p, element) && cg_has_relative(p, element) {
        cg_append_relative_literal(p, m, f, node, id, base, arg); return;
    }
    if p.types[element].storage == 1 { cg_varint_array_builtin(p, m, f, node, builtin, id, base, arg); return; }
    if m.regions_enabled && cg_region_value(p, id) { cg_region_array_builtin(p, m, f, node, builtin, id, base, arg); return; }
    if builtin == 29 {
        wb_i32(f.code, 0); let zero = cg_save(f, 0x7f); cg_array_set_length(p, m, f, id, base, zero); return;
    }
    if builtin == 24 {
        let direct = cg_fixed_relative(p, element); var value = -1;
        if !direct { cg_to(p, m, f, arg, element); value = cg_save(f, cg_wasm_type(p, element)); }
        cg_array_length(p, m, f, id, base); let old = cg_save(f, 0x7f);
        cg_get(f, old); wb_i32(f.code, -1); wb_byte(f.code, 0x46); cg_trap_if(p, m, f, node, "array length overflow");
        cg_get(f, old); wb_i32(f.code, 1); wb_byte(f.code, 0x6a); let count = cg_save(f, 0x7f); cg_array_reserve(p, m, f, id, base, count, node);
        cg_array_element(p, m, f, id, base, old); let destination = cg_save(f, 0x7f);
        if direct { cg_fixed_to(p, m, f, arg, element, destination); if cg_diverges(p, arg) { return; } }
        else { cg_get(f, value); cg_write_value(p, m, f, element, destination, node); }
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
        let saved_raw = f.raw_node; f.raw_node = arg; cg_expr(p, m, f, arg); f.raw_node = saved_raw;
        cg_pack_view(p, m, f, p.nodes[arg].type_id, node); let view = cg_save(f, 0x7e);
        cg_get(f, view); wb_i64(f.code, 32); wb_byte(f.code, 0x88); wb_byte(f.code, 0xa7); let added = cg_save(f, 0x7f);
        cg_array_length(p, m, f, id, base); let old = cg_save(f, 0x7f);
        cg_get(f, old); cg_get(f, added); wb_byte(f.code, 0x6a); let count = cg_save(f, 0x7f);
        cg_get(f, count); cg_get(f, old); wb_byte(f.code, 0x49); cg_trap_if(p, m, f, node, "array length overflow"); cg_array_reserve(p, m, f, id, base, count, node);
        cg_array_element(p, m, f, id, base, old); cg_get(f, view); wb_byte(f.code, 0xa7); cg_get(f, added); wb_i32(f.code, cg_size(p, element)); wb_byte(f.code, 0x6c); wb_copy(f.code);
        cg_array_set_length(p, m, f, id, base, count); return;
    }
    cg_to(p, m, f, arg, TYPE_U64); let requested = cg_save(f, 0x7e);
    if !cg_unsigned(p, p.nodes[arg].type_id) { cg_get(f, requested); wb_i64(f.code, 0); wb_byte(f.code, 0x53); if builtin == 27 { cg_trap_if(p, m, f, node, "negative pop count"); } else { cg_trap_if(p, m, f, node, "negative array count"); } }
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
fn cg_raw_append_type(p: Program&, id: i64) -> bool {
    return cg_type_kind(p, id) == TY_ARRAY && p.types[id].array_kind == A_GROW &&
           p.types[id].element == TYPE_U8 && p.types[id].length_storage < 0 && p.types[id].size == 24;
}
fn cg_format_bytes(p: Program&, m: CgModule&, f: CgBody&, id: i64, output: i64, data: i64, length: i64, node: i64) {
    if m.raw_append >= 0 && !f.scratch && cg_raw_append_type(p, id) {
        cg_get(f, output); cg_get(f, data); cg_get(f, length);
        var line = 0; if node >= 0 && p.nodes[node].token >= 0 { line = p.tokens[p.nodes[node].token].line; }
        wb_i32(f.code, line); wb_op(f.code, 0x10, m.raw_append); return;
    }
    cg_format_bytes_inline(p, m, f, id, output, data, length, node);
}
fn cg_format_bytes_inline(p: Program&, m: CgModule&, f: CgBody&, id: i64, output: i64, data: i64, length: i64, node: i64) {
    cg_array_length(p, m, f, id, output); let old = cg_save(f, 0x7f);
    cg_get(f, old); wb_byte(f.code, 0xad); cg_get(f, length); wb_byte(f.code, 0xad); wb_byte(f.code, 0x7c); let wide = cg_save(f, 0x7e);
    cg_get(f, wide); wb_i64(f.code, 4294967295); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "formatted output length overflow"); cg_get(f, wide); wb_byte(f.code, 0xa7); let count = cg_save(f, 0x7f);
    if p.types[id].array_kind == A_LIMITED {
        cg_get(f, count); if cg_owner(p, id) { cg_owner_read_capacity(p, m, f, output); } else { wb_i32(f.code, p.types[id].count); }
        wb_byte(f.code, 0x4b); cg_trap_if(p, m, f, node, "limited array capacity exceeded");
    }
    let region = m.regions_enabled && cg_region_value(p, id); let grow = p.types[id].array_kind == A_GROW || p.types[id].array_kind == A_GROWSHRINK;
    var destination = -1; var top = -1;
    if region && grow {
        cg_get(f, length); wb_byte(f.code, 0xad); let bytes = cg_save(f, 0x7e); top = cg_region_reserve(p, m, f, output, bytes, node); destination = cg_region_cursor(f, output);
    } else {
        if !region { cg_array_reserve(p, m, f, id, output, count, node); }
        cg_array_element(p, m, f, id, output, old); destination = cg_save(f, 0x7f);
    }
    cg_get(f, destination); cg_get(f, data); cg_resolve_pointer(m, f); cg_get(f, length); wb_copy(f.code);
    if region && grow { cg_region_publish(f, output, top); } cg_array_set_length(p, m, f, id, output, count);
}
fn cg_format_text(p: Program&, m: CgModule&, f: CgBody&, id: i64, output: i64, text: u8[:], node: i64) {
    wb_i32(f.code, cg_data(m, text)); let data = cg_save(f, 0x7f); wb_i32(f.code, text.len); let length = cg_save(f, 0x7f);
    cg_format_bytes(p, m, f, id, output, data, length, node);
}
fn cg_format_scalar(p: Program&, m: CgModule&, f: CgBody&, output_type: i64, output: i64, id: i64, value: i64, node: i64) {
    let kind = cg_type_kind(p, id);
    if kind == TY_FLOAT {
        let offset = cg_frame(f, 32, 1); cg_frame_address(f, offset); let buffer = cg_save(f, 0x7f);
        var host = m.format_f64; if p.types[id].count == 32 { host = m.format_f32; }
        if host < 0 { cg_fail(p, node, "wasm: floating-point formatter demand was not planned"); return; }
        cg_get(f, buffer); cg_get(f, value); wb_op(f.code, 0x10, host); let length = cg_save(f, 0x7f);
        cg_format_bytes(p, m, f, output_type, output, buffer, length, node); return;
    }
    if kind == TY_BOOL {
        cg_get(f, value); cg_begin(f, 0x04, 0x40); cg_format_text(p, m, f, output_type, output, "true", node);
        wb_byte(f.code, 0x05); cg_format_text(p, m, f, output_type, output, "false", node); cg_end(f); return;
    }
    if kind == TY_ARRAY || kind == TY_SLICE {
        if p.types[id].element != TYPE_U8 { cg_fail(p, node, "wasm: compound formatting requires the semantic rendering helper"); return; }
        cg_get(f, value); cg_pack_view(p, m, f, id, node); let view = cg_save(f, 0x7e);
        cg_get(f, view); wb_byte(f.code, 0xa7); let data = cg_save(f, 0x7f); cg_get(f, view); wb_i64(f.code, 32); wb_byte(f.code, 0x88); wb_byte(f.code, 0xa7); let length = cg_save(f, 0x7f);
        cg_format_bytes(p, m, f, output_type, output, data, length, node); return;
    }
    if kind != TY_INT { cg_fail(p, node, "wasm: this raw formatting scalar is unsupported"); return; }
    let text = cg_integer_text(p, f, id, value); cg_format_bytes(p, m, f, output_type, output, text.data, text.length, node);
}
fn cg_integer_text(p: Program&, f: CgBody&, id: i64, value: i64) -> CgText {
    let frame = cg_frame(f, 32, 1); cg_frame_address(f, frame); let buffer = cg_save(f, 0x7f);
    cg_get(f, value); if cg_wasm_type(p, id) == 0x7f { if cg_unsigned(p, id) { wb_byte(f.code, 0xad); } else { wb_byte(f.code, 0xac); } }
    let magnitude = cg_save(f, 0x7e); wb_i32(f.code, 0); let negative = cg_save(f, 0x7f);
    if !cg_unsigned(p, id) {
        cg_get(f, magnitude); wb_i64(f.code, 0); wb_byte(f.code, 0x53); cg_set(f, negative);
        cg_get(f, negative); cg_begin(f, 0x04, 0x40); wb_i64(f.code, 0); cg_get(f, magnitude); wb_byte(f.code, 0x7d); cg_set(f, magnitude); cg_end(f);
    }
    cg_get(f, buffer); wb_i32(f.code, 32); wb_byte(f.code, 0x6a); let end = cg_save(f, 0x7f); cg_get(f, end); let cursor = cg_save(f, 0x7f);
    let again = cg_begin(f, 0x03, 0x40);
    cg_get(f, cursor); wb_i32(f.code, 1); wb_byte(f.code, 0x6b); cg_set(f, cursor);
    cg_get(f, cursor); cg_get(f, magnitude); wb_i64(f.code, 10); wb_byte(f.code, 0x82); wb_byte(f.code, 0xa7); wb_i32(f.code, 48); wb_byte(f.code, 0x6a); wb_mem(f.code, 0x3a, 0, 0);
    cg_get(f, magnitude); wb_i64(f.code, 10); wb_byte(f.code, 0x80); cg_set(f, magnitude); cg_get(f, magnitude); wb_byte(f.code, 0x50); wb_byte(f.code, 0x45); cg_branch(p, f, again, true); cg_end(f);
    cg_get(f, negative); cg_begin(f, 0x04, 0x40); cg_get(f, cursor); wb_i32(f.code, 1); wb_byte(f.code, 0x6b); cg_set(f, cursor); cg_get(f, cursor); wb_i32(f.code, 45); wb_mem(f.code, 0x3a, 0, 0); cg_end(f);
    cg_get(f, end); cg_get(f, cursor); wb_byte(f.code, 0x6b); let length = cg_save(f, 0x7f); return CgText { data: cursor, length: length };
}
recursive fn cg_format_builtin(p: Program&, m: CgModule&, f: CgBody&, node: i64, builtin: i64) {
    let n = p.nodes[node]; var child = n.first; var output = -1; var output_type = n.type_id;
    if builtin == 2 {
        output_type = p.nodes[child].type_id; cg_expr(p, m, f, child);
        if cg_type_kind(p, output_type) == TY_REF { output_type = p.types[output_type].element; cg_load(p, m, f, output_type, 0); }
        output = cg_save(f, 0x7f); child = p.nodes[child].next;
    }
    if builtin == 1 {
        wb_i32(f.code, 0); let zero = cg_save(f, 0x7f);
        if m.regions_enabled {
            let receiving = cg_temporary_destination(p, m, f, output_type, node); output = f.construction_destinations[receiving].header;
            cg_region_array_prefix(p, m, f, output_type, output, zero, zero, node);
        } else {
            output = cg_temporary(p, f, output_type); cg_get(f, output); wb_i32(f.code, 0); wb_i32(f.code, 24); wb_fill(f.code);
            cg_owner_image(p, m, f, output_type, output, zero, zero, node);
        }
    }
    while child >= 0 {
        var id = p.nodes[child].type_id; cg_expr(p, m, f, child); if cg_diverges(p, child) { return; }
        if cg_type_kind(p, id) == TY_REF { id = p.types[id].element; cg_load(p, m, f, id, 0); }
        let value = cg_save(f, cg_wasm_type(p, id)); cg_format_scalar(p, m, f, output_type, output, id, value, node);
        child = p.nodes[child].next;
    }
    if builtin == 1 { cg_get(f, output); }
}
recursive fn cg_bytes_builtin(p: Program&, m: CgModule&, f: CgBody&, node: i64, builtin: i64) {
    let n = p.nodes[node]; let argument = n.first; var id = p.nodes[argument].type_id;
    while cg_type_kind(p, id) == TY_REF { id = p.types[id].element; }
    if cg_type_kind(p, id) != TY_ARRAY && cg_type_kind(p, id) != TY_SLICE { cg_fail(p, node, "wasm: byte images require an array or slice"); return; }
    let element = p.types[id].element;
    if cg_has_owner(p, element) { cg_fail(p, node, "wasm: byte images of variable aggregate elements require physical image packing"); return; }
    cg_expr(p, m, f, argument); if cg_diverges(p, argument) { return; } cg_pack_view(p, m, f, p.nodes[argument].type_id, node);
    let view = cg_save(f, 0x7e); cg_get(f, view); wb_byte(f.code, 0xa7); let data = cg_save(f, 0x7f);
    cg_get(f, view); wb_i64(f.code, 32); wb_byte(f.code, 0x88); let count = cg_save(f, 0x7e); var length = -1;
    if cg_encoded_scalar(p, element) {
        let end = cg_walk_elements(p, m, f, data, count, node); cg_get(f, end); cg_get(f, data); wb_byte(f.code, 0x6b); length = cg_save(f, 0x7f);
    } else {
        cg_get(f, count); wb_i64(f.code, cg_size(p, element)); wb_byte(f.code, 0x7e); let bytes = cg_save(f, 0x7e);
        cg_get(f, bytes); wb_i64(f.code, 4294967295); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "byte image exceeds wasm32 range"); cg_get(f, bytes); wb_byte(f.code, 0xa7); length = cg_save(f, 0x7f);
    }
    if builtin == 17 {
        cg_get(f, data); wb_byte(f.code, 0xad); cg_get(f, length); wb_byte(f.code, 0xad); wb_i64(f.code, 32); wb_byte(f.code, 0x86); wb_byte(f.code, 0x84); return;
    }
    var output = -1; var output_type = n.type_id; let receiver = p.nodes[argument].next;
    if receiver >= 0 {
        output_type = p.nodes[receiver].type_id; cg_expr(p, m, f, receiver); if cg_diverges(p, receiver) { return; }
        if cg_type_kind(p, output_type) == TY_REF { output_type = p.types[output_type].element; cg_load(p, m, f, output_type, 0); }
        output = cg_save(f, 0x7f);
    } else {
        wb_i32(f.code, 0); let zero = cg_save(f, 0x7f);
        if m.regions_enabled {
            let receiving = cg_temporary_destination(p, m, f, output_type, node); output = f.construction_destinations[receiving].header;
            cg_region_array_prefix(p, m, f, output_type, output, zero, zero, node);
        } else {
            output = cg_temporary(p, f, output_type); cg_get(f, output); wb_i32(f.code, 0); wb_i32(f.code, 24); wb_fill(f.code);
            cg_owner_image(p, m, f, output_type, output, zero, zero, node);
        }
    }
    let frame = cg_frame(f, 10, 1); cg_frame_address(f, frame); let prefix = cg_save(f, 0x7f);
    cg_get(f, length); wb_byte(f.code, 0xad); let wide = cg_save(f, 0x7e); let end = cg_write_uleb(p, f, prefix, wide);
    cg_get(f, end); cg_get(f, prefix); wb_byte(f.code, 0x6b); let prefix_length = cg_save(f, 0x7f);
    cg_format_bytes(p, m, f, output_type, output, prefix, prefix_length, node); cg_format_bytes(p, m, f, output_type, output, data, length, node);
    if receiver < 0 { cg_get(f, output); }
}
recursive fn cg_builtin(p: Program&, m: CgModule&, f: CgBody&, node: i64, builtin: i64) {
    let n = p.nodes[node]; let arg = n.first;
    if builtin == 1 || builtin == 2 { cg_format_builtin(p, m, f, node, builtin); return; }
    if builtin == 0 {
        let mark = f.work.len; wb_op(f.code, 0x23, 0); let scratch_mark = cg_save(f, 0x7f);
        var child = arg;
        while child >= 0 {
            var id = p.nodes[child].type_id; cg_expr(p, m, f, child); if cg_diverges(p, child) { f.work.resize(mark); return; }
            if cg_type_kind(p, id) == TY_SLICE { cg_pack_view(p, m, f, id, child); }
            if cg_type_kind(p, id) == TY_REF { id = p.types[id].element; cg_load(p, m, f, id, 0); }
            var value = cg_save(f, cg_wasm_type(p, id));
            if cg_aggregate(p, id) {
                let snapshot = cg_temporary(p, f, id); f.scratch = true; cg_copy(p, m, f, id, snapshot, value, child); f.scratch = false; value = snapshot;
            } else if cg_type_kind(p, id) == TY_SLICE {
                cg_get(f, value); wb_i64(f.code, 32); wb_byte(f.code, 0x88); wb_byte(f.code, 0xa7); let length = cg_save(f, 0x7f);
                var bytes = -1;
                if p.types[p.types[id].element].storage == 1 {
                    cg_get(f, value); wb_byte(f.code, 0xa7); let base = cg_save(f, 0x7f); cg_get(f, length); wb_byte(f.code, 0xad); let count = cg_save(f, 0x7e); let end = cg_walk_elements(p, m, f, base, count, node);
                    cg_get(f, end); cg_get(f, base); wb_byte(f.code, 0x6b); bytes = cg_save(f, 0x7f);
                } else { cg_get(f, length); wb_i32(f.code, cg_size(p, p.types[id].element)); wb_byte(f.code, 0x6c); bytes = cg_save(f, 0x7f); }
                cg_get(f, bytes); f.scratch = true; cg_allocate(p, m, f, node); f.scratch = false; let copy = cg_save(f, 0x7f);
                cg_get(f, copy); cg_get(f, value); wb_byte(f.code, 0xa7); cg_get(f, bytes); wb_copy(f.code);
                cg_get(f, copy); wb_byte(f.code, 0xad); cg_get(f, length); wb_byte(f.code, 0xad); wb_i64(f.code, 32); wb_byte(f.code, 0x86); wb_byte(f.code, 0x84); value = cg_save(f, 0x7e);
            }
            f.work.push(id); f.work.push(value); child = p.nodes[child].next;
        }
        let end = f.work.len; var at = mark;
        while at < end { let id = f.work[at]; let value = f.work[at + 1]; cg_print(p, m, f, id, value, node, false); at += 2; }
        f.work.resize(mark); wb_op(f.code, 0x10, CG_NEWLINE);
        cg_get(f, scratch_mark); wb_op(f.code, 0x24, 0); return;
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
            let destination = cg_temporary(p, f, n.type_id);
            if cg_byte_record(p, n.type_id) { cg_construct_byte_record(p, m, f, n.type_id, destination, -1); }
            else { cg_get(f, destination); wb_i32(f.code, 0); wb_i32(f.code, cg_size(p, n.type_id)); wb_fill(f.code); }
            cg_get(f, destination);
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
    if builtin >= 30 && builtin <= 32 { cg_pool_builtin(p, m, f, node, builtin); return; }
    if builtin == 16 || builtin == 17 { cg_bytes_builtin(p, m, f, node, builtin); return; }
    if builtin == 18 { cg_fail(p, node, "wasm: from_bytes image verification is unsupported by the direct Wasm backend"); return; }
    cg_fail(p, node, "wasm: builtin is unsupported by the direct Wasm execution environment");
}
recursive fn cg_slice(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n = p.nodes[node]; var id = p.nodes[n.left].type_id;
    if cg_type_kind(p, id) == TY_REF { id = p.types[id].element; }
    cg_expr(p, m, f, n.left); cg_pack_view(p, m, f, p.nodes[n.left].type_id, node); let view = cg_save(f, 0x7e);
    if n.right >= 0 {
        if (n.flags & F_FROM_END) != 0 { cg_get(f, view); wb_i64(f.code, 32); wb_byte(f.code, 0x88); }
        cg_to(p, m, f, n.right, TYPE_U64); if cg_diverges(p, n.right) { return; } if (n.flags & F_FROM_END) != 0 { wb_byte(f.code, 0x7d); }
    } else { wb_i64(f.code, 0); }
    let start = cg_save(f, 0x7e);
    if n.third >= 0 {
        if (n.flags & F_TO_END) != 0 { cg_get(f, view); wb_i64(f.code, 32); wb_byte(f.code, 0x88); }
        cg_to(p, m, f, n.third, TYPE_U64); if cg_diverges(p, n.third) { return; } if (n.flags & F_TO_END) != 0 { wb_byte(f.code, 0x7d); }
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
    let result = p.nodes[node].type_id; var requested = result; let right = p.nodes[node].right;
    if right >= 0 && p.nodes[right].type_id >= 0 { requested = p.nodes[right].type_id; }
    p.nodes[node].type_id = requested; cg_cast_body(p, m, f, node); p.nodes[node].type_id = result;
    if requested != result && !cg_diverges(p, p.nodes[node].left) { cg_convert(p, m, f, requested, result, node); }
}
recursive fn cg_cast_body(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
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

fn cg_diverges(p: Program&, node: i64) -> bool {
    if node < 0 { return false; } let n = p.nodes[node];
    if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE || n.kind == N_INTEGER || n.kind == N_FLOAT || n.kind == N_BOOL || n.kind == N_NULL || n.kind == N_STRING || n.kind == N_NAME { return false; }
    return (n.flags & F_DIVERGES) != 0;
}
fn cg_terminal(p: Program&, node: i64) -> bool {
    if node < 0 { return false; } let n = p.nodes[node];
    if cg_diverges(p, node) || n.kind == N_RETURN || n.kind == N_BREAK || n.kind == N_CONTINUE { return true; }
    if n.kind == N_EXPR_STMT { return cg_diverges(p, n.left); }
    if n.kind == N_VARIABLE || n.kind == N_ASSIGN { return cg_diverges(p, n.right); } return false;
}
recursive fn cg_bottom_prefix(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n = p.nodes[node];
    if n.kind == N_BINARY {
        cg_discard(p, m, f, n.left); if cg_diverges(p, n.left) { return; }
        cg_discard(p, m, f, n.right); return;
    }
    if n.kind == N_RECORD {
        var binding = n.first;
        while binding >= 0 { let value = p.nodes[binding].right; cg_discard(p, m, f, value); if cg_diverges(p, value) { return; } binding = p.nodes[binding].next; } return;
    }
    if n.third >= 0 { cg_discard(p, m, f, n.third); if cg_diverges(p, n.third) { return; } }
    var child = n.first;
    while child >= 0 { cg_discard(p, m, f, child); if cg_diverges(p, child) { return; } child = p.nodes[child].next; }
    if n.right >= 0 { cg_discard(p, m, f, n.right); }
}
fn cg_projection_receiver(p: Program&, m: CgModule&, f: CgBody&, node: i64, requested: i64) -> bool {
    if requested < 0 { return false; } let n = p.nodes[node];
    let natural = cg_result_at(p, p.nodes[n.left].type_id, n.integer); let target = f.construction_destinations[requested].type_id;
    return natural == target && (cg_fixed_relative(p, natural) || m.regions_enabled && cg_region_value(p, natural));
}
recursive fn cg_project_result(p: Program&, m: CgModule&, f: CgBody&, node: i64, requested: i64) {
    let n = p.nodes[node]; let tuple = p.nodes[n.left].type_id; let count = cg_result_count(p, tuple);
    if cg_type_kind(p, tuple) != TY_TUPLE || n.integer < 0 || n.integer >= count { cg_fail(p, node, "wasm: result projection has no natural channel"); return; }
    let mark = f.receiving.len;
    if cg_projection_receiver(p, m, f, node, requested) { f.receiving.push(CgReceiving { slot: -2 - n.left, ordinal: n.integer, destination: requested }); }
    let values = f.work.len;
    for ordinal in 0..count { f.work.push(cg_local(f, cg_wasm_type(p, cg_result_at(p, tuple, ordinal)))); }
    // The producer keeps its complete result type. Receive every channel before
    // converting the selected value; other channels retain effects and storage.
    cg_expr(p, m, f, n.left); f.receiving.resize(mark); if cg_diverges(p, n.left) { f.work.resize(values); return; }
    var ordinal = count; while ordinal > 0 { ordinal -= 1; cg_set(f, f.work[values + ordinal]); }
    cg_get(f, f.work[values + n.integer]); cg_convert(p, m, f, cg_result_at(p, tuple, n.integer), n.type_id, node); f.work.resize(values);
}
recursive fn cg_expr(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    if node < 0 { return; }
    let original = p.nodes[node].type_id; let diverges = cg_diverges(p, node); let n = p.nodes[node];
    if diverges && original < 0 && (n.kind == N_ARRAY || n.kind == N_FILL || n.kind == N_RECORD || n.kind == N_BINARY) {
        cg_bottom_prefix(p, m, f, node); wb_byte(f.code, 0x00); return;
    }
    if diverges && original < 0 { p.nodes[node].type_id = TYPE_VOID; }
    if m.regions_enabled && cg_region_value(p, n.type_id) && f.active_node != node &&
       (n.kind == N_BLOCK || n.kind == N_IF || n.kind == N_GUARD || n.kind == N_LOOP || n.kind == N_WHILE || n.kind == N_MATCH) {
        let receiving = cg_temporary_destination(p, m, f, n.type_id, node);
        if cg_owner(p, n.type_id) && cg_raw_value(f, node) { f.construction_destinations[receiving].elements = true; }
        cg_construct_region(p, m, f, node, receiving); cg_get(f, f.construction_destinations[receiving].header);
    } else { cg_expr_body(p, m, f, node); }
    p.nodes[node].type_id = original;
    if diverges { wb_byte(f.code, 0x00); }
}
recursive fn cg_expr_body(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    if node < 0 { return; } let n = p.nodes[node]; let w = cg_wasm_type(p, n.type_id);
    if n.kind == N_RESULT {
        var requested = cg_receiving(f, -2 - node, 0); if requested < 0 && f.active_node == node { requested = f.active_destination; }
        cg_project_result(p, m, f, node, requested); return;
    }
    if (n.kind == N_MEMBER || n.kind == N_INDEX || n.kind == N_SLICE || n.kind == N_CAST || n.kind == N_UNARY) && cg_diverges(p, n.left) { cg_expr(p, m, f, n.left); return; }
    if n.kind == N_INTEGER && cg_type_kind(p, n.type_id) == TY_ENUM {
        if m.regions_enabled && cg_enum_image(p, n.type_id) { let receiving = cg_temporary_destination(p, m, f, n.type_id, node); cg_construct_region(p, m, f, node, receiving); cg_get(f, f.construction_destinations[receiving].header); return; }
        let destination = cg_temporary(p, f, n.type_id);
        if cg_enum_image(p, n.type_id) {
            var variant = p.types[n.type_id].first; while variant >= 0 && p.nodes[variant].integer != n.integer { variant = p.nodes[variant].next; }
            if variant < 0 { cg_fail(p, node, "wasm: enum constant has no matching variant"); return; }
            let payload_id = p.nodes[variant].type_id; let payload = cg_temporary(p, f, payload_id);
            cg_get(f, payload); wb_i32(f.code, 0); wb_i32(f.code, cg_size(p, payload_id)); wb_fill(f.code); cg_enum_variant_image(p, m, f, n.type_id, destination, variant, payload, node);
        } else {
            cg_get(f, destination); wb_i32(f.code, 0); wb_i32(f.code, cg_size(p, n.type_id)); wb_fill(f.code);
            cg_get(f, destination); wb_i32(f.code, n.integer); if p.types[n.type_id].length_storage == 2 { wb_mem(f.code, 0x3b, 0, 0); } else { wb_mem(f.code, 0x3a, 0, 0); }
        }
        cg_get(f, destination); return;
    }
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
        let stored = p.symbols[n.symbol].type_id;
        if stored >= 0 && p.types[stored].kind == TY_INT && p.types[stored].storage == 1 { cg_load_fixed(p, f.code, TYPE_I64, 0); return; }
        if !cg_load(p, m, f, stored, 0) { cg_fail(p, node, "wasm: unresolved name value type"); }
        return;
    }
    if n.kind == N_FUNCTION_VALUE { cg_closure(p, m, f, n.symbol, node); return; }
    if n.kind == N_ARRAY || n.kind == N_FILL { cg_array_literal(p, m, f, node); return; }
    if n.kind == N_RECORD { cg_record_literal(p, m, f, node); return; }
    if n.kind == N_UNARY {
        if n.integer == T_BITAND {
            if cg_type_kind(p, p.nodes[n.left].type_id) == TY_REF { cg_expr(p, m, f, n.left); }
            else { cg_address(p, m, f, n.left); } return;
        }
        if n.integer == T_MUL || n.integer == T_XOR {
            cg_expr(p, m, f, n.left); var storage = n.type_id; if n.aux >= 0 { storage = n.aux; }
            cg_load(p, m, f, storage, 0); cg_convert(p, m, f, storage, n.type_id, node); return;
        }
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
        cg_address(p, m, f, node); if cg_diverges(p, node) { return; } var object_type = p.nodes[n.left].type_id;
        if cg_type_kind(p, object_type) == TY_REF { object_type = p.types[object_type].element; }
        let element = p.types[object_type].element;
        if cg_type_kind(p, n.type_id) == TY_REF && cg_type_kind(p, element) != TY_REF { return; }
        cg_load(p, m, f, element, 0); cg_convert(p, m, f, element, n.type_id, node); return;
    }
    if n.kind == N_SLICE { cg_slice(p, m, f, node); return; }
    if n.kind == N_CAST { cg_cast(p, m, f, node); return; }
    if n.kind == N_CALL { cg_call(p, m, f, node); return; }
    if n.kind == N_BLOCK {
        // Inline bodies keep their natural result channels until every return
        // operand has finished, exactly as an ordinary call does.
        let count = cg_result_count(p, n.type_id); let plans = f.work.len; let result_mark = f.receiving.len; var adapting = false;
        for ordinal in 0..count {
            let id = cg_result_at(p, n.type_id, ordinal); var requested = cg_receiving(f, -2 - node, ordinal); var producer = -1; var adaptation = 0;
            if requested < 0 && count == 1 && f.active_node == node { requested = f.active_destination; }
            if m.regions_enabled && requested >= 0 {
                if cg_variant_result(p, id, f.construction_destinations[requested].type_id) >= 0 && (count == 1 || cg_region_value(p, id)) {
                    producer = cg_prepare_variant_result(p, m, f, id, requested, node); adaptation = 3;
                } else if count == 1 && !cg_callback_expression(p, node) && cg_owner(p, id) && p.types[id].array_kind == A_VAR &&
                          cg_owner(p, f.construction_destinations[requested].type_id) && p.types[f.construction_destinations[requested].type_id].array_kind == A_VAR &&
                          p.types[id].length_storage != p.types[f.construction_destinations[requested].type_id].length_storage {
                    producer = cg_share_destination(p, m, f, requested, id, true, false, f.construction_destinations[requested].escape, node); adaptation = 1;
                } else if cg_region_value(p, id) && f.construction_destinations[requested].type_id != id &&
                          (!cg_inline_array_receiver(p, id, f.construction_destinations[requested]) || n.origin >= 0 && p.nodes[n.origin].kind == N_FUNCTION_VALUE) {
                    producer = cg_temporary_destination(p, m, f, id, node); adaptation = 2;
                }
                if adaptation != 0 { adapting = true; f.receiving.push(CgReceiving { slot: -2 - node, ordinal: ordinal, destination: producer }); }
            }
            f.work.push(producer); f.work.push(requested); f.work.push(adaptation);
        }
        let result = cg_control_slots(p, f, n.type_id, node); cg_bind_inline_results(p, f, node, result);
        if (n.flags & F_EARLY) != 0 {
            // Argument materializations belong to the caller expression. A
            // returned view must survive later arguments of that expression.
            if n.origin >= 0 {
                var argument = n.first;
                while cg_inline_argument(p, argument) {
                    cg_declaration(p, m, f, argument); if cg_decl_diverges(p, argument) { f.receiving.resize(result_mark); f.work.resize(plans); return; }
                    argument = p.nodes[argument].next;
                }
            }
            wb_op(f.code, 0x23, 0); let scratch = cg_save(f, 0x7f); var regions = -1; if m.regions_enabled { regions = cg_mark_regions(f); }
            let done = cg_begin(f, 0x02, 0x40); f.exits.push(CgExit { label: done, node: node, result: result, type_id: n.type_id, scratch: scratch, regions: regions, publication: cg_mark_publications(m, f) });
            cg_block_into(p, m, f, node, n.type_id, result); f.exits.pop(); cg_end(f);
        } else { cg_block_into(p, m, f, node, n.type_id, result); }
        f.receiving.resize(result_mark); cg_control_get(p, f, n.type_id, result);
        if adapting {
            let values = f.work.len;
            for ordinal in 0..count { f.work.push(cg_local(f, cg_wasm_type(p, cg_result_at(p, n.type_id, ordinal)))); }
            var ordinal = count; while ordinal > 0 { ordinal -= 1; cg_set(f, f.work[values + ordinal]); }
            for ordinal in 0..count {
                let producer = f.work[plans + ordinal * 3]; let receiving = f.work[plans + ordinal * 3 + 1]; let adaptation = f.work[plans + ordinal * 3 + 2];
                if adaptation == 3 { cg_publish_variant_result(p, m, f, cg_result_at(p, n.type_id, ordinal), f.work[values + ordinal], producer, receiving, node); }
                else if adaptation == 1 { cg_finish_value_array(p, m, f, f.construction_destinations[producer].header, receiving, node); }
                else if adaptation != 0 { cg_construct_captured(p, m, f, cg_result_at(p, n.type_id, ordinal), f.work[values + ordinal], receiving, node); }
            }
            for ordinal in 0..count {
                if f.work[plans + ordinal * 3 + 2] != 0 { cg_get(f, f.construction_destinations[f.work[plans + ordinal * 3 + 1]].header); }
                else { cg_get(f, f.work[values + ordinal]); }
            }
        }
        f.work.resize(plans); return;
    }
    if n.kind == N_IF || n.kind == N_GUARD {
        let result = cg_control_slots(p, f, n.type_id, node); cg_truth_scope(p, m, f, n.left); if cg_diverges(p, n.left) { return; } cg_begin(f, 0x04, 0x40);
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
    if m.regions_enabled { f.region_mark = cg_local(f, 0x7f); f.publication_mark = cg_local(f, 0x7f); }
    if !m.scalar && function >= 0 {
        let index = cg_function(m, p.nodes[function].symbol);
        if index >= 0 && m.functions[index].arena_local {
            f.heap_mark = cg_local(f, 0x7f); if m.resolver >= 0 { f.forward_mark = cg_local(f, 0x7f); }
        }
    }
    var parameter_count = 0; param = -1; if function >= 0 { param = p.nodes[function].first; }
    while param >= 0 { parameter_count++; param = p.nodes[param].next; }
    var capture_param = parameter_count;
    for capture in m.captures {
        if capture.function == function { f.slots[capture.symbol] = capture_param; capture_param++; }
    }
    for symbol, i in p.symbols {
        if symbol.owner == function && (function >= 0 || cg_storage_binding(p, i)) && (symbol.flags & (S_FUNCTION | S_TYPE | S_GLOBAL | S_BUILTIN)) == 0 {
            let size = cg_slot_size(p, symbol.type_id);
            if size <= 0 {
                if cg_dead_binding(p, symbol.node) { continue; }
                cg_fail(p, symbol.node, "wasm: variable has no physical layout"); continue;
            }
            f.slots[i] = cg_local(f, 0x7f); f.offsets[i] = cg_frame(f, size, p.types[symbol.type_id].align);
        }
    }
    for id in results { f.results.push(cg_local(f, cg_wasm_type(p, id))); }
    var destination = destination_start;
    for id, ordinal in results {
        if cg_aggregate(p, id) {
            f.destinations.push(destination);
            if m.regions_enabled && cg_region_value(p, id) {
                let header = destination; let physical = cg_region_header(p, f, id, header); let entry = cg_region_cursor(f, physical);
                let receiving = cg_destination(f, id, header, CG_CALLER, f.elements && ordinal == 0, true, false, entry, -1);
                f.receiving.push(CgReceiving { slot: f.results[0], ordinal: ordinal, destination: receiving });
            } else if cg_fixed_relative(p, id) {
                let receiving = cg_destination(f, id, destination, CG_CALLER, false, false, false, -1, -1);
                f.receiving.push(CgReceiving { slot: f.results[0], ordinal: ordinal, destination: receiving });
            }
            destination += 1;
        } else { f.destinations.push(-1); }
    }
    var mailbox_size = 16;
    for id in results { mailbox_size = cg_align(mailbox_size, 8) + cg_size(p, id); }
    if function >= 0 && cg_nonlocal_target(p, function) &&
       (m.regions_enabled && cg_region_owned_result(p, cg_result_type(p, function)) || cg_fixed_relative_results(p, cg_result_type(p, function))) {
        f.effect_metadata = cg_align(mailbox_size, 8); mailbox_size = f.effect_metadata + results.len * 12;
    }
    if !m.scalar { f.effect = cg_frame(f, mailbox_size, 8); }
}
fn cg_emit_prelude(p: Program&, m: CgModule&, f: CgBody&) {
    if m.scalar { if !f.frame_free { wb_op(f.code, 0x23, 0); cg_set(f, f.frame); } return; }
    wb_op(f.code, 0x23, 0); cg_set(f, f.frame);
    cg_get(f, f.frame); wb_i32(f.code, cg_align(f.frame_bytes, 8)); wb_byte(f.code, 0x6a); let top = cg_save(f, 0x7f);
    cg_get(f, top); cg_get(f, f.frame); wb_byte(f.code, 0x49); cg_get(f, top);
    if m.regions_enabled { wb_op(f.code, 0x23, 10); } else { wb_i32(f.code, m.stack_limit); } wb_byte(f.code, 0x4b); wb_byte(f.code, 0x72);
    cg_trap_if(p, m, f, f.function, "activation stack exhausted"); cg_ensure_memory(p, m, f, top, f.function);
    cg_get(f, top); wb_op(f.code, 0x24, 0);
    if f.region_mark >= 0 { wb_op(f.code, 0x23, 3); cg_set(f, f.region_mark); }
    if f.publication_mark >= 0 { wb_op(f.code, 0x23, 11); cg_set(f, f.publication_mark); }
    if f.heap_mark >= 0 { wb_op(f.code, 0x23, 1); cg_set(f, f.heap_mark); }
    if f.forward_mark >= 0 { wb_op(f.code, 0x23, 5); cg_set(f, f.forward_mark); }
    for offset, symbol in f.offsets {
        if offset >= 0 { cg_frame_address(f, offset); cg_set(f, f.slots[symbol]); }
    }
    cg_frame_address(f, f.effect); wb_op(f.code, 0x23, 4); wb_mem(f.code, 0x36, 2, 0);
    cg_frame_address(f, f.effect); wb_i32(f.code, f.function + 1); wb_mem(f.code, 0x36, 2, 4);
    cg_frame_address(f, f.effect); wb_op(f.code, 0x24, 4);
    if f.effect_metadata >= 0 {
        let result_type = cg_result_type(p, f.function);
        for ordinal in 0..cg_result_count(p, result_type) {
            let id = cg_result_at(p, result_type, ordinal);
            if cg_fixed_relative(p, id) {
                cg_frame_address(f, f.effect + f.effect_metadata + ordinal * 12); cg_get(f, f.destinations[ordinal]); wb_mem(f.code, 0x36, 2, 0); continue;
            }
            if !cg_region_value(p, id) { continue; }
            let original = f.destinations[ordinal]; let original_tail = cg_region_header(p, f, id, original); let entry = cg_region_cursor(f, original_tail); let metadata = f.effect_metadata + ordinal * 12;
            cg_frame_address(f, f.effect + metadata); cg_get(f, original); wb_mem(f.code, 0x36, 2, 0);
            cg_frame_address(f, f.effect + metadata + 8); cg_get(f, entry); wb_mem(f.code, 0x36, 2, 0);
            if cg_enum_image(p, id) { cg_set_enum_anchor(f, original, entry); }
            else if cg_image_owner(p, id) { cg_set_record_anchor(p, m, f, id, original, entry, f.function); }
            else if p.types[id].array_kind == A_LIMITED || p.types[id].array_kind == A_VAR { cg_set_array_anchor(p, f, original, entry, id); }
        }
    }
}
fn cg_parameter_copies(p: Program&, m: CgModule&, f: CgBody&) {
    if f.function < 0 { return; } var param = p.nodes[f.function].first; var index = 0;
    while param >= 0 {
        let symbol = p.nodes[param].symbol;
        if symbol < 0 { cg_fail(p, param, "wasm: parameter has no storage symbol"); return; }
        let id = p.nodes[param].type_id;
        if m.regions_enabled && cg_region_value(p, id) { cg_get(f, f.slots[symbol]); cg_get(f, index); wb_i32(f.code, cg_size(p, id)); wb_copy(f.code); }
        else { cg_get(f, index); cg_write_value(p, m, f, id, f.slots[symbol], param); }
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
        offset = cg_align(offset, 8);
        if f.effect_metadata >= 0 && cg_fixed_relative(p, id) {
            cg_frame_address(f, f.effect + f.effect_metadata + i * 12); wb_mem(f.code, 0x28, 2, 0); cg_set(f, f.results[i]);
        } else if f.effect_metadata >= 0 && cg_region_value(p, id) {
            cg_frame_address(f, f.effect + f.effect_metadata + i * 12); wb_mem(f.code, 0x28, 2, 0); let original = cg_save(f, 0x7f);
            cg_frame_address(f, f.effect + f.effect_metadata + i * 12 + 4); wb_mem(f.code, 0x28, 2, 0); let start = cg_save(f, 0x7f);
            cg_frame_address(f, f.effect + f.effect_metadata + i * 12 + 8); wb_mem(f.code, 0x28, 2, 0); let entry = cg_save(f, 0x7f);
            cg_frame_address(f, f.effect + offset); let stage = cg_save(f, 0x7f);
            if cg_enum_image(p, id) { cg_set_enum_anchor(f, original, entry); cg_finish_enum(p, m, f, id, original, start, true, f.function); }
            else if cg_image_owner(p, id) {
                cg_set_record_anchor(p, m, f, id, original, entry, f.function); cg_finish_record_image(p, m, f, id, original, start, true, f.function);
            } else if cg_frame_owner(p, id) { cg_finish_frame_record(p, m, f, id, original, stage, start, entry, true, f.function); }
            else {
                if p.types[id].array_kind != A_LIMITED && p.types[id].array_kind != A_VAR { cg_get(f, original); cg_get(f, entry); wb_mem(f.code, 0x36, 2, 0); }
                cg_finish_region_array(p, m, f, original, stage, start, id, false, true, f.function);
            }
            cg_get(f, original); cg_set(f, f.results[i]);
        } else {
            cg_frame_address(f, f.effect + offset);
            if p.types[id].kind == TY_INT && p.types[id].storage == 1 { cg_load_fixed(p, f.code, TYPE_I64, 0); }
            else { cg_load(p, m, f, id, 0); }
            cg_set(f, f.results[i]);
        }
        offset += cg_size(p, id);
    }
    wb_i32(f.code, 0); wb_op(f.code, 0x24, 2); cg_end(f);
    cg_frame_address(f, f.effect); wb_mem(f.code, 0x28, 2, 0); wb_op(f.code, 0x24, 4);
    wb_op(f.code, 0x23, 2); wb_byte(f.code, 0x45); cg_begin(f, 0x04, 0x40);
    for id, i in results {
        if f.destinations[i] >= 0 {
            if m.regions_enabled && cg_region_value(p, id) { cg_get(f, f.destinations[i]); cg_set(f, f.results[i]); continue; }
            let saved_raw = f.raw_node; if f.elements && i == 0 { f.raw_node = f.function; }
            cg_copy(p, m, f, id, f.destinations[i], f.results[i], f.function); f.raw_node = saved_raw; cg_get(f, f.destinations[i]); cg_set(f, f.results[i]); }
    }
    cg_end(f);
    cg_restore_regions(f, f.region_mark); cg_restore_publications(f, f.publication_mark);
    if f.heap_mark >= 0 { cg_get(f, f.heap_mark); wb_op(f.code, 0x24, 1); }
    if f.forward_mark >= 0 { cg_get(f, f.forward_mark); wb_op(f.code, 0x24, 5); }
    cg_get(f, f.frame); wb_op(f.code, 0x24, 0);
    for result in f.results { cg_get(f, result); } wb_byte(f.code, 0x0b);
}
fn cg_emit_function(p: Program&, m: CgModule&, function: i64, function_index: i64, elements: bool, out: u8[>..]&) {
    var code: u8[>..] = []; var locals: i64[>..] = []; var slots: i64[>..] = []; var offsets: i64[>..] = [];
    var labels: i64[>..] = []; var exits: CgExit[>..] = []; var results: i64[>..] = []; var destinations: i64[>..] = []; var work: i64[>..] = []; var raw_slots: i64[>..] = []; var sequences: CgSequence[>..] = []; var constructions: CgConstruction[>..] = []; var construction_destinations: CgDestination[>..] = []; var receiving: CgReceiving[>..] = [];
    var f = CgBody { code: code, locals: locals, slots: slots, offsets: offsets, labels: labels, exits: exits, results: results, destinations: destinations, work: work, raw_slots: raw_slots, sequences: sequences, constructions: constructions, construction_destinations: construction_destinations, receiving: receiving, function: function, function_index: function_index, elements: elements };
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
            else { cg_region_call(m, f, index, p.entry); wb_op(f.code, 0x10, m.functions[index].index); cg_drop_type(p, f, cg_result_type(p, p.entry)); }
        }
    }
    cg_end(f); cg_emit_epilogue(p, m, f);
    // Frame size includes literals and call snapshots discovered recursively.
    // Emit the reservation only after that size has become final.
    var body: u8[>..] = []; body.append(code); code.clear(); cg_emit_prelude(p, m, f); code.append(body);
    if m.scalar { wb_compact_body(out, locals, code, f.params); }
    else { wb_body(out, locals, code); }
    m.region_functions[function_index].own = f.region_peak;
}
fn cg_emit_raw_append(p: Program&, m: CgModule&, out: u8[>..]&) {
    var code: u8[>..] = []; var locals: i64[>..] = []; var slots: i64[>..] = []; var offsets: i64[>..] = [];
    var labels: i64[>..] = []; var exits: CgExit[>..] = []; var results: i64[>..] = []; var destinations: i64[>..] = []; var work: i64[>..] = []; var raw_slots: i64[>..] = []; var sequences: CgSequence[>..] = []; var constructions: CgConstruction[>..] = []; var construction_destinations: CgDestination[>..] = []; var receiving: CgReceiving[>..] = [];
    var f = CgBody { code: code, locals: locals, slots: slots, offsets: offsets, labels: labels, exits: exits, results: results, destinations: destinations, work: work, raw_slots: raw_slots, sequences: sequences, constructions: constructions, construction_destinations: construction_destinations, receiving: receiving, params: 4, diagnostic_line: 3 };
    cg_format_bytes_inline(p, m, f, m.raw_append_type, 0, 1, 2, -1); wb_byte(code, 0x0b); wb_body(out, locals, code);
}
fn cg_allocate(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    if !f.scratch { wb_op(f.code, 0x10, m.allocator); return; }
    let bytes = cg_save(f, 0x7f); wb_op(f.code, 0x23, 0); let base = cg_save(f, 0x7f);
    cg_get(f, base); wb_byte(f.code, 0xad); cg_get(f, bytes); wb_byte(f.code, 0xad); wb_byte(f.code, 0x7c); wb_i64(f.code, 7); wb_byte(f.code, 0x7c); wb_i64(f.code, -8); wb_byte(f.code, 0x83); let top64 = cg_save(f, 0x7e);
    cg_get(f, top64); if m.regions_enabled { wb_op(f.code, 0x23, 10); wb_byte(f.code, 0xad); } else { wb_i64(f.code, m.stack_limit); } wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "activation/scratch arena exhausted");
    cg_get(f, top64); wb_byte(f.code, 0xa7); let top = cg_save(f, 0x7f); cg_ensure_memory(p, m, f, top, node);
    cg_get(f, top); wb_op(f.code, 0x24, 0); cg_get(f, base);
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
    if n.kind == N_PATTERN || (n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE) && node != function { return; }
    if (n.kind == N_CALL || n.kind == N_FUNCTION_VALUE || n.kind == N_NAME) && n.symbol >= 0 && (p.symbols[n.symbol].flags & S_FUNCTION) != 0 {
        let target = p.symbols[n.symbol].node; let count = m.captures.len;
        for i in 0..count {
            let capture = m.captures[i];
            if capture.function == target && p.symbols[capture.symbol].owner != function && !cg_capture(m, function, capture.symbol) {
                m.captures.push(CgCapture { function: function, symbol: capture.symbol });
            }
        }
    }
    if n.kind == N_CALL && (n.flags & F_DISPATCH) != 0 {
        var arm = n.third;
        while arm >= 0 {
            let target = p.symbols[p.nodes[arm].symbol].node; let count = m.captures.len;
            for i in 0..count {
                let capture = m.captures[i];
                if capture.function == target && p.symbols[capture.symbol].owner != function && !cg_capture(m, function, capture.symbol) {
                    m.captures.push(CgCapture { function: function, symbol: capture.symbol });
                }
            }
            arm = p.nodes[arm].next;
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
    else if host == CG_FORMAT_F32 || host == CG_FORMAT_F64 {
        args.push(0x7f); if host == CG_FORMAT_F32 { args.push(0x7d); } else { args.push(0x7c); } results.push(0x7f);
    }
    return cg_signature(m, args, results);
}
fn cg_host_name(host: i64) -> u8[:] {
    if host == CG_WRITE { return "write"; } if host == CG_PRINT_I64 { return "print_i64"; }
    if host == CG_PRINT_U64 { return "print_u64"; } if host == CG_PRINT_F64 { return "print_f64"; }
    if host == CG_PRINT_F32 { return "print_f32"; } if host == CG_PRINT_BOOL { return "print_bool"; }
    if host == CG_FORMAT_F32 { return "format_f32"; } if host == CG_FORMAT_F64 { return "format_f64"; }
    if host == CG_NEWLINE { return "newline"; } if host == CG_ABORT { return "abort"; } return "exit";
}
fn cg_external_name(p: Program&, function: i64) -> u8[:] {
    let token = p.nodes[function].integer;
    if token >= 0 && token < p.tokens.len && p.tokens[token].kind == T_STRLIT {
        let t = p.tokens[token]; return p.text[t.text_start..t.text_start + t.text_len];
    }
    return token_text(p, p.nodes[function].token);
}
recursive fn cg_private_place(p: Program&, function: i64, node: i64) -> bool {
    if node < 0 { return false; } let n = p.nodes[node];
    if cg_type_kind(p, n.type_id) == TY_REF { return false; }
    if n.kind == N_NAME {
        if n.symbol < 0 || n.symbol >= p.symbols.len { return false; }
        let symbol = p.symbols[n.symbol];
        return symbol.owner == function && (symbol.flags & (S_GLOBAL | S_CAPTURE)) == 0 && cg_type_kind(p, symbol.type_id) != TY_REF;
    }
    if n.kind == N_MEMBER || n.kind == N_INDEX { return cg_private_place(p, function, n.left); }
    return false;
}
fn cg_scalar_results(p: Program&, function: i64) -> bool {
    let result = cg_result_type(p, function); let count = cg_result_count(p, result);
    for ordinal in 0..count {
        let kind = cg_type_kind(p, cg_result_at(p, result, ordinal));
        if kind != TY_INT && kind != TY_FLOAT && kind != TY_BOOL { return false; }
    }
    return true;
}
recursive fn cg_private_arena(p: Program&, m: CgModule&, function: i64, node: i64) -> bool {
    if node < 0 { return true; } let n = p.nodes[node];
    if n.kind == N_PATTERN || (n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE) && node != function { return true; }
    if m.pool_global >= 0 && n.kind == N_VARIABLE && (n.flags & F_REUSABLE) != 0 { return false; }
    if n.kind == N_RETURN && n.symbol >= 0 && p.symbols[n.symbol].node != function { return false; }
    if n.kind == N_ASSIGN && !cg_private_place(p, function, n.left) { return false; }
    if n.kind == N_CALL {
        if (n.flags & F_DISPATCH) != 0 {
            var arm = n.third;
            while arm >= 0 { let target = cg_function(m, p.nodes[arm].symbol); if target < 0 || !m.functions[target].arena_local { return false; } arm = p.nodes[arm].next; }
        } else {
            if n.symbol < 0 || n.symbol >= p.symbols.len { return false; }
            let symbol = p.symbols[n.symbol];
            if (symbol.flags & S_BUILTIN) != 0 {
                if symbol.index == 2 && !cg_private_place(p, function, n.first) { return false; }
                if symbol.index == 16 && n.first >= 0 && p.nodes[n.first].next >= 0 &&
                   !cg_private_place(p, function, p.nodes[n.first].next) { return false; }
                if symbol.index >= 24 && symbol.index <= 29 && !cg_private_place(p, function, n.first) { return false; }
                if symbol.index >= 7 && symbol.index <= 13 || symbol.index >= 30 { return false; }
            } else {
                let target = cg_function(m, n.symbol); if target < 0 || !m.functions[target].arena_local { return false; }
            }
        }
    }
    if !cg_private_arena(p, m, function, n.left) || !cg_private_arena(p, m, function, n.right) || !cg_private_arena(p, m, function, n.third) { return false; }
    var child = n.first;
    while child >= 0 { if !cg_private_arena(p, m, function, child) { return false; } child = p.nodes[child].next; }
    return true;
}
fn cg_plan_private_arenas(p: Program&, m: CgModule&) {
    for item, index in m.functions { m.functions[index].arena_local = cg_scalar_results(p, item.node) && (p.nodes[item.node].flags & F_NONLOCAL) == 0; }
    loop {
        var changed = false;
        for item, index in m.functions {
            if item.arena_local && !cg_private_arena(p, m, item.node, p.nodes[item.node].right) { m.functions[index].arena_local = false; changed = true; }
        }
        if !changed { break; }
    }
}
recursive fn cg_region_owned_result(p: Program&, id: i64) -> bool {
    if cg_type_kind(p, id) != TY_TUPLE { return cg_has_owner(p, id); }
    var component = p.types[id].first;
    while component >= 0 { if cg_region_owned_result(p, p.nodes[component].type_id) { return true; } component = p.nodes[component].next; }
    return false;
}
recursive fn cg_region_type_supported(p: Program&, id: i64) -> bool {
    var value = id; while cg_type_kind(p, value) == TY_REF { value = p.types[value].element; }
    if cg_type_kind(p, value) == TY_TUPLE {
        var component = p.types[value].first; while component >= 0 { if !cg_region_type_supported(p, p.nodes[component].type_id) { return false; } component = p.nodes[component].next; } return true;
    }
    if !cg_has_owner(p, value) { return true; }
    if cg_enum_image(p, value) {
        var variant = p.types[value].first;
        while variant >= 0 { let payload = p.nodes[variant].type_id; if cg_has_owner(p, payload) && (!cg_image_owner(p, payload) || !cg_region_type_supported(p, payload)) { return false; } variant = p.nodes[variant].next; } return true;
    }
    if cg_image_owner(p, value) {
        var current = value;
        while cg_record_image(p, current) {
            var field = p.types[current].first;
            while field >= 0 && field != p.types[current].tail { if (p.nodes[field].flags & F_PAD) == 0 && cg_has_owner(p, p.nodes[field].type_id) { return false; } field = p.nodes[field].next; }
            current = p.nodes[p.types[current].tail].type_id;
        }
        if cg_byte_record(p, current) {
            var field = p.types[current].first;
            while field >= 0 { if (p.nodes[field].flags & F_PAD) == 0 && cg_has_owner(p, p.nodes[field].type_id) { return false; } field = p.nodes[field].next; } return true;
        }
        return (cg_owner(p, current) || cg_enum_image(p, current)) && cg_region_type_supported(p, current);
    }
    if cg_frame_owner(p, value) {
        var current = value;
        while cg_type_kind(p, current) == TY_STRUCT {
            var field = p.types[current].first;
            while field >= 0 && field != p.types[current].tail { if (p.nodes[field].flags & F_PAD) == 0 && cg_has_owner(p, p.nodes[field].type_id) { return false; } field = p.nodes[field].next; }
            current = p.nodes[p.types[current].tail].type_id;
        }
        return cg_region_type_supported(p, current);
    }
    if !cg_owner(p, value) { return false; }
    let element = p.types[value].element;
    return element >= 0 && !cg_has_owner(p, element) && (p.types[element].storage == 1 || cg_size(p, element) > 0);
}
recursive fn cg_effect_result_supported(p: Program&, id: i64) -> bool {
    if cg_type_kind(p, id) == TY_TUPLE {
        var component = p.types[id].first; while component >= 0 { if !cg_effect_result_supported(p, p.nodes[component].type_id) { return false; } component = p.nodes[component].next; } return true;
    }
    if !cg_has_owner(p, id) { return true; }
    if cg_enum_image(p, id) { return cg_enum_effect_supported(p, id); }
    var array = id; if cg_frame_owner(p, id) { array = cg_frame_tail_type(p, id); }
    if cg_image_owner(p, id) { if !cg_record_effect_supported(p, id) { return false; } array = cg_image_tail_type(p, id); }
    return cg_owner(p, array) && (p.types[array].array_kind != A_VAR || p.types[array].length_storage != 0) && p.types[p.types[array].element].storage != 1;
}
recursive fn cg_region_body_supported(p: Program&, function: i64, node: i64) -> bool {
    if node < 0 { return true; } let n = p.nodes[node];
    if n.kind == N_PATTERN || n.kind == N_STRUCT || n.kind == N_ENUM || n.kind == N_ALIAS || n.kind == N_IMPORT || (n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE) && node != function { return true; }
    if !cg_region_type_supported(p, n.type_id) { return false; }
    if n.kind == N_RETURN && n.symbol >= 0 {
        let target = p.symbols[n.symbol].node;
        if target != function && !cg_effect_result_supported(p, cg_result_type(p, target)) { return false; }

    }
    if !cg_region_body_supported(p, function, n.left) || !cg_region_body_supported(p, function, n.right) || !cg_region_body_supported(p, function, n.third) { return false; }
    var child = n.first; while child >= 0 { if !cg_region_body_supported(p, function, child) { return false; } child = p.nodes[child].next; } return true;
}
fn cg_array_regions_supported(p: Program&, m: CgModule&) -> bool {
    var owns = false;
    for symbol in p.symbols {
        if symbol.owner >= 0 && (p.nodes[symbol.owner].flags & F_REACHABLE) == 0 { continue; }
        if symbol.node >= 0 && (p.nodes[symbol.node].kind == N_FIELD || p.nodes[symbol.node].kind == N_VARIANT) { continue; }
        if symbol.type_id >= 0 && (symbol.flags & (S_FUNCTION | S_TYPE | S_BUILTIN)) == 0 {
            if !cg_region_type_supported(p, symbol.type_id) { return false; }
            if cg_has_owner(p, symbol.type_id) { owns = true; }
        }
    }
    for item in m.functions {
        let result = cg_result_type(p, item.node);
        if !cg_region_type_supported(p, result) || !cg_region_body_supported(p, item.node, p.nodes[item.node].right) { return false; }
    }
    return owns;
}
recursive fn cg_uses_pool(p: Program&, node: i64) -> bool {
    if node < 0 { return false; } let n = p.nodes[node];
    if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE || n.kind == N_STRUCT || n.kind == N_ENUM || n.kind == N_ALIAS || n.kind == N_IMPORT || n.kind == N_PATTERN { return false; }
    if n.kind == N_CALL && n.symbol >= 0 && (p.symbols[n.symbol].flags & S_BUILTIN) != 0 {
        let builtin = p.symbols[n.symbol].index; if builtin >= 30 && builtin <= 32 { return true; }
    }
    if cg_uses_pool(p, n.left) || cg_uses_pool(p, n.right) || cg_uses_pool(p, n.third) { return true; }
    var child = n.first; while child >= 0 { if cg_uses_pool(p, child) { return true; } child = p.nodes[child].next; } return false;
}
recursive fn cg_float_format_demand(p: Program&, node: i64) -> i64 {
    if node < 0 { return 0; } let n = p.nodes[node];
    if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE || n.kind == N_STRUCT || n.kind == N_ENUM || n.kind == N_ALIAS || n.kind == N_IMPORT || n.kind == N_PATTERN { return 0; }
    var demand = 0;
    if n.kind == N_CALL && n.symbol >= 0 && (p.symbols[n.symbol].flags & S_BUILTIN) != 0 {
        let builtin = p.symbols[n.symbol].index;
        if builtin == 1 || builtin == 2 {
            var arg = n.first; if builtin == 2 && arg >= 0 { arg = p.nodes[arg].next; }
            while arg >= 0 {
                var id = p.nodes[arg].type_id;
                while cg_type_kind(p, id) == TY_REF { id = p.types[id].element; }
                if cg_type_kind(p, id) == TY_FLOAT { if p.types[id].count == 32 { demand |= 1; } else { demand |= 2; } }
                arg = p.nodes[arg].next;
            }
        }
    }
    demand |= cg_float_format_demand(p, n.left) | cg_float_format_demand(p, n.right) | cg_float_format_demand(p, n.third);
    var child = n.first; while child >= 0 { demand |= cg_float_format_demand(p, child); child = p.nodes[child].next; } return demand;
}
recursive fn cg_raw_append_demand(p: Program&, m: CgModule&, node: i64) -> i64 {
    if node < 0 { return 0; } let n = p.nodes[node];
    if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE || n.kind == N_STRUCT || n.kind == N_ENUM || n.kind == N_ALIAS || n.kind == N_IMPORT || n.kind == N_PATTERN { return 0; }
    var count = 0;
    if n.kind == N_CALL && n.symbol >= 0 && (p.symbols[n.symbol].flags & S_BUILTIN) != 0 {
        let builtin = p.symbols[n.symbol].index; var output = -1; var arg = n.first;
        if builtin == 1 { output = n.type_id; }
        else if builtin == 2 && arg >= 0 { output = p.nodes[arg].type_id; arg = p.nodes[arg].next; }
        while cg_type_kind(p, output) == TY_REF { output = p.types[output].element; }
        if arg >= 0 && cg_raw_append_type(p, output) { count = 1; if m.raw_append_type < 0 { m.raw_append_type = output; } }
    }
    count += cg_raw_append_demand(p, m, n.left) + cg_raw_append_demand(p, m, n.right) + cg_raw_append_demand(p, m, n.third);
    var child = n.first; while child >= 0 { count += cg_raw_append_demand(p, m, child); child = p.nodes[child].next; } return count;
}
fn cg_collect(p: Program&, m: CgModule&) {
    cg_scan_effect_targets(p);
    for host in 0..9 { m.imports.push(CgImport { signature: cg_host_signature(m, host), host: host }); }
    for symbol, i in p.symbols {
        m.globals.push(-1); m.global_regions.push(-1);
        if (symbol.flags & S_GLOBAL) != 0 && symbol.type_id >= 0 {
            m.next_data = cg_align(m.next_data, p.types[symbol.type_id].align); m.globals[i] = m.next_data; m.next_data += cg_slot_size(p, symbol.type_id);
            if cg_has_owner(p, symbol.type_id) { m.global_regions[i] = m.global_region_count; m.global_region_count += 1; }
        }
    }
    for n, node in p.nodes {
        if n.kind != N_FUNCTION && n.kind != N_FUNCTION_VALUE || n.symbol < 0 || (n.flags & F_GENERIC) != 0 ||
           (n.flags & (F_CHECKED | F_REACHABLE)) != (F_CHECKED | F_REACHABLE) { continue; }
        if (n.flags & F_THREAD) != 0 { cg_fail(p, node, "wasm: threads are unsupported by the direct host ABI"); }
        if (n.flags & F_EXTERN) != 0 {
            if n.aux >= 0 { cg_fail(p, node, "wasm: dynamic-library externs are unsupported"); }
            cg_exportable(p, node);
            if cg_intrinsic(p, node) == 0 { m.imports.push(CgImport { symbol: n.symbol, signature: cg_make_signature(p, m, node, false) }); }
        } else { m.functions.push(CgFunction { node: node, symbol: n.symbol }); }
    }
    let ordinary_count = m.functions.len;
    for index in 0..ordinary_count {
        let item = m.functions[index]; let result = cg_result_type(p, item.node);
        if cg_type_kind(p, result) == TY_ARRAY && p.types[result].array_kind == A_VAR && !cg_nonlocal_target(p, item.node) {
            m.functions.push(CgFunction { node: item.node, symbol: item.symbol, elements: true });
        }
    }
    for item in m.functions { if cg_uses_pool(p, p.nodes[item.node].right) { m.pool_global = 0; break; } }
    if m.pool_global < 0 { for symbol in p.symbols { if (symbol.flags & S_GLOBAL) != 0 && symbol.node >= 0 && cg_uses_pool(p, p.nodes[symbol.node].right) { m.pool_global = 0; break; } } }
    var format_demand = 0;
    for item in m.functions { format_demand |= cg_float_format_demand(p, p.nodes[item.node].right); }
    for symbol in p.symbols { if (symbol.flags & S_GLOBAL) != 0 && symbol.node >= 0 { format_demand |= cg_float_format_demand(p, p.nodes[symbol.node].right); } }
    if (format_demand & 1) != 0 { m.format_f32 = m.imports.len; m.imports.push(CgImport { signature: cg_host_signature(m, CG_FORMAT_F32), host: CG_FORMAT_F32 }); }
    if (format_demand & 2) != 0 { m.format_f64 = m.imports.len; m.imports.push(CgImport { signature: cg_host_signature(m, CG_FORMAT_F64), host: CG_FORMAT_F64 }); }
    cg_plan_private_arenas(p, m);
    for item in m.functions { cg_scan_captures(p, m, item.node, p.nodes[item.node].right); }
    loop {
        let count = m.captures.len;
        for item in m.functions { cg_propagate_captures(p, m, item.node, p.nodes[item.node].right); }
        if count == m.captures.len { break; }
    }
    for item, i in m.functions {
        m.region_functions.push(RegionFunction { node: item.node, entry: item.node == p.entry || (p.nodes[item.node].flags & F_EXPORT) != 0 });
        var count = 0; for capture in m.captures { if capture.function == item.node { count++; } }
        m.functions[i].capture_count = count;
        m.functions[i].signature = cg_make_signature(p, m, item.node, false);
        m.functions[i].closure_signature = cg_make_signature(p, m, item.node, true);
        m.functions[i].index = m.imports.len + i;
    }
    m.region_functions.push(RegionFunction { entry: true });
    m.start = m.imports.len + m.functions.len; m.allocator = m.start + 1; m.float_wrap = m.start + 2;
    if m.pool_global < 0 { m.regions_enabled = cg_array_regions_supported(p, m); }
    var grows = false;
    for ty in p.types { if ty.kind == TY_ARRAY && (ty.array_kind == A_GROW || ty.array_kind == A_GROWSHRINK) { grows = true; } }
    if grows && !m.regions_enabled { m.resolver = m.start + 3; }
    if m.pool_global >= 0 { m.pool_global = 5; if m.resolver >= 0 { m.pool_global = 8; } }
    var thunk_base = m.start + 3; if m.resolver >= 0 { thunk_base++; }
    if m.regions_enabled {
        m.header_helper = thunk_base; thunk_base += 1;
        var frames = false; for type_id in 0..p.types.len { if cg_frame_owner(p, type_id) { frames = true; } }
        if frames { m.prefix_helper = thunk_base; thunk_base += 1; }
    }
    var raw_appends = 0;
    for item in m.functions { raw_appends += cg_raw_append_demand(p, m, p.nodes[item.node].right); }
    for symbol in p.symbols { if (symbol.flags & S_GLOBAL) != 0 && symbol.node >= 0 { raw_appends += cg_raw_append_demand(p, m, p.nodes[symbol.node].right); } }
    if raw_appends > 1 { m.raw_append = thunk_base; thunk_base += 1; }
    for item, i in m.functions { m.functions[i].thunk = thunk_base + i; }
    if m.functions.len == 1 && m.imports.len == 9 && p.entry == m.functions[0].node && m.functions[0].capture_count == 0 {
        let entry = m.functions[0].node;
        var globals = false; for address in m.globals { if address >= 0 { globals = true; } }
        if !globals && (p.nodes[entry].flags & F_NONLOCAL) == 0 && p.nodes[entry].first < 0 && cg_result_type(p, entry) == TYPE_VOID && cg_scalar_body(p, entry, p.nodes[entry].right) { m.scalar = true; }
    }
}
fn cg_module_globals(p: Program&, m: CgModule&, out: u8[>..]&) {
    var count = 5; if m.resolver >= 0 && !m.scalar { count = 8; } if m.regions_enabled { count = 12; } if m.scalar { count = 1; }
    if m.pool_global >= 0 { count += 1; } wb_u(out, count);
    for index in 0..count {
        wb_byte(out, 0x7f); wb_byte(out, 1); var initial = 0;
        if index == 0 { initial = cg_align(m.next_data, 8); if m.scalar || m.regions_enabled { initial = cg_align(m.next_data, 16); } }
        if index == 1 { initial = m.stack_limit; }
        if m.regions_enabled {
            if index == 3 { initial = m.global_region_count; }
            if index == 6 || index == 10 { initial = m.stack_limit; }
            if index == 7 { initial = m.region_bytes; }
            if index == 8 { initial = m.region_count; }
            if index == 9 { initial = m.region_cursor_address; }
        } else if index == 7 { initial = -1; }
        wb_i32(out, initial); wb_byte(out, 0x0b);
    }
}
fn cg_layout_regions(p: Program&, m: CgModule&) {
    if !m.regions_enabled { return; }
    m.next_data = cg_align(m.next_data, 4); m.region_cursor_address = m.next_data; m.next_data += m.region_count * 4;
    let stack_base = cg_align(m.next_data, 16); let bytes = p.maximum_pages * 65536;
    if stack_base >= bytes { cg_fail(p, -1, "static data exceeds linear memory limit"); return; }
    m.region_bytes = ((bytes - stack_base) / (m.region_count + 1)) & -8;
    if m.region_count > 0 && m.region_bytes == 0 { cg_fail(p, -1, "data regions have no available storage"); return; }
    m.stack_limit = bytes - m.region_count * m.region_bytes;
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
    var signatures: CgSignature[>..] = []; var signature_bytes: u8[>..] = []; var segments: CgSegment[>..] = []; var data: u8[>..] = []; var globals: i64[>..] = []; var global_regions: i64[>..] = []; var region_functions: RegionFunction[>..] = []; var region_calls: RegionCall[>..] = [];
    var m = CgModule { functions: functions, captures: captures, imports: imports, signatures: signatures, signature_bytes: signature_bytes, segments: segments, data: data, globals: globals, global_regions: global_regions, region_functions: region_functions, region_calls: region_calls,
        stack_limit: (p.maximum_pages * 65536 / 2) & -8 };
    cg_collect(p, m); if p.diagnostics.len > 0 { return; }
    if m.scalar { m.resolver = -1; }
    var body_count = m.functions.len * 2 + 3; if m.resolver >= 0 { body_count++; } if m.header_helper >= 0 { body_count++; } if m.prefix_helper >= 0 { body_count++; } if m.raw_append >= 0 { body_count++; } if m.scalar { body_count = m.functions.len + 1; }
    var code: u8[>..] = []; wb_u(code, body_count);
    var body: u8[>..] = [];
    for item, index in m.functions { body.clear(); cg_emit_function(p, m, item.node, index, item.elements, body); wb_u(code, body.len); wb_raw(code, body); }
    body.clear(); cg_emit_function(p, m, -1, m.functions.len, false, body); wb_u(code, body.len); wb_raw(code, body);
    if !m.scalar {
        body.clear(); cg_allocator_body(body); wb_u(code, body.len); wb_raw(code, body);
        body.clear(); cg_float_wrap_body(body); wb_u(code, body.len); wb_raw(code, body);
        if m.resolver >= 0 { body.clear(); cg_resolver_body(body); wb_u(code, body.len); wb_raw(code, body); }
        if m.header_helper >= 0 { body.clear(); cg_header_publish_body(body); wb_u(code, body.len); wb_raw(code, body); }
        if m.prefix_helper >= 0 { body.clear(); cg_prefix_mapping_body(body); wb_u(code, body.len); wb_raw(code, body); }
        if m.raw_append >= 0 { body.clear(); cg_emit_raw_append(p, m, body); wb_u(code, body.len); wb_raw(code, body); }
        for item, i in m.functions { body.clear(); cg_emit_thunk(p, m, i, body); wb_u(code, body.len); wb_raw(code, body); }
    }
    cg_bound_regions(p, m); cg_layout_regions(p, m);
    if m.next_data >= m.stack_limit { cg_fail(p, -1, "wasm: static storage overlaps the activation arena"); }
    if p.diagnostics.len > 0 { return; }
    var empty: u8[>..] = []; var one_i32: u8[>..] = [0x7f]; var one_i64: u8[>..] = [0x7e]; var one_f64: u8[>..] = [0x7c];
    let start_signature = cg_signature(m, empty, empty); var allocator_signature = -1; var wrap_signature = -1; var header_signature = -1; var prefix_signature = -1; var append_signature = -1;
    if !m.scalar { allocator_signature = cg_signature(m, one_i32, one_i32); wrap_signature = cg_signature(m, one_f64, one_i64); }
    if m.header_helper >= 0 { var pair_i32: u8[>..] = [0x7f, 0x7f]; header_signature = cg_signature(m, pair_i32, empty); }
    if m.prefix_helper >= 0 { var pair_i32: u8[>..] = [0x7f, 0x7f]; prefix_signature = cg_signature(m, pair_i32, one_i32); }
    if m.raw_append >= 0 { var append_args: u8[>..] = [0x7f, 0x7f, 0x7f, 0x7f]; append_signature = cg_signature(m, append_args, empty); }
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
    if !m.scalar { wb_u(section, allocator_signature); wb_u(section, wrap_signature); if m.resolver >= 0 { wb_u(section, allocator_signature); } if m.header_helper >= 0 { wb_u(section, header_signature); } if m.prefix_helper >= 0 { wb_u(section, prefix_signature); } if m.raw_append >= 0 { wb_u(section, append_signature); } for item in m.functions { wb_u(section, item.closure_signature); } }
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
    if offset != 0 { wb_i32(f.code, offset); wb_byte(f.code, 0x6a); }
    cg_resolve_pointer(m, f); cg_canonical_address(m, f, cg_size(p, id));
    if cg_relative_type(p, id) { cg_read_relative(p, m, f, id, -1); return true; }
    if p.types[id].storage == 1 {
        let address = cg_save(f, 0x7f); let decoded = cg_read_uleb(p, m, f, address, -1);
        cg_get(f, decoded.value); wb_i64(f.code, 1); wb_byte(f.code, 0x88);
        wb_i64(f.code, 0); cg_get(f, decoded.value); wb_i64(f.code, 1); wb_byte(f.code, 0x83); wb_byte(f.code, 0x7d); wb_byte(f.code, 0x85); return true;
    }
    return cg_load_fixed(p, f.code, id, 0);
}
fn cg_relative_type(p: Program&, id: i64) -> bool {
    return cg_type_kind(p, id) == TY_REF && p.types[id].length_storage >= 0;
}
fn cg_relative_origin(p: Program&, m: CgModule&, f: CgBody&, id: i64, slot: i64, node: i64) -> i64 {
    let pool = p.types[id].pool;
    if pool < 0 { cg_get(f, slot); wb_byte(f.code, 0xad); return cg_save(f, 0x7e); }
    if pool >= p.symbols.len || p.symbols[pool].type_id < 0 || cg_type_kind(p, p.symbols[pool].type_id) != TY_ARRAY {
        cg_fail(p, node, "wasm: relative reference has no checked array pool"); wb_i64(f.code, 0); return cg_save(f, 0x7e);
    }
    cg_symbol_address(p, m, f, pool, node); let owner = cg_save(f, 0x7f);
    cg_array_pointer(p, m, f, p.symbols[pool].type_id, owner); cg_resolve_pointer(m, f);
    wb_byte(f.code, 0xad); wb_i64(f.code, 1); wb_byte(f.code, 0x7d); return cg_save(f, 0x7e);
}
fn cg_read_relative(p: Program&, m: CgModule&, f: CgBody&, id: i64, node: i64) {
    let t = p.types[id]; let slot = cg_save(f, 0x7f); let origin = cg_relative_origin(p, m, f, id, slot, node);
    if cg_image_owner(p, t.element) || cg_enum_image(p, t.element) {
        cg_fail(p, node, "wasm: a relative reference to a variable image requires a borrowed image view"); wb_i32(f.code, 0); return;
    }
    if t.length_storage == 0 {
        let decoded = cg_read_uleb(p, m, f, slot, node); cg_get(f, decoded.value);
        if t.pool < 0 {
            wb_i64(f.code, 1); wb_byte(f.code, 0x88); wb_i64(f.code, 0); cg_get(f, decoded.value);
            wb_i64(f.code, 1); wb_byte(f.code, 0x83); wb_byte(f.code, 0x7d); wb_byte(f.code, 0x85);
        }
    } else {
        cg_get(f, slot); var opcode = 0x29;
        if t.length_storage == 1 { opcode = 0x30; if t.pool >= 0 { opcode = 0x31; } }
        else if t.length_storage == 2 { opcode = 0x32; if t.pool >= 0 { opcode = 0x33; } }
        else if t.length_storage == 4 { opcode = 0x34; if t.pool >= 0 { opcode = 0x35; } }
        wb_mem(f.code, opcode, 0, 0);
    }
    let offset = cg_save(f, 0x7e);
    let optional = (t.flags & TF_OPTIONAL) != 0;
    if optional { cg_get(f, offset); wb_byte(f.code, 0x50); cg_begin(f, 0x04, 0x7f); wb_i32(f.code, 0); wb_byte(f.code, 0x05); }
    cg_get(f, origin); cg_get(f, offset); wb_byte(f.code, 0x7c); let target = cg_save(f, 0x7e);
    cg_get(f, target); wb_i64(f.code, 0); wb_byte(f.code, 0x53); cg_get(f, target); wb_i64(f.code, 4294967295); wb_byte(f.code, 0x56); wb_byte(f.code, 0x72);
    cg_trap_if(p, m, f, node, "relative reference points outside wasm32 memory"); cg_get(f, target); wb_byte(f.code, 0xa7);
    if optional { cg_end(f); }
}
fn cg_relative_offset(p: Program&, m: CgModule&, f: CgBody&, id: i64, slot: i64, value: i64, node: i64) -> i64 {
    let t = p.types[id];
    let origin = cg_relative_origin(p, m, f, id, slot, node);
    cg_get(f, value); cg_resolve_pointer(m, f); let target = cg_save(f, 0x7f);
    let optional = (t.flags & TF_OPTIONAL) != 0;
    if optional { cg_get(f, target); wb_byte(f.code, 0x45); cg_begin(f, 0x04, 0x7e); wb_i64(f.code, 0); wb_byte(f.code, 0x05); }
    cg_get(f, target); wb_byte(f.code, 0xad); cg_get(f, origin); wb_byte(f.code, 0x7d);
    if optional { cg_end(f); }
    let offset = cg_save(f, 0x7e);
    if optional {
        cg_get(f, target); wb_byte(f.code, 0x45); wb_byte(f.code, 0x45); cg_get(f, offset); wb_byte(f.code, 0x50); wb_byte(f.code, 0x71);
        cg_trap_if(p, m, f, node, "non-null relative reference encodes as null");
    }
    if t.length_storage > 0 && t.length_storage < 8 {
        var minimum = 0; var maximum = (1 as i64 << (8 * t.length_storage)) - 1;
        if t.pool < 0 { maximum >>= 1; minimum = -maximum - 1; }
        cg_get(f, offset); wb_i64(f.code, minimum); wb_byte(f.code, 0x53);
        cg_get(f, offset); wb_i64(f.code, maximum); wb_byte(f.code, 0x55); wb_byte(f.code, 0x72);
        cg_trap_if(p, m, f, node, "relative reference offset overflow");
    } else if t.pool >= 0 {
        cg_get(f, offset); wb_i64(f.code, 0); wb_byte(f.code, 0x53); cg_trap_if(p, m, f, node, "relative reference precedes its pool");
    }
    return offset;
}
fn cg_relative_encoding(p: Program&, m: CgModule&, f: CgBody&, id: i64, slot: i64, value: i64, node: i64) -> i64 {
    let offset = cg_relative_offset(p, m, f, id, slot, value, node);
    cg_get(f, offset);
    if p.types[id].length_storage == 0 && p.types[id].pool < 0 {
        wb_i64(f.code, 1); wb_byte(f.code, 0x86); cg_get(f, offset); wb_i64(f.code, 63); wb_byte(f.code, 0x87); wb_byte(f.code, 0x85);
    }
    return cg_save(f, 0x7e);
}
fn cg_write_relative(p: Program&, m: CgModule&, f: CgBody&, id: i64, destination: i64, value: i64, node: i64) -> i64 {
    let t = p.types[id];
    cg_get(f, destination); cg_resolve_pointer(m, f); let slot = cg_save(f, 0x7f);
    let encoded = cg_relative_encoding(p, m, f, id, slot, value, node);
    if t.length_storage == 0 { return cg_write_uleb(p, f, slot, encoded); }
    cg_get(f, slot); cg_canonical_address(m, f, t.length_storage); cg_get(f, encoded);
    if t.length_storage == 8 { wb_mem(f.code, 0x37, 0, 0); }
    else {
        wb_byte(f.code, 0xa7); var opcode = 0x36;
        if t.length_storage == 1 { opcode = 0x3a; } else if t.length_storage == 2 { opcode = 0x3b; }
        wb_mem(f.code, opcode, 0, 0);
    }
    return -1;
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
    if cg_owner(p, to) {
        if m.regions_enabled && !f.scratch { cg_get(f, pointer); cg_get(f, bytes); wb_byte(f.code, 0x6a); let top = cg_save(f, 0x7f); cg_region_publish(f, destination, top); }
        else if p.types[to].array_kind != A_VAR { cg_get(f, destination); cg_get(f, pointer); cg_get(f, bytes); wb_byte(f.code, 0x6a); wb_mem(f.code, 0x36, 2, 16); }
    }
    cg_get(f, destination);
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
    cg_end(f); cg_get(f, result); cg_resolve_pointer(m, f);
}
fn cg_owner_read_capacity(p: Program&, m: CgModule&, f: CgBody&, header: i64) {
    cg_get(f, header); wb_mem(f.code, 0x28, 2, 20); wb_i32(f.code, 5); wb_byte(f.code, 0x46); cg_begin(f, 0x04, 0x7f);
    cg_get(f, header); wb_mem(f.code, 0x28, 2, 16); wb_mem(f.code, 0x28, 0, 0);
    wb_byte(f.code, 0x05); cg_get(f, header); wb_mem(f.code, 0x28, 2, 12); cg_end(f);
}
fn cg_destination(f: CgBody&, type_id: i64, header: i64, lifetime: i64, elements: bool, normal: bool, escape: bool, entry: i64, construction: i64) -> i64 {
    var state = construction;
    if state < 0 { state = f.constructions.len; f.constructions.push(CgConstruction {}); }
    let result = f.construction_destinations.len;
    f.construction_destinations.push(CgDestination { type_id: type_id, header: header, lifetime: lifetime, elements: elements, normal: normal,
        escape: escape, construction: state, open0: f.constructions[state].open, entry: entry }); return result;
}
fn cg_receiving(f: CgBody&, slot: i64, ordinal: i64) -> i64 {
    var at = f.receiving.len;
    while at > 0 { at -= 1; let item = f.receiving[at]; if item.slot == slot && item.ordinal == ordinal { return item.destination; } }
    return -1;
}
fn cg_temporary_destination(p: Program&, m: CgModule&, f: CgBody&, id: i64, node: i64) -> i64 {
    let owner = cg_temporary(p, f, id); let header = cg_region_acquire(p, m, f, id, owner, -1, node); let entry = cg_region_cursor(f, header);
    return cg_destination(f, id, owner, CG_TEMPORARY, false, false, false, entry, -1);
}
fn cg_share_destination(p: Program&, m: CgModule&, f: CgBody&, source: i64, id: i64, elements: bool, normal: bool, escape: bool, node: i64) -> i64 {
    let parent = f.construction_destinations[source]; let source_header = cg_region_header(p, f, parent.type_id, parent.header);
    let owner = cg_temporary(p, f, id); let header = cg_region_header(p, f, id, owner); let entry = cg_region_cursor(f, source_header);
    cg_get(f, header); wb_i32(f.code, 0); wb_i32(f.code, 24); wb_fill(f.code);
    cg_get(f, header); cg_get(f, entry); wb_mem(f.code, 0x36, 2, 0);
    cg_get(f, header); cg_get(f, source_header); wb_mem(f.code, 0x28, 2, 8); wb_mem(f.code, 0x36, 2, 8);
    if cg_enum_image(p, id) { cg_set_enum_anchor(f, owner, entry); }
    else if cg_image_owner(p, id) { cg_set_record_anchor(p, m, f, id, owner, entry, node); }
    return cg_destination(f, id, owner, parent.lifetime, elements, normal, escape, parent.entry, parent.construction);
}
fn cg_region_varint(p: Program&, m: CgModule&, f: CgBody&, header: i64, value: i64, node: i64) -> i64 {
    cg_get(f, value); wb_i64(f.code, 1); wb_byte(f.code, 0x86); cg_get(f, value); wb_i64(f.code, 63); wb_byte(f.code, 0x87); wb_byte(f.code, 0x85); let encoded = cg_save(f, 0x7e);
    let width = cg_uleb_width(p, f, encoded); cg_get(f, width); wb_byte(f.code, 0xad); let bytes = cg_save(f, 0x7e); cg_region_reserve(p, m, f, header, bytes, node);
    let start = cg_region_cursor(f, header); let top = cg_write_uleb(p, f, start, encoded); cg_region_publish(f, header, top); return start;
}
fn cg_region_relative(p: Program&, m: CgModule&, f: CgBody&, id: i64, header: i64, value: i64, node: i64) -> i64 {
    let start = cg_region_cursor(f, header); let encoded = cg_relative_encoding(p, m, f, id, start, value, node);
    let width = cg_uleb_width(p, f, encoded); cg_get(f, width); wb_byte(f.code, 0xad); let bytes = cg_save(f, 0x7e); cg_region_reserve(p, m, f, header, bytes, node);
    let top = cg_write_uleb(p, f, start, encoded); cg_region_publish(f, header, top); return start;
}
fn cg_validate_region_array(p: Program&, m: CgModule&, f: CgBody&, id: i64, header: i64, node: i64) {
    cg_owner_read_base(p, m, f, header, node); let base = cg_save(f, 0x7f); cg_get(f, header); wb_mem(f.code, 0x28, 2, 8); let limit = cg_save(f, 0x7f);
    cg_get(f, base); cg_get(f, limit); wb_byte(f.code, 0x4b); cg_trap_if(p, m, f, node, "array image exceeds data region");
    cg_owner_read_length(p, m, f, header, node); let count = cg_save(f, 0x7f); var extent = count;
    if p.types[id].array_kind == A_LIMITED {
        cg_owner_read_capacity(p, m, f, header); extent = cg_save(f, 0x7f);
        cg_get(f, count); cg_get(f, extent); wb_byte(f.code, 0x4b); cg_trap_if(p, m, f, node, "array image length exceeds capacity");
    }
    var stride = cg_size(p, p.types[id].element); if p.types[p.types[id].element].storage == 1 { stride = 1; }
    cg_get(f, extent); wb_byte(f.code, 0xad); cg_get(f, limit); cg_get(f, base); wb_byte(f.code, 0x6b); wb_byte(f.code, 0xad); wb_i64(f.code, stride); wb_byte(f.code, 0x80); wb_byte(f.code, 0x56);
    cg_trap_if(p, m, f, node, "array image exceeds data region");
    cg_get(f, base); cg_get(f, extent); wb_i32(f.code, stride); wb_byte(f.code, 0x6c); wb_byte(f.code, 0x6a); let top = cg_save(f, 0x7f); cg_ensure_memory(p, m, f, top, node);
}
fn cg_set_array_anchor(p: Program&, f: CgBody&, header: i64, anchor: i64, id: i64) {
    var width = p.types[id].length_storage; var mode = 4;
    if p.types[id].array_kind == A_VAR && width == 0 { width = 1; mode = 6; }
    if mode != 6 {
        if p.types[id].array_kind == A_LIMITED { width = 8; mode = 5; }
        else if width == 1 { mode = 1; } else if width == 2 { mode = 2; } else if width == 4 { mode = 3; }
    }
    cg_get(f, header); cg_get(f, anchor); wb_mem(f.code, 0x36, 2, 16);
    cg_get(f, header); wb_i32(f.code, mode); wb_mem(f.code, 0x36, 2, 20);
    cg_get(f, header); cg_get(f, anchor); wb_i32(f.code, width); wb_byte(f.code, 0x6a); wb_mem(f.code, 0x36, 2, 0);
    cg_get(f, header); wb_i32(f.code, 0); wb_mem(f.code, 0x36, 2, 4);
    cg_get(f, header); if mode == 6 { wb_i32(f.code, 1); } else { wb_i32(f.code, 0); } wb_mem(f.code, 0x36, 2, 12);
}
fn cg_value_array_receiver(p: Program&, f: CgBody&, node: i64, destination: i64) -> bool {
    let n = p.nodes[node]; let target = f.construction_destinations[destination];
    if n.kind != N_CALL || n.symbol < 0 || (p.symbols[n.symbol].flags & S_FUNCTION) == 0 { return false; }
    let function = p.symbols[n.symbol].node; let natural = cg_result_type(p, function);
    if !cg_owner(p, natural) || p.types[natural].array_kind != A_VAR || !cg_nonlocal_target(p, function) { return false; }
    let to = p.types[target.type_id]; return target.elements || to.array_kind == A_GROW || to.array_kind == A_GROWSHRINK || to.array_kind == A_VAR && to.length_storage != p.types[natural].length_storage;
}
fn cg_finish_value_array(p: Program&, m: CgModule&, f: CgBody&, source: i64, destination: i64, node: i64) {
    let target = f.construction_destinations[destination]; let header = target.header; let id = target.type_id;
    cg_owner_read_length(p, m, f, source, node); let count = cg_save(f, 0x7f); cg_check_array_length(p, m, f, id, count, node);
    cg_get(f, source); wb_mem(f.code, 0x28, 2, 16); let anchor = cg_save(f, 0x7f);
    cg_get(f, source); wb_mem(f.code, 0x28, 2, 20); wb_byte(f.code, 0x45); cg_begin(f, 0x04, 0x40);
    cg_owner_read_base(p, m, f, source, node); cg_set(f, anchor); cg_end(f);
    cg_owner_read_base(p, m, f, source, node); let elements = cg_save(f, 0x7f); let finish = cg_region_cursor(f, source);
    cg_get(f, elements); cg_get(f, finish); wb_byte(f.code, 0x4b); cg_trap_if(p, m, f, node, "invalid array image adaptation span");
    cg_get(f, finish); cg_get(f, elements); wb_byte(f.code, 0x6b); let bytes = cg_save(f, 0x7f);
    var width = 0; let image = p.types[id].array_kind == A_VAR && !target.elements; var prefix = -1;
    if image && p.types[id].length_storage == 0 { cg_get(f, count); wb_byte(f.code, 0xad); let wide = cg_save(f, 0x7e); prefix = cg_uleb_width(p, f, wide); }
    else { if image { width = p.types[id].length_storage; } wb_i32(f.code, width); prefix = cg_save(f, 0x7f); }
    cg_get(f, anchor); wb_byte(f.code, 0xad); cg_get(f, prefix); wb_byte(f.code, 0xad); wb_byte(f.code, 0x7c); cg_get(f, bytes); wb_byte(f.code, 0xad); wb_byte(f.code, 0x7c); let end64 = cg_save(f, 0x7e);
    cg_get(f, end64); cg_get(f, header); wb_mem(f.code, 0x28, 2, 8); wb_byte(f.code, 0xad); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "data region exhausted");
    cg_get(f, end64); wb_byte(f.code, 0xa7); let top = cg_save(f, 0x7f); cg_ensure_memory(p, m, f, top, node);
    cg_get(f, anchor); cg_get(f, prefix); wb_byte(f.code, 0x6a); let pointer = cg_save(f, 0x7f);
    cg_get(f, pointer); cg_get(f, elements); cg_get(f, bytes); wb_copy(f.code);
    if image {
        if p.types[id].length_storage == 0 {
            cg_get(f, header); cg_get(f, anchor); wb_mem(f.code, 0x36, 2, 16); cg_get(f, header); cg_get(f, pointer); wb_mem(f.code, 0x36, 2, 0);
            cg_get(f, header); wb_i32(f.code, 6); wb_mem(f.code, 0x36, 2, 20); cg_get(f, header); cg_get(f, prefix); wb_mem(f.code, 0x36, 2, 12);
        } else { cg_set_array_anchor(p, f, header, anchor, id); }
    } else {
        cg_get(f, header); wb_i32(f.code, 0); wb_mem(f.code, 0x36, 2, 16); cg_get(f, header); wb_i32(f.code, 0); wb_mem(f.code, 0x36, 2, 20);
    }
    cg_owner_set_length(p, m, f, header, count, node); cg_region_publish(f, header, top);
}
fn cg_finish_region_array(p: Program&, m: CgModule&, f: CgBody&, original: i64, stage: i64, start: i64, id: i64, elements: bool, land: bool, node: i64) {
    let image = p.types[id].array_kind == A_VAR && !elements || p.types[id].array_kind == A_LIMITED;
    cg_owner_read_length(p, m, f, stage, node); let count = cg_save(f, 0x7f);
    if land {
        let finish = cg_region_cursor(f, original); cg_get(f, original); wb_mem(f.code, 0x28, 2, 0); let anchor = cg_save(f, 0x7f);
        if image {
            cg_get(f, original); wb_mem(f.code, 0x28, 2, 20); cg_begin(f, 0x04, 0x40);
            cg_get(f, original); wb_mem(f.code, 0x28, 2, 16); cg_set(f, anchor); cg_end(f);
        }
        cg_get(f, start); cg_get(f, anchor); wb_byte(f.code, 0x49); cg_get(f, start); cg_get(f, finish); wb_byte(f.code, 0x4b); wb_byte(f.code, 0x72);
        cg_get(f, finish); cg_get(f, original); wb_mem(f.code, 0x28, 2, 8); wb_byte(f.code, 0x4b); wb_byte(f.code, 0x72); cg_trap_if(p, m, f, node, "invalid array image landing span");
        cg_get(f, finish); cg_get(f, start); wb_byte(f.code, 0x6b); let bytes = cg_save(f, 0x7f);
        if !image {
            let element = p.types[id].element;
            if p.types[element].storage == 1 {
                cg_get(f, count); wb_byte(f.code, 0xad); let wide = cg_save(f, 0x7e); let end = cg_walk_elements(p, m, f, start, wide, node);
                cg_get(f, end); cg_get(f, finish); wb_byte(f.code, 0x4b);
            } else {
                cg_get(f, count); wb_byte(f.code, 0xad); wb_i64(f.code, cg_size(p, element)); wb_byte(f.code, 0x7e); cg_get(f, bytes); wb_byte(f.code, 0xad); wb_byte(f.code, 0x56);
            }
            cg_trap_if(p, m, f, node, "invalid nonlocal landing length");
        }
        cg_get(f, anchor); cg_get(f, start); cg_get(f, bytes); wb_copy(f.code);
        if image {
            if p.types[id].length_storage == 0 {
                cg_get(f, original); wb_mem(f.code, 0x28, 2, 20); wb_byte(f.code, 0x45); cg_begin(f, 0x04, 0x40);
                cg_get(f, original); cg_get(f, stage); wb_mem(f.code, 0x28, 2, 12); wb_mem(f.code, 0x36, 2, 12); cg_end(f);
            }
            cg_get(f, original); cg_get(f, stage); wb_mem(f.code, 0x28, 2, 20); wb_mem(f.code, 0x36, 2, 20);
            cg_get(f, original); cg_get(f, anchor); wb_mem(f.code, 0x36, 2, 16);
        } else { cg_get(f, original); cg_get(f, count); wb_mem(f.code, 0x36, 2, 4); }
        cg_get(f, anchor); cg_get(f, bytes); wb_byte(f.code, 0x6a); let top = cg_save(f, 0x7f); cg_region_publish(f, original, top);
    } else if image {
        cg_get(f, original); wb_mem(f.code, 0x28, 2, 20); wb_byte(f.code, 0x45); cg_begin(f, 0x04, 0x40);
        for offset in [0, 4, 12, 16, 20] { cg_get(f, original); cg_get(f, stage); wb_mem(f.code, 0x28, 2, offset); wb_mem(f.code, 0x36, 2, offset); }
        cg_end(f);
    } else { cg_get(f, original); cg_get(f, count); wb_mem(f.code, 0x36, 2, 4); }
    if image {
        cg_get(f, original); cg_owner_read_base(p, m, f, original, node); wb_mem(f.code, 0x36, 2, 0);
        cg_get(f, original); cg_owner_read_length(p, m, f, original, node); wb_mem(f.code, 0x36, 2, 4);
        if p.types[id].array_kind == A_LIMITED { cg_get(f, original); cg_owner_read_capacity(p, m, f, original); wb_mem(f.code, 0x36, 2, 12); }
    }
    cg_publish_header(m, f, original, 4); cg_validate_region_array(p, m, f, id, original, node);
}
fn cg_close_constructor(f: CgBody&, state: i64, opened: bool, node: i64, destination: i64, raw: i64) {
    if opened { f.constructions[state].open -= 1; }
    f.active_node = node; f.active_destination = destination; f.raw_node = raw;
}
fn cg_set_enum_anchor(f: CgBody&, owner: i64, anchor: i64) {
    for word in [0, 16] { cg_get(f, owner); cg_get(f, anchor); wb_mem(f.code, 0x36, 2, word); }
    for word in [4, 12, 20] { cg_get(f, owner); wb_i32(f.code, 0); wb_mem(f.code, 0x36, 2, word); }
}
fn cg_decode_enum(p: Program&, m: CgModule&, f: CgBody&, id: i64, owner: i64, node: i64) {
    let bytes = cg_enum_image_bytes(p, m, f, id, owner, node);
    cg_get(f, owner); cg_get(f, bytes); wb_mem(f.code, 0x36, 2, 4);
}
fn cg_finish_enum(p: Program&, m: CgModule&, f: CgBody&, id: i64, owner: i64, start: i64, land: bool, node: i64) {
    if land {
        cg_get(f, owner); wb_mem(f.code, 0x28, 2, 0); let base = cg_save(f, 0x7f); let finish = cg_region_cursor(f, owner);
        cg_get(f, finish); cg_get(f, start); wb_byte(f.code, 0x6b); let bytes = cg_save(f, 0x7f);
        cg_get(f, base); wb_byte(f.code, 0xad); cg_get(f, bytes); wb_byte(f.code, 0xad); wb_byte(f.code, 0x7c); let top64 = cg_save(f, 0x7e);
        cg_get(f, start); cg_get(f, finish); wb_byte(f.code, 0x4b); cg_get(f, top64); cg_get(f, owner); wb_mem(f.code, 0x28, 2, 8); wb_byte(f.code, 0xad); wb_byte(f.code, 0x56); wb_byte(f.code, 0x72); cg_trap_if(p, m, f, node, "invalid enum image landing span");
        cg_get(f, top64); wb_byte(f.code, 0xa7); let top = cg_save(f, 0x7f); cg_ensure_memory(p, m, f, top, node);
        cg_get(f, base); cg_get(f, start); cg_get(f, bytes); wb_copy(f.code); cg_region_publish(f, owner, top);
    }
    cg_decode_enum(p, m, f, id, owner, node);
}
recursive fn cg_packed_integer_image(p: Program&, id: i64) -> bool {
    if cg_type_kind(p, id) == TY_INT { return p.types[id].storage == 0; }
    if cg_type_kind(p, id) == TY_ARRAY { return p.types[id].array_kind == A_FIXED && p.types[id].count > 0 && cg_packed_integer_image(p, p.types[id].element); }
    if cg_type_kind(p, id) != TY_STRUCT || cg_has_owner(p, id) || p.types[id].first < 0 { return false; }
    var field = p.types[id].first; while field >= 0 { let n = p.nodes[field]; if (n.flags & F_PAD) != 0 || !cg_packed_integer_image(p, n.type_id) { return false; } field = n.next; } return true;
}
fn cg_enum_effect_supported(p: Program&, id: i64) -> bool {
    var variant = p.types[id].first;
    while variant >= 0 {
        let payload = p.nodes[variant].type_id;
        if cg_has_owner(p, payload) { if !cg_record_effect_supported(p, payload) { return false; } }
        else { var field = p.types[payload].first; while field >= 0 { if !cg_packed_integer_image(p, p.nodes[field].type_id) { return false; } field = p.nodes[field].next; } }
        variant = p.nodes[variant].next;
    }
    return true;
}
fn cg_prepare_enum_payload(p: Program&, m: CgModule&, f: CgBody&, destination: i64, variant: i64, node: i64, tag: bool) -> i64 {
    let target = f.construction_destinations[destination]; let id = target.type_id; let owner = target.header; let width = p.types[id].length_storage;
    var top = cg_region_cursor(f, owner);
    if tag {
        wb_i64(f.code, width); let bytes = cg_save(f, 0x7e); top = cg_region_reserve(p, m, f, owner, bytes, node); let cursor = cg_region_cursor(f, owner);
        cg_get(f, cursor); wb_i32(f.code, p.nodes[variant].integer); if width == 2 { wb_mem(f.code, 0x3b, 0, 0); } else { wb_mem(f.code, 0x3a, 0, 0); } cg_region_publish(f, owner, top);
    }
    let payload = p.nodes[variant].type_id;
    if !cg_region_value(p, payload) { return -1; }
    let carrier = cg_temporary(p, f, payload); let header = cg_region_header(p, f, payload, carrier);
    cg_get(f, header); wb_i32(f.code, 0); wb_i32(f.code, 24); wb_fill(f.code); cg_get(f, header); cg_get(f, owner); wb_mem(f.code, 0x28, 2, 8); wb_mem(f.code, 0x36, 2, 8);
    cg_set_record_anchor(p, m, f, payload, carrier, top, node);
    return cg_destination(f, payload, carrier, target.lifetime, false, false, true, target.entry, target.construction);
}
fn cg_variant_result(p: Program&, natural: i64, target: i64) -> i64 {
    var from = natural; while cg_type_kind(p, from) == TY_REF { from = p.types[from].element; }
    if !cg_enum_image(p, target) || cg_type_kind(p, from) != TY_STRUCT || p.types[from].pool < 0 { return -1; }
    if p.types[p.types[from].pool].declaration != p.types[target].declaration { return -1; }
    return p.types[from].declaration;
}
fn cg_prepare_variant_result(p: Program&, m: CgModule&, f: CgBody&, natural: i64, receiving: i64, node: i64) -> i64 {
    let target = f.construction_destinations[receiving]; let variant = cg_variant_result(p, natural, target.type_id);
    var producer = cg_prepare_enum_payload(p, m, f, receiving, variant, node, cg_result_count(p, p.nodes[node].type_id) != 1 || cg_enum_image(p, p.nodes[node].coerced_type));
    if producer < 0 { producer = cg_destination(f, natural, cg_temporary(p, f, natural), CG_TEMPORARY, false, false, false, -1, -1); }
    return producer;
}
fn cg_publish_variant_result(p: Program&, m: CgModule&, f: CgBody&, natural: i64, source: i64, producer: i64, receiving: i64, node: i64) {
    let target = f.construction_destinations[receiving]; var payload = natural; while cg_type_kind(p, payload) == TY_REF { payload = p.types[payload].element; }
    if cg_region_value(p, payload) {
        if cg_type_kind(p, natural) == TY_REF { cg_construct_captured(p, m, f, natural, source, producer, node); }
    } else { cg_append_fixed_variant(p, m, f, target.header, payload, source, node); }
    cg_decode_enum(p, m, f, target.type_id, target.header, node);
}
fn cg_append_fixed_variant(p: Program&, m: CgModule&, f: CgBody&, owner: i64, payload: i64, source: i64, node: i64) {
    var count = cg_size(p, payload); if p.types[payload].first < 0 { count = 0; }
    wb_i64(f.code, count); let bytes = cg_save(f, 0x7e); let top = cg_region_reserve(p, m, f, owner, bytes, node); let cursor = cg_region_cursor(f, owner);
    if count > 0 { cg_get(f, cursor); cg_get(f, source); wb_i32(f.code, count); wb_copy(f.code); } cg_region_publish(f, owner, top);
}
recursive fn cg_construct_enum_captured(p: Program&, m: CgModule&, f: CgBody&, natural: i64, source: i64, destination: i64, node: i64) {
    let target = f.construction_destinations[destination]; let id = target.type_id; let owner = target.header; var from = natural;
    while cg_type_kind(p, from) == TY_REF { from = p.types[from].element; }
    if cg_enum_image(p, from) {
        let count = cg_enum_image_bytes(p, m, f, from, source, node); cg_get(f, count); wb_byte(f.code, 0xad); let bytes = cg_save(f, 0x7e); let top = cg_region_reserve(p, m, f, owner, bytes, node); let cursor = cg_region_cursor(f, owner);
        cg_get(f, cursor); cg_get(f, source); wb_mem(f.code, 0x28, 2, 0); cg_get(f, count); wb_copy(f.code); cg_region_publish(f, owner, top); cg_decode_enum(p, m, f, id, owner, node); return;
    }
    if cg_type_kind(p, from) == TY_STRUCT {
        let variant = p.types[from].declaration; let receiving = cg_prepare_enum_payload(p, m, f, destination, variant, node, true);
        if receiving >= 0 { cg_construct_captured(p, m, f, from, source, receiving, node); }
        else { cg_append_fixed_variant(p, m, f, owner, from, source, node); }
        cg_decode_enum(p, m, f, id, owner, node); return;
    }
    cg_get(f, source); var load = 0x2d; if p.types[from].length_storage == 2 { load = 0x2f; } wb_mem(f.code, load, 0, 0); let tag = cg_save(f, 0x7f); let done = cg_begin(f, 0x02, 0x40); var variant = p.types[id].first;
    while variant >= 0 {
        cg_get(f, tag); wb_i32(f.code, p.nodes[variant].integer); wb_byte(f.code, 0x46); cg_begin(f, 0x04, 0x40);
        let receiving = cg_prepare_enum_payload(p, m, f, destination, variant, node, true); cg_get(f, source); wb_i32(f.code, p.types[from].length_storage); wb_byte(f.code, 0x6a); let payload = cg_save(f, 0x7f);
        if receiving >= 0 { cg_construct_captured(p, m, f, p.nodes[variant].type_id, payload, receiving, node); }
        else { cg_append_fixed_variant(p, m, f, owner, p.nodes[variant].type_id, payload, node); }
        cg_branch(p, f, done, false); cg_end(f); variant = p.nodes[variant].next;
    }
    cg_abort(p, m, f, node, "invalid enum tag"); cg_end(f); cg_decode_enum(p, m, f, id, owner, node);
}
recursive fn cg_construct_enum(p: Program&, m: CgModule&, f: CgBody&, node: i64, destination: i64) {
    let target = f.construction_destinations[destination]; let id = target.type_id; let owner = target.header; var kind = N_RECORD; if node >= 0 { kind = p.nodes[node].kind; }
    if kind == N_NAME && p.nodes[node].symbol >= 0 && cg_same_destination(f, cg_named_array_destination(p, f, p.nodes[node].symbol), destination) { cg_decode_enum(p, m, f, id, owner, node); return; }
    if target.normal && !target.escape {
        let start = cg_region_cursor(f, owner); let land = f.constructions[target.construction].open > target.open0; let stage = cg_share_destination(p, m, f, destination, id, false, false, true, node);
        cg_construct_enum(p, m, f, node, stage); cg_finish_enum(p, m, f, id, owner, start, land, node); return;
    }
    if node >= 0 && kind == N_UNARY && (p.nodes[node].flags & F_SYNTHETIC) != 0 && p.nodes[node].integer == T_MUL && cg_variant_result(p, p.nodes[p.nodes[node].left].type_id, id) >= 0 {
        cg_construct_enum(p, m, f, p.nodes[node].left, destination); return;
    }
    if node >= 0 && kind == N_CALL && p.nodes[node].symbol >= 0 && (p.symbols[p.nodes[node].symbol].flags & S_BUILTIN) != 0 {
        if p.symbols[p.nodes[node].symbol].index == 15 { cg_construct_enum(p, m, f, p.nodes[node].first, destination); return; }
        if p.symbols[p.nodes[node].symbol].index == 14 { cg_construct_enum(p, m, f, -1, destination); return; }
    }
    let saved_node = f.active_node; let saved_destination = f.active_destination; let saved_raw = f.raw_node; f.active_node = node; f.active_destination = destination;
    let control = kind == N_BLOCK || kind == N_IF || kind == N_GUARD || kind == N_LOOP || kind == N_WHILE || kind == N_MATCH; if !control { f.constructions[target.construction].open += 1; }
    var variant = -1;
    if node < 0 { variant = p.types[id].first; }
    else if kind == N_RECORD { variant = p.nodes[node].symbol; }
    else if kind == N_MEMBER && p.nodes[node].symbol >= 0 && p.nodes[p.nodes[node].symbol].kind == N_VARIANT { variant = p.nodes[node].symbol; }
    else if kind == N_INTEGER { variant = p.types[id].first; while variant >= 0 && p.nodes[variant].integer != p.nodes[node].integer { variant = p.nodes[variant].next; } }
    if control || kind == N_CALL && cg_direct_array_call(p, f, node, destination) { cg_expr(p, m, f, node); if !cg_diverges(p, node) { wb_byte(f.code, 0x1a); } }
    else if variant >= 0 {
        let payload = p.nodes[variant].type_id; let receiving = cg_prepare_enum_payload(p, m, f, destination, variant, node, true);
        if receiving >= 0 { cg_construct_region(p, m, f, node, receiving); }
        else {
            var field = p.types[payload].first;
            while field >= 0 {
                let n = p.nodes[field]; let value = cg_record_initializer(p, node, field); var scalar = -1;
                if (n.flags & F_PAD) == 0 && value >= 0 { cg_to(p, m, f, value, n.type_id); if cg_diverges(p, value) { break; } scalar = cg_save(f, cg_wasm_type(p, n.type_id)); }
                var size = cg_size(p, n.type_id); if (n.flags & F_PAD) != 0 { size = n.aux; }
                wb_i64(f.code, size); let bytes = cg_save(f, 0x7e); let top = cg_region_reserve(p, m, f, owner, bytes, node); let cursor = cg_region_cursor(f, owner);
                if scalar >= 0 { cg_get(f, scalar); cg_write_value(p, m, f, n.type_id, cursor, node); }
                else { cg_get(f, cursor); wb_i32(f.code, 0); wb_i32(f.code, size); wb_fill(f.code); }
                cg_region_publish(f, owner, top); field = n.next;
            }
        }
        if node < 0 || !cg_diverges(p, node) { cg_decode_enum(p, m, f, id, owner, node); }
    } else {
        cg_expr(p, m, f, node); if !cg_diverges(p, node) { let source = cg_save(f, 0x7f); cg_construct_enum_captured(p, m, f, p.nodes[node].type_id, source, destination, node); }
    }
    cg_close_constructor(f, target.construction, !control, saved_node, saved_destination, saved_raw);
}
fn cg_inline_array_receiver(p: Program&, natural: i64, destination: CgDestination) -> bool {
    if !cg_owner(p, natural) || p.types[natural].array_kind != A_VAR || !cg_owner(p, destination.type_id) { return false; }
    let receiving = p.types[destination.type_id]; return destination.elements || receiving.array_kind == A_GROW || receiving.array_kind == A_GROWSHRINK || receiving.array_kind == A_LIMITED;
}
fn cg_value_array_adaptation(p: Program&, natural: i64, destination: CgDestination) -> bool {
    if !cg_owner(p, natural) || !cg_owner(p, destination.type_id) || p.types[natural].array_kind != A_VAR { return false; }
    let receiving = p.types[destination.type_id]; return destination.elements || receiving.array_kind == A_GROW || receiving.array_kind == A_GROWSHRINK || receiving.array_kind == A_VAR && receiving.length_storage != p.types[natural].length_storage;
}
recursive fn cg_construct_captured(p: Program&, m: CgModule&, f: CgBody&, natural: i64, source: i64, destination: i64, node: i64) {
    let target = f.construction_destinations[destination]; let id = target.type_id;
    if cg_enum_image(p, id) { cg_construct_enum_captured(p, m, f, natural, source, destination, node); return; }
    if cg_image_owner(p, id) { cg_construct_image_captured(p, m, f, id, source, destination, node); return; }
    if cg_frame_owner(p, id) { cg_construct_frame_captured(p, m, f, id, source, destination, node); return; }
    cg_get(f, source); cg_pack_view(p, m, f, natural, node); let view = cg_save(f, 0x7e);
    cg_get(f, view); wb_i64(f.code, 32); wb_byte(f.code, 0x88); wb_byte(f.code, 0xa7); let count = cg_save(f, 0x7f); cg_check_array_length(p, m, f, id, count, node);
    var capacity = count;
    if cg_owner(p, natural) && p.types[natural].array_kind == A_LIMITED { cg_owner_read_capacity(p, m, f, source); capacity = cg_save(f, 0x7f); }
    let previous_node = f.active_node; let previous_destination = f.active_destination; f.active_node = node; f.active_destination = destination;
    let pointer = cg_region_array_prefix(p, m, f, id, target.header, count, capacity, node);
    cg_get(f, view); wb_byte(f.code, 0xa7); let base = cg_save(f, 0x7f); var bytes = -1;
    if p.types[p.types[id].element].storage == 1 {
        cg_get(f, count); wb_byte(f.code, 0xad); let wide = cg_save(f, 0x7e); let end = cg_walk_elements(p, m, f, base, wide, node); cg_get(f, end); cg_get(f, base); wb_byte(f.code, 0x6b); bytes = cg_save(f, 0x7f);
    } else {
        var extent = count; if p.types[id].array_kind == A_LIMITED { extent = capacity; }
        cg_get(f, extent); wb_i32(f.code, cg_size(p, p.types[id].element)); wb_byte(f.code, 0x6c); bytes = cg_save(f, 0x7f);
    }
    cg_get(f, bytes); wb_byte(f.code, 0xad); let wide = cg_save(f, 0x7e); let top = cg_region_reserve(p, m, f, target.header, wide, node);
    cg_get(f, pointer); cg_get(f, base); cg_get(f, bytes); wb_copy(f.code); cg_region_publish(f, target.header, top);
    f.active_node = previous_node; f.active_destination = previous_destination;
}
fn cg_set_record_anchor(p: Program&, m: CgModule&, f: CgBody&, id: i64, owner: i64, base: i64, node: i64) {
    let header = cg_region_header(p, f, id, owner);
    if cg_byte_record(p, id) {
        for word in [0, 16] { cg_get(f, header); cg_get(f, base); wb_mem(f.code, 0x36, 2, word); } return;
    }
    cg_get(f, base); wb_i32(f.code, cg_record_total_prefix(p, id)); wb_byte(f.code, 0x6a); let anchor = cg_save(f, 0x7f);
    let tail = cg_image_tail_type(p, id);
    if cg_enum_image(p, tail) { cg_set_enum_anchor(f, header, anchor); }
    else { cg_set_array_anchor(p, f, header, anchor, tail); }
}
fn cg_decode_record(p: Program&, m: CgModule&, f: CgBody&, id: i64, owner: i64, node: i64) {
    let header = cg_region_header(p, f, id, owner);
    if cg_byte_record(p, id) {
        let end = cg_byte_field(p, m, f, id, owner, -1, node);
        cg_get(f, header); cg_get(f, end); cg_get(f, header); wb_mem(f.code, 0x28, 2, 16); wb_byte(f.code, 0x6b); wb_mem(f.code, 0x36, 2, 4); return;
    }
    let tail = cg_image_tail_type(p, id);
    if cg_enum_image(p, tail) { cg_decode_enum(p, m, f, tail, header, node); return; }
    cg_get(f, header); cg_owner_read_base(p, m, f, header, node); wb_mem(f.code, 0x36, 2, 0);
    cg_get(f, header); cg_owner_read_length(p, m, f, header, node); wb_mem(f.code, 0x36, 2, 4);
    if p.types[tail].array_kind == A_LIMITED { cg_get(f, header); cg_owner_read_capacity(p, m, f, header); wb_mem(f.code, 0x36, 2, 12); }
    cg_validate_region_array(p, m, f, tail, header, node);
}
fn cg_record_effect_supported(p: Program&, id: i64) -> bool {
    var current = id;
    while cg_record_image(p, current) {
        var field = p.types[current].first;
        while field >= 0 && field != p.types[current].tail {
            let n = p.nodes[field]; if (n.flags & F_PAD) == 0 && (cg_type_kind(p, n.type_id) != TY_INT || p.types[n.type_id].storage != 0) { return false; } field = n.next;
        }
        current = p.nodes[p.types[current].tail].type_id;
    }
    if !cg_owner(p, current) || p.types[current].array_kind != A_VAR && p.types[current].array_kind != A_LIMITED { return false; }
    return p.types[current].length_storage != 0 && p.types[p.types[current].element].storage == 0;
}
fn cg_record_physical_base(p: Program&, m: CgModule&, f: CgBody&, id: i64, owner: i64, node: i64) -> i64 {
    if cg_byte_record(p, id) { cg_get(f, owner); wb_mem(f.code, 0x28, 2, 16); return cg_save(f, 0x7f); }
    return cg_record_image_base(p, m, f, id, owner, node);
}
fn cg_finish_record_image(p: Program&, m: CgModule&, f: CgBody&, id: i64, owner: i64, start: i64, land: bool, node: i64) {
    let header = cg_region_header(p, f, id, owner);
    if land {
        let base = cg_record_physical_base(p, m, f, id, owner, node); let finish = cg_region_cursor(f, header);
        cg_get(f, finish); cg_get(f, start); wb_byte(f.code, 0x6b); let bytes = cg_save(f, 0x7f);
        cg_get(f, base); wb_byte(f.code, 0xad); cg_get(f, bytes); wb_byte(f.code, 0xad); wb_byte(f.code, 0x7c); let top64 = cg_save(f, 0x7e);
        cg_get(f, start); cg_get(f, finish); wb_byte(f.code, 0x4b); cg_get(f, top64); cg_get(f, header); wb_mem(f.code, 0x28, 2, 8); wb_byte(f.code, 0xad); wb_byte(f.code, 0x56); wb_byte(f.code, 0x72); cg_trap_if(p, m, f, node, "invalid record image landing span");
        cg_get(f, top64); wb_byte(f.code, 0xa7); let top = cg_save(f, 0x7f); cg_ensure_memory(p, m, f, top, node);
        cg_get(f, base); cg_get(f, start); cg_get(f, bytes); wb_copy(f.code); cg_region_publish(f, header, top);
    }
    cg_decode_record(p, m, f, id, owner, node);
}
fn cg_construct_image_captured(p: Program&, m: CgModule&, f: CgBody&, id: i64, source: i64, destination: i64, node: i64) {
    let target = f.construction_destinations[destination]; let header = cg_region_header(p, f, id, target.header);
    cg_decode_record(p, m, f, id, source, node); let base = cg_record_physical_base(p, m, f, id, source, node); var bytes = -1;
    if cg_byte_record(p, id) { cg_get(f, source); wb_mem(f.code, 0x28, 2, 4); bytes = cg_save(f, 0x7f); }
    else { bytes = cg_record_image_bytes(p, m, f, id, source, node); }
    cg_get(f, bytes); wb_byte(f.code, 0xad); let wide = cg_save(f, 0x7e); let top = cg_region_reserve(p, m, f, header, wide, node); let cursor = cg_region_cursor(f, header);
    cg_get(f, cursor); cg_get(f, base); cg_get(f, bytes); wb_copy(f.code); cg_region_publish(f, header, top); cg_decode_record(p, m, f, id, target.header, node);
}
recursive fn cg_construct_record_image(p: Program&, m: CgModule&, f: CgBody&, node: i64, destination: i64) {
    let target = f.construction_destinations[destination]; let id = target.type_id; let owner = target.header; let header = cg_region_header(p, f, id, owner);
    var kind = N_RECORD; if node >= 0 { kind = p.nodes[node].kind; }
    if kind == N_NAME && p.nodes[node].symbol >= 0 && cg_same_destination(f, cg_named_array_destination(p, f, p.nodes[node].symbol), destination) { cg_decode_record(p, m, f, id, owner, node); return; }
    if target.normal && !target.escape {
        let start = cg_region_cursor(f, header); let land = f.constructions[target.construction].open > target.open0;
        let stage = cg_share_destination(p, m, f, destination, id, false, false, true, node); cg_construct_record_image(p, m, f, node, stage);
        cg_finish_record_image(p, m, f, id, owner, start, land, node); return;
    }
    if node >= 0 && kind == N_CALL && p.nodes[node].symbol >= 0 && (p.symbols[p.nodes[node].symbol].flags & S_BUILTIN) != 0 && p.symbols[p.nodes[node].symbol].index == 15 { cg_construct_record_image(p, m, f, p.nodes[node].first, destination); return; }
    let saved_node = f.active_node; let saved_destination = f.active_destination; let saved_raw = f.raw_node;
    f.active_node = node; f.active_destination = destination;
    let control = kind == N_BLOCK || kind == N_IF || kind == N_GUARD || kind == N_LOOP || kind == N_WHILE || kind == N_MATCH;
    if !control { f.constructions[target.construction].open += 1; }
    if control || kind == N_CALL && cg_direct_array_call(p, f, node, destination) { cg_expr(p, m, f, node); if !cg_diverges(p, node) { wb_byte(f.code, 0x1a); } }
    else if kind == N_RECORD {
        var field = p.types[id].first;
        while field >= 0 {
            let n = p.nodes[field]; let value = cg_record_initializer(p, node, field);
            if !cg_byte_record(p, id) && field == p.types[id].tail {
                let child = n.type_id; let carrier = cg_temporary(p, f, child); let child_header = cg_region_header(p, f, child, carrier); let start = cg_region_cursor(f, header);
                cg_get(f, child_header); wb_i32(f.code, 0); wb_i32(f.code, 24); wb_fill(f.code);
                cg_get(f, child_header); cg_get(f, start); wb_mem(f.code, 0x36, 2, 0); cg_get(f, child_header); cg_get(f, header); wb_mem(f.code, 0x28, 2, 8); wb_mem(f.code, 0x36, 2, 8);
                if cg_enum_image(p, child) { cg_set_enum_anchor(f, carrier, start); }
                else if cg_image_owner(p, child) { cg_set_record_anchor(p, m, f, child, carrier, start, node); }
                let receiving = cg_destination(f, child, carrier, target.lifetime, false, false, true, target.entry, target.construction);
                if value >= 0 || cg_image_owner(p, child) || cg_enum_image(p, child) { cg_construct_region(p, m, f, value, receiving); }
                else {
                    let previous_node = f.active_node; let previous_destination = f.active_destination; f.active_node = node; f.active_destination = receiving;
                    wb_i32(f.code, 0); let zero = cg_save(f, 0x7f); cg_region_array_prefix(p, m, f, child, carrier, zero, zero, node); f.active_node = previous_node; f.active_destination = previous_destination;
                }
            } else if (n.flags & F_PAD) != 0 {
                wb_i64(f.code, n.aux); let bytes = cg_save(f, 0x7e); let top = cg_region_reserve(p, m, f, header, bytes, node); let cursor = cg_region_cursor(f, header);
                cg_get(f, cursor); wb_i32(f.code, 0); wb_i32(f.code, n.aux); wb_fill(f.code); cg_region_publish(f, header, top);
            } else if cg_relative_type(p, n.type_id) && p.types[n.type_id].length_storage == 0 {
                if value >= 0 { cg_to(p, m, f, value, n.type_id); if cg_diverges(p, value) { break; } } else { wb_i32(f.code, 0); }
                let reference = cg_save(f, 0x7f); cg_region_relative(p, m, f, n.type_id, header, reference, node);
            } else if p.types[n.type_id].storage == 1 {
                if value >= 0 { cg_to(p, m, f, value, TYPE_I64); if cg_diverges(p, value) { break; } } else { wb_i64(f.code, 0); }
                let scalar = cg_save(f, 0x7e); cg_region_varint(p, m, f, header, scalar, node);
            } else {
                var scalar = -1;
                if value >= 0 { cg_to(p, m, f, value, n.type_id); if cg_diverges(p, value) { break; } scalar = cg_save(f, cg_wasm_type(p, n.type_id)); }
                wb_i64(f.code, cg_size(p, n.type_id)); let bytes = cg_save(f, 0x7e); let top = cg_region_reserve(p, m, f, header, bytes, node); let cursor = cg_region_cursor(f, header);
                if scalar >= 0 { cg_get(f, scalar); cg_write_value(p, m, f, n.type_id, cursor, node); }
                else { cg_get(f, cursor); wb_i32(f.code, 0); wb_i32(f.code, cg_size(p, n.type_id)); wb_fill(f.code); }
                cg_region_publish(f, header, top);
            }
            if value >= 0 && cg_diverges(p, value) { break; } field = n.next;
        }
        if node < 0 || !cg_diverges(p, node) { cg_decode_record(p, m, f, id, owner, node); }
    } else {
        cg_expr(p, m, f, node); if !cg_diverges(p, node) {
            var from = p.nodes[node].type_id; while cg_type_kind(p, from) == TY_REF { from = p.types[from].element; cg_load(p, m, f, from, 0); }
            let source = cg_save(f, 0x7f); cg_construct_image_captured(p, m, f, id, source, destination, node);
        }
    }
    cg_close_constructor(f, target.construction, !control, saved_node, saved_destination, saved_raw);
}
recursive fn cg_construct_region(p: Program&, m: CgModule&, f: CgBody&, node: i64, destination: i64) -> i64 {
    let id = f.construction_destinations[destination].type_id;
    if p.nodes[node].kind == N_RESULT {
        let forwarded = cg_projection_receiver(p, m, f, node, destination); cg_project_result(p, m, f, node, destination);
        if cg_diverges(p, node) { return 0; }
        if forwarded { wb_byte(f.code, 0x1a); }
        else { let source = cg_save(f, cg_wasm_type(p, p.nodes[node].type_id)); cg_construct_captured(p, m, f, p.nodes[node].type_id, source, destination, node); }
        return 0;
    }
    if cg_enum_image(p, id) { cg_construct_enum(p, m, f, node, destination); }
    else if cg_image_owner(p, id) { cg_construct_record_image(p, m, f, node, destination); }
    else if cg_frame_owner(p, id) { cg_construct_frame_record(p, m, f, node, destination); }
    else { cg_construct_array(p, m, f, node, destination); }
    return 0;
}
fn cg_record_initializer(p: Program&, node: i64, field: i64) -> i64 {
    if node < 0 { return -1; } var binding = p.nodes[node].first;
    while binding >= 0 { if p.nodes[binding].symbol == field { return p.nodes[binding].right; } binding = p.nodes[binding].next; } return -1;
}
fn cg_frame_tail_destination(p: Program&, f: CgBody&, destination: i64, field: i64) -> i64 {
    let parent = f.construction_destinations[destination]; let n = p.nodes[field];
    cg_get(f, parent.header); wb_i32(f.code, n.integer); wb_byte(f.code, 0x6a); let owner = cg_save(f, 0x7f);
    return cg_destination(f, n.type_id, owner, parent.lifetime, false, false, false, parent.entry, parent.construction);
}
fn cg_copy_frame_prefix(p: Program&, m: CgModule&, f: CgBody&, id: i64, destination: i64, source: i64) {
    let bytes = cg_frame_prefix(p, id); if bytes == 0 { return; }
    cg_get(f, destination); cg_canonical_address(m, f, bytes); cg_get(f, source); cg_canonical_address(m, f, bytes); wb_i32(f.code, bytes); wb_copy(f.code);
}
fn cg_finish_frame_record(p: Program&, m: CgModule&, f: CgBody&, id: i64, original: i64, stage: i64, start: i64, base: i64, land: bool, node: i64) {
    cg_copy_frame_prefix(p, m, f, id, original, stage);
    let receiving = cg_region_header(p, f, id, original); let source = cg_region_header(p, f, id, stage);
    cg_get(f, source); wb_mem(f.code, 0x28, 2, 0); let final_base = cg_save(f, 0x7f);
    if land {
        cg_get(f, final_base); cg_get(f, start); wb_byte(f.code, 0x6b); cg_get(f, base); wb_byte(f.code, 0x6a); cg_set(f, final_base);
        cg_get(f, receiving); cg_get(f, base); wb_mem(f.code, 0x36, 2, 0);
    }
    cg_finish_region_array(p, m, f, receiving, source, start, cg_frame_tail_type(p, id), false, land, node);
    cg_get(f, receiving); cg_get(f, final_base); wb_mem(f.code, 0x36, 2, 0); cg_publish_header(m, f, receiving, 0);
}
recursive fn cg_construct_frame_captured(p: Program&, m: CgModule&, f: CgBody&, id: i64, source: i64, destination: i64, node: i64) {
    let target = f.construction_destinations[destination]; cg_copy_frame_prefix(p, m, f, id, target.header, source);
    let source_tail = cg_region_header(p, f, id, source); let tail = cg_region_header(p, f, id, target.header); let tail_id = cg_frame_tail_type(p, id);
    cg_get(f, source_tail); cg_pack_view(p, m, f, tail_id, node); let view = cg_save(f, 0x7e);
    cg_get(f, view); wb_i64(f.code, 32); wb_byte(f.code, 0x88); wb_byte(f.code, 0xa7); let count = cg_save(f, 0x7f);
    let saved_node = f.active_node; let saved_destination = f.active_destination;
    let tail_destination = cg_destination(f, tail_id, tail, target.lifetime, false, false, false, target.entry, target.construction); f.active_node = node; f.active_destination = tail_destination;
    let pointer = cg_region_array_prefix(p, m, f, tail_id, tail, count, count, node);
    cg_get(f, count); wb_byte(f.code, 0xad); wb_i64(f.code, cg_size(p, p.types[tail_id].element)); wb_byte(f.code, 0x7e); let bytes = cg_save(f, 0x7e); let top = cg_region_reserve(p, m, f, tail, bytes, node);
    cg_get(f, pointer); cg_get(f, view); wb_byte(f.code, 0xa7); cg_get(f, bytes); wb_byte(f.code, 0xa7); wb_copy(f.code); cg_region_publish(f, tail, top);
    f.active_node = saved_node; f.active_destination = saved_destination;
}
recursive fn cg_construct_frame_record(p: Program&, m: CgModule&, f: CgBody&, node: i64, destination: i64) {
    let target = f.construction_destinations[destination]; let id = target.type_id; let owner = target.header; let header = cg_region_header(p, f, id, owner);
    var kind = N_RECORD; if node >= 0 { kind = p.nodes[node].kind; }
    if kind == N_NAME && p.nodes[node].symbol >= 0 && cg_same_destination(f, cg_named_array_destination(p, f, p.nodes[node].symbol), destination) {
        cg_symbol_address(p, m, f, p.nodes[node].symbol, node); let source = cg_save(f, 0x7f); cg_copy_frame_prefix(p, m, f, id, owner, source);
        let tail = cg_region_header(p, f, id, source);
        for word in [0, 4] { cg_get(f, header); cg_get(f, tail); wb_mem(f.code, 0x28, 2, word); wb_mem(f.code, 0x36, 2, word); cg_publish_header(m, f, header, word); } return;
    }
    if target.normal && !target.escape {
        let start = cg_region_cursor(f, header); cg_get(f, header); wb_mem(f.code, 0x28, 2, 0); let base = cg_save(f, 0x7f); let land = f.constructions[target.construction].open > target.open0;
        let stage = cg_share_destination(p, m, f, destination, id, false, false, true, node); let publication = cg_map_frame(p, m, f, f.construction_destinations[stage].header, owner, cg_frame_prefix(p, id));
        cg_construct_frame_record(p, m, f, node, stage); cg_finish_frame_record(p, m, f, id, owner, f.construction_destinations[stage].header, start, base, land, node); cg_restore_publications(f, publication); return;
    }
    if node >= 0 && kind == N_CALL && p.nodes[node].symbol >= 0 && (p.symbols[p.nodes[node].symbol].flags & S_BUILTIN) != 0 && p.symbols[p.nodes[node].symbol].index == 15 { cg_construct_frame_record(p, m, f, p.nodes[node].first, destination); return; }
    let saved_node = f.active_node; let saved_destination = f.active_destination; let saved_raw = f.raw_node;
    f.active_node = node; f.active_destination = destination;
    let control = kind == N_BLOCK || kind == N_IF || kind == N_GUARD || kind == N_LOOP || kind == N_WHILE || kind == N_MATCH;
    if !control { f.constructions[target.construction].open += 1; }
    if control || kind == N_CALL && cg_direct_array_call(p, f, node, destination) { cg_expr(p, m, f, node); if !cg_diverges(p, node) { wb_byte(f.code, 0x1a); } }
    else if kind == N_RECORD {
        var field = p.types[id].first;
        while field >= 0 {
            let n = p.nodes[field]; let value = cg_record_initializer(p, node, field);
            cg_get(f, owner); wb_i32(f.code, n.integer); wb_byte(f.code, 0x6a); let address = cg_save(f, 0x7f);
            if field == p.types[id].tail {
                let receiving = cg_frame_tail_destination(p, f, destination, field);
                if cg_owner(p, n.type_id) {
                    let cursor = cg_region_cursor(f, address); cg_get(f, address); cg_get(f, cursor); wb_mem(f.code, 0x36, 2, 0); cg_publish_header(m, f, address, 0);
                    wb_i32(f.code, 0); let zero = cg_save(f, 0x7f); cg_owner_set_length(p, m, f, address, zero, node);
                }
                if value >= 0 { cg_construct_region(p, m, f, value, receiving); }
                else if cg_frame_owner(p, n.type_id) { cg_construct_region(p, m, f, -1, receiving); }
                else {
                    let before_node = f.active_node; let before_destination = f.active_destination; f.active_node = node; f.active_destination = receiving;
                    wb_i32(f.code, 0); let zero = cg_save(f, 0x7f); cg_region_array_prefix(p, m, f, n.type_id, address, zero, zero, node); f.active_node = before_node; f.active_destination = before_destination;
                }
            } else if (n.flags & F_PAD) != 0 {
                cg_get(f, address); cg_canonical_address(m, f, n.aux); wb_i32(f.code, 0); wb_i32(f.code, n.aux); wb_fill(f.code);
            } else if value >= 0 { cg_to(p, m, f, value, n.type_id); if cg_diverges(p, value) { break; } cg_write_value(p, m, f, n.type_id, address, field); }
            else { cg_get(f, address); cg_canonical_address(m, f, cg_size(p, n.type_id)); wb_i32(f.code, 0); wb_i32(f.code, cg_size(p, n.type_id)); wb_fill(f.code); }
            if value >= 0 && cg_diverges(p, value) { break; } field = n.next;
        }
    } else {
        cg_expr(p, m, f, node); if !cg_diverges(p, node) {
            var from = p.nodes[node].type_id; while cg_type_kind(p, from) == TY_REF { from = p.types[from].element; cg_load(p, m, f, from, 0); }
            let source = cg_save(f, 0x7f); cg_construct_frame_captured(p, m, f, id, source, destination, node);
        }
    }
    cg_close_constructor(f, target.construction, !control, saved_node, saved_destination, saved_raw);
}
recursive fn cg_construct_array(p: Program&, m: CgModule&, f: CgBody&, node: i64, destination: i64) {
    let target = f.construction_destinations[destination]; let id = target.type_id; let header = target.header; let element = p.types[id].element;
    let n = p.nodes[node];
    if n.kind == N_NAME && n.symbol >= 0 && cg_same_destination(f, cg_named_array_destination(p, f, n.symbol), destination) {
        let local = p.symbols[n.symbol].type_id;
        if cg_nonlocal_target(p, f.function) && cg_owner(p, local) && (p.types[local].array_kind == A_VAR || p.types[local].array_kind == A_LIMITED) &&
           (p.types[id].array_kind == A_VAR || p.types[id].array_kind == A_LIMITED) { return; }
        cg_symbol_address(p, m, f, n.symbol, node); let source = cg_save(f, 0x7f);
        let prefix = cg_named_prefix(f, n.symbol);
        if prefix >= 0 { cg_owner_read_length(p, m, f, source, node); let count = cg_save(f, 0x7f); cg_check_array_length(p, m, f, id, count, node); cg_owner_set_length(p, m, f, prefix, count, node); return; }
        cg_owner_read_length(p, m, f, source, node); let count = cg_save(f, 0x7f); if !target.elements { cg_check_array_length(p, m, f, id, count, node); }
        cg_owner_set_length(p, m, f, header, count, node);
        if p.types[id].array_kind == A_LIMITED { cg_get(f, header); cg_get(f, source); wb_mem(f.code, 0x28, 2, 12); wb_mem(f.code, 0x36, 2, 12); }
        return;
    }
    if target.normal && !target.escape {
        let start = cg_region_cursor(f, header); let land = f.constructions[target.construction].open > target.open0;
        let stage = cg_share_destination(p, m, f, destination, id, target.elements, false, true, node);
        var publication = -1;
        if target.elements || p.types[id].array_kind == A_GROW || p.types[id].array_kind == A_GROWSHRINK { publication = cg_map_header(p, m, f, f.construction_destinations[stage].header, header); }
        cg_construct_array(p, m, f, node, stage); cg_finish_region_array(p, m, f, header, f.construction_destinations[stage].header, start, id, target.elements, land, node);
        cg_restore_publications(f, publication); return;
    }
    if n.kind == N_CALL && n.symbol >= 0 && (p.symbols[n.symbol].flags & S_BUILTIN) != 0 && p.symbols[n.symbol].index == 15 {
        cg_construct_array(p, m, f, n.first, destination); return;
    }
    let saved_node = f.active_node; let saved_destination = f.active_destination; let saved_raw = f.raw_node;
    f.active_node = node; f.active_destination = destination; if target.elements { f.raw_node = node; }
    let control = n.kind == N_BLOCK || n.kind == N_IF || n.kind == N_GUARD || n.kind == N_LOOP || n.kind == N_WHILE || n.kind == N_MATCH;
    if !control { f.constructions[target.construction].open += 1; }
    if n.kind == N_BLOCK || n.kind == N_IF || n.kind == N_GUARD || n.kind == N_LOOP || n.kind == N_WHILE || n.kind == N_MATCH {
        cg_expr(p, m, f, node); wb_byte(f.code, 0x1a);
    } else if cg_value_array_receiver(p, f, node, destination) {
        let natural = cg_result_type(p, p.symbols[n.symbol].node); let adapter = cg_share_destination(p, m, f, destination, natural, false, false, target.escape, node);
        f.active_destination = adapter; f.raw_node = -1; cg_expr(p, m, f, node);
        if !cg_diverges(p, node) { wb_byte(f.code, 0x1a); cg_finish_value_array(p, m, f, f.construction_destinations[adapter].header, destination, node); }
    } else if n.kind == N_CALL && cg_direct_array_call(p, f, node, destination) {
        if target.elements || p.types[id].array_kind == A_GROW || p.types[id].array_kind == A_GROWSHRINK { f.raw_node = node; }
        cg_expr(p, m, f, node); wb_byte(f.code, 0x1a);
    } else if n.kind == N_ARRAY || n.kind == N_FILL {
        var count = 0; var child = n.first; while child >= 0 { count += 1; child = p.nodes[child].next; }
        var count_local = -1;
        if n.right >= 0 {
            cg_to(p, m, f, n.right, TYPE_U64); let wide = cg_save(f, 0x7e); cg_get(f, wide); wb_i64(f.code, 4294967295); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array repetition count out of range");
            cg_get(f, wide); wb_byte(f.code, 0xa7); count_local = cg_save(f, 0x7f);
        } else { wb_i32(f.code, count); count_local = cg_save(f, 0x7f); }
        cg_check_array_length(p, m, f, id, count_local, node);
        var capacity = count_local;
        if n.third >= 0 {
            cg_to(p, m, f, n.third, TYPE_U64); let wide = cg_save(f, 0x7e); cg_get(f, wide); wb_i64(f.code, 4294967295); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array capacity out of range");
            cg_get(f, wide); wb_byte(f.code, 0xa7); capacity = cg_save(f, 0x7f);
            cg_get(f, count_local); cg_get(f, capacity); wb_byte(f.code, 0x4b); cg_trap_if(p, m, f, node, "array capacity exceeded");
        }
        let pointer = cg_region_array_prefix(p, m, f, id, header, count_local, capacity, node);
        if !cg_has_owner(p, element) && cg_has_relative(p, element) {
            cg_get(f, count_local); wb_byte(f.code, 0xad); wb_i64(f.code, cg_size(p, element)); wb_byte(f.code, 0x7e); let bytes = cg_save(f, 0x7e);
            let top = cg_region_reserve(p, m, f, header, bytes, node);
            cg_literal_elements(p, m, f, node, element, pointer, count_local);
            if !cg_diverges(p, node) { cg_region_publish(f, header, top); }
            cg_close_constructor(f, target.construction, !control, saved_node, saved_destination, saved_raw); return;
        }
        var fill = -1;
        if n.right >= 0 && n.first >= 0 {
            var value_type = element; if p.types[element].storage == 1 { value_type = TYPE_I64; }
            cg_to(p, m, f, n.first, value_type);
            if cg_diverges(p, n.first) { cg_close_constructor(f, target.construction, !control, saved_node, saved_destination, saved_raw); return; }
            fill = cg_save(f, cg_wasm_type(p, value_type));
            if p.types[element].storage != 1 {
                cg_get(f, count_local); wb_byte(f.code, 0xad); wb_i64(f.code, cg_size(p, element)); wb_byte(f.code, 0x7e); let bytes = cg_save(f, 0x7e); cg_region_reserve(p, m, f, header, bytes, node);
            }
        }
        if n.right >= 0 && n.first >= 0 {
            wb_i32(f.code, 0); let index = cg_save(f, 0x7f); let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
            cg_get(f, index); cg_get(f, count_local); wb_byte(f.code, 0x4f); cg_branch(p, f, done, true);
            if p.types[element].storage == 1 { cg_region_varint(p, m, f, header, fill, node); }
            else {
                wb_i64(f.code, cg_size(p, element)); let bytes = cg_save(f, 0x7e); let top = cg_region_reserve(p, m, f, header, bytes, node); let cursor = cg_region_cursor(f, header);
                cg_get(f, fill); cg_write_value(p, m, f, element, cursor, node); cg_region_publish(f, header, top);
            }
            cg_get(f, index); wb_i32(f.code, 1); wb_byte(f.code, 0x6a); cg_set(f, index); cg_branch(p, f, again, false); cg_end(f); cg_end(f);
        } else {
            child = n.first;
            while child >= 0 {
                var value_type = element; if p.types[element].storage == 1 { value_type = TYPE_I64; }
                cg_to(p, m, f, child, value_type); if cg_diverges(p, child) { break; } let value = cg_save(f, cg_wasm_type(p, value_type));
                if p.types[element].storage == 1 { cg_region_varint(p, m, f, header, value, child); }
                else {
                    wb_i64(f.code, cg_size(p, element)); let bytes = cg_save(f, 0x7e); let top = cg_region_reserve(p, m, f, header, bytes, child); let cursor = cg_region_cursor(f, header);
                    cg_get(f, value); cg_write_value(p, m, f, element, cursor, child); cg_region_publish(f, header, top);
                }
                child = p.nodes[child].next;
            }
        }
        if p.types[id].array_kind == A_LIMITED {
            cg_get(f, capacity); cg_get(f, count_local); wb_byte(f.code, 0x6b); wb_byte(f.code, 0xad); wb_i64(f.code, cg_size(p, element)); wb_byte(f.code, 0x7e); let spare = cg_save(f, 0x7e); cg_region_reserve(p, m, f, header, spare, node);
            cg_get(f, pointer); cg_get(f, capacity); wb_i32(f.code, cg_size(p, element)); wb_byte(f.code, 0x6c); wb_byte(f.code, 0x6a); let top = cg_save(f, 0x7f); cg_region_publish(f, header, top);
        }
    } else {
        var natural = n.type_id; let receiving_raw = f.raw_node;
        if n.kind == N_CALL && cg_owner(p, natural) && p.types[natural].array_kind == A_VAR &&
           p.types[id].array_kind == A_VAR && p.types[natural].length_storage != p.types[id].length_storage && (n.flags & F_DISPATCH) == 0 { f.raw_node = node; }
        cg_expr(p, m, f, node); f.raw_node = receiving_raw;
        if cg_diverges(p, node) { cg_close_constructor(f, target.construction, !control, saved_node, saved_destination, saved_raw); return; }
        while cg_type_kind(p, natural) == TY_REF { natural = p.types[natural].element; cg_load(p, m, f, natural, 0); }
        var source_capacity = -1;
        if cg_owner(p, natural) && p.types[natural].array_kind == A_LIMITED {
            let source_header = cg_save(f, 0x7f); cg_owner_read_capacity(p, m, f, source_header); source_capacity = cg_save(f, 0x7f); cg_get(f, source_header);
        }
        cg_pack_view(p, m, f, natural, node); let view = cg_save(f, 0x7e);
        cg_get(f, view); wb_i64(f.code, 32); wb_byte(f.code, 0x88); wb_byte(f.code, 0xa7); let count = cg_save(f, 0x7f); cg_check_array_length(p, m, f, id, count, node);
        var capacity = count; var pointer = -1; let existing_limited = p.types[id].array_kind == A_LIMITED && target.lifetime == CG_EXISTING;
        if existing_limited {
            cg_owner_read_capacity(p, m, f, header); capacity = cg_save(f, 0x7f);
            cg_get(f, count); cg_get(f, capacity); wb_byte(f.code, 0x4b); cg_trap_if(p, m, f, node, "array capacity exceeded");
            cg_owner_read_base(p, m, f, header, node); pointer = cg_save(f, 0x7f);
        } else {
            if p.types[id].array_kind == A_LIMITED && source_capacity >= 0 { capacity = source_capacity; }
            pointer = cg_region_owner_image(p, m, f, id, header, count, capacity, node);
        }
        cg_get(f, view); wb_byte(f.code, 0xa7); let source = cg_save(f, 0x7f); var bytes = -1;
        if p.types[element].storage == 1 {
            cg_get(f, count); wb_byte(f.code, 0xad); let wide = cg_save(f, 0x7e); let end = cg_walk_elements(p, m, f, source, wide, node);
            cg_get(f, end); cg_get(f, source); wb_byte(f.code, 0x6b); bytes = cg_save(f, 0x7f);
        } else {
            var extent = count; if p.types[id].array_kind == A_LIMITED && source_capacity >= 0 && !existing_limited { extent = capacity; }
            cg_get(f, extent); wb_i32(f.code, cg_size(p, element)); wb_byte(f.code, 0x6c); bytes = cg_save(f, 0x7f);
        }
        var top = -1;
        if existing_limited {
            cg_get(f, pointer); cg_get(f, capacity); wb_i32(f.code, cg_size(p, element)); wb_byte(f.code, 0x6c); wb_byte(f.code, 0x6a); top = cg_save(f, 0x7f); cg_ensure_memory(p, m, f, top, node);
        } else { cg_get(f, bytes); wb_byte(f.code, 0xad); let wide = cg_save(f, 0x7e); top = cg_region_reserve(p, m, f, header, wide, node); }
        cg_get(f, pointer); cg_get(f, source); cg_get(f, bytes); wb_copy(f.code); cg_owner_set_length(p, m, f, header, count, node); cg_region_publish(f, header, top);
    }
    cg_close_constructor(f, target.construction, !control, saved_node, saved_destination, saved_raw);
}
fn cg_region_header(p: Program&, f: CgBody&, id: i64, owner: i64) -> i64 {
    var current = id; var offset = 0;
    while cg_type_kind(p, current) == TY_STRUCT && !cg_byte_record(p, current) && p.types[current].tail >= 0 {
        let tail = p.types[current].tail; offset += p.nodes[tail].integer; current = p.nodes[tail].type_id;
    }
    cg_get(f, owner); if offset != 0 { wb_i32(f.code, offset); wb_byte(f.code, 0x6a); } return cg_save(f, 0x7f);
}
fn cg_region_cursor_slot(f: CgBody&, header: i64) -> i64 {
    cg_get(f, header); wb_mem(f.code, 0x28, 2, 8); wb_op(f.code, 0x23, 6); wb_byte(f.code, 0x6b);
    wb_op(f.code, 0x23, 7); wb_byte(f.code, 0x6e); wb_i32(f.code, 1); wb_byte(f.code, 0x6b);
    wb_i32(f.code, 4); wb_byte(f.code, 0x6c); wb_op(f.code, 0x23, 9); wb_byte(f.code, 0x6a); return cg_save(f, 0x7f);
}
fn cg_region_cursor(f: CgBody&, header: i64) -> i64 {
    let slot = cg_region_cursor_slot(f, header); cg_get(f, slot); wb_mem(f.code, 0x28, 2, 0); return cg_save(f, 0x7f);
}
fn cg_region_publish(f: CgBody&, header: i64, top: i64) {
    let slot = cg_region_cursor_slot(f, header); cg_get(f, slot); cg_get(f, top); wb_mem(f.code, 0x36, 2, 0);
}
fn cg_region_reserve(p: Program&, m: CgModule&, f: CgBody&, header: i64, bytes: i64, node: i64) -> i64 {
    let cursor = cg_region_cursor(f, header); cg_get(f, header); wb_mem(f.code, 0x28, 2, 8); let limit = cg_save(f, 0x7f);
    cg_get(f, cursor); cg_get(f, limit); wb_op(f.code, 0x23, 7); wb_byte(f.code, 0x6b); wb_byte(f.code, 0x49);
    cg_get(f, cursor); cg_get(f, limit); wb_byte(f.code, 0x4b); wb_byte(f.code, 0x72); cg_trap_if(p, m, f, node, "data region exhausted");
    cg_get(f, bytes); cg_get(f, limit); cg_get(f, cursor); wb_byte(f.code, 0x6b); wb_byte(f.code, 0xad); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "data region exhausted");
    cg_get(f, cursor); wb_byte(f.code, 0xad); cg_get(f, bytes); wb_byte(f.code, 0x7c); let top64 = cg_save(f, 0x7e);
    cg_get(f, top64); cg_get(f, limit); wb_byte(f.code, 0xad); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "data region exhausted");
    cg_get(f, top64); wb_byte(f.code, 0xa7); let top = cg_save(f, 0x7f); cg_ensure_memory(p, m, f, top, node); return top;
}
fn cg_region_acquire(p: Program&, m: CgModule&, f: CgBody&, id: i64, owner: i64, global_region: i64, node: i64) -> i64 {
    let header = cg_region_header(p, f, id, owner);
    if global_region >= 0 { wb_i32(f.code, global_region); } else { wb_op(f.code, 0x23, 3); }
    let region = cg_save(f, 0x7f); cg_get(f, region); wb_op(f.code, 0x23, 8); wb_byte(f.code, 0x4f); cg_trap_if(p, m, f, node, "data-region count exhausted");
    if global_region < 0 {
        cg_get(f, region); wb_i32(f.code, 1); wb_byte(f.code, 0x6a); wb_op(f.code, 0x24, 3);
        f.region_live += 1; if f.region_live > f.region_peak { f.region_peak = f.region_live; }
    }
    wb_op(f.code, 0x23, 6); cg_get(f, region); wb_op(f.code, 0x23, 7); wb_byte(f.code, 0x6c); wb_byte(f.code, 0x6a); let base = cg_save(f, 0x7f);
    cg_get(f, header); wb_i32(f.code, 0); wb_i32(f.code, 24); wb_fill(f.code);
    cg_get(f, header); cg_get(f, base); wb_mem(f.code, 0x36, 2, 0);
    cg_get(f, header); cg_get(f, base); wb_op(f.code, 0x23, 7); wb_byte(f.code, 0x6a); wb_mem(f.code, 0x36, 2, 8);
    cg_region_publish(f, header, base);
    if cg_enum_image(p, id) { cg_set_enum_anchor(f, owner, base); }
    else if cg_image_owner(p, id) { cg_set_record_anchor(p, m, f, id, owner, base, node); }
    return header;
}
fn cg_region_array_prefix(p: Program&, m: CgModule&, f: CgBody&, id: i64, header: i64, count: i64, capacity: i64, node: i64) -> i64 {
    var existing = false;
    if f.active_node == node && f.active_destination >= 0 { existing = f.construction_destinations[f.active_destination].header == header; }
    if !existing { cg_region_acquire(p, m, f, id, header, -1, node); }
    let image = cg_region_cursor(f, header);
    var mode = 0; var width = 0;
    if p.types[id].array_kind == A_VAR && !cg_raw_value(f, node) {
        width = p.types[id].length_storage;
        if width == 0 { mode = 6; } else if width == 1 { mode = 1; } else if width == 2 { mode = 2; }
        else if width == 4 { mode = 3; } else { mode = 4; }
    }
    if p.types[id].array_kind == A_LIMITED { mode = 5; width = 8; }
    var prefix = -1;
    if mode == 6 { cg_get(f, count); wb_byte(f.code, 0xad); let value = cg_save(f, 0x7e); prefix = cg_uleb_width(p, f, value); }
    else { wb_i32(f.code, width); prefix = cg_save(f, 0x7f); }
    cg_get(f, prefix); wb_byte(f.code, 0xad); let prefix64 = cg_save(f, 0x7e); let pointer = cg_region_reserve(p, m, f, header, prefix64, node);
    cg_get(f, header); if mode == 0 { wb_i32(f.code, 0); } else { cg_get(f, image); } wb_mem(f.code, 0x36, 2, 16);
    cg_get(f, header); cg_get(f, pointer); wb_mem(f.code, 0x36, 2, 0);
    cg_get(f, header); cg_get(f, count); wb_mem(f.code, 0x36, 2, 4); cg_publish_header(m, f, header, 4);
    cg_get(f, header); if mode == 6 { cg_get(f, prefix); } else { cg_get(f, capacity); } wb_mem(f.code, 0x36, 2, 12);
    cg_get(f, header); wb_i32(f.code, mode); wb_mem(f.code, 0x36, 2, 20);
    if mode == 6 { cg_get(f, count); wb_byte(f.code, 0xad); let value = cg_save(f, 0x7e); cg_write_uleb(p, f, image, value); }
    else if mode != 0 {
        cg_get(f, image); if mode == 5 { cg_get(f, capacity); wb_mem(f.code, 0x36, 0, 0); cg_get(f, image); cg_get(f, count); wb_mem(f.code, 0x36, 0, 4); }
        else { cg_get(f, count); if mode == 1 { wb_mem(f.code, 0x3a, 0, 0); } else if mode == 2 { wb_mem(f.code, 0x3b, 0, 0); }
            else if mode == 3 { wb_mem(f.code, 0x36, 0, 0); } else { wb_byte(f.code, 0xad); wb_mem(f.code, 0x37, 0, 0); } }
    }
    cg_region_publish(f, header, pointer);
    return pointer;
}
fn cg_region_owner_image(p: Program&, m: CgModule&, f: CgBody&, id: i64, header: i64, count: i64, capacity: i64, node: i64) -> i64 {
    let pointer = cg_region_array_prefix(p, m, f, id, header, count, capacity, node);
    cg_get(f, capacity); wb_byte(f.code, 0xad); var stride = cg_size(p, p.types[id].element); if p.types[p.types[id].element].storage == 1 { stride = 1; }
    wb_i64(f.code, stride); wb_byte(f.code, 0x7e); let bytes = cg_save(f, 0x7e); cg_region_reserve(p, m, f, header, bytes, node); return pointer;
}

fn cg_check_array_length(p: Program&, m: CgModule&, f: CgBody&, id: i64, count: i64, node: i64) {
    if cg_type_kind(p, id) != TY_ARRAY || p.types[id].array_kind != A_VAR || cg_raw_value(f, node) { return; }
    let width = p.types[id].length_storage;
    if width <= 0 || width >= 8 { return; }
    let maximum = (1 << (width * 8)) - 1;
    cg_get(f, count); wb_byte(f.code, 0xad); wb_i64(f.code, maximum); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array length exceeds storage range");
}
fn cg_owner_image(p: Program&, m: CgModule&, f: CgBody&, id: i64, header: i64, count: i64, capacity: i64, node: i64) -> i64 {
    cg_check_array_length(p, m, f, id, count, node);
    if m.regions_enabled && !f.scratch { return cg_region_owner_image(p, m, f, id, header, count, capacity, node); }
    let element = p.types[id].element; var stride = cg_size(p, element); if p.types[element].storage == 1 { stride = 10; }
    var mode = 0; var prefix_bytes = 0;
    if p.types[id].array_kind == A_VAR && !cg_raw_value(f, node) {
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
    cg_get(f, bytes); wb_byte(f.code, 0xa7); cg_allocate(p, m, f, node); let image = cg_save(f, 0x7f);
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
fn cg_patch_uleb_length(p: Program&, m: CgModule&, f: CgBody&, header: i64, count: i64, node: i64) {
    cg_get(f, count); wb_byte(f.code, 0xad); let value = cg_save(f, 0x7e); let width = cg_uleb_width(p, f, value);
    cg_get(f, header); wb_mem(f.code, 0x28, 2, 12); let previous = cg_save(f, 0x7f);
    cg_get(f, previous); wb_i32(f.code, 1); wb_byte(f.code, 0x49); cg_get(f, previous); wb_i32(f.code, 10); wb_byte(f.code, 0x4b); wb_byte(f.code, 0x72); cg_trap_if(p, m, f, node, "invalid ULEB construction prefix");
    cg_get(f, header); wb_mem(f.code, 0x28, 2, 16); let image = cg_save(f, 0x7f);
    cg_get(f, image); cg_get(f, previous); wb_byte(f.code, 0x6a); let source = cg_save(f, 0x7f); let finish = cg_region_cursor(f, header);
    cg_get(f, finish); cg_get(f, source); wb_byte(f.code, 0x49); cg_trap_if(p, m, f, node, "invalid ULEB construction suffix");
    cg_get(f, finish); wb_byte(f.code, 0xad); cg_get(f, width); wb_byte(f.code, 0xad); wb_byte(f.code, 0x7c); cg_get(f, previous); wb_byte(f.code, 0xad); wb_byte(f.code, 0x7d); let end = cg_save(f, 0x7e);
    cg_get(f, end); cg_get(f, header); wb_mem(f.code, 0x28, 2, 8); wb_byte(f.code, 0xad); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "data region exhausted");
    cg_get(f, end); wb_byte(f.code, 0xa7); let top = cg_save(f, 0x7f); cg_ensure_memory(p, m, f, top, node);
    cg_get(f, image); cg_get(f, width); wb_byte(f.code, 0x6a); let destination = cg_save(f, 0x7f);
    cg_get(f, destination); cg_get(f, source); cg_get(f, finish); cg_get(f, source); wb_byte(f.code, 0x6b); wb_copy(f.code); cg_write_uleb(p, f, image, value);
    cg_get(f, header); cg_get(f, destination); wb_mem(f.code, 0x36, 2, 0); cg_region_publish(f, header, top);
}
fn cg_owner_set_length(p: Program&, m: CgModule&, f: CgBody&, header: i64, count: i64, node: i64) {
    cg_get(f, header); cg_get(f, count); wb_mem(f.code, 0x36, 2, 4); cg_publish_header(m, f, header, 4);
    cg_get(f, header); wb_mem(f.code, 0x28, 2, 20); let mode = cg_save(f, 0x7f); let done = cg_begin(f, 0x02, 0x40);
    for selected in 1..7 {
        cg_get(f, mode); wb_i32(f.code, selected); wb_byte(f.code, 0x46); cg_begin(f, 0x04, 0x40);
        cg_get(f, header); wb_mem(f.code, 0x28, 2, 16); let image = cg_save(f, 0x7f);
        if selected == 6 {
            if m.regions_enabled { cg_patch_uleb_length(p, m, f, header, count, node); }
            else {
                cg_get(f, count); wb_byte(f.code, 0xad); let value = cg_save(f, 0x7e); let width = cg_uleb_width(p, f, value);
                cg_get(f, width); cg_get(f, header); wb_mem(f.code, 0x28, 2, 12); wb_byte(f.code, 0x47); cg_trap_if(p, m, f, node, "immutable array length changed its prefix width"); cg_write_uleb(p, f, image, value);
            }
        } else {
            cg_get(f, image); cg_get(f, count);
            if selected == 1 { wb_mem(f.code, 0x3a, 0, 0); } else if selected == 2 { wb_mem(f.code, 0x3b, 0, 0); } else if selected == 3 { wb_mem(f.code, 0x36, 0, 0); }
            else if selected == 5 { wb_mem(f.code, 0x36, 0, 4); } else { wb_byte(f.code, 0xad); wb_mem(f.code, 0x37, 0, 0); }
        }
        cg_branch(p, f, done, false); cg_end(f);
    }
    cg_end(f);
}
recursive fn cg_encoded_array_initializers(p: Program&, m: CgModule&, f: CgBody&, node: i64, header: i64, pointer: i64, count: i64, fill_value: i64) {
    let n = p.nodes[node]; cg_get(f, pointer); let cursor = cg_save(f, 0x7f);
    if n.right >= 0 && n.first >= 0 {
        let value = fill_value; wb_i32(f.code, 0); let index = cg_save(f, 0x7f);
        let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
        cg_get(f, index); cg_get(f, count); wb_byte(f.code, 0x4f); cg_branch(p, f, done, true);
        let end = cg_write_varint(p, f, cursor, value); cg_get(f, end); cg_set(f, cursor);
        cg_get(f, index); wb_i32(f.code, 1); wb_byte(f.code, 0x6a); cg_set(f, index); cg_branch(p, f, again, false); cg_end(f); cg_end(f);
    } else {
        var child = n.first;
        while child >= 0 {
            cg_to(p, m, f, child, TYPE_I64); if cg_diverges(p, child) { return; } let value = cg_save(f, 0x7e); let end = cg_write_varint(p, f, cursor, value);
            cg_get(f, end); cg_set(f, cursor); child = p.nodes[child].next;
        }
    }
    if p.types[n.type_id].array_kind != A_VAR { cg_get(f, header); cg_get(f, cursor); wb_mem(f.code, 0x36, 2, 16); }
}
fn cg_borrowed_sequence(p: Program&, node: i64) -> bool {
    let n = p.nodes[node]; let kind = cg_type_kind(p, n.type_id);
    return kind == TY_REF || kind == TY_SLICE || n.kind == N_NAME || n.kind == N_INDEX || n.kind == N_SLICE ||
           n.kind == N_MEMBER && n.symbol >= 0 && n.symbol < p.nodes.len && p.nodes[n.symbol].kind == N_FIELD ||
           n.kind == N_UNARY && (n.integer == T_MUL || n.integer == T_XOR);
}
recursive fn cg_region_varint_builtin(p: Program&, m: CgModule&, f: CgBody&, node: i64, builtin: i64, id: i64, header: i64, arg: i64) {
    if p.types[id].array_kind != A_GROW || builtin != 24 && builtin != 25 && builtin != 29 { cg_fail(p, node, "wasm: varint growables support push, append and clear only"); return; }
    if builtin == 29 {
        cg_owner_read_base(p, m, f, header, node); let base = cg_save(f, 0x7f); cg_region_publish(f, header, base); wb_i32(f.code, 0); let count = cg_save(f, 0x7f); cg_owner_set_length(p, m, f, header, count, node); return;
    }
    var added = -1; var address = -1;
    if builtin == 24 {
        address = cg_region_cursor(f, header); cg_to(p, m, f, arg, TYPE_I64); let value = cg_save(f, 0x7e);
        cg_owner_read_length(p, m, f, header, node); wb_i32(f.code, -1); wb_byte(f.code, 0x46); cg_trap_if(p, m, f, node, "data region exhausted"); cg_region_varint(p, m, f, header, value, node);
        wb_i64(f.code, 1); added = cg_save(f, 0x7e);
    } else {
        var source = arg;
        loop {
            let n = p.nodes[source];
            if n.kind != N_CALL || n.symbol < 0 || (p.symbols[n.symbol].flags & S_BUILTIN) == 0 || p.symbols[n.symbol].index != 15 { break; }
            source = n.first;
        }
        if cg_borrowed_sequence(p, source) {
            cg_expr(p, m, f, source); cg_pack_view(p, m, f, p.nodes[source].type_id, node); let view = cg_save(f, 0x7e);
            cg_get(f, view); wb_i64(f.code, 32); wb_byte(f.code, 0x88); added = cg_save(f, 0x7e); cg_get(f, view); wb_byte(f.code, 0xa7); let cursor = cg_save(f, 0x7f);
            wb_i64(f.code, 0); let index = cg_save(f, 0x7e); let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
            cg_get(f, index); cg_get(f, added); wb_byte(f.code, 0x5a); cg_branch(p, f, done, true);
            let decoded = cg_read_uleb(p, m, f, cursor, node); cg_get(f, decoded.cursor); cg_get(f, cursor); wb_byte(f.code, 0x6b); wb_byte(f.code, 0xad); let bytes = cg_save(f, 0x7e);
            let top = cg_region_reserve(p, m, f, header, bytes, node); let destination = cg_region_cursor(f, header);
            cg_get(f, destination); cg_get(f, cursor); cg_get(f, bytes); wb_byte(f.code, 0xa7); wb_copy(f.code); cg_region_publish(f, header, top); cg_get(f, decoded.cursor); cg_set(f, cursor);
            cg_get(f, index); wb_i64(f.code, 1); wb_byte(f.code, 0x7c); cg_set(f, index); cg_branch(p, f, again, false); cg_end(f); cg_end(f);
        } else {
            let entry = cg_region_cursor(f, header); let owner = cg_destination(f, id, header, CG_EXISTING, false, false, false, entry, -1);
            var carrier = p.nodes[source].type_id; if !cg_owner(p, carrier) { carrier = id; }
            let receiving = cg_share_destination(p, m, f, owner, carrier, true, false, false, node); cg_construct_array(p, m, f, source, receiving);
            cg_owner_read_length(p, m, f, f.construction_destinations[receiving].header, node); wb_byte(f.code, 0xad); added = cg_save(f, 0x7e);
        }
    }
    cg_owner_read_length(p, m, f, header, node); wb_byte(f.code, 0xad); cg_get(f, added); wb_byte(f.code, 0x7c); let total = cg_save(f, 0x7e);
    cg_get(f, total); wb_i64(f.code, 4294967295); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "data region exhausted"); cg_get(f, total); wb_byte(f.code, 0xa7); let count = cg_save(f, 0x7f); cg_owner_set_length(p, m, f, header, count, node);
    if builtin == 24 && p.nodes[node].type_id != TYPE_VOID { cg_get(f, address); }
}
recursive fn cg_varint_array_builtin(p: Program&, m: CgModule&, f: CgBody&, node: i64, builtin: i64, id: i64, header: i64, arg: i64) {
    if m.regions_enabled { cg_region_varint_builtin(p, m, f, node, builtin, id, header, arg); return; }
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
        let saved_raw = f.raw_node; f.raw_node = arg; cg_expr(p, m, f, arg); f.raw_node = saved_raw;
        cg_pack_view(p, m, f, p.nodes[arg].type_id, node); let view = cg_save(f, 0x7e);
        cg_get(f, view); wb_byte(f.code, 0xa7); source = cg_save(f, 0x7f); cg_get(f, view); wb_i64(f.code, 32); wb_byte(f.code, 0x88); let count64 = cg_save(f, 0x7e);
        cg_get(f, count64); wb_byte(f.code, 0xa7); added = cg_save(f, 0x7f); let end = cg_walk_elements(p, m, f, source, count64, node);
        cg_get(f, end); cg_get(f, source); wb_byte(f.code, 0x6b); source_bytes = cg_save(f, 0x7f);
    }
    cg_owner_read_length(p, m, f, header, node); let old = cg_save(f, 0x7f);
    cg_get(f, old); cg_get(f, added); wb_byte(f.code, 0x6a); let count = cg_save(f, 0x7f);
    cg_get(f, count); cg_get(f, old); wb_byte(f.code, 0x49); cg_trap_if(p, m, f, node, "array length overflow");
    cg_owner_read_base(p, m, f, header, node); let base = cg_save(f, 0x7f);
    cg_get(f, header); wb_mem(f.code, 0x28, 2, 16); let end = cg_save(f, 0x7f);
    cg_get(f, end); cg_get(f, base); wb_byte(f.code, 0x49);
    cg_get(f, end); cg_get(f, header); wb_mem(f.code, 0x28, 2, 8); wb_byte(f.code, 0x4b); wb_byte(f.code, 0x72);
    cg_trap_if(p, m, f, node, "invalid varint array cursor");
    cg_get(f, end); cg_get(f, base); wb_byte(f.code, 0x6b); let old_bytes = cg_save(f, 0x7f);
    cg_get(f, old_bytes); wb_byte(f.code, 0xad);
    if source_bytes >= 0 { cg_get(f, source_bytes); wb_byte(f.code, 0xad); } else { wb_i64(f.code, 10); }
    wb_byte(f.code, 0x7c); let needed = cg_save(f, 0x7e);
    cg_get(f, needed); wb_i64(f.code, 4294967295); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array byte size overflow");
    cg_get(f, header); wb_mem(f.code, 0x28, 2, 8); cg_get(f, base); wb_byte(f.code, 0x6b); let old_capacity = cg_save(f, 0x7f);
    cg_get(f, base); let copy = cg_save(f, 0x7f); cg_get(f, old_capacity); let capacity = cg_save(f, 0x7f);
    cg_get(f, needed); cg_get(f, old_capacity); wb_byte(f.code, 0xad); wb_byte(f.code, 0x56); cg_begin(f, 0x04, 0x40);
    cg_get(f, old_capacity); wb_byte(f.code, 0xad); wb_i64(f.code, 2); wb_byte(f.code, 0x7e); let doubled = cg_save(f, 0x7e);
    cg_get(f, doubled); cg_get(f, needed); cg_get(f, doubled); cg_get(f, needed); wb_byte(f.code, 0x56); wb_byte(f.code, 0x1b); let capacity64 = cg_save(f, 0x7e);
    cg_get(f, capacity64); wb_i64(f.code, 4294967295); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array byte capacity overflow");
    cg_get(f, capacity64); wb_byte(f.code, 0xa7); cg_set(f, capacity);
    cg_get(f, capacity); cg_allocate(p, m, f, node); cg_set(f, copy);
    cg_get(f, copy); cg_get(f, base); cg_get(f, old_bytes); wb_copy(f.code);
    cg_forward_span(p, m, f, base, old_capacity, copy);
    cg_get(f, header); cg_get(f, copy); wb_mem(f.code, 0x36, 2, 0);
    cg_get(f, header); cg_get(f, copy); cg_get(f, capacity); wb_byte(f.code, 0x6a); wb_mem(f.code, 0x36, 2, 8); cg_end(f);
    cg_get(f, copy); cg_get(f, old_bytes); wb_byte(f.code, 0x6a); let destination = cg_save(f, 0x7f); var finish = -1;
    if builtin == 24 { finish = cg_write_varint(p, f, destination, value); }
    else {
        cg_get(f, source); cg_resolve_pointer(m, f); source = cg_save(f, 0x7f);
        cg_get(f, destination); cg_get(f, source); cg_get(f, source_bytes); wb_copy(f.code); cg_get(f, destination); cg_get(f, source_bytes); wb_byte(f.code, 0x6a); finish = cg_save(f, 0x7f);
    }
    cg_get(f, header); cg_get(f, count); wb_mem(f.code, 0x36, 2, 4); cg_get(f, header); cg_get(f, finish); wb_mem(f.code, 0x36, 2, 16);
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
fn cg_encoded_scalar(p: Program&, id: i64) -> bool {
    if id < 0 || id >= p.types.len { return false; }
    return p.types[id].storage == 1 || cg_relative_type(p, id) && p.types[id].length_storage == 0;
}
fn cg_byte_record(p: Program&, id: i64) -> bool {
    if cg_type_kind(p, id) != TY_STRUCT { return false; }
    var field = p.types[id].first;
    while field >= 0 {
        if (p.nodes[field].flags & F_PAD) == 0 && cg_encoded_scalar(p, p.nodes[field].type_id) { return true; }
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
    wb_name(section, "abi=1;layout=15;encoded-record-tails=terminal;encoded-arrays=combined;array-lengths=unsigned-uleb;varint-elements=sequential-grow;varint-records=sequential;record-padding=fixed-alignment-variable-explicit;static-limited=compact-lengths;enum-tags=compact;variable-enums=active-payloads;resizable-payloads=descriptor-tail;resizable-prefix=frame;record-values=packed-single-tail;owner-control=24;array-values=unsigned-prefixes;variant-payloads=packed-fields;fixed-records=packed-fields;memory=wasm32;slices=packed-ptr32-len32;features=bulk-memory,multi-value,sign-ext");
    wb_section(module, 0, section);
}
fn cg_decimal(out: u8[>..]&, value: i64) {
    var digits: u8[>..] = []; var n = value;
    if n < 0 { out.push('-'); n = 0 - n; }
    loop { digits.push((n % 10) as u8 + '0'); n /= 10; if n == 0 { break; } }
    var at = digits.len; while at > 0 { at--; out.push(digits[at]); }
}
recursive fn cg_type_name(p: Program&, out: u8[>..]&, id: i64) {
    if id < 0 || id >= p.types.len { out.append("<unresolved>"); return; }
    let t = p.types[id];
    if t.kind == TY_VOID { out.append("void"); return; }
    if t.kind == TY_BOOL { out.append("bool"); return; }
    if t.kind == TY_INT {
        if t.storage == 1 { out.append("varint"); return; }
        if (t.flags & TF_UNSIGNED) != 0 { out.push('u'); } else { out.push('i'); }
        cg_decimal(out, t.count); return;
    }
    if t.kind == TY_FLOAT { out.push('f'); cg_decimal(out, t.count); return; }
    if t.kind == TY_REF {
        cg_type_name(p, out, t.element); if (t.flags & TF_OPTIONAL) != 0 { out.push('?'); } else { out.push('&'); } return;
    }
    if t.kind == TY_ARRAY || t.kind == TY_SLICE {
        cg_type_name(p, out, t.element); out.push('[');
        if t.kind == TY_SLICE { out.push(':'); }
        else if t.array_kind == A_FIXED { cg_decimal(out, t.count); }
        else if t.array_kind == A_GROW { out.append(">.."); }
        else if t.array_kind == A_GROWSHRINK { out.append(">..<"); }
        else if t.array_kind == A_LIMITED { out.append(".."); if t.count >= 0 { cg_decimal(out, t.count); } }
        else if t.length_explicit {
            if t.length_storage == 0 { out.append("varint"); }
            else if t.length_storage > 0 { out.push('u'); cg_decimal(out, t.length_storage * 8); }
        }
        out.push(']'); return;
    }
    if t.declaration >= 0 { out.append(token_text(p, p.nodes[t.declaration].token)); }
    else if t.name_token >= 0 { out.append(token_text(p, t.name_token)); }
    if t.arguments >= 0 {
        out.push('<'); var arg = t.arguments; var first = true;
        while arg >= 0 {
            if !first { out.append(", "); } first = false;
            cg_type_name(p, out, p.nodes[arg].type_id); arg = p.nodes[arg].next;
        }
        out.push('>');
    }
}
fn cg_print_name(p: Program&, m: CgModule&, f: CgBody&, id: i64) {
    var name: u8[>..] = []; cg_type_name(p, name, id); cg_text(m, f, name);
}
fn cg_byte_record_bound(p: Program&, id: i64) -> i64 {
    var bytes = 0; var field = p.types[id].first;
    while field >= 0 {
        let n = p.nodes[field];
        if (n.flags & F_PAD) != 0 { bytes += n.aux; }
        else if cg_encoded_scalar(p, n.type_id) { bytes += 10; }
        else { bytes += cg_size(p, n.type_id); }
        field = n.next;
    }
    if bytes < 1 { return 1; } return bytes;
}
fn cg_byte_field(p: Program&, m: CgModule&, f: CgBody&, id: i64, header: i64, wanted: i64, node: i64) -> i64 {
    cg_get(f, header); wb_mem(f.code, 0x28, 2, 16); let cursor = cg_save(f, 0x7f);
    var field = p.types[id].first;
    while field >= 0 {
        let n = p.nodes[field];
        if field == wanted { return cursor; }
        if (n.flags & F_PAD) == 0 && cg_encoded_scalar(p, n.type_id) {
            let decoded = cg_read_uleb(p, m, f, cursor, node); cg_get(f, decoded.cursor); cg_set(f, cursor);
        } else {
            var bytes = n.aux; if (n.flags & F_PAD) == 0 { bytes = cg_size(p, n.type_id); }
            cg_get(f, cursor); wb_i32(f.code, bytes); wb_byte(f.code, 0x6a); cg_set(f, cursor);
        }
        cg_get(f, cursor); cg_get(f, header); wb_mem(f.code, 0x28, 2, 8); wb_byte(f.code, 0x4b);
        cg_trap_if(p, m, f, node, "byte-record field exceeds data region");
        field = n.next;
    }
    return cursor;
}
fn cg_byte_header(f: CgBody&, header: i64, image: i64, bytes: i64) {
    for offset in [0, 16] { cg_get(f, header); cg_get(f, image); wb_mem(f.code, 0x36, 2, offset); }
    cg_get(f, header); cg_get(f, image); cg_get(f, bytes); wb_byte(f.code, 0x6a); wb_mem(f.code, 0x36, 2, 8);
    cg_get(f, header); cg_get(f, bytes); wb_mem(f.code, 0x36, 2, 4);
    for offset in [12, 20] { cg_get(f, header); wb_i32(f.code, 0); wb_mem(f.code, 0x36, 2, offset); }
}
recursive fn cg_construct_byte_record(p: Program&, m: CgModule&, f: CgBody&, id: i64, header: i64, node: i64) {
    let bound = cg_byte_record_bound(p, id);
    wb_i32(f.code, bound); cg_allocate(p, m, f, node); let image = cg_save(f, 0x7f);
    wb_i32(f.code, bound); let reserved = cg_save(f, 0x7f); cg_byte_header(f, header, image, reserved);
    cg_get(f, image); let cursor = cg_save(f, 0x7f); var field = p.types[id].first;
    while field >= 0 {
        let n = p.nodes[field];
        if (n.flags & F_PAD) != 0 {
            cg_get(f, cursor); wb_i32(f.code, 0); wb_i32(f.code, n.aux); wb_fill(f.code);
            cg_get(f, cursor); wb_i32(f.code, n.aux); wb_byte(f.code, 0x6a); cg_set(f, cursor);
        } else {
            var initializer = -1;
            if node >= 0 {
                var binding = p.nodes[node].first;
                while binding >= 0 {
                    if p.nodes[binding].symbol == field { initializer = p.nodes[binding].right; break; }
                    binding = p.nodes[binding].next;
                }
            }
            if cg_relative_type(p, n.type_id) && p.types[n.type_id].length_storage == 0 {
                if initializer >= 0 { cg_to(p, m, f, initializer, n.type_id); if cg_diverges(p, initializer) { return; } } else { wb_i32(f.code, 0); }
                let value = cg_save(f, 0x7f); let end = cg_write_relative(p, m, f, n.type_id, cursor, value, node); cg_get(f, end); cg_set(f, cursor);
            } else if p.types[n.type_id].storage == 1 {
                if initializer >= 0 { cg_to(p, m, f, initializer, TYPE_I64); if cg_diverges(p, initializer) { return; } } else { wb_i64(f.code, 0); }
                let value = cg_save(f, 0x7e); let end = cg_write_varint(p, f, cursor, value); cg_get(f, end); cg_set(f, cursor);
            } else {
                if initializer >= 0 { cg_to(p, m, f, initializer, n.type_id); if cg_diverges(p, initializer) { return; } cg_write_value(p, m, f, n.type_id, cursor, node); }
                else { cg_get(f, cursor); wb_i32(f.code, 0); wb_i32(f.code, cg_size(p, n.type_id)); wb_fill(f.code); }
                cg_get(f, cursor); wb_i32(f.code, cg_size(p, n.type_id)); wb_byte(f.code, 0x6a); cg_set(f, cursor);
            }
        }
        field = n.next;
    }
    cg_get(f, header); cg_get(f, cursor); cg_get(f, image); wb_byte(f.code, 0x6b); wb_mem(f.code, 0x36, 2, 4);
}
fn cg_copy_byte_record(p: Program&, m: CgModule&, f: CgBody&, id: i64, destination: i64, source: i64, node: i64) {
    cg_get(f, source); wb_mem(f.code, 0x28, 2, 16); let original = cg_save(f, 0x7f);
    let end = cg_byte_field(p, m, f, id, source, -1, node);
    cg_get(f, end); cg_get(f, original); wb_byte(f.code, 0x6b); let bytes = cg_save(f, 0x7f);
    cg_get(f, bytes); cg_allocate(p, m, f, node); let image = cg_save(f, 0x7f);
    cg_get(f, image); cg_get(f, original); cg_get(f, bytes); wb_copy(f.code); cg_byte_header(f, destination, image, bytes);
}
fn cg_enum_image(p: Program&, id: i64) -> bool {
    return cg_type_kind(p, id) == TY_ENUM && (p.types[id].flags & F_VARIABLE_MODE) != 0;
}
recursive fn cg_frame_metadata(p: Program&, id: i64) -> bool {
    if cg_frame_owner(p, id) { return true; }
    if cg_record_image(p, id) { return cg_frame_metadata(p, cg_image_tail_type(p, id)); }
    if !cg_enum_image(p, id) { return false; }
    var variant = p.types[id].first;
    while variant >= 0 { if cg_frame_metadata(p, p.nodes[variant].type_id) { return true; } variant = p.nodes[variant].next; }
    return false;
}
fn cg_frame_array_bytes(p: Program&, m: CgModule&, f: CgBody&, id: i64, owner: i64, node: i64) -> i64 {
    let tail = cg_region_header(p, f, id, owner); let array = cg_frame_tail_type(p, id);
    cg_owner_read_base(p, m, f, tail, node); let base = cg_save(f, 0x7f);
    cg_owner_read_length(p, m, f, tail, node);
    if p.types[p.types[array].element].storage == 1 {
        wb_byte(f.code, 0xad); let count = cg_save(f, 0x7e); let end = cg_walk_elements(p, m, f, base, count, node);
        cg_get(f, end); cg_get(f, base); wb_byte(f.code, 0x6b);
    } else { wb_i32(f.code, cg_size(p, p.types[array].element)); wb_byte(f.code, 0x6c); }
    return cg_save(f, 0x7f);
}
recursive fn cg_rebase_enum_frame(p: Program&, f: CgBody&, id: i64, owner: i64, image: i64, bytes: i64) {
    cg_get(f, image); var load = 0x2d; if p.types[id].length_storage == 2 { load = 0x2f; }
    wb_mem(f.code, load, 0, 0); let tag = cg_save(f, 0x7f); var variant = p.types[id].first;
    while variant >= 0 {
        let payload = p.nodes[variant].type_id;
        if cg_frame_metadata(p, payload) {
            cg_get(f, tag); wb_i32(f.code, p.nodes[variant].integer); wb_byte(f.code, 0x46); cg_begin(f, 0x04, 0x40);
            cg_get(f, owner); wb_i32(f.code, p.nodes[variant].aux); wb_byte(f.code, 0x6a); let place = cg_save(f, 0x7f);
            if cg_record_image(p, payload) {
                cg_get(f, image); wb_i32(f.code, p.types[id].length_storage); wb_byte(f.code, 0x6a); let payload_image = cg_save(f, 0x7f);
                cg_get(f, bytes); wb_i32(f.code, p.types[id].length_storage); wb_byte(f.code, 0x6b); let payload_bytes = cg_save(f, 0x7f);
                cg_rebase_record_image(p, f, payload, place, payload_image, payload_bytes);
            } else {
            let tail = cg_region_header(p, f, payload, place);
            for word in [0, 16] { cg_get(f, tail); cg_get(f, image); wb_i32(f.code, p.types[id].length_storage); wb_byte(f.code, 0x6a); wb_mem(f.code, 0x36, 2, word); }
            cg_get(f, tail); cg_get(f, image); cg_get(f, bytes); wb_byte(f.code, 0x6a); wb_mem(f.code, 0x36, 2, 8);
            }
            cg_end(f);
        }
        variant = p.nodes[variant].next;
    }
}
fn cg_seed_record_image(p: Program&, m: CgModule&, f: CgBody&, id: i64, owner: i64, image: i64, limit: i64, node: i64) {
    if cg_byte_record(p, id) {
        for offset in [0, 16] { cg_get(f, owner); cg_get(f, image); wb_mem(f.code, 0x36, 2, offset); }
        cg_get(f, owner); cg_get(f, limit); wb_mem(f.code, 0x36, 2, 8); return;
    }
    let header = cg_image_tail_control(p, f, id, owner); let tail = cg_image_tail_type(p, id);
    cg_get(f, image); wb_i32(f.code, cg_record_total_prefix(p, id)); wb_byte(f.code, 0x6a); let anchor = cg_save(f, 0x7f);
    cg_get(f, header); cg_get(f, anchor); wb_mem(f.code, 0x36, 2, 16);
    cg_get(f, header); cg_get(f, limit); wb_mem(f.code, 0x36, 2, 8);
    var mode = 0;
    if cg_type_kind(p, tail) == TY_ARRAY {
        if p.types[tail].array_kind == A_LIMITED { mode = 5; }
        else if p.types[tail].length_storage == 0 { mode = 6; }
        else if p.types[tail].length_storage == 1 { mode = 1; }
        else if p.types[tail].length_storage == 2 { mode = 2; }
        else if p.types[tail].length_storage == 4 { mode = 3; }
        else { mode = 4; }
    }
    cg_get(f, header); wb_i32(f.code, mode); wb_mem(f.code, 0x36, 2, 20);
    if mode == 6 {
        let decoded = cg_read_uleb(p, m, f, anchor, node);
        cg_get(f, header); cg_get(f, decoded.cursor); cg_get(f, anchor); wb_byte(f.code, 0x6b); wb_mem(f.code, 0x36, 2, 12);
    }
    if mode == 0 { cg_get(f, header); cg_get(f, anchor); wb_mem(f.code, 0x36, 2, 0); }
}
fn cg_enum_payload(p: Program&, m: CgModule&, f: CgBody&, enum_id: i64, owner: i64, variant: i64, node: i64) -> i64 {
    cg_get(f, owner);
    if cg_enum_image(p, enum_id) { wb_mem(f.code, 0x28, 2, 0); }
    wb_i32(f.code, p.types[enum_id].length_storage); wb_byte(f.code, 0x6a); let image = cg_save(f, 0x7f);
    if cg_enum_image(p, enum_id) && variant >= 0 && p.nodes[variant].aux > 0 {
        cg_get(f, owner); wb_i32(f.code, p.nodes[variant].aux); wb_byte(f.code, 0x6a); let payload = cg_save(f, 0x7f);
        if cg_frame_metadata(p, p.nodes[variant].type_id) { return payload; }
        cg_get(f, owner); wb_mem(f.code, 0x28, 2, 8); let limit = cg_save(f, 0x7f);
        cg_seed_record_image(p, m, f, p.nodes[variant].type_id, payload, image, limit, node); return payload;
    }
    return image;
}
recursive fn cg_enum_image_bytes(p: Program&, m: CgModule&, f: CgBody&, id: i64, owner: i64, node: i64) -> i64 {
    cg_get(f, owner); wb_mem(f.code, 0x28, 2, 0); var load = 0x2d; if p.types[id].length_storage == 2 { load = 0x2f; }
    wb_mem(f.code, load, 0, 0); let tag = cg_save(f, 0x7f); let result = cg_local(f, 0x7f); let done = cg_begin(f, 0x02, 0x40);
    var variant = p.types[id].first;
    while variant >= 0 {
        cg_get(f, tag); wb_i32(f.code, p.nodes[variant].integer); wb_byte(f.code, 0x46); cg_begin(f, 0x04, 0x40);
        let payload = p.nodes[variant].type_id;
        if cg_frame_owner(p, payload) {
            let place = cg_enum_payload(p, m, f, id, owner, variant, node); let bytes = cg_frame_array_bytes(p, m, f, payload, place, node);
            cg_get(f, bytes); wb_i32(f.code, p.types[id].length_storage); wb_byte(f.code, 0x6a);
        } else if cg_byte_record(p, payload) {
            let place = cg_enum_payload(p, m, f, id, owner, variant, node); let end = cg_byte_field(p, m, f, payload, place, -1, node);
            cg_get(f, end); cg_get(f, owner); wb_mem(f.code, 0x28, 2, 0); wb_byte(f.code, 0x6b);
        } else if cg_record_image(p, payload) {
            let place = cg_enum_payload(p, m, f, id, owner, variant, node); let bytes = cg_record_image_bytes(p, m, f, payload, place, node);
            cg_get(f, bytes); wb_i32(f.code, p.types[id].length_storage); wb_byte(f.code, 0x6a);
        } else { var bytes = 0; if p.nodes[variant].first >= 0 { bytes = cg_size(p, payload); } wb_i32(f.code, bytes + p.types[id].length_storage); }
        cg_set(f, result); cg_branch(p, f, done, false); cg_end(f); variant = p.nodes[variant].next;
    }
    cg_abort(p, m, f, node, "invalid enum tag"); cg_end(f);
    if m.regions_enabled {
        cg_get(f, owner); wb_mem(f.code, 0x28, 2, 0); wb_byte(f.code, 0xad); cg_get(f, result); wb_byte(f.code, 0xad); wb_byte(f.code, 0x7c); let end = cg_save(f, 0x7e);
        cg_get(f, end); cg_get(f, owner); wb_mem(f.code, 0x28, 2, 8); wb_byte(f.code, 0xad); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "enum image exceeds data region");
        cg_get(f, end); wb_byte(f.code, 0xa7); let top = cg_save(f, 0x7f); cg_ensure_memory(p, m, f, top, node);
    }
    return result;
}
recursive fn cg_enum_variant_image(p: Program&, m: CgModule&, f: CgBody&, id: i64, destination: i64, variant: i64, source: i64, node: i64) {
    let payload = p.nodes[variant].type_id; var original = source; var payload_bytes = -1;
    if cg_frame_owner(p, payload) {
        let tail = cg_region_header(p, f, payload, source); cg_owner_read_base(p, m, f, tail, node); original = cg_save(f, 0x7f);
        payload_bytes = cg_frame_array_bytes(p, m, f, payload, source, node);
        cg_get(f, destination); wb_i32(f.code, p.nodes[variant].aux); wb_byte(f.code, 0x6a); let place = cg_save(f, 0x7f);
        cg_get(f, place); cg_get(f, source); wb_i32(f.code, cg_size(p, payload)); wb_copy(f.code);
    } else if cg_byte_record(p, payload) {
        cg_get(f, source); wb_mem(f.code, 0x28, 2, 16); original = cg_save(f, 0x7f); let end = cg_byte_field(p, m, f, payload, source, -1, node);
        cg_get(f, end); cg_get(f, original); wb_byte(f.code, 0x6b); payload_bytes = cg_save(f, 0x7f);
    } else if cg_record_image(p, payload) {
        original = cg_record_image_base(p, m, f, payload, source, node); payload_bytes = cg_record_image_bytes(p, m, f, payload, source, node);
        if cg_frame_metadata(p, payload) {
            cg_get(f, destination); wb_i32(f.code, p.nodes[variant].aux); wb_byte(f.code, 0x6a); let place = cg_save(f, 0x7f);
            cg_get(f, place); cg_get(f, source); wb_i32(f.code, cg_size(p, payload)); wb_copy(f.code);
        }
    }
    else { var bytes = 0; if p.nodes[variant].first >= 0 { bytes = cg_size(p, payload); } wb_i32(f.code, bytes); payload_bytes = cg_save(f, 0x7f); }
    cg_get(f, payload_bytes); wb_i32(f.code, p.types[id].length_storage); wb_byte(f.code, 0x6a); let bytes = cg_save(f, 0x7f);
    cg_get(f, bytes); cg_allocate(p, m, f, node); let image = cg_save(f, 0x7f);
    cg_get(f, image); wb_i32(f.code, p.nodes[variant].integer); var store = 0x3a; if p.types[id].length_storage == 2 { store = 0x3b; } wb_mem(f.code, store, 0, 0);
    cg_get(f, image); wb_i32(f.code, p.types[id].length_storage); wb_byte(f.code, 0x6a); cg_get(f, original); cg_get(f, payload_bytes); wb_copy(f.code);
    cg_byte_header(f, destination, image, bytes);
    if cg_frame_metadata(p, payload) { cg_rebase_enum_frame(p, f, id, destination, image, bytes); }
}
recursive fn cg_enum_from_value(p: Program&, m: CgModule&, f: CgBody&, id: i64, destination: i64, from: i64, source: i64, node: i64) {
    if cg_type_kind(p, from) == TY_STRUCT { cg_enum_variant_image(p, m, f, id, destination, p.types[from].declaration, source, node); return; }
    if cg_enum_image(p, from) && !cg_frame_metadata(p, from) {
        let bytes = cg_enum_image_bytes(p, m, f, from, source, node);
        cg_get(f, source); wb_mem(f.code, 0x28, 2, 0); let original = cg_save(f, 0x7f);
        cg_get(f, bytes); cg_allocate(p, m, f, node); let image = cg_save(f, 0x7f);
        cg_get(f, image); cg_get(f, original); cg_get(f, bytes); wb_copy(f.code); cg_byte_header(f, destination, image, bytes); return;
    }
    cg_get(f, source); if cg_enum_image(p, from) { wb_mem(f.code, 0x28, 2, 0); }
    var load = 0x2d; if p.types[from].length_storage == 2 { load = 0x2f; } wb_mem(f.code, load, 0, 0); let tag = cg_save(f, 0x7f);
    let done = cg_begin(f, 0x02, 0x40); var variant = p.types[id].first;
    while variant >= 0 {
        cg_get(f, tag); wb_i32(f.code, p.nodes[variant].integer); wb_byte(f.code, 0x46); cg_begin(f, 0x04, 0x40);
        let payload = cg_enum_payload(p, m, f, from, source, variant, node);
        cg_enum_variant_image(p, m, f, id, destination, variant, payload, node); cg_branch(p, f, done, false); cg_end(f); variant = p.nodes[variant].next;
    }
    cg_abort(p, m, f, node, "invalid enum tag"); cg_end(f);
}
fn cg_dispatch_invoke(p: Program&, m: CgModule&, f: CgBody&, node: i64, symbol: i64, arguments: i64, argument_count: i64, dispatch: i64, enum_id: i64, enum_value: i64, payload_id: i64) {
    let function = p.symbols[symbol].node; var param = p.nodes[function].first; var ordinal = 0;
    while param >= 0 && ordinal < argument_count {
        let id = p.nodes[param].type_id;
        if ordinal == dispatch {
            let variant = p.types[payload_id].declaration;
            let payload = cg_enum_payload(p, m, f, enum_id, enum_value, variant, node);
            if cg_type_kind(p, id) == TY_REF { cg_get(f, payload); }
            else {
                let snapshot = cg_temporary(p, f, id); cg_copy(p, m, f, id, snapshot, payload, node); cg_get(f, snapshot);
            }
        } else {
            let saved_type = f.work[arguments + ordinal * 2]; let saved = f.work[arguments + ordinal * 2 + 1];
            cg_get(f, saved); cg_convert(p, m, f, saved_type, id, node);
        }
        param = p.nodes[param].next; ordinal++;
    }
    if param >= 0 || ordinal != argument_count { cg_fail(p, node, "wasm: dispatch case argument arity mismatch"); return; }
    for capture in m.captures { if capture.function == function { cg_symbol_address(p, m, f, capture.symbol, node); } }
    var results: i64[>..] = []; cg_function_results(p, function, results);
    for id, ordinal in results {
        if cg_aggregate(p, id) {
            let requested = cg_receiving(f, -2 - node, ordinal);
            if m.regions_enabled && cg_region_value(p, id) {
                var receiving = -1;
                if results.len == 1 && f.active_node == node && f.active_destination >= 0 && cg_direct_array_call(p, f, node, f.active_destination) { receiving = f.active_destination; }
                else { receiving = cg_temporary_destination(p, m, f, id, node); }
                cg_get(f, f.construction_destinations[receiving].header);
            } else if requested >= 0 && f.construction_destinations[requested].type_id == id && cg_fixed_relative(p, id) { cg_get(f, f.construction_destinations[requested].header); }
            else { cg_get(f, cg_temporary(p, f, id)); }
        }
    }
    let target = cg_function(m, symbol);
    if target < 0 { cg_fail(p, node, "wasm: dispatch specialization has no emitted body"); return; }
    cg_region_call(m, f, target, node); wb_op(f.code, 0x10, m.functions[target].index); cg_effect_check(p, m, f, results);
    if results.len == 1 && results[0] != p.nodes[node].type_id && !cg_diverges(p, node) { cg_convert(p, m, f, results[0], p.nodes[node].type_id, node); }
}
recursive fn cg_dispatch(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n = p.nodes[node]; let mark = f.work.len; var arm = n.third; var by_reference = false;
    while arm >= 0 {
        var param = p.nodes[p.symbols[p.nodes[arm].symbol].node].first; var ordinal = 0;
        while param >= 0 && ordinal < n.aux { param = p.nodes[param].next; ordinal++; }
        if param >= 0 && cg_type_kind(p, p.nodes[param].type_id) == TY_REF { by_reference = true; }
        arm = p.nodes[arm].next;
    }
    var arg = n.first; var param = p.nodes[p.symbols[n.symbol].node].first; var ordinal = 0; var enum_id = -1; var enum_value = -1;
    while arg >= 0 && param >= 0 {
        var id = p.nodes[param].type_id; var saved = -1;
        if ordinal == n.aux {
            id = p.nodes[arg].type_id; cg_expr(p, m, f, arg);
            if cg_type_kind(p, id) == TY_REF { id = p.types[id].element; cg_load(p, m, f, id, 0); }
            enum_id = id; saved = cg_save(f, 0x7f);
            if !by_reference { let snapshot = cg_temporary(p, f, id); cg_copy(p, m, f, id, snapshot, saved, arg); saved = snapshot; }
            enum_value = saved;
        } else {
            cg_to(p, m, f, arg, id); saved = cg_save(f, cg_wasm_type(p, id));
            if cg_aggregate(p, id) { let snapshot = cg_temporary(p, f, id); cg_copy(p, m, f, id, snapshot, saved, arg); saved = snapshot; }
        }
        f.work.push(id); f.work.push(saved); arg = p.nodes[arg].next; param = p.nodes[param].next; ordinal++;
    }
    if arg >= 0 || param >= 0 || enum_value < 0 || cg_type_kind(p, enum_id) != TY_ENUM {
        cg_fail(p, node, "wasm: dispatch requires one checked enum argument"); f.work.resize(mark); return;
    }
    cg_get(f, enum_value); if (p.types[enum_id].flags & F_VARIABLE_MODE) != 0 { wb_mem(f.code, 0x28, 2, 0); }
    var load = 0x2d; if p.types[enum_id].length_storage == 2 { load = 0x2f; }
    wb_mem(f.code, load, 0, 0); let tag = cg_save(f, 0x7f);
    let result = cg_control_slots(p, f, n.type_id, node); let count = cg_result_count(p, n.type_id); let done = cg_begin(f, 0x02, 0x40); arm = n.third;
    while arm >= 0 {
        let a = p.nodes[arm]; cg_get(f, tag); wb_i32(f.code, a.integer); wb_byte(f.code, 0x46); cg_begin(f, 0x04, 0x40);
        cg_dispatch_invoke(p, m, f, node, a.symbol, mark, ordinal, n.aux, enum_id, enum_value, a.type_id);
        var at = count; while at > 0 { at--; cg_set(f, result + at); }
        cg_branch(p, f, done, false); cg_end(f); arm = a.next;
    }
    cg_abort(p, m, f, node, "invalid enum dispatch tag"); cg_end(f); cg_control_get(p, f, n.type_id, result); f.work.resize(mark);
}
recursive fn cg_record_image(p: Program&, id: i64) -> bool {
    if cg_type_kind(p, id) != TY_STRUCT || cg_byte_record(p, id) || p.types[id].tail < 0 { return false; }
    let field = p.types[id].tail; let tail = p.nodes[field].type_id;
    if cg_type_kind(p, tail) == TY_ARRAY { return p.types[tail].array_kind == A_VAR || p.types[tail].array_kind == A_LIMITED && p.types[tail].count < 0; }
    return cg_enum_image(p, tail) || cg_record_image(p, tail);
}
fn cg_image_tail_type(p: Program&, id: i64) -> i64 {
    var current = id;
    while cg_record_image(p, current) { current = p.nodes[p.types[current].tail].type_id; }
    return current;
}
fn cg_image_tail_control(p: Program&, f: CgBody&, id: i64, owner: i64) -> i64 {
    var current = id; var offset = 0;
    while cg_record_image(p, current) {
        let field = p.types[current].tail; offset += p.nodes[field].integer; current = p.nodes[field].type_id;
    }
    cg_get(f, owner); if offset != 0 { wb_i32(f.code, offset); wb_byte(f.code, 0x6a); }
    return cg_save(f, 0x7f);
}
fn cg_record_prefix(p: Program&, id: i64) -> i64 {
    var bytes = 0; var field = p.types[id].first;
    while field >= 0 && field != p.types[id].tail {
        if (p.nodes[field].flags & F_PAD) != 0 { bytes += p.nodes[field].aux; }
        else { bytes += cg_size(p, p.nodes[field].type_id); }
        field = p.nodes[field].next;
    }
    return bytes;
}
fn cg_record_total_prefix(p: Program&, id: i64) -> i64 {
    var bytes = 0; var current = id;
    while cg_record_image(p, current) { bytes += cg_record_prefix(p, current); current = p.nodes[p.types[current].tail].type_id; }
    return bytes;
}
recursive fn cg_record_image_base(p: Program&, m: CgModule&, f: CgBody&, id: i64, owner: i64, node: i64) -> i64 {
    if cg_frame_metadata(p, id) { cg_pack_record_image(p, m, f, id, owner, node); }
    let header = cg_image_tail_control(p, f, id, owner); cg_get(f, header); wb_mem(f.code, 0x28, 2, 16);
    wb_i32(f.code, cg_record_total_prefix(p, id)); wb_byte(f.code, 0x6b); return cg_save(f, 0x7f);
}
fn cg_array_image_bytes(p: Program&, m: CgModule&, f: CgBody&, id: i64, header: i64, node: i64) -> i64 {
    cg_get(f, header); wb_mem(f.code, 0x28, 2, 16); let image = cg_save(f, 0x7f);
    cg_owner_read_base(p, m, f, header, node); let elements = cg_save(f, 0x7f);
    let element = p.types[id].element;
    if p.types[element].storage == 1 {
        cg_owner_read_length(p, m, f, header, node); wb_byte(f.code, 0xad); let count = cg_save(f, 0x7e);
        let end = cg_walk_elements(p, m, f, elements, count, node); cg_get(f, end);
    } else {
        cg_get(f, elements);
        if p.types[id].array_kind == A_LIMITED { cg_owner_read_capacity(p, m, f, header); }
        else { cg_owner_read_length(p, m, f, header, node); }
        wb_i32(f.code, cg_size(p, element)); wb_byte(f.code, 0x6c); wb_byte(f.code, 0x6a);
    }
    cg_get(f, image); wb_byte(f.code, 0x6b); return cg_save(f, 0x7f);
}
recursive fn cg_record_image_bytes(p: Program&, m: CgModule&, f: CgBody&, id: i64, owner: i64, node: i64) -> i64 {
    let header = cg_image_tail_control(p, f, id, owner); let tail = cg_image_tail_type(p, id);
    var bytes = -1;
    if cg_enum_image(p, tail) { bytes = cg_enum_image_bytes(p, m, f, tail, header, node); }
    else { bytes = cg_array_image_bytes(p, m, f, tail, header, node); }
    cg_get(f, bytes); wb_i32(f.code, cg_record_total_prefix(p, id)); wb_byte(f.code, 0x6a); return cg_save(f, 0x7f);
}
recursive fn cg_rebase_record_image(p: Program&, f: CgBody&, id: i64, owner: i64, image: i64, bytes: i64) {
    let header = cg_image_tail_control(p, f, id, owner);
    cg_get(f, header); wb_mem(f.code, 0x28, 2, 16); let old_tail = cg_save(f, 0x7f);
    cg_get(f, image); wb_i32(f.code, cg_record_total_prefix(p, id)); wb_byte(f.code, 0x6a); let new_tail = cg_save(f, 0x7f);
    cg_get(f, header); cg_get(f, header); wb_mem(f.code, 0x28, 2, 0); cg_get(f, old_tail); wb_byte(f.code, 0x6b); cg_get(f, new_tail); wb_byte(f.code, 0x6a); wb_mem(f.code, 0x36, 2, 0);
    cg_get(f, header); cg_get(f, new_tail); wb_mem(f.code, 0x36, 2, 16);
    cg_get(f, header); cg_get(f, image); cg_get(f, bytes); wb_byte(f.code, 0x6a); wb_mem(f.code, 0x36, 2, 8);
    let tail = cg_image_tail_type(p, id);
    if cg_frame_metadata(p, tail) {
        cg_get(f, bytes); wb_i32(f.code, cg_record_total_prefix(p, id)); wb_byte(f.code, 0x6b); let tail_bytes = cg_save(f, 0x7f);
        cg_rebase_enum_frame(p, f, tail, header, new_tail, tail_bytes);
    }
}
recursive fn cg_pack_record_image(p: Program&, m: CgModule&, f: CgBody&, id: i64, owner: i64, node: i64) {
    let tail_field = p.types[id].tail; let tail_id = p.nodes[tail_field].type_id;
    cg_get(f, owner); wb_i32(f.code, p.nodes[tail_field].integer); wb_byte(f.code, 0x6a); let tail = cg_save(f, 0x7f);
    var tail_image = -1; var tail_bytes = -1;
    if cg_record_image(p, tail_id) {
        tail_image = cg_record_image_base(p, m, f, tail_id, tail, node); tail_bytes = cg_record_image_bytes(p, m, f, tail_id, tail, node);
    } else {
        cg_get(f, tail); wb_mem(f.code, 0x28, 2, 16); tail_image = cg_save(f, 0x7f);
        if cg_enum_image(p, tail_id) { tail_bytes = cg_enum_image_bytes(p, m, f, tail_id, tail, node); }
        else { tail_bytes = cg_array_image_bytes(p, m, f, tail_id, tail, node); }
    }
    let prefix = cg_record_prefix(p, id); cg_get(f, tail_bytes); wb_i32(f.code, prefix); wb_byte(f.code, 0x6a); let bytes = cg_save(f, 0x7f);
    cg_get(f, bytes); cg_allocate(p, m, f, node); let image = cg_save(f, 0x7f);
    var field = p.types[id].first; var offset = 0;
    while field >= 0 && field != tail_field {
        let n = p.nodes[field];
        cg_get(f, image); wb_i32(f.code, offset); wb_byte(f.code, 0x6a);
        if (n.flags & F_PAD) != 0 { wb_i32(f.code, 0); wb_i32(f.code, n.aux); wb_fill(f.code); offset += n.aux; }
        else {
            cg_get(f, owner); wb_i32(f.code, n.integer); wb_byte(f.code, 0x6a); wb_i32(f.code, cg_size(p, n.type_id)); wb_copy(f.code); offset += cg_size(p, n.type_id);
        }
        field = n.next;
    }
    cg_get(f, image); wb_i32(f.code, prefix); wb_byte(f.code, 0x6a); cg_get(f, tail_image); cg_get(f, tail_bytes); wb_copy(f.code);
    cg_rebase_record_image(p, f, id, owner, image, bytes);
}
fn cg_copy_record_image(p: Program&, m: CgModule&, f: CgBody&, id: i64, destination: i64, source: i64, node: i64) {
    let original = cg_record_image_base(p, m, f, id, source, node); let bytes = cg_record_image_bytes(p, m, f, id, source, node);
    cg_get(f, bytes); cg_allocate(p, m, f, node); let image = cg_save(f, 0x7f);
    cg_get(f, image); cg_get(f, original); cg_get(f, bytes); wb_copy(f.code);
    cg_get(f, destination); cg_get(f, source); wb_i32(f.code, cg_size(p, id)); wb_copy(f.code);
    cg_rebase_record_image(p, f, id, destination, image, bytes);
}
recursive fn cg_default_storage(p: Program&, m: CgModule&, f: CgBody&, id: i64, destination: i64, node: i64) {
    cg_get(f, destination); wb_i32(f.code, 0); wb_i32(f.code, cg_size(p, id)); wb_fill(f.code);
    if cg_byte_record(p, id) { cg_construct_byte_record(p, m, f, id, destination, -1); return; }
    if cg_owner(p, id) {
        wb_i32(f.code, 0); let count = cg_save(f, 0x7f); cg_owner_image(p, m, f, id, destination, count, count, node); return;
    }
    if cg_type_kind(p, id) == TY_STRUCT {
        var field = p.types[id].first;
        while field >= 0 {
            let n = p.nodes[field];
            if (n.flags & F_PAD) == 0 && cg_aggregate(p, n.type_id) {
                cg_get(f, destination); wb_i32(f.code, n.integer); wb_byte(f.code, 0x6a); let address = cg_save(f, 0x7f); cg_default_storage(p, m, f, n.type_id, address, node);
            }
            field = n.next;
        }
        if cg_record_image(p, id) { cg_pack_record_image(p, m, f, id, destination, node); }
    }
}
fn cg_copy_runtime_limited(p: Program&, m: CgModule&, f: CgBody&, id: i64, destination: i64, source: i64, node: i64) {
    cg_owner_read_length(p, m, f, source, node); let count = cg_save(f, 0x7f);
    cg_owner_read_capacity(p, m, f, source); let capacity = cg_save(f, 0x7f);
    cg_get(f, count); cg_get(f, capacity); wb_byte(f.code, 0x4b); cg_trap_if(p, m, f, node, "array image length exceeds capacity");
    let target = cg_owner_image(p, m, f, id, destination, count, capacity, node);
    cg_get(f, target); cg_owner_read_base(p, m, f, source, node);
    cg_get(f, capacity); wb_i32(f.code, cg_size(p, p.types[id].element)); wb_byte(f.code, 0x6c); wb_copy(f.code);
    if m.regions_enabled && !f.scratch { cg_get(f, target); cg_get(f, capacity); wb_i32(f.code, cg_size(p, p.types[id].element)); wb_byte(f.code, 0x6c); wb_byte(f.code, 0x6a); let top = cg_save(f, 0x7f); cg_region_publish(f, destination, top); }
}

recursive fn cg_has_owner(p: Program&, id: i64) -> bool {
    if cg_owner(p, id) || cg_byte_record(p, id) || cg_record_image(p, id) { return true; }
    if cg_type_kind(p, id) == TY_ENUM { return (p.types[id].flags & F_VARIABLE_MODE) != 0; }
    if cg_type_kind(p, id) != TY_STRUCT { return false; }
    var field = p.types[id].first;
    while field >= 0 { if (p.nodes[field].flags & F_PAD) == 0 && cg_has_owner(p, p.nodes[field].type_id) { return true; } field = p.nodes[field].next; }
    return false;
}
fn cg_named_owner(p: Program&, f: CgBody&, node: i64, id: i64) -> bool {
    if p.nodes[node].kind != N_NAME || p.nodes[node].symbol < 0 || !cg_has_owner(p, id) { return false; }
    let symbol = p.symbols[p.nodes[node].symbol];
    return symbol.owner == f.function && (symbol.flags & (S_GLOBAL | S_PARAMETER)) == 0;
}
fn cg_resolve_pointer(m: CgModule&, f: CgBody&) { if m.resolver >= 0 { wb_op(f.code, 0x10, m.resolver); } }
fn cg_resolve_location(m: CgModule&, f: CgBody&, location: i64) -> i64 {
    if m.resolver < 0 { return location; }
    cg_get(f, location); cg_resolve_pointer(m, f); return cg_save(f, 0x7f);
}
fn cg_forward_span(p: Program&, m: CgModule&, f: CgBody&, original: i64, bytes: i64, replacement: i64) {
    if m.resolver < 0 { return; }
    cg_get(f, bytes); cg_begin(f, 0x04, 0x40);
    wb_i32(f.code, 16); cg_allocate(p, m, f, -1); let entry = cg_save(f, 0x7f);
    cg_get(f, entry); wb_op(f.code, 0x23, 5); wb_mem(f.code, 0x36, 2, 0);
    cg_get(f, entry); cg_get(f, original); wb_mem(f.code, 0x36, 2, 4);
    cg_get(f, entry); cg_get(f, original); cg_get(f, bytes); wb_byte(f.code, 0x6a); wb_mem(f.code, 0x36, 2, 8);
    cg_get(f, entry); cg_get(f, replacement); wb_mem(f.code, 0x36, 2, 12);
    cg_get(f, entry); wb_op(f.code, 0x24, 5);
    cg_get(f, original); wb_op(f.code, 0x23, 7); wb_byte(f.code, 0x49); cg_begin(f, 0x04, 0x40);
    cg_get(f, original); wb_op(f.code, 0x24, 7); cg_end(f);
    cg_get(f, original); cg_get(f, bytes); wb_byte(f.code, 0x6a); let end = cg_save(f, 0x7f);
    cg_get(f, end); wb_op(f.code, 0x23, 6); wb_byte(f.code, 0x4b); cg_begin(f, 0x04, 0x40);
    cg_get(f, end); wb_op(f.code, 0x24, 6); cg_end(f); cg_end(f);
}
fn cg_resolver_body(out: u8[>..]&) {
    // (address:i32)->i32. Forwarded spans never overlap metadata or newer
    // allocations. Restarting the scan follows transitive moves in order.
    wb_u(out, 1); wb_u(out, 1); wb_byte(out, 0x7f);
    // Bounds include every published move. Values outside this interval
    // cannot belong to any forwarding span, including activation addresses.
    wb_op(out, 0x20, 0); wb_op(out, 0x23, 7); wb_byte(out, 0x49);
    wb_op(out, 0x20, 0); wb_op(out, 0x23, 6); wb_byte(out, 0x4f); wb_byte(out, 0x72);
    wb_byte(out, 0x04); wb_byte(out, 0x40); wb_op(out, 0x20, 0); wb_byte(out, 0x0f); wb_byte(out, 0x0b);
    wb_op(out, 0x23, 5); wb_op(out, 0x21, 1);
    wb_byte(out, 0x02); wb_byte(out, 0x40); wb_byte(out, 0x03); wb_byte(out, 0x40);
    wb_op(out, 0x20, 1); wb_byte(out, 0x45); wb_op(out, 0x0d, 1);
    wb_op(out, 0x20, 0); wb_op(out, 0x20, 1); wb_mem(out, 0x28, 2, 4); wb_byte(out, 0x4f);
    wb_op(out, 0x20, 0); wb_op(out, 0x20, 1); wb_mem(out, 0x28, 2, 8); wb_byte(out, 0x49); wb_byte(out, 0x71);
    wb_byte(out, 0x04); wb_byte(out, 0x40);
    wb_op(out, 0x20, 0); wb_op(out, 0x20, 1); wb_mem(out, 0x28, 2, 4); wb_byte(out, 0x6b);
    wb_op(out, 0x20, 1); wb_mem(out, 0x28, 2, 12); wb_byte(out, 0x6a); wb_op(out, 0x21, 0);
    wb_op(out, 0x23, 5); wb_op(out, 0x21, 1); wb_byte(out, 0x05);
    wb_op(out, 0x20, 1); wb_mem(out, 0x28, 2, 0); wb_op(out, 0x21, 1);
    wb_byte(out, 0x0b); wb_op(out, 0x0c, 0); wb_byte(out, 0x0b); wb_byte(out, 0x0b);
    wb_op(out, 0x20, 0); wb_byte(out, 0x0b);
}
