import model;
import checker;
import checker_lifetimes;

// Folding deliberately declines an operation that would trap. In particular,
// x * 0 is not a rewrite: evaluating x may call, mutate memory or abort.
fn opt_add_safe(a: i64, b: i64) -> bool {
    if b > 0 { return a <= 9223372036854775807 - b; }
    if b < 0 { return a >= -9223372036854775808 - b; }
    return true;
}
fn opt_sub_safe(a: i64, b: i64) -> bool {
    if b < 0 { return a <= 9223372036854775807 + b; }
    if b > 0 { return a >= -9223372036854775808 + b; }
    return true;
}
fn opt_mul_safe(a: i64, b: i64) -> bool {
    if a == 0 || b == 0 { return true; }
    if a == -1 { return b != -9223372036854775808; }
    if b == -1 { return a != -9223372036854775808; }
    if a > 0 {
        if b > 0 { return a <= 9223372036854775807 / b; }
        return b >= -9223372036854775808 / a;
    }
    if b > 0 { return a >= -9223372036854775808 / b; }
    return a >= 9223372036854775807 / b;
}

fn opt_wrap(value: u64, kind: i64) -> i64 {
    if kind == TYPE_I8 { return value as! i8; }
    if kind == TYPE_U8 { return value as! u8; }
    if kind == TYPE_I16 { return value as! i16; }
    if kind == TYPE_U16 { return value as! u16; }
    if kind == TYPE_I32 { return value as! i32; }
    if kind == TYPE_U32 { return value as! u32; }
    return value as! i64;
}

let OPT_FACT_WRITTEN: u32 = 1;
let OPT_FACT_DIRECT_WRITTEN: u32 = 2;
let OPT_FACT_ADDRESSED: u32 = 4;
let OPT_FACT_INDEX_VAR: u32 = 8;
struct OptFact { flags: u32 = 0, calls: i32 = 0, literal: i64 = -1 }
struct OptBoundGuard { index_sym: i64, index_field: i64 = -1, index_is_ref: bool = false, arr_sym: i64, arr_field: i64, arr_imm_slice: bool = false, pos: bool = false }
struct OptLenAlias { sym: i64, arr_sym: i64, arr_field: i64, arr_imm_slice: bool = false, delta: i64 = 0 }
struct OptLenMin { arr_sym: i64, arr_field: i64, arr_imm_slice: bool = false, min_len: i64 = 0 }
struct OptLenEq { a_sym: i64, a_field: i64, a_imm: bool = false, b_sym: i64, b_field: i64, b_imm: bool = false, ordered: bool = false, stable: bool = false }
struct OptBoundState {
    guards: OptBoundGuard[>..]&,
    nonneg: i64[>..]&,
    aliases: OptLenAlias[>..]&,
    mins: OptLenMin[>..]&,
    eqs: OptLenEq[>..]&,
    snaps: OptBoundSnap[>..]&,
    snap_guards: OptBoundGuard[>..]&,
    snap_nonneg: i64[>..]&,
    snap_aliases: OptLenAlias[>..]&,
    snap_mins: OptLenMin[>..]&,
    snap_eqs: OptLenEq[>..]&,
    mut_syms: i64[>..]&,
    mut_fields: i64[>..]&,
    glen: i64 = 0,
    nlen: i64 = 0,
    alen: i64 = 0,
    mlen: i64 = 0,
    elen: i64 = 0,
    snap_depth: i64 = 0,
    sglen: i64 = 0,
    snlen: i64 = 0,
    salen: i64 = 0,
    smlen: i64 = 0,
    selen: i64 = 0,
    mut_slen: i64 = 0,
    mut_flen: i64 = 0,
    mut_arrays_gen: i64 = 0,
    mut_refs_gen: i64 = 0,
    mut_grow_gen: i64 = 0,
    mut_any_gen: i64 = 0,
    scan_budget: i64 = 0,
    has_break: bool = false,
    checkfree: i64 = -1,
    body: i64 = -1,
    inline_parent: i64 = -1, inline_parent_body: i64 = -1,
    // Scalar scratch outputs for zero-frame path/key matching.
    path_sym: i64 = -1, path_field: i64 = -1, path_imm: bool = false, path_delta: i64 = 0,
    key_sym: i64 = -1, key_field: i64 = -1, key_ref: bool = false,
}
struct OptBoundSnap {
    sg0: i64, sn0: i64, sa0: i64, sm0: i64, se0: i64,
    glen: i64, nlen: i64, alen: i64, mlen: i64, elen: i64,
}
struct OptMap { from: i64, to: i64 }
struct OptNodeMap { from: i64, to: i64 }
let OPT_ACTIVE: u8 = 1;
let OPT_DONE: u8 = 2;
let OPT_DEP_KNOWN: u8 = 4;
let OPT_DEP_BAD: u8 = 8;
let OPT_SDEP_KNOWN: u8 = 16;
let OPT_SDEP_BAD: u8 = 32;
let OPT_HAS_INDEX: u8 = 64;
let OPT_HAS_BREAK: u8 = 128;
struct Optimizer {
    first_free_slots: const i64[:],
    facts: OptFact[>..]&, function_states: u8[>..]&, maps: OptMap[>..]&, node_maps: OptNodeMap[>..]&, dependency_work: i64[>..]&, proof_old: i64[>..]&, proof_new: i64[>..]&,
    inlined_blocks: i64[>..]&,
    current_function: i64 = -1, next_slot: i64 = 0, folded: i64 = 0, propagated: i64 = 0,
    inlined: i64 = 0, tail_loops: i64 = 0, has_index: bool = false, has_break: bool = false,
    // While a library body is copied into the program's code, the call its
    // library nodes report at (opt_note_site); -1 otherwise.
    site: i64 = -1,
}
fn opt_fact(o: Optimizer&, symbol: i64) {
    while o.facts.len <= symbol { o.facts.push(OptFact {}); }
}
fn opt_mark_break(o: Optimizer&, target: i64) {
    if target < 0 { o.has_break = true; return; }
    while o.function_states.len <= target { o.function_states.push(0); }
    o.function_states[target] |= OPT_HAS_BREAK;
}
fn opt_literal(p: Program&, node: i64) -> bool {
    if node < 0 { return false; }
    let kind = p.nodes[node].kind;
    return kind == N_INTEGER || kind == N_FLOAT || kind == N_BOOL || kind == N_NULL;
}
fn opt_replace(p: Program&, o: Optimizer&, destination: i64, source: i64) {
    let next = p.nodes[destination].next; let token = p.nodes[destination].token;
    let type_id = p.nodes[destination].type_id; let coerced_type = p.nodes[destination].coerced_type; let tail = p.nodes[destination].flags & F_TAIL;
    let replacement = p.nodes[source];
    p.nodes[destination] = replacement; p.nodes[destination].next = next; p.nodes[destination].token = token;
    p.nodes[destination].flags |= tail;
    if type_id >= 0 { p.nodes[destination].type_id = type_id; }
    if coerced_type >= 0 { p.nodes[destination].coerced_type = coerced_type; }
    if replacement.kind == N_FLOAT {
        let value = opt_float_value(p, replacement.type_id, replacement.float_value);
        p.nodes[destination].float_value = opt_float_value(p, p.nodes[destination].type_id, value);
    } else if replacement.kind == N_BLOCK && (replacement.flags & F_EARLY) != 0 && replacement.origin >= 0 {
        o.inlined_blocks.push(destination);
    }
    if destination != source && (replacement.kind == N_BLOCK && (replacement.flags & F_EARLY) != 0 ||
        replacement.kind == N_LOOP || replacement.kind == N_FOR || replacement.kind == N_WHILE) {
        check_retarget_exits(p, destination, source, destination);
        if source < o.function_states.len && (o.function_states[source] & OPT_HAS_BREAK) != 0 {
            opt_mark_break(o, destination);
        }
    }
}
fn opt_set_integer(p: Program&, node: i64, value: i64, kind: i64) {
    let tok = p.nodes[node].token; let nxt = p.nodes[node].next;
    let ty = p.nodes[node].type_id; let fl = p.nodes[node].flags; let sc = p.nodes[node].scope;
    p.nodes[node] = Node { kind: kind, token: tok, next: nxt, type_id: ty, integer: value, flags: fl | F_CHECKED, scope: sc };
}
fn opt_float_value(p: Program&, type_id: i64, value: f64) -> f64 {
    if check_numeric_value_type(p, type_id) == TYPE_F32 { return (value as! f32) as f64; }
    return value;
}
fn opt_set_float(p: Program&, node: i64, value: f64) {
    let tok = p.nodes[node].token; let nxt = p.nodes[node].next;
    let ty = p.nodes[node].type_id; let fl = p.nodes[node].flags; let sc = p.nodes[node].scope;
    p.nodes[node] = Node { kind: N_FLOAT, token: tok, next: nxt, type_id: ty, float_value: opt_float_value(p, ty, value), flags: fl | F_CHECKED, scope: sc };
}
fn opt_empty(p: Program&, node: i64) {
    let tok = p.nodes[node].token; let nxt = p.nodes[node].next; let sc = p.nodes[node].scope;
    p.nodes[node] = Node { kind: N_EMPTY, token: tok, next: nxt, type_id: TYPE_VOID, flags: F_CHECKED, scope: sc };
}
// Bitwise arithmetic makes release wrapping independent of the bootstrap
// compiler's own debug-overflow instrumentation.
fn opt_add_bits(a: u64, b: u64) -> u64 {
    var x = a; var carry = b;
    while carry != 0 { let next = (x & carry) << 1; x = x ^ carry; carry = next; }
    return x;
}
fn opt_mul_bits(a: u64, b: u64) -> u64 {
    var x = a; var y = b; var result: u64 = 0;
    while y != 0 { if (y & 1) != 0 { result = opt_add_bits(result, x); } x = x << 1; y = y >> 1; }
    return result;
}
recursive fn opt_mark_index_vars(p: Program&, o: Optimizer&, node: i64) {
    if node < 0 { return; }
    let n: const Node& = p.nodes[node];
    let k = n.kind;
    if k == N_NAME {
        if n.symbol >= 0 { opt_fact(o, n.symbol); o.facts[n.symbol].flags |= OPT_FACT_INDEX_VAR; }
        return;
    }
    if k == N_CAST || k == N_MEMBER || k == N_UNARY { opt_mark_index_vars(p, o, n.left); return; }
    if k == N_BINARY { opt_mark_index_vars(p, o, n.left); opt_mark_index_vars(p, o, n.right); }
}
recursive fn opt_collect(p: Program&, o: Optimizer&, node: i64) {
    if node < 0 { return; }
    let n: const Node& = p.nodes[node];
    let kind = n.kind;
    if kind == N_NAME || kind == N_INTEGER || kind == N_FLOAT || kind == N_BOOL || kind == N_NULL || kind == N_STRING ||
       kind == N_EMPTY || kind == N_CONTINUE || kind == N_FUNCTION || kind == N_FUNCTION_VALUE { return; }
    if kind == N_INDEX {
        opt_mark_index_vars(p, o, n.right);
    } else if kind == N_FOR && n.left >= 0 && p.nodes[n.left].kind == N_RANGE {
        opt_mark_index_vars(p, o, p.nodes[n.left].left);
    } else if kind == N_BINARY && (n.integer == T_LT || n.integer == T_LTEQ || n.integer == T_GT || n.integer == T_GTEQ) {
        if n.right >= 0 && p.nodes[n.right].kind == N_CALL && p.nodes[n.right].symbol >= 0 &&
           (p.symbols[p.nodes[n.right].symbol].flags & S_BUILTIN) != 0 && p.symbols[p.nodes[n.right].symbol].index == 21 {
            opt_mark_index_vars(p, o, n.left);
        } else if n.left >= 0 && p.nodes[n.left].kind == N_CALL && p.nodes[n.left].symbol >= 0 &&
                  (p.symbols[p.nodes[n.left].symbol].flags & S_BUILTIN) != 0 && p.symbols[p.nodes[n.left].symbol].index == 21 {
            opt_mark_index_vars(p, o, n.right);
        }
    } else if kind == N_ASSIGN || kind == N_MULTI_ASSIGN {
        var target = n.left; if kind == N_MULTI_ASSIGN { target = n.first; }
        while target >= 0 {
            let symbol = check_place_root(p, target);
            if symbol >= 0 {
                opt_fact(o, symbol);
                var f: u32 = OPT_FACT_WRITTEN;
                if p.nodes[target].kind == N_NAME && p.nodes[target].symbol == symbol { f |= OPT_FACT_DIRECT_WRITTEN; }
                o.facts[symbol].flags |= f;
            }
            if kind != N_MULTI_ASSIGN { break; }
            target = p.nodes[target].next;
        }
    } else if kind == N_UNARY && n.integer == T_BITAND {
        let symbol = check_place_root(p, n.left);
        if symbol >= 0 { opt_fact(o, symbol); o.facts[symbol].flags |= OPT_FACT_ADDRESSED; }
    } else if kind == N_CALL && n.symbol >= 0 {
        opt_fact(o, n.symbol); o.facts[n.symbol].calls += 1;
        let s: const Symbol& = p.symbols[n.symbol];
        if (s.flags & S_BUILTIN) != 0 && (s.index == 2 || s.index >= 24) && n.first >= 0 {
            let root = check_place_root(p, n.first);
            if root >= 0 { opt_fact(o, root); o.facts[root].flags |= OPT_FACT_WRITTEN; }
        }
    }
    var child = n.first;
    while child >= 0 {
        let ck = p.nodes[child].kind;
        if ck < N_INTEGER || ck > N_NAME { opt_collect(p, o, child); }
        child = p.nodes[child].next;
    }
    if n.left >= 0 && kind != N_RECORD && kind != N_VARIABLE && kind != N_PARAM && kind != N_FIELD {
        let lk = p.nodes[n.left].kind;
        if lk < N_INTEGER || lk > N_NAME { opt_collect(p, o, n.left); }
    }
    if n.right >= 0 {
        let rk = p.nodes[n.right].kind;
        if rk < N_INTEGER || rk > N_NAME { opt_collect(p, o, n.right); }
    }
    if n.third >= 0 && kind != N_CALL {
        let tk = p.nodes[n.third].kind;
        if tk < N_INTEGER || tk > N_NAME { opt_collect(p, o, n.third); }
    }
}
// Callers only need the exact cost up to their remaining inlining budget.
recursive fn opt_inline_cost(p: Program&, node: i64, budget: i64) -> i64 {
    if node < 0 { return 0; }
    let n: const Node& = p.nodes[node];
    let kind = n.kind;
    if kind >= N_INTEGER && kind <= N_NULL || kind == N_NAME && n.first < 0 && n.left < 0 && n.right < 0 && n.third < 0 { return 1; }
    if kind == N_FUNCTION || kind == N_FUNCTION_VALUE { return 0; }
    var cost = 1;
    var child = n.first;
    while child >= 0 && cost <= budget {
        let ck = p.nodes[child].kind;
        if ck >= N_INTEGER && ck <= N_NULL { cost += 1; }
        else { cost += opt_inline_cost(p, child, budget - cost); }
        child = p.nodes[child].next;
    }
    if cost <= budget && n.left >= 0 && kind != N_VARIABLE && kind != N_PARAM && kind != N_FIELD && kind != N_RECORD {
        let lk = p.nodes[n.left].kind;
        if lk >= N_INTEGER && lk <= N_NULL { cost += 1; }
        else { cost += opt_inline_cost(p, n.left, budget - cost); }
    }
    if cost <= budget && n.right >= 0 {
        let rk = p.nodes[n.right].kind;
        if rk >= N_INTEGER && rk <= N_NULL { cost += 1; }
        else { cost += opt_inline_cost(p, n.right, budget - cost); }
    }
    if cost <= budget && n.third >= 0 && (kind != N_CALL || (n.flags & F_DISPATCH) != 0) {
        let tk = p.nodes[n.third].kind;
        if tk >= N_INTEGER && tk <= N_NULL { cost += 1; }
        else { cost += opt_inline_cost(p, n.third, budget - cost); }
    }
    return cost;
}
recursive fn opt_separate_tree(p: Program&, o: Optimizer&, node: i64, owner: i64, visited_start: i64, strict: bool) -> bool {
    if node < 0 { return false; }
    let n: const Node& = p.nodes[node];
    let kind = n.kind;
    if kind == N_NAME { return n.symbol >= 0 && n.symbol < p.symbols.len && p.symbols[n.symbol].owner == owner; }
    if kind >= N_INTEGER && kind <= N_STRING || kind == N_EMPTY || kind == N_CONTINUE || kind == N_FUNCTION || kind == N_FUNCTION_VALUE { return false; }
    if kind == N_RETURN && n.symbol == p.nodes[owner].symbol { return true; }
    if kind == N_CALL {
        if strict && (n.flags & F_DISPATCH) != 0 { return true; }
        if opt_separate_call(p, o, n.symbol, owner, visited_start, strict) { return true; }
    }
    var child = n.first; if kind == N_PATTERN { child = -1; }
    while child >= 0 {
        let ck = p.nodes[child].kind;
        if ck < N_INTEGER || ck > N_STRING {
            if opt_separate_tree(p, o, child, owner, visited_start, strict) { return true; }
        }
        child = p.nodes[child].next;
    }
    // These nodes also own linked expression lists outside their first list.
    var extra = -1;
    if strict && kind == N_VARIABLE { extra = n.right; }
    if strict && kind == N_BREAK { extra = n.left; }
    while extra >= 0 {
        extra = p.nodes[extra].next;
        if extra >= 0 && opt_separate_tree(p, o, extra, owner, visited_start, strict) { return true; }
    }
    if n.left >= 0 && kind != N_RECORD && kind != N_VARIABLE && kind != N_PARAM && kind != N_FIELD {
        let lk = p.nodes[n.left].kind;
        if (lk < N_INTEGER || lk > N_STRING) && opt_separate_tree(p, o, n.left, owner, visited_start, strict) { return true; }
    }
    if n.right >= 0 {
        let rk = p.nodes[n.right].kind;
        if (rk < N_INTEGER || rk > N_STRING) && opt_separate_tree(p, o, n.right, owner, visited_start, strict) { return true; }
    }
    if n.third >= 0 {
        let tk = p.nodes[n.third].kind;
        if (tk < N_INTEGER || tk > N_STRING) && opt_separate_tree(p, o, n.third, owner, visited_start, strict) { return true; }
    }
    return false;
}
recursive fn opt_separate_call(p: Program&, o: Optimizer&, symbol: i64, owner: i64, visited_start: i64, strict: bool) -> bool {
    if symbol < 0 { return strict; }
    if strict && symbol >= p.symbols.len { return true; }
    let called: const Symbol& = p.symbols[symbol];
    if (called.flags & S_BUILTIN) != 0 {
        // Spawn workers and reusable-slice defaults live outside this call graph.
        if strict && (called.index < 0 || called.index > 35 || called.index == 7 || called.index == 8 || called.index == 33 || called.index == 34) { return true; }
        return false;
    }
    if (called.flags & S_EXTERN) != 0 { return strict; }
    let function_node = called.node;
    if function_node < 0 { return strict; }
    if strict {
        if function_node >= p.nodes.len || (called.flags & S_FUNCTION) == 0 { return true; }
        let function: const Node& = p.nodes[function_node];
        if (function.kind != N_FUNCTION && function.kind != N_FUNCTION_VALUE) || function.right < 0 { return true; }
    }
    if function_node == owner { return true; }
    for index in visited_start..o.dependency_work.len { if o.dependency_work[index] == function_node { return false; } }
    o.dependency_work.push(function_node);
    return opt_separate_tree(p, o, p.nodes[function_node].right, owner, visited_start, strict);
}
recursive fn opt_inline_dependencies(p: Program&, o: Optimizer&, node: i64, owner: i64, strict: bool) -> bool {
    if node < 0 { return false; }
    let n: const Node& = p.nodes[node];
    let kind = n.kind;
    if kind >= N_INTEGER && kind <= N_NULL || kind == N_EMPTY || kind == N_CONTINUE || kind == N_FUNCTION || kind == N_FUNCTION_VALUE { return false; }
    if kind == N_CALL {
        if strict && (n.flags & F_DISPATCH) != 0 { return true; }
        if opt_separate_call(p, o, n.symbol, owner, o.dependency_work.len, strict) { return true; }
    }
    var child = n.first; if kind == N_PATTERN { child = -1; }
    while child >= 0 {
        let ck = p.nodes[child].kind;
        if (ck < N_INTEGER || ck > N_NULL) && opt_inline_dependencies(p, o, child, owner, strict) { return true; }
        child = p.nodes[child].next;
    }
    var extra = -1;
    if strict && kind == N_VARIABLE { extra = n.right; }
    if strict && kind == N_BREAK { extra = n.left; }
    while extra >= 0 {
        extra = p.nodes[extra].next;
        if extra >= 0 && opt_inline_dependencies(p, o, extra, owner, strict) { return true; }
    }
    if n.left >= 0 && kind != N_RECORD && kind != N_VARIABLE && kind != N_PARAM && kind != N_FIELD {
        let lk = p.nodes[n.left].kind;
        if (lk < N_INTEGER || lk > N_NULL) && opt_inline_dependencies(p, o, n.left, owner, strict) { return true; }
    }
    if n.right >= 0 {
        let rk = p.nodes[n.right].kind;
        if (rk < N_INTEGER || rk > N_NULL) && opt_inline_dependencies(p, o, n.right, owner, strict) { return true; }
    }
    if n.third >= 0 {
        let tk = p.nodes[n.third].kind;
        if (tk < N_INTEGER || tk > N_NULL) && opt_inline_dependencies(p, o, n.third, owner, strict) { return true; }
    }
    return false;
}
fn opt_inline_dependencies_cached(p: Program&, o: Optimizer&, fn_node: i64, strict: bool) -> bool {
    if fn_node >= o.function_states.len { o.function_states.resize(p.nodes.len, 0); }
    let known_bit = if strict { OPT_SDEP_KNOWN } else { OPT_DEP_KNOWN };
    let bad_bit = if strict { OPT_SDEP_BAD } else { OPT_DEP_BAD };
    let st = o.function_states[fn_node];
    if (st & known_bit) != 0 { return (st & bad_bit) != 0; }
    let bad = opt_inline_dependencies(p, o, p.nodes[fn_node].right, fn_node, strict);
    if bad { o.function_states[fn_node] = st | known_bit | bad_bit; }
    else { o.function_states[fn_node] = st | known_bit; }
    return bad;
}
// A copy fails where its original does (location_token): a library node an
// inline from the library into the program's code copies reports that call,
// o.site, and a copy of a node so re-anchored keeps its place. Copies are
// made in ascending node order, which keeps p.inline_sites sorted.
fn opt_note_site(p: Program&, o: Optimizer&, original: i64, copy: i64) {
    let token = location_token(p, original); var site = -1;
    if library_token(p, token) { site = o.site; }
    else if token != p.nodes[original].token { site = token; }
    if site < 0 { return; }
    let last = p.inline_sites.len - 1;
    if last >= 0 && p.inline_sites[last].end == copy && p.inline_sites[last].site == site { p.inline_sites[last].end = copy + 1; return; }
    p.inline_sites.push(InlineSite { first: copy, end: copy + 1, site: site });
}
fn opt_mapped_symbol(o: Optimizer&, symbol: i64, map_start: i64) -> i64 {
    for index in map_start..o.maps.len { if o.maps[index].from == symbol { return o.maps[index].to; } }
    return symbol;
}
fn opt_copy_fact(o: Optimizer&, from: i64, to: i64) {
    opt_fact(o, from); opt_fact(o, to); o.facts[to] = o.facts[from]; o.facts[to].literal = -1;
}
recursive fn opt_clone(p: Program&, o: Optimizer&, node: i64, map_start: i64) -> i64 {
    if node < 0 { return -1; }
    var n = p.nodes[node]; let first = n.first; let left = n.left; let right = n.right; let third = n.third;
    n.first = -1; n.last = -1; n.left = -1; n.right = -1; n.third = -1; n.next = -1;
    if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE {
        let empty = new_node(p, N_EMPTY, n.token); p.nodes[empty].flags = F_CHECKED; p.nodes[empty].type_id = TYPE_VOID; return empty;
    }
    let result = p.nodes.len; p.nodes.push(n); o.node_maps.push(OptNodeMap { from: node, to: result });
    if (o.site >= 0 || p.inline_sites.len > 0 && node >= p.inline_sites[0].first) && library_token(p, n.token) {
        opt_note_site(p, o, node, result);
    }
    if n.kind >= N_INTEGER && n.kind <= N_NULL || n.kind == N_NAME && first < 0 && left < 0 && right < 0 && third < 0 { return result; }
    if n.kind == N_BLOCK && (n.flags & F_EARLY) != 0 && n.origin >= 0 { o.inlined_blocks.push(result); }
    if (n.kind == N_BINDING || n.kind == N_VARIABLE) && n.symbol >= 0 && n.symbol < p.symbols.len && p.symbols[n.symbol].node == node {
        var symbol = p.symbols[n.symbol]; let original = n.symbol;
        symbol.node = result; symbol.owner = o.current_function; symbol.scope = -2;
        symbol.slot = o.next_slot; o.next_slot++; symbol.next = -1; symbol.flags &= ~(S_PARAMETER | S_GLOBAL | S_CAPTURE);
        let id = p.symbols.len; p.symbols.push(symbol); p.nodes[result].symbol = id;
        o.maps.push(OptMap { from: original, to: id }); opt_copy_fact(o, original, id);
    }
    var child = first;
    while child >= 0 { append_child(p, result, opt_clone(p, o, child, map_start)); child = p.nodes[child].next; }
    if left >= 0 {
        p.nodes[result].left = opt_clone(p, o, left, map_start);
        if n.kind == N_BREAK {
            var previous = p.nodes[result].left; var old = p.nodes[left].next;
            while old >= 0 { let copy = opt_clone(p, o, old, map_start); p.nodes[previous].next = copy; previous = copy; old = p.nodes[old].next; }
        }
    }
    if n.kind == N_RECORD { p.nodes[result].right = right; }
    else if right >= 0 {
        p.nodes[result].right = opt_clone(p, o, right, map_start);
        if n.kind == N_VARIABLE {
            var previous = p.nodes[result].right; var old = p.nodes[right].next;
            while old >= 0 { let copy = opt_clone(p, o, old, map_start); p.nodes[previous].next = copy; previous = copy; old = p.nodes[old].next; }
        }
    }
    if third >= 0 && (n.kind != N_CALL || (n.flags & F_DISPATCH) != 0) {
        p.nodes[result].third = opt_clone(p, o, third, map_start);
        if n.kind == N_CALL && (n.flags & F_DISPATCH) != 0 {
            var previous = p.nodes[result].third; var old = p.nodes[third].next;
            while old >= 0 { let copy = opt_clone(p, o, old, map_start); p.nodes[previous].next = copy; previous = copy; old = p.nodes[old].next; }
        }
    }
    return result;
}
fn opt_capture(p: Program&, function_node: i64, symbol: i64) {
    if function_node < 0 || symbol < 0 || symbol >= p.symbols.len { return; }
    let owner = p.symbols[symbol].owner; let flags = p.symbols[symbol].flags;
    if owner < 0 || owner == function_node || (flags & (S_FUNCTION | S_TYPE | S_GLOBAL)) != 0 { return; }
    var binding = p.nodes[function_node].captures; var last = -1;
    while binding >= 0 { if p.nodes[binding].symbol == symbol { return; } last = binding; binding = p.nodes[binding].next; }
    let name_token = p.symbols[symbol].name_token; let type_id = p.symbols[symbol].type_id;
    let capture = new_node(p, N_BINDING, name_token); p.nodes[capture].symbol = symbol; p.nodes[capture].type_id = type_id;
    if last < 0 { p.nodes[function_node].captures = capture; } else { p.nodes[last].next = capture; }
    p.nodes[function_node].flags |= F_CAPTURE; p.symbols[symbol].flags |= S_CAPTURE;
}
recursive fn opt_fix_inline(p: Program&, o: Optimizer&, node: i64, callee: i64, target: i64, map_start: i64, node_start: i64) {
    if node < 0 { return; }
    var kind = p.nodes[node].kind;
    if kind == N_INTEGER || kind == N_FLOAT || kind == N_BOOL || kind == N_NULL || kind == N_STRING || kind == N_EMPTY || kind == N_FUNCTION || kind == N_FUNCTION_VALUE { return; }
    let sym = p.nodes[node].symbol;
    if kind == N_NAME {
        let mapped = opt_mapped_symbol(o, sym, map_start);
        p.nodes[node].symbol = mapped;
        opt_capture(p, o.current_function, mapped);
        return;
    }
    if kind == N_VARIABLE || kind == N_BINDING && sym >= 0 && sym < p.symbols.len && p.symbols[sym].node == node {
        p.nodes[node].symbol = opt_mapped_symbol(o, sym, map_start);
    }
    if kind == N_RETURN && sym == callee {
        p.nodes[node].kind = N_BREAK; p.nodes[node].symbol = target; p.nodes[node].left = p.nodes[node].first;
        p.nodes[node].first = -1; p.nodes[node].last = -1; p.nodes[node].flags &= ~F_NONLOCAL; kind = N_BREAK;
    } else if kind == N_RETURN && o.current_function >= 0 && sym == p.nodes[o.current_function].symbol { p.nodes[node].flags &= ~F_NONLOCAL; }
    if kind == N_BREAK || kind == N_CONTINUE {
        let cur_sym = p.nodes[node].symbol;
        for index in node_start..o.node_maps.len { let map: const OptNodeMap& = o.node_maps[index]; if cur_sym == map.from { p.nodes[node].symbol = map.to; break; } }
        if kind == N_BREAK { opt_mark_break(o, p.nodes[node].symbol); }
    }
    let first = p.nodes[node].first; let left = p.nodes[node].left;
    let right = p.nodes[node].right; let third = p.nodes[node].third;
    let flags = p.nodes[node].flags;
    var child = first; if kind == N_PATTERN { child = -1; }
    while child >= 0 {
        let ck = p.nodes[child].kind;
        if ck < N_INTEGER || ck > N_STRING { opt_fix_inline(p, o, child, callee, target, map_start, node_start); }
        child = p.nodes[child].next;
    }
    if kind == N_BREAK {
        child = left;
        while child >= 0 {
            let ck = p.nodes[child].kind;
            if ck < N_INTEGER || ck > N_STRING { opt_fix_inline(p, o, child, callee, target, map_start, node_start); }
            child = p.nodes[child].next;
        }
    } else if left >= 0 && kind != N_RECORD && kind != N_VARIABLE && kind != N_PARAM && kind != N_FIELD {
        let lk = p.nodes[left].kind;
        if lk < N_INTEGER || lk > N_STRING { opt_fix_inline(p, o, left, callee, target, map_start, node_start); }
    }
    if right >= 0 {
        let rk = p.nodes[right].kind;
        if rk < N_INTEGER || rk > N_STRING { opt_fix_inline(p, o, right, callee, target, map_start, node_start); }
    }
    if third >= 0 && (kind != N_CALL || (flags & F_DISPATCH) != 0) {
        let tk = p.nodes[third].kind;
        if tk < N_INTEGER || tk > N_STRING { opt_fix_inline(p, o, third, callee, target, map_start, node_start); }
    }
}

