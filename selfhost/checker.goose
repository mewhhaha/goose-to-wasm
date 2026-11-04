import model;

// Stable IDs are the only links held while tables grow. Scope, flow and
// provenance are checker work tables; checked nodes contain backend contracts.
struct CheckScope { parent: i64, function_node: i64, depth: i64 = 0, namespace_node: i64 = -1 }
struct TypeBinding { parameter: i64, value: i64, next: i64 = -1 }
struct CheckList { first: i64 = -1, last: i64 = -1, count: i64 = 0 }
struct CheckSpan { first: i64 = 0, count: i64 = 0 }
struct CheckInteger { value: i64, next: i64 = -1 }
struct CheckVariable {
    symbol: i64, assigned: bool = false, maybeassigned: bool = false,
    root_depth: i64 = -1, readonly: bool = false, narrowed: i64 = -1,
}
struct CheckRoot { value: i64, root: i64 }
struct CheckEffect { function_node: i64, root: i64, kind: i64 }
struct CheckReturnRoot { function_node: i64, index: i64, root: i64 }
struct CheckSpecialization { original: i64, symbol: i64, binding_start: i64, binding_count: i64 }
struct CheckFlow { symbol: i64, assigned: bool, maybeassigned: bool, narrowed: i64 = -1 }
struct CheckLoop { node: i64, scope: i64, function_node: i64, result: i64 = -1, breaks: bool = false }
struct Checker {
    scopes: CheckScope[>..]&, variables: CheckVariable[>..]&,
    roots: CheckRoot[>..]&, effects: CheckEffect[>..]&,
    return_roots: CheckReturnRoot[>..]&,
    specializations: CheckSpecialization[>..]&, bindings: TypeBinding[>..]&,
    checking: i64[>..]&, loop_stack: CheckLoop[>..]&,
    integer_work: CheckInteger[>..]&, binding_work: TypeBinding[>..]&, flow_work: CheckFlow[>..]&, interval_work: CheckInterval[>..]&,
    scope: i64 = 0, function_node: i64 = -1, result_type: i64 = -1,
    next_slot: i64 = 0, reachable: bool = true, signature: bool = false,
    returns: bool = false, inference_depth: i64 = 0,
}

fn check_list_push(c: Checker&, list: CheckList&, value: i64) {
    let id = c.integer_work.len; c.integer_work.push(CheckInteger { value: value });
    if list.last < 0 { list.first = id; } else { c.integer_work[list.last].next = id; }
    list.last = id; list.count += 1;
}
fn check_list_at(c: Checker&, list: CheckList&, index: i64) -> i64 {
    var item = list.first; var at = 0;
    while item >= 0 && at < index { item = c.integer_work[item].next; at += 1; }
    if item < 0 { return -1; }
    return c.integer_work[item].value;
}
fn check_binding_push(c: Checker&, list: CheckList&, value: TypeBinding) {
    let id = c.binding_work.len; c.binding_work.push(value); c.binding_work[id].next = -1;
    if list.last < 0 { list.first = id; } else { c.binding_work[list.last].next = id; }
    list.last = id; list.count += 1;
}
fn check_binding_at(c: Checker&, list: CheckList&, index: i64) -> TypeBinding {
    var item = list.first; var at = 0;
    while item >= 0 && at < index { item = c.binding_work[item].next; at += 1; }
    return c.binding_work[item];
}
fn check_interval_push(c: Checker&, list: CheckList&, value: CheckInterval) {
    let id = c.interval_work.len; c.interval_work.push(value); c.interval_work[id].next = -1;
    if list.last < 0 { list.first = id; } else { c.interval_work[list.last].next = id; }
    list.last = id; list.count += 1;
}
fn check_interval_at(c: Checker&, list: CheckList&, index: i64) -> CheckInterval {
    var item = list.first; var at = 0;
    while item >= 0 && at < index { item = c.interval_work[item].next; at += 1; }
    return c.interval_work[item];
}

fn check_enter(c: Checker&, function_node: i64) -> i64 {
    let saved = c.scope;
    let id = c.scopes.len;
    c.scopes.push(CheckScope { parent: saved, function_node: function_node,
        depth: c.scopes[saved].depth + 1 });
    c.scope = id;
    return saved;
}
fn check_visible(c: Checker&, declaration_scope: i64, use_scope: i64) -> bool {
    var scope = use_scope;
    loop {
        if scope == declaration_scope { return true; }
        if scope <= 0 { return false; }
        scope = c.scopes[scope].parent;
    }
}
fn check_integer_bits(type_id: i64) -> i64 {
    if type_id == TYPE_I8 || type_id == TYPE_U8 { return 8; }
    if type_id == TYPE_I16 || type_id == TYPE_U16 { return 16; }
    if type_id == TYPE_I32 || type_id == TYPE_U32 { return 32; }
    return 64;
}
fn check_unsigned(type_id: i64) -> bool {
    return type_id == TYPE_U8 || type_id == TYPE_U16 || type_id == TYPE_U32 || type_id == TYPE_U64;
}
fn check_integer(type_id: i64) -> bool { return type_id >= TYPE_I8 && type_id <= TYPE_U64; }
fn check_float(type_id: i64) -> bool { return type_id == TYPE_F32 || type_id == TYPE_F64; }
fn check_numeric(type_id: i64) -> bool { return check_integer(type_id) || check_float(type_id); }
fn check_min(type_id: i64) -> i64 {
    if check_unsigned(type_id) { return 0; }
    if type_id == TYPE_I8 { return -128; }
    if type_id == TYPE_I16 { return -32768; }
    if type_id == TYPE_I32 { return -2147483648; }
    return -9223372036854775808;
}
fn check_max(type_id: i64) -> i64 {
    if type_id == TYPE_I8 { return 127; }
    if type_id == TYPE_U8 { return 255; }
    if type_id == TYPE_I16 { return 32767; }
    if type_id == TYPE_U16 { return 65535; }
    if type_id == TYPE_I32 { return 2147483647; }
    if type_id == TYPE_U32 { return 4294967295; }
    return 9223372036854775807;
}
fn check_align(value: i64, align: i64) -> i64 {
    if align <= 1 { return value; }
    return (value + align - 1) / align * align;
}
fn check_list_count(p: Program&, first: i64) -> i64 {
    var n = first; var result = 0;
    while n >= 0 { result += 1; n = p.nodes[n].next; }
    return result;
}
recursive fn check_same_type(p: Program&, a: i64, b: i64) -> bool {
    if a == b { return true; }
    if a < 0 || b < 0 { return false; }
    let at = p.types[a]; let bt = p.types[b];
    if at.kind != bt.kind || at.flags != bt.flags { return false; }
    if at.kind == TY_INT || at.kind == TY_FLOAT { return at.count == bt.count; }
    if at.kind == TY_STRUCT || at.kind == TY_ENUM || at.kind == TY_GENERIC {
        return at.declaration == bt.declaration;
    }
    if at.kind == TY_ARRAY || at.kind == TY_REF || at.kind == TY_SLICE {
        return at.count == bt.count && at.array_kind == bt.array_kind &&
            check_same_type(p, at.element, bt.element);
    }
    if at.kind == TY_FN || at.kind == TY_TUPLE {
        if at.element < 0 && bt.element >= 0 || at.element >= 0 && bt.element < 0 { return false; }
        if !check_same_type(p, at.element, bt.element) { return false; }
        var ap = at.first; var bp = bt.first;
        while ap >= 0 && bp >= 0 {
            if !check_same_type(p, p.nodes[ap].type_id, p.nodes[bp].type_id) { return false; }
            ap = p.nodes[ap].next; bp = p.nodes[bp].next;
        }
        return ap < 0 && bp < 0;
    }
    return true;
}
fn check_type(p: Program&, kind: i64, element: i64, count: i64, declaration: i64, flags: i64) -> i64 {
    for t, id in p.types {
        if t.kind == kind && t.element == element && t.count == count &&
           t.declaration == declaration && t.flags == flags { return id; }
    }
    var ty = Type { kind: kind, element: element, count: count, declaration: declaration, flags: flags };
    if kind == TY_REF || kind == TY_FN { ty.size = p.pointer_bytes; ty.align = p.pointer_bytes; }
    if kind == TY_SLICE { ty.size = 2 * p.pointer_bytes; ty.align = 2 * p.pointer_bytes; ty.array_kind = A_SLICE; }
    return add_type(p, ty);
}
fn check_array_type(p: Program&, element: i64, count: i64, array_kind: i64, flags: i64) -> i64 {
    for t, id in p.types {
        if t.kind == TY_ARRAY && t.element == element && t.count == count &&
           t.array_kind == array_kind && t.flags == flags { return id; }
    }
    var size = 24; var align = 4;
    if array_kind == A_FIXED && element >= 0 {
        align = p.types[element].align;
        if count >= 0 && p.types[element].size <= 2147483647 / (count + 1) {
            size = count * p.types[element].size;
        } else { size = 0; }
    }
    var length_storage = -1;
    if array_kind == A_VAR { length_storage = 0; }
    return add_type(p, Type { kind: TY_ARRAY, element: element, count: count, flags: flags, size: size, align: align, array_kind: array_kind, length_storage: length_storage });
}
fn check_const_type(p: Program&, ty: i64) -> i64 {
    if ty < 0 || (p.types[ty].flags & TF_CONST) != 0 { return ty; }
    var copy = p.types[ty]; copy.flags |= TF_CONST;
    return add_type(p, copy);
}
fn check_lookup_scope(p: Program&, token: i64, scope: i64) -> i64 {
    var id = p.symbols.len - 1;
    while id >= 0 {
        if p.symbols[id].scope == scope && same_name(p, p.symbols[id].name_token, token) { return id; }
        id -= 1;
    }
    return -1;
}
fn check_lookup(p: Program&, c: Checker&, token: i64, scope: i64) -> i64 {
    var current = scope;
    loop {
        let found = check_lookup_scope(p, token, current);
        if found >= 0 { return found; }
        if current <= 0 { return -1; }
        current = c.scopes[current].parent;
    }
}
fn check_lookup_name(p: Program&, c: Checker&, node: i64) -> i64 {
    let n = p.nodes[node];
    if n.aux <= 1 || n.integer < 0 || n.integer >= p.tokens.len {
        return check_lookup(p, c, n.token, c.scope);
    }
    var at = n.integer; var scope = c.scope;
    if p.tokens[at].kind == T_COLONCOLON { scope = 0; at += 1; }
    var symbol = check_lookup(p, c, at, scope);
    at += 1;
    while at < n.token {
        if p.tokens[at].kind == T_COLONCOLON { at += 1; }
        if symbol < 0 { return -1; }
        let declaration = p.symbols[symbol].node;
        if declaration < 0 || p.nodes[declaration].kind != N_NAMESPACE { return -1; }
        symbol = check_lookup_scope(p, at, p.nodes[declaration].scope);
        at += 1;
    }
    return symbol;
}
fn check_variable_index(c: Checker&, symbol: i64) -> i64 {
    var i = c.variables.len - 1;
    while i >= 0 { if c.variables[i].symbol == symbol { return i; } i -= 1; }
    return -1;
}
fn check_declare(p: Program&, c: Checker&, node: i64, scope: i64) -> i64 {
    if p.nodes[node].symbol >= 0 { return p.nodes[node].symbol; }
    let n = p.nodes[node];
    var previous = check_lookup_scope(p, n.token, scope);
    if n.kind == N_FUNCTION_VALUE { previous = -1; }
    var flags = 0; var slot = -1;
    if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE { flags |= S_FUNCTION; }
    if n.kind == N_STRUCT || n.kind == N_ENUM || n.kind == N_ALIAS || n.kind == N_TYPE_PARAM { flags |= S_TYPE; }
    if n.kind == N_PARAM { flags |= S_PARAMETER; }
    if (n.flags & F_VAR) != 0 { flags |= S_MUTABLE; }
    if (n.flags & F_EXTERN) != 0 { flags |= S_EXTERN; }
    if c.function_node < 0 && (flags & (S_FUNCTION | S_TYPE)) == 0 && n.kind != N_NAMESPACE && n.kind != N_FIELD && n.kind != N_VARIANT { flags |= S_GLOBAL; }
    if previous >= 0 {
        let old = p.symbols[previous];
        let namespace_merge = n.kind == N_NAMESPACE && old.node >= 0 && p.nodes[old.node].kind == N_NAMESPACE;
        if !namespace_merge && !((flags & S_FUNCTION) != 0 && (old.flags & S_FUNCTION) != 0) {
            diagnose(p, n.token, "duplicate declaration in this scope");
        }
    }
    if (flags & (S_FUNCTION | S_TYPE)) == 0 && n.kind != N_NAMESPACE && n.kind != N_FIELD && n.kind != N_VARIANT {
        slot = c.next_slot; c.next_slot += 1;
    }
    let id = p.symbols.len;
    p.symbols.push(Symbol { name_token: n.token, type_id: n.type_id, node: node,
        scope: scope, slot: slot, flags: flags, next: previous, owner: c.function_node });
    p.nodes[node].symbol = id;
    p.nodes[node].scope = scope;
    if slot >= 0 { c.variables.push(CheckVariable { symbol: id }); }
    return id;
}
fn check_add_root(c: Checker&, value: i64, root: i64) {
    for r in c.roots { if r.value == value && r.root == root { return; } }
    c.roots.push(CheckRoot { value: value, root: root });
}
fn check_copy_roots(c: Checker&, destination: i64, source: i64) {
    let end = c.roots.len;
    for i in 0..end { if c.roots[i].value == source { check_add_root(c, destination, c.roots[i].root); } }
}
fn check_place_root(p: Program&, node: i64) -> i64 {
    var current = node;
    while current >= 0 {
        let n = p.nodes[current];
        if n.kind == N_NAME { return n.symbol; }
        if n.kind == N_MEMBER || n.kind == N_INDEX || n.kind == N_SLICE || n.kind == N_UNARY {
            current = n.left;
        } else { return -2; }
    }
    return -2;
}
recursive fn check_contains_refs(p: Program&, ty: i64, depth: i64) -> bool {
    if ty < 0 || depth > 64 { return false; }
    let t = p.types[ty];
    if t.kind == TY_REF || t.kind == TY_SLICE { return true; }
    if t.kind == TY_ARRAY { return check_contains_refs(p, t.element, depth + 1); }
    if t.kind == TY_STRUCT || t.kind == TY_ENUM || t.kind == TY_TUPLE {
        var field = t.first;
        while field >= 0 {
            if check_contains_refs(p, p.nodes[field].type_id, depth + 1) { return true; }
            field = p.nodes[field].next;
        }
    }
    return false;
}
recursive fn check_size_class(p: Program&, ty: i64, depth: i64) -> i64 {
    if ty < 0 || depth > 64 { return 0; }
    let t = p.types[ty];
    if t.storage == 1 { return 1; }
    if t.kind == TY_ARRAY {
        if t.array_kind == A_GROW || t.array_kind == A_GROWSHRINK { return 2; }
        if t.array_kind == A_VAR || t.array_kind == A_LIMITED && t.count < 0 { return 1; }
        return check_size_class(p, t.element, depth + 1);
    }
    var result = 0;
    if t.kind == TY_STRUCT || t.kind == TY_ENUM {
        var field = t.first;
        while field >= 0 {
            let fc = check_size_class(p, p.nodes[field].type_id, depth + 1);
            if fc > result { result = fc; }
            field = p.nodes[field].next;
        }
    }
    return result;
}
fn check_store_roots(p: Program&, c: Checker&, destination: i64, expression: i64) {
    if destination < 0 { return; }
    let stored_type = p.nodes[expression].type_id;
    if stored_type >= 0 && !check_contains_refs(p, stored_type, 0) { return; }
    let target = p.symbols[destination];
    let vindex = check_variable_index(c, destination);
    let roots_end = c.roots.len;
    for ri in 0..roots_end {
        let r = c.roots[ri];
        if r.value != expression { continue; }
        let root = r.root;
        if root == -2 { diagnose(p, p.nodes[expression].token, "reference into a temporary escapes its statement"); continue; }
        if root < 0 { continue; }
        let owner = p.symbols[root];
        if (target.flags & S_GLOBAL) != 0 && (owner.flags & S_GLOBAL) == 0 {
            diagnose(p, p.nodes[expression].token, "global value cannot retain a reference into local storage");
        }
        if owner.owner == target.owner && !check_visible(c, owner.scope, target.scope) {
            diagnose(p, p.nodes[expression].token, "stored reference would outlive its owner");
        }
        let depth = c.scopes[owner.scope].depth;
        if vindex >= 0 {
            let fixed = c.variables[vindex].root_depth;
            if fixed >= 0 && fixed != depth {
                diagnose(p, p.nodes[expression].token, "a reference binding must keep one root lifetime depth");
            } else { c.variables[vindex].root_depth = depth; }
        }
        check_add_root(c, -destination - 10, root);
    }
}
fn check_note_effect(c: Checker&, root: i64, kind: i64) {
    if c.function_node < 0 || root < 0 { return; }
    for effect in c.effects {
        if effect.function_node == c.function_node && effect.root == root && effect.kind == kind { return; }
    }
    c.effects.push(CheckEffect { function_node: c.function_node, root: root, kind: kind });
}
fn check_primitive_token(kind: i64) -> i64 {
    if kind == T_TBOOL { return TYPE_BOOL; }
    if kind == T_TI8 { return TYPE_I8; }
    if kind == T_TI16 { return TYPE_I16; }
    if kind == T_TI32 { return TYPE_I32; }
    if kind == T_TI64 || kind == T_TVARINT { return TYPE_I64; }
    if kind == T_TU8 { return TYPE_U8; }
    if kind == T_TU16 { return TYPE_U16; }
    if kind == T_TU32 { return TYPE_U32; }
    if kind == T_TU64 { return TYPE_U64; }
    if kind == T_TF32 { return TYPE_F32; }
    if kind == T_TF64 { return TYPE_F64; }
    return -1;
}
fn check_bind_generic(p: Program&, c: Checker&, parameter: i64, value: i64, bindings: CheckList&) -> bool {
    for b_index in 0..bindings.count { let b = check_binding_at(c, bindings, b_index); if b.parameter == parameter { return check_same_type(p, b.value, value); } }
    check_binding_push(c, bindings, TypeBinding { parameter: parameter, value: value }); return true;
}
recursive fn check_unify(p: Program&, c: Checker&, formal: i64, actual: i64, bindings: CheckList&) -> bool {
    if formal < 0 { return true; }
    if actual < 0 { return false; }
    let f = p.types[formal]; let a = p.types[actual];
    if f.kind == TY_GENERIC { return check_bind_generic(p, c, f.declaration, actual, bindings); }
    if a.kind == TY_REF && f.kind != TY_REF { return check_unify(p, c, formal, a.element, bindings); }
    if f.kind == TY_REF && a.kind != TY_REF { return check_unify(p, c, f.element, actual, bindings); }
    if f.kind == TY_ARRAY || f.kind == TY_SLICE || f.kind == TY_REF {
        if f.kind != a.kind && !(f.kind == TY_SLICE && a.kind == TY_ARRAY) { return false; }
        if f.kind == TY_ARRAY && f.array_kind == A_FIXED && f.count != a.count { return false; }
        return check_unify(p, c, f.element, a.element, bindings);
    }
    if f.kind == TY_FN && a.kind == TY_FN {
        var fp = f.first; var ap = a.first;
        while fp >= 0 && ap >= 0 {
            if !check_unify(p, c, p.nodes[fp].type_id, p.nodes[ap].type_id, bindings) { return false; }
            fp = p.nodes[fp].next; ap = p.nodes[ap].next;
        }
        return fp < 0 && ap < 0 && check_unify(p, c, f.element, a.element, bindings);
    }
    return true;
}
recursive fn check_substitute(p: Program&, c: Checker&, ty: i64, bindings: CheckList&) -> i64 {
    if ty < 0 { return -1; }
    let t = p.types[ty];
    if t.kind == TY_GENERIC {
        for b_index in 0..bindings.count { let b = check_binding_at(c, bindings, b_index); if b.parameter == t.declaration { return b.value; } }
        return ty;
    }
    if t.kind == TY_ARRAY || t.kind == TY_SLICE || t.kind == TY_REF {
        let element = check_substitute(p, c, t.element, bindings);
        if element == t.element { return ty; }
        if t.kind == TY_ARRAY { return check_array_type(p, element, t.count, t.array_kind, t.flags); }
        return check_type(p, t.kind, element, t.count, t.declaration, t.flags);
    }
    if t.kind == TY_FN {
        for b_index in 0..bindings.count { let b = check_binding_at(c, bindings, b_index); if b.parameter == t.declaration { return b.value; } }
    }
    if t.kind == TY_TUPLE {
        var first = -1; var last = -1; var part = t.first;
        while part >= 0 {
            let id = new_node(p, N_TYPE_ARG, p.nodes[part].token);
            p.nodes[id].type_id = check_substitute(p, c, p.nodes[part].type_id, bindings);
            if first < 0 { first = id; } else { p.nodes[last].next = id; }
            last = id; part = p.nodes[part].next;
        }
        return add_type(p, Type { kind: TY_TUPLE, count: t.count, first: first, size: t.size, align: t.align });
    }
    return ty;
}
recursive fn check_clone(p: Program&, c: Checker&, node: i64, bindings: CheckList&) -> i64 {
    if node < 0 { return -1; }
    var copy = p.nodes[node];
    copy.type_id = check_substitute(p, c, copy.type_id, bindings);
    if copy.kind == N_PARAM {
        for binding_index in 0..bindings.count {
            let binding = check_binding_at(c, bindings, binding_index);
            if binding.parameter == node { copy.type_id = binding.value; }
        }
    }
    copy.symbol = -1; copy.scope = -1; copy.captures = -1; copy.flags &= ~(F_CHECKED | F_REACHABLE | F_CAPTURE);
    let old_first = copy.first; let old_left = copy.left; let old_right = copy.right; let old_third = copy.third;
    copy.first = -1; copy.last = -1; copy.left = -1; copy.right = -1; copy.third = -1; copy.next = -1;
    let id = p.nodes.len; p.nodes.push(copy);
    var child = old_first;
    while child >= 0 { append_child(p, id, check_clone(p, c, child, bindings)); child = p.nodes[child].next; }
    p.nodes[id].left = check_clone(p, c, old_left, bindings);
    p.nodes[id].right = check_clone(p, c, old_right, bindings);
    p.nodes[id].third = check_clone(p, c, old_third, bindings);
    // left and third may own lists (function results and generic parameters).
    if copy.kind == N_FUNCTION || copy.kind == N_FUNCTION_VALUE || copy.kind == N_TYPE_FN || copy.kind == N_CONST_FOR {
        var old = old_left; var tail = p.nodes[id].left;
        if old >= 0 { old = p.nodes[old].next; }
        while old >= 0 {
            let item = check_clone(p, c, old, bindings); p.nodes[tail].next = item; tail = item; old = p.nodes[old].next;
        }
    }
    if copy.kind == N_FUNCTION || copy.kind == N_STRUCT || copy.kind == N_ENUM {
        var old = old_third; var tail = p.nodes[id].third;
        if old >= 0 { old = p.nodes[old].next; }
        while old >= 0 {
            let item = check_clone(p, c, old, bindings); p.nodes[tail].next = item; tail = item; old = p.nodes[old].next;
        }
    }
    if copy.kind == N_VARIABLE {
        var old = old_right; var tail = p.nodes[id].right;
        if old >= 0 { old = p.nodes[old].next; }
        while old >= 0 {
            let item = check_clone(p, c, old, bindings); p.nodes[tail].next = item; tail = item; old = p.nodes[old].next;
        }
    }
    return id;
}

