import model;

// Aggregate operations lower to ordinary typed functions. Parameters retain
// evaluation order, and the backends share the resulting scalar operations.
fn operation_name(p: Program&, at: i64, prefix: u8[:], unique: bool = true) -> i64 {
    var token = p.tokens[at]; token.kind = T_IDENT; token.start = p.text.len;
    for byte in prefix { p.text.push(byte); }
    if unique {
        var value = p.nodes.len;
        loop { p.text.push(('a' as i64 + value % 26) as u8); value /= 26; if value == 0 { break; } }
    }
    token.end = p.text.len; token.text_start = token.start; token.text_len = token.end - token.start;
    let result = p.tokens.len; p.tokens.push(token); return result;
}
fn operation_type(p: Program&, type_id: i64, token: i64) -> i64 {
    let node = new_node(p, N_TYPE_NAME, token); p.nodes[node].type_id = type_id; return node;
}
fn operation_ident(p: Program&, token: i64) -> i64 { return new_node(p, N_NAME, token); }
fn operation_integer(p: Program&, value: i64, token: i64) -> i64 {
    let node = new_node(p, N_INTEGER, token); p.nodes[node].integer = value; return node;
}
fn operation_bool(p: Program&, value: bool, token: i64) -> i64 {
    let node = new_node(p, N_BOOL, token); if value { p.nodes[node].integer = 1; } return node;
}
fn operation_member(p: Program&, base: i64, field: i64) -> i64 {
    let node = new_node(p, N_MEMBER, field); p.nodes[node].left = operation_ident(p, base); return node;
}
fn operation_index(p: Program&, base: i64, index: i64) -> i64 {
    let node = new_node(p, N_INDEX, base); p.nodes[node].flags = F_SYNTHETIC; p.nodes[node].left = operation_ident(p, base); p.nodes[node].right = operation_ident(p, index); return node;
}
fn operation_binary(p: Program&, op: i64, left: i64, right: i64, token: i64) -> i64 {
    let node = new_node(p, N_BINARY, token); p.nodes[node].left = left; p.nodes[node].right = right; p.nodes[node].integer = op; return node;
}
fn operation_return(p: Program&, body: i64, value: i64, token: i64) {
    let node = new_node(p, N_RETURN, token); append_child(p, node, value); append_child(p, body, node);
}
fn operation_reject_if(p: Program&, body: i64, condition: i64, token: i64) {
    let branch = new_node(p, N_IF, token); p.nodes[branch].left = condition;
    let rejected = new_node(p, N_BLOCK, token); p.nodes[branch].right = rejected;
    operation_return(p, rejected, operation_bool(p, false, token), token); append_child(p, body, branch);
}
fn operation_value_type(p: Program&, type_id: i64) -> i64 {
    var value = type_id; while value >= 0 && p.types[value].kind == TY_REF { value = p.types[value].element; } return value;
}
recursive fn operation_numeric_class(p: Program&, type_id: i64) -> i64 {
    if type_id < 0 { return 0; }
    let t = p.types[type_id];
    if t.kind == TY_INT { if t.storage == 1 || t.index_type >= 0 { return 0; } return 1; }
    if t.kind == TY_FLOAT { return 2; }
    if t.kind == TY_ARRAY { if t.array_kind != A_FIXED { return 0; } return operation_numeric_class(p, t.element); }
    if t.kind != TY_STRUCT || t.pool >= 0 { return 0; }
    var result = -1; var field = t.first;
    while field >= 0 {
        if (p.nodes[field].flags & F_PAD) == 0 {
            let found = operation_numeric_class(p, p.nodes[field].type_id);
            if found == 0 || result >= 0 && found != result { return 0; } result = found;
        }
        field = p.nodes[field].next;
    }
    if result < 0 { return 1; } return result;
}
recursive fn operation_uniform_leaf(p: Program&, type_id: i64) -> i64 {
    let t = p.types[type_id];
    if t.kind == TY_INT || t.kind == TY_FLOAT { return type_id; }
    if t.kind == TY_ARRAY { return operation_uniform_leaf(p, t.element); }
    var result = -1; var field = t.first;
    while field >= 0 {
        if (p.nodes[field].flags & F_PAD) == 0 {
            let leaf = operation_uniform_leaf(p, p.nodes[field].type_id);
            if leaf < 0 { return -1; }
            if result >= 0 && (p.types[result].kind != p.types[leaf].kind || p.types[result].count != p.types[leaf].count || (p.types[result].flags & TF_UNSIGNED) != (p.types[leaf].flags & TF_UNSIGNED)) { return -1; }
            result = leaf;
        }
        field = p.nodes[field].next;
    }
    return result;
}
recursive fn operation_unsigned_leaf(p: Program&, type_id: i64) -> bool {
    let t = p.types[type_id];
    if t.kind == TY_INT { return (t.flags & TF_UNSIGNED) != 0; }
    if t.kind == TY_ARRAY { return operation_unsigned_leaf(p, t.element); }
    if t.kind == TY_STRUCT { var field = t.first; while field >= 0 { if (p.nodes[field].flags & F_PAD) == 0 && operation_unsigned_leaf(p, p.nodes[field].type_id) { return true; } field = p.nodes[field].next; } }
    return false;
}
fn operation_leaf_binary(p: Program&, op: i64, left: i64, right: i64, field_type: i64, token: i64) -> i64 {
    var actual = op;
    if op == T_EQ && p.types[field_type].kind == TY_REF { actual = T_DOTEQ; }
    if right < 0 { let node = new_node(p, N_UNARY, token); p.nodes[node].left = left; p.nodes[node].integer = T_MINUS; return node; }
    return operation_binary(p, actual, left, right, token);
}
fn operation_field_operand(p: Program&, parameter: i64, parameter_type: i64, field: i64) -> i64 {
    if p.types[operation_value_type(p, parameter_type)].kind != TY_STRUCT { return operation_ident(p, parameter); }
    return operation_member(p, parameter, p.nodes[field].token);
}
fn operation_array_operand(p: Program&, parameter: i64, parameter_type: i64, index: i64) -> i64 {
    let kind = p.types[operation_value_type(p, parameter_type)].kind;
    if kind != TY_ARRAY && kind != TY_SLICE { return operation_ident(p, parameter); }
    return operation_index(p, parameter, index);
}
fn operation_record_body(p: Program&, body: i64, result_type: i64, a: i64, b: i64, left_type: i64, right_type: i64, op: i64, token: i64) {
    var result = -1;
    if op == T_EQ { result = operation_bool(p, true, token); }
    else { result = new_node(p, N_RECORD, token); p.nodes[result].left = operation_type(p, result_type, token); }
    var field = p.types[result_type].first;
    while field >= 0 {
        let f = p.nodes[field];
        if (f.flags & F_PAD) == 0 {
            let left = operation_field_operand(p, a, left_type, field); var right = -1;
            if right_type >= 0 { right = operation_field_operand(p, b, right_type, field); }
            let value = operation_leaf_binary(p, op, left, right, f.type_id, token);
            if op == T_EQ { result = operation_binary(p, T_ANDAND, result, value, token); }
            else { let binding = new_node(p, N_BINDING, f.token); p.nodes[binding].right = value; append_child(p, result, binding); }
        }
        field = f.next;
    }
    operation_return(p, body, result, token);
}
fn operation_array_body(p: Program&, body: i64, result_type: i64, a: i64, b: i64, left_type: i64, right_type: i64, op: i64, token: i64) {
    let length = operation_name(p, token, "len", false);
    let index = operation_name(p, token, "__goose_index");
    let result_name = operation_name(p, token, "__goose_result");
    var count = -1; var element = -1;
    if op == T_EQ {
        let left = operation_value_type(p, left_type); element = p.types[left].element;
        let mismatch = operation_binary(p, T_NEQ, operation_member(p, a, length), operation_member(p, b, length), token);
        operation_reject_if(p, body, mismatch, token); count = operation_member(p, a, length);
    } else {
        let array = p.types[result_type]; element = array.element; count = operation_integer(p, array.count, token);
        let variable = new_node(p, N_VARIABLE, result_name); p.nodes[variable].flags = F_VAR;
        p.nodes[variable].left = operation_type(p, result_type, token);
        let default_name = operation_name(p, token, "default", false);
        let callee = operation_ident(p, default_name); let argument = new_node(p, N_TYPE_ARG, token); p.nodes[argument].type_id = result_type; p.nodes[callee].first = argument;
        let value = new_node(p, N_CALL, token); p.nodes[value].left = callee; p.nodes[variable].right = value; append_child(p, body, variable);
    }
    let loop_node = new_node(p, N_FOR, token); p.nodes[loop_node].left = count;
    let binding = new_node(p, N_BINDING, index); append_child(p, loop_node, binding);
    let loop_body = new_node(p, N_BLOCK, token); p.nodes[loop_node].right = loop_body;
    let left = operation_array_operand(p, a, left_type, index); var right = -1;
    if right_type >= 0 { right = operation_array_operand(p, b, right_type, index); }
    let value = operation_leaf_binary(p, op, left, right, element, token);
    if op == T_EQ {
        let unequal = new_node(p, N_UNARY, token); p.nodes[unequal].integer = T_NOT; p.nodes[unequal].left = value;
        operation_reject_if(p, loop_body, unequal, token);
    } else {
        let assign = new_node(p, N_ASSIGN, token); p.nodes[assign].left = operation_index(p, result_name, index); p.nodes[assign].right = value; p.nodes[assign].integer = T_ASSIGN; append_child(p, loop_body, assign);
    }
    append_child(p, body, loop_node);
    if op == T_EQ { operation_return(p, body, operation_bool(p, true, token), token); }
    else { operation_return(p, body, operation_ident(p, result_name), token); }
}
fn operation_enum_body(p: Program&, body: i64, enum_type: i64, a: i64, b: i64, token: i64) {
    let outer = new_node(p, N_MATCH, token); p.nodes[outer].left = operation_ident(p, a);
    var variant = p.types[enum_type].first;
    while variant >= 0 {
        let v = p.nodes[variant]; let left_name = operation_name(p, token, "__goose_left_payload"); let right_name = operation_name(p, token, "__goose_right_payload");
        let arm = new_node(p, N_ARM, v.token); let pattern = new_node(p, N_PATTERN, v.token); p.nodes[arm].left = pattern; append_child(p, pattern, operation_ident(p, v.token));
        if v.first >= 0 { p.nodes[pattern].left = new_node(p, N_BINDING, left_name); }
        let nested = new_node(p, N_MATCH, token); p.nodes[nested].left = operation_ident(p, b); p.nodes[arm].right = nested;
        let same = new_node(p, N_ARM, v.token); let same_pattern = new_node(p, N_PATTERN, v.token); p.nodes[same].left = same_pattern; append_child(p, same_pattern, operation_ident(p, v.token));
        if v.first >= 0 {
            p.nodes[same_pattern].left = new_node(p, N_BINDING, right_name);
            p.nodes[same].right = operation_binary(p, T_EQ, operation_ident(p, left_name), operation_ident(p, right_name), token);
        } else { p.nodes[same].right = operation_bool(p, true, token); }
        append_child(p, nested, same);
        let different = new_node(p, N_ARM, token); let wildcard = new_node(p, N_PATTERN, token); p.nodes[wildcard].flags = F_DEFAULT; p.nodes[different].left = wildcard; p.nodes[different].right = operation_bool(p, false, token); append_child(p, nested, different);
        append_child(p, outer, arm); variant = v.next;
    }
    operation_return(p, body, outer, token);
}
fn operation_function(p: Program&, left_type: i64, right_type: i64, result_type: i64, op: i64, token: i64) -> i64 {
    let name = operation_name(p, token, "__goose_operation"); let a = operation_name(p, token, "__goose_a"); let b = operation_name(p, token, "__goose_b");
    let function_node = new_node(p, N_FUNCTION, name); p.nodes[function_node].flags = F_SYNTHETIC | F_RECURSIVE; p.nodes[function_node].aux = op;
    let parameter = new_node(p, N_PARAM, a); p.nodes[parameter].type_id = left_type; append_child(p, function_node, parameter);
    if right_type >= 0 { let second = new_node(p, N_PARAM, b); p.nodes[second].type_id = right_type; append_child(p, function_node, second); }
    var returned = result_type; if op == T_EQ { returned = TYPE_BOOL; }
    p.nodes[function_node].left = operation_type(p, returned, token);
    let body = new_node(p, N_BLOCK, token); p.nodes[function_node].right = body;
    let t = p.types[result_type];
    if t.kind == TY_ARRAY || t.kind == TY_SLICE { operation_array_body(p, body, result_type, a, b, left_type, right_type, op, token); }
    else if t.kind == TY_ENUM { operation_enum_body(p, body, result_type, a, b, token); }
    else { operation_record_body(p, body, result_type, a, b, left_type, right_type, op, token); }
    return function_node;
}
