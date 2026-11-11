import model;
import thread_plan;

// Checked-node invariants are independent of overload selection and flow joins.
recursive fn validation_size_class(p: Program&, type_id: i64, depth: i64 = 0) -> i64 {
    if type_id < 0 || depth > 64 { return 0; }
    let t = p.types[type_id];
    if t.kind == TY_ENUM && (t.flags & F_VARIABLE_MODE) == 0 { return 0; }
    if t.storage == 1 || t.kind == TY_REF && t.length_storage == 0 { return 1; }
    if t.kind == TY_ARRAY {
        if t.array_kind == A_GROW || t.array_kind == A_GROWSHRINK { return 2; }
        if t.array_kind == A_VAR || t.array_kind == A_LIMITED && t.count < 0 { return 1; }
        return validation_size_class(p, t.element, depth + 1);
    }
    var result = 0;
    if t.kind == TY_ENUM { result = 1; }
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
    if p.nodes[expression].kind == N_NAME && (p.nodes[expression].flags & F_RETURN_MOVE) != 0 { return; }
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
    if n.kind == N_INDEX {
        var array = p.nodes[n.left].type_id;
        while array >= 0 && p.types[array].kind == TY_REF { array = p.types[array].element; }
        if array >= 0 && (p.types[array].kind == TY_ARRAY || p.types[array].kind == TY_SLICE) {
            let storage = p.types[array].element;
            if storage >= 0 && p.types[storage].kind == TY_REF && p.types[storage].length_storage >= 0 {
                return ValidationRoot { symbol: p.types[storage].pool };
            }
        }
        return validation_root(p, n.left);
    }
    if n.kind == N_MEMBER && n.symbol >= 0 && n.symbol < p.nodes.len && p.nodes[n.symbol].kind == N_FIELD {
        let storage = p.nodes[n.symbol].type_id;
        if storage >= 0 && p.types[storage].kind == TY_REF && p.types[storage].length_storage >= 0 {
            return ValidationRoot { symbol: p.types[storage].pool };
        }
    }
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

fn validation_varint(p: Program&, type_id: i64) -> bool {
    return type_id >= 0 && p.types[type_id].kind == TY_INT && p.types[type_id].storage == 1;
}
fn validation_value_type(p: Program&, type_id: i64, token: i64) {
    if validation_varint(p, type_id) {
        diagnose(p, token, "varint is a storage type: only fields and array elements");
    }
}

fn validation_zero_layout(p: Program&, type_id: i64) -> bool {
    if type_id < 0 { return false; }
    let t = p.types[type_id];
    if t.kind == TY_ARRAY && (t.array_kind == A_FIXED || t.array_kind == A_LIMITED) && t.count == 0 { return true; }
    if t.kind != TY_STRUCT || t.declaration < 0 || t.size < 0 || p.nodes[t.declaration].kind != N_VARIANT { return false; }
    var field = t.first;
    while field >= 0 {
        let f = p.nodes[field];
        if (f.flags & F_PAD) == 0 || f.aux > 0 { return false; }
        field = f.next;
    }
    return true;
}

fn validation_element_layout(p: Program&, type_id: i64, token: i64) {
    if type_id < 0 { return; }
    let t = p.types[type_id];
    if (t.kind == TY_ARRAY || t.kind == TY_SLICE) && validation_zero_layout(p, t.element) {
        diagnose(p, token, "array and slice elements cannot use zero-length arrays or empty variant types");
    }
    if (t.kind == TY_ARRAY || t.kind == TY_SLICE) && t.element >= 0 && p.types[t.element].kind == TY_FN {
        diagnose(p, token, "function values cannot be stored in arrays or slices");
    }
}

fn validation_array_type(p: Program&, node: i64) -> i64 {
    if node < 0 { return -1; }
    var type_id = p.nodes[node].type_id;
    while type_id >= 0 && p.types[type_id].kind == TY_REF { type_id = p.types[type_id].element; }
    if type_id >= 0 && (p.types[type_id].kind == TY_ARRAY || p.types[type_id].kind == TY_SLICE) { return type_id; }
    return -1;
}
fn validation_array_operation(p: Program&, node: i64) {
    let n = p.nodes[node];
    if n.kind == N_INDEX {
        if (n.flags & F_SYNTHETIC) != 0 { return; }
        let array = validation_array_type(p, n.left);
        if array >= 0 && validation_size_class(p, p.types[array].element) > 0 {
            diagnose(p, n.token, "arrays of variable-size elements can only be iterated, not indexed");
        }
        return;
    }
    if n.kind != N_CALL || n.symbol < 0 || (p.symbols[n.symbol].flags & S_BUILTIN) == 0 { return; }
    let builtin = p.symbols[n.symbol].index;
    if builtin == 26 || builtin == 27 {
        let array = validation_array_type(p, n.first);
        if array >= 0 && validation_size_class(p, p.types[array].element) > 0 {
            diagnose(p, n.token, "pop and pop_n require fixed-size elements");
        }
    } else if builtin == 24 || builtin == 30 || builtin == 31 {
        if n.first < 0 { return; }
        let array = validation_array_type(p, n.first);
        if array < 0 || validation_size_class(p, p.types[array].element) == 0 { return; }
        let value = p.nodes[n.first].next;
        if value >= 0 && validation_storage_value(p, value) {
            diagnose(p, p.nodes[value].token, "non-fixed storage requires explicit copy when constructing an element");
        }
    }
}
recursive fn validation_frozen(p: Program&, type_id: i64, depth: i64 = 0) -> bool {
    if type_id < 0 || depth > 64 { return false; }
    if validation_size_class(p, type_id) == 2 { return false; }
    let t = p.types[type_id];
    if t.storage == 1 || t.kind == TY_REF && t.length_storage == 0 { return true; }
    if t.kind == TY_ARRAY { return t.array_kind == A_VAR; }
    if t.kind == TY_ENUM && (t.flags & F_VARIABLE_MODE) == 0 { return false; }
    if t.kind == TY_STRUCT || t.kind == TY_ENUM {
        var field = t.first;
        while field >= 0 {
            if validation_frozen(p, p.nodes[field].type_id, depth + 1) { return true; }
            field = p.nodes[field].next;
        }
    }
    return false;
}
fn validation_temporary_write(p: Program&, node: i64, rebind: bool) -> bool {
    var current = node; var slot = rebind;
    while current >= 0 {
        let n = p.nodes[current];
        if n.type_id >= 0 && (p.types[n.type_id].kind == TY_REF || p.types[n.type_id].kind == TY_SLICE) && !slot { return false; }
        if n.kind == N_IF || n.kind == N_MATCH || n.kind == N_BLOCK || n.kind == N_LOOP {
            return (n.flags & F_REFERENCE_CONTEXT) == 0;
        }
        if n.kind != N_MEMBER && n.kind != N_INDEX && n.kind != N_SLICE && n.kind != N_UNARY { return false; }
        current = n.left; slot = false;
    }
    return false;
}
fn validation_assignment(p: Program&, node: i64) {
    let n = p.nodes[node];
    if n.kind != N_ASSIGN || n.left < 0 { return; }
    if validation_temporary_write(p, n.left, n.integer == T_DOTASSIGN) {
        diagnose(p, n.token, "a control-flow value is a read-only temporary"); return;
    }
    var type_id = p.nodes[n.left].type_id;
    if n.integer == T_DOTASSIGN && type_id >= 0 && (p.types[type_id].kind == TY_REF || p.types[type_id].kind == TY_SLICE) { return; }
    while type_id >= 0 && p.types[type_id].kind == TY_REF { type_id = p.types[type_id].element; }
    if validation_frozen(p, type_id) {
        diagnose(p, n.token, "variable-size storage is frozen at construction: rebuild its container");
    }
}

let V_NONFIXED: i64 = 1;
let V_REFERENCE: i64 = 2;
let V_INDEX: i64 = 4;
let V_PAD: i64 = 8;
let V_UNKNOWN: i64 = 16;
let V_RELATIVE: i64 = 32;
struct ValidationTypeVisit { type_id: i64, size_class: bool }
// References still reach index-qualified types and padding, but the pointee's
// size class does not change the reference's own fixed-size representation.
fn validation_c_properties(p: Program&, type_id: i64) -> i64 {
    var pending: ValidationTypeVisit[>..] = [ValidationTypeVisit { type_id: type_id, size_class: true }];
    var seen: i64[>..] = [];
    var properties = 0;
    while pending.len > 0 {
        let item = pending.pop();
        if item.type_id < 0 { properties |= V_UNKNOWN; continue; }
        var key = item.type_id * 2; if item.size_class { key += 1; }
        var visited = false;
        for old in seen { if old == key { visited = true; break; } }
        if visited { continue; }
        seen.push(key);
        let t = p.types[item.type_id];
        if t.kind == TY_INT {
            if t.index_type >= 0 { properties |= V_INDEX; }
            if item.size_class && t.storage == 1 { properties |= V_NONFIXED; }
        } else if t.kind == TY_REF || t.kind == TY_SLICE {
            properties |= V_REFERENCE;
            if t.kind == TY_REF && t.length_storage >= 0 { properties |= V_RELATIVE; }
            if item.size_class && t.kind == TY_REF && t.length_storage == 0 { properties |= V_NONFIXED; }
            pending.push(ValidationTypeVisit { type_id: t.element, size_class: false });
        } else if t.kind == TY_ARRAY {
            if item.size_class && (t.array_kind == A_VAR || t.array_kind == A_GROW ||
               t.array_kind == A_GROWSHRINK || t.array_kind == A_LIMITED && t.count < 0) {
                properties |= V_NONFIXED;
            }
            pending.push(ValidationTypeVisit { type_id: t.element, size_class: false });
        } else if t.kind == TY_STRUCT || t.kind == TY_ENUM {
            var classify = item.size_class;
            if t.kind == TY_ENUM && (t.flags & F_VARIABLE_MODE) == 0 { classify = false; }
            var field = t.first;
            while field >= 0 {
                let f = p.nodes[field];
                if (f.flags & F_PAD) != 0 {
                    if t.kind == TY_STRUCT && t.declaration >= 0 && p.nodes[t.declaration].kind == N_STRUCT {
                        properties |= V_PAD;
                    }
                } else { pending.push(ValidationTypeVisit { type_id: f.type_id, size_class: classify }); }
                field = f.next;
            }
        } else if t.kind != TY_BOOL && t.kind != TY_FLOAT { properties |= V_UNKNOWN; }
    }
    return properties;
}
fn validation_c_value_reason(p: Program&, type_id: i64) -> u8[:] {
    let properties = validation_c_properties(p, type_id);
    if (properties & V_INDEX) != 0 { return "C code is not checked against the array an index type names"; }
    if type_id < 0 { return "the C value needs a concrete type"; }
    let t = p.types[type_id];
    if validation_varint(p, type_id) { return "varints have no C form"; }
    if t.kind == TY_REF || t.kind == TY_SLICE { return "nested references and slices do not cross"; }
    if (properties & V_NONFIXED) != 0 { return "only fixed-size values cross by value"; }
    if (properties & V_REFERENCE) != 0 { return "values holding references do not cross"; }
    if (properties & V_UNKNOWN) != 0 { return "the C value needs a concrete fixed-size type"; }
    return "";
}
fn validation_c_param_reason(p: Program&, type_id: i64) -> u8[:] {
    if type_id < 0 { return "parameter needs a type"; }
    let t = p.types[type_id];
    if t.kind == TY_REF {
        if (t.flags & TF_OPTIONAL) != 0 || t.length_storage >= 0 { return "only plain references cross"; }
        if t.element >= 0 {
            let sub = p.types[t.element];
            if sub.kind == TY_ARRAY && sub.array_kind == A_GROW && sub.element >= 0 {
                let element = p.types[sub.element];
                if element.kind == TY_INT && element.storage == 0 && element.count == 8 &&
                   (element.flags & TF_UNSIGNED) != 0 && element.index_type < 0 { return ""; }
            }
        }
        return validation_c_value_reason(p, t.element);
    }
    if t.kind == TY_SLICE { return validation_c_value_reason(p, t.element); }
    return validation_c_value_reason(p, type_id);
}
fn validation_c_nested_ref(p: Program&, syntax: i64) -> bool {
    // Alias expansion can hide an outer reference in the written signature.
    var current = syntax; var seen: i64[>..] = [];
    while current >= 0 {
        for old in seen { if old == current { return false; } }
        seen.push(current);
        let n = p.nodes[current];
        if n.kind == N_TYPE_REF {
            return n.left >= 0 && p.nodes[n.left].type_id >= 0 && p.types[p.nodes[n.left].type_id].kind == TY_REF;
        }
        if n.kind != N_TYPE_NAME || n.symbol < 0 { return false; }
        let declaration = p.symbols[n.symbol].node;
        if declaration < 0 || p.nodes[declaration].kind != N_ALIAS { return false; }
        current = p.nodes[declaration].left;
    }
    return false;
}
fn validation_c_identifier(name: u8[:]) -> bool {
    if name.len == 0 || name[0] >= 48 && name[0] <= 57 { return false; }
    for c in name {
        if c != 95 && !(c >= 48 && c <= 57) && !(c >= 65 && c <= 90) && !(c >= 97 && c <= 122) { return false; }
    }
    return true;
}
fn validation_c_keyword(name: u8[:]) -> bool {
    for keyword in ["auto", "break", "case", "char", "const", "continue", "default", "do", "double",
        "else", "enum", "extern", "float", "for", "goto", "if", "inline", "int", "long",
        "register", "restrict", "return", "short", "signed", "sizeof", "static", "struct",
        "switch", "typedef", "union", "unsigned", "void", "volatile", "while", "_Alignas",
        "_Alignof", "_Atomic", "_Bool", "_Complex", "_Generic", "_Imaginary", "_Noreturn",
        "_Static_assert", "_Thread_local"] {
        if same_bytes(name, keyword) { return true; }
    }
    return false;
}
fn validation_extern_diagnostic(p: Program&, function_node: i64, parameter: i64, reason: u8[:]) {
    var message: u8[>..] = []; message.append("extern fn ");
    message.append(token_text(p, p.nodes[function_node].token));
    if parameter >= 0 { message.append(": parameter "); message.append(token_text(p, p.nodes[parameter].token)); }
    message.append(": "); message.append(reason);
    diagnose(p, p.nodes[function_node].token, message);
}
fn validation_extern_padding(p: Program&, function_node: i64, parameter: i64, type_id: i64) {
    if p.nodes[function_node].aux < 0 || type_id < 0 { return; }
    let t = p.types[type_id];
    if t.kind == TY_REF || t.kind == TY_SLICE { return; }
    if (validation_c_properties(p, type_id) & V_PAD) != 0 {
        validation_extern_diagnostic(p, function_node, parameter,
            "a struct with pad passes by value unlike the library's own struct; pass it by reference");
    }
}
fn validation_function(p: Program&, node: i64) {
    let n = p.nodes[node];
    // Generic declarations are checked when instantiated. Their concrete
    // clones retain the origin, so an attempted generic extern call is still
    // refused even though its argument types have become concrete.
    if n.third >= 0 || (n.flags & F_GENERIC) != 0 { return; }
    // An unreached library signature is never prepared.
    if n.type_id < 0 && library_node(p, node) { return; }
    let external = (n.flags & F_EXTERN) != 0;
    if external {
        var original = n.origin;
        while original >= 0 && (p.nodes[original].kind == N_FUNCTION || p.nodes[original].kind == N_FUNCTION_VALUE) {
            if p.nodes[original].third >= 0 || (p.nodes[original].flags & F_GENERIC) != 0 {
                validation_extern_diagnostic(p, node, -1, "cannot be generic"); return;
            }
            original = p.nodes[original].origin;
        }
        var name = token_text(p, n.token);
        if n.integer >= 0 {
            let token = p.tokens[n.integer];
            if token.text_len == 0 { p.nodes[node].integer = -1; }
            else { name = p.text[token.text_start..token.text_start + token.text_len]; }
        }
        if !validation_c_identifier(name) { validation_extern_diagnostic(p, node, -1, "C symbol is not a C identifier"); }
        else if validation_c_keyword(name) { validation_extern_diagnostic(p, node, -1, "C symbol is a C keyword"); }
    }
    var parameter = n.first;
    while parameter >= 0 {
        let param = p.nodes[parameter];
        validation_value_type(p, param.type_id, param.token);
        if external {
            let reason = validation_c_param_reason(p, param.type_id);
            if param.left < 0 { validation_extern_diagnostic(p, node, parameter, "parameter needs a type"); }
            else if validation_c_nested_ref(p, param.left) {
                validation_extern_diagnostic(p, node, parameter, "nested references and slices do not cross");
            }
            else if reason.len > 0 { validation_extern_diagnostic(p, node, parameter, reason); }
            else { validation_extern_padding(p, node, parameter, param.type_id); }
        }
        parameter = param.next;
    }
    var result = n.left; var results = 0;
    while result >= 0 {
        let type_id = p.nodes[result].type_id;
        validation_value_type(p, type_id, p.nodes[result].token);
        if external {
            let reason = validation_c_value_reason(p, type_id);
            if reason.len > 0 { validation_extern_diagnostic(p, node, -1, reason); }
            else { validation_extern_padding(p, node, -1, type_id); }
        }
        results += 1; result = p.nodes[result].next;
    }
    if external && results > 1 { validation_extern_diagnostic(p, node, -1, "returns at most one value"); }
}

struct ValidationThreadFamily { worker: i64 = -1, count: i64 = 0 }
fn validation_thread_family(p: Program&, argument: i64) -> ValidationThreadFamily {
    if argument < 0 || p.nodes[argument].kind != N_NAME { return ValidationThreadFamily {}; }
    var symbol = p.nodes[argument].symbol;
    if symbol < 0 { return ValidationThreadFamily {}; }
    if (p.symbols[symbol].flags & S_FUNCTION) == 0 {
        // A compile-time function parameter keeps the bound function's type,
        // whose declaration identifies the original overload family.
        let type_id = p.symbols[symbol].type_id;
        if type_id < 0 || p.types[type_id].kind != TY_FN { return ValidationThreadFamily {}; }
        let bound = p.types[type_id].declaration;
        if bound < 0 || p.nodes[bound].kind != N_FUNCTION || p.nodes[bound].symbol < 0 { return ValidationThreadFamily {}; }
        symbol = p.nodes[bound].symbol;
    }
    var declaration = p.symbols[symbol].node;
    while declaration >= 0 && p.nodes[declaration].origin >= 0 {
        let original = p.nodes[declaration].origin;
        if p.nodes[original].kind != N_FUNCTION { break; }
        declaration = original;
    }
    if declaration >= 0 && p.nodes[declaration].symbol >= 0 { symbol = p.nodes[declaration].symbol; }
    let family = p.symbols[symbol]; var result = ValidationThreadFamily {};
    // A generic function parameter may name an entire overload family. The
    // worker arguments never select among that family's thread declarations.
    for candidate, index in p.symbols {
        if candidate.scope == family.scope && (candidate.flags & S_FUNCTION) != 0 &&
           same_name(p, candidate.name_token, family.name_token) && candidate.node >= 0 &&
           (p.nodes[candidate.node].flags & F_THREAD) != 0 {
            if result.worker < 0 { result.worker = index; }
            result.count += 1;
        }
    }
    return result;
}
fn validation_resolve_thread(p: Program&, argument: i64) -> i64 {
    return validation_thread_family(p, argument).worker;
}
fn validation_thread_signature(p: Program&, node: i64) {
    let n = p.nodes[node];
    if n.symbol >= 0 && p.symbols[n.symbol].scope == 0 && token_is(p, n.token, "main") {
        diagnose(p, n.token, "fn main must be an ordinary function, not a thread_fn");
    }
    if n.third >= 0 || (n.flags & F_GENERIC) != 0 { diagnose(p, n.token, "thread_fn cannot be generic and needs fully typed parameters"); }
    if n.left >= 0 { diagnose(p, n.token, "thread_fn cannot return values"); }
    var parameter = n.first;
    while parameter >= 0 {
        let param = p.nodes[parameter];
        if param.left < 0 || param.type_id < 0 { diagnose(p, param.token, "thread_fn needs fully typed parameters"); }
        else {
            let properties = validation_c_properties(p, param.type_id);
            if (properties & V_REFERENCE) != 0 { diagnose(p, param.token, "thread_fn parameters must be flat"); }
            if (properties & V_UNKNOWN) != 0 { diagnose(p, param.token, "thread_fn parameters need concrete stored value types"); }
        }
        parameter = param.next;
    }
}
fn validation_thread_call_target(p: Program&, node: i64, symbol: i64) {
    if symbol < 0 || (p.symbols[symbol].flags & S_FUNCTION) == 0 { return; }
    let function_node = p.symbols[symbol].node;
    if function_node >= 0 && (p.nodes[function_node].flags & F_THREAD) != 0 {
        diagnose(p, p.nodes[node].token, "thread_fn is spawned with thread_spawn, not called");
    }
}
fn validation_thread_transfer(p: Program&, node: i64, type_id: i64) {
    if type_id >= 0 && (validation_c_properties(p, type_id) & V_INDEX) != 0 {
        diagnose(p, p.nodes[node].token, "index types cannot pass between threads: each program has its own copy of the named array");
    }
}
fn validation_thread_call(p: Program&, node: i64) {
    let n = p.nodes[node];
    validation_thread_call_target(p, node, n.symbol);
    if (n.flags & F_DISPATCH) != 0 {
        var arm = n.third;
        while arm >= 0 { validation_thread_call_target(p, node, p.nodes[arm].symbol); arm = p.nodes[arm].next; }
    }
    if validation_builtin(p, node, 7) || validation_builtin(p, node, 8) {
        let family = validation_thread_family(p, n.first);
        if family.count > 1 { diagnose(p, n.token, "ambiguous thread_spawn: more than one thread_fn has that name"); }
        else if family.worker < 0 { diagnose(p, n.token, "thread_spawn's first argument names a thread_fn"); }
        if family.worker >= 0 {
            var param = p.nodes[p.symbols[family.worker].node].first;
            while param >= 0 { validation_thread_transfer(p, node, p.nodes[param].type_id); param = p.nodes[param].next; }
        }
    } else if validation_builtin(p, node, 10) && n.first >= 0 {
        validation_thread_transfer(p, node, p.nodes[n.first].type_id);
    } else if (validation_builtin(p, node, 11) || validation_builtin(p, node, 12) || validation_builtin(p, node, 13)) && n.left >= 0 {
        let argument = p.nodes[n.left].first;
        if argument >= 0 { validation_thread_transfer(p, node, p.nodes[argument].type_id); }
    }
}
// The lifetime pass publishes -2 only for exact static/null roots. A type's
// const qualifier says nothing about whether it points into another global.
fn check_validate_thread_globals(p: Program&) {
    var globals: bool[>..] = [];
    for function_node in 0..p.nodes.len {
        let n = p.nodes[function_node];
        if n.kind != N_FUNCTION || (n.flags & (F_THREAD | F_CHECKED)) != (F_THREAD | F_CHECKED) { continue; }
        thread_globals(p, function_node, globals);
        for used, symbol in globals {
            if !used { continue; }
            let global = p.symbols[symbol];
            let properties = validation_c_properties(p, global.type_id);
            if (properties & V_REFERENCE) == 0 { continue; }
            if (global.flags & S_MUTABLE) == 0 && global.provenance == -2 && (properties & V_RELATIVE) == 0 { continue; }
            var message: u8[>..] = []; message.append("thread programs may access only flat globals, and let globals whose references lead only to static data: ");
            message.append(token_text(p, global.name_token)); message.append(" holds references");
            if (global.flags & S_MUTABLE) != 0 { message.append(" and is a var"); }
            message.append(" (reached from thread_fn "); message.append(token_text(p, n.token)); message.append(")");
            diagnose(p, global.name_token, message);
        }
    }
}
fn validation_index_owners(p: Program&) {
    var seen: bool[>..] = []; seen.resize(p.symbols.len, false);
    for t in p.types {
        if t.kind != TY_INT || t.index_type < 0 || t.pool < 0 || t.pool >= p.symbols.len { continue; }
        let owner = p.symbols[t.pool];
        if seen[t.pool] { continue; }
        seen[t.pool] = true;
        if (owner.flags & S_GLOBAL) == 0 {
            diagnose(p, owner.name_token, "the array of an index type must be a global variable");
        } else if (owner.flags & S_MUTABLE) == 0 || owner.type_id < 0 ||
            p.types[owner.type_id].kind != TY_ARRAY || p.types[owner.type_id].array_kind != A_GROW {
            diagnose(p, owner.name_token, "the array of an index type must be a grow-only resizable global var");
        } else {
            let element = p.types[owner.type_id].element;
            if (validation_c_properties(p, element) & V_NONFIXED) != 0 {
                diagnose(p, owner.name_token, "the array of an index type holds variable-size elements, which cannot be indexed");
            }
        }
    }
}
fn validation_checkfree(p: Program&, function: i64) -> bool {
    var current = function; var depth = 0;
    while current >= 0 && depth < 64 {
        let n = p.nodes[current];
        if (n.flags & F_CHECKFREE) != 0 { return true; }
        if n.symbol < 0 { return false; }
        current = p.symbols[n.symbol].owner; depth += 1;
    }
    return false;
}
fn validation_checkfree_target(p: Program&, call: i64, symbol: i64, work: i64[>..]&) {
    if symbol < 0 || (p.symbols[symbol].flags & (S_BUILTIN | S_FUNCTION)) != S_FUNCTION { return; }
    let function = p.symbols[symbol].node;
    if function < 0 || (p.nodes[function].flags & F_EXTERN) != 0 { return; }
    if (p.nodes[function].flags & F_SYNTHETIC) != 0 {
        work.push(p.nodes[function].right); return;
    }
    if !validation_checkfree(p, function) {
        diagnose(p, p.nodes[call].token, "a checkfree function can call only checkfree functions and blocks written in checkfree functions");
    }
}
fn validation_checkfree_calls(p: Program&, function: i64) {
    if !validation_checkfree(p, function) { return; }
    var work: i64[>..] = [p.nodes[function].right];
    var seen: bool[>..] = []; seen.resize(p.nodes.len, false);
    while work.len > 0 {
        let node = work.pop();
        if node < 0 || node >= p.nodes.len || seen[node] { continue; }
        seen[node] = true; let n = p.nodes[node];
        if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE || n.kind == N_STRUCT ||
           n.kind == N_ENUM || n.kind == N_ALIAS || n.kind == N_IMPORT { continue; }
        if n.kind == N_CALL {
            validation_checkfree_target(p, node, n.symbol, work);
            if (n.flags & F_DISPATCH) != 0 {
                var arm = n.third;
                while arm >= 0 { validation_checkfree_target(p, node, p.nodes[arm].symbol, work); arm = p.nodes[arm].next; }
            }
        }
        var child = n.first;
        while child >= 0 { work.push(child); child = p.nodes[child].next; }
        work.push(n.left); work.push(n.right);
        if n.kind != N_CALL { work.push(n.third); }
    }
}

fn check_validate_program(p: Program&) {
    let count = p.nodes.len;
    for node in 0..count {
        let n = p.nodes[node];
        if n.kind == N_FUNCTION && (n.flags & F_THREAD) != 0 { validation_thread_signature(p, node); }
        if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE || n.kind == N_TYPE_FN { validation_function(p, node); }
        if (n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE) && (n.flags & F_CHECKED) != 0 { validation_checkfree_calls(p, node); }
        if n.kind == N_TYPE_ARRAY { validation_element_layout(p, n.type_id, n.token); }
        if (n.flags & F_CHECKED) == 0 || n.type_id < 0 { continue; }
        validation_element_layout(p, n.type_id, n.token);
        if p.types[n.type_id].kind == TY_FN &&
           (n.kind == N_BLOCK || n.kind == N_IF || n.kind == N_LOOP || n.kind == N_MATCH) {
            diagnose(p, n.token, "a function value must be a function name or block literal");
        }
        validation_array_operation(p, node); validation_assignment(p, node);
        if n.kind == N_CALL { validation_thread_call(p, node); }
        if n.kind == N_VARIABLE {
            validation_value_type(p, n.type_id, n.token);
            var binding = n.first;
            while binding >= 0 {
                validation_value_type(p, p.nodes[binding].type_id, p.nodes[binding].token);
                binding = p.nodes[binding].next;
            }
        } else if n.kind == N_FOR {
            var binding = n.first;
            while binding >= 0 {
                let annotation = p.nodes[binding].left;
                if annotation >= 0 { validation_value_type(p, p.nodes[annotation].type_id, p.nodes[binding].token); }
                binding = p.nodes[binding].next;
            }
        } else if n.kind == N_CAST && n.right >= 0 && validation_varint(p, p.nodes[n.right].type_id) {
            diagnose(p, n.token, "cannot cast to varint (varints are written at construction only)");
        }
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
        if n.kind == N_ARRAY || n.kind == N_FILL {
            if p.types[n.type_id].kind == TY_ARRAY && p.types[n.type_id].element < 0 {
                diagnose(p, n.token, "empty array element type was never determined");
            }
            validation_array_length(p, node);
        }
    }
    validation_index_owners(p);
    for t in p.types {
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
            field = p.nodes[field].next;
        }
    }
}
