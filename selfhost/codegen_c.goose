import model;
import std;
import checker_rendering;
import region_plan;
import codegen_c_storage;
import codegen_c_images;
import codegen_c_threads;

// Native C lowering shares the checked ID-based IR with the direct Wasm path.
// Runtime text contains storage/OS/formatting only; it never invokes a compiler.
let cc_runtime_header = embed_file("../native/runtime/runtime.h");
let cc_runtime_impl = embed_file("../native/runtime/runtime_impl.h");
let cc_runtime_threads = embed_file("../native/runtime/runtime_threads.h");
let cc_runtime = embed_file("../native/storage.h");
let cc_runtime_relative = embed_file("../native/relative.h");
let cc_runtime_pools = embed_file("../native/pools.h");
let cc_runtime_images = embed_file("../native/images.h");
let cc_runtime_workers = embed_file("../native/threads.h");

struct CcExit { node: i64, done: i64, again: i64 = -1, result: i64 = -1, type_id: i64 = TYPE_VOID, regions: i64 = 0, again_regions: i64 = 0, publications: i64 = -1 }
struct CcBody {
    out: u8[>..]&, exits: CcExit[>..]&, work: i64[>..]&, function: i64 = -1,
    serial: i64 = 0, result_type: i64 = TYPE_VOID,
    region_live: i64 = 0, region_peak: i64 = 0, function_index: i64 = -1, active_node: i64 = -1, receiver: i64 = -1,
    calls: RegionCall[>..]&, indices: i64[>..]&, temp_regions: i64[>..]&, destinations: CcDestination[>..]&, receiving: CcReceiving[>..]&, fills: CcFill[>..]&, indirect: i64[>..]&, channels: CcChannels[>..]&, cursors: CcCursor[>..]&, result_ref: i64 = -1,
}
fn cc_region_slot(f: CcBody&, width: i64) -> i64 {
    let slot = f.region_live; f.region_live += width;
    if f.region_live > f.region_peak { f.region_peak = f.region_live; }
    return slot;
}
fn cc_region_argument(f: CcBody&, slot: i64) {
    cc_text(f.out, "g_base+"); cc_number(f.out, slot);
}
fn cc_region_call(f: CcBody&, function: i64, node: i64) {
    if function >= 0 && function < f.indices.len && f.indices[function] >= 0 {
        f.calls.push(RegionCall { caller: f.function_index, callee: f.indices[function], live: f.region_live, node: node });
    }
}
fn cc_raw_array(f: CcBody&, name: const u8[:], id: i64) {
    let slot = cc_region_slot(f, 1);
    cc_text(f.out, "GArray "); cc_id(f.out, name, id); cc_text(f.out, "=g_array("); cc_region_argument(f, slot); cc_text(f.out, ");\n");
}
fn cc_seed(p: Program&, f: CcBody&, type_id: i64, name: const u8[:], id: i64) {
    let width = cc_region_width(p, type_id); if width == 0 { return; }
    let slot = cc_region_slot(f, width);
    cc_id(f.out, "g_init_", type_id); cc_text(f.out, "(g_ref(&"); cc_id(f.out, name, id); cc_text(f.out, "),");
    cc_region_argument(f, slot); cc_text(f.out, ");\n");
    if same_bytes(name, "g_v") {
        while f.temp_regions.len <= id { f.temp_regions.push(-1); }
        f.temp_regions[id] = slot;
    }
}
fn cc_restore(f: CcBody&, live: i64) {
    if f.region_live <= live { return; }
    cc_text(f.out, "g_restore_regions(g_base+"); cc_number(f.out, live); cc_text(f.out, ","); cc_number(f.out, f.region_live - live);
    cc_text(f.out, ",g_watermarks+"); cc_number(f.out, live); cc_text(f.out, ");\n");
}
fn cc_map_value(p: Program&, f: CcBody&, type_id: i64, value: i64, target: i64) {
    let width = cc_region_width(p, type_id); if width == 0 { return; }
    let links = f.serial; f.serial++;
    cc_id(f.out, "GPublication g_links", links); cc_text(f.out, "["); cc_number(f.out, width); cc_text(f.out, "];\n");
    cc_id(f.out, "g_map_", type_id); cc_text(f.out, "(g_ref(&"); cc_id(f.out, "g_v", value); cc_text(f.out, "),");
    cc_id(f.out, "g_v", target); cc_text(f.out, ","); cc_id(f.out, "g_links", links); cc_text(f.out, ");\n");
}
fn cc_alias_temp(p: Program&, f: CcBody&, type_id: i64, target: i64) -> i64 {
    let id = f.serial; f.serial++; cc_text(f.out, "#define "); cc_id(f.out, "g_v", id); cc_text(f.out, " (*("); cc_type(f.out, type_id);
    cc_text(f.out, "*)g_address("); cc_id(f.out, "g_v", target); cc_text(f.out, "))\n"); f.indirect.push(id); return id;
}
fn cc_alias_symbol(p: Program&, out: u8[>..]&, symbol: i64, target: i64) {
    cc_undef(out, "g_s", symbol); cc_text(out, "#define "); cc_id(out, "g_s", symbol); cc_text(out, " (*("); cc_type(out, p.symbols[symbol].type_id);
    cc_text(out, "*)g_address("); cc_id(out, "g_v", target); cc_text(out, "))\n");
}
fn cc_channels_address(f: CcBody&, value: i64) -> i64 {
    if value < 0 { return -1; }
    for item in f.channels { if item.value == value { return item.address; } } return -1;
}
fn cc_channels_place(f: CcBody&, address: i64) -> bool {
    for item in f.channels { if item.address == address { return true; } } return false;
}
fn cc_channel_target(p: Program&, f: CcBody&, address: i64, type_id: i64, ordinal: i64) -> i64 {
    let target = cc_ref_temp(f); cc_set(f, target);
    if cc_channels_place(f, address) {
        cc_text(f.out, "((GRef*)g_address("); cc_id(f.out, "g_v", address); cc_text(f.out, "))["); cc_number(f.out, ordinal); cc_text(f.out, "];\n");
    } else {
        cc_text(f.out, "g_offset("); cc_id(f.out, "g_v", address); cc_text(f.out, ",offsetof("); cc_type(f.out, type_id); cc_text(f.out, ","); cc_id(f.out, "f", ordinal); cc_text(f.out, "));\n");
    }
    return target;
}
recursive fn cc_tuple_value(p: Program&, f: CcBody&, value: i64, type_id: i64, ordinal: i64) -> i64 {
    var field = p.types[type_id].first; for index in 0..ordinal { field = p.nodes[field].next; }
    let address = cc_temporary_ref(f, value); let target = cc_channel_target(p, f, address, type_id, ordinal);
    return cc_read(p, f, CcPlace { type_id: p.nodes[field].type_id, address: target, form: CC_REGISTER }, p.nodes[field].type_id, -1);
}
fn cc_tuple_result(p: Program&, f: CcBody&, node: i64, type_id: i64) -> i64 {
    let result = cc_temp(p, f, type_id); let raw = f.serial; f.serial++;
    cc_id(f.out, "GRef g_channels", raw); cc_text(f.out, "["); cc_number(f.out, p.types[type_id].count); cc_text(f.out, "];\n");
    var receiving = -1;
    if cc_tuple_channels(p, type_id) && f.receiver >= 0 && f.active_node == node && cc_queue_same(p, f.destinations[f.receiver].type_id, type_id) {
        receiving = f.destinations[f.receiver].header; f.active_node = -1;
    }
    var field = p.types[type_id].first; var ordinal = 0;
    while field >= 0 {
        var target = -1;
        if receiving >= 0 { target = cc_channel_target(p, f, receiving, type_id, ordinal); }
        for item in f.receiving {
            if cc_tuple_channels(p, type_id) && item.call >= 0 && item.call == node && item.ordinal == ordinal && cc_queue_same(p, f.destinations[item.destination].type_id, p.nodes[field].type_id) {
                target = f.destinations[item.destination].header;
            }
        }
        cc_id(f.out, "g_channels", raw); cc_text(f.out, "["); cc_number(f.out, ordinal); cc_text(f.out, "]=");
        if target >= 0 { cc_id(f.out, "g_v", target); }
        else { cc_text(f.out, "g_ref(&"); cc_id(f.out, "g_v", result); cc_id(f.out, ".f", ordinal); cc_text(f.out, ")"); }
        cc_text(f.out, ";\n"); field = p.nodes[field].next; ordinal++;
    }
    let address = cc_ref_temp(f); cc_set(f, address); cc_text(f.out, "g_ref("); cc_id(f.out, "g_channels", raw); cc_text(f.out, ");\n");
    f.channels.push(CcChannels { value: result, address: address }); return result;
}
fn cc_result_temp(p: Program&, f: CcBody&, node: i64, type_id: i64) -> i64 {
    if cc_kind(p, type_id) == TY_TUPLE { return cc_tuple_result(p, f, node, type_id); }
    if f.receiver >= 0 && f.active_node == node && cc_result_location(p, type_id) && cc_queue_same(p, f.destinations[f.receiver].type_id, type_id) {
        let target = f.destinations[f.receiver].header; f.active_node = -1; return cc_alias_temp(p, f, type_id, target);
    }
    if f.receiver < 0 || f.active_node != node || f.destinations[f.receiver].type_id != type_id || cc_region_width(p, type_id) == 0 || cc_kind(p, type_id) == TY_ENUM {
        return cc_temp(p, f, type_id);
    }
    let target = f.destinations[f.receiver].header; f.active_node = -1;
    let result = cc_temp(p, f, type_id, true, false);
    cc_set(f, result); cc_id(f.out, "g_load_", type_id); cc_text(f.out, "("); cc_id(f.out, "g_v", target); cc_text(f.out, ");\n");
    cc_map_value(p, f, type_id, result, target);
    return result;
}
fn cc_diverges(p: Program&, node: i64) -> bool {
    if node < 0 { return false; }
    let n = p.nodes[node];
    return (n.flags & F_DIVERGES) != 0 || n.kind == N_RETURN || n.kind == N_BREAK || n.kind == N_CONTINUE;
}
recursive fn cc_construct_into(p: Program&, f: CcBody&, node: i64, type_id: i64, target: i64, form: i64 = 0) -> i64 {
    let previous = f.receiver; let active = f.active_node; let destination = f.destinations.len;
    f.destinations.push(CcDestination { type_id: type_id, header: target, stack: -1, lifetime: 2, form: form });
    f.receiver = destination; f.active_node = node;
    let publications = f.serial; f.serial++;
    cc_id(f.out, "GPublication *g_saved_publications", publications); cc_text(f.out, "=g_publication_top;\n");
    var value = -1;
    if node < 0 { value = cc_default(p, f, type_id); } else { value = cc_to(p, f, node, type_id); }
    if value >= 0 { cc_write(p, f, CcPlace { type_id: type_id, address: target, form: form }, value, node); }
    cc_text(f.out, "g_publication_top="); cc_id(f.out, "g_saved_publications", publications); cc_text(f.out, ";\n");
    f.receiver = previous; f.active_node = active;
    return value;
}
fn cc_bind_named_results(p: Program&, f: CcBody&, node: i64, type_id: i64, target: i64) {
    let n = p.nodes[node];
    if n.kind == N_FUNCTION_VALUE { return; }
    if n.kind == N_BLOCK && (n.origin < 0 || p.nodes[n.origin].kind != N_FUNCTION) { return; }
    var binding = n.named_results;
    while binding >= 0 {
        let b = p.nodes[binding]; var result_type = type_id; var field = -1;
        if cc_kind(p, type_id) == TY_TUPLE {
            field = p.types[type_id].first;
            for index in 0..b.integer { if field >= 0 { field = p.nodes[field].next; } }
            if field < 0 { binding = b.next; continue; } result_type = p.nodes[field].type_id;
        }
        if b.symbol >= 0 && result_type == p.symbols[b.symbol].type_id && (cc_region_width(p, result_type) > 0 || cc_result_location(p, result_type)) {
            let original = p.symbols[b.symbol].node;
            if original >= 0 && p.nodes[original].origin >= 0 && p.nodes[p.nodes[original].origin].kind == N_PARAM { binding = b.next; continue; }
            var header = target;
            if field >= 0 {
                header = cc_channel_target(p, f, target, type_id, b.integer);
            }
            let destination = f.destinations.len;
            f.destinations.push(CcDestination { type_id: result_type, header: header, stack: -1, lifetime: 3 });
            f.receiving.push(CcReceiving { ordinal: b.integer, destination: destination, symbol: b.symbol });
        }
        binding = b.next;
    }
}
fn cc_seed_symbol(p: Program&, f: CcBody&, symbol: i64) {
    let type_id = p.symbols[symbol].type_id; var index = f.receiving.len;
    while index > 0 {
        index--;
        let receiving = f.receiving[index];
        if receiving.symbol != symbol { continue; }
        let target = f.destinations[receiving.destination].header;
        if cc_result_location(p, type_id) { cc_alias_symbol(p, f.out, symbol, target); return; }
        cc_text(f.out, "memcpy(&"); cc_id(f.out, "g_s", symbol); cc_text(f.out, ",g_address("); cc_id(f.out, "g_v", target); cc_text(f.out, "),sizeof("); cc_type(f.out, type_id); cc_text(f.out, "));\n");
        return;
    }
    cc_seed(p, f, type_id, "g_s", symbol);
    let mode = cc_pool_mode(p, symbol);
    if mode > 0 {
        let slot = cc_region_slot(f, 1); cc_text(f.out, "g_pool_init(g_ref(&"); cc_id(f.out, "g_s", symbol); cc_text(f.out, "),");
        cc_region_argument(f, slot); cc_text(f.out, ","); cc_number(f.out, mode); cc_text(f.out, ");\n");
    }
}
fn cc_emit_map(p: Program&, out: u8[>..]&, id: i64) {
    let width = cc_region_width(p, id); if width == 0 { return; } let t = p.types[id];
    cc_id(out, "static void g_map_", id); cc_text(out, "(GRef source,GRef target,GPublication *links){\n");
    if cc_owner(p, id) || cc_image_type(p, id) { cc_text(out, "g_map_header(links,source,target);\n"); }
    else if t.kind == TY_STRUCT && t.declaration >= 0 {
        var field = p.nodes[t.declaration].first; var offset = 0;
        while field >= 0 {
            let n = p.nodes[field]; let count = cc_region_width(p, n.type_id);
            if count > 0 && (n.flags & F_PAD) == 0 {
                cc_id(out, "g_map_", n.type_id); cc_text(out, "(g_offset(source,"); cc_number(out, cc_field_offset(p, id, field));
                cc_text(out, "),g_offset(target,"); cc_number(out, cc_field_offset(p, id, field)); cc_text(out, "),links+"); cc_number(out, offset); cc_text(out, ");\n"); offset += count;
            }
            field = n.next;
        }
    } else if t.kind == TY_TUPLE {
        var field = t.first; var ordinal = 0; var offset = 0;
        while field >= 0 {
            let count = cc_region_width(p, p.nodes[field].type_id);
            if count > 0 {
                cc_id(out, "g_map_", p.nodes[field].type_id); cc_text(out, "(g_offset(source,offsetof("); cc_type(out, id); cc_text(out, ","); cc_id(out, "f", ordinal);
                cc_text(out, ")),g_offset(target,offsetof("); cc_type(out, id); cc_text(out, ","); cc_id(out, "f", ordinal);
                cc_text(out, ")),links+"); cc_number(out, offset); cc_text(out, ");\n"); offset += count;
            }
            ordinal++; field = p.nodes[field].next;
        }
    } else if t.kind == TY_ENUM && t.declaration >= 0 {
        cc_text(out, "switch(g_read_length(g_address(source),"); cc_number(out, t.length_storage); cc_text(out, ")){\n");
        var variant = p.nodes[t.declaration].first;
        while variant >= 0 {
            let payload = p.nodes[variant].type_id;
            if cc_region_width(p, payload) > 0 {
                cc_text(out, "case "); cc_number(out, p.nodes[variant].integer); cc_text(out, ":"); cc_id(out, "g_map_", payload);
                cc_text(out, "(g_offset(source,"); cc_number(out, t.length_storage); cc_text(out, "),g_offset(target,"); cc_number(out, t.length_storage); cc_text(out, "),links);break;\n");
            }
            variant = p.nodes[variant].next;
        }
        cc_text(out, "default:break;}\n");
    }
    cc_text(out, "}\n");
}
fn cc_text(out: u8[>..]&, text: const u8[:]) { out.append(text); }
fn cc_number(out: u8[>..]&, value: i64) { out.format(value); }
fn cc_id(out: u8[>..]&, prefix: const u8[:], id: i64) { cc_text(out, prefix); cc_number(out, id); }
fn cc_type(out: u8[>..]&, type_id: i64) { cc_id(out, "g_t", type_id); }
fn cc_fail(p: Program&, node: i64, message: const u8[:]) {
    var token: i64 = -1; if node >= 0 && node < p.nodes.len { token = p.nodes[node].token; }
    diagnose(p, token, message);
}
fn cc_aggregate(p: Program&, type_id: i64) -> bool {
    let kind = cc_kind(p, type_id); return kind == TY_ARRAY || kind == TY_STRUCT || kind == TY_ENUM || kind == TY_TUPLE;
}
fn cc_owner(p: Program&, type_id: i64) -> bool {
    if cc_kind(p, type_id) != TY_ARRAY { return false; }
    let t = p.types[type_id]; return t.array_kind == A_GROW || t.array_kind == A_GROWSHRINK;
}
fn cc_array_args(p: Program&, out: u8[>..]&, type_id: i64, width: bool = true) {
    let t = p.types[type_id]; cc_number(out, cc_array_kind(p, type_id)); cc_text(out, ",");
    cc_number(out, t.count); cc_text(out, ","); cc_number(out, cc_prefix(p, type_id));
    if width { cc_text(out, ","); cc_number(out, cc_frame_size(p, t.element)); }
}
fn cc_fixed(out: u8[>..]&, type_id: i64, prefix: const u8[:], id: i64, zero: bool = true) {
    cc_text(out, "GFixed g_fixed_"); cc_id(out, prefix, id); cc_text(out, " __attribute__((cleanup(g_fixed_release)))=g_fixed_begin(sizeof("); cc_type(out, type_id);
    cc_text(out, "),"); if zero { cc_text(out, "1"); } else { cc_text(out, "0"); } cc_text(out, ");\n#define "); cc_id(out, prefix, id);
    cc_text(out, " (*("); cc_type(out, type_id); cc_text(out, "*)"); cc_text(out, "g_fixed_"); cc_id(out, prefix, id); cc_text(out, ".data)\n");
}
fn cc_undef(out: u8[>..]&, prefix: const u8[:], id: i64) { cc_text(out, "#undef "); cc_id(out, prefix, id); cc_text(out, "\n"); }
fn cc_temp(p: Program&, f: CcBody&, type_id: i64, zero: bool = true, seed: bool = true) -> i64 {
    if cc_kind(p, type_id) == TY_VOID { return -1; }
    if type_id < 0 { cc_fail(p, f.function, "c: expression lacks a checked type"); return -1; }
    if cc_image_type(p, type_id) && !cc_image_constructible(p, type_id) { cc_fail(p, f.function, "c: variable image fields require canonical array/reference cursors"); }
    if cc_variable_prefix_frame(p, type_id) { cc_fail(p, f.function, "c: variable-prefix frames require physical tail views"); }
    if cc_kind(p, type_id) == TY_ARRAY && cc_size_class(p, p.types[type_id].element) == 1 && (!cc_image_constructible(p, p.types[type_id].element) || cc_relative_fields(p, p.types[type_id].element)) { cc_fail(p, f.function, "c: variable element requires a canonical image constructor"); }
    if cc_aggregate(p, type_id) && cc_relative_fields(p, type_id) && !cc_result_location(p, type_id) {
        cc_fail(p, f.function, "c: variable relative images require physical cursor lowering");
    }
    if cc_relative_cell(p, type_id) && !cc_fixed_storage(p, p.types[type_id].element) { cc_fail(p, f.function, "c: relative pointers to variable images require physical views"); }
    let id = f.serial; f.serial++;
    if cc_indirect(p, type_id) {
        cc_fixed(f.out, type_id, "g_v", id, zero); f.indirect.push(id);
        if seed { cc_seed(p, f, type_id, "g_v", id); } return id;
    }
    cc_type(f.out, type_id); cc_text(f.out, " "); cc_id(f.out, "g_v", id);
    if zero { cc_text(f.out, "="); cc_zero_initializer(p, f.out, type_id); }
    cc_text(f.out, ";\n"); if seed { cc_seed(p, f, type_id, "g_v", id); } return id;
}
fn cc_ref_temp(f: CcBody&) -> i64 {
    let id = f.serial; f.serial++; cc_id(f.out, "GRef g_v", id); cc_text(f.out, "=0;\n"); return id;
}
fn cc_set(f: CcBody&, id: i64) { cc_id(f.out, "g_v", id); cc_text(f.out, "="); }
fn cc_load(p: Program&, f: CcBody&, ref: i64, type_id: i64) -> i64 {
    if cc_flat_relative_image(p, type_id) { cc_fail(p, f.function, "c: relative image load requires its bounded owner view"); return -1; }
    if cc_result_location(p, type_id) && cc_relative_fields(p, type_id, true) { return cc_alias_temp(p, f, type_id, ref); }
    let value = cc_temp(p, f, type_id, true, false); if value < 0 { return value; }
    cc_set(f, value); cc_id(f.out, "g_load_", type_id); cc_text(f.out, "("); cc_id(f.out, "g_v", ref); cc_text(f.out, ");\n"); return value;
}
recursive fn cc_read(p: Program&, f: CcBody&, place: CcPlace, wanted: i64, node: i64) -> i64 {
    if place.form == CC_IMAGE && cc_flat_relative_image(p, place.type_id) {
        if place.owner_header < 0 || place.image_end < 0 { cc_fail(p, node, "c: whole relative image needs its bounded owner view"); return -1; }
        let value = cc_temp(p, f, place.type_id, true, false); cc_text(f.out, "memcpy(&"); cc_id(f.out, "g_v", value); cc_text(f.out, ",g_address("); cc_id(f.out, "g_v", place.owner_header); cc_text(f.out, "),sizeof(GImage));\n");
        return cc_convert(p, f, value, place.type_id, wanted, node);
    }
    if place.form == CC_IMAGE && place.image_end >= 0 {
        let value = cc_temp(p, f, place.type_id); cc_set(f, value); cc_id(f.out, "g_physical_load_", place.type_id); cc_text(f.out, "(g_address("); cc_id(f.out, "g_v", place.address); cc_text(f.out, "),g_address("); cc_id(f.out, "g_v", place.image_end); cc_text(f.out, "));\n");
        return cc_convert(p, f, value, place.type_id, wanted, node);
    }
    if place.form == CC_IMAGE && cc_relative_cell(p, place.type_id) && p.types[place.type_id].length_storage == 0 { cc_fail(p, node, "c: varint relative image cells require physical receiver cursors"); return -1; }
    if cc_kind(p, place.type_id) == TY_INT && p.types[place.type_id].storage != 0 && place.form != CC_REGISTER {
        let value = cc_load(p, f, place.address, place.type_id); return cc_convert(p, f, value, place.type_id, wanted, node);
    }
    if place.form != CC_IMAGE && cc_image_type(p, place.type_id) || place.form == CC_REGISTER && cc_kind(p, place.type_id) == TY_INT && p.types[place.type_id].storage != 0 {
        let value = cc_temp(p, f, place.type_id, true, false); cc_text(f.out, "memcpy(&"); cc_id(f.out, "g_v", value); cc_text(f.out, ",g_address("); cc_id(f.out, "g_v", place.address); cc_text(f.out, "),sizeof("); cc_id(f.out, "g_v", value); cc_text(f.out, "));\n");
        return cc_convert(p, f, value, place.type_id, wanted, node);
    }
    if place.form == CC_REGISTER && cc_relative_cell(p, place.type_id) {
        let value = cc_temp(p, f, place.type_id); cc_text(f.out, "memcpy(&"); cc_id(f.out, "g_v", value); cc_text(f.out, ",g_address("); cc_id(f.out, "g_v", place.address); cc_text(f.out, "),sizeof(GRef));\n");
        return cc_convert(p, f, value, place.type_id, wanted, node);
    }
    if place.form == 0 && cc_relative_cell(p, place.type_id) {
        let value = cc_temp(p, f, place.type_id); cc_set(f, value); cc_id(f.out, "g_load_", place.type_id); cc_text(f.out, "("); cc_id(f.out, "g_v", place.address); cc_text(f.out, ");\n");
        return cc_convert(p, f, value, place.type_id, wanted, node);
    }
    return cc_load(p, f, place.address, wanted);
}
fn cc_relative_origin(p: Program&, out: u8[>..]&, type_id: i64) {
    let pool = p.types[type_id].pool;
    if pool >= 0 { cc_id(out, "g_pool_origin_", pool); cc_text(out, "()"); } else { cc_text(out, "0"); }
}
fn cc_pool_origins(p: Program&, out: u8[>..]&, definitions: bool = false) {
    var seen: bool[>..] = []; seen.resize(p.symbols.len, false);
    for t in p.types {
        if t.kind != TY_REF || t.length_storage < 0 || t.pool < 0 || t.pool >= p.symbols.len || seen[t.pool] { continue; }
        if (p.symbols[t.pool].flags & S_GLOBAL) == 0 { continue; } seen[t.pool] = true;
        cc_id(out, "static GRef g_pool_origin_", t.pool); cc_text(out, "(void)");
        if !definitions { cc_text(out, ";\n"); continue; }
        cc_text(out, "{GRef base=g_ref(&"); cc_id(out, "g_s", t.pool); cc_text(out, ");\n"); var array = p.symbols[t.pool].type_id;
        while cc_kind(p, array) == TY_REF { cc_text(out, "memcpy(&base,g_address(base),sizeof base);\n"); array = p.types[array].element; }
        cc_text(out, "return g_element(base,"); cc_array_args(p, out, array); cc_text(out, ",0,1)-(uintptr_t)1;}\n");
    }
}
fn cc_relative_check(p: Program&, f: CcBody&, value: i64, type_id: i64, node: i64) {
    if !cc_relative_cell(p, type_id) { return; }
    let raw = f.serial; f.serial++;
    if p.types[type_id].length_storage == 0 { cc_id(f.out, "GVarRelative g_check", raw); cc_text(f.out, "={0};\ng_relative_store(g_ref(&"); }
    else { cc_id(f.out, "uint8_t g_check", raw); cc_text(f.out, "[8];\ng_relative_store(g_ref("); }
    cc_id(f.out, "g_check", raw);
    cc_text(f.out, "),"); cc_id(f.out, "g_v", value); cc_text(f.out, ","); cc_number(f.out, p.types[type_id].length_storage); cc_text(f.out, ",");
    if (p.types[type_id].flags & TF_OPTIONAL) != 0 { cc_text(f.out, "1"); } else { cc_text(f.out, "0"); }
    cc_text(f.out, ","); cc_relative_origin(p, f.out, type_id); cc_text(f.out, ","); cc_location(p, f.out, node); cc_text(f.out, ");\n");
}
fn cc_return_store(p: Program&, f: CcBody&, value: i64, type_id: i64) {
    if cc_tuple_channels(p, type_id) { cc_store(p, f, f.result_ref, value, type_id); return; }
    if cc_kind(p, type_id) == TY_TUPLE {
        var field = p.types[type_id].first; var ordinal = 0;
        while field >= 0 {
            let part = cc_tuple_value(p, f, value, type_id, ordinal); cc_id(f.out, "g_result.f", ordinal); cc_text(f.out, "="); cc_id(f.out, "g_v", part); cc_text(f.out, ";\n");
            field = p.nodes[field].next; ordinal++;
        }
        return;
    }
    if cc_relative_cell(p, type_id) || cc_kind(p, type_id) == TY_INT && p.types[type_id].storage != 0 { cc_text(f.out, "g_result="); cc_id(f.out, "g_v", value); cc_text(f.out, ";\n"); }
    else { cc_id(f.out, "g_store_", type_id); cc_text(f.out, "(g_ref((void*)&g_result),"); cc_id(f.out, "g_v", value); cc_text(f.out, ");\n"); }
}
fn cc_write(p: Program&, f: CcBody&, place: CcPlace, value: i64, node: i64) {
    if place.form == CC_IMAGE && cc_relative_cell(p, place.type_id) && p.types[place.type_id].length_storage == 0 { cc_fail(p, node, "c: varint relative image cells require physical receiver cursors"); return; }
    if place.form == CC_REGISTER && cc_kind(p, place.type_id) == TY_INT && p.types[place.type_id].storage != 0 {
        cc_text(f.out, "memmove(g_address("); cc_id(f.out, "g_v", place.address); cc_text(f.out, "),&"); cc_id(f.out, "g_v", value); cc_text(f.out, ",sizeof(int64_t));\n"); return;
    }
    if place.form == 1 && cc_relative_cell(p, place.type_id) {
        cc_text(f.out, "memmove(g_address("); cc_id(f.out, "g_v", place.address); cc_text(f.out, "),&"); cc_id(f.out, "g_v", value); cc_text(f.out, ",sizeof(GRef));\n"); return;
    }
    cc_store(p, f, place.address, value, place.type_id, node);
}
fn cc_value_form(p: Program&, type_id: i64) -> i64 { if cc_relative_cell(p, type_id) || cc_kind(p, type_id) == TY_INT && p.types[type_id].storage != 0 { return CC_REGISTER; } return CC_NATIVE; }
recursive fn cc_copy_tuple(p: Program&, f: CcBody&, target: i64, value: i64, type_id: i64) {
    let source = cc_temporary_ref(f, value); let start = f.work.len; var field = p.types[type_id].first; var ordinal = 0;
    while field >= 0 { f.work.push(cc_tuple_value(p, f, value, type_id, ordinal)); field = p.nodes[field].next; ordinal++; }
    field = p.types[type_id].first; ordinal = 0;
    while field >= 0 {
        let destination = cc_channel_target(p, f, target, type_id, ordinal); let origin = cc_channel_target(p, f, source, type_id, ordinal);
        cc_text(f.out, "if("); cc_id(f.out, "g_v", destination); cc_text(f.out, "!="); cc_id(f.out, "g_v", origin); cc_text(f.out, "){\n");
        cc_write(p, f, CcPlace { type_id: p.nodes[field].type_id, address: destination, form: CC_REGISTER }, f.work[start + ordinal], -1); cc_text(f.out, "}\n");
        field = p.nodes[field].next; ordinal++;
    }
    f.work.resize(start);
}
recursive fn cc_store(p: Program&, f: CcBody&, ref: i64, value: i64, type_id: i64, node: i64 = -1) {
    if ref < 0 || value < 0 { return; }
    if cc_kind(p, type_id) == TY_TUPLE { cc_copy_tuple(p, f, ref, value, type_id); return; }
    if cc_relative_cell(p, type_id) {
        cc_text(f.out, "g_relative_store("); cc_id(f.out, "g_v", ref); cc_text(f.out, ","); cc_id(f.out, "g_v", value); cc_text(f.out, ","); cc_number(f.out, p.types[type_id].length_storage);
        cc_text(f.out, ","); if (p.types[type_id].flags & TF_OPTIONAL) != 0 { cc_text(f.out, "1"); } else { cc_text(f.out, "0"); }
        cc_text(f.out, ","); cc_relative_origin(p, f.out, type_id); cc_text(f.out, ","); var location = node; if location < 0 { location = f.function; } cc_location(p, f.out, location); cc_text(f.out, ");\n"); return;
    }
    cc_id(f.out, "g_store_", type_id); cc_text(f.out, "("); cc_id(f.out, "g_v", ref); cc_text(f.out, ","); cc_id(f.out, "g_v", value); cc_text(f.out, ");\n");
}
fn cc_temporary_ref(f: CcBody&, value: i64) -> i64 {
    let channels = cc_channels_address(f, value); if channels >= 0 { return channels; }
    let ref = cc_ref_temp(f); cc_set(f, ref); cc_text(f.out, "g_ref(&"); cc_id(f.out, "g_v", value); cc_text(f.out, ");\n"); return ref;
}
fn cc_symbol_ref(p: Program&, f: CcBody&, symbol: i64, node: i64) -> i64 {
    if symbol < 0 || symbol >= p.symbols.len { cc_fail(p, node, "c: unresolved place"); return -1; }
    let s = p.symbols[symbol]; let ref = cc_ref_temp(f); cc_set(f, ref);
    if s.owner == f.function || (s.flags & S_GLOBAL) != 0 {
        cc_text(f.out, "g_ref(&"); cc_id(f.out, "g_s", symbol); cc_text(f.out, ");\n"); return ref;
    }
    var capture = p.nodes[f.function].captures; var index = 0;
    while capture >= 0 {
        if p.nodes[capture].symbol == symbol {
            cc_text(f.out, "g_env->captures["); cc_number(f.out, index); cc_text(f.out, "];\n"); return ref;
        }
        index++; capture = p.nodes[capture].next;
    }
    cc_text(f.out, "0;\n"); cc_fail(p, node, "c: captured variable missing from closure environment"); return -1;
}
fn cc_image_address(p: Program&, f: CcBody&, place: CcPlace) -> CcPlace {
    let address = cc_ref_temp(f); cc_set(f, address); cc_text(f.out, "g_ref(((GImage*)g_address("); cc_id(f.out, "g_v", place.address); cc_text(f.out, "))->base);\n");
    var end = -1;
    if cc_flat_relative_image(p, place.type_id) {
        end = cc_ref_temp(f); cc_set(f, end); cc_text(f.out, "g_ref(((GImage*)g_address("); cc_id(f.out, "g_v", place.address); cc_text(f.out, "))->end);\n");
    }
    return CcPlace { type_id: place.type_id, address: address, form: CC_IMAGE, owner_header: place.address, image_base: address, image_end: end };
}
recursive fn cc_image_reference_owner(p: Program&, f: CcBody&, node: i64, depth: i64 = 0) -> i64 {
    if node < 0 || depth > 32 { return -1; }
    let n = p.nodes[node];
    if cc_flat_relative_image(p, n.type_id) && n.kind == N_NAME { return cc_symbol_ref(p, f, n.symbol, node); }
    if n.kind == N_UNARY && n.integer == T_BITAND { return cc_image_reference_owner(p, f, n.left, depth + 1); }
    if n.kind == N_CAST && (n.flags & F_SYNTHETIC) != 0 { return cc_image_reference_owner(p, f, n.left, depth + 1); }
    if n.kind != N_NAME || n.symbol < 0 { return -1; }
    let symbol = p.symbols[n.symbol]; if !cc_flat_image_reference(p, symbol.type_id) || symbol.node < 0 { return -1; }
    let declaration = p.nodes[symbol.node];
    if (declaration.flags & F_VAR) != 0 { return -1; }
    if declaration.kind == N_PARAM && symbol.owner == f.function {
        let owner = cc_ref_temp(f); cc_set(f, owner); cc_id(f.out, "g_image_owner_", n.symbol); cc_text(f.out, ";\n"); return owner;
    }
    if declaration.kind == N_VARIABLE && declaration.right >= 0 { return cc_image_reference_owner(p, f, declaration.right, depth + 1); }
    return -1;
}
recursive fn cc_base_place(p: Program&, f: CcBody&, node: i64) -> CcPlace {
    if cc_kind(p, p.nodes[node].type_id) == TY_REF {
        let type_id = p.types[p.nodes[node].type_id].element; let address = cc_expr(p, f, node);
        if cc_flat_relative_image(p, type_id) {
            let owner = cc_image_reference_owner(p, f, node);
            if owner < 0 { cc_fail(p, node, "c: relative image reference has no proved owner authority"); return CcPlace { type_id: -1, address: -1 }; }
            cc_text(f.out, "if(((GImage*)g_address("); cc_id(f.out, "g_v", owner); cc_text(f.out, "))->base!=g_address("); cc_id(f.out, "g_v", address); cc_text(f.out, "))g_panic(\"image reference owner mismatch\");\n");
            cc_text(f.out, "(void)g_image_span(*(GImage*)g_address("); cc_id(f.out, "g_v", owner); cc_text(f.out, "));\n");
            let end = cc_ref_temp(f); cc_set(f, end); cc_text(f.out, "g_ref(((GImage*)g_address("); cc_id(f.out, "g_v", owner); cc_text(f.out, "))->end);\n");
            return CcPlace { type_id: type_id, address: address, form: CC_IMAGE, image_base: address, owner_header: owner, image_end: end };
        }
        if cc_image_type(p, type_id) { return CcPlace { type_id: type_id, address: address, form: CC_IMAGE, image_base: address }; }
        return CcPlace { type_id: type_id, address: address };
    }
    let place = cc_place_location(p, f, node);
    if place.form == CC_NATIVE && cc_image_type(p, place.type_id) { return cc_image_address(p, f, place); } return place;
}
recursive fn cc_base(p: Program&, f: CcBody&, node: i64) -> i64 { return cc_base_place(p, f, node).address; }
recursive fn cc_place(p: Program&, f: CcBody&, node: i64) -> i64 { return cc_place_location(p, f, node).address; }
recursive fn cc_reference_place(p: Program&, f: CcBody&, node: i64) -> i64 {
    if cc_image_type(p, cc_place_type(p, node)) { return cc_base_place(p, f, node).address; } return cc_place(p, f, node);
}
fn cc_cursor_symbol(p: Program&, node: i64) -> i64 {
    var at = node;
    while at >= 0 && p.nodes[at].kind == N_UNARY && p.nodes[at].integer == T_MUL { at = p.nodes[at].left; }
    if at >= 0 && p.nodes[at].kind == N_NAME { return p.nodes[at].symbol; } return -1;
}
recursive fn cc_place_location(p: Program&, f: CcBody&, node: i64) -> CcPlace {
    if node < 0 { cc_fail(p, node, "c: missing place"); return CcPlace { type_id: -1, address: -1 }; }
    let n = p.nodes[node]; let type_id = cc_place_type(p, node);
    if n.kind == N_UNARY && n.integer == T_MUL { return cc_base_place(p, f, n.left); }
    if n.kind == N_NAME { return CcPlace { type_id: type_id, address: cc_symbol_ref(p, f, n.symbol, node) }; }
    if n.kind == N_MEMBER {
        let base = cc_base_place(p, f, n.left);
        if base.address < 0 || n.symbol < 0 { cc_fail(p, node, "c: member has no checked field"); return CcPlace { type_id: -1, address: -1 }; }
        let ref = cc_ref_temp(f); cc_set(f, ref);
        if base.form == CC_IMAGE {
            if cc_flat_relative_image(p, base.type_id) && base.image_end < 0 { cc_fail(p, node, "c: relative image member requires its bounded owner view"); return CcPlace { type_id: -1, address: -1 }; }
            cc_text(f.out, "g_ref(g_address("); cc_id(f.out, "g_v", base.address); cc_text(f.out, "));\n");
            var field = p.nodes[p.types[base.type_id].declaration].first;
            while field >= 0 && field != n.symbol {
                let previous = p.nodes[field];
                if base.image_end >= 0 && (previous.flags & F_PAD) != 0 && previous.aux == 0 { field = previous.next; continue; }
                cc_set(f, ref);
                if base.image_end >= 0 {
                    cc_text(f.out, "g_ref(g_relative_cell_skip(g_address("); cc_id(f.out, "g_v", ref); cc_text(f.out, "),g_address("); cc_id(f.out, "g_v", base.image_end); cc_text(f.out, "),");
                    if (previous.flags & F_PAD) != 0 { cc_number(f.out, previous.aux); } else { cc_number(f.out, cc_physical_cell_width(p, previous.type_id)); }
                    cc_text(f.out, "));\n");
                }
                else if (previous.flags & F_PAD) != 0 { cc_text(f.out, "g_offset("); cc_id(f.out, "g_v", ref); cc_text(f.out, ","); cc_number(f.out, previous.aux); cc_text(f.out, ");\n"); }
                else { cc_text(f.out, "g_ref(g_physical_skip_"); cc_number(f.out, previous.type_id); cc_text(f.out, "(g_address("); cc_id(f.out, "g_v", ref); cc_text(f.out, ")));\n"); }
                field = previous.next;
            }
            if base.image_end >= 0 { cc_text(f.out, "(void)g_relative_cell_skip(g_address("); cc_id(f.out, "g_v", ref); cc_text(f.out, "),g_address("); cc_id(f.out, "g_v", base.image_end); cc_text(f.out, "),"); cc_number(f.out, cc_physical_cell_width(p, type_id)); cc_text(f.out, ");\n"); }
            return CcPlace { type_id: type_id, address: ref, form: CC_IMAGE, stack: base.stack, owner_header: base.owner_header, image_base: base.image_base, image_end: base.image_end };
        }
        cc_text(f.out, "g_offset("); cc_id(f.out, "g_v", base.address); cc_text(f.out, ","); cc_number(f.out, cc_field_offset(p, p.nodes[n.left].type_id, n.symbol)); cc_text(f.out, ");\n");
        return CcPlace { type_id: type_id, address: ref };
    }
    if n.kind == N_INDEX {
        let base = cc_base(p, f, n.left); let index = cc_to(p, f, n.right, TYPE_I64);
        var array = p.nodes[n.left].type_id; if cc_kind(p, array) == TY_REF { array = p.types[array].element; }
        if cc_kind(p, array) != TY_ARRAY && cc_kind(p, array) != TY_SLICE { cc_fail(p, node, "c: indexing a non-array"); return CcPlace { type_id: -1, address: -1 }; }
        if cc_size_class(p, type_id) == 1 {
            for cursor in f.cursors {
                if cc_cursor_symbol(p, n.left) >= 0 && p.nodes[n.right].kind == N_NAME && cursor.symbol == cc_cursor_symbol(p, n.left) && cursor.index == p.nodes[n.right].symbol {
                    cc_text(f.out, "if("); cc_id(f.out, "g_v", index); cc_text(f.out, "<0 || "); cc_id(f.out, "g_v", index); cc_text(f.out, ">=g_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, array, false); cc_text(f.out, "))g_index_fail("); cc_id(f.out, "g_v", index); cc_text(f.out, ",g_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, array, false); cc_text(f.out, "),"); cc_location(p, f.out, node); cc_text(f.out, ");\n");
                    return CcPlace { type_id: type_id, address: cursor.address, form: CC_IMAGE };
                }
            }
            cc_fail(p, node, "c: variable element indexing requires a checked traversal cursor"); return CcPlace { type_id: -1, address: -1 };
        }
        let ref = cc_ref_temp(f); cc_set(f, ref); cc_text(f.out, "g_element_at("); cc_id(f.out, "g_v", base); cc_text(f.out, ",");
        cc_array_args(p, f.out, array); cc_text(f.out, ","); cc_id(f.out, "g_v", index); cc_text(f.out, ",0,"); cc_location(p, f.out, node); cc_text(f.out, ");\n"); return CcPlace { type_id: type_id, address: ref };
    }
    let value = cc_expr(p, f, node); if value < 0 { return CcPlace { type_id: -1, address: -1 }; }
    return CcPlace { type_id: type_id, address: cc_temporary_ref(f, value), form: cc_value_form(p, type_id) };
}
recursive fn cc_convert(p: Program&, f: CcBody&, value: i64, from: i64, to: i64, node: i64, clone: bool = false) -> i64 {
    if value < 0 || to < 0 { return -1; }
    if from == to {
        if clone && cc_needs_clone(p, to, 0) {
            let result = cc_temp(p, f, to); let destination = cc_temporary_ref(f, result); cc_store(p, f, destination, value, to); return result;
        }
        return value;
    }
    let a = cc_kind(p, from); let b = cc_kind(p, to);
    if cc_tuple_channels(p, from) && cc_tuple_channels(p, to) && cc_queue_same(p, from, to) { return value; }
    if a == TY_REF && b == TY_BOOL && (p.types[from].flags & TF_OPTIONAL) != 0 {
        let result = cc_temp(p, f, to); cc_set(f, result); cc_text(f.out, "!!"); cc_id(f.out, "g_v", value); cc_text(f.out, ";\n"); return result;
    }
    if a == TY_REF && b == TY_SLICE && cc_kind(p, p.types[from].element) == TY_ARRAY {
        let result = cc_temp(p, f, to); cc_set(f, result); cc_text(f.out, "g_view("); cc_id(f.out, "g_v", value); cc_text(f.out, ","); cc_array_args(p, f.out, p.types[from].element); cc_text(f.out, ");\n"); return result;
    }
    if a == TY_REF && b != TY_REF {
        let inner = p.types[from].element; let loaded = cc_load(p, f, value, inner); return cc_convert(p, f, loaded, inner, to, node, clone);
    }
    var result = -1;
    if b == TY_TUPLE { result = cc_tuple_result(p, f, node, to); }
    else if cc_image_type(p, to) { result = cc_result_temp(p, f, node, to); }
    else { result = cc_temp(p, f, to); }
    if result < 0 { return -1; }
    if (a == TY_INT || a == TY_FLOAT || a == TY_BOOL) && (b == TY_INT || b == TY_FLOAT || b == TY_BOOL) {
        cc_set(f, result);
        if b == TY_BOOL { cc_text(f.out, "!!"); cc_id(f.out, "g_v", value); }
        else {
            cc_text(f.out, "("); cc_type(f.out, to); cc_text(f.out, ")");
            if a == TY_FLOAT && b == TY_INT { cc_text(f.out, "g_float_wrap("); cc_id(f.out, "g_v", value); cc_text(f.out, ")"); }
            else { cc_id(f.out, "g_v", value); }
        }
        cc_text(f.out, ";\n"); return result;
    }
    if a == TY_REF && b == TY_REF || a == TY_FN && b == TY_FN || a == TY_SLICE && b == TY_SLICE {
        cc_set(f, result); cc_id(f.out, "g_v", value); cc_text(f.out, ";\n"); return result;
    }
    if a == TY_ARRAY && b == TY_SLICE {
        let source = cc_array_value_ref(p, f, value, from); cc_set(f, result); cc_text(f.out, "g_view("); cc_id(f.out, "g_v", source); cc_text(f.out, ","); cc_array_args(p, f.out, from); cc_text(f.out, ");\n"); return result;
    }
    if (a == TY_ARRAY || a == TY_SLICE) && b == TY_ARRAY {
        cc_array_convert(p, f, value, from, to, result, node); return result;
    }
    if a == TY_ENUM && b == TY_ENUM && cc_queue_declaration(p, p.types[from].declaration) == cc_queue_declaration(p, p.types[to].declaration) && cc_image_type(p, from) != cc_image_type(p, to) {
        cc_enum_convert(p, f, value, from, to, result, node); return result;
    }
    if a == TY_STRUCT && b == TY_ENUM && p.types[from].pool >= 0 &&
       p.types[p.types[from].pool].declaration == p.types[to].declaration {
        if cc_image_type(p, to) {
            let raw = f.serial; f.serial++; let width = p.types[to].length_storage;
            cc_id(f.out, "uint8_t *g_enum", raw); cc_text(f.out, "=g_image_space("); cc_id(f.out, "g_v", result); cc_text(f.out, ".region,"); cc_number(f.out, width); cc_text(f.out, ");\n");
            cc_text(f.out, "g_write_length("); cc_id(f.out, "g_enum", raw); cc_text(f.out, ","); cc_number(f.out, width); cc_text(f.out, ","); cc_number(f.out, p.nodes[p.types[from].declaration].integer); cc_text(f.out, ");\n");
            cc_text(f.out, "g_image_advance("); cc_id(f.out, "g_v", result); cc_text(f.out, ".region,"); cc_id(f.out, "g_enum", raw); cc_text(f.out, "+"); cc_number(f.out, width); cc_text(f.out, ");\n");
            let owner = cc_temporary_ref(f, result); cc_image_put_value(p, f, owner, value, from, node);
            cc_text(f.out, "g_image_finish("); cc_id(f.out, "g_v", owner); cc_text(f.out, ","); cc_id(f.out, "g_v", result); cc_text(f.out, ".region->stack.top);\n"); return result;
        }
        cc_text(f.out, "g_write_length(&"); cc_id(f.out, "g_v", result); cc_text(f.out, ",");
        cc_number(f.out, p.types[to].length_storage); cc_text(f.out, ",");
        cc_number(f.out, p.nodes[p.types[from].declaration].integer); cc_text(f.out, ");\n");
        if cc_region_width(p, to) > 0 {
            cc_id(f.out, "g_init_", to); cc_text(f.out, "(g_ref(&"); cc_id(f.out, "g_v", result); cc_text(f.out, "),");
            cc_region_argument(f, f.temp_regions[result]); cc_text(f.out, ");\n");
        }
        cc_id(f.out, "g_store_", from); cc_text(f.out, "(g_offset(g_ref(&"); cc_id(f.out, "g_v", result); cc_text(f.out, "),");
        cc_number(f.out, p.types[to].length_storage); cc_text(f.out, "),"); cc_id(f.out, "g_v", value); cc_text(f.out, ");\n"); return result;
    }
    if a == TY_TUPLE && b == TY_TUPLE {
        let start = f.work.len; var source = p.types[from].first; var index = 0;
        while source >= 0 { f.work.push(cc_tuple_value(p, f, value, from, index)); source = p.nodes[source].next; index++; }
        source = p.types[from].first; var destination = p.types[to].first; index = 0; let target = cc_temporary_ref(f, result);
        while source >= 0 && destination >= 0 {
            let source_type = p.nodes[source].type_id; let destination_type = p.nodes[destination].type_id;
            let adapted = cc_convert(p, f, f.work[start + index], source_type, destination_type, node, clone);
            if adapted >= 0 {
                let part = cc_channel_target(p, f, target, to, index);
                cc_write(p, f, CcPlace { type_id: destination_type, address: part, form: CC_REGISTER }, adapted, node);
            }
            source = p.nodes[source].next; destination = p.nodes[destination].next; index++;
        }
        f.work.resize(start); if source >= 0 || destination >= 0 { cc_fail(p, node, "c: tuple conversion arity mismatch"); } return result;
    }
    if cc_aggregate(p, from) && cc_aggregate(p, to) && cc_frame_size(p, from) == cc_frame_size(p, to) {
        if cc_image_type(p, from) && cc_image_type(p, to) {
            cc_id(f.out, "g_store_", to); cc_text(f.out, "(g_ref(&"); cc_id(f.out, "g_v", result); cc_text(f.out, "),"); cc_id(f.out, "g_v", value); cc_text(f.out, ");\n"); return result;
        }
        cc_text(f.out, "memcpy(&"); cc_id(f.out, "g_v", result); cc_text(f.out, ",&"); cc_id(f.out, "g_v", value); cc_text(f.out, ",sizeof("); cc_type(f.out, to); cc_text(f.out, "));\n");
        if clone && cc_needs_clone(p, to, 0) {
            cc_set(f, result); cc_id(f.out, "g_clone_", to); cc_text(f.out, "("); cc_id(f.out, "g_v", result); if cc_region_width(p, to) > 0 { cc_text(f.out, ","); cc_region_argument(f, f.temp_regions[result]); } cc_text(f.out, ");\n");
        }
        return result;
    }
    cc_conversion_fail(p, node, from, to); return -1;
}
recursive fn cc_enum_convert(p: Program&, f: CcBody&, value: i64, from: i64, to: i64, result: i64, node: i64) {
    let source = cc_array_value_ref(p, f, value, from); let target = cc_temporary_ref(f, result); let width = p.types[to].length_storage;
    let tag = cc_temp(p, f, TYPE_I64); cc_set(f, tag); cc_text(f.out, "g_read_length(g_address("); cc_id(f.out, "g_v", source); cc_text(f.out, "),"); cc_number(f.out, p.types[from].length_storage); cc_text(f.out, ");\n");
    if cc_image_type(p, to) {
        let raw = f.serial; f.serial++;
        cc_id(f.out, "GImage *g_enum", raw); cc_text(f.out, "=(GImage*)g_address("); cc_id(f.out, "g_v", target); cc_text(f.out, ");"); cc_id(f.out, "g_enum", raw); cc_text(f.out, "->region->stack.top="); cc_id(f.out, "g_enum", raw); cc_text(f.out, "->base;\n");
        cc_text(f.out, "g_write_length(g_image_space("); cc_id(f.out, "g_enum", raw); cc_text(f.out, "->region,"); cc_number(f.out, width); cc_text(f.out, "),"); cc_number(f.out, width); cc_text(f.out, ","); cc_id(f.out, "g_v", tag); cc_text(f.out, ");g_image_advance("); cc_id(f.out, "g_enum", raw); cc_text(f.out, "->region,"); cc_id(f.out, "g_enum", raw); cc_text(f.out, "->base+"); cc_number(f.out, width); cc_text(f.out, ");\n");
    } else {
        cc_text(f.out, "g_write_length(g_address("); cc_id(f.out, "g_v", target); cc_text(f.out, "),"); cc_number(f.out, width); cc_text(f.out, ","); cc_id(f.out, "g_v", tag); cc_text(f.out, ");\n");
        if cc_region_width(p, to) > 0 { cc_id(f.out, "g_init_", to); cc_text(f.out, "("); cc_id(f.out, "g_v", target); cc_text(f.out, ","); cc_region_argument(f, f.temp_regions[result]); cc_text(f.out, ");\n"); }
    }
    cc_text(f.out, "switch("); cc_id(f.out, "g_v", tag); cc_text(f.out, "){\n");
    var variant = p.nodes[p.types[from].declaration].first;
    while variant >= 0 {
        let source_payload = p.nodes[variant].type_id; var target_variant = p.nodes[p.types[to].declaration].first;
        while target_variant >= 0 && p.nodes[target_variant].integer != p.nodes[variant].integer { target_variant = p.nodes[target_variant].next; }
        if target_variant < 0 { cc_fail(p, node, "c: enum adaptation has no matching natural variant"); return; }
        let target_payload = p.nodes[target_variant].type_id;
        cc_text(f.out, "case "); cc_number(f.out, p.nodes[variant].integer); cc_text(f.out, ":{\n");
        let input = cc_ref_temp(f); cc_set(f, input); cc_text(f.out, "g_offset("); cc_id(f.out, "g_v", source); cc_text(f.out, ","); cc_number(f.out, p.types[from].length_storage); cc_text(f.out, ");\n");
        var form = CC_NATIVE; if cc_image_type(p, from) { form = CC_IMAGE; }
        let loaded = cc_read(p, f, CcPlace { type_id: source_payload, address: input, form: form }, source_payload, node);
        let adapted = cc_convert(p, f, loaded, source_payload, target_payload, node);
        if cc_image_type(p, to) { cc_image_put_value(p, f, target, adapted, target_payload, node); }
        else {
            let output = cc_ref_temp(f); cc_set(f, output); cc_text(f.out, "g_offset("); cc_id(f.out, "g_v", target); cc_text(f.out, ","); cc_number(f.out, width); cc_text(f.out, ");\n"); cc_store(p, f, output, adapted, target_payload, node);
        }
        cc_text(f.out, "break;}\n"); variant = p.nodes[variant].next;
    }
    cc_text(f.out, "default:g_panic("); cc_bytes(f.out, "corrupt ADT tag"); cc_text(f.out, ");}\n");
    if cc_image_type(p, to) { cc_text(f.out, "g_image_finish("); cc_id(f.out, "g_v", target); cc_text(f.out, ",((GImage*)g_address("); cc_id(f.out, "g_v", target); cc_text(f.out, "))->region->stack.top);\n"); }
}
fn cc_array_value_ref(p: Program&, f: CcBody&, value: i64, type_id: i64) -> i64 {
    if cc_image_type(p, type_id) {
        let address = cc_ref_temp(f); cc_set(f, address); cc_text(f.out, "g_ref("); cc_id(f.out, "g_v", value); cc_text(f.out, ".base);\n"); return address;
    }
    return cc_temporary_ref(f, value);
}
struct CcImageRun { start: i64, end: i64, count: i64 }
fn cc_array_span(p: Program&, f: CcBody&, source: i64, type_id: i64, known_count: i64 = -1) -> CcImageRun {
    var count = known_count;
    if count < 0 { count = cc_temp(p, f, TYPE_I64); cc_set(f, count); cc_text(f.out, "g_len("); cc_id(f.out, "g_v", source); cc_text(f.out, ","); cc_array_args(p, f.out, type_id, false); cc_text(f.out, ");\n"); }
    let start = cc_ref_temp(f); cc_set(f, start); cc_text(f.out, "g_element("); cc_id(f.out, "g_v", source); cc_text(f.out, ","); cc_array_args(p, f.out, type_id); cc_text(f.out, ",0,1);\n");
    let end = cc_ref_temp(f); cc_set(f, end); cc_id(f.out, "g_v", start); cc_text(f.out, ";\n");
    let element = p.types[type_id].element;
    if cc_size_class(p, element) == 1 {
        let raw = f.serial; f.serial++;
        cc_id(f.out, "for(int64_t g_i", raw); cc_text(f.out, "=0;"); cc_id(f.out, "g_i", raw); cc_text(f.out, "<"); cc_id(f.out, "g_v", count); cc_text(f.out, ";"); cc_id(f.out, "g_i", raw); cc_text(f.out, "++)"); cc_id(f.out, "g_v", end); cc_text(f.out, "=g_ref(g_physical_skip_"); cc_number(f.out, element); cc_text(f.out, "(g_address("); cc_id(f.out, "g_v", end); cc_text(f.out, ")));\n");
    } else { cc_set(f, end); cc_text(f.out, "g_offset("); cc_id(f.out, "g_v", start); cc_text(f.out, ",g_image_product("); cc_id(f.out, "g_v", count); cc_text(f.out, ","); cc_number(f.out, p.types[element].size); cc_text(f.out, "));\n"); }
    return CcImageRun { start: start, end: end, count: count };
}
recursive fn cc_array_convert(p: Program&, f: CcBody&, value: i64, from: i64, to: i64, result: i64, node: i64) {
    let source = cc_array_value_ref(p, f, value, from); let destination = cc_temporary_ref(f, result);
    let count = cc_temp(p, f, TYPE_I64); cc_set(f, count);
    cc_text(f.out, "g_len("); cc_id(f.out, "g_v", source); cc_text(f.out, ","); cc_array_args(p, f.out, from, false); cc_text(f.out, ");\n");
    if cc_image_type(p, to) || cc_size_class(p, p.types[to].element) == 1 {
        let source_element = p.types[from].element; let element = p.types[to].element;
        let run = cc_array_span(p, f, source, from, count); let raw = f.serial; f.serial++; var writer = destination;
        if cc_image_type(p, to) {
            cc_text(f.out, "g_image_array_begin("); cc_id(f.out, "g_v", destination); cc_text(f.out, ","); cc_number(f.out, cc_array_kind(p, to)); cc_text(f.out, ","); cc_number(f.out, cc_prefix(p, to)); cc_text(f.out, ","); cc_id(f.out, "g_v", count); cc_text(f.out, ","); cc_id(f.out, "g_v", count); cc_text(f.out, ","); cc_number(f.out, p.types[element].size); cc_text(f.out, ");\n");
        } else {
            cc_text(f.out, "g_begin_builder("); cc_id(f.out, "g_v", destination); cc_text(f.out, ");\n"); writer = cc_run_writer(f, destination);
        }
        if cc_queue_same(p, source_element, element) {
            cc_id(f.out, "int64_t g_copy_bytes", raw); cc_text(f.out, "="); cc_id(f.out, "g_v", run.end); cc_text(f.out, "-"); cc_id(f.out, "g_v", run.start); cc_text(f.out, ";\n");
            cc_id(f.out, "uint8_t *g_write", raw); cc_text(f.out, "=g_image_space(((GImage*)g_address("); cc_id(f.out, "g_v", writer); cc_text(f.out, "))->region,"); cc_id(f.out, "g_copy_bytes", raw); cc_text(f.out, ");memmove("); cc_id(f.out, "g_write", raw); cc_text(f.out, ",g_address("); cc_id(f.out, "g_v", run.start); cc_text(f.out, "),(size_t)"); cc_id(f.out, "g_copy_bytes", raw); cc_text(f.out, ");g_image_advance(((GImage*)g_address("); cc_id(f.out, "g_v", writer); cc_text(f.out, "))->region,"); cc_id(f.out, "g_write", raw); cc_text(f.out, "+"); cc_id(f.out, "g_copy_bytes", raw); cc_text(f.out, ");\n");
        } else {
            cc_id(f.out, "for(int64_t g_i", raw); cc_text(f.out, "=0;"); cc_id(f.out, "g_i", raw); cc_text(f.out, "<"); cc_id(f.out, "g_v", count); cc_text(f.out, ";"); cc_id(f.out, "g_i", raw); cc_text(f.out, "++){\n");
            let mark = f.region_live; let loaded = cc_load(p, f, run.start, source_element); let adapted = cc_convert(p, f, loaded, source_element, element, node);
            cc_image_put_value(p, f, writer, adapted, element, node); cc_restore(f, mark); f.region_live = mark;
            cc_set(f, run.start); cc_text(f.out, "g_ref(g_physical_skip_"); cc_number(f.out, source_element); cc_text(f.out, "(g_address("); cc_id(f.out, "g_v", run.start); cc_text(f.out, ")));\n}\n");
        }
        if cc_image_type(p, to) {
            cc_text(f.out, "g_image_array_finish("); cc_id(f.out, "g_v", destination); cc_text(f.out, ","); cc_number(f.out, cc_array_kind(p, to)); cc_text(f.out, ","); cc_id(f.out, "g_v", count); cc_text(f.out, ","); cc_number(f.out, p.types[element].size); cc_text(f.out, ");\n");
        } else {
            cc_text(f.out, "g_image_commit("); cc_id(f.out, "g_v", destination); cc_text(f.out, ",((GImage*)g_address("); cc_id(f.out, "g_v", writer); cc_text(f.out, "))->region->stack.top,"); cc_id(f.out, "g_v", count); cc_text(f.out, ");\n");
        }
        return;
    }
    if p.types[to].array_kind == A_FIXED {
        cc_text(f.out, "if("); cc_id(f.out, "g_v", count); cc_text(f.out, "!="); cc_number(f.out, p.types[to].count); cc_text(f.out, ")g_panic(\"fixed array length mismatch\");\n");
    } else {
        cc_text(f.out, "g_reserve("); cc_id(f.out, "g_v", destination); cc_text(f.out, ","); cc_array_args(p, f.out, to);
        cc_text(f.out, ","); cc_id(f.out, "g_v", count); cc_text(f.out, ");g_set_len("); cc_id(f.out, "g_v", destination);
        cc_text(f.out, ","); cc_array_args(p, f.out, to, false); cc_text(f.out, ","); cc_id(f.out, "g_v", count); cc_text(f.out, ");\n");
    }
    let source_element = p.types[from].element; let destination_element = p.types[to].element;
    if source_element == destination_element && !cc_needs_clone(p, destination_element, 0) {
        cc_text(f.out, "if("); cc_id(f.out, "g_v", count); cc_text(f.out, ")memcpy(g_address(g_element("); cc_id(f.out, "g_v", destination);
        cc_text(f.out, ","); cc_array_args(p, f.out, to); cc_text(f.out, ",0,1)),g_address(g_element("); cc_id(f.out, "g_v", source);
        cc_text(f.out, ","); cc_array_args(p, f.out, from); cc_text(f.out, ",0,1)),(size_t)"); cc_id(f.out, "g_v", count);
        cc_text(f.out, "*"); cc_number(f.out, cc_frame_size(p, destination_element)); cc_text(f.out, ");\n"); return;
    }
    let counter = f.serial; f.serial++;
    cc_id(f.out, "for(int64_t g_i", counter); cc_text(f.out, "=0;"); cc_id(f.out, "g_i", counter); cc_text(f.out, "<"); cc_id(f.out, "g_v", count);
    cc_text(f.out, ";"); cc_id(f.out, "g_i", counter); cc_text(f.out, "++){\n");
    let loaded = cc_temp(p, f, source_element); cc_set(f, loaded); cc_id(f.out, "g_load_", source_element); cc_text(f.out, "(g_element(");
    cc_id(f.out, "g_v", source); cc_text(f.out, ","); cc_array_args(p, f.out, from); cc_text(f.out, ","); cc_id(f.out, "g_i", counter); cc_text(f.out, ",0));\n");
    let copied = cc_convert(p, f, loaded, source_element, destination_element, node, true);
    cc_id(f.out, "g_store_", destination_element); cc_text(f.out, "(g_element("); cc_id(f.out, "g_v", destination); cc_text(f.out, ","); cc_array_args(p, f.out, to);
    cc_text(f.out, ","); cc_id(f.out, "g_i", counter); cc_text(f.out, ",0),"); cc_id(f.out, "g_v", copied); cc_text(f.out, ");}\n");
}
recursive fn cc_to(p: Program&, f: CcBody&, node: i64, to: i64, clone: bool = false) -> i64 {
    if node < 0 { cc_fail(p, node, "c: missing value"); return -1; }
    var frozen = f.fills.len;
    while frozen > 0 {
        frozen--; let entry = f.fills[frozen];
        if entry.node == node { return cc_convert(p, f, entry.value, entry.type_id, to, node, clone); }
    }
    let from = p.nodes[node].type_id;
    if cc_kind(p, to) == TY_REF && cc_kind(p, p.types[to].element) == TY_INT && p.types[p.types[to].element].storage == 0 {
        var stored = cc_place_type(p, node);
        if cc_kind(p, from) == TY_REF { stored = p.types[from].element; }
        if cc_kind(p, stored) == TY_INT && p.types[stored].storage != 0 {
            let value = cc_expr(p, f, node); let decoded = cc_convert(p, f, value, from, p.types[to].element, node); return cc_temporary_ref(f, decoded);
        }
    }
    if cc_kind(p, to) == TY_REF && cc_owner(p, p.types[to].element) {
        var location: i64 = -1;
        if cc_kind(p, from) == TY_REF { location = cc_expr(p, f, node); }
        else { location = cc_reference_place(p, f, node); }
        let owner = cc_ref_temp(f); cc_set(f, owner); cc_text(f.out, "g_owner("); cc_id(f.out, "g_v", location); cc_text(f.out, ");\n"); return owner;
    }
    if cc_kind(p, to) == TY_REF && cc_kind(p, from) != TY_REF { return cc_reference_place(p, f, node); }
    var source_array = from;
    while cc_kind(p, source_array) == TY_REF { source_array = p.types[source_array].element; }
    if cc_kind(p, source_array) == TY_ARRAY && cc_kind(p, to) == TY_SLICE {
        var base = cc_base(p, f, node); var current = from;
        while cc_kind(p, current) == TY_REF && cc_kind(p, p.types[current].element) == TY_REF {
            current = p.types[current].element; base = cc_load(p, f, base, current);
        }
        let result = cc_temp(p, f, to); cc_set(f, result); cc_text(f.out, "g_view("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, source_array); cc_text(f.out, ");\n"); return result;
    }
    let value = cc_expr(p, f, node); return cc_convert(p, f, value, from, to, node, clone);
}
fn cc_bytes(out: u8[>..]&, text: const u8[:]) {
    cc_text(out, "\"");
    for c in text {
        // Fixed-width octal escapes cannot consume a following hex digit.
        cc_text(out, "\\"); out.push((48 + ((c as i64 >> 6) & 7)) as u8);
        out.push((48 + ((c as i64 >> 3) & 7)) as u8); out.push((48 + ((c as i64) & 7)) as u8);
    }
    cc_text(out, "\"");
}
fn cc_function_result(p: Program&, function: i64) -> i64 {
    let type_id = p.nodes[function].type_id;
    if cc_kind(p, type_id) != TY_FN { return TYPE_VOID; } return p.types[type_id].element;
}
fn cc_function_type(p: Program&, out: u8[>..]&, type_id: i64) {
    let result = p.types[type_id].element;
    if cc_result_indirect(p, result) { cc_text(out, "void"); } else { cc_type(out, result); } cc_text(out, " (*)(GClosure*,int64_t");
    if cc_receives(p, result) { cc_text(out, ","); if cc_tuple_channels(p, result) { cc_text(out, "GRef*"); } else { cc_type(out, result); cc_text(out, "*"); } }
    var param = p.types[type_id].first;
    while param >= 0 {
        cc_text(out, ","); cc_type(out, p.nodes[param].type_id); if cc_indirect(p, p.nodes[param].type_id) { cc_text(out, "*"); }
        if cc_flat_image_reference(p, p.nodes[param].type_id) { cc_text(out, ",GRef"); }
        param = p.nodes[param].next;
    }
    cc_text(out, ")");
}
recursive fn cc_closure(p: Program&, f: CcBody&, function: i64, type_id: i64) -> i64 {
    let result = cc_temp(p, f, type_id); var count = 0; var capture = p.nodes[function].captures;
    while capture >= 0 { count++; capture = p.nodes[capture].next; }
    cc_set(f, result); cc_text(f.out, "g_closure((void*)"); cc_id(f.out, "g_fn", function); cc_text(f.out, ","); cc_number(f.out, count); cc_text(f.out, ");\n");
    capture = p.nodes[function].captures; var index = 0;
    while capture >= 0 {
        let ref = cc_symbol_ref(p, f, p.nodes[capture].symbol, function);
        cc_id(f.out, "g_v", result); cc_text(f.out, "->captures["); cc_number(f.out, index); cc_text(f.out, "]="); cc_id(f.out, "g_v", ref); cc_text(f.out, ";\n");
        index++; capture = p.nodes[capture].next;
    }
    return result;
}