fn opt_temporary(p: Program&, o: Optimizer&, owner: i64, scope: i64, token: i64, ty: i64, value: i64) -> i64 {
    let node = new_node(p, N_VARIABLE, token);
    let symbol = p.symbols.len; let slot = o.next_slot; o.next_slot++;
    p.symbols.push(Symbol { name_token: token, type_id: ty, node: node, scope: -2, slot: slot, owner: owner });
    p.nodes[node].symbol = symbol; p.nodes[node].type_id = ty; p.nodes[node].right = value;
    p.nodes[node].scope = scope; p.nodes[node].flags = F_CHECKED;
    return node;
}
recursive fn opt_try_inline(p: Program&, o: Optimizer&, node: i64) -> bool {
    if o.current_function < 0 { return false; }
    let strict = (p.nodes[o.current_function].flags & F_RECURSIVE) != 0;
    let call_flags = p.nodes[node].flags;
    let call_symbol = p.nodes[node].symbol;
    if (call_flags & F_DISPATCH) != 0 || call_symbol < 0 || call_symbol >= p.symbols.len { return false; }
    let sym_flags = p.symbols[call_symbol].flags;
    let callee_node = p.symbols[call_symbol].node;
    if (sym_flags & (S_BUILTIN | S_EXTERN)) != 0 || callee_node < 0 { return false; }
    // Inlining an explicitly inline checkfree helper lets the same bounds
    // analysis use the caller's length facts at every optimization level.
    if p.optimization <= 0 && ((p.nodes[callee_node].flags & (F_INLINE | F_CHECKFREE)) != (F_INLINE | F_CHECKFREE) ||
                               !validation_checkfree(p, o.current_function)) { return false; }
    if strict && (p.nodes[callee_node].flags & F_INLINE) == 0 { return false; }
    if callee_node < o.function_states.len && (o.function_states[callee_node] & OPT_ACTIVE) != 0 { return false; }
    opt_function(p, o, callee_node);
    let callee_flags = p.nodes[callee_node].flags;
    let callee_right = p.nodes[callee_node].right;
    if (callee_flags & F_RECURSIVE) != 0 || callee_right < 0 { return false; }
    let callee_first = p.nodes[callee_node].first;
    let call_first = p.nodes[node].first;
    if check_list_count(p, callee_first) != check_list_count(p, call_first) { return false; }
    var threshold = 8; var use_threshold = 48;
    if p.optimization >= 2 { threshold = 16; use_threshold = 96; }
    opt_fact(o, call_symbol); var uses: i64 = o.facts[call_symbol].calls; if uses < 1 { uses = 1; }
    var budget = threshold;
    if use_threshold / uses > budget { budget = use_threshold / uses; }
    if uses == 1 && budget < 200 { budget = 200; }
    if (callee_flags & F_INLINE) != 0 { budget = 200; }
    let cost = opt_inline_cost(p, callee_right, budget);
    if cost > budget || opt_inline_dependencies_cached(p, o, callee_node, strict) { return false; }
    let call_tok = p.nodes[node].token; let call_ty = p.nodes[node].type_id; let call_scope = p.nodes[node].scope;
    let map_start = o.maps.len; let node_start = o.node_maps.len;
    // A library body copied into the program's code, but into a checkfree
    // function, has its library nodes report at the call (upstream AtCallSite).
    let site = location_token(p, node); let outer_site = o.site; o.site = -1;
    if library_node(p, callee_node) && !library_token(p, site) && (p.nodes[o.current_function].flags & F_CHECKFREE) == 0 { o.site = site; }
    let inline_body = new_node(p, N_BLOCK, call_tok); p.nodes[inline_body].flags = F_CHECKED | F_EARLY | (call_flags & F_DIVERGES);
    p.nodes[inline_body].type_id = call_ty; p.nodes[inline_body].scope = call_scope;
    p.nodes[inline_body].origin = callee_node; p.nodes[inline_body].symbol = call_symbol;
    var formal = callee_first; var argument = call_first;
    while formal >= 0 {
        let next = p.nodes[argument].next; p.nodes[argument].next = -1;
        let local = opt_temporary(p, o, o.current_function, call_scope, p.nodes[formal].token, p.nodes[formal].type_id, argument);
        p.nodes[local].origin = formal; opt_note_site(p, o, formal, local);
        append_child(p, inline_body, local);
        o.maps.push(OptMap { from: p.nodes[formal].symbol, to: p.nodes[local].symbol }); opt_copy_fact(o, p.nodes[formal].symbol, p.nodes[local].symbol);
        if (o.facts[p.nodes[formal].symbol].flags & OPT_FACT_INDEX_VAR) != 0 { opt_mark_index_vars(p, o, argument); }
        formal = p.nodes[formal].next; argument = next;
    }
    let body = opt_clone(p, o, callee_right, map_start); o.site = outer_site;
    opt_fix_inline(p, o, body, call_symbol, inline_body, map_start, node_start);
    var child = p.nodes[body].first;
    while child >= 0 { let next = p.nodes[child].next; p.nodes[child].next = -1; append_child(p, inline_body, child); child = next; }
    let proof_start = o.proof_old.len;
    for index in map_start..o.maps.len { o.proof_old.push(o.maps[index].from); o.proof_new.push(o.maps[index].to); }
    life_clone_provenance(p, o.proof_old[proof_start..], o.proof_new[proof_start..]);
    opt_replace(p, o, node, inline_body); o.inlined += 1;
    opt_node(p, o, node, 1); return true;
}

fn opt_fold_binary(p: Program&, o: Optimizer&, node: i64) {
    let n: const Node& = p.nodes[node]; let left: const Node& = p.nodes[n.left]; let right: const Node& = p.nodes[n.right]; let op = n.integer;
    if left.kind == N_INTEGER && right.kind == N_INTEGER {
        let a = left.integer; let b = right.integer; var result = 0; var folded = true; var comparison = false;
        let unsigned = check_unsigned(left.type_id);
        if op == T_PLUS {
            if p.debug && !opt_add_safe(a, b) { return; }
            if p.debug && !check_unsigned(n.type_id) && check_integer(n.type_id) &&
               (a + b < check_min(n.type_id) || a + b > check_max(n.type_id)) { return; }
            result = opt_wrap(opt_add_bits(a as! u64, b as! u64), n.type_id);
        } else if op == T_MINUS {
            if p.debug && !opt_sub_safe(a, b) { return; }
            if p.debug && !check_unsigned(n.type_id) && check_integer(n.type_id) &&
               (a - b < check_min(n.type_id) || a - b > check_max(n.type_id)) { return; }
            result = opt_wrap(opt_add_bits(opt_add_bits(a as! u64, ~(b as! u64)), 1), n.type_id);
        } else if op == T_MUL {
            if p.debug && !opt_mul_safe(a, b) { return; }
            if p.debug && !check_unsigned(n.type_id) && check_integer(n.type_id) &&
               (a * b < check_min(n.type_id) || a * b > check_max(n.type_id)) { return; }
            result = opt_wrap(opt_mul_bits(a as! u64, b as! u64), n.type_id);
        } else if op == T_DIV || op == T_MOD {
            if b == 0 || !unsigned && a == -9223372036854775808 && b == -1 { return; }
            if unsigned {
                if op == T_DIV { result = ((a as! u64) / (b as! u64)) as! i64; }
                else { result = ((a as! u64) % (b as! u64)) as! i64; }
            } else {
                if op == T_DIV { result = a / b; } else { result = a % b; }
            }
        } else if op == T_BITAND { result = a & b; }
        else if op == T_BITOR { result = a | b; }
        else if op == T_XOR { result = a ^ b; }
        else if op == T_SHL || op == T_SHR {
            if b < 0 || b >= check_integer_bits(left.type_id) { return; }
            if op == T_SHL { result = opt_wrap((a as! u64) << b, n.type_id); }
            else if unsigned { result = ((a as! u64) >> b) as! i64; }
            else { result = a >> b; }
        } else {
            var truth = false; comparison = true;
            if op == T_EQ { truth = a == b; }
            else if op == T_NEQ { truth = a != b; }
            else if op == T_LT { if unsigned { truth = (a as! u64) < (b as! u64); } else { truth = a < b; } }
            else if op == T_LTEQ { if unsigned { truth = (a as! u64) <= (b as! u64); } else { truth = a <= b; } }
            else if op == T_GT { if unsigned { truth = (a as! u64) > (b as! u64); } else { truth = a > b; } }
            else if op == T_GTEQ { if unsigned { truth = (a as! u64) >= (b as! u64); } else { truth = a >= b; } }
            else { folded = false; }
            if truth { result = 1; }
        }
        if folded {
            if p.debug && !comparison && check_integer(n.type_id) && !check_unsigned(n.type_id) &&
               (result < check_min(n.type_id) || result > check_max(n.type_id)) { return; }
            var kind = N_INTEGER; if comparison { kind = N_BOOL; }
            opt_set_integer(p, node, result, kind); o.folded += 1;
        }
    } else if left.kind == N_BOOL && right.kind == N_BOOL {
        var result = false; var valid = true;
        if op == T_EQ { result = left.integer == right.integer; }
        else if op == T_NEQ { result = left.integer != right.integer; }
        else if op == T_ANDAND { result = left.integer != 0 && right.integer != 0; }
        else if op == T_OROR { result = left.integer != 0 || right.integer != 0; }
        else { valid = false; }
        if valid { var value = 0; if result { value = 1; } opt_set_integer(p, node, value, N_BOOL); o.folded += 1; }
    } else if left.kind == N_FLOAT && right.kind == N_FLOAT {
        var a = left.float_value; var b = right.float_value; var value = 0.0; var valid = true;
        if n.type_id == TYPE_F32 || n.aux == TYPE_F32 { a = (a as! f32) as f64; b = (b as! f32) as f64; }
        if op == T_PLUS { value = a + b; } else if op == T_MINUS { value = a - b; }
        else if op == T_MUL { value = a * b; } else if op == T_DIV && b != 0.0 { value = a / b; }
        else { valid = false; }
        if valid && value == value && value > -1.0e308 && value < 1.0e308 {
            opt_set_float(p, node, value); o.folded += 1;
        }
    }
}

