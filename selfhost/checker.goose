import model;
import sources;
import checker_validation;
import checker_operations;
import checker_lifetimes;
import checker_rendering;
import os;

// Stable IDs are the only links held while tables grow. Scope, flow and
// provenance are checker work tables; checked nodes contain backend contracts.
struct CheckScope { parent: i64, function_node: i64, depth: i64 = 0, namespace_node: i64 = -1, frame_root: i64 = 0, first_variable: i64 = -1, outer_exits: i64 = -1, decl_count: i32 = 0, small_decls: i32[4] = [-1; 4], small_hashes: i32[4] = [0; 4] }
struct CheckPointee { type_id: i64, token: i64, chain: i64 }
struct TypeBinding { parameter: i64, value: i64, next: i64 = -1, literal: bool = false }
struct CheckList { first: i64 = -1, last: i64 = -1, count: i64 = 0 }
struct CheckSpan { first: i64 = 0, count: i64 = 0 }
struct CheckInteger { value: i64, next: i64 = -1 }
struct CheckContextFloat { node: i64, original: i64, bindings: CheckList }
struct CheckChoice { symbol: i64 = -1, bindings: CheckList, ambiguous: bool = false, hof: bool = false, converting: bool = false, written: i64 = 0 }
struct CheckVariable {
    symbol: i64, assigned: bool = false, maybeassigned: bool = false, global_initialized: bool = false,
    readonly: bool = false, narrowed: i64 = -1, next_frame: i64 = -1, literal_use: i64 = -1, writable_use: i64 = -1,
    nonnegative: i64 = -2, nonnegative_use: i64 = -1,
    // The flow clock when declared, and scratch tags for one delta or join.
    born: i64 = 0, seen: i64 = -1, seen_at: i64 = -1,
}
struct CheckEnvironment {
    symbol: i64, assigned: bool, maybeassigned: bool, narrowed: i64, readonly: bool, next: i64 = -1,
}
struct CheckRoot { value: i64, root: i64, kind: i64 = 0, next: i64 = -1 }
// Each function's effects are a list in recording order (effect_lists).
struct CheckEffect { function_node: i64, root: i64, kind: i64, next: i64 = -1 }
struct CheckEffectList { first: i64 = -1, last: i64 = -1 }
// An effect indexed under (function, root, kind): its kind when recorded, and
// kind 0 again once a join rewrites it to 0. A lookup checks the effect's
// current fields.
struct CheckEffectKey { effect: i64, kind: i64, next: i64 = -1 }
// Each function's return roots are a list in recording order (return_root_lists).
struct CheckReturnRoot { function_node: i64, index: i64, root: i64, kind: i64 = 0, next: i64 = -1 }
struct CheckNeed { function_node: i64, target: i64 }
struct CheckNeedFrame { function_node: i64, parent: i64 }
struct CheckNeedEdge { function_node: i64, token: i64, path: i64 }
struct CheckSpecialization { original: i64, symbol: i64, binding_start: i64, binding_count: i64, next_spec: i64 = -1 }
struct CheckSpecializationRow { head: i64 = -1, tail: i64 = -1 }
// A type a literal parameter adapted to inside its function (upstream §7.7):
// each call's literal argument must fit it.
struct CheckLiteralUse { symbol: i64, type_id: i64 }
// A variable's flow state now and at a mark (a delta entry).
struct CheckFlow {
    variable: i64, assigned: bool, maybeassigned: bool, narrowed: i64 = -1,
    old_assigned: bool = false, old_maybeassigned: bool = false, old_narrowed: i64 = -1,
}
// A variable's flow state before a logged write.
struct CheckFlowUndo { variable: i64, assigned: bool, maybeassigned: bool, narrowed: i64 = -1 }
// Where a construct's branches start: the log length, the flow clock (variables
// declared later are local to the construct), the enclosing mark's clock and
// the delta and exit table lengths.
struct CheckFlowMark { trail: i64 = 0, stamp: i64 = -1, outer: i64 = -1, work: i64 = 0, exits: i64 = 0, narrowed: i64 = 0 }
// A function being checked, and the mark its exits are recorded against.
struct CheckActive { function_node: i64, mark: CheckFlowMark }
// One variable's meet over several states.
struct CheckFlowJoin {
    variable: i64, assigned: bool = true, maybeassigned: bool = false, narrowed: i64 = -1, count: i64 = 0, empty: bool = true,
    base_assigned: bool = false, base_maybeassigned: bool = false, base_narrowed: i64 = -1,
}
// flow is a delta since the target's mark.
struct CheckExit { target: i64, flow: CheckSpan, backedge: bool = false }
// flow indexes outer_flows: (variable, assigned, maybeassigned) additions.
struct CheckOuterExit { target: i64, flow: CheckSpan, next: i64 = -1 }
struct CheckLoop { node: i64, scope: i64, function_node: i64, result: i64 = -1, values: CheckList = CheckList {}, breaks: bool = false, expected: i64 = -1, returning: bool = false, mark: CheckFlowMark = CheckFlowMark {} }
struct CheckLogicalKill { node: i64, symbol: i64 }

struct CheckDefaultCapture { node: i64, function_node: i64, floor: i64 }

struct Checker {
    literal_comparison: bool = false, default_body: bool = false, render_reference: bool = false,
    format_scan_end: i64 = 0, has_format_hooks: bool = false,
    scopes: CheckScope[>..]&, variables: CheckVariable[>..]&, variable_lookup: i64[>..]&,
    roots: CheckRoot[>..]&, root_nodes: i64[>..]&, root_symbols: i64[>..]&, effects: CheckEffect[>..]&, effect_lists: CheckEffectList[>..]&, effect_keys: CheckEffectKey[>..]&, effect_key_heads: i64[>..]&,
    // Scope names (check_link_symbol): buckets, each symbol's link scope and name hash, symbols in link order.
    name_table: i32[>..]&, link_scopes: i32[>..]&, name_hashes: i32[>..]&, linked: i32[>..]&,
    environments: CheckEnvironment[>..]&, environment_heads: i64[>..]&,
    outer_exits: CheckOuterExit[>..]&,
    syntax_nodes: Node[>..]&, syntax_lookup: i64[>..]&,
    node_nonnegative: i64[>..]&,
    clone_syntax: bool = false, syntax_body: i64 = -1, syntax_function: i64 = -1, optional_globals: bool = false,
    return_roots: CheckReturnRoot[>..]&, return_root_lists: CheckEffectList[>..]&,
    specializations: CheckSpecialization[>..]&, specialization_rows: CheckSpecializationRow[>..]&, bindings: TypeBinding[>..]&,
    choice_args: i64[>..]&,
    needs: CheckNeed[>..]&, need_frames: CheckNeedFrame[>..]&, need_edges: CheckNeedEdge[>..]&, need_path: i64 = -1,
    contextual_floats: CheckContextFloat[>..]&, contextual_lookup: i64[>..]&,
    checking: CheckActive[>..]&, loop_stack: CheckLoop[>..]&,
    integer_work: CheckInteger[>..]&, binding_work: TypeBinding[>..]&, flow_work: CheckFlow[>..]&, flow_trail: CheckFlowUndo[>..]&,
    flow_join: CheckFlowJoin[>..]&, narrowed_variables: i64[>..]&, outer_flows: CheckFlow[>..]&,
    format_symbols: i64[>..]&, operation_functions: i64[>..]&, component_symbols: i64[>..]&, exit_work: CheckExit[>..]&, interval_work: CheckInterval[>..]&, render_cache: RenderKey[>..]&, render_hooks: i64[>..]&,
    scope: i64 = 0, function_node: i64 = -1, result_type: i64 = -1,
    next_slot: i64 = 0, reachable: bool = true, tuple_context: bool = false, returning: bool = false,
    parameter_default_contexts: CheckDefaultCapture[>..]&,
    logical_kills: CheckLogicalKill[>..]&,
    literal_uses: CheckLiteralUse[>..]&,
    implicit_type_scope: i64 = -1, implicit_types: CheckList = CheckList {},
    type_build_depth: i64 = 0, pointees: CheckPointee[>..]&,
    parameter_default_function: i64 = -1, parameter_default_floor: i64 = -1,
    // The call that left out the parameter default being checked, and the
    // function that call is in: src_file() and src_line() written in the
    // default report that call (upstream a5579b1).
    call_location: i64 = -1, call_location_function: i64 = -1,
    // flow_stamp is the innermost open mark's clock; format_symbol_scan the
    // symbols already searched for format overloads.
    flow_clock: i64 = 0, flow_stamp: i64 = -1, format_symbol_scan: i64 = 0, narrowed_count: i64 = 0,
    // The next expression checked is the base of an index or slice, or of a
    // member path being written: a local array or struct there need not be
    // assigned as a whole (upstream LValueBase, typecheck_exprs.h).
    path_base: bool = false,
    // The record literal a declaration initializes directly: the only place
    // a root owner is constructed (upstream rootinit).
    root_record: i64 = -1,
    // check_list_at's position: the list it walked, the index and the item.
    list_first: i64 = -1, list_index: i64 = -1, list_item: i64 = -1,
    list_other_first: i64 = -1, list_other_index: i64 = -1, list_other_item: i64 = -1,
    returns: bool = false, initializing_globals: bool = false, expanding: bool = false, expansion_nodes: i64 = 0, inference_depth: i64 = 0, type_indirections: i64 = 0, checking_count: i64 = 0, loop_count: i64 = 0, default_fields: CheckList = CheckList {}, backedges: CheckList = CheckList {}, type_chain: i64 = -1,
    // `defer` (§6.6): the bodies being checked (their N_DEFER entries on
    // loop_stack), every checked statement with its function, and the locals
    // of that function each body names (pairs), for check_defers.
    defer_bodies: i64 = 0, defers: CheckList = CheckList {}, defer_mentions: CheckList = CheckList {},
    in_unreached: bool = false, unreached_marked: i64[>..]&,
    batch_out: CheckBodyBatch[>..]&, batch_index: i32[>..]&,
    batch_patches: CheckBodyPatch[>..]&, batch_events: CheckBodyEvent[>..]&,
    batch_pending_apply: i32[>..]&, batch_proof_end: i64 = 0,
    batch_deferred: i64 = 0, batch_committed: i64 = 0,
}

fn check_push_loop(c: Checker&, value: CheckLoop) {
    if c.loop_count == c.loop_stack.len { c.loop_stack.push(value); } else { c.loop_stack[c.loop_count] = value; }
    c.loop_count += 1;
}
fn check_push_function(c: Checker&, value: i64, mark: CheckFlowMark) {
    let active = CheckActive { function_node: value, mark: mark };
    if c.checking_count == c.checking.len { c.checking.push(active); } else { c.checking[c.checking_count] = active; }
    c.checking_count += 1;
}

fn check_list_push(c: Checker&, list: CheckList&, value: i64) {
    let id = c.integer_work.len; c.integer_work.push(CheckInteger { value: value });
    if list.last < 0 { list.first = id; } else { c.integer_work[list.last].next = id; }
    list.last = id; list.count += 1;
}
fn check_list_at(c: Checker&, list: CheckList&, index: i64) -> i64 {
    if index == 0 {
        if list.first < 0 { return -1; }
        return c.integer_work[list.first].value;
    }
    // Lists are read in order, often two in alternation (candidates and
    // arguments): resume from the last position read in the same list. The
    // work array only grows and links only on append, so a position stays valid.
    var item = list.first; var at = 0;
    if list.first >= 0 && c.list_first != list.first && c.list_other_first == list.first {
        let first = c.list_first; let position = c.list_index; let found = c.list_item;
        c.list_first = c.list_other_first; c.list_index = c.list_other_index; c.list_item = c.list_other_item;
        c.list_other_first = first; c.list_other_index = position; c.list_other_item = found;
    }
    if list.first >= 0 && c.list_first == list.first && c.list_index >= 0 && c.list_index <= index { item = c.list_item; at = c.list_index; }
    while item >= 0 && at < index { item = c.integer_work[item].next; at += 1; }
    if item < 0 { return -1; }
    if c.list_first != list.first {
        c.list_other_first = c.list_first; c.list_other_index = c.list_index; c.list_other_item = c.list_item;
    }
    c.list_first = list.first; c.list_index = index; c.list_item = item;
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
inline fn check_specialization_head(c: Checker&, original: i64) -> i64 {
    if original < 0 || original >= c.specialization_rows.len { return -1; }
    return c.specialization_rows[original].head;
}
fn check_add_specialization(c: Checker&, spec: CheckSpecialization) {
    let id = c.specializations.len;
    c.specializations.push(spec);
    let original = spec.original;
    if original >= c.specialization_rows.len { c.specialization_rows.resize(original + 1, CheckSpecializationRow {}); }
    let tail = c.specialization_rows[original].tail;
    if tail < 0 { c.specialization_rows[original].head = id; }
    else { c.specializations[tail].next_spec = id; }
    c.specialization_rows[original].tail = id;
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
inline fn check_integer_bits(type_id: i64) -> i64 {
    if type_id == TYPE_I8 || type_id == TYPE_U8 { return 8; }
    if type_id == TYPE_I16 || type_id == TYPE_U16 { return 16; }
    if type_id == TYPE_I32 || type_id == TYPE_U32 { return 32; }
    return 64;
}
inline fn check_unsigned(type_id: i64) -> bool {
    return type_id == TYPE_U8 || type_id == TYPE_U16 || type_id == TYPE_U32 || type_id == TYPE_U64;
}
inline fn check_integer(type_id: i64) -> bool { return type_id >= TYPE_I8 && type_id <= TYPE_U64; }
inline fn check_float(type_id: i64) -> bool { return type_id == TYPE_F32 || type_id == TYPE_F64; }
inline fn check_numeric(type_id: i64) -> bool { return check_integer(type_id) || check_float(type_id); }
inline fn check_min(type_id: i64) -> i64 {
    if check_unsigned(type_id) { return 0; }
    if type_id == TYPE_I8 { return -128; }
    if type_id == TYPE_I16 { return -32768; }
    if type_id == TYPE_I32 { return -2147483648; }
    return -9223372036854775808;
}
inline fn check_max(type_id: i64) -> i64 {
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
    let at: const Type& = p.types[a]; let bt: const Type& = p.types[b];
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
    var id = type_find(p, kind, element, count, flags, declaration);
    while id >= 0 {
        let t: const Type& = p.types[id];
        if t.kind == kind && t.element == element && t.count == count &&
           t.declaration == declaration && t.flags == flags &&
           (kind != TY_REF || t.length_storage < 0 && t.pool < 0) { return id; }
        id = p.type_links[id].next;
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
    var id = type_find(p, TY_ARRAY, element, count, flags, -1);
    while id >= 0 {
        let t: const Type& = p.types[id];
        if t.kind == TY_ARRAY && !t.length_explicit && t.length_storage == default_length && t.element == element && t.count == count &&
           t.array_kind == array_kind && t.flags == flags { return id; }
        id = p.type_links[id].next;
    }
    var size = p.control_bytes; var align = p.control_align;
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
    let cur_flags = p.types[ty].flags;
    if readonly && (cur_flags & TF_CONST) != 0 || !readonly && (cur_flags & TF_CONST) == 0 { return ty; }
    var copy = p.types[ty];
    if readonly { copy.flags |= TF_CONST; } else { copy.flags &= ~TF_CONST; }
    var id = type_find(p, copy.kind, copy.element, copy.count, copy.flags, copy.declaration);
    while id >= 0 {
        let candidate: const Type& = p.types[id];
        if candidate.kind == copy.kind && candidate.element == copy.element && candidate.count == copy.count && candidate.declaration == copy.declaration && candidate.first == copy.first && candidate.flags == copy.flags && candidate.array_kind == copy.array_kind && candidate.storage == copy.storage && candidate.length_storage == copy.length_storage && candidate.length_explicit == copy.length_explicit && candidate.pool == copy.pool && candidate.index_type == copy.index_type { return id; }
        id = p.type_links[id].next;
    }
    return add_type(p, copy);
}
inline fn check_const_type(p: Program&, ty: i64) -> i64 {
    if ty < 0 || (p.types[ty].flags & TF_CONST) != 0 { return ty; }
    return check_type_const(p, ty, true);
}
inline fn check_plain_value_type(p: Program&, ty: i64) -> i64 {
    if ty < 0 || (p.types[ty].flags & TF_CONST) == 0 || p.types[ty].kind == TY_REF || p.types[ty].kind == TY_SLICE { return ty; }
    return check_type_const(p, ty, false);
}
let CHECK_INITIAL_BUCKETS: i64 = 64;

// Every scope's names share one table, bucketed by scope and name. A chain
// holds a scope's same-named symbols in reverse link order, as a lookup expects.
inline fn check_name_bucket(c: Checker&, hash: i64, scope: i64) -> i64 {
    var h = (hash as! u64) * 11400714819323198485 ^ (scope as! u64) * 14029467366897019727;
    h ^= h >> 31; return (h & ((c.name_table.len - 1) as! u64)) as i64;
}
fn check_link_table(p: Program&, c: Checker&, symbol: i64, scope: i64, h: i64) {
    if c.link_scopes.len < p.symbols.len {
        c.link_scopes.resize(p.symbols.len, -1);
        c.name_hashes.resize(p.symbols.len, 0);
    }
    c.link_scopes[symbol] = scope as i32; c.name_hashes[symbol] = h as! i32;
    // One name per bucket at most, on average; rebuilt in link order.
    if c.name_table.len <= c.linked.len + 1 {
        var count = CHECK_INITIAL_BUCKETS; while count <= c.linked.len + 1 { count <<= 1; }
        for slot in 0..c.name_table.len { c.name_table[slot] = -1; }
        if c.name_table.len < count { c.name_table.resize(count, -1); }
        for index in 0..c.linked.len {
            let old = c.linked[index] as i64;
            let bucket = check_name_bucket(c, (c.name_hashes[old] as! u32) as i64, c.link_scopes[old] as i64);
            p.symbols[old].name_next = c.name_table[bucket] as i64; c.name_table[bucket] = old as i32;
        }
    }
    c.linked.push(symbol as i32);
    let bucket = check_name_bucket(c, h, scope);
    p.symbols[symbol].name_next = c.name_table[bucket] as i64;
    c.name_table[bucket] = symbol as i32;
}
fn check_link_symbol(p: Program&, c: Checker&, symbol: i64, scope: i64) {
    if scope < 0 { return; }
    let h = token_hash(p, p.symbols[symbol].name_token);
    let cnt = c.scopes[scope].decl_count as i64;
    if cnt < 4 {
        c.scopes[scope].small_decls[cnt] = symbol as i32;
        c.scopes[scope].small_hashes[cnt] = h as! i32;
        c.scopes[scope].decl_count = (cnt + 1) as i32;
        return;
    }
    if cnt == 4 {
        for i in 0..4 {
            let prev = c.scopes[scope].small_decls[i] as i64;
            let ph = (c.scopes[scope].small_hashes[i] as! u32) as i64;
            check_link_table(p, c, prev, scope, ph);
        }
    }
    c.scopes[scope].decl_count = (cnt + 1) as i32;
    check_link_table(p, c, symbol, scope, h);
}
inline fn check_lookup_scope(p: Program&, c: Checker&, token: i64, scope: i64, role: i64 = 0) -> i64 {
    return check_lookup_scope_hashed(p, c, token, scope, token_hash(p, token), role);
}
fn check_lookup_scope_hashed(p: Program&, c: Checker&, token: i64, scope: i64, hash: i64, role: i64 = 0) -> i64 {
    if scope < 0 || scope >= c.scopes.len { return -1; }
    let sc: const CheckScope& = c.scopes[scope];
    let cnt = sc.decl_count as i64;
    if cnt == 0 { return -1; }
    let h32 = hash as! i32;
    if cnt <= 4 {
        var k = cnt - 1;
        while k >= 0 {
            if sc.small_hashes[k] == h32 {
                let id = sc.small_decls[k] as i64;
                let symbol: const Symbol& = p.symbols[id];
                if same_name(p, symbol.name_token, token) {
                    if role == 0 || (symbol.flags & role) != 0 { return id; }
                    if role == S_FUNCTION && symbol.node >= 0 {
                        let kind = p.nodes[symbol.node].kind;
                        if (symbol.flags & (S_GLOBAL | S_FUNCTION | S_TYPE)) == 0 && kind != N_NAMESPACE || kind == N_TYPE_PARAM { return id; }
                    }
                }
            }
            k -= 1;
        }
        return -1;
    }
    if c.name_table.len == 0 { return -1; }
    let bucket = check_name_bucket(c, hash, scope);
    let scope32 = scope as i32;
    var id = c.name_table[bucket] as i64;
    while id >= 0 {
        let symbol: const Symbol& = p.symbols[id];
        if c.link_scopes[id] == scope32 && c.name_hashes[id] == h32 && same_name(p, symbol.name_token, token) {
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

inline fn check_lookup(p: Program&, c: Checker&, token: i64, scope: i64, role: i64 = 0) -> i64 {
    return check_lookup_hashed(p, c, token, scope, token_hash(p, token), role);
}
fn check_lookup_hashed(p: Program&, c: Checker&, token: i64, scope: i64, hash: i64, role: i64) -> i64 {
    var current = scope;
    let h32 = hash as! i32;
    while current > 0 && c.scopes[current].namespace_node < 0 {
        let function_node = c.scopes[current].function_node;
        var at = current; var parameter = -1; var function_symbol = -1; var type_symbol = -1;
        while at > 0 && c.scopes[at].namespace_node < 0 && c.scopes[at].function_node == function_node {
            let sc: const CheckScope& = c.scopes[at];
            let cnt = sc.decl_count as i64;
            if cnt > 0 {
                var may_hit = cnt > 4;
                if !may_hit {
                    var k = cnt - 1;
                    while k >= 0 {
                        if sc.small_hashes[k] == h32 { may_hit = true; break; }
                        k -= 1;
                    }
                }
                if may_hit {
                    let found = check_lookup_scope_hashed(p, c, token, at, hash, role);
                    if found >= 0 {
                        let symbol: const Symbol& = p.symbols[found];
                        if (symbol.flags & S_FUNCTION) != 0 { if function_symbol < 0 { function_symbol = found; } }
                        else if (symbol.flags & S_TYPE) != 0 {
                            if symbol.node >= 0 && p.nodes[symbol.node].kind == N_TYPE_PARAM { if parameter < 0 { parameter = found; } }
                            else if type_symbol < 0 { type_symbol = found; }
                        } else { return found; }
                    }
                }
            }
            at = sc.parent;
        }
        if parameter >= 0 { return parameter; }
        if function_symbol >= 0 { return function_symbol; }
        if type_symbol >= 0 { return type_symbol; }
        current = at;
    }
    loop {
        let sc: const CheckScope& = c.scopes[current];
        let cnt = sc.decl_count as i64;
        if cnt > 0 {
            var may_hit = cnt > 4;
            if !may_hit {
                var k = cnt - 1;
                while k >= 0 {
                    if sc.small_hashes[k] == h32 { may_hit = true; break; }
                    k -= 1;
                }
            }
            if may_hit {
                var found = check_lookup_scope_hashed(p, c, token, current, hash, role);
                if role == 0 { found = check_global_value(p, found); }
                if found >= 0 { return found; }
            }
        }
        if current <= 0 { return -1; }
        current = sc.parent;
    }
}
// The namespace among the declarations of one name in one scope. A
// namespace's name is no declaration of the scope it is in, so a function,
// type or global of that name stands beside it (upstream §11.1).
fn check_namespace_in(p: Program&, symbol: i64) -> i64 {
    var current = symbol;
    while current >= 0 {
        let declaration = p.symbols[current].node;
        if declaration >= 0 && p.nodes[declaration].kind == N_NAMESPACE { return current; }
        current = p.symbols[current].next;
    }
    return -1;
}
// A qualifier `ns::` names a namespace, which no variable hides.
fn check_lookup_namespace(p: Program&, c: Checker&, token: i64, scope: i64) -> i64 {
    let hash = token_hash(p, token); var current = scope;
    loop {
        if current >= 0 && current < c.scopes.len && c.scopes[current].decl_count > 0 {
            let found = check_namespace_in(p, check_lookup_scope_hashed(p, c, token, current, hash));
            if found >= 0 { return found; }
        }
        if current <= 0 || current >= c.scopes.len { return -1; }
        current = c.scopes[current].parent;
    }
}
fn check_lookup_name(p: Program&, c: Checker&, node: i64, role: i64 = 0) -> i64 {
    let n: const Node& = p.nodes[node];
    if n.aux <= 1 || n.integer < 0 || n.integer >= p.tokens.len {
        return check_lookup(p, c, n.token, c.scope, role);
    }
    var at = n.integer; var scope = c.scope;
    if p.tokens[at].kind == T_COLONCOLON { scope = 0; at += 1; }
    var symbol = -1;
    if at < n.token { symbol = check_lookup_namespace(p, c, at, scope); }
    else { symbol = check_lookup(p, c, at, scope, role); }
    at += 1;
    while at < n.token {
        if p.tokens[at].kind == T_COLONCOLON { at += 1; }
        if symbol < 0 { return -1; }
        let declaration = p.symbols[symbol].node;
        if declaration < 0 || p.nodes[declaration].kind != N_NAMESPACE { return -1; }
        let member_scope = p.nodes[declaration].scope;
        if at < n.token { symbol = check_namespace_in(p, check_lookup_scope(p, c, at, member_scope)); }
        else {
            symbol = check_lookup_scope(p, c, at, member_scope, role);
            if role == 0 { symbol = check_global_value(p, symbol); }
        }
        at += 1;
    }
    return symbol;
}
inline fn check_variable_index(c: Checker&, symbol: i64) -> i64 {
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

// The storage an index or relative reference type names: a global, or a
// direct field of a global root owner written `owner.field`, which stands
// for that field's storage as a synthetic global symbol.
fn check_storage_name(p: Program&, c: Checker&, node: i64) -> i64 {
    if node < 0 || p.nodes[node].kind != N_MEMBER { return check_lookup_global_name(p, c, node); }
    var base = p.nodes[node].left;
    while p.nodes[base].kind == N_MEMBER { base = p.nodes[base].left; }
    let owner = check_lookup_global_name(p, c, base);
    if owner < 0 { return -1; }
    if p.nodes[p.nodes[node].left].kind == N_MEMBER {
        diagnose(p, p.nodes[node].token, "a named array component must be a direct field of a global root owner"); return -1;
    }
    for symbol in c.component_symbols {
        if p.symbols[symbol].component_owner == owner && same_name(p, p.symbols[symbol].name_token, p.nodes[node].token) { return symbol; }
    }
    let id = p.symbols.len;
    p.symbols.push(Symbol { name_token: p.nodes[node].token, node: p.symbols[owner].node, flags: S_GLOBAL | (p.symbols[owner].flags & S_MUTABLE), component_owner: owner });
    c.component_symbols.push(id); check_resolve_component(p, id);
    return id;
}
// A named component's field and type, once its owner's type is known.
fn check_resolve_component(p: Program&, symbol: i64) -> bool {
    let s: const Symbol& = p.symbols[symbol];
    if s.component_owner < 0 || s.component >= 0 { return true; }
    let owner_type = p.symbols[s.component_owner].type_id;
    if !root_struct_type(p, owner_type) || p.types[owner_type].size < 0 { return false; }
    var field = p.nodes[p.types[owner_type].declaration].first;
    while field >= 0 { if (p.nodes[field].flags & F_PAD) == 0 && same_name(p, p.nodes[field].token, s.name_token) { break; } field = p.nodes[field].next; }
    if field < 0 || p.nodes[field].type_id < 0 { return false; }
    p.symbols[symbol].component = field; p.symbols[symbol].type_id = p.nodes[field].type_id;
    if (p.nodes[field].flags & F_CONST) != 0 || (p.types[owner_type].flags & TF_CONST) != 0 { p.symbols[symbol].flags &= ~S_MUTABLE; }
    return true;
}
fn check_finish_components(p: Program&, c: Checker&) {
    for symbol in c.component_symbols {
        if check_resolve_component(p, symbol) { continue; }
        let s: const Symbol& = p.symbols[symbol]; let owner_type = p.symbols[s.component_owner].type_id;
        var message: u8[>..] = []; message.append("in "); message.append(token_text(p, p.symbols[s.component_owner].name_token)); message.push('.'); message.append(token_text(p, s.name_token));
        if root_struct_type(p, owner_type) { message.append(": root struct "); render_type_name(p, owner_type, message); message.append(" has no field "); message.append(token_text(p, s.name_token)); }
        else { message.append(": a named array component must be a direct field of a global root owner"); }
        diagnose(p, s.name_token, message);
    }
}
// Whether an array expression is the storage a pool or index type names.
fn check_names_storage(p: Program&, pool: i64, node: i64) -> bool {
    if pool < 0 || node < 0 { return false; }
    if p.symbols[pool].component_owner < 0 { return pool == check_place_root(p, node); }
    if !check_resolve_component(p, pool) || p.nodes[node].kind != N_MEMBER || p.nodes[node].symbol != p.symbols[pool].component { return false; }
    let base = p.nodes[node].left;
    return p.nodes[base].kind == N_NAME && p.nodes[base].symbol == p.symbols[pool].component_owner;
}
fn check_declare(p: Program&, c: Checker&, node: i64, scope: i64) -> i64 {
    let n: const Node& = p.nodes[node];
    if n.symbol >= 0 { return n.symbol; }
    let n_kind = n.kind; let n_token = n.token; let n_flags = n.flags; let n_type_id = n.type_id;
    var previous = check_lookup_scope(p, c, n_token, scope);
    if n_kind == N_FUNCTION_VALUE { previous = -1; }
    var flags = 0; var slot = -1;
    if n_kind == N_FUNCTION || n_kind == N_FUNCTION_VALUE { flags |= S_FUNCTION; }
    if n_kind == N_STRUCT || n_kind == N_ENUM || n_kind == N_ALIAS || n_kind == N_TYPE_PARAM { flags |= S_TYPE; }
    if n_kind == N_PARAM { flags |= S_PARAMETER; }
    if (n_flags & F_VAR) != 0 { flags |= S_MUTABLE; }
    if (n_flags & F_EXTERN) != 0 { flags |= S_EXTERN; }
    if c.function_node < 0 && (scope == 0 || scope >= 0 && c.scopes[scope].namespace_node >= 0) && (flags & (S_FUNCTION | S_TYPE)) == 0 && n_kind != N_NAMESPACE && n_kind != N_FIELD && n_kind != N_VARIANT { flags |= S_GLOBAL; }
    var collision = previous;
    while collision >= 0 {
        let old: const Symbol& = p.symbols[collision];
        let old_namespace = old.node >= 0 && p.nodes[old.node].kind == N_NAMESPACE;
        let namespace_merge = n_kind == N_NAMESPACE && old_namespace;
        // A namespace and a declaration of its name do not collide (§11.1).
        let namespace_apart = (n_kind == N_NAMESPACE) != old_namespace;
        let overload = (flags & S_FUNCTION) != 0 && (old.flags & S_FUNCTION) != 0;
        let separate_global_roles = (scope == 0 || scope >= 0 && c.scopes[scope].namespace_node >= 0) &&
            (flags & (S_GLOBAL | S_FUNCTION | S_TYPE)) != 0 && (old.flags & (S_GLOBAL | S_FUNCTION | S_TYPE)) != 0 &&
            (flags & (S_FUNCTION | S_TYPE)) != (old.flags & (S_FUNCTION | S_TYPE));
        let discard = n_kind == N_BINDING && token_is(p, n_token, "_");
        if !discard && !namespace_merge && !namespace_apart && !overload && !separate_global_roles {
            let prev_tok = old.name_token;
            var msg: u8[>..] = [];
            msg.append("duplicate declaration in this scope: `"); msg.append(token_text(p, n_token)); msg.push('`');
            if prev_tok >= 0 && prev_tok < p.tokens.len {
                msg.append("\n  note: previously declared at ");
                format_token_location(p, prev_tok, msg);
            }
            diagnose(p, n_token, msg); break;
        }
        collision = old.next;
    }
    if (flags & (S_FUNCTION | S_TYPE)) == 0 && n_kind != N_NAMESPACE && n_kind != N_FIELD && n_kind != N_VARIANT {
        slot = c.next_slot; c.next_slot += 1;
    }
    let id = p.symbols.len;
    var owner = c.function_node;
    if c.default_body && (n_kind == N_FUNCTION || n_kind == N_FUNCTION_VALUE) { owner = -1; }
    p.symbols.push(Symbol { name_token: n_token, type_id: n_type_id, node: node,
        scope: scope, slot: slot, flags: flags, next: previous, owner: owner });
    check_link_symbol(p, c, id, scope);
    p.nodes[node].symbol = id as i32;
    p.nodes[node].scope = scope as i32;
    if (n_kind == N_FUNCTION || n_kind == N_FUNCTION_VALUE) && c.default_fields.count > 0 { p.nodes[node].flags |= F_DEFAULT; }
    if (n_kind == N_FUNCTION || n_kind == N_FUNCTION_VALUE) && (n_flags & F_SYNTHETIC) == 0 && c.parameter_default_function >= 0 {
        c.parameter_default_contexts.push(CheckDefaultCapture { node: node, function_node: c.parameter_default_function, floor: c.parameter_default_floor });
    }
    if slot >= 0 {
        while c.variable_lookup.len <= id { c.variable_lookup.push(-1); }
        c.variable_lookup[id] = c.variables.len; var next_frame = -1;
        if scope >= 0 {
            let frame = c.scopes[scope].frame_root; next_frame = c.scopes[frame].first_variable;
            c.scopes[frame].first_variable = c.variables.len;
        }
        c.flow_clock += 1;
        c.variables.push(CheckVariable { symbol: id, next_frame: next_frame, born: c.flow_clock });
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
    while at >= 0 { let old: const CheckRoot& = c.roots[at]; if old.root == root && old.kind == kind { return; } at = old.next; }
    let id = c.roots.len; c.roots.push(CheckRoot { value: value, root: root, kind: kind, next: first }); check_root_index(c, value, id);
}
fn check_copy_roots(c: Checker&, destination: i64, source: i64) {
    var at = check_root_head(c, source);
    while at >= 0 { let r = c.roots[at].root; let k = c.roots[at].kind; at = c.roots[at].next; check_add_root(c, destination, r, k); }
}

fn check_place_root(p: Program&, node: i64) -> i64 {
    var current = node;
    while current >= 0 {
        let n: const Node& = p.nodes[current];
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
        let n: const Node& = p.nodes[current];
        if n.kind == N_INDEX || n.kind == N_SLICE { return 1; }
        if n.kind == N_MEMBER || n.kind == N_UNARY || n.kind == N_CAST { current = n.left; }
        else { return 0; }
    }
    return 0;
}

fn check_type_property(p: Program&, ty: i64, property: i64) -> i64 {
    if ty < 0 { return 0; }
    let key = ty * 8 + property;
    if key < p.type_properties.len && p.type_properties[key] != 0 { return p.type_properties[key] - 1; }
    var complete = true; let result = check_type_property_scan(p, ty, property, complete);
    // A found reference, generic or growable array stays found; anything else
    // is final once every part's layout is.
    if complete || result != 0 && (property != 2 || result >= 2) {
        if p.type_properties.len <= key { p.type_properties.resize(key + 1, 0); }
        p.type_properties[key] = result + 1;
    }
    return result;
}
// complete turns false where the walk meets a type whose parts are still
// being determined: a result that walk did not find may change later.
fn check_type_property_scan(p: Program&, ty: i64, property: i64, complete: bool&) -> i64 {
    // Each type is queued once; a stamp per scan marks the queued ones.
    p.type_scan_stamp += 1; let stamp = p.type_scan_stamp;
    if p.type_scan_marks.len < p.types.len { p.type_scan_marks.resize(p.types.len, 0); }
    var work: i64[>..] = [ty]; p.type_scan_marks[ty] = stamp; var scanned = 0; var result = 0;
    while scanned < work.len {
        let current = work[scanned]; scanned += 1;
        let t: const Type& = p.types[current];
        if t.kind == TY_FN { complete = false; }
        if (t.kind == TY_ARRAY || t.kind == TY_REF || t.kind == TY_SLICE) && t.element < 0 { complete = false; }
        if t.kind == TY_STRUCT || t.kind == TY_ENUM {
            if t.declaration < 0 { complete = false; }
            else if p.nodes[t.declaration].kind == N_VARIANT { if t.size < 0 { complete = false; } }
            else if (p.nodes[t.declaration].flags & F_CHECKED) == 0 { complete = false; }
        }
        if property == 0 && t.kind == TY_GENERIC { return 1; }
        if property == 1 && (t.kind == TY_REF || t.kind == TY_SLICE) { return 1; }
        if property == 3 && t.kind == TY_REF && t.length_storage >= 0 { return 1; }
        if property == 6 && t.kind == TY_REF && t.length_storage >= 0 && t.pool < 0 { return 1; }
        if property == 4 && t.kind == TY_ARRAY && t.array_kind == A_GROWSHRINK { return 1; }
        // A root owner's components own their arrays separately (upstream
        // ContainsGrowShrink); provenance decides which one a view is in.
        if property == 4 && root_struct_type(p, current) { continue; }
        if property == 5 && (t.kind == TY_SLICE || t.kind == TY_FN || t.kind == TY_REF && (t.length_storage < 0 || t.pool >= 0)) { return 1; }
        if property == 2 {
            // A root owner is its own class: its fields are stored apart,
            // and it is never a fixed-size value (upstream SC_ROOT).
            if current == ty && root_struct_type(p, current) { return 3; }
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
        if traverse_element && t.element >= 0 && p.type_scan_marks[t.element] != stamp { p.type_scan_marks[t.element] = stamp; work.push(t.element); }
        if traverse_fields {
            var part = t.first;
            while part >= 0 {
                let child = p.nodes[part].type_id;
                if child < 0 && (p.nodes[part].flags & F_PAD) == 0 { complete = false; }
                if child >= 0 && p.type_scan_marks[child] != stamp { p.type_scan_marks[child] = stamp; work.push(child); }
                part = p.nodes[part].next;
            }
        }
    }
    return result;
}
// The image verifier can prove element starts and the tag of an ADT variant.
recursive fn check_image_links(p: Program&, type_id: i64, element: i64) -> bool {
    if type_id < 0 || check_type_property(p, type_id, 6) == 0 { return true; }
    let t: const Type& = p.types[type_id];
    if t.kind == TY_REF {
        if t.element < 0 { return false; }
        if check_same_type(p, t.element, element) { return true; }
        let pointee: const Type& = p.types[t.element];
        let root: const Type& = p.types[element];
        return pointee.kind == TY_STRUCT && pointee.pool >= 0 && root.kind == TY_ENUM &&
            p.types[pointee.pool].declaration == root.declaration;
    }
    if t.kind == TY_ARRAY { return check_image_links(p, t.element, element); }
    var field = t.first;
    while field >= 0 {
        if !check_image_links(p, p.nodes[field].type_id, element) { return false; }
        field = p.nodes[field].next;
    }
    return true;
}
inline fn check_contains_refs(p: Program&, ty: i64, depth: i64) -> bool {
    if ty < 12 { return false; }
    return check_type_property(p, ty, 1) != 0;
}
// 0 fixed, 1 variable, 2 resizable, 3 a root owner (upstream SizeClass).
inline fn check_size_class(p: Program&, ty: i64, depth: i64) -> i64 {
    if ty < 13 { return 0; }
    return check_type_property(p, ty, 2);
}
fn check_store_roots(p: Program&, c: Checker&, destination: i64, expression: i64) {
    if destination < 0 { return; }
    let stored_type = p.nodes[expression].type_id;
    if stored_type >= 0 && !check_contains_refs(p, stored_type, 0) { return; }
    var at = check_root_head(c, expression);
    while at >= 0 { let root = c.roots[at]; at = root.next; if root.root >= 0 { check_add_root(c, -destination - 10, root.root, root.kind); } }
}

inline fn check_effect_bucket(c: Checker&, function_node: i64, root: i64, kind: i64) -> i64 {
    var h = (function_node as! u64) * 11400714819323198485 ^ (root as! u64) * 14029467366897019727 ^ (kind as! u64) * 1609587929392839161;
    h ^= h >> 29; return (h & ((c.effect_key_heads.len - 1) as! u64)) as i64;
}
// One key per bucket at most, on average.
fn check_index_effect(c: Checker&, effect: i64, kind: i64) {
    if c.effect_key_heads.len <= c.effect_keys.len + 1 {
        var count = CHECK_INITIAL_BUCKETS; while count <= c.effect_keys.len + 1 { count <<= 1; }
        for slot in 0..c.effect_key_heads.len { c.effect_key_heads[slot] = -1; }
        while c.effect_key_heads.len < count { c.effect_key_heads.push(-1); }
        for index in 0..c.effect_keys.len {
            let key: const CheckEffectKey& = c.effect_keys[index]; let owner: const CheckEffect& = c.effects[key.effect];
            let bucket = check_effect_bucket(c, owner.function_node, owner.root, key.kind);
            c.effect_keys[index].next = c.effect_key_heads[bucket]; c.effect_key_heads[bucket] = index;
        }
    }
    let owner: const CheckEffect& = c.effects[effect]; let bucket = check_effect_bucket(c, owner.function_node, owner.root, kind);
    c.effect_keys.push(CheckEffectKey { effect: effect, kind: kind, next: c.effect_key_heads[bucket] });
    c.effect_key_heads[bucket] = c.effect_keys.len - 1;
}
fn check_note_effect(c: Checker&, root: i64, kind: i64) {
    let function_node = c.function_node;
    if function_node < 0 || root < 0 { return; }
    var at = c.effect_key_heads[check_effect_bucket(c, function_node, root, kind)];
    while at >= 0 {
        let key = c.effect_keys[at]; let effect: const CheckEffect& = c.effects[key.effect];
        if effect.function_node == function_node && effect.root == root && effect.kind == kind { return; }
        at = key.next;
    }
    while c.effect_lists.len <= function_node { c.effect_lists.push(CheckEffectList {}); }
    let id = c.effects.len;
    c.effects.push(CheckEffect { function_node: function_node, root: root, kind: kind });
    check_index_effect(c, id, kind);
    let last = c.effect_lists[function_node].last;
    if last < 0 { c.effect_lists[function_node].first = id; } else { c.effects[last].next = id; }
    c.effect_lists[function_node].last = id;
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
// from_bytes verifies every index and bound type anywhere inside its element
// type against that type's named array length (§3.11), which reads the global
// holding the array.
fn check_from_bytes_indices(p: Program&, c: Checker&, ty: i64, token: i64) {
    if ty < 0 { return; }
    p.type_scan_stamp += 1; let stamp = p.type_scan_stamp;
    if p.type_scan_marks.len < p.types.len { p.type_scan_marks.resize(p.types.len, 0); }
    var work: i64[>..] = [ty]; p.type_scan_marks[ty] = stamp; var scanned = 0;
    while scanned < work.len {
        let current = work[scanned]; scanned += 1;
        let t: const Type& = p.types[current];
        if t.kind == TY_INT && t.index_type >= 0 && t.pool >= 0 {
            var named = t.pool;
            if p.symbols[named].component_owner >= 0 { named = p.symbols[named].component_owner; }
            check_global_use(p, c, named, token);
        }
        if (t.kind == TY_ARRAY || t.kind == TY_SLICE || t.kind == TY_REF) && t.element >= 0 && p.type_scan_marks[t.element] != stamp {
            p.type_scan_marks[t.element] = stamp; work.push(t.element);
        }
        if t.kind == TY_STRUCT || t.kind == TY_ENUM || t.kind == TY_TUPLE {
            var part = t.first;
            while part >= 0 {
                let child = p.nodes[part].type_id;
                if child >= 0 && (p.nodes[part].flags & F_PAD) == 0 && p.type_scan_marks[child] != stamp {
                    p.type_scan_marks[child] = stamp; work.push(child);
                }
                part = p.nodes[part].next;
            }
        }
    }
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
// A literal parameter named as a value (upstream §7.7).
fn check_literal_parameter(p: Program&, node: i64) -> bool {
    if node < 0 { return false; }
    let n: const Node& = p.nodes[node];
    return n.kind == N_NAME && n.symbol >= 0 && (p.symbols[n.symbol].flags & S_LITERAL) != 0;
}
fn check_note_literal_use(c: Checker&, symbol: i64, type_id: i64) {
    for entry in c.literal_uses { if entry.symbol == symbol && entry.type_id == type_id { return; } }
    c.literal_uses.push(CheckLiteralUse { symbol: symbol, type_id: type_id });
}
fn check_binding_same(p: Program&, a: i64, b: i64) -> bool {
    if a >= 0 && b >= 0 && p.types[a].kind == TY_FN && p.types[b].kind == TY_FN && p.types[a].declaration != p.types[b].declaration { return false; }
    return check_same_type(p, a, b);
}
fn check_find_binding(c: Checker&, bindings: CheckList&, parameter: i64) -> i64 {
    var item = bindings.first;
    for index in 0..bindings.count {
        let binding = c.binding_work[item];
        if binding.parameter == parameter { return item; }
        item = binding.next;
    }
    return -1;
}
fn check_bind_generic(p: Program&, c: Checker&, parameter: i64, value: i64, bindings: CheckList&) -> bool {
    let item = check_find_binding(c, bindings, parameter);
    if item >= 0 { return check_binding_same(p, c.binding_work[item].value, value); }
    check_binding_push(c, bindings, TypeBinding { parameter: parameter, value: value }); return true;
}
recursive fn check_unify(p: Program&, c: Checker&, formal: i64, actual: i64, bindings: CheckList&) -> bool {
    if formal < 0 || actual < 0 { return true; }
    if formal == actual && !check_has_generic(p, formal, 0) { return true; }
    let fk = p.types[formal].kind; let ak = p.types[actual].kind;
    // Concrete copying destinations use argument conversion. A slice cannot
    // infer an unbound array element type or construct a fixed array.
    if fk == TY_ARRAY && p.types[formal].array_kind != A_FIXED && ak == TY_SLICE {
        let concrete = check_substitute(p, c, formal, bindings);
        if !check_has_generic(p, concrete, 0) { return true; }
    }
    let a_elem = p.types[actual].element;
    if ak == TY_ARRAY && a_elem < 0 || ak == TY_REF && a_elem == TYPE_VOID { return true; }
    if fk == TY_GENERIC {
        let f_decl = p.types[formal].declaration;
        if check_find_binding(c, bindings, f_decl) >= 0 { return true; }
        return check_bind_generic(p, c, f_decl, actual, bindings);
    }
    if ak == TY_REF && fk != TY_REF { return check_unify(p, c, formal, a_elem, bindings); }
    let f_elem = p.types[formal].element;
    if fk == TY_REF && ak != TY_REF { return check_unify(p, c, f_elem, actual, bindings); }
    if fk == TY_ARRAY || fk == TY_SLICE || fk == TY_REF {
        if fk != ak && !(fk == TY_SLICE && ak == TY_ARRAY) { return false; }
        if fk == TY_ARRAY && p.types[formal].array_kind == A_FIXED && p.types[formal].count != p.types[actual].count { return false; }
        return check_unify(p, c, f_elem, a_elem, bindings);
    }
    if (fk == TY_STRUCT || fk == TY_ENUM) && (ak == TY_STRUCT || ak == TY_ENUM) {
        var fp = formal; var ap = actual;
        if fk == TY_STRUCT && p.types[formal].pool >= 0 { fp = p.types[formal].pool; }
        if ak == TY_STRUCT && p.types[actual].pool >= 0 { ap = p.types[actual].pool; }
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
    if fk == TY_FN && ak == TY_FN {
        var fp = p.types[formal].first; var ap = p.types[actual].first;
        while fp >= 0 && ap >= 0 {
            if !check_unify(p, c, p.nodes[fp].type_id, p.nodes[ap].type_id, bindings) { return false; }
            fp = p.nodes[fp].next; ap = p.nodes[ap].next;
        }
        return fp < 0 && ap < 0 && check_unify(p, c, f_elem, a_elem, bindings);
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
        // A slice is interned like a written one, so a substituted const u8[:]
        // is the string type itself.
        if t.kind == TY_SLICE { return check_type(p, TY_SLICE, element, t.count, t.declaration, t.flags); }
        // T? makes a reference type nullable while preserving its storage
        // form. T& exposes the loaded reference held in T (§3.8).
        if t.length_storage < 0 && p.types[element].kind == TY_REF {
            var reference = element;
            if (t.flags & TF_OPTIONAL) == 0 { reference = check_loaded_type(p, reference); }
            var copy = p.types[reference];
            copy.flags |= t.flags & (TF_CONST | TF_OPTIONAL);
            if copy.flags == p.types[reference].flags { return reference; }
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
                let copy = new_node(p, N_TYPE_ARG, old.token); p.nodes[copy].type_id = value as i32;
                if first < 0 { first = copy; } else { p.nodes[last].next = copy as i32; }
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
            let sty = check_substitute(p, c, p.nodes[part].type_id, bindings); p.nodes[id].type_id = sty as i32;
            if first < 0 { first = id; } else { p.nodes[last].next = id as i32; }
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
        if ty >= 0 && (p.types[ty].kind == TY_FN ||
            (p.types[ty].kind == TY_SLICE || p.types[ty].kind == TY_REF) && (p.types[ty].flags & TF_CONST) == 0) {
            preserve = true;
        }
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
        if c.expansion_nodes > p.expansion_limit {
            if c.expansion_nodes == p.expansion_limit + 1 {
                var message: u8[>..] = []; message.append("const for expansion exceeds "); message.format(p.expansion_limit); message.append(" generated nodes");
                diagnose(p, p.nodes[node].token, message);
            }
            return -1;
        }
    }
    let saved_syntax = c.clone_syntax;
    if node == c.syntax_body { c.clone_syntax = true; }
    var copy = check_clone_node(p, c, node);
    if node == c.syntax_function { copy.right = c.syntax_body as i32; }
    copy.type_id = check_substitute(p, c, copy.type_id, bindings) as i32;
    copy.coerced_type = check_substitute(p, c, copy.coerced_type, bindings) as i32;
    if copy.kind == N_PARAM {
        for binding_index in 0..bindings.count {
            let binding = check_binding_at(c, bindings, binding_index);
            if binding.parameter == node { copy.type_id = binding.value as i32; }
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
    let cl_left = check_clone(p, c, old_left, bindings); p.nodes[id].left = cl_left as i32;
    if copy.kind == N_RECORD { p.nodes[id].right = old_right; }
    else { let cl_right = check_clone(p, c, old_right, bindings); p.nodes[id].right = cl_right as i32; }
    let cl_third = check_clone(p, c, old_third, bindings); p.nodes[id].third = cl_third as i32;
    if c.expanding && c.expansion_nodes > p.expansion_limit { c.clone_syntax = saved_syntax; return id; }
    // left and third may own lists (function results and generic parameters).
    if copy.kind == N_FUNCTION || copy.kind == N_FUNCTION_VALUE || copy.kind == N_TYPE_FN || copy.kind == N_CONST_FOR {
        var old = old_left; var tail: i64 = p.nodes[id].left;
        if old >= 0 { old = check_clone_node(p, c, old).next; }
        while old >= 0 {
            let item = check_clone(p, c, old, bindings); if item < 0 || tail < 0 { break; }
            p.nodes[tail].next = item as i32; tail = item; old = check_clone_node(p, c, old).next;
        }
    }
    if copy.kind == N_FUNCTION || copy.kind == N_STRUCT || copy.kind == N_ENUM {
        var old = old_third; var tail: i64 = p.nodes[id].third;
        if old >= 0 { old = check_clone_node(p, c, old).next; }
        while old >= 0 {
            let item = check_clone(p, c, old, bindings); if item < 0 || tail < 0 { break; }
            p.nodes[tail].next = item as i32; tail = item; old = check_clone_node(p, c, old).next;
        }
    }
    if copy.kind == N_VARIABLE {
        var old = old_right; var tail: i64 = p.nodes[id].right;
        if old >= 0 { old = check_clone_node(p, c, old).next; }
        while old >= 0 {
            let item = check_clone(p, c, old, bindings); if item < 0 || tail < 0 { break; }
            p.nodes[tail].next = item as i32; tail = item; old = check_clone_node(p, c, old).next;
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
fn check_constant_above_i64(p: Program&, c: Checker&, node: i64) -> bool {
    let constant = check_constant(p, c, node, 0);
    return constant.valid && constant.type_id == TYPE_U64 && constant.value < 0;
}
fn check_constant_negative(p: Program&, c: Checker&, node: i64) -> bool {
    let constant = check_constant(p, c, node, 0);
    if constant.valid { return constant.type_id != TYPE_U64 && constant.value < 0; }
    let flex = check_flex_integer(p, c, node);
    return flex.valid && flex.minimum < 0;
}
fn check_constant_fits(value: CheckConstant, type_id: i64) -> bool {
    if value.type_id == TYPE_U64 && value.value < 0 { return type_id == TYPE_U64; }
    return value.value >= check_min(type_id) && (type_id == TYPE_U64 || value.value <= check_max(type_id));
}
recursive fn check_constant_extent(p: Program&, c: Checker&, node: i64, capacity: bool, depth: i64) -> CheckConstant {
    if node < 0 || depth > 64 || p.nodes[node].kind != N_NAME { return CheckConstant {}; }
    let n = p.nodes[node]; var symbol: i64 = n.symbol; if symbol < 0 { symbol = check_lookup_name(p, c, node); }
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
    let kind = p.nodes[node].kind;
    if kind == N_INTEGER || kind == N_BOOL {
        let flags = p.nodes[node].flags; let n_ty = p.nodes[node].type_id;
        var type_id = TYPE_I64; if (flags & F_UNSIGNED) != 0 { type_id = TYPE_U64; }
        if n_ty >= 0 {
            let num = check_numeric_value_type(p, n_ty);
            if check_integer(num) { type_id = num; }
        }
        return CheckConstant { valid: true, value: p.nodes[node].integer, type_id: type_id, literal: true };
    }
    if kind == N_NAME {
        var symbol: i64 = p.nodes[node].symbol; if symbol < 0 { symbol = check_lookup_name(p, c, node); }
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
        return CheckConstant {};
    }
    if kind == N_CAST && (p.nodes[node].flags & F_SYNTHETIC) != 0 {
        let n_left = p.nodes[node].left;
        let destination = check_numeric_value_type(p, check_resolve_type(p, c, p.nodes[node].right));
        if check_integer(destination) {
            var value = check_constant(p, c, n_left, depth + 1);
            let complement = check_complement_input(p, c, n_left);
            if complement.valid && complement.value <= check_max(destination) { value = CheckConstant { valid: true, value: check_constant_wrap(~complement.value, destination), type_id: destination }; }
            if value.valid && check_constant_fits(value, destination) { value.type_id = destination; value.literal = false; return value; }
        }
        return CheckConstant {};
    }
    if kind == N_MEMBER {
        let tok = p.nodes[node].token;
        if token_is(p, tok, "len") || token_is(p, tok, "cap") { return check_constant_extent(p, c, p.nodes[node].left, token_is(p, tok, "cap"), depth + 1); }
        return CheckConstant {};
    }
    if kind == N_CALL {
        let sym = p.nodes[node].symbol;
        if sym >= 0 && (p.symbols[sym].flags & S_BUILTIN) != 0 {
            let builtin = p.symbols[sym].index;
            if builtin == 21 || builtin == 22 { return check_constant_extent(p, c, p.nodes[node].first, builtin == 22, depth + 1); }
        }
        return CheckConstant {};
    }
    if kind == N_UNARY {
        let op = p.nodes[node].integer;
        let a = check_constant(p, c, p.nodes[node].left, depth + 1); if !a.valid { return a; }
        if op == T_MINUS {
            if a.type_id == TYPE_U64 && a.value == -9223372036854775808 && a.literal { return CheckConstant { valid: true, value: a.value, type_id: TYPE_I64, literal: true }; }
            if check_unsigned(a.type_id) || a.value == -9223372036854775808 { return CheckConstant {}; }
            let value = -a.value;
            if value < check_min(a.type_id) || value > check_max(a.type_id) { return CheckConstant {}; }
            return CheckConstant { valid: true, value: value, type_id: a.type_id, literal: a.literal };
        }
        if op == T_BITNOT { return CheckConstant { valid: true, value: check_constant_wrap(~a.value, a.type_id), type_id: a.type_id, literal: a.literal }; }
        if op == T_NOT { var value = 0; if a.value == 0 { value = 1; } return CheckConstant { valid: true, value: value }; }
        return CheckConstant {};
    }
    if kind == N_BINARY {
        let n_left = p.nodes[node].left; let n_right = p.nodes[node].right; let op = p.nodes[node].integer;
        let a = check_constant(p, c, n_left, depth + 1); if !a.valid { return CheckConstant {}; }
        let b = check_constant(p, c, n_right, depth + 1); if !b.valid { return CheckConstant {}; }
        let x = a.value; let y = b.value; var type_id = a.type_id;
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
        if p.nodes[param].type_id < 0 { let ty = check_type(p, TY_GENERIC, -1, 0, param, 0); p.nodes[param].type_id = ty as i32; }
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
fn check_push_type_chain(c: Checker&, declaration: i64) {
    // A queued pointee retains the ancestry of the field that named it.
    c.integer_work.push(CheckInteger { value: declaration, next: c.type_chain });
    c.type_chain = c.integer_work.len - 1;
}

fn check_defer_pointee(p: Program&, c: Checker&, type_id: i64, token: i64) {
    if type_id < 0 || c.type_build_depth == 0 { return; }
    let kind = p.types[type_id].kind;
    if kind == TY_STRUCT || kind == TY_ENUM || kind == TY_ARRAY {
        c.pointees.push(CheckPointee { type_id: type_id, token: token, chain: c.type_chain });
    }
}

recursive fn check_array_element(p: Program&, c: Checker&, element: i64, array_kind: i64, token: i64) {
    if element < 0 || check_has_generic(p, element, 0) { return; }
    // Validation reports a root owner's placement.
    if root_struct_type(p, element) { return; }
    if p.types[element].kind == TY_STRUCT || p.types[element].kind == TY_ENUM { check_layout_nominal(p, c, element); }
    if p.types[element].kind == TY_ARRAY && p.types[element].size < 0 { check_layout_deferred_array(p, c, element, token); }
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
    if p.nodes[syntax].expansion_binding == -3 {
        if p.nodes[syntax].first < 0 && (p.nodes[syntax].flags & F_VARIABLE_MODE) == 0 {
            var message: u8[>..] = []; message.append("const for binding "); message.append(token_text(p, p.nodes[syntax].token)); message.append(" is not a type");
            diagnose(p, p.nodes[syntax].token, message);
        } else { diagnose(p, p.nodes[syntax].token, "const for binding is not a type or cannot take type arguments"); }
        return -1;
    }
    if p.nodes[syntax].type_id >= 0 { return p.nodes[syntax].type_id; }
    let n_kind = p.nodes[syntax].kind; let n_left = p.nodes[syntax].left;
    let n_right = p.nodes[syntax].right; let n_third = p.nodes[syntax].third;
    let n_first = p.nodes[syntax].first; let n_tok = p.nodes[syntax].token;
    let n_flags = p.nodes[syntax].flags; let n_int = p.nodes[syntax].integer;
    var result = -1;
    if n_kind == N_TYPE_NAME || n_kind == N_NAME {
        if n_left >= 0 {
            let outer = check_resolve_type(p, c, n_left);
            if outer >= 0 && p.types[outer].kind == TY_ENUM {
                if p.types[outer].size == -1 { check_prepare_variants(p, outer); }
                else if c.type_indirections > 0 && c.type_build_depth > 0 { check_prepare_variants(p, outer); }
                else { check_layout_nominal(p, c, outer); }
                var variant = p.types[outer].first;
                while variant >= 0 {
                    if same_name(p, p.nodes[variant].token, n_tok) {
                        result = p.nodes[variant].type_id;
                        if c.type_indirections == 0 { check_layout_variant(p, c, result); }
                        break;
                    }
                    variant = p.nodes[variant].next;
                }
            }
            if result < 0 {
                var msg: u8[>..] = []; msg.append("unknown enum variant type: `"); msg.append(token_text(p, n_tok)); msg.push('`');
                if outer >= 0 && p.types[outer].kind == TY_ENUM {
                    msg.append(" on `"); diag_append_type(p, outer, msg); msg.push('`');
                    diag_suggest_member(p, p.types[outer].first, token_text(p, n_tok), "variants", msg);
                }
                diagnose(p, n_tok, msg);
            }
        } else {
            let tok_kind = p.tokens[n_tok].kind;
            result = check_primitive_token(tok_kind);
            if tok_kind == T_TVARINT {
                var ty = p.types[TYPE_I64]; ty.storage = 1; ty.size = 0; result = add_type(p, ty);
            }
            if result < 0 && token_is(p, n_tok, "void") { result = TYPE_VOID; }
            if result < 0 {
                let symbol = check_lookup_name(p, c, syntax, S_TYPE);
                if symbol >= 0 && (p.symbols[symbol].flags & S_TYPE) != 0 {
                    let declaration = p.symbols[symbol].node;
                    p.nodes[syntax].symbol = symbol as i32;
                    if declaration >= 0 && p.nodes[declaration].kind == N_ALIAS {
                        if (p.nodes[declaration].flags & F_CHECKED) != 0 { diagnose(p, n_tok, "cyclic type alias"); }
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
                            result = check_nominal_instance(p, c, declaration, n_first, n_tok);
                        } else if n_first >= 0 { diagnose(p, n_tok, "type does not take generic arguments"); }
                    }
                } else if c.scope == c.implicit_type_scope && n_first < 0 && p.nodes[syntax].aux == 1 && tok_kind == T_IDENT {
                    // Upstream BindTypes can infer a name from the written
                    // parameter even when it has no explicit type parameter.
                    let parameter = new_node(p, N_TYPE_PARAM, n_tok);
                    p.nodes[parameter].flags |= F_SYNTHETIC;
                    result = check_type(p, TY_GENERIC, -1, 0, parameter, 0);
                    p.nodes[parameter].type_id = result as i32;
                    let symbol = check_declare(p, c, parameter, c.scope);
                    p.nodes[syntax].symbol = symbol as i32;
                    check_list_push(c, c.implicit_types, parameter);
                } else {
                    var message: u8[>..] = []; message.append("unknown type: "); message.append(token_text(p, n_tok));
                    diag_suggest_type(p, c, token_text(p, n_tok), c.scope, message);
                    diagnose(p, n_tok, message);
                }
            }
        }
    } else if n_kind == N_TYPE_REF {
        c.type_indirections += 1; let element = check_resolve_type(p, c, n_left); c.type_indirections -= 1;
        check_defer_pointee(p, c, element, n_tok);
        let flags = n_flags & (TF_CONST | TF_OPTIONAL);
        if element >= 0 && p.types[element].kind == TY_REF { var copy = p.types[element]; copy.flags |= flags; result = add_type(p, copy); }
        else { result = check_type(p, TY_REF, element, 0, -1, flags); }
        if n_right >= 0 && root_struct_type(p, element) { diagnose(p, n_tok, "root struct references must be plain references, not relative references"); }
        if n_right >= 0 {
            let storage = check_resolve_type(p, c, n_right);
            var copy = p.types[result];
            if storage >= 0 && p.types[storage].storage == 1 { copy.length_storage = 0; }
            else if check_integer(storage) && check_unsigned(storage) { copy.length_storage = p.types[storage].size; }
            else { diagnose(p, n_tok, "relative reference offset must use an unsigned integer storage"); }
            if n_third >= 0 {
                let pool = check_storage_name(p, c, n_third);
                if pool < 0 { diagnose(p, n_tok, "unknown reference pool"); }
                copy.pool = pool;
            }
            if copy.length_storage > 0 { copy.size = copy.length_storage; }
            if copy.length_storage == 0 { copy.size = 0; }
            copy.align = 1; result = add_type(p, copy);
        }
    } else if n_kind == N_TYPE_ARRAY {
        if n_int == A_SLICE { c.type_indirections += 1; }
        let element = check_resolve_type(p, c, n_left);
        if n_int == A_SLICE { c.type_indirections -= 1; }
        let deferred = c.type_build_depth > 0 && c.type_indirections > 0;
        if n_int == A_SLICE { check_defer_pointee(p, c, element, n_tok); }
        else if !deferred { check_array_element(p, c, element, n_int, n_tok); }
        var count = -1;
        if n_right >= 0 {
            check_constant_names(p, c, n_right);
            let constant = check_constant(p, c, n_right, 0);
            if constant.valid { count = constant.value; }
            else if n_int == A_FIXED || n_int == A_LIMITED { diagnose(p, n_tok, "array size or capacity must be a constant integer"); }
        }
        if count < 0 && n_right >= 0 && (n_int == A_FIXED || n_int == A_LIMITED) { diagnose(p, n_tok, "array size or capacity must be nonnegative"); }
        if n_int == A_SLICE { result = check_type(p, TY_SLICE, element, -1, -1, n_flags & TF_CONST); }
        else { result = check_array_type(p, element, count, n_int, n_flags & TF_CONST); }
        if n_third >= 0 {
            let length = check_resolve_type(p, c, n_third);
            var copy = p.types[result]; copy.length_explicit = true;
            if length >= 0 && p.types[length].storage == 1 { copy.length_storage = 0; }
            else if check_integer(length) && check_unsigned(length) { copy.length_storage = p.types[length].size; }
            else { diagnose(p, n_tok, "array length storage must be an unsigned integer"); }
            result = add_type(p, copy);
        }
        if n_int == A_LIMITED && count >= 0 && element >= 0 {
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
        if element >= 0 && p.types[element].kind == TY_VOID { diagnose(p, n_tok, "array element cannot be void"); }
        if deferred && count >= 0 && (n_int == A_FIXED || n_int == A_LIMITED) && element >= 0 &&
           (p.types[element].size < 0 || (p.types[element].kind == TY_STRUCT || p.types[element].kind == TY_ENUM) &&
            (p.nodes[p.types[element].declaration].flags & F_CHECKED) == 0) {
            p.types[result].size = -1;
        }
        if !deferred && n_int == A_FIXED && element >= 0 && !check_has_generic(p, element, 0) && p.types[element].size == 0 && count > 0 {
            diagnose(p, n_tok, "fixed array elements require a fixed physical size");
        }
    } else if n_kind == N_TYPE_PARAM {
        result = check_type(p, TY_GENERIC, -1, 0, syntax, 0);
    } else if n_kind == N_TYPE_FN {
        var param = n_first;
        while param >= 0 { check_resolve_type(p, c, param); param = p.nodes[param].next; }
        var ret = n_left;
        while ret >= 0 { let rty = check_value_annotation(p, c, ret, check_resolve_type(p, c, ret)); p.nodes[ret].type_id = rty as i32; ret = p.nodes[ret].next; }
        result = add_type(p, Type { kind: TY_FN, element: check_tuple(p, n_left), declaration: syntax, first: n_first, size: p.pointer_bytes, align: p.pointer_bytes });
    } else if n_kind == N_TYPEOF {
        result = check_loaded_type(p, check_single_expression(p, c, n_left));
    } else if n_kind == N_TYPE_DEDUCED {
        result = check_type(p, TY_GENERIC, -1, 0, syntax, 0);
    } else { diagnose(p, n_tok, "invalid type syntax"); }
    if result >= 0 && (n_flags & F_VARIABLE_MODE) != 0 {
        if p.types[result].kind != TY_ENUM { diagnose(p, n_tok, "variable mode applies only to an enum type"); }
        else { result = check_variable_enum_type(p, c, result); }
    }
    if result >= 0 && (n_flags & F_INDEX_TYPE) != 0 && n_third >= 0 {
        let pool = check_storage_name(p, c, n_third);
        if pool < 0 { diagnose(p, n_tok, "index type names an unknown owner"); }
        var copy = p.types[result]; copy.pool = pool; copy.index_type = result;
        if (n_flags & F_BOUND_TYPE) != 0 { copy.flags |= F_BOUND_TYPE; }
        result = add_type(p, copy);
    }
    if result >= 0 && (n_flags & TF_CONST) != 0 && n_kind != N_TYPE_REF && n_kind != N_TYPE_ARRAY {
        result = check_const_type(p, result);
    }
    p.nodes[syntax].type_id = result as i32;
    return result;
}
recursive fn check_layout_fields(p: Program&, c: Checker&, first: i64, owner: i64) -> i64 {
    var field = first; var size = 0; var index = 0; var variable = false;
    let root = owner >= 0 && p.nodes[owner].kind == N_STRUCT && (p.nodes[owner].flags & F_ROOT) != 0;
    let parent_scope = c.scope;
    var owner_fn = -1;
    if parent_scope >= 0 { owner_fn = c.scopes[parent_scope].function_node; }
    check_enter(c, owner_fn);
    let field_scope = c.scope;
    c.scope = parent_scope;
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
            if (n.flags & F_DEFAULT) != 0 && !variable {
                var following = n.next;
                while following >= 0 && (p.nodes[following].flags & F_PAD) != 0 { following = p.nodes[following].next; }
                if following >= 0 {
                    let next_type = check_resolve_type(p, c, p.nodes[following].left);
                    if next_type >= 0 {
                        let t: const Type& = p.types[next_type];
                        var alignment = 1;
                        if (t.kind == TY_INT || t.kind == TY_FLOAT) && t.storage == 0 { alignment = t.size; }
                        else if t.kind == TY_REF && t.length_storage > 0 { alignment = t.length_storage; }
                        else if t.kind == TY_SLICE || t.kind == TY_REF && t.length_storage < 0 { alignment = p.pointer_bytes; }
                        bytes = check_align(size, alignment) - size;
                    }
                }
            }
            if bytes < 0 { diagnose(p, n.token, "padding size must be nonnegative"); bytes = 0; }
            p.nodes[field].integer = size; p.nodes[field].aux = bytes; size += bytes;
        } else {
            let ty = check_resolve_type(p, c, n.left);
            p.nodes[field].type_id = ty as i32;
            if ty >= 0 && (p.types[ty].kind == TY_STRUCT || p.types[ty].kind == TY_ENUM) {
                check_layout_nominal(p, c, ty);
            }
            if ty >= 0 && p.types[ty].kind == TY_ARRAY && p.types[ty].size < 0 {
                check_layout_deferred_array(p, c, ty, n.token);
            }
            p.nodes[field].integer = size;
            if variable { p.nodes[field].integer = -1; }
            let symbol = check_declare(p, c, field, field_scope);
            p.nodes[field].scope = parent_scope as i32;
            // Field ownership is the only change to an indexed hook predicate.
            if symbol >= 0 && symbol < c.format_scan_end && (p.symbols[symbol].owner < 0) != (owner < 0) {
                c.format_scan_end = 0; c.has_format_hooks = false;
            }
            p.symbols[symbol].type_id = ty; p.symbols[symbol].owner = owner;
            p.symbols[symbol].offset = size; p.symbols[symbol].index = index;
            if root {
                // A root's record holds one plain reference per field, to
                // that field's own storage (upstream codegen_types.h).
                if ty >= 0 && p.types[ty].kind == TY_VOID { diagnose(p, n.token, "field cannot have void type"); }
                size += p.pointer_bytes;
            } else if ty >= 0 {
                if p.types[ty].kind == TY_VOID { diagnose(p, n.token, "field cannot have void type"); }
                if check_size_class(p, ty, 0) == 2 && n.next >= 0 {
                    diagnose(p, n.token, "a resizable field must be the final field; use root struct for independently stored fields");
                }
                if p.types[ty].storage == 1 || p.types[ty].kind == TY_REF && p.types[ty].length_storage == 0 { variable = true; }
                if !variable { size += p.types[ty].size; }
            }
            index += 1;
        }
        var layout_limit = p.maximum_pages * 65536;
        if p.pointer_bytes == 8 && !p.wide { layout_limit = 281474976710656; }
        if size > layout_limit { diagnose(p, n.token, "aggregate layout exceeds configured memory"); }
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
            p.nodes[variant].type_id = add_type(p, Type { kind: TY_STRUCT, declaration: variant, first: p.nodes[variant].first, size: -2, align: 1, pool: enum_type }) as i32;
        }
        p.nodes[variant].integer = tag; tag += 1; variant = p.nodes[variant].next;
    }
    p.types[enum_type].first = p.nodes[declaration].first; p.types[enum_type].count = tag; type_reindex(p, enum_type);
}
recursive fn check_finish_record_layout(p: Program&, type_id: i64, first: i64, size: i64) {
    p.types[type_id].size = size; p.types[type_id].align = 1; p.types[type_id].first = first;
    if root_struct_type(p, type_id) { if size > 0 { p.types[type_id].align = p.pointer_bytes; } return; }
    var field = first; var last = -1; var byte_record = false;
    while field >= 0 {
        let ft = p.nodes[field].type_id;
        if ft >= 0 && (p.types[ft].storage == 1 || p.types[ft].kind == TY_REF && p.types[ft].length_storage == 0) {
            if !byte_record { p.types[type_id].prefix = p.nodes[field].integer; }
            byte_record = true;
        }
        last = field; field = p.nodes[field].next;
    }
    if byte_record { p.types[type_id].size = p.control_bytes; p.types[type_id].align = p.control_align; p.types[type_id].tail = last; }
    else if last >= 0 && p.nodes[last].type_id >= 0 && check_size_class(p, p.nodes[last].type_id, 0) > 0 {
        p.types[type_id].prefix = p.nodes[last].integer; p.types[type_id].tail = last; p.types[type_id].align = p.control_align;
    }
}
recursive fn check_layout_variant(p: Program&, c: Checker&, type_id: i64) {
    if type_id < 0 { return; }
    let t = p.types[type_id]; let variant = t.declaration;
    if t.size >= 0 { return; }
    if t.size == -1 { diagnose(p, p.nodes[variant].token, "variant contains itself by value"); return; }
    p.types[type_id].size = -1;
    c.type_build_depth += 1;
    let saved = c.scope;
    if t.pool >= 0 { c.scope = p.nodes[p.types[t.pool].declaration].scope; }
    var owner_fn = -1;
    if c.scope >= 0 { owner_fn = c.scopes[c.scope].function_node; }
    check_enter(c, owner_fn);
    let size = check_layout_fields(p, c, p.nodes[variant].first, variant);
    check_finish_record_layout(p, type_id, p.nodes[variant].first, size);
    p.nodes[variant].flags |= F_CHECKED; c.scope = saved;
    check_finish_type_build(p, c);
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
    if result < 0 { var copy = t; copy.flags |= F_VARIABLE_MODE; copy.size = p.control_bytes; copy.align = p.control_align; result = add_type(p, copy); }
    if p.types[base].size == -1 || (p.nodes[t.declaration].flags & F_CHECKED) == 0 { return result; }
    var size = p.control_bytes; var align = p.control_align; var variant = declaration_layout.first;
    while variant >= 0 {
        let payload = p.nodes[variant].type_id;
        if check_size_class(p, payload, 0) == 0 { p.nodes[variant].aux = 0; }
        else {
            var alignment = p.types[payload].align; if alignment < p.control_align { alignment = p.control_align; }
            if alignment > align { align = alignment; }
            size = check_align(size, alignment); p.nodes[variant].aux = size; size += p.types[payload].size;
        }
        variant = p.nodes[variant].next;
    }
    p.types[result].first = declaration_layout.first; p.types[result].count = declaration_layout.count; type_reindex(p, result);
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
    c.type_build_depth += 1;
    let saved_chain = c.type_chain;
    if p.nodes[declaration].origin >= 0 { check_push_type_chain(c, p.nodes[declaration].origin); }
    let saved = c.scope;
    if p.nodes[declaration].scope >= 0 { c.scope = p.nodes[declaration].scope; }
    var owner_fn = -1;
    if c.scope >= 0 { owner_fn = c.scopes[c.scope].function_node; }
    check_enter(c, owner_fn); p.nodes[declaration].scope = c.scope as i32;
    check_ensure_generics(p, c, declaration);
    if t.kind == TY_STRUCT {
        var size = check_layout_fields(p, c, p.nodes[declaration].first, declaration);
        // Ordinary structs occupy at least one byte, even with no fields.
        if size == 0 && !root_struct_type(p, type_id) { size = 1; }
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
    c.type_chain = saved_chain;
    check_finish_type_build(p, c);
}

recursive fn check_layout_deferred_array(p: Program&, c: Checker&, type_id: i64, token: i64) {
    let t = p.types[type_id];
    check_array_element(p, c, t.element, t.array_kind, token);
    if t.element < 0 || t.size >= 0 { return; }
    let element = p.types[t.element];
    if t.array_kind == A_FIXED {
        var size = 0;
        if t.count >= 0 && element.size >= 0 && element.size <= 2147483647 / (t.count + 1) {
            size = t.count * element.size;
            if size == 0 { size = 1; }
        }
        p.types[type_id].size = size;
        p.types[type_id].align = element.align;
    } else {
        var slots = t.count;
        if slots == 0 { slots = 1; }
        p.types[type_id].size = t.length_storage + slots * element.size;
    }
}

recursive fn check_finish_type_build(p: Program&, c: Checker&) {
    // As in upstream EndTypeBuild, finish the outermost by-value layout
    // before following its reference and slice edges. Keep the worklist
    // open so pointees discovered while draining it also wait their turn.
    if c.type_build_depth == 1 {
        let saved_chain = c.type_chain;
        var index = 0;
        while index < c.pointees.len {
            let entry = c.pointees[index]; index += 1;
            c.type_chain = entry.chain;
            let kind = p.types[entry.type_id].kind;
            if kind == TY_ARRAY { check_layout_deferred_array(p, c, entry.type_id, entry.token); }
            else { check_layout_nominal(p, c, entry.type_id); }
        }
        c.pointees.clear();
        c.type_chain = saved_chain;
    }
    c.type_build_depth -= 1;
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
inline fn check_enqueue_type_use(pending: CheckTypeUse[>..]&, seen: bool[:], type_id: i64, token: i64) {
    if type_id < 0 || seen[type_id] { return; }
    seen[type_id] = true;
    pending.push(CheckTypeUse { type_id: type_id, token: token });
}
fn check_validate_type_uses(p: Program&) {
    var pending: CheckTypeUse[>..] = []; var seen: bool[>..] = [];
    seen.resize(p.types.len, false);
    for n in p.nodes {
        if (n.flags & F_CHECKED) == 0 { continue; }
        if n.kind == N_VARIABLE || n.kind == N_ARRAY || n.kind == N_FILL || n.kind == N_CAST {
            check_enqueue_type_use(pending, seen, n.type_id, n.token);
        }
        if n.kind == N_VARIABLE || n.kind == N_FOR {
            var binding = n.first;
            while binding >= 0 {
                check_enqueue_type_use(pending, seen, p.nodes[binding].type_id, p.nodes[binding].token);
                binding = p.nodes[binding].next;
            }
        }
        if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE {
            check_enqueue_type_use(pending, seen, n.type_id, n.token);
        }
    }
    for t in p.types {
        if t.kind != TY_STRUCT { continue; }
        var field = t.first;
        while field >= 0 {
            check_enqueue_type_use(pending, seen, p.nodes[field].type_id, p.nodes[field].token);
            field = p.nodes[field].next;
        }
    }
    var at = 0;
    while at < pending.len {
        let use = pending[at]; at += 1;
        let t = p.types[use.type_id];
        if t.kind == TY_ENUM {
            let reason = check_enum_fixed_reason(p, use.type_id);
            if reason == 1 { diagnose(p, use.token, "fixed-mode enum requires fixed-size payloads; use variable mode (E..)"); }
            if reason == 2 { diagnose(p, use.token, "fixed-mode enum payloads cannot hold self-relative references; use variable mode (E..)"); }
        }
        if t.kind == TY_ARRAY || t.kind == TY_SLICE || t.kind == TY_REF || t.kind == TY_FN {
            check_enqueue_type_use(pending, seen, t.element, use.token);
        }
        if t.kind == TY_STRUCT || t.kind == TY_ENUM || t.kind == TY_FN || t.kind == TY_TUPLE {
            var field = t.first;
            while field >= 0 {
                check_enqueue_type_use(pending, seen, p.nodes[field].type_id, use.token);
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
    var spec_id = check_specialization_head(c, declaration);
    while spec_id >= 0 {
        let spec = c.specializations[spec_id]; spec_id = spec.next_spec;
        if spec.binding_count != bindings.count { continue; }
        var equal = true; var item = bindings.first;
        for i in 0..bindings.count {
            let b = c.binding_work[item]; item = b.next;
            if !check_binding_same(p, b.value, c.bindings[spec.binding_start + i].value) { equal = false; }
        }
        if equal { return p.symbols[spec.symbol].type_id; }
    }
    var same_declaration = 0; var type_chain = c.type_chain;
    while type_chain >= 0 {
        let entry = c.integer_work[type_chain];
        if entry.value == declaration { same_declaration += 1; }
        type_chain = entry.next;
    }
    if same_declaration >= 16 || c.inference_depth >= 64 { diagnose(p, token, "generic type instantiation does not reach a finite set"); return -1; }
    let saved_chain = c.type_chain; check_push_type_chain(c, declaration);
    c.inference_depth += 1;
    let copy = check_clone(p, c, declaration, bindings);
    p.nodes[copy].third = -1; p.nodes[copy].origin = declaration as i32; p.nodes[copy].scope = outer_scope;
    var kind = TY_STRUCT; if p.nodes[declaration].kind == N_ENUM { kind = TY_ENUM; }
    let ty = add_type(p, Type { kind: kind, declaration: copy, first: p.nodes[copy].first,
        name_token: p.nodes[copy].token });
    p.nodes[copy].type_id = ty as i32;
    var argument_first = -1; var argument_last = -1;
    for binding_index in 0..bindings.count {
        let binding = check_binding_at(c, bindings, binding_index); let argument = new_node(p, N_TYPE_ARG, p.nodes[copy].token);
        p.nodes[argument].type_id = binding.value as i32;
        if argument_first < 0 { argument_first = argument; } else { p.nodes[argument_last].next = argument as i32; }
        argument_last = argument;
    }
    p.types[ty].arguments = argument_first;
    let symbol = p.symbols.len;
    p.symbols.push(Symbol { name_token: p.nodes[copy].token, type_id: ty, node: copy, scope: -2, flags: S_TYPE, owner: c.function_node });
    p.nodes[copy].symbol = symbol as i32;
    let start = c.bindings.len; var item = bindings.first;
    for index in 0..bindings.count {
        let binding = c.binding_work[item]; item = binding.next;
        c.bindings.push(binding);
    }
    check_add_specialization(c, CheckSpecialization { original: declaration, symbol: symbol,
        binding_start: start, binding_count: bindings.count });
    // Resolve generic names through their concrete bindings while laying out.
    let saved = c.scope;
    if outer_scope >= 0 { c.scope = outer_scope; }
    check_enter(c, c.function_node);
    for b_index in 0..bindings.count { let b = check_binding_at(c, bindings, b_index);
        let original = p.nodes[b.parameter];
        let binding = new_node(p, N_TYPE_PARAM, original.token);
        p.nodes[binding].type_id = b.value as i32; check_declare(p, c, binding, c.scope);
    }
    p.nodes[copy].scope = c.scope as i32;
    c.type_chain = saved_chain;
    if c.type_indirections == 0 || c.type_build_depth == 0 {
        push_instantiation(p, declaration, token);
        check_layout_nominal(p, c, ty);
        pop_instantiation(p);
    }
    c.scope = saved; c.inference_depth -= 1;
    return ty;
}

fn check_addressable(p: Program&, node: i64) -> bool {
    if node < 0 { return false; }
    let n: const Node& = p.nodes[node];
    return n.kind == N_NAME || n.kind == N_INDEX || n.kind == N_MEMBER ||
        n.kind == N_UNARY && n.integer == T_MUL;
}
fn check_frame_object(p: Program&, type_id: i64) -> bool {
    var current = type_id;
    loop {
        if current < 0 || p.types[current].kind != TY_STRUCT || check_size_class(p, current, 0) != 2 { return false; }
        let t: const Type& = p.types[current];
        if t.declaration < 0 || p.nodes[t.declaration].kind != N_STRUCT { return false; }
        let tail = t.tail;
        if tail < 0 || (p.nodes[tail].flags & F_PAD) != 0 { return false; }
        var field = t.first;
        while field >= 0 && field != tail {
            let n: const Node& = p.nodes[field];
            if (n.flags & F_PAD) == 0 && (check_size_class(p, n.type_id, 0) != 0 || check_type_property(p, n.type_id, 3) != 0) { return false; }
            field = n.next;
        }
        current = p.nodes[tail].type_id;
        if current >= 0 && p.types[current].kind == TY_ARRAY { return true; }
    }
}
fn check_referenceable(p: Program&, node: i64) -> bool {
    let n: const Node& = p.nodes[node];
    if n.type_id < 0 || check_size_class(p, n.type_id, 0) != 2 || n.kind == N_NAME { return true; }
    var member = node;
    loop {
        if p.nodes[member].kind != N_MEMBER { return false; }
        let owner = p.nodes[member].left; var ty: i64 = p.nodes[owner].type_id;
        if ty < 0 { return false; }
        let reference = p.types[ty].kind == TY_REF;
        if reference { ty = p.types[ty].element; }
        // A root's field is an independently stored component (upstream
        // FieldsInFrame).
        if root_struct_type(p, ty) { return true; }
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
        let n: const Node& = p.nodes[current]; var view = false;
        let storage = check_storage_type(p, current);
        if storage >= 0 && p.types[storage].kind != TY_REF && p.types[storage].kind != TY_SLICE && (p.types[storage].flags & TF_CONST) != 0 && !(place && (n.kind == N_MEMBER || n.kind == N_INDEX)) { return true; }
        if storage >= 0 && (p.types[storage].storage == 1 || place && p.types[storage].kind == TY_REF && p.types[storage].length_storage == 0) { return true; }
        if n.type_id >= 0 { view = p.types[n.type_id].kind == TY_REF || p.types[n.type_id].kind == TY_SLICE; }
        if n.kind == N_STRING { return true; }
        if n.kind == N_MEMBER && n.symbol >= 0 && p.nodes[n.symbol].kind == N_FIELD && (p.nodes[n.symbol].flags & F_CONST) != 0 && !(view && !place) { return true; }
        if n.type_id >= 0 && (p.types[n.type_id].flags & TF_CONST) != 0 && !(place && (n.kind == N_MEMBER || n.kind == N_INDEX)) { return true; }
        if view && !place {
            let t: const Type& = p.types[n.type_id];
            if t.kind == TY_SLICE && n.kind == N_UNARY && n.integer == T_MUL { current = n.left; continue; }
            if t.kind != TY_REF || t.length_storage < 0 || t.pool >= 0 { return false; }
        }
        var root_at = check_root_head(c, current);
        while root_at >= 0 { let root: const CheckRoot& = c.roots[root_at]; if root.root == -1 { return true; } root_at = root.next; }
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
    if p.types[expected].kind == TY_SLICE { return check_branch_readonly(p, c, node); }
    return check_readonly(p, c, node);
}
fn check_own_local(p: Program&, c: Checker&, node: i64) -> bool {
    if node < 0 || c.function_node < 0 { return false; }
    let n: const Node& = p.nodes[node];
    if n.kind != N_NAME || n.symbol < 0 { return false; }
    let symbol: const Symbol& = p.symbols[n.symbol];
    return symbol.owner == c.function_node && (symbol.flags & S_GLOBAL) == 0 &&
        symbol.type_id >= 0 && p.types[symbol.type_id].kind != TY_REF;
}
fn check_slot_value(p: Program&, c: Checker&, value: i64, expected: i64, aggregate_slot: bool = false) {
    if value < 0 || expected < 0 { return; }
    let t: const Type& = p.types[expected];
    if aggregate_slot && check_contains_refs(p, expected, 0) {
        var root_at = check_root_head(c, value);
        while root_at >= 0 {
            let root: const CheckRoot& = c.roots[root_at]; root_at = root.next;
            if root.root >= 0 && root.kind == 1 && check_type_property(p, p.symbols[root.root].type_id, 4) != 0 {
                diagnose(p, p.nodes[value].token, "a reference into grow-shrink storage cannot be stored in an aggregate slot");
            }
        }
    }
    if c.reachable && check_size_class(p, expected, 0) > 0 && t.kind != TY_REF && check_addressable(p, value) && check_size_class(p, p.nodes[value].type_id, 0) > 0 && !(c.returning && check_own_local(p, c, value)) {
        if root_struct_type(p, expected) { diagnose(p, p.nodes[value].token, "root owners cannot be copied; bind a reference instead"); }
        else { diagnose(p, p.nodes[value].token, "non-fixed storage requires explicit copy when passed or stored by value"); }
    }
    if (t.kind == TY_REF || t.kind == TY_SLICE) && (t.flags & TF_CONST) == 0 && check_readonly(p, c, value) {
        diagnose(p, p.nodes[value].token, "storing a read-only reference or slice requires a const slot\n  help: mark the target field or variable `const` (e.g. `const u8[:]`)");
    }
}
recursive fn check_bottom(p: Program&, node: i64) -> bool {
    if node < 0 { return false; }
    let n: const Node& = p.nodes[node];
    if (n.flags & F_DIVERGES) != 0 && n.kind != N_FUNCTION && n.kind != N_FUNCTION_VALUE || n.kind == N_RETURN || n.kind == N_BREAK || n.kind == N_CONTINUE { return true; }
    if n.kind == N_BLOCK && (n.flags & F_EARLY) == 0 && n.last >= 0 { return check_bottom(p, n.last); }
    if n.kind == N_IF { return n.third >= 0 && check_bottom(p, n.right) && check_bottom(p, n.third); }
    if n.kind == N_CALL && n.symbol >= 0 {
        let s: const Symbol& = p.symbols[n.symbol]; return (s.flags & S_BUILTIN) != 0 && (s.index == 4 || s.index == 5);
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
    if value != ty && node >= 0 { p.nodes[node].type_id = value as i32; }
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
    if ty <= TYPE_F64 { return ty; }
    let t: const Type& = p.types[ty];
    if t.kind == TY_FLOAT { if t.count == 32 { return TYPE_F32; } return TYPE_F64; }
    if t.kind != TY_INT { return ty; }
    if t.storage == 1 { return TYPE_I64; }
    var first = TYPE_I8; if (t.flags & TF_UNSIGNED) != 0 { first = TYPE_U8; }
    for id in first..first + 4 { if p.types[id].count == t.count { return id; } }
    return ty;
}
recursive fn check_literal_tree(p: Program&, node: i64, depth: i64) -> bool {
    if node < 0 || depth > 64 { return false; }
    let n: const Node& = p.nodes[node];
    if n.kind == N_INTEGER { return true; }
    if n.kind == N_UNARY && (n.integer == T_MINUS || n.integer == T_BITNOT) { return check_literal_tree(p, n.left, depth + 1); }
    if n.kind == N_BINARY { return check_literal_tree(p, n.left, depth + 1) && check_literal_tree(p, n.right, depth + 1); }
    if n.kind == N_NAME && n.symbol >= 0 {
        let s: const Symbol& = p.symbols[n.symbol];
        if (s.flags & S_GLOBAL) != 0 && (s.flags & S_MUTABLE) == 0 && s.node >= 0 && p.nodes[s.node].left < 0 {
            return check_literal_tree(p, p.nodes[s.node].right, depth + 1);
        }
    }
    return false;
}

// A branch construct adapts as a constant only when every reachable value does.
recursive fn check_integer_constants(p: Program&, c: Checker&, node: i64, depth: i64 = 0) -> bool {
    if node < 0 || depth > 64 { return false; }
    if check_bottom(p, node) { return true; }
    let kind = p.nodes[node].kind;
    if kind == N_BLOCK && (p.nodes[node].flags & F_TAIL) != 0 { return check_integer_constants(p, c, p.nodes[node].last, depth + 1); }
    if kind == N_IF && p.nodes[node].third >= 0 {
        return check_integer_constants(p, c, p.nodes[node].right, depth + 1) && check_integer_constants(p, c, p.nodes[node].third, depth + 1);
    }
    if kind == N_MATCH && p.nodes[node].first >= 0 {
        var arm = p.nodes[node].first;
        while arm >= 0 {
            if !check_integer_constants(p, c, p.nodes[arm].right, depth + 1) { return false; }
            arm = p.nodes[arm].next;
        }
        return true;
    }
    return check_literal_tree(p, node, depth + 1) && check_constant(p, c, node, depth + 1).valid;
}

// construct: an if or match whose values are all integer constants, which
// starts an adapting operation as a shift of a constant does (upstream
// 71e5ade1, §6.1).
struct CheckFlex { valid: bool = false, flexible: bool = false, minimum: i64 = 0, maximum: i64 = 0, construct: bool = false }
recursive fn check_flex_integer(p: Program&, c: Checker&, node: i64, depth: i64 = 0) -> CheckFlex {
    if node < 0 || depth > 64 { return CheckFlex {}; }
    if check_bottom(p, node) { return CheckFlex { valid: true }; }
    let kind = p.nodes[node].kind; let n_int = p.nodes[node].integer;
    if kind == N_UNARY && n_int == T_BITNOT {
        var child = check_flex_integer(p, c, p.nodes[node].left, depth + 1);
        if child.valid && (child.flexible || child.minimum >= 0) { child.flexible = true; return child; }
    }
    let constant = check_constant(p, c, node, 0);
    if constant.valid && check_integer_constants(p, c, node, depth + 1) && !(check_unsigned(check_numeric_value_type(p, constant.type_id)) && constant.value < 0) {
        return CheckFlex { valid: true, minimum: constant.value, maximum: constant.value };
    }
    if kind == N_BLOCK && (p.nodes[node].flags & F_TAIL) != 0 { return check_flex_integer(p, c, p.nodes[node].last, depth + 1); }
    if kind == N_IF && p.nodes[node].third >= 0 {
        let a = check_flex_integer(p, c, p.nodes[node].right, depth + 1); let b = check_flex_integer(p, c, p.nodes[node].third, depth + 1);
        if !a.valid || !b.valid { return CheckFlex {}; }
        var out = a; out.flexible = a.flexible || b.flexible; out.construct = true;
        if b.minimum < out.minimum { out.minimum = b.minimum; } if b.maximum > out.maximum { out.maximum = b.maximum; } return out;
    }
    if kind == N_MATCH && p.nodes[node].first >= 0 {
        var out = CheckFlex { valid: true }; var first = true; var arm = p.nodes[node].first;
        while arm >= 0 {
            let value = check_flex_integer(p, c, p.nodes[arm].right, depth + 1); if !value.valid { return CheckFlex {}; }
            if first { out = value; first = false; }
            else { if value.minimum < out.minimum { out.minimum = value.minimum; } if value.maximum > out.maximum { out.maximum = value.maximum; } out.flexible = out.flexible || value.flexible; }
            arm = p.nodes[arm].next;
        }
        out.construct = true; return out;
    }
    if kind == N_BINARY {
        let left = check_flex_integer(p, c, p.nodes[node].left, depth + 1); if !left.valid { return CheckFlex {}; }
        let n_right = p.nodes[node].right;
        if n_int == T_SHL || n_int == T_SHR {
            if !check_integer(check_numeric_value_type(p, p.nodes[n_right].type_id)) { return CheckFlex {}; }
            var out = left; out.flexible = true; return out;
        }
        if n_int == T_PLUS || n_int == T_MINUS || n_int == T_MUL || n_int == T_DIV || n_int == T_MOD || n_int == T_BITAND || n_int == T_BITOR || n_int == T_XOR {
            let right = check_flex_integer(p, c, n_right, depth + 1);
            if !right.valid || !left.flexible && !right.flexible && !left.construct && !right.construct { return CheckFlex {}; }
            var out = left; out.flexible = true; out.construct = false;
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
    if n.kind == N_BLOCK && (n.flags & F_TAIL) != 0 { check_retype_integer(p, c, n.last, type_id); p.nodes[node].type_id = type_id as i32; return; }
    if n.kind == N_IF {
        check_retype_integer(p, c, n.right, type_id); check_retype_integer(p, c, n.third, type_id); p.nodes[node].type_id = type_id as i32; return;
    }
    if n.kind == N_MATCH {
        var arm = n.first;
        while arm >= 0 { check_retype_integer(p, c, p.nodes[arm].right, type_id); arm = p.nodes[arm].next; }
        p.nodes[node].type_id = type_id as i32; return;
    }
    if n.kind == N_BINARY {
        check_retype_integer(p, c, n.left, type_id);
        if n.integer != T_SHL && n.integer != T_SHR { check_retype_integer(p, c, n.right, type_id); }
        p.nodes[node].type_id = type_id as i32; p.nodes[node].aux = type_id; return;
    }
    if n.kind == N_UNARY && n.integer == T_BITNOT { check_retype_integer(p, c, n.left, type_id); p.nodes[node].type_id = type_id as i32; return; }
    check_expect(p, c, node, n.type_id, type_id);
}

recursive fn check_float_literal_tree(p: Program&, node: i64, depth: i64) -> bool {
    if node < 0 || depth > 64 { return false; }
    let n: const Node& = p.nodes[node];
    if n.kind == N_FLOAT || n.kind == N_INTEGER { return true; }
    if n.kind == N_NAME && n.symbol >= 0 && check_float(check_numeric_value_type(p, n.type_id)) {
        let symbol: const Symbol& = p.symbols[n.symbol]; let declaration = symbol.node;
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
    let n: const Node& = p.nodes[node];
    if n.kind == N_FLOAT || n.kind == N_INTEGER { return true; }
    if n.kind == N_NAME && n.symbol >= 0 {
        let symbol: const Symbol& = p.symbols[n.symbol]; let declaration = symbol.node;
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
    let n: const Node& = p.nodes[node];
    if n.kind == N_NAME && n.symbol >= 0 {
        let symbol: const Symbol& = p.symbols[n.symbol]; let declaration = symbol.node;
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
        var symbol: i64 = n.symbol; if symbol < 0 { symbol = check_lookup_name(p, c, node); } if symbol < 0 { return; }
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
fn check_nonnegative_result(p: Program&, c: Checker&, node: i64, orig_kind: i64, orig_integer: i64, orig_flags: i64, orig_right: i64, orig_third: i64, result: i64) {
    var proof = -2;
    if result >= 0 && p.types[result].kind == TY_INT {
        let n: const Node& = p.nodes[node];
        if orig_kind == N_INTEGER && (orig_integer >= 0 || (orig_flags & F_UNSIGNED) != 0) { proof = -1; }
        else if orig_kind == N_NAME && n.symbol >= 0 {
            let index = check_variable_index(c, n.symbol);
            if index >= 0 && c.variables[index].nonnegative >= -1 { proof = n.symbol; }
        } else if n.kind == N_CALL && (n.flags & F_PROPERTY) != 0 && n.symbol >= 0 && (p.symbols[n.symbol].flags & S_BUILTIN) != 0 {
            let builtin = p.symbols[n.symbol].index;
            if builtin == 21 || builtin == 22 { proof = -1; }
        } else if orig_kind == N_BLOCK && (n.flags & F_TAIL) != 0 && (n.flags & F_EARLY) == 0 {
            proof = check_nonnegative_get(c, n.last);
        } else if orig_kind == N_IF && orig_third >= 0 {
            if check_bottom(p, orig_right) { proof = check_nonnegative_get(c, orig_third); }
            else if check_bottom(p, orig_third) { proof = check_nonnegative_get(c, orig_right); }
            else if check_integer_constants(p, c, node) {
                let constants = check_flex_integer(p, c, node);
                if constants.valid && !constants.flexible && constants.minimum >= 0 { check_rely_named(p, c, node); proof = -1; }
            }
        } else if orig_kind == N_MATCH && check_integer_constants(p, c, node) {
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
    p.nodes[node] = Node { flags: F_CHECKED | F_SYNTHETIC | (original.flags & F_TAIL), kind: N_CAST as i32,
                    token: original.token, next: original.next, left: left as i32, right: syntax as i32,
                    type_id: type_id as i32, scope: original.scope };
}
recursive fn check_retype_float(p: Program&, c: Checker&, node: i64, type_id: i64) {
    if node < 0 || p.nodes[node].type_id == type_id { return; }
    let n = p.nodes[node];
    if check_integer(check_numeric_value_type(p, n.type_id)) { check_wrap_numeric_cast(p, node, type_id); return; }
    if n.kind == N_FLOAT { p.nodes[node].type_id = type_id as i32; return; }
    if n.kind == N_BLOCK && (n.flags & F_TAIL) != 0 { check_retype_float(p, c, n.last, type_id); p.nodes[node].type_id = type_id as i32; return; }
    if n.kind == N_IF {
        check_retype_float(p, c, n.right, type_id); check_retype_float(p, c, n.third, type_id); p.nodes[node].type_id = type_id as i32; return;
    }
    if n.kind == N_BINARY && !check_float_constant_tree(p, node, 0) {
        check_retype_float(p, c, n.left, type_id); check_retype_float(p, c, n.right, type_id);
        p.nodes[node].type_id = type_id as i32; p.nodes[node].aux = type_id; return;
    }
    if n.kind == N_UNARY && n.integer == T_MINUS && !check_float_constant_tree(p, node, 0) {
        check_retype_float(p, c, n.left, type_id); p.nodes[node].type_id = type_id as i32; return;
    }
    // Named literal-like floats keep their stored f64 value. Their use
    // rounds that value; only an unfixed computation changes its operations.
    check_wrap_numeric_cast(p, node, type_id);
}

recursive fn check_complement_input(p: Program&, c: Checker&, node: i64, depth: i64 = 0) -> CheckConstant {
    if node < 0 || depth > 64 { return CheckConstant {}; }
    let kind = p.nodes[node].kind;
    if kind == N_UNARY && p.nodes[node].integer == T_BITNOT {
        let n_left = p.nodes[node].left;
        let value = check_constant(p, c, n_left, 0);
        if value.valid && value.value >= 0 && check_literal_tree(p, n_left, 0) { return value; }
    }
    if kind == N_NAME {
        var symbol: i64 = p.nodes[node].symbol; if symbol < 0 { symbol = check_lookup_name(p, c, node); }
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
    let n: const Node& = p.nodes[node];
    // default<T[:]>() is a typed empty slice, not an untyped [] literal.
    if n.kind == N_ARRAY { return n.first < 0 && n.right < 0 && !((n.flags & F_DEFAULT) != 0 && n.type_id >= 0 && p.types[n.type_id].kind == TY_SLICE); }
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
    let n: const Node& = p.nodes[node];
    // default<T[:]>() is an empty slice of no storage, not a temporary.
    if n.kind == N_ARRAY && n.first < 0 && (n.flags & F_DEFAULT) != 0 && n.type_id >= 0 && p.types[n.type_id].kind == TY_SLICE { return false; }
    if n.kind == N_ARRAY || n.kind == N_FILL { return true; }
    if n.kind == N_BLOCK && (n.flags & F_TAIL) != 0 { return check_branch_array_literal(p, n.last); }
    if n.kind == N_IF { return check_branch_array_literal(p, n.right) || check_branch_array_literal(p, n.third); }
    if n.kind == N_MATCH { var arm = n.first; while arm >= 0 { if check_branch_array_literal(p, p.nodes[arm].right) { return true; } arm = p.nodes[arm].next; } }
    return false;
}
fn check_storage_type(p: Program&, node: i64) -> i64 {
    let n: const Node& = p.nodes[node];
    if n.kind == N_NAME && n.symbol >= 0 && n.symbol < p.symbols.len { return p.symbols[n.symbol].type_id; }
    if n.kind == N_MEMBER && n.symbol >= 0 { return p.nodes[n.symbol].type_id; }
    if n.kind == N_INDEX {
        var array: i64 = p.nodes[n.left].type_id;
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
    let kind = p.nodes[node].kind;
    if kind == N_FUNCTION || kind == N_FUNCTION_VALUE || kind == N_IMPORT { return 0; }
    let n_left = p.nodes[node].left;
    if kind == N_BREAK && p.nodes[node].symbol == target {
        if n_left < 0 { if expected == TYPE_VOID { return 0; } return -1; }
        return check_conversion(p, c, n_left, p.nodes[n_left].type_id, expected);
    }
    let n_right = p.nodes[node].right; let n_third = p.nodes[node].third;
    var score = 0; var child = p.nodes[node].first;
    while child >= 0 { let value = check_exit_conversion(p, c, child, target, expected); if value < 0 { return -1; } if value > score { score = value; } child = p.nodes[child].next; }
    let left = check_exit_conversion(p, c, n_left, target, expected); if left < 0 { return -1; } if left > score { score = left; }
    let right = check_exit_conversion(p, c, n_right, target, expected); if right < 0 { return -1; } if right > score { score = right; }
    if kind != N_CALL { let third = check_exit_conversion(p, c, n_third, target, expected); if third < 0 { return -1; } if third > score { score = third; } }
    return score;
}
recursive fn check_exit_expect(p: Program&, c: Checker&, node: i64, target: i64, expected: i64) {
    if node < 0 { return; }
    let kind = p.nodes[node].kind;
    if kind == N_FUNCTION || kind == N_FUNCTION_VALUE || kind == N_IMPORT { return; }
    let n_left = p.nodes[node].left;
    if kind == N_BREAK && p.nodes[node].symbol == target {
        if n_left >= 0 {
            check_value(p, c, n_left, expected);
            check_copy_roots(c, target, n_left);
        }
        return;
    }
    let n_right = p.nodes[node].right; let n_third = p.nodes[node].third;
    var child = p.nodes[node].first;
    while child >= 0 { check_exit_expect(p, c, child, target, expected); child = p.nodes[child].next; }
    check_exit_expect(p, c, n_left, target, expected); check_exit_expect(p, c, n_right, target, expected);
    if kind != N_CALL { check_exit_expect(p, c, n_third, target, expected); }
}
// default<T>() of a fixed array is a value, not a literal: converting it to a
// static capacity it exceeds aborts at run time like any stored array (§4.2,
// §9.3). It keeps its own type, and the conversion checks its length.
fn check_default_overflow(p: Program&, node: i64, source: i64, destination: i64) -> bool {
    if node < 0 || source < 0 || destination < 0 { return false; }
    let n: const Node& = p.nodes[node];
    if n.kind != N_ARRAY && n.kind != N_FILL || (n.flags & F_DEFAULT) == 0 { return false; }
    let s: const Type& = p.types[source]; let d: const Type& = p.types[destination];
    return s.kind == TY_ARRAY && s.array_kind == A_FIXED && d.kind == TY_ARRAY && d.array_kind == A_LIMITED &&
        d.count >= 0 && s.count > d.count && check_same_type(p, s.element, d.element);
}
recursive fn check_conversion(p: Program&, c: Checker&, expression: i64, source_type: i64, destination_type: i64) -> i64 {
    if destination_type < 0 { return 0; }
    let expr_kind = p.nodes[expression].kind;
    let dst_kind = p.types[destination_type].kind;
    if source_type == destination_type && p.types[destination_type].index_type < 0 &&
       expr_kind != N_ARRAY && expr_kind != N_FILL && expr_kind != N_LOOP &&
       expr_kind != N_BLOCK && expr_kind != N_IF && expr_kind != N_MATCH &&
       !(expr_kind == N_UNARY && dst_kind == TY_REF) {
        return 0;
    }
    if check_bottom(p, expression) { return 0; }
    if dst_kind == TY_INT && p.types[destination_type].index_type >= 0 {
        let actual = check_index_value(p, expression, source_type);
        if actual < 0 || p.types[actual].kind != TY_INT || p.types[actual].index_type < 0 { return -1; }
        let a: const Type& = p.types[actual]; let d: const Type& = p.types[destination_type];
        if a.pool != d.pool || (a.flags & F_BOUND_TYPE) != 0 && (d.flags & F_BOUND_TYPE) == 0 || a.count > d.count { return -1; }
        if check_same_type(p, actual, destination_type) { return 0; } return 2;
    }
    var source = check_numeric_value_type(p, source_type); let destination = check_numeric_value_type(p, destination_type);
    if destination >= 0 && p.types[destination].kind == TY_REF {
        source = source_type;
        if expr_kind == N_UNARY && p.nodes[expression].integer == T_MUL && (p.nodes[expression].flags & F_SYNTHETIC) != 0 {
            let nl = p.nodes[expression].left;
            return check_conversion(p, c, nl, p.nodes[nl].type_id, destination);
        }
        // Binding storage by reference never adds const to the referenced
        // type: a reference to a const slice could rebind a mutable one to a
        // read-only view (upstream UnifyArgRaw: the pointee must be TypeEq).
        let storage = check_storage_type(p, expression); let pointee = p.types[destination].element;
        if check_addressable(p, expression) && check_operation_same(p, storage, pointee) &&
           !((p.types[pointee].flags & TF_CONST) != 0 && (p.types[storage].flags & TF_CONST) == 0) { source = pointee; }
    }
    if destination < 0 || check_bottom(p, expression) { return 0; }
    if source < 0 { return -1; }
    let b_flags = p.nodes[expression].flags;
    if !c.literal_comparison && (expr_kind == N_ARRAY || expr_kind == N_FILL) && p.nodes[expression].first >= 0 &&
       (p.types[destination].kind == TY_SLICE || p.types[destination].kind == TY_REF) && check_size_class(p, source, 0) > 0 { return -1; }
    if expr_kind == N_LOOP { return check_exit_conversion(p, c, p.nodes[expression].right, expression, destination); }
    if expr_kind == N_BLOCK && (b_flags & F_EARLY) != 0 {
        let exits = check_exit_conversion(p, c, expression, expression, destination);
        if exits < 0 { return -1; }
        let blast = p.nodes[expression].last;
        if (b_flags & F_TAIL) == 0 || blast < 0 || check_bottom(p, blast) {
            if source == TYPE_VOID && destination != TYPE_VOID { return -1; }
            return exits;
        }
    }
    if expr_kind == N_BLOCK && (b_flags & F_TAIL) != 0 && p.nodes[expression].last >= 0 {
        let blast = p.nodes[expression].last;
        return check_conversion(p, c, blast, p.nodes[blast].type_id, destination);
    }
    if expr_kind == N_IF {
        let bthird = p.nodes[expression].third;
        if bthird < 0 { return -1; }
        let bright = p.nodes[expression].right;
        let a = check_conversion(p, c, bright, p.nodes[bright].type_id, destination);
        let b = check_conversion(p, c, bthird, p.nodes[bthird].type_id, destination);
        if a < 0 || b < 0 { return -1; }
        if a > b { return a; } return b;
    }
    if expr_kind == N_MATCH {
        var arm = p.nodes[expression].first; var score = 0;
        while arm >= 0 {
            let body = p.nodes[arm].right; let conversion = check_conversion(p, c, body, p.nodes[body].type_id, destination);
            if conversion < 0 { return -1; }
            if conversion > score { score = conversion; } arm = p.nodes[arm].next;
        }
        return score;
    }
    if check_same_type(p, source, destination) { return 0; }
    if check_integer(destination) && check_flex_fits(p, c, expression, destination) { return 1; }
    if check_literal_parameter(p, expression) && (check_integer(source) || check_float(source)) &&
       (check_float(destination) || check_integer(source) && check_integer(destination)) { return 1; }
    if check_width_constant(p, c, expression, destination).valid { return 1; }
    let sk = p.types[source].kind; let dk = p.types[destination].kind;
    if sk == TY_GENERIC || dk == TY_GENERIC { return 1; }
    if sk == TY_BOOL && dk == TY_BOOL { return 1; }
    if expr_kind == N_INTEGER && check_integer(destination) {
        if (b_flags & F_UNSIGNED) != 0 { if destination == TYPE_U64 { return 1; } return -1; }
        let n_int = p.nodes[expression].integer;
        if n_int >= check_min(destination) && n_int <= check_max(destination) { return 1; }
        return -1;
    }
    if check_integer(destination) && check_literal_tree(p, expression, 0) {
        let constant = check_constant(p, c, expression, 0);
        // A u64 constant above i64.max is held as a negative value; it fits only u64.
        if constant.valid && check_constant_fits(constant, destination) { return 1; }
    }
    if check_float(destination) && check_float_literal_tree(p, expression, 0) { return 1; }
    if check_integer(source) && check_float(destination) { return 4; }
    if source == TYPE_F32 && destination == TYPE_F64 { return 2; }
    if check_integer(source) && check_integer(destination) {
        let sb = check_integer_bits(source); let db = check_integer_bits(destination);
        if check_unsigned(source) == check_unsigned(destination) && sb < db { return 2; }
        if check_unsigned(source) && !check_unsigned(destination) && sb < db { return 2; }
    }
    let s_elem = p.types[source].element; let d_elem = p.types[destination].element;
    let s_flags = p.types[source].flags; let d_flags = p.types[destination].flags;
    if sk == TY_REF && dk != TY_REF {
        if dk == TY_SLICE && (s_flags & TF_CONST) != 0 && (d_flags & TF_CONST) == 0 && s_elem >= 0 &&
           (p.types[s_elem].kind == TY_ARRAY || p.types[s_elem].kind == TY_SLICE) { return -1; }
        return check_conversion(p, c, expression, s_elem, destination);
    }
    if dk == TY_REF {
        if expr_kind == N_NULL && (d_flags & TF_OPTIONAL) != 0 { return 1; }
        if sk == TY_REF && check_operation_same(p, s_elem, d_elem) {
            if (s_flags & TF_CONST) != 0 && (d_flags & TF_CONST) == 0 { return -1; }
            if (s_flags & TF_OPTIONAL) != 0 && (d_flags & TF_OPTIONAL) == 0 { return -1; }
            // Relative widths describe stored offsets. Loaded references
            // convert as pointers; the lifetime pass proves each relative store.
            return 1;
        }
        if check_same_type(p, source, d_elem) && check_addressable(p, expression) { return 2; }
    }
    if (expr_kind == N_ARRAY || expr_kind == N_FILL) && sk == TY_ARRAY && (dk == TY_ARRAY || dk == TY_SLICE) {
        if dk == TY_ARRAY && p.types[destination].array_kind == A_FIXED && p.types[source].count != p.types[destination].count { return -1; }
        if check_default_overflow(p, expression, source, destination) { return 3; }
        if dk == TY_ARRAY && p.types[destination].array_kind == A_LIMITED && p.types[destination].count >= 0 && p.types[source].count > p.types[destination].count { return -1; }
        var element = p.nodes[expression].first;
        while element >= 0 {
            if check_conversion(p, c, element, p.nodes[element].type_id, d_elem) < 0 { return -1; }
            element = p.nodes[element].next;
        }
        return 2;
    }
    if sk == TY_ARRAY && s_elem < 0 && check_empty_tree(p, expression) && (dk == TY_ARRAY || dk == TY_SLICE) { return 2; }
    if dk == TY_SLICE && (sk == TY_ARRAY || sk == TY_SLICE) &&
       check_same_type(p, s_elem, d_elem) {
        let actual = p.nodes[expression].type_id;
        let whole = actual >= 0 && (p.types[actual].kind == TY_ARRAY || p.types[actual].kind == TY_SLICE);
        if (d_flags & TF_CONST) == 0 && expr_kind != N_STRING && ((s_flags & TF_CONST) != 0 || whole && check_readonly(p, c, expression)) { return -1; }
        return 2;
    }
    if dk == TY_ARRAY && (sk == TY_ARRAY || sk == TY_SLICE) && check_same_type(p, s_elem, d_elem) {
        if p.types[destination].array_kind == A_FIXED && p.types[source].count >= 0 && p.types[destination].count != p.types[source].count { return -1; }
        // Only a literal must fit a static capacity when compiled (§4.2);
        // a stored array's length is checked against it at run time (§9.3).
        return 3;
    }
    if expr_kind == N_STRING && dk == TY_ARRAY && d_elem == TYPE_U8 { return 2; }
    if dk == TY_ENUM && sk == TY_STRUCT && p.types[source].pool >= 0 && p.types[p.types[source].pool].declaration == p.types[destination].declaration { return 1; }
    if sk == TY_ENUM && dk == TY_ENUM && p.types[source].declaration == p.types[destination].declaration { return 2; }
    if sk == TY_STRUCT && dk == TY_STRUCT && p.types[source].declaration == p.types[destination].declaration && (s_flags & ~TF_CONST) == (d_flags & ~TF_CONST) { return 1; }
    if sk == TY_TUPLE && dk == TY_TUPLE && p.types[source].count == p.types[destination].count {
        var sp = p.types[source].first; var dp = p.types[destination].first; var score = 0;
        while sp >= 0 && dp >= 0 {
            let conversion = check_conversion(p, c, expression, p.nodes[sp].type_id, p.nodes[dp].type_id);
            if conversion < 0 { return -1; } if conversion > score { score = conversion; }
            sp = p.nodes[sp].next; dp = p.nodes[dp].next;
        }
        return score;
    }
    return -1;
}
inline fn check_retarget_exits(p: Program&, node: i64, previous: i64, replacement: i64) {
    if node < 0 { return; }
    let rk = p.nodes[replacement].kind;
    if rk != N_BLOCK && rk != N_WHILE && rk != N_FOR && rk != N_LOOP { return; }
    check_retarget_exits_walk(p, node, previous, replacement);
}
recursive fn check_retarget_exits_walk(p: Program&, node: i64, previous: i64, replacement: i64) {
    let n: const Node& = p.nodes[node];
    let kind = n.kind;
    if kind >= N_INTEGER && kind <= N_NAME || kind == N_EMPTY || kind == N_FUNCTION || kind == N_FUNCTION_VALUE { return; }
    if (kind == N_BREAK || kind == N_CONTINUE) && n.symbol == previous { p.nodes[node].symbol = replacement as i32; }
    var child = n.first;
    while child >= 0 {
        let ck = p.nodes[child].kind;
        if ck < N_INTEGER || ck > N_NAME { check_retarget_exits_walk(p, child, previous, replacement); }
        child = p.nodes[child].next;
    }
    // A break's values are the list at its left; a later one may hold an exit.
    if kind == N_BREAK {
        child = n.left;
        while child >= 0 {
            let ck = p.nodes[child].kind;
            if ck < N_INTEGER || ck > N_NAME { check_retarget_exits_walk(p, child, previous, replacement); }
            child = p.nodes[child].next;
        }
    } else if n.left >= 0 {
        let lk = p.nodes[n.left].kind;
        if lk < N_INTEGER || lk > N_NAME { check_retarget_exits_walk(p, n.left, previous, replacement); }
    }
    if n.right >= 0 {
        let rk = p.nodes[n.right].kind;
        if rk < N_INTEGER || rk > N_NAME { check_retarget_exits_walk(p, n.right, previous, replacement); }
    }
    if n.third >= 0 {
        let tk = p.nodes[n.third].kind;
        if tk < N_INTEGER || tk > N_NAME { check_retarget_exits_walk(p, n.third, previous, replacement); }
    }
}

fn check_wrap_unary(p: Program&, node: i64, op: i64, ty: i64) {
    var original = p.nodes[node]; let next = original.next; original.next = -1;
    let inner = p.nodes.len; p.nodes.push(original); check_retarget_exits(p, inner, node, inner);
    p.nodes[node] = Node { integer: op, flags: F_CHECKED | F_SYNTHETIC | (original.flags & F_TAIL), kind: N_UNARY as i32,
                    token: original.token, next: next, left: inner as i32, type_id: ty as i32, scope: original.scope,
                    coerced_type: original.coerced_type };
    if op == T_MUL { p.nodes[node].aux = ty; }
}
fn check_mark_coercion(p: Program&, expression: i64, expected: i64) {
    var node = expression;
    while node >= 0 {
        p.nodes[node].coerced_type = expected as i32; let n = p.nodes[node];
        if n.kind != N_UNARY || n.integer != T_MUL || (n.flags & F_SYNTHETIC) == 0 { break; }
        node = n.left;
    }
}
// Rich error-only diagnostic helpers (never called on valid programs).
inline fn diag_lower_byte(b: u8) -> u8 {
    if b >= 'A' && b <= 'Z' { return b + 32; }
    return b;
}
fn diag_edit_distance(a: const u8[:], b: const u8[:], limit: i64) -> i64 {
    let m = a.len; let n = b.len;
    if m == 0 || n == 0 || m > 64 || n > 64 { return limit + 1; }
    var diff = m - n; if diff < 0 { diff = -diff; }
    if diff > limit { return limit + 1; }
    var prev2: i64[65] = [0; 65];
    var prev: i64[65] = [0; 65];
    var curr: i64[65] = [0; 65];
    for j in 0..n + 1 { prev[j] = j; prev2[j] = j; }
    for i in 1..m + 1 {
        curr[0] = i;
        var row_min = i;
        let ca = diag_lower_byte(a[i - 1]);
        var ca_prev: u8 = 0; if i > 1 { ca_prev = diag_lower_byte(a[i - 2]); }
        for j in 1..n + 1 {
            let cb = diag_lower_byte(b[j - 1]);
            var cost: i64 = 1;
            if ca == cb { cost = 0; }
            var best = prev[j] + 1;
            if curr[j - 1] + 1 < best { best = curr[j - 1] + 1; }
            if prev[j - 1] + cost < best { best = prev[j - 1] + cost; }
            if i > 1 && j > 1 && ca == diag_lower_byte(b[j - 2]) && ca_prev == cb {
                if prev2[j - 2] + 1 < best { best = prev2[j - 2] + 1; }
            }
            curr[j] = best;
            if best < row_min { row_min = best; }
        }
        if row_min > limit { return limit + 1; }
        for j in 0..n + 1 { prev2[j] = prev[j]; prev[j] = curr[j]; }
    }
    return prev[n];
}
fn diag_consider_symbol(p: Program&, sym_id: i64, want: const u8[:], role: i64, best_tok: i64&, best_dist: i64&) {
    if sym_id < 0 || sym_id >= p.symbols.len { return; }
    let s: const Symbol& = p.symbols[sym_id];
    if s.name_token < 0 || s.name_token >= p.tokens.len { return; }
    if (s.flags & S_BUILTIN) != 0 { return; }
    if role == S_TYPE && (s.flags & S_TYPE) == 0 { return; }
    if role == S_FUNCTION && (s.flags & S_FUNCTION) == 0 { return; }
    if role == 0 && (s.flags & S_TYPE) != 0 { return; }
    let cand = token_text(p, s.name_token);
    if cand.len == 0 || (cand.len >= 2 && cand[0] == '_' && cand[1] == '_') { return; }
    if same_bytes(cand, want) { return; }
    var lim = 2; if want.len <= 3 { lim = 1; }
    let d = diag_edit_distance(want, cand, lim);
    if d < best_dist { best_dist = d; best_tok = s.name_token; }
}
fn diag_suggest_name(p: Program&, c: Checker&, want: const u8[:], scope: i64, role: i64, out: u8[>..]&) -> bool {
    if want.len < 2 || want.len > 64 { return false; }
    var best_tok: i64 = -1;
    var best_dist: i64 = 3;
    var cur = scope;
    var steps: i64 = 0;
    var has_large = false;
    while cur >= 0 && cur < c.scopes.len && steps < 128 {
        let sc: const CheckScope& = c.scopes[cur];
        let cnt = sc.decl_count as i64;
        if cnt > 0 && cnt <= 4 {
            for k in 0..cnt {
                diag_consider_symbol(p, sc.small_decls[k] as i64, want, role, best_tok, best_dist);
            }
        } else if cnt > 4 { has_large = true; }
        cur = sc.parent; steps += 1;
    }
    if has_large {
        for li in 0..c.linked.len {
            let sym_id = c.linked[li] as i64;
            let lsc = c.link_scopes[sym_id] as i64;
            var vis = false;
            var walk = scope; var wg: i64 = 0;
            while walk >= 0 && walk < c.scopes.len && wg < 128 {
                if walk == lsc { vis = true; break; }
                walk = c.scopes[walk].parent; wg += 1;
            }
            if vis { diag_consider_symbol(p, sym_id, want, role, best_tok, best_dist); }
        }
    }
    if best_tok >= 0 {
        out.append("; did you mean `"); out.append(token_text(p, best_tok)); out.append("`?");
        return true;
    }
    return false;
}
fn diag_suggest_type(p: Program&, c: Checker&, want: const u8[:], scope: i64, out: u8[>..]&) -> bool {
    if want.len < 2 || want.len > 64 { return false; }
    var lim = 2; if want.len <= 3 { lim = 1; }
    var best_prim: const u8[:] = ""; var prim_dist: i64 = 3;
    for prim in ["i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64", "f32", "f64", "bool", "void", "varint"] {
        let d = diag_edit_distance(want, prim, lim);
        if d < prim_dist { prim_dist = d; best_prim = prim; }
    }
    var best_tok: i64 = -1; var best_dist = prim_dist;
    var cur = scope; var steps: i64 = 0; var has_large = false;
    while cur >= 0 && cur < c.scopes.len && steps < 128 {
        let sc: const CheckScope& = c.scopes[cur];
        let cnt = sc.decl_count as i64;
        if cnt > 0 && cnt <= 4 {
            for k in 0..cnt { diag_consider_symbol(p, sc.small_decls[k] as i64, want, S_TYPE, best_tok, best_dist); }
        } else if cnt > 4 { has_large = true; }
        cur = sc.parent; steps += 1;
    }
    if has_large {
        for li in 0..c.linked.len {
            let sym_id = c.linked[li] as i64;
            let lsc = c.link_scopes[sym_id] as i64;
            var vis = false; var walk = scope; var wg: i64 = 0;
            while walk >= 0 && walk < c.scopes.len && wg < 128 {
                if walk == lsc { vis = true; break; }
                walk = c.scopes[walk].parent; wg += 1;
            }
            if vis { diag_consider_symbol(p, sym_id, want, S_TYPE, best_tok, best_dist); }
        }
    }
    if best_tok >= 0 {
        out.append("; did you mean `"); out.append(token_text(p, best_tok)); out.append("`?");
        return true;
    }
    if best_prim.len > 0 {
        out.append("; did you mean `"); out.append(best_prim); out.append("`?");
        return true;
    }
    return false;
}
fn diag_suggest_member(p: Program&, first: i64, want: const u8[:], label: const u8[:], out: u8[>..]&) {
    var best_tok: i64 = -1; var best_dist: i64 = 3;
    var lim = 2; if want.len <= 3 { lim = 1; }
    var at = first; var count: i64 = 0;
    while at >= 0 {
        let n: const Node& = p.nodes[at];
        if (n.flags & F_PAD) == 0 && n.token >= 0 {
            count += 1;
            let name = token_text(p, n.token);
            let d = diag_edit_distance(want, name, lim);
            if d < best_dist { best_dist = d; best_tok = n.token; }
        }
        at = n.next;
    }
    if best_tok >= 0 {
        out.append("; did you mean `"); out.append(token_text(p, best_tok)); out.append("`?");
        return;
    }
    if count > 0 {
        out.append("\n  note: available "); out.append(label); out.append(": ");
        at = first; var shown: i64 = 0;
        while at >= 0 && shown < 8 {
            let n: const Node& = p.nodes[at];
            if (n.flags & F_PAD) == 0 && n.token >= 0 {
                if shown > 0 { out.append(", "); }
                out.push('`'); out.append(token_text(p, n.token)); out.push('`');
                shown += 1;
            }
            at = n.next;
        }
        if count > 8 { out.append(", ..."); }
    }
}
fn diag_append_type(p: Program&, ty: i64, out: u8[>..]&) {
    if ty < 0 || ty >= p.types.len { out.append("<unknown>"); return; }
    render_type_name(p, ty, out);
}
fn diag_append_fn_sig(p: Program&, fn_node: i64, out: u8[>..]&) {
    let n: const Node& = p.nodes[fn_node];
    out.append("fn ");
    if n.token >= 0 { out.append(token_text(p, n.token)); }
    if n.third >= 0 {
        out.push('<'); var gp = n.third; var gi: i64 = 0;
        while gp >= 0 {
            if gi > 0 { out.append(", "); }
            out.append(token_text(p, p.nodes[gp].token));
            gp = p.nodes[gp].next; gi += 1;
        }
        out.push('>');
    }
    out.push('(');
    var param = n.first; var pi: i64 = 0;
    while param >= 0 {
        if pi > 0 { out.append(", "); }
        let pn: const Node& = p.nodes[param];
        if pn.token >= 0 { out.append(token_text(p, pn.token)); out.append(": "); }
        diag_append_type(p, pn.type_id, out);
        if pn.right >= 0 { out.append(" = ..."); }
        param = pn.next; pi += 1;
    }
    out.push(')');
    if n.type_id >= 0 && p.types[n.type_id].kind == TY_FN {
        let ret = p.types[n.type_id].element;
        if ret >= 0 && ret != TYPE_VOID { out.append(" -> "); diag_append_type(p, ret, out); }
    }
}
fn diag_conversion_help(p: Program&, src: i64, dst: i64, out: u8[>..]&) {
    if src < 0 || dst < 0 || src >= p.types.len || dst >= p.types.len { return; }
    let st: const Type& = p.types[src]; let dt: const Type& = p.types[dst];
    if (st.kind == TY_REF || st.kind == TY_SLICE) && st.kind == dt.kind &&
       (st.flags & TF_CONST) != 0 && (dt.flags & TF_CONST) == 0 {
        out.append("\n  help: cannot drop `const` when converting to a mutable reference/slice; accept `const` or copy the value");
        return;
    }
    if st.kind == TY_REF && (st.flags & TF_OPTIONAL) != 0 && dt.kind == TY_REF && (dt.flags & TF_OPTIONAL) == 0 {
        out.append("\n  help: narrow the optional reference first (e.g. `if x != null { ... }`)");
        return;
    }
    if check_numeric(src) && check_numeric(dst) {
        out.append("\n  help: convert explicitly with `as "); diag_append_type(p, dst, out);
        out.append("` (or `as! "); diag_append_type(p, dst, out); out.append("` for wrapping/bit cast)");
        return;
    }
    if st.kind == TY_ARRAY && dt.kind == TY_SLICE && (st.flags & TF_CONST) != 0 && (dt.flags & TF_CONST) == 0 {
        out.append("\n  help: source array is read-only; target slice must be `const`");
        return;
    }
    if st.kind == TY_SLICE && dt.kind == TY_ARRAY {
        out.append("\n  help: slices do not implicitly convert to owned arrays; copy elements or accept a slice");
        return;
    }
}
fn diag_call_mismatch(p: Program&, c: Checker&, tok: i64, callee_node: i64, args: CheckList&, candidates: CheckList&, ambiguous: bool) {
    // Precompute the first incompatible argument per candidate before opening any growable buffer (§7.8).
    var bad_idx: i64[5] = [-1; 5];
    var bad_formal: i64[5] = [-1; 5];
    var bad_arg: i64[5] = [-1; 5];
    var limit = candidates.count; if limit > 5 { limit = 5; }
    if !ambiguous {
        for ci in 0..limit {
            let sym_id = check_list_at(c, candidates, ci);
            let fn_node = p.symbols[sym_id].node;
            if fn_node < 0 { continue; }
            var min_args: i64 = 0; var max_args: i64 = 0;
            var f0 = p.nodes[fn_node].first;
            while f0 >= 0 {
                if p.nodes[f0].right < 0 { min_args += 1; }
                max_args += 1; f0 = p.nodes[f0].next;
            }
            if args.count >= min_args && args.count <= max_args {
                var formal = p.nodes[fn_node].first; var idx: i64 = 0;
                while formal >= 0 && idx < args.count {
                    let an = check_list_at(c, args, idx);
                    let ft = p.nodes[formal].type_id; let at = p.nodes[an].type_id;
                    if ft >= 0 && at >= 0 && !check_has_generic(p, ft, 0) && check_conversion(p, c, an, at, ft) < 0 {
                        bad_idx[ci] = idx; bad_formal[ci] = formal; bad_arg[ci] = an;
                        break;
                    }
                    formal = p.nodes[formal].next; idx += 1;
                }
            }
        }
    }
    var msg: u8[>..] = [];
    if ambiguous { msg.append("ambiguous call: equally specific overloads match"); }
    else { msg.append("no overload matches this call's argument types and count"); }
    let cname = token_text(p, p.nodes[callee_node].token);
    if cname.len > 0 {
        msg.append(": `"); msg.append(cname); msg.push('(');
        for ai in 0..args.count {
            if ai > 0 { msg.append(", "); }
            let an = check_list_at(c, args, ai);
            diag_append_type(p, p.nodes[an].type_id, msg);
        }
        msg.append(")`");
    }
    if candidates.count == 0 {
        if cname.len > 0 {
            msg.append("\n  note: no function named `"); msg.append(cname); msg.append("` is in scope");
            diag_suggest_name(p, c, cname, c.scope, S_FUNCTION, msg);
        }
        diagnose(p, tok, msg); return;
    }
    for ci in 0..limit {
        let sym_id = check_list_at(c, candidates, ci);
        let fn_node = p.symbols[sym_id].node;
        if fn_node < 0 { continue; }
        msg.append("\n  note: candidate `"); diag_append_fn_sig(p, fn_node, msg); msg.append("` at ");
        format_token_location(p, p.nodes[fn_node].token, msg);
        if !ambiguous {
            var min_args: i64 = 0; var max_args: i64 = 0;
            var formal = p.nodes[fn_node].first;
            while formal >= 0 {
                if p.nodes[formal].right < 0 { min_args += 1; }
                max_args += 1; formal = p.nodes[formal].next;
            }
            if args.count < min_args || args.count > max_args {
                msg.append(" (expects ");
                if min_args == max_args { msg.format(min_args); }
                else { msg.format(min_args); msg.append(".."); msg.format(max_args); }
                msg.append(" args, got "); msg.format(args.count); msg.push(')');
            } else if bad_idx[ci] >= 0 {
                let bf = bad_formal[ci]; let ba = bad_arg[ci];
                msg.append(" (argument "); msg.format(bad_idx[ci] + 1);
                if p.nodes[bf].token >= 0 { msg.append(" `"); msg.append(token_text(p, p.nodes[bf].token)); msg.push('`'); }
                msg.append(": got `"); diag_append_type(p, p.nodes[ba].type_id, msg);
                msg.append("`, expected `"); diag_append_type(p, p.nodes[bf].type_id, msg); msg.append("`)");
            }
        }
    }
    if candidates.count > 5 {
        msg.append("\n  note: ... and "); msg.format(candidates.count - 5); msg.append(" more candidate(s)");
    }
    diagnose(p, tok, msg);
}

recursive fn check_expect(p: Program&, c: Checker&, expression: i64, source: i64, expected: i64) -> i64 {
    if expected < 0 || expected == TYPE_VOID { return source; }
    let expected_kind = p.types[expected].kind;
    if expected_kind == TY_REF || expected_kind == TY_SLICE { p.nodes[expression].flags |= F_REFERENCE_CONTEXT; }
    if check_bottom(p, expression) { return expected; }
    if expected_kind == TY_INT && p.types[expected].index_type >= 0 {
        if check_conversion(p, c, expression, source, expected) < 0 {
            var msg: u8[>..] = [];
            msg.append("index or bound storage requires a checked value of the same named array: got `");
            diag_append_type(p, source, msg); msg.append("`, expected `"); diag_append_type(p, expected, msg); msg.push('`');
            diagnose(p, p.nodes[expression].token, msg); return source;
        }
        return expected;
    }
    let constant = check_width_constant(p, c, expression, expected);
    if constant.valid {
        check_rely_named(p, c, expression);
        let original = p.nodes[expression]; var flags = original.flags & F_TAIL;
        if check_unsigned(check_numeric_value_type(p, expected)) { flags |= F_UNSIGNED; }
        p.nodes[expression] = Node { integer: constant.value, flags: flags | F_CHECKED | F_SYNTHETIC, kind: N_INTEGER as i32,
                              token: original.token, next: original.next, type_id: expected as i32, scope: original.scope };
        return expected;
    }
    if source == TYPE_F64 && expected == TYPE_F32 && check_narrow_context_float(p, c, expression) { return expected; }
    if check_conversion(p, c, expression, source, expected) < 0 {
        var msg: u8[>..] = [];
        msg.append("value cannot implicitly convert to the required type: got `");
        diag_append_type(p, source, msg); msg.append("`, expected `"); diag_append_type(p, expected, msg); msg.push('`');
        diag_conversion_help(p, source, expected, msg);
        diagnose(p, p.nodes[expression].token, msg); return source;
    }
    if source < 0 { return expected; }
    if expected_kind == TY_SLICE { p.nodes[expression].flags &= ~F_ARRAY_JOIN; }
    if check_literal_parameter(p, expression) {
        let from = check_numeric_value_type(p, source); let to = check_numeric_value_type(p, expected);
        if from != to && (check_integer(to) || check_float(to)) {
            check_note_literal_use(c, p.nodes[expression].symbol, to); check_wrap_numeric_cast(p, expression, expected); return expected;
        }
    }
    if source == TYPE_F32 && expected == TYPE_F64 { return expected; }
    let bk = p.nodes[expression].kind; let bflags = p.nodes[expression].flags;
    if bk == N_LOOP || bk == N_BLOCK && (bflags & F_EARLY) != 0 {
        check_exit_expect(p, c, expression, expression, expected);
        if bk == N_LOOP || (bflags & F_TAIL) == 0 { p.nodes[expression].type_id = expected as i32; return expected; }
    }
    if check_integer(expected) && check_flex_integer(p, c, expression).flexible {
        check_rely_named(p, c, expression); check_retype_integer(p, c, expression, expected); return expected;
    }
    if c.reachable && expected_kind == TY_ENUM { check_mark_coercion(p, expression, expected); }
    if source != expected && (check_integer(expected) && check_literal_tree(p, expression, 0) || check_float(expected) && check_float_literal_tree(p, expression, 0)) {
        check_rely_named(p, c, expression);
        if check_float(expected) && check_float(source) { check_retype_float(p, c, expression, expected); return expected; }
    }
    if bk == N_BLOCK && (bflags & F_SYNTHETIC) != 0 && p.types[source].kind == TY_ARRAY && p.types[source].array_kind == A_GROW && expected_kind == TY_SLICE {
        // A lowered builder call still produces its natural owning result.
        // Its receiving slice views that completed value outside the body.
        check_wrap_numeric_cast(p, expression, expected); return expected;
    }
    if expected_kind == TY_REF && bk == N_UNARY && p.nodes[expression].integer == T_MUL && (bflags & F_SYNTHETIC) != 0 {
        let bnext = p.nodes[expression].next;
        var reference = p.nodes[p.nodes[expression].left]; reference.next = bnext; reference.flags |= bflags & F_TAIL; reference.type_id = expected as i32; p.nodes[expression] = reference; return expected;
    }
    if expected_kind == TY_SLICE && (bk == N_BLOCK || bk == N_IF || bk == N_MATCH) && check_branch_array_literal(p, expression) {
        diagnose(p, p.nodes[expression].token, "control-flow slice result refers to a branch temporary");
    }
    if (bk == N_ARRAY || bk == N_FILL) && (expected_kind == TY_ARRAY || expected_kind == TY_SLICE) &&
       !check_default_overflow(p, expression, source, expected) {
        let aty = check_array(p, c, expression, expected); p.nodes[expression].type_id = aty as i32; return expected;
    }
    if bk == N_BLOCK && (bflags & F_TAIL) != 0 && p.nodes[expression].last >= 0 {
        let blast = p.nodes[expression].last;
        check_expect(p, c, blast, p.nodes[blast].type_id, expected); check_copy_roots(c, expression, blast); p.nodes[expression].type_id = expected as i32; return expected;
    }
    if bk == N_IF {
        let bright = p.nodes[expression].right; let bthird = p.nodes[expression].third;
        check_expect(p, c, bright, p.nodes[bright].type_id, expected);
        check_copy_roots(c, expression, bright);
        if bthird >= 0 { check_expect(p, c, bthird, p.nodes[bthird].type_id, expected); check_copy_roots(c, expression, bthird); }
        p.nodes[expression].type_id = expected as i32; return expected;
    }
    if bk == N_MATCH {
        var arm = p.nodes[expression].first;
        while arm >= 0 { let body = p.nodes[arm].right; check_expect(p, c, body, p.nodes[body].type_id, expected); check_copy_roots(c, expression, body); arm = p.nodes[arm].next; }
        p.nodes[expression].type_id = expected as i32; return expected;
    }
    if expected_kind == TY_REF && p.types[source].kind != TY_REF && p.nodes[expression].kind != N_NULL {
        if (p.types[expected].flags & TF_CONST) == 0 && check_borrow_readonly(p, c, expression) {
            diagnose(p, p.nodes[expression].token, "writable reference cannot bind read-only storage");
        }
        let root = check_place_root(p, expression);
        if (p.types[expected].flags & TF_CONST) == 0 { check_named_writable(p, c, root, p.nodes[expression].token); }
        let root_kind = check_reference_kind(p, expression);
        check_require_referenceable(p, c, expression);
        check_wrap_unary(p, expression, T_BITAND, expected); check_add_root(c, expression, root, root_kind);
    } else if p.types[source].kind == TY_REF && expected_kind != TY_REF {
        check_wrap_unary(p, expression, T_MUL, p.types[source].element);
    }
    let kind = p.nodes[expression].kind;
    if kind == N_INTEGER || kind == N_FLOAT || kind == N_ARRAY && expected_kind == TY_ARRAY || kind == N_NULL || kind == N_STRING {
        p.nodes[expression].type_id = expected as i32;
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
    p.nodes[node] = Node { integer: 0, flags: F_CHECKED | F_SYNTHETIC | (producer.flags & (F_TAIL | F_REACHABLE | F_DIVERGES)),
                    kind: N_RESULT as i32, token: producer.token, next: next, left: inner as i32,
                    type_id: selected as i32, scope: producer.scope };
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
        if p.nodes[node].kind != N_CAST && p.types[ty].index_type < 0 { p.nodes[node].type_id = numeric as i32; }
        ty = numeric;
    }
    return check_expect(p, c, node, ty, expected);
}
recursive fn check_proven_nonnull(p: Program&, node: i64) -> bool {
    if node < 0 { return false; }
    let n: const Node& = p.nodes[node];
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
    var narrowed_type = -1;
    if type_id >= 0 && p.types[type_id].kind == TY_REF && (p.types[type_id].flags & TF_OPTIONAL) != 0 && check_proven_nonnull(p, value) {
        var narrowed = p.types[type_id]; narrowed.flags &= ~TF_OPTIONAL;
        narrowed_type = add_type(p, narrowed);
    }
    check_set_narrowed(c, vi, narrowed_type);
}
fn check_logical_apply(c: Checker&, node: i64) {
    for kill in c.logical_kills {
        if kill.node != node { continue; }
        let vi = check_variable_index(c, kill.symbol); if vi >= 0 { check_set_narrowed(c, vi, -1); }
    }
}
// narrowed_variables is a stack of narrowed_count entries; shrinking it would
// invalidate the checker's own references, so its tail is reused instead.
fn check_narrowed_add(c: Checker&, vi: i64) {
    if c.narrowed_count == c.narrowed_variables.len { c.narrowed_variables.push(vi); } else { c.narrowed_variables[c.narrowed_count] = vi; }
    c.narrowed_count += 1;
}
// The variables narrowed now, whose narrowing the right operand may end.
fn check_logical_capture(c: Checker&, narrowed: CheckList&) {
    c.flow_clock += 1; let tag = c.flow_clock; var write = 0;
    for index in 0..c.narrowed_count {
        let vi = c.narrowed_variables[index];
        if c.variables[vi].narrowed < 0 || c.variables[vi].seen == tag { continue; }
        c.variables[vi].seen = tag; c.narrowed_variables[write] = vi; write += 1;
        check_list_push(c, narrowed, c.variables[vi].symbol);
    }
    c.narrowed_count = write;
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
    let kind = p.nodes[node].kind;
    if kind == N_UNARY && p.nodes[node].integer == T_NOT { check_narrow_condition(p, c, p.nodes[node].left, !sense); return; }
    if kind == N_BINARY {
        let op = p.nodes[node].integer; let n_left = p.nodes[node].left; let n_right = p.nodes[node].right;
        if op == T_ANDAND && sense || op == T_OROR && !sense {
            check_narrow_condition(p, c, n_left, sense); check_logical_apply(c, node);
            check_narrow_condition(p, c, n_right, sense); return;
        }
        if op == T_EQ || op == T_NEQ || op == T_DOTEQ || op == T_DOTNEQ {
            var value = -1;
            if p.nodes[n_left].kind == N_NULL { value = n_right; }
            if p.nodes[n_right].kind == N_NULL { value = n_left; }
            if value >= 0 { check_narrow_condition(p, c, value, sense == (op == T_NEQ || op == T_DOTNEQ)); }
            return;
        }
    }
    if kind != N_NAME || !sense { return; }
    let sym = p.nodes[node].symbol;
    if sym < 0 { return; }
    let declared = p.symbols[sym].type_id; let vi = check_variable_index(c, sym);
    if declared < 0 || vi < 0 || p.types[declared].kind != TY_REF { return; }
    var copy = p.types[check_loaded_type(p, declared)]; copy.flags &= ~TF_OPTIONAL;
    check_set_narrowed(c, vi, add_type(p, copy));
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
        if p.nodes[node].kind == N_NAME && p.nodes[node].symbol >= 0 {
            let declared = p.symbols[p.nodes[node].symbol].type_id;
            if declared >= 0 && p.types[declared].kind == TY_REF && (p.types[declared].flags & TF_OPTIONAL) != 0 { let lty = check_loaded_type(p, declared); p.nodes[node].type_id = lty as i32; return; }
        }
        let element = p.types[ty].element;
        if element >= 0 && p.types[element].kind == TY_BOOL { check_wrap_unary(p, node, T_MUL, TYPE_BOOL); p.nodes[node].aux = element; return; }
    }
    diagnose(p, p.nodes[node].token, "condition requires bool or an optional reference");
}
fn check_capture(p: Program&, c: Checker&, symbol: i64) {
    if c.defer_bodies > 0 { check_defer_mention(p, c, symbol); }
    if c.function_node < 0 || symbol < 0 { return; }
    let s_owner = p.symbols[symbol].owner; let s_flags = p.symbols[symbol].flags;
    if s_owner < 0 || s_owner == c.function_node || (s_flags & (S_FUNCTION | S_TYPE)) != 0 { return; }
    p.symbols[symbol].flags |= S_CAPTURE;
    p.nodes[c.function_node].flags |= F_CAPTURE;
    var capture = p.nodes[c.function_node].captures; var last = -1;
    while capture >= 0 {
        if p.nodes[capture].symbol == symbol { return; }
        last = capture; capture = p.nodes[capture].next;
    }
    let id = new_node(p, N_BINDING, p.symbols[symbol].name_token); p.nodes[id].symbol = symbol as i32; p.nodes[id].type_id = p.symbols[symbol].type_id as i32;
    if last < 0 { p.nodes[c.function_node].captures = id as i32; } else { p.nodes[last].next = id as i32; }
}
fn check_parameter_default_name(p: Program&, c: Checker&, node: i64, functions_only: bool) {
    let function_node = c.parameter_default_function;
    if function_node < 0 || node < 0 { return; }
    let n: const Node& = p.nodes[node];
    if n.aux > 1 || n.integer >= 0 && n.integer < p.tokens.len && p.tokens[n.integer].kind == T_COLONCOLON { return; }
    let actual = check_lookup_name(p, c, node);
    if actual >= 0 && p.symbols[actual].node >= c.parameter_default_floor && (p.symbols[actual].flags & S_GLOBAL) == 0 { return; }
    let saved = c.scope; c.scope = p.nodes[function_node].scope;
    let symbol = check_lookup_name(p, c, node); c.scope = saved;
    if symbol < 0 { return; } let binding: const Symbol& = p.symbols[symbol];
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
    let saved_location = c.call_location; let saved_location_function = c.call_location_function;
    c.call_location = token; c.call_location_function = c.function_node;
    check_list_push(c, c.default_fields, p.nodes[parameter].token);
    if p.nodes[function_node].scope >= 0 { c.scope = c.scopes[p.nodes[function_node].scope].parent; }
    var bindings = CheckList {};
    let value = check_clone(p, c, p.nodes[parameter].right, bindings);
    let saved_render_reference = c.render_reference; c.render_reference = false;
    check_value(p, c, value, p.nodes[parameter].type_id);
    c.render_reference = saved_render_reference;
    c.default_fields = saved_defaults; c.scope = saved_scope; c.default_body = saved_default_body;
    c.parameter_default_function = saved_parameter_function; c.parameter_default_floor = saved_parameter_floor;
    c.call_location = saved_location; c.call_location_function = saved_location_function;
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
    p.nodes[value].kind = N_SELF as i32; p.nodes[value].type_id = reference; p.nodes[value].symbol = field as i32;
    p.nodes[value].aux = owner; p.nodes[value].scope = c.scope as i32; p.nodes[value].flags |= F_CHECKED;
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
    let id = new_node(p, kind, token); p.nodes[id].type_id = ty as i32; p.nodes[id].flags |= F_DEFAULT;
    if kind == N_RECORD {
        check_layout_nominal(p, c, ty);
        if t.kind == TY_ENUM { p.nodes[id].symbol = p.types[ty].first as i32; }
    } else if kind == N_ARRAY && t.kind == TY_ARRAY && t.array_kind == A_FIXED && t.count > 0 {
        p.nodes[id].kind = N_FILL as i32;
        let element = check_default_syntax(p, c, t.element, token, depth + 1);
        let count = new_node(p, N_INTEGER, token); p.nodes[count].integer = t.count; p.nodes[count].type_id = TYPE_I64 as i32; p.nodes[count].flags |= F_CHECKED;
        p.nodes[id].first = element as i32; p.nodes[id].last = element as i32; p.nodes[id].right = count as i32;
    } else if kind != N_ARRAY || t.kind == TY_SLICE { p.nodes[id].flags |= F_CHECKED; }
    return id;
}
recursive fn check_default(p: Program&, c: Checker&, ty: i64, token: i64, depth: i64) -> i64 {
    let value = check_default_syntax(p, c, ty, token, depth);
    if value >= 0 { check_expression(p, c, value, ty); }
    return value;
}

recursive fn check_array(p: Program&, c: Checker&, node: i64, expected: i64) -> i64 {
    let n_kind = p.nodes[node].kind; let n_first = p.nodes[node].first; let n_flags = p.nodes[node].flags;
    let n_ty = p.nodes[node].type_id; let n_third = p.nodes[node].third; let n_right = p.nodes[node].right;
    let n_tok = p.nodes[node].token;
    var element = -1; var count = check_list_count(p, n_first);
    if n_kind == N_ARRAY && n_first < 0 && (n_flags & F_DEFAULT) != 0 && n_ty >= 0 && p.types[n_ty].kind == TY_SLICE &&
       (expected < 0 || p.types[expected].kind == TY_SLICE) { return n_ty; }
    if n_third >= 0 { check_value(p, c, n_third, TYPE_I64); }
    if expected >= 0 && (p.types[expected].kind == TY_ARRAY || p.types[expected].kind == TY_SLICE) {
        element = p.types[expected].element;
    }
    if !c.literal_comparison && expected >= 0 && p.types[expected].kind == TY_SLICE && element >= 0 && check_size_class(p, element, 0) > 0 && (n_first >= 0 || p.types[element].storage != 1) {
        diagnose(p, n_tok, "variable-size array elements require a construction context before viewing");
    }
    var child = n_first;
    while child >= 0 {
        let ty = check_index_value(p, child, check_value(p, c, child, element)); check_slot_value(p, c, child, element, true);
        if element < 0 { element = ty; }
        check_copy_roots(c, node, child); child = p.nodes[child].next;
    }
    if n_right >= 0 {
        check_constant_names(p, c, n_right);
        check_value(p, c, n_right, TYPE_I64);
        let constant = check_constant(p, c, n_right, 0);
        if constant.valid {
            if constant.value < 0 { diagnose(p, n_tok, "array repetition count must be nonnegative"); }
            count = constant.value;
            if p.nodes[n_right].kind != N_INTEGER {
                let literal = operation_integer(p, count, p.nodes[n_right].token);
                p.nodes[literal].type_id = TYPE_I64 as i32;
                p.nodes[literal].flags |= F_CHECKED;
                p.nodes[node].right = literal as i32;
            }
        } else { count = -1; diagnose(p, n_tok, "array repetition count must be a compile-time integer constant"); }
        if check_list_count(p, n_first) != 1 { diagnose(p, n_tok, "array repetition requires one element"); }
    }
    if expected >= 0 && p.types[expected].kind == TY_ARRAY {
        check_array_element(p, c, element, p.types[expected].array_kind, n_tok);
        let d: const Type& = p.types[expected];
        if d.array_kind == A_FIXED && (count < 0 || d.count != count) { diagnose(p, n_tok, "array literal length does not match its fixed destination"); }
        if d.array_kind == A_LIMITED && d.count >= 0 && count > d.count { diagnose(p, n_tok, "array literal exceeds its destination capacity"); }
        return expected;
    }
    if element < 0 { return check_array_type(p, -1, 0, A_GROW, 0); }
    var array_kind = A_FIXED; if count < 0 || check_size_class(p, element, 0) == 1 { array_kind = A_VAR; }
    check_array_element(p, c, element, array_kind, n_tok);
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
        let argument = new_node(p, N_TYPE_ARG, p.nodes[param].token); p.nodes[argument].type_id = type_id as i32;
        if first < 0 { first = argument; } else { p.nodes[last].next = argument as i32; }
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
        var value = n.right; var binding: i64 = n.first; if binding < 0 { binding = node; }
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
    check_body_flush(p, c);
    var visiting = CheckList {}; let value = p.nodes[binding].right;
    return check_init_store_safe(p, c, value, p.nodes[field].type_id) && check_init_safe(p, c, value, visiting);
}

recursive fn check_record(p: Program&, c: Checker&, node: i64, expected: i64) -> i64 {
    check_expand_children(p, c, node);
    let n_left = p.nodes[node].left; let n_type_id = p.nodes[node].type_id;
    let n_tok = p.nodes[node].token; let n_sym = p.nodes[node].symbol;
    let n_first = p.nodes[node].first; let n_right = p.nodes[node].right; let n_flags = p.nodes[node].flags;
    var ty = expected;
    if n_left < 0 && n_type_id >= 0 { ty = n_type_id; }
    if n_left >= 0 {
        let name_kind = p.nodes[n_left].kind; let name_left = p.nodes[n_left].left;
        let name_tok = p.nodes[n_left].token; let name_first = p.nodes[n_left].first;
        if name_kind == N_MEMBER {
            let outer = check_resolve_type(p, c, name_left);
            if outer >= 0 && p.types[outer].kind == TY_ENUM {
                check_layout_nominal(p, c, outer);
                var v = p.types[outer].first;
                while v >= 0 {
                    if same_name(p, p.nodes[v].token, name_tok) { ty = p.nodes[v].type_id; p.nodes[node].symbol = v as i32; break; }
                    v = p.nodes[v].next;
                }
            }
        } else if name_left < 0 {
            let symbol = check_lookup_name(p, c, n_left, S_TYPE);
            var declaration = -1; if symbol >= 0 { declaration = p.symbols[symbol].node; }
            if declaration >= 0 && p.nodes[declaration].kind == N_STRUCT && p.nodes[declaration].third >= 0 && name_first < 0 {
                ty = check_infer_record_type(p, c, declaration, node, expected);
            } else { ty = check_resolve_type(p, c, n_left); }
        } else {
            ty = check_resolve_type(p, c, n_left);
        }
    }
    if ty < 0 || p.types[ty].kind != TY_STRUCT && p.types[ty].kind != TY_ENUM {
        diagnose(p, n_tok, "record literal requires a struct or enum variant type"); return -1;
    }
    check_layout_nominal(p, c, ty); let result_type = ty;
    if root_struct_type(p, ty) && node != c.root_record { diagnose(p, n_tok, "a root owner must be constructed directly at its declaration"); }
    if p.types[ty].kind == TY_ENUM {
        let cur_sym = p.nodes[node].symbol;
        if cur_sym >= 0 && p.nodes[cur_sym].kind == N_VARIANT { ty = p.nodes[cur_sym].type_id; }
        else if n_sym >= 0 && p.nodes[n_sym].kind == N_VARIANT { ty = p.nodes[n_sym].type_id; }
        else { diagnose(p, n_tok, "enum construction requires a named variant"); return -1; }
    }
    let first = p.types[ty].first; var self_type = ty;
    if p.types[ty].pool >= 0 {
        p.nodes[node].symbol = p.types[ty].declaration as i32;
        if expected >= 0 && p.types[expected].kind == TY_ENUM && p.types[expected].declaration == p.types[p.types[ty].pool].declaration { self_type = expected; }
    }
    var binding: i64 = n_first; var positional = first; var seen_named = false; var seen_positional = false;
    var used = CheckList {}; var supplied_bindings = CheckList {}; var source_order: i64 = n_right;
    var prev_ordinal = -1; var inversion = false;
    while binding >= 0 {
        let b_aux = p.nodes[binding].aux; let b_tok = p.nodes[binding].token;
        let b_kind = p.nodes[binding].kind; let b_flags = p.nodes[binding].flags;
        let b_left = p.nodes[binding].left; let b_right = p.nodes[binding].right;
        let b_next = p.nodes[binding].next;
        var field = -1; var ord = 0;
        if b_aux >= 0 && !check_operation_same(p, ty, b_aux) { diagnose(p, b_tok, "const for field accessor belongs to a different aggregate type"); }
        if b_kind == N_EMPTY { binding = b_next; continue; }
        if b_tok >= 0 {
            if (b_flags & F_DEFAULT) == 0 { seen_named = true; } field = first;
            while field >= 0 { if same_name(p, p.nodes[field].token, b_tok) && (p.nodes[field].flags & F_PAD) == 0 { break; } field = p.nodes[field].next; ord += 1; }
        } else {
            if (b_flags & F_DEFAULT) == 0 { seen_positional = true; }
            while positional >= 0 && (p.nodes[positional].flags & F_PAD) != 0 { positional = p.nodes[positional].next; }
            field = positional; if positional >= 0 { positional = p.nodes[positional].next; }
        }
        if field < 0 {
            var msg: u8[>..] = []; msg.append("record initializer names no field");
            if b_tok >= 0 {
                msg.append(": `"); diag_append_type(p, ty, msg); msg.append("` has no field `"); msg.append(token_text(p, b_tok)); msg.push('`');
                diag_suggest_member(p, first, token_text(p, b_tok), "fields", msg);
            } else {
                msg.append(": too many positional initializers for `"); diag_append_type(p, ty, msg); msg.push('`');
            }
            diagnose(p, b_tok, msg);
        }
        else {
            var ui = used.first;
            while ui >= 0 {
                if c.integer_work[ui].value == field {
                    var msg: u8[>..] = [];
                    msg.append("field initialized more than once: `"); msg.append(token_text(p, p.nodes[field].token)); msg.push('`');
                    diagnose(p, b_tok, msg);
                }
                ui = c.integer_work[ui].next;
            }
            if (b_flags & F_DEFAULT) == 0 {
                check_list_push(c, used, field);
                if b_tok >= 0 {
                    if ord < prev_ordinal { inversion = true; }
                    prev_ordinal = ord;
                }
            }
            p.nodes[binding].symbol = field as i32; p.nodes[binding].type_id = p.nodes[field].type_id;
            check_list_push(c, supplied_bindings, binding);
            if b_right < 0 { p.nodes[binding].right = b_left; p.nodes[binding].left = -1; }
        }
        binding = b_next;
    }
    if seen_named && seen_positional { diagnose(p, n_tok, "record literal mixes named and positional initializers"); }
    // Preserve the immutable source ordinals only when a supplied pair inverts.
    if source_order < 0 && seen_named && inversion {
        var last = -1;
        var ui = used.first;
        while ui >= 0 {
            let field = c.integer_work[ui].value; ui = c.integer_work[ui].next;
            var at = first; var ordinal = 0;
            while at >= 0 && at != field { ordinal += 1; at = p.nodes[at].next; }
            let entry = new_node(p, N_TYPE_ARG, p.nodes[field].token); p.nodes[entry].integer = ordinal;
            if source_order < 0 { source_order = entry; } else { p.nodes[last].next = entry as i32; } last = entry;
        }
    }
    p.nodes[node].right = source_order as i32;
    // Put every supplied or omitted initializer in place before checking any.
    var ordered = -1; var last = -1; var field = first;
    var missing_count: i64 = 0; var missing_toks: i64[8] = [-1; 8];
    while field >= 0 {
        let f_flags = p.nodes[field].flags; let f_right = p.nodes[field].right;
        let f_type_id = p.nodes[field].type_id; let f_tok = p.nodes[field].token; let f_next = p.nodes[field].next;
        var init = -1;
        var si = supplied_bindings.first;
        while si >= 0 {
            let candidate = c.integer_work[si].value;
            if p.nodes[candidate].symbol == field { init = candidate; break; }
            si = c.integer_work[si].next;
        }
        if (f_flags & F_PAD) == 0 {
            if init < 0 {
                if f_right < 0 && (n_flags & F_DEFAULT) == 0 && !(f_type_id >= 0 && p.types[f_type_id].kind == TY_REF && (p.types[f_type_id].flags & TF_OPTIONAL) != 0) {
                    if missing_count < 8 { missing_toks[missing_count] = f_tok; }
                    missing_count += 1;
                } else {
                    var value = -1;
                    if f_right >= 0 { var bindings = CheckList {}; value = check_clone(p, c, f_right, bindings); }
                    else { value = check_default_syntax(p, c, f_type_id, n_tok, 1); }
                    init = new_node(p, N_BINDING, f_tok); p.nodes[init].symbol = field as i32; p.nodes[init].type_id = f_type_id;
                    p.nodes[init].right = value as i32; p.nodes[init].flags |= F_DEFAULT;
                }
            }
            if init >= 0 {
                if ordered < 0 { ordered = init; } else { p.nodes[last].next = init as i32; } last = init;
            }
        }
        field = f_next;
    }
    if missing_count > 0 {
        var missing_msg: u8[>..] = [];
        missing_msg.append("record literal leaves a field without an initializer: `");
        diag_append_type(p, ty, missing_msg);
        missing_msg.append("` is missing ");
        var shown = missing_count; if shown > 8 { shown = 8; }
        for mi in 0..shown {
            if mi > 0 { missing_msg.append(", "); }
            missing_msg.push('`'); missing_msg.append(token_text(p, missing_toks[mi])); missing_msg.push('`');
        }
        if missing_count > 8 {
            missing_msg.append(", ... ("); missing_msg.format(missing_count - 8); missing_msg.append(" more)");
        }
        missing_msg.append("\n  help: provide initializers for the missing field(s) or add default values");
        diagnose(p, n_tok, missing_msg);
    }
    if last >= 0 { p.nodes[last].next = -1; }
    p.nodes[node].first = ordered as i32; p.nodes[node].last = last as i32;
    binding = ordered;
    while binding >= 0 {
        let field = p.nodes[binding].symbol; let value = p.nodes[binding].right;
        let b_tok = p.nodes[binding].token; let b_flags = p.nodes[binding].flags;
        let b_type_id = p.nodes[binding].type_id; let b_next = p.nodes[binding].next;
        if value < 0 { diagnose(p, b_tok, "field initializer is missing"); }
        else if (b_flags & F_DEFAULT) != 0 { let def_val = check_field_default(p, c, field, n_tok, 0, self_type, value); p.nodes[binding].right = def_val as i32; }
        else if !check_self_init(p, c, value, field, self_type) { check_value(p, c, value, b_type_id); check_slot_value(p, c, value, b_type_id, true); }
        check_copy_roots(c, node, p.nodes[binding].right); binding = b_next;
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
                    let init = check_init_binding(p, node, low_field); var token = n_tok; if init >= 0 { token = p.nodes[init].token; }
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
    let name = token_text(p, token);
    if name.len < 3 || name.len > 22 { return -1; }
    let first = name[0];
    if first == 'a' {
        if same_bytes(name, "assert") { return 3; }
        if same_bytes(name, "abort") { return 4; }
        if same_bytes(name, "append") { return 25; }
        if same_bytes(name, "alloc_index") { return 30; }
        if same_bytes(name, "alloc_ref") { return 31; }
        if same_bytes(name, "alloc_slice") { return 33; }
        return -1;
    }
    if first == 'b' {
        if same_bytes(name, "bytes_of") { return 17; }
        return -1;
    }
    if first == 'c' {
        if same_bytes(name, "copy") { return 15; }
        if same_bytes(name, "cap") { return 22; }
        if same_bytes(name, "clear") { return 29; }
        if same_bytes(name, "check_length") { return 39; }
        return -1;
    }
    if first == 'd' {
        if same_bytes(name, "default") { return 14; }
        return -1;
    }
    if first == 'e' {
        if same_bytes(name, "exit") { return 5; }
        if same_bytes(name, "embed_shader") { return 19; }
        if same_bytes(name, "embed_file") { return 20; }
        return -1;
    }
    if first == 'f' {
        if same_bytes(name, "format") { return 2; }
        if same_bytes(name, "from_bytes") { return 18; }
        if same_bytes(name, "free") { return 32; }
        if same_bytes(name, "free_slice") { return 35; }
        return -1;
    }
    if first == 'h' {
        if same_bytes(name, "hardware_threads") { return 6; }
        return -1;
    }
    if first == 'i' {
        if same_bytes(name, "index_of") { return 23; }
        return -1;
    }
    if first == 'l' {
        if same_bytes(name, "len") { return 21; }
        return -1;
    }
    if first == 'm' {
        if same_bytes(name, "move_from") { return 40; }
        return -1;
    }
    if first == 'p' {
        if same_bytes(name, "print") { return 0; }
        if same_bytes(name, "push") { return 24; }
        if same_bytes(name, "pop") { return 26; }
        if same_bytes(name, "pop_n") { return 27; }
        return -1;
    }
    if first == 'q' {
        if same_bytes(name, "qput") { return 10; }
        if same_bytes(name, "qget") { return 11; }
        if same_bytes(name, "qpoll") { return 12; }
        if same_bytes(name, "qlimit") { return 13; }
        return -1;
    }
    if first == 'r' {
        if same_bytes(name, "resize") { return 28; }
        if same_bytes(name, "realloc_slice") { return 34; }
        if same_bytes(name, "range_index") { return 38; }
        return -1;
    }
    if first == 's' {
        if same_bytes(name, "str") { return 1; }
        if same_bytes(name, "src_file") { return 36; }
        if same_bytes(name, "src_line") { return 37; }
        return -1;
    }
    if first == 't' {
        if same_bytes(name, "thread_spawn") { return 7; }
        if same_bytes(name, "thread_spawn_contained") { return 8; }
        if same_bytes(name, "thread_wait") { return 9; }
        if same_bytes(name, "to_bytes") { return 16; }
        return -1;
    }
    return -1;
}
fn check_builtin_symbol(p: Program&, token: i64, builtin: i64, result: i64) -> i64 {
    // Builtin symbols are created only here, one per builtin ID.
    if builtin < p.builtin_symbols.len && p.builtin_symbols[builtin] >= 0 { return p.builtin_symbols[builtin]; }
    let type_id = add_type(p, Type { kind: TY_FN, element: result, size: p.pointer_bytes, align: p.pointer_bytes });
    let id = p.symbols.len;
    p.symbols.push(Symbol { name_token: token, type_id: type_id, scope: -2,
        flags: S_FUNCTION | S_BUILTIN, index: builtin });
    while p.builtin_symbols.len <= builtin { p.builtin_symbols.push(-1); }
    p.builtin_symbols[builtin] = id;
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
    var array_type: i64 = p.nodes[receiver].type_id;
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
recursive fn check_type_is_generic(p: Program&, ty: i64, depth: i64 = 0) -> bool {
    if ty < 0 || depth > 32 { return false; }
    if check_has_generic(p, ty, 0) { return true; }
    let t = p.types[ty];
    if t.kind == TY_REF || t.kind == TY_ARRAY || t.kind == TY_SLICE {
        return check_type_is_generic(p, t.element, depth + 1);
    }
    if t.kind == TY_STRUCT || t.kind == TY_ENUM {
        var arg = t.arguments;
        while arg >= 0 {
            if check_type_is_generic(p, p.nodes[arg].type_id, depth + 1) { return true; }
            arg = p.nodes[arg].next;
        }
    }
    return false;
}
recursive fn check_render_hook(p: Program&, c: Checker&, type_id: i64, token: i64) -> i64 {
    if type_id < 0 || check_type_is_generic(p, type_id) { return -1; }
    let t = p.types[type_id]; var namespace_scope = 0;
    if (t.kind == TY_STRUCT || t.kind == TY_ENUM) && t.declaration >= 0 {
        var scope: i64 = p.nodes[t.declaration].scope;
        if t.kind == TY_STRUCT && t.pool >= 0 { scope = p.nodes[p.types[t.pool].declaration].scope; }
        while scope > 0 { if c.scopes[scope].namespace_node >= 0 { namespace_scope = scope; break; } scope = c.scopes[scope].parent; }
    }
    var round = 0;
    while round < 2 {
        var scope = namespace_scope; if round == 1 { scope = 0; }
        // Only symbols named format can qualify; they are indexed once, in order.
        while c.format_symbol_scan < p.symbols.len {
            if token_is(p, p.symbols[c.format_symbol_scan].name_token, "format") { c.format_symbols.push(c.format_symbol_scan); }
            c.format_symbol_scan += 1;
        }
        let count = c.format_symbols.len;
        // Pass 0 checks non-generic format overloads; pass 1 checks generic
        // struct/enum patterns (such as Box<T> or const Opt<T>&), excluding
        // bare type variables, arrays/slices of T, non-generic types, and
        // optional references.
        var pass = 0;
        while pass < 2 {
            if pass == 1 && t.kind != TY_STRUCT && t.kind != TY_ENUM { break; }
            for candidate in 0..count {
                let index = c.format_symbols[candidate]; let symbol = p.symbols[index];
                if symbol.scope != scope || symbol.owner >= 0 || (symbol.flags & (S_FUNCTION | S_BUILTIN)) != S_FUNCTION || symbol.node < 0 || !token_is(p, symbol.name_token, "format") { continue; }
                let n = p.nodes[symbol.node];
                if n.kind != N_FUNCTION || n.origin >= 0 || n.first < 0 { continue; }
                if pass == 0 && n.third >= 0 { continue; }
                if pass == 1 && n.third < 0 { continue; }
                let first = n.first; let second = p.nodes[first].next;
                if second < 0 || p.nodes[second].next >= 0 || p.nodes[first].left < 0 || p.nodes[second].left < 0 { continue; }
                check_prepare_function(p, c, symbol.node);
                let output = p.nodes[first].type_id;
                if output < 0 || p.types[output].kind != TY_REF || (p.types[output].flags & TF_OPTIONAL) != 0 { continue; }
                let array = p.types[output].element;
                if array < 0 || p.types[array].kind != TY_ARRAY || p.types[array].array_kind != A_GROW || p.types[array].element != TYPE_U8 { continue; }
                var value: i64 = p.nodes[second].type_id;
                if value >= 0 && p.types[value].kind == TY_REF && (p.types[value].flags & TF_OPTIONAL) == 0 && p.types[value].length_storage < 0 { value = p.types[value].element; }
                if value < 0 { continue; }
                if pass == 0 {
                    if (p.nodes[symbol.node].flags & F_GENERIC) != 0 { continue; }
                    if t.kind == TY_SLICE && (p.types[value].flags & TF_CONST) != (t.flags & TF_CONST) { continue; }
                    if check_operation_same(p, value, type_id) { return index; }
                } else {
                    if (p.types[value].kind != TY_STRUCT && p.types[value].kind != TY_ENUM) || p.types[value].kind != t.kind { continue; }
                    if !check_type_is_generic(p, value) { continue; }
                    var bindings = CheckList {};
                    if !check_unify(p, c, value, type_id, bindings) { continue; }
                    var all_bound = true;
                    var gp = p.nodes[symbol.node].third;
                    while gp >= 0 {
                        var found = false;
                        for bi in 0..bindings.count {
                            if check_binding_at(c, bindings, bi).parameter == gp { found = true; break; }
                        }
                        if !found { all_bound = false; break; }
                        gp = p.nodes[gp].next;
                    }
                    if !all_bound { continue; }
                    let substituted = check_substitute(p, c, value, bindings);
                    if substituted < 0 || !check_operation_same(p, substituted, type_id) { continue; }
                    let spec = check_specialize_function(p, c, symbol.node, bindings, token);
                    if spec >= 0 { return spec; }
                }
            }
            pass += 1;
        }
        if namespace_scope == 0 { break; } round += 1;
    }
    return -1;
}
recursive fn check_populate_render_hooks(p: Program&, c: Checker&, type_id: i64, token: i64, depth: i64 = 0) {
    if type_id < 0 || depth > 64 { return; }
    while c.render_hooks.len <= type_id { c.render_hooks.push(-2); }
    if c.render_hooks[type_id] != -2 { return; }
    c.render_hooks[type_id] = -1;
    let hook = check_render_hook(p, c, type_id, token);
    c.render_hooks[type_id] = hook;
    let t = p.types[type_id];
    if hook >= 0 && !(t.kind == TY_STRUCT && t.pool >= 0) { return; }
    if t.kind == TY_REF || t.kind == TY_ARRAY || t.kind == TY_SLICE {
        check_populate_render_hooks(p, c, t.element, token, depth + 1);
    } else if t.kind == TY_STRUCT || t.kind == TY_ENUM {
        var field = t.first;
        while field >= 0 {
            if t.kind == TY_ENUM {
                var part = p.nodes[field].first;
                while part >= 0 {
                    check_populate_render_hooks(p, c, p.nodes[part].type_id, token, depth + 1);
                    part = p.nodes[part].next;
                }
            } else if (p.nodes[field].flags & F_PAD) == 0 {
                check_populate_render_hooks(p, c, p.nodes[field].type_id, token, depth + 1);
            }
            field = p.nodes[field].next;
        }
    }
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
    // A helper for a by-value hook takes its own copy. A const-reference
    // hook needs only a read-only borrow of the original argument.
    var hook = -1;
    if type_id >= 0 && type_id < c.render_hooks.len { hook = c.render_hooks[type_id]; }
    var flags = 0;
    if hook >= 0 {
        let formal = p.nodes[p.nodes[p.symbols[hook].node].first].next;
        let parameter = p.nodes[formal].type_id;
        if p.types[parameter].kind != TY_REF && p.types[parameter].kind != TY_SLICE { return parameter; }
        flags = p.types[parameter].flags & TF_CONST;
    } else if p.types[type_id].kind == TY_INT || p.types[type_id].kind == TY_FLOAT || p.types[type_id].kind == TY_BOOL {
        return type_id;
    }
    if check_addressable(p, node) && check_operation_same(p, check_storage_type(p, node), type_id) {
        if check_borrow_readonly(p, c, node) { flags |= TF_CONST; }
        return render_reference(p, type_id, flags);
    }
    return check_const_type(p, type_id);
}
fn check_render_layout(p: Program&, c: Checker&, type_id: i64, token: i64) -> bool {
    if type_id < 0 && p.diagnostics.len > 0 { return false; }
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
    let wasm_default = (p.pointer_bytes == 4 || p.wide) && builtin >= 0 && builtin <= 2;
    if !hooks_exist && !wasm_default { return -2; }
    var first = 0; if builtin == 2 { first = 1; }
    for index in first..args.count { let argument = check_list_at(c, args, index); if !check_render_layout(p, c, p.nodes[argument].type_id, p.nodes[argument].token) { return -1; } }
    if check_has_format_hooks(p, c) {
        for index in first..args.count {
            check_populate_render_hooks(p, c, p.nodes[check_list_at(c, args, index)].type_id, p.nodes[node].token);
        }
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
        let argument = check_list_at(c, args, index); var ty: i64 = p.nodes[argument].type_id;
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
        p.nodes[builder].left = operation_type(p, receiver_reference, original.token) as i32;
        p.nodes[receiver].next = -1; var value = receiver;
        if receiver_kind == A_GROWSHRINK {
            let address = new_node(p, N_UNARY, original.token); p.nodes[address].left = value as i32; p.nodes[address].integer = T_BITAND;
            let cast = new_node(p, N_CAST, original.token); p.nodes[cast].left = address as i32; p.nodes[cast].right = operation_type(p, output_type, original.token) as i32; p.nodes[cast].flags = F_UNSIGNED | F_SYNTHETIC; value = cast;
        }
        p.nodes[builder].right = value as i32;
    } else {
        p.nodes[builder].left = operation_type(p, array_type, original.token) as i32; p.nodes[builder].right = new_node(p, N_ARRAY, original.token) as i32;
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
            p.nodes[temporary].left = operation_type(p, array_type, original.token) as i32; p.nodes[temporary].right = new_node(p, N_ARRAY, original.token) as i32; append_child(p, body, temporary);
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
        let name = operation_name(p, original.token, "print", false); let print_call = new_node(p, N_CALL, original.token); p.nodes[print_call].left = operation_ident(p, name) as i32; p.nodes[print_call].flags = F_FORMAT_RAW | F_SYNTHETIC; append_child(p, print_call, operation_ident(p, out)); append_child(p, body, print_call);
    } else if builtin == 1 { let value = operation_ident(p, out); p.nodes[value].flags |= F_TAIL; p.nodes[body].flags |= F_TAIL; append_child(p, body, value); }
    var result = TYPE_VOID; if builtin == 1 { result = array_type; }
    var lowered = p.nodes[body]; lowered.next = original.next; lowered.flags |= original.flags & F_TAIL; lowered.scope = original.scope;
    p.nodes[node] = lowered;
    return check_expression(p, c, node, result);
}

fn check_builtin_pair(p: Program&, first_type: i64, token: i64) -> i64 {
    let first = new_node(p, N_TYPE_ARG, token); p.nodes[first].type_id = first_type as i32;
    let second = new_node(p, N_TYPE_ARG, token); p.nodes[second].type_id = TYPE_BOOL as i32; p.nodes[first].next = second as i32;
    return check_tuple(p, first);
}
// A branch can carry a pool capability only if every value-producing
// path selects a pool of the same kind.
recursive fn check_pool_branch_flags(p: Program&, c: Checker&, receiver: i64) -> i64 {
    let n: const Node& = p.nodes[receiver];
    var values = CheckList {};
    if n.kind == N_LOOP || n.kind == N_BLOCK && (n.flags & F_EARLY) != 0 {
        check_collect_break_values(p, c, receiver, receiver, values);
    }
    if n.kind == N_BLOCK && (n.flags & F_TAIL) != 0 && !check_bottom(p, n.last) {
        check_list_push(c, values, n.last);
    }
    if n.kind == N_IF {
        if n.right >= 0 && !check_bottom(p, n.right) { check_list_push(c, values, n.right); }
        if n.third >= 0 && !check_bottom(p, n.third) { check_list_push(c, values, n.third); }
    }
    if n.kind == N_MATCH {
        var arm = n.first;
        while arm >= 0 {
            let body = p.nodes[arm].right;
            if !check_bottom(p, body) { check_list_push(c, values, body); }
            arm = p.nodes[arm].next;
        }
    }
    var flags = 0;
    for index in 0..values.count {
        let value = check_list_at(c, values, index);
        if value < 0 { return 0; }
        let other = check_pool_flags(p, c, value, true);
        if other == 0 || flags != 0 && other != flags { return 0; }
        flags = other;
    }
    return flags;
}
recursive fn check_pool_flags(p: Program&, c: Checker&, receiver: i64, expression_roots: bool = false) -> i64 {
    let type_id = p.nodes[receiver].type_id;
    if type_id >= 0 && p.types[type_id].kind == TY_REF && (p.types[type_id].flags & TF_OPTIONAL) != 0 { return 0; }
    if type_id >= 0 && (p.types[type_id].flags & F_REUSABLE) != 0 { return p.types[type_id].flags & (F_REUSABLE | F_REUSABLE_SLICES); }
    let kind = p.nodes[receiver].kind;
    if kind == N_IF || kind == N_MATCH || kind == N_BLOCK || kind == N_LOOP {
        return check_pool_branch_flags(p, c, receiver);
    }
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
    p.types[array].element = element; type_reindex(p, array);
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
    if builtin == 6 || builtin == 12 || builtin == 14 || builtin == 36 || builtin == 37 { minimum = 0; maximum = 0; }
    if builtin == 11 { minimum = 0; maximum = 1; }
    if builtin == 7 || builtin == 8 || builtin == 19 { minimum = 1; maximum = 99; }
    if builtin == 9 || builtin == 16 { maximum = 2; }
    if builtin == 23 || builtin == 24 || builtin == 25 || builtin == 27 || builtin == 30 || builtin == 31 ||
       builtin == 32 || builtin == 33 || builtin == 35 { minimum = 2; maximum = 2; }
    if builtin == 28 || builtin == 38 || builtin == 39 { minimum = 2; maximum = 3; }
    if builtin == 34 { minimum = 3; maximum = 3; }
    if builtin == 40 { minimum = 2; maximum = 2; }
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
        if root_struct_type(p, result) { diagnose(p, n.token, "root owners cannot be copied; bind a reference instead"); }
        if result >= 0 && p.types[result].kind == TY_SLICE { diagnose(p, n.token, "copy takes a stored value or reference, not a slice"); }
        if !check_addressable(p, argument) && !(source >= 0 && p.types[source].kind == TY_REF) { diagnose(p, n.token, "copy of a temporary is unnecessary: its value is already fresh"); }
        if check_type_property(p, result, 6) != 0 { diagnose(p, n.token, "copying values containing self-relative references is unsupported"); }
        if result >= 0 && check_size_class(p, result, 0) == 2 && (p.types[result].kind == TY_ENUM || p.types[result].kind == TY_STRUCT && p.types[result].pool >= 0) { diagnose(p, n.token, "copying a resizable enum or variant is unsupported"); }
        check_copy_roots(c, node, argument);
    } else if builtin == 7 || builtin == 8 {
        let argument = check_list_at(c, args, 0); check_expression(p, c, argument, -1);
        let worker = validation_resolve_thread(p, argument);
        if worker >= 0 { p.nodes[argument].symbol = worker as i32; p.nodes[argument].type_id = p.symbols[worker].type_id as i32; }
        if worker < 0 || p.symbols[worker].node < 0 || (p.nodes[p.symbols[worker].node].flags & F_THREAD) == 0 {
            diagnose(p, n.token, "thread_spawn requires a thread_fn declaration");
        } else {
            let fnnode = p.symbols[worker].node;
            var active = false;
            for index in 0..c.checking_count { if c.checking[index].function_node == fnnode { active = true; break; } }
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
        // A root owner has no single image, even with flat fields.
        if ty >= 0 && (check_contains_refs(p, ty, 0) || root_struct_type(p, ty) || p.types[ty].kind == TY_ARRAY && p.types[ty].element < 0 || p.types[ty].kind == TY_VOID || p.types[ty].kind == TY_FN) { diagnose(p, n.token, "queue messages must be flat values with a concrete element type"); }
        result = TYPE_BOOL;
    } else if builtin == 11 || builtin == 12 || builtin == 13 {
        if type_argument < 0 { diagnose(p, n.token, "queue builtin requires an explicit message type"); return -1; }
        if check_contains_refs(p, type_argument, 0) || root_struct_type(p, type_argument) || p.types[type_argument].kind == TY_VOID || p.types[type_argument].kind == TY_FN { diagnose(p, n.token, "queue message type must be flat"); }
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
        if destination.kind != TY_ARRAY || destination.array_kind != A_GROW && destination.array_kind != A_GROWSHRINK && destination.array_kind != A_VAR {
            diagnose(p, n.token, "from_bytes constructs only a resizable or variable array");
        } else {
            let element = destination.element;
            if check_type_property(p, element, 5) != 0 || root_struct_type(p, element) || check_size_class(p, element, 0) >= 2 {
                diagnose(p, n.token, "from_bytes requires a contiguous image without external references");
            } else if !check_image_links(p, element, element) {
                diagnose(p, n.token, "from_bytes requires relative references to point at an element of the array or one of its variants");
            } else if destination.array_kind == A_GROWSHRINK && check_type_property(p, element, 3) != 0 {
                diagnose(p, n.token, "from_bytes grow-shrink array cannot hold relative references: a shrink would free what they still name");
            }
            check_from_bytes_indices(p, c, element, n.token);
        }
        result = check_builtin_pair(p, type_argument, n.token); check_add_root(c, node, -2);
    } else if builtin == 36 || builtin == 37 {
        // The call's base file name and 1-based line; written in a parameter
        // default, those of the call that left the argument out.
        var at: i64 = n.token;
        if c.call_location >= 0 && c.call_location_function == c.function_node { at = c.call_location; }
        let location = p.tokens[at];
        var replacement = -1;
        if builtin == 37 { replacement = new_node(p, N_INTEGER, at); p.nodes[replacement].integer = location.line; }
        else {
            let source = p.sources[location.source];
            var name: u8[>..] = [];
            name.append(p.text[source.path_start..source.path_start + source.path_len]);
            var base = 0;
            for byte, i in name { if byte == '/' || byte == '\\' { base = i + 1; } }
            var token = location; token.kind = T_STRLIT as i16; token.flags = 0;
            token.text_start = p.text.len as i32; token.text_len = (name.len - base) as i32; p.text.append(name[base..]);
            let token_id = p.tokens.len; p.tokens.push(token);
            replacement = new_node(p, N_STRING, token_id);
        }
        let next = n.next; let scope = n.scope;
        p.nodes[node] = p.nodes[replacement]; p.nodes[node].next = next; p.nodes[node].scope = scope;
        return check_expression(p, c, node, -1);
    } else if builtin == 20 {
        let argument = check_list_at(c, args, 0); check_value(p, c, argument, TYPE_STRING);
        let replacement = source_embed_file(p, node, argument);
        if replacement < 0 { return -1; }
        let next = n.next; let scope = n.scope;
        p.nodes[node] = p.nodes[replacement]; p.nodes[node].next = next; p.nodes[node].scope = scope;
        return check_expression(p, c, node, -1);
    } else if builtin == 19 {
        for i in 0..args.count { check_value(p, c, check_list_at(c, args, i), TYPE_STRING); }
        let replacement = source_embed_shader(p, node);
        if replacement < 0 { return -1; }
        let next = n.next; let scope = n.scope;
        p.nodes[node] = p.nodes[replacement]; p.nodes[node].next = next; p.nodes[node].scope = scope;
        return check_expression(p, c, node, -1);
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
        let write = builtin == 2 || builtin >= 24 && builtin <= 37;
        let receiver = check_array_receiver(p, c, check_list_at(c, args, 0), write);
        if receiver < 0 { return -1; }
        var element = p.types[receiver].element; let array_kind = p.types[receiver].array_kind;
        if builtin >= 38 { result = check_range_builtin(p, c, node, builtin, args, receiver); }
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
        if builtin >= 24 && builtin <= 37 {
            if p.types[receiver].kind != TY_ARRAY || array_kind == A_FIXED || array_kind == A_VAR {
                diagnose(p, n.token, "array operation requires a resizable or limited owner");
            }
            let shrink = builtin == 26 || builtin == 27 || builtin == 28 || builtin == 29 || builtin == 32 || builtin == 34 || builtin == 35;
            check_mutation_views(p, c, check_list_at(c, args, 0), shrink);
            // A verified image may contain links to elements in the removed suffix.
            if array_kind == A_GROWSHRINK && shrink && builtin != 29 && check_type_property(p, element, 6) != 0 {
                diagnose(p, n.token, "cannot partially shrink an array whose elements contain self-relative references");
            }
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
        p.nodes[node].symbol = check_builtin_symbol(p, callee.token, builtin, result) as i32;
        p.nodes[n.left].symbol = p.nodes[node].symbol;
    }
    return result;
}
// range_index, check_length and move_from (upstream §3.3), on arrays and
// slices of fixed-size elements: the checked start of a slice inside the
// receiver, a count validated against a data stack, and an equal-length copy
// that is safe for overlapping slices. A failed check aborts in every build,
// with the runtime's message or the string literal given in its place.
recursive fn check_range_builtin(p: Program&, c: Checker&, node: i64, builtin: i64, args: CheckList&, receiver: i64) -> i64 {
    let n = p.nodes[node]; let element = p.types[receiver].element; let array_kind = p.types[receiver].array_kind;
    let target = check_list_at(c, args, 0); let argument = check_list_at(c, args, 1);
    var name = "range_index"; if builtin == 39 { name = "check_length"; } else if builtin == 40 { name = "move_from"; }
    let fixed = element >= 0 && check_size_class(p, element, 0) == 0;
    if builtin == 40 {
        if p.types[receiver].kind != TY_SLICE { diagnose(p, n.token, ".move_from requires a slice receiver"); }
        else if check_readonly(p, c, target) { diagnose(p, n.token, "cannot .move_from through a non-writable value"); }
        if element >= 0 && !fixed { diagnose(p, n.token, ".move_from requires fixed-size elements"); }
        if element >= 0 { check_value(p, c, argument, check_const_type(p, check_type(p, TY_SLICE, element, -1, -1, 0))); }
        else { check_value(p, c, argument, -1); }
        if element >= 0 && check_type_property(p, element, 6) != 0 { diagnose(p, n.token, ".move_from cannot copy elements containing self-relative references"); }
        if element >= 0 && check_contains_refs(p, element, 0) { check_store_roots(p, c, check_place_root(p, target), argument); }
        return TYPE_VOID;
    }
    if element >= 0 && !fixed {
        var message: u8[>..] = []; message.push('.'); message.append(name); message.append(" needs fixed-size elements: ");
        render_type_name(p, receiver, message); message.append(" is sequential (§3.3)");
        diagnose(p, n.token, message);
    }
    if builtin == 38 {
        if p.types[receiver].kind != TY_ARRAY || array_kind == A_VAR { diagnose(p, n.token, ".range_index requires a fixed-stride array owner"); }
        if element >= 0 { check_value(p, c, argument, check_const_type(p, check_type(p, TY_SLICE, element, -1, -1, 0))); }
        else { check_value(p, c, argument, -1); }
    } else {
        if p.types[receiver].kind != TY_ARRAY || array_kind != A_GROW && array_kind != A_GROWSHRINK { diagnose(p, n.token, ".check_length requires a resizable array owner"); }
        let count = check_numeric_value_type(p, check_value(p, c, argument, -1));
        if c.reachable && !check_integer(count) { diagnose(p, p.nodes[argument].token, ".check_length requires an integer count"); }
    }
    if args.count == 3 {
        let reason = check_list_at(c, args, 2); check_value(p, c, reason, TYPE_STRING);
        if p.nodes[reason].kind != N_STRING {
            var message: u8[>..] = []; message.push('.'); message.append(name); message.append(" takes its abort message as a string literal");
            diagnose(p, p.nodes[reason].token, message);
        }
    }
    return TYPE_I64;
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
    check_enter(c, function_node); p.nodes[function_node].scope = c.scope as i32;
    check_ensure_generics(p, c, function_node);
    let saved_implicit_scope = c.implicit_type_scope;
    if n.kind == N_FUNCTION && n.origin < 0 { c.implicit_type_scope = c.scope; }
    var generic = n.third >= 0; var param = n.first;
    while param >= 0 {
        var ty: i64 = p.nodes[param].type_id;
        if ty < 0 {
            if p.nodes[param].left >= 0 { ty = check_resolve_type(p, c, p.nodes[param].left); }
            else { ty = check_type(p, TY_GENERIC, -1, 0, param, 0); }
        }
        ty = check_value_annotation(p, c, p.nodes[param].left, ty);
        if ty >= 0 && p.types[ty].kind == TY_GENERIC { generic = true; }
        if check_has_generic(p, ty, 0) { generic = true; }
        p.nodes[param].type_id = ty as i32;
        let ps = check_declare(p, c, param, c.scope); p.symbols[ps].type_id = ty;
        let vi = check_variable_index(c, ps); check_set_assigned(c, vi, true, true);
        if ty >= 0 && check_contains_refs(p, ty, 0) {
            var root_kind = 0; if p.types[ty].kind == TY_SLICE { root_kind = 1; }
            check_add_root(c, -ps - 10, ps, root_kind);
        }
        param = p.nodes[param].next;
    }
    c.implicit_type_scope = saved_implicit_scope;
    var ret = n.left; var written = -1;
    if n.origin >= 0 { written = p.nodes[n.origin].left; }
    while ret >= 0 {
        let result_type = check_resolve_type(p, c, ret);
        // A relative result introduced by substitution leaves as a value.
        // A result explicitly written with relative storage is an error.
        if result_type >= 0 && p.types[result_type].kind == TY_REF && p.types[result_type].length_storage >= 0 {
            var value_type = result_type;
            if written >= 0 {
                let written_type = p.nodes[written].type_id;
                if check_has_generic(p, written_type, 0) && (p.types[written_type].kind != TY_REF || p.types[written_type].length_storage < 0) {
                    value_type = check_loaded_type(p, result_type);
                }
            }
            let loaded = check_value_annotation(p, c, ret, value_type);
            p.nodes[ret].type_id = loaded as i32;
        }
        if written >= 0 { written = p.nodes[written].next; }
        ret = p.nodes[ret].next;
    }
    var result = -1; if n.left >= 0 { result = check_tuple(p, n.left); }
    if result < 0 && (n.flags & F_RECURSIVE) != 0 && n.right >= 0 && check_obvious_void_body(p, n.right) { result = TYPE_VOID; }
    if n.kind == N_FUNCTION_VALUE && n.left < 0 && n.aux >= 0 { result = n.aux; }
    if n.right < 0 && result < 0 { result = TYPE_VOID; }
    let type_id = add_type(p, Type { kind: TY_FN, element: result, declaration: function_node, first: n.first, size: p.pointer_bytes, align: p.pointer_bytes });
    p.nodes[function_node].type_id = type_id as i32;
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
    for index in 0..c.checking_count { if c.checking[index].function_node == function_node { active = true; } }
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
    for index in 0..c.checking_count { if c.checking[index].function_node == function_node { return true; } }
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

// The parameters of an instance whose bare type variable literal arguments
// alone bound: each reads as a constant of unknown value that adapts where
// it is used (upstream §7.7).
fn check_mark_literal_parameters(p: Program&, c: Checker&, original: i64, copy: i64, bindings: CheckList&) {
    var formal = p.nodes[original].first; var param = p.nodes[copy].first;
    while formal >= 0 && param >= 0 {
        let ty = p.nodes[formal].type_id; let symbol = p.nodes[param].symbol;
        if ty >= 0 && p.types[ty].kind == TY_GENERIC && symbol >= 0 && (p.nodes[formal].flags & F_VAR) == 0 {
            for index in 0..bindings.count {
                let b = check_binding_at(c, bindings, index);
                if b.parameter == p.types[ty].declaration && b.literal { p.symbols[symbol].flags |= S_LITERAL; }
            }
        }
        formal = p.nodes[formal].next; param = p.nodes[param].next;
    }
}
// A scalar argument that makes a literal parameter: a numeric constant or a
// literal parameter passed on. A construct of constants, a shift of one or
// a float computed from typed integers binds its default type as a typed
// value would (upstream 71e5ade1, §7.7).
fn check_literal_scalar(p: Program&, node: i64) -> bool {
    if check_literal_parameter(p, node) { return true; }
    let ty = check_numeric_value_type(p, p.nodes[node].type_id);
    return check_integer(ty) && check_literal_tree(p, node, 0) || check_float(ty) && check_float_constant_tree(p, node, 0);
}
// Marks the binding of `parameter` as made by literals alone, unless one of
// the first `typed` bindings (explicit and typed arguments) is its.
fn check_mark_literal_binding(c: Checker&, bindings: CheckList&, parameter: i64, typed: i64) {
    var item = bindings.first; var at = 0;
    while item >= 0 {
        if c.binding_work[item].parameter == parameter {
            if at >= typed { c.binding_work[item].literal = true; }
            return;
        }
        item = c.binding_work[item].next; at += 1;
    }
}
recursive fn check_specialize_function(p: Program&, c: Checker&, original: i64, bindings: CheckList&, token: i64) -> i64 {
    parse_deferred_body(p, original);
    if !check_function_reached(p, c, original, token) { return -1; }
    if bindings.count == 0 && check_environment_same(p, c, original, token) {
        if (p.nodes[original].flags & F_CHECKED) == 0 && !check_need_active(c, original) { return p.nodes[original].symbol; }
        if check_reuse_needs(p, c, original, token) { return p.nodes[original].symbol; }
    }
    var spec_id = check_specialization_head(c, original);
    while spec_id >= 0 {
        let spec = c.specializations[spec_id]; spec_id = spec.next_spec;
        if spec.binding_count != bindings.count { continue; }
        var equal = true; var item = bindings.first;
        for i in 0..bindings.count {
            let b = c.binding_work[item]; item = b.next;
            let old = c.bindings[spec.binding_start + i];
            if old.parameter != b.parameter || old.literal != b.literal || !check_binding_same(p, old.value, b.value) { equal = false; }
        }
        if equal && check_environment_same(p, c, p.symbols[spec.symbol].node, token) && check_reuse_needs(p, c, p.symbols[spec.symbol].node, token) { return spec.symbol; }
    }
    var same_declaration = 0;
    for active_index in 0..c.checking_count { let active = c.checking[active_index].function_node; if active == original || p.nodes[active].origin == original { same_declaration += 1; } }
    if same_declaration >= 16 || c.inference_depth >= 64 { diagnose(p, token, "function specialization does not reach a finite set"); return -1; }
    c.inference_depth += 1;
    let saved_syntax = c.clone_syntax; let saved_body = c.syntax_body; let saved_function = c.syntax_function;
    c.clone_syntax = false; c.syntax_function = original; c.syntax_body = p.nodes[original].right;
    if original < c.syntax_lookup.len && c.syntax_lookup[original] >= 0 {
        c.syntax_body = c.syntax_nodes[c.syntax_lookup[original]].right;
    }
    check_body_flush(p, c);
    let copy = check_clone(p, c, original, bindings);
    c.clone_syntax = saved_syntax; c.syntax_body = saved_body; c.syntax_function = saved_function;
    p.nodes[copy].type_id = -1; p.nodes[copy].third = -1; p.nodes[copy].origin = original as i32;
    p.nodes[copy].flags &= ~F_GENERIC;
    if p.nodes[original].kind == N_FUNCTION_VALUE {
        for binding_index in 0..bindings.count { let binding = check_binding_at(c, bindings, binding_index); if binding.parameter == original { p.nodes[copy].aux = binding.value; } }
    }
    let old = p.symbols[p.nodes[original].symbol];
    let symbol = p.symbols.len;
    p.symbols.push(Symbol { name_token: old.name_token, node: copy, scope: -2, flags: old.flags, owner: old.owner });
    p.nodes[copy].symbol = symbol as i32;
    let start = c.bindings.len; var item = bindings.first;
    for index in 0..bindings.count {
        let binding = c.binding_work[item]; item = binding.next;
        c.bindings.push(binding);
    }
    check_add_specialization(c, CheckSpecialization { original: original, symbol: symbol, binding_start: start, binding_count: bindings.count });
    let saved = c.scope; c.scope = c.scopes[p.nodes[original].scope].parent;
    check_enter(c, copy);
    for b_index in 0..bindings.count { let b = check_binding_at(c, bindings, b_index);
        if p.nodes[b.parameter].token < 0 || p.nodes[original].kind == N_FUNCTION_VALUE && b.parameter == original { continue; }
        let binding = new_node(p, N_TYPE_PARAM, p.nodes[b.parameter].token); p.nodes[binding].type_id = b.value as i32;
        check_declare(p, c, binding, c.scope);
    }
    p.nodes[copy].scope = c.scope as i32;
    push_instantiation(p, original, token);
    check_prepare_function(p, c, copy); check_mark_literal_parameters(p, c, original, copy, bindings); check_function(p, c, copy);
    pop_instantiation(p);
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
    p.nodes[node].first = parameter as i32; p.nodes[node].last = parameter as i32; p.nodes[node].type_id = -1;
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
    if s.owner == c.function_node && s.index < 0 { return true; }
    if candidates.count == 1 { return false; }
    var cutoff = token;
    if s.owner != c.function_node { cutoff = check_function_cutoff(p, c, s.owner, token); }
    let position = p.nodes[s.node].token;
    var item = candidates.first;
    for index in 0..candidates.count {
        let other = c.integer_work[item].value; item = c.integer_work[item].next;
        let o = p.symbols[other];
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
    var actual: i64 = p.nodes[node].type_id;
    if actual >= 0 && function_node >= 0 && p.nodes[function_node].kind == N_FUNCTION_VALUE && parameter >= 0 && p.nodes[parameter].left < 0 {
        let n = p.nodes[node];
        if (n.kind == N_IF || n.kind == N_MATCH || n.kind == N_BLOCK || n.kind == N_LOOP) && p.types[actual].kind == TY_REF && (p.types[actual].flags & TF_OPTIONAL) == 0 {
            return p.types[actual].element;
        }
        if p.types[actual].kind == TY_REF && p.types[actual].length_storage >= 0 {
            let loaded = check_loaded_type(p, actual);
            if p.types[actual].pool < 0 && check_readonly(p, c, node) { return check_const_type(p, loaded); }
            return loaded;
        }
        // A non-fixed lvalue binds an untyped block parameter by reference (§4.1).
        if p.types[actual].kind != TY_REF && check_size_class(p, actual, 0) > 0 && check_addressable(p, node) {
            var flags = 0; if check_readonly(p, c, node) { flags |= TF_CONST; }
            return check_type(p, TY_REF, actual, 0, -1, flags);
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
    let n: const Node& = p.nodes[node];
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
    var leaf: i64 = p.nodes[node].type_id;
    while leaf >= 0 && p.types[leaf].kind == TY_ARRAY { leaf = p.types[leaf].element; }
    return check_float(check_numeric_value_type(p, leaf)) && check_literal_argument(p, c, node);
}

recursive fn check_choose_call(p: Program&, c: Checker&, callee_node: i64, args: CheckList&, candidates: CheckList&, no_defaults: bool) -> CheckChoice {
    var best = -1; var best_score = 9223372036854775807; var ambiguous = false; var best_hof = false; var best_converting = true;
    var best_bindings = CheckList {}; var best_written = 0; var typeless_known = false; var typeless = false;
    let callee_tok = p.nodes[callee_node].token; let callee_first = p.nodes[callee_node].first;
    // Keep only node IDs across inference. Nested selections append their own suffix.
    let args_base = c.choice_args.len;
    var arg_item = args.first;
    for index in 0..args.count {
        c.choice_args.push(c.integer_work[arg_item].value);
        arg_item = c.integer_work[arg_item].next;
    }
    var candidate_item = candidates.first;
    for candidate_index in 0..candidates.count {
        let candidate = c.integer_work[candidate_item].value; candidate_item = c.integer_work[candidate_item].next;
        let fnnode = p.symbols[candidate].node;
        if check_function_shadowed(p, c, candidate, candidates, callee_tok) { continue; }
        check_prepare_function(p, c, fnnode);
        var bindings = CheckList {};
        var generic = p.nodes[fnnode].third; var explicit_arg = callee_first; var matches = true;
        var has_generic = generic >= 0;
        if !has_generic {
            var chk = p.nodes[fnnode].first;
            while chk >= 0 {
                if check_has_generic(p, p.nodes[chk].type_id, 0) { has_generic = true; break; }
                chk = p.nodes[chk].next;
            }
        }
        while generic >= 0 && explicit_arg >= 0 {
            let ty = check_resolve_type(p, c, explicit_arg);
            if !check_bind_generic(p, c, generic, ty, bindings) { matches = false; }
            generic = p.nodes[generic].next; explicit_arg = p.nodes[explicit_arg].next;
        }
        if explicit_arg >= 0 { matches = false; }
        // Trailing function values bind leftover generics. They may follow
        // the written prefix even when ordinary parameters take defaults.
        var parameter_count = 0; var required = 0; var parameter = p.nodes[fnnode].first;
        while parameter >= 0 {
            parameter_count += 1;
            if no_defaults || p.nodes[parameter].right < 0 { required = parameter_count; }
            parameter = p.nodes[parameter].next;
        }
        var written = min(args.count, parameter_count);
        while written > 0 && p.nodes[c.choice_args[args_base + written - 1]].kind == N_FUNCTION_VALUE { written -= 1; }
        while written > required {
            let actual = p.nodes[c.choice_args[args_base + written - 1]].type_id;
            if actual < 0 || p.types[actual].kind != TY_FN { break; }
            written -= 1;
        }
        var typed_bindings = 0;
        if has_generic {
            if !typeless_known {
                typeless_known = true;
                for arg_index in 0..args.count {
                    let arg = c.choice_args[args_base + arg_index]; let ty = p.nodes[arg].type_id;
                    if check_empty_tree(p, arg) || ty >= 0 && p.types[ty].kind == TY_REF && p.types[ty].element == TYPE_VOID { typeless = true; break; }
                }
            }
            var infer_formal = p.nodes[fnnode].first; var infer_index = 0;
            while infer_formal >= 0 && infer_index < written {
                let argument = c.choice_args[args_base + infer_index];
                if !check_literal_argument(p, c, argument) && !check_literal_parameter(p, argument) &&
                   !check_unify(p, c, p.nodes[infer_formal].type_id, check_argument_inference(p, c, argument, p.nodes[infer_formal].type_id, fnnode, infer_formal), bindings) { matches = false; }
                infer_formal = p.nodes[infer_formal].next; infer_index += 1;
            }
            typed_bindings = bindings.count;
            // A floating literal-like argument binds before integer literals;
            // typed arguments have already anchored their generic parameters.
            infer_formal = p.nodes[fnnode].first; infer_index = 0;
            while infer_formal >= 0 && infer_index < written {
                let argument = c.choice_args[args_base + infer_index]; let actual = p.nodes[argument].type_id;
                if check_float_argument(p, c, argument) {
                    check_unify(p, c, p.nodes[infer_formal].type_id, actual, bindings);
                }
                infer_formal = p.nodes[infer_formal].next; infer_index += 1;
            }
        }
        var formal = p.nodes[fnnode].first; var index = 0; var score = 0; var converting = false;
        while formal >= 0 && index < written {
            let arg_node = c.choice_args[args_base + index];
            let ft = p.nodes[formal].type_id; let at = p.nodes[arg_node].type_id;
            if (p.nodes[arg_node].flags & F_ARRAY_JOIN) != 0 && (ft < 0 || p.types[ft].kind != TY_SLICE) { matches = false; }
            if ft >= 0 && at >= 0 && p.types[ft].kind == TY_FN && p.types[at].kind == TY_FN {
                if !check_bind_generic(p, c, p.types[ft].declaration, at, bindings) { matches = false; }
            } else if !check_unify(p, c, ft, check_argument_inference(p, c, arg_node, ft, fnnode, formal), bindings) && !check_literal_tree(p, arg_node, 0) && !check_float_literal_tree(p, arg_node, 0) { matches = false; }
            var concrete = check_substitute(p, c, ft, bindings);
            if concrete >= 0 && p.types[concrete].kind == TY_REF && (p.types[concrete].flags & TF_OPTIONAL) == 0 && p.types[concrete].element >= 0 && p.types[p.types[concrete].element].kind == TY_ARRAY {
                let flags = check_pool_flags(p, c, arg_node);
                if flags != 0 && (p.types[concrete].flags & (F_REUSABLE | F_REUSABLE_SLICES)) != flags {
                    var qualified = p.types[concrete]; qualified.flags |= flags; concrete = add_type(p, qualified);
                    if !check_bind_generic(p, c, formal, concrete, bindings) { matches = false; }
                }
            }
            if concrete >= 0 && (p.types[concrete].kind == TY_SLICE || p.types[concrete].kind == TY_REF) &&
               (p.types[concrete].flags & TF_CONST) == 0 && check_argument_readonly(p, c, arg_node, concrete) {
                if (p.nodes[fnnode].flags & F_EXTERN) != 0 { matches = false; }
                concrete = check_const_type(p, concrete);
                if !check_bind_generic(p, c, formal, concrete, bindings) { matches = false; }
            }
            var conversion = check_conversion(p, c, arg_node, at, concrete);
            if conversion > 0 && check_exact_borrow(p, c, arg_node, concrete) { conversion = 0; }
            // An optional reference converts to no value: only a reference
            // parameter takes it (upstream UnifyArg retries only a plain
            // reference as its pointee).
            if at >= 0 && concrete >= 0 && p.types[at].kind == TY_REF && (p.types[at].flags & TF_OPTIONAL) != 0 && p.types[concrete].kind != TY_REF { conversion = -1; matches = false; }
            // A value parameter takes its argument's type exactly but for the
            // constness of the type itself (upstream TopConstEq, tier 0/1).
            if conversion > 0 && at >= 0 && concrete >= 0 && p.types[at].kind != TY_REF && p.types[concrete].kind != TY_REF && check_top_const_same(p, at, concrete) { conversion = 0; }
            // A const slice bound through a reference to a mutable one only by
            // read-only instantiation ranks below a reference to a const slice.
            if conversion == 0 && concrete >= 0 && p.types[concrete].kind == TY_REF {
                let pointee = p.types[concrete].element; let storage = check_storage_type(p, arg_node);
                if pointee >= 0 && storage >= 0 && p.types[pointee].kind == TY_SLICE && p.types[storage].kind == TY_SLICE &&
                   (p.types[pointee].flags & TF_CONST) == 0 && (p.types[storage].flags & TF_CONST) != 0 { conversion = 2; }
            }
            if conversion < 0 { matches = false; } else if conversion > 0 && score < 2 { score = 2; }
            var value_type: i64 = at;
            if value_type >= 0 && p.types[value_type].kind == TY_REF { value_type = p.types[value_type].element; }
            if check_integer(check_numeric_value_type(p, value_type)) && check_float(check_numeric_value_type(p, concrete)) { converting = true; }
            if has_generic && !typeless && check_has_generic(p, ft, 0) && score < 1 { score = 1; }
            formal = p.nodes[formal].next; index += 1;
        }
        // A default string literal is read-only, as an argument would be, so
        // its slice parameter instantiates read-only (upstream read-only
        // instantiation, §9.5).
        var default_formal = formal;
        while default_formal >= 0 && index >= written {
            let value = p.nodes[default_formal].right;
            if value >= 0 && (p.nodes[value].kind == N_STRING || p.nodes[value].kind == N_CALL && p.nodes[value].first < 0 &&
                              p.nodes[p.nodes[value].left].kind == N_NAME && token_is(p, p.nodes[p.nodes[value].left].token, "src_file")) {
                var concrete = check_substitute(p, c, p.nodes[default_formal].type_id, bindings);
                if concrete >= 0 && p.types[concrete].kind == TY_SLICE && (p.types[concrete].flags & TF_CONST) == 0 {
                    if (p.nodes[fnnode].flags & F_EXTERN) != 0 { matches = false; }
                    concrete = check_const_type(p, concrete);
                    if !check_bind_generic(p, c, default_formal, concrete, bindings) { matches = false; }
                }
            }
            default_formal = p.nodes[default_formal].next;
        }
        var hof = false;
        while index < args.count {
            let extra = c.choice_args[args_base + index]; let extra_type = p.nodes[extra].type_id;
            if extra_type < 0 || p.types[extra_type].kind != TY_FN { break; }
            var unbound = -1; var candidate_generic = p.nodes[fnnode].third;
            while candidate_generic >= 0 {
                if check_find_binding(c, bindings, candidate_generic) < 0 { unbound = candidate_generic; break; }
                candidate_generic = p.nodes[candidate_generic].next;
            }
            if unbound < 0 || !check_bind_generic(p, c, unbound, extra_type, bindings) { break; }
            hof = true; index += 1;
        }
        if index != args.count { matches = false; }
        // A literal argument to a bare type variable that no typed argument
        // binds stays a literal inside the instance (upstream §7.7).
        if has_generic && (p.nodes[fnnode].flags & F_EXTERN) == 0 {
            var literal_formal = p.nodes[fnnode].first; var literal_index = 0;
            while literal_formal >= 0 && literal_index < written {
                let ft = p.nodes[literal_formal].type_id;
                if ft >= 0 && p.types[ft].kind == TY_GENERIC && (p.nodes[literal_formal].flags & F_VAR) == 0 && check_literal_scalar(p, c.choice_args[args_base + literal_index]) {
                    let parameter = p.types[ft].declaration;
                    // Names inferred from an annotation have a concrete
                    // argument type. Only declared and untyped parameters
                    // can read as literals (upstream TryMatch).
                    if (p.nodes[parameter].flags & F_SYNTHETIC) == 0 {
                        check_mark_literal_binding(c, bindings, parameter, typed_bindings);
                    }
                }
                literal_formal = p.nodes[literal_formal].next; literal_index += 1;
            }
        }
        while formal >= 0 {
            if no_defaults || p.nodes[formal].right < 0 { matches = false; }
            formal = p.nodes[formal].next;
        }
        generic = p.nodes[fnnode].third;
        while generic >= 0 {
            if check_find_binding(c, bindings, generic) < 0 { matches = false; }
            generic = p.nodes[generic].next;
        }
        if !matches { continue; }
        if best < 0 || !converting && best_converting || converting == best_converting && !converting && score < best_score {
            best = candidate; best_score = score; ambiguous = false; best_hof = hof; best_converting = converting;
            best_bindings = bindings; best_written = written;
        } else if converting == best_converting && (converting || score == best_score) { ambiguous = true; }
    }
    c.choice_args.resize(args_base);
    return CheckChoice { symbol: best, bindings: best_bindings, ambiguous: ambiguous, hof: best_hof, converting: best_converting, written: best_written };
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
recursive fn check_context_float_choice(p: Program&, c: Checker&, node: i64, callee_node: i64, args: CheckList&, candidates: CheckList&, natural: CheckChoice, expected: i64) -> CheckChoice {
    if natural.symbol < 0 || natural.ambiguous { return natural; }
    let original = p.symbols[natural.symbol].node;
    let fn_left = p.nodes[original].left;
    if p.nodes[original].kind != N_FUNCTION || (p.nodes[original].flags & F_EXTERN) != 0 || fn_left < 0 || p.nodes[fn_left].next >= 0 { return natural; }
    let result = p.nodes[fn_left].type_id;
    if result < 0 || p.types[result].kind != TY_GENERIC { return natural; }
    let generic = p.types[result].declaration;
    var own = false; var parameter = p.nodes[original].third; var ordinal = 0;
    while parameter >= 0 {
        if parameter == generic {
            if ordinal < check_list_count(p, p.nodes[callee_node].first) { return natural; }
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
    var trial_args = CheckList {}; var formal = p.nodes[original].first; var index = 0; var changed = false;
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
                p.nodes[trial].type_id = TYPE_F32 as i32; p.nodes[trial].flags = F_CHECKED;
                changed = true;
            }
            check_list_push(c, trial_args, trial);
        }
        index += 1; formal = p.nodes[formal].next;
    }
    while index < args.count { check_list_push(c, trial_args, check_list_at(c, args, index)); index += 1; }
    if !changed { return natural; }
    let trial = check_choose_call(p, c, callee_node, trial_args, candidates, false); var trial_bindings = trial.bindings;
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
    p.nodes[node].symbol = symbol as i32; p.nodes[p.nodes[node].left].symbol = symbol as i32;
    var parameter = p.nodes[function_node].first; var argument = p.nodes[node].first;
    // Only a named function narrows here; its arguments are not returned (§4.1).
    let returning = c.returning;
    while parameter >= 0 && argument >= 0 {
        check_value(p, c, argument, p.nodes[parameter].type_id);
        c.returning = false; check_slot_value(p, c, argument, p.nodes[parameter].type_id); c.returning = returning;
        parameter = p.nodes[parameter].next; argument = p.nodes[argument].next;
    }
    p.nodes[node].type_id = p.types[p.symbols[symbol].type_id].element as i32;
    return p.nodes[node].type_id == TYPE_F32;
}

// A nonlocal exit from function_node to an enclosing active function: the
// variables unassigned when function_node was entered that the exit assigns,
// met over the exits, for replay where function_node is called. entry is the
// delta since function_node's own mark, whose state now is at that mark for
// variables it leaves out.
fn check_flow_base(c: Checker&, tag: i64, vi: i64, assigned: bool&, maybeassigned: bool&) {
    if c.variables[vi].seen == tag {
        let flow = c.flow_work[c.variables[vi].seen_at]; assigned = flow.old_assigned; maybeassigned = flow.old_maybeassigned; return;
    }
    assigned = c.variables[vi].assigned; maybeassigned = c.variables[vi].maybeassigned;
}
fn check_record_outer_exits(p: Program&, c: Checker&, function_node: i64, mark: CheckFlowMark&, entry_tag: i64, exit_start: i64) {
    if (p.nodes[function_node].flags & F_NONLOCAL) == 0 { return; }
    let scope = p.nodes[function_node].scope; let exit_end = c.exit_work.len;
    for exit_index in exit_start..exit_end {
        let exit = c.exit_work[exit_index]; if exit.backedge || exit.target == function_node { continue; }
        var active = false;
        for index in 0..c.checking_count - 1 { if c.checking[index].function_node == exit.target { active = true; break; } }
        if !active { continue; }
        var summary = c.scopes[scope].outer_exits;
        while summary >= 0 && c.outer_exits[summary].target != exit.target { summary = c.outer_exits[summary].next; }
        let first = summary < 0;
        // A new summary span replaces the previous one each time.
        let start = c.outer_flows.len;
        for at in exit.flow.first..exit.flow.first + exit.flow.count {
            let value = c.flow_work[at]; let vi = value.variable;
            if c.variables[vi].born >= mark.stamp { continue; }
            var base_assigned = false; var base_maybeassigned = false; check_flow_base(c, entry_tag, vi, base_assigned, base_maybeassigned);
            if base_assigned { continue; }
            var assigned = value.assigned; var maybeassigned = value.maybeassigned && !base_maybeassigned;
            if !first {
                // A variable the previous summary leaves out was unassigned there.
                assigned = false; var previous = c.outer_exits[summary].flow;
                for old_index in previous.first..previous.first + previous.count {
                    let old = c.outer_flows[old_index]; if old.variable != vi { continue; }
                    assigned = old.assigned && value.assigned; maybeassigned = old.maybeassigned || maybeassigned; break;
                }
            }
            if !assigned && !maybeassigned { continue; }
            c.outer_flows.push(CheckFlow { variable: vi, assigned: assigned, maybeassigned: maybeassigned });
        }
        if !first {
            let added_end = c.outer_flows.len; var previous = c.outer_exits[summary].flow;
            for old_index in previous.first..previous.first + previous.count {
                let old = c.outer_flows[old_index]; if !old.maybeassigned { continue; }
                var present = false;
                for added in start..added_end { if c.outer_flows[added].variable == old.variable { present = true; break; } }
                // Absent from this exit, so unassigned on it.
                if !present { c.outer_flows.push(CheckFlow { variable: old.variable, assigned: false, maybeassigned: true }); }
            }
        }
        if first {
            summary = c.outer_exits.len;
            c.outer_exits.push(CheckOuterExit { target: exit.target, flow: CheckSpan { first: start, count: c.outer_flows.len - start }, next: c.scopes[scope].outer_exits });
            c.scopes[scope].outer_exits = summary;
        } else { c.outer_exits[summary].flow = CheckSpan { first: start, count: c.outer_flows.len - start }; }
    }
}
fn check_replay_outer_exits(p: Program&, c: Checker&, function_node: i64) {
    let scope = p.nodes[function_node].scope; if scope < 0 { return; }
    var at = c.scopes[scope].outer_exits;
    while at >= 0 {
        let summary = c.outer_exits[at]; at = summary.next;
        var found = false; let mark = check_function_mark(c, summary.target, found);
        if !found { continue; }
        var flow = CheckSpan {}; check_flow_delta(c, mark, flow);
        c.flow_clock += 1; let tag = c.flow_clock;
        for index in flow.first..flow.first + flow.count { let vi = c.flow_work[index].variable; c.variables[vi].seen = tag; c.variables[vi].seen_at = index; }
        for added_index in summary.flow.first..summary.flow.first + summary.flow.count {
            let added = c.outer_flows[added_index]; let vi = added.variable;
            if c.variables[vi].born >= mark.stamp { continue; }
            if c.variables[vi].seen == tag {
                let index = c.variables[vi].seen_at;
                c.flow_work[index].assigned = c.flow_work[index].assigned || added.assigned;
                c.flow_work[index].maybeassigned = c.flow_work[index].maybeassigned || added.maybeassigned;
            } else {
                let v: const CheckVariable& = c.variables[vi];
                let value = CheckFlow { variable: vi, assigned: v.assigned || added.assigned, maybeassigned: v.maybeassigned || added.maybeassigned,
                    narrowed: v.narrowed, old_assigned: v.assigned, old_maybeassigned: v.maybeassigned, old_narrowed: v.narrowed };
                c.flow_work.push(value); flow.count += 1;
                c.variables[vi].seen = tag; c.variables[vi].seen_at = c.flow_work.len - 1;
            }
        }
        c.exit_work.push(CheckExit { target: summary.target, flow: flow });
        p.nodes[summary.target].flags |= F_RETURNS; p.nodes[summary.target].flags &= ~F_DIVERGES;
    }
}

fn check_push_return_root(c: Checker&, value: CheckReturnRoot) {
    let id = c.return_roots.len; c.return_roots.push(value);
    if value.function_node < 0 { return; }
    while c.return_root_lists.len <= value.function_node { c.return_root_lists.push(CheckEffectList {}); }
    let last = c.return_root_lists[value.function_node].last;
    if last < 0 { c.return_root_lists[value.function_node].first = id; } else { c.return_roots[last].next = id; }
    c.return_root_lists[value.function_node].last = id;
}
fn check_apply_call_effects(p: Program&, c: Checker&, node: i64, function_node: i64, args: CheckList&) {
    check_environment_callee(p, c, function_node);
    check_replay_outer_exits(p, c, function_node);
    let roots_end = c.return_roots.len; var next_root = -1;
    if function_node < c.return_root_lists.len { next_root = c.return_root_lists[function_node].first; }
    while next_root >= 0 && next_root < roots_end {
        let rr = c.return_roots[next_root]; next_root = rr.next;
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
    // Effects recorded from here on belong to this call's own checking.
    let effects_end = c.effects.len; var next_effect = -1;
    if function_node < c.effect_lists.len { next_effect = c.effect_lists[function_node].first; }
    while next_effect >= 0 && next_effect < effects_end {
        let effect = c.effects[next_effect]; next_effect = effect.next;
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
                check_set_assigned(c, vi, c.variables[vi].assigned, true);
            }
            if vi >= 0 && effect.kind == 4 { check_set_assigned(c, vi, true, true); }
            if vi >= 0 && effect.kind == 5 { check_set_narrowed(c, vi, -1); }
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
    let call_tok = p.nodes[node].token; let callee_node = p.nodes[node].left;
    var position = -1; var selected_arms = -1; var selected_hof = false; var selected_byref = false;
    for index in 0..args.count {
        let argument = check_list_at(c, args, index); var enum_type: i64 = p.nodes[argument].type_id; var through_ref = false;
        if enum_type >= 0 && p.types[enum_type].kind == TY_REF { through_ref = true; enum_type = p.types[enum_type].element; }
        if enum_type < 0 || p.types[enum_type].kind != TY_ENUM { continue; }
        check_layout_nominal(p, c, enum_type);
        let reference = check_type(p, TY_REF, enum_type, 0, -1, 0);
        let byref = (p.types[enum_type].flags & F_VARIABLE_MODE) != 0 &&
            (through_ref || check_size_class(p, enum_type, 0) != 0 && check_exact_borrow(p, c, argument, reference));
        let alternatives = new_node(p, N_EMPTY, call_tok); var variant = p.types[enum_type].first; var complete = true; var all_hof = false;
        while variant >= 0 {
            let payload = p.nodes[variant].type_id; var trial_type: i64 = payload;
            if byref { var flags = 0; if check_dispatch_readonly(p, c, argument) { flags |= TF_CONST; } trial_type = check_type(p, TY_REF, payload, 0, -1, flags); }
            var trial_args = CheckList {};
            for at in 0..args.count {
                let source = check_list_at(c, args, at);
                if at == index {
                    // Rank the payload, not the enum construct's source branches.
                    let trial = new_node(p, N_EMPTY, p.nodes[source].token);
                    p.nodes[trial].type_id = trial_type as i32; p.nodes[trial].flags = F_CHECKED;
                    p.nodes[trial].scope = p.nodes[source].scope; check_copy_roots(c, trial, source);
                    check_list_push(c, trial_args, trial);
                } else { check_list_push(c, trial_args, source); }
            }
            let choice = check_choose_call(p, c, callee_node, trial_args, candidates, true);
            if choice.symbol < 0 || choice.ambiguous { complete = false; break; }
            if variant == p.types[enum_type].first { all_hof = choice.hof; }
            else if all_hof != choice.hof { complete = false; break; }
            let arm = new_node(p, N_BINDING, p.nodes[variant].token);
            p.nodes[arm].type_id = payload; p.nodes[arm].symbol = choice.symbol as i32; p.nodes[arm].integer = p.nodes[variant].integer;
            for b in 0..choice.bindings.count {
                var bindings = choice.bindings; let value = check_binding_at(c, bindings, b);
                let binding = new_node(p, N_TYPE_ARG, p.nodes[value.parameter].token);
                p.nodes[binding].type_id = value.value as i32; p.nodes[binding].symbol = value.parameter as i32; append_child(p, arm, binding);
            }
            append_child(p, alternatives, arm); variant = p.nodes[variant].next;
        }
        if !complete { continue; }
        if position >= 0 { diagnose(p, call_tok, "case dispatch can select only one enum argument"); return -1; }
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
        let symbol = check_specialize_function(p, c, original, bindings, call_tok);
        if symbol < 0 { return -1; }
        let function_node = p.symbols[symbol].node; check_function(p, c, function_node);
        if (p.nodes[function_node].flags & F_DIVERGES) == 0 { may_return = true; }
        let fn_type = p.symbols[symbol].type_id;
        if first_symbol < 0 { first_symbol = symbol; result = p.types[fn_type].element; expected_parameters = p.types[fn_type].first; }
        else if !check_same_type(p, result, p.types[fn_type].element) { diagnose(p, call_tok, "case functions must agree on their result types"); }
        var parameter = p.types[fn_type].first; var first_parameter = expected_parameters; var index = 0;
        while parameter >= 0 && first_parameter >= 0 {
            let ty = p.nodes[parameter].type_id;
            if index == position {
                if p.types[ty].kind == TY_REF { any_reference = true; p.nodes[arm].flags |= F_REFERENCE; }
            } else if !check_same_type(p, ty, p.nodes[first_parameter].type_id) {
                diagnose(p, call_tok, "case functions must agree on non-dispatch parameter types");
            }
            parameter = p.nodes[parameter].next; first_parameter = p.nodes[first_parameter].next; index += 1;
        }
        p.nodes[arm].symbol = symbol as i32; p.nodes[arm].first = -1; p.nodes[arm].last = -1; p.nodes[arm].flags |= F_CHECKED;
        check_apply_call_effects(p, c, node, function_node, args); arm = p.nodes[arm].next;
    }
    let dispatched = check_list_at(c, args, position); var enum_type: i64 = p.nodes[dispatched].type_id;
    if enum_type >= 0 && p.types[enum_type].kind == TY_REF { enum_type = p.types[enum_type].element; }
    if any_reference && (p.types[enum_type].flags & F_VARIABLE_MODE) == 0 { diagnose(p, call_tok, "fixed-mode enum payloads pass to cases by value"); }
    if check_size_class(p, enum_type, 0) == 2 { diagnose(p, call_tok, "case dispatch cannot bind a resizable enum payload"); }
    var parameter = expected_parameters; var index = 0; var last = -1;
    while parameter >= 0 && index < args.count {
        let argument = check_list_at(c, args, index);
        if index != position { check_value(p, c, argument, p.nodes[parameter].type_id); }
        else if selected_byref && p.types[p.nodes[argument].type_id].kind != TY_REF {
            var flags = 0; if check_dispatch_readonly(p, c, argument) { flags |= TF_CONST; }
            let reference = check_type(p, TY_REF, enum_type, 0, -1, flags); check_expect(p, c, argument, p.nodes[argument].type_id, reference);
        }
        if last < 0 { p.nodes[node].first = argument as i32; } else { p.nodes[last].next = argument as i32; }
        last = argument; parameter = p.nodes[parameter].next; index += 1;
    }
    if last >= 0 { p.nodes[last].next = -1; }
    p.nodes[node].last = last as i32; p.nodes[node].third = selected_arms as i32; p.nodes[node].aux = position;
    p.nodes[node].symbol = first_symbol as i32; p.nodes[node].type_id = result as i32; p.nodes[node].flags |= F_DISPATCH;
    if any_reference { p.nodes[node].flags |= F_REFERENCE; }
    if !may_return { p.nodes[node].flags |= F_DIVERGES; c.reachable = false; }
    return result;
}

// A literal argument must fit every type its literal parameter adapts to in
// the callee; a literal parameter passed on takes those types on for its own
// callers to check (upstream VerifyLiterals, §7.7).
fn check_literal_arguments(p: Program&, c: Checker&, function_node: i64, args: CheckList&) {
    var formal = p.nodes[function_node].first; var index = 0;
    while formal >= 0 && index < args.count {
        let symbol = p.nodes[formal].symbol; let value = check_list_at(c, args, index);
        if symbol >= 0 && (p.symbols[symbol].flags & S_LITERAL) != 0 {
            let count = c.literal_uses.len;
            for use_index in 0..count {
                let entry = c.literal_uses[use_index];
                if entry.symbol != symbol { continue; }
                if check_literal_parameter(p, value) { check_note_literal_use(c, p.nodes[value].symbol, entry.type_id); continue; }
                if check_conversion(p, c, value, p.nodes[value].type_id, entry.type_id) >= 0 { continue; }
                let constant = check_constant(p, c, value, 0);
                var message: u8[>..] = []; message.append("argument "); message.format(index + 1); message.append(" of ");
                message.append(token_text(p, p.nodes[function_node].token)); message.append(": constant ");
                if constant.valid { message.format(constant.value); message.append(" "); }
                message.append("does not fit "); render_type_name(p, entry.type_id, message);
                message.append(", which parameter "); message.append(token_text(p, p.nodes[formal].token)); message.append(" takes");
                diagnose(p, p.nodes[value].token, message); break;
            }
        }
        formal = p.nodes[formal].next; index += 1;
    }
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
    let hash = token_hash(p, token); var scope = c.scope; var local = -1;
    while scope > 0 && c.scopes[scope].namespace_node < 0 {
        if c.scopes[scope].decl_count > 0 {
            let parameter = check_lookup_scope_hashed(p, c, token, scope, hash, S_TYPE);
            if parameter >= 0 && p.nodes[p.symbols[parameter].node].kind == N_TYPE_PARAM {
                diagnose(p, token, "a type parameter cannot be called as a member"); return -2;
            }
            if local < 0 { local = check_lookup_scope_hashed(p, c, token, scope, hash, S_FUNCTION | S_BUILTIN); }
        }
        scope = c.scopes[scope].parent;
    }
    if local >= 0 { return local; }
    if ty >= 0 && p.types[ty].kind == TY_STRUCT && p.types[ty].pool >= 0 { ty = p.types[ty].pool; }
    if ty >= 0 && (p.types[ty].kind == TY_STRUCT || p.types[ty].kind == TY_ENUM) {
        var nominal_scope: i64 = p.nodes[p.types[ty].declaration].scope;
        while nominal_scope > 0 && c.scopes[nominal_scope].namespace_node < 0 { nominal_scope = c.scopes[nominal_scope].parent; }
        if nominal_scope > 0 {
            let nominal = check_lookup_scope_hashed(p, c, token, nominal_scope, hash, S_FUNCTION | S_BUILTIN);
            if nominal >= 0 { return nominal; }
        }
    }
    return check_lookup_hashed(p, c, token, scope, hash, S_FUNCTION);
}

// An untyped block parameter receives the construct's copied value. A
// non-fixed lvalue binds it by reference instead (check_argument_inference),
// as reference arguments and explicitly typed reference parameters do.
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
    var source: i64 = n.type_id;
    if source >= 0 && p.types[source].kind == TY_REF && (p.types[source].flags & TF_OPTIONAL) == 0 { source = p.types[source].element; }
    // Within the returned value, a branch may name the function's own local,
    // which the return moves (upstream accepts it there, as for a call's own
    // block argument).
    if source >= 0 && check_size_class(p, source, 0) > 0 && (check_addressable(p, node) || n.type_id >= 0 && p.types[n.type_id].kind == TY_REF) &&
       !(c.returning && check_own_local(p, c, node)) {
        diagnose(p, n.token, "non-fixed storage requires explicit copy when passed or stored by value");
    }
}

recursive fn check_call(p: Program&, c: Checker&, node: i64, expected: i64) -> i64 {
    let n_tok = p.nodes[node].token; let n_flags = p.nodes[node].flags;
    let n_sym = p.nodes[node].symbol; let n_third = p.nodes[node].third;
    var n_first = p.nodes[node].first; var callee_node: i64 = p.nodes[node].left;
    var member = false; var member_symbol = -1;
    if p.nodes[callee_node].kind == N_MEMBER {
        let orig_tok = p.nodes[callee_node].token;
        if p.nodes[callee_node].aux >= 0 { diagnose(p, orig_tok, "const for field accessor is not callable"); return -1; }
        let orig_scope = p.nodes[callee_node].scope; let orig_first = p.nodes[callee_node].first;
        member = true;
        let receiver = p.nodes[callee_node].left;
        var ty = check_single_expression(p, c, receiver);
        while ty >= 0 && p.types[ty].kind == TY_REF { ty = p.types[ty].element; }
        let builtin = check_builtin_kind(p, orig_tok);
        if !(check_array_member_builtin(builtin) && ty >= 0 && (p.types[ty].kind == TY_ARRAY || p.types[ty].kind == TY_SLICE)) {
            member_symbol = check_member_function(p, c, orig_tok, ty);
            if member_symbol == -2 { return -1; }
        }
        let name = new_node(p, N_NAME, orig_tok);
        p.nodes[name].scope = orig_scope; p.nodes[name].aux = 1; p.nodes[name].first = orig_first;
        p.nodes[receiver].next = n_first;
        p.nodes[node].first = receiver; p.nodes[node].left = name as i32;
        n_first = receiver; callee_node = name;
    }
    let callee_kind = p.nodes[callee_node].kind; let callee_tok = p.nodes[callee_node].token;
    if callee_kind == N_NAME { check_parameter_default_name(p, c, callee_node, member); }
    if p.nodes[callee_node].expansion_binding == -2 { diagnose(p, callee_tok, "const for binding is not a callable function"); return -1; }
    if callee_kind == N_FUNCTION_VALUE { check_expression(p, c, callee_node, -1); }
    if callee_kind != N_NAME && callee_kind != N_FUNCTION_VALUE {
        diagnose(p, n_tok, "call target must name a function or function value"); return -1;
    }
    let builtin = check_builtin_kind(p, callee_tok);
    if (n_flags & F_SYNTHETIC) != 0 && n_sym >= 0 && (p.symbols[n_sym].flags & S_BUILTIN) != 0 { return check_builtin(p, c, node, p.symbols[n_sym].index); }
    if (n_flags & F_FORMAT_RAW) != 0 && builtin >= 0 && builtin <= 2 { return check_builtin(p, c, node, builtin); }
    if member && check_array_member_builtin(builtin) && n_first >= 0 {
        var receiver = check_single_expression(p, c, n_first);
        let optional = receiver >= 0 && p.types[receiver].kind == TY_REF && (p.types[receiver].flags & TF_OPTIONAL) != 0;
        while receiver >= 0 && p.types[receiver].kind == TY_REF { receiver = p.types[receiver].element; }
        if receiver >= 0 && (p.types[receiver].kind == TY_ARRAY || p.types[receiver].kind == TY_SLICE) {
            if optional { diagnose(p, callee_tok, "optional receiver must be narrowed before a builtin member call"); return -1; }
            return check_builtin(p, c, node, builtin);
        }
    }
    var args = CheckList {}; var argument = n_first;
    while argument >= 0 {
        check_single_expression(p, c, argument); check_list_push(c, args, argument); argument = p.nodes[argument].next;
    }
    if n_third >= 0 {
        check_expression(p, c, n_third, -1); check_list_push(c, args, n_third);
    }
    var first = -1; var bound_function = false;
    if (n_flags & F_SYNTHETIC) != 0 && n_sym >= 0 { first = n_sym; bound_function = true; }
    else if member { first = member_symbol; }
    else if callee_kind == N_NAME { first = check_lookup_name(p, c, callee_node, S_FUNCTION); }
    else { first = p.nodes[callee_node].symbol; }
    if first >= 0 && (p.symbols[first].flags & S_FUNCTION) == 0 {
        let ty = p.symbols[first].type_id;
        if ty >= 0 && p.types[ty].kind == TY_FN && p.types[ty].declaration >= 0 {
            let target = p.types[ty].declaration;
            if p.nodes[target].kind == N_FUNCTION || p.nodes[target].kind == N_FUNCTION_VALUE {
                check_implicit_function_parameter(p, c, target, args.count);
                first = p.nodes[target].symbol; bound_function = p.nodes[target].kind == N_FUNCTION_VALUE || p.nodes[target].origin >= 0;
            }
            else { diagnose(p, n_tok, "function parameter has no bound function value"); return -1; }
        } else if (p.symbols[first].flags & S_GLOBAL) == 0 {
            diagnose(p, n_tok, "local value hides this function name and cannot be called"); return -1;
        } else { first = -1; }
    }
    var candidates = CheckList {};
    var current = first;
    while current >= 0 {
        let s: const Symbol& = p.symbols[current];
        if (s.flags & S_FUNCTION) != 0 && (s.flags & S_BUILTIN) == 0 && s.node >= 0 &&
           (bound_function || p.nodes[s.node].origin < 0) { check_list_push(c, candidates, current); }
        if bound_function { break; }
        current = s.next;
    }
    let choice = check_choose_call(p, c, callee_node, args, candidates, false);
    var best = choice.symbol; var best_bindings = choice.bindings; let ambiguous = choice.ambiguous;
    if best < 0 || choice.converting {
        let dispatched = check_try_dispatch(p, c, node, expected, args, candidates);
        if dispatched >= 0 || (p.nodes[node].flags & F_DISPATCH) != 0 { return dispatched; }
        let callee_aux = p.nodes[callee_node].aux; let callee_int = p.nodes[callee_node].integer;
        if builtin >= 0 && (!member || first < 0) && (callee_aux <= 1 || callee_int >= 0 && p.tokens[callee_int].kind == T_COLONCOLON) {
            if member && (builtin == 21 || builtin == 22) { diagnose(p, callee_tok, "a property is not callable"); return -1; }
            return check_builtin(p, c, node, builtin);
        }
        if best < 0 { diag_call_mismatch(p, c, n_tok, callee_node, args, candidates, false); return -1; }
    }
    if ambiguous { diag_call_mismatch(p, c, n_tok, callee_node, args, candidates, true); return -1; }
    let contextual = check_context_float_choice(p, c, node, callee_node, args, candidates, choice, expected);
    best = contextual.symbol; best_bindings = contextual.bindings;
    let original = p.symbols[best].node;
    // A block call produces its own temporary value. Only numeric literal
    // widths adapt here; a destination never turns its slice or owner tail
    // into a reference, nor supplies an empty array's element type.
    if p.nodes[original].kind == N_FUNCTION_VALUE && p.nodes[original].left < 0 && check_numeric(expected) {
        check_bind_generic(p, c, original, expected, best_bindings);
    }
    best = check_specialize_function(p, c, original, best_bindings, n_tok);
    if best < 0 { return -1; }
    let function_node = p.symbols[best].node;
    p.nodes[node].symbol = best as i32; p.nodes[callee_node].symbol = best as i32;
    let lib_inst = (p.nodes[function_node].flags & (F_CHECKED | F_GENERIC)) == 0 && library_node(p, function_node);
    if lib_inst { push_instantiation(p, function_node, n_tok); }
    check_function(p, c, function_node);
    if lib_inst { pop_instantiation(p); }
    // Keep the linked argument list appendable when inserting defaults.
    if contextual.written < args.count {
        var written = CheckList {};
        for ordinal in 0..contextual.written { check_list_push(c, written, check_list_at(c, args, ordinal)); }
        args = written;
    }
    var formal = p.nodes[function_node].first; var index = 0; var last = -1;
    while formal >= 0 {
        var value = -1;
        if index < args.count { value = check_list_at(c, args, index); }
        else if p.nodes[formal].right >= 0 {
            value = check_parameter_default(p, c, function_node, formal, n_tok);
            if value >= 0 {
                if last < 0 { p.nodes[node].first = value as i32; } else { p.nodes[last].next = value as i32; }
                check_list_push(c, args, value);
            }
        }
        if value >= 0 {
            let saved_render_reference = c.render_reference;
            c.render_reference = (p.nodes[function_node].flags & F_FORMAT_RAW) != 0;
            if p.nodes[original].kind == N_FUNCTION_VALUE && p.nodes[formal].left < 0 { check_funval_copy(p, c, value, p.nodes[formal].type_id); }
            check_value(p, c, value, p.nodes[formal].type_id);
            // A named function's argument is never the returned value, so a
            // return does not move a local into it (§4.1); upstream keeps that
            // move for a block's argument within the returned expression, and
            // for what the argument itself constructs.
            let returning = c.returning;
            if p.nodes[original].kind != N_FUNCTION_VALUE { c.returning = false; }
            check_slot_value(p, c, value, p.nodes[formal].type_id);
            c.returning = returning; c.render_reference = saved_render_reference;
            if value == n_third {
                if last < 0 { p.nodes[node].first = value as i32; } else { p.nodes[last].next = value as i32; }
                p.nodes[node].third = -1;
            }
            last = value;
        }
        formal = p.nodes[formal].next; index += 1;
    }
    if contextual.hof {
        if last >= 0 { p.nodes[last].next = -1; } else { p.nodes[node].first = -1; }
        p.nodes[node].third = -1;
    }
    p.nodes[node].last = last as i32;
    check_literal_arguments(p, c, function_node, args);
    let type_id = p.symbols[best].type_id;
    let result = p.types[type_id].element;
    check_apply_call_effects(p, c, node, function_node, args);
    if (p.nodes[function_node].flags & F_DIVERGES) != 0 { p.nodes[node].flags |= F_DIVERGES; c.reachable = false; }
    return result;
}

// Flow facts (definite assignment and optional narrowing) change through
// check_flow_set, which logs a variable's previous state when it was declared
// before the innermost open mark. A construct opens a mark where its branches
// start. Undoing to the mark pops the log; a delta lists each variable
// changed since the mark with its state then and now. Variables declared
// after a mark are local to its construct, which neither undoes nor reports
// them, so the log and the deltas follow live nesting, not program size.
fn check_flow_set(c: Checker&, vi: i64, assigned: bool, maybeassigned: bool, narrowed: i64) {
    let v: const CheckVariable& = c.variables[vi];
    if v.assigned == assigned && v.maybeassigned == maybeassigned && v.narrowed == narrowed { return; }
    if v.born < c.flow_stamp {
        c.flow_trail.push(CheckFlowUndo { variable: vi, assigned: v.assigned, maybeassigned: v.maybeassigned, narrowed: v.narrowed });
    }
    if narrowed >= 0 && v.narrowed < 0 { check_narrowed_add(c, vi); }
    c.variables[vi].assigned = assigned; c.variables[vi].maybeassigned = maybeassigned; c.variables[vi].narrowed = narrowed;
}
fn check_set_assigned(c: Checker&, vi: i64, assigned: bool, maybeassigned: bool) {
    check_flow_set(c, vi, assigned, maybeassigned, c.variables[vi].narrowed);
}
fn check_set_narrowed(c: Checker&, vi: i64, narrowed: i64) {
    check_flow_set(c, vi, c.variables[vi].assigned, c.variables[vi].maybeassigned, narrowed);
}
fn check_flow_mark(c: Checker&) -> CheckFlowMark {
    c.flow_clock += 1;
    let mark = CheckFlowMark { trail: c.flow_trail.len, stamp: c.flow_clock, outer: c.flow_stamp,
                               work: c.flow_work.len, exits: c.exit_work.len, narrowed: c.narrowed_count };
    c.flow_stamp = mark.stamp; return mark;
}
fn check_flow_undo(c: Checker&, mark: CheckFlowMark&) {
    while c.flow_trail.len > mark.trail {
        let entry = c.flow_trail.pop(); let vi = entry.variable;
        c.variables[vi].assigned = entry.assigned; c.variables[vi].maybeassigned = entry.maybeassigned;
        c.variables[vi].narrowed = entry.narrowed;
        if entry.narrowed >= 0 { check_narrowed_add(c, vi); }
    }
}
// Appends each variable declared before the mark and changed since, with its
// state at the mark (its first log entry since) and now.
fn check_flow_delta(c: Checker&, mark: CheckFlowMark&, out: CheckSpan&) {
    c.flow_clock += 1; let tag = c.flow_clock;
    out.first = c.flow_work.len; out.count = 0;
    for index in mark.trail..c.flow_trail.len {
        let entry = c.flow_trail[index]; let vi = entry.variable;
        if c.variables[vi].born >= mark.stamp || c.variables[vi].seen == tag { continue; }
        c.variables[vi].seen = tag;
        let v: const CheckVariable& = c.variables[vi];
        let flow = CheckFlow { variable: vi, assigned: v.assigned, maybeassigned: v.maybeassigned, narrowed: v.narrowed,
                               old_assigned: entry.assigned, old_maybeassigned: entry.maybeassigned, old_narrowed: entry.narrowed };
        c.flow_work.push(flow); out.count += 1;
    }
}
// Closes the innermost mark: drops deltas no pending exit holds, then keeps
// only the first log entry of each variable the enclosing mark still needs.
fn check_flow_close(c: Checker&, mark: CheckFlowMark&) {
    var write = mark.work;
    for index in mark.exits..c.exit_work.len {
        let flow = c.exit_work[index].flow;
        if flow.first < mark.work { continue; }
        for at in 0..flow.count { c.flow_work[write + at] = c.flow_work[flow.first + at]; }
        c.exit_work[index].flow.first = write; write += flow.count;
    }
    if c.flow_work.len > write { let extra = c.flow_work.len - write; c.flow_work.pop_n(extra); }
    c.flow_stamp = mark.outer;
    c.flow_clock += 1; let tag = c.flow_clock; var kept = mark.trail;
    for index in mark.trail..c.flow_trail.len {
        let entry = c.flow_trail[index]; let vi = entry.variable;
        if c.variables[vi].born >= c.flow_stamp || c.variables[vi].seen == tag { continue; }
        c.variables[vi].seen = tag; c.flow_trail[kept] = entry; kept += 1;
    }
    if c.flow_trail.len > kept { let extra = c.flow_trail.len - kept; c.flow_trail.pop_n(extra); }
    // Narrowed variables declared inside the construct are out of scope.
    var narrowed = mark.narrowed;
    for index in mark.narrowed..c.narrowed_count {
        let vi = c.narrowed_variables[index];
        if c.variables[vi].narrowed < 0 || c.variables[vi].born >= mark.stamp { continue; }
        c.narrowed_variables[narrowed] = vi; narrowed += 1;
    }
    c.narrowed_count = narrowed;
}
// Removes the exits a finished construct consumed.
fn check_exits_consume(c: Checker&, start: i64, target: i64) {
    var write = start;
    for index in start..c.exit_work.len {
        let exit = c.exit_work[index];
        if exit.target == target { continue; }
        c.exit_work[write] = exit; write += 1;
    }
    if c.exit_work.len > write { let extra = c.exit_work.len - write; c.exit_work.pop_n(extra); }
}
fn check_flow_merge(p: Program&, c: Checker&, vi: i64, left: CheckFlowUndo, right: CheckFlowUndo, left_reachable: bool, right_reachable: bool) {
    if !left_reachable { check_flow_set(c, vi, right.assigned, right.maybeassigned, right.narrowed); return; }
    if !right_reachable { check_flow_set(c, vi, left.assigned, left.maybeassigned, left.narrowed); return; }
    var narrowed = -1; if check_same_type(p, left.narrowed, right.narrowed) { narrowed = left.narrowed; }
    check_flow_set(c, vi, left.assigned && right.assigned, left.maybeassigned || right.maybeassigned, narrowed);
}
// Joins two deltas since one mark; the current state is the right one.
fn check_flow_join(p: Program&, c: Checker&, left: CheckSpan&, right: CheckSpan&, left_reachable: bool, right_reachable: bool) {
    c.flow_clock += 1; let in_left = c.flow_clock; c.flow_clock += 1; let paired = c.flow_clock;
    for index in left.first..left.first + left.count {
        let vi = c.flow_work[index].variable; c.variables[vi].seen = in_left; c.variables[vi].seen_at = index;
    }
    for index in right.first..right.first + right.count {
        let r = c.flow_work[index]; let vi = r.variable;
        var l = CheckFlowUndo { variable: vi, assigned: r.old_assigned, maybeassigned: r.old_maybeassigned, narrowed: r.old_narrowed };
        if c.variables[vi].seen == in_left {
            let f = c.flow_work[c.variables[vi].seen_at];
            l = CheckFlowUndo { variable: vi, assigned: f.assigned, maybeassigned: f.maybeassigned, narrowed: f.narrowed };
            c.variables[vi].seen = paired;
        }
        let now = CheckFlowUndo { variable: vi, assigned: r.assigned, maybeassigned: r.maybeassigned, narrowed: r.narrowed };
        check_flow_merge(p, c, vi, l, now, left_reachable, right_reachable);
    }
    for index in left.first..left.first + left.count {
        let f = c.flow_work[index]; let vi = f.variable;
        if c.variables[vi].seen != in_left { continue; }
        let l = CheckFlowUndo { variable: vi, assigned: f.assigned, maybeassigned: f.maybeassigned, narrowed: f.narrowed };
        let base = CheckFlowUndo { variable: vi, assigned: f.old_assigned, maybeassigned: f.old_maybeassigned, narrowed: f.old_narrowed };
        check_flow_merge(p, c, vi, l, base, left_reachable, right_reachable);
    }
}
fn check_join_value(p: Program&, c: Checker&, index: i64, assigned: bool, maybeassigned: bool, narrowed: i64) {
    if c.flow_join[index].empty {
        c.flow_join[index].assigned = assigned; c.flow_join[index].maybeassigned = maybeassigned;
        c.flow_join[index].narrowed = narrowed; c.flow_join[index].empty = false; return;
    }
    c.flow_join[index].assigned = c.flow_join[index].assigned && assigned;
    c.flow_join[index].maybeassigned = c.flow_join[index].maybeassigned || maybeassigned;
    if !check_same_type(p, c.flow_join[index].narrowed, narrowed) { c.flow_join[index].narrowed = -1; }
}
// Adds one state, a delta since the join's mark, to the meet started at
// tag; contribute false only registers its variables.
fn check_join_delta(p: Program&, c: Checker&, tag: i64, span: CheckSpan, contribute: bool) {
    for index in span.first..span.first + span.count {
        let d = c.flow_work[index]; let vi = d.variable; var at = c.variables[vi].seen_at;
        if c.variables[vi].seen != tag {
            c.variables[vi].seen = tag; at = c.flow_join.len; c.variables[vi].seen_at = at;
            c.flow_join.push(CheckFlowJoin { variable: vi, base_assigned: d.old_assigned, base_maybeassigned: d.old_maybeassigned, base_narrowed: d.old_narrowed });
        }
        if contribute { c.flow_join[at].count += 1; check_join_value(p, c, at, d.assigned, d.maybeassigned, d.narrowed); }
    }
}
// Sets each joined variable to its meet; a state that left a variable out
// contributes the variable's state at the mark.
fn check_join_finish(p: Program&, c: Checker&, start: i64, contributors: i64) {
    for index in start..c.flow_join.len {
        if c.flow_join[index].count < contributors {
            let join = c.flow_join[index];
            check_join_value(p, c, index, join.base_assigned, join.base_maybeassigned, join.base_narrowed);
        }
        let value = c.flow_join[index];
        check_flow_set(c, value.variable, value.assigned, value.maybeassigned, value.narrowed);
    }
    if c.flow_join.len > start { let extra = c.flow_join.len - start; c.flow_join.pop_n(extra); }
}
// Meets the fallthrough's current state with the exits to target recorded
// since start, all deltas since mark.
fn check_join_control_exits(p: Program&, c: Checker&, target: i64, start: i64, fallthrough: bool, mark: CheckFlowMark&) -> bool {
    var exits = 0;
    for index in start..c.exit_work.len { let exit = c.exit_work[index]; if exit.target == target && !exit.backedge { exits += 1; } }
    if exits == 0 { return fallthrough; }
    c.flow_clock += 1; let tag = c.flow_clock; let join_start = c.flow_join.len;
    var current = CheckSpan {}; check_flow_delta(c, mark, current);
    check_join_delta(p, c, tag, current, fallthrough);
    for index in start..c.exit_work.len {
        let exit = c.exit_work[index]; if exit.target != target || exit.backedge { continue; }
        check_join_delta(p, c, tag, exit.flow, true);
    }
    var contributors = exits; if fallthrough { contributors += 1; }
    check_join_finish(p, c, join_start, contributors);
    if current.count > 0 { let extra = current.count; c.flow_work.pop_n(extra); }
    return true;
}
// The mark of an active function, the target of an exit from inside it.
fn check_function_mark(c: Checker&, function_node: i64, found: bool&) -> CheckFlowMark {
    var index = c.checking_count;
    while index > 0 { index -= 1; if c.checking[index].function_node == function_node { found = true; return c.checking[index].mark; } }
    found = false; return CheckFlowMark {};
}
// Records an exit to target, an active function or loop whose mark is given.
fn check_flow_exit(c: Checker&, target: i64, mark: CheckFlowMark&, backedge: bool = false) {
    var flow = CheckSpan {}; check_flow_delta(c, mark, flow);
    c.exit_work.push(CheckExit { target: target, flow: flow, backedge: backedge });
}
recursive fn check_branch_readonly(p: Program&, c: Checker&, node: i64) -> bool {
    if node < 0 { return false; }
    let n_kind = p.nodes[node].kind; let n_flags = p.nodes[node].flags;
    let n_last = p.nodes[node].last; let n_right = p.nodes[node].right;
    let n_third = p.nodes[node].third; let n_first = p.nodes[node].first;
    if n_kind == N_LOOP || n_kind == N_BLOCK && (n_flags & F_EARLY) != 0 {
        var values = CheckList {}; check_collect_break_values(p, c, node, node, values, true);
        if n_kind == N_BLOCK && (n_flags & F_TAIL) != 0 && (p.nodes[n_last].flags & F_DIVERGES) == 0 { check_list_push(c, values, n_last); }
        for index in 0..values.count { if check_branch_readonly(p, c, check_list_at(c, values, index)) { return true; } }
        return false;
    }
    if (n_flags & F_DIVERGES) != 0 { return false; }
    if n_kind == N_BLOCK && (n_flags & F_TAIL) != 0 { return check_branch_readonly(p, c, n_last); }
    if n_kind == N_IF { return check_branch_readonly(p, c, n_right) || check_branch_readonly(p, c, n_third); }
    if n_kind == N_MATCH {
        var arm = n_first;
        while arm >= 0 { if check_branch_readonly(p, c, p.nodes[arm].right) { return true; } arm = p.nodes[arm].next; }
        return false;
    }
    return check_readonly(p, c, node);
}
fn check_join_type(p: Program&, c: Checker&, left_node: i64, left: i64, right_node: i64, right: i64, token: i64, adapt: bool = true, owner: i64 = -1) -> i64 {
    if left < 0 { return right; }
    if right < 0 { return left; }
    if left == right && left <= TYPE_F64 { return left; }
    var left_value = left; var right_value = right;
    if p.types[left_value].kind == TY_REF && (p.types[left_value].flags & TF_OPTIONAL) == 0 { left_value = p.types[left_value].element; }
    if p.types[right_value].kind == TY_REF && (p.types[right_value].flags & TF_OPTIONAL) == 0 { right_value = p.types[right_value].element; }
    let a_kind = p.types[left_value].kind; let b_kind = p.types[right_value].kind;
    let a_idx = p.types[left_value].index_type; let b_idx = p.types[right_value].index_type;
    if a_kind == TY_INT && b_kind == TY_INT && (a_idx >= 0 || b_idx >= 0) {
        var common = -1;
        if a_idx >= 0 && b_idx >= 0 && p.types[left_value].pool == p.types[right_value].pool {
            var widest = left_value; if p.types[right_value].count > p.types[left_value].count { widest = right_value; }
            var joined = p.types[widest]; joined.flags |= (p.types[left_value].flags | p.types[right_value].flags) & F_BOUND_TYPE;
            common = add_type(p, joined);
        } else {
            let l = check_numeric_value_type(p, left_value); let r = check_numeric_value_type(p, right_value);
            if left_node >= 0 && check_conversion(p, c, left_node, left, r) >= 0 { common = r; }
            else if right_node >= 0 && check_conversion(p, c, right_node, right, l) >= 0 { common = l; }
            else {
                var msg: u8[>..] = []; msg.append("control-flow branches produce incompatible integer types: `");
                diag_append_type(p, left, msg); msg.append("` vs `"); diag_append_type(p, right, msg); msg.push('`');
                diagnose(p, token, msg); return -1;
            }
        }
        if adapt && left_node >= 0 { check_expect(p, c, left_node, left, common); }
        if adapt && right_node >= 0 { check_expect(p, c, right_node, right, common); }
        return common;
    }
    // A join of two distinct array types is provisional until a branch
    // contributes a slice or the destination is explicitly a slice.
    let left_pending = left_node >= 0 && (p.nodes[left_node].flags & F_ARRAY_JOIN) != 0 ||
        owner >= 0 && a_kind == TY_SLICE && (p.nodes[owner].flags & F_ARRAY_JOIN) != 0;
    let right_pending = right_node >= 0 && (p.nodes[right_node].flags & F_ARRAY_JOIN) != 0;
    if (a_kind == TY_SLICE || b_kind == TY_SLICE || owner >= 0 && !check_same_type(p, left_value, right_value)) &&
       (a_kind == TY_ARRAY || a_kind == TY_SLICE) && (b_kind == TY_ARRAY || b_kind == TY_SLICE) &&
       check_same_type(p, p.types[left_value].element, p.types[right_value].element) {
        var flags = (p.types[left_value].flags | p.types[right_value].flags) & TF_CONST;
        if check_branch_readonly(p, c, left_node) || check_branch_readonly(p, c, right_node) { flags |= TF_CONST; }
        let view = check_type(p, TY_SLICE, p.types[left_value].element, -1, -1, flags);
        if (left_node < 0 || check_conversion(p, c, left_node, left, view) >= 0) && (right_node < 0 || check_conversion(p, c, right_node, right, view) >= 0) {
            let pending = (a_kind == TY_ARRAY || left_pending) && (b_kind == TY_ARRAY || right_pending);
            if owner >= 0 {
                if pending { p.nodes[owner].flags |= F_ARRAY_JOIN; }
                else { p.nodes[owner].flags &= ~F_ARRAY_JOIN; }
            }
            if adapt && !pending && left_node >= 0 { check_expect(p, c, left_node, left, view); }
            if adapt && !pending && right_node >= 0 { check_expect(p, c, right_node, right, view); }
            return view;
        }
    }
    if check_same_type(p, left, right) { return left; }
    if p.types[left].kind == TY_ARRAY && p.types[right].kind == TY_ARRAY && (p.types[left].element < 0) != (p.types[right].element < 0) {
        diagnose(p, token, "an empty array branch cannot infer its element type from another branch"); return -1;
    }
    if right_node >= 0 && (check_join_literal(p, c, right_node) || check_literal_parameter(p, right_node)) && !check_join_literal(p, c, left_node) && !check_literal_parameter(p, left_node) && check_conversion(p, c, right_node, right, left) >= 0 {
        if adapt { check_expect(p, c, right_node, right, left); } return left;
    }
    if left_node >= 0 && check_conversion(p, c, left_node, left, right) >= 0 {
        if adapt { check_expect(p, c, left_node, left, right); } return right;
    }
    if right_node >= 0 && check_conversion(p, c, right_node, right, left) >= 0 {
        if adapt { check_expect(p, c, right_node, right, left); } return left;
    }
    var msg: u8[>..] = []; msg.append("control-flow branches produce incompatible types: `");
    diag_append_type(p, left, msg); msg.append("` vs `"); diag_append_type(p, right, msg); msg.push('`');
    diagnose(p, token, msg); return -1;
}
recursive fn check_predeclare(p: Program&, c: Checker&, first: i64) {
    var node = first;
    while node >= 0 {
        let n = p.nodes[node];
        if n.kind == N_NAMESPACE {
            let previous = check_namespace_in(p, check_lookup_scope(p, c, n.token, c.scope));
            var namespace_scope = -1;
            if previous >= 0 {
                namespace_scope = p.nodes[p.symbols[previous].node].scope; p.nodes[node].symbol = previous as i32;
            } else {
                check_declare(p, c, node, c.scope);
                let saved = check_enter(c, c.function_node); namespace_scope = c.scope;
                c.scopes[namespace_scope].namespace_node = node; c.scope = saved;
            }
            p.nodes[node].scope = namespace_scope as i32;
            let saved = c.scope; c.scope = namespace_scope;
            check_predeclare(p, c, n.first); c.scope = saved;
        } else if n.kind == N_EXTERN { check_predeclare(p, c, n.first); }
        else if n.kind == N_FUNCTION || n.kind == N_STRUCT || n.kind == N_ENUM || n.kind == N_ALIAS {
            if n.kind == N_STRUCT || n.kind == N_ENUM {
                var kind = TY_STRUCT; if n.kind == N_ENUM { kind = TY_ENUM; }
                let ty = add_type(p, Type { kind: kind, declaration: node, first: n.first, name_token: n.token });
                p.nodes[node].type_id = ty as i32;
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
        ty = check_inferred_result(p, c, n.last, target); p.nodes[node].type_id = ty as i32; check_copy_roots(c, node, n.last); return ty;
    }
    if n.kind == N_IF && n.third >= 0 {
        let left = check_inferred_result(p, c, n.right, target); let right = check_inferred_result(p, c, n.third, target);
        ty = check_join_type(p, c, n.right, left, n.third, right, n.token); p.nodes[node].type_id = ty as i32;
        check_copy_roots(c, node, n.right); check_copy_roots(c, node, n.third); return ty;
    }
    if n.kind == N_MATCH {
        var arm = n.first; var result = -1; var previous = -1;
        while arm >= 0 {
            let body = p.nodes[arm].right; let branch = check_inferred_result(p, c, body, target);
            result = check_join_type(p, c, previous, result, body, branch, n.token); previous = body;
            check_copy_roots(c, node, body); arm = p.nodes[arm].next;
        }
        p.nodes[node].type_id = result as i32; return result;
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
    let n_flags = p.nodes[node].flags; let n_first = p.nodes[node].first; let n_tok = p.nodes[node].token;
    let saved = check_enter(c, c.function_node); let exit_start = c.exit_work.len;
    p.nodes[node].scope = c.scope as i32;
    if expected >= 0 && (p.types[expected].kind == TY_REF || p.types[expected].kind == TY_SLICE) { p.nodes[node].flags |= F_REFERENCE_CONTEXT; }
    var early = false; var mark = CheckFlowMark {};
    if (n_flags & (F_EARLY | F_NONLOCAL)) != 0 {
        mark = check_flow_mark(c);
        check_push_loop(c, CheckLoop { node: node, scope: c.scope, function_node: c.function_node, expected: expected, returning: c.returning, mark: mark }); early = true;
    }
    check_predeclare(p, c, n_first);
    var child = n_first; var result = TYPE_VOID; var previous_child = -1;
    while child >= 0 {
        if !c.reachable {
            if previous_child < 0 { p.nodes[node].first = -1; } else { p.nodes[previous_child].next = -1; }
            p.nodes[node].last = previous_child as i32; p.nodes[node].flags &= ~F_TAIL; break;
        }
        let item_kind = p.nodes[child].kind; let item_flags = p.nodes[child].flags; let item_next = p.nodes[child].next;
        if item_kind == N_VARIABLE {
            let previous = c.scope; check_enter(c, c.function_node);
            c.scopes[c.scope].depth = c.scopes[previous].depth;
        }
        // F_TAIL on a block also means it has a tail value; only the last
        // child is this block's tail.
        if (item_flags & F_TAIL) != 0 && item_next < 0 {
            let returning = c.returning;
            if c.function_node >= 0 && p.nodes[c.function_node].right == node { c.returning = true; }
            var tail_expected = expected;
            if c.function_node >= 0 && p.nodes[c.function_node].right == node && expected >= 0 &&
               (p.types[expected].kind == TY_REF || p.types[expected].kind == TY_SLICE) &&
               (item_kind == N_NAME || item_kind == N_CALL || item_kind == N_SLICE || item_kind == N_MEMBER || item_kind == N_INDEX) {
                check_expression(p, c, child, -1);
                if check_readonly(p, c, child) {
                    tail_expected = check_const_type(p, expected); c.result_type = tail_expected;
                    p.types[p.nodes[c.function_node].type_id].element = tail_expected; type_reindex(p, p.nodes[c.function_node].type_id);
                }
            }
            let keep_tuple = c.tuple_context || tail_expected < 0 && c.function_node >= 0 && check_tail_contains(p, p.nodes[c.function_node].right, node);
            result = check_value(p, c, child, tail_expected, keep_tuple);
            p.nodes[node].flags |= p.nodes[child].flags & F_ARRAY_JOIN;
            if tail_expected < 0 { result = check_index_value(p, child, result); }
            if tail_expected < 0 && c.function_node >= 0 && p.nodes[c.function_node].right == node { result = check_inferred_result(p, c, child, c.function_node); }
            check_copy_roots(c, node, child); c.returning = returning;
        } else { check_statement(p, c, child); }
        previous_child = child; child = item_next;
    }
    if (p.nodes[node].flags & F_TAIL) == 0 && expected >= 0 && expected != TYPE_VOID && c.reachable {
        diagnose(p, n_tok, "value-producing block must end with an expression");
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
        let reach = check_join_control_exits(p, c, node, exit_start, body_reachable, mark); c.reachable = reach;
        check_exits_consume(c, exit_start, node); check_flow_close(c, mark);
    }
    c.scope = saved;
    if !c.reachable { return -1; }
    if expected == TYPE_VOID { return TYPE_VOID; }
    return result;
}
recursive fn check_if(p: Program&, c: Checker&, node: i64, expected: i64) -> i64 {
    let n_left = p.nodes[node].left; let n_right = p.nodes[node].right; let n_third = p.nodes[node].third; let n_tok = p.nodes[node].token;
    check_condition(p, c, n_left);
    var mark = check_flow_mark(c);
    let reachable = c.reachable;
    check_narrow_condition(p, c, n_left, true);
    let left = check_expression(p, c, n_right, expected); let left_reachable = c.reachable;
    var left_flow = CheckSpan {}; check_flow_delta(c, mark, left_flow);
    check_flow_undo(c, mark); c.reachable = reachable;
    check_narrow_condition(p, c, n_left, false);
    var right = TYPE_VOID;
    if n_third >= 0 { right = check_expression(p, c, n_third, expected); }
    else if expected >= 0 && expected != TYPE_VOID { diagnose(p, n_tok, "if used as a value requires an else branch"); }
    let right_reachable = c.reachable;
    var right_flow = CheckSpan {}; check_flow_delta(c, mark, right_flow);
    check_flow_join(p, c, left_flow, right_flow, left_reachable, right_reachable);
    check_flow_close(c, mark);
    c.reachable = left_reachable || right_reachable;
    check_copy_roots(c, node, n_right); if n_third >= 0 { check_copy_roots(c, node, n_third); }
    if expected == TYPE_VOID { return TYPE_VOID; }
    if !left_reachable {
        if n_third >= 0 { p.nodes[node].flags |= p.nodes[n_third].flags & F_ARRAY_JOIN; }
        return right;
    }
    if !right_reachable { p.nodes[node].flags |= p.nodes[n_right].flags & F_ARRAY_JOIN; return left; }
    return check_join_type(p, c, n_right, left, n_third, right, n_tok, true, node);
}

fn check_operation_same(p: Program&, a: i64, b: i64) -> bool {
    if a < 0 || b < 0 { return false; }
    if check_same_type(p, a, b) { return true; }
    let at: const Type& = p.types[a]; let bt: const Type& = p.types[b];
    return at.kind == bt.kind && at.element == bt.element && at.count == bt.count && at.array_kind == bt.array_kind && at.storage == bt.storage && at.length_storage == bt.length_storage && at.pool == bt.pool && at.index_type == bt.index_type && at.declaration == bt.declaration && (at.flags & ~TF_CONST) == (bt.flags & ~TF_CONST);
}
// Equal but for the constness of the type itself; slices compare by element,
// whatever array_kind their interned type happens to record.
fn check_top_const_same(p: Program&, a: i64, b: i64) -> bool {
    if a < 0 || b < 0 { return false; }
    let at: const Type& = p.types[a]; let bt: const Type& = p.types[b];
    if at.kind == TY_SLICE && bt.kind == TY_SLICE { return at.element == bt.element && at.count == bt.count && (at.flags & ~TF_CONST) == (bt.flags & ~TF_CONST); }
    return check_operation_same(p, a, b);
}
fn check_operation_parameter(p: Program&, c: Checker&, node: i64, type_id: i64, comparison: bool) -> i64 {
    if p.types[type_id].kind == TY_REF { return type_id; }
    let borrow = comparison && check_type_property(p, type_id, 6) != 0;
    if (borrow || check_size_class(p, type_id, 0) > 0) && check_addressable(p, node) {
        let flags = if borrow || check_readonly(p, c, node) { TF_CONST } else { 0 };
        return check_type(p, TY_REF, type_id, 0, -1, flags);
    }
    return type_id;
}
recursive fn check_lower_operation(p: Program&, c: Checker&, node: i64, left_type: i64, right_type: i64, result_type: i64, op: i64) -> i64 {
    let original = p.nodes[node]; var left_formal = check_operation_parameter(p, c, original.left, left_type, op == T_EQ); var right_formal = -1;
    if right_type >= 0 { right_formal = check_operation_parameter(p, c, original.right, right_type, op == T_EQ); }
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
    // Synthetic operation functions are created only below, in node order.
    var function_node = -1; let count = c.operation_functions.len;
    for operation in 0..count {
        let candidate = c.operation_functions[operation]; let n = p.nodes[candidate];
        if n.kind != N_FUNCTION || (n.flags & F_SYNTHETIC) == 0 || n.aux != op || n.first < 0 { continue; }
        let first = n.first; let second = p.nodes[first].next;
        if !check_same_type(p, p.nodes[first].type_id, left_formal) { continue; }
        if right_formal < 0 && second < 0 || right_formal >= 0 && second >= 0 && check_same_type(p, p.nodes[second].type_id, right_formal) { function_node = candidate; break; }
    }
    if function_node < 0 {
        function_node = operation_function(p, left_formal, right_formal, result_type, op, original.token);
        c.operation_functions.push(function_node);
        p.nodes[function_node].scope = 0;
        let saved_function = c.function_node; c.function_node = -1; check_declare(p, c, function_node, 0); c.function_node = saved_function;
    }
    let callee = operation_ident(p, p.nodes[function_node].token); var last = original.left;
    p.nodes[original.left].next = -1;
    if right_type >= 0 { p.nodes[original.left].next = original.right; p.nodes[original.right].next = -1; last = original.right; }
    p.nodes[node] = Node { flags: original.flags & F_TAIL, kind: N_CALL as i32, token: original.token, first: original.left,
                    last: last, next: original.next, left: callee as i32, scope: original.scope };
    let comparison = c.literal_comparison; c.literal_comparison = op == T_EQ;
    let result = check_call(p, c, node, -1); p.nodes[node].type_id = result as i32;
    c.literal_comparison = comparison;
    if original.integer == T_NEQ { check_wrap_unary(p, node, T_NOT, TYPE_BOOL); }
    return result;
}
recursive fn check_aggregate_operation(p: Program&, c: Checker&, node: i64, left: i64, right: i64) -> i64 {
    let op = p.nodes[node].integer;
    if p.types[left].kind == TY_REF && (p.types[left].flags & TF_OPTIONAL) != 0 || p.types[right].kind == TY_REF && (p.types[right].flags & TF_OPTIONAL) != 0 { return -2; }
    let lt = operation_value_type(p, left); let rt = operation_value_type(p, right);
    if root_struct_type(p, lt) || root_struct_type(p, rt) {
        diagnose(p, p.nodes[node].token, "root owners do not support value operators; operate on their fields instead"); return -1;
    }
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
    let path_base = c.path_base; c.path_base = false;
    if node < 0 { return TYPE_VOID; }
    let n: const Node& = p.nodes[node];
    let kind = n.kind;
    let flags = n.flags;
    let tok = n.token;
    let n_sym = n.symbol;
    let tid = n.type_id;
    if kind == N_NAME && n_sym >= 0 && !check_global_use(p, c, n_sym, tok) { return -1; }
    if (flags & F_CHECKED) != 0 && tid >= 0 {
        if kind == N_CALL && expected > TYPE_VOID && n_sym >= 0 && p.symbols[n_sym].node >= 0 &&
           p.nodes[p.symbols[n_sym].node].kind == N_FUNCTION_VALUE && check_conversion(p, c, node, tid, expected) < 0 {
            return check_call(p, c, node, expected);
        }
        if (kind == N_ARRAY || kind == N_FILL) && expected >= 0 { return check_array(p, c, node, expected); }
        if check_addressable(p, node) || kind == N_CALL { let loaded = check_plain_value_type(p, tid); p.nodes[node].type_id = loaded as i32; return loaded; }
        return tid;
    }
    let left = n.left;
    let right = n.right;
    let third = n.third;
    let integer = n.integer;
    let entry_reachable = c.reachable;
    p.nodes[node].scope = c.scope as i32;
    if c.reachable && kind != N_FUNCTION_VALUE { p.nodes[node].flags |= F_REACHABLE; }
    var result = -1;
    if kind == N_INTEGER { result = TYPE_I64; if (flags & F_UNSIGNED) != 0 { result = TYPE_U64; } }
    else if kind == N_FLOAT { result = TYPE_F64; }
    else if kind == N_BOOL { result = TYPE_BOOL; }
    else if kind == N_STRING {
        result = TYPE_STRING;
        if expected >= 0 && p.types[expected].kind == TY_ARRAY && p.types[expected].element == TYPE_U8 {
            let length = p.tokens[tok].text_len;
            if p.types[expected].array_kind == A_FIXED && p.types[expected].count != length {
                diagnose(p, tok, "string literal length does not match the fixed array");
            }
            if p.types[expected].array_kind == A_LIMITED && p.types[expected].count >= 0 && p.types[expected].count < length {
                diagnose(p, tok, "string literal exceeds the limited array capacity");
            }
            result = expected;
        }
        check_add_root(c, node, -1);
    } else if kind == N_NULL {
        if expected >= 0 && p.types[expected].kind == TY_REF && (p.types[expected].flags & TF_OPTIONAL) != 0 { result = expected; }
        else { result = check_type(p, TY_REF, TYPE_VOID, 0, -1, TF_OPTIONAL); }
    } else if kind == N_NAME {
        check_parameter_default_name(p, c, node, false);
        if p.nodes[node].expansion_binding == -2 { diagnose(p, tok, "const for binding is not a value or callable function"); }
        else if p.tokens[tok].kind == T_SELF { diagnose(p, tok, "self requires a relative reference field initializer"); }
        else {
            let symbol = check_lookup_name(p, c, node);
            if symbol < 0 {
                var msg: u8[>..] = []; msg.append("unknown name `"); msg.append(token_text(p, tok)); msg.push('`');
                diag_suggest_name(p, c, token_text(p, tok), c.scope, 0, msg);
                diagnose(p, tok, msg);
            }
            else {
                p.nodes[node].symbol = symbol as i32;
                let sflags = p.symbols[symbol].flags;
                let stype = p.symbols[symbol].type_id;
                let snode = p.symbols[symbol].node;
                if (sflags & S_TYPE) != 0 {
                    if stype >= 0 && p.types[stype].kind == TY_FN { result = stype; }
                    else { diagnose(p, tok, "type name is not a runtime value"); }
                }
                else if (sflags & S_FUNCTION) != 0 {
                    if snode >= 0 { check_prepare_function(p, c, snode); result = p.nodes[snode].type_id; }
                } else {
                    if !check_global_use(p, c, symbol, tok) { return -1; }
                    if (sflags & S_GLOBAL) != 0 && snode >= 0 && (p.nodes[snode].flags & F_CHECKED) == 0 { check_variable(p, c, snode); }
                    result = p.symbols[symbol].type_id;
                    let vi = check_variable_index(c, symbol); check_environment_note(p, c, symbol);
                    if vi >= 0 && c.variables[vi].narrowed >= 0 { result = c.variables[vi].narrowed; }
                    let element_access = path_base && (sflags & S_GLOBAL) == 0 && stype >= 0 && p.types[stype].kind != TY_REF && p.types[stype].kind != TY_SLICE;
                    if vi >= 0 && !c.variables[vi].assigned && !element_access {
                        var msg: u8[>..] = []; msg.append("value is read before it is definitely assigned: `");
                        msg.append(token_text(p, tok)); msg.push('`');
                        diagnose(p, tok, msg);
                    }
                    check_capture(p, c, symbol); check_copy_roots(c, node, -symbol - 10);
                }
            }
        }
    } else if kind == N_UNARY {
        if integer == T_BITAND {
            let ty = check_single_expression(p, c, left);
            if !check_addressable(p, left) && !(ty >= 0 && p.types[ty].kind == TY_REF) { diagnose(p, tok, "reference requires addressable storage"); }
            check_require_referenceable(p, c, left);
            var rflags = 0; if check_borrow_readonly(p, c, left) { rflags |= TF_CONST; }
            if ty >= 0 && p.types[ty].kind == TY_REF {
                result = check_read_value_type(p, c, left, ty); check_copy_roots(c, node, left);
            } else {
                if ty >= 0 && p.types[ty].storage == 1 { rflags |= TF_CONST; }
                result = check_type(p, TY_REF, ty, 0, -1, rflags);
                if (rflags & TF_CONST) == 0 { check_named_writable(p, c, check_place_root(p, left), tok); }
                check_add_root(c, node, check_place_root(p, left), check_reference_kind(p, left));
            }
        } else if integer == T_MUL {
            let ty = check_expression(p, c, left, -1);
            if ty < 0 || p.types[ty].kind != TY_REF {
                var msg: u8[>..] = []; msg.append("dereference requires a reference: got `"); diag_append_type(p, ty, msg); msg.push('`');
                diagnose(p, tok, msg);
            }
            else { result = p.types[ty].element; check_copy_roots(c, node, left); }
        } else if integer == T_NOT {
            check_condition(p, c, left); result = TYPE_BOOL;
        } else {
            let ty = check_value(p, c, left, -1);
            if ty >= 0 && integer == T_MINUS && (p.types[ty].kind == TY_STRUCT || p.types[ty].kind == TY_ARRAY) && operation_numeric_class(p, ty) > 0 && !operation_unsigned_leaf(p, ty) {
                result = check_lower_operation(p, c, node, ty, -1, ty, T_MINUS); p.nodes[node].type_id = result as i32; return result;
            }
            if !check_numeric(ty) { diagnose(p, tok, "numeric unary operator requires a number"); }
            if integer == T_BITNOT && !check_integer(ty) { diagnose(p, tok, "bitwise complement requires an integer"); }
            if integer != T_MINUS && integer != T_BITNOT { diagnose(p, tok, "invalid unary operator"); }
            result = ty;
            if integer == T_MINUS && check_unsigned(ty) {
                let constant = check_constant(p, c, left, 0);
                if !constant.valid || !check_integer_constants(p, c, left) { diagnose(p, tok, "cannot negate an unsigned value: convert it with as first"); }
                else if constant.type_id == TYPE_U64 && constant.value < 0 && constant.value != -9223372036854775808 {
                    diagnose(p, tok, "negated constant is too large for i64");
                } else {
                    check_rely_named(p, c, left);
                    p.nodes[node].kind = N_INTEGER as i32; p.nodes[node].left = -1;
                    p.nodes[node].integer = constant.value;
                    if constant.value != -9223372036854775808 { p.nodes[node].integer = -constant.value; }
                    result = TYPE_I64;
                }
            }
        }
    } else if kind == N_BINARY {
        let op = integer;
        if op == T_ANDAND || op == T_OROR {
            check_condition(p, c, left);
            var mark = check_flow_mark(c);
            let reachable = c.reachable; check_narrow_condition(p, c, left, op == T_ANDAND);
            var narrowed = CheckList {}; check_logical_capture(c, narrowed);
            check_condition(p, c, right); check_logical_record(c, node, narrowed);
            var after = CheckSpan {}; check_flow_delta(c, mark, after); let right_reachable = c.reachable;
            // The state before the right operand meets the state after it;
            // optional globals keep their state from before the operator.
            for index in after.first..after.first + after.count {
                let d = c.flow_work[index]; let vi = d.variable;
                let before = CheckFlowUndo { variable: vi, assigned: d.old_assigned, maybeassigned: d.old_maybeassigned, narrowed: d.old_narrowed };
                let now = CheckFlowUndo { variable: vi, assigned: d.assigned, maybeassigned: d.maybeassigned, narrowed: d.narrowed };
                check_flow_merge(p, c, vi, before, now, reachable, right_reachable);
                let symbol: const Symbol& = p.symbols[c.variables[vi].symbol]; let ty = symbol.type_id;
                if (symbol.flags & S_GLOBAL) != 0 && ty >= 0 && p.types[ty].kind == TY_REF && (p.types[ty].flags & TF_OPTIONAL) != 0 {
                    check_flow_set(c, vi, d.old_assigned, d.old_maybeassigned, d.old_narrowed);
                }
            }
            check_logical_apply(c, node); c.reachable = reachable; check_flow_close(c, mark);
            result = TYPE_BOOL;
        } else {
            var lt = -1; var rt = -1;
            let identity = op == T_DOTEQ || op == T_DOTNEQ;
            let null_comparison = (op == T_EQ || op == T_NEQ) && (p.nodes[left].kind == N_NULL || p.nodes[right].kind == N_NULL);
            if identity {
                lt = check_identity_operand(p, c, left); rt = check_identity_operand(p, c, right);
                result = TYPE_BOOL; p.nodes[node].aux = -1;
                if lt >= 0 && rt >= 0 && !check_bottom(p, left) && !check_bottom(p, right) {
                    if p.types[lt].kind != TY_REF || p.types[rt].kind != TY_REF {
                        diagnose(p, tok, "reference identity compares addresses of references or storage");
                    } else if p.nodes[left].kind != N_NULL && p.nodes[right].kind != N_NULL &&
                              !check_same_type(p, p.types[lt].element, p.types[rt].element) {
                        diagnose(p, tok, "reference identity requires the same pointee type");
                    }
                }
            } else if null_comparison {
                lt = check_expression(p, c, left, -1); rt = check_expression(p, c, right, -1);
            } else { lt = check_value(p, c, left, -1); rt = check_value(p, c, right, -1); }
            if !identity && lt >= 0 && rt >= 0 {
                let comparison = op == T_EQ || op == T_NEQ || op == T_LT || op == T_LTEQ || op == T_GT || op == T_GTEQ || op == T_DOTEQ || op == T_DOTNEQ;
                if check_numeric(lt) && check_numeric(rt) {
                    if !check_same_type(p, lt, rt) && op != T_SHL && op != T_SHR {
                        let lr = check_conversion(p, c, left, lt, rt); let rl = check_conversion(p, c, right, rt, lt);
                        var lc = false; var rc = false;
                        if check_integer(lt) && check_integer(rt) {
                            lc = check_integer_constants(p, c, left) || check_flex_integer(p, c, left).flexible;
                            rc = check_integer_constants(p, c, right) || check_flex_integer(p, c, right).flexible;
                        }
                        // Two constants, one above i64.max: the operation is u64, unless the
                        // other is negative (upstream UnifyNumeric).
                        let left_above = lc && rc && check_constant_above_i64(p, c, left) && check_numeric_value_type(p, lt) == TYPE_U64;
                        let right_above = lc && rc && !left_above && check_constant_above_i64(p, c, right) && check_numeric_value_type(p, rt) == TYPE_U64;
                        if left_above || right_above {
                            if check_constant_negative(p, c, left) || check_constant_negative(p, c, right) {
                                diagnose(p, tok, "constant operands have no common type (one is above i64.max, the other negative)");
                            } else if left_above { check_expect(p, c, right, rt, lt); rt = lt; }
                            else { check_expect(p, c, left, lt, rt); lt = rt; }
                        } else if lc && !rc {
                            if lr < 0 { diagnose(p, tok, "integer constants do not all fit the other operand's type"); }
                            else { check_expect(p, c, left, lt, rt); lt = rt; }
                        } else if rc && !lc {
                            if rl < 0 { diagnose(p, tok, "integer constants do not all fit the other operand's type"); }
                            else { check_expect(p, c, right, rt, lt); rt = lt; }
                        } else if lr >= 0 && (rl < 0 || lr <= rl) { check_expect(p, c, left, lt, rt); lt = rt; }
                        else if rl >= 0 { check_expect(p, c, right, rt, lt); rt = lt; }
                        else if !identity && comparison && check_integer(lt) && check_integer(rt) &&
                            (check_numeric_value_type(p, lt) == TYPE_U64 && !check_unsigned(check_numeric_value_type(p, rt)) ||
                             check_numeric_value_type(p, rt) == TYPE_U64 && !check_unsigned(check_numeric_value_type(p, lt))) {
                            var signed = left;
                            if check_numeric_value_type(p, lt) == TYPE_U64 { signed = right; }
                            let proof = check_nonnegative_get(c, signed);
                            if proof < -1 { diagnose(p, tok, "comparison with u64 requires the signed side to be known non-negative"); }
                            else { check_nonnegative_rely(p, c, proof, tok); lt = TYPE_U64; rt = TYPE_U64; }
                        } else {
                            var msg: u8[>..] = []; msg.append("numeric operands require compatible types: `");
                            diag_append_type(p, lt, msg); msg.append("` and `"); diag_append_type(p, rt, msg);
                            msg.append("`\n  help: convert one operand explicitly with `as ...`");
                            diagnose(p, tok, msg);
                        }
                    }
                    if (op == T_BITAND || op == T_BITOR || op == T_XOR || op == T_SHL || op == T_SHR) &&
                       (!check_integer(lt) || !check_integer(rt)) { diagnose(p, tok, "integer operator requires integer operands"); }
                    p.nodes[node].aux = lt;
                    result = lt;
                } else {
                    var aggregate = -2;
                    if !identity && !null_comparison { aggregate = check_aggregate_operation(p, c, node, lt, rt); }
                    if aggregate != -2 { result = aggregate; }
                    else if comparison && (check_same_type(p, lt, rt) || identity && p.types[lt].kind == TY_REF && p.types[rt].kind == TY_REF && check_same_type(p, p.types[lt].element, p.types[rt].element) || p.nodes[left].kind == N_NULL || p.nodes[right].kind == N_NULL) {
                        if (op == T_LT || op == T_LTEQ || op == T_GT || op == T_GTEQ) && lt != TYPE_BOOL {
                            var msg: u8[>..] = []; msg.append("ordered comparison requires numeric operands: got `");
                            diag_append_type(p, lt, msg); msg.push('`');
                            diagnose(p, tok, msg);
                        }
                    } else {
                        var msg: u8[>..] = []; msg.append("operator does not accept these operand types: `");
                        diag_append_type(p, lt, msg); msg.append("` and `"); diag_append_type(p, rt, msg); msg.push('`');
                        diagnose(p, tok, msg);
                    }
                }
                if comparison { result = TYPE_BOOL; }
            }
        }
    } else if kind == N_CALL { result = check_call(p, c, node, expected); }
    else if kind == N_MEMBER {
        var enum_type = -1;
        if p.nodes[left].kind == N_TYPE_NAME {
            // Name<T>.Variant names its enum type with type arguments.
            enum_type = check_resolve_type(p, c, left);
            if enum_type >= 0 && p.types[enum_type].kind != TY_ENUM { diagnose(p, tok, "only an enum type names a variant constant"); return -1; }
            if enum_type < 0 { return -1; }
        } else if p.nodes[left].kind == N_NAME {
            let symbol = check_lookup_name(p, c, left);
            if symbol >= 0 && (p.symbols[symbol].flags & S_TYPE) != 0 {
                if p.symbols[symbol].node >= 0 && p.nodes[p.symbols[symbol].node].kind == N_TYPE_PARAM { diagnose(p, tok, "type parameter names a type, not a runtime enum value"); return -1; }
                enum_type = p.symbols[symbol].type_id;
            }
        }
        if enum_type >= 0 && p.types[enum_type].kind == TY_ENUM {
            check_layout_nominal(p, c, enum_type);
            var variant = p.types[enum_type].first;
            while variant >= 0 {
                if same_name(p, p.nodes[variant].token, tok) {
                    if p.nodes[variant].first >= 0 { diagnose(p, tok, "enum variant payload requires a constructor"); }
                    p.nodes[node].kind = N_RECORD as i32; p.nodes[node].left = -1; p.nodes[node].symbol = variant as i32;
                    result = enum_type;
                    if check_enum_fixed_reason(p, enum_type) != 0 {
                        var variable = p.types[enum_type]; variable.flags |= F_VARIABLE_MODE;
                        result = add_type(p, variable); check_layout_nominal(p, c, result);
                    }
                    break;
                }
                variant = p.nodes[variant].next;
            }
            if result < 0 {
                var msg: u8[>..] = []; msg.append("unknown enum variant: `"); diag_append_type(p, enum_type, msg);
                msg.append("` has no variant `"); msg.append(token_text(p, tok)); msg.push('`');
                diag_suggest_member(p, p.types[enum_type].first, token_text(p, tok), "variants", msg);
                diagnose(p, tok, msg);
            }
        } else {
            c.path_base = path_base; var ty = check_single_expression(p, c, left);
            if ty >= 0 && p.types[ty].kind == TY_REF {
                let element = p.types[ty].element; check_wrap_unary(p, left, T_MUL, element); ty = element;
            }
            let n_aux = p.nodes[node].aux;
            if n_aux >= 0 && !check_operation_same(p, ty, n_aux) { diagnose(p, tok, "const for field accessor belongs to a different aggregate type"); }
            let builtin = check_builtin_kind(p, tok);
            if ty >= 0 && (p.types[ty].kind == TY_ARRAY || p.types[ty].kind == TY_SLICE) && (builtin == 21 || builtin == 22) {
                let name = new_node(p, N_NAME, tok);
                p.nodes[node].kind = N_CALL as i32; p.nodes[node].first = left; p.nodes[node].last = left;
                p.nodes[node].left = name as i32; p.nodes[node].right = -1; p.nodes[node].flags |= F_PROPERTY;
                result = check_builtin(p, c, node, builtin);
            } else if ty >= 0 && p.types[ty].kind == TY_STRUCT {
                check_layout_nominal(p, c, ty);
                var field = p.types[ty].first;
                while field >= 0 {
                    if same_name(p, p.nodes[field].token, tok) { result = p.nodes[field].type_id; p.nodes[node].symbol = field as i32; break; }
                    field = p.nodes[field].next;
                }
                if result < 0 {
                    var msg: u8[>..] = []; msg.append("struct has no field of this name: `"); diag_append_type(p, ty, msg);
                    msg.append("` has no field `"); msg.append(token_text(p, tok)); msg.push('`');
                    diag_suggest_member(p, p.types[ty].first, token_text(p, tok), "fields", msg);
                    diagnose(p, tok, msg);
                }
                check_copy_roots(c, node, left);
            } else {
                var msg: u8[>..] = []; msg.append("member access requires an aggregate, array or enum type: got `");
                diag_append_type(p, ty, msg); msg.push('`');
                diagnose(p, tok, msg);
            }
        }
    } else if kind == N_INDEX || kind == N_SLICE {
        c.path_base = true; var ty = check_single_expression(p, c, left);
        if ty >= 0 && p.types[ty].kind == TY_REF {
            let element = p.types[ty].element; check_wrap_unary(p, left, T_MUL, element); ty = element;
        }
        if ty < 0 || p.types[ty].kind != TY_ARRAY && p.types[ty].kind != TY_SLICE {
            var msg: u8[>..] = []; msg.append("index or slice requires an array or slice: got `");
            diag_append_type(p, ty, msg); msg.push('`');
            diagnose(p, tok, msg);
        } else {
            let arr_elem = p.types[ty].element; let arr_count = p.types[ty].count;
            let arr_kind = p.types[ty].array_kind; let arr_flags = p.types[ty].flags;
            if right >= 0 { let it = check_value(p, c, right, -1); if !check_integer(it) { diagnose(p, tok, "array index must be an integer"); } }
            if third >= 0 { let it = check_value(p, c, third, -1); if !check_integer(it) { diagnose(p, tok, "slice bound must be an integer"); } }
            let start = check_constant(p, c, right, 0); let end = check_constant(p, c, third, 0);
            if start.valid && start.value < 0 { diagnose(p, tok, "array index must be nonnegative"); }
            if kind == N_INDEX {
                result = arr_elem;
                let index_type = check_index_value(p, right, -1);
                if index_type >= 0 && (p.types[index_type].flags & F_BOUND_TYPE) == 0 && check_names_storage(p, p.types[index_type].pool, left) { p.nodes[node].flags |= F_BOUNDS_PROVEN; }
                if start.valid && arr_count >= 0 && arr_kind == A_FIXED {
                    if start.value >= arr_count { diagnose(p, tok, "constant index is outside the fixed array"); }
                    else if start.value >= 0 { p.nodes[node].flags |= F_BOUNDS_PROVEN; }
                }
            } else {
                var sflags = arr_flags & TF_CONST; if check_readonly(p, c, left) { sflags |= TF_CONST; }
                result = check_type(p, TY_SLICE, arr_elem, -1, -1, sflags);
                if (flags & (F_FROM_END | F_TO_END)) == 0 && start.valid && end.valid && start.value > end.value { diagnose(p, tok, "slice start exceeds its end"); }
                if end.valid && end.value < 0 || end.valid && arr_kind == A_FIXED && arr_count >= 0 && end.value > arr_count {
                    diagnose(p, tok, "slice bound is outside the fixed array");
                }
                check_add_root(c, node, check_place_root(p, left), 1);
            }
            check_copy_roots(c, node, left);
        }
    } else if kind == N_ARRAY || kind == N_FILL { result = check_array(p, c, node, expected); }
    else if kind == N_RECORD { result = check_record(p, c, node, expected); }
    else if kind == N_CAST {
        let destination = check_resolve_type(p, c, right); var source = -1;
        if (flags & (F_SYNTHETIC | F_UNSIGNED)) == (F_SYNTHETIC | F_UNSIGNED) && destination >= 0 && p.types[destination].kind == TY_REF {
            source = check_expression(p, c, left, -1);
        } else { source = check_value(p, c, left, -1); }
        if source >= 0 && destination >= 0 {
            let sk = p.types[source].kind; let dk = p.types[destination].kind;
            if p.types[destination].index_type >= 0 && p.types[destination].pool >= 0 {
                var named = p.types[destination].pool;
                if p.symbols[named].component_owner >= 0 { named = p.symbols[named].component_owner; }
                let owner_node = p.symbols[named].node;
                let vi = check_variable_index(c, named);
                if c.initializing_globals && (owner_node < 0 || (p.nodes[owner_node].flags & F_CHECKED) == 0 || vi >= 0 && !c.variables[vi].assigned) {
                    diagnose(p, tok, "index conversion reads its named array before global initialization");
                }
            }
            if p.types[destination].index_type >= 0 && (flags & F_UNSIGNED) != 0 { diagnose(p, tok, "an index or bound cast always checks its named array; as! is not allowed"); }
            if p.types[destination].index_type >= 0 && !check_integer(check_numeric_value_type(p, source)) { diagnose(p, tok, "only an integer converts to an index or bound type"); }
            else if check_numeric(check_numeric_value_type(p, source)) && check_numeric(check_numeric_value_type(p, destination)) || source == TYPE_BOOL && check_integer(check_numeric_value_type(p, destination)) ||
               check_integer(check_numeric_value_type(p, source)) && destination == TYPE_BOOL || check_conversion(p, c, left, source, destination) >= 0 {
                result = destination;
            } else if (flags & F_UNSIGNED) != 0 && sk == TY_REF && dk == TY_REF { result = destination; }
            else { diagnose(p, tok, "explicit cast is not defined for these types"); }
            check_copy_roots(c, node, left);
        }
    } else if kind == N_IF { result = check_if(p, c, node, expected); }
    else if kind == N_BLOCK { result = check_block(p, c, node, expected); }
    else if kind == N_MATCH { result = check_match(p, c, node, expected); }
    else if kind == N_LOOP || kind == N_FOR || kind == N_WHILE {
        let returning = c.returning;
        if kind != N_LOOP { c.returning = false; }
        result = check_loop(p, c, node, expected); c.returning = returning;
    }
    else if kind == N_FUNCTION_VALUE {
        if p.nodes[node].symbol < 0 { check_declare(p, c, node, -2); }
        check_prepare_function(p, c, node); result = p.nodes[node].type_id;
        if expected >= 0 && p.types[expected].kind == TY_FN && p.types[expected].first >= 0 {
            var formal = p.nodes[node].first; var context = p.types[expected].first;
            while formal >= 0 && context >= 0 {
                if p.nodes[formal].left < 0 { p.nodes[formal].type_id = p.nodes[context].type_id; }
                formal = p.nodes[formal].next; context = p.nodes[context].next;
            }
            if formal >= 0 || context >= 0 { diagnose(p, tok, "function value parameter count does not match context"); }
        }
    } else if kind == N_RETURN { check_return(p, c, node); result = TYPE_VOID; }
    else if kind == N_BREAK || kind == N_CONTINUE { check_jump(p, c, node); result = TYPE_VOID; }
    else if kind == N_ASSIGN || kind == N_MULTI_ASSIGN { check_assignment(p, c, node); result = TYPE_VOID; }
    else if kind == N_RANGE {
        let l_ty = check_value(p, c, left, -1); let r_ty = check_value(p, c, right, -1);
        if !check_integer(l_ty) || !check_integer(r_ty) { diagnose(p, tok, "range bounds must be integers"); }
        result = check_join_type(p, c, left, check_index_value(p, left, l_ty), right, check_index_value(p, right, r_ty), tok);
    } else if kind == N_RESULT {
        let tuple = check_expression(p, c, left, -1);
        if tuple < 0 || p.types[tuple].kind != TY_TUPLE { diagnose(p, tok, "result projection requires a multi-result producer"); }
        else {
            var part = p.types[tuple].first; var ordinal = 0;
            while part >= 0 && ordinal < integer { part = p.nodes[part].next; ordinal += 1; }
            if part < 0 { diagnose(p, tok, "result projection ordinal is outside the producer's results"); }
            else { result = check_loaded_type(p, p.nodes[part].type_id); check_copy_roots(c, node, left); }
        }
    } else if kind == N_TUPLE {
        let n_first = p.nodes[node].first;
        var child = n_first;
        while child >= 0 { check_value(p, c, child, -1); child = p.nodes[child].next; }
        result = check_tuple(p, n_first);
    } else if kind == N_CONST_FOR || kind == N_CONST_IF { result = check_const_for(p, c, node, expected); }
    else if kind == N_DEFER { check_defer(p, c, node); result = TYPE_VOID; }
    else if kind == N_EMPTY { result = TYPE_VOID; }
    else if kind == N_EXPR_STMT { check_expression(p, c, left, TYPE_VOID); result = TYPE_VOID; }
    else { diagnose(p, tok, "syntax node is not a valid expression"); }
    if check_addressable(p, node) || kind == N_CALL { result = check_plain_value_type(p, result); }
    p.nodes[node].type_id = result as i32;
    check_nonnegative_result(p, c, node, kind, integer, flags, right, third, result);
    if entry_reachable && !c.reachable { p.nodes[node].flags |= F_DIVERGES; }
    if kind != N_FUNCTION_VALUE { p.nodes[node].flags |= F_CHECKED; }
    return result;
}

// edge is a delta since the loop's mark: its old state is the loop entry's.
fn check_loop_backedge(p: Program&, c: Checker&, node: i64, edge: CheckSpan, weakened: CheckList&) {
    for at in edge.first..edge.first + edge.count {
        let flow = c.flow_work[at]; let symbol = c.variables[flow.variable].symbol;
        if !flow.old_maybeassigned && flow.maybeassigned && (p.symbols[symbol].flags & S_MUTABLE) == 0 {
            diagnose(p, p.nodes[node].token, "let binding may already be assigned on a loop backedge");
        }
        if flow.old_narrowed >= 0 && !check_same_type(p, flow.old_narrowed, flow.narrowed) {
            check_list_push(c, weakened, symbol);
        }
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
    if expected == TYPE_VOID { return TYPE_VOID; }
    var values = inputs;
    if tail_reachable { check_list_push(c, values, tail); }
    var result = -1; var anchor = -1; var literal = true; var integer_constants = true;
    p.nodes[node].flags &= ~F_ARRAY_JOIN;
    for index in 0..values.count {
        let value = check_list_at(c, values, index); var ty = TYPE_VOID;
        if value >= 0 { ty = p.nodes[value].type_id; }
        else if tail_reachable && index == values.count - 1 { ty = tail_type; }
        let adaptable = check_join_literal(p, c, value);
        let integer_constant = adaptable && check_integer(check_numeric_value_type(p, ty)) && check_conversion(p, c, value, ty, TYPE_I64) >= 0;
        let previous = result;
        if index == 0 {
            result = ty; anchor = value;
            if value >= 0 { p.nodes[node].flags |= p.nodes[value].flags & F_ARRAY_JOIN; }
        }
        else if integer_constants && integer_constant {
            if !check_same_type(p, result, ty) { result = TYPE_I64; }
        }
        else if !literal && adaptable && (p.nodes[node].flags & F_ARRAY_JOIN) == 0 { result = check_join_type(p, c, value, ty, anchor, result, p.nodes[node].token, false, node); }
        else { result = check_join_type(p, c, anchor, result, value, ty, p.nodes[node].token, false, node); }
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
    if expected >= 0 && p.types[expected].kind == TY_SLICE { p.nodes[node].flags &= ~F_ARRAY_JOIN; }
    if adapt && result >= 0 && result != TYPE_VOID && (p.nodes[node].flags & F_ARRAY_JOIN) == 0 {
        if p.types[result].kind == TY_SLICE || p.types[result].kind == TY_REF { p.nodes[node].flags |= F_REFERENCE_CONTEXT; }
        for index in 0..values.count {
            let value = check_list_at(c, values, index);
            if value < 0 { diagnose(p, p.nodes[node].token, "value-producing construct has a valueless exit"); }
            else { check_expect(p, c, value, p.nodes[value].type_id, result); check_copy_roots(c, node, value); }
        }
    }
    return result;
}
recursive fn check_loop(p: Program&, c: Checker&, node: i64, expected: i64) -> i64 {
    let n_kind = p.nodes[node].kind; let n_left = p.nodes[node].left; let n_right = p.nodes[node].right;
    let n_first = p.nodes[node].first; let n_tok = p.nodes[node].token;
    let saved = check_enter(c, c.function_node); let exit_start = c.exit_work.len;
    p.nodes[node].scope = c.scope as i32;
    let mark = check_flow_mark(c);
    let li = c.loop_count;
    if n_kind == N_WHILE { check_push_loop(c, CheckLoop { node: node, scope: c.scope, function_node: c.function_node, expected: expected, returning: c.returning, mark: mark }); }
    if n_kind == N_WHILE { check_condition(p, c, n_left); }
    if n_kind == N_FOR {
        let source = check_single_expression(p, c, n_left); var element = TYPE_I64; var sequence = false; var sequence_type = -1;
        if source >= 0 {
            var ty = source;
            while ty >= 0 && p.types[ty].kind == TY_REF {
                if (p.types[ty].flags & TF_OPTIONAL) != 0 { diagnose(p, n_tok, "optional count must be narrowed before iteration"); }
                ty = p.types[ty].element;
            }
            if p.nodes[n_left].kind == N_RANGE || check_integer(check_numeric_value_type(p, ty)) {
                element = check_numeric_value_type(p, ty);
                if p.types[ty].kind == TY_INT && p.types[ty].index_type >= 0 {
                    var index_type = p.types[ty]; index_type.flags &= ~F_BOUND_TYPE; element = add_type(p, index_type);
                }
            }
            else if p.types[ty].kind == TY_ARRAY || p.types[ty].kind == TY_SLICE { element = p.types[ty].element; sequence = true; sequence_type = ty; }
            else { diagnose(p, n_tok, "for source must be a range, integer count, array or slice"); element = -1; }
        }
        var binding = n_first; var index = 0;
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
                        var bound = n_left;
                        if p.nodes[n_left].kind == N_RANGE { check_value(p, c, p.nodes[n_left].left, annotation); bound = p.nodes[n_left].right; }
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
                    if check_argument_readonly(p, c, n_left, sequence_type) || p.types[ty].storage == 1 { flags |= TF_CONST; }
                    ty = check_type(p, TY_REF, ty, 0, -1, flags);
                }
            }
            if ty >= 0 && p.types[ty].kind == TY_REF && p.types[ty].length_storage >= 0 && p.types[ty].pool < 0 && check_readonly(p, c, n_left) { ty = check_const_type(p, ty); }
            ty = check_loaded_type(p, ty);
            p.nodes[binding].type_id = ty as i32;
            let symbol = check_declare(p, c, binding, c.scope); p.symbols[symbol].type_id = ty;
            let vi = check_variable_index(c, symbol); check_set_assigned(c, vi, true, true);
            // The copied binding slot is immutable. A reference or slice
            // stored in it retains its own pointee writability.
            c.variables[vi].readonly = (p.nodes[binding].flags & F_REFERENCE) == 0;
            if (p.nodes[binding].flags & F_REFERENCE) != 0 {
                check_add_root(c, -symbol - 10, check_place_root(p, n_left), 1);
            }
            index += 1; binding = p.nodes[binding].next;
        }
    }
    if n_kind != N_WHILE { check_push_loop(c, CheckLoop { node: node, scope: c.scope, function_node: c.function_node, expected: expected, returning: c.returning, mark: mark }); }
    var entry = check_flow_mark(c);
    if n_kind == N_WHILE { check_narrow_condition(p, c, n_left, true); }
    let returning = c.returning; c.returning = false;
    check_expression(p, c, n_right, TYPE_VOID); c.returning = returning;
    if c.reachable { check_flow_exit(c, node, mark, true); }
    var weakened = CheckList {};
    for index in exit_start..c.exit_work.len {
        let edge = c.exit_work[index];
        if edge.target == node && edge.backedge { check_loop_backedge(p, c, node, edge.flow, weakened); }
    }
    if weakened.count > 0 {
        check_flow_undo(c, entry); check_flow_close(c, entry);
        for index in 0..weakened.count { let symbol = check_list_at(c, weakened, index); check_set_narrowed(c, check_variable_index(c, symbol), -1); }
        c.reachable = true;
        var bindings = CheckList {};
        if n_kind == N_WHILE {
            let condition = check_clone(p, c, n_left, bindings); p.nodes[node].left = condition as i32;
            check_condition(p, c, condition);
        }
        entry = check_flow_mark(c);
        if n_kind == N_WHILE { check_narrow_condition(p, c, p.nodes[node].left, true); }
        let body = check_clone(p, c, n_right, bindings); p.nodes[node].right = body as i32;
        c.returning = false; check_expression(p, c, body, TYPE_VOID); c.returning = returning;
    }
    let loop_state = c.loop_stack[li]; c.loop_count -= 1;
    check_flow_undo(c, entry); check_flow_close(c, entry);
    var fallthrough = n_kind != N_LOOP;
    if n_kind == N_WHILE { let condition = check_constant(p, c, n_left, 0); if condition.valid && condition.value != 0 { fallthrough = false; } }
    let reach = check_join_control_exits(p, c, node, exit_start, fallthrough, mark); c.reachable = reach;
    check_exits_consume(c, exit_start, node); check_flow_close(c, mark);
    c.scope = saved;
    if n_kind == N_LOOP && loop_state.breaks {
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
            if n.kind == N_CONTINUE { diagnose(p, n.token, "continue cannot cross a const for expansion boundary"); }
            else { diagnose(p, n.token, "break cannot cross a const for expansion boundary"); }
            return;
        }
        // A defer body runs at its block's exits; it cannot exit anything itself.
        if target.function_node == c.function_node && p.nodes[target.node].kind == N_DEFER {
            if n.kind == N_BREAK { diagnose(p, n.token, "break cannot leave a defer body (§6.6)"); }
            else { diagnose(p, n.token, "continue cannot leave a defer body (§6.6)"); }
            return;
        }
        if target.function_node == c.function_node &&
           (n.kind != N_CONTINUE || (p.nodes[target.node].flags & F_EARLY) == 0) { break; }
        li -= 1;
    }
    if li < 0 { diagnose(p, n.token, "break or continue has no enclosing target in this function"); return; }
    let target = c.loop_stack[li]; p.nodes[node].symbol = target.node as i32;
    if n.kind == N_BREAK {
        var ty = TYPE_VOID;
        if n.left >= 0 {
            // A prior exit's array or slice does not decide whether later
            // exits copy a value or borrow storage. Join them after discovery.
            var expected = target.expected;
            if expected < 0 && target.result >= 0 &&
               p.types[target.result].kind != TY_ARRAY && p.types[target.result].kind != TY_SLICE { expected = target.result; }
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
                let jres = check_join_break_values(p, c, target.node, values, -1, false, -1, target.expected, false);
                c.loop_stack[li].result = jres;
            }
            c.loop_stack[li].breaks = true;
            check_flow_exit(c, target.node, target.mark);
            if n.left >= 0 { check_copy_roots(c, target.node, n.left); }
        }
    } else if c.reachable {
        check_flow_exit(c, target.node, target.mark, true);
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
        while arm >= 0 {
            if p.nodes[arm].kind == N_ARM && check_valueless_tail(p, p.nodes[arm].right) || p.nodes[arm].kind == N_CONST_IF && check_valueless_tail(p, arm) { return true; }
            arm = p.nodes[arm].next;
        }
    }
    // Conditions are not evaluated here: every branch's arms count, as a
    // runtime if's branches do.
    if n.kind == N_CONST_IF { return check_valueless_tail(p, n.right) || check_valueless_tail(p, n.third); }
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
    let mark = check_flow_mark(c);
    var branches = CheckList {}; var any_reachable = false;
    var result = -1; var result_node = -1; var wildcard = false;
    var intervals = CheckList {}; var tags = CheckList {};
    var arm = p.nodes[node].first;
    while arm >= 0 {
        let a = p.nodes[arm];
        if a.kind != N_ARM { diagnose(p, a.token, "match expansion did not produce an arm"); arm = a.next; continue; }
        check_flow_undo(c, mark); c.reachable = true;
        let saved = check_enter(c, c.function_node);
        p.nodes[arm].scope = c.scope as i32;
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
                if variant < 0 {
                    var msg: u8[>..] = [];
                    msg.append("match pattern names no variant of this enum: `");
                    diag_append_type(p, source, msg);
                    msg.append("` has no variant `"); msg.append(token_text(p, pat.token)); msg.push('`');
                    diag_suggest_member(p, p.types[source].first, token_text(p, pat.token), "variants", msg);
                    diagnose(p, pat.token, msg);
                }
                else {
                    let tag = p.nodes[variant].integer;
                    for previous_index in 0..tags.count { let previous = check_list_at(c, tags, previous_index); if previous == tag { diagnose(p, pat.token, "duplicate enum match pattern"); } }
                    for previous_index in 0..arm_tags.count { if check_list_at(c, arm_tags, previous_index) == tag { diagnose(p, pat.token, "enum variant is listed twice in one arm"); } }
                    check_list_push(c, arm_tags, tag); p.nodes[item].symbol = variant as i32; p.nodes[item].integer = tag;
                    p.nodes[item].type_id = source as i32; p.nodes[item].flags |= F_CHECKED;
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
                        p.nodes[pat.left].kind = N_INTEGER as i32; p.nodes[pat.left].integer = emitted_low; p.nodes[pat.left].type_id = source as i32;
                        p.nodes[pat.right].kind = N_INTEGER as i32; p.nodes[pat.right].integer = emitted_high; p.nodes[pat.right].type_id = source as i32;
                    } else { p.nodes[item].kind = N_INTEGER as i32; p.nodes[item].integer = emitted_low; }
                    p.nodes[item].type_id = source as i32; p.nodes[item].flags |= F_CHECKED;
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
                p.nodes[binder].type_id = ty as i32;
                let symbol = check_declare(p, c, binder, c.scope); p.symbols[symbol].type_id = ty;
                let vi = check_variable_index(c, symbol); check_set_assigned(c, vi, true, true);
                c.variables[vi].readonly = (p.nodes[binder].flags & F_REFERENCE) == 0;
                if (p.nodes[binder].flags & F_REFERENCE) != 0 { check_add_root(c, -symbol - 10, check_place_root(p, n.left), 1); }
            }
        }
        if a.third >= 0 { check_condition(p, c, a.third); }
        var ty = TYPE_VOID;
        if statement { check_expression(p, c, a.right, TYPE_VOID); }
        else { ty = check_value(p, c, a.right, arm_expected, c.tuple_context); }
        if c.reachable {
            if result_node < 0 { p.nodes[node].flags |= p.nodes[a.right].flags & F_ARRAY_JOIN; }
            result = check_join_type(p, c, result_node, result, a.right, ty, n.token, true, node); result_node = a.right;
            var branch = CheckSpan {}; check_flow_delta(c, mark, branch);
            check_list_push(c, branches, branch.first); check_list_push(c, branches, branch.count);
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
    if !exhaustive {
        var msg: u8[>..] = [];
        msg.append("match does not cover every possible value");
        if enum_match {
            var v = p.types[source].first; var missing: i64 = 0;
            while v >= 0 {
                let tag = p.nodes[v].integer;
                var covered = false;
                for ti in 0..tags.count {
                    if check_list_at(c, tags, ti) == tag { covered = true; break; }
                }
                if !covered {
                    if missing == 0 { msg.append(": missing variant(s): "); }
                    else if missing < 8 { msg.append(", "); }
                    if missing < 8 {
                        msg.push('`'); msg.append(token_text(p, p.nodes[v].token)); msg.push('`');
                    }
                    missing += 1;
                }
                v = p.nodes[v].next;
            }
            if missing > 8 {
                msg.append(", ... ("); msg.format(missing - 8); msg.append(" more)");
            }
            msg.append("\n  help: add the missing arm(s) or a wildcard `_ => ...`");
        } else {
            msg.append("\n  help: integer match requires a wildcard arm `_ => ...`");
        }
        diagnose(p, n.token, msg);
    }
    if any_reachable {
        // Meet the reachable arms' states from the state before the match.
        check_flow_undo(c, mark);
        c.flow_clock += 1; let tag = c.flow_clock; let join_start = c.flow_join.len;
        for index in 0..branches.count / 2 {
            let branch = CheckSpan { first: check_list_at(c, branches, 2 * index), count: check_list_at(c, branches, 2 * index + 1) };
            check_join_delta(p, c, tag, branch, true);
        }
        check_join_finish(p, c, join_start, branches.count / 2);
    }
    check_flow_close(c, mark); c.reachable = any_reachable;
    if statement { return TYPE_VOID; }
    if result >= 0 && p.types[result].kind == TY_SLICE && (p.nodes[node].flags & F_ARRAY_JOIN) == 0 {
        p.nodes[node].flags |= F_REFERENCE_CONTEXT;
        var expanded_arm = p.nodes[node].first;
        while expanded_arm >= 0 {
            let body = p.nodes[expanded_arm].right;
            check_expect(p, c, body, p.nodes[body].type_id, result);
            check_copy_roots(c, node, body);
            expanded_arm = p.nodes[expanded_arm].next;
        }
    }
    return result;
}
recursive fn check_return(p: Program&, c: Checker&, node: i64) {
    let returning = c.returning; c.returning = true;
    check_return_value(p, c, node); c.returning = returning;
}
recursive fn check_return_value(p: Program&, c: Checker&, node: i64) {
    let n_tok = p.nodes[node].token; let n_flags = p.nodes[node].flags;
    let n_left = p.nodes[node].left; let n_first = p.nodes[node].first;
    var target = c.function_node;
    if c.default_body { diagnose(p, n_tok, "return is only valid inside a function"); return; }
    // A return written in a defer body, or in a function value written in
    // one, would leave the body (a function value's own tail is no exit).
    if c.defer_bodies > 0 && (n_flags & F_IMPLICIT_RETURN) == 0 && check_in_defer_body(p, c) {
        diagnose(p, n_tok, "return cannot leave a defer body (§6.6)"); return;
    }
    if target >= 0 && p.nodes[target].kind == N_FUNCTION_VALUE && (n_flags & F_IMPLICIT_RETURN) == 0 && n_left < 0 {
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
    if target < 0 { diagnose(p, n_tok, "return is only valid inside a function"); return; }
    if n_left >= 0 {
        target = -1;
        let functions = check_lookup_name(p, c, n_left, S_FUNCTION | S_BUILTIN);
        var i = c.checking_count - 1;
        while i >= 0 && target < 0 {
            let fnnode = c.checking[i].function_node; var candidate = functions;
            while candidate >= 0 {
                let symbol: const Symbol& = p.symbols[candidate];
                if (symbol.flags & S_FUNCTION) != 0 && p.nodes[fnnode].kind == N_FUNCTION &&
                   check_function_declaration(p, fnnode) == check_function_declaration(p, symbol.node) { target = fnnode; break; }
                candidate = symbol.next;
            }
            i -= 1;
        }
        if target < 0 { diagnose(p, n_tok, "nonlocal return does not name an active enclosing function"); return; }
        if target != c.function_node { p.nodes[c.function_node].flags |= F_NONLOCAL; }
    }
    let symbol = p.nodes[target].symbol; p.nodes[node].symbol = symbol;
    if target != c.function_node {
        p.nodes[node].flags |= F_NONLOCAL;
        var index = c.checking_count - 1;
        while index >= 0 && c.checking[index].function_node != target { check_add_need(p, c, c.checking[index].function_node, target); index -= 1; }
    }
    var expected = c.result_type;
    if target != c.function_node { expected = p.types[p.nodes[target].type_id].element; }
    var expected_part = -1;
    if expected >= 0 && p.types[expected].kind == TY_TUPLE { expected_part = p.types[expected].first; }
    var forward_tuple = false;
    let single_return = n_first >= 0 && p.nodes[n_first].next < 0;
    if single_return {
        let saved = c.tuple_context; c.tuple_context = expected < 0 || p.types[expected].kind == TY_TUPLE;
        let value_type = check_expression(p, c, n_first, expected); c.tuple_context = saved;
        if !c.reachable { return; }
        if value_type >= 0 && p.types[value_type].kind == TY_TUPLE && (expected < 0 || p.types[expected].kind == TY_TUPLE) { forward_tuple = true; expected_part = -1; }
    }
    var converted_first = -1; var converted_last = -1;
    var value = n_first; var index = 0;
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
                if expected_part >= 0 { p.nodes[expected_part].type_id = destination as i32; }
                else {
                    expected = destination;
                    p.types[p.nodes[target].type_id].element = destination; type_reindex(p, p.nodes[target].type_id);
                    if target == c.function_node { c.result_type = destination; }
                }
            }
        }
        var ty = check_value(p, c, value, destination, forward_tuple);
        if !c.reachable { return; }
        if destination < 0 { ty = check_inferred_result(p, c, value, target); }
        let converted = new_node(p, N_TYPE_ARG, p.nodes[value].token); p.nodes[converted].type_id = ty as i32;
        if converted_first < 0 { converted_first = converted; } else { p.nodes[converted_last].next = converted as i32; }
        converted_last = converted;
        if expected_part >= 0 { expected_part = p.nodes[expected_part].next; }
        if ty >= 0 && check_contains_refs(p, ty, 0) {
            var root_at = check_root_head(c, value);
            while root_at >= 0 {
                let r = c.roots[root_at]; root_at = r.next;
                check_push_return_root(c, CheckReturnRoot { function_node: target, index: index, root: r.root, kind: r.kind });
            }
        }
        index += 1; value = p.nodes[value].next;
    }
    var actual = check_tuple(p, converted_first);
    if forward_tuple && converted_first >= 0 { actual = p.nodes[converted_first].type_id; }
    if expected >= 0 && !check_same_type(p, expected, actual) {
        if n_first < 0 || !single_return || check_conversion(p, c, n_first, actual, expected) < 0 {
            var msg: u8[>..] = [];
            msg.append("return values do not match the function result signature: got `");
            diag_append_type(p, actual, msg);
            msg.append("`, expected `");
            diag_append_type(p, expected, msg);
            msg.push('`');
            diag_conversion_help(p, actual, expected, msg);
            diagnose(p, n_tok, msg);
        }
    }
    // An exit only reaches a target being checked: its join is that check's end.
    var target_active = false; let target_mark = check_function_mark(c, target, target_active);
    if target_active { check_flow_exit(c, target, target_mark); }
    p.nodes[target].flags |= F_RETURNS; p.nodes[target].flags &= ~F_DIVERGES;
    if target == c.function_node {
        if c.result_type < 0 { c.result_type = actual; p.types[p.nodes[target].type_id].element = actual; type_reindex(p, p.nodes[target].type_id); }
        else if expected < 0 { let joined = check_join_type(p, c, -1, c.result_type, n_first, actual, n_tok); c.result_type = joined; }
        c.returns = true;
    } else if expected < 0 { p.types[p.nodes[target].type_id].element = actual; type_reindex(p, p.nodes[target].type_id); }
    c.reachable = false;
}

recursive fn check_variable(p: Program&, c: Checker&, node: i64) {
    if (p.nodes[node].flags & F_CHECKED) != 0 { return; }
    let n_flags = p.nodes[node].flags; let n_tok = p.nodes[node].token;
    let n_left = p.nodes[node].left; let n_first = p.nodes[node].first; let n_right = p.nodes[node].right;
    let original_symbol = p.nodes[node].symbol;
    p.nodes[node].flags |= F_CHECKED;
    var declaration_scope = c.scope; var function_node = c.function_node;
    let global = original_symbol >= 0 && (p.symbols[original_symbol].flags & S_GLOBAL) != 0;
    if global {
        declaration_scope = p.symbols[original_symbol].scope; function_node = -1;
    }
    let saved_scope = c.scope; let saved_function = c.function_node;
    c.scope = declaration_scope; c.function_node = function_node;
    var annotation = check_value_annotation(p, c, n_left, check_resolve_type(p, c, n_left));
    if (n_flags & F_CONST) != 0 && annotation >= 0 { annotation = check_const_type(p, annotation); }
    var names = CheckList {};
    if n_first >= 0 {
        var binding = n_first;
        while binding >= 0 {
            p.nodes[binding].flags |= n_flags & (F_VAR | F_CONST | F_REUSABLE | F_REUSABLE_SLICES);
            check_list_push(c, names, binding); binding = p.nodes[binding].next;
        }
    } else { check_list_push(c, names, node); }
    var values = CheckList {}; var value = n_right;
    while value >= 0 { check_list_push(c, values, value); value = p.nodes[value].next; }
    if values.count == 0 && global && annotation >= 0 {
        // A global's default value is its declaration's own initializer.
        let init = check_default_syntax(p, c, annotation, n_tok, 0);
        if init >= 0 { let saved_root = c.root_record; c.root_record = init; check_expression(p, c, init, annotation); c.root_record = saved_root; }
        p.nodes[node].right = init as i32;
        if init >= 0 { check_list_push(c, values, init); }
    }
    var tuple = -1;
    if values.count == 1 && names.count > 1 {
        tuple = check_value(p, c, check_list_at(c, values, 0), -1, true);
        if tuple < 0 && !c.reachable { tuple = p.nodes[check_list_at(c, values, 0)].type_id; }
        if tuple < 0 || p.types[tuple].kind != TY_TUPLE || p.types[tuple].count != names.count {
            diagnose(p, n_tok, "multiple binding requires the same number of call results"); tuple = -1;
        }
        if annotation >= 0 { diagnose(p, n_tok, "multiple-value binding cannot have one type annotation"); }
    } else if values.count > 0 && values.count != names.count { diagnose(p, n_tok, "binding name and initializer counts differ"); }
    var component = -1; if tuple >= 0 { component = p.types[tuple].first; }
    for index in 0..names.count { let binding = check_list_at(c, names, index);
        var ty = annotation; var init = -1;
        if tuple >= 0 && component >= 0 {
            ty = check_loaded_type(p, p.nodes[component].type_id); init = check_list_at(c, values, 0); component = p.nodes[component].next;
            if (n_flags & F_REFERENCE) == 0 {
                if ty >= 0 && p.types[ty].kind == TY_REF && (p.types[ty].flags & TF_OPTIONAL) == 0 {
                    let element = p.types[ty].element;
                    if check_size_class(p, element, 0) == 0 || p.types[element].storage == 1 { ty = element; }
                }
                if ty < 0 || p.types[ty].index_type < 0 { ty = check_numeric_value_type(p, ty); }
            }
        }
        else if index < values.count {
            init = check_list_at(c, values, index);
            if (n_flags & F_REFERENCE) != 0 && annotation < 0 {
                ty = check_read_value_type(p, c, init, check_single_expression(p, c, init));
                if ty >= 0 && p.types[ty].kind != TY_REF && p.types[ty].kind != TY_SLICE {
                    if !check_addressable(p, init) { diagnose(p, n_tok, ".= initialization requires storage, reference or slice"); }
                    else {
                        let root = check_place_root(p, init); var flags = 0;
                        if check_readonly(p, c, init) || p.types[ty].storage == 1 { flags |= TF_CONST; }
                        ty = check_type(p, TY_REF, ty, 0, -1, flags);
                        let root_kind = check_reference_kind(p, init);
                        if (flags & TF_CONST) == 0 { check_named_writable(p, c, root, n_tok); }
                        check_require_referenceable(p, c, init);
                        check_wrap_unary(p, init, T_BITAND, ty); check_add_root(c, init, root, root_kind);
                    }
                }
            } else {
                if annotation < 0 && p.nodes[init].kind == N_UNARY && p.nodes[init].integer == T_BITAND {
                    ty = check_read_value_type(p, c, init, check_expression(p, c, init, -1));
                } else {
                    let saved_root = c.root_record; c.root_record = init;
                    ty = check_value(p, c, init, annotation);
                    c.root_record = saved_root;
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
            if p.nodes[init].kind == N_NULL && annotation < 0 { diagnose(p, n_tok, "null binding requires an optional type annotation"); }
            if ty >= 0 && p.types[ty].kind == TY_ARRAY && p.types[ty].element < 0 {
                if (n_flags & F_VAR) == 0 || p.nodes[init].kind != N_ARRAY {
                    diagnose(p, n_tok, "empty array element inference requires a var initialized directly with []");
                }
                ty = add_type(p, Type { kind: TY_ARRAY, element: -1, count: -1, size: p.control_bytes, align: p.control_align, array_kind: A_GROW, length_storage: -1 });
                p.nodes[init].type_id = ty as i32;
            }
        } else if annotation < 0 { diagnose(p, n_tok, "binding requires a type or initializer"); }
        if init >= 0 && ty < 0 && annotation < 0 {
            if p.nodes[init].type_id < 0 { diagnose(p, n_tok, "initializer has no value from which to infer its type"); }
            else if !c.reachable { ty = p.nodes[init].type_id; }
        }
        if ty == TYPE_VOID { diagnose(p, n_tok, "binding initializer produces no value"); }
        if ty >= 0 && p.types[ty].kind == TY_FN { diagnose(p, n_tok, "function values are compile-time arguments and cannot be stored"); }
        if ty >= 0 && (n_flags & F_CONST) != 0 { ty = check_const_type(p, ty); }
        p.nodes[binding].type_id = ty as i32;
        let symbol = check_declare(p, c, binding, c.scope); p.symbols[symbol].type_id = ty;
        if (p.symbols[symbol].flags & S_GLOBAL) != 0 && ty >= 0 && p.types[ty].kind == TY_REF && (p.types[ty].flags & TF_OPTIONAL) != 0 { c.optional_globals = true; }
        if index == 0 { p.nodes[node].symbol = symbol as i32; p.nodes[node].type_id = ty as i32; }
        let vi = check_variable_index(c, symbol);
        if vi >= 0 {
            check_set_assigned(c, vi, init >= 0, init >= 0);
            c.variables[vi].readonly = (n_flags & F_CONST) != 0;
            if init >= 0 && tuple < 0 && ty >= 0 && p.types[ty].kind == TY_INT && (n_flags & F_VAR) == 0 {
                c.variables[vi].nonnegative = check_nonnegative_get(c, init);
            }
            if init >= 0 && ty >= 0 && (p.types[ty].kind == TY_REF || p.types[ty].kind == TY_SLICE) && check_readonly(p, c, init) { c.variables[vi].readonly = true; }
        }
        if init >= 0 && ty >= 0 && check_contains_refs(p, ty, 0) { check_store_roots(p, c, symbol, init); }
        if (n_flags & F_REUSABLE) != 0 {
            if (n_flags & F_VAR) == 0 || ty < 0 || p.types[ty].kind != TY_ARRAY || p.types[ty].array_kind != A_GROW {
                diagnose(p, n_tok, "reusable applies to a var grow-only array pool");
            } else if p.types[ty].element >= 0 && check_size_class(p, p.types[ty].element, 0) != 0 {
                diagnose(p, n_tok, "reusable pool elements require fixed size");
            }
        }
        if init < 0 && ty >= 0 && check_size_class(p, ty, 0) != 0 {
            diagnose(p, n_tok, "nonfixed values must be constructed at declaration");
        }
    }
    c.scope = saved_scope; c.function_node = saved_function;
}
recursive fn check_compound_aggregate(p: Program&, c: Checker&, node: i64, type_id: i64) {
    let n = p.nodes[node];
    if check_bottom(p, n.left) {
        p.nodes[node] = Node { flags: F_CHECKED | F_DIVERGES | F_REACHABLE, kind: N_EXPR_STMT as i32, token: n.token,
                        next: n.next, left: n.left, type_id: TYPE_VOID as i32, scope: n.scope }; return;
    }
    // Only a whole variable is read as such; an element or field path is not.
    let root = check_place_root(p, n.left); let vi = check_variable_index(c, root);
    if vi >= 0 && p.nodes[n.left].kind == N_NAME && !c.variables[vi].assigned { diagnose(p, n.token, "compound assignment reads uninitialized storage"); }
    check_assignment_target(p, c, n.left, n.right, false);
    // Preserve the evaluated location and its old value before the RHS.
    // The final assignment uses ordinary aggregate arithmetic in both backends.
    var value_type = type_id;
    if (p.types[value_type].flags & TF_CONST) != 0 { var mutable = p.types[value_type]; mutable.flags &= ~TF_CONST; value_type = add_type(p, mutable); }
    let reference_type = check_type(p, TY_REF, value_type, 0, -1, 0);
    let target_name = operation_name(p, n.token, "__goose_update_target");
    let old_name = operation_name(p, n.token, "__goose_update_old");
    let target = new_node(p, N_VARIABLE, target_name); p.nodes[target].left = operation_type(p, reference_type, n.token) as i32;
    var address: i64 = n.left;
    if p.types[p.nodes[n.left].type_id].kind != TY_REF {
        address = new_node(p, N_UNARY, n.token); p.nodes[address].integer = T_BITAND; p.nodes[address].left = n.left;
        p.nodes[address].type_id = reference_type as i32; p.nodes[address].flags = F_CHECKED | F_SYNTHETIC;
        check_copy_roots(c, address, n.left); check_add_root(c, address, root, check_reference_kind(p, n.left));
    }
    p.nodes[target].right = address as i32;
    let old = new_node(p, N_VARIABLE, old_name); p.nodes[old].left = operation_type(p, value_type, n.token) as i32;
    p.nodes[old].right = operation_ident(p, target_name) as i32;
    var op = T_PLUS;
    if n.integer == T_MINUSEQ { op = T_MINUS; } else if n.integer == T_MULEQ { op = T_MUL; }
    else if n.integer == T_DIVEQ { op = T_DIV; } else if n.integer == T_MODEQ { op = T_MOD; }
    let binary = operation_binary(p, op, operation_ident(p, old_name), n.right, n.token);
    let assign = new_node(p, N_ASSIGN, n.token); p.nodes[assign].integer = T_ASSIGN;
    p.nodes[assign].left = operation_ident(p, target_name) as i32; p.nodes[assign].right = binary as i32;
    p.nodes[node] = Node { flags: F_SYNTHETIC | (n.flags & (F_REACHABLE | F_TAIL)), kind: N_BLOCK as i32, token: n.token,
                    next: n.next, scope: n.scope };
    append_child(p, node, target); append_child(p, node, old); append_child(p, node, assign);
    check_block(p, c, node, TYPE_VOID);
    if check_bottom(p, n.right) {
        p.nodes[assign] = Node { flags: F_CHECKED | F_DIVERGES | F_REACHABLE, kind: N_EXPR_STMT as i32, token: n.token,
                          left: n.right, type_id: TYPE_VOID as i32, scope: p.nodes[assign].scope };
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
        p.nodes[assign].left = target; p.nodes[assign].right = operation_ident(p, name) as i32; check_list_push(c, stores, assign);
        target = next;
    }
    p.nodes[node] = Node { flags: F_SYNTHETIC | (n.flags & (F_REACHABLE | F_TAIL)), kind: N_BLOCK as i32, token: n.token,
                    next: n.next, scope: n.scope };
    append_child(p, node, binding);
    for index in 0..stores.count { append_child(p, node, check_list_at(c, stores, index)); }
    check_block(p, c, node, TYPE_VOID);
}

recursive fn check_assignment(p: Program&, c: Checker&, node: i64) {
    let n_kind = p.nodes[node].kind;
    if n_kind == N_MULTI_ASSIGN { check_multi_assignment(p, c, node); return; }
    let n_left = p.nodes[node].left; let n_tok = p.nodes[node].token; let n_int = p.nodes[node].integer;
    var n_right: i64 = p.nodes[node].right;
    if n_right >= 0 && p.nodes[n_right].kind == N_NAME {
        let symbol = check_lookup_name(p, c, n_right);
        if symbol >= 0 && p.symbols[symbol].node >= 0 && (p.nodes[p.symbols[symbol].node].flags & F_RESULT_TEMP) != 0 {
            let ty = p.symbols[symbol].type_id;
            if ty >= 0 && p.types[ty].kind != TY_REF && p.types[ty].kind != TY_SLICE && check_size_class(p, ty, 0) > 0 {
                let name = operation_name(p, n_tok, "copy", false); let copy = new_node(p, N_CALL, n_tok);
                p.nodes[copy].left = operation_ident(p, name) as i32; p.nodes[copy].flags = F_SYNTHETIC;
                p.nodes[copy].symbol = check_builtin_symbol(p, name, 15, ty) as i32; append_child(p, copy, n_right);
                p.nodes[node].right = copy as i32; n_right = copy;
            }
        }
    }
    // A bare unassigned name is a legal assignment target, without reading it.
    let target_kind = p.nodes[n_left].kind; let target_tok = p.nodes[n_left].token; var ty = -1;
    if target_kind == N_NAME {
        let symbol = check_lookup_name(p, c, n_left);
        if symbol >= 0 {
            if !check_global_use(p, c, symbol, target_tok) { return; }
            check_environment_note(p, c, symbol); p.nodes[n_left].symbol = symbol as i32; ty = p.symbols[symbol].type_id; p.nodes[n_left].type_id = ty as i32;
        }
        else { diagnose(p, target_tok, "assignment target is unknown"); }
    } else { c.path_base = true; ty = check_expression(p, c, n_left, -1); }
    if ty < 0 { return; }
    let rebind = n_int == T_DOTASSIGN;
    // The binding keeps the kind it carried before evaluating the RHS.
    var prior_pool = 0;
    if rebind && target_kind == N_NAME && p.types[ty].kind == TY_REF { prior_pool = check_pool_flags(p, c, n_left); }
    if p.types[ty].kind == TY_REF && !rebind {
        // Writing through a reference reads the binding before its RHS runs.
        if target_kind == N_NAME { ty = check_expression(p, c, n_left, -1); }
        if ty >= 0 && (p.types[ty].flags & TF_OPTIONAL) != 0 { diagnose(p, n_tok, "optional reference must be narrowed before writing through it"); }
    }
    if ty < 0 { return; }
    var value_type = ty;
    if p.types[ty].kind == TY_REF && !rebind { value_type = p.types[ty].element; }
    // Upstream AssignableClassCheck: its fields are assigned instead.
    if root_struct_type(p, value_type) && n_int == T_ASSIGN { diagnose(p, n_tok, "a root owner cannot be assigned as a whole; assign its fields instead"); }
    if rebind && p.types[ty].kind != TY_REF && p.types[ty].kind != TY_SLICE && target_kind != N_INDEX && target_kind != N_MEMBER {
        diagnose(p, n_tok, ".= requires a reference or slice binding");
    }
    if n_right >= 0 && (n_int == T_PLUSEQ || n_int == T_MINUSEQ || n_int == T_MULEQ || n_int == T_DIVEQ || n_int == T_MODEQ) &&
       (p.types[value_type].kind == TY_ARRAY || p.types[value_type].kind == TY_STRUCT) && operation_numeric_class(p, value_type) > 0 {
        check_compound_aggregate(p, c, node, value_type); return;
    }
    if n_right >= 0 {
        if n_int == T_ASSIGN && p.types[value_type].kind == TY_ARRAY && p.types[value_type].element < 0 {
            let source = check_array_receiver(p, c, n_right, false);
            if source >= 0 { check_complete_pending(p, c, n_left, value_type, p.types[source].element, n_tok); }
        }
        if n_int == T_SHLEQ || n_int == T_SHREQ {
            let count_type = check_numeric_value_type(p, check_value(p, c, n_right, -1));
            if count_type < 0 || p.types[count_type].kind != TY_INT { diagnose(p, n_tok, "shift count must be an integer"); }
        } else {
            var context = value_type;
            if prior_pool != 0 && (p.types[context].flags & F_REUSABLE) != 0 {
                // Expected types guide literals and generic results, but do not
                // supply the source pool proof for a rebinding.
                var unqualified = p.types[context]; unqualified.flags &= ~(F_REUSABLE | F_REUSABLE_SLICES);
                context = add_type(p, unqualified);
            }
            check_value(p, c, n_right, context);
        }
        if prior_pool != 0 && prior_pool != check_pool_flags(p, c, n_right, true) {
            diagnose(p, n_tok, "rebinding a pool reference requires another pool of the same kind");
        }
        if n_int == T_ASSIGN || n_int == T_DOTASSIGN { check_slot_value(p, c, n_right, value_type); }
    }
    else if n_int != T_INC && n_int != T_DEC { diagnose(p, n_tok, "assignment has no right operand"); }
    if n_int != T_ASSIGN && n_int != T_DOTASSIGN {
        if p.types[value_type].kind == TY_INT && p.types[value_type].index_type >= 0 { diagnose(p, n_tok, "arithmetic computes a plain integer and cannot update index or bound storage"); }
        if !check_numeric(check_numeric_value_type(p, value_type)) { diagnose(p, n_tok, "compound assignment requires numeric storage"); }
        let symbol = check_place_root(p, n_left); let vi = check_variable_index(c, symbol);
        if vi >= 0 && p.nodes[n_left].kind == N_NAME && !c.variables[vi].assigned { diagnose(p, n_tok, "compound assignment reads uninitialized storage"); }
    }
    check_assignment_target(p, c, n_left, n_right, rebind);
    if n_right >= 0 && check_contains_refs(p, value_type, 0) {
        check_store_roots(p, c, check_place_root(p, n_left), n_right);
    }
}
fn check_assignment_target(p: Program&, c: Checker&, target: i64, value: i64, rebind: bool) {
    if !check_addressable(p, target) { diagnose(p, p.nodes[target].token, "assignment requires addressable storage"); return; }
    let n_kind = p.nodes[target].kind; let n_ty = p.nodes[target].type_id;
    let n_tok = p.nodes[target].token; let n_sym = p.nodes[target].symbol;
    let root = check_place_root(p, target);
    let through_ref = n_ty >= 0 && p.types[n_ty].kind == TY_REF && !rebind;
    let binding_update = n_kind == N_NAME && n_ty >= 0 && (rebind || p.types[n_ty].kind == TY_SLICE);
    let whole_binding = n_kind == N_NAME && !through_ref;
    if !binding_update && !whole_binding && check_readonly(p, c, target, !through_ref) { diagnose(p, n_tok, "assignment cannot change read-only storage"); }
    if binding_update && root >= 0 && p.symbols[root].node >= 0 && (p.nodes[p.symbols[root].node].flags & F_CONST) != 0 {
        diagnose(p, n_tok, "assignment cannot change a const binding");
    }
    if n_kind == N_NAME && root >= 0 && !through_ref {
        let s_flags = p.symbols[root].flags; let s_ty = p.symbols[root].type_id; let vi = check_variable_index(c, root);
        if (s_flags & S_MUTABLE) == 0 && (vi < 0 || c.variables[vi].maybeassigned) {
            var msg: u8[>..] = [];
            msg.append("let binding cannot be assigned again: `"); msg.append(token_text(p, n_tok)); msg.push('`');
            let decl_tok = p.symbols[root].name_token;
            if decl_tok >= 0 && decl_tok < p.tokens.len {
                msg.append("\n  note: `"); msg.append(token_text(p, decl_tok)); msg.append("` declared at ");
                format_token_location(p, decl_tok, msg);
            }
            msg.append("\n  help: declare `"); msg.append(token_text(p, n_tok)); msg.append("` with `var` to allow reassignment");
            diagnose(p, n_tok, msg);
        }
        check_note_effect(c, root, 6);
        if vi >= 0 {
            check_set_assigned(c, vi, true, true);
            if rebind { check_assign_narrowing(p, c, root, value); check_note_effect(c, root, 5); }
        }
        if value >= 0 && s_ty >= 0 && check_contains_refs(p, s_ty, 0) { check_store_roots(p, c, root, value); }
    }
    if n_kind == N_MEMBER && n_sym >= 0 && n_sym < p.nodes.len && (p.nodes[n_sym].flags & F_CONST) != 0 && !through_ref {
        diagnose(p, n_tok, "let field cannot be assigned as a whole");
    }
    if root >= 0 {
        check_capture(p, c, root); check_note_effect(c, root, 0);
        let ty = p.symbols[root].type_id;
        if ty >= 0 && check_size_class(p, ty, 0) == 2 && n_kind == N_NAME && !through_ref {
            check_mutation_views(p, c, target, true);
        }
    }
}
// The speculative checker accepts fixed, reference-free bodies. A failed
// check leaves only scratch entries in its slice. Calls are dependencies;
// the main thread validates the entire dependency graph before replay.
let CHECK_BODY_FOR_SOURCE: i64 = -3;
let CHECK_BODY_FALLBACK: i64 = 0;
let CHECK_BODY_PENDING: i64 = 1;
let CHECK_BODY_VISITING: i64 = 2;
let CHECK_BODY_READY: i64 = 3;
let CHECK_BODY_SCOPE: i64 = 1;
let CHECK_BODY_LOCAL: i64 = 2;
let CHECK_BODY_CALL: i64 = 3;
let CHECK_BODY_RETURN: i64 = 4;
// Private patch bit, removed before writing Node.flags.
let CHECK_BODY_NONCONSTANT: i64 = 1 << 62;
let CHECK_BODY_PATCHED: i64 = 1 << 61;

struct CheckBodyPatch {
    flags: i64 = 0, type_id: i32 = -1, scope: i32 = -1, symbol: i32 = -1,
    aux: i32 = -1, last: i32 = -1, proof: i32 = -2,
}
struct CheckBodyEvent {
    kind: i32, node: i32, scope: i32, value: i32 = -1, mapped: i32 = -1,
}
fn gp_grow_check_patches(arr: CheckBodyPatch[>..]&, new_len: i64) {
    while arr.len < new_len { arr.push(CheckBodyPatch {}); }
}
fn gp_grow_check_events(arr: CheckBodyEvent[>..]&, new_len: i64) {
    while arr.len < new_len { arr.push(CheckBodyEvent { kind: 0, node: 0, scope: -1 }); }
}

// A frame's slots are contiguous only when it declares them all before
// calling another function. Return nodes still follow the DFS event order.
struct CheckBodyInstall {
    function_node: i64 = -1, root_scope: i64 = -1, root_depth: i64 = 0,
    scope_base: i64 = 0, symbol_base: i64 = 0, variable_base: i64 = 0,
    flow_base: i64 = 0, first_slot: i64 = 0, previous: i64 = -1,
}
struct CheckBodySlots { scope: i64, symbol: i64, variable: i64, flow: i64, node: i64 }
struct CheckInstallTables {
    scopes: CheckScope[:], symbols: Symbol[:], variables: CheckVariable[:], variable_lookup: i64[:],
}
fn gp_grow_check_scopes(arr: CheckScope[>..]&, new_len: i64) {
    while arr.len < new_len { arr.push(CheckScope { parent: -1, function_node: -1 }); }
}
fn gp_grow_check_symbols(arr: Symbol[>..]&, new_len: i64) {
    while arr.len < new_len { arr.push(Symbol {}); }
}
fn gp_grow_check_variables(arr: CheckVariable[>..]&, new_len: i64) {
    while arr.len < new_len { arr.push(CheckVariable { symbol: -1 }); }
}
fn gp_grow_check_variable_lookup(arr: i64[>..]&, new_len: i64) {
    while arr.len < new_len { arr.push(-1); }
}

fn gp_grow_check_proofs(arr: i64[>..]&, new_len: i64) {
    while arr.len < new_len { arr.push(-2); }
}

struct CheckBatchOut {
    function_node: i64 = -1, base: i64 = 0,
    patches: CheckBodyPatch[:], events: CheckBodyEvent[:],
    apply_nodes: Node[:], apply_proofs: i64[:],
    patch_count: i64 = 0, proof_count: i64 = 0, event_count: i64 = 0,
    first_step: i64 = -1, last_step: i64 = -1, seen_call: bool = false,
    scope_count: i64 = 0, local_count: i64 = 0, installable: bool = true,
    status: i64 = 0, returns: bool = false,
    validation_end: i64 = 0, checked_checkfree: bool = false,
    tables: CheckInstallTables, batches: CheckBodyBatch[:],
}
struct CheckBodyBatch {
    base: i64, patch_at: i64, event_at: i64,
    function_node: i64, patch_cap: i64, event_cap: i64,
    patch_count: i64 = 0, proof_count: i64 = 0, event_count: i64 = 0,
    first_step: i64 = -1, scope_count: i64 = 0, local_count: i64 = 0, installable: bool = false,
    status: i64 = 0, returns: bool = false, install: CheckBodyInstall = CheckBodyInstall {},
}
struct CheckBatchCtx {
    program: const Program&, mode: i64 = 0, elem_bad: const bool[:],
    nodes: const Node[:], types: const Type[:], symbols: const Symbol[:],
    tokens: const Token[:], text: const u8[:],
    scopes: const CheckScope[:], names: const i32[:],
    link_scopes: const i32[:], hashes: const i32[:],
    functions: const i32[:], fixed_arrays: const i32[:], value_types: const bool[:],
    install_batches: const CheckBodyBatch[:], install_pending: const i32[:],
    install_proof_start: i64 = -1,
}
struct CheckBodyState {
    scope: i64 = -1, local_count: i64 = 0,
    local_names: i64[64] = [0; 64], locals: i32[64] = [0; 64],
    depth: i64 = 0, reachable: bool = true, returns: bool = false,
}

inline fn check_body_scalar(ty: i64) -> bool {
    return ty == TYPE_I64 || ty == TYPE_BOOL || ty == TYPE_F64;
}
inline fn check_body_patchable(out: const CheckBatchOut&, node: i64) -> bool {
    return node >= out.base && node - out.base < out.patches.len;
}
inline fn check_body_patch(out: CheckBatchOut&, node: i64, patch: CheckBodyPatch) {
    let index = node - out.base;
    out.patches[index] = patch;
    out.patches[index].flags |= CHECK_BODY_PATCHED;
    if index >= out.patch_count { out.patch_count = index + 1; }
    if patch.proof != -2 && index >= out.proof_count { out.proof_count = index + 1; }
}
fn check_body_event(out: CheckBatchOut&, kind: i64, node: i64, scope: i64, value: i64 = -1) -> i64 {
    let at = out.event_count;
    if at >= out.events.len { return -1; }
    out.events[at] = CheckBodyEvent { kind: kind as i32, node: node as i32, scope: scope as i32, value: value as i32 };
    if kind == CHECK_BODY_CALL || kind == CHECK_BODY_RETURN {
        if out.last_step < 0 { out.first_step = at; }
        else { out.events[out.last_step].mapped = at as i32; }
        out.last_step = at;
        if kind == CHECK_BODY_CALL { out.seen_call = true; }
    } else {
        if out.seen_call { out.installable = false; }
        if kind == CHECK_BODY_SCOPE { out.scope_count += 1; }
        else { out.local_count += 1; }
    }
    out.event_count = at + 1;
    return at;
}
inline fn check_body_same(ctx: const CheckBatchCtx&, a: i64, b: i64) -> bool {
    if a == b { return true; }
    let x: const Token& = ctx.tokens[a]; let y: const Token& = ctx.tokens[b];
    if x.kind == T_IDENT && y.kind == T_IDENT && x.text_start > 0 && y.text_start > 0 {
        return x.text_start == y.text_start;
    }
    if x.end - x.start != y.end - y.start { return false; }
    for i in 0..x.end - x.start { if ctx.text[x.start + i] != ctx.text[y.start + i] { return false; } }
    return true;
}
// The supported names are unqualified interned identifiers. Locals have
// their own declaration scopes, so each entry shadows the previous one.
fn check_body_name(ctx: const CheckBatchCtx&, out: const CheckBatchOut&, state: const CheckBodyState&, token: i64, role: i64) -> i64 {
    let t: const Token& = ctx.tokens[token];
    if t.kind != T_IDENT || t.text_start <= 0 { return -1; }
    if role != S_TYPE {
        var i = state.local_count;
        while i > 0 {
            i -= 1;
            if state.local_names[i] == t.text_start { return -(state.locals[i] as i64) - 10; }
        }
    }
    let hash = t.integer; let h32 = hash as! i32;
    var scope: i64 = ctx.nodes[out.function_node].scope;
    while scope >= 0 {
        let row: const CheckScope& = ctx.scopes[scope];
        let count = row.decl_count as i64;
        if count <= 4 {
            var i = count;
            while i > 0 {
                i -= 1;
                if row.small_hashes[i] != h32 { continue; }
                let id = row.small_decls[i] as i64;
                let s: const Symbol& = ctx.symbols[id];
                if check_body_same(ctx, s.name_token, token) && (role == 0 || (s.flags & role) != 0 ||
                    role == S_FUNCTION && (s.flags & S_PARAMETER) != 0) { return id; }
            }
        } else {
            var h = (hash as! u64) * 11400714819323198485 ^ (scope as! u64) * 14029467366897019727;
            h ^= h >> 31;
            let bucket = (h & ((ctx.names.len - 1) as! u64)) as i64;
            var id = ctx.names[bucket] as i64;
            while id >= 0 {
                let s: const Symbol& = ctx.symbols[id];
                if ctx.link_scopes[id] as i64 == scope && ctx.hashes[id] == h32 &&
                    check_body_same(ctx, s.name_token, token) && (role == 0 || (s.flags & role) != 0 ||
                    role == S_FUNCTION && (s.flags & S_PARAMETER) != 0) { return id; }
                id = s.name_next;
            }
        }
        scope = row.parent;
    }
    return -1;
}
inline fn check_body_simple_name(n: const Node&) -> bool {
    return n.aux == 1 && n.left < 0 && n.first < 0 && n.expansion_binding == -1 && n.symbol < 0;
}
recursive fn check_body_type(ctx: const CheckBatchCtx&, out: CheckBatchOut&, state: const CheckBodyState&, id: i64) -> i64 {
    if !check_body_patchable(out, id) { return -1; }
    let n: const Node& = ctx.nodes[id];
    if n.flags != 0 || n.type_id >= 0 { return -1; }
    var ty = -1; var symbol = -1;
    if n.kind == N_TYPE_NAME && n.left < 0 && n.first < 0 && n.third < 0 && n.aux <= 1 && n.expansion_binding == -1 {
        let kind = ctx.tokens[n.token].kind;
        if kind == T_TVARINT { return -1; }
        ty = check_primitive_token(kind);
        if ty < 0 && check_body_simple_name(n) {
            symbol = check_body_name(ctx, out, state, n.token, S_TYPE);
            if symbol < 0 { return -1; }
            let s: const Symbol& = ctx.symbols[symbol];
            if s.node < 0 || ctx.nodes[s.node].kind != N_STRUCT || ctx.nodes[s.node].third >= 0 { return -1; }
            ty = s.type_id;
        }
    } else if n.kind == N_TYPE_ARRAY && n.integer == A_FIXED && n.third < 0 && n.right >= 0 {
        // The bound is resolved as a constant without checking it as an expression.
        let size: const Node& = ctx.nodes[n.right];
        if size.kind != N_INTEGER || (size.flags & F_UNSIGNED) != 0 || size.integer < 0 { return -1; }
        let element = check_body_type(ctx, out, state, n.left);
        if element < 0 { return -1; }
        for candidate in ctx.fixed_arrays {
            let t: const Type& = ctx.types[candidate as i64];
            if t.element == element && t.count == size.integer { ty = candidate as i64; break; }
        }
    }
    if ty < 0 || !ctx.value_types[ty] { return -1; }
    check_body_patch(out, id, CheckBodyPatch { type_id: ty as i32, symbol: symbol as i32 });
    return ty;
}
fn check_body_local(ctx: const CheckBatchCtx&, out: CheckBatchOut&, state: CheckBodyState&, id: i64, ty: i64, proof: i32, flags: i64) -> bool {
    if state.local_count == state.locals.len || !check_body_patchable(out, id) { return false; }
    let t: const Token& = ctx.tokens[ctx.nodes[id].token];
    if t.kind != T_IDENT || t.text_start <= 0 { return false; }
    let event = check_body_event(out, CHECK_BODY_LOCAL, id, state.scope, proof as i64);
    if event < 0 { return false; }
    state.local_names[state.local_count] = t.text_start;
    state.locals[state.local_count] = event as i32;
    state.local_count += 1;
    check_body_patch(out, id, CheckBodyPatch { flags: flags, type_id: ty as i32, symbol: (-event - 10) as i32 });
    return true;
}
fn check_body_binding(ctx: const CheckBatchCtx&, out: const CheckBatchOut&, symbol: i64, patch: CheckBodyPatch&) -> bool {
    patch.symbol = symbol as i32;
    patch.flags |= CHECK_BODY_NONCONSTANT;
    if symbol <= -10 {
        let event: const CheckBodyEvent& = out.events[-symbol - 10];
        let decl = event.node as i64;
        let n: const Node& = ctx.nodes[decl];
        patch.type_id = out.patches[decl - out.base].type_id;
        if event.value >= -1 || event.value <= -10 { patch.proof = symbol as i32; }
        if n.kind == N_VARIABLE && (n.flags & F_VAR) == 0 { patch.flags &= ~CHECK_BODY_NONCONSTANT; patch.flags |= out.patches[n.right - out.base].flags & CHECK_BODY_NONCONSTANT; }
        return true;
    }
    if symbol < 0 { return false; }
    let s: const Symbol& = ctx.symbols[symbol];
    if s.owner != out.function_node || (s.flags & (S_PARAMETER | S_LITERAL)) != S_PARAMETER ||
        s.type_id < 0 || !ctx.value_types[s.type_id] { return false; }
    patch.type_id = s.type_id as i32;
    return true;
}
fn check_body_write_root(ctx: const CheckBatchCtx&, out: const CheckBatchOut&, id: i64) -> i64 {
    var at = id;
    loop {
        if !check_body_patchable(out, at) { return -1; }
        let n: const Node& = ctx.nodes[at];
        if n.kind == N_NAME {
            let symbol = out.patches[at - out.base].symbol as i64;
            if symbol > -10 { return -1; }
            let decl = out.events[-symbol - 10].node as i64;
            if (ctx.nodes[decl].flags & F_VAR) == 0 { return -1; }
            return symbol;
        }
        if n.kind != N_MEMBER && n.kind != N_INDEX { return -1; }
        at = n.left;
    }
}
inline fn check_body_comparison(op: i64) -> bool {
    return op == T_EQ || op == T_NEQ || op == T_LT || op == T_LTEQ || op == T_GT || op == T_GTEQ;
}
recursive fn check_body_block(ctx: const CheckBatchCtx&, out: CheckBatchOut&, state: CheckBodyState&, node: i64, expected: i64, patch: CheckBodyPatch&) -> i64 {
    let n: const Node& = ctx.nodes[node];
    if (n.flags & F_TAIL) != 0 { return -1; }
    let saved = state.scope; let locals = state.local_count;
    state.scope = check_body_event(out, CHECK_BODY_SCOPE, node, saved);
    if state.scope < 0 { return -1; }
    patch.scope = state.scope as i32;
    var child = n.first;
    while child >= 0 {
        if !state.reachable { return -1; }
        let item: const Node& = ctx.nodes[child];
        if item.kind == N_VARIABLE {
            if (item.flags & ~F_VAR) != 0 || item.first >= 0 || item.right < 0 || ctx.nodes[item.right].next >= 0 { return -1; }
            state.scope = check_body_event(out, CHECK_BODY_SCOPE, child, state.scope, 1);
            if state.scope < 0 { return -1; }
            var annotation = -1;
            if item.left >= 0 {
                annotation = check_body_type(ctx, out, state, item.left);
                if annotation < 0 { return -1; }
            }
            let ty = check_body_expr(ctx, out, state, item.right, annotation);
            if ty <= TYPE_VOID { return -1; }
            var proof: i32 = -2;
            if ty == TYPE_I64 && (item.flags & F_VAR) == 0 { proof = out.patches[item.right - out.base].proof; }
            if !check_body_local(ctx, out, state, child, ty, proof, F_CHECKED) { return -1; }
        } else {
            if check_body_expr(ctx, out, state, child, TYPE_VOID) < 0 { return -1; }
        }
        child = item.next;
    }
    state.scope = saved; state.local_count = locals;
    if state.reachable && expected > TYPE_VOID { return -1; }
    return TYPE_VOID;
}
recursive fn check_body_call(ctx: const CheckBatchCtx&, out: CheckBatchOut&, state: CheckBodyState&, n: const Node&, patch: CheckBodyPatch&) -> i64 {
    if n.third >= 0 || !check_body_patchable(out, n.left) { return -1; }
    let name: const Node& = ctx.nodes[n.left];
    if name.kind != N_NAME || !check_body_simple_name(name) { return -1; }
    let symbol = check_body_name(ctx, out, state, name.token, S_FUNCTION);
    if symbol < 0 { return -1; }
    let s: const Symbol& = ctx.symbols[symbol];
    if (s.flags & S_FUNCTION) == 0 || s.next >= 0 || s.node < 0 || ctx.functions[symbol] == -1 { return -1; }
    var formal = ctx.nodes[s.node].first; var actual = n.first; var last = -1;
    while actual >= 0 && formal >= 0 {
        let ty = check_body_expr(ctx, out, state, actual, -1);
        if !check_body_scalar(ty) || ty != ctx.nodes[formal].type_id { return -1; }
        last = actual; actual = ctx.nodes[actual].next; formal = ctx.nodes[formal].next;
    }
    if formal >= 0 || actual >= 0 || check_body_event(out, CHECK_BODY_CALL, s.node, symbol, n.token) < 0 { return -1; }
    check_body_patch(out, n.left, CheckBodyPatch { symbol: symbol as i32 });
    patch.symbol = symbol as i32; patch.last = last as i32; patch.flags |= CHECK_BODY_NONCONSTANT;
    return ctx.types[s.type_id].element;
}
recursive fn check_body_match(ctx: const CheckBatchCtx&, out: CheckBatchOut&, state: CheckBodyState&, n: const Node&, expected: i64, patch: CheckBodyPatch&) -> i64 {
    if expected != TYPE_I64 || check_body_expr(ctx, out, state, n.left, TYPE_I64) != TYPE_I64 { return -1; }
    var patterns: i64[32] = [0; 32]; var count = 0; var wildcard = false; var nonconstant = false;
    let saved = state.scope;
    var arm = n.first;
    while arm >= 0 {
        if wildcard || !check_body_patchable(out, arm) { return -1; }
        let a: const Node& = ctx.nodes[arm];
        if a.kind != N_ARM || a.third >= 0 { return -1; }
        let pattern: const Node& = ctx.nodes[a.left];
        if pattern.left >= 0 { return -1; }
        wildcard = (pattern.flags & F_DEFAULT) != 0;
        if !wildcard {
            let item = pattern.first;
            if count == patterns.len || !check_body_patchable(out, item) { return -1; }
            let literal: const Node& = ctx.nodes[item];
            if literal.kind != N_INTEGER || literal.next >= 0 || (literal.flags & F_UNSIGNED) != 0 { return -1; }
            for i in 0..count { if patterns[i] == literal.integer { return -1; } }
            patterns[count] = literal.integer; count += 1;
            check_body_patch(out, item, CheckBodyPatch { flags: F_CHECKED, type_id: TYPE_I64 as i32 });
        }
        state.scope = check_body_event(out, CHECK_BODY_SCOPE, arm, saved);
        if state.scope < 0 { return -1; }
        check_body_patch(out, arm, CheckBodyPatch { scope: state.scope as i32 });
        if check_body_expr(ctx, out, state, a.right, TYPE_I64) != TYPE_I64 || !state.reachable { return -1; }
        nonconstant = nonconstant || (out.patches[a.right - out.base].flags & CHECK_BODY_NONCONSTANT) != 0;
        arm = a.next;
    }
    state.scope = saved;
    // The integer-constant match path also computes a width and a proof.
    if !wildcard || !nonconstant { return -1; }
    patch.aux = TYPE_I64 as i32; patch.flags |= CHECK_BODY_NONCONSTANT;
    return TYPE_I64;
}
recursive fn check_body_aggregate(ctx: const CheckBatchCtx&, out: CheckBatchOut&, state: CheckBodyState&, n: const Node&, expected: i64) -> i64 {
    var item = n.first;
    if n.kind == N_RECORD {
        if n.right >= 0 || (n.flags & F_DEFAULT) != 0 { return -1; }
        let ty = check_body_type(ctx, out, state, n.left);
        if ty < 0 || ctx.types[ty].kind != TY_STRUCT { return -1; }
        var field = ctx.types[ty].first; var count = 0;
        while field >= 0 && item >= 0 {
            if !check_body_patchable(out, item) { return -1; }
            let init: const Node& = ctx.nodes[item]; let f: const Node& = ctx.nodes[field];
            if init.kind != N_BINDING || init.left >= 0 || init.aux >= 0 || init.flags != 0 ||
                init.token >= 0 && !check_body_same(ctx, init.token, f.token) { return -1; }
            if check_body_expr(ctx, out, state, init.right, f.type_id) != f.type_id { return -1; }
            check_body_patch(out, item, CheckBodyPatch { type_id: f.type_id, symbol: field as i32 });
            field = f.next; item = init.next; count += 1;
        }
        if count == 0 || field >= 0 || item >= 0 { return -1; }
        return ty;
    }
    if expected < 0 || ctx.types[expected].kind != TY_ARRAY || n.right >= 0 || n.third >= 0 { return -1; }
    let t: const Type& = ctx.types[expected];
    var count = 0;
    while item >= 0 {
        if check_body_expr(ctx, out, state, item, t.element) != t.element { return -1; }
        item = ctx.nodes[item].next; count += 1;
    }
    if count != t.count { return -1; }
    return expected;
}
recursive fn check_body_expr(ctx: const CheckBatchCtx&, out: CheckBatchOut&, state: CheckBodyState&, id: i64, expected: i64) -> i64 {
    if state.depth >= 128 || !check_body_patchable(out, id) { return -1; }
    // An error aborts the entire body, so only success restores the depth.
    state.depth += 1;
    let n: const Node& = ctx.nodes[id]; let kind = n.kind;
    if n.type_id >= 0 || n.symbol >= 0 || (n.flags & (F_TAIL | F_EARLY | F_CHECKED | F_SYNTHETIC | F_UNSIGNED | F_NONLOCAL)) != 0 { return -1; }
    var patch = CheckBodyPatch { flags: F_REACHABLE | F_CHECKED, scope: state.scope as i32 };
    var ty = -1;
    if kind == N_INTEGER { ty = TYPE_I64; if n.integer >= 0 { patch.proof = -1; } }
    else if kind == N_BOOL { ty = TYPE_BOOL; }
    else if kind == N_FLOAT { ty = TYPE_F64; }
    else if kind == N_NAME {
        if !check_body_simple_name(n) { return -1; }
        let symbol = check_body_name(ctx, out, state, n.token, 0);
        if !check_body_binding(ctx, out, symbol, patch) { return -1; }
        ty = patch.type_id as i64;
    } else if kind == N_BINARY {
        let l = check_body_expr(ctx, out, state, n.left, -1);
        if !check_body_scalar(l) || check_body_expr(ctx, out, state, n.right, -1) != l { return -1; }
        let op = n.integer; let comparison = check_body_comparison(op);
        if l == TYPE_BOOL {
            if op != T_ANDAND && op != T_OROR { return -1; }
            ty = TYPE_BOOL;
        } else {
            if !comparison && op != T_PLUS && op != T_MINUS && op != T_MUL && op != T_DIV && op != T_MOD &&
                !(l == TYPE_I64 && (op == T_BITAND || op == T_BITOR || op == T_XOR)) { return -1; }
            patch.aux = l as i32; ty = l;
            if comparison { ty = TYPE_BOOL; }
        }
        patch.flags |= (out.patches[n.left - out.base].flags | out.patches[n.right - out.base].flags) & CHECK_BODY_NONCONSTANT;
    } else if kind == N_UNARY {
        ty = check_body_expr(ctx, out, state, n.left, -1);
        if !(n.integer == T_MINUS && (ty == TYPE_I64 || ty == TYPE_F64) || n.integer == T_NOT && ty == TYPE_BOOL) { return -1; }
        patch.flags |= out.patches[n.left - out.base].flags & CHECK_BODY_NONCONSTANT;
    } else if kind == N_MEMBER {
        if n.aux >= 0 { return -1; }
        let source = check_body_expr(ctx, out, state, n.left, -1);
        if source < 0 || ctx.types[source].kind != TY_STRUCT { return -1; }
        var field = ctx.types[source].first;
        while field >= 0 && !check_body_same(ctx, ctx.nodes[field].token, n.token) { field = ctx.nodes[field].next; }
        if field < 0 || ctx.nodes[field].type_id < 0 { return -1; }
        ty = ctx.nodes[field].type_id; patch.symbol = field as i32;
        // Constant evaluation treats .len and .cap specially.
        patch.flags |= CHECK_BODY_NONCONSTANT;
        let token: const Token& = ctx.tokens[n.token];
        if token.end - token.start == 3 { patch.flags &= ~CHECK_BODY_NONCONSTANT; }
    } else if kind == N_INDEX {
        let source = check_body_expr(ctx, out, state, n.left, -1);
        if source < 0 || ctx.types[source].kind != TY_ARRAY || check_body_expr(ctx, out, state, n.right, TYPE_I64) != TYPE_I64 { return -1; }
        let index: const Node& = ctx.nodes[n.right];
        if index.kind == N_INTEGER {
            if index.integer < 0 || index.integer >= ctx.types[source].count { return -1; }
            patch.flags |= F_BOUNDS_PROVEN;
        } else if (out.patches[n.right - out.base].flags & CHECK_BODY_NONCONSTANT) == 0 { return -1; }
        ty = ctx.types[source].element; patch.flags |= CHECK_BODY_NONCONSTANT;
    } else if kind == N_ARRAY || kind == N_RECORD {
        ty = check_body_aggregate(ctx, out, state, n, expected);
    } else if kind == N_CALL {
        ty = check_body_call(ctx, out, state, n, patch);
    } else if kind == N_MATCH {
        ty = check_body_match(ctx, out, state, n, expected, patch);
    } else if kind == N_BLOCK {
        ty = check_body_block(ctx, out, state, id, expected, patch);
    } else if kind == N_IF && expected == TYPE_VOID {
        if check_body_expr(ctx, out, state, n.left, TYPE_BOOL) != TYPE_BOOL ||
            check_body_expr(ctx, out, state, n.right, TYPE_VOID) < 0 { return -1; }
        let then_reaches = state.reachable;
        state.reachable = true;
        if n.third >= 0 && check_body_expr(ctx, out, state, n.third, TYPE_VOID) < 0 { return -1; }
        state.reachable = state.reachable || then_reaches; ty = TYPE_VOID;
    } else if (kind == N_WHILE || kind == N_FOR) && expected == TYPE_VOID {
        let saved = state.scope; let locals = state.local_count;
        state.scope = check_body_event(out, CHECK_BODY_SCOPE, id, saved);
        if state.scope < 0 { return -1; }
        patch.scope = state.scope as i32;
        if kind == N_WHILE {
            if check_body_expr(ctx, out, state, n.left, TYPE_BOOL) != TYPE_BOOL ||
                (out.patches[n.left - out.base].flags & CHECK_BODY_NONCONSTANT) == 0 { return -1; }
        } else {
            if check_body_expr(ctx, out, state, n.left, CHECK_BODY_FOR_SOURCE) != TYPE_I64 || n.first < 0 { return -1; }
            let binding: const Node& = ctx.nodes[n.first];
            if binding.kind != N_BINDING || binding.flags != 0 || binding.left >= 0 || binding.next >= 0 ||
                !check_body_local(ctx, out, state, n.first, TYPE_I64, -2, 0) { return -1; }
        }
        if check_body_expr(ctx, out, state, n.right, TYPE_VOID) < 0 { return -1; }
        state.scope = saved; state.local_count = locals; state.reachable = true; ty = TYPE_VOID;
    } else if kind == N_RANGE && expected == CHECK_BODY_FOR_SOURCE {
        if check_body_expr(ctx, out, state, n.left, TYPE_I64) != TYPE_I64 ||
            check_body_expr(ctx, out, state, n.right, TYPE_I64) != TYPE_I64 { return -1; }
        ty = TYPE_I64;
    } else if kind == N_CAST {
        let target = check_body_type(ctx, out, state, n.right);
        let source = check_body_expr(ctx, out, state, n.left, -1);
        if !check_body_scalar(target) || !check_body_scalar(source) ||
            target == TYPE_BOOL && source == TYPE_F64 || target == TYPE_F64 && source == TYPE_BOOL { return -1; }
        ty = target; patch.flags |= CHECK_BODY_NONCONSTANT;
    } else if kind == N_ASSIGN && n.integer == T_ASSIGN {
        let lhs: const Node& = ctx.nodes[n.left];
        var dest = -1;
        if lhs.kind == N_NAME {
            if !check_body_patchable(out, n.left) || !check_body_simple_name(lhs) { return -1; }
            var place = CheckBodyPatch {};
            if !check_body_binding(ctx, out, check_body_name(ctx, out, state, lhs.token, 0), place) { return -1; }
            dest = place.type_id as i64; place.proof = -2;
            check_body_patch(out, n.left, place);
        } else { dest = check_body_expr(ctx, out, state, n.left, -1); }
        if !check_body_scalar(dest) { return -1; }
        let symbol = check_body_write_root(ctx, out, n.left);
        if symbol > -10 || check_body_expr(ctx, out, state, n.right, dest) != dest { return -1; }
        // These writes touch initialized locals owned by this function.
        // They do not contribute to any caller's flow or effect summary.
        ty = TYPE_VOID;
    } else if kind == N_RETURN {
        if n.left >= 0 { return -1; }
        let result = ctx.types[ctx.nodes[out.function_node].type_id].element;
        if n.first >= 0 {
            if result == TYPE_VOID || ctx.nodes[n.first].next >= 0 || check_body_expr(ctx, out, state, n.first, result) != result ||
                check_body_event(out, CHECK_BODY_RETURN, n.first, state.scope, result) < 0 { return -1; }
        } else if result != TYPE_VOID { return -1; }
        patch.symbol = ctx.nodes[out.function_node].symbol;
        state.returns = true; state.reachable = false; ty = TYPE_VOID;
    } else if kind == N_EMPTY { ty = TYPE_VOID; }
    if ty == -1 || expected > TYPE_VOID && ty != expected { return -1; }
    state.depth -= 1;
    if !state.reachable { patch.flags |= F_DIVERGES; }
    // A terminal block has no raw type in the serial checker.
    if kind != N_BLOCK || state.reachable { patch.type_id = ty as i32; }
    check_body_patch(out, id, patch);
    return ty;
}

// Mirror the node order of check_validate_program and reuse its validators.
// The worker's Program shares input tables but owns its diagnostic sink.
// Extern normalization is the only AST write in these validators.
fn check_validate_program_nodes(p: Program&, first: i64, end: i64, elem_bad: const bool[:]) -> bool {
    for node in first..end {
        if p.diagnostics.len != 0 { return false; }
        let n: const Node& = p.nodes[node];
        let kind = n.kind;
        let flags = n.flags;
        let tid = n.type_id;
        let tok = n.token;
        if kind == N_FUNCTION || kind == N_FUNCTION_VALUE || kind == N_TYPE_FN {
            if kind == N_FUNCTION && (flags & F_THREAD) != 0 { validation_thread_signature(p, node); }
            if (flags & F_EXTERN) != 0 && n.integer >= 0 && p.tokens[n.integer].text_len == 0 { return false; }
            validation_function(p, node);
            if kind != N_TYPE_FN && (flags & F_CHECKED) != 0 {
                if (flags & F_CHECKFREE) != 0 { p.has_checked_checkfree = true; }
                validation_checkfree_calls(p, node);
            }
        }
        if kind == N_TYPE_ARRAY && tid >= 0 && tid < elem_bad.len && elem_bad[tid] { validation_element_layout(p, tid, tok); }
        if (flags & F_CHECKED) == 0 || tid < 0 { continue; }
        if (flags & F_ARRAY_JOIN) != 0 {
            diagnose(p, tok, "control-flow branches produce incompatible array types without a slice destination");
        }
        if tid < elem_bad.len && elem_bad[tid] { validation_element_layout(p, tid, tok); }
        if (kind == N_BLOCK || kind == N_IF || kind == N_LOOP || kind == N_MATCH) &&
           p.types[tid].kind == TY_FN {
            diagnose(p, tok, "a function value must be a function name or block literal");
        }
        if kind == N_INDEX || kind == N_CALL { validation_array_operation(p, node); }
        else if kind == N_ASSIGN { validation_assignment(p, node); }
        if kind == N_CALL {
            validation_thread_call(p, node);
            if validation_builtin(p, node, 23) { validation_index_of(p, node); }
        } else if kind == N_VARIABLE {
            validation_value_type(p, tid, tok);
            var binding = n.first;
            while binding >= 0 {
                validation_value_type(p, p.nodes[binding].type_id, p.nodes[binding].token);
                binding = p.nodes[binding].next;
            }
            if p.types[tid].kind == TY_FN { diagnose(p, tok, "function values cannot be stored"); }
        } else if kind == N_FIELD {
            if p.types[tid].kind == TY_FN { diagnose(p, tok, "function values cannot be stored"); }
        } else if kind == N_FOR {
            var binding = n.first;
            while binding >= 0 {
                let annotation = p.nodes[binding].left;
                if annotation >= 0 { validation_value_type(p, p.nodes[annotation].type_id, p.nodes[binding].token); }
                binding = p.nodes[binding].next;
            }
        } else if kind == N_CAST && n.right >= 0 && validation_varint(p, p.nodes[n.right].type_id) {
            diagnose(p, tok, "cannot cast to varint (varints are written at construction only)");
        } else if kind == N_BINARY {
            var inspect = true;
            if n.integer == T_DOTEQ || n.integer == T_DOTNEQ || n.integer == T_ANDAND || n.integer == T_OROR { inspect = false; }
            if (n.integer == T_EQ || n.integer == T_NEQ) && n.left >= 0 && n.right >= 0 &&
               (p.nodes[n.left].kind == N_NULL || p.nodes[n.right].kind == N_NULL) { inspect = false; }
            if inspect && (validation_optional(p, n.left) || validation_optional(p, n.right)) {
                diagnose(p, tok, "optional reference must be narrowed before a value operation");
            }
        } else if kind == N_UNARY {
            if (n.integer == T_MUL || n.integer == T_MINUS || n.integer == T_BITNOT ||
                n.integer == T_INC || n.integer == T_DEC) && validation_optional(p, n.left) {
                diagnose(p, tok, "optional reference must be narrowed before dereferencing");
            }
        } else if kind == N_MEMBER || kind == N_INDEX || kind == N_SLICE {
            if validation_optional(p, n.left) { diagnose(p, tok, "optional reference must be narrowed before access"); }
        } else if kind == N_BLOCK {
            if n.last >= 0 && (p.nodes[n.last].flags & F_TAIL) != 0 && p.nodes[n.last].kind != N_RETURN {
                validation_control_value(p, n.last, node);
            }
        } else if kind == N_MATCH {
            var arm = n.first;
            while arm >= 0 { validation_control_value(p, p.nodes[arm].right, node); arm = p.nodes[arm].next; }
        } else if kind == N_BREAK {
            if n.symbol >= 0 { validation_control_value(p, n.left, n.symbol); }
        } else if kind == N_RETURN {
            var value = n.first;
            while value >= 0 {
                let type_id = p.nodes[value].type_id;
                if type_id >= 0 && p.types[type_id].kind == TY_FN { diagnose(p, tok, "function values cannot be returned"); }
                value = p.nodes[value].next;
            }
        } else if kind == N_ARRAY || kind == N_FILL {
            if p.types[tid].kind == TY_ARRAY && p.types[tid].element < 0 {
                diagnose(p, tok, "empty array element type was never determined");
            }
            validation_array_length(p, node);
        }
    }
    return p.diagnostics.len == 0;
}
fn check_validate_range(ctx: const CheckBatchCtx&, out: CheckBatchOut&) {
    var diagnostics: Diagnostic[>..] = [];
    var messages: u8[>..] = [];
    var local = ctx.program;
    local.diagnostics .= diagnostics;
    local.messages .= messages;
    local.has_checked_checkfree = false;
    if !check_validate_program_nodes(local, out.base, out.validation_end, ctx.elem_bad) {
        out.status = 1; return;
    }
    out.checked_checkfree = local.has_checked_checkfree;
}
fn check_validate_parallel(p: Program&, c: Checker&) -> bool {
    if p.jobs <= 1 || p.nodes.len < 32768 || p.diagnostics.len != 0 { return false; }

    let type_count = p.types.len;
    var elem_bad: bool[>..] = []; elem_bad.resize(type_count, false);
    for tid in 0..type_count {
        let t: const Type& = p.types[tid];
        if t.kind == TY_ARRAY || t.kind == TY_SLICE {
            let elem = t.element;
            if root_struct_type(p, elem) || validation_zero_layout(p, elem) || (elem >= 0 && p.types[elem].kind == TY_FN) {
                elem_bad[tid] = true;
            }
        }
    }
    var patches: CheckBodyPatch[>..] = [];
    var events: CheckBodyEvent[>..] = [];
    var outputs: CheckBatchOut[>..] = [];
    let count = p.nodes.len;
    let chunks = p.jobs * 2;
    for i in 0..chunks {
        let first = count * i / chunks;
        let end = count * (i + 1) / chunks;
        outputs.push(CheckBatchOut { base: first, patches: patches[..], events: events[..],
            apply_nodes: p.nodes[..0], apply_proofs: c.node_nonnegative[..0], validation_end: end,
            tables: CheckInstallTables { scopes: c.scopes[..0], symbols: p.symbols[..0],
                variables: c.variables[..0], variable_lookup: c.variable_lookup[..0] }, batches: c.batch_out[..0] });
    }
    let ctx = CheckBatchCtx { program: p, mode: 1, elem_bad: elem_bad[..],
        nodes: p.nodes[..], types: p.types[..], symbols: p.symbols[..], tokens: p.tokens[..], text: p.text[..],
        scopes: c.scopes[..], names: c.name_table[..], link_scopes: c.link_scopes[..], hashes: c.name_hashes[..],
        functions: c.batch_index[..], fixed_arrays: c.batch_index[..0], value_types: elem_bad[..0],
        install_batches: c.batch_out[..0], install_pending: c.batch_pending_apply[..0] };
    gp_check_dispatch(p.jobs, ctx, outputs[..]);
    var checked_checkfree = false;
    for out in outputs {
        if out.status != 0 { return false; }
        checked_checkfree = checked_checkfree || out.checked_checkfree;
    }
    p.has_checked_checkfree = checked_checkfree;
    validation_index_owners(p);
    for tid in 0..p.types.len {
        let t: const Type& = p.types[tid];
        if t.kind != TY_STRUCT { continue; }
        var field = t.first;
        while field >= 0 {
            let type_id = p.nodes[field].type_id;
            if type_id >= 0 && p.types[type_id].kind == TY_FN {
                diagnose(p, p.nodes[field].token, "function values cannot be stored in fields");
            }
            if validation_zero_layout(p, type_id) {
                diagnose(p, p.nodes[field].token, "field cannot use a zero-length array or an empty variant type");
            }
            validation_root_placement(p, type_id, p.nodes[field].token, "nested");
            field = p.nodes[field].next;
        }
    }
    return true;
}

// The serial BFS reports each reachable enum at its first use. If every enum
// is admissible, the BFS cannot emit a diagnostic, regardless of its seeds.
fn check_validate_types(p: Program&) {
    if p.jobs > 1 && p.nodes.len >= 32768 && p.diagnostics.len == 0 {
        var admissible = true;
        for tid in 0..p.types.len {
            if p.types[tid].kind == TY_ENUM && check_enum_fixed_reason(p, tid) != 0 {
                admissible = false; break;
            }
        }
        if admissible { return; }
    }
    check_validate_type_uses(p);
}

fn check_body_precheck_range(ctx: const CheckBatchCtx&, bucket: CheckBatchOut&) {
    for i in bucket.base..bucket.validation_end {
        let item: CheckBodyBatch& = bucket.batches[i];
        var work = CheckBatchOut { function_node: item.function_node, base: item.base,
            patches: bucket.patches[item.patch_at..item.patch_at + item.patch_cap],
            events: bucket.events[item.event_at..item.event_at + item.event_cap],
            apply_nodes: bucket.apply_nodes, apply_proofs: bucket.apply_proofs,
            tables: bucket.tables, batches: bucket.batches[..0] };
        // A zero flag marks an unwritten patch. Other fields are assigned as
        // a whole when the worker visits the node.
        for at in 0..work.patches.len { work.patches[at].flags = 0; }
        var state = CheckBodyState {};
        let result = ctx.types[ctx.nodes[item.function_node].type_id].element;
        if check_body_expr(ctx, work, state, item.base, TYPE_VOID) < 0 ||
            state.reachable && result != TYPE_VOID { continue; }
        item.patch_count = work.patch_count; item.proof_count = work.proof_count;
        item.event_count = work.event_count; item.first_step = work.first_step;
        item.scope_count = work.scope_count; item.local_count = work.local_count;
        item.installable = work.installable; item.returns = state.returns;
        item.status = CHECK_BODY_PENDING;
    }
}

fn gp_check_range(ctx: const CheckBatchCtx&, out: CheckBatchOut[:], begin: i64, end: i64) {
    if ctx.mode == 1 {
        for i in begin..end { check_validate_range(ctx, out[i]); }
        return;
    }
    if ctx.mode == 2 {
        for i in begin..end {
            check_body_install_range(ctx, out[i]);
        }
        return;
    }
    for i in begin..end { check_body_precheck_range(ctx, out[i]); }
}
fn gp_check_dispatch(jobs: i64, ctx: const CheckBatchCtx&, out: CheckBatchOut[:]) -> bool {
    gp_check_range(ctx, out, 0, out.len);
    return true;
}

fn check_body_candidate(p: Program&, id: i64) -> bool {
    let n: const Node& = p.nodes[id];
    return n.kind == N_FUNCTION && n.origin < 0 && n.right >= 0 && n.left >= 0 && n.type_id >= 0 &&
        p.types[n.type_id].element >= 0 &&
        (n.flags & (F_GENERIC | F_RECURSIVE | F_EXTERN | F_DEFERRED | F_DEFAULT | F_PROPERTY | F_NONLOCAL | F_THREAD | F_LOCATED)) == 0 &&
        !library_node(p, id);
}
fn check_body_signature(p: Program&, id: i64) -> bool {
    let n: const Node& = p.nodes[id];
    let result = p.types[n.type_id].element;
    if n.named_results >= 0 || result != TYPE_VOID && !check_body_scalar(result) { return false; }
    var param = n.first;
    while param >= 0 {
        let v: const Node& = p.nodes[param];
        if v.right >= 0 || !check_body_scalar(v.type_id) || (p.symbols[v.symbol].flags & S_LITERAL) != 0 { return false; }
        param = v.next;
    }
    return true;
}
fn check_body_checked_leaf(p: Program&, c: Checker&, id: i64) -> bool {
    // A body already checked serially can be a dependency if its summary
    // cannot change any caller's flow, result, roots or specialization.
    if (p.nodes[id].flags & F_DIVERGES) != 0 || check_environment_head(c, id) >= 0 ||
        c.scopes[p.nodes[id].scope].outer_exits >= 0 || check_specialization_head(c, id) >= 0 { return false; }
    if id < c.return_root_lists.len && c.return_root_lists[id].first >= 0 { return false; }
    for need in c.needs { if need.function_node == id { return false; } }
    if id < c.effect_lists.len {
        var at = c.effect_lists[id].first;
        while at >= 0 {
            let effect: const CheckEffect& = c.effects[at];
            let root: const Symbol& = p.symbols[effect.root];
            if root.owner != id || (root.flags & S_PARAMETER) != 0 || (effect.kind != 0 && effect.kind != 6) { return false; }
            at = effect.next;
        }
    }
    return true;
}
fn check_body_batch_start(p: Program&, c: Checker&, declarations: i64, wait_for_first_body: bool) {
    c.batch_deferred = 0;
    if p.jobs <= 1 || p.diagnostics.len != 0 ||
        p.nodes.len >= 2147483647 || p.symbols.len >= 2147483647 || p.types.len >= 2147483647 { return; }
    var candidates: i64[>..] = [];
    for i in 0..declarations {
        let s: const Symbol& = p.symbols[i];
        if s.owner >= 0 || s.node < 0 || s.scope < 0 || s.scope > 0 && c.scopes[s.scope].namespace_node < 0 ||
            !check_body_candidate(p, s.node) || !check_body_signature(p, s.node) { continue; }
        if (p.nodes[s.node].flags & F_CHECKED) == 0 && !check_need_active(c, s.node) { candidates.push(((p.nodes[s.node].right as i64) << 32) | s.node); }
    }
    if candidates.len < 64 { return; }

    var arrays: i32[>..] = [];
    var values: bool[>..] = []; values.resize(p.types.len, false);
    for id in 0..p.types.len {
        let t: const Type& = p.types[id];
        if check_body_scalar(id) { values[id] = true; }
        else if t.kind == TY_ARRAY && t.array_kind == A_FIXED && t.flags == 0 && t.size > 0 && t.count >= 0 &&
            t.length_storage < 0 && !t.length_explicit && check_body_scalar(t.element) {
            arrays.push(id as i32); values[id] = true;
        } else if t.kind == TY_STRUCT && t.flags == 0 && t.size > 0 && t.pool < 0 && t.declaration >= 0 {
            let decl: const Node& = p.nodes[t.declaration];
            if decl.kind != N_STRUCT || (decl.flags & (F_ROOT | F_CHECKED)) != F_CHECKED || decl.third >= 0 { continue; }
            var field = t.first; var valid = true;
            while field >= 0 {
                let f: const Node& = p.nodes[field];
                if f.kind != N_FIELD || (f.flags & (F_CONST | F_PAD)) != 0 || !check_body_scalar(f.type_id) { valid = false; break; }
                field = f.next;
            }
            values[id] = valid;
        }
    }
    if arrays.len == 0 && wait_for_first_body {
        // A local fixed-array annotation can be the first use of its type.
        // Let the first serial body intern its types in the normal DFS order.
        c.batch_deferred = declarations;
        return;
    }
    // -1 means no result, -2 means a serially checked dependency with
    // no caller-visible effects. Nonnegative entries index the output rows.
    c.batch_index.resize(p.symbols.len, -1);
    for i in 0..declarations {
        let s: const Symbol& = p.symbols[i];
        if s.owner < 0 && s.node >= 0 && (p.nodes[s.node].flags & F_CHECKED) != 0 &&
            check_body_candidate(p, s.node) && check_body_signature(p, s.node) && check_body_checked_leaf(p, c, s.node) { c.batch_index[i] = -2; }
    }
    // The high half sorts by body base. Fence every speculative window at
    // the next base, so both node patches and proof writes are disjoint.
    candidates[..].sort();
    var patch_total = 0; var event_total = 0;
    for candidate, i in candidates {
        let body = candidate >> 32;
        let node = candidate & 4294967295;
        var cap = p.nodes[body].last - body + 32;
        if cap < 32 { cap = 32; } else if cap > 1024 { cap = 1024; }
        var limit = p.nodes.len;
        if i + 1 < candidates.len { limit = candidates[i + 1] >> 32; }
        if cap > limit - body { cap = limit - body; }
        if i > 0 && (candidates[i - 1] >> 32) == body { cap = 0; }
        let events = cap / 5 + 8;
        c.batch_index[p.nodes[node].symbol] = i as i32;
        c.batch_out.push(CheckBodyBatch { base: body, patch_at: patch_total, event_at: event_total,
            function_node: node, patch_cap: cap, event_cap: events });
        patch_total += cap; event_total += events;
    }
    // Main reserves the backing arrays before workers receive their views.
    gp_grow_check_patches(c.batch_patches, patch_total);
    gp_grow_check_events(c.batch_events, event_total);
    var outputs: CheckBatchOut[>..] = [];
    let buckets = p.jobs * 4;
    for i in 0..buckets {
        outputs.push(CheckBatchOut { base: candidates.len * i / buckets,
            patches: c.batch_patches[..], events: c.batch_events[..],
            apply_nodes: p.nodes[..0], apply_proofs: c.node_nonnegative[..0],
            validation_end: candidates.len * (i + 1) / buckets,
            tables: CheckInstallTables { scopes: c.scopes[..0], symbols: p.symbols[..0],
                variables: c.variables[..0], variable_lookup: c.variable_lookup[..0] },
            batches: c.batch_out[..] });
    }
    let ctx = CheckBatchCtx { program: p, elem_bad: values[..0], nodes: p.nodes[..], types: p.types[..], symbols: p.symbols[..], tokens: p.tokens[..], text: p.text[..],
        scopes: c.scopes[..], names: c.name_table[..], link_scopes: c.link_scopes[..], hashes: c.name_hashes[..],
        functions: c.batch_index[..], fixed_arrays: arrays[..], value_types: values[..],
        install_batches: c.batch_out[..0], install_pending: c.batch_pending_apply[..0] };
    gp_check_dispatch(p.jobs, ctx, outputs[..]);

}

recursive fn check_body_batch_ready(c: Checker&, index: i64) -> bool {
    let status = c.batch_out[index].status;
    if status != CHECK_BODY_PENDING { return status == CHECK_BODY_READY; }
    c.batch_out[index].status = CHECK_BODY_VISITING;
    let base = c.batch_out[index].event_at;
    var at = c.batch_out[index].first_step;
    while at >= 0 {
        let e = c.batch_events[base + at];
        at = e.mapped as i64;
        if e.kind as i64 != CHECK_BODY_CALL { continue; }
        let target = c.batch_index[e.scope as i64] as i64;
        if target == -2 { continue; }
        if target < 0 || !check_body_batch_ready(c, target) {
            c.batch_out[index].status = CHECK_BODY_FALLBACK; return false;
        }
        if !c.batch_out[target].installable { c.batch_out[index].installable = false; }
    }
    c.batch_out[index].status = CHECK_BODY_READY;
    return true;
}
inline fn check_body_relocate(c: Checker&, base: i64, id: i64) -> i64 {
    if id <= -10 { return c.batch_events[base - id - 10].mapped as i64; }
    return id;
}
fn check_body_apply(nodes: Node[:], proofs: i64[:], patches: const CheckBodyPatch[:], events: const CheckBodyEvent[:]) {
    for i in 0..nodes.len {
        let patch: const CheckBodyPatch& = patches[i];
        if (patch.flags & CHECK_BODY_PATCHED) == 0 { continue; }
        let n: Node& = nodes[i];
        n.flags |= patch.flags & ~(CHECK_BODY_NONCONSTANT | CHECK_BODY_PATCHED);
        if patch.type_id >= 0 { n.type_id = patch.type_id; }
        if patch.scope >= 0 { n.scope = events[patch.scope].mapped; }
        if patch.symbol != -1 {
            var symbol = patch.symbol as i64;
            if symbol <= -10 { symbol = events[-symbol - 10].mapped as i64; }
            n.symbol = symbol as i32;
        }
        if patch.aux >= 0 { n.aux = patch.aux as i64; }
        if patch.last >= 0 { n.last = patch.last; }
        if patch.proof != -2 {
            var proof = patch.proof as i64;
            if proof <= -10 { proof = events[-proof - 10].mapped as i64; }
            proofs[i] = proof;
        }
    }
}
// Each replayed local is the sole declaration in a fresh scope. Retain
// its small-scope entry, using the identifier hash established by parsing.
fn check_declare_committed_local(p: Program&, c: Checker&, node: i64, scope: i64, owner: i64,
                                 slot: i64, ty: i64, proof: i64, previous: i64) -> i64 {
    let n: Node& = p.nodes[node];
    let token = n.token; let id = p.symbols.len;
    var symbol_flags = 0;
    if (n.flags & F_VAR) != 0 { symbol_flags = S_MUTABLE; }
    p.symbols.push(Symbol { name_token: token, type_id: ty, node: node, scope: scope,
        slot: slot, flags: symbol_flags, owner: owner });
    // The node patch supplies type_id, flags and symbol at the flush.
    n.scope = scope as i32;
    let row: CheckScope& = c.scopes[scope];
    row.decl_count = 1;
    row.small_decls[0] = id as i32;
    row.small_hashes[0] = p.tokens[token].integer as! i32;
    let vi = c.variables.len;
    if c.variable_lookup.len == id { c.variable_lookup.push(vi); }
    else {
        c.variable_lookup.resize(id + 1, -1);
        c.variable_lookup[id] = vi;
    }
    c.flow_clock += 1;
    c.variables.push(CheckVariable { symbol: id, assigned: true, maybeassigned: true,
        readonly: n.kind == N_BINDING, next_frame: previous, nonnegative: proof, born: c.flow_clock });
    return id;
}
recursive fn check_body_commit(p: Program&, c: Checker&, id: i64, index: i64) {
    let out = c.batch_out[index];
    // Other syntax-preservation triggers are excluded by batch eligibility.
    if c.optional_globals { check_function_syntax(p, c, id); }
    let path = c.need_path; let root_scope = p.nodes[id].scope;
    var previous_variable = c.scopes[root_scope].first_variable;
    var slot = check_list_count(p, p.nodes[id].first);
    c.need_path = c.need_frames.len;
    c.need_frames.push(CheckNeedFrame { function_node: id, parent: path });
    // A ready dependency graph is acyclic and contains no unchecked serial
    // callers. Its calls can resume replay without another active-stack scan.
    p.nodes[id].flags |= F_REACHABLE;
    for i in 0..out.event_count {
        let e = c.batch_events[out.event_at + i];
        let kind = e.kind as i64; let node = e.node as i64;
        if kind == CHECK_BODY_SCOPE {
            var parent: i64 = root_scope;
            if e.scope >= 0 { parent = c.batch_events[out.event_at + e.scope as i64].mapped as i64; }
            var depth = c.scopes[parent].depth;
            if e.value != 1 { depth += 1; }
            let scope = c.scopes.len;
            c.scopes.push(CheckScope { parent: parent, function_node: id, depth: depth, frame_root: root_scope });
            c.batch_events[out.event_at + i].mapped = scope as i32;
        } else if kind == CHECK_BODY_LOCAL {
            let scope = c.batch_events[out.event_at + e.scope as i64].mapped as i64;
            let patch: const CheckBodyPatch& = c.batch_patches[out.patch_at + node - out.base];
            let proof = check_body_relocate(c, out.event_at, e.value as i64);
            let vi = c.variables.len;
            let symbol = check_declare_committed_local(p, c, node, scope, id, slot, patch.type_id as i64, proof, previous_variable);
            previous_variable = vi; slot += 1;
            c.batch_events[out.event_at + i].mapped = symbol as i32;
        } else if kind == CHECK_BODY_CALL {
            if (p.nodes[node].flags & F_CHECKED) != 0 {
                p.nodes[node].flags |= F_REACHABLE;
                if c.needs.len == 0 {
                    c.need_edges.push(CheckNeedEdge { function_node: node, token: e.value as i64, path: c.need_path });
                } else { check_reuse_needs(p, c, node, e.value as i64); }
            } else { check_body_commit(p, c, node, c.batch_index[e.scope as i64] as i64); }
        } else if kind == CHECK_BODY_RETURN {
            let result = new_node(p, N_TYPE_ARG, p.nodes[node].token);
            p.nodes[result].type_id = e.value;
        }
    }
    c.scopes[root_scope].first_variable = previous_variable;
    if out.proof_count > 0 && out.base + out.proof_count > c.batch_proof_end {
        c.batch_proof_end = out.base + out.proof_count;
    }
    c.batch_pending_apply.push(index as i32);
    p.nodes[id].flags |= F_CHECKED;
    if out.returns { p.nodes[id].flags |= F_RETURNS; }
    c.need_path = path;
    c.batch_committed += 1;
}
// Only call and return events affect allocation order across frames. The
// planner runs a closed, ready graph while the serial checker is suspended.
recursive fn check_body_plan(p: Program&, c: Checker&, id: i64, index: i64, slots: CheckBodySlots&) {
    let out = c.batch_out[index];
    let root = p.nodes[id].scope;
    let prior = c.scopes[root].first_variable;
    c.batch_out[index].install = CheckBodyInstall { function_node: id, root_scope: root,
        root_depth: c.scopes[root].depth, scope_base: slots.scope, symbol_base: slots.symbol,
        variable_base: slots.variable, flow_base: slots.flow, first_slot: check_list_count(p, p.nodes[id].first), previous: prior };
    slots.scope += out.scope_count;
    slots.symbol += out.local_count;
    slots.variable += out.local_count;
    slots.flow += out.local_count;
    if out.local_count > 0 { c.scopes[root].first_variable = slots.variable - 1; }
    let path = c.need_path;
    c.need_path = c.need_frames.len;
    c.need_frames.push(CheckNeedFrame { function_node: id, parent: path });
    p.nodes[id].flags |= F_REACHABLE;
    var at = out.first_step;
    while at >= 0 {
        let e: CheckBodyEvent& = c.batch_events[out.event_at + at];
        at = e.mapped as i64;
        let node = e.node as i64;
        if e.kind as i64 == CHECK_BODY_RETURN {
            e.scope = slots.node as i32;
            slots.node += 1;
        } else if (p.nodes[node].flags & F_CHECKED) != 0 {
            p.nodes[node].flags |= F_REACHABLE;
            c.need_edges.push(CheckNeedEdge { function_node: node, token: e.value as i64, path: c.need_path });
        } else { check_body_plan(p, c, node, c.batch_index[e.scope as i64] as i64, slots); }
    }
    c.need_path = path;
    p.nodes[id].flags |= F_CHECKED;
    if out.returns { p.nodes[id].flags |= F_RETURNS; }
    if out.proof_count > 0 && out.base + out.proof_count > c.batch_proof_end {
        c.batch_proof_end = out.base + out.proof_count;
    }
    c.batch_pending_apply.push(index as i32);
    c.batch_committed += 1;
}

fn check_body_install(tokens: const Token[:], row: CheckBatchOut&, out: const CheckBodyBatch&) {
    let events = row.events[out.event_at..out.event_at + out.event_count];
    let patches = row.patches[out.patch_at..out.patch_at + out.patch_count];
    let nodes = row.apply_nodes[out.base..out.base + out.patch_count];
    let install = out.install;
    if install.function_node >= 0 {
        let scopes = row.tables.scopes[install.scope_base..install.scope_base + out.scope_count];
        let symbols = row.tables.symbols[install.symbol_base..install.symbol_base + out.local_count];
        let variables = row.tables.variables[install.variable_base..install.variable_base + out.local_count];
        let lookup = row.tables.variable_lookup[install.symbol_base..install.symbol_base + out.local_count];
        var scope_count = 0; var local_count = 0;
        var previous = install.previous;
        for e, i in events {
            if e.kind as i64 == CHECK_BODY_SCOPE {
                var parent = install.root_scope;
                var depth = install.root_depth;
                if e.scope >= 0 {
                    parent = events[e.scope].mapped as i64;
                    depth = scopes[parent - install.scope_base].depth;
                }
                if e.value != 1 { depth += 1; }
                scopes[scope_count] = CheckScope { parent: parent, function_node: install.function_node, depth: depth, frame_root: install.root_scope };
                events[i].mapped = (install.scope_base + scope_count) as i32;
                scope_count += 1;
            } else if e.kind as i64 == CHECK_BODY_LOCAL {
                let local_node = e.node as i64 - out.base;
                let n: Node& = nodes[local_node];
                let token = n.token as i64;
                let scope = events[e.scope].mapped;
                let symbol = install.symbol_base + local_count;
                let variable = install.variable_base + local_count;
                var flags = 0;
                if (n.flags & F_VAR) != 0 { flags = S_MUTABLE; }
                symbols[local_count] = Symbol { name_token: token, type_id: patches[local_node].type_id as i64,
                    node: e.node as i64, scope: scope as i64, slot: install.first_slot + local_count,
                    flags: flags, owner: install.function_node };
                n.scope = scope;
                let local: CheckScope& = scopes[(scope as i64) - install.scope_base];
                local.decl_count = 1; local.small_decls[0] = symbol as i32;
                local.small_hashes[0] = tokens[token].integer as! i32;
                var proof = e.value as i64;
                if proof <= -10 { proof = events[-proof - 10].mapped as i64; }
                variables[local_count] = CheckVariable { symbol: symbol, assigned: true, maybeassigned: true,
                    readonly: n.kind == N_BINDING, next_frame: previous, nonnegative: proof, born: install.flow_base + local_count + 1 };
                lookup[local_count] = variable;
                events[i].mapped = symbol as i32;
                previous = variable; local_count += 1;
            } else if e.kind as i64 == CHECK_BODY_RETURN {
                row.apply_nodes[e.scope] = Node { kind: N_TYPE_ARG as i32,
                    token: nodes[(e.node as i64) - out.base].token, type_id: e.value };
            }
        }
    }
    var first = 0; var end = 0;
    if out.proof_count > 0 { first = out.base; end = first + out.proof_count; }
    check_body_apply(nodes, row.apply_proofs[first..end], patches, events);
}

fn check_body_install_range(ctx: const CheckBatchCtx&, row: CheckBatchOut&) {
    if ctx.install_proof_start >= 0 {
        // Pending bodies are sorted by base. Give each bucket the new
        // proof rows for its bodies, including gaps and the initial prefix.
        let old_len = ctx.install_proof_start;
        let new_len = row.apply_proofs.len;
        var first = old_len;
        var end = new_len;
        if row.base > 0 {
            first = ctx.install_batches[ctx.install_pending[row.base]].base;
            if first < old_len { first = old_len; }
            if first > new_len { first = new_len; }
        }
        if row.validation_end < ctx.install_pending.len {
            end = ctx.install_batches[ctx.install_pending[row.validation_end]].base;
            if end < old_len { end = old_len; }
            if end > new_len { end = new_len; }
        }
        let proofs = row.apply_proofs[first..end];
        for i in 0..proofs.len { proofs[i] = -2; }
    }
    for at in row.base..row.validation_end {
        check_body_install(ctx.tokens, row, ctx.install_batches[ctx.install_pending[at] as i64]);
    }
}

// Publish before cloning or inspecting checked bodies. The full installer
// also uses this barrier before returning from a closed replay to DFS.
fn check_body_flush(p: Program&, c: Checker&) {
    let count = c.batch_pending_apply.len;
    if count == 0 { return; }
    let old_len = c.node_nonnegative.len;
    var proof_start = -1;
    if c.batch_proof_end > old_len {
        if count >= 32 && p.jobs > 1 && c.batch_proof_end - old_len >= 16384 {
            c.batch_pending_apply[..].sort();
            gp_grow_check_proofs(c.node_nonnegative, c.batch_proof_end);
            proof_start = old_len;
        } else { c.node_nonnegative.resize(c.batch_proof_end, -2); }
    }
    var row = CheckBatchOut { patches: c.batch_patches[..], events: c.batch_events[..],
        apply_nodes: p.nodes[..], apply_proofs: c.node_nonnegative[..],
        tables: CheckInstallTables { scopes: c.scopes[..], symbols: p.symbols[..],
            variables: c.variables[..], variable_lookup: c.variable_lookup[..] }, batches: c.batch_out[..0] };
    let tokens = p.tokens[..];
    if count < 32 || p.jobs <= 1 {
        for index in c.batch_pending_apply {
            check_body_install(tokens, row, c.batch_out[index]);
        }
    } else {
        var outputs: CheckBatchOut[>..] = [];
        var buckets = p.jobs;
        if proof_start < 0 { buckets *= 2; }
        if buckets > count { buckets = count; }
        // Each index occurs once. Body windows were fenced at precheck, and
        // the planner gave each install its own symbol, scope and flow rows.
        for i in 0..buckets {
            row.base = count * i / buckets;
            row.validation_end = count * (i + 1) / buckets;
            outputs.push(row);
        }
        var empty: bool[>..] = [];
        let ctx = CheckBatchCtx { program: p, mode: 2, elem_bad: empty[..],
            nodes: p.nodes[..0], types: p.types[..0], symbols: p.symbols[..0], tokens: tokens, text: p.text[..0],
            scopes: c.scopes[..0], names: c.name_table[..0], link_scopes: c.link_scopes[..0], hashes: c.name_hashes[..0],
            functions: c.batch_index[..0], fixed_arrays: c.batch_index[..0], value_types: empty[..],
            install_batches: c.batch_out[..], install_pending: c.batch_pending_apply[..], install_proof_start: proof_start };
        gp_check_dispatch(p.jobs, ctx, outputs[..]);
    }
    c.batch_pending_apply.clear();
    c.batch_proof_end = 0;
}

fn check_body_commit_root(p: Program&, c: Checker&, id: i64, index: i64) {
    let out: const CheckBodyBatch& = c.batch_out[index];
    var at = out.first_step;
    if out.installable && !c.optional_globals && c.needs.len == 0 {
        while at >= 0 {
            let e: const CheckBodyEvent& = c.batch_events[out.event_at + at];
            at = e.mapped as i64;
            if e.kind as i64 != CHECK_BODY_CALL || (p.nodes[e.node].flags & F_CHECKED) != 0 { continue; }
            let start_symbol = p.symbols.len;
            var slots = CheckBodySlots { scope: c.scopes.len, symbol: start_symbol,
                variable: c.variables.len, flow: c.flow_clock, node: p.nodes.len };
            check_body_plan(p, c, id, index, slots);
            if c.variable_lookup.len < start_symbol { c.variable_lookup.resize(start_symbol, -1); }
            gp_grow_nodes(p.nodes, slots.node);
            gp_grow_check_scopes(c.scopes, slots.scope);
            gp_grow_check_symbols(p.symbols, slots.symbol);
            gp_grow_check_variables(c.variables, slots.variable);
            gp_grow_check_variable_lookup(c.variable_lookup, slots.symbol);
            c.flow_clock = slots.flow;
            check_body_flush(p, c);
            return;
        }
    }
    check_body_commit(p, c, id, index);
}

fn check_body_batch_stats(p: Program&, c: Checker&) {
    var setting: u8[>..] = [];
    if !env("GOOSE_CHECK_BATCH_STATS", setting) { return; }
    var ready = 0;
    for index in 0..c.batch_out.len { if check_body_batch_ready(c, index) { ready += 1; } }
    var line: u8[>..] = [];
    line.append("body precheck jobs="); line.format(p.jobs);
    line.append(" prechecked="); line.format(ready);
    line.append(" fallback="); line.format(c.batch_out.len - ready);
    line.append(" committed="); line.format(c.batch_committed);
    line.push(10); write_stderr(line);
}

recursive fn check_function(p: Program&, c: Checker&, function_node: i64) {
    if function_node < 0 { return; }
    parse_deferred_body(p, function_node);
    check_prepare_function(p, c, function_node);
    let n_flags = p.nodes[function_node].flags; let n_tok = p.nodes[function_node].token;
    let n_ty = p.nodes[function_node].type_id; let n_right = p.nodes[function_node].right;
    let n_kind = p.nodes[function_node].kind; let n_scope = p.nodes[function_node].scope;
    let n_first = p.nodes[function_node].first; let n_sym = p.nodes[function_node].symbol;
    if c.in_unreached && (n_flags & F_REACHABLE) == 0 { c.unreached_marked.push(function_node); }
    p.nodes[function_node].flags |= F_REACHABLE;
    if (n_flags & F_CHECKED) != 0 || (n_flags & F_GENERIC) != 0 { return; }
    for active_index in 0..c.checking_count { let active = c.checking[active_index].function_node;
        if active == function_node {
            var found = false; var backedges = c.backedges;
            for index in 0..backedges.count { if check_list_at(c, backedges, index) == function_node { found = true; break; } }
            if !found { check_list_push(c, c.backedges, function_node); }
            if (n_flags & F_RECURSIVE) == 0 { diagnose(p, n_tok, "recursive cycle requires recursive declarations"); }
            if p.types[n_ty].element < 0 { diagnose(p, n_tok, "recursive function requires an explicit result type"); }
            return;
        }
    }
    if n_right < 0 { p.nodes[function_node].flags |= F_CHECKED; return; }
    if !c.in_unreached && c.parameter_default_contexts.len == 0 && n_sym >= 0 && n_sym < c.batch_index.len {
        let batch = c.batch_index[n_sym] as i64;
        if batch >= 0 && check_body_batch_ready(c, batch) { check_body_commit_root(p, c, function_node, batch); return; }
    }
    check_body_flush(p, c);
    check_function_syntax(p, c, function_node);
    let mark = check_flow_mark(c); let exit_start = c.exit_work.len; let effect_start = c.effects.len;
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
    if n_kind == N_FUNCTION && (n_flags & F_DEFAULT) == 0 { c.default_fields = CheckList {}; }
    c.scope = n_scope; c.function_node = function_node; c.result_type = p.types[n_ty].element;
    c.next_slot = check_list_count(p, n_first); c.reachable = true; c.returns = false;
    let saved_need_path = c.need_path; c.need_path = c.need_frames.len;
    c.need_frames.push(CheckNeedFrame { function_node: function_node, parent: saved_need_path });
    check_push_function(c, function_node, mark);
    var body_node: i64 = n_right; check_expression(p, c, body_node, c.result_type);
    var recursive_path = false; var backedges = c.backedges;
    for index in 0..backedges.count { if check_list_at(c, backedges, index) == function_node { recursive_path = true; break; } }
    var repeat = false;
    if recursive_path {
        for index in effect_start..c.effects.len {
            let effect: const CheckEffect& = c.effects[index];
            if effect.function_node == function_node && effect.kind == 5 && p.symbols[effect.root].owner != function_node { repeat = true; break; }
        }
    }
    if repeat {
        // The first round discovers transitive rebinds, including defaults
        // and format hooks. The second applies them at recursive backedges.
        var bindings = CheckList {}; body_node = check_clone(p, c, n_right, bindings);
        p.nodes[function_node].right = body_node as i32; check_flow_undo(c, mark);
        c.scope = n_scope; c.reachable = true; check_expression(p, c, body_node, c.result_type);
    }
    if !c.reachable && (p.nodes[function_node].flags & F_RETURNS) == 0 { p.nodes[function_node].flags |= F_DIVERGES; }
    let body_flags = p.nodes[body_node].flags; let body_last = p.nodes[body_node].last;
    if c.reachable && (body_flags & F_TAIL) != 0 && body_last >= 0 {
        let tail = body_last;
        if p.nodes[tail].kind != N_RETURN && p.nodes[tail].kind != N_BREAK && p.nodes[tail].kind != N_CONTINUE {
            var original = p.nodes[tail]; original.next = -1; original.flags &= ~F_TAIL;
            let value = p.nodes.len; p.nodes.push(original); check_retarget_exits(p, value, tail, value);
            p.nodes[tail] = Node { flags: F_IMPLICIT_RETURN | F_TAIL, kind: N_RETURN as i32, token: original.token,
                            first: value as i32, last: value as i32, symbol: n_sym, scope: original.scope };
            check_copy_roots(c, value, tail);
            check_return(p, c, tail); p.nodes[tail].type_id = TYPE_VOID as i32; p.nodes[tail].flags |= F_CHECKED;
        }
    } else if c.reachable && c.result_type >= 0 && c.result_type != TYPE_VOID {
        diagnose(p, n_tok, "function can reach its end without returning every result");
    }
    if c.reachable { check_flow_exit(c, function_node, mark); }
    // entry: what changed since the function's mark, for each variable's state there.
    var entry = CheckSpan {}; check_flow_delta(c, mark, entry); let entry_tag = c.flow_clock;
    for index in entry.first..entry.first + entry.count { let vi = c.flow_work[index].variable; c.variables[vi].seen_at = index; }
    check_record_outer_exits(p, c, function_node, mark, entry_tag, exit_start);
    // A variable unassigned at entry that every exit assigns is assigned by a
    // call; one some exit assigns may be. Only a variable an exit changed, or a
    // root this function assigns, can qualify.
    var exits = 0;
    for index in exit_start..c.exit_work.len { let exit = c.exit_work[index]; if exit.target == function_node && !exit.backedge { exits += 1; } }
    c.flow_clock += 1; let tag = c.flow_clock; let join_start = c.flow_join.len;
    for index in exit_start..c.exit_work.len {
        let exit = c.exit_work[index]; if exit.target != function_node || exit.backedge { continue; }
        for at in exit.flow.first..exit.flow.first + exit.flow.count {
            let flow = c.flow_work[at]; let vi = flow.variable;
            if flow.old_assigned { continue; }
            var join_at = c.variables[vi].seen_at;
            if c.variables[vi].seen != tag {
                c.variables[vi].seen = tag; join_at = c.flow_join.len; c.variables[vi].seen_at = join_at;
                c.flow_join.push(CheckFlowJoin { variable: vi, maybeassigned: flow.old_maybeassigned, empty: false,
                    base_assigned: flow.old_assigned, base_maybeassigned: flow.old_maybeassigned });
            }
            c.flow_join[join_at].count += 1;
            c.flow_join[join_at].assigned = c.flow_join[join_at].assigned && flow.assigned;
            c.flow_join[join_at].maybeassigned = c.flow_join[join_at].maybeassigned || flow.maybeassigned;
        }
    }
    let changed_end = c.flow_join.len;
    for effect_index in effect_start..c.effects.len {
        let effect = c.effects[effect_index]; if effect.function_node != function_node || effect.kind != 6 { continue; }
        let vi = check_variable_index(c, effect.root);
        if vi < 0 || c.variables[vi].born >= mark.stamp || c.variables[vi].seen == tag { continue; }
        var base_assigned = false; var base_maybeassigned = false; check_flow_base(c, entry_tag, vi, base_assigned, base_maybeassigned);
        if base_assigned { continue; }
        c.variables[vi].seen = tag;
        c.flow_join.push(CheckFlowJoin { variable: vi, assigned: false, maybeassigned: base_maybeassigned, empty: false,
            base_maybeassigned: base_maybeassigned });
    }
    for join_index in join_start..c.flow_join.len {
        let join = c.flow_join[join_index]; let symbol = c.variables[join.variable].symbol;
        // An exit that leaves the variable out leaves it unassigned.
        let assigned = join.assigned && join_index < changed_end && join.count == exits; let maybeassigned = join.maybeassigned;
        // Assignments on nonlocal exits belong to their target's join.
        if !maybeassigned {
            for effect_index in effect_start..c.effects.len {
                let effect = c.effects[effect_index];
                if effect.function_node == function_node && effect.root == symbol && effect.kind == 6 {
                    c.effects[effect_index].kind = 0; check_index_effect(c, effect_index, 0);
                }
            }
        }
        if exits > 0 {
            if maybeassigned && !join.base_maybeassigned { check_note_effect(c, symbol, 6); }
            check_set_assigned(c, join.variable, assigned, maybeassigned);
            if assigned { check_note_effect(c, symbol, 4); }
        }
    }
    if c.flow_join.len > join_start { let extra = c.flow_join.len - join_start; c.flow_join.pop_n(extra); }
    if c.result_type < 0 && p.types[n_ty].element >= 0 { c.result_type = p.types[n_ty].element; }
    if c.result_type < 0 { c.result_type = TYPE_VOID; }
    if c.result_type >= 0 && p.types[c.result_type].kind == TY_ARRAY && p.types[c.result_type].element < 0 { diagnose(p, n_tok, "cannot infer a result element type from an empty array"); }
    p.types[n_ty].element = c.result_type; type_reindex(p, n_ty);
    p.nodes[function_node].flags |= F_CHECKED;
    c.checking_count -= 1; c.need_path = saved_need_path;
    check_flow_undo(c, mark); check_exits_consume(c, exit_start, function_node); check_flow_close(c, mark);
    c.scope = saved_scope; c.function_node = saved_function; c.result_type = saved_result;
    c.next_slot = saved_slot; c.reachable = saved_reachable; c.returns = saved_returns; c.default_fields = saved_defaults; c.returning = saved_returning;
    c.parameter_default_function = saved_parameter_function; c.parameter_default_floor = saved_parameter_floor;
    c.render_reference = saved_render_reference;
    c.literal_comparison = saved_comparison; c.default_body = saved_default_body;
    if c.batch_deferred > 0 { check_body_batch_start(p, c, c.batch_deferred, false); }
}
recursive fn check_statement(p: Program&, c: Checker&, node: i64) {
    let returning = c.returning; c.returning = false;
    let kind = p.nodes[node].kind;
    if kind == N_VARIABLE { check_variable(p, c, node); }
    else if kind == N_FUNCTION {
        let n_ty = p.nodes[node].type_id; let n_sym = p.nodes[node].symbol;
        if n_ty >= 0 { c.scopes[p.nodes[node].scope].parent = c.scope; }
        else { p.nodes[node].scope = c.scope as i32; }
        if n_sym >= 0 { p.symbols[n_sym].index = 1; }
        check_prepare_function(p, c, node);
    }
    else if kind == N_STRUCT || kind == N_ENUM {
        if p.nodes[node].third < 0 { check_layout_nominal(p, c, p.nodes[node].type_id); }
    } else if kind == N_ALIAS { check_resolve_type(p, c, p.nodes[node].left); }
    else if kind == N_IMPORT || kind == N_NAMESPACE || kind == N_EXTERN || kind == N_EMPTY { }
    else if kind == N_DEFER { check_defer(p, c, node); }
    else { check_expression(p, c, node, TYPE_VOID); }
    c.returning = returning;
}

// `defer` (§6.6, upstream e1d95ed TypeCheck::CheckDefer). The body is checked
// where it is written, as a block in a marker on loop_stack that jumps and
// returns may not leave (check_jump, check_return_value). It names what is
// declared before it; definite assignment and a let's narrowing hold at every
// exit too, but a var's narrowing may have been undone before an exit, so the
// body is checked without it. The body runs at the exits, after the last
// read in the block: the flow after the statement is the flow before it,
// whether or not the body can complete. What it may call and whether it names
// the function's named result are checked once every function is
// (check_defers).
recursive fn check_defer(p: Program&, c: Checker&, node: i64) {
    let n = p.nodes[node];
    if c.function_node < 0 || c.default_body {
        diagnose(p, n.token, "defer outside of a function: a global initializer has no scope exit (§6.6)"); return;
    }
    var defers = c.defers; check_list_push(c, defers, node); check_list_push(c, defers, c.function_node); c.defers = defers;
    let mark = check_flow_mark(c);
    for index in 0..c.narrowed_count {
        let vi = c.narrowed_variables[index];
        if c.variables[vi].narrowed >= 0 && (p.symbols[c.variables[vi].symbol].flags & S_MUTABLE) != 0 { check_set_narrowed(c, vi, -1); }
    }
    let reachable = c.reachable; let returning = c.returning; c.returning = false;
    check_push_loop(c, CheckLoop { node: node, scope: c.scope, function_node: c.function_node, mark: mark });
    c.defer_bodies += 1;
    check_expression(p, c, n.right, TYPE_VOID);
    c.defer_bodies -= 1; c.loop_count -= 1;
    c.reachable = reachable; c.returning = returning;
    check_flow_undo(c, mark); check_flow_close(c, mark);
    p.nodes[node].type_id = TYPE_VOID as i32; p.nodes[node].flags |= F_CHECKED;
}
// Whether the code being checked is written in a defer body: a marker of its
// function, or of the function a function value it is in is written in
// (upstream InDeferBody). A nested named function's returns are its own.
fn check_in_defer_body(p: Program&, c: Checker&) -> bool {
    var li = c.loop_count - 1;
    while li >= 0 {
        let entry = c.loop_stack[li]; li -= 1;
        if p.nodes[entry.node].kind != N_DEFER { continue; }
        var function_node = c.function_node;
        while function_node >= 0 {
            if entry.function_node == function_node { return true; }
            if p.nodes[function_node].kind != N_FUNCTION_VALUE || p.nodes[function_node].symbol < 0 { break; }
            function_node = p.symbols[p.nodes[function_node].symbol].owner;
        }
    }
    return false;
}
// A use of a local in a defer body, in a function value or a nested
// function written there included: one of what the body names
// (upstream NoteDeferMention), recorded for each body of the local's
// function the use is lexically in.
fn check_defer_mention(p: Program&, c: Checker&, symbol: i64) {
    if symbol < 0 || c.function_node < 0 { return; }
    let s = p.symbols[symbol];
    if s.owner < 0 || (s.flags & (S_GLOBAL | S_FUNCTION | S_TYPE)) != 0 { return; }
    var lexical = false; var function_node = c.function_node;
    while function_node >= 0 && p.nodes[function_node].symbol >= 0 {
        if function_node == s.owner { lexical = true; break; }
        function_node = p.symbols[p.nodes[function_node].symbol].owner;
    }
    if !lexical { return; }
    var li = c.loop_count - 1;
    while li >= 0 {
        let entry = c.loop_stack[li]; li -= 1;
        if p.nodes[entry.node].kind != N_DEFER || entry.function_node != s.owner { continue; }
        var mentions = c.defer_mentions; var seen = false;
        for index in 0..mentions.count / 2 {
            if check_list_at(c, mentions, 2 * index) == entry.node && check_list_at(c, mentions, 2 * index + 1) == symbol { seen = true; break; }
        }
        if !seen { check_list_push(c, mentions, entry.node); check_list_push(c, mentions, symbol); c.defer_mentions = mentions; }
    }
}
// The functions a checked body calls, nested declarations aside: direct
// calls and dispatch targets.
fn check_body_callees(p: Program&, root: i64, out: i64[>..]&) {
    var work: i64[>..] = [root];
    while work.len > 0 {
        let id = work.pop(); if id < 0 { continue; }
        let n = p.nodes[id];
        if id != root && n.next >= 0 { work.push(n.next); }
        if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE || n.kind == N_IMPORT || n.kind == N_STRUCT || n.kind == N_ENUM || n.kind == N_ALIAS || n.kind == N_PATTERN { continue; }
        if n.kind == N_CALL && (n.flags & F_DISPATCH) != 0 {
            var arm = n.third;
            while arm >= 0 {
                let symbol = p.nodes[arm].symbol;
                if symbol >= 0 && (p.symbols[symbol].flags & (S_FUNCTION | S_BUILTIN)) == S_FUNCTION && p.symbols[symbol].node >= 0 { out.push(p.symbols[symbol].node); }
                arm = p.nodes[arm].next;
            }
        } else if n.kind == N_CALL && n.symbol >= 0 && (p.symbols[n.symbol].flags & (S_FUNCTION | S_BUILTIN)) == S_FUNCTION && p.symbols[n.symbol].node >= 0 {
            out.push(p.symbols[n.symbol].node);
        }
        for child in [n.first, n.left, n.right, n.third] { if child >= 0 { work.push(child); } }
    }
}
// Checked once every function is (upstream TypeCheck::CheckDefers): what a
// defer body calls, and what it names of its function's result.
//
// A body runs on the propagation path of a `return ... from`, in the
// epilogue of a frame the return passes through, while the return is in
// flight (§7.9). Long-distance return machinery running then would disturb
// it: a site, a frame one passes through (c.needs) or a catch (which calls
// one of those), or a function calling any of them, transitively. A site
// written in the body itself was rejected as it was checked.
//
// A local the function returns by name in a nonfixed result position is
// built at its result destination (§7.3): after `return x` its bytes are the
// caller's value and its count is recorded. The body may not name it at all,
// reads included: what it names itself, function values and nested
// functions written in it included (check_defer_mention), or what a
// function it calls names of the variables outside it (captures).
fn check_defers(p: Program&, c: Checker&) {
    if c.defers.count == 0 { return; }
    let count = p.nodes.len;
    var via: i64[>..] = []; via.resize(count, -1);
    var functions: i64[>..] = []; var edge_start: i64[>..] = []; var edges: i64[>..] = [];
    for n, id in p.nodes {
        if n.kind != N_FUNCTION && n.kind != N_FUNCTION_VALUE || (n.flags & (F_CHECKED | F_GENERIC)) != F_CHECKED || n.right < 0 { continue; }
        functions.push(id); edge_start.push(edges.len); check_body_callees(p, n.right, edges);
    }
    edge_start.push(edges.len);
    for need in c.needs { if need.function_node >= 0 && need.function_node < count { via[need.function_node] = need.function_node; } }
    var changed = true;
    while changed {
        changed = false;
        for function_node, index in functions {
            if via[function_node] >= 0 { continue; }
            for at in edge_start[index]..edge_start[index + 1] {
                if via[edges[at]] >= 0 { via[function_node] = edges[at]; changed = true; break; }
            }
        }
    }
    var defers = c.defers; var mentions = c.defer_mentions; var done: i64[>..] = [];
    for pair in 0..defers.count / 2 {
        let function_node = check_list_at(c, defers, 2 * pair + 1);
        var repeated = false; for old in done { if old == function_node { repeated = true; break; } }
        if repeated || p.nodes[function_node].right < 0 { continue; }
        done.push(function_node);
        // The locals returned by name in nonfixed result positions.
        var named: i64[>..] = [];
        if p.nodes[function_node].kind == N_FUNCTION && p.nodes[function_node].type_id >= 0 {
            var symbols: i64[>..] = []; var ordinals: i64[>..] = [];
            life_named_results_of(p, function_node, false, symbols, ordinals);
            let result_type = p.types[p.nodes[function_node].type_id].element;
            for symbol, index in symbols {
                var ty = result_type;
                if ty >= 0 && p.types[ty].kind == TY_TUPLE {
                    ty = -1; var field = p.types[result_type].first;
                    for skip in 0..ordinals[index] { if field >= 0 { field = p.nodes[field].next; } }
                    if field >= 0 { ty = p.nodes[field].type_id; }
                }
                if ty >= 0 && check_size_class(p, ty, 0) != 0 { named.push(symbol); }
            }
        }
        // Each defer statement of the body as it now stands.
        var work: i64[>..] = [p.nodes[function_node].right]; let root = p.nodes[function_node].right;
        while work.len > 0 {
            let id = work.pop(); if id < 0 { continue; }
            let n = p.nodes[id];
            if id != root && n.next >= 0 { work.push(n.next); }
            if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE || n.kind == N_IMPORT || n.kind == N_STRUCT || n.kind == N_ENUM || n.kind == N_ALIAS || n.kind == N_PATTERN { continue; }
            for child in [n.first, n.left, n.right, n.third] { if child >= 0 { work.push(child); } }
            if n.kind != N_DEFER { continue; }
            var callees: i64[>..] = []; check_body_callees(p, n.right, callees);
            var message: u8[>..] = [];
            for callee in callees {
                if via[callee] < 0 { continue; }
                message.append("defer body calls "); render_nominal_name(p, callee, message); message.append(", which");
                var step = callee;
                while via[step] != step { message.append(" calls "); render_nominal_name(p, via[step], message); message.append(", which"); step = via[step]; }
                message.append(" uses a long-distance return (a `return ... from` site, a frame one passes through, or a catch, §7.9): a defer body runs while such a return may be in flight (§6.6)");
                break;
            }
            if message.len == 0 && named.len > 0 {
                for index in 0..mentions.count / 2 {
                    if check_list_at(c, mentions, 2 * index) != id { continue; }
                    let symbol = check_list_at(c, mentions, 2 * index + 1);
                    for local in named {
                        if local != symbol { continue; }
                        message.append("defer body names "); message.append(token_text(p, p.symbols[local].name_token)); message.append(", which ");
                        render_nominal_name(p, function_node, message);
                        message.append(" returns by name and so builds at its destination (§7.3): a defer runs after the value is complete (§6.6)");
                        break;
                    }
                    if message.len > 0 { break; }
                }
            }
            if message.len == 0 && named.len > 0 {
                for callee in callees {
                    // The variables outside its activation the callee names,
                    // through what it calls in turn.
                    var reached: i64[>..] = [callee]; var at = 0; var found = -1;
                    while at < reached.len && found < 0 {
                        let current = reached[at]; at += 1;
                        var capture = p.nodes[current].captures;
                        while capture >= 0 && found < 0 {
                            for local in named { if p.nodes[capture].symbol == local { found = local; } }
                            capture = p.nodes[capture].next;
                        }
                        if p.nodes[current].right < 0 { continue; }
                        var next: i64[>..] = []; check_body_callees(p, p.nodes[current].right, next);
                        for item in next {
                            var seen = false; for old in reached { if old == item { seen = true; break; } }
                            if !seen { reached.push(item); }
                        }
                    }
                    if found < 0 { continue; }
                    message.append("defer body calls "); render_nominal_name(p, callee, message); message.append(", which names ");
                    message.append(token_text(p, p.symbols[found].name_token)); message.append(", which ");
                    render_nominal_name(p, function_node, message);
                    message.append(" returns by name and so builds at its destination (§7.3): a defer runs after the value is complete (§6.6)");
                    break;
                }
            }
            if message.len > 0 { diagnose(p, n.token, message); }
        }
    }
}

fn check_name_literal(p: Program&, token: i64) -> i64 {
    var text = p.tokens[token]; text.kind = T_STRLIT as i16; text.text_start = text.start; text.text_len = text.end - text.start;
    let tid = p.tokens.len; p.tokens.push(text);
    let id = new_node(p, N_STRING, tid); p.nodes[id].type_id = TYPE_STRING as i32;
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
    p.nodes[node].type_id = result as i32; p.nodes[node].expansion_binding = -1;
}
recursive fn check_expand_replace(p: Program&, node: i64, binding: i64, value: i64, accessor: i64, actual: i64, type_id: i64, owner: i64, pattern: bool = false) {
    if node < 0 { return; }
    let n = p.nodes[node];
    if accessor >= 0 && n.first >= 0 && p.nodes[n.first].expansion_binding == accessor && expansion_query(p, node) == 1 {
        // has_default<A> keeps the field A stands for, as an accessor member does.
        p.nodes[n.first] = Node { aux: owner, kind: N_MEMBER as i32, token: actual as i32, next: p.nodes[n.first].next };
        return;
    }
    if n.expansion_binding == binding && binding >= 0 {
        if n.kind == N_NAME {
            if value >= 0 { let next = n.next; p.nodes[node] = p.nodes[value]; p.nodes[node].next = next; return; }
            p.nodes[node].expansion_binding = -2;
        } else if n.kind == N_TYPE_NAME && accessor < 0 { check_expansion_type(p, node, type_id); }
    }
    if n.expansion_binding == accessor && accessor >= 0 {
        if type_id < 0 {
            if n.kind == N_MEMBER || n.kind == N_BINDING { p.nodes[node].token = actual as i32; p.nodes[node].aux = owner; p.nodes[node].expansion_binding = -1; }
            else if n.kind == N_TYPE_NAME { p.nodes[node].type_id = -1; p.nodes[node].expansion_binding = -3; }
            else if n.kind == N_NAME { p.nodes[node].expansion_binding = -2; }
        } else if n.kind == N_TYPE_NAME { check_expansion_type(p, node, type_id); }
        else if n.kind == N_NAME {
            if pattern { p.nodes[node].token = actual as i32; p.nodes[node].type_id = type_id as i32; p.nodes[node].expansion_binding = -1; }
            else if p.types[type_id].declaration >= 0 && p.nodes[p.types[type_id].declaration].kind == N_VARIANT && p.nodes[p.types[type_id].declaration].first < 0 {
                p.nodes[node] = Node { flags: F_CHECKED, kind: N_RECORD as i32, token: n.token, next: n.next,
                                type_id: type_id as i32, symbol: p.types[type_id].declaration as i32 };
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
            var symbol: i64 = n.symbol; if symbol < 0 { symbol = check_lookup_name(p, c, id); }
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
    let result = new_node(p, N_CAST, token); p.nodes[result].left = value as i32;
    p.nodes[result].right = operation_type(p, type_id, token) as i32; p.nodes[result].flags = F_SYNTHETIC;
    return result;
}
// The constant a const for source entry or, with condition, a const if
// operand is, as a literal node: an adaptable or typed integer, a float, a
// bool or a string.
recursive fn check_expansion_constant(p: Program&, c: Checker&, node: i64, visiting: CheckList&, condition: bool = false) -> i64 {
    if node < 0 { return -1; }
    let n = p.nodes[node]; var bindings = CheckList {};
    if n.kind == N_NAME {
        var symbol: i64 = n.symbol; if symbol < 0 { symbol = check_lookup_name(p, c, node); }
        if symbol >= 0 && (p.symbols[symbol].flags & (S_GLOBAL | S_MUTABLE)) == S_GLOBAL {
            let declaration = p.symbols[symbol].node;
            if declaration >= 0 && p.nodes[declaration].kind == N_VARIABLE && check_list_count(p, p.nodes[declaration].right) == 1 {
                for index in 0..visiting.count {
                    if check_list_at(c, visiting, index) == symbol {
                        if condition { diagnose(p, n.token, "cycle in const if condition constant initializer"); }
                        else { diagnose(p, n.token, "cycle in const for constant initializer"); }
                        return -1;
                    }
                }
                check_list_push(c, visiting, symbol);
                let value = check_expansion_constant(p, c, p.nodes[declaration].right, visiting, condition); if value < 0 { return -1; }
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
        let value = check_expansion_constant(p, c, n.left, visiting, condition);
        let ty = check_resolve_type(p, c, n.right);
        if value >= 0 && ty >= 0 { return check_expansion_fixed(p, value, ty, n.token); }
    }
    var constant = CheckConstant {};
    if check_expansion_integer(p, c, node) { constant = check_constant(p, c, node, 0); }
    if constant.valid {
        let complement = check_complement_input(p, c, node);
        if complement.valid {
            let input = new_node(p, N_INTEGER, n.token); p.nodes[input].integer = complement.value;
            let value = new_node(p, N_UNARY, n.token); p.nodes[value].integer = T_BITNOT; p.nodes[value].left = input as i32; return value;
        }
        let value = new_node(p, N_INTEGER, n.token); p.nodes[value].integer = constant.value;
        if constant.type_id == TYPE_U64 && constant.value < 0 { p.nodes[value].flags |= F_UNSIGNED; }
        if !constant.literal { return check_expansion_fixed(p, value, constant.type_id, n.token); }
        return value;
    }
    if condition { diagnose(p, n.token, "const if condition requires a scalar or string constant, or supported integer constant expression"); }
    else { diagnose(p, n.token, "const for source requires a scalar or string constant or supported integer computation"); }
    return -1;
}
// The kind of a constant check_expansion_constant gives: 1 an integer, 2 a
// float, 3 a bool, 4 a string.
fn check_const_kind(p: Program&, value: i64) -> i64 {
    var n = p.nodes[value];
    if n.kind == N_CAST { n = p.nodes[n.left]; }
    if n.kind == N_FLOAT { return 2; }
    if n.kind == N_BOOL { return 3; }
    if n.kind == N_STRING { return 4; }
    return 1;
}
fn check_const_kind_name(kind: i64) -> u8[:] {
    if kind == 2 { return "a float"; }
    if kind == 3 { return "a bool"; }
    if kind == 4 { return "a string"; }
    return "an integer";
}
// A const if condition as written, for diagnostics; substituted bindings
// show their constants (upstream ExprStr).
recursive fn check_const_condition_text(p: Program&, node: i64, out: u8[>..]&, depth: i64 = 0) {
    if node < 0 || depth > 32 { return; }
    let n = p.nodes[node];
    if n.kind == N_CAST && (n.flags & F_SYNTHETIC) != 0 { check_const_condition_text(p, n.left, out, depth + 1); }
    else if n.kind == N_INTEGER { out.format(n.integer); }
    else if n.kind == N_STRING {
        let t = p.tokens[n.token];
        out.push('"'); out.append(p.text[t.text_start..t.text_start + t.text_len]); out.push('"');
    } else if n.kind == N_UNARY { out.append(token_text(p, n.token)); check_const_condition_text(p, n.left, out, depth + 1); }
    else if n.kind == N_BINARY {
        check_const_condition_text(p, n.left, out, depth + 1); out.push(' '); out.append(token_text(p, n.token)); out.push(' ');
        check_const_condition_text(p, n.right, out, depth + 1);
    } else if n.kind == N_MEMBER { check_const_condition_text(p, n.left, out, depth + 1); out.push('.'); out.append(token_text(p, n.token)); }
    else if n.kind == N_CALL { check_const_condition_text(p, n.left, out, depth + 1); out.append("()"); }
    else { out.append(token_text(p, n.token)); }
}
// The names a const if condition reads, checked where it is written: a
// local, a type parameter or a nested function of the name is no constant
// (upstream ConstName). Operands are walked as constant arithmetic takes them.
recursive fn check_const_condition_names(p: Program&, c: Checker&, node: i64, depth: i64 = 0) -> bool {
    if node < 0 || depth > 64 { return true; }
    let n = p.nodes[node];
    if n.kind == N_UNARY { return check_const_condition_names(p, c, n.left, depth + 1); }
    if n.kind == N_BINARY { return check_const_condition_names(p, c, n.left, depth + 1) && check_const_condition_names(p, c, n.right, depth + 1); }
    if n.kind == N_MEMBER && n.left >= 0 && p.nodes[n.left].kind == N_NAME { return check_const_condition_names(p, c, n.left, depth + 1); }
    if n.kind != N_NAME || expansion_query(p, node) != 0 { return true; }
    if n.expansion_binding == -2 { diagnose(p, n.token, "const for binding is not a value or callable function"); return false; }
    let symbol = check_lookup_name(p, c, node); if symbol < 0 { return true; }
    let s = p.symbols[symbol]; var kind: const u8[:] = "";
    if (s.flags & S_TYPE) != 0 {
        if s.node >= 0 && p.nodes[s.node].kind == N_TYPE_PARAM { kind = "type parameter"; }
    } else if (s.flags & S_FUNCTION) != 0 {
        if s.scope > 0 && c.scopes[s.scope].namespace_node < 0 { kind = "nested function"; }
    } else if (s.flags & S_GLOBAL) == 0 && s.node >= 0 &&
              (p.nodes[s.node].kind == N_VARIABLE || p.nodes[s.node].kind == N_PARAM || p.nodes[s.node].kind == N_BINDING) {
        kind = "local variable";
    }
    if kind.len == 0 { return true; }
    var message: u8[>..] = []; message.append("const if condition "); message.append(token_text(p, n.token));
    message.append(" names a "); message.append(kind); message.append(", not a constant");
    diagnose(p, n.token, message); return false;
}
// A same<T1, T2> operand, resolved in this specialization and required to be
// concrete; -1 once diagnosed.
fn check_const_query_type(p: Program&, c: Checker&, query: i64, syntax: i64) -> i64 {
    let errors = p.diagnostics.len; let type_id = check_resolve_type(p, c, syntax);
    if type_id < 0 {
        if p.diagnostics.len == errors { diagnose(p, p.nodes[query].token, "same requires two valid types"); }
        return -1;
    }
    if check_has_generic(p, type_id, 0) {
        var message: u8[>..] = []; message.append("same requires concrete types, got "); render_type_name(p, type_id, message);
        diagnose(p, p.nodes[query].token, message); return -1;
    }
    return type_id;
}
// A query's value (upstream ConstQueryValue): has_default<A> is whether A's
// field declaration has a written default, which is not evaluated; same<T1,
// T2> compares two types by the checker's type identity. 1 true, 0 false,
// -1 once diagnosed.
fn check_const_query(p: Program&, c: Checker&, node: i64, query: i64) -> i64 {
    let argument = p.nodes[node].first; let a = p.nodes[argument];
    if query == 1 {
        if a.kind != N_MEMBER || a.aux < 0 {
            var message: u8[>..] = []; message.append("has_default<"); message.append(token_text(p, a.token));
            message.append("> requires "); message.append(token_text(p, a.token)); message.append(" to be a fields<T> accessor binding in scope");
            diagnose(p, a.token, message); return -1;
        }
        var field = p.types[a.aux].first;
        while field >= 0 {
            if (p.nodes[field].flags & F_PAD) == 0 && same_name(p, p.nodes[field].token, a.token) {
                if p.nodes[field].right >= 0 { return 1; }
                return 0;
            }
            field = p.nodes[field].next;
        }
        diagnose(p, a.token, "internal: has_default of an unknown field"); return -1;
    }
    let left = check_const_query_type(p, c, node, argument); if left < 0 { return -1; }
    let right = check_const_query_type(p, c, node, a.next); if right < 0 { return -1; }
    if check_same_type(p, left, right) { return 1; }
    return 0;
}
// A const if operand's constant: a query's bool, or the literal node
// check_expansion_constant gives; -1 once diagnosed.
fn check_const_operand(p: Program&, c: Checker&, node: i64) -> i64 {
    let query = expansion_query(p, node);
    if query != 0 {
        let value = check_const_query(p, c, node, query); if value < 0 { return -1; }
        return operation_bool(p, value == 1, p.nodes[node].token);
    }
    if !check_const_condition_names(p, c, node) { return -1; }
    var visiting = CheckList {}; let value = check_expansion_constant(p, c, node, visiting, true);
    // A named constant relies on keeping its initializer's value.
    if value >= 0 { check_constant_names(p, c, node); }
    return value;
}
fn check_const_float(p: Program&, c: Checker&, value: i64) -> f64 {
    var n = p.nodes[value];
    if n.kind == N_CAST { n = p.nodes[n.left]; }
    if n.kind == N_FLOAT { return n.float_value; }
    let constant = check_constant(p, c, value, 0);
    if constant.type_id == TYPE_U64 { return (constant.value as! u64) as f64; }
    return constant.value as f64;
}
// A comparison in a const if condition: two constants of one kind (upstream
// ConstComparison). Integers unify as constant arithmetic unifies them:
// equal types stay, a literal adapts to the other's type and must fit it,
// and the comparison is signed or unsigned per that type. An integer beside
// a float converts; bools and strings take == and != only.
fn check_const_comparison(p: Program&, c: Checker&, node: i64) -> i64 {
    let n = p.nodes[node]; let op = n.integer;
    if !check_const_condition_names(p, c, n.left) || !check_const_condition_names(p, c, n.right) { return -1; }
    let left = check_const_operand(p, c, n.left); if left < 0 { return -1; }
    let right = check_const_operand(p, c, n.right); if right < 0 { return -1; }
    let lk = check_const_kind(p, left); let rk = check_const_kind(p, right);
    var order = 0;
    if lk == 1 && rk == 1 {
        let a = check_constant(p, c, left, 0); let b = check_constant(p, c, right, 0);
        if !a.valid || !b.valid { diagnose(p, n.token, "const if condition requires a scalar or string constant, or supported integer constant expression"); return -1; }
        var type_id = a.type_id;
        if a.type_id != b.type_id {
            if a.literal && b.literal {
                if a.type_id == TYPE_I64 && a.value < 0 || b.type_id == TYPE_I64 && b.value < 0 {
                    diagnose(p, n.token, "constant operands have no common type (one is above i64.max, the other negative)"); return -1;
                }
                type_id = TYPE_U64;
            } else if a.literal || b.literal {
                var constant = a; type_id = b.type_id;
                if b.literal { constant = b; type_id = a.type_id; }
                if !check_constant_fits(constant, type_id) {
                    var message: u8[>..] = []; message.append("constant "); message.format(constant.value); message.append(" does not fit "); render_type_name(p, type_id, message);
                    diagnose(p, n.token, message); return -1;
                }
            } else {
                let ab = check_integer_bits(a.type_id); let bb = check_integer_bits(b.type_id);
                if ab < bb && (check_unsigned(a.type_id) == check_unsigned(b.type_id) || !check_unsigned(b.type_id)) { type_id = b.type_id; }
                else if bb < ab && (check_unsigned(a.type_id) == check_unsigned(b.type_id) || !check_unsigned(a.type_id)) { type_id = a.type_id; }
                else {
                    var message: u8[>..] = []; message.append("operands of "); message.append(token_text(p, n.token)); message.append(" have no common type: ");
                    render_type_name(p, a.type_id, message); message.append(" and "); render_type_name(p, b.type_id, message);
                    message.append(" (convert one with `as`)"); diagnose(p, n.token, message); return -1;
                }
            }
        }
        if check_unsigned(type_id) {
            let x = a.value as! u64; let y = b.value as! u64;
            if x < y { order = -1; } else if x > y { order = 1; }
        } else if a.value < b.value { order = -1; } else if a.value > b.value { order = 1; }
    } else if lk == 2 || rk == 2 {
        if lk > 2 || rk > 2 {
            var other = lk; if lk == 2 { other = rk; }
            var message: u8[>..] = []; message.append("const if condition compares a float with "); message.append(check_const_kind_name(other));
            diagnose(p, n.token, message); return -1;
        }
        let x = check_const_float(p, c, left); let y = check_const_float(p, c, right);
        if x < y { order = -1; } else if x > y { order = 1; }
    } else {
        if lk != rk {
            var message: u8[>..] = []; message.append("const if condition compares "); message.append(check_const_kind_name(lk));
            message.append(" with "); message.append(check_const_kind_name(rk)); diagnose(p, n.token, message); return -1;
        }
        if op != T_EQ && op != T_NEQ {
            if lk == 3 { diagnose(p, n.token, "bool constants compare with == and != only in a const if condition"); }
            else { diagnose(p, n.token, "string constants compare with == and != only in a const if condition"); }
            return -1;
        }
        var equal = false;
        if lk == 3 { equal = (p.nodes[left].integer != 0) == (p.nodes[right].integer != 0); }
        else {
            let x = p.tokens[p.nodes[left].token]; let y = p.tokens[p.nodes[right].token];
            equal = same_bytes(p.text[x.text_start..x.text_start + x.text_len], p.text[y.text_start..y.text_start + y.text_len]);
        }
        if !equal { order = 1; }
    }
    var truth = false;
    if op == T_EQ { truth = order == 0; }
    else if op == T_NEQ { truth = order != 0; }
    else if op == T_LT { truth = order < 0; }
    else if op == T_LTEQ { truth = order <= 0; }
    else if op == T_GT { truth = order > 0; }
    else { truth = order >= 0; }
    if truth { return 1; }
    return 0;
}
// A const if condition's value in this specialization (upstream
// ConstCondition): bool constants and queries, `!`, `&&` and `||` over
// conditions, both operands validated, and comparisons of constants.
// Anything else is an error, never a runtime branch. 1 true, 0 false, -1
// once diagnosed.
recursive fn check_const_condition(p: Program&, c: Checker&, node: i64) -> i64 {
    if node < 0 { return -1; }
    let n = p.nodes[node];
    if n.kind == N_BOOL {
        if n.integer != 0 { return 1; }
        return 0;
    }
    let query = expansion_query(p, node);
    if query != 0 { return check_const_query(p, c, node, query); }
    if n.kind == N_UNARY && n.integer == T_NOT {
        let value = check_const_condition(p, c, n.left); if value < 0 { return -1; }
        return 1 - value;
    }
    if n.kind == N_BINARY && (n.integer == T_ANDAND || n.integer == T_OROR) {
        let left = check_const_condition(p, c, n.left); if left < 0 { return -1; }
        let right = check_const_condition(p, c, n.right); if right < 0 { return -1; }
        if n.integer == T_ANDAND { return left & right; }
        return left | right;
    }
    if n.kind == N_BINARY && (n.integer == T_EQ || n.integer == T_NEQ || n.integer == T_LT || n.integer == T_LTEQ || n.integer == T_GT || n.integer == T_GTEQ) {
        return check_const_comparison(p, c, node);
    }
    if n.kind == N_NAME || n.kind == N_INTEGER || n.kind == N_FLOAT || n.kind == N_STRING || n.kind == N_UNARY || n.kind == N_BINARY || n.kind == N_CAST && (n.flags & F_SYNTHETIC) != 0 {
        let value = check_const_operand(p, c, node); if value < 0 { return -1; }
        let kind = check_const_kind(p, value);
        if kind == 3 {
            if p.nodes[value].integer != 0 { return 1; }
            return 0;
        }
        var message: u8[>..] = []; message.append("const if condition requires a bool, not "); message.append(check_const_kind_name(kind)); message.append(": ");
        check_const_condition_text(p, node, message); diagnose(p, n.token, message); return -1;
    }
    var message: u8[>..] = []; message.append("const if condition requires a constant: "); check_const_condition_text(p, node, message); message.append(" is not one");
    diagnose(p, n.token, message); return -1;
}
// The fragments a const if supplies in this specialization (upstream
// SelectBranch): the first branch whose condition holds, else the final
// else's, else -1 for none; -2 once a condition is diagnosed. A branch not
// chosen is never checked.
fn check_const_select(p: Program&, c: Checker&, node: i64) -> i64 {
    var at = node;
    while at >= 0 && p.nodes[at].kind == N_CONST_IF {
        let value = check_const_condition(p, c, p.nodes[at].left);
        if value < 0 { return -2; }
        if value == 1 { return p.nodes[at].right; }
        at = p.nodes[at].third;
    }
    return at;
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
    if c.expansion_nodes > p.expansion_limit { return result; }
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
        if copy < 0 || c.expansion_nodes > p.expansion_limit { break; }
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
        let next = p.nodes[child].next; var expansion = -1;
        if p.nodes[child].kind == N_CONST_IF {
            // The chosen branch's entries or arms join the list in place.
            expansion = check_const_select(p, c, child);
            if expansion >= 0 { check_expand_children(p, c, expansion); }
        } else if p.nodes[child].kind == N_CONST_FOR {
            expansion = check_expand_const_for(p, c, child);
            if p.nodes[expansion].kind != N_BLOCK { check_expand_children(p, c, expansion); }
        } else {
            p.nodes[child].next = -1;
            if first < 0 { first = child; } else { p.nodes[last].next = child; }
            last = child;
        }
        if expansion >= 0 {
            var item = p.nodes[expansion].first;
            while item >= 0 {
                let after = p.nodes[item].next; p.nodes[item].next = -1;
                if first < 0 { first = item; } else { p.nodes[last].next = item; }
                last = item; item = after;
            }
        }
        child = next;
    }
    p.nodes[node].first = first as i32; p.nodes[node].last = last as i32;
}
// A const for or const if in a statement list: its instances, or the chosen
// branch's block, in place. That block is a plain nested scope, not an
// expansion boundary: break, continue and return in it mean what they mean
// in an if's branch. With no branch chosen nothing is supplied.
recursive fn check_const_for(p: Program&, c: Checker&, node: i64, expected: i64) -> i64 {
    let next = p.nodes[node].next;
    if p.nodes[node].kind == N_CONST_IF {
        let branch = check_const_select(p, c, node);
        if branch < 0 { p.nodes[node] = Node { kind: N_BLOCK as i32, token: p.nodes[node].token, next: next }; }
        else { p.nodes[node] = p.nodes[branch]; p.nodes[node].next = next; }
        if branch == -2 { return -1; }
        return check_expression(p, c, node, expected);
    }
    let expanded = check_expand_const_for(p, c, node);
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
    c.scopes[result].namespace_node = namespace_node; p.nodes[namespace_node].scope = result as i32;
    c.scope = saved_scope; c.function_node = saved_function;
    return result;
}
recursive fn check_top_declarations(p: Program&, c: Checker&, first: i64) {
    var node = first;
    while node >= 0 {
        let n = p.nodes[node];
        if n.kind == N_NAMESPACE {
            let scope = check_namespace_scope(p, c, n.token); p.nodes[node].scope = scope as i32;
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
                    first: n.first, name_token: n.token }) as i32;
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
    c.in_unreached = true;
    c.unreached_marked.clear();
    for i in 0..declarations {
        let s_node = p.symbols[i].node; if s_node < 0 || p.symbols[i].owner >= 0 { continue; }
        let kind = p.nodes[s_node].kind; let right = p.nodes[s_node].right; let flags = p.nodes[s_node].flags;
        if kind != N_FUNCTION || right < 0 || (flags & (F_GENERIC | F_THREAD | F_CHECKED)) != 0 { continue; }
        if library_node(p, s_node) { continue; }
        if (p.reachable_program || p.c_host) && (flags & F_EXPORT) == 0 { continue; }
        if check_specialization_head(c, s_node) >= 0 { continue; }
        // Signatures were prepared with the declarations; only bodies remain.
        if !check_foreign_return(p, s_node) { check_function(p, c, s_node); }
    }
    // A signature name inferred by a call has no binding in an otherwise
    // uninstantiated function (upstream CheckUnreached).
    for index in 0..c.implicit_types.count {
        let parameter = check_list_at(c, c.implicit_types, index);
        let owner = p.symbols[p.nodes[parameter].symbol].owner;
        if p.nodes[owner].third >= 0 { continue; }
        var argument = p.nodes[owner].first;
        while argument >= 0 && p.nodes[argument].left >= 0 { argument = p.nodes[argument].next; }
        if argument >= 0 { continue; }
        if check_specialization_head(c, owner) < 0 {
            let token = p.nodes[parameter].token;
            var message: u8[>..] = [];
            message.append("unknown type: "); message.append(token_text(p, token));
            diagnose(p, token, message);
        }
    }
    c.in_unreached = false;
    for id in c.unreached_marked { p.nodes[id].flags &= ~F_REACHABLE; }
    c.unreached_marked.clear();
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
    var checker_effects: CheckEffect[>..] = []; var checker_effect_lists: CheckEffectList[>..] = [];
    var checker_name_table: i32[>..] = []; var checker_link_scopes: i32[>..] = []; var checker_name_hashes: i32[>..] = []; var checker_linked: i32[>..] = [];
    var checker_effect_keys: CheckEffectKey[>..] = []; var checker_effect_key_heads: i64[>..] = []; checker_effect_key_heads.resize(CHECK_INITIAL_BUCKETS, -1);
    var checker_return_roots: CheckReturnRoot[>..] = []; var checker_return_root_lists: CheckEffectList[>..] = [];
    var checker_specializations: CheckSpecialization[>..] = [];
    var checker_specialization_rows: CheckSpecializationRow[>..] = [];
    var checker_choice_args: i64[>..] = [];
    var checker_needs: CheckNeed[>..] = []; var checker_need_frames: CheckNeedFrame[>..] = []; var checker_need_edges: CheckNeedEdge[>..] = [];
    var checker_contextual_floats: CheckContextFloat[>..] = []; var checker_contextual_lookup: i64[>..] = [];
    var checker_bindings: TypeBinding[>..] = [];
    var checker_checking: CheckActive[>..] = [];
    var checker_loop_stack: CheckLoop[>..] = [];
    var checker_integer_work: CheckInteger[>..] = [];
    var checker_binding_work: TypeBinding[>..] = [];
    var checker_flow_work: CheckFlow[>..] = []; var checker_flow_trail: CheckFlowUndo[>..] = [];
    var checker_flow_join: CheckFlowJoin[>..] = []; var checker_narrowed_variables: i64[>..] = []; var checker_outer_flows: CheckFlow[>..] = [];
    var checker_format_symbols: i64[>..] = []; var checker_operation_functions: i64[>..] = []; var checker_component_symbols: i64[>..] = [];
    var checker_exit_work: CheckExit[>..] = [];
    var checker_interval_work: CheckInterval[>..] = [];
    var checker_render_cache: RenderKey[>..] = []; var checker_render_hooks: i64[>..] = [];
    var parameter_default_contexts: CheckDefaultCapture[>..] = [];
    var logical_kills: CheckLogicalKill[>..] = [];
    var literal_uses: CheckLiteralUse[>..] = [];
    var unreached_marked: i64[>..] = [];
    var pointees: CheckPointee[>..] = [];
    var batch_out: CheckBodyBatch[>..] = []; var batch_index: i32[>..] = [];
    var batch_patches: CheckBodyPatch[>..] = []; var batch_events: CheckBodyEvent[>..] = [];
    var batch_pending_apply: i32[>..] = [];
    var c = Checker { scopes: checker_scopes, variables: checker_variables, variable_lookup: checker_variable_lookup, roots: checker_roots, root_nodes: checker_root_nodes, root_symbols: checker_root_symbols, effects: checker_effects, effect_lists: checker_effect_lists, effect_keys: checker_effect_keys, effect_key_heads: checker_effect_key_heads, name_table: checker_name_table, link_scopes: checker_link_scopes, name_hashes: checker_name_hashes, linked: checker_linked, environments: checker_environments, environment_heads: checker_environment_heads, outer_exits: checker_outer_exits, syntax_nodes: checker_syntax_nodes, syntax_lookup: checker_syntax_lookup, node_nonnegative: checker_node_nonnegative, return_roots: checker_return_roots, return_root_lists: checker_return_root_lists, specializations: checker_specializations, specialization_rows: checker_specialization_rows, bindings: checker_bindings, choice_args: checker_choice_args, needs: checker_needs, need_frames: checker_need_frames, need_edges: checker_need_edges, contextual_floats: checker_contextual_floats, contextual_lookup: checker_contextual_lookup, checking: checker_checking, loop_stack: checker_loop_stack, integer_work: checker_integer_work, binding_work: checker_binding_work, flow_work: checker_flow_work, flow_trail: checker_flow_trail, flow_join: checker_flow_join, narrowed_variables: checker_narrowed_variables, outer_flows: checker_outer_flows, format_symbols: checker_format_symbols, operation_functions: checker_operation_functions, component_symbols: checker_component_symbols, exit_work: checker_exit_work, interval_work: checker_interval_work, render_cache: checker_render_cache, render_hooks: checker_render_hooks, parameter_default_contexts: parameter_default_contexts, logical_kills: logical_kills, literal_uses: literal_uses, pointees: pointees, unreached_marked: unreached_marked, batch_out: batch_out, batch_index: batch_index, batch_patches: batch_patches, batch_events: batch_events, batch_pending_apply: batch_pending_apply };
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
        else if n.kind == N_ALIAS { let aty = check_resolve_type(p, c, n.left); p.symbols[i].type_id = aty; }
    }
    c.scope = 0; c.initializing_globals = true;
    for i in 0..declarations {
        let s = p.symbols[i];
        if (s.flags & S_GLOBAL) != 0 && s.node >= 0 && p.nodes[s.node].kind == N_VARIABLE {
            check_variable(p, c, s.node);
            let vi = check_variable_index(c, i);
            if vi >= 0 { c.variables[vi].global_initialized = true; check_set_assigned(c, vi, true, true); }
        }
    }
    c.initializing_globals = false;
    check_body_batch_start(p, c, declarations, true);
    var main_symbol = -1;
    for i in 0..declarations {
        let s = p.symbols[i];
        if s.node < 0 || p.nodes[s.node].kind != N_FUNCTION { continue; }
        let n = p.nodes[s.node];
        if s.scope == 0 && token_is(p, s.name_token, "main") {
            if main_symbol >= 0 { diagnose(p, n.token, "main cannot be overloaded"); }
            main_symbol = i;
        }
        if (n.flags & F_EXPORT) != 0 || p.library && !p.reachable_program && (n.flags & F_GENERIC) == 0 { check_function(p, c, s.node); }
    }
    if main_symbol < 0 {
        // Checking only, a program that declares no main anywhere is checked on its own.
        var declares_main = false;
        for symbol in p.symbols { if (symbol.flags & S_FUNCTION) != 0 && symbol.owner < 0 && token_is(p, symbol.name_token, "main") { declares_main = true; break; } }
        if !p.library && !p.c_host && !(p.check_only && !declares_main) { diagnose(p, -1, "program requires fn main()"); }
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
    check_body_flush(p, c);
    check_unreached(p, c, declarations);
    check_body_batch_stats(p, c);
    check_defers(p, c);
    var pending_arrays = false;
    for t in p.types {
        if t.kind == TY_ARRAY && t.element < 0 { pending_arrays = true; break; }
    }
    if pending_arrays {
        for variable in c.variables {
            let s = p.symbols[variable.symbol]; let ty = s.type_id;
            if ty >= 0 && p.types[ty].kind == TY_ARRAY && p.types[ty].element < 0 {
                diagnose(p, s.name_token, "empty array element type was never determined");
            }
        }
    }
    check_finish_components(p, c);
    check_validate_types(p);
    if !check_validate_parallel(p, c) { check_validate_program(p); }
    for i in 0..c.scopes.len {
        let scope: const CheckScope& = c.scopes[i];
        scope_parents.push(scope.parent); scope_depths.push(scope.depth); scope_functions.push(scope.function_node);
    }
    var has_pool_ref = false;
    for tid in 0..p.types.len {
        let t: const Type& = p.types[tid];
        if t.kind == TY_REF && t.length_storage >= 0 && t.pool >= 0 { has_pool_ref = true; break; }
    }
    if has_pool_ref {
        var pool_types: bool[>..] = []; pool_types.resize(p.types.len, false);
        for id in 0..p.nodes.len {
            let ty = p.nodes[id].type_id;
            if ty < 0 || pool_types[ty] { continue; }
            let t: const Type& = p.types[ty];
            if t.kind != TY_REF || t.length_storage < 0 || t.pool < 0 || check_has_generic(p, t.element, 0) { continue; }
            pool_types[ty] = true; pool_references.push(id);
        }
    }
    return true;
}
fn check_program(p: Program&, declarations_only: bool = false) {
    var scope_parents: i64[>..] = []; var scope_depths: i64[>..] = []; var scope_functions: i64[>..] = [];
    var pool_references: i64[>..] = [];
    if !check_program_types(p, declarations_only, scope_parents, scope_depths, scope_functions, pool_references) { return; }
    let lifetimes_started = clock_ns();
    check_lifetimes(p, scope_parents, scope_depths, scope_functions, pool_references);
    p.lifetime_ns = clock_ns() - lifetimes_started;
    if p.diagnostics.len == 0 { check_validate_thread_globals(p); }
}