struct CheckConstant { valid: bool = false, value: i64 = 0 }
recursive fn check_constant(p: Program&, c: Checker&, node: i64, depth: i64) -> CheckConstant {
    if node < 0 || depth > 64 { return CheckConstant {}; }
    let n = p.nodes[node];
    if n.kind == N_INTEGER || n.kind == N_BOOL { return CheckConstant { valid: true, value: n.integer }; }
    if n.kind == N_NAME {
        var symbol = n.symbol;
        if symbol < 0 { symbol = check_lookup_name(p, c, node); }
        if symbol >= 0 && (p.symbols[symbol].flags & S_MUTABLE) == 0 {
            let declaration = p.symbols[symbol].node;
            if declaration >= 0 && p.nodes[declaration].kind == N_VARIABLE {
                return check_constant(p, c, p.nodes[declaration].right, depth + 1);
            }
        }
    }
    if n.kind == N_UNARY {
        let a = check_constant(p, c, n.left, depth + 1);
        if !a.valid { return a; }
        if n.integer == T_MINUS && a.value != -9223372036854775808 { return CheckConstant { valid: true, value: -a.value }; }
        if n.integer == T_BITNOT { return CheckConstant { valid: true, value: ~a.value }; }
        if n.integer == T_NOT {
            var value = 0; if a.value == 0 { value = 1; }
            return CheckConstant { valid: true, value: value };
        }
    }
    if n.kind == N_BINARY {
        let a = check_constant(p, c, n.left, depth + 1);
        let b = check_constant(p, c, n.right, depth + 1);
        if !a.valid || !b.valid { return CheckConstant {}; }
        let x = a.value; let y = b.value; let op = n.integer;
        if op == T_PLUS {
            if y > 0 && x > 9223372036854775807 - y || y < 0 && x < -9223372036854775808 - y { return CheckConstant {}; }
            return CheckConstant { valid: true, value: x + y };
        }
        if op == T_MINUS {
            if y < 0 && x > 9223372036854775807 + y || y > 0 && x < -9223372036854775808 + y { return CheckConstant {}; }
            return CheckConstant { valid: true, value: x - y };
        }
        if op == T_MUL {
            if x == 0 || y == 0 { return CheckConstant { valid: true }; }
            if x == -1 && y == -9223372036854775808 || y == -1 && x == -9223372036854775808 { return CheckConstant {}; }
            if x > 0 && y > 0 && x > 9223372036854775807 / y ||
               x > 0 && y < 0 && y < -9223372036854775808 / x ||
               x < 0 && y > 0 && x < -9223372036854775808 / y ||
               x < 0 && y < 0 && x < 9223372036854775807 / y { return CheckConstant {}; }
            return CheckConstant { valid: true, value: x * y };
        }
        if op == T_DIV || op == T_MOD {
            if y == 0 || x == -9223372036854775808 && y == -1 { return CheckConstant {}; }
            if op == T_DIV { return CheckConstant { valid: true, value: x / y }; }
            return CheckConstant { valid: true, value: x % y };
        }
        if op == T_BITAND { return CheckConstant { valid: true, value: x & y }; }
        if op == T_BITOR { return CheckConstant { valid: true, value: x | y }; }
        if op == T_XOR { return CheckConstant { valid: true, value: x ^ y }; }
        if op == T_SHL && y >= 0 && y < 63 && x >= 0 && x <= 9223372036854775807 >> y {
            return CheckConstant { valid: true, value: x << y };
        }
        if op == T_SHR && y >= 0 && y < 64 { return CheckConstant { valid: true, value: x >> y }; }
        var truth = false;
        if op == T_EQ { truth = x == y; }
        else if op == T_NEQ { truth = x != y; }
        else if op == T_LT { truth = x < y; }
        else if op == T_LTEQ { truth = x <= y; }
        else if op == T_GT { truth = x > y; }
        else if op == T_GTEQ { truth = x >= y; }
        else if op == T_ANDAND { truth = x != 0 && y != 0; }
        else if op == T_OROR { truth = x != 0 || y != 0; }
        else { return CheckConstant {}; }
        var value = 0; if truth { value = 1; }
        return CheckConstant { valid: true, value: value };
    }
    return CheckConstant {};
}
fn check_tuple(p: Program&, first: i64) -> i64 {
    if first < 0 { return TYPE_VOID; }
    if p.nodes[first].next < 0 { return p.nodes[first].type_id; }
    var size = 0; var align = 1; var count = 0; var part = first;
    while part >= 0 {
        let ty = p.nodes[part].type_id;
        if ty >= 0 { size += p.types[ty].size; if p.types[ty].align > align { align = p.types[ty].align; } }
        count += 1; part = p.nodes[part].next;
    }
    return add_type(p, Type { kind: TY_TUPLE, count: count, first: first, size: size, align: align });
}
fn check_ensure_generics(p: Program&, c: Checker&, declaration: i64) {
    var param = p.nodes[declaration].third;
    while param >= 0 {
        if p.nodes[param].type_id < 0 { p.nodes[param].type_id = check_type(p, TY_GENERIC, -1, 0, param, 0); }
        check_declare(p, c, param, c.scope);
        param = p.nodes[param].next;
    }
}
recursive fn check_array_element(p: Program&, c: Checker&, element: i64, array_kind: i64, token: i64) {
    if element < 0 || check_has_generic(p, element, 0) { return; }
    if p.types[element].kind == TY_STRUCT || p.types[element].kind == TY_ENUM { check_layout_nominal(p, c, element); }
    if check_has_generic(p, element, 0) { return; }
    let size_class = check_size_class(p, element, 0);
    if array_kind == A_FIXED || array_kind == A_LIMITED || array_kind == A_GROWSHRINK {
        if size_class != 0 { diagnose(p, token, "this array kind requires fixed-size elements"); }
    } else if array_kind == A_VAR || array_kind == A_GROW {
        if size_class == 2 { diagnose(p, token, "array elements cannot be resizable values"); }
    }
    if p.types[element].kind == TY_VOID || p.types[element].size == 0 && size_class == 0 {
        diagnose(p, token, "array elements require nonzero size");
    }
}

recursive fn check_resolve_type(p: Program&, c: Checker&, syntax: i64) -> i64 {
    if syntax < 0 { return -1; }
    if p.nodes[syntax].type_id >= 0 { return p.nodes[syntax].type_id; }
    let n = p.nodes[syntax]; var result = -1;
    if n.kind == N_TYPE_NAME || n.kind == N_NAME {
        if n.left >= 0 {
            let outer = check_resolve_type(p, c, n.left);
            if outer >= 0 && p.types[outer].kind == TY_ENUM {
                check_layout_nominal(p, c, outer);
                var variant = p.types[outer].first;
                while variant >= 0 {
                    if same_name(p, p.nodes[variant].token, n.token) { result = p.nodes[variant].type_id; break; }
                    variant = p.nodes[variant].next;
                }
            }
            if result < 0 { diagnose(p, n.token, "unknown enum variant type"); }
        } else {
            result = check_primitive_token(p.tokens[n.token].kind);
            if p.tokens[n.token].kind == T_TVARINT {
                var ty = p.types[TYPE_I64]; ty.storage = 1; ty.size = 0; result = add_type(p, ty);
            }
            if result < 0 && token_is(p, n.token, "void") { result = TYPE_VOID; }
            if result < 0 {
                let symbol = check_lookup_name(p, c, syntax);
                if symbol >= 0 && (p.symbols[symbol].flags & S_TYPE) != 0 {
                    let declaration = p.symbols[symbol].node;
                    p.nodes[syntax].symbol = symbol;
                    if declaration >= 0 && p.nodes[declaration].kind == N_ALIAS {
                        if (p.nodes[declaration].flags & F_CHECKED) != 0 { diagnose(p, n.token, "cyclic type alias"); }
                        else {
                            p.nodes[declaration].flags |= F_CHECKED;
                            let saved = c.scope; c.scope = p.symbols[symbol].scope;
                            result = check_resolve_type(p, c, p.nodes[declaration].left);
                            c.scope = saved; p.nodes[declaration].flags &= ~F_CHECKED;
                            p.symbols[symbol].type_id = result;
                        }
                    } else {
                        result = p.symbols[symbol].type_id;
                        if declaration >= 0 && p.nodes[declaration].third >= 0 {
                            result = check_nominal_instance(p, c, declaration, n.first, n.token);
                        } else if n.first >= 0 { diagnose(p, n.token, "type does not take generic arguments"); }
                    }
                } else if c.signature && n.aux <= 1 {
                    // An implicit generic parameter in a function signature.
                    let parameter = new_node(p, N_TYPE_PARAM, n.token);
                    result = check_type(p, TY_GENERIC, -1, 0, parameter, 0);
                    p.nodes[parameter].type_id = result;
                    check_declare(p, c, parameter, c.scope);
                } else { diagnose(p, n.token, "unknown type name"); }
            }
        }
    } else if n.kind == N_TYPE_REF {
        let element = check_resolve_type(p, c, n.left);
        let flags = n.flags & (TF_CONST | TF_OPTIONAL);
        result = check_type(p, TY_REF, element, 0, -1, flags);
        if n.right >= 0 {
            let storage = check_resolve_type(p, c, n.right);
            var copy = p.types[result];
            if storage >= 0 && p.types[storage].storage == 1 { copy.length_storage = 0; }
            else if check_integer(storage) && check_unsigned(storage) { copy.length_storage = p.types[storage].size; }
            else { diagnose(p, n.token, "relative reference offset must use an unsigned integer storage"); }
            if n.third >= 0 {
                let pool = check_lookup_name(p, c, n.third);
                if pool < 0 { diagnose(p, n.token, "unknown reference pool"); }
                copy.pool = pool;
            }
            if copy.length_storage > 0 { copy.size = copy.length_storage; }
            if copy.length_storage == 0 { copy.size = 0; }
            copy.align = 1; result = add_type(p, copy);
        }
    } else if n.kind == N_TYPE_ARRAY {
        let element = check_resolve_type(p, c, n.left);
        if n.integer != A_SLICE { check_array_element(p, c, element, n.integer, n.token); }
        var count = -1;
        if n.right >= 0 {
            let constant = check_constant(p, c, n.right, 0);
            if constant.valid { count = constant.value; }
            else if n.integer == A_FIXED { diagnose(p, n.token, "fixed array length must be a constant integer"); }
        }
        if count < 0 && n.right >= 0 && n.integer == A_FIXED { diagnose(p, n.token, "array length must be nonnegative"); }
        if n.integer == A_SLICE { result = check_type(p, TY_SLICE, element, -1, -1, n.flags & TF_CONST); }
        else { result = check_array_type(p, element, count, n.integer, n.flags & TF_CONST); }
        if n.third >= 0 {
            let length = check_resolve_type(p, c, n.third);
            if length >= 0 && p.types[length].storage == 1 { p.types[result].length_storage = 0; }
            else if check_integer(length) && check_unsigned(length) { p.types[result].length_storage = p.types[length].size; }
            else { diagnose(p, n.token, "array length storage must be an unsigned integer"); }
        }
        if n.integer == A_LIMITED && count >= 0 && element >= 0 {
            var bytes = 1;
            if count > 255 { bytes = 2; }
            if count > 65535 { bytes = 4; }
            if count > 4294967295 { bytes = 8; }
            p.types[result].length_storage = bytes;
            p.types[result].size = bytes + count * p.types[element].size;
            p.types[result].align = 1;
        }
        if element >= 0 && p.types[element].kind == TY_VOID { diagnose(p, n.token, "array element cannot be void"); }
        if n.integer == A_FIXED && element >= 0 && !check_has_generic(p, element, 0) && p.types[element].size == 0 && count > 0 {
            diagnose(p, n.token, "fixed array elements require a fixed physical size");
        }
    } else if n.kind == N_TYPE_PARAM {
        result = check_type(p, TY_GENERIC, -1, 0, syntax, 0);
    } else if n.kind == N_TYPE_FN {
        var param = n.first;
        while param >= 0 { check_resolve_type(p, c, param); param = p.nodes[param].next; }
        var ret = n.left;
        while ret >= 0 { check_resolve_type(p, c, ret); ret = p.nodes[ret].next; }
        result = add_type(p, Type { kind: TY_FN, element: check_tuple(p, n.left), declaration: syntax, first: n.first, size: p.pointer_bytes, align: p.pointer_bytes });
    } else if n.kind == N_TYPEOF {
        result = check_expression(p, c, n.left, -1);
    } else if n.kind == N_TYPE_DEDUCED {
        result = check_type(p, TY_GENERIC, -1, 0, syntax, 0);
    } else { diagnose(p, n.token, "invalid type syntax"); }
    if result >= 0 && (n.flags & F_INDEX_TYPE) != 0 && n.third >= 0 {
        let pool = check_lookup_name(p, c, n.third);
        if pool < 0 { diagnose(p, n.token, "index type names an unknown owner"); }
        var copy = p.types[result]; copy.pool = pool; copy.index_type = result;
        if (n.flags & F_BOUND_TYPE) != 0 { copy.flags |= F_BOUND_TYPE; }
        result = add_type(p, copy);
    }
    if result >= 0 && (n.flags & TF_CONST) != 0 && n.kind != N_TYPE_REF && n.kind != N_TYPE_ARRAY {
        result = check_const_type(p, result);
    }
    p.nodes[syntax].type_id = result;
    return result;
}
recursive fn check_layout_fields(p: Program&, c: Checker&, first: i64, owner: i64) -> i64 {
    var field = first; var size = 0; var index = 0; var variable = false;
    while field >= 0 {
        let n = p.nodes[field];
        if (n.flags & F_PAD) != 0 {
            var bytes = n.integer;
            if n.right >= 0 {
                let constant = check_constant(p, c, n.right, 0);
                if constant.valid { bytes = constant.value; }
                else { diagnose(p, n.token, "padding size must be a constant integer"); }
            }
            if bytes < 0 { diagnose(p, n.token, "padding size must be nonnegative"); bytes = 0; }
            p.nodes[field].integer = size; p.nodes[field].aux = bytes; size += bytes;
        } else {
            let ty = check_resolve_type(p, c, n.left);
            p.nodes[field].type_id = ty;
            if ty >= 0 && (p.types[ty].kind == TY_STRUCT || p.types[ty].kind == TY_ENUM) {
                check_layout_nominal(p, c, ty);
            }
            p.nodes[field].integer = size;
            if variable { p.nodes[field].integer = -1; }
            let symbol = check_declare(p, c, field, c.scope);
            p.symbols[symbol].type_id = ty; p.symbols[symbol].owner = owner;
            p.symbols[symbol].offset = size; p.symbols[symbol].index = index;
            if ty >= 0 {
                if p.types[ty].kind == TY_VOID { diagnose(p, n.token, "field cannot have void type"); }
                if check_size_class(p, ty, 0) == 2 && n.next >= 0 {
                    diagnose(p, n.token, "a resizable field must be the final field");
                }
                if p.types[ty].storage == 1 || p.types[ty].kind == TY_REF && p.types[ty].length_storage == 0 { variable = true; }
                if !variable { size += p.types[ty].size; }
            }
            index += 1;
        }
        if size > p.maximum_pages * 65536 { diagnose(p, n.token, "aggregate layout exceeds configured memory"); }
        field = n.next;
    }
    if variable { p.nodes[owner].flags |= F_VARIABLE_MODE; }
    return size;
}
recursive fn check_layout_nominal(p: Program&, c: Checker&, type_id: i64) {
    if type_id < 0 { return; }
    let t = p.types[type_id]; let declaration = t.declaration;
    if declaration < 0 || (p.nodes[declaration].flags & F_CHECKED) != 0 { return; }
    if t.size < 0 { diagnose(p, p.nodes[declaration].token, "aggregate contains itself by value"); return; }
    p.types[type_id].size = -1;
    let saved = c.scope;
    if p.nodes[declaration].scope >= 0 { c.scope = p.nodes[declaration].scope; }
    let parent = check_enter(c, c.function_node);
    p.nodes[declaration].scope = c.scope;
    check_ensure_generics(p, c, declaration);
    if t.kind == TY_STRUCT {
        let size = check_layout_fields(p, c, p.nodes[declaration].first, declaration);
        p.types[type_id].size = size; p.types[type_id].align = 1;
        p.types[type_id].first = p.nodes[declaration].first;
        var field = p.nodes[declaration].first; var last = -1; var byte_record = false;
        while field >= 0 {
            let ft = p.nodes[field].type_id;
            if ft >= 0 && (p.types[ft].storage == 1 || p.types[ft].kind == TY_REF && p.types[ft].length_storage == 0) {
                if !byte_record { p.types[type_id].prefix = p.nodes[field].integer; }
                byte_record = true;
            }
            last = field; field = p.nodes[field].next;
        }
        if byte_record {
            p.types[type_id].size = 24; p.types[type_id].align = 4; p.types[type_id].tail = last;
        } else if last >= 0 && p.nodes[last].type_id >= 0 && check_size_class(p, p.nodes[last].type_id, 0) > 0 {
            p.types[type_id].prefix = p.nodes[last].integer; p.types[type_id].tail = last; p.types[type_id].align = 4;
        }
    } else {
        var variant = p.nodes[declaration].first; var tag = 0; var maximum = 0;
        while variant >= 0 {
            let n = p.nodes[variant];
            let old_scope = check_enter(c, c.function_node);
            let payload = check_layout_fields(p, c, n.first, variant);
            c.scope = old_scope;
            let vt = add_type(p, Type { kind: TY_STRUCT, declaration: variant, first: n.first,
                size: payload, align: 1, pool: type_id });
            p.nodes[variant].type_id = vt; p.nodes[variant].integer = tag;
            p.nodes[variant].flags |= F_CHECKED;
            if payload > maximum { maximum = payload; }
            tag += 1; variant = n.next;
        }
        var tag_bytes = 1; if tag > 256 { tag_bytes = 2; }
        if tag > 65536 { diagnose(p, p.nodes[declaration].token, "enum has too many variants"); }
        p.types[type_id].size = tag_bytes + maximum; p.types[type_id].align = 1;
        p.types[type_id].first = p.nodes[declaration].first; p.types[type_id].count = tag;
        p.types[type_id].length_storage = tag_bytes;
    }
    c.scope = parent; c.scope = saved;
    p.nodes[declaration].flags |= F_CHECKED;
}
recursive fn check_nominal_instance(p: Program&, c: Checker&, declaration: i64, arguments: i64, token: i64) -> i64 {
    let saved_scope = c.scope;
    let outer_scope = p.nodes[declaration].scope;
    if outer_scope >= 0 { c.scope = outer_scope; }
    check_enter(c, c.function_node);
    check_ensure_generics(p, c, declaration);
    c.scope = saved_scope;
    var bindings = CheckList {};
    var param = p.nodes[declaration].third; var arg = arguments;
    while param >= 0 && arg >= 0 {
        let value = check_resolve_type(p, c, arg);
        check_binding_push(c, bindings, TypeBinding { parameter: param, value: value });
        param = p.nodes[param].next; arg = p.nodes[arg].next;
    }
    if param >= 0 || arg >= 0 { diagnose(p, token, "generic type argument count does not match its declaration"); return -1; }
    for spec in c.specializations {
        if spec.original != declaration || spec.binding_count != bindings.count { continue; }
        var equal = true;
        for i in 0..bindings.count { let b = check_binding_at(c, bindings, i);
            if !check_same_type(p, b.value, c.bindings[spec.binding_start + i].value) { equal = false; }
        }
        if equal { return p.symbols[spec.symbol].type_id; }
    }
    if c.inference_depth >= 64 { diagnose(p, token, "generic type instantiation does not reach a finite set"); return -1; }
    c.inference_depth += 1;
    let copy = check_clone(p, c, declaration, bindings);
    p.nodes[copy].third = -1; p.nodes[copy].origin = declaration; p.nodes[copy].scope = outer_scope;
    var kind = TY_STRUCT; if p.nodes[declaration].kind == N_ENUM { kind = TY_ENUM; }
    let ty = add_type(p, Type { kind: kind, declaration: copy, first: p.nodes[copy].first,
        name_token: p.nodes[copy].token });
    p.nodes[copy].type_id = ty;
    let symbol = p.symbols.len;
    p.symbols.push(Symbol { name_token: p.nodes[copy].token, type_id: ty, node: copy, scope: -2, flags: S_TYPE, owner: c.function_node });
    p.nodes[copy].symbol = symbol;
    let start = c.bindings.len; for binding_index in 0..bindings.count { c.bindings.push(check_binding_at(c, bindings, binding_index)); }
    c.specializations.push(CheckSpecialization { original: declaration, symbol: symbol,
        binding_start: start, binding_count: bindings.count });
    // Resolve generic names through their concrete bindings while laying out.
    let saved = c.scope;
    if outer_scope >= 0 { c.scope = outer_scope; }
    check_enter(c, c.function_node);
    for b_index in 0..bindings.count { let b = check_binding_at(c, bindings, b_index);
        let original = p.nodes[b.parameter];
        let binding = new_node(p, N_TYPE_PARAM, original.token);
        p.nodes[binding].type_id = b.value; check_declare(p, c, binding, c.scope);
    }
    p.nodes[copy].scope = c.scope;
    check_layout_nominal(p, c, ty);
    c.scope = saved; c.inference_depth -= 1;
    return ty;
}

