import model;
import checker;

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
struct OptMap { from: i64, to: i64 }
struct Optimizer {
    facts: OptFact[>..]&, visited: i64[>..]&, active: i64[>..]&, maps: OptMap[>..]&,
    current_function: i64 = -1, folded: i64 = 0, propagated: i64 = 0,
    inlined: i64 = 0, tail_loops: i64 = 0,
}
fn opt_fact(o: Optimizer&, symbol: i64) {
    while o.facts.len <= symbol { o.facts.push(OptFact {}); }
}
fn opt_literal(p: Program&, node: i64) -> bool {
    if node < 0 { return false; }
    let kind = p.nodes[node].kind;
    return kind == N_INTEGER || kind == N_FLOAT || kind == N_BOOL || kind == N_NULL;
}
fn opt_replace(p: Program&, destination: i64, source: i64) {
    let next = p.nodes[destination].next; let token = p.nodes[destination].token;
    let type_id = p.nodes[destination].type_id; let tail = p.nodes[destination].flags & F_TAIL;
    p.nodes[destination] = p.nodes[source]; p.nodes[destination].next = next; p.nodes[destination].token = token;
    p.nodes[destination].flags |= tail;
    if type_id >= 0 { p.nodes[destination].type_id = type_id; }
}
fn opt_set_integer(p: Program&, node: i64, value: i64, kind: i64) {
    let original = p.nodes[node];
    p.nodes[node] = Node { kind: kind, token: original.token, next: original.next, type_id: original.type_id, integer: value, flags: original.flags | F_CHECKED, scope: original.scope };
}
fn opt_set_float(p: Program&, node: i64, value: f64) {
    let original = p.nodes[node];
    p.nodes[node] = Node { kind: N_FLOAT, token: original.token, next: original.next, type_id: original.type_id, float_value: value, flags: original.flags | F_CHECKED, scope: original.scope };
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
    let n = p.nodes[node];
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
        let s = p.symbols[n.symbol];
        if (s.flags & S_BUILTIN) != 0 && (s.index == 2 || s.index >= 24) && n.first >= 0 {
            let root = check_place_root(p, n.first);
            if root >= 0 { opt_fact(o, root); o.facts[root].writes += 1; }
        }
    }
    var child = n.first;
    while child >= 0 { opt_collect(p, o, child); child = p.nodes[child].next; }
    if n.kind != N_RECORD && n.kind != N_VARIABLE && n.kind != N_PARAM && n.kind != N_FIELD && n.kind != N_CAST {
        opt_collect(p, o, n.left);
    }
    opt_collect(p, o, n.right);
    if n.kind != N_CALL { opt_collect(p, o, n.third); }
}
recursive fn opt_inline_cost(p: Program&, node: i64, owner: i64, budget: i64) -> i64 {
    if node < 0 { return 0; }
    if budget < 0 { return 1000000; }
    let n = p.nodes[node];
    if n.kind == N_RETURN || n.kind == N_BREAK || n.kind == N_CONTINUE || n.kind == N_FUNCTION ||
       n.kind == N_FUNCTION_VALUE || n.kind == N_VARIABLE || n.kind == N_LOOP || n.kind == N_WHILE || n.kind == N_FOR || n.kind == N_CONST_FOR {
        return 1000000;
    }
    if n.kind == N_CALL && n.symbol >= 0 && p.symbols[n.symbol].owner == owner { return 1000000; }
    var result = 1; var child = n.first;
    while child >= 0 { result += opt_inline_cost(p, child, owner, budget - result); child = p.nodes[child].next; }
    result += opt_inline_cost(p, n.left, owner, budget - result);
    result += opt_inline_cost(p, n.right, owner, budget - result);
    result += opt_inline_cost(p, n.third, owner, budget - result);
    return result;
}
recursive fn opt_clone(p: Program&, o: Optimizer&, node: i64, map_start: i64) -> i64 {
    if node < 0 { return -1; }
    var n = p.nodes[node]; let first = n.first; let left = n.left; let right = n.right; let third = n.third;
    n.first = -1; n.last = -1; n.left = -1; n.right = -1; n.third = -1; n.next = -1;
    if n.kind == N_NAME {
        for map_index in map_start..o.maps.len { let binding = o.maps[map_index]; if n.symbol == binding.from { n.symbol = binding.to; } }
    }
    let result = p.nodes.len; p.nodes.push(n);
    // Pattern payload bindings are declarations too. Their copied uses must
    // name storage owned by the caller, just as copied parameters do.
    if n.kind == N_BINDING && n.symbol >= 0 && n.symbol < p.symbols.len && p.symbols[n.symbol].node == node {
        var symbol = p.symbols[n.symbol]; let original_symbol = n.symbol;
        symbol.node = result; symbol.owner = o.current_function; symbol.scope = -2;
        symbol.slot = opt_next_slot(p, o.current_function); symbol.next = -1;
        let id = p.symbols.len; p.symbols.push(symbol); p.nodes[result].symbol = id;
        o.maps.push(OptMap { from: original_symbol, to: id });
    }
    var child = first;
    while child >= 0 { append_child(p, result, opt_clone(p, o, child, map_start)); child = p.nodes[child].next; }
    p.nodes[result].left = opt_clone(p, o, left, map_start);
    p.nodes[result].right = opt_clone(p, o, right, map_start);
    p.nodes[result].third = opt_clone(p, o, third, map_start);
    return result;
}
fn opt_next_slot(p: Program&, owner: i64) -> i64 {
    var result = 0;
    for s in p.symbols { if s.owner == owner && s.slot >= result { result = s.slot + 1; } }
    return result;
}
fn opt_temporary(p: Program&, owner: i64, scope: i64, token: i64, ty: i64, value: i64) -> i64 {
    let node = new_node(p, N_VARIABLE, token);
    let symbol = p.symbols.len; let slot = opt_next_slot(p, owner);
    p.symbols.push(Symbol { name_token: token, type_id: ty, node: node, scope: -2, slot: slot, owner: owner });
    p.nodes[node].symbol = symbol; p.nodes[node].type_id = ty; p.nodes[node].right = value;
    p.nodes[node].scope = scope; p.nodes[node].flags = F_CHECKED;
    return node;
}
recursive fn opt_try_inline(p: Program&, o: Optimizer&, node: i64) -> bool {
    if p.optimization <= 0 || o.current_function < 0 { return false; }
    let call = p.nodes[node];
    if call.symbol < 0 || call.symbol >= p.symbols.len { return false; }
    let symbol = p.symbols[call.symbol];
    if (symbol.flags & (S_BUILTIN | S_EXTERN)) != 0 || symbol.node < 0 { return false; }
    let callee = p.nodes[symbol.node];
    if (callee.flags & (F_RECURSIVE | F_CAPTURE | F_NONLOCAL)) != 0 || callee.right < 0 { return false; }
    for active in o.active { if active == symbol.node { return false; } }
    opt_function(p, o, symbol.node);
    let body = p.nodes[callee.right];
    if body.first < 0 || p.nodes[body.first].next >= 0 { return false; }
    let ret = p.nodes[body.first];
    if ret.kind != N_RETURN || ret.first < 0 || p.nodes[ret.first].next >= 0 { return false; }
    if ret.symbol != call.symbol { return false; }
    var threshold = 8; if p.optimization >= 2 { threshold = 16; }
    opt_fact(o, call.symbol);
    if o.facts[call.symbol].calls == 1 { threshold = 200; }
    let cost = opt_inline_cost(p, ret.first, symbol.node, threshold);
    if cost > threshold { return false; }
    let map_start = o.maps.len;
    let inline_body = new_node(p, N_BLOCK, call.token); p.nodes[inline_body].flags = F_CHECKED | F_TAIL;
    p.nodes[inline_body].type_id = call.type_id; p.nodes[inline_body].scope = call.scope;
    var formal = callee.first; var argument = call.first;
    while formal >= 0 && argument >= 0 {
        let next = p.nodes[argument].next; p.nodes[argument].next = -1;
        let local = opt_temporary(p, o.current_function, call.scope, p.nodes[formal].token,
            p.nodes[formal].type_id, argument);
        append_child(p, inline_body, local);
        o.maps.push(OptMap { from: p.nodes[formal].symbol, to: p.nodes[local].symbol });
        formal = p.nodes[formal].next; argument = next;
    }
    if formal >= 0 || argument >= 0 { return false; }
    let expression = opt_clone(p, o, ret.first, map_start); p.nodes[expression].flags |= F_TAIL;
    append_child(p, inline_body, expression); opt_replace(p, node, inline_body); o.inlined += 1;
    opt_node(p, o, node, 1);
    return true;
}
fn opt_fold_binary(p: Program&, o: Optimizer&, node: i64) {
    let n = p.nodes[node]; let left = p.nodes[n.left]; let right = p.nodes[n.right]; let op = n.integer;
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
        let a = left.float_value; let b = right.float_value; var value = 0.0; var valid = true;
        if op == T_PLUS { value = a + b; } else if op == T_MINUS { value = a - b; }
        else if op == T_MUL { value = a * b; } else if op == T_DIV && b != 0.0 { value = a / b; }
        else { valid = false; }
        if valid && value == value && value > -1.0e308 && value < 1.0e308 {
            if n.type_id == TYPE_F32 { value = (value as! f32) as f64; }
            opt_set_float(p, node, value); o.folded += 1;
        }
    }
}

