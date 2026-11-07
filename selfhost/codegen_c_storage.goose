import model;

// These describe native frames. Image sizes and field offsets remain separate.
struct CcPlace { type_id: i64, address: i64, form: i64 = 0, stack: i64 = -1, owner_header: i64 = -1, image_base: i64 = -1, image_end: i64 = -1 }
struct CcDestination {
    type_id: i64, header: i64, stack: i64, lifetime: i64, form: i64 = 0,
    entry: i64 = -1, start: i64 = -1, receiver: i64 = -1,
    publication: i64 = -1, construction: i64 = -1,
}
struct CcReceiving { ordinal: i64, destination: i64, symbol: i64 = -1, call: i64 = -1 }
struct CcChannels { value: i64, address: i64 }
struct CcCursor { symbol: i64, index: i64, address: i64, type_id: i64 }
let CC_NATIVE: i64 = 0;
let CC_REGISTER: i64 = 1;
let CC_IMAGE: i64 = 2;
let CC_CHANNELS: i64 = 3;

recursive fn cc_size_class(p: Program&, id: i64) -> i64 {
    if id < 0 { return 0; } let t = p.types[id];
    if t.kind == TY_INT { if t.storage != 0 { return 1; } return 0; }
    if t.kind == TY_REF { if t.length_storage == 0 { return 1; } return 0; }
    if t.kind == TY_ARRAY {
        if t.array_kind == A_FIXED || t.array_kind == A_LIMITED && t.count >= 0 { return 0; }
        if t.array_kind == A_VAR || t.array_kind == A_LIMITED { return 1; } return 2;
    }
    if t.kind == TY_ENUM && (t.flags & F_VARIABLE_MODE) == 0 { return 0; }
    var field = -1; var result = 0; if t.kind == TY_ENUM { result = 1; }
    if (t.kind == TY_STRUCT || t.kind == TY_ENUM) && t.declaration >= 0 { field = p.nodes[t.declaration].first; }
    while field >= 0 {
        let n = p.nodes[field];
        if (n.flags & F_PAD) == 0 { let size_class = cc_size_class(p, n.type_id); if size_class > result { result = size_class; } }
        field = n.next;
    }
    return result;
}
fn cc_image_type(p: Program&, id: i64) -> bool {
    let kind = cc_kind(p, id);
    if kind == TY_ARRAY { return p.types[id].array_kind == A_VAR || p.types[id].array_kind == A_LIMITED && p.types[id].count < 0; }
    return (kind == TY_STRUCT || kind == TY_ENUM) && cc_size_class(p, id) == 1 && (kind == TY_ENUM || cc_image_fields(p, id));
}
recursive fn cc_image_fields(p: Program&, id: i64) -> bool {
    let t = p.types[id];
    if t.kind == TY_ENUM && (t.flags & F_VARIABLE_MODE) != 0 { return true; }
    if t.kind == TY_INT { return t.storage != 0; }
    if t.kind == TY_REF { return t.length_storage == 0; }
    if t.kind == TY_ARRAY { return t.array_kind == A_VAR || t.array_kind == A_LIMITED && t.count < 0 || cc_image_fields(p, t.element); }
    var field = -1;
    if (t.kind == TY_STRUCT || t.kind == TY_ENUM) && t.declaration >= 0 { field = p.nodes[t.declaration].first; }
    while field >= 0 { let n = p.nodes[field]; if (n.flags & F_PAD) == 0 && cc_image_fields(p, n.type_id) { return true; } field = n.next; }
    return false;
}
// This first physical stage has no nested owner or self-relative field.
fn cc_flat_relative_image(p: Program&, id: i64) -> bool {
    if id < 0 || p.types[id].kind != TY_STRUCT || cc_size_class(p, id) != 1 { return false; }
    var field = p.nodes[p.types[id].declaration].first; var relative = false;
    while field >= 0 {
        let n = p.nodes[field]; field = n.next;
        if (n.flags & F_PAD) != 0 { continue; }
        let t = p.types[n.type_id];
        if t.kind == TY_REF && t.length_storage >= 0 && t.pool >= 0 {
            if !cc_fixed_storage(p, t.element) || cc_region_width(p, t.element) != 0 || cc_frame_size(p, t.element) != p.types[t.element].size { return false; }
            relative = true;
        } else if t.kind != TY_INT && t.kind != TY_BOOL { return false; }
    }
    return relative;
}
fn cc_flat_image_reference(p: Program&, id: i64) -> bool {
    return id >= 0 && p.types[id].kind == TY_REF && p.types[id].length_storage < 0 && (p.types[id].flags & TF_OPTIONAL) == 0 && cc_flat_relative_image(p, p.types[id].element);
}
fn cc_flat_image_abi_pending(p: Program&, id: i64) -> bool {
    if cc_flat_relative_image(p, id) { return true; }
    return id >= 0 && p.types[id].kind == TY_REF && cc_flat_relative_image(p, p.types[id].element);
}
fn cc_render_unbounded_image(p: Program&, id: i64) -> bool {
    let kind = cc_kind(p, id);
    if kind == TY_VOID || kind == TY_BOOL || kind == TY_INT || kind == TY_FLOAT || kind == TY_FN { return false; }
    var work: i64[>..] = [id]; var seen: bool[>..] = []; seen.resize(p.types.len, false);
    while work.len > 0 {
        let current = work.pop(); if current < 0 || seen[current] { continue; } seen[current] = true;
        let t = p.types[current];
        if t.kind == TY_REF {
            if cc_flat_relative_image(p, t.element) { return true; }
            work.push(t.element);
        } else if t.kind == TY_ARRAY || t.kind == TY_SLICE { work.push(t.element); }
        else {
            var field = -1;
            if (t.kind == TY_STRUCT || t.kind == TY_ENUM) && t.declaration >= 0 { field = p.nodes[t.declaration].first; }
            if t.kind == TY_TUPLE { field = t.first; }
            while field >= 0 { let n = p.nodes[field]; if (n.flags & F_PAD) == 0 { work.push(n.type_id); } field = n.next; }
        }
    }
    return false;
}
fn cc_physical_cell_width(p: Program&, id: i64) -> i64 {
    let t = p.types[id];
    if t.kind == TY_REF { return t.length_storage; }
    if t.kind == TY_INT && t.storage != 0 { return 0; }
    return t.size;
}
fn cc_image_constructible(p: Program&, id: i64) -> bool {
    if cc_flat_relative_image(p, id) { return true; }
    let root = p.types[id];
    if root.kind == TY_REF { return root.length_storage < 0; }
    if root.kind != TY_ARRAY && root.kind != TY_STRUCT && root.kind != TY_ENUM { return true; }
    var work: i64[>..] = [id]; var seen: bool[>..] = []; seen.resize(p.types.len, false);
    while work.len > 0 {
        let current = work.pop(); if current < 0 || seen[current] { continue; } seen[current] = true; let t = p.types[current];
        if t.kind == TY_REF { if t.length_storage >= 0 { return false; } continue; }
        if t.kind == TY_ARRAY {
            if t.array_kind != A_FIXED && t.array_kind != A_VAR && t.array_kind != A_LIMITED { return false; }
            if cc_fixed_storage(p, t.element) { continue; }
            if t.array_kind != A_VAR { return false; } work.push(t.element); continue;
        }
        var field = -1;
        if (t.kind == TY_STRUCT || t.kind == TY_ENUM) && t.declaration >= 0 { field = p.nodes[t.declaration].first; }
        while field >= 0 { let n = p.nodes[field]; if (n.flags & F_PAD) == 0 { work.push(n.type_id); } field = n.next; }
    }
    return true;
}
recursive fn cc_variable_prefix_frame(p: Program&, id: i64) -> bool {
    if cc_size_class(p, id) != 2 { return false; } let t = p.types[id];
    if t.kind != TY_STRUCT && t.kind != TY_ENUM { return false; } var field = p.nodes[t.declaration].first;
    while field >= 0 {
        let n = p.nodes[field];
        if (n.flags & F_PAD) == 0 && (cc_size_class(p, n.type_id) == 1 && !cc_image_type(p, n.type_id) || cc_variable_prefix_frame(p, n.type_id)) { return true; } field = n.next;
    }
    return false;
}