fn check_addressable(p: Program&, node: i64) -> bool {
    if node < 0 { return false; }
    let n = p.nodes[node];
    return n.kind == N_NAME || n.kind == N_INDEX || n.kind == N_MEMBER ||
        n.kind == N_UNARY && n.integer == T_MUL;
}
fn check_readonly(p: Program&, c: Checker&, node: i64) -> bool {
    var current = node;
    while current >= 0 {
        let n = p.nodes[current];
        if n.kind == N_STRING { return true; }
        if n.type_id >= 0 && (p.types[n.type_id].flags & TF_CONST) != 0 { return true; }
        for root in c.roots { if root.value == current && root.root == -1 { return true; } }
        if n.kind == N_NAME {
            let vi = check_variable_index(c, n.symbol);
            return vi >= 0 && c.variables[vi].readonly;
        }
        if n.kind == N_MEMBER || n.kind == N_INDEX || n.kind == N_SLICE || n.kind == N_UNARY { current = n.left; }
        else { return false; }
    }
    return false;
}
recursive fn check_bottom(p: Program&, node: i64) -> bool {
    if node < 0 { return false; }
    let n = p.nodes[node];
    if n.kind == N_RETURN || n.kind == N_BREAK || n.kind == N_CONTINUE { return true; }
    if n.kind == N_BLOCK && n.last >= 0 { return check_bottom(p, n.last); }
    if n.kind == N_IF { return n.third >= 0 && check_bottom(p, n.right) && check_bottom(p, n.third); }
    if n.kind == N_CALL && n.symbol >= 0 {
        let s = p.symbols[n.symbol]; return (s.flags & S_BUILTIN) != 0 && (s.index == 4 || s.index == 5);
    }
    return false;
}

fn check_numeric_value_type(p: Program&, ty: i64) -> i64 {
    if ty < 0 { return ty; }
    let t = p.types[ty];
    if t.kind == TY_FLOAT { if t.count == 32 { return TYPE_F32; } return TYPE_F64; }
    if t.kind != TY_INT { return ty; }
    if t.storage == 1 { return TYPE_I64; }
    var first = TYPE_I8; if (t.flags & TF_UNSIGNED) != 0 { first = TYPE_U8; }
    for id in first..first + 4 { if p.types[id].count == t.count { return id; } }
    return ty;
}
recursive fn check_literal_tree(p: Program&, node: i64, depth: i64) -> bool {
    if node < 0 || depth > 64 { return false; }
    let n = p.nodes[node];
    if n.kind == N_INTEGER { return true; }
    if n.kind == N_UNARY && (n.integer == T_MINUS || n.integer == T_BITNOT) { return check_literal_tree(p, n.left, depth + 1); }
    if n.kind == N_BINARY { return check_literal_tree(p, n.left, depth + 1) && check_literal_tree(p, n.right, depth + 1); }
    if n.kind == N_NAME && n.symbol >= 0 {
        let s = p.symbols[n.symbol];
        if (s.flags & S_GLOBAL) != 0 && (s.flags & S_MUTABLE) == 0 && s.node >= 0 && p.nodes[s.node].left < 0 {
            return check_literal_tree(p, p.nodes[s.node].right, depth + 1);
        }
    }
    return false;
}

recursive fn check_conversion(p: Program&, c: Checker&, expression: i64, source_type: i64, destination_type: i64) -> i64 {
    let source = check_numeric_value_type(p, source_type); let destination = check_numeric_value_type(p, destination_type);
    if destination < 0 { return 0; }
    if source < 0 { if check_bottom(p, expression) { return 0; } return -1; }
    let branch = p.nodes[expression];
    if branch.kind == N_BLOCK && (branch.flags & F_TAIL) != 0 && branch.last >= 0 {
        return check_conversion(p, c, branch.last, p.nodes[branch.last].type_id, destination);
    }
    if branch.kind == N_IF {
        if branch.third < 0 { return -1; }
        let a = check_conversion(p, c, branch.right, p.nodes[branch.right].type_id, destination);
        let b = check_conversion(p, c, branch.third, p.nodes[branch.third].type_id, destination);
        if a < 0 || b < 0 { return -1; }
        if a > b { return a; } return b;
    }
    if branch.kind == N_MATCH {
        var arm = branch.first; var score = 0;
        while arm >= 0 {
            let body = p.nodes[arm].right; let conversion = check_conversion(p, c, body, p.nodes[body].type_id, destination);
            if conversion < 0 { return -1; }
            if conversion > score { score = conversion; } arm = p.nodes[arm].next;
        }
        return score;
    }
    if check_same_type(p, source, destination) { return 0; }
    let s = p.types[source]; let d = p.types[destination]; let n = p.nodes[expression];
    if s.kind == TY_GENERIC || d.kind == TY_GENERIC { return 1; }
    if n.kind == N_INTEGER && check_integer(destination) {
        if (n.flags & F_UNSIGNED) != 0 { if destination == TYPE_U64 { return 1; } return -1; }
        if n.integer >= check_min(destination) && n.integer <= check_max(destination) { return 1; }
        return -1;
    }
    if check_integer(destination) && check_literal_tree(p, expression, 0) {
        let constant = check_constant(p, c, expression, 0);
        if constant.valid && constant.value >= check_min(destination) && constant.value <= check_max(destination) { return 1; }
    }
    if n.kind == N_FLOAT && check_float(destination) { return 1; }
    if check_integer(source) && check_float(destination) { return 4; }
    if source == TYPE_F32 && destination == TYPE_F64 { return 2; }
    if check_integer(source) && check_integer(destination) {
        let sb = check_integer_bits(source); let db = check_integer_bits(destination);
        if check_unsigned(source) == check_unsigned(destination) && sb < db { return 2; }
        if check_unsigned(source) && !check_unsigned(destination) && sb < db { return 2; }
    }
    if s.kind == TY_REF && d.kind != TY_REF { return check_conversion(p, c, expression, s.element, destination); }
    if d.kind == TY_REF {
        if n.kind == N_NULL && (d.flags & TF_OPTIONAL) != 0 { return 1; }
        if s.kind == TY_REF && check_same_type(p, s.element, d.element) {
            if (s.flags & TF_CONST) != 0 && (d.flags & TF_CONST) == 0 { return -1; }
            if (s.flags & TF_OPTIONAL) != 0 && (d.flags & TF_OPTIONAL) == 0 { return -1; }
            if s.length_storage != d.length_storage || s.pool != d.pool { return -1; }
            return 1;
        }
        if check_same_type(p, source, d.element) && check_addressable(p, expression) { return 2; }
    }
    if d.kind == TY_SLICE && (s.kind == TY_ARRAY || s.kind == TY_SLICE) &&
       check_same_type(p, s.element, d.element) {
        if (s.flags & TF_CONST) != 0 && (d.flags & TF_CONST) == 0 && n.kind != N_STRING { return -1; }
        return 2;
    }
    if d.kind == TY_ARRAY && (s.kind == TY_ARRAY || s.kind == TY_SLICE) && check_same_type(p, s.element, d.element) {
        if d.array_kind == A_FIXED && s.count >= 0 && d.count != s.count { return -1; }
        if d.array_kind == A_LIMITED && d.count >= 0 && s.count > d.count { return -1; }
        return 3;
    }
    if n.kind == N_STRING && d.kind == TY_ARRAY && d.element == TYPE_U8 { return 2; }
    if d.kind == TY_ENUM && s.kind == TY_STRUCT && s.pool == destination { return 1; }
    if s.kind == d.kind && s.element == d.element && s.count == d.count &&
       (s.flags & ~TF_CONST) == (d.flags & ~TF_CONST) { return 1; }
    return -1;
}
fn check_wrap_unary(p: Program&, node: i64, op: i64, ty: i64) {
    var original = p.nodes[node]; let next = original.next; original.next = -1;
    let inner = p.nodes.len; p.nodes.push(original);
    p.nodes[node] = Node { kind: N_UNARY, token: original.token, next: next, left: inner, type_id: ty, integer: op, flags: F_CHECKED, scope: original.scope };
}
recursive fn check_expect(p: Program&, c: Checker&, expression: i64, source: i64, expected: i64) -> i64 {
    if expected < 0 || expected == TYPE_VOID { return source; }
    if check_conversion(p, c, expression, source, expected) < 0 {
        diagnose(p, p.nodes[expression].token, "value cannot implicitly convert to the required type"); return source;
    }
    if source < 0 { return expected; }
    let branch = p.nodes[expression];
    if branch.kind == N_BLOCK && (branch.flags & F_TAIL) != 0 && branch.last >= 0 {
        check_expect(p, c, branch.last, p.nodes[branch.last].type_id, expected); p.nodes[expression].type_id = expected; return expected;
    }
    if branch.kind == N_IF {
        check_expect(p, c, branch.right, p.nodes[branch.right].type_id, expected);
        if branch.third >= 0 { check_expect(p, c, branch.third, p.nodes[branch.third].type_id, expected); }
        p.nodes[expression].type_id = expected; return expected;
    }
    if branch.kind == N_MATCH {
        var arm = branch.first;
        while arm >= 0 { let body = p.nodes[arm].right; check_expect(p, c, body, p.nodes[body].type_id, expected); arm = p.nodes[arm].next; }
        p.nodes[expression].type_id = expected; return expected;
    }
    if p.types[expected].kind == TY_REF && p.types[source].kind != TY_REF && p.nodes[expression].kind != N_NULL {
        if (p.types[expected].flags & TF_CONST) == 0 && check_readonly(p, c, expression) {
            diagnose(p, p.nodes[expression].token, "writable reference cannot bind read-only storage");
        }
        let root = check_place_root(p, expression);
        check_wrap_unary(p, expression, T_BITAND, expected); check_add_root(c, expression, root);
    } else if p.types[source].kind == TY_REF && p.types[expected].kind != TY_REF {
        check_wrap_unary(p, expression, T_MUL, p.types[source].element);
    }
    let kind = p.nodes[expression].kind;
    if kind == N_INTEGER || kind == N_FLOAT || kind == N_ARRAY || kind == N_NULL || kind == N_STRING {
        p.nodes[expression].type_id = expected;
    }
    return expected;
}
recursive fn check_value(p: Program&, c: Checker&, node: i64, expected: i64) -> i64 {
    var ty = check_expression(p, c, node, expected);
    if ty >= 0 && p.types[ty].kind == TY_REF && (expected < 0 || p.types[expected].kind != TY_REF) {
        let element = p.types[ty].element;
        if expected >= 0 || (p.types[ty].flags & TF_OPTIONAL) == 0 && check_size_class(p, element, 0) == 0 {
            if (p.types[ty].flags & TF_OPTIONAL) != 0 { diagnose(p, p.nodes[node].token, "optional reference must be narrowed before dereferencing"); }
            check_wrap_unary(p, node, T_MUL, element); ty = element;
        }
    }
    let numeric = check_numeric_value_type(p, ty);
    if numeric != ty { p.nodes[node].type_id = numeric; ty = numeric; }
    return check_expect(p, c, node, ty, expected);
}
recursive fn check_narrow_condition(p: Program&, c: Checker&, node: i64, sense: bool) {
    if node < 0 { return; }
    let n = p.nodes[node];
    if n.kind == N_UNARY && n.integer == T_NOT { check_narrow_condition(p, c, n.left, !sense); return; }
    if n.kind == N_BINARY {
        if n.integer == T_ANDAND && sense || n.integer == T_OROR && !sense {
            check_narrow_condition(p, c, n.left, sense); check_narrow_condition(p, c, n.right, sense); return;
        }
        if n.integer == T_EQ || n.integer == T_NEQ || n.integer == T_DOTEQ || n.integer == T_DOTNEQ {
            var value = -1;
            if p.nodes[n.left].kind == N_NULL { value = n.right; }
            if p.nodes[n.right].kind == N_NULL { value = n.left; }
            if value >= 0 { check_narrow_condition(p, c, value, sense == (n.integer == T_NEQ || n.integer == T_DOTNEQ)); }
            return;
        }
    }
    if n.kind != N_NAME || !sense || n.symbol < 0 { return; }
    let declared = p.symbols[n.symbol].type_id; let vi = check_variable_index(c, n.symbol);
    if declared < 0 || vi < 0 || p.types[declared].kind != TY_REF { return; }
    var copy = p.types[declared]; copy.flags &= ~TF_OPTIONAL;
    c.variables[vi].narrowed = add_type(p, copy);
}