recursive fn opt_node(p: Program&, o: Optimizer&, node: i64, depth: i64) {
    if node < 0 || depth > 512 { return; }
    let entry: const Node& = p.nodes[node];
    let kind = entry.kind;
    // Checked float literals keep their value when propagation widens their type.
    if kind == N_INTEGER || kind == N_BOOL || kind == N_NULL || kind == N_STRING || kind == N_EMPTY || kind == N_CONTINUE ||
       kind == N_FUNCTION || kind == N_FUNCTION_VALUE || kind == N_STRUCT || kind == N_ENUM || kind == N_ALIAS || kind == N_PATTERN { return; }
    if kind == N_FLOAT { p.nodes[node].float_value = opt_float_value(p, entry.type_id, entry.float_value); return; }
    if kind == N_NAME {
        let sym = entry.symbol;
        if sym >= 0 && sym < o.facts.len {
            let fact: const OptFact& = o.facts[sym];
            if fact.literal >= 0 && (fact.flags & (OPT_FACT_WRITTEN | OPT_FACT_ADDRESSED)) == 0 {
                let type_id = entry.type_id; opt_replace(p, o, node, fact.literal); p.nodes[node].type_id = type_id; o.propagated += 1;
            }
        }
        return;
    }
    // Inlining can grow the node array. Keep just the traversal fields across child visits.
    let left = entry.left; let right = entry.right;
    let third = entry.third; let first = entry.first;
    let op = entry.integer;
    var left_done = false;
    if kind == N_IF {
        left_done = true;
        if left >= 0 { opt_node(p, o, left, depth + 1); }
        let condition: const Node& = p.nodes[left];
        if condition.kind == N_BOOL {
            var chosen = third; if condition.integer != 0 { chosen = right; }
            if chosen >= 0 { opt_node(p, o, chosen, depth + 1); opt_replace(p, o, node, chosen); }
            else { opt_empty(p, node); }
            o.folded += 1; return;
        }
    } else if kind == N_BINARY && (op == T_ANDAND || op == T_OROR) {
        left_done = true;
        if left >= 0 { opt_node(p, o, left, depth + 1); }
        let value: const Node& = p.nodes[left];
        if value.kind == N_BOOL {
            if op == T_ANDAND && value.integer == 0 || op == T_OROR && value.integer != 0 {
                opt_replace(p, o, node, left); o.folded += 1; return;
            }
            opt_node(p, o, right, depth + 1); opt_replace(p, o, node, right); o.folded += 1; return;
        }
    }
    var child = first;
    while child >= 0 {
        let next = p.nodes[child].next;
        let ck = p.nodes[child].kind;
        if ck != N_INTEGER && ck != N_BOOL && ck != N_NULL && ck != N_STRING && ck != N_EMPTY && ck != N_CONTINUE {
            opt_node(p, o, child, depth + 1);
        }
        child = next;
    }
    if kind == N_BREAK { opt_mark_break(o, p.nodes[node].symbol); }
    if !left_done && left >= 0 && kind != N_VARIABLE && kind != N_PARAM && kind != N_FIELD && kind != N_RECORD &&
       kind != N_ASSIGN && kind != N_MULTI_ASSIGN {
        let lk = p.nodes[left].kind;
        if lk != N_INTEGER && lk != N_BOOL && lk != N_NULL && lk != N_STRING && lk != N_EMPTY && lk != N_CONTINUE {
            opt_node(p, o, left, depth + 1);
        }
    } else if kind == N_ASSIGN {
        var target_id = left;
        while target_id >= 0 && p.nodes[target_id].kind == N_MEMBER { target_id = p.nodes[target_id].left; }
        if target_id >= 0 && p.nodes[target_id].kind == N_INDEX {
            o.has_index = true;
            opt_node(p, o, p.nodes[target_id].right, depth + 1);
        }
    }
    if right >= 0 {
        let rk = p.nodes[right].kind;
        if rk != N_INTEGER && rk != N_BOOL && rk != N_NULL && rk != N_STRING && rk != N_EMPTY && rk != N_CONTINUE {
            opt_node(p, o, right, depth + 1);
        }
    }
    if third >= 0 && kind != N_CALL {
        let tk = p.nodes[third].kind;
        if tk != N_INTEGER && tk != N_BOOL && tk != N_NULL && tk != N_STRING && tk != N_EMPTY && tk != N_CONTINUE {
            opt_node(p, o, third, depth + 1);
        }
    }
    if kind == N_MEMBER || kind == N_ASSIGN || kind == N_EXPR_STMT || kind == N_RETURN || kind == N_IF { return; }
    let n: const Node& = p.nodes[node];
    if n.kind == N_VARIABLE && n.symbol >= 0 && n.first < 0 {
        opt_fact(o, n.symbol); let fact: const OptFact& = o.facts[n.symbol];
        if (fact.flags & (OPT_FACT_WRITTEN | OPT_FACT_ADDRESSED)) == 0 && opt_literal(p, n.right) {
            o.facts[n.symbol].literal = n.right;
        }
    } else if n.kind == N_BINARY { opt_fold_binary(p, o, node); }
    else if n.kind == N_UNARY && n.left >= 0 {
        let value: const Node& = p.nodes[n.left];
        if value.kind == N_INTEGER {
            if n.integer == T_MINUS && (!p.debug || value.integer != check_min(n.type_id)) {
                let bits = opt_add_bits(~(value.integer as! u64), 1);
                opt_set_integer(p, node, opt_wrap(bits, n.type_id), N_INTEGER); o.folded += 1;
            } else if n.integer == T_BITNOT {
                opt_set_integer(p, node, opt_wrap(~(value.integer as! u64), n.type_id), N_INTEGER); o.folded += 1;
            }
        } else if value.kind == N_BOOL && n.integer == T_NOT {
            var result = 0; if value.integer == 0 { result = 1; }
            opt_set_integer(p, node, result, N_BOOL); o.folded += 1;
        } else if value.kind == N_FLOAT && n.integer == T_MINUS {
            opt_set_float(p, node, -value.float_value); o.folded += 1;
        }
    } else if n.kind == N_CAST && n.left >= 0 {
        let source: const Node& = p.nodes[n.left]; let destination = n.type_id;
        if source.kind == N_INTEGER && check_integer(destination) {
            if (n.flags & F_UNSIGNED) != 0 || source.integer >= check_min(destination) && source.integer <= check_max(destination) &&
               !(check_unsigned(source.type_id) && source.integer < 0 && destination != TYPE_U64) {
                opt_set_integer(p, node, opt_wrap(source.integer as! u64, destination), N_INTEGER); o.folded += 1;
            }
        } else if source.kind == N_FLOAT && check_float(destination) {
            opt_set_float(p, node, source.float_value); o.folded += 1;
        } else if source.kind == N_INTEGER && check_float(destination) {
            var value = source.integer as f64;
            let unsigned = check_unsigned(check_numeric_value_type(p, source.type_id));
            if unsigned { value = (source.integer as! u64) as f64; }
            if destination == TYPE_F32 {
                value = (source.integer as f32) as f64;
                if unsigned { value = ((source.integer as! u64) as f32) as f64; }
            }
            opt_set_float(p, node, value); o.folded += 1;
        }
    } else if n.kind == N_CALL && n.symbol >= 0 {
        let symbol: const Symbol& = p.symbols[n.symbol];
        if (symbol.flags & S_BUILTIN) != 0 && symbol.index == 21 && n.first >= 0 {
            let receiver: const Node& = p.nodes[n.first]; var length = -1;
            if receiver.kind == N_ARRAY && receiver.right < 0 { length = check_list_count(p, receiver.first); }
            if receiver.kind == N_STRING { length = p.tokens[receiver.token].text_len; }
            if receiver.type_id >= 0 && p.types[receiver.type_id].kind == TY_ARRAY && p.types[receiver.type_id].array_kind == A_FIXED &&
               receiver.kind == N_NAME { length = p.types[receiver.type_id].count; }
            // Array element expressions still have to execute, even for .len.
            if receiver.kind == N_ARRAY {
                var item = receiver.first;
                while item >= 0 { if !opt_literal(p, item) { length = -1; } item = p.nodes[item].next; }
            }
            if length >= 0 { opt_set_integer(p, node, length, N_INTEGER); o.folded += 1; }
        } else { opt_try_inline(p, o, node); }
    } else if n.kind == N_WHILE && n.left >= 0 && p.nodes[n.left].kind == N_BOOL && p.nodes[n.left].integer == 0 {
        opt_empty(p, node); o.folded += 1;
    } else if n.kind == N_FOR && n.left >= 0 && p.nodes[n.left].kind == N_RANGE {
        let range: const Node& = p.nodes[n.left];
        if p.nodes[range.left].kind == N_INTEGER && p.nodes[range.right].kind == N_INTEGER &&
           p.nodes[range.left].integer >= p.nodes[range.right].integer && (range.flags & F_INCLUSIVE) == 0 {
            opt_empty(p, node); o.folded += 1;
        }
    } else if n.kind == N_INDEX && n.right >= 0 {
        o.has_index = true;
        let index: const Node& = p.nodes[n.right]; let source: const Node& = p.nodes[n.left];
        if index.kind == N_INTEGER && index.integer >= 0 && source.type_id >= 0 &&
           p.types[source.type_id].kind == TY_ARRAY && p.types[source.type_id].array_kind == A_FIXED &&
           index.integer < p.types[source.type_id].count { p.nodes[node].flags |= F_BOUNDS_PROVEN; }
    } else if n.kind == N_BLOCK {
        var first = p.nodes[node].first; var last = -1; var current = first; var leaves = false;
        while current >= 0 {
            let next = p.nodes[current].next;
            if leaves { if last >= 0 { p.nodes[last].next = -1; } break; }
            if p.nodes[current].kind == N_EMPTY {
                if last < 0 { first = next; } else { p.nodes[last].next = next; }
            } else {
                last = current;
                let kind = p.nodes[current].kind;
                leaves = kind == N_RETURN || kind == N_BREAK || kind == N_CONTINUE;
                if kind == N_CALL && p.nodes[current].symbol >= 0 {
                    let s: const Symbol& = p.symbols[p.nodes[current].symbol];
                    leaves = (s.flags & S_BUILTIN) != 0 && (s.index == 4 || s.index == 5);
                }
            }
            current = next;
        }
        p.nodes[node].first = first; p.nodes[node].last = last;
    }
}
recursive fn opt_tail_rewrite(p: Program&, o: Optimizer&, node: i64, function_symbol: i64, loop_node: i64) -> i64 {
    if node < 0 { return 0; }
    let kind = p.nodes[node].kind;
    if kind == N_NAME || kind == N_INTEGER || kind == N_FLOAT || kind == N_BOOL || kind == N_NULL || kind == N_STRING ||
       kind == N_EMPTY || kind == N_CONTINUE || kind == N_FUNCTION || kind == N_FUNCTION_VALUE { return 0; }
    let n_first = p.nodes[node].first; let n_left = p.nodes[node].left;
    let n_right = p.nodes[node].right; let n_third = p.nodes[node].third;
    var changed = 0;
    if kind == N_RETURN && p.nodes[node].symbol == function_symbol && n_first >= 0 && p.nodes[n_first].next < 0 {
        if p.nodes[n_first].kind == N_CALL && p.nodes[n_first].symbol == function_symbol && (p.nodes[n_first].flags & F_DISPATCH) == 0 {
            let n_tok = p.nodes[node].token; let n_scope = p.nodes[node].scope;
            let call_first = p.nodes[n_first].first;
            let function_node = p.symbols[function_symbol].node;
            let inline_body = new_node(p, N_BLOCK, n_tok); p.nodes[inline_body].type_id = TYPE_VOID;
            p.nodes[inline_body].flags = F_CHECKED; p.nodes[inline_body].scope = n_scope;
            var temp_count = 0; var formal = p.nodes[function_node].first; var argument = call_first;
            while formal >= 0 && argument >= 0 {
                let next = p.nodes[argument].next; p.nodes[argument].next = -1;
                let temp = opt_temporary(p, o, function_node, n_scope, p.nodes[formal].token, p.nodes[formal].type_id, argument);
                p.nodes[temp].origin = formal;
                append_child(p, inline_body, temp); temp_count += 1;
                formal = p.nodes[formal].next; argument = next;
            }
            formal = p.nodes[function_node].first;
            var temp = p.nodes[inline_body].first;
            for temp_index in 0..temp_count {
                let next_temp = p.nodes[temp].next;
                let left = new_node(p, N_NAME, p.nodes[formal].token);
                p.nodes[left].symbol = p.nodes[formal].symbol; p.nodes[left].type_id = p.nodes[formal].type_id;
                let right = new_node(p, N_NAME, p.nodes[temp].token);
                p.nodes[right].symbol = p.nodes[temp].symbol; p.nodes[right].type_id = p.nodes[temp].type_id;
                let assign = new_node(p, N_ASSIGN, n_tok);
                p.nodes[assign].left = left; p.nodes[assign].right = right; p.nodes[assign].integer = T_ASSIGN;
                p.nodes[assign].type_id = TYPE_VOID; p.nodes[assign].flags = F_CHECKED;
                append_child(p, inline_body, assign); formal = p.nodes[formal].next; temp = next_temp;
            }
            let jump = new_node(p, N_CONTINUE, n_tok); p.nodes[jump].symbol = loop_node;
            p.nodes[jump].type_id = TYPE_VOID; p.nodes[jump].flags = F_CHECKED;
            append_child(p, inline_body, jump); opt_replace(p, o, node, inline_body); return 1;
        }
    }
    var child = n_first;
    while child >= 0 { changed += opt_tail_rewrite(p, o, child, function_symbol, loop_node); child = p.nodes[child].next; }
    if n_left >= 0 { changed += opt_tail_rewrite(p, o, n_left, function_symbol, loop_node); }
    if n_right >= 0 { changed += opt_tail_rewrite(p, o, n_right, function_symbol, loop_node); }
    if n_third >= 0 { changed += opt_tail_rewrite(p, o, n_third, function_symbol, loop_node); }
    return changed;
}
// Whether the tree holds a `defer` (§6.6, upstream HasDefer). Its body runs
// once the call returns, after the self-call a tail loop would replace.
recursive fn opt_has_defer(p: Program&, node: i64) -> bool {
    if node < 0 { return false; }
    let n: const Node& = p.nodes[node];
    let k = n.kind;
    if k == N_DEFER { return true; }
    if k >= N_INTEGER && k <= N_NAME || k == N_EMPTY || k == N_CONTINUE || k == N_FUNCTION || k == N_FUNCTION_VALUE { return false; }
    var child = n.first;
    while child >= 0 { if opt_has_defer(p, child) { return true; } child = p.nodes[child].next; }
    return (n.left >= 0 && opt_has_defer(p, n.left)) || (n.right >= 0 && opt_has_defer(p, n.right)) || (n.third >= 0 && opt_has_defer(p, n.third));
}
fn opt_tail_function(p: Program&, o: Optimizer&, node: i64) {
    let n_flags = p.nodes[node].flags; let n_right = p.nodes[node].right;
    if p.optimization < 1 || (n_flags & (F_CAPTURE | F_NONLOCAL)) != 0 || n_right < 0 { return; }
    var formal = p.nodes[node].first;
    while formal >= 0 {
        let ty = p.nodes[formal].type_id;
        if ty < 0 || !check_numeric(ty) && ty != TYPE_BOOL { return; }
        formal = p.nodes[formal].next;
    }
    if opt_has_defer(p, n_right) { return; }
    let n_tok = p.nodes[node].token; let n_scope = p.nodes[node].scope; let n_sym = p.nodes[node].symbol;
    let loop_node = new_node(p, N_LOOP, n_tok); p.nodes[loop_node].type_id = TYPE_VOID;
    p.nodes[loop_node].flags = F_CHECKED; p.nodes[loop_node].right = n_right; p.nodes[loop_node].scope = n_scope;
    let changed = opt_tail_rewrite(p, o, n_right, n_sym, loop_node);
    if changed == 0 { return; }
    let body = new_node(p, N_BLOCK, n_tok); p.nodes[body].type_id = TYPE_VOID;
    p.nodes[body].flags = F_CHECKED; p.nodes[body].scope = n_scope; append_child(p, body, loop_node);
    p.nodes[node].right = body; o.tail_loops += changed;
}
recursive fn opt_callees(p: Program&, o: Optimizer&, node: i64) {
    if node < 0 { return; }
    let kind = p.nodes[node].kind;
    if kind == N_NAME || kind == N_INTEGER || kind == N_FLOAT || kind == N_BOOL || kind == N_NULL || kind == N_STRING ||
       kind == N_EMPTY || kind == N_CONTINUE || kind == N_FUNCTION || kind == N_FUNCTION_VALUE { return; }
    let first = p.nodes[node].first; let left = p.nodes[node].left;
    let right = p.nodes[node].right; let third = p.nodes[node].third;
    if kind == N_CALL {
        let sym = p.nodes[node].symbol;
        if sym >= 0 {
            let sflags = p.symbols[sym].flags; let snode = p.symbols[sym].node;
            if (sflags & S_BUILTIN) == 0 && snode >= 0 { opt_function(p, o, snode); }
        }
    }
    var child = first;
    while child >= 0 { opt_callees(p, o, child); child = p.nodes[child].next; }
    if left >= 0 && kind != N_RECORD && kind != N_VARIABLE { opt_callees(p, o, left); }
    if right >= 0 { opt_callees(p, o, right); }
    if third >= 0 { opt_callees(p, o, third); }
}
// Intra-procedural bounds proof: marks N_INDEX nodes with F_BOUNDS_PROVEN
// using forward evaluation-order fact propagation over blocks, conditions,
// early-exit guards, loops, length aliases, constant bounds, bitmasks,
// unsigned modulo, and repeated verified accesses.

fn opt_unwrap_deref(p: Program&, node: i64) -> i64 {
    var cur = node;
    while cur >= 0 && p.nodes[cur].kind == N_UNARY && p.nodes[cur].integer == T_MUL {
        cur = p.nodes[cur].left;
    }
    return cur;
}

fn opt_array_path_into(p: Program&, o: Optimizer&, bs: OptBoundState&, node: i64) -> bool {
    let cur = opt_unwrap_deref(p, node);
    if cur < 0 { bs.path_sym = -1; return false; }
    let kind = p.nodes[cur].kind;
    let sym = p.nodes[cur].symbol;
    if kind == N_NAME && sym >= 0 {
        let sflags = p.symbols[sym].flags;
        let sty = p.symbols[sym].type_id;
        bs.path_sym = sym;
        bs.path_field = -1;
        bs.path_imm = (sflags & (S_MUTABLE | S_GLOBAL)) == 0 &&
            sty >= 0 && p.types[sty].kind == TY_SLICE &&
            sym < o.facts.len && (o.facts[sym].flags & (OPT_FACT_DIRECT_WRITTEN | OPT_FACT_ADDRESSED)) == 0;
        return true;
    }
    if kind == N_MEMBER && sym >= 0 && p.nodes[cur].left >= 0 {
        let base = opt_unwrap_deref(p, p.nodes[cur].left);
        if base >= 0 && p.nodes[base].kind == N_NAME && p.nodes[base].symbol >= 0 {
            let base_sym = p.nodes[base].symbol;
            if base_sym < o.facts.len && (o.facts[base_sym].flags & (OPT_FACT_DIRECT_WRITTEN | OPT_FACT_ADDRESSED)) == 0 &&
               (p.symbols[base_sym].flags & S_GLOBAL) == 0 && p.symbols[base_sym].type_id >= 0 {
                bs.path_sym = base_sym;
                bs.path_field = sym;
                bs.path_imm = false;
                return true;
            }
        }
    }
    bs.path_sym = -1;
    return false;
}

fn opt_len_target_into(p: Program&, o: Optimizer&, bs: OptBoundState&, node: i64) -> bool {
    if node < 0 { bs.path_sym = -1; return false; }
    let kind = p.nodes[node].kind;
    let sym = p.nodes[node].symbol;
    if kind == N_CALL && sym >= 0 && (p.symbols[sym].flags & S_BUILTIN) != 0 &&
       p.symbols[sym].index == 21 && p.nodes[node].first >= 0 && p.nodes[p.nodes[node].first].next < 0 {
        return opt_array_path_into(p, o, bs, p.nodes[node].first);
    }
    if kind == N_MEMBER && sym < 0 && token_is(p, p.nodes[node].token, "len") {
        return opt_array_path_into(p, o, bs, p.nodes[node].left);
    }
    bs.path_sym = -1;
    return false;
}

fn opt_index_safe(p: Program&, o: Optimizer&, sym: i64) -> bool {
    if sym < 0 || sym >= p.symbols.len { return false; }
    if (p.symbols[sym].flags & (S_GLOBAL | S_CAPTURE)) != 0 { return false; }
    return sym < o.facts.len && (o.facts[sym].flags & OPT_FACT_ADDRESSED) == 0;
}

fn opt_unwrap_wide_cast(p: Program&, node: i64) -> i64 {
    var cur = node;
    while cur >= 0 && p.nodes[cur].kind == N_CAST && p.nodes[cur].left >= 0 {
        let dst = p.nodes[cur].type_id;
        let src = p.nodes[p.nodes[cur].left].type_id;
        if dst < 0 || src < 0 || p.types[dst].kind != TY_INT || p.types[src].kind != TY_INT { break; }
        let su = (p.types[src].flags & TF_UNSIGNED) != 0;
        let du = (p.types[dst].flags & TF_UNSIGNED) != 0;
        let sb = p.types[src].count;
        let db = p.types[dst].count;
        if (su == du && db >= sb) || (su && !du && db > sb) { cur = p.nodes[cur].left; }
        else { break; }
    }
    return cur;
}

fn opt_index_key_into(p: Program&, o: Optimizer&, bs: OptBoundState&, node: i64) -> bool {
    let cur = opt_unwrap_wide_cast(p, node);
    if cur < 0 { bs.key_sym = -1; return false; }
    let kind = p.nodes[cur].kind;
    let sym = p.nodes[cur].symbol;
    if kind == N_NAME && sym >= 0 && opt_index_safe(p, o, sym) {
        bs.key_sym = sym; bs.key_field = -1; bs.key_ref = false;
        return true;
    }
    if kind == N_MEMBER && sym >= 0 && p.nodes[cur].left >= 0 {
        let base = opt_unwrap_deref(p, p.nodes[cur].left);
        if base >= 0 && p.nodes[base].kind == N_NAME && p.nodes[base].symbol >= 0 {
            let bsym = p.nodes[base].symbol;
            if opt_index_safe(p, o, bsym) && (o.facts[bsym].flags & OPT_FACT_DIRECT_WRITTEN) == 0 {
                let bty = p.symbols[bsym].type_id;
                bs.key_sym = bsym; bs.key_field = sym;
                bs.key_ref = bty >= 0 && p.types[bty].kind == TY_REF;
                return true;
            }
        }
    }
    bs.key_sym = -1;
    return false;
}

fn opt_may_contain_array(p: Program&, ty: i64) -> bool {
    if ty < 0 || ty >= p.types.len { return true; }
    let k = p.types[ty].kind;
    return k == TY_ARRAY || k == TY_SLICE || k == TY_STRUCT || k == TY_REF || k == TY_ENUM;
}

fn opt_type_unsigned(p: Program&, ty: i64) -> bool {
    return ty >= 0 && ty < p.types.len && p.types[ty].kind == TY_INT && (p.types[ty].flags & TF_UNSIGNED) != 0;
}

fn opt_key_unsigned_raw(p: Program&, ksym: i64, kfield: i64) -> bool {
    if ksym < 0 { return false; }
    if kfield < 0 { return opt_type_unsigned(p, p.symbols[ksym].type_id); }
    if kfield < p.nodes.len { return opt_type_unsigned(p, p.nodes[kfield].type_id); }
    return false;
}

fn opt_has_nonneg(bs: OptBoundState&, sym: i64) -> bool {
    var i = bs.nlen - 1;
    while i >= 0 {
        if bs.nonneg[i] == sym { return true; }
        i--;
    }
    return false;
}

fn opt_add_nonneg(bs: OptBoundState&, sym: i64) {
    if sym < 0 || bs.nlen >= 32 || opt_has_nonneg(bs, sym) { return; }
    if bs.nlen < bs.nonneg.len { bs.nonneg[bs.nlen] = sym; } else { bs.nonneg.push(sym); }
    bs.nlen++;
}

fn opt_add_guard_raw(bs: OptBoundState&, ksym: i64, kfield: i64, kref: bool, asym: i64, afield: i64, aimm: bool) {
    if ksym < 0 || asym < 0 || bs.glen >= 32 { return; }
    for i in 0..bs.glen {
        let e: const OptBoundGuard& = bs.guards[i];
        if e.index_sym == ksym && e.index_field == kfield && e.arr_sym == asym && e.arr_field == afield { return; }
    }
    if bs.glen < bs.guards.len {
        bs.guards[bs.glen].index_sym = ksym; bs.guards[bs.glen].index_field = kfield; bs.guards[bs.glen].index_is_ref = kref;
        bs.guards[bs.glen].arr_sym = asym; bs.guards[bs.glen].arr_field = afield; bs.guards[bs.glen].arr_imm_slice = aimm;
        bs.guards[bs.glen].pos = false;
    } else {
        bs.guards.push(OptBoundGuard { index_sym: ksym, index_field: kfield, index_is_ref: kref, arr_sym: asym, arr_field: afield, arr_imm_slice: aimm, pos: false });
    }
    bs.glen++;
}

fn opt_mark_guard_pos(bs: OptBoundState&, sym: i64) {
    if sym < 0 || bs.glen == 0 { return; }
    for i in 0..bs.glen {
        if bs.guards[i].index_sym == sym && bs.guards[i].index_field < 0 { bs.guards[i].pos = true; }
    }
}

fn opt_add_alias_raw(bs: OptBoundState&, sym: i64, asym: i64, afield: i64, aimm: bool, delta: i64) {
    if sym < 0 || asym < 0 || bs.alen >= 16 { return; }
    for i in 0..bs.alen {
        if bs.aliases[i].sym == sym {
            bs.aliases[i].arr_sym = asym; bs.aliases[i].arr_field = afield; bs.aliases[i].arr_imm_slice = aimm; bs.aliases[i].delta = delta;
            return;
        }
    }
    if bs.alen < bs.aliases.len {
        bs.aliases[bs.alen].sym = sym; bs.aliases[bs.alen].arr_sym = asym; bs.aliases[bs.alen].arr_field = afield;
        bs.aliases[bs.alen].arr_imm_slice = aimm; bs.aliases[bs.alen].delta = delta;
    } else {
        bs.aliases.push(OptLenAlias { sym: sym, arr_sym: asym, arr_field: afield, arr_imm_slice: aimm, delta: delta });
    }
    bs.alen++;
}

fn opt_add_len_min_raw(bs: OptBoundState&, asym: i64, afield: i64, aimm: bool, min_len: i64) {
    if asym < 0 || min_len <= 0 { return; }
    for i in 0..bs.mlen {
        if bs.mins[i].arr_sym == asym && bs.mins[i].arr_field == afield {
            if min_len > bs.mins[i].min_len { bs.mins[i].min_len = min_len; }
            return;
        }
    }
    if bs.mlen >= 16 { return; }
    if bs.mlen < bs.mins.len {
        bs.mins[bs.mlen].arr_sym = asym; bs.mins[bs.mlen].arr_field = afield;
        bs.mins[bs.mlen].arr_imm_slice = aimm; bs.mins[bs.mlen].min_len = min_len;
    } else {
        bs.mins.push(OptLenMin { arr_sym: asym, arr_field: afield, arr_imm_slice: aimm, min_len: min_len });
    }
    bs.mlen++;
}