recursive fn cc_region_width(p: Program&, type_id: i64) -> i64 {
    if type_id < 0 { return 0; }
    if cc_image_type(p, type_id) { return 1; }
    let t = p.types[type_id];
    if t.kind == TY_ARRAY {
        if t.array_kind == A_FIXED || t.array_kind == A_VAR || t.array_kind == A_LIMITED { return 0; }
        return 1;
    }
    if t.kind == TY_STRUCT && t.declaration >= 0 {
        var result = 0; var field = p.nodes[t.declaration].first;
        while field >= 0 {
            if (p.nodes[field].flags & F_PAD) == 0 { result += cc_region_width(p, p.nodes[field].type_id); }
            field = p.nodes[field].next;
        }
        return result;
    }
    if t.kind == TY_TUPLE {
        var result = 0; var field = t.first;
        while field >= 0 { result += cc_region_width(p, p.nodes[field].type_id); field = p.nodes[field].next; }
        return result;
    }
    if t.kind == TY_ENUM && t.declaration >= 0 {
        var result = 0; var variant = p.nodes[t.declaration].first;
        while variant >= 0 {
            let width = cc_region_width(p, p.nodes[variant].type_id);
            if width > result { result = width; }
            variant = p.nodes[variant].next;
        }
        return result;
    }
    return 0;
}