recursive fn check_condition(p: Program&, c: Checker&, node: i64) {
    let ty = check_expression(p, c, node, -1);
    if ty == TYPE_BOOL || ty >= 0 && p.types[ty].kind == TY_REF { return; }
    diagnose(p, p.nodes[node].token, "condition requires bool or an optional reference");
}
fn check_capture(p: Program&, c: Checker&, symbol: i64) {
    if c.function_node < 0 || symbol < 0 { return; }
    let s = p.symbols[symbol];
    if s.owner < 0 || s.owner == c.function_node || (s.flags & (S_FUNCTION | S_TYPE)) != 0 { return; }
    p.symbols[symbol].flags |= S_CAPTURE;
    p.nodes[c.function_node].flags |= F_CAPTURE;
    var capture = p.nodes[c.function_node].captures; var last = -1;
    while capture >= 0 {
        if p.nodes[capture].symbol == symbol { return; }
        last = capture; capture = p.nodes[capture].next;
    }
    let id = new_node(p, N_BINDING, s.name_token); p.nodes[id].symbol = symbol; p.nodes[id].type_id = s.type_id;
    if last < 0 { p.nodes[c.function_node].captures = id; } else { p.nodes[last].next = id; }
}
recursive fn check_default(p: Program&, c: Checker&, ty: i64, token: i64, depth: i64) -> i64 {
    if ty < 0 || depth > 64 { diagnose(p, token, "type has no finite default value"); return -1; }
    let t = p.types[ty]; var kind = N_INTEGER;
    if t.kind == TY_BOOL { kind = N_BOOL; }
    else if t.kind == TY_FLOAT { kind = N_FLOAT; }
    else if t.kind == TY_REF {
        if (t.flags & TF_OPTIONAL) == 0 { diagnose(p, token, "non-optional reference has no default value"); return -1; }
        kind = N_NULL;
    } else if t.kind == TY_ARRAY { kind = N_ARRAY; }
    else if t.kind == TY_STRUCT || t.kind == TY_ENUM { kind = N_RECORD; }
    else if t.kind != TY_INT { diagnose(p, token, "type has no default value"); return -1; }
    let id = new_node(p, kind, token); p.nodes[id].type_id = ty;
    if kind == N_ARRAY && t.array_kind == A_FIXED && t.count > 0 {
        let element = check_default(p, c, t.element, token, depth + 1);
        let count = new_node(p, N_INTEGER, token); p.nodes[count].integer = t.count; p.nodes[count].type_id = TYPE_I64;
        p.nodes[id].first = element; p.nodes[id].last = element; p.nodes[id].right = count; p.nodes[id].flags |= F_DEFAULT;
    }
    if kind == N_RECORD {
        check_layout_nominal(p, c, ty);
        var field = p.types[ty].first;
        if t.kind == TY_ENUM && field >= 0 { p.nodes[id].symbol = field; field = p.nodes[field].first; }
        while field >= 0 {
            let f = p.nodes[field];
            if (f.flags & F_PAD) == 0 {
                var value = -1;
                if f.right >= 0 { var bindings = CheckList {}; value = check_clone(p, c, f.right, bindings); }
                else { value = check_default(p, c, f.type_id, token, depth + 1); }
                let binding = new_node(p, N_BINDING, f.token);
                p.nodes[binding].symbol = field; p.nodes[binding].right = value; p.nodes[binding].type_id = f.type_id;
                append_child(p, id, binding);
            }
            field = f.next;
        }
    }
    p.nodes[id].flags |= F_CHECKED;
    return id;
}
recursive fn check_array(p: Program&, c: Checker&, node: i64, expected: i64) -> i64 {
    let n = p.nodes[node]; var element = -1; var count = check_list_count(p, n.first);
    if expected >= 0 && (p.types[expected].kind == TY_ARRAY || p.types[expected].kind == TY_SLICE) {
        element = p.types[expected].element;
    }
    var child = n.first;
    while child >= 0 {
        let ty = check_value(p, c, child, element);
        if element < 0 { element = ty; }
        check_copy_roots(c, node, child); child = p.nodes[child].next;
    }
    if n.right >= 0 {
        check_value(p, c, n.right, TYPE_I64);
        let constant = check_constant(p, c, n.right, 0);
        if constant.valid {
            if constant.value < 0 { diagnose(p, n.token, "array repetition count must be nonnegative"); }
            count = constant.value;
        } else { count = -1; }
        if check_list_count(p, n.first) != 1 { diagnose(p, n.token, "array repetition requires one element"); }
    }
    if expected >= 0 && p.types[expected].kind == TY_ARRAY {
        check_array_element(p, c, element, p.types[expected].array_kind, n.token);
        let d = p.types[expected];
        if d.array_kind == A_FIXED && (count < 0 || d.count != count) { diagnose(p, n.token, "array literal length does not match its fixed destination"); }
        if d.array_kind == A_LIMITED && d.count >= 0 && count > d.count { diagnose(p, n.token, "array literal exceeds its destination capacity"); }
        return expected;
    }
    if element < 0 { return check_array_type(p, -1, 0, A_GROW, 0); }
    var array_kind = A_FIXED; if count < 0 { array_kind = A_VAR; }
    check_array_element(p, c, element, array_kind, n.token);
    if count < 0 { return check_array_type(p, element, count, A_VAR, 0); }
    return check_array_type(p, element, count, A_FIXED, 0);
}
recursive fn check_record(p: Program&, c: Checker&, node: i64, expected: i64) -> i64 {
    check_expand_children(p, c, node);
    let n = p.nodes[node]; var ty = expected;
    if n.left >= 0 {
        let name = p.nodes[n.left];
        if name.kind == N_MEMBER {
            let outer = check_resolve_type(p, c, name.left);
            if outer >= 0 && p.types[outer].kind == TY_ENUM {
                check_layout_nominal(p, c, outer);
                var v = p.types[outer].first;
                while v >= 0 {
                    if same_name(p, p.nodes[v].token, name.token) { ty = p.nodes[v].type_id; p.nodes[node].symbol = v; break; }
                    v = p.nodes[v].next;
                }
            }
        } else { ty = check_resolve_type(p, c, n.left); }
    }
    if ty < 0 || p.types[ty].kind != TY_STRUCT && p.types[ty].kind != TY_ENUM {
        diagnose(p, n.token, "record literal requires a struct or enum variant type"); return -1;
    }
    check_layout_nominal(p, c, ty);
    if p.types[ty].kind == TY_ENUM { diagnose(p, n.token, "enum construction requires a named variant"); return -1; }
    let first = p.types[ty].first;
    if p.types[ty].pool >= 0 { p.nodes[node].symbol = p.types[ty].declaration; }
    var binding = n.first; var positional = first; var seen_named = false;
    var used = CheckList {};
    while binding >= 0 {
        let b = p.nodes[binding]; var field = -1;
        if (b.flags & F_DEFAULT) != 0 || (b.flags & 1) != 0 {
            if b.right >= 0 { check_value(p, c, b.right, ty); }
            field = first;
            while field >= 0 {
                var exists = false; for old_index in 0..used.count { let old = check_list_at(c, used, old_index); if old == field { exists = true; } }
                if !exists && (p.nodes[field].flags & F_PAD) == 0 {
                    let value = check_default(p, c, p.nodes[field].type_id, b.token, 0);
                    let init = new_node(p, N_BINDING, p.nodes[field].token);
                    p.nodes[init].symbol = field; p.nodes[init].right = value; p.nodes[init].type_id = p.nodes[field].type_id;
                    append_child(p, node, init); check_list_push(c, used, field);
                }
                field = p.nodes[field].next;
            }
            p.nodes[binding].kind = N_EMPTY;
        } else {
            let named = b.token >= 0;
            if named {
                seen_named = true; field = first;
                while field >= 0 { if same_name(p, p.nodes[field].token, b.token) { break; } field = p.nodes[field].next; }
            } else {
                if seen_named { diagnose(p, b.token, "positional initializer cannot follow a named initializer"); }
                while positional >= 0 && (p.nodes[positional].flags & F_PAD) != 0 { positional = p.nodes[positional].next; }
                field = positional; if positional >= 0 { positional = p.nodes[positional].next; }
            }
            if field < 0 { diagnose(p, b.token, "record initializer names no field"); }
            else {
                for old_index in 0..used.count { let old = check_list_at(c, used, old_index); if old == field { diagnose(p, b.token, "field initialized more than once"); } }
                check_list_push(c, used, field); p.nodes[binding].symbol = field;
                var value = b.right; if value < 0 { value = b.left; p.nodes[binding].right = value; p.nodes[binding].left = -1; }
                if value < 0 { diagnose(p, b.token, "field initializer is missing"); }
                else {
                    let ft = p.nodes[field].type_id;
                    check_value(p, c, value, ft); p.nodes[binding].type_id = ft; check_copy_roots(c, node, value);
                }
            }
        }
        binding = b.next;
    }
    var field = first;
    while field >= 0 {
        let f = p.nodes[field]; var exists = false;
        for old_index in 0..used.count { let old = check_list_at(c, used, old_index); if old == field { exists = true; } }
        if !exists && (f.flags & F_PAD) == 0 {
            if f.right < 0 && (n.flags & F_DEFAULT) == 0 { diagnose(p, n.token, "record literal leaves a field without an initializer"); }
            else {
                var bindings = CheckList {};
                var value = -1;
                if f.right >= 0 { value = check_clone(p, c, f.right, bindings); }
                else { value = check_default(p, c, f.type_id, n.token, 0); }
                if value >= 0 { check_value(p, c, value, f.type_id); }
                let init = new_node(p, N_BINDING, f.token);
                p.nodes[init].symbol = field; p.nodes[init].right = value; p.nodes[init].type_id = f.type_id;
                append_child(p, node, init); check_copy_roots(c, node, value);
            }
        }
        field = f.next;
    }
    return ty;
}

fn check_builtin_kind(p: Program&, token: i64) -> i64 {
    if token_is(p, token, "print") { return 0; }
    if token_is(p, token, "str") { return 1; }
    if token_is(p, token, "format") { return 2; }
    if token_is(p, token, "assert") { return 3; }
    if token_is(p, token, "abort") { return 4; }
    if token_is(p, token, "exit") { return 5; }
    if token_is(p, token, "hardware_threads") { return 6; }
    if token_is(p, token, "thread_spawn") { return 7; }
    if token_is(p, token, "thread_spawn_contained") { return 8; }
    if token_is(p, token, "thread_wait") { return 9; }
    if token_is(p, token, "qput") { return 10; }
    if token_is(p, token, "qget") { return 11; }
    if token_is(p, token, "qpoll") { return 12; }
    if token_is(p, token, "qlimit") { return 13; }
    if token_is(p, token, "default") { return 14; }
    if token_is(p, token, "copy") { return 15; }
    if token_is(p, token, "to_bytes") { return 16; }
    if token_is(p, token, "bytes_of") { return 17; }
    if token_is(p, token, "from_bytes") { return 18; }
    if token_is(p, token, "embed_shader") { return 19; }
    if token_is(p, token, "embed_file") { return 20; }
    if token_is(p, token, "len") { return 21; }
    if token_is(p, token, "cap") { return 22; }
    if token_is(p, token, "index_of") { return 23; }
    if token_is(p, token, "push") { return 24; }
    if token_is(p, token, "append") { return 25; }
    if token_is(p, token, "pop") { return 26; }
    if token_is(p, token, "pop_n") { return 27; }
    if token_is(p, token, "resize") { return 28; }
    if token_is(p, token, "clear") { return 29; }
    if token_is(p, token, "alloc_index") { return 30; }
    if token_is(p, token, "alloc_ref") { return 31; }
    if token_is(p, token, "free") { return 32; }
    if token_is(p, token, "alloc_slice") { return 33; }
    if token_is(p, token, "realloc_slice") { return 34; }
    if token_is(p, token, "free_slice") { return 35; }
    return -1;
}
fn check_builtin_symbol(p: Program&, token: i64, builtin: i64, result: i64) -> i64 {
    for s, id in p.symbols { if (s.flags & S_BUILTIN) != 0 && s.index == builtin { return id; } }
    let type_id = add_type(p, Type { kind: TY_FN, element: result, size: p.pointer_bytes, align: p.pointer_bytes });
    let id = p.symbols.len;
    p.symbols.push(Symbol { name_token: token, type_id: type_id, scope: -2,
        flags: S_FUNCTION | S_BUILTIN, index: builtin });
    return id;
}
fn check_array_receiver(p: Program&, c: Checker&, node: i64, write: bool) -> i64 {
    var ty = p.nodes[node].type_id;
    if ty >= 0 && p.types[ty].kind == TY_REF { ty = p.types[ty].element; }
    if ty < 0 || p.types[ty].kind != TY_ARRAY && p.types[ty].kind != TY_SLICE {
        diagnose(p, p.nodes[node].token, "array builtin requires an array or slice receiver"); return -1;
    }
    if write && check_readonly(p, c, node) { diagnose(p, p.nodes[node].token, "array mutation requires writable storage"); }
    return ty;
}
fn check_mutation_views(p: Program&, c: Checker&, receiver: i64, shrink: bool) {
    let root = check_place_root(p, receiver);
    if root < 0 { return; }
    check_note_effect(c, root, 1);
    if shrink { check_note_effect(c, root, 2); }
    if !shrink && p.pointer_bytes == 8 { return; }
    for v in c.variables {
        if !v.assigned || v.symbol == root { continue; }
        let holder = p.symbols[v.symbol];
        if !check_visible(c, holder.scope, c.scope) { continue; }
        for r in c.roots {
            if r.value == -v.symbol - 10 && r.root == root {
                diagnose(p, p.nodes[receiver].token, "array mutation may invalidate a live reference or slice");
            }
        }
    }
}
recursive fn check_builtin(p: Program&, c: Checker&, node: i64, builtin: i64) -> i64 {
    let n = p.nodes[node]; var args = CheckList {};
    var argument = n.first;
    while argument >= 0 { check_list_push(c, args, argument); argument = p.nodes[argument].next; }
    var minimum = 1; var maximum = 1;
    if builtin == 0 || builtin == 1 { minimum = 0; maximum = 99; }
    if builtin == 2 { minimum = 1; maximum = 99; }
    if builtin == 6 || builtin == 11 || builtin == 12 || builtin == 14 { minimum = 0; maximum = 0; }
    if builtin == 7 || builtin == 8 || builtin == 19 { minimum = 1; maximum = 99; }
    if builtin == 9 || builtin == 16 { maximum = 2; }
    if builtin == 23 || builtin == 24 || builtin == 25 || builtin == 27 || builtin == 30 || builtin == 31 ||
       builtin == 32 || builtin == 33 || builtin == 35 { minimum = 2; maximum = 2; }
    if builtin == 28 { minimum = 2; maximum = 3; }
    if builtin == 34 { minimum = 3; maximum = 3; }
    if args.count < minimum || args.count > maximum {
        diagnose(p, n.token, "builtin argument count does not match its signature"); return -1;
    }
    if n.third >= 0 { diagnose(p, n.token, "builtin does not accept a trailing function value"); }
    let callee = p.nodes[n.left];
    var type_argument = -1;
    if callee.first >= 0 {
        type_argument = check_resolve_type(p, c, callee.first);
        if p.nodes[callee.first].next >= 0 { diagnose(p, n.token, "builtin accepts one explicit type argument"); }
        if builtin != 11 && builtin != 12 && builtin != 13 && builtin != 14 && builtin != 18 {
            diagnose(p, n.token, "builtin does not accept explicit type arguments");
        }
    }
    var result = TYPE_VOID;
    if builtin == 0 || builtin == 1 || builtin == 2 {
        var start = 0;
        if builtin == 2 {
            let receiver = check_array_receiver(p, c, check_list_at(c, args, 0), true);
            if receiver >= 0 && p.types[receiver].element != TYPE_U8 { diagnose(p, n.token, "format receiver must be a byte array"); }
            check_mutation_views(p, c, check_list_at(c, args, 0), false); start = 1;
        }
        for i in start..args.count {
            let ty = check_value(p, c, check_list_at(c, args, i), -1);
            if ty >= 0 && p.types[ty].kind == TY_FN { diagnose(p, n.token, "a function value cannot be formatted"); }
        }
        if builtin == 1 { result = check_array_type(p, TYPE_U8, -1, A_GROW, 0); }
    } else if builtin == 3 { check_condition(p, c, check_list_at(c, args, 0)); check_narrow_condition(p, c, check_list_at(c, args, 0), true); }
    else if builtin == 4 { check_value(p, c, check_list_at(c, args, 0), TYPE_STRING); c.reachable = false; }
    else if builtin == 5 { check_value(p, c, check_list_at(c, args, 0), TYPE_I64); c.reachable = false; }
    else if builtin == 6 { result = TYPE_I64; }
    else if builtin == 14 {
        if type_argument < 0 { diagnose(p, n.token, "default requires an explicit type argument"); return -1; }
        let replacement = check_default(p, c, type_argument, n.token, 0);
        if replacement >= 0 { let next = n.next; p.nodes[node] = p.nodes[replacement]; p.nodes[node].next = next; }
        return type_argument;
    } else if builtin == 15 {
        result = check_value(p, c, check_list_at(c, args, 0), -1); check_copy_roots(c, node, check_list_at(c, args, 0));
    } else if builtin == 7 || builtin == 8 {
        let worker = p.nodes[check_list_at(c, args, 0)].symbol;
        if worker < 0 || p.symbols[worker].node < 0 || (p.nodes[p.symbols[worker].node].flags & F_THREAD) == 0 {
            diagnose(p, n.token, "thread_spawn requires a thread_fn declaration");
        } else {
            let fnnode = p.symbols[worker].node;
            check_function(p, c, fnnode);
            var formal = p.nodes[fnnode].first; var i = 1;
            while formal >= 0 && i < args.count {
                check_value(p, c, check_list_at(c, args, i), p.nodes[formal].type_id); formal = p.nodes[formal].next; i += 1;
            }
            if formal >= 0 || i != args.count { diagnose(p, n.token, "thread worker argument count does not match"); }
        }
        result = TYPE_I64;
    } else if builtin == 9 { check_value(p, c, check_list_at(c, args, 0), TYPE_I64); }
    else if builtin == 10 {
        let ty = check_value(p, c, check_list_at(c, args, 0), -1);
        if ty >= 0 && check_contains_refs(p, ty, 0) { diagnose(p, n.token, "queue messages cannot contain references"); }
    } else if builtin == 11 || builtin == 12 || builtin == 13 {
        if type_argument < 0 { diagnose(p, n.token, "queue builtin requires an explicit message type"); return -1; }
        if check_contains_refs(p, type_argument, 0) { diagnose(p, n.token, "queue message type cannot hold references"); }
        if builtin == 11 { result = type_argument; }
        if builtin == 12 { result = TYPE_BOOL; }
        if builtin == 13 { check_value(p, c, check_list_at(c, args, 0), TYPE_I64); }
    } else if builtin == 18 {
        if type_argument < 0 { diagnose(p, n.token, "from_bytes requires an explicit result type"); return -1; }
        let bytes = check_array_receiver(p, c, check_list_at(c, args, 0), false);
        if bytes >= 0 && p.types[bytes].element != TYPE_U8 { diagnose(p, n.token, "from_bytes requires bytes"); }
        result = type_argument; check_add_root(c, node, -2);
    } else if builtin == 19 || builtin == 20 {
        if p.nodes[check_list_at(c, args, 0)].kind != N_STRING { diagnose(p, n.token, "embedded source path must be a string literal"); }
        // File loading belongs to the driver; no process invocation is allowed.
        diagnose(p, n.token, "embedded source requires driver materialization before checking");
        result = TYPE_STRING;
    } else {
        let write = builtin == 2 || builtin >= 24;
        let receiver = check_array_receiver(p, c, check_list_at(c, args, 0), write);
        if receiver < 0 { return -1; }
        var element = p.types[receiver].element; let array_kind = p.types[receiver].array_kind;
        if builtin == 21 || builtin == 22 || builtin == 23 { result = TYPE_I64; }
        if builtin == 22 && array_kind != A_LIMITED { diagnose(p, n.token, "cap is available only on limited arrays"); }
        if builtin == 16 || builtin == 17 {
            result = check_type(p, TY_SLICE, TYPE_U8, -1, -1, TF_CONST);
            if builtin == 16 { result = check_array_type(p, TYPE_U8, -1, A_GROW, 0); }
            check_copy_roots(c, node, check_list_at(c, args, 0));
            if builtin == 17 { check_add_root(c, node, check_place_root(p, check_list_at(c, args, 0))); }
        }
        if builtin == 23 {
            if array_kind == A_VAR || array_kind == A_SLICE { diagnose(p, n.token, "index_of requires a fixed-stride array owner"); }
            let ref_type = check_type(p, TY_REF, element, 0, -1, 0);
            check_value(p, c, check_list_at(c, args, 1), ref_type);
        }
        if builtin >= 24 {
            if p.types[receiver].kind != TY_ARRAY || array_kind == A_FIXED || array_kind == A_VAR {
                diagnose(p, n.token, "array operation requires a resizable or limited owner");
            }
            let shrink = builtin == 26 || builtin == 27 || builtin == 28 || builtin == 29 || builtin == 32 || builtin == 34 || builtin == 35;
            check_mutation_views(p, c, check_list_at(c, args, 0), shrink);
            if builtin == 24 || builtin == 30 || builtin == 31 {
                if element < 0 {
                    element = check_value(p, c, check_list_at(c, args, 1), -1); p.types[receiver].element = element;
                } else { check_value(p, c, check_list_at(c, args, 1), element); }
                let root = check_place_root(p, check_list_at(c, args, 0));
                if check_contains_refs(p, element, 0) { check_store_roots(p, c, root, check_list_at(c, args, 1)); }
                if builtin == 30 { result = TYPE_I64; }
                else { result = check_type(p, TY_REF, element, 0, -1, 0); check_add_root(c, node, root); }
            } else if builtin == 25 {
                let source = check_array_receiver(p, c, check_list_at(c, args, 1), false);
                if source >= 0 {
                    if element < 0 { element = p.types[source].element; p.types[receiver].element = element; }
                    else if !check_same_type(p, element, p.types[source].element) { diagnose(p, n.token, "append requires the same element type"); }
                    if check_contains_refs(p, element, 0) { check_store_roots(p, c, check_place_root(p, check_list_at(c, args, 0)), check_list_at(c, args, 1)); }
                }
            } else if builtin == 26 { result = element; check_copy_roots(c, node, check_list_at(c, args, 0)); }
            else if builtin == 27 || builtin == 28 || builtin == 32 || builtin == 33 || builtin == 34 {
                check_value(p, c, check_list_at(c, args, 1), TYPE_I64);
                if builtin == 28 && args.count == 3 { check_value(p, c, check_list_at(c, args, 2), element); }
                if builtin == 33 || builtin == 34 {
                    if element < 0 || p.types[element].kind != TY_SLICE { diagnose(p, n.token, "slice allocation requires a reusable slice pool"); }
                    result = element; check_add_root(c, node, check_place_root(p, check_list_at(c, args, 0)));
                }
            }
            if builtin >= 30 {
                let root = check_place_root(p, check_list_at(c, args, 0));
                if array_kind != A_GROW || root < 0 ||
                   (p.nodes[p.symbols[root].node].flags & F_REUSABLE) == 0 {
                    diagnose(p, n.token, "allocation builtin requires a reusable grow-only pool");
                }
            }
        }
    }
    if p.nodes[node].kind == N_CALL {
        p.nodes[node].symbol = check_builtin_symbol(p, callee.token, builtin, result);
        p.nodes[n.left].symbol = p.nodes[node].symbol;
    }
    return result;
}
recursive fn check_prepare_function(p: Program&, c: Checker&, function_node: i64) {
    if p.nodes[function_node].type_id >= 0 { return; }
    let n = p.nodes[function_node];
    let saved_scope = c.scope; let saved_function = c.function_node; let saved_slot = c.next_slot; let saved_signature = c.signature;
    let symbol = n.symbol;
    if symbol >= 0 && p.symbols[symbol].scope >= 0 { c.scope = p.symbols[symbol].scope; }
    c.function_node = function_node; c.next_slot = 0; c.signature = true;
    check_enter(c, function_node); p.nodes[function_node].scope = c.scope;
    check_ensure_generics(p, c, function_node);
    var generic = n.third >= 0; var param = n.first;
    while param >= 0 {
        var ty = p.nodes[param].type_id;
        if ty < 0 {
            if p.nodes[param].left >= 0 { ty = check_resolve_type(p, c, p.nodes[param].left); }
            else { ty = check_type(p, TY_GENERIC, -1, 0, param, 0); }
        }
        if ty >= 0 && p.types[ty].kind == TY_GENERIC { generic = true; }
        if check_has_generic(p, ty, 0) { generic = true; }
        p.nodes[param].type_id = ty;
        let ps = check_declare(p, c, param, c.scope); p.symbols[ps].type_id = ty;
        let vi = check_variable_index(c, ps); c.variables[vi].assigned = true; c.variables[vi].maybeassigned = true;
        if ty >= 0 && check_contains_refs(p, ty, 0) { check_add_root(c, -ps - 10, ps); }
        param = p.nodes[param].next;
    }
    var ret = n.left;
    while ret >= 0 { check_resolve_type(p, c, ret); ret = p.nodes[ret].next; }
    var result = -1; if n.left >= 0 { result = check_tuple(p, n.left); }
    if result < 0 && (n.flags & F_RECURSIVE) != 0 && n.right >= 0 && (p.nodes[n.right].flags & F_TAIL) == 0 { result = TYPE_VOID; }
    if n.right < 0 && result < 0 { result = TYPE_VOID; }
    let type_id = add_type(p, Type { kind: TY_FN, element: result, declaration: function_node, first: n.first, size: p.pointer_bytes, align: p.pointer_bytes });
    p.nodes[function_node].type_id = type_id;
    if symbol >= 0 { p.symbols[symbol].type_id = type_id; }
    if generic { p.nodes[function_node].flags |= F_GENERIC; }
    c.scope = saved_scope; c.function_node = saved_function; c.next_slot = saved_slot; c.signature = saved_signature;
}
recursive fn check_has_generic(p: Program&, ty: i64, depth: i64) -> bool {
    if ty < 0 { return false; }
    if depth > 64 { return false; }
    let t = p.types[ty];
    if t.kind == TY_GENERIC { return true; }
    if t.kind == TY_ARRAY || t.kind == TY_REF || t.kind == TY_SLICE { return check_has_generic(p, t.element, depth + 1); }
    if t.kind == TY_FN || t.kind == TY_TUPLE || t.kind == TY_STRUCT || t.kind == TY_ENUM {
        if check_has_generic(p, t.element, depth + 1) { return true; }
        var part = t.first;
        while part >= 0 { if check_has_generic(p, p.nodes[part].type_id, depth + 1) { return true; } part = p.nodes[part].next; }
    }
    return false;
}
recursive fn check_specialize_function(p: Program&, c: Checker&, original: i64, bindings: CheckList&, token: i64) -> i64 {
    if bindings.count == 0 { return p.nodes[original].symbol; }
    for spec in c.specializations {
        if spec.original != original || spec.binding_count != bindings.count { continue; }
        var equal = true;
        for i in 0..bindings.count { let b = check_binding_at(c, bindings, i);
            let old = c.bindings[spec.binding_start + i];
            if old.parameter != b.parameter || !check_same_type(p, old.value, b.value) { equal = false; }
        }
        if equal { return spec.symbol; }
    }
    if c.inference_depth >= 64 { diagnose(p, token, "function specialization does not reach a finite set"); return -1; }
    c.inference_depth += 1;
    let copy = check_clone(p, c, original, bindings);
    p.nodes[copy].type_id = -1; p.nodes[copy].third = -1; p.nodes[copy].origin = original;
    p.nodes[copy].flags &= ~F_GENERIC;
    let old = p.symbols[p.nodes[original].symbol];
    let symbol = p.symbols.len;
    p.symbols.push(Symbol { name_token: old.name_token, node: copy, scope: -2, flags: old.flags, owner: old.owner });
    p.nodes[copy].symbol = symbol;
    let start = c.bindings.len; for binding_index in 0..bindings.count { c.bindings.push(check_binding_at(c, bindings, binding_index)); }
    c.specializations.push(CheckSpecialization { original: original, symbol: symbol, binding_start: start, binding_count: bindings.count });
    let saved = c.scope; c.scope = p.nodes[original].scope;
    check_enter(c, old.owner);
    for b_index in 0..bindings.count { let b = check_binding_at(c, bindings, b_index);
        let binding = new_node(p, N_TYPE_PARAM, p.nodes[b.parameter].token); p.nodes[binding].type_id = b.value;
        check_declare(p, c, binding, c.scope);
    }
    p.nodes[copy].scope = c.scope;
    check_prepare_function(p, c, copy); check_function(p, c, copy);
    c.scope = saved; c.inference_depth -= 1;
    return symbol;
}