// Length relations are stored from the shorter array to the longer one.
fn opt_add_len_eq_raw(bs: OptBoundState&, a_sym: i64, a_field: i64, a_imm: bool, b_sym: i64, b_field: i64, b_imm: bool,
                      ordered: bool = false, stable: bool = false) {
    if a_sym < 0 || b_sym < 0 || a_sym == b_sym && a_field == b_field { return; }
    for i in 0..bs.elen {
        let e: const OptLenEq& = bs.eqs[i];
        if e.ordered != ordered || e.stable != stable { continue; }
        if e.a_sym == a_sym && e.a_field == a_field && e.b_sym == b_sym && e.b_field == b_field ||
           !ordered && e.a_sym == b_sym && e.a_field == b_field && e.b_sym == a_sym && e.b_field == a_field { return; }
    }
    if bs.elen >= 8 { return; }
    let relation = OptLenEq { a_sym: a_sym, a_field: a_field, a_imm: a_imm, b_sym: b_sym, b_field: b_field,
                              b_imm: b_imm, ordered: ordered, stable: stable };
    if bs.elen < bs.eqs.len { bs.eqs[bs.elen] = relation; }
    else { bs.eqs.push(relation); }
    bs.elen++;
}

recursive fn opt_length_le(bs: OptBoundState&, a_sym: i64, a_field: i64, b_sym: i64, b_field: i64, seen: i64 = 0) -> bool {
    if a_sym == b_sym && a_field == b_field { return true; }
    for i in 0..bs.elen {
        let bit = 1 << i;
        if (seen & bit) != 0 { continue; }
        let e: const OptLenEq& = bs.eqs[i];
        if e.a_sym == a_sym && e.a_field == a_field && opt_length_le(bs, e.b_sym, e.b_field, b_sym, b_field, seen | bit) { return true; }
        if !e.ordered && e.b_sym == a_sym && e.b_field == a_field && opt_length_le(bs, e.a_sym, e.a_field, b_sym, b_field, seen | bit) { return true; }
    }
    return false;
}

fn opt_snap_push(bs: OptBoundState&) -> i64 {
    if bs.glen == 0 && bs.nlen == 0 && bs.alen == 0 && bs.mlen == 0 && bs.elen == 0 { return -1; }
    let idx = bs.snap_depth;
    bs.snap_depth++;
    if idx >= bs.snaps.len {
        bs.snaps.push(OptBoundSnap {
            sg0: bs.sglen, sn0: bs.snlen, sa0: bs.salen, sm0: bs.smlen, se0: bs.selen,
            glen: bs.glen, nlen: bs.nlen, alen: bs.alen, mlen: bs.mlen, elen: bs.elen,
        });
    } else {
        bs.snaps[idx].sg0 = bs.sglen; bs.snaps[idx].sn0 = bs.snlen; bs.snaps[idx].sa0 = bs.salen;
        bs.snaps[idx].sm0 = bs.smlen; bs.snaps[idx].se0 = bs.selen;
        bs.snaps[idx].glen = bs.glen; bs.snaps[idx].nlen = bs.nlen; bs.snaps[idx].alen = bs.alen;
        bs.snaps[idx].mlen = bs.mlen; bs.snaps[idx].elen = bs.elen;
    }
    for i in 0..bs.glen {
        let g = bs.guards[i];
        if bs.sglen < bs.snap_guards.len { bs.snap_guards[bs.sglen] = g; } else { bs.snap_guards.push(g); }
        bs.sglen++;
    }
    for i in 0..bs.nlen {
        let v = bs.nonneg[i];
        if bs.snlen < bs.snap_nonneg.len { bs.snap_nonneg[bs.snlen] = v; } else { bs.snap_nonneg.push(v); }
        bs.snlen++;
    }
    for i in 0..bs.alen {
        let a = bs.aliases[i];
        if bs.salen < bs.snap_aliases.len { bs.snap_aliases[bs.salen] = a; } else { bs.snap_aliases.push(a); }
        bs.salen++;
    }
    for i in 0..bs.mlen {
        let m = bs.mins[i];
        if bs.smlen < bs.snap_mins.len { bs.snap_mins[bs.smlen] = m; } else { bs.snap_mins.push(m); }
        bs.smlen++;
    }
    for i in 0..bs.elen {
        let e = bs.eqs[i];
        if bs.selen < bs.snap_eqs.len { bs.snap_eqs[bs.selen] = e; } else { bs.snap_eqs.push(e); }
        bs.selen++;
    }
    return idx;
}

fn opt_snap_restore(bs: OptBoundState&, snap_id: i64) {
    if snap_id < 0 {
        bs.glen = 0; bs.nlen = 0; bs.alen = 0; bs.mlen = 0; bs.elen = 0;
        return;
    }
    let sg0 = bs.snaps[snap_id].sg0; let sn0 = bs.snaps[snap_id].sn0;
    let sa0 = bs.snaps[snap_id].sa0; let sm0 = bs.snaps[snap_id].sm0; let se0 = bs.snaps[snap_id].se0;
    let gl = bs.snaps[snap_id].glen; let nl = bs.snaps[snap_id].nlen;
    let al = bs.snaps[snap_id].alen; let ml = bs.snaps[snap_id].mlen; let el = bs.snaps[snap_id].elen;
    bs.glen = gl;
    for i in 0..gl { bs.guards[i] = bs.snap_guards[sg0 + i]; }
    bs.nlen = nl;
    for i in 0..nl { bs.nonneg[i] = bs.snap_nonneg[sn0 + i]; }
    bs.alen = al;
    for i in 0..al { bs.aliases[i] = bs.snap_aliases[sa0 + i]; }
    bs.mlen = ml;
    for i in 0..ml { bs.mins[i] = bs.snap_mins[sm0 + i]; }
    bs.elen = el;
    for i in 0..el { bs.eqs[i] = bs.snap_eqs[se0 + i]; }
}

fn opt_snap_pop(bs: OptBoundState&, snap_id: i64) {
    if snap_id < 0 {
        bs.glen = 0; bs.nlen = 0; bs.alen = 0; bs.mlen = 0; bs.elen = 0;
        return;
    }
    bs.snap_depth--;
    opt_snap_restore(bs, snap_id);
    bs.sglen = bs.snaps[snap_id].sg0; bs.snlen = bs.snaps[snap_id].sn0;
    bs.salen = bs.snaps[snap_id].sa0; bs.smlen = bs.snaps[snap_id].sm0; bs.selen = bs.snaps[snap_id].se0;
    if bs.snap_depth == 0 { bs.mut_slen = 0; bs.mut_flen = 0; }
}

fn opt_snap_discard(bs: OptBoundState&, snap_id: i64) {
    if snap_id < 0 { return; }
    bs.snap_depth--;
    bs.sglen = bs.snaps[snap_id].sg0; bs.snlen = bs.snaps[snap_id].sn0;
    bs.salen = bs.snaps[snap_id].sa0; bs.smlen = bs.snaps[snap_id].sm0; bs.selen = bs.snaps[snap_id].se0;
    if bs.snap_depth == 0 { bs.mut_slen = 0; bs.mut_flen = 0; }
}

fn opt_has_len_min_raw(bs: OptBoundState&, asym: i64, afield: i64, needed: i64) -> bool {
    if asym < 0 || needed <= 0 { return false; }
    for i in 0..bs.mlen {
        let m: const OptLenMin& = bs.mins[i];
        if m.arr_sym == asym && m.arr_field == afield && m.min_len >= needed { return true; }
    }
    return false;
}

fn opt_sym_has_guard(bs: OptBoundState&, sym: i64) -> bool {
    if sym < 0 { return false; }
    for i in 0..bs.glen {
        let g: const OptBoundGuard& = bs.guards[i];
        if g.index_sym == sym && g.index_field < 0 { return true; }
    }
    return false;
}

fn opt_upper_bound_const(p: Program&, node: i64) -> i64 {
    if node < 0 { return -1; }
    let cur = opt_unwrap_wide_cast(p, node);
    let n: const Node& = p.nodes[cur];
    if n.kind == N_INTEGER && n.integer >= 0 { return n.integer; }
    if n.type_id == TYPE_U8 { return 255; }
    if n.type_id == TYPE_U16 { return 65535; }
    if n.kind == N_BINARY && n.integer == T_BITAND && n.left >= 0 && n.right >= 0 {
        let ty = n.type_id;
        let ok_ty = ty == TYPE_I64 || ty == TYPE_U64 || ty == TYPE_U32 || ty == TYPE_U16 || ty == TYPE_U8 || ty == TYPE_I32;
        if ok_ty {
            var mask: i64 = -1;
            if p.nodes[n.right].kind == N_INTEGER && p.nodes[n.right].integer >= 0 { mask = p.nodes[n.right].integer; }
            else if p.nodes[n.left].kind == N_INTEGER && p.nodes[n.left].integer >= 0 { mask = p.nodes[n.left].integer; }
            if mask >= 0 && (ty != TYPE_I32 || mask <= 2147483647) { return mask; }
        }
    }
    return -1;
}

fn opt_is_nonneg(p: Program&, o: Optimizer&, bs: OptBoundState&, node: i64) -> bool {
    if node < 0 { return false; }
    let cur = opt_unwrap_wide_cast(p, node);
    let kind = p.nodes[cur].kind;
    if kind == N_INTEGER && p.nodes[cur].integer >= 0 { return true; }
    if opt_type_unsigned(p, p.nodes[cur].type_id) { return true; }
    if kind == N_NAME && p.nodes[cur].symbol >= 0 && opt_has_nonneg(bs, p.nodes[cur].symbol) { return true; }
    if (kind == N_CALL || kind == N_MEMBER) && opt_len_target_into(p, o, bs, cur) { return true; }
    if kind == N_BINARY && p.nodes[cur].integer == T_BITAND && opt_upper_bound_const(p, cur) >= 0 { return true; }
    return false;
}

recursive fn opt_len_expr_into(p: Program&, o: Optimizer&, bs: OptBoundState&, node: i64) -> bool {
    if node < 0 { bs.path_sym = -1; return false; }
    let kind = p.nodes[node].kind;
    if kind == N_CALL || kind == N_MEMBER {
        if opt_len_target_into(p, o, bs, node) { bs.path_delta = 0; return true; }
        return false;
    }
    if kind == N_CAST && p.nodes[node].left >= 0 {
        let dst = p.nodes[node].type_id;
        let src = p.nodes[p.nodes[node].left].type_id;
        if (dst == TYPE_I64 || dst == TYPE_U64) && (src == TYPE_I64 || src == TYPE_U64) {
            return opt_len_expr_into(p, o, bs, p.nodes[node].left);
        }
        bs.path_sym = -1; return false;
    }
    if kind == N_NAME && p.nodes[node].symbol >= 0 && bs.alen > 0 {
        let sym = p.nodes[node].symbol;
        for i in 0..bs.alen {
            let a: const OptLenAlias& = bs.aliases[i];
            if a.sym == sym {
                bs.path_sym = a.arr_sym; bs.path_field = a.arr_field; bs.path_imm = a.arr_imm_slice; bs.path_delta = a.delta;
                return true;
            }
        }
        bs.path_sym = -1; return false;
    }
    if kind == N_BINARY && p.nodes[node].integer == T_MINUS && p.nodes[node].left >= 0 && p.nodes[node].right >= 0 &&
       p.nodes[p.nodes[node].right].kind == N_INTEGER && p.nodes[p.nodes[node].right].integer >= 0 && p.nodes[p.nodes[node].right].integer <= 1048576 {
        let sub_k = p.nodes[p.nodes[node].right].integer;
        if opt_len_expr_into(p, o, bs, p.nodes[node].left) && bs.path_delta >= -1048576 {
            bs.path_delta -= sub_k;
            return true;
        }
    }
    bs.path_sym = -1; return false;
}

fn opt_match_inbounds_into(p: Program&, o: Optimizer&, bs: OptBoundState&, node: i64) -> bool {
    if node < 0 { bs.path_sym = -1; return false; }
    var cur = node;
    if p.nodes[cur].kind == N_CAST && p.nodes[cur].left >= 0 &&
       (p.nodes[cur].type_id == TYPE_I64 || p.nodes[cur].type_id == TYPE_U64) &&
       (p.nodes[p.nodes[cur].left].type_id == TYPE_I64 || p.nodes[p.nodes[cur].left].type_id == TYPE_U64) {
        cur = p.nodes[cur].left;
    }
    let kind = p.nodes[cur].kind;
    let op = p.nodes[cur].integer;
    let ty = p.nodes[cur].type_id;
    let left = p.nodes[cur].left;
    let right = p.nodes[cur].right;
    if kind != N_BINARY || left < 0 || right < 0 { bs.path_sym = -1; return false; }
    if op == T_BITAND && (ty == TYPE_I64 || ty == TYPE_U64) && bs.mlen > 0 {
        if opt_len_expr_into(p, o, bs, right) && bs.path_delta == -1 && opt_has_len_min_raw(bs, bs.path_sym, bs.path_field, 1) { return true; }
        if opt_len_expr_into(p, o, bs, left) && bs.path_delta == -1 && opt_has_len_min_raw(bs, bs.path_sym, bs.path_field, 1) { return true; }
    } else if op == T_MOD && opt_type_unsigned(p, ty) {
        if opt_len_expr_into(p, o, bs, right) && bs.path_delta == 0 { return true; }
    }
    bs.path_sym = -1; return false;
}

fn opt_kill_sym_only(bs: OptBoundState&, sym: i64) {
    if sym < 0 { return; }
    var gi = 0;
    while gi < bs.glen {
        if bs.guards[gi].index_sym == sym || bs.guards[gi].arr_sym == sym {
            bs.glen--; bs.guards[gi] = bs.guards[bs.glen];
        } else { gi++; }
    }
    var ni = 0;
    while ni < bs.nlen {
        if bs.nonneg[ni] == sym {
            bs.nlen--; bs.nonneg[ni] = bs.nonneg[bs.nlen];
        } else { ni++; }
    }
    var ai = 0;
    while ai < bs.alen {
        if bs.aliases[ai].sym == sym || bs.aliases[ai].arr_sym == sym {
            bs.alen--; bs.aliases[ai] = bs.aliases[bs.alen];
        } else { ai++; }
    }
    var mi = 0;
    while mi < bs.mlen {
        if bs.mins[mi].arr_sym == sym {
            bs.mlen--; bs.mins[mi] = bs.mins[bs.mlen];
        } else { mi++; }
    }
    var ei = 0;
    while ei < bs.elen {
        if bs.eqs[ei].a_sym == sym || bs.eqs[ei].b_sym == sym {
            bs.elen--; bs.eqs[ei] = bs.eqs[bs.elen];
        } else { ei++; }
    }
}

fn opt_kill_sym(bs: OptBoundState&, sym: i64) {
    if sym < 0 { return; }
    bs.mut_any_gen++;
    if bs.snap_depth > 0 {
        if bs.mut_slen < bs.mut_syms.len { bs.mut_syms[bs.mut_slen] = sym; } else { bs.mut_syms.push(sym); }
        bs.mut_slen++;
    }
    opt_kill_sym_only(bs, sym);
}

fn opt_kill_eq_mutable_only(bs: OptBoundState&) {
    var ei = 0;
    while ei < bs.elen {
        if !bs.eqs[ei].stable && (!bs.eqs[ei].a_imm || !bs.eqs[ei].b_imm) {
            bs.elen--; bs.eqs[ei] = bs.eqs[bs.elen];
        } else { ei++; }
    }
}

fn opt_kill_mutable_arrays_only(bs: OptBoundState&) {
    var gi = 0;
    while gi < bs.glen {
        if !bs.guards[gi].arr_imm_slice || bs.guards[gi].index_is_ref {
            bs.glen--; bs.guards[gi] = bs.guards[bs.glen];
        } else { gi++; }
    }
    var ai = 0;
    while ai < bs.alen {
        if !bs.aliases[ai].arr_imm_slice {
            bs.alen--; bs.aliases[ai] = bs.aliases[bs.alen];
        } else { ai++; }
    }
    var mi = 0;
    while mi < bs.mlen {
        if !bs.mins[mi].arr_imm_slice {
            bs.mlen--; bs.mins[mi] = bs.mins[bs.mlen];
        } else { mi++; }
    }
    opt_kill_eq_mutable_only(bs);
}

fn opt_kill_mutable_arrays(bs: OptBoundState&) {
    bs.mut_any_gen++; bs.mut_arrays_gen++; bs.mut_refs_gen++; bs.mut_grow_gen++;
    opt_kill_mutable_arrays_only(bs);
}

fn opt_kill_field_only(bs: OptBoundState&, field_sym: i64) {
    if field_sym < 0 { return; }
    var gi = 0;
    while gi < bs.glen {
        if bs.guards[gi].index_field == field_sym || !bs.guards[gi].arr_imm_slice && bs.guards[gi].arr_field == field_sym {
            bs.glen--; bs.guards[gi] = bs.guards[bs.glen];
        } else { gi++; }
    }
    var ai = 0;
    while ai < bs.alen {
        if !bs.aliases[ai].arr_imm_slice && bs.aliases[ai].arr_field == field_sym {
            bs.alen--; bs.aliases[ai] = bs.aliases[bs.alen];
        } else { ai++; }
    }
    var mi = 0;
    while mi < bs.mlen {
        if !bs.mins[mi].arr_imm_slice && bs.mins[mi].arr_field == field_sym {
            bs.mlen--; bs.mins[mi] = bs.mins[bs.mlen];
        } else { mi++; }
    }
    var ei = 0;
    while ei < bs.elen {
        if !bs.eqs[ei].a_imm && bs.eqs[ei].a_field == field_sym || !bs.eqs[ei].b_imm && bs.eqs[ei].b_field == field_sym {
            bs.elen--; bs.eqs[ei] = bs.eqs[bs.elen];
        } else { ei++; }
    }
}

fn opt_kill_field(bs: OptBoundState&, field_sym: i64) {
    if field_sym < 0 { return; }
    bs.mut_any_gen++;
    if bs.snap_depth > 0 {
        if bs.mut_flen < bs.mut_fields.len { bs.mut_fields[bs.mut_flen] = field_sym; } else { bs.mut_fields.push(field_sym); }
        bs.mut_flen++;
    }
    opt_kill_field_only(bs, field_sym);
}

fn opt_kill_ref_indices_only(bs: OptBoundState&) {
    var gi = 0;
    while gi < bs.glen {
        if bs.guards[gi].index_is_ref {
            bs.glen--; bs.guards[gi] = bs.guards[bs.glen];
        } else { gi++; }
    }
}

fn opt_kill_ref_indices(bs: OptBoundState&) {
    bs.mut_any_gen++; bs.mut_refs_gen++;
    opt_kill_ref_indices_only(bs);
}

// Conservative fallback when a loop body exceeds the bounded scan budget:
// preserves only function-wide immutable locals and immutable-slice guards.
fn opt_sym_immutable(o: Optimizer&, sym: i64) -> bool {
    return sym >= 0 && sym < o.facts.len && (o.facts[sym].flags & (OPT_FACT_DIRECT_WRITTEN | OPT_FACT_ADDRESSED)) == 0;
}

fn opt_kill_mutable_all(o: Optimizer&, bs: OptBoundState&) {
    opt_kill_mutable_arrays(bs);
    var gi = 0;
    while gi < bs.glen {
        let g: const OptBoundGuard& = bs.guards[gi];
        if g.index_field >= 0 || !opt_sym_immutable(o, g.index_sym) {
            bs.glen--; bs.guards[gi] = bs.guards[bs.glen];
        } else { gi++; }
    }
    var ni = 0;
    while ni < bs.nlen {
        if !opt_sym_immutable(o, bs.nonneg[ni]) {
            bs.nlen--; bs.nonneg[ni] = bs.nonneg[bs.nlen];
        } else { ni++; }
    }
    var ai = 0;
    while ai < bs.alen {
        if !opt_sym_immutable(o, bs.aliases[ai].sym) {
            bs.alen--; bs.aliases[ai] = bs.aliases[bs.alen];
        } else { ai++; }
    }
}

fn opt_replay_mutations(bs: OptBoundState&, ms0: i64, ms1: i64, mf0: i64, mf1: i64, arrays_dirty: bool, refs_dirty: bool, grow_dirty: bool) {
    if bs.glen == 0 && bs.nlen == 0 && bs.alen == 0 && bs.mlen == 0 && bs.elen == 0 { return; }
    if arrays_dirty { opt_kill_mutable_arrays_only(bs); }
    else {
        if refs_dirty { opt_kill_ref_indices_only(bs); }
        if grow_dirty { opt_kill_eq_mutable_only(bs); }
    }
    for i in ms0..ms1 { opt_kill_sym_only(bs, bs.mut_syms[i]); }
    for i in mf0..mf1 { opt_kill_field_only(bs, bs.mut_fields[i]); }
}

fn opt_is_index_var(o: Optimizer&, sym: i64) -> bool {
    return sym >= 0 && sym < o.facts.len && (o.facts[sym].flags & OPT_FACT_INDEX_VAR) != 0;
}

fn opt_invalidate_assign_target(p: Program&, bs: OptBoundState&, target: i64) {
    if target < 0 { return; }
    let tn: const Node& = p.nodes[target];
    let tkind = tn.kind;
    let tsym = tn.symbol;
    let tint = tn.integer;
    let tty = tn.type_id;
    if tkind == N_NAME {
        opt_kill_sym(bs, tsym);
        if tsym >= 0 && p.symbols[tsym].type_id >= 0 && p.types[p.symbols[tsym].type_id].kind == TY_REF {
            opt_kill_mutable_arrays(bs);
        }
        return;
    }
    if tkind == N_UNARY && (tint == T_MUL || tint == T_XOR) {
        opt_kill_mutable_arrays(bs);
        return;
    }
    if tkind == N_MEMBER {
        opt_kill_field(bs, tsym);
        if bs.glen > 0 || bs.alen > 0 || bs.mlen > 0 {
            let root = check_place_root(p, target);
            if root >= 0 {
                var gi = 0;
                while gi < bs.glen {
                    if !bs.guards[gi].arr_imm_slice && bs.guards[gi].arr_field < 0 && bs.guards[gi].arr_sym == root {
                        bs.glen--; bs.guards[gi] = bs.guards[bs.glen];
                    } else { gi++; }
                }
                var ai = 0;
                while ai < bs.alen {
                    if !bs.aliases[ai].arr_imm_slice && bs.aliases[ai].arr_field < 0 && bs.aliases[ai].arr_sym == root {
                        bs.alen--; bs.aliases[ai] = bs.aliases[bs.alen];
                    } else { ai++; }
                }
                var mi = 0;
                while mi < bs.mlen {
                    if !bs.mins[mi].arr_imm_slice && bs.mins[mi].arr_field < 0 && bs.mins[mi].arr_sym == root {
                        bs.mlen--; bs.mins[mi] = bs.mins[bs.mlen];
                    } else { mi++; }
                }
            }
        }
        if opt_may_contain_array(p, tty) { opt_kill_mutable_arrays(bs); }
        return;
    }
    if tkind == N_INDEX {
        if opt_may_contain_array(p, tty) { opt_kill_mutable_arrays(bs); }
        else { opt_kill_ref_indices(bs); }
        return;
    }
    opt_kill_mutable_arrays(bs);
}