fn cc_use_type(p: Program&, used: bool[:], work: i64[>..]&, type_id: i64) {
    if type_id < 0 || type_id >= used.len || used[type_id] { return; }
    used[type_id] = true; work.push(type_id);
}
fn cc_used_types(p: Program&, used: bool[:], work: i64[>..]&) {
    // Lowering introduces scalar counters, predicates, and conversion temps.
    for type_id in 0..TYPE_STRING + 1 { cc_use_type(p, used, work, type_id); }
    for n in p.nodes {
        if (n.flags & F_CHECKED) == 0 { continue; }
        if n.kind >= N_INTEGER && n.kind <= N_EXPR_STMT || n.kind == N_BLOCK || n.kind == N_FUNCTION_VALUE || n.kind == N_VARIABLE || n.kind == N_TUPLE || n.kind == N_CAST || n.kind == N_CONST_FOR || n.kind == N_RESULT {
            cc_use_type(p, used, work, n.type_id);
        }
        if n.kind == N_BINARY && n.aux >= 0 { cc_use_type(p, used, work, n.aux); }
    }
    for symbol in p.symbols {
        if (symbol.flags & (S_FUNCTION | S_TYPE | S_BUILTIN)) == 0 &&
           (symbol.owner < 0 || cc_emittable(p, symbol.owner)) {
            cc_use_type(p, used, work, symbol.type_id);
        }
    }
    for n, id in p.nodes { if cc_emittable(p, id) { cc_use_type(p, used, work, n.type_id); } }
    var at = 0;
    while at < work.len {
        let t = p.types[work[at]]; at++;
        if t.kind == TY_REF || t.kind == TY_ARRAY || t.kind == TY_SLICE || t.kind == TY_FN { cc_use_type(p, used, work, t.element); }
        var field = -1;
        if t.kind == TY_STRUCT || t.kind == TY_ENUM || t.kind == TY_TUPLE || t.kind == TY_FN { field = t.first; }
        while field >= 0 {
            if (p.nodes[field].flags & F_PAD) == 0 { cc_use_type(p, used, work, p.nodes[field].type_id); }
            field = p.nodes[field].next;
        }
    }
}
fn cc_helper_name(p: Program&, out: u8[>..]&, prefix: const u8[:], id: i64) {
    cc_text(out, prefix); if cc_helper_indirect(p, id) { cc_text(out, "value_"); } cc_number(out, id);
}
fn cc_helper_value(p: Program&, out: u8[>..]&, id: i64, name: const u8[:]) {
    if cc_helper_indirect(p, id) { cc_text(out, "const "); } cc_type(out, id);
    if cc_helper_indirect(p, id) { cc_text(out, " *g_indirect_"); } else { cc_text(out, " "); } cc_text(out, name);
}
fn cc_helper_alias(p: Program&, out: u8[>..]&, id: i64, name: const u8[:], end: bool = false) {
    if !cc_helper_indirect(p, id) { return; }
    if end { cc_text(out, "#undef "); cc_text(out, name); cc_text(out, "\n"); }
    else { cc_text(out, "#define "); cc_text(out, name); cc_text(out, " (*g_indirect_"); cc_text(out, name); cc_text(out, ")\n"); }
}
fn cc_emit_types(p: Program&, out: u8[>..]&, used: const bool[:]) {
    for t, id in p.types {
        if !used[id] || !cc_concrete(p, id) { continue; }
        let trailer = t.kind == TY_ENUM && cc_region_width(p, id) > 0;
        if trailer { cc_text(out, "#pragma pack(push,1)\n"); }
        cc_text(out, "typedef ");
        if cc_image_type(p, id) { cc_text(out, "GImage"); }
        else if t.kind == TY_VOID { cc_text(out, "void"); }
        else if t.kind == TY_BOOL { cc_text(out, "uint8_t"); }
        else if t.kind == TY_INT {
            if (t.flags & TF_UNSIGNED) != 0 { cc_text(out, "uint"); } else { cc_text(out, "int"); }
            cc_number(out, t.count); cc_text(out, "_t");
        } else if t.kind == TY_FLOAT {
            if t.count == 32 { cc_text(out, "float"); } else { cc_text(out, "double"); }
        } else if t.kind == TY_REF { cc_text(out, "GRef"); }
        else if t.kind == TY_FN { cc_text(out, "GClosure*"); }
        else if t.kind == TY_SLICE { cc_text(out, "GSlice"); }
        else if t.kind == TY_TUPLE { cc_id(out, "struct g_tuple", id); }
        else {
            cc_text(out, "struct { unsigned char data["); var bytes = cc_frame_size(p, id); if trailer { bytes -= 8; }
            cc_number(out, bytes); cc_text(out, "]; "); if trailer { cc_text(out, "GRegion *region;"); } cc_text(out, "}");
        }
        cc_text(out, " "); cc_type(out, id); cc_text(out, ";\n"); if trailer { cc_text(out, "#pragma pack(pop)\n"); }
    }
    for t, id in p.types {
        if !used[id] || t.kind != TY_TUPLE { continue; }
        cc_text(out, "#pragma pack(push,1)\n"); cc_id(out, "struct g_tuple", id); cc_text(out, " {"); var field = t.first; var index = 0;
        while field >= 0 {
            cc_type(out, p.nodes[field].type_id); cc_text(out, " "); cc_id(out, "f", index); cc_text(out, ";");
            index++; field = p.nodes[field].next;
        }
        cc_text(out, "};\n#pragma pack(pop)\n");
    }
    for t, id in p.types {
        if !used[id] || !cc_concrete(p, id) || t.kind == TY_VOID { continue; }
        cc_id(out, "static const uint8_t *g_image_skip_", id); cc_text(out, "(const uint8_t*);\n");
        if cc_size_class(p, id) == 0 { out.format("#define g_physical_skip_", id, "(image) ((image)+", t.size, ")\n"); }
        else { out.format("#define g_physical_skip_", id, " g_image_skip_", id, "\n"); }
        let regions = cc_region_width(p, id);
        if regions > 0 {
            cc_id(out, "static void g_init_", id); cc_text(out, "(GRef p,int64_t slot);\n");
            cc_id(out, "static void g_map_", id); cc_text(out, "(GRef source,GRef target,GPublication *links);\n");
        }
        if cc_helper_indirect(p, id) {
            cc_text(out, "#define "); cc_id(out, "g_load_", id); cc_text(out, "(p) (*(const "); cc_type(out, id); cc_text(out, "*)g_address(p))\n");
            cc_text(out, "#define "); cc_id(out, "g_store_", id); cc_text(out, "(p,v) "); cc_id(out, "g_store_value_", id); cc_text(out, "((p),&(v))\n");
            cc_text(out, "#define "); cc_id(out, "g_equal_", id); cc_text(out, "(a,b) "); cc_id(out, "g_equal_value_", id); cc_text(out, "(&(a),&(b))\n");
            cc_text(out, "#define "); cc_id(out, "g_print_", id); cc_text(out, "(out,v) "); cc_id(out, "g_print_value_", id); cc_text(out, "((out),&(v))\n");
            cc_text(out, "#define "); cc_id(out, "g_nested_", id); cc_text(out, "(out,v) "); cc_id(out, "g_nested_value_", id); cc_text(out, "((out),&(v))\n");
            cc_text(out, "#define "); cc_id(out, "g_clone_", id); cc_text(out, "(v"); if regions > 0 { cc_text(out, ",slot"); }
            cc_text(out, ") (*"); cc_id(out, "g_clone_value_", id); cc_text(out, "(&(v)"); if regions > 0 { cc_text(out, ",(slot)"); } cc_text(out, "))\n");
        }
        cc_text(out, "static "); if cc_helper_indirect(p, id) { cc_text(out, "const "); } cc_type(out, id);
        if cc_helper_indirect(p, id) { cc_text(out, " *"); } else { cc_text(out, " "); } cc_helper_name(p, out, "g_clone_", id); cc_text(out, "("); cc_helper_value(p, out, id, "v");
        if regions > 0 { cc_text(out, ",int64_t slot"); } cc_text(out, ");\n");
        cc_text(out, "static int "); cc_helper_name(p, out, "g_equal_", id); cc_text(out, "("); cc_helper_value(p, out, id, "a"); cc_text(out, ","); cc_helper_value(p, out, id, "b"); cc_text(out, ");\n");
        for prefix in ["g_print_", "g_nested_"] {
            cc_text(out, "static void "); cc_helper_name(p, out, prefix, id); cc_text(out, "(GArray *out,"); cc_helper_value(p, out, id, "v"); cc_text(out, ");\n");
        }
        if cc_image_type(p, id) { out.format("static g_t", id, " g_native_load_", id, "(GRef p){g_t", id, " value;memcpy(&value,g_address(p),sizeof value);return value;}\n"); }
        else { out.format("#define g_native_load_", id, " g_load_", id, "\n"); }
        if !cc_helper_indirect(p, id) {
            cc_text(out, "static "); cc_type(out, id); cc_id(out, " g_load_", id); cc_text(out, "(GRef p) {");
            if cc_image_type(p, id) {
                cc_text(out, "const uint8_t *start=g_address(p);return (GImage){(uint8_t*)start,(uint8_t*)"); cc_id(out, "g_image_skip_", id); cc_text(out, "(start),NULL};}\n");
            } else if t.kind == TY_INT && t.storage != 0 { cc_text(out, "return gs_zig_read(g_address(p));}\n"); }
            else if cc_relative_cell(p, id) {
                cc_text(out, "return g_relative_load(p,"); cc_number(out, t.length_storage); cc_text(out, ",");
                if (t.flags & TF_OPTIONAL) != 0 { cc_text(out, "1"); } else { cc_text(out, "0"); }
                cc_text(out, ","); cc_relative_origin(p, out, id); cc_text(out, ");}\n");
            } else { cc_type(out, id); cc_text(out, " v; memcpy(&v,g_address(p),sizeof v); return v;}\n"); }
        }
        cc_text(out, "static void "); cc_helper_name(p, out, "g_store_", id); cc_text(out, "(GRef p,"); cc_helper_value(p, out, id, "v"); cc_text(out, ");\n");
        cc_id(out, "static void g_publish_", id); cc_text(out, "(void *p,const void *source){");
        if cc_image_type(p, id) { cc_text(out, "GImage value;memcpy(&value,source,sizeof value);g_image_copy_into(g_ref(p),value); }\n"); }
        else if cc_relative_cell(p, id) || t.kind == TY_INT && t.storage != 0 { cc_text(out, "memmove(p,source,sizeof(g_t"); cc_number(out, id); cc_text(out, "));}\n"); }
        else { cc_id(out, "g_store_", id); cc_text(out, "(g_ref(p),"); cc_id(out, "g_load_", id); cc_text(out, "(g_ref(source)));}\n"); }
    }
    var physical: bool[>..] = []; physical.resize(p.types.len, false);
    for t, id in p.types {
        if !used[id] || !cc_flat_relative_image(p, id) { continue; }
        var field = p.nodes[t.declaration].first;
        while field >= 0 { let n = p.nodes[field]; if (n.flags & F_PAD) == 0 { physical[n.type_id] = true; } field = n.next; }
    }
    for t, id in p.types {
        if !physical[id] { continue; }
        out.format("static g_t", id, " g_physical_load_", id, "(const uint8_t *cell,const uint8_t *end){(void)g_relative_cell_skip(cell,end,", cc_physical_cell_width(p, id), ");\n");
        if cc_relative_cell(p, id) {
            if t.length_storage == 0 { out.append("return g_relative_var_load(g_ref(cell),end,"); }
            else { out.format("return g_relative_load(g_ref(cell),", t.length_storage, ","); }
            if (t.flags & TF_OPTIONAL) != 0 { out.append("1,"); } else { out.append("0,"); }
            cc_relative_origin(p, out, id);
            if t.length_storage == 0 { out.append(",NULL);}"); } else { out.append(");}"); }
        } else { out.format("return g_load_", id, "(g_ref(cell));}"); }
        out.push(10);
    }
}
fn cc_emit_init(p: Program&, out: u8[>..]&, id: i64) {
    let width = cc_region_width(p, id); if width == 0 { return; }
    let t = p.types[id];
    cc_id(out, "static void g_init_", id); cc_text(out, "(GRef p,int64_t slot){\n");
    if cc_image_type(p, id) { cc_text(out, "GImage value=g_image(slot);memcpy(g_address(p),&value,sizeof value);\n"); }
    else if cc_owner(p, id) {
        cc_text(out, "GArray value=g_array(slot);memcpy(g_address(p),&value,sizeof value);\n");
    } else if t.kind == TY_STRUCT && t.declaration >= 0 {
        var field = p.nodes[t.declaration].first; var offset = 0;
        while field >= 0 {
            let n = p.nodes[field]; let count = cc_region_width(p, n.type_id);
            if (n.flags & F_PAD) == 0 && count > 0 {
                cc_id(out, "g_init_", n.type_id); cc_text(out, "(g_offset(p,"); cc_number(out, cc_field_offset(p, id, field));
                cc_text(out, "),slot+"); cc_number(out, offset); cc_text(out, ");\n"); offset += count;
            }
            field = n.next;
        }
    } else if t.kind == TY_TUPLE {
        var part = t.first; var index = 0; var offset = 0;
        while part >= 0 {
            let type_id = p.nodes[part].type_id; let count = cc_region_width(p, type_id);
            if count > 0 {
                cc_id(out, "g_init_", type_id); cc_text(out, "(g_offset(p,offsetof("); cc_type(out, id);
                cc_text(out, ","); cc_id(out, "f", index); cc_text(out, ")),slot+"); cc_number(out, offset); cc_text(out, ");\n"); offset += count;
            }
            index++; part = p.nodes[part].next;
        }
    } else if t.kind == TY_ENUM && t.declaration >= 0 {
        cc_type(out, id); cc_text(out, " *value=("); cc_type(out, id); cc_text(out, "*)g_address(p);value->region=g_region(slot);value->region->entry=value->region->stack.top;\n");
        cc_text(out, "switch(g_read_length(value,"); cc_number(out, t.length_storage); cc_text(out, ")){\n");
        var variant = p.nodes[t.declaration].first;
        while variant >= 0 {
            let payload = p.nodes[variant].type_id;
            if cc_region_width(p, payload) > 0 {
                cc_text(out, "case "); cc_number(out, p.nodes[variant].integer); cc_text(out, ":"); cc_id(out, "g_init_", payload);
                cc_text(out, "(g_offset(p,"); cc_number(out, t.length_storage); cc_text(out, "),slot);break;\n");
            }
            variant = p.nodes[variant].next;
        }
        cc_text(out, "default:break;}\n");
    }
    cc_text(out, "}\n");
}
fn cc_emit_store(p: Program&, out: u8[>..]&, id: i64) {
    let t = p.types[id]; let width = cc_region_width(p, id);
    cc_text(out, "static void "); cc_helper_name(p, out, "g_store_", id); cc_text(out, "(GRef p,"); cc_helper_value(p, out, id, "v"); cc_text(out, "){\n"); cc_helper_alias(p, out, id, "v");
    if cc_image_type(p, id) { cc_text(out, "g_image_copy_into(p,v);}\n"); return; }
    if t.kind == TY_INT && t.storage != 0 { cc_text(out, "gs_zig_write(g_address(p),v);}\n"); return; }
    if t.kind == TY_ARRAY && cc_owner(p, id) && cc_size_class(p, t.element) == 1 {
        cc_text(out, "GArray source,target;memcpy(&source,&v,sizeof source);memcpy(&target,g_address(p),sizeof target);const uint8_t *end=source.data;\n");
        cc_text(out, "if(source.region==target.region && source.data==target.data){memcpy(g_address(p),&source,sizeof source);g_header_changed(p);return;}\n");
        out.format("for(int64_t i=0;i<source.len;i++)end=g_physical_skip_", t.element, "(end);int64_t bytes=end-source.data;g_begin_builder(p);\n",
            "uint8_t *data=g_image_space(target.region,bytes);if(bytes)memmove(data,source.data,(size_t)bytes);g_image_commit(p,data+bytes,source.len);}\n"); return;
    }
    if cc_relative_cell(p, id) {
        cc_text(out, "g_relative_store(p,v,"); cc_number(out, t.length_storage); cc_text(out, ",");
        if (t.flags & TF_OPTIONAL) != 0 { cc_text(out, "1"); } else { cc_text(out, "0"); }
        cc_text(out, ","); cc_relative_origin(p, out, id); cc_text(out, ",\"<native>\",0);}\n"); return;
    }
    if !cc_needs_clone(p, id, 0) { cc_text(out, "memmove(g_address(p),&v,sizeof v);}\n"); cc_helper_alias(p, out, id, "v", true); return; }
    if cc_owner(p, id) {
        cc_text(out, "GArray source,target;memcpy(&source,&v,sizeof source);memcpy(&target,g_address(p),sizeof target);\n");
        cc_text(out, "if(source.region==target.region && source.data==target.data){memcpy(g_address(p),&source,sizeof source);g_header_changed(p);return;}\n");
        cc_text(out, "g_reserve(p,"); cc_array_args(p, out, id); cc_text(out, ",source.len);\n");
        if cc_needs_clone(p, t.element, 0) {
            cc_text(out, "for(int64_t i=0;i<source.len;i++){"); cc_id(out, "g_store_", t.element); cc_text(out, "(g_ref(target.data+i*");
            cc_number(out, cc_frame_size(p, t.element)); cc_text(out, "),"); cc_id(out, "g_native_load_", t.element);
            cc_text(out, "(g_ref(source.data+i*"); cc_number(out, cc_frame_size(p, t.element)); cc_text(out, ")));}\n");
        } else {
            cc_text(out, "if(source.len)memmove(target.data,source.data,(size_t)source.len*"); cc_number(out, cc_frame_size(p, t.element)); cc_text(out, ");\n");
        }
        cc_text(out, "g_set_len(p,"); cc_array_args(p, out, id, false); cc_text(out, ",source.len);\n");
    } else if t.kind == TY_STRUCT && t.declaration >= 0 {
        var field = p.nodes[t.declaration].first;
        while field >= 0 {
            let n = p.nodes[field];
            if (n.flags & F_PAD) != 0 {
                cc_text(out, "memcpy(g_address(g_offset(p,"); cc_number(out, cc_field_offset(p, id, field)); cc_text(out, ")),g_address(g_offset(g_ref(&v),");
                cc_number(out, cc_field_offset(p, id, field)); cc_text(out, ")),"); cc_number(out, n.aux); cc_text(out, ");\n");
            } else {
                cc_id(out, "g_store_", n.type_id); cc_text(out, "(g_offset(p,"); cc_number(out, cc_field_offset(p, id, field)); cc_text(out, "),");
                cc_id(out, "g_native_load_", n.type_id); cc_text(out, "(g_offset(g_ref(&v),"); cc_number(out, cc_field_offset(p, id, field)); cc_text(out, ")));\n");
            }
            field = n.next;
        }
    } else if t.kind == TY_ENUM && t.declaration >= 0 {
        if width > 0 {
            cc_type(out, id); cc_text(out, " *target=("); cc_type(out, id); cc_text(out, "*)g_address(p);GRegion *region=target->region;\n");
            cc_text(out, "if(!region)g_panic(\"enum has no receiving region\");if(v.region==region){memcpy(target,&v,sizeof v);return;}\n");
            cc_text(out, "memcpy(target,&v,sizeof v);target->region=region;region->stack.top=region->entry;\n");
        } else { cc_text(out, "memcpy(g_address(p),&v,sizeof v);\n"); }
        cc_text(out, "switch(g_read_length(&v,"); cc_number(out, t.length_storage); cc_text(out, ")){\n");
        var variant = p.nodes[t.declaration].first;
        while variant >= 0 {
            let payload = p.nodes[variant].type_id;
            if cc_needs_clone(p, payload, 0) {
                cc_text(out, "case "); cc_number(out, p.nodes[variant].integer); cc_text(out, ":{\n");
                if cc_region_width(p, payload) > 0 {
                    cc_id(out, "g_init_", payload); cc_text(out, "(g_offset(p,"); cc_number(out, t.length_storage); cc_text(out, "),region-g_regions);\n");
                }
                cc_id(out, "g_store_", payload); cc_text(out, "(g_offset(p,"); cc_number(out, t.length_storage);
                cc_text(out, "),"); cc_id(out, "g_native_load_", payload); cc_text(out, "(g_offset(g_ref(&v),"); cc_number(out, t.length_storage); cc_text(out, ")));break;}\n");
            }
            variant = p.nodes[variant].next;
        }
        cc_text(out, "default:break;}\n");
    } else if t.kind == TY_TUPLE {
        var part = t.first; var index = 0;
        while part >= 0 {
            if cc_relative_cell(p, p.nodes[part].type_id) {
                cc_text(out, "memmove(g_address(g_offset(p,offsetof("); cc_type(out, id); cc_text(out, ","); cc_id(out, "f", index); cc_text(out, "))),&v."); cc_id(out, "f", index); cc_text(out, ",sizeof(GRef));\n");
            } else {
                cc_id(out, "g_store_", p.nodes[part].type_id); cc_text(out, "(g_offset(p,offsetof("); cc_type(out, id);
                cc_text(out, ","); cc_id(out, "f", index); cc_text(out, ")),v."); cc_id(out, "f", index); cc_text(out, ");\n");
            }
            index++; part = p.nodes[part].next;
        }
    }
    cc_text(out, "}\n"); cc_helper_alias(p, out, id, "v", true);
}
fn cc_emit_clone(p: Program&, out: u8[>..]&, id: i64) {
    let t = p.types[id]; if !cc_concrete(p, id) || t.kind == TY_VOID { return; }
    let width = cc_region_width(p, id);
    if cc_helper_indirect(p, id) {
        cc_text(out, "static const "); cc_type(out, id); cc_id(out, " *g_clone_value_", id); cc_text(out, "(const "); cc_type(out, id); cc_text(out, " *v");
        if width > 0 { cc_text(out, ",int64_t slot"); } cc_text(out, "){\n");
        if !cc_needs_clone(p, id, 0) { cc_text(out, "return v;}\n"); return; }
        cc_type(out, id); cc_text(out, " *result=("); cc_type(out, id); cc_text(out, "*)g_fixed_alloc(sizeof *result);memset(result,0,sizeof *result);\n");
        if width > 0 { cc_id(out, "g_init_", id); cc_text(out, "(g_ref(result),slot);\n"); }
        cc_id(out, "g_store_", id); cc_text(out, "(g_ref(result),*v);return result;}\n"); return;
    }
    cc_text(out, "static "); cc_type(out, id); cc_id(out, " g_clone_", id); cc_text(out, "("); cc_type(out, id); cc_text(out, " v");
    if width > 0 { cc_text(out, ",int64_t slot"); }
    cc_text(out, "){\n");
    if !cc_needs_clone(p, id, 0) { cc_text(out, "return v;}\n"); return; }
    cc_type(out, id); cc_text(out, " result="); cc_zero_initializer(p, out, id); cc_text(out, ";\n");
    if width > 0 { cc_id(out, "g_init_", id); cc_text(out, "(g_ref(&result),slot);\n"); }
    cc_id(out, "g_store_", id); cc_text(out, "(g_ref(&result),v);return result;}\n");
}
fn cc_print_field(p: Program&, out: u8[>..]&, type_id: i64, field: i64, separator: bool) {
    let n = p.nodes[field];
    if cc_flat_relative_image(p, type_id) {
        if (n.flags & F_PAD) != 0 { if n.aux > 0 { out.format("g_cursor=g_relative_cell_skip(g_cursor,v.end,", n.aux, ");\n"); } return; }
        if separator { cc_text(out, "g_print_text(out,\", \");\n"); }
        out.format("g_nested_", n.type_id, "(out,g_physical_load_", n.type_id, "(g_cursor,v.end));g_cursor=g_relative_cell_skip(g_cursor,v.end,", cc_physical_cell_width(p, n.type_id), ");\n"); return;
    }
    if cc_image_type(p, type_id) {
        if (n.flags & F_PAD) != 0 { out.format("g_cursor+=", n.aux, ";\n"); return; }
        if separator { cc_text(out, "g_print_text(out,\", \");\n"); }
        out.format("g_nested_", n.type_id, "(out,g_load_", n.type_id, "(g_ref(g_cursor)));g_cursor=g_physical_skip_", n.type_id, "(g_cursor);\n"); return;
    }
    if (n.flags & F_PAD) != 0 { return; }
    if separator { cc_text(out, "g_print_text(out,\", \");\n"); }
    cc_id(out, "g_nested_", n.type_id); cc_text(out, "(out,"); cc_id(out, "g_native_load_", n.type_id); cc_text(out, "(g_offset(g_ref(&v),"); cc_number(out, cc_field_offset(p, type_id, field)); cc_text(out, ")));\n");
}
fn cc_emit_print(p: Program&, out: u8[>..]&, id: i64) {
    let t = p.types[id]; if !cc_concrete(p, id) || t.kind == TY_VOID { return; }
    cc_text(out, "static void "); cc_helper_name(p, out, "g_print_", id); cc_text(out, "(GArray *out,"); cc_helper_value(p, out, id, "v"); cc_text(out, ") {\n"); cc_helper_alias(p, out, id, "v"); cc_text(out, "g_stack_check();\n");
    if t.kind == TY_INT || t.kind == TY_FLOAT || t.kind == TY_BOOL {
        cc_text(out, "unsigned char b[128]; int64_t n=");
        if t.kind == TY_BOOL { cc_text(out, "gs_fmt_bool(b,v)"); }
        else if t.kind == TY_FLOAT && t.count == 32 { cc_text(out, "gs_fmt_f32(b,v)"); }
        else if t.kind == TY_FLOAT { cc_text(out, "gs_fmt_f64(b,v)"); }
        else if (t.flags & TF_UNSIGNED) != 0 { cc_text(out, "gs_fmt_u64(b,v)"); }
        else { cc_text(out, "gs_fmt_i64(b,v)"); }
        cc_text(out, ";g_print_bytes(out,b,n);\n");
    } else if t.kind == TY_REF && cc_kind(p, t.element) == TY_VOID {
        cc_text(out, "g_print_text(out,\"null\");\n");
    } else if t.kind == TY_REF {
        cc_text(out, "if(!v) g_print_text(out,\"null\"); else "); cc_id(out, "g_print_", t.element); cc_text(out, "(out,"); cc_id(out, "g_load_", t.element); cc_text(out, "(v));\n");
    } else if t.kind == TY_FN { cc_text(out, "g_print_text(out,\"fn\");\n"); }
    else if t.kind == TY_ARRAY || t.kind == TY_SLICE {
        cc_text(out, "GRef r=g_ref("); if cc_image_type(p, id) { cc_text(out, "v.base"); } else { cc_text(out, "&v"); } cc_text(out, "); int64_t n=g_len(r,"); cc_array_args(p, out, id, false); cc_text(out, ");\n");
        if cc_size_class(p, t.element) == 1 {
            cc_text(out, "const uint8_t *cursor=g_address(g_element(r,"); cc_array_args(p, out, id); cc_text(out, ",0,1));g_print_text(out,\"[\");\n");
            out.format("for(int64_t i=0;i<n;i++){if(i)g_print_text(out,\", \");g_nested_", t.element, "(out,g_load_", t.element, "(g_ref(cursor)));cursor=g_physical_skip_", t.element, "(cursor);}g_print_text(out,\"]\");}\n");
            cc_helper_alias(p, out, id, "v", true); return;
        }
        let bytes = cc_kind(p, t.element) == TY_INT && p.types[t.element].count == 8 && (p.types[t.element].flags & TF_UNSIGNED) != 0;
        if !bytes { cc_text(out, "g_print_text(out,\"[\");\n"); }
        cc_text(out, "for(int64_t i=0;i<n;i++) {\n");
        if !bytes { cc_text(out, "if(i)g_print_text(out,\", \");\n"); }
        if bytes {
            cc_text(out, "g_print_bytes(out,g_address(g_element(r,"); cc_array_args(p, out, id); cc_text(out, ",i,0)),1);\n");
        } else {
            cc_id(out, "g_nested_", t.element); cc_text(out, "(out,"); cc_id(out, "g_load_", t.element); cc_text(out, "(g_element(r,"); cc_array_args(p, out, id); cc_text(out, ",i,0)));\n");
        }
        cc_text(out, "}\n"); if !bytes { cc_text(out, "g_print_text(out,\"]\");\n"); }
    } else if t.kind == TY_STRUCT && t.declaration >= 0 && p.nodes[t.declaration].kind == N_VARIANT && p.nodes[t.declaration].first < 0 && t.pool >= 0 {
        cc_text(out, "g_print_text(out,"); cc_bytes(out, token_text(p, p.nodes[p.types[t.pool].declaration].token)); cc_text(out, ");g_print_text(out,\".\");g_print_text(out,");
        cc_bytes(out, token_text(p, p.nodes[t.declaration].token)); cc_text(out, ");\n");
    } else if t.kind == TY_STRUCT && t.declaration >= 0 {
        var name: u8[>..] = [];
        if p.nodes[t.declaration].kind == N_VARIANT { name.append(token_text(p, p.nodes[t.declaration].token)); }
        else { render_type_name(p, id, name, 0, false); }
        cc_text(out, "g_print_text(out,"); cc_bytes(out, name); cc_text(out, ");g_print_text(out,\" { \");\n");
        if cc_image_type(p, id) { cc_text(out, "const uint8_t *g_cursor=v.base;\n"); }
        var field = p.nodes[t.declaration].first; var separator = false;
        while field >= 0 { cc_print_field(p, out, id, field, separator); if (p.nodes[field].flags & F_PAD) == 0 { separator = true; } field = p.nodes[field].next; }
        cc_text(out, "g_print_text(out,\" }\");\n");
    } else if t.kind == TY_ENUM && t.declaration >= 0 {
        cc_text(out, "switch(g_read_length("); if cc_image_type(p, id) { cc_text(out, "v.base,"); } else { cc_text(out, "&v,"); } cc_number(out, t.length_storage); cc_text(out, ")) {\n");
        var variant = p.nodes[t.declaration].first;
        while variant >= 0 {
            cc_text(out, "case "); cc_number(out, p.nodes[variant].integer); cc_text(out, ":\n");
            var field = p.nodes[variant].first;
            if field < 0 {
                cc_text(out, "g_print_text(out,"); cc_bytes(out, token_text(p, p.nodes[t.declaration].token)); cc_text(out, ");g_print_text(out,\".\");g_print_text(out,");
                cc_bytes(out, token_text(p, p.nodes[variant].token)); cc_text(out, ");\n");
            }
            if field >= 0 {
                let payload = p.nodes[variant].type_id; cc_id(out, "g_print_", payload); cc_text(out, "(out,"); if cc_image_type(p, id) { cc_id(out, "g_load_", payload); } else { cc_id(out, "g_native_load_", payload); }
                cc_text(out, "(g_offset("); if cc_image_type(p, id) { cc_text(out, "g_ref(v.base),"); } else { cc_text(out, "g_ref(&v),"); } cc_number(out, t.length_storage); cc_text(out, ")));\n");
            }
            cc_text(out, "break;\n"); variant = p.nodes[variant].next;
        }
        cc_text(out, "default:g_panic(\"corrupt ADT tag\");}\n");
    } else if t.kind == TY_TUPLE {
        var part = t.first; var index = 0;
        while part >= 0 {
            if index > 0 { cc_text(out, "g_print_text(out,\", \");\n"); }
            cc_id(out, "g_print_", p.nodes[part].type_id); cc_text(out, "(out,"); cc_id(out, "v.f", index); cc_text(out, ");\n");
            index++; part = p.nodes[part].next;
        }
    }
    cc_text(out, "}\n"); cc_helper_alias(p, out, id, "v", true);
}