recursive fn check_find_it(p: Program&, node: i64) -> i64 {
    if node < 0 { return -1; }
    let n = p.nodes[node];
    if n.kind == N_NAME && token_is(p, n.token, "it") { return n.token; }
    if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE { return -1; }
    var child = n.first;
    while child >= 0 { let found = check_find_it(p, child); if found >= 0 { return found; } child = p.nodes[child].next; }
    let left = check_find_it(p, n.left); if left >= 0 { return left; }
    let right = check_find_it(p, n.right); if right >= 0 { return right; }
    return check_find_it(p, n.third);
}
recursive fn check_implicit_function_parameter(p: Program&, c: Checker&, node: i64, count: i64) {
    let n = p.nodes[node];
    if n.kind != N_FUNCTION_VALUE || (n.flags & F_EXPLICIT_PARAMS) != 0 || n.first >= 0 || count != 1 { return; }
    var token = check_find_it(p, n.right);
    if token < 0 { token = n.token; }
    let parameter = new_node(p, N_PARAM, token);
    p.nodes[node].first = parameter; p.nodes[node].last = parameter; p.nodes[node].type_id = -1;
    p.nodes[node].flags &= ~F_CHECKED;
    if n.symbol >= 0 { p.symbols[n.symbol].type_id = -1; }
    let saved = c.scope; c.scope = n.scope;
    check_prepare_function(p, c, node); c.scope = saved;
}

recursive fn check_call(p: Program&, c: Checker&, node: i64, expected: i64) -> i64 {
    var n = p.nodes[node];
    let original_callee = p.nodes[n.left];
    var member = false;
    if original_callee.kind == N_MEMBER {
        member = true;
        let receiver = original_callee.left;
        let name = new_node(p, N_NAME, original_callee.token);
        p.nodes[name].scope = original_callee.scope; p.nodes[name].aux = 1;
        p.nodes[receiver].next = n.first;
        p.nodes[node].first = receiver; p.nodes[node].left = name;
        n = p.nodes[node];
    }
    let callee = p.nodes[n.left];
    if callee.kind != N_NAME && callee.kind != N_FUNCTION_VALUE {
        diagnose(p, n.token, "call target must name a function or function value"); return -1;
    }
    var args = CheckList {}; var argument = n.first;
    while argument >= 0 {
        check_expression(p, c, argument, -1); check_list_push(c, args, argument); argument = p.nodes[argument].next;
    }
    if n.third >= 0 {
        check_expression(p, c, n.third, -1); check_list_push(c, args, n.third);
    }
    let builtin = check_builtin_kind(p, callee.token);
    if member && builtin >= 21 {
        let receiver_type = p.nodes[n.first].type_id;
        if receiver_type >= 0 && (p.types[receiver_type].kind == TY_ARRAY || p.types[receiver_type].kind == TY_SLICE ||
            p.types[receiver_type].kind == TY_REF && p.types[p.types[receiver_type].element].kind == TY_ARRAY) {
            return check_builtin(p, c, node, builtin);
        }
    }
    var first = -1; var bound_function = false;
    if callee.kind == N_NAME { first = check_lookup_name(p, c, n.left); }
    else { first = callee.symbol; }
    if first >= 0 && (p.symbols[first].flags & S_FUNCTION) == 0 {
        let ty = p.symbols[first].type_id;
        if ty >= 0 && p.types[ty].kind == TY_FN && p.types[ty].declaration >= 0 {
            let target = p.types[ty].declaration;
            if p.nodes[target].kind == N_FUNCTION || p.nodes[target].kind == N_FUNCTION_VALUE {
                check_implicit_function_parameter(p, c, target, args.count);
                first = p.nodes[target].symbol; bound_function = true;
            }
            else { diagnose(p, n.token, "function parameter has no bound function value"); return -1; }
        } else if (p.symbols[first].flags & S_GLOBAL) == 0 {
            diagnose(p, n.token, "local value hides this function name and cannot be called"); return -1;
        } else { first = -1; }
    }
    var candidates = CheckList {};
    var current = first;
    while current >= 0 {
        let s = p.symbols[current];
        if (s.flags & S_FUNCTION) != 0 && (s.flags & S_BUILTIN) == 0 && s.node >= 0 &&
           (bound_function || p.nodes[s.node].origin < 0) { check_list_push(c, candidates, current); }
        if bound_function { break; }
        current = s.next;
    }
    var best = -1; var best_score = 9223372036854775807; var ambiguous = false; var best_hof = false;
    var best_bindings = CheckList {};
    for candidate_index in 0..candidates.count { let candidate = check_list_at(c, candidates, candidate_index);
        let fnnode = p.symbols[candidate].node;
        check_prepare_function(p, c, fnnode);
        var bindings = CheckList {};
        var generic = p.nodes[fnnode].third; var explicit_arg = callee.first; var matches = true;
        while generic >= 0 && explicit_arg >= 0 {
            let ty = check_resolve_type(p, c, explicit_arg);
            if !check_bind_generic(p, c, generic, ty, bindings) { matches = false; }
            generic = p.nodes[generic].next; explicit_arg = p.nodes[explicit_arg].next;
        }
        if explicit_arg >= 0 { matches = false; }
        var formal = p.nodes[fnnode].first; var index = 0; var score = 0;
        while formal >= 0 && index < args.count {
            let ft = p.nodes[formal].type_id; let at = p.nodes[check_list_at(c, args, index)].type_id;
            if ft >= 0 && at >= 0 && p.types[ft].kind == TY_FN && p.types[at].kind == TY_FN {
                if !check_bind_generic(p, c, p.types[ft].declaration, at, bindings) { matches = false; }
            } else if !check_unify(p, c, ft, at, bindings) && !check_literal_tree(p, check_list_at(c, args, index), 0) { matches = false; }
            var concrete = check_substitute(p, c, ft, bindings);
            if concrete >= 0 && (p.types[concrete].kind == TY_SLICE || p.types[concrete].kind == TY_REF) &&
               (p.types[concrete].flags & TF_CONST) == 0 && check_readonly(p, c, check_list_at(c, args, index)) {
                concrete = check_const_type(p, concrete);
                if !check_bind_generic(p, c, formal, concrete, bindings) { matches = false; }
            }
            let conversion = check_conversion(p, c, check_list_at(c, args, index), at, concrete);
            if conversion < 0 { matches = false; } else { score += conversion; }
            if check_has_generic(p, ft, 0) { score += 1; }
            formal = p.nodes[formal].next; index += 1;
        }
        var hof = false;
        if formal < 0 && index + 1 == args.count {
            let extra = check_list_at(c, args, index); let extra_type = p.nodes[extra].type_id;
            if extra_type >= 0 && p.types[extra_type].kind == TY_FN {
                var unbound = -1; var unbound_count = 0; var candidate_generic = p.nodes[fnnode].third;
                while candidate_generic >= 0 {
                    var bound = false;
                    for binding_index in 0..bindings.count { let binding = check_binding_at(c, bindings, binding_index); if binding.parameter == candidate_generic { bound = true; } }
                    if !bound { unbound = candidate_generic; unbound_count += 1; }
                    candidate_generic = p.nodes[candidate_generic].next;
                }
                if unbound_count == 1 && check_bind_generic(p, c, unbound, extra_type, bindings) { hof = true; index += 1; }
            }
        }
        if index != args.count { matches = false; }
        while formal >= 0 {
            if p.nodes[formal].right < 0 { matches = false; }
            formal = p.nodes[formal].next; score += 1;
        }
        generic = p.nodes[fnnode].third;
        while generic >= 0 {
            var bound = false; for b_index in 0..bindings.count { let b = check_binding_at(c, bindings, b_index); if b.parameter == generic { bound = true; } }
            if !bound { matches = false; }
            generic = p.nodes[generic].next;
        }
        if !matches { continue; }
        if score < best_score {
            best = candidate; best_score = score; ambiguous = false; best_hof = hof;
            best_bindings = bindings;
        } else if score == best_score { ambiguous = true; }
    }
    if best < 0 {
        if builtin >= 0 && (callee.aux <= 1 || callee.integer >= 0 && p.tokens[callee.integer].kind == T_COLONCOLON) {
            return check_builtin(p, c, node, builtin);
        }
        diagnose(p, n.token, "no overload matches this call's argument types and count"); return -1;
    }
    if ambiguous { diagnose(p, n.token, "ambiguous call: equally specific overloads match"); return -1; }
    let original = p.symbols[best].node;
    best = check_specialize_function(p, c, original, best_bindings, n.token);
    if best < 0 { return -1; }
    let function_node = p.symbols[best].node;
    p.nodes[node].symbol = best; p.nodes[n.left].symbol = best;
    check_function(p, c, function_node);
    var formal = p.nodes[function_node].first; var index = 0; var last = -1;
    while formal >= 0 {
        var value = -1;
        if index < args.count { value = check_list_at(c, args, index); }
        else if p.nodes[formal].right >= 0 {
            var empty = CheckList {};
            value = check_clone(p, c, p.nodes[formal].right, empty);
            if last < 0 { p.nodes[node].first = value; } else { p.nodes[last].next = value; }
            check_list_push(c, args, value);
        }
        if value >= 0 {
            check_value(p, c, value, p.nodes[formal].type_id);
            if value == n.third {
                if last < 0 { p.nodes[node].first = value; } else { p.nodes[last].next = value; }
                p.nodes[node].third = -1;
            }
            last = value;
        }
        formal = p.nodes[formal].next; index += 1;
    }
    if best_hof {
        if last >= 0 { p.nodes[last].next = -1; } else { p.nodes[node].first = -1; }
        p.nodes[node].third = -1;
    }
    p.nodes[node].last = last;
    let type_id = p.symbols[best].type_id;
    let result = p.types[type_id].element;
    let roots_end = c.return_roots.len;
    for i in 0..roots_end {
        let rr = c.return_roots[i];
        if rr.function_node != function_node { continue; }
        if rr.root < 0 { check_add_root(c, node, rr.root); continue; }
        let root_symbol = p.symbols[rr.root];
        if root_symbol.owner == function_node && (root_symbol.flags & S_PARAMETER) != 0 {
            let slot = root_symbol.slot;
            if slot >= 0 && slot < args.count {
                check_copy_roots(c, node, check_list_at(c, args, slot));
                if check_addressable(p, check_list_at(c, args, slot)) { check_add_root(c, node, check_place_root(p, check_list_at(c, args, slot))); }
            }
        } else { check_add_root(c, node, rr.root); }
    }
    let effects_end = c.effects.len;
    for i in 0..effects_end {
        let effect = c.effects[i];
        if effect.function_node != function_node { continue; }
        let root = p.symbols[effect.root];
        if root.owner == function_node && (root.flags & S_PARAMETER) != 0 && root.slot >= 0 && root.slot < args.count {
            if effect.kind == 1 || effect.kind == 2 { check_mutation_views(p, c, check_list_at(c, args, root.slot), effect.kind == 2); }
            else { check_note_effect(c, check_place_root(p, check_list_at(c, args, root.slot)), effect.kind); }
        } else { check_note_effect(c, effect.root, effect.kind); }
    }
    if (p.nodes[function_node].flags & F_NONLOCAL) != 0 && c.function_node >= 0 { p.nodes[c.function_node].flags |= F_NONLOCAL; }
    return result;
}

fn check_flow_save(p: Program&, c: Checker&, out: CheckSpan&) {
    out.first = c.flow_work.len; out.count = 0;
    for v in c.variables {
        let scope = p.symbols[v.symbol].scope;
        if scope < 0 || !check_visible(c, scope, c.scope) { continue; }
        c.flow_work.push(CheckFlow { symbol: v.symbol, assigned: v.assigned, maybeassigned: v.maybeassigned, narrowed: v.narrowed });
        out.count += 1;
    }
}
fn check_flow_restore(c: Checker&, flow: CheckSpan&) {
    for flow_index in flow.first..flow.first + flow.count { let saved = c.flow_work[flow_index];
        let vi = check_variable_index(c, saved.symbol);
        if vi >= 0 { c.variables[vi].assigned = saved.assigned; c.variables[vi].maybeassigned = saved.maybeassigned; c.variables[vi].narrowed = saved.narrowed; }
    }
}
fn check_flow_join(p: Program&, c: Checker&, left: CheckSpan&, right: CheckSpan&, left_reachable: bool, right_reachable: bool) {
    if !left_reachable { check_flow_restore(c, right); return; }
    if !right_reachable { check_flow_restore(c, left); return; }
    for left_index in left.first..left.first + left.count { let a = c.flow_work[left_index];
        for right_index in right.first..right.first + right.count { let b = c.flow_work[right_index];
            if a.symbol != b.symbol { continue; }
            let vi = check_variable_index(c, a.symbol);
            if vi >= 0 {
                c.variables[vi].assigned = a.assigned && b.assigned;
                c.variables[vi].maybeassigned = a.maybeassigned || b.maybeassigned;
                c.variables[vi].narrowed = -1;
                if check_same_type(p, a.narrowed, b.narrowed) { c.variables[vi].narrowed = a.narrowed; }
            }
        }
    }
}
fn check_join_type(p: Program&, c: Checker&, left_node: i64, left: i64, right_node: i64, right: i64, token: i64) -> i64 {
    if left < 0 { return right; }
    if right < 0 { return left; }
    if check_same_type(p, left, right) { return left; }
    if left_node >= 0 && check_conversion(p, c, left_node, left, right) >= 0 {
        check_expect(p, c, left_node, left, right); return right;
    }
    if right_node >= 0 && check_conversion(p, c, right_node, right, left) >= 0 {
        check_expect(p, c, right_node, right, left); return left;
    }
    diagnose(p, token, "control-flow branches produce incompatible types"); return -1;
}
recursive fn check_predeclare(p: Program&, c: Checker&, first: i64) {
    var node = first;
    while node >= 0 {
        let n = p.nodes[node];
        if n.kind == N_NAMESPACE {
            let previous = check_lookup_scope(p, n.token, c.scope);
            var namespace_scope = -1;
            if previous >= 0 && p.symbols[previous].node >= 0 && p.nodes[p.symbols[previous].node].kind == N_NAMESPACE {
                namespace_scope = p.nodes[p.symbols[previous].node].scope; p.nodes[node].symbol = previous;
            } else {
                check_declare(p, c, node, c.scope);
                let saved = check_enter(c, c.function_node); namespace_scope = c.scope;
                c.scopes[namespace_scope].namespace_node = node; c.scope = saved;
            }
            p.nodes[node].scope = namespace_scope;
            let saved = c.scope; c.scope = namespace_scope;
            check_predeclare(p, c, n.first); c.scope = saved;
        } else if n.kind == N_EXTERN { check_predeclare(p, c, n.first); }
        else if n.kind == N_FUNCTION || n.kind == N_STRUCT || n.kind == N_ENUM || n.kind == N_ALIAS ||
                n.kind == N_VARIABLE && c.function_node < 0 {
            if n.kind == N_STRUCT || n.kind == N_ENUM {
                var kind = TY_STRUCT; if n.kind == N_ENUM { kind = TY_ENUM; }
                let ty = add_type(p, Type { kind: kind, declaration: node, first: n.first, name_token: n.token });
                p.nodes[node].type_id = ty;
            }
            check_declare(p, c, node, c.scope);
        }
        node = n.next;
    }
}
recursive fn check_block(p: Program&, c: Checker&, node: i64, expected: i64) -> i64 {
    let n = p.nodes[node]; let saved = check_enter(c, c.function_node);
    p.nodes[node].scope = c.scope;
    var early = false;
    if (n.flags & (F_EARLY | F_NONLOCAL)) != 0 {
        c.loop_stack.push(CheckLoop { node: node, scope: c.scope, function_node: c.function_node }); early = true;
    }
    check_predeclare(p, c, n.first);
    var child = n.first; var result = TYPE_VOID;
    while child >= 0 {
        let item = p.nodes[child];
        if !c.reachable && item.kind != N_FUNCTION && item.kind != N_STRUCT && item.kind != N_ENUM && item.kind != N_ALIAS {
            diagnose(p, item.token, "unreachable statement");
        }
        if (item.flags & F_TAIL) != 0 {
            var tail_expected = expected;
            if c.function_node >= 0 && p.nodes[c.function_node].right == node && expected >= 0 &&
               (p.types[expected].kind == TY_REF || p.types[expected].kind == TY_SLICE) &&
               (item.kind == N_NAME || item.kind == N_CALL || item.kind == N_SLICE) {
                check_expression(p, c, child, -1);
                if check_readonly(p, c, child) {
                    tail_expected = check_const_type(p, expected); c.result_type = tail_expected;
                    p.types[p.nodes[c.function_node].type_id].element = tail_expected;
                }
            }
            result = check_value(p, c, child, tail_expected); check_copy_roots(c, node, child);
        } else { check_statement(p, c, child); }
        child = item.next;
    }
    if (n.flags & F_TAIL) == 0 && expected >= 0 && expected != TYPE_VOID && c.reachable {
        diagnose(p, n.token, "value-producing block must end with an expression");
    }
    if early {
        let li = c.loop_stack.len - 1; let loop_state = c.loop_stack[li];
        if loop_state.breaks { result = check_join_type(p, c, node, result, -1, loop_state.result, n.token); c.reachable = true; }
        c.loop_stack.pop();
    }
    let roots_end = c.roots.len;
    for i in 0..roots_end {
        let r = c.roots[i];
        if r.value == node && r.root >= 0 && p.symbols[r.root].owner == c.function_node &&
           !check_visible(c, p.symbols[r.root].scope, saved) {
            diagnose(p, n.token, "block result retains a reference to storage that ends with the block");
        }
    }
    c.scope = saved;
    if !c.reachable { return -1; }
    return result;
}
recursive fn check_if(p: Program&, c: Checker&, node: i64, expected: i64) -> i64 {
    let n = p.nodes[node]; check_condition(p, c, n.left);
    var entry = CheckSpan {}; check_flow_save(p, c, entry);
    let reachable = c.reachable;
    check_narrow_condition(p, c, n.left, true);
    let left = check_expression(p, c, n.right, expected); let left_reachable = c.reachable;
    var left_flow = CheckSpan {}; check_flow_save(p, c, left_flow);
    check_flow_restore(c, entry); c.reachable = reachable;
    check_narrow_condition(p, c, n.left, false);
    var right = TYPE_VOID;
    if n.third >= 0 { right = check_expression(p, c, n.third, expected); }
    else if expected >= 0 && expected != TYPE_VOID { diagnose(p, n.token, "if used as a value requires an else branch"); }
    let right_reachable = c.reachable;
    var right_flow = CheckSpan {}; check_flow_save(p, c, right_flow);
    check_flow_join(p, c, left_flow, right_flow, left_reachable, right_reachable);
    c.reachable = left_reachable || right_reachable;
    check_copy_roots(c, node, n.right); if n.third >= 0 { check_copy_roots(c, node, n.third); }
    if expected == TYPE_VOID { return TYPE_VOID; }
    if !left_reachable { return right; }
    if !right_reachable { return left; }
    return check_join_type(p, c, n.right, left, n.third, right, n.token);
}