fn opt_invalidate_call(p: Program&, bs: OptBoundState&, node: i64) {
    let sym = p.nodes[node].symbol;
    if sym >= 0 && (p.symbols[sym].flags & S_BUILTIN) != 0 {
        let b = p.symbols[sym].index;
        if b == 3 || b == 4 || b == 5 || b == 6 || b == 21 || b == 22 || b == 38 || b == 39 { return; }
        if b == 24 || b == 25 {
            bs.mut_any_gen++; bs.mut_grow_gen++;
            opt_kill_eq_mutable_only(bs);
            return;
        }
        opt_kill_mutable_arrays(bs);
        return;
    }
    opt_kill_mutable_arrays(bs);
    if bs.snap_depth == 0 && bs.glen == 0 && bs.nlen == 0 && bs.alen == 0 && bs.mlen == 0 && bs.elen == 0 { return; }
    var arg = p.nodes[node].first;
    while arg >= 0 {
        let an: const Node& = p.nodes[arg];
        if (an.flags & F_REFERENCE_CONTEXT) != 0 {
            var root: i64 = -1;
            if an.kind == N_NAME { root = an.symbol; } else { root = check_place_root(p, arg); }
            if root >= 0 && p.symbols[root].type_id >= 0 && p.types[p.symbols[root].type_id].kind != TY_REF {
                opt_kill_sym(bs, root);
            }
        }
        arg = an.next;
    }
}

recursive fn opt_invalidate_subtree(p: Program&, o: Optimizer&, bs: OptBoundState&, node: i64) {
    if node < 0 || bs.glen == 0 && bs.nlen == 0 && bs.alen == 0 && bs.mlen == 0 && bs.elen == 0 { return; }
    if bs.scan_budget <= 0 { opt_kill_mutable_all(o, bs); return; }
    bs.scan_budget--;
    let kind = p.nodes[node].kind;
    if kind == N_NAME || kind == N_INTEGER || kind == N_FLOAT || kind == N_BOOL || kind == N_NULL || kind == N_STRING ||
       kind == N_EMPTY || kind == N_CONTINUE || kind == N_FUNCTION || kind == N_FUNCTION_VALUE { return; }
    let first = p.nodes[node].first; let left = p.nodes[node].left;
    let right = p.nodes[node].right; let third = p.nodes[node].third;
    let tint = p.nodes[node].integer;
    if kind == N_ASSIGN {
        opt_invalidate_assign_target(p, bs, left);
    } else if kind == N_MULTI_ASSIGN {
        var target = first;
        while target >= 0 { opt_invalidate_assign_target(p, bs, target); target = p.nodes[target].next; }
    } else if kind == N_UNARY && tint == T_BITAND {
        let root = check_place_root(p, left);
        if root >= 0 { opt_kill_sym(bs, root); }
    } else if kind == N_CALL {
        opt_invalidate_call(p, bs, node);
    }
    var child = first;
    while child >= 0 && bs.scan_budget > 0 {
        let ck = p.nodes[child].kind;
        if ck < N_INTEGER || ck > N_NAME { opt_invalidate_subtree(p, o, bs, child); }
        child = p.nodes[child].next;
    }
    if kind == N_VARIABLE && right >= 0 {
        var extra = p.nodes[right].next;
        while extra >= 0 && bs.scan_budget > 0 { opt_invalidate_subtree(p, o, bs, extra); extra = p.nodes[extra].next; }
    } else if kind == N_BREAK && left >= 0 {
        var extra = p.nodes[left].next;
        while extra >= 0 && bs.scan_budget > 0 { opt_invalidate_subtree(p, o, bs, extra); extra = p.nodes[extra].next; }
    }
    if left >= 0 && kind != N_RECORD && kind != N_VARIABLE && bs.scan_budget > 0 {
        let lk = p.nodes[left].kind;
        if lk < N_INTEGER || lk > N_NAME { opt_invalidate_subtree(p, o, bs, left); }
    }
    if right >= 0 && bs.scan_budget > 0 {
        let rk = p.nodes[right].kind;
        if rk < N_INTEGER || rk > N_NAME { opt_invalidate_subtree(p, o, bs, right); }
    }
    if third >= 0 && bs.scan_budget > 0 {
        let tk = p.nodes[third].kind;
        if tk < N_INTEGER || tk > N_NAME { opt_invalidate_subtree(p, o, bs, third); }
    }
    if bs.scan_budget <= 0 && (bs.glen > 0 || bs.nlen > 0 || bs.alen > 0 || bs.mlen > 0 || bs.elen > 0) {
        opt_kill_mutable_all(o, bs);
    }
}

recursive fn opt_subtree_modifies_sym(p: Program&, bs: OptBoundState&, node: i64, sym: i64) -> bool {
    if node < 0 { return false; }
    if bs.scan_budget <= 0 { return true; }
    bs.scan_budget--;
    let kind = p.nodes[node].kind;
    if kind == N_INTEGER || kind == N_FLOAT || kind == N_BOOL || kind == N_NULL || kind == N_STRING ||
       kind == N_EMPTY || kind == N_CONTINUE || kind == N_FUNCTION || kind == N_FUNCTION_VALUE { return false; }
    if kind == N_NAME {
        return p.nodes[node].symbol == sym && (p.nodes[node].flags & F_REFERENCE_CONTEXT) != 0;
    }
    let first = p.nodes[node].first; let left = p.nodes[node].left;
    let right = p.nodes[node].right; let third = p.nodes[node].third;
    let tint = p.nodes[node].integer;
    if kind == N_ASSIGN {
        if check_place_root(p, left) == sym { return true; }
    } else if kind == N_MULTI_ASSIGN {
        var target = first;
        while target >= 0 {
            if check_place_root(p, target) == sym { return true; }
            target = p.nodes[target].next;
        }
    } else if kind == N_UNARY && tint == T_BITAND {
        if check_place_root(p, left) == sym { return true; }
    }
    var child = first;
    while child >= 0 {
        let ck = p.nodes[child].kind;
        if (ck < N_INTEGER || ck > N_STRING) && opt_subtree_modifies_sym(p, bs, child, sym) { return true; }
        child = p.nodes[child].next;
    }
    if kind == N_VARIABLE && right >= 0 {
        var extra = p.nodes[right].next;
        while extra >= 0 { if opt_subtree_modifies_sym(p, bs, extra, sym) { return true; } extra = p.nodes[extra].next; }
    }
    if left >= 0 && kind != N_RECORD && kind != N_VARIABLE {
        let lk = p.nodes[left].kind;
        if (lk < N_INTEGER || lk > N_STRING) && opt_subtree_modifies_sym(p, bs, left, sym) { return true; }
    }
    if right >= 0 {
        let rk = p.nodes[right].kind;
        if (rk < N_INTEGER || rk > N_STRING) && opt_subtree_modifies_sym(p, bs, right, sym) { return true; }
    }
    if third >= 0 {
        let tk = p.nodes[third].kind;
        if (tk < N_INTEGER || tk > N_STRING) && opt_subtree_modifies_sym(p, bs, third, sym) { return true; }
    }
    return false;
}

recursive fn opt_subtree_may_shrink_arr(p: Program&, bs: OptBoundState&, node: i64, arr_sym: i64, arr_field: i64, arr_imm: bool) -> bool {
    if node < 0 || arr_imm { return false; }
    if bs.scan_budget <= 0 { return true; }
    bs.scan_budget--;
    let kind = p.nodes[node].kind;
    if kind == N_NAME || kind == N_INTEGER || kind == N_FLOAT || kind == N_BOOL || kind == N_NULL || kind == N_STRING ||
       kind == N_EMPTY || kind == N_CONTINUE || kind == N_FUNCTION || kind == N_FUNCTION_VALUE { return false; }
    let first = p.nodes[node].first; let left = p.nodes[node].left;
    let right = p.nodes[node].right; let third = p.nodes[node].third;
    let tint = p.nodes[node].integer;
    if kind == N_ASSIGN || kind == N_MULTI_ASSIGN {
        var target = left; if kind == N_MULTI_ASSIGN { target = first; }
        while target >= 0 {
            let tk = p.nodes[target].kind; let ts = p.nodes[target].symbol; let tty = p.nodes[target].type_id;
            if tk == N_UNARY && (p.nodes[target].integer == T_MUL || p.nodes[target].integer == T_XOR) { return true; }
            if tk == N_NAME && (ts == arr_sym || ts >= 0 && p.symbols[ts].type_id >= 0 && p.types[p.symbols[ts].type_id].kind == TY_REF) { return true; }
            if tk == N_MEMBER {
                if arr_field < 0 && check_place_root(p, target) == arr_sym { return true; }
                if arr_field >= 0 && ts == arr_field { return true; }
                if opt_may_contain_array(p, tty) { return true; }
            }
            if tk == N_INDEX && opt_may_contain_array(p, tty) { return true; }
            if kind != N_MULTI_ASSIGN { break; }
            target = p.nodes[target].next;
        }
    } else if kind == N_UNARY && tint == T_BITAND {
        if check_place_root(p, left) == arr_sym { return true; }
    } else if kind == N_CALL {
        let sym = p.nodes[node].symbol;
        if sym < 0 || (p.symbols[sym].flags & S_BUILTIN) == 0 { return true; }
        let b = p.symbols[sym].index;
        if b != 21 && b != 22 && b != 24 && b != 25 && b != 3 && b != 4 && b != 5 && b != 6 && b != 38 && b != 39 {
            return true;
        }
    }
    var child = first;
    while child >= 0 {
        let ck = p.nodes[child].kind;
        if (ck < N_INTEGER || ck > N_NAME) && opt_subtree_may_shrink_arr(p, bs, child, arr_sym, arr_field, arr_imm) { return true; }
        child = p.nodes[child].next;
    }
    if kind == N_VARIABLE && right >= 0 {
        var extra = p.nodes[right].next;
        while extra >= 0 { if opt_subtree_may_shrink_arr(p, bs, extra, arr_sym, arr_field, arr_imm) { return true; } extra = p.nodes[extra].next; }
    }
    if left >= 0 && kind != N_RECORD && kind != N_VARIABLE {
        let lk = p.nodes[left].kind;
        if (lk < N_INTEGER || lk > N_NAME) && opt_subtree_may_shrink_arr(p, bs, left, arr_sym, arr_field, arr_imm) { return true; }
    }
    if right >= 0 {
        let rk = p.nodes[right].kind;
        if (rk < N_INTEGER || rk > N_NAME) && opt_subtree_may_shrink_arr(p, bs, right, arr_sym, arr_field, arr_imm) { return true; }
    }
    if third >= 0 {
        let tk = p.nodes[third].kind;
        if (tk < N_INTEGER || tk > N_NAME) && opt_subtree_may_shrink_arr(p, bs, third, arr_sym, arr_field, arr_imm) { return true; }
    }
    return false;
}

recursive fn opt_diverges(p: Program&, node: i64) -> bool {
    if node < 0 { return false; }
    let kind = p.nodes[node].kind;
    let flags = p.nodes[node].flags;
    if (flags & F_DIVERGES) != 0 && kind != N_FUNCTION && kind != N_FUNCTION_VALUE { return true; }
    if kind == N_RETURN || kind == N_BREAK || kind == N_CONTINUE { return true; }
    if kind == N_CALL && p.nodes[node].symbol >= 0 {
        let s: const Symbol& = p.symbols[p.nodes[node].symbol];
        return (s.flags & S_BUILTIN) != 0 && (s.index == 4 || s.index == 5);
    }
    if kind == N_BLOCK && (flags & F_EARLY) == 0 && p.nodes[node].last >= 0 {
        return opt_diverges(p, p.nodes[node].last);
    }
    if kind == N_IF && p.nodes[node].third >= 0 {
        return opt_diverges(p, p.nodes[node].right) && opt_diverges(p, p.nodes[node].third);
    }
    return false;
}

// Counts the maximum number of `sym++` / `sym += 1` increments on any path through
// `node`; returns -1 if `sym` is modified in any other way or taken by reference.
recursive fn opt_count_unit_incs(p: Program&, bs: OptBoundState&, node: i64, sym: i64) -> i64 {
    if node < 0 { return 0; }
    if bs.scan_budget <= 0 { return -1; }
    bs.scan_budget--;
    let kind = p.nodes[node].kind;
    if kind == N_INTEGER || kind == N_FLOAT || kind == N_BOOL || kind == N_NULL || kind == N_STRING ||
       kind == N_EMPTY || kind == N_CONTINUE || kind == N_FUNCTION || kind == N_FUNCTION_VALUE { return 0; }
    if kind == N_NAME {
        if p.nodes[node].symbol == sym && (p.nodes[node].flags & F_REFERENCE_CONTEXT) != 0 { return -1; }
        return 0;
    }
    let first = p.nodes[node].first; let left = p.nodes[node].left;
    let right = p.nodes[node].right; let third = p.nodes[node].third;
    let op = p.nodes[node].integer;
    if kind == N_ASSIGN {
        if check_place_root(p, left) == sym {
            if p.nodes[left].kind != N_NAME || p.nodes[left].symbol != sym { return -1; }
            if op == T_INC { return 1; }
            if op == T_PLUSEQ && right >= 0 && p.nodes[right].kind == N_INTEGER && p.nodes[right].integer == 1 { return 1; }
            if op == T_ASSIGN && right >= 0 && p.nodes[right].kind == N_INTEGER && p.nodes[right].integer >= 0 { return 0; }
            return -1;
        }
        return opt_count_unit_incs(p, bs, right, sym);
    }
    if kind == N_MULTI_ASSIGN {
        var target = first;
        while target >= 0 {
            if check_place_root(p, target) == sym { return -1; }
            target = p.nodes[target].next;
        }
    }
    if kind == N_UNARY && op == T_BITAND && check_place_root(p, left) == sym { return -1; }
    if kind == N_IF {
        let c = opt_count_unit_incs(p, bs, left, sym); if c < 0 { return -1; }
        let a = opt_count_unit_incs(p, bs, right, sym); if a < 0 { return -1; }
        let b = opt_count_unit_incs(p, bs, third, sym); if b < 0 { return -1; }
        var branch = a; if b > branch { branch = b; }
        return c + branch;
    }
    if kind == N_WHILE || kind == N_FOR || kind == N_LOOP {
        if opt_subtree_modifies_sym(p, bs, node, sym) { return -1; }
        return 0;
    }
    var total: i64 = 0;
    var child = first;
    while child >= 0 {
        let ck = p.nodes[child].kind;
        if ck < N_INTEGER || ck > N_STRING {
            let c = opt_count_unit_incs(p, bs, child, sym); if c < 0 { return -1; }
            total += c;
        }
        child = p.nodes[child].next;
    }
    if left >= 0 && kind != N_RECORD && kind != N_VARIABLE {
        let lk = p.nodes[left].kind;
        if lk < N_INTEGER || lk > N_STRING {
            let c = opt_count_unit_incs(p, bs, left, sym); if c < 0 { return -1; }
            total += c;
        }
    }
    if right >= 0 {
        let rk = p.nodes[right].kind;
        if rk < N_INTEGER || rk > N_STRING {
            let c = opt_count_unit_incs(p, bs, right, sym); if c < 0 { return -1; }
            total += c;
        }
    }
    if third >= 0 {
        let tk = p.nodes[third].kind;
        if tk < N_INTEGER || tk > N_STRING {
            let c = opt_count_unit_incs(p, bs, third, sym); if c < 0 { return -1; }
            total += c;
        }
    }
    return total;
}

// Counts the maximum number of `sym--` / `sym -= 1` decrements on any path through
// `node`; returns -1 if `sym` is modified in any other way or taken by reference.
recursive fn opt_count_unit_decs(p: Program&, bs: OptBoundState&, node: i64, sym: i64) -> i64 {
    if node < 0 { return 0; }
    if bs.scan_budget <= 0 { return -1; }
    bs.scan_budget--;
    let n: const Node& = p.nodes[node];
    let kind = n.kind;
    if kind >= N_INTEGER && kind <= N_STRING || kind == N_EMPTY || kind == N_CONTINUE || kind == N_FUNCTION || kind == N_FUNCTION_VALUE { return 0; }
    if kind == N_NAME {
        if n.symbol == sym && (n.flags & F_REFERENCE_CONTEXT) != 0 { return -1; }
        return 0;
    }
    let first = n.first; let left = n.left; let right = n.right; let third = n.third; let op = n.integer;
    if kind == N_ASSIGN {
        if check_place_root(p, left) == sym {
            if p.nodes[left].kind != N_NAME || p.nodes[left].symbol != sym { return -1; }
            if op == T_DEC { return 1; }
            if op == T_MINUSEQ && right >= 0 && p.nodes[right].kind == N_INTEGER && p.nodes[right].integer == 1 { return 1; }
            return -1;
        }
        return opt_count_unit_decs(p, bs, right, sym);
    }
    if kind == N_MULTI_ASSIGN {
        var target = first;
        while target >= 0 {
            if check_place_root(p, target) == sym { return -1; }
            target = p.nodes[target].next;
        }
    }
    if kind == N_UNARY && op == T_BITAND && check_place_root(p, left) == sym { return -1; }
    if kind == N_IF {
        let c = opt_count_unit_decs(p, bs, left, sym); if c < 0 { return -1; }
        let a = opt_count_unit_decs(p, bs, right, sym); if a < 0 { return -1; }
        let b = opt_count_unit_decs(p, bs, third, sym); if b < 0 { return -1; }
        var branch = a; if b > branch { branch = b; }
        return c + branch;
    }
    if kind == N_WHILE || kind == N_FOR || kind == N_LOOP {
        if opt_subtree_modifies_sym(p, bs, node, sym) { return -1; }
        return 0;
    }
    var total: i64 = 0;
    var child = first;
    while child >= 0 {
        let ck = p.nodes[child].kind;
        if ck < N_INTEGER || ck > N_STRING {
            let c = opt_count_unit_decs(p, bs, child, sym); if c < 0 { return -1; }
            total += c;
        }
        child = p.nodes[child].next;
    }
    if left >= 0 && kind != N_RECORD && kind != N_VARIABLE {
        let lk = p.nodes[left].kind;
        if lk < N_INTEGER || lk > N_STRING {
            let c = opt_count_unit_decs(p, bs, left, sym); if c < 0 { return -1; }
            total += c;
        }
    }
    if right >= 0 {
        let rk = p.nodes[right].kind;
        if rk < N_INTEGER || rk > N_STRING {
            let c = opt_count_unit_decs(p, bs, right, sym); if c < 0 { return -1; }
            total += c;
        }
    }
    if third >= 0 {
        let tk = p.nodes[third].kind;
        if tk < N_INTEGER || tk > N_STRING {
            let c = opt_count_unit_decs(p, bs, third, sym); if c < 0 { return -1; }
            total += c;
        }
    }
    return total;
}

// Checks whether a `while` condition guarantees `sym >= 1` (`sym > 0`, `sym >= 1`, `0 < sym`, `1 <= sym`).
recursive fn opt_cond_requires_pos(p: Program&, o: Optimizer&, bs: OptBoundState&, cond: i64, sym: i64) -> bool {
    if cond < 0 { return false; }
    let cn: const Node& = p.nodes[cond];
    if cn.kind != N_BINARY || cn.left < 0 || cn.right < 0 { return false; }
    let op = cn.integer;
    if op == T_ANDAND {
        return opt_cond_requires_pos(p, o, bs, cn.left, sym) || opt_cond_requires_pos(p, o, bs, cn.right, sym);
    }
    if p.nodes[cn.right].kind == N_INTEGER {
        let rv = p.nodes[cn.right].integer;
        if (op == T_GT && rv >= 0 || op == T_GTEQ && rv >= 1) && opt_index_key_into(p, o, bs, cn.left) && bs.key_sym == sym && bs.key_field < 0 { return true; }
    }
    if p.nodes[cn.left].kind == N_INTEGER {
        let lv = p.nodes[cn.left].integer;
        if (op == T_LT && lv >= 0 || op == T_LTEQ && lv >= 1) && opt_index_key_into(p, o, bs, cn.right) && bs.key_sym == sym && bs.key_field < 0 { return true; }
    }
    return false;
}

// Checks whether a `while` condition bounds `sym < some_arr.len` (or `<= some_arr.len - 1`).
recursive fn opt_cond_bounds_sym(p: Program&, o: Optimizer&, bs: OptBoundState&, cond: i64, sym: i64) -> bool {
    if cond < 0 { return false; }
    let kind = p.nodes[cond].kind;
    let op = p.nodes[cond].integer;
    let left = p.nodes[cond].left;
    let right = p.nodes[cond].right;
    if kind != N_BINARY { return false; }
    if op == T_ANDAND {
        return opt_cond_bounds_sym(p, o, bs, left, sym) || opt_cond_bounds_sym(p, o, bs, right, sym);
    }
    if op == T_LT || op == T_LTEQ {
        if opt_index_key_into(p, o, bs, left) && bs.key_sym == sym && bs.key_field < 0 {
            if opt_len_expr_into(p, o, bs, right) && (op == T_LT && bs.path_delta <= 0 || op == T_LTEQ && bs.path_delta <= -1) { return true; }
        }
    }
    if op == T_GT || op == T_GTEQ {
        if opt_index_key_into(p, o, bs, right) && bs.key_sym == sym && bs.key_field < 0 {
            if opt_len_expr_into(p, o, bs, left) && (op == T_GT && bs.path_delta <= 0 || op == T_GTEQ && bs.path_delta <= -1) { return true; }
        }
    }
    return false;
}

// Pass 1 of condition harvesting: nonneg and LenMin facts.
// Pass 2 of condition harvesting: upper-bound guards (relying on nonneg from pass 1).
fn opt_array_element(p: Program&, storage: i64) -> i64 {
    let ty = if storage >= 0 && p.types[storage].kind == TY_REF { p.types[storage].element } else { storage };
    if ty >= 0 && p.types[ty].kind == TY_ARRAY { return p.types[ty].element; }
    return -1;
}

fn opt_length_write(p: Program&, target: i64, element: i64) -> bool {
    if target < 0 { return true; }
    let storage = p.nodes[target].type_id;
    let ty = if storage >= 0 && p.types[storage].kind == TY_REF { p.types[storage].element } else { storage };
    if ty < 0 { return true; }
    if p.types[ty].kind == TY_ARRAY { return check_same_type(p, p.types[ty].element, element) || check_size_class(p, p.types[ty].element, 0) > 0; }
    return p.types[ty].kind == TY_STRUCT || p.types[ty].kind == TY_ENUM || p.types[ty].kind == TY_TUPLE;
}

recursive fn opt_length_stable(p: Program&, node: i64, element: i64, budget: i64&) -> bool {
    if node < 0 { return true; }
    if budget <= 0 { return false; }
    budget--;
    let n: const Node& = p.nodes[node];
    if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE || n.kind >= N_INTEGER && n.kind <= N_NAME { return true; }
    if n.kind == N_ASSIGN && opt_length_write(p, n.left, element) { return false; }
    if n.kind == N_MULTI_ASSIGN {
        var target = n.first;
        while target >= 0 {
            if opt_length_write(p, target, element) { return false; }
            target = p.nodes[target].next;
        }
    }
    if n.kind == N_CALL {
        if n.symbol < 0 || (p.symbols[n.symbol].flags & S_BUILTIN) == 0 { return false; }
        let b = p.symbols[n.symbol].index;
        if b == 24 || b == 25 || b == 26 || b == 27 || b == 28 || b == 29 || b == 30 || b == 31 || b == 33 || b == 34 || b == 35 {
            if opt_length_write(p, n.first, element) { return false; }
        } else if b != 3 && b != 4 && b != 5 && b != 6 && b != 21 && b != 22 { return false; }
    }
    var child = n.first;
    while child >= 0 {
        if !opt_length_stable(p, child, element, budget) { return false; }
        child = p.nodes[child].next;
    }
    if n.kind != N_VARIABLE && n.kind != N_RECORD && n.kind != N_PARAM && n.kind != N_FIELD &&
       !opt_length_stable(p, n.left, element, budget) { return false; }
    return opt_length_stable(p, n.right, element, budget) &&
        (n.kind == N_CALL || opt_length_stable(p, n.third, element, budget));
}