recursive fn cc_default(p: Program&, f: CcBody&, type_id: i64) -> i64 {
    if cc_image_type(p, type_id) {
        if cc_kind(p, type_id) == TY_ARRAY { return cc_image_array(p, f, -1, type_id); } return cc_image_record(p, f, -1, type_id);
    }
    let result = cc_temp(p, f, type_id); if result < 0 { return -1; }
    let t = p.types[type_id];
    if t.kind == TY_ARRAY && t.array_kind == A_FIXED {
        let counter = f.serial; f.serial++;
        cc_id(f.out, "for(int64_t g_i", counter); cc_text(f.out, "=0;"); cc_id(f.out, "g_i", counter); cc_text(f.out, "<"); cc_number(f.out, t.count); cc_text(f.out, ";"); cc_id(f.out, "g_i", counter); cc_text(f.out, "++) {\n");
        let element = cc_default(p, f, t.element); cc_id(f.out, "g_store_", t.element); cc_text(f.out, "(g_element(g_ref(&"); cc_id(f.out, "g_v", result); cc_text(f.out, "),"); cc_array_args(p, f.out, type_id); cc_text(f.out, ","); cc_id(f.out, "g_i", counter); cc_text(f.out, ",0),"); cc_id(f.out, "g_v", element); cc_text(f.out, ");}\n");
    } else if t.kind == TY_STRUCT && t.declaration >= 0 {
        var field = p.nodes[t.declaration].first;
        while field >= 0 {
            let n = p.nodes[field];
            if (n.flags & F_PAD) == 0 {
                var value: i64 = -1;
                if n.right >= 0 { value = cc_to(p, f, n.right, n.type_id, true); } else { value = cc_default(p, f, n.type_id); }
                let ref = cc_ref_temp(f); cc_set(f, ref); cc_text(f.out, "g_offset(g_ref(&"); cc_id(f.out, "g_v", result); cc_text(f.out, "),"); cc_number(f.out, cc_field_offset(p, type_id, field)); cc_text(f.out, ");\n"); cc_store(p, f, ref, value, n.type_id);
            }
            field = n.next;
        }
    }
    return result;
}
fn cc_binary_operator(out: u8[>..]&, op: i64) -> bool {
    if op == T_PLUS { cc_text(out, "+"); } else if op == T_MINUS { cc_text(out, "-"); }
    else if op == T_MUL { cc_text(out, "*"); } else if op == T_DIV { cc_text(out, "/"); }
    else if op == T_MOD { cc_text(out, "%"); } else if op == T_BITAND { cc_text(out, "&"); }
    else if op == T_BITOR { cc_text(out, "|"); } else if op == T_XOR { cc_text(out, "^"); }
    else if op == T_SHL { cc_text(out, "<<"); } else if op == T_SHR { cc_text(out, ">>"); }
    else if op == T_EQ || op == T_DOTEQ { cc_text(out, "=="); } else if op == T_NEQ || op == T_DOTNEQ { cc_text(out, "!="); }
    else if op == T_LT { cc_text(out, "<"); } else if op == T_GT { cc_text(out, ">"); }
    else if op == T_LTEQ { cc_text(out, "<="); } else if op == T_GTEQ { cc_text(out, ">="); }
    else { return false; } return true;
}
fn cc_binary_values(p: Program&, f: CcBody&, op: i64, left: i64, right: i64, operand: i64, result_type: i64, node: i64) -> i64 {
    let result = cc_temp(p, f, result_type); if result < 0 { return -1; }
    let t = p.types[operand]; cc_set(f, result);
    if op == T_DOTEQ || op == T_DOTNEQ {
        cc_text(f.out, "(g_nullable_address("); cc_id(f.out, "g_v", left); cc_text(f.out, ")"); cc_binary_operator(f.out, op); cc_text(f.out, "g_nullable_address("); cc_id(f.out, "g_v", right); cc_text(f.out, "))");
    } else if cc_aggregate(p, operand) || t.kind == TY_SLICE {
        if op != T_EQ && op != T_NEQ { cc_text(f.out, "0"); cc_fail(p, node, "c: aggregate operator needs a resolved overload"); }
        else {
            if op == T_NEQ { cc_text(f.out, "!"); }
            cc_id(f.out, "g_equal_", operand); cc_text(f.out, "("); cc_id(f.out, "g_v", left); cc_text(f.out, ","); cc_id(f.out, "g_v", right); cc_text(f.out, ")");
        }
    } else if p.debug && t.kind == TY_INT && (t.flags & TF_UNSIGNED) == 0 &&
              (op == T_PLUS || op == T_MINUS || op == T_MUL || op == T_DIV) {
        cc_text(f.out, "g_checked_binary("); cc_id(f.out, "g_v", left); cc_text(f.out, ","); cc_id(f.out, "g_v", right);
        cc_text(f.out, ","); cc_number(f.out, t.count); cc_text(f.out, ","); cc_number(f.out, op); cc_text(f.out, ",");
        cc_location(p, f.out, node); cc_text(f.out, ")");
    } else if (op == T_DIV || op == T_MOD) && t.kind == TY_INT {
        if (t.flags & TF_UNSIGNED) != 0 { if op == T_DIV { cc_text(f.out, "g_udiv("); } else { cc_text(f.out, "g_umod("); } }
        else { if op == T_DIV { cc_text(f.out, "g_div("); } else { cc_text(f.out, "g_mod("); } }
        cc_id(f.out, "g_v", left); cc_text(f.out, ","); cc_id(f.out, "g_v", right); cc_text(f.out, ","); cc_location(p, f.out, node); cc_text(f.out, ")");
    } else if op == T_MOD && t.kind == TY_FLOAT {
        cc_text(f.out, "fmod("); cc_id(f.out, "g_v", left); cc_text(f.out, ","); cc_id(f.out, "g_v", right); cc_text(f.out, ")");
    } else {
        let wrap = t.kind == TY_INT && (op == T_PLUS || op == T_MINUS || op == T_MUL || op == T_SHL);
        cc_text(f.out, "("); cc_type(f.out, result_type); cc_text(f.out, ")(");
        if wrap { cc_text(f.out, "(uint64_t)"); }
        cc_id(f.out, "g_v", left);
        if !cc_binary_operator(f.out, op) { cc_fail(p, node, "c: unknown binary operator"); }
        if wrap { cc_text(f.out, "(uint64_t)"); }
        if op == T_SHL || op == T_SHR { cc_text(f.out, "("); }
        cc_id(f.out, "g_v", right);
        if op == T_SHL || op == T_SHR { cc_text(f.out, "&"); cc_number(f.out, t.count - 1); cc_text(f.out, ")"); }
        cc_text(f.out, ")");
    }
    cc_text(f.out, ";\n"); return result;
}
recursive fn cc_binary(p: Program&, f: CcBody&, node: i64) -> i64 {
    let n = p.nodes[node];
    if (n.integer == T_EQ || n.integer == T_NEQ) &&
       (p.nodes[n.left].kind == N_NULL || p.nodes[n.right].kind == N_NULL) {
        let left = cc_expr(p, f, n.left); let right = cc_expr(p, f, n.right);
        var op = T_DOTEQ; if n.integer == T_NEQ { op = T_DOTNEQ; }
        return cc_binary_values(p, f, op, left, right, p.nodes[n.left].type_id, TYPE_BOOL, node);
    }
    if n.integer == T_ANDAND || n.integer == T_OROR {
        let result = cc_to(p, f, n.left, TYPE_BOOL); cc_text(f.out, "if(");
        if n.integer == T_OROR { cc_text(f.out, "!"); } cc_id(f.out, "g_v", result); cc_text(f.out, ") {\n");
        let right = cc_to(p, f, n.right, TYPE_BOOL); cc_set(f, result); cc_id(f.out, "g_v", right); cc_text(f.out, ";}\n"); return result;
    }
    var operand = p.nodes[n.left].type_id;
    if cc_kind(p, operand) == TY_REF && n.integer != T_DOTEQ && n.integer != T_DOTNEQ { operand = p.types[operand].element; }
    if cc_kind(p, n.aux) == TY_INT || cc_kind(p, n.aux) == TY_FLOAT || cc_kind(p, n.aux) == TY_BOOL { operand = n.aux; }
    let left = cc_to(p, f, n.left, operand); let right = cc_to(p, f, n.right, operand);
    return cc_binary_values(p, f, n.integer, left, right, operand, n.type_id, node);
}
fn cc_inline_argument(p: Program&, node: i64) -> bool {
    let n = p.nodes[node]; if n.kind != N_VARIABLE { return false; }
    var binding = n.first;
    if binding < 0 { return n.origin >= 0 && p.nodes[n.origin].kind == N_PARAM; }
    while binding >= 0 {
        let b = p.nodes[binding]; if b.origin < 0 || p.nodes[b.origin].kind != N_PARAM { return false; } binding = b.next;
    }
    return true;
}
recursive fn cc_block(p: Program&, f: CcBody&, node: i64, destination: i64 = -1) -> i64 {
    let n = p.nodes[node]; var result = destination;
    if result < 0 && n.type_id >= 0 && cc_kind(p, n.type_id) != TY_VOID { result = cc_result_temp(p, f, node, n.type_id); }
    var child = n.first;
    while child >= 0 && cc_inline_argument(p, child) { cc_expr(p, f, child); child = p.nodes[child].next; }
    let region_mark = f.region_live; let receiving_mark = f.receiving.len;
    let publications = f.serial; f.serial++;
    cc_id(f.out, "GPublication *g_scope_publications", publications); cc_text(f.out, "=g_publication_top;\n");
    if result >= 0 && n.named_results >= 0 {
        let target = cc_temporary_ref(f, result); cc_bind_named_results(p, f, node, n.type_id, target);
    }
    var early = false; var label = -1;
    if (n.flags & F_EARLY) != 0 {
        early = true; label = f.serial; f.serial++;
        f.exits.push(CcExit { node: node, done: label, result: result, type_id: n.type_id, regions: region_mark, publications: publications });
    }
    cc_text(f.out, "{\n");
    while child >= 0 {
        let kind = p.nodes[child].kind; let statement_mark = f.region_live;
        let terminates = cc_diverges(p, child);
        if !terminates && p.nodes[child].next < 0 && (p.nodes[child].flags & F_TAIL) != 0 && result >= 0 {
            let destination = cc_temporary_ref(f, result); let value = cc_construct_into(p, f, child, n.type_id, destination, cc_value_form(p, n.type_id));
            if value < 0 { cc_fail(p, child, "c: block result has no value"); }
        } else {
            cc_expr(p, f, child);
            if kind != N_VARIABLE { cc_restore(f, statement_mark); f.region_live = statement_mark; }
        }
        child = p.nodes[child].next;
    }
    cc_restore(f, region_mark); f.region_live = region_mark; cc_text(f.out, "g_publication_top="); cc_id(f.out, "g_scope_publications", publications); cc_text(f.out, ";\n}\n");
    f.receiving.resize(receiving_mark);
    if early { f.exits.pop(); cc_id(f.out, "g_label", label); cc_text(f.out, ":;\n"); }
    return result;
}
recursive fn cc_values(p: Program&, f: CcBody&, first: i64, type_id: i64, target: i64 = -1) -> i64 {
    if target >= 0 && (cc_kind(p, type_id) == TY_TUPLE || cc_region_width(p, type_id) > 0 || cc_result_location(p, type_id)) {
        if cc_kind(p, type_id) != TY_TUPLE || first >= 0 && p.nodes[first].next < 0 && cc_kind(p, p.nodes[first].type_id) == TY_TUPLE {
            return cc_construct_into(p, f, first, type_id, target);
        }
        var part = p.types[type_id].first; var value = first; var ordinal = 0;
        while part >= 0 && value >= 0 {
            let header = cc_channel_target(p, f, target, type_id, ordinal);
            cc_construct_into(p, f, value, p.nodes[part].type_id, header, cc_value_form(p, p.nodes[part].type_id));
            ordinal++; part = p.nodes[part].next; value = p.nodes[value].next;
        }
        if part >= 0 || value >= 0 { cc_fail(p, first, "c: return value arity mismatch"); }
        let result = cc_temp(p, f, type_id, true, false); f.channels.push(CcChannels { value: result, address: target }); return result;
    }
    if cc_kind(p, type_id) == TY_VOID {
        var effect = first;
        while effect >= 0 { cc_expr(p, f, effect); effect = p.nodes[effect].next; }
        return -1;
    }
    if p.nodes[first].next < 0 && cc_kind(p, p.nodes[first].type_id) == TY_TUPLE { return cc_to(p, f, first, type_id, true); }
    if cc_kind(p, type_id) != TY_TUPLE { return cc_to(p, f, first, type_id, true); }
    let result = cc_temp(p, f, type_id); var part = p.types[type_id].first; var value = first; var index = 0;
    while part >= 0 && value >= 0 {
        let v = cc_to(p, f, value, p.nodes[part].type_id, true);
        if v < 0 { return -1; }
        if cc_relative_cell(p, p.nodes[part].type_id) { cc_id(f.out, "g_v", result); cc_id(f.out, ".f", index); cc_text(f.out, "="); cc_id(f.out, "g_v", v); cc_text(f.out, ";\n"); }
        else { cc_id(f.out, "g_store_", p.nodes[part].type_id); cc_text(f.out, "(g_ref(&"); cc_id(f.out, "g_v", result); cc_id(f.out, ".f", index); cc_text(f.out, "),"); cc_id(f.out, "g_v", v); cc_text(f.out, ");\n"); }
        index++; part = p.nodes[part].next; value = p.nodes[value].next;
    }
    if part >= 0 || value >= 0 { cc_fail(p, first, "c: return value arity mismatch"); } return result;
}
recursive fn cc_return(p: Program&, f: CcBody&, node: i64) {
    let n = p.nodes[node]; var target = f.function;
    if n.symbol >= 0 && n.symbol < p.symbols.len { target = p.symbols[n.symbol].node; }
    let type_id = cc_function_result(p, target); var receiver = -1;
    if cc_tuple_channels(p, type_id) && target == f.function { receiver = f.result_ref; }
    else if cc_tuple_channels(p, type_id) || cc_region_width(p, type_id) > 0 || cc_result_location(p, type_id) {
        receiver = cc_ref_temp(f); cc_set(f, receiver);
        if target == f.function { cc_text(f.out, "g_ref((void*)&g_result);\n"); }
        else { cc_text(f.out, "g_ref(g_return_destination("); cc_number(f.out, target); cc_text(f.out, "));\n"); }
        if cc_tuple_channels(p, type_id) { f.channels.push(CcChannels { value: -1, address: receiver }); }
    }
    let result = cc_values(p, f, n.first, type_id, receiver);
    if target == f.function {
        if result >= 0 { cc_return_store(p, f, result, type_id); }
        cc_text(f.out, "goto g_return;\n");
    } else {
        cc_text(f.out, "g_throw("); cc_number(f.out, target); cc_text(f.out, ",");
        if result >= 0 && cc_tuple_channels(p, type_id) {
            cc_text(f.out, "g_address("); cc_id(f.out, "g_v", receiver); cc_text(f.out, "),"); cc_number(f.out, p.types[type_id].count * 8);
        } else if result >= 0 { cc_text(f.out, "&"); cc_id(f.out, "g_v", result); cc_text(f.out, ",sizeof("); cc_type(f.out, type_id); cc_text(f.out, ")"); }
        else { cc_text(f.out, "NULL,0"); } cc_text(f.out, ");\n");
    }
}
recursive fn cc_loop_path(p: Program&, node: i64) -> bool {
    if node < 0 { return false; }
    let n = p.nodes[node];
    if n.kind == N_NAME { return true; }
    if n.kind == N_MEMBER || n.kind == N_UNARY && n.integer == T_MUL { return cc_loop_path(p, n.left); }
    return false;
}
recursive fn cc_loop_cursors(p: Program&, f: CcBody&, body: i64, index: i64) {
    let mark = f.work.len; f.work.push(body);
    while f.work.len > mark {
        let node = f.work.pop(); if node < 0 { continue; } let n = p.nodes[node];
        if n.next >= 0 { f.work.push(n.next); }
        if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE { continue; }
        if n.kind == N_INDEX && cc_cursor_symbol(p, n.left) >= 0 && p.nodes[n.right].kind == N_NAME && p.nodes[n.right].symbol == index {
            var type_id = p.nodes[n.left].type_id; while cc_kind(p, type_id) == TY_REF { type_id = p.types[type_id].element; }
            if (cc_kind(p, type_id) == TY_ARRAY || cc_kind(p, type_id) == TY_SLICE) && cc_size_class(p, p.types[type_id].element) == 1 {
                var exists = false;
                for cursor in f.cursors { if cursor.symbol == cc_cursor_symbol(p, n.left) && cursor.index == index { exists = true; } }
                if !exists {
                    let base = cc_base(p, f, n.left); let address = cc_ref_temp(f); cc_set(f, address); cc_text(f.out, "g_element("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id); cc_text(f.out, ",0,1);\n");
                    f.cursors.push(CcCursor { symbol: cc_cursor_symbol(p, n.left), index: index, address: address, type_id: p.types[type_id].element });
                }
            }
        }
        if n.first >= 0 { f.work.push(n.first); } if n.left >= 0 { f.work.push(n.left); } if n.right >= 0 { f.work.push(n.right); } if n.third >= 0 { f.work.push(n.third); }
    }
}
recursive fn cc_loop(p: Program&, f: CcBody&, node: i64) -> i64 {
    let n = p.nodes[node]; var result = -1; let cursor_mark = f.cursors.len;
    if n.type_id >= 0 { result = cc_result_temp(p, f, node, n.type_id); }
    let done = f.serial; f.serial++;
    let again = f.serial; f.serial++;
    let region_mark = f.region_live; let publications = f.serial; f.serial++;
    cc_id(f.out, "GPublication *g_scope_publications", publications); cc_text(f.out, "=g_publication_top;\n");
    f.exits.push(CcExit { node: node, done: done, again: again, result: result, type_id: n.type_id, regions: region_mark, again_regions: region_mark, publications: publications });
    cc_text(f.out, "{\n");
    if n.kind == N_FOR {
        let binding = n.first; let index_binding = p.nodes[binding].next;
        let iterable = p.nodes[n.left]; var counter = -1; var end = -1; var base = -1; var array = iterable.type_id; var cursor = -1; var origin = -1;
        var count_type = iterable.type_id;
        while cc_kind(p, count_type) == TY_REF { count_type = p.types[count_type].element; }
        if iterable.kind == N_RANGE {
            counter = cc_to(p, f, iterable.left, TYPE_I64); end = cc_to(p, f, iterable.right, TYPE_I64);
        } else if cc_kind(p, count_type) == TY_INT {
            if cc_kind(p, iterable.type_id) == TY_REF {
                var place = cc_base_place(p, f, n.left);
                while cc_kind(p, place.type_id) == TY_REF {
                    let address = cc_read(p, f, place, place.type_id, n.left);
                    place = CcPlace { type_id: p.types[place.type_id].element, address: address };
                }
                let value = cc_read(p, f, place, count_type, n.left);
                end = cc_convert(p, f, value, count_type, TYPE_I64, n.left);
            } else { end = cc_to(p, f, n.left, TYPE_I64); }
            counter = cc_temp(p, f, TYPE_I64);
        } else {
            if cc_kind(p, array) == TY_REF { array = p.types[array].element; }
            base = cc_base(p, f, n.left); counter = cc_temp(p, f, TYPE_I64); end = cc_temp(p, f, TYPE_I64);
            cc_set(f, end); cc_text(f.out, "g_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, array, false); cc_text(f.out, ");\n");
        }
        if base < 0 && (iterable.kind == N_RANGE && p.nodes[iterable.left].kind == N_INTEGER && p.nodes[iterable.left].integer == 0 || cc_kind(p, count_type) == TY_INT) {
            cc_loop_cursors(p, f, n.right, p.nodes[binding].symbol);
        }
        let cursor_end = f.cursors.len;
        if base >= 0 {
            if cc_size_class(p, p.types[array].element) == 1 {
                cursor = cc_ref_temp(f); cc_set(f, cursor); cc_text(f.out, "g_element("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, array); cc_text(f.out, ",0,1);\n");
                origin = cc_ref_temp(f); cc_set(f, origin); cc_id(f.out, "g_v", cursor); cc_text(f.out, ";\n");
            }
            cc_text(f.out, "for(;;) {\n");
            if cc_loop_path(p, n.left) { base = cc_base(p, f, n.left); }
            cc_set(f, end); cc_text(f.out, "g_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, array, false); cc_text(f.out, ");\n");
            cc_text(f.out, "if("); cc_id(f.out, "g_v", counter); cc_text(f.out, ">="); cc_id(f.out, "g_v", end); cc_text(f.out, ")break;\n");
            if cursor >= 0 && cc_loop_path(p, n.left) {
                let current = cc_ref_temp(f); cc_set(f, current); cc_text(f.out, "g_element("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, array); cc_text(f.out, ",0,1);\n");
                f.out.format("if(g_v", current, "!=g_v", origin, "){g_v", origin, "=g_v", current, ";g_v", cursor, "=g_v", current, ";\n",
                    "for(int64_t g_repoint", current, "=0;g_repoint", current, "<g_v", counter, ";g_repoint", current, "++)g_v", cursor, "=g_ref(g_physical_skip_", p.types[array].element, "(g_address(g_v", cursor, ")));}\n");
            }
        } else {
            cc_text(f.out, "for(; "); cc_id(f.out, "g_v", counter); cc_text(f.out, "<"); cc_id(f.out, "g_v", end); cc_text(f.out, ";"); cc_id(f.out, "g_v", counter); cc_text(f.out, "++) {\n");
        }
        f.exits[f.exits.len - 1].again_regions = f.region_live;
        if base >= 0 {
            let ref = cc_ref_temp(f); cc_set(f, ref);
            if cursor >= 0 { cc_id(f.out, "g_v", cursor); cc_text(f.out, ";\n"); }
            else { cc_text(f.out, "g_element("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, array); cc_text(f.out, ","); cc_id(f.out, "g_v", counter); cc_text(f.out, ",0);\n"); }
            var value = ref;
            if (p.nodes[binding].flags & F_REFERENCE) == 0 || cc_kind(p, p.types[array].element) == TY_REF { value = cc_load(p, f, ref, p.types[array].element); }
            cc_id(f.out, "g_s", p.nodes[binding].symbol); cc_text(f.out, "="); cc_id(f.out, "g_v", value); cc_text(f.out, ";\n");
        } else {
            cc_id(f.out, "g_s", p.nodes[binding].symbol); cc_text(f.out, "="); cc_id(f.out, "g_v", counter); cc_text(f.out, ";\n");
        }
        if index_binding >= 0 {
            cc_id(f.out, "g_s", p.nodes[index_binding].symbol); cc_text(f.out, "="); cc_id(f.out, "g_v", counter); cc_text(f.out, ";\n");
        }
        cc_expr(p, f, n.right); cc_id(f.out, "g_label", again); cc_text(f.out, ":;\n");
        var cursor_index = cursor_mark;
        while cursor_index < cursor_end {
            let indexed = f.cursors[cursor_index]; cc_set(f, indexed.address); cc_text(f.out, "g_ref(g_physical_skip_"); cc_number(f.out, indexed.type_id); cc_text(f.out, "(g_address("); cc_id(f.out, "g_v", indexed.address); cc_text(f.out, ")));\n"); cursor_index++;
        }
        if cursor >= 0 {
            cc_set(f, cursor); cc_text(f.out, "g_ref(g_physical_skip_"); cc_number(f.out, p.types[array].element); cc_text(f.out, "(g_address("); cc_id(f.out, "g_v", cursor); cc_text(f.out, ")));\n");
        }
        if base >= 0 { cc_id(f.out, "g_v", counter); cc_text(f.out, "++;\n"); }
        cc_text(f.out, "}\n");
    } else {
        cc_text(f.out, "for(;;) {\n");
        if n.kind == N_WHILE {
            let condition = cc_truth(p, f, n.left); cc_text(f.out, "if(!"); cc_id(f.out, "g_v", condition); cc_text(f.out, ") break;\n");
        }
        cc_expr(p, f, n.right); cc_id(f.out, "g_label", again); cc_text(f.out, ":;\n}\n");
    }
    cc_id(f.out, "g_label", done); cc_text(f.out, ":;\n"); cc_restore(f, region_mark); f.region_live = region_mark; cc_text(f.out, "g_publication_top="); cc_id(f.out, "g_scope_publications", publications); cc_text(f.out, ";\n}\n"); f.cursors.resize(cursor_mark); f.exits.pop(); return result;
}
recursive fn cc_call(p: Program&, f: CcBody&, node: i64) -> i64 {
    let n = p.nodes[node];
    if (n.flags & F_DISPATCH) != 0 { return cc_dispatch(p, f, node); }
    if n.symbol >= 0 && (p.symbols[n.symbol].flags & S_BUILTIN) != 0 { return cc_builtin(p, f, node, p.symbols[n.symbol].index); }
    var function: i64 = -1; var callable = p.nodes[n.left].type_id; var closure: i64 = -1;
    if n.symbol >= 0 && (p.symbols[n.symbol].flags & S_FUNCTION) != 0 { function = p.symbols[n.symbol].node; callable = p.symbols[n.symbol].type_id; }
    if function >= 0 {
        if p.nodes[function].captures >= 0 { closure = cc_closure(p, f, function, callable); }
    } else { closure = cc_expr(p, f, n.left); }
    if cc_kind(p, callable) != TY_FN { cc_fail(p, node, "c: call lacks a checked function signature"); return -1; }
    let args_start = f.work.len; var args_count = 0; var param = p.types[callable].first; var arg = n.first;
    while arg >= 0 { f.work.push(-1); args_count++; arg = p.nodes[arg].next; }
    var authority = false; var scan = param;
    while scan >= 0 { if cc_flat_image_reference(p, p.nodes[scan].type_id) { authority = true; } scan = p.nodes[scan].next; }
    if authority { for i in args_count { f.work.push(-1); } }
    arg = n.first; var ordinal = 0;
    while param >= 0 && arg >= 0 {
        let value = cc_to(p, f, arg, p.nodes[param].type_id, true);
        if value < 0 { return -1; }
        cc_relative_check(p, f, value, p.nodes[param].type_id, arg);
        f.work[args_start + ordinal] = value;
        if cc_flat_image_reference(p, p.nodes[param].type_id) {
            let owner = cc_image_reference_owner(p, f, arg);
            if owner < 0 { cc_fail(p, arg, "c: relative image argument has no proved owner authority"); return -1; }
            f.work[args_start + args_count + ordinal] = owner;
        }
        ordinal++; param = p.nodes[param].next; arg = p.nodes[arg].next;
    }
    if param >= 0 || arg >= 0 { cc_fail(p, node, "c: checked call argument arity mismatch"); return -1; }
    let natural_type = p.types[callable].element;
    let result = cc_result_temp(p, f, node, natural_type);
    var result_channels = -1; if cc_tuple_channels(p, natural_type) { result_channels = cc_temporary_ref(f, result); }
    if result >= 0 && !cc_result_indirect(p, natural_type) { cc_set(f, result); }
    if function >= 0 { cc_id(f.out, "g_fn", function); }
    else { cc_text(f.out, "(("); cc_function_type(p, f.out, callable); cc_text(f.out, ")"); cc_id(f.out, "g_v", closure); cc_text(f.out, "->function)"); }
    cc_text(f.out, "(");
    if closure >= 0 { cc_id(f.out, "g_v", closure); } else { cc_text(f.out, "NULL"); }
    cc_text(f.out, ","); cc_region_argument(f, f.region_live);
    if cc_receives(p, natural_type) {
        if cc_tuple_channels(p, natural_type) { cc_text(f.out, ",(GRef*)g_address("); cc_id(f.out, "g_v", result_channels); cc_text(f.out, ")"); }
        else { cc_text(f.out, ",&"); cc_id(f.out, "g_v", result); }
    }
    param = p.types[callable].first;
    for i in 0..args_count {
        cc_text(f.out, ","); if cc_indirect(p, p.nodes[param].type_id) { cc_text(f.out, "&"); } cc_id(f.out, "g_v", f.work[args_start + i]);
        if cc_flat_image_reference(p, p.nodes[param].type_id) { cc_text(f.out, ","); cc_id(f.out, "g_v", f.work[args_start + args_count + i]); }
        param = p.nodes[param].next;
    } cc_text(f.out, ");\n");
    if function >= 0 { cc_region_call(f, function, node); }
    else {
        for candidate, id in p.nodes { if cc_emittable(p, id) && candidate.type_id == callable { cc_region_call(f, id, node); } }
    }
    return cc_convert(p, f, result, natural_type, n.type_id, node);
}