recursive fn cc_frame_size(p: Program&, type_id: i64) -> i64 {
    if type_id < 0 { return 0; }
    if cc_image_type(p, type_id) { return 24; }
    let t = p.types[type_id];
    if t.kind == TY_STRUCT && t.declaration >= 0 {
        var size = t.size; var field = p.nodes[t.declaration].first;
        while field >= 0 {
            let n = p.nodes[field];
            if (n.flags & F_PAD) == 0 { size += cc_frame_size(p, n.type_id) - p.types[n.type_id].size; }
            field = n.next;
        }
        return size;
    }
    if t.kind == TY_TUPLE {
        var size = 0; var field = t.first;
        while field >= 0 {
            let id = p.nodes[field].type_id;
            if p.types[id].kind == TY_REF || p.types[id].kind == TY_INT && p.types[id].storage != 0 { size += 8; }
            else { size += cc_frame_size(p, id); } field = p.nodes[field].next;
        }
        return size;
    }
    if t.kind == TY_ENUM && t.declaration >= 0 {
        var payload = 0; var variant = p.nodes[t.declaration].first;
        while variant >= 0 {
            let size = cc_frame_size(p, p.nodes[variant].type_id); if size > payload { payload = size; }
            variant = p.nodes[variant].next;
        }
        let size = t.length_storage + payload;
        if cc_region_width(p, type_id) > 0 { return size + 8; }
        return size;
    }
    return t.size;
}
fn cc_field_offset(p: Program&, type_id: i64, field: i64) -> i64 {
    var id = type_id;
    while id >= 0 && p.types[id].kind == TY_REF { id = p.types[id].element; }
    let n = p.nodes[field];
    if id < 0 || p.types[id].kind != TY_STRUCT || p.types[id].declaration < 0 { return n.integer; }
    var offset = n.integer; var previous = p.nodes[p.types[id].declaration].first;
    while previous >= 0 && previous != field {
        let value = p.nodes[previous];
        if (value.flags & F_PAD) == 0 { offset += cc_frame_size(p, value.type_id) - p.types[value.type_id].size; }
        previous = value.next;
    }
    return offset;
}

fn cc_frame_borrows(p: Program&, type_id: i64) -> bool {
    if type_id < 0 { return false; }
    let root = p.types[type_id];
    if root.kind == TY_REF || root.kind == TY_SLICE || root.kind == TY_FN { return true; }
    if root.kind != TY_ARRAY && root.kind != TY_STRUCT && root.kind != TY_ENUM && root.kind != TY_TUPLE { return false; }
    var work: i64[>..] = [type_id]; var seen: bool[>..] = []; seen.resize(p.types.len, false);
    while work.len > 0 {
        let current = work.pop(); if current < 0 || seen[current] { continue; } seen[current] = true; let t = p.types[current];
        if t.kind == TY_REF || t.kind == TY_SLICE || t.kind == TY_FN { return true; }
        if t.kind == TY_ARRAY { work.push(t.element); }
        var field = -1;
        if (t.kind == TY_STRUCT || t.kind == TY_ENUM) && t.declaration >= 0 { field = p.nodes[t.declaration].first; }
        else if t.kind == TY_TUPLE { field = t.first; }
        while field >= 0 { let n = p.nodes[field]; if (n.flags & F_PAD) == 0 { work.push(n.type_id); } field = n.next; }
    }
    return false;
}

