import model;

struct ExpansionBinding {
    token: i64 = -1, id: i64 = -1,
    accessor: bool = false, type_name: bool = false,
}

fn expansion_find(p: Program&, bindings: ExpansionBinding[:], token: i64, type_name: bool = false) -> ExpansionBinding {
    if token < 0 { return ExpansionBinding {}; }
    var i = bindings.len;
    while i > 0 {
        i--;
        let b = bindings[i];
        var matches = false;
        if b.token < 0 { matches = token_is(p, token, "it"); }
        else { matches = same_name(p, b.token, token); }
        if matches && (!type_name || b.type_name) { return b; }
    }
    return ExpansionBinding {};
}

fn expansion_hide(bindings: ExpansionBinding[>..]&, token: i64, type_name: bool = false) {
    bindings.push(ExpansionBinding { token: token, type_name: type_name });
}

recursive fn expansion_list(p: Program&, first: i64, bindings: ExpansionBinding[>..]&) {
    var child = first;
    while child >= 0 { expansion_walk(p, child, bindings); child = p.nodes[child].next; }
}

recursive fn expansion_walk(p: Program&, node: i64, bindings: ExpansionBinding[>..]&) {
    if node < 0 { return; }
    let n = p.nodes[node];
    if n.kind == N_IMPORT { return; }
    if n.kind == N_TYPE_NAME {
        if n.left < 0 { p.nodes[node].expansion_binding = expansion_find(p, bindings, n.token, true).id; }
        else { expansion_walk(p, n.left, bindings); }
        expansion_list(p, n.first, bindings); return;
    }
    if n.kind == N_TYPE_REF {
        expansion_walk(p, n.left, bindings); return;
    }
    if n.kind == N_CONST_FOR {
        expansion_list(p, n.left, bindings);
        let mark = bindings.len; var binder = n.first; var ordinal = 0;
        while binder >= 0 {
            p.nodes[binder].expansion_binding = binder;
            bindings.push(ExpansionBinding { token: p.nodes[binder].token, id: binder,
                accessor: n.integer == 1 && ordinal == 1, type_name: true });
            ordinal++; binder = p.nodes[binder].next;
        }
        expansion_walk(p, n.right, bindings); bindings.resize(mark); return;
    }
    if n.kind == N_BLOCK {
        let mark = bindings.len; var child = n.first;
        while child >= 0 {
            expansion_walk(p, child, bindings); let statement = p.nodes[child];
            if statement.kind == N_VARIABLE {
                if statement.first < 0 { expansion_hide(bindings, statement.token); }
                else {
                    var binding = statement.first;
                    while binding >= 0 { expansion_hide(bindings, p.nodes[binding].token); binding = p.nodes[binding].next; }
                }
            } else if statement.kind == N_FUNCTION { expansion_hide(bindings, statement.token); }
            child = statement.next;
        }
        bindings.resize(mark); return;
    }
    if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE {
        let mark = bindings.len;
        if n.kind == N_FUNCTION { expansion_hide(bindings, n.token); }
        else if (n.flags & F_EXPLICIT_PARAMS) == 0 { expansion_hide(bindings, -1); }
        var generic = n.third;
        while generic >= 0 { expansion_hide(bindings, p.nodes[generic].token, true); generic = p.nodes[generic].next; }
        generic = n.third;
        while generic >= 0 { expansion_walk(p, p.nodes[generic].left, bindings); generic = p.nodes[generic].next; }
        var param = n.first;
        while param >= 0 { expansion_hide(bindings, p.nodes[param].token); param = p.nodes[param].next; }
        param = n.first;
        while param >= 0 {
            expansion_walk(p, p.nodes[param].left, bindings); expansion_walk(p, p.nodes[param].right, bindings);
            param = p.nodes[param].next;
        }
        expansion_list(p, n.left, bindings); expansion_walk(p, n.right, bindings);
        bindings.resize(mark); return;
    }
    if n.kind == N_FOR {
        var binding = n.first;
        while binding >= 0 { expansion_walk(p, p.nodes[binding].left, bindings); binding = p.nodes[binding].next; }
        expansion_walk(p, n.left, bindings);
        let mark = bindings.len; binding = n.first;
        while binding >= 0 { expansion_hide(bindings, p.nodes[binding].token); binding = p.nodes[binding].next; }
        expansion_walk(p, n.right, bindings); bindings.resize(mark); return;
    }
    if n.kind == N_ARM {
        expansion_walk(p, n.left, bindings);
        let mark = bindings.len;
        if n.left >= 0 && p.nodes[n.left].left >= 0 { expansion_hide(bindings, p.nodes[p.nodes[n.left].left].token); }
        expansion_walk(p, n.third, bindings); expansion_walk(p, n.right, bindings);
        bindings.resize(mark); return;
    }
    if n.kind == N_PATTERN {
        expansion_list(p, n.first, bindings); return;
    }
    if n.kind == N_RECORD {
        expansion_walk(p, n.left, bindings);
        var child = n.first;
        while child >= 0 {
            let binding = p.nodes[child];
            if binding.kind == N_BINDING {
                let lexical = expansion_find(p, bindings, binding.token);
                if lexical.accessor { p.nodes[child].expansion_binding = lexical.id; }
                expansion_walk(p, binding.right, bindings);
            } else { expansion_walk(p, child, bindings); }
            child = binding.next;
        }
        return;
    }
    if n.kind == N_NAME { p.nodes[node].expansion_binding = expansion_find(p, bindings, n.token).id; }
    else if n.kind == N_MEMBER {
        let lexical = expansion_find(p, bindings, n.token);
        if lexical.accessor { p.nodes[node].expansion_binding = lexical.id; }
    }
    expansion_list(p, n.first, bindings);
    expansion_walk(p, n.left, bindings); expansion_walk(p, n.right, bindings); expansion_walk(p, n.third, bindings);
}

fn bind_expansion_names(p: Program&, module: i64) {
    var bindings: ExpansionBinding[>..] = [];
    expansion_list(p, p.nodes[module].first, bindings);
}
