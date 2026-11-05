import model;

// These describe native frames. Image sizes and field offsets remain separate.
struct CcPlace { type_id: i64, address: i64, stack: i64 = -1, owner_header: i64 = -1, image_base: i64 = -1 }
struct CcDestination {
    type_id: i64, header: i64, stack: i64, lifetime: i64,
    entry: i64 = -1, start: i64 = -1, receiver: i64 = -1,
    publication: i64 = -1, construction: i64 = -1,
}
struct CcReceiving { ordinal: i64, destination: i64, symbol: i64 = -1 }

recursive fn cc_region_width(p: Program&, type_id: i64) -> i64 {
    if type_id < 0 { return 0; }
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
        var size = t.size; var field = t.first;
        while field >= 0 { let id = p.nodes[field].type_id; size += cc_frame_size(p, id) - p.types[id].size; field = p.nodes[field].next; }
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

recursive fn cc_frame_borrows(p: Program&, type_id: i64) -> bool {
    if type_id < 0 { return false; }
    let t = p.types[type_id];
    if t.kind == TY_REF || t.kind == TY_SLICE || t.kind == TY_FN { return true; }
    if t.kind == TY_ARRAY { return cc_frame_borrows(p, t.element); }
    if t.kind == TY_STRUCT && t.declaration >= 0 {
        var field = p.nodes[t.declaration].first;
        while field >= 0 { if cc_frame_borrows(p, p.nodes[field].type_id) { return true; } field = p.nodes[field].next; }
    }
    if t.kind == TY_TUPLE {
        var field = t.first;
        while field >= 0 { if cc_frame_borrows(p, p.nodes[field].type_id) { return true; } field = p.nodes[field].next; }
    }
    return false;
}
