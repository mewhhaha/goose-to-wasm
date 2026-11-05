import model;
import codegen_c_storage;
import thread_plan;

// Workers transfer value images; their globals and receiving regions are private.
fn cc_thread_function(p: Program&, node: i64) -> bool {
    let n = p.nodes[node];
    return n.kind == N_FUNCTION && (n.flags & (F_THREAD | F_CHECKED | F_REACHABLE)) == (F_THREAD | F_CHECKED | F_REACHABLE) &&
        (n.flags & F_GENERIC) == 0 && n.type_id >= 0 && p.types[n.type_id].kind == TY_FN;
}

fn cc_threads_used(p: Program&) -> bool {
    for n in p.nodes {
        if n.kind != N_CALL || n.symbol < 0 { continue; }
        let s = p.symbols[n.symbol];
        if (s.flags & S_BUILTIN) != 0 && s.index >= 7 && s.index <= 13 { return true; }
    }
    return false;
}

fn cc_queue_declaration(p: Program&, declaration: i64) -> i64 {
    var node = declaration;
    while node >= 0 && p.nodes[node].origin >= 0 {
        let original = p.nodes[node].origin;
        if p.nodes[original].kind != p.nodes[node].kind { break; }
        node = original;
    }
    return node;
}

// Queue identity follows concrete value layout, ignoring const and spelling.
recursive fn cc_queue_same(p: Program&, left: i64, right: i64, depth: i64 = 0) -> bool {
    if left == right { return true; }
    if left < 0 || right < 0 || depth > 128 { return false; }
    let a = p.types[left]; let b = p.types[right];
    if a.kind != b.kind { return false; }
    if a.kind == TY_INT {
        return a.count == b.count && a.storage == b.storage && a.pool == b.pool &&
            (a.index_type >= 0) == (b.index_type >= 0) &&
            (a.flags & (TF_UNSIGNED | F_BOUND_TYPE)) == (b.flags & (TF_UNSIGNED | F_BOUND_TYPE));
    }
    if a.kind == TY_FLOAT { return a.count == b.count; }
    if a.kind == TY_BOOL { return true; }
    if a.kind == TY_ARRAY {
        if a.array_kind != b.array_kind { return false; }
        if (a.array_kind == A_FIXED || a.array_kind == A_LIMITED) && a.count != b.count { return false; }
        if a.array_kind == A_VAR && a.length_storage != b.length_storage { return false; }
        return cc_queue_same(p, a.element, b.element, depth + 1);
    }
    if a.kind == TY_REF {
        if a.length_storage != b.length_storage || a.pool != b.pool ||
           (a.flags & TF_OPTIONAL) != (b.flags & TF_OPTIONAL) { return false; }
        return cc_queue_same(p, a.element, b.element, depth + 1);
    }
    if a.kind == TY_SLICE { return cc_queue_same(p, a.element, b.element, depth + 1); }
    var ap = a.first; var bp = b.first;
    if a.kind == TY_STRUCT || a.kind == TY_ENUM {
        if a.kind == TY_ENUM && (a.flags & F_VARIABLE_MODE) != (b.flags & F_VARIABLE_MODE) { return false; }
        if a.kind == TY_STRUCT && (a.pool >= 0 || b.pool >= 0) {
            if a.pool < 0 || b.pool < 0 { return false; }
            return p.nodes[a.declaration].integer == p.nodes[b.declaration].integer &&
                cc_queue_same(p, a.pool, b.pool, depth + 1);
        }
        if cc_queue_declaration(p, a.declaration) != cc_queue_declaration(p, b.declaration) { return false; }
        ap = a.arguments; bp = b.arguments;
    } else if a.kind != TY_TUPLE { return false; }
    while ap >= 0 && bp >= 0 {
        if !cc_queue_same(p, p.nodes[ap].type_id, p.nodes[bp].type_id, depth + 1) { return false; }
        ap = p.nodes[ap].next; bp = p.nodes[bp].next;
    }
    return ap < 0 && bp < 0;
}

