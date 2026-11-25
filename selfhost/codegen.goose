import model;
import checker_rendering;
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
    closure_signature: i64 = -1, thunk: i64 = -1, table_index: i64 = -1,
    capture_first: i64 = 0, capture_count: i64 = 0, arena_local: bool = false, elements: bool = false,
    header_pure: bool = false, sroa_return: i32 = 0,
}
// Positions in functions, before adding the import count.
struct CgFunctionIndex { first: i32 = -1, elements: i32 = -1 }
struct CgCapture { function: i64, symbol: i64 }
struct CgText { data: i64, length: i64 }
struct CgSegment { address: i64, start: i64, count: i64 }
struct CgAbortHelper { address: i64, length: i64 }
// A private reference parameter can stay in its incoming Wasm local. Record
// its initial store and direct slot loads until body emission has revealed
// whether any operation requires the address of the parameter cell itself.
struct CgParameterUse { symbol: i64, start: i64, end: i64, initial: bool = false }
struct CgModule {
    parameter_uses: CgParameterUse[>..]&,
    functions: CgFunction[>..]&, functions_by_symbol: CgFunctionIndex[>..]&, captures: CgCapture[>..]&, imports: CgImport[>..]&,
    signatures: CgSignature[>..]&, signature_bytes: u8[>..]&, signature_slots: i64[>..]&, signature_scratch: u8[>..]&,
    segments: CgSegment[>..]&, segment_slots: i64[>..]&, data: u8[>..]&, globals: i64[>..]&,
    symbol_owners: SymbolOwners,
    global_regions: i64[>..]&, region_functions: RegionFunction[>..]&, region_calls: RegionCall[>..]&,
    region_memo: u8[>..]&, abort_helpers: CgAbortHelper[>..]&,
    next_data: i64 = 1024, stack_limit: i64 = 0, thunk_count: i64 = 0, abort_base: i64 = -1,
    region_count: i64 = 0, global_region_count: i64 = 0, regions_enabled: bool = false,
    nonlocal_returns: bool = false, ordinary_owners: bool = false, safe_refs: bool = false, maps_headers: bool = false,
    region_table_address: i64 = 0, host_reserve: i64 = -1, host_reserve_type: i64 = -1,
    start: i64 = -1, allocator: i64 = -1, float_wrap: i64 = -1, scalar: bool = false, resolver: i64 = -1, forward_helper: i64 = -1, header_helper: i64 = -1, prefix_helper: i64 = -1, pool_global: i64 = -1,
    span_scratch: i64 = -1, pool_state_fn: i64 = -1,
    spans_newnode: i64 = -1, spans_fix: i64 = -1, spans_delete: i64 = -1, spans_insert: i64 = -1,
    spans_near: i64 = -1, spans_release: i64 = -1, spans_alloc: i64 = -1, spans_free: i64 = -1, spans_regrow: i64 = -1,
    owner_view: i64 = -1, update_length: i64 = -1,
    format_f32: i64 = -1, format_f64: i64 = -1, raw_append: i64 = -1, raw_append_type: i64 = -1,
}
// defers: the height of the defer stack the exit runs back down to (§6.6).
struct CgExit { label: i64, again: i64 = -1, node: i64 = -1, result: i64 = -1, type_id: i64 = 0, scratch: i64 = -1, regions: i64 = -1, publication: i64 = -1, defers: i64 = 0 }
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
struct CgSlot { local: i64 = -1, value: bool = false, incoming: i64 = -1, address_used: bool = false, sroa_count: i32 = 0 }
struct CgFrameAddress { local: i64, offset: i64 }
struct CgHoist {
    sym: i32 = -1, field: i32 = -1, ptr_local: i32 = -1, len_local: i32 = -1,
    sample_node: i32 = -1, target_type: i32 = -1,
    flags: u16 = 0, uses: u16 = 0,
}
let CG_HOIST_SLICE: u16 = 1;
let CG_HOIST_LEN: u16 = 2;
let CG_HOIST_ALIVE: u16 = 4;
struct CgBody {
    // User and start functions use wb_reuse_locals. Scalar and hand-written
    // helper bodies use their own encoding paths.
    events: WbEvent[>..]&, record_events: bool = false,
    code: u8[>..]&, locals: i64[>..]&, slots: CgSlot[>..]&, addresses: CgFrameAddress[>..]&,
    labels: i64[>..]&, exits: CgExit[>..]&, results: i64[>..]&, destinations: i64[>..]&, work: i64[>..]&, raw_slots: i64[>..]&, sequences: CgSequence[>..]&,
    constructions: CgConstruction[>..]&, construction_destinations: CgDestination[>..]&, receiving: CgReceiving[>..]&,
    hoists: CgHoist[>..]&,
    function: i64 = -1, function_index: i64 = -1, params: i64 = 0, serial: i64 = 0,
    region_live: i64 = 0, region_peak: i64 = 0, acquisitions: i64 = 0, publishes: bool = false, region_mark: i64 = -1, publication_mark: i64 = -1,
    frame: i64 = -1, frame_bytes: i64 = 0, frame_used: bool = false, effect: i64 = 0, effect_metadata: i64 = -1, done: i64 = -1, frame_free: bool = false,
    direct_return: bool = false, direct_node: i64 = -1, direct_dest: i64 = -1,
    sroa_return: i64 = 0, sroa_call_node: i64 = -1, sroa_call_base: i64 = -1,
    // diagnostic_line: a helper's line parameter. at: a located function's
    // caller's line (mark_located_functions), the host's abort taking a line.
    diagnostic_line: i64 = -1, at: i64 = -1, heap_mark: i64 = -1, forward_mark: i64 = -1, scratch: bool = false, elements: bool = false, raw_node: i64 = -1, active_node: i64 = -1, active_destination: i64 = -1,
    // The `defer` statements of the blocks being emitted, in registration
    // order (§6.6): an exit emits the bodies above its height, latest first.
    defers: i64[>..]&, running_defers: i64 = 0,
    // Where a call's effect check sends a nonlocal return in flight while
    // defer bodies are registered: the landing that runs them (cg_block_into).
    effect_landing: i64 = -1,
}
struct CgEmitScratch {
    events: WbEvent[>..]&,
    code: u8[>..]&, body: u8[>..]&, locals: i64[>..]&, addresses: CgFrameAddress[>..]&,
    labels: i64[>..]&, exits: CgExit[>..]&, results: i64[>..]&, destinations: i64[>..]&,
    work: i64[>..]&, raw_slots: i64[>..]&, sequences: CgSequence[>..]&,
    constructions: CgConstruction[>..]&, construction_destinations: CgDestination[>..]&,
    receiving: CgReceiving[>..]&, defers: i64[>..]&, hoists: CgHoist[>..]&,
    thunk_code: u8[>..]&, thunk_locals: i64[>..]&, thunk_results: i64[>..]&,
    reuse: WbReuseScratch,
}
struct CgReserved { cursor: i64, limit: i64, top: i64 }

fn cg_align(value: i64, alignment: i64) -> i64 {
    if alignment <= 1 { return value; }
    return (value + alignment - 1) & (0 - alignment);
}
fn cg_fail(p: Program&, node: i64, message: const u8[:]) {
    var token = -1;
    if node >= 0 && node < p.nodes.len { token = p.nodes[node].token; }
    diagnose(p, token, message);
}
inline fn cg_type_kind(p: Program&, id: i64) -> i64 {
    if id < 0 || id >= p.types.len { return TY_UNKNOWN; }
    return p.types[id].kind;
}
inline fn cg_aggregate(p: Program&, id: i64) -> bool {
    if id < 13 { return false; }
    let kind = cg_type_kind(p, id);
    return kind == TY_ARRAY || kind == TY_STRUCT || kind == TY_ENUM;
}
inline fn cg_owner(p: Program&, id: i64) -> bool {
    if id < 13 || cg_type_kind(p, id) != TY_ARRAY { return false; }
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
    if kind == TY_SLICE { return ws(); }
    if kind == TY_INT && p.types[id].count == 64 || kind == TY_FN { return 0x7e; }
    if kind == TY_FLOAT && p.types[id].count == 32 { return 0x7d; }
    if kind == TY_FLOAT { return 0x7c; }
    if kind == TY_UNKNOWN || kind == TY_GENERIC || kind == TY_NAME || kind == TY_TUPLE { return 0; }
    if kind == TY_REF || kind == TY_ARRAY || kind == TY_STRUCT || kind == TY_ENUM { return wa(); }
    return 0x7f;
}
fn cg_size(p: Program&, id: i64) -> i64 {
    if id < 0 || id >= p.types.len { return 0; }
    if cg_owner(p, id) { return wc_bytes(); }
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
    if cg_aggregate(p, id) { wa_add(out, offset); return true; }
    let kind = cg_type_kind(p, id);
    if kind == TY_INT {
        let bits = p.types[id].count;
        if bits == 8 { var op = 0x2c; if cg_unsigned(p, id) { op = 0x2d; } wb_mem(out, op, 0, offset); return true; }
        if bits == 16 { var op = 0x2e; if cg_unsigned(p, id) { op = 0x2f; } wb_mem(out, op, 1, offset); return true; }
    }
    let w = cg_wasm_type(p, id);
    if kind == TY_BOOL { wb_mem(out, 0x2d, 0, offset); return true; }
    if w == 0x7b { ws_load(out, offset); return true; }
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
    if w == 0x7b { ws_store(out, offset); return true; }
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
// An event carries the original byte offset, operand and opcode. Locals in
// the incoming signature do not take part in slot reuse.
inline fn cg_record(f: CgBody&, opcode: i64, operand: i64) {
    if f.record_events { f.events.push(WbEvent { start: f.code.len as i32, operand: operand as i32, opcode: opcode as u8 }); }
}
inline fn cg_control(f: CgBody&, opcode: i64) {
    cg_record(f, opcode, 0);
    wb_byte(f.code, opcode);
}
fn cg_save(f: CgBody&, wasm_type: i64) -> i64 {
    let slot = cg_local(f, wasm_type);
    cg_record(f, 0x21, slot);
    wb_op(f.code, 0x21, slot);
    return slot;
}
fn cg_tee(f: CgBody&, wasm_type: i64) -> i64 {
    let slot = cg_local(f, wasm_type);
    cg_record(f, 0x22, slot);
    wb_op(f.code, 0x22, slot);
    return slot;
}
fn cg_get(f: CgBody&, slot: i64) {
    if slot >= f.params { cg_record(f, 0x20, slot); }
    f.code.push(0x20);
    if (slot as! u64) < 128 { f.code.push(slot as u8); }
    else if (slot as! u64) < 16384 { f.code.push(((slot & 127) | 128) as u8); f.code.push((slot >> 7) as u8); }
    else { wb_u(f.code, slot); }
}
fn cg_set(f: CgBody&, slot: i64) {
    if slot >= f.params { cg_record(f, 0x21, slot); }
    f.code.push(0x21);
    if (slot as! u64) < 128 { f.code.push(slot as u8); }
    else if (slot as! u64) < 16384 { f.code.push(((slot & 127) | 128) as u8); f.code.push((slot >> 7) as u8); }
    else { wb_u(f.code, slot); }
}
// 64-bit memory (docs/TARGET.md). With cg_wide an address is an i64 and a
// slice a v128 of pointer and count; without it they are what they always
// were, an i32 and an i64 of 32-bit pointer and count, and every helper
// below emits exactly the bytes its call site did before.
var cg_wide: bool = false;
// --wasm-region-stats: every region keeps its high-water mark.
var cg_region_stats: bool = false;
// The value type of an address, and of a slice.
inline fn wa() -> i64 { if cg_wide { return 0x7e; } return 0x7f; }
inline fn ws() -> i64 { if cg_wide { return 0x7b; } return 0x7e; }
// The bytes of a growable array's control: six address-sized words.
inline fn wc_bytes() -> i64 { if cg_wide { return 48; } return 24; }
// Keep address and slice writers as calls when the compiler builds itself.
// An address or size constant.
fn wa_const(out: u8[>..]&, value: i64) { if cg_wide { wb_i64(out, value); } else { wb_i32(out, value); } }
// An i32 instruction on addresses: the i64 one of the same name with cg_wide.
fn wa_op(out: u8[>..]&, op: i64) {
    var opcode = op;
    if cg_wide { if op >= 0x45 && op <= 0x4f { opcode = op + 0x0b; } else if op >= 0x67 && op <= 0x78 { opcode = op + 0x12; } }
    wb_byte(out, opcode);
}
// Adds a constant offset to the address on the stack.
fn wa_add(out: u8[>..]&, offset: i64) { if offset != 0 { wa_const(out, offset); wa_op(out, 0x6a); } }
// Loads and stores an address-sized word.
fn wa_load(out: u8[>..]&, offset: i64) { if cg_wide { wb_mem(out, 0x29, 3, offset); } else { wb_mem(out, 0x28, 2, offset); } }
fn wa_store(out: u8[>..]&, offset: i64) { if cg_wide { wb_mem(out, 0x37, 3, offset); } else { wb_mem(out, 0x36, 2, offset); } }
// Word k of a control (base, raw length, limit, raw capacity, image base, mode).
fn wc_load(out: u8[>..]&, word: i64) { if cg_wide { wb_mem(out, 0x29, 3, word * 8); } else { wb_mem(out, 0x28, 2, word * 4); } }
fn wc_store(out: u8[>..]&, word: i64) { if cg_wide { wb_mem(out, 0x37, 3, word * 8); } else { wb_mem(out, 0x36, 2, word * 4); } }
// The bytes of an address-sized word, and of k of them. A structure the
// backend lays out itself as u32 words (controls, effect records and their
// metadata, capture environments, cursor tables) keeps its word order with
// every word address-sized: word k is at ww(k).
inline fn wa_bytes() -> i64 { if cg_wide { return 8; } return 4; }
// The most elements or bytes a count may name: what 32 bits hold, or with
// cg_wide 2^62 - 1, so that the sum of two never wraps. A product with an
// element size is checked where it is formed (wG_check_product).
inline fn wn_limit() -> i64 { if cg_wide { return 4611686018427387903; } return 4294967295; }
inline fn ww(words: i64) -> i64 { return words * wa_bytes(); }
// Signed i64.extend of an address-sized number.
inline fn wa_extend_s(out: u8[>..]&) { if !cg_wide { wb_byte(out, 0xac); } }
// i64 to address (i32.wrap_i64), address to i64 (i64.extend_i32_u), and an
// i32 count to and from an address-sized one: nothing where they are the same.
inline fn wa_wrap(out: u8[>..]&) { if !cg_wide { wb_byte(out, 0xa7); } }
inline fn wa_extend(out: u8[>..]&) { if !cg_wide { wb_byte(out, 0xad); } }
inline fn wa_from_i32(out: u8[>..]&) { if cg_wide { wb_byte(out, 0xad); } }
inline fn wa_to_i32(out: u8[>..]&) { if cg_wide { wb_byte(out, 0xa7); } }
// An address as a condition: nonzero.
inline fn wa_truth(out: u8[>..]&) { if cg_wide { wb_byte(out, 0x50); wb_byte(out, 0x45); } }
// A slice on the stack: its pointer (an address), its count as an i64, its
// count as an address-sized number.
fn ws_ptr(out: u8[>..]&) { if cg_wide { wb_byte(out, 0xfd); wb_u(out, 0x1d); wb_byte(out, 0); } else { wb_byte(out, 0xa7); } }
fn ws_count(out: u8[>..]&) { if cg_wide { wb_byte(out, 0xfd); wb_u(out, 0x1d); wb_byte(out, 1); } else { wb_i64(out, 32); wb_byte(out, 0x88); } }
fn ws_len(out: u8[>..]&) { ws_count(out); wa_wrap(out); }
fn ws_load(out: u8[>..]&, offset: i64) { if cg_wide { wb_byte(out, 0xfd); wb_u(out, 0); wb_u(out, 3); wb_u(out, offset); } else { wb_mem(out, 0x29, 3, offset); } }
fn ws_store(out: u8[>..]&, offset: i64) { if cg_wide { wb_byte(out, 0xfd); wb_u(out, 0x0b); wb_u(out, 3); wb_u(out, offset); } else { wb_mem(out, 0x37, 3, offset); } }
// Makes a slice of the pointer and the count on the stack, both i64 (the
// pointer after wa_extend).
fn ws_pack(f: CgBody&) {
    if !cg_wide { wb_i64(f.code, 32); wb_byte(f.code, 0x86); wb_byte(f.code, 0x84); return; }
    let count = cg_save(f, 0x7e); wb_byte(f.code, 0xfd); wb_u(f.code, 0x12); cg_get(f, count); wb_byte(f.code, 0xfd); wb_u(f.code, 0x1e); wb_byte(f.code, 1);
}
fn cg_begin(f: CgBody&, opcode: i64, result: i64) -> i64 {
    cg_control(f, opcode); wb_byte(f.code, result);
    f.serial++; f.labels.push(f.serial); return f.serial;
}
fn cg_end(f: CgBody&) { cg_control(f, 0x0b); f.labels.pop(); }
fn cg_branch(p: Program&, f: CgBody&, label: i64, conditional: bool) {
    var at = f.labels.len;
    while at > 0 {
        at--;
        if f.labels[at] == label {
            var opcode = 0x0c; if conditional { opcode = 0x0d; }
            let depth = f.labels.len - at - 1;
            cg_record(f, opcode, depth); wb_op(f.code, opcode, depth); return;
        }
    }
    cg_fail(p, f.function, "wasm: branch target is outside this function");
}
fn cg_zero(out: u8[>..]&, wasm_type: i64) {
    if wasm_type == 0x7f { wb_i32(out, 0); }
    else if wasm_type == 0x7e { wb_i64(out, 0); }
    else if wasm_type == 0x7d { wb_f32(out, 0.0); }
    else if wasm_type == 0x7c { wb_f64(out, 0.0); }
    else if wasm_type == 0x7b { wb_byte(out, 0xfd); wb_u(out, 0x0c); for part in 0..16 { wb_byte(out, 0); } }
}
fn cg_frame(f: CgBody&, bytes: i64, align: i64) -> i64 {
    f.frame_used = true;
    f.frame_bytes = cg_align(f.frame_bytes, align);
    let offset = f.frame_bytes;
    f.frame_bytes += bytes;
    return offset;
}
fn cg_frame_address(f: CgBody&, offset: i64) {
    f.frame_used = true;
    cg_get(f, f.frame);
    wa_add(f.code, offset);
}
fn cg_temporary(p: Program&, f: CgBody&, id: i64) -> i64 {
    var bytes = cg_slot_size(p, id); if bytes < 1 { bytes = 1; }
    let offset = cg_frame(f, bytes, p.types[id].align);
    cg_frame_address(f, offset); return cg_save(f, wa());
}
fn cg_signature_slot(m: CgModule&, bytes: u8[:]) -> i64 {
    let mask = m.signature_slots.len - 1;
    var slot = bytes_hash(bytes) & mask;
    while m.signature_slots[slot] > 0 {
        let sig: const CgSignature& = m.signatures[m.signature_slots[slot] - 1];
        if bytes.len == sig.count && same_bytes(bytes, m.signature_bytes[sig.start..sig.start + sig.count]) { break; }
        slot = (slot + 1) & mask;
    }
    return slot;
}
fn cg_signature(m: CgModule&, args: const u8[:], results: const u8[:]) -> i64 {
    wb_signature(m.signature_scratch, args, results);
    if 2 * m.signatures.len >= m.signature_slots.len {
        var size = m.signature_slots.len * 2; if size == 0 { size = 32; }
        m.signature_slots.clear(); m.signature_slots.resize(size, 0);
        for sig, index in m.signatures {
            let slot = cg_signature_slot(m, m.signature_bytes[sig.start..sig.start + sig.count]);
            m.signature_slots[slot] = index + 1;
        }
    }
    let slot = cg_signature_slot(m, m.signature_scratch);
    let found = m.signature_slots[slot];
    if found > 0 { m.signature_scratch.clear(); return found - 1; }
    let at = m.signature_bytes.len;
    m.signature_bytes.append(m.signature_scratch);
    let result = m.signatures.len;
    m.signatures.push(CgSignature { start: at, count: m.signature_scratch.len });
    m.signature_slots[slot] = result + 1;
    m.signature_scratch.clear();
    return result;
}
// Slots hold segment index + 1. The segments themselves stay in emission order.
fn cg_data_slot(m: CgModule&, bytes: u8[:]) -> i64 {
    let mask = m.segment_slots.len - 1;
    var slot = bytes_hash(bytes) & mask;
    while m.segment_slots[slot] > 0 {
        let segment: const CgSegment& = m.segments[m.segment_slots[slot] - 1];
        if bytes.len == segment.count && same_bytes(bytes, m.data[segment.start..segment.start + segment.count]) { break; }
        slot = (slot + 1) & mask;
    }
    return slot;
}
fn cg_data(m: CgModule&, bytes: u8[:]) -> i64 {
    if 2 * m.segments.len >= m.segment_slots.len {
        var size = m.segment_slots.len * 2; if size == 0 { size = 16; }
        m.segment_slots.clear(); m.segment_slots.resize(size, 0);
        for segment, index in m.segments {
            let slot = cg_data_slot(m, m.data[segment.start..segment.start + segment.count]);
            m.segment_slots[slot] = index + 1;
        }
    }
    let slot = cg_data_slot(m, bytes);
    let found = m.segment_slots[slot];
    if found > 0 { return m.segments[found - 1].address; }
    m.segment_slots[slot] = m.segments.len + 1;
    let address = m.next_data;
    let at = m.data.len;
    m.data.append(bytes); m.next_data += bytes.len;
    m.segments.push(CgSegment { address: address, start: at, count: bytes.len });
    return address;
}
fn cg_text(m: CgModule&, f: CgBody&, text: u8[:]) {
    wa_const(f.code, cg_data(m, text)); wb_i32(f.code, text.len); wb_op(f.code, 0x10, CG_WRITE);
}
// The line a failed check at node reports, and the one a call at node passes
// a located callee (upstream CodeGen::LocArgs, CallerLoc): its own, or, on a
// library line of a located function, the caller's, its at parameter.
fn cg_line(p: Program&, f: CgBody&, node: i64) {
    let token = location_token(p, node);
    if f.at >= 0 && library_token(p, token) { cg_get(f, f.at); return; }
    var line = 0; if token >= 0 && token < p.tokens.len { line = p.tokens[token].line; }
    wb_i32(f.code, line);
}
fn cg_diagnostic_line(p: Program&, f: CgBody&, node: i64) {
    if f.diagnostic_line >= 0 { cg_get(f, f.diagnostic_line); } else { cg_line(p, f, node); }
}
fn cg_abort_helper(m: CgModule&, address: i64, length: i64) -> i64 {
    for item, i in m.abort_helpers {
        if item.address == address && item.length == length { return m.abort_base + i; }
    }
    let idx = m.abort_helpers.len;
    m.abort_helpers.push(CgAbortHelper { address: address, length: length });
    return m.abort_base + idx;
}
fn cg_abort(p: Program&, m: CgModule&, f: CgBody&, node: i64, text: u8[:]) {
    let address = cg_data(m, text);
    if m.abort_base >= 0 {
        let helper = cg_abort_helper(m, address, text.len);
        cg_diagnostic_line(p, f, node); wb_op(f.code, 0x10, helper); wb_byte(f.code, 0);
        return;
    }
    wa_const(f.code, address); wb_i32(f.code, text.len); cg_diagnostic_line(p, f, node);
    wb_op(f.code, 0x10, CG_ABORT); wb_byte(f.code, 0);
}
fn cg_trap_if(p: Program&, m: CgModule&, f: CgBody&, node: i64, text: u8[:]) {
    cg_begin(f, 0x04, 0x40); cg_abort(p, m, f, node, text); cg_end(f);
}
inline fn cg_function(m: CgModule&, symbol: i64) -> i64 {
    if symbol < 0 || symbol >= m.functions_by_symbol.len { return -1; }
    return m.functions_by_symbol[symbol].first as i64;
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
inline fn cg_elements_function(m: CgModule&, symbol: i64) -> i64 {
    if symbol < 0 || symbol >= m.functions_by_symbol.len { return -1; }
    let elements = m.functions_by_symbol[symbol].elements;
    if elements >= 0 { return elements as i64; }
    return m.functions_by_symbol[symbol].first as i64;
}
fn cg_elements_table(m: CgModule&) -> i64 {
    var bytes: u8[>..] = [];
    for item in m.functions {
        if item.table_index < 0 { continue; }
        let target = cg_elements_function(m, item.symbol);
        let slot = m.functions[target].table_index;
        for part in 0..4 { wb_byte(bytes, slot >> (part * 8)); }
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
fn cg_make_signature(p: Program&, m: CgModule&, function: i64, closure: bool, sroa_ret: i64 = 0) -> i64 {
    var args: u8[>..] = []; var results: u8[>..] = []; var types: i64[>..] = [];
    if closure { args.push(wa() as u8); }
    // A host cannot take a v128: an import takes a wide slice as its pointer
    // and its count, two i64 (cg_import_arguments).
    let split = cg_wide && (p.nodes[function].flags & F_EXTERN) != 0;
    var param = p.nodes[function].first;
    while param >= 0 {
        if split && cg_type_kind(p, p.nodes[param].type_id) == TY_SLICE { args.push(0x7e); args.push(0x7e); }
        else { args.push(cg_wasm_type(p, p.nodes[param].type_id) as u8); }
        param = p.nodes[param].next;
    }
    if !closure {
        for capture in m.captures { if capture.function == function { args.push(wa() as u8); } }
    }
    cg_function_results(p, function, types);
    if !closure && sroa_ret > 0 && types.len == 1 {
        var field = p.types[types[0]].first;
        while field >= 0 {
            if (p.nodes[field].flags & F_PAD) == 0 {
                results.push(cg_wasm_type(p, p.nodes[field].type_id) as u8);
            }
            field = p.nodes[field].next;
        }
    } else {
        for id in types {
            if cg_aggregate(p, id) { args.push(wa() as u8); }
            results.push(cg_wasm_type(p, id) as u8);
        }
    }
    if !closure && (p.nodes[function].flags & F_LOCATED) != 0 { args.push(0x7f); }
    return cg_signature(m, args, results);
}
inline fn cg_convert(p: Program&, m: CgModule&, f: CgBody&, from: i64, to: i64, node: i64) {
    if from == to { return; }
    cg_convert_slow(p, m, f, from, to, node);
}
recursive fn cg_convert_slow(p: Program&, m: CgModule&, f: CgBody&, from: i64, to: i64, node: i64) {
    if from == to { return; }
    if cg_type_kind(p, from) == TY_REF && (p.types[from].flags & TF_OPTIONAL) != 0 && cg_type_kind(p, to) == TY_BOOL {
        wa_op(f.code, 0x45); wb_byte(f.code, 0x45); return;
    }
    if cg_type_kind(p, from) == TY_REF && cg_type_kind(p, to) != TY_REF {
        let pointee = p.types[from].element;
        if (p.types[from].flags & TF_OPTIONAL) != 0 { cg_fail(p, node, "wasm: optional reference must be narrowed before reading"); return; }
        cg_load(p, m, f, pointee, 0); cg_convert_slow(p, m, f, pointee, to, node); return;
    }
    if cg_type_kind(p, from) == TY_ARRAY && cg_type_kind(p, to) == TY_SLICE { cg_pack_view(p, m, f, from, node); return; }
    if cg_type_kind(p, to) == TY_ENUM && cg_enum_image(p, to) &&
       (cg_type_kind(p, from) == TY_ENUM && p.types[from].declaration == p.types[to].declaration ||
        cg_type_kind(p, from) == TY_STRUCT && p.types[from].pool >= 0 && p.types[p.types[from].pool].declaration == p.types[to].declaration) {
        let source = cg_save(f, wa());
        if m.regions_enabled { let receiving = cg_temporary_destination(p, m, f, to, node); cg_construct_enum_captured(p, m, f, from, source, receiving, node); cg_get(f, f.construction_destinations[receiving].header); return; }
        let destination = cg_temporary(p, f, to);
        cg_enum_from_value(p, m, f, to, destination, from, source, node); cg_get(f, destination); return;
    }
    if cg_type_kind(p, from) == TY_ENUM && cg_enum_image(p, from) && cg_type_kind(p, to) == TY_ENUM && p.types[from].declaration == p.types[to].declaration {
        let source = cg_save(f, wa()); let bytes = cg_enum_image_bytes(p, m, f, from, source, node);
        cg_get(f, bytes); wa_const(f.code, cg_size(p, to)); wa_op(f.code, 0x4b); cg_trap_if(p, m, f, node, "enum payload exceeds fixed envelope");
        let destination = cg_temporary(p, f, to); cg_get(f, destination); wb_i32(f.code, 0); wa_const(f.code, cg_size(p, to)); wb_fill(f.code);
        cg_get(f, destination); cg_get(f, source); wc_load(f.code, 0); cg_get(f, bytes); wb_copy(f.code); cg_get(f, destination); return;
    }
    if cg_type_kind(p, from) == TY_STRUCT && cg_type_kind(p, to) == TY_ENUM && p.types[from].pool >= 0 && p.types[p.types[from].pool].declaration == p.types[to].declaration {
        let source = cg_save(f, wa()); let destination = cg_temporary(p, f, to);
        cg_get(f, destination); wb_i32(f.code, 0); wa_const(f.code, cg_size(p, to)); wb_fill(f.code);
        cg_get(f, destination); wb_i32(f.code, p.nodes[p.types[from].declaration].integer);
        if p.types[to].length_storage == 2 { wb_mem(f.code, 0x3b, 0, 0); } else { wb_mem(f.code, 0x3a, 0, 0); }
        cg_get(f, destination); wa_const(f.code, p.types[to].length_storage); wa_op(f.code, 0x6a); let payload = cg_save(f, wa());
        if p.types[from].first >= 0 { cg_copy(p, m, f, from, payload, source, node); }
        cg_get(f, destination); return;
    }
    if cg_type_kind(p, to) == TY_ARRAY && (cg_type_kind(p, from) == TY_SLICE || cg_type_kind(p, from) == TY_ARRAY) && from != to {
        if cg_type_kind(p, from) == TY_ARRAY { cg_pack_view(p, m, f, from, node); }
        // An array whose static extent exceeds a static capacity is checked
        // here, with upstream's message (§9.3).
        if cg_type_kind(p, from) == TY_ARRAY && p.types[to].array_kind == A_LIMITED && p.types[to].count >= 0 && !cg_owner(p, to) &&
           p.types[from].count > p.types[to].count {
            let view = cg_save(f, ws());
            cg_get(f, view); ws_len(f.code); wa_const(f.code, p.types[to].count); wa_op(f.code, 0x4b);
            cg_trap_if(p, m, f, node, "limited array capacity exceeded"); cg_get(f, view);
        }
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
    // The count comes out address-sized.
    let bytes = cg_static_prefix(p, id);
    if cg_wide {
        if bytes == 1 { wb_mem(f.code, 0x31, 0, 0); } else if bytes == 2 { wb_mem(f.code, 0x33, 0, 0); }
        else if bytes == 4 { wb_mem(f.code, 0x35, 0, 0); } else { wb_mem(f.code, 0x29, 0, 0); }
        return;
    }
    if bytes == 1 { wb_mem(f.code, 0x2d, 0, 0); }
    else if bytes == 2 { wb_mem(f.code, 0x2f, 0, 0); }
    else if bytes == 4 { wb_mem(f.code, 0x28, 0, 0); }
    else { wb_mem(f.code, 0x29, 0, 0); wb_byte(f.code, 0xa7); }
}
fn cg_length_store(p: Program&, f: CgBody&, id: i64) {
    // Takes an address-sized count.
    let bytes = cg_static_prefix(p, id);
    if cg_wide {
        if bytes == 1 { wb_mem(f.code, 0x3c, 0, 0); } else if bytes == 2 { wb_mem(f.code, 0x3d, 0, 0); }
        else if bytes == 4 { wb_mem(f.code, 0x3e, 0, 0); } else { wb_mem(f.code, 0x37, 0, 0); }
        return;
    }
    if bytes == 1 { wb_mem(f.code, 0x3a, 0, 0); }
    else if bytes == 2 { wb_mem(f.code, 0x3b, 0, 0); }
    else if bytes == 4 { wb_mem(f.code, 0x36, 0, 0); }
    else { wb_byte(f.code, 0xad); wb_mem(f.code, 0x37, 0, 0); }
}
recursive fn cg_pack_view(p: Program&, m: CgModule&, f: CgBody&, id: i64, node: i64) {
    if cg_type_kind(p, id) == TY_SLICE {
        if m.resolver >= 0 && cg_wide {
            // The slice with its pointer resolved: lane 0 replaced.
            let view = cg_save(f, ws()); cg_get(f, view); cg_get(f, view); ws_ptr(f.code); cg_resolve_pointer(m, f);
            wb_byte(f.code, 0xfd); wb_u(f.code, 0x1e); wb_byte(f.code, 0);
        } else if m.resolver >= 0 {
            let view = cg_save(f, 0x7e); cg_get(f, view); wb_byte(f.code, 0xa7); cg_resolve_pointer(m, f); wb_byte(f.code, 0xad);
            cg_get(f, view); wb_i64(f.code, -4294967296); wb_byte(f.code, 0x83); wb_byte(f.code, 0x84);
        }
        return;
    }
    if cg_type_kind(p, id) == TY_REF { cg_load(p, m, f, p.types[id].element, 0); cg_pack_view(p, m, f, p.types[id].element, node); return; }
    if cg_type_kind(p, id) != TY_ARRAY { cg_fail(p, node, "wasm: expected an array or slice"); return; }
    if cg_owner(p, id) && m.ordinary_owners { ws_load(f.code, 0); return; }
    if !cg_owner(p, id) && p.types[id].array_kind == A_FIXED {
        wa_extend(f.code); wb_i64(f.code, p.types[id].count); ws_pack(f); return;
    }
    let base = cg_save(f, wa());
    if cg_owner(p, id) {
        // An ordinary control starts with the slice itself. Keep image decoding
        // and its caller's diagnostic line in one shared fallback.
        if m.owner_view >= 0 {
            cg_get(f, base); wc_load(f.code, 5); wa_op(f.code, 0x45); cg_begin(f, 0x04, ws());
            cg_get(f, base); ws_load(f.code, 0); cg_control(f, 0x05);
            cg_get(f, base); cg_diagnostic_line(p, f, node); wb_op(f.code, 0x10, m.owner_view); cg_end(f); return;
        }
        cg_owner_read_base(p, m, f, base, node); wa_extend(f.code);
        cg_owner_read_length(p, m, f, base, node); wa_extend(f.code);
    } else {
        cg_get(f, base); let prefix = cg_static_prefix(p, id);
        wa_add(f.code, prefix);
        wa_extend(f.code);
        cg_get(f, base); cg_length_load(p, f, id); wa_extend(f.code);
    }
    ws_pack(f);
}
fn cg_symbol_address(p: Program&, m: CgModule&, f: CgBody&, symbol: i64, node: i64) {
    if symbol < 0 || symbol >= p.symbols.len { cg_fail(p, node, "wasm: unresolved storage symbol"); return; }
    if (p.symbols[symbol].flags & S_GLOBAL) != 0 {
        if symbol >= m.globals.len || m.globals[symbol] < 0 { cg_fail(p, node, "wasm: global storage was not assigned"); return; }
        wa_const(f.code, m.globals[symbol]); return;
    }
    if symbol >= f.slots.len || f.slots[symbol].local < 0 { cg_fail(p, node, "wasm: local or capture storage was not assigned"); return; }
    if f.slots[symbol].value { cg_fail(p, node, "wasm: scalar local unexpectedly requires an address"); return; }
    if f.slots[symbol].sroa_count > 0 { cg_fail(p, node, "wasm: SROA struct local unexpectedly requires an address"); return; }
    f.slots[symbol].address_used = true;
    cg_get(f, f.slots[symbol].local);
}
fn cg_field_place(p: Program&, m: CgModule&, f: CgBody&, object_type: i64, node: i64, field_id: i64 = -1) {
    var selected = field_id; if selected < 0 { selected = p.nodes[node].symbol; }
    if cg_byte_record(p, object_type) {
        let header = cg_save(f, wa()); let address = cg_byte_field(p, m, f, object_type, header, selected, node); cg_get(f, address); return;
    }
    if cg_record_image(p, object_type) && !cg_frame_metadata(p, object_type) && selected != p.types[object_type].tail {
        let owner = cg_save(f, wa()); let image = cg_record_image_base(p, m, f, object_type, owner, node);
        var field = p.types[object_type].first; var offset = 0;
        while field >= 0 && field != selected {
        if (p.nodes[field].flags & F_PAD) != 0 { offset += p.nodes[field].aux; }
        else { offset += cg_size(p, p.nodes[field].type_id); }
        field = p.nodes[field].next;
        }
        cg_get(f, image); wa_add(f.code, offset); return;
    }
    let offset = p.nodes[selected].integer;
    if offset < 0 { cg_fail(p, node, "wasm: variable record field requires an encoded field walker"); return; }
    wa_add(f.code, offset);
    return;
 }
// Wasm adds a load offset without wrapping. For compiler-created references,
// even the end of the largest permitted memory plus this offset must fit in u32
// on memory32 (memory64 addresses are u64 and never wrap within 2^48).
fn cg_member_memory_offset(p: Program&, m: CgModule&, node: i64, id: i64) -> i64 {
    if p.optimization < 2 || !m.safe_refs || m.resolver >= 0 || m.prefix_helper >= 0 ||
       id < 0 || cg_aggregate(p, id) || cg_relative_type(p, id) || p.types[id].storage != 0 { return -1; }
    let n: const Node& = p.nodes[node];
    if n.symbol < 0 || n.symbol >= p.nodes.len || p.nodes[n.symbol].kind != N_FIELD { return -1; }
    var object = p.nodes[n.left].type_id;
    if cg_type_kind(p, object) == TY_REF { object = p.types[object].element; }
    if cg_byte_record(p, object) || cg_record_image(p, object) { return -1; }
    let offset = p.nodes[n.symbol].integer;
    if offset <= 0 { return -1; }
    if !cg_wide && offset > 4294967295 - p.maximum_pages * 65536 { return -1; }
    return offset;
}
recursive fn cg_member_object(p: Program&, m: CgModule&, f: CgBody&, node: i64) -> i64 {
    let left = p.nodes[node].left;
    cg_expr(p, m, f, left);
    var id = p.nodes[left].type_id;
    if cg_type_kind(p, id) == TY_REF { id = p.types[id].element; cg_load(p, m, f, id, 0); }
    return id;
}
fn cg_scale_index(f: CgBody&, stride: i64) {
    if stride == 1 { return; }
    if stride == 2 { wa_const(f.code, 1); wa_op(f.code, 0x74); return; }
    if stride == 4 { wa_const(f.code, 2); wa_op(f.code, 0x74); return; }
    if stride == 8 { wa_const(f.code, 3); wa_op(f.code, 0x74); return; }
    if stride == 16 { wa_const(f.code, 4); wa_op(f.code, 0x74); return; }
    if stride == 32 { wa_const(f.code, 5); wa_op(f.code, 0x74); return; }
    if stride == 64 { wa_const(f.code, 6); wa_op(f.code, 0x74); return; }
    if stride == 128 { wa_const(f.code, 7); wa_op(f.code, 0x74); return; }
    if stride == 256 { wa_const(f.code, 8); wa_op(f.code, 0x74); return; }
    wa_const(f.code, stride); wa_op(f.code, 0x6c);
}

fn cg_add_proven_index(p: Program&, m: CgModule&, f: CgBody&, index_node: i64, stride: i64) {
    if p.nodes[index_node].kind == N_INTEGER && p.nodes[index_node].integer >= 0 {
        wa_add(f.code, p.nodes[index_node].integer * stride);
        return;
    }
    if cg_wide { cg_to(p, m, f, index_node, TYPE_U64); }
    else { cg_to(p, m, f, index_node, TYPE_U32); }
    cg_scale_index(f, stride);
    wa_op(f.code, 0x6a);
}

recursive fn cg_address(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    if node < 0 { cg_fail(p, node, "wasm: missing assignment location"); return; }
    let n: const Node& = p.nodes[node];
    if n.kind == N_NAME { cg_symbol_address(p, m, f, n.symbol, node); return; }
    if n.kind == N_UNARY && (n.integer == T_MUL || n.integer == T_XOR) { cg_expr(p, m, f, n.left); return; }
    if n.kind == N_MEMBER {
        if n.symbol < 0 || n.symbol >= p.nodes.len || p.nodes[n.symbol].kind != N_FIELD { cg_fail(p, node, "wasm: member does not identify a stored field"); return; }
        let object_type = cg_member_object(p, m, f, node);
        cg_field_place(p, m, f, object_type, node); cg_canonical_address(m, f, cg_size(p, p.nodes[n.symbol].type_id)); return;
    }
    if n.kind == N_INDEX {
        var id = p.nodes[n.left].type_id;
        let is_ref = cg_type_kind(p, id) == TY_REF;
        if is_ref { id = p.types[id].element; }
        let element = p.types[id].element;
        let kind = cg_type_kind(p, id);
        let owner = cg_owner(p, id);
        if f.hoists.len > 0 && m.resolver < 0 && p.types[element].storage != 1 {
            let hi = cg_hoist_find(p, f, n.left);
            if hi >= 0 {
                let h = f.hoists[hi];
                if (n.flags & F_BOUNDS_PROVEN) != 0 {
                    cg_get(f, h.ptr_local);
                    cg_add_proven_index(p, m, f, n.right, cg_size(p, element));
                    return;
                }
                if h.len_local >= 0 {
                    if p.nodes[n.right].kind == N_INTEGER && p.nodes[n.right].integer >= 0 {
                        let kv = p.nodes[n.right].integer;
                        wb_i64(f.code, kv); cg_get(f, h.len_local); wb_byte(f.code, 0x5a);
                        cg_trap_if(p, m, f, node, "array index out of bounds");
                        cg_get(f, h.ptr_local); wa_add(f.code, kv * cg_size(p, element)); return;
                    }
                    var index = -1;
                    let simple_idx = p.nodes[n.right].kind == N_NAME && p.nodes[n.right].symbol >= 0 &&
                        p.nodes[n.right].symbol < f.slots.len && f.slots[p.nodes[n.right].symbol].value &&
                        cg_wasm_type(p, p.nodes[n.right].type_id) == 0x7e && cg_type_kind(p, p.nodes[n.right].type_id) == TY_INT;
                    if simple_idx {
                        index = f.slots[p.nodes[n.right].symbol].local;
                        cg_get(f, index);
                    } else {
                        cg_to(p, m, f, n.right, TYPE_U64); index = cg_tee(f, 0x7e);
                    }
                    cg_get(f, h.len_local); wb_byte(f.code, 0x5a);
                    cg_trap_if(p, m, f, node, "array index out of bounds");
                    cg_get(f, h.ptr_local); cg_get(f, index); wa_wrap(f.code);
                    cg_scale_index(f, cg_size(p, element)); wa_op(f.code, 0x6a); return;
                }
            }
        }
        if (n.flags & F_BOUNDS_PROVEN) != 0 && m.resolver < 0 && p.types[element].storage != 1 {
            if owner && m.ordinary_owners {
                cg_expr(p, m, f, n.left);
                if is_ref { cg_load(p, m, f, id, 0); }
                wc_load(f.code, 0);
                cg_add_proven_index(p, m, f, n.right, cg_size(p, element));
                return;
            }
            if kind == TY_SLICE {
                cg_expr(p, m, f, n.left);
                if is_ref { cg_load(p, m, f, id, 0); }
                ws_ptr(f.code);
                cg_add_proven_index(p, m, f, n.right, cg_size(p, element));
                return;
            }
            if kind == TY_ARRAY && !owner {
                cg_expr(p, m, f, n.left);
                if is_ref { cg_load(p, m, f, id, 0); }
                wa_add(f.code, cg_static_prefix(p, id));
                cg_add_proven_index(p, m, f, n.right, cg_size(p, element));
                return;
            }
        }
        let simple_idx = p.nodes[n.right].kind == N_NAME && p.nodes[n.right].symbol >= 0 &&
            p.nodes[n.right].symbol < f.slots.len && f.slots[p.nodes[n.right].symbol].value &&
            cg_wasm_type(p, p.nodes[n.right].type_id) == 0x7e && cg_type_kind(p, p.nodes[n.right].type_id) == TY_INT;
        let const_idx = p.nodes[n.right].kind == N_INTEGER && p.nodes[n.right].integer >= 0;
        if cg_wide && owner && m.ordinary_owners && m.resolver < 0 && p.types[element].storage != 1 {
            cg_expr(p, m, f, n.left);
            if is_ref { cg_load(p, m, f, id, 0); }
            if const_idx {
                let hdr = cg_save(f, wa());
                let kv = p.nodes[n.right].integer;
                wb_i64(f.code, kv); cg_get(f, hdr); wc_load(f.code, 1); wb_byte(f.code, 0x5a);
                cg_trap_if(p, m, f, node, "array index out of bounds");
                cg_get(f, hdr); wc_load(f.code, 0); wa_add(f.code, kv * cg_size(p, element)); return;
            }
            if simple_idx {
                let hdr = cg_save(f, wa());
                let index = f.slots[p.nodes[n.right].symbol].local;
                cg_get(f, index); cg_get(f, hdr); wc_load(f.code, 1); wb_byte(f.code, 0x5a);
                cg_trap_if(p, m, f, node, "array index out of bounds");
                cg_get(f, hdr); wc_load(f.code, 0); cg_get(f, index);
                cg_scale_index(f, cg_size(p, element)); wa_op(f.code, 0x6a); return;
            }
            let hdr = cg_tee(f, wa());
            wc_load(f.code, 0); let ptr = cg_save(f, wa());
            cg_get(f, hdr); wc_load(f.code, 1); let len = cg_save(f, 0x7e);
            cg_to(p, m, f, n.right, TYPE_U64); let index = cg_tee(f, 0x7e);
            cg_get(f, len); wb_byte(f.code, 0x5a);
            cg_trap_if(p, m, f, node, "array index out of bounds");
            cg_get(f, ptr); cg_get(f, index);
            cg_scale_index(f, cg_size(p, element)); wa_op(f.code, 0x6a); return;
        }
        let simple_slice = kind == TY_SLICE && !is_ref && m.resolver < 0 &&
            p.nodes[n.left].kind == N_NAME && p.nodes[n.left].symbol >= 0 &&
            p.nodes[n.left].symbol < f.slots.len && f.slots[p.nodes[n.left].symbol].value &&
            (simple_idx || const_idx);
        var view = -1;
        if simple_slice {
            view = f.slots[p.nodes[n.left].symbol].local;
        } else {
            cg_expr(p, m, f, n.left); cg_pack_view(p, m, f, p.nodes[n.left].type_id, node);
            view = cg_save(f, ws());
        }
        if (n.flags & F_BOUNDS_PROVEN) == 0 {
            if const_idx && p.types[element].storage != 1 {
                let kv = p.nodes[n.right].integer;
                wb_i64(f.code, kv);
                cg_get(f, view); ws_count(f.code); wb_byte(f.code, 0x5a);
                cg_trap_if(p, m, f, node, "array index out of bounds");
                cg_get(f, view); ws_ptr(f.code); wa_add(f.code, kv * cg_size(p, element)); return;
            }
            var index = -1;
            if simple_idx {
                index = f.slots[p.nodes[n.right].symbol].local;
                cg_get(f, index);
            } else {
                cg_to(p, m, f, n.right, TYPE_U64); index = cg_tee(f, 0x7e);
            }
            cg_get(f, view); ws_count(f.code); wb_byte(f.code, 0x5a);
            cg_trap_if(p, m, f, node, "array index out of bounds");
            if p.types[element].storage == 1 {
                cg_get(f, view); ws_ptr(f.code); let base = cg_save(f, wa());
                let cursor = cg_walk_elements(p, m, f, base, index, node); cg_get(f, cursor); return;
            }
            cg_get(f, view); ws_ptr(f.code); cg_get(f, index); wa_wrap(f.code);
            cg_scale_index(f, cg_size(p, element)); wa_op(f.code, 0x6a); return;
        }
        cg_to(p, m, f, n.right, TYPE_U64); let index = cg_save(f, 0x7e);
        if p.types[element].storage == 1 {
            cg_get(f, view); ws_ptr(f.code); let base = cg_save(f, wa());
            let cursor = cg_walk_elements(p, m, f, base, index, node); cg_get(f, cursor); return;
        }
        cg_get(f, view); ws_ptr(f.code); cg_get(f, index); wa_wrap(f.code);
        cg_scale_index(f, cg_size(p, element)); wa_op(f.code, 0x6a); return;
    }
    cg_fail(p, node, "wasm: expression has no addressable storage");
}
fn cg_fixed_vectors(p: Program&, size: i64) -> bool {
    return p.bundled_host && p.optimization >= 2 && !cg_wide && size >= 16 && size <= 256;
}
fn cg_vector_memory(f: CgBody&, opcode: i64, offset: i64) {
    wb_byte(f.code, 0xfd); wb_u(f.code, opcode);
    wb_u(f.code, 0); wb_u(f.code, offset);
}
// The final vector ends at the exact byte count. It can overlap its predecessor.
fn cg_vector_offset(chunk: i64, size: i64) -> i64 {
    let offset = chunk * 16;
    if offset + 16 > size { return size - 16; }
    return offset;
}
fn cg_fixed_copy(p: Program&, m: CgModule&, f: CgBody&, into: i64, from: i64, size: i64) {
    cg_get(f, into); cg_canonical_address(m, f, size);
    cg_get(f, from); cg_canonical_address(m, f, size);
    if p.optimization >= 2 {
        if size == 1 { wb_mem(f.code, 0x2d, 0, 0); wb_mem(f.code, 0x3a, 0, 0); return; }
        if size == 2 { wb_mem(f.code, 0x2f, 0, 0); wb_mem(f.code, 0x3b, 0, 0); return; }
        if size == 4 { wb_mem(f.code, 0x28, 0, 0); wb_mem(f.code, 0x36, 0, 0); return; }
        if size == 8 { wb_mem(f.code, 0x29, 0, 0); wb_mem(f.code, 0x37, 0, 0); return; }
    }
    if !cg_fixed_vectors(p, size) { wa_const(f.code, size); wb_copy(f.code); return; }

    let source = cg_save(f, wa()); let destination = cg_save(f, wa());
    let start = f.work.len; let chunks = (size + 15) / 16;
    // Read every source byte before any write, preserving overlap and source traps.
    for chunk in 0..chunks {
        cg_get(f, source); cg_vector_memory(f, 0, cg_vector_offset(chunk, size));
        f.work.push(cg_save(f, 0x7b));
    }
    // The highest store checks the complete destination extent before a write.
    var chunk = chunks;
    while chunk > 0 {
        chunk--;
        cg_get(f, destination); cg_get(f, f.work[start + chunk]);
        cg_vector_memory(f, 11, cg_vector_offset(chunk, size));
    }
    f.work.resize(start);
}
// Takes the destination address from the stack.
fn cg_clear_bytes(p: Program&, f: CgBody&, size: i64) {
    if p.optimization >= 2 {
        if size == 1 { wb_i32(f.code, 0); wb_mem(f.code, 0x3a, 0, 0); return; }
        if size == 2 { wb_i32(f.code, 0); wb_mem(f.code, 0x3b, 0, 0); return; }
        if size == 4 { wb_i32(f.code, 0); wb_mem(f.code, 0x36, 0, 0); return; }
        if size == 8 { wb_i64(f.code, 0); wb_mem(f.code, 0x37, 0, 0); return; }
        if size == 12 {
            let dst = cg_tee(f, wa());
            wb_i64(f.code, 0); wb_mem(f.code, 0x37, 0, 4);
            cg_get(f, dst); wb_i32(f.code, 0); wb_mem(f.code, 0x36, 0, 0);
            return;
        }
    }
    if !cg_fixed_vectors(p, size) {
        wb_i32(f.code, 0); wa_const(f.code, size); wb_fill(f.code); return;
    }
    let destination = cg_save(f, wa());
    var chunk = (size + 15) / 16;
    while chunk > 0 {
        chunk--;
        cg_get(f, destination);
        wb_i32(f.code, 0); wb_byte(f.code, 0xfd); wb_u(f.code, 15); // i8x16.splat
        cg_vector_memory(f, 11, cg_vector_offset(chunk, size));
    }
}
recursive fn cg_copy(p: Program&, m: CgModule&, f: CgBody&, id: i64, destination: i64, source: i64, node: i64) {
    let into = cg_resolve_location(m, f, destination); let from = cg_resolve_location(m, f, source);
    if m.regions_enabled && (cg_frame_owner(p, id) || cg_image_owner(p, id) || cg_enum_image(p, id)) {
        let header = cg_region_acquire(p, m, f, id, into, -1, node); let entry = cg_region_cursor(f, header);
        let receiving = cg_destination(f, id, into, CG_TEMPORARY, false, false, false, entry, -1); if cg_enum_image(p, id) { cg_construct_enum_captured(p, m, f, id, from, receiving, node); }
        else if cg_image_owner(p, id) { cg_construct_image_captured(p, m, f, id, from, receiving, node); }
        else { cg_construct_frame_captured(p, m, f, id, from, receiving, node); } return;
    }
    // Without forwarding, this value's complete image needs no field repairs.
    if m.resolver < 0 && cg_aggregate(p, id) && !cg_has_owner(p, id) {
        cg_fixed_copy(p, m, f, into, from, cg_size(p, id)); return;
    }
    if !cg_aggregate(p, id) {
        cg_get(f, from); cg_load(p, m, f, id, 0); cg_write_value(p, m, f, id, into, node); return;
    }
    if cg_owner(p, id) {
        if p.types[id].array_kind == A_LIMITED { cg_copy_runtime_limited(p, m, f, id, into, from, node); return; }
        cg_get(f, from); cg_pack_view(p, m, f, id, node); cg_array_from_view(p, m, f, id, node);
        let snapshot = cg_save(f, wa()); cg_get(f, into); cg_get(f, snapshot); wa_const(f.code, wc_bytes()); wb_copy(f.code); return;
    }

    if cg_enum_image(p, id) { cg_enum_from_value(p, m, f, id, into, id, from, node); return; }
    if cg_byte_record(p, id) { cg_copy_byte_record(p, m, f, id, into, from, node); return; }
    if cg_record_image(p, id) { cg_copy_record_image(p, m, f, id, into, from, node); return; }
    // Fixed records and arrays are packed. Their checked offsets include all
    // explicit padding. Copy the complete image before repairing owner fields.
    cg_get(f, into); cg_get(f, from); wa_const(f.code, cg_size(p, id)); wb_copy(f.code);
    if cg_type_kind(p, id) == TY_STRUCT {
        let declaration = p.types[id].declaration;
        var field = p.nodes[declaration].first;
        while field >= 0 {
            let type_id = p.nodes[field].type_id;
            if cg_aggregate(p, type_id) {
                cg_get(f, into); wa_const(f.code, p.nodes[field].integer); wa_op(f.code, 0x6a); let dst = cg_save(f, wa());
                cg_get(f, from); wa_const(f.code, p.nodes[field].integer); wa_op(f.code, 0x6a); let src = cg_save(f, wa());
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
    let n: const Node& = p.nodes[node];
    if n.kind == N_BLOCK && n.origin >= 0 { return p.nodes[n.origin].kind == N_FUNCTION_VALUE; }
    if n.kind != N_CALL { return false; }
    if n.symbol < 0 { return true; }
    return (p.symbols[n.symbol].flags & (S_FUNCTION | S_BUILTIN)) == S_FUNCTION &&
        p.symbols[n.symbol].node >= 0 && p.nodes[p.symbols[n.symbol].node].kind == N_FUNCTION_VALUE;
}
recursive fn cg_to(p: Program&, m: CgModule&, f: CgBody&, node: i64, id: i64) {
    if node < 0 { cg_fail(p, node, "wasm: missing value expression"); return; }
    let from = p.nodes[node].type_id;
    if cg_type_kind(p, id) == TY_REF && cg_type_kind(p, from) != TY_REF && !cg_diverges(p, node) { cg_address(p, m, f, node); return; }
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
    if !m.regions_enabled || !cg_may_region(p, m, node) { cg_truth(p, m, f, node); return; }
    let live = f.region_live; let acq = f.acquisitions; let mark = cg_mark_regions(f); cg_truth(p, m, f, node);
    if f.acquisitions != acq { cg_restore_regions(f, mark); }
    f.region_live = live;
}
recursive fn cg_truth(p: Program&, m: CgModule&, f: CgBody&, node: i64) { cg_to(p, m, f, node, TYPE_BOOL); }
fn cg_drop_type(p: Program&, f: CgBody&, id: i64) {
    var types: i64[>..] = []; cg_result_types(p, id, types);
    for item in types { wb_byte(f.code, 0x1a); }
}
recursive fn cg_discard(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    if node < 0 { return; }
    if cg_call_sroa_return(p, m, node) > 0 && f.active_node != node && cg_receiving(f, -2 - node, 0) < 0 {
        let saved_cn = f.sroa_call_node; let saved_cb = f.sroa_call_base;
        f.sroa_call_node = node; f.sroa_call_base = -2;
        cg_expr(p, m, f, node);
        f.sroa_call_node = saved_cn; f.sroa_call_base = saved_cb;
        return;
    }
    cg_expr(p, m, f, node); cg_drop_type(p, f, p.nodes[node].type_id);
}
fn cg_invert_comparison(op: i64) -> i64 {
    if op == T_EQ { return T_NEQ; } if op == T_NEQ { return T_EQ; }
    if op == T_DOTEQ { return T_DOTNEQ; } if op == T_DOTNEQ { return T_DOTEQ; }
    if op == T_LT { return T_GTEQ; } if op == T_GTEQ { return T_LT; }
    if op == T_GT { return T_LTEQ; } if op == T_LTEQ { return T_GT; }
    return 0;
}
recursive fn cg_branch_cond(p: Program&, m: CgModule&, f: CgBody&, node: i64, target: i64, jump_if_true: bool) {
    if node < 0 || m.regions_enabled && cg_may_region(p, m, node) {
        cg_truth_scope(p, m, f, node);
        if cg_diverges(p, node) { return; }
        if !jump_if_true { wb_byte(f.code, 0x45); }
        cg_branch(p, f, target, true); return;
    }
    let n: const Node& = p.nodes[node];
    if n.kind == N_UNARY && n.integer == T_NOT {
        cg_branch_cond(p, m, f, n.left, target, !jump_if_true); return;
    }
    if n.kind == N_BINARY {
        let op = n.integer;
        if op == T_ANDAND {
            if !jump_if_true {
                cg_branch_cond(p, m, f, n.left, target, false);
                if cg_diverges(p, n.left) { return; }
                cg_branch_cond(p, m, f, n.right, target, false); return;
            }
            let fall = cg_begin(f, 0x02, 0x40);
            cg_branch_cond(p, m, f, n.left, fall, false);
            if !cg_diverges(p, n.left) { cg_branch_cond(p, m, f, n.right, target, true); }
            cg_end(f); return;
        }
        if op == T_OROR {
            if jump_if_true {
                cg_branch_cond(p, m, f, n.left, target, true);
                if cg_diverges(p, n.left) { return; }
                cg_branch_cond(p, m, f, n.right, target, true); return;
            }
            let fall = cg_begin(f, 0x02, 0x40);
            cg_branch_cond(p, m, f, n.left, fall, true);
            if !cg_diverges(p, n.left) { cg_branch_cond(p, m, f, n.right, target, false); }
            cg_end(f); return;
        }
        if !jump_if_true && cg_type_kind(p, n.type_id) == TY_BOOL {
            let inv = cg_invert_comparison(op);
            if inv != 0 {
                if op == T_DOTEQ || op == T_DOTNEQ || (op == T_EQ || op == T_NEQ) && (p.nodes[n.left].kind == N_NULL || p.nodes[n.right].kind == N_NULL) {
                    cg_expr(p, m, f, n.left); if cg_diverges(p, n.left) { return; } cg_resolve_pointer(m, f);
                    cg_expr(p, m, f, n.right); if cg_diverges(p, n.right) { return; } cg_resolve_pointer(m, f);
                    wb_byte(f.code, cg_numeric_opcode(inv, wa(), true)); cg_branch(p, f, target, true); return;
                }
                var id = p.nodes[n.left].type_id;
                if cg_type_kind(p, id) == TY_REF { id = p.types[id].element; }
                if n.aux >= 0 && n.aux < p.types.len && (p.types[n.aux].kind == TY_INT || p.types[n.aux].kind == TY_FLOAT) { id = n.aux; }
                let kind = cg_type_kind(p, id);
                if (kind == TY_INT && p.types[id].storage == 0) || kind == TY_BOOL {
                    cg_to(p, m, f, n.left, id); if cg_diverges(p, n.left) { return; }
                    cg_to(p, m, f, n.right, id); if cg_diverges(p, n.right) { return; }
                    cg_numeric(p, m, f, inv, id, node); cg_branch(p, f, target, true); return;
                }
            }
        }
    }
    cg_truth(p, m, f, node);
    if cg_diverges(p, node) { return; }
    if !jump_if_true { wb_byte(f.code, 0x45); }
    cg_branch(p, f, target, true);
}
recursive fn cg_binary(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n: const Node& = p.nodes[node]; let op = n.integer;
    if op == T_ANDAND || op == T_OROR {
        cg_truth_scope(p, m, f, n.left); if cg_diverges(p, n.left) { return; } cg_begin(f, 0x04, 0x7f);
        if op == T_ANDAND { cg_truth(p, m, f, n.right); } else { wb_i32(f.code, 1); }
        cg_control(f, 0x05);
        if op == T_OROR { cg_truth(p, m, f, n.right); } else { wb_i32(f.code, 0); }
        cg_end(f); return;
    }
    if op == T_DOTEQ || op == T_DOTNEQ || (op == T_EQ || op == T_NEQ) && (p.nodes[n.left].kind == N_NULL || p.nodes[n.right].kind == N_NULL) {
        cg_expr(p, m, f, n.left); if cg_diverges(p, n.left) { return; } cg_resolve_pointer(m, f); cg_expr(p, m, f, n.right); if cg_diverges(p, n.right) { return; } cg_resolve_pointer(m, f);
        wb_byte(f.code, cg_numeric_opcode(op, wa(), true)); return;
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
    cg_control(f, 0x05);
    cg_get(f, value); cg_get(f, magnitude); wb_byte(f.code, cg_numeric_opcode(T_LT, w, false));
    cg_begin(f, 0x04, w); cg_get(f, original); cg_control(f, 0x05);
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
// After a call: a nonlocal return in flight (global 2) leaves this frame
// too, through the landing of the statement being emitted where defer
// bodies are registered (cg_block_into).
fn cg_effect_check(p: Program&, m: CgModule&, f: CgBody&, types: i64[:]) {
    if !m.nonlocal_returns { return; }
    var saved: i64[>..] = [];
    for id in types { saved.push(cg_local(f, cg_wasm_type(p, id))); }
    var at = saved.len;
    while at > 0 { at--; cg_set(f, saved[at]); }
    var exit = f.done; if f.effect_landing >= 0 { exit = f.effect_landing; }
    wb_op(f.code, 0x23, 2); wa_truth(f.code); cg_branch(p, f, exit, true);
    for slot in saved { cg_get(f, slot); }
}
// Whether a statement holds a call that a nonlocal return in flight may
// leave through (§7.9, mark_unwinding_functions).
recursive fn cg_unwinding_tree(p: Program&, node: i64) -> bool {
    if node < 0 { return false; } let n: const Node& = p.nodes[node];
    if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE || n.kind == N_STRUCT || n.kind == N_ENUM || n.kind == N_ALIAS || n.kind == N_PATTERN || n.kind == N_IMPORT { return false; }
    if n.kind == N_CALL && (n.flags & F_DISPATCH) != 0 {
        var arm = n.third;
        while arm >= 0 {
            let symbol = p.nodes[arm].symbol;
            if symbol >= 0 && p.symbols[symbol].node >= 0 && (p.nodes[p.symbols[symbol].node].flags & F_UNWINDS) != 0 { return true; }
            arm = p.nodes[arm].next;
        }
    } else if n.kind == N_CALL && n.symbol >= 0 {
        let callee: const Symbol& = p.symbols[n.symbol];
        if (callee.flags & (S_FUNCTION | S_BUILTIN)) == S_FUNCTION && callee.node >= 0 && (p.nodes[callee.node].flags & F_UNWINDS) != 0 { return true; }
    } else if n.kind == N_CALL { return true; }
    for head in [n.left, n.right, n.third, n.first] {
        var child = head;
        while child >= 0 { if cg_unwinding_tree(p, child) { return true; } child = p.nodes[child].next; }
    }
    return false;
}
// One run of each `defer` body registered above mark, latest first (§6.6),
// at an exit of its block. The body cannot leave, so the exit goes on after.
recursive fn cg_run_defers(p: Program&, m: CgModule&, f: CgBody&, mark: i64) {
    var index = f.defers.len;
    f.running_defers += 1;
    while index > mark { index -= 1; cg_statement(p, m, f, p.nodes[f.defers[index]].right); }
    f.running_defers -= 1;
}
// The opcode an extern is, where it is one instruction. CG_WRAP_COUNT marks
// a rotation whose i64 count wraps to i32 first; i32.rotl and i64.rotl take
// the count modulo the width, as std's rotl does (upstream runtime_ext.h).
let CG_WRAP_COUNT: i64 = 256;
fn cg_intrinsic(p: Program&, function: i64) -> i64 {
    if (p.nodes[function].flags & F_EXTERN) == 0 { return 0; }
    var parameter = p.nodes[function].first;
    if parameter < 0 { return 0; }
    let id = p.nodes[parameter].type_id; let w = cg_wasm_type(p, id);
    var name = token_text(p, p.nodes[function].token);
    if p.nodes[function].integer >= 0 && p.nodes[function].integer < p.tokens.len && p.tokens[p.nodes[function].integer].kind == T_STRLIT {
        let token = p.tokens[p.nodes[function].integer]; name = p.text[token.text_start..token.text_start + token.text_len];
    }
    let count = p.nodes[parameter].next;
    if count >= 0 {
        if p.nodes[count].next >= 0 || cg_wasm_type(p, p.nodes[count].type_id) != 0x7e { return 0; }
        if w == 0x7f && same_bytes(name, "gs_rotl32") { return CG_WRAP_COUNT | 0x77; }
        if w == 0x7f && same_bytes(name, "gs_rotr32") { return CG_WRAP_COUNT | 0x78; }
        if w == 0x7e && same_bytes(name, "gs_rotl64") { return 0x89; }
        if w == 0x7e && same_bytes(name, "gs_rotr64") { return 0x8a; }
        return 0;
    }
    if same_bytes(name, "gs_clz") && id == TYPE_U64 { return 0x79; }
    if same_bytes(name, "gs_ctz") && id == TYPE_U64 { return 0x7a; }
    if same_bytes(name, "gs_popcount") && id == TYPE_U64 { return 0x7b; }
    // binary's float bits: the reinterpretations.
    if w == 0x7f && same_bytes(name, "gs_f32_from_bits") { return 0xbe; }
    if w == 0x7e && same_bytes(name, "gs_f64_from_bits") { return 0xbf; }
    if w == 0x7d && same_bytes(name, "gs_f32_to_bits") { return 0xbc; }
    if w == 0x7c && same_bytes(name, "gs_f64_to_bits") { return 0xbd; }
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
    let offset = cg_frame(f, ww(item.capture_count), wa_bytes()); cg_frame_address(f, offset); let environment = cg_save(f, wa());
    var ordinal = 0;
    for capture in m.captures {
        if capture.function == item.node {
            cg_get(f, environment); cg_symbol_address(p, m, f, capture.symbol, node); wa_store(f.code, ww(ordinal)); ordinal++;
        }
    }
    // A function value stays one i64 for now: the table slot below, the
    // environment's address above, which has to be under 4 GiB with cg_wide.
    wb_i64(f.code, item.table_index); cg_get(f, environment); wa_extend(f.code); wb_i64(f.code, 32); wb_byte(f.code, 0x86); wb_byte(f.code, 0x84);
}
fn cg_direct_array_call(p: Program&, f: CgBody&, node: i64, destination: i64) -> bool {
    let n: const Node& = p.nodes[node]; let target = f.construction_destinations[destination]; var natural = -1;
    if n.symbol >= 0 && (p.symbols[n.symbol].flags & S_BUILTIN) != 0 { return false; }
    var callback = false;
    if n.symbol >= 0 && (p.symbols[n.symbol].flags & S_FUNCTION) != 0 { let function = p.symbols[n.symbol].node; natural = cg_result_type(p, function); callback = p.nodes[function].kind == N_FUNCTION_VALUE; }
    else if n.left >= 0 && cg_type_kind(p, p.nodes[n.left].type_id) == TY_FN { natural = p.types[p.nodes[n.left].type_id].element; }
    if callback && cg_owner(p, natural) && !cg_named_array_mode(p, natural, target.type_id) { return false; }
    if cg_variant_result(p, natural, target.type_id) >= 0 { return true; }
    if cg_frame_owner(p, natural) || cg_frame_owner(p, target.type_id) || cg_image_owner(p, natural) || cg_image_owner(p, target.type_id) || cg_enum_image(p, natural) || cg_enum_image(p, target.type_id) { return natural == target.type_id; }
    if !cg_owner(p, natural) || !cg_owner(p, target.type_id) { return false; }
    let source: const Type& = p.types[natural]; let receiving: const Type& = p.types[target.type_id];
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
fn cg_plain_fixed_aggregate(p: Program&, id: i64) -> bool {
    return cg_aggregate(p, id) && !cg_has_owner(p, id) && !cg_fixed_relative(p, id) &&
           !cg_enum_image(p, id) && !cg_byte_record(p, id) && !cg_record_image(p, id);
}
fn cg_fresh_aggregate_expr(p: Program&, node: i64, id: i64) -> bool {
    if node < 0 { return false; }
    let n: const Node& = p.nodes[node];
    if n.type_id != id { return false; }
    if n.kind == N_RECORD { return true; }
    if n.kind == N_CALL && (n.flags & F_DISPATCH) == 0 {
        if n.symbol < 0 {
            let ct = p.nodes[n.left].type_id;
            return cg_type_kind(p, ct) == TY_FN && p.types[ct].element == id;
        }
        let s: const Symbol& = p.symbols[n.symbol];
        if (s.flags & S_BUILTIN) == 0 && (s.flags & S_FUNCTION) != 0 && s.node >= 0 &&
           (p.nodes[s.node].flags & F_EXTERN) == 0 && cg_type_kind(p, s.type_id) == TY_FN {
            return p.types[s.type_id].element == id;
        }
    }
    return false;
}
fn cg_sroa_struct(p: Program&, id: i64) -> i64 {
    if id < 13 || id >= p.types.len { return 0; }
    let t: const Type& = p.types[id];
    if t.kind != TY_STRUCT || t.size <= 0 || t.tail >= 0 || root_struct_type(p, id) { return 0; }
    if cg_byte_record(p, id) || cg_record_image(p, id) || cg_has_owner(p, id) || cg_fixed_relative(p, id) { return 0; }
    var count: i64 = 0;
    var field = t.first;
    while field >= 0 {
        let fn_n: const Node& = p.nodes[field];
        if (fn_n.flags & F_PAD) == 0 {
            if fn_n.integer < 0 || !cg_local_slot_type(p, fn_n.type_id) { return 0; }
            count += 1;
            if count > 4 { return 0; }
        }
        field = fn_n.next;
    }
    return count;
}
fn cg_sroa_field_index(p: Program&, struct_id: i64, field_node: i64) -> i64 {
    var fi: i64 = 0;
    var field = p.types[struct_id].first;
    while field >= 0 {
        if (p.nodes[field].flags & F_PAD) == 0 {
            if field == field_node { return fi; }
            fi += 1;
        }
        field = p.nodes[field].next;
    }
    return -1;
}
fn cg_sroa_field_type(p: Program&, struct_id: i64, target_fi: i64) -> i64 {
    var fi: i64 = 0;
    var field = p.types[struct_id].first;
    while field >= 0 {
        if (p.nodes[field].flags & F_PAD) == 0 {
            if fi == target_fi { return p.nodes[field].type_id; }
            fi += 1;
        }
        field = p.nodes[field].next;
    }
    return -1;
}
fn cg_sroa_has_padding(p: Program&, id: i64) -> bool {
    let size = cg_size(p, id);
    var total: i64 = 0;
    var field = p.types[id].first;
    while field >= 0 {
        let fn_n: const Node& = p.nodes[field];
        if (fn_n.flags & F_PAD) != 0 { return true; }
        total += cg_size(p, fn_n.type_id);
        field = fn_n.next;
    }
    return total != size;
}
fn cg_record_has_self(p: Program&, node: i64) -> bool {
    if node < 0 || p.nodes[node].kind != N_RECORD { return false; }
    var binding = p.nodes[node].first;
    while binding >= 0 {
        let init = p.nodes[binding].right;
        if init >= 0 && p.nodes[init].kind == N_SELF { return true; }
        binding = p.nodes[binding].next;
    }
    return false;
}
fn cg_record_has_extern(p: Program&, node: i64) -> bool {
    if node < 0 || p.nodes[node].kind != N_RECORD { return false; }
    var binding = p.nodes[node].first;
    while binding >= 0 {
        let init = p.nodes[binding].right;
        if init >= 0 && p.nodes[init].kind == N_CALL && (p.nodes[init].flags & F_DISPATCH) == 0 && p.nodes[init].symbol >= 0 {
            let s: const Symbol& = p.symbols[p.nodes[init].symbol];
            if (s.flags & (S_FUNCTION | S_BUILTIN)) == S_FUNCTION && s.node >= 0 &&
               (p.nodes[s.node].flags & F_EXTERN) != 0 && cg_intrinsic(p, s.node) == 0 {
                return true;
            }
        }
        binding = p.nodes[binding].next;
    }
    return false;
}
fn cg_sroa_field_store(p: Program&, f: CgBody&, id: i64, local: i64) {
    if cg_type_kind(p, id) == TY_BOOL { wb_i32(f.code, 255); wb_byte(f.code, 0x71); }
    else if cg_type_kind(p, id) == TY_INT && p.types[id].count < 32 { cg_normalize(p, f.code, id); }
    cg_set(f, local);
}
fn cg_sroa_zero(p: Program&, f: CgBody&, id: i64, base_local: i64) {
    var fi: i64 = 0;
    var field = p.types[id].first;
    while field >= 0 {
        if (p.nodes[field].flags & F_PAD) == 0 {
            cg_zero(f.code, cg_wasm_type(p, p.nodes[field].type_id));
            cg_set(f, base_local + fi);
            fi += 1;
        }
        field = p.nodes[field].next;
    }
}
fn cg_sroa_load_from_addr(p: Program&, f: CgBody&, id: i64, addr_local: i64, base_local: i64) {
    var fi: i64 = 0;
    var field = p.types[id].first;
    while field >= 0 {
        let fn_n: const Node& = p.nodes[field];
        if (fn_n.flags & F_PAD) == 0 {
            cg_get(f, addr_local);
            cg_load_fixed(p, f.code, fn_n.type_id, fn_n.integer);
            cg_set(f, base_local + fi);
            fi += 1;
        }
        field = fn_n.next;
    }
}
fn cg_sroa_store_to_addr(p: Program&, f: CgBody&, id: i64, base_local: i64, addr_local: i64) {
    if cg_sroa_has_padding(p, id) { cg_get(f, addr_local); cg_clear_bytes(p, f, cg_size(p, id)); }
    var fi: i64 = 0;
    var field = p.types[id].first;
    while field >= 0 {
        let fn_n: const Node& = p.nodes[field];
        if (fn_n.flags & F_PAD) == 0 {
            cg_get(f, addr_local);
            cg_get(f, base_local + fi);
            cg_store(p, f.code, fn_n.type_id, fn_n.integer);
            fi += 1;
        }
        field = fn_n.next;
    }
}
fn cg_sroa_store_locals_to_addr(p: Program&, f: CgBody&, id: i64, locals: const i64[:], addr_local: i64) {
    if cg_sroa_has_padding(p, id) { cg_get(f, addr_local); cg_clear_bytes(p, f, cg_size(p, id)); }
    var fi: i64 = 0;
    var field = p.types[id].first;
    while field >= 0 {
        let fn_n: const Node& = p.nodes[field];
        if (fn_n.flags & F_PAD) == 0 {
            cg_get(f, addr_local);
            cg_get(f, locals[fi]);
            cg_store(p, f.code, fn_n.type_id, fn_n.integer);
            fi += 1;
        }
        field = fn_n.next;
    }
}
fn cg_sroa_alloc_locals(p: Program&, f: CgBody&, id: i64) -> i64 {
    var first_local = -1;
    var field = p.types[id].first;
    while field >= 0 {
        if (p.nodes[field].flags & F_PAD) == 0 {
            let fl = cg_local(f, cg_wasm_type(p, p.nodes[field].type_id));
            if first_local < 0 { first_local = fl; }
        }
        field = p.nodes[field].next;
    }
    return first_local;
}
fn cg_sroa_materialize(p: Program&, f: CgBody&, sym: i64) {
    let id = p.symbols[sym].type_id;
    let dst = cg_temporary(p, f, id);
    cg_sroa_store_to_addr(p, f, id, f.slots[sym].local, dst);
    cg_get(f, dst);
}
fn cg_call_sroa_return(p: Program&, m: CgModule&, node: i64) -> i64 {
    if node < 0 { return 0; }
    let n: const Node& = p.nodes[node];
    if n.kind != N_CALL || (n.flags & F_DISPATCH) != 0 || n.symbol < 0 { return 0; }
    let s: const Symbol& = p.symbols[n.symbol];
    if (s.flags & (S_FUNCTION | S_BUILTIN)) != S_FUNCTION { return 0; }
    let idx = cg_function(m, n.symbol);
    if idx < 0 || m.functions[idx].sroa_return <= 0 { return 0; }
    if cg_type_kind(p, s.type_id) != TY_FN || p.types[s.type_id].element != n.type_id { return 0; }
    return m.functions[idx].sroa_return;
}
recursive fn cg_emit_into_sroa(p: Program&, m: CgModule&, f: CgBody&, node: i64, id: i64, base_local: i64, sc: i64, fresh: bool) {
    if node < 0 { cg_sroa_zero(p, f, id, base_local); return; }
    let n: const Node& = p.nodes[node];
    if n.kind == N_RECORD && n.type_id == id && !cg_record_has_self(p, node) && !cg_record_has_extern(p, node) {
        var seen: bool[4] = [false; 4];
        if fresh {
            var binding = n.first;
            while binding >= 0 {
                let field = p.nodes[binding].symbol;
                let fi = cg_sroa_field_index(p, id, field);
                let ft = p.nodes[field].type_id;
                let init = p.nodes[binding].right;
                if init >= 0 {
                    cg_to(p, m, f, init, ft);
                    if cg_diverges(p, init) { return; }
                } else { cg_zero(f.code, cg_wasm_type(p, ft)); }
                cg_sroa_field_store(p, f, ft, base_local + fi);
                seen[fi] = true;
                binding = p.nodes[binding].next;
            }
            var fi: i64 = 0; var field = p.types[id].first;
            while field >= 0 {
                if (p.nodes[field].flags & F_PAD) == 0 {
                    if !seen[fi] { cg_zero(f.code, cg_wasm_type(p, p.nodes[field].type_id)); cg_set(f, base_local + fi); }
                    fi += 1;
                }
                field = p.nodes[field].next;
            }
            return;
        }
        var temps: i64[4] = [-1; 4];
        var binding = n.first;
        while binding >= 0 {
            let field = p.nodes[binding].symbol;
            let fi = cg_sroa_field_index(p, id, field);
            let ft = p.nodes[field].type_id;
            let init = p.nodes[binding].right;
            if init >= 0 {
                cg_to(p, m, f, init, ft);
                if cg_diverges(p, init) { return; }
            } else { cg_zero(f.code, cg_wasm_type(p, ft)); }
            let tmp = cg_local(f, cg_wasm_type(p, ft));
            cg_sroa_field_store(p, f, ft, tmp);
            temps[fi] = tmp; seen[fi] = true;
            binding = p.nodes[binding].next;
        }
        var fi: i64 = 0; var field = p.types[id].first;
        while field >= 0 {
            if (p.nodes[field].flags & F_PAD) == 0 {
                if seen[fi] { cg_get(f, temps[fi]); }
                else { cg_zero(f.code, cg_wasm_type(p, p.nodes[field].type_id)); }
                cg_set(f, base_local + fi);
                fi += 1;
            }
            field = p.nodes[field].next;
        }
        return;
    }
    if n.kind == N_NAME && n.type_id == id && n.symbol >= 0 && n.symbol < f.slots.len && f.slots[n.symbol].sroa_count > 0 {
        let src_base = f.slots[n.symbol].local;
        if src_base != base_local {
            for fi in 0..sc { cg_get(f, src_base + fi); cg_set(f, base_local + fi); }
        }
        return;
    }
    if n.type_id == id && cg_call_sroa_return(p, m, node) == sc && f.active_node != node && cg_receiving(f, -2 - node, 0) < 0 {
        let saved_cn = f.sroa_call_node; let saved_cb = f.sroa_call_base;
        f.sroa_call_node = node; f.sroa_call_base = base_local;
        cg_expr(p, m, f, node);
        f.sroa_call_node = saved_cn; f.sroa_call_base = saved_cb;
        return;
    }
    cg_to(p, m, f, node, id);
    if !cg_diverges(p, node) {
        let addr = cg_save(f, wa());
        cg_sroa_load_from_addr(p, f, id, addr, base_local);
    }
}
recursive fn cg_emit_into_dest(p: Program&, m: CgModule&, f: CgBody&, node: i64, id: i64, dest: i64) {
    if node < 0 { cg_fail(p, node, "wasm: missing aggregate value"); return; }
    let n: const Node& = p.nodes[node];
    if m.resolver < 0 && cg_plain_fixed_aggregate(p, id) && n.type_id == id {
        if n.kind == N_NAME && n.symbol >= 0 && n.symbol < f.slots.len && f.slots[n.symbol].sroa_count > 0 {
            cg_sroa_store_to_addr(p, f, id, f.slots[n.symbol].local, dest); return;
        }
        if n.kind == N_RECORD {
            cg_record_fields(p, m, f, id, dest, node); return;
        }
        if n.kind == N_CALL && (n.flags & F_DISPATCH) == 0 && f.active_node != node && cg_receiving(f, -2 - node, 0) < 0 {
            var direct = false;
            if n.symbol < 0 {
                let ct = p.nodes[n.left].type_id;
                direct = cg_type_kind(p, ct) == TY_FN && p.types[ct].element == id;
            } else {
                let s: const Symbol& = p.symbols[n.symbol];
                direct = (s.flags & S_BUILTIN) == 0 && (s.flags & S_FUNCTION) != 0 && s.node >= 0 &&
                         (p.nodes[s.node].flags & F_EXTERN) == 0 && cg_type_kind(p, s.type_id) == TY_FN && p.types[s.type_id].element == id;
            }
            if direct {
                let saved_node = f.direct_node; let saved_dest = f.direct_dest;
                f.direct_node = node; f.direct_dest = dest;
                cg_expr(p, m, f, node);
                f.direct_node = saved_node; f.direct_dest = saved_dest;
                if !cg_diverges(p, node) { wb_byte(f.code, 0x1a); }
                return;
            }
        }
    }
    cg_to(p, m, f, node, id);
    if !cg_diverges(p, node) { let src = cg_save(f, wa()); cg_copy(p, m, f, id, dest, src, node); }
}
recursive fn cg_call(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n: const Node& = p.nodes[node];
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
        cg_get(f, closure); wb_i64(f.code, 32); wb_byte(f.code, 0x88); wa_wrap(f.code);
    }
    let variant_plans = f.work.len; let result_count = cg_result_count(p, return_id);
    var mv: i64 = 0;
    if function >= 0 && index >= 0 && m.functions[index].sroa_return > 0 { mv = m.functions[index].sroa_return; }
    for ordinal in 0..result_count {
        let natural = cg_result_at(p, return_id, ordinal); var requested = cg_receiving(f, -2 - node, ordinal); var producer = -1;
        if requested < 0 && result_count == 1 && f.active_node == node { requested = f.active_destination; }
        if m.regions_enabled && requested >= 0 && cg_variant_result(p, natural, f.construction_destinations[requested].type_id) >= 0 && (result_count == 1 || cg_region_value(p, natural)) { producer = cg_prepare_variant_result(p, m, f, natural, requested, node); }
        f.work.push(producer); f.work.push(requested);
    }
    // An import takes a wide slice as its pointer and its count, two i64
    // (cg_make_signature): a v128 cannot cross to the host.
    let split = cg_wide && function >= 0 && (p.nodes[function].flags & F_EXTERN) != 0;
    var arg = n.first;
    while param >= 0 && arg >= 0 {
        let id = p.nodes[param].type_id;
        if m.regions_enabled && cg_region_value(p, id) {
            let receiving = cg_temporary_destination(p, m, f, id, arg); cg_construct_region(p, m, f, arg, receiving); if cg_diverges(p, arg) { return; } cg_get(f, f.construction_destinations[receiving].header);
        } else {
            cg_to(p, m, f, arg, id); if cg_diverges(p, arg) { return; }
            if cg_aggregate(p, id) {
                let fresh_sroa = p.nodes[arg].kind == N_NAME && p.nodes[arg].type_id == id &&
                    p.nodes[arg].symbol >= 0 && p.nodes[arg].symbol < f.slots.len && f.slots[p.nodes[arg].symbol].sroa_count > 0;
                if !(m.resolver < 0 && cg_plain_fixed_aggregate(p, id) && (fresh_sroa || cg_fresh_aggregate_expr(p, arg, id))) {
                    let source = cg_save(f, wa()); let snapshot = cg_temporary(p, f, id);
                    cg_copy(p, m, f, id, snapshot, source, arg); cg_get(f, snapshot);
                }
            } else if split && cg_type_kind(p, id) == TY_SLICE {
                let view = cg_save(f, ws()); cg_get(f, view); ws_ptr(f.code); cg_get(f, view); ws_count(f.code);
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
        if mv == 0 {
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
                else if results.len == 1 && f.direct_node == node && f.direct_dest >= 0 { cg_get(f, f.direct_dest); }
                else { cg_get(f, cg_temporary(p, f, id)); }
            }
        }
        plans.push(plan);
    }
    f.work.resize(variant_plans);
    if function >= 0 {
        let opcode = cg_intrinsic(p, function);
        if opcode != 0 { if (opcode & CG_WRAP_COUNT) != 0 { wb_byte(f.code, 0xa7); } wb_byte(f.code, opcode & 255); }
        else {
            var target = -1;
            if index >= 0 { target = m.functions[index].index; cg_region_call(m, f, index, node); }
            else { for item, i in m.imports { if item.symbol == n.symbol { target = i; } } }
            if target < 0 { cg_fail(p, node, "wasm: call has no emitted function or import"); return; }
            if (p.nodes[function].flags & F_LOCATED) != 0 { cg_line(p, f, node); }
            wb_op(f.code, 0x10, target);
        }
    } else {
        var args: u8[>..] = [wa() as u8]; var returns: u8[>..] = [];
        param = p.types[callable_type].first;
        while param >= 0 { args.push(cg_wasm_type(p, p.nodes[param].type_id) as u8); param = p.nodes[param].next; }
        for id in results { if cg_aggregate(p, id) { args.push(wa() as u8); } returns.push(cg_wasm_type(p, id) as u8); }
        // The function number is a true i32; the elements table keeps its
        // four-byte entries (cg_elements_table).
        cg_get(f, closure); wb_byte(f.code, 0xa7);
        if cg_raw_value(f, node) { wa_from_i32(f.code); wa_const(f.code, 4); wa_op(f.code, 0x6c); wa_const(f.code, cg_elements_table(m)); wa_op(f.code, 0x6a); wb_mem(f.code, 0x28, 0, 0); }
        let signature = cg_signature(m, args, returns);
        for item, candidate in m.functions { if item.table_index >= 0 && item.closure_signature == signature { cg_region_call(m, f, candidate, node); } }
        wb_op(f.code, 0x11, signature); wb_u(f.code, 0);
    }
    cg_effect_check(p, m, f, results);
    var adapting = false; for plan in plans { if plan.adaptation != 0 { adapting = true; } }
    if mv > 0 {
        if !adapting && f.sroa_call_node == node && n.type_id == results[0] {
            if f.sroa_call_base == -2 {
                for drop_i in 0..mv { wb_byte(f.code, 0x1a); }
                return;
            }
            if f.sroa_call_base >= 0 {
                var fi = mv;
                while fi > 0 { fi -= 1; cg_set(f, f.sroa_call_base + fi); }
                return;
            }
            if f.sroa_call_base <= -3 {
                let target_fi = -3 - f.sroa_call_base;
                var k = mv - 1;
                while k > target_fi { wb_byte(f.code, 0x1a); k -= 1; }
                if target_fi > 0 {
                    let kept = cg_save(f, cg_wasm_type(p, cg_sroa_field_type(p, results[0], target_fi)));
                    while k > 0 { wb_byte(f.code, 0x1a); k -= 1; }
                    cg_get(f, kept);
                }
                return;
            }
        }
        var sroa_temps: i64[4] = [-1; 4];
        var field = p.types[results[0]].first; var fi: i64 = 0;
        while field >= 0 {
            if (p.nodes[field].flags & F_PAD) == 0 {
                sroa_temps[fi] = cg_local(f, cg_wasm_type(p, p.nodes[field].type_id));
                fi += 1;
            }
            field = p.nodes[field].next;
        }
        while fi > 0 { fi -= 1; cg_set(f, sroa_temps[fi]); }
        var dst = -1;
        if plans[0].adaptation == 3 { dst = f.construction_destinations[plans[0].producer].header; }
        else if !adapting && f.direct_node == node && f.direct_dest >= 0 { dst = f.direct_dest; }
        else { dst = cg_temporary(p, f, results[0]); }
        cg_sroa_store_locals_to_addr(p, f, results[0], sroa_temps, dst);
        cg_get(f, dst);
    }
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
    let n: const Node& = p.nodes[node]; let id = n.type_id; let element = p.types[id].element;
    if cg_type_kind(p, id) == TY_SLICE && (n.flags & F_DEFAULT) != 0 && n.first < 0 { cg_zero(f.code, ws()); return; }
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
    cg_get(f, destination); cg_clear_bytes(p, f, cg_size(p, id));
    var count = 0; var child = n.first;
    while child >= 0 { count++; child = p.nodes[child].next; }
    var fill_value = -1; let each = cg_fill_each(p, node, element);
    var count_local = -1;
    if n.right >= 0 {
        cg_to(p, m, f, n.right, TYPE_U64); let count64 = cg_save(f, 0x7e);
        if n.first >= 0 && !cg_has_relative(p, element) && !each && !cg_wide {
            cg_get(f, count64); wb_i64(f.code, wn_limit()); wb_byte(f.code, 0x56);
            cg_begin(f, 0x04, 0x40);
            var vt = element; if p.types[element].storage == 1 { vt = TYPE_I64; }
            cg_to(p, m, f, n.first, vt);
            if !cg_diverges(p, n.first) { wb_byte(f.code, 0x1a); }
            cg_abort(p, m, f, node, "array repetition count out of range");
            cg_end(f);
        } else {
            cg_get(f, count64); wb_i64(f.code, wn_limit()); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array repetition count out of range");
        }
        cg_get(f, count64); wa_wrap(f.code); count_local = cg_save(f, wa());
    }
    else { wa_const(f.code, count); count_local = cg_save(f, wa()); }
    cg_check_array_length(p, m, f, id, count_local, node);
    if n.right >= 0 && n.first >= 0 && !cg_has_relative(p, element) && !each {
        var value_type = element; if p.types[element].storage == 1 { value_type = TYPE_I64; }
        cg_to(p, m, f, n.first, value_type); fill_value = cg_save(f, cg_wasm_type(p, value_type));
    }
    var base = destination;
    if cg_owner(p, id) {
        var capacity = count_local;
        if n.third >= 0 {
            cg_to(p, m, f, n.third, TYPE_U64); let capacity64 = cg_save(f, 0x7e);
            cg_get(f, capacity64); wb_i64(f.code, wn_limit()); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array capacity out of range");
            cg_get(f, capacity64); wa_wrap(f.code); capacity = cg_save(f, wa());
            cg_get(f, count_local); cg_get(f, capacity); wa_op(f.code, 0x4b); cg_trap_if(p, m, f, node, "limited array capacity exceeded");
        }
        base = cg_owner_image(p, m, f, id, destination, count_local, capacity, node);
    } else {
        cg_get(f, count_local); wa_const(f.code, p.types[id].count); wa_op(f.code, 0x4b); cg_trap_if(p, m, f, node, "limited array capacity exceeded");
        if p.types[id].array_kind == A_LIMITED {
            cg_get(f, destination); cg_get(f, count_local); cg_length_store(p, f, id);
            cg_get(f, destination); wa_const(f.code, cg_static_prefix(p, id)); wa_op(f.code, 0x6a); base = cg_save(f, wa());
        }
    }
    if cg_has_relative(p, element) {
        cg_literal_elements(p, m, f, node, element, base, count_local); cg_get(f, destination); return;
    }
    if p.types[element].storage == 1 { cg_encoded_array_initializers(p, m, f, node, destination, base, count_local, fill_value); cg_get(f, destination); return; }
    if n.right >= 0 && n.first >= 0 {
        let value = fill_value;
        wa_const(f.code, 0); let counter = cg_save(f, wa());
        let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
        cg_get(f, counter); cg_get(f, count_local); wa_op(f.code, 0x4f); cg_branch(p, f, done, true);
        cg_get(f, base); cg_get(f, counter); wa_const(f.code, cg_size(p, element)); wa_op(f.code, 0x6c); wa_op(f.code, 0x6a); let address = cg_save(f, wa());
        if each {
            // Each slot's defaults release their temporaries' regions.
            let live = f.region_live; let acq = f.acquisitions; var mark = -1; if m.regions_enabled { mark = cg_mark_regions(f); }
            cg_to(p, m, f, n.first, element); cg_write_value(p, m, f, element, address, node);
            if f.acquisitions != acq { cg_restore_regions(f, mark); }
            f.region_live = live;
        } else { cg_get(f, value); cg_write_value(p, m, f, element, address, node); }
        cg_get(f, counter); wa_const(f.code, 1); wa_op(f.code, 0x6a); cg_set(f, counter); cg_branch(p, f, again, false); cg_end(f); cg_end(f);
    } else {
        child = n.first; var ordinal = 0;
        while child >= 0 {
            cg_get(f, base); wa_const(f.code, ordinal * cg_size(p, element)); wa_op(f.code, 0x6a); let address = cg_save(f, wa());
            cg_to(p, m, f, child, element); if cg_diverges(p, child) { return; } cg_write_value(p, m, f, element, address, child);
            child = p.nodes[child].next; ordinal++;
        }
    }
    cg_get(f, destination);
}
fn cg_record_full_init(p: Program&, id: i64, node: i64) -> bool {
    if cg_type_kind(p, id) != TY_STRUCT || cg_byte_record(p, id) || cg_record_image(p, id) || cg_has_owner(p, id) { return false; }
    let size = cg_size(p, id); if size <= 0 { return false; }
    var expected_bytes = 0; var field = p.types[id].first;
    while field >= 0 {
        let fn_node: const Node& = p.nodes[field];
        if (fn_node.flags & F_PAD) != 0 { return false; }
        let fsize = cg_size(p, fn_node.type_id);
        if fn_node.integer != expected_bytes || fsize <= 0 { return false; }
        expected_bytes += fsize; field = fn_node.next;
    }
    if expected_bytes != size { return false; }
    var init_bytes = 0; var binding = p.nodes[node].first;
    while binding >= 0 {
        let b: const Node& = p.nodes[binding];
        if b.symbol < 0 || b.right < 0 || p.nodes[b.right].kind == N_SELF || cg_diverges(p, b.right) { return false; }
        init_bytes += cg_size(p, p.nodes[b.symbol].type_id);
        binding = b.next;
    }
    return init_bytes == size;
}
recursive fn cg_record_fields(p: Program&, m: CgModule&, f: CgBody&, id: i64, destination: i64, node: i64, captured: i64 = -1, in_place: bool = false) {
    let n: const Node& = p.nodes[node];
    if cg_byte_record(p, id) { cg_construct_byte_record(p, m, f, id, destination, node); return; }
    if (!in_place || n.first < 0) && !(n.first >= 0 && cg_record_full_init(p, id, node)) { cg_get(f, destination); cg_clear_bytes(p, f, cg_size(p, id)); }
    var payload_offset = 0;
    if cg_type_kind(p, id) == TY_ENUM && n.symbol >= 0 {
        cg_get(f, destination); wb_i32(f.code, p.nodes[n.symbol].integer);
        if p.types[id].length_storage == 2 { wb_mem(f.code, 0x3b, 0, 0); } else { wb_mem(f.code, 0x3a, 0, 0); }
        payload_offset = p.types[id].length_storage;
    }
    let fold_base = p.optimization >= 2 && m.safe_refs && m.resolver < 0 && m.prefix_helper < 0 && !cg_record_image(p, id);
    var binding = n.first;
    while binding >= 0 {
        let field = p.nodes[binding].symbol;
        if field < 0 || field >= p.nodes.len { cg_fail(p, binding, "wasm: record initializer has no resolved field"); return; }
        let initializer = p.nodes[binding].right;
        if p.nodes[field].integer < 0 { cg_fail(p, binding, "wasm: byte-record construction requires sequential image packing"); return; }
        let field_type = p.nodes[field].type_id;
        let offset = payload_offset + p.nodes[field].integer;
        if initializer >= 0 && fold_base && !cg_aggregate(p, field_type) && !cg_relative_type(p, field_type) &&
           p.types[field_type].storage == 0 && offset >= 0 && (cg_wide || offset <= 4294967295 - p.maximum_pages * 65536) {
            cg_get(f, destination);
            if p.nodes[initializer].kind == N_SELF { cg_get(f, destination); wa_add(f.code, payload_offset); }
            else if captured >= 0 { cg_get(f, cg_literal_saved(p, f, captured, initializer)); }
            else { cg_to(p, m, f, initializer, field_type); }
            if cg_diverges(p, initializer) { return; }
            if !cg_store(p, f.code, field_type, offset) { cg_fail(p, binding, "wasm: unsupported stored value type"); }
            binding = p.nodes[binding].next; continue;
        }
        cg_get(f, destination); wa_add(f.code, offset); let address = cg_save(f, wa());
        if initializer >= 0 {
            if p.nodes[initializer].kind == N_SELF {
                cg_get(f, destination); wa_add(f.code, payload_offset);
            } else if cg_relative_literal(p, initializer, field_type) {
                cg_literal_at(p, m, f, initializer, field_type, address, captured, in_place);
                if cg_diverges(p, initializer) { return; } binding = p.nodes[binding].next; continue;
            } else if captured < 0 && cg_fixed_relative(p, field_type) {
                cg_fixed_to(p, m, f, initializer, field_type, address);
                if cg_diverges(p, initializer) { return; } binding = p.nodes[binding].next; continue;
            } else if captured >= 0 { cg_get(f, cg_literal_saved(p, f, captured, initializer)); }
            else if !in_place && m.resolver < 0 && cg_plain_fixed_aggregate(p, field_type) {
                cg_emit_into_dest(p, m, f, initializer, field_type, address);
                if cg_diverges(p, initializer) { return; } binding = p.nodes[binding].next; continue;
            } else { cg_to(p, m, f, initializer, field_type); }
            if cg_diverges(p, initializer) { return; } cg_write_value(p, m, f, field_type, address, binding);
        } else if in_place { cg_get(f, address); cg_clear_bytes(p, f, cg_size(p, field_type)); }
        binding = p.nodes[binding].next;
    }
    if cg_record_image(p, id) { cg_pack_record_image(p, m, f, id, destination, node); }
}
fn cg_has_relative(p: Program&, id: i64) -> bool {
    var pending: i64[>..] = [id]; var seen: i64[>..] = [];
    while pending.len > 0 {
        let current = pending.pop(); if current < 0 { continue; }
        var visited = false; for old in seen { if old == current { visited = true; break; } } if visited { continue; } seen.push(current);
        let t: const Type& = p.types[current];
        if t.kind == TY_REF { if t.length_storage >= 0 { return true; } }
        else if t.kind == TY_ARRAY { pending.push(t.element); }
        else if t.kind == TY_STRUCT || t.kind == TY_ENUM {
            var field = t.first; while field >= 0 { if (p.nodes[field].flags & F_PAD) == 0 { pending.push(p.nodes[field].type_id); } field = p.nodes[field].next; }
        }
    }
    return false;
}
recursive fn cg_field_defaults(p: Program&, id: i64) -> bool {
    let t: const Type& = p.types[id];
    if t.kind == TY_ARRAY { return t.array_kind == A_FIXED && t.count > 0 && cg_field_defaults(p, t.element); }
    if t.kind == TY_ENUM { return t.first >= 0 && cg_field_defaults(p, p.nodes[t.first].type_id); }
    if t.kind != TY_STRUCT { return false; }
    var field = t.first;
    while field >= 0 {
        let n: const Node& = p.nodes[field];
        if (n.flags & F_PAD) == 0 && (n.right >= 0 || cg_field_defaults(p, n.type_id)) { return true; } field = n.next;
    }
    return false;
}
// A default fill builds each element from the declared field defaults, which
// may have effects, so it evaluates its element once per slot; a written
// `[v; n]` evaluates `v` once.
fn cg_fill_each(p: Program&, node: i64, element: i64) -> bool {
    let n: const Node& = p.nodes[node];
    return n.right >= 0 && n.first >= 0 && (n.flags & F_DEFAULT) != 0 && cg_field_defaults(p, element);
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
        let n: const Node& = p.nodes[node];
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
    let n: const Node& = p.nodes[node];
    if n.right >= 0 {
        if captured >= 0 { cg_get(f, cg_literal_saved(p, f, captured, -node - 1)); }
        else { cg_to(p, m, f, n.right, TYPE_U64); }
        let wide = cg_save(f, 0x7e); cg_get(f, wide); wb_i64(f.code, wn_limit()); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array repetition count out of range");
        cg_get(f, wide); wa_wrap(f.code); return cg_save(f, wa());
    }
    var count = 0; var child = n.first; while child >= 0 { count += 1; child = p.nodes[child].next; }
    wa_const(f.code, count); return cg_save(f, wa());
}
recursive fn cg_literal_elements(p: Program&, m: CgModule&, f: CgBody&, node: i64, element: i64, destination: i64, count: i64, captured: i64 = -1, in_place: bool = false) {
    let n: const Node& = p.nodes[node]; let mark = f.work.len; var replay = captured;
    if n.right >= 0 && n.first >= 0 {
        let each = replay < 0 && cg_fill_each(p, node, element);
        if replay < 0 && !each { replay = mark; cg_capture_literal(p, m, f, n.first, element); if cg_diverges(p, n.first) { f.work.resize(mark); return; } }
        wa_const(f.code, 0); let index = cg_save(f, wa()); let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
        cg_get(f, index); cg_get(f, count); wa_op(f.code, 0x4f); cg_branch(p, f, done, true);
        cg_get(f, destination); cg_get(f, index); wa_const(f.code, cg_size(p, element)); wa_op(f.code, 0x6c); wa_op(f.code, 0x6a); let address = cg_save(f, wa());
        let live = f.region_live; let acq = f.acquisitions; var regions = -1; if each && m.regions_enabled { regions = cg_mark_regions(f); }
        cg_literal_at(p, m, f, n.first, element, address, replay, in_place);
        if each { if f.acquisitions != acq { cg_restore_regions(f, regions); } f.region_live = live; }
        cg_get(f, index); wa_const(f.code, 1); wa_op(f.code, 0x6a); cg_set(f, index); cg_branch(p, f, again, false); cg_end(f); cg_end(f);
    } else {
        var child = n.first; var ordinal = 0;
        while child >= 0 {
            cg_get(f, destination); wa_const(f.code, ordinal * cg_size(p, element)); wa_op(f.code, 0x6a); let address = cg_save(f, wa());
            cg_literal_at(p, m, f, child, element, address, replay, in_place); if cg_diverges(p, child) { break; } child = p.nodes[child].next; ordinal += 1;
        }
    }
    f.work.resize(mark);
}
recursive fn cg_literal_at(p: Program&, m: CgModule&, f: CgBody&, node: i64, id: i64, destination: i64, captured: i64 = -1, in_place: bool = false) {
    if cg_relative_literal(p, node, id) {
        let n: const Node& = p.nodes[node];
        if n.kind == N_RECORD { cg_record_fields(p, m, f, id, destination, node, captured, in_place); }
        else {
            let count = cg_literal_count(p, m, f, node, captured); cg_check_array_length(p, m, f, id, count, node);
            cg_get(f, count); wa_const(f.code, p.types[id].count); wa_op(f.code, 0x4b); cg_trap_if(p, m, f, node, "limited array capacity exceeded");
            if !in_place { cg_get(f, destination); cg_clear_bytes(p, f, cg_size(p, id)); } var data = destination;
            if p.types[id].array_kind == A_LIMITED { cg_get(f, destination); cg_get(f, count); cg_length_store(p, f, id); cg_get(f, destination); wa_const(f.code, cg_static_prefix(p, id)); wa_op(f.code, 0x6a); data = cg_save(f, wa()); }
            cg_literal_elements(p, m, f, node, p.types[id].element, data, count, captured, in_place);
        }
        return;
    }
    if captured >= 0 { cg_get(f, cg_literal_saved(p, f, captured, node)); }
    else { cg_to(p, m, f, node, id); }
    if !cg_diverges(p, node) { cg_write_value(p, m, f, id, destination, node); }
}
recursive fn cg_record_literal(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n: const Node& = p.nodes[node]; let id = n.type_id;
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
    let n: const Node& = p.nodes[node];
    if n.kind == N_CALL { return (n.flags & F_DISPATCH) == 0 && (n.symbol < 0 || (p.symbols[n.symbol].flags & S_BUILTIN) == 0); }
    return n.kind == N_BLOCK || n.kind == N_IF || n.kind == N_GUARD || n.kind == N_MATCH || n.kind == N_LOOP || n.kind == N_WHILE;
}
fn cg_forward_result_channel(p: Program&, node: i64, ordinal: i64) -> bool {
    if !cg_result_channels(p, node) { return false; }
    if p.nodes[node].kind == N_CALL { return true; }
    return cg_region_value(p, cg_result_at(p, p.nodes[node].type_id, ordinal));
}
fn cg_fixed_result_channel(p: Program&, node: i64) -> bool {
    let n: const Node& = p.nodes[node];
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
        if f.sroa_return > 0 && count == 1 && f.results.len > 0 && first_slot == f.results[0] && p.nodes[item].next < 0 {
            cg_emit_into_sroa(p, m, f, item, id, f.results[0], f.sroa_return, true);
            if cg_diverges(p, item) { return; }
            item = p.nodes[item].next; ordinal += 1; continue;
        }
        if f.direct_return && count == 1 && f.results.len > 0 && first_slot == f.results[0] && p.nodes[item].next < 0 {
            cg_emit_into_dest(p, m, f, item, id, f.destinations[0]);
            if cg_diverges(p, item) { return; }
            item = p.nodes[item].next; ordinal += 1; continue;
        }
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
        // Every aggregate channel owns its value, including the last one.
        // Views of an inline call or a control construct consume this copy.
        if cg_aggregate(p, id) {
            let source = cg_save(f, wa()); let snapshot = cg_temporary(p, f, id);
            if cg_named_owner(p, f, item, id) {
                cg_get(f, snapshot); cg_get(f, source); wa_const(f.code, cg_size(p, id)); wb_copy(f.code);
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
let CG_EFFECT_TARGET: i64 = 2305843009213693952;
fn cg_nonlocal_target(p: Program&, function: i64) -> bool { return function >= 0 && (p.nodes[function].flags & CG_EFFECT_TARGET) != 0; }
fn cg_effect_frame(p: Program&, m: CgModule&, f: CgBody&, target: i64, node: i64) -> i64 {
    // An effect record: word 0 the previous one, word 1 the function number.
    wb_op(f.code, 0x23, 4); let frame = cg_save(f, wa());
    let found = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
    cg_get(f, frame); wa_op(f.code, 0x45); cg_trap_if(p, m, f, node, "nonlocal return target is no longer active");
    cg_get(f, frame); wa_load(f.code, ww(1)); wa_const(f.code, target + 1); wa_op(f.code, 0x46); cg_branch(p, f, found, true);
    cg_get(f, frame); wa_load(f.code, 0); cg_set(f, frame); cg_branch(p, f, again, false); cg_end(f); cg_end(f); return frame;
}
recursive fn cg_emit_return(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n: const Node& = p.nodes[node]; var target = f.function;
    if n.symbol >= 0 && n.symbol < p.symbols.len && (p.symbols[n.symbol].flags & S_FUNCTION) != 0 { target = p.symbols[n.symbol].node; }
    if target == f.function {
        var first_slot = -1; if f.results.len > 0 { first_slot = f.results[0]; }
        cg_set_values(p, m, f, n.first, cg_result_type(p, f.function), first_slot, node);
        // The value is built at its destination, then the defers run.
        cg_run_defers(p, m, f, 0);
        cg_branch(p, f, f.done, false); return;
    }
    if !m.nonlocal_returns { cg_fail(p, node, "missing nonlocal return in effect scan"); return; }
    let target_type = cg_result_type(p, target); let count = cg_result_count(p, target_type);
    let frame = cg_effect_frame(p, m, f, target, node); let first_slot = cg_control_slots(p, f, target_type, node);
    let attempt_mark = f.work.len;
    for ordinal in 0..count {
        let id = cg_result_at(p, target_type, ordinal); var stage = -1; var start = -1;
        if m.regions_enabled && cg_region_value(p, id) {
            let metadata = cg_owned_effect_metadata(p, target_type) + ordinal * ww(3);
            cg_get(f, frame); wa_load(f.code, metadata); let original = cg_save(f, wa());
            let original_tail = cg_region_header(p, f, id, original); start = cg_region_cursor(f, original_tail);
            cg_get(f, frame); wa_load(f.code, metadata + ww(2)); let entry = cg_save(f, wa());
            let receiver = cg_destination(f, id, original, CG_CALLER, false, false, false, entry, -1);
            let receiving = cg_share_destination(p, m, f, receiver, id, false, false, true, node); stage = f.construction_destinations[receiving].header;
            f.receiving.push(CgReceiving { slot: first_slot, ordinal: ordinal, destination: receiving });
        } else if cg_fixed_relative(p, id) {
            let metadata = cg_owned_effect_metadata(p, target_type) + ordinal * ww(3);
            cg_get(f, frame); wa_load(f.code, metadata); let original = cg_save(f, wa());
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
        cg_get(f, frame); wa_const(f.code, offset); wa_op(f.code, 0x6a); let destination = cg_save(f, wa());
        if f.work[attempt_mark + ordinal * 2] >= 0 { cg_get(f, destination); cg_get(f, f.work[attempt_mark + ordinal * 2]); wa_const(f.code, cg_size(p, id)); wb_copy(f.code); }
        else { cg_get(f, first_slot + ordinal); cg_write_value(p, m, f, id, destination, node); }
        offset += cg_size(p, id);
    }
    for ordinal in 0..count {
        if f.work[attempt_mark + ordinal * 2 + 1] >= 0 { cg_get(f, frame); cg_get(f, f.work[attempt_mark + ordinal * 2 + 1]); wa_store(f.code, cg_owned_effect_metadata(p, target_type) + ordinal * ww(3) + ww(1)); }
    }
    // The values are in the target's channels; this frame's defers run before
    // the return is set in flight.
    f.work.resize(attempt_mark); cg_run_defers(p, m, f, 0); cg_get(f, frame); wb_op(f.code, 0x24, 2); cg_branch(p, f, f.done, false);
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
    let source = f.construction_destinations[temporary].header; cg_owner_read_length(p, m, f, source, node); let count = cg_save(f, wa());
    cg_owner_read_capacity(p, m, f, header); let capacity = cg_save(f, wa()); cg_get(f, count); cg_get(f, capacity); wa_op(f.code, 0x4b); cg_trap_if(p, m, f, node, "limited array capacity exceeded");
    cg_owner_read_base(p, m, f, source, node); let source_base = cg_save(f, wa()); cg_owner_read_base(p, m, f, header, node); let base = cg_save(f, wa());
    let element = p.types[id].element; var bytes = -1;
    if p.types[element].storage == 1 {
        cg_get(f, count); wa_extend(f.code); let wide = cg_save(f, 0x7e); let end = cg_walk_elements(p, m, f, source_base, wide, node);
        cg_get(f, end); cg_get(f, source_base); wa_op(f.code, 0x6b); bytes = cg_save(f, wa());
    } else { cg_get(f, count); wa_const(f.code, cg_size(p, element)); wa_op(f.code, 0x6c); bytes = cg_save(f, wa()); }
    cg_get(f, base); wa_extend(f.code); cg_get(f, bytes); wa_extend(f.code); wb_byte(f.code, 0x7c); let end = cg_save(f, 0x7e);
    cg_get(f, end); cg_get(f, header); wc_load(f.code, 2); wa_extend(f.code); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array image exceeds data region");
    cg_get(f, end); wa_wrap(f.code); let copied_end = cg_save(f, wa()); cg_ensure_memory(p, m, f, copied_end, node);
    cg_get(f, base); cg_get(f, source_base); cg_get(f, bytes); wb_copy(f.code); cg_owner_set_length(p, m, f, header, count, node);
    if p.types[element].storage == 1 { cg_region_publish(f, header, copied_end); }
    else { cg_get(f, base); cg_get(f, capacity); wa_const(f.code, cg_size(p, element)); wa_op(f.code, 0x6c); wa_op(f.code, 0x6a); let top = cg_save(f, wa()); cg_region_publish(f, header, top); }
}
recursive fn cg_assign(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n: const Node& = p.nodes[node]; var id = p.nodes[n.left].type_id;
    var symbol = -1;
    if p.nodes[n.left].kind == N_NAME { symbol = p.nodes[n.left].symbol; }
    if symbol >= 0 && symbol < f.slots.len && f.slots[symbol].sroa_count > 0 && n.integer == T_ASSIGN {
        let sc: i64 = f.slots[symbol].sroa_count;
        cg_emit_into_sroa(p, m, f, n.right, id, f.slots[symbol].local, sc, false);
        return;
    }
    var value = false; var value_local = -1;
    if symbol >= 0 && symbol < f.slots.len && f.slots[symbol].value && (cg_type_kind(p, id) != TY_REF || n.integer == T_DOTASSIGN) {
        value = true; value_local = f.slots[symbol].local;
    } else if p.nodes[n.left].kind == N_MEMBER && (cg_type_kind(p, id) != TY_REF || n.integer == T_DOTASSIGN) {
        let ml = p.nodes[n.left].left;
        if ml >= 0 && p.nodes[ml].kind == N_NAME {
            let msym = p.nodes[ml].symbol;
            if msym >= 0 && msym < f.slots.len && f.slots[msym].sroa_count > 0 {
                let fi = cg_sroa_field_index(p, p.symbols[msym].type_id, p.nodes[n.left].symbol);
                if fi >= 0 { value = true; value_local = f.slots[msym].local + fi; }
            }
        }
    }
    var address = -1; var member_offset = -1;
    if !value {
        if cg_type_kind(p, id) == TY_REF && n.integer != T_DOTASSIGN { cg_expr(p, m, f, n.left); id = p.types[id].element; }
        else {
            if p.nodes[n.left].kind == N_MEMBER { member_offset = cg_member_memory_offset(p, m, n.left, id); }
            if member_offset > 0 { cg_member_object(p, m, f, n.left); }
            else { cg_address(p, m, f, n.left); }
        }
        address = cg_save(f, wa());
    }
    if (n.integer == T_ASSIGN || n.integer == T_DOTASSIGN) && cg_fixed_relative(p, id) {
        cg_fixed_to(p, m, f, n.right, id, address); return;
    }
    if m.regions_enabled && (n.integer == T_ASSIGN || n.integer == T_DOTASSIGN) && cg_region_value(p, id) {
        if cg_owner(p, id) && p.types[id].array_kind == A_LIMITED { cg_region_limited_assignment(p, m, f, node, id, address); return; }
        let header = cg_region_header(p, f, id, address);
        if cg_frame_owner(p, id) || p.types[id].array_kind == A_GROW || p.types[id].array_kind == A_GROWSHRINK {
            cg_owner_read_base(p, m, f, header, node); let base = cg_save(f, wa()); cg_region_publish(f, header, base);
        }
        let entry = cg_region_cursor(f, header); let receiving = cg_destination(f, id, address, CG_EXISTING, false, false, false, entry, -1);
        cg_construct_region(p, m, f, n.right, receiving); return;
    }
    if (n.integer == T_ASSIGN || n.integer == T_DOTASSIGN) && cg_owner(p, id) && p.types[id].array_kind == A_LIMITED {
        cg_expr(p, m, f, n.right); cg_pack_view(p, m, f, p.nodes[n.right].type_id, node); let view = cg_save(f, ws());
        cg_get(f, view); ws_len(f.code); let count = cg_save(f, wa());
        cg_get(f, count); cg_owner_read_capacity(p, m, f, address); wa_op(f.code, 0x4b); cg_trap_if(p, m, f, node, "limited array capacity exceeded");
        cg_owner_read_base(p, m, f, address, node); cg_get(f, view); ws_ptr(f.code); cg_get(f, count); wa_const(f.code, cg_size(p, p.types[id].element)); wa_op(f.code, 0x6c); wb_copy(f.code);
        cg_owner_set_length(p, m, f, address, count, node); return;
    }
    if !value && n.integer == T_ASSIGN && m.resolver < 0 && m.prefix_helper < 0 && cg_plain_fixed_aggregate(p, id) &&
       n.right >= 0 && p.nodes[n.right].type_id == id {
        if p.nodes[n.right].kind == N_NAME && p.nodes[n.right].symbol >= 0 && p.nodes[n.right].symbol < f.slots.len && f.slots[p.nodes[n.right].symbol].sroa_count > 0 {
            cg_sroa_store_to_addr(p, f, id, f.slots[p.nodes[n.right].symbol].local, address); return;
        }
        if cg_call_sroa_return(p, m, n.right) > 0 {
            cg_emit_into_dest(p, m, f, n.right, id, address); return;
        }
        if p.optimization >= 2 && p.nodes[n.right].kind == N_RECORD && !cg_record_has_self(p, n.right) && !cg_record_has_extern(p, n.right) {
            let sc = cg_sroa_struct(p, id);
            if sc > 0 {
                let first_tmp = cg_sroa_alloc_locals(p, f, id);
                cg_emit_into_sroa(p, m, f, n.right, id, first_tmp, sc, true);
                if !cg_diverges(p, n.right) { cg_sroa_store_to_addr(p, f, id, first_tmp, address); }
                return;
            }
        }
    }
    if n.integer != T_ASSIGN && n.integer != T_DOTASSIGN {
        if value { cg_get(f, value_local); }
        else if member_offset > 0 { cg_get(f, address); cg_load_fixed(p, f.code, id, member_offset); }
        else { cg_get(f, address); cg_load(p, m, f, id, 0); }
        if n.integer == T_INC || n.integer == T_DEC {
            let w = cg_wasm_type(p, id);
            if w == 0x7d { wb_f32(f.code, 1.0); } else if w == 0x7c { wb_f64(f.code, 1.0); }
            else if w == 0x7e { wb_i64(f.code, 1); } else { wb_i32(f.code, 1); }
        } else { cg_to(p, m, f, n.right, id); }
        cg_numeric(p, m, f, cg_assignment_operator(n.integer), id, node);
    } else { cg_to(p, m, f, n.right, id); }
    if p.types[id].storage == 1 { cg_fail(p, node, "wasm: encoded element replacement requires a size-preserving image edit"); return; }
    if value { cg_sroa_field_store(p, f, id, value_local); }
    else if member_offset > 0 {
        let stored_val = cg_save(f, cg_wasm_type(p, id));
        cg_get(f, address); cg_get(f, stored_val);
        if !cg_store(p, f.code, id, member_offset) { cg_fail(p, node, "wasm: unsupported stored value type"); }
    } else { cg_write_value(p, m, f, id, address, node); }
}
// The byte offset of a control word a caller names by its narrow offset (0 or
// 4, the base and the raw length) or by ww(k).
inline fn wB_control_offset(offset: i64) -> i64 { if cg_wide && offset == 4 { return 8; } return offset; }
// Replaces the pointer of the slice on the stack with the address in a local.
fn wB_slice_repoint(f: CgBody&, pointer: i64) {
    if cg_wide { cg_get(f, pointer); wb_byte(f.code, 0xfd); wb_u(f.code, 0x1e); wb_byte(f.code, 0); return; }
    wb_i64(f.code, -4294967296); wb_byte(f.code, 0x83); cg_get(f, pointer); wb_byte(f.code, 0xad); wb_byte(f.code, 0x84);
}
fn cg_mark_publications(m: CgModule&, f: CgBody&) -> i64 {
    if !m.regions_enabled { return -1; } wb_op(f.code, 0x23, 11); return cg_save(f, wa());
}
fn cg_restore_publications(f: CgBody&, mark: i64) { if mark >= 0 { cg_get(f, mark); wb_op(f.code, 0x24, 11); } }
fn cg_publish_header(m: CgModule&, f: CgBody&, header: i64, word: i64) {
    if m.header_helper >= 0 { cg_get(f, header); wa_const(f.code, wB_control_offset(word)); wb_op(f.code, 0x10, m.header_helper); }
}
fn cg_canonical_address(m: CgModule&, f: CgBody&, bytes: i64) {
    if m.prefix_helper >= 0 && bytes > 0 { wa_const(f.code, bytes); wb_op(f.code, 0x10, m.prefix_helper); }
}
fn cg_map_frame(p: Program&, m: CgModule&, f: CgBody&, source: i64, target: i64, prefix: i64) -> i64 {
    // A publication record is six address-sized words: the previous record,
    // the source, the target, the mapped prefix bytes twice, the mode.
    f.publishes = true; m.maps_headers = true;
    let previous = cg_mark_publications(m, f); let offset = cg_frame(f, ww(6), wa_bytes()); cg_frame_address(f, offset); let entry = cg_save(f, wa());
    cg_get(f, entry); cg_get(f, previous); wa_store(f.code, 0);
    cg_get(f, entry); cg_get(f, source); wa_store(f.code, ww(1));
    cg_get(f, entry); cg_get(f, target); wa_store(f.code, ww(2));
    for word in [3, 4] { cg_get(f, entry); wa_const(f.code, prefix); wa_store(f.code, ww(word)); }
    cg_get(f, entry); wa_const(f.code, 1); wa_store(f.code, ww(5));
    cg_get(f, entry); wb_op(f.code, 0x24, 11); return previous;
}
fn cg_map_header(p: Program&, m: CgModule&, f: CgBody&, source: i64, target: i64) -> i64 {
    let previous = cg_map_frame(p, m, f, source, target, 0); wb_op(f.code, 0x23, 11); wa_const(f.code, 0); wa_store(f.code, ww(5)); return previous;
}
fn cg_header_publish_body(out: u8[>..]&) {
    // (header,word)->void; follow scoped array/frame publication channels.
    // Both parameters and both locals are address-sized; word is the byte
    // offset of a control word, 0 or ww(1).
    wb_u(out, 1); wb_u(out, 2); wb_byte(out, wa());
    wb_byte(out, 0x02); wb_byte(out, 0x40); wb_byte(out, 0x03); wb_byte(out, 0x40);
    wb_op(out, 0x23, 11); wb_op(out, 0x21, 2); wb_byte(out, 0x03); wb_byte(out, 0x40);
    wb_op(out, 0x20, 2); wa_op(out, 0x45); wb_op(out, 0x0d, 2);
    wb_op(out, 0x20, 0); wb_op(out, 0x20, 2); wa_load(out, ww(1)); wb_op(out, 0x20, 2); wa_load(out, ww(4)); wa_op(out, 0x6a); wa_op(out, 0x46);
    wb_op(out, 0x20, 1); wa_const(out, ww(1)); wa_op(out, 0x46);
    wb_op(out, 0x20, 1); wa_op(out, 0x45); wb_op(out, 0x20, 2); wa_load(out, ww(5)); wa_truth(out); wb_byte(out, 0x71); wb_byte(out, 0x72); wb_byte(out, 0x71); wb_byte(out, 0x04); wb_byte(out, 0x40);
    wb_op(out, 0x20, 2); wa_load(out, ww(2)); wb_op(out, 0x20, 2); wa_load(out, ww(4)); wa_op(out, 0x6a); wb_op(out, 0x21, 3);
    wb_op(out, 0x20, 3); wb_op(out, 0x20, 1); wa_op(out, 0x6a); wb_op(out, 0x20, 0); wb_op(out, 0x20, 1); wa_op(out, 0x6a); wa_load(out, 0); wa_store(out, 0);
    wb_op(out, 0x20, 3); wb_op(out, 0x21, 0); wb_op(out, 0x0c, 2); wb_byte(out, 0x0b);
    wb_op(out, 0x20, 2); wa_load(out, 0); wb_op(out, 0x21, 2); wb_op(out, 0x0c, 0);
    wb_byte(out, 0x0b); wb_byte(out, 0x0b); wb_byte(out, 0x0b); wb_byte(out, 0x0b);
}
fn cg_prefix_mapping_body(out: u8[>..]&) {
    // (address,bytes)->address; a fixed access must fit the complete mapped prefix.
    // Both parameters, the result and both locals are address-sized.
    wb_u(out, 1); wb_u(out, 2); wb_byte(out, wa());
    wb_byte(out, 0x02); wb_byte(out, 0x40); wb_byte(out, 0x03); wb_byte(out, 0x40);
    wb_op(out, 0x23, 11); wb_op(out, 0x21, 2); wb_byte(out, 0x03); wb_byte(out, 0x40);
    wb_op(out, 0x20, 2); wa_op(out, 0x45); wb_op(out, 0x0d, 2);
    wb_op(out, 0x20, 2); wa_load(out, ww(3)); wa_truth(out); wb_byte(out, 0x04); wb_byte(out, 0x40);
    wb_op(out, 0x20, 2); wa_load(out, ww(1)); wb_op(out, 0x21, 3);
    wb_op(out, 0x20, 0); wb_op(out, 0x20, 3); wa_op(out, 0x4f);
    wb_op(out, 0x20, 0); wa_extend(out); wb_op(out, 0x20, 1); wa_extend(out); wb_byte(out, 0x7c);
    wb_op(out, 0x20, 3); wa_extend(out); wb_op(out, 0x20, 2); wa_load(out, ww(3)); wa_extend(out); wb_byte(out, 0x7c); wb_byte(out, 0x58); wb_byte(out, 0x71); wb_byte(out, 0x04); wb_byte(out, 0x40);
    wb_op(out, 0x20, 2); wa_load(out, ww(2)); wb_op(out, 0x20, 0); wb_op(out, 0x20, 3); wa_op(out, 0x6b); wa_op(out, 0x6a); wb_op(out, 0x21, 0); wb_op(out, 0x0c, 3);
    wb_byte(out, 0x0b); wb_byte(out, 0x0b);
    wb_op(out, 0x20, 2); wa_load(out, 0); wb_op(out, 0x21, 2); wb_op(out, 0x0c, 0);
    wb_byte(out, 0x0b); wb_byte(out, 0x0b); wb_byte(out, 0x0b); wb_op(out, 0x20, 0); wb_byte(out, 0x0b);
}
fn cg_mark_regions(f: CgBody&) -> i64 { cg_record(f, 0x23, 3); wb_op(f.code, 0x23, 3); return cg_save(f, 0x7f); }
fn cg_restore_regions(f: CgBody&, mark: i64) { if mark >= 0 { cg_get(f, mark); cg_record(f, 0x24, 3); wb_op(f.code, 0x24, 3); } }
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
        let n: const Node& = p.nodes[binding]; let receiving = cg_receiving(f, first_slot, n.integer);
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
        prefix = cg_temporary(p, f, id); cg_get(f, prefix); cg_clear_bytes(p, f, wc_bytes());
        for word in [0, 2] { cg_get(f, prefix); cg_get(f, target.header); wc_load(f.code, word); wc_store(f.code, word); }
        receiving = cg_destination(f, id, prefix, target.lifetime, false, false, false, target.entry, target.construction);
    }
    let saved_node = f.active_node; let saved_destination = f.active_destination; let saved_raw = f.raw_node;
    f.active_node = node; f.active_destination = receiving; f.raw_node = -1;
    wa_const(f.code, 0); let zero = cg_save(f, wa()); cg_region_array_prefix(p, m, f, id, prefix, zero, zero, node);
    f.active_node = saved_node; f.active_destination = saved_destination; f.raw_node = saved_raw;
    f.receiving.push(CgReceiving { slot: -1, ordinal: 0, destination: named, symbol: symbol, prefix: prefix });
}
recursive fn cg_region_declaration(p: Program&, m: CgModule&, f: CgBody&, node: i64, binding: i64) {
    let n: const Node& = p.nodes[node]; let symbol = p.nodes[binding].symbol; let id = p.symbols[symbol].type_id;
    cg_symbol_address(p, m, f, symbol, binding); let address = cg_save(f, wa()); let global = m.global_regions[symbol];
    let named = cg_named_array_destination(p, f, symbol); var receiving = -1;
    if named >= 0 {
        let target = f.construction_destinations[named]; f.constructions[target.construction].open += 1;
        cg_prepare_named_prefix(p, m, f, node, symbol, named);
        if (p.types[id].array_kind == A_VAR || p.types[id].array_kind == A_LIMITED || cg_image_owner(p, id) || cg_enum_image(p, id)) && !cg_nonlocal_target(p, f.function) {
            cg_get(f, target.header); cg_set(f, f.slots[symbol].local); cg_get(f, target.header); cg_set(f, address);
        } else {
            let source_header = cg_region_header(p, f, id, target.header); let header = cg_region_header(p, f, id, address); let cursor = cg_region_cursor(f, source_header);
            cg_get(f, header); cg_clear_bytes(p, f, wc_bytes());
            cg_get(f, header); cg_get(f, cursor); wc_store(f.code, 0);
            cg_get(f, header); cg_get(f, source_header); wc_load(f.code, 2); wc_store(f.code, 2);
            if cg_enum_image(p, id) { cg_set_enum_anchor(f, address, cursor); }
            else if cg_image_owner(p, id) { cg_set_record_anchor(p, m, f, id, address, cursor, node); }
        }
        receiving = cg_destination(f, id, address, target.lifetime, false, false, false, target.entry, target.construction);
    } else {
        let header = cg_region_acquire(p, m, f, id, address, global, binding); let entry = cg_region_cursor(f, header);
        var lifetime = CG_BLOCK_OWNER; if global >= 0 { lifetime = CG_STATIC; }
        receiving = cg_destination(f, id, address, lifetime, false, false, false, entry, -1);
    }
    let keep = f.region_live; let acq = f.acquisitions; let mark = cg_mark_regions(f);
    if n.right >= 0 { cg_construct_region(p, m, f, n.right, receiving); }
    else if cg_frame_owner(p, id) || cg_image_owner(p, id) || cg_enum_image(p, id) { cg_construct_region(p, m, f, -1, receiving); }
    else {
        let saved_node = f.active_node; let saved_destination = f.active_destination; f.active_node = node; f.active_destination = receiving;
        wa_const(f.code, 0); let count = cg_save(f, wa()); cg_region_owner_image(p, m, f, id, address, count, count, node);
        f.active_node = saved_node; f.active_destination = saved_destination;
    }
    if f.acquisitions != acq { cg_restore_regions(f, mark); }
    f.region_live = keep;
}
// A root owner's declaration builds each component in its place in the
// owner's frame, in field order. A component that owns storage takes its own
// region (a dedicated one for a global) and is constructed there as its own
// declaration would be, so it grows independently and pool-relative `self` in
// its initializer names that component's storage. A fixed component is
// stored, an encoded scalar in its encoding.
recursive fn cg_root_declaration(p: Program&, m: CgModule&, f: CgBody&, node: i64, binding: i64) {
    let symbol = p.nodes[binding].symbol; let id = p.symbols[symbol].type_id; let init = p.nodes[node].right;
    if init >= 0 && p.nodes[init].kind != N_RECORD { cg_fail(p, node, "wasm: a root owner is constructed by its record literal at its declaration"); return; }
    cg_symbol_address(p, m, f, symbol, binding); let owner = cg_save(f, wa());
    cg_get(f, owner); cg_clear_bytes(p, f, cg_size(p, id));
    var region = m.global_regions[symbol]; var field = p.types[id].first;
    while field >= 0 {
        let n: const Node& = p.nodes[field];
        if (n.flags & F_PAD) != 0 { field = n.next; continue; }
        let value = cg_record_initializer(p, init, field); let component = n.type_id;
        cg_get(f, owner); wa_add(f.code, n.integer); let address = cg_save(f, wa());
        if m.regions_enabled && cg_region_value(p, component) {
            let header = cg_region_acquire(p, m, f, component, address, region, binding); let entry = cg_region_cursor(f, header);
            var lifetime = CG_BLOCK_OWNER; if region >= 0 { lifetime = CG_STATIC; }
            let receiving = cg_destination(f, component, address, lifetime, false, false, false, entry, -1);
            let keep = f.region_live; let acq = f.acquisitions; let mark = cg_mark_regions(f);
            if value >= 0 { cg_construct_region(p, m, f, value, receiving); }
            else if cg_frame_owner(p, component) || cg_image_owner(p, component) || cg_enum_image(p, component) { cg_construct_region(p, m, f, -1, receiving); }
            else {
                let saved_node = f.active_node; let saved_destination = f.active_destination; f.active_node = node; f.active_destination = receiving;
                wa_const(f.code, 0); let count = cg_save(f, wa()); cg_region_owner_image(p, m, f, component, address, count, count, node);
                f.active_node = saved_node; f.active_destination = saved_destination;
            }
            if f.acquisitions != acq { cg_restore_regions(f, mark); }
            f.region_live = keep;
        } else if value >= 0 && cg_fixed_relative(p, component) { cg_fixed_to(p, m, f, value, component, address); }
        else if value >= 0 {
            cg_to(p, m, f, value, component);
            if !cg_diverges(p, value) {
                if p.types[component].storage == 1 { let encoded = cg_save(f, 0x7e); cg_write_varint(p, f, address, encoded); }
                else { cg_write_value(p, m, f, component, address, binding); }
            }
        } else { cg_default_storage(p, m, f, component, address, binding); }
        if value >= 0 && cg_diverges(p, value) { return; }
        if region >= 0 && cg_has_owner(p, component) { region += 1; }
        field = n.next;
    }
}
fn cg_decl_diverges(p: Program&, node: i64) -> bool {
    if node < 0 { return false; } let n: const Node& = p.nodes[node]; if cg_diverges(p, node) { return true; }
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
    let n: const Node& = p.nodes[node]; var binding = node; if n.first >= 0 { binding = n.first; }
    let first = n.right;
    if first >= 0 && p.nodes[first].next < 0 && cg_diverges(p, first) {
        if m.regions_enabled && p.nodes[binding].symbol >= 0 && cg_region_value(p, p.symbols[p.nodes[binding].symbol].type_id) && (n.first < 0 || p.nodes[binding].next < 0) { cg_region_declaration(p, m, f, node, binding); }
        else { cg_expr(p, m, f, first); } return;
    }
    var value = first;
    while binding >= 0 && value >= 0 {
        if cg_diverges(p, value) { cg_expr(p, m, f, value); return; }
        let symbol = p.nodes[binding].symbol;
        if symbol >= 0 && symbol < f.slots.len && f.slots[symbol].value {
            cg_to(p, m, f, value, p.symbols[symbol].type_id); cg_scalar_slot_store(p, f, symbol);
        } else if symbol >= 0 && symbol < f.slots.len && f.slots[symbol].sroa_count > 0 {
            let sc: i64 = f.slots[symbol].sroa_count;
            cg_emit_into_sroa(p, m, f, value, p.symbols[symbol].type_id, f.slots[symbol].local, sc, true);
        } else {
            cg_symbol_address(p, m, f, symbol, binding); let address = cg_save(f, wa());
            cg_to(p, m, f, value, p.symbols[symbol].type_id); cg_write_value(p, m, f, p.symbols[symbol].type_id, address, binding);
        }
        binding = p.nodes[binding].next; value = p.nodes[value].next;
    }
}
inline fn cg_binding_result_type(first: i64) -> i64 { return -2 - first; }
recursive fn cg_region_multi_declaration(p: Program&, m: CgModule&, f: CgBody&, node: i64) -> i64 {
    let n: const Node& = p.nodes[node]; let result_type = cg_binding_result_type(n.first); var binding = n.first; var first_slot = -1; var ordinal = 0;
    while binding >= 0 { let slot = cg_local(f, cg_wasm_type(p, p.nodes[binding].type_id)); if first_slot < 0 { first_slot = slot; } binding = p.nodes[binding].next; }
    binding = n.first;
    while binding >= 0 {
        let id = p.nodes[binding].type_id;
        if cg_region_value(p, id) {
            cg_symbol_address(p, m, f, p.nodes[binding].symbol, binding); let owner = cg_save(f, wa()); let header = cg_region_acquire(p, m, f, id, owner, -1, binding); let entry = cg_region_cursor(f, header);
            let receiving = cg_destination(f, id, owner, CG_BLOCK_OWNER, false, false, false, entry, -1); f.receiving.push(CgReceiving { slot: first_slot, ordinal: ordinal, destination: receiving });
        }
        ordinal += 1; binding = p.nodes[binding].next;
    }
    let live = f.region_live; let acq = f.acquisitions; let mark = cg_mark_regions(f); cg_set_values(p, m, f, n.right, result_type, first_slot, node);
    binding = n.first; ordinal = 0;
    while binding >= 0 {
        let id = p.nodes[binding].type_id;
        if !cg_region_value(p, id) {
            let sym = p.nodes[binding].symbol;
            if sym >= 0 && sym < f.slots.len && f.slots[sym].value { cg_get(f, first_slot + ordinal); cg_scalar_slot_store(p, f, sym); }
            else if sym >= 0 && sym < f.slots.len && f.slots[sym].sroa_count > 0 { cg_sroa_load_from_addr(p, f, id, first_slot + ordinal, f.slots[sym].local); }
            else { cg_symbol_address(p, m, f, sym, binding); let address = cg_save(f, wa()); cg_get(f, first_slot + ordinal); cg_write_value(p, m, f, id, address, binding); }
        }
        ordinal += 1; binding = p.nodes[binding].next;
    }
    if f.acquisitions != acq { cg_restore_regions(f, mark); }
    f.region_live = live; return 0;
}
recursive fn cg_declaration(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    cg_declaration_body(p, m, f, node);
    if m.pool_global < 0 || cg_decl_diverges(p, node) || (p.nodes[node].flags & F_REUSABLE) == 0 { return; }
    var binding = node; if p.nodes[node].first >= 0 { binding = p.nodes[node].first; }
    while binding >= 0 {
        let symbol = p.nodes[binding].symbol;
        if symbol >= 0 {
            cg_symbol_address(p, m, f, symbol, node); let header = cg_save(f, wa()); let state = cg_pool_state(p, m, f, header, node);
            cg_get(f, state); wa_const(f.code, 0); wa_store(f.code, ww(3));
        }
        if binding == node { break; } binding = p.nodes[binding].next;
    }
}
recursive fn cg_declaration_body(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n: const Node& = p.nodes[node];
    if n.first < 0 && n.symbol >= 0 && root_struct_type(p, p.symbols[n.symbol].type_id) { cg_root_declaration(p, m, f, node, node); return; }
    if cg_decl_diverges(p, node) { cg_divergent_declaration(p, m, f, node); return; }
    if m.regions_enabled {
        if n.first >= 0 && p.nodes[n.first].next >= 0 { cg_region_multi_declaration(p, m, f, node); return; }
        var binding = node; if n.first >= 0 && p.nodes[n.first].next < 0 { binding = n.first; }
        let symbol = p.nodes[binding].symbol;
        if symbol >= 0 && cg_region_value(p, p.symbols[symbol].type_id) { cg_region_declaration(p, m, f, node, binding); return; }
    }
    // A plain declaration's value lies outside the regions its initializer
    // acquires. Unless it can hold a reference it keeps none of them (a
    // declaration cannot bind a view of a statement temporary, §9.2), so
    // they are released after it, as after any other statement
    // (cg_statement) and as native C does (cc_variable): a later recursive
    // call does not retain them.
    let live = f.region_live; let acq = f.acquisitions; var mark = -1;
    if m.regions_enabled && n.right >= 0 && cg_may_region(p, m, node) && !cg_declaration_borrows(p, node) { mark = cg_mark_regions(f); }
    cg_plain_declaration(p, m, f, node);
    if mark >= 0 {
        if f.acquisitions != acq { cg_restore_regions(f, mark); }
        f.region_live = live;
    }
}
// Whether a declared binding's type may hold a reference, slice or function
// value, in any element or field (cc_frame_borrows); an unknown type may.
fn cg_declaration_borrows(p: Program&, node: i64) -> bool {
    let n: const Node& = p.nodes[node]; var pending: i64[>..] = []; var seen: i64[>..] = [];
    if n.first < 0 { pending.push(n.type_id); if n.symbol >= 0 { pending.push(p.symbols[n.symbol].type_id); } }
    var binding = n.first; while binding >= 0 { pending.push(p.nodes[binding].type_id); binding = p.nodes[binding].next; }
    while pending.len > 0 {
        let current = pending.pop(); if current < 0 || current >= p.types.len { return true; }
        var visited = false; for old in seen { if old == current { visited = true; break; } } if visited { continue; } seen.push(current);
        let t: const Type& = p.types[current];
        if t.kind == TY_REF || t.kind == TY_SLICE || t.kind == TY_FN { return true; }
        if t.kind == TY_ARRAY { pending.push(t.element); }
        else if t.kind == TY_STRUCT || t.kind == TY_ENUM || t.kind == TY_TUPLE {
            var field = t.first; while field >= 0 { if (p.nodes[field].flags & F_PAD) == 0 { pending.push(p.nodes[field].type_id); } field = p.nodes[field].next; }
        }
    }
    return false;
}
recursive fn cg_plain_declaration(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n: const Node& = p.nodes[node];
    if n.first >= 0 {
        var binding = n.first; var first_slot = -1;
        while binding >= 0 {
            let slot = cg_local(f, cg_wasm_type(p, p.nodes[binding].type_id));
            if first_slot < 0 { first_slot = slot; } binding = p.nodes[binding].next;
        }
        if n.right >= 0 && cg_type_kind(p, p.nodes[n.right].type_id) == TY_TUPLE {
            cg_set_values(p, m, f, n.right, cg_binding_result_type(n.first), first_slot, node);
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
            let sym = p.nodes[binding].symbol;
            let tid = p.nodes[binding].type_id;
            if sym >= 0 && sym < f.slots.len && f.slots[sym].value {
                if n.right < 0 { cg_zero(f.code, cg_wasm_type(p, tid)); }
                else { cg_get(f, first_slot + ordinal); }
                cg_scalar_slot_store(p, f, sym);
            } else if sym >= 0 && sym < f.slots.len && f.slots[sym].sroa_count > 0 {
                if n.right < 0 { cg_sroa_zero(p, f, tid, f.slots[sym].local); }
                else { cg_sroa_load_from_addr(p, f, tid, first_slot + ordinal, f.slots[sym].local); }
            } else {
                cg_symbol_address(p, m, f, sym, binding); let address = cg_save(f, wa());
                if n.right < 0 { cg_default_storage(p, m, f, tid, address, binding); }
                else { cg_get(f, first_slot + ordinal); cg_write_value(p, m, f, tid, address, binding); }
            }
            binding = p.nodes[binding].next; ordinal++;
        }
        return;
    }
    let symbol = n.symbol;
    if symbol < 0 { cg_fail(p, node, "wasm: declaration has no symbol"); return; }
    if symbol < f.slots.len && f.slots[symbol].value {
        if n.right < 0 { cg_zero(f.code, cg_wasm_type(p, n.type_id)); } else { cg_to(p, m, f, n.right, n.type_id); }
        cg_scalar_slot_store(p, f, symbol); return;
    }
    if symbol < f.slots.len && f.slots[symbol].sroa_count > 0 {
        let sc: i64 = f.slots[symbol].sroa_count;
        cg_emit_into_sroa(p, m, f, n.right, n.type_id, f.slots[symbol].local, sc, true);
        return;
    }
    cg_symbol_address(p, m, f, symbol, node); let address = cg_save(f, wa());
    if n.right < 0 { cg_default_storage(p, m, f, n.type_id, address, node); return; }
    if m.resolver < 0 && (p.symbols[symbol].flags & S_GLOBAL) == 0 && cg_plain_fixed_aggregate(p, n.type_id) {
        cg_emit_into_dest(p, m, f, n.right, n.type_id, address); return;
    }
    cg_to(p, m, f, n.right, n.type_id); cg_write_value(p, m, f, n.type_id, address, node);
}
recursive fn cg_break(p: Program&, m: CgModule&, f: CgBody&, node: i64, continuing: bool) {
    let n: const Node& = p.nodes[node]; var at = f.exits.len;
    while at > 0 {
        at--; let exit = f.exits[at];
        if n.symbol >= 0 && exit.node != n.symbol { continue; }
        if continuing {
            if exit.again < 0 { continue; }
            cg_run_defers(p, m, f, exit.defers);
            if exit.scratch >= 0 { cg_get(f, exit.scratch); wb_op(f.code, 0x24, 0); }
            cg_restore_regions(f, exit.regions); cg_restore_publications(f, exit.publication);
            cg_branch(p, f, exit.again, false); return;
        }
        if n.left >= 0 { cg_set_values(p, m, f, n.left, exit.type_id, exit.result, node); }
        cg_run_defers(p, m, f, exit.defers);
        if exit.scratch >= 0 { cg_get(f, exit.scratch); wb_op(f.code, 0x24, 0); }
        cg_restore_regions(f, exit.regions); cg_restore_publications(f, exit.publication);
        cg_branch(p, f, exit.label, false); return;
    }
    cg_fail(p, node, "wasm: loop or block exit has no active target");
}
fn cg_inline_argument(p: Program&, node: i64) -> bool {
    if node < 0 { return false; } let n: const Node& = p.nodes[node];
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
    let n: const Node& = p.nodes[node]; var child = n.first;
    if (n.flags & F_EARLY) != 0 && n.origin >= 0 {
        while cg_inline_argument(p, child) { child = p.nodes[child].next; }
    }
    let live = f.region_live; let acquisitions = f.acquisitions; var region_mark = -1;
    if m.regions_enabled && cg_may_region(p, m, node) { region_mark = cg_mark_regions(f); }
    let defer_mark = f.defers.len; var falls = true;
    while child >= 0 {
        let item: const Node& = p.nodes[child];
        if item.kind == N_DEFER { f.defers.push(child); child = item.next; continue; }
        // A statement a nonlocal return in flight may leave while defer bodies
        // are registered (§6.6, §7.9) is wrapped: its calls' effect checks
        // land after it, where the bodies run with the return set aside, so
        // their own calls complete, before it goes on out of the frame.
        let outer_landing = f.effect_landing; var after = -1;
        if p.unwinding && f.defers.len > 0 && f.running_defers == 0 && cg_unwinding_tree(p, child) {
            after = cg_begin(f, 0x02, 0x40); f.effect_landing = cg_begin(f, 0x02, 0x40);
        }
        if item.kind == N_EXPR_STMT && (item.flags & (F_TAIL | F_IMPLICIT_RETURN)) != 0 {
            if id == TYPE_VOID { cg_discard(p, m, f, item.left); }
            else { cg_set_values(p, m, f, item.left, id, result, child); }
        } else if item.next < 0 && (item.flags & F_TAIL) != 0 && item.kind != N_RETURN && item.kind != N_BREAK && item.kind != N_CONTINUE {
            if id == TYPE_VOID { cg_discard(p, m, f, child); } else { cg_set_values(p, m, f, child, id, result, child); }
        } else { cg_statement(p, m, f, child); }
        if after >= 0 {
            f.effect_landing = outer_landing; cg_branch(p, f, after, false); cg_end(f);
            wb_op(f.code, 0x23, 2); let effect = cg_save(f, wa()); wa_const(f.code, 0); wb_op(f.code, 0x24, 2);
            cg_run_defers(p, m, f, 0);
            cg_get(f, effect); wb_op(f.code, 0x24, 2); cg_branch(p, f, f.done, false); cg_end(f);
        }
        if cg_terminal(p, child) { falls = false; break; }
        child = item.next;
    }
    if n.right >= 0 {
        if id == TYPE_VOID { cg_discard(p, m, f, n.right); } else { cg_set_values(p, m, f, n.right, id, result, node); }
    }
    // The end of the block's text is an exit, after its value is built.
    if f.defers.len > defer_mark { if falls { cg_run_defers(p, m, f, defer_mark); } f.defers.resize(defer_mark); }
    // Every callee restores its own cursor. With no local acquisition the
    // saved value is dead and the engine can remove its read as well.
    if f.acquisitions != acquisitions { cg_restore_regions(f, region_mark); }
    f.region_live = live;
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
            let n: const Node& = p.nodes[node];
            if n.kind == N_BLOCK && (n.flags & F_EARLY) != 0 && n.origin >= 0 {
                var target = f.construction_destinations[receiving]; target.open0 = f.constructions[target.construction].open; target.escape = false;
                receiving = f.construction_destinations.len; f.construction_destinations.push(target);
            }
            f.receiving.push(CgReceiving { slot: first, ordinal: ordinal, destination: receiving });
        }
    }
    if first >= 0 && f.active_node == node && f.active_destination >= 0 && cg_receiving(f, -2 - node, 0) < 0 {
        var destination = f.active_destination; let n: const Node& = p.nodes[node];
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
fn cg_hoist_unwrap(p: Program&, node: i64) -> i64 {
    var cur = node;
    while cur >= 0 && p.nodes[cur].kind == N_UNARY && p.nodes[cur].integer == T_MUL { cur = p.nodes[cur].left; }
    return cur;
}
fn cg_hoist_find(p: Program&, f: CgBody&, expr: i64) -> i64 {
    if f.hoists.len == 0 { return -1; }
    let node = cg_hoist_unwrap(p, expr);
    if node < 0 { return -1; }
    let n: const Node& = p.nodes[node];
    var sym = -1; var field = -1;
    if n.kind == N_NAME { sym = n.symbol; }
    else if n.kind == N_MEMBER && n.symbol >= 0 {
        let base = cg_hoist_unwrap(p, n.left);
        if base < 0 || p.nodes[base].kind != N_NAME { return -1; }
        sym = p.nodes[base].symbol; field = n.symbol;
    } else { return -1; }
    var i = f.hoists.len;
    while i > 0 {
        i -= 1;
        if f.hoists[i].sym == sym as i32 && f.hoists[i].field == field as i32 { return i; }
    }
    return -1;
}
fn cg_hoist_match(p: Program&, m: CgModule&, f: CgBody&, expr: i64, sym_out: i64&, field_out: i64&, target_ty_out: i64&, is_slice_out: bool&, allow_value_slice: bool = false) -> bool {
    let node = cg_hoist_unwrap(p, expr);
    if node < 0 { return false; }
    let n: const Node& = p.nodes[node];
    var tid = n.type_id;
    if cg_type_kind(p, tid) == TY_REF {
        if (p.types[tid].flags & TF_OPTIONAL) != 0 { return false; }
        tid = p.types[tid].element;
    }
    if cg_type_kind(p, tid) == TY_REF { return false; }
    let tk = cg_type_kind(p, tid);
    let is_slice = tk == TY_SLICE;
    let is_owner = cg_owner(p, tid);
    if !is_slice && !is_owner { return false; }
    let elem = p.types[tid].element;
    if elem < 0 || elem >= p.types.len || p.types[elem].storage == 1 { return false; }
    if n.kind == N_NAME {
        let sym = n.symbol;
        if sym < 0 || sym >= p.symbols.len || sym >= f.slots.len { return false; }
        let s: const Symbol& = p.symbols[sym];
        if s.owner != f.function || (s.flags & (S_GLOBAL | S_CAPTURE | S_FUNCTION | S_TYPE | S_BUILTIN)) != 0 { return false; }
        if f.slots[sym].local < 0 { return false; }
        if cg_type_kind(p, s.type_id) == TY_REF && (p.types[s.type_id].flags & TF_OPTIONAL) != 0 { return false; }
        sym_out = sym; field_out = -1; target_ty_out = tid; is_slice_out = is_slice; return true;
    }
    if n.kind == N_MEMBER {
        if m.prefix_helper >= 0 { return false; }
        if n.symbol < 0 || n.symbol >= p.nodes.len || p.nodes[n.symbol].kind != N_FIELD { return false; }
        if p.nodes[n.symbol].integer < 0 { return false; }
        let ft = p.nodes[n.symbol].type_id;
        if cg_type_kind(p, ft) == TY_REF && (p.types[ft].flags & TF_OPTIONAL) != 0 { return false; }
        let base = cg_hoist_unwrap(p, n.left);
        if base < 0 || p.nodes[base].kind != N_NAME { return false; }
        let sym = p.nodes[base].symbol;
        if sym < 0 || sym >= p.symbols.len || sym >= f.slots.len { return false; }
        let s: const Symbol& = p.symbols[sym];
        if s.owner != f.function || (s.flags & (S_GLOBAL | S_CAPTURE | S_FUNCTION | S_TYPE | S_BUILTIN)) != 0 { return false; }
        if f.slots[sym].local < 0 { return false; }
        var base_ty = p.nodes[base].type_id;
        if cg_type_kind(p, base_ty) == TY_REF {
            if (p.types[base_ty].flags & TF_OPTIONAL) != 0 { return false; }
            base_ty = p.types[base_ty].element;
        }
        if cg_type_kind(p, s.type_id) == TY_REF && (p.types[s.type_id].flags & TF_OPTIONAL) != 0 { return false; }
        if cg_type_kind(p, base_ty) != TY_STRUCT { return false; }
        if cg_byte_record(p, base_ty) || cg_record_image(p, base_ty) || cg_frame_owner(p, base_ty) { return false; }
        sym_out = sym; field_out = n.symbol; target_ty_out = tid; is_slice_out = is_slice; return true;
    }
    return false;
}
recursive fn cg_may_contain_owner(p: Program&, id: i64, depth: i64) -> bool {
    if depth > 8 || id < 0 || id >= p.types.len { return true; }
    if id <= TYPE_F64 { return false; }
    let t: const Type& = p.types[id];
    if t.kind == TY_INT || t.kind == TY_FLOAT || t.kind == TY_BOOL || t.kind == TY_VOID || t.kind == TY_FN { return false; }
    if t.kind == TY_SLICE || t.kind == TY_REF { return true; }
    if t.kind == TY_ARRAY {
        if cg_owner(p, id) { return true; }
        return cg_may_contain_owner(p, t.element, depth + 1);
    }
    if t.kind == TY_STRUCT || t.kind == TY_ENUM || t.kind == TY_TUPLE {
        var field = t.first;
        while field >= 0 {
            if (p.nodes[field].flags & F_PAD) == 0 && cg_may_contain_owner(p, p.nodes[field].type_id, depth + 1) { return true; }
            field = p.nodes[field].next;
        }
        return false;
    }
    return true;
}
fn cg_hoist_array_types_disjoint(p: Program&, t1: i64, t2: i64) -> bool {
    if t1 < 0 || t2 < 0 || t1 >= p.types.len || t2 >= p.types.len { return false; }
    let k1 = p.types[t1].kind; let k2 = p.types[t2].kind;
    if k1 == TY_SLICE && k2 == TY_ARRAY || k1 == TY_ARRAY && k2 == TY_SLICE { return true; }
    if k1 != TY_ARRAY || k2 != TY_ARRAY { return false; }
    let e1 = p.types[t1].element; let e2 = p.types[t2].element;
    if e1 < 0 || e2 < 0 || e1 >= p.types.len || e2 >= p.types.len || e1 == e2 { return false; }
    let ek1 = p.types[e1].kind; let ek2 = p.types[e2].kind;
    if ek1 != ek2 { return true; }
    if cg_size(p, e1) != cg_size(p, e2) { return true; }
    if ek1 == TY_STRUCT || ek1 == TY_ENUM { return e1 != e2; }
    if ek1 == TY_INT { return p.types[e1].count != p.types[e2].count || cg_unsigned(p, e1) != cg_unsigned(p, e2); }
    return false;
}
fn cg_hoist_disjoint(p: Program&, f: CgBody&, cand: CgHoist&, target_node: i64) -> bool {
    let tn_id = cg_hoist_unwrap(p, target_node);
    if tn_id < 0 { return false; }
    let tn: const Node& = p.nodes[tn_id];
    let csym: i64 = cand.sym;
    let cfield: i64 = cand.field;
    let ctgt: i64 = cand.target_type;
    let csym_ty = p.symbols[csym].type_id;
    let csym_ref = cg_type_kind(p, csym_ty) == TY_REF;
    let cfield_ref = cfield >= 0 && cg_type_kind(p, p.nodes[cfield].type_id) == TY_REF;
    let c_is_param = (p.symbols[csym].flags & S_PARAMETER) != 0;
    var target_ty = tn.type_id;
    if cg_type_kind(p, target_ty) == TY_REF { target_ty = p.types[target_ty].element; }
    if tn.kind == N_NAME {
        let tsym = tn.symbol;
        if tsym < 0 || tsym >= p.symbols.len || tsym == csym { return false; }
        let ts: const Symbol& = p.symbols[tsym];
        let ts_local_nonref = ts.owner == f.function && (ts.flags & (S_GLOBAL | S_CAPTURE)) == 0 && cg_type_kind(p, ts.type_id) != TY_REF;
        if ts_local_nonref {
            if !csym_ref && !cfield_ref { return true; }
            if c_is_param && !cfield_ref && (ts.flags & S_PARAMETER) == 0 { return true; }
        }
        return cg_hoist_array_types_disjoint(p, ctgt, target_ty);
    }
    if tn.kind == N_MEMBER {
        let tbase = cg_hoist_unwrap(p, tn.left);
        if tbase < 0 || p.nodes[tbase].kind != N_NAME {
            return cg_hoist_array_types_disjoint(p, ctgt, target_ty);
        }
        let tsym = p.nodes[tbase].symbol; let tfield = tn.symbol;
        if tsym < 0 || tsym >= p.symbols.len || tfield < 0 || tfield >= p.nodes.len || p.nodes[tfield].kind != N_FIELD { return false; }
        let tfield_ref = cg_type_kind(p, p.nodes[tfield].type_id) == TY_REF;
        if cfield >= 0 && tsym == csym && tfield != cfield && !cfield_ref && !tfield_ref { return true; }
        let ts: const Symbol& = p.symbols[tsym];
        let ts_local_nonref = ts.owner == f.function && (ts.flags & (S_GLOBAL | S_CAPTURE)) == 0 && cg_type_kind(p, ts.type_id) != TY_REF;
        if tsym != csym && ts_local_nonref && !cfield_ref && !tfield_ref {
            if !csym_ref { return true; }
            if c_is_param && (ts.flags & S_PARAMETER) == 0 { return true; }
        }
        return cg_hoist_array_types_disjoint(p, ctgt, target_ty);
    }
    return cg_hoist_array_types_disjoint(p, ctgt, target_ty);
}
recursive fn cg_scan_header_pure(p: Program&, m: CgModule&, fn_node: i64, node: i64, budget: i64&) -> bool {
    if node < 0 { return true; }
    let n: const Node& = p.nodes[node]; let kind = n.kind;
    if kind >= N_INTEGER && kind <= N_NAME { return true; }
    if kind == N_FUNCTION || kind == N_FUNCTION_VALUE || kind == N_STRUCT || kind == N_ENUM || kind == N_ALIAS || kind == N_IMPORT || kind == N_EMPTY { return true; }
    budget -= 1;
    if budget < 0 { return false; }
    if kind == N_DEFER || kind == N_MULTI_ASSIGN { return false; }
    if kind == N_CAST && (n.flags & F_UNSIGNED) != 0 && cg_type_kind(p, n.type_id) == TY_REF { return false; }
    if kind == N_RETURN && n.symbol >= 0 && (p.symbols[n.symbol].flags & S_FUNCTION) != 0 && p.symbols[n.symbol].node != fn_node { return false; }
    if kind == N_ASSIGN {
        if n.left < 0 { return false; }
        let lhs: const Node& = p.nodes[n.left];
        if lhs.kind == N_UNARY && (lhs.integer == T_MUL || lhs.integer == T_XOR) { return false; }
        var lhs_ty = lhs.type_id;
        if n.integer != T_DOTASSIGN && cg_type_kind(p, lhs_ty) == TY_REF { lhs_ty = p.types[lhs_ty].element; }
        if lhs_ty > TYPE_F64 && cg_may_contain_owner(p, lhs_ty, 0) || lhs.kind == N_NAME && cg_type_kind(p, lhs.type_id) == TY_REF { return false; }
    }
    if kind == N_CALL {
        if (n.flags & F_DISPATCH) != 0 || n.symbol < 0 || (p.symbols[n.symbol].flags & S_BUILTIN) == 0 { return false; }
        let b = p.symbols[n.symbol].index;
        if !(b == 0 || b == 1 || b == 3 || b == 4 || b == 5 || b == 6 || b == 14 || b == 15 || b == 17 || b == 21 || b == 22 || b == 23 || b == 38 || b == 39) {
            return false;
        }
    }
    if n.left >= 0 && !cg_scan_header_pure(p, m, fn_node, n.left, budget) { return false; }
    if n.right >= 0 && !cg_scan_header_pure(p, m, fn_node, n.right, budget) { return false; }
    if n.third >= 0 && !cg_scan_header_pure(p, m, fn_node, n.third, budget) { return false; }
    var child = n.first;
    while child >= 0 {
        if !cg_scan_header_pure(p, m, fn_node, child, budget) { return false; }
        child = p.nodes[child].next;
    }
    return true;
}
fn cg_compute_header_pure(p: Program&, m: CgModule&) {
    if p.optimization < 2 || m.resolver >= 0 { return; }
    for i in 0..m.functions.len {
        if m.functions[i].capture_count != 0 { continue; }
        let fn_node = m.functions[i].node;
        if fn_node < 0 || (p.nodes[fn_node].flags & (F_EXTERN | F_NONLOCAL)) != 0 { continue; }
        if cg_may_contain_owner(p, cg_result_type(p, fn_node), 0) { continue; }
        var budget: i64 = 64;
        if cg_scan_header_pure(p, m, fn_node, p.nodes[fn_node].right, budget) {
            m.functions[i].header_pure = true;
        }
    }
}
fn cg_hoist_add_cand(p: Program&, m: CgModule&, f: CgBody&, expr: i64, needs_len: bool, cands: CgHoist[:], cand_count: i64&) {
    var sym: i64 = -1; var field: i64 = -1; var target_ty: i64 = -1; var is_slice = false;
    if !cg_hoist_match(p, m, f, expr, sym, field, target_ty, is_slice, false) { return; }
    var existing_ptr: i32 = -1;
    var hi = f.hoists.len;
    while hi > 0 {
        hi -= 1;
        if f.hoists[hi].sym == sym as i32 && f.hoists[hi].field == field as i32 {
            if f.hoists[hi].len_local >= 0 || !needs_len { return; }
            existing_ptr = f.hoists[hi].ptr_local;
            break;
        }
    }
    for j in 0..cand_count {
        if cands[j].sym == sym as i32 && cands[j].field == field as i32 {
            if cands[j].uses < 65000 { cands[j].uses += 1; }
            if needs_len { cands[j].flags |= CG_HOIST_LEN; }
            return;
        }
    }
    if cand_count < cands.len {
        var fl: u16 = CG_HOIST_ALIVE;
        if is_slice { fl |= CG_HOIST_SLICE; }
        if needs_len { fl |= CG_HOIST_LEN; }
        cands[cand_count] = CgHoist {
            sym: sym as i32, field: field as i32, ptr_local: existing_ptr, len_local: -1,
            sample_node: cg_hoist_unwrap(p, expr) as i32, target_type: target_ty as i32,
            flags: fl, uses: 1,
        };
        cand_count += 1;
    }
}
recursive fn cg_hoist_scan_collect(p: Program&, m: CgModule&, f: CgBody&, node: i64, cands: CgHoist[:], cand_count: i64&, budget: i64&, mutations: i64&, aborted: bool&) {
    if aborted || node < 0 { return; }
    let n: const Node& = p.nodes[node]; let kind = n.kind;
    if kind >= N_INTEGER && kind <= N_NAME { return; }
    if kind == N_FUNCTION || kind == N_FUNCTION_VALUE || kind == N_STRUCT || kind == N_ENUM || kind == N_ALIAS || kind == N_IMPORT || kind == N_EMPTY { return; }
    budget -= 1;
    if budget < 0 { aborted = true; return; }
    if kind == N_DEFER || kind == N_MULTI_ASSIGN { aborted = true; return; }
    if kind == N_CAST && (n.flags & F_UNSIGNED) != 0 && cg_type_kind(p, n.type_id) == TY_REF { aborted = true; return; }
    if kind == N_UNARY && n.integer == T_BITAND { mutations += 1; }
    if kind == N_VARIABLE || kind == N_FOR || kind == N_PATTERN { mutations += 1; }
    if kind == N_ASSIGN {
        if n.left < 0 { aborted = true; return; }
        let lhs: const Node& = p.nodes[n.left];
        if lhs.kind == N_UNARY && (lhs.integer == T_MUL || lhs.integer == T_XOR) { aborted = true; return; }
        var lhs_ty = lhs.type_id;
        if n.integer != T_DOTASSIGN && cg_type_kind(p, lhs_ty) == TY_REF { lhs_ty = p.types[lhs_ty].element; }
        if lhs_ty > TYPE_F64 && cg_may_contain_owner(p, lhs_ty, 0) || lhs.kind == N_NAME && cg_type_kind(p, lhs.type_id) == TY_REF { mutations += 1; }
    }
    if kind == N_CALL {
        if (n.flags & F_DISPATCH) != 0 || n.symbol < 0 { aborted = true; return; }
        if (p.symbols[n.symbol].flags & S_BUILTIN) != 0 {
            let b = p.symbols[n.symbol].index;
            if b == 21 && n.first >= 0 { cg_hoist_add_cand(p, m, f, n.first, true, cands, cand_count); }
            else if b == 0 || b == 1 || b == 3 || b == 4 || b == 5 || b == 6 || b == 14 || b == 15 || b == 17 || b == 22 || b == 23 || b == 38 || b == 39 {}
            else if b == 2 || b == 16 || b >= 24 && b <= 29 { mutations += 1; }
            else if b == 40 {
                if n.first < 0 { aborted = true; return; }
                var rid = p.nodes[n.first].type_id; if cg_type_kind(p, rid) == TY_REF { rid = p.types[rid].element; }
                if cg_may_contain_owner(p, p.types[rid].element, 0) { aborted = true; return; }
            } else { aborted = true; return; }
        } else if (p.symbols[n.symbol].flags & S_FUNCTION) != 0 {
            let cidx = cg_function(m, n.symbol);
            if cidx < 0 || !m.functions[cidx].header_pure { aborted = true; return; }
        } else { aborted = true; return; }
    }
    if kind == N_INDEX { cg_hoist_add_cand(p, m, f, n.left, (n.flags & F_BOUNDS_PROVEN) == 0, cands, cand_count); }
    if kind == N_MEMBER && n.symbol < 0 && token_is(p, n.token, "len") { cg_hoist_add_cand(p, m, f, n.left, true, cands, cand_count); }
    if n.left >= 0 { cg_hoist_scan_collect(p, m, f, n.left, cands, cand_count, budget, mutations, aborted); if aborted { return; } }
    if n.right >= 0 { cg_hoist_scan_collect(p, m, f, n.right, cands, cand_count, budget, mutations, aborted); if aborted { return; } }
    if n.third >= 0 { cg_hoist_scan_collect(p, m, f, n.third, cands, cand_count, budget, mutations, aborted); if aborted { return; } }
    if kind != N_FOR {
        var child = n.first;
        while child >= 0 {
            cg_hoist_scan_collect(p, m, f, child, cands, cand_count, budget, mutations, aborted);
            if aborted { return; }
            child = p.nodes[child].next;
        }
    }
}
fn cg_hoist_kill_sym(cands: CgHoist[:], cand_count: i64, sym: i64, alive_count: i64&) {
    if sym < 0 { return; }
    let s32 = sym as i32;
    for j in 0..cand_count {
        if (cands[j].flags & CG_HOIST_ALIVE) != 0 && cands[j].sym == s32 { cands[j].flags &= ~CG_HOIST_ALIVE; alive_count -= 1; }
    }
}
fn cg_hoist_kill_receiver(p: Program&, f: CgBody&, cands: CgHoist[:], cand_count: i64, receiver: i64, alive_count: i64&) {
    for j in 0..cand_count {
        if (cands[j].flags & CG_HOIST_ALIVE) != 0 && !cg_hoist_disjoint(p, f, cands[j], receiver) { cands[j].flags &= ~CG_HOIST_ALIVE; alive_count -= 1; }
    }
}
recursive fn cg_hoist_scan_kill(p: Program&, f: CgBody&, node: i64, cands: CgHoist[:], cand_count: i64, alive_count: i64&) {
    if alive_count <= 0 || node < 0 { return; }
    let n: const Node& = p.nodes[node]; let kind = n.kind;
    if kind >= N_INTEGER && kind <= N_NAME { return; }
    if kind == N_FUNCTION || kind == N_FUNCTION_VALUE || kind == N_STRUCT || kind == N_ENUM || kind == N_ALIAS || kind == N_IMPORT || kind == N_EMPTY { return; }
    if kind == N_VARIABLE {
        if n.symbol >= 0 { cg_hoist_kill_sym(cands, cand_count, n.symbol, alive_count); }
        var b = n.first; while b >= 0 { cg_hoist_kill_sym(cands, cand_count, p.nodes[b].symbol, alive_count); b = p.nodes[b].next; }
    } else if kind == N_FOR {
        var b = n.first; while b >= 0 { cg_hoist_kill_sym(cands, cand_count, p.nodes[b].symbol, alive_count); b = p.nodes[b].next; }
    } else if kind == N_PATTERN {
        if n.left >= 0 { cg_hoist_kill_sym(cands, cand_count, p.nodes[n.left].symbol, alive_count); }
    } else if kind == N_UNARY && n.integer == T_BITAND {
        let target = cg_hoist_unwrap(p, n.left);
        if target >= 0 {
            if p.nodes[target].kind == N_NAME { cg_hoist_kill_sym(cands, cand_count, p.nodes[target].symbol, alive_count); }
            else if p.nodes[target].kind == N_MEMBER {
                let tb = cg_hoist_unwrap(p, p.nodes[target].left);
                if tb >= 0 && p.nodes[tb].kind == N_NAME { cg_hoist_kill_sym(cands, cand_count, p.nodes[tb].symbol, alive_count); }
            }
            if p.nodes[target].type_id > TYPE_F64 && cg_may_contain_owner(p, p.nodes[target].type_id, 0) {
                cg_hoist_kill_receiver(p, f, cands, cand_count, target, alive_count);
            }
        }
    } else if kind == N_ASSIGN {
        let lhs: const Node& = p.nodes[n.left];
        if lhs.kind == N_NAME { cg_hoist_kill_sym(cands, cand_count, lhs.symbol, alive_count); }
        else if lhs.kind == N_MEMBER {
            let tb = cg_hoist_unwrap(p, lhs.left);
            if tb >= 0 && p.nodes[tb].kind == N_NAME && lhs.symbol >= 0 {
                let lsym = p.nodes[tb].symbol as i32; let lfield = lhs.symbol as i32;
                for j in 0..cand_count {
                    if (cands[j].flags & CG_HOIST_ALIVE) != 0 && cands[j].sym == lsym && cands[j].field == lfield {
                        cands[j].flags &= ~CG_HOIST_ALIVE; alive_count -= 1;
                    }
                }
            }
        }
        var lhs_ty = lhs.type_id;
        if n.integer != T_DOTASSIGN && cg_type_kind(p, lhs_ty) == TY_REF { lhs_ty = p.types[lhs_ty].element; }
        if lhs_ty > TYPE_F64 && cg_may_contain_owner(p, lhs_ty, 0) { cg_hoist_kill_receiver(p, f, cands, cand_count, n.left, alive_count); }
    } else if kind == N_CALL {
        if n.symbol >= 0 && (p.symbols[n.symbol].flags & S_BUILTIN) != 0 {
            let b = p.symbols[n.symbol].index;
            if b == 2 || b >= 24 && b <= 29 { cg_hoist_kill_receiver(p, f, cands, cand_count, n.first, alive_count); }
            else if b == 16 && n.first >= 0 && p.nodes[n.first].next >= 0 { cg_hoist_kill_receiver(p, f, cands, cand_count, p.nodes[n.first].next, alive_count); }
        }
    }
    if alive_count <= 0 { return; }
    if n.left >= 0 { cg_hoist_scan_kill(p, f, n.left, cands, cand_count, alive_count); if alive_count <= 0 { return; } }
    if n.right >= 0 { cg_hoist_scan_kill(p, f, n.right, cands, cand_count, alive_count); if alive_count <= 0 { return; } }
    if n.third >= 0 { cg_hoist_scan_kill(p, f, n.third, cands, cand_count, alive_count); if alive_count <= 0 { return; } }
    if kind != N_FOR {
        var child = n.first;
        while child >= 0 {
            cg_hoist_scan_kill(p, f, child, cands, cand_count, alive_count);
            if alive_count <= 0 { return; }
            child = p.nodes[child].next;
        }
    }
}
recursive fn cg_hoist_emit_cands(p: Program&, m: CgModule&, f: CgBody&, cands: CgHoist[:], cand_count: i64) {
    var ready: CgHoist[2] = [CgHoist {}; 2];
    var ready_count: i64 = 0;
    while ready_count < 2 && f.hoists.len + ready_count < 4 {
        var best = -1; var best_uses: i64 = -1;
        for j in 0..cand_count {
            if (cands[j].flags & CG_HOIST_ALIVE) == 0 { continue; }
            let is_slice = (cands[j].flags & CG_HOIST_SLICE) != 0;
            let needs_len = (cands[j].flags & CG_HOIST_LEN) != 0;
            let csym: i64 = cands[j].sym;
            let in_local = cands[j].field < 0 && f.slots[csym].value && cg_type_kind(p, p.symbols[csym].type_id) != TY_REF ||
                cands[j].field >= 0 && f.slots[csym].sroa_count > 0;
            if is_slice && in_local &&
               (cg_wide && cands[j].uses < 3 || !cg_wide && !needs_len && cands[j].uses < 2) {
                cands[j].flags &= ~CG_HOIST_ALIVE; continue;
            }
            let cuses: i64 = cands[j].uses;
            if cuses > best_uses { best = j; best_uses = cuses; }
        }
        if best < 0 { break; }
        cands[best].flags &= ~CG_HOIST_ALIVE;
        var h = cands[best];
        let snode: i64 = h.sample_node;
        let is_slice = (h.flags & CG_HOIST_SLICE) != 0;
        let needs_len = (h.flags & CG_HOIST_LEN) != 0;
        cg_expr(p, m, f, snode);
        var sid = p.nodes[snode].type_id;
        if cg_type_kind(p, sid) == TY_REF { sid = p.types[sid].element; cg_load(p, m, f, sid, 0); }
        if is_slice || !m.ordinary_owners {
            if !is_slice { cg_pack_view(p, m, f, sid, snode); }
            if !needs_len {
                ws_ptr(f.code); h.ptr_local = cg_save(f, wa()) as i32; h.len_local = -1;
            } else if h.ptr_local >= 0 {
                ws_count(f.code); h.len_local = cg_save(f, 0x7e) as i32;
            } else {
                let v = cg_tee(f, ws());
                ws_ptr(f.code); h.ptr_local = cg_save(f, wa()) as i32;
                cg_get(f, v); ws_count(f.code); h.len_local = cg_save(f, 0x7e) as i32;
            }
        } else {
            if !needs_len {
                wc_load(f.code, 0); h.ptr_local = cg_save(f, wa()) as i32; h.len_local = -1;
            } else if h.ptr_local >= 0 {
                wc_load(f.code, 1); wa_extend(f.code); h.len_local = cg_save(f, 0x7e) as i32;
            } else {
                let hdr = cg_tee(f, wa());
                wc_load(f.code, 0); h.ptr_local = cg_save(f, wa()) as i32;
                cg_get(f, hdr); wc_load(f.code, 1); wa_extend(f.code); h.len_local = cg_save(f, 0x7e) as i32;
            }
        }
        ready[ready_count] = h;
        ready_count += 1;
    }
    for i in 0..ready_count { f.hoists.push(ready[i]); }
}
recursive fn cg_hoist_enter_loop(p: Program&, m: CgModule&, f: CgBody&, node: i64) -> i64 {
    let mark = f.hoists.len;
    if p.optimization < 2 || m.resolver >= 0 || f.hoists.len >= 4 { return mark; }
    let n: const Node& = p.nodes[node];
    var cands: CgHoist[4] = [CgHoist {}; 4];
    var cand_count: i64 = 0;
    var budget: i64 = 256; var mutations: i64 = 0; var aborted = false;
    if n.kind == N_WHILE && n.left >= 0 { cg_hoist_scan_collect(p, m, f, n.left, cands, cand_count, budget, mutations, aborted); }
    if !aborted && n.right >= 0 { cg_hoist_scan_collect(p, m, f, n.right, cands, cand_count, budget, mutations, aborted); }
    if aborted || cand_count == 0 { return mark; }
    if mutations > 0 {
        var alive = cand_count;
        if n.kind == N_WHILE && n.left >= 0 { cg_hoist_scan_kill(p, f, n.left, cands, cand_count, alive); }
        if alive > 0 && n.right >= 0 { cg_hoist_scan_kill(p, f, n.right, cands, cand_count, alive); }
        if alive <= 0 { return mark; }
    }
    cg_hoist_emit_cands(p, m, f, cands, cand_count);
    return mark;
}
recursive fn cg_hoist_enter_for(p: Program&, m: CgModule&, f: CgBody&, node: i64, element_binding: i64, ordinal_binding: i64, sequence: bool, stable_view: bool&, view: i64, cursor: i64, hoisted_base: i64&, counter: i64, limit: i64, counter_type: i64, done: i64&, hoist_mark: i64&) {
    let n: const Node& = p.nodes[node];
    let iterable: const Node& = p.nodes[n.left];
    var cands: CgHoist[4] = [CgHoist {}; 4];
    var cand_count: i64 = 0;
    var seq_sym: i64 = -1; var seq_field: i64 = -1; var seq_ty: i64 = -1; var seq_is_slice = false;
    var seq_hoistable = false;
    if sequence && cg_hoist_match(p, m, f, n.left, seq_sym, seq_field, seq_ty, seq_is_slice, true) {
        if !stable_view && cg_hoist_find(p, f, n.left) >= 0 { stable_view = true; }
        seq_hoistable = true;
    }
    if f.hoists.len < 4 || sequence && !stable_view && seq_hoistable {
        var budget: i64 = 256; var mutations: i64 = 0; var aborted = false;
        if sequence && !stable_view && seq_hoistable {
            var fl: u16 = CG_HOIST_ALIVE | CG_HOIST_LEN;
            if seq_is_slice { fl |= CG_HOIST_SLICE; }
            cands[0] = CgHoist {
                sym: seq_sym as i32, field: seq_field as i32, ptr_local: -1, len_local: -1,
                sample_node: cg_hoist_unwrap(p, n.left) as i32, target_type: seq_ty as i32,
                flags: fl, uses: 1,
            };
            cand_count = 1;
        }
        if n.right >= 0 { cg_hoist_scan_collect(p, m, f, n.right, cands, cand_count, budget, mutations, aborted); }
        if aborted { cand_count = 0; }
        else if cand_count > 0 {
            var alive = cand_count;
            cg_hoist_kill_sym(cands, cand_count, element_binding, alive);
            cg_hoist_kill_sym(cands, cand_count, ordinal_binding, alive);
            if alive > 0 && mutations > 0 && n.right >= 0 { cg_hoist_scan_kill(p, f, n.right, cands, cand_count, alive); }
            if sequence && !stable_view && seq_hoistable && cands[0].sym == seq_sym as i32 && cands[0].field == seq_field as i32 && (cands[0].flags & CG_HOIST_ALIVE) != 0 {
                stable_view = true;
            }
        }
    }
    if stable_view && cursor < 0 { cg_get(f, view); ws_ptr(f.code); hoisted_base = cg_save(f, wa()); }
    hoist_mark = f.hoists.len;
    if sequence && stable_view && seq_hoistable && hoisted_base >= 0 && f.hoists.len < 4 {
        var sfl: u16 = CG_HOIST_ALIVE | CG_HOIST_LEN;
        if seq_is_slice { sfl |= CG_HOIST_SLICE; }
        f.hoists.push(CgHoist {
            sym: seq_sym as i32, field: seq_field as i32, ptr_local: hoisted_base as i32, len_local: limit as i32,
            sample_node: -1, target_type: seq_ty as i32, flags: sfl, uses: 1,
        });
        for j in 0..cand_count {
            if cands[j].sym == seq_sym as i32 && cands[j].field == seq_field as i32 { cands[j].flags &= ~CG_HOIST_ALIVE; }
        }
    }
    var emit_count = 0;
    for j in 0..cand_count {
        if (cands[j].flags & CG_HOIST_ALIVE) == 0 { continue; }
        let is_sl = (cands[j].flags & CG_HOIST_SLICE) != 0;
        let need_l = (cands[j].flags & CG_HOIST_LEN) != 0;
        let csym: i64 = cands[j].sym;
        let in_local = cands[j].field < 0 && f.slots[csym].value && cg_type_kind(p, p.symbols[csym].type_id) != TY_REF ||
            cands[j].field >= 0 && f.slots[csym].sroa_count > 0;
        if is_sl && in_local &&
           (cg_wide && cands[j].uses < 3 || !cg_wide && !need_l && cands[j].uses < 2) {
            cands[j].flags &= ~CG_HOIST_ALIVE; continue;
        }
        emit_count += 1;
    }
    done = cg_begin(f, 0x02, 0x40);
    if emit_count > 0 && f.hoists.len < 4 {
        if !m.ordinary_owners {
            cg_get(f, counter); cg_get(f, limit); var pre_cmp = T_GTEQ;
            if iterable.kind == N_RANGE && (iterable.flags & F_INCLUSIVE) != 0 { pre_cmp = T_GT; }
            wb_byte(f.code, cg_numeric_opcode(pre_cmp, cg_wasm_type(p, counter_type), cg_unsigned(p, counter_type)));
            cg_branch(p, f, done, true);
        }
        cg_hoist_emit_cands(p, m, f, cands, cand_count);
    }
}
recursive fn cg_loop(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n: const Node& = p.nodes[node]; let result = cg_control_slots(p, f, n.type_id, node);
    var scratch = -1;
    if cg_may_print(p, m, node) { cg_record(f, 0x23, 0); wb_op(f.code, 0x23, 0); scratch = cg_save(f, wa()); }
    var regions = -1;
    if m.regions_enabled && cg_may_region(p, m, node) { regions = cg_mark_regions(f); }
    let hoist_mark = cg_hoist_enter_loop(p, m, f, node);
    let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
    f.exits.push(CgExit { label: done, again: again, node: node, result: result, type_id: n.type_id, scratch: scratch, regions: regions, publication: cg_mark_publications(m, f), defers: f.defers.len });
    if n.kind == N_WHILE {
        cg_branch_cond(p, m, f, n.left, done, false);
        if cg_diverges(p, n.left) { f.exits.pop(); cg_end(f); cg_end(f); f.hoists.resize(hoist_mark); return; }
    }
    cg_block_into(p, m, f, n.right, TYPE_VOID, -1); f.exits.pop(); cg_branch(p, f, again, false);
    cg_end(f); cg_end(f); f.hoists.resize(hoist_mark); cg_control_get(p, f, n.type_id, result);
}
recursive fn cg_replayable(p: Program&, node: i64) -> bool {
    if node < 0 { return true; } let n: const Node& = p.nodes[node];
    if n.kind == N_NAME || n.kind == N_INTEGER { return true; }
    if n.kind == N_MEMBER || n.kind == N_UNARY { return cg_replayable(p, n.left); }
    if n.kind == N_INDEX { return cg_replayable(p, n.left) && cg_replayable(p, n.right); }
    return false;
}
recursive fn cg_index_effects(p: Program&, node: i64) -> bool {
    if node < 0 { return false; } let n: const Node& = p.nodes[node];
    if n.kind == N_CALL || n.kind == N_STRING || n.kind == N_BLOCK || n.kind == N_IF || n.kind == N_MATCH ||
       n.kind == N_LOOP || n.kind == N_WHILE || n.kind == N_FOR || n.kind == N_RETURN || n.kind == N_ASSIGN || n.kind == N_VARIABLE { return true; }
    if cg_index_effects(p, n.left) || cg_index_effects(p, n.right) || cg_index_effects(p, n.third) { return true; }
    var child = n.first; while child >= 0 { if cg_index_effects(p, child) { return true; } child = p.nodes[child].next; } return false;
}
recursive fn cg_pin_sequence(p: Program&, m: CgModule&, f: CgBody&, node: i64, address: bool) -> i64 {
    let n: const Node& = p.nodes[node]; var item = CgSequence { kind: 0, node: node, address: address };
    if n.kind == N_NAME { item.kind = 1; }
    else if n.kind == N_MEMBER && n.symbol >= 0 && n.symbol < p.nodes.len && p.nodes[n.symbol].kind == N_FIELD {
        item.kind = 2; item.parent = cg_pin_sequence(p, m, f, n.left, false);
    } else if n.kind == N_INDEX {
        item.kind = 3; item.parent = cg_pin_sequence(p, m, f, n.left, false);
        var object = p.nodes[n.left].type_id; while cg_type_kind(p, object) == TY_REF { object = p.types[object].element; }
        if cg_index_effects(p, n.right) {
            cg_emit_sequence(p, m, f, item.parent); cg_pack_view(p, m, f, p.nodes[n.left].type_id, node); item.saved = cg_save(f, ws());
        }
        cg_to(p, m, f, n.right, TYPE_U64); item.index = cg_save(f, 0x7e);
        if cg_type_kind(p, object) == TY_SLICE && item.saved < 0 {
            cg_emit_sequence(p, m, f, item.parent); cg_pack_view(p, m, f, p.nodes[n.left].type_id, node); ws_ptr(f.code); item.pointer = cg_save(f, wa());
        }
    } else if n.kind == N_UNARY && n.integer == T_BITAND && cg_type_kind(p, p.nodes[n.left].type_id) != TY_REF &&
              (p.nodes[n.left].kind == N_NAME || p.nodes[n.left].kind == N_MEMBER || p.nodes[n.left].kind == N_INDEX) {
        return cg_pin_sequence(p, m, f, n.left, true);
    } else {
        if address { cg_address(p, m, f, node); item.saved = cg_save(f, wa()); }
        else { cg_expr(p, m, f, node); item.saved = cg_save(f, cg_wasm_type(p, n.type_id)); }
    }
    let result = f.sequences.len; f.sequences.push(item); return result;
}
recursive fn cg_emit_sequence(p: Program&, m: CgModule&, f: CgBody&, recipe: i64) {
    let item = f.sequences[recipe]; let n: const Node& = p.nodes[item.node];
    if item.kind == 0 { cg_get(f, item.saved); return; }
    if item.kind == 1 {
        let stored = p.symbols[n.symbol].type_id;
        if !item.address && f.slots[n.symbol].value { cg_get(f, f.slots[n.symbol].local); cg_convert(p, m, f, stored, n.type_id, item.node); return; }
        if !item.address && f.slots[n.symbol].sroa_count > 0 { cg_sroa_materialize(p, f, n.symbol); cg_convert(p, m, f, stored, n.type_id, item.node); return; }
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
        if !item.address && p.nodes[n.left].kind == N_NAME {
            let bsym = p.nodes[n.left].symbol;
            if bsym >= 0 && bsym < f.slots.len && f.slots[bsym].sroa_count > 0 {
                let fi = cg_sroa_field_index(p, p.symbols[bsym].type_id, n.symbol);
                if fi >= 0 {
                    let field = p.nodes[n.symbol].type_id;
                    cg_get(f, f.slots[bsym].local + fi);
                    cg_convert(p, m, f, field, n.type_id, item.node);
                    return;
                }
            }
        }
        cg_emit_sequence(p, m, f, item.parent); var object = p.nodes[n.left].type_id;
        while cg_type_kind(p, object) == TY_REF { object = p.types[object].element; cg_load(p, m, f, object, 0); }
        cg_field_place(p, m, f, object, item.node); let field = p.nodes[n.symbol].type_id;
        if !item.address && (cg_type_kind(p, n.type_id) != TY_REF || cg_type_kind(p, field) == TY_REF) {
            cg_load(p, m, f, field, 0); cg_convert(p, m, f, field, n.type_id, item.node);
        }
        return;
    }
    var object = p.nodes[n.left].type_id; while cg_type_kind(p, object) == TY_REF { object = p.types[object].element; }
    let element = p.types[object].element;
    if f.hoists.len > 0 && item.saved < 0 && item.pointer < 0 && m.resolver < 0 && p.types[element].storage != 1 {
        let hi = cg_hoist_find(p, f, n.left);
        if hi >= 0 && ((n.flags & F_BOUNDS_PROVEN) != 0 || f.hoists[hi].len_local >= 0) {
            if (n.flags & F_BOUNDS_PROVEN) == 0 {
                cg_get(f, item.index); cg_get(f, f.hoists[hi].len_local); wb_byte(f.code, 0x5a);
                cg_trap_if(p, m, f, item.node, "array index out of bounds");
            }
            cg_get(f, f.hoists[hi].ptr_local); cg_get(f, item.index); wa_wrap(f.code); cg_scale_index(f, cg_size(p, element)); wa_op(f.code, 0x6a);
            if !item.address && (cg_type_kind(p, n.type_id) != TY_REF || cg_type_kind(p, element) == TY_REF) {
                cg_load(p, m, f, element, 0); cg_convert(p, m, f, element, n.type_id, item.node);
            }
            return;
        }
    }
    if (n.flags & F_BOUNDS_PROVEN) != 0 && item.saved < 0 && item.pointer < 0 && m.resolver < 0 {
        let obj_kind = cg_type_kind(p, object);
        let obj_owner = cg_owner(p, object);
        if obj_owner && m.ordinary_owners || obj_kind == TY_SLICE || obj_kind == TY_ARRAY && !obj_owner {
            cg_emit_sequence(p, m, f, item.parent);
            var deref = p.nodes[n.left].type_id;
            while cg_type_kind(p, deref) == TY_REF { deref = p.types[deref].element; cg_load(p, m, f, deref, 0); }
            if obj_owner { wc_load(f.code, 0); }
            else if obj_kind == TY_SLICE { ws_ptr(f.code); }
            else { wa_add(f.code, cg_static_prefix(p, object)); }
            cg_get(f, item.index); wa_wrap(f.code); cg_scale_index(f, cg_size(p, element)); wa_op(f.code, 0x6a);
            if !item.address && (cg_type_kind(p, n.type_id) != TY_REF || cg_type_kind(p, element) == TY_REF) {
                cg_load(p, m, f, element, 0); cg_convert(p, m, f, element, n.type_id, item.node);
            }
            return;
        }
    }
    if item.saved >= 0 { cg_get(f, item.saved); }
    else {
        cg_emit_sequence(p, m, f, item.parent); cg_pack_view(p, m, f, p.nodes[n.left].type_id, item.node);
        if item.pointer >= 0 { wB_slice_repoint(f, item.pointer); }
    }
    let view = cg_save(f, ws());
    if (n.flags & F_BOUNDS_PROVEN) == 0 {
        cg_get(f, item.index); cg_get(f, view); ws_count(f.code); wb_byte(f.code, 0x5a); cg_trap_if(p, m, f, item.node, "array index out of bounds");
    }
    cg_get(f, view); ws_ptr(f.code); cg_get(f, item.index); wa_wrap(f.code); cg_scale_index(f, cg_size(p, element)); wa_op(f.code, 0x6a);
    if !item.address && (cg_type_kind(p, n.type_id) != TY_REF || cg_type_kind(p, element) == TY_REF) {
        cg_load(p, m, f, element, 0); cg_convert(p, m, f, element, n.type_id, item.node);
    }
}
// Only private numeric locals may be written between visits to the encoded
// elements. Calls, indirect stores and rebindings need a fresh prefix walk.
recursive fn cg_stable_scan_body(p: Program&, function: i64, node: i64, row_fields: bool = false) -> bool {
    if node < 0 { return true; }
    let n: const Node& = p.nodes[node];
    if n.kind == N_NAME || n.kind == N_INTEGER || n.kind == N_FLOAT || n.kind == N_BOOL { return true; }
    if n.kind == N_ASSIGN || n.kind == N_VARIABLE {
        var binding = node; if n.kind == N_ASSIGN { binding = n.left; if p.nodes[binding].kind != N_NAME { return false; } }
        let symbol = p.nodes[binding].symbol;
        if symbol < 0 || symbol >= p.symbols.len { return false; }
        let stored: const Symbol& = p.symbols[symbol];
        if stored.owner != function || (stored.flags & (S_CAPTURE | S_GLOBAL)) != 0 || !cg_scalar_slot_type(p, stored.type_id) { return false; }
        if n.first >= 0 { return false; }
        return cg_stable_scan_body(p, function, n.right, row_fields);
    }
    if row_fields && n.kind == N_MEMBER && n.symbol >= 0 && n.symbol < p.nodes.len && p.nodes[n.symbol].kind == N_FIELD {
        return cg_stable_scan_body(p, function, n.left, row_fields);
    }
    if n.kind == N_CAST { return cg_stable_scan_body(p, function, n.left, row_fields); }
    if n.kind != N_BLOCK && n.kind != N_BINARY && n.kind != N_UNARY && n.kind != N_IF &&
       n.kind != N_BREAK && n.kind != N_CONTINUE && n.kind != N_EXPR_STMT { return false; }
    if !cg_stable_scan_body(p, function, n.left, row_fields) || !cg_stable_scan_body(p, function, n.right, row_fields) || !cg_stable_scan_body(p, function, n.third, row_fields) { return false; }
    var child = n.first; while child >= 0 { if !cg_stable_scan_body(p, function, child, row_fields) { return false; } child = p.nodes[child].next; }
    return true;
}
fn cg_varint_cursor(p: Program&, function: i64, node: i64) -> bool {
    let loop_node: const Node& = p.nodes[node]; let iterable: const Node& = p.nodes[loop_node.left];
    if function < 0 || iterable.kind != N_NAME || iterable.symbol < 0 { return false; }
    let source: const Symbol& = p.symbols[iterable.symbol];
    if source.owner != function || (source.flags & (S_PARAMETER | S_MUTABLE | S_CAPTURE)) != S_PARAMETER ||
       cg_type_kind(p, source.type_id) != TY_SLICE { return false; }
    // Incoming elements are outside this activation. An earlier call or
    // reinterpretation could have rebound the slice to its own scalar slots.
    let body = p.nodes[function].right; if body < 0 { return false; }
    var statement = p.nodes[body].first;
    while statement >= 0 && statement != node {
        if !cg_stable_scan_body(p, function, statement) { return false; }
        statement = p.nodes[statement].next;
    }
    return statement == node && cg_stable_scan_body(p, function, loop_node.right);
}
recursive fn cg_for(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n: const Node& = p.nodes[node]; let iterable: const Node& = p.nodes[n.left]; var type_id = iterable.type_id;
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
        recipe = cg_pin_sequence(p, m, f, n.left, false); cg_emit_sequence(p, m, f, recipe); cg_pack_view(p, m, f, iterable.type_id, node); view = cg_save(f, ws()); wb_i64(f.code, 0);
    } else if iterable.kind == N_RANGE { cg_to(p, m, f, iterable.left, counter_type); }
    else { cg_zero(f.code, cg_wasm_type(p, counter_type)); }
    let counter = cg_save(f, cg_wasm_type(p, counter_type));
    if sequence { cg_get(f, view); ws_count(f.code); }
    else if iterable.kind == N_RANGE { cg_to(p, m, f, iterable.right, counter_type); }
    else { cg_to(p, m, f, n.left, counter_type); }
    let limit = cg_save(f, cg_wasm_type(p, counter_type));
    var ordinal = -1;
    if ordinal_binding >= 0 {
        if sequence { ordinal = counter; }
        else { wb_i64(f.code, 0); ordinal = cg_save(f, 0x7e); }
    }
    var cursor = -1;
    if sequence && p.types[p.types[type_id].element].storage == 1 && cg_varint_cursor(p, f.function, node) {
        cg_get(f, view); ws_ptr(f.code); cursor = cg_save(f, wa());
    }
    var stable_view = sequence && (
        cg_type_kind(p, type_id) == TY_ARRAY && p.types[type_id].array_kind == A_FIXED ||
        m.resolver < 0 && f.sequences[recipe].kind == 0 && cg_type_kind(p, iterable.type_id) == TY_SLICE ||
        m.resolver < 0 && iterable.kind == N_NAME && iterable.symbol >= 0 && cg_type_kind(p, p.symbols[iterable.symbol].type_id) == TY_SLICE &&
        (p.symbols[iterable.symbol].flags & (S_MUTABLE | S_GLOBAL | S_CAPTURE | CG_ADDRESS_TAKEN)) == 0);
    var scratch = -1;
    if cg_may_print(p, m, n.right) { cg_record(f, 0x23, 0); wb_op(f.code, 0x23, 0); scratch = cg_save(f, wa()); }
    var regions = -1; if m.regions_enabled && cg_may_region(p, m, n.right) { regions = cg_mark_regions(f); }
    let publication = cg_mark_publications(m, f);
    var hoisted_base = -1;
    var hoist_mark = f.hoists.len;
    var done = -1;
    if p.optimization >= 2 && m.resolver < 0 {
        cg_hoist_enter_for(p, m, f, node, element_binding, ordinal_binding, sequence, stable_view, view, cursor, hoisted_base, counter, limit, counter_type, done, hoist_mark);
    } else {
        if stable_view && cursor < 0 { cg_get(f, view); ws_ptr(f.code); hoisted_base = cg_save(f, wa()); }
        done = cg_begin(f, 0x02, 0x40);
    }
    let again = cg_begin(f, 0x03, 0x40);
    if sequence && !stable_view {
        cg_emit_sequence(p, m, f, recipe); cg_pack_view(p, m, f, iterable.type_id, node); cg_set(f, view);
        cg_get(f, view); ws_count(f.code); cg_set(f, limit);
    }
    cg_get(f, counter); cg_get(f, limit); var comparison = T_GTEQ;
    if iterable.kind == N_RANGE && (iterable.flags & F_INCLUSIVE) != 0 { comparison = T_GT; }
    wb_byte(f.code, cg_numeric_opcode(comparison, cg_wasm_type(p, counter_type), cg_unsigned(p, counter_type))); cg_branch(p, f, done, true);
    let binding_type = p.symbols[element_binding].type_id;
    let elem_value = element_binding >= 0 && element_binding < f.slots.len && f.slots[element_binding].value;
    let elem_sroa = element_binding >= 0 && element_binding < f.slots.len && f.slots[element_binding].sroa_count > 0;
    var place = -1;
    if !elem_value && !elem_sroa { cg_symbol_address(p, m, f, element_binding, node); place = cg_save(f, wa()); }
    if sequence {
        let element = p.types[type_id].element;
        var sequence_base = hoisted_base;
        if sequence_base < 0 && cursor < 0 { cg_get(f, view); ws_ptr(f.code); sequence_base = cg_save(f, wa()); }
        if cursor >= 0 {
            // Seeking only when the next iteration begins preserves the
            // original decode behavior at break, continue and exhaustion.
            cg_get(f, counter); wb_i64(f.code, 0); wb_byte(f.code, 0x52); cg_begin(f, 0x04, 0x40);
            let previous = cg_read_uleb(p, m, f, cursor, node); cg_get(f, previous.cursor); cg_set(f, cursor); cg_end(f);
            cg_get(f, cursor);
        } else if p.types[element].storage == 1 { let at = cg_walk_elements(p, m, f, sequence_base, counter, node); cg_get(f, at); }
        else { cg_get(f, sequence_base); cg_get(f, counter); wa_wrap(f.code); wa_const(f.code, cg_size(p, element)); wa_op(f.code, 0x6c); wa_op(f.code, 0x6a); }
        if cg_type_kind(p, binding_type) != TY_REF || cg_type_kind(p, element) == TY_REF { cg_load(p, m, f, element, 0); cg_convert(p, m, f, element, binding_type, node); }
    } else { cg_get(f, counter); cg_convert(p, m, f, counter_type, binding_type, node); }
    if elem_value { cg_scalar_slot_store(p, f, element_binding); }
    else if elem_sroa { let src = cg_save(f, wa()); cg_sroa_load_from_addr(p, f, binding_type, src, f.slots[element_binding].local); }
    else { cg_write_value(p, m, f, binding_type, place, node); }
    if ordinal_binding >= 0 {
        let ord_type = p.symbols[ordinal_binding].type_id;
        if ordinal_binding < f.slots.len && f.slots[ordinal_binding].value {
            cg_get(f, ordinal); cg_convert(p, m, f, TYPE_U64, ord_type, node); cg_scalar_slot_store(p, f, ordinal_binding);
        } else {
            cg_symbol_address(p, m, f, ordinal_binding, node); let destination = cg_save(f, wa());
            cg_get(f, ordinal); cg_convert(p, m, f, TYPE_U64, ord_type, node); cg_write_value(p, m, f, ord_type, destination, node);
        }
    }
    let step = cg_begin(f, 0x02, 0x40); f.exits.push(CgExit { label: done, again: step, node: node, scratch: scratch, regions: regions, publication: publication, defers: f.defers.len });
    cg_block_into(p, m, f, n.right, TYPE_VOID, -1); f.exits.pop(); cg_end(f);
    if iterable.kind == N_RANGE && (iterable.flags & F_INCLUSIVE) != 0 {
        cg_get(f, counter); cg_get(f, limit); wb_byte(f.code, cg_numeric_opcode(T_EQ, cg_wasm_type(p, counter_type), false)); cg_branch(p, f, done, true);
    }
    cg_get(f, counter); if cg_wasm_type(p, counter_type) == 0x7e { wb_i64(f.code, 1); } else { wb_i32(f.code, 1); }
    wb_byte(f.code, cg_numeric_opcode(T_PLUS, cg_wasm_type(p, counter_type), false)); cg_normalize(p, f.code, counter_type); cg_set(f, counter);
    if ordinal_binding >= 0 && !sequence { cg_get(f, ordinal); wb_i64(f.code, 1); wb_byte(f.code, 0x7c); cg_set(f, ordinal); }
    cg_branch(p, f, again, false); cg_end(f); cg_end(f); f.hoists.resize(hoist_mark);
}
recursive fn cg_pattern(p: Program&, m: CgModule&, f: CgBody&, pattern: i64, type_id: i64, value: i64) {
    let n: const Node& = p.nodes[pattern];
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
    if cg_wide && cg_wasm_type(p, type_id) == 0x7b {
        // A slice is a v128: the same pointer and the same count.
        cg_to(p, m, f, pattern, type_id); let other = cg_save(f, ws());
        cg_get(f, value); ws_ptr(f.code); cg_get(f, other); ws_ptr(f.code); wb_byte(f.code, 0x51);
        cg_get(f, value); ws_count(f.code); cg_get(f, other); ws_count(f.code); wb_byte(f.code, 0x51); wb_byte(f.code, 0x71); return;
    }
    cg_get(f, value); cg_to(p, m, f, pattern, type_id); wb_byte(f.code, cg_numeric_opcode(T_EQ, cg_wasm_type(p, type_id), false));
}
recursive fn cg_match(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n: const Node& = p.nodes[node]; var id = p.nodes[n.left].type_id; cg_expr(p, m, f, n.left); if cg_diverges(p, n.left) { return; }
    if cg_type_kind(p, id) == TY_REF { id = p.types[id].element; cg_load(p, m, f, id, 0); }
    var base = -1;
    if cg_type_kind(p, id) == TY_ENUM {
        base = cg_save(f, wa()); cg_get(f, base);
        if cg_enum_image(p, id) { wa_load(f.code, 0); }
        if p.types[id].length_storage == 2 { wb_mem(f.code, 0x2f, 0, 0); } else { wb_mem(f.code, 0x2d, 0, 0); }
        id = TYPE_U32;
    }
    let value = cg_save(f, cg_wasm_type(p, id)); let result = cg_control_slots(p, f, n.type_id, node); let done = cg_begin(f, 0x02, 0x40);
    var arm = n.first;
    while arm >= 0 {
        let item: const Node& = p.nodes[arm]; cg_pattern(p, m, f, item.left, id, value); cg_begin(f, 0x04, 0x40);
        var binder = -1;
        if p.nodes[item.left].kind == N_PATTERN { binder = p.nodes[item.left].left; }
        if binder >= 0 && base >= 0 {
            let symbol = p.nodes[binder].symbol;
            var enum_id = p.nodes[n.left].type_id;
            if cg_type_kind(p, enum_id) == TY_REF { enum_id = p.types[enum_id].element; }
            var payload_type = p.symbols[symbol].type_id;
            if cg_type_kind(p, payload_type) == TY_REF { payload_type = p.types[payload_type].element; }
            let variant = p.types[payload_type].declaration;
            let payload = cg_enum_payload(p, m, f, enum_id, base, variant, arm);
            if symbol >= 0 && symbol < f.slots.len && f.slots[symbol].value {
                cg_get(f, payload); cg_scalar_slot_store(p, f, symbol);
            } else if symbol >= 0 && symbol < f.slots.len && f.slots[symbol].sroa_count > 0 {
                cg_sroa_load_from_addr(p, f, p.symbols[symbol].type_id, payload, f.slots[symbol].local);
            } else {
                cg_symbol_address(p, m, f, symbol, arm); let address = cg_save(f, wa());
                cg_get(f, payload); cg_write_value(p, m, f, p.symbols[symbol].type_id, address, arm);
            }
        }
        if item.third >= 0 { cg_truth(p, m, f, item.third); cg_begin(f, 0x04, 0x40); }
        cg_block_into(p, m, f, item.right, n.type_id, result); cg_branch(p, f, done, false);
        if item.third >= 0 { cg_end(f); } cg_end(f); arm = item.next;
    }
    cg_abort(p, m, f, node, "non-exhaustive match"); cg_end(f); cg_control_get(p, f, n.type_id, result);
}
// Whether a subtree may produce region-owned values. Results are memoized per
// node (0 unknown, 1 no, 2 yes): a subtree is scanned before any of it is emitted,
// and emission only retypes nodes that are being emitted.
recursive fn cg_may_print(p: Program&, m: CgModule&, node: i64) -> bool {
    if node < 0 { return false; }
    if node >= m.region_memo.len { m.region_memo.resize(p.nodes.len, 0); }
    let known = (m.region_memo[node] >> 2) & 3;
    if known != 0 { return known == 2; }
    var result = false; let n: const Node& = p.nodes[node];
    let kind = n.kind;
    if kind != N_FUNCTION && kind != N_FUNCTION_VALUE && kind != N_STRUCT && kind != N_ENUM && kind != N_ALIAS && kind != N_PATTERN {
        if kind == N_CALL && n.symbol >= 0 && n.symbol < p.symbols.len && (p.symbols[n.symbol].flags & S_BUILTIN) != 0 && p.symbols[n.symbol].index == 0 {
            result = true;
        } else {
            result = cg_may_print(p, m, n.left) || cg_may_print(p, m, n.right) || cg_may_print(p, m, n.third);
            var child = n.first; while !result && child >= 0 { result = cg_may_print(p, m, child); child = p.nodes[child].next; }
        }
    }
    var bits: u8 = 4; if result { bits = 8; }
    m.region_memo[node] = (m.region_memo[node] & 3) | bits;
    return result;
}
recursive fn cg_may_region(p: Program&, m: CgModule&, node: i64) -> bool {
    if node < 0 { return false; }
    if node >= m.region_memo.len { m.region_memo.resize(p.nodes.len, 0); }
    let known = m.region_memo[node] & 3; if known != 0 { return known == 2; }
    var result = false; let n: const Node& = p.nodes[node];
    let kind = n.kind;
    if kind != N_FUNCTION && kind != N_FUNCTION_VALUE && kind != N_STRUCT && kind != N_ENUM && kind != N_ALIAS && kind != N_PATTERN {
        if kind == N_NAME {
            result = false;
        } else if kind == N_MEMBER || kind == N_INDEX || kind == N_SLICE || kind == N_UNARY || kind == N_BINARY {
            if kind == N_MEMBER && n.symbol >= 0 && n.symbol < p.nodes.len && n.type_id != p.nodes[n.symbol].type_id && cg_region_owned_result(p, n.type_id) { result = true; }
            else if kind == N_INDEX && n.left >= 0 {
                var ot = p.nodes[n.left].type_id;
                if cg_type_kind(p, ot) == TY_REF { ot = p.types[ot].element; }
                if ot >= 0 && n.type_id != p.types[ot].element && cg_region_owned_result(p, n.type_id) { result = true; }
            }
            if !result { result = cg_may_region(p, m, n.left) || cg_may_region(p, m, n.right) || cg_may_region(p, m, n.third); }
        } else if kind == N_ASSIGN {
            if n.left >= 0 {
                var lid = p.nodes[n.left].type_id;
                while cg_type_kind(p, lid) == TY_REF { lid = p.types[lid].element; }
                result = cg_region_owned_result(p, lid);
            }
            if !result { result = cg_may_region(p, m, n.left) || cg_may_region(p, m, n.right); }
        } else if kind == N_RETURN {
            result = cg_region_owned_result(p, n.type_id);
            if !result && n.left >= 0 { result = cg_region_owned_result(p, p.nodes[n.left].type_id) || cg_may_region(p, m, n.left); }
            var child = n.first; while !result && child >= 0 {
                result = cg_region_owned_result(p, p.nodes[child].type_id) || cg_may_region(p, m, child);
                child = p.nodes[child].next;
            }
        } else if kind == N_CALL {
            result = cg_region_owned_result(p, n.type_id);
            if !result {
                if (n.flags & F_DISPATCH) != 0 {
                    var arg = n.first;
                    while !result && arg >= 0 {
                        var aid = p.nodes[arg].type_id;
                        while cg_type_kind(p, aid) == TY_REF { aid = p.types[aid].element; }
                        result = cg_region_owned_result(p, aid);
                        arg = p.nodes[arg].next;
                    }
                } else if n.symbol >= 0 && n.symbol < p.symbols.len && (p.symbols[n.symbol].flags & S_BUILTIN) != 0 {
                    let builtin = p.symbols[n.symbol].index;
                    if builtin == 1 || builtin == 2 { result = true; }
                    else if builtin == 0 {
                        var arg = n.first;
                        while !result && arg >= 0 {
                            var aid = p.nodes[arg].type_id;
                            while cg_type_kind(p, aid) == TY_REF { aid = p.types[aid].element; }
                            result = cg_region_owned_result(p, aid);
                            arg = p.nodes[arg].next;
                        }
                    } else if n.first >= 0 {
                        // Array/slice/pool builtins only copy elements if the element type owns a region.
                        var rid = p.nodes[n.first].type_id;
                        if cg_type_kind(p, rid) == TY_REF { rid = p.types[rid].element; }
                        if rid >= 0 && (cg_type_kind(p, rid) == TY_ARRAY || cg_type_kind(p, rid) == TY_SLICE) {
                            result = cg_region_owned_result(p, p.types[rid].element);
                        } else {
                            var arg = n.first;
                            while !result && arg >= 0 {
                                result = cg_region_owned_result(p, p.nodes[arg].type_id);
                                arg = p.nodes[arg].next;
                            }
                        }
                    }
                } else if n.symbol >= 0 && n.symbol < p.symbols.len && (p.symbols[n.symbol].flags & S_FUNCTION) != 0 && p.symbols[n.symbol].node >= 0 {
                    var param = p.nodes[p.symbols[n.symbol].node].first;
                    while !result && param >= 0 {
                        result = cg_region_owned_result(p, p.nodes[param].type_id);
                        param = p.nodes[param].next;
                    }
                } else {
                    var arg = n.first;
                    while !result && arg >= 0 {
                        result = cg_region_owned_result(p, p.nodes[arg].type_id);
                        arg = p.nodes[arg].next;
                    }
                }
            }
            if !result { result = cg_may_region(p, m, n.left) || cg_may_region(p, m, n.right) || cg_may_region(p, m, n.third); }
            var child = n.first; while !result && child >= 0 { result = cg_may_region(p, m, child); child = p.nodes[child].next; }
        } else if kind == N_VARIABLE {
            result = cg_region_owned_result(p, n.type_id) || root_struct_type(p, n.type_id);
            var child = n.first;
            while !result && child >= 0 {
                let cid = p.nodes[child].type_id;
                result = cg_region_owned_result(p, cid) || root_struct_type(p, cid);
                child = p.nodes[child].next;
            }
            if !result { result = cg_may_region(p, m, n.right); }
        } else {
            result = cg_region_owned_result(p, n.type_id) || cg_may_region(p, m, n.left) || cg_may_region(p, m, n.right) || cg_may_region(p, m, n.third);
            var child = n.first; while !result && child >= 0 { result = cg_may_region(p, m, child); child = p.nodes[child].next; }
        }
    }
    var rbits: u8 = 1; if result { rbits = 2; }
    m.region_memo[node] = (m.region_memo[node] & 12) | rbits;
    return result;
}
recursive fn cg_statement(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    if !m.regions_enabled || p.nodes[node].kind == N_VARIABLE || !cg_may_region(p, m, node) { cg_statement_body(p, m, f, node); return; }
    let live = f.region_live; let acq = f.acquisitions; let mark = cg_mark_regions(f); cg_statement_body(p, m, f, node);
    if f.acquisitions != acq { cg_restore_regions(f, mark); }
    f.region_live = live;
}
recursive fn cg_statement_body(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let kind = p.nodes[node].kind;
    if kind == N_VARIABLE { cg_declaration(p, m, f, node); return; }
    if kind == N_ASSIGN { cg_assign(p, m, f, node); return; }
    if kind == N_RETURN { cg_emit_return(p, m, f, node); return; }
    if kind == N_BREAK { cg_break(p, m, f, node, false); return; }
    if kind == N_CONTINUE { cg_break(p, m, f, node, true); return; }
    if kind == N_FUNCTION || kind == N_STRUCT || kind == N_ENUM || kind == N_ALIAS || kind == N_EMPTY || kind == N_IMPORT { return; }
    if kind == N_EXPR_STMT { cg_discard(p, m, f, p.nodes[node].left); return; }
    if kind == N_FOR { cg_for(p, m, f, node); return; }
    if kind == N_DEFER { cg_fail(p, node, "wasm: defer statement outside an emitted block"); return; }
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
        cg_get(f, value); cg_pack_view(p, m, f, id, node); let view = cg_save(f, ws());
        cg_get(f, view); ws_ptr(f.code); let pointer = cg_save(f, wa());
        cg_get(f, view); ws_len(f.code); let length = cg_save(f, wa());
        let element = p.types[id].element;
        if element == TYPE_U8 && !nested { cg_get(f, pointer); cg_get(f, length); wa_to_i32(f.code); wb_op(f.code, 0x10, CG_WRITE); return; }
        if element == TYPE_U8 { cg_text(m, f, "\""); } else { cg_text(m, f, "["); }
        wa_const(f.code, 0); let index = cg_save(f, wa());
        let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
        cg_get(f, index); cg_get(f, length); wa_op(f.code, 0x4f); cg_branch(p, f, done, true);
        if element == TYPE_U8 {
            cg_get(f, pointer); cg_get(f, index); wa_op(f.code, 0x6a); wb_mem(f.code, 0x2d, 0, 0); let byte = cg_save(f, 0x7f);
            let emitted = cg_begin(f, 0x02, 0x40);
            for character in [34, 92, 10, 13, 9] {
                cg_get(f, byte); wb_i32(f.code, character); wb_byte(f.code, 0x46); cg_begin(f, 0x04, 0x40);
                if character == 34 { cg_text(m, f, "\\\""); } else if character == 92 { cg_text(m, f, "\\\\"); }
                else if character == 10 { cg_text(m, f, "\\n"); } else if character == 13 { cg_text(m, f, "\\r"); } else { cg_text(m, f, "\\t"); }
                cg_branch(p, f, emitted, false); cg_end(f);
            }
            cg_get(f, pointer); cg_get(f, index); wa_op(f.code, 0x6a); wb_i32(f.code, 1); wb_op(f.code, 0x10, CG_WRITE); cg_end(f);
        } else {
            cg_get(f, index); wa_truth(f.code); cg_begin(f, 0x04, 0x40); cg_text(m, f, ", "); cg_end(f);
            if p.types[element].storage == 1 {
                cg_get(f, index); wa_extend(f.code); let index64 = cg_save(f, 0x7e); let cursor = cg_walk_elements(p, m, f, pointer, index64, node); cg_get(f, cursor);
            } else { cg_get(f, pointer); cg_get(f, index); wa_const(f.code, cg_size(p, element)); wa_op(f.code, 0x6c); wa_op(f.code, 0x6a); }
            cg_load(p, m, f, element, 0); let item = cg_save(f, cg_wasm_type(p, element)); cg_print(p, m, f, element, item, node, true);
        }
        cg_get(f, index); wa_const(f.code, 1); wa_op(f.code, 0x6a); cg_set(f, index); cg_branch(p, f, again, false); cg_end(f); cg_end(f);
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
        cg_get(f, value); if cg_enum_image(p, id) { wa_load(f.code, 0); } var load = 0x2d; if p.types[id].length_storage == 2 { load = 0x2f; }
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
// A string literal as a slice: its data address and its byte count.
fn wC_slice_const(out: u8[>..]&, address: i64, count: i64) {
    if !cg_wide { wb_i64(out, address | (count << 32)); return; }
    wb_byte(out, 0xfd); wb_u(out, 0x0c);
    for part in 0..8 { wb_byte(out, address >> (part * 8)); }
    for part in 0..8 { wb_byte(out, count >> (part * 8)); }
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
    else { cg_get(f, base); wa_const(f.code, cg_static_prefix(p, id)); wa_op(f.code, 0x6a); }
}
fn cg_array_element(p: Program&, m: CgModule&, f: CgBody&, id: i64, base: i64, index: i64) {
    cg_array_pointer(p, m, f, id, base); cg_get(f, index); cg_scale_index(f, cg_size(p, p.types[id].element)); wa_op(f.code, 0x6a);
}
fn cg_pool_state(p: Program&, m: CgModule&, f: CgBody&, header: i64, node: i64) -> i64 {
    if m.pool_global < 0 { cg_fail(p, node, "wasm: reusable pool state was not planned"); wa_const(f.code, 0); return cg_save(f, wa()); }
    cg_get(f, header); cg_resolve_pointer(m, f); cg_canonical_address(m, f, wc_bytes());
    if m.pool_state_fn >= 0 { wb_op(f.code, 0x10, m.pool_state_fn); return cg_save(f, wa()); }
    let owner = cg_save(f, wa());
    wb_op(f.code, 0x23, m.pool_global); let cursor = cg_save(f, wa()); wa_const(f.code, 0); let result = cg_save(f, wa());
    let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
    cg_get(f, cursor); wa_op(f.code, 0x45); cg_branch(p, f, done, true);
    cg_get(f, cursor); wa_load(f.code, ww(1)); cg_get(f, owner); wa_op(f.code, 0x46); cg_begin(f, 0x04, 0x40);
    cg_get(f, cursor); cg_set(f, result); cg_branch(p, f, done, false); cg_end(f);
    cg_get(f, cursor); wa_load(f.code, 0); cg_set(f, cursor); cg_branch(p, f, again, false); cg_end(f); cg_end(f);
    cg_get(f, result); wa_op(f.code, 0x45); cg_begin(f, 0x04, 0x40);
    let scratch = f.scratch; f.scratch = false; wa_const(f.code, ww(5)); cg_allocate(p, m, f, node); f.scratch = scratch; cg_set(f, result);
    cg_get(f, result); cg_clear_bytes(p, f, ww(5));
    cg_get(f, result); wb_op(f.code, 0x23, m.pool_global); wa_store(f.code, 0);
    cg_get(f, result); cg_get(f, owner); wa_store(f.code, ww(1)); cg_get(f, result); wb_op(f.code, 0x24, m.pool_global); cg_end(f);
    return result;
}
fn cg_pool_reserve(p: Program&, m: CgModule&, f: CgBody&, state: i64, count: i64, node: i64) {
    cg_get(f, state); wa_load(f.code, ww(4)); let old = cg_save(f, wa());
    cg_get(f, count); cg_get(f, old); wa_op(f.code, 0x4b); cg_begin(f, 0x04, 0x40);
    cg_get(f, old); wa_extend(f.code); wb_i64(f.code, 2); wb_byte(f.code, 0x7e); let capacity = cg_save(f, 0x7e);
    cg_get(f, capacity); cg_get(f, count); wa_extend(f.code); cg_get(f, capacity); cg_get(f, count); wa_extend(f.code); wb_byte(f.code, 0x56); wb_byte(f.code, 0x1b); cg_set(f, capacity);
    cg_get(f, capacity); wb_i64(f.code, 1073741823); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "reusable pool freelist exceeds wasm32 range");
    let scratch = f.scratch; f.scratch = false; cg_get(f, capacity); wb_i64(f.code, wa_bytes()); wb_byte(f.code, 0x7e); wa_wrap(f.code); cg_allocate(p, m, f, node); f.scratch = scratch; let data = cg_save(f, wa());
    cg_get(f, data); cg_get(f, state); wa_load(f.code, ww(2)); cg_get(f, state); wa_load(f.code, ww(3)); wa_const(f.code, wa_bytes()); wa_op(f.code, 0x6c); wb_copy(f.code);
    cg_get(f, state); cg_get(f, data); wa_store(f.code, ww(2)); cg_get(f, state); cg_get(f, capacity); wa_wrap(f.code); wa_store(f.code, ww(4)); cg_end(f);
}
fn cg_message_bytes(f: CgBody&, cursor: i64, text: CgText) {
    cg_get(f, cursor); cg_get(f, text.data); cg_get(f, text.length); wb_copy(f.code);
    cg_get(f, cursor); cg_get(f, text.length); wa_op(f.code, 0x6a); cg_set(f, cursor);
}
fn cg_message_literal(m: CgModule&, f: CgBody&, cursor: i64, text: u8[:]) {
    wa_const(f.code, cg_data(m, text)); let data = cg_save(f, wa()); wa_const(f.code, text.len); let length = cg_save(f, wa());
    cg_message_bytes(f, cursor, CgText { data: data, length: length });
}
fn cg_abort_index(p: Program&, m: CgModule&, f: CgBody&, index: i64, length: i64, node: i64) {
    let frame = cg_frame(f, 96, 1); cg_frame_address(f, frame); let buffer = cg_save(f, wa()); cg_get(f, buffer); let cursor = cg_save(f, wa());
    cg_message_literal(m, f, cursor, "index "); cg_message_bytes(f, cursor, cg_integer_text(p, f, TYPE_I64, index));
    cg_message_literal(m, f, cursor, " out of bounds (length "); cg_get(f, length); wa_extend(f.code); let count = cg_save(f, 0x7e);
    cg_message_bytes(f, cursor, cg_integer_text(p, f, TYPE_U64, count)); cg_message_literal(m, f, cursor, ")");
    cg_get(f, buffer); cg_get(f, cursor); cg_get(f, buffer); wa_op(f.code, 0x6b); wa_to_i32(f.code);
    cg_line(p, f, node); wb_op(f.code, 0x10, CG_ABORT); wb_byte(f.code, 0);
}
fn cg_zero_default_scalar(p: Program&, element: i64, def_node: i64) -> bool {
    let k = cg_type_kind(p, element);
    if k == TY_INT && p.types[element].storage == 0 {
        return def_node < 0 || p.nodes[def_node].kind == N_INTEGER && p.nodes[def_node].integer == 0;
    }
    if k == TY_BOOL { return def_node < 0 || p.nodes[def_node].kind == N_BOOL && p.nodes[def_node].integer == 0; }
    if k == TY_FLOAT { return def_node < 0 || p.nodes[def_node].kind == N_FLOAT && p.nodes[def_node].float_value == 0.0; }
    if k == TY_SLICE { return def_node < 0 || p.nodes[def_node].kind == N_ARRAY && p.nodes[def_node].first < 0; }
    return false;
}
recursive fn cg_slice_pool_builtin(p: Program&, m: CgModule&, f: CgBody&, node: i64, builtin: i64, id: i64, header: i64, arg1: i64) {
    let n: const Node& = p.nodes[node]; let element = p.types[id].element; let width = cg_size(p, element);
    if !cg_owner(p, id) || p.types[id].array_kind != A_GROW || cg_has_owner(p, element) || width <= 0 {
        cg_fail(p, node, "wasm: reusable slice pools require fixed-size growable elements"); return;
    }
    if m.spans_alloc < 0 { cg_fail(p, node, "wasm: reusable slice pool helpers were not planned"); return; }
    var old_view = -1;
    if builtin == 34 || builtin == 35 {
        cg_expr(p, m, f, arg1); if cg_diverges(p, arg1) { return; }
        cg_pack_view(p, m, f, p.nodes[arg1].type_id, node);
        old_view = cg_save(f, ws());
    }
    var count64 = -1;
    if builtin == 33 || builtin == 34 {
        var count_arg = arg1; if builtin == 34 { count_arg = p.nodes[arg1].next; }
        cg_to(p, m, f, count_arg, TYPE_I64); if cg_diverges(p, count_arg) { return; }
        count64 = cg_save(f, 0x7e);
        var max_bytes = p.maximum_pages * 65536;
        if !cg_wide && max_bytes > 2147483648 { max_bytes = 2147483648; }
        var max_count = max_bytes / width;
        if max_count > wn_limit() { max_count = wn_limit(); }
        cg_get(f, count64); wb_i64(f.code, max_count); wb_byte(f.code, 0x56);
        cg_trap_if(p, m, f, node, "invalid slice length");
    }
    wb_i64(f.code, 0); let old_idx = cg_save(f, 0x7e);
    wb_i64(f.code, 0); let old_len = cg_save(f, 0x7e);
    if old_view >= 0 {
        cg_get(f, old_view); ws_count(f.code); cg_set(f, old_len);
        cg_get(f, old_len); wb_i64(f.code, 0); wb_byte(f.code, 0x52); cg_begin(f, 0x04, 0x40);
        cg_get(f, old_view); ws_ptr(f.code); cg_resolve_pointer(m, f); let old_ptr = cg_save(f, wa());
        cg_array_pointer(p, m, f, id, header); let pool_ptr = cg_save(f, wa());
        cg_array_length(p, m, f, id, header); let pool_len_wa = cg_save(f, wa());
        cg_get(f, old_ptr); cg_get(f, pool_ptr); wa_op(f.code, 0x6b); let offset = cg_save(f, wa());
        cg_get(f, offset); wa_const(f.code, width); wa_op(f.code, 0x6e); let start = cg_save(f, wa());
        cg_get(f, old_ptr); cg_get(f, pool_ptr); wa_op(f.code, 0x49);
        cg_get(f, offset); wa_const(f.code, width); wa_op(f.code, 0x70); wa_truth(f.code); wb_byte(f.code, 0x72);
        cg_get(f, start); cg_get(f, pool_len_wa); wa_op(f.code, 0x4f); wb_byte(f.code, 0x72);
        cg_get(f, old_len); cg_get(f, pool_len_wa); cg_get(f, start); wa_op(f.code, 0x6b); wa_extend(f.code); wb_byte(f.code, 0x56); wb_byte(f.code, 0x72);
        cg_trap_if(p, m, f, node, "slice not from this pool");
        cg_get(f, start); wa_extend(f.code); cg_set(f, old_idx);
        cg_end(f);
    }
    let state = cg_pool_state(p, m, f, header, node);
    if builtin == 35 {
        cg_get(f, old_len); wb_i64(f.code, 0); wb_byte(f.code, 0x52); cg_begin(f, 0x04, 0x40);
        cg_get(f, state); cg_get(f, old_idx); cg_get(f, old_len); wb_op(f.code, 0x10, m.spans_free);
        cg_end(f); return;
    }
    cg_array_length(p, m, f, id, header); wa_extend(f.code); let pool_len = cg_save(f, 0x7e);
    wb_i64(f.code, 0); let new_idx = cg_save(f, 0x7e);
    if builtin == 33 {
        cg_get(f, state); cg_get(f, pool_len); cg_get(f, count64); wb_op(f.code, 0x10, m.spans_alloc); cg_set(f, new_idx);
    } else {
        cg_get(f, count64); cg_get(f, old_len); wb_byte(f.code, 0x57); cg_begin(f, 0x04, 0x40);
        cg_get(f, old_len); cg_get(f, count64); wb_byte(f.code, 0x55); cg_begin(f, 0x04, 0x40);
        cg_get(f, state); cg_get(f, old_idx); cg_get(f, count64); wb_byte(f.code, 0x7c);
        cg_get(f, old_len); cg_get(f, count64); wb_byte(f.code, 0x7d);
        wb_op(f.code, 0x10, m.spans_free); cg_end(f);
        cg_get(f, old_idx); cg_set(f, new_idx);
        cg_control(f, 0x05);
        cg_get(f, old_len); wb_byte(f.code, 0x50); cg_begin(f, 0x04, 0x40);
        cg_get(f, state); cg_get(f, pool_len); cg_get(f, count64); wb_op(f.code, 0x10, m.spans_alloc); cg_set(f, new_idx);
        cg_control(f, 0x05);
        cg_get(f, old_idx); cg_get(f, old_len); wb_byte(f.code, 0x7c); cg_get(f, pool_len); wb_byte(f.code, 0x51); cg_begin(f, 0x04, 0x40);
        cg_get(f, old_idx); cg_set(f, new_idx);
        cg_control(f, 0x05);
        cg_get(f, state); cg_get(f, pool_len); cg_get(f, old_idx); cg_get(f, old_len); cg_get(f, count64); wb_op(f.code, 0x10, m.spans_regrow); cg_set(f, new_idx);
        cg_end(f); cg_end(f); cg_end(f);
    }
    cg_get(f, count64); cg_get(f, old_len); wb_byte(f.code, 0x55); cg_begin(f, 0x04, 0x40);
    cg_get(f, new_idx); wb_i64(f.code, wn_limit()); cg_get(f, count64); wb_byte(f.code, 0x7d); wb_byte(f.code, 0x56);
    cg_trap_if(p, m, f, node, "pool slice length overflow");
    cg_get(f, new_idx); cg_get(f, count64); wb_byte(f.code, 0x7c); let end64 = cg_save(f, 0x7e);
    cg_get(f, end64); wa_wrap(f.code); let end_wa = cg_save(f, wa());
    cg_get(f, end64); cg_get(f, pool_len); wb_byte(f.code, 0x55); cg_begin(f, 0x04, 0x40);
    cg_array_reserve(p, m, f, id, header, end_wa, node);
    cg_end(f);
    if builtin == 34 {
        cg_get(f, old_len); wb_i64(f.code, 0); wb_byte(f.code, 0x52);
        cg_get(f, new_idx); cg_get(f, old_idx); wb_byte(f.code, 0x52); wb_byte(f.code, 0x71);
        cg_begin(f, 0x04, 0x40);
        cg_array_pointer(p, m, f, id, header); let cur_p = cg_save(f, wa());
        cg_get(f, cur_p); cg_get(f, new_idx); wa_wrap(f.code); cg_scale_index(f, width); wa_op(f.code, 0x6a);
        cg_get(f, cur_p); cg_get(f, old_idx); wa_wrap(f.code); cg_scale_index(f, width); wa_op(f.code, 0x6a);
        cg_get(f, old_len); wa_wrap(f.code); cg_scale_index(f, width); wb_copy(f.code);
        cg_end(f);
    }
    cg_get(f, end64); cg_get(f, pool_len); wb_byte(f.code, 0x55); cg_begin(f, 0x04, 0x40);
    cg_array_set_length(p, m, f, id, header, end_wa);
    cg_end(f);
    cg_array_pointer(p, m, f, id, header); let init_ptr = cg_save(f, wa());
    if cg_zero_default_scalar(p, element, n.aux) {
        cg_get(f, init_ptr); cg_get(f, new_idx); cg_get(f, old_len); wb_byte(f.code, 0x7c); wa_wrap(f.code); cg_scale_index(f, width); wa_op(f.code, 0x6a);
        wb_i32(f.code, 0);
        cg_get(f, count64); cg_get(f, old_len); wb_byte(f.code, 0x7d); wa_wrap(f.code); cg_scale_index(f, width);
        wb_fill(f.code);
    } else {
        var tmpl = -1;
        if n.aux >= 0 && !cg_fixed_relative(p, element) {
            cg_to(p, m, f, n.aux, element);
            tmpl = cg_save(f, cg_wasm_type(p, element));
            if cg_aggregate(p, element) {
                let copy = cg_temporary(p, f, element);
                cg_copy(p, m, f, element, copy, tmpl, n.aux);
                tmpl = copy;
            }
        }
        cg_get(f, old_len); let idx_i = cg_save(f, 0x7e);
        let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
        cg_get(f, idx_i); cg_get(f, count64); wb_byte(f.code, 0x59); cg_branch(p, f, done, true);
        cg_get(f, init_ptr); cg_get(f, new_idx); cg_get(f, idx_i); wb_byte(f.code, 0x7c); wa_wrap(f.code); cg_scale_index(f, width); wa_op(f.code, 0x6a);
        let elem_addr = cg_save(f, wa());
        if tmpl >= 0 {
            if cg_aggregate(p, element) {
                cg_get(f, elem_addr); cg_get(f, tmpl); wa_const(f.code, width); wb_copy(f.code);
            } else {
                cg_get(f, tmpl); cg_write_value(p, m, f, element, elem_addr, node);
            }
        } else if n.aux >= 0 {
            cg_fixed_to(p, m, f, n.aux, element, elem_addr);
        } else {
            cg_default_storage(p, m, f, element, elem_addr, node);
        }
        cg_get(f, idx_i); wb_i64(f.code, 1); wb_byte(f.code, 0x7c); cg_set(f, idx_i);
        cg_branch(p, f, again, false); cg_end(f); cg_end(f);
    }
    cg_end(f);
    cg_array_pointer(p, m, f, id, header); cg_get(f, new_idx); wa_wrap(f.code); cg_scale_index(f, width); wa_op(f.code, 0x6a);
    wa_extend(f.code); cg_get(f, count64); ws_pack(f);
}
recursive fn cg_pool_builtin(p: Program&, m: CgModule&, f: CgBody&, node: i64, builtin: i64) {
    let n: const Node& = p.nodes[node]; let receiver = n.first; let argument = p.nodes[receiver].next; var id = p.nodes[receiver].type_id;
    cg_expr(p, m, f, receiver); if cg_type_kind(p, id) == TY_REF { id = p.types[id].element; cg_load(p, m, f, id, 0); }
    let header = cg_save(f, wa()); let element = p.types[id].element;
    if builtin >= 33 && builtin <= 35 { cg_slice_pool_builtin(p, m, f, node, builtin, id, header, argument); return; }
    if !cg_owner(p, id) || p.types[id].array_kind != A_GROW || cg_has_owner(p, element) || cg_size(p, element) <= 0 {
        cg_fail(p, node, "wasm: reusable slot pools require fixed-size growable elements"); return;
    }
    if builtin == 32 {
        cg_to(p, m, f, argument, TYPE_U64); if cg_diverges(p, argument) { return; } let index = cg_save(f, 0x7e);
        cg_array_length(p, m, f, id, header); let length = cg_save(f, wa());
        cg_get(f, index); cg_get(f, length); wa_extend(f.code); wb_byte(f.code, 0x5a); cg_begin(f, 0x04, 0x40); cg_abort_index(p, m, f, index, length, node); cg_end(f);
        let state = cg_pool_state(p, m, f, header, node); cg_get(f, state); wa_load(f.code, ww(3)); let old = cg_save(f, wa());
        cg_get(f, old); wa_const(f.code, -1); wa_op(f.code, 0x46); cg_trap_if(p, m, f, node, "reusable pool freelist exceeds wasm32 range");
        cg_get(f, old); wa_const(f.code, 1); wa_op(f.code, 0x6a); let count = cg_save(f, wa()); cg_pool_reserve(p, m, f, state, count, node);
        cg_get(f, state); wa_load(f.code, ww(2)); cg_get(f, old); wa_const(f.code, wa_bytes()); wa_op(f.code, 0x6c); wa_op(f.code, 0x6a); cg_get(f, index); wa_wrap(f.code); wa_store(f.code, 0);
        cg_get(f, state); cg_get(f, count); wa_store(f.code, ww(3)); return;
    }
    let direct = cg_fixed_relative(p, element); var value = -1;
    if !direct {
        cg_to(p, m, f, argument, element); if cg_diverges(p, argument) { return; } value = cg_save(f, cg_wasm_type(p, element));
        if cg_aggregate(p, element) { let copy = cg_temporary(p, f, element); cg_copy(p, m, f, element, copy, value, argument); value = copy; }
    }
    let state = cg_pool_state(p, m, f, header, node); cg_array_length(p, m, f, id, header); let old = cg_save(f, wa());
    cg_get(f, state); wa_load(f.code, ww(3)); let free_count = cg_save(f, wa()); cg_get(f, old); let index = cg_save(f, wa()); wb_i32(f.code, 0); let fresh = cg_save(f, 0x7f);
    cg_get(f, free_count); wa_truth(f.code); cg_begin(f, 0x04, 0x40);
    cg_get(f, free_count); wa_const(f.code, 1); wa_op(f.code, 0x6b); cg_set(f, free_count); cg_get(f, state); cg_get(f, free_count); wa_store(f.code, ww(3));
    cg_get(f, state); wa_load(f.code, ww(2)); cg_get(f, free_count); wa_const(f.code, wa_bytes()); wa_op(f.code, 0x6c); wa_op(f.code, 0x6a); wa_load(f.code, 0); cg_set(f, index);
    cg_control(f, 0x05); wb_i32(f.code, 1); cg_set(f, fresh); cg_end(f);
    cg_get(f, fresh); cg_begin(f, 0x04, 0x40);
    cg_get(f, old); wa_const(f.code, -1); wa_op(f.code, 0x46); cg_trap_if(p, m, f, node, "array length overflow");
    cg_get(f, old); wa_const(f.code, 1); wa_op(f.code, 0x6a); let count = cg_save(f, wa()); cg_array_reserve(p, m, f, id, header, count, node); cg_end(f);
    cg_array_element(p, m, f, id, header, index); let destination = cg_save(f, wa());
    if direct { cg_fixed_to(p, m, f, argument, element, destination); if cg_diverges(p, argument) { return; } }
    else { cg_get(f, value); cg_write_value(p, m, f, element, destination, node); }
    cg_get(f, fresh); cg_begin(f, 0x04, 0x40); cg_get(f, old); wa_const(f.code, 1); wa_op(f.code, 0x6a); let count = cg_save(f, wa()); cg_array_set_length(p, m, f, id, header, count); cg_end(f);
    if builtin == 30 { cg_get(f, index); wa_extend(f.code); cg_convert(p, m, f, TYPE_I64, n.type_id, node); }
    else {
        cg_get(f, destination); if cg_type_kind(p, element) == TY_REF { cg_load(p, m, f, element, 0); cg_convert(p, m, f, element, n.type_id, node); }
        else if cg_type_kind(p, n.type_id) != TY_REF { cg_load(p, m, f, element, 0); cg_convert(p, m, f, element, n.type_id, node); }
    }
}
fn cg_array_reserve(p: Program&, m: CgModule&, f: CgBody&, id: i64, base: i64, count: i64, node: i64) {
    if !cg_owner(p, id) {
        cg_get(f, count); wa_const(f.code, p.types[id].count); wa_op(f.code, 0x4b); cg_trap_if(p, m, f, node, "limited array capacity exceeded"); return;
    }
    cg_owner_read_capacity(p, m, f, base); let old_capacity = cg_save(f, wa());
    cg_get(f, count); cg_get(f, old_capacity); wa_op(f.code, 0x4b); cg_begin(f, 0x04, 0x40);
    if p.types[id].array_kind != A_GROW && p.types[id].array_kind != A_GROWSHRINK { cg_abort(p, m, f, node, "limited array capacity exceeded"); }
    cg_get(f, old_capacity); wa_extend(f.code); wb_i64(f.code, 2); wb_byte(f.code, 0x7e); cg_get(f, count); wa_extend(f.code);
    cg_get(f, old_capacity); wa_extend(f.code); wb_i64(f.code, 2); wb_byte(f.code, 0x7e); cg_get(f, count); wa_extend(f.code); wb_byte(f.code, 0x56); wb_byte(f.code, 0x1b);
    let capacity64 = cg_save(f, 0x7e);
    cg_get(f, capacity64); wb_i64(f.code, wn_limit()); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array capacity overflow");
    wG_check_product(p, m, f, capacity64, cg_size(p, p.types[id].element), node, "array byte size overflow");
    cg_get(f, capacity64); wb_i64(f.code, cg_size(p, p.types[id].element)); wb_byte(f.code, 0x7e); let bytes64 = cg_save(f, 0x7e);
    cg_get(f, bytes64); wb_i64(f.code, wn_limit()); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array byte size overflow");
    cg_get(f, bytes64); wa_wrap(f.code); cg_allocate(p, m, f, node); let pointer = cg_save(f, wa());
    cg_array_pointer(p, m, f, id, base); let original = cg_save(f, wa());
    cg_get(f, pointer); cg_get(f, original); cg_array_length(p, m, f, id, base); wa_const(f.code, cg_size(p, p.types[id].element)); wa_op(f.code, 0x6c); wb_copy(f.code);
    cg_get(f, old_capacity); wa_const(f.code, cg_size(p, p.types[id].element)); wa_op(f.code, 0x6c); let old_bytes = cg_save(f, wa()); cg_forward_span(p, m, f, original, old_bytes, pointer);
    cg_get(f, base); cg_get(f, pointer); wc_store(f.code, 0);
    cg_get(f, base); cg_get(f, pointer); cg_get(f, bytes64); wa_wrap(f.code); wa_op(f.code, 0x6a); wc_store(f.code, 2);
    cg_get(f, base); cg_get(f, capacity64); wa_wrap(f.code); wc_store(f.code, 3); cg_end(f);
}
fn cg_region_array_bytes(p: Program&, m: CgModule&, f: CgBody&, id: i64, count: i64, node: i64) -> i64 {
    wG_check_product(p, m, f, count, cg_size(p, p.types[id].element), node, "data region exhausted");
    cg_get(f, count); wa_extend(f.code); wb_i64(f.code, cg_size(p, p.types[id].element)); wb_byte(f.code, 0x7e); return cg_save(f, 0x7e);
}
fn cg_region_rewind(p: Program&, m: CgModule&, f: CgBody&, header: i64, bytes: i64, node: i64) -> i64 {
    let cursor = cg_region_cursor(f, header); cg_get(f, cursor); wa_extend(f.code); cg_get(f, header); wc_load(f.code, 0); wa_extend(f.code); cg_get(f, bytes); wb_byte(f.code, 0x7c); wb_byte(f.code, 0x54);
    cg_trap_if(p, m, f, node, "data region exhausted"); cg_get(f, cursor); cg_get(f, bytes); wa_wrap(f.code); wa_op(f.code, 0x6b); let top = cg_save(f, wa()); cg_region_publish(f, header, top); return top;
}
recursive fn cg_append_relative_literal(p: Program&, m: CgModule&, f: CgBody&, node: i64, id: i64, header: i64, literal: i64) {
    let element = p.types[id].element; let added = cg_literal_count(p, m, f, literal);
    cg_array_length(p, m, f, id, header); let old = cg_save(f, wa());
    cg_get(f, old); wa_extend(f.code); cg_get(f, added); wa_extend(f.code); wb_byte(f.code, 0x7c); let wide = cg_save(f, 0x7e);
    cg_get(f, wide); wb_i64(f.code, wn_limit()); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array length overflow"); cg_get(f, wide); wa_wrap(f.code); let count = cg_save(f, wa());
    let region = m.regions_enabled && cg_region_value(p, id);
    let grow = p.types[id].array_kind == A_GROW || p.types[id].array_kind == A_GROWSHRINK;
    var destination = -1; var top = -1;
    if region && grow {
        let bytes = cg_region_array_bytes(p, m, f, id, added, node); top = cg_region_reserve(p, m, f, header, bytes, node); destination = cg_region_cursor(f, header);
    } else {
        if region { cg_get(f, count); cg_owner_read_capacity(p, m, f, header); wa_op(f.code, 0x4b); cg_trap_if(p, m, f, node, "limited array capacity exceeded"); }
        else { cg_array_reserve(p, m, f, id, header, count, node); }
        cg_array_element(p, m, f, id, header, old); destination = cg_save(f, wa());
    }
    cg_literal_elements(p, m, f, literal, element, destination, added); if cg_diverges(p, literal) { return; }
    if region && grow { cg_region_publish(f, header, top); }
    cg_array_set_length(p, m, f, id, header, count);
}
recursive fn cg_region_array_builtin(p: Program&, m: CgModule&, f: CgBody&, node: i64, builtin: i64, id: i64, header: i64, arg: i64) {
    let element = p.types[id].element; let grow = p.types[id].array_kind == A_GROW || p.types[id].array_kind == A_GROWSHRINK;
    if builtin == 29 {
        wa_const(f.code, 0); let zero = cg_save(f, wa()); cg_owner_set_length(p, m, f, header, zero, node);
        if grow { cg_owner_read_base(p, m, f, header, node); let base = cg_save(f, wa()); cg_region_publish(f, header, base); } return;
    }
    if builtin == 24 {
        let direct = cg_fixed_relative(p, element); var value = -1; var sroa_push_base = -1;
        if !direct && p.optimization >= 2 && m.resolver < 0 && m.prefix_helper < 0 && arg >= 0 && p.nodes[arg].type_id == element {
            let sc = cg_sroa_struct(p, element);
            if sc > 0 {
                if p.nodes[arg].kind == N_NAME && p.nodes[arg].symbol >= 0 && p.nodes[arg].symbol < f.slots.len && f.slots[p.nodes[arg].symbol].sroa_count > 0 {
                    sroa_push_base = f.slots[p.nodes[arg].symbol].local;
                } else if p.nodes[arg].kind == N_RECORD && !cg_record_has_self(p, arg) && !cg_record_has_extern(p, arg) || cg_call_sroa_return(p, m, arg) == sc {
                    sroa_push_base = cg_sroa_alloc_locals(p, f, element);
                    cg_emit_into_sroa(p, m, f, arg, element, sroa_push_base, sc, true);
                    if cg_diverges(p, arg) { return; }
                }
            }
        }
        if !direct && sroa_push_base < 0 { cg_to(p, m, f, arg, element); value = cg_save(f, cg_wasm_type(p, element)); }
        cg_owner_read_length(p, m, f, header, node); let old = cg_save(f, wa());
        let stride = cg_size(p, element);
        if !grow || stride == 0 {
            cg_get(f, old); wa_const(f.code, -1); wa_op(f.code, 0x46); cg_trap_if(p, m, f, node, "data region exhausted");
        }
        cg_get(f, old); wa_const(f.code, 1); wa_op(f.code, 0x6a); let count = cg_save(f, wa()); var destination = -1;
        var reserved = CgReserved { cursor: -1, limit: -1, top: -1 };
        if grow {
            wb_i64(f.code, stride); let bytes = cg_save(f, 0x7e); reserved = cg_region_reserve_at(p, m, f, header, bytes, node); destination = reserved.cursor;
        } else {
            cg_get(f, count); cg_owner_read_capacity(p, m, f, header); wa_op(f.code, 0x4b); cg_trap_if(p, m, f, node, "limited array capacity exceeded");
            cg_array_element(p, m, f, id, header, old); destination = cg_save(f, wa());
        }
        if direct { cg_fixed_to(p, m, f, arg, element, destination); if cg_diverges(p, arg) { return; } }
        else if sroa_push_base >= 0 { cg_sroa_store_to_addr(p, f, element, sroa_push_base, destination); }
        else { cg_get(f, value); cg_write_value(p, m, f, element, destination, node); }
        if grow { cg_region_publish_at(f, reserved.limit, reserved.top); }
        cg_owner_set_length(p, m, f, header, count, node);
        if p.nodes[node].type_id != TYPE_VOID {
            cg_get(f, destination); if cg_type_kind(p, element) == TY_REF { cg_load(p, m, f, element, 0); }
            else if cg_type_kind(p, p.nodes[node].type_id) != TY_REF { cg_load(p, m, f, element, 0); cg_convert(p, m, f, element, p.nodes[node].type_id, node); }
        } return;
    }
    if builtin == 26 {
        cg_owner_read_length(p, m, f, header, node); let old = cg_save(f, wa()); cg_get(f, old); wa_op(f.code, 0x45); cg_trap_if(p, m, f, node, "pop from empty array");
        cg_get(f, old); wa_const(f.code, 1); wa_op(f.code, 0x6b); let count = cg_save(f, wa()); var source = -1;
        if grow { wb_i64(f.code, cg_size(p, element)); let bytes = cg_save(f, 0x7e); source = cg_region_rewind(p, m, f, header, bytes, node); }
        else { cg_array_element(p, m, f, id, header, count); source = cg_save(f, wa()); }
        cg_owner_set_length(p, m, f, header, count, node); cg_get(f, source); cg_load(p, m, f, element, 0);
        if cg_aggregate(p, element) { let value = cg_save(f, wa()); let snapshot = cg_temporary(p, f, element); cg_copy(p, m, f, element, snapshot, value, node); cg_get(f, snapshot); }
        cg_convert(p, m, f, element, p.nodes[node].type_id, node); return;
    }
    if builtin == 25 {
        let saved_raw = f.raw_node; if grow { f.raw_node = arg; } cg_expr(p, m, f, arg); f.raw_node = saved_raw;
        cg_pack_view(p, m, f, p.nodes[arg].type_id, node); let view = cg_save(f, ws()); cg_get(f, view); ws_len(f.code); let added = cg_save(f, wa());
        cg_owner_read_length(p, m, f, header, node); let old = cg_save(f, wa()); cg_get(f, old); wa_extend(f.code); cg_get(f, added); wa_extend(f.code); wb_byte(f.code, 0x7c); let wide = cg_save(f, 0x7e);
        cg_get(f, wide); wb_i64(f.code, wn_limit()); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "data region exhausted"); cg_get(f, wide); wa_wrap(f.code); let count = cg_save(f, wa());
        var destination = -1; var reserved = CgReserved { cursor: -1, limit: -1, top: -1 };
        if grow { let bytes = cg_region_array_bytes(p, m, f, id, added, node); reserved = cg_region_reserve_at(p, m, f, header, bytes, node); destination = reserved.cursor; }
        else { cg_get(f, count); cg_owner_read_capacity(p, m, f, header); wa_op(f.code, 0x4b); cg_trap_if(p, m, f, node, "limited array capacity exceeded"); cg_array_element(p, m, f, id, header, old); destination = cg_save(f, wa()); }
        cg_get(f, destination); cg_get(f, view); ws_ptr(f.code); cg_get(f, added); cg_scale_index(f, cg_size(p, element)); wb_copy(f.code);
        if grow { cg_region_publish_at(f, reserved.limit, reserved.top); } cg_owner_set_length(p, m, f, header, count, node); return;
    }
    cg_to(p, m, f, arg, TYPE_U64); let wide = cg_save(f, 0x7e);
    if !cg_unsigned(p, p.nodes[arg].type_id) { cg_get(f, wide); wb_i64(f.code, 0); wb_byte(f.code, 0x53); if builtin == 27 { cg_trap_if(p, m, f, node, "negative pop count"); } else { cg_trap_if(p, m, f, node, "negative array count"); } }
    var fill = -1; let fill_node = p.nodes[arg].next; if fill_node >= 0 { cg_to(p, m, f, fill_node, element); fill = cg_save(f, cg_wasm_type(p, element)); }
    cg_owner_read_length(p, m, f, header, node); let old = cg_save(f, wa());
    if builtin == 27 {
        cg_get(f, wide); cg_get(f, old); wa_extend(f.code); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "pop count out of bounds");
        if grow { cg_get(f, wide); wb_i64(f.code, cg_size(p, element)); wb_byte(f.code, 0x7e); let bytes = cg_save(f, 0x7e); cg_region_rewind(p, m, f, header, bytes, node); }
        cg_get(f, old); cg_get(f, wide); wa_wrap(f.code); wa_op(f.code, 0x6b); let count = cg_save(f, wa()); cg_owner_set_length(p, m, f, header, count, node); return;
    }
    cg_get(f, wide); wb_i64(f.code, wn_limit()); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array length overflow"); cg_get(f, wide); wa_wrap(f.code); let count = cg_save(f, wa());
    cg_get(f, count); cg_get(f, old); wa_op(f.code, 0x4b); cg_begin(f, 0x04, 0x40);
    if fill < 0 { cg_abort(p, m, f, node, "array resize growth requires a fill value"); }
    else {
        cg_get(f, count); cg_get(f, old); wa_op(f.code, 0x6b); let added = cg_save(f, wa()); var destination = -1;
        var reserved = CgReserved { cursor: -1, limit: -1, top: -1 };
        if grow { let bytes = cg_region_array_bytes(p, m, f, id, added, node); reserved = cg_region_reserve_at(p, m, f, header, bytes, node); destination = reserved.cursor; }
        else { cg_get(f, count); cg_owner_read_capacity(p, m, f, header); wa_op(f.code, 0x4b); cg_trap_if(p, m, f, node, "limited array capacity exceeded"); cg_array_element(p, m, f, id, header, old); destination = cg_save(f, wa()); }
        wa_const(f.code, 0); let index = cg_save(f, wa()); let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
        cg_get(f, index); cg_get(f, added); wa_op(f.code, 0x4f); cg_branch(p, f, done, true);
        cg_get(f, destination); cg_get(f, index); cg_scale_index(f, cg_size(p, element)); wa_op(f.code, 0x6a); let location = cg_save(f, wa()); cg_get(f, fill); cg_write_value(p, m, f, element, location, node);
        cg_get(f, index); wa_const(f.code, 1); wa_op(f.code, 0x6a); cg_set(f, index); cg_branch(p, f, again, false); cg_end(f); cg_end(f); if grow { cg_region_publish_at(f, reserved.limit, reserved.top); }
    }
    cg_control(f, 0x05);
    if grow { cg_get(f, old); cg_get(f, count); wa_op(f.code, 0x6b); let removed = cg_save(f, wa()); let bytes = cg_region_array_bytes(p, m, f, id, removed, node); cg_region_rewind(p, m, f, header, bytes, node); }
    cg_end(f); cg_owner_set_length(p, m, f, header, count, node);
}
// The abort of a failed range_index or check_length: the runtime's message,
// or the string literal the call gave in its place.
fn cg_range_fail(p: Program&, m: CgModule&, f: CgBody&, node: i64, reason: i64, message: const u8[:]) {
    if reason >= 0 && p.nodes[reason].kind == N_STRING {
        let token = p.tokens[p.nodes[reason].token]; cg_trap_if(p, m, f, node, p.text[token.text_start..token.text_start + token.text_len]);
    } else { cg_trap_if(p, m, f, node, message); }
}
// range_index, check_length and move_from (upstream §3.3) over fixed-size
// elements. A count is checked against the native data-stack reservation
// (GS_STACK_RESERVE, 2 GiB), so both targets accept the same counts.
recursive fn cg_range_builtin(p: Program&, m: CgModule&, f: CgBody&, node: i64, builtin: i64) {
    let n: const Node& = p.nodes[node]; let receiver = n.first;
    if receiver < 0 || p.nodes[receiver].next < 0 { cg_fail(p, node, "wasm: array builtin has no receiver"); return; }
    let argument = p.nodes[receiver].next; let reason = p.nodes[argument].next;
    var id = p.nodes[receiver].type_id; if cg_type_kind(p, id) == TY_REF { id = p.types[id].element; }
    let width = cg_size(p, p.types[id].element);
    if builtin == 40 {
        // The destination is captured before the source runs; memory.copy
        // copies as though the source values were saved first.
        cg_expr(p, m, f, receiver); cg_pack_view(p, m, f, p.nodes[receiver].type_id, node); let target = cg_save(f, ws());
        cg_expr(p, m, f, argument); cg_pack_view(p, m, f, p.nodes[argument].type_id, node); let source = cg_save(f, ws());
        cg_get(f, target); ws_len(f.code); let count = cg_save(f, wa());
        cg_get(f, count); cg_get(f, source); ws_len(f.code); wa_op(f.code, 0x47);
        cg_trap_if(p, m, f, node, "move_from lengths differ");
        if width > 0 {
            cg_get(f, target); ws_ptr(f.code); cg_get(f, source); ws_ptr(f.code);
            cg_get(f, count); wa_const(f.code, width); wa_op(f.code, 0x6c); wb_copy(f.code);
        }
        return;
    }
    cg_expr(p, m, f, receiver); if cg_type_kind(p, p.nodes[receiver].type_id) == TY_REF { cg_load(p, m, f, id, 0); }
    let base = cg_save(f, wa());
    if builtin == 39 {
        // A negative count, or one whose elements no data stack could hold.
        cg_to(p, m, f, argument, TYPE_I64); let count = cg_save(f, 0x7e);
        cg_get(f, count);
        if width > 0 { wb_i64(f.code, 2147483648 / width); wb_byte(f.code, 0x56); } else { wb_i64(f.code, 0); wb_byte(f.code, 0x53); }
        cg_range_fail(p, m, f, node, reason, "invalid array length");
        cg_get(f, count); cg_convert(p, m, f, TYPE_I64, n.type_id, node); return;
    }
    // An empty slice from anywhere starts at zero; a nonempty one must be
    // element-aligned and wholly inside the receiver's current length.
    cg_expr(p, m, f, argument); cg_pack_view(p, m, f, p.nodes[argument].type_id, node); let view = cg_save(f, ws());
    cg_get(f, view); ws_len(f.code); let count = cg_save(f, wa());
    if p.types[id].array_kind == A_FIXED { wa_const(f.code, p.types[id].count); } else { cg_array_length(p, m, f, id, base); }
    let length = cg_save(f, wa());
    wb_i64(f.code, 0); let result = cg_save(f, 0x7e);
    if width == 0 {
        cg_get(f, count); cg_get(f, length); wa_op(f.code, 0x4b); cg_range_fail(p, m, f, node, reason, "slice not within this array");
    } else {
        cg_get(f, count); wa_truth(f.code); cg_begin(f, 0x04, 0x40);
        cg_get(f, view); ws_ptr(f.code); cg_array_pointer(p, m, f, id, base); wa_op(f.code, 0x6b); let offset = cg_save(f, wa());
        cg_get(f, offset); wa_const(f.code, width); wa_op(f.code, 0x6e); let start = cg_save(f, wa());
        cg_get(f, offset); wa_const(f.code, width); wa_op(f.code, 0x70); wa_truth(f.code);
        cg_get(f, start); cg_get(f, length); wa_op(f.code, 0x4f); wb_byte(f.code, 0x72);
        cg_get(f, count); cg_get(f, length); cg_get(f, start); wa_op(f.code, 0x6b); wa_op(f.code, 0x4b); wb_byte(f.code, 0x72);
        cg_range_fail(p, m, f, node, reason, "slice not within this array");
        cg_get(f, start); wa_extend(f.code); cg_set(f, result); cg_end(f);
    }
    cg_get(f, result); cg_convert(p, m, f, TYPE_I64, n.type_id, node);
}
recursive fn cg_array_builtin(p: Program&, m: CgModule&, f: CgBody&, node: i64, builtin: i64) {
    let n: const Node& = p.nodes[node]; let receiver = n.first;
    if receiver < 0 { cg_fail(p, node, "wasm: array builtin has no receiver"); return; }
    var id = p.nodes[receiver].type_id; cg_expr(p, m, f, receiver);
    if cg_type_kind(p, id) == TY_REF { id = p.types[id].element; cg_load(p, m, f, id, 0); }
    let base = cg_save(f, wa()); let element = p.types[id].element; let arg = p.nodes[receiver].next;
    if builtin == 23 {
        cg_expr(p, m, f, arg); cg_resolve_pointer(m, f); cg_array_pointer(p, m, f, id, base); wa_op(f.code, 0x6b); wa_extend(f.code);
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
        wa_const(f.code, 0); let zero = cg_save(f, wa()); cg_array_set_length(p, m, f, id, base, zero); return;
    }
    if builtin == 24 {
        let direct = cg_fixed_relative(p, element); var value = -1; var sroa_push_base = -1;
        if !direct && p.optimization >= 2 && m.resolver < 0 && m.prefix_helper < 0 && arg >= 0 && p.nodes[arg].type_id == element {
            let sc = cg_sroa_struct(p, element);
            if sc > 0 {
                if p.nodes[arg].kind == N_NAME && p.nodes[arg].symbol >= 0 && p.nodes[arg].symbol < f.slots.len && f.slots[p.nodes[arg].symbol].sroa_count > 0 {
                    sroa_push_base = f.slots[p.nodes[arg].symbol].local;
                } else if p.nodes[arg].kind == N_RECORD && !cg_record_has_self(p, arg) && !cg_record_has_extern(p, arg) || cg_call_sroa_return(p, m, arg) == sc {
                    sroa_push_base = cg_sroa_alloc_locals(p, f, element);
                    cg_emit_into_sroa(p, m, f, arg, element, sroa_push_base, sc, true);
                    if cg_diverges(p, arg) { return; }
                }
            }
        }
        if !direct && sroa_push_base < 0 { cg_to(p, m, f, arg, element); value = cg_save(f, cg_wasm_type(p, element)); }
        cg_array_length(p, m, f, id, base); let old = cg_save(f, wa());
        cg_get(f, old); wa_const(f.code, -1); wa_op(f.code, 0x46); cg_trap_if(p, m, f, node, "array length overflow");
        cg_get(f, old); wa_const(f.code, 1); wa_op(f.code, 0x6a); let count = cg_save(f, wa()); cg_array_reserve(p, m, f, id, base, count, node);
        cg_array_element(p, m, f, id, base, old); let destination = cg_save(f, wa());
        if direct { cg_fixed_to(p, m, f, arg, element, destination); if cg_diverges(p, arg) { return; } }
        else if sroa_push_base >= 0 { cg_sroa_store_to_addr(p, f, element, sroa_push_base, destination); }
        else { cg_get(f, value); cg_write_value(p, m, f, element, destination, node); }
        cg_array_set_length(p, m, f, id, base, count);
        if n.type_id != TYPE_VOID {
            cg_get(f, destination); if cg_type_kind(p, element) == TY_REF { cg_load(p, m, f, element, 0); }
            else if cg_type_kind(p, n.type_id) != TY_REF { cg_load(p, m, f, element, 0); cg_convert(p, m, f, element, n.type_id, node); }
        }
        return;
    }
    if builtin == 26 {
        cg_array_length(p, m, f, id, base); let old = cg_save(f, wa()); cg_get(f, old); wa_op(f.code, 0x45); cg_trap_if(p, m, f, node, "pop from empty array");
        cg_get(f, old); wa_const(f.code, 1); wa_op(f.code, 0x6b); let count = cg_save(f, wa()); cg_array_set_length(p, m, f, id, base, count);
        cg_array_element(p, m, f, id, base, count); cg_load(p, m, f, element, 0);
        if cg_aggregate(p, element) { let source = cg_save(f, wa()); let destination = cg_temporary(p, f, element); cg_copy(p, m, f, element, destination, source, node); cg_get(f, destination); }
        cg_convert(p, m, f, element, n.type_id, node); return;
    }
    if builtin == 25 {
        let saved_raw = f.raw_node; f.raw_node = arg; cg_expr(p, m, f, arg); f.raw_node = saved_raw;
        cg_pack_view(p, m, f, p.nodes[arg].type_id, node); let view = cg_save(f, ws());
        cg_get(f, view); ws_len(f.code); let added = cg_save(f, wa());
        cg_array_length(p, m, f, id, base); let old = cg_save(f, wa());
        cg_get(f, old); cg_get(f, added); wa_op(f.code, 0x6a); let count = cg_save(f, wa());
        cg_get(f, count); cg_get(f, old); wa_op(f.code, 0x49); cg_trap_if(p, m, f, node, "array length overflow"); cg_array_reserve(p, m, f, id, base, count, node);
        cg_array_element(p, m, f, id, base, old); cg_get(f, view); ws_ptr(f.code); cg_get(f, added); wa_const(f.code, cg_size(p, element)); wa_op(f.code, 0x6c); wb_copy(f.code);
        cg_array_set_length(p, m, f, id, base, count); return;
    }
    cg_to(p, m, f, arg, TYPE_U64); let requested = cg_save(f, 0x7e);
    if !cg_unsigned(p, p.nodes[arg].type_id) { cg_get(f, requested); wb_i64(f.code, 0); wb_byte(f.code, 0x53); if builtin == 27 { cg_trap_if(p, m, f, node, "negative pop count"); } else { cg_trap_if(p, m, f, node, "negative array count"); } }
    var fill_value = -1; let fill_node = p.nodes[arg].next;
    if fill_node >= 0 { cg_to(p, m, f, fill_node, element); fill_value = cg_save(f, cg_wasm_type(p, element)); }
    cg_array_length(p, m, f, id, base); let old = cg_save(f, wa());
    if builtin == 27 {
        cg_get(f, requested); cg_get(f, old); wa_extend(f.code); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "pop count out of bounds");
        cg_get(f, old); cg_get(f, requested); wa_wrap(f.code); wa_op(f.code, 0x6b); let count = cg_save(f, wa()); cg_array_set_length(p, m, f, id, base, count); return;
    }
    cg_get(f, requested); wb_i64(f.code, wn_limit()); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array length overflow");
    cg_get(f, requested); wa_wrap(f.code); let count = cg_save(f, wa());
    cg_get(f, count); cg_get(f, old); wa_op(f.code, 0x4b); cg_begin(f, 0x04, 0x40);
    if fill_value < 0 { cg_abort(p, m, f, node, "array resize growth requires a fill value"); }
    else {
        cg_array_reserve(p, m, f, id, base, count, node); cg_get(f, old); let index = cg_save(f, wa());
        let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
        cg_get(f, index); cg_get(f, count); wa_op(f.code, 0x4f); cg_branch(p, f, done, true);
        cg_array_element(p, m, f, id, base, index); let destination = cg_save(f, wa()); cg_get(f, fill_value); cg_write_value(p, m, f, element, destination, node);
        cg_get(f, index); wa_const(f.code, 1); wa_op(f.code, 0x6a); cg_set(f, index); cg_branch(p, f, again, false); cg_end(f); cg_end(f);
    }
    cg_end(f); cg_array_set_length(p, m, f, id, base, count);
}
fn cg_raw_append_type(p: Program&, id: i64) -> bool {
    return cg_type_kind(p, id) == TY_ARRAY && p.types[id].array_kind == A_GROW &&
           p.types[id].element == TYPE_U8 && p.types[id].length_storage < 0 && p.types[id].size == wc_bytes();
}
fn cg_format_bytes(p: Program&, m: CgModule&, f: CgBody&, id: i64, output: i64, data: i64, length: i64, node: i64) {
    if m.raw_append >= 0 && !f.scratch && cg_raw_append_type(p, id) {
        cg_get(f, output); cg_get(f, data); cg_get(f, length);
        cg_line(p, f, node); wb_op(f.code, 0x10, m.raw_append); return;
    }
    cg_format_bytes_inline(p, m, f, id, output, data, length, node);
}
fn cg_format_bytes_inline(p: Program&, m: CgModule&, f: CgBody&, id: i64, output: i64, data: i64, length: i64, node: i64) {
    cg_array_length(p, m, f, id, output); let old = cg_save(f, wa());
    cg_get(f, old); wa_extend(f.code); cg_get(f, length); wa_extend(f.code); wb_byte(f.code, 0x7c); let wide = cg_save(f, 0x7e);
    cg_get(f, wide); wb_i64(f.code, wn_limit()); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "formatted output length overflow"); cg_get(f, wide); wa_wrap(f.code); let count = cg_save(f, wa());
    if p.types[id].array_kind == A_LIMITED {
        cg_get(f, count); if cg_owner(p, id) { cg_owner_read_capacity(p, m, f, output); } else { wa_const(f.code, p.types[id].count); }
        wa_op(f.code, 0x4b); cg_trap_if(p, m, f, node, "limited array capacity exceeded");
    }
    let region = m.regions_enabled && cg_region_value(p, id); let grow = p.types[id].array_kind == A_GROW || p.types[id].array_kind == A_GROWSHRINK;
    var destination = -1; var reserved = CgReserved { cursor: -1, limit: -1, top: -1 };
    if region && grow {
        cg_get(f, length); wa_extend(f.code); let bytes = cg_save(f, 0x7e); reserved = cg_region_reserve_at(p, m, f, output, bytes, node); destination = reserved.cursor;
    } else {
        if !region { cg_array_reserve(p, m, f, id, output, count, node); }
        cg_array_element(p, m, f, id, output, old); destination = cg_save(f, wa());
    }
    cg_get(f, destination); cg_get(f, data); cg_resolve_pointer(m, f); cg_get(f, length); wb_copy(f.code);
    if region && grow { cg_region_publish_at(f, reserved.limit, reserved.top); } cg_array_set_length(p, m, f, id, output, count);
}
fn cg_format_text(p: Program&, m: CgModule&, f: CgBody&, id: i64, output: i64, text: u8[:], node: i64) {
    wa_const(f.code, cg_data(m, text)); let data = cg_save(f, wa()); wa_const(f.code, text.len); let length = cg_save(f, wa());
    cg_format_bytes(p, m, f, id, output, data, length, node);
}
fn cg_format_scalar(p: Program&, m: CgModule&, f: CgBody&, output_type: i64, output: i64, id: i64, value: i64, node: i64) {
    let kind = cg_type_kind(p, id);
    if kind == TY_FLOAT {
        let offset = cg_frame(f, 32, 1); cg_frame_address(f, offset); let buffer = cg_save(f, wa());
        var host = m.format_f64; if p.types[id].count == 32 { host = m.format_f32; }
        if host < 0 { cg_fail(p, node, "wasm: floating-point formatter demand was not planned"); return; }
        cg_get(f, buffer); cg_get(f, value); wb_op(f.code, 0x10, host); wa_from_i32(f.code); let length = cg_save(f, wa());
        cg_format_bytes(p, m, f, output_type, output, buffer, length, node); return;
    }
    if kind == TY_BOOL {
        cg_get(f, value); cg_begin(f, 0x04, 0x40); cg_format_text(p, m, f, output_type, output, "true", node);
        cg_control(f, 0x05); cg_format_text(p, m, f, output_type, output, "false", node); cg_end(f); return;
    }
    if kind == TY_ARRAY || kind == TY_SLICE {
        if p.types[id].element != TYPE_U8 { cg_fail(p, node, "wasm: compound formatting requires the semantic rendering helper"); return; }
        cg_get(f, value); cg_pack_view(p, m, f, id, node); let view = cg_save(f, ws());
        cg_get(f, view); ws_ptr(f.code); let data = cg_save(f, wa()); cg_get(f, view); ws_len(f.code); let length = cg_save(f, wa());
        cg_format_bytes(p, m, f, output_type, output, data, length, node); return;
    }
    if kind != TY_INT { cg_fail(p, node, "wasm: this raw formatting scalar is unsupported"); return; }
    let text = cg_integer_text(p, f, id, value); cg_format_bytes(p, m, f, output_type, output, text.data, text.length, node);
}
fn cg_integer_text(p: Program&, f: CgBody&, id: i64, value: i64) -> CgText {
    let frame = cg_frame(f, 32, 1); cg_frame_address(f, frame); let buffer = cg_save(f, wa());
    cg_get(f, value); if cg_wasm_type(p, id) == 0x7f { if cg_unsigned(p, id) { wb_byte(f.code, 0xad); } else { wb_byte(f.code, 0xac); } }
    let magnitude = cg_save(f, 0x7e); wb_i32(f.code, 0); let negative = cg_save(f, 0x7f);
    if !cg_unsigned(p, id) {
        cg_get(f, magnitude); wb_i64(f.code, 0); wb_byte(f.code, 0x53); cg_set(f, negative);
        cg_get(f, negative); cg_begin(f, 0x04, 0x40); wb_i64(f.code, 0); cg_get(f, magnitude); wb_byte(f.code, 0x7d); cg_set(f, magnitude); cg_end(f);
    }
    cg_get(f, buffer); wa_const(f.code, 32); wa_op(f.code, 0x6a); let end = cg_save(f, wa()); cg_get(f, end); let cursor = cg_save(f, wa());
    let again = cg_begin(f, 0x03, 0x40);
    cg_get(f, cursor); wa_const(f.code, 1); wa_op(f.code, 0x6b); cg_set(f, cursor);
    cg_get(f, cursor); cg_get(f, magnitude); wb_i64(f.code, 10); wb_byte(f.code, 0x82); wb_byte(f.code, 0xa7); wb_i32(f.code, 48); wb_byte(f.code, 0x6a); wb_mem(f.code, 0x3a, 0, 0);
    cg_get(f, magnitude); wb_i64(f.code, 10); wb_byte(f.code, 0x80); cg_set(f, magnitude); cg_get(f, magnitude); wb_byte(f.code, 0x50); wb_byte(f.code, 0x45); cg_branch(p, f, again, true); cg_end(f);
    cg_get(f, negative); cg_begin(f, 0x04, 0x40); cg_get(f, cursor); wa_const(f.code, 1); wa_op(f.code, 0x6b); cg_set(f, cursor); cg_get(f, cursor); wb_i32(f.code, 45); wb_mem(f.code, 0x3a, 0, 0); cg_end(f);
    cg_get(f, end); cg_get(f, cursor); wa_op(f.code, 0x6b); let length = cg_save(f, wa()); return CgText { data: cursor, length: length };
}
recursive fn cg_format_builtin(p: Program&, m: CgModule&, f: CgBody&, node: i64, builtin: i64) {
    let n: const Node& = p.nodes[node]; var child = n.first; var output = -1; var output_type = n.type_id;
    if builtin == 2 {
        output_type = p.nodes[child].type_id; cg_expr(p, m, f, child);
        if cg_type_kind(p, output_type) == TY_REF { output_type = p.types[output_type].element; cg_load(p, m, f, output_type, 0); }
        output = cg_save(f, wa()); child = p.nodes[child].next;
    }
    if builtin == 1 {
        wa_const(f.code, 0); let zero = cg_save(f, wa());
        if m.regions_enabled {
            let receiving = cg_temporary_destination(p, m, f, output_type, node); output = f.construction_destinations[receiving].header;
            cg_region_array_prefix(p, m, f, output_type, output, zero, zero, node);
        } else {
            output = cg_temporary(p, f, output_type); cg_get(f, output); cg_clear_bytes(p, f, wc_bytes());
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
    let n: const Node& = p.nodes[node]; let argument = n.first; var id = p.nodes[argument].type_id;
    while cg_type_kind(p, id) == TY_REF { id = p.types[id].element; }
    if cg_type_kind(p, id) != TY_ARRAY && cg_type_kind(p, id) != TY_SLICE { cg_fail(p, node, "wasm: byte images require an array or slice"); return; }
    let element = p.types[id].element;
    if cg_has_owner(p, element) { cg_fail(p, node, "wasm: byte images of variable aggregate elements require physical image packing"); return; }
    cg_expr(p, m, f, argument); if cg_diverges(p, argument) { return; } cg_pack_view(p, m, f, p.nodes[argument].type_id, node);
    let view = cg_save(f, ws()); cg_get(f, view); ws_ptr(f.code); let data = cg_save(f, wa());
    cg_get(f, view); ws_count(f.code); let count = cg_save(f, 0x7e); var length = -1;
    if cg_encoded_scalar(p, element) {
        let end = cg_walk_elements(p, m, f, data, count, node); cg_get(f, end); cg_get(f, data); wa_op(f.code, 0x6b); length = cg_save(f, wa());
    } else {
        cg_get(f, count); wb_i64(f.code, cg_size(p, element)); wb_byte(f.code, 0x7e); let bytes = cg_save(f, 0x7e);
        cg_get(f, bytes); wb_i64(f.code, wn_limit()); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "byte image exceeds wasm32 range"); cg_get(f, bytes); wa_wrap(f.code); length = cg_save(f, wa());
    }
    if builtin == 17 {
        cg_get(f, data); wa_extend(f.code); cg_get(f, length); wa_extend(f.code); ws_pack(f); return;
    }
    var output = -1; var output_type = n.type_id; let receiver = p.nodes[argument].next;
    if receiver >= 0 {
        output_type = p.nodes[receiver].type_id; cg_expr(p, m, f, receiver); if cg_diverges(p, receiver) { return; }
        if cg_type_kind(p, output_type) == TY_REF { output_type = p.types[output_type].element; cg_load(p, m, f, output_type, 0); }
        output = cg_save(f, wa());
    } else {
        wa_const(f.code, 0); let zero = cg_save(f, wa());
        if m.regions_enabled {
            let receiving = cg_temporary_destination(p, m, f, output_type, node); output = f.construction_destinations[receiving].header;
            cg_region_array_prefix(p, m, f, output_type, output, zero, zero, node);
        } else {
            output = cg_temporary(p, f, output_type); cg_get(f, output); cg_clear_bytes(p, f, wc_bytes());
            cg_owner_image(p, m, f, output_type, output, zero, zero, node);
        }
    }
    let frame = cg_frame(f, 10, 1); cg_frame_address(f, frame); let prefix = cg_save(f, wa());
    cg_get(f, length); wa_extend(f.code); let wide = cg_save(f, 0x7e); let end = cg_write_uleb(p, f, prefix, wide);
    cg_get(f, end); cg_get(f, prefix); wa_op(f.code, 0x6b); let prefix_length = cg_save(f, wa());
    cg_format_bytes(p, m, f, output_type, output, prefix, prefix_length, node); cg_format_bytes(p, m, f, output_type, output, data, length, node);
    if receiver < 0 { cg_get(f, output); }
}
recursive fn cg_from_bytes_flat(p: Program&, id: i64) -> bool {
    if id < 0 || id >= p.types.len { return false; }
    let t: const Type& = p.types[id];
    if t.storage != 0 || cg_has_owner(p, id) || cg_has_relative(p, id) { return false; }
    if t.kind == TY_VOID || t.kind == TY_BOOL || t.kind == TY_FLOAT { return true; }
    if t.kind == TY_INT { return t.index_type < 0; }
    if t.kind == TY_ARRAY { return t.array_kind == A_FIXED && cg_from_bytes_flat(p, t.element); }
    if t.kind == TY_STRUCT || t.kind == TY_TUPLE {
        var field = t.first; if t.kind == TY_STRUCT && t.declaration >= 0 { field = p.nodes[t.declaration].first; }
        while field >= 0 {
            let fn_node: const Node& = p.nodes[field];
            if (fn_node.flags & F_PAD) == 0 && !cg_from_bytes_flat(p, fn_node.type_id) { return false; }
            field = fn_node.next;
        }
        return true;
    }
    if t.kind == TY_ENUM && (t.flags & F_VARIABLE_MODE) == 0 && (t.length_storage == 1 || t.length_storage == 2 || t.length_storage == 4) {
        var variant = t.first; if variant < 0 && t.declaration >= 0 { variant = p.nodes[t.declaration].first; }
        if variant < 0 { return false; }
        while variant >= 0 {
            if p.nodes[variant].first >= 0 && !cg_from_bytes_flat(p, p.nodes[variant].type_id) { return false; }
            variant = p.nodes[variant].next;
        }
        return true;
    }
    return false;
}
recursive fn cg_from_bytes_needs_check(p: Program&, id: i64) -> bool {
    if id < 0 || id >= p.types.len { return false; }
    let t: const Type& = p.types[id];
    if t.kind == TY_BOOL || t.kind == TY_ENUM { return true; }
    if t.kind == TY_ARRAY { return cg_from_bytes_needs_check(p, t.element); }
    if t.kind == TY_STRUCT || t.kind == TY_TUPLE {
        var field = t.first; if t.kind == TY_STRUCT && t.declaration >= 0 { field = p.nodes[t.declaration].first; }
        while field >= 0 {
            let fn_node: const Node& = p.nodes[field];
            if (fn_node.flags & F_PAD) == 0 && cg_from_bytes_needs_check(p, fn_node.type_id) { return true; }
            field = fn_node.next;
        }
    }
    return false;
}
recursive fn cg_from_bytes_check_val(p: Program&, f: CgBody&, id: i64, ptr: i64, offset: i64, ok: i64, fail_label: i64) {
    if !cg_from_bytes_needs_check(p, id) { return; }
    let t: const Type& = p.types[id];
    if t.kind == TY_BOOL {
        cg_get(f, ptr); wa_add(f.code, offset); wb_mem(f.code, 0x2d, 0, 0); wb_i32(f.code, 1); wb_byte(f.code, 0x4b);
        cg_begin(f, 0x04, 0x40); wb_i32(f.code, 0); cg_set(f, ok); cg_branch(p, f, fail_label, false); cg_end(f);
        return;
    }
    if t.kind == TY_ARRAY {
        let esz = cg_size(p, t.element);
        cg_get(f, ptr); wa_add(f.code, offset); let cur = cg_save(f, wa());
        wa_const(f.code, 0); let ai = cg_save(f, wa());
        let adone = cg_begin(f, 0x02, 0x40); let aagain = cg_begin(f, 0x03, 0x40);
        cg_get(f, ai); wa_const(f.code, t.count); wa_op(f.code, 0x4f); cg_branch(p, f, adone, true);
        cg_from_bytes_check_val(p, f, t.element, cur, 0, ok, fail_label);
        cg_get(f, cur); wa_add(f.code, esz); cg_set(f, cur);
        cg_get(f, ai); wa_const(f.code, 1); wa_op(f.code, 0x6a); cg_set(f, ai);
        cg_branch(p, f, aagain, false); cg_end(f); cg_end(f);
        return;
    }
    if t.kind == TY_STRUCT || t.kind == TY_TUPLE {
        var field = t.first; if t.kind == TY_STRUCT && t.declaration >= 0 { field = p.nodes[t.declaration].first; }
        var off = 0;
        while field >= 0 {
            let fn_node: const Node& = p.nodes[field];
            if (fn_node.flags & F_PAD) != 0 { off += fn_node.aux; }
            else {
                var foff = off; if t.kind == TY_STRUCT { foff = fn_node.integer; }
                if cg_from_bytes_needs_check(p, fn_node.type_id) {
                    cg_from_bytes_check_val(p, f, fn_node.type_id, ptr, offset + foff, ok, fail_label);
                }
                off += cg_size(p, fn_node.type_id);
            }
            field = fn_node.next;
        }
        return;
    }
    if t.kind == TY_ENUM {
        cg_get(f, ptr); wa_add(f.code, offset);
        if t.length_storage == 1 { wb_mem(f.code, 0x2d, 0, 0); }
        else if t.length_storage == 2 { wb_mem(f.code, 0x2f, 0, 0); }
        else { wb_mem(f.code, 0x28, 0, 0); }
        let tag = cg_save(f, 0x7f);
        var variant = t.first; if variant < 0 && t.declaration >= 0 { variant = p.nodes[t.declaration].first; }
        let min_tag = p.nodes[variant].integer; var expected = min_tag; var vcount = 0; var contig = true;
        var scan = variant;
        while scan >= 0 {
            if p.nodes[scan].integer != expected { contig = false; }
            if p.nodes[scan].first >= 0 && cg_from_bytes_needs_check(p, p.nodes[scan].type_id) { contig = false; }
            expected++; vcount++; scan = p.nodes[scan].next;
        }
        if contig {
            cg_get(f, tag); if min_tag != 0 { wb_i32(f.code, min_tag); wb_byte(f.code, 0x6b); }
            wb_i32(f.code, vcount); wb_byte(f.code, 0x4f);
            cg_begin(f, 0x04, 0x40); wb_i32(f.code, 0); cg_set(f, ok); cg_branch(p, f, fail_label, false); cg_end(f);
            return;
        }
        let matched = cg_begin(f, 0x02, 0x40);
        while variant >= 0 {
            cg_get(f, tag); wb_i32(f.code, p.nodes[variant].integer); wb_byte(f.code, 0x46);
            cg_begin(f, 0x04, 0x40);
            if p.nodes[variant].first >= 0 && cg_from_bytes_needs_check(p, p.nodes[variant].type_id) {
                cg_from_bytes_check_val(p, f, p.nodes[variant].type_id, ptr, offset + t.length_storage, ok, fail_label);
            }
            cg_branch(p, f, matched, false); cg_end(f);
            variant = p.nodes[variant].next;
        }
        wb_i32(f.code, 0); cg_set(f, ok); cg_branch(p, f, fail_label, false);
        cg_end(f);
    }
}
recursive fn cg_from_bytes(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n: const Node& = p.nodes[node]; let argument = n.first;
    let array_type = p.nodes[p.types[n.type_id].first].type_id;
    let element = p.types[array_type].element;
    if !cg_owner(p, array_type) || !cg_from_bytes_flat(p, element) {
        cg_fail(p, node, "wasm: from_bytes image verification is unsupported by the direct Wasm backend"); return;
    }
    cg_expr(p, m, f, argument); if cg_diverges(p, argument) { return; }
    cg_pack_view(p, m, f, p.nodes[argument].type_id, node);
    let view = cg_save(f, ws());
    cg_get(f, view); ws_ptr(f.code); let in_ptr = cg_save(f, wa());
    cg_get(f, view); ws_len(f.code); let in_len = cg_save(f, wa());
    cg_get(f, in_ptr); cg_get(f, in_len); wa_op(f.code, 0x6a); let in_end = cg_save(f, wa());
    wb_i32(f.code, 1); let ok = cg_save(f, 0x7f);
    cg_get(f, in_ptr); let cursor = cg_save(f, wa());
    wb_i64(f.code, 0); let payload_bytes = cg_save(f, 0x7e);
    wb_i32(f.code, 0); let shift = cg_save(f, 0x7f);
    wb_i64(f.code, 0); let count64 = cg_save(f, 0x7e);
    let check_done = cg_begin(f, 0x02, 0x40);
    let udone = cg_begin(f, 0x02, 0x40); let uagain = cg_begin(f, 0x03, 0x40);
    cg_get(f, cursor); cg_get(f, in_end); wa_op(f.code, 0x4f); cg_begin(f, 0x04, 0x40);
    wb_i32(f.code, 0); cg_set(f, ok); cg_branch(p, f, check_done, false); cg_end(f);
    cg_get(f, cursor); wb_mem(f.code, 0x2d, 0, 0); let byte = cg_save(f, 0x7f);
    cg_get(f, cursor); wa_const(f.code, 1); wa_op(f.code, 0x6a); cg_set(f, cursor);
    cg_get(f, shift); wb_i32(f.code, 63); wb_byte(f.code, 0x4a);
    cg_get(f, shift); wb_i32(f.code, 63); wb_byte(f.code, 0x46);
    cg_get(f, byte); wb_i32(f.code, 254); wb_byte(f.code, 0x71); wb_byte(f.code, 0x45); wb_byte(f.code, 0x45);
    wb_byte(f.code, 0x71); wb_byte(f.code, 0x72); cg_begin(f, 0x04, 0x40);
    wb_i32(f.code, 0); cg_set(f, ok); cg_branch(p, f, check_done, false); cg_end(f);
    cg_get(f, payload_bytes); cg_get(f, byte); wb_i32(f.code, 127); wb_byte(f.code, 0x71); wb_byte(f.code, 0xad);
    cg_get(f, shift); wb_byte(f.code, 0xad); wb_byte(f.code, 0x86); wb_byte(f.code, 0x84); cg_set(f, payload_bytes);
    cg_get(f, byte); wb_i32(f.code, 128); wb_byte(f.code, 0x71); wb_byte(f.code, 0x45); cg_begin(f, 0x04, 0x40);
    cg_get(f, shift); wb_i32(f.code, 0); wb_byte(f.code, 0x47); cg_get(f, byte); wb_byte(f.code, 0x45); wb_byte(f.code, 0x71);
    cg_begin(f, 0x04, 0x40); wb_i32(f.code, 0); cg_set(f, ok); cg_branch(p, f, check_done, false); cg_end(f);
    cg_branch(p, f, udone, false); cg_end(f);
    cg_get(f, shift); wb_i32(f.code, 7); wb_byte(f.code, 0x6a); cg_set(f, shift);
    cg_branch(p, f, uagain, false); cg_end(f); cg_end(f);
    cg_get(f, payload_bytes); wb_i64(f.code, 0); wb_byte(f.code, 0x53);
    cg_get(f, payload_bytes); cg_get(f, in_end); cg_get(f, cursor); wa_op(f.code, 0x6b); wa_extend(f.code); wb_byte(f.code, 0x52);
    wb_byte(f.code, 0x72); cg_begin(f, 0x04, 0x40);
    wb_i32(f.code, 0); cg_set(f, ok); cg_branch(p, f, check_done, false); cg_end(f);
    let width = cg_size(p, element);
    if width <= 0 {
        cg_get(f, payload_bytes); wb_i64(f.code, 0); wb_byte(f.code, 0x52); cg_begin(f, 0x04, 0x40);
        wb_i32(f.code, 0); cg_set(f, ok); cg_branch(p, f, check_done, false); cg_end(f);
    } else {
        if width > 1 {
            cg_get(f, payload_bytes); wb_i64(f.code, width); wb_byte(f.code, 0x82); wb_i64(f.code, 0); wb_byte(f.code, 0x52);
            cg_begin(f, 0x04, 0x40); wb_i32(f.code, 0); cg_set(f, ok); cg_branch(p, f, check_done, false); cg_end(f);
            cg_get(f, payload_bytes); wb_i64(f.code, width); wb_byte(f.code, 0x80); cg_set(f, count64);
        } else { cg_get(f, payload_bytes); cg_set(f, count64); }
        cg_get(f, count64); wb_i64(f.code, wn_limit()); wb_byte(f.code, 0x56); cg_begin(f, 0x04, 0x40);
        wb_i32(f.code, 0); cg_set(f, ok); cg_branch(p, f, check_done, false); cg_end(f);
        if p.types[array_type].array_kind == A_VAR && p.types[array_type].length_storage > 0 && p.types[array_type].length_storage < 8 {
            let max_count = (1 << (p.types[array_type].length_storage * 8)) - 1;
            cg_get(f, count64); wb_i64(f.code, max_count); wb_byte(f.code, 0x56); cg_begin(f, 0x04, 0x40);
            wb_i32(f.code, 0); cg_set(f, ok); cg_branch(p, f, check_done, false); cg_end(f);
        }
        if cg_from_bytes_needs_check(p, element) {
            cg_get(f, cursor); let scan_ptr = cg_save(f, wa());
            let sdone = cg_begin(f, 0x02, 0x40); let sagain = cg_begin(f, 0x03, 0x40);
            cg_get(f, scan_ptr); cg_get(f, in_end); wa_op(f.code, 0x4f); cg_branch(p, f, sdone, true);
            cg_from_bytes_check_val(p, f, element, scan_ptr, 0, ok, check_done);
            cg_get(f, scan_ptr); wa_add(f.code, width); cg_set(f, scan_ptr);
            cg_branch(p, f, sagain, false); cg_end(f); cg_end(f);
        }
    }
    cg_end(f);
    cg_get(f, ok); wb_byte(f.code, 0x45); cg_begin(f, 0x04, 0x40);
    wb_i64(f.code, 0); cg_set(f, count64); wb_i64(f.code, 0); cg_set(f, payload_bytes); cg_end(f);
    cg_get(f, count64); wa_wrap(f.code); let count = cg_save(f, wa());
    cg_get(f, payload_bytes); wa_wrap(f.code); let copy_len = cg_save(f, wa());
    var output = -1; var dst = -1;
    if m.regions_enabled {
        let receiving = cg_temporary_destination(p, m, f, array_type, node);
        output = f.construction_destinations[receiving].header;
        dst = cg_region_owner_image(p, m, f, array_type, output, count, count, node);
        cg_get(f, copy_len); wa_truth(f.code); cg_begin(f, 0x04, 0x40);
        cg_get(f, dst); cg_get(f, cursor); cg_resolve_pointer(m, f); cg_get(f, copy_len); wb_copy(f.code);
        cg_end(f);
        cg_get(f, dst); cg_get(f, copy_len); wa_op(f.code, 0x6a); let top = cg_save(f, wa());
        cg_region_publish(f, output, top);
    } else {
        output = cg_temporary(p, f, array_type); cg_get(f, output); cg_clear_bytes(p, f, wc_bytes());
        dst = cg_owner_image(p, m, f, array_type, output, count, count, node);
        cg_get(f, copy_len); wa_truth(f.code); cg_begin(f, 0x04, 0x40);
        cg_get(f, dst); cg_get(f, cursor); cg_resolve_pointer(m, f); cg_get(f, copy_len); wb_copy(f.code);
        cg_end(f);
    }
    cg_get(f, output); cg_get(f, ok);
}
recursive fn cg_builtin(p: Program&, m: CgModule&, f: CgBody&, node: i64, builtin: i64) {
    let n: const Node& = p.nodes[node]; let arg = n.first;
    if builtin == 1 || builtin == 2 { cg_format_builtin(p, m, f, node, builtin); return; }
    if builtin == 0 {
        f.frame_used = true;
        let mark = f.work.len; wb_op(f.code, 0x23, 0); let scratch_mark = cg_save(f, wa());
        var child = arg;
        while child >= 0 {
            var id = p.nodes[child].type_id; cg_expr(p, m, f, child); if cg_diverges(p, child) { f.work.resize(mark); return; }
            if cg_type_kind(p, id) == TY_SLICE { cg_pack_view(p, m, f, id, child); }
            if cg_type_kind(p, id) == TY_REF { id = p.types[id].element; cg_load(p, m, f, id, 0); }
            var value = cg_save(f, cg_wasm_type(p, id));
            if cg_aggregate(p, id) {
                let snapshot = cg_temporary(p, f, id); f.scratch = true; cg_copy(p, m, f, id, snapshot, value, child); f.scratch = false; value = snapshot;
            } else if cg_type_kind(p, id) == TY_SLICE {
                cg_get(f, value); ws_len(f.code); let length = cg_save(f, wa());
                var bytes = -1;
                if p.types[p.types[id].element].storage == 1 {
                    cg_get(f, value); ws_ptr(f.code); let base = cg_save(f, wa()); cg_get(f, length); wa_extend(f.code); let count = cg_save(f, 0x7e); let end = cg_walk_elements(p, m, f, base, count, node);
                    cg_get(f, end); cg_get(f, base); wa_op(f.code, 0x6b); bytes = cg_save(f, wa());
                } else { cg_get(f, length); wa_const(f.code, cg_size(p, p.types[id].element)); wa_op(f.code, 0x6c); bytes = cg_save(f, wa()); }
                cg_get(f, bytes); f.scratch = true; cg_allocate(p, m, f, node); f.scratch = false; let copy = cg_save(f, wa());
                cg_get(f, copy); cg_get(f, value); ws_ptr(f.code); cg_get(f, bytes); wb_copy(f.code);
                cg_get(f, copy); wa_extend(f.code); cg_get(f, length); wa_extend(f.code); ws_pack(f); value = cg_save(f, ws());
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
        cg_expr(p, m, f, arg); cg_pack_view(p, m, f, p.nodes[arg].type_id, node); let view = cg_save(f, ws());
        cg_get(f, view); ws_ptr(f.code); cg_get(f, view); ws_len(f.code); wa_to_i32(f.code);
        cg_line(p, f, node); wb_op(f.code, 0x10, CG_ABORT); wb_byte(f.code, 0); return;
    }
    if builtin == 5 { cg_to(p, m, f, arg, TYPE_I32); wb_op(f.code, 0x10, CG_EXIT); wb_byte(f.code, 0); return; }
    // hardware_threads: the direct host ABI runs one thread of Goose code.
    if builtin == 6 { wb_i64(f.code, 1); cg_convert(p, m, f, TYPE_I64, n.type_id, node); return; }
    if builtin == 14 {
        if cg_aggregate(p, n.type_id) {
            let destination = cg_temporary(p, f, n.type_id);
            if cg_byte_record(p, n.type_id) { cg_construct_byte_record(p, m, f, n.type_id, destination, -1); }
            else { cg_get(f, destination); cg_clear_bytes(p, f, cg_size(p, n.type_id)); }
            cg_get(f, destination);
        } else { cg_zero(f.code, cg_wasm_type(p, n.type_id)); } return;
    }
    if builtin == 15 {
        cg_to(p, m, f, arg, n.type_id);
        if cg_aggregate(p, n.type_id) { let source = cg_save(f, wa()); let destination = cg_temporary(p, f, n.type_id); cg_copy(p, m, f, n.type_id, destination, source, node); cg_get(f, destination); }
        return;
    }
    if builtin == 21 {
        if f.hoists.len > 0 && m.resolver < 0 {
            let hi = cg_hoist_find(p, f, arg);
            if hi >= 0 && f.hoists[hi].len_local >= 0 {
                cg_get(f, f.hoists[hi].len_local);
                cg_convert(p, m, f, TYPE_U64, n.type_id, node); return;
            }
        }
        var id = p.nodes[arg].type_id;
        let is_ref = cg_type_kind(p, id) == TY_REF;
        if is_ref { id = p.types[id].element; }
        if m.ordinary_owners && m.resolver < 0 && cg_owner(p, id) {
            cg_expr(p, m, f, arg);
            if is_ref { cg_load(p, m, f, id, 0); }
            wc_load(f.code, 1); wa_extend(f.code);
            cg_convert(p, m, f, TYPE_U64, n.type_id, node); return;
        }
        cg_expr(p, m, f, arg); cg_pack_view(p, m, f, p.nodes[arg].type_id, node); ws_count(f.code); cg_convert(p, m, f, TYPE_U64, n.type_id, node); return;
    }
    if builtin == 22 {
        var id = p.nodes[arg].type_id; cg_expr(p, m, f, arg);
        if cg_type_kind(p, id) == TY_REF { id = p.types[id].element; cg_load(p, m, f, id, 0); }
        if cg_owner(p, id) { let header = cg_save(f, wa()); cg_owner_read_capacity(p, m, f, header); wa_extend(f.code); }
        else { wb_byte(f.code, 0x1a); wb_i64(f.code, p.types[id].count); }
        cg_convert(p, m, f, TYPE_U64, n.type_id, node); return;
    }
    if builtin >= 23 && builtin <= 29 { cg_array_builtin(p, m, f, node, builtin); return; }
    if builtin >= 30 && builtin <= 35 { cg_pool_builtin(p, m, f, node, builtin); return; }
    if builtin >= 38 && builtin <= 40 { cg_range_builtin(p, m, f, node, builtin); return; }
    if builtin == 16 || builtin == 17 { cg_bytes_builtin(p, m, f, node, builtin); return; }
    if builtin == 18 { cg_from_bytes(p, m, f, node); return; }
    cg_fail(p, node, "wasm: builtin is unsupported by the direct Wasm execution environment");
}
recursive fn cg_slice(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n: const Node& = p.nodes[node]; var id = p.nodes[n.left].type_id;
    if cg_type_kind(p, id) == TY_REF { id = p.types[id].element; }
    cg_expr(p, m, f, n.left); cg_pack_view(p, m, f, p.nodes[n.left].type_id, node); let view = cg_save(f, ws());
    if n.right >= 0 {
        if (n.flags & F_FROM_END) != 0 { cg_get(f, view); ws_count(f.code); }
        cg_to(p, m, f, n.right, TYPE_U64); if cg_diverges(p, n.right) { return; } if (n.flags & F_FROM_END) != 0 { wb_byte(f.code, 0x7d); }
    } else { wb_i64(f.code, 0); }
    let start = cg_save(f, 0x7e);
    if n.third >= 0 {
        if (n.flags & F_TO_END) != 0 { cg_get(f, view); ws_count(f.code); }
        cg_to(p, m, f, n.third, TYPE_U64); if cg_diverges(p, n.third) { return; } if (n.flags & F_TO_END) != 0 { wb_byte(f.code, 0x7d); }
    }
    else { cg_get(f, view); ws_count(f.code); }
    let end = cg_save(f, 0x7e);
    if (n.flags & F_BOUNDS_PROVEN) == 0 {
        cg_get(f, start); cg_get(f, end); wb_byte(f.code, 0x56);
        cg_get(f, end); cg_get(f, view); ws_count(f.code); wb_byte(f.code, 0x56); wb_byte(f.code, 0x72); cg_trap_if(p, m, f, node, "slice bounds out of range");
    }
    if p.types[p.types[id].element].storage == 1 {
        cg_get(f, view); ws_ptr(f.code); let base = cg_save(f, wa()); let pointer = cg_walk_elements(p, m, f, base, start, node); cg_get(f, pointer); wa_extend(f.code);
    } else {
        cg_get(f, view); ws_ptr(f.code); cg_get(f, start); wa_wrap(f.code); cg_scale_index(f, cg_size(p, p.types[id].element)); wa_op(f.code, 0x6a); wa_extend(f.code);
    }
    cg_get(f, end); cg_get(f, start); wb_byte(f.code, 0x7d); ws_pack(f);
}
recursive fn cg_cast(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let result = p.nodes[node].type_id; var requested = result; let right = p.nodes[node].right;
    if right >= 0 && p.nodes[right].type_id >= 0 { requested = p.nodes[right].type_id; }
    p.nodes[node].type_id = requested; cg_cast_body(p, m, f, node); p.nodes[node].type_id = result;
    if requested != result && !cg_diverges(p, p.nodes[node].left) { cg_convert(p, m, f, requested, result, node); }
}
recursive fn cg_cast_body(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n: const Node& = p.nodes[node]; var from = p.nodes[n.left].type_id; let to = n.type_id;
    cg_expr(p, m, f, n.left);
    if cg_type_kind(p, from) == TY_REF && (p.types[from].flags & TF_OPTIONAL) != 0 && cg_type_kind(p, to) == TY_BOOL { cg_convert(p, m, f, from, to, node); return; }
    if cg_type_kind(p, from) == TY_REF && cg_type_kind(p, to) != TY_REF { from = p.types[from].element; cg_load(p, m, f, from, 0); }
    if cg_type_kind(p, from) == TY_ARRAY && cg_type_kind(p, to) == TY_SLICE { cg_pack_view(p, m, f, from, node); return; }
    let value = cg_save(f, cg_wasm_type(p, from));
    if cg_type_kind(p, to) == TY_INT && p.types[to].index_type >= 0 && (n.flags & F_BOUNDS_PROVEN) == 0 {
        let symbol = p.types[to].pool;
        if symbol < 0 || cg_type_kind(p, from) != TY_INT { cg_fail(p, node, "wasm: index cast requires an integer and a resolved array owner"); return; }
        cg_symbol_address(p, m, f, symbol, node); let owner_type = p.symbols[symbol].type_id; cg_load(p, m, f, owner_type, 0); cg_pack_view(p, m, f, owner_type, node);
        ws_count(f.code); let length = cg_save(f, 0x7e);
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

inline fn cg_diverges(p: Program&, node: i64) -> bool {
    if node < 0 { return false; }
    let n: const Node& = p.nodes[node];
    if (n.flags & F_DIVERGES) == 0 { return false; }
    let k = n.kind;
    return k != N_FUNCTION && k != N_FUNCTION_VALUE && k != N_INTEGER && k != N_FLOAT && k != N_BOOL && k != N_NULL && k != N_STRING && k != N_NAME;
}
fn cg_terminal(p: Program&, node: i64) -> bool {
    if node < 0 { return false; }
    let n: const Node& = p.nodes[node];
    if cg_diverges(p, node) || n.kind == N_RETURN || n.kind == N_BREAK || n.kind == N_CONTINUE { return true; }
    if n.kind == N_EXPR_STMT { return cg_diverges(p, n.left); }
    if n.kind == N_VARIABLE || n.kind == N_ASSIGN { return cg_diverges(p, n.right); } return false;
}
recursive fn cg_bottom_prefix(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n: const Node& = p.nodes[node];
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
    if requested < 0 { return false; } let n: const Node& = p.nodes[node];
    let natural = cg_result_at(p, p.nodes[n.left].type_id, n.integer); let target = f.construction_destinations[requested].type_id;
    return natural == target && (cg_fixed_relative(p, natural) || m.regions_enabled && cg_region_value(p, natural));
}
recursive fn cg_project_result(p: Program&, m: CgModule&, f: CgBody&, node: i64, requested: i64) {
    let n: const Node& = p.nodes[node]; let tuple = p.nodes[n.left].type_id; let count = cg_result_count(p, tuple);
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
    let original = p.nodes[node].type_id; let diverges = cg_diverges(p, node); let kind = p.nodes[node].kind;
    if diverges && original < 0 && (kind == N_ARRAY || kind == N_FILL || kind == N_RECORD || kind == N_BINARY) {
        cg_bottom_prefix(p, m, f, node); wb_byte(f.code, 0x00); return;
    }
    if diverges && original < 0 { p.nodes[node].type_id = TYPE_VOID; }
    if m.regions_enabled && cg_region_value(p, original) && f.active_node != node &&
       (kind == N_BLOCK || kind == N_IF || kind == N_GUARD || kind == N_LOOP || kind == N_WHILE || kind == N_MATCH) {
        let receiving = cg_temporary_destination(p, m, f, original, node);
        if cg_owner(p, original) && cg_raw_value(f, node) { f.construction_destinations[receiving].elements = true; }
        cg_construct_region(p, m, f, node, receiving); cg_get(f, f.construction_destinations[receiving].header);
    } else { cg_expr_body(p, m, f, node); }
    p.nodes[node].type_id = original;
    if diverges { wb_byte(f.code, 0x00); }
}
recursive fn cg_expr_body(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    if node < 0 { return; } let n: const Node& = p.nodes[node]; let kind = n.kind;
    if kind == N_NAME {
        let sym = n.symbol;
        if sym >= 0 {
            if (p.symbols[sym].flags & S_FUNCTION) != 0 { cg_closure(p, m, f, sym, node); return; }
            if sym < f.slots.len {
                let sl: const CgSlot& = f.slots[sym];
                if sl.value { cg_get(f, sl.local); return; }
                if sl.sroa_count > 0 { cg_sroa_materialize(p, f, sym); return; }
                if sl.incoming >= 0 {
                    let start = f.code.len;
                    cg_get(f, sl.local); cg_load_fixed(p, f.code, p.symbols[sym].type_id, 0);
                    m.parameter_uses.push(CgParameterUse { symbol: sym, start: start, end: f.code.len });
                    return;
                }
            }
        }
        if sym < 0 { cg_fail(p, node, "wasm: unresolved name symbol"); return; }
        cg_symbol_address(p, m, f, sym, node);
        let stored = p.symbols[sym].type_id;
        if stored >= 0 && p.types[stored].kind == TY_INT && p.types[stored].storage == 1 { cg_load_fixed(p, f.code, TYPE_I64, 0); return; }
        if !cg_load(p, m, f, stored, 0) { cg_fail(p, node, "wasm: unresolved name value type"); }
        return;
    }
    if kind == N_INTEGER && n.type_id <= TYPE_F64 {
        if n.type_id == TYPE_I64 || n.type_id == TYPE_U64 { wb_i64(f.code, n.integer); return; }
        if n.type_id >= TYPE_BOOL && n.type_id <= TYPE_U32 { wb_i32(f.code, n.integer); return; }
        let w = cg_wasm_type(p, n.type_id);
        if w == 0x7e { wb_i64(f.code, n.integer); } else if w == 0x7d { wb_f32(f.code, n.integer); }
        else if w == 0x7c { wb_f64(f.code, n.integer); } else { wb_i32(f.code, n.integer); }
        return;
    }
    if kind == N_BOOL { wb_i32(f.code, n.integer); return; }
    if kind == N_RESULT {
        var requested = cg_receiving(f, -2 - node, 0); if requested < 0 && f.active_node == node { requested = f.active_destination; }
        cg_project_result(p, m, f, node, requested); return;
    }
    if (kind == N_MEMBER || kind == N_INDEX || kind == N_SLICE || kind == N_CAST || kind == N_UNARY) && cg_diverges(p, n.left) { cg_expr(p, m, f, n.left); return; }
    if kind == N_INTEGER && cg_type_kind(p, n.type_id) == TY_ENUM {
        if m.regions_enabled && cg_enum_image(p, n.type_id) { let receiving = cg_temporary_destination(p, m, f, n.type_id, node); cg_construct_region(p, m, f, node, receiving); cg_get(f, f.construction_destinations[receiving].header); return; }
        let destination = cg_temporary(p, f, n.type_id);
        if cg_enum_image(p, n.type_id) {
            var variant = p.types[n.type_id].first; while variant >= 0 && p.nodes[variant].integer != n.integer { variant = p.nodes[variant].next; }
            if variant < 0 { cg_fail(p, node, "wasm: enum constant has no matching variant"); return; }
            let payload_id = p.nodes[variant].type_id; let payload = cg_temporary(p, f, payload_id);
            cg_get(f, payload); cg_clear_bytes(p, f, cg_size(p, payload_id)); cg_enum_variant_image(p, m, f, n.type_id, destination, variant, payload, node);
        } else {
            cg_get(f, destination); cg_clear_bytes(p, f, cg_size(p, n.type_id));
            cg_get(f, destination); wb_i32(f.code, n.integer); if p.types[n.type_id].length_storage == 2 { wb_mem(f.code, 0x3b, 0, 0); } else { wb_mem(f.code, 0x3a, 0, 0); }
        }
        cg_get(f, destination); return;
    }
    if kind == N_INTEGER || kind == N_BOOL || kind == N_NULL {
        let w = cg_wasm_type(p, n.type_id);
        if w == 0x7e { wb_i64(f.code, n.integer); } else if w == 0x7d { wb_f32(f.code, n.integer); }
        else if w == 0x7c { wb_f64(f.code, n.integer); } else { wb_i32(f.code, n.integer); }
        return;
    }
    if kind == N_FLOAT { let w = cg_wasm_type(p, n.type_id); if w == 0x7d { wb_f32(f.code, n.float_value); } else { wb_f64(f.code, n.float_value); } return; }
    if kind == N_STRING {
        let token = p.tokens[n.token]; let bytes = p.text[token.text_start..token.text_start + token.text_len]; let address = cg_data(m, bytes);
        if cg_type_kind(p, n.type_id) == TY_SLICE { wC_slice_const(f.code, address, bytes.len); return; }
        if cg_type_kind(p, n.type_id) == TY_ARRAY {
            let destination = cg_temporary(p, f, n.type_id);
            if cg_owner(p, n.type_id) {
                wa_const(f.code, bytes.len); let count = cg_save(f, wa());
                let buffer = cg_owner_image(p, m, f, n.type_id, destination, count, count, node);
                cg_get(f, buffer); wa_const(f.code, address); wa_const(f.code, bytes.len); wb_copy(f.code);
            } else {
                cg_get(f, destination); cg_clear_bytes(p, f, cg_size(p, n.type_id));
                if p.types[n.type_id].array_kind == A_LIMITED { cg_get(f, destination); wa_const(f.code, bytes.len); cg_length_store(p, f, n.type_id); }
                cg_get(f, destination); wa_const(f.code, cg_static_prefix(p, n.type_id)); wa_op(f.code, 0x6a); wa_const(f.code, address); wa_const(f.code, bytes.len); wb_copy(f.code);
            }
            cg_get(f, destination); return;
        }
        cg_fail(p, node, "wasm: unsupported string representation"); return;
    }
    if kind == N_FUNCTION_VALUE { cg_closure(p, m, f, n.symbol, node); return; }
    if kind == N_ARRAY || kind == N_FILL { cg_array_literal(p, m, f, node); return; }
    if kind == N_RECORD { cg_record_literal(p, m, f, node); return; }
    if kind == N_UNARY {
        if n.integer == T_BITAND {
            if cg_type_kind(p, p.nodes[n.left].type_id) == TY_REF { cg_expr(p, m, f, n.left); }
            else { cg_address(p, m, f, n.left); } return;
        }
        if n.integer == T_MUL || n.integer == T_XOR {
            cg_expr(p, m, f, n.left); var storage = n.type_id; if n.aux >= 0 { storage = n.aux; }
            cg_load(p, m, f, storage, 0); cg_convert(p, m, f, storage, n.type_id, node); return;
        }
        if n.integer == T_NOT { cg_truth(p, m, f, n.left); wb_byte(f.code, 0x45); return; }
        let w = cg_wasm_type(p, n.type_id);
        if n.integer == T_MINUS && (w == 0x7d || w == 0x7c) {
            cg_to(p, m, f, n.left, n.type_id); var opcode = 0x8c; if w == 0x7c { opcode = 0x9a; } wb_byte(f.code, opcode); return;
        }
        if n.integer == T_MINUS { cg_zero(f.code, w); cg_to(p, m, f, n.left, n.type_id); cg_numeric(p, m, f, T_MINUS, n.type_id, node); return; }
        if n.integer == T_BITNOT { cg_to(p, m, f, n.left, n.type_id); if w == 0x7e { wb_i64(f.code, -1); } else { wb_i32(f.code, -1); } wb_byte(f.code, cg_numeric_opcode(T_XOR, w, false)); cg_normalize(p, f.code, n.type_id); return; }
        cg_fail(p, node, "wasm: unsupported unary operation"); return;
    }
    if n.kind == N_BINARY { cg_binary(p, m, f, node); return; }
    if n.kind == N_MEMBER {
        if n.symbol < 0 && (token_is(p, n.token, "len") || token_is(p, n.token, "cap")) {
            let is_len = token_is(p, n.token, "len");
            if is_len && f.hoists.len > 0 && m.resolver < 0 {
                let hi = cg_hoist_find(p, f, n.left);
                if hi >= 0 && f.hoists[hi].len_local >= 0 {
                    cg_get(f, f.hoists[hi].len_local);
                    cg_convert(p, m, f, TYPE_U64, n.type_id, node); return;
                }
            }
            cg_expr(p, m, f, n.left); var id = p.nodes[n.left].type_id;
            if cg_type_kind(p, id) == TY_REF { id = p.types[id].element; cg_load(p, m, f, id, 0); }
            if !is_len && cg_type_kind(p, id) == TY_ARRAY {
                if cg_owner(p, id) { let header = cg_save(f, wa()); cg_owner_read_capacity(p, m, f, header); wa_extend(f.code); }
                else { wb_byte(f.code, 0x1a); wb_i64(f.code, p.types[id].count); }
            } else if m.ordinary_owners && m.resolver < 0 && cg_owner(p, id) {
                wc_load(f.code, 1); wa_extend(f.code);
            } else { cg_pack_view(p, m, f, id, node); ws_count(f.code); }
            cg_convert(p, m, f, TYPE_U64, n.type_id, node); return;
        }
        if n.symbol >= 0 && n.symbol < p.nodes.len && p.nodes[n.symbol].kind == N_VARIANT {
            let destination = cg_temporary(p, f, n.type_id); cg_get(f, destination); cg_clear_bytes(p, f, cg_size(p, n.type_id)); cg_get(f, destination); return;
        }
        var id = n.type_id;
        if n.symbol >= 0 { id = p.nodes[n.symbol].type_id; }
        let reference = n.type_id != id && n.type_id >= 13 && cg_type_kind(p, n.type_id) == TY_REF && cg_type_kind(p, id) != TY_REF;
        if !reference && n.symbol >= 0 && n.symbol < p.nodes.len && p.nodes[n.symbol].kind == N_FIELD {
            if p.nodes[n.left].kind == N_NAME {
                let bsym = p.nodes[n.left].symbol;
                if bsym >= 0 && bsym < f.slots.len && f.slots[bsym].sroa_count > 0 {
                    let fi = cg_sroa_field_index(p, p.symbols[bsym].type_id, n.symbol);
                    if fi >= 0 {
                        cg_get(f, f.slots[bsym].local + fi);
                        cg_convert(p, m, f, id, n.type_id, node); return;
                    }
                }
            }
            let mv = cg_call_sroa_return(p, m, n.left);
            if mv > 0 && f.active_node != n.left && cg_receiving(f, -2 - n.left, 0) < 0 {
                let fi = cg_sroa_field_index(p, p.nodes[n.left].type_id, n.symbol);
                if fi >= 0 {
                    let saved_cn = f.sroa_call_node; let saved_cb = f.sroa_call_base;
                    f.sroa_call_node = n.left; f.sroa_call_base = -3 - fi;
                    cg_expr(p, m, f, n.left);
                    f.sroa_call_node = saved_cn; f.sroa_call_base = saved_cb;
                    if !cg_diverges(p, n.left) { cg_convert(p, m, f, id, n.type_id, node); }
                    return;
                }
            }
            let offset = cg_member_memory_offset(p, m, node, id);
            if offset > 0 {
                cg_member_object(p, m, f, node);
                cg_load_fixed(p, f.code, id, offset); cg_convert(p, m, f, id, n.type_id, node); return;
            }
        }
        cg_address(p, m, f, node);
        if reference { return; }
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
            var scratch = -1;
            if cg_may_print(p, m, node) { cg_record(f, 0x23, 0); wb_op(f.code, 0x23, 0); scratch = cg_save(f, wa()); }
            var regions = -1;
            if m.regions_enabled && cg_may_region(p, m, node) { regions = cg_mark_regions(f); }
            let done = cg_begin(f, 0x02, 0x40); f.exits.push(CgExit { label: done, node: node, result: result, type_id: n.type_id, scratch: scratch, regions: regions, publication: cg_mark_publications(m, f), defers: f.defers.len });
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
        let result = cg_control_slots(p, f, n.type_id, node);
        if cg_diverges(p, n.left) { cg_truth_scope(p, m, f, n.left); return; }
        if n.third < 0 {
            let skip = cg_begin(f, 0x02, 0x40);
            cg_branch_cond(p, m, f, n.left, skip, false);
            cg_block_into(p, m, f, n.right, n.type_id, result);
            cg_end(f);
        } else {
            let done = cg_begin(f, 0x02, 0x40);
            let other = cg_begin(f, 0x02, 0x40);
            cg_branch_cond(p, m, f, n.left, other, false);
            cg_block_into(p, m, f, n.right, n.type_id, result);
            cg_branch(p, f, done, false);
            cg_end(f);
            cg_block_into(p, m, f, n.third, n.type_id, result);
            cg_end(f);
        }
        cg_control_get(p, f, n.type_id, result); return;
    }
    if n.kind == N_WHILE || n.kind == N_LOOP { cg_loop(p, m, f, node); return; }
    if n.kind == N_FOR { cg_for(p, m, f, node); return; }
    if n.kind == N_MATCH { cg_match(p, m, f, node); return; }
    if n.kind == N_RETURN || n.kind == N_BREAK || n.kind == N_CONTINUE || n.kind == N_ASSIGN || n.kind == N_VARIABLE || n.kind == N_EXPR_STMT { cg_statement(p, m, f, node); return; }
    if n.kind == N_EMPTY { return; }
    cg_fail(p, node, "wasm: checked AST node has no binary lowering");
}
fn cg_ensure_memory(p: Program&, m: CgModule&, f: CgBody&, top: i64, node: i64) {
    if p.initial_pages == p.maximum_pages {
        cg_get(f, top); wa_const(f.code, p.maximum_pages * 65536); wa_op(f.code, 0x4b);
        cg_trap_if(p, m, f, node, "linear memory exhausted"); return;
    }
    // top is an address local. Page counts are address-sized: memory.size
    // gives and memory.grow takes and gives an i64 with cg_wide.
    cg_get(f, top); wb_op(f.code, 0x3f, 0); wa_const(f.code, 16); wa_op(f.code, 0x74); wa_op(f.code, 0x4b); cg_begin(f, 0x04, 0x40);
    cg_get(f, top); wa_const(f.code, 16); wa_op(f.code, 0x76);
    cg_get(f, top); wa_const(f.code, 65535); wa_op(f.code, 0x71); wa_op(f.code, 0x45); wb_byte(f.code, 0x45); wa_from_i32(f.code); wa_op(f.code, 0x6a);
    wb_op(f.code, 0x3f, 0); wa_op(f.code, 0x6b); wb_op(f.code, 0x40, 0); wa_const(f.code, -1); wa_op(f.code, 0x46);
    cg_trap_if(p, m, f, node, "linear memory exhausted"); cg_end(f);
}
// A scalar can live in a Wasm local unless code can observe its address.
let CG_ADDRESS_TAKEN: i64 = 512;
let CG_NO_SROA: i64 = 1024;
fn cg_scalar_slot_type(p: Program&, id: i64) -> bool {
    if !cg_scalar_type(p, id) { return false; }
    let kind = cg_type_kind(p, id);
    return kind == TY_BOOL || kind == TY_FLOAT || kind == TY_INT && (p.types[id].count == 32 || p.types[id].count == 64);
}
fn cg_local_slot_type(p: Program&, id: i64) -> bool {
    if id < 0 || id >= p.types.len { return false; }
    let t: const Type& = p.types[id];
    if t.kind == TY_REF { return t.length_storage < 0; }
    return t.kind == TY_BOOL || t.kind == TY_FLOAT || t.kind == TY_SLICE || t.kind == TY_FN || t.kind == TY_INT && t.storage == 0;
}
fn cg_scalar_slot_store(p: Program&, f: CgBody&, symbol: i64) {
    let id = p.symbols[symbol].type_id;
    if cg_type_kind(p, id) == TY_BOOL { wb_i32(f.code, 255); wb_byte(f.code, 0x71); }
    else if cg_type_kind(p, id) == TY_INT && p.types[id].count < 32 { cg_normalize(p, f.code, id); }
    cg_set(f, f.slots[symbol].local);
}
// Only ordinary fixed records use their private call-site snapshot as the
// parameter's storage. Packed images, owners and relative fields need their
// normal copy semantics. Dispatch arguments may be adapted for each arm.
let CG_DISPATCH_ENTRY: i64 = 144115188075855872;
recursive fn cg_snapshot_field(p: Program&, id: i64) -> bool {
    if id < 0 || p.types[id].size < 0 { return false; }
    let t: const Type& = p.types[id];
    if t.kind == TY_STRUCT {
        if root_struct_type(p, id) || t.tail >= 0 { return false; }
        var field = t.first;
        while field >= 0 {
            if (p.nodes[field].flags & F_PAD) == 0 && !cg_snapshot_field(p, p.nodes[field].type_id) { return false; }
            field = p.nodes[field].next;
        }
        return true;
    }
    if t.kind == TY_ARRAY { return t.array_kind == A_FIXED && cg_snapshot_field(p, t.element); }
    if t.kind == TY_REF { return t.length_storage < 0; }
    return t.kind == TY_BOOL || t.kind == TY_FLOAT || t.kind == TY_INT && t.storage == 0 || t.kind == TY_SLICE || t.kind == TY_FN;
}
fn cg_prepare_function(p: Program&, m: CgModule&, f: CgBody&, function: i64) {
    var param = -1; if function >= 0 { param = p.nodes[function].first; }
    while param >= 0 { f.params++; param = p.nodes[param].next; }
    if m.captures.len > 0 { for capture in m.captures { if capture.function == function { f.params++; } } }
    var results: i64[>..] = []; if function >= 0 { cg_function_results(p, function, results); }
    var sroa_ret: i64 = 0;
    if function >= 0 && f.function_index >= 0 && f.function_index < m.functions.len && m.functions[f.function_index].sroa_return > 0 {
        sroa_ret = m.functions[f.function_index].sroa_return;
    }
    let destination_start = f.params;
    if sroa_ret == 0 {
        for id in results { if cg_aggregate(p, id) { f.params++; } }
    }
    if function >= 0 && (p.nodes[function].flags & F_LOCATED) != 0 { f.at = f.params; f.params++; }
    f.frame = cg_local(f, wa());
    if !m.scalar && function >= 0 {
        let index = cg_function(m, p.nodes[function].symbol);
        if index >= 0 && m.functions[index].arena_local {
            f.heap_mark = cg_local(f, wa()); if m.resolver >= 0 { f.forward_mark = cg_local(f, wa()); }
        }
    }
    var parameter_count = 0; param = -1; if function >= 0 { param = p.nodes[function].first; }
    while param >= 0 {
        let id = p.nodes[param].type_id;
        let sym = p.nodes[param].symbol;
        if (p.nodes[function].flags & (F_EXPORT | CG_DISPATCH_ENTRY)) == 0 {
            if cg_type_kind(p, id) == TY_STRUCT && cg_snapshot_field(p, id) {
                f.slots[sym].local = parameter_count;
            } else if sym >= 0 && (p.symbols[sym].flags & CG_ADDRESS_TAKEN) == 0 && cg_local_slot_type(p, id) &&
                      cg_type_kind(p, id) != TY_BOOL && !(cg_type_kind(p, id) == TY_INT && p.types[id].count < 32) {
                f.slots[sym] = CgSlot { local: parameter_count, value: true };
            }
        }
        parameter_count++; param = p.nodes[param].next;
    }
    var capture_param = parameter_count;
    if m.captures.len > 0 {
        for capture in m.captures {
            if capture.function == function { f.slots[capture.symbol].local = capture_param; capture_param++; }
        }
    }
    var next = m.symbol_owners.heads[function + 1];
    while next >= 0 {
        let index = next; next = m.symbol_owners.next[index];
        let symbol: const Symbol& = p.symbols[index];
        if (symbol.flags & (S_FUNCTION | S_TYPE | S_GLOBAL | S_BUILTIN)) != 0 { continue; }
        if f.slots[index].local >= 0 { continue; }
        if function < 0 && !cg_storage_binding(p, index) { continue; }
        let size = cg_slot_size(p, symbol.type_id);
        if size <= 0 {
            if cg_dead_binding(p, symbol.node) { continue; }
            cg_fail(p, symbol.node, "wasm: variable has no physical layout"); continue;
        }
        var value = false;
        if function >= 0 && symbol.node >= 0 && (symbol.flags & CG_ADDRESS_TAKEN) == 0 && cg_local_slot_type(p, symbol.type_id) {
            let bkind = p.nodes[symbol.node].kind;
            value = bkind == N_PARAM || bkind == N_BINDING || bkind == N_VARIABLE;
        }
        if !value && p.optimization >= 2 && m.resolver < 0 && m.prefix_helper < 0 &&
           function >= 0 && symbol.node >= 0 && (symbol.flags & (CG_ADDRESS_TAKEN | CG_NO_SROA)) == 0 {
            let bkind = p.nodes[symbol.node].kind;
            if bkind == N_VARIABLE || bkind == N_BINDING {
                let sc = cg_sroa_struct(p, symbol.type_id);
                if sc > 0 {
                    var first_local = -1;
                    var field = p.types[symbol.type_id].first;
                    while field >= 0 {
                        if (p.nodes[field].flags & F_PAD) == 0 {
                            let fl = cg_local(f, cg_wasm_type(p, p.nodes[field].type_id));
                            if first_local < 0 { first_local = fl; }
                        }
                        field = p.nodes[field].next;
                    }
                    f.slots[index] = CgSlot { local: first_local, sroa_count: sc as i32 };
                    continue;
                }
            }
        }
        var wasm_type = wa(); if value { wasm_type = cg_wasm_type(p, symbol.type_id); }
        let local = cg_local(f, wasm_type);
        f.slots[index] = CgSlot { local: local, value: value };
        if !value {
            let offset = cg_frame(f, size, p.types[symbol.type_id].align);
            f.addresses.push(CgFrameAddress { local: local, offset: offset });
        }
    }
    if sroa_ret > 0 && results.len == 1 {
        var field = p.types[results[0]].first;
        while field >= 0 {
            if (p.nodes[field].flags & F_PAD) == 0 {
                f.results.push(cg_local(f, cg_wasm_type(p, p.nodes[field].type_id)));
            }
            field = p.nodes[field].next;
        }
        f.destinations.push(-1);
        f.sroa_return = sroa_ret;
    } else {
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
        if function >= 0 && !m.nonlocal_returns && m.resolver < 0 && results.len == 1 && f.destinations[0] >= 0 &&
           cg_plain_fixed_aggregate(p, results[0]) {
            f.direct_return = true;
        }
    }
    if !m.nonlocal_returns { return; }
    var mailbox_size = 16;
    for id in results { mailbox_size = cg_align(mailbox_size, 8) + cg_size(p, id); }
    if function >= 0 && cg_nonlocal_target(p, function) &&
       (m.regions_enabled && cg_region_owned_result(p, cg_result_type(p, function)) || cg_fixed_relative_results(p, cg_result_type(p, function))) {
        f.effect_metadata = cg_align(mailbox_size, 8); mailbox_size = f.effect_metadata + results.len * ww(3);
    }
    if !m.scalar { f.effect = cg_frame(f, mailbox_size, 8); }
}
fn cg_emit_prelude(p: Program&, m: CgModule&, f: CgBody&) {
    if m.scalar { if !f.frame_free { wb_op(f.code, 0x23, 0); cg_set(f, f.frame); } return; }
    let needs_frame = m.nonlocal_returns || f.frame_bytes > 0 || f.frame_used || f.addresses.len > 0;
    if needs_frame {
        wb_op(f.code, 0x23, 0); cg_set(f, f.frame);
        let bytes = cg_align(f.frame_bytes, 8);
        if bytes > 0 {
            cg_get(f, f.frame); wa_const(f.code, bytes); wa_op(f.code, 0x6a); let top = cg_save(f, wa());
            // With fixed memory, every valid frame is already committed. A frame
            // that fits the remaining address bits also cannot wrap the addition.
            let fixed = p.initial_pages == p.maximum_pages;
            let check_wrap = !fixed || bytes < 0 || !cg_wide && bytes > 4294967295 - p.maximum_pages * 65536;
            if check_wrap { cg_get(f, top); cg_get(f, f.frame); wa_op(f.code, 0x49); }
            cg_get(f, top);
            if m.regions_enabled { wb_op(f.code, 0x23, 10); } else { wa_const(f.code, m.stack_limit); }
            wa_op(f.code, 0x4b); if check_wrap { wb_byte(f.code, 0x72); }
            cg_trap_if(p, m, f, f.function, "activation stack exhausted");
            if !fixed { cg_ensure_memory(p, m, f, top, f.function); }
            cg_get(f, top); wb_op(f.code, 0x24, 0);
        }
    }
    if f.region_mark >= 0 { wb_op(f.code, 0x23, 3); cg_set(f, f.region_mark); }
    if f.publication_mark >= 0 { wb_op(f.code, 0x23, 11); cg_set(f, f.publication_mark); }
    if f.heap_mark >= 0 { wb_op(f.code, 0x23, 1); cg_set(f, f.heap_mark); }
    if f.forward_mark >= 0 { wb_op(f.code, 0x23, 5); cg_set(f, f.forward_mark); }
    for address in f.addresses { cg_frame_address(f, address.offset); cg_set(f, address.local); }
    if !m.nonlocal_returns { return; }
    // The effect record: word 0 the previous chain, word 1 the function
    // number, both address-sized; the result mailbox from byte 16 on.
    cg_frame_address(f, f.effect); wb_op(f.code, 0x23, 4); wa_store(f.code, 0);
    cg_frame_address(f, f.effect); wa_const(f.code, f.function + 1); wa_store(f.code, ww(1));
    cg_frame_address(f, f.effect); wb_op(f.code, 0x24, 4);
    if f.effect_metadata >= 0 {
        let result_type = cg_result_type(p, f.function);
        for ordinal in 0..cg_result_count(p, result_type) {
            let id = cg_result_at(p, result_type, ordinal);
            if cg_fixed_relative(p, id) {
                cg_frame_address(f, f.effect + f.effect_metadata + ordinal * ww(3)); cg_get(f, f.destinations[ordinal]); wa_store(f.code, 0); continue;
            }
            if !cg_region_value(p, id) { continue; }
            let original = f.destinations[ordinal]; let original_tail = cg_region_header(p, f, id, original); let entry = cg_region_cursor(f, original_tail); let metadata = f.effect_metadata + ordinal * ww(3);
            cg_frame_address(f, f.effect + metadata); cg_get(f, original); wa_store(f.code, 0);
            cg_frame_address(f, f.effect + metadata + ww(2)); cg_get(f, entry); wa_store(f.code, 0);
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
        if f.slots[symbol].local == index { param = p.nodes[param].next; index++; continue; }
        let start = f.code.len;
        if f.slots[symbol].value { cg_get(f, index); cg_scalar_slot_store(p, f, symbol); }
        else if m.regions_enabled && cg_region_value(p, id) { cg_get(f, f.slots[symbol].local); cg_get(f, index); wa_const(f.code, cg_size(p, id)); wb_copy(f.code); }
        else { cg_get(f, index); cg_write_value(p, m, f, id, f.slots[symbol].local, param); }
        if !f.slots[symbol].value && m.prefix_helper < 0 && m.resolver < 0 && cg_type_kind(p, id) == TY_REF && !cg_relative_type(p, id) {
            f.slots[symbol].incoming = index;
            m.parameter_uses.push(CgParameterUse { symbol: symbol, start: start, end: f.code.len, initial: true });
        }
        param = p.nodes[param].next; index++;
    }
}
fn cg_emit_epilogue(p: Program&, m: CgModule&, f: CgBody&) {
    if m.scalar {
        if !f.frame_free { cg_get(f, f.frame); wb_op(f.code, 0x24, 0); }
        for result in f.results { cg_get(f, result); } cg_control(f, 0x0b); return;
    }
    var results: i64[>..] = []; if f.function >= 0 { cg_function_results(p, f.function, results); }
    if m.nonlocal_returns {
        wb_op(f.code, 0x23, 2); cg_frame_address(f, f.effect); wa_op(f.code, 0x46); cg_begin(f, 0x04, 0x40);
        var offset = 16;
        for id, i in results {
            offset = cg_align(offset, 8);
            if f.effect_metadata >= 0 && cg_fixed_relative(p, id) {
                cg_frame_address(f, f.effect + f.effect_metadata + i * ww(3)); wa_load(f.code, 0); cg_set(f, f.results[i]);
            } else if f.effect_metadata >= 0 && cg_region_value(p, id) {
                cg_frame_address(f, f.effect + f.effect_metadata + i * ww(3)); wa_load(f.code, 0); let original = cg_save(f, wa());
                cg_frame_address(f, f.effect + f.effect_metadata + i * ww(3) + ww(1)); wa_load(f.code, 0); let start = cg_save(f, wa());
                cg_frame_address(f, f.effect + f.effect_metadata + i * ww(3) + ww(2)); wa_load(f.code, 0); let entry = cg_save(f, wa());
                cg_frame_address(f, f.effect + offset); let stage = cg_save(f, wa());
                if cg_enum_image(p, id) { cg_set_enum_anchor(f, original, entry); cg_finish_enum(p, m, f, id, original, start, true, f.function); }
                else if cg_image_owner(p, id) {
                    cg_set_record_anchor(p, m, f, id, original, entry, f.function); cg_finish_record_image(p, m, f, id, original, start, true, f.function);
                } else if cg_frame_owner(p, id) { cg_finish_frame_record(p, m, f, id, original, stage, start, entry, true, f.function); }
                else {
                    if p.types[id].array_kind != A_LIMITED && p.types[id].array_kind != A_VAR { cg_get(f, original); cg_get(f, entry); wc_store(f.code, 0); }
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
        wa_const(f.code, 0); wb_op(f.code, 0x24, 2); cg_end(f);
        cg_frame_address(f, f.effect); wa_load(f.code, 0); wb_op(f.code, 0x24, 4);
        wb_op(f.code, 0x23, 2); wa_op(f.code, 0x45); cg_begin(f, 0x04, 0x40);
    }
    for id, i in results {
        if f.destinations[i] >= 0 {
            if f.direct_return && i == 0 { cg_get(f, f.destinations[0]); cg_set(f, f.results[0]); continue; }
            if m.regions_enabled && cg_region_value(p, id) { cg_get(f, f.destinations[i]); cg_set(f, f.results[i]); continue; }
            let saved_raw = f.raw_node; if f.elements && i == 0 { f.raw_node = f.function; }
            cg_copy(p, m, f, id, f.destinations[i], f.results[i], f.function); f.raw_node = saved_raw; cg_get(f, f.destinations[i]); cg_set(f, f.results[i]); }
    }
    if m.nonlocal_returns { cg_end(f); }
    // The prelude is written after the body. Only save globals this body can change.
    if f.acquisitions > 0 { f.region_mark = cg_local(f, 0x7f); }
    if f.publishes { f.publication_mark = cg_local(f, wa()); }
    cg_restore_regions(f, f.region_mark); cg_restore_publications(f, f.publication_mark);
    if f.heap_mark >= 0 { cg_get(f, f.heap_mark); wb_op(f.code, 0x24, 1); }
    if f.forward_mark >= 0 { cg_get(f, f.forward_mark); wb_op(f.code, 0x24, 5); }
    if m.nonlocal_returns || f.frame_bytes > 0 || f.frame_used || f.addresses.len > 0 {
        cg_get(f, f.frame); wb_op(f.code, 0x24, 0);
    }
    for result in f.results { cg_get(f, result); } cg_control(f, 0x0b);
}
// Move the events from an unchanged byte run. The write cursor can trail
// the read cursor after a removed parameter use.
fn cg_copy_events(events: WbEvent[>..]&, read: i64&, write: i64&, end: i64, delta: i64) {
    while read < events.len {
        let start = events[read].start as i64;
        if start >= end { return; }
        if read != write { events[write] = events[read]; }
        if delta != 0 { events[write].start = (start + delta) as i32; }
        read++; write++;
    }
}
fn cg_emit_function(p: Program&, m: CgModule&, function: i64, function_index: i64, elements: bool, out: u8[>..]&, slots: CgSlot[>..]&, scratch: CgEmitScratch&) {
    scratch.events.clear(); scratch.code.clear(); scratch.locals.clear(); scratch.addresses.clear();
    scratch.labels.clear(); scratch.exits.clear(); scratch.results.clear(); scratch.destinations.clear();
    scratch.work.clear(); scratch.raw_slots.clear(); scratch.sequences.clear();
    scratch.constructions.clear(); scratch.construction_destinations.clear(); scratch.receiving.clear(); scratch.defers.clear(); scratch.hoists.clear();
    var f = CgBody { events: scratch.events, code: scratch.code, locals: scratch.locals, slots: slots, addresses: scratch.addresses, labels: scratch.labels, exits: scratch.exits, results: scratch.results, destinations: scratch.destinations, work: scratch.work, raw_slots: scratch.raw_slots, sequences: scratch.sequences, constructions: scratch.constructions, construction_destinations: scratch.construction_destinations, receiving: scratch.receiving, hoists: scratch.hoists, record_events: !m.scalar, function: function, function_index: function_index, elements: elements, defers: scratch.defers };
    cg_prepare_function(p, m, f, function);
    if m.scalar && function >= 0 { f.frame_free = !cg_scalar_prints(p, p.nodes[function].right); }
    f.done = cg_begin(f, 0x02, 0x40);
    if function >= 0 {
        cg_parameter_copies(p, m, f); let id = cg_result_type(p, function); var first = -1; if f.results.len > 0 { first = f.results[0]; }
        cg_block_into(p, m, f, p.nodes[function].right, id, first);
    } else {
        for symbol in p.symbols {
            if (symbol.flags & S_GLOBAL) != 0 && symbol.node >= 0 && symbol.component_owner < 0 {
                let live = f.region_live; let acq = f.acquisitions; var regions = -1;
                if m.regions_enabled { regions = cg_mark_regions(f); }
                cg_declaration(p, m, f, symbol.node);
                if f.acquisitions != acq { cg_restore_regions(f, regions); }
                f.region_live = live;
            }
        }
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
    scratch.body.clear(); var cursor = 0;
    var event_read = 0; var event_write = 0; var parameter_edits = false;
    for use in m.parameter_uses {
        if slots[use.symbol].address_used { continue; }
        if f.record_events {
            cg_copy_events(scratch.events, event_read, event_write, use.start, scratch.body.len - cursor);
            while event_read < scratch.events.len && (scratch.events[event_read].start as i64) < use.end { event_read++; }
            parameter_edits = true;
        }
        scratch.body.append(scratch.code[cursor..use.start]);
        // The replacement accesses an incoming parameter and needs no event.
        if !use.initial { wb_op(scratch.body, 0x20, slots[use.symbol].incoming); }
        cursor = use.end;
    }
    m.parameter_uses.clear();
    if parameter_edits {
        cg_copy_events(scratch.events, event_read, event_write, scratch.code.len, scratch.body.len - cursor);
        scratch.events.resize(event_write);
    }
    let body_event_count = scratch.events.len;
    scratch.body.append(scratch.code[cursor..]); scratch.code.clear(); cg_emit_prelude(p, m, f);
    let prelude_bytes = scratch.code.len;
    scratch.code.append(scratch.body);
    if m.scalar { wb_compact_body(out, scratch.locals, scratch.code, f.params); }
    else {
        wb_reuse_locals(scratch.locals, scratch.code, f.params, scratch.events, body_event_count, prelude_bytes, f.acquisitions == 0, scratch.reuse);
        wb_body(out, scratch.locals, scratch.code);
    }
    m.region_functions[function_index].own = f.region_peak;
    // The next body reuses the table. Only this body's bindings and
    // captures acquired slots.
    var binding = m.symbol_owners.heads[function + 1];
    while binding >= 0 { slots[binding] = CgSlot {}; binding = m.symbol_owners.next[binding]; }
    for capture in m.captures { if capture.function == function { slots[capture.symbol] = CgSlot {}; } }
}
fn cg_emit_array_helper(p: Program&, m: CgModule&, out: u8[>..]&, helper: i64) {
    var events: WbEvent[>..] = [];
    var code: u8[>..] = []; var locals: i64[>..] = []; var slots: CgSlot[>..] = []; var addresses: CgFrameAddress[>..] = [];
    var labels: i64[>..] = []; var exits: CgExit[>..] = []; var results: i64[>..] = []; var destinations: i64[>..] = []; var work: i64[>..] = []; var raw_slots: i64[>..] = []; var sequences: CgSequence[>..] = []; var constructions: CgConstruction[>..] = []; var construction_destinations: CgDestination[>..] = []; var receiving: CgReceiving[>..] = []; var defers: i64[>..] = []; var hoists: CgHoist[>..] = [];
    var f = CgBody { events: events, code: code, locals: locals, slots: slots, addresses: addresses, labels: labels, exits: exits, results: results, destinations: destinations, work: work, raw_slots: raw_slots, sequences: sequences, constructions: constructions, construction_destinations: construction_destinations, receiving: receiving, hoists: hoists, params: 4, diagnostic_line: 3, defers: defers };
    if helper == m.update_length {
        f.params = 3; f.diagnostic_line = 2;
        cg_update_image_length(p, m, f, 0, 1, -1);
    } else if helper == m.owner_view {
        f.params = 2; f.diagnostic_line = 1;
        cg_owner_read_base(p, m, f, 0, -1); wa_extend(code);
        cg_owner_read_length(p, m, f, 0, -1); wa_extend(code); ws_pack(f);
    } else { cg_format_bytes_inline(p, m, f, m.raw_append_type, 0, 1, 2, -1); }
    wb_byte(code, 0x0b); wb_body(out, locals, code);
}
// goose.reserve(control, count) -> address, exported for a host: makes room
// for count more bytes at the end of the growable byte array whose control is
// given, as a push would (length, region cursor, memory), and returns where
// they go. The host copies them in. It needs to know nothing of regions.
fn cg_emit_host_reserve(p: Program&, m: CgModule&, out: u8[>..]&) {
    var events: WbEvent[>..] = [];
    var code: u8[>..] = []; var locals: i64[>..] = []; var slots: CgSlot[>..] = []; var addresses: CgFrameAddress[>..] = [];
    var labels: i64[>..] = []; var exits: CgExit[>..] = []; var results: i64[>..] = []; var destinations: i64[>..] = []; var work: i64[>..] = []; var raw_slots: i64[>..] = []; var sequences: CgSequence[>..] = []; var constructions: CgConstruction[>..] = []; var construction_destinations: CgDestination[>..] = []; var receiving: CgReceiving[>..] = []; var defers: i64[>..] = []; var hoists: CgHoist[>..] = [];
    var f = CgBody { events: events, code: code, locals: locals, slots: slots, addresses: addresses, labels: labels, exits: exits, results: results, destinations: destinations, work: work, raw_slots: raw_slots, sequences: sequences, constructions: constructions, construction_destinations: construction_destinations, receiving: receiving, hoists: hoists, params: 2, defers: defers };
    let id = m.host_reserve_type;
    cg_array_length(p, m, f, id, 0); let old = cg_save(f, wa());
    cg_get(f, old); wa_extend(f.code); cg_get(f, 1); wa_extend(f.code); wb_byte(f.code, 0x7c); let wide = cg_save(f, 0x7e);
    if cg_wide { cg_get(f, wide); cg_get(f, old); wb_byte(f.code, 0x54); } else { cg_get(f, wide); wb_i64(f.code, 4294967295); wb_byte(f.code, 0x56); }
    cg_trap_if(p, m, f, -1, "array length overflow"); cg_get(f, wide); wa_wrap(f.code); let count = cg_save(f, wa());
    cg_get(f, 1); wa_extend(f.code); let bytes = cg_save(f, 0x7e); let reserved = cg_region_reserve_at(p, m, f, 0, bytes, -1);
    cg_region_publish_at(f, reserved.limit, reserved.top); cg_array_set_length(p, m, f, id, 0, count);
    cg_get(f, reserved.cursor); wb_byte(code, 0x0b); wb_body(out, locals, code);
}
// Reusable[] slice-pool helpers: O(1) hashed pool-state map plus the exact
// 512-byte B+ max-augmented span tree from native/runtime/runtime_impl.h
// (LEAF = 31, FAN = 20, DEPTH = 24), emitted once per module when used.
fn cg_sp_node_ptr(f: CgBody&, base: i64, node_id: i64) {
    cg_get(f, base); cg_get(f, node_id); wb_i64(f.code, 9); wb_byte(f.code, 0x86); wa_wrap(f.code); wa_op(f.code, 0x6a);
}
fn cg_sp_slot_addr(f: CgBody&, addr: i64, idx: i64, off: i64) {
    cg_get(f, addr); cg_get(f, idx); wb_i64(f.code, 3); wb_byte(f.code, 0x86); wa_wrap(f.code); wa_op(f.code, 0x6a); wa_add(f.code, off);
}
fn cg_sp_load64(f: CgBody&, addr: i64, idx: i64, off: i64) {
    cg_sp_slot_addr(f, addr, idx, off); wb_mem(f.code, 0x29, 3, 0);
}
fn cg_sp_open_arr(f: CgBody&, node_addr: i64, n_loc: i64, s_loc: i64, off: i64) {
    cg_get(f, n_loc); cg_get(f, s_loc); wb_byte(f.code, 0x55); cg_begin(f, 0x04, 0x40);
    cg_get(f, node_addr); cg_get(f, s_loc); wb_i64(f.code, 1); wb_byte(f.code, 0x7c); wb_i64(f.code, 3); wb_byte(f.code, 0x86); wa_wrap(f.code); wa_op(f.code, 0x6a); wa_add(f.code, off);
    cg_get(f, node_addr); cg_get(f, s_loc); wb_i64(f.code, 3); wb_byte(f.code, 0x86); wa_wrap(f.code); wa_op(f.code, 0x6a); wa_add(f.code, off);
    cg_get(f, n_loc); cg_get(f, s_loc); wb_byte(f.code, 0x7d); wb_i64(f.code, 3); wb_byte(f.code, 0x86); wa_wrap(f.code);
    wb_copy(f.code); cg_end(f);
}
fn cg_sp_close_arr(f: CgBody&, node_addr: i64, new_n: i64, s_loc: i64, off: i64) {
    cg_get(f, new_n); cg_get(f, s_loc); wb_byte(f.code, 0x55); cg_begin(f, 0x04, 0x40);
    cg_get(f, node_addr); cg_get(f, s_loc); wb_i64(f.code, 3); wb_byte(f.code, 0x86); wa_wrap(f.code); wa_op(f.code, 0x6a); wa_add(f.code, off);
    cg_get(f, node_addr); cg_get(f, s_loc); wb_i64(f.code, 1); wb_byte(f.code, 0x7c); wb_i64(f.code, 3); wb_byte(f.code, 0x86); wa_wrap(f.code); wa_op(f.code, 0x6a); wa_add(f.code, off);
    cg_get(f, new_n); cg_get(f, s_loc); wb_byte(f.code, 0x7d); wb_i64(f.code, 3); wb_byte(f.code, 0x86); wa_wrap(f.code);
    wb_copy(f.code); cg_end(f);
}
fn cg_sp_leaf_close(f: CgBody&, lf: i64, k_loc: i64) {
    cg_get(f, lf); wb_mem(f.code, 0x29, 3, 0); wb_i64(f.code, 1); wb_byte(f.code, 0x7d); let nn = cg_save(f, 0x7e);
    cg_get(f, lf); cg_get(f, nn); wb_mem(f.code, 0x37, 3, 0);
    cg_sp_close_arr(f, lf, nn, k_loc, 16);
    cg_sp_close_arr(f, lf, nn, k_loc, 264);
}
fn cg_sp_inner_close(f: CgBody&, inn: i64, k_loc: i64) {
    cg_get(f, inn); wb_mem(f.code, 0x29, 3, 0); wb_i64(f.code, 1); wb_byte(f.code, 0x7d); let nn = cg_save(f, 0x7e);
    cg_get(f, inn); cg_get(f, nn); wb_mem(f.code, 0x37, 3, 0);
    cg_sp_close_arr(f, inn, nn, k_loc, 16);
    cg_sp_close_arr(f, inn, nn, k_loc, 176);
    cg_sp_close_arr(f, inn, nn, k_loc, 336);
}
fn cg_sp_dropnode(f: CgBody&, base: i64, node_id: i64) {
    cg_sp_node_ptr(f, base, node_id);
    cg_get(f, base); wb_mem(f.code, 0x29, 3, 16);
    wb_mem(f.code, 0x37, 3, 8);
    cg_get(f, base); cg_get(f, node_id); wb_mem(f.code, 0x37, 3, 16);
}
fn cg_sp_scan_max(p: Program&, f: CgBody&, node_addr: i64, leaf_i32: i64, stop_i64: i64) -> i64 {
    cg_get(f, node_addr);
    wa_const(f.code, 264); wa_const(f.code, 176); cg_get(f, leaf_i32); wb_byte(f.code, 0x1b);
    wa_op(f.code, 0x6a); let arr = cg_save(f, wa());
    cg_get(f, node_addr); wb_mem(f.code, 0x29, 3, 0); let w = cg_save(f, 0x7e);
    wb_i64(f.code, 0); let mx = cg_save(f, 0x7e);
    wb_i64(f.code, 0); let k = cg_save(f, 0x7e);
    let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
    cg_get(f, k); cg_get(f, w); wb_byte(f.code, 0x59);
    cg_get(f, mx); cg_get(f, stop_i64); wb_byte(f.code, 0x59); wb_byte(f.code, 0x72);
    cg_branch(p, f, done, true);
    cg_sp_load64(f, arr, k, 0); let v = cg_save(f, 0x7e);
    cg_get(f, v); cg_get(f, mx); wb_byte(f.code, 0x55); cg_begin(f, 0x04, 0x40);
    cg_get(f, v); cg_set(f, mx); cg_end(f);
    cg_get(f, k); wb_i64(f.code, 1); wb_byte(f.code, 0x7c); cg_set(f, k);
    cg_branch(p, f, again, false); cg_end(f); cg_end(f);
    return mx;
}
fn cg_sp_emit_newroot(p: Program&, m: CgModule&, f: CgBody&, state_loc: i64, a_loc: i64, b_loc: i64, leaf_i32: i64) {
    cg_get(f, state_loc); wb_op(f.code, 0x10, m.spans_newnode); let r = cg_save(f, 0x7e);
    cg_get(f, state_loc); wa_load(f.code, ww(2)); let base = cg_save(f, wa());
    cg_sp_node_ptr(f, base, r); let rn = cg_save(f, wa());
    cg_sp_node_ptr(f, base, a_loc); let an = cg_save(f, wa());
    cg_sp_node_ptr(f, base, b_loc); let bn = cg_save(f, wa());
    wb_i64(f.code, 9223372036854775807); let big = cg_save(f, 0x7e);
    let ma = cg_sp_scan_max(p, f, an, leaf_i32, big);
    let mb = cg_sp_scan_max(p, f, bn, leaf_i32, big);
    cg_get(f, rn); wb_i64(f.code, 2); wb_mem(f.code, 0x37, 3, 0);
    cg_get(f, rn); cg_get(f, an); wb_mem(f.code, 0x29, 3, 16); wb_mem(f.code, 0x37, 3, 16);
    cg_get(f, rn); cg_get(f, ma); wb_mem(f.code, 0x37, 3, 176);
    cg_get(f, rn); cg_get(f, a_loc); wb_mem(f.code, 0x37, 3, 336);
    cg_get(f, rn); cg_get(f, bn); wb_mem(f.code, 0x29, 3, 16); wb_mem(f.code, 0x37, 3, 24);
    cg_get(f, rn); cg_get(f, mb); wb_mem(f.code, 0x37, 3, 184);
    cg_get(f, rn); cg_get(f, b_loc); wb_mem(f.code, 0x37, 3, 344);
    cg_get(f, base); cg_get(f, r); wb_mem(f.code, 0x37, 3, 0);
    cg_get(f, base); cg_get(f, base); wb_mem(f.code, 0x29, 3, 8); wb_i64(f.code, 1); wb_byte(f.code, 0x7c); wb_mem(f.code, 0x37, 3, 8);
}
fn cg_emit_pool_state_fn(p: Program&, m: CgModule&, out: u8[>..]&) {
    var events: WbEvent[>..] = [];
    var code: u8[>..] = []; var locals: i64[>..] = []; var slots: CgSlot[>..] = []; var addresses: CgFrameAddress[>..] = [];
    var labels: i64[>..] = []; var exits: CgExit[>..] = []; var results: i64[>..] = []; var destinations: i64[>..] = []; var work: i64[>..] = []; var raw_slots: i64[>..] = []; var sequences: CgSequence[>..] = []; var constructions: CgConstruction[>..] = []; var construction_destinations: CgDestination[>..] = []; var receiving: CgReceiving[>..] = []; var defers: i64[>..] = []; var hoists: CgHoist[>..] = [];
    var f = CgBody { events: events, code: code, locals: locals, slots: slots, addresses: addresses, labels: labels, exits: exits, results: results, destinations: destinations, work: work, raw_slots: raw_slots, sequences: sequences, constructions: constructions, construction_destinations: construction_destinations, receiving: receiving, hoists: hoists, params: 1, defers: defers };
    var eshift = 3; if cg_wide { eshift = 4; }
    wb_op(code, 0x23, m.pool_global); let map = cg_save(f, wa());
    cg_get(f, map); wa_op(code, 0x45); cg_begin(f, 0x04, 0x40);
    wa_const(code, ww(3)); wb_op(code, 0x10, m.allocator); cg_set(f, map);
    wa_const(code, 16 * ww(2)); wb_op(code, 0x10, m.allocator); let init_b = cg_save(f, wa());
    cg_get(f, init_b); wb_i32(code, 0); wa_const(code, 16 * ww(2)); wb_fill(code);
    cg_get(f, map); cg_get(f, init_b); wa_store(code, 0);
    cg_get(f, map); wa_const(code, 0); wa_store(code, ww(1));
    cg_get(f, map); wa_const(code, 15); wa_store(code, ww(2));
    cg_get(f, map); wb_op(code, 0x24, m.pool_global);
    cg_end(f);
    cg_get(f, map); wa_load(code, 0); let buckets = cg_save(f, wa());
    cg_get(f, map); wa_load(code, ww(2)); let mask = cg_save(f, wa());
    cg_get(f, 0); wa_const(code, 3); wa_op(code, 0x76); wa_const(code, 2654435761); wa_op(code, 0x6c); cg_get(f, mask); wa_op(code, 0x71);
    let slot = cg_save(f, wa());
    wa_const(code, 0); let entry = cg_save(f, wa());
    let pdone = cg_begin(f, 0x02, 0x40); let pagain = cg_begin(f, 0x03, 0x40);
    cg_get(f, buckets); cg_get(f, slot); wa_const(code, eshift); wa_op(code, 0x74); wa_op(code, 0x6a); cg_set(f, entry);
    cg_get(f, entry); wa_load(code, 0); let k = cg_save(f, wa());
    cg_get(f, k); cg_get(f, 0); wa_op(code, 0x46); cg_begin(f, 0x04, 0x40);
    cg_get(f, entry); wa_load(code, ww(1)); wb_byte(code, 0x0f); cg_end(f);
    cg_get(f, k); wa_op(code, 0x45); cg_branch(p, f, pdone, true);
    cg_get(f, slot); wa_const(code, 1); wa_op(code, 0x6a); cg_get(f, mask); wa_op(code, 0x71); cg_set(f, slot);
    cg_branch(p, f, pagain, false); cg_end(f); cg_end(f);
    wa_const(code, ww(5)); wb_op(code, 0x10, m.allocator); let st = cg_save(f, wa());
    cg_get(f, st); wb_i32(code, 0); wa_const(code, ww(5)); wb_fill(code);
    cg_get(f, st); cg_get(f, 0); wa_store(code, ww(1));
    cg_get(f, entry); cg_get(f, 0); wa_store(code, 0);
    cg_get(f, entry); cg_get(f, st); wa_store(code, ww(1));
    cg_get(f, map); wa_load(code, ww(1)); wa_const(code, 1); wa_op(code, 0x6a); let count = cg_save(f, wa());
    cg_get(f, map); cg_get(f, count); wa_store(code, ww(1));
    cg_get(f, count); wa_const(code, 1); wa_op(code, 0x74); cg_get(f, mask); wa_op(code, 0x4b); cg_begin(f, 0x04, 0x40);
    cg_get(f, mask); wa_const(code, 1); wa_op(code, 0x6a); let old_cap = cg_save(f, wa());
    cg_get(f, old_cap); wa_const(code, 1); wa_op(code, 0x74); let new_cap = cg_save(f, wa());
    cg_get(f, new_cap); wa_const(code, 1); wa_op(code, 0x6b); let new_mask = cg_save(f, wa());
    cg_get(f, new_cap); wa_const(code, eshift); wa_op(code, 0x74); let nb_bytes = cg_save(f, wa());
    cg_get(f, nb_bytes); wb_op(code, 0x10, m.allocator); let nb = cg_save(f, wa());
    cg_get(f, nb); wb_i32(code, 0); cg_get(f, nb_bytes); wb_fill(code);
    wa_const(code, 0); let ri = cg_save(f, wa());
    let rdone = cg_begin(f, 0x02, 0x40); let ragain = cg_begin(f, 0x03, 0x40);
    cg_get(f, ri); cg_get(f, old_cap); wa_op(code, 0x4f); cg_branch(p, f, rdone, true);
    cg_get(f, buckets); cg_get(f, ri); wa_const(code, eshift); wa_op(code, 0x74); wa_op(code, 0x6a); let oe = cg_save(f, wa());
    cg_get(f, oe); wa_load(code, 0); let ok = cg_save(f, wa());
    cg_get(f, ok); wa_truth(code); cg_begin(f, 0x04, 0x40);
    cg_get(f, ok); wa_const(code, 3); wa_op(code, 0x76); wa_const(code, 2654435761); wa_op(code, 0x6c); cg_get(f, new_mask); wa_op(code, 0x71);
    let ns = cg_save(f, wa());
    let idn = cg_begin(f, 0x02, 0x40); let iag = cg_begin(f, 0x03, 0x40);
    cg_get(f, nb); cg_get(f, ns); wa_const(code, eshift); wa_op(code, 0x74); wa_op(code, 0x6a); let ne = cg_save(f, wa());
    cg_get(f, ne); wa_load(code, 0); wa_op(code, 0x45); cg_begin(f, 0x04, 0x40);
    cg_get(f, ne); cg_get(f, ok); wa_store(code, 0);
    cg_get(f, ne); cg_get(f, oe); wa_load(code, ww(1)); wa_store(code, ww(1));
    cg_branch(p, f, idn, false); cg_end(f);
    cg_get(f, ns); wa_const(code, 1); wa_op(code, 0x6a); cg_get(f, new_mask); wa_op(code, 0x71); cg_set(f, ns);
    cg_branch(p, f, iag, false); cg_end(f); cg_end(f);
    cg_end(f);
    cg_get(f, ri); wa_const(code, 1); wa_op(code, 0x6a); cg_set(f, ri);
    cg_branch(p, f, ragain, false); cg_end(f); cg_end(f);
    cg_get(f, map); cg_get(f, nb); wa_store(code, 0);
    cg_get(f, map); cg_get(f, new_mask); wa_store(code, ww(2));
    cg_end(f);
    cg_get(f, st); wb_byte(code, 0x0b); wb_body(out, locals, code);
}
fn cg_emit_spans_newnode(p: Program&, m: CgModule&, out: u8[>..]&) {
    var events: WbEvent[>..] = [];
    var code: u8[>..] = []; var locals: i64[>..] = []; var slots: CgSlot[>..] = []; var addresses: CgFrameAddress[>..] = [];
    var labels: i64[>..] = []; var exits: CgExit[>..] = []; var results: i64[>..] = []; var destinations: i64[>..] = []; var work: i64[>..] = []; var raw_slots: i64[>..] = []; var sequences: CgSequence[>..] = []; var constructions: CgConstruction[>..] = []; var construction_destinations: CgDestination[>..] = []; var receiving: CgReceiving[>..] = []; var defers: i64[>..] = []; var hoists: CgHoist[>..] = [];
    var f = CgBody { events: events, code: code, locals: locals, slots: slots, addresses: addresses, labels: labels, exits: exits, results: results, destinations: destinations, work: work, raw_slots: raw_slots, sequences: sequences, constructions: constructions, construction_destinations: construction_destinations, receiving: receiving, hoists: hoists, params: 1, defers: defers };
    cg_get(f, 0); wa_load(code, ww(2)); let base = cg_save(f, wa());
    cg_get(f, 0); wa_load(code, ww(3)); let n = cg_save(f, wa());
    cg_get(f, 0); wa_load(code, ww(4)); let cap = cg_save(f, wa());
    cg_get(f, n); wa_truth(code); cg_begin(f, 0x04, 0x40);
    cg_get(f, base); wb_mem(code, 0x29, 3, 16); let chain = cg_save(f, 0x7e);
    cg_get(f, chain); wb_i64(code, 0); wb_byte(code, 0x52); cg_begin(f, 0x04, 0x40);
    cg_get(f, base); cg_sp_node_ptr(f, base, chain); wb_mem(code, 0x29, 3, 8); wb_mem(code, 0x37, 3, 16);
    cg_get(f, chain); wb_byte(code, 0x0f);
    cg_end(f); cg_end(f);
    cg_get(f, n); cg_get(f, cap); wa_op(code, 0x4f); cg_begin(f, 0x04, 0x40);
    wa_const(code, 4); cg_get(f, cap); wa_const(code, 1); wa_op(code, 0x74); cg_get(f, cap); wa_op(code, 0x45); wb_byte(code, 0x1b);
    let new_cap = cg_save(f, wa());
    cg_get(f, new_cap); wa_const(code, 9); wa_op(code, 0x74); wb_op(code, 0x10, m.allocator); let new_base = cg_save(f, wa());
    cg_get(f, n); wa_truth(code); cg_begin(f, 0x04, 0x40);
    cg_get(f, new_base); cg_get(f, base); cg_get(f, n); wa_const(code, 9); wa_op(code, 0x74); wb_copy(code);
    cg_end(f);
    cg_get(f, 0); cg_get(f, new_base); wa_store(code, ww(2));
    cg_get(f, 0); cg_get(f, new_cap); wa_store(code, ww(4));
    cg_get(f, new_base); cg_set(f, base);
    cg_end(f);
    cg_get(f, base); cg_get(f, n); wa_const(code, 9); wa_op(code, 0x74); wa_op(code, 0x6a);
    wb_i32(code, 0); wa_const(code, 512); wb_fill(code);
    cg_get(f, 0); cg_get(f, n); wa_const(code, 1); wa_op(code, 0x6a); wa_store(code, ww(3));
    cg_get(f, n); wa_extend(code); wb_byte(code, 0x0b); wb_body(out, locals, code);
}
fn cg_emit_spans_fix(p: Program&, m: CgModule&, out: u8[>..]&) {
    // Params: 0: state (wa), 1: path (wa), 2: h (i64), 3: l (i64), 4: was (i64), 5: now (i64)
    var events: WbEvent[>..] = [];
    var code: u8[>..] = []; var locals: i64[>..] = []; var slots: CgSlot[>..] = []; var addresses: CgFrameAddress[>..] = [];
    var labels: i64[>..] = []; var exits: CgExit[>..] = []; var results: i64[>..] = []; var destinations: i64[>..] = []; var work: i64[>..] = []; var raw_slots: i64[>..] = []; var sequences: CgSequence[>..] = []; var constructions: CgConstruction[>..] = []; var construction_destinations: CgDestination[>..] = []; var receiving: CgReceiving[>..] = []; var defers: i64[>..] = []; var hoists: CgHoist[>..] = [];
    var f = CgBody { events: events, code: code, locals: locals, slots: slots, addresses: addresses, labels: labels, exits: exits, results: results, destinations: destinations, work: work, raw_slots: raw_slots, sequences: sequences, constructions: constructions, construction_destinations: construction_destinations, receiving: receiving, hoists: hoists, params: 6, defers: defers };
    cg_get(f, 0); wa_load(code, ww(2)); let base = cg_save(f, wa());
    let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
    cg_get(f, 3); wb_i64(code, 0); wb_byte(code, 0x57); cg_branch(p, f, done, true);
    cg_get(f, 3); wb_i64(code, 1); wb_byte(code, 0x7d); let lm1 = cg_save(f, 0x7e);
    cg_sp_load64(f, 1, lm1, 0); let pnode = cg_save(f, 0x7e);
    cg_sp_node_ptr(f, base, pnode); let inn = cg_save(f, wa());
    cg_sp_load64(f, 1, lm1, 192); let k = cg_save(f, 0x7e);
    cg_sp_load64(f, 1, 3, 0); let cnode = cg_save(f, 0x7e);
    cg_sp_node_ptr(f, base, cnode); let cn = cg_save(f, wa());
    cg_sp_load64(f, inn, k, 176); let old_m = cg_save(f, 0x7e);
    cg_get(f, 3); cg_get(f, 2); wb_byte(code, 0x51); let leaf = cg_save(f, 0x7f);
    cg_get(f, cn); wb_mem(code, 0x29, 3, 16); let key = cg_save(f, 0x7e);
    wb_i64(code, 0); let nm = cg_save(f, 0x7e);
    cg_get(f, 5); cg_get(f, old_m); wb_byte(code, 0x59); cg_begin(f, 0x04, 0x40);
    cg_get(f, 5); cg_set(f, nm);
    cg_control(f, 0x05);
    cg_get(f, 4); cg_get(f, old_m); wb_byte(code, 0x53); cg_begin(f, 0x04, 0x40);
    cg_get(f, old_m); cg_set(f, nm);
    cg_control(f, 0x05);
    let scanned = cg_sp_scan_max(p, f, cn, leaf, 4);
    cg_get(f, scanned); cg_set(f, nm);
    cg_end(f); cg_end(f);
    cg_sp_load64(f, inn, k, 16); cg_get(f, key); wb_byte(code, 0x51);
    cg_get(f, nm); cg_get(f, old_m); wb_byte(code, 0x51); wb_byte(code, 0x71);
    cg_branch(p, f, done, true);
    cg_sp_slot_addr(f, inn, k, 16); cg_get(f, key); wb_mem(code, 0x37, 3, 0);
    cg_sp_slot_addr(f, inn, k, 176); cg_get(f, nm); wb_mem(code, 0x37, 3, 0);
    cg_get(f, old_m); cg_set(f, 4);
    cg_get(f, nm); cg_set(f, 5);
    cg_get(f, lm1); cg_set(f, 3);
    cg_branch(p, f, again, false); cg_end(f); cg_end(f);
    wb_byte(code, 0x0b); wb_body(out, locals, code);
}
fn cg_emit_spans_delete(p: Program&, m: CgModule&, out: u8[>..]&) {
    // Params: 0: state (wa), 1: path (wa), 2: h (i64), 3: k (i64)
    var events: WbEvent[>..] = [];
    var code: u8[>..] = []; var locals: i64[>..] = []; var slots: CgSlot[>..] = []; var addresses: CgFrameAddress[>..] = [];
    var labels: i64[>..] = []; var exits: CgExit[>..] = []; var results: i64[>..] = []; var destinations: i64[>..] = []; var work: i64[>..] = []; var raw_slots: i64[>..] = []; var sequences: CgSequence[>..] = []; var constructions: CgConstruction[>..] = []; var construction_destinations: CgDestination[>..] = []; var receiving: CgReceiving[>..] = []; var defers: i64[>..] = []; var hoists: CgHoist[>..] = [];
    var f = CgBody { events: events, code: code, locals: locals, slots: slots, addresses: addresses, labels: labels, exits: exits, results: results, destinations: destinations, work: work, raw_slots: raw_slots, sequences: sequences, constructions: constructions, construction_destinations: construction_destinations, receiving: receiving, hoists: hoists, params: 4, defers: defers };
    cg_get(f, 0); wa_load(code, ww(2)); let base = cg_save(f, wa());
    cg_sp_load64(f, 1, 2, 0); let lf_id = cg_save(f, 0x7e);
    cg_sp_node_ptr(f, base, lf_id); let lf = cg_save(f, wa());
    cg_sp_load64(f, lf, 3, 264); let c = cg_save(f, 0x7e);
    cg_sp_leaf_close(f, lf, 3);
    cg_get(f, lf); wb_mem(code, 0x29, 3, 0); wb_i64(code, 0); wb_byte(code, 0x55);
    cg_get(f, 2); wb_byte(code, 0x50); wb_byte(code, 0x72); cg_begin(f, 0x04, 0x40);
    cg_get(f, 0); cg_get(f, 1); cg_get(f, 2); cg_get(f, 2); cg_get(f, c); wb_i64(code, 0); wb_op(code, 0x10, m.spans_fix);
    wb_byte(code, 0x0f); cg_end(f);
    cg_sp_dropnode(f, base, lf_id);
    cg_get(f, 2); wb_i64(code, 1); wb_byte(code, 0x7d); let l = cg_save(f, 0x7e);
    let ldone = cg_begin(f, 0x02, 0x40); let lagain = cg_begin(f, 0x03, 0x40);
    cg_sp_load64(f, 1, l, 0); let in_id = cg_save(f, 0x7e);
    cg_sp_node_ptr(f, base, in_id); let inn = cg_save(f, wa());
    cg_sp_load64(f, 1, l, 192); let e = cg_save(f, 0x7e);
    cg_sp_load64(f, inn, e, 176); let old_m = cg_save(f, 0x7e);
    cg_sp_inner_close(f, inn, e);
    cg_get(f, inn); wb_mem(code, 0x29, 3, 0); wb_i64(code, 0); wb_byte(code, 0x55); cg_begin(f, 0x04, 0x40);
    cg_get(f, 0); cg_get(f, 1); cg_get(f, 2); cg_get(f, l); cg_get(f, old_m); wb_i64(code, 0); wb_op(code, 0x10, m.spans_fix);
    cg_branch(p, f, ldone, false); cg_end(f);
    cg_sp_dropnode(f, base, in_id);
    cg_get(f, l); wb_i64(code, 1); wb_byte(code, 0x7d); cg_set(f, l);
    cg_branch(p, f, lagain, false); cg_end(f); cg_end(f);
    let rdone = cg_begin(f, 0x02, 0x40); let ragain = cg_begin(f, 0x03, 0x40);
    cg_get(f, base); wb_mem(code, 0x29, 3, 8); wb_i64(code, 0); wb_byte(code, 0x57); cg_branch(p, f, rdone, true);
    cg_get(f, base); wb_mem(code, 0x29, 3, 0); let r = cg_save(f, 0x7e);
    cg_sp_node_ptr(f, base, r); let rn = cg_save(f, wa());
    cg_get(f, rn); wb_mem(code, 0x29, 3, 0); wb_i64(code, 1); wb_byte(code, 0x52); cg_branch(p, f, rdone, true);
    cg_get(f, base); cg_get(f, rn); wb_mem(code, 0x29, 3, 336); wb_mem(code, 0x37, 3, 0);
    cg_get(f, base); cg_get(f, base); wb_mem(code, 0x29, 3, 8); wb_i64(code, 1); wb_byte(code, 0x7d); wb_mem(code, 0x37, 3, 8);
    cg_sp_dropnode(f, base, r);
    cg_branch(p, f, ragain, false); cg_end(f); cg_end(f);
    wb_byte(code, 0x0b); wb_body(out, locals, code);
}
fn cg_emit_spans_insert(p: Program&, m: CgModule&, out: u8[>..]&) {
    // Params: 0: state (wa), 1: path (wa), 2: h (i64), 3: k (i64), 4: idx (i64), 5: cnt (i64)
    var events: WbEvent[>..] = [];
    var code: u8[>..] = []; var locals: i64[>..] = []; var slots: CgSlot[>..] = []; var addresses: CgFrameAddress[>..] = [];
    var labels: i64[>..] = []; var exits: CgExit[>..] = []; var results: i64[>..] = []; var destinations: i64[>..] = []; var work: i64[>..] = []; var raw_slots: i64[>..] = []; var sequences: CgSequence[>..] = []; var constructions: CgConstruction[>..] = []; var construction_destinations: CgDestination[>..] = []; var receiving: CgReceiving[>..] = []; var defers: i64[>..] = []; var hoists: CgHoist[>..] = [];
    var f = CgBody { events: events, code: code, locals: locals, slots: slots, addresses: addresses, labels: labels, exits: exits, results: results, destinations: destinations, work: work, raw_slots: raw_slots, sequences: sequences, constructions: constructions, construction_destinations: construction_destinations, receiving: receiving, hoists: hoists, params: 6, defers: defers };
    cg_get(f, 0); wa_load(code, ww(2)); let base = cg_save(f, wa());
    cg_sp_load64(f, 1, 2, 0); let lf_id = cg_save(f, 0x7e);
    cg_sp_node_ptr(f, base, lf_id); let lf = cg_save(f, wa());
    cg_get(f, lf); let o = cg_save(f, wa());
    cg_get(f, 3); let s = cg_save(f, 0x7e);
    wb_i64(code, 0); let nn = cg_save(f, 0x7e);
    cg_get(f, lf); wb_mem(code, 0x29, 3, 0); wb_i64(code, 31); wb_byte(code, 0x51); cg_begin(f, 0x04, 0x40);
    cg_get(f, 0); wb_op(code, 0x10, m.spans_newnode); cg_set(f, nn);
    cg_get(f, 0); wa_load(code, ww(2)); cg_set(f, base);
    cg_sp_node_ptr(f, base, lf_id); cg_set(f, lf); cg_get(f, lf); cg_set(f, o);
    cg_sp_node_ptr(f, base, nn); let rlf = cg_save(f, wa());
    cg_get(f, rlf); wb_i64(code, 16); wb_mem(code, 0x37, 3, 0);
    cg_get(f, rlf); wa_add(code, 16); cg_get(f, lf); wa_add(code, 16 + 15 * 8); wa_const(code, 16 * 8); wb_copy(code);
    cg_get(f, rlf); wa_add(code, 264); cg_get(f, lf); wa_add(code, 264 + 15 * 8); wa_const(code, 16 * 8); wb_copy(code);
    cg_get(f, lf); wb_i64(code, 15); wb_mem(code, 0x37, 3, 0);
    cg_get(f, 3); wb_i64(code, 15); wb_byte(code, 0x55); cg_begin(f, 0x04, 0x40);
    cg_get(f, rlf); cg_set(f, o);
    cg_get(f, 3); wb_i64(code, 15); wb_byte(code, 0x7d); cg_set(f, s);
    cg_end(f); cg_end(f);
    cg_get(f, o); wb_mem(code, 0x29, 3, 0); let on = cg_save(f, 0x7e);
    cg_sp_open_arr(f, o, on, s, 16);
    cg_sp_open_arr(f, o, on, s, 264);
    cg_get(f, o); cg_get(f, on); wb_i64(code, 1); wb_byte(code, 0x7c); wb_mem(code, 0x37, 3, 0);
    cg_sp_slot_addr(f, o, s, 16); cg_get(f, 4); wb_mem(code, 0x37, 3, 0);
    cg_sp_slot_addr(f, o, s, 264); cg_get(f, 5); wb_mem(code, 0x37, 3, 0);
    cg_get(f, nn); wb_byte(code, 0x50); cg_begin(f, 0x04, 0x40);
    cg_get(f, 0); cg_get(f, 1); cg_get(f, 2); cg_get(f, 2); wb_i64(code, 0); cg_get(f, 5); wb_op(code, 0x10, m.spans_fix);
    wb_byte(code, 0x0f); cg_end(f);
    cg_get(f, 2); wb_byte(code, 0x50); cg_begin(f, 0x04, 0x40);
    cg_get(f, 1); wb_mem(code, 0x29, 3, 0); let a0 = cg_save(f, 0x7e);
    wb_i32(code, 1); let one32 = cg_save(f, 0x7f);
    cg_sp_emit_newroot(p, m, f, 0, a0, nn, one32);
    wb_byte(code, 0x0f); cg_end(f);
    cg_get(f, 0); cg_get(f, 1); cg_get(f, 2); cg_get(f, 2); wb_i64(code, 9223372036854775807); wb_i64(code, 0); wb_op(code, 0x10, m.spans_fix);
    // addchild loop
    cg_get(f, 2); wb_i64(code, 1); wb_byte(code, 0x7d); let l = cg_save(f, 0x7e);
    cg_sp_load64(f, 1, l, 192); wb_i64(code, 1); wb_byte(code, 0x7c); let kin = cg_save(f, 0x7e);
    cg_get(f, nn); let child = cg_save(f, 0x7e);
    wb_i32(code, 1); let leaf = cg_save(f, 0x7f);
    wb_i64(code, 9223372036854775807); let big = cg_save(f, 0x7e);
    let adone = cg_begin(f, 0x02, 0x40); let aagain = cg_begin(f, 0x03, 0x40);
    cg_get(f, 0); wa_load(code, ww(2)); cg_set(f, base);
    cg_sp_load64(f, 1, l, 0); let in_id = cg_save(f, 0x7e);
    cg_sp_node_ptr(f, base, in_id); let inn = cg_save(f, wa());
    cg_sp_node_ptr(f, base, child); let chn = cg_save(f, wa());
    cg_get(f, chn); wb_mem(code, 0x29, 3, 16); let ckey = cg_save(f, 0x7e);
    let cmax = cg_sp_scan_max(p, f, chn, leaf, big);
    cg_get(f, inn); let oi = cg_save(f, wa());
    cg_get(f, kin); let si = cg_save(f, 0x7e);
    wb_i64(code, 0); let nni = cg_save(f, 0x7e);
    cg_get(f, inn); wb_mem(code, 0x29, 3, 0); wb_i64(code, 20); wb_byte(code, 0x51); cg_begin(f, 0x04, 0x40);
    cg_get(f, 0); wb_op(code, 0x10, m.spans_newnode); cg_set(f, nni);
    cg_get(f, 0); wa_load(code, ww(2)); cg_set(f, base);
    cg_sp_node_ptr(f, base, in_id); cg_set(f, inn); cg_get(f, inn); cg_set(f, oi);
    cg_sp_node_ptr(f, base, nni); let rin = cg_save(f, wa());
    cg_get(f, rin); wb_i64(code, 10); wb_mem(code, 0x37, 3, 0);
    cg_get(f, rin); wa_add(code, 16); cg_get(f, inn); wa_add(code, 16 + 10 * 8); wa_const(code, 10 * 8); wb_copy(code);
    cg_get(f, rin); wa_add(code, 176); cg_get(f, inn); wa_add(code, 176 + 10 * 8); wa_const(code, 10 * 8); wb_copy(code);
    cg_get(f, rin); wa_add(code, 336); cg_get(f, inn); wa_add(code, 336 + 10 * 8); wa_const(code, 10 * 8); wb_copy(code);
    cg_get(f, inn); wb_i64(code, 10); wb_mem(code, 0x37, 3, 0);
    cg_get(f, kin); wb_i64(code, 10); wb_byte(code, 0x55); cg_begin(f, 0x04, 0x40);
    cg_get(f, rin); cg_set(f, oi);
    cg_get(f, kin); wb_i64(code, 10); wb_byte(code, 0x7d); cg_set(f, si);
    cg_end(f); cg_end(f);
    cg_get(f, oi); wb_mem(code, 0x29, 3, 0); let oin = cg_save(f, 0x7e);
    cg_sp_open_arr(f, oi, oin, si, 16);
    cg_sp_open_arr(f, oi, oin, si, 176);
    cg_sp_open_arr(f, oi, oin, si, 336);
    cg_get(f, oi); cg_get(f, oin); wb_i64(code, 1); wb_byte(code, 0x7c); wb_mem(code, 0x37, 3, 0);
    cg_sp_slot_addr(f, oi, si, 16); cg_get(f, ckey); wb_mem(code, 0x37, 3, 0);
    cg_sp_slot_addr(f, oi, si, 176); cg_get(f, cmax); wb_mem(code, 0x37, 3, 0);
    cg_sp_slot_addr(f, oi, si, 336); cg_get(f, child); wb_mem(code, 0x37, 3, 0);
    cg_get(f, nni); wb_byte(code, 0x50); cg_begin(f, 0x04, 0x40);
    cg_get(f, 0); cg_get(f, 1); cg_get(f, 2); cg_get(f, l); wb_i64(code, 0); cg_get(f, cmax); wb_op(code, 0x10, m.spans_fix);
    cg_branch(p, f, adone, false); cg_end(f);
    cg_get(f, l); wb_byte(code, 0x50); cg_begin(f, 0x04, 0x40);
    cg_get(f, 1); wb_mem(code, 0x29, 3, 0); let r0 = cg_save(f, 0x7e);
    wb_i32(code, 0); let z32 = cg_save(f, 0x7f);
    cg_sp_emit_newroot(p, m, f, 0, r0, nni, z32);
    cg_branch(p, f, adone, false); cg_end(f);
    cg_get(f, 0); cg_get(f, 1); cg_get(f, 2); cg_get(f, l); cg_get(f, big); wb_i64(code, 0); wb_op(code, 0x10, m.spans_fix);
    cg_get(f, nni); cg_set(f, child);
    wb_i32(code, 0); cg_set(f, leaf);
    cg_get(f, l); wb_i64(code, 1); wb_byte(code, 0x7d); cg_set(f, l);
    cg_sp_load64(f, 1, l, 192); wb_i64(code, 1); wb_byte(code, 0x7c); cg_set(f, kin);
    cg_branch(p, f, aagain, false); cg_end(f); cg_end(f);
    wb_byte(code, 0x0b); wb_body(out, locals, code);
}
fn cg_emit_spans_near(p: Program&, m: CgModule&, out: u8[>..]&) {
    // Params: 0: state (wa), 1: idx (i64), 2: end (i64)
    var events: WbEvent[>..] = [];
    var code: u8[>..] = []; var locals: i64[>..] = []; var slots: CgSlot[>..] = []; var addresses: CgFrameAddress[>..] = [];
    var labels: i64[>..] = []; var exits: CgExit[>..] = []; var results: i64[>..] = []; var destinations: i64[>..] = []; var work: i64[>..] = []; var raw_slots: i64[>..] = []; var sequences: CgSequence[>..] = []; var constructions: CgConstruction[>..] = []; var construction_destinations: CgDestination[>..] = []; var receiving: CgReceiving[>..] = []; var defers: i64[>..] = []; var hoists: CgHoist[>..] = [];
    var f = CgBody { events: events, code: code, locals: locals, slots: slots, addresses: addresses, labels: labels, exits: exits, results: results, destinations: destinations, work: work, raw_slots: raw_slots, sequences: sequences, constructions: constructions, construction_destinations: construction_destinations, receiving: receiving, hoists: hoists, params: 3, defers: defers };
    let sc = m.span_scratch;
    wa_const(code, sc); let pnode = cg_save(f, wa());
    wa_const(code, sc + 384); let qnode = cg_save(f, wa());
    cg_get(f, 0); wa_load(code, ww(2)); let base = cg_save(f, wa());
    cg_get(f, base); wb_mem(code, 0x29, 3, 8); let h = cg_save(f, 0x7e);
    cg_get(f, base); wb_mem(code, 0x29, 3, 0); let i = cg_save(f, 0x7e);
    wb_i64(code, 0); let l = cg_save(f, 0x7e);
    let ddone = cg_begin(f, 0x02, 0x40); let dagain = cg_begin(f, 0x03, 0x40);
    cg_get(f, l); cg_get(f, h); wb_byte(code, 0x59); cg_branch(p, f, ddone, true);
    cg_sp_node_ptr(f, base, i); let inn = cg_save(f, wa());
    cg_get(f, inn); wb_mem(code, 0x29, 3, 0); let in_n = cg_save(f, 0x7e);
    wb_i64(code, 1); let k = cg_save(f, 0x7e);
    let kdone = cg_begin(f, 0x02, 0x40); let kagain = cg_begin(f, 0x03, 0x40);
    cg_get(f, k); cg_get(f, in_n); wb_byte(code, 0x59); cg_branch(p, f, kdone, true);
    cg_sp_load64(f, inn, k, 16); cg_get(f, 1); wb_byte(code, 0x55); cg_branch(p, f, kdone, true);
    cg_get(f, k); wb_i64(code, 1); wb_byte(code, 0x7c); cg_set(f, k);
    cg_branch(p, f, kagain, false); cg_end(f); cg_end(f);
    cg_get(f, k); wb_i64(code, 1); wb_byte(code, 0x7d); let km1 = cg_save(f, 0x7e);
    cg_sp_slot_addr(f, pnode, l, 0); cg_get(f, i); wb_mem(code, 0x37, 3, 0);
    cg_sp_slot_addr(f, pnode, l, 192); cg_get(f, km1); wb_mem(code, 0x37, 3, 0);
    cg_sp_load64(f, inn, km1, 336); cg_set(f, i);
    cg_get(f, l); wb_i64(code, 1); wb_byte(code, 0x7c); cg_set(f, l);
    cg_branch(p, f, dagain, false); cg_end(f); cg_end(f);
    cg_sp_slot_addr(f, pnode, h, 0); cg_get(f, i); wb_mem(code, 0x37, 3, 0);
    cg_sp_node_ptr(f, base, i); let lf = cg_save(f, wa());
    cg_get(f, lf); wb_mem(code, 0x29, 3, 0); let lf_n = cg_save(f, 0x7e);
    wb_i64(code, 0); let lk = cg_save(f, 0x7e);
    let ldone = cg_begin(f, 0x02, 0x40); let lagain = cg_begin(f, 0x03, 0x40);
    cg_get(f, lk); cg_get(f, lf_n); wb_byte(code, 0x59); cg_branch(p, f, ldone, true);
    cg_sp_load64(f, lf, lk, 16); cg_get(f, 1); wb_byte(code, 0x55); cg_branch(p, f, ldone, true);
    cg_get(f, lk); wb_i64(code, 1); wb_byte(code, 0x7c); cg_set(f, lk);
    cg_branch(p, f, lagain, false); cg_end(f); cg_end(f);
    cg_get(f, lk); wb_i64(code, 1); wb_byte(code, 0x7d); let sk = cg_save(f, 0x7e);
    cg_sp_slot_addr(f, pnode, h, 192); cg_get(f, sk); wb_mem(code, 0x37, 3, 0);
    wa_const(code, sc + 960); cg_get(f, sk); wb_mem(code, 0x37, 3, 0);
    wa_const(code, sc + 968); wb_i64(code, -1); wb_mem(code, 0x37, 3, 0);
    wa_const(code, sc + 976); wb_i64(code, 0); wb_mem(code, 0x37, 3, 0);
    wa_const(code, sc + 984); cg_get(f, h); wb_mem(code, 0x37, 3, 0);
    cg_get(f, sk); wb_i64(code, 1); wb_byte(code, 0x7c); cg_get(f, lf_n); wb_byte(code, 0x53); cg_begin(f, 0x04, 0x40);
    wa_const(code, sc + 968); cg_get(f, sk); wb_i64(code, 1); wb_byte(code, 0x7c); wb_mem(code, 0x37, 3, 0);
    wa_const(code, sc + 976); wb_i64(code, 1); wb_mem(code, 0x37, 3, 0);
    wb_byte(code, 0x0f); cg_end(f);
    cg_get(f, h); wb_i64(code, 1); wb_byte(code, 0x7d); cg_set(f, l);
    let udone = cg_begin(f, 0x02, 0x40); let uagain = cg_begin(f, 0x03, 0x40);
    cg_get(f, l); wb_i64(code, 0); wb_byte(code, 0x53); cg_branch(p, f, udone, true);
    cg_sp_load64(f, pnode, l, 0); let up_id = cg_save(f, 0x7e);
    cg_sp_node_ptr(f, base, up_id); let up_in = cg_save(f, wa());
    cg_sp_load64(f, pnode, l, 192); wb_i64(code, 1); wb_byte(code, 0x7c);
    cg_get(f, up_in); wb_mem(code, 0x29, 3, 0); wb_byte(code, 0x53); cg_branch(p, f, udone, true);
    cg_get(f, l); wb_i64(code, 1); wb_byte(code, 0x7d); cg_set(f, l);
    cg_branch(p, f, uagain, false); cg_end(f); cg_end(f);
    cg_get(f, l); wb_i64(code, 0); wb_byte(code, 0x53); cg_begin(f, 0x04, 0x40); wb_byte(code, 0x0f); cg_end(f);
    cg_sp_load64(f, pnode, l, 0); let top_id = cg_save(f, 0x7e);
    cg_sp_node_ptr(f, base, top_id); let top_in = cg_save(f, wa());
    cg_sp_load64(f, pnode, l, 192); wb_i64(code, 1); wb_byte(code, 0x7c); let top_next = cg_save(f, 0x7e);
    cg_sp_load64(f, top_in, top_next, 16); cg_get(f, 2); wb_byte(code, 0x52); cg_begin(f, 0x04, 0x40); wb_byte(code, 0x0f); cg_end(f);
    cg_get(f, l); wb_i64(code, 1); wb_byte(code, 0x7c); wb_i64(code, 3); wb_byte(code, 0x86); wa_wrap(code); let cp_bytes = cg_save(f, wa());
    cg_get(f, qnode); cg_get(f, pnode); cg_get(f, cp_bytes); wb_copy(code);
    cg_get(f, qnode); wa_add(code, 192); cg_get(f, pnode); wa_add(code, 192); cg_get(f, cp_bytes); wb_copy(code);
    cg_sp_slot_addr(f, qnode, l, 192); cg_get(f, top_next); wb_mem(code, 0x37, 3, 0);
    let qdone = cg_begin(f, 0x02, 0x40); let qagain = cg_begin(f, 0x03, 0x40);
    cg_get(f, l); cg_get(f, h); wb_byte(code, 0x59); cg_branch(p, f, qdone, true);
    cg_sp_load64(f, qnode, l, 0); let qid = cg_save(f, 0x7e);
    cg_sp_node_ptr(f, base, qid); let qin = cg_save(f, wa());
    cg_sp_load64(f, qnode, l, 192); let qpos = cg_save(f, 0x7e);
    cg_sp_load64(f, qin, qpos, 336); let qch = cg_save(f, 0x7e);
    cg_get(f, l); wb_i64(code, 1); wb_byte(code, 0x7c); cg_set(f, l);
    cg_sp_slot_addr(f, qnode, l, 0); cg_get(f, qch); wb_mem(code, 0x37, 3, 0);
    cg_sp_slot_addr(f, qnode, l, 192); wb_i64(code, 0); wb_mem(code, 0x37, 3, 0);
    cg_branch(p, f, qagain, false); cg_end(f); cg_end(f);
    wa_const(code, sc + 968); wb_i64(code, 0); wb_mem(code, 0x37, 3, 0);
    wa_const(code, sc + 976); wb_i64(code, 2); wb_mem(code, 0x37, 3, 0);
    wb_byte(code, 0x0b); wb_body(out, locals, code);
}
fn cg_emit_spans_release(p: Program&, m: CgModule&, out: u8[>..]&) {
    // Params: 0: state (wa), 1: idx (i64), 2: cnt (i64)
    var events: WbEvent[>..] = [];
    var code: u8[>..] = []; var locals: i64[>..] = []; var slots: CgSlot[>..] = []; var addresses: CgFrameAddress[>..] = [];
    var labels: i64[>..] = []; var exits: CgExit[>..] = []; var results: i64[>..] = []; var destinations: i64[>..] = []; var work: i64[>..] = []; var raw_slots: i64[>..] = []; var sequences: CgSequence[>..] = []; var constructions: CgConstruction[>..] = []; var construction_destinations: CgDestination[>..] = []; var receiving: CgReceiving[>..] = []; var defers: i64[>..] = []; var hoists: CgHoist[>..] = [];
    var f = CgBody { events: events, code: code, locals: locals, slots: slots, addresses: addresses, labels: labels, exits: exits, results: results, destinations: destinations, work: work, raw_slots: raw_slots, sequences: sequences, constructions: constructions, construction_destinations: construction_destinations, receiving: receiving, hoists: hoists, params: 3, defers: defers };
    let sc = m.span_scratch;
    wa_const(code, sc); let pnode = cg_save(f, wa());
    wa_const(code, sc + 384); let qnode = cg_save(f, wa());
    cg_get(f, 0); wa_load(code, ww(2)); let base = cg_save(f, wa());
    wa_const(code, sc + 960); wb_mem(code, 0x29, 3, 0); let k = cg_save(f, 0x7e);
    wa_const(code, sc + 968); wb_mem(code, 0x29, 3, 0); let nk = cg_save(f, 0x7e);
    wa_const(code, sc + 976); wb_mem(code, 0x29, 3, 0); let kind = cg_save(f, 0x7e);
    wa_const(code, sc + 984); wb_mem(code, 0x29, 3, 0); let h = cg_save(f, 0x7e);
    cg_sp_load64(f, pnode, h, 0); let lf_id = cg_save(f, 0x7e);
    cg_sp_node_ptr(f, base, lf_id); let lf = cg_save(f, wa());
    cg_get(f, qnode); cg_get(f, pnode); cg_get(f, kind); wb_i64(code, 2); wb_byte(code, 0x51); wb_byte(code, 0x1b);
    let nl_path = cg_save(f, wa());
    wa_const(code, 0); let nl = cg_save(f, wa());
    wb_i32(code, 0); let prev = cg_save(f, 0x7f);
    wb_i32(code, 0); let next = cg_save(f, 0x7f);
    cg_get(f, k); wb_i64(code, 0); wb_byte(code, 0x59); cg_begin(f, 0x04, 0x40);
    cg_sp_load64(f, lf, k, 16); cg_sp_load64(f, lf, k, 264); wb_byte(code, 0x7c); cg_get(f, 1); wb_byte(code, 0x51); cg_set(f, prev);
    cg_end(f);
    cg_get(f, kind); wb_i64(code, 0); wb_byte(code, 0x52); cg_begin(f, 0x04, 0x40);
    cg_sp_load64(f, nl_path, h, 0); let nl_id = cg_save(f, 0x7e);
    cg_sp_node_ptr(f, base, nl_id); cg_set(f, nl);
    cg_get(f, 1); cg_get(f, 2); wb_byte(code, 0x7c); cg_sp_load64(f, nl, nk, 16); wb_byte(code, 0x51); cg_set(f, next);
    cg_end(f);
    cg_get(f, prev); cg_begin(f, 0x04, 0x40);
    cg_sp_load64(f, lf, k, 264); let c = cg_save(f, 0x7e);
    cg_get(f, c); cg_get(f, 2); wb_byte(code, 0x7c); let merged = cg_save(f, 0x7e);
    cg_get(f, next); cg_begin(f, 0x04, 0x40);
    cg_get(f, merged); cg_sp_load64(f, nl, nk, 264); wb_byte(code, 0x7c); cg_set(f, merged);
    cg_end(f);
    cg_sp_slot_addr(f, lf, k, 264); cg_get(f, merged); wb_mem(code, 0x37, 3, 0);
    cg_get(f, next); cg_get(f, kind); wb_i64(code, 1); wb_byte(code, 0x51); wb_byte(code, 0x71); cg_begin(f, 0x04, 0x40);
    cg_sp_leaf_close(f, lf, nk); cg_end(f);
    cg_get(f, 0); cg_get(f, pnode); cg_get(f, h); cg_get(f, h); cg_get(f, c); cg_get(f, merged); wb_op(code, 0x10, m.spans_fix);
    cg_get(f, next); cg_get(f, kind); wb_i64(code, 2); wb_byte(code, 0x51); wb_byte(code, 0x71); cg_begin(f, 0x04, 0x40);
    cg_get(f, 0); cg_get(f, qnode); cg_get(f, h); cg_get(f, nk); wb_op(code, 0x10, m.spans_delete); cg_end(f);
    cg_control(f, 0x05);
    cg_get(f, next); cg_begin(f, 0x04, 0x40);
    cg_sp_load64(f, nl, nk, 264); let nc = cg_save(f, 0x7e);
    cg_get(f, nc); cg_get(f, 2); wb_byte(code, 0x7c); let nsum = cg_save(f, 0x7e);
    cg_sp_slot_addr(f, nl, nk, 16); cg_get(f, 1); wb_mem(code, 0x37, 3, 0);
    cg_sp_slot_addr(f, nl, nk, 264); cg_get(f, nsum); wb_mem(code, 0x37, 3, 0);
    cg_get(f, 0); cg_get(f, nl_path); cg_get(f, h); cg_get(f, h); cg_get(f, nc); cg_get(f, nsum); wb_op(code, 0x10, m.spans_fix);
    cg_control(f, 0x05);
    cg_get(f, 0); cg_get(f, pnode); cg_get(f, h); cg_get(f, k); wb_i64(code, 1); wb_byte(code, 0x7c); cg_get(f, 1); cg_get(f, 2); wb_op(code, 0x10, m.spans_insert);
    cg_end(f); cg_end(f);
    wb_byte(code, 0x0b); wb_body(out, locals, code);
}
fn cg_emit_spans_alloc(p: Program&, m: CgModule&, out: u8[>..]&) {
    // Params: 0: state (wa), 1: len (i64), 2: cnt (i64) -> i64
    var events: WbEvent[>..] = [];
    var code: u8[>..] = []; var locals: i64[>..] = []; var slots: CgSlot[>..] = []; var addresses: CgFrameAddress[>..] = [];
    var labels: i64[>..] = []; var exits: CgExit[>..] = []; var results: i64[>..] = []; var destinations: i64[>..] = []; var work: i64[>..] = []; var raw_slots: i64[>..] = []; var sequences: CgSequence[>..] = []; var constructions: CgConstruction[>..] = []; var construction_destinations: CgDestination[>..] = []; var receiving: CgReceiving[>..] = []; var defers: i64[>..] = []; var hoists: CgHoist[>..] = [];
    var f = CgBody { events: events, code: code, locals: locals, slots: slots, addresses: addresses, labels: labels, exits: exits, results: results, destinations: destinations, work: work, raw_slots: raw_slots, sequences: sequences, constructions: constructions, construction_destinations: construction_destinations, receiving: receiving, hoists: hoists, params: 3, defers: defers };
    cg_get(f, 2); wb_byte(code, 0x50);
    cg_get(f, 0); wa_load(code, ww(3)); wa_op(code, 0x45); wb_byte(code, 0x72);
    cg_begin(f, 0x04, 0x40); cg_get(f, 1); wb_byte(code, 0x0f); cg_end(f);
    let sc = m.span_scratch;
    wa_const(code, sc); let pnode = cg_save(f, wa());
    wa_const(code, sc + 768); let before = cg_save(f, wa());
    cg_get(f, 0); wa_load(code, ww(2)); let base = cg_save(f, wa());
    cg_get(f, base); wb_mem(code, 0x29, 3, 8); let h = cg_save(f, 0x7e);
    cg_get(f, base); wb_mem(code, 0x29, 3, 0); let i = cg_save(f, 0x7e);
    wb_i64(code, 0); let l = cg_save(f, 0x7e);
    wb_i64(code, 0); let k = cg_save(f, 0x7e);
    wa_const(code, 0); let lf = cg_save(f, wa());
    wb_i32(code, 0); let found = cg_save(f, 0x7f);
    let ddone = cg_begin(f, 0x02, 0x40); let dagain = cg_begin(f, 0x03, 0x40);
    cg_get(f, l); cg_get(f, h); wb_byte(code, 0x59); cg_branch(p, f, ddone, true);
    cg_sp_node_ptr(f, base, i); let inn = cg_save(f, wa());
    cg_get(f, inn); wb_mem(code, 0x29, 3, 0); let in_n = cg_save(f, 0x7e);
    wb_i64(code, 0); cg_set(f, k);
    wb_i64(code, 0); let mx = cg_save(f, 0x7e);
    let kdone = cg_begin(f, 0x02, 0x40); let kagain = cg_begin(f, 0x03, 0x40);
    cg_get(f, k); cg_get(f, in_n); wb_byte(code, 0x59); cg_branch(p, f, kdone, true);
    cg_sp_load64(f, inn, k, 176); let mv = cg_save(f, 0x7e);
    cg_get(f, mv); cg_get(f, 2); wb_byte(code, 0x59); cg_branch(p, f, kdone, true);
    cg_get(f, mv); cg_get(f, mx); wb_byte(code, 0x55); cg_begin(f, 0x04, 0x40); cg_get(f, mv); cg_set(f, mx); cg_end(f);
    cg_get(f, k); wb_i64(code, 1); wb_byte(code, 0x7c); cg_set(f, k);
    cg_branch(p, f, kagain, false); cg_end(f); cg_end(f);
    cg_get(f, k); cg_get(f, in_n); wb_byte(code, 0x51); cg_branch(p, f, ddone, true);
    cg_sp_slot_addr(f, pnode, l, 0); cg_get(f, i); wb_mem(code, 0x37, 3, 0);
    cg_sp_slot_addr(f, pnode, l, 192); cg_get(f, k); wb_mem(code, 0x37, 3, 0);
    cg_sp_slot_addr(f, before, l, 0); cg_get(f, mx); wb_mem(code, 0x37, 3, 0);
    cg_sp_load64(f, inn, k, 336); cg_set(f, i);
    cg_get(f, l); wb_i64(code, 1); wb_byte(code, 0x7c); cg_set(f, l);
    cg_branch(p, f, dagain, false); cg_end(f); cg_end(f);
    cg_get(f, l); cg_get(f, h); wb_byte(code, 0x51); cg_begin(f, 0x04, 0x40);
    cg_sp_node_ptr(f, base, i); cg_set(f, lf);
    cg_get(f, lf); wb_mem(code, 0x29, 3, 0); let lf_n = cg_save(f, 0x7e);
    wb_i64(code, 0); cg_set(f, k);
    wb_i64(code, 0); let lmx = cg_save(f, 0x7e);
    let ldone = cg_begin(f, 0x02, 0x40); let lagain = cg_begin(f, 0x03, 0x40);
    cg_get(f, k); cg_get(f, lf_n); wb_byte(code, 0x59); cg_branch(p, f, ldone, true);
    cg_sp_load64(f, lf, k, 264); let cv = cg_save(f, 0x7e);
    cg_get(f, cv); cg_get(f, 2); wb_byte(code, 0x59); cg_branch(p, f, ldone, true);
    cg_get(f, cv); cg_get(f, lmx); wb_byte(code, 0x55); cg_begin(f, 0x04, 0x40); cg_get(f, cv); cg_set(f, lmx); cg_end(f);
    cg_get(f, k); wb_i64(code, 1); wb_byte(code, 0x7c); cg_set(f, k);
    cg_branch(p, f, lagain, false); cg_end(f); cg_end(f);
    cg_sp_slot_addr(f, before, h, 0); cg_get(f, lmx); wb_mem(code, 0x37, 3, 0);
    cg_get(f, k); cg_get(f, lf_n); wb_byte(code, 0x53); cg_set(f, found);
    cg_end(f);
    cg_get(f, found); wb_byte(code, 0x45); cg_begin(f, 0x04, 0x40);
    wb_i64(code, 0); cg_set(f, l);
    cg_get(f, base); wb_mem(code, 0x29, 3, 0); cg_set(f, i);
    let tdone = cg_begin(f, 0x02, 0x40); let tagain = cg_begin(f, 0x03, 0x40);
    cg_get(f, l); cg_get(f, h); wb_byte(code, 0x59); cg_branch(p, f, tdone, true);
    cg_sp_node_ptr(f, base, i); let tin = cg_save(f, wa());
    cg_get(f, tin); wb_mem(code, 0x29, 3, 0); wb_i64(code, 1); wb_byte(code, 0x7d); let last = cg_save(f, 0x7e);
    cg_sp_slot_addr(f, pnode, l, 0); cg_get(f, i); wb_mem(code, 0x37, 3, 0);
    cg_sp_slot_addr(f, pnode, l, 192); cg_get(f, last); wb_mem(code, 0x37, 3, 0);
    cg_sp_load64(f, tin, last, 336); cg_set(f, i);
    cg_get(f, l); wb_i64(code, 1); wb_byte(code, 0x7c); cg_set(f, l);
    cg_branch(p, f, tagain, false); cg_end(f); cg_end(f);
    cg_sp_slot_addr(f, pnode, h, 0); cg_get(f, i); wb_mem(code, 0x37, 3, 0);
    cg_sp_node_ptr(f, base, i); cg_set(f, lf);
    cg_get(f, lf); wb_mem(code, 0x29, 3, 0); wb_i64(code, 1); wb_byte(code, 0x7d); cg_set(f, k);
    cg_get(f, k); wb_i64(code, 0); wb_byte(code, 0x53); cg_begin(f, 0x04, 0x40); cg_get(f, 1); wb_byte(code, 0x0f); cg_end(f);
    cg_sp_load64(f, lf, k, 16); let tidx = cg_save(f, 0x7e);
    cg_sp_load64(f, lf, k, 264); let tcnt = cg_save(f, 0x7e);
    cg_get(f, tidx); cg_get(f, tcnt); wb_byte(code, 0x7c); cg_get(f, 1); wb_byte(code, 0x52);
    cg_begin(f, 0x04, 0x40); cg_get(f, 1); wb_byte(code, 0x0f); cg_end(f);
    cg_get(f, tcnt); cg_get(f, 2); wb_byte(code, 0x57); cg_begin(f, 0x04, 0x40);
    cg_get(f, 0); cg_get(f, pnode); cg_get(f, h); cg_get(f, k); wb_op(code, 0x10, m.spans_delete);
    cg_control(f, 0x05);
    cg_sp_slot_addr(f, lf, k, 16); cg_get(f, tidx); cg_get(f, 2); wb_byte(code, 0x7c); wb_mem(code, 0x37, 3, 0);
    cg_get(f, tcnt); cg_get(f, 2); wb_byte(code, 0x7d); let trem = cg_save(f, 0x7e);
    cg_sp_slot_addr(f, lf, k, 264); cg_get(f, trem); wb_mem(code, 0x37, 3, 0);
    cg_get(f, 0); cg_get(f, pnode); cg_get(f, h); cg_get(f, h); cg_get(f, tcnt); cg_get(f, trem); wb_op(code, 0x10, m.spans_fix);
    cg_end(f);
    cg_get(f, tidx); wb_byte(code, 0x0f); cg_end(f);
    cg_sp_slot_addr(f, pnode, h, 0); cg_get(f, i); wb_mem(code, 0x37, 3, 0);
    cg_sp_slot_addr(f, pnode, h, 192); cg_get(f, k); wb_mem(code, 0x37, 3, 0);
    cg_sp_load64(f, lf, k, 16); let idx = cg_save(f, 0x7e);
    cg_sp_load64(f, lf, k, 264); let c = cg_save(f, 0x7e);
    wb_i64(code, 0); let now = cg_save(f, 0x7e);
    wb_i64(code, 0); let j = cg_save(f, 0x7e);
    cg_get(f, c); cg_get(f, 2); wb_byte(code, 0x55); cg_begin(f, 0x04, 0x40);
    cg_sp_slot_addr(f, lf, k, 16); cg_get(f, idx); cg_get(f, 2); wb_byte(code, 0x7c); wb_mem(code, 0x37, 3, 0);
    cg_get(f, c); cg_get(f, 2); wb_byte(code, 0x7d); cg_set(f, now);
    cg_sp_slot_addr(f, lf, k, 264); cg_get(f, now); wb_mem(code, 0x37, 3, 0);
    cg_get(f, k); wb_i64(code, 1); wb_byte(code, 0x7c); cg_set(f, j);
    cg_control(f, 0x05);
    cg_get(f, lf); wb_mem(code, 0x29, 3, 0); wb_i64(code, 1); wb_byte(code, 0x55);
    cg_get(f, h); wb_byte(code, 0x50); wb_byte(code, 0x72); cg_begin(f, 0x04, 0x40);
    cg_sp_leaf_close(f, lf, k);
    wb_i64(code, 0); cg_set(f, now);
    cg_get(f, k); cg_set(f, j);
    cg_control(f, 0x05);
    cg_get(f, 0); cg_get(f, pnode); cg_get(f, h); cg_get(f, k); wb_op(code, 0x10, m.spans_delete);
    cg_get(f, idx); wb_byte(code, 0x0f);
    cg_end(f); cg_end(f);
    cg_get(f, h); cg_set(f, l);
    let fdone = cg_begin(f, 0x02, 0x40); let fagain = cg_begin(f, 0x03, 0x40);
    cg_get(f, l); wb_i64(code, 0); wb_byte(code, 0x57); cg_branch(p, f, fdone, true);
    cg_get(f, l); wb_i64(code, 1); wb_byte(code, 0x7d); let lm1 = cg_save(f, 0x7e);
    cg_sp_load64(f, pnode, lm1, 0); let pin_id = cg_save(f, 0x7e);
    cg_sp_node_ptr(f, base, pin_id); let pin = cg_save(f, wa());
    cg_sp_load64(f, pnode, lm1, 192); let e = cg_save(f, 0x7e);
    cg_sp_load64(f, pin, e, 176); let mx2 = cg_save(f, 0x7e);
    cg_get(f, mx2); let nm = cg_save(f, 0x7e);
    cg_sp_load64(f, pnode, l, 0); let ch_id = cg_save(f, 0x7e);
    cg_sp_node_ptr(f, base, ch_id); let chn = cg_save(f, wa());
    cg_get(f, chn); wb_mem(code, 0x29, 3, 16); let key = cg_save(f, 0x7e);
    cg_get(f, c); cg_get(f, mx2); wb_byte(code, 0x51); cg_begin(f, 0x04, 0x40);
    cg_get(f, chn); wa_const(code, 264); wa_const(code, 176); cg_get(f, l); cg_get(f, h); wb_byte(code, 0x51); wb_byte(code, 0x1b); wa_op(code, 0x6a);
    let varr = cg_save(f, wa());
    cg_get(f, chn); wb_mem(code, 0x29, 3, 0); let w = cg_save(f, 0x7e);
    cg_sp_load64(f, before, l, 0); let bf = cg_save(f, 0x7e);
    cg_get(f, bf); cg_get(f, now); cg_get(f, bf); cg_get(f, now); wb_byte(code, 0x55); wb_byte(code, 0x1b); cg_set(f, nm);
    let sdone = cg_begin(f, 0x02, 0x40); let sagain = cg_begin(f, 0x03, 0x40);
    cg_get(f, j); cg_get(f, w); wb_byte(code, 0x59);
    cg_get(f, nm); cg_get(f, c); wb_byte(code, 0x59); wb_byte(code, 0x72);
    cg_branch(p, f, sdone, true);
    cg_sp_load64(f, varr, j, 0); let vv = cg_save(f, 0x7e);
    cg_get(f, vv); cg_get(f, nm); wb_byte(code, 0x55); cg_begin(f, 0x04, 0x40); cg_get(f, vv); cg_set(f, nm); cg_end(f);
    cg_get(f, j); wb_i64(code, 1); wb_byte(code, 0x7c); cg_set(f, j);
    cg_branch(p, f, sagain, false); cg_end(f); cg_end(f);
    cg_end(f);
    cg_sp_load64(f, pin, e, 16); cg_get(f, key); wb_byte(code, 0x51);
    cg_get(f, nm); cg_get(f, mx2); wb_byte(code, 0x51); wb_byte(code, 0x71);
    cg_branch(p, f, fdone, true);
    cg_sp_slot_addr(f, pin, e, 16); cg_get(f, key); wb_mem(code, 0x37, 3, 0);
    cg_sp_slot_addr(f, pin, e, 176); cg_get(f, nm); wb_mem(code, 0x37, 3, 0);
    cg_get(f, mx2); cg_set(f, c);
    cg_get(f, nm); cg_set(f, now);
    cg_get(f, e); wb_i64(code, 1); wb_byte(code, 0x7c); cg_set(f, j);
    cg_get(f, lm1); cg_set(f, l);
    cg_branch(p, f, fagain, false); cg_end(f); cg_end(f);
    cg_get(f, idx); wb_byte(code, 0x0b); wb_body(out, locals, code);
}
fn cg_emit_spans_free(p: Program&, m: CgModule&, out: u8[>..]&) {
    // Params: 0: state (wa), 1: idx (i64), 2: cnt (i64)
    var events: WbEvent[>..] = [];
    var code: u8[>..] = []; var locals: i64[>..] = []; var slots: CgSlot[>..] = []; var addresses: CgFrameAddress[>..] = [];
    var labels: i64[>..] = []; var exits: CgExit[>..] = []; var results: i64[>..] = []; var destinations: i64[>..] = []; var work: i64[>..] = []; var raw_slots: i64[>..] = []; var sequences: CgSequence[>..] = []; var constructions: CgConstruction[>..] = []; var construction_destinations: CgDestination[>..] = []; var receiving: CgReceiving[>..] = []; var defers: i64[>..] = []; var hoists: CgHoist[>..] = [];
    var f = CgBody { events: events, code: code, locals: locals, slots: slots, addresses: addresses, labels: labels, exits: exits, results: results, destinations: destinations, work: work, raw_slots: raw_slots, sequences: sequences, constructions: constructions, construction_destinations: construction_destinations, receiving: receiving, hoists: hoists, params: 3, defers: defers };
    cg_get(f, 2); wb_i64(code, 0); wb_byte(code, 0x57); cg_begin(f, 0x04, 0x40); wb_byte(code, 0x0f); cg_end(f);
    cg_get(f, 0); wa_load(code, ww(3)); wa_op(code, 0x45); cg_begin(f, 0x04, 0x40);
    cg_get(f, 0); wb_op(code, 0x10, m.spans_newnode); wb_byte(code, 0x1a);
    cg_get(f, 0); wb_op(code, 0x10, m.spans_newnode); let r = cg_save(f, 0x7e);
    cg_get(f, 0); wa_load(code, ww(2)); cg_get(f, r); wb_mem(code, 0x37, 3, 0);
    cg_end(f);
    cg_get(f, 0); cg_get(f, 1); cg_get(f, 1); cg_get(f, 2); wb_byte(code, 0x7c); wb_op(code, 0x10, m.spans_near);
    cg_get(f, 0); cg_get(f, 1); cg_get(f, 2); wb_op(code, 0x10, m.spans_release);
    wb_byte(code, 0x0b); wb_body(out, locals, code);
}
fn cg_emit_spans_regrow(p: Program&, m: CgModule&, out: u8[>..]&) {
    // Params: 0: state (wa), 1: len (i64), 2: idx (i64), 3: ol (i64), 4: cnt (i64) -> i64
    var events: WbEvent[>..] = [];
    var code: u8[>..] = []; var locals: i64[>..] = []; var slots: CgSlot[>..] = []; var addresses: CgFrameAddress[>..] = [];
    var labels: i64[>..] = []; var exits: CgExit[>..] = []; var results: i64[>..] = []; var destinations: i64[>..] = []; var work: i64[>..] = []; var raw_slots: i64[>..] = []; var sequences: CgSequence[>..] = []; var constructions: CgConstruction[>..] = []; var construction_destinations: CgDestination[>..] = []; var receiving: CgReceiving[>..] = []; var defers: i64[>..] = []; var hoists: CgHoist[>..] = [];
    var f = CgBody { events: events, code: code, locals: locals, slots: slots, addresses: addresses, labels: labels, exits: exits, results: results, destinations: destinations, work: work, raw_slots: raw_slots, sequences: sequences, constructions: constructions, construction_destinations: construction_destinations, receiving: receiving, hoists: hoists, params: 5, defers: defers };
    cg_get(f, 0); wa_load(code, ww(3)); wa_op(code, 0x45); cg_begin(f, 0x04, 0x40);
    cg_get(f, 0); cg_get(f, 2); cg_get(f, 3); wb_op(code, 0x10, m.spans_free);
    cg_get(f, 0); cg_get(f, 1); cg_get(f, 4); wb_op(code, 0x10, m.spans_alloc); wb_byte(code, 0x0f);
    cg_end(f);
    let sc = m.span_scratch;
    cg_get(f, 2); cg_get(f, 3); wb_byte(code, 0x7c); let end = cg_save(f, 0x7e);
    cg_get(f, 0); cg_get(f, 2); cg_get(f, end); wb_op(code, 0x10, m.spans_near);
    wa_const(code, sc + 976); wb_mem(code, 0x29, 3, 0); let kind = cg_save(f, 0x7e);
    cg_get(f, kind); wb_i64(code, 0); wb_byte(code, 0x52); cg_begin(f, 0x04, 0x40);
    wa_const(code, sc + 968); wb_mem(code, 0x29, 3, 0); let nk = cg_save(f, 0x7e);
    wa_const(code, sc + 984); wb_mem(code, 0x29, 3, 0); let h = cg_save(f, 0x7e);
    wa_const(code, sc + 384); wa_const(code, sc); cg_get(f, kind); wb_i64(code, 2); wb_byte(code, 0x51); wb_byte(code, 0x1b);
    let nl_path = cg_save(f, wa());
    cg_get(f, 0); wa_load(code, ww(2)); let base = cg_save(f, wa());
    cg_sp_load64(f, nl_path, h, 0); let nl_id = cg_save(f, 0x7e);
    cg_sp_node_ptr(f, base, nl_id); let nl = cg_save(f, wa());
    cg_sp_load64(f, nl, nk, 16); let nidx = cg_save(f, 0x7e);
    cg_sp_load64(f, nl, nk, 264); let ncnt = cg_save(f, 0x7e);
    cg_get(f, 4); cg_get(f, 3); wb_byte(code, 0x7d); let need = cg_save(f, 0x7e);
    cg_get(f, nidx); cg_get(f, end); wb_byte(code, 0x51);
    cg_get(f, ncnt); cg_get(f, need); wb_byte(code, 0x59);
    cg_get(f, end); cg_get(f, ncnt); wb_byte(code, 0x7c); cg_get(f, 1); wb_byte(code, 0x51); wb_byte(code, 0x72);
    wb_byte(code, 0x71); cg_begin(f, 0x04, 0x40);
    cg_get(f, ncnt); cg_get(f, need); wb_byte(code, 0x57); cg_begin(f, 0x04, 0x40);
    cg_get(f, 0); cg_get(f, nl_path); cg_get(f, h); cg_get(f, nk); wb_op(code, 0x10, m.spans_delete);
    cg_control(f, 0x05);
    cg_sp_slot_addr(f, nl, nk, 16); cg_get(f, nidx); cg_get(f, need); wb_byte(code, 0x7c); wb_mem(code, 0x37, 3, 0);
    cg_get(f, ncnt); cg_get(f, need); wb_byte(code, 0x7d); let rem = cg_save(f, 0x7e);
    cg_sp_slot_addr(f, nl, nk, 264); cg_get(f, rem); wb_mem(code, 0x37, 3, 0);
    cg_get(f, 0); cg_get(f, nl_path); cg_get(f, h); cg_get(f, h); cg_get(f, ncnt); cg_get(f, rem); wb_op(code, 0x10, m.spans_fix);
    cg_end(f);
    cg_get(f, 2); wb_byte(code, 0x0f);
    cg_end(f); cg_end(f);
    cg_get(f, 0); cg_get(f, 2); cg_get(f, 3); wb_op(code, 0x10, m.spans_release);
    cg_get(f, 0); cg_get(f, 1); cg_get(f, 4); wb_op(code, 0x10, m.spans_alloc);
    wb_byte(code, 0x0b); wb_body(out, locals, code);
}
fn cg_allocate(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    if !f.scratch { wb_op(f.code, 0x10, m.allocator); return; }
    f.frame_used = true;
    // Takes an address-sized byte count, leaves an address.
    let bytes = cg_save(f, wa()); wb_op(f.code, 0x23, 0); let base = cg_save(f, wa());
    cg_get(f, base); wa_extend(f.code); cg_get(f, bytes); wa_extend(f.code); wb_byte(f.code, 0x7c); wb_i64(f.code, 7); wb_byte(f.code, 0x7c); wb_i64(f.code, -8); wb_byte(f.code, 0x83); let top64 = cg_save(f, 0x7e);
    // The i64 sum cannot wrap from 32-bit operands; from 64-bit ones it can,
    // and then lands below the base.
    if cg_wide { cg_get(f, top64); cg_get(f, base); wb_byte(f.code, 0x54); }
    cg_get(f, top64); if m.regions_enabled { wb_op(f.code, 0x23, 10); wa_extend(f.code); } else { wb_i64(f.code, m.stack_limit); } wb_byte(f.code, 0x56);
    if cg_wide { wb_byte(f.code, 0x72); }
    cg_trap_if(p, m, f, node, "activation/scratch arena exhausted");
    cg_get(f, top64); wa_wrap(f.code); let top = cg_save(f, wa()); cg_ensure_memory(p, m, f, top, node);
    cg_get(f, top); wb_op(f.code, 0x24, 0); cg_get(f, base);
}
fn cg_allocator_body(out: u8[>..]&) {
    // (bytes:i32)->i32, (bytes:i64)->i64 with cg_wide: local 0 the bytes,
    // 1 the base, 2 the new top, all address-sized. global 1 is the aligned
    // persistent arena cursor.
    wb_u(out, 1); wb_u(out, 2); wb_byte(out, wa());
    wb_op(out, 0x23, 1); wb_op(out, 0x21, 1);
    wb_op(out, 0x20, 1); wb_op(out, 0x20, 0); wa_op(out, 0x6a); wa_const(out, 7); wa_op(out, 0x6a); wa_const(out, -8); wa_op(out, 0x71); wb_op(out, 0x22, 2);
    wb_op(out, 0x20, 1); wa_op(out, 0x49); wb_byte(out, 0x04); wb_byte(out, 0x40); wb_byte(out, 0); wb_byte(out, 0x0b);
    wb_op(out, 0x20, 2); wb_op(out, 0x3f, 0); wa_const(out, 16); wa_op(out, 0x74); wa_op(out, 0x4b); wb_byte(out, 0x04); wb_byte(out, 0x40);
    wb_op(out, 0x20, 2); wa_const(out, 16); wa_op(out, 0x76); wb_op(out, 0x20, 2); wa_const(out, 65535); wa_op(out, 0x71); wa_op(out, 0x45); wb_byte(out, 0x45); wa_from_i32(out); wa_op(out, 0x6a);
    wb_op(out, 0x3f, 0); wa_op(out, 0x6b); wb_op(out, 0x40, 0); wa_const(out, -1); wa_op(out, 0x46); wb_byte(out, 0x04); wb_byte(out, 0x40); wb_byte(out, 0); wb_byte(out, 0x0b); wb_byte(out, 0x0b);
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
fn cg_emit_thunk(p: Program&, m: CgModule&, function_index: i64, out: u8[>..]&, scratch: CgEmitScratch&) {
    let item = m.functions[function_index]; scratch.thunk_code.clear(); scratch.thunk_locals.clear();
    var param = p.nodes[item.node].first; var count = 0;
    while param >= 0 { wb_op(scratch.thunk_code, 0x20, count + 1); count++; param = p.nodes[param].next; }
    var capture_offset = 0;
    for capture in m.captures {
        if capture.function == item.node { wb_op(scratch.thunk_code, 0x20, 0); wa_load(scratch.thunk_code, capture_offset); capture_offset += wa_bytes(); }
    }
    scratch.thunk_results.clear(); cg_function_results(p, item.node, scratch.thunk_results);
    var destination = count + 1;
    for id in scratch.thunk_results { if cg_aggregate(p, id) { wb_op(scratch.thunk_code, 0x20, destination); destination++; } }
    if (p.nodes[item.node].flags & F_LOCATED) != 0 { wb_i32(scratch.thunk_code, p.tokens[p.nodes[item.node].token].line); }
    wb_op(scratch.thunk_code, 0x10, item.index); wb_byte(scratch.thunk_code, 0x0b); wb_body(out, scratch.thunk_locals, scratch.thunk_code);
}
recursive fn cg_propagate_captures(p: Program&, m: CgModule&, function: i64, node: i64) {
    if node < 0 { return; } let n: const Node& = p.nodes[node];
    let kind = n.kind;
    if kind == N_PATTERN || (kind == N_FUNCTION || kind == N_FUNCTION_VALUE) && node != function { return; }
    if (kind == N_CALL || kind == N_FUNCTION_VALUE || kind == N_NAME) && n.symbol >= 0 && (p.symbols[n.symbol].flags & S_FUNCTION) != 0 {
        let target = p.symbols[n.symbol].node; let count = m.captures.len;
        for i in 0..count {
            let capture = m.captures[i];
            if capture.function == target && p.symbols[capture.symbol].owner != function && !cg_capture(m, function, capture.symbol) {
                m.captures.push(CgCapture { function: function, symbol: capture.symbol });
            }
        }
    }
    if kind == N_CALL && (n.flags & F_DISPATCH) != 0 {
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
    var child = n.left; while child >= 0 { cg_propagate_captures(p, m, function, child); child = p.nodes[child].next; }
    child = n.right; while child >= 0 { cg_propagate_captures(p, m, function, child); child = p.nodes[child].next; }
    child = n.third; while child >= 0 { cg_propagate_captures(p, m, function, child); child = p.nodes[child].next; }
    child = n.first; while child >= 0 { cg_propagate_captures(p, m, function, child); child = p.nodes[child].next; }
}
fn cg_host_signature(m: CgModule&, host: i64) -> i64 {
    var args: u8[>..] = []; var results: u8[>..] = [];
    if host == CG_WRITE { args.push(wa() as u8); args.push(0x7f); }
    else if host == CG_PRINT_I64 || host == CG_PRINT_U64 { args.push(0x7e); }
    else if host == CG_PRINT_F64 { args.push(0x7c); }
    else if host == CG_PRINT_F32 { args.push(0x7d); }
    else if host == CG_PRINT_BOOL || host == CG_EXIT { args.push(0x7f); }
    else if host == CG_ABORT { args.push(wa() as u8); args.push(0x7f); args.push(0x7f); }
    else if host == CG_FORMAT_F32 || host == CG_FORMAT_F64 {
        args.push(wa() as u8); if host == CG_FORMAT_F32 { args.push(0x7d); } else { args.push(0x7c); } results.push(0x7f);
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
    if node < 0 { return false; } let n: const Node& = p.nodes[node];
    if cg_type_kind(p, n.type_id) == TY_REF { return false; }
    if n.kind == N_NAME {
        if n.symbol < 0 || n.symbol >= p.symbols.len { return false; }
        let symbol: const Symbol& = p.symbols[n.symbol];
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
recursive fn cg_region_owned_result(p: Program&, id: i64) -> bool {
    if id < 13 { return false; }
    if cg_type_kind(p, id) != TY_TUPLE { return cg_has_owner(p, id); }
    var component = p.types[id].first;
    while component >= 0 { if cg_region_owned_result(p, p.nodes[component].type_id) { return true; } component = p.nodes[component].next; }
    return false;
}
recursive fn cg_region_type_supported(p: Program&, id: i64) -> bool {
    if id < 13 { return true; }
    var value = id;
    var kind = cg_type_kind(p, value);
    while kind == TY_REF { value = p.types[value].element; kind = cg_type_kind(p, value); }
    if kind != TY_STRUCT && kind != TY_ENUM && kind != TY_ARRAY && kind != TY_TUPLE { return true; }
    let known = cg_memo_get(p, value, CG_MEMO_REGION_TYPE);
    if known >= 0 { return known == 1; }
    return cg_memo_set(p, value, CG_MEMO_REGION_TYPE, cg_region_type_layout_supported(p, value));
}
recursive fn cg_region_type_layout_supported(p: Program&, value: i64) -> bool {
    if cg_type_kind(p, value) == TY_TUPLE {
        var component = p.types[value].first; while component >= 0 { if !cg_region_type_supported(p, p.nodes[component].type_id) { return false; } component = p.nodes[component].next; } return true;
    }
    if !cg_has_owner(p, value) { return true; }
    // A reference component to a root owner is checked where that owner is.
    if root_struct_type(p, value) {
        var field = p.types[value].first;
        while field >= 0 {
            var component = p.nodes[field].type_id; while cg_type_kind(p, component) == TY_REF { component = p.types[component].element; }
            if (p.nodes[field].flags & F_PAD) == 0 && !root_struct_type(p, component) && !cg_region_type_supported(p, component) { return false; }
            field = p.nodes[field].next;
        }
        return true;
    }
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
// Forwarding spans can only be published by growable arrays. Restrict this
// omission proof to scalar values and fixed scalar arrays; compound values,
// references, closures and unknown call targets retain the general backend.
fn cg_unforwarded_type(p: Program&, id: i64) -> bool {
    if cg_scalar_type(p, id) { return true; }
    return cg_type_kind(p, id) == TY_ARRAY && p.types[id].array_kind == A_FIXED && cg_scalar_type(p, p.types[id].element);
}
recursive fn cg_unforwarded_body(p: Program&, function: i64, node: i64) -> bool {
    if node < 0 { return true; } let n: const Node& = p.nodes[node];
    if n.kind == N_PATTERN || n.kind == N_STRUCT || n.kind == N_ENUM || n.kind == N_ALIAS || n.kind == N_IMPORT { return true; }
    if n.kind == N_FUNCTION && node != function { return true; }
    if n.kind == N_FUNCTION_VALUE { return false; }
    if n.type_id >= 0 && !cg_unforwarded_type(p, n.type_id) {
        if cg_type_kind(p, n.type_id) != TY_FN || n.symbol < 0 || (p.symbols[n.symbol].flags & (S_FUNCTION | S_BUILTIN)) == 0 { return false; }
    }
    if n.coerced_type >= 0 && !cg_unforwarded_type(p, n.coerced_type) { return false; }
    if n.kind == N_CALL && (n.symbol < 0 || (n.flags & F_DISPATCH) != 0) { return false; }
    if !cg_unforwarded_body(p, function, n.left) || !cg_unforwarded_body(p, function, n.right) || !cg_unforwarded_body(p, function, n.third) { return false; }
    var child = n.first; while child >= 0 { if !cg_unforwarded_body(p, function, child) { return false; } child = p.nodes[child].next; }
    return true;
}
fn cg_unforwarded_module(p: Program&, m: CgModule&) -> bool {
    if m.pool_global >= 0 { return false; }
    for symbol in p.symbols {
        if symbol.owner >= 0 && (p.nodes[symbol.owner].flags & F_REACHABLE) == 0 { continue; }
        if symbol.node >= 0 && (p.nodes[symbol.node].kind == N_FIELD || p.nodes[symbol.node].kind == N_VARIANT) { continue; }
        if symbol.type_id >= 0 && (symbol.flags & (S_FUNCTION | S_TYPE | S_BUILTIN)) == 0 && !cg_unforwarded_type(p, symbol.type_id) { return false; }
        if (symbol.flags & S_GLOBAL) != 0 && symbol.node >= 0 && !cg_unforwarded_body(p, -1, p.nodes[symbol.node].right) { return false; }
    }
    for item in m.functions { if !cg_unforwarded_body(p, item.node, item.node) { return false; } }
    return true;
}
// Collect host imports and array helpers in the same walk of emitted bodies.
struct CgHelperDemand {
    pool: bool = false, slice_pool: bool = false, formats: i64 = 0, raw_appends: i64 = 0, raw_append_type: i64 = -1,
    owner_indexes: i64 = 0, owner_mutations: i64 = 0
}
// A root owner's frame places its components' own storage side by side, as
// native C's does: each field takes the slot its type takes as a variable, so
// a resizable component keeps its 24-byte control there and has its own
// region. An encoded scalar keeps its encoding, which reads of it as a field
// decode, in the widest slot it needs. The checked layout (one reference per
// field) only describes the owner to the frontend; emission uses this one,
// set before it starts.
fn cg_root_layouts(p: Program&) {
    for id in 0..p.types.len {
        if p.types[id].size < 0 || !root_struct_type(p, id) { continue; }
        var offset = 0; var align = p.types[id].align; var field = p.types[id].first;
        while field >= 0 {
            let component = p.nodes[field].type_id;
            if (p.nodes[field].flags & F_PAD) == 0 && component >= 0 {
                let component_align = p.types[component].align; offset = cg_align(offset, component_align);
                var bytes = cg_slot_size(p, component); if p.types[component].storage == 1 { bytes = 10; }
                p.nodes[field].integer = offset; offset += bytes;
                if component_align > align { align = component_align; }
            }
            field = p.nodes[field].next;
        }
        p.types[id].size = cg_align(offset, align); p.types[id].align = align;
    }
}
// The data regions a global of this type owns: one per component that owns
// storage for a root owner, otherwise its one.
fn cg_region_width(p: Program&, id: i64) -> i64 {
    if !root_struct_type(p, id) { return 1; }
    var width = 0; var field = p.types[id].first;
    while field >= 0 { if (p.nodes[field].flags & F_PAD) == 0 && cg_has_owner(p, p.nodes[field].type_id) { width += 1; } field = p.nodes[field].next; }
    return width;
}
struct CgPrescan {
    helpers: CgHelperDemand,
    arena_edges: i32[>..]&,
    fn_edge_start: i32[>..]&,
    fn_edge_count: i32[>..]&,
    fn_reusable: bool[>..]&,
    type_reg: u8[>..]&,
    region_ok: bool = true,
    region_owns: bool = false,
    cur_fn_node: i64 = -1,
    cur_fn_idx: i64 = -1,
    cur_captures: bool = false,
    cur_helpers: bool = false,
    cur_arrays: bool = false,
    cur_region: bool = false,
    cur_arena_ok: bool = false,
}
// Cached per-type region classification for prescan:
// 1 = unsupported, 2 = supported & no owner, 3 = supported & stripped owns, 4 = supported & tid owns.
fn cg_prescan_type_reg(p: Program&, ps: CgPrescan&, tid: i64) -> u8 {
    let cached = ps.type_reg[tid];
    if cached != 0 { return cached; }
    if !cg_region_type_supported(p, tid) { ps.type_reg[tid] = 1; return 1; }
    var stripped = tid;
    while cg_type_kind(p, stripped) == TY_REF { stripped = p.types[stripped].element; }
    var code: u8 = 2;
    if cg_region_owned_result(p, stripped) {
        if stripped == tid || cg_region_owned_result(p, tid) { code = 4; } else { code = 3; }
    }
    ps.type_reg[tid] = code;
    return code;
}
recursive fn cg_prescan_node(p: Program&, m: CgModule&, ps: CgPrescan&, node: i64, mark_val: bool, primary: bool, reg_owns: bool&, reg_may: bool&) {
    if node < 0 { return; }
    let n: const Node& = p.nodes[node];
    let kind = n.kind;
    if kind == N_INTEGER || kind == N_FLOAT || kind == N_BOOL || kind == N_NULL || kind == N_EMPTY || kind == N_CONTINUE ||
       kind == N_PATTERN || kind == N_STRUCT || kind == N_ENUM || kind == N_ALIAS || kind == N_IMPORT || kind == N_FUNCTION {
        if primary && ps.cur_region && ps.region_ok {
            let tid = n.type_id;
            if tid >= 13 && cg_prescan_type_reg(p, ps, tid) == 1 { ps.region_ok = false; }
            else { m.region_memo[node] = 1; }
        }
        return;
    }
    if kind == N_FUNCTION_VALUE {
        if mark_val { p.nodes[node].flags |= F_VALUE_USED; }
        if primary && ps.cur_region && ps.region_ok { m.region_memo[node] = 1; }
        return;
    }
    if kind == N_NAME {
        let sym = n.symbol;
        if sym >= 0 && sym < p.symbols.len {
            let s: const Symbol& = p.symbols[sym];
            if mark_val && (s.flags & (S_FUNCTION | S_BUILTIN)) == S_FUNCTION && s.node >= 0 {
                p.nodes[s.node].flags |= F_VALUE_USED;
            }
            if ps.cur_captures && (s.flags & (S_FUNCTION | S_GLOBAL | S_TYPE | S_BUILTIN)) == 0 &&
               (s.owner >= 0 || cg_storage_binding(p, sym)) && s.owner != ps.cur_fn_node && !cg_capture(m, ps.cur_fn_node, sym) {
                m.captures.push(CgCapture { function: ps.cur_fn_node, symbol: sym });
            }
            if (s.flags & CG_ADDRESS_TAKEN) == 0 &&
               ((n.flags & F_REFERENCE_CONTEXT) != 0 || n.type_id >= 13 && cg_type_kind(p, n.type_id) == TY_REF || n.coerced_type >= 13 && cg_type_kind(p, n.coerced_type) == TY_REF) {
                let sk = cg_type_kind(p, s.type_id);
                if sk == TY_REF {
                    if cg_type_kind(p, n.type_id) == TY_REF && cg_type_kind(p, p.types[n.type_id].element) == TY_REF ||
                       cg_type_kind(p, n.coerced_type) == TY_REF && cg_type_kind(p, p.types[n.coerced_type].element) == TY_REF ||
                       (n.flags & F_REFERENCE_CONTEXT) != 0 && cg_type_kind(p, n.type_id) != TY_REF {
                        p.symbols[sym].flags |= CG_ADDRESS_TAKEN;
                    }
                } else if sk == TY_SLICE {
                    if cg_type_kind(p, n.type_id) == TY_REF || cg_type_kind(p, n.coerced_type) == TY_REF {
                        p.symbols[sym].flags |= CG_ADDRESS_TAKEN;
                    }
                } else {
                    p.symbols[sym].flags |= CG_ADDRESS_TAKEN;
                }
            }
        }
        if primary && ps.cur_region && ps.region_ok {
            let tid = n.type_id;
            if tid < 13 {
                m.region_memo[node] = 1;
            } else {
                let tr = cg_prescan_type_reg(p, ps, tid);
                if tr == 1 { ps.region_ok = false; }
                else if tr >= 3 { m.region_memo[node] = 2; reg_may = true; }
                else { m.region_memo[node] = 1; }
            }
        }
        return;
    }
    var sub_may = false;
    if primary && ps.cur_region && ps.region_ok {
        let tid = n.type_id;
        if tid >= 13 {
            let tr = cg_prescan_type_reg(p, ps, tid);
            if tr == 1 {
                ps.region_ok = false;
            } else {
                if tr >= 3 {
                    sub_may = true;
                    if tr == 4 && (kind == N_CALL || cg_result_channels(p, node) || kind == N_ARRAY || kind == N_FILL || kind == N_RECORD || kind == N_CAST) {
                        reg_owns = true;
                    }
                }
                if kind == N_RETURN && n.symbol >= 0 {
                    let target = p.symbols[n.symbol].node;
                    if target != ps.cur_fn_node && !cg_effect_result_supported(p, cg_result_type(p, target)) { ps.region_ok = false; }
                }
            }
        } else if kind == N_RETURN && n.symbol >= 0 {
            let target = p.symbols[n.symbol].node;
            if target != ps.cur_fn_node && !cg_effect_result_supported(p, cg_result_type(p, target)) { ps.region_ok = false; }
        }
    }
    if kind == N_CALL {
        if (n.flags & F_DISPATCH) != 0 {
            var arm = n.third;
            while arm >= 0 {
                let asym = p.nodes[arm].symbol;
                if asym >= 0 && p.symbols[asym].node >= 0 { p.nodes[p.symbols[asym].node].flags |= CG_DISPATCH_ENTRY; }
                if primary && ps.cur_arena_ok {
                    if asym < 0 { ps.cur_arena_ok = false; } else { ps.arena_edges.push(asym as i32); }
                }
                arm = p.nodes[arm].next;
            }
        } else {
            let csym = n.symbol;
            if csym >= 0 && csym < p.symbols.len && (p.symbols[csym].flags & S_BUILTIN) != 0 {
                let builtin = p.symbols[csym].index;
                if primary && ps.cur_helpers {
                    if builtin >= 30 && builtin <= 35 { ps.helpers.pool = true; }
                    if builtin >= 33 && builtin <= 35 { ps.helpers.slice_pool = true; }
                    if ps.cur_arrays && ps.helpers.owner_mutations < 2 && builtin >= 24 && builtin <= 29 && n.first >= 0 {
                        var id = p.nodes[n.first].type_id; while cg_type_kind(p, id) == TY_REF { id = p.types[id].element; }
                        if cg_owner(p, id) { ps.helpers.owner_mutations++; }
                    }
                    if builtin == 1 || builtin == 2 {
                        var output = n.type_id; var arg = n.first;
                        if builtin == 2 {
                            output = -1;
                            if arg >= 0 { output = p.nodes[arg].type_id; arg = p.nodes[arg].next; }
                        }
                        while cg_type_kind(p, output) == TY_REF { output = p.types[output].element; }
                        if ps.cur_arrays && arg >= 0 && cg_raw_append_type(p, output) {
                            ps.helpers.raw_appends++;
                            if ps.helpers.raw_append_type < 0 { ps.helpers.raw_append_type = output; }
                        }
                        while arg >= 0 {
                            var id = p.nodes[arg].type_id;
                            while cg_type_kind(p, id) == TY_REF { id = p.types[id].element; }
                            if cg_type_kind(p, id) == TY_FLOAT { if p.types[id].count == 32 { ps.helpers.formats |= 1; } else { ps.helpers.formats |= 2; } }
                            arg = p.nodes[arg].next;
                        }
                    }
                }
                if primary && ps.cur_arena_ok {
                    if builtin == 2 && !cg_private_place(p, ps.cur_fn_node, n.first) { ps.cur_arena_ok = false; }
                    if builtin == 16 && n.first >= 0 && p.nodes[n.first].next >= 0 &&
                       !cg_private_place(p, ps.cur_fn_node, p.nodes[n.first].next) { ps.cur_arena_ok = false; }
                    if builtin >= 24 && builtin <= 29 && !cg_private_place(p, ps.cur_fn_node, n.first) { ps.cur_arena_ok = false; }
                    if builtin >= 7 && builtin <= 13 || builtin >= 30 { ps.cur_arena_ok = false; }
                }
            } else if primary && ps.cur_arena_ok {
                if csym < 0 || csym >= p.symbols.len { ps.cur_arena_ok = false; }
                else { ps.arena_edges.push(csym as i32); }
            }
        }
    } else if kind == N_UNARY {
        if n.integer == T_BITAND && n.left >= 0 {
            if p.nodes[n.left].kind == N_NAME && cg_type_kind(p, p.nodes[n.left].type_id) != TY_REF {
                let sym = p.nodes[n.left].symbol; if sym >= 0 { p.symbols[sym].flags |= CG_ADDRESS_TAKEN; }
            } else if p.nodes[n.left].kind == N_MEMBER && cg_type_kind(p, p.nodes[n.left].type_id) != TY_REF {
                let ml = p.nodes[n.left].left;
                if ml >= 0 && p.nodes[ml].kind == N_NAME && p.nodes[ml].symbol >= 0 &&
                   cg_type_kind(p, p.symbols[p.nodes[ml].symbol].type_id) == TY_STRUCT {
                    p.symbols[p.nodes[ml].symbol].flags |= CG_NO_SROA;
                }
            }
        }
    } else if kind == N_MEMBER {
        if n.left >= 0 && p.nodes[n.left].kind == N_NAME {
            let sym = p.nodes[n.left].symbol;
            if sym >= 0 && sym < p.symbols.len && cg_type_kind(p, p.symbols[sym].type_id) == TY_STRUCT &&
               (p.symbols[sym].flags & CG_NO_SROA) == 0 {
                if n.symbol < 0 || n.symbol >= p.nodes.len || p.nodes[n.symbol].kind != N_FIELD {
                    p.symbols[sym].flags |= CG_NO_SROA;
                } else if (n.flags & F_REFERENCE_CONTEXT) != 0 ||
                          n.type_id >= 13 && cg_type_kind(p, n.type_id) == TY_REF ||
                          n.coerced_type >= 13 && cg_type_kind(p, n.coerced_type) == TY_REF {
                    let fk = cg_type_kind(p, p.nodes[n.symbol].type_id);
                    if fk == TY_REF {
                        if cg_type_kind(p, n.type_id) == TY_REF && cg_type_kind(p, p.types[n.type_id].element) == TY_REF ||
                           cg_type_kind(p, n.coerced_type) == TY_REF && cg_type_kind(p, p.types[n.coerced_type].element) == TY_REF ||
                           (n.flags & F_REFERENCE_CONTEXT) != 0 && cg_type_kind(p, n.type_id) != TY_REF {
                            p.symbols[sym].flags |= CG_NO_SROA;
                        }
                    } else if fk == TY_SLICE {
                        if cg_type_kind(p, n.type_id) == TY_REF || cg_type_kind(p, n.coerced_type) == TY_REF {
                            p.symbols[sym].flags |= CG_NO_SROA;
                        }
                    } else {
                        p.symbols[sym].flags |= CG_NO_SROA;
                    }
                }
            }
        }
    } else if kind == N_INDEX {
        if primary && ps.cur_helpers && ps.cur_arrays && ps.helpers.owner_indexes < 2 {
            var id = p.nodes[n.left].type_id; while cg_type_kind(p, id) == TY_REF { id = p.types[id].element; }
            if cg_owner(p, id) { ps.helpers.owner_indexes++; }
        }
    } else if kind == N_RETURN {
        if ps.cur_fn_node >= 0 && n.symbol >= 0 && (p.symbols[n.symbol].flags & S_FUNCTION) != 0 {
            let target = p.symbols[n.symbol].node;
            if target >= 0 && target != ps.cur_fn_node {
                m.nonlocal_returns = true; p.nodes[target].flags |= CG_EFFECT_TARGET; p.nodes[node].flags |= F_NONLOCAL;
            }
        }
        if primary && ps.cur_arena_ok && n.symbol >= 0 && p.symbols[n.symbol].node != ps.cur_fn_node { ps.cur_arena_ok = false; }
    } else if kind == N_ASSIGN {
        if primary && ps.cur_arena_ok && !cg_private_place(p, ps.cur_fn_node, n.left) { ps.cur_arena_ok = false; }
        if n.left >= 0 && p.nodes[n.left].kind == N_NAME && p.nodes[n.left].symbol >= 0 &&
           n.right >= 0 && p.nodes[n.right].kind == N_RECORD && (cg_record_has_self(p, n.right) || cg_record_has_extern(p, n.right)) {
            p.symbols[p.nodes[n.left].symbol].flags |= CG_NO_SROA;
        }
    } else if kind == N_VARIABLE {
        if primary && ps.cur_arena_ok && (n.flags & F_REUSABLE) != 0 { ps.fn_reusable[ps.cur_fn_idx] = true; }
        if n.symbol >= 0 && n.right >= 0 && p.nodes[n.right].kind == N_RECORD && (cg_record_has_self(p, n.right) || cg_record_has_extern(p, n.right)) {
            p.symbols[n.symbol].flags |= CG_NO_SROA;
        }
    } else if kind == N_RECORD {
        if ps.cur_fn_idx >= 0 && cg_record_has_extern(p, node) { m.functions[ps.cur_fn_idx].sroa_return = -1; }
    } else if kind == N_SELF {
        if ps.cur_fn_idx >= 0 { m.functions[ps.cur_fn_idx].sroa_return = -1; }
    }
    let is_direct_call = kind == N_CALL && n.symbol >= 0 && ((n.flags & F_DISPATCH) != 0 || (p.symbols[n.symbol].flags & (S_FUNCTION | S_BUILTIN)) == S_FUNCTION);
    let side_mark = mark_val && !is_direct_call;
    var dummy_owns = false; var dummy_may = false;
    if n.left >= 0 {
        cg_prescan_node(p, m, ps, n.left, side_mark, primary, reg_owns, sub_may);
        var tail = p.nodes[n.left].next;
        while tail >= 0 { cg_prescan_node(p, m, ps, tail, side_mark, false, dummy_owns, dummy_may); tail = p.nodes[tail].next; }
    }
    if n.right >= 0 {
        cg_prescan_node(p, m, ps, n.right, side_mark, primary, reg_owns, sub_may);
        var tail = p.nodes[n.right].next;
        while tail >= 0 { cg_prescan_node(p, m, ps, tail, side_mark, false, dummy_owns, dummy_may); tail = p.nodes[tail].next; }
    }
    if n.third >= 0 {
        cg_prescan_node(p, m, ps, n.third, side_mark, primary, reg_owns, sub_may);
        var tail = p.nodes[n.third].next;
        while tail >= 0 { cg_prescan_node(p, m, ps, tail, side_mark, false, dummy_owns, dummy_may); tail = p.nodes[tail].next; }
    }
    var child = n.first; var emitted = true;
    while child >= 0 {
        var child_owns = false;
        cg_prescan_node(p, m, ps, child, mark_val, primary, child_owns, sub_may);
        if primary && emitted && child_owns { reg_owns = true; }
        if primary && ps.cur_region && ps.region_ok && cg_terminal(p, child) { emitted = false; }
        child = p.nodes[child].next;
    }
    if primary && ps.cur_region && ps.region_ok {
        if sub_may { m.region_memo[node] = 2; reg_may = true; } else { m.region_memo[node] = 1; }
    }
}
fn cg_sort_ids(ids: i64[>..]&) {
    let n = ids.len;
    var gap = n / 2;
    while gap > 0 {
        for i in gap..n {
            let v = ids[i];
            var j = i;
            while j >= gap && ids[j - gap] > v {
                ids[j] = ids[j - gap];
                j -= gap;
            }
            ids[j] = v;
        }
        gap /= 2;
    }
}
fn cg_collect(p: Program&, m: CgModule&) {
    cg_root_layouts(p);
    for host in 0..9 { m.imports.push(CgImport { signature: cg_host_signature(m, host), host: host }); }
    var checked_fns: i64[>..] = [];
    var loc_candidates = false;
    for i in 0..p.symbols.len {
        let symbol: const Symbol& = p.symbols[i];
        m.globals.push(-1); m.global_regions.push(-1);
        if (symbol.flags & S_GLOBAL) != 0 && symbol.type_id >= 0 && symbol.component_owner < 0 {
            m.next_data = cg_align(m.next_data, p.types[symbol.type_id].align); m.globals[i] = m.next_data; m.next_data += cg_slot_size(p, symbol.type_id);
            if cg_has_owner(p, symbol.type_id) { m.global_regions[i] = m.global_region_count; m.global_region_count += cg_region_width(p, symbol.type_id); }
        }
        if (symbol.flags & S_FUNCTION) != 0 && symbol.node >= 0 {
            let fnode = symbol.node;
            let fn_n: const Node& = p.nodes[fnode];
            if (fn_n.kind == N_FUNCTION || fn_n.kind == N_FUNCTION_VALUE) && fn_n.symbol == i {
                p.nodes[fnode].flags &= ~(CG_EFFECT_TARGET | F_LOCATED | F_VALUE_USED);
                if (fn_n.flags & (F_CHECKED | F_GENERIC)) == F_CHECKED {
                    checked_fns.push(fnode);
                    if library_node(p, fnode) || (fn_n.flags & F_EXTERN) != 0 && location_extern(p, fnode) { loc_candidates = true; }
                }
            }
        }
    }
    cg_sort_ids(checked_fns);
    // A named component (`owner.field` in an index or relative reference
    // type) is that field's place inside its global owner's frame.
    for i in 0..p.symbols.len {
        let symbol: const Symbol& = p.symbols[i];
        if symbol.component_owner >= 0 && symbol.component >= 0 && m.globals[symbol.component_owner] >= 0 { m.globals[i] = m.globals[symbol.component_owner] + p.nodes[symbol.component].integer; }
    }
    var checked_fn_idx: i32[>..] = []; checked_fn_idx.resize(checked_fns.len, -1);
    var extern_fns: i64[>..] = [];
    for ci in 0..checked_fns.len {
        let fnode = checked_fns[ci];
        let fn_n: const Node& = p.nodes[fnode];
        if (fn_n.flags & F_REACHABLE) == 0 { continue; }
        if (fn_n.flags & F_THREAD) != 0 { cg_fail(p, fnode, "wasm: threads are unsupported by the direct host ABI"); }
        if (fn_n.flags & F_EXTERN) != 0 {
            if location_extern(p, fnode) { cg_fail(p, fnode, "wasm: the slice pool span tree externs are not supported by the direct Wasm backend; use --target native\n  help: compile with `--target native` or `--target c` for slice-pool span-tree externs"); continue; }
            cg_importable(p, fnode);
            extern_fns.push(fnode);
        } else {
            checked_fn_idx[ci] = m.functions.len as i32;
            m.functions.push(CgFunction { node: fnode, symbol: fn_n.symbol });
        }
    }
    let ordinary_count = m.functions.len;
    m.region_memo.resize(p.nodes.len, 0);
    var arena_edges: i32[>..] = [];
    var fn_edge_start: i32[>..] = []; fn_edge_start.resize(ordinary_count, 0);
    var fn_edge_count: i32[>..] = []; fn_edge_count.resize(ordinary_count, 0);
    var fn_reusable: bool[>..] = []; fn_reusable.resize(ordinary_count, false);
    var type_reg: u8[>..] = []; type_reg.resize(p.types.len, 0);
    var ps = CgPrescan {
        helpers: CgHelperDemand {},
        arena_edges: arena_edges,
        fn_edge_start: fn_edge_start,
        fn_edge_count: fn_edge_count,
        fn_reusable: fn_reusable,
        type_reg: type_reg,
    };
    for s_id in 0..p.symbols.len {
        let symbol: const Symbol& = p.symbols[s_id];
        if symbol.owner >= 0 && (p.nodes[symbol.owner].flags & F_REACHABLE) == 0 { continue; }
        if symbol.node >= 0 && (p.nodes[symbol.node].kind == N_FIELD || p.nodes[symbol.node].kind == N_VARIANT) { continue; }
        if symbol.type_id >= 0 && (symbol.flags & (S_FUNCTION | S_TYPE | S_BUILTIN)) == 0 {
            if !cg_region_type_supported(p, symbol.type_id) { ps.region_ok = false; }
            if cg_has_owner(p, symbol.type_id) { ps.region_owns = true; }
        }
    }
    for index in 0..ordinary_count {
        let fnode = m.functions[index].node;
        m.functions[index].arena_local = cg_scalar_results(p, fnode) && (p.nodes[fnode].flags & F_NONLOCAL) == 0;
        let result = cg_result_type(p, fnode);
        if !cg_region_type_supported(p, result) { ps.region_ok = false; }
        if cg_region_owned_result(p, result) { ps.region_owns = true; }
    }
    var reg_may = false;
    for ci in 0..checked_fns.len {
        let fnode = checked_fns[ci];
        let fn_idx = checked_fn_idx[ci] as i64;
        let body = p.nodes[fnode].right;
        ps.cur_fn_node = fnode;
        ps.cur_fn_idx = fn_idx;
        if fn_idx >= 0 {
            ps.cur_captures = true;
            ps.cur_helpers = true;
            ps.cur_arrays = true;
            ps.cur_region = true;
            ps.cur_arena_ok = m.functions[fn_idx].arena_local;
            ps.fn_edge_start[fn_idx] = ps.arena_edges.len as i32;
            cg_prescan_node(p, m, ps, body, true, true, ps.region_owns, reg_may);
            m.functions[fn_idx].arena_local = ps.cur_arena_ok;
            ps.fn_edge_count[fn_idx] = (ps.arena_edges.len as i32) - ps.fn_edge_start[fn_idx];
        } else {
            ps.cur_captures = false;
            ps.cur_helpers = false;
            ps.cur_arrays = false;
            ps.cur_region = false;
            ps.cur_arena_ok = false;
            var dummy_owns = false;
            cg_prescan_node(p, m, ps, body, true, true, dummy_owns, reg_may);
        }
    }
    ps.cur_fn_node = -1;
    ps.cur_fn_idx = -1;
    ps.cur_captures = false;
    ps.cur_arena_ok = false;
    for s_id in 0..p.symbols.len {
        let symbol: const Symbol& = p.symbols[s_id];
        if (symbol.flags & S_GLOBAL) == 0 || symbol.node < 0 { continue; }
        ps.cur_helpers = true;
        ps.cur_arrays = symbol.component_owner < 0;
        ps.cur_region = symbol.type_id >= 0 && (symbol.flags & (S_FUNCTION | S_TYPE | S_BUILTIN)) == 0 &&
            !(p.nodes[symbol.node].kind == N_FIELD || p.nodes[symbol.node].kind == N_VARIANT);
        cg_prescan_node(p, m, ps, p.nodes[symbol.node].right, true, true, ps.region_owns, reg_may);
    }
    if loc_candidates {
        for ci in 0..checked_fns.len {
            let fnode = checked_fns[ci];
            let n: const Node& = p.nodes[fnode];
            if (n.flags & (F_CHECKED | F_GENERIC | F_VALUE_USED)) != F_CHECKED { continue; }
            if (n.flags & (F_EXPORT | F_THREAD)) != 0 || fnode == p.entry { continue; }
            if (n.flags & F_EXTERN) != 0 { if !location_extern(p, fnode) { continue; } }
            else if !library_node(p, fnode) { continue; }
            p.nodes[fnode].flags |= F_LOCATED;
        }
    }
    p.unwinding = m.nonlocal_returns && mark_unwinding_functions(p);
    for ei in 0..extern_fns.len {
        let fnode = extern_fns[ei];
        if cg_intrinsic(p, fnode) == 0 {
            m.imports.push(CgImport { symbol: p.nodes[fnode].symbol, signature: cg_make_signature(p, m, fnode, false) });
        }
    }
    for index in 0..ordinary_count {
        let fnode = m.functions[index].node; let fsym = m.functions[index].symbol;
        let result = cg_result_type(p, fnode);
        if cg_type_kind(p, result) == TY_ARRAY && p.types[result].array_kind == A_VAR && !cg_nonlocal_target(p, fnode) {
            m.functions.push(CgFunction { node: fnode, symbol: fsym, elements: true });
        }
    }
    // Both ordinary bodies and element bodies are now registered. The first
    // position wins, and an element lookup falls back to the first body.
    // Every body has a thunk outside scalar mode, so a valid Wasm function
    // section's u32 count bounds every position below 2^31.
    m.functions_by_symbol.resize(p.symbols.len, CgFunctionIndex {});
    for index in 0..m.functions.len {
        let symbol = m.functions[index].symbol;
        if m.functions_by_symbol[symbol].first < 0 { m.functions_by_symbol[symbol].first = index as i32; }
        if m.functions[index].elements && m.functions_by_symbol[symbol].elements < 0 {
            m.functions_by_symbol[symbol].elements = index as i32;
        }
    }
    if ps.helpers.pool { m.pool_global = 0; }
    if (ps.helpers.formats & 1) != 0 { m.format_f32 = m.imports.len; m.imports.push(CgImport { signature: cg_host_signature(m, CG_FORMAT_F32), host: CG_FORMAT_F32 }); }
    if (ps.helpers.formats & 2) != 0 { m.format_f64 = m.imports.len; m.imports.push(CgImport { signature: cg_host_signature(m, CG_FORMAT_F64), host: CG_FORMAT_F64 }); }
    if m.pool_global >= 0 {
        for index in 0..ordinary_count { if ps.fn_reusable[index] { m.functions[index].arena_local = false; } }
    }
    loop {
        var changed = false;
        for index in 0..ordinary_count {
            if !m.functions[index].arena_local { continue; }
            let start = ps.fn_edge_start[index] as i64;
            let end = start + (ps.fn_edge_count[index] as i64);
            for ei in start..end {
                let target = cg_function(m, ps.arena_edges[ei] as i64);
                if target < 0 || !m.functions[target].arena_local {
                    m.functions[index].arena_local = false; changed = true; break;
                }
            }
        }
        if !changed { break; }
    }
    for index in ordinary_count..m.functions.len {
        let first = m.functions_by_symbol[m.functions[index].symbol].first as i64;
        if first >= 0 { m.functions[index].arena_local = m.functions[first].arena_local; }
    }
    var previous_captures = 0;
    while previous_captures < m.captures.len {
        previous_captures = m.captures.len;
        for item in m.functions { if !item.elements { cg_propagate_captures(p, m, item.node, p.nodes[item.node].right); } }
    }
    for capture in m.captures { p.symbols[capture.symbol].flags |= CG_ADDRESS_TAKEN; }
    m.start = m.imports.len + m.functions.len; m.allocator = m.start + 1; m.float_wrap = m.start + 2;
    if m.pool_global < 0 { m.regions_enabled = ps.region_ok && ps.region_owns; }
    var grows = false;
    for ty in p.types { if ty.kind == TY_ARRAY && (ty.array_kind == A_GROW || ty.array_kind == A_GROWSHRINK) { grows = true; } }
    if grows && !m.regions_enabled && !cg_unforwarded_module(p, m) { m.resolver = m.start + 3; m.forward_helper = m.start + 4; }
    if m.pool_global >= 0 { m.pool_global = 5; if m.resolver >= 0 { m.pool_global = 8; } }
    var thunk_base = m.start + 3; if m.resolver >= 0 { thunk_base += 2; }
    if m.regions_enabled {
        m.header_helper = thunk_base; thunk_base += 1;
        var frames = false; for type_id in 0..p.types.len { if cg_frame_owner(p, type_id) { frames = true; } }
        if frames { m.prefix_helper = thunk_base; thunk_base += 1; }
    }
    let allow_sroa_ret = p.optimization >= 2 && !m.nonlocal_returns && m.resolver < 0 && m.prefix_helper < 0;
    for i in 0..m.functions.len {
        let fnode = m.functions[i].node;
        m.region_functions.push(RegionFunction { node: fnode, entry: fnode == p.entry || (p.nodes[fnode].flags & F_EXPORT) != 0 });
        var count = 0; for capture in m.captures { if capture.function == fnode { count++; } }
        m.functions[i].capture_count = count;
        var sroa_ret: i64 = 0;
        if allow_sroa_ret && m.functions[i].sroa_return == 0 && !m.functions[i].elements && fnode != p.entry &&
           (p.nodes[fnode].flags & (F_EXPORT | F_EXTERN | F_VALUE_USED | CG_DISPATCH_ENTRY)) == 0 {
            let ret_ty = cg_result_type(p, fnode);
            if cg_type_kind(p, ret_ty) == TY_STRUCT { sroa_ret = cg_sroa_struct(p, ret_ty); }
        }
        m.functions[i].sroa_return = sroa_ret as i32;
        let sig = cg_make_signature(p, m, fnode, false, sroa_ret);
        m.functions[i].signature = sig;
        if (p.nodes[fnode].flags & F_VALUE_USED) != 0 {
            let csig = cg_make_signature(p, m, fnode, true);
            m.functions[i].closure_signature = csig;
            m.functions[i].table_index = m.thunk_count;
            m.thunk_count += 1;
        }
        m.functions[i].index = m.imports.len + i;
    }
    m.region_functions.push(RegionFunction { entry: true });
    m.ordinary_owners = cg_ordinary_owner_module(p, m);
    m.safe_refs = cg_safe_refs_module(p, m);
    if ps.helpers.raw_appends > 1 { m.raw_append_type = ps.helpers.raw_append_type; m.raw_append = thunk_base; thunk_base++; }
    if !m.ordinary_owners && m.resolver < 0 && ps.helpers.owner_indexes > 1 { m.owner_view = thunk_base; thunk_base++; }
    if !m.ordinary_owners && m.regions_enabled && ps.helpers.owner_mutations > 1 { m.update_length = thunk_base; thunk_base++; }
    if ps.helpers.slice_pool {
        m.next_data = cg_align(m.next_data, 8);
        m.span_scratch = m.next_data;
        m.next_data += 992;
        m.pool_state_fn = thunk_base; thunk_base++;
        m.spans_newnode = thunk_base; thunk_base++;
        m.spans_fix = thunk_base; thunk_base++;
        m.spans_delete = thunk_base; thunk_base++;
        m.spans_insert = thunk_base; thunk_base++;
        m.spans_near = thunk_base; thunk_base++;
        m.spans_release = thunk_base; thunk_base++;
        m.spans_alloc = thunk_base; thunk_base++;
        m.spans_free = thunk_base; thunk_base++;
        m.spans_regrow = thunk_base; thunk_base++;
    }
    for i in 0..m.functions.len { if m.functions[i].table_index >= 0 { m.functions[i].thunk = thunk_base + m.functions[i].table_index; } }
    if m.regions_enabled {
        m.host_reserve_type = cg_host_reserve_type(p, m);
        if m.host_reserve_type >= 0 { m.host_reserve = thunk_base + m.thunk_count; }
    }
    if m.functions.len == 1 && m.imports.len == 9 && m.pool_global < 0 && p.entry == m.functions[0].node && m.functions[0].capture_count == 0 {
        let entry = m.functions[0].node;
        var globals = false; for address in m.globals { if address >= 0 { globals = true; } }
        if !globals && (p.nodes[entry].flags & F_NONLOCAL) == 0 && p.nodes[entry].first < 0 && cg_result_type(p, entry) == TYPE_VOID && cg_scalar_body(p, entry, p.nodes[entry].right) { m.scalar = true; }
    }
}
fn cg_module_globals(p: Program&, m: CgModule&, out: u8[>..]&) {
    var count = 5; if m.resolver >= 0 && !m.scalar { count = 8; } if m.regions_enabled { count = 12; } if m.scalar { count = 1; }
    if m.pool_global >= 0 { count += 1; } wb_u(out, count);
    for index in 0..count {
        // Every global is an address or an address-sized number but the
        // region index (3) and the region count (8), which a pool global in
        // that place is not.
        var global_type = wa(); if index == 3 || (index == 8 && index != m.pool_global) { global_type = 0x7f; }
        wb_byte(out, global_type); wb_byte(out, 1); var initial = 0;
        if index == 0 { initial = cg_align(m.next_data, 8); if m.scalar || m.regions_enabled { initial = cg_align(m.next_data, 16); } }
        if index == 1 { initial = m.stack_limit; }
        if m.regions_enabled {
            if index == 3 { initial = m.global_region_count; }
            if index == 6 || index == 10 { initial = m.stack_limit; }
            if index == 8 { initial = m.region_count; }
            if index == 9 { initial = m.region_table_address; }
        } else if index == 7 { initial = -1; }
        if global_type == 0x7e { wb_i64(out, initial); } else { wb_i32(out, initial); } wb_byte(out, 0x0b);
    }
}
// Linear memory above the static data is the activation stack and then the
// data regions, one for each growable array that can be live at once. The
// stack takes an equal share. The regions divide the rest by weight: what
// --wasm-region-profile says a region was seen to need plus the mean of
// those, so that an unprofiled region gets an average share and, with no
// profile, all are equal. The region table is static data: where each region
// starts, and after the last where memory ends.
fn cg_layout_regions(p: Program&, m: CgModule&) {
    if !m.regions_enabled { return; }
    m.next_data = cg_align(m.next_data, wa_bytes()); let table = m.next_data;
    let stack_base = cg_align(table + ww(m.region_count + 1), 16); let bytes = p.maximum_pages * 65536;
    if stack_base >= bytes { cg_fail(p, -1, "static data exceeds linear memory limit"); return; }
    let share = ((bytes - stack_base) / (m.region_count + 1)) & -8;
    if m.region_count > 0 && share < ww(3) + 8 { cg_fail(p, -1, "data regions have no available storage"); return; }
    m.stack_limit = bytes - m.region_count * share;
    var profiled: i64 = 0; var known = p.region_profile.len; if known > m.region_count { known = m.region_count; }
    for index in 0..known { profiled += p.region_profile[index]; }
    var floor: i64 = 1; if m.region_count > 0 && profiled / m.region_count > 0 { floor = profiled / m.region_count; }
    // Weights are scaled down to sum to 65,536 or less, so that the bytes
    // that go with one unit of weight are a whole number that loses little.
    var scale = 0; while ((profiled + floor * m.region_count) >> scale) > 65536 { scale++; }
    var weights: i64 = 0;
    for index in 0..m.region_count {
        var weight = floor; if index < known { weight += p.region_profile[index]; }
        weight >>= scale; if weight < 1 { weight = 1; } weights += weight;
    }
    var unit: i64 = 0; if weights > 0 { unit = (m.region_count * share) / weights; }
    var encoded: u8[>..] = []; var base = m.stack_limit;
    for index in 0..m.region_count {
        for part in 0..wa_bytes() { wb_byte(encoded, base >> (part * 8)); }
        var weight = floor; if index < known { weight += p.region_profile[index]; }
        weight >>= scale; if weight < 1 { weight = 1; }
        let size = (unit * weight) & -8;
        if size < ww(3) + 8 { cg_fail(p, -1, "data regions have no available storage"); return; }
        base += size;
    }
    for part in 0..wa_bytes() { wb_byte(encoded, bytes >> (part * 8)); }
    // Placed by hand at the address reserved above: cg_data would share an
    // equal run of bytes elsewhere.
    let at = m.data.len; m.data.append(encoded);
    m.segments.push(CgSegment { address: table, start: at, count: encoded.len });
    m.next_data = table + encoded.len; m.region_table_address = table;
}
// A host import takes numbers and booleans, and what the module holds a
// slice or a reference as: an i64 of pointer and count, an i32 address (of a
// growable array, its control, which a host appends through with the
// exported region words; docs/TARGET.md). It returns numbers and booleans.
// An extern of a named dynamic library is an import like any other: the
// host stands for the library.
fn cg_importable(p: Program&, function: i64) -> bool {
    var param = p.nodes[function].first;
    while param >= 0 {
        let id = p.nodes[param].type_id; let kind = cg_type_kind(p, id);
        let passed = kind == TY_INT || kind == TY_FLOAT || kind == TY_BOOL || kind == TY_SLICE || kind == TY_REF && p.types[id].length_storage < 0;
        if !passed {
            var msg: u8[>..] = [];
            msg.append("wasm: host imports accept numeric, bool, slice and reference parameters only: `");
            msg.append(token_text(p, p.nodes[function].token)); msg.append("` parameter `");
            msg.append(token_text(p, p.nodes[param].token)); msg.append("` has type `");
            render_type_name(p, id, msg);
            msg.append("`\n  help: pass `const T&`, `T&`, or a slice `T[:]` across the Wasm host import `env.");
            msg.append(token_text(p, p.nodes[function].token)); msg.append("`, or compile with `--target native`");
            cg_fail(p, param, msg); return false;
        }
        param = p.nodes[param].next;
    }
    var results: i64[>..] = []; cg_function_results(p, function, results);
    for id in results {
        let kind = cg_type_kind(p, id);
        if kind != TY_INT && kind != TY_FLOAT && kind != TY_BOOL {
            var msg: u8[>..] = [];
            msg.append("wasm: host imports return numeric and bool values only: `");
            msg.append(token_text(p, p.nodes[function].token)); msg.append("` returns `");
            render_type_name(p, id, msg);
            msg.append("`\n  help: return via an out-reference parameter (e.g. `out: T&` or `out: u8[>..]&`), or compile with `--target native`");
            cg_fail(p, function, msg); return false;
        }
    }
    return true;
}
// The growable byte array type some host import takes a reference to: what
// goose.reserve appends to.
fn cg_host_reserve_type(p: Program&, m: CgModule&) -> i64 {
    for item in m.imports {
        if item.symbol < 0 { continue; }
        var param = p.nodes[p.symbols[item.symbol].node].first;
        while param >= 0 {
            let id = p.nodes[param].type_id;
            if cg_type_kind(p, id) == TY_REF {
                let target = p.types[id].element;
                if cg_type_kind(p, target) == TY_ARRAY && (p.types[target].array_kind == A_GROW || p.types[target].array_kind == A_GROWSHRINK) &&
                   cg_region_value(p, target) && cg_size(p, p.types[target].element) == 1 { return target; }
            }
            param = p.nodes[param].next;
        }
    }
    return -1;
}
fn cg_exportable(p: Program&, function: i64) -> bool {
    var param = p.nodes[function].first;
    while param >= 0 {
        let id = p.nodes[param].type_id;
        let kind = cg_type_kind(p, id);
        if kind != TY_INT && kind != TY_FLOAT && kind != TY_BOOL {
            var msg: u8[>..] = [];
            msg.append("wasm: public exports accept numeric and bool values only: `");
            msg.append(token_text(p, p.nodes[function].token)); msg.append("` parameter `");
            msg.append(token_text(p, p.nodes[param].token)); msg.append("` has type `");
            render_type_name(p, id, msg); msg.push('`');
            cg_fail(p, param, msg); return false;
        }
        param = p.nodes[param].next;
    }
    var results: i64[>..] = []; cg_function_results(p, function, results);
    for id in results {
        let kind = cg_type_kind(p, id);
        if kind != TY_INT && kind != TY_FLOAT && kind != TY_BOOL {
            var msg: u8[>..] = [];
            msg.append("wasm: public exports return numeric and bool values only: `");
            msg.append(token_text(p, p.nodes[function].token)); msg.append("` returns `");
            render_type_name(p, id, msg); msg.push('`');
            cg_fail(p, function, msg); return false;
        }
    }
    return true;
}
// The bundled hosts take byte builders through goose.reserve. Other approved
// imports only read their arguments or return scalars. Check the language ABI
// as well as the symbol before relying on that contract.
fn cg_bundled_host_param(p: Program&, id: i64, form: u8) -> bool {
    if id < 0 { return false; }
    let t: const Type& = p.types[id];
    if form == 'i' { return id == TYPE_I64; }
    if form == 's' { return t.kind == TY_SLICE && t.element == TYPE_U8 && t.flags == TF_CONST; }
    if t.kind != TY_REF || t.length_storage >= 0 || t.element < 0 { return false; }
    let target: const Type& = p.types[t.element];
    if form == 'o' { return t.flags == 0 && target.kind == TY_ARRAY && target.array_kind == A_GROW && target.element == TYPE_U8 && target.flags == 0; }
    if t.flags != TF_CONST { return false; }
    if form == 'p' { return t.element == TYPE_U8; }
    return form == 'b' && target.kind == TY_STRUCT && target.declaration >= 0 && library_node(p, target.declaration) &&
        token_is(p, p.nodes[target.declaration].token, "ByteSet") && target.size == 293;
}
fn cg_bundled_host_import(p: Program&, function: i64) -> bool {
    let name = cg_external_name(p, function);
    var params: const u8[:] = ""; var result = TYPE_VOID;
    if same_bytes(name, "system") { params = "p"; result = TYPE_I32; }
    else if !library_node(p, function) { return false; }
    else if same_bytes(name, "gs_find_pair") { params = "sbib"; result = TYPE_I64; }
    else if same_bytes(name, "gs_os_read_file") || same_bytes(name, "gs_os_getenv") { params = "so"; result = TYPE_BOOL; }
    else if same_bytes(name, "gs_os_write_file") { params = "ss"; result = TYPE_BOOL; }
    else if same_bytes(name, "gs_os_file_exists") || same_bytes(name, "gs_os_is_dir") { params = "s"; result = TYPE_BOOL; }
    else if same_bytes(name, "gs_os_write_stdout") || same_bytes(name, "gs_os_write_stderr") { params = "s"; }
    else if same_bytes(name, "gs_os_arg_count") || same_bytes(name, "gs_os_clock_ns") { result = TYPE_I64; }
    else if same_bytes(name, "gs_os_arg") { params = "io"; }
    else if same_bytes(name, "gs_os_resource_dir") { params = "o"; result = TYPE_BOOL; }
    else { return false; }
    var param = p.nodes[function].first;
    for form in params {
        if param < 0 || !cg_bundled_host_param(p, p.nodes[param].type_id, form) { return false; }
        param = p.nodes[param].next;
    }
    return param < 0 && cg_result_type(p, function) == result;
}
fn cg_safe_refs_import(p: Program&, function: i64) -> bool {
    if cg_bundled_host_import(p, function) { return true; }
    let ret = cg_result_type(p, function);
    if cg_type_kind(p, ret) == TY_REF { return false; }
    var param = p.nodes[function].first;
    while param >= 0 {
        let tid = p.nodes[param].type_id;
        if cg_type_kind(p, tid) == TY_REF {
            let target = p.types[tid].element;
            let tk = cg_type_kind(p, target);
            if tk != TY_INT && tk != TY_FLOAT && tk != TY_BOOL {
                if tk == TY_ARRAY {
                    let ek = cg_type_kind(p, p.types[target].element);
                    if ek != TY_INT && ek != TY_FLOAT && ek != TY_BOOL { return false; }
                } else { return false; }
            }
        }
        param = p.nodes[param].next;
    }
    return true;
}
fn cg_safe_refs_module(p: Program&, m: CgModule&) -> bool {
    if m.resolver >= 0 || m.prefix_helper >= 0 { return false; }
    for item in m.functions {
        if (p.nodes[item.node].flags & F_EXPORT) != 0 {
            var param = p.nodes[item.node].first;
            while param >= 0 {
                if cg_type_kind(p, p.nodes[param].type_id) == TY_REF { return false; }
                param = p.nodes[param].next;
            }
        }
    }
    for imp in m.imports {
        if imp.symbol >= 0 && !cg_safe_refs_import(p, p.symbols[imp.symbol].node) { return false; }
    }
    for id in 0..p.nodes.len {
        let n: const Node& = p.nodes[id];
        if n.kind == N_CAST && (n.flags & F_UNSIGNED) != 0 && (cg_type_kind(p, n.type_id) == TY_REF ||
            n.right >= 0 && cg_type_kind(p, p.nodes[n.right].type_id) == TY_REF) { return false; }
    }
    return true;
}
// Every nonzero control mode originates in a variable or runtime-limited
// array, including named result channels and packed record/enum tails. Scan
// the complete type table so those channels and aliases participate.
fn cg_ordinary_owner_module(p: Program&, m: CgModule&) -> bool {
    if !m.regions_enabled || p.library { return false; }
    for item in m.functions { if (p.nodes[item.node].flags & F_EXPORT) != 0 { return false; } }
    for imp in m.imports {
        if imp.symbol >= 0 && (!p.bundled_host || !cg_bundled_host_import(p, p.symbols[imp.symbol].node)) { return false; }
    }
    for t in p.types {
        if t.kind == TY_ARRAY && (t.array_kind == A_VAR || t.array_kind == A_LIMITED && t.count < 0) { return false; }
        if t.kind == TY_REF && t.length_storage >= 0 { return false; }
    }
    for id in 0..p.nodes.len {
        let n: const Node& = p.nodes[id];
        if n.kind == N_CAST && (n.flags & F_UNSIGNED) != 0 && (cg_type_kind(p, n.type_id) == TY_REF ||
            n.right >= 0 && cg_type_kind(p, p.nodes[n.right].type_id) == TY_REF) { return false; }
    }
    return true;
}
// With no mapping registrations, the publication head stays zero. A
// user/start body only saves it into a private mark or restores such a mark.
// All uses of that mark restore the head. Local allocation may reuse its slot
// after the last restore. Decode instructions so immediates cannot look like calls.
fn cg_without_publications(m: CgModule&, bytes: const u8[:], out: u8[>..]&, marks: bool) -> bool {
    var at = 0; let groups = wb_read_unsigned(bytes, at);
    for _ in 0..groups { wb_skip_leb(bytes, at); at++; }
    var copied = 0; var before = at; var prior = at;
    while at < bytes.len {
        let start = at; let op = bytes[at] as i64; at++;
        var omit = -1;
        var patch_at = -1;
        var patch_byte: u8 = 0;
        var drop_before = false;
        if op == 0x10 {
            let target = wb_read_unsigned(bytes, at);
            if target == m.header_helper || target == m.prefix_helper {
                if before == start || (bytes[before] != 0x41 && bytes[before] != 0x42) { return false; }
                omit = before;
                if target == m.header_helper {
                    if prior < before && bytes[prior] == 0x20 {
                        omit = prior;
                    } else if prior < before && bytes[prior] == 0x22 {
                        patch_at = prior; patch_byte = 0x21; omit = before;
                    } else {
                        drop_before = true; omit = before;
                    }
                }
            }
        } else if op == 0x23 || op == 0x24 {
            let index = wb_read_unsigned(bytes, at);
            if index == 11 {
                if !marks { return false; }
                if op == 0x23 {
                    // cg_mark_publications writes the head to a fresh local;
                    // peephole folding may have turned an unread set into drop
                    // or folded set+get into global.set 11 / local.tee+global.set 11.
                    if at == bytes.len { return false; }
                    if bytes[at] == 0x21 { at++; wb_skip_leb(bytes, at); omit = start; }
                    else if bytes[at] == 0x1a { at++; omit = start; }
                    else if bytes[at] == 0x24 {
                        var next_at = at + 1;
                        if wb_read_unsigned(bytes, next_at) != 11 { return false; }
                        at = next_at; omit = start;
                    } else if bytes[at] == 0x22 {
                        var next_at = at + 1; wb_skip_leb(bytes, next_at);
                        if next_at == bytes.len || bytes[next_at] != 0x24 { return false; }
                        next_at++;
                        if wb_read_unsigned(bytes, next_at) != 11 { return false; }
                        at = next_at; omit = start;
                    } else { return false; }
                } else {
                    // cg_restore_publications reads only that saved mark.
                    if before == start || bytes[before] != 0x20 { return false; }
                    omit = before;
                }
            }
        } else if op < 0x45 || op >= 0xfc { wb_read_operands(bytes, at, op); }
        if omit >= 0 {
            if patch_at >= 0 {
                out.append(bytes[copied..patch_at]); out.push(patch_byte); out.append(bytes[patch_at + 1..omit]);
            } else if drop_before {
                out.append(bytes[copied..omit]); out.push(0x1a);
            } else {
                out.append(bytes[copied..omit]);
            }
            copied = at;
            before = at; prior = at;
        } else { prior = before; before = start; }
    }
    if at != bytes.len { return false; }
    out.append(bytes[copied..]); return true;
}
fn cg_strip_publications(m: CgModule&, code: u8[>..]&) {
    let bytes: const u8[:] = code;
    var rewritten: u8[>..] = []; var body: u8[>..] = []; var at = 0;
    let count = wb_read_unsigned(bytes, at); wb_u(rewritten, count);
    for ordinal in 0..count {
        let header = at; let size = wb_read_unsigned(bytes, at); let end = at + size;
        let user_body = ordinal <= m.functions.len; let function = m.imports.len + ordinal;
        if user_body || function == m.raw_append || function == m.update_length || function == m.host_reserve {
            body.clear();
            if !cg_without_publications(m, bytes[at..end], body, user_body) { return; }
            wb_u(rewritten, body.len); rewritten.append(body);
        } else { rewritten.append(bytes[header..end]); }
        at = end;
    }
    if at != bytes.len { return; }
    code.clear(); code.append(rewritten);
}
fn generate_wasm(p: Program&, out: u8[>..]&) {
    // The checked layout decides the memory: 8-byte pointers are 64-bit
    // memory. Set before anything is collected, laid out or emitted.
    cg_wide = p.pointer_bytes == 8; cg_region_stats = p.region_stats;
    if p.diagnostics.len > 0 { return; }
    if cg_wide {
        // Up to 2^48 bytes; an engine has its own cap (V8: 262,144 pages).
        if p.initial_pages < 1 || p.initial_pages > p.maximum_pages || p.maximum_pages > 4294967296 {
            cg_fail(p, -1, "wasm: 64-bit linear memory requires 1 <= initial_pages <= maximum_pages <= 4294967296"); return;
        }
    } else if p.initial_pages < 1 || p.initial_pages > p.maximum_pages || p.maximum_pages > 65535 {
        cg_fail(p, -1, "wasm: linear memory requires 1 <= initial_pages <= maximum_pages <= 65535"); return;
    }
    if p.pointer_bytes != 4 && p.pointer_bytes != 8 { cg_fail(p, -1, "wasm: checked layout must use memory32 or memory64 pointers"); return; }
    var functions: CgFunction[>..] = []; var functions_by_symbol: CgFunctionIndex[>..] = []; var captures: CgCapture[>..] = []; var imports: CgImport[>..] = [];
    var signatures: CgSignature[>..] = []; var signature_bytes: u8[>..] = []; var signature_slots: i64[>..] = []; var signature_scratch: u8[>..] = [];
    var segments: CgSegment[>..] = []; var segment_slots: i64[>..] = []; var data: u8[>..] = []; var globals: i64[>..] = []; var global_regions: i64[>..] = []; var region_functions: RegionFunction[>..] = []; var region_calls: RegionCall[>..] = [];
    var region_memo: u8[>..] = []; var abort_helpers: CgAbortHelper[>..] = [];
    var binding_heads: i64[>..] = []; var binding_next: i64[>..] = [];
    var owners = SymbolOwners { heads: binding_heads, next: binding_next };
    index_symbol_owners(p, owners);
    var parameter_uses: CgParameterUse[>..] = [];
    var m = CgModule { parameter_uses: parameter_uses, functions: functions, functions_by_symbol: functions_by_symbol, captures: captures, imports: imports, signatures: signatures, signature_bytes: signature_bytes, signature_slots: signature_slots, signature_scratch: signature_scratch, segments: segments, segment_slots: segment_slots, data: data, globals: globals, global_regions: global_regions, symbol_owners: owners, region_functions: region_functions, region_calls: region_calls, region_memo: region_memo, abort_helpers: abort_helpers,
        stack_limit: (p.maximum_pages * 65536 / 2) & -8 };
    cg_collect(p, m); if p.diagnostics.len > 0 { return; }
    if m.scalar { m.resolver = -1; m.forward_helper = -1; m.host_reserve = -1; }
    cg_compute_header_pure(p, m);
    var slots: CgSlot[>..] = []; slots.resize(p.symbols.len, CgSlot {});
    var sc_events: WbEvent[>..] = []; var sc_code: u8[>..] = []; var sc_body: u8[>..] = []; var sc_locals: i64[>..] = [];
    var sc_addresses: CgFrameAddress[>..] = []; var sc_labels: i64[>..] = []; var sc_exits: CgExit[>..] = [];
    var sc_results: i64[>..] = []; var sc_destinations: i64[>..] = []; var sc_work: i64[>..] = []; var sc_raw_slots: i64[>..] = [];
    var sc_sequences: CgSequence[>..] = []; var sc_constructions: CgConstruction[>..] = [];
    var sc_construction_destinations: CgDestination[>..] = []; var sc_receiving: CgReceiving[>..] = []; var sc_defers: i64[>..] = []; var sc_hoists: CgHoist[>..] = [];
    var sc_thunk_code: u8[>..] = []; var sc_thunk_locals: i64[>..] = []; var sc_thunk_results: i64[>..] = [];
    var rw_locals_at: WbLocalAccess[>..] = []; var rw_first: i32[>..] = []; var rw_last: i32[>..] = [];
    var rw_written: i32[>..] = []; var rw_arm: i32[>..] = []; var rw_stamp: i32[>..] = []; var rw_loop_end: i32[>..] = [];
    var rw_frames: WbFrame[>..] = []; var rw_undo: i32[>..] = []; var rw_covers: i32[>..] = []; var rw_merged: i32[>..] = [];
    var rw_head: i32[>..] = []; var rw_next: i32[>..] = []; var rw_kinds: i64[>..] = []; var rw_kept: i64[>..] = [];
    var rw_ends: i32[>..] = []; var rw_reads: i32[>..] = []; var rw_action: u8[>..] = []; var rw_encoded: u8[>..] = [];
    var emit_scratch = CgEmitScratch {
        events: sc_events, code: sc_code, body: sc_body, locals: sc_locals, addresses: sc_addresses,
        labels: sc_labels, exits: sc_exits, results: sc_results, destinations: sc_destinations,
        work: sc_work, raw_slots: sc_raw_slots, sequences: sc_sequences,
        constructions: sc_constructions, construction_destinations: sc_construction_destinations,
        receiving: sc_receiving, defers: sc_defers, hoists: sc_hoists,
        thunk_code: sc_thunk_code, thunk_locals: sc_thunk_locals, thunk_results: sc_thunk_results,
        reuse: WbReuseScratch {
            locals_at: rw_locals_at, first: rw_first, last: rw_last, written: rw_written, arm: rw_arm, stamp: rw_stamp,
            loop_end: rw_loop_end, frames: rw_frames, undo: rw_undo, covers: rw_covers, merged: rw_merged,
            head: rw_head, next: rw_next, kinds: rw_kinds, kept: rw_kept, ends: rw_ends, reads: rw_reads, action: rw_action, encoded: rw_encoded,
        },
    };
    var body_count = m.functions.len + m.thunk_count + 3; if m.resolver >= 0 { body_count += 2; } if m.header_helper >= 0 { body_count++; } if m.prefix_helper >= 0 { body_count++; } if m.raw_append >= 0 { body_count++; } if m.owner_view >= 0 { body_count++; } if m.update_length >= 0 { body_count++; } if m.spans_alloc >= 0 { body_count += 10; } if m.host_reserve >= 0 { body_count++; } if m.scalar { body_count = m.functions.len + 1; }
    if !m.scalar { m.abort_base = m.imports.len + body_count; }
    var bodies: u8[>..] = [];
    var body: u8[>..] = [];
    for item, index in m.functions { body.clear(); cg_emit_function(p, m, item.node, index, item.elements, body, slots, emit_scratch); wb_u(bodies, body.len); wb_raw(bodies, body); }
    body.clear(); cg_emit_function(p, m, -1, m.functions.len, false, body, slots, emit_scratch); wb_u(bodies, body.len); wb_raw(bodies, body);
    if !m.scalar {
        body.clear(); cg_allocator_body(body); wb_u(bodies, body.len); wb_raw(bodies, body);
        body.clear(); cg_float_wrap_body(body); wb_u(bodies, body.len); wb_raw(bodies, body);
        if m.resolver >= 0 {
            body.clear(); cg_resolver_body(body); wb_u(bodies, body.len); wb_raw(bodies, body);
            body.clear(); cg_forward_helper_body(m, body); wb_u(bodies, body.len); wb_raw(bodies, body);
        }
        if m.header_helper >= 0 { body.clear(); cg_header_publish_body(body); wb_u(bodies, body.len); wb_raw(bodies, body); }
        if m.prefix_helper >= 0 { body.clear(); cg_prefix_mapping_body(body); wb_u(bodies, body.len); wb_raw(bodies, body); }
        let saved_abort = m.abort_base; m.abort_base = -1;
        if m.raw_append >= 0 { body.clear(); cg_emit_array_helper(p, m, body, m.raw_append); wb_u(bodies, body.len); wb_raw(bodies, body); }
        if m.owner_view >= 0 { body.clear(); cg_emit_array_helper(p, m, body, m.owner_view); wb_u(bodies, body.len); wb_raw(bodies, body); }
        if m.update_length >= 0 { body.clear(); cg_emit_array_helper(p, m, body, m.update_length); wb_u(bodies, body.len); wb_raw(bodies, body); }
        if m.spans_alloc >= 0 {
            body.clear(); cg_emit_pool_state_fn(p, m, body); wb_u(bodies, body.len); wb_raw(bodies, body);
            body.clear(); cg_emit_spans_newnode(p, m, body); wb_u(bodies, body.len); wb_raw(bodies, body);
            body.clear(); cg_emit_spans_fix(p, m, body); wb_u(bodies, body.len); wb_raw(bodies, body);
            body.clear(); cg_emit_spans_delete(p, m, body); wb_u(bodies, body.len); wb_raw(bodies, body);
            body.clear(); cg_emit_spans_insert(p, m, body); wb_u(bodies, body.len); wb_raw(bodies, body);
            body.clear(); cg_emit_spans_near(p, m, body); wb_u(bodies, body.len); wb_raw(bodies, body);
            body.clear(); cg_emit_spans_release(p, m, body); wb_u(bodies, body.len); wb_raw(bodies, body);
            body.clear(); cg_emit_spans_alloc(p, m, body); wb_u(bodies, body.len); wb_raw(bodies, body);
            body.clear(); cg_emit_spans_free(p, m, body); wb_u(bodies, body.len); wb_raw(bodies, body);
            body.clear(); cg_emit_spans_regrow(p, m, body); wb_u(bodies, body.len); wb_raw(bodies, body);
        }
        for item, i in m.functions { if item.table_index >= 0 { body.clear(); cg_emit_thunk(p, m, i, body, emit_scratch); wb_u(bodies, body.len); wb_raw(bodies, body); } }
        if m.host_reserve >= 0 {
            // This exported helper accepts a control address from the host.
            let ordinary = m.ordinary_owners; m.ordinary_owners = false;
            body.clear(); cg_emit_host_reserve(p, m, body); wb_u(bodies, body.len); wb_raw(bodies, body);
            m.ordinary_owners = ordinary;
        }
        m.abort_base = saved_abort;
        for ah in m.abort_helpers {
            body.clear(); wb_u(body, 0); wa_const(body, ah.address); wb_i32(body, ah.length);
            wb_op(body, 0x20, 0); wb_op(body, 0x10, CG_ABORT); wb_byte(body, 0); wb_byte(body, 0x0b);
            wb_u(bodies, body.len); wb_raw(bodies, body);
        }
    }
    let total_bodies = body_count + m.abort_helpers.len;
    var code: u8[>..] = []; wb_u(code, total_bodies); wb_raw(code, bodies);
    cg_bound_regions(p, m); cg_layout_regions(p, m);
    if m.next_data >= m.stack_limit { cg_fail(p, -1, "wasm: static storage overlaps the activation arena"); }
    if p.diagnostics.len > 0 { return; }
    if p.bundled_host && m.ordinary_owners && !m.scalar && !m.maps_headers { cg_strip_publications(m, code); }
    var empty: u8[>..] = []; var one_i32: u8[>..] = [0x7f]; var one_i64: u8[>..] = [0x7e]; var one_f64: u8[>..] = [0x7c];
    let start_signature = cg_signature(m, empty, empty); var allocator_signature = -1; var wrap_signature = -1; var header_signature = -1; var prefix_signature = -1; var append_signature = -1;
    // The helpers take and return addresses and address-sized numbers: the
    // allocator and the resolver (bytes or address) -> address, the header
    // publisher (header, word offset), the prefix mapper (address, bytes) ->
    // address, the raw append (control, data, byte count, line: i32).
    var one_address: u8[>..] = []; one_address.push(wa() as u8);
    if !m.scalar { allocator_signature = cg_signature(m, one_address, one_address); wrap_signature = cg_signature(m, one_f64, one_i64); }
    var forward_signature = -1;
    if m.forward_helper >= 0 { var fwd_args: u8[>..] = []; for _ in 0..3 { fwd_args.push(wa() as u8); } forward_signature = cg_signature(m, fwd_args, empty); }
    if m.header_helper >= 0 { var pair_address: u8[>..] = []; pair_address.push(wa() as u8); pair_address.push(wa() as u8); header_signature = cg_signature(m, pair_address, empty); }
    if m.prefix_helper >= 0 { var pair_address: u8[>..] = []; pair_address.push(wa() as u8); pair_address.push(wa() as u8); prefix_signature = cg_signature(m, pair_address, one_address); }
    if m.raw_append >= 0 { var append_args: u8[>..] = []; for part in 0..3 { append_args.push(wa() as u8); } append_args.push(0x7f); append_signature = cg_signature(m, append_args, empty); }
    var view_signature = -1;
    if m.owner_view >= 0 {
        var view_args: u8[>..] = []; view_args.push(wa() as u8); view_args.push(0x7f);
        var view_result: u8[>..] = []; view_result.push(ws() as u8); view_signature = cg_signature(m, view_args, view_result);
    }
    var update_signature = -1;
    if m.update_length >= 0 {
        var args: u8[>..] = []; args.push(wa() as u8); args.push(wa() as u8); args.push(0x7f);
        update_signature = cg_signature(m, args, empty);
    }
    var sp_new_sig = -1; var sp_fix_sig = -1; var sp_del_sig = -1; var sp_near_sig = -1; var sp_alloc_sig = -1; var sp_regrow_sig = -1;
    if m.spans_alloc >= 0 {
        sp_new_sig = cg_signature(m, one_address, one_i64);
        var a_fix: u8[>..] = []; a_fix.push(wa() as u8); a_fix.push(wa() as u8); for _ in 0..4 { a_fix.push(0x7e); }
        sp_fix_sig = cg_signature(m, a_fix, empty);
        var a_del: u8[>..] = []; a_del.push(wa() as u8); a_del.push(wa() as u8); a_del.push(0x7e); a_del.push(0x7e);
        sp_del_sig = cg_signature(m, a_del, empty);
        var a_near: u8[>..] = []; a_near.push(wa() as u8); a_near.push(0x7e); a_near.push(0x7e);
        sp_near_sig = cg_signature(m, a_near, empty);
        sp_alloc_sig = cg_signature(m, a_near, one_i64);
        var a_reg: u8[>..] = []; a_reg.push(wa() as u8); for _ in 0..4 { a_reg.push(0x7e); }
        sp_regrow_sig = cg_signature(m, a_reg, one_i64);
    }
    var reserve_signature = -1;
    if m.host_reserve >= 0 { var pair_address: u8[>..] = []; pair_address.push(wa() as u8); pair_address.push(wa() as u8); reserve_signature = cg_signature(m, pair_address, one_address); }
    var abort_signature = -1;
    if m.abort_helpers.len > 0 { abort_signature = cg_signature(m, one_i32, empty); }
    let out_mark = out.len;
    for b in [0, 97, 115, 109, 1, 0, 0, 0] { out.push(b as u8); }
    var section: u8[>..] = [];
    wb_u(section, m.signatures.len);
    for sig in m.signatures { wb_raw(section, m.signature_bytes[sig.start..sig.start + sig.count]); } wb_section(out, 1, section); section.clear();
    wb_u(section, m.imports.len);
    for item in m.imports {
        if item.host >= 0 { wb_import(section, "goose", cg_host_name(item.host), item.signature); }
        else { wb_import(section, "env", cg_external_name(p, p.symbols[item.symbol].node), item.signature); }
    }
    wb_section(out, 2, section); section.clear();
    wb_u(section, total_bodies); for item in m.functions { wb_u(section, item.signature); }
    wb_u(section, start_signature);
    if !m.scalar { wb_u(section, allocator_signature); wb_u(section, wrap_signature); if m.resolver >= 0 { wb_u(section, allocator_signature); wb_u(section, forward_signature); } if m.header_helper >= 0 { wb_u(section, header_signature); } if m.prefix_helper >= 0 { wb_u(section, prefix_signature); } if m.raw_append >= 0 { wb_u(section, append_signature); } if m.owner_view >= 0 { wb_u(section, view_signature); } if m.update_length >= 0 { wb_u(section, update_signature); } if m.spans_alloc >= 0 { wb_u(section, allocator_signature); wb_u(section, sp_new_sig); wb_u(section, sp_fix_sig); wb_u(section, sp_del_sig); wb_u(section, sp_fix_sig); wb_u(section, sp_near_sig); wb_u(section, sp_near_sig); wb_u(section, sp_alloc_sig); wb_u(section, sp_near_sig); wb_u(section, sp_regrow_sig); } for item in m.functions { if item.table_index >= 0 { wb_u(section, item.closure_signature); } } if m.host_reserve >= 0 { wb_u(section, reserve_signature); } for _ in m.abort_helpers { wb_u(section, abort_signature); } }
    wb_section(out, 3, section); section.clear();
    if !m.scalar { wb_u(section, 1); wb_byte(section, 0x70); wb_byte(section, 0); wb_u(section, m.thunk_count); wb_section(out, 4, section); section.clear(); }
    var initial_pages = p.initial_pages; let static_pages = (m.next_data + 65535) / 65536;
    if initial_pages < static_pages { initial_pages = static_pages; }
    // Limits with a maximum (0x01), of an i64-indexed memory (0x04) when wide.
    var memory_limits = 1; if cg_wide { memory_limits = 5; }
    wb_u(section, 1); wb_byte(section, memory_limits); wb_u(section, initial_pages); wb_u(section, p.maximum_pages); wb_section(out, 5, section); section.clear();
    cg_module_globals(p, m, section); wb_section(out, 6, section); section.clear();
    var export_count = 2; for item in m.functions { if (p.nodes[item.node].flags & F_EXPORT) != 0 { export_count++; } }
    // For a host: goose.reserve, which a host appends to a growable byte
    // array with, and, with --wasm-region-stats, the region table's address
    // and the number of regions, to report what each region held.
    let region_words = m.regions_enabled && !m.scalar && cg_region_stats;
    if region_words { export_count += 2; } if m.host_reserve >= 0 { export_count += 1; }
    wb_u(section, export_count); wb_export(section, "memory", 2, 0); wb_export(section, "_start", 0, m.start);
    if region_words { wb_export(section, "goose.region_table", 3, 9); wb_export(section, "goose.region_count", 3, 8); }
    if m.host_reserve >= 0 { wb_export(section, "goose.reserve", 0, m.host_reserve); }
    for item in m.functions {
        if (p.nodes[item.node].flags & F_EXPORT) != 0 {
            if item.capture_count > 0 { cg_fail(p, item.node, "wasm: public entrypoints cannot capture local storage"); }
            cg_exportable(p, item.node); wb_export(section, cg_external_name(p, item.node), 0, item.index);
        }
    }
    wb_section(out, 7, section); section.clear();
    if !m.scalar && m.thunk_count > 0 {
        wb_u(section, 1); wb_u(section, 0); wb_i32(section, 0); wb_byte(section, 0x0b); wb_u(section, m.thunk_count);
        for item in m.functions { if item.table_index >= 0 { wb_u(section, item.thunk); } } wb_section(out, 9, section); section.clear();
    }
    wb_section(out, 10, code);
    wb_u(section, m.segments.len);
    for segment in m.segments {
        wb_u(section, 0); wa_const(section, segment.address); wb_byte(section, 0x0b); wb_u(section, segment.count); wb_raw(section, m.data[segment.start..segment.start + segment.count]);
    }
    wb_section(out, 11, section); section.clear();
    if m.scalar { cg_scalar_metadata(p, m, out); }
    else if p.debug {
        var name_count = m.imports.len + m.functions.len + 3; if m.host_reserve >= 0 { name_count++; }
        wb_name(section, "name"); var names: u8[>..] = []; wb_u(names, name_count);
        for item, i in m.imports { wb_u(names, i); if item.host >= 0 { wb_name(names, cg_host_name(item.host)); } else { wb_name(names, cg_external_name(p, p.symbols[item.symbol].node)); } }
        for item in m.functions { wb_u(names, item.index); wb_name(names, token_text(p, p.nodes[item.node].token)); }
        wb_u(names, m.start); wb_name(names, "_start"); wb_u(names, m.allocator); wb_name(names, "goose.allocate"); wb_u(names, m.float_wrap); wb_name(names, "goose.float_wrap");
        if m.host_reserve >= 0 { wb_u(names, m.host_reserve); wb_name(names, "goose.reserve"); }
        wb_byte(section, 1); wb_u(section, names.len); wb_raw(section, names); wb_section(out, 0, section);
    }
    if p.diagnostics.len > 0 { out.resize(out_mark, 0); }
}

struct CgDecoded { value: i64, cursor: i64 }
fn cg_read_uleb(p: Program&, m: CgModule&, f: CgBody&, address: i64, node: i64) -> CgDecoded {
    // address and the cursor are addresses; the value is an i64, the shift and the byte i32.
    cg_get(f, address); let cursor = cg_save(f, wa()); wb_i64(f.code, 0); let value = cg_save(f, 0x7e); wb_i32(f.code, 0); let shift = cg_save(f, 0x7f);
    let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
    cg_get(f, cursor); wa_extend(f.code); wb_op(f.code, 0x3f, 0); wa_extend(f.code); wb_i64(f.code, 65536); wb_byte(f.code, 0x7e); wb_byte(f.code, 0x5a);
    cg_trap_if(p, m, f, node, "truncated varint image");
    cg_get(f, cursor); wb_mem(f.code, 0x2d, 0, 0); let byte = cg_save(f, 0x7f);
    cg_get(f, shift); wb_i32(f.code, 63); wb_byte(f.code, 0x4b);
    cg_get(f, shift); wb_i32(f.code, 63); wb_byte(f.code, 0x46); cg_get(f, byte); wb_i32(f.code, 254); wb_byte(f.code, 0x71); wb_byte(f.code, 0x45); wb_byte(f.code, 0x45); wb_byte(f.code, 0x71); wb_byte(f.code, 0x72);
    cg_trap_if(p, m, f, node, "varint image exceeds 64 bits");
    cg_get(f, value); cg_get(f, byte); wb_i32(f.code, 127); wb_byte(f.code, 0x71); wb_byte(f.code, 0xad); cg_get(f, shift); wb_byte(f.code, 0xad); wb_byte(f.code, 0x86); wb_byte(f.code, 0x84); cg_set(f, value);
    cg_get(f, cursor); wa_const(f.code, 1); wa_op(f.code, 0x6a); cg_set(f, cursor);
    cg_get(f, byte); wb_i32(f.code, 128); wb_byte(f.code, 0x71); wb_byte(f.code, 0x45); cg_branch(p, f, done, true);
    cg_get(f, shift); wb_i32(f.code, 7); wb_byte(f.code, 0x6a); cg_set(f, shift); cg_branch(p, f, again, false); cg_end(f); cg_end(f);
    return CgDecoded { value: value, cursor: cursor };
}
fn cg_load(p: Program&, m: CgModule&, f: CgBody&, id: i64, offset: i64) -> bool {
    if id < 0 || id >= p.types.len { return false; }
    wa_add(f.code, offset);
    cg_resolve_pointer(m, f); cg_canonical_address(m, f, cg_size(p, id));
    if cg_relative_type(p, id) { cg_read_relative(p, m, f, id, -1); return true; }
    if p.types[id].storage == 1 {
        let address = cg_save(f, wa()); let decoded = cg_read_uleb(p, m, f, address, -1);
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
    if pool < 0 { cg_get(f, slot); wa_extend(f.code); return cg_save(f, 0x7e); }
    if pool >= p.symbols.len || p.symbols[pool].type_id < 0 || cg_type_kind(p, p.symbols[pool].type_id) != TY_ARRAY {
        cg_fail(p, node, "wasm: relative reference has no checked array pool"); wb_i64(f.code, 0); return cg_save(f, 0x7e);
    }
    cg_symbol_address(p, m, f, pool, node); let owner = cg_save(f, wa());
    cg_array_pointer(p, m, f, p.symbols[pool].type_id, owner); cg_resolve_pointer(m, f);
    wa_extend(f.code); wb_i64(f.code, 1); wb_byte(f.code, 0x7d); return cg_save(f, 0x7e);
}
// Takes the address of the slot and leaves the reference, an address.
fn cg_read_relative(p: Program&, m: CgModule&, f: CgBody&, id: i64, node: i64) {
    let t: const Type& = p.types[id]; let slot = cg_save(f, wa()); let origin = cg_relative_origin(p, m, f, id, slot, node);
    if cg_image_owner(p, t.element) || cg_enum_image(p, t.element) {
        cg_fail(p, node, "wasm: a relative reference to a variable image requires a borrowed image view"); wa_const(f.code, 0); return;
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
    if optional { cg_get(f, offset); wb_byte(f.code, 0x50); cg_begin(f, 0x04, wa()); wa_const(f.code, 0); cg_control(f, 0x05); }
    cg_get(f, origin); cg_get(f, offset); wb_byte(f.code, 0x7c); let target = cg_save(f, 0x7e);
    // A 64-bit target is the address as it is: there is no narrower range
    // to leave, and an address outside memory traps where it is used.
    if cg_wide { cg_get(f, target); }
    else {
        cg_get(f, target); wb_i64(f.code, 0); wb_byte(f.code, 0x53); cg_get(f, target); wb_i64(f.code, 4294967295); wb_byte(f.code, 0x56); wb_byte(f.code, 0x72);
        cg_trap_if(p, m, f, node, "relative reference points outside wasm32 memory"); cg_get(f, target); wb_byte(f.code, 0xa7);
    }
    if optional { cg_end(f); }
}
fn cg_relative_offset(p: Program&, m: CgModule&, f: CgBody&, id: i64, slot: i64, value: i64, node: i64) -> i64 {
    let t: const Type& = p.types[id];
    let origin = cg_relative_origin(p, m, f, id, slot, node);
    cg_get(f, value); cg_resolve_pointer(m, f); let target = cg_save(f, wa());
    let optional = (t.flags & TF_OPTIONAL) != 0;
    if optional { cg_get(f, target); wa_op(f.code, 0x45); cg_begin(f, 0x04, 0x7e); wb_i64(f.code, 0); cg_control(f, 0x05); }
    cg_get(f, target); wa_extend(f.code); cg_get(f, origin); wb_byte(f.code, 0x7d);
    if optional { cg_end(f); }
    let offset = cg_save(f, 0x7e);
    if optional {
        cg_get(f, target); wa_op(f.code, 0x45); wb_byte(f.code, 0x45); cg_get(f, offset); wb_byte(f.code, 0x50); wb_byte(f.code, 0x71);
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
    let t: const Type& = p.types[id];
    cg_get(f, destination); cg_resolve_pointer(m, f); let slot = cg_save(f, wa());
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
    cg_get(f, address); let cursor = cg_save(f, wa()); cg_get(f, value); let remaining = cg_save(f, 0x7e);
    let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
    cg_get(f, remaining); wb_byte(f.code, 0xa7); wb_i32(f.code, 127); wb_byte(f.code, 0x71); let byte = cg_save(f, 0x7f);
    cg_get(f, remaining); wb_i64(f.code, 7); wb_byte(f.code, 0x88); cg_set(f, remaining);
    cg_get(f, remaining); wb_i64(f.code, 0); wb_byte(f.code, 0x52); cg_begin(f, 0x04, 0x40); cg_get(f, byte); wb_i32(f.code, 128); wb_byte(f.code, 0x72); cg_set(f, byte); cg_end(f);
    cg_get(f, cursor); cg_get(f, byte); wb_mem(f.code, 0x3a, 0, 0); cg_get(f, cursor); wa_const(f.code, 1); wa_op(f.code, 0x6a); cg_set(f, cursor);
    cg_get(f, remaining); wb_byte(f.code, 0x50); cg_branch(p, f, done, true); cg_branch(p, f, again, false); cg_end(f); cg_end(f); return cursor;
}
fn cg_write_varint(p: Program&, f: CgBody&, address: i64, value: i64) -> i64 {
    cg_get(f, value); wb_i64(f.code, 1); wb_byte(f.code, 0x86); cg_get(f, value); wb_i64(f.code, 63); wb_byte(f.code, 0x87); wb_byte(f.code, 0x85);
    let encoded = cg_save(f, 0x7e); return cg_write_uleb(p, f, address, encoded);
}
fn cg_walk_elements(p: Program&, m: CgModule&, f: CgBody&, base: i64, count: i64, node: i64) -> i64 {
    cg_get(f, base); let cursor = cg_save(f, wa()); wb_i64(f.code, 0); let index = cg_save(f, 0x7e);
    let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
    cg_get(f, index); cg_get(f, count); wb_byte(f.code, 0x5a); cg_branch(p, f, done, true);
    let decoded = cg_read_uleb(p, m, f, cursor, node); cg_get(f, decoded.cursor); cg_set(f, cursor);
    cg_get(f, index); wb_i64(f.code, 1); wb_byte(f.code, 0x7c); cg_set(f, index); cg_branch(p, f, again, false); cg_end(f); cg_end(f); return cursor;
}
recursive fn cg_array_from_view(p: Program&, m: CgModule&, f: CgBody&, to: i64, node: i64) {
    // Takes a slice and leaves the address of the array made of it. The
    // count, the pointers and the byte count are address-sized.
    let view = cg_save(f, ws()); let destination = cg_temporary(p, f, to); let element = p.types[to].element;
    cg_get(f, view); ws_len(f.code); let count = cg_save(f, wa());
    cg_get(f, destination); cg_clear_bytes(p, f, cg_size(p, to));
    var pointer = destination;
    if cg_owner(p, to) { pointer = cg_owner_image(p, m, f, to, destination, count, count, node);
    } else {
        cg_get(f, count); wa_const(f.code, p.types[to].count); wa_op(f.code, 0x4b); cg_trap_if(p, m, f, node, "limited array capacity exceeded");
        if p.types[to].array_kind == A_LIMITED { cg_get(f, destination); cg_get(f, count); cg_length_store(p, f, to); }
        cg_get(f, destination); wa_const(f.code, cg_static_prefix(p, to)); wa_op(f.code, 0x6a); pointer = cg_save(f, wa());
    }
    cg_get(f, view); ws_ptr(f.code); let source = cg_save(f, wa());
    var bytes = -1;
    if p.types[element].storage == 1 {
        cg_get(f, count); wa_extend(f.code); let count64 = cg_save(f, 0x7e); let end = cg_walk_elements(p, m, f, source, count64, node);
        cg_get(f, end); cg_get(f, source); wa_op(f.code, 0x6b); bytes = cg_save(f, wa());
    } else { cg_get(f, count); wa_const(f.code, cg_size(p, element)); wa_op(f.code, 0x6c); bytes = cg_save(f, wa()); }
    cg_get(f, pointer); cg_get(f, source); cg_get(f, bytes); wb_copy(f.code);
    if cg_owner(p, to) {
        if m.regions_enabled && !f.scratch { cg_get(f, pointer); cg_get(f, bytes); wa_op(f.code, 0x6a); let top = cg_save(f, wa()); cg_region_publish(f, destination, top); }
        else if p.types[to].array_kind != A_VAR { cg_get(f, destination); cg_get(f, pointer); cg_get(f, bytes); wa_op(f.code, 0x6a); wc_store(f.code, 4); }
    }
    cg_get(f, destination);
}
fn cg_uleb_width(p: Program&, f: CgBody&, value: i64) -> i64 {
    // The width is a byte count: an address-sized local.
    cg_get(f, value); let remaining = cg_save(f, 0x7e); wa_const(f.code, 1); let width = cg_save(f, wa());
    let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
    cg_get(f, remaining); wb_i64(f.code, 128); wb_byte(f.code, 0x54); cg_branch(p, f, done, true);
    cg_get(f, remaining); wb_i64(f.code, 7); wb_byte(f.code, 0x88); cg_set(f, remaining);
    cg_get(f, width); wa_const(f.code, 1); wa_op(f.code, 0x6a); cg_set(f, width); cg_branch(p, f, again, false); cg_end(f); cg_end(f); return width;
}
// The length of the array of the control in the local header, address-sized.
// Its image, by the control's mode word, starts with the length in 1, 2, 4
// or 8 bytes (modes 1 to 4), as a ULEB128 (6), or, for a runtime-limited
// array (5), with two address-sized words, the capacity and the length.
fn cg_owner_read_length(p: Program&, m: CgModule&, f: CgBody&, header: i64, node: i64) {
    if m.ordinary_owners { cg_get(f, header); wc_load(f.code, 1); return; }
    // Generated helpers retain the inline decoder. Ordinary functions can
    // take the length from the shared view on the encoded path.
    if m.owner_view >= 0 && f.diagnostic_line < 0 {
        cg_get(f, header); wc_load(f.code, 5); wa_op(f.code, 0x45); cg_begin(f, 0x04, wa());
        cg_get(f, header); wc_load(f.code, 1); cg_control(f, 0x05);
        cg_get(f, header); cg_diagnostic_line(p, f, node); wb_op(f.code, 0x10, m.owner_view); ws_len(f.code);
        cg_end(f); return;
    }
    cg_get(f, header); wc_load(f.code, 5); let mode = cg_save(f, wa());
    cg_get(f, header); wc_load(f.code, 1); let result = cg_save(f, wa());
    let done = cg_begin(f, 0x02, 0x40);
    cg_get(f, mode); wa_op(f.code, 0x45); cg_branch(p, f, done, true);
    for selected in 1..7 {
        cg_get(f, mode); wa_const(f.code, selected); wa_op(f.code, 0x46); cg_begin(f, 0x04, 0x40);
        cg_get(f, header); wc_load(f.code, 4); let image = cg_save(f, wa());
        if selected == 6 {
            let decoded = cg_read_uleb(p, m, f, image, node);
            if cg_wide { cg_get(f, decoded.value); }
            else {
                cg_get(f, decoded.value); wb_i64(f.code, 4294967295); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array image length exceeds wasm32 range");
                cg_get(f, decoded.value); wb_byte(f.code, 0xa7);
            }
        } else if cg_wide {
            cg_get(f, image);
            if selected == 1 { wb_mem(f.code, 0x31, 0, 0); } else if selected == 2 { wb_mem(f.code, 0x33, 0, 0); }
            else if selected == 3 { wb_mem(f.code, 0x35, 0, 0); } else if selected == 5 { wb_mem(f.code, 0x29, 0, ww(1)); }
            else { wb_mem(f.code, 0x29, 0, 0); }
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
// The address of the first element: past the image's prefix.
fn cg_owner_read_base(p: Program&, m: CgModule&, f: CgBody&, header: i64, node: i64) {
    if m.ordinary_owners { cg_get(f, header); wc_load(f.code, 0); return; }
    cg_get(f, header); wc_load(f.code, 5); let mode = cg_save(f, wa());
    cg_get(f, header); wc_load(f.code, 0); let result = cg_save(f, wa());
    let done = cg_begin(f, 0x02, 0x40);
    cg_get(f, mode); wa_op(f.code, 0x45); cg_branch(p, f, done, true);
    for selected in 1..7 {
        cg_get(f, mode); wa_const(f.code, selected); wa_op(f.code, 0x46); cg_begin(f, 0x04, 0x40);
        cg_get(f, header); wc_load(f.code, 4); let image = cg_save(f, wa());
        if selected == 6 { let decoded = cg_read_uleb(p, m, f, image, node); cg_get(f, decoded.cursor); }
        else { cg_get(f, image); var width = 1; if selected == 2 { width = 2; } if selected == 3 { width = 4; } if selected == 4 { width = 8; } if selected == 5 { width = ww(2); } wa_const(f.code, width); wa_op(f.code, 0x6a); }
        cg_set(f, result); cg_branch(p, f, done, false); cg_end(f);
    }
    cg_end(f); cg_get(f, result); cg_resolve_pointer(m, f);
}
fn cg_owner_read_capacity(p: Program&, m: CgModule&, f: CgBody&, header: i64) {
    if m.ordinary_owners { cg_get(f, header); wc_load(f.code, 3); return; }
    // Address-sized: a runtime-limited image's first word, or the control's capacity word.
    cg_get(f, header); wc_load(f.code, 5); wa_const(f.code, 5); wa_op(f.code, 0x46); cg_begin(f, 0x04, wa());
    cg_get(f, header); wc_load(f.code, 4); if cg_wide { wb_mem(f.code, 0x29, 0, 0); } else { wb_mem(f.code, 0x28, 0, 0); }
    cg_control(f, 0x05); cg_get(f, header); wc_load(f.code, 3); cg_end(f);
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
    cg_get(f, header); cg_clear_bytes(p, f, wc_bytes());
    cg_get(f, header); cg_get(f, entry); wc_store(f.code, 0);
    cg_get(f, header); cg_get(f, source_header); wc_load(f.code, 2); wc_store(f.code, 2);
    if cg_enum_image(p, id) { cg_set_enum_anchor(f, owner, entry); }
    else if cg_image_owner(p, id) { cg_set_record_anchor(p, m, f, id, owner, entry, node); }
    return cg_destination(f, id, owner, parent.lifetime, elements, normal, escape, parent.entry, parent.construction);
}
fn cg_region_varint(p: Program&, m: CgModule&, f: CgBody&, header: i64, value: i64, node: i64) -> i64 {
    cg_get(f, value); wb_i64(f.code, 1); wb_byte(f.code, 0x86); cg_get(f, value); wb_i64(f.code, 63); wb_byte(f.code, 0x87); wb_byte(f.code, 0x85); let encoded = cg_save(f, 0x7e);
    let width = cg_uleb_width(p, f, encoded); cg_get(f, width); wa_extend(f.code); let bytes = cg_save(f, 0x7e); cg_region_reserve(p, m, f, header, bytes, node);
    let start = cg_region_cursor(f, header); let top = cg_write_uleb(p, f, start, encoded); cg_region_publish(f, header, top); return start;
}
fn cg_region_relative(p: Program&, m: CgModule&, f: CgBody&, id: i64, header: i64, value: i64, node: i64) -> i64 {
    let start = cg_region_cursor(f, header); let encoded = cg_relative_encoding(p, m, f, id, start, value, node);
    let width = cg_uleb_width(p, f, encoded); cg_get(f, width); wa_extend(f.code); let bytes = cg_save(f, 0x7e); cg_region_reserve(p, m, f, header, bytes, node);
    let top = cg_write_uleb(p, f, start, encoded); cg_region_publish(f, header, top); return start;
}
fn cg_validate_region_array(p: Program&, m: CgModule&, f: CgBody&, id: i64, header: i64, node: i64) {
    cg_owner_read_base(p, m, f, header, node); let base = cg_save(f, wa()); cg_get(f, header); wc_load(f.code, 2); let limit = cg_save(f, wa());
    cg_get(f, base); cg_get(f, limit); wa_op(f.code, 0x4b); cg_trap_if(p, m, f, node, "array image exceeds data region");
    cg_owner_read_length(p, m, f, header, node); let count = cg_save(f, wa()); var extent = count;
    if p.types[id].array_kind == A_LIMITED {
        cg_owner_read_capacity(p, m, f, header); extent = cg_save(f, wa());
        cg_get(f, count); cg_get(f, extent); wa_op(f.code, 0x4b); cg_trap_if(p, m, f, node, "array image length exceeds capacity");
    }
    var stride = cg_size(p, p.types[id].element); if p.types[p.types[id].element].storage == 1 { stride = 1; }
    cg_get(f, extent); wa_extend(f.code); cg_get(f, limit); cg_get(f, base); wa_op(f.code, 0x6b); wa_extend(f.code); wb_i64(f.code, stride); wb_byte(f.code, 0x80); wb_byte(f.code, 0x56);
    cg_trap_if(p, m, f, node, "array image exceeds data region");
    cg_get(f, base); cg_get(f, extent); wa_const(f.code, stride); wa_op(f.code, 0x6c); wa_op(f.code, 0x6a); let top = cg_save(f, wa()); cg_ensure_memory(p, m, f, top, node);
}
fn cg_set_array_anchor(p: Program&, f: CgBody&, header: i64, anchor: i64, id: i64) {
    var width = p.types[id].length_storage; var mode = 4;
    if p.types[id].array_kind == A_VAR && width == 0 { width = 1; mode = 6; }
    if mode != 6 {
        if p.types[id].array_kind == A_LIMITED { width = ww(2); mode = 5; }
        else if width == 1 { mode = 1; } else if width == 2 { mode = 2; } else if width == 4 { mode = 3; }
    }
    cg_get(f, header); cg_get(f, anchor); wc_store(f.code, 4);
    cg_get(f, header); wa_const(f.code, mode); wc_store(f.code, 5);
    cg_get(f, header); cg_get(f, anchor); wa_const(f.code, width); wa_op(f.code, 0x6a); wc_store(f.code, 0);
    cg_get(f, header); wa_const(f.code, 0); wc_store(f.code, 1);
    cg_get(f, header); if mode == 6 { wa_const(f.code, 1); } else { wa_const(f.code, 0); } wc_store(f.code, 3);
}
fn cg_value_array_receiver(p: Program&, f: CgBody&, node: i64, destination: i64) -> bool {
    let n: const Node& = p.nodes[node]; let target = f.construction_destinations[destination];
    if n.kind != N_CALL || n.symbol < 0 || (p.symbols[n.symbol].flags & S_FUNCTION) == 0 { return false; }
    let function = p.symbols[n.symbol].node; let natural = cg_result_type(p, function);
    if !cg_owner(p, natural) || p.types[natural].array_kind != A_VAR || !cg_nonlocal_target(p, function) { return false; }
    let to: const Type& = p.types[target.type_id]; return target.elements || to.array_kind == A_GROW || to.array_kind == A_GROWSHRINK || to.array_kind == A_VAR && to.length_storage != p.types[natural].length_storage;
}
fn cg_finish_value_array(p: Program&, m: CgModule&, f: CgBody&, source: i64, destination: i64, node: i64) {
    let target = f.construction_destinations[destination]; let header = target.header; let id = target.type_id;
    cg_owner_read_length(p, m, f, source, node); let count = cg_save(f, wa()); cg_check_array_length(p, m, f, id, count, node);
    cg_get(f, source); wc_load(f.code, 4); let anchor = cg_save(f, wa());
    cg_get(f, source); wc_load(f.code, 5); wa_op(f.code, 0x45); cg_begin(f, 0x04, 0x40);
    cg_owner_read_base(p, m, f, source, node); cg_set(f, anchor); cg_end(f);
    cg_owner_read_base(p, m, f, source, node); let elements = cg_save(f, wa()); let finish = cg_region_cursor(f, source);
    cg_get(f, elements); cg_get(f, finish); wa_op(f.code, 0x4b); cg_trap_if(p, m, f, node, "invalid array image adaptation span");
    cg_get(f, finish); cg_get(f, elements); wa_op(f.code, 0x6b); let bytes = cg_save(f, wa());
    var width = 0; let image = p.types[id].array_kind == A_VAR && !target.elements; var prefix = -1;
    if image && p.types[id].length_storage == 0 { cg_get(f, count); wa_extend(f.code); let wide = cg_save(f, 0x7e); prefix = cg_uleb_width(p, f, wide); }
    else { if image { width = p.types[id].length_storage; } wa_const(f.code, width); prefix = cg_save(f, wa()); }
    cg_get(f, anchor); wa_extend(f.code); cg_get(f, prefix); wa_extend(f.code); wb_byte(f.code, 0x7c); cg_get(f, bytes); wa_extend(f.code); wb_byte(f.code, 0x7c); let end64 = cg_save(f, 0x7e);
    cg_get(f, end64); cg_get(f, header); wc_load(f.code, 2); wa_extend(f.code); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "data region exhausted");
    cg_get(f, end64); wa_wrap(f.code); let top = cg_save(f, wa()); cg_ensure_memory(p, m, f, top, node);
    cg_get(f, anchor); cg_get(f, prefix); wa_op(f.code, 0x6a); let pointer = cg_save(f, wa());
    cg_get(f, pointer); cg_get(f, elements); cg_get(f, bytes); wb_copy(f.code);
    if image {
        if p.types[id].length_storage == 0 {
            cg_get(f, header); cg_get(f, anchor); wc_store(f.code, 4); cg_get(f, header); cg_get(f, pointer); wc_store(f.code, 0);
            cg_get(f, header); wa_const(f.code, 6); wc_store(f.code, 5); cg_get(f, header); cg_get(f, prefix); wc_store(f.code, 3);
        } else { cg_set_array_anchor(p, f, header, anchor, id); }
    } else {
        cg_get(f, header); wa_const(f.code, 0); wc_store(f.code, 4); cg_get(f, header); wa_const(f.code, 0); wc_store(f.code, 5);
    }
    cg_owner_set_length(p, m, f, header, count, node); cg_region_publish(f, header, top);
}
fn cg_finish_region_array(p: Program&, m: CgModule&, f: CgBody&, original: i64, stage: i64, start: i64, id: i64, elements: bool, land: bool, node: i64) {
    let image = p.types[id].array_kind == A_VAR && !elements || p.types[id].array_kind == A_LIMITED;
    cg_owner_read_length(p, m, f, stage, node); let count = cg_save(f, wa());
    if land {
        let finish = cg_region_cursor(f, original); cg_get(f, original); wc_load(f.code, 0); let anchor = cg_save(f, wa());
        if image {
            cg_get(f, original); wc_load(f.code, 5); wa_truth(f.code); cg_begin(f, 0x04, 0x40);
            cg_get(f, original); wc_load(f.code, 4); cg_set(f, anchor); cg_end(f);
        }
        cg_get(f, start); cg_get(f, anchor); wa_op(f.code, 0x49); cg_get(f, start); cg_get(f, finish); wa_op(f.code, 0x4b); wb_byte(f.code, 0x72);
        cg_get(f, finish); cg_get(f, original); wc_load(f.code, 2); wa_op(f.code, 0x4b); wb_byte(f.code, 0x72); cg_trap_if(p, m, f, node, "invalid array image landing span");
        cg_get(f, finish); cg_get(f, start); wa_op(f.code, 0x6b); let bytes = cg_save(f, wa());
        if !image {
            let element = p.types[id].element;
            if p.types[element].storage == 1 {
                cg_get(f, count); wa_extend(f.code); let wide = cg_save(f, 0x7e); let end = cg_walk_elements(p, m, f, start, wide, node);
                cg_get(f, end); cg_get(f, finish); wa_op(f.code, 0x4b);
            } else {
                cg_get(f, count); wa_extend(f.code); wb_i64(f.code, cg_size(p, element)); wb_byte(f.code, 0x7e); cg_get(f, bytes); wa_extend(f.code); wb_byte(f.code, 0x56);
            }
            cg_trap_if(p, m, f, node, "invalid nonlocal landing length");
        }
        cg_get(f, anchor); cg_get(f, start); cg_get(f, bytes); wb_copy(f.code);
        if image {
            if p.types[id].length_storage == 0 {
                cg_get(f, original); wc_load(f.code, 5); wa_op(f.code, 0x45); cg_begin(f, 0x04, 0x40);
                cg_get(f, original); cg_get(f, stage); wc_load(f.code, 3); wc_store(f.code, 3); cg_end(f);
            }
            cg_get(f, original); cg_get(f, stage); wc_load(f.code, 5); wc_store(f.code, 5);
            cg_get(f, original); cg_get(f, anchor); wc_store(f.code, 4);
        } else { cg_get(f, original); cg_get(f, count); wc_store(f.code, 1); }
        cg_get(f, anchor); cg_get(f, bytes); wa_op(f.code, 0x6a); let top = cg_save(f, wa()); cg_region_publish(f, original, top);
    } else if image {
        cg_get(f, original); wc_load(f.code, 5); wa_op(f.code, 0x45); cg_begin(f, 0x04, 0x40);
        for word in [0, 1, 3, 4, 5] { cg_get(f, original); cg_get(f, stage); wc_load(f.code, word); wc_store(f.code, word); }
        cg_end(f);
    } else { cg_get(f, original); cg_get(f, count); wc_store(f.code, 1); }
    if image {
        cg_get(f, original); cg_owner_read_base(p, m, f, original, node); wc_store(f.code, 0);
        cg_get(f, original); cg_owner_read_length(p, m, f, original, node); wc_store(f.code, 1);
        if p.types[id].array_kind == A_LIMITED { cg_get(f, original); cg_owner_read_capacity(p, m, f, original); wc_store(f.code, 3); }
    }
    cg_publish_header(m, f, original, ww(1)); cg_validate_region_array(p, m, f, id, original, node);
}
fn cg_close_constructor(f: CgBody&, state: i64, opened: bool, node: i64, destination: i64, raw: i64) {
    if opened { f.constructions[state].open -= 1; }
    f.active_node = node; f.active_destination = destination; f.raw_node = raw;
}
fn cg_set_enum_anchor(f: CgBody&, owner: i64, anchor: i64) {
    for word in [0, 4] { cg_get(f, owner); cg_get(f, anchor); wc_store(f.code, word); }
    for word in [1, 3, 5] { cg_get(f, owner); wa_const(f.code, 0); wc_store(f.code, word); }
}
fn cg_decode_enum(p: Program&, m: CgModule&, f: CgBody&, id: i64, owner: i64, node: i64) {
    let bytes = cg_enum_image_bytes(p, m, f, id, owner, node);
    cg_get(f, owner); cg_get(f, bytes); wc_store(f.code, 1);
}
fn cg_finish_enum(p: Program&, m: CgModule&, f: CgBody&, id: i64, owner: i64, start: i64, land: bool, node: i64) {
    if land {
        cg_get(f, owner); wc_load(f.code, 0); let base = cg_save(f, wa()); let finish = cg_region_cursor(f, owner);
        cg_get(f, finish); cg_get(f, start); wa_op(f.code, 0x6b); let bytes = cg_save(f, wa());
        cg_get(f, base); wa_extend(f.code); cg_get(f, bytes); wa_extend(f.code); wb_byte(f.code, 0x7c); let top64 = cg_save(f, 0x7e);
        cg_get(f, start); cg_get(f, finish); wa_op(f.code, 0x4b); cg_get(f, top64); cg_get(f, owner); wc_load(f.code, 2); wa_extend(f.code); wb_byte(f.code, 0x56); wb_byte(f.code, 0x72); cg_trap_if(p, m, f, node, "invalid enum image landing span");
        cg_get(f, top64); wa_wrap(f.code); let top = cg_save(f, wa()); cg_ensure_memory(p, m, f, top, node);
        cg_get(f, base); cg_get(f, start); cg_get(f, bytes); wb_copy(f.code); cg_region_publish(f, owner, top);
    }
    cg_decode_enum(p, m, f, id, owner, node);
}
recursive fn cg_packed_integer_image(p: Program&, id: i64) -> bool {
    if cg_type_kind(p, id) == TY_INT { return p.types[id].storage == 0; }
    if cg_type_kind(p, id) == TY_ARRAY { return p.types[id].array_kind == A_FIXED && p.types[id].count > 0 && cg_packed_integer_image(p, p.types[id].element); }
    if cg_type_kind(p, id) != TY_STRUCT || cg_has_owner(p, id) || p.types[id].first < 0 { return false; }
    var field = p.types[id].first; while field >= 0 { let n: const Node& = p.nodes[field]; if (n.flags & F_PAD) != 0 || !cg_packed_integer_image(p, n.type_id) { return false; } field = n.next; } return true;
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
    cg_get(f, header); cg_clear_bytes(p, f, wc_bytes()); cg_get(f, header); cg_get(f, owner); wc_load(f.code, 2); wc_store(f.code, 2);
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
    if count > 0 { cg_get(f, cursor); cg_get(f, source); wa_const(f.code, count); wb_copy(f.code); } cg_region_publish(f, owner, top);
}
recursive fn cg_construct_enum_captured(p: Program&, m: CgModule&, f: CgBody&, natural: i64, source: i64, destination: i64, node: i64) {
    let target = f.construction_destinations[destination]; let id = target.type_id; let owner = target.header; var from = natural;
    while cg_type_kind(p, from) == TY_REF { from = p.types[from].element; }
    if cg_enum_image(p, from) {
        let count = cg_enum_image_bytes(p, m, f, from, source, node); cg_get(f, count); wa_extend(f.code); let bytes = cg_save(f, 0x7e); let top = cg_region_reserve(p, m, f, owner, bytes, node); let cursor = cg_region_cursor(f, owner);
        cg_get(f, cursor); cg_get(f, source); wc_load(f.code, 0); cg_get(f, count); wb_copy(f.code); cg_region_publish(f, owner, top); cg_decode_enum(p, m, f, id, owner, node); return;
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
        let receiving = cg_prepare_enum_payload(p, m, f, destination, variant, node, true); cg_get(f, source); wa_const(f.code, p.types[from].length_storage); wa_op(f.code, 0x6a); let payload = cg_save(f, wa());
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
                let n: const Node& = p.nodes[field]; let value = cg_record_initializer(p, node, field); var scalar = -1;
                if (n.flags & F_PAD) == 0 && value >= 0 { cg_to(p, m, f, value, n.type_id); if cg_diverges(p, value) { break; } scalar = cg_save(f, cg_wasm_type(p, n.type_id)); }
                var size = cg_size(p, n.type_id); if (n.flags & F_PAD) != 0 { size = n.aux; }
                wb_i64(f.code, size); let bytes = cg_save(f, 0x7e); let top = cg_region_reserve(p, m, f, owner, bytes, node); let cursor = cg_region_cursor(f, owner);
                if scalar >= 0 { cg_get(f, scalar); cg_write_value(p, m, f, n.type_id, cursor, node); }
                else { cg_get(f, cursor); cg_clear_bytes(p, f, size); }
                cg_region_publish(f, owner, top); field = n.next;
            }
        }
        if node < 0 || !cg_diverges(p, node) { cg_decode_enum(p, m, f, id, owner, node); }
    } else {
        cg_expr(p, m, f, node); if !cg_diverges(p, node) { let source = cg_save(f, wa()); cg_construct_enum_captured(p, m, f, p.nodes[node].type_id, source, destination, node); }
    }
    cg_close_constructor(f, target.construction, !control, saved_node, saved_destination, saved_raw);
}
fn cg_inline_array_receiver(p: Program&, natural: i64, destination: const CgDestination&) -> bool {
    if !cg_owner(p, natural) || p.types[natural].array_kind != A_VAR || !cg_owner(p, destination.type_id) { return false; }
    let receiving: const Type& = p.types[destination.type_id]; return destination.elements || receiving.array_kind == A_GROW || receiving.array_kind == A_GROWSHRINK || receiving.array_kind == A_LIMITED;
}
fn cg_value_array_adaptation(p: Program&, natural: i64, destination: const CgDestination&) -> bool {
    if !cg_owner(p, natural) || !cg_owner(p, destination.type_id) || p.types[natural].array_kind != A_VAR { return false; }
    let receiving: const Type& = p.types[destination.type_id]; return destination.elements || receiving.array_kind == A_GROW || receiving.array_kind == A_GROWSHRINK || receiving.array_kind == A_VAR && receiving.length_storage != p.types[natural].length_storage;
}
recursive fn cg_construct_captured(p: Program&, m: CgModule&, f: CgBody&, natural: i64, source: i64, destination: i64, node: i64) {
    let target = f.construction_destinations[destination]; let id = target.type_id;
    if cg_enum_image(p, id) { cg_construct_enum_captured(p, m, f, natural, source, destination, node); return; }
    if cg_image_owner(p, id) { cg_construct_image_captured(p, m, f, id, source, destination, node); return; }
    if cg_frame_owner(p, id) { cg_construct_frame_captured(p, m, f, id, source, destination, node); return; }
    cg_get(f, source); cg_pack_view(p, m, f, natural, node); let view = cg_save(f, ws());
    cg_get(f, view); ws_len(f.code); let count = cg_save(f, wa()); cg_check_array_length(p, m, f, id, count, node);
    var capacity = count;
    if cg_owner(p, natural) && p.types[natural].array_kind == A_LIMITED { cg_owner_read_capacity(p, m, f, source); capacity = cg_save(f, wa()); }
    let previous_node = f.active_node; let previous_destination = f.active_destination; f.active_node = node; f.active_destination = destination;
    let pointer = cg_region_array_prefix(p, m, f, id, target.header, count, capacity, node);
    cg_get(f, view); ws_ptr(f.code); let base = cg_save(f, wa()); var bytes = -1;
    if p.types[p.types[id].element].storage == 1 {
        cg_get(f, count); wa_extend(f.code); let wide = cg_save(f, 0x7e); let end = cg_walk_elements(p, m, f, base, wide, node); cg_get(f, end); cg_get(f, base); wa_op(f.code, 0x6b); bytes = cg_save(f, wa());
    } else {
        var extent = count; if p.types[id].array_kind == A_LIMITED { extent = capacity; }
        cg_get(f, extent); wa_const(f.code, cg_size(p, p.types[id].element)); wa_op(f.code, 0x6c); bytes = cg_save(f, wa());
    }
    cg_get(f, bytes); wa_extend(f.code); let wide = cg_save(f, 0x7e); let top = cg_region_reserve(p, m, f, target.header, wide, node);
    cg_get(f, pointer); cg_get(f, base); cg_get(f, bytes); wb_copy(f.code); cg_region_publish(f, target.header, top);
    f.active_node = previous_node; f.active_destination = previous_destination;
}
fn cg_set_record_anchor(p: Program&, m: CgModule&, f: CgBody&, id: i64, owner: i64, base: i64, node: i64) {
    let header = cg_region_header(p, f, id, owner);
    if cg_byte_record(p, id) {
        for word in [0, 4] { cg_get(f, header); cg_get(f, base); wc_store(f.code, word); } return;
    }
    cg_get(f, base); wa_const(f.code, cg_record_total_prefix(p, id)); wa_op(f.code, 0x6a); let anchor = cg_save(f, wa());
    let tail = cg_image_tail_type(p, id);
    if cg_enum_image(p, tail) { cg_set_enum_anchor(f, header, anchor); }
    else { cg_set_array_anchor(p, f, header, anchor, tail); }
}
fn cg_decode_record(p: Program&, m: CgModule&, f: CgBody&, id: i64, owner: i64, node: i64) {
    let header = cg_region_header(p, f, id, owner);
    if cg_byte_record(p, id) {
        let end = cg_byte_field(p, m, f, id, owner, -1, node);
        cg_get(f, header); cg_get(f, end); cg_get(f, header); wc_load(f.code, 4); wa_op(f.code, 0x6b); wc_store(f.code, 1); return;
    }
    let tail = cg_image_tail_type(p, id);
    if cg_enum_image(p, tail) { cg_decode_enum(p, m, f, tail, header, node); return; }
    cg_get(f, header); cg_owner_read_base(p, m, f, header, node); wc_store(f.code, 0);
    cg_get(f, header); cg_owner_read_length(p, m, f, header, node); wc_store(f.code, 1);
    if p.types[tail].array_kind == A_LIMITED { cg_get(f, header); cg_owner_read_capacity(p, m, f, header); wc_store(f.code, 3); }
    cg_validate_region_array(p, m, f, tail, header, node);
}
fn cg_record_effect_supported(p: Program&, id: i64) -> bool {
    var current = id;
    while cg_record_image(p, current) {
        var field = p.types[current].first;
        while field >= 0 && field != p.types[current].tail {
            let n: const Node& = p.nodes[field]; if (n.flags & F_PAD) == 0 && (cg_type_kind(p, n.type_id) != TY_INT || p.types[n.type_id].storage != 0) { return false; } field = n.next;
        }
        current = p.nodes[p.types[current].tail].type_id;
    }
    if !cg_owner(p, current) || p.types[current].array_kind != A_VAR && p.types[current].array_kind != A_LIMITED { return false; }
    return p.types[current].length_storage != 0 && p.types[p.types[current].element].storage == 0;
}
fn cg_record_physical_base(p: Program&, m: CgModule&, f: CgBody&, id: i64, owner: i64, node: i64) -> i64 {
    if cg_byte_record(p, id) { cg_get(f, owner); wc_load(f.code, 4); return cg_save(f, wa()); }
    return cg_record_image_base(p, m, f, id, owner, node);
}
fn cg_finish_record_image(p: Program&, m: CgModule&, f: CgBody&, id: i64, owner: i64, start: i64, land: bool, node: i64) {
    let header = cg_region_header(p, f, id, owner);
    if land {
        let base = cg_record_physical_base(p, m, f, id, owner, node); let finish = cg_region_cursor(f, header);
        cg_get(f, finish); cg_get(f, start); wa_op(f.code, 0x6b); let bytes = cg_save(f, wa());
        cg_get(f, base); wa_extend(f.code); cg_get(f, bytes); wa_extend(f.code); wb_byte(f.code, 0x7c); let top64 = cg_save(f, 0x7e);
        cg_get(f, start); cg_get(f, finish); wa_op(f.code, 0x4b); cg_get(f, top64); cg_get(f, header); wc_load(f.code, 2); wa_extend(f.code); wb_byte(f.code, 0x56); wb_byte(f.code, 0x72); cg_trap_if(p, m, f, node, "invalid record image landing span");
        cg_get(f, top64); wa_wrap(f.code); let top = cg_save(f, wa()); cg_ensure_memory(p, m, f, top, node);
        cg_get(f, base); cg_get(f, start); cg_get(f, bytes); wb_copy(f.code); cg_region_publish(f, header, top);
    }
    cg_decode_record(p, m, f, id, owner, node);
}
fn cg_construct_image_captured(p: Program&, m: CgModule&, f: CgBody&, id: i64, source: i64, destination: i64, node: i64) {
    let target = f.construction_destinations[destination]; let header = cg_region_header(p, f, id, target.header);
    cg_decode_record(p, m, f, id, source, node); let base = cg_record_physical_base(p, m, f, id, source, node); var bytes = -1;
    if cg_byte_record(p, id) { cg_get(f, source); wc_load(f.code, 1); bytes = cg_save(f, wa()); }
    else { bytes = cg_record_image_bytes(p, m, f, id, source, node); }
    cg_get(f, bytes); wa_extend(f.code); let wide = cg_save(f, 0x7e); let top = cg_region_reserve(p, m, f, header, wide, node); let cursor = cg_region_cursor(f, header);
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
            let n: const Node& = p.nodes[field]; let value = cg_record_initializer(p, node, field);
            if !cg_byte_record(p, id) && field == p.types[id].tail {
                let child = n.type_id; let carrier = cg_temporary(p, f, child); let child_header = cg_region_header(p, f, child, carrier); let start = cg_region_cursor(f, header);
                cg_get(f, child_header); cg_clear_bytes(p, f, wc_bytes());
                cg_get(f, child_header); cg_get(f, start); wc_store(f.code, 0); cg_get(f, child_header); cg_get(f, header); wc_load(f.code, 2); wc_store(f.code, 2);
                if cg_enum_image(p, child) { cg_set_enum_anchor(f, carrier, start); }
                else if cg_image_owner(p, child) { cg_set_record_anchor(p, m, f, child, carrier, start, node); }
                let receiving = cg_destination(f, child, carrier, target.lifetime, false, false, true, target.entry, target.construction);
                if value >= 0 || cg_image_owner(p, child) || cg_enum_image(p, child) { cg_construct_region(p, m, f, value, receiving); }
                else {
                    let previous_node = f.active_node; let previous_destination = f.active_destination; f.active_node = node; f.active_destination = receiving;
                    wa_const(f.code, 0); let zero = cg_save(f, wa()); cg_region_array_prefix(p, m, f, child, carrier, zero, zero, node); f.active_node = previous_node; f.active_destination = previous_destination;
                }
            } else if (n.flags & F_PAD) != 0 {
                wb_i64(f.code, n.aux); let bytes = cg_save(f, 0x7e); let top = cg_region_reserve(p, m, f, header, bytes, node); let cursor = cg_region_cursor(f, header);
                cg_get(f, cursor); cg_clear_bytes(p, f, n.aux); cg_region_publish(f, header, top);
            } else if cg_relative_type(p, n.type_id) && p.types[n.type_id].length_storage == 0 {
                if value >= 0 { cg_to(p, m, f, value, n.type_id); if cg_diverges(p, value) { break; } } else { wa_const(f.code, 0); }
                let reference = cg_save(f, wa()); cg_region_relative(p, m, f, n.type_id, header, reference, node);
            } else if p.types[n.type_id].storage == 1 {
                if value >= 0 { cg_to(p, m, f, value, TYPE_I64); if cg_diverges(p, value) { break; } } else { wb_i64(f.code, 0); }
                let scalar = cg_save(f, 0x7e); cg_region_varint(p, m, f, header, scalar, node);
            } else {
                var scalar = -1;
                if value >= 0 { cg_to(p, m, f, value, n.type_id); if cg_diverges(p, value) { break; } scalar = cg_save(f, cg_wasm_type(p, n.type_id)); }
                wb_i64(f.code, cg_size(p, n.type_id)); let bytes = cg_save(f, 0x7e); let top = cg_region_reserve(p, m, f, header, bytes, node); let cursor = cg_region_cursor(f, header);
                if scalar >= 0 { cg_get(f, scalar); cg_write_value(p, m, f, n.type_id, cursor, node); }
                else { cg_get(f, cursor); cg_clear_bytes(p, f, cg_size(p, n.type_id)); }
                cg_region_publish(f, header, top);
            }
            if value >= 0 && cg_diverges(p, value) { break; } field = n.next;
        }
        if node < 0 || !cg_diverges(p, node) { cg_decode_record(p, m, f, id, owner, node); }
    } else {
        cg_expr(p, m, f, node); if !cg_diverges(p, node) {
            var from = p.nodes[node].type_id; while cg_type_kind(p, from) == TY_REF { from = p.types[from].element; cg_load(p, m, f, from, 0); }
            let source = cg_save(f, wa()); cg_construct_image_captured(p, m, f, id, source, destination, node);
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
    let parent = f.construction_destinations[destination]; let n: const Node& = p.nodes[field];
    cg_get(f, parent.header); wa_const(f.code, n.integer); wa_op(f.code, 0x6a); let owner = cg_save(f, wa());
    return cg_destination(f, n.type_id, owner, parent.lifetime, false, false, false, parent.entry, parent.construction);
}
fn cg_copy_frame_prefix(p: Program&, m: CgModule&, f: CgBody&, id: i64, destination: i64, source: i64) {
    let bytes = cg_frame_prefix(p, id); if bytes == 0 { return; }
    cg_get(f, destination); cg_canonical_address(m, f, bytes); cg_get(f, source); cg_canonical_address(m, f, bytes); wa_const(f.code, bytes); wb_copy(f.code);
}
fn cg_finish_frame_record(p: Program&, m: CgModule&, f: CgBody&, id: i64, original: i64, stage: i64, start: i64, base: i64, land: bool, node: i64) {
    cg_copy_frame_prefix(p, m, f, id, original, stage);
    let receiving = cg_region_header(p, f, id, original); let source = cg_region_header(p, f, id, stage);
    cg_get(f, source); wc_load(f.code, 0); let final_base = cg_save(f, wa());
    if land {
        cg_get(f, final_base); cg_get(f, start); wa_op(f.code, 0x6b); cg_get(f, base); wa_op(f.code, 0x6a); cg_set(f, final_base);
        cg_get(f, receiving); cg_get(f, base); wc_store(f.code, 0);
    }
    cg_finish_region_array(p, m, f, receiving, source, start, cg_frame_tail_type(p, id), false, land, node);
    cg_get(f, receiving); cg_get(f, final_base); wc_store(f.code, 0); cg_publish_header(m, f, receiving, 0);
}
recursive fn cg_construct_frame_captured(p: Program&, m: CgModule&, f: CgBody&, id: i64, source: i64, destination: i64, node: i64) {
    let target = f.construction_destinations[destination]; cg_copy_frame_prefix(p, m, f, id, target.header, source);
    let source_tail = cg_region_header(p, f, id, source); let tail = cg_region_header(p, f, id, target.header); let tail_id = cg_frame_tail_type(p, id);
    cg_get(f, source_tail); cg_pack_view(p, m, f, tail_id, node); let view = cg_save(f, ws());
    cg_get(f, view); ws_len(f.code); let count = cg_save(f, wa());
    let saved_node = f.active_node; let saved_destination = f.active_destination;
    let tail_destination = cg_destination(f, tail_id, tail, target.lifetime, false, false, false, target.entry, target.construction); f.active_node = node; f.active_destination = tail_destination;
    let pointer = cg_region_array_prefix(p, m, f, tail_id, tail, count, count, node);
    cg_get(f, count); wa_extend(f.code); wb_i64(f.code, cg_size(p, p.types[tail_id].element)); wb_byte(f.code, 0x7e); let bytes = cg_save(f, 0x7e); let top = cg_region_reserve(p, m, f, tail, bytes, node);
    cg_get(f, pointer); cg_get(f, view); ws_ptr(f.code); cg_get(f, bytes); wa_wrap(f.code); wb_copy(f.code); cg_region_publish(f, tail, top);
    f.active_node = saved_node; f.active_destination = saved_destination;
}
recursive fn cg_construct_frame_record(p: Program&, m: CgModule&, f: CgBody&, node: i64, destination: i64) {
    let target = f.construction_destinations[destination]; let id = target.type_id; let owner = target.header; let header = cg_region_header(p, f, id, owner);
    var kind = N_RECORD; if node >= 0 { kind = p.nodes[node].kind; }
    if kind == N_NAME && p.nodes[node].symbol >= 0 && cg_same_destination(f, cg_named_array_destination(p, f, p.nodes[node].symbol), destination) {
        cg_symbol_address(p, m, f, p.nodes[node].symbol, node); let source = cg_save(f, wa()); cg_copy_frame_prefix(p, m, f, id, owner, source);
        let tail = cg_region_header(p, f, id, source);
        for word in [0, 1] { cg_get(f, header); cg_get(f, tail); wc_load(f.code, word); wc_store(f.code, word); cg_publish_header(m, f, header, ww(word)); } return;
    }
    if target.normal && !target.escape {
        let start = cg_region_cursor(f, header); cg_get(f, header); wc_load(f.code, 0); let base = cg_save(f, wa()); let land = f.constructions[target.construction].open > target.open0;
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
            let n: const Node& = p.nodes[field]; let value = cg_record_initializer(p, node, field);
            cg_get(f, owner); wa_const(f.code, n.integer); wa_op(f.code, 0x6a); let address = cg_save(f, wa());
            if field == p.types[id].tail {
                let receiving = cg_frame_tail_destination(p, f, destination, field);
                if cg_owner(p, n.type_id) {
                    let cursor = cg_region_cursor(f, address); cg_get(f, address); cg_get(f, cursor); wc_store(f.code, 0); cg_publish_header(m, f, address, 0);
                    wa_const(f.code, 0); let zero = cg_save(f, wa()); cg_owner_set_length(p, m, f, address, zero, node);
                }
                if value >= 0 { cg_construct_region(p, m, f, value, receiving); }
                else if cg_frame_owner(p, n.type_id) { cg_construct_region(p, m, f, -1, receiving); }
                else {
                    let before_node = f.active_node; let before_destination = f.active_destination; f.active_node = node; f.active_destination = receiving;
                    wa_const(f.code, 0); let zero = cg_save(f, wa()); cg_region_array_prefix(p, m, f, n.type_id, address, zero, zero, node); f.active_node = before_node; f.active_destination = before_destination;
                }
            } else if (n.flags & F_PAD) != 0 {
                cg_get(f, address); cg_canonical_address(m, f, n.aux); cg_clear_bytes(p, f, n.aux);
            } else if value >= 0 { cg_to(p, m, f, value, n.type_id); if cg_diverges(p, value) { break; } cg_write_value(p, m, f, n.type_id, address, field); }
            else { cg_get(f, address); cg_canonical_address(m, f, cg_size(p, n.type_id)); cg_clear_bytes(p, f, cg_size(p, n.type_id)); }
            if value >= 0 && cg_diverges(p, value) { break; } field = n.next;
        }
    } else {
        cg_expr(p, m, f, node); if !cg_diverges(p, node) {
            var from = p.nodes[node].type_id; while cg_type_kind(p, from) == TY_REF { from = p.types[from].element; cg_load(p, m, f, from, 0); }
            let source = cg_save(f, wa()); cg_construct_frame_captured(p, m, f, id, source, destination, node);
        }
    }
    cg_close_constructor(f, target.construction, !control, saved_node, saved_destination, saved_raw);
}
recursive fn cg_construct_array(p: Program&, m: CgModule&, f: CgBody&, node: i64, destination: i64) {
    let target = f.construction_destinations[destination]; let id = target.type_id; let header = target.header; let element = p.types[id].element;
    let n: const Node& = p.nodes[node];
    if n.kind == N_NAME && n.symbol >= 0 && cg_same_destination(f, cg_named_array_destination(p, f, n.symbol), destination) {
        let local = p.symbols[n.symbol].type_id;
        if cg_nonlocal_target(p, f.function) && cg_owner(p, local) && (p.types[local].array_kind == A_VAR || p.types[local].array_kind == A_LIMITED) &&
           (p.types[id].array_kind == A_VAR || p.types[id].array_kind == A_LIMITED) { return; }
        cg_symbol_address(p, m, f, n.symbol, node); let source = cg_save(f, wa());
        let prefix = cg_named_prefix(f, n.symbol);
        if prefix >= 0 { cg_owner_read_length(p, m, f, source, node); let count = cg_save(f, wa()); cg_check_array_length(p, m, f, id, count, node); cg_owner_set_length(p, m, f, prefix, count, node); return; }
        cg_owner_read_length(p, m, f, source, node); let count = cg_save(f, wa()); if !target.elements { cg_check_array_length(p, m, f, id, count, node); }
        cg_owner_set_length(p, m, f, header, count, node);
        if p.types[id].array_kind == A_LIMITED { cg_get(f, header); cg_get(f, source); wc_load(f.code, 3); wc_store(f.code, 3); }
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
        let each = cg_fill_each(p, node, element);
        var count = 0; var child = n.first; while child >= 0 { count += 1; child = p.nodes[child].next; }
        var count_local = -1;
        if n.right >= 0 {
            cg_to(p, m, f, n.right, TYPE_U64); let wide = cg_save(f, 0x7e);
            if n.first >= 0 && !each && !cg_wide {
                cg_get(f, wide); wb_i64(f.code, wn_limit()); wb_byte(f.code, 0x56);
                cg_begin(f, 0x04, 0x40);
                // Count exceeds 32-bit length: evaluate v once (§4.2) in case v exits before trapping.
                if !cg_has_owner(p, element) && cg_has_relative(p, element) {
                    let m0 = f.work.len; cg_capture_literal(p, m, f, n.first, element); f.work.resize(m0);
                } else {
                    var vt = element; if p.types[element].storage == 1 { vt = TYPE_I64; }
                    cg_to(p, m, f, n.first, vt);
                    if !cg_diverges(p, n.first) { wb_byte(f.code, 0x1a); }
                }
                cg_abort(p, m, f, node, "array repetition count out of range");
                cg_end(f);
            } else {
                cg_get(f, wide); wb_i64(f.code, wn_limit()); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array repetition count out of range");
            }
            cg_get(f, wide); wa_wrap(f.code); count_local = cg_save(f, wa());
        } else { wa_const(f.code, count); count_local = cg_save(f, wa()); }
        cg_check_array_length(p, m, f, id, count_local, node);
        var capacity = count_local;
        if n.third >= 0 {
            cg_to(p, m, f, n.third, TYPE_U64); let wide = cg_save(f, 0x7e); cg_get(f, wide); wb_i64(f.code, wn_limit()); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array capacity out of range");
            cg_get(f, wide); wa_wrap(f.code); capacity = cg_save(f, wa());
            cg_get(f, count_local); cg_get(f, capacity); wa_op(f.code, 0x4b); cg_trap_if(p, m, f, node, "limited array capacity exceeded");
        }
        let pointer = cg_region_array_prefix(p, m, f, id, header, count_local, capacity, node);
        if !cg_has_owner(p, element) && cg_has_relative(p, element) {
            cg_get(f, count_local); wa_extend(f.code); wb_i64(f.code, cg_size(p, element)); wb_byte(f.code, 0x7e); let bytes = cg_save(f, 0x7e);
            let top = cg_region_reserve(p, m, f, header, bytes, node);
            cg_literal_elements(p, m, f, node, element, pointer, count_local);
            if !cg_diverges(p, node) { cg_region_publish(f, header, top); }
            cg_close_constructor(f, target.construction, !control, saved_node, saved_destination, saved_raw); return;
        }
        var fill = -1;
        if n.right >= 0 && n.first >= 0 {
            var value_type = element; if p.types[element].storage == 1 { value_type = TYPE_I64; }
            if !each {
                cg_to(p, m, f, n.first, value_type);
                if cg_diverges(p, n.first) { cg_close_constructor(f, target.construction, !control, saved_node, saved_destination, saved_raw); return; }
                fill = cg_save(f, cg_wasm_type(p, value_type));
            }
            if p.types[element].storage != 1 {
                cg_get(f, count_local); wa_extend(f.code); wb_i64(f.code, cg_size(p, element)); wb_byte(f.code, 0x7e); let bytes = cg_save(f, 0x7e); cg_region_reserve(p, m, f, header, bytes, node);
            }
        }
        if n.right >= 0 && n.first >= 0 {
            wa_const(f.code, 0); let index = cg_save(f, wa()); let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
            cg_get(f, index); cg_get(f, count_local); wa_op(f.code, 0x4f); cg_branch(p, f, done, true);
            if p.types[element].storage == 1 { cg_region_varint(p, m, f, header, fill, node); }
            else {
                let live = f.region_live; let acq = f.acquisitions; var regions = -1;
                if each { regions = cg_mark_regions(f); cg_to(p, m, f, n.first, element); fill = cg_save(f, cg_wasm_type(p, element)); }
                wb_i64(f.code, cg_size(p, element)); let bytes = cg_save(f, 0x7e); let top = cg_region_reserve(p, m, f, header, bytes, node); let cursor = cg_region_cursor(f, header);
                cg_get(f, fill); cg_write_value(p, m, f, element, cursor, node); cg_region_publish(f, header, top);
                if each { if f.acquisitions != acq { cg_restore_regions(f, regions); } f.region_live = live; }
            }
            cg_get(f, index); wa_const(f.code, 1); wa_op(f.code, 0x6a); cg_set(f, index); cg_branch(p, f, again, false); cg_end(f); cg_end(f);
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
            cg_get(f, capacity); cg_get(f, count_local); wa_op(f.code, 0x6b); wa_extend(f.code); wb_i64(f.code, cg_size(p, element)); wb_byte(f.code, 0x7e); let spare = cg_save(f, 0x7e); cg_region_reserve(p, m, f, header, spare, node);
            cg_get(f, pointer); cg_get(f, capacity); wa_const(f.code, cg_size(p, element)); wa_op(f.code, 0x6c); wa_op(f.code, 0x6a); let top = cg_save(f, wa()); cg_region_publish(f, header, top);
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
            let source_header = cg_save(f, wa()); cg_owner_read_capacity(p, m, f, source_header); source_capacity = cg_save(f, wa()); cg_get(f, source_header);
        }
        cg_pack_view(p, m, f, natural, node); let view = cg_save(f, ws());
        cg_get(f, view); ws_len(f.code); let count = cg_save(f, wa()); cg_check_array_length(p, m, f, id, count, node);
        var capacity = count; var pointer = -1; let existing_limited = p.types[id].array_kind == A_LIMITED && target.lifetime == CG_EXISTING;
        if existing_limited {
            cg_owner_read_capacity(p, m, f, header); capacity = cg_save(f, wa());
            cg_get(f, count); cg_get(f, capacity); wa_op(f.code, 0x4b); cg_trap_if(p, m, f, node, "limited array capacity exceeded");
            cg_owner_read_base(p, m, f, header, node); pointer = cg_save(f, wa());
        } else {
            if p.types[id].array_kind == A_LIMITED && source_capacity >= 0 { capacity = source_capacity; }
            pointer = cg_region_owner_image(p, m, f, id, header, count, capacity, node);
        }
        cg_get(f, view); ws_ptr(f.code); let source = cg_save(f, wa()); var bytes = -1;
        if p.types[element].storage == 1 {
            cg_get(f, count); wa_extend(f.code); let wide = cg_save(f, 0x7e); let end = cg_walk_elements(p, m, f, source, wide, node);
            cg_get(f, end); cg_get(f, source); wa_op(f.code, 0x6b); bytes = cg_save(f, wa());
        } else {
            var extent = count; if p.types[id].array_kind == A_LIMITED && source_capacity >= 0 && !existing_limited { extent = capacity; }
            cg_get(f, extent); wa_const(f.code, cg_size(p, element)); wa_op(f.code, 0x6c); bytes = cg_save(f, wa());
        }
        var top = -1;
        if existing_limited {
            cg_get(f, pointer); cg_get(f, capacity); wa_const(f.code, cg_size(p, element)); wa_op(f.code, 0x6c); wa_op(f.code, 0x6a); top = cg_save(f, wa()); cg_ensure_memory(p, m, f, top, node);
        } else { cg_get(f, bytes); wa_extend(f.code); let wide = cg_save(f, 0x7e); top = cg_region_reserve(p, m, f, header, wide, node); }
        cg_get(f, pointer); cg_get(f, source); cg_get(f, bytes); wb_copy(f.code); cg_owner_set_length(p, m, f, header, count, node); cg_region_publish(f, header, top);
    }
    cg_close_constructor(f, target.construction, !control, saved_node, saved_destination, saved_raw);
}
// 64-bit memory, regions and images. Stores the address-sized count on the
// stack as an unsigned integer of 1, 2, 4 or 8 bytes, unaligned, at offset.
fn wG_store_count(out: u8[>..]&, bytes: i64, offset: i64) {
    if cg_wide {
        if bytes == 1 { wb_mem(out, 0x3c, 0, offset); } else if bytes == 2 { wb_mem(out, 0x3d, 0, offset); }
        else if bytes == 4 { wb_mem(out, 0x3e, 0, offset); } else { wb_mem(out, 0x37, 0, offset); }
        return;
    }
    if bytes == 1 { wb_mem(out, 0x3a, 0, offset); } else if bytes == 2 { wb_mem(out, 0x3b, 0, offset); }
    else if bytes == 4 { wb_mem(out, 0x36, 0, offset); } else { wb_byte(out, 0xad); wb_mem(out, 0x37, 0, offset); }
}
// The largest i64 sum of byte or element counts that is still taken as an
// address-sized number.
inline fn wG_limit() -> i64 { if cg_wide { return 9223372036854775807; } return 4294967295; }
// With cg_wide a count is 64 bits, so its product with a stride no longer has
// the headroom an i64 gives a 32-bit count: trap before it can wrap.
fn wG_check_product(p: Program&, m: CgModule&, f: CgBody&, count: i64, stride: i64, node: i64, text: u8[:]) {
    if !cg_wide { return; }
    var divisor = stride; if divisor < 1 { divisor = 1; }
    cg_get(f, count); wb_i64(f.code, 4611686018427387903 / divisor); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, text);
}
fn cg_region_header(p: Program&, f: CgBody&, id: i64, owner: i64) -> i64 {
    var current = id; var offset = 0;
    while cg_type_kind(p, current) == TY_STRUCT && !cg_byte_record(p, current) && p.types[current].tail >= 0 {
        let tail = p.types[current].tail; offset += p.nodes[tail].integer; current = p.nodes[tail].type_id;
    }
    cg_get(f, owner); wa_add(f.code, offset); return cg_save(f, wa());
}
// A region ends in three address-sized words: its cursor, its start and its
// high-water mark (kept with --wasm-region-stats). A control's limit, word 2,
// is their address, so the cursor is found without knowing the region's
// size: regions need not be equal (cg_layout_regions).
fn cg_region_cursor_slot(f: CgBody&, header: i64) -> i64 {
    cg_get(f, header); wc_load(f.code, 2); return cg_save(f, wa());
}
fn cg_region_cursor(f: CgBody&, header: i64) -> i64 {
    let slot = cg_region_cursor_slot(f, header); cg_get(f, slot); wa_load(f.code, 0); return cg_save(f, wa());
}
fn cg_region_publish_at(f: CgBody&, slot: i64, top: i64) {
    cg_get(f, slot); cg_get(f, top); wa_store(f.code, 0);
    if cg_region_stats {
        cg_get(f, top); cg_get(f, slot); wa_load(f.code, ww(2)); wa_op(f.code, 0x4b); cg_begin(f, 0x04, 0x40);
        cg_get(f, slot); cg_get(f, top); wa_store(f.code, ww(2)); cg_end(f);
    }
}
fn cg_region_publish(f: CgBody&, header: i64, top: i64) {
    let slot = cg_region_cursor_slot(f, header);
    cg_region_publish_at(f, slot, top);
}
fn cg_region_reserve_at(p: Program&, m: CgModule&, f: CgBody&, header: i64, bytes: i64, node: i64) -> CgReserved {
    let limit = cg_region_cursor_slot(f, header);
    cg_get(f, limit); wa_load(f.code, 0); let cursor = cg_save(f, wa());
    // One combined bounds check: cursor < base || cursor > limit || bytes > (limit - cursor).
    // When this does not trap, base <= cursor <= limit and cursor + bytes <= limit without wrapping.
    cg_get(f, cursor); cg_get(f, limit); wa_load(f.code, ww(1)); wa_op(f.code, 0x49);
    cg_get(f, cursor); cg_get(f, limit); wa_op(f.code, 0x4b); wb_byte(f.code, 0x72);
    cg_get(f, bytes); cg_get(f, limit); cg_get(f, cursor); wa_op(f.code, 0x6b); wa_extend(f.code); wb_byte(f.code, 0x56); wb_byte(f.code, 0x72);
    cg_trap_if(p, m, f, node, "data region exhausted");
    cg_get(f, cursor); cg_get(f, bytes); wa_wrap(f.code); wa_op(f.code, 0x6a); let top = cg_save(f, wa());
    if p.initial_pages != p.maximum_pages { cg_ensure_memory(p, m, f, top, node); }
    return CgReserved { cursor: cursor, limit: limit, top: top };
}
fn cg_region_reserve(p: Program&, m: CgModule&, f: CgBody&, header: i64, bytes: i64, node: i64) -> i64 {
    return cg_region_reserve_at(p, m, f, header, bytes, node).top;
}
fn cg_region_acquire(p: Program&, m: CgModule&, f: CgBody&, id: i64, owner: i64, global_region: i64, node: i64) -> i64 {
    let header = cg_region_header(p, f, id, owner);
    if global_region >= 0 { wb_i32(f.code, global_region); } else { wb_op(f.code, 0x23, 3); }
    let region = cg_save(f, 0x7f); cg_get(f, region); wb_op(f.code, 0x23, 8); wb_byte(f.code, 0x4f); cg_trap_if(p, m, f, node, "data-region count exhausted");
    if global_region < 0 {
        cg_get(f, region); wb_i32(f.code, 1); wb_byte(f.code, 0x6a); wb_op(f.code, 0x24, 3);
        f.acquisitions++; f.region_live += 1; if f.region_live > f.region_peak { f.region_peak = f.region_live; }
    }
    // The region table (global 9) holds where each region starts, and after
    // the last where memory ends. The region's own three words end it.
    wb_op(f.code, 0x23, 9); cg_get(f, region); wa_from_i32(f.code); wa_const(f.code, wa_bytes()); wa_op(f.code, 0x6c); wa_op(f.code, 0x6a); let entry = cg_save(f, wa());
    cg_get(f, entry); wa_load(f.code, 0); let base = cg_save(f, wa());
    cg_get(f, entry); wa_load(f.code, ww(1)); let end = cg_save(f, wa()); cg_ensure_memory(p, m, f, end, node);
    cg_get(f, end); wa_const(f.code, ww(3)); wa_op(f.code, 0x6b); let limit = cg_save(f, wa());
    cg_get(f, header); cg_clear_bytes(p, f, wc_bytes());
    cg_get(f, header); cg_get(f, base); wc_store(f.code, 0);
    cg_get(f, header); cg_get(f, limit); wc_store(f.code, 2);
    cg_get(f, limit); cg_get(f, base); wa_store(f.code, ww(1));
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
    if p.types[id].array_kind == A_LIMITED { mode = 5; width = ww(2); }
    var prefix = -1;
    if mode == 6 { cg_get(f, count); wa_extend(f.code); let value = cg_save(f, 0x7e); prefix = cg_uleb_width(p, f, value); }
    else { wa_const(f.code, width); prefix = cg_save(f, wa()); }
    cg_get(f, prefix); wa_extend(f.code); let prefix64 = cg_save(f, 0x7e); let pointer = cg_region_reserve(p, m, f, header, prefix64, node);
    cg_get(f, header); if mode == 0 { wa_const(f.code, 0); } else { cg_get(f, image); } wc_store(f.code, 4);
    cg_get(f, header); cg_get(f, pointer); wc_store(f.code, 0);
    cg_get(f, header); cg_get(f, count); wc_store(f.code, 1); cg_publish_header(m, f, header, ww(1));
    cg_get(f, header); if mode == 6 { cg_get(f, prefix); } else { cg_get(f, capacity); } wc_store(f.code, 3);
    cg_get(f, header); wa_const(f.code, mode); wc_store(f.code, 5);
    if mode == 6 { cg_get(f, count); wa_extend(f.code); let value = cg_save(f, 0x7e); cg_write_uleb(p, f, image, value); }
    else if mode != 0 {
        cg_get(f, image); if mode == 5 { cg_get(f, capacity); wG_store_count(f.code, wa_bytes(), 0); cg_get(f, image); cg_get(f, count); wG_store_count(f.code, wa_bytes(), ww(1)); }
        else { cg_get(f, count); if mode == 1 { wG_store_count(f.code, 1, 0); } else if mode == 2 { wG_store_count(f.code, 2, 0); }
            else if mode == 3 { wG_store_count(f.code, 4, 0); } else { wG_store_count(f.code, 8, 0); } }
    }
    cg_region_publish(f, header, pointer);
    return pointer;
}
fn cg_region_owner_image(p: Program&, m: CgModule&, f: CgBody&, id: i64, header: i64, count: i64, capacity: i64, node: i64) -> i64 {
    let pointer = cg_region_array_prefix(p, m, f, id, header, count, capacity, node);
    var stride = cg_size(p, p.types[id].element); if p.types[p.types[id].element].storage == 1 { stride = 1; }
    wG_check_product(p, m, f, capacity, stride, node, "data region exhausted"); cg_get(f, capacity); wa_extend(f.code);
    wb_i64(f.code, stride); wb_byte(f.code, 0x7e); let bytes = cg_save(f, 0x7e); cg_region_reserve(p, m, f, header, bytes, node); return pointer;
}

fn cg_check_array_length(p: Program&, m: CgModule&, f: CgBody&, id: i64, count: i64, node: i64) {
    if cg_type_kind(p, id) != TY_ARRAY || p.types[id].array_kind != A_VAR || cg_raw_value(f, node) { return; }
    let width = p.types[id].length_storage;
    if width <= 0 || width >= 8 { return; }
    let maximum = (1 << (width * 8)) - 1;
    cg_get(f, count); wa_extend(f.code); wb_i64(f.code, maximum); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array length exceeds storage range");
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
    if p.types[id].array_kind == A_LIMITED { mode = 5; prefix_bytes = ww(2); }
    var prefix = -1;
    if mode == 6 { cg_get(f, count); wa_extend(f.code); let length64 = cg_save(f, 0x7e); prefix = cg_uleb_width(p, f, length64); }
    else { wa_const(f.code, prefix_bytes); prefix = cg_save(f, wa()); }
    wG_check_product(p, m, f, capacity, stride, node, "array image byte size overflow");
    cg_get(f, capacity); wa_extend(f.code); wb_i64(f.code, stride); wb_byte(f.code, 0x7e); cg_get(f, prefix); wa_extend(f.code); wb_byte(f.code, 0x7c); let bytes = cg_save(f, 0x7e);
    cg_get(f, bytes); wb_i64(f.code, wG_limit()); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array image byte size overflow");
    cg_get(f, bytes); wa_wrap(f.code); cg_allocate(p, m, f, node); let image = cg_save(f, wa());
    cg_get(f, image); cg_get(f, prefix); wa_op(f.code, 0x6a); let pointer = cg_save(f, wa());
    cg_get(f, header); cg_get(f, pointer); wc_store(f.code, 0);
    cg_get(f, header); cg_get(f, count); wc_store(f.code, 1);
    cg_get(f, header); cg_get(f, image); cg_get(f, bytes); wa_wrap(f.code); wa_op(f.code, 0x6a); wc_store(f.code, 2);
    cg_get(f, header); if mode == 6 { cg_get(f, prefix); } else { cg_get(f, capacity); } wc_store(f.code, 3);
    cg_get(f, header); cg_get(f, image); wc_store(f.code, 4); cg_get(f, header); wa_const(f.code, mode); wc_store(f.code, 5);
    if mode == 6 { cg_get(f, count); wa_extend(f.code); let length = cg_save(f, 0x7e); cg_write_uleb(p, f, image, length); }
    else if mode != 0 {
        cg_get(f, image);
        if mode == 5 { cg_get(f, capacity); wG_store_count(f.code, wa_bytes(), 0); cg_get(f, image); cg_get(f, count); wG_store_count(f.code, wa_bytes(), ww(1)); }
        else { cg_get(f, count); if mode == 1 { wG_store_count(f.code, 1, 0); } else if mode == 2 { wG_store_count(f.code, 2, 0); } else if mode == 3 { wG_store_count(f.code, 4, 0); } else { wG_store_count(f.code, 8, 0); } }
    }
    return pointer;
}
fn cg_patch_uleb_length(p: Program&, m: CgModule&, f: CgBody&, header: i64, count: i64, node: i64) {
    cg_get(f, count); wa_extend(f.code); let value = cg_save(f, 0x7e); let width = cg_uleb_width(p, f, value);
    cg_get(f, header); wc_load(f.code, 3); let previous = cg_save(f, wa());
    cg_get(f, previous); wa_const(f.code, 1); wa_op(f.code, 0x49); cg_get(f, previous); wa_const(f.code, 10); wa_op(f.code, 0x4b); wb_byte(f.code, 0x72); cg_trap_if(p, m, f, node, "invalid ULEB construction prefix");
    cg_get(f, header); wc_load(f.code, 4); let image = cg_save(f, wa());
    cg_get(f, image); cg_get(f, previous); wa_op(f.code, 0x6a); let source = cg_save(f, wa()); let finish = cg_region_cursor(f, header);
    cg_get(f, finish); cg_get(f, source); wa_op(f.code, 0x49); cg_trap_if(p, m, f, node, "invalid ULEB construction suffix");
    cg_get(f, finish); wa_extend(f.code); cg_get(f, width); wa_extend(f.code); wb_byte(f.code, 0x7c); cg_get(f, previous); wa_extend(f.code); wb_byte(f.code, 0x7d); let end = cg_save(f, 0x7e);
    cg_get(f, end); cg_get(f, header); wc_load(f.code, 2); wa_extend(f.code); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "data region exhausted");
    cg_get(f, end); wa_wrap(f.code); let top = cg_save(f, wa()); cg_ensure_memory(p, m, f, top, node);
    cg_get(f, image); cg_get(f, width); wa_op(f.code, 0x6a); let destination = cg_save(f, wa());
    cg_get(f, destination); cg_get(f, source); cg_get(f, finish); cg_get(f, source); wa_op(f.code, 0x6b); wb_copy(f.code); cg_write_uleb(p, f, image, value);
    cg_get(f, header); cg_get(f, destination); wc_store(f.code, 0); cg_region_publish(f, header, top);
}
fn cg_owner_set_length(p: Program&, m: CgModule&, f: CgBody&, header: i64, count: i64, node: i64) {
    cg_get(f, header); cg_get(f, count); wc_store(f.code, 1); cg_publish_header(m, f, header, ww(1));
    if m.ordinary_owners { return; }
    if m.update_length >= 0 {
        let done = cg_begin(f, 0x02, 0x40);
        cg_get(f, header); wc_load(f.code, 5); wa_op(f.code, 0x45); cg_branch(p, f, done, true);
        cg_get(f, header); cg_get(f, count); cg_diagnostic_line(p, f, node); wb_op(f.code, 0x10, m.update_length);
        cg_end(f); return;
    }
    cg_update_image_length(p, m, f, header, count, node);
}
fn cg_update_image_length(p: Program&, m: CgModule&, f: CgBody&, header: i64, count: i64, node: i64) {
    cg_get(f, header); wc_load(f.code, 5); let mode = cg_save(f, wa()); let done = cg_begin(f, 0x02, 0x40);
    for selected in 1..7 {
        cg_get(f, mode); wa_const(f.code, selected); wa_op(f.code, 0x46); cg_begin(f, 0x04, 0x40);
        cg_get(f, header); wc_load(f.code, 4); let image = cg_save(f, wa());
        if selected == 6 {
            if m.regions_enabled { cg_patch_uleb_length(p, m, f, header, count, node); }
            else {
                cg_get(f, count); wa_extend(f.code); let value = cg_save(f, 0x7e); let width = cg_uleb_width(p, f, value);
                cg_get(f, width); cg_get(f, header); wc_load(f.code, 3); wa_op(f.code, 0x47); cg_trap_if(p, m, f, node, "immutable array length changed its prefix width"); cg_write_uleb(p, f, image, value);
            }
        } else {
            cg_get(f, image); cg_get(f, count);
            if selected == 1 { wG_store_count(f.code, 1, 0); } else if selected == 2 { wG_store_count(f.code, 2, 0); } else if selected == 3 { wG_store_count(f.code, 4, 0); }
            else if selected == 5 { wG_store_count(f.code, wa_bytes(), ww(1)); } else { wG_store_count(f.code, 8, 0); }
        }
        cg_branch(p, f, done, false); cg_end(f);
    }
    cg_end(f);
}
recursive fn cg_encoded_array_initializers(p: Program&, m: CgModule&, f: CgBody&, node: i64, header: i64, pointer: i64, count: i64, fill_value: i64) {
    let n: const Node& = p.nodes[node]; cg_get(f, pointer); let cursor = cg_save(f, wa());
    if n.right >= 0 && n.first >= 0 {
        let value = fill_value; wa_const(f.code, 0); let index = cg_save(f, wa());
        let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
        cg_get(f, index); cg_get(f, count); wa_op(f.code, 0x4f); cg_branch(p, f, done, true);
        let end = cg_write_varint(p, f, cursor, value); cg_get(f, end); cg_set(f, cursor);
        cg_get(f, index); wa_const(f.code, 1); wa_op(f.code, 0x6a); cg_set(f, index); cg_branch(p, f, again, false); cg_end(f); cg_end(f);
    } else {
        var child = n.first;
        while child >= 0 {
            cg_to(p, m, f, child, TYPE_I64); if cg_diverges(p, child) { return; } let value = cg_save(f, 0x7e); let end = cg_write_varint(p, f, cursor, value);
            cg_get(f, end); cg_set(f, cursor); child = p.nodes[child].next;
        }
    }
    if p.types[n.type_id].array_kind != A_VAR { cg_get(f, header); cg_get(f, cursor); wc_store(f.code, 4); }
}
fn cg_borrowed_sequence(p: Program&, node: i64) -> bool {
    let n: const Node& = p.nodes[node]; let kind = cg_type_kind(p, n.type_id);
    return kind == TY_REF || kind == TY_SLICE || n.kind == N_NAME || n.kind == N_INDEX || n.kind == N_SLICE ||
           n.kind == N_MEMBER && n.symbol >= 0 && n.symbol < p.nodes.len && p.nodes[n.symbol].kind == N_FIELD ||
           n.kind == N_UNARY && (n.integer == T_MUL || n.integer == T_XOR);
}
recursive fn cg_region_varint_builtin(p: Program&, m: CgModule&, f: CgBody&, node: i64, builtin: i64, id: i64, header: i64, arg: i64) {
    if p.types[id].array_kind != A_GROW || builtin != 24 && builtin != 25 && builtin != 29 { cg_fail(p, node, "wasm: varint growables support push, append and clear only"); return; }
    if builtin == 29 {
        cg_owner_read_base(p, m, f, header, node); let base = cg_save(f, wa()); cg_region_publish(f, header, base); wa_const(f.code, 0); let count = cg_save(f, wa()); cg_owner_set_length(p, m, f, header, count, node); return;
    }
    var added = -1; var address = -1;
    if builtin == 24 {
        address = cg_region_cursor(f, header); cg_to(p, m, f, arg, TYPE_I64); let value = cg_save(f, 0x7e);
        cg_owner_read_length(p, m, f, header, node); wa_const(f.code, -1); wa_op(f.code, 0x46); cg_trap_if(p, m, f, node, "data region exhausted"); cg_region_varint(p, m, f, header, value, node);
        wb_i64(f.code, 1); added = cg_save(f, 0x7e);
    } else {
        var source = arg;
        loop {
            let n: const Node& = p.nodes[source];
            if n.kind != N_CALL || n.symbol < 0 || (p.symbols[n.symbol].flags & S_BUILTIN) == 0 || p.symbols[n.symbol].index != 15 { break; }
            source = n.first;
        }
        if cg_borrowed_sequence(p, source) {
            cg_expr(p, m, f, source); cg_pack_view(p, m, f, p.nodes[source].type_id, node); let view = cg_save(f, ws());
            cg_get(f, view); ws_count(f.code); added = cg_save(f, 0x7e); cg_get(f, view); ws_ptr(f.code); let cursor = cg_save(f, wa());
            wb_i64(f.code, 0); let index = cg_save(f, 0x7e); let done = cg_begin(f, 0x02, 0x40); let again = cg_begin(f, 0x03, 0x40);
            cg_get(f, index); cg_get(f, added); wb_byte(f.code, 0x5a); cg_branch(p, f, done, true);
            let decoded = cg_read_uleb(p, m, f, cursor, node); cg_get(f, decoded.cursor); cg_get(f, cursor); wa_op(f.code, 0x6b); wa_extend(f.code); let bytes = cg_save(f, 0x7e);
            let top = cg_region_reserve(p, m, f, header, bytes, node); let destination = cg_region_cursor(f, header);
            cg_get(f, destination); cg_get(f, cursor); cg_get(f, bytes); wa_wrap(f.code); wb_copy(f.code); cg_region_publish(f, header, top); cg_get(f, decoded.cursor); cg_set(f, cursor);
            cg_get(f, index); wb_i64(f.code, 1); wb_byte(f.code, 0x7c); cg_set(f, index); cg_branch(p, f, again, false); cg_end(f); cg_end(f);
        } else {
            let entry = cg_region_cursor(f, header); let owner = cg_destination(f, id, header, CG_EXISTING, false, false, false, entry, -1);
            var carrier = p.nodes[source].type_id; if !cg_owner(p, carrier) { carrier = id; }
            let receiving = cg_share_destination(p, m, f, owner, carrier, true, false, false, node); cg_construct_array(p, m, f, source, receiving);
            cg_owner_read_length(p, m, f, f.construction_destinations[receiving].header, node); wa_extend(f.code); added = cg_save(f, 0x7e);
        }
    }
    cg_owner_read_length(p, m, f, header, node); wa_extend(f.code); cg_get(f, added); wb_byte(f.code, 0x7c); let total = cg_save(f, 0x7e);
    cg_get(f, total); wb_i64(f.code, wG_limit()); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "data region exhausted"); cg_get(f, total); wa_wrap(f.code); let count = cg_save(f, wa()); cg_owner_set_length(p, m, f, header, count, node);
    if builtin == 24 && p.nodes[node].type_id != TYPE_VOID { cg_get(f, address); }
}
recursive fn cg_varint_array_builtin(p: Program&, m: CgModule&, f: CgBody&, node: i64, builtin: i64, id: i64, header: i64, arg: i64) {
    if m.regions_enabled { cg_region_varint_builtin(p, m, f, node, builtin, id, header, arg); return; }
    if p.types[id].array_kind != A_GROW || builtin != 24 && builtin != 25 && builtin != 29 {
        cg_fail(p, node, "wasm: varint growables support push, append and clear only"); return;
    }
    if builtin == 29 {
        cg_get(f, header); cg_owner_read_base(p, m, f, header, node); wc_store(f.code, 4);
        cg_get(f, header); wa_const(f.code, 0); wc_store(f.code, 1); return;
    }
    var value = -1; var source = -1; var added = -1; var source_bytes = -1;
    if builtin == 24 { cg_to(p, m, f, arg, TYPE_I64); value = cg_save(f, 0x7e); wa_const(f.code, 1); added = cg_save(f, wa()); }
    else {
        let saved_raw = f.raw_node; f.raw_node = arg; cg_expr(p, m, f, arg); f.raw_node = saved_raw;
        cg_pack_view(p, m, f, p.nodes[arg].type_id, node); let view = cg_save(f, ws());
        cg_get(f, view); ws_ptr(f.code); source = cg_save(f, wa()); cg_get(f, view); ws_count(f.code); let count64 = cg_save(f, 0x7e);
        cg_get(f, count64); wa_wrap(f.code); added = cg_save(f, wa()); let end = cg_walk_elements(p, m, f, source, count64, node);
        cg_get(f, end); cg_get(f, source); wa_op(f.code, 0x6b); source_bytes = cg_save(f, wa());
    }
    cg_owner_read_length(p, m, f, header, node); let old = cg_save(f, wa());
    cg_get(f, old); cg_get(f, added); wa_op(f.code, 0x6a); let count = cg_save(f, wa());
    cg_get(f, count); cg_get(f, old); wa_op(f.code, 0x49); cg_trap_if(p, m, f, node, "array length overflow");
    cg_owner_read_base(p, m, f, header, node); let base = cg_save(f, wa());
    cg_get(f, header); wc_load(f.code, 4); let end = cg_save(f, wa());
    cg_get(f, end); cg_get(f, base); wa_op(f.code, 0x49);
    cg_get(f, end); cg_get(f, header); wc_load(f.code, 2); wa_op(f.code, 0x4b); wb_byte(f.code, 0x72);
    cg_trap_if(p, m, f, node, "invalid varint array cursor");
    cg_get(f, end); cg_get(f, base); wa_op(f.code, 0x6b); let old_bytes = cg_save(f, wa());
    cg_get(f, old_bytes); wa_extend(f.code);
    if source_bytes >= 0 { cg_get(f, source_bytes); wa_extend(f.code); } else { wb_i64(f.code, 10); }
    wb_byte(f.code, 0x7c); let needed = cg_save(f, 0x7e);
    cg_get(f, needed); wb_i64(f.code, wG_limit()); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array byte size overflow");
    cg_get(f, header); wc_load(f.code, 2); cg_get(f, base); wa_op(f.code, 0x6b); let old_capacity = cg_save(f, wa());
    cg_get(f, base); let copy = cg_save(f, wa()); cg_get(f, old_capacity); let capacity = cg_save(f, wa());
    cg_get(f, needed); cg_get(f, old_capacity); wa_extend(f.code); wb_byte(f.code, 0x56); cg_begin(f, 0x04, 0x40);
    cg_get(f, old_capacity); wa_extend(f.code); wb_i64(f.code, 2); wb_byte(f.code, 0x7e); let doubled = cg_save(f, 0x7e);
    cg_get(f, doubled); cg_get(f, needed); cg_get(f, doubled); cg_get(f, needed); wb_byte(f.code, 0x56); wb_byte(f.code, 0x1b); let capacity64 = cg_save(f, 0x7e);
    cg_get(f, capacity64); wb_i64(f.code, wG_limit()); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "array byte capacity overflow");
    cg_get(f, capacity64); wa_wrap(f.code); cg_set(f, capacity);
    cg_get(f, capacity); cg_allocate(p, m, f, node); cg_set(f, copy);
    cg_get(f, copy); cg_get(f, base); cg_get(f, old_bytes); wb_copy(f.code);
    cg_forward_span(p, m, f, base, old_capacity, copy);
    cg_get(f, header); cg_get(f, copy); wc_store(f.code, 0);
    cg_get(f, header); cg_get(f, copy); cg_get(f, capacity); wa_op(f.code, 0x6a); wc_store(f.code, 2); cg_end(f);
    cg_get(f, copy); cg_get(f, old_bytes); wa_op(f.code, 0x6a); let destination = cg_save(f, wa()); var finish = -1;
    if builtin == 24 { finish = cg_write_varint(p, f, destination, value); }
    else {
        cg_get(f, source); cg_resolve_pointer(m, f); source = cg_save(f, wa());
        cg_get(f, destination); cg_get(f, source); cg_get(f, source_bytes); wb_copy(f.code); cg_get(f, destination); cg_get(f, source_bytes); wa_op(f.code, 0x6a); finish = cg_save(f, wa());
    }
    cg_get(f, header); cg_get(f, count); wc_store(f.code, 1); cg_get(f, header); cg_get(f, finish); wc_store(f.code, 4);
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
        wb_i64(f.code, 0); cg_get(f, divisor); wb_byte(f.code, 0x7d); cg_control(f, 0x05); cg_get(f, divisor); cg_end(f);
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
// Emission never changes an existing type or field (root owners take their
// frame layout before it starts), so these per-type predicates are computed once.
let CG_MEMO_BYTE_RECORD: i64 = 0;
let CG_MEMO_HAS_OWNER: i64 = 1;
let CG_MEMO_RECORD_IMAGE: i64 = 2;
let CG_MEMO_REGION_TYPE: i64 = 3;
inline fn cg_memo_get(p: Program&, id: i64, predicate: i64) -> i64 {
    let memo = p.types[id].codegen_memo;
    if (memo >> 16) != id + 1 { return -1; }
    let bits = (memo >> (2 * predicate)) & 3;
    if (bits & 1) == 0 { return -1; }
    return bits >> 1;
}
fn cg_memo_set(p: Program&, id: i64, predicate: i64, value: bool) -> bool {
    var memo = p.types[id].codegen_memo;
    if (memo >> 16) != id + 1 { memo = (id + 1) << 16; }
    var bits = 1; if value { bits = 3; }
    p.types[id].codegen_memo = memo | (bits << (2 * predicate));
    return value;
}
fn cg_byte_record(p: Program&, id: i64) -> bool {
    if id < 13 || cg_type_kind(p, id) != TY_STRUCT { return false; }
    let known = cg_memo_get(p, id, CG_MEMO_BYTE_RECORD); if known >= 0 { return known == 1; }
    // A root owner stores each component apart, never as one byte image.
    if root_struct_type(p, id) { return cg_memo_set(p, id, CG_MEMO_BYTE_RECORD, false); }
    var field = p.types[id].first;
    while field >= 0 {
        if (p.nodes[field].flags & F_PAD) == 0 && cg_encoded_scalar(p, p.nodes[field].type_id) { return cg_memo_set(p, id, CG_MEMO_BYTE_RECORD, true); }
        field = p.nodes[field].next;
    }
    return cg_memo_set(p, id, CG_MEMO_BYTE_RECORD, false);
}

fn cg_result_count(p: Program&, id: i64) -> i64 {
    if id <= -2 {
        var count = 0; var part = -2 - id;
        while part >= 0 { count++; part = p.nodes[part].next; } return count;
    }
    if cg_type_kind(p, id) == TY_VOID { return 0; }
    if cg_type_kind(p, id) != TY_TUPLE { return 1; }
    var count = 0; var part = p.types[id].first;
    while part >= 0 { count++; part = p.nodes[part].next; } return count;
}
fn cg_result_at(p: Program&, id: i64, index: i64) -> i64 {
    if id <= -2 {
        var part = -2 - id; var ordinal = 0;
        while part >= 0 { if ordinal == index { return p.nodes[part].type_id; } part = p.nodes[part].next; ordinal++; }
        return TYPE_UNKNOWN;
    }
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
    if node < 0 { return false; } let n: const Node& = p.nodes[node];
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
    if node < 0 { return true; } let n: const Node& = p.nodes[node];
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
    if node < 0 { return false; } let n: const Node& = p.nodes[node];
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
    if cg_wide {
        wb_name(section, "abi=1;layout=15;encoded-record-tails=terminal;encoded-arrays=combined;array-lengths=unsigned-uleb;varint-elements=sequential-grow;varint-records=sequential;record-padding=fixed-alignment-variable-explicit;static-limited=compact-lengths;enum-tags=compact;variable-enums=active-payloads;resizable-payloads=descriptor-tail;resizable-prefix=frame;record-values=packed-single-tail;owner-control=48;array-values=unsigned-prefixes;variant-payloads=packed-fields;fixed-records=packed-fields;memory=wasm64;slices=v128-ptr64-len64;features=bulk-memory,multi-value,sign-ext,memory64,simd128");
    } else {
        wb_name(section, "abi=1;layout=15;encoded-record-tails=terminal;encoded-arrays=combined;array-lengths=unsigned-uleb;varint-elements=sequential-grow;varint-records=sequential;record-padding=fixed-alignment-variable-explicit;static-limited=compact-lengths;enum-tags=compact;variable-enums=active-payloads;resizable-payloads=descriptor-tail;resizable-prefix=frame;record-values=packed-single-tail;owner-control=24;array-values=unsigned-prefixes;variant-payloads=packed-fields;fixed-records=packed-fields;memory=wasm32;slices=packed-ptr32-len32;features=bulk-memory,multi-value,sign-ext");
    }
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
    let t: const Type& = p.types[id];
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
        let n: const Node& = p.nodes[field];
        if (n.flags & F_PAD) != 0 { bytes += n.aux; }
        else if cg_encoded_scalar(p, n.type_id) { bytes += 10; }
        else { bytes += cg_size(p, n.type_id); }
        field = n.next;
    }
    if bytes < 1 { return 1; } return bytes;
}
fn cg_byte_field(p: Program&, m: CgModule&, f: CgBody&, id: i64, header: i64, wanted: i64, node: i64) -> i64 {
    cg_get(f, header); wc_load(f.code, 4); let cursor = cg_save(f, wa());
    var field = p.types[id].first;
    while field >= 0 {
        let n: const Node& = p.nodes[field];
        if field == wanted { return cursor; }
        if (n.flags & F_PAD) == 0 && cg_encoded_scalar(p, n.type_id) {
            let decoded = cg_read_uleb(p, m, f, cursor, node); cg_get(f, decoded.cursor); cg_set(f, cursor);
        } else {
            var bytes = n.aux; if (n.flags & F_PAD) == 0 { bytes = cg_size(p, n.type_id); }
            cg_get(f, cursor); wa_const(f.code, bytes); wa_op(f.code, 0x6a); cg_set(f, cursor);
        }
        cg_get(f, cursor); cg_get(f, header); wc_load(f.code, 2); wa_op(f.code, 0x4b);
        cg_trap_if(p, m, f, node, "byte-record field exceeds data region");
        field = n.next;
    }
    return cursor;
}
fn cg_byte_header(f: CgBody&, header: i64, image: i64, bytes: i64) {
    for word in [0, 4] { cg_get(f, header); cg_get(f, image); wc_store(f.code, word); }
    cg_get(f, header); cg_get(f, image); cg_get(f, bytes); wa_op(f.code, 0x6a); wc_store(f.code, 2);
    cg_get(f, header); cg_get(f, bytes); wc_store(f.code, 1);
    for word in [3, 5] { cg_get(f, header); wa_const(f.code, 0); wc_store(f.code, word); }
}
recursive fn cg_construct_byte_record(p: Program&, m: CgModule&, f: CgBody&, id: i64, header: i64, node: i64) {
    let bound = cg_byte_record_bound(p, id);
    wa_const(f.code, bound); cg_allocate(p, m, f, node); let image = cg_save(f, wa());
    wa_const(f.code, bound); let reserved = cg_save(f, wa()); cg_byte_header(f, header, image, reserved);
    cg_get(f, image); let cursor = cg_save(f, wa()); var field = p.types[id].first;
    while field >= 0 {
        let n: const Node& = p.nodes[field];
        if (n.flags & F_PAD) != 0 {
            cg_get(f, cursor); cg_clear_bytes(p, f, n.aux);
            cg_get(f, cursor); wa_const(f.code, n.aux); wa_op(f.code, 0x6a); cg_set(f, cursor);
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
                if initializer >= 0 { cg_to(p, m, f, initializer, n.type_id); if cg_diverges(p, initializer) { return; } } else { wa_const(f.code, 0); }
                let value = cg_save(f, wa()); let end = cg_write_relative(p, m, f, n.type_id, cursor, value, node); cg_get(f, end); cg_set(f, cursor);
            } else if p.types[n.type_id].storage == 1 {
                if initializer >= 0 { cg_to(p, m, f, initializer, TYPE_I64); if cg_diverges(p, initializer) { return; } } else { wb_i64(f.code, 0); }
                let value = cg_save(f, 0x7e); let end = cg_write_varint(p, f, cursor, value); cg_get(f, end); cg_set(f, cursor);
            } else {
                if initializer >= 0 { cg_to(p, m, f, initializer, n.type_id); if cg_diverges(p, initializer) { return; } cg_write_value(p, m, f, n.type_id, cursor, node); }
                else { cg_get(f, cursor); cg_clear_bytes(p, f, cg_size(p, n.type_id)); }
                cg_get(f, cursor); wa_const(f.code, cg_size(p, n.type_id)); wa_op(f.code, 0x6a); cg_set(f, cursor);
            }
        }
        field = n.next;
    }
    cg_get(f, header); cg_get(f, cursor); cg_get(f, image); wa_op(f.code, 0x6b); wc_store(f.code, 1);
}
fn cg_copy_byte_record(p: Program&, m: CgModule&, f: CgBody&, id: i64, destination: i64, source: i64, node: i64) {
    cg_get(f, source); wc_load(f.code, 4); let original = cg_save(f, wa());
    let end = cg_byte_field(p, m, f, id, source, -1, node);
    cg_get(f, end); cg_get(f, original); wa_op(f.code, 0x6b); let bytes = cg_save(f, wa());
    cg_get(f, bytes); cg_allocate(p, m, f, node); let image = cg_save(f, wa());
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
    cg_owner_read_base(p, m, f, tail, node); let base = cg_save(f, wa());
    cg_owner_read_length(p, m, f, tail, node);
    if p.types[p.types[array].element].storage == 1 {
        wa_extend(f.code); let count = cg_save(f, 0x7e); let end = cg_walk_elements(p, m, f, base, count, node);
        cg_get(f, end); cg_get(f, base); wa_op(f.code, 0x6b);
    } else { wa_const(f.code, cg_size(p, p.types[array].element)); wa_op(f.code, 0x6c); }
    return cg_save(f, wa());
}
recursive fn cg_rebase_enum_frame(p: Program&, f: CgBody&, id: i64, owner: i64, image: i64, bytes: i64) {
    cg_get(f, image); var load = 0x2d; if p.types[id].length_storage == 2 { load = 0x2f; }
    wb_mem(f.code, load, 0, 0); let tag = cg_save(f, 0x7f); var variant = p.types[id].first;
    while variant >= 0 {
        let payload = p.nodes[variant].type_id;
        if cg_frame_metadata(p, payload) {
            cg_get(f, tag); wb_i32(f.code, p.nodes[variant].integer); wb_byte(f.code, 0x46); cg_begin(f, 0x04, 0x40);
            cg_get(f, owner); wa_const(f.code, p.nodes[variant].aux); wa_op(f.code, 0x6a); let place = cg_save(f, wa());
            if cg_record_image(p, payload) {
                cg_get(f, image); wa_const(f.code, p.types[id].length_storage); wa_op(f.code, 0x6a); let payload_image = cg_save(f, wa());
                cg_get(f, bytes); wa_const(f.code, p.types[id].length_storage); wa_op(f.code, 0x6b); let payload_bytes = cg_save(f, wa());
                cg_rebase_record_image(p, f, payload, place, payload_image, payload_bytes);
            } else {
            let tail = cg_region_header(p, f, payload, place);
            for word in [0, 4] { cg_get(f, tail); cg_get(f, image); wa_const(f.code, p.types[id].length_storage); wa_op(f.code, 0x6a); wc_store(f.code, word); }
            cg_get(f, tail); cg_get(f, image); cg_get(f, bytes); wa_op(f.code, 0x6a); wc_store(f.code, 2);
            }
            cg_end(f);
        }
        variant = p.nodes[variant].next;
    }
}
fn cg_seed_record_image(p: Program&, m: CgModule&, f: CgBody&, id: i64, owner: i64, image: i64, limit: i64, node: i64) {
    if cg_byte_record(p, id) {
        for word in [0, 4] { cg_get(f, owner); cg_get(f, image); wc_store(f.code, word); }
        cg_get(f, owner); cg_get(f, limit); wc_store(f.code, 2); return;
    }
    let header = cg_image_tail_control(p, f, id, owner); let tail = cg_image_tail_type(p, id);
    cg_get(f, image); wa_const(f.code, cg_record_total_prefix(p, id)); wa_op(f.code, 0x6a); let anchor = cg_save(f, wa());
    cg_get(f, header); cg_get(f, anchor); wc_store(f.code, 4);
    cg_get(f, header); cg_get(f, limit); wc_store(f.code, 2);
    var mode = 0;
    if cg_type_kind(p, tail) == TY_ARRAY {
        if p.types[tail].array_kind == A_LIMITED { mode = 5; }
        else if p.types[tail].length_storage == 0 { mode = 6; }
        else if p.types[tail].length_storage == 1 { mode = 1; }
        else if p.types[tail].length_storage == 2 { mode = 2; }
        else if p.types[tail].length_storage == 4 { mode = 3; }
        else { mode = 4; }
    }
    cg_get(f, header); wa_const(f.code, mode); wc_store(f.code, 5);
    if mode == 6 {
        let decoded = cg_read_uleb(p, m, f, anchor, node);
        cg_get(f, header); cg_get(f, decoded.cursor); cg_get(f, anchor); wa_op(f.code, 0x6b); wc_store(f.code, 3);
    }
    if mode == 0 { cg_get(f, header); cg_get(f, anchor); wc_store(f.code, 0); }
}
fn cg_enum_payload(p: Program&, m: CgModule&, f: CgBody&, enum_id: i64, owner: i64, variant: i64, node: i64) -> i64 {
    cg_get(f, owner);
    if cg_enum_image(p, enum_id) { wc_load(f.code, 0); }
    wa_const(f.code, p.types[enum_id].length_storage); wa_op(f.code, 0x6a); let image = cg_save(f, wa());
    if cg_enum_image(p, enum_id) && variant >= 0 && p.nodes[variant].aux > 0 {
        cg_get(f, owner); wa_const(f.code, p.nodes[variant].aux); wa_op(f.code, 0x6a); let payload = cg_save(f, wa());
        if cg_frame_metadata(p, p.nodes[variant].type_id) { return payload; }
        cg_get(f, owner); wc_load(f.code, 2); let limit = cg_save(f, wa());
        cg_seed_record_image(p, m, f, p.nodes[variant].type_id, payload, image, limit, node); return payload;
    }
    return image;
}
recursive fn cg_enum_image_bytes(p: Program&, m: CgModule&, f: CgBody&, id: i64, owner: i64, node: i64) -> i64 {
    cg_get(f, owner); wc_load(f.code, 0); var load = 0x2d; if p.types[id].length_storage == 2 { load = 0x2f; }
    wb_mem(f.code, load, 0, 0); let tag = cg_save(f, 0x7f); let result = cg_local(f, wa()); let done = cg_begin(f, 0x02, 0x40);
    var variant = p.types[id].first;
    while variant >= 0 {
        cg_get(f, tag); wb_i32(f.code, p.nodes[variant].integer); wb_byte(f.code, 0x46); cg_begin(f, 0x04, 0x40);
        let payload = p.nodes[variant].type_id;
        if cg_frame_owner(p, payload) {
            let place = cg_enum_payload(p, m, f, id, owner, variant, node); let bytes = cg_frame_array_bytes(p, m, f, payload, place, node);
            cg_get(f, bytes); wa_const(f.code, p.types[id].length_storage); wa_op(f.code, 0x6a);
        } else if cg_byte_record(p, payload) {
            let place = cg_enum_payload(p, m, f, id, owner, variant, node); let end = cg_byte_field(p, m, f, payload, place, -1, node);
            cg_get(f, end); cg_get(f, owner); wc_load(f.code, 0); wa_op(f.code, 0x6b);
        } else if cg_record_image(p, payload) {
            let place = cg_enum_payload(p, m, f, id, owner, variant, node); let bytes = cg_record_image_bytes(p, m, f, payload, place, node);
            cg_get(f, bytes); wa_const(f.code, p.types[id].length_storage); wa_op(f.code, 0x6a);
        } else { var bytes = 0; if p.nodes[variant].first >= 0 { bytes = cg_size(p, payload); } wa_const(f.code, bytes + p.types[id].length_storage); }
        cg_set(f, result); cg_branch(p, f, done, false); cg_end(f); variant = p.nodes[variant].next;
    }
    cg_abort(p, m, f, node, "invalid enum tag"); cg_end(f);
    if m.regions_enabled {
        cg_get(f, owner); wc_load(f.code, 0); wa_extend(f.code); cg_get(f, result); wa_extend(f.code); wb_byte(f.code, 0x7c); let end = cg_save(f, 0x7e);
        cg_get(f, end); cg_get(f, owner); wc_load(f.code, 2); wa_extend(f.code); wb_byte(f.code, 0x56); cg_trap_if(p, m, f, node, "enum image exceeds data region");
        cg_get(f, end); wa_wrap(f.code); let top = cg_save(f, wa()); cg_ensure_memory(p, m, f, top, node);
    }
    return result;
}
recursive fn cg_enum_variant_image(p: Program&, m: CgModule&, f: CgBody&, id: i64, destination: i64, variant: i64, source: i64, node: i64) {
    let payload = p.nodes[variant].type_id; var original = source; var payload_bytes = -1;
    if cg_frame_owner(p, payload) {
        let tail = cg_region_header(p, f, payload, source); cg_owner_read_base(p, m, f, tail, node); original = cg_save(f, wa());
        payload_bytes = cg_frame_array_bytes(p, m, f, payload, source, node);
        cg_get(f, destination); wa_const(f.code, p.nodes[variant].aux); wa_op(f.code, 0x6a); let place = cg_save(f, wa());
        cg_get(f, place); cg_get(f, source); wa_const(f.code, cg_size(p, payload)); wb_copy(f.code);
    } else if cg_byte_record(p, payload) {
        cg_get(f, source); wc_load(f.code, 4); original = cg_save(f, wa()); let end = cg_byte_field(p, m, f, payload, source, -1, node);
        cg_get(f, end); cg_get(f, original); wa_op(f.code, 0x6b); payload_bytes = cg_save(f, wa());
    } else if cg_record_image(p, payload) {
        original = cg_record_image_base(p, m, f, payload, source, node); payload_bytes = cg_record_image_bytes(p, m, f, payload, source, node);
        if cg_frame_metadata(p, payload) {
            cg_get(f, destination); wa_const(f.code, p.nodes[variant].aux); wa_op(f.code, 0x6a); let place = cg_save(f, wa());
            cg_get(f, place); cg_get(f, source); wa_const(f.code, cg_size(p, payload)); wb_copy(f.code);
        }
    }
    else { var bytes = 0; if p.nodes[variant].first >= 0 { bytes = cg_size(p, payload); } wa_const(f.code, bytes); payload_bytes = cg_save(f, wa()); }
    cg_get(f, payload_bytes); wa_const(f.code, p.types[id].length_storage); wa_op(f.code, 0x6a); let bytes = cg_save(f, wa());
    cg_get(f, bytes); cg_allocate(p, m, f, node); let image = cg_save(f, wa());
    cg_get(f, image); wb_i32(f.code, p.nodes[variant].integer); var store = 0x3a; if p.types[id].length_storage == 2 { store = 0x3b; } wb_mem(f.code, store, 0, 0);
    cg_get(f, image); wa_const(f.code, p.types[id].length_storage); wa_op(f.code, 0x6a); cg_get(f, original); cg_get(f, payload_bytes); wb_copy(f.code);
    cg_byte_header(f, destination, image, bytes);
    if cg_frame_metadata(p, payload) { cg_rebase_enum_frame(p, f, id, destination, image, bytes); }
}
recursive fn cg_enum_from_value(p: Program&, m: CgModule&, f: CgBody&, id: i64, destination: i64, from: i64, source: i64, node: i64) {
    if cg_type_kind(p, from) == TY_STRUCT { cg_enum_variant_image(p, m, f, id, destination, p.types[from].declaration, source, node); return; }
    if cg_enum_image(p, from) && !cg_frame_metadata(p, from) {
        let bytes = cg_enum_image_bytes(p, m, f, from, source, node);
        cg_get(f, source); wc_load(f.code, 0); let original = cg_save(f, wa());
        cg_get(f, bytes); cg_allocate(p, m, f, node); let image = cg_save(f, wa());
        cg_get(f, image); cg_get(f, original); cg_get(f, bytes); wb_copy(f.code); cg_byte_header(f, destination, image, bytes); return;
    }
    cg_get(f, source); if cg_enum_image(p, from) { wc_load(f.code, 0); }
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
    if (p.nodes[function].flags & F_LOCATED) != 0 { cg_line(p, f, node); }
    cg_region_call(m, f, target, node); wb_op(f.code, 0x10, m.functions[target].index); cg_effect_check(p, m, f, results);
    if results.len == 1 && results[0] != p.nodes[node].type_id && !cg_diverges(p, node) { cg_convert(p, m, f, results[0], p.nodes[node].type_id, node); }
}
recursive fn cg_dispatch(p: Program&, m: CgModule&, f: CgBody&, node: i64) {
    let n: const Node& = p.nodes[node]; let mark = f.work.len; var arm = n.third; var by_reference = false;
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
            enum_id = id; saved = cg_save(f, wa());
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
    cg_get(f, enum_value); if (p.types[enum_id].flags & F_VARIABLE_MODE) != 0 { wc_load(f.code, 0); }
    var load = 0x2d; if p.types[enum_id].length_storage == 2 { load = 0x2f; }
    wb_mem(f.code, load, 0, 0); let tag = cg_save(f, 0x7f);
    let result = cg_control_slots(p, f, n.type_id, node); let count = cg_result_count(p, n.type_id); let done = cg_begin(f, 0x02, 0x40); arm = n.third;
    while arm >= 0 {
        let a: const Node& = p.nodes[arm]; cg_get(f, tag); wb_i32(f.code, a.integer); wb_byte(f.code, 0x46); cg_begin(f, 0x04, 0x40);
        cg_dispatch_invoke(p, m, f, node, a.symbol, mark, ordinal, n.aux, enum_id, enum_value, a.type_id);
        var at = count; while at > 0 { at--; cg_set(f, result + at); }
        cg_branch(p, f, done, false); cg_end(f); arm = a.next;
    }
    cg_abort(p, m, f, node, "invalid enum dispatch tag"); cg_end(f); cg_control_get(p, f, n.type_id, result); f.work.resize(mark);
}
recursive fn cg_record_image(p: Program&, id: i64) -> bool {
    if id < 13 || cg_type_kind(p, id) != TY_STRUCT || cg_byte_record(p, id) || p.types[id].tail < 0 { return false; }
    let known = cg_memo_get(p, id, CG_MEMO_RECORD_IMAGE); if known >= 0 { return known == 1; }
    let field = p.types[id].tail; let tail = p.nodes[field].type_id;
    if cg_type_kind(p, tail) == TY_ARRAY { return cg_memo_set(p, id, CG_MEMO_RECORD_IMAGE, p.types[tail].array_kind == A_VAR || p.types[tail].array_kind == A_LIMITED && p.types[tail].count < 0); }
    return cg_memo_set(p, id, CG_MEMO_RECORD_IMAGE, cg_enum_image(p, tail) || cg_record_image(p, tail));
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
    cg_get(f, owner); wa_add(f.code, offset);
    return cg_save(f, wa());
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
    let header = cg_image_tail_control(p, f, id, owner); cg_get(f, header); wc_load(f.code, 4);
    wa_const(f.code, cg_record_total_prefix(p, id)); wa_op(f.code, 0x6b); return cg_save(f, wa());
}
fn cg_array_image_bytes(p: Program&, m: CgModule&, f: CgBody&, id: i64, header: i64, node: i64) -> i64 {
    cg_get(f, header); wc_load(f.code, 4); let image = cg_save(f, wa());
    cg_owner_read_base(p, m, f, header, node); let elements = cg_save(f, wa());
    let element = p.types[id].element;
    if p.types[element].storage == 1 {
        cg_owner_read_length(p, m, f, header, node); wa_extend(f.code); let count = cg_save(f, 0x7e);
        let end = cg_walk_elements(p, m, f, elements, count, node); cg_get(f, end);
    } else {
        cg_get(f, elements);
        if p.types[id].array_kind == A_LIMITED { cg_owner_read_capacity(p, m, f, header); }
        else { cg_owner_read_length(p, m, f, header, node); }
        wa_const(f.code, cg_size(p, element)); wa_op(f.code, 0x6c); wa_op(f.code, 0x6a);
    }
    cg_get(f, image); wa_op(f.code, 0x6b); return cg_save(f, wa());
}
recursive fn cg_record_image_bytes(p: Program&, m: CgModule&, f: CgBody&, id: i64, owner: i64, node: i64) -> i64 {
    let header = cg_image_tail_control(p, f, id, owner); let tail = cg_image_tail_type(p, id);
    var bytes = -1;
    if cg_enum_image(p, tail) { bytes = cg_enum_image_bytes(p, m, f, tail, header, node); }
    else { bytes = cg_array_image_bytes(p, m, f, tail, header, node); }
    cg_get(f, bytes); wa_const(f.code, cg_record_total_prefix(p, id)); wa_op(f.code, 0x6a); return cg_save(f, wa());
}
recursive fn cg_rebase_record_image(p: Program&, f: CgBody&, id: i64, owner: i64, image: i64, bytes: i64) {
    let header = cg_image_tail_control(p, f, id, owner);
    cg_get(f, header); wc_load(f.code, 4); let old_tail = cg_save(f, wa());
    cg_get(f, image); wa_const(f.code, cg_record_total_prefix(p, id)); wa_op(f.code, 0x6a); let new_tail = cg_save(f, wa());
    cg_get(f, header); cg_get(f, header); wc_load(f.code, 0); cg_get(f, old_tail); wa_op(f.code, 0x6b); cg_get(f, new_tail); wa_op(f.code, 0x6a); wc_store(f.code, 0);
    cg_get(f, header); cg_get(f, new_tail); wc_store(f.code, 4);
    cg_get(f, header); cg_get(f, image); cg_get(f, bytes); wa_op(f.code, 0x6a); wc_store(f.code, 2);
    let tail = cg_image_tail_type(p, id);
    if cg_frame_metadata(p, tail) {
        cg_get(f, bytes); wa_const(f.code, cg_record_total_prefix(p, id)); wa_op(f.code, 0x6b); let tail_bytes = cg_save(f, wa());
        cg_rebase_enum_frame(p, f, tail, header, new_tail, tail_bytes);
    }
}
recursive fn cg_pack_record_image(p: Program&, m: CgModule&, f: CgBody&, id: i64, owner: i64, node: i64) {
    let tail_field = p.types[id].tail; let tail_id = p.nodes[tail_field].type_id;
    cg_get(f, owner); wa_const(f.code, p.nodes[tail_field].integer); wa_op(f.code, 0x6a); let tail = cg_save(f, wa());
    var tail_image = -1; var tail_bytes = -1;
    if cg_record_image(p, tail_id) {
        tail_image = cg_record_image_base(p, m, f, tail_id, tail, node); tail_bytes = cg_record_image_bytes(p, m, f, tail_id, tail, node);
    } else {
        cg_get(f, tail); wc_load(f.code, 4); tail_image = cg_save(f, wa());
        if cg_enum_image(p, tail_id) { tail_bytes = cg_enum_image_bytes(p, m, f, tail_id, tail, node); }
        else { tail_bytes = cg_array_image_bytes(p, m, f, tail_id, tail, node); }
    }
    let prefix = cg_record_prefix(p, id); cg_get(f, tail_bytes); wa_const(f.code, prefix); wa_op(f.code, 0x6a); let bytes = cg_save(f, wa());
    cg_get(f, bytes); cg_allocate(p, m, f, node); let image = cg_save(f, wa());
    var field = p.types[id].first; var offset = 0;
    while field >= 0 && field != tail_field {
        let n: const Node& = p.nodes[field];
        cg_get(f, image); wa_const(f.code, offset); wa_op(f.code, 0x6a);
        if (n.flags & F_PAD) != 0 { cg_clear_bytes(p, f, n.aux); offset += n.aux; }
        else {
            cg_get(f, owner); wa_const(f.code, n.integer); wa_op(f.code, 0x6a); wa_const(f.code, cg_size(p, n.type_id)); wb_copy(f.code); offset += cg_size(p, n.type_id);
        }
        field = n.next;
    }
    cg_get(f, image); wa_const(f.code, prefix); wa_op(f.code, 0x6a); cg_get(f, tail_image); cg_get(f, tail_bytes); wb_copy(f.code);
    cg_rebase_record_image(p, f, id, owner, image, bytes);
}
fn cg_copy_record_image(p: Program&, m: CgModule&, f: CgBody&, id: i64, destination: i64, source: i64, node: i64) {
    let original = cg_record_image_base(p, m, f, id, source, node); let bytes = cg_record_image_bytes(p, m, f, id, source, node);
    cg_get(f, bytes); cg_allocate(p, m, f, node); let image = cg_save(f, wa());
    cg_get(f, image); cg_get(f, original); cg_get(f, bytes); wb_copy(f.code);
    cg_get(f, destination); cg_get(f, source); wa_const(f.code, cg_size(p, id)); wb_copy(f.code);
    cg_rebase_record_image(p, f, id, destination, image, bytes);
}
recursive fn cg_default_storage(p: Program&, m: CgModule&, f: CgBody&, id: i64, destination: i64, node: i64) {
    cg_get(f, destination); cg_clear_bytes(p, f, cg_size(p, id));
    if cg_byte_record(p, id) { cg_construct_byte_record(p, m, f, id, destination, -1); return; }
    if cg_owner(p, id) {
        wa_const(f.code, 0); let count = cg_save(f, wa()); cg_owner_image(p, m, f, id, destination, count, count, node); return;
    }
    if cg_type_kind(p, id) == TY_STRUCT {
        var field = p.types[id].first;
        while field >= 0 {
            let n: const Node& = p.nodes[field];
            if (n.flags & F_PAD) == 0 && cg_aggregate(p, n.type_id) {
                cg_get(f, destination); wa_const(f.code, n.integer); wa_op(f.code, 0x6a); let address = cg_save(f, wa()); cg_default_storage(p, m, f, n.type_id, address, node);
            }
            field = n.next;
        }
        if cg_record_image(p, id) { cg_pack_record_image(p, m, f, id, destination, node); }
    }
}
fn cg_copy_runtime_limited(p: Program&, m: CgModule&, f: CgBody&, id: i64, destination: i64, source: i64, node: i64) {
    cg_owner_read_length(p, m, f, source, node); let count = cg_save(f, wa());
    cg_owner_read_capacity(p, m, f, source); let capacity = cg_save(f, wa());
    cg_get(f, count); cg_get(f, capacity); wa_op(f.code, 0x4b); cg_trap_if(p, m, f, node, "array image length exceeds capacity");
    let target = cg_owner_image(p, m, f, id, destination, count, capacity, node);
    cg_get(f, target); cg_owner_read_base(p, m, f, source, node);
    cg_get(f, capacity); wa_const(f.code, cg_size(p, p.types[id].element)); wa_op(f.code, 0x6c); wb_copy(f.code);
    if m.regions_enabled && !f.scratch { cg_get(f, target); cg_get(f, capacity); wa_const(f.code, cg_size(p, p.types[id].element)); wa_op(f.code, 0x6c); wa_op(f.code, 0x6a); let top = cg_save(f, wa()); cg_region_publish(f, destination, top); }
}

recursive fn cg_has_owner(p: Program&, id: i64) -> bool {
    if id < 13 { return false; }
    if cg_owner(p, id) || cg_byte_record(p, id) || cg_record_image(p, id) { return true; }
    if cg_type_kind(p, id) == TY_ENUM { return (p.types[id].flags & F_VARIABLE_MODE) != 0; }
    if cg_type_kind(p, id) != TY_STRUCT { return false; }
    let known = cg_memo_get(p, id, CG_MEMO_HAS_OWNER); if known >= 0 { return known == 1; }
    var field = p.types[id].first;
    while field >= 0 { if (p.nodes[field].flags & F_PAD) == 0 && cg_has_owner(p, p.nodes[field].type_id) { return cg_memo_set(p, id, CG_MEMO_HAS_OWNER, true); } field = p.nodes[field].next; }
    return cg_memo_set(p, id, CG_MEMO_HAS_OWNER, false);
}
fn cg_named_owner(p: Program&, f: CgBody&, node: i64, id: i64) -> bool {
    if p.nodes[node].kind != N_NAME || p.nodes[node].symbol < 0 || !cg_has_owner(p, id) { return false; }
    let symbol = p.symbols[p.nodes[node].symbol];
    return symbol.owner == f.function && (symbol.flags & (S_GLOBAL | S_PARAMETER)) == 0;
}
fn cg_resolve_pointer(m: CgModule&, f: CgBody&) { if m.resolver >= 0 { wb_op(f.code, 0x10, m.resolver); } }
fn cg_resolve_location(m: CgModule&, f: CgBody&, location: i64) -> i64 {
    if m.resolver < 0 { return location; }
    cg_get(f, location); cg_resolve_pointer(m, f); return cg_save(f, wa());
}
// A forwarding entry is four address-sized words: the previous entry, the
// span's start, its end, and the start of its replacement.
fn cg_forward_span(p: Program&, m: CgModule&, f: CgBody&, original: i64, bytes: i64, replacement: i64) {
    if m.forward_helper < 0 { return; }
    cg_get(f, original); cg_get(f, bytes); cg_get(f, replacement); wb_op(f.code, 0x10, m.forward_helper);
}
fn cg_forward_helper_body(m: CgModule&, out: u8[>..]&) {
    // (original, bytes, replacement) -> void. Indexes forwarded spans by 4 KiB
    // page in a lazily allocated bucket table stored in global 5.
    var bcount = 4096; var bshift = 2; if cg_wide { bcount = 16384; bshift = 3; }
    let bmask = bcount - 1; let bbytes = bcount * wa_bytes();
    wb_u(out, 1); wb_u(out, 6); wb_byte(out, wa());
    // Locals: 3=table, 4=end, 5=page, 6=last_page, 7=slot_addr, 8=entry
    wb_op(out, 0x20, 1); wa_op(out, 0x45); wb_byte(out, 0x04); wb_byte(out, 0x40); wb_byte(out, 0x0f); wb_byte(out, 0x0b);
    wb_op(out, 0x23, 5); wb_op(out, 0x22, 3); wa_op(out, 0x45); wb_byte(out, 0x04); wb_byte(out, 0x40);
    wa_const(out, bbytes); wb_op(out, 0x10, m.allocator); wb_op(out, 0x22, 3);
    wb_i32(out, 0); wa_const(out, bbytes); wb_fill(out);
    wb_op(out, 0x20, 3); wb_op(out, 0x24, 5); wb_byte(out, 0x0b);
    wb_op(out, 0x20, 0); wb_op(out, 0x20, 1); wa_op(out, 0x6a); wb_op(out, 0x21, 4);
    wb_op(out, 0x20, 0); wb_op(out, 0x23, 7); wa_op(out, 0x49); wb_byte(out, 0x04); wb_byte(out, 0x40);
    wb_op(out, 0x20, 0); wb_op(out, 0x24, 7); wb_byte(out, 0x0b);
    wb_op(out, 0x20, 4); wb_op(out, 0x23, 6); wa_op(out, 0x4b); wb_byte(out, 0x04); wb_byte(out, 0x40);
    wb_op(out, 0x20, 4); wb_op(out, 0x24, 6); wb_byte(out, 0x0b);
    wb_op(out, 0x20, 0); wa_const(out, 12); wa_op(out, 0x76); wb_op(out, 0x21, 5);
    wb_op(out, 0x20, 4); wa_const(out, 1); wa_op(out, 0x6b); wa_const(out, 12); wa_op(out, 0x76); wb_op(out, 0x21, 6);
    wb_op(out, 0x20, 6); wb_op(out, 0x20, 5); wa_op(out, 0x6b); wa_const(out, bmask); wa_op(out, 0x4b);
    wb_byte(out, 0x04); wb_byte(out, 0x40); wb_op(out, 0x20, 5); wa_const(out, bmask); wa_op(out, 0x6a); wb_op(out, 0x21, 6); wb_byte(out, 0x0b);
    wb_byte(out, 0x03); wb_byte(out, 0x40);
    wb_op(out, 0x20, 3); wb_op(out, 0x20, 5); wa_const(out, bmask); wa_op(out, 0x71); wa_const(out, bshift); wa_op(out, 0x74); wa_op(out, 0x6a); wb_op(out, 0x21, 7);
    wa_const(out, ww(4)); wb_op(out, 0x10, m.allocator); wb_op(out, 0x21, 8);
    wb_op(out, 0x20, 8); wb_op(out, 0x20, 7); wa_load(out, 0); wa_store(out, ww(0));
    wb_op(out, 0x20, 8); wb_op(out, 0x20, 0); wa_store(out, ww(1));
    wb_op(out, 0x20, 8); wb_op(out, 0x20, 4); wa_store(out, ww(2));
    wb_op(out, 0x20, 8); wb_op(out, 0x20, 2); wa_store(out, ww(3));
    wb_op(out, 0x20, 7); wb_op(out, 0x20, 8); wa_store(out, 0);
    wb_op(out, 0x20, 5); wb_op(out, 0x20, 6); wa_op(out, 0x49); wb_byte(out, 0x04); wb_byte(out, 0x40);
    wb_op(out, 0x20, 5); wa_const(out, 1); wa_op(out, 0x6a); wb_op(out, 0x21, 5); wb_op(out, 0x0c, 1); wb_byte(out, 0x0b);
    wb_byte(out, 0x0b); wb_byte(out, 0x0b);
}
fn cg_resolver_body(out: u8[>..]&) {
    // (address)->address. Looks up 4 KiB page bucket in global 5 and follows
    // transitive moves in O(1) expected time.
    var bmask = 4095; var bshift = 2; if cg_wide { bmask = 16383; bshift = 3; }
    wb_u(out, 1); wb_u(out, 3); wb_byte(out, wa());
    // Locals: 1=entry, 2=table, 3=orig
    wb_op(out, 0x20, 0); wb_op(out, 0x23, 7); wa_op(out, 0x49);
    wb_op(out, 0x20, 0); wb_op(out, 0x23, 6); wa_op(out, 0x4f); wb_byte(out, 0x72);
    wb_byte(out, 0x04); wb_byte(out, 0x40); wb_op(out, 0x20, 0); wb_byte(out, 0x0f); wb_byte(out, 0x0b);
    wb_op(out, 0x23, 5); wb_op(out, 0x22, 2); wa_op(out, 0x45);
    wb_byte(out, 0x04); wb_byte(out, 0x40); wb_op(out, 0x20, 0); wb_byte(out, 0x0f); wb_byte(out, 0x0b);
    wb_byte(out, 0x03); wb_byte(out, 0x40);
    wb_op(out, 0x20, 2); wb_op(out, 0x20, 0); wa_const(out, 12); wa_op(out, 0x76); wa_const(out, bmask); wa_op(out, 0x71); wa_const(out, bshift); wa_op(out, 0x74); wa_op(out, 0x6a); wa_load(out, 0); wb_op(out, 0x21, 1);
    wb_byte(out, 0x03); wb_byte(out, 0x40);
    wb_op(out, 0x20, 1); wa_op(out, 0x45); wb_byte(out, 0x04); wb_byte(out, 0x40); wb_op(out, 0x20, 0); wb_byte(out, 0x0f); wb_byte(out, 0x0b);
    wb_op(out, 0x20, 0); wb_op(out, 0x20, 1); wa_load(out, ww(1)); wb_op(out, 0x22, 3); wa_op(out, 0x4f);
    wb_op(out, 0x20, 0); wb_op(out, 0x20, 1); wa_load(out, ww(2)); wa_op(out, 0x49); wb_byte(out, 0x71);
    wb_byte(out, 0x04); wb_byte(out, 0x40);
    wb_op(out, 0x20, 0); wb_op(out, 0x20, 3); wa_op(out, 0x6b); wb_op(out, 0x20, 1); wa_load(out, ww(3)); wa_op(out, 0x6a); wb_op(out, 0x22, 0);
    wb_op(out, 0x23, 7); wa_op(out, 0x49); wb_op(out, 0x20, 0); wb_op(out, 0x23, 6); wa_op(out, 0x4f); wb_byte(out, 0x72);
    wb_byte(out, 0x04); wb_byte(out, 0x40); wb_op(out, 0x20, 0); wb_byte(out, 0x0f); wb_byte(out, 0x0b);
    wb_op(out, 0x0c, 2);
    wb_byte(out, 0x0b);
    wb_op(out, 0x20, 1); wa_load(out, ww(0)); wb_op(out, 0x21, 1); wb_op(out, 0x0c, 0);
    wb_byte(out, 0x0b); wb_byte(out, 0x0b);
    wb_op(out, 0x20, 0); wb_byte(out, 0x0b);
}