recursive fn check_expression(p: Program&, c: Checker&, node: i64, expected: i64) -> i64 {
    if node < 0 { return TYPE_VOID; }
    let n = p.nodes[node];
    if (n.flags & F_CHECKED) != 0 && n.type_id >= 0 {
        if (n.kind == N_ARRAY || n.kind == N_FILL) && expected >= 0 { return check_array(p, c, node, expected); }
        return n.type_id;
    }
    p.nodes[node].scope = c.scope;
    if c.reachable && n.kind != N_FUNCTION_VALUE { p.nodes[node].flags |= F_REACHABLE; }
    var result = -1;
    if n.kind == N_INTEGER { result = TYPE_I64; if (n.flags & F_UNSIGNED) != 0 { result = TYPE_U64; } }
    else if n.kind == N_FLOAT { result = TYPE_F64; }
    else if n.kind == N_BOOL { result = TYPE_BOOL; }
    else if n.kind == N_STRING {
        result = TYPE_STRING;
        if expected >= 0 && p.types[expected].kind == TY_ARRAY && p.types[expected].element == TYPE_U8 {
            let length = p.tokens[n.token].text_len;
            if p.types[expected].array_kind == A_FIXED && p.types[expected].count != length {
                diagnose(p, n.token, "string literal length does not match the fixed array");
            }
            if p.types[expected].array_kind == A_LIMITED && p.types[expected].count >= 0 && p.types[expected].count < length {
                diagnose(p, n.token, "string literal exceeds the limited array capacity");
            }
            result = expected;
        }
        check_add_root(c, node, -1);
    } else if n.kind == N_NULL {
        if expected >= 0 && p.types[expected].kind == TY_REF && (p.types[expected].flags & TF_OPTIONAL) != 0 { result = expected; }
        else { result = check_type(p, TY_REF, TYPE_VOID, 0, -1, TF_OPTIONAL); }
    } else if n.kind == N_NAME {
        if p.tokens[n.token].kind == T_SELF { diagnose(p, n.token, "self requires a relative reference field initializer"); }
        else {
            let symbol = check_lookup_name(p, c, node);
            if symbol < 0 { diagnose(p, n.token, "unknown name"); }
            else {
                p.nodes[node].symbol = symbol;
                let s = p.symbols[symbol];
                if (s.flags & S_TYPE) != 0 { diagnose(p, n.token, "type name is not a runtime value"); }
                else if (s.flags & S_FUNCTION) != 0 {
                    let declaration = s.node;
                    if declaration >= 0 { check_prepare_function(p, c, declaration); result = p.nodes[declaration].type_id; }
                } else {
                    if (s.flags & S_GLOBAL) != 0 && s.node >= 0 && (p.nodes[s.node].flags & F_CHECKED) == 0 { check_variable(p, c, s.node); }
                    result = p.symbols[symbol].type_id;
                    let vi = check_variable_index(c, symbol);
                    if vi >= 0 && c.variables[vi].narrowed >= 0 { result = c.variables[vi].narrowed; }
                    if vi >= 0 && !c.variables[vi].assigned { diagnose(p, n.token, "value is read before it is definitely assigned"); }
                    check_capture(p, c, symbol); check_copy_roots(c, node, -symbol - 10);
                }
            }
        }
    } else if n.kind == N_UNARY {
        if n.integer == T_BITAND {
            let ty = check_expression(p, c, n.left, -1);
            if !check_addressable(p, n.left) { diagnose(p, n.token, "reference requires addressable storage"); }
            var flags = 0; if check_readonly(p, c, n.left) { flags |= TF_CONST; }
            result = check_type(p, TY_REF, ty, 0, -1, flags);
            check_add_root(c, node, check_place_root(p, n.left));
        } else if n.integer == T_MUL {
            let ty = check_expression(p, c, n.left, -1);
            if ty < 0 || p.types[ty].kind != TY_REF { diagnose(p, n.token, "dereference requires a reference"); }
            else { result = p.types[ty].element; check_copy_roots(c, node, n.left); }
        } else if n.integer == T_NOT {
            check_condition(p, c, n.left); result = TYPE_BOOL;
        } else {
            let ty = check_value(p, c, n.left, -1);
            if !check_numeric(ty) { diagnose(p, n.token, "numeric unary operator requires a number"); }
            if n.integer == T_BITNOT && !check_integer(ty) { diagnose(p, n.token, "bitwise complement requires an integer"); }
            if n.integer != T_MINUS && n.integer != T_BITNOT { diagnose(p, n.token, "invalid unary operator"); }
            result = ty;
            if n.integer == T_MINUS && p.nodes[n.left].kind == N_INTEGER &&
               p.nodes[n.left].integer == -9223372036854775808 && (p.nodes[n.left].flags & F_UNSIGNED) != 0 {
                p.nodes[node].kind = N_INTEGER; p.nodes[node].left = -1;
                p.nodes[node].integer = -9223372036854775808; result = TYPE_I64;
            }
        }
    } else if n.kind == N_BINARY {
        let op = n.integer;
        if op == T_ANDAND || op == T_OROR {
            check_condition(p, c, n.left);
            var before = CheckSpan {}; check_flow_save(p, c, before);
            let reachable = c.reachable; check_narrow_condition(p, c, n.left, op == T_ANDAND); check_condition(p, c, n.right);
            var after = CheckSpan {}; check_flow_save(p, c, after);
            check_flow_join(p, c, before, after, reachable, c.reachable); c.reachable = reachable;
            result = TYPE_BOOL;
        } else {
            var lt = -1; var rt = -1;
            let identity = op == T_DOTEQ || op == T_DOTNEQ;
            let null_comparison = (op == T_EQ || op == T_NEQ) && (p.nodes[n.left].kind == N_NULL || p.nodes[n.right].kind == N_NULL);
            if identity || null_comparison {
                lt = check_expression(p, c, n.left, -1); rt = check_expression(p, c, n.right, -1);
                if identity && lt >= 0 && p.types[lt].kind == TY_REF && rt >= 0 && p.types[rt].kind != TY_REF {
                    rt = check_expect(p, c, n.right, rt, lt);
                }
            } else { lt = check_value(p, c, n.left, -1); rt = check_value(p, c, n.right, -1); }
            if lt >= 0 && rt >= 0 {
                let comparison = op == T_EQ || op == T_NEQ || op == T_LT || op == T_LTEQ || op == T_GT || op == T_GTEQ || op == T_DOTEQ || op == T_DOTNEQ;
                if check_numeric(lt) && check_numeric(rt) {
                    if !check_same_type(p, lt, rt) && op != T_SHL && op != T_SHR {
                        let lr = check_conversion(p, c, n.left, lt, rt); let rl = check_conversion(p, c, n.right, rt, lt);
                        if lr >= 0 && (rl < 0 || lr <= rl) { check_expect(p, c, n.left, lt, rt); lt = rt; }
                        else if rl >= 0 { check_expect(p, c, n.right, rt, lt); rt = lt; }
                        else { diagnose(p, n.token, "numeric operands require compatible types"); }
                    }
                    if (op == T_BITAND || op == T_BITOR || op == T_XOR || op == T_SHL || op == T_SHR || op == T_MOD) &&
                       (!check_integer(lt) || !check_integer(rt)) { diagnose(p, n.token, "integer operator requires integer operands"); }
                    if op == T_SHL || op == T_SHR {
                        let count = check_constant(p, c, n.right, 0);
                        if count.valid && (count.value < 0 || count.value >= check_integer_bits(lt)) { diagnose(p, n.token, "shift count is outside the operand width"); }
                    }
                    result = lt;
                } else if comparison && (check_same_type(p, lt, rt) || p.nodes[n.left].kind == N_NULL || p.nodes[n.right].kind == N_NULL) {
                    if (op == T_LT || op == T_LTEQ || op == T_GT || op == T_GTEQ) && lt != TYPE_BOOL {
                        diagnose(p, n.token, "ordered comparison requires numeric operands");
                    }
                } else { diagnose(p, n.token, "operator does not accept these operand types"); }
                if comparison { result = TYPE_BOOL; }
            }
        }
    } else if n.kind == N_CALL { result = check_call(p, c, node, expected); }
    else if n.kind == N_MEMBER {
        var enum_type = -1;
        if p.nodes[n.left].kind == N_NAME {
            let symbol = check_lookup_name(p, c, n.left);
            if symbol >= 0 && (p.symbols[symbol].flags & S_TYPE) != 0 { enum_type = p.symbols[symbol].type_id; }
        }
        if enum_type >= 0 && p.types[enum_type].kind == TY_ENUM {
            check_layout_nominal(p, c, enum_type);
            var variant = p.types[enum_type].first;
            while variant >= 0 {
                if same_name(p, p.nodes[variant].token, n.token) {
                    if p.nodes[variant].first >= 0 { diagnose(p, n.token, "enum variant payload requires a constructor"); }
                    p.nodes[node].kind = N_RECORD; p.nodes[node].left = -1; p.nodes[node].symbol = variant;
                    result = p.nodes[variant].type_id; break;
                }
                variant = p.nodes[variant].next;
            }
            if result < 0 { diagnose(p, n.token, "unknown enum variant"); }
        } else {
            var ty = check_expression(p, c, n.left, -1);
            if ty >= 0 && p.types[ty].kind == TY_REF {
                let element = p.types[ty].element; check_wrap_unary(p, n.left, T_MUL, element); ty = element;
            }
            let builtin = check_builtin_kind(p, n.token);
            if ty >= 0 && (p.types[ty].kind == TY_ARRAY || p.types[ty].kind == TY_SLICE) && (builtin == 21 || builtin == 22) {
                let name = new_node(p, N_NAME, n.token);
                p.nodes[node].kind = N_CALL; p.nodes[node].first = n.left; p.nodes[node].last = n.left;
                p.nodes[node].left = name; p.nodes[node].right = -1;
                result = check_builtin(p, c, node, builtin);
            } else if ty >= 0 && p.types[ty].kind == TY_STRUCT {
                check_layout_nominal(p, c, ty);
                var field = p.types[ty].first;
                while field >= 0 {
                    if same_name(p, p.nodes[field].token, n.token) { result = p.nodes[field].type_id; p.nodes[node].symbol = field; break; }
                    field = p.nodes[field].next;
                }
                if result < 0 { diagnose(p, n.token, "struct has no field of this name"); }
                check_copy_roots(c, node, n.left);
            } else { diagnose(p, n.token, "member access requires an aggregate, array or enum type"); }
        }
    } else if n.kind == N_INDEX || n.kind == N_SLICE {
        var ty = check_expression(p, c, n.left, -1);
        if ty >= 0 && p.types[ty].kind == TY_REF {
            let element = p.types[ty].element; check_wrap_unary(p, n.left, T_MUL, element); ty = element;
        }
        if ty < 0 || p.types[ty].kind != TY_ARRAY && p.types[ty].kind != TY_SLICE {
            diagnose(p, n.token, "index or slice requires an array or slice");
        } else {
            let array = p.types[ty];
            if n.right >= 0 { let it = check_value(p, c, n.right, -1); if !check_integer(it) { diagnose(p, n.token, "array index must be an integer"); } }
            if n.third >= 0 { let it = check_value(p, c, n.third, -1); if !check_integer(it) { diagnose(p, n.token, "slice bound must be an integer"); } }
            let start = check_constant(p, c, n.right, 0); let end = check_constant(p, c, n.third, 0);
            if start.valid && start.value < 0 { diagnose(p, n.token, "array index must be nonnegative"); }
            if n.kind == N_INDEX {
                result = array.element;
                if start.valid && array.count >= 0 && array.array_kind == A_FIXED {
                    if start.value >= array.count { diagnose(p, n.token, "constant index is outside the fixed array"); }
                    else if start.value >= 0 { p.nodes[node].flags |= F_BOUNDS_PROVEN; }
                }
            } else {
                var flags = array.flags & TF_CONST; if check_readonly(p, c, n.left) { flags |= TF_CONST; }
                result = check_type(p, TY_SLICE, array.element, -1, -1, flags);
                if start.valid && end.valid && start.value > end.value { diagnose(p, n.token, "slice start exceeds its end"); }
                if end.valid && end.value < 0 || end.valid && array.array_kind == A_FIXED && array.count >= 0 && end.value > array.count {
                    diagnose(p, n.token, "slice bound is outside the fixed array");
                }
                check_add_root(c, node, check_place_root(p, n.left));
            }
            check_copy_roots(c, node, n.left);
        }
    } else if n.kind == N_ARRAY || n.kind == N_FILL { result = check_array(p, c, node, expected); }
    else if n.kind == N_RECORD { result = check_record(p, c, node, expected); }
    else if n.kind == N_CAST {
        let source = check_value(p, c, n.left, -1); let destination = check_resolve_type(p, c, n.right);
        if source >= 0 && destination >= 0 {
            let sk = p.types[source].kind; let dk = p.types[destination].kind;
            if check_numeric(source) && check_numeric(destination) || source == TYPE_BOOL && check_integer(destination) ||
               check_integer(source) && destination == TYPE_BOOL || check_conversion(p, c, n.left, source, destination) >= 0 {
                result = destination;
            } else if (n.flags & F_UNSIGNED) != 0 && sk == TY_REF && dk == TY_REF { result = destination; }
            else { diagnose(p, n.token, "explicit cast is not defined for these types"); }
            check_copy_roots(c, node, n.left);
        }
    } else if n.kind == N_IF { result = check_if(p, c, node, expected); }
    else if n.kind == N_BLOCK { result = check_block(p, c, node, expected); }
    else if n.kind == N_MATCH { result = check_match(p, c, node, expected); }
    else if n.kind == N_LOOP || n.kind == N_FOR || n.kind == N_WHILE { result = check_loop(p, c, node, expected); }
    else if n.kind == N_FUNCTION_VALUE {
        if p.nodes[node].symbol < 0 { check_declare(p, c, node, -2); }
        check_prepare_function(p, c, node); result = p.nodes[node].type_id;
        if expected >= 0 && p.types[expected].kind == TY_FN && p.types[expected].first >= 0 {
            var formal = p.nodes[node].first; var context = p.types[expected].first;
            while formal >= 0 && context >= 0 {
                if p.nodes[formal].left < 0 { p.nodes[formal].type_id = p.nodes[context].type_id; }
                formal = p.nodes[formal].next; context = p.nodes[context].next;
            }
            if formal >= 0 || context >= 0 { diagnose(p, n.token, "function value parameter count does not match context"); }
        }
    } else if n.kind == N_RETURN { check_return(p, c, node); result = TYPE_VOID; }
    else if n.kind == N_BREAK || n.kind == N_CONTINUE { check_jump(p, c, node); result = TYPE_VOID; }
    else if n.kind == N_ASSIGN || n.kind == N_MULTI_ASSIGN { check_assignment(p, c, node); result = TYPE_VOID; }
    else if n.kind == N_RANGE {
        let left = check_value(p, c, n.left, -1); let right = check_value(p, c, n.right, left);
        if !check_integer(left) || !check_integer(right) { diagnose(p, n.token, "range bounds must be integers"); }
        result = left;
    } else if n.kind == N_TUPLE {
        var child = n.first;
        while child >= 0 { check_value(p, c, child, -1); child = p.nodes[child].next; }
        result = check_tuple(p, n.first);
    } else if n.kind == N_CONST_FOR { result = check_const_for(p, c, node, expected); }
    else if n.kind == N_EMPTY { result = TYPE_VOID; }
    else if n.kind == N_EXPR_STMT { check_expression(p, c, n.left, TYPE_VOID); result = TYPE_VOID; }
    else { diagnose(p, n.token, "syntax node is not a valid expression"); }
    p.nodes[node].type_id = result;
    if n.kind != N_FUNCTION_VALUE { p.nodes[node].flags |= F_CHECKED; }
    return result;
}

