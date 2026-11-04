import model;

// Checked-node invariants are independent of overload selection and flow joins.
recursive fn validation_size_class(p: Program&, type_id: i64, depth: i64 = 0) -> i64 {
    if type_id < 0 || depth > 64 { return 0; }
    let t = p.types[type_id];
    if t.kind == TY_ENUM && (t.flags & F_VARIABLE_MODE) == 0 { return 0; }
    if t.storage == 1 { return 1; }
    if t.kind == TY_ARRAY {
        if t.array_kind == A_GROW || t.array_kind == A_GROWSHRINK { return 2; }
        if t.array_kind == A_VAR || t.array_kind == A_LIMITED && t.count < 0 { return 1; }
        return validation_size_class(p, t.element, depth + 1);
    }
    var result = 0;
    if t.kind == TY_STRUCT || t.kind == TY_ENUM {
        var field = t.first;
        while field >= 0 {
            let size_class = validation_size_class(p, p.nodes[field].type_id, depth + 1);
            if size_class > result { result = size_class; }
            field = p.nodes[field].next;
        }
    }
    return result;
}
fn validation_optional(p: Program&, node: i64) -> bool {
    if node < 0 || p.nodes[node].type_id < 0 { return false; }
    let t = p.types[p.nodes[node].type_id];
    return t.kind == TY_REF && (t.flags & TF_OPTIONAL) != 0;
}
fn validation_builtin(p: Program&, node: i64, index: i64) -> bool {
    if node < 0 || p.nodes[node].kind != N_CALL { return false; }
    let symbol = p.nodes[node].symbol;
    return symbol >= 0 && (p.symbols[symbol].flags & S_BUILTIN) != 0 && p.symbols[symbol].index == index;
}
fn validation_storage_value(p: Program&, node: i64) -> bool {
    if node < 0 || p.nodes[node].type_id < 0 { return false; }
    if validation_builtin(p, node, 15) { return false; }
    let n = p.nodes[node]; var type_id = n.type_id;
    if p.types[type_id].kind == TY_REF {
        type_id = p.types[type_id].element;
        return validation_size_class(p, type_id) > 0;
    }
    if n.kind == N_NAME || n.kind == N_MEMBER || n.kind == N_INDEX ||
       n.kind == N_UNARY && n.integer == T_MUL {
        return validation_size_class(p, type_id) > 0;
    }
    return false;
}
recursive fn validation_contains_binding(p: Program&, node: i64, symbol: i64, depth: i64 = 0) -> bool {
    if node < 0 || depth > 128 { return false; }
    let n = p.nodes[node];
    if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE || n.kind == N_IMPORT { return false; }
    if n.kind == N_VARIABLE && n.symbol == symbol { return true; }
    var child = n.first;
    while child >= 0 {
        if p.nodes[child].symbol == symbol && n.kind == N_VARIABLE { return true; }
        if validation_contains_binding(p, child, symbol, depth + 1) { return true; }
        child = p.nodes[child].next;
    }
    return validation_contains_binding(p, n.left, symbol, depth + 1) ||
        validation_contains_binding(p, n.right, symbol, depth + 1) ||
        validation_contains_binding(p, n.third, symbol, depth + 1);
}
fn validation_fresh_local(p: Program&, expression: i64, owner: i64) -> bool {
    let n = p.nodes[expression];
    if n.kind != N_NAME || n.symbol < 0 { return false; }
    let s = p.symbols[n.symbol];
    if s.type_id < 0 || p.types[s.type_id].kind == TY_REF || (s.flags & (S_PARAMETER | S_GLOBAL)) != 0 { return false; }
    return validation_contains_binding(p, owner, n.symbol);
}
fn validation_control_value(p: Program&, expression: i64, owner: i64) {
    if expression < 0 || owner < 0 || (p.nodes[owner].flags & F_REFERENCE_CONTEXT) != 0 { return; }
    if validation_storage_value(p, expression) && !validation_fresh_local(p, expression, owner) {
        diagnose(p, p.nodes[expression].token, "non-fixed storage requires explicit copy in a control-flow value");
    }
}