fn opt_path_stable(p: Program&, bs: OptBoundState&, symbol: i64, field: i64, immutable: bool) -> bool {
    if immutable { return true; }
    let ty = if field < 0 { p.symbols[symbol].type_id } else { p.nodes[field].type_id };
    let element = opt_array_element(p, ty);
    if element < 0 || bs.body < 0 { return false; }
    var budget = 512;
    return opt_length_stable(p, bs.body, element, budget);
}

fn opt_note_len_order(p: Program&, o: Optimizer&, bs: OptBoundState&, shorter: i64, longer: i64) {
    if !opt_len_expr_into(p, o, bs, shorter) || bs.path_delta != 0 { return; }
    let a = bs.path_sym; let af = bs.path_field; let ai = bs.path_imm;
    if !opt_len_expr_into(p, o, bs, longer) || bs.path_delta != 0 { return; }
    let b = bs.path_sym; let bf = bs.path_field; let bi = bs.path_imm;
    let stable = opt_path_stable(p, bs, a, af, ai) && opt_path_stable(p, bs, b, bf, bi);
    opt_add_len_eq_raw(bs, a, af, ai, b, bf, bi, true, stable);
}

recursive fn opt_harvest_cond_pass(p: Program&, o: Optimizer&, bs: OptBoundState&, cond: i64, truthy: bool, pass: i64, cond_mutated: bool) {
    if cond < 0 { return; }
    let kind = p.nodes[cond].kind;
    let op = p.nodes[cond].integer;
    let left = p.nodes[cond].left;
    let right = p.nodes[cond].right;
    if kind == N_UNARY && op == T_NOT {
        opt_harvest_cond_pass(p, o, bs, left, !truthy, pass, cond_mutated);
        return;
    }
    if kind != N_BINARY || left < 0 || right < 0 { return; }
    if truthy && op == T_ANDAND || !truthy && op == T_OROR {
        opt_harvest_cond_pass(p, o, bs, left, truthy, pass, cond_mutated);
        if cond_mutated { bs.scan_budget = 64; opt_invalidate_subtree(p, o, bs, right); }
        opt_harvest_cond_pass(p, o, bs, right, truthy, pass, cond_mutated);
        return;
    }
    var cmp = op;
    if !truthy {
        if op == T_LT { cmp = T_GTEQ; }
        else if op == T_LTEQ { cmp = T_GT; }
        else if op == T_GT { cmp = T_LTEQ; }
        else if op == T_GTEQ { cmp = T_LT; }
        else if op == T_EQ { cmp = T_NEQ; }
        else if op == T_NEQ { cmp = T_EQ; }
        else { return; }
    }
    if bs.checkfree >= 0 && pass == 1 {
        if cmp == T_LT || cmp == T_LTEQ { opt_note_len_order(p, o, bs, left, right); }
        if cmp == T_GT || cmp == T_GTEQ { opt_note_len_order(p, o, bs, right, left); }
    }
    if pass == 0 {
        let lk = p.nodes[left].kind;
        let rk = p.nodes[right].kind;
        if rk == N_INTEGER {
            let rv = p.nodes[right].integer;
            if (cmp == T_GTEQ && rv >= 0 || cmp == T_GT && rv >= -1) &&
               (lk == N_NAME || lk == N_CAST) &&
               opt_index_key_into(p, o, bs, left) && bs.key_field < 0 && opt_is_index_var(o, bs.key_sym) {
                opt_add_nonneg(bs, bs.key_sym);
                if cmp == T_GT && rv >= 0 || cmp == T_GTEQ && rv >= 1 { opt_mark_guard_pos(bs, bs.key_sym); }
            }
            if (cmp == T_GT && rv >= 0 && rv < 1048576 || (cmp == T_GTEQ || cmp == T_EQ) && rv >= 1 && rv <= 1048576 || cmp == T_NEQ && rv == 0) &&
               (lk == N_CALL || lk == N_MEMBER || lk == N_NAME && bs.alen > 0 || lk == N_CAST || lk == N_BINARY && p.nodes[left].integer == T_MINUS) &&
               opt_len_expr_into(p, o, bs, left) && bs.path_delta == 0 {
                var mn = rv;
                if cmp == T_GT { mn = rv + 1; } else if cmp == T_NEQ { mn = 1; }
                opt_add_len_min_raw(bs, bs.path_sym, bs.path_field, bs.path_imm, mn);
            }
            return;
        }
        if lk == N_INTEGER {
            let lv = p.nodes[left].integer;
            if (cmp == T_LTEQ && lv >= 0 || cmp == T_LT && lv >= -1) &&
               (rk == N_NAME || rk == N_CAST) &&
               opt_index_key_into(p, o, bs, right) && bs.key_field < 0 && opt_is_index_var(o, bs.key_sym) {
                opt_add_nonneg(bs, bs.key_sym);
                if cmp == T_LT && lv >= 0 || cmp == T_LTEQ && lv >= 1 { opt_mark_guard_pos(bs, bs.key_sym); }
            }
            if (cmp == T_LT && lv >= 0 && lv < 1048576 || (cmp == T_LTEQ || cmp == T_EQ) && lv >= 1 && lv <= 1048576 || cmp == T_NEQ && lv == 0) &&
               (rk == N_CALL || rk == N_MEMBER || rk == N_NAME && bs.alen > 0 || rk == N_CAST || rk == N_BINARY && p.nodes[right].integer == T_MINUS) &&
               opt_len_expr_into(p, o, bs, right) && bs.path_delta == 0 {
                var mn = lv;
                if cmp == T_LT { mn = lv + 1; } else if cmp == T_NEQ { mn = 1; }
                opt_add_len_min_raw(bs, bs.path_sym, bs.path_field, bs.path_imm, mn);
            }
            return;
        }
        if cmp == T_EQ &&
           (lk == N_CALL || lk == N_MEMBER || lk == N_NAME && bs.alen > 0 || lk == N_CAST) &&
           (rk == N_CALL || rk == N_MEMBER || rk == N_NAME && bs.alen > 0 || rk == N_CAST) &&
           opt_len_expr_into(p, o, bs, left) && bs.path_delta == 0 {
            let a_sym = bs.path_sym; let a_field = bs.path_field; let a_imm = bs.path_imm;
            if opt_len_expr_into(p, o, bs, right) && bs.path_delta == 0 {
                opt_add_len_eq_raw(bs, a_sym, a_field, a_imm, bs.path_sym, bs.path_field, bs.path_imm);
            }
        }
        return;
    }
    if cmp != T_LT && cmp != T_LTEQ && cmp != T_GT && cmp != T_GTEQ { return; }
    var ok = false;
    if cmp == T_LT || cmp == T_LTEQ {
        let rk = p.nodes[right].kind;
        if (rk == N_CALL || rk == N_MEMBER || rk == N_NAME && bs.alen > 0 || rk == N_CAST || rk == N_BINARY && p.nodes[right].integer == T_MINUS) &&
           opt_index_key_into(p, o, bs, left) && opt_len_expr_into(p, o, bs, right) &&
           (cmp == T_LT && bs.path_delta <= 0 || cmp == T_LTEQ && bs.path_delta <= -1) { ok = true; }
    } else {
        let lk = p.nodes[left].kind;
        if (lk == N_CALL || lk == N_MEMBER || lk == N_NAME && bs.alen > 0 || lk == N_CAST || lk == N_BINARY && p.nodes[left].integer == T_MINUS) &&
           opt_index_key_into(p, o, bs, right) && opt_len_expr_into(p, o, bs, left) &&
           (cmp == T_GT && bs.path_delta <= 0 || cmp == T_GTEQ && bs.path_delta <= -1) { ok = true; }
    }
    if ok {
        let nonneg = opt_key_unsigned_raw(p, bs.key_sym, bs.key_field) || (bs.key_field < 0 && opt_has_nonneg(bs, bs.key_sym));
        if nonneg {
            opt_add_guard_raw(bs, bs.key_sym, bs.key_field, bs.key_ref, bs.path_sym, bs.path_field, bs.path_imm);
            opt_add_len_min_raw(bs, bs.path_sym, bs.path_field, bs.path_imm, 1);
        }
    }
}

fn opt_harvest_cond(p: Program&, o: Optimizer&, bs: OptBoundState&, cond: i64, truthy: bool, cond_mutated: bool) {
    if cond < 0 { return; }
    let cn: const Node& = p.nodes[cond];
    let ck = cn.kind;
    if ck != N_BINARY && ck != N_UNARY { return; }
    let cop = cn.integer;
    if ck == N_BINARY {
        if cop == T_ANDAND {
            if !truthy { return; }
            opt_harvest_cond_pass(p, o, bs, cond, true, 0, cond_mutated);
            opt_harvest_cond_pass(p, o, bs, cond, true, 1, cond_mutated);
            return;
        }
        if cop == T_OROR {
            if truthy { return; }
            opt_harvest_cond_pass(p, o, bs, cond, false, 0, cond_mutated);
            opt_harvest_cond_pass(p, o, bs, cond, false, 1, cond_mutated);
            return;
        }
        if cn.left < 0 || cn.right < 0 { return; }
        let lk = p.nodes[cn.left].kind;
        let rk = p.nodes[cn.right].kind;
        if lk == N_INTEGER || rk == N_INTEGER {
            opt_harvest_cond_pass(p, o, bs, cond, truthy, 0, cond_mutated);
            return;
        }
        if cop == T_EQ || cop == T_NEQ {
            if truthy && cop == T_EQ || !truthy && cop == T_NEQ {
                opt_harvest_cond_pass(p, o, bs, cond, truthy, 0, cond_mutated);
            }
            return;
        }
        opt_harvest_cond_pass(p, o, bs, cond, truthy, 1, cond_mutated);
        return;
    }
    if cop != T_NOT { return; }
    opt_harvest_cond_pass(p, o, bs, cond, truthy, 0, cond_mutated);
    opt_harvest_cond_pass(p, o, bs, cond, truthy, 1, cond_mutated);
}

fn opt_has_checkfree(p: Program&) -> bool {
    for n in p.nodes {
        if (n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE) &&
           (n.flags & (F_CHECKED | F_CHECKFREE)) == (F_CHECKED | F_CHECKFREE) { return true; }
    }
    return false;
}

recursive fn opt_bound_expr(p: Program&, node: i64, out: u8[>..]&) {
    let n: const Node& = p.nodes[node];
    if n.kind == N_MEMBER || n.kind == N_INDEX {
        opt_bound_expr(p, n.left, out);
        if n.kind == N_INDEX {
            out.push('['); opt_bound_expr(p, n.right, out); out.push(']');
        } else {
            out.push('.'); out.append(token_text(p, n.token));
        }
    } else { out.append(token_text(p, n.token)); }
}

fn opt_checkfree_message(p: Program&, function: i64, out: u8[>..]&) {
    out.append("checkfree fn ");
    let symbol = p.nodes[function].symbol;
    if symbol >= 0 { out.append(token_text(p, p.symbols[symbol].name_token)); }
    out.append(" keeps a bounds check: ");
}

fn opt_checkfree_diagnose(p: Program&, node: i64, msg: const u8[:]) {
    let token = p.nodes[node].token;
    let t = p.tokens[token];
    for d in p.diagnostics {
        if d.source == t.source && d.line == t.line &&
           same_bytes(p.messages[d.message_start..d.message_start + d.message_len], msg) { return; }
    }
    diagnose(p, token, msg);
}

fn opt_checkfree_index(p: Program&, function: i64, node: i64, left: i64, right: i64) {
    var msg: u8[>..] = [];
    opt_checkfree_message(p, function, msg);
    let n: const Node& = p.nodes[right];
    let ty = check_index_value(p, right, -1);
    let index_type = ty >= 0;
    if !index_type && (n.kind == N_INDEX || n.kind == N_MEMBER || n.kind == N_CALL) {
        opt_bound_expr(p, right, msg);
        msg.append(" is read out of an element, a field or a call result, whose value the analysis does not know; an index type (`u32 in a`) for what is stored there carries it (§3.11)");
    } else {
        msg.append("nothing shows "); opt_bound_expr(p, right, msg);
        msg.append(" < "); opt_bound_expr(p, left, msg); msg.append(".len");
        if index_type && p.types[ty].pool >= 0 {
            msg.append("; "); opt_bound_expr(p, right, msg); msg.append(" is a ");
            diag_append_type(p, ty, msg);
            msg.append(", so `assert("); opt_bound_expr(p, left, msg);
            msg.append(".len >= "); msg.append(token_text(p, p.symbols[p.types[ty].pool].name_token));
            msg.append(".len)` where neither changes after it would settle it");
        }
    }
    opt_checkfree_diagnose(p, node, msg);
}

fn opt_index_pool_path(p: Program&, bs: OptBoundState&, expr: i64, inclusive: bool) -> bool {
    let ty = check_index_value(p, expr, -1);
    if ty < 0 || p.types[ty].pool < 0 || inclusive && (p.types[ty].flags & F_BOUND_TYPE) != 0 { return false; }
    opt_pool_path(p, bs, p.types[ty].pool);
    return true;
}

fn opt_pool_path(p: Program&, bs: OptBoundState&, symbol: i64) {
    let owner = p.symbols[symbol].component_owner;
    bs.path_sym = if owner < 0 { symbol } else { owner };
    bs.path_field = if owner < 0 { -1 } else { p.symbols[symbol].component };
    bs.path_imm = false;
}

fn opt_check_index_cast(p: Program&, o: Optimizer&, bs: OptBoundState&, node: i64) {
    let n: const Node& = p.nodes[node];
    let ty = if n.right >= 0 { p.nodes[n.right].type_id } else { n.type_id };
    if ty < 0 || p.types[ty].kind != TY_INT || p.types[ty].index_type < 0 || p.types[ty].pool < 0 { return; }
    let pool = p.types[ty].pool;
    opt_pool_path(p, bs, pool);
    let symbol = bs.path_sym; let field = bs.path_field;
    let bound = (p.types[ty].flags & F_BOUND_TYPE) != 0;
    let upper = opt_upper_bound_const(p, n.left);
    var proven = bound && upper == 0;
    if upper >= 0 && upper < 9223372036854775807 && opt_has_len_min_raw(bs, symbol, field, upper + (if bound { 0 } else { 1 })) {
        proven = true;
    }
    if opt_index_pool_path(p, bs, n.left, !bound) &&
       opt_length_le(bs, bs.path_sym, bs.path_field, symbol, field) { proven = true; }
    if !proven && opt_index_key_into(p, o, bs, n.left) {
        for i in 0..bs.glen {
            let g = bs.guards[i];
            if g.index_sym == bs.key_sym && g.index_field == bs.key_field &&
               opt_length_le(bs, g.arr_sym, g.arr_field, symbol, field) { proven = true; break; }
        }
    }
    if proven { p.nodes[node].flags |= F_BOUNDS_PROVEN; return; }
    var msg: u8[>..] = [];
    opt_checkfree_message(p, bs.checkfree, msg);
    msg.append("nothing shows "); opt_bound_expr(p, n.left, msg);
    if bound { msg.append(" <= "); } else { msg.append(" < "); }
    msg.append(token_text(p, p.symbols[pool].name_token)); msg.append(".len");
    opt_checkfree_diagnose(p, node, msg);
}

fn opt_check_slice(p: Program&, o: Optimizer&, bs: OptBoundState&, node: i64) {
    let n: const Node& = p.nodes[node];
    let lo = if n.right < 0 { 0 } else if p.nodes[n.right].kind == N_INTEGER { p.nodes[n.right].integer } else { -1 };
    let hi = if n.third < 0 { -1 } else { opt_upper_bound_const(p, n.third) };
    var len_min = 0;
    var ty = p.nodes[n.left].type_id;
    if ty >= 0 && p.types[ty].kind == TY_REF { ty = p.types[ty].element; }
    if ty >= 0 && p.types[ty].kind == TY_ARRAY && p.types[ty].array_kind == A_FIXED { len_min = p.types[ty].count; }
    let has_path = opt_array_path_into(p, o, bs, n.left);
    let symbol = bs.path_sym; let field = bs.path_field;
    var proven = false;
    if (n.flags & (F_FROM_END | F_TO_END)) == 0 && lo >= 0 {
        if n.third < 0 {
            proven = lo <= len_min || has_path && opt_has_len_min_raw(bs, symbol, field, lo);
        } else if opt_is_nonneg(p, o, bs, n.third) {
            let ordered = lo == 0 || p.nodes[n.third].kind == N_INTEGER && lo <= hi;
            if ordered {
                proven = hi >= 0 && (hi <= len_min || has_path && opt_has_len_min_raw(bs, symbol, field, hi)) ||
                         has_path && opt_index_pool_path(p, bs, n.third, false) &&
                         opt_length_le(bs, bs.path_sym, bs.path_field, symbol, field);
            }
        }
    }
    if proven { p.nodes[node].flags |= F_BOUNDS_PROVEN; return; }
    var msg: u8[>..] = [];
    opt_checkfree_message(p, bs.checkfree, msg);
    msg.append("slice of "); opt_bound_expr(p, n.left, msg);
    msg.append(": the analysis cannot relate the slice's bounds to the length");
    opt_checkfree_diagnose(p, node, msg);
}

fn opt_check_index(p: Program&, o: Optimizer&, bs: OptBoundState&, node: i64) {
    let flags = p.nodes[node].flags;
    let left = p.nodes[node].left;
    let right = p.nodes[node].right;
    if right < 0 { return; }
    let rk = p.nodes[right].kind;
    let rty = p.nodes[right].type_id;
    let has_path = opt_array_path_into(p, o, bs, left);
    let psym = bs.path_sym; let pfield = bs.path_field; let pimm = bs.path_imm;
    var has_key = false;
    var ksym: i64 = -1; var kfield: i64 = -1; var kref = false;
    if has_path && (rk == N_NAME || rk == N_MEMBER || rk == N_CAST) {
        has_key = opt_index_key_into(p, o, bs, right);
        ksym = bs.key_sym; kfield = bs.key_field; kref = bs.key_ref;
    }
    if (flags & F_BOUNDS_PROVEN) == 0 {
        var proven = false;
        // 1. Active guard `(key, path)` (commonest case — check first!).
        if has_key && bs.glen > 0 {
            for gi in 0..bs.glen {
                let g: const OptBoundGuard& = bs.guards[gi];
                if g.index_sym == ksym && g.index_field == kfield &&
                   (g.arr_sym == psym && g.arr_field == pfield ||
                    bs.elen > 0 && opt_length_le(bs, g.arr_sym, g.arr_field, psym, pfield)) {
                    proven = true; break;
                }
            }
        }
        // 1b. `arr[idx - 1]` when `idx` has a positive active guard (`1 <= idx < arr.len`).
        if !proven && has_path && bs.glen > 0 && rk == N_BINARY && p.nodes[right].integer == T_MINUS {
            let sub_r = p.nodes[right].right;
            if sub_r >= 0 && p.nodes[sub_r].kind == N_INTEGER && p.nodes[sub_r].integer == 1 &&
               opt_index_key_into(p, o, bs, p.nodes[right].left) && bs.key_field < 0 {
                let dsym = bs.key_sym;
                for gi in 0..bs.glen {
                    let g: const OptBoundGuard& = bs.guards[gi];
                    if g.index_sym == dsym && g.index_field < 0 && g.pos &&
                       (g.arr_sym == psym && g.arr_field == pfield ||
                        bs.elen > 0 && opt_length_le(bs, g.arr_sym, g.arr_field, psym, pfield)) {
                        proven = true; break;
                    }
                }
            }
        }
        // 2. Constant / u8 / u16 / constant-bitmask upper bound against fixed array or LenMin.
        if !proven && (rk == N_INTEGER || rk == N_BINARY && p.nodes[right].integer == T_BITAND || rk == N_CAST || rty == TYPE_U8 || rty == TYPE_U16) {
            let ub = opt_upper_bound_const(p, right);
            if ub >= 0 {
                var sty = p.nodes[left].type_id;
                if sty >= 0 && p.types[sty].kind == TY_REF { sty = p.types[sty].element; }
                if sty >= 0 && p.types[sty].kind == TY_ARRAY && p.types[sty].array_kind == A_FIXED && ub < p.types[sty].count {
                    proven = true;
                } else if has_path && bs.mlen > 0 && opt_has_len_min_raw(bs, psym, pfield, ub + 1) {
                    proven = true;
                }
            }
        }
        // 3. `arr[arr.len - k]` when `arr.len >= k`.
        if !proven && has_path && bs.mlen > 0 && rk == N_BINARY && p.nodes[right].integer == T_MINUS {
            if opt_len_expr_into(p, o, bs, right) && bs.path_sym == psym && bs.path_field == pfield &&
               bs.path_delta < 0 && opt_has_len_min_raw(bs, psym, pfield, -bs.path_delta) {
                proven = true;
            }
        }
        // 4. Bitmask `arr[x & (arr.len - 1)]` (with arr.len >= 1) or unsigned `arr[u % arr.len]`.
        if !proven && has_path && (rk == N_BINARY && (p.nodes[right].integer == T_BITAND || p.nodes[right].integer == T_MOD) || rk == N_CAST) {
            if opt_match_inbounds_into(p, o, bs, right) && bs.path_sym == psym && bs.path_field == pfield {
                proven = true;
            }
        }
        if !proven && has_path && bs.elen > 0 && opt_index_pool_path(p, bs, right, true) {
            proven = opt_length_le(bs, bs.path_sym, bs.path_field, psym, pfield);
        }
        if proven { p.nodes[node].flags |= F_BOUNDS_PROVEN; }
    }
    if bs.checkfree >= 0 && (p.nodes[node].flags & F_BOUNDS_PROVEN) == 0 {
        opt_checkfree_index(p, bs.checkfree, node, left, right);
    }
    if has_key {
        opt_add_guard_raw(bs, ksym, kfield, kref, psym, pfield, pimm);
        if kfield < 0 { opt_add_nonneg(bs, ksym); }
    }
}