recursive fn check_loop(p: Program&, c: Checker&, node: i64, expected: i64) -> i64 {
    let n = p.nodes[node]; let saved = check_enter(c, c.function_node);
    p.nodes[node].scope = c.scope;
    var entry = CheckSpan {}; check_flow_save(p, c, entry);
    if n.kind == N_WHILE { check_condition(p, c, n.left); }
    if n.kind == N_FOR {
        let source = check_expression(p, c, n.left, -1); var element = TYPE_I64;
        if source >= 0 {
            var ty = source; if p.types[ty].kind == TY_REF { ty = p.types[ty].element; }
            if p.nodes[n.left].kind == N_RANGE || check_integer(ty) { element = ty; }
            else if p.types[ty].kind == TY_ARRAY || p.types[ty].kind == TY_SLICE { element = p.types[ty].element; }
            else { diagnose(p, n.token, "for source must be a range, integer count, array or slice"); element = -1; }
        }
        var binding = n.first; var index = 0;
        while binding >= 0 {
            var ty = element;
            if index > 0 { ty = TYPE_I64; }
            if (p.nodes[binding].flags & F_REFERENCE) != 0 {
                if index > 0 || p.nodes[n.left].kind == N_RANGE || check_integer(source) {
                    diagnose(p, p.nodes[binding].token, "reference iteration requires array or slice elements");
                }
                ty = check_type(p, TY_REF, ty, 0, -1, 0);
            }
            if p.nodes[binding].left >= 0 {
                let annotation = check_resolve_type(p, c, p.nodes[binding].left);
                if !check_same_type(p, ty, annotation) { diagnose(p, p.nodes[binding].token, "for binding annotation does not match its iterator"); }
                ty = annotation;
            }
            p.nodes[binding].type_id = ty;
            let symbol = check_declare(p, c, binding, c.scope); p.symbols[symbol].type_id = ty;
            let vi = check_variable_index(c, symbol); c.variables[vi].assigned = true; c.variables[vi].maybeassigned = true;
            c.variables[vi].readonly = (p.nodes[binding].flags & F_REFERENCE) == 0;
            if (p.nodes[binding].flags & F_REFERENCE) != 0 {
                check_add_root(c, -symbol - 10, check_place_root(p, n.left));
            }
            index += 1; binding = p.nodes[binding].next;
        }
    }
    let li = c.loop_stack.len;
    c.loop_stack.push(CheckLoop { node: node, scope: c.scope, function_node: c.function_node });
    check_expression(p, c, n.right, TYPE_VOID);
    let loop_state = c.loop_stack[li]; c.loop_stack.pop();
    check_flow_restore(c, entry);
    c.reachable = true;
    if n.kind == N_LOOP && !loop_state.breaks { c.reachable = false; }
    if n.kind == N_WHILE {
        let condition = check_constant(p, c, n.left, 0);
        if condition.valid && condition.value != 0 && !loop_state.breaks { c.reachable = false; }
    }
    c.scope = saved;
    if n.kind == N_LOOP && loop_state.breaks {
        if expected >= 0 && loop_state.result >= 0 && expected != TYPE_VOID && !check_same_type(p, loop_state.result, expected) {
            diagnose(p, n.token, "loop break values do not match the expected result");
        }
        return loop_state.result;
    }
    return TYPE_VOID;
}
recursive fn check_jump(p: Program&, c: Checker&, node: i64) {
    let n = p.nodes[node]; var li = c.loop_stack.len - 1;
    while li >= 0 {
        let target = c.loop_stack[li];
        if target.function_node == c.function_node && (p.nodes[target.node].flags & F_NONLOCAL) != 0 &&
           p.nodes[target.node].kind == N_BLOCK {
            diagnose(p, n.token, "break or continue cannot cross a const for expansion"); return;
        }
        if target.function_node == c.function_node &&
           (n.kind != N_CONTINUE || (p.nodes[target.node].flags & F_EARLY) == 0) { break; }
        li -= 1;
    }
    if li < 0 { diagnose(p, n.token, "break or continue has no enclosing target in this function"); return; }
    let target = c.loop_stack[li]; p.nodes[node].symbol = target.node;
    if n.kind == N_BREAK {
        var ty = TYPE_VOID;
        if n.left >= 0 { ty = check_value(p, c, n.left, target.result); }
        if p.nodes[target.node].kind != N_LOOP && (p.nodes[target.node].flags & F_EARLY) == 0 && n.left >= 0 {
            diagnose(p, n.token, "only loop expressions and early blocks accept a break value");
        }
        if target.result < 0 { c.loop_stack[li].result = ty; }
        else if !check_same_type(p, target.result, ty) { diagnose(p, n.token, "break values have incompatible types"); }
        c.loop_stack[li].breaks = true;
        if n.left >= 0 { check_copy_roots(c, target.node, n.left); }
    }
    c.reachable = false;
}
struct CheckInterval { low: i64, high: i64, next: i64 = -1 }
recursive fn check_match(p: Program&, c: Checker&, node: i64, expected: i64) -> i64 {
    let n = p.nodes[node]; let source = check_value(p, c, n.left, -1);
    if source < 0 { return -1; }
    let enum_match = p.types[source].kind == TY_ENUM;
    if !enum_match && !check_integer(source) && source != TYPE_BOOL { diagnose(p, n.token, "match requires an integer, bool or enum"); }
    if enum_match { check_layout_nominal(p, c, source); }
    check_expand_children(p, c, node);
    var entry = CheckSpan {}; check_flow_save(p, c, entry);
    var merged = CheckSpan {}; var merged_reachable = false; var any_reachable = false;
    var result = -1; var result_node = -1; var wildcard = false;
    var intervals = CheckList {}; var tags = CheckList {};
    var arm = p.nodes[node].first;
    while arm >= 0 {
        let a = p.nodes[arm];
        if a.kind != N_ARM { diagnose(p, a.token, "match expansion did not produce an arm"); arm = a.next; continue; }
        check_flow_restore(c, entry); c.reachable = true;
        let saved = check_enter(c, c.function_node);
        p.nodes[arm].scope = c.scope;
        let pattern = p.nodes[a.left];
        if wildcard { diagnose(p, a.token, "match arm is unreachable after the wildcard"); }
        if (pattern.flags & F_DEFAULT) != 0 { wildcard = true; }
        var item = pattern.first; var payload = -1;
        while item >= 0 {
            let pat = p.nodes[item];
            if enum_match {
                var variant = p.types[source].first;
                while variant >= 0 { if same_name(p, p.nodes[variant].token, pat.token) { break; } variant = p.nodes[variant].next; }
                if variant < 0 { diagnose(p, pat.token, "match pattern names no variant of this enum"); }
                else {
                    let tag = p.nodes[variant].integer;
                    for previous_index in 0..tags.count { let previous = check_list_at(c, tags, previous_index); if previous == tag { diagnose(p, pat.token, "duplicate enum match pattern"); } }
                    check_list_push(c, tags, tag); p.nodes[item].symbol = variant; p.nodes[item].integer = tag;
                    p.nodes[item].type_id = source; p.nodes[item].flags |= F_CHECKED;
                    payload = p.nodes[variant].type_id;
                }
            } else {
                var low = check_constant(p, c, item, 0); var high = low;
                if pat.kind == N_RANGE {
                    low = check_constant(p, c, pat.left, 0); high = check_constant(p, c, pat.right, 0);
                }
                if !low.valid || !high.valid { diagnose(p, pat.token, "match pattern must be a constant integer or range"); }
                else {
                    if low.value > high.value { diagnose(p, pat.token, "match range lower bound exceeds its upper bound"); }
                    if check_integer(source) && (low.value < check_min(source) || high.value > check_max(source)) {
                        diagnose(p, pat.token, "match pattern is outside the scrutinee type");
                    }
                    for previous_index in 0..intervals.count { let previous = check_interval_at(c, intervals, previous_index);
                        if low.value <= previous.high && previous.low <= high.value { diagnose(p, pat.token, "overlapping match patterns"); }
                    }
                    check_interval_push(c, intervals, CheckInterval { low: low.value, high: high.value });
                    if pat.kind == N_RANGE {
                        p.nodes[pat.left].kind = N_INTEGER; p.nodes[pat.left].integer = low.value; p.nodes[pat.left].type_id = source;
                        p.nodes[pat.right].kind = N_INTEGER; p.nodes[pat.right].integer = high.value; p.nodes[pat.right].type_id = source;
                    } else { p.nodes[item].kind = N_INTEGER; p.nodes[item].integer = low.value; }
                    p.nodes[item].type_id = source; p.nodes[item].flags |= F_CHECKED;
                }
            }
            item = pat.next;
        }
        if pattern.left >= 0 {
            let binder = pattern.left;
            if !enum_match || payload < 0 { diagnose(p, pattern.token, "payload binding requires one enum variant pattern"); }
            else {
                var ty = payload;
                if (p.nodes[binder].flags & F_REFERENCE) != 0 {
                    if check_size_class(p, source, 0) == 2 { diagnose(p, pattern.token, "resizable enum payloads cannot bind by reference"); }
                    ty = check_type(p, TY_REF, payload, 0, -1, 0);
                }
                p.nodes[binder].type_id = ty;
                let symbol = check_declare(p, c, binder, c.scope); p.symbols[symbol].type_id = ty;
                let vi = check_variable_index(c, symbol); c.variables[vi].assigned = true; c.variables[vi].maybeassigned = true;
                c.variables[vi].readonly = (p.nodes[binder].flags & F_REFERENCE) == 0;
                if (p.nodes[binder].flags & F_REFERENCE) != 0 { check_add_root(c, -symbol - 10, check_place_root(p, n.left)); }
            }
        }
        if a.third >= 0 { check_condition(p, c, a.third); }
        let ty = check_expression(p, c, a.right, expected);
        if c.reachable {
            result = check_join_type(p, c, result_node, result, a.right, ty, n.token); result_node = a.right;
            var branch = CheckSpan {}; check_flow_save(p, c, branch);
            if !merged_reachable { merged = branch; merged_reachable = true; }
            else {
                check_flow_join(p, c, merged, branch, true, true); check_flow_save(p, c, merged);
            }
            any_reachable = true;
        }
        check_copy_roots(c, node, a.right);
        c.scope = saved; arm = a.next;
    }
    var exhaustive = wildcard;
    if enum_match && tags.count == p.types[source].count { exhaustive = true; }
    if !enum_match && !wildcard {
        var minimum = check_min(source); var maximum = check_max(source);
        if source == TYPE_BOOL { minimum = 0; maximum = 1; }
        var covered = minimum; var started = false; var progress = true;
        while progress {
            progress = false;
            for interval_index in 0..intervals.count { let interval = check_interval_at(c, intervals, interval_index);
                if !started && interval.low <= minimum && interval.high >= minimum { covered = interval.high; started = true; progress = true; }
                else if started && covered != maximum && interval.low <= covered + 1 && interval.high > covered {
                    covered = interval.high; progress = true;
                }
            }
        }
        if started && covered >= maximum { exhaustive = true; }
    }
    if !exhaustive { diagnose(p, n.token, "match does not cover every possible value"); }
    check_flow_restore(c, merged); c.reachable = any_reachable;
    if expected == TYPE_VOID { return TYPE_VOID; }
    return result;
}
recursive fn check_return(p: Program&, c: Checker&, node: i64) {
    let n = p.nodes[node]; var target = c.function_node;
    if target >= 0 && p.nodes[target].kind == N_FUNCTION_VALUE && (n.flags & F_IMPLICIT_RETURN) == 0 && n.left < 0 {
        let function_symbol = p.nodes[target].symbol;
        if function_symbol >= 0 && p.symbols[function_symbol].owner >= 0 { target = p.symbols[function_symbol].owner; }
        if target != c.function_node { p.nodes[c.function_node].flags |= F_NONLOCAL; }
    }
    if target < 0 { diagnose(p, n.token, "return is only valid inside a function"); return; }
    if n.left >= 0 {
        target = -1;
        var i = c.checking.len - 1;
        while i >= 0 {
            let fnnode = c.checking[i];
            if same_name(p, p.nodes[fnnode].token, p.nodes[n.left].token) { target = fnnode; break; }
            i -= 1;
        }
        if target < 0 { diagnose(p, n.token, "nonlocal return does not name an active enclosing function"); return; }
        if target != c.function_node { p.nodes[c.function_node].flags |= F_NONLOCAL; }
    }
    let symbol = p.nodes[target].symbol; p.nodes[node].symbol = symbol;
    var expected = c.result_type;
    if target != c.function_node { expected = p.types[p.nodes[target].type_id].element; }
    var expected_part = -1;
    if expected >= 0 && p.types[expected].kind == TY_TUPLE { expected_part = p.types[expected].first; }
    var forward_tuple = false;
    if n.first >= 0 && p.nodes[n.first].next < 0 {
        let value_type = check_expression(p, c, n.first, expected);
        if value_type >= 0 && p.types[value_type].kind == TY_TUPLE { forward_tuple = true; expected_part = -1; }
    }
    var value = n.first; var index = 0;
    while value >= 0 {
        var destination = expected;
        if expected_part >= 0 { destination = p.nodes[expected_part].type_id; }
        if expected >= 0 && p.types[expected].kind == TY_TUPLE && expected_part < 0 && !forward_tuple { destination = -1; }
        // Result annotations fix shape; read-only provenance remains part of
        // this specialization's actual result and follows it to callers.
        if destination >= 0 && (p.types[destination].kind == TY_REF || p.types[destination].kind == TY_SLICE) {
            check_expression(p, c, value, -1);
            if check_readonly(p, c, value) {
                destination = check_const_type(p, destination);
                if expected_part >= 0 { p.nodes[expected_part].type_id = destination; }
                else {
                    expected = destination;
                    p.types[p.nodes[target].type_id].element = destination;
                    if target == c.function_node { c.result_type = destination; }
                }
            }
        }
        let ty = check_value(p, c, value, destination);
        if expected_part >= 0 { expected_part = p.nodes[expected_part].next; }
        if ty >= 0 && check_contains_refs(p, ty, 0) {
            let end = c.roots.len;
            for i in 0..end {
                let r = c.roots[i]; if r.value != value { continue; }
                if r.root == -2 { diagnose(p, n.token, "return value retains a temporary reference"); }
                else if r.root >= 0 {
                    let root = p.symbols[r.root];
                    if root.owner == target && (root.flags & S_PARAMETER) == 0 {
                        diagnose(p, n.token, "return value retains a reference to this function's local storage");
                    }
                    if target != c.function_node && root.owner >= 0 && root.owner != target &&
                       (root.flags & S_GLOBAL) == 0 { diagnose(p, n.token, "nonlocal return reference does not outlive its target"); }
                }
                c.return_roots.push(CheckReturnRoot { function_node: target, index: index, root: r.root });
            }
        }
        index += 1; value = p.nodes[value].next;
    }
    var actual = check_tuple(p, n.first);
    if n.first >= 0 && p.nodes[n.first].next < 0 { actual = p.nodes[n.first].type_id; }
    if expected >= 0 && !check_same_type(p, expected, actual) {
        if n.first < 0 || p.nodes[n.first].next >= 0 || check_conversion(p, c, n.first, actual, expected) < 0 {
            diagnose(p, n.token, "return values do not match the function result signature");
        }
    }
    if target == c.function_node {
        if c.result_type < 0 { c.result_type = actual; p.types[p.nodes[target].type_id].element = actual; }
        else if expected < 0 { c.result_type = check_join_type(p, c, -1, c.result_type, n.first, actual, n.token); }
        c.returns = true;
    } else if expected < 0 { diagnose(p, n.token, "nonlocal return target needs an explicit result type"); }
    c.reachable = false;
}

