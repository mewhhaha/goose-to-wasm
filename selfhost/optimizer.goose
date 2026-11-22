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

struct OptFact { writes: i64 = 0, addresses: i64 = 0, calls: i64 = 0, literal: i64 = -1 }
struct OptBoundGuard { index_sym: i64, arr_sym: i64, arr_field: i64 }
struct OptArrayPath { sym: i64 = -1, field: i64 = -1, immutable_slice: bool = false }
struct OptMap { from: i64, to: i64 }
struct OptNodeMap { from: i64, to: i64 }
let OPT_ACTIVE: u8 = 1;
let OPT_DONE: u8 = 2;
let OPT_DEP_KNOWN: u8 = 4;
let OPT_DEP_BAD: u8 = 8;
let OPT_SDEP_KNOWN: u8 = 16;
let OPT_SDEP_BAD: u8 = 32;
struct Optimizer {
    first_free_slots: const i64[:],
    facts: OptFact[>..]&, function_states: u8[>..]&, maps: OptMap[>..]&, node_maps: OptNodeMap[>..]&, dependency_work: i64[>..]&, proof_old: i64[>..]&, proof_new: i64[>..]&,
    bound_guards: OptBoundGuard[>..]&,
    inlined_blocks: i64[>..]&,
    current_function: i64 = -1, next_slot: i64 = 0, folded: i64 = 0, propagated: i64 = 0,
    inlined: i64 = 0, tail_loops: i64 = 0, has_index: bool = false,
    // While a library body is copied into the program's code, the call its
    // library nodes report at (opt_note_site); -1 otherwise.
    site: i64 = -1,
}
fn opt_fact(o: Optimizer&, symbol: i64) {
    while o.facts.len <= symbol { o.facts.push(OptFact {}); }
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
}
fn opt_set_integer(p: Program&, node: i64, value: i64, kind: i64) {
    let original = p.nodes[node];
    p.nodes[node] = Node { kind: kind, token: original.token, next: original.next, type_id: original.type_id, integer: value, flags: original.flags | F_CHECKED, scope: original.scope };
}
fn opt_float_value(p: Program&, type_id: i64, value: f64) -> f64 {
    if check_numeric_value_type(p, type_id) == TYPE_F32 { return (value as! f32) as f64; }
    return value;
}
fn opt_set_float(p: Program&, node: i64, value: f64) {
    let original = p.nodes[node];
    p.nodes[node] = Node { kind: N_FLOAT, token: original.token, next: original.next, type_id: original.type_id, float_value: opt_float_value(p, original.type_id, value), flags: original.flags | F_CHECKED, scope: original.scope };
}
fn opt_empty(p: Program&, node: i64) {
    let original = p.nodes[node];
    p.nodes[node] = Node { kind: N_EMPTY, token: original.token, next: original.next, type_id: TYPE_VOID, flags: F_CHECKED, scope: original.scope };
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
recursive fn opt_collect(p: Program&, o: Optimizer&, node: i64) {
    if node < 0 { return; }
    let n: const Node& = p.nodes[node];
    if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE { return; }
    if n.kind == N_ASSIGN || n.kind == N_MULTI_ASSIGN {
        var target = n.left; if n.kind == N_MULTI_ASSIGN { target = n.first; }
        while target >= 0 {
            let symbol = check_place_root(p, target);
            if symbol >= 0 { opt_fact(o, symbol); o.facts[symbol].writes += 1; }
            if n.kind != N_MULTI_ASSIGN { break; }
            target = p.nodes[target].next;
        }
    }
    if n.kind == N_UNARY && n.integer == T_BITAND {
        let symbol = check_place_root(p, n.left);
        if symbol >= 0 { opt_fact(o, symbol); o.facts[symbol].addresses += 1; }
    }
    if n.kind == N_CALL && n.symbol >= 0 {
        opt_fact(o, n.symbol); o.facts[n.symbol].calls += 1;
        let s: const Symbol& = p.symbols[n.symbol];
        if (s.flags & S_BUILTIN) != 0 && (s.index == 2 || s.index >= 24) && n.first >= 0 {
            let root = check_place_root(p, n.first);
            if root >= 0 { opt_fact(o, root); o.facts[root].writes += 1; }
        }
    }
    var child = n.first;
    while child >= 0 { opt_collect(p, o, child); child = p.nodes[child].next; }
    if n.left >= 0 && n.kind != N_RECORD && n.kind != N_VARIABLE && n.kind != N_PARAM && n.kind != N_FIELD {
        opt_collect(p, o, n.left);
    }
    if n.right >= 0 { opt_collect(p, o, n.right); }
    if n.third >= 0 && n.kind != N_CALL { opt_collect(p, o, n.third); }
}
// Callers only need the exact cost up to their remaining inlining budget.
recursive fn opt_inline_cost(p: Program&, node: i64, budget: i64) -> i64 {
    if node < 0 { return 0; }
    let n: const Node& = p.nodes[node];
    if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE { return 0; }
    var cost = 1;
    var child = n.first;
    while child >= 0 && cost <= budget {
        cost += opt_inline_cost(p, child, budget - cost); child = p.nodes[child].next;
    }
    if cost <= budget && n.left >= 0 && n.kind != N_VARIABLE && n.kind != N_PARAM && n.kind != N_FIELD && n.kind != N_RECORD {
        cost += opt_inline_cost(p, n.left, budget - cost);
    }
    if cost <= budget && n.right >= 0 { cost += opt_inline_cost(p, n.right, budget - cost); }
    if cost <= budget && n.third >= 0 && (n.kind != N_CALL || (n.flags & F_DISPATCH) != 0) {
        cost += opt_inline_cost(p, n.third, budget - cost);
    }
    return cost;
}
recursive fn opt_separate_tree(p: Program&, o: Optimizer&, node: i64, owner: i64, visited_start: i64, strict: bool) -> bool {
    if node < 0 { return false; }
    let n: const Node& = p.nodes[node];
    if n.kind == N_NAME && n.symbol >= 0 && n.symbol < p.symbols.len && p.symbols[n.symbol].owner == owner { return true; }
    if n.kind == N_RETURN && n.symbol == p.nodes[owner].symbol { return true; }
    if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE { return false; }
    if n.kind == N_CALL && strict && (n.flags & F_DISPATCH) != 0 { return true; }
    if n.kind == N_CALL && opt_separate_call(p, o, n.symbol, owner, visited_start, strict) { return true; }
    var child = n.first; if n.kind == N_PATTERN { child = -1; }
    while child >= 0 { if opt_separate_tree(p, o, child, owner, visited_start, strict) { return true; } child = p.nodes[child].next; }
    // These nodes also own linked expression lists outside their first list.
    var extra = -1;
    if strict && n.kind == N_VARIABLE { extra = n.right; }
    if strict && n.kind == N_BREAK { extra = n.left; }
    while extra >= 0 {
        extra = p.nodes[extra].next;
        if opt_separate_tree(p, o, extra, owner, visited_start, strict) { return true; }
    }
    if n.kind != N_RECORD && n.kind != N_VARIABLE && n.kind != N_PARAM && n.kind != N_FIELD && opt_separate_tree(p, o, n.left, owner, visited_start, strict) { return true; }
    return opt_separate_tree(p, o, n.right, owner, visited_start, strict) || opt_separate_tree(p, o, n.third, owner, visited_start, strict);
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
    if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE { return false; }
    if n.kind == N_CALL && strict && (n.flags & F_DISPATCH) != 0 { return true; }
    if n.kind == N_CALL && opt_separate_call(p, o, n.symbol, owner, o.dependency_work.len, strict) { return true; }
    var child = n.first; if n.kind == N_PATTERN { child = -1; }
    while child >= 0 { if opt_inline_dependencies(p, o, child, owner, strict) { return true; } child = p.nodes[child].next; }
    var extra = -1;
    if strict && n.kind == N_VARIABLE { extra = n.right; }
    if strict && n.kind == N_BREAK { extra = n.left; }
    while extra >= 0 {
        extra = p.nodes[extra].next;
        if opt_inline_dependencies(p, o, extra, owner, strict) { return true; }
    }
    if n.kind != N_RECORD && n.kind != N_VARIABLE && n.kind != N_PARAM && n.kind != N_FIELD && opt_inline_dependencies(p, o, n.left, owner, strict) { return true; }
    return opt_inline_dependencies(p, o, n.right, owner, strict) || opt_inline_dependencies(p, o, n.third, owner, strict);
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
    let result = p.nodes.len; p.nodes.push(n); o.node_maps.push(OptNodeMap { from: node, to: result }); opt_note_site(p, o, node, result);
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
    p.nodes[result].left = opt_clone(p, o, left, map_start);
    if n.kind == N_BREAK && left >= 0 {
        var previous = p.nodes[result].left; var old = p.nodes[left].next;
        while old >= 0 { let copy = opt_clone(p, o, old, map_start); p.nodes[previous].next = copy; previous = copy; old = p.nodes[old].next; }
    }
    if n.kind == N_RECORD { p.nodes[result].right = right; }
    else { p.nodes[result].right = opt_clone(p, o, right, map_start); }
    if n.kind == N_VARIABLE && right >= 0 {
        var previous = p.nodes[result].right; var old = p.nodes[right].next;
        while old >= 0 { let copy = opt_clone(p, o, old, map_start); p.nodes[previous].next = copy; previous = copy; old = p.nodes[old].next; }
    }
    if n.kind != N_CALL || (n.flags & F_DISPATCH) != 0 { p.nodes[result].third = opt_clone(p, o, third, map_start); }
    if n.kind == N_CALL && (n.flags & F_DISPATCH) != 0 && third >= 0 {
        var previous = p.nodes[result].third; var old = p.nodes[third].next;
        while old >= 0 { let copy = opt_clone(p, o, old, map_start); p.nodes[previous].next = copy; previous = copy; old = p.nodes[old].next; }
    }
    return result;
}
fn opt_capture(p: Program&, function_node: i64, symbol: i64) {
    if function_node < 0 || symbol < 0 || symbol >= p.symbols.len { return; }
    let s = p.symbols[symbol];
    if s.owner < 0 || s.owner == function_node || (s.flags & (S_FUNCTION | S_TYPE | S_GLOBAL)) != 0 { return; }
    var binding = p.nodes[function_node].captures; var last = -1;
    while binding >= 0 { if p.nodes[binding].symbol == symbol { return; } last = binding; binding = p.nodes[binding].next; }
    let capture = new_node(p, N_BINDING, s.name_token); p.nodes[capture].symbol = symbol; p.nodes[capture].type_id = s.type_id;
    if last < 0 { p.nodes[function_node].captures = capture; } else { p.nodes[last].next = capture; }
    p.nodes[function_node].flags |= F_CAPTURE; p.symbols[symbol].flags |= S_CAPTURE;
}
recursive fn opt_fix_inline(p: Program&, o: Optimizer&, node: i64, callee: i64, target: i64, map_start: i64, node_start: i64) {
    if node < 0 { return; }
    var kind = p.nodes[node].kind;
    if kind == N_FUNCTION || kind == N_FUNCTION_VALUE { return; }
    let sym = p.nodes[node].symbol;
    if kind == N_NAME || kind == N_VARIABLE || kind == N_BINDING && sym >= 0 && sym < p.symbols.len && p.symbols[sym].node == node {
        let mapped = opt_mapped_symbol(o, sym, map_start);
        p.nodes[node].symbol = mapped;
        if kind == N_NAME { opt_capture(p, o.current_function, mapped); }
    }
    if kind == N_RETURN && sym == callee {
        p.nodes[node].kind = N_BREAK; p.nodes[node].symbol = target; p.nodes[node].left = p.nodes[node].first;
        p.nodes[node].first = -1; p.nodes[node].last = -1; p.nodes[node].flags &= ~F_NONLOCAL; kind = N_BREAK;
    } else if kind == N_RETURN && o.current_function >= 0 && sym == p.nodes[o.current_function].symbol { p.nodes[node].flags &= ~F_NONLOCAL; }
    if kind == N_BREAK || kind == N_CONTINUE {
        let cur_sym = p.nodes[node].symbol;
        for index in node_start..o.node_maps.len { let map: const OptNodeMap& = o.node_maps[index]; if cur_sym == map.from { p.nodes[node].symbol = map.to; break; } }
    }
    let first = p.nodes[node].first; let left = p.nodes[node].left;
    let right = p.nodes[node].right; let third = p.nodes[node].third;
    let flags = p.nodes[node].flags;
    var child = first; if kind == N_PATTERN { child = -1; }
    while child >= 0 { opt_fix_inline(p, o, child, callee, target, map_start, node_start); child = p.nodes[child].next; }
    if kind == N_BREAK {
        child = left;
        while child >= 0 { opt_fix_inline(p, o, child, callee, target, map_start, node_start); child = p.nodes[child].next; }
    } else if kind != N_RECORD && kind != N_VARIABLE && kind != N_PARAM && kind != N_FIELD { opt_fix_inline(p, o, left, callee, target, map_start, node_start); }
    opt_fix_inline(p, o, right, callee, target, map_start, node_start);
    if kind != N_CALL || (flags & F_DISPATCH) != 0 { opt_fix_inline(p, o, third, callee, target, map_start, node_start); }
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
    if p.optimization <= 0 || o.current_function < 0 { return false; }
    let strict = (p.nodes[o.current_function].flags & F_RECURSIVE) != 0;
    let call_flags = p.nodes[node].flags;
    let call_symbol = p.nodes[node].symbol;
    if (call_flags & F_DISPATCH) != 0 || call_symbol < 0 || call_symbol >= p.symbols.len { return false; }
    let sym_flags = p.symbols[call_symbol].flags;
    let callee_node = p.symbols[call_symbol].node;
    if (sym_flags & (S_BUILTIN | S_EXTERN)) != 0 || callee_node < 0 { return false; }
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
    opt_fact(o, call_symbol); var uses = o.facts[call_symbol].calls; if uses < 1 { uses = 1; }
    var budget = threshold;
    if use_threshold / uses > budget { budget = use_threshold / uses; }
    if uses == 1 && budget < 200 { budget = 200; }
    if (callee_flags & F_INLINE) != 0 { budget = 200; }
    let cost = opt_inline_cost(p, callee_right, budget);
    if cost > budget || opt_inline_dependencies_cached(p, o, callee_node, strict) { return false; }
    let call = p.nodes[node];
    let callee = p.nodes[callee_node];
    let map_start = o.maps.len; let node_start = o.node_maps.len;
    // A library body copied into the program's code, but into a checkfree
    // function, has its library nodes report at the call (upstream AtCallSite).
    let site = location_token(p, node); let outer_site = o.site; o.site = -1;
    if library_node(p, callee_node) && !library_token(p, site) && (p.nodes[o.current_function].flags & F_CHECKFREE) == 0 { o.site = site; }
    let inline_body = new_node(p, N_BLOCK, call.token); p.nodes[inline_body].flags = F_CHECKED | F_EARLY | (call.flags & F_DIVERGES);
    p.nodes[inline_body].type_id = call.type_id; p.nodes[inline_body].scope = call.scope;
    p.nodes[inline_body].origin = callee_node; p.nodes[inline_body].symbol = call.symbol;
    var formal = callee.first; var argument = call.first;
    while formal >= 0 {
        let next = p.nodes[argument].next; p.nodes[argument].next = -1;
        let local = opt_temporary(p, o, o.current_function, call.scope, p.nodes[formal].token, p.nodes[formal].type_id, argument);
        p.nodes[local].origin = formal; opt_note_site(p, o, formal, local);
        append_child(p, inline_body, local);
        o.maps.push(OptMap { from: p.nodes[formal].symbol, to: p.nodes[local].symbol }); opt_copy_fact(o, p.nodes[formal].symbol, p.nodes[local].symbol);
        formal = p.nodes[formal].next; argument = next;
    }
    let body = opt_clone(p, o, callee.right, map_start); o.site = outer_site;
    opt_fix_inline(p, o, body, call.symbol, inline_body, map_start, node_start);
    var child = p.nodes[body].first;
    while child >= 0 { let next = p.nodes[child].next; p.nodes[child].next = -1; append_child(p, inline_body, child); child = next; }
    let proof_start = o.proof_old.len;
    for index in map_start..o.maps.len { o.proof_old.push(o.maps[index].from); o.proof_new.push(o.maps[index].to); }
    life_clone_provenance(p, o.proof_old[proof_start..], o.proof_new[proof_start..]);
    opt_replace(p, o, node, inline_body); check_retarget_exits(p, node, inline_body, node); o.inlined += 1;
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
    if kind == N_FLOAT { p.nodes[node].float_value = opt_float_value(p, entry.type_id, entry.float_value); return; }
    if kind == N_FUNCTION || kind == N_FUNCTION_VALUE || kind == N_STRUCT || kind == N_ENUM || kind == N_ALIAS || kind == N_PATTERN { return; }
    if kind == N_NAME && entry.symbol >= 0 {
        opt_fact(o, entry.symbol); let fact: const OptFact& = o.facts[entry.symbol];
        if fact.literal >= 0 && fact.writes == 0 && fact.addresses == 0 {
            let type_id = entry.type_id; opt_replace(p, o, node, fact.literal); p.nodes[node].type_id = type_id; o.propagated += 1;
        }
        return;
    }
    // Inlining can grow the node array. Keep just the traversal fields across child visits.
    let left = entry.left; let right = entry.right;
    let third = entry.third; let first = entry.first;
    let op = entry.integer;
    if kind == N_IF {
        opt_node(p, o, left, depth + 1);
        let condition: const Node& = p.nodes[left];
        if condition.kind == N_BOOL {
            var chosen = third; if condition.integer != 0 { chosen = right; }
            if chosen >= 0 { opt_node(p, o, chosen, depth + 1); opt_replace(p, o, node, chosen); }
            else { opt_empty(p, node); }
            o.folded += 1; return;
        }
    } else if kind == N_BINARY && (op == T_ANDAND || op == T_OROR) {
        opt_node(p, o, left, depth + 1); let value: const Node& = p.nodes[left];
        if value.kind == N_BOOL {
            if op == T_ANDAND && value.integer == 0 || op == T_OROR && value.integer != 0 {
                opt_replace(p, o, node, left); o.folded += 1; return;
            }
            opt_node(p, o, right, depth + 1); opt_replace(p, o, node, right); o.folded += 1; return;
        }
    }
    var child = first;
    while child >= 0 { let next = p.nodes[child].next; opt_node(p, o, child, depth + 1); child = next; }
    if left >= 0 && kind != N_VARIABLE && kind != N_PARAM && kind != N_FIELD && kind != N_RECORD &&
       kind != N_ASSIGN && kind != N_MULTI_ASSIGN {
        opt_node(p, o, left, depth + 1);
    } else if kind == N_ASSIGN {
        let target: const Node& = p.nodes[left];
        if target.kind == N_INDEX { opt_node(p, o, target.right, depth + 1); }
    }
    if right >= 0 { opt_node(p, o, right, depth + 1); }
    if third >= 0 && kind != N_CALL { opt_node(p, o, third, depth + 1); }
    let n: const Node& = p.nodes[node];
    if n.kind == N_VARIABLE && n.symbol >= 0 && n.first < 0 {
        opt_fact(o, n.symbol); let fact: const OptFact& = o.facts[n.symbol];
        if fact.writes == 0 && fact.addresses == 0 && opt_literal(p, n.right) {
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
    let n = p.nodes[node]; var changed = 0;
    if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE { return 0; }
    if n.kind == N_RETURN && n.symbol == function_symbol && n.first >= 0 && p.nodes[n.first].next < 0 {
        let call = p.nodes[n.first];
        if call.kind == N_CALL && call.symbol == function_symbol && (call.flags & F_DISPATCH) == 0 {
            let function_node = p.symbols[function_symbol].node;
            let inline_body = new_node(p, N_BLOCK, n.token); p.nodes[inline_body].type_id = TYPE_VOID;
            p.nodes[inline_body].flags = F_CHECKED; p.nodes[inline_body].scope = n.scope;
            var temp_count = 0; var formal = p.nodes[function_node].first; var argument = call.first;
            while formal >= 0 && argument >= 0 {
                let next = p.nodes[argument].next; p.nodes[argument].next = -1;
                let temp = opt_temporary(p, o, function_node, n.scope, p.nodes[formal].token, p.nodes[formal].type_id, argument);
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
                let assign = new_node(p, N_ASSIGN, n.token);
                p.nodes[assign].left = left; p.nodes[assign].right = right; p.nodes[assign].integer = T_ASSIGN;
                p.nodes[assign].type_id = TYPE_VOID; p.nodes[assign].flags = F_CHECKED;
                append_child(p, inline_body, assign); formal = p.nodes[formal].next; temp = next_temp;
            }
            let jump = new_node(p, N_CONTINUE, n.token); p.nodes[jump].symbol = loop_node;
            p.nodes[jump].type_id = TYPE_VOID; p.nodes[jump].flags = F_CHECKED;
            append_child(p, inline_body, jump); opt_replace(p, o, node, inline_body); return 1;
        }
    }
    var child = n.first;
    while child >= 0 { changed += opt_tail_rewrite(p, o, child, function_symbol, loop_node); child = p.nodes[child].next; }
    changed += opt_tail_rewrite(p, o, n.left, function_symbol, loop_node);
    changed += opt_tail_rewrite(p, o, n.right, function_symbol, loop_node);
    changed += opt_tail_rewrite(p, o, n.third, function_symbol, loop_node);
    return changed;
}
// Whether the tree holds a `defer` (§6.6, upstream HasDefer). Its body runs
// once the call returns, after the self-call a tail loop would replace.
recursive fn opt_has_defer(p: Program&, node: i64) -> bool {
    if node < 0 { return false; }
    let n: const Node& = p.nodes[node];
    if n.kind == N_DEFER { return true; }
    if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE { return false; }
    var child = n.first;
    while child >= 0 { if opt_has_defer(p, child) { return true; } child = p.nodes[child].next; }
    return opt_has_defer(p, n.left) || opt_has_defer(p, n.right) || opt_has_defer(p, n.third);
}
fn opt_tail_function(p: Program&, o: Optimizer&, node: i64) {
    let n = p.nodes[node];
    if p.optimization < 1 || (n.flags & (F_CAPTURE | F_NONLOCAL)) != 0 || n.right < 0 { return; }
    var formal = n.first;
    while formal >= 0 {
        let ty = p.nodes[formal].type_id;
        if ty < 0 || !check_numeric(ty) && ty != TYPE_BOOL { return; }
        formal = p.nodes[formal].next;
    }
    if opt_has_defer(p, n.right) { return; }
    let loop_node = new_node(p, N_LOOP, n.token); p.nodes[loop_node].type_id = TYPE_VOID;
    p.nodes[loop_node].flags = F_CHECKED; p.nodes[loop_node].right = n.right; p.nodes[loop_node].scope = n.scope;
    let changed = opt_tail_rewrite(p, o, n.right, n.symbol, loop_node);
    if changed == 0 { return; }
    let body = new_node(p, N_BLOCK, n.token); p.nodes[body].type_id = TYPE_VOID;
    p.nodes[body].flags = F_CHECKED; p.nodes[body].scope = n.scope; append_child(p, body, loop_node);
    p.nodes[node].right = body; o.tail_loops += changed;
}
recursive fn opt_callees(p: Program&, o: Optimizer&, node: i64) {
    if node < 0 { return; }
    let n = p.nodes[node];
    if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE { return; }
    if n.kind == N_CALL && n.symbol >= 0 {
        let s = p.symbols[n.symbol]; if (s.flags & S_BUILTIN) == 0 && s.node >= 0 { opt_function(p, o, s.node); }
    }
    var child = n.first;
    while child >= 0 { opt_callees(p, o, child); child = p.nodes[child].next; }
    if n.kind != N_RECORD && n.kind != N_VARIABLE { opt_callees(p, o, n.left); }
    opt_callees(p, o, n.right); opt_callees(p, o, n.third);
}
// Lightweight intra-procedural bounds proof: marks N_INDEX nodes with
// F_BOUNDS_PROVEN when dominated by `for i in lo..arr.len` (lo >= 0),
// `if i >= 0 && i < arr.len`, or `i >= 0 && i < arr.len && ...` and neither
// the index nor the array's length can change in the guarded subtree.

fn opt_array_path(p: Program&, o: Optimizer&, node: i64) -> OptArrayPath {
    if node < 0 { return OptArrayPath {}; }
    let n: const Node& = p.nodes[node];
    if n.kind == N_NAME && n.symbol >= 0 {
        let s: const Symbol& = p.symbols[n.symbol];
        let imm_slice = (s.flags & (S_MUTABLE | S_GLOBAL)) == 0 &&
            s.type_id >= 0 && p.types[s.type_id].kind == TY_SLICE &&
            n.symbol < o.facts.len && o.facts[n.symbol].writes == 0 && o.facts[n.symbol].addresses == 0;
        return OptArrayPath { sym: n.symbol, field: -1, immutable_slice: imm_slice };
    }
    if n.kind == N_MEMBER && n.symbol >= 0 && n.left >= 0 && p.nodes[n.left].kind == N_NAME && p.nodes[n.left].symbol >= 0 {
        let base_sym = p.nodes[n.left].symbol;
        let base_ty = p.symbols[base_sym].type_id;
        // Require the base binding itself not to be reassigned in this function.
        if base_sym < o.facts.len && o.facts[base_sym].writes == 0 && o.facts[base_sym].addresses == 0 &&
           (p.symbols[base_sym].flags & S_GLOBAL) == 0 && base_ty >= 0 {
            return OptArrayPath { sym: base_sym, field: n.symbol, immutable_slice: false };
        }
    }
    return OptArrayPath {};
}

fn opt_len_target(p: Program&, o: Optimizer&, node: i64) -> OptArrayPath {
    if node < 0 { return OptArrayPath {}; }
    let n: const Node& = p.nodes[node];
    if n.kind == N_CALL && n.symbol >= 0 && (p.symbols[n.symbol].flags & S_BUILTIN) != 0 &&
       p.symbols[n.symbol].index == 21 && n.first >= 0 && p.nodes[n.first].next < 0 {
        return opt_array_path(p, o, n.first);
    }
    if n.kind == N_MEMBER && n.symbol < 0 && token_is(p, n.token, "len") {
        return opt_array_path(p, o, n.left);
    }
    return OptArrayPath {};
}

fn opt_nonneg_expr(p: Program&, node: i64) -> bool {
    if node < 0 { return false; }
    let n: const Node& = p.nodes[node];
    if n.kind == N_INTEGER && n.integer >= 0 { return true; }
    if n.type_id >= 0 && p.types[n.type_id].kind == TY_INT && (p.types[n.type_id].flags & TF_UNSIGNED) != 0 { return true; }
    return false;
}

fn opt_index_safe(p: Program&, o: Optimizer&, sym: i64) -> bool {
    if sym < 0 || sym >= p.symbols.len { return false; }
    if (p.symbols[sym].flags & (S_GLOBAL | S_CAPTURE)) != 0 { return false; }
    return sym < o.facts.len && o.facts[sym].addresses == 0;
}

fn opt_may_contain_array(p: Program&, ty: i64) -> bool {
    if ty < 0 || ty >= p.types.len { return true; }
    let k = p.types[ty].kind;
    return k == TY_ARRAY || k == TY_SLICE || k == TY_STRUCT || k == TY_REF || k == TY_ENUM;
}

recursive fn opt_subtree_safe_for_bound(p: Program&, node: i64, index_sym: i64, arr: OptArrayPath) -> bool {
    if node < 0 { return true; }
    let n: const Node& = p.nodes[node];
    let kind = n.kind;
    if kind == N_FUNCTION || kind == N_FUNCTION_VALUE { return true; }
    if kind == N_ASSIGN || kind == N_MULTI_ASSIGN {
        var target = n.left; if kind == N_MULTI_ASSIGN { target = n.first; }
        while target >= 0 {
            let tn: const Node& = p.nodes[target];
            if tn.kind == N_NAME && tn.symbol == index_sym { return false; }
            if !arr.immutable_slice {
                // Element writes arr[k] = v of scalars cannot change arr.len; direct writes
                // to the array binding, its field, aggregates, refs, or pointers might.
                if tn.kind == N_UNARY && (tn.integer == T_MUL || tn.integer == T_XOR) { return false; }
                if tn.kind == N_NAME && (tn.symbol == arr.sym || tn.symbol >= 0 && p.symbols[tn.symbol].type_id >= 0 && p.types[p.symbols[tn.symbol].type_id].kind == TY_REF) { return false; }
                if tn.kind == N_MEMBER {
                    if arr.field < 0 && check_place_root(p, target) == arr.sym { return false; }
                    if arr.field >= 0 && tn.symbol == arr.field { return false; }
                    if opt_may_contain_array(p, tn.type_id) { return false; }
                }
                if tn.kind == N_INDEX && opt_may_contain_array(p, tn.type_id) { return false; }
            }
            if kind != N_MULTI_ASSIGN { break; }
            target = tn.next;
        }
    } else if kind == N_UNARY && n.integer == T_BITAND {
        let root = check_place_root(p, n.left);
        if root == index_sym || !arr.immutable_slice && root == arr.sym { return false; }
    } else if kind == N_CALL {
        if n.symbol < 0 || (p.symbols[n.symbol].flags & S_BUILTIN) == 0 {
            // Immutable slices cannot change length across calls, and the index_sym
            // is checked against address-taking/writes/globals/captures.
            if !arr.immutable_slice { return false; }
        } else {
            let b = p.symbols[n.symbol].index;
            // Only pure read-only and grow-only builtins cannot shrink arrays.
            if !arr.immutable_slice && b != 21 && b != 22 && b != 24 && b != 25 &&
               b != 3 && b != 4 && b != 5 && b != 6 && b != 38 && b != 39 {
                return false;
            }
        }
    } else if kind == N_NAME && n.symbol == index_sym && (n.flags & F_REFERENCE_CONTEXT) != 0 {
        return false; }
    var child = n.first;
    while child >= 0 {
        if !opt_subtree_safe_for_bound(p, child, index_sym, arr) { return false; }
        child = p.nodes[child].next;
    }
    if kind == N_VARIABLE && n.right >= 0 {
        var extra = p.nodes[n.right].next;
        while extra >= 0 {
            if !opt_subtree_safe_for_bound(p, extra, index_sym, arr) { return false; }
            extra = p.nodes[extra].next;
        }
    } else if kind == N_BREAK && n.left >= 0 {
        var extra = p.nodes[n.left].next;
        while extra >= 0 {
            if !opt_subtree_safe_for_bound(p, extra, index_sym, arr) { return false; }
            extra = p.nodes[extra].next;
        }
    }
    if !opt_subtree_safe_for_bound(p, n.left, index_sym, arr) { return false; }
    if !opt_subtree_safe_for_bound(p, n.right, index_sym, arr) { return false; }
    if !opt_subtree_safe_for_bound(p, n.third, index_sym, arr) { return false; }
    return true;
}

fn opt_match_upper(p: Program&, o: Optimizer&, node: i64, out_idx: i64&, out_arr: OptArrayPath&) -> bool {
    if node < 0 { return false; }
    let n: const Node& = p.nodes[node];
    if n.kind != N_BINARY { return false; }
    if n.integer == T_LT && n.left >= 0 && p.nodes[n.left].kind == N_NAME && p.nodes[n.left].symbol >= 0 {
        let arr = opt_len_target(p, o, n.right);
        if arr.sym >= 0 { out_idx = p.nodes[n.left].symbol; out_arr = arr; return true; }
    }
    if n.integer == T_GT && n.right >= 0 && p.nodes[n.right].kind == N_NAME && p.nodes[n.right].symbol >= 0 {
        let arr = opt_len_target(p, o, n.left);
        if arr.sym >= 0 { out_idx = p.nodes[n.right].symbol; out_arr = arr; return true; }
    }
    return false;
}

fn opt_match_nonneg(p: Program&, node: i64, sym: i64) -> bool {
    if node < 0 { return false; }
    let n: const Node& = p.nodes[node];
    if n.kind != N_BINARY { return false; }
    if n.integer == T_GTEQ && n.left >= 0 && p.nodes[n.left].kind == N_NAME && p.nodes[n.left].symbol == sym &&
       n.right >= 0 && p.nodes[n.right].kind == N_INTEGER && p.nodes[n.right].integer >= 0 { return true; }
    if n.integer == T_GT && n.left >= 0 && p.nodes[n.left].kind == N_NAME && p.nodes[n.left].symbol == sym &&
       n.right >= 0 && p.nodes[n.right].kind == N_INTEGER && p.nodes[n.right].integer >= -1 { return true; }
    if n.integer == T_LTEQ && n.right >= 0 && p.nodes[n.right].kind == N_NAME && p.nodes[n.right].symbol == sym &&
       n.left >= 0 && p.nodes[n.left].kind == N_INTEGER && p.nodes[n.left].integer >= 0 { return true; }
    if n.integer == T_LT && n.right >= 0 && p.nodes[n.right].kind == N_NAME && p.nodes[n.right].symbol == sym &&
       n.left >= 0 && p.nodes[n.left].kind == N_INTEGER && p.nodes[n.left].integer >= -1 { return true; }
    return false;
}

fn opt_guard_safe(p: Program&, o: Optimizer&, subtree: i64, idx_sym: i64, arr: OptArrayPath) -> bool {
    if !opt_index_safe(p, o, idx_sym) { return false; }
    // Immutable slice + immutable local/for-binder index is always safe without walking the subtree.
    if arr.immutable_slice && (p.symbols[idx_sym].flags & S_MUTABLE) == 0 && o.facts[idx_sym].writes == 0 {
        return true;
    }
    return opt_subtree_safe_for_bound(p, subtree, idx_sym, arr);
}

fn opt_put_guard(guards: OptBoundGuard[>..]&, at: i64, g: OptBoundGuard) {
    if at < guards.len { guards[at] = g; } else { guards.push(g); }
}

recursive fn opt_prove_bounds(p: Program&, o: Optimizer&, node: i64, guards: OptBoundGuard[>..]&, glen: i64) {
    if node < 0 { return; }
    let n: const Node& = p.nodes[node];
    let kind = n.kind;
    if kind == N_FUNCTION || kind == N_FUNCTION_VALUE { return; }
    if kind == N_INDEX && (n.flags & F_BOUNDS_PROVEN) == 0 && glen > 0 &&
       n.right >= 0 && p.nodes[n.right].kind == N_NAME && p.nodes[n.right].symbol >= 0 {
        let idx_sym = p.nodes[n.right].symbol;
        let path = opt_array_path(p, o, n.left);
        if path.sym >= 0 {
            for gi in 0..glen {
                let g: const OptBoundGuard& = guards[gi];
                if g.index_sym == idx_sym && g.arr_sym == path.sym && g.arr_field == path.field {
                    p.nodes[node].flags |= F_BOUNDS_PROVEN; break;
                }
            }
        }
    }
    if kind == N_FOR && n.left >= 0 && p.nodes[n.left].kind == N_RANGE && (p.nodes[n.left].flags & F_INCLUSIVE) == 0 &&
       n.first >= 0 && p.nodes[n.first].symbol >= 0 {
        opt_prove_bounds(p, o, n.left, guards, glen);
        let range: const Node& = p.nodes[n.left];
        let idx_sym = p.nodes[n.first].symbol;
        let arr = opt_len_target(p, o, range.right);
        var next_len = glen;
        if arr.sym >= 0 && opt_nonneg_expr(p, range.left) && opt_guard_safe(p, o, n.right, idx_sym, arr) {
            opt_put_guard(guards, next_len, OptBoundGuard { index_sym: idx_sym, arr_sym: arr.sym, arr_field: arr.field });
            next_len++;
        }
        opt_prove_bounds(p, o, n.right, guards, next_len);
        return;
    }
    if kind == N_IF && n.left >= 0 {
        opt_prove_bounds(p, o, n.left, guards, glen);
        var next_len = glen;
        var idx_sym: i64 = -1; var arr = OptArrayPath {};
        let cond: const Node& = p.nodes[n.left];
        if cond.kind == N_BINARY && cond.integer == T_ANDAND {
            if opt_match_upper(p, o, cond.right, idx_sym, arr) && opt_match_nonneg(p, cond.left, idx_sym) ||
               opt_match_upper(p, o, cond.left, idx_sym, arr) && opt_match_nonneg(p, cond.right, idx_sym) {
                if opt_guard_safe(p, o, n.right, idx_sym, arr) {
                    opt_put_guard(guards, next_len, OptBoundGuard { index_sym: idx_sym, arr_sym: arr.sym, arr_field: arr.field });
                    next_len++;
                }
            }
        } else if opt_match_upper(p, o, n.left, idx_sym, arr) {
            let idx_ty = p.symbols[idx_sym].type_id;
            if idx_ty >= 0 && p.types[idx_ty].kind == TY_INT && (p.types[idx_ty].flags & TF_UNSIGNED) != 0 &&
               opt_guard_safe(p, o, n.right, idx_sym, arr) {
                opt_put_guard(guards, next_len, OptBoundGuard { index_sym: idx_sym, arr_sym: arr.sym, arr_field: arr.field });
                next_len++;
            }
        }
        opt_prove_bounds(p, o, n.right, guards, next_len);
        opt_prove_bounds(p, o, n.third, guards, glen);
        return;
    }
    if kind == N_BINARY && n.integer == T_ANDAND && n.left >= 0 && n.right >= 0 {
        opt_prove_bounds(p, o, n.left, guards, glen);
        var next_len = glen;
        var idx_sym: i64 = -1; var arr = OptArrayPath {};
        let cond: const Node& = p.nodes[n.left];
        if cond.kind == N_BINARY && cond.integer == T_ANDAND {
            if opt_match_upper(p, o, cond.right, idx_sym, arr) && opt_match_nonneg(p, cond.left, idx_sym) ||
               opt_match_upper(p, o, cond.left, idx_sym, arr) && opt_match_nonneg(p, cond.right, idx_sym) {
                if opt_guard_safe(p, o, n.right, idx_sym, arr) {
                    opt_put_guard(guards, next_len, OptBoundGuard { index_sym: idx_sym, arr_sym: arr.sym, arr_field: arr.field });
                    next_len++;
                }
            }
        } else if opt_match_upper(p, o, n.left, idx_sym, arr) {
            let idx_ty = p.symbols[idx_sym].type_id;
            if idx_ty >= 0 && p.types[idx_ty].kind == TY_INT && (p.types[idx_ty].flags & TF_UNSIGNED) != 0 &&
               opt_guard_safe(p, o, n.right, idx_sym, arr) {
                opt_put_guard(guards, next_len, OptBoundGuard { index_sym: idx_sym, arr_sym: arr.sym, arr_field: arr.field });
                next_len++;
            }
        }
        opt_prove_bounds(p, o, n.right, guards, next_len);
        return;
    }
    var child = n.first;
    while child >= 0 { opt_prove_bounds(p, o, child, guards, glen); child = p.nodes[child].next; }
    if kind != N_RECORD && kind != N_VARIABLE { opt_prove_bounds(p, o, n.left, guards, glen); }
    opt_prove_bounds(p, o, n.right, guards, glen);
    opt_prove_bounds(p, o, n.third, guards, glen);
}

recursive fn opt_function(p: Program&, o: Optimizer&, node: i64) {
    if node < 0 { return; }
    if node >= o.function_states.len { o.function_states.resize(p.nodes.len, 0); }
    if (o.function_states[node] & (OPT_ACTIVE | OPT_DONE)) != 0 { return; }
    o.function_states[node] = OPT_ACTIVE;
    let body = p.nodes[node].right;
    if body >= 0 {
        let saved = o.current_function; let saved_slot = o.next_slot; let saved_index = o.has_index;
        o.current_function = node; o.next_slot = 0; o.has_index = false;
        if node < o.first_free_slots.len { o.next_slot = o.first_free_slots[node]; }
        opt_node(p, o, body, 0); opt_tail_function(p, o, node);
        if p.optimization >= 2 && o.has_index {
            opt_prove_bounds(p, o, p.nodes[node].right, o.bound_guards, 0);
        }
        o.current_function = saved; o.next_slot = saved_slot; o.has_index = saved_index;
    }
    o.function_states[node] = OPT_DONE;
}
fn optimize_program(p: Program&) {
    if p.diagnostics.len > 0 { return; }
    var optimizer_facts: OptFact[>..] = []; optimizer_facts.resize(p.symbols.len, OptFact {});
    var function_states: u8[>..] = []; function_states.resize(p.nodes.len, 0);
    var optimizer_maps: OptMap[>..] = []; var optimizer_node_maps: OptNodeMap[>..] = [];
    var optimizer_dependencies: i64[>..] = []; var optimizer_proof_old: i64[>..] = []; var optimizer_proof_new: i64[>..] = [];
    var optimizer_bound_guards: OptBoundGuard[>..] = [];
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
    var o = Optimizer { first_free_slots: slots[..], facts: optimizer_facts, function_states: function_states, maps: optimizer_maps, node_maps: optimizer_node_maps, dependency_work: optimizer_dependencies, proof_old: optimizer_proof_old, proof_new: optimizer_proof_new, bound_guards: optimizer_bound_guards, inlined_blocks: optimizer_inlined_blocks };
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
    life_refresh_named_results_for(p, o.inlined_blocks[..]);
}