fn cc_queue_key(p: Program&, type_id: i64) -> i64 {
    if type_id < 0 { return -1; }
    for candidate in 0..type_id { if cc_queue_same(p, candidate, type_id) { return candidate; } }
    return type_id;
}

fn cc_queue_type(p: Program&, node: i64) -> i64 {
    let n = p.nodes[node];
    if n.kind != N_CALL || n.symbol < 0 { return -1; }
    let symbol = p.symbols[n.symbol];
    if (symbol.flags & S_BUILTIN) == 0 || symbol.index < 10 || symbol.index > 13 { return -1; }
    if symbol.index == 10 {
        if n.first < 0 { return -1; }
        var ty = p.nodes[n.first].type_id;
        while ty >= 0 && p.types[ty].kind == TY_REF { ty = p.types[ty].element; }
        return ty;
    }
    if n.left < 0 || p.nodes[n.left].first < 0 { return -1; }
    return p.nodes[p.nodes[n.left].first].type_id;
}

fn cc_thread_emit_queues(p: Program&, out: u8[>..]&, initialize: bool = false) {
    var seen: bool[>..] = []; seen.resize(p.types.len, false);
    for n, node in p.nodes {
        let key = cc_queue_key(p, cc_queue_type(p, node));
        if key < 0 || seen[key] { continue; }
        seen[key] = true;
        if initialize { out.format("gs_qinit(&g_queue_", key, ");\n"); }
        else { out.format("static gs_queue g_queue_", key, "=GS_QUEUE_INIT;\n"); }
    }
}

// The extra region holds the received variable image after a queue node dies.
fn cc_transfer_width(p: Program&, type_id: i64) -> i64 {
    return cc_region_width(p, type_id) + 1;
}

fn cc_thread_regions(p: Program&, function: i64) -> i64 {
    var count = 0; var formal = p.nodes[function].first;
    while formal >= 0 { count += cc_transfer_width(p, p.nodes[formal].type_id); formal = p.nodes[formal].next; }
    var globals: bool[>..] = []; thread_globals(p, function, globals);
    for used, symbol in globals {
        if !used { continue; }
        count += cc_transfer_width(p, p.symbols[symbol].type_id);
        if cc_pool_mode(p, symbol) > 0 { count++; }
    }
    return count;
}

fn cc_thread_emit_globals(p: Program&, out: u8[>..]&) {
    out.append("typedef struct {\nunsigned char empty;\n");
    for s, symbol in p.symbols {
        if (s.flags & S_GLOBAL) != 0 && s.type_id >= 0 {
            cc_storage_type(p, out, s.type_id); out.format(" v", symbol, ";\n");
        }
    }
    out.append("} GGlobals;\nstatic GGlobals g_main_globals;\n");
    for s, symbol in p.symbols {
        if (s.flags & S_GLOBAL) != 0 && s.type_id >= 0 { out.format("#define g_s", symbol, " (((GGlobals*)gs_gl)->v", symbol, ")\n"); }
    }
    out.append("static int64_t g_worker_regions;\n");
    for n, node in p.nodes {
        if cc_thread_function(p, node) { out.format("static void g_worker_", node, "(uint8_t*);\n"); }
    }
}

fn cc_thread_emit_image(out: u8[>..]&, type_id: i64, value: i64, packet: i64) {
    out.format("g_image_write_", type_id, "(g_transfer_append(&g_packet", packet,
        ",g_image_size_", type_id, "(g_ref(&g_v", value, "))),g_ref(&g_v", value, "));\n");
}