recursive fn check_variable(p: Program&, c: Checker&, node: i64) {
    if (p.nodes[node].flags & F_CHECKED) != 0 { return; }
    let n = p.nodes[node]; p.nodes[node].flags |= F_CHECKED;
    var declaration_scope = c.scope; var function_node = c.function_node;
    let original_symbol = n.symbol;
    if original_symbol >= 0 && (p.symbols[original_symbol].flags & S_GLOBAL) != 0 {
        declaration_scope = p.symbols[original_symbol].scope; function_node = -1;
    }
    let saved_scope = c.scope; let saved_function = c.function_node;
    c.scope = declaration_scope; c.function_node = function_node;
    var annotation = check_resolve_type(p, c, n.left);
    if (n.flags & F_CONST) != 0 && annotation >= 0 { annotation = check_const_type(p, annotation); }
    var names = CheckList {};
    if n.first >= 0 {
        var binding = n.first;
        while binding >= 0 {
            p.nodes[binding].flags |= n.flags & (F_VAR | F_CONST | F_REUSABLE | F_REUSABLE_SLICES);
            check_list_push(c, names, binding); binding = p.nodes[binding].next;
        }
    } else { check_list_push(c, names, node); }
    var values = CheckList {}; var value = n.right;
    while value >= 0 { check_list_push(c, values, value); value = p.nodes[value].next; }
    if values.count == 0 && function_node < 0 && annotation >= 0 {
        let init = check_default(p, c, annotation, n.token, 0);
        p.nodes[node].right = init;
        if init >= 0 { check_list_push(c, values, init); }
    }
    var tuple = -1;
    if values.count == 1 && names.count > 1 {
        tuple = check_value(p, c, check_list_at(c, values, 0), -1);
        if tuple < 0 || p.types[tuple].kind != TY_TUPLE || p.types[tuple].count != names.count {
            diagnose(p, n.token, "multiple binding requires the same number of call results"); tuple = -1;
        }
        if annotation >= 0 { diagnose(p, n.token, "multiple-value binding cannot have one type annotation"); }
    } else if values.count > 0 && values.count != names.count { diagnose(p, n.token, "binding name and initializer counts differ"); }
    var component = -1; if tuple >= 0 { component = p.types[tuple].first; }
    for index in 0..names.count { let binding = check_list_at(c, names, index);
        var ty = annotation; var init = -1;
        if tuple >= 0 && component >= 0 { ty = p.nodes[component].type_id; init = check_list_at(c, values, 0); component = p.nodes[component].next; }
        else if index < values.count {
            init = check_list_at(c, values, index);
            if (n.flags & F_REFERENCE) != 0 && annotation < 0 {
                ty = check_expression(p, c, init, -1);
                if ty >= 0 && p.types[ty].kind != TY_REF && p.types[ty].kind != TY_SLICE {
                    if !check_addressable(p, init) { diagnose(p, n.token, ".= initialization requires storage, reference or slice"); }
                    else {
                        let root = check_place_root(p, init); var flags = 0;
                        if check_readonly(p, c, init) { flags |= TF_CONST; }
                        ty = check_type(p, TY_REF, ty, 0, -1, flags);
                        check_wrap_unary(p, init, T_BITAND, ty); check_add_root(c, init, root);
                    }
                }
            } else {
                if annotation < 0 && p.nodes[init].kind == N_UNARY && p.nodes[init].integer == T_BITAND {
                    ty = check_expression(p, c, init, -1);
                } else { ty = check_value(p, c, init, annotation); }
                if annotation < 0 && ty >= 0 && check_size_class(p, ty, 0) > 0 && check_addressable(p, init) {
                    let root = check_place_root(p, init); var flags = 0;
                    if check_readonly(p, c, init) { flags |= TF_CONST; }
                    ty = check_type(p, TY_REF, ty, 0, -1, flags);
                    check_wrap_unary(p, init, T_BITAND, ty); check_add_root(c, init, root);
                }
            }
            if annotation >= 0 { ty = annotation; }
            if p.nodes[init].kind == N_NULL && annotation < 0 { diagnose(p, n.token, "null binding requires an optional type annotation"); }
            if ty >= 0 && p.types[ty].kind == TY_ARRAY && p.types[ty].element < 0 {
                if (n.flags & F_VAR) == 0 || p.nodes[init].kind != N_ARRAY {
                    diagnose(p, n.token, "empty array element inference requires a var initialized directly with []");
                }
                ty = add_type(p, Type { kind: TY_ARRAY, element: -1, count: -1, size: 24, align: 4, array_kind: A_GROW, length_storage: 0 });
                p.nodes[init].type_id = ty;
            }
        } else if annotation < 0 { diagnose(p, n.token, "binding requires a type or initializer"); }
        if ty == TYPE_VOID { diagnose(p, n.token, "binding initializer produces no value"); }
        if ty >= 0 && p.types[ty].kind == TY_FN { diagnose(p, n.token, "function values are compile-time arguments and cannot be stored"); }
        if ty >= 0 && (n.flags & F_CONST) != 0 { ty = check_const_type(p, ty); }
        p.nodes[binding].type_id = ty;
        let symbol = check_declare(p, c, binding, c.scope); p.symbols[symbol].type_id = ty;
        if index == 0 { p.nodes[node].symbol = symbol; p.nodes[node].type_id = ty; }
        let vi = check_variable_index(c, symbol);
        if vi >= 0 {
            c.variables[vi].assigned = init >= 0; c.variables[vi].maybeassigned = init >= 0;
            c.variables[vi].readonly = (n.flags & F_CONST) != 0;
            if init >= 0 && ty >= 0 && (p.types[ty].kind == TY_REF || p.types[ty].kind == TY_SLICE) && check_readonly(p, c, init) { c.variables[vi].readonly = true; }
        }
        if init >= 0 && ty >= 0 && check_contains_refs(p, ty, 0) { check_store_roots(p, c, symbol, init); }
        if (n.flags & F_REUSABLE) != 0 {
            if (n.flags & F_VAR) == 0 || ty < 0 || p.types[ty].kind != TY_ARRAY || p.types[ty].array_kind != A_GROW {
                diagnose(p, n.token, "reusable applies to a var grow-only array pool");
            } else if p.types[ty].element >= 0 && check_size_class(p, p.types[ty].element, 0) != 0 {
                diagnose(p, n.token, "reusable pool elements require fixed size");
            }
        }
        if init < 0 && ty >= 0 && (check_size_class(p, ty, 0) != 0 || p.types[ty].kind == TY_REF) {
            diagnose(p, n.token, "nonfixed values and references must be constructed at declaration");
        }
    }
    c.scope = saved_scope; c.function_node = saved_function;
}
recursive fn check_assignment(p: Program&, c: Checker&, node: i64) {
    let n = p.nodes[node];
    if n.kind == N_MULTI_ASSIGN {
        let source = check_value(p, c, n.right, -1);
        if source < 0 || p.types[source].kind != TY_TUPLE || p.types[source].count != check_list_count(p, n.first) {
            diagnose(p, n.token, "multiple assignment requires matching call results"); return;
        }
        var target = n.first; var component = p.types[source].first;
        while target >= 0 && component >= 0 {
            let ty = check_expression(p, c, target, -1); let ct = p.nodes[component].type_id;
            if !check_same_type(p, ty, ct) { diagnose(p, p.nodes[target].token, "multiple assignment result type does not match its target"); }
            check_assignment_target(p, c, target, n.right, false);
            target = p.nodes[target].next; component = p.nodes[component].next;
        }
        return;
    }
    // A bare unassigned name is a legal assignment target, without reading it.
    let target = p.nodes[n.left]; var ty = -1;
    if target.kind == N_NAME {
        let symbol = check_lookup_name(p, c, n.left);
        if symbol >= 0 { p.nodes[n.left].symbol = symbol; ty = p.symbols[symbol].type_id; p.nodes[n.left].type_id = ty; }
        else { diagnose(p, target.token, "assignment target is unknown"); }
    } else { ty = check_expression(p, c, n.left, -1); }
    if ty < 0 { return; }
    let rebind = n.integer == T_DOTASSIGN;
    var value_type = ty;
    if p.types[ty].kind == TY_REF && !rebind { value_type = p.types[ty].element; }
    if rebind && p.types[ty].kind != TY_REF && p.types[ty].kind != TY_SLICE && target.kind != N_INDEX && target.kind != N_MEMBER {
        diagnose(p, n.token, ".= requires a reference or slice binding");
    }
    if n.right >= 0 { check_value(p, c, n.right, value_type); }
    else if n.integer != T_INC && n.integer != T_DEC { diagnose(p, n.token, "assignment has no right operand"); }
    if n.integer != T_ASSIGN && n.integer != T_DOTASSIGN {
        if !check_numeric(value_type) { diagnose(p, n.token, "compound assignment requires numeric storage"); }
        let symbol = check_place_root(p, n.left); let vi = check_variable_index(c, symbol);
        if vi >= 0 && !c.variables[vi].assigned { diagnose(p, n.token, "compound assignment reads uninitialized storage"); }
    }
    check_assignment_target(p, c, n.left, n.right, rebind);
    if n.right >= 0 && check_contains_refs(p, value_type, 0) {
        check_store_roots(p, c, check_place_root(p, n.left), n.right);
    }
}
fn check_assignment_target(p: Program&, c: Checker&, target: i64, value: i64, rebind: bool) {
    if !check_addressable(p, target) { diagnose(p, p.nodes[target].token, "assignment requires addressable storage"); return; }
    let n = p.nodes[target]; let root = check_place_root(p, target);
    let through_ref = n.type_id >= 0 && p.types[n.type_id].kind == TY_REF && !rebind;
    if check_readonly(p, c, target) { diagnose(p, n.token, "assignment cannot change read-only storage"); }
    if n.kind == N_NAME && root >= 0 && !through_ref {
        let s = p.symbols[root]; let vi = check_variable_index(c, root);
        if (s.flags & S_MUTABLE) == 0 && (vi < 0 || c.variables[vi].maybeassigned) {
            diagnose(p, n.token, "let binding cannot be assigned again");
        }
        if vi >= 0 { c.variables[vi].assigned = true; c.variables[vi].maybeassigned = true; }
        if value >= 0 && s.type_id >= 0 && check_contains_refs(p, s.type_id, 0) { check_store_roots(p, c, root, value); }
    }
    if n.kind == N_MEMBER && n.symbol >= 0 && n.symbol < p.nodes.len && (p.nodes[n.symbol].flags & F_CONST) != 0 && !through_ref {
        diagnose(p, n.token, "let field cannot be assigned as a whole");
    }
    if root >= 0 {
        check_capture(p, c, root); check_note_effect(c, root, 0);
        let ty = p.symbols[root].type_id;
        if ty >= 0 && check_size_class(p, ty, 0) == 2 && n.kind == N_NAME && !through_ref {
            check_mutation_views(p, c, target, true);
        }
    }
}
recursive fn check_function(p: Program&, c: Checker&, function_node: i64) {
    if function_node < 0 { return; }
    check_prepare_function(p, c, function_node);
    let n = p.nodes[function_node];
    p.nodes[function_node].flags |= F_REACHABLE;
    if (n.flags & F_CHECKED) != 0 || (n.flags & F_GENERIC) != 0 { return; }
    for active in c.checking {
        if active == function_node {
            if (n.flags & F_RECURSIVE) == 0 { diagnose(p, n.token, "recursive cycle requires recursive declarations"); }
            if p.types[n.type_id].element < 0 { diagnose(p, n.token, "recursive function requires an explicit result type"); }
            return;
        }
    }
    if n.right < 0 { p.nodes[function_node].flags |= F_CHECKED; return; }
    let saved_scope = c.scope; let saved_function = c.function_node; let saved_result = c.result_type;
    let saved_slot = c.next_slot; let saved_reachable = c.reachable; let saved_returns = c.returns;
    c.scope = n.scope; c.function_node = function_node; c.result_type = p.types[n.type_id].element;
    c.next_slot = check_list_count(p, n.first); c.reachable = true; c.returns = false;
    c.checking.push(function_node);
    let body_type = check_expression(p, c, n.right, c.result_type);
    let body = p.nodes[n.right];
    if c.reachable && (body.flags & F_TAIL) != 0 && body.last >= 0 {
        let tail = body.last;
        if p.nodes[tail].kind != N_RETURN && p.nodes[tail].kind != N_BREAK && p.nodes[tail].kind != N_CONTINUE {
            var original = p.nodes[tail]; original.next = -1; original.flags &= ~F_TAIL;
            let value = p.nodes.len; p.nodes.push(original);
            p.nodes[tail] = Node { kind: N_RETURN, token: original.token, first: value, last: value, symbol: n.symbol, flags: F_IMPLICIT_RETURN | F_TAIL, scope: original.scope };
            check_copy_roots(c, value, tail);
            check_return(p, c, tail); p.nodes[tail].type_id = TYPE_VOID; p.nodes[tail].flags |= F_CHECKED;
        }
    } else if c.reachable && c.result_type >= 0 && c.result_type != TYPE_VOID {
        diagnose(p, n.token, "function can reach its end without returning every result");
    }
    if c.result_type < 0 { c.result_type = TYPE_VOID; }
    p.types[n.type_id].element = c.result_type;
    p.nodes[function_node].flags |= F_CHECKED;
    c.checking.pop();
    c.scope = saved_scope; c.function_node = saved_function; c.result_type = saved_result;
    c.next_slot = saved_slot; c.reachable = saved_reachable; c.returns = saved_returns;
}
recursive fn check_statement(p: Program&, c: Checker&, node: i64) {
    let n = p.nodes[node];
    if n.kind == N_VARIABLE { check_variable(p, c, node); }
    else if n.kind == N_FUNCTION { check_prepare_function(p, c, node); }
    else if n.kind == N_STRUCT || n.kind == N_ENUM {
        if n.third < 0 { check_layout_nominal(p, c, n.type_id); }
    } else if n.kind == N_ALIAS { check_resolve_type(p, c, n.left); }
    else if n.kind == N_IMPORT || n.kind == N_NAMESPACE || n.kind == N_EXTERN || n.kind == N_EMPTY { }
    else { check_expression(p, c, node, TYPE_VOID); }
}

fn check_name_literal(p: Program&, token: i64) -> i64 {
    var text = p.tokens[token]; text.kind = T_STRLIT; text.text_start = text.start; text.text_len = text.end - text.start;
    let tid = p.tokens.len; p.tokens.push(text);
    let id = new_node(p, N_STRING, tid); p.nodes[id].type_id = TYPE_STRING;
    return id;
}
recursive fn check_expand_replace(p: Program&, node: i64, name: i64, value: i64, accessor: i64, actual: i64, type_id: i64) {
    if node < 0 { return; }
    let n = p.nodes[node];
    if n.kind == N_NAME && same_name(p, n.token, name) && value >= 0 {
        let next = n.next; p.nodes[node] = p.nodes[value]; p.nodes[node].next = next; return;
    }
    if accessor >= 0 && same_name(p, n.token, accessor) {
        if n.kind == N_MEMBER || n.kind == N_BINDING {
            p.nodes[node].token = actual;
        } else if n.kind == N_TYPE_NAME {
            if type_id >= 0 { p.nodes[node].type_id = type_id; }
            else { diagnose(p, n.token, "field accessor is not a type"); }
        } else if n.kind == N_NAME {
            if type_id >= 0 {
                p.nodes[node].token = actual;
                p.nodes[node].type_id = type_id;
                if p.types[type_id].declaration >= 0 && p.nodes[p.types[type_id].declaration].kind == N_VARIANT {
                    p.nodes[node].symbol = p.types[type_id].declaration;
                    if p.nodes[p.types[type_id].declaration].first < 0 {
                        p.nodes[node].kind = N_RECORD; p.nodes[node].flags |= F_CHECKED;
                    }
                }
            } else { diagnose(p, n.token, "field accessor requires member or initializer-label position"); }
        }
    }
    if type_id >= 0 && accessor < 0 && n.kind == N_TYPE_NAME && same_name(p, n.token, name) { p.nodes[node].type_id = type_id; }
    var child = n.first;
    while child >= 0 { let next = p.nodes[child].next; check_expand_replace(p, child, name, value, accessor, actual, type_id); child = next; }
    check_expand_replace(p, n.left, name, value, accessor, actual, type_id);
    check_expand_replace(p, n.right, name, value, accessor, actual, type_id);
    check_expand_replace(p, n.third, name, value, accessor, actual, type_id);
}
recursive fn check_expand_const_for(p: Program&, c: Checker&, node: i64) -> i64 {
    let n = p.nodes[node]; let body = p.nodes[n.right];
    let result = new_node(p, body.kind, n.token);
    p.nodes[result].flags = body.flags;
    let first_binding = n.first; var second_binding = -1;
    if first_binding >= 0 { second_binding = p.nodes[first_binding].next; }
    if first_binding < 0 { diagnose(p, n.token, "const for has no binding"); return result; }
    var entries = CheckList {};
    if n.integer == 0 || n.integer == 2 {
        var entry = n.left;
        while entry >= 0 { check_list_push(c, entries, entry); entry = p.nodes[entry].next; }
    } else {
        let type_id = check_resolve_type(p, c, n.left);
        if type_id < 0 { return result; }
        check_layout_nominal(p, c, type_id);
        if n.integer == 1 && p.types[type_id].kind != TY_STRUCT || n.integer == 3 && p.types[type_id].kind != TY_ENUM {
            diagnose(p, n.token, "reflection source has the wrong nominal type"); return result;
        }
        var field = p.types[type_id].first;
        while field >= 0 {
            if (p.nodes[field].flags & F_PAD) == 0 { check_list_push(c, entries, field); }
            field = p.nodes[field].next;
        }
    }
    if entries.count > 4096 { diagnose(p, n.token, "const for expansion exceeds its finite implementation limit"); return result; }
    for entry_index in 0..entries.count { let entry = check_list_at(c, entries, entry_index);
        var bindings = CheckList {}; var value = -1; var accessor = -1; var actual = -1; var ty = -1;
        if n.integer == 0 {
            let constant = check_constant(p, c, entry, 0);
            if constant.valid {
                value = new_node(p, N_INTEGER, p.nodes[entry].token); p.nodes[value].integer = constant.value;
            } else if p.nodes[entry].kind == N_STRING || p.nodes[entry].kind == N_BOOL || p.nodes[entry].kind == N_FLOAT {
                value = check_clone(p, c, entry, bindings);
            } else { diagnose(p, p.nodes[entry].token, "const for list entry is not a compile-time constant"); continue; }
        } else if n.integer == 2 { ty = check_resolve_type(p, c, entry); }
        else {
            value = check_name_literal(p, p.nodes[entry].token); actual = p.nodes[entry].token;
            if second_binding < 0 { diagnose(p, n.token, "reflection expansion requires name and accessor bindings"); continue; }
            accessor = p.nodes[second_binding].token;
            if n.integer == 3 { ty = p.nodes[entry].type_id; }
        }
        let copy = check_clone(p, c, n.right, bindings);
        check_expand_replace(p, copy, p.nodes[first_binding].token, value, accessor, actual, ty);
        if body.kind == N_BLOCK {
            // A marker prevents a jump from crossing an expansion boundary.
            p.nodes[copy].flags |= F_NONLOCAL;
            append_child(p, result, copy);
        } else {
            var child = p.nodes[copy].first;
            while child >= 0 { let next = p.nodes[child].next; p.nodes[child].next = -1; append_child(p, result, child); child = next; }
        }
    }
    return result;
}
recursive fn check_expand_children(p: Program&, c: Checker&, node: i64) {
    var first = -1; var last = -1; var child = p.nodes[node].first;
    while child >= 0 {
        let next = p.nodes[child].next;
        if p.nodes[child].kind == N_CONST_FOR {
            let expansion = check_expand_const_for(p, c, child);
            var item = p.nodes[expansion].first;
            while item >= 0 {
                let after = p.nodes[item].next; p.nodes[item].next = -1;
                if first < 0 { first = item; } else { p.nodes[last].next = item; }
                last = item; item = after;
            }
        } else {
            p.nodes[child].next = -1;
            if first < 0 { first = child; } else { p.nodes[last].next = child; }
            last = child;
        }
        child = next;
    }
    p.nodes[node].first = first; p.nodes[node].last = last;
}
recursive fn check_const_for(p: Program&, c: Checker&, node: i64, expected: i64) -> i64 {
    let next = p.nodes[node].next; let expanded = check_expand_const_for(p, c, node);
    p.nodes[node] = p.nodes[expanded]; p.nodes[node].next = next;
    return check_expression(p, c, node, expected);
}
fn check_namespace_scope(p: Program&, c: Checker&, token: i64) -> i64 {
    if token < 0 { return 0; }
    for scope, id in c.scopes {
        if scope.namespace_node >= 0 && same_name(p, p.nodes[scope.namespace_node].token, token) { return id; }
    }
    let saved_scope = c.scope; let saved_function = c.function_node;
    c.scope = 0; c.function_node = -1;
    let namespace_node = new_node(p, N_NAMESPACE, token); check_declare(p, c, namespace_node, 0);
    check_enter(c, -1); let result = c.scope;
    c.scopes[result].namespace_node = namespace_node; p.nodes[namespace_node].scope = result;
    c.scope = saved_scope; c.function_node = saved_function;
    return result;
}
recursive fn check_top_declarations(p: Program&, c: Checker&, first: i64) {
    var node = first;
    while node >= 0 {
        let n = p.nodes[node];
        if n.kind == N_NAMESPACE {
            let scope = check_namespace_scope(p, c, n.token); p.nodes[node].scope = scope;
            if n.first >= 0 {
                let saved = c.scope; c.scope = scope; check_top_declarations(p, c, n.first); c.scope = saved;
            }
        } else if n.kind == N_EXTERN { check_top_declarations(p, c, n.first); }
        else if n.kind != N_IMPORT && n.kind != N_EMPTY {
            let saved = c.scope; var scope = c.scope;
            if n.scope >= 0 { scope = check_namespace_scope(p, c, n.scope); }
            c.scope = scope;
            if n.kind == N_STRUCT || n.kind == N_ENUM {
                var kind = TY_STRUCT; if n.kind == N_ENUM { kind = TY_ENUM; }
                p.nodes[node].type_id = add_type(p, Type { kind: kind, declaration: node,
                    first: n.first, name_token: n.token });
            }
            check_declare(p, c, node, scope); c.scope = saved;
        }
        node = n.next;
    }
}
fn check_program(p: Program&) {
    if p.types.len == 0 { initialize_types(p); }
    for i in TYPE_I8..TYPE_STRING {
        if p.types[i].size > 0 { p.types[i].align = p.types[i].size; }
    }
    p.types[TYPE_STRING].size = 2 * p.pointer_bytes;
    p.types[TYPE_STRING].align = 2 * p.pointer_bytes;
    var checker_scopes: CheckScope[>..] = [];
    var checker_variables: CheckVariable[>..] = [];
    var checker_roots: CheckRoot[>..] = [];
    var checker_effects: CheckEffect[>..] = [];
    var checker_return_roots: CheckReturnRoot[>..] = [];
    var checker_specializations: CheckSpecialization[>..] = [];
    var checker_bindings: TypeBinding[>..] = [];
    var checker_checking: i64[>..] = [];
    var checker_loop_stack: CheckLoop[>..] = [];
    var checker_integer_work: CheckInteger[>..] = [];
    var checker_binding_work: TypeBinding[>..] = [];
    var checker_flow_work: CheckFlow[>..] = [];
    var checker_interval_work: CheckInterval[>..] = [];
    var c = Checker { scopes: checker_scopes, variables: checker_variables, roots: checker_roots, effects: checker_effects, return_roots: checker_return_roots, specializations: checker_specializations, bindings: checker_bindings, checking: checker_checking, loop_stack: checker_loop_stack, integer_work: checker_integer_work, binding_work: checker_binding_work, flow_work: checker_flow_work, interval_work: checker_interval_work };
    c.scopes.push(CheckScope { parent: -1, function_node: -1 });
    for source in p.sources { if source.root >= 0 { check_top_declarations(p, c, p.nodes[source.root].first); } }
    let declarations = p.symbols.len;
    for i in 0..declarations {
        let s = p.symbols[i]; if s.node < 0 { continue; }
        let n = p.nodes[s.node]; c.scope = s.scope;
        if n.kind == N_FUNCTION { check_prepare_function(p, c, s.node); }
        else if (n.kind == N_STRUCT || n.kind == N_ENUM) && n.third < 0 { check_layout_nominal(p, c, s.type_id); }
        else if n.kind == N_ALIAS { p.symbols[i].type_id = check_resolve_type(p, c, n.left); }
    }
    c.scope = 0;
    for i in 0..declarations {
        let s = p.symbols[i];
        if (s.flags & S_GLOBAL) != 0 && s.node >= 0 && p.nodes[s.node].kind == N_VARIABLE { check_variable(p, c, s.node); }
    }
    var main_symbol = -1;
    for i in 0..declarations {
        let s = p.symbols[i];
        if s.node < 0 || p.nodes[s.node].kind != N_FUNCTION { continue; }
        let n = p.nodes[s.node];
        if s.scope == 0 && token_is(p, s.name_token, "main") {
            if main_symbol >= 0 { diagnose(p, n.token, "main cannot be overloaded"); }
            main_symbol = i;
        }
        if (n.flags & F_EXPORT) != 0 || p.library && (n.flags & F_GENERIC) == 0 { check_function(p, c, s.node); }
    }
    if main_symbol < 0 {
        if !p.library { diagnose(p, -1, "program requires fn main()"); }
    } else {
        let main = p.symbols[main_symbol].node;
        if p.nodes[main].first >= 0 || (p.nodes[main].flags & F_GENERIC) != 0 { diagnose(p, p.nodes[main].token, "main must be nongeneric and take no parameters"); }
        check_function(p, c, main); p.entry = main;
    }
    for variable in c.variables {
        let s = p.symbols[variable.symbol]; let ty = s.type_id;
        if ty >= 0 && p.types[ty].kind == TY_ARRAY && p.types[ty].element < 0 {
            diagnose(p, s.name_token, "empty array element type was never determined");
        }
    }
}