recursive fn opt_node(p: Program&, o: Optimizer&, node: i64, depth: i64) {
    if node < 0 || depth > 512 { return; }
    var n = p.nodes[node];
    if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE || n.kind == N_STRUCT || n.kind == N_ENUM || n.kind == N_ALIAS { return; }
    if n.kind == N_NAME && n.symbol >= 0 {
        opt_fact(o, n.symbol); let fact = o.facts[n.symbol];
        if fact.literal >= 0 && fact.writes == 0 && fact.addresses == 0 {
            let type_id = n.type_id; opt_replace(p, node, fact.literal); p.nodes[node].type_id = type_id; o.propagated += 1;
        }
        return;
    }
    if n.kind == N_IF {
        opt_node(p, o, n.left, depth + 1);
        let condition = p.nodes[n.left];
        if condition.kind == N_BOOL {
            var chosen = n.third; if condition.integer != 0 { chosen = n.right; }
            if chosen >= 0 { opt_node(p, o, chosen, depth + 1); opt_replace(p, node, chosen); }
            else { opt_empty(p, node); }
            o.folded += 1; return;
        }
    } else if n.kind == N_BINARY && (n.integer == T_ANDAND || n.integer == T_OROR) {
        opt_node(p, o, n.left, depth + 1); let left = p.nodes[n.left];
        if left.kind == N_BOOL {
            if n.integer == T_ANDAND && left.integer == 0 || n.integer == T_OROR && left.integer != 0 {
                opt_replace(p, node, n.left); o.folded += 1; return;
            }
            opt_node(p, o, n.right, depth + 1); opt_replace(p, node, n.right); o.folded += 1; return;
        }
    }
    var child = n.first;
    while child >= 0 { let next = p.nodes[child].next; opt_node(p, o, child, depth + 1); child = next; }
    if n.kind != N_VARIABLE && n.kind != N_PARAM && n.kind != N_FIELD && n.kind != N_RECORD && n.kind != N_CAST &&
       n.kind != N_ASSIGN && n.kind != N_MULTI_ASSIGN {
        opt_node(p, o, n.left, depth + 1);
    } else if n.kind == N_ASSIGN {
        let target = p.nodes[n.left];
        if target.kind == N_INDEX { opt_node(p, o, target.right, depth + 1); }
    }
    opt_node(p, o, n.right, depth + 1);
    if n.kind != N_CALL { opt_node(p, o, n.third, depth + 1); }
    n = p.nodes[node];
    if n.kind == N_VARIABLE && n.symbol >= 0 && n.first < 0 {
        opt_fact(o, n.symbol); let fact = o.facts[n.symbol];
        if fact.writes == 0 && fact.addresses == 0 && opt_literal(p, n.right) {
            o.facts[n.symbol].literal = n.right;
        }
    } else if n.kind == N_BINARY { opt_fold_binary(p, o, node); }
    else if n.kind == N_UNARY && n.left >= 0 {
        let value = p.nodes[n.left];
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
        let source = p.nodes[n.left]; let destination = n.type_id;
        if source.kind == N_INTEGER && check_integer(destination) {
            if (n.flags & F_UNSIGNED) != 0 || source.integer >= check_min(destination) && source.integer <= check_max(destination) &&
               !(check_unsigned(source.type_id) && source.integer < 0 && destination != TYPE_U64) {
                opt_set_integer(p, node, opt_wrap(source.integer as! u64, destination), N_INTEGER); o.folded += 1;
            }
        } else if source.kind == N_FLOAT && check_float(destination) {
            var value = source.float_value; if destination == TYPE_F32 { value = (value as! f32) as f64; }
            opt_set_float(p, node, value); o.folded += 1;
        } else if source.kind == N_INTEGER && check_float(destination) {
            var value = source.integer as f64;
            if check_unsigned(source.type_id) { value = (source.integer as! u64) as f64; }
            if destination == TYPE_F32 { value = (value as! f32) as f64; }
            opt_set_float(p, node, value); o.folded += 1;
        }
    } else if n.kind == N_CALL && n.symbol >= 0 {
        let symbol = p.symbols[n.symbol];
        if (symbol.flags & S_BUILTIN) != 0 && symbol.index == 21 && n.first >= 0 {
            let receiver = p.nodes[n.first]; var length = -1;
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
        let range = p.nodes[n.left];
        if p.nodes[range.left].kind == N_INTEGER && p.nodes[range.right].kind == N_INTEGER &&
           p.nodes[range.left].integer >= p.nodes[range.right].integer && (range.flags & F_INCLUSIVE) == 0 {
            opt_empty(p, node); o.folded += 1;
        }
    } else if n.kind == N_INDEX && n.right >= 0 {
        let index = p.nodes[n.right]; let source = p.nodes[n.left];
        if index.kind == N_INTEGER && index.integer >= 0 && source.type_id >= 0 &&
           p.types[source.type_id].kind == TY_ARRAY && p.types[source.type_id].array_kind == A_FIXED &&
           index.integer < p.types[source.type_id].count { p.nodes[node].flags |= F_BOUNDS_PROVEN; }
    }
    if n.kind == N_BLOCK {
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
                    let s = p.symbols[p.nodes[current].symbol];
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
        if call.kind == N_CALL && call.symbol == function_symbol {
            let function_node = p.symbols[function_symbol].node;
            let inline_body = new_node(p, N_BLOCK, n.token); p.nodes[inline_body].type_id = TYPE_VOID;
            p.nodes[inline_body].flags = F_CHECKED; p.nodes[inline_body].scope = n.scope;
            var temp_count = 0; var formal = p.nodes[function_node].first; var argument = call.first;
            while formal >= 0 && argument >= 0 {
                let next = p.nodes[argument].next; p.nodes[argument].next = -1;
                let temp = opt_temporary(p, function_node, n.scope, p.nodes[formal].token, p.nodes[formal].type_id, argument);
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
            append_child(p, inline_body, jump); opt_replace(p, node, inline_body); return 1;
        }
    }
    var child = n.first;
    while child >= 0 { changed += opt_tail_rewrite(p, o, child, function_symbol, loop_node); child = p.nodes[child].next; }
    changed += opt_tail_rewrite(p, o, n.left, function_symbol, loop_node);
    changed += opt_tail_rewrite(p, o, n.right, function_symbol, loop_node);
    changed += opt_tail_rewrite(p, o, n.third, function_symbol, loop_node);
    return changed;
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
    if n.kind != N_RECORD && n.kind != N_VARIABLE && n.kind != N_CAST { opt_callees(p, o, n.left); }
    opt_callees(p, o, n.right); opt_callees(p, o, n.third);
}
recursive fn opt_function(p: Program&, o: Optimizer&, node: i64) {
    if node < 0 { return; }
    for visited in o.visited { if visited == node { return; } }
    for active in o.active { if active == node { return; } }
    o.active.push(node);
    let n = p.nodes[node];
    if n.right >= 0 {
        opt_callees(p, o, n.right);
        let saved = o.current_function; o.current_function = node;
        opt_node(p, o, n.right, 0); opt_tail_function(p, o, node);
        o.current_function = saved;
    }
    o.active.pop(); o.visited.push(node);
}
fn optimize_program(p: Program&) {
    if p.diagnostics.len > 0 { return; }
    var optimizer_facts: OptFact[>..] = [];
    var optimizer_visited: i64[>..] = [];
    var optimizer_active: i64[>..] = [];
    var optimizer_maps: OptMap[>..] = [];
    var o = Optimizer { facts: optimizer_facts, visited: optimizer_visited, active: optimizer_active, maps: optimizer_maps };
    for symbol, id in p.symbols { opt_fact(o, id); }
    let count = p.symbols.len;
    for i in 0..count {
        let s = p.symbols[i]; if s.node < 0 { continue; }
        if (s.flags & S_GLOBAL) != 0 { opt_collect(p, o, s.node); }
        if (s.flags & S_FUNCTION) != 0 && (s.flags & S_BUILTIN) == 0 && (p.nodes[s.node].flags & F_REACHABLE) != 0 {
            opt_collect(p, o, p.nodes[s.node].right);
        }
    }
    for i in 0..count {
        let s = p.symbols[i]; if s.node >= 0 && (s.flags & S_GLOBAL) != 0 { opt_node(p, o, s.node, 0); }
    }
    for i in 0..count {
        let s = p.symbols[i];
        if s.node >= 0 && (s.flags & S_FUNCTION) != 0 && (s.flags & S_BUILTIN) == 0 &&
           (p.nodes[s.node].flags & F_REACHABLE) != 0 { opt_function(p, o, s.node); }
    }
}