recursive fn cc_dispatch(p: Program&, f: CcBody&, node: i64) -> i64 {
    let n = p.nodes[node];
    if n.symbol < 0 || n.third < 0 || n.aux < 0 { cc_fail(p, node, "c: case dispatch lacks checked arms"); return -1; }
    let signature = p.symbols[n.symbol].type_id;
    var checked = p.types[signature].first;
    while checked >= 0 {
        if cc_flat_image_reference(p, p.nodes[checked].type_id) { cc_fail(p, node, "c: image-reference dispatch needs owner authority forwarding"); return -1; }
        checked = p.nodes[checked].next;
    }
    let args_start = f.work.len; var count = 0; var argument = n.first;
    while argument >= 0 { f.work.push(-1); count++; argument = p.nodes[argument].next; }
    var parameter = p.types[signature].first; var ordinal = 0;
    var original = -1; var snapshot = -1; var enum_type = -1; argument = n.first;
    while argument >= 0 && parameter >= 0 {
        if ordinal == n.aux {
            enum_type = p.nodes[argument].type_id;
            while cc_kind(p, enum_type) == TY_REF { enum_type = p.types[enum_type].element; }
            if cc_kind(p, enum_type) != TY_ENUM { cc_fail(p, node, "c: dispatch argument is not an enum"); return -1; }
            original = cc_base(p, f, argument);
            let value = cc_load(p, f, original, enum_type);
            let copied = cc_convert(p, f, value, enum_type, enum_type, argument, true);
            snapshot = cc_array_value_ref(p, f, copied, enum_type);
        } else {
            let value = cc_to(p, f, argument, p.nodes[parameter].type_id, true);
            cc_relative_check(p, f, value, p.nodes[parameter].type_id, argument);
            f.work[args_start + ordinal] = value;
        }
        ordinal++; argument = p.nodes[argument].next; parameter = p.nodes[parameter].next;
    }
    if argument >= 0 || parameter >= 0 || snapshot < 0 { cc_fail(p, node, "c: dispatch argument arity mismatch"); return -1; }
    let result = cc_temp(p, f, n.type_id); var tag_source = snapshot;
    if (p.types[enum_type].flags & F_VARIABLE_MODE) != 0 { tag_source = original; }
    cc_text(f.out, "switch(g_read_length(g_address("); cc_id(f.out, "g_v", tag_source); cc_text(f.out, "),"); cc_number(f.out, p.types[enum_type].length_storage); cc_text(f.out, ")){\n");
    var arm = n.third;
    while arm >= 0 {
        let selected = p.nodes[arm]; let function = p.symbols[selected.symbol].node;
        let callable = p.symbols[selected.symbol].type_id;
        var dispatch_parameter = p.types[callable].first;
        for i in 0..n.aux { dispatch_parameter = p.nodes[dispatch_parameter].next; }
        let dispatch_type = p.nodes[dispatch_parameter].type_id;
        cc_text(f.out, "case "); cc_number(f.out, selected.integer); cc_text(f.out, ":{\n");
        let payload_ref = cc_ref_temp(f); cc_set(f, payload_ref); cc_text(f.out, "g_offset(");
        if cc_kind(p, dispatch_type) == TY_REF { cc_id(f.out, "g_v", original); }
        else { cc_id(f.out, "g_v", snapshot); }
        cc_text(f.out, ","); cc_number(f.out, p.types[enum_type].length_storage); cc_text(f.out, ");\n");
        var payload = payload_ref;
        if cc_kind(p, dispatch_type) != TY_REF {
            var form = CC_NATIVE; if cc_image_type(p, enum_type) { form = CC_IMAGE; }
            payload = cc_read(p, f, CcPlace { type_id: dispatch_type, address: payload_ref, form: form }, dispatch_type, node);
        } else if !cc_image_type(p, enum_type) && cc_image_type(p, p.types[dispatch_type].element) {
            payload = cc_ref_temp(f); cc_set(f, payload); cc_text(f.out, "g_ref(((GImage*)g_address("); cc_id(f.out, "g_v", payload_ref); cc_text(f.out, "))->base);\n");
        }
        f.work[args_start + n.aux] = payload;
        var closure = -1;
        if p.nodes[function].captures >= 0 { closure = cc_closure(p, f, function, callable); }
        let arm_args = f.work.len; var source_parameter = p.types[signature].first; dispatch_parameter = p.types[callable].first;
        for i in 0..count {
            var value = f.work[args_start + i]; let target_type = p.nodes[dispatch_parameter].type_id; let source_type = p.nodes[source_parameter].type_id;
            if i != n.aux && source_type != target_type {
                if cc_queue_same(p, source_type, target_type) && cc_frame_size(p, source_type) == cc_frame_size(p, target_type) {
                    let adapted = cc_temp(p, f, target_type, true, false);
                    cc_text(f.out, "memcpy(&"); cc_id(f.out, "g_v", adapted); cc_text(f.out, ",&"); cc_id(f.out, "g_v", value); cc_text(f.out, ",sizeof("); cc_type(f.out, target_type); cc_text(f.out, "));\n"); value = adapted;
                } else { value = cc_convert(p, f, value, source_type, target_type, node); }
            }
            f.work.push(value); dispatch_parameter = p.nodes[dispatch_parameter].next; source_parameter = p.nodes[source_parameter].next;
        }
        let natural_type = p.types[callable].element; let natural = cc_result_temp(p, f, node, natural_type);
        var result_channels = -1; if cc_tuple_channels(p, natural_type) { result_channels = cc_temporary_ref(f, natural); }
        if natural >= 0 && !cc_result_indirect(p, natural_type) { cc_set(f, natural); }
        cc_id(f.out, "g_fn", function); cc_text(f.out, "(");
        if closure >= 0 { cc_id(f.out, "g_v", closure); } else { cc_text(f.out, "NULL"); }
        cc_text(f.out, ","); cc_region_argument(f, f.region_live);
        if cc_receives(p, natural_type) {
            if cc_tuple_channels(p, natural_type) { cc_text(f.out, ",(GRef*)g_address("); cc_id(f.out, "g_v", result_channels); cc_text(f.out, ")"); }
            else { cc_text(f.out, ",&"); cc_id(f.out, "g_v", natural); }
        }
        dispatch_parameter = p.types[callable].first;
        for i in 0..count { cc_text(f.out, ","); if cc_indirect(p, p.nodes[dispatch_parameter].type_id) { cc_text(f.out, "&"); } cc_id(f.out, "g_v", f.work[arm_args + i]); dispatch_parameter = p.nodes[dispatch_parameter].next; }
        cc_text(f.out, ");\n"); f.work.resize(arm_args); cc_region_call(f, function, node);
        let adapted = cc_convert(p, f, natural, natural_type, n.type_id, node);
        if result >= 0 && adapted >= 0 { let destination = cc_temporary_ref(f, result); cc_store(p, f, destination, adapted, n.type_id); }
        cc_text(f.out, "break;}\n"); arm = selected.next;
    }
    cc_text(f.out, "default:g_panic(\"corrupt ADT tag\");}\n"); return result;
}