struct ValidationRoot { symbol: i64 = -1, path: u64 = 0 }
recursive fn validation_root(p: Program&, node: i64, depth: i64 = 0) -> ValidationRoot {
    if node < 0 || depth > 64 { return ValidationRoot {}; }
    let n = p.nodes[node];
    if n.kind == N_UNARY && (n.integer == T_BITAND || n.integer == T_MUL) {
        return validation_root(p, n.left, depth + 1);
    }
    if n.kind == N_SLICE { return validation_root(p, n.left, depth + 1); }
    if n.kind == N_NAME && n.symbol >= 0 {
        let symbol = p.symbols[n.symbol];
        if symbol.type_id < 0 { return ValidationRoot {}; }
        let t = p.types[symbol.type_id];
        if t.kind == TY_REF || t.kind == TY_SLICE {
            if (symbol.flags & (S_PARAMETER | S_MUTABLE)) != 0 || symbol.node < 0 { return ValidationRoot {}; }
            if p.nodes[symbol.node].kind == N_VARIABLE {
                return validation_root(p, p.nodes[symbol.node].right, depth + 1);
            }
            return ValidationRoot {};
        }
        return ValidationRoot { symbol: n.symbol };
    }
    if n.kind == N_MEMBER && n.symbol >= 0 && n.type_id >= 0 {
        if p.types[n.type_id].kind == TY_REF { return ValidationRoot {}; }
        var root = validation_root(p, n.left, depth + 1);
        root.path = root.path * 1099511628211 + (p.nodes[n.symbol].token + 1) as u64;
        return root;
    }
    return ValidationRoot {};
}
recursive fn validation_element_owner(p: Program&, node: i64, depth: i64 = 0) -> ValidationRoot {
    if node < 0 || depth > 64 { return ValidationRoot {}; }
    let n = p.nodes[node];
    if n.kind == N_UNARY && (n.integer == T_BITAND || n.integer == T_MUL) {
        return validation_element_owner(p, n.left, depth + 1);
    }
    if n.kind == N_INDEX { return validation_root(p, n.left); }
    if n.kind == N_NAME && n.symbol >= 0 {
        let symbol = p.symbols[n.symbol];
        if symbol.type_id >= 0 && p.types[symbol.type_id].kind == TY_REF &&
           (symbol.flags & (S_PARAMETER | S_MUTABLE)) == 0 && symbol.node >= 0 &&
           p.nodes[symbol.node].kind == N_VARIABLE {
            return validation_element_owner(p, p.nodes[symbol.node].right, depth + 1);
        }
    }
    return ValidationRoot {};
}
fn validation_index_of(p: Program&, node: i64) {
    let receiver = p.nodes[node].first;
    if receiver < 0 { return; }
    let argument = p.nodes[receiver].next;
    if argument < 0 { return; }
    let array = validation_root(p, receiver); let owner = validation_element_owner(p, argument);
    if array.symbol >= 0 && owner.symbol >= 0 &&
       (array.symbol != owner.symbol || array.path != owner.path) {
        diagnose(p, p.nodes[argument].token, "index_of requires an element of the receiver array");
    }
}
fn validation_array_length(p: Program&, node: i64) {
    let n = p.nodes[node]; let t = p.types[n.type_id];
    if t.kind != TY_ARRAY || t.array_kind != A_VAR && t.array_kind != A_LIMITED ||
       t.length_storage < 1 || t.length_storage > 4 { return; }
    var count = 0;
    if n.right >= 0 {
        if p.nodes[n.right].kind != N_INTEGER { return; }
        count = p.nodes[n.right].integer;
    } else {
        var child = n.first;
        while child >= 0 { count += 1; child = p.nodes[child].next; }
    }
    let maximum = (1 as i64 << (t.length_storage * 8)) - 1;
    if count > maximum { diagnose(p, n.token, "array length exceeds storage range"); }
}
fn check_validate_program(p: Program&) {
    let count = p.nodes.len;
    for node in 0..count {
        let n = p.nodes[node];
        if (n.flags & F_CHECKED) == 0 || n.type_id < 0 { continue; }
        if n.kind == N_BINARY {
            var inspect = true;
            if n.integer == T_DOTEQ || n.integer == T_DOTNEQ || n.integer == T_ANDAND || n.integer == T_OROR { inspect = false; }
            if (n.integer == T_EQ || n.integer == T_NEQ) && n.left >= 0 && n.right >= 0 &&
               (p.nodes[n.left].kind == N_NULL || p.nodes[n.right].kind == N_NULL) { inspect = false; }
            if inspect && (validation_optional(p, n.left) || validation_optional(p, n.right)) {
                diagnose(p, n.token, "optional reference must be narrowed before a value operation");
            }
        } else if n.kind == N_UNARY {
            if (n.integer == T_MUL || n.integer == T_MINUS || n.integer == T_BITNOT ||
                n.integer == T_INC || n.integer == T_DEC) && validation_optional(p, n.left) {
                diagnose(p, n.token, "optional reference must be narrowed before dereferencing");
            }
        } else if n.kind == N_MEMBER || n.kind == N_INDEX || n.kind == N_SLICE {
            if validation_optional(p, n.left) { diagnose(p, n.token, "optional reference must be narrowed before access"); }
        }
        if n.kind == N_BLOCK && n.last >= 0 && (p.nodes[n.last].flags & F_TAIL) != 0 &&
           p.nodes[n.last].kind != N_RETURN {
            validation_control_value(p, n.last, node);
        } else if n.kind == N_MATCH {
            var arm = n.first;
            while arm >= 0 { validation_control_value(p, p.nodes[arm].right, node); arm = p.nodes[arm].next; }
        } else if n.kind == N_BREAK && n.symbol >= 0 {
            validation_control_value(p, n.left, n.symbol);
        }
        if (n.kind == N_VARIABLE || n.kind == N_FIELD) && p.types[n.type_id].kind == TY_FN {
            diagnose(p, n.token, "function values cannot be stored");
        }
        if n.kind == N_RETURN {
            var value = n.first;
            while value >= 0 {
                let type_id = p.nodes[value].type_id;
                if type_id >= 0 && p.types[type_id].kind == TY_FN { diagnose(p, n.token, "function values cannot be returned"); }
                value = p.nodes[value].next;
            }
        }
        if validation_builtin(p, node, 23) { validation_index_of(p, node); }
        if n.kind == N_ARRAY || n.kind == N_FILL { validation_array_length(p, node); }
    }
    for t in p.types {
        if t.kind != TY_STRUCT { continue; }
        var field = t.first;
        while field >= 0 {
            let type_id = p.nodes[field].type_id;
            if type_id >= 0 && p.types[type_id].kind == TY_FN {
                diagnose(p, p.nodes[field].token, "function values cannot be stored in fields");
            }
            field = p.nodes[field].next;
        }
    }
}
