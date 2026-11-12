import model;

// Reachable globals belong to the worker program and its spawned descendants.
fn thread_type_globals(p: Program&, type_id: i64, globals: bool[>..]&, seen: bool[>..]&) {
    if type_id < 0 || type_id >= p.types.len || seen[type_id] { return; }
    var work: i64[>..] = [type_id];
    while work.len > 0 {
        let id = work.pop();
        if id < 0 || id >= p.types.len || seen[id] { continue; }
        seen[id] = true;
        let t = p.types[id];
        if t.pool >= 0 {
            if t.kind == TY_REF || t.kind == TY_INT && t.index_type >= 0 {
                if t.pool < p.symbols.len && (p.symbols[t.pool].flags & S_GLOBAL) != 0 {
                    // A named component belongs to its owner.
                    var named = t.pool; if p.symbols[named].component_owner >= 0 { named = p.symbols[named].component_owner; }
                    globals[named] = true; work.push(p.symbols[named].type_id);
                }
            }
        }
        work.push(t.element);
        var field = t.first;
        while field >= 0 { work.push(p.nodes[field].type_id); field = p.nodes[field].next; }
    }
}

fn thread_globals(p: Program&, function: i64, globals: bool[>..]&) {
    globals.clear();
    globals.resize(p.symbols.len, false);
    var seen: bool[>..] = []; seen.resize(p.nodes.len, false);
    var types_seen: bool[>..] = []; types_seen.resize(p.types.len, false);
    thread_type_globals(p, p.nodes[function].type_id, globals, types_seen);
    var work: i64[>..] = [p.nodes[function].right];
    while work.len > 0 {
        let node = work.pop();
        if node < 0 || node >= p.nodes.len || seen[node] { continue; }
        seen[node] = true;
        let n = p.nodes[node];
        if n.kind == N_FUNCTION || n.kind == N_STRUCT || n.kind == N_ENUM || n.kind == N_ALIAS { continue; }
        thread_type_globals(p, n.type_id, globals, types_seen);
        if (n.kind == N_NAME || n.kind == N_CALL) && n.symbol >= 0 && n.symbol < p.symbols.len {
            let s = p.symbols[n.symbol];
            thread_type_globals(p, s.type_id, globals, types_seen);
            if (s.flags & S_GLOBAL) != 0 { globals[n.symbol] = true; }
            if (s.flags & S_FUNCTION) != 0 && s.node >= 0 { work.push(p.nodes[s.node].right); }
        }
        // A function value may be invoked indirectly. Its checked body and the
        // bodies of matching call targets participate in the program instance.
        if n.kind == N_CALL && n.left >= 0 {
            let callee = p.nodes[n.left];
            if callee.type_id >= 0 && p.types[callee.type_id].kind == TY_FN &&
               (callee.symbol < 0 || (p.symbols[callee.symbol].flags & S_FUNCTION) == 0) {
                for candidate in p.nodes {
                    if (candidate.kind == N_FUNCTION || candidate.kind == N_FUNCTION_VALUE) &&
                       candidate.type_id == callee.type_id && (candidate.flags & F_GENERIC) == 0 {
                        work.push(candidate.right);
                    }
                }
            }
        }
        var child = n.first;
        while child >= 0 { work.push(child); child = p.nodes[child].next; }
        if n.kind != N_VARIABLE && n.kind != N_PARAM && n.kind != N_FIELD && n.kind != N_RECORD { work.push(n.left); }
        work.push(n.right);
        if n.kind == N_CALL && (n.flags & F_DISPATCH) != 0 {
            var arm = n.third;
            while arm >= 0 {
                let selected = p.nodes[arm];
                if selected.symbol >= 0 { work.push(p.nodes[p.symbols[selected.symbol].node].right); }
                arm = selected.next;
            }
        } else if n.kind != N_CALL { work.push(n.third); }
    }
}