recursive fn opt_prove_if(p: Program&, o: Optimizer&, bs: OptBoundState&, node: i64) {
    let n: const Node& = p.nodes[node];
    let left = n.left; let right = n.right; let third = n.third;
    if third >= 0 && p.nodes[third].kind == N_IF {
        var cur = node;
        var outer_snap: i64 = -2;
        var chain_ms0: i64 = 0; var chain_mf0: i64 = 0;
        var chain_ma0: i64 = 0; var chain_mr0: i64 = 0; var chain_mg0: i64 = 0;
        while cur >= 0 && p.nodes[cur].kind == N_IF && p.nodes[cur].left >= 0 {
            let cn: const Node& = p.nodes[cur];
            let cl = cn.left; let cr = cn.right; let ct = cn.third;
            let cany0 = bs.mut_any_gen;
            let clk = p.nodes[cl].kind;
            if clk < N_INTEGER || clk > N_NAME { opt_prove_bounds(p, o, bs, cl); }
            let cond_mut = bs.mut_any_gen != cany0;
            if outer_snap == -2 {
                let s = opt_snap_push(bs);
                let tms0 = bs.mut_slen; let tmf0 = bs.mut_flen;
                let tma0 = bs.mut_arrays_gen; let tmr0 = bs.mut_refs_gen; let tmg0 = bs.mut_grow_gen;
                opt_harvest_cond(p, o, bs, cl, true, cond_mut);
                if cr >= 0 { opt_prove_bounds(p, o, bs, cr); }
                if opt_diverges(p, cr) {
                    opt_snap_pop(bs, s);
                    opt_harvest_cond(p, o, bs, cl, false, cond_mut);
                    cur = ct;
                    continue;
                }
                outer_snap = s;
                chain_ms0 = tms0; chain_mf0 = tmf0;
                chain_ma0 = tma0; chain_mr0 = tmr0; chain_mg0 = tmg0;
                opt_snap_restore(bs, outer_snap);
                opt_harvest_cond(p, o, bs, cl, false, cond_mut);
                cur = ct;
                continue;
            }
            let arm_snap = opt_snap_push(bs);
            opt_harvest_cond(p, o, bs, cl, true, cond_mut);
            if cr >= 0 { opt_prove_bounds(p, o, bs, cr); }
            opt_snap_pop(bs, arm_snap);
            opt_harvest_cond(p, o, bs, cl, false, cond_mut);
            cur = ct;
        }
        if cur >= 0 { opt_prove_bounds(p, o, bs, cur); }
        if outer_snap != -2 {
            let cms1 = bs.mut_slen; let cmf1 = bs.mut_flen;
            let cma_dirty = bs.mut_arrays_gen != chain_ma0;
            let cmr_dirty = bs.mut_refs_gen != chain_mr0;
            let cmg_dirty = bs.mut_grow_gen != chain_mg0;
            opt_snap_pop(bs, outer_snap);
            if outer_snap >= 0 { opt_replay_mutations(bs, chain_ms0, cms1, chain_mf0, cmf1, cma_dirty, cmr_dirty, cmg_dirty); }
        }
        return;
    }
    let cany0 = bs.mut_any_gen;
    let lk = p.nodes[left].kind;
    if lk < N_INTEGER || lk > N_NAME { opt_prove_bounds(p, o, bs, left); }
    let cond_mut = bs.mut_any_gen != cany0;
    let snap = opt_snap_push(bs);
    let tms0 = bs.mut_slen; let tmf0 = bs.mut_flen; let tma0 = bs.mut_arrays_gen; let tmr0 = bs.mut_refs_gen; let tmg0 = bs.mut_grow_gen; let tany0 = bs.mut_any_gen;
    opt_harvest_cond(p, o, bs, left, true, cond_mut);
    if right >= 0 { opt_prove_bounds(p, o, bs, right); }
    let tms1 = bs.mut_slen; let tmf1 = bs.mut_flen;
    let tma_dirty = bs.mut_arrays_gen != tma0; let tmr_dirty = bs.mut_refs_gen != tmr0; let tmg_dirty = bs.mut_grow_gen != tmg0; let t_mut = bs.mut_any_gen != tany0;
    let then_div = opt_diverges(p, right);
    if third >= 0 {
        let else_div = opt_diverges(p, third);
        opt_snap_restore(bs, snap);
        let ems0 = bs.mut_slen; let emf0 = bs.mut_flen; let ema0 = bs.mut_arrays_gen; let emr0 = bs.mut_refs_gen; let emg0 = bs.mut_grow_gen;
        opt_harvest_cond(p, o, bs, left, false, cond_mut);
        opt_prove_bounds(p, o, bs, third);
        if then_div && !else_div {
            opt_snap_discard(bs, snap);
            return;
        }
        let ems1 = bs.mut_slen; let emf1 = bs.mut_flen;
        let ema_dirty = bs.mut_arrays_gen != ema0; let emr_dirty = bs.mut_refs_gen != emr0; let emg_dirty = bs.mut_grow_gen != emg0;
        opt_snap_pop(bs, snap);
        if else_div && !then_div {
            if snap >= 0 {
                opt_harvest_cond(p, o, bs, left, true, cond_mut);
                opt_replay_mutations(bs, tms0, tms1, tmf0, tmf1, tma_dirty, tmr_dirty, tmg_dirty);
            } else if !t_mut {
                opt_harvest_cond(p, o, bs, left, true, cond_mut);
            }
        } else if !then_div && !else_div && snap >= 0 {
            opt_replay_mutations(bs, tms0, tms1, tmf0, tmf1, tma_dirty, tmr_dirty, tmg_dirty);
            opt_replay_mutations(bs, ems0, ems1, emf0, emf1, ema_dirty, emr_dirty, emg_dirty);
        }
    } else {
        opt_snap_pop(bs, snap);
        if then_div {
            opt_harvest_cond(p, o, bs, left, false, cond_mut);
        } else if snap >= 0 {
            opt_replay_mutations(bs, tms0, tms1, tmf0, tmf1, tma_dirty, tmr_dirty, tmg_dirty);
        }
    }
}

recursive fn opt_prove_for(p: Program&, o: Optimizer&, bs: OptBoundState&, node: i64) {
    let n: const Node& = p.nodes[node];
    let first = n.first; let left = n.left; let right = n.right;
    let lk = p.nodes[left].kind;
    if lk < N_INTEGER || lk > N_NAME { opt_prove_bounds(p, o, bs, left); }
    let snap = opt_snap_push(bs);
    var bind_sym: i64 = -1;
    var bind_nonneg = false;
    var bind_pos = false;
    var bind_asym: i64 = -1; var bind_afield: i64 = -1; var bind_aimm = false;
    if lk == N_RANGE && first >= 0 {
        let rlo = p.nodes[left].left;
        let rhi = p.nodes[left].right;
        let inclusive = (p.nodes[left].flags & F_INCLUSIVE) != 0;
        let idx_sym = p.nodes[first].symbol;
        if idx_sym >= 0 && opt_index_safe(p, o, idx_sym) {
            bind_sym = idx_sym;
            bind_nonneg = opt_is_nonneg(p, o, bs, rlo);
            bind_pos = rlo >= 0 && p.nodes[rlo].kind == N_INTEGER && p.nodes[rlo].integer >= 1;
            if bind_nonneg &&
               (opt_len_expr_into(p, o, bs, rhi) && (!inclusive && bs.path_delta <= 0 || inclusive && bs.path_delta <= -1) ||
                opt_index_pool_path(p, bs, rhi, inclusive)) {
                bind_asym = bs.path_sym; bind_afield = bs.path_field; bind_aimm = bs.path_imm;
            }
        }
    } else if first >= 0 {
        var lt = p.nodes[left].type_id;
        while lt >= 0 && p.types[lt].kind == TY_REF { lt = p.types[lt].element; }
        if lt >= 0 && (p.types[lt].kind == TY_ARRAY || p.types[lt].kind == TY_SLICE) {
            let second = p.nodes[first].next;
            if second >= 0 && p.nodes[second].symbol >= 0 && opt_index_safe(p, o, p.nodes[second].symbol) {
                bind_sym = p.nodes[second].symbol;
                bind_nonneg = true;
                if opt_array_path_into(p, o, bs, left) {
                    bind_asym = bs.path_sym; bind_afield = bs.path_field; bind_aimm = bs.path_imm;
                }
            }
        } else if p.nodes[first].symbol >= 0 && opt_index_safe(p, o, p.nodes[first].symbol) {
            bind_sym = p.nodes[first].symbol;
            bind_nonneg = true;
            if opt_len_expr_into(p, o, bs, left) && bs.path_delta <= 0 {
                bind_asym = bs.path_sym; bind_afield = bs.path_field; bind_aimm = bs.path_imm;
            }
        }
    }
    let bms0 = bs.mut_slen; let bmf0 = bs.mut_flen; let bma0 = bs.mut_arrays_gen; let bmr0 = bs.mut_refs_gen; let bmg0 = bs.mut_grow_gen;
    if snap >= 0 { bs.scan_budget = 128; opt_invalidate_subtree(p, o, bs, right); }
    let bind_imm = bind_sym >= 0 && (p.symbols[bind_sym].flags & S_MUTABLE) == 0 && opt_sym_immutable(o, bind_sym);
    var bind_ok = false;
    if bind_sym >= 0 {
        if bind_imm { bind_ok = true; }
        else { bs.scan_budget = 128; bind_ok = !opt_subtree_modifies_sym(p, bs, right, bind_sym); }
    }
    if bind_ok && opt_is_index_var(o, bind_sym) {
        if bind_nonneg { opt_add_nonneg(bs, bind_sym); }
        if bind_asym >= 0 {
            var arr_ok = bind_aimm;
            if !arr_ok { bs.scan_budget = 128; arr_ok = !opt_subtree_may_shrink_arr(p, bs, right, bind_asym, bind_afield, bind_aimm); }
            if arr_ok {
                opt_add_guard_raw(bs, bind_sym, -1, false, bind_asym, bind_afield, bind_aimm);
                if bind_pos { opt_mark_guard_pos(bs, bind_sym); }
            }
        }
    }
    if right >= 0 { opt_prove_bounds(p, o, bs, right); }
    let bms1 = bs.mut_slen; let bmf1 = bs.mut_flen;
    let bma_dirty = bs.mut_arrays_gen != bma0; let bmr_dirty = bs.mut_refs_gen != bmr0; let bmg_dirty = bs.mut_grow_gen != bmg0;
    opt_snap_pop(bs, snap);
    if snap >= 0 { opt_replay_mutations(bs, bms0, bms1, bmf0, bmf1, bma_dirty, bmr_dirty, bmg_dirty); }
}

recursive fn opt_prove_while(p: Program&, o: Optimizer&, bs: OptBoundState&, node: i64) {
    let n: const Node& = p.nodes[node];
    let left = n.left; let right = n.right;
    let snap = opt_snap_push(bs);
    // Ascending unit-step induction: `var i = 0; while i < arr.len { ... i++; }`
    var ks0: i64 = -1; var ks1: i64 = -1; var ks2: i64 = -1; var ks3: i64 = -1;
    var keep_count: i64 = 0;
    for ni in 0..bs.nlen {
        let nsym = bs.nonneg[ni];
        if keep_count < 4 && nsym >= 0 && p.symbols[nsym].type_id == TYPE_I64 &&
           opt_cond_bounds_sym(p, o, bs, left, nsym) {
            var ok = false;
            if opt_sym_immutable(o, nsym) { ok = true; }
            else {
                bs.scan_budget = 64;
                if !opt_subtree_modifies_sym(p, bs, left, nsym) {
                    bs.scan_budget = 128;
                    let incs = opt_count_unit_incs(p, bs, right, nsym);
                    ok = incs >= 0 && incs <= 1;
                }
            }
            if ok {
                if keep_count == 0 { ks0 = nsym; }
                else if keep_count == 1 { ks1 = nsym; }
                else if keep_count == 2 { ks2 = nsym; }
                else { ks3 = nsym; }
                keep_count++;
            }
        }
    }
    // Descending unit-step induction: `var j = i; while j > 0 && ... { ... j--; }`
    var dg0_sym: i64 = -1; var dg0_asym: i64 = -1; var dg0_afield: i64 = -1; var dg0_aimm = false;
    var dg1_sym: i64 = -1; var dg1_asym: i64 = -1; var dg1_afield: i64 = -1; var dg1_aimm = false;
    var dg_count: i64 = 0;
    for gi in 0..bs.glen {
        if dg_count >= 2 { break; }
        let g: const OptBoundGuard& = bs.guards[gi];
        if g.index_field < 0 && g.index_sym >= 0 && p.symbols[g.index_sym].type_id == TYPE_I64 &&
           opt_cond_requires_pos(p, o, bs, left, g.index_sym) {
            bs.scan_budget = 64;
            if !opt_subtree_modifies_sym(p, bs, left, g.index_sym) {
                bs.scan_budget = 128;
                let decs = opt_count_unit_decs(p, bs, right, g.index_sym);
                if decs >= 0 && decs <= 1 {
                    var arr_ok = g.arr_imm_slice;
                    if !arr_ok {
                        bs.scan_budget = 64;
                        arr_ok = !opt_subtree_may_shrink_arr(p, bs, left, g.arr_sym, g.arr_field, g.arr_imm_slice);
                        if arr_ok {
                            bs.scan_budget = 128;
                            arr_ok = !opt_subtree_may_shrink_arr(p, bs, right, g.arr_sym, g.arr_field, g.arr_imm_slice);
                        }
                    }
                    if arr_ok {
                        if dg_count == 0 { dg0_sym = g.index_sym; dg0_asym = g.arr_sym; dg0_afield = g.arr_field; dg0_aimm = g.arr_imm_slice; }
                        else { dg1_sym = g.index_sym; dg1_asym = g.arr_sym; dg1_afield = g.arr_field; dg1_aimm = g.arr_imm_slice; }
                        dg_count++;
                    }
                }
            }
        }
    }
    let lms0 = bs.mut_slen; let lmf0 = bs.mut_flen; let lma0 = bs.mut_arrays_gen; let lmr0 = bs.mut_refs_gen; let lmg0 = bs.mut_grow_gen;
    if snap >= 0 {
        bs.scan_budget = 64; opt_invalidate_subtree(p, o, bs, left);
        bs.scan_budget = 128; opt_invalidate_subtree(p, o, bs, right);
    }
    if ks0 >= 0 { opt_add_nonneg(bs, ks0); }
    if ks1 >= 0 { opt_add_nonneg(bs, ks1); }
    if ks2 >= 0 { opt_add_nonneg(bs, ks2); }
    if ks3 >= 0 { opt_add_nonneg(bs, ks3); }
    if dg0_sym >= 0 { opt_add_guard_raw(bs, dg0_sym, -1, false, dg0_asym, dg0_afield, dg0_aimm); opt_add_nonneg(bs, dg0_sym); }
    if dg1_sym >= 0 { opt_add_guard_raw(bs, dg1_sym, -1, false, dg1_asym, dg1_afield, dg1_aimm); opt_add_nonneg(bs, dg1_sym); }
    let cany0 = bs.mut_any_gen;
    let lk = p.nodes[left].kind;
    if lk < N_INTEGER || lk > N_NAME { opt_prove_bounds(p, o, bs, left); }
    let cond_mut = bs.mut_any_gen != cany0;
    opt_harvest_cond(p, o, bs, left, true, cond_mut);
    if right >= 0 { opt_prove_bounds(p, o, bs, right); }
    let lms1 = bs.mut_slen; let lmf1 = bs.mut_flen;
    let lma_dirty = bs.mut_arrays_gen != lma0; let lmr_dirty = bs.mut_refs_gen != lmr0; let lmg_dirty = bs.mut_grow_gen != lmg0;
    opt_snap_pop(bs, snap);
    if snap >= 0 { opt_replay_mutations(bs, lms0, lms1, lmf0, lmf1, lma_dirty, lmr_dirty, lmg_dirty); }
    if ks0 >= 0 { opt_add_nonneg(bs, ks0); }
    if ks1 >= 0 { opt_add_nonneg(bs, ks1); }
    if ks2 >= 0 { opt_add_nonneg(bs, ks2); }
    if ks3 >= 0 { opt_add_nonneg(bs, ks3); }
    if dg0_sym >= 0 { opt_add_guard_raw(bs, dg0_sym, -1, false, dg0_asym, dg0_afield, dg0_aimm); opt_add_nonneg(bs, dg0_sym); }
    if dg1_sym >= 0 { opt_add_guard_raw(bs, dg1_sym, -1, false, dg1_asym, dg1_afield, dg1_aimm); opt_add_nonneg(bs, dg1_sym); }
    if !bs.has_break && (node >= o.function_states.len || (o.function_states[node] & OPT_HAS_BREAK) == 0) {
        opt_harvest_cond(p, o, bs, left, false, cond_mut);
    }
}

recursive fn opt_prove_assign(p: Program&, o: Optimizer&, bs: OptBoundState&, node: i64) {
    let n: const Node& = p.nodes[node];
    let left = n.left; let right = n.right; let op = n.integer;
    if left >= 0 {
        let lk = p.nodes[left].kind;
        if lk != N_NAME && (lk < N_INTEGER || lk > N_NAME) { opt_prove_bounds(p, o, bs, left); }
    }
    if right >= 0 {
        let rk = p.nodes[right].kind;
        if rk < N_INTEGER || rk > N_NAME { opt_prove_bounds(p, o, bs, right); }
    }
    var dst_sym: i64 = -1;
    var was_guarded = false;
    var rhs_nonneg = false;
    var rhs_asym: i64 = -1; var rhs_afield: i64 = -1; var rhs_aimm = false;
    if left >= 0 && p.nodes[left].kind == N_NAME && p.nodes[left].symbol >= 0 && opt_is_index_var(o, p.nodes[left].symbol) && opt_index_safe(p, o, p.nodes[left].symbol) {
        dst_sym = p.nodes[left].symbol;
        was_guarded = bs.glen > 0 && opt_sym_has_guard(bs, dst_sym);
        if op == T_ASSIGN && right >= 0 {
            let rk = p.nodes[right].kind;
            rhs_nonneg = opt_is_nonneg(p, o, bs, right);
            if (rk == N_BINARY && (p.nodes[right].integer == T_BITAND || p.nodes[right].integer == T_MOD) || rk == N_CAST) &&
               opt_match_inbounds_into(p, o, bs, right) {
                rhs_asym = bs.path_sym; rhs_afield = bs.path_field; rhs_aimm = bs.path_imm;
            }
        }
    }
    if bs.snap_depth > 0 || bs.glen > 0 || bs.nlen > 0 || bs.alen > 0 || bs.mlen > 0 || bs.elen > 0 {
        opt_invalidate_assign_target(p, bs, left);
    }
    if dst_sym >= 0 {
        if rhs_asym >= 0 {
            opt_add_guard_raw(bs, dst_sym, -1, false, rhs_asym, rhs_afield, rhs_aimm);
            opt_add_nonneg(bs, dst_sym);
        } else if rhs_nonneg {
            opt_add_nonneg(bs, dst_sym);
        } else if was_guarded && p.symbols[dst_sym].type_id == TYPE_I64 &&
                  (op == T_INC || op == T_PLUSEQ && right >= 0 && p.nodes[right].kind == N_INTEGER && p.nodes[right].integer == 1) {
            opt_add_nonneg(bs, dst_sym);
        }
    }
}

recursive fn opt_prove_var(p: Program&, o: Optimizer&, bs: OptBoundState&, node: i64) {
    let n: const Node& = p.nodes[node];
    let first = n.first; let right = n.right; let sym = n.symbol; let origin = n.origin;
    let saved = bs.checkfree; let saved_body = bs.body;
    if origin >= 0 && p.nodes[origin].kind == N_PARAM && bs.inline_parent_body >= 0 {
        // Arguments to an inlined call still execute as the caller's text.
        bs.checkfree = bs.inline_parent; bs.body = bs.inline_parent_body;
    }
    if right >= 0 {
        let rk0 = p.nodes[right].kind;
        if rk0 < N_INTEGER || rk0 > N_NAME { opt_prove_bounds(p, o, bs, right); }
        var extra = p.nodes[right].next;
        while extra >= 0 {
            let ek = p.nodes[extra].kind;
            if ek < N_INTEGER || ek > N_NAME { opt_prove_bounds(p, o, bs, extra); }
            extra = p.nodes[extra].next;
        }
    }
    bs.checkfree = saved; bs.body = saved_body;
    if sym < 0 || first >= 0 || right < 0 || !opt_index_safe(p, o, sym) { return; }
    let rk = p.nodes[right].kind;
    if (rk == N_CALL || rk == N_MEMBER || rk == N_BINARY && p.nodes[right].integer == T_MINUS || rk == N_CAST || rk == N_NAME && bs.alen > 0) &&
       opt_len_expr_into(p, o, bs, right) && bs.path_delta <= 0 {
        opt_add_alias_raw(bs, sym, bs.path_sym, bs.path_field, bs.path_imm, bs.path_delta);
        if bs.path_delta == 0 && opt_is_index_var(o, sym) { opt_add_nonneg(bs, sym); }
    }
    if opt_is_index_var(o, sym) {
        if (rk == N_BINARY && (p.nodes[right].integer == T_BITAND || p.nodes[right].integer == T_MOD) || rk == N_CAST) &&
           opt_match_inbounds_into(p, o, bs, right) {
            opt_add_guard_raw(bs, sym, -1, false, bs.path_sym, bs.path_field, bs.path_imm);
            opt_add_nonneg(bs, sym);
        } else if rk == N_NAME && bs.glen > 0 && p.nodes[right].symbol >= 0 {
            let rsym = p.nodes[right].symbol;
            let gcount = bs.glen;
            for gi in 0..gcount {
                if bs.guards[gi].index_sym == rsym && bs.guards[gi].index_field < 0 {
                    let was_pos = bs.guards[gi].pos;
                    opt_add_guard_raw(bs, sym, -1, false, bs.guards[gi].arr_sym, bs.guards[gi].arr_field, bs.guards[gi].arr_imm_slice);
                    if was_pos { opt_mark_guard_pos(bs, sym); }
                }
            }
            if opt_is_nonneg(p, o, bs, right) { opt_add_nonneg(bs, sym); }
        } else if opt_is_nonneg(p, o, bs, right) {
            opt_add_nonneg(bs, sym);
        }
    }
    if origin >= 0 && (bs.glen > 0 || bs.mlen > 0 || bs.elen > 0) &&
       (rk == N_NAME || rk == N_MEMBER || rk == N_UNARY && p.nodes[right].integer == T_MUL) {
        let raw_sty = p.symbols[sym].type_id;
        var inner_sty = raw_sty;
        if inner_sty >= 0 && p.types[inner_sty].kind == TY_REF { inner_sty = p.types[inner_sty].element; }
        if inner_sty >= 0 && (p.types[inner_sty].kind == TY_ARRAY || p.types[inner_sty].kind == TY_SLICE) &&
           opt_array_path_into(p, o, bs, right) {
            let sym_imm = (p.symbols[sym].flags & (S_MUTABLE | S_GLOBAL)) == 0 &&
                raw_sty >= 0 && p.types[raw_sty].kind == TY_SLICE &&
                (o.facts[sym].flags & (OPT_FACT_DIRECT_WRITTEN | OPT_FACT_ADDRESSED)) == 0;
            opt_add_len_eq_raw(bs, sym, -1, sym_imm, bs.path_sym, bs.path_field, bs.path_imm);
        }
    }
}