fn cc_kind(p: Program&, type_id: i64) -> i64 {
    if type_id < 0 || type_id >= p.types.len { return TY_UNKNOWN; } return p.types[type_id].kind;
}
fn cc_concrete(p: Program&, id: i64) -> bool {
    let kind = cc_kind(p, id);
    if kind == TY_UNKNOWN || kind == TY_GENERIC || kind == TY_NAME { return false; }
    let t = p.types[id];
    if kind == TY_ARRAY || kind == TY_SLICE || kind == TY_REF {
        let element = cc_kind(p, t.element);
        if element == TY_UNKNOWN || element == TY_GENERIC || element == TY_NAME { return false; }
    }
    if kind == TY_STRUCT || kind == TY_ENUM {
        if t.declaration < 0 { return false; }
        var field = p.nodes[t.declaration].first;
        while field >= 0 {
            if p.nodes[field].kind == N_VARIANT && p.nodes[field].type_id < 0 { return false; }
            if p.nodes[field].kind == N_FIELD && (p.nodes[field].flags & F_PAD) == 0 {
                let fk = cc_kind(p, p.nodes[field].type_id);
                if fk == TY_UNKNOWN || fk == TY_GENERIC || fk == TY_NAME { return false; }
            }
            field = p.nodes[field].next;
        }
    }
    return true;
}

fn cc_indirect(p: Program&, type_id: i64) -> bool {
    let kind = cc_kind(p, type_id);
    return (kind == TY_ARRAY || kind == TY_STRUCT || kind == TY_ENUM || kind == TY_TUPLE) && cc_frame_size(p, type_id) > 4096;
}
fn cc_receives(p: Program&, type_id: i64) -> bool {
    return cc_region_width(p, type_id) > 0 || cc_result_indirect(p, type_id);
}
fn cc_array_kind(p: Program&, type_id: i64) -> i64 {
    if cc_kind(p, type_id) == TY_SLICE { return A_SLICE; }
    return p.types[type_id].array_kind;
}
fn cc_prefix(p: Program&, type_id: i64) -> i64 {
    if p.types[type_id].array_kind == A_VAR && p.types[type_id].length_storage > 0 { return p.types[type_id].length_storage; }
    let t = p.types[type_id]; if t.array_kind != A_LIMITED || t.count < 0 { return 0; }
    if t.length_storage > 0 { return t.length_storage; } return 1;
}
fn cc_pool_mode(p: Program&, symbol: i64) -> i64 {
    if symbol < 0 || p.symbols[symbol].node < 0 { return 0; }
    let flags = p.nodes[p.symbols[symbol].node].flags;
    if (flags & F_REUSABLE) == 0 { return 0; }
    if (flags & F_REUSABLE_SLICES) != 0 { return 2; } return 1;
}

fn cc_relative_cell(p: Program&, type_id: i64) -> bool {
    return cc_kind(p, type_id) == TY_REF && p.types[type_id].length_storage >= 0;
}
fn cc_storage_type(p: Program&, out: u8[>..]&, type_id: i64) {
    if cc_relative_cell(p, type_id) && p.types[type_id].length_storage == 0 { out.append("GVarRelative"); }
    else if cc_relative_cell(p, type_id) { out.format("uint", p.types[type_id].length_storage * 8, "_t"); }
    else { out.format("g_t", type_id); }
}
fn cc_place_type(p: Program&, node: i64) -> i64 {
    let n = p.nodes[node];
    if n.kind == N_NAME && n.symbol >= 0 { return p.symbols[n.symbol].type_id; }
    if n.kind == N_MEMBER && n.symbol >= 0 { return p.nodes[n.symbol].type_id; }
    if n.kind == N_INDEX {
        var array = p.nodes[n.left].type_id; while cc_kind(p, array) == TY_REF { array = p.types[array].element; }
        if cc_kind(p, array) == TY_ARRAY || cc_kind(p, array) == TY_SLICE { return p.types[array].element; }
    }
    if n.kind == N_UNARY && n.integer == T_MUL && cc_kind(p, p.nodes[n.left].type_id) == TY_REF { return p.types[p.nodes[n.left].type_id].element; }
    return n.type_id;
}