fn cc_thread_emit_global_images(p: Program&, out: u8[>..]&, function: i64, packet: i64) {
    var globals: bool[>..] = []; thread_globals(p, function, globals);
    for used, symbol in globals {
        if !used { continue; }
        let type_id = p.symbols[symbol].type_id;
        out.format("g_image_write_", type_id, "(g_transfer_append(&g_packet", packet,
            ",g_image_size_", type_id, "(g_ref(&g_s", symbol, "))),g_ref(&g_s", symbol, "));\n");
        if cc_pool_mode(p, symbol) > 0 {
            out.format("g_pool_image_write(g_transfer_append(&g_packet", packet,
                ",g_pool_image_size(g_ref(&g_s", symbol, "))),g_ref(&g_s", symbol, "));\n");
        }
    }
}

fn cc_thread_emit_receive(p: Program&, out: u8[>..]&, type_id: i64, name: const u8[:], id: i64, slot: i64) {
    let width = cc_region_width(p, type_id);
    if width > 0 { out.format("g_init_", type_id, "(g_ref(&", name, id, "),", slot, ");\n"); }
    out.format("g_image_read_", type_id, "(g_ref(&", name, id, "),g_transfer_next(&g_cursor,NULL),", slot + width, ");\n");
}

fn cc_thread_emit_workers(p: Program&, out: u8[>..]&) {
    for n, function in p.nodes {
        if !cc_thread_function(p, function) { continue; }
        let regions = cc_thread_regions(p, function);
        out.format("static void g_worker_", function, "(uint8_t *g_packet){\n",
            "const uint8_t *g_cursor=g_packet;\n",
            "g_region_pool_begin(g_worker_regions+", regions, ");\n",
            "gs_gl=calloc(1,sizeof(GGlobals));\n",
            "if(!gs_gl)gs_panic(\"out of memory copying globals\");\n");
        var slot = 0; var formal = n.first; var ordinal = 0;
        while formal >= 0 {
            let type_id = p.nodes[formal].type_id;
            if cc_indirect(p, type_id) {
                out.format("GFixed g_argument_fixed", ordinal,
                    " __attribute__((cleanup(g_fixed_release)))=g_fixed_begin(sizeof(g_t", type_id, "),1);\n",
                    "#define g_argument", ordinal, " (*(g_t", type_id, "*)g_argument_fixed", ordinal, ".data)\n");
            } else {
                cc_storage_type(p, out, type_id);
                out.format(" g_argument", ordinal, ";memset(&g_argument", ordinal,
                    ",0,sizeof g_argument", ordinal, ");\n");
            }
            cc_thread_emit_receive(p, out, type_id, "g_argument", ordinal, slot);
            slot += cc_transfer_width(p, type_id); ordinal++; formal = p.nodes[formal].next;
        }
        var globals: bool[>..] = []; thread_globals(p, function, globals);
        for used, symbol in globals {
            if !used { continue; }
            let type_id = p.symbols[symbol].type_id;
            cc_thread_emit_receive(p, out, type_id, "g_s", symbol, slot);
            slot += cc_transfer_width(p, type_id);
            let mode = cc_pool_mode(p, symbol);
            if mode > 0 {
                out.format("g_pool_image_read(g_ref(&g_s", symbol,
                    "),g_transfer_next(&g_cursor,NULL),", slot, ",", mode, ");\n");
                slot++;
            }
        }
        out.format("g_fn", function, "(NULL,", regions);
        formal = n.first; ordinal = 0;
        while formal >= 0 {
            out.append(",");
            if cc_indirect(p, p.nodes[formal].type_id) { out.append("&"); }
            if cc_relative_cell(p, p.nodes[formal].type_id) {
                out.format("g_load_", p.nodes[formal].type_id, "(g_ref(&g_argument", ordinal, "))");
            } else { out.format("g_argument", ordinal); }
            ordinal++; formal = p.nodes[formal].next;
        }
        out.append(");\n}\n");
        formal = n.first; ordinal = 0;
        while formal >= 0 {
            if cc_indirect(p, p.nodes[formal].type_id) { out.format("#undef g_argument", ordinal, "\n"); }
            ordinal++; formal = p.nodes[formal].next;
        }
    }
}