fn opt_prove_call_post(p: Program&, o: Optimizer&, bs: OptBoundState&, node: i64, sym: i64, first: i64) {
    if sym >= 0 && (p.symbols[sym].flags & S_BUILTIN) != 0 {
        let b = p.symbols[sym].index;
        if b == 3 && first >= 0 {
            opt_harvest_cond(p, o, bs, first, true, false);
            return;
        }
        if b == 24 && first >= 0 {
            bs.mut_any_gen++; bs.mut_grow_gen++;
            if bs.elen > 0 { opt_kill_eq_mutable_only(bs); }
            if opt_array_path_into(p, o, bs, first) { opt_add_len_min_raw(bs, bs.path_sym, bs.path_field, bs.path_imm, 1); }
            return;
        }
        if b == 28 && first >= 0 {
            let has_rarr = opt_array_path_into(p, o, bs, first);
            let r_sym = bs.path_sym; let r_field = bs.path_field; let r_imm = bs.path_imm;
            let second = p.nodes[first].next;
            var r_const: i64 = -1;
            var r_idx: i64 = -1;
            if second >= 0 {
                if p.nodes[second].kind == N_INTEGER && p.nodes[second].integer >= 1 && p.nodes[second].integer <= 1048576 {
                    r_const = p.nodes[second].integer;
                } else if p.nodes[second].kind == N_BINARY && p.nodes[second].integer == T_PLUS &&
                          p.nodes[second].left >= 0 && p.nodes[second].right >= 0 {
                    var candidate: i64 = -1;
                    if p.nodes[p.nodes[second].right].kind == N_INTEGER && p.nodes[p.nodes[second].right].integer >= 1 {
                        candidate = p.nodes[second].left;
                    } else if p.nodes[p.nodes[second].left].kind == N_INTEGER && p.nodes[p.nodes[second].left].integer >= 1 {
                        candidate = p.nodes[second].right;
                    }
                    if candidate >= 0 && opt_index_key_into(p, o, bs, candidate) && bs.key_field < 0 &&
                       (opt_key_unsigned_raw(p, bs.key_sym, -1) || opt_has_nonneg(bs, bs.key_sym)) {
                        r_idx = bs.key_sym;
                    }
                }
            }
            opt_invalidate_call(p, bs, node);
            if has_rarr {
                if r_const >= 1 { opt_add_len_min_raw(bs, r_sym, r_field, r_imm, r_const); }
                if r_idx >= 0 {
                    opt_add_guard_raw(bs, r_idx, -1, false, r_sym, r_field, r_imm);
                    opt_add_len_min_raw(bs, r_sym, r_field, r_imm, 1);
                }
            }
            return;
        }
    }
    if bs.snap_depth > 0 || bs.glen > 0 || bs.nlen > 0 || bs.alen > 0 || bs.mlen > 0 || bs.elen > 0 {
        opt_invalidate_call(p, bs, node);
    } else {
        bs.mut_any_gen++;
    }
}

recursive fn opt_prove_defer(p: Program&, o: Optimizer&, bs: OptBoundState&, node: i64) {
    if bs.checkfree >= 0 {
        let snap = opt_snap_push(bs);
        bs.glen = 0; bs.nlen = 0; bs.alen = 0; bs.mlen = 0; bs.elen = 0;
        opt_prove_bounds(p, o, bs, node);
        opt_snap_pop(bs, snap);
    }
    bs.scan_budget = 128;
    opt_invalidate_subtree(p, o, bs, node);
}

recursive fn opt_prove_block(p: Program&, o: Optimizer&, bs: OptBoundState&, node: i64) {
    let n: const Node& = p.nodes[node];
    let first = n.first; let flags = n.flags; let ty = n.type_id;
    let rollback = (flags & F_EARLY) != 0 || ty != TYPE_VOID || bs.has_break ||
        (node < o.function_states.len && (o.function_states[node] & OPT_HAS_BREAK) != 0);
    if !rollback {
        var has_defer = false;
        var stmt = first;
        while stmt >= 0 {
            let sk = p.nodes[stmt].kind;
            if sk == N_DEFER { has_defer = true; }
            else if sk < N_INTEGER || sk > N_NAME { opt_prove_bounds(p, o, bs, stmt); }
            stmt = p.nodes[stmt].next;
        }
        if has_defer {
            stmt = first;
            while stmt >= 0 {
                if p.nodes[stmt].kind == N_DEFER { opt_prove_defer(p, o, bs, p.nodes[stmt].right); }
                stmt = p.nodes[stmt].next;
            }
        }
        return;
    }
    let ms0 = bs.mut_slen; let mf0 = bs.mut_flen;
    let ma0 = bs.mut_arrays_gen; let mr0 = bs.mut_refs_gen; let mg0 = bs.mut_grow_gen;
    let snap = opt_snap_push(bs);
    var has_defer = false;
    var stmt = first;
    while stmt >= 0 {
        let sk = p.nodes[stmt].kind;
        if sk == N_DEFER { has_defer = true; }
        else if sk < N_INTEGER || sk > N_NAME { opt_prove_bounds(p, o, bs, stmt); }
        stmt = p.nodes[stmt].next;
    }
    if has_defer {
        stmt = first;
        while stmt >= 0 {
            if p.nodes[stmt].kind == N_DEFER { opt_prove_defer(p, o, bs, p.nodes[stmt].right); }
            stmt = p.nodes[stmt].next;
        }
    }
    opt_snap_pop(bs, snap);
    if snap >= 0 { opt_replay_mutations(bs, ms0, bs.mut_slen, mf0, bs.mut_flen, bs.mut_arrays_gen != ma0, bs.mut_refs_gen != mr0, bs.mut_grow_gen != mg0); }
}

recursive fn opt_prove_bounds(p: Program&, o: Optimizer&, bs: OptBoundState&, node: i64) {
    if node < 0 { return; }
    let n: const Node& = p.nodes[node];
    let kind = n.kind;
    if kind >= N_INTEGER && kind <= N_NAME || kind == N_EMPTY || kind == N_CONTINUE || kind == N_FUNCTION || kind == N_FUNCTION_VALUE { return; }
    if kind == N_MEMBER || kind == N_CAST || kind == N_EXPR_STMT {
        let left = n.left;
        if left >= 0 { let lk = p.nodes[left].kind; if lk < N_INTEGER || lk > N_NAME { opt_prove_bounds(p, o, bs, left); } }
        if bs.checkfree >= 0 && kind == N_CAST { opt_check_index_cast(p, o, bs, node); }
        return;
    }
    if kind == N_BINARY {
        let op = n.integer; let left = n.left; let right = n.right;
        if op != T_ANDAND && op != T_OROR {
            if left >= 0 { let lk = p.nodes[left].kind; if lk < N_INTEGER || lk > N_NAME { opt_prove_bounds(p, o, bs, left); } }
            if right >= 0 { let rk = p.nodes[right].kind; if rk < N_INTEGER || rk > N_NAME { opt_prove_bounds(p, o, bs, right); } }
            return;
        }
        if left >= 0 && right >= 0 {
            let cany0 = bs.mut_any_gen;
            let lk = p.nodes[left].kind;
            if lk < N_INTEGER || lk > N_NAME { opt_prove_bounds(p, o, bs, left); }
            let rn: const Node& = p.nodes[right];
            let rk = rn.kind;
            if rk >= N_INTEGER && rk <= N_NAME { return; }
            if rk == N_BINARY && rn.integer != T_ANDAND && rn.integer != T_OROR && rn.left >= 0 && rn.right >= 0 {
                let rlk = p.nodes[rn.left].kind; let rrk = p.nodes[rn.right].kind;
                if rlk >= N_INTEGER && rlk <= N_NAME && rrk >= N_INTEGER && rrk <= N_NAME { return; }
            }
            let cond_mut = bs.mut_any_gen != cany0;
            let snap = opt_snap_push(bs);
            let rms0 = bs.mut_slen; let rmf0 = bs.mut_flen; let rma0 = bs.mut_arrays_gen; let rmr0 = bs.mut_refs_gen; let rmg0 = bs.mut_grow_gen;
            opt_harvest_cond(p, o, bs, left, op == T_ANDAND, cond_mut);
            opt_prove_bounds(p, o, bs, right);
            let rms1 = bs.mut_slen; let rmf1 = bs.mut_flen;
            let rma_dirty = bs.mut_arrays_gen != rma0; let rmr_dirty = bs.mut_refs_gen != rmr0; let rmg_dirty = bs.mut_grow_gen != rmg0;
            opt_snap_pop(bs, snap);
            if snap >= 0 { opt_replay_mutations(bs, rms0, rms1, rmf0, rmf1, rma_dirty, rmr_dirty, rmg_dirty); }
        }
        return;
    }
    if kind == N_SLICE && bs.checkfree >= 0 {
        opt_prove_bounds(p, o, bs, n.left);
        opt_prove_bounds(p, o, bs, n.right);
        opt_prove_bounds(p, o, bs, n.third);
        opt_check_slice(p, o, bs, node);
        return;
    }
    if kind == N_INDEX {
        let left = n.left; let right = n.right;
        if left >= 0 { let lk = p.nodes[left].kind; if lk < N_INTEGER || lk > N_NAME { opt_prove_bounds(p, o, bs, left); } }
        if right >= 0 { let rk = p.nodes[right].kind; if rk < N_INTEGER || rk > N_NAME { opt_prove_bounds(p, o, bs, right); } }
        opt_check_index(p, o, bs, node);
        return;
    }
    if kind == N_BLOCK {
        let saved = bs.checkfree; let saved_body = bs.body;
        let parent = bs.inline_parent; let parent_body = bs.inline_parent_body;
        if n.origin >= 0 && (n.flags & F_EARLY) != 0 && validation_checkfree(p, n.origin) {
            bs.inline_parent = saved; bs.inline_parent_body = saved_body;
            bs.checkfree = n.origin; bs.body = node;
        }
        opt_prove_block(p, o, bs, node);
        bs.checkfree = saved; bs.body = saved_body;
        bs.inline_parent = parent; bs.inline_parent_body = parent_body;
        return;
    }
    if kind == N_IF && n.left >= 0 { opt_prove_if(p, o, bs, node); return; }
    if kind == N_ASSIGN { opt_prove_assign(p, o, bs, node); return; }
    if kind == N_VARIABLE { opt_prove_var(p, o, bs, node); return; }
    if kind == N_CALL {
        let first = n.first; let left = n.left; let sym = n.symbol;
        var arg = first;
        while arg >= 0 {
            let ak = p.nodes[arg].kind;
            if ak < N_INTEGER || ak > N_NAME { opt_prove_bounds(p, o, bs, arg); }
            arg = p.nodes[arg].next;
        }
        if left >= 0 {
            let lk = p.nodes[left].kind;
            if lk < N_INTEGER || lk > N_NAME { opt_prove_bounds(p, o, bs, left); }
        }
        opt_prove_call_post(p, o, bs, node, sym, first);
        return;
    }
    if kind == N_FOR && n.left >= 0 { opt_prove_for(p, o, bs, node); return; }
    if kind == N_WHILE && n.left >= 0 { opt_prove_while(p, o, bs, node); return; }
    if kind == N_UNARY {
        let left = n.left; let op = n.integer;
        if left >= 0 { let lk = p.nodes[left].kind; if lk < N_INTEGER || lk > N_NAME { opt_prove_bounds(p, o, bs, left); } }
        if op == T_BITAND {
            let root = check_place_root(p, left);
            if root >= 0 { opt_kill_sym(bs, root); }
        }
        return;
    }
    let first = n.first; let left = n.left; let right = n.right; let third = n.third;
    if kind == N_LOOP {
        let snap = opt_snap_push(bs);
        let lms0 = bs.mut_slen; let lmf0 = bs.mut_flen; let lma0 = bs.mut_arrays_gen; let lmr0 = bs.mut_refs_gen; let lmg0 = bs.mut_grow_gen;
        if snap >= 0 { bs.scan_budget = 128; opt_invalidate_subtree(p, o, bs, right); }
        if right >= 0 { opt_prove_bounds(p, o, bs, right); }
        let lms1 = bs.mut_slen; let lmf1 = bs.mut_flen;
        let lma_dirty = bs.mut_arrays_gen != lma0; let lmr_dirty = bs.mut_refs_gen != lmr0; let lmg_dirty = bs.mut_grow_gen != lmg0;
        opt_snap_pop(bs, snap);
        if snap >= 0 { opt_replay_mutations(bs, lms0, lms1, lmf0, lmf1, lma_dirty, lmr_dirty, lmg_dirty); }
        return;
    }
    if kind == N_MATCH {
        if left >= 0 { let lk = p.nodes[left].kind; if lk < N_INTEGER || lk > N_NAME { opt_prove_bounds(p, o, bs, left); } }
        let snap = opt_snap_push(bs);
        let mms0 = bs.mut_slen; let mmf0 = bs.mut_flen; let mma0 = bs.mut_arrays_gen; let mmr0 = bs.mut_refs_gen; let mmg0 = bs.mut_grow_gen;
        var arm = first;
        while arm >= 0 {
            opt_snap_restore(bs, snap);
            if p.nodes[arm].third >= 0 { opt_prove_bounds(p, o, bs, p.nodes[arm].third); }
            if p.nodes[arm].right >= 0 { opt_prove_bounds(p, o, bs, p.nodes[arm].right); }
            arm = p.nodes[arm].next;
        }
        let mms1 = bs.mut_slen; let mmf1 = bs.mut_flen;
        let mma_dirty = bs.mut_arrays_gen != mma0; let mmr_dirty = bs.mut_refs_gen != mmr0; let mmg_dirty = bs.mut_grow_gen != mmg0;
        opt_snap_pop(bs, snap);
        if snap >= 0 { opt_replay_mutations(bs, mms0, mms1, mmf0, mmf1, mma_dirty, mmr_dirty, mmg_dirty); }
        return;
    }
    if kind == N_MULTI_ASSIGN {
        var target = first;
        while target >= 0 { opt_invalidate_assign_target(p, bs, target); target = p.nodes[target].next; }
        target = first;
        while target >= 0 {
            if p.nodes[target].kind != N_NAME { opt_prove_bounds(p, o, bs, target); }
            target = p.nodes[target].next;
        }
        var expr = right;
        while expr >= 0 { opt_prove_bounds(p, o, bs, expr); expr = p.nodes[expr].next; }
        target = first;
        while target >= 0 { opt_invalidate_assign_target(p, bs, target); target = p.nodes[target].next; }
        return;
    }
    var child = first;
    while child >= 0 {
        let ck = p.nodes[child].kind;
        if ck < N_INTEGER || ck > N_NAME { opt_prove_bounds(p, o, bs, child); }
        child = p.nodes[child].next;
    }
    if left >= 0 && kind != N_RECORD && kind != N_VARIABLE {
        let lk = p.nodes[left].kind;
        if lk < N_INTEGER || lk > N_NAME { opt_prove_bounds(p, o, bs, left); }
    }
    if right >= 0 {
        let rk = p.nodes[right].kind;
        if rk < N_INTEGER || rk > N_NAME { opt_prove_bounds(p, o, bs, right); }
    }
    if third >= 0 {
        let tk = p.nodes[third].kind;
        if tk < N_INTEGER || tk > N_NAME { opt_prove_bounds(p, o, bs, third); }
    }
}

// The original body of an explicitly inline helper can be dead after
// rewriting; only the copies that will execute must keep their promise.
fn opt_remove_inlined_checkfree(p: Program&, count: i64) {
    var used: bool[>..] = []; used.resize(count, false);
    var inlined: bool[>..] = []; inlined.resize(count, false);
    for n in p.nodes {
        if n.symbol < 0 || n.symbol >= count { continue; }
        if n.kind == N_CALL || n.kind == N_NAME && n.type_id >= 0 || n.kind == N_ARM { used[n.symbol] = true; }
        if n.kind == N_BLOCK && n.origin >= 0 && (n.flags & F_EARLY) != 0 { inlined[n.symbol] = true; }
    }
    for i in 0..count {
        let fn_node = p.symbols[i].node;
        if !inlined[i] || used[i] || fn_node < 0 || fn_node == p.entry || p.nodes[fn_node].kind != N_FUNCTION { continue; }
        let flags = p.nodes[fn_node].flags;
        if (flags & (F_CHECKFREE | F_INLINE | F_EXPORT | F_THREAD)) == (F_CHECKFREE | F_INLINE) {
            p.nodes[fn_node].flags &= ~F_REACHABLE;
        }
    }
}

fn opt_prove_bounds_program(p: Program&, o: Optimizer&, count: i64) {
    while o.facts.len < p.symbols.len { o.facts.push(OptFact {}); }
    var optimizer_bound_guards: OptBoundGuard[>..] = [];
    var optimizer_bound_nonneg: i64[>..] = [];
    var optimizer_bound_aliases: OptLenAlias[>..] = [];
    var optimizer_bound_mins: OptLenMin[>..] = [];
    var optimizer_bound_eqs: OptLenEq[>..] = [];
    var optimizer_bound_snaps: OptBoundSnap[>..] = [];
    var optimizer_snap_guards: OptBoundGuard[>..] = [];
    var optimizer_snap_nonneg: i64[>..] = [];
    var optimizer_snap_aliases: OptLenAlias[>..] = [];
    var optimizer_snap_mins: OptLenMin[>..] = [];
    var optimizer_snap_eqs: OptLenEq[>..] = [];
    var optimizer_mut_syms: i64[>..] = [];
    var optimizer_mut_fields: i64[>..] = [];
    var bs = OptBoundState {
        guards: optimizer_bound_guards, nonneg: optimizer_bound_nonneg, aliases: optimizer_bound_aliases,
        mins: optimizer_bound_mins, eqs: optimizer_bound_eqs, snaps: optimizer_bound_snaps,
        snap_guards: optimizer_snap_guards, snap_nonneg: optimizer_snap_nonneg, snap_aliases: optimizer_snap_aliases,
        snap_mins: optimizer_snap_mins, snap_eqs: optimizer_snap_eqs,
        mut_syms: optimizer_mut_syms, mut_fields: optimizer_mut_fields,
    };
    for i in 0..count {
        let s: const Symbol& = p.symbols[i];
        if s.node < 0 || (s.flags & (S_FUNCTION | S_BUILTIN)) != S_FUNCTION { continue; }
        let flags = p.nodes[s.node].flags;
        let checkfree = (flags & (F_CHECKED | F_REACHABLE)) == (F_CHECKED | F_REACHABLE) && validation_checkfree(p, s.node);
        let optimize = p.optimization >= 2 && (flags & F_REACHABLE) != 0 &&
                       s.node < o.function_states.len && (o.function_states[s.node] & OPT_HAS_INDEX) != 0;
        if checkfree || optimize {
            let body = p.nodes[s.node].right;
            if body >= 0 {
                bs.glen = 0; bs.nlen = 0; bs.alen = 0; bs.mlen = 0; bs.elen = 0;
                bs.snap_depth = 0; bs.sglen = 0; bs.snlen = 0; bs.salen = 0; bs.smlen = 0; bs.selen = 0;
                bs.mut_slen = 0; bs.mut_flen = 0;
                bs.checkfree = if checkfree { s.node } else { -1 };
                bs.body = body;
                bs.has_break = (o.function_states[s.node] & OPT_HAS_BREAK) != 0;
                opt_prove_bounds(p, o, bs, body);
            }
        }
    }
}

recursive fn opt_function(p: Program&, o: Optimizer&, node: i64) {
    if node < 0 { return; }
    if node >= o.function_states.len { o.function_states.resize(p.nodes.len, 0); }
    if (o.function_states[node] & (OPT_ACTIVE | OPT_DONE)) != 0 { return; }
    o.function_states[node] = OPT_ACTIVE;
    var done_bits: u8 = OPT_DONE;
    let body = p.nodes[node].right;
    if body >= 0 {
        let saved = o.current_function; let saved_slot = o.next_slot; let saved_index = o.has_index; let saved_break = o.has_break;
        o.current_function = node; o.next_slot = 0; o.has_index = false; o.has_break = false;
        if node < o.first_free_slots.len { o.next_slot = o.first_free_slots[node]; }
        opt_node(p, o, body, 0); opt_tail_function(p, o, node);
        if o.has_index { done_bits |= OPT_HAS_INDEX; }
        if o.has_break { done_bits |= OPT_HAS_BREAK; }
        o.current_function = saved; o.next_slot = saved_slot; o.has_index = saved_index; o.has_break = saved_break;
    }
    o.function_states[node] = (o.function_states[node] & ~OPT_ACTIVE) | done_bits;
}
fn optimize_program(p: Program&) {
    if p.diagnostics.len > 0 { return; }
    var optimizer_facts: OptFact[>..] = []; optimizer_facts.resize(p.symbols.len, OptFact {});
    var function_states: u8[>..] = []; function_states.resize(p.nodes.len, 0);
    var optimizer_maps: OptMap[>..] = []; var optimizer_node_maps: OptNodeMap[>..] = [];
    var optimizer_dependencies: i64[>..] = []; var optimizer_proof_old: i64[>..] = []; var optimizer_proof_new: i64[>..] = [];
    var optimizer_inlined_blocks: i64[>..] = [];
    // Each function is optimized once. Inlining and tail calls allocate their
    // temporaries from next_slot while that function is active.
    var slots: i64[>..] = [];
    for s_id in 0..p.symbols.len {
        let symbol: const Symbol& = p.symbols[s_id];
        if symbol.owner < 0 || symbol.slot < 0 { continue; }
        if symbol.owner >= slots.len { slots.resize(symbol.owner + 1, 0); }
        if symbol.slot >= slots[symbol.owner] { slots[symbol.owner] = symbol.slot + 1; }
    }
    var o = Optimizer {
        first_free_slots: slots[..], facts: optimizer_facts, function_states: function_states, maps: optimizer_maps,
        node_maps: optimizer_node_maps, dependency_work: optimizer_dependencies, proof_old: optimizer_proof_old,
        proof_new: optimizer_proof_new, inlined_blocks: optimizer_inlined_blocks,
    };
    let count = p.symbols.len;
    for i in 0..count {
        let s: const Symbol& = p.symbols[i]; if s.node < 0 { continue; }
        if (s.flags & S_GLOBAL) != 0 && s.component_owner < 0 { opt_collect(p, o, s.node); }
        if (s.flags & S_FUNCTION) != 0 && (s.flags & S_BUILTIN) == 0 && (p.nodes[s.node].flags & F_REACHABLE) != 0 {
            opt_collect(p, o, p.nodes[s.node].right);
        }
    }
    for i in 0..count {
        let s: const Symbol& = p.symbols[i]; if s.node >= 0 && (s.flags & S_GLOBAL) != 0 && s.component_owner < 0 { opt_node(p, o, s.node, 0); }
    }
    for i in 0..count {
        let s: const Symbol& = p.symbols[i];
        if s.node >= 0 && (s.flags & S_FUNCTION) != 0 && (s.flags & S_BUILTIN) == 0 &&
           (p.nodes[s.node].flags & F_REACHABLE) != 0 { opt_function(p, o, s.node); }
    }
    let checkfree = opt_has_checkfree(p);
    if checkfree { opt_remove_inlined_checkfree(p, count); }
    if p.optimization >= 2 || checkfree { opt_prove_bounds_program(p, o, count); }
    life_refresh_named_results_for(p, o.inlined_blocks[..]);
}