recursive fn cc_relative_fields(p: Program&, type_id: i64, self_only: bool = false) -> bool {
    let t = p.types[type_id];
    if t.kind == TY_REF { return t.length_storage >= 0 && (!self_only || t.pool < 0); }
    if t.kind == TY_ARRAY {
        if t.array_kind == A_FIXED || t.array_kind == A_LIMITED && t.count >= 0 { return cc_relative_fields(p, t.element, self_only); } return false;
    }
    var field = -1;
    if t.kind == TY_STRUCT && t.declaration >= 0 { field = p.nodes[t.declaration].first; }
    else if t.kind == TY_ENUM && t.declaration >= 0 { field = p.nodes[t.declaration].first; }
    else if t.kind == TY_TUPLE { field = t.first; }
    while field >= 0 {
        let n = p.nodes[field];
        if (n.flags & F_PAD) == 0 && !(t.kind == TY_TUPLE && cc_kind(p, n.type_id) == TY_REF) && cc_relative_fields(p, n.type_id, self_only) { return true; }
        field = n.next;
    }
    return false;
}
recursive fn cc_fixed_storage(p: Program&, type_id: i64) -> bool {
    let t = p.types[type_id];
    if t.kind == TY_INT { return t.storage == 0; }
    if t.kind == TY_REF { return t.length_storage != 0; }
    if t.kind == TY_ARRAY { return (t.array_kind == A_FIXED || t.array_kind == A_LIMITED && t.count >= 0) && cc_fixed_storage(p, t.element); }
    if t.kind == TY_ENUM && (t.flags & F_VARIABLE_MODE) != 0 { return false; }
    var field = -1;
    if (t.kind == TY_STRUCT || t.kind == TY_ENUM) && t.declaration >= 0 { field = p.nodes[t.declaration].first; }
    else if t.kind == TY_TUPLE { field = t.first; }
    while field >= 0 {
        let n = p.nodes[field]; if (n.flags & F_PAD) == 0 && !cc_fixed_storage(p, n.type_id) { return false; } field = n.next;
    }
    return true;
}
fn cc_result_location(p: Program&, type_id: i64) -> bool {
    if cc_image_type(p, type_id) { return true; }
    let kind = cc_kind(p, type_id);
    if kind == TY_TUPLE {
        var field = p.types[type_id].first;
        while field >= 0 {
            let child = p.nodes[field].type_id;
            if cc_kind(p, child) != TY_REF && cc_relative_fields(p, child) && !cc_fixed_storage(p, child) { return false; } field = p.nodes[field].next;
        }
        return cc_relative_fields(p, type_id);
    }
    return (kind == TY_ARRAY || kind == TY_STRUCT || kind == TY_ENUM) && cc_fixed_storage(p, type_id) && cc_relative_fields(p, type_id);
}
fn cc_tuple_channels(p: Program&, type_id: i64) -> bool {
    if cc_kind(p, type_id) != TY_TUPLE { return false; }
    if cc_indirect(p, type_id) { return true; }
    var field = p.types[type_id].first;
    while field >= 0 {
        let kind = cc_kind(p, p.nodes[field].type_id);
        if kind == TY_ARRAY || kind == TY_STRUCT || kind == TY_ENUM || kind == TY_TUPLE { return true; }
        field = p.nodes[field].next;
    }
    return false;
}
fn cc_result_indirect(p: Program&, type_id: i64) -> bool { return cc_tuple_channels(p, type_id) || cc_indirect(p, type_id) || cc_result_location(p, type_id); }
fn cc_helper_indirect(p: Program&, type_id: i64) -> bool {
    if cc_image_type(p, type_id) { return false; }
    let kind = cc_kind(p, type_id);
    return cc_indirect(p, type_id) || (kind == TY_ARRAY || kind == TY_STRUCT || kind == TY_ENUM || kind == TY_TUPLE) && cc_relative_fields(p, type_id, true);
}

struct CcFill { node: i64, type_id: i64, value: i64 }
recursive fn cc_field_defaults(p: Program&, type_id: i64) -> bool {
    let t = p.types[type_id];
    if t.kind == TY_ARRAY { return t.array_kind == A_FIXED && t.count > 0 && cc_field_defaults(p, t.element); }
    if t.kind == TY_ENUM && t.declaration >= 0 {
        let first = p.nodes[t.declaration].first; return first >= 0 && cc_field_defaults(p, p.nodes[first].type_id);
    }
    if t.kind != TY_STRUCT || t.declaration < 0 { return false; }
    var field = p.nodes[t.declaration].first;
    while field >= 0 {
        let n = p.nodes[field];
        if (n.flags & F_PAD) == 0 && (n.right >= 0 || cc_field_defaults(p, n.type_id)) { return true; } field = n.next;
    }
    return false;
}

// The frontend exports -2 only for exact static/null roots and rejects
// relative cells in these globals. Owning fields still need private copies.
fn cc_static_global(p: Program&, symbol: i64) -> bool {
    let s = p.symbols[symbol];
    return (s.flags & (S_GLOBAL | S_MUTABLE)) == S_GLOBAL && s.provenance == -2 && cc_frame_borrows(p, s.type_id);
}