recursive fn cc_freeze_fill(p: Program&, f: CcBody&, node: i64, type_id: i64) {
    if node < 0 || p.nodes[node].kind == N_SELF { return; }
    for entry in f.fills { if entry.node == node { return; } }
    let n = p.nodes[node];
    if cc_relative_fields(p, type_id) {
        if n.kind == N_RECORD {
            var binding = n.first;
            while binding >= 0 {
                let b = p.nodes[binding]; if b.symbol >= 0 { cc_freeze_fill(p, f, b.right, p.nodes[b.symbol].type_id); } binding = b.next;
            }
            return;
        }
        if (n.kind == N_ARRAY || n.kind == N_FILL) && cc_kind(p, type_id) == TY_ARRAY {
            if n.right >= 0 { cc_freeze_fill(p, f, n.right, TYPE_I64); }
            if n.third >= 0 { cc_freeze_fill(p, f, n.third, TYPE_I64); }
            var element = n.first;
            while element >= 0 { cc_freeze_fill(p, f, element, p.types[type_id].element); element = p.nodes[element].next; }
            return;
        }
    }
    var value = cc_to(p, f, node, type_id, true);
    if cc_result_location(p, type_id) {
        let snapshot = cc_temp(p, f, type_id); let target = cc_temporary_ref(f, snapshot); cc_store(p, f, target, value, type_id, node); value = snapshot;
    }
    f.fills.push(CcFill { node: node, type_id: type_id, value: value });
}
fn cc_array_slot(p: Program&, f: CcBody&, base: i64, array: i64, index: i64, literal_index: bool = false) -> i64 {
    let target = cc_ref_temp(f); cc_set(f, target); cc_text(f.out, "g_slot("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_literal_array_args(p, f.out, array);
    cc_text(f.out, ","); if literal_index { cc_number(f.out, index); } else { cc_id(f.out, "g_i", index); } cc_text(f.out, ");\n"); return target;
}
recursive fn cc_image_run_array(p: Program&, f: CcBody&, node: i64) -> i64 {
    let n = p.nodes[node]; let element = p.types[n.type_id].element;
    if !cc_image_constructible(p, element) { cc_fail(p, node, "c: variable element requires a canonical image constructor"); return -1; }
    let result = cc_result_temp(p, f, node, n.type_id); let base = cc_temporary_ref(f, result);
    var length = cc_temp(p, f, TYPE_I64);
    if n.right >= 0 { length = cc_to(p, f, n.right, TYPE_I64); }
    else { var count = 0; var child = n.first; while child >= 0 { count++; child = p.nodes[child].next; } cc_set(f, length); cc_number(f.out, count); cc_text(f.out, ";\n"); }
    if n.third >= 0 { cc_to(p, f, n.third, TYPE_I64); }
    let raw = f.serial; f.serial++;
    cc_id(f.out, "GArray g_run", raw); cc_text(f.out, ";memcpy(&"); cc_id(f.out, "g_run", raw); cc_text(f.out, ",g_address("); cc_id(f.out, "g_v", base); cc_text(f.out, "),sizeof(GArray));g_begin_builder("); cc_id(f.out, "g_v", base); cc_text(f.out, ");\n");
    cc_id(f.out, "GImage g_run_image", raw); cc_text(f.out, "={"); cc_id(f.out, "g_run", raw); cc_text(f.out, ".data,"); cc_id(f.out, "g_run", raw); cc_text(f.out, ".data,"); cc_id(f.out, "g_run", raw); cc_text(f.out, ".region};\n");
    let owner = cc_ref_temp(f); cc_set(f, owner); cc_text(f.out, "g_ref(&"); cc_id(f.out, "g_run_image", raw); cc_text(f.out, ");\n");
    cc_text(f.out, "g_image_commit("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_id(f.out, "g_run", raw); cc_text(f.out, ".region->stack.top,"); cc_id(f.out, "g_v", length); cc_text(f.out, ");\n");
    let mark = f.fills.len;
    if n.right >= 0 {
        if n.first >= 0 && (n.flags & F_DEFAULT) == 0 { cc_freeze_fill(p, f, n.first, element); }
        cc_id(f.out, "for(int64_t g_i", raw); cc_text(f.out, "=0;"); cc_id(f.out, "g_i", raw); cc_text(f.out, "<"); cc_id(f.out, "g_v", length); cc_text(f.out, ";"); cc_id(f.out, "g_i", raw); cc_text(f.out, "++){\n");
        cc_image_field_value(p, f, owner, n.first, element); cc_text(f.out, "}\n");
    } else { var child = n.first; while child >= 0 { cc_image_field_value(p, f, owner, child, element); child = p.nodes[child].next; } }
    f.fills.resize(mark);
    cc_text(f.out, "g_image_commit("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_id(f.out, "g_run", raw); cc_text(f.out, ".region->stack.top,"); cc_id(f.out, "g_v", length); cc_text(f.out, ");\n"); return result;
}
recursive fn cc_array(p: Program&, f: CcBody&, node: i64) -> i64 {
    if cc_image_type(p, p.nodes[node].type_id) { return cc_image_array(p, f, node, p.nodes[node].type_id); }
    if cc_kind(p, p.nodes[node].type_id) == TY_ARRAY && cc_size_class(p, p.types[p.nodes[node].type_id].element) == 1 { return cc_image_run_array(p, f, node); }
    let n = p.nodes[node]; let t = p.types[n.type_id]; let result = cc_result_temp(p, f, node, n.type_id);
    var base: i64 = -1;
    if t.kind == TY_SLICE {
        let raw = f.serial; f.serial++; cc_raw_array(f, "g_array", raw);
        base = cc_ref_temp(f); cc_set(f, base); cc_text(f.out, "g_ref(&"); cc_id(f.out, "g_array", raw); cc_text(f.out, ");\n");
    } else { base = cc_temporary_ref(f, result); }
    var length = -1; var elements = 0; var child = n.first;
    while child >= 0 { elements++; child = p.nodes[child].next; }
    if n.right >= 0 { length = cc_to(p, f, n.right, TYPE_I64); }
    else { length = cc_temp(p, f, TYPE_I64); cc_set(f, length); cc_number(f.out, elements); cc_text(f.out, ";\n"); }
    var capacity = length;
    if n.third >= 0 { capacity = cc_to(p, f, n.third, TYPE_I64); }
    if length < 0 || capacity < 0 { return -1; }
    if cc_owner(p, n.type_id) || t.kind == TY_SLICE {
        cc_text(f.out, "g_reserve("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_literal_array_args(p, f.out, n.type_id); cc_text(f.out, ",");
        cc_id(f.out, "g_v", capacity);
        cc_text(f.out, ");\n");
    }
    if cc_relative_fields(p, t.element) || (n.flags & F_DEFAULT) != 0 && cc_field_defaults(p, t.element) {
        if t.kind == TY_SLICE || t.array_kind != A_FIXED {
            cc_text(f.out, "g_reserve("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_literal_array_args(p, f.out, n.type_id); cc_text(f.out, ","); cc_id(f.out, "g_v", length); cc_text(f.out, ");\n");
        }
        let fill_mark = f.fills.len;
        if n.right >= 0 && n.first >= 0 {
            if (n.flags & F_DEFAULT) == 0 { cc_freeze_fill(p, f, n.first, t.element); }
            let counter = f.serial; f.serial++;
            cc_id(f.out, "for(int64_t g_i", counter); cc_text(f.out, "=0;"); cc_id(f.out, "g_i", counter); cc_text(f.out, "<"); cc_id(f.out, "g_v", length); cc_text(f.out, ";"); cc_id(f.out, "g_i", counter); cc_text(f.out, "++){\n");
            let target = cc_array_slot(p, f, base, n.type_id, counter); cc_construct_into(p, f, n.first, t.element, target); cc_text(f.out, "}\n");
        } else {
            var child = n.first; var index = 0;
            while child >= 0 {
                let target = cc_array_slot(p, f, base, n.type_id, index, true); cc_construct_into(p, f, child, t.element, target); child = p.nodes[child].next; index++;
            }
        }
        f.fills.resize(fill_mark);
        if t.kind == TY_SLICE || t.array_kind != A_FIXED {
            cc_text(f.out, "g_set_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_literal_array_args(p, f.out, n.type_id, false); cc_text(f.out, ","); cc_id(f.out, "g_v", length); cc_text(f.out, ");\n");
        }
        if t.kind == TY_SLICE { cc_set(f, result); cc_text(f.out, "g_view("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_literal_array_args(p, f.out, n.type_id); cc_text(f.out, ");\n"); }
        return result;
    }
    if t.array_kind != A_FIXED {
        cc_text(f.out, "g_set_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_literal_array_args(p, f.out, n.type_id, false); cc_text(f.out, ","); cc_id(f.out, "g_v", length); cc_text(f.out, ");\n");
    }
    if n.right >= 0 && n.first >= 0 {
        let value = cc_to(p, f, n.first, t.element, true); if value < 0 { return -1; }
        if cc_kind(p, t.element) == TY_INT || cc_kind(p, t.element) == TY_BOOL || cc_kind(p, t.element) == TY_FLOAT {
            let initializer = p.nodes[n.first]; let width = cc_frame_size(p, t.element);
            cc_text(f.out, "if("); cc_id(f.out, "g_v", length); cc_text(f.out, ">0){\n");
            let data = f.serial; f.serial++;
            cc_id(f.out, "unsigned char *g_fill", data); cc_text(f.out, "=g_address(g_element("); cc_id(f.out, "g_v", base);
            cc_text(f.out, ","); cc_literal_array_args(p, f.out, n.type_id); cc_text(f.out, ",0,1));\n");
            if (initializer.kind == N_INTEGER || initializer.kind == N_BOOL) && initializer.integer == 0 {
                cc_text(f.out, "memset("); cc_id(f.out, "g_fill", data); cc_text(f.out, ",0,(size_t)"); cc_id(f.out, "g_v", length); cc_text(f.out, "*"); cc_number(f.out, width); cc_text(f.out, ");\n");
            } else {
                cc_id(f.out, "for(int64_t g_i", data); cc_text(f.out, "=0;"); cc_id(f.out, "g_i", data); cc_text(f.out, "<"); cc_id(f.out, "g_v", length);
                cc_text(f.out, ";"); cc_id(f.out, "g_i", data); cc_text(f.out, "++)memcpy("); cc_id(f.out, "g_fill", data); cc_text(f.out, "+"); cc_id(f.out, "g_i", data);
                cc_text(f.out, "*"); cc_number(f.out, width); cc_text(f.out, ",&"); cc_id(f.out, "g_v", value); cc_text(f.out, ","); cc_number(f.out, width); cc_text(f.out, ");\n");
            }
            cc_text(f.out, "}\n");
            if t.kind == TY_SLICE { cc_set(f, result); cc_text(f.out, "g_view("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_literal_array_args(p, f.out, n.type_id); cc_text(f.out, ");\n"); }
            return result;
        }
        let counter = f.serial; f.serial++;
        cc_id(f.out, "for(int64_t g_i", counter); cc_text(f.out, "=0;"); cc_id(f.out, "g_i", counter); cc_text(f.out, "<"); cc_id(f.out, "g_v", length); cc_text(f.out, ";"); cc_id(f.out, "g_i", counter); cc_text(f.out, "++){\n");
        cc_id(f.out, "g_store_", t.element); cc_text(f.out, "(g_element("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_literal_array_args(p, f.out, n.type_id); cc_text(f.out, ","); cc_id(f.out, "g_i", counter); cc_text(f.out, ",0),"); cc_id(f.out, "g_clone_", t.element); cc_text(f.out, "("); cc_id(f.out, "g_v", value); cc_text(f.out, "));}\n");
    } else {
        child = n.first; var index = 0;
        while child >= 0 {
            let value = cc_to(p, f, child, t.element, true);
            if value < 0 { return -1; }
            cc_id(f.out, "g_store_", t.element); cc_text(f.out, "(g_element("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_literal_array_args(p, f.out, n.type_id); cc_text(f.out, ","); cc_number(f.out, index); cc_text(f.out, ",0),"); cc_id(f.out, "g_v", value); cc_text(f.out, ");\n");
            index++; child = p.nodes[child].next;
        }
    }
    if t.kind == TY_SLICE {
        cc_set(f, result); cc_text(f.out, "g_view("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_literal_array_args(p, f.out, n.type_id); cc_text(f.out, ");\n");
    }
    return result;
}
recursive fn cc_image_field_value(p: Program&, f: CcBody&, owner: i64, node: i64, type_id: i64) {
    let temporary_mark = f.region_live;
    if cc_image_type(p, type_id) {
        let raw = f.serial; f.serial++;
        cc_id(f.out, "GRegion *g_field_region", raw); cc_text(f.out, "=((GImage*)g_address("); cc_id(f.out, "g_v", owner); cc_text(f.out, "))->region;\n");
        cc_id(f.out, "GImage g_field", raw); cc_text(f.out, "={"); cc_id(f.out, "g_field_region", raw); cc_text(f.out, "->stack.top,"); cc_id(f.out, "g_field_region", raw); cc_text(f.out, "->stack.top,"); cc_id(f.out, "g_field_region", raw); cc_text(f.out, "};\n");
        let destination = cc_ref_temp(f); cc_set(f, destination); cc_text(f.out, "g_ref(&"); cc_id(f.out, "g_field", raw); cc_text(f.out, ");\n");
        cc_construct_into(p, f, node, type_id, destination);
        if !cc_frame_borrows(p, type_id) { cc_restore(f, temporary_mark); f.region_live = temporary_mark; } return;
    }
    if cc_result_location(p, type_id) && cc_fixed_storage(p, type_id) {
        let target = cc_ref_temp(f); cc_set(f, target); cc_text(f.out, "g_ref(g_image_space(((GImage*)g_address("); cc_id(f.out, "g_v", owner); cc_text(f.out, "))->region,"); cc_number(f.out, p.types[type_id].size); cc_text(f.out, "));\n");
        if node >= 0 { cc_construct_into(p, f, node, type_id, target); }
        else { let value = cc_default(p, f, type_id); cc_store(p, f, target, value, type_id); }
        cc_text(f.out, "g_image_advance(((GImage*)g_address("); cc_id(f.out, "g_v", owner); cc_text(f.out, "))->region,g_address("); cc_id(f.out, "g_v", target); cc_text(f.out, ")+"); cc_number(f.out, p.types[type_id].size); cc_text(f.out, ");\n");
        if !cc_frame_borrows(p, type_id) { cc_restore(f, temporary_mark); f.region_live = temporary_mark; } return;
    }
    var value = -1;
    if node >= 0 { value = cc_to(p, f, node, type_id); } else { value = cc_default(p, f, type_id); }
    cc_image_put_value(p, f, owner, value, type_id, node);
    if !cc_frame_borrows(p, type_id) { cc_restore(f, temporary_mark); f.region_live = temporary_mark; }
}
fn cc_image_put_value(p: Program&, f: CcBody&, owner: i64, value: i64, type_id: i64, node: i64) {
    if value < 0 { if node >= 0 && cc_diverges(p, node) { return; } cc_fail(p, node, "c: image field has no value"); return; }
    let cursor = f.serial; f.serial++;
    cc_id(f.out, "GImage *g_image_owner", cursor); cc_text(f.out, "=(GImage*)g_address("); cc_id(f.out, "g_v", owner); cc_text(f.out, ");\n");
    cc_id(f.out, "uint8_t *g_image_cursor", cursor); cc_text(f.out, "=g_image_space("); cc_id(f.out, "g_image_owner", cursor); cc_text(f.out, "->region,");
    if cc_relative_cell(p, type_id) {
        let width = p.types[type_id].length_storage; cc_number(f.out, width); cc_text(f.out, ");\n");
        cc_text(f.out, "g_relative_store(g_ref("); cc_id(f.out, "g_image_cursor", cursor); cc_text(f.out, "),"); cc_id(f.out, "g_v", value); cc_text(f.out, ","); cc_number(f.out, width); cc_text(f.out, ",");
        if (p.types[type_id].flags & TF_OPTIONAL) != 0 { cc_text(f.out, "1"); } else { cc_text(f.out, "0"); }
        cc_text(f.out, ","); cc_relative_origin(p, f.out, type_id); cc_text(f.out, ","); var location = node; if location < 0 { location = f.function; } cc_location(p, f.out, location); cc_text(f.out, ");g_image_advance("); cc_id(f.out, "g_image_owner", cursor); cc_text(f.out, "->region,"); cc_id(f.out, "g_image_cursor", cursor); cc_text(f.out, "+"); cc_number(f.out, width); cc_text(f.out, ");\n"); return;
    }
    let fixed = cc_size_class(p, type_id) == 0 && cc_frame_size(p, type_id) == p.types[type_id].size && cc_region_width(p, type_id) == 0;
    if fixed { cc_number(f.out, p.types[type_id].size); cc_text(f.out, ");\n"); }
    else { cc_id(f.out, "g_image_size_", type_id); cc_text(f.out, "(g_ref(&"); cc_id(f.out, "g_v", value); cc_text(f.out, ")));\n"); }
    if fixed {
        cc_text(f.out, "memcpy("); cc_id(f.out, "g_image_cursor", cursor); cc_text(f.out, ",&"); cc_id(f.out, "g_v", value); cc_text(f.out, ","); cc_number(f.out, p.types[type_id].size); cc_text(f.out, ");g_image_advance("); cc_id(f.out, "g_image_owner", cursor); cc_text(f.out, "->region,"); cc_id(f.out, "g_image_cursor", cursor); cc_text(f.out, "+"); cc_number(f.out, p.types[type_id].size); cc_text(f.out, ");\n"); return;
    }
    cc_text(f.out, "g_image_advance("); cc_id(f.out, "g_image_owner", cursor); cc_text(f.out, "->region,"); cc_id(f.out, "g_image_write_", type_id); cc_text(f.out, "("); cc_id(f.out, "g_image_cursor", cursor); cc_text(f.out, ",g_ref(&"); cc_id(f.out, "g_v", value); cc_text(f.out, ")));\n");
}
fn cc_image_padding(f: CcBody&, owner: i64, bytes: i64) {
    if bytes <= 0 { return; } let cursor = f.serial; f.serial++;
    cc_id(f.out, "GRegion *g_pad_region", cursor); cc_text(f.out, "=((GImage*)g_address("); cc_id(f.out, "g_v", owner); cc_text(f.out, "))->region;\n");
    cc_id(f.out, "uint8_t *g_pad", cursor); cc_text(f.out, "=g_image_space("); cc_id(f.out, "g_pad_region", cursor); cc_text(f.out, ","); cc_number(f.out, bytes); cc_text(f.out, ");memset("); cc_id(f.out, "g_pad", cursor); cc_text(f.out, ",0,"); cc_number(f.out, bytes); cc_text(f.out, ");g_image_advance("); cc_id(f.out, "g_pad_region", cursor); cc_text(f.out, ","); cc_id(f.out, "g_pad", cursor); cc_text(f.out, "+"); cc_number(f.out, bytes); cc_text(f.out, ");\n");
}
recursive fn cc_image_array(p: Program&, f: CcBody&, node: i64, type_id: i64) -> i64 {
    if !cc_image_constructible(p, type_id) { cc_fail(p, node, "c: array element requires a canonical image constructor"); return -1; }
    let result = cc_result_temp(p, f, node, type_id); let owner = cc_temporary_ref(f, result); let raw = f.serial; f.serial++;
    var count = cc_temp(p, f, TYPE_I64); var first = -1; var fill = false;
    if node >= 0 {
        let n = p.nodes[node]; first = n.first; fill = n.right >= 0;
        if n.kind == N_STRING { cc_set(f, count); cc_number(f.out, p.tokens[n.token].text_len); cc_text(f.out, ";\n"); }
        else if n.right >= 0 { count = cc_to(p, f, n.right, TYPE_I64); }
        else { var length = 0; var child = n.first; while child >= 0 { length++; child = p.nodes[child].next; } cc_set(f, count); cc_number(f.out, length); cc_text(f.out, ";\n"); }
    }
    cc_id(f.out, "GImage *g_array_image", raw); cc_text(f.out, "=(GImage*)g_address("); cc_id(f.out, "g_v", owner); cc_text(f.out, ");\n");
    var capacity = count;
    if node >= 0 && p.nodes[node].third >= 0 { capacity = cc_to(p, f, p.nodes[node].third, TYPE_I64); }
    cc_text(f.out, "g_image_array_begin("); cc_id(f.out, "g_v", owner); cc_text(f.out, ","); cc_number(f.out, cc_array_kind(p, type_id)); cc_text(f.out, ","); cc_number(f.out, cc_prefix(p, type_id)); cc_text(f.out, ","); cc_id(f.out, "g_v", count); cc_text(f.out, ","); cc_id(f.out, "g_v", capacity); cc_text(f.out, ","); cc_number(f.out, p.types[p.types[type_id].element].size); cc_text(f.out, ");\n");
    if node >= 0 && p.nodes[node].kind == N_STRING {
        let token = p.tokens[p.nodes[node].token];
        cc_text(f.out, "memcpy(g_image_space("); cc_id(f.out, "g_array_image", raw); cc_text(f.out, "->region,"); cc_number(f.out, token.text_len); cc_text(f.out, "),"); cc_bytes(f.out, p.text[token.text_start..token.text_start + token.text_len]); cc_text(f.out, ","); cc_number(f.out, token.text_len); cc_text(f.out, ");g_image_advance("); cc_id(f.out, "g_array_image", raw); cc_text(f.out, "->region,"); cc_id(f.out, "g_array_image", raw); cc_text(f.out, "->region->stack.top+"); cc_number(f.out, token.text_len); cc_text(f.out, ");\n");
    } else if fill {
        let mark = f.fills.len;
        if first >= 0 && (p.nodes[node].flags & F_DEFAULT) == 0 { cc_freeze_fill(p, f, first, p.types[type_id].element); }
        cc_id(f.out, "for(int64_t g_i", raw); cc_text(f.out, "=0;"); cc_id(f.out, "g_i", raw); cc_text(f.out, "<"); cc_id(f.out, "g_v", count); cc_text(f.out, ";"); cc_id(f.out, "g_i", raw); cc_text(f.out, "++){\n");
        cc_image_field_value(p, f, owner, first, p.types[type_id].element); cc_text(f.out, "}\n"); f.fills.resize(mark);
    } else {
        var child = first; while child >= 0 { cc_image_field_value(p, f, owner, child, p.types[type_id].element); child = p.nodes[child].next; }
    }
    cc_text(f.out, "g_image_array_finish("); cc_id(f.out, "g_v", owner); cc_text(f.out, ","); cc_number(f.out, cc_array_kind(p, type_id)); cc_text(f.out, ","); cc_id(f.out, "g_v", capacity); cc_text(f.out, ","); cc_number(f.out, p.types[p.types[type_id].element].size); cc_text(f.out, ");\n"); return result;
}
recursive fn cc_flat_image_record(p: Program&, f: CcBody&, node: i64, type_id: i64) -> i64 {
    let result = cc_result_temp(p, f, node, type_id); let owner = cc_temporary_ref(f, result);
    let start = f.work.len; let regions = f.region_live; var binding = -1;
    if node >= 0 { binding = p.nodes[node].first; }
    var field = p.nodes[p.types[type_id].declaration].first;
    while field >= 0 { let n = p.nodes[field]; if (n.flags & F_PAD) == 0 { f.work.push(-1); } field = n.next; }
    field = p.nodes[p.types[type_id].declaration].first; var staged = start;
    while field >= 0 {
        let current = field; let n = p.nodes[field]; field = n.next;
        if (n.flags & F_PAD) != 0 { continue; }
        var initializer = n.right;
        if binding >= 0 {
            if p.nodes[binding].symbol != current { cc_fail(p, node, "c: image initializer is not in declaration order"); return -1; }
            initializer = p.nodes[binding].right; binding = p.nodes[binding].next;
        }
        var value = -1;
        if initializer >= 0 { value = cc_to(p, f, initializer, n.type_id); } else { value = cc_default(p, f, n.type_id); }
        if cc_relative_cell(p, n.type_id) {
            let encoded = f.serial; f.serial++; cc_storage_type(p, f.out, n.type_id); cc_id(f.out, " g_v", encoded); cc_text(f.out, "={0};\n");
            let target = cc_temporary_ref(f, encoded); cc_store(p, f, target, value, n.type_id, initializer); value = encoded;
        }
        f.work[staged] = value; staged++;
    }
    let raw = f.serial; f.serial++;
    cc_id(f.out, "GImage *g_flat", raw); cc_text(f.out, "=(GImage*)g_address("); cc_id(f.out, "g_v", owner); cc_text(f.out, ");\n");
    cc_id(f.out, "g_flat", raw); cc_text(f.out, "->region->stack.top="); cc_id(f.out, "g_flat", raw); cc_text(f.out, "->base;\n");
    field = p.nodes[p.types[type_id].declaration].first; var ordinal = start;
    while field >= 0 {
        let n = p.nodes[field]; field = n.next;
        if (n.flags & F_PAD) != 0 { cc_image_padding(f, owner, n.aux); continue; }
        let value = f.work[ordinal]; ordinal++;
        if cc_relative_cell(p, n.type_id) {
            let width = p.types[n.type_id].length_storage; let cursor = cc_ref_temp(f);
            cc_set(f, cursor); cc_text(f.out, "g_ref(g_image_space("); cc_id(f.out, "g_flat", raw); cc_text(f.out, "->region,");
            if width == 0 { cc_id(f.out, "g_v", value); cc_text(f.out, ".extent"); } else { cc_number(f.out, width); } cc_text(f.out, "));\n");
            cc_text(f.out, "memcpy(g_address("); cc_id(f.out, "g_v", cursor); cc_text(f.out, "),");
            if width == 0 { cc_id(f.out, "g_v", value); cc_text(f.out, ".bytes,"); cc_id(f.out, "g_v", value); cc_text(f.out, ".extent"); }
            else { cc_text(f.out, "&"); cc_id(f.out, "g_v", value); cc_text(f.out, ","); cc_number(f.out, width); }
            cc_text(f.out, ");g_image_advance("); cc_id(f.out, "g_flat", raw); cc_text(f.out, "->region,g_address("); cc_id(f.out, "g_v", cursor); cc_text(f.out, ")+");
            if width == 0 { cc_id(f.out, "g_v", value); cc_text(f.out, ".extent"); } else { cc_number(f.out, width); } cc_text(f.out, ");\n");
        } else { cc_image_put_value(p, f, owner, value, n.type_id, node); }
    }
    cc_text(f.out, "g_image_finish("); cc_id(f.out, "g_v", owner); cc_text(f.out, ","); cc_id(f.out, "g_flat", raw); cc_text(f.out, "->region->stack.top);\n");
    cc_restore(f, regions); f.region_live = regions; f.work.resize(start); return result;
}
recursive fn cc_image_record(p: Program&, f: CcBody&, node: i64, type_id: i64) -> i64 {
    if cc_flat_relative_image(p, type_id) { return cc_flat_image_record(p, f, node, type_id); }
    if !cc_image_constructible(p, type_id) { cc_fail(p, node, "c: variable image fields require canonical array/reference cursors"); return -1; }
    let result = cc_result_temp(p, f, node, type_id); let owner = cc_temporary_ref(f, result);
    let raw = f.serial; f.serial++;
    cc_id(f.out, "GImage *g_image_root", raw); cc_text(f.out, "=(GImage*)g_address("); cc_id(f.out, "g_v", owner); cc_text(f.out, ");\n");
    cc_id(f.out, "g_image_root", raw); cc_text(f.out, "->region->stack.top="); cc_id(f.out, "g_image_root", raw); cc_text(f.out, "->base;\n");
    var record_type = type_id; var binding = -1;
    if node >= 0 { binding = p.nodes[node].first; }
    if cc_kind(p, type_id) == TY_ENUM {
        var variant = p.nodes[p.types[type_id].declaration].first;
        if node >= 0 { variant = p.nodes[node].symbol; }
        record_type = p.nodes[variant].type_id;
        let width = p.types[type_id].length_storage;
        cc_text(f.out, "g_write_length(g_image_space("); cc_id(f.out, "g_image_root", raw); cc_text(f.out, "->region,"); cc_number(f.out, width); cc_text(f.out, "),"); cc_number(f.out, width); cc_text(f.out, ","); cc_number(f.out, p.nodes[variant].integer); cc_text(f.out, ");g_image_advance("); cc_id(f.out, "g_image_root", raw); cc_text(f.out, "->region,"); cc_id(f.out, "g_image_root", raw); cc_text(f.out, "->base+"); cc_number(f.out, width); cc_text(f.out, ");\n");
    }
    var field = p.nodes[p.types[record_type].declaration].first;
    while field >= 0 {
        let n = p.nodes[field];
        if (n.flags & F_PAD) != 0 { cc_image_padding(f, owner, n.aux); }
        else {
            var initializer = n.right;
            if binding >= 0 {
                if p.nodes[binding].symbol != field { cc_fail(p, node, "c: image initializer is not in declaration order"); return -1; }
                initializer = p.nodes[binding].right; binding = p.nodes[binding].next;
            }
            cc_image_field_value(p, f, owner, initializer, n.type_id);
        }
        field = n.next;
    }
    cc_text(f.out, "g_image_finish("); cc_id(f.out, "g_v", owner); cc_text(f.out, ","); cc_id(f.out, "g_image_root", raw); cc_text(f.out, "->region->stack.top);\n");
    return result;
}
recursive fn cc_record(p: Program&, f: CcBody&, node: i64) -> i64 {
    if cc_image_type(p, p.nodes[node].type_id) { return cc_image_record(p, f, node, p.nodes[node].type_id); }
    let n = p.nodes[node]; let result = cc_result_temp(p, f, node, n.type_id); var base = cc_temporary_ref(f, result); let literal_start = base;
    if cc_kind(p, n.type_id) == TY_ENUM && n.symbol >= 0 && p.nodes[n.symbol].kind == N_VARIANT {
        let tag_bytes = p.types[n.type_id].length_storage;
        cc_text(f.out, "g_write_length(g_address("); cc_id(f.out, "g_v", base); cc_text(f.out, "),");
        cc_number(f.out, tag_bytes); cc_text(f.out, ","); cc_number(f.out, p.nodes[n.symbol].integer); cc_text(f.out, ");\n");
        if cc_region_width(p, n.type_id) > 0 {
            cc_id(f.out, "g_init_", n.type_id); cc_text(f.out, "(g_ref(&"); cc_id(f.out, "g_v", result); cc_text(f.out, "),");
            cc_region_argument(f, f.temp_regions[result]); cc_text(f.out, ");\n");
        }
        let payload = cc_ref_temp(f); cc_set(f, payload); cc_text(f.out, "g_offset("); cc_id(f.out, "g_v", base);
        cc_text(f.out, ","); cc_number(f.out, tag_bytes); cc_text(f.out, ");\n"); base = payload;
    }
    var record_type = n.type_id;
    if cc_kind(p, record_type) == TY_ENUM && n.symbol >= 0 { record_type = p.nodes[n.symbol].type_id; }
    var binding = n.first;
    while binding >= 0 {
        let field = p.nodes[binding].symbol;
        if field < 0 { cc_fail(p, binding, "c: record initializer lacks a checked field"); return -1; }
        let type_id = p.nodes[field].type_id; let initializer = p.nodes[binding].right;
        let ref = cc_ref_temp(f); cc_set(f, ref); cc_text(f.out, "g_offset("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_number(f.out, cc_field_offset(p, record_type, field)); cc_text(f.out, ");\n");
        if initializer >= 0 && p.nodes[initializer].kind == N_SELF {
            var owner = base;
            if cc_kind(p, n.type_id) == TY_ENUM && p.types[p.nodes[initializer].aux].declaration == p.types[n.type_id].declaration { owner = literal_start; }
            cc_store(p, f, ref, owner, type_id, binding);
        } else if initializer >= 0 && cc_result_location(p, type_id) { cc_construct_into(p, f, initializer, type_id, ref); }
        else {
            var value = -1; if initializer >= 0 { value = cc_to(p, f, initializer, type_id, true); } else { value = cc_default(p, f, type_id); }
            if value < 0 { return -1; } cc_store(p, f, ref, value, type_id, binding);
        }
        binding = p.nodes[binding].next;
    }
    return result;
}
recursive fn cc_variable(p: Program&, f: CcBody&, node: i64) {
    let n = p.nodes[node];
    if n.first < 0 {
        if n.symbol >= 0 && (p.symbols[n.symbol].flags & S_GLOBAL) == 0 { cc_seed_symbol(p, f, n.symbol); }
        let type_id = p.symbols[n.symbol].type_id; let keep = f.region_live;
        let destination = cc_symbol_ref(p, f, n.symbol, node); var value: i64 = -1;
        if n.right >= 0 && (cc_region_width(p, type_id) > 0 || cc_result_location(p, type_id)) { cc_construct_into(p, f, n.right, type_id, destination); }
        else {
            if n.right >= 0 { value = cc_to(p, f, n.right, type_id, true); }
            else { value = cc_default(p, f, type_id); }
            cc_store(p, f, destination, value, type_id, node);
        }
        if !cc_frame_borrows(p, type_id) { cc_restore(f, keep); f.region_live = keep; }
        return;
    }
    var seed_binding = n.first;
    while seed_binding >= 0 {
        let symbol = p.nodes[seed_binding].symbol;
        if symbol >= 0 && (p.symbols[symbol].flags & S_GLOBAL) == 0 { cc_seed_symbol(p, f, symbol); }
        seed_binding = p.nodes[seed_binding].next;
    }
    let keep = f.region_live; var borrowed = false;
    let values_start = f.work.len; var values_count = 0; var current = n.right;
    while current >= 0 { f.work.push(-1); f.work.push(-1); values_count++; current = p.nodes[current].next; }
    let receiving_mark = f.receiving.len;
    if values_count == 1 && cc_kind(p, p.nodes[n.right].type_id) == TY_TUPLE {
        var binding = n.first; var field = p.types[p.nodes[n.right].type_id].first; var index = 0;
        while binding >= 0 && field >= 0 {
            let type_id = p.symbols[p.nodes[binding].symbol].type_id;
            if cc_receives(p, type_id) && cc_queue_same(p, type_id, p.nodes[field].type_id) {
                let target = cc_symbol_ref(p, f, p.nodes[binding].symbol, binding); let destination = f.destinations.len;
                f.destinations.push(CcDestination { type_id: type_id, header: target, stack: -1, lifetime: 2 });
                f.receiving.push(CcReceiving { ordinal: index, destination: destination, call: n.right });
            }
            binding = p.nodes[binding].next; field = p.nodes[field].next; index++;
        }
    }
    current = n.right; var ordinal = 0;
    while current >= 0 {
        let value = cc_expr(p, f, current); f.work[values_start + ordinal * 2] = value;
        f.work[values_start + ordinal * 2 + 1] = p.nodes[current].type_id;
        ordinal++; current = p.nodes[current].next;
    }
    f.receiving.resize(receiving_mark);
    var binding = n.first; var index = 0;
    while binding >= 0 {
        let bn = p.nodes[binding]; let destination = cc_symbol_ref(p, f, bn.symbol, binding); let type_id = p.symbols[bn.symbol].type_id;
        if values_count == 1 && cc_kind(p, f.work[values_start + (0) * 2 + 1]) == TY_TUPLE {
            var field = p.types[f.work[values_start + 1]].first; for ordinal in 0..index { field = p.nodes[field].next; }
            let natural_type = p.nodes[field].type_id;
            let value = cc_tuple_value(p, f, f.work[values_start], f.work[values_start + 1], index);
            let adapted = cc_convert(p, f, value, natural_type, type_id, binding, true); cc_store(p, f, destination, adapted, type_id);
        } else if index < values_count {
            let value = cc_convert(p, f, f.work[values_start + (index) * 2], f.work[values_start + (index) * 2 + 1], type_id, binding, true); cc_store(p, f, destination, value, type_id);
        } else { let value = cc_default(p, f, type_id); cc_store(p, f, destination, value, type_id); }
        if cc_frame_borrows(p, type_id) { borrowed = true; }
        index++; binding = bn.next;
    }
    if !borrowed { cc_restore(f, keep); f.region_live = keep; }
}
recursive fn cc_assignment(p: Program&, f: CcBody&, node: i64) {
    let n = p.nodes[node];
    if n.kind == N_MULTI_ASSIGN {
        let value = cc_expr(p, f, n.right);
        if value < 0 { if !cc_diverges(p, n.right) { cc_fail(p, n.right, "c: multiple assignment has no natural values"); } return; }
        var target = n.first; var index = 0;
        while target >= 0 {
            var actual_type = p.nodes[target].type_id; while cc_kind(p, actual_type) == TY_REF { actual_type = p.types[actual_type].element; }
            if cc_kind(p, actual_type) == TY_ARRAY && p.types[actual_type].array_kind == A_LIMITED && p.types[actual_type].count < 0 {
                let place = cc_base_place(p, f, target); let part = cc_tuple_value(p, f, value, p.nodes[n.right].type_id, index);
                var field = p.types[p.nodes[n.right].type_id].first; for ordinal in 0..index { field = p.nodes[field].next; }
                let adapted = cc_convert(p, f, part, p.nodes[field].type_id, actual_type, target);
                cc_text(f.out, "g_image_limited_assign("); cc_id(f.out, "g_v", place.address); cc_text(f.out, ","); cc_id(f.out, "g_v", adapted); cc_text(f.out, ","); cc_number(f.out, p.types[p.types[actual_type].element].size); cc_text(f.out, ");\n");
                index++; target = p.nodes[target].next; continue;
            }
            var type_id = p.nodes[target].type_id; var ref = cc_place(p, f, target);
            if cc_kind(p, type_id) == TY_REF { ref = cc_expr(p, f, target); type_id = p.types[type_id].element; }
            let part = cc_tuple_value(p, f, value, p.nodes[n.right].type_id, index); cc_store(p, f, ref, part, type_id);
            index++; target = p.nodes[target].next;
        }
        return;
    }
    if n.integer == T_ASSIGN {
        var type_id = p.nodes[n.left].type_id; while cc_kind(p, type_id) == TY_REF { type_id = p.types[type_id].element; }
        if cc_kind(p, type_id) == TY_ARRAY && p.types[type_id].array_kind == A_LIMITED && p.types[type_id].count < 0 {
            let place = cc_base_place(p, f, n.left); let value = cc_to(p, f, n.right, type_id);
            if value >= 0 {
                cc_text(f.out, "g_image_limited_assign("); cc_id(f.out, "g_v", place.address); cc_text(f.out, ","); cc_id(f.out, "g_v", value); cc_text(f.out, ","); cc_number(f.out, p.types[p.types[type_id].element].size); cc_text(f.out, ");\n");
            }
            return;
        }
    }
    var type_id = p.nodes[n.left].type_id; var ref = cc_place(p, f, n.left);
    if n.integer == T_DOTASSIGN { type_id = cc_place_type(p, n.left); }
    if n.integer != T_DOTASSIGN && cc_kind(p, type_id) == TY_REF { ref = cc_expr(p, f, n.left); type_id = p.types[type_id].element; }
    if n.integer == T_ASSIGN || n.integer == T_DOTASSIGN {
        if cc_result_location(p, type_id) { cc_construct_into(p, f, n.right, type_id, ref); return; }
        let value = cc_to(p, f, n.right, type_id, true); cc_store(p, f, ref, value, type_id, node); return;
    }
    let old = cc_load(p, f, ref, type_id); var right: i64 = -1; var op = n.integer;
    if op == T_INC || op == T_DEC {
        right = cc_temp(p, f, type_id); cc_set(f, right); cc_text(f.out, "1;\n");
        if op == T_INC { op = T_PLUS; } else { op = T_MINUS; }
    } else {
        right = cc_to(p, f, n.right, type_id);
        if op == T_PLUSEQ { op = T_PLUS; } else if op == T_MINUSEQ { op = T_MINUS; }
        else if op == T_MULEQ { op = T_MUL; } else if op == T_DIVEQ { op = T_DIV; }
        else if op == T_MODEQ { op = T_MOD; } else if op == T_ANDEQ { op = T_BITAND; }
        else if op == T_OREQ { op = T_BITOR; } else if op == T_XOREQ { op = T_XOR; }
        else if op == T_SHLEQ { op = T_SHL; } else if op == T_SHREQ { op = T_SHR; }
    }
    let value = cc_binary_values(p, f, op, old, right, type_id, type_id, node); cc_store(p, f, ref, value, type_id);
}
recursive fn cc_zero_receive(p: Program&, f: CcBody&, type_id: i64, target: i64) {
    let t = p.types[type_id];
    if cc_image_type(p, type_id) {
        f.out.format("g_image_zero(g_v", target, ",", ci_zero_bytes(p, type_id), ");\n"); return;
    }
    if cc_region_width(p, type_id) == 0 {
        f.out.format("memset(g_address(g_v", target, "),0,", cc_frame_size(p, type_id), ");\n"); return;
    }
    if cc_owner(p, type_id) { f.out.format("g_begin_builder(g_v", target, ");\n"); return; }
    if t.kind == TY_ENUM {
        let raw = f.serial; f.serial++;
        f.out.format("GRegion *g_zero_region", raw, "=((g_t", type_id, "*)g_address(g_v", target, "))->region;\n",
            "memset(g_address(g_v", target, "),0,", cc_frame_size(p, type_id) - 8, ");g_init_", type_id, "(g_v", target, ",g_zero_region", raw, "-g_regions);\n");
        let payload = cc_ref_temp(f); cc_set(f, payload); f.out.format("g_offset(g_v", target, ",", t.length_storage, ");\n");
        cc_zero_receive(p, f, p.nodes[p.nodes[t.declaration].first].type_id, payload); return;
    }
    var field = t.first; if t.kind == TY_STRUCT { field = p.nodes[t.declaration].first; } var ordinal = 0;
    while field >= 0 {
        let n = p.nodes[field]; let address = cc_ref_temp(f); cc_set(f, address);
        f.out.format("g_offset(g_v", target, ",");
        if t.kind == TY_TUPLE { f.out.format("offsetof(g_t", type_id, ",f", ordinal, ")"); }
        else { cc_number(f.out, cc_field_offset(p, type_id, field)); } cc_text(f.out, ");\n");
        if (n.flags & F_PAD) == 0 { cc_zero_receive(p, f, n.type_id, address); ordinal++; }
        else if n.aux > 0 { f.out.format("memset(g_address(g_v", address, "),0,", n.aux, ");\n"); }
        field = n.next;
    }
}
recursive fn cc_thread_builtin(p: Program&, f: CcBody&, node: i64, builtin: i64, args_start: i64, args_count: i64) -> i64 {
    let n = p.nodes[node];
    if builtin == 7 || builtin == 8 {
        let worker = p.symbols[p.nodes[f.work[args_start]].symbol].node;
        let packet = f.serial; f.serial++; cc_raw_array(f, "g_packet", packet);
        var formal = p.nodes[worker].first; var ordinal = 1;
        while formal >= 0 && ordinal < args_count {
            let type_id = p.nodes[formal].type_id; let value = cc_to(p, f, f.work[args_start + ordinal], type_id); var image = value;
            if cc_relative_cell(p, type_id) {
                image = f.serial; f.serial++; cc_storage_type(p, f.out, type_id); cc_text(f.out, " "); cc_id(f.out, "g_v", image); cc_text(f.out, "={0};\n");
                let cell = cc_temporary_ref(f, image); cc_store(p, f, cell, value, type_id, f.work[args_start + ordinal]);
            }
            cc_thread_emit_image(f.out, type_id, image, packet);
            formal = p.nodes[formal].next; ordinal++;
        }
        cc_thread_emit_global_images(p, f.out, worker, packet);
        let result = cc_temp(p, f, n.type_id); cc_set(f, result);
        f.out.format("g_worker_start(g_worker_", worker, ",g_packet", packet, ".data,g_packet", packet, ".len,");
        if builtin == 8 { f.out.append("1"); } else { f.out.append("0"); } f.out.append(");\n"); return result;
    }
    if builtin == 9 {
        let id = cc_to(p, f, f.work[args_start], TYPE_I64); let result = cc_temp(p, f, n.type_id);
        if args_count == 1 {
            cc_set(f, result); f.out.format("gs_thread_wait(g_v", id, ",NULL,NULL,"); cc_location(p, f.out, node); f.out.append(");\n"); return result;
        }
        let message = f.serial; f.serial++; f.out.format("uint8_t *g_message", message, "=NULL;int64_t g_message_bytes", message, "=0;\n");
        cc_set(f, result); f.out.format("gs_thread_wait(g_v", id, ",&g_message", message, ",&g_message_bytes", message, ","); cc_location(p, f.out, node); f.out.append(");\n");
        f.out.format("if(g_message", message, "){\n");
        let copied = f.serial; f.serial++; cc_raw_array(f, "g_wait_image", copied);
        f.out.format("g_transfer_hold(g_message", message, ");g_bytes(&g_wait_image", copied, ",g_message", message, ",g_message_bytes", message, ");g_transfer_drop();\n");
        let receiver = f.work[args_start + 1]; var type_id = p.nodes[receiver].type_id;
        while cc_kind(p, type_id) == TY_REF { type_id = p.types[type_id].element; }
        let target = cc_base(p, f, receiver);
        f.out.format("g_append_bytes(g_v", target, ","); cc_array_args(p, f.out, type_id, false);
        f.out.format(",g_wait_image", copied, ".data,g_wait_image", copied, ".len);}\n"); return result;
    }
    let type_id = cc_queue_type(p, node); let queue = cc_queue_key(p, type_id);
    if builtin == 10 {
        let value = cc_to(p, f, f.work[args_start], type_id); let packet = f.serial; f.serial++; cc_raw_array(f, "g_queue_image", packet);
        let size = f.serial; f.serial++;
        f.out.format("int64_t g_image_bytes", size, "=g_image_size_", type_id, "(g_ref(&g_v", value, "));\n",
            "g_reserve(g_ref(&g_queue_image", packet, "),3,-1,0,1,g_image_bytes", size, ");\n",
            "g_image_write_", type_id, "(g_queue_image", packet, ".data,g_ref(&g_v", value, "));\n");
        let result = cc_temp(p, f, n.type_id); cc_set(f, result);
        f.out.format("gs_qput(&g_queue_", queue, ",g_queue_image", packet, ".data,g_image_bytes", size, ");\n"); return result;
    }
    if builtin == 13 {
        let limit = cc_to(p, f, f.work[args_start], TYPE_I64);
        f.out.format("gs_qlimit(&g_queue_", queue, ",g_v", limit, ","); cc_location(p, f.out, node); f.out.append(");\n"); return -1;
    }
    let pair = builtin == 12 || args_count > 0;
    var timeout = -1; if args_count > 0 { timeout = cc_to(p, f, f.work[args_start], TYPE_I64); }
    let result = cc_result_temp(p, f, node, n.type_id); let message = f.serial; f.serial++;
    var target = cc_temporary_ref(f, result); var present = -1;
    if pair { present = cc_channel_target(p, f, target, n.type_id, 1); target = cc_channel_target(p, f, target, n.type_id, 0); }
    f.out.format("gs_qnode *g_node", message, "=");
    if builtin == 12 { f.out.format("gs_qpoll(&g_queue_", queue, ");\n"); }
    else if timeout >= 0 { f.out.format("gs_qwait(&g_queue_", queue, ",g_v", timeout, ");\n"); }
    else { f.out.format("gs_qget(&g_queue_", queue, ");\n"); }
    if pair { f.out.format("*(uint8_t*)g_address(g_v", present, ")=(g_node", message, "!=NULL);\n"); }
    f.out.format("if(g_node", message, "){g_transfer_hold(g_node", message, ");\n");
    let slot = cc_region_slot(f, 1);
    f.out.format("g_image_read_", type_id, "(g_v", target, ",(const uint8_t*)(g_node", message, "+1),"); cc_region_argument(f, slot);
    f.out.append(");g_transfer_drop();}");
    if pair { cc_text(f.out, "else {\n"); cc_zero_receive(p, f, type_id, target); cc_text(f.out, "}"); }
    cc_text(f.out, "\n"); return result;
}
recursive fn cc_truth(p: Program&, f: CcBody&, node: i64) -> i64 {
    let mark = f.region_live; let value = cc_to(p, f, node, TYPE_BOOL);
    cc_restore(f, mark); f.region_live = mark; return value;
}
fn cc_slice_type(p: Program&, element: i64) -> i64 {
    for t, id in p.types { if t.kind == TY_SLICE && t.element == element { return id; } } return -1;
}
recursive fn cc_pool_builtin(p: Program&, f: CcBody&, node: i64, builtin: i64, args: i64, base: i64, type_id: i64) -> i64 {
    let n = p.nodes[node]; let element = p.types[type_id].element; let width = cc_frame_size(p, element);
    if builtin == 30 || builtin == 31 {
        var value = -1; if !cc_result_location(p, element) { value = cc_to(p, f, f.work[args + 1], element, true); }
        let index = cc_temp(p, f, TYPE_I64); cc_set(f, index); cc_text(f.out, "g_pool_take("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_number(f.out, width); cc_text(f.out, ");\n");
        let target = cc_ref_temp(f); cc_set(f, target); cc_text(f.out, "g_moving("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_id(f.out, "g_v", index); cc_text(f.out, "*"); cc_number(f.out, width); cc_text(f.out, ");\n");
        if cc_result_location(p, element) { cc_construct_into(p, f, f.work[args + 1], element, target); }
        else { cc_store(p, f, target, value, element, node); } cc_text(f.out, "g_pool_commit("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_id(f.out, "g_v", index); cc_text(f.out, ");\n");
        if builtin == 30 { return cc_convert(p, f, index, TYPE_I64, n.type_id, node); }
        if cc_kind(p, element) == TY_REF { return value; } return target;
    }
    if builtin == 32 {
        let index = cc_to(p, f, f.work[args + 1], TYPE_I64); cc_text(f.out, "g_pool_free("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_id(f.out, "g_v", index);
        cc_text(f.out, ","); cc_location(p, f.out, node); cc_text(f.out, ");\n"); return -1;
    }
    let slice_type = cc_slice_type(p, element); var old = -1; var old_len = -1;
    if builtin != 33 { old = cc_to(p, f, f.work[args + 1], slice_type); }
    if builtin == 35 {
        cc_text(f.out, "g_pool_slice_free("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_id(f.out, "g_v", old); cc_text(f.out, ","); cc_number(f.out, width);
        cc_text(f.out, ","); cc_location(p, f.out, node); cc_text(f.out, ");\n"); return -1;
    }
    var count_arg = args + 1; if builtin == 34 { count_arg++; }
    let count = cc_to(p, f, f.work[count_arg], TYPE_I64);
    if builtin == 34 { old_len = cc_temp(p, f, TYPE_I64); cc_set(f, old_len); cc_id(f.out, "g_v", old); cc_text(f.out, ".len;\n"); }
    let result = cc_temp(p, f, n.type_id); cc_set(f, result); cc_text(f.out, "g_pool_slice_resize("); cc_id(f.out, "g_v", base); cc_text(f.out, ",");
    if old >= 0 { cc_id(f.out, "g_v", old); } else { cc_text(f.out, "(GSlice){0}"); }
    cc_text(f.out, ","); cc_id(f.out, "g_v", count); cc_text(f.out, ","); cc_number(f.out, width); cc_text(f.out, ","); cc_location(p, f.out, node); cc_text(f.out, ");\n");
    let counter = f.serial; f.serial++;
    cc_id(f.out, "for(int64_t g_i", counter); cc_text(f.out, "="); if old_len >= 0 { cc_id(f.out, "g_v", old_len); } else { cc_text(f.out, "0"); }
    cc_text(f.out, ";"); cc_id(f.out, "g_i", counter); cc_text(f.out, "<"); cc_id(f.out, "g_v", count); cc_text(f.out, ";"); cc_id(f.out, "g_i", counter); cc_text(f.out, "++){\n");
    let target = cc_ref_temp(f); cc_set(f, target); cc_text(f.out, "g_offset("); cc_id(f.out, "g_v", result); cc_text(f.out, ".base,");
    cc_id(f.out, "g_i", counter); cc_text(f.out, "*"); cc_number(f.out, width); cc_text(f.out, ");\n");
    if n.aux >= 0 { cc_construct_into(p, f, n.aux, element, target); }
    else { let value = cc_default(p, f, element); cc_store(p, f, target, value, element, node); } cc_text(f.out, "}\n"); return result;
}
fn cc_images_used(p: Program&) -> bool {
    if cc_threads_used(p) { return true; }
    for t, id in p.types { if cc_image_type(p, id) { return true; } }
    for n in p.nodes {
        if n.kind == N_CALL && n.symbol >= 0 && (p.symbols[n.symbol].flags & S_BUILTIN) != 0 {
            let builtin = p.symbols[n.symbol].index; if builtin == 16 || builtin == 18 { return true; }
        }
    }
    return false;
}
recursive fn cc_from_bytes(p: Program&, f: CcBody&, node: i64, argument: i64) -> i64 {
    let n = p.nodes[node]; let array = p.nodes[p.types[n.type_id].first].type_id; let element = p.types[array].element;
    if !ci_verifiable(p, element) { cc_fail(p, node, "c: this element needs packed/relative image verification"); return -1; }
    let input = cc_to(p, f, argument, TYPE_STRING); let result = cc_result_temp(p, f, node, n.type_id);
    let channels = cc_temporary_ref(f, result); let target = cc_channel_target(p, f, channels, n.type_id, 0); let present = cc_channel_target(p, f, channels, n.type_id, 1);
    if p.types[array].array_kind == A_GROW || p.types[array].array_kind == A_GROWSHRINK { cc_text(f.out, "g_begin_builder("); cc_id(f.out, "g_v", target); cc_text(f.out, ");\n"); }
    let raw = f.serial; f.serial++;
    f.out.format("const uint8_t *g_input", raw, "=g_image_slice_data(g_v", input, ");const uint8_t *g_end", raw, "=g_input", raw, "+g_v", input, ".len;\n",
        "int64_t g_bytes", raw, "=0,g_count", raw, "=0;const uint8_t *g_payload", raw, "=g_image_count_check(g_input", raw, ",g_end", raw, ",0,&g_bytes", raw, ");\n",
        "int g_ok", raw, "=g_payload", raw, " && g_bytes", raw, "==g_end", raw, "-g_payload", raw, ";\n",
        "if(g_ok", raw, "){const uint8_t *cursor=g_payload", raw, ";while(cursor<g_end", raw, "){const uint8_t *next=g_image_check_", element,
        "(cursor,g_end", raw, ");if(!next || next<=cursor){g_ok", raw, "=0;break;}cursor=next;g_count", raw, "++;}}\n");
    if cc_image_type(p, array) || cc_size_class(p, element) == 1 {
        let prefix = p.types[array].length_storage;
        if p.types[array].array_kind == A_VAR && prefix > 0 && prefix < 8 {
            f.out.format("if((uint64_t)g_count", raw, ">=(UINT64_C(1)<<", prefix * 8, "))g_ok", raw, "=0;\n");
        }
        if p.types[array].array_kind == A_LIMITED && p.types[array].count < 0 { f.out.format("if((uint64_t)g_count", raw, ">UINT32_MAX)g_ok", raw, "=0;\n"); }
        f.out.format("if(!g_ok", raw, "){g_count", raw, "=0;g_bytes", raw, "=0;}\n");
        if cc_image_type(p, array) {
            f.out.format("g_image_array_begin(g_v", target, ",", cc_array_kind(p, array), ",", cc_prefix(p, array), ",g_count", raw, ",g_count", raw, ",", p.types[element].size, ");\n",
                "uint8_t *write", raw, "=((GImage*)g_address(g_v", target, "))->region->stack.top;\n");
        } else {
            f.out.format("uint8_t *write", raw, "=g_image_space(g_array_region(g_v", target, "),g_bytes", raw, ");\n");
        }
        f.out.format("if(g_bytes", raw, ")memcpy(write", raw, ",g_payload", raw, ",(size_t)g_bytes", raw, ");\n");
        if cc_image_type(p, array) { f.out.format("g_image_finish(g_v", target, ",write", raw, "+g_bytes", raw, ");\n"); }
        else { f.out.format("g_image_commit(g_v", target, ",write", raw, "+g_bytes", raw, ",g_count", raw, ");\n"); }
        f.out.format("*(uint8_t*)g_address(g_v", present, ")=g_ok", raw, ";\n"); return result;
    }
    f.out.format("if(g_ok", raw, "){g_reserve(g_v", target, ","); cc_array_args(p, f.out, array); f.out.format(",g_count", raw, ");const uint8_t *cursor=g_payload", raw, ";\n",
        "for(int64_t i=0;i<g_count", raw, ";i++)cursor=g_image_unpack_", element, "(g_ref(g_image_data(g_v", target, ","); ci_array_args(p, f.out, array);
    f.out.format(")+i*", cc_frame_size(p, element), "),cursor);\n}else g_count", raw, "=0;\n",
        "g_set_len(g_v", target, ","); cc_array_args(p, f.out, array, false); f.out.format(",g_count", raw, ");*(uint8_t*)g_address(g_v", present, ")=g_ok", raw, ";\n"); return result;
}
recursive fn cc_byte_builtin(p: Program&, f: CcBody&, node: i64, builtin: i64, args: i64, count: i64, base: i64, type_id: i64) -> i64 {
    let n = p.nodes[node]; let element = p.types[type_id].element;
    if builtin == 17 {
        if cc_size_class(p, element) == 1 && ci_verifiable(p, element) {
            let run = cc_array_span(p, f, base, type_id); let result = cc_temp(p, f, n.type_id); cc_set(f, result);
            cc_text(f.out, "(GSlice){"); cc_id(f.out, "g_v", run.start); cc_text(f.out, ","); cc_id(f.out, "g_v", run.end); cc_text(f.out, "-"); cc_id(f.out, "g_v", run.start); cc_text(f.out, "};\n"); return result;
        }
        if !ci_direct(p, element) { cc_fail(p, node, "c: bytes_of needs a physical variable image view"); return -1; }
        let result = cc_temp(p, f, n.type_id); cc_set(f, result); cc_text(f.out, "g_view("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id); cc_text(f.out, ");\n");
        cc_id(f.out, "g_v", result); cc_text(f.out, ".len*="); cc_number(f.out, cc_frame_size(p, element)); cc_text(f.out, ";\n"); return result;
    }
    if !ci_verifiable(p, element) && !ci_direct(p, element) { cc_fail(p, node, "c: this element needs packed/relative image serialization"); return -1; }
    let view = cc_temp(p, f, TYPE_STRING); cc_set(f, view); cc_text(f.out, "g_view("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id); cc_text(f.out, ");\n");
    let raw = f.serial; f.serial++;
    if cc_size_class(p, element) == 1 {
        let run = cc_array_span(p, f, base, type_id); f.out.format("int64_t g_bytes", raw, "=g_v", run.end, "-g_v", run.start, ";\n");
    } else if ci_direct(p, element) { f.out.format("int64_t g_bytes", raw, "=g_image_product(g_v", view, ".len,", p.types[element].size, ");\n"); }
    else { f.out.format("int64_t g_bytes", raw, "=0;for(int64_t i=0;i<g_v", view, ".len;i++)g_bytes", raw, "=g_image_add(g_bytes", raw, ",g_image_size_", element,
        "(g_offset(g_v", view, ".base,i*", cc_frame_size(p, element), ")));\n"); }
    f.out.format("uint8_t g_prefix", raw, "[10];int64_t g_prefix_size", raw, "=gs_uleb_write(g_prefix", raw, ",(uint64_t)g_bytes", raw, ");\n");
    var result = -1; var destination = -1; var receiving_type = -1;
    if count == 1 {
        result = cc_result_temp(p, f, node, n.type_id); destination = cc_temporary_ref(f, result); receiving_type = n.type_id;
        cc_text(f.out, "g_begin_builder("); cc_id(f.out, "g_v", destination); cc_text(f.out, ");\n");
    } else {
        let output = f.work[args + 1]; receiving_type = p.nodes[output].type_id; destination = cc_base(p, f, output);
        while cc_kind(p, receiving_type) == TY_REF { receiving_type = p.types[receiving_type].element; }
    }
    cc_text(f.out, "g_append_bytes("); cc_id(f.out, "g_v", destination); cc_text(f.out, ","); cc_array_args(p, f.out, receiving_type, false);
    f.out.format(",g_prefix", raw, ",g_prefix_size", raw, ");\nint64_t g_old", raw, "=g_len(g_v", destination, ","); cc_array_args(p, f.out, receiving_type, false);
    f.out.format(");if(g_bytes", raw, ">INT64_MAX-g_old", raw, ")g_panic(\"image length overflow\");\ng_reserve(g_v", destination, ","); cc_array_args(p, f.out, receiving_type);
    f.out.format(",g_old", raw, "+g_bytes", raw, ");\nuint8_t *g_write", raw, "=g_address(g_element(g_v", destination, ","); cc_array_args(p, f.out, receiving_type);
    f.out.format(",g_old", raw, ",1));\n");
    if ci_direct(p, element) || cc_size_class(p, element) == 1 { f.out.format("if(g_bytes", raw, ")memmove(g_write", raw, ",g_image_slice_data(g_v", view, "),(size_t)g_bytes", raw, ");\n"); }
    else { f.out.format("for(int64_t i=0;i<g_v", view, ".len;i++)g_write", raw, "=g_image_write_", element, "(g_write", raw, ",g_offset(g_v", view, ".base,i*", cc_frame_size(p, element), "));\n"); }
    cc_text(f.out, "g_set_len("); cc_id(f.out, "g_v", destination); cc_text(f.out, ","); cc_array_args(p, f.out, receiving_type, false); f.out.format(",g_old", raw, "+g_bytes", raw, ");\n"); return result;
}
fn cc_run_writer(f: CcBody&, header: i64) -> i64 {
    let raw = f.serial; f.serial++;
    cc_id(f.out, "GArray g_writer_array", raw); cc_text(f.out, ";memcpy(&"); cc_id(f.out, "g_writer_array", raw); cc_text(f.out, ",g_address("); cc_id(f.out, "g_v", header); cc_text(f.out, "),sizeof(GArray));\n");
    cc_id(f.out, "GImage g_writer", raw); cc_text(f.out, "={"); cc_id(f.out, "g_writer_array", raw); cc_text(f.out, ".region->stack.top,"); cc_id(f.out, "g_writer_array", raw); cc_text(f.out, ".region->stack.top,"); cc_id(f.out, "g_writer_array", raw); cc_text(f.out, ".region};\n");
    let owner = cc_ref_temp(f); cc_set(f, owner); cc_text(f.out, "g_ref(&"); cc_id(f.out, "g_writer", raw); cc_text(f.out, ");\n"); return owner;
}
recursive fn cc_image_extend(p: Program&, f: CcBody&, node: i64, builtin: i64, base: i64, array: i64, argument: i64) -> i64 {
    let element = p.types[array].element; var value = -1; var source_type = p.nodes[argument].type_id; var source = -1;
    if builtin == 24 { value = cc_to(p, f, argument, element); if value < 0 { return -1; } }
    else {
        value = cc_expr(p, f, argument); if value < 0 { return -1; }
        if cc_kind(p, source_type) == TY_REF {
            while cc_kind(p, source_type) == TY_REF {
                source_type = p.types[source_type].element;
                if cc_kind(p, source_type) == TY_REF { value = cc_load(p, f, value, source_type); }
            }
            source = value;
        } else { source = cc_array_value_ref(p, f, value, source_type); }
    }
    let length = cc_temp(p, f, TYPE_I64); cc_set(f, length); cc_text(f.out, "g_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, array, false); cc_text(f.out, ");\n");
    let owner = cc_run_writer(f, base); let result = cc_ref_temp(f); cc_set(f, result); cc_text(f.out, "g_ref(((GImage*)g_address("); cc_id(f.out, "g_v", owner); cc_text(f.out, "))->region->stack.top);\n");
    if builtin == 24 {
        cc_text(f.out, "if("); cc_id(f.out, "g_v", length); cc_text(f.out, "==INT64_MAX)g_panic(\"array length overflow\");\n");
        cc_image_put_value(p, f, owner, value, element, node);
        cc_text(f.out, "g_image_commit("); cc_id(f.out, "g_v", base); cc_text(f.out, ",((GImage*)g_address("); cc_id(f.out, "g_v", owner); cc_text(f.out, "))->region->stack.top,"); cc_id(f.out, "g_v", length); cc_text(f.out, "+1);\n"); return result;
    }
    let run = cc_array_span(p, f, source, source_type);
    cc_text(f.out, "if("); cc_id(f.out, "g_v", run.count); cc_text(f.out, ">INT64_MAX-"); cc_id(f.out, "g_v", length); cc_text(f.out, ")g_panic(\"array length overflow\");\n");
    if cc_queue_same(p, element, p.types[source_type].element) {
        let raw = f.serial; f.serial++;
        cc_id(f.out, "int64_t g_run_bytes", raw); cc_text(f.out, "="); cc_id(f.out, "g_v", run.end); cc_text(f.out, "-"); cc_id(f.out, "g_v", run.start); cc_text(f.out, ";\n");
        cc_id(f.out, "uint8_t *g_run_target", raw); cc_text(f.out, "=g_image_space(((GImage*)g_address("); cc_id(f.out, "g_v", owner); cc_text(f.out, "))->region,"); cc_id(f.out, "g_run_bytes", raw); cc_text(f.out, ");memmove("); cc_id(f.out, "g_run_target", raw); cc_text(f.out, ",g_address("); cc_id(f.out, "g_v", run.start); cc_text(f.out, "),(size_t)"); cc_id(f.out, "g_run_bytes", raw); cc_text(f.out, ");g_image_advance(((GImage*)g_address("); cc_id(f.out, "g_v", owner); cc_text(f.out, "))->region,"); cc_id(f.out, "g_run_target", raw); cc_text(f.out, "+"); cc_id(f.out, "g_run_bytes", raw); cc_text(f.out, ");\n");
    } else {
        let raw = f.serial; f.serial++; let source_element = p.types[source_type].element;
        cc_id(f.out, "for(int64_t g_i", raw); cc_text(f.out, "=0;"); cc_id(f.out, "g_i", raw); cc_text(f.out, "<"); cc_id(f.out, "g_v", run.count); cc_text(f.out, ";"); cc_id(f.out, "g_i", raw); cc_text(f.out, "++){\n");
        let mark = f.region_live; let loaded = cc_load(p, f, run.start, source_element); let adapted = cc_convert(p, f, loaded, source_element, element, node);
        cc_image_put_value(p, f, owner, adapted, element, node); cc_restore(f, mark); f.region_live = mark;
        cc_set(f, run.start); cc_text(f.out, "g_ref(g_physical_skip_"); cc_number(f.out, source_element); cc_text(f.out, "(g_address("); cc_id(f.out, "g_v", run.start); cc_text(f.out, ")));\n}\n");
    }
    cc_text(f.out, "g_image_commit("); cc_id(f.out, "g_v", base); cc_text(f.out, ",((GImage*)g_address("); cc_id(f.out, "g_v", owner); cc_text(f.out, "))->region->stack.top,"); cc_id(f.out, "g_v", length); cc_text(f.out, "+"); cc_id(f.out, "g_v", run.count); cc_text(f.out, ");\n"); return -1;
}
fn cc_render_type(p: Program&, id: i64) -> i64 {
    if cc_kind(p, id) == TY_REF && cc_flat_relative_image(p, p.types[id].element) { return p.types[id].element; }
    return id;
}
recursive fn cc_render_value(p: Program&, f: CcBody&, node: i64) -> i64 {
    let type_id = p.nodes[node].type_id; let rendered = cc_render_type(p, type_id);
    if cc_render_unbounded_image(p, rendered) { cc_fail(p, node, "c: nested image reference rendering requires owner authority"); return -1; }
    if rendered != type_id {
        let place = cc_base_place(p, f, node); if place.address < 0 { return -1; }
        return cc_read(p, f, place, rendered, node);
    }
    return cc_expr(p, f, node);
}
recursive fn cc_builtin(p: Program&, f: CcBody&, node: i64, builtin: i64) -> i64 {
    let n = p.nodes[node]; let args_start = f.work.len; var args_count = 0; var arg = n.first;
    while arg >= 0 { f.work.push(arg); args_count++; arg = p.nodes[arg].next; }
    if builtin == 14 { return cc_default(p, f, n.type_id); }
    if builtin == 15 { return cc_to(p, f, f.work[args_start + 0], n.type_id, true); }
    if builtin == 0 || builtin == 1 || builtin == 2 {
        var output = -1; var start = 0; var builder = -1; var limited = -1;
        let raw = f.serial; f.serial++;
        if builtin == 0 {
            cc_raw_array(f, "g_output", raw);
            builder = cc_ref_temp(f); cc_set(f, builder); cc_text(f.out, "g_ref(&"); cc_id(f.out, "g_output", raw); cc_text(f.out, ");\n");
        }
        if builtin == 1 { output = cc_result_temp(p, f, node, n.type_id); builder = cc_temporary_ref(f, output); cc_text(f.out, "g_begin_builder("); cc_id(f.out, "g_v", builder); cc_text(f.out, ");\n"); }
        if builtin == 2 {
            let receiver = f.work[args_start]; builder = cc_base(p, f, receiver); start = 1;
            var array = p.nodes[receiver].type_id; while cc_kind(p, array) == TY_REF { array = p.types[array].element; }
            if cc_kind(p, array) == TY_ARRAY && p.types[array].array_kind == A_LIMITED { limited = array; }
        }
        cc_id(f.out, "GArray g_builder", raw); cc_text(f.out, ";\n");
        for i in start..args_count {
            let value = cc_render_value(p, f, f.work[args_start + i]); if value < 0 { return -1; }
            if limited >= 0 { let slot = cc_region_slot(f, 1); cc_id(f.out, "g_builder", raw); cc_text(f.out, "=g_array("); cc_region_argument(f, slot); cc_text(f.out, ");\n"); }
            else {
                cc_text(f.out, "memcpy(&"); cc_id(f.out, "g_builder", raw); cc_text(f.out, ",g_address("); cc_id(f.out, "g_v", builder); cc_text(f.out, "),sizeof(GArray));\n");
            }
            cc_id(f.out, "g_print_", cc_render_type(p, p.nodes[f.work[args_start + i]].type_id)); cc_text(f.out, "(&"); cc_id(f.out, "g_builder", raw);
            cc_text(f.out, ","); cc_id(f.out, "g_v", value); cc_text(f.out, ");\n");
            if limited >= 0 {
                cc_text(f.out, "g_append_bytes("); cc_id(f.out, "g_v", builder); cc_text(f.out, ","); cc_array_args(p, f.out, limited, false);
                cc_text(f.out, ","); cc_id(f.out, "g_builder", raw); cc_text(f.out, ".data,"); cc_id(f.out, "g_builder", raw); cc_text(f.out, ".len);\n");
            } else {
                cc_text(f.out, "memcpy(g_address("); cc_id(f.out, "g_v", builder); cc_text(f.out, "),&"); cc_id(f.out, "g_builder", raw); cc_text(f.out, ",sizeof(GArray));g_header_changed("); cc_id(f.out, "g_v", builder); cc_text(f.out, ");\n");
            }
        }
        if builtin == 0 {
            cc_text(f.out, "flockfile(stdout);g_print_bytes(NULL,"); cc_id(f.out, "g_output", raw); cc_text(f.out, ".data,");
            cc_id(f.out, "g_output", raw); cc_text(f.out, ".len);g_print_text(NULL,\"\\n\");funlockfile(stdout);\n");
        }
        return output;
    }
    if builtin == 3 {
        let condition = cc_to(p, f, f.work[args_start + 0], TYPE_BOOL); cc_text(f.out, "if(!"); cc_id(f.out, "g_v", condition);
        cc_text(f.out, ")g_debug_fail("); cc_location(p, f.out, node); cc_text(f.out, ",\"assert failed\");\n"); return -1;
    }
    if builtin == 4 {
        let value = cc_render_value(p, f, f.work[args_start + 0]); if value < 0 { return -1; } let message = f.serial; f.serial++;
        cc_raw_array(f, "g_message", message);
        cc_id(f.out, "g_print_", cc_render_type(p, p.nodes[f.work[args_start + 0]].type_id)); cc_text(f.out, "(&"); cc_id(f.out, "g_message", message);
        cc_text(f.out, ","); cc_id(f.out, "g_v", value); cc_text(f.out, ");g_abort_value("); cc_id(f.out, "g_message", message);
        cc_text(f.out, ","); cc_location(p, f.out, node); cc_text(f.out, ");\n"); return -1;
    }
    if builtin == 5 { let value = cc_to(p, f, f.work[args_start + 0], TYPE_I32); cc_text(f.out, "g_exit("); cc_id(f.out, "g_v", value); cc_text(f.out, ");\n"); return -1; }
    if builtin == 6 {
        let result = cc_temp(p, f, n.type_id); cc_set(f, result); cc_text(f.out, "gs_hardware_threads();\n"); return result;
    }
    if builtin >= 7 && builtin <= 13 { return cc_thread_builtin(p, f, node, builtin, args_start, args_count); }
    if builtin == 19 || builtin == 20 { cc_fail(p, node, "c: embed builtin must be folded by the source driver"); return -1; }
    if builtin == 18 { return cc_from_bytes(p, f, node, f.work[args_start]); }
    if args_count == 0 { cc_fail(p, node, "c: builtin has no receiver"); return -1; }
    let receiver = f.work[args_start + 0]; var type_id = p.nodes[receiver].type_id;
    if cc_kind(p, type_id) == TY_REF { type_id = p.types[type_id].element; }
    let base = cc_base(p, f, receiver); let t = p.types[type_id];
    if builtin == 16 || builtin == 17 { return cc_byte_builtin(p, f, node, builtin, args_start, args_count, base, type_id); }
    if builtin == 21 || builtin == 22 {
        let result = cc_temp(p, f, n.type_id); cc_set(f, result);
        if builtin == 21 || t.array_kind == A_VAR { cc_text(f.out, "g_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id, false); }
        else { cc_text(f.out, "g_cap("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_number(f.out, cc_array_kind(p, type_id)); cc_text(f.out, ","); cc_number(f.out, t.count); }
        cc_text(f.out, ");\n"); return result;
    }
    if builtin == 23 {
        let value = cc_base(p, f, f.work[args_start + 1]); let result = cc_temp(p, f, n.type_id); cc_set(f, result);
        cc_text(f.out, "(int64_t)(((uintptr_t)"); cc_id(f.out, "g_v", value); cc_text(f.out, "-(uintptr_t)g_element("); cc_id(f.out, "g_v", base);
        cc_text(f.out, ","); cc_array_args(p, f.out, type_id); cc_text(f.out, ",0,1))/"); cc_number(f.out, cc_frame_size(p, t.element)); cc_text(f.out, ");\n"); return result;
    }
    if builtin >= 30 && builtin <= 35 { return cc_pool_builtin(p, f, node, builtin, args_start, base, type_id); }
    if (builtin == 24 || builtin == 25) && cc_size_class(p, t.element) == 1 {
        return cc_image_extend(p, f, node, builtin, base, type_id, f.work[args_start + 1]);
    }
    if builtin == 24 {
        if cc_result_location(p, t.element) {
            let length = cc_temp(p, f, TYPE_I64); cc_set(f, length); cc_text(f.out, "g_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id, false); cc_text(f.out, ");\n");
            cc_text(f.out, "if("); cc_id(f.out, "g_v", length); cc_text(f.out, "==INT64_MAX)g_panic(\"array length overflow\");\ng_reserve("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id); cc_text(f.out, ","); cc_id(f.out, "g_v", length); cc_text(f.out, "+1);\n");
            let slot = cc_ref_temp(f); cc_set(f, slot); cc_text(f.out, "g_slot("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id); cc_text(f.out, ","); cc_id(f.out, "g_v", length); cc_text(f.out, ");\n");
            cc_construct_into(p, f, f.work[args_start + 1], t.element, slot); cc_text(f.out, "g_set_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id, false); cc_text(f.out, ","); cc_id(f.out, "g_v", length); cc_text(f.out, "+1);\n"); return slot;
        }
        let value = cc_to(p, f, f.work[args_start + 1], t.element, true);
        if cc_relative_cell(p, t.element) {
            let length = cc_temp(p, f, TYPE_I64); cc_set(f, length); cc_text(f.out, "g_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id, false); cc_text(f.out, ");\n");
            cc_text(f.out, "if("); cc_id(f.out, "g_v", length); cc_text(f.out, "==INT64_MAX)g_panic(\"array length overflow\");\ng_reserve("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id);
            cc_text(f.out, ","); cc_id(f.out, "g_v", length); cc_text(f.out, "+1);\n");
            let cell = cc_ref_temp(f); cc_set(f, cell); cc_text(f.out, "g_slot("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id); cc_text(f.out, ","); cc_id(f.out, "g_v", length); cc_text(f.out, ");\n");
            cc_store(p, f, cell, value, t.element, node); cc_text(f.out, "g_set_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id, false);
            cc_text(f.out, ","); cc_id(f.out, "g_v", length); cc_text(f.out, "+1);\n"); return cc_convert(p, f, value, t.element, n.type_id, node);
        }
        let result = cc_temp(p, f, n.type_id); cc_set(f, result);
        cc_text(f.out, "g_push("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id); cc_text(f.out, ",&"); cc_id(f.out, "g_v", value); cc_text(f.out, ");\n");
        if cc_kind(p, t.element) == TY_REF { return cc_convert(p, f, value, t.element, n.type_id, node); } return result;
    }
    if builtin == 25 {
        let argument = f.work[args_start + 1]; let literal = p.nodes[argument]; let literal_type = literal.type_id;
        if (literal.kind == N_ARRAY || literal.kind == N_FILL) && cc_kind(p, literal_type) == TY_ARRAY && p.types[literal_type].array_kind == A_FIXED && cc_relative_fields(p, t.element) {
            let fill_mark = f.fills.len;
            if cc_relative_cell(p, t.element) { cc_freeze_fill(p, f, argument, literal_type); }
            let old = cc_temp(p, f, TYPE_I64); cc_set(f, old); cc_text(f.out, "g_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id, false); cc_text(f.out, ");\n");
            let count = p.types[literal_type].count;
            cc_text(f.out, "if("); cc_id(f.out, "g_v", old); cc_text(f.out, ">INT64_MAX-"); cc_number(f.out, count); cc_text(f.out, ")g_panic(\"array length overflow\");\ng_reserve("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id); cc_text(f.out, ","); cc_id(f.out, "g_v", old); cc_text(f.out, "+"); cc_number(f.out, count); cc_text(f.out, ");\n");
            let target = cc_ref_temp(f); cc_set(f, target); cc_text(f.out, "g_slot("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id); cc_text(f.out, ","); cc_id(f.out, "g_v", old); cc_text(f.out, ");\n");
            cc_construct_into(p, f, argument, literal_type, target); f.fills.resize(fill_mark);
            cc_text(f.out, "g_set_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id, false); cc_text(f.out, ","); cc_id(f.out, "g_v", old); cc_text(f.out, "+"); cc_number(f.out, count); cc_text(f.out, ");\n"); return -1;
        }
        let source = cc_base(p, f, f.work[args_start + 1]); var source_type = p.nodes[f.work[args_start + 1]].type_id;
        if cc_kind(p, source_type) == TY_REF { source_type = p.types[source_type].element; }
        let count = cc_temp(p, f, TYPE_I64); cc_set(f, count); cc_text(f.out, "g_len("); cc_id(f.out, "g_v", source); cc_text(f.out, ","); cc_array_args(p, f.out, source_type, false); cc_text(f.out, ");\n");
        if !cc_needs_clone(p, t.element, 0) {
            let old = cc_temp(p, f, TYPE_I64); cc_set(f, old); cc_text(f.out, "g_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id, false); cc_text(f.out, ");\n");
            cc_text(f.out, "g_reserve("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id); cc_text(f.out, ","); cc_id(f.out, "g_v", old); cc_text(f.out, "+"); cc_id(f.out, "g_v", count); cc_text(f.out, ");\n");
            cc_text(f.out, "if("); cc_id(f.out, "g_v", count); cc_text(f.out, ")memmove(g_address(g_element("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id); cc_text(f.out, ","); cc_id(f.out, "g_v", old); cc_text(f.out, ",1)),g_address(g_element("); cc_id(f.out, "g_v", source); cc_text(f.out, ","); cc_array_args(p, f.out, source_type); cc_text(f.out, ",0,1)),(size_t)"); cc_id(f.out, "g_v", count); cc_text(f.out, "*"); cc_number(f.out, cc_frame_size(p, t.element)); cc_text(f.out, ");\n");
            cc_text(f.out, "g_set_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id, false); cc_text(f.out, ","); cc_id(f.out, "g_v", old); cc_text(f.out, "+"); cc_id(f.out, "g_v", count); cc_text(f.out, ");\n"); return -1;
        }
        let counter = f.serial; f.serial++;
        cc_id(f.out, "for(int64_t g_i", counter); cc_text(f.out, "=0;"); cc_id(f.out, "g_i", counter); cc_text(f.out, "<"); cc_id(f.out, "g_v", count); cc_text(f.out, ";"); cc_id(f.out, "g_i", counter); cc_text(f.out, "++){\n");
        let value = cc_temp(p, f, t.element); cc_set(f, value); cc_id(f.out, "g_clone_", t.element); cc_text(f.out, "("); cc_id(f.out, "g_load_", t.element); cc_text(f.out, "(g_element("); cc_id(f.out, "g_v", source); cc_text(f.out, ","); cc_array_args(p, f.out, source_type); cc_text(f.out, ","); cc_id(f.out, "g_i", counter); cc_text(f.out, ",0)));\n");
        cc_text(f.out, "g_push("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id); cc_text(f.out, ",&"); cc_id(f.out, "g_v", value); cc_text(f.out, ");}\n"); return -1;
    }
    if builtin >= 26 && builtin <= 29 {
        var requested = -1; var fill = -1;
        if builtin == 27 || builtin == 28 {
            requested = cc_to(p, f, f.work[args_start + 1], TYPE_I64); if requested < 0 { return -1; }
        }
        if builtin == 28 {
            cc_text(f.out, "if("); cc_id(f.out, "g_v", requested); cc_text(f.out, "<0)g_panic_at(\"resize to a negative length\","); cc_location(p, f.out, node); cc_text(f.out, ");\n");
            if args_count >= 3 { fill = cc_to(p, f, f.work[args_start + 2], t.element, true); if fill < 0 { return -1; } }
        }
        let old = cc_temp(p, f, TYPE_I64); cc_set(f, old); cc_text(f.out, "g_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id, false); cc_text(f.out, ");\n");
        var length = cc_temp(p, f, TYPE_I64); var result = -1;
        if builtin == 26 {
            cc_text(f.out, "if(!"); cc_id(f.out, "g_v", old); cc_text(f.out, ")g_panic(\"pop on empty array\");\n");
            cc_set(f, length); cc_id(f.out, "g_v", old); cc_text(f.out, "-1;\n");
            result = cc_temp(p, f, n.type_id); cc_set(f, result); cc_id(f.out, "g_clone_", t.element); cc_text(f.out, "("); cc_id(f.out, "g_load_", t.element); cc_text(f.out, "(g_element("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id); cc_text(f.out, ","); cc_id(f.out, "g_v", length); cc_text(f.out, ",0)));\n");
        } else if builtin == 29 { cc_set(f, length); cc_text(f.out, "0;\n"); }
        else {
            if builtin == 27 {
                cc_text(f.out, "if("); cc_id(f.out, "g_v", requested); cc_text(f.out, "<0||"); cc_id(f.out, "g_v", requested); cc_text(f.out, ">");
                cc_id(f.out, "g_v", old); cc_text(f.out, ")g_panic_at(\"pop_n count negative or beyond the array's length\","); cc_location(p, f.out, node); cc_text(f.out, ");\n");
            }
            cc_set(f, length);
            if builtin == 27 { cc_id(f.out, "g_v", old); cc_text(f.out, "-"); } cc_id(f.out, "g_v", requested); cc_text(f.out, ";\n");
        }
        cc_text(f.out, "if("); cc_id(f.out, "g_v", length); cc_text(f.out, "<0)g_panic_at(\"resize to a negative length\","); cc_location(p, f.out, node); cc_text(f.out, ");\n");
        if builtin == 28 {
            cc_text(f.out, "g_reserve("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id); cc_text(f.out, ","); cc_id(f.out, "g_v", length); cc_text(f.out, ");\n");
            if args_count >= 3 {
                let counter = f.serial; f.serial++;
                cc_text(f.out, "g_set_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id, false); cc_text(f.out, ","); cc_id(f.out, "g_v", length); cc_text(f.out, ");\n");
                cc_id(f.out, "for(int64_t g_i", counter); cc_text(f.out, "="); cc_id(f.out, "g_v", old); cc_text(f.out, ";"); cc_id(f.out, "g_i", counter); cc_text(f.out, "<"); cc_id(f.out, "g_v", length); cc_text(f.out, ";"); cc_id(f.out, "g_i", counter); cc_text(f.out, "++){"); cc_id(f.out, "g_store_", t.element); cc_text(f.out, "(g_element("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id); cc_text(f.out, ","); cc_id(f.out, "g_i", counter); cc_text(f.out, ",0),"); cc_id(f.out, "g_clone_", t.element); cc_text(f.out, "("); cc_id(f.out, "g_v", fill); cc_text(f.out, "));}\n");
            } else { cc_text(f.out, "if("); cc_id(f.out, "g_v", length); cc_text(f.out, ">"); cc_id(f.out, "g_v", old); cc_text(f.out, ")g_panic(\"resize growth requires fill\");\n"); }
        } else { cc_text(f.out, "if("); cc_id(f.out, "g_v", length); cc_text(f.out, ">"); cc_id(f.out, "g_v", old); cc_text(f.out, ")g_panic(\"pop count exceeds length\");\n"); }
        cc_text(f.out, "g_set_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, type_id, false); cc_text(f.out, ","); cc_id(f.out, "g_v", length); cc_text(f.out, ");\n"); return result;
    }
    cc_fail(p, node, "c: reusable slice/slot builtin requires pool runtime integration"); return -1;
}

recursive fn cc_match(p: Program&, f: CcBody&, node: i64) -> i64 {
    let n = p.nodes[node]; var source_type = p.nodes[n.left].type_id;
    while cc_kind(p, source_type) == TY_REF { source_type = p.types[source_type].element; }
    var scrutinee = cc_base_place(p, f, n.left); var current = p.nodes[n.left].type_id;
    while cc_kind(p, current) == TY_REF && cc_kind(p, p.types[current].element) == TY_REF {
        current = p.types[current].element;
        let address = cc_read(p, f, scrutinee, current, node); let pointee = p.types[current].element;
        scrutinee = CcPlace { type_id: pointee, address: address };
        if cc_image_type(p, pointee) { scrutinee.form = CC_IMAGE; }
    }
    let place = scrutinee.address; let source = cc_read(p, f, scrutinee, source_type, node);
    let result = cc_result_temp(p, f, node, n.type_id); let done = f.serial; f.serial++;
    let enum_match = cc_kind(p, source_type) == TY_ENUM;
    var arm = n.first;
    while arm >= 0 {
        let a = p.nodes[arm]; let pattern = p.nodes[a.left]; cc_text(f.out, "if(");
        if (pattern.flags & F_DEFAULT) != 0 { cc_text(f.out, "1"); }
        else {
            var item = pattern.first; var separator = false;
            while item >= 0 {
                if separator { cc_text(f.out, "||"); } cc_text(f.out, "("); let pat = p.nodes[item];
                if enum_match {
                    cc_text(f.out, "g_read_length("); if !cc_image_type(p, source_type) { cc_text(f.out, "&"); } cc_id(f.out, "g_v", source); if cc_image_type(p, source_type) { cc_text(f.out, ".base"); } cc_text(f.out, ","); cc_number(f.out, p.types[source_type].length_storage); cc_text(f.out, ")=="); cc_number(f.out, pat.integer);
                } else if pat.kind == N_RANGE {
                    cc_id(f.out, "g_v", source); cc_text(f.out, ">="); cc_number(f.out, p.nodes[pat.left].integer); cc_text(f.out, "&&"); cc_id(f.out, "g_v", source);
                    if (pat.flags & F_INCLUSIVE) != 0 { cc_text(f.out, "<="); } else { cc_text(f.out, "<"); }
                    cc_number(f.out, p.nodes[pat.right].integer);
                } else { cc_id(f.out, "g_v", source); cc_text(f.out, "==UINT64_C("); f.out.format(pat.integer as! u64); cc_text(f.out, ")"); }
                cc_text(f.out, ")"); separator = true; item = pat.next;
            }
        }
        cc_text(f.out, "){\n");
        if pattern.left >= 0 {
            let binder = p.nodes[pattern.left];
            if (binder.flags & F_REFERENCE) != 0 {
                cc_id(f.out, "g_s", binder.symbol); cc_text(f.out, "=g_offset("); cc_id(f.out, "g_v", place); cc_text(f.out, ","); cc_number(f.out, p.types[source_type].length_storage); cc_text(f.out, ");\n");
                if !cc_image_type(p, source_type) && cc_kind(p, binder.type_id) == TY_REF && cc_image_type(p, p.types[binder.type_id].element) {
                    cc_id(f.out, "g_s", binder.symbol); cc_text(f.out, "=g_ref(((GImage*)g_address("); cc_id(f.out, "g_s", binder.symbol); cc_text(f.out, "))->base);\n");
                }
            } else if cc_image_type(p, source_type) {
                cc_id(f.out, "g_s", binder.symbol); cc_text(f.out, "="); cc_id(f.out, "g_load_", binder.type_id); cc_text(f.out, "(g_offset("); cc_id(f.out, "g_v", place); cc_text(f.out, ","); cc_number(f.out, p.types[source_type].length_storage); cc_text(f.out, "));\n");
            } else {
                cc_text(f.out, "memcpy(&"); cc_id(f.out, "g_s", binder.symbol); cc_text(f.out, ",((unsigned char*)&"); cc_id(f.out, "g_v", source); cc_text(f.out, ")+"); cc_number(f.out, p.types[source_type].length_storage); cc_text(f.out, ",sizeof("); cc_type(f.out, binder.type_id); cc_text(f.out, "));\n");
            }
        }
        if a.third >= 0 { let condition_guard = cc_to(p, f, a.third, TYPE_BOOL); cc_text(f.out, "if("); cc_id(f.out, "g_v", condition_guard); cc_text(f.out, "){\n"); }
        if result >= 0 && !cc_diverges(p, a.right) {
            let target = cc_temporary_ref(f, result); let body = cc_construct_into(p, f, a.right, n.type_id, target, cc_value_form(p, n.type_id));
            if body < 0 { cc_fail(p, a.right, "c: match arm result has no value"); }
        } else { cc_expr(p, f, a.right); }
        cc_id(f.out, "goto g_label", done); cc_text(f.out, ";\n"); if a.third >= 0 { cc_text(f.out, "}\n"); }
        cc_text(f.out, "}\n"); arm = a.next;
    }
    cc_text(f.out, "g_panic(\"non-exhaustive match\");\n"); cc_id(f.out, "g_label", done); cc_text(f.out, ":;\n"); return result;
}
recursive fn cc_expr(p: Program&, f: CcBody&, node: i64) -> i64 {
    if node < 0 { return -1; }
    let n = p.nodes[node];
    if n.kind == N_INTEGER || n.kind == N_BOOL || n.kind == N_NULL {
        let result = cc_temp(p, f, n.type_id); if result < 0 { return -1; } cc_set(f, result);
        if n.kind == N_NULL { cc_text(f.out, "0"); }
        else { cc_text(f.out, "("); cc_type(f.out, n.type_id); cc_text(f.out, ")UINT64_C("); f.out.format(n.integer as! u64); cc_text(f.out, ")"); }
        cc_text(f.out, ";\n"); return result;
    }
    if n.kind == N_FLOAT {
        let result = cc_temp(p, f, n.type_id); let values: f64[1] = [n.float_value]; let bytes = bytes_of(values);
        cc_set(f, result);
        if n.float_value != n.float_value { cc_text(f.out, "NAN"); }
        else if n.float_value > 1.7976931348623157e308 { cc_text(f.out, "INFINITY"); }
        else {
            cc_text(f.out, "g_float_literal(UINT64_C("); var bits: u64 = 0;
            for byte, i in bytes { bits |= byte as u64 << (i * 8); } f.out.format(bits); cc_text(f.out, "))");
        }
        cc_text(f.out, ";\n"); return result;
    }
    if n.kind == N_STRING {
        if cc_image_type(p, n.type_id) { return cc_image_array(p, f, node, n.type_id); }
        let result = cc_result_temp(p, f, node, n.type_id); let token = p.tokens[n.token];
        if cc_kind(p, n.type_id) == TY_SLICE {
            cc_set(f, result); cc_text(f.out, "(GSlice){g_ref((void*)"); cc_bytes(f.out, p.text[token.text_start..token.text_start + token.text_len]); cc_text(f.out, "),"); cc_number(f.out, token.text_len); cc_text(f.out, "};\n");
        } else if cc_kind(p, n.type_id) == TY_ARRAY {
            let base = cc_temporary_ref(f, result);
            if cc_owner(p, n.type_id) {
                cc_text(f.out, "g_reserve("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, n.type_id); cc_text(f.out, ","); cc_number(f.out, token.text_len); cc_text(f.out, ");\n");
            }
            if p.types[n.type_id].array_kind != A_FIXED {
                cc_text(f.out, "g_set_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, n.type_id, false); cc_text(f.out, ","); cc_number(f.out, token.text_len); cc_text(f.out, ");\n");
            }
            cc_text(f.out, "memcpy(g_address(g_element("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, n.type_id); cc_text(f.out, ",0,1)),"); cc_bytes(f.out, p.text[token.text_start..token.text_start + token.text_len]); cc_text(f.out, ","); cc_number(f.out, token.text_len); cc_text(f.out, ");\n");
        } else { cc_fail(p, node, "c: string literal has a non-byte-array destination"); }
        return result;
    }
    if n.kind == N_NAME {
        if n.symbol >= 0 && (p.symbols[n.symbol].flags & S_FUNCTION) != 0 { return cc_closure(p, f, p.symbols[n.symbol].node, n.type_id); }
        let ref = cc_symbol_ref(p, f, n.symbol, node); return cc_read(p, f, CcPlace { type_id: cc_place_type(p, node), address: ref }, n.type_id, node);
    }
    if n.kind == N_MEMBER || n.kind == N_INDEX { return cc_read(p, f, cc_place_location(p, f, node), n.type_id, node); }
    if n.kind == N_UNARY {
        if n.integer == T_BITAND {
            let stored = cc_place_type(p, n.left);
            if cc_relative_cell(p, stored) {
                let place = cc_place_location(p, f, n.left);
                if place.form == CC_IMAGE && place.image_end >= 0 { return cc_read(p, f, place, n.type_id, node); }
                let ref = place.address; let result = cc_temp(p, f, n.type_id); cc_set(f, result); cc_id(f.out, "g_load_", stored);
                cc_text(f.out, "("); cc_id(f.out, "g_v", ref); cc_text(f.out, ");\n"); return result;
            }
            if cc_kind(p, p.nodes[n.left].type_id) == TY_REF { return cc_expr(p, f, n.left); }
            return cc_reference_place(p, f, n.left);
        }
        if n.integer == T_MUL { return cc_read(p, f, cc_place_location(p, f, node), n.type_id, node); }
        let operand = cc_to(p, f, n.left, p.nodes[n.left].type_id); let result = cc_temp(p, f, n.type_id); cc_set(f, result);
        if n.integer == T_NOT { cc_text(f.out, "!"); }
        else if n.integer == T_BITNOT { cc_text(f.out, "~"); }
        else if n.integer == T_MINUS {
            if p.debug && cc_kind(p, n.type_id) == TY_INT && (p.types[n.type_id].flags & TF_UNSIGNED) == 0 {
                cc_text(f.out, "g_checked_neg("); cc_id(f.out, "g_v", operand); cc_text(f.out, ",");
                cc_number(f.out, p.types[n.type_id].count); cc_text(f.out, ","); cc_location(p, f.out, node); cc_text(f.out, ");\n"); return result;
            }
            if cc_kind(p, n.type_id) == TY_INT { cc_text(f.out, "("); cc_type(f.out, n.type_id); cc_text(f.out, ")(UINT64_C(0)-(uint64_t)"); cc_id(f.out, "g_v", operand); cc_text(f.out, ");\n"); return result; }
            cc_text(f.out, "-");
        } else { cc_fail(p, node, "c: unknown unary operator"); }
        cc_id(f.out, "g_v", operand); cc_text(f.out, ";\n"); return result;
    }
    if n.kind == N_RESULT {
        let mark = f.receiving.len;
        if f.receiver >= 0 && f.active_node == node {
            f.receiving.push(CcReceiving { ordinal: n.integer, destination: f.receiver, call: n.left });
        }
        let tuple = cc_expr(p, f, n.left);
        if tuple < 0 {
            f.receiving.resize(mark); if !cc_diverges(p, n.left) { cc_fail(p, n.left, "c: result producer has no natural values"); } return -1;
        }
        let result = cc_tuple_value(p, f, tuple, p.nodes[n.left].type_id, n.integer);
        f.receiving.resize(mark); return result;
    }
    if n.kind == N_BINARY { return cc_binary(p, f, node); }
    if n.kind == N_CAST { return cc_cast(p, f, node); }
    if n.kind == N_CALL { return cc_call(p, f, node); }
    if n.kind == N_BLOCK { return cc_block(p, f, node); }
    if n.kind == N_ARRAY || n.kind == N_FILL { return cc_array(p, f, node); }
    if n.kind == N_RECORD { return cc_record(p, f, node); }
    if n.kind == N_TUPLE {
        var target = -1;
        if f.receiver >= 0 && f.active_node == node && cc_queue_same(p, f.destinations[f.receiver].type_id, n.type_id) { target = f.destinations[f.receiver].header; f.active_node = -1; }
        return cc_values(p, f, n.first, n.type_id, target);
    }
    if n.kind == N_FUNCTION_VALUE { return cc_closure(p, f, node, n.type_id); }
    if n.kind == N_SLICE {
        let base = cc_base(p, f, n.left); var array = p.nodes[n.left].type_id;
        if cc_kind(p, array) == TY_REF { array = p.types[array].element; }
        let length = cc_temp(p, f, TYPE_I64); cc_set(f, length); cc_text(f.out, "g_len("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, array, false); cc_text(f.out, ");\n");
        var low = cc_temp(p, f, TYPE_I64); var high = length;
        if n.right >= 0 { low = cc_to(p, f, n.right, TYPE_I64); }
        if n.third >= 0 { high = cc_to(p, f, n.third, TYPE_I64); }
        if (n.flags & F_FROM_END) != 0 { cc_set(f, low); cc_id(f.out, "g_v", length); cc_text(f.out, "-"); cc_id(f.out, "g_v", low); cc_text(f.out, ";\n"); }
        if (n.flags & F_TO_END) != 0 { cc_set(f, high); cc_id(f.out, "g_v", length); cc_text(f.out, "-"); cc_id(f.out, "g_v", high); cc_text(f.out, ";\n"); }
        cc_text(f.out, "if("); cc_id(f.out, "g_v", low); cc_text(f.out, "<0||"); cc_id(f.out, "g_v", high); cc_text(f.out, "<"); cc_id(f.out, "g_v", low); cc_text(f.out, "||"); cc_id(f.out, "g_v", high); cc_text(f.out, ">"); cc_id(f.out, "g_v", length); cc_text(f.out, ")g_panic(\"slice bounds out of range\");\n");
        let result = cc_temp(p, f, n.type_id); cc_set(f, result); cc_text(f.out, "(GSlice){g_element("); cc_id(f.out, "g_v", base); cc_text(f.out, ","); cc_array_args(p, f.out, array); cc_text(f.out, ","); cc_id(f.out, "g_v", low); cc_text(f.out, ",1),"); cc_id(f.out, "g_v", high); cc_text(f.out, "-"); cc_id(f.out, "g_v", low); cc_text(f.out, "};\n"); return result;
    }
    if n.kind == N_IF {
        let condition = cc_truth(p, f, n.left); let result = cc_result_temp(p, f, node, n.type_id);
        cc_text(f.out, "if("); cc_id(f.out, "g_v", condition); cc_text(f.out, "){\n");
        if result >= 0 {
            let destination = cc_temporary_ref(f, result); cc_construct_into(p, f, n.right, n.type_id, destination, cc_value_form(p, n.type_id));
        }
        else { cc_expr(p, f, n.right); } cc_text(f.out, "}else{\n");
        if n.third >= 0 {
            if result >= 0 {
                let destination = cc_temporary_ref(f, result); cc_construct_into(p, f, n.third, n.type_id, destination, cc_value_form(p, n.type_id));
            }
            else { cc_expr(p, f, n.third); }
        }
        cc_text(f.out, "}\n"); return result;
    }
    if n.kind == N_LOOP || n.kind == N_FOR || n.kind == N_WHILE { return cc_loop(p, f, node); }
    if n.kind == N_MATCH { return cc_match(p, f, node); }
    if n.kind == N_RETURN { cc_return(p, f, node); return -1; }
    if n.kind == N_BREAK || n.kind == N_CONTINUE {
        var index = f.exits.len - 1;
        while index >= 0 && (n.symbol >= 0 && f.exits[index].node != n.symbol ||
              n.kind == N_CONTINUE && f.exits[index].again < 0) { index--; }
        if index < 0 { cc_fail(p, node, "c: jump has no enclosing loop or early block"); return -1; }
        let exit = f.exits[index];
        if n.left >= 0 && exit.result >= 0 {
            var value = -1;
            let destination = cc_temporary_ref(f, exit.result);
            if cc_kind(p, exit.type_id) == TY_TUPLE && p.nodes[n.left].next >= 0 { value = cc_values(p, f, n.left, exit.type_id, destination); }
            else { value = cc_construct_into(p, f, n.left, exit.type_id, destination); }
            if value >= 0 { cc_store(p, f, destination, value, exit.type_id); }
        } else if n.left >= 0 { cc_values(p, f, n.left, TYPE_VOID); }
        var label = exit.done; var mark = exit.regions; if n.kind == N_CONTINUE { label = exit.again; mark = exit.again_regions; }
        cc_restore(f, mark);
        if exit.publications >= 0 { cc_text(f.out, "g_publication_top="); cc_id(f.out, "g_scope_publications", exit.publications); cc_text(f.out, ";\n"); }
        cc_id(f.out, "goto g_label", label); cc_text(f.out, ";\n"); return -1;
    }
    if n.kind == N_VARIABLE { cc_variable(p, f, node); return -1; }
    if n.kind == N_ASSIGN || n.kind == N_MULTI_ASSIGN { cc_assignment(p, f, node); return -1; }
    if n.kind == N_FUNCTION || n.kind == N_EMPTY { return -1; }
    if n.kind == N_EXPR_STMT { cc_expr(p, f, n.left); return -1; }
    cc_fail(p, node, "c: checked syntax has no native lowering"); return -1;
}

fn cc_param_symbol(p: Program&, function: i64, index: i64) -> i64 {
    var param = p.nodes[function].first; var at = 0;
    while param >= 0 { if at == index { return p.nodes[param].symbol; } at++; param = p.nodes[param].next; } return -1;
}
fn cc_extern_name(p: Program&, function: i64) -> u8[:] {
    let n = p.nodes[function];
    if n.integer >= 0 && n.integer < p.tokens.len && p.tokens[n.integer].kind == T_STRLIT {
        let t = p.tokens[n.integer]; return p.text[t.text_start..t.text_start + t.text_len];
    }
    return token_text(p, n.token);
}
fn cc_param(p: Program&, out: u8[>..]&, function: i64, index: i64) { cc_id(out, "g_s", cc_param_symbol(p, function, index)); }
fn cc_runtime_extern(name: const u8[:]) -> const u8[:] {
    if same_bytes(name, "gs_find_any") { return "g_find_any"; }
    if same_bytes(name, "gs_find_pair") { return "g_find_pair"; }
    if same_bytes(name, "gs_mul_add") { return "g_mul_add"; }
    if same_bytes(name, "gs_mul_addf") { return "g_mul_addf"; }
    for math_name in ["sqrt", "sqrtf", "sin", "sinf", "cos", "cosf", "tan", "tanf",
                      "asin", "asinf", "acos", "acosf", "atan", "atanf", "atan2", "atan2f",
                      "exp", "expf", "log", "logf", "log2", "log2f", "log10", "log10f", "pow", "powf"] {
        if name.len == math_name.len + 3 && same_bytes(name[0..3], "gs_") && same_bytes(name[3..], math_name) { return math_name; }
    }
    return "";
}
fn cc_emit_extern(p: Program&, out: u8[>..]&, function: i64) {
    let name = cc_extern_name(p, function); let result_type = cc_function_result(p, function);
    let value = cc_kind(p, result_type) != TY_VOID;
    for exported, id in p.nodes {
        if id == function || (exported.flags & F_EXPORT) == 0 || !cc_emittable(p, id) { continue; }
        if !same_bytes(name, cc_extern_name(p, id)) { continue; }
        if value && !cc_result_indirect(p, result_type) { cc_text(out, "return "); }
        cc_id(out, "g_fn", id); cc_text(out, "(NULL,g_base");
        if cc_receives(p, result_type) { cc_text(out, ",g_into"); }
        var param = p.nodes[function].first; var index = 0;
        while param >= 0 { cc_text(out, ","); if cc_indirect(p, p.nodes[param].type_id) { cc_text(out, "&"); } cc_param(p, out, function, index); index++; param = p.nodes[param].next; }
        cc_text(out, ");\n"); if cc_tuple_channels(p, result_type) { cc_text(out, "return;\n"); } return;
    }
    if value && cc_tuple_channels(p, result_type) { cc_text(out, "g_foreign="); }
    else if value { if cc_indirect(p, result_type) { cc_text(out, "*g_into="); } else { cc_text(out, "return "); } }
    let runtime = cc_runtime_extern(name);
    if runtime.len > 0 {
        cc_text(out, runtime); cc_text(out, "(");
        var param = p.nodes[function].first; var index = 0;
        while param >= 0 {
            if index > 0 { cc_text(out, ","); }
            cc_param(p, out, function, index); index++; param = p.nodes[param].next;
        }
        cc_text(out, ");\n"); return;
    }
    if same_bytes(name, "gs_os_read_file") || same_bytes(name, "gs_os_list_dir") || same_bytes(name, "gs_os_getenv") {
        if same_bytes(name, "gs_os_read_file") { cc_text(out, "g_os_read_file("); }
        else if same_bytes(name, "gs_os_list_dir") { cc_text(out, "g_os_list("); }
        else { cc_text(out, "g_os_env("); }
        cc_param(p, out, function, 0); cc_text(out, ","); cc_param(p, out, function, 1); cc_text(out, ");\n"); return;
    }
    if same_bytes(name, "gs_os_write_file") || same_bytes(name, "gs_os_append_file") || same_bytes(name, "gs_os_write_file_atomic") {
        if same_bytes(name, "gs_os_write_file_atomic") { cc_text(out, "g_os_write_atomic("); }
        else { cc_text(out, "g_os_write_file("); }
        cc_param(p, out, function, 0); cc_text(out, ","); cc_param(p, out, function, 1);
        if same_bytes(name, "gs_os_write_file") { cc_text(out, ",\"wb\""); }
        if same_bytes(name, "gs_os_append_file") { cc_text(out, ",\"ab\""); }
        cc_text(out, ");\n"); return;
    }
    if same_bytes(name, "gs_os_file_exists") || same_bytes(name, "gs_os_is_dir") {
        cc_text(out, "g_os_kind("); cc_param(p, out, function, 0); cc_text(out, ")==");
        if same_bytes(name, "gs_os_is_dir") { cc_text(out, "2;\n"); } else { cc_text(out, "1;\n"); } return;
    }
    if same_bytes(name, "gs_os_remove_file") || same_bytes(name, "gs_os_remove_dir") || same_bytes(name, "gs_os_make_dir") {
        cc_text(out, "g_os_path_op("); cc_param(p, out, function, 0); cc_text(out, ",");
        if same_bytes(name, "gs_os_remove_file") { cc_text(out, "0"); }
        else if same_bytes(name, "gs_os_remove_dir") { cc_text(out, "1"); } else { cc_text(out, "2"); }
        cc_text(out, ");\n"); return;
    }
    if same_bytes(name, "gs_os_rename_file") {
        cc_text(out, "g_os_rename("); cc_param(p, out, function, 0); cc_text(out, ","); cc_param(p, out, function, 1); cc_text(out, ");\n"); return;
    }
    if same_bytes(name, "gs_os_read_line") || same_bytes(name, "gs_os_read_stdin") || same_bytes(name, "gs_os_resource_dir") {
        if same_bytes(name, "gs_os_read_line") { cc_text(out, "g_os_line("); }
        else if same_bytes(name, "gs_os_read_stdin") { cc_text(out, "g_os_stdin("); } else { cc_text(out, "g_os_resource("); }
        cc_param(p, out, function, 0); cc_text(out, ");\n"); return;
    }
    if same_bytes(name, "gs_os_write_stdout") || same_bytes(name, "gs_os_write_stderr") {
        cc_text(out, "fwrite(g_address("); cc_param(p, out, function, 0); cc_text(out, ".base),1,(size_t)"); cc_param(p, out, function, 0); cc_text(out, ".len,");
        if same_bytes(name, "gs_os_write_stderr") { cc_text(out, "stderr"); } else { cc_text(out, "stdout"); } cc_text(out, ");\n"); return;
    }
    if same_bytes(name, "gs_os_flush_stdout") { cc_text(out, "fflush(stdout);\n"); return; }
    if same_bytes(name, "gs_os_arg_count") { cc_text(out, "g_argc;\n"); return; }
    if same_bytes(name, "gs_os_arg") {
        cc_text(out, "g_os_arg("); cc_param(p, out, function, 0); cc_text(out, ","); cc_param(p, out, function, 1); cc_text(out, ");\n"); return;
    }
    if same_bytes(name, "gs_os_time_ns") { cc_text(out, "g_os_time(0);\n"); return; }
    if same_bytes(name, "gs_os_clock_ns") { cc_text(out, "g_os_time(1);\n"); return; }
    if same_bytes(name, "gs_os_sleep_ms") { cc_text(out, "g_os_sleep("); cc_param(p, out, function, 0); cc_text(out, ");\n"); return; }
    if same_bytes(name, "gs_os_random_u64") { cc_text(out, "g_os_random();\n"); return; }
    if same_bytes(name, "gs_trim_memory") { cc_text(out, "g_trim_memory();\n"); return; }
    if same_bytes(name, "gs_clz") || same_bytes(name, "gs_ctz") || same_bytes(name, "gs_popcount") {
        if same_bytes(name, "gs_clz") { cc_text(out, "g_clz("); }
        else if same_bytes(name, "gs_ctz") { cc_text(out, "g_ctz("); } else { cc_text(out, "__builtin_popcountll("); }
        cc_param(p, out, function, 0); cc_text(out, ");\n"); return;
    }
    // Foreign C signatures use raw pointers and raw pointer/length slices.
    // Runtime-owned builder references have a distinct ABI and are rejected.
    if value && !cc_tuple_channels(p, result_type) && cc_kind(p, result_type) != TY_TUPLE { cc_text(out, "("); cc_type(out, result_type); cc_text(out, ")"); }
    cc_text(out, "((");
    if cc_kind(p, result_type) == TY_REF { cc_text(out, "void*"); }
    else { cc_type(out, result_type); }
    cc_text(out, " (*) ("); var param = p.nodes[function].first; var index = 0;
    while param >= 0 {
        if index > 0 { cc_text(out, ","); }
        let type_id = p.nodes[param].type_id;
        if cc_kind(p, type_id) == TY_REF {
            let element = p.types[type_id].element;
            if cc_owner(p, element) { cc_fail(p, function, "c: foreign builder reference ABI requires a runtime adapter"); }
            cc_text(out, "void*");
        } else if cc_kind(p, type_id) == TY_SLICE { cc_text(out, "GForeignSlice"); }
        else { cc_type(out, type_id); }
        param = p.nodes[param].next; index++;
    }
    if index == 0 { cc_text(out, "void"); }
    cc_text(out, "))g_external(");
    if p.nodes[function].aux >= 0 && p.nodes[function].aux < p.tokens.len && p.tokens[p.nodes[function].aux].kind == T_STRLIT {
        let t = p.tokens[p.nodes[function].aux]; cc_bytes(out, p.text[t.text_start..t.text_start + t.text_len]);
    } else { cc_text(out, "NULL"); }
    cc_text(out, ","); cc_bytes(out, name); cc_text(out, "))("); param = p.nodes[function].first; index = 0;
    while param >= 0 {
        if index > 0 { cc_text(out, ","); }
        let kind = cc_kind(p, p.nodes[param].type_id);
        if kind == TY_REF { cc_text(out, "g_address("); cc_param(p, out, function, index); cc_text(out, ")"); }
        else if kind == TY_SLICE { cc_text(out, "g_foreign_slice("); cc_param(p, out, function, index); cc_text(out, ")"); }
        else { cc_param(p, out, function, index); }
        index++; param = p.nodes[param].next;
    }
    cc_text(out, ");\n");
    if cc_kind(p, result_type) == TY_REF || cc_kind(p, result_type) == TY_SLICE {
        cc_fail(p, function, "c: foreign reference return requires explicit ownership adaptation");
    }
}
fn cc_emit_signature(p: Program&, out: u8[>..]&, function: i64) {
    cc_text(out, "static "); if cc_result_indirect(p, cc_function_result(p, function)) { cc_text(out, "void"); } else { cc_type(out, cc_function_result(p, function)); } cc_id(out, " g_fn", function); cc_text(out, "(GClosure *g_env,int64_t g_base");
    let result = cc_function_result(p, function);
    if cc_receives(p, result) { cc_text(out, ","); if cc_tuple_channels(p, result) { cc_text(out, "GRef *g_into"); } else { cc_type(out, result); cc_text(out, " *g_into"); } }
    var param = p.nodes[function].first;
    while param >= 0 {
        cc_text(out, ","); cc_type(out, p.nodes[param].type_id);
        if cc_indirect(p, p.nodes[param].type_id) { cc_text(out, " *"); cc_id(out, "g_parameter_", p.nodes[param].symbol); }
        else if cc_relative_cell(p, p.nodes[param].type_id) { cc_text(out, " "); cc_id(out, "g_parameter_", p.nodes[param].symbol); }
        else { cc_text(out, " "); cc_id(out, "g_s", p.nodes[param].symbol); }
        if cc_flat_image_reference(p, p.nodes[param].type_id) { cc_text(out, ",GRef "); cc_id(out, "g_image_owner_", p.nodes[param].symbol); }
        param = p.nodes[param].next;
    }
    cc_text(out, ")");
}
fn cc_parameter_aliases(p: Program&, out: u8[>..]&, function: i64, end: bool = false) {
    var param = p.nodes[function].first;
    while param >= 0 {
        let n = p.nodes[param];
        if cc_flat_image_reference(p, n.type_id) && !end {
            cc_text(out, "if(((GImage*)g_address("); cc_id(out, "g_image_owner_", n.symbol); cc_text(out, "))->base!=g_address("); cc_id(out, "g_s", n.symbol); cc_text(out, "))g_panic(\"image reference owner mismatch\");\n");
            cc_text(out, "(void)g_image_span(*(GImage*)g_address("); cc_id(out, "g_image_owner_", n.symbol); cc_text(out, "));\n");
        }
        if cc_indirect(p, n.type_id) {
            if end { cc_undef(out, "g_s", n.symbol); }
            else { cc_text(out, "#define "); cc_id(out, "g_s", n.symbol); cc_text(out, " (*"); cc_id(out, "g_parameter_", n.symbol); cc_text(out, ")\n"); }
        } else if cc_relative_cell(p, n.type_id) && !end {
            cc_storage_type(p, out, n.type_id); cc_text(out, " "); cc_id(out, "g_s", n.symbol); cc_text(out, "={0};\ng_relative_store(g_ref(&"); cc_id(out, "g_s", n.symbol);
            cc_text(out, "),"); cc_id(out, "g_parameter_", n.symbol); cc_text(out, ","); cc_number(out, p.types[n.type_id].length_storage); cc_text(out, ",");
            if (p.types[n.type_id].flags & TF_OPTIONAL) != 0 { cc_text(out, "1"); } else { cc_text(out, "0"); }
            cc_text(out, ","); cc_relative_origin(p, out, n.type_id); cc_text(out, ","); cc_location(p, out, param); cc_text(out, ");\n");
        }
        param = n.next;
    }
}
fn cc_emit_function(p: Program&, out: u8[>..]&, function: i64, plans: RegionFunction[>..]&, calls: RegionCall[>..]&, indices: i64[>..]&) {
    let n = p.nodes[function]; var checked = n.first;
    while checked >= 0 {
        let type_id = p.nodes[checked].type_id;
        if cc_relative_cell(p, type_id) && cc_flat_relative_image(p, p.types[type_id].element) { cc_fail(p, checked, "c: encoded relative image parameter requires physical owner adaptation"); }
        checked = p.nodes[checked].next;
    }
    cc_emit_signature(p, out, function); cc_text(out, " {\n"); cc_parameter_aliases(p, out, function);
    if (n.flags & (F_EXTERN | F_EXPORT | F_THREAD)) != 0 {
        var parameter = n.first;
        while parameter >= 0 {
            if cc_flat_image_abi_pending(p, p.nodes[parameter].type_id) { cc_fail(p, function, "c: relative image foreign/export/thread ABI needs explicit adaptation"); }
            parameter = p.nodes[parameter].next;
        }
        if cc_flat_image_abi_pending(p, cc_function_result(p, function)) { cc_fail(p, function, "c: relative image foreign/export/thread result ABI needs explicit adaptation"); }
    }
    if (n.flags & F_EXTERN) != 0 {
        var parameter = n.first;
        while parameter >= 0 { if cc_relative_cell(p, p.nodes[parameter].type_id) { cc_fail(p, function, "c: encoded foreign reference ABI needs adaptation"); } parameter = p.nodes[parameter].next; }
        if cc_relative_cell(p, cc_function_result(p, function)) { cc_fail(p, function, "c: encoded foreign reference ABI needs adaptation"); }
        let result = cc_function_result(p, function);
        if cc_tuple_channels(p, result) { cc_type(out, result); cc_text(out, " g_foreign={};\n"); }
        cc_emit_extern(p, out, function);
        if cc_tuple_channels(p, result) {
            var field = p.types[result].first; var ordinal = 0;
            while field >= 0 {
                cc_id(out, "g_publish_", p.nodes[field].type_id); cc_text(out, "(g_address(g_into["); cc_number(out, ordinal); cc_text(out, "]),&g_foreign"); cc_id(out, ".f", ordinal); cc_text(out, ");\n");
                field = p.nodes[field].next; ordinal++;
            }
        }
        cc_text(out, "}\n"); cc_parameter_aliases(p, out, function, true); return; }
    var body: u8[>..] = []; var exits: CcExit[>..] = []; var work: i64[>..] = []; var temp_regions: i64[>..] = []; var destinations: CcDestination[>..] = []; var receiving: CcReceiving[>..] = []; var indirect: i64[>..] = []; var fills: CcFill[>..] = []; var channels: CcChannels[>..] = []; var cursors: CcCursor[>..] = [];
    let result_type = cc_function_result(p, function);
    var f = CcBody { out: body, exits: exits, work: work, function: function, result_type: result_type,
        function_index: indices[function], calls: calls, indices: indices, temp_regions: temp_regions, destinations: destinations, receiving: receiving, fills: fills, indirect: indirect, channels: channels, cursors: cursors };
    let returns = cc_kind(p, result_type) != TY_VOID;
    let nonlocal = (n.flags & F_NONLOCAL) != 0;
    if returns && !cc_tuple_channels(p, result_type) {
        if cc_result_indirect(p, result_type) { cc_text(body, "#define g_result (*g_into)\n"); }
        else {
            if nonlocal { cc_text(body, "volatile "); }
            cc_type(body, result_type); cc_text(body, " g_result="); cc_zero_initializer(p, body, result_type); cc_text(body, ";\n");
            if cc_region_width(p, result_type) > 0 { cc_text(body, "memcpy((void*)&g_result,g_into,sizeof g_result);\n"); }
        }
    }
    var result_ref = -1;
    if returns && (cc_tuple_channels(p, result_type) || cc_region_width(p, result_type) > 0 || cc_result_location(p, result_type)) {
        result_ref = cc_ref_temp(f); cc_set(f, result_ref);
        if cc_tuple_channels(p, result_type) {
            cc_text(body, "g_ref(g_into);\n"); f.channels.push(CcChannels { value: -1, address: result_ref });
        } else { cc_text(body, "g_ref((void*)&g_result);\n"); }
        f.result_ref = result_ref;
        if !cc_tuple_channels(p, result_type) && cc_region_width(p, result_type) > 0 {
            let links = f.serial; f.serial++;
            cc_id(body, "GPublication g_result_links", links); cc_text(body, "["); cc_number(body, cc_region_width(p, result_type)); cc_text(body, "];\n");
            cc_id(body, "g_map_", result_type); cc_text(body, "(g_ref((void*)&g_result),g_ref(g_into),"); cc_id(body, "g_result_links", links); cc_text(body, ");\n");
        }
        cc_bind_named_results(p, f, function, result_type, result_ref);
    }
    if nonlocal {
        cc_text(body, "GReturnFrame g_frame={0};g_frame.parent=g_return_top;g_frame.function="); cc_number(body, function); cc_text(body, ";g_frame.activation=&g_activation;\n");
        if returns {
            if cc_tuple_channels(p, result_type) {
                cc_text(body, "g_frame.result=g_into;g_frame.size="); cc_number(body, p.types[result_type].count * 8); cc_text(body, ";g_frame.publish="); cc_id(body, "g_publish_channels_", result_type);
            } else {
                cc_text(body, "g_frame.result=(void*)&g_result;g_frame.size=sizeof g_result;g_frame.publish="); cc_id(body, "g_publish_", result_type);
            }
            cc_text(body, ";\n");
        }
        cc_text(body, "g_return_top=&g_frame;if(setjmp(g_frame.jump))goto g_return;\n");
    }
    cc_text(body, "{\n");
    for symbol, id in p.symbols {
        if symbol.owner != function || (symbol.flags & (S_PARAMETER | S_FUNCTION | S_TYPE)) != 0 { continue; }
        if symbol.type_id < 0 || !cc_concrete(p, symbol.type_id) { cc_fail(p, symbol.node, "c: local variable lacks a concrete type"); continue; }
        var named = -1;
        if cc_result_location(p, symbol.type_id) { for receiving in f.receiving { if receiving.symbol == id { named = f.destinations[receiving.destination].header; } } }
        if named >= 0 { cc_alias_symbol(p, body, id, named); }
        else if cc_indirect(p, symbol.type_id) { cc_fixed(body, symbol.type_id, "g_s", id); }
        else { cc_storage_type(p, body, symbol.type_id); cc_text(body, " "); cc_id(body, "g_s", id); cc_text(body, "="); cc_zero_initializer(p, body, symbol.type_id); cc_text(body, ";\n"); }
    }
    if n.right >= 0 {
        var result = -1;
        if result_ref >= 0 { result = cc_construct_into(p, f, n.right, result_type, result_ref); }
        else { result = cc_expr(p, f, n.right); }
        if returns && result >= 0 {
            cc_return_store(p, f, result, result_type);
        }
    } else { cc_fail(p, function, "c: non-extern function has no body"); }
    cc_text(body, "}\ng_return:;\n");
    if nonlocal { cc_text(body, "g_return_top=g_frame.parent;\n"); }
    if returns && !cc_tuple_channels(p, result_type) && cc_region_width(p, result_type) > 0 && !cc_result_location(p, result_type) { cc_text(body, "memcpy(g_into,(const void*)&g_result,sizeof g_result);\n"); }
    cc_text(body, "g_activation_leave(&g_activation);\n");
    if returns && !cc_result_indirect(p, result_type) { cc_text(body, "return g_result;\n"); } else { cc_text(body, "return;\n"); }
    plans[indices[function]].own = f.region_peak;
    cc_text(out, "g_stack_check();\nGWatermark g_watermarks["); cc_number(out, f.region_peak + 1); cc_text(out, "];GActivation g_activation;\n");
    cc_text(out, "g_activation_enter(&g_activation,g_base,"); cc_number(out, f.region_peak); cc_text(out, ",g_watermarks);\n");
    cc_text(out, body); cc_text(out, "}\n");
    if !cc_tuple_channels(p, result_type) && cc_result_indirect(p, result_type) { cc_text(out, "#undef g_result\n"); }
    for id in indirect { cc_undef(out, "g_v", id); }
    for symbol, id in p.symbols {
        if symbol.owner == function && (symbol.flags & (S_PARAMETER | S_FUNCTION | S_TYPE)) == 0 && (cc_indirect(p, symbol.type_id) || cc_result_location(p, symbol.type_id)) { cc_undef(out, "g_s", id); }
    }
    cc_parameter_aliases(p, out, function, true);
}
fn cc_emit_export(p: Program&, out: u8[>..]&, function: i64) {
    let n = p.nodes[function]; if (n.flags & F_EXPORT) == 0 { return; }
    let result = cc_function_result(p, function);
    cc_type(out, cc_function_result(p, function)); cc_id(out, " g_export", function); cc_text(out, "(");
    var param = n.first; var index = 0;
    while param >= 0 {
        if index > 0 { cc_text(out, ","); } cc_type(out, p.nodes[param].type_id); cc_text(out, " "); cc_id(out, "g_s", p.nodes[param].symbol);
        param = p.nodes[param].next; index++;
    }
    if index == 0 { cc_text(out, "void"); }
    cc_text(out, ") __asm__("); cc_bytes(out, cc_extern_name(p, function)); cc_text(out, ");\n");
    cc_type(out, cc_function_result(p, function)); cc_id(out, " g_export", function); cc_text(out, "("); param = n.first; index = 0;
    while param >= 0 {
        if index > 0 { cc_text(out, ","); } cc_type(out, p.nodes[param].type_id); cc_text(out, " "); cc_id(out, "g_s", p.nodes[param].symbol);
        param = p.nodes[param].next; index++;
    }
    if index == 0 { cc_text(out, "void"); } cc_text(out, "){g_initialize();\n");
    if cc_result_indirect(p, result) { cc_fixed(out, result, "g_export_result", function); }
    if cc_tuple_channels(p, result) {
        cc_id(out, "GRef g_export_channels", function); cc_text(out, "[]={"); var field = p.types[result].first; var ordinal = 0;
        while field >= 0 {
            if ordinal > 0 { cc_text(out, ","); } cc_text(out, "g_ref(&"); cc_id(out, "g_export_result", function); cc_id(out, ".f", ordinal); cc_text(out, ")");
            field = p.nodes[field].next; ordinal++;
        }
        cc_text(out, "};\n");
    } else if !cc_result_indirect(p, result) && cc_kind(p, result) != TY_VOID { cc_text(out, "return "); }
    if cc_region_width(p, cc_function_result(p, function)) > 0 { cc_fail(p, function, "c: exported owning results need a caller destination"); }
    cc_id(out, "g_fn", function); cc_text(out, "(NULL,g_global_regions");
    if cc_tuple_channels(p, result) { cc_text(out, ","); cc_id(out, "g_export_channels", function); }
    else if cc_result_indirect(p, result) { cc_text(out, ",&"); cc_id(out, "g_export_result", function); }
    param = n.first;
    while param >= 0 { cc_text(out, ","); if cc_indirect(p, p.nodes[param].type_id) { cc_text(out, "&"); } cc_id(out, "g_s", p.nodes[param].symbol); param = p.nodes[param].next; }
    cc_text(out, ");"); if cc_result_indirect(p, result) { cc_text(out, "return "); cc_id(out, "g_export_result", function); cc_text(out, ";"); } cc_text(out, "}\n");
    if cc_result_indirect(p, result) { cc_undef(out, "g_export_result", function); }
}
fn cc_emittable(p: Program&, function: i64) -> bool {
    let n = p.nodes[function];
    if n.kind != N_FUNCTION && n.kind != N_FUNCTION_VALUE { return false; }
    if (n.flags & F_GENERIC) != 0 || (n.flags & F_CHECKED) == 0 || (n.flags & F_REACHABLE) == 0 || n.type_id < 0 || cc_kind(p, n.type_id) != TY_FN { return false; }
    if !cc_concrete(p, p.types[n.type_id].element) { return false; }
    var param = n.first;
    while param >= 0 { if !cc_concrete(p, p.nodes[param].type_id) { return false; } param = p.nodes[param].next; }
    return true;
}
fn generate_c(p: Program&, out: u8[>..]&) {
    if p.diagnostics.len > 0 { return; }
    if p.pointer_bytes != 8 { diagnose_at(p, 0, 0, 0, "c: native layouts require pointer_bytes = 8"); return; }
    cc_collect_captures(p);
    var used: bool[>..] = []; used.resize(p.types.len, false); var type_work: i64[>..] = [];
    cc_used_types(p, used, type_work);
    var plans: RegionFunction[>..] = []; var calls: RegionCall[>..] = []; var indices: i64[>..] = [];
    indices.resize(p.nodes.len, -1);
    for n, node in p.nodes {
        if !cc_emittable(p, node) { continue; }
        indices[node] = plans.len; plans.push(RegionFunction { node: node, entry: true });
    }
    let initializer = plans.len; plans.push(RegionFunction { entry: true });
    var global_count = 0;
    for symbol, s in p.symbols { if (symbol.flags & S_GLOBAL) != 0 { global_count += cc_region_width(p, symbol.type_id); if cc_pool_mode(p, s) > 0 { global_count++; } } }
    let threads = cc_threads_used(p); let images = cc_images_used(p); let begin = out.len;
    cc_text(out, "#define _GNU_SOURCE 1\n"); if threads { cc_text(out, "#define GS_NEED_THREADS 1\n"); } cc_text(out, cc_runtime_header); cc_text(out, cc_runtime_impl); cc_text(out, cc_runtime_threads);
    cc_text(out, cc_runtime); cc_text(out, cc_runtime_relative); cc_text(out, cc_runtime_pools); cc_text(out, cc_runtime_extra);
    if images { cc_text(out, cc_runtime_images); } if threads { cc_text(out, cc_runtime_workers); }
    cc_text(out, "static void g_initialize(void);static int g_initialized;static int64_t g_global_regions;\n"); cc_pool_origins(p, out); cc_emit_types(p, out, used);
    for t, id in p.types {
        if !used[id] { continue; }
        if t.kind != TY_VOID && cc_concrete(p, id) { cc_emit_init(p, out, id); cc_emit_map(p, out, id); cc_emit_store(p, out, id); }
        cc_emit_clone(p, out, id); cc_emit_equal(p, out, id); cc_emit_print(p, out, id); cc_emit_nested(p, out, id);
    }
    if images {
        cc_image_emit(p, out, used);
        if threads { var static_types: bool[>..] = []; cc_thread_static_types(p, static_types); cc_global_image_emit(p, out, static_types); }
    }
    for t, type_id in p.types {
        if !used[type_id] || t.kind != TY_TUPLE { continue; }
        cc_id(out, "static void g_publish_channels_", type_id); cc_text(out, "(void *p,const void *source){GRef *a=p;const GRef *b=source;\n");
        var field = t.first; var ordinal = 0;
        while field >= 0 {
            cc_text(out, "if(a["); cc_number(out, ordinal); cc_text(out, "]!=b["); cc_number(out, ordinal); cc_text(out, "])");
            cc_id(out, "g_publish_", p.nodes[field].type_id); cc_text(out, "(g_address(a["); cc_number(out, ordinal); cc_text(out, "]),g_address(b["); cc_number(out, ordinal); cc_text(out, "]));\n");
            field = p.nodes[field].next; ordinal++;
        }
        cc_text(out, "}\n");
    }
    for n, node in p.nodes { if cc_emittable(p, node) { cc_emit_signature(p, out, node); cc_text(out, ";\n"); } }
    if threads {
        cc_thread_emit_globals(p, out); cc_thread_emit_queues(p, out); cc_thread_emit_workers(p, out);
    } else {
    for s, symbol in p.symbols {
        if (s.flags & S_GLOBAL) == 0 { continue; }
        if s.type_id < 0 || !cc_concrete(p, s.type_id) { cc_fail(p, s.node, "c: global lacks a concrete type"); continue; }
        cc_text(out, "static "); cc_storage_type(p, out, s.type_id); cc_text(out, " "); cc_id(out, "g_s", symbol); cc_text(out, ";\n");
    }
    }
    cc_pool_origins(p, out, true);
    if images { cc_index_lengths(p, out, true); }
    for n, node in p.nodes { if cc_emittable(p, node) { cc_emit_function(p, out, node, plans, calls, indices); cc_emit_export(p, out, node); } }
    var initialization: u8[>..] = []; var exits: CcExit[>..] = []; var work: i64[>..] = []; var temp_regions: i64[>..] = []; var destinations: CcDestination[>..] = []; var receiving: CcReceiving[>..] = []; var indirect: i64[>..] = []; var fills: CcFill[>..] = []; var channels: CcChannels[>..] = []; var cursors: CcCursor[>..] = [];
    var f = CcBody { out: initialization, exits: exits, work: work, function_index: initializer, calls: calls, indices: indices,
        temp_regions: temp_regions, destinations: destinations, receiving: receiving, fills: fills, indirect: indirect, channels: channels, cursors: cursors };
    for s, symbol in p.symbols {
        if s.owner >= 0 || (s.flags & (S_GLOBAL | S_PARAMETER | S_FUNCTION | S_TYPE | S_BUILTIN)) != 0 ||
           !cc_storage_binding(p, symbol) || !cc_concrete(p, s.type_id) { continue; }
        if cc_indirect(p, s.type_id) { cc_fixed(initialization, s.type_id, "g_s", symbol); }
        else { cc_storage_type(p, initialization, s.type_id); cc_text(initialization, " "); cc_id(initialization, "g_s", symbol); cc_text(initialization, "="); cc_zero_initializer(p, initialization, s.type_id); cc_text(initialization, ";\n"); }
    }
    var slot = 0;
    for s, symbol in p.symbols {
        if (s.flags & S_GLOBAL) == 0 { continue; }
        let width = cc_region_width(p, s.type_id); if width == 0 { continue; }
        cc_id(initialization, "g_init_", s.type_id); cc_text(initialization, "(g_ref(&"); cc_id(initialization, "g_s", symbol);
        cc_text(initialization, "),"); cc_number(initialization, slot); cc_text(initialization, ");\n"); slot += width;
        let mode = cc_pool_mode(p, symbol);
        if mode > 0 {
            cc_id(initialization, "g_pool_init(g_ref(&g_s", symbol); cc_text(initialization, "),"); cc_number(initialization, slot); cc_text(initialization, ",");
            cc_number(initialization, mode); cc_text(initialization, ");\n"); slot++;
        }
    }
    for s in p.symbols { if (s.flags & S_GLOBAL) != 0 && s.node >= 0 { cc_variable(p, f, s.node); } }
    plans[initializer].own = f.region_peak;
    var stack: i64[>..] = []; var members: i64[>..] = [];
    var graph = RegionGraph { functions: plans, calls: calls, stack: stack, members: members };
    let bound = region_bound(p, graph, global_count); var snapshots = 0;
    if threads { for n, node in p.nodes { if cc_thread_function(p, node) { let count = cc_thread_regions(p, node); if count > snapshots { snapshots = count; } } } }
    cc_text(out, "static void g_initialize(void){if(g_initialized)return;g_initialized=1;g_global_regions="); cc_number(out, global_count);
    if threads { cc_text(out, ";g_worker_regions="); cc_number(out, bound); }
    cc_text(out, ";g_runtime_start(g_argc,g_argv,"); cc_number(out, bound); cc_text(out, ",");
    var worker_bound = 0; if threads { worker_bound = bound + snapshots; } cc_number(out, worker_bound);
    cc_text(out, ");int64_t g_base=g_global_regions;\n");
    if threads { cc_text(out, "gs_gl=&g_main_globals;\n"); cc_thread_emit_queues(p, out, true); }
    cc_text(out, "GWatermark g_watermarks["); cc_number(out, f.region_peak + 1); cc_text(out, "];GActivation g_activation;\n");
    cc_text(out, "g_activation_enter(&g_activation,g_base,"); cc_number(out, f.region_peak); cc_text(out, ",g_watermarks);\n");
    cc_text(out, initialization); cc_text(out, "g_activation_leave(&g_activation);}\n");
    for id in indirect { cc_undef(out, "g_v", id); }
    for s, symbol in p.symbols {
        if s.owner < 0 && (s.flags & (S_GLOBAL | S_PARAMETER | S_FUNCTION | S_TYPE | S_BUILTIN)) == 0 && cc_storage_binding(p, symbol) && cc_indirect(p, s.type_id) { cc_undef(out, "g_s", symbol); }
    }
    if !p.library {
        if p.entry < 0 || !cc_emittable(p, p.entry) { diagnose_at(p, 0, 0, 0, "c: program has no checked concrete entry function"); }
        else {
            cc_text(out, "int main(int argc,char **argv){g_argc=argc;g_argv=argv;g_initialize();");
            let result = cc_function_result(p, p.entry);
            if cc_kind(p, result) == TY_INT { cc_text(out, "return (int)"); }
            cc_id(out, "g_fn", p.entry); cc_text(out, "(NULL,g_global_regions);");
            if cc_kind(p, result) != TY_INT { cc_text(out, "return 0;"); } cc_text(out, "}\n");
        }
    }
    if p.diagnostics.len > 0 { out.resize(begin); }
}
let cc_runtime_extra = """
static GS_NORETURN void g_debug_fail(const char *file,int line,const char *format,...) {
    char buffer[512];va_list args;va_start(args,format);
    int count=vsnprintf(buffer,sizeof buffer,format,args);va_end(args);
    if(count<0)gs_panic("cannot format native runtime error");
    if((size_t)count<sizeof buffer)gs_abort_msg((const uint8_t*)buffer,count,file,line);
    char *message=g_alloc((size_t)count+1);va_start(args,format);vsnprintf(message,(size_t)count+1,format,args);va_end(args);
    gs_abort_msg((const uint8_t*)message,count,file,line);
}
static GS_NORETURN void g_abort_value(GArray message,const char *file,int line) {
    gs_abort_msg(message.data,message.len,file,line);
}
static __int128 g_signed_min(int bits) { return -((__int128)1<<(bits-1)); }
static __int128 g_signed_max(int bits) { return ((__int128)1<<(bits-1))-1; }
static int64_t g_checked_binary(int64_t a,int64_t b,int bits,int op,const char *file,int line) {
    __int128 r=0;const char *text="?";
    if(op==21){r=(__int128)a+b;text="+";}
    else if(op==22){r=(__int128)a-b;text="-";}
    else if(op==23){r=(__int128)a*b;text="*";}
    else if(op==24){if(!b)g_debug_fail(file,line,"division by zero");if(a==INT64_MIN&&b==-1)g_debug_fail(file,line,"integer overflow in division");r=a/b;text="/";}
    if(r<g_signed_min(bits)||r>g_signed_max(bits))g_debug_fail(file,line,"integer overflow (debug): %" PRId64 " %s %" PRId64 " at i%d",a,text,b,bits);
    return (int64_t)r;
}
static int64_t g_checked_neg(int64_t a,int bits,const char *file,int line) {
    __int128 r=-(__int128)a;
    if(r<g_signed_min(bits)||r>g_signed_max(bits))g_debug_fail(file,line,"integer overflow (debug): -(%" PRId64 ") at i%d",a,bits);
    return (int64_t)r;
}
static uint64_t g_unsigned_max(int bits) { if(bits==64)return UINT64_MAX;return (UINT64_C(1)<<bits)-1; }
static uint64_t g_checked_cast_i(int64_t v,int bits,int uns,const char *file,int line) {
    int bad=0;if(uns){if(v<0||(uint64_t)v>g_unsigned_max(bits))bad=1;}
    else if((__int128)v<g_signed_min(bits)||(__int128)v>g_signed_max(bits))bad=1;
    if(bad){char kind='i';if(uns)kind='u';g_debug_fail(file,line,"as conversion out of range (debug): %" PRId64 " as %c%d",v,kind,bits);}
    return (uint64_t)v;
}
static uint64_t g_checked_cast_u(uint64_t v,int bits,int uns,const char *file,int line) {
    uint64_t hi=g_unsigned_max(bits);if(!uns)hi=(uint64_t)g_signed_max(bits);
    if(v>hi){char kind='i';if(uns)kind='u';g_debug_fail(file,line,"as conversion out of range (debug): %" PRIu64 " as %c%d",v,kind,bits);}
    return v;
}
static void g_cast_float_fail(const char *why,double v,int f32,int bits,int uns,const char *file,int line) {
    uint8_t text[64];int64_t count;char kind='i';if(uns)kind='u';
    if(f32)count=gs_fmt_f32(text,(float)v);else count=gs_fmt_f64(text,v);text[count]=0;
    g_debug_fail(file,line,"as conversion %s (debug): %s as %c%d",why,(char*)text,kind,bits);
}
static uint64_t g_checked_cast_f(double v,int f32,int bits,int uns,const char *file,int line) {
    if(uns&&bits==64){
        if(!(v>=0&&v<18446744073709551616.0))g_cast_float_fail("out of range",v,f32,bits,uns,file,line);
        uint64_t value=(uint64_t)v;
        if((double)value!=v)g_cast_float_fail("changes the value",v,f32,bits,uns,file,line);
        return value;
    }
    if(!(v>=-9223372036854775808.0&&v<9223372036854775808.0))g_cast_float_fail("out of range",v,f32,bits,uns,file,line);
    int64_t value=(int64_t)v;int bad=0;
    if(uns){if(value<0||(uint64_t)value>g_unsigned_max(bits))bad=1;}
    else if((__int128)value<g_signed_min(bits)||(__int128)value>g_signed_max(bits))bad=1;
    if(bad)g_cast_float_fail("out of range",v,f32,bits,uns,file,line);
    if((double)value!=v)g_cast_float_fail("changes the value",v,f32,bits,uns,file,line);
    return (uint64_t)value;
}
static unsigned char *g_nullable_address(GRef r) { if(!r)return NULL;return g_address(r); }
static double g_float_literal(uint64_t bits) { double v; memcpy(&v,&bits,sizeof v); return v; }
static int64_t g_clz(uint64_t x) { if(!x) return 64; return __builtin_clzll(x); }
static int64_t g_ctz(uint64_t x) { if(!x) return 64; return __builtin_ctzll(x); }
static int g_os_path_op(GSlice path,int op) { char *s=g_path(path); if(!s) return 0; if(op==0) return unlink(s)==0; if(op==1) return rmdir(s)==0; if(mkdir(s,0777)==0) return 1; return errno==EEXIST && g_os_kind(path)==2; }
static int g_os_rename(GSlice from,GSlice to) { char *a=g_path(from),*b=g_path(to); if(!a || !b) return 0; return rename(a,b)==0; }
static int g_os_resource(GRef out) { char path[4096]; ssize_t n=readlink("/proc/self/exe",path,sizeof path); if(n<=0 || n==(ssize_t)sizeof path) return 0; while(n>0 && path[n-1]!='/') n--; if(!n) return 0; GArray a; memcpy(&a,g_address(out),sizeof a); g_bytes(&a,path,n); memcpy(g_address(out),&a,sizeof a); return 1; }
static int g_trim_memory(void) { return gs_trim_memory(); }
typedef struct { void *data; int64_t len; } GForeignSlice;
static GForeignSlice g_foreign_slice(GSlice s) { GForeignSlice r={g_address(s.base),s.len}; return r; }
static void *g_external(const char *library,const char *name) { void *handle=RTLD_DEFAULT; if(library) { handle=dlopen(library,RTLD_NOW|RTLD_LOCAL); if(!handle) g_panic(dlerror()); } void *p=dlsym(handle,name); if(!p) g_panic(dlerror()); return p; }
""";

fn cc_literal_array_args(p: Program&, out: u8[>..]&, type_id: i64, width: bool = true) {
    if cc_kind(p, type_id) != TY_SLICE { cc_array_args(p, out, type_id, width); return; }
    cc_text(out, "3,-1,0");
    if width { cc_text(out, ","); cc_number(out, cc_frame_size(p, p.types[type_id].element)); }
}
fn cc_equal_fields(p: Program&, out: u8[>..]&, type_id: i64, first: i64) {
    if cc_flat_relative_image(p, type_id) {
        out.append("const uint8_t *ac=a.base,*bc=b.base;\n"); var field = first;
        while field >= 0 {
            let n = p.nodes[field];
            if (n.flags & F_PAD) != 0 && n.aux == 0 { field = n.next; continue; }
            var width = n.aux;
            if (n.flags & F_PAD) == 0 {
                out.format("if(!g_equal_", n.type_id, "(g_physical_load_", n.type_id, "(ac,a.end),g_physical_load_", n.type_id, "(bc,b.end)))return 0;\n");
                width = cc_physical_cell_width(p, n.type_id);
            }
            out.format("ac=g_relative_cell_skip(ac,a.end,", width, ");bc=g_relative_cell_skip(bc,b.end,", width, ");\n"); field = n.next;
        }
        return;
    }
    if cc_image_type(p, type_id) {
        cc_text(out, "const uint8_t *ac=a.base,*bc=b.base;\n"); var field = first;
        while field >= 0 {
            let n = p.nodes[field];
            if (n.flags & F_PAD) != 0 { out.format("ac+=", n.aux, ";bc+=", n.aux, ";\n"); }
            else { out.format("if(!g_equal_", n.type_id, "(g_load_", n.type_id, "(g_ref(ac)),g_load_", n.type_id, "(g_ref(bc))))return 0;ac=g_physical_skip_", n.type_id, "(ac);bc=g_physical_skip_", n.type_id, "(bc);\n"); }
            field = n.next;
        }
        return;
    }
    var field = first;
    while field >= 0 {
        let n = p.nodes[field];
        if (n.flags & F_PAD) == 0 {
            if cc_relative_cell(p, n.type_id) {
                cc_text(out, "if(memcmp(g_address(g_offset(g_ref(&a),"); cc_number(out, cc_field_offset(p, type_id, field));
                cc_text(out, ")),g_address(g_offset(g_ref(&b),"); cc_number(out, cc_field_offset(p, type_id, field));
                cc_text(out, ")),"); cc_number(out, p.types[n.type_id].length_storage); cc_text(out, "))return 0;\n");
                field = n.next; continue;
            }
            cc_text(out, "if(!"); cc_id(out, "g_equal_", n.type_id); cc_text(out, "(");
            cc_id(out, "g_native_load_", n.type_id); cc_text(out, "(g_offset(g_ref(&a),"); cc_number(out, cc_field_offset(p, type_id, field)); cc_text(out, ")),");
            cc_id(out, "g_native_load_", n.type_id); cc_text(out, "(g_offset(g_ref(&b),"); cc_number(out, cc_field_offset(p, type_id, field)); cc_text(out, "))))return 0;\n");
        }
        field = n.next;
    }
}
fn cc_emit_equal(p: Program&, out: u8[>..]&, id: i64) {
    let t = p.types[id]; if !cc_concrete(p, id) || t.kind == TY_VOID { return; }
    cc_text(out, "static int "); cc_helper_name(p, out, "g_equal_", id); cc_text(out, "("); cc_helper_value(p, out, id, "a"); cc_text(out, ","); cc_helper_value(p, out, id, "b"); cc_text(out, "){\n"); cc_helper_alias(p, out, id, "a"); cc_helper_alias(p, out, id, "b");
    if t.kind == TY_ARRAY || t.kind == TY_SLICE {
        cc_text(out, "GRef ar=g_ref("); if cc_image_type(p, id) { cc_text(out, "a.base"); } else { cc_text(out, "&a"); } cc_text(out, "),br=g_ref("); if cc_image_type(p, id) { cc_text(out, "b.base"); } else { cc_text(out, "&b"); } cc_text(out, ");int64_t n=g_len(ar,"); cc_array_args(p, out, id, false); cc_text(out, ");if(n!=g_len(br,"); cc_array_args(p, out, id, false); cc_text(out, "))return 0;\n");
        if cc_size_class(p, t.element) == 1 {
            cc_text(out, "const uint8_t *ac=g_address(g_element(ar,"); cc_array_args(p, out, id); cc_text(out, ",0,1)),*bc=g_address(g_element(br,"); cc_array_args(p, out, id); cc_text(out, ",0,1));\n");
            out.format("for(int64_t i=0;i<n;i++){if(!g_equal_", t.element, "(g_load_", t.element, "(g_ref(ac)),g_load_", t.element, "(g_ref(bc))))return 0;ac=g_physical_skip_", t.element, "(ac);bc=g_physical_skip_", t.element, "(bc);}return 1;}\n");
            cc_helper_alias(p, out, id, "a", true); cc_helper_alias(p, out, id, "b", true); return;
        }
        cc_text(out, "for(int64_t i=0;i<n;i++){if(");
        if cc_relative_cell(p, t.element) {
            cc_text(out, "memcmp(g_address(g_element(ar,"); cc_array_args(p, out, id); cc_text(out, ",i,0)),g_address(g_element(br,");
            cc_array_args(p, out, id); cc_text(out, ",i,0)),"); cc_number(out, p.types[t.element].length_storage); cc_text(out, "))return 0;}return 1;\n");
            cc_text(out, "}\n"); cc_helper_alias(p, out, id, "a", true); cc_helper_alias(p, out, id, "b", true); return;
        }
        cc_text(out, "!"); cc_id(out, "g_equal_", t.element); cc_text(out, "("); cc_id(out, "g_load_", t.element); cc_text(out, "(g_element(ar,"); cc_array_args(p, out, id); cc_text(out, ",i,0)),");
        cc_id(out, "g_load_", t.element); cc_text(out, "(g_element(br,"); cc_array_args(p, out, id); cc_text(out, ",i,0))))return 0;}return 1;\n");
    } else if t.kind == TY_STRUCT && t.declaration >= 0 {
        cc_equal_fields(p, out, id, p.nodes[t.declaration].first); cc_text(out, "return 1;\n");
    } else if t.kind == TY_ENUM && t.declaration >= 0 {
        cc_text(out, "uint64_t tag=g_read_length("); if cc_image_type(p, id) { cc_text(out, "a.base,"); } else { cc_text(out, "&a,"); } cc_number(out, t.length_storage); cc_text(out, ");if(tag!=g_read_length("); if cc_image_type(p, id) { cc_text(out, "b.base,"); } else { cc_text(out, "&b,"); } cc_number(out, t.length_storage); cc_text(out, "))return 0;switch(tag){\n");
        var variant = p.nodes[t.declaration].first;
        while variant >= 0 {
            let payload = p.nodes[variant].type_id;
            cc_text(out, "case "); cc_number(out, p.nodes[variant].integer); cc_text(out, ":return "); cc_id(out, "g_equal_", payload); cc_text(out, "(");
            if cc_image_type(p, id) { cc_id(out, "g_load_", payload); } else { cc_id(out, "g_native_load_", payload); } cc_text(out, "(g_offset("); if cc_image_type(p, id) { cc_text(out, "g_ref(a.base),"); } else { cc_text(out, "g_ref(&a),"); } cc_number(out, t.length_storage); cc_text(out, "))," );
            if cc_image_type(p, id) { cc_id(out, "g_load_", payload); } else { cc_id(out, "g_native_load_", payload); } cc_text(out, "(g_offset("); if cc_image_type(p, id) { cc_text(out, "g_ref(b.base),"); } else { cc_text(out, "g_ref(&b),"); } cc_number(out, t.length_storage); cc_text(out, ")));\n");
            variant = p.nodes[variant].next;
        }
        cc_text(out, "default:g_panic(\"corrupt ADT tag\");}return 0;\n");
    } else if t.kind == TY_TUPLE {
        var field = t.first; var index = 0;
        while field >= 0 {
            cc_text(out, "if(!"); cc_id(out, "g_equal_", p.nodes[field].type_id); cc_text(out, "("); cc_id(out, "a.f", index); cc_text(out, ","); cc_id(out, "b.f", index); cc_text(out, "))return 0;\n");
            index++; field = p.nodes[field].next;
        }
        cc_text(out, "return 1;\n");
    } else if t.kind == TY_REF { cc_text(out, "return g_nullable_address(a)==g_nullable_address(b);\n"); }
    else { cc_text(out, "return a==b;\n"); }
    cc_text(out, "}\n"); cc_helper_alias(p, out, id, "a", true); cc_helper_alias(p, out, id, "b", true);
}

fn cc_emit_nested(p: Program&, out: u8[>..]&, id: i64) {
    let t = p.types[id]; if !cc_concrete(p, id) || t.kind == TY_VOID { return; }
    cc_text(out, "static void "); cc_helper_name(p, out, "g_nested_", id); cc_text(out, "(GArray *out,"); cc_helper_value(p, out, id, "v"); cc_text(out, "){\n"); cc_helper_alias(p, out, id, "v");
    if (t.kind == TY_ARRAY || t.kind == TY_SLICE) && cc_kind(p, t.element) == TY_INT && p.types[t.element].count == 8 && (p.types[t.element].flags & TF_UNSIGNED) != 0 {
        cc_text(out, "GRef r=g_ref("); if cc_image_type(p, id) { cc_text(out, "v.base"); } else { cc_text(out, "&v"); } cc_text(out, ");int64_t n=g_len(r,"); cc_array_args(p, out, id, false); cc_text(out, ");if(n<0 || (uint64_t)n>(SIZE_MAX-2)/2)g_panic(\"text size overflow\");unsigned char *b=malloc((size_t)n*2+2);if(!b)gs_panic(\"out of memory\");int64_t written=gs_fmt_quoted(b,g_address(g_element(r,"); cc_array_args(p, out, id); cc_text(out, ",0,1)),n);g_print_bytes(out,b,written);free(b);\n");
    } else if t.kind == TY_REF && cc_kind(p, t.element) == TY_VOID {
        cc_text(out, "g_print_text(out,\"null\");\n");
    } else if t.kind == TY_REF {
        cc_text(out, "if(!v)g_print_text(out,\"null\");else "); cc_id(out, "g_nested_", t.element); cc_text(out, "(out,"); cc_id(out, "g_load_", t.element); cc_text(out, "(v));\n");
    } else { cc_id(out, "g_print_", id); cc_text(out, "(out,v);\n"); }
    cc_text(out, "}\n"); cc_helper_alias(p, out, id, "v", true);
}

fn cc_zero_initializer(p: Program&, out: u8[>..]&, type_id: i64) {
    if cc_aggregate(p, type_id) { cc_text(out, "{}"); }
    else { cc_text(out, "{0}"); }
}

recursive fn cc_needs_clone(p: Program&, type_id: i64, depth: i64) -> bool {
    if cc_image_type(p, type_id) { return true; }
    if type_id < 0 { return false; }
    if depth > 64 { return true; }
    let t = p.types[type_id];
    if t.kind == TY_ARRAY {
        if cc_owner(p, type_id) { return true; }
        return cc_needs_clone(p, t.element, depth + 1);
    }
    if t.kind == TY_STRUCT && t.declaration >= 0 {
        var field = p.nodes[t.declaration].first;
        while field >= 0 {
            if (p.nodes[field].flags & F_PAD) == 0 && cc_needs_clone(p, p.nodes[field].type_id, depth + 1) { return true; }
            field = p.nodes[field].next;
        }
    }
    if t.kind == TY_ENUM && t.declaration >= 0 {
        var variant = p.nodes[t.declaration].first;
        while variant >= 0 {
            if cc_needs_clone(p, p.nodes[variant].type_id, depth + 1) { return true; }
            variant = p.nodes[variant].next;
        }
    }
    if t.kind == TY_TUPLE {
        var part = t.first;
        while part >= 0 {
            if cc_needs_clone(p, p.nodes[part].type_id, depth + 1) { return true; }
            part = p.nodes[part].next;
        }
    }
    return false;
}

fn cc_conversion_fail(p: Program&, node: i64, from: i64, to: i64) {
    var message: u8[>..] = [];
    message.format("c: unsupported checked value conversion ", from, " (kind ", cc_kind(p, from), ") to ", to, " (kind ", cc_kind(p, to), ")");
    cc_fail(p, node, message);
}

fn cc_location(p: Program&, out: u8[>..]&, node: i64) {
    if node < 0 || node >= p.nodes.len { cc_text(out, "\"<generated>\",1"); return; }
    let token = p.nodes[node].token;
    if token < 0 || token >= p.tokens.len { cc_text(out, "\"<generated>\",1"); return; }
    let t = p.tokens[token];
    if t.source < 0 || t.source >= p.sources.len { cc_text(out, "\"<generated>\""); }
    else {
        let source = p.sources[t.source]; cc_bytes(out, p.text[source.path_start..source.path_start + source.path_len]);
    }
    cc_text(out, ","); cc_number(out, t.line);
}
recursive fn cc_cast(p: Program&, f: CcBody&, node: i64) -> i64 {
    let n = p.nodes[node]; var target = p.types[n.type_id];
    if n.right >= 0 && cc_kind(p, p.nodes[n.right].type_id) == TY_INT && p.types[p.nodes[n.right].type_id].index_type >= 0 {
        target = p.types[p.nodes[n.right].type_id];
    }
    if cc_relative_cell(p, n.type_id) {
        let value = cc_to(p, f, n.left, n.type_id); cc_relative_check(p, f, value, n.type_id, node); return value;
    }
    var source = p.nodes[n.left].type_id;
    while cc_kind(p, source) == TY_REF { source = p.types[source].element; }
    var value = -1;
    if target.kind == TY_INT && target.index_type >= 0 && (n.flags & F_BOUNDS_PROVEN) == 0 {
        let symbol = target.pool;
        if symbol < 0 || cc_kind(p, source) != TY_INT { cc_fail(p, node, "c: index cast requires an integer and array owner"); return -1; }
        value = cc_to(p, f, n.left, source);
        var owner = cc_symbol_ref(p, f, symbol, node); var owner_type = p.symbols[symbol].type_id;
        while cc_kind(p, owner_type) == TY_REF { owner = cc_load(p, f, owner, owner_type); owner_type = p.types[owner_type].element; }
        let length = cc_temp(p, f, TYPE_I64); cc_set(f, length); cc_text(f.out, "g_len("); cc_id(f.out, "g_v", owner);
        cc_text(f.out, ","); cc_array_args(p, f.out, owner_type, false); cc_text(f.out, ");\nif((uint64_t)"); cc_id(f.out, "g_v", value);
        if (target.flags & F_BOUND_TYPE) != 0 { cc_text(f.out, ">"); } else { cc_text(f.out, ">="); }
        cc_text(f.out, "(uint64_t)"); cc_id(f.out, "g_v", length); cc_text(f.out, ")g_index_fail("); cc_id(f.out, "g_v", value);
        cc_text(f.out, ","); cc_id(f.out, "g_v", length); cc_text(f.out, ","); cc_location(p, f.out, node); cc_text(f.out, ");\n");
    }
    if !p.debug || (n.flags & F_UNSIGNED) != 0 || target.kind != TY_INT {
        if value >= 0 { return cc_convert(p, f, value, source, n.type_id, node); }
        return cc_to(p, f, n.left, n.type_id);
    }
    if cc_kind(p, source) != TY_INT && cc_kind(p, source) != TY_FLOAT { return cc_to(p, f, n.left, n.type_id); }
    if value < 0 { value = cc_to(p, f, n.left, source); }
    let result = cc_temp(p, f, n.type_id);
    cc_set(f, result); cc_text(f.out, "("); cc_type(f.out, n.type_id); cc_text(f.out, ")g_checked_cast_");
    if p.types[source].kind == TY_FLOAT { cc_text(f.out, "f("); }
    else if (p.types[source].flags & TF_UNSIGNED) != 0 { cc_text(f.out, "u("); }
    else { cc_text(f.out, "i("); }
    cc_id(f.out, "g_v", value); cc_text(f.out, ",");
    if p.types[source].kind == TY_FLOAT {
        var source_f32 = 0; if p.types[source].count == 32 { source_f32 = 1; }
        cc_number(f.out, source_f32); cc_text(f.out, ",");
    }
    cc_number(f.out, target.count); cc_text(f.out, ",");
    var uns = 0; if (target.flags & TF_UNSIGNED) != 0 { uns = 1; }
    cc_number(f.out, uns); cc_text(f.out, ","); cc_location(p, f.out, node); cc_text(f.out, ");\n"); return result;
}

fn cc_has_capture(p: Program&, function: i64, symbol: i64) -> bool {
    var capture = p.nodes[function].captures;
    while capture >= 0 {
        if p.nodes[capture].symbol == symbol { return true; }
        capture = p.nodes[capture].next;
    }
    return false;
}
fn cc_storage_binding(p: Program&, symbol: i64) -> bool {
    let node = p.symbols[symbol].node; if node < 0 { return false; }
    let kind = p.nodes[node].kind; return kind == N_VARIABLE || kind == N_BINDING || kind == N_PARAM;
}
fn cc_add_capture(p: Program&, function: i64, symbol: i64) -> bool {
    if symbol < 0 { return false; } let s = p.symbols[symbol];
    if s.owner == function || (s.flags & (S_GLOBAL | S_FUNCTION | S_TYPE | S_BUILTIN)) != 0 ||
       s.owner < 0 && !cc_storage_binding(p, symbol) || cc_has_capture(p, function, symbol) { return false; }
    let id = new_node(p, N_BINDING, s.name_token); p.nodes[id].symbol = symbol; p.nodes[id].type_id = s.type_id; p.nodes[id].flags = F_CHECKED;
    let first = p.nodes[function].captures;
    if first < 0 { p.nodes[function].captures = id; }
    else {
        var last = first; while p.nodes[last].next >= 0 { last = p.nodes[last].next; } p.nodes[last].next = id;
    }
    p.nodes[function].flags |= F_CAPTURE; return true;
}
fn cc_capture_call(p: Program&, function: i64, callee: i64) -> bool {
    if callee < 0 || callee >= p.nodes.len { return false; }
    var changed = false; var capture = p.nodes[callee].captures;
    while capture >= 0 {
        if cc_add_capture(p, function, p.nodes[capture].symbol) { changed = true; } capture = p.nodes[capture].next;
    }
    return changed;
}
recursive fn cc_capture_tree(p: Program&, function: i64, node: i64) -> bool {
    if node < 0 { return false; }
    let n = p.nodes[node];
    if n.kind == N_FUNCTION { return false; }
    if n.kind == N_FUNCTION_VALUE { return cc_capture_call(p, function, node); }
    if n.kind == N_RETURN && n.symbol >= 0 && n.symbol < p.symbols.len {
        let target = p.symbols[n.symbol].node;
        if target >= 0 && target != function { p.nodes[target].flags |= F_NONLOCAL; }
    }
    var changed = false;
    if n.kind == N_NAME && n.symbol >= 0 && cc_add_capture(p, function, n.symbol) { changed = true; }
    if (n.kind == N_CALL || n.kind == N_NAME) && n.symbol >= 0 &&
       (p.symbols[n.symbol].flags & S_FUNCTION) != 0 && (p.symbols[n.symbol].flags & S_BUILTIN) == 0 {
        changed = cc_capture_call(p, function, p.symbols[n.symbol].node);
    }
    if n.kind == N_CALL && (n.flags & F_DISPATCH) != 0 {
        var arm = n.third;
        while arm >= 0 {
            let symbol = p.nodes[arm].symbol;
            if symbol >= 0 && cc_capture_call(p, function, p.symbols[symbol].node) { changed = true; }
            arm = p.nodes[arm].next;
        }
    }
    // A match pattern names variant nodes, not symbols or executable callees.
    if n.kind != N_ARM && cc_capture_tree(p, function, n.left) { changed = true; }
    if cc_capture_tree(p, function, n.right) { changed = true; }
    if cc_capture_tree(p, function, n.third) { changed = true; }
    var child = n.first;
    while child >= 0 {
        if cc_capture_tree(p, function, child) { changed = true; }
        child = p.nodes[child].next;
    }
    return changed;
}
fn cc_collect_captures(p: Program&) {
    var changed = true;
    while changed {
        changed = false;
        let count = p.nodes.len;
        for function in 0..count {
            if cc_emittable(p, function) && p.nodes[function].right >= 0 &&
               cc_capture_tree(p, function, p.nodes[function].right) { changed = true; }
        }
    }
}
