import model;
import checker_operations;

// Rendering lowers to ordinary calls so both backends retain user hooks,
// evaluation order, places, and the same default aggregate spelling.
struct RenderKey {
    type_id: i64, parameter_type: i64, quoted: bool, variant: bool, helper: i64,
}

fn render_reference(p: Program&, type_id: i64, flags: i64 = 0) -> i64 {
    // Const is shallow: a stored mutable reference keeps its pointee writable.
    if p.types[type_id].kind == TY_REF { return type_id; }
    for t, id in p.types {
        if t.kind == TY_REF && t.element == type_id && t.flags == flags && t.length_storage < 0 { return id; }
    }
    return add_type(p, Type { kind: TY_REF, element: type_id, flags: flags, size: p.pointer_bytes, align: p.pointer_bytes });
}
fn render_output_type(p: Program&) -> i64 {
    var array = -1;
    for t, id in p.types {
        if t.kind == TY_ARRAY && t.element == TYPE_U8 && t.array_kind == A_GROW && t.flags == 0 { array = id; break; }
    }
    if array < 0 { array = add_type(p, Type { kind: TY_ARRAY, element: TYPE_U8, count: -1, size: 24, align: 4, array_kind: A_GROW }); }
    return render_reference(p, array);
}
fn render_literal(p: Program&, at: i64, text: const u8[:]) -> i64 {
    var token = p.tokens[at]; token.kind = T_STRLIT; token.start = p.text.len;
    p.text.append(text); token.end = p.text.len; token.text_start = token.start; token.text_len = text.len;
    let id = p.tokens.len; p.tokens.push(token); return new_node(p, N_STRING, id);
}
fn render_call(p: Program&, body: i64, callee: i64, out: i64, value: i64, raw: bool = false, symbol: i64 = -1) {
    let call = new_node(p, N_CALL, callee); p.nodes[call].left = operation_ident(p, callee);
    p.nodes[call].flags = F_SYNTHETIC; p.nodes[call].symbol = symbol;
    if raw { p.nodes[call].flags |= F_FORMAT_RAW; }
    append_child(p, call, operation_ident(p, out)); append_child(p, call, value); append_child(p, body, call);
}
fn render_raw(p: Program&, body: i64, out: i64, value: i64, token: i64) {
    render_call(p, body, operation_name(p, token, "format", false), out, value, true);
}
fn render_text(p: Program&, body: i64, out: i64, text: const u8[:], token: i64) {
    render_raw(p, body, out, render_literal(p, token, text), token);
}
fn render_nominal_name(p: Program&, declaration: i64, out: u8[>..]&) {
    let token = p.nodes[declaration].token;
    if token >= 2 && p.tokens[token - 1].kind == T_COLONCOLON {
        out.append(token_text(p, token - 2)); out.append("::");
    } else {
        let source = p.tokens[token].source;
        if source >= 0 && source < p.sources.len {
            let module = p.sources[source].root;
            if module >= 0 {
                var item = p.nodes[module].first;
                while item >= 0 {
                    if p.nodes[item].kind == N_NAMESPACE { out.append(token_text(p, p.nodes[item].token)); out.append("::"); break; }
                    item = p.nodes[item].next;
                }
            }
        }
    }
    out.append(token_text(p, token));
}
recursive fn render_type_name(p: Program&, type_id: i64, out: u8[>..]&, depth: i64 = 0, top_const: bool = true) {
    if type_id < 0 || depth > 128 { return; }
    let t = p.types[type_id];
    if top_const && (t.flags & TF_CONST) != 0 { out.append("const "); }
    if t.kind == TY_INT {
        if t.storage == 1 { out.append("varint"); }
        else { if (t.flags & TF_UNSIGNED) != 0 { out.push('u'); } else { out.push('i'); } out.format(t.count); }
        if t.index_type >= 0 && t.pool >= 0 && t.pool < p.symbols.len {
            if (t.flags & F_BOUND_TYPE) != 0 { out.append(" upto "); } else { out.append(" in "); }
            out.append(token_text(p, p.symbols[t.pool].name_token));
        }
    } else if t.kind == TY_FLOAT { out.push('f'); out.format(t.count); }
    else if t.kind == TY_BOOL { out.append("bool"); }
    else if t.kind == TY_VOID { out.append("void"); }
    else if t.kind == TY_STRUCT || t.kind == TY_ENUM {
        if t.pool >= 0 && p.nodes[t.declaration].kind == N_VARIANT {
            render_type_name(p, t.pool, out, depth + 1); out.push('.'); out.append(token_text(p, p.nodes[t.declaration].token)); return;
        }
        render_nominal_name(p, t.declaration, out);
        var argument = t.arguments;
        if argument >= 0 { out.push('<'); }
        while argument >= 0 {
            render_type_name(p, p.nodes[argument].type_id, out, depth + 1); argument = p.nodes[argument].next;
            if argument >= 0 { out.append(", "); } else { out.push('>'); }
        }
        if t.kind == TY_ENUM && (t.flags & F_VARIABLE_MODE) != 0 { out.append(".."); }
    } else if t.kind == TY_ARRAY || t.kind == TY_SLICE {
        render_type_name(p, t.element, out, depth + 1);
        if t.kind == TY_SLICE { out.append("[:]"); }
        else if t.array_kind == A_FIXED { out.push('['); out.format(t.count); out.push(']'); }
        else if t.array_kind == A_VAR {
            out.push('[');
            if t.length_explicit {
                if t.length_storage == 0 { out.append("varint"); }
                else { out.push('u'); out.format(t.length_storage * 8); }
            }
            out.push(']');
        } else if t.array_kind == A_LIMITED { out.append("[.."); if t.count >= 0 { out.format(t.count); } out.push(']'); }
        else if t.array_kind == A_GROW { out.append("[>..]"); }
        else { out.append("[>..<]"); }
    } else if t.kind == TY_REF {
        render_type_name(p, t.element, out, depth + 1);
        if t.length_storage >= 0 {
            out.append("&<"); if t.length_storage == 0 { out.append("varint"); } else { out.push('u'); out.format(t.length_storage * 8); }
            if t.pool >= 0 && t.pool < p.symbols.len { out.append(" in "); out.append(token_text(p, p.symbols[t.pool].name_token)); }
            out.push('>'); if (t.flags & TF_OPTIONAL) != 0 { out.push('?'); }
        } else if (t.flags & TF_OPTIONAL) != 0 { out.push('?'); } else { out.push('&'); }
    }
}
fn render_label(p: Program&, body: i64, out: i64, type_id: i64, token: i64) {
    var text: u8[>..] = []; render_type_name(p, type_id, text, 0, false); render_text(p, body, out, text, token);
}
fn render_variant_label(p: Program&, body: i64, out: i64, type_id: i64, token: i64, empty: bool) {
    let t = p.types[type_id];
    if empty && t.pool >= 0 { render_raw(p, body, out, render_literal(p, token, token_text(p, p.nodes[p.types[t.pool].declaration].token)), token); render_text(p, body, out, ".", token); }
    render_raw(p, body, out, render_literal(p, token, token_text(p, p.nodes[t.declaration].token)), token);
}
fn render_raw_byte(p: Program&, body: i64, out: i64, byte: i64, token: i64) {
    let array = new_node(p, N_ARRAY, token); append_child(p, array, operation_ident(p, byte)); render_raw(p, body, out, array, token);
}
fn render_escape(p: Program&, body: i64, out: i64, value: i64, token: i64) {
    render_text(p, body, out, "\"", token);
    let byte = operation_name(p, token, "__goose_render_byte");
    let loop_node = new_node(p, N_FOR, token); p.nodes[loop_node].left = operation_ident(p, value);
    append_child(p, loop_node, new_node(p, N_BINDING, byte));
    let loop_body = new_node(p, N_BLOCK, token); p.nodes[loop_node].right = loop_body; append_child(p, body, loop_node);
    var tail = loop_body;
    for code in [10, 13, 9, 92, 34] {
        let branch = new_node(p, N_IF, token);
        p.nodes[branch].left = operation_binary(p, T_EQ, operation_ident(p, byte), operation_integer(p, code, token), token);
        let yes = new_node(p, N_BLOCK, token); let no = new_node(p, N_BLOCK, token);
        p.nodes[branch].right = yes; p.nodes[branch].third = no; append_child(p, tail, branch);
        if code == 10 { render_text(p, yes, out, "\\n", token); }
        else if code == 13 { render_text(p, yes, out, "\\r", token); }
        else if code == 9 { render_text(p, yes, out, "\\t", token); }
        else if code == 92 { render_text(p, yes, out, "\\\\", token); }
        else { render_text(p, yes, out, "\\\"", token); }
        tail = no;
    }
    render_raw_byte(p, tail, out, byte, token);
    render_text(p, body, out, "\"", token);
}
fn render_empty_enum(p: Program&, body: i64, out: i64, value: i64, type_id: i64, token: i64) {
    let t = p.types[type_id]; let match_node = new_node(p, N_MATCH, token);
    p.nodes[match_node].left = operation_ident(p, value);
    var variant = t.first;
    while variant >= 0 {
        let v = p.nodes[variant]; let arm = new_node(p, N_ARM, v.token);
        let pattern = new_node(p, N_PATTERN, v.token); p.nodes[arm].left = pattern;
        append_child(p, pattern, operation_ident(p, v.token));
        var label: u8[>..] = [];
        label.append(token_text(p, p.nodes[t.declaration].token)); label.push('.'); label.append(token_text(p, v.token));
        p.nodes[arm].right = render_literal(p, token, label); append_child(p, match_node, arm);
        variant = v.next;
    }
    render_raw(p, body, out, match_node, token);
}

