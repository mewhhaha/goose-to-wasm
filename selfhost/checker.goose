import model;
import sources;
import checker_validation;
import checker_operations;
import checker_lifetimes;
import checker_rendering;

// Stable IDs are the only links held while tables grow. Scope, flow and
// provenance are checker work tables; checked nodes contain backend contracts.
struct CheckScope { parent: i64, function_node: i64, depth: i64 = 0, namespace_node: i64 = -1, frame_root: i64 = 0, first_variable: i64 = -1, outer_exits: i64 = -1, name_heads: i64[16] = [-1; 16] }
struct TypeBinding { parameter: i64, value: i64, next: i64 = -1 }
struct CheckList { first: i64 = -1, last: i64 = -1, count: i64 = 0 }
struct CheckSpan { first: i64 = 0, count: i64 = 0 }
struct CheckInteger { value: i64, next: i64 = -1 }
struct CheckContextFloat { node: i64, original: i64, bindings: CheckList }
struct CheckChoice { symbol: i64 = -1, bindings: CheckList, ambiguous: bool = false, hof: bool = false, converting: bool = false }
struct CheckVariable {
    symbol: i64, assigned: bool = false, maybeassigned: bool = false, global_initialized: bool = false,
    readonly: bool = false, narrowed: i64 = -1, next_frame: i64 = -1, literal_use: i64 = -1, writable_use: i64 = -1,
    nonnegative: i64 = -2, nonnegative_use: i64 = -1,
}
struct CheckEnvironment {
    symbol: i64, assigned: bool, maybeassigned: bool, narrowed: i64, readonly: bool, next: i64 = -1,
}
struct CheckRoot { value: i64, root: i64, kind: i64 = 0, next: i64 = -1 }
struct CheckEffect { function_node: i64, root: i64, kind: i64 }
struct CheckReturnRoot { function_node: i64, index: i64, root: i64, kind: i64 = 0 }
struct CheckNeed { function_node: i64, target: i64 }
struct CheckNeedFrame { function_node: i64, parent: i64 }
struct CheckNeedEdge { function_node: i64, token: i64, path: i64 }
struct CheckSpecialization { original: i64, symbol: i64, binding_start: i64, binding_count: i64 }
struct CheckFlow { symbol: i64, assigned: bool, maybeassigned: bool, narrowed: i64 = -1 }
struct CheckFlowCursor { frame: i64, index: i64, active: bool = false }
struct CheckExit { target: i64, flow: CheckSpan, backedge: bool = false }
struct CheckOuterExit { target: i64, flow: CheckSpan, next: i64 = -1 }
struct CheckLoop { node: i64, scope: i64, function_node: i64, result: i64 = -1, values: CheckList = CheckList {}, breaks: bool = false, expected: i64 = -1, returning: bool = false }
struct CheckLogicalKill { node: i64, symbol: i64 }

struct CheckDefaultCapture { node: i64, function_node: i64, floor: i64 }

struct Checker {
    literal_comparison: bool = false, default_body: bool = false, render_reference: bool = false,
    format_scan_end: i64 = 0, has_format_hooks: bool = false,
    scopes: CheckScope[>..]&, variables: CheckVariable[>..]&, variable_lookup: i64[>..]&,
    roots: CheckRoot[>..]&, root_nodes: i64[>..]&, root_symbols: i64[>..]&, effects: CheckEffect[>..]&,
    environments: CheckEnvironment[>..]&, environment_heads: i64[>..]&,
    outer_exits: CheckOuterExit[>..]&,
    syntax_nodes: Node[>..]&, syntax_lookup: i64[>..]&,
    node_nonnegative: i64[>..]&,
    clone_syntax: bool = false, syntax_body: i64 = -1, syntax_function: i64 = -1, optional_globals: bool = false,
    return_roots: CheckReturnRoot[>..]&,
    specializations: CheckSpecialization[>..]&, bindings: TypeBinding[>..]&,
    needs: CheckNeed[>..]&, need_frames: CheckNeedFrame[>..]&, need_edges: CheckNeedEdge[>..]&, need_path: i64 = -1,
    contextual_floats: CheckContextFloat[>..]&, contextual_lookup: i64[>..]&,
    checking: i64[>..]&, loop_stack: CheckLoop[>..]&,
    integer_work: CheckInteger[>..]&, binding_work: TypeBinding[>..]&, flow_work: CheckFlow[>..]&, flow_cursors: CheckFlowCursor[>..]&, exit_work: CheckExit[>..]&, interval_work: CheckInterval[>..]&, render_cache: RenderKey[>..]&, render_hooks: i64[>..]&,
    scope: i64 = 0, function_node: i64 = -1, result_type: i64 = -1,
    next_slot: i64 = 0, reachable: bool = true, tuple_context: bool = false, returning: bool = false,
    parameter_default_contexts: CheckDefaultCapture[>..]&,
    logical_kills: CheckLogicalKill[>..]&,
    parameter_default_function: i64 = -1, parameter_default_floor: i64 = -1,
    returns: bool = false, initializing_globals: bool = false, expanding: bool = false, expansion_nodes: i64 = 0, inference_depth: i64 = 0, type_indirections: i64 = 0, checking_count: i64 = 0, loop_count: i64 = 0, default_fields: CheckList = CheckList {}, backedges: CheckList = CheckList {}, type_chain: CheckList = CheckList {},
}

fn check_push_loop(c: Checker&, value: CheckLoop) {
    if c.loop_count == c.loop_stack.len { c.loop_stack.push(value); } else { c.loop_stack[c.loop_count] = value; }
    c.loop_count += 1;
}
fn check_push_function(c: Checker&, value: i64) {
    if c.checking_count == c.checking.len { c.checking.push(value); } else { c.checking[c.checking_count] = value; }
    c.checking_count += 1;
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
    let id = c.scopes.len; var frame_root = id;
    if c.scopes[saved].function_node == function_node { frame_root = c.scopes[saved].frame_root; }
    c.scopes.push(CheckScope { parent: saved, function_node: function_node,
        depth: c.scopes[saved].depth + 1, frame_root: frame_root });
    c.scope = id;
    return saved;
}
fn check_visible(c: Checker&, scope: i64, current_scope: i64) -> bool {
    if scope < 0 || current_scope < 0 { return false; }
    let owner = c.scopes[scope].function_node; var current = current_scope;
    // A scope from an unrelated function cannot be an ancestor. Jump
    // directly between lexical function frames before walking local scopes.
    while current >= 0 && c.scopes[current].function_node != owner {
        current = c.scopes[c.scopes[current].frame_root].parent;
    }
    while current >= 0 && c.scopes[current].function_node == owner {
        if current == scope { return true; }
        current = c.scopes[current].parent;
    }
    return false;
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
    if at.kind != bt.kind || at.flags != bt.flags || at.storage != bt.storage || at.length_storage != bt.length_storage || at.pool != bt.pool || at.index_type != bt.index_type { return false; }
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
    for id in 0..p.types.len {
        let t: const Type& = p.types[id];
        if t.kind == kind && t.element == element && t.count == count &&
           t.declaration == declaration && t.flags == flags &&
           (kind != TY_REF || t.length_storage < 0 && t.pool < 0) { return id; }
    }
    var ty = Type { kind: kind, element: element, count: count, declaration: declaration, flags: flags };
    if kind == TY_REF || kind == TY_FN { ty.size = p.pointer_bytes; ty.align = p.pointer_bytes; }
    if kind == TY_SLICE { ty.size = 2 * p.pointer_bytes; ty.align = 2 * p.pointer_bytes; ty.array_kind = A_SLICE; }
    return add_type(p, ty);
}
fn check_array_type(p: Program&, element: i64, count: i64, array_kind: i64, flags: i64) -> i64 {
    var default_length = -1; if array_kind == A_VAR { default_length = 4; }
    if array_kind == A_LIMITED && count >= 0 {
        default_length = 1; if count > 255 { default_length = 2; } if count > 65535 { default_length = 4; } if count > 4294967295 { default_length = 8; }
    }
    for id in 0..p.types.len {
        let t: const Type& = p.types[id];
        if t.kind == TY_ARRAY && !t.length_explicit && t.length_storage == default_length && t.element == element && t.count == count &&
           t.array_kind == array_kind && t.flags == flags { return id; }
    }
    var size = 24; var align = 4;
    if array_kind == A_FIXED && element >= 0 {
        align = p.types[element].align;
        if count >= 0 && p.types[element].size <= 2147483647 / (count + 1) {
            size = count * p.types[element].size; if size == 0 { size = 1; }
        } else { size = 0; }
    }
    var length_storage = default_length;
    if array_kind == A_LIMITED && count >= 0 && element >= 0 {
        var slots = count; if slots == 0 { slots = 1; }
        size = length_storage + slots * p.types[element].size; align = 1;
    }
    return add_type(p, Type { kind: TY_ARRAY, element: element, count: count, flags: flags, size: size, align: align, array_kind: array_kind, length_storage: length_storage });
}
fn check_type_const(p: Program&, ty: i64, readonly: bool) -> i64 {
    if ty < 0 { return ty; }
    var copy = p.types[ty];
    if readonly { copy.flags |= TF_CONST; } else { copy.flags &= ~TF_CONST; }
    if copy.flags == p.types[ty].flags { return ty; }
    for id in 0..p.types.len {
        let candidate: const Type& = p.types[id];
        if candidate.kind == copy.kind && candidate.element == copy.element && candidate.count == copy.count && candidate.declaration == copy.declaration && candidate.first == copy.first && candidate.flags == copy.flags && candidate.array_kind == copy.array_kind && candidate.storage == copy.storage && candidate.length_storage == copy.length_storage && candidate.length_explicit == copy.length_explicit && candidate.pool == copy.pool && candidate.index_type == copy.index_type { return id; }
    }
    return add_type(p, copy);
}
fn check_const_type(p: Program&, ty: i64) -> i64 { return check_type_const(p, ty, true); }
fn check_plain_value_type(p: Program&, ty: i64) -> i64 {
    if ty < 0 || p.types[ty].kind == TY_REF || p.types[ty].kind == TY_SLICE { return ty; }
    return check_type_const(p, ty, false);
}
fn check_name_bucket(p: Program&, token: i64) -> i64 {
    var hash: u32 = 2166136261;
    for byte in token_text(p, token) { hash = (hash ^ (byte as u32)) * 16777619; }
    return (hash & 15) as i64;
}
fn check_link_symbol(p: Program&, c: Checker&, symbol: i64, scope: i64) {
    if scope < 0 { return; }
    let bucket = check_name_bucket(p, p.symbols[symbol].name_token);
    p.symbols[symbol].name_next = c.scopes[scope].name_heads[bucket];
    c.scopes[scope].name_heads[bucket] = symbol;
}
fn check_lookup_scope(p: Program&, c: Checker&, token: i64, scope: i64, role: i64 = 0) -> i64 {
    if scope < 0 || scope >= c.scopes.len { return -1; }
    let bucket = check_name_bucket(p, token);
    var id = c.scopes[scope].name_heads[bucket];
    while id >= 0 {
        let symbol: const Symbol& = p.symbols[id];
        if same_name(p, symbol.name_token, token) {
            if role == 0 || (symbol.flags & role) != 0 { return id; }
            if role == S_FUNCTION && symbol.node >= 0 {
                let kind = p.nodes[symbol.node].kind;
                if (symbol.flags & (S_GLOBAL | S_FUNCTION | S_TYPE)) == 0 && kind != N_NAMESPACE || kind == N_TYPE_PARAM { return id; }
            }
        }
        id = symbol.name_next;
    }
    return -1;
}

fn check_global_value(p: Program&, symbol: i64) -> i64 {
    var current = symbol; var function_symbol = -1;
    while current >= 0 {
        let flags = p.symbols[current].flags;
        if (flags & S_GLOBAL) != 0 { return current; }
        if function_symbol < 0 && (flags & S_FUNCTION) != 0 { function_symbol = current; }
        current = p.symbols[current].next;
    }
    if function_symbol >= 0 { return function_symbol; }
    return symbol;
}

fn check_lookup(p: Program&, c: Checker&, token: i64, scope: i64, role: i64 = 0) -> i64 {
    var current = scope;
    while current > 0 && c.scopes[current].namespace_node < 0 {
        let function_node = c.scopes[current].function_node; var end = current;
        while end > 0 && c.scopes[end].namespace_node < 0 && c.scopes[end].function_node == function_node { end = c.scopes[end].parent; }
        var at = current; var parameter = -1; var function_symbol = -1; var type_symbol = -1;
        while at != end {
            let found = check_lookup_scope(p, c, token, at, role);
            if found >= 0 {
                let symbol = p.symbols[found];
                if (symbol.flags & S_FUNCTION) != 0 { if function_symbol < 0 { function_symbol = found; } }
                else if (symbol.flags & S_TYPE) != 0 {
                    if symbol.node >= 0 && p.nodes[symbol.node].kind == N_TYPE_PARAM { if parameter < 0 { parameter = found; } }
                    else if type_symbol < 0 { type_symbol = found; }
                } else { return found; }
            }
            at = c.scopes[at].parent;
        }
        if parameter >= 0 { return parameter; }
        if function_symbol >= 0 { return function_symbol; }
        if type_symbol >= 0 { return type_symbol; }
        current = end;
    }
    loop {
        var found = check_lookup_scope(p, c, token, current, role);
        if role == 0 { found = check_global_value(p, found); }
        if found >= 0 { return found; }
        if current <= 0 { return -1; }
        current = c.scopes[current].parent;
    }
}
fn check_lookup_name(p: Program&, c: Checker&, node: i64, role: i64 = 0) -> i64 {
    let n = p.nodes[node];
    if n.aux <= 1 || n.integer < 0 || n.integer >= p.tokens.len {
        return check_lookup(p, c, n.token, c.scope, role);
    }
    var at = n.integer; var scope = c.scope;
    if p.tokens[at].kind == T_COLONCOLON { scope = 0; at += 1; }
    var first_role = role; if at < n.token { first_role = 0; }
    var symbol = check_lookup(p, c, at, scope, first_role);
    at += 1;
    while at < n.token {
        if p.tokens[at].kind == T_COLONCOLON { at += 1; }
        if symbol < 0 { return -1; }
        let declaration = p.symbols[symbol].node;
        if declaration < 0 || p.nodes[declaration].kind != N_NAMESPACE { return -1; }
        var member_role = role; if at < n.token { member_role = 0; }
        let member_scope = p.nodes[declaration].scope;
        symbol = check_lookup_scope(p, c, at, member_scope, member_role);
        if member_role == 0 { symbol = check_global_value(p, symbol); }
        at += 1;
    }
    return symbol;
}
fn check_variable_index(c: Checker&, symbol: i64) -> i64 {
    if symbol < 0 || symbol >= c.variable_lookup.len { return -1; }
    return c.variable_lookup[symbol];
}
fn check_lookup_global_name(p: Program&, c: Checker&, node: i64) -> i64 {
    let saved = c.scope;
    while c.scope > 0 && c.scopes[c.scope].namespace_node < 0 { c.scope = c.scopes[c.scope].parent; }
    let symbol = check_lookup_name(p, c, node); c.scope = saved;
    if symbol >= 0 && (p.symbols[symbol].flags & S_GLOBAL) != 0 { return symbol; }
    return -1;
}

fn check_declare(p: Program&, c: Checker&, node: i64, scope: i64) -> i64 {
    if p.nodes[node].symbol >= 0 { return p.nodes[node].symbol; }
    let n = p.nodes[node];
    var previous = check_lookup_scope(p, c, n.token, scope);
    if n.kind == N_FUNCTION_VALUE { previous = -1; }
    var flags = 0; var slot = -1;
    if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE { flags |= S_FUNCTION; }
    if n.kind == N_STRUCT || n.kind == N_ENUM || n.kind == N_ALIAS || n.kind == N_TYPE_PARAM { flags |= S_TYPE; }
    if n.kind == N_PARAM { flags |= S_PARAMETER; }
    if (n.flags & F_VAR) != 0 { flags |= S_MUTABLE; }
    if (n.flags & F_EXTERN) != 0 { flags |= S_EXTERN; }
    if c.function_node < 0 && (scope == 0 || scope >= 0 && c.scopes[scope].namespace_node >= 0) && (flags & (S_FUNCTION | S_TYPE)) == 0 && n.kind != N_NAMESPACE && n.kind != N_FIELD && n.kind != N_VARIANT { flags |= S_GLOBAL; }
    var collision = previous;
    while collision >= 0 {
        let old = p.symbols[collision];
        let namespace_merge = n.kind == N_NAMESPACE && old.node >= 0 && p.nodes[old.node].kind == N_NAMESPACE;
        let overload = (flags & S_FUNCTION) != 0 && (old.flags & S_FUNCTION) != 0;
        let separate_global_roles = (scope == 0 || scope >= 0 && c.scopes[scope].namespace_node >= 0) &&
            (flags & (S_GLOBAL | S_FUNCTION | S_TYPE)) != 0 && (old.flags & (S_GLOBAL | S_FUNCTION | S_TYPE)) != 0 &&
            (flags & (S_FUNCTION | S_TYPE)) != (old.flags & (S_FUNCTION | S_TYPE));
        if !namespace_merge && !overload && !separate_global_roles {
            diagnose(p, n.token, "duplicate declaration in this scope"); break;
        }
        collision = old.next;
    }
    if (flags & (S_FUNCTION | S_TYPE)) == 0 && n.kind != N_NAMESPACE && n.kind != N_FIELD && n.kind != N_VARIANT {
        slot = c.next_slot; c.next_slot += 1;
    }
    let id = p.symbols.len;
    var owner = c.function_node;
    if c.default_body && (n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE) { owner = -1; }
    p.symbols.push(Symbol { name_token: n.token, type_id: n.type_id, node: node,
        scope: scope, slot: slot, flags: flags, next: previous, owner: owner });
    check_link_symbol(p, c, id, scope);
    p.nodes[node].symbol = id;
    p.nodes[node].scope = scope;
    if (n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE) && c.default_fields.count > 0 { p.nodes[node].flags |= F_DEFAULT; }
    if (n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE) && (n.flags & F_SYNTHETIC) == 0 && c.parameter_default_function >= 0 {
        c.parameter_default_contexts.push(CheckDefaultCapture { node: node, function_node: c.parameter_default_function, floor: c.parameter_default_floor });
    }
    if slot >= 0 {
        while c.variable_lookup.len <= id { c.variable_lookup.push(-1); }
        c.variable_lookup[id] = c.variables.len; var next_frame = -1;
        if scope >= 0 {
            let frame = c.scopes[scope].frame_root; next_frame = c.scopes[frame].first_variable;
            c.scopes[frame].first_variable = c.variables.len;
        }
        c.variables.push(CheckVariable { symbol: id, next_frame: next_frame });
    }
    return id;
}
fn check_root_head(c: Checker&, value: i64) -> i64 {
    if value >= 0 { if value >= c.root_nodes.len { return -1; } return c.root_nodes[value]; }
    let index = -value - 1; if index >= c.root_symbols.len { return -1; } return c.root_symbols[index];
}
fn check_root_index(c: Checker&, value: i64, root: i64) {
    if value >= 0 {
        while c.root_nodes.len <= value { c.root_nodes.push(-1); }
        c.root_nodes[value] = root;
    } else {
        let index = -value - 1;
        while c.root_symbols.len <= index { c.root_symbols.push(-1); }
        c.root_symbols[index] = root;
    }
}
fn check_add_root(c: Checker&, value: i64, root: i64, kind: i64 = 0) {
    let first = check_root_head(c, value); var at = first;
    while at >= 0 { let old = c.roots[at]; if old.root == root && old.kind == kind { return; } at = old.next; }
    let id = c.roots.len; c.roots.push(CheckRoot { value: value, root: root, kind: kind, next: first }); check_root_index(c, value, id);
}
fn check_copy_roots(c: Checker&, destination: i64, source: i64) {
    var at = check_root_head(c, source);
    while at >= 0 { let root = c.roots[at]; at = root.next; check_add_root(c, destination, root.root, root.kind); }
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
fn check_reference_kind(p: Program&, node: i64) -> i64 {
    var current = node;
    while current >= 0 {
        let n = p.nodes[current];
        if n.kind == N_INDEX || n.kind == N_SLICE { return 1; }
        if n.kind == N_MEMBER || n.kind == N_UNARY || n.kind == N_CAST { current = n.left; }
        else { return 0; }
    }
    return 0;
}

fn check_type_property(p: Program&, ty: i64, property: i64) -> i64 {
    if ty < 0 { return 0; }
    var work: i64[>..] = [ty]; var scanned = 0; var result = 0;
    while scanned < work.len {
        let current = work[scanned]; scanned += 1;
        let t = p.types[current];
        if property == 0 && t.kind == TY_GENERIC { return 1; }
        if property == 1 && (t.kind == TY_REF || t.kind == TY_SLICE) { return 1; }
        if property == 3 && t.kind == TY_REF && t.length_storage >= 0 { return 1; }
        if property == 6 && t.kind == TY_REF && t.length_storage >= 0 && t.pool < 0 { return 1; }
        if property == 4 && t.kind == TY_ARRAY && t.array_kind == A_GROWSHRINK { return 1; }
        if property == 5 && (t.kind == TY_SLICE || t.kind == TY_FN || t.kind == TY_REF && (t.length_storage < 0 || t.pool >= 0)) { return 1; }
        if property == 2 {
            if t.kind == TY_ENUM {
                if (t.flags & F_VARIABLE_MODE) == 0 { continue; }
                if result < 1 { result = 1; }
            }
            if t.storage == 1 || t.kind == TY_REF && t.length_storage == 0 { result = 1; continue; }
            if t.kind == TY_ARRAY {
                if t.array_kind == A_GROW || t.array_kind == A_GROWSHRINK { return 2; }
                if t.array_kind == A_VAR || t.array_kind == A_LIMITED && t.count < 0 { result = 1; continue; }
            }
        }
        var traverse_element = t.kind == TY_ARRAY;
        var traverse_fields = t.kind == TY_STRUCT || t.kind == TY_ENUM;
        if property == 0 { traverse_element = traverse_element || t.kind == TY_REF || t.kind == TY_SLICE || t.kind == TY_FN || t.kind == TY_TUPLE; traverse_fields = traverse_fields || t.kind == TY_FN || t.kind == TY_TUPLE; }
        if property == 1 || property == 3 || property == 4 || property == 5 || property == 6 { traverse_fields = traverse_fields || t.kind == TY_TUPLE; }
        if traverse_element && t.element >= 0 {
            var seen = false; for old in work { if old == t.element { seen = true; } }
            if !seen { work.push(t.element); }
        }
        if traverse_fields {
            var part = t.first;
            while part >= 0 {
                let child = p.nodes[part].type_id;
                if child >= 0 {
                    var seen = false; for old in work { if old == child { seen = true; } }
                    if !seen { work.push(child); }
                }
                part = p.nodes[part].next;
            }
        }
    }
    return result;
}
fn check_contains_refs(p: Program&, ty: i64, depth: i64) -> bool { return check_type_property(p, ty, 1) != 0; }
fn check_size_class(p: Program&, ty: i64, depth: i64) -> i64 { return check_type_property(p, ty, 2); }
fn check_store_roots(p: Program&, c: Checker&, destination: i64, expression: i64) {
    if destination < 0 { return; }
    let stored_type = p.nodes[expression].type_id;
    if stored_type >= 0 && !check_contains_refs(p, stored_type, 0) { return; }
    var at = check_root_head(c, expression);
    while at >= 0 { let root = c.roots[at]; at = root.next; if root.root >= 0 { check_add_root(c, -destination - 10, root.root, root.kind); } }
}

fn check_note_effect(c: Checker&, root: i64, kind: i64) {
    if c.function_node < 0 || root < 0 { return; }
    for effect in c.effects {
        if effect.function_node == c.function_node && effect.root == root && effect.kind == kind { return; }
    }
    c.effects.push(CheckEffect { function_node: c.function_node, root: root, kind: kind });
}
fn check_global_use(p: Program&, c: Checker&, symbol: i64, token: i64) -> bool {
    if symbol < 0 || (p.symbols[symbol].flags & S_GLOBAL) == 0 { return true; }
    let vi = check_variable_index(c, symbol);
    if vi >= 0 && c.variables[vi].global_initialized { return true; }
    // Only pending globals need a cached use obligation: initialization is
    // monotone, unlike a function's flow-assignment snapshots.
    check_note_effect(c, symbol, 7);
    if !c.initializing_globals { return true; }
    diagnose(p, token, "global value is used before its initialization"); return false;
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
fn check_binding_same(p: Program&, a: i64, b: i64) -> bool {
    if a >= 0 && b >= 0 && p.types[a].kind == TY_FN && p.types[b].kind == TY_FN && p.types[a].declaration != p.types[b].declaration { return false; }
    return check_same_type(p, a, b);
}
fn check_bind_generic(p: Program&, c: Checker&, parameter: i64, value: i64, bindings: CheckList&) -> bool {
    for b_index in 0..bindings.count { let b = check_binding_at(c, bindings, b_index); if b.parameter == parameter { return check_binding_same(p, b.value, value); } }
    check_binding_push(c, bindings, TypeBinding { parameter: parameter, value: value }); return true;
}
recursive fn check_unify(p: Program&, c: Checker&, formal: i64, actual: i64, bindings: CheckList&) -> bool {
    if formal < 0 { return true; }
    if actual < 0 { return true; }
    let f = p.types[formal]; let a = p.types[actual];
    // Concrete copying destinations use argument conversion. A slice cannot
    // infer an unbound array element type or construct a fixed array.
    if f.kind == TY_ARRAY && f.array_kind != A_FIXED && a.kind == TY_SLICE {
        let concrete = check_substitute(p, c, formal, bindings);
        if !check_has_generic(p, concrete, 0) { return true; }
    }
    if a.kind == TY_ARRAY && a.element < 0 || a.kind == TY_REF && a.element == TYPE_VOID { return true; }
    if f.kind == TY_GENERIC {
        for index in 0..bindings.count { let binding = check_binding_at(c, bindings, index); if binding.parameter == f.declaration { return true; } }
        return check_bind_generic(p, c, f.declaration, actual, bindings);
    }
    if a.kind == TY_REF && f.kind != TY_REF { return check_unify(p, c, formal, a.element, bindings); }
    if f.kind == TY_REF && a.kind != TY_REF { return check_unify(p, c, f.element, actual, bindings); }
    if f.kind == TY_ARRAY || f.kind == TY_SLICE || f.kind == TY_REF {
        if f.kind != a.kind && !(f.kind == TY_SLICE && a.kind == TY_ARRAY) { return false; }
        if f.kind == TY_ARRAY && f.array_kind == A_FIXED && f.count != a.count { return false; }
        return check_unify(p, c, f.element, a.element, bindings);
    }
    if (f.kind == TY_STRUCT || f.kind == TY_ENUM) && (a.kind == TY_STRUCT || a.kind == TY_ENUM) {
        var fp = formal; var ap = actual;
        if f.kind == TY_STRUCT && f.pool >= 0 { fp = f.pool; }
        if a.kind == TY_STRUCT && a.pool >= 0 { ap = a.pool; }
        var fd = p.types[fp].declaration; var ad = p.types[ap].declaration;
        if fd >= 0 && p.nodes[fd].origin >= 0 { fd = p.nodes[fd].origin; }
        if ad >= 0 && p.nodes[ad].origin >= 0 { ad = p.nodes[ad].origin; }
        if fd != ad { return false; }
        var argument = p.types[fp].arguments; var other = p.types[ap].arguments;
        while argument >= 0 && other >= 0 {
            if !check_unify(p, c, p.nodes[argument].type_id, p.nodes[other].type_id, bindings) { return false; }
            argument = p.nodes[argument].next; other = p.nodes[other].next;
        }
        return argument < 0 && other < 0;
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
    if ty < 0 || bindings.count == 0 { return ty; }
    let t = p.types[ty];
    if t.kind == TY_GENERIC {
        for b_index in 0..bindings.count { let b = check_binding_at(c, bindings, b_index); if b.parameter == t.declaration { return b.value; } }
        return ty;
    }
    if t.kind == TY_ARRAY || t.kind == TY_SLICE || t.kind == TY_REF {
        let element = check_substitute(p, c, t.element, bindings);
        if element == t.element { return ty; }
        if t.kind == TY_ARRAY {
            var copy = t; copy.element = element;
            if t.array_kind == A_FIXED && t.count >= 0 { copy.size = t.count * p.types[element].size; if copy.size == 0 { copy.size = 1; } copy.align = p.types[element].align; }
            if t.array_kind == A_LIMITED && t.count >= 0 { var slots = t.count; if slots == 0 { slots = 1; } copy.size = t.length_storage + slots * p.types[element].size; }
            return add_type(p, copy);
        }
        var copy = t; copy.element = element; return add_type(p, copy);
    }
    if t.kind == TY_STRUCT || t.kind == TY_ENUM {
        var nominal = ty;
        if t.kind == TY_STRUCT && t.pool >= 0 { nominal = t.pool; }
        let instance = p.types[nominal];
        if instance.arguments >= 0 {
            var argument = instance.arguments; var first = -1; var last = -1; var changed = false;
            while argument >= 0 {
                let old = p.nodes[argument]; let value = check_substitute(p, c, old.type_id, bindings);
                if value != old.type_id { changed = true; }
                let copy = new_node(p, N_TYPE_ARG, old.token); p.nodes[copy].type_id = value;
                if first < 0 { first = copy; } else { p.nodes[last].next = copy; }
                last = copy; argument = old.next;
            }
            if changed {
                let declaration = p.nodes[instance.declaration].origin;
                if declaration < 0 { return ty; }
                var result = check_nominal_instance(p, c, declaration, first, p.nodes[instance.declaration].token);
                if result < 0 { return result; }
                if nominal != ty {
                    var variant = p.types[result].first;
                    while variant >= 0 { if same_name(p, p.nodes[variant].token, p.nodes[t.declaration].token) { result = p.nodes[variant].type_id; break; } variant = p.nodes[variant].next; }
                } else if (t.flags & F_VARIABLE_MODE) != 0 { result = check_variable_enum_type(p, c, result); }
                if (t.flags & TF_CONST) != 0 { result = check_const_type(p, result); }
                return result;
            }
        }
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
fn check_clone_node(p: Program&, c: Checker&, node: i64) -> Node {
    if c.clone_syntax && node < c.syntax_lookup.len && c.syntax_lookup[node] >= 0 { return c.syntax_nodes[c.syntax_lookup[node]]; }
    return p.nodes[node];
}
fn check_function_syntax(p: Program&, c: Checker&, function_node: i64) {
    let n = p.nodes[function_node]; var preserve = c.optional_globals || n.origin >= 0;
    var original = function_node;
    while original >= 0 && !preserve {
        let f = p.nodes[original]; let symbol = f.symbol;
        if f.kind == N_FUNCTION_VALUE { preserve = true; }
        if symbol >= 0 {
            let s = p.symbols[symbol];
            if s.owner >= 0 || s.scope > 0 && c.scopes[s.scope].namespace_node < 0 { preserve = true; }
        }
        original = f.origin;
    }
    var parameter = n.first;
    while parameter >= 0 && !preserve {
        let ty = p.nodes[parameter].type_id;
        if ty >= 0 && p.types[ty].kind == TY_FN { preserve = true; }
        parameter = p.nodes[parameter].next;
    }
    if !preserve || n.right < 0 { return; }
    while c.syntax_lookup.len <= function_node { c.syntax_lookup.push(-1); }
    if c.syntax_lookup[function_node] < 0 {
        c.syntax_lookup[function_node] = c.syntax_nodes.len; c.syntax_nodes.push(n);
    }
    let original_body = c.syntax_nodes[c.syntax_lookup[function_node]].right;
    var pending: i64[>..] = [original_body];
    while pending.len > 0 {
        let node = pending.pop(); if node < 0 { continue; }
        while c.syntax_lookup.len <= node { c.syntax_lookup.push(-1); }
        if c.syntax_lookup[node] >= 0 { continue; }
        let value = p.nodes[node]; c.syntax_lookup[node] = c.syntax_nodes.len; c.syntax_nodes.push(value);
        if value.kind == N_IMPORT { continue; }
        pending.push(value.first); pending.push(value.left); pending.push(value.right); pending.push(value.third); pending.push(value.next);
    }
}
recursive fn check_clone(p: Program&, c: Checker&, node: i64, bindings: CheckList&) -> i64 {
    if node < 0 { return -1; }
    if c.expanding {
        c.expansion_nodes += 1;
        if c.expansion_nodes > 100000 {
            if c.expansion_nodes == 100001 { diagnose(p, p.nodes[node].token, "const for expansion exceeds 100000 generated nodes"); }
            return -1;
        }
    }
    let saved_syntax = c.clone_syntax;
    if node == c.syntax_body { c.clone_syntax = true; }
    var copy = check_clone_node(p, c, node);
    if node == c.syntax_function { copy.right = c.syntax_body; }
    copy.type_id = check_substitute(p, c, copy.type_id, bindings);
    copy.coerced_type = check_substitute(p, c, copy.coerced_type, bindings);
    if copy.kind == N_PARAM {
        for binding_index in 0..bindings.count {
            let binding = check_binding_at(c, bindings, binding_index);
            if binding.parameter == node { copy.type_id = binding.value; }
        }
    }
    let resolved_symbol = copy.symbol;
    copy.symbol = -1; copy.scope = -1; copy.captures = -1; copy.flags &= ~(F_CHECKED | F_REACHABLE | F_CAPTURE | F_RETURNS | F_DIVERGES | F_RETURN_MOVE);
    if copy.kind == N_FUNCTION || copy.kind == N_FUNCTION_VALUE { copy.type_id = -1; }
    if copy.kind == N_RECORD && resolved_symbol >= 0 && resolved_symbol < p.nodes.len && p.nodes[resolved_symbol].kind == N_VARIANT { copy.symbol = resolved_symbol; }
    if copy.kind == N_CALL && resolved_symbol >= 0 && ((copy.flags & F_SYNTHETIC) != 0 || (p.symbols[resolved_symbol].flags & S_BUILTIN) != 0) { copy.symbol = resolved_symbol; copy.flags |= F_SYNTHETIC; }
    let old_first = copy.first; let old_left = copy.left; let old_right = copy.right; var old_third = copy.third;
    if copy.kind == N_CALL && (copy.flags & F_DISPATCH) != 0 { old_third = -1; copy.flags &= ~F_DISPATCH; copy.aux = -1; }
    copy.first = -1; copy.last = -1; copy.left = -1; copy.right = -1; copy.third = -1; copy.next = -1;
    let id = p.nodes.len; p.nodes.push(copy);
    var child = old_first;
    while child >= 0 { append_child(p, id, check_clone(p, c, child, bindings)); child = check_clone_node(p, c, child).next; }
    p.nodes[id].left = check_clone(p, c, old_left, bindings);
    if copy.kind == N_RECORD { p.nodes[id].right = old_right; }
    else { p.nodes[id].right = check_clone(p, c, old_right, bindings); }
    p.nodes[id].third = check_clone(p, c, old_third, bindings);
    if c.expanding && c.expansion_nodes > 100000 { c.clone_syntax = saved_syntax; return id; }
    // left and third may own lists (function results and generic parameters).
    if copy.kind == N_FUNCTION || copy.kind == N_FUNCTION_VALUE || copy.kind == N_TYPE_FN || copy.kind == N_CONST_FOR {
        var old = old_left; var tail = p.nodes[id].left;
        if old >= 0 { old = check_clone_node(p, c, old).next; }
        while old >= 0 {
            let item = check_clone(p, c, old, bindings); p.nodes[tail].next = item; tail = item; old = check_clone_node(p, c, old).next;
        }
    }
    if copy.kind == N_FUNCTION || copy.kind == N_STRUCT || copy.kind == N_ENUM {
        var old = old_third; var tail = p.nodes[id].third;
        if old >= 0 { old = check_clone_node(p, c, old).next; }
        while old >= 0 {
            let item = check_clone(p, c, old, bindings); p.nodes[tail].next = item; tail = item; old = check_clone_node(p, c, old).next;
        }
    }
    if copy.kind == N_VARIABLE {
        var old = old_right; var tail = p.nodes[id].right;
        if old >= 0 { old = check_clone_node(p, c, old).next; }
        while old >= 0 {
            let item = check_clone(p, c, old, bindings); p.nodes[tail].next = item; tail = item; old = check_clone_node(p, c, old).next;
        }
    }
    c.clone_syntax = saved_syntax; return id;
}

struct CheckConstant {
    valid: bool = false, value: i64 = 0, type_id: i64 = TYPE_I64,
    literal: bool = false, extent_fixed: bool = false,
}
fn check_constant_wrap(value: i64, type_id: i64) -> i64 {
    let bits = check_integer_bits(type_id);
    if bits >= 64 { return value; }
    let mask = (1 << bits) - 1; let wrapped = value & mask;
    if !check_unsigned(type_id) && (wrapped & (1 << (bits - 1))) != 0 { return wrapped | ~mask; }
    return wrapped;
}
fn check_constant_fits(value: CheckConstant, type_id: i64) -> bool {
    if value.type_id == TYPE_U64 && value.value < 0 { return type_id == TYPE_U64; }
    return value.value >= check_min(type_id) && (type_id == TYPE_U64 || value.value <= check_max(type_id));
}
recursive fn check_constant_extent(p: Program&, c: Checker&, node: i64, capacity: bool, depth: i64) -> CheckConstant {
    if node < 0 || depth > 64 || p.nodes[node].kind != N_NAME { return CheckConstant {}; }
    let n = p.nodes[node]; var symbol = n.symbol; if symbol < 0 { symbol = check_lookup_name(p, c, node); }
    if symbol < 0 || (p.symbols[symbol].flags & S_GLOBAL) == 0 { return CheckConstant {}; }
    let declaration = p.symbols[symbol].node;
    if declaration < 0 { return CheckConstant {}; }
    let d = p.nodes[declaration];
    if d.kind != N_VARIABLE || (d.flags & (F_REFERENCE | F_REUSABLE)) != 0 || check_list_count(p, d.first) > 1 { return CheckConstant {}; }
    if d.left >= 0 {
        let syntax = p.nodes[d.left];
        if syntax.kind == N_TYPE_ARRAY && syntax.right >= 0 && (capacity && syntax.integer == A_LIMITED || !capacity && syntax.integer == A_FIXED) {
            var extent = check_constant(p, c, syntax.right, depth + 1); extent.type_id = TYPE_I64; extent.literal = false; extent.extent_fixed = true; return extent;
        }
        return CheckConstant {};
    }
    if d.right < 0 { return CheckConstant {}; }
    let init = p.nodes[d.right];
    if init.kind == N_NAME {
        let extent = check_constant_extent(p, c, d.right, capacity, depth + 1);
        if (d.flags & F_VAR) != 0 && !extent.extent_fixed { return CheckConstant {}; }
        return extent;
    }
    if capacity { return CheckConstant {}; }
    if init.kind == N_STRING {
        if (d.flags & F_VAR) != 0 { return CheckConstant {}; }
        return CheckConstant { valid: true, value: p.tokens[init.token].text_len };
    }
    if init.kind == N_ARRAY || init.kind == N_FILL {
        if init.third >= 0 { return CheckConstant {}; }
        var fixed = false;
        if init.type_id >= 0 { fixed = p.types[init.type_id].kind == TY_ARRAY && p.types[init.type_id].array_kind == A_FIXED; }
        else if init.first < 0 { fixed = true; }
        else { let element = p.nodes[init.first]; fixed = element.kind == N_INTEGER || element.kind == N_BOOL || element.kind == N_FLOAT || element.kind == N_STRING; }
        if (d.flags & F_VAR) != 0 && !fixed { return CheckConstant {}; }
        if init.right >= 0 { var extent = check_constant(p, c, init.right, depth + 1); extent.type_id = TYPE_I64; extent.literal = false; extent.extent_fixed = fixed; return extent; }
        return CheckConstant { valid: true, value: check_list_count(p, init.first), extent_fixed: fixed };
    }
    return CheckConstant {};
}
recursive fn check_constant(p: Program&, c: Checker&, node: i64, depth: i64) -> CheckConstant {
    if node < 0 || depth > 64 { return CheckConstant {}; }
    let n = p.nodes[node];
    if n.kind == N_INTEGER || n.kind == N_BOOL {
        var type_id = TYPE_I64; if (n.flags & F_UNSIGNED) != 0 { type_id = TYPE_U64; }
        if n.type_id >= 0 && check_integer(check_numeric_value_type(p, n.type_id)) { type_id = check_numeric_value_type(p, n.type_id); }
        return CheckConstant { valid: true, value: n.integer, type_id: type_id, literal: true };
    }
    if n.kind == N_CAST && (n.flags & F_SYNTHETIC) != 0 {
        let destination = check_numeric_value_type(p, check_resolve_type(p, c, n.right));
        if check_integer(destination) {
            var value = check_constant(p, c, n.left, depth + 1);
            let complement = check_complement_input(p, c, n.left);
            if complement.valid && complement.value <= check_max(destination) { value = CheckConstant { valid: true, value: check_constant_wrap(~complement.value, destination), type_id: destination }; }
            if value.valid && check_constant_fits(value, destination) { value.type_id = destination; value.literal = false; return value; }
        }
        return CheckConstant {};
    }
    if n.kind == N_NAME {
        var symbol = n.symbol; if symbol < 0 { symbol = check_lookup_name(p, c, node); }
        if symbol >= 0 && (p.symbols[symbol].flags & S_MUTABLE) == 0 {
            let declaration = p.symbols[symbol].node;
            if declaration >= 0 && p.nodes[declaration].kind == N_VARIABLE {
                var value = check_constant(p, c, p.nodes[declaration].right, depth + 1);
                let annotation = p.nodes[declaration].left;
                if value.valid && annotation >= 0 {
                    let type_id = check_numeric_value_type(p, check_resolve_type(p, c, annotation));
                    if !check_integer(type_id) { return CheckConstant {}; }
                    let complement = check_complement_input(p, c, p.nodes[declaration].right);
                    if complement.valid && complement.value <= check_max(type_id) { value.value = check_constant_wrap(~complement.value, type_id); value.type_id = type_id; }
                    if !check_constant_fits(value, type_id) { return CheckConstant {}; }
                    value.type_id = type_id;
                }
                value.literal = false; return value;
            }
        }
    }
    if n.kind == N_MEMBER && (token_is(p, n.token, "len") || token_is(p, n.token, "cap")) { return check_constant_extent(p, c, n.left, token_is(p, n.token, "cap"), depth + 1); }
    if n.kind == N_CALL && n.symbol >= 0 && (p.symbols[n.symbol].flags & S_BUILTIN) != 0 {
        let builtin = p.symbols[n.symbol].index;
        if builtin == 21 || builtin == 22 { return check_constant_extent(p, c, n.first, builtin == 22, depth + 1); }
    }
    if n.kind == N_UNARY {
        let a = check_constant(p, c, n.left, depth + 1); if !a.valid { return a; }
        if n.integer == T_MINUS {
            if a.type_id == TYPE_U64 && a.value == -9223372036854775808 && a.literal { return CheckConstant { valid: true, value: a.value, type_id: TYPE_I64, literal: true }; }
            if check_unsigned(a.type_id) || a.value == -9223372036854775808 { return CheckConstant {}; }
            let value = -a.value;
            if value < check_min(a.type_id) || value > check_max(a.type_id) { return CheckConstant {}; }
            return CheckConstant { valid: true, value: value, type_id: a.type_id, literal: a.literal };
        }
        if n.integer == T_BITNOT { return CheckConstant { valid: true, value: check_constant_wrap(~a.value, a.type_id), type_id: a.type_id, literal: a.literal }; }
        if n.integer == T_NOT { var value = 0; if a.value == 0 { value = 1; } return CheckConstant { valid: true, value: value }; }
    }
    if n.kind == N_BINARY {
        let a = check_constant(p, c, n.left, depth + 1); let b = check_constant(p, c, n.right, depth + 1);
        if !a.valid || !b.valid { return CheckConstant {}; }
        let x = a.value; let y = b.value; let op = n.integer; var type_id = a.type_id;
        if op != T_SHL && op != T_SHR && a.type_id != b.type_id {
            if b.literal && check_constant_fits(b, a.type_id) { type_id = a.type_id; }
            else if a.literal && check_constant_fits(a, b.type_id) { type_id = b.type_id; }
            else {
                let ab = check_integer_bits(a.type_id); let bb = check_integer_bits(b.type_id);
                if ab < bb && (check_unsigned(a.type_id) == check_unsigned(b.type_id) || !check_unsigned(b.type_id)) { type_id = b.type_id; }
                else if bb < ab && (check_unsigned(a.type_id) == check_unsigned(b.type_id) || !check_unsigned(a.type_id)) { type_id = a.type_id; }
                else { return CheckConstant {}; }
            }
        }
        var value = 0;
        if op == T_PLUS || op == T_MINUS || op == T_MUL {
            if !check_unsigned(type_id) {
                if op == T_PLUS && (y > 0 && x > 9223372036854775807 - y || y < 0 && x < -9223372036854775808 - y) { return CheckConstant {}; }
                if op == T_MINUS && (y < 0 && x > 9223372036854775807 + y || y > 0 && x < -9223372036854775808 + y) { return CheckConstant {}; }
                if op == T_MUL && x != 0 && y != 0 {
                    if x == -1 && y == -9223372036854775808 || y == -1 && x == -9223372036854775808 { return CheckConstant {}; }
                    if x > 0 && y > 0 && x > 9223372036854775807 / y || x > 0 && y < 0 && y < -9223372036854775808 / x || x < 0 && y > 0 && x < -9223372036854775808 / y || x < 0 && y < 0 && x < 9223372036854775807 / y { return CheckConstant {}; }
                }
            }
            if op == T_PLUS { value = ((x as! u64) + (y as! u64)) as! i64; }
            else if op == T_MINUS { value = ((x as! u64) - (y as! u64)) as! i64; }
            else { value = ((x as! u64) * (y as! u64)) as! i64; }
            if check_unsigned(type_id) { value = check_constant_wrap(value, type_id); }
            else if value < check_min(type_id) || value > check_max(type_id) { return CheckConstant {}; }
        } else if op == T_DIV || op == T_MOD {
            if y == 0 { return CheckConstant {}; }
            if check_unsigned(type_id) {
                if op == T_DIV { value = ((x as! u64) / (y as! u64)) as! i64; } else { value = ((x as! u64) % (y as! u64)) as! i64; }
            } else if x == -9223372036854775808 && y == -1 {
                if op == T_DIV { return CheckConstant {}; } value = 0;
            } else { if op == T_DIV { value = x / y; } else { value = x % y; } }
        } else if op == T_BITAND { value = x & y; }
        else if op == T_BITOR { value = x | y; }
        else if op == T_XOR { value = x ^ y; }
        else if op == T_SHL || op == T_SHR {
            let count = y & (check_integer_bits(type_id) - 1);
            if op == T_SHL { value = ((x as! u64) << count) as! i64; }
            else if check_unsigned(type_id) { value = ((x as! u64) >> count) as! i64; } else { value = x >> count; }
            value = check_constant_wrap(value, type_id);
        } else {
            var truth = false;
            if op == T_EQ { truth = x == y; }
            else if op == T_NEQ { truth = x != y; }
            else if op == T_LT { if check_unsigned(type_id) { truth = (x as! u64) < (y as! u64); } else { truth = x < y; } }
            else if op == T_LTEQ { if check_unsigned(type_id) { truth = (x as! u64) <= (y as! u64); } else { truth = x <= y; } }
            else if op == T_GT { if check_unsigned(type_id) { truth = (x as! u64) > (y as! u64); } else { truth = x > y; } }
            else if op == T_GTEQ { if check_unsigned(type_id) { truth = (x as! u64) >= (y as! u64); } else { truth = x >= y; } }
            else if op == T_ANDAND { truth = x != 0 && y != 0; }
            else if op == T_OROR { truth = x != 0 || y != 0; }
            else { return CheckConstant {}; }
            if truth { value = 1; } type_id = TYPE_I64;
        }
        return CheckConstant { valid: true, value: value, type_id: type_id, literal: a.literal && b.literal };
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
        let existing = check_lookup_scope(p, c, p.nodes[param].token, c.scope);
        if existing < 0 {
            if p.nodes[param].symbol < 0 { check_declare(p, c, param, c.scope); }
            else {
                // Each lexical layout scope binds the declaration's same
                // generic identity, even after an earlier instantiation.
                let binding = new_node(p, N_TYPE_PARAM, p.nodes[param].token);
                p.nodes[binding].type_id = p.nodes[param].type_id; check_declare(p, c, binding, c.scope);
            }
        } else if !check_same_type(p, p.symbols[existing].type_id, p.nodes[param].type_id) { diagnose(p, p.nodes[param].token, "duplicate generic parameter in this scope"); }
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
    if p.types[element].kind == TY_VOID || p.types[element].size == 0 && size_class == 0 || p.types[element].kind == TY_ARRAY && p.types[element].array_kind == A_FIXED && p.types[element].count == 0 {
        diagnose(p, token, "array elements require nonzero size");
    }
}

recursive fn check_resolve_type(p: Program&, c: Checker&, syntax: i64) -> i64 {
    if syntax < 0 { return -1; }
    if p.nodes[syntax].expansion_binding == -3 { diagnose(p, p.nodes[syntax].token, "const for binding is not a type or cannot take type arguments"); return -1; }
    if p.nodes[syntax].type_id >= 0 { return p.nodes[syntax].type_id; }
    let n = p.nodes[syntax]; var result = -1;
    if n.kind == N_TYPE_NAME || n.kind == N_NAME {
        if n.left >= 0 {
            let outer = check_resolve_type(p, c, n.left);
            if outer >= 0 && p.types[outer].kind == TY_ENUM {
                if p.types[outer].size == -1 { check_prepare_variants(p, outer); }
                else { check_layout_nominal(p, c, outer); }
                var variant = p.types[outer].first;
                while variant >= 0 {
                    if same_name(p, p.nodes[variant].token, n.token) {
                        result = p.nodes[variant].type_id;
                        if c.type_indirections == 0 { check_layout_variant(p, c, result); }
                        break;
                    }
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
                let symbol = check_lookup_name(p, c, syntax, S_TYPE);
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
                } else { diagnose(p, n.token, "unknown type name"); }
            }
        }
    } else if n.kind == N_TYPE_REF {
        c.type_indirections += 1; let element = check_resolve_type(p, c, n.left); c.type_indirections -= 1;
        let flags = n.flags & (TF_CONST | TF_OPTIONAL);
        if element >= 0 && p.types[element].kind == TY_REF { var copy = p.types[element]; copy.flags |= flags; result = add_type(p, copy); }
        else { result = check_type(p, TY_REF, element, 0, -1, flags); }
        if n.right >= 0 {
            let storage = check_resolve_type(p, c, n.right);
            var copy = p.types[result];
            if storage >= 0 && p.types[storage].storage == 1 { copy.length_storage = 0; }
            else if check_integer(storage) && check_unsigned(storage) { copy.length_storage = p.types[storage].size; }
            else { diagnose(p, n.token, "relative reference offset must use an unsigned integer storage"); }
            if n.third >= 0 {
                let pool = check_lookup_global_name(p, c, n.third);
                if pool < 0 { diagnose(p, n.token, "unknown reference pool"); }
                copy.pool = pool;
            }
            if copy.length_storage > 0 { copy.size = copy.length_storage; }
            if copy.length_storage == 0 { copy.size = 0; }
            copy.align = 1; result = add_type(p, copy);
        }
    } else if n.kind == N_TYPE_ARRAY {
        if n.integer == A_SLICE { c.type_indirections += 1; }
        let element = check_resolve_type(p, c, n.left);
        if n.integer == A_SLICE { c.type_indirections -= 1; }
        if n.integer != A_SLICE { check_array_element(p, c, element, n.integer, n.token); }
        var count = -1;
        if n.right >= 0 {
            check_constant_names(p, c, n.right);
            let constant = check_constant(p, c, n.right, 0);
            if constant.valid { count = constant.value; }
            else if n.integer == A_FIXED || n.integer == A_LIMITED { diagnose(p, n.token, "array size or capacity must be a constant integer"); }
        }
        if count < 0 && n.right >= 0 && (n.integer == A_FIXED || n.integer == A_LIMITED) { diagnose(p, n.token, "array size or capacity must be nonnegative"); }
        if n.integer == A_SLICE { result = check_type(p, TY_SLICE, element, -1, -1, n.flags & TF_CONST); }
        else { result = check_array_type(p, element, count, n.integer, n.flags & TF_CONST); }
        if n.third >= 0 {
            let length = check_resolve_type(p, c, n.third);
            var copy = p.types[result]; copy.length_explicit = true;
            if length >= 0 && p.types[length].storage == 1 { copy.length_storage = 0; }
            else if check_integer(length) && check_unsigned(length) { copy.length_storage = p.types[length].size; }
            else { diagnose(p, n.token, "array length storage must be an unsigned integer"); }
            result = add_type(p, copy);
        }
        if n.integer == A_LIMITED && count >= 0 && element >= 0 {
            var copy = p.types[result]; result = add_type(p, copy);
            var bytes = 1;
            if count > 255 { bytes = 2; }
            if count > 65535 { bytes = 4; }
            if count > 4294967295 { bytes = 8; }
            p.types[result].length_storage = bytes;
            var slots = count; if slots == 0 { slots = 1; }
            p.types[result].size = bytes + slots * p.types[element].size;
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
        while ret >= 0 { p.nodes[ret].type_id = check_value_annotation(p, c, ret, check_resolve_type(p, c, ret)); ret = p.nodes[ret].next; }
        result = add_type(p, Type { kind: TY_FN, element: check_tuple(p, n.left), declaration: syntax, first: n.first, size: p.pointer_bytes, align: p.pointer_bytes });
    } else if n.kind == N_TYPEOF {
        result = check_loaded_type(p, check_single_expression(p, c, n.left));
    } else if n.kind == N_TYPE_DEDUCED {
        result = check_type(p, TY_GENERIC, -1, 0, syntax, 0);
    } else { diagnose(p, n.token, "invalid type syntax"); }
    if result >= 0 && (n.flags & F_VARIABLE_MODE) != 0 {
        if p.types[result].kind != TY_ENUM { diagnose(p, n.token, "variable mode applies only to an enum type"); }
        else { result = check_variable_enum_type(p, c, result); }
    }
    if result >= 0 && (n.flags & F_INDEX_TYPE) != 0 && n.third >= 0 {
        let pool = check_lookup_global_name(p, c, n.third);
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
    let root = owner >= 0 && p.nodes[owner].kind == N_STRUCT && (p.nodes[owner].flags & F_ROOT) != 0;
    if root {
        diagnose(p, p.nodes[owner].token, "root structs are not yet supported: their independently stored fields have no layout");
    }
    while field >= 0 {
        let n = p.nodes[field];
        if root && (n.flags & F_PAD) != 0 {
            diagnose(p, p.nodes[owner].token, "root structs have no packed byte layout; padding belongs inside a component");
        }
        if (n.flags & F_PAD) != 0 {
            var bytes = n.integer;
            if n.right >= 0 {
                check_constant_names(p, c, n.right);
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
            // Field ownership is the only change to an indexed hook predicate.
            if symbol >= 0 && symbol < c.format_scan_end && (p.symbols[symbol].owner < 0) != (owner < 0) {
                c.format_scan_end = 0; c.has_format_hooks = false;
            }
            p.symbols[symbol].type_id = ty; p.symbols[symbol].owner = owner;
            p.symbols[symbol].offset = size; p.symbols[symbol].index = index;
            if ty >= 0 {
                if p.types[ty].kind == TY_VOID { diagnose(p, n.token, "field cannot have void type"); }
                if check_size_class(p, ty, 0) == 2 && n.next >= 0 && !root {
                    diagnose(p, n.token, "a resizable field must be the final field; use root struct for independently stored fields");
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
fn check_prepare_variants(p: Program&, enum_type: i64) {
    let declaration = p.types[enum_type].declaration; var variant = p.nodes[declaration].first; var tag = 0;
    while variant >= 0 {
        let existing = p.nodes[variant].type_id;
        if existing < 0 || p.types[existing].declaration != variant {
            p.nodes[variant].type_id = add_type(p, Type { kind: TY_STRUCT, declaration: variant, first: p.nodes[variant].first, size: -2, align: 1, pool: enum_type });
        }
        p.nodes[variant].integer = tag; tag += 1; variant = p.nodes[variant].next;
    }
    p.types[enum_type].first = p.nodes[declaration].first; p.types[enum_type].count = tag;
}
recursive fn check_finish_record_layout(p: Program&, type_id: i64, first: i64, size: i64) {
    p.types[type_id].size = size; p.types[type_id].align = 1; p.types[type_id].first = first;
    var field = first; var last = -1; var byte_record = false;
    while field >= 0 {
        let ft = p.nodes[field].type_id;
        if ft >= 0 && (p.types[ft].storage == 1 || p.types[ft].kind == TY_REF && p.types[ft].length_storage == 0) {
            if !byte_record { p.types[type_id].prefix = p.nodes[field].integer; }
            byte_record = true;
        }
        last = field; field = p.nodes[field].next;
    }
    if byte_record { p.types[type_id].size = 24; p.types[type_id].align = 4; p.types[type_id].tail = last; }
    else if last >= 0 && p.nodes[last].type_id >= 0 && check_size_class(p, p.nodes[last].type_id, 0) > 0 {
        p.types[type_id].prefix = p.nodes[last].integer; p.types[type_id].tail = last; p.types[type_id].align = 4;
    }
}
recursive fn check_layout_variant(p: Program&, c: Checker&, type_id: i64) {
    if type_id < 0 { return; }
    let t = p.types[type_id]; let variant = t.declaration;
    if t.size >= 0 { return; }
    if t.size == -1 { diagnose(p, p.nodes[variant].token, "variant contains itself by value"); return; }
    p.types[type_id].size = -1;
    let saved = c.scope;
    if t.pool >= 0 { c.scope = p.nodes[p.types[t.pool].declaration].scope; }
    check_enter(c, c.function_node);
    let size = check_layout_fields(p, c, p.nodes[variant].first, variant);
    check_finish_record_layout(p, type_id, p.nodes[variant].first, size);
    p.nodes[variant].flags |= F_CHECKED; c.scope = saved;
}
recursive fn check_variable_enum_type(p: Program&, c: Checker&, base: i64) -> i64 {
    let t = p.types[base]; var result = -1; var declaration_type = base;
    if (t.flags & F_VARIABLE_MODE) != 0 {
        for candidate, id in p.types { if candidate.kind == TY_ENUM && candidate.declaration == t.declaration && (candidate.flags & F_VARIABLE_MODE) == 0 { declaration_type = id; break; } }
    }
    let declaration_layout = p.types[declaration_type];
    for candidate, id in p.types {
        if candidate.kind == TY_ENUM && candidate.declaration == t.declaration && candidate.flags == (t.flags | F_VARIABLE_MODE) { result = id; break; }
    }
    if result < 0 { var copy = t; copy.flags |= F_VARIABLE_MODE; copy.size = 24; copy.align = 4; result = add_type(p, copy); }
    if p.types[base].size == -1 || (p.nodes[t.declaration].flags & F_CHECKED) == 0 { return result; }
    var size = 24; var align = 4; var variant = declaration_layout.first;
    while variant >= 0 {
        let payload = p.nodes[variant].type_id;
        if check_size_class(p, payload, 0) == 0 { p.nodes[variant].aux = 0; }
        else {
            var alignment = p.types[payload].align; if alignment < 4 { alignment = 4; }
            if alignment > align { align = alignment; }
            size = check_align(size, alignment); p.nodes[variant].aux = size; size += p.types[payload].size;
        }
        variant = p.nodes[variant].next;
    }
    p.types[result].first = declaration_layout.first; p.types[result].count = declaration_layout.count;
    p.types[result].length_storage = declaration_layout.length_storage; p.types[result].size = check_align(size, align); p.types[result].align = align;
    return result;
}
recursive fn check_layout_nominal(p: Program&, c: Checker&, type_id: i64) {
    if type_id < 0 { return; }
    let t = p.types[type_id]; let declaration = t.declaration;
    if t.kind == TY_ENUM && (t.flags & F_VARIABLE_MODE) != 0 {
        var plain = -1;
        for candidate, id in p.types { if candidate.kind == TY_ENUM && candidate.declaration == declaration && (candidate.flags & F_VARIABLE_MODE) == 0 { plain = id; break; } }
        if plain >= 0 { check_layout_nominal(p, c, plain); check_variable_enum_type(p, c, type_id); }
        return;
    }
    if t.kind == TY_STRUCT && declaration >= 0 && p.nodes[declaration].kind == N_VARIANT { check_layout_variant(p, c, type_id); return; }
    if declaration < 0 || (p.nodes[declaration].flags & F_CHECKED) != 0 { return; }
    if t.size < 0 { diagnose(p, p.nodes[declaration].token, "aggregate contains itself by value"); return; }
    p.types[type_id].size = -1;
    let saved = c.scope;
    if p.nodes[declaration].scope >= 0 { c.scope = p.nodes[declaration].scope; }
    check_enter(c, c.function_node); p.nodes[declaration].scope = c.scope;
    check_ensure_generics(p, c, declaration);
    if t.kind == TY_STRUCT {
        let size = check_layout_fields(p, c, p.nodes[declaration].first, declaration);
        check_finish_record_layout(p, type_id, p.nodes[declaration].first, size);
    } else {
        check_prepare_variants(p, type_id);
        var variant = p.nodes[declaration].first; var maximum = 0; var maximum_class = 0;
        while variant >= 0 {
            let payload = p.nodes[variant].type_id; check_layout_variant(p, c, payload);
            if p.types[payload].size > maximum { maximum = p.types[payload].size; }
            let payload_class = check_size_class(p, payload, 0); if payload_class > maximum_class { maximum_class = payload_class; }
            variant = p.nodes[variant].next;
        }
        if maximum_class == 2 {
            variant = p.nodes[declaration].first;
            while variant >= 0 {
                let payload = p.nodes[variant].type_id;
                if check_size_class(p, payload, 0) < 2 && check_type_property(p, payload, 6) != 0 { diagnose(p, p.nodes[declaration].token, "a resizable enum cannot have a non-resizable payload containing self-relative references: its payloads bind only by value"); }
                variant = p.nodes[variant].next;
            }
        }
        var tag_bytes = 1; if p.types[type_id].count > 256 { tag_bytes = 2; }
        if p.types[type_id].count > 65536 { diagnose(p, p.nodes[declaration].token, "enum has too many variants"); }
        p.types[type_id].size = tag_bytes + maximum; p.types[type_id].align = 1; p.types[type_id].length_storage = tag_bytes;
    }
    p.nodes[declaration].flags |= F_CHECKED; c.scope = saved;
    if t.kind == TY_ENUM {
        let end = p.types.len;
        for id in 0..end { if p.types[id].kind == TY_ENUM && p.types[id].declaration == declaration && (p.types[id].flags & F_VARIABLE_MODE) != 0 { check_variable_enum_type(p, c, id); } }
    }
}
fn check_enum_fixed_reason(p: Program&, type_id: i64) -> i64 {
    let t = p.types[type_id];
    if t.kind != TY_ENUM || (t.flags & F_VARIABLE_MODE) != 0 { return 0; }
    var reason = 0; var variant = t.first;
    while variant >= 0 {
        let payload = p.nodes[variant].type_id;
        if payload >= 0 && !check_has_generic(p, payload, 0) {
            if check_size_class(p, payload, 0) > 0 { return 1; }
            if check_type_property(p, payload, 6) != 0 { reason = 2; }
        }
        variant = p.nodes[variant].next;
    }
    return reason;
}
struct CheckTypeUse { type_id: i64, token: i64 }
fn check_validate_type_uses(p: Program&) {
    var pending: CheckTypeUse[>..] = []; var seen: bool[>..] = [];
    seen.resize(p.types.len, false);
    for n in p.nodes {
        if (n.flags & F_CHECKED) == 0 { continue; }
        if n.kind == N_VARIABLE || n.kind == N_ARRAY || n.kind == N_FILL || n.kind == N_CAST {
            pending.push(CheckTypeUse { type_id: n.type_id, token: n.token });
        }
        if n.kind == N_VARIABLE || n.kind == N_FOR {
            var binding = n.first;
            while binding >= 0 {
                pending.push(CheckTypeUse { type_id: p.nodes[binding].type_id, token: p.nodes[binding].token });
                binding = p.nodes[binding].next;
            }
        }
        if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE {
            pending.push(CheckTypeUse { type_id: n.type_id, token: n.token });
        }
    }
    for t in p.types {
        if t.kind != TY_STRUCT { continue; }
        var field = t.first;
        while field >= 0 {
            pending.push(CheckTypeUse { type_id: p.nodes[field].type_id, token: p.nodes[field].token });
            field = p.nodes[field].next;
        }
    }
    var at = 0;
    while at < pending.len {
        let use = pending[at]; at += 1;
        if use.type_id < 0 || seen[use.type_id] { continue; }
        seen[use.type_id] = true; let t = p.types[use.type_id];
        if t.kind == TY_ENUM {
            let reason = check_enum_fixed_reason(p, use.type_id);
            if reason == 1 { diagnose(p, use.token, "fixed-mode enum requires fixed-size payloads; use variable mode (E..)"); }
            if reason == 2 { diagnose(p, use.token, "fixed-mode enum payloads cannot hold self-relative references; use variable mode (E..)"); }
        }
        if t.kind == TY_ARRAY || t.kind == TY_SLICE || t.kind == TY_REF || t.kind == TY_FN {
            pending.push(CheckTypeUse { type_id: t.element, token: use.token });
        }
        if t.kind == TY_STRUCT || t.kind == TY_ENUM || t.kind == TY_FN || t.kind == TY_TUPLE {
            var field = t.first;
            while field >= 0 {
                pending.push(CheckTypeUse { type_id: p.nodes[field].type_id, token: use.token });
                field = p.nodes[field].next;
            }
        }
    }
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
            if !check_binding_same(p, b.value, c.bindings[spec.binding_start + i].value) { equal = false; }
        }
        if equal { return p.symbols[spec.symbol].type_id; }
    }
    var same_declaration = 0; var type_chain = c.type_chain;
    for index in 0..type_chain.count { if check_list_at(c, type_chain, index) == declaration { same_declaration += 1; } }
    if same_declaration >= 16 || c.inference_depth >= 64 { diagnose(p, token, "generic type instantiation does not reach a finite set"); return -1; }
    let saved_chain = c.type_chain; check_list_push(c, c.type_chain, declaration);
    c.inference_depth += 1;
    let copy = check_clone(p, c, declaration, bindings);
    p.nodes[copy].third = -1; p.nodes[copy].origin = declaration; p.nodes[copy].scope = outer_scope;
    var kind = TY_STRUCT; if p.nodes[declaration].kind == N_ENUM { kind = TY_ENUM; }
    let ty = add_type(p, Type { kind: kind, declaration: copy, first: p.nodes[copy].first,
        name_token: p.nodes[copy].token });
    p.nodes[copy].type_id = ty;
    var argument_first = -1; var argument_last = -1;
    for binding_index in 0..bindings.count {
        let binding = check_binding_at(c, bindings, binding_index); let argument = new_node(p, N_TYPE_ARG, p.nodes[copy].token);
        p.nodes[argument].type_id = binding.value;
        if argument_first < 0 { argument_first = argument; } else { p.nodes[argument_last].next = argument; }
        argument_last = argument;
    }
    p.types[ty].arguments = argument_first;
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
    c.scope = saved; c.inference_depth -= 1; c.type_chain = saved_chain;
    return ty;
}

fn check_addressable(p: Program&, node: i64) -> bool {
    if node < 0 { return false; }
    let n = p.nodes[node];
    return n.kind == N_NAME || n.kind == N_INDEX || n.kind == N_MEMBER ||
        n.kind == N_UNARY && n.integer == T_MUL;
}
fn check_frame_object(p: Program&, type_id: i64) -> bool {
    var current = type_id;
    loop {
        if current < 0 || p.types[current].kind != TY_STRUCT || check_size_class(p, current, 0) != 2 { return false; }
        let t = p.types[current];
        if t.declaration < 0 || p.nodes[t.declaration].kind != N_STRUCT { return false; }
        let tail = t.tail;
        if tail < 0 || (p.nodes[tail].flags & F_PAD) != 0 { return false; }
        var field = t.first;
        while field >= 0 && field != tail {
            let n = p.nodes[field];
            if (n.flags & F_PAD) == 0 && (check_size_class(p, n.type_id, 0) != 0 || check_type_property(p, n.type_id, 3) != 0) { return false; }
            field = n.next;
        }
        current = p.nodes[tail].type_id;
        if current >= 0 && p.types[current].kind == TY_ARRAY { return true; }
    }
}
fn check_referenceable(p: Program&, node: i64) -> bool {
    let n = p.nodes[node];
    if n.type_id < 0 || check_size_class(p, n.type_id, 0) != 2 || n.kind == N_NAME { return true; }
    var member = node;
    loop {
        if p.nodes[member].kind != N_MEMBER { return false; }
        let owner = p.nodes[member].left; var ty = p.nodes[owner].type_id;
        if ty < 0 { return false; }
        let reference = p.types[ty].kind == TY_REF;
        if reference { ty = p.types[ty].element; }
        if !check_frame_object(p, ty) { return false; }
        if reference || p.nodes[owner].kind != N_MEMBER { return true; }
        member = owner;
    }
}
fn check_require_referenceable(p: Program&, c: Checker&, node: i64) {
    if !check_addressable(p, node) { return; }
    // Raw rendering call conversion borrows an already-checked place.
    if c.render_reference { return; }
    if !check_referenceable(p, node) { diagnose(p, p.nodes[node].token, "cannot reference a resizable value nested in a variable-size prefix or an ADT payload; reference the owning variable instead"); }
}
fn check_readonly(p: Program&, c: Checker&, node: i64, slot: bool = false) -> bool {
    var current = node; var place = slot;
    while current >= 0 {
        let n = p.nodes[current]; var view = false;
        let storage = check_storage_type(p, current);
        if storage >= 0 && p.types[storage].kind != TY_REF && p.types[storage].kind != TY_SLICE && (p.types[storage].flags & TF_CONST) != 0 && !(place && (n.kind == N_MEMBER || n.kind == N_INDEX)) { return true; }
        if storage >= 0 && (p.types[storage].storage == 1 || place && p.types[storage].kind == TY_REF && p.types[storage].length_storage == 0) { return true; }
        if n.type_id >= 0 { view = p.types[n.type_id].kind == TY_REF || p.types[n.type_id].kind == TY_SLICE; }
        if n.kind == N_STRING { return true; }
        if n.kind == N_MEMBER && n.symbol >= 0 && p.nodes[n.symbol].kind == N_FIELD && (p.nodes[n.symbol].flags & F_CONST) != 0 && !(view && !place) { return true; }
        if n.type_id >= 0 && (p.types[n.type_id].flags & TF_CONST) != 0 && !(place && (n.kind == N_MEMBER || n.kind == N_INDEX)) { return true; }
        if view && !place {
            let t = p.types[n.type_id];
            if t.kind == TY_SLICE && n.kind == N_UNARY && n.integer == T_MUL { current = n.left; continue; }
            if t.kind != TY_REF || t.length_storage < 0 || t.pool >= 0 { return false; }
        }
        var root_at = check_root_head(c, current);
        while root_at >= 0 { let root = c.roots[root_at]; if root.root == -1 { return true; } root_at = root.next; }
        if n.kind == N_NAME { let vi = check_variable_index(c, n.symbol); return vi >= 0 && c.variables[vi].readonly; }
        if n.kind == N_CALL || n.kind == N_FILL { return true; }
        if n.kind == N_MEMBER || n.kind == N_INDEX || n.kind == N_SLICE || n.kind == N_UNARY { current = n.left; place = false; }
        else { return false; }
    }
    return false;
}
fn check_borrow_readonly(p: Program&, c: Checker&, node: i64) -> bool {
    if check_readonly(p, c, node, true) { return true; }
    let actual = p.nodes[node].type_id;
    return actual >= 0 && p.types[actual].kind != TY_REF && p.types[actual].kind != TY_SLICE && check_readonly(p, c, node);
}
fn check_argument_readonly(p: Program&, c: Checker&, node: i64, expected: i64) -> bool {
    let actual = p.nodes[node].type_id;
    if actual < 0 || expected < 0 { return false; }
    if p.types[expected].kind == TY_SLICE && p.types[actual].kind == TY_REF && p.types[p.types[actual].element].kind == TY_SLICE { return (p.types[actual].flags & TF_CONST) != 0 || (p.types[p.types[actual].element].flags & TF_CONST) != 0; }
    if p.types[expected].kind == TY_REF && p.types[actual].kind != TY_REF {
        let storage = check_storage_type(p, node);
        if storage >= 0 && p.types[storage].storage == 1 { return true; }
        return check_borrow_readonly(p, c, node);
    }
    return check_readonly(p, c, node);
}
fn check_own_local(p: Program&, c: Checker&, node: i64) -> bool {
    if node < 0 || c.function_node < 0 { return false; }
    let n = p.nodes[node];
    if n.kind != N_NAME || n.symbol < 0 { return false; }
    let symbol = p.symbols[n.symbol];
    return symbol.owner == c.function_node && (symbol.flags & S_GLOBAL) == 0 &&
        symbol.type_id >= 0 && p.types[symbol.type_id].kind != TY_REF;
}
fn check_slot_value(p: Program&, c: Checker&, value: i64, expected: i64, aggregate_slot: bool = false) {
    if value < 0 || expected < 0 { return; }
    let t = p.types[expected];
    if aggregate_slot && check_contains_refs(p, expected, 0) {
        var root_at = check_root_head(c, value);
        while root_at >= 0 {
            let root = c.roots[root_at]; root_at = root.next;
            if root.root >= 0 && root.kind == 1 && check_type_property(p, p.symbols[root.root].type_id, 4) != 0 {
                diagnose(p, p.nodes[value].token, "a reference into grow-shrink storage cannot be stored in an aggregate slot");
            }
        }
    }
    if c.reachable && check_size_class(p, expected, 0) > 0 && t.kind != TY_REF && check_addressable(p, value) && check_size_class(p, p.nodes[value].type_id, 0) > 0 && !(c.returning && check_own_local(p, c, value)) {
        diagnose(p, p.nodes[value].token, "non-fixed storage requires explicit copy when passed or stored by value");
    }
    if (t.kind == TY_REF || t.kind == TY_SLICE) && (t.flags & TF_CONST) == 0 && check_readonly(p, c, value) {
        diagnose(p, p.nodes[value].token, "storing a read-only reference or slice requires a const slot");
    }
}
recursive fn check_bottom(p: Program&, node: i64) -> bool {
    if node < 0 { return false; }
    let n = p.nodes[node];
    if (n.flags & F_DIVERGES) != 0 && n.kind != N_FUNCTION && n.kind != N_FUNCTION_VALUE || n.kind == N_RETURN || n.kind == N_BREAK || n.kind == N_CONTINUE { return true; }
    if n.kind == N_BLOCK && (n.flags & F_EARLY) == 0 && n.last >= 0 { return check_bottom(p, n.last); }
    if n.kind == N_IF { return n.third >= 0 && check_bottom(p, n.right) && check_bottom(p, n.third); }
    if n.kind == N_CALL && n.symbol >= 0 {
        let s = p.symbols[n.symbol]; return (s.flags & S_BUILTIN) != 0 && (s.index == 4 || s.index == 5);
    }
    return false;
}

fn check_loaded_type(p: Program&, ty: i64) -> i64 {
    if ty >= 0 && p.types[ty].kind == TY_INT && p.types[ty].storage == 1 { return TYPE_I64; }
    if ty >= 0 && p.types[ty].kind == TY_REF && p.types[ty].length_storage >= 0 {
        let t = p.types[ty];
        return check_type(p, TY_REF, t.element, t.count, t.declaration, t.flags);
    }
    return check_plain_value_type(p, ty);
}
fn check_read_value_type(p: Program&, c: Checker&, node: i64, ty: i64) -> i64 {
    // Varint storage can still bind a reference to its encoded cell.
    // Numeric decay follows that decision in check_value.
    var value = check_plain_value_type(p, ty);
    if ty >= 0 && p.types[ty].kind == TY_REF { value = check_loaded_type(p, ty); }
    if ty >= 0 && p.types[ty].kind == TY_REF && p.types[ty].length_storage >= 0 && p.types[ty].pool < 0 && check_readonly(p, c, node) { value = check_const_type(p, value); }
    if value != ty && node >= 0 { p.nodes[node].type_id = value; }
    return value;
}

fn check_value_annotation(p: Program&, c: Checker&, syntax: i64, ty: i64) -> i64 {
    if syntax < 0 || p.nodes[syntax].kind != N_TYPE_NAME { return ty; }
    let symbol = check_lookup_name(p, c, syntax, S_TYPE);
    if symbol >= 0 && p.symbols[symbol].node >= 0 && p.nodes[p.symbols[symbol].node].kind == N_TYPE_PARAM { return check_loaded_type(p, ty); }
    return ty;
}

fn check_index_value(p: Program&, node: i64, fallback: i64) -> i64 {
    if node >= 0 {
        let ty = p.nodes[node].type_id;
        if ty >= 0 && p.types[ty].kind == TY_INT && p.types[ty].index_type >= 0 { return ty; }
    }
    return fallback;
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

// A branch construct adapts as a constant only when every reachable value does.
recursive fn check_integer_constants(p: Program&, c: Checker&, node: i64, depth: i64 = 0) -> bool {
    if node < 0 || depth > 64 { return false; }
    let n = p.nodes[node];
    if check_bottom(p, node) { return true; }
    if n.kind == N_BLOCK && (n.flags & F_TAIL) != 0 { return check_integer_constants(p, c, n.last, depth + 1); }
    if n.kind == N_IF && n.third >= 0 {
        return check_integer_constants(p, c, n.right, depth + 1) && check_integer_constants(p, c, n.third, depth + 1);
    }
    if n.kind == N_MATCH && n.first >= 0 {
        var arm = n.first;
        while arm >= 0 {
            if !check_integer_constants(p, c, p.nodes[arm].right, depth + 1) { return false; }
            arm = p.nodes[arm].next;
        }
        return true;
    }
    return check_literal_tree(p, node, depth + 1) && check_constant(p, c, node, depth + 1).valid;
}

struct CheckFlex { valid: bool = false, flexible: bool = false, minimum: i64 = 0, maximum: i64 = 0 }
recursive fn check_flex_integer(p: Program&, c: Checker&, node: i64, depth: i64 = 0) -> CheckFlex {
    if node < 0 || depth > 64 { return CheckFlex {}; }
    let n = p.nodes[node];
    if check_bottom(p, node) { return CheckFlex { valid: true }; }
    if n.kind == N_UNARY && n.integer == T_BITNOT {
        var child = check_flex_integer(p, c, n.left, depth + 1);
        if child.valid && (child.flexible || child.minimum >= 0) { child.flexible = true; return child; }
    }
    let constant = check_constant(p, c, node, 0);
    if constant.valid && check_integer_constants(p, c, node, depth + 1) && !(check_unsigned(check_numeric_value_type(p, constant.type_id)) && constant.value < 0) {
        return CheckFlex { valid: true, minimum: constant.value, maximum: constant.value };
    }
    if n.kind == N_BLOCK && (n.flags & F_TAIL) != 0 { return check_flex_integer(p, c, n.last, depth + 1); }
    if n.kind == N_IF && n.third >= 0 {
        let a = check_flex_integer(p, c, n.right, depth + 1); let b = check_flex_integer(p, c, n.third, depth + 1);
        if !a.valid || !b.valid { return CheckFlex {}; }
        var out = a; out.flexible = a.flexible || b.flexible;
        if b.minimum < out.minimum { out.minimum = b.minimum; } if b.maximum > out.maximum { out.maximum = b.maximum; } return out;
    }
    if n.kind == N_MATCH && n.first >= 0 {
        var out = CheckFlex { valid: true }; var first = true; var arm = n.first;
        while arm >= 0 {
            let value = check_flex_integer(p, c, p.nodes[arm].right, depth + 1); if !value.valid { return CheckFlex {}; }
            if first { out = value; first = false; }
            else { if value.minimum < out.minimum { out.minimum = value.minimum; } if value.maximum > out.maximum { out.maximum = value.maximum; } out.flexible = out.flexible || value.flexible; }
            arm = p.nodes[arm].next;
        }
        return out;
    }
    if n.kind == N_BINARY {
        let left = check_flex_integer(p, c, n.left, depth + 1); if !left.valid { return CheckFlex {}; }
        if n.integer == T_SHL || n.integer == T_SHR {
            if !check_integer(check_numeric_value_type(p, p.nodes[n.right].type_id)) { return CheckFlex {}; }
            var out = left; out.flexible = true; return out;
        }
        if n.integer == T_PLUS || n.integer == T_MINUS || n.integer == T_MUL || n.integer == T_DIV || n.integer == T_MOD || n.integer == T_BITAND || n.integer == T_BITOR || n.integer == T_XOR {
            let right = check_flex_integer(p, c, n.right, depth + 1);
            if !right.valid || !left.flexible && !right.flexible { return CheckFlex {}; }
            var out = left; out.flexible = true;
            if right.minimum < out.minimum { out.minimum = right.minimum; } if right.maximum > out.maximum { out.maximum = right.maximum; } return out;
        }
    }
    return CheckFlex {};
}
fn check_flex_fits(p: Program&, c: Checker&, node: i64, destination: i64) -> bool {
    let value = check_flex_integer(p, c, node);
    return value.valid && value.flexible && value.minimum >= check_min(destination) && value.maximum <= check_max(destination);
}
recursive fn check_retype_integer(p: Program&, c: Checker&, node: i64, type_id: i64) {
    if node < 0 { return; } let n = p.nodes[node];
    if !check_flex_integer(p, c, node).flexible { check_expect(p, c, node, n.type_id, type_id); return; }
    if n.kind == N_BLOCK && (n.flags & F_TAIL) != 0 { check_retype_integer(p, c, n.last, type_id); p.nodes[node].type_id = type_id; return; }
    if n.kind == N_IF {
        check_retype_integer(p, c, n.right, type_id); check_retype_integer(p, c, n.third, type_id); p.nodes[node].type_id = type_id; return;
    }
    if n.kind == N_MATCH {
        var arm = n.first;
        while arm >= 0 { check_retype_integer(p, c, p.nodes[arm].right, type_id); arm = p.nodes[arm].next; }
        p.nodes[node].type_id = type_id; return;
    }
    if n.kind == N_BINARY {
        check_retype_integer(p, c, n.left, type_id);
        if n.integer != T_SHL && n.integer != T_SHR { check_retype_integer(p, c, n.right, type_id); }
        p.nodes[node].type_id = type_id; p.nodes[node].aux = type_id; return;
    }
    if n.kind == N_UNARY && n.integer == T_BITNOT { check_retype_integer(p, c, n.left, type_id); p.nodes[node].type_id = type_id; return; }
    check_expect(p, c, node, n.type_id, type_id);
}

recursive fn check_float_literal_tree(p: Program&, node: i64, depth: i64) -> bool {
    if node < 0 || depth > 64 { return false; }
    let n = p.nodes[node];
    if n.kind == N_FLOAT || n.kind == N_INTEGER { return true; }
    if n.kind == N_NAME && n.symbol >= 0 && check_float(check_numeric_value_type(p, n.type_id)) {
        let symbol = p.symbols[n.symbol]; let declaration = symbol.node;
        if declaration >= 0 && (symbol.flags & S_MUTABLE) == 0 && p.nodes[declaration].kind == N_VARIABLE && p.nodes[declaration].left < 0 {
            return check_float_literal_tree(p, p.nodes[declaration].right, depth + 1);
        }
    }
    if n.kind == N_BLOCK && (n.flags & F_TAIL) != 0 { return check_float_literal_tree(p, n.last, depth + 1); }
    if n.kind == N_IF && n.third >= 0 { return check_float_literal_tree(p, n.right, depth + 1) && check_float_literal_tree(p, n.third, depth + 1); }
    if n.kind == N_UNARY && n.integer == T_MINUS { return check_float_literal_tree(p, n.left, depth + 1); }
    if n.kind == N_BINARY && (n.integer == T_PLUS || n.integer == T_MINUS || n.integer == T_MUL || n.integer == T_DIV || n.integer == T_MOD) {
        let left = p.nodes[n.left].type_id; let right = p.nodes[n.right].type_id;
        if !check_float(check_numeric_value_type(p, n.type_id)) { return check_literal_tree(p, node, depth + 1); }
        return (check_integer(check_numeric_value_type(p, left)) || check_float_literal_tree(p, n.left, depth + 1)) &&
               (check_integer(check_numeric_value_type(p, right)) || check_float_literal_tree(p, n.right, depth + 1));
    }
    return false;
}
recursive fn check_float_constant_tree(p: Program&, node: i64, depth: i64) -> bool {
    if node < 0 || depth > 64 { return false; }
    let n = p.nodes[node];
    if n.kind == N_FLOAT || n.kind == N_INTEGER { return true; }
    if n.kind == N_NAME && n.symbol >= 0 {
        let symbol = p.symbols[n.symbol]; let declaration = symbol.node;
        if declaration >= 0 && (symbol.flags & S_MUTABLE) == 0 && p.nodes[declaration].kind == N_VARIABLE && p.nodes[declaration].left < 0 &&
           ((symbol.flags & S_GLOBAL) != 0 || check_float(check_numeric_value_type(p, n.type_id))) {
            return check_float_constant_tree(p, p.nodes[declaration].right, depth + 1);
        }
    }
    if n.kind == N_UNARY && n.integer == T_MINUS { return check_float_constant_tree(p, n.left, depth + 1); }
    if n.kind == N_BINARY { return check_float_constant_tree(p, n.left, depth + 1) && check_float_constant_tree(p, n.right, depth + 1); }
    return false;
}
recursive fn check_rely_named(p: Program&, c: Checker&, node: i64, depth: i64 = 0) {
    if node < 0 || depth > 64 || check_bottom(p, node) { return; }
    let n = p.nodes[node];
    if n.kind == N_NAME && n.symbol >= 0 {
        let symbol = p.symbols[n.symbol]; let declaration = symbol.node;
        if declaration < 0 || (symbol.flags & S_MUTABLE) != 0 || p.nodes[declaration].kind != N_VARIABLE || p.nodes[declaration].left >= 0 { return; }
        if !((symbol.flags & S_GLOBAL) != 0 && check_literal_tree(p, node, 0) || check_float(check_numeric_value_type(p, n.type_id)) && check_float_literal_tree(p, node, 0)) { return; }
        let index = check_variable_index(c, n.symbol);
        if index >= 0 {
            if c.variables[index].writable_use >= 0 { diagnose(p, n.token, "use as a literal depends on a named constant bound to a writable reference"); }
            if c.variables[index].literal_use < 0 { c.variables[index].literal_use = n.token; }
        }
        check_rely_named(p, c, p.nodes[declaration].right, depth + 1); return;
    }
    if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE || n.kind == N_CALL || n.kind == N_IMPORT { return; }
    if n.kind == N_LOOP || n.kind == N_BLOCK && (n.flags & F_EARLY) != 0 {
        var values = CheckList {}; check_collect_break_values(p, c, node, node, values);
        for index in 0..values.count { check_rely_named(p, c, check_list_at(c, values, index), depth + 1); }
        if n.kind == N_BLOCK && (n.flags & F_TAIL) != 0 { check_rely_named(p, c, n.last, depth + 1); }
        return;
    }
    if n.kind == N_BLOCK && (n.flags & F_TAIL) != 0 { check_rely_named(p, c, n.last, depth + 1); return; }
    if n.kind == N_IF {
        check_rely_named(p, c, n.right, depth + 1);
        check_rely_named(p, c, n.third, depth + 1); return;
    }
    if n.kind == N_MATCH {
        var arm = n.first;
        while arm >= 0 { check_rely_named(p, c, p.nodes[arm].right, depth + 1); arm = p.nodes[arm].next; }
        return;
    }
    check_rely_named(p, c, n.left, depth + 1); check_rely_named(p, c, n.right, depth + 1); check_rely_named(p, c, n.third, depth + 1);
}
recursive fn check_constant_names(p: Program&, c: Checker&, node: i64, depth: i64 = 0, depend: bool = true) {
    if node < 0 || depth > 64 { return; }
    let n = p.nodes[node];
    if n.kind == N_NAME {
        check_parameter_default_name(p, c, node, false);
        var symbol = n.symbol; if symbol < 0 { symbol = check_lookup_name(p, c, node); } if symbol < 0 { return; }
        let binding = p.symbols[symbol];
        if (binding.flags & S_GLOBAL) == 0 {
            diagnose(p, n.token, "compile-time constant names a local binding or type parameter"); return;
        }
        if !depend || (binding.flags & S_MUTABLE) != 0 || binding.node < 0 || p.nodes[binding.node].kind != N_VARIABLE { return; }
        let index = check_variable_index(c, symbol);
        if index >= 0 {
            if c.variables[index].writable_use >= 0 { diagnose(p, n.token, "compile-time constant depends on a binding taken by writable reference"); }
            if c.variables[index].literal_use < 0 { c.variables[index].literal_use = n.token; }
        }
        check_constant_names(p, c, p.nodes[binding.node].right, depth + 1); return;
    }
    if n.kind == N_MEMBER && (token_is(p, n.token, "len") || token_is(p, n.token, "cap")) {
        let extent = check_constant_extent(p, c, n.left, token_is(p, n.token, "cap"), 0);
        check_constant_names(p, c, n.left, depth + 1, depend && !extent.extent_fixed); return;
    }
    if n.kind == N_ARRAY || n.kind == N_FILL { check_constant_names(p, c, n.right, depth + 1); return; }
    if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE || n.kind == N_IMPORT { return; }
    if n.kind == N_CALL {
        if n.symbol >= 0 && (p.symbols[n.symbol].flags & S_BUILTIN) != 0 {
            let builtin = p.symbols[n.symbol].index;
            if builtin == 21 || builtin == 22 {
                let extent = check_constant_extent(p, c, n.first, builtin == 22, 0);
                check_constant_names(p, c, n.first, depth + 1, depend && !extent.extent_fixed);
            }
        }
        return;
    }
    check_constant_names(p, c, n.left, depth + 1, depend); check_constant_names(p, c, n.right, depth + 1, depend);
    check_constant_names(p, c, n.third, depth + 1, depend);
}
fn check_nonnegative_get(c: Checker&, node: i64) -> i64 {
    if node < 0 || node >= c.node_nonnegative.len { return -2; }
    return c.node_nonnegative[node];
}
fn check_nonnegative_set(c: Checker&, node: i64, proof: i64) {
    while c.node_nonnegative.len <= node { c.node_nonnegative.push(-2); }
    c.node_nonnegative[node] = proof;
}
fn check_nonnegative_rely(p: Program&, c: Checker&, proof: i64, token: i64) {
    var symbol = proof;
    while symbol >= 0 {
        let index = check_variable_index(c, symbol); if index < 0 { return; }
        let value = c.variables[index];
        if value.writable_use >= 0 { diagnose(p, token, "comparison relies on a non-negative binding already exposed through a writable reference"); }
        if value.nonnegative_use < 0 { c.variables[index].nonnegative_use = token; }
        symbol = value.nonnegative;
    }
}
fn check_nonnegative_result(p: Program&, c: Checker&, node: i64, original: Node, result: i64) {
    var proof = -2;
    if result >= 0 && p.types[result].kind == TY_INT {
        let n = p.nodes[node];
        if original.kind == N_INTEGER && (original.integer >= 0 || (original.flags & F_UNSIGNED) != 0) { proof = -1; }
        else if original.kind == N_NAME && n.symbol >= 0 {
            let index = check_variable_index(c, n.symbol);
            if index >= 0 && c.variables[index].nonnegative >= -1 { proof = n.symbol; }
        } else if n.kind == N_CALL && (n.flags & F_PROPERTY) != 0 && n.symbol >= 0 && (p.symbols[n.symbol].flags & S_BUILTIN) != 0 {
            let builtin = p.symbols[n.symbol].index;
            if builtin == 21 || builtin == 22 { proof = -1; }
        } else if original.kind == N_BLOCK && (n.flags & F_TAIL) != 0 && (n.flags & F_EARLY) == 0 {
            proof = check_nonnegative_get(c, n.last);
        } else if original.kind == N_IF && original.third >= 0 {
            if check_bottom(p, original.right) { proof = check_nonnegative_get(c, original.third); }
            else if check_bottom(p, original.third) { proof = check_nonnegative_get(c, original.right); }
            else if check_integer_constants(p, c, node) {
                let constants = check_flex_integer(p, c, node);
                if constants.valid && !constants.flexible && constants.minimum >= 0 { check_rely_named(p, c, node); proof = -1; }
            }
        } else if original.kind == N_MATCH && check_integer_constants(p, c, node) {
            let constants = check_flex_integer(p, c, node);
            if constants.valid && !constants.flexible && constants.minimum >= 0 { check_rely_named(p, c, node); proof = -1; }
        }
    }
    check_nonnegative_set(c, node, proof);
}
fn check_named_writable(p: Program&, c: Checker&, root: i64, token: i64) {
    let index = check_variable_index(c, root); if index < 0 { return; }
    if c.variables[index].nonnegative_use >= 0 { diagnose(p, token, "writable reference may invalidate a comparison that relies on a non-negative binding"); }
    if c.variables[index].literal_use >= 0 { diagnose(p, token, "named constant is bound to a writable reference after a use depends on its initializer value"); }
    if c.variables[index].writable_use < 0 { c.variables[index].writable_use = token; }
}
fn check_wrap_numeric_cast(p: Program&, node: i64, type_id: i64) {
    let original = p.nodes[node]; var inner = original; inner.next = -1; inner.flags &= ~F_TAIL;
    let left = p.nodes.len; p.nodes.push(inner); let syntax = operation_type(p, type_id, original.token);
    p.nodes[node] = Node { kind: N_CAST, token: original.token, next: original.next, left: left, right: syntax,
        type_id: type_id, flags: F_CHECKED | F_SYNTHETIC | (original.flags & F_TAIL), scope: original.scope };
}
recursive fn check_retype_float(p: Program&, c: Checker&, node: i64, type_id: i64) {
    if node < 0 || p.nodes[node].type_id == type_id { return; }
    let n = p.nodes[node];
    if check_integer(check_numeric_value_type(p, n.type_id)) { check_wrap_numeric_cast(p, node, type_id); return; }
    if n.kind == N_FLOAT { p.nodes[node].type_id = type_id; return; }
    if n.kind == N_BLOCK && (n.flags & F_TAIL) != 0 { check_retype_float(p, c, n.last, type_id); p.nodes[node].type_id = type_id; return; }
    if n.kind == N_IF {
        check_retype_float(p, c, n.right, type_id); check_retype_float(p, c, n.third, type_id); p.nodes[node].type_id = type_id; return;
    }
    if n.kind == N_BINARY && !check_float_constant_tree(p, node, 0) {
        check_retype_float(p, c, n.left, type_id); check_retype_float(p, c, n.right, type_id);
        p.nodes[node].type_id = type_id; p.nodes[node].aux = type_id; return;
    }
    if n.kind == N_UNARY && n.integer == T_MINUS && !check_float_constant_tree(p, node, 0) {
        check_retype_float(p, c, n.left, type_id); p.nodes[node].type_id = type_id; return;
    }
    // Named literal-like floats keep their stored f64 value. Their use
    // rounds that value; only an unfixed computation changes its operations.
    check_wrap_numeric_cast(p, node, type_id);
}

recursive fn check_complement_input(p: Program&, c: Checker&, node: i64, depth: i64 = 0) -> CheckConstant {
    if node < 0 || depth > 64 { return CheckConstant {}; }
    let n = p.nodes[node];
    if n.kind == N_UNARY && n.integer == T_BITNOT {
        let value = check_constant(p, c, n.left, 0);
        if value.valid && value.value >= 0 && check_literal_tree(p, n.left, 0) { return value; }
    }
    if n.kind == N_NAME {
        var symbol = n.symbol; if symbol < 0 { symbol = check_lookup_name(p, c, node); }
        if symbol >= 0 && (p.symbols[symbol].flags & (S_GLOBAL | S_MUTABLE)) == S_GLOBAL {
            let declaration = p.symbols[symbol].node;
            if declaration >= 0 && p.nodes[declaration].kind == N_VARIABLE && p.nodes[declaration].left < 0 { return check_complement_input(p, c, p.nodes[declaration].right, depth + 1); }
        }
    }
    return CheckConstant {};
}
fn check_width_constant(p: Program&, c: Checker&, node: i64, expected: i64) -> CheckConstant {
    let destination = check_numeric_value_type(p, expected);
    if !check_integer(destination) { return CheckConstant {}; }
    let input = check_complement_input(p, c, node);
    if !input.valid || input.value > check_max(destination) { return CheckConstant {}; }
    var value = ~input.value;
    if check_unsigned(destination) && check_integer_bits(destination) < 64 { value = value & ((1 << check_integer_bits(destination)) - 1); }
    return CheckConstant { valid: true, value: value };
}
recursive fn check_empty_tree(p: Program&, node: i64) -> bool {
    if node < 0 { return false; }
    let n = p.nodes[node];
    if n.kind == N_ARRAY { return n.first < 0 && n.right < 0; }
    if n.kind == N_BLOCK && (n.flags & F_TAIL) != 0 { return check_empty_tree(p, n.last); }
    if n.kind == N_IF { return n.third >= 0 && check_empty_tree(p, n.right) && check_empty_tree(p, n.third); }
    if n.kind == N_MATCH {
        if n.first < 0 { return false; }
        var arm = n.first;
        while arm >= 0 { if !check_empty_tree(p, p.nodes[arm].right) { return false; } arm = p.nodes[arm].next; }
        return true;
    }
    return false;
}
recursive fn check_branch_array_literal(p: Program&, node: i64) -> bool {
    if node < 0 { return false; }
    let n = p.nodes[node];
    if n.kind == N_ARRAY || n.kind == N_FILL { return true; }
    if n.kind == N_BLOCK && (n.flags & F_TAIL) != 0 { return check_branch_array_literal(p, n.last); }
    if n.kind == N_IF { return check_branch_array_literal(p, n.right) || check_branch_array_literal(p, n.third); }
    if n.kind == N_MATCH { var arm = n.first; while arm >= 0 { if check_branch_array_literal(p, p.nodes[arm].right) { return true; } arm = p.nodes[arm].next; } }
    return false;
}
fn check_storage_type(p: Program&, node: i64) -> i64 {
    let n = p.nodes[node];
    if n.kind == N_NAME && n.symbol >= 0 && n.symbol < p.symbols.len { return p.symbols[n.symbol].type_id; }
    if n.kind == N_MEMBER && n.symbol >= 0 { return p.nodes[n.symbol].type_id; }
    if n.kind == N_INDEX {
        var array = p.nodes[n.left].type_id;
        while array >= 0 && p.types[array].kind == TY_REF { array = p.types[array].element; }
        if array >= 0 && (p.types[array].kind == TY_ARRAY || p.types[array].kind == TY_SLICE) { return p.types[array].element; }
    }
    if n.kind == N_UNARY && n.integer == T_MUL {
        let reference = p.nodes[n.left].type_id;
        if reference >= 0 && p.types[reference].kind == TY_REF { return p.types[reference].element; }
    }
    return n.type_id;
}
recursive fn check_exit_conversion(p: Program&, c: Checker&, node: i64, target: i64, expected: i64) -> i64 {
    if node < 0 { return 0; }
    let n = p.nodes[node];
    if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE || n.kind == N_IMPORT { return 0; }
    if n.kind == N_BREAK && n.symbol == target {
        if n.left < 0 { if expected == TYPE_VOID { return 0; } return -1; }
        return check_conversion(p, c, n.left, p.nodes[n.left].type_id, expected);
    }
    var score = 0; var child = n.first;
    while child >= 0 { let value = check_exit_conversion(p, c, child, target, expected); if value < 0 { return -1; } if value > score { score = value; } child = p.nodes[child].next; }
    let left = check_exit_conversion(p, c, n.left, target, expected); if left < 0 { return -1; } if left > score { score = left; }
    let right = check_exit_conversion(p, c, n.right, target, expected); if right < 0 { return -1; } if right > score { score = right; }
    if n.kind != N_CALL { let third = check_exit_conversion(p, c, n.third, target, expected); if third < 0 { return -1; } if third > score { score = third; } }
    return score;
}
recursive fn check_exit_expect(p: Program&, c: Checker&, node: i64, target: i64, expected: i64) {
    if node < 0 { return; }
    let n = p.nodes[node];
    if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE || n.kind == N_IMPORT { return; }
    if n.kind == N_BREAK && n.symbol == target { if n.left >= 0 { check_value(p, c, n.left, expected); } return; }
    var child = n.first;
    while child >= 0 { check_exit_expect(p, c, child, target, expected); child = p.nodes[child].next; }
    check_exit_expect(p, c, n.left, target, expected); check_exit_expect(p, c, n.right, target, expected);
    if n.kind != N_CALL { check_exit_expect(p, c, n.third, target, expected); }
}
recursive fn check_conversion(p: Program&, c: Checker&, expression: i64, source_type: i64, destination_type: i64) -> i64 {
    if destination_type < 0 || check_bottom(p, expression) { return 0; }
    if destination_type >= 0 && p.types[destination_type].kind == TY_INT && p.types[destination_type].index_type >= 0 {
        let actual = check_index_value(p, expression, source_type);
        if actual < 0 || p.types[actual].kind != TY_INT || p.types[actual].index_type < 0 { return -1; }
        let a = p.types[actual]; let d = p.types[destination_type];
        if a.pool != d.pool || (a.flags & F_BOUND_TYPE) != 0 && (d.flags & F_BOUND_TYPE) == 0 || a.count > d.count { return -1; }
        if check_same_type(p, actual, destination_type) { return 0; } return 2;
    }
    var source = check_numeric_value_type(p, source_type); let destination = check_numeric_value_type(p, destination_type);
    if destination >= 0 && p.types[destination].kind == TY_REF {
        source = source_type;
        let n = p.nodes[expression];
        if n.kind == N_UNARY && n.integer == T_MUL && (n.flags & F_SYNTHETIC) != 0 { return check_conversion(p, c, n.left, p.nodes[n.left].type_id, destination); }
        if check_addressable(p, expression) && check_operation_same(p, check_storage_type(p, expression), p.types[destination].element) { source = p.types[destination].element; }
    }
    if destination < 0 || check_bottom(p, expression) { return 0; }
    if source < 0 { return -1; }
    let branch = p.nodes[expression];
    if !c.literal_comparison && (branch.kind == N_ARRAY || branch.kind == N_FILL) && branch.first >= 0 &&
       (p.types[destination].kind == TY_SLICE || p.types[destination].kind == TY_REF) && check_size_class(p, source, 0) > 0 { return -1; }
    if branch.kind == N_LOOP { return check_exit_conversion(p, c, branch.right, expression, destination); }
    if branch.kind == N_BLOCK && (branch.flags & F_EARLY) != 0 {
        let exits = check_exit_conversion(p, c, expression, expression, destination);
        if exits < 0 { return -1; }
        if (branch.flags & F_TAIL) == 0 || branch.last < 0 || check_bottom(p, branch.last) {
            if source == TYPE_VOID && destination != TYPE_VOID { return -1; }
            return exits;
        }
    }
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
    if check_integer(destination) && check_flex_fits(p, c, expression, destination) { return 1; }
    if check_width_constant(p, c, expression, destination).valid { return 1; }
    let s = p.types[source]; let d = p.types[destination]; let n = p.nodes[expression];
    if s.kind == TY_GENERIC || d.kind == TY_GENERIC { return 1; }
    if s.kind == TY_BOOL && d.kind == TY_BOOL { return 1; }
    if n.kind == N_INTEGER && check_integer(destination) {
        if (n.flags & F_UNSIGNED) != 0 { if destination == TYPE_U64 { return 1; } return -1; }
        if n.integer >= check_min(destination) && n.integer <= check_max(destination) { return 1; }
        return -1;
    }
    if check_integer(destination) && check_literal_tree(p, expression, 0) {
        let constant = check_constant(p, c, expression, 0);
        if constant.valid && constant.value >= check_min(destination) && constant.value <= check_max(destination) { return 1; }
    }
    if check_float(destination) && check_float_literal_tree(p, expression, 0) { return 1; }
    if check_integer(source) && check_float(destination) { return 4; }
    if source == TYPE_F32 && destination == TYPE_F64 { return 2; }
    if check_integer(source) && check_integer(destination) {
        let sb = check_integer_bits(source); let db = check_integer_bits(destination);
        if check_unsigned(source) == check_unsigned(destination) && sb < db { return 2; }
        if check_unsigned(source) && !check_unsigned(destination) && sb < db { return 2; }
    }
    if s.kind == TY_REF && d.kind != TY_REF {
        if d.kind == TY_SLICE && (s.flags & TF_CONST) != 0 && (d.flags & TF_CONST) == 0 && s.element >= 0 &&
           (p.types[s.element].kind == TY_ARRAY || p.types[s.element].kind == TY_SLICE) { return -1; }
        return check_conversion(p, c, expression, s.element, destination);
    }
    if d.kind == TY_REF {
        if n.kind == N_NULL && (d.flags & TF_OPTIONAL) != 0 { return 1; }
        if s.kind == TY_REF && check_operation_same(p, s.element, d.element) {
            if (s.flags & TF_CONST) != 0 && (d.flags & TF_CONST) == 0 { return -1; }
            if (s.flags & TF_OPTIONAL) != 0 && (d.flags & TF_OPTIONAL) == 0 { return -1; }
            // Relative widths describe stored offsets. Loaded references
            // convert as pointers; the lifetime pass proves each relative store.
            return 1;
        }
        if check_same_type(p, source, d.element) && check_addressable(p, expression) { return 2; }
    }
    if (n.kind == N_ARRAY || n.kind == N_FILL) && s.kind == TY_ARRAY && (d.kind == TY_ARRAY || d.kind == TY_SLICE) {
        if d.kind == TY_ARRAY && d.array_kind == A_FIXED && s.count != d.count { return -1; }
        if d.kind == TY_ARRAY && d.array_kind == A_LIMITED && d.count >= 0 && s.count > d.count { return -1; }
        var element = n.first;
        while element >= 0 {
            if check_conversion(p, c, element, p.nodes[element].type_id, d.element) < 0 { return -1; }
            element = p.nodes[element].next;
        }
        return 2;
    }
    if s.kind == TY_ARRAY && s.element < 0 && check_empty_tree(p, expression) && (d.kind == TY_ARRAY || d.kind == TY_SLICE) { return 2; }
    if d.kind == TY_SLICE && (s.kind == TY_ARRAY || s.kind == TY_SLICE) &&
       check_same_type(p, s.element, d.element) {
        let actual = p.nodes[expression].type_id;
        let whole = actual >= 0 && (p.types[actual].kind == TY_ARRAY || p.types[actual].kind == TY_SLICE);
        if (d.flags & TF_CONST) == 0 && n.kind != N_STRING && ((s.flags & TF_CONST) != 0 || whole && check_readonly(p, c, expression)) { return -1; }
        return 2;
    }
    if d.kind == TY_ARRAY && (s.kind == TY_ARRAY || s.kind == TY_SLICE) && check_same_type(p, s.element, d.element) {
        if d.array_kind == A_FIXED && s.count >= 0 && d.count != s.count { return -1; }
        if d.array_kind == A_LIMITED && d.count >= 0 && s.count > d.count { return -1; }
        return 3;
    }
    if n.kind == N_STRING && d.kind == TY_ARRAY && d.element == TYPE_U8 { return 2; }
    if d.kind == TY_ENUM && s.kind == TY_STRUCT && s.pool >= 0 && p.types[s.pool].declaration == d.declaration { return 1; }
    if s.kind == TY_ENUM && d.kind == TY_ENUM && s.declaration == d.declaration { return 2; }
    if s.kind == TY_STRUCT && d.kind == TY_STRUCT && s.declaration == d.declaration && (s.flags & ~TF_CONST) == (d.flags & ~TF_CONST) { return 1; }
    if s.kind == TY_TUPLE && d.kind == TY_TUPLE && s.count == d.count {
        var sp = s.first; var dp = d.first; var score = 0;
        while sp >= 0 && dp >= 0 {
            let conversion = check_conversion(p, c, expression, p.nodes[sp].type_id, p.nodes[dp].type_id);
            if conversion < 0 { return -1; } if conversion > score { score = conversion; }
            sp = p.nodes[sp].next; dp = p.nodes[dp].next;
        }
        return score;
    }
    return -1;
}
recursive fn check_retarget_exits(p: Program&, node: i64, previous: i64, replacement: i64) {
    if node < 0 { return; }
    let n = p.nodes[node];
    if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE { return; }
    if (n.kind == N_BREAK || n.kind == N_CONTINUE) && n.symbol == previous { p.nodes[node].symbol = replacement; }
    var child = n.first;
    while child >= 0 { check_retarget_exits(p, child, previous, replacement); child = p.nodes[child].next; }
    check_retarget_exits(p, n.left, previous, replacement); check_retarget_exits(p, n.right, previous, replacement); check_retarget_exits(p, n.third, previous, replacement);
}

fn check_wrap_unary(p: Program&, node: i64, op: i64, ty: i64) {
    var original = p.nodes[node]; let next = original.next; original.next = -1;
    let inner = p.nodes.len; p.nodes.push(original); check_retarget_exits(p, inner, node, inner);
    p.nodes[node] = Node { kind: N_UNARY, token: original.token, next: next, left: inner, type_id: ty, integer: op, flags: F_CHECKED | F_SYNTHETIC | (original.flags & F_TAIL), scope: original.scope, coerced_type: original.coerced_type };
    if op == T_MUL { p.nodes[node].aux = ty; }
}
fn check_mark_coercion(p: Program&, expression: i64, expected: i64) {
    var node = expression;
    while node >= 0 {
        p.nodes[node].coerced_type = expected; let n = p.nodes[node];
        if n.kind != N_UNARY || n.integer != T_MUL || (n.flags & F_SYNTHETIC) == 0 { break; }
        node = n.left;
    }
}
recursive fn check_expect(p: Program&, c: Checker&, expression: i64, source: i64, expected: i64) -> i64 {
    if expected < 0 || expected == TYPE_VOID { return source; }
    if p.types[expected].kind == TY_REF || p.types[expected].kind == TY_SLICE { p.nodes[expression].flags |= F_REFERENCE_CONTEXT; }
    if check_bottom(p, expression) { return expected; }
    if p.types[expected].kind == TY_INT && p.types[expected].index_type >= 0 {
        if check_conversion(p, c, expression, source, expected) < 0 {
            diagnose(p, p.nodes[expression].token, "index or bound storage requires a checked value of the same named array"); return source;
        }
        return expected;
    }
    let constant = check_width_constant(p, c, expression, expected);
    if constant.valid {
        check_rely_named(p, c, expression);
        let original = p.nodes[expression]; var flags = original.flags & F_TAIL;
        if check_unsigned(check_numeric_value_type(p, expected)) { flags |= F_UNSIGNED; }
        p.nodes[expression] = Node { kind: N_INTEGER, token: original.token, next: original.next, type_id: expected, integer: constant.value, flags: flags | F_CHECKED | F_SYNTHETIC, scope: original.scope };
        return expected;
    }
    if source == TYPE_F64 && expected == TYPE_F32 && check_narrow_context_float(p, c, expression) { return expected; }
    if check_conversion(p, c, expression, source, expected) < 0 {
        diagnose(p, p.nodes[expression].token, "value cannot implicitly convert to the required type"); return source;
    }
    if source < 0 { return expected; }
    if source == TYPE_F32 && expected == TYPE_F64 { return expected; }
    let branch = p.nodes[expression];
    if branch.kind == N_LOOP || branch.kind == N_BLOCK && (branch.flags & F_EARLY) != 0 {
        check_exit_expect(p, c, expression, expression, expected);
        if branch.kind == N_LOOP || (branch.flags & F_TAIL) == 0 { p.nodes[expression].type_id = expected; return expected; }
    }
    if check_integer(expected) && check_flex_integer(p, c, expression).flexible {
        check_rely_named(p, c, expression); check_retype_integer(p, c, expression, expected); return expected;
    }
    if c.reachable && p.types[expected].kind == TY_ENUM { check_mark_coercion(p, expression, expected); }
    if source != expected && (check_integer(expected) && check_literal_tree(p, expression, 0) || check_float(expected) && check_float_literal_tree(p, expression, 0)) {
        check_rely_named(p, c, expression);
        if check_float(expected) && check_float(source) { check_retype_float(p, c, expression, expected); return expected; }
    }
    if branch.kind == N_BLOCK && (branch.flags & F_SYNTHETIC) != 0 && p.types[source].kind == TY_ARRAY && p.types[source].array_kind == A_GROW && p.types[expected].kind == TY_SLICE {
        // A lowered builder call still produces its natural owning result.
        // Its receiving slice views that completed value outside the body.
        check_wrap_numeric_cast(p, expression, expected); return expected;
    }
    if p.types[expected].kind == TY_REF && branch.kind == N_UNARY && branch.integer == T_MUL && (branch.flags & F_SYNTHETIC) != 0 {
        var reference = p.nodes[branch.left]; reference.next = branch.next; reference.flags |= branch.flags & F_TAIL; reference.type_id = expected; p.nodes[expression] = reference; return expected;
    }
    if p.types[expected].kind == TY_SLICE && (branch.kind == N_BLOCK || branch.kind == N_IF || branch.kind == N_MATCH) && check_branch_array_literal(p, expression) {
        diagnose(p, branch.token, "control-flow slice result refers to a branch temporary");
    }
    if (branch.kind == N_ARRAY || branch.kind == N_FILL) && (p.types[expected].kind == TY_ARRAY || p.types[expected].kind == TY_SLICE) {
        p.nodes[expression].type_id = check_array(p, c, expression, expected); return expected;
    }
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
        if (p.types[expected].flags & TF_CONST) == 0 && check_borrow_readonly(p, c, expression) {
            diagnose(p, p.nodes[expression].token, "writable reference cannot bind read-only storage");
        }
        let root = check_place_root(p, expression);
        if (p.types[expected].flags & TF_CONST) == 0 { check_named_writable(p, c, root, p.nodes[expression].token); }
        let root_kind = check_reference_kind(p, expression);
        check_require_referenceable(p, c, expression);
        check_wrap_unary(p, expression, T_BITAND, expected); check_add_root(c, expression, root, root_kind);
    } else if p.types[source].kind == TY_REF && p.types[expected].kind != TY_REF {
        check_wrap_unary(p, expression, T_MUL, p.types[source].element);
    }
    let kind = p.nodes[expression].kind;
    if kind == N_INTEGER || kind == N_FLOAT || kind == N_ARRAY && p.types[expected].kind == TY_ARRAY || kind == N_NULL || kind == N_STRING {
        p.nodes[expression].type_id = expected;
    }
    return expected;
}
fn check_project_result(p: Program&, c: Checker&, node: i64, type_id: i64) -> i64 {
    if type_id < 0 || p.types[type_id].kind != TY_TUPLE { return type_id; }
    let first = p.types[type_id].first;
    if first < 0 { diagnose(p, p.nodes[node].token, "a scalar context requires at least one result"); return -1; }
    let selected = check_loaded_type(p, p.nodes[first].type_id);
    var producer = p.nodes[node]; let next = producer.next; producer.next = -1;
    let inner = p.nodes.len; p.nodes.push(producer); check_retarget_exits(p, inner, node, inner);
    p.nodes[node] = Node { kind: N_RESULT, token: producer.token, next: next, left: inner, type_id: selected,
        integer: 0, flags: F_CHECKED | F_SYNTHETIC | (producer.flags & (F_TAIL | F_REACHABLE | F_DIVERGES)), scope: producer.scope };
    check_copy_roots(c, node, inner); return selected;
}
recursive fn check_single_expression(p: Program&, c: Checker&, node: i64, expected: i64 = -1) -> i64 {
    let saved = c.tuple_context; c.tuple_context = false;
    let ty = check_expression(p, c, node, expected); c.tuple_context = saved;
    return check_project_result(p, c, node, ty);
}
recursive fn check_value(p: Program&, c: Checker&, node: i64, expected: i64, keep_tuple: bool = false) -> i64 {
    let tuple_result = keep_tuple || expected >= 0 && p.types[expected].kind == TY_TUPLE;
    let saved = c.tuple_context; c.tuple_context = tuple_result;
    var ty = check_expression(p, c, node, expected); c.tuple_context = saved;
    if !tuple_result && c.reachable { ty = check_project_result(p, c, node, ty); }
    if !c.reachable { return -1; }
    ty = check_read_value_type(p, c, node, ty);
    if c.returning && ty >= 0 && p.types[ty].kind != TY_REF && check_size_class(p, ty, 0) > 0 && check_own_local(p, c, node) &&
       (expected < 0 || p.types[expected].kind != TY_REF && p.types[expected].kind != TY_SLICE && expected != TYPE_VOID) {
        p.nodes[node].flags |= F_RETURN_MOVE;
    }
    if ty >= 0 && p.types[ty].kind == TY_REF && (expected < 0 || p.types[expected].kind != TY_REF) {
        let element = p.types[ty].element;
        if expected >= 0 || (p.types[ty].flags & TF_OPTIONAL) == 0 && (check_size_class(p, element, 0) == 0 || p.types[element].storage == 1) {
            if (p.types[ty].flags & TF_OPTIONAL) != 0 { diagnose(p, p.nodes[node].token, "optional reference must be narrowed before dereferencing"); }
            check_wrap_unary(p, node, T_MUL, element); ty = element;
        }
    }
    let numeric = check_numeric_value_type(p, ty);
    if numeric != ty && (expected < 0 || p.types[expected].kind != TY_REF) {
        // The explicit conversion keeps its destination metadata, including
        // index bounds; consumers can adapt the resulting numeric value.
        if p.nodes[node].kind != N_CAST && p.types[ty].index_type < 0 { p.nodes[node].type_id = numeric; }
        ty = numeric;
    }
    return check_expect(p, c, node, ty, expected);
}
recursive fn check_proven_nonnull(p: Program&, node: i64) -> bool {
    if node < 0 { return false; }
    let n = p.nodes[node];
    if n.kind == N_NULL { return false; }
    if n.kind == N_UNARY && n.integer == T_BITAND && n.left >= 0 {
        let child = p.nodes[n.left].type_id;
        if child >= 0 && p.types[child].kind != TY_REF { return true; }
        return check_proven_nonnull(p, n.left);
    }
    if n.type_id >= 0 && p.types[n.type_id].kind == TY_REF && (p.types[n.type_id].flags & TF_OPTIONAL) == 0 { return true; }
    if n.kind == N_BLOCK && (n.flags & F_TAIL) != 0 { return check_proven_nonnull(p, n.last); }
    if n.kind == N_IF { return n.third >= 0 && check_proven_nonnull(p, n.right) && check_proven_nonnull(p, n.third); }
    if n.kind == N_MATCH {
        var arm = n.first;
        while arm >= 0 { if !check_proven_nonnull(p, p.nodes[arm].right) { return false; } arm = p.nodes[arm].next; }
        return n.first >= 0;
    }
    return false;
}
fn check_assign_narrowing(p: Program&, c: Checker&, symbol: i64, value: i64) {
    let vi = check_variable_index(c, symbol); if vi < 0 { return; }
    let type_id = p.symbols[symbol].type_id;
    c.variables[vi].narrowed = -1;
    if type_id >= 0 && p.types[type_id].kind == TY_REF && (p.types[type_id].flags & TF_OPTIONAL) != 0 && check_proven_nonnull(p, value) {
        var narrowed = p.types[type_id]; narrowed.flags &= ~TF_OPTIONAL;
        c.variables[vi].narrowed = add_type(p, narrowed);
    }
}
fn check_logical_apply(c: Checker&, node: i64) {
    for kill in c.logical_kills {
        if kill.node != node { continue; }
        let vi = check_variable_index(c, kill.symbol); if vi >= 0 { c.variables[vi].narrowed = -1; }
    }
}
fn check_logical_globals(p: Program&, c: Checker&, out: CheckSpan&) {
    out.first = c.flow_work.len; out.count = 0; var vi = c.scopes[0].first_variable;
    while vi >= 0 {
        let variable = c.variables[vi]; let symbol = p.symbols[variable.symbol]; let ty = symbol.type_id;
        if (symbol.flags & S_GLOBAL) != 0 && ty >= 0 && p.types[ty].kind == TY_REF && (p.types[ty].flags & TF_OPTIONAL) != 0 {
            c.flow_work.push(CheckFlow { symbol: variable.symbol, assigned: variable.assigned, maybeassigned: variable.maybeassigned, narrowed: variable.narrowed }); out.count += 1;
        }
        vi = variable.next_frame;
    }
}
fn check_logical_capture(c: Checker&, narrowed: CheckList&, span: CheckSpan&) {
    for index in span.first..span.first + span.count {
        let symbol = c.flow_work[index].symbol; let vi = check_variable_index(c, symbol);
        if vi < 0 || c.variables[vi].narrowed < 0 { continue; }
        var found = false;
        for j in 0..narrowed.count { if check_list_at(c, narrowed, j) == symbol { found = true; break; } }
        if !found { check_list_push(c, narrowed, symbol); }
    }
}
fn check_logical_record(c: Checker&, node: i64, narrowed: CheckList&) {
    for kill, index in c.logical_kills { if kill.node == node { c.logical_kills[index].node = -1; } }
    for index in 0..narrowed.count {
        let symbol = check_list_at(c, narrowed, index); let vi = check_variable_index(c, symbol);
        if vi >= 0 && c.variables[vi].narrowed < 0 { c.logical_kills.push(CheckLogicalKill { node: node, symbol: symbol }); }
    }
}

recursive fn check_narrow_condition(p: Program&, c: Checker&, node: i64, sense: bool) {
    if node < 0 { return; }
    let n = p.nodes[node];
    if n.kind == N_UNARY && n.integer == T_NOT { check_narrow_condition(p, c, n.left, !sense); return; }
    if n.kind == N_BINARY {
        if n.integer == T_ANDAND && sense || n.integer == T_OROR && !sense {
            check_narrow_condition(p, c, n.left, sense); check_logical_apply(c, node);
            check_narrow_condition(p, c, n.right, sense); return;
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
    var copy = p.types[check_loaded_type(p, declared)]; copy.flags &= ~TF_OPTIONAL;
    c.variables[vi].narrowed = add_type(p, copy);
}

recursive fn check_condition(p: Program&, c: Checker&, node: i64) {
    let returning = c.returning; c.returning = false;
    check_condition_value(p, c, node); c.returning = returning;
}
recursive fn check_condition_value(p: Program&, c: Checker&, node: i64) {
    let ty = check_read_value_type(p, c, node, check_single_expression(p, c, node));
    if !c.reachable || ty == TYPE_BOOL { return; }
    if ty >= 0 && p.types[ty].kind == TY_REF {
        if (p.types[ty].flags & TF_OPTIONAL) != 0 { return; }
        let n = p.nodes[node];
        if n.kind == N_NAME && n.symbol >= 0 {
            let declared = p.symbols[n.symbol].type_id;
            if declared >= 0 && p.types[declared].kind == TY_REF && (p.types[declared].flags & TF_OPTIONAL) != 0 { p.nodes[node].type_id = check_loaded_type(p, declared); return; }
        }
        let element = p.types[ty].element;
        if element >= 0 && p.types[element].kind == TY_BOOL { check_wrap_unary(p, node, T_MUL, TYPE_BOOL); p.nodes[node].aux = element; return; }
    }
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
fn check_parameter_default_name(p: Program&, c: Checker&, node: i64, functions_only: bool) {
    let function_node = c.parameter_default_function;
    if function_node < 0 || node < 0 { return; }
    let n = p.nodes[node];
    if n.aux > 1 || n.integer >= 0 && n.integer < p.tokens.len && p.tokens[n.integer].kind == T_COLONCOLON { return; }
    let actual = check_lookup_name(p, c, node);
    if actual >= 0 && p.symbols[actual].node >= c.parameter_default_floor && (p.symbols[actual].flags & S_GLOBAL) == 0 { return; }
    let saved = c.scope; c.scope = p.nodes[function_node].scope;
    let symbol = check_lookup_name(p, c, node); c.scope = saved;
    if symbol < 0 { return; } let binding = p.symbols[symbol];
    if (binding.flags & S_TYPE) != 0 {
        if binding.type_id >= 0 && p.types[binding.type_id].kind == TY_FN { diagnose(p, n.token, "a parameter default cannot name a function-value type parameter"); }
        return;
    }
    if functions_only && (binding.flags & S_FUNCTION) == 0 { return; }
    if (binding.flags & S_PARAMETER) != 0 || binding.owner >= 0 {
        diagnose(p, n.token, "a parameter default cannot name a parameter, enclosing local, or nested function");
    }
}

recursive fn check_parameter_default(p: Program&, c: Checker&, function_node: i64, parameter: i64, token: i64) -> i64 {
    var defaults = c.default_fields;
    for index in 0..defaults.count {
        if check_list_at(c, defaults, index) == p.nodes[parameter].token { diagnose(p, token, "parameter default construction is cyclic"); return -1; }
    }
    let saved_defaults = c.default_fields; let saved_scope = c.scope;
    let saved_default_body = c.default_body; c.default_body = true;
    let saved_parameter_function = c.parameter_default_function; let saved_parameter_floor = c.parameter_default_floor;
    c.parameter_default_function = function_node; c.parameter_default_floor = p.nodes.len;
    check_list_push(c, c.default_fields, p.nodes[parameter].token);
    if p.nodes[function_node].scope >= 0 { c.scope = c.scopes[p.nodes[function_node].scope].parent; }
    var bindings = CheckList {};
    let value = check_clone(p, c, p.nodes[parameter].right, bindings);
    let saved_render_reference = c.render_reference; c.render_reference = false;
    check_value(p, c, value, p.nodes[parameter].type_id);
    c.render_reference = saved_render_reference;
    c.default_fields = saved_defaults; c.scope = saved_scope; c.default_body = saved_default_body;
    c.parameter_default_function = saved_parameter_function; c.parameter_default_floor = saved_parameter_floor;
    return value;
}

fn check_self_init(p: Program&, c: Checker&, value: i64, field: i64, owner: i64) -> bool {
    if value < 0 { return false; }
    let n = p.nodes[value];
    if n.kind != N_SELF && !(n.kind == N_NAME && p.tokens[n.token].kind == T_SELF) { return false; }
    let reference = p.nodes[field].type_id;
    if reference < 0 || p.types[reference].kind != TY_REF || p.types[reference].length_storage < 0 {
        diagnose(p, n.token, "self initializes only a relative-reference field"); return true;
    }
    if (p.types[reference].flags & TF_OPTIONAL) != 0 { diagnose(p, n.token, "self cannot initialize an optional relative reference: zero is null"); }
    if !check_operation_same(p, p.types[reference].element, owner) { diagnose(p, n.token, "self pointee must match the literal's constructed type"); }
    if check_size_class(p, owner, 0) == 2 { diagnose(p, n.token, "self cannot refer to a resizable value through a relative offset"); }
    p.nodes[value].kind = N_SELF; p.nodes[value].type_id = reference; p.nodes[value].symbol = field;
    p.nodes[value].aux = owner; p.nodes[value].scope = c.scope; p.nodes[value].flags |= F_CHECKED;
    return true;
}
recursive fn check_field_default(p: Program&, c: Checker&, field: i64, token: i64, depth: i64, owner: i64, existing: i64 = -1) -> i64 {
    let f = p.nodes[field]; let saved = c.default_fields; let saved_scope = c.scope;
    let saved_default_body = c.default_body; c.default_body = true;
    let saved_parameter_function = c.parameter_default_function; let saved_parameter_floor = c.parameter_default_floor;
    c.parameter_default_function = -1; c.parameter_default_floor = -1;
    if f.right >= 0 {
        var fields = c.default_fields;
        for index in 0..fields.count { if check_list_at(c, fields, index) == f.token { diagnose(p, token, "field default construction is cyclic"); c.default_body = saved_default_body; return -1; } }
        check_list_push(c, c.default_fields, f.token);
    }
    if f.scope >= 0 { c.scope = f.scope; }
    let saved_render_reference = c.render_reference; c.render_reference = false;
    var value = existing;
    if value < 0 {
        if f.right >= 0 { var bindings = CheckList {}; value = check_clone(p, c, f.right, bindings); }
        else { value = check_default_syntax(p, c, f.type_id, token, depth + 1); }
    }
    if value >= 0 && !check_self_init(p, c, value, field, owner) { check_value(p, c, value, f.type_id); check_slot_value(p, c, value, f.type_id, true); }
    c.render_reference = saved_render_reference;
    c.default_fields = saved; c.scope = saved_scope; c.default_body = saved_default_body;
    c.parameter_default_function = saved_parameter_function; c.parameter_default_floor = saved_parameter_floor;
    return value;
}

recursive fn check_default_syntax(p: Program&, c: Checker&, ty: i64, token: i64, depth: i64) -> i64 {
    if ty < 0 || depth > 64 { diagnose(p, token, "type has no finite default value"); return -1; }
    let t = p.types[ty]; var kind = N_INTEGER;
    if t.kind == TY_INT && t.index_type >= 0 { diagnose(p, token, "an index or bound type has no default value while its named array may be empty"); return -1; }
    if t.kind == TY_BOOL { kind = N_BOOL; }
    else if t.kind == TY_FLOAT { kind = N_FLOAT; }
    else if t.kind == TY_REF {
        if (t.flags & TF_OPTIONAL) == 0 { diagnose(p, token, "non-optional reference has no default value"); return -1; }
        kind = N_NULL;
    } else if t.kind == TY_ARRAY || t.kind == TY_SLICE { kind = N_ARRAY; }
    else if t.kind == TY_STRUCT || t.kind == TY_ENUM { kind = N_RECORD; }
    else if t.kind != TY_INT { diagnose(p, token, "type has no default value"); return -1; }
    let id = new_node(p, kind, token); p.nodes[id].type_id = ty; p.nodes[id].flags |= F_DEFAULT;
    if kind == N_RECORD {
        check_layout_nominal(p, c, ty);
        if t.kind == TY_ENUM { p.nodes[id].symbol = p.types[ty].first; }
    } else if kind == N_ARRAY && t.kind == TY_ARRAY && t.array_kind == A_FIXED && t.count > 0 {
        p.nodes[id].kind = N_FILL;
        let element = check_default_syntax(p, c, t.element, token, depth + 1);
        let count = new_node(p, N_INTEGER, token); p.nodes[count].integer = t.count; p.nodes[count].type_id = TYPE_I64; p.nodes[count].flags |= F_CHECKED;
        p.nodes[id].first = element; p.nodes[id].last = element; p.nodes[id].right = count;
    } else if kind != N_ARRAY || t.kind == TY_SLICE { p.nodes[id].flags |= F_CHECKED; }
    return id;
}
recursive fn check_default(p: Program&, c: Checker&, ty: i64, token: i64, depth: i64) -> i64 {
    let value = check_default_syntax(p, c, ty, token, depth);
    if value >= 0 { check_expression(p, c, value, ty); }
    return value;
}

recursive fn check_array(p: Program&, c: Checker&, node: i64, expected: i64) -> i64 {
    let n = p.nodes[node]; var element = -1; var count = check_list_count(p, n.first);
    if n.kind == N_ARRAY && n.first < 0 && (n.flags & F_DEFAULT) != 0 && n.type_id >= 0 && p.types[n.type_id].kind == TY_SLICE &&
       (expected < 0 || p.types[expected].kind == TY_SLICE) { return n.type_id; }
    if n.third >= 0 { check_value(p, c, n.third, TYPE_I64); }
    if expected >= 0 && (p.types[expected].kind == TY_ARRAY || p.types[expected].kind == TY_SLICE) {
        element = p.types[expected].element;
    }
    if !c.literal_comparison && expected >= 0 && p.types[expected].kind == TY_SLICE && element >= 0 && check_size_class(p, element, 0) > 0 && (n.first >= 0 || p.types[element].storage != 1) {
        diagnose(p, n.token, "variable-size array elements require a construction context before viewing");
    }
    var child = n.first;
    while child >= 0 {
        let ty = check_index_value(p, child, check_value(p, c, child, element)); check_slot_value(p, c, child, element, true);
        if element < 0 { element = ty; }
        check_copy_roots(c, node, child); child = p.nodes[child].next;
    }
    if n.right >= 0 {
        check_constant_names(p, c, n.right);
        check_value(p, c, n.right, TYPE_I64);
        let constant = check_constant(p, c, n.right, 0);
        if constant.valid {
            if constant.value < 0 { diagnose(p, n.token, "array repetition count must be nonnegative"); }
            count = constant.value;
        } else { count = -1; diagnose(p, n.token, "array repetition count must be a compile-time integer constant"); }
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
    var array_kind = A_FIXED; if count < 0 || check_size_class(p, element, 0) == 1 { array_kind = A_VAR; }
    check_array_element(p, c, element, array_kind, n.token);
    return check_array_type(p, element, count, array_kind, 0);
}
recursive fn check_infer_record_type(p: Program&, c: Checker&, declaration: i64, record: i64, expected: i64) -> i64 {
    var context = expected;
    while context >= 0 && p.types[context].kind == TY_REF { context = p.types[context].element; }
    if context >= 0 && p.types[context].kind == TY_STRUCT {
        let actual = p.types[context].declaration;
        if actual == declaration || actual >= 0 && p.nodes[actual].origin == declaration { return context; }
    }
    check_layout_nominal(p, c, p.nodes[declaration].type_id);
    var bindings = CheckList {}; var positional = p.nodes[declaration].first; var init = p.nodes[record].first;
    while init >= 0 {
        let binding = p.nodes[init]; var field = positional;
        if binding.token >= 0 {
            field = p.nodes[declaration].first;
            while field >= 0 { if same_name(p, p.nodes[field].token, binding.token) { break; } field = p.nodes[field].next; }
        } else {
            while field >= 0 && (p.nodes[field].flags & F_PAD) != 0 { field = p.nodes[field].next; }
            if field >= 0 { positional = p.nodes[field].next; }
        }
        if field >= 0 && binding.right >= 0 {
            let actual = check_expression(p, c, binding.right, -1);
            if !check_unify(p, c, p.nodes[field].type_id, actual, bindings) && !check_literal_tree(p, binding.right, 0) {
                diagnose(p, binding.token, "generic record fields infer inconsistent type arguments");
            }
        }
        init = binding.next;
    }
    var first = -1; var last = -1; var param = p.nodes[declaration].third;
    while param >= 0 {
        var type_id = -1;
        for i in 0..bindings.count { let binding = check_binding_at(c, bindings, i); if binding.parameter == param { type_id = binding.value; } }
        if type_id < 0 { diagnose(p, p.nodes[record].token, "record constructor cannot infer every generic argument"); return -1; }
        let argument = new_node(p, N_TYPE_ARG, p.nodes[param].token); p.nodes[argument].type_id = type_id;
        if first < 0 { first = argument; } else { p.nodes[last].next = argument; }
        last = argument; param = p.nodes[param].next;
    }
    return check_nominal_instance(p, c, declaration, first, p.nodes[record].token);
}

recursive fn check_init_store_safe(p: Program&, c: Checker&, node: i64, destination: i64) -> bool {
    if node < 0 || destination < 0 || destination == TYPE_VOID { return true; }
    let n = p.nodes[node];
    if check_type_property(p, destination, 3) != 0 { return n.kind == N_NULL; }
    if n.kind == N_BLOCK {
        if (n.flags & F_TAIL) == 0 { return true; }
        return check_init_store_safe(p, c, n.last, destination);
    }
    if n.kind == N_RETURN && (n.flags & F_IMPLICIT_RETURN) != 0 && n.first >= 0 && p.nodes[n.first].next < 0 { return check_init_store_safe(p, c, n.first, destination); }
    if n.kind == N_IF { return check_init_store_safe(p, c, n.right, destination) && check_init_store_safe(p, c, n.third, destination); }
    if n.kind == N_MATCH {
        var arm = n.first;
        while arm >= 0 { if !check_init_store_safe(p, c, p.nodes[arm].right, destination) { return false; } arm = p.nodes[arm].next; }
        return true;
    }
    if p.types[destination].kind != TY_ARRAY { return true; }
    var source = -1;
    if n.kind == N_STRING || n.kind == N_ARRAY || n.kind == N_FILL { source = n.type_id; }
    else if n.kind == N_NAME && n.symbol >= 0 { source = p.symbols[n.symbol].type_id; }
    else if n.kind == N_CALL && n.symbol >= 0 && (p.symbols[n.symbol].flags & (S_BUILTIN | S_EXTERN)) == 0 {
        let ty = p.symbols[n.symbol].type_id; if ty >= 0 && p.types[ty].kind == TY_FN { source = p.types[ty].element; }
    } else if n.kind == N_UNARY && n.integer == T_BITAND { return check_init_store_safe(p, c, n.left, destination); }
    if source >= 0 && p.types[source].kind == TY_REF { source = p.types[source].element; }
    if source >= 0 && (p.types[source].flags & TF_CONST) != 0 && p.types[source].kind != TY_REF && p.types[source].kind != TY_SLICE {
        var plain = p.types[source]; plain.flags &= ~TF_CONST; source = add_type(p, plain);
    }
    return source >= 0 && check_same_type(p, source, destination);
}
recursive fn check_init_safe(p: Program&, c: Checker&, node: i64, visiting: CheckList&, callee: i64 = -1) -> bool {
    if node < 0 { return true; } let n = p.nodes[node];
    if n.kind == N_INTEGER || n.kind == N_FLOAT || n.kind == N_BOOL || n.kind == N_STRING || n.kind == N_NULL || n.kind == N_SELF || n.kind == N_NAME { return true; }
    if n.kind == N_MEMBER { return check_init_safe(p, c, n.left, visiting, callee); }
    if n.kind == N_UNARY {
        if n.integer == T_MINUS {
            let ty = check_numeric_value_type(p, p.nodes[n.left].type_id);
            if !check_numeric(ty) || check_integer(ty) && !check_unsigned(ty) { return false; }
        }
        return check_init_safe(p, c, n.left, visiting, callee);
    }
    if n.kind == N_BINARY {
        let op = n.integer; let ty = check_numeric_value_type(p, p.nodes[n.left].type_id);
        if op != T_ANDAND && op != T_OROR && op != T_EQ && op != T_NEQ && op != T_DOTEQ && op != T_DOTNEQ {
            if !check_numeric(ty) && ty != TYPE_BOOL { return false; }
            if check_integer(ty) && (op == T_DIV || op == T_MOD || !check_unsigned(ty) && (op == T_PLUS || op == T_MINUS || op == T_MUL)) { return false; }
        }
        return check_init_safe(p, c, n.left, visiting, callee) && check_init_safe(p, c, n.right, visiting, callee);
    }
    if n.kind == N_CAST {
        let from = check_numeric_value_type(p, p.nodes[n.left].type_id); let to = check_numeric_value_type(p, n.type_id);
        if n.type_id >= 0 && p.types[n.type_id].index_type >= 0 { return false; }
        var lossless = false;
        if check_integer(from) && check_integer(to) {
            lossless = check_unsigned(from) == check_unsigned(to) && check_integer_bits(to) >= check_integer_bits(from) || check_unsigned(from) && !check_unsigned(to) && check_integer_bits(to) > check_integer_bits(from);
        }
        return ((n.flags & (F_UNSIGNED | F_SYNTHETIC)) != 0 || check_float(to) || lossless) && check_init_safe(p, c, n.left, visiting, callee);
    }
    if n.kind == N_CALL {
        if (n.flags & F_PROPERTY) != 0 { return check_init_safe(p, c, n.first, visiting, callee); }
        if n.symbol < 0 || (p.symbols[n.symbol].flags & (S_BUILTIN | S_EXTERN)) != 0 || (n.flags & F_DISPATCH) != 0 { return false; }
        let function = p.symbols[n.symbol].node;
        if function < 0 || p.nodes[function].right < 0 { return false; }
        for i in 0..visiting.count { if check_list_at(c, visiting, i) == function { return false; } }
        // Scalar equality came from a binary even when aggregates lower to
        // a shared helper. Keep the original equality proof over its operands.
        if (p.nodes[function].flags & F_SYNTHETIC) != 0 && p.nodes[function].aux >= 0 {
            if p.nodes[function].aux != T_EQ { return false; }
            var argument = n.first;
            while argument >= 0 { if !check_init_safe(p, c, argument, visiting, callee) { return false; } argument = p.nodes[argument].next; }
            return true;
        }
        let type_id = p.symbols[n.symbol].type_id; if type_id < 0 { return false; }
        let result = p.types[type_id].element;
        if result >= 0 && p.types[result].kind == TY_TUPLE { return false; }
        var path = visiting; check_list_push(c, path, function);
        var formal = p.nodes[function].first; var argument = n.first;
        while formal >= 0 && argument >= 0 {
            if !check_init_store_safe(p, c, argument, p.nodes[formal].type_id) || !check_init_safe(p, c, argument, path, callee) { return false; }
            formal = p.nodes[formal].next; argument = p.nodes[argument].next;
        }
        return formal < 0 && argument < 0 && check_init_store_safe(p, c, p.nodes[function].right, result) && check_init_safe(p, c, p.nodes[function].right, path, function);
    }
    if n.kind == N_RETURN {
        if callee < 0 || n.symbol != p.nodes[callee].symbol { return false; }
        let result = p.types[p.nodes[callee].type_id].element;
        var count = 0; var value = n.first;
        while value >= 0 {
            if !check_init_store_safe(p, c, value, result) || !check_init_safe(p, c, value, visiting, callee) { return false; }
            count += 1; value = p.nodes[value].next;
        }
        if result == TYPE_VOID { return count == 0 || count == 1 && p.nodes[n.first].type_id == TYPE_VOID; }
        return count == 1;
    }
    if n.kind == N_VARIABLE {
        if callee < 0 { return false; }
        if n.right < 0 { return true; }
        var value = n.right; var binding = n.first; if binding < 0 { binding = node; }
        while value >= 0 && binding >= 0 {
            if !check_init_store_safe(p, c, value, p.nodes[binding].type_id) || !check_init_safe(p, c, value, visiting, callee) { return false; }
            value = p.nodes[value].next;
            if n.first < 0 { binding = -1; } else { binding = p.nodes[binding].next; }
        }
        return value < 0 && binding < 0;
    }
    if n.kind == N_ARRAY || n.kind == N_FILL {
        if n.third >= 0 || n.right >= 0 && p.nodes[n.right].kind != N_INTEGER { return false; }
        let element = p.types[n.type_id].element; var child = n.first;
        while child >= 0 {
            if !check_init_store_safe(p, c, child, element) || !check_init_safe(p, c, child, visiting, callee) { return false; }
            child = p.nodes[child].next;
        }
        return true;
    }
    if n.kind == N_RECORD {
        var binding = n.first;
        while binding >= 0 {
            let b = p.nodes[binding];
            if !check_init_store_safe(p, c, b.right, b.type_id) || !check_init_safe(p, c, b.right, visiting, callee) { return false; }
            binding = b.next;
        }
        return true;
    }
    if n.kind == N_BLOCK {
        var child = n.first;
        while child >= 0 { if !check_init_safe(p, c, child, visiting, callee) { return false; } child = p.nodes[child].next; }
        return true;
    }
    if n.kind == N_IF { return check_init_safe(p, c, n.left, visiting, callee) && check_init_safe(p, c, n.right, visiting, callee) && check_init_safe(p, c, n.third, visiting, callee); }
    if n.kind == N_MATCH {
        if !check_init_safe(p, c, n.left, visiting, callee) { return false; }
        var arm = n.first;
        while arm >= 0 {
            if !check_init_safe(p, c, p.nodes[arm].third, visiting, callee) || !check_init_safe(p, c, p.nodes[arm].right, visiting, callee) { return false; }
            arm = p.nodes[arm].next;
        }
        return true;
    }
    if n.kind == N_EXPR_STMT { return check_init_safe(p, c, n.left, visiting, callee); }
    if n.kind == N_EMPTY { return true; }
    return false;
}
fn check_init_binding(p: Program&, record: i64, field: i64) -> i64 {
    var binding = p.nodes[record].first;
    while binding >= 0 { if p.nodes[binding].symbol == field { return binding; } binding = p.nodes[binding].next; }
    return -1;
}
fn check_init_field_safe(p: Program&, c: Checker&, record: i64, field: i64) -> bool {
    let binding = check_init_binding(p, record, field); if binding < 0 { return true; }
    var visiting = CheckList {}; let value = p.nodes[binding].right;
    return check_init_store_safe(p, c, value, p.nodes[field].type_id) && check_init_safe(p, c, value, visiting);
}

recursive fn check_record(p: Program&, c: Checker&, node: i64, expected: i64) -> i64 {
    check_expand_children(p, c, node);
    let n = p.nodes[node]; var ty = expected;
    if n.left < 0 && n.type_id >= 0 { ty = n.type_id; }
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
        } else {
            let symbol = check_lookup_name(p, c, n.left, S_TYPE);
            var declaration = -1; if symbol >= 0 { declaration = p.symbols[symbol].node; }
            if declaration >= 0 && p.nodes[declaration].kind == N_STRUCT && p.nodes[declaration].third >= 0 && name.first < 0 {
                ty = check_infer_record_type(p, c, declaration, node, expected);
            } else { ty = check_resolve_type(p, c, n.left); }
        }
    }
    if ty < 0 || p.types[ty].kind != TY_STRUCT && p.types[ty].kind != TY_ENUM {
        diagnose(p, n.token, "record literal requires a struct or enum variant type"); return -1;
    }
    check_layout_nominal(p, c, ty); let result_type = ty;
    if p.types[ty].kind == TY_ENUM {
        if n.symbol >= 0 && p.nodes[n.symbol].kind == N_VARIANT { ty = p.nodes[n.symbol].type_id; }
        else { diagnose(p, n.token, "enum construction requires a named variant"); return -1; }
    }
    let first = p.types[ty].first; var self_type = ty;
    if p.types[ty].pool >= 0 {
        p.nodes[node].symbol = p.types[ty].declaration;
        if expected >= 0 && p.types[expected].kind == TY_ENUM && p.types[expected].declaration == p.types[p.types[ty].pool].declaration { self_type = expected; }
    }
    var binding = n.first; var positional = first; var seen_named = false; var seen_positional = false;
    var used = CheckList {}; var supplied_bindings = CheckList {}; var source_order = n.right;
    while binding >= 0 {
        let b = p.nodes[binding]; var field = -1;
        if b.aux >= 0 && !check_operation_same(p, ty, b.aux) { diagnose(p, b.token, "const for field accessor belongs to a different aggregate type"); }
        if b.kind == N_EMPTY { binding = b.next; continue; }
        if b.token >= 0 {
            if (b.flags & F_DEFAULT) == 0 { seen_named = true; } field = first;
            while field >= 0 { if same_name(p, p.nodes[field].token, b.token) && (p.nodes[field].flags & F_PAD) == 0 { break; } field = p.nodes[field].next; }
        } else {
            if (b.flags & F_DEFAULT) == 0 { seen_positional = true; }
            while positional >= 0 && (p.nodes[positional].flags & F_PAD) != 0 { positional = p.nodes[positional].next; }
            field = positional; if positional >= 0 { positional = p.nodes[positional].next; }
        }
        if field < 0 { diagnose(p, b.token, "record initializer names no field"); }
        else {
            for i in 0..used.count { if check_list_at(c, used, i) == field { diagnose(p, b.token, "field initialized more than once"); } }
            if (b.flags & F_DEFAULT) == 0 { check_list_push(c, used, field); }
            p.nodes[binding].symbol = field; p.nodes[binding].type_id = p.nodes[field].type_id;
            check_list_push(c, supplied_bindings, binding);
            if b.right < 0 { p.nodes[binding].right = b.left; p.nodes[binding].left = -1; }
        }
        binding = b.next;
    }
    if seen_named && seen_positional { diagnose(p, n.token, "record literal mixes named and positional initializers"); }
    // Preserve the immutable source ordinals only when a supplied pair inverts.
    if source_order < 0 && seen_named {
        var inversion = false;
        for a in 0..used.count {
            let high = check_list_at(c, used, a);
            for b in a + 1..used.count {
                let low = check_list_at(c, used, b); var field = first;
                while field >= 0 && field != high { if field == low { inversion = true; break; } field = p.nodes[field].next; }
            }
        }
        if inversion {
            var last = -1;
            for i in 0..used.count {
                let field = check_list_at(c, used, i); var at = first; var ordinal = 0;
                while at >= 0 && at != field { ordinal += 1; at = p.nodes[at].next; }
                let entry = new_node(p, N_TYPE_ARG, p.nodes[field].token); p.nodes[entry].integer = ordinal;
                if source_order < 0 { source_order = entry; } else { p.nodes[last].next = entry; } last = entry;
            }
        }
    }
    p.nodes[node].right = source_order;
    // Put every supplied or omitted initializer in place before checking any.
    var ordered = -1; var last = -1; var field = first;
    while field >= 0 {
        let f = p.nodes[field]; var init = -1;
        for i in 0..supplied_bindings.count {
            let candidate = check_list_at(c, supplied_bindings, i);
            if p.nodes[candidate].symbol == field { init = candidate; break; }
        }
        if (f.flags & F_PAD) == 0 {
            if init < 0 {
                if f.right < 0 && (n.flags & F_DEFAULT) == 0 && !(f.type_id >= 0 && p.types[f.type_id].kind == TY_REF && (p.types[f.type_id].flags & TF_OPTIONAL) != 0) {
                    diagnose(p, n.token, "record literal leaves a field without an initializer");
                } else {
                    var value = -1;
                    if f.right >= 0 { var bindings = CheckList {}; value = check_clone(p, c, f.right, bindings); }
                    else { value = check_default_syntax(p, c, f.type_id, n.token, 1); }
                    init = new_node(p, N_BINDING, f.token); p.nodes[init].symbol = field; p.nodes[init].type_id = f.type_id;
                    p.nodes[init].right = value; p.nodes[init].flags |= F_DEFAULT;
                }
            }
            if init >= 0 {
                if ordered < 0 { ordered = init; } else { p.nodes[last].next = init; } last = init;
            }
        }
        field = f.next;
    }
    if last >= 0 { p.nodes[last].next = -1; }
    p.nodes[node].first = ordered; p.nodes[node].last = last;
    binding = ordered;
    while binding >= 0 {
        let b = p.nodes[binding]; let field = b.symbol; let value = b.right;
        if value < 0 { diagnose(p, b.token, "field initializer is missing"); }
        else if (b.flags & F_DEFAULT) != 0 { p.nodes[binding].right = check_field_default(p, c, field, n.token, 0, self_type, value); }
        else if !check_self_init(p, c, value, field, self_type) { check_value(p, c, value, b.type_id); check_slot_value(p, c, value, b.type_id, true); }
        check_copy_roots(c, node, p.nodes[binding].right); binding = b.next;
    }
    // Every inverted supplied pair also crosses omitted declaration-position
    // defaults between it. An unrelated effect outside these spans is allowed.
    var a = source_order;
    while a >= 0 {
        var b = p.nodes[a].next;
        while b >= 0 {
            let high = p.nodes[a].integer; let low = p.nodes[b].integer;
            if high > low {
                var safe = true; var field = first; var ordinal = 0; var low_field = -1;
                while field >= 0 && ordinal <= high {
                    var test = ordinal == low || ordinal == high;
                    if ordinal > low && ordinal < high {
                        var supplied = false; var source = source_order;
                        while source >= 0 { if p.nodes[source].integer == ordinal { supplied = true; break; } source = p.nodes[source].next; }
                        test = !supplied;
                    }
                    if ordinal == low { low_field = field; }
                    if test && (p.nodes[field].flags & F_PAD) == 0 && !check_init_field_safe(p, c, node, field) { safe = false; }
                    field = p.nodes[field].next; ordinal += 1;
                }
                if !safe {
                    let init = check_init_binding(p, node, low_field); var token = n.token; if init >= 0 { token = p.nodes[init].token; }
                    diagnose(p, token, "field initializers must follow declaration order: reordering may cross a side effect, runtime check, or nonlocal exit");
                }
            }
            b = p.nodes[b].next;
        }
        a = p.nodes[a].next;
    }
    return result_type;
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
recursive fn check_array_receiver(p: Program&, c: Checker&, node: i64, write: bool) -> i64 {
    var ty = check_single_expression(p, c, node);
    while ty >= 0 && p.types[ty].kind == TY_REF { ty = p.types[ty].element; }
    if ty < 0 || p.types[ty].kind != TY_ARRAY && p.types[ty].kind != TY_SLICE {
        diagnose(p, p.nodes[node].token, "array builtin requires an array or slice receiver"); return -1;
    }
    if write && check_readonly(p, c, node) { diagnose(p, p.nodes[node].token, "array mutation requires writable storage"); }
    return ty;
}
fn check_live_views(p: Program&, c: Checker&, root: i64, token: i64) { }

fn check_mutation_views(p: Program&, c: Checker&, receiver: i64, shrink: bool) {
    let root = check_place_root(p, receiver);
    if root < 0 { return; }
    check_note_effect(c, root, 0);
    var array_type = p.nodes[receiver].type_id;
    while array_type >= 0 && p.types[array_type].kind == TY_REF { array_type = p.types[array_type].element; }
    // Growth keeps storage live. A limited array's pop/clear changes its
    // logical length while its fixed-capacity slots remain allocated.
    if !shrink || array_type >= 0 && p.types[array_type].kind == TY_ARRAY && p.types[array_type].array_kind == A_LIMITED { return; }
    check_note_effect(c, root, 2);
    check_live_views(p, c, root, p.nodes[receiver].token);
    for value in [receiver, -root - 10] {
        var at = check_root_head(c, value);
        while at >= 0 {
            let r = c.roots[at]; at = r.next;
            if r.root >= 0 && r.root != root { check_live_views(p, c, r.root, p.nodes[receiver].token); check_note_effect(c, r.root, 2); }
        }
    }
}
recursive fn check_render_hook(p: Program&, c: Checker&, type_id: i64) -> i64 {
    let t = p.types[type_id]; var namespace_scope = 0;
    if (t.kind == TY_STRUCT || t.kind == TY_ENUM) && t.declaration >= 0 {
        var scope = p.nodes[t.declaration].scope;
        if t.kind == TY_STRUCT && t.pool >= 0 { scope = p.nodes[p.types[t.pool].declaration].scope; }
        while scope > 0 { if c.scopes[scope].namespace_node >= 0 { namespace_scope = scope; break; } scope = c.scopes[scope].parent; }
    }
    var round = 0;
    while round < 2 {
        var scope = namespace_scope; if round == 1 { scope = 0; }
        let count = p.symbols.len;
        for index in 0..count {
            let symbol = p.symbols[index];
            if symbol.scope != scope || symbol.owner >= 0 || (symbol.flags & (S_FUNCTION | S_BUILTIN)) != S_FUNCTION || symbol.node < 0 || !token_is(p, symbol.name_token, "format") { continue; }
            let n = p.nodes[symbol.node];
            if n.kind != N_FUNCTION || n.origin >= 0 || n.third >= 0 || n.first < 0 { continue; }
            let first = n.first; let second = p.nodes[first].next;
            if second < 0 || p.nodes[second].next >= 0 || p.nodes[first].left < 0 || p.nodes[second].left < 0 { continue; }
            check_prepare_function(p, c, symbol.node);
            if (p.nodes[symbol.node].flags & F_GENERIC) != 0 { continue; }
            let output = p.nodes[first].type_id;
            if output < 0 || p.types[output].kind != TY_REF || (p.types[output].flags & TF_OPTIONAL) != 0 { continue; }
            let array = p.types[output].element;
            if array < 0 || p.types[array].kind != TY_ARRAY || p.types[array].array_kind != A_GROW || p.types[array].element != TYPE_U8 { continue; }
            var value = p.nodes[second].type_id;
            if value >= 0 && p.types[value].kind == TY_REF && (p.types[value].flags & TF_OPTIONAL) == 0 && p.types[value].length_storage < 0 { value = p.types[value].element; }
            if value >= 0 && t.kind == TY_SLICE && (p.types[value].flags & TF_CONST) != (t.flags & TF_CONST) { continue; }
            if value >= 0 && check_operation_same(p, value, type_id) { return index; }
        }
        if namespace_scope == 0 { break; } round += 1;
    }
    return -1;
}
fn check_render_has_hook(p: Program&, hooks: const i64[:], type_id: i64) -> bool {
    if type_id < 0 { return false; }
    var work: i64[>..] = [type_id]; var cursor = 0;
    while cursor < work.len {
        let current = work[cursor]; cursor += 1;
        if current < hooks.len && hooks[current] >= 0 { return true; }
        let t = p.types[current]; var child = -1;
        if t.kind == TY_REF || t.kind == TY_ARRAY || t.kind == TY_SLICE { child = t.element; }
        if child >= 0 { var found = false; for old in work { if old == child { found = true; } } if !found { work.push(child); } }
        if t.kind == TY_STRUCT || t.kind == TY_ENUM {
            var field = t.first;
            while field >= 0 {
                if t.kind == TY_ENUM {
                    var part = p.nodes[field].first;
                    while part >= 0 { let ty = p.nodes[part].type_id; if ty >= 0 { var found = false; for old in work { if old == ty { found = true; } } if !found { work.push(ty); } } part = p.nodes[part].next; }
                } else if (p.nodes[field].flags & F_PAD) == 0 {
                    let ty = p.nodes[field].type_id;
                    if ty >= 0 { var found = false; for old in work { if old == ty { found = true; } } if !found { work.push(ty); } }
                }
                field = p.nodes[field].next;
            }
        }
    }
    return false;
}
fn check_render_parameter(p: Program&, c: Checker&, node: i64, type_id: i64) -> i64 {
    if p.types[type_id].kind == TY_REF { return type_id; }
    if check_addressable(p, node) && check_operation_same(p, check_storage_type(p, node), type_id) {
        var flags = 0; if check_borrow_readonly(p, c, node) { flags |= TF_CONST; }
        return render_reference(p, type_id, flags);
    }
    return check_const_type(p, type_id);
}
fn check_render_layout(p: Program&, c: Checker&, type_id: i64, token: i64) -> bool {
    var work = CheckList {}; var visited = CheckList {}; check_list_push(c, work, type_id); var at = 0;
    while at < work.count {
        let ty = check_list_at(c, work, at); at += 1;
        if ty < 0 { diagnose(p, token, "empty array element type was never determined"); return false; }
        var seen = false; for index in 0..visited.count { if check_list_at(c, visited, index) == ty { seen = true; break; } }
        if seen { continue; } check_list_push(c, visited, ty);
        let t = p.types[ty];
        if t.kind == TY_STRUCT || t.kind == TY_ENUM {
            check_layout_nominal(p, c, ty);
            var field = p.types[ty].first;
            while field >= 0 { if (p.nodes[field].flags & F_PAD) == 0 { check_list_push(c, work, p.nodes[field].type_id); } field = p.nodes[field].next; }
        } else if t.kind == TY_REF || t.kind == TY_ARRAY || t.kind == TY_SLICE { check_list_push(c, work, t.element); }
    }
    return true;
}
recursive fn check_render_recurring(p: Program&, c: Checker&, ty: i64, path: CheckList&, recurring: CheckList&, variant: bool = false) {
    if ty < 0 { return; }
    let t = p.types[ty];
    for index in 0..path.count {
        if !check_same_type(p, check_list_at(c, path, index), ty) { continue; }
        var base = ty;
        while p.types[base].kind == TY_REF || p.types[base].kind == TY_ARRAY || p.types[base].kind == TY_SLICE { base = p.types[base].element; if base < 0 { return; } }
        for old in 0..recurring.count { if check_same_type(p, check_list_at(c, recurring, old), base) { return; } }
        check_list_push(c, recurring, base); return;
    }
    if !variant && ty < c.render_hooks.len && c.render_hooks[ty] >= 0 { return; }
    let saved = path; check_list_push(c, path, ty);
    if t.kind == TY_REF || t.kind == TY_ARRAY || t.kind == TY_SLICE { check_render_recurring(p, c, t.element, path, recurring); }
    else if t.kind == TY_STRUCT || t.kind == TY_ENUM {
        var field = t.first;
        while field >= 0 {
            if (p.nodes[field].flags & F_PAD) == 0 { check_render_recurring(p, c, p.nodes[field].type_id, path, recurring, t.kind == TY_ENUM); }
            field = p.nodes[field].next;
        }
    }
    path = saved;
}
fn check_has_format_hooks(p: Program&, c: Checker&) -> bool {
    while !c.has_format_hooks && c.format_scan_end < p.symbols.len {
        let index = c.format_scan_end; c.format_scan_end += 1;
        let symbol: const Symbol& = p.symbols[index];
        if symbol.node >= 0 && symbol.owner < 0 && token_is(p, symbol.name_token, "format") && (symbol.flags & S_BUILTIN) == 0 {
            c.has_format_hooks = true;
        }
    }
    return c.has_format_hooks;
}
recursive fn check_lower_rendering(p: Program&, c: Checker&, node: i64, builtin: i64, args: CheckList&) -> i64 {
    let hooks_exist = check_has_format_hooks(p, c);
    let wasm_default = p.pointer_bytes == 4 && builtin >= 0 && builtin <= 2;
    if !hooks_exist && !wasm_default { return -2; }
    var first = 0; if builtin == 2 { first = 1; }
    for index in first..args.count { let argument = check_list_at(c, args, index); if !check_render_layout(p, c, p.nodes[argument].type_id, p.nodes[argument].token) { return -1; } }
    while c.render_hooks.len < p.types.len {
        let type_id = c.render_hooks.len; c.render_hooks.push(-1);
        if check_has_format_hooks(p, c) { c.render_hooks[type_id] = check_render_hook(p, c, type_id); }
    }
    for index in first..args.count {
        let argument = check_list_at(c, args, index); var path = CheckList {}; var recurring = CheckList {};
        check_render_recurring(p, c, p.nodes[argument].type_id, path, recurring);
        for at in 0..recurring.count {
            if check_render_has_hook(p, c.render_hooks, check_list_at(c, recurring, at)) {
                diagnose(p, p.nodes[argument].token, "a recursively referenced rendered type needs its own format overload to use a part's format overload"); return -1;
            }
        }
    }
    var needed = false;
    for index in first..args.count {
        let argument = check_list_at(c, args, index); var ty = p.nodes[argument].type_id;
        if check_render_has_hook(p, c.render_hooks, ty) { needed = true; }
        if wasm_default && ty >= 0 && p.types[ty].kind == TY_REF && (p.types[ty].flags & TF_OPTIONAL) != 0 { needed = true; }
        while ty >= 0 && p.types[ty].kind == TY_REF { ty = p.types[ty].element; }
        if wasm_default && ty >= 0 {
            let t = p.types[ty];
            if t.kind == TY_STRUCT || t.kind == TY_ENUM || (t.kind == TY_ARRAY || t.kind == TY_SLICE) && t.element != TYPE_U8 { needed = true; }
        }
    }
    if !needed { return -2; }
    let output_type = render_output_type(p); let array_type = p.types[output_type].element;
    let original = p.nodes[node]; let out = operation_name(p, original.token, "__goose_render_builder");
    let body = new_node(p, N_BLOCK, original.token); p.nodes[body].flags = F_SYNTHETIC;
    let builder = new_node(p, N_VARIABLE, out); p.nodes[builder].flags = F_VAR;
    var limited = false;
    if builtin == 2 {
        let receiver = check_list_at(c, args, 0); let receiver_type = check_array_receiver(p, c, receiver, true);
        if receiver_type < 0 { return -1; }
        let receiver_kind = p.types[receiver_type].array_kind;
        if receiver_kind != A_GROW && receiver_kind != A_GROWSHRINK && receiver_kind != A_LIMITED { diagnose(p, original.token, "formatting requires a growable byte builder"); return -1; }
        var receiver_reference = output_type;
        if receiver_kind == A_LIMITED { limited = true; receiver_reference = render_reference(p, receiver_type); }
        p.nodes[builder].left = operation_type(p, receiver_reference, original.token);
        p.nodes[receiver].next = -1; var value = receiver;
        if receiver_kind == A_GROWSHRINK {
            let address = new_node(p, N_UNARY, original.token); p.nodes[address].left = value; p.nodes[address].integer = T_BITAND;
            let cast = new_node(p, N_CAST, original.token); p.nodes[cast].left = address; p.nodes[cast].right = operation_type(p, output_type, original.token); p.nodes[cast].flags = F_UNSIGNED | F_SYNTHETIC; value = cast;
        }
        p.nodes[builder].right = value;
    } else {
        p.nodes[builder].left = operation_type(p, array_type, original.token); p.nodes[builder].right = new_node(p, N_ARRAY, original.token);
    }
    append_child(p, body, builder);
    for index in first..args.count {
        let argument = check_list_at(c, args, index); let type_id = p.nodes[argument].type_id;
        if type_id < 0 || p.types[type_id].kind == TY_FN { continue; }
        let parameter = check_render_parameter(p, c, argument, type_id);
        let helper = render_function(p, c.render_cache, c.render_hooks, type_id, parameter);
        var argument_output = out;
        if limited {
            argument_output = operation_name(p, original.token, "__goose_render_argument");
            let temporary = new_node(p, N_VARIABLE, argument_output); p.nodes[temporary].flags = F_VAR;
            p.nodes[temporary].left = operation_type(p, array_type, original.token); p.nodes[temporary].right = new_node(p, N_ARRAY, original.token); append_child(p, body, temporary);
        }
        p.nodes[argument].next = -1; render_call(p, body, p.nodes[helper].token, argument_output, argument);
        if limited {
            let append_name = operation_name(p, original.token, "append", false);
            let append_symbol = check_builtin_symbol(p, append_name, 25, TYPE_VOID);
            render_call(p, body, append_name, out, operation_ident(p, argument_output), false, append_symbol);
        }
    }
    for key in c.render_cache {
        if p.nodes[key.helper].symbol < 0 {
            let saved_function = c.function_node; c.function_node = -1;
            p.nodes[key.helper].scope = 0; check_declare(p, c, key.helper, 0); c.function_node = saved_function;
        }
    }
    if builtin == 0 {
        let name = operation_name(p, original.token, "print", false); let print_call = new_node(p, N_CALL, original.token); p.nodes[print_call].left = operation_ident(p, name); p.nodes[print_call].flags = F_FORMAT_RAW | F_SYNTHETIC; append_child(p, print_call, operation_ident(p, out)); append_child(p, body, print_call);
    } else if builtin == 1 { let value = operation_ident(p, out); p.nodes[value].flags |= F_TAIL; p.nodes[body].flags |= F_TAIL; append_child(p, body, value); }
    var result = TYPE_VOID; if builtin == 1 { result = array_type; }
    var lowered = p.nodes[body]; lowered.next = original.next; lowered.flags |= original.flags & F_TAIL; lowered.scope = original.scope;
    p.nodes[node] = lowered;
    return check_expression(p, c, node, result);
}

fn check_builtin_pair(p: Program&, first_type: i64, token: i64) -> i64 {
    let first = new_node(p, N_TYPE_ARG, token); p.nodes[first].type_id = first_type;
    let second = new_node(p, N_TYPE_ARG, token); p.nodes[second].type_id = TYPE_BOOL; p.nodes[first].next = second;
    return check_tuple(p, first);
}
fn check_pool_flags(p: Program&, c: Checker&, receiver: i64, expression_roots: bool = false) -> i64 {
    let type_id = p.nodes[receiver].type_id;
    if type_id >= 0 && p.types[type_id].kind == TY_REF && (p.types[type_id].flags & TF_OPTIONAL) != 0 { return 0; }
    if type_id >= 0 && (p.types[type_id].flags & F_REUSABLE) != 0 { return p.types[type_id].flags & (F_REUSABLE | F_REUSABLE_SLICES); }
    let root = check_place_root(p, receiver); var work: i64[>..] = [];
    if root >= 0 { work.push(root); }
    else if expression_roots {
        var edge_at = check_root_head(c, receiver);
        while edge_at >= 0 {
            let edge = c.roots[edge_at]; edge_at = edge.next;
            if edge.kind != 0 || edge.root < 0 { return 0; }
            work.push(edge.root);
        }
    }
    if work.len == 0 { return 0; }
    var cursor = 0; var found = 0;
    while cursor < work.len {
        let symbol = p.symbols[work[cursor]]; cursor += 1; var flags = 0;
        if symbol.type_id >= 0 && p.types[symbol.type_id].kind == TY_REF && (p.types[symbol.type_id].flags & TF_OPTIONAL) != 0 { return 0; }
        if symbol.node >= 0 { flags = p.nodes[symbol.node].flags & (F_REUSABLE | F_REUSABLE_SLICES); }
        if symbol.type_id >= 0 { flags |= p.types[symbol.type_id].flags & (F_REUSABLE | F_REUSABLE_SLICES); }
        if flags != 0 { if found != 0 && found != flags { return 0; } found = flags; continue; }
        var held = false;
        var edge_at = check_root_head(c, -work[cursor - 1] - 10);
        while edge_at >= 0 {
            let edge = c.roots[edge_at]; edge_at = edge.next;
            if edge.kind != 0 { continue; }
            if edge.root < 0 { return 0; }
            held = true; var seen = false; for old in work { if old == edge.root { seen = true; break; } }
            if !seen { work.push(edge.root); }
        }
        if !held { return 0; }
    }
    return found;
}
recursive fn check_byte_output(p: Program&, c: Checker&, node: i64) {
    let ty = check_array_receiver(p, c, node, true);
    if ty < 0 { return; } let array = p.types[ty]; var byte = false;
    if array.element >= 0 {
        let element = p.types[array.element];
        byte = element.kind == TY_INT && element.count == 8 && element.storage == 0 && element.index_type < 0 && (element.flags & TF_UNSIGNED) != 0;
    }
    if !byte || array.kind != TY_ARRAY || array.array_kind != A_GROW && array.array_kind != A_GROWSHRINK && array.array_kind != A_LIMITED {
        diagnose(p, p.nodes[node].token, "byte output appends only to a writable growable u8 array");
    }
    check_mutation_views(p, c, node, false);
}

// Every route that completes a pending array validates its resolved element.
recursive fn check_complete_pending(p: Program&, c: Checker&, receiver: i64, array: i64, element: i64, token: i64) {
    if element < 0 || p.types[element].kind == TY_VOID || p.types[element].kind == TY_FN ||
       p.types[element].kind == TY_ARRAY && p.types[element].element < 0 ||
       p.types[element].kind == TY_REF && p.types[element].element == TYPE_VOID {
        diagnose(p, token, "cannot infer the element type of this array from this value"); return;
    }
    p.types[array].element = element;
    check_array_element(p, c, element, p.types[array].array_kind, token);
    if check_pool_flags(p, c, receiver) != 0 && check_size_class(p, element, 0) != 0 {
        diagnose(p, token, "reusable pools require fixed-size elements");
    }
}

// A pending element keeps a string literal's construction form through a
// block tail or a sole returning branch. Names, real joins and breaks do not.
recursive fn check_pending_string(p: Program&, c: Checker&, node: i64) -> bool {
    if node < 0 || check_bottom(p, node) { return false; }
    let n = p.nodes[node];
    if n.kind == N_STRING { return true; }
    if n.kind == N_BLOCK && (n.flags & F_TAIL) != 0 {
        if (n.flags & F_EARLY) != 0 {
            var breaks = CheckList {}; check_collect_break_values(p, c, node, node, breaks);
            if breaks.count != 0 { return false; }
        }
        return check_pending_string(p, c, n.last);
    }
    if n.kind == N_IF && n.third >= 0 {
        if check_bottom(p, n.right) { return check_pending_string(p, c, n.third); }
        if check_bottom(p, n.third) { return check_pending_string(p, c, n.right); }
    }
    if n.kind == N_MATCH {
        var selected = -1; var arm = n.first;
        while arm >= 0 {
            let body = p.nodes[arm].right;
            if !check_bottom(p, body) { if selected >= 0 { return false; } selected = body; }
            arm = p.nodes[arm].next;
        }
        return check_pending_string(p, c, selected);
    }
    return false;
}

recursive fn check_builtin(p: Program&, c: Checker&, node: i64, builtin: i64) -> i64 {
    let n = p.nodes[node]; var args = CheckList {};
    var argument = n.first;
    while argument >= 0 { check_list_push(c, args, argument); argument = p.nodes[argument].next; }
    var minimum = 1; var maximum = 1;
    if builtin == 0 || builtin == 1 { minimum = 0; maximum = 99; }
    if builtin == 2 { minimum = 1; maximum = 99; }
    if builtin == 6 || builtin == 12 || builtin == 14 { minimum = 0; maximum = 0; }
    if builtin == 11 { minimum = 0; maximum = 1; }
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
            if receiver >= 0 && p.types[receiver].element < 0 { check_complete_pending(p, c, check_list_at(c, args, 0), receiver, TYPE_U8, n.token); }
            if receiver >= 0 && p.types[receiver].element != TYPE_U8 { diagnose(p, n.token, "format receiver must be a byte array"); }
            check_mutation_views(p, c, check_list_at(c, args, 0), false); start = 1;
        }
        for i in start..args.count {
            let ty = check_value(p, c, check_list_at(c, args, i), -1);
            if ty >= 0 && p.types[ty].kind == TY_FN { diagnose(p, n.token, "a function value cannot be formatted"); }
        }
        if builtin == 1 { result = check_array_type(p, TYPE_U8, -1, A_GROW, 0); }
        if (n.flags & F_FORMAT_RAW) == 0 && c.reachable {
            let lowered = check_lower_rendering(p, c, node, builtin, args); if lowered != -2 { return lowered; }
        }
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
        let argument = check_list_at(c, args, 0); let source = check_expression(p, c, argument, -1);
        if source >= 0 && p.types[source].kind == TY_REF { result = check_value(p, c, argument, p.types[source].element); }
        else { result = check_value(p, c, argument, -1); }
        if result >= 0 && p.types[result].kind == TY_SLICE { diagnose(p, n.token, "copy takes a stored value or reference, not a slice"); }
        if !check_addressable(p, argument) && !(source >= 0 && p.types[source].kind == TY_REF) { diagnose(p, n.token, "copy of a temporary is unnecessary: its value is already fresh"); }
        if check_type_property(p, result, 6) != 0 { diagnose(p, n.token, "copying values containing self-relative references is unsupported"); }
        if result >= 0 && check_size_class(p, result, 0) == 2 && (p.types[result].kind == TY_ENUM || p.types[result].kind == TY_STRUCT && p.types[result].pool >= 0) { diagnose(p, n.token, "copying a resizable enum or variant is unsupported"); }
        check_copy_roots(c, node, argument);
    } else if builtin == 7 || builtin == 8 {
        let argument = check_list_at(c, args, 0); check_expression(p, c, argument, -1);
        let worker = validation_resolve_thread(p, argument);
        if worker >= 0 { p.nodes[argument].symbol = worker; p.nodes[argument].type_id = p.symbols[worker].type_id; }
        if worker < 0 || p.symbols[worker].node < 0 || (p.nodes[p.symbols[worker].node].flags & F_THREAD) == 0 {
            diagnose(p, n.token, "thread_spawn requires a thread_fn declaration");
        } else {
            let fnnode = p.symbols[worker].node;
            var active = false;
            for index in 0..c.checking_count { if c.checking[index] == fnnode { active = true; break; } }
            if !active { check_function(p, c, fnnode); }
            var formal = p.nodes[fnnode].first; var i = 1;
            while formal >= 0 && i < args.count {
                check_value(p, c, check_list_at(c, args, i), p.nodes[formal].type_id); formal = p.nodes[formal].next; i += 1;
            }
            if formal >= 0 || i != args.count { diagnose(p, n.token, "thread worker argument count does not match"); }
        }
        result = TYPE_I64;
    } else if builtin == 9 {
        check_value(p, c, check_list_at(c, args, 0), TYPE_I64); result = TYPE_BOOL;
        if args.count == 2 { check_byte_output(p, c, check_list_at(c, args, 1)); }
    }
    else if builtin == 10 {
        let argument = check_list_at(c, args, 0);
        validation_thread_transfer(p, argument, check_expression(p, c, argument, -1));
        let ty = check_value(p, c, argument, -1);
        if ty >= 0 && (check_contains_refs(p, ty, 0) || p.types[ty].kind == TY_ARRAY && p.types[ty].element < 0 || p.types[ty].kind == TY_VOID || p.types[ty].kind == TY_FN) { diagnose(p, n.token, "queue messages must be flat values with a concrete element type"); }
        result = TYPE_BOOL;
    } else if builtin == 11 || builtin == 12 || builtin == 13 {
        if type_argument < 0 { diagnose(p, n.token, "queue builtin requires an explicit message type"); return -1; }
        if check_contains_refs(p, type_argument, 0) || p.types[type_argument].kind == TY_VOID || p.types[type_argument].kind == TY_FN { diagnose(p, n.token, "queue message type must be flat"); }
        if builtin == 11 || builtin == 12 {
            result = type_argument;
            if builtin == 12 || args.count > 0 { result = check_builtin_pair(p, type_argument, n.token); }
        }
        if args.count > 0 { check_value(p, c, check_list_at(c, args, 0), TYPE_I64); }
    } else if builtin == 18 {
        if type_argument < 0 { diagnose(p, n.token, "from_bytes requires an explicit result type"); return -1; }
        let bytes = check_array_receiver(p, c, check_list_at(c, args, 0), false);
        if bytes >= 0 && p.types[bytes].element != TYPE_U8 { diagnose(p, n.token, "from_bytes requires bytes"); }
        let destination = p.types[type_argument];
        if destination.kind != TY_ARRAY || destination.array_kind != A_GROW && destination.array_kind != A_GROWSHRINK && destination.array_kind != A_VAR { diagnose(p, n.token, "from_bytes constructs only a resizable or variable array"); }
        result = check_builtin_pair(p, type_argument, n.token); check_add_root(c, node, -2);
    } else if builtin == 20 {
        let argument = check_list_at(c, args, 0); check_value(p, c, argument, TYPE_STRING);
        let replacement = source_embed_file(p, node, argument);
        if replacement < 0 { return -1; }
        let next = n.next; let scope = n.scope;
        p.nodes[node] = p.nodes[replacement]; p.nodes[node].next = next; p.nodes[node].scope = scope;
        return check_expression(p, c, node, -1);
    } else if builtin == 19 {
        diagnose(p, n.token, "embed_shader requires shader compilation tool integration"); result = TYPE_STRING;
    } else if builtin == 16 || builtin == 17 {
        let source = check_list_at(c, args, 0); let storage = check_array_receiver(p, c, source, false);
        if storage < 0 { return -1; }
        let element = p.types[storage].element;
        if element < 0 { diagnose(p, n.token, "a byte image requires a concrete source type"); }
        if check_type_property(p, element, 5) != 0 { diagnose(p, n.token, "byte images cannot contain slices, plain references, pool-relative references or function values"); }
        if builtin == 16 {
            if args.count == 2 { check_byte_output(p, c, check_list_at(c, args, 1)); }
            else { result = check_array_type(p, TYPE_U8, -1, A_GROW, 0); check_add_root(c, node, -2); }
        } else {
            result = check_type(p, TY_SLICE, TYPE_U8, -1, -1, TF_CONST);
            check_copy_roots(c, node, source); check_add_root(c, node, check_place_root(p, source), 1);
        }
    } else {
        let write = builtin == 2 || builtin >= 24;
        let receiver = check_array_receiver(p, c, check_list_at(c, args, 0), write);
        if receiver < 0 { return -1; }
        var element = p.types[receiver].element; let array_kind = p.types[receiver].array_kind;
        if builtin == 21 || builtin == 22 || builtin == 23 { result = TYPE_I64; }
        if builtin == 22 && array_kind != A_LIMITED { diagnose(p, n.token, "cap is available only on limited arrays"); }
        if builtin == 23 {
            if array_kind == A_VAR || array_kind == A_SLICE { diagnose(p, n.token, "index_of requires a fixed-stride array owner"); }
            let argument = check_list_at(c, args, 1);
            var actual = check_single_expression(p, c, argument);
            actual = check_read_value_type(p, c, argument, actual);
            if actual >= 0 && p.types[actual].kind != TY_REF && check_addressable(p, argument) && check_same_type(p, check_storage_type(p, argument), element) {
                var flags = 0; if check_readonly(p, c, argument, true) { flags |= TF_CONST; }
                let reference = check_type(p, TY_REF, element, 0, -1, flags);
                actual = check_expect(p, c, argument, actual, reference);
            }
            if actual < 0 || p.types[actual].kind != TY_REF || (p.types[actual].flags & TF_OPTIONAL) != 0 || p.types[actual].length_storage >= 0 || !check_same_type(p, p.types[actual].element, element) {
                diagnose(p, n.token, "index_of requires a reference to an element of its array owner");
            }
        }
        if builtin >= 24 {
            if p.types[receiver].kind != TY_ARRAY || array_kind == A_FIXED || array_kind == A_VAR {
                diagnose(p, n.token, "array operation requires a resizable or limited owner");
            }
            let shrink = builtin == 26 || builtin == 27 || builtin == 28 || builtin == 29 || builtin == 32 || builtin == 34 || builtin == 35;
            check_mutation_views(p, c, check_list_at(c, args, 0), shrink);
            if builtin == 24 || builtin == 30 || builtin == 31 {
                if element < 0 {
                    let value = check_list_at(c, args, 1);
                    element = check_value(p, c, value, -1);
                    if check_pending_string(p, c, value) {
                        element = check_array_type(p, TYPE_U8, -1, A_VAR, 0);
                        check_expect(p, c, value, p.nodes[value].type_id, element);
                    }
                    check_complete_pending(p, c, check_list_at(c, args, 0), receiver, element, n.token);
                } else { check_value(p, c, check_list_at(c, args, 1), element); }
                let root = check_place_root(p, check_list_at(c, args, 0));
                if check_contains_refs(p, element, 0) { check_store_roots(p, c, root, check_list_at(c, args, 1)); }
                if builtin == 30 { result = TYPE_I64; }
                else if element >= 0 && p.types[element].kind == TY_REF { result = check_loaded_type(p, element); check_copy_roots(c, node, check_list_at(c, args, 1)); }
                else { var flags = 0; if element >= 0 && p.types[element].storage == 1 { flags |= TF_CONST; } result = check_type(p, TY_REF, element, 0, -1, flags); check_add_root(c, node, root, 1); }
            } else if builtin == 25 {
                let source_node = check_list_at(c, args, 1);
                if element >= 0 && (p.nodes[source_node].kind == N_ARRAY || p.nodes[source_node].kind == N_FILL) {
                    var expected_run = check_type(p, TY_SLICE, element, -1, -1, 0);
                    if check_size_class(p, element, 0) == 1 { expected_run = check_array_type(p, element, -1, A_VAR, 0); }
                    check_expression(p, c, source_node, expected_run);
                }
                let source = check_array_receiver(p, c, source_node, false);
                if source >= 0 {
                    if element < 0 { element = p.types[source].element; check_complete_pending(p, c, check_list_at(c, args, 0), receiver, element, n.token); }
                    else if !check_same_type(p, element, p.types[source].element) { diagnose(p, n.token, "append requires the same element type"); }
                    if check_contains_refs(p, element, 0) { check_store_roots(p, c, check_place_root(p, check_list_at(c, args, 0)), check_list_at(c, args, 1)); }
                }
            } else if builtin == 26 { result = check_loaded_type(p, element); check_copy_roots(c, node, check_list_at(c, args, 0)); }
            else if builtin == 27 || builtin == 28 || builtin == 32 {
                if builtin == 32 {
                    let index = check_list_at(c, args, 1);
                    let ty = check_numeric_value_type(p, check_value(p, c, index, -1));
                    if c.reachable && !check_integer(ty) { diagnose(p, p.nodes[index].token, "free requires an integer index"); }
                } else { check_value(p, c, check_list_at(c, args, 1), TYPE_I64); }
                if builtin == 28 && args.count == 3 { check_value(p, c, check_list_at(c, args, 2), element); }
            } else if builtin == 33 || builtin == 34 || builtin == 35 {
                let view = check_type(p, TY_SLICE, element, -1, -1, 0);
                if builtin != 33 { check_value(p, c, check_list_at(c, args, 1), check_const_type(p, view)); }
                if builtin != 35 {
                    var count_index = 1; if builtin == 34 { count_index = 2; }
                    check_value(p, c, check_list_at(c, args, count_index), TYPE_I64);
                    let default_value = check_default(p, c, element, n.token, 0);
                    p.nodes[node].aux = default_value;
                    if builtin == 34 && check_type_property(p, element, 6) != 0 { diagnose(p, n.token, "realloc_slice cannot move elements containing self-relative references"); }
                    result = view; check_add_root(c, node, check_place_root(p, check_list_at(c, args, 0)), 1);
                }
            }
            if builtin >= 30 {
                let flags = check_pool_flags(p, c, check_list_at(c, args, 0));
                var required = F_REUSABLE; if builtin >= 33 { required |= F_REUSABLE_SLICES; }
                if array_kind != A_GROW || flags != required { diagnose(p, n.token, "allocation builtin requires the corresponding reusable slot or slice pool"); }
                if element < 0 || check_size_class(p, element, 0) != 0 { diagnose(p, n.token, "reusable pools require fixed-size elements"); }
            }
        }
    }
    if p.nodes[node].kind == N_CALL {
        p.nodes[node].symbol = check_builtin_symbol(p, callee.token, builtin, result);
        p.nodes[n.left].symbol = p.nodes[node].symbol;
    }
    return result;
}
recursive fn check_obvious_void_body(p: Program&, body: i64) -> bool {
    if body < 0 { return true; }
    let n = p.nodes[body];
    if n.kind == N_BLOCK {
        if (n.flags & F_TAIL) == 0 || n.last < 0 { return true; }
        return check_obvious_void_body(p, n.last);
    }
    if n.kind == N_IF { return check_obvious_void_body(p, n.right) && (n.third < 0 || check_obvious_void_body(p, n.third)); }
    if n.kind == N_MATCH {
        var arm = n.first;
        while arm >= 0 { if !check_obvious_void_body(p, p.nodes[arm].right) { return false; } arm = p.nodes[arm].next; }
        return true;
    }
    return n.kind == N_WHILE || n.kind == N_FOR || n.kind == N_CONST_FOR ||
        n.kind == N_ASSIGN || n.kind == N_MULTI_ASSIGN || n.kind == N_VARIABLE ||
        n.kind == N_EMPTY || n.kind == N_RETURN && n.first < 0;
}

recursive fn check_prepare_function(p: Program&, c: Checker&, function_node: i64) {
    if p.nodes[function_node].type_id >= 0 { return; }
    // Result inference below reads the body of a recursive function without a declared result.
    if (p.nodes[function_node].flags & F_RECURSIVE) != 0 && p.nodes[function_node].left < 0 { parse_deferred_body(p, function_node); }
    let n = p.nodes[function_node];
    let saved_scope = c.scope; let saved_function = c.function_node; let saved_slot = c.next_slot;
    let symbol = n.symbol;
    if n.scope >= 0 { c.scope = n.scope; }
    else if symbol >= 0 && p.symbols[symbol].scope >= 0 { c.scope = p.symbols[symbol].scope; }
    c.function_node = function_node; c.next_slot = 0;
    check_enter(c, function_node); p.nodes[function_node].scope = c.scope;
    check_ensure_generics(p, c, function_node);
    var generic = n.third >= 0; var param = n.first;
    while param >= 0 {
        var ty = p.nodes[param].type_id;
        if ty < 0 {
            if p.nodes[param].left >= 0 { ty = check_resolve_type(p, c, p.nodes[param].left); }
            else { ty = check_type(p, TY_GENERIC, -1, 0, param, 0); }
        }
        ty = check_value_annotation(p, c, p.nodes[param].left, ty);
        if ty >= 0 && p.types[ty].kind == TY_GENERIC { generic = true; }
        if check_has_generic(p, ty, 0) { generic = true; }
        p.nodes[param].type_id = ty;
        let ps = check_declare(p, c, param, c.scope); p.symbols[ps].type_id = ty;
        let vi = check_variable_index(c, ps); c.variables[vi].assigned = true; c.variables[vi].maybeassigned = true;
        if ty >= 0 && check_contains_refs(p, ty, 0) {
            var root_kind = 0; if p.types[ty].kind == TY_SLICE { root_kind = 1; }
            check_add_root(c, -ps - 10, ps, root_kind);
        }
        param = p.nodes[param].next;
    }
    var ret = n.left;
    while ret >= 0 {
        let result_type = check_resolve_type(p, c, ret);
        if result_type >= 0 && p.types[result_type].kind == TY_REF && p.nodes[ret].kind == N_TYPE_NAME && p.nodes[ret].left < 0 {
            let binding = check_lookup_name(p, c, ret, S_TYPE);
            if binding >= 0 && p.symbols[binding].node >= 0 && p.nodes[p.symbols[binding].node].kind == N_TYPE_PARAM { p.nodes[ret].type_id = check_loaded_type(p, result_type); }
        }
        ret = p.nodes[ret].next;
    }
    var result = -1; if n.left >= 0 { result = check_tuple(p, n.left); }
    if result < 0 && (n.flags & F_RECURSIVE) != 0 && n.right >= 0 && check_obvious_void_body(p, n.right) { result = TYPE_VOID; }
    if n.kind == N_FUNCTION_VALUE && n.left < 0 && n.aux >= 0 { result = n.aux; }
    if n.right < 0 && result < 0 { result = TYPE_VOID; }
    let type_id = add_type(p, Type { kind: TY_FN, element: result, declaration: function_node, first: n.first, size: p.pointer_bytes, align: p.pointer_bytes });
    p.nodes[function_node].type_id = type_id;
    if symbol >= 0 { p.symbols[symbol].type_id = type_id; }
    if generic { p.nodes[function_node].flags |= F_GENERIC; }
    c.scope = saved_scope; c.function_node = saved_function; c.next_slot = saved_slot;
}
fn check_has_generic(p: Program&, ty: i64, depth: i64) -> bool { return check_type_property(p, ty, 0) != 0; }
fn check_environment_head(c: Checker&, function_node: i64) -> i64 {
    if function_node < 0 || function_node >= c.environment_heads.len { return -1; }
    return c.environment_heads[function_node];
}
fn check_environment_add(p: Program&, c: Checker&, value: CheckEnvironment) {
    let function_node = c.function_node;
    if function_node < 0 || value.symbol < 0 { return; }
    let symbol = p.symbols[value.symbol];
    if symbol.owner == function_node || (symbol.flags & (S_TYPE | S_FUNCTION)) != 0 { return; }
    if (symbol.flags & S_GLOBAL) != 0 && (symbol.type_id < 0 || p.types[symbol.type_id].kind != TY_REF || (p.types[symbol.type_id].flags & TF_OPTIONAL) == 0) { return; }
    let head = check_environment_head(c, function_node); var at = head;
    while at >= 0 { let old = c.environments[at]; if old.symbol == value.symbol { return; } at = old.next; }
    while c.environment_heads.len <= function_node { c.environment_heads.push(-1); }
    var entry = value; entry.next = head;
    let id = c.environments.len; c.environments.push(entry); c.environment_heads[function_node] = id;
}
fn check_environment_note(p: Program&, c: Checker&, symbol: i64) {
    let vi = check_variable_index(c, symbol); if vi < 0 { return; }
    let v = c.variables[vi];
    check_environment_add(p, c, CheckEnvironment { symbol: symbol, assigned: v.assigned, maybeassigned: v.maybeassigned, narrowed: v.narrowed, readonly: v.readonly });
}
fn check_environment_callee(p: Program&, c: Checker&, function_node: i64) {
    if function_node == c.function_node { return; }
    var at = check_environment_head(c, function_node);
    while at >= 0 { let value = c.environments[at]; at = value.next; check_environment_add(p, c, value); }
}
fn check_environment_same(p: Program&, c: Checker&, function_node: i64, token: i64) -> bool {
    var active = false;
    for index in 0..c.checking_count { if c.checking[index] == function_node { active = true; } }
    var at = check_environment_head(c, function_node);
    while at >= 0 {
        let previous = c.environments[at]; at = previous.next;
        let vi = check_variable_index(c, previous.symbol); if vi < 0 { return false; }
        let current = c.variables[vi];
        if active {
            if previous.narrowed >= 0 && !check_same_type(p, previous.narrowed, current.narrowed) {
                diagnose(p, token, "recursive call requires a captured optional to remain narrowed");
            }
        } else if current.assigned != previous.assigned ||
           (p.symbols[previous.symbol].flags & S_MUTABLE) == 0 && current.maybeassigned != previous.maybeassigned ||
           !check_same_type(p, current.narrowed, previous.narrowed) || current.readonly != previous.readonly { return false; }
    }
    return true;
}
fn check_function_reached(p: Program&, c: Checker&, function_node: i64, token: i64) -> bool {
    var declaration = function_node; var depth = 0;
    while declaration >= 0 && p.nodes[declaration].kind == N_FUNCTION && depth < 64 {
        let symbol = p.nodes[declaration].symbol;
        if symbol >= 0 && p.symbols[symbol].scope >= 0 {
            let scope = p.symbols[symbol].scope;
            if scope > 0 && c.scopes[scope].namespace_node < 0 && p.symbols[symbol].index < 0 {
                diagnose(p, token, "a nested function is called before its declaration is reached"); return false;
            }
            return true;
        }
        declaration = p.nodes[declaration].origin; depth += 1;
    }
    return true;
}

fn check_need_active(c: Checker&, function_node: i64) -> bool {
    for index in 0..c.checking_count { if c.checking[index] == function_node { return true; } }
    return false;
}
fn check_need_target(p: Program&, c: Checker&, target: i64, path: i64) -> i64 {
    let declaration = check_function_declaration(p, target); var cursor = path;
    while cursor >= 0 {
        let frame = c.need_frames[cursor];
        if p.nodes[frame.function_node].kind == N_FUNCTION && check_function_declaration(p, frame.function_node) == declaration { return cursor; }
        cursor = frame.parent;
    }
    return -1;
}
fn check_need_context(p: Program&, c: Checker&, function_node: i64) -> bool {
    for need in c.needs {
        if need.function_node != function_node { continue; }
        let found = check_need_target(p, c, need.target, c.need_path);
        if found >= 0 && c.need_frames[found].function_node != need.target { return false; }
    }
    return true;
}
fn check_need_error(p: Program&, c: Checker&, function_node: i64, target: i64, token: i64, path: i64, found: i64) {
    var message: u8[>..] = [];
    if found < 0 { message.format("call requires an enclosing nonlocal return target"); }
    else { message.format("recursive call changes the enclosing specialization of a long-distance return"); }
    message.format(" [callee#", function_node, " target#", target, " innermost#", found, " path");
    var cursor = path;
    while cursor >= 0 { let frame = c.need_frames[cursor]; message.format(" ", frame.function_node); cursor = frame.parent; }
    message.format("]"); diagnose(p, token, message);
}
recursive fn check_need_on_path(p: Program&, c: Checker&, function_node: i64, target: i64, token: i64, path: i64) {
    let found = check_need_target(p, c, target, path);
    if found < 0 { check_need_error(p, c, function_node, target, token, path, -1); return; }
    if c.need_frames[found].function_node != target { check_need_error(p, c, function_node, target, token, path, c.need_frames[found].function_node); return; }
    var cursor = path;
    while cursor != found {
        let frame = c.need_frames[cursor]; check_add_need(p, c, frame.function_node, target); cursor = frame.parent;
    }
}
recursive fn check_add_need(p: Program&, c: Checker&, function_node: i64, target: i64) {
    if function_node < 0 || function_node == target { return; }
    for need in c.needs { if need.function_node == function_node && need.target == target { return; } }
    c.needs.push(CheckNeed { function_node: function_node, target: target });
    let end = c.need_edges.len;
    for index in 0..end {
        let edge = c.need_edges[index];
        if edge.function_node == function_node { check_need_on_path(p, c, function_node, target, edge.token, edge.path); }
    }
}
fn check_reuse_needs(p: Program&, c: Checker&, function_node: i64, token: i64) -> bool {
    if !check_need_context(p, c, function_node) && !check_need_active(c, function_node) { return false; }
    c.need_edges.push(CheckNeedEdge { function_node: function_node, token: token, path: c.need_path });
    let end = c.needs.len;
    for index in 0..end {
        let need = c.needs[index];
        if need.function_node == function_node { check_need_on_path(p, c, function_node, need.target, token, c.need_path); }
    }
    return true;
}

recursive fn check_specialize_function(p: Program&, c: Checker&, original: i64, bindings: CheckList&, token: i64) -> i64 {
    parse_deferred_body(p, original);
    if !check_function_reached(p, c, original, token) { return -1; }
    if bindings.count == 0 && check_environment_same(p, c, original, token) {
        if (p.nodes[original].flags & F_CHECKED) == 0 && !check_need_active(c, original) { return p.nodes[original].symbol; }
        if check_reuse_needs(p, c, original, token) { return p.nodes[original].symbol; }
    }
    for spec in c.specializations {
        if spec.original != original || spec.binding_count != bindings.count { continue; }
        var equal = true;
        for i in 0..bindings.count { let b = check_binding_at(c, bindings, i);
            let old = c.bindings[spec.binding_start + i];
            if old.parameter != b.parameter || !check_binding_same(p, old.value, b.value) { equal = false; }
        }
        if equal && check_environment_same(p, c, p.symbols[spec.symbol].node, token) && check_reuse_needs(p, c, p.symbols[spec.symbol].node, token) { return spec.symbol; }
    }
    var same_declaration = 0;
    for active_index in 0..c.checking_count { let active = c.checking[active_index]; if active == original || p.nodes[active].origin == original { same_declaration += 1; } }
    if same_declaration >= 16 || c.inference_depth >= 64 { diagnose(p, token, "function specialization does not reach a finite set"); return -1; }
    c.inference_depth += 1;
    let saved_syntax = c.clone_syntax; let saved_body = c.syntax_body; let saved_function = c.syntax_function;
    c.clone_syntax = false; c.syntax_function = original; c.syntax_body = p.nodes[original].right;
    if original < c.syntax_lookup.len && c.syntax_lookup[original] >= 0 {
        c.syntax_body = c.syntax_nodes[c.syntax_lookup[original]].right;
    }
    let copy = check_clone(p, c, original, bindings);
    c.clone_syntax = saved_syntax; c.syntax_body = saved_body; c.syntax_function = saved_function;
    p.nodes[copy].type_id = -1; p.nodes[copy].third = -1; p.nodes[copy].origin = original;
    p.nodes[copy].flags &= ~F_GENERIC;
    if p.nodes[original].kind == N_FUNCTION_VALUE {
        for binding_index in 0..bindings.count { let binding = check_binding_at(c, bindings, binding_index); if binding.parameter == original { p.nodes[copy].aux = binding.value; } }
    }
    let old = p.symbols[p.nodes[original].symbol];
    let symbol = p.symbols.len;
    p.symbols.push(Symbol { name_token: old.name_token, node: copy, scope: -2, flags: old.flags, owner: old.owner });
    p.nodes[copy].symbol = symbol;
    let start = c.bindings.len; for binding_index in 0..bindings.count { c.bindings.push(check_binding_at(c, bindings, binding_index)); }
    c.specializations.push(CheckSpecialization { original: original, symbol: symbol, binding_start: start, binding_count: bindings.count });
    let saved = c.scope; c.scope = c.scopes[p.nodes[original].scope].parent;
    check_enter(c, copy);
    for b_index in 0..bindings.count { let b = check_binding_at(c, bindings, b_index);
        if p.nodes[b.parameter].token < 0 || p.nodes[original].kind == N_FUNCTION_VALUE && b.parameter == original { continue; }
        let binding = new_node(p, N_TYPE_PARAM, p.nodes[b.parameter].token); p.nodes[binding].type_id = b.value;
        check_declare(p, c, binding, c.scope);
    }
    p.nodes[copy].scope = c.scope;
    check_prepare_function(p, c, copy); check_function(p, c, copy);
    p.nodes[original].flags |= p.nodes[copy].flags & (F_CAPTURE | F_NONLOCAL);
    if p.nodes[original].captures < 0 { p.nodes[original].captures = p.nodes[copy].captures; }
    c.scope = saved; c.inference_depth -= 1;
    return symbol;
}

recursive fn check_find_it(p: Program&, node: i64) -> i64 {
    if node < 0 { return -1; }
    let n = p.nodes[node];
    if n.kind == N_NAME && token_is(p, n.token, "it") { return n.token; }
    if n.kind == N_FUNCTION_VALUE { return -1; }
    if n.kind == N_FUNCTION {
        var parameter = n.first;
        while parameter >= 0 { if token_is(p, p.nodes[parameter].token, "it") { return -1; } parameter = p.nodes[parameter].next; }
        return check_find_it(p, n.right);
    }
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
    if token < 0 { token = operation_name(p, n.token, "__goose_unused_parameter"); }
    let parameter = new_node(p, N_PARAM, token);
    p.nodes[node].first = parameter; p.nodes[node].last = parameter; p.nodes[node].type_id = -1;
    p.nodes[node].flags &= ~F_CHECKED;
    if n.symbol >= 0 { p.symbols[n.symbol].type_id = -1; }
    let saved = c.scope; c.scope = n.scope;
    check_prepare_function(p, c, node); c.scope = saved;
}

recursive fn check_same_signature(p: Program&, c: Checker&, a: i64, b: i64) -> bool {
    check_prepare_function(p, c, a); check_prepare_function(p, c, b);
    var ap = p.nodes[a].first; var bp = p.nodes[b].first;
    while ap >= 0 && bp >= 0 {
        if !check_same_type(p, p.nodes[ap].type_id, p.nodes[bp].type_id) { return false; }
        ap = p.nodes[ap].next; bp = p.nodes[bp].next;
    }
    return ap < 0 && bp < 0;
}
fn check_function_cutoff(p: Program&, c: Checker&, owner: i64, token: i64) -> i64 {
    var function_node = c.function_node;
    while function_node >= 0 {
        let symbol = p.nodes[function_node].symbol;
        if symbol < 0 { break; }
        let parent = p.symbols[symbol].owner;
        if parent == owner { return p.nodes[function_node].token; }
        function_node = parent;
    }
    return token;
}
recursive fn check_function_shadowed(p: Program&, c: Checker&, candidate: i64, candidates: CheckList&, token: i64) -> bool {
    let s = p.symbols[candidate];
    if s.owner < 0 || p.nodes[s.node].kind != N_FUNCTION { return false; }
    var cutoff = token;
    if s.owner != c.function_node { cutoff = check_function_cutoff(p, c, s.owner, token); }
    if s.owner == c.function_node && s.index < 0 { return true; }
    let position = p.nodes[s.node].token;
    for index in 0..candidates.count {
        let other = check_list_at(c, candidates, index); let o = p.symbols[other];
        if other == candidate || o.owner != s.owner || o.scope != s.scope || p.nodes[o.node].kind != N_FUNCTION { continue; }
        let at = p.nodes[o.node].token;
        if s.owner == c.function_node && o.index < 0 { continue; }
        if (at <= cutoff && (position > cutoff || at > position) || position > cutoff && at > cutoff && at < position) && check_same_signature(p, c, s.node, o.node) { return true; }
    }
    return false;
}

fn check_function_declaration(p: Program&, function_node: i64) -> i64 {
    var declaration = function_node;
    while declaration >= 0 && p.nodes[declaration].origin >= 0 { declaration = p.nodes[declaration].origin; }
    return declaration;
}

// Borrowing matching storage is an exact call match. Conversion and AST
// adaptation still use check_conversion/check_expect after selection.
recursive fn check_exact_borrow(p: Program&, c: Checker&, node: i64, expected: i64) -> bool {
    if expected < 0 || p.types[expected].kind != TY_REF || p.types[expected].length_storage >= 0 || (p.types[expected].flags & TF_OPTIONAL) != 0 { return false; }
    if node < 0 || check_bottom(p, node) { return true; }
    let n = p.nodes[node];
    if n.kind == N_LOOP || n.kind == N_BLOCK && (n.flags & F_EARLY) != 0 {
        var values = CheckList {}; check_collect_break_values(p, c, node, node, values);
        if n.kind == N_BLOCK && (n.flags & F_TAIL) != 0 && !check_bottom(p, n.last) { check_list_push(c, values, n.last); }
        if values.count == 0 { return false; }
        for index in 0..values.count { if !check_exact_borrow(p, c, check_list_at(c, values, index), expected) { return false; } }
        return true;
    }
    if n.kind == N_BLOCK && (n.flags & F_TAIL) != 0 { return check_exact_borrow(p, c, n.last, expected); }
    if n.kind == N_IF { return n.third >= 0 && check_exact_borrow(p, c, n.right, expected) && check_exact_borrow(p, c, n.third, expected); }
    if n.kind == N_MATCH {
        var arm = n.first;
        if arm < 0 { return false; }
        while arm >= 0 { if !check_exact_borrow(p, c, p.nodes[arm].right, expected) { return false; } arm = p.nodes[arm].next; }
        return true;
    }
    if check_addressable(p, node) && check_operation_same(p, check_storage_type(p, node), p.types[expected].element) { return true; }
    return n.type_id >= 0 && p.types[n.type_id].kind == TY_REF && check_operation_same(p, n.type_id, expected);
}

fn check_argument_inference(p: Program&, c: Checker&, node: i64, formal: i64, function_node: i64 = -1, parameter: i64 = -1) -> i64 {
    var actual = p.nodes[node].type_id;
    if actual >= 0 && function_node >= 0 && p.nodes[function_node].kind == N_FUNCTION_VALUE && parameter >= 0 && p.nodes[parameter].left < 0 {
        let n = p.nodes[node];
        if (n.kind == N_IF || n.kind == N_MATCH || n.kind == N_BLOCK || n.kind == N_LOOP) && p.types[actual].kind == TY_REF && (p.types[actual].flags & TF_OPTIONAL) == 0 {
            return p.types[actual].element;
        }
        return actual;
    }
    if actual < 0 || formal < 0 || p.types[formal].kind != TY_GENERIC { return actual; }
    if p.types[actual].kind == TY_INT { return check_index_value(p, node, check_numeric_value_type(p, actual)); }
    if p.types[actual].kind == TY_REF {
        return check_loaded_type(p, actual);
    }
    if check_size_class(p, actual, 0) > 0 && check_addressable(p, node) {
        var flags = 0; if check_readonly(p, c, node) { flags |= TF_CONST; }
        actual = check_type(p, TY_REF, actual, 0, -1, flags);
    }
    return actual;
}

// Literals constrain generics after typed inputs, as their scalar leaves do.
recursive fn check_literal_argument(p: Program&, c: Checker&, node: i64, depth: i64 = 0) -> bool {
    if node < 0 || depth > 64 { return false; }
    if check_bottom(p, node) { return true; }
    let n = p.nodes[node];
    if n.kind == N_ARRAY || n.kind == N_FILL {
        var child = n.first;
        while child >= 0 { if !check_literal_argument(p, c, child, depth + 1) { return false; } child = p.nodes[child].next; }
        return true;
    }
    if n.kind == N_LOOP || n.kind == N_BLOCK && (n.flags & F_EARLY) != 0 {
        var values = CheckList {}; check_collect_break_values(p, c, node, node, values);
        if n.kind == N_BLOCK && (n.flags & F_TAIL) != 0 && !check_bottom(p, n.last) { check_list_push(c, values, n.last); }
        if values.count == 0 { return false; }
        for index in 0..values.count { if !check_literal_argument(p, c, check_list_at(c, values, index), depth + 1) { return false; } }
        return true;
    }
    if n.kind == N_BLOCK && (n.flags & F_TAIL) != 0 { return check_literal_argument(p, c, n.last, depth + 1); }
    if n.kind == N_IF { return n.third >= 0 && check_literal_argument(p, c, n.right, depth + 1) && check_literal_argument(p, c, n.third, depth + 1); }
    if n.kind == N_MATCH {
        var arm = n.first;
        if arm < 0 { return false; }
        while arm >= 0 { if !check_literal_argument(p, c, p.nodes[arm].right, depth + 1) { return false; } arm = p.nodes[arm].next; }
        return true;
    }
    return n.kind == N_NULL || check_literal_tree(p, node, 0) || check_float_literal_tree(p, node, 0) || check_flex_integer(p, c, node).flexible;
}
fn check_float_argument(p: Program&, c: Checker&, node: i64) -> bool {
    var leaf = p.nodes[node].type_id;
    while leaf >= 0 && p.types[leaf].kind == TY_ARRAY { leaf = p.types[leaf].element; }
    return check_float(check_numeric_value_type(p, leaf)) && check_literal_argument(p, c, node);
}

recursive fn check_choose_call(p: Program&, c: Checker&, callee: Node, args: CheckList&, candidates: CheckList&, no_defaults: bool) -> CheckChoice {
    var best = -1; var best_score = 9223372036854775807; var ambiguous = false; var best_hof = false; var best_converting = true;
    var best_bindings = CheckList {}; var typeless = false;
    for arg_index in 0..args.count {
        let arg = check_list_at(c, args, arg_index); let ty = p.nodes[arg].type_id;
        if check_empty_tree(p, arg) || ty >= 0 && p.types[ty].kind == TY_REF && p.types[ty].element == TYPE_VOID { typeless = true; }
    }
    for candidate_index in 0..candidates.count { let candidate = check_list_at(c, candidates, candidate_index);
        let fnnode = p.symbols[candidate].node;
        if check_function_shadowed(p, c, candidate, candidates, callee.token) { continue; }
        check_prepare_function(p, c, fnnode);
        var bindings = CheckList {};
        var generic = p.nodes[fnnode].third; var explicit_arg = callee.first; var matches = true;
        while generic >= 0 && explicit_arg >= 0 {
            let ty = check_resolve_type(p, c, explicit_arg);
            if !check_bind_generic(p, c, generic, ty, bindings) { matches = false; }
            generic = p.nodes[generic].next; explicit_arg = p.nodes[explicit_arg].next;
        }
        if explicit_arg >= 0 { matches = false; }
        var infer_formal = p.nodes[fnnode].first; var infer_index = 0;
        while infer_formal >= 0 && infer_index < args.count {
            let argument = check_list_at(c, args, infer_index);
            if !check_literal_argument(p, c, argument) &&
               !check_unify(p, c, p.nodes[infer_formal].type_id, check_argument_inference(p, c, argument, p.nodes[infer_formal].type_id, fnnode, infer_formal), bindings) { matches = false; }
            infer_formal = p.nodes[infer_formal].next; infer_index += 1;
        }
        // A floating literal-like argument binds before integer literals;
        // typed arguments have already anchored their generic parameters.
        infer_formal = p.nodes[fnnode].first; infer_index = 0;
        while infer_formal >= 0 && infer_index < args.count {
            let argument = check_list_at(c, args, infer_index); let actual = p.nodes[argument].type_id;
            if check_float_argument(p, c, argument) {
                check_unify(p, c, p.nodes[infer_formal].type_id, actual, bindings);
            }
            infer_formal = p.nodes[infer_formal].next; infer_index += 1;
        }
        var formal = p.nodes[fnnode].first; var index = 0; var score = 0; var converting = false;
        while formal >= 0 && index < args.count {
            let ft = p.nodes[formal].type_id; let at = p.nodes[check_list_at(c, args, index)].type_id;
            if ft >= 0 && at >= 0 && p.types[ft].kind == TY_FN && p.types[at].kind == TY_FN {
                if !check_bind_generic(p, c, p.types[ft].declaration, at, bindings) { matches = false; }
            } else if !check_unify(p, c, ft, check_argument_inference(p, c, check_list_at(c, args, index), ft, fnnode, formal), bindings) && !check_literal_tree(p, check_list_at(c, args, index), 0) && !check_float_literal_tree(p, check_list_at(c, args, index), 0) { matches = false; }
            var concrete = check_substitute(p, c, ft, bindings);
            if concrete >= 0 && p.types[concrete].kind == TY_REF && (p.types[concrete].flags & TF_OPTIONAL) == 0 && p.types[p.types[concrete].element].kind == TY_ARRAY {
                let flags = check_pool_flags(p, c, check_list_at(c, args, index));
                if flags != 0 && (p.types[concrete].flags & (F_REUSABLE | F_REUSABLE_SLICES)) != flags {
                    var qualified = p.types[concrete]; qualified.flags |= flags; concrete = add_type(p, qualified);
                    if !check_bind_generic(p, c, formal, concrete, bindings) { matches = false; }
                }
            }
            if concrete >= 0 && (p.types[concrete].kind == TY_SLICE || p.types[concrete].kind == TY_REF) &&
               (p.types[concrete].flags & TF_CONST) == 0 && check_argument_readonly(p, c, check_list_at(c, args, index), concrete) {
                if (p.nodes[fnnode].flags & F_EXTERN) != 0 { matches = false; }
                concrete = check_const_type(p, concrete);
                if !check_bind_generic(p, c, formal, concrete, bindings) { matches = false; }
            }
            var conversion = check_conversion(p, c, check_list_at(c, args, index), at, concrete);
            if conversion > 0 && check_exact_borrow(p, c, check_list_at(c, args, index), concrete) { conversion = 0; }
            if conversion < 0 { matches = false; } else if conversion > 0 && score < 2 { score = 2; }
            var value_type = at;
            if value_type >= 0 && p.types[value_type].kind == TY_REF { value_type = p.types[value_type].element; }
            if check_integer(check_numeric_value_type(p, value_type)) && check_float(check_numeric_value_type(p, concrete)) { converting = true; }
            if !typeless && check_has_generic(p, ft, 0) && score < 1 { score = 1; }
            formal = p.nodes[formal].next; index += 1;
        }
        var hof = false;
        while formal < 0 && index < args.count {
            let extra = check_list_at(c, args, index); let extra_type = p.nodes[extra].type_id;
            if extra_type < 0 || p.types[extra_type].kind != TY_FN { break; }
            var unbound = -1; var candidate_generic = p.nodes[fnnode].third;
            while candidate_generic >= 0 {
                var bound = false;
                for binding_index in 0..bindings.count { let binding = check_binding_at(c, bindings, binding_index); if binding.parameter == candidate_generic { bound = true; } }
                if !bound { unbound = candidate_generic; break; }
                candidate_generic = p.nodes[candidate_generic].next;
            }
            if unbound < 0 || !check_bind_generic(p, c, unbound, extra_type, bindings) { break; }
            hof = true; index += 1;
        }
        if index != args.count { matches = false; }
        while formal >= 0 {
            if no_defaults || p.nodes[formal].right < 0 { matches = false; }
            formal = p.nodes[formal].next;
        }
        generic = p.nodes[fnnode].third;
        while generic >= 0 {
            var bound = false; for b_index in 0..bindings.count { let b = check_binding_at(c, bindings, b_index); if b.parameter == generic { bound = true; } }
            if !bound { matches = false; }
            generic = p.nodes[generic].next;
        }
        if !matches { continue; }
        if best < 0 || !converting && best_converting || converting == best_converting && !converting && score < best_score {
            best = candidate; best_score = score; ambiguous = false; best_hof = hof; best_converting = converting;
            best_bindings = bindings;
        } else if converting == best_converting && (converting || score == best_score) { ambiguous = true; }
    }
    return CheckChoice { symbol: best, bindings: best_bindings, ambiguous: ambiguous, hof: best_hof, converting: best_converting };
}

fn check_context_float(c: Checker&, node: i64) -> i64 {
    if node < 0 || node >= c.contextual_lookup.len { return -1; }
    return c.contextual_lookup[node];
}
fn check_names_generic(p: Program&, c: Checker&, type_id: i64, generic: i64) -> bool {
    var work = CheckList {}; var visited = CheckList {}; check_list_push(c, work, type_id);
    var work_index = 0;
    while work_index < work.count {
        let ty = check_list_at(c, work, work_index); work_index += 1;
        if ty < 0 { continue; }
        var seen = false;
        for index in 0..visited.count { if check_list_at(c, visited, index) == ty { seen = true; break; } }
        if seen { continue; } check_list_push(c, visited, ty);
        let t = p.types[ty];
        if t.kind == TY_GENERIC && t.declaration == generic { return true; }
        if t.kind == TY_REF || t.kind == TY_SLICE || t.kind == TY_ARRAY || t.kind == TY_FN { check_list_push(c, work, t.element); }
        if t.kind == TY_FN || t.kind == TY_TUPLE {
            var part = t.first;
            while part >= 0 { check_list_push(c, work, p.nodes[part].type_id); part = p.nodes[part].next; }
        }
        if t.kind == TY_STRUCT || t.kind == TY_ENUM {
            var nominal = ty; if t.kind == TY_STRUCT && t.pool >= 0 { nominal = t.pool; }
            var argument = p.types[nominal].arguments;
            while argument >= 0 { check_list_push(c, work, p.nodes[argument].type_id); argument = p.nodes[argument].next; }
        }
    }
    return false;
}
fn check_same_bindings(p: Program&, c: Checker&, left: CheckList&, right: CheckList&) -> bool {
    if left.count != right.count { return false; }
    for index in 0..left.count {
        let binding = check_binding_at(c, left, index); var found = false;
        for other in 0..right.count {
            let candidate = check_binding_at(c, right, other);
            if candidate.parameter == binding.parameter && check_binding_same(p, candidate.value, binding.value) { found = true; break; }
        }
        if !found { return false; }
    }
    return true;
}
recursive fn check_context_float_choice(p: Program&, c: Checker&, node: i64, callee: Node, args: CheckList&, candidates: CheckList&, natural: CheckChoice, expected: i64) -> CheckChoice {
    if natural.symbol < 0 || natural.ambiguous { return natural; }
    let original = p.symbols[natural.symbol].node; let fnnode = p.nodes[original];
    if fnnode.kind != N_FUNCTION || (fnnode.flags & F_EXTERN) != 0 || fnnode.left < 0 || p.nodes[fnnode.left].next >= 0 { return natural; }
    let result = p.nodes[fnnode.left].type_id;
    if result < 0 || p.types[result].kind != TY_GENERIC { return natural; }
    let generic = p.types[result].declaration;
    var own = false; var parameter = fnnode.third; var ordinal = 0;
    while parameter >= 0 {
        if parameter == generic {
            if ordinal < check_list_count(p, callee.first) { return natural; }
            own = true; break;
        }
        parameter = p.nodes[parameter].next; ordinal += 1;
    }
    if !own { return natural; }
    var narrowed = CheckList {}; var floating = false;
    var original_bindings = natural.bindings;
    for index in 0..original_bindings.count {
        var binding = check_binding_at(c, original_bindings, index);
        if binding.parameter == generic {
            if binding.value != TYPE_F64 { return natural; }
            binding.value = TYPE_F32; floating = true;
        }
        check_binding_push(c, narrowed, binding);
    }
    if !floating { return natural; }
    var trial_args = CheckList {}; var formal = fnnode.first; var index = 0; var changed = false;
    while formal >= 0 {
        let ft = p.nodes[formal].type_id;
        let mentions = check_names_generic(p, c, ft, generic);
        if mentions && (ft < 0 || p.types[ft].kind != TY_GENERIC || index >= args.count) { return natural; }
        if index < args.count {
            let argument = check_list_at(c, args, index); var trial = argument;
            if mentions {
                let at = check_numeric_value_type(p, p.nodes[argument].type_id);
                let integer = check_integer(at) && (check_literal_tree(p, argument, 0) || check_constant(p, c, argument, 0).valid);
                if !check_float_literal_tree(p, argument, 0) && !integer && check_context_float(c, argument) < 0 { return natural; }
                trial = new_node(p, N_NAME, p.nodes[argument].token);
                p.nodes[trial].type_id = TYPE_F32; p.nodes[trial].flags = F_CHECKED;
                changed = true;
            }
            check_list_push(c, trial_args, trial);
        }
        index += 1; formal = p.nodes[formal].next;
    }
    while index < args.count { check_list_push(c, trial_args, check_list_at(c, args, index)); index += 1; }
    if !changed { return natural; }
    let trial = check_choose_call(p, c, callee, trial_args, candidates, false); var trial_bindings = trial.bindings;
    if trial.symbol != natural.symbol || trial.ambiguous || !check_same_bindings(p, c, narrowed, trial_bindings) { return natural; }
    while c.contextual_lookup.len <= node { c.contextual_lookup.push(-1); }
    let key = c.contextual_floats.len;
    c.contextual_floats.push(CheckContextFloat { node: node, original: original, bindings: narrowed }); c.contextual_lookup[node] = key;
    if expected == TYPE_F32 { return trial; }
    return natural;
}
recursive fn check_narrow_context_float(p: Program&, c: Checker&, node: i64) -> bool {
    let key = check_context_float(c, node);
    if key < 0 || p.nodes[node].kind != N_CALL { return false; }
    let context = c.contextual_floats[key]; var bindings = context.bindings;
    let symbol = check_specialize_function(p, c, context.original, bindings, p.nodes[node].token);
    if symbol < 0 { return false; }
    let function_node = p.symbols[symbol].node;
    p.nodes[node].symbol = symbol; p.nodes[p.nodes[node].left].symbol = symbol;
    var parameter = p.nodes[function_node].first; var argument = p.nodes[node].first;
    while parameter >= 0 && argument >= 0 {
        check_value(p, c, argument, p.nodes[parameter].type_id);
        check_slot_value(p, c, argument, p.nodes[parameter].type_id);
        parameter = p.nodes[parameter].next; argument = p.nodes[argument].next;
    }
    p.nodes[node].type_id = p.types[p.symbols[symbol].type_id].element;
    return p.nodes[node].type_id == TYPE_F32;
}

fn check_record_outer_exits(p: Program&, c: Checker&, function_node: i64, entry: CheckSpan&, exit_start: i64) {
    if (p.nodes[function_node].flags & F_NONLOCAL) == 0 { return; }
    let scope = p.nodes[function_node].scope; let exit_end = c.exit_work.len;
    for exit_index in exit_start..exit_end {
        let exit = c.exit_work[exit_index]; if exit.backedge || exit.target == function_node { continue; }
        var active = false;
        for index in 0..c.checking_count - 1 { if c.checking[index] == exit.target { active = true; break; } }
        if !active { continue; }
        var summary = c.scopes[scope].outer_exits;
        while summary >= 0 && c.outer_exits[summary].target != exit.target { summary = c.outer_exits[summary].next; }
        let first = summary < 0;
        if first {
            summary = c.outer_exits.len;
            c.outer_exits.push(CheckOuterExit { target: exit.target, flow: CheckSpan { first: c.flow_work.len }, next: c.scopes[scope].outer_exits });
            c.scopes[scope].outer_exits = summary;
        }
        var ordinal = 0;
        for entry_index in entry.first..entry.first + entry.count {
            let initial = c.flow_work[entry_index]; if initial.assigned { continue; }
            var assigned = false; var maybeassigned = false;
            for at in exit.flow.first..exit.flow.first + exit.flow.count {
                let value = c.flow_work[at]; if value.symbol != initial.symbol { continue; }
                assigned = value.assigned; maybeassigned = value.maybeassigned && !initial.maybeassigned; break;
            }
            if first {
                c.flow_work.push(CheckFlow { symbol: initial.symbol, assigned: assigned, maybeassigned: maybeassigned });
                c.outer_exits[summary].flow.count += 1;
            } else {
                let at = c.outer_exits[summary].flow.first + ordinal;
                c.flow_work[at].assigned = c.flow_work[at].assigned && assigned;
                c.flow_work[at].maybeassigned = c.flow_work[at].maybeassigned || maybeassigned;
            }
            ordinal += 1;
        }
    }
}
fn check_replay_outer_exits(p: Program&, c: Checker&, function_node: i64) {
    let scope = p.nodes[function_node].scope; if scope < 0 { return; }
    var at = c.scopes[scope].outer_exits;
    while at >= 0 {
        let summary = c.outer_exits[at]; at = summary.next;
        var active = false;
        for index in 0..c.checking_count { if c.checking[index] == summary.target { active = true; break; } }
        if !active { continue; }
        var flow = CheckSpan {}; check_flow_save(p, c, flow);
        for index in flow.first..flow.first + flow.count {
            let value = c.flow_work[index];
            for old_index in summary.flow.first..summary.flow.first + summary.flow.count {
                let added = c.flow_work[old_index]; if added.symbol != value.symbol { continue; }
                c.flow_work[index].assigned = value.assigned || added.assigned;
                c.flow_work[index].maybeassigned = value.maybeassigned || added.maybeassigned; break;
            }
        }
        c.exit_work.push(CheckExit { target: summary.target, flow: flow });
        p.nodes[summary.target].flags |= F_RETURNS; p.nodes[summary.target].flags &= ~F_DIVERGES;
    }
}

fn check_apply_call_effects(p: Program&, c: Checker&, node: i64, function_node: i64, args: CheckList&) {
    check_environment_callee(p, c, function_node);
    check_replay_outer_exits(p, c, function_node);
    let roots_end = c.return_roots.len;
    for i in 0..roots_end {
        let rr = c.return_roots[i];
        if rr.function_node != function_node { continue; }
        if rr.root < 0 { check_add_root(c, node, rr.root, rr.kind); continue; }
        let root_symbol = p.symbols[rr.root];
        if root_symbol.owner == function_node && (root_symbol.flags & S_PARAMETER) != 0 {
            let slot = root_symbol.slot;
            if slot >= 0 && slot < args.count {
                check_copy_roots(c, node, check_list_at(c, args, slot));
                if check_addressable(p, check_list_at(c, args, slot)) { check_add_root(c, node, check_place_root(p, check_list_at(c, args, slot)), rr.kind); }
            }
        } else { check_add_root(c, node, rr.root, rr.kind); }
    }
    let effects_end = c.effects.len;
    for i in 0..effects_end {
        let effect = c.effects[i];
        if effect.function_node != function_node { continue; }
        let root = p.symbols[effect.root];
        if effect.kind == 7 { check_global_use(p, c, effect.root, p.nodes[node].token); continue; }
        if !check_global_use(p, c, effect.root, p.nodes[node].token) { continue; }
        if root.owner == function_node && (root.flags & S_PARAMETER) == 0 { continue; }
        if root.owner == function_node && (root.flags & S_PARAMETER) != 0 && root.slot >= 0 && root.slot < args.count {
            if effect.kind == 1 || effect.kind == 2 { check_mutation_views(p, c, check_list_at(c, args, root.slot), effect.kind == 2); }
            else if effect.kind != 6 { check_note_effect(c, check_place_root(p, check_list_at(c, args, root.slot)), effect.kind); }
        } else {
            check_note_effect(c, effect.root, effect.kind);
            let vi = check_variable_index(c, effect.root);
            if vi >= 0 && effect.kind == 6 {
                if (root.flags & S_MUTABLE) == 0 && c.variables[vi].maybeassigned { diagnose(p, p.nodes[node].token, "call may assign a let binding that may already be assigned"); }
                c.variables[vi].maybeassigned = true;
            }
            if vi >= 0 && effect.kind == 4 { c.variables[vi].assigned = true; c.variables[vi].maybeassigned = true; }
            if vi >= 0 && effect.kind == 5 { c.variables[vi].narrowed = -1; }
            if effect.kind == 2 { check_live_views(p, c, effect.root, p.nodes[node].token); }
        }
    }
    if (p.nodes[function_node].flags & F_NONLOCAL) != 0 && c.function_node >= 0 { p.nodes[c.function_node].flags |= F_NONLOCAL; }
}

// Dispatch borrows every contributing storage branch, retaining its authority.
recursive fn check_dispatch_readonly(p: Program&, c: Checker&, node: i64) -> bool {
    if node < 0 || check_bottom(p, node) { return false; }
    let n = p.nodes[node];
    if n.kind == N_LOOP || n.kind == N_BLOCK && (n.flags & F_EARLY) != 0 {
        var values = CheckList {}; check_collect_break_values(p, c, node, node, values);
        if n.kind == N_BLOCK && (n.flags & F_TAIL) != 0 && !check_bottom(p, n.last) { check_list_push(c, values, n.last); }
        for index in 0..values.count { if check_dispatch_readonly(p, c, check_list_at(c, values, index)) { return true; } }
        return false;
    }
    if n.kind == N_BLOCK && (n.flags & F_TAIL) != 0 { return check_dispatch_readonly(p, c, n.last); }
    if n.kind == N_IF { return check_dispatch_readonly(p, c, n.right) || check_dispatch_readonly(p, c, n.third); }
    if n.kind == N_MATCH {
        var arm = n.first;
        while arm >= 0 { if check_dispatch_readonly(p, c, p.nodes[arm].right) { return true; } arm = p.nodes[arm].next; }
        return false;
    }
    return check_borrow_readonly(p, c, node);
}

recursive fn check_try_dispatch(p: Program&, c: Checker&, node: i64, expected: i64, args: CheckList&, candidates: CheckList&) -> i64 {
    let call = p.nodes[node]; let callee = p.nodes[call.left];
    var position = -1; var selected_arms = -1; var selected_hof = false; var selected_byref = false;
    for index in 0..args.count {
        let argument = check_list_at(c, args, index); var enum_type = p.nodes[argument].type_id; var through_ref = false;
        if enum_type >= 0 && p.types[enum_type].kind == TY_REF { through_ref = true; enum_type = p.types[enum_type].element; }
        if enum_type < 0 || p.types[enum_type].kind != TY_ENUM { continue; }
        check_layout_nominal(p, c, enum_type);
        let reference = check_type(p, TY_REF, enum_type, 0, -1, 0);
        let byref = (p.types[enum_type].flags & F_VARIABLE_MODE) != 0 &&
            (through_ref || check_size_class(p, enum_type, 0) != 0 && check_exact_borrow(p, c, argument, reference));
        let alternatives = new_node(p, N_EMPTY, call.token); var variant = p.types[enum_type].first; var complete = true; var all_hof = false;
        while variant >= 0 {
            let payload = p.nodes[variant].type_id; var trial_type = payload;
            if byref { var flags = 0; if check_dispatch_readonly(p, c, argument) { flags |= TF_CONST; } trial_type = check_type(p, TY_REF, payload, 0, -1, flags); }
            var trial_args = CheckList {};
            for at in 0..args.count {
                let source = check_list_at(c, args, at); var copy = p.nodes[source]; copy.next = -1;
                if at == index {
                    // Rank the payload, not the enum construct's source branches.
                    copy = Node { kind: N_EMPTY, token: copy.token, type_id: trial_type, flags: F_CHECKED, scope: copy.scope };
                }
                if copy.kind == N_FUNCTION_VALUE { copy.kind = N_NAME; }
                copy.flags |= F_CHECKED;
                let trial = p.nodes.len; p.nodes.push(copy); check_copy_roots(c, trial, source); check_list_push(c, trial_args, trial);
            }
            let choice = check_choose_call(p, c, callee, trial_args, candidates, true);
            if choice.symbol < 0 || choice.ambiguous { complete = false; break; }
            if variant == p.types[enum_type].first { all_hof = choice.hof; }
            else if all_hof != choice.hof { complete = false; break; }
            let arm = new_node(p, N_BINDING, p.nodes[variant].token);
            p.nodes[arm].type_id = payload; p.nodes[arm].symbol = choice.symbol; p.nodes[arm].integer = p.nodes[variant].integer;
            for b in 0..choice.bindings.count {
                var bindings = choice.bindings; let value = check_binding_at(c, bindings, b);
                let binding = new_node(p, N_TYPE_ARG, p.nodes[value.parameter].token);
                p.nodes[binding].type_id = value.value; p.nodes[binding].symbol = value.parameter; append_child(p, arm, binding);
            }
            append_child(p, alternatives, arm); variant = p.nodes[variant].next;
        }
        if !complete { continue; }
        if position >= 0 { diagnose(p, call.token, "case dispatch can select only one enum argument"); return -1; }
        position = index; selected_arms = p.nodes[alternatives].first; selected_hof = all_hof; selected_byref = byref;
    }
    if position < 0 { return -1; }
    var first_symbol = -1; var result = -1; var arm = selected_arms; var any_reference = false; var expected_parameters = -1; var may_return = false;
    while arm >= 0 {
        var bindings = CheckList {}; var binding = p.nodes[arm].first;
        while binding >= 0 {
            check_binding_push(c, bindings, TypeBinding { parameter: p.nodes[binding].symbol, value: p.nodes[binding].type_id });
            binding = p.nodes[binding].next;
        }
        let original = p.symbols[p.nodes[arm].symbol].node;
        let symbol = check_specialize_function(p, c, original, bindings, call.token);
        if symbol < 0 { return -1; }
        let function_node = p.symbols[symbol].node; check_function(p, c, function_node);
        if (p.nodes[function_node].flags & F_DIVERGES) == 0 { may_return = true; }
        let fn_type = p.symbols[symbol].type_id;
        if first_symbol < 0 { first_symbol = symbol; result = p.types[fn_type].element; expected_parameters = p.types[fn_type].first; }
        else if !check_same_type(p, result, p.types[fn_type].element) { diagnose(p, call.token, "case functions must agree on their result types"); }
        var parameter = p.types[fn_type].first; var first_parameter = expected_parameters; var index = 0;
        while parameter >= 0 && first_parameter >= 0 {
            let ty = p.nodes[parameter].type_id;
            if index == position {
                if p.types[ty].kind == TY_REF { any_reference = true; p.nodes[arm].flags |= F_REFERENCE; }
            } else if !check_same_type(p, ty, p.nodes[first_parameter].type_id) {
                diagnose(p, call.token, "case functions must agree on non-dispatch parameter types");
            }
            parameter = p.nodes[parameter].next; first_parameter = p.nodes[first_parameter].next; index += 1;
        }
        p.nodes[arm].symbol = symbol; p.nodes[arm].first = -1; p.nodes[arm].last = -1; p.nodes[arm].flags |= F_CHECKED;
        check_apply_call_effects(p, c, node, function_node, args); arm = p.nodes[arm].next;
    }
    let dispatched = check_list_at(c, args, position); var enum_type = p.nodes[dispatched].type_id;
    if enum_type >= 0 && p.types[enum_type].kind == TY_REF { enum_type = p.types[enum_type].element; }
    if any_reference && (p.types[enum_type].flags & F_VARIABLE_MODE) == 0 { diagnose(p, call.token, "fixed-mode enum payloads pass to cases by value"); }
    if check_size_class(p, enum_type, 0) == 2 { diagnose(p, call.token, "case dispatch cannot bind a resizable enum payload"); }
    var parameter = expected_parameters; var index = 0; var last = -1;
    while parameter >= 0 && index < args.count {
        let argument = check_list_at(c, args, index);
        if index != position { check_value(p, c, argument, p.nodes[parameter].type_id); }
        else if selected_byref && p.types[p.nodes[argument].type_id].kind != TY_REF {
            var flags = 0; if check_dispatch_readonly(p, c, argument) { flags |= TF_CONST; }
            let reference = check_type(p, TY_REF, enum_type, 0, -1, flags); check_expect(p, c, argument, p.nodes[argument].type_id, reference);
        }
        if last < 0 { p.nodes[node].first = argument; } else { p.nodes[last].next = argument; }
        last = argument; parameter = p.nodes[parameter].next; index += 1;
    }
    if last >= 0 { p.nodes[last].next = -1; }
    p.nodes[node].last = last; p.nodes[node].third = selected_arms; p.nodes[node].aux = position;
    p.nodes[node].symbol = first_symbol; p.nodes[node].type_id = result; p.nodes[node].flags |= F_DISPATCH;
    if any_reference { p.nodes[node].flags |= F_REFERENCE; }
    if !may_return { p.nodes[node].flags |= F_DIVERGES; c.reachable = false; }
    return result;
}

fn check_array_member_builtin(builtin: i64) -> bool {
    return builtin == 2 || builtin == 16 || builtin == 17 || builtin >= 23;
}

recursive fn check_member_function(p: Program&, c: Checker&, token: i64, receiver: i64) -> i64 {
    var ty = receiver;
    while ty >= 0 && p.types[ty].kind == TY_REF { ty = p.types[ty].element; }
    if ty >= 0 && p.types[ty].kind == TY_STRUCT {
        check_layout_nominal(p, c, ty); var field = p.types[ty].first;
        while field >= 0 {
            if (p.nodes[field].flags & F_PAD) == 0 && same_name(p, p.nodes[field].token, token) {
                diagnose(p, token, "a field is not callable"); return -2;
            }
            field = p.nodes[field].next;
        }
    }
    // Member syntax passes variables. Type parameters hide every function
    // set; local functions then precede the receiver and caller namespaces.
    var scope = c.scope; var local = -1;
    while scope > 0 && c.scopes[scope].namespace_node < 0 {
        let parameter = check_lookup_scope(p, c, token, scope, S_TYPE);
        if parameter >= 0 && p.nodes[p.symbols[parameter].node].kind == N_TYPE_PARAM {
            diagnose(p, token, "a type parameter cannot be called as a member"); return -2;
        }
        if local < 0 { local = check_lookup_scope(p, c, token, scope, S_FUNCTION | S_BUILTIN); }
        scope = c.scopes[scope].parent;
    }
    if local >= 0 { return local; }
    if ty >= 0 && p.types[ty].kind == TY_STRUCT && p.types[ty].pool >= 0 { ty = p.types[ty].pool; }
    if ty >= 0 && (p.types[ty].kind == TY_STRUCT || p.types[ty].kind == TY_ENUM) {
        var nominal_scope = p.nodes[p.types[ty].declaration].scope;
        while nominal_scope > 0 && c.scopes[nominal_scope].namespace_node < 0 { nominal_scope = c.scopes[nominal_scope].parent; }
        if nominal_scope > 0 {
            let nominal = check_lookup_scope(p, c, token, nominal_scope, S_FUNCTION | S_BUILTIN);
            if nominal >= 0 { return nominal; }
        }
    }
    return check_lookup(p, c, token, scope, S_FUNCTION);
}

// An untyped block parameter receives the construct's copied value.
// Direct reference arguments and explicitly typed reference parameters retain
// their ordinary borrowing path.
recursive fn check_funval_copy(p: Program&, c: Checker&, node: i64, expected: i64) {
    if node < 0 || check_bottom(p, node) || expected < 0 || p.types[expected].kind == TY_REF || check_size_class(p, expected, 0) == 0 { return; }
    let n = p.nodes[node];
    if n.kind == N_LOOP || n.kind == N_BLOCK && (n.flags & F_EARLY) != 0 {
        var values = CheckList {}; check_collect_break_values(p, c, node, node, values);
        if n.kind == N_BLOCK && (n.flags & F_TAIL) != 0 && !check_bottom(p, n.last) { check_list_push(c, values, n.last); }
        for index in 0..values.count { check_funval_copy(p, c, check_list_at(c, values, index), expected); }
        return;
    }
    if n.kind == N_BLOCK && (n.flags & F_TAIL) != 0 { check_funval_copy(p, c, n.last, expected); return; }
    if n.kind == N_IF { check_funval_copy(p, c, n.right, expected); check_funval_copy(p, c, n.third, expected); return; }
    if n.kind == N_MATCH { var arm = n.first; while arm >= 0 { check_funval_copy(p, c, p.nodes[arm].right, expected); arm = p.nodes[arm].next; } return; }
    var source = n.type_id;
    if source >= 0 && p.types[source].kind == TY_REF && (p.types[source].flags & TF_OPTIONAL) == 0 { source = p.types[source].element; }
    if source >= 0 && check_size_class(p, source, 0) > 0 && (check_addressable(p, node) || n.type_id >= 0 && p.types[n.type_id].kind == TY_REF) {
        diagnose(p, n.token, "non-fixed storage requires explicit copy when passed or stored by value");
    }
}

recursive fn check_call(p: Program&, c: Checker&, node: i64, expected: i64) -> i64 {
    var n = p.nodes[node];
    let original_callee = p.nodes[n.left];
    var member = false; var member_symbol = -1;
    if original_callee.kind == N_MEMBER {
        if original_callee.aux >= 0 { diagnose(p, original_callee.token, "const for field accessor is not callable"); return -1; }
        member = true;
        let receiver = original_callee.left;
        var ty = check_single_expression(p, c, receiver);
        while ty >= 0 && p.types[ty].kind == TY_REF { ty = p.types[ty].element; }
        let builtin = check_builtin_kind(p, original_callee.token);
        if !(check_array_member_builtin(builtin) && ty >= 0 && (p.types[ty].kind == TY_ARRAY || p.types[ty].kind == TY_SLICE)) {
            member_symbol = check_member_function(p, c, original_callee.token, ty);
            if member_symbol == -2 { return -1; }
        }
        let name = new_node(p, N_NAME, original_callee.token);
        p.nodes[name].scope = original_callee.scope; p.nodes[name].aux = 1; p.nodes[name].first = original_callee.first;
        p.nodes[receiver].next = n.first;
        p.nodes[node].first = receiver; p.nodes[node].left = name;
        n = p.nodes[node];
    }
    var callee = p.nodes[n.left];
    if callee.kind == N_NAME { check_parameter_default_name(p, c, n.left, member); }
    if callee.expansion_binding == -2 { diagnose(p, callee.token, "const for binding is not a callable function"); return -1; }
    if callee.kind == N_FUNCTION_VALUE { check_expression(p, c, n.left, -1); callee = p.nodes[n.left]; }
    if callee.kind != N_NAME && callee.kind != N_FUNCTION_VALUE {
        diagnose(p, n.token, "call target must name a function or function value"); return -1;
    }
    let builtin = check_builtin_kind(p, callee.token);
    if (n.flags & F_SYNTHETIC) != 0 && n.symbol >= 0 && (p.symbols[n.symbol].flags & S_BUILTIN) != 0 { return check_builtin(p, c, node, p.symbols[n.symbol].index); }
    if (n.flags & F_FORMAT_RAW) != 0 && builtin >= 0 && builtin <= 2 { return check_builtin(p, c, node, builtin); }
    if member && check_array_member_builtin(builtin) && n.first >= 0 {
        var receiver = check_single_expression(p, c, n.first);
        let optional = receiver >= 0 && p.types[receiver].kind == TY_REF && (p.types[receiver].flags & TF_OPTIONAL) != 0;
        while receiver >= 0 && p.types[receiver].kind == TY_REF { receiver = p.types[receiver].element; }
        if receiver >= 0 && (p.types[receiver].kind == TY_ARRAY || p.types[receiver].kind == TY_SLICE) {
            if optional { diagnose(p, callee.token, "optional receiver must be narrowed before a builtin member call"); return -1; }
            return check_builtin(p, c, node, builtin);
        }
    }
    var args = CheckList {}; var argument = n.first;
    while argument >= 0 {
        check_single_expression(p, c, argument); check_list_push(c, args, argument); argument = p.nodes[argument].next;
    }
    if n.third >= 0 {
        check_expression(p, c, n.third, -1); check_list_push(c, args, n.third);
    }
    var first = -1; var bound_function = false;
    if (n.flags & F_SYNTHETIC) != 0 && n.symbol >= 0 { first = n.symbol; bound_function = true; }
    else if member { first = member_symbol; }
    else if callee.kind == N_NAME { first = check_lookup_name(p, c, n.left, S_FUNCTION); }
    else { first = callee.symbol; }
    if first >= 0 && (p.symbols[first].flags & S_FUNCTION) == 0 {
        let ty = p.symbols[first].type_id;
        if ty >= 0 && p.types[ty].kind == TY_FN && p.types[ty].declaration >= 0 {
            let target = p.types[ty].declaration;
            if p.nodes[target].kind == N_FUNCTION || p.nodes[target].kind == N_FUNCTION_VALUE {
                check_implicit_function_parameter(p, c, target, args.count);
                first = p.nodes[target].symbol; bound_function = p.nodes[target].kind == N_FUNCTION_VALUE || p.nodes[target].origin >= 0;
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
    let choice = check_choose_call(p, c, callee, args, candidates, false);
    var best = choice.symbol; var best_bindings = choice.bindings; let ambiguous = choice.ambiguous; let best_hof = choice.hof;
    if best < 0 || choice.converting {
        let dispatched = check_try_dispatch(p, c, node, expected, args, candidates);
        if dispatched >= 0 || (p.nodes[node].flags & F_DISPATCH) != 0 { return dispatched; }
        if builtin >= 0 && (!member || first < 0) && (callee.aux <= 1 || callee.integer >= 0 && p.tokens[callee.integer].kind == T_COLONCOLON) {
            if member && (builtin == 21 || builtin == 22) { diagnose(p, callee.token, "a property is not callable"); return -1; }
            return check_builtin(p, c, node, builtin);
        }
        if best < 0 { diagnose(p, n.token, "no overload matches this call's argument types and count"); return -1; }
    }
    if ambiguous { diagnose(p, n.token, "ambiguous call: equally specific overloads match"); return -1; }
    let contextual = check_context_float_choice(p, c, node, callee, args, candidates, choice, expected);
    best = contextual.symbol; best_bindings = contextual.bindings;
    let original = p.symbols[best].node;
    // A block call produces its own temporary value. Only numeric literal
    // widths adapt here; a destination never turns its slice or owner tail
    // into a reference, nor supplies an empty array's element type.
    if p.nodes[original].kind == N_FUNCTION_VALUE && p.nodes[original].left < 0 && check_numeric(expected) {
        check_bind_generic(p, c, original, expected, best_bindings);
    }
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
            value = check_parameter_default(p, c, function_node, formal, n.token);
            if value >= 0 {
                if last < 0 { p.nodes[node].first = value; } else { p.nodes[last].next = value; }
                check_list_push(c, args, value);
            }
        }
        if value >= 0 {
            let saved_render_reference = c.render_reference;
            c.render_reference = (p.nodes[function_node].flags & F_FORMAT_RAW) != 0;
            if p.nodes[original].kind == N_FUNCTION_VALUE && p.nodes[formal].left < 0 { check_funval_copy(p, c, value, p.nodes[formal].type_id); }
            check_value(p, c, value, p.nodes[formal].type_id); check_slot_value(p, c, value, p.nodes[formal].type_id);
            c.render_reference = saved_render_reference;
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
    check_apply_call_effects(p, c, node, function_node, args);
    if (p.nodes[function_node].flags & F_DIVERGES) != 0 { p.nodes[node].flags |= F_DIVERGES; c.reachable = false; }
    return result;
}

fn check_flow_frame(c: Checker&, count: i64&, frame: i64, active: bool) {
    if frame < 0 { return; }
    for index in 0..count {
        // Lexical frames keep their scope filter. Only suspended callers
        // outside that chain need all frame variables.
        if c.flow_cursors[index].frame == frame { return; }
    }
    let cursor = CheckFlowCursor { frame: frame, index: c.scopes[frame].first_variable, active: active };
    if count == c.flow_cursors.len { c.flow_cursors.push(cursor); } else { c.flow_cursors[count] = cursor; }
    count += 1;
}
fn check_flow_advance(p: Program&, c: Checker&, cursor: i64) {
    var index = c.flow_cursors[cursor].index;
    while index >= 0 {
        let symbol: const Symbol& = p.symbols[c.variables[index].symbol];
        if c.flow_cursors[cursor].active {
            // Declaration-initialized immutable values keep stable
            // assignment facts. Delayed lets stay in every snapshot.
            var stable = false;
            if (symbol.flags & S_MUTABLE) == 0 && symbol.type_id >= 0 {
                stable = (symbol.flags & S_PARAMETER) != 0;
                if symbol.node >= 0 && p.nodes[symbol.node].kind == N_VARIABLE && p.nodes[symbol.node].right >= 0 { stable = true; }
                if stable {
                    let kind = p.types[symbol.type_id].kind;
                    stable = kind == TY_BOOL || kind == TY_INT || kind == TY_FLOAT ||
                        kind == TY_STRUCT || kind == TY_ENUM || kind == TY_ARRAY || kind == TY_TUPLE;
                }
            }
            if !stable { break; }
        } else if (symbol.flags & S_GLOBAL) != 0 || check_visible(c, symbol.scope, c.scope) { break; }
        index = c.variables[index].next_frame;
    }
    c.flow_cursors[cursor].index = index;
}
fn check_flow_save(p: Program&, c: Checker&, out: CheckSpan&, active_callers: bool = true) {
    out.first = c.flow_work.len; out.count = 0;
    var cursor_count = 0; var scope = c.scope;
    while scope >= 0 {
        let frame = c.scopes[scope].frame_root; check_flow_frame(c, cursor_count, frame, false);
        scope = c.scopes[frame].parent;
    }
    if active_callers {
        for index in 0..c.checking_count {
            let function_scope = p.nodes[c.checking[index]].scope;
            if function_scope >= 0 { check_flow_frame(c, cursor_count, c.scopes[function_scope].frame_root, true); }
        }
    }
    for cursor in 0..cursor_count { check_flow_advance(p, c, cursor); }
    // Each frame chain is in reverse declaration order. Merge the chains
    // and reverse once so flow joins retain their ordered symbol IDs.
    while true {
        var selected = -1; var greatest = -1;
        for cursor in 0..cursor_count {
            let index = c.flow_cursors[cursor].index;
            if index >= 0 && c.variables[index].symbol > greatest { selected = cursor; greatest = c.variables[index].symbol; }
        }
        if selected < 0 { break; }
        let variable = c.variables[c.flow_cursors[selected].index];
        c.flow_cursors[selected].index = variable.next_frame;
        check_flow_advance(p, c, selected);
        c.flow_work.push(CheckFlow { symbol: variable.symbol, assigned: variable.assigned,
            maybeassigned: variable.maybeassigned, narrowed: variable.narrowed });
        out.count += 1;
    }
    var left = out.first; var right = out.first + out.count - 1;
    while left < right {
        let saved = c.flow_work[left]; c.flow_work[left] = c.flow_work[right]; c.flow_work[right] = saved;
        left += 1; right -= 1;
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
    var left_index = left.first; var right_index = right.first;
    while left_index < left.first + left.count && right_index < right.first + right.count {
        let a = c.flow_work[left_index]; let b = c.flow_work[right_index];
        if a.symbol < b.symbol { left_index += 1; continue; }
        if b.symbol < a.symbol { right_index += 1; continue; }
        let vi = check_variable_index(c, a.symbol);
        if vi >= 0 {
            c.variables[vi].assigned = a.assigned && b.assigned;
            c.variables[vi].maybeassigned = a.maybeassigned || b.maybeassigned;
            c.variables[vi].narrowed = -1;
            if check_same_type(p, a.narrowed, b.narrowed) { c.variables[vi].narrowed = a.narrowed; }
        }
        left_index += 1; right_index += 1;
    }
}
fn check_join_control_exits(p: Program&, c: Checker&, target: i64, start: i64, fallthrough: bool) -> bool {
    var merged = CheckSpan {}; var reachable = fallthrough;
    if fallthrough { check_flow_save(p, c, merged); }
    for index in start..c.exit_work.len {
        let exit = c.exit_work[index]; if exit.target != target || exit.backedge { continue; }
        if !reachable { merged = exit.flow; reachable = true; }
        else { var next = exit.flow; check_flow_join(p, c, merged, next, true, true); check_flow_save(p, c, merged); }
    }
    if reachable { check_flow_restore(c, merged); }
    return reachable;
}
recursive fn check_branch_readonly(p: Program&, c: Checker&, node: i64) -> bool {
    if node < 0 { return false; }
    let n = p.nodes[node];
    if n.kind == N_LOOP || n.kind == N_BLOCK && (n.flags & F_EARLY) != 0 {
        var values = CheckList {}; check_collect_break_values(p, c, node, node, values, true);
        if n.kind == N_BLOCK && (n.flags & F_TAIL) != 0 && (p.nodes[n.last].flags & F_DIVERGES) == 0 { check_list_push(c, values, n.last); }
        for index in 0..values.count { if check_branch_readonly(p, c, check_list_at(c, values, index)) { return true; } }
        return false;
    }
    if (n.flags & F_DIVERGES) != 0 { return false; }
    if n.kind == N_BLOCK && (n.flags & F_TAIL) != 0 { return check_branch_readonly(p, c, n.last); }
    if n.kind == N_IF { return check_branch_readonly(p, c, n.right) || check_branch_readonly(p, c, n.third); }
    if n.kind == N_MATCH {
        var arm = n.first;
        while arm >= 0 { if check_branch_readonly(p, c, p.nodes[arm].right) { return true; } arm = p.nodes[arm].next; }
        return false;
    }
    return check_readonly(p, c, node);
}
fn check_join_type(p: Program&, c: Checker&, left_node: i64, left: i64, right_node: i64, right: i64, token: i64, adapt: bool = true) -> i64 {
    if left < 0 { return right; }
    if right < 0 { return left; }
    var left_value = left; var right_value = right;
    if p.types[left_value].kind == TY_REF && (p.types[left_value].flags & TF_OPTIONAL) == 0 { left_value = p.types[left_value].element; }
    if p.types[right_value].kind == TY_REF && (p.types[right_value].flags & TF_OPTIONAL) == 0 { right_value = p.types[right_value].element; }
    let a = p.types[left_value]; let b = p.types[right_value];
    if a.kind == TY_INT && b.kind == TY_INT && (a.index_type >= 0 || b.index_type >= 0) {
        var common = -1;
        if a.index_type >= 0 && b.index_type >= 0 && a.pool == b.pool {
            var widest = left_value; if b.count > a.count { widest = right_value; }
            var joined = p.types[widest]; joined.flags |= (a.flags | b.flags) & F_BOUND_TYPE;
            common = add_type(p, joined);
        } else {
            let l = check_numeric_value_type(p, left_value); let r = check_numeric_value_type(p, right_value);
            if left_node >= 0 && check_conversion(p, c, left_node, left, r) >= 0 { common = r; }
            else if right_node >= 0 && check_conversion(p, c, right_node, right, l) >= 0 { common = l; }
            else { diagnose(p, token, "control-flow branches produce incompatible integer types"); return -1; }
        }
        if adapt && left_node >= 0 { check_expect(p, c, left_node, left, common); }
        if adapt && right_node >= 0 { check_expect(p, c, right_node, right, common); }
        return common;
    }
    if (a.kind == TY_SLICE || b.kind == TY_SLICE) && (a.kind == TY_ARRAY || a.kind == TY_SLICE) && (b.kind == TY_ARRAY || b.kind == TY_SLICE) && check_same_type(p, a.element, b.element) {
        var flags = (a.flags | b.flags) & TF_CONST;
        if check_branch_readonly(p, c, left_node) || check_branch_readonly(p, c, right_node) { flags |= TF_CONST; }
        let view = check_type(p, TY_SLICE, a.element, -1, -1, flags);
        if (left_node < 0 || check_conversion(p, c, left_node, left, view) >= 0) && (right_node < 0 || check_conversion(p, c, right_node, right, view) >= 0) {
            if adapt && left_node >= 0 { check_expect(p, c, left_node, left, view); }
            if adapt && right_node >= 0 { check_expect(p, c, right_node, right, view); }
            return view;
        }
    }
    if check_same_type(p, left, right) { return left; }
    if p.types[left].kind == TY_ARRAY && p.types[right].kind == TY_ARRAY && (p.types[left].element < 0) != (p.types[right].element < 0) {
        diagnose(p, token, "an empty array branch cannot infer its element type from another branch"); return -1;
    }
    if right_node >= 0 && check_join_literal(p, c, right_node) && !check_join_literal(p, c, left_node) && check_conversion(p, c, right_node, right, left) >= 0 {
        if adapt { check_expect(p, c, right_node, right, left); } return left;
    }
    if left_node >= 0 && check_conversion(p, c, left_node, left, right) >= 0 {
        if adapt { check_expect(p, c, left_node, left, right); } return right;
    }
    if right_node >= 0 && check_conversion(p, c, right_node, right, left) >= 0 {
        if adapt { check_expect(p, c, right_node, right, left); } return left;
    }
    diagnose(p, token, "control-flow branches produce incompatible types"); return -1;
}
recursive fn check_predeclare(p: Program&, c: Checker&, first: i64) {
    var node = first;
    while node >= 0 {
        let n = p.nodes[node];
        if n.kind == N_NAMESPACE {
            let previous = check_lookup_scope(p, c, n.token, c.scope);
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
        else if n.kind == N_FUNCTION || n.kind == N_STRUCT || n.kind == N_ENUM || n.kind == N_ALIAS {
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
recursive fn check_inferred_result(p: Program&, c: Checker&, node: i64, target: i64) -> i64 {
    if node < 0 { return TYPE_VOID; }
    let n = p.nodes[node]; var ty = check_read_value_type(p, c, node, n.type_id);
    if ty < 0 || ty == TYPE_VOID { return ty; }
    if n.kind == N_BLOCK && (n.flags & F_EARLY) == 0 && (n.flags & F_TAIL) != 0 && n.last >= 0 {
        ty = check_inferred_result(p, c, n.last, target); p.nodes[node].type_id = ty; check_copy_roots(c, node, n.last); return ty;
    }
    if n.kind == N_IF && n.third >= 0 {
        let left = check_inferred_result(p, c, n.right, target); let right = check_inferred_result(p, c, n.third, target);
        ty = check_join_type(p, c, n.right, left, n.third, right, n.token); p.nodes[node].type_id = ty;
        check_copy_roots(c, node, n.right); check_copy_roots(c, node, n.third); return ty;
    }
    if n.kind == N_MATCH {
        var arm = n.first; var result = -1; var previous = -1;
        while arm >= 0 {
            let body = p.nodes[arm].right; let branch = check_inferred_result(p, c, body, target);
            result = check_join_type(p, c, previous, result, body, branch, n.token); previous = body;
            check_copy_roots(c, node, body); arm = p.nodes[arm].next;
        }
        p.nodes[node].type_id = result; return result;
    }
    // Explicit address-taking is a reference result even for fixed-size
    // pointees. An implicit scalar read inserted before inference is undone.
    if n.kind == N_UNARY && n.integer == T_MUL && (n.flags & F_SYNTHETIC) != 0 && n.left >= 0 {
        var address = p.nodes[n.left];
        if address.kind == N_UNARY && address.integer == T_BITAND && (address.flags & F_SYNTHETIC) == 0 {
            address.next = n.next; address.flags |= n.flags & F_TAIL; p.nodes[node] = address; return address.type_id;
        }
    }
    if target >= 0 && p.nodes[target].kind == N_FUNCTION && p.types[ty].kind != TY_REF && check_size_class(p, ty, 0) > 0 && check_addressable(p, node) {
        let root = check_place_root(p, node); var borrowed = false;
        if root >= 0 {
            let symbol = p.symbols[root];
            borrowed = n.kind != N_NAME || symbol.owner != target || (symbol.flags & S_GLOBAL) != 0;
            if symbol.type_id >= 0 && p.types[symbol.type_id].kind == TY_REF { borrowed = true; }
        }
        if borrowed {
            var flags = 0; if check_readonly(p, c, node) { flags |= TF_CONST; }
            let reference = check_type(p, TY_REF, ty, 0, -1, flags);
            check_require_referenceable(p, c, node);
            check_add_root(c, node, root, check_reference_kind(p, node)); check_wrap_unary(p, node, T_BITAND, reference); return reference;
        }
    }
    return ty;
}
recursive fn check_block(p: Program&, c: Checker&, node: i64, expected: i64) -> i64 {
    let n = p.nodes[node]; let saved = check_enter(c, c.function_node); let exit_start = c.exit_work.len;
    p.nodes[node].scope = c.scope;
    if expected >= 0 && (p.types[expected].kind == TY_REF || p.types[expected].kind == TY_SLICE) { p.nodes[node].flags |= F_REFERENCE_CONTEXT; }
    var early = false;
    if (n.flags & (F_EARLY | F_NONLOCAL)) != 0 {
        check_push_loop(c, CheckLoop { node: node, scope: c.scope, function_node: c.function_node, expected: expected, returning: c.returning }); early = true;
    }
    check_predeclare(p, c, n.first);
    var child = n.first; var result = TYPE_VOID; var previous_child = -1;
    while child >= 0 {
        if !c.reachable {
            if previous_child < 0 { p.nodes[node].first = -1; } else { p.nodes[previous_child].next = -1; }
            p.nodes[node].last = previous_child; p.nodes[node].flags &= ~F_TAIL; break;
        }
        let item = p.nodes[child];
        if item.kind == N_VARIABLE {
            let previous = c.scope; check_enter(c, c.function_node);
            c.scopes[c.scope].depth = c.scopes[previous].depth;
        }
        if (item.flags & F_TAIL) != 0 {
            let returning = c.returning;
            if c.function_node >= 0 && p.nodes[c.function_node].right == node { c.returning = true; }
            var tail_expected = expected;
            if c.function_node >= 0 && p.nodes[c.function_node].right == node && expected >= 0 &&
               (p.types[expected].kind == TY_REF || p.types[expected].kind == TY_SLICE) &&
               (item.kind == N_NAME || item.kind == N_CALL || item.kind == N_SLICE || item.kind == N_MEMBER || item.kind == N_INDEX) {
                check_expression(p, c, child, -1);
                if check_readonly(p, c, child) {
                    tail_expected = check_const_type(p, expected); c.result_type = tail_expected;
                    p.types[p.nodes[c.function_node].type_id].element = tail_expected;
                }
            }
            let keep_tuple = c.tuple_context || tail_expected < 0 && c.function_node >= 0 && check_tail_contains(p, p.nodes[c.function_node].right, node);
            result = check_value(p, c, child, tail_expected, keep_tuple);
            if tail_expected < 0 { result = check_index_value(p, child, result); }
            if tail_expected < 0 && c.function_node >= 0 && p.nodes[c.function_node].right == node { result = check_inferred_result(p, c, child, c.function_node); }
            check_copy_roots(c, node, child); c.returning = returning;
        } else { check_statement(p, c, child); }
        previous_child = child; child = item.next;
    }
    if (p.nodes[node].flags & F_TAIL) == 0 && expected >= 0 && expected != TYPE_VOID && c.reachable {
        diagnose(p, n.token, "value-producing block must end with an expression");
    }
    if early {
        let li = c.loop_count - 1; let loop_state = c.loop_stack[li]; let body_reachable = c.reachable;
        if loop_state.breaks {
            var tail = -1; if body_reachable && (p.nodes[node].flags & F_TAIL) != 0 { tail = p.nodes[node].last; }
            var values = CheckList {}; check_collect_break_values(p, c, node, node, values);
            result = check_join_break_values(p, c, node, values, tail, body_reachable, result, expected);
            c.reachable = true;
        }
        c.loop_count -= 1;
        c.reachable = check_join_control_exits(p, c, node, exit_start, body_reachable);
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

fn check_operation_same(p: Program&, a: i64, b: i64) -> bool {
    if a < 0 || b < 0 { return false; }
    if check_same_type(p, a, b) { return true; }
    let at = p.types[a]; let bt = p.types[b];
    return at.kind == bt.kind && at.element == bt.element && at.count == bt.count && at.array_kind == bt.array_kind && at.storage == bt.storage && at.length_storage == bt.length_storage && at.pool == bt.pool && at.index_type == bt.index_type && at.declaration == bt.declaration && (at.flags & ~TF_CONST) == (bt.flags & ~TF_CONST);
}
fn check_operation_parameter(p: Program&, c: Checker&, node: i64, type_id: i64) -> i64 {
    if p.types[type_id].kind == TY_REF { return type_id; }
    if check_size_class(p, type_id, 0) > 0 && check_addressable(p, node) {
        var flags = 0; if check_readonly(p, c, node) { flags |= TF_CONST; }
        return check_type(p, TY_REF, type_id, 0, -1, flags);
    }
    return type_id;
}
recursive fn check_lower_operation(p: Program&, c: Checker&, node: i64, left_type: i64, right_type: i64, result_type: i64, op: i64) -> i64 {
    let original = p.nodes[node]; var left_formal = check_operation_parameter(p, c, original.left, left_type); var right_formal = -1;
    if right_type >= 0 { right_formal = check_operation_parameter(p, c, original.right, right_type); }
    if op == T_EQ && right_type >= 0 {
        let left = operation_value_type(p, left_type); let right = operation_value_type(p, right_type);
        let a = p.types[left]; let b = p.types[right];
        if (a.kind == TY_ARRAY || a.kind == TY_SLICE) && (b.kind == TY_ARRAY || b.kind == TY_SLICE) && !check_same_type(p, left, right) {
            var left_flags = a.flags & TF_CONST; var right_flags = b.flags & TF_CONST;
            if check_readonly(p, c, original.left) { left_flags |= TF_CONST; }
            if check_readonly(p, c, original.right) { right_flags |= TF_CONST; }
            left_formal = check_type(p, TY_SLICE, a.element, -1, -1, left_flags);
            right_formal = check_type(p, TY_SLICE, b.element, -1, -1, right_flags);
        }
    }
    var function_node = -1; let count = p.nodes.len;
    for candidate in 0..count {
        let n = p.nodes[candidate];
        if n.kind != N_FUNCTION || (n.flags & F_SYNTHETIC) == 0 || n.aux != op || n.first < 0 { continue; }
        let first = n.first; let second = p.nodes[first].next;
        if !check_same_type(p, p.nodes[first].type_id, left_formal) { continue; }
        if right_formal < 0 && second < 0 || right_formal >= 0 && second >= 0 && check_same_type(p, p.nodes[second].type_id, right_formal) { function_node = candidate; break; }
    }
    if function_node < 0 {
        function_node = operation_function(p, left_formal, right_formal, result_type, op, original.token);
        p.nodes[function_node].scope = 0;
        let saved_function = c.function_node; c.function_node = -1; check_declare(p, c, function_node, 0); c.function_node = saved_function;
    }
    let callee = operation_ident(p, p.nodes[function_node].token); var last = original.left;
    p.nodes[original.left].next = -1;
    if right_type >= 0 { p.nodes[original.left].next = original.right; p.nodes[original.right].next = -1; last = original.right; }
    p.nodes[node] = Node { kind: N_CALL, token: original.token, first: original.left, last: last, next: original.next, left: callee, flags: original.flags & F_TAIL, scope: original.scope };
    let comparison = c.literal_comparison; c.literal_comparison = op == T_EQ;
    let result = check_call(p, c, node, -1); p.nodes[node].type_id = result;
    c.literal_comparison = comparison;
    if original.integer == T_NEQ { check_wrap_unary(p, node, T_NOT, TYPE_BOOL); }
    return result;
}
recursive fn check_aggregate_operation(p: Program&, c: Checker&, node: i64, left: i64, right: i64) -> i64 {
    let op = p.nodes[node].integer;
    if p.types[left].kind == TY_REF && (p.types[left].flags & TF_OPTIONAL) != 0 || p.types[right].kind == TY_REF && (p.types[right].flags & TF_OPTIONAL) != 0 { return -2; }
    let lt = operation_value_type(p, left); let rt = operation_value_type(p, right);
    let a = p.types[lt]; let b = p.types[rt];
    if op == T_EQ || op == T_NEQ {
        var comparable = false;
        if (a.kind == TY_ARRAY || a.kind == TY_SLICE) && (b.kind == TY_ARRAY || b.kind == TY_SLICE) && a.element >= 0 && b.element >= 0 { comparable = check_operation_same(p, a.element, b.element); }
        else if a.kind == b.kind && (a.kind == TY_STRUCT || a.kind == TY_ENUM) { comparable = a.declaration == b.declaration; }
        if comparable { return check_lower_operation(p, c, node, left, right, lt, T_EQ); }
    }
    if op == T_PLUS || op == T_MINUS || op == T_MUL || op == T_DIV || op == T_MOD {
        if (a.kind == TY_ARRAY || a.kind == TY_STRUCT) && check_operation_same(p, lt, rt) && operation_numeric_class(p, lt) > 0 { return check_lower_operation(p, c, node, left, right, lt, op); }
        if op == T_MUL || op == T_DIV {
            var aggregate = lt; var scalar = p.nodes[node].right;
            if check_numeric(lt) { aggregate = rt; scalar = p.nodes[node].left; }
            if operation_numeric_class(p, aggregate) > 0 && (p.types[aggregate].kind == TY_ARRAY || p.types[aggregate].kind == TY_STRUCT) && (check_numeric(lt) || check_numeric(rt)) {
                let leaf = operation_uniform_leaf(p, aggregate);
                if leaf >= 0 && check_conversion(p, c, scalar, p.nodes[scalar].type_id, leaf) >= 0 {
                    check_value(p, c, scalar, leaf);
                    if check_numeric(lt) { return check_lower_operation(p, c, node, leaf, right, aggregate, op); }
                    return check_lower_operation(p, c, node, left, leaf, aggregate, op);
                }
            }
        }
    }
    return -2;
}

recursive fn check_identity_operand(p: Program&, c: Checker&, node: i64) -> i64 {
    let ty = check_expression(p, c, node, -1);
    if ty < 0 || check_bottom(p, node) { return ty; }
    let kind = p.types[ty].kind;
    if kind == TY_REF { return ty; }
    if kind == TY_SLICE || kind == TY_FN || !check_addressable(p, node) {
        diagnose(p, p.nodes[node].token, "reference identity requires a reference, null, or addressable storage"); return ty;
    }
    var storage = check_storage_type(p, node); if storage < 0 { storage = ty; }
    var flags = 0;
    if check_readonly(p, c, node, true) || p.types[storage].storage == 1 { flags |= TF_CONST; }
    if (p.types[storage].flags & TF_CONST) != 0 {
        var plain = p.types[storage]; plain.flags &= ~TF_CONST; storage = add_type(p, plain);
    }
    let reference = check_type(p, TY_REF, storage, 0, -1, flags);
    let root = check_place_root(p, node); let root_kind = check_reference_kind(p, node);
    // Address comparison cannot write through the implicit reference.
    check_require_referenceable(p, c, node);
    check_wrap_unary(p, node, T_BITAND, reference); check_add_root(c, node, root, root_kind);
    return reference;
}

recursive fn check_expression(p: Program&, c: Checker&, node: i64, expected: i64) -> i64 {
    if node < 0 { return TYPE_VOID; }
    let n = p.nodes[node];
    if n.kind == N_NAME && n.symbol >= 0 && !check_global_use(p, c, n.symbol, n.token) { return -1; }
    if (n.flags & F_CHECKED) != 0 && n.type_id >= 0 {
        if n.kind == N_CALL && expected > TYPE_VOID && n.symbol >= 0 && p.symbols[n.symbol].node >= 0 &&
           p.nodes[p.symbols[n.symbol].node].kind == N_FUNCTION_VALUE && check_conversion(p, c, node, n.type_id, expected) < 0 {
            return check_call(p, c, node, expected);
        }
        if (n.kind == N_ARRAY || n.kind == N_FILL) && expected >= 0 { return check_array(p, c, node, expected); }
        if check_addressable(p, node) || n.kind == N_CALL { let loaded = check_plain_value_type(p, n.type_id); p.nodes[node].type_id = loaded; return loaded; }
        return n.type_id;
    }
    let entry_reachable = c.reachable;
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
        check_parameter_default_name(p, c, node, false);
        if n.expansion_binding == -2 { diagnose(p, n.token, "const for binding is not a value or callable function"); }
        else if p.tokens[n.token].kind == T_SELF { diagnose(p, n.token, "self requires a relative reference field initializer"); }
        else {
            let symbol = check_lookup_name(p, c, node);
            if symbol < 0 { diagnose(p, n.token, "unknown name"); }
            else {
                p.nodes[node].symbol = symbol;
                let s = p.symbols[symbol];
                if (s.flags & S_TYPE) != 0 {
                    if s.type_id >= 0 && p.types[s.type_id].kind == TY_FN { result = s.type_id; }
                    else { diagnose(p, n.token, "type name is not a runtime value"); }
                }
                else if (s.flags & S_FUNCTION) != 0 {
                    let declaration = s.node;
                    if declaration >= 0 { check_prepare_function(p, c, declaration); result = p.nodes[declaration].type_id; }
                } else {
                    if !check_global_use(p, c, symbol, n.token) { return -1; }
                    if (s.flags & S_GLOBAL) != 0 && s.node >= 0 && (p.nodes[s.node].flags & F_CHECKED) == 0 { check_variable(p, c, s.node); }
                    result = p.symbols[symbol].type_id;
                    let vi = check_variable_index(c, symbol); check_environment_note(p, c, symbol);
                    if vi >= 0 && c.variables[vi].narrowed >= 0 { result = c.variables[vi].narrowed; }
                    if vi >= 0 && !c.variables[vi].assigned { diagnose(p, n.token, "value is read before it is definitely assigned"); }
                    check_capture(p, c, symbol); check_copy_roots(c, node, -symbol - 10);
                }
            }
        }
    } else if n.kind == N_UNARY {
        if n.integer == T_BITAND {
            let ty = check_single_expression(p, c, n.left);
            if !check_addressable(p, n.left) && !(ty >= 0 && p.types[ty].kind == TY_REF) { diagnose(p, n.token, "reference requires addressable storage"); }
            check_require_referenceable(p, c, n.left);
            var flags = 0; if check_borrow_readonly(p, c, n.left) { flags |= TF_CONST; }
            if ty >= 0 && p.types[ty].kind == TY_REF {
                result = check_read_value_type(p, c, n.left, ty); check_copy_roots(c, node, n.left);
            } else {
                if ty >= 0 && p.types[ty].storage == 1 { flags |= TF_CONST; }
                result = check_type(p, TY_REF, ty, 0, -1, flags);
                if (flags & TF_CONST) == 0 { check_named_writable(p, c, check_place_root(p, n.left), n.token); }
                check_add_root(c, node, check_place_root(p, n.left), check_reference_kind(p, n.left));
            }
        } else if n.integer == T_MUL {
            let ty = check_expression(p, c, n.left, -1);
            if ty < 0 || p.types[ty].kind != TY_REF { diagnose(p, n.token, "dereference requires a reference"); }
            else { result = p.types[ty].element; check_copy_roots(c, node, n.left); }
        } else if n.integer == T_NOT {
            check_condition(p, c, n.left); result = TYPE_BOOL;
        } else {
            let ty = check_value(p, c, n.left, -1);
            if ty >= 0 && n.integer == T_MINUS && (p.types[ty].kind == TY_STRUCT || p.types[ty].kind == TY_ARRAY) && operation_numeric_class(p, ty) > 0 && !operation_unsigned_leaf(p, ty) {
                result = check_lower_operation(p, c, node, ty, -1, ty, T_MINUS); p.nodes[node].type_id = result; return result;
            }
            if !check_numeric(ty) { diagnose(p, n.token, "numeric unary operator requires a number"); }
            if n.integer == T_BITNOT && !check_integer(ty) { diagnose(p, n.token, "bitwise complement requires an integer"); }
            if n.integer != T_MINUS && n.integer != T_BITNOT { diagnose(p, n.token, "invalid unary operator"); }
            result = ty;
            if n.integer == T_MINUS && check_unsigned(ty) {
                let constant = check_constant(p, c, n.left, 0);
                if !constant.valid || !check_integer_constants(p, c, n.left) { diagnose(p, n.token, "cannot negate an unsigned value: convert it with as first"); }
                else if constant.type_id == TYPE_U64 && constant.value < 0 && constant.value != -9223372036854775808 {
                    diagnose(p, n.token, "negated constant is too large for i64");
                } else {
                    check_rely_named(p, c, n.left);
                    p.nodes[node].kind = N_INTEGER; p.nodes[node].left = -1;
                    p.nodes[node].integer = constant.value;
                    if constant.value != -9223372036854775808 { p.nodes[node].integer = -constant.value; }
                    result = TYPE_I64;
                }
            }
        }
    } else if n.kind == N_BINARY {
        let op = n.integer;
        if op == T_ANDAND || op == T_OROR {
            check_condition(p, c, n.left);
            var before = CheckSpan {}; check_flow_save(p, c, before, true);
            var globals = CheckSpan {}; check_logical_globals(p, c, globals);
            let reachable = c.reachable; check_narrow_condition(p, c, n.left, op == T_ANDAND);
            var narrowed = CheckList {}; check_logical_capture(c, narrowed, before); check_logical_capture(c, narrowed, globals);
            check_condition(p, c, n.right); check_logical_record(c, node, narrowed);
            var after = CheckSpan {}; check_flow_save(p, c, after, true);
            check_flow_join(p, c, before, after, reachable, c.reachable); check_flow_restore(c, globals); check_logical_apply(c, node); c.reachable = reachable;
            result = TYPE_BOOL;
        } else {
            var lt = -1; var rt = -1;
            let identity = op == T_DOTEQ || op == T_DOTNEQ;
            let null_comparison = (op == T_EQ || op == T_NEQ) && (p.nodes[n.left].kind == N_NULL || p.nodes[n.right].kind == N_NULL);
            if identity {
                lt = check_identity_operand(p, c, n.left); rt = check_identity_operand(p, c, n.right);
                result = TYPE_BOOL; p.nodes[node].aux = -1;
                if lt >= 0 && rt >= 0 && !check_bottom(p, n.left) && !check_bottom(p, n.right) {
                    if p.types[lt].kind != TY_REF || p.types[rt].kind != TY_REF {
                        diagnose(p, n.token, "reference identity compares addresses of references or storage");
                    } else if p.nodes[n.left].kind != N_NULL && p.nodes[n.right].kind != N_NULL &&
                              !check_same_type(p, p.types[lt].element, p.types[rt].element) {
                        diagnose(p, n.token, "reference identity requires the same pointee type");
                    }
                }
            } else if null_comparison {
                lt = check_expression(p, c, n.left, -1); rt = check_expression(p, c, n.right, -1);
            } else { lt = check_value(p, c, n.left, -1); rt = check_value(p, c, n.right, -1); }
            if !identity && lt >= 0 && rt >= 0 {
                let comparison = op == T_EQ || op == T_NEQ || op == T_LT || op == T_LTEQ || op == T_GT || op == T_GTEQ || op == T_DOTEQ || op == T_DOTNEQ;
                if check_numeric(lt) && check_numeric(rt) {
                    if !check_same_type(p, lt, rt) && op != T_SHL && op != T_SHR {
                        let lr = check_conversion(p, c, n.left, lt, rt); let rl = check_conversion(p, c, n.right, rt, lt);
                        var lc = false; var rc = false;
                        if check_integer(lt) && check_integer(rt) {
                            lc = check_integer_constants(p, c, n.left) || check_flex_integer(p, c, n.left).flexible;
                            rc = check_integer_constants(p, c, n.right) || check_flex_integer(p, c, n.right).flexible;
                        }
                        if lc && !rc {
                            if lr < 0 { diagnose(p, n.token, "integer constants do not all fit the other operand's type"); }
                            else { check_expect(p, c, n.left, lt, rt); lt = rt; }
                        } else if rc && !lc {
                            if rl < 0 { diagnose(p, n.token, "integer constants do not all fit the other operand's type"); }
                            else { check_expect(p, c, n.right, rt, lt); rt = lt; }
                        } else if lr >= 0 && (rl < 0 || lr <= rl) { check_expect(p, c, n.left, lt, rt); lt = rt; }
                        else if rl >= 0 { check_expect(p, c, n.right, rt, lt); rt = lt; }
                        else if !identity && comparison && check_integer(lt) && check_integer(rt) &&
                            (check_numeric_value_type(p, lt) == TYPE_U64 && !check_unsigned(check_numeric_value_type(p, rt)) ||
                             check_numeric_value_type(p, rt) == TYPE_U64 && !check_unsigned(check_numeric_value_type(p, lt))) {
                            var signed = n.left;
                            if check_numeric_value_type(p, lt) == TYPE_U64 { signed = n.right; }
                            let proof = check_nonnegative_get(c, signed);
                            if proof < -1 { diagnose(p, n.token, "comparison with u64 requires the signed side to be known non-negative"); }
                            else { check_nonnegative_rely(p, c, proof, n.token); lt = TYPE_U64; rt = TYPE_U64; }
                        } else { diagnose(p, n.token, "numeric operands require compatible types"); }
                    }
                    if (op == T_BITAND || op == T_BITOR || op == T_XOR || op == T_SHL || op == T_SHR) &&
                       (!check_integer(lt) || !check_integer(rt)) { diagnose(p, n.token, "integer operator requires integer operands"); }
                    p.nodes[node].aux = lt;
                    result = lt;
                } else {
                    var aggregate = -2;
                    if !identity && !null_comparison { aggregate = check_aggregate_operation(p, c, node, lt, rt); }
                    if aggregate != -2 { result = aggregate; }
                    else if comparison && (check_same_type(p, lt, rt) || identity && p.types[lt].kind == TY_REF && p.types[rt].kind == TY_REF && check_same_type(p, p.types[lt].element, p.types[rt].element) || p.nodes[n.left].kind == N_NULL || p.nodes[n.right].kind == N_NULL) {
                        if (op == T_LT || op == T_LTEQ || op == T_GT || op == T_GTEQ) && lt != TYPE_BOOL { diagnose(p, n.token, "ordered comparison requires numeric operands"); }
                    } else { diagnose(p, n.token, "operator does not accept these operand types"); }
                }
                if comparison { result = TYPE_BOOL; }
            }
        }
    } else if n.kind == N_CALL { result = check_call(p, c, node, expected); }
    else if n.kind == N_MEMBER {
        var enum_type = -1;
        if p.nodes[n.left].kind == N_TYPE_NAME {
            // Name<T>.Variant names its enum type with type arguments.
            enum_type = check_resolve_type(p, c, n.left);
            if enum_type >= 0 && p.types[enum_type].kind != TY_ENUM { diagnose(p, n.token, "only an enum type names a variant constant"); return -1; }
            if enum_type < 0 { return -1; }
        } else if p.nodes[n.left].kind == N_NAME {
            let symbol = check_lookup_name(p, c, n.left);
            if symbol >= 0 && (p.symbols[symbol].flags & S_TYPE) != 0 {
                if p.symbols[symbol].node >= 0 && p.nodes[p.symbols[symbol].node].kind == N_TYPE_PARAM { diagnose(p, n.token, "type parameter names a type, not a runtime enum value"); return -1; }
                enum_type = p.symbols[symbol].type_id;
            }
        }
        if enum_type >= 0 && p.types[enum_type].kind == TY_ENUM {
            check_layout_nominal(p, c, enum_type);
            var variant = p.types[enum_type].first;
            while variant >= 0 {
                if same_name(p, p.nodes[variant].token, n.token) {
                    if p.nodes[variant].first >= 0 { diagnose(p, n.token, "enum variant payload requires a constructor"); }
                    p.nodes[node].kind = N_RECORD; p.nodes[node].left = -1; p.nodes[node].symbol = variant;
                    result = enum_type;
                    if check_enum_fixed_reason(p, enum_type) != 0 {
                        var variable = p.types[enum_type]; variable.flags |= F_VARIABLE_MODE;
                        result = add_type(p, variable); check_layout_nominal(p, c, result);
                    }
                    break;
                }
                variant = p.nodes[variant].next;
            }
            if result < 0 { diagnose(p, n.token, "unknown enum variant"); }
        } else {
            var ty = check_single_expression(p, c, n.left);
            if ty >= 0 && p.types[ty].kind == TY_REF {
                let element = p.types[ty].element; check_wrap_unary(p, n.left, T_MUL, element); ty = element;
            }
            if n.aux >= 0 && !check_operation_same(p, ty, n.aux) { diagnose(p, n.token, "const for field accessor belongs to a different aggregate type"); }
            let builtin = check_builtin_kind(p, n.token);
            if ty >= 0 && (p.types[ty].kind == TY_ARRAY || p.types[ty].kind == TY_SLICE) && (builtin == 21 || builtin == 22) {
                let name = new_node(p, N_NAME, n.token);
                p.nodes[node].kind = N_CALL; p.nodes[node].first = n.left; p.nodes[node].last = n.left;
                p.nodes[node].left = name; p.nodes[node].right = -1; p.nodes[node].flags |= F_PROPERTY;
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
        var ty = check_single_expression(p, c, n.left);
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
                let index_type = check_index_value(p, n.right, -1);
                if index_type >= 0 && (p.types[index_type].flags & F_BOUND_TYPE) == 0 && p.types[index_type].pool == check_place_root(p, n.left) { p.nodes[node].flags |= F_BOUNDS_PROVEN; }
                if start.valid && array.count >= 0 && array.array_kind == A_FIXED {
                    if start.value >= array.count { diagnose(p, n.token, "constant index is outside the fixed array"); }
                    else if start.value >= 0 { p.nodes[node].flags |= F_BOUNDS_PROVEN; }
                }
            } else {
                var flags = array.flags & TF_CONST; if check_readonly(p, c, n.left) { flags |= TF_CONST; }
                result = check_type(p, TY_SLICE, array.element, -1, -1, flags);
                if (n.flags & (F_FROM_END | F_TO_END)) == 0 && start.valid && end.valid && start.value > end.value { diagnose(p, n.token, "slice start exceeds its end"); }
                if end.valid && end.value < 0 || end.valid && array.array_kind == A_FIXED && array.count >= 0 && end.value > array.count {
                    diagnose(p, n.token, "slice bound is outside the fixed array");
                }
                check_add_root(c, node, check_place_root(p, n.left), 1);
            }
            check_copy_roots(c, node, n.left);
        }
    } else if n.kind == N_ARRAY || n.kind == N_FILL { result = check_array(p, c, node, expected); }
    else if n.kind == N_RECORD { result = check_record(p, c, node, expected); }
    else if n.kind == N_CAST {
        let destination = check_resolve_type(p, c, n.right); var source = -1;
        if (n.flags & (F_SYNTHETIC | F_UNSIGNED)) == (F_SYNTHETIC | F_UNSIGNED) && destination >= 0 && p.types[destination].kind == TY_REF {
            source = check_expression(p, c, n.left, -1);
        } else { source = check_value(p, c, n.left, -1); }
        if source >= 0 && destination >= 0 {
            let sk = p.types[source].kind; let dk = p.types[destination].kind;
            if p.types[destination].index_type >= 0 && p.types[destination].pool >= 0 {
                let owner = p.symbols[p.types[destination].pool];
                let vi = check_variable_index(c, p.types[destination].pool);
                if c.initializing_globals && (owner.node < 0 || (p.nodes[owner.node].flags & F_CHECKED) == 0 || vi >= 0 && !c.variables[vi].assigned) {
                    diagnose(p, n.token, "index conversion reads its named array before global initialization");
                }
            }
            if p.types[destination].index_type >= 0 && (n.flags & F_UNSIGNED) != 0 { diagnose(p, n.token, "an index or bound cast always checks its named array; as! is not allowed"); }
            if p.types[destination].index_type >= 0 && !check_integer(check_numeric_value_type(p, source)) { diagnose(p, n.token, "only an integer converts to an index or bound type"); }
            else if check_numeric(check_numeric_value_type(p, source)) && check_numeric(check_numeric_value_type(p, destination)) || source == TYPE_BOOL && check_integer(check_numeric_value_type(p, destination)) ||
               check_integer(check_numeric_value_type(p, source)) && destination == TYPE_BOOL || check_conversion(p, c, n.left, source, destination) >= 0 {
                result = destination;
            } else if (n.flags & F_UNSIGNED) != 0 && sk == TY_REF && dk == TY_REF { result = destination; }
            else { diagnose(p, n.token, "explicit cast is not defined for these types"); }
            check_copy_roots(c, node, n.left);
        }
    } else if n.kind == N_IF { result = check_if(p, c, node, expected); }
    else if n.kind == N_BLOCK { result = check_block(p, c, node, expected); }
    else if n.kind == N_MATCH { result = check_match(p, c, node, expected); }
    else if n.kind == N_LOOP || n.kind == N_FOR || n.kind == N_WHILE {
        let returning = c.returning;
        if n.kind != N_LOOP { c.returning = false; }
        result = check_loop(p, c, node, expected); c.returning = returning;
    }
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
        let left = check_value(p, c, n.left, -1); let right = check_value(p, c, n.right, -1);
        if !check_integer(left) || !check_integer(right) { diagnose(p, n.token, "range bounds must be integers"); }
        result = check_join_type(p, c, n.left, check_index_value(p, n.left, left), n.right, check_index_value(p, n.right, right), n.token);
    } else if n.kind == N_RESULT {
        let tuple = check_expression(p, c, n.left, -1);
        if tuple < 0 || p.types[tuple].kind != TY_TUPLE { diagnose(p, n.token, "result projection requires a multi-result producer"); }
        else {
            var part = p.types[tuple].first; var ordinal = 0;
            while part >= 0 && ordinal < n.integer { part = p.nodes[part].next; ordinal += 1; }
            if part < 0 { diagnose(p, n.token, "result projection ordinal is outside the producer's results"); }
            else { result = check_loaded_type(p, p.nodes[part].type_id); check_copy_roots(c, node, n.left); }
        }
    } else if n.kind == N_TUPLE {
        var child = n.first;
        while child >= 0 { check_value(p, c, child, -1); child = p.nodes[child].next; }
        result = check_tuple(p, n.first);
    } else if n.kind == N_CONST_FOR { result = check_const_for(p, c, node, expected); }
    else if n.kind == N_EMPTY { result = TYPE_VOID; }
    else if n.kind == N_EXPR_STMT { check_expression(p, c, n.left, TYPE_VOID); result = TYPE_VOID; }
    else { diagnose(p, n.token, "syntax node is not a valid expression"); }
    if check_addressable(p, node) || n.kind == N_CALL { result = check_plain_value_type(p, result); }
    p.nodes[node].type_id = result;
    check_nonnegative_result(p, c, node, n, result);
    if entry_reachable && !c.reachable { p.nodes[node].flags |= F_DIVERGES; }
    if n.kind != N_FUNCTION_VALUE { p.nodes[node].flags |= F_CHECKED; }
    return result;
}

fn check_loop_backedge(p: Program&, c: Checker&, node: i64, entry: CheckSpan, edge: CheckSpan, weakened: CheckList&) {
    var before_at = entry.first; var after_at = edge.first;
    while before_at < entry.first + entry.count && after_at < edge.first + edge.count {
        let before = c.flow_work[before_at]; let after = c.flow_work[after_at];
        if before.symbol < after.symbol { before_at += 1; continue; }
        if after.symbol < before.symbol { after_at += 1; continue; }
        if !before.maybeassigned && after.maybeassigned && (p.symbols[before.symbol].flags & S_MUTABLE) == 0 {
            diagnose(p, p.nodes[node].token, "let binding may already be assigned on a loop backedge");
        }
        if before.narrowed >= 0 && !check_same_type(p, before.narrowed, after.narrowed) {
            check_list_push(c, weakened, before.symbol);
        }
        before_at += 1; after_at += 1;
    }
}
recursive fn check_collect_break_values(p: Program&, c: Checker&, node: i64, target: i64, values: CheckList&, divergence_flags: bool = false) {
    if node < 0 { return; } let n = p.nodes[node];
    if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE || n.kind == N_IMPORT { return; }
    if n.kind == N_BREAK && n.symbol == target {
        if n.left >= 0 {
            if divergence_flags && (p.nodes[n.left].flags & F_DIVERGES) != 0 { return; }
            if !divergence_flags && check_bottom(p, n.left) { return; }
        }
        check_list_push(c, values, n.left); return;
    }
    var child = n.first;
    while child >= 0 { check_collect_break_values(p, c, child, target, values, divergence_flags); child = p.nodes[child].next; }
    check_collect_break_values(p, c, n.left, target, values, divergence_flags);
    check_collect_break_values(p, c, n.right, target, values, divergence_flags);
    if n.kind != N_CALL { check_collect_break_values(p, c, n.third, target, values, divergence_flags); }
}
recursive fn check_join_literal(p: Program&, c: Checker&, node: i64, depth: i64 = 0) -> bool {
    if node < 0 || depth > 64 { return false; } let n = p.nodes[node];
    if check_bottom(p, node) { return true; }
    if n.kind == N_LOOP || n.kind == N_BLOCK && (n.flags & F_EARLY) != 0 {
        var values = CheckList {}; check_collect_break_values(p, c, node, node, values);
        if n.kind == N_BLOCK && (n.flags & F_TAIL) != 0 { check_list_push(c, values, n.last); }
        if values.count == 0 { return false; }
        for index in 0..values.count { if !check_join_literal(p, c, check_list_at(c, values, index), depth + 1) { return false; } }
        return true;
    }
    if n.kind == N_BLOCK && (n.flags & F_TAIL) != 0 { return check_join_literal(p, c, n.last, depth + 1); }
    if n.kind == N_IF && n.third >= 0 { return check_join_literal(p, c, n.right, depth + 1) && check_join_literal(p, c, n.third, depth + 1); }
    if n.kind == N_MATCH && n.first >= 0 {
        var arm = n.first;
        while arm >= 0 { if !check_join_literal(p, c, p.nodes[arm].right, depth + 1) { return false; } arm = p.nodes[arm].next; }
        return true;
    }
    return check_integer_constants(p, c, node) || check_float_literal_tree(p, node, 0);
}
fn check_join_break_values(p: Program&, c: Checker&, node: i64, inputs: CheckList, tail: i64, tail_reachable: bool, tail_type: i64, expected: i64, adapt: bool = true) -> i64 {
    var values = inputs;
    if tail_reachable { check_list_push(c, values, tail); }
    var result = -1; var anchor = -1; var literal = true; var integer_constants = true;
    for index in 0..values.count {
        let value = check_list_at(c, values, index); var ty = TYPE_VOID;
        if value >= 0 { ty = p.nodes[value].type_id; }
        else if tail_reachable && index == values.count - 1 { ty = tail_type; }
        let adaptable = check_join_literal(p, c, value);
        let integer_constant = adaptable && check_integer(check_numeric_value_type(p, ty)) && check_conversion(p, c, value, ty, TYPE_I64) >= 0;
        let previous = result;
        if index == 0 { result = ty; anchor = value; }
        else if integer_constants && integer_constant {
            if !check_same_type(p, result, ty) { result = TYPE_I64; }
        }
        else if !literal && adaptable { result = check_join_type(p, c, value, ty, anchor, result, p.nodes[node].token, false); }
        else { result = check_join_type(p, c, anchor, result, value, ty, p.nodes[node].token, false); }
        if index > 0 && result >= 0 && result != previous {
            var fits = true;
            for prior in 0..index + 1 {
                let earlier = check_list_at(c, values, prior);
                if earlier < 0 || check_conversion(p, c, earlier, p.nodes[earlier].type_id, result) < 0 { fits = false; break; }
            }
            if !fits {
                result = previous;
                if result < 0 || value < 0 || check_conversion(p, c, value, ty, result) < 0 {
                    diagnose(p, p.nodes[node].token, "control-flow branches produce incompatible types"); return -1;
                }
            }
        }
        if !adaptable { anchor = value; }
        else if literal && (result == ty || anchor < 0) { anchor = value; }
        literal = literal && adaptable;
        integer_constants = integer_constants && integer_constant;
    }
    // A merged constant no longer retains one named initializer chain.
    if adapt && values.count > 1 && integer_constants {
        for index in 0..values.count { check_rely_named(p, c, check_list_at(c, values, index)); }
    }
    if expected >= 0 && expected != TYPE_VOID { result = expected; }
    if adapt && result >= 0 && result != TYPE_VOID {
        for index in 0..values.count {
            let value = check_list_at(c, values, index);
            if value < 0 { diagnose(p, p.nodes[node].token, "value-producing construct has a valueless exit"); }
            else { check_expect(p, c, value, p.nodes[value].type_id, result); }
        }
    }
    return result;
}
recursive fn check_loop(p: Program&, c: Checker&, node: i64, expected: i64) -> i64 {
    let n = p.nodes[node]; let saved = check_enter(c, c.function_node); let exit_start = c.exit_work.len;
    p.nodes[node].scope = c.scope;
    var entry = CheckSpan {}; check_flow_save(p, c, entry); let initial_entry = entry;
    let li = c.loop_count;
    if n.kind == N_WHILE { check_push_loop(c, CheckLoop { node: node, scope: c.scope, function_node: c.function_node, expected: expected, returning: c.returning }); }
    if n.kind == N_WHILE { check_condition(p, c, n.left); }
    if n.kind == N_FOR {
        let source = check_single_expression(p, c, n.left); var element = TYPE_I64; var sequence = false; var sequence_type = -1;
        if source >= 0 {
            var ty = source;
            while ty >= 0 && p.types[ty].kind == TY_REF {
                if (p.types[ty].flags & TF_OPTIONAL) != 0 { diagnose(p, n.token, "optional count must be narrowed before iteration"); }
                ty = p.types[ty].element;
            }
            if p.nodes[n.left].kind == N_RANGE || check_integer(check_numeric_value_type(p, ty)) {
                element = check_numeric_value_type(p, ty);
                if p.types[ty].kind == TY_INT && p.types[ty].index_type >= 0 {
                    var index_type = p.types[ty]; index_type.flags &= ~F_BOUND_TYPE; element = add_type(p, index_type);
                }
            }
            else if p.types[ty].kind == TY_ARRAY || p.types[ty].kind == TY_SLICE { element = p.types[ty].element; sequence = true; sequence_type = ty; }
            else { diagnose(p, n.token, "for source must be a range, integer count, array or slice"); element = -1; }
        }
        var binding = n.first; var index = 0;
        while binding >= 0 {
            var ty = element;
            if index > 0 { ty = TYPE_I64; }
            let annotation = check_resolve_type(p, c, p.nodes[binding].left);
            if annotation >= 0 {
                if !check_integer(check_numeric_value_type(p, annotation)) { diagnose(p, p.nodes[binding].token, "for binding annotation requires an integer type"); }
                if index == 0 && sequence { diagnose(p, p.nodes[binding].token, "array elements bind at their element type"); }
                else if index > 0 && !sequence { diagnose(p, p.nodes[binding].token, "range and count indexes always bind as i64"); }
                else {
                    ty = annotation;
                    if index == 0 {
                        var bound = n.left;
                        if p.nodes[n.left].kind == N_RANGE { check_value(p, c, p.nodes[n.left].left, annotation); bound = p.nodes[n.left].right; }
                        let end = check_constant(p, c, bound, 0);
                        let canonical = check_numeric_value_type(p, annotation);
                        let past_end = end.valid && check_integer_bits(canonical) < 64 && end.value == check_max(canonical) + 1;
                        if !past_end { check_value(p, c, bound, annotation); }
                    } else {
                        var maximum_index = 281474976710655;
                        if sequence_type >= 0 && p.types[sequence_type].kind == TY_ARRAY && p.types[sequence_type].count >= 0 {
                            maximum_index = p.types[sequence_type].count - 1;
                        }
                        if maximum_index > check_max(check_numeric_value_type(p, annotation)) { diagnose(p, p.nodes[binding].token, "index binding type cannot hold every sequence index"); }
                    }
                }
            }
            var byref = (p.nodes[binding].flags & F_REFERENCE) != 0;
            if index == 0 && sequence && check_size_class(p, element, 0) != 0 { byref = true; p.nodes[binding].flags |= F_REFERENCE; }
            if byref {
                if index > 0 || !sequence { diagnose(p, p.nodes[binding].token, "reference iteration requires array or slice elements"); }
                if ty >= 0 && p.types[ty].kind != TY_REF {
                    var flags = 0;
                    if check_argument_readonly(p, c, n.left, sequence_type) || p.types[ty].storage == 1 { flags |= TF_CONST; }
                    ty = check_type(p, TY_REF, ty, 0, -1, flags);
                }
            }
            if ty >= 0 && p.types[ty].kind == TY_REF && p.types[ty].length_storage >= 0 && p.types[ty].pool < 0 && check_readonly(p, c, n.left) { ty = check_const_type(p, ty); }
            ty = check_loaded_type(p, ty);
            p.nodes[binding].type_id = ty;
            let symbol = check_declare(p, c, binding, c.scope); p.symbols[symbol].type_id = ty;
            let vi = check_variable_index(c, symbol); c.variables[vi].assigned = true; c.variables[vi].maybeassigned = true;
            // The copied binding slot is immutable. A reference or slice
            // stored in it retains its own pointee writability.
            c.variables[vi].readonly = (p.nodes[binding].flags & F_REFERENCE) == 0;
            if (p.nodes[binding].flags & F_REFERENCE) != 0 {
                check_add_root(c, -symbol - 10, check_place_root(p, n.left), 1);
            }
            index += 1; binding = p.nodes[binding].next;
        }
    }
    if n.kind != N_WHILE { check_push_loop(c, CheckLoop { node: node, scope: c.scope, function_node: c.function_node, expected: expected, returning: c.returning }); }
    check_flow_save(p, c, entry);
    if n.kind == N_WHILE { check_narrow_condition(p, c, n.left, true); }
    let returning = c.returning; c.returning = false;
    check_expression(p, c, n.right, TYPE_VOID); c.returning = returning;
    if c.reachable {
        var edge = CheckSpan {}; check_flow_save(p, c, edge);
        c.exit_work.push(CheckExit { target: node, flow: edge, backedge: true });
    }
    var weakened = CheckList {};
    for index in exit_start..c.exit_work.len {
        let edge = c.exit_work[index];
        if edge.target == node && edge.backedge { check_loop_backedge(p, c, node, initial_entry, edge.flow, weakened); }
    }
    if weakened.count > 0 {
        check_flow_restore(c, entry);
        for index in 0..weakened.count { let symbol = check_list_at(c, weakened, index); c.variables[check_variable_index(c, symbol)].narrowed = -1; }
        c.reachable = true;
        var bindings = CheckList {};
        if n.kind == N_WHILE {
            let condition = check_clone(p, c, n.left, bindings); p.nodes[node].left = condition;
            check_condition(p, c, condition);
        }
        check_flow_save(p, c, entry);
        if n.kind == N_WHILE { check_narrow_condition(p, c, p.nodes[node].left, true); }
        let body = check_clone(p, c, n.right, bindings); p.nodes[node].right = body;
        c.returning = false; check_expression(p, c, body, TYPE_VOID); c.returning = returning;
    }
    let loop_state = c.loop_stack[li]; c.loop_count -= 1;
    check_flow_restore(c, entry);
    var fallthrough = n.kind != N_LOOP;
    if n.kind == N_WHILE { let condition = check_constant(p, c, n.left, 0); if condition.valid && condition.value != 0 { fallthrough = false; } }
    c.reachable = check_join_control_exits(p, c, node, exit_start, fallthrough);
    c.scope = saved;
    if n.kind == N_LOOP && loop_state.breaks {
        var values = CheckList {}; check_collect_break_values(p, c, node, node, values);
        return check_join_break_values(p, c, node, values, -1, false, -1, expected);
    }
    return TYPE_VOID;
}
recursive fn check_jump(p: Program&, c: Checker&, node: i64) {
    let n = p.nodes[node]; var li = c.loop_count - 1;
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
        if n.left >= 0 {
            var expected = target.expected; if expected < 0 { expected = target.result; }
            let returning = c.returning; c.returning = target.returning;
            ty = check_value(p, c, n.left, expected, c.tuple_context); c.returning = returning;
            if expected < 0 { ty = check_index_value(p, n.left, ty); }
        }
        if p.nodes[target.node].kind != N_LOOP && (p.nodes[target.node].flags & F_EARLY) == 0 && n.left >= 0 {
            diagnose(p, n.token, "only loop expressions and early blocks accept a break value");
        }
        if c.reachable {
            var values = c.loop_stack[li].values; check_list_push(c, values, n.left); c.loop_stack[li].values = values;
            if target.result >= 0 || !check_join_literal(p, c, n.left) {
                c.loop_stack[li].result = check_join_break_values(p, c, target.node, values, -1, false, -1, target.expected, false);
            }
            c.loop_stack[li].breaks = true;
            var exit_flow = CheckSpan {}; check_flow_save(p, c, exit_flow); c.exit_work.push(CheckExit { target: target.node, flow: exit_flow });
            if n.left >= 0 { check_copy_roots(c, target.node, n.left); }
        }
    } else if c.reachable {
        var exit_flow = CheckSpan {}; check_flow_save(p, c, exit_flow);
        c.exit_work.push(CheckExit { target: target.node, flow: exit_flow, backedge: true });
    }
    c.reachable = false;
}
struct CheckInterval {
    low: i64, high: i64, next: i64 = -1,
    token_first: i64 = -1, token_last: i64 = -1, literal: bool = false,
}
fn check_interval_covered(c: Checker&, intervals: CheckList&, low: i64, high: i64) -> bool {
    var reached = low; var started = false; var progress = true;
    while progress {
        progress = false;
        for index in 0..intervals.count {
            let interval = check_interval_at(c, intervals, index);
            if !started {
                if interval.low <= low && interval.high >= low { reached = interval.high; started = true; progress = true; }
            } else if reached < high && interval.low <= reached + 1 && interval.high > reached {
                reached = interval.high; progress = true;
            }
            if started && reached >= high { return true; }
        }
    }
    return false;
}
recursive fn check_pattern_literal(p: Program&, node: i64) -> bool {
    let n = p.nodes[node];
    if n.kind == N_INTEGER { return true; }
    if n.kind == N_UNARY && n.integer == T_MINUS { return p.nodes[n.left].kind == N_INTEGER; }
    if n.kind == N_RANGE { return check_pattern_literal(p, n.left) && check_pattern_literal(p, n.right); }
    return false;
}
recursive fn check_pattern_first(p: Program&, node: i64) -> i64 {
    let n = p.nodes[node];
    if n.kind == N_RANGE { return check_pattern_first(p, n.left); }
    if n.kind == N_NAME && n.aux > 1 { return n.integer; }
    return n.token;
}
recursive fn check_pattern_last(p: Program&, node: i64) -> i64 {
    let n = p.nodes[node];
    if n.kind == N_RANGE { return check_pattern_last(p, n.right); }
    if n.kind == N_UNARY { return check_pattern_last(p, n.left); }
    return n.token;
}
fn check_pattern_spelling(p: Program&, first: i64, last: i64, previous: CheckInterval) -> bool {
    if last - first != previous.token_last - previous.token_first { return false; }
    for offset in 0..last - first + 1 { if !same_name(p, first + offset, previous.token_first + offset) { return false; } }
    return true;
}
recursive fn check_tail_contains(p: Program&, node: i64, target: i64) -> bool {
    if node < 0 { return false; }
    if node == target { return true; }
    let n = p.nodes[node];
    if n.kind == N_BLOCK && (n.flags & F_TAIL) != 0 { return check_tail_contains(p, n.last, target); }
    if n.kind == N_IF { return check_tail_contains(p, n.right, target) || check_tail_contains(p, n.third, target); }
    if n.kind == N_MATCH {
        var arm = n.first;
        while arm >= 0 { if p.nodes[arm].kind == N_ARM && check_tail_contains(p, p.nodes[arm].right, target) { return true; } arm = p.nodes[arm].next; }
    }
    return false;
}
recursive fn check_valueless_tail(p: Program&, node: i64) -> bool {
    if node < 0 { return false; }
    let n = p.nodes[node];
    if n.kind == N_IF { return n.third < 0 || check_valueless_tail(p, n.right) || check_valueless_tail(p, n.third); }
    if n.kind == N_BLOCK { return (n.flags & F_TAIL) != 0 && check_valueless_tail(p, n.last); }
    if n.kind == N_MATCH {
        var arm = n.first;
        while arm >= 0 { if p.nodes[arm].kind == N_ARM && check_valueless_tail(p, p.nodes[arm].right) { return true; } arm = p.nodes[arm].next; }
    }
    return false;
}
recursive fn check_match(p: Program&, c: Checker&, node: i64, expected: i64) -> i64 {
    let n = p.nodes[node]; let returning = c.returning; c.returning = false;
    var source = check_value(p, c, n.left, -1); c.returning = returning;
    if source >= 0 && p.types[source].kind == TY_REF && (p.types[source].flags & TF_OPTIONAL) != 0 { diagnose(p, n.token, "optional reference must be narrowed before matching"); }
    while source >= 0 && p.types[source].kind == TY_REF { source = p.types[source].element; }
    p.nodes[node].aux = source;
    if source < 0 { return -1; }
    let enum_match = p.types[source].kind == TY_ENUM;
    if !enum_match && !check_integer(source) && source != TYPE_BOOL { diagnose(p, n.token, "match requires an integer, bool or enum"); }
    if enum_match { check_layout_nominal(p, c, source); }
    check_expand_children(p, c, node);
    if p.nodes[node].first < 0 { diagnose(p, n.token, "match has no arms: its const for generated none"); }
    var arm_expected = expected; var statement = expected == TYPE_VOID;
    if expected < 0 && c.function_node >= 0 && check_tail_contains(p, p.nodes[c.function_node].right, node) {
        var arm = p.nodes[node].first;
        while arm >= 0 { if p.nodes[arm].kind == N_ARM && check_valueless_tail(p, p.nodes[arm].right) { statement = true; } arm = p.nodes[arm].next; }
        if statement { arm_expected = TYPE_VOID; }
    }
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
        if (pattern.flags & F_DEFAULT) != 0 && a.third < 0 { wildcard = true; }
        var arm_intervals = CheckList {}; var arm_tags = CheckList {};
        var item = pattern.first; var payload = -1;
        while item >= 0 {
            let pat = p.nodes[item];
            if pat.expansion_binding == -2 { diagnose(p, pat.token, "const for binding is not a variant pattern"); }
            if !enum_match && pat.type_id >= 0 && p.types[pat.type_id].kind == TY_STRUCT && p.types[pat.type_id].pool >= 0 { diagnose(p, pat.token, "const for variant pattern requires its enum as the scrutinee"); }
            if enum_match {
                if pat.type_id >= 0 && p.types[pat.type_id].kind == TY_STRUCT && p.types[pat.type_id].pool >= 0 && p.types[p.types[pat.type_id].pool].declaration != p.types[source].declaration { diagnose(p, pat.token, "const for variant pattern belongs to a different enum type"); }
                var variant = p.types[source].first;
                while variant >= 0 { if same_name(p, p.nodes[variant].token, pat.token) { break; } variant = p.nodes[variant].next; }
                if variant < 0 { diagnose(p, pat.token, "match pattern names no variant of this enum"); }
                else {
                    let tag = p.nodes[variant].integer;
                    for previous_index in 0..tags.count { let previous = check_list_at(c, tags, previous_index); if previous == tag { diagnose(p, pat.token, "duplicate enum match pattern"); } }
                    for previous_index in 0..arm_tags.count { if check_list_at(c, arm_tags, previous_index) == tag { diagnose(p, pat.token, "enum variant is listed twice in one arm"); } }
                    check_list_push(c, arm_tags, tag); p.nodes[item].symbol = variant; p.nodes[item].integer = tag;
                    p.nodes[item].type_id = source; p.nodes[item].flags |= F_CHECKED;
                    payload = p.nodes[variant].type_id;
                }
            } else {
                check_constant_names(p, c, item);
                var low = check_width_constant(p, c, item, source); if !low.valid { low = check_constant(p, c, item, 0); } var high = low;
                if pat.kind == N_RANGE {
                    low = check_width_constant(p, c, pat.left, source); if !low.valid { low = check_constant(p, c, pat.left, 0); }
                    high = check_width_constant(p, c, pat.right, source); if !high.valid { high = check_constant(p, c, pat.right, 0); }
                }
                if !low.valid || !high.valid { diagnose(p, pat.token, "match pattern must be a constant integer or range"); }
                else {
                    let emitted_low = low.value; let emitted_high = high.value;
                    let token_first = check_pattern_first(p, item); let token_last = check_pattern_last(p, item);
                    let literal = check_pattern_literal(p, item);
                    if source == TYPE_U64 { low.value = low.value ^ -9223372036854775808; high.value = high.value ^ -9223372036854775808; }
                    if check_integer(source) && source != TYPE_U64 && (low.value < check_min(source) || high.value > check_max(source)) {
                        diagnose(p, pat.token, "match pattern is outside the scrutinee type");
                    }
                    var valid = low.value <= high.value;
                    if pat.kind == N_RANGE && (pat.flags & F_INCLUSIVE) == 0 {
                        valid = low.value < high.value;
                        if valid { high.value -= 1; }
                    }
                    if !valid { diagnose(p, pat.token, "empty range in match pattern"); }
                    else {
                        if check_interval_covered(c, intervals, low.value, high.value) { diagnose(p, pat.token, "match pattern never matches: earlier arms cover all of its values"); }
                        for previous_index in 0..arm_intervals.count {
                            let previous = check_interval_at(c, arm_intervals, previous_index);
                            if low.value <= previous.high && previous.low <= high.value {
                                if check_pattern_spelling(p, token_first, token_last, previous) { diagnose(p, pat.token, "match pattern is listed twice in one arm"); }
                                else if literal && previous.literal { diagnose(p, pat.token, "literal match patterns overlap within one arm"); }
                            }
                        }
                        check_interval_push(c, arm_intervals, CheckInterval { low: low.value, high: high.value,
                            token_first: token_first, token_last: token_last, literal: literal });
                    }
                    if pat.kind == N_RANGE {
                        p.nodes[pat.left].kind = N_INTEGER; p.nodes[pat.left].integer = emitted_low; p.nodes[pat.left].type_id = source;
                        p.nodes[pat.right].kind = N_INTEGER; p.nodes[pat.right].integer = emitted_high; p.nodes[pat.right].type_id = source;
                    } else { p.nodes[item].kind = N_INTEGER; p.nodes[item].integer = emitted_low; }
                    p.nodes[item].type_id = source; p.nodes[item].flags |= F_CHECKED;
                }
            }
            item = pat.next;
        }
        if a.third < 0 {
            for index in 0..arm_intervals.count { check_interval_push(c, intervals, check_interval_at(c, arm_intervals, index)); }
            for index in 0..arm_tags.count { check_list_push(c, tags, check_list_at(c, arm_tags, index)); }
        }
        if pattern.left >= 0 {
            let binder = pattern.left;
            if !enum_match || payload < 0 { diagnose(p, pattern.token, "payload binding requires one enum variant pattern"); }
            else {
                var ty = payload;
                let intrinsic = (p.nodes[binder].flags & (F_REFERENCE | F_SYNTHETIC)) == (F_REFERENCE | F_SYNTHETIC) && c.function_node >= 0 && (p.nodes[c.function_node].flags & (F_SYNTHETIC | F_FORMAT_RAW)) == (F_SYNTHETIC | F_FORMAT_RAW);
                if check_size_class(p, payload, 0) == 2 && !intrinsic { diagnose(p, pattern.token, "binding a resizable enum payload is unsupported"); }
                if (p.nodes[binder].flags & F_REFERENCE) != 0 {
                    if (p.types[source].flags & F_VARIABLE_MODE) == 0 { diagnose(p, pattern.token, "fixed-mode enum payloads cannot bind by reference"); }
                    if check_size_class(p, source, 0) == 2 && !intrinsic { diagnose(p, pattern.token, "resizable enum payloads cannot bind by reference"); }
                    ty = check_type(p, TY_REF, payload, 0, -1, 0);
                }
                p.nodes[binder].type_id = ty;
                let symbol = check_declare(p, c, binder, c.scope); p.symbols[symbol].type_id = ty;
                let vi = check_variable_index(c, symbol); c.variables[vi].assigned = true; c.variables[vi].maybeassigned = true;
                c.variables[vi].readonly = (p.nodes[binder].flags & F_REFERENCE) == 0;
                if (p.nodes[binder].flags & F_REFERENCE) != 0 { check_add_root(c, -symbol - 10, check_place_root(p, n.left), 1); }
            }
        }
        if a.third >= 0 { check_condition(p, c, a.third); }
        var ty = check_value(p, c, a.right, arm_expected, c.tuple_context);
        if statement && ty >= 0 { ty = TYPE_VOID; }
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
    // Integer patterns always retain an explicit default arm, including a
    // complete finite-width partition. Enum wildcards may be empty after
    // specialization and remain valid generic code.
    if !exhaustive { diagnose(p, n.token, "match does not cover every possible value"); }
    check_flow_restore(c, merged); c.reachable = any_reachable;
    if expected == TYPE_VOID { return TYPE_VOID; }
    return result;
}
recursive fn check_return(p: Program&, c: Checker&, node: i64) {
    let returning = c.returning; c.returning = true;
    check_return_value(p, c, node); c.returning = returning;
}
recursive fn check_return_value(p: Program&, c: Checker&, node: i64) {
    let n = p.nodes[node]; var target = c.function_node;
    if c.default_body { diagnose(p, n.token, "return is only valid inside a function"); return; }
    if target >= 0 && p.nodes[target].kind == N_FUNCTION_VALUE && (n.flags & F_IMPLICIT_RETURN) == 0 && n.left < 0 {
        let function_symbol = p.nodes[target].symbol;
        target = -1;
        if function_symbol >= 0 { target = p.symbols[function_symbol].owner; }
        while target >= 0 && p.nodes[target].kind == N_FUNCTION_VALUE {
            let owner_symbol = p.nodes[target].symbol;
            if owner_symbol < 0 { break; }
            target = p.symbols[owner_symbol].owner;
        }
        if target != c.function_node { p.nodes[c.function_node].flags |= F_NONLOCAL; }
    }
    if target < 0 { diagnose(p, n.token, "return is only valid inside a function"); return; }
    if n.left >= 0 {
        target = -1;
        let functions = check_lookup_name(p, c, n.left, S_FUNCTION | S_BUILTIN);
        var i = c.checking_count - 1;
        while i >= 0 && target < 0 {
            let fnnode = c.checking[i]; var candidate = functions;
            while candidate >= 0 {
                let symbol = p.symbols[candidate];
                if (symbol.flags & S_FUNCTION) != 0 && p.nodes[fnnode].kind == N_FUNCTION &&
                   check_function_declaration(p, fnnode) == check_function_declaration(p, symbol.node) { target = fnnode; break; }
                candidate = symbol.next;
            }
            i -= 1;
        }
        if target < 0 { diagnose(p, n.token, "nonlocal return does not name an active enclosing function"); return; }
        if target != c.function_node { p.nodes[c.function_node].flags |= F_NONLOCAL; }
    }
    let symbol = p.nodes[target].symbol; p.nodes[node].symbol = symbol;
    if target != c.function_node {
        p.nodes[node].flags |= F_NONLOCAL;
        var index = c.checking_count - 1;
        while index >= 0 && c.checking[index] != target { check_add_need(p, c, c.checking[index], target); index -= 1; }
    }
    var expected = c.result_type;
    if target != c.function_node { expected = p.types[p.nodes[target].type_id].element; }
    var expected_part = -1;
    if expected >= 0 && p.types[expected].kind == TY_TUPLE { expected_part = p.types[expected].first; }
    var forward_tuple = false;
    if n.first >= 0 && p.nodes[n.first].next < 0 {
        let saved = c.tuple_context; c.tuple_context = expected < 0 || p.types[expected].kind == TY_TUPLE;
        let value_type = check_expression(p, c, n.first, expected); c.tuple_context = saved;
        if !c.reachable { return; }
        if value_type >= 0 && p.types[value_type].kind == TY_TUPLE && (expected < 0 || p.types[expected].kind == TY_TUPLE) { forward_tuple = true; expected_part = -1; }
    }
    var converted_first = -1; var converted_last = -1;
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
        var ty = check_value(p, c, value, destination, forward_tuple);
        if !c.reachable { return; }
        if destination < 0 { ty = check_inferred_result(p, c, value, target); }
        let converted = new_node(p, N_TYPE_ARG, p.nodes[value].token); p.nodes[converted].type_id = ty;
        if converted_first < 0 { converted_first = converted; } else { p.nodes[converted_last].next = converted; }
        converted_last = converted;
        if expected_part >= 0 { expected_part = p.nodes[expected_part].next; }
        if ty >= 0 && check_contains_refs(p, ty, 0) {
            var root_at = check_root_head(c, value);
            while root_at >= 0 {
                let r = c.roots[root_at]; root_at = r.next;
                c.return_roots.push(CheckReturnRoot { function_node: target, index: index, root: r.root, kind: r.kind });
            }
        }
        index += 1; value = p.nodes[value].next;
    }
    var actual = check_tuple(p, converted_first);
    if forward_tuple && converted_first >= 0 { actual = p.nodes[converted_first].type_id; }
    if expected >= 0 && !check_same_type(p, expected, actual) {
        if n.first < 0 || p.nodes[n.first].next >= 0 || check_conversion(p, c, n.first, actual, expected) < 0 {
            diagnose(p, n.token, "return values do not match the function result signature");
        }
    }
    var exit_flow = CheckSpan {}; check_flow_save(p, c, exit_flow); c.exit_work.push(CheckExit { target: target, flow: exit_flow });
    p.nodes[target].flags |= F_RETURNS; p.nodes[target].flags &= ~F_DIVERGES;
    if target == c.function_node {
        if c.result_type < 0 { c.result_type = actual; p.types[p.nodes[target].type_id].element = actual; }
        else if expected < 0 { c.result_type = check_join_type(p, c, -1, c.result_type, n.first, actual, n.token); }
        c.returns = true;
    } else if expected < 0 { p.types[p.nodes[target].type_id].element = actual; }
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
    var annotation = check_value_annotation(p, c, n.left, check_resolve_type(p, c, n.left));
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
        tuple = check_value(p, c, check_list_at(c, values, 0), -1, true);
        if tuple < 0 && !c.reachable { tuple = p.nodes[check_list_at(c, values, 0)].type_id; }
        if tuple < 0 || p.types[tuple].kind != TY_TUPLE || p.types[tuple].count != names.count {
            diagnose(p, n.token, "multiple binding requires the same number of call results"); tuple = -1;
        }
        if annotation >= 0 { diagnose(p, n.token, "multiple-value binding cannot have one type annotation"); }
    } else if values.count > 0 && values.count != names.count { diagnose(p, n.token, "binding name and initializer counts differ"); }
    var component = -1; if tuple >= 0 { component = p.types[tuple].first; }
    for index in 0..names.count { let binding = check_list_at(c, names, index);
        var ty = annotation; var init = -1;
        if tuple >= 0 && component >= 0 {
            ty = check_loaded_type(p, p.nodes[component].type_id); init = check_list_at(c, values, 0); component = p.nodes[component].next;
            if (n.flags & F_REFERENCE) == 0 {
                if ty >= 0 && p.types[ty].kind == TY_REF && (p.types[ty].flags & TF_OPTIONAL) == 0 {
                    let element = p.types[ty].element;
                    if check_size_class(p, element, 0) == 0 || p.types[element].storage == 1 { ty = element; }
                }
                if ty < 0 || p.types[ty].index_type < 0 { ty = check_numeric_value_type(p, ty); }
            }
        }
        else if index < values.count {
            init = check_list_at(c, values, index);
            if (n.flags & F_REFERENCE) != 0 && annotation < 0 {
                ty = check_read_value_type(p, c, init, check_single_expression(p, c, init));
                if ty >= 0 && p.types[ty].kind != TY_REF && p.types[ty].kind != TY_SLICE {
                    if !check_addressable(p, init) { diagnose(p, n.token, ".= initialization requires storage, reference or slice"); }
                    else {
                        let root = check_place_root(p, init); var flags = 0;
                        if check_readonly(p, c, init) || p.types[ty].storage == 1 { flags |= TF_CONST; }
                        ty = check_type(p, TY_REF, ty, 0, -1, flags);
                        let root_kind = check_reference_kind(p, init);
                        if (flags & TF_CONST) == 0 { check_named_writable(p, c, root, n.token); }
                        check_require_referenceable(p, c, init);
                        check_wrap_unary(p, init, T_BITAND, ty); check_add_root(c, init, root, root_kind);
                    }
                }
            } else {
                if annotation < 0 && p.nodes[init].kind == N_UNARY && p.nodes[init].integer == T_BITAND {
                    ty = check_read_value_type(p, c, init, check_expression(p, c, init, -1));
                } else {
                    ty = check_value(p, c, init, annotation);
                    if annotation < 0 { ty = check_index_value(p, init, ty); }
                }
                if annotation < 0 && ty >= 0 && check_size_class(p, ty, 0) > 0 && check_addressable(p, init) {
                    let root = check_place_root(p, init); var flags = 0;
                    if check_readonly(p, c, init) { flags |= TF_CONST; }
                    ty = check_type(p, TY_REF, ty, 0, -1, flags);
                    let root_kind = check_reference_kind(p, init);
                        check_require_referenceable(p, c, init);
                        check_wrap_unary(p, init, T_BITAND, ty); check_add_root(c, init, root, root_kind);
                }
            }
            if annotation >= 0 { check_slot_value(p, c, init, annotation); ty = annotation; }
            if p.nodes[init].kind == N_NULL && annotation < 0 { diagnose(p, n.token, "null binding requires an optional type annotation"); }
            if ty >= 0 && p.types[ty].kind == TY_ARRAY && p.types[ty].element < 0 {
                if (n.flags & F_VAR) == 0 || p.nodes[init].kind != N_ARRAY {
                    diagnose(p, n.token, "empty array element inference requires a var initialized directly with []");
                }
                ty = add_type(p, Type { kind: TY_ARRAY, element: -1, count: -1, size: 24, align: 4, array_kind: A_GROW, length_storage: -1 });
                p.nodes[init].type_id = ty;
            }
        } else if annotation < 0 { diagnose(p, n.token, "binding requires a type or initializer"); }
        if init >= 0 && ty < 0 && annotation < 0 {
            if p.nodes[init].type_id < 0 { diagnose(p, n.token, "initializer has no value from which to infer its type"); }
            else if !c.reachable { ty = p.nodes[init].type_id; }
        }
        if ty == TYPE_VOID { diagnose(p, n.token, "binding initializer produces no value"); }
        if ty >= 0 && p.types[ty].kind == TY_FN { diagnose(p, n.token, "function values are compile-time arguments and cannot be stored"); }
        if ty >= 0 && (n.flags & F_CONST) != 0 { ty = check_const_type(p, ty); }
        p.nodes[binding].type_id = ty;
        let symbol = check_declare(p, c, binding, c.scope); p.symbols[symbol].type_id = ty;
        if (p.symbols[symbol].flags & S_GLOBAL) != 0 && ty >= 0 && p.types[ty].kind == TY_REF && (p.types[ty].flags & TF_OPTIONAL) != 0 { c.optional_globals = true; }
        if index == 0 { p.nodes[node].symbol = symbol; p.nodes[node].type_id = ty; }
        let vi = check_variable_index(c, symbol);
        if vi >= 0 {
            c.variables[vi].assigned = init >= 0; c.variables[vi].maybeassigned = init >= 0;
            c.variables[vi].readonly = (n.flags & F_CONST) != 0;
            if init >= 0 && tuple < 0 && ty >= 0 && p.types[ty].kind == TY_INT && (n.flags & F_VAR) == 0 {
                c.variables[vi].nonnegative = check_nonnegative_get(c, init);
            }
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
        if init < 0 && ty >= 0 && check_size_class(p, ty, 0) != 0 {
            diagnose(p, n.token, "nonfixed values must be constructed at declaration");
        }
    }
    c.scope = saved_scope; c.function_node = saved_function;
}
recursive fn check_compound_aggregate(p: Program&, c: Checker&, node: i64, type_id: i64) {
    let n = p.nodes[node];
    if check_bottom(p, n.left) {
        p.nodes[node] = Node { kind: N_EXPR_STMT, token: n.token, next: n.next, left: n.left, type_id: TYPE_VOID,
            flags: F_CHECKED | F_DIVERGES | F_REACHABLE, scope: n.scope }; return;
    }
    let root = check_place_root(p, n.left); let vi = check_variable_index(c, root);
    if vi >= 0 && !c.variables[vi].assigned { diagnose(p, n.token, "compound assignment reads uninitialized storage"); }
    check_assignment_target(p, c, n.left, n.right, false);
    // Preserve the evaluated location and its old value before the RHS.
    // The final assignment uses ordinary aggregate arithmetic in both backends.
    var value_type = type_id;
    if (p.types[value_type].flags & TF_CONST) != 0 { var mutable = p.types[value_type]; mutable.flags &= ~TF_CONST; value_type = add_type(p, mutable); }
    let reference_type = check_type(p, TY_REF, value_type, 0, -1, 0);
    let target_name = operation_name(p, n.token, "__goose_update_target");
    let old_name = operation_name(p, n.token, "__goose_update_old");
    let target = new_node(p, N_VARIABLE, target_name); p.nodes[target].left = operation_type(p, reference_type, n.token);
    var address = n.left;
    if p.types[p.nodes[n.left].type_id].kind != TY_REF {
        address = new_node(p, N_UNARY, n.token); p.nodes[address].integer = T_BITAND; p.nodes[address].left = n.left;
        p.nodes[address].type_id = reference_type; p.nodes[address].flags = F_CHECKED | F_SYNTHETIC;
        check_copy_roots(c, address, n.left); check_add_root(c, address, root, check_reference_kind(p, n.left));
    }
    p.nodes[target].right = address;
    let old = new_node(p, N_VARIABLE, old_name); p.nodes[old].left = operation_type(p, value_type, n.token);
    p.nodes[old].right = operation_ident(p, target_name);
    var op = T_PLUS;
    if n.integer == T_MINUSEQ { op = T_MINUS; } else if n.integer == T_MULEQ { op = T_MUL; }
    else if n.integer == T_DIVEQ { op = T_DIV; } else if n.integer == T_MODEQ { op = T_MOD; }
    let binary = operation_binary(p, op, operation_ident(p, old_name), n.right, n.token);
    let assign = new_node(p, N_ASSIGN, n.token); p.nodes[assign].integer = T_ASSIGN;
    p.nodes[assign].left = operation_ident(p, target_name); p.nodes[assign].right = binary;
    p.nodes[node] = Node { kind: N_BLOCK, token: n.token, next: n.next, scope: n.scope, flags: F_SYNTHETIC | (n.flags & (F_REACHABLE | F_TAIL)) };
    append_child(p, node, target); append_child(p, node, old); append_child(p, node, assign);
    check_block(p, c, node, TYPE_VOID);
    if check_bottom(p, n.right) {
        p.nodes[assign] = Node { kind: N_EXPR_STMT, token: n.token, left: n.right, type_id: TYPE_VOID,
            flags: F_CHECKED | F_DIVERGES | F_REACHABLE, scope: p.nodes[assign].scope };
    }
}

// A multi-assignment is one result binding followed by ordinary stores.
recursive fn check_multi_assignment(p: Program&, c: Checker&, node: i64) {
    let n = p.nodes[node];
    let binding = new_node(p, N_VARIABLE, n.token); p.nodes[binding].flags = F_MULTI | F_SYNTHETIC; p.nodes[binding].right = n.right;
    var stores = CheckList {}; var target = n.first;
    while target >= 0 {
        let next = p.nodes[target].next; p.nodes[target].next = -1;
        let name = operation_name(p, n.token, "__goose_result");
        let result = new_node(p, N_BINDING, name); p.nodes[result].flags = F_RESULT_TEMP; append_child(p, binding, result);
        let assign = new_node(p, N_ASSIGN, n.token); p.nodes[assign].integer = T_ASSIGN;
        p.nodes[assign].left = target; p.nodes[assign].right = operation_ident(p, name); check_list_push(c, stores, assign);
        target = next;
    }
    p.nodes[node] = Node { kind: N_BLOCK, token: n.token, next: n.next, scope: n.scope, flags: F_SYNTHETIC | (n.flags & (F_REACHABLE | F_TAIL)) };
    append_child(p, node, binding);
    for index in 0..stores.count { append_child(p, node, check_list_at(c, stores, index)); }
    check_block(p, c, node, TYPE_VOID);
}

recursive fn check_assignment(p: Program&, c: Checker&, node: i64) {
    var n = p.nodes[node];
    if n.kind == N_MULTI_ASSIGN { check_multi_assignment(p, c, node); return; }
    if n.right >= 0 && p.nodes[n.right].kind == N_NAME {
        let symbol = check_lookup_name(p, c, n.right);
        if symbol >= 0 && p.symbols[symbol].node >= 0 && (p.nodes[p.symbols[symbol].node].flags & F_RESULT_TEMP) != 0 {
            let ty = p.symbols[symbol].type_id;
            if ty >= 0 && p.types[ty].kind != TY_REF && p.types[ty].kind != TY_SLICE && check_size_class(p, ty, 0) > 0 {
                let name = operation_name(p, n.token, "copy", false); let copy = new_node(p, N_CALL, n.token);
                p.nodes[copy].left = operation_ident(p, name); p.nodes[copy].flags = F_SYNTHETIC;
                p.nodes[copy].symbol = check_builtin_symbol(p, name, 15, ty); append_child(p, copy, n.right);
                p.nodes[node].right = copy; n.right = copy;
            }
        }
    }
    // A bare unassigned name is a legal assignment target, without reading it.
    let target = p.nodes[n.left]; var ty = -1;
    if target.kind == N_NAME {
        let symbol = check_lookup_name(p, c, n.left);
        if symbol >= 0 {
            if !check_global_use(p, c, symbol, target.token) { return; }
            check_environment_note(p, c, symbol); p.nodes[n.left].symbol = symbol; ty = p.symbols[symbol].type_id; p.nodes[n.left].type_id = ty;
        }
        else { diagnose(p, target.token, "assignment target is unknown"); }
    } else { ty = check_expression(p, c, n.left, -1); }
    if ty < 0 { return; }
    let rebind = n.integer == T_DOTASSIGN;
    // The binding keeps the kind it carried before evaluating the RHS.
    var prior_pool = 0;
    if rebind && target.kind == N_NAME && p.types[ty].kind == TY_REF { prior_pool = check_pool_flags(p, c, n.left); }
    if p.types[ty].kind == TY_REF && !rebind {
        // Writing through a reference reads the binding before its RHS runs.
        if target.kind == N_NAME { ty = check_expression(p, c, n.left, -1); }
        if ty >= 0 && (p.types[ty].flags & TF_OPTIONAL) != 0 { diagnose(p, n.token, "optional reference must be narrowed before writing through it"); }
    }
    if ty < 0 { return; }
    var value_type = ty;
    if p.types[ty].kind == TY_REF && !rebind { value_type = p.types[ty].element; }
    if rebind && p.types[ty].kind != TY_REF && p.types[ty].kind != TY_SLICE && target.kind != N_INDEX && target.kind != N_MEMBER {
        diagnose(p, n.token, ".= requires a reference or slice binding");
    }
    if n.right >= 0 && (n.integer == T_PLUSEQ || n.integer == T_MINUSEQ || n.integer == T_MULEQ || n.integer == T_DIVEQ || n.integer == T_MODEQ) &&
       (p.types[value_type].kind == TY_ARRAY || p.types[value_type].kind == TY_STRUCT) && operation_numeric_class(p, value_type) > 0 {
        check_compound_aggregate(p, c, node, value_type); return;
    }
    if n.right >= 0 {
        if n.integer == T_ASSIGN && p.types[value_type].kind == TY_ARRAY && p.types[value_type].element < 0 {
            let source = check_array_receiver(p, c, n.right, false);
            if source >= 0 { check_complete_pending(p, c, n.left, value_type, p.types[source].element, n.token); }
        }
        if n.integer == T_SHLEQ || n.integer == T_SHREQ {
            let count_type = check_numeric_value_type(p, check_value(p, c, n.right, -1));
            if count_type < 0 || p.types[count_type].kind != TY_INT { diagnose(p, n.token, "shift count must be an integer"); }
        } else {
            var context = value_type;
            if prior_pool != 0 && (p.types[context].flags & F_REUSABLE) != 0 {
                // Expected types guide literals and generic results, but do not
                // supply the source pool proof for a rebinding.
                var unqualified = p.types[context]; unqualified.flags &= ~(F_REUSABLE | F_REUSABLE_SLICES);
                context = add_type(p, unqualified);
            }
            check_value(p, c, n.right, context);
        }
        if prior_pool != 0 && prior_pool != check_pool_flags(p, c, n.right, true) {
            diagnose(p, n.token, "rebinding a pool reference requires another pool of the same kind");
        }
        if n.integer == T_ASSIGN || n.integer == T_DOTASSIGN { check_slot_value(p, c, n.right, value_type); }
    }
    else if n.integer != T_INC && n.integer != T_DEC { diagnose(p, n.token, "assignment has no right operand"); }
    if n.integer != T_ASSIGN && n.integer != T_DOTASSIGN {
        if p.types[value_type].kind == TY_INT && p.types[value_type].index_type >= 0 { diagnose(p, n.token, "arithmetic computes a plain integer and cannot update index or bound storage"); }
        if !check_numeric(check_numeric_value_type(p, value_type)) { diagnose(p, n.token, "compound assignment requires numeric storage"); }
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
    let binding_update = n.kind == N_NAME && n.type_id >= 0 && (rebind || p.types[n.type_id].kind == TY_SLICE);
    let whole_binding = n.kind == N_NAME && !through_ref;
    if !binding_update && !whole_binding && check_readonly(p, c, target, !through_ref) { diagnose(p, n.token, "assignment cannot change read-only storage"); }
    if binding_update && root >= 0 && p.symbols[root].node >= 0 && (p.nodes[p.symbols[root].node].flags & F_CONST) != 0 {
        diagnose(p, n.token, "assignment cannot change a const binding");
    }
    if n.kind == N_NAME && root >= 0 && !through_ref {
        let s = p.symbols[root]; let vi = check_variable_index(c, root);
        if (s.flags & S_MUTABLE) == 0 && (vi < 0 || c.variables[vi].maybeassigned) {
            diagnose(p, n.token, "let binding cannot be assigned again");
        }
        check_note_effect(c, root, 6);
        if vi >= 0 {
            c.variables[vi].assigned = true; c.variables[vi].maybeassigned = true;
            if rebind { check_assign_narrowing(p, c, root, value); check_note_effect(c, root, 5); }
        }
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
    parse_deferred_body(p, function_node);
    check_prepare_function(p, c, function_node);
    let n = p.nodes[function_node];
    p.nodes[function_node].flags |= F_REACHABLE;
    if (n.flags & F_CHECKED) != 0 || (n.flags & F_GENERIC) != 0 { return; }
    for active_index in 0..c.checking_count { let active = c.checking[active_index];
        if active == function_node {
            var found = false; var backedges = c.backedges;
            for index in 0..backedges.count { if check_list_at(c, backedges, index) == function_node { found = true; break; } }
            if !found { check_list_push(c, c.backedges, function_node); }
            if (n.flags & F_RECURSIVE) == 0 { diagnose(p, n.token, "recursive cycle requires recursive declarations"); }
            if p.types[n.type_id].element < 0 { diagnose(p, n.token, "recursive function requires an explicit result type"); }
            return;
        }
    }
    if n.right < 0 { p.nodes[function_node].flags |= F_CHECKED; return; }
    check_function_syntax(p, c, function_node);
    var entry_flow = CheckSpan {}; check_flow_save(p, c, entry_flow, true); let exit_start = c.exit_work.len; let effect_start = c.effects.len;
    let saved_scope = c.scope; let saved_function = c.function_node; let saved_result = c.result_type;
    let saved_slot = c.next_slot; let saved_reachable = c.reachable; let saved_returns = c.returns; let saved_defaults = c.default_fields;
    let saved_returning = c.returning; c.returning = false;
    let saved_comparison = c.literal_comparison; c.literal_comparison = false;
    let saved_default_body = c.default_body; c.default_body = false;
    let saved_render_reference = c.render_reference; c.render_reference = false;
    let saved_parameter_function = c.parameter_default_function; let saved_parameter_floor = c.parameter_default_floor;
    c.parameter_default_function = -1; c.parameter_default_floor = -1;
    if c.parameter_default_contexts.len > 0 {
        var context_node = function_node; var context_found = false;
        while context_node >= 0 && !context_found {
            for context in c.parameter_default_contexts {
                if context.node == context_node {
                    c.parameter_default_function = context.function_node; c.parameter_default_floor = context.floor; context_found = true; break;
                }
            }
            context_node = p.nodes[context_node].origin;
        }
    }
    if n.kind == N_FUNCTION && (n.flags & F_DEFAULT) == 0 { c.default_fields = CheckList {}; }
    c.scope = n.scope; c.function_node = function_node; c.result_type = p.types[n.type_id].element;
    c.next_slot = check_list_count(p, n.first); c.reachable = true; c.returns = false;
    let saved_need_path = c.need_path; c.need_path = c.need_frames.len;
    c.need_frames.push(CheckNeedFrame { function_node: function_node, parent: saved_need_path });
    check_push_function(c, function_node);
    var body_node = n.right; check_expression(p, c, body_node, c.result_type);
    var recursive_path = false; var backedges = c.backedges;
    for index in 0..backedges.count { if check_list_at(c, backedges, index) == function_node { recursive_path = true; break; } }
    var repeat = false;
    if recursive_path {
        for index in effect_start..c.effects.len {
            let effect = c.effects[index];
            if effect.function_node == function_node && effect.kind == 5 && p.symbols[effect.root].owner != function_node { repeat = true; break; }
        }
    }
    if repeat {
        // The first round discovers transitive rebinds, including defaults
        // and format hooks. The second applies them at recursive backedges.
        var bindings = CheckList {}; body_node = check_clone(p, c, n.right, bindings);
        p.nodes[function_node].right = body_node; check_flow_restore(c, entry_flow);
        c.scope = n.scope; c.reachable = true; check_expression(p, c, body_node, c.result_type);
    }
    if !c.reachable && (p.nodes[function_node].flags & F_RETURNS) == 0 { p.nodes[function_node].flags |= F_DIVERGES; }
    let body = p.nodes[body_node];
    if c.reachable && (body.flags & F_TAIL) != 0 && body.last >= 0 {
        let tail = body.last;
        if p.nodes[tail].kind != N_RETURN && p.nodes[tail].kind != N_BREAK && p.nodes[tail].kind != N_CONTINUE {
            var original = p.nodes[tail]; original.next = -1; original.flags &= ~F_TAIL;
            let value = p.nodes.len; p.nodes.push(original); check_retarget_exits(p, value, tail, value);
            p.nodes[tail] = Node { kind: N_RETURN, token: original.token, first: value, last: value, symbol: n.symbol, flags: F_IMPLICIT_RETURN | F_TAIL, scope: original.scope };
            check_copy_roots(c, value, tail);
            check_return(p, c, tail); p.nodes[tail].type_id = TYPE_VOID; p.nodes[tail].flags |= F_CHECKED;
        }
    } else if c.reachable && c.result_type >= 0 && c.result_type != TYPE_VOID {
        diagnose(p, n.token, "function can reach its end without returning every result");
    }
    if c.reachable { var exit_flow = CheckSpan {}; check_flow_save(p, c, exit_flow); c.exit_work.push(CheckExit { target: function_node, flow: exit_flow }); }
    check_record_outer_exits(p, c, function_node, entry_flow, exit_start);
    for entry_index in entry_flow.first..entry_flow.first + entry_flow.count {
        let entry = c.flow_work[entry_index]; if entry.assigned { continue; }
        var assigned = true; var maybeassigned = entry.maybeassigned; var exits = 0;
        for index in exit_start..c.exit_work.len {
            let exit = c.exit_work[index]; if exit.target != function_node || exit.backedge { continue; }
            exits += 1; var found = false;
            for flow_index in exit.flow.first..exit.flow.first + exit.flow.count {
                let flow = c.flow_work[flow_index]; if flow.symbol != entry.symbol { continue; }
                assigned = assigned && flow.assigned; maybeassigned = maybeassigned || flow.maybeassigned; found = true; break;
            }
            if !found { assigned = false; }
        }
        // Assignments on nonlocal exits belong to their target's join.
        if !maybeassigned {
            for effect_index in effect_start..c.effects.len {
                let effect = c.effects[effect_index];
                if effect.function_node == function_node && effect.root == entry.symbol && effect.kind == 6 {
                    c.effects[effect_index].kind = 0;
                }
            }
        }
        if exits > 0 {
            if maybeassigned && !entry.maybeassigned { check_note_effect(c, entry.symbol, 6); }
            let vi = check_variable_index(c, entry.symbol);
            if vi >= 0 { c.variables[vi].assigned = assigned; c.variables[vi].maybeassigned = maybeassigned; }
            if assigned { check_note_effect(c, entry.symbol, 4); }
        }
    }
    if c.result_type < 0 && p.types[n.type_id].element >= 0 { c.result_type = p.types[n.type_id].element; }
    if c.result_type < 0 { c.result_type = TYPE_VOID; }
    if c.result_type >= 0 && p.types[c.result_type].kind == TY_ARRAY && p.types[c.result_type].element < 0 { diagnose(p, n.token, "cannot infer a result element type from an empty array"); }
    p.types[n.type_id].element = c.result_type;
    p.nodes[function_node].flags |= F_CHECKED;
    c.checking_count -= 1; c.need_path = saved_need_path;
    check_flow_restore(c, entry_flow);
    c.scope = saved_scope; c.function_node = saved_function; c.result_type = saved_result;
    c.next_slot = saved_slot; c.reachable = saved_reachable; c.returns = saved_returns; c.default_fields = saved_defaults; c.returning = saved_returning;
    c.parameter_default_function = saved_parameter_function; c.parameter_default_floor = saved_parameter_floor;
    c.render_reference = saved_render_reference;
    c.literal_comparison = saved_comparison; c.default_body = saved_default_body;
}
recursive fn check_statement(p: Program&, c: Checker&, node: i64) {
    let returning = c.returning; c.returning = false;
    let n = p.nodes[node];
    if n.kind == N_VARIABLE { check_variable(p, c, node); }
    else if n.kind == N_FUNCTION {
        if n.type_id >= 0 { c.scopes[n.scope].parent = c.scope; }
        else { p.nodes[node].scope = c.scope; }
        if n.symbol >= 0 { p.symbols[n.symbol].index = 1; }
        check_prepare_function(p, c, node);
    }
    else if n.kind == N_STRUCT || n.kind == N_ENUM {
        if n.third < 0 { check_layout_nominal(p, c, n.type_id); }
    } else if n.kind == N_ALIAS { check_resolve_type(p, c, n.left); }
    else if n.kind == N_IMPORT || n.kind == N_NAMESPACE || n.kind == N_EXTERN || n.kind == N_EMPTY { }
    else { check_expression(p, c, node, TYPE_VOID); }
    c.returning = returning;
}

fn check_name_literal(p: Program&, token: i64) -> i64 {
    var text = p.tokens[token]; text.kind = T_STRLIT; text.text_start = text.start; text.text_len = text.end - text.start;
    let tid = p.tokens.len; p.tokens.push(text);
    let id = new_node(p, N_STRING, tid); p.nodes[id].type_id = TYPE_STRING;
    return id;
}
fn check_expansion_type(p: Program&, node: i64, type_id: i64) {
    let n = p.nodes[node];
    if type_id < 0 || n.first >= 0 || (n.flags & F_VARIABLE_MODE) != 0 && p.types[type_id].kind != TY_ENUM {
        p.nodes[node].type_id = -1; p.nodes[node].expansion_binding = -3; return;
    }
    var result = type_id;
    if (n.flags & TF_CONST) != 0 { result = check_const_type(p, result); }
    if (n.flags & F_VARIABLE_MODE) != 0 { var qualified = p.types[result]; qualified.flags |= F_VARIABLE_MODE; result = add_type(p, qualified); }
    p.nodes[node].type_id = result; p.nodes[node].expansion_binding = -1;
}
recursive fn check_expand_replace(p: Program&, node: i64, binding: i64, value: i64, accessor: i64, actual: i64, type_id: i64, owner: i64, pattern: bool = false) {
    if node < 0 { return; }
    let n = p.nodes[node];
    if n.expansion_binding == binding && binding >= 0 {
        if n.kind == N_NAME {
            if value >= 0 { let next = n.next; p.nodes[node] = p.nodes[value]; p.nodes[node].next = next; return; }
            p.nodes[node].expansion_binding = -2;
        } else if n.kind == N_TYPE_NAME && accessor < 0 { check_expansion_type(p, node, type_id); }
    }
    if n.expansion_binding == accessor && accessor >= 0 {
        if type_id < 0 {
            if n.kind == N_MEMBER || n.kind == N_BINDING { p.nodes[node].token = actual; p.nodes[node].aux = owner; p.nodes[node].expansion_binding = -1; }
            else if n.kind == N_TYPE_NAME { p.nodes[node].type_id = -1; p.nodes[node].expansion_binding = -3; }
            else if n.kind == N_NAME { p.nodes[node].expansion_binding = -2; }
        } else if n.kind == N_TYPE_NAME { check_expansion_type(p, node, type_id); }
        else if n.kind == N_NAME {
            if pattern { p.nodes[node].token = actual; p.nodes[node].type_id = type_id; p.nodes[node].expansion_binding = -1; }
            else if p.types[type_id].declaration >= 0 && p.nodes[p.types[type_id].declaration].kind == N_VARIANT && p.nodes[p.types[type_id].declaration].first < 0 {
                p.nodes[node] = Node { kind: N_RECORD, token: n.token, next: n.next, type_id: type_id, symbol: p.types[type_id].declaration, flags: F_CHECKED };
            } else { p.nodes[node].expansion_binding = -2; }
        }
    }
    if n.kind == N_IMPORT { return; }
    var child = n.first;
    while child >= 0 { let next = p.nodes[child].next; check_expand_replace(p, child, binding, value, accessor, actual, type_id, owner, n.kind == N_PATTERN); child = next; }
    for first in [n.left, n.right, n.third] {
        var part = first;
        while part >= 0 { let next = p.nodes[part].next; check_expand_replace(p, part, binding, value, accessor, actual, type_id, owner); part = next; }
    }
}
fn check_expansion_integer(p: Program&, c: Checker&, node: i64) -> bool {
    var work = CheckList {}; var visited = CheckList {}; check_list_push(c, work, node); var work_index = 0;
    while work_index < work.count {
        let id = check_list_at(c, work, work_index); work_index += 1;
        if id < 0 { return false; }
        var seen = false; for index in 0..visited.count { if check_list_at(c, visited, index) == id { seen = true; break; } }
        if seen { continue; } check_list_push(c, visited, id);
        let n = p.nodes[id];
        if n.kind == N_INTEGER { continue; }
        if n.kind == N_NAME {
            var symbol = n.symbol; if symbol < 0 { symbol = check_lookup_name(p, c, id); }
            if symbol < 0 || (p.symbols[symbol].flags & (S_GLOBAL | S_MUTABLE)) != S_GLOBAL { return false; }
            let declaration = p.symbols[symbol].node;
            if declaration < 0 || p.nodes[declaration].kind != N_VARIABLE { return false; }
            let annotation = p.nodes[declaration].left;
            if annotation >= 0 && !check_integer(check_numeric_value_type(p, check_resolve_type(p, c, annotation))) { return false; }
            check_list_push(c, work, p.nodes[declaration].right); continue;
        }
        if n.kind == N_UNARY && (n.integer == T_MINUS || n.integer == T_BITNOT) { check_list_push(c, work, n.left); continue; }
        if n.kind == N_BINARY && (n.integer == T_PLUS || n.integer == T_MINUS || n.integer == T_MUL || n.integer == T_DIV || n.integer == T_MOD || n.integer == T_BITAND || n.integer == T_BITOR || n.integer == T_XOR || n.integer == T_SHL || n.integer == T_SHR) {
            check_list_push(c, work, n.left); check_list_push(c, work, n.right); continue;
        }
        if n.kind == N_CAST && (n.flags & F_SYNTHETIC) != 0 && check_integer(check_numeric_value_type(p, check_resolve_type(p, c, n.right))) { check_list_push(c, work, n.left); continue; }
        if n.kind == N_MEMBER && (token_is(p, n.token, "len") || token_is(p, n.token, "cap")) { continue; }
        if n.kind == N_CALL && n.symbol >= 0 && (p.symbols[n.symbol].flags & S_BUILTIN) != 0 && (p.symbols[n.symbol].index == 21 || p.symbols[n.symbol].index == 22) { continue; }
        return false;
    }
    return true;
}
fn check_expansion_fixed(p: Program&, value: i64, type_id: i64, token: i64) -> i64 {
    let result = new_node(p, N_CAST, token); p.nodes[result].left = value;
    p.nodes[result].right = operation_type(p, type_id, token); p.nodes[result].flags = F_SYNTHETIC;
    return result;
}
recursive fn check_expansion_constant(p: Program&, c: Checker&, node: i64, visiting: CheckList&) -> i64 {
    if node < 0 { return -1; }
    let n = p.nodes[node]; var bindings = CheckList {};
    if n.kind == N_NAME {
        var symbol = n.symbol; if symbol < 0 { symbol = check_lookup_name(p, c, node); }
        if symbol >= 0 && (p.symbols[symbol].flags & (S_GLOBAL | S_MUTABLE)) == S_GLOBAL {
            let declaration = p.symbols[symbol].node;
            if declaration >= 0 && p.nodes[declaration].kind == N_VARIABLE && check_list_count(p, p.nodes[declaration].right) == 1 {
                for index in 0..visiting.count { if check_list_at(c, visiting, index) == symbol { diagnose(p, n.token, "cycle in const for constant initializer"); return -1; } }
                check_list_push(c, visiting, symbol);
                let value = check_expansion_constant(p, c, p.nodes[declaration].right, visiting); if value < 0 { return -1; }
                let written = p.nodes[declaration].left;
                if written < 0 { return value; }
                let ty = check_numeric_value_type(p, check_resolve_type(p, c, written));
                let v = p.nodes[value];
                if check_float(ty) && (v.kind == N_INTEGER || v.kind == N_FLOAT) {
                    let f = new_node(p, N_FLOAT, n.token); var number = v.float_value;
                    if v.kind == N_INTEGER { if (v.flags & F_UNSIGNED) != 0 { number = (v.integer as! u64) as f64; } else { number = v.integer as f64; } }
                    if ty == TYPE_F32 {
                        if v.kind == N_INTEGER { if (v.flags & F_UNSIGNED) != 0 { number = ((v.integer as! u64) as f32) as f64; } else { number = (v.integer as f32) as f64; } }
                        else { number = (number as! f32) as f64; }
                    }
                    p.nodes[f].float_value = number; return check_expansion_fixed(p, f, ty, n.token);
                }
                if check_integer(ty) && v.kind == N_INTEGER { return check_expansion_fixed(p, value, ty, n.token); }
                return value;
            }
        }
    }
    if n.kind == N_BOOL || n.kind == N_FLOAT || n.kind == N_STRING { return check_clone(p, c, node, bindings); }
    if n.kind == N_UNARY && n.integer == T_MINUS && p.nodes[n.left].kind == N_FLOAT {
        let value = new_node(p, N_FLOAT, n.token); p.nodes[value].float_value = -p.nodes[n.left].float_value; return value;
    }
    if n.kind == N_CAST && (n.flags & F_SYNTHETIC) != 0 {
        let value = check_expansion_constant(p, c, n.left, visiting);
        let ty = check_resolve_type(p, c, n.right);
        if value >= 0 && ty >= 0 { return check_expansion_fixed(p, value, ty, n.token); }
    }
    var constant = CheckConstant {};
    if check_expansion_integer(p, c, node) { constant = check_constant(p, c, node, 0); }
    if constant.valid {
        let complement = check_complement_input(p, c, node);
        if complement.valid {
            let input = new_node(p, N_INTEGER, n.token); p.nodes[input].integer = complement.value;
            let value = new_node(p, N_UNARY, n.token); p.nodes[value].integer = T_BITNOT; p.nodes[value].left = input; return value;
        }
        let value = new_node(p, N_INTEGER, n.token); p.nodes[value].integer = constant.value;
        if constant.type_id == TYPE_U64 && constant.value < 0 { p.nodes[value].flags |= F_UNSIGNED; }
        if !constant.literal { return check_expansion_fixed(p, value, constant.type_id, n.token); }
        return value;
    }
    diagnose(p, n.token, "const for source requires a scalar or string constant or supported integer computation"); return -1;
}
recursive fn check_expand_const_for(p: Program&, c: Checker&, node: i64) -> i64 {
    let n = p.nodes[node]; let body = p.nodes[n.right];
    let result = new_node(p, body.kind, n.token);
    p.nodes[result].flags = body.flags;
    let first_binding = n.first; var second_binding = -1;
    if first_binding >= 0 { second_binding = p.nodes[first_binding].next; }
    if first_binding < 0 { diagnose(p, n.token, "const for has no binding"); return result; }
    var entries = CheckList {}; var owner = -1;
    if n.integer == 0 || n.integer == 2 {
        var entry = n.left;
        while entry >= 0 { check_list_push(c, entries, entry); entry = p.nodes[entry].next; }
    } else {
        let type_id = check_resolve_type(p, c, n.left);
        if type_id < 0 { return result; }
        owner = type_id;
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
    if c.expansion_nodes > 100000 { return result; }
    for entry_index in 0..entries.count { let entry = check_list_at(c, entries, entry_index);
        var bindings = CheckList {}; var value = -1; var accessor = -1; var actual = -1; var ty = -1;
        if n.integer == 0 {
            check_constant_names(p, c, entry);
            var visiting = CheckList {}; value = check_expansion_constant(p, c, entry, visiting);
            if value < 0 { continue; }
        } else if n.integer == 2 { ty = check_resolve_type(p, c, entry); }
        else {
            value = check_name_literal(p, p.nodes[entry].token); actual = p.nodes[entry].token;
            if second_binding < 0 { diagnose(p, n.token, "reflection expansion requires name and accessor bindings"); continue; }
            accessor = p.nodes[second_binding].expansion_binding;
            if n.integer == 3 { ty = p.nodes[entry].type_id; }
        }
        let was_expanding = c.expanding; c.expanding = true;
        let copy = check_clone(p, c, n.right, bindings); c.expanding = was_expanding;
        if copy < 0 || c.expansion_nodes > 100000 { break; }
        check_expand_replace(p, copy, p.nodes[first_binding].expansion_binding, value, accessor, actual, ty, owner);
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
            if p.nodes[expansion].kind != N_BLOCK { check_expand_children(p, c, expansion); }
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
recursive fn check_alias_names(p: Program&, c: Checker&, node: i64) {
    if node < 0 { return; }
    let n = p.nodes[node];
    if n.kind == N_TYPE_NAME && n.left < 0 && check_primitive_token(p.tokens[n.token].kind) < 0 {
        let symbol = check_lookup_name(p, c, node, S_TYPE);
        if symbol < 0 { diagnose(p, n.token, "unknown type name in alias"); }
        else if p.symbols[symbol].node >= 0 && p.nodes[p.symbols[symbol].node].kind == N_ALIAS { check_alias_declaration(p, c, p.symbols[symbol].node); }
    }
    check_alias_names(p, c, n.first); check_alias_names(p, c, n.left);
    check_alias_names(p, c, n.right); check_alias_names(p, c, n.third); check_alias_names(p, c, n.next);
}
recursive fn check_alias_declaration(p: Program&, c: Checker&, node: i64) {
    let n = p.nodes[node];
    if (n.flags & F_CHECKED) != 0 { diagnose(p, n.token, "cyclic type alias"); return; }
    if (n.flags & F_REACHABLE) != 0 { return; }
    p.nodes[node].flags |= F_CHECKED;
    let saved = c.scope; c.scope = p.symbols[n.symbol].scope;
    check_alias_names(p, c, n.left); c.scope = saved;
    p.nodes[node].flags &= ~F_CHECKED; p.nodes[node].flags |= F_REACHABLE;
}
recursive fn check_qualified_body_types(p: Program&, c: Checker&, node: i64) {
    if node < 0 { return; }
    let n = p.nodes[node]; let saved = c.scope;
    // Only a declared node's scope is a scope ID; a nested function's still
    // holds its namespace token and keeps its enclosing function's scope.
    if (n.kind == N_NAMESPACE || (n.kind == N_FUNCTION || n.kind == N_STRUCT || n.kind == N_ENUM) && n.symbol >= 0) && n.scope >= 0 { c.scope = n.scope; }
    if n.kind == N_TYPE_NAME && n.left < 0 {
        let symbol = check_lookup_name(p, c, node, S_TYPE);
        if n.aux > 1 && symbol < 0 { diagnose(p, n.token, "unknown qualified type name"); }
        if symbol >= 0 && p.symbols[symbol].node >= 0 && p.nodes[p.symbols[symbol].node].kind == N_STRUCT && (n.flags & F_VARIABLE_MODE) != 0 {
            diagnose(p, n.token, "variable mode applies only to an enum type");
        }
    }
    if n.kind != N_IMPORT {
        check_qualified_body_types(p, c, n.first); check_qualified_body_types(p, c, n.left);
        check_qualified_body_types(p, c, n.right); check_qualified_body_types(p, c, n.third);
    }
    c.scope = saved; check_qualified_body_types(p, c, n.next);
}

fn check_foreign_return(p: Program&, function_node: i64) -> bool {
    var names: i64[>..] = [p.nodes[function_node].token]; var work: i64[>..] = [p.nodes[function_node].right];
    var at = 0;
    while at < work.len {
        let id = work[at]; at += 1; if id < 0 { continue; }
        let n = p.nodes[id];
        if n.kind == N_FUNCTION { names.push(n.token); }
        if n.kind == N_IMPORT { continue; }
        for child in [n.first, n.left, n.right, n.third, n.next] { if child >= 0 { work.push(child); } }
    }
    for id in work {
        if id < 0 { continue; } let n = p.nodes[id];
        if n.kind != N_RETURN || n.left < 0 { continue; }
        var local = false;
        for name in names { if same_name(p, name, p.nodes[n.left].token) { local = true; break; } }
        if !local { return true; }
    }
    return false;
}

fn check_unreached(p: Program&, c: Checker&, declarations: i64) {
    // A diagnostic-only root is checked with the declared parameter types.
    // Calls discovered here must not make emitted program roots reachable.
    var reachable: bool[>..] = [];
    for n in p.nodes { reachable.push((n.flags & F_REACHABLE) != 0); }
    for i in 0..declarations {
        let symbol = p.symbols[i]; if symbol.node < 0 || symbol.owner >= 0 { continue; }
        let n = p.nodes[symbol.node];
        if n.kind != N_FUNCTION || n.right < 0 || (n.flags & (F_GENERIC | F_THREAD | F_CHECKED)) != 0 { continue; }
        if library_node(p, symbol.node) { continue; }
        var specialized = false;
        for spec in c.specializations { if spec.original == symbol.node { specialized = true; break; } }
        if specialized { continue; }
        if !check_foreign_return(p, symbol.node) { check_function(p, c, symbol.node); }
    }
    for n, i in p.nodes {
        if n.kind != N_FUNCTION && n.kind != N_FUNCTION_VALUE { continue; }
        p.nodes[i].flags &= ~F_REACHABLE;
        if i < reachable.len && reachable[i] { p.nodes[i].flags |= F_REACHABLE; }
    }
}

// Type checking, with its work tables. They are released before lifetime
// analysis runs, which then reuses their storage.
fn check_program_types(p: Program&, declarations_only: bool, scope_parents: i64[>..]&, scope_depths: i64[>..]&,
                       scope_functions: i64[>..]&, pool_references: i64[>..]&) -> bool {
    if p.types.len == 0 { initialize_types(p); }
    for i in TYPE_I8..TYPE_STRING {
        if p.types[i].size > 0 { p.types[i].align = p.types[i].size; }
    }
    p.types[TYPE_STRING].size = 2 * p.pointer_bytes;
    p.types[TYPE_STRING].align = 2 * p.pointer_bytes;
    var checker_scopes: CheckScope[>..] = [];
    var checker_variables: CheckVariable[>..] = [];
    var checker_variable_lookup: i64[>..] = [];
    var checker_roots: CheckRoot[>..] = []; var checker_root_nodes: i64[>..] = []; var checker_root_symbols: i64[>..] = [];
    var checker_environments: CheckEnvironment[>..] = []; var checker_environment_heads: i64[>..] = [];
    var checker_outer_exits: CheckOuterExit[>..] = [];
    var checker_node_nonnegative: i64[>..] = [];
    var checker_syntax_nodes: Node[>..] = []; var checker_syntax_lookup: i64[>..] = [];
    var checker_effects: CheckEffect[>..] = [];
    var checker_return_roots: CheckReturnRoot[>..] = [];
    var checker_specializations: CheckSpecialization[>..] = [];
    var checker_needs: CheckNeed[>..] = []; var checker_need_frames: CheckNeedFrame[>..] = []; var checker_need_edges: CheckNeedEdge[>..] = [];
    var checker_contextual_floats: CheckContextFloat[>..] = []; var checker_contextual_lookup: i64[>..] = [];
    var checker_bindings: TypeBinding[>..] = [];
    var checker_checking: i64[>..] = [];
    var checker_loop_stack: CheckLoop[>..] = [];
    var checker_integer_work: CheckInteger[>..] = [];
    var checker_binding_work: TypeBinding[>..] = [];
    var checker_flow_work: CheckFlow[>..] = []; var checker_flow_cursors: CheckFlowCursor[>..] = [];
    var checker_exit_work: CheckExit[>..] = [];
    var checker_interval_work: CheckInterval[>..] = [];
    var checker_render_cache: RenderKey[>..] = []; var checker_render_hooks: i64[>..] = [];
    var parameter_default_contexts: CheckDefaultCapture[>..] = [];
    var logical_kills: CheckLogicalKill[>..] = [];
    var c = Checker { scopes: checker_scopes, variables: checker_variables, variable_lookup: checker_variable_lookup, roots: checker_roots, root_nodes: checker_root_nodes, root_symbols: checker_root_symbols, effects: checker_effects, environments: checker_environments, environment_heads: checker_environment_heads, outer_exits: checker_outer_exits, syntax_nodes: checker_syntax_nodes, syntax_lookup: checker_syntax_lookup, node_nonnegative: checker_node_nonnegative, return_roots: checker_return_roots, specializations: checker_specializations, bindings: checker_bindings, needs: checker_needs, need_frames: checker_need_frames, need_edges: checker_need_edges, contextual_floats: checker_contextual_floats, contextual_lookup: checker_contextual_lookup, checking: checker_checking, loop_stack: checker_loop_stack, integer_work: checker_integer_work, binding_work: checker_binding_work, flow_work: checker_flow_work, flow_cursors: checker_flow_cursors, exit_work: checker_exit_work, interval_work: checker_interval_work, render_cache: checker_render_cache, render_hooks: checker_render_hooks, parameter_default_contexts: parameter_default_contexts, logical_kills: logical_kills };
    c.scopes.push(CheckScope { parent: -1, function_node: -1 });
    var source_id = p.first_decl_source;
    while source_id >= 0 {
        let source = p.sources[source_id];
        if source.root >= 0 { check_top_declarations(p, c, p.nodes[source.root].first); }
        source_id = source.next_decl;
    }
    let declarations = p.symbols.len;
    if declarations_only {
        let parsed_nodes = p.nodes.len;
        for i in 0..parsed_nodes { if p.nodes[i].kind == N_FUNCTION { parse_deferred_body(p, i); } }
        for i in 0..declarations { let symbol = p.symbols[i]; if symbol.node >= 0 && p.nodes[symbol.node].kind == N_ALIAS { check_alias_declaration(p, c, symbol.node); } }
        for source in p.sources { if source.root >= 0 { check_qualified_body_types(p, c, source.root); } }
        return false;
    }
    for i in 0..declarations {
        let s = p.symbols[i]; if s.node < 0 { continue; }
        let n = p.nodes[s.node]; c.scope = s.scope;
        // Library signatures are prepared when a lookup or call first reaches them.
        if n.kind == N_FUNCTION { if !library_node(p, s.node) { check_prepare_function(p, c, s.node); } }
        else if (n.kind == N_STRUCT || n.kind == N_ENUM) && n.third < 0 { check_layout_nominal(p, c, s.type_id); }
        else if n.kind == N_ALIAS { p.symbols[i].type_id = check_resolve_type(p, c, n.left); }
    }
    c.scope = 0; c.initializing_globals = true;
    for i in 0..declarations {
        let s = p.symbols[i];
        if (s.flags & S_GLOBAL) != 0 && s.node >= 0 && p.nodes[s.node].kind == N_VARIABLE {
            check_variable(p, c, s.node);
            let vi = check_variable_index(c, i);
            if vi >= 0 { c.variables[vi].global_initialized = true; c.variables[vi].assigned = true; c.variables[vi].maybeassigned = true; }
        }
    }
    c.initializing_globals = false;
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
    // Workers are independent program roots, including workers not spawned by main.
    for i in 0..declarations {
        let symbol = p.symbols[i]; if symbol.node < 0 { continue; }
        let n = p.nodes[symbol.node];
        if n.kind == N_FUNCTION && (n.flags & (F_THREAD | F_GENERIC)) == F_THREAD { check_function(p, c, symbol.node); }
    }
    check_unreached(p, c, declarations);
    for variable in c.variables {
        let s = p.symbols[variable.symbol]; let ty = s.type_id;
        if ty >= 0 && p.types[ty].kind == TY_ARRAY && p.types[ty].element < 0 {
            diagnose(p, s.name_token, "empty array element type was never determined");
        }
    }
    check_validate_type_uses(p); check_validate_program(p);
    for scope in c.scopes { scope_parents.push(scope.parent); scope_depths.push(scope.depth); scope_functions.push(scope.function_node); }
    var pool_types: bool[>..] = [];
    for ty in p.types { pool_types.push(false); }
    for node, id in p.nodes {
        let ty = node.type_id;
        if ty < 0 || pool_types[ty] || p.types[ty].kind != TY_REF || p.types[ty].length_storage < 0 || p.types[ty].pool < 0 || check_has_generic(p, p.types[ty].element, 0) { continue; }
        pool_types[ty] = true; pool_references.push(id);
    }
    return true;
}
fn check_program(p: Program&, declarations_only: bool = false) {
    var scope_parents: i64[>..] = []; var scope_depths: i64[>..] = []; var scope_functions: i64[>..] = [];
    var pool_references: i64[>..] = [];
    if !check_program_types(p, declarations_only, scope_parents, scope_depths, scope_functions, pool_references) { return; }
    check_lifetimes(p, scope_parents, scope_depths, scope_functions, pool_references);
    if p.diagnostics.len == 0 { check_validate_thread_globals(p); }
}