recursive fn render_function(p: Program&, cache: RenderKey[>..]&, hooks: const i64[:],
                             type_id: i64, parameter_type: i64, quoted: bool = false, variant: bool = false) -> i64 {
    for key in cache {
        if key.type_id == type_id && key.parameter_type == parameter_type && key.quoted == quoted && key.variant == variant { return key.helper; }
    }
    let t = p.types[type_id]; var token = t.name_token;
    if token < 0 && t.declaration >= 0 { token = p.nodes[t.declaration].token; }
    if token < 0 { token = 0; }
    let name = operation_name(p, token, "__goose_render"); let out = operation_name(p, token, "__goose_render_out");
    let value = operation_name(p, token, "__goose_render_value");
    let function_node = new_node(p, N_FUNCTION, name); p.nodes[function_node].flags = F_SYNTHETIC | F_RECURSIVE;
    cache.push(RenderKey { type_id: type_id, parameter_type: parameter_type, quoted: quoted, variant: variant, helper: function_node });
    let destination = new_node(p, N_PARAM, out); p.nodes[destination].type_id = render_output_type(p); append_child(p, function_node, destination);
    let source = new_node(p, N_PARAM, value); p.nodes[source].type_id = parameter_type; append_child(p, function_node, source);
    p.nodes[function_node].left = operation_type(p, TYPE_VOID, token);
    let body = new_node(p, N_BLOCK, token); p.nodes[function_node].right = body;
    if !variant && type_id < hooks.len && hooks[type_id] >= 0 {
        let symbol = hooks[type_id]; render_call(p, body, p.symbols[symbol].name_token, out, operation_ident(p, value), false, symbol); return function_node;
    }
    p.nodes[function_node].flags |= F_FORMAT_RAW;
    var const_flags = (p.types[parameter_type].flags | t.flags) & TF_CONST;
    if t.kind == TY_REF {
        if t.element == TYPE_VOID { render_text(p, body, out, "null", token); return function_node; }
        var element_type = t.element;
        if (t.flags & TF_CONST) != 0 && p.types[element_type].kind == TY_SLICE && (p.types[element_type].flags & TF_CONST) == 0 {
            var qualified = p.types[element_type]; qualified.flags |= TF_CONST; element_type = add_type(p, qualified);
        }
        let child_type = render_reference(p, element_type, const_flags);
        let child = render_function(p, cache, hooks, element_type, child_type, quoted);
        if (t.flags & TF_OPTIONAL) == 0 { render_call(p, body, p.nodes[child].token, out, operation_ident(p, value)); }
        else {
            let branch = new_node(p, N_IF, token); let null_node = new_node(p, N_NULL, token);
            p.nodes[branch].left = operation_binary(p, T_NEQ, operation_ident(p, value), null_node, token);
            let yes = new_node(p, N_BLOCK, token); let no = new_node(p, N_BLOCK, token);
            p.nodes[branch].right = yes; p.nodes[branch].third = no; append_child(p, body, branch);
            render_call(p, yes, p.nodes[child].token, out, operation_ident(p, value)); render_text(p, no, out, "null", token);
        }
    } else if t.kind == TY_ARRAY || t.kind == TY_SLICE {
        if t.kind == TY_SLICE { const_flags = t.flags & TF_CONST; }
        let sequence = operation_name(p, token, "__goose_render_sequence");
        var source_value = operation_ident(p, value);
        if t.kind == TY_SLICE && p.types[parameter_type].kind == TY_REF {
            let descriptor = new_node(p, N_CAST, token); p.nodes[descriptor].flags = F_SYNTHETIC | F_UNSIGNED;
            p.nodes[descriptor].left = source_value; p.nodes[descriptor].right = operation_type(p, render_reference(p, type_id), token);
            source_value = descriptor;
        }
        let snapshot = new_node(p, N_VARIABLE, sequence); p.nodes[snapshot].flags = F_SYNTHETIC;
        let view = new_node(p, N_SLICE, token); p.nodes[view].left = source_value;
        p.nodes[snapshot].right = view; append_child(p, body, snapshot);
        let element = p.types[t.element];
        if element.kind == TY_INT && element.count == 8 && (element.flags & TF_UNSIGNED) != 0 {
            if quoted { render_escape(p, body, out, sequence, token); } else { render_raw(p, body, out, operation_ident(p, sequence), token); }
            return function_node;
        }
        render_text(p, body, out, "[", token);
        let index = operation_name(p, token, "__goose_render_index"); let item = operation_name(p, token, "__goose_render_item");
        let loop_node = new_node(p, N_FOR, token); p.nodes[loop_node].left = operation_ident(p, sequence);
        let binding = new_node(p, N_BINDING, item);
        if element.kind != TY_REF { p.nodes[binding].flags |= F_REFERENCE; }
        append_child(p, loop_node, binding); append_child(p, loop_node, new_node(p, N_BINDING, index));
        let loop_body = new_node(p, N_BLOCK, token); p.nodes[loop_node].right = loop_body; append_child(p, body, loop_node);
        let separator = new_node(p, N_IF, token);
        p.nodes[separator].left = operation_binary(p, T_NEQ, operation_ident(p, index), operation_integer(p, 0, token), token);
        let separated = new_node(p, N_BLOCK, token); p.nodes[separator].right = separated; append_child(p, loop_body, separator); render_text(p, separated, out, ", ", token);
        let child = render_function(p, cache, hooks, t.element, render_reference(p, t.element, const_flags), true);
        render_call(p, loop_body, p.nodes[child].token, out, operation_ident(p, item)); render_text(p, body, out, "]", token);
    } else if t.kind == TY_STRUCT {
        let empty = t.first < 0; var field = t.first;
        if t.pool >= 0 && p.nodes[t.declaration].kind == N_VARIANT { render_variant_label(p, body, out, type_id, token, empty); }
        else { render_label(p, body, out, type_id, token); }
        if empty && t.pool >= 0 { return function_node; }
        render_text(p, body, out, " { ", token); field = t.first; var separator = false;
        while field >= 0 {
            let f = p.nodes[field];
            if (f.flags & F_PAD) == 0 {
                if separator { render_text(p, body, out, ", ", token); } separator = true;
                let child = render_function(p, cache, hooks, f.type_id, render_reference(p, f.type_id, const_flags), true);
                render_call(p, body, p.nodes[child].token, out, operation_member(p, value, f.token));
            }
            field = f.next;
        }
        render_text(p, body, out, " }", token);
    } else if t.kind == TY_ENUM {
        var empty = t.first >= 0; var variant = t.first;
        while variant >= 0 { if p.nodes[variant].first >= 0 { empty = false; } variant = p.nodes[variant].next; }
        if empty { render_empty_enum(p, body, out, value, type_id, token); return function_node; }
        let match_node = new_node(p, N_MATCH, token); p.nodes[match_node].left = operation_ident(p, value); append_child(p, body, match_node);
        var arm_variant = t.first;
        while arm_variant >= 0 {
            let v = p.nodes[arm_variant]; let payload = operation_name(p, token, "__goose_render_payload");
            let arm = new_node(p, N_ARM, v.token); let pattern = new_node(p, N_PATTERN, v.token); p.nodes[arm].left = pattern;
            append_child(p, pattern, operation_ident(p, v.token));
            let arm_body = new_node(p, N_BLOCK, token); p.nodes[arm].right = arm_body; append_child(p, match_node, arm);
            if v.first >= 0 {
                let binding = new_node(p, N_BINDING, payload);
                if (t.flags & F_VARIABLE_MODE) != 0 {
                    p.nodes[binding].flags |= F_REFERENCE | F_SYNTHETIC;
                }
                p.nodes[pattern].left = binding;
                let child = render_function(p, cache, hooks, v.type_id, render_reference(p, v.type_id, const_flags), true, true);
                render_call(p, arm_body, p.nodes[child].token, out, operation_ident(p, payload));
            } else { render_variant_label(p, arm_body, out, v.type_id, token, true); }
            arm_variant = v.next;
        }
    } else { render_raw(p, body, out, operation_ident(p, value), token); }
    return function_node;
}
