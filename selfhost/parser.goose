import model;
import lexer;

// Cursors and table IDs survive recursion and table growth; borrowed elements do not.
struct ParseCursor {
    source: i64, at: i64, end: i64,
    no_record: bool = false, statement: bool = false, ended: bool = false,
    for_binding: bool = false, half_angle: bool = false,
    namespace_token: i64 = -1, file_namespace: i64 = -1,
    declaration_seen: bool = false, function: i64 = -1,
    tentative: bool = false, failed: bool = false,
}
fn parse_kind(p: Program&, c: ParseCursor&) -> i64 {
    if c.at >= c.end { return T_EOF; }
    if c.half_angle { return T_GT; }
    return p.tokens[c.at].kind;
}
fn parse_ahead(p: Program&, c: ParseCursor&, ahead: i64 = 1) -> i64 {
    if c.at + ahead >= c.end { return T_EOF; }
    return p.tokens[c.at + ahead].kind;
}
fn parse_next(p: Program&, c: ParseCursor&) -> i64 {
    let token = c.at;
    c.half_angle = false;
    if c.at + 1 < c.end { c.at++; }
    while c.at + 1 < c.end && p.tokens[c.at].kind < 0 { c.at++; }
    return token;
}
fn parse_accept(p: Program&, c: ParseCursor&, kind: i64) -> bool {
    if parse_kind(p, c) != kind { return false; }
    parse_next(p, c); return true;
}
fn parse_error(p: Program&, c: ParseCursor&, message: const u8[:]) {
    c.failed = true;
    if !c.tentative { diagnose(p, c.at, message); }
}
fn parse_expect(p: Program&, c: ParseCursor&, kind: i64, message: const u8[:]) -> i64 {
    let token = c.at;
    if !parse_accept(p, c, kind) { parse_error(p, c, message); }
    return token;
}
fn parse_node(p: Program&, kind: i64, token: i64) -> i64 {
    return new_node(p, kind, token);
}
fn parse_link(p: Program&, first: i64&, last: i64&, node: i64) {
    if node < 0 { return; }
    if first < 0 { first = node; } else { p.nodes[last].next = node; }
    last = node;
}
fn parse_word(p: Program&, c: ParseCursor&, word: const u8[:]) -> bool {
    return parse_kind(p, c) == T_IDENT && token_is(p, c.at, word);
}
fn parse_from(p: Program&, c: ParseCursor&) -> bool {
    return parse_word(p, c, "from") && (parse_ahead(p, c) == T_IDENT || parse_ahead(p, c) == T_COLONCOLON);
}
fn parse_inline(p: Program&, c: ParseCursor&) -> bool {
    let next = parse_ahead(p, c);
    return parse_word(p, c, "inline") && (next == T_FN || next == T_RECURSIVE || next == T_THREADFN);
}
fn parse_checkfree(p: Program&, c: ParseCursor&) -> bool {
    let next = parse_ahead(p, c);
    return parse_word(p, c, "checkfree") && (next == T_FN || next == T_RECURSIVE || next == T_THREADFN || next == T_SIMD || next == T_EXTERN || next == T_IDENT);
}
fn parse_qualified(p: Program&, c: ParseCursor&, declaration: bool = false) -> i64 {
    let start = c.at;
    let absolute = parse_accept(p, c, T_COLONCOLON);
    var token = parse_expect(p, c, T_IDENT, "expected identifier");
    if !absolute && parse_accept(p, c, T_COLONCOLON) {
        if declaration { c.namespace_token = token; }
        token = parse_expect(p, c, T_IDENT, "expected identifier after ::");
    } else if absolute && declaration { c.namespace_token = -1; }
    let id = parse_node(p, N_NAME, token);
    p.nodes[id].integer = start;
    p.nodes[id].aux = c.at - start;
    p.nodes[id].scope = c.namespace_token;
    return id;
}
fn parse_angle_end(p: Program&, c: ParseCursor&) {
    if parse_accept(p, c, T_GT) { return; }
    if parse_kind(p, c) == T_SHR { c.half_angle = true; return; }
    parse_error(p, c, "expected > to close type argument list");
}
fn parse_duplicate(p: Program&, c: ParseCursor&, first: i64, token: i64) {
    var id = first;
    while id >= 0 {
        if same_name(p, p.nodes[id].token, token) { parse_error(p, c, "duplicate declaration name"); return; }
        id = p.nodes[id].next;
    }
}
fn parse_resync(p: Program&, c: ParseCursor&, declaration: bool) {
    var braces = 0;
    loop {
        let kind = parse_kind(p, c);
        if kind == T_EOF { return; }
        if kind == T_RCURLY && braces == 0 { if declaration { parse_next(p, c); } return; }
        parse_next(p, c);
        if kind == T_LCURLY { braces++; }
        if kind == T_RCURLY { braces--; if declaration && braces == 0 { return; } }
        if kind == T_SEMI && braces == 0 { return; }
    }
}
recursive fn parse_type(p: Program&, c: ParseCursor&) -> i64 {
    let token = c.at;
    var constant = parse_accept(p, c, T_CONST);
    var id: i64 = -1;
    let kind = parse_kind(p, c);
    if kind == T_LPAREN {
        parse_next(p, c);
        let saved = c.for_binding; c.for_binding = false;
        id = parse_type(p, c); c.for_binding = saved;
        parse_expect(p, c, T_RPAREN, "expected ) after type");
    } else if kind == T_FN {
        parse_next(p, c);
        id = parse_node(p, N_TYPE_FN, token);
        if parse_accept(p, c, T_LPAREN) {
            p.nodes[id].flags |= F_EXPLICIT_PARAMS;
            let args = parse_type_list(p, c, T_RPAREN);
            p.nodes[id].first = args;
            parse_expect(p, c, T_RPAREN, "expected ) after function argument types");
            if parse_accept(p, c, T_ARROW) {
                let multiple = parse_accept(p, c, T_LPAREN);
                var results: i64 = -1;
                if multiple {
                    results = parse_type_list(p, c, T_RPAREN);
                    parse_expect(p, c, T_RPAREN, "expected ) after function result types");
                } else { results = parse_type(p, c); }
                p.nodes[id].left = results;
            }
        }
    } else if kind == T_IDENT || kind == T_COLONCOLON {
        id = parse_qualified(p, c);
        p.nodes[id].kind = N_TYPE_NAME;
        if parse_accept(p, c, T_LT) {
            let arguments = parse_type_list(p, c, T_GT);
            p.nodes[id].first = arguments;
            parse_angle_end(p, c);
        }
    } else if kind >= T_TBOOL && kind <= T_TF64 {
        id = parse_node(p, N_TYPE_NAME, parse_next(p, c));
        if !c.for_binding && (parse_kind(p, c) == T_IN || parse_word(p, c, "upto")) {
            let upto = parse_word(p, c, "upto"); parse_next(p, c);
            if kind < T_TU8 || kind > T_TU64 { parse_error(p, c, "an index type requires u8, u16, u32 or u64"); }
            let bound = parse_qualified(p, c); p.nodes[id].third = bound;
            p.nodes[id].flags |= F_INDEX_TYPE;
            if upto { p.nodes[id].flags |= F_BOUND_TYPE; }
            let postfix = parse_kind(p, c);
            if postfix == T_LBRACKET || postfix == T_BITAND || postfix == T_QUESTION || postfix == T_DOTDOT || postfix == T_DOT {
                parse_error(p, c, "an index type takes no postfix; parenthesize the index type");
            }
            if constant { p.nodes[id].flags |= TF_CONST; }
            return id;
        }
    } else {
        parse_error(p, c, "expected a type");
        return parse_node(p, N_EMPTY, parse_next(p, c));
    }
    loop {
        let postfix = parse_kind(p, c);
        if postfix == T_LBRACKET {
            let at = parse_next(p, c);
            let array = parse_node(p, N_TYPE_ARRAY, at);
            p.nodes[array].left = id;
            if parse_accept(p, c, T_COLON) {
                p.nodes[array].integer = A_SLICE;
                if constant { p.nodes[array].flags |= TF_CONST; constant = false; }
            } else if parse_kind(p, c) == T_RBRACKET { p.nodes[array].integer = A_VAR; }
            else if parse_accept(p, c, T_GT) {
                parse_expect(p, c, T_DOTDOT, "expected .. in growable array type");
                p.nodes[array].integer = A_GROW;
                if parse_accept(p, c, T_LT) { p.nodes[array].integer = A_GROWSHRINK; }
            } else if parse_accept(p, c, T_DOTDOT) {
                p.nodes[array].integer = A_LIMITED;
                if parse_kind(p, c) != T_RBRACKET {
                    let size = parse_subexpr(p, c, false); p.nodes[array].right = size;
                }
            } else if parse_kind(p, c) >= T_TBOOL && parse_kind(p, c) <= T_TF64 {
                let storage_kind = parse_kind(p, c);
                if storage_kind != T_TVARINT && (storage_kind < T_TU8 || storage_kind > T_TU64) {
                    parse_error(p, c, "array length storage requires an unsigned integer or varint");
                }
                let storage = parse_node(p, N_TYPE_NAME, parse_next(p, c));
                p.nodes[array].third = storage; p.nodes[array].integer = A_VAR;
            } else {
                let size = parse_subexpr(p, c, false); p.nodes[array].right = size;
                p.nodes[array].integer = A_FIXED;
            }
            parse_expect(p, c, T_RBRACKET, "expected ] after array type"); id = array;
        } else if postfix == T_BITAND || postfix == T_QUESTION {
            let at = parse_next(p, c);
            if postfix == T_QUESTION && p.nodes[id].kind == N_TYPE_REF {
                if (p.nodes[id].flags & TF_OPTIONAL) != 0 { parse_error(p, c, "type is already optional"); }
                p.nodes[id].flags |= TF_OPTIONAL;
            } else {
                let reference = parse_node(p, N_TYPE_REF, at); p.nodes[reference].left = id;
                if constant { p.nodes[reference].flags |= TF_CONST; constant = false; }
                if postfix == T_QUESTION { p.nodes[reference].flags |= TF_OPTIONAL; }
                if postfix == T_BITAND && parse_accept(p, c, T_LT) {
                    let storage_kind = parse_kind(p, c);
                    if storage_kind != T_TVARINT && (storage_kind < T_TU8 || storage_kind > T_TU64) {
                        parse_error(p, c, "relative reference width requires an unsigned integer or varint");
                    }
                    let storage = parse_node(p, N_TYPE_NAME, parse_next(p, c)); p.nodes[reference].right = storage;
                    if parse_accept(p, c, T_IN) {
                        let pool = parse_qualified(p, c); p.nodes[reference].third = pool;
                    }
                    parse_angle_end(p, c);
                }
                id = reference;
            }
        } else if postfix == T_DOTDOT {
            parse_next(p, c);
            if p.nodes[id].kind != N_TYPE_NAME { parse_error(p, c, "variable mode applies only to ADT type names"); }
            if (p.nodes[id].flags & F_VARIABLE_MODE) != 0 { parse_error(p, c, "type is already variable-mode"); }
            p.nodes[id].flags |= F_VARIABLE_MODE;
        } else if postfix == T_DOT {
            parse_next(p, c);
            let variant = parse_node(p, N_TYPE_NAME, parse_expect(p, c, T_IDENT, "expected variant type name"));
            p.nodes[variant].left = id; id = variant;
        } else { break; }
    }
    if constant { p.nodes[id].flags |= TF_CONST; }
    return id;
}
recursive fn parse_type_list(p: Program&, c: ParseCursor&, closing: i64) -> i64 {
    var first: i64 = -1; var last: i64 = -1;
    while parse_kind(p, c) != closing && parse_kind(p, c) != T_EOF && !(closing == T_GT && parse_kind(p, c) == T_SHR) {
        let at = c.at; let half = c.half_angle;
        let item = parse_type(p, c); parse_link(p, first, last, item);
        if at == c.at && half == c.half_angle { parse_error(p, c, "type list made no progress"); break; }
        if !parse_accept(p, c, T_COMMA) { break; }
    }
    return first;
}
fn parse_precedence(kind: i64) -> i64 {
    if kind == T_MUL || kind == T_DIV || kind == T_MOD { return 10; }
    if kind == T_PLUS || kind == T_MINUS { return 9; }
    if kind == T_SHL || kind == T_SHR { return 8; }
    if kind == T_BITAND { return 7; }
    if kind == T_XOR { return 6; }
    if kind == T_BITOR { return 5; }
    if kind == T_LT || kind == T_GT || kind == T_LTEQ || kind == T_GTEQ { return 4; }
    if kind == T_EQ || kind == T_NEQ || kind == T_DOTEQ || kind == T_DOTNEQ { return 3; }
    if kind == T_ANDAND { return 2; }
    if kind == T_OROR { return 1; }
    return 0;
}
recursive fn parse_subexpr(p: Program&, c: ParseCursor&, restricted: bool) -> i64 {
    let no_record = c.no_record; let statement = c.statement; let ended = c.ended;
    c.no_record = restricted; c.statement = false; c.ended = false;
    let id = parse_expr(p, c);
    c.no_record = no_record; c.statement = statement; c.ended = ended;
    return id;
}
recursive fn parse_binary(p: Program&, c: ParseCursor&, minimum: i64) -> i64 {
    var left = parse_unary(p, c);
    loop {
        if c.ended { return left; }
        let precedence = parse_precedence(parse_kind(p, c));
        if precedence == 0 || precedence < minimum { return left; }
        let token = parse_next(p, c);
        let statement = c.statement; let ended = c.ended;
        c.statement = false; c.ended = false;
        let right = parse_binary(p, c, precedence + 1);
        c.statement = statement; c.ended = ended;
        let binary = parse_node(p, N_BINARY, token);
        p.nodes[binary].left = left; p.nodes[binary].right = right;
        p.nodes[binary].integer = p.tokens[token].kind; left = binary;
    }
}
recursive fn parse_unary(p: Program&, c: ParseCursor&) -> i64 {
    let kind = parse_kind(p, c);
    if kind == T_MINUS || kind == T_NOT || kind == T_BITNOT || kind == T_BITAND {
        let token = parse_next(p, c);
        let statement = c.statement; let ended = c.ended;
        c.statement = false; c.ended = false;
        let value = parse_unary(p, c);
        c.statement = statement; c.ended = ended;
        let id = parse_node(p, N_UNARY, token);
        p.nodes[id].left = value; p.nodes[id].integer = kind; return id;
    }
    return parse_postfix(p, c);
}
recursive fn parse_expr_list(p: Program&, c: ParseCursor&, closing: i64) -> i64 {
    var first: i64 = -1; var last: i64 = -1;
    while parse_kind(p, c) != closing && parse_kind(p, c) != T_EOF {
        let at = c.at;
        let item = parse_subexpr(p, c, false); parse_link(p, first, last, item);
        if c.at == at { parse_error(p, c, "expression list made no progress"); break; }
        if !parse_accept(p, c, T_COMMA) { break; }
    }
    return first;
}
recursive fn parse_record(p: Program&, c: ParseCursor&, type_node: i64, fragment: bool = false) -> i64 {
    let token = parse_expect(p, c, T_LCURLY, "expected { in record literal");
    let id = parse_node(p, N_RECORD, token); p.nodes[id].left = type_node;
    var first: i64 = -1; var last: i64 = -1; var named = 0; var positional = 0; var expanded = false;
    while parse_kind(p, c) != T_RCURLY && parse_kind(p, c) != T_EOF {
        let at = c.at;
        if parse_accept(p, c, T_DOTDOT) {
            if fragment { parse_error(p, c, "trailing .. belongs to the whole constructor"); }
            p.nodes[id].flags |= F_DEFAULT; break;
        }
        var init: i64 = -1;
        if parse_kind(p, c) == T_CONST && parse_ahead(p, c) == T_FOR {
            init = parse_const_for(p, c, 1); expanded = true;
        } else {
            var name: i64 = -1;
            if parse_kind(p, c) == T_IDENT && parse_ahead(p, c) == T_COLON {
                name = parse_next(p, c); parse_next(p, c); named++;
            } else { positional++; }
            let value = parse_subexpr(p, c, false);
            init = parse_node(p, N_BINDING, name); p.nodes[init].right = value;
        }
        parse_link(p, first, last, init);
        if c.at == at { parse_error(p, c, "record initializer made no progress"); break; }
        if !parse_accept(p, c, T_COMMA) { break; }
    }
    parse_expect(p, c, T_RCURLY, "expected } after record literal");
    if !expanded && named > 0 && positional > 0 { parse_error(p, c, "record literal mixes named and positional initializers"); }
    p.nodes[id].first = first; p.nodes[id].last = last; return id;
}
recursive fn parse_type_arguments(p: Program&, c: ParseCursor&) -> i64 {
    let saved = c; let count = p.nodes.len;
    c.tentative = true; c.failed = false;
    parse_next(p, c);
    let arguments = parse_type_list(p, c, T_GT); parse_angle_end(p, c);
    var accepted = arguments >= 0 && !c.failed && (parse_kind(p, c) == T_LPAREN || !c.no_record && parse_kind(p, c) == T_LCURLY);
    if !accepted && !c.failed && !c.no_record && parse_kind(p, c) == T_DOT {
        accepted = parse_ahead(p, c) == T_IDENT && parse_ahead(p, c, 2) == T_LCURLY;
    }
    if !accepted { c = saved; p.nodes.resize(count); return -1; }
    c.tentative = saved.tentative; c.failed = saved.failed; return arguments;
}
recursive fn parse_call(p: Program&, c: ParseCursor&, callee: i64) -> i64 {
    parse_expect(p, c, T_LPAREN, "expected ( in call");
    let token = p.nodes[callee].token;
    let arguments = parse_expr_list(p, c, T_RPAREN);
    parse_expect(p, c, T_RPAREN, "expected ) after call arguments");
    let call = parse_node(p, N_CALL, token);
    p.nodes[call].left = callee; p.nodes[call].first = arguments;
    if parse_kind(p, c) == T_LCURLY && !c.no_record {
        let trailing = parse_function_value(p, c); p.nodes[call].third = trailing;
        if c.statement { c.ended = true; }
    }
    return call;
}
recursive fn parse_postfix(p: Program&, c: ParseCursor&) -> i64 {
    var value = parse_primary(p, c);
    loop {
        if c.ended { return value; }
        let kind = parse_kind(p, c);
        if kind == T_LPAREN { value = parse_call(p, c, value); }
        else if kind == T_LBRACKET {
            let token = parse_next(p, c); var low: i64 = -1; var high: i64 = -1; var flags: i64 = 0;
            if parse_kind(p, c) != T_DOTDOT {
                if parse_accept(p, c, T_XOR) { flags |= F_FROM_END; }
                low = parse_subexpr(p, c, false);
            }
            var node_kind = N_INDEX;
            if parse_accept(p, c, T_DOTDOT) {
                node_kind = N_SLICE;
                if parse_kind(p, c) != T_RBRACKET {
                    if parse_accept(p, c, T_XOR) { flags |= F_TO_END; }
                    high = parse_subexpr(p, c, false);
                }
            } else if flags != 0 { parse_error(p, c, "^ bounds are only valid in slices"); }
            parse_expect(p, c, T_RBRACKET, "expected ] after index or slice");
            let id = parse_node(p, node_kind, token);
            p.nodes[id].left = value; p.nodes[id].right = low; p.nodes[id].third = high; p.nodes[id].flags = flags; value = id;
        } else if kind == T_DOT {
            parse_next(p, c);
            let token = parse_expect(p, c, T_IDENT, "expected field or variant name");
            let id = parse_node(p, N_MEMBER, token); p.nodes[id].left = value; p.nodes[id].scope = c.namespace_token;
            if parse_kind(p, c) == T_LCURLY && !c.no_record && p.nodes[value].kind == N_NAME {
                p.nodes[id].kind = N_TYPE_NAME; p.nodes[value].kind = N_TYPE_NAME;
                value = parse_record(p, c, id);
            } else { value = id; }
        } else if kind == T_AS {
            let token = parse_next(p, c); let unchecked = parse_accept(p, c, T_NOT);
            let type_node = parse_type(p, c); let id = parse_node(p, N_CAST, token);
            p.nodes[id].left = value; p.nodes[id].right = type_node;
            if unchecked { p.nodes[id].flags = F_UNSIGNED; }
            value = id;
        } else { return value; }
    }
}
recursive fn parse_primary(p: Program&, c: ParseCursor&) -> i64 {
    let kind = parse_kind(p, c); let token = c.at;
    if kind == T_IDENT || kind == T_COLONCOLON {
        let id = parse_qualified(p, c);
        if parse_kind(p, c) == T_LT {
            let arguments = parse_type_arguments(p, c);
            if arguments >= 0 {
                p.nodes[id].first = arguments;
                if parse_kind(p, c) == T_LPAREN { return parse_call(p, c, id); }
                p.nodes[id].kind = N_TYPE_NAME;
                var type_node = id;
                if parse_accept(p, c, T_DOT) {
                    let variant = parse_node(p, N_TYPE_NAME, parse_expect(p, c, T_IDENT, "expected variant literal name"));
                    p.nodes[variant].left = id; type_node = variant;
                }
                return parse_record(p, c, type_node);
            }
        }
        if parse_kind(p, c) == T_LCURLY && !c.no_record {
            p.nodes[id].kind = N_TYPE_NAME; return parse_record(p, c, id);
        }
        return id;
    }
    if kind == T_INTLIT || kind == T_FLTLIT || kind == T_STRLIT || kind == T_TRUE || kind == T_FALSE || kind == T_NULLLIT || kind == T_SELF {
        parse_next(p, c); var node_kind = N_INTEGER;
        if kind == T_FLTLIT { node_kind = N_FLOAT; }
        else if kind == T_STRLIT { node_kind = N_STRING; }
        else if kind == T_TRUE || kind == T_FALSE { node_kind = N_BOOL; }
        else if kind == T_NULLLIT { node_kind = N_NULL; }
        else if kind == T_SELF { node_kind = N_NAME; }
        let id = parse_node(p, node_kind, token);
        p.nodes[id].integer = p.tokens[token].integer; p.nodes[id].float_value = p.tokens[token].float_value;
        if kind == T_INTLIT && (p.tokens[token].flags & 1) != 0 { p.nodes[id].flags |= F_UNSIGNED; }
        if kind == T_STRLIT { p.nodes[id].flags = p.tokens[token].flags; }
        if kind == T_TRUE { p.nodes[id].integer = 1; }
        p.nodes[id].scope = c.namespace_token; return id;
    }
    if kind == T_LPAREN {
        parse_next(p, c); let id = parse_subexpr(p, c, false);
        parse_expect(p, c, T_RPAREN, "expected ) after expression"); return id;
    }
    if kind == T_LBRACKET {
        parse_next(p, c); let id = parse_node(p, N_ARRAY, token);
        var first: i64 = -1; var last: i64 = -1;
        if parse_accept(p, c, T_DOTDOT) {
            let capacity = parse_subexpr(p, c, false); p.nodes[id].third = capacity;
        } else if parse_kind(p, c) != T_RBRACKET {
            let item = parse_subexpr(p, c, false); parse_link(p, first, last, item);
            if parse_accept(p, c, T_SEMI) {
                let count = parse_subexpr(p, c, false); p.nodes[id].right = count; p.nodes[id].kind = N_FILL;
            } else {
                while parse_accept(p, c, T_COMMA) && parse_kind(p, c) != T_RBRACKET && parse_kind(p, c) != T_EOF {
                    let at = c.at; let element = parse_subexpr(p, c, false); parse_link(p, first, last, element);
                    if at == c.at { break; }
                }
            }
        }
        p.nodes[id].first = first; p.nodes[id].last = last;
        parse_expect(p, c, T_RBRACKET, "expected ] after array literal"); return id;
    }
    parse_error(p, c, "expected an expression");
    return parse_node(p, N_EMPTY, parse_next(p, c));
}
recursive fn parse_expr(p: Program&, c: ParseCursor&) -> i64 {
    let token = c.at; let kind = parse_kind(p, c); var id: i64 = -1;
    if kind == T_IF {
        parse_next(p, c); let condition = parse_subexpr(p, c, true); let yes = parse_block(p, c);
        var no: i64 = -1;
        if parse_accept(p, c, T_ELSE) {
            if parse_kind(p, c) == T_IF { no = parse_expr(p, c); } else { no = parse_block(p, c); }
        }
        id = parse_node(p, N_IF, token); p.nodes[id].left = condition; p.nodes[id].right = yes; p.nodes[id].third = no;
    } else if kind == T_LCURLY || kind == T_BLOCK {
        if kind == T_BLOCK { parse_next(p, c); }
        id = parse_block(p, c);
        if kind == T_BLOCK { p.nodes[id].flags |= F_EARLY; }
    } else if kind == T_WHILE {
        parse_next(p, c); let condition = parse_subexpr(p, c, true); let body = parse_block(p, c);
        id = parse_node(p, N_WHILE, token); p.nodes[id].left = condition; p.nodes[id].right = body;
    } else if kind == T_LOOP {
        parse_next(p, c); let body = parse_block(p, c); id = parse_node(p, N_LOOP, token); p.nodes[id].right = body;
    } else if kind == T_FOR { id = parse_for(p, c); }
    else if kind == T_MATCH { id = parse_match(p, c); }
    else if kind == T_RETURN {
        parse_next(p, c); var first: i64 = -1; var last: i64 = -1;
        if parse_kind(p, c) != T_SEMI && parse_kind(p, c) != T_RCURLY && parse_kind(p, c) != T_EOF && !parse_from(p, c) {
            loop {
                let value = parse_subexpr(p, c, c.no_record); parse_link(p, first, last, value);
                if !parse_accept(p, c, T_COMMA) { break; }
            }
        }
        var target: i64 = -1;
        if parse_from(p, c) { parse_next(p, c); target = parse_qualified(p, c); }
        id = parse_node(p, N_RETURN, token); p.nodes[id].first = first; p.nodes[id].last = last; p.nodes[id].left = target;
        if target >= 0 { p.nodes[id].flags |= F_NONLOCAL; }
        return id;
    } else if kind == T_BREAK {
        parse_next(p, c); var value: i64 = -1;
        if parse_kind(p, c) != T_SEMI && parse_kind(p, c) != T_RCURLY && parse_kind(p, c) != T_EOF { value = parse_subexpr(p, c, c.no_record); }
        id = parse_node(p, N_BREAK, token); p.nodes[id].left = value; return id;
    } else if kind == T_CONTINUE { return parse_node(p, N_CONTINUE, parse_next(p, c)); }
    else if kind == T_GUARD {
        parse_error(p, c, "guard is a statement that guards the rest of its block");
        return parse_node(p, N_EMPTY, parse_next(p, c));
    } else { return parse_binary(p, c, 1); }
    if c.statement { c.ended = true; } return id;
}
recursive fn parse_for(p: Program&, c: ParseCursor&) -> i64 {
    let token = parse_next(p, c); let byref = parse_accept(p, c, T_BITAND);
    var first: i64 = -1; var last: i64 = -1;
    let saved = c.for_binding; c.for_binding = true;
    for i in 0..2 {
        let name = parse_expect(p, c, T_IDENT, "expected for binding name");
        let binding = parse_node(p, N_BINDING, name);
        if i == 0 && byref { p.nodes[binding].flags |= F_REFERENCE; }
        if parse_accept(p, c, T_COLON) { let type_node = parse_type(p, c); p.nodes[binding].left = type_node; }
        parse_duplicate(p, c, first, name); parse_link(p, first, last, binding);
        if i != 0 || !parse_accept(p, c, T_COMMA) { break; }
    }
    c.for_binding = saved;
    parse_expect(p, c, T_IN, "expected in after for bindings");
    var iterable = parse_subexpr(p, c, true);
    if parse_accept(p, c, T_DOTDOT) {
        let end = parse_subexpr(p, c, true); let range = parse_node(p, N_RANGE, token);
        p.nodes[range].left = iterable; p.nodes[range].right = end; p.nodes[range].integer = T_DOTDOT; iterable = range;
    }
    let body = parse_block(p, c); let id = parse_node(p, N_FOR, token);
    p.nodes[id].first = first; p.nodes[id].last = last; p.nodes[id].left = iterable; p.nodes[id].right = body;
    if byref { p.nodes[id].flags |= F_REFERENCE; } return id;
}
recursive fn parse_pattern_bound(p: Program&, c: ParseCursor&) -> i64 {
    let token = c.at; let negative = parse_accept(p, c, T_MINUS); var id: i64 = -1;
    if parse_kind(p, c) == T_IDENT || parse_kind(p, c) == T_COLONCOLON { id = parse_qualified(p, c); }
    else if parse_kind(p, c) == T_INTLIT {
        let value_token = parse_next(p, c); id = parse_node(p, N_INTEGER, value_token);
        p.nodes[id].integer = p.tokens[value_token].integer;
        if (p.tokens[value_token].flags & 1) != 0 { p.nodes[id].flags |= F_UNSIGNED; }
        if negative && p.tokens[value_token].integer != -9223372036854775808 && (p.tokens[value_token].flags & 1) != 0 {
            parse_error(p, c, "negated literal too large for i64");
        }
    } else { parse_error(p, c, "expected integer constant in match pattern"); id = parse_node(p, N_EMPTY, parse_next(p, c)); }
    if negative {
        let unary = parse_node(p, N_UNARY, token); p.nodes[unary].left = id; p.nodes[unary].integer = T_MINUS; return unary;
    }
    return id;
}
recursive fn parse_pattern(p: Program&, c: ParseCursor&) -> i64 {
    let id = parse_node(p, N_PATTERN, c.at);
    if parse_word(p, c, "_") {
        parse_next(p, c); p.nodes[id].flags |= F_DEFAULT;
        if parse_kind(p, c) == T_COMMA { parse_error(p, c, "_ cannot be listed with other patterns"); }
        return id;
    }
    var first: i64 = -1; var last: i64 = -1;
    loop {
        var item = parse_pattern_bound(p, c);
        if parse_accept(p, c, T_DOTDOT) {
            let high = parse_pattern_bound(p, c); let range = parse_node(p, N_RANGE, p.nodes[item].token);
            p.nodes[range].left = item; p.nodes[range].right = high; item = range;
        }
        parse_link(p, first, last, item);
        if p.nodes[item].kind == N_NAME && (parse_kind(p, c) == T_BITAND || parse_kind(p, c) == T_IDENT) {
            if first != last { parse_error(p, c, "a list of patterns binds no payload"); }
            let byref = parse_accept(p, c, T_BITAND);
            let name = parse_expect(p, c, T_IDENT, "expected match payload binding"); let binder = parse_node(p, N_BINDING, name);
            if byref { p.nodes[binder].flags |= F_REFERENCE; }
            p.nodes[id].left = binder;
            if parse_kind(p, c) == T_COMMA { parse_error(p, c, "a list of patterns binds no payload"); }
            break;
        }
        if !parse_accept(p, c, T_COMMA) { break; }
        if parse_word(p, c, "_") { parse_error(p, c, "_ cannot be listed with other patterns"); parse_next(p, c); break; }
    }
    p.nodes[id].first = first; p.nodes[id].last = last; return id;
}
recursive fn parse_arms(p: Program&, c: ParseCursor&, owner: i64) {
    while parse_kind(p, c) != T_RCURLY && parse_kind(p, c) != T_EOF {
        let at = c.at; var arm: i64 = -1;
        if parse_kind(p, c) == T_CONST && parse_ahead(p, c) == T_FOR { arm = parse_const_for(p, c, 2); }
        else {
            let pattern = parse_pattern(p, c);
            parse_expect(p, c, T_FATARROW, "expected => after match pattern");
            let body = parse_subexpr(p, c, false); arm = parse_node(p, N_ARM, at);
            p.nodes[arm].left = pattern; p.nodes[arm].right = body;
        }
        append_child(p, owner, arm);
        if c.at == at { parse_error(p, c, "match arm made no progress"); break; }
        if !parse_accept(p, c, T_COMMA) { break; }
    }
}
recursive fn parse_match(p: Program&, c: ParseCursor&) -> i64 {
    let token = parse_next(p, c); let value = parse_subexpr(p, c, true);
    let id = parse_node(p, N_MATCH, token); p.nodes[id].left = value;
    parse_expect(p, c, T_LCURLY, "expected { after match value"); parse_arms(p, c, id);
    parse_expect(p, c, T_RCURLY, "expected } after match arms");
    if p.nodes[id].first < 0 { parse_error(p, c, "match must have at least one arm"); } return id;
}
recursive fn parse_const_for(p: Program&, c: ParseCursor&, context: i64) -> i64 {
    let token = parse_expect(p, c, T_CONST, "expected const"); parse_expect(p, c, T_FOR, "expected for after const");
    let id = parse_node(p, N_CONST_FOR, token);
    parse_expect(p, c, T_LT, "expected < after const for");
    var first: i64 = -1; var last: i64 = -1; var count = 0;
    while parse_kind(p, c) != T_GT && parse_kind(p, c) != T_SHR && parse_kind(p, c) != T_EOF {
        let at = c.at; let name = parse_expect(p, c, T_IDENT, "expected const for binding");
        parse_duplicate(p, c, first, name); let binder = parse_node(p, N_BINDING, name);
        parse_link(p, first, last, binder); count++;
        if c.at == at || !parse_accept(p, c, T_COMMA) { break; }
    }
    p.nodes[id].first = first; p.nodes[id].last = last; parse_angle_end(p, c);
    parse_expect(p, c, T_IN, "expected in after const for bindings");
    var source: i64 = -1; var source_kind = 0;
    if parse_accept(p, c, T_LBRACKET) {
        source = parse_expr_list(p, c, T_RBRACKET); parse_expect(p, c, T_RBRACKET, "expected ] after const for constants");
    } else {
        if parse_word(p, c, "fields") { source_kind = 1; }
        else if parse_word(p, c, "types") { source_kind = 2; }
        else if parse_word(p, c, "variants") { source_kind = 3; }
        else { parse_error(p, c, "const for source requires fields<T>, variants<E>, types<...> or [constants]"); }
        parse_next(p, c); parse_expect(p, c, T_LT, "expected < after const for source");
        source = parse_type_list(p, c, T_GT); parse_angle_end(p, c);
        if (source_kind == 1 || source_kind == 3) && (source < 0 || p.nodes[source].next >= 0) {
            parse_error(p, c, "fields and variants require exactly one type");
        }
    }
    var arity = 1; if source_kind == 1 || source_kind == 3 { arity = 2; }
    if count != arity { parse_error(p, c, "const for source has the wrong number of bindings"); }
    p.nodes[id].left = source; p.nodes[id].integer = source_kind;
    var body: i64 = -1;
    if context == 1 { body = parse_record(p, c, -1, true); }
    else if context == 2 {
        let open = parse_expect(p, c, T_LCURLY, "expected { before const for arms"); body = parse_node(p, N_MATCH, open);
        parse_arms(p, c, body); parse_expect(p, c, T_RCURLY, "expected } after const for arms");
    } else { body = parse_block(p, c); }
    p.nodes[id].right = body; return id;
}
recursive fn parse_generics(p: Program&, c: ParseCursor&) -> i64 {
    if !parse_accept(p, c, T_LT) { return -1; }
    var first: i64 = -1; var last: i64 = -1;
    loop {
        let at = c.at; let token = parse_expect(p, c, T_IDENT, "expected type parameter name");
        parse_duplicate(p, c, first, token); let generic = parse_node(p, N_TYPE_PARAM, token);
        if parse_accept(p, c, T_COLON) { let bound = parse_type(p, c); p.nodes[generic].left = bound; }
        parse_link(p, first, last, generic);
        if c.at == at || !parse_accept(p, c, T_COMMA) || parse_kind(p, c) == T_GT || parse_kind(p, c) == T_SHR { break; }
    }
    parse_angle_end(p, c); return first;
}
recursive fn parse_parameters(p: Program&, c: ParseCursor&, closing: i64, defaults: bool) -> i64 {
    var first: i64 = -1; var last: i64 = -1; var default_seen = false;
    while parse_kind(p, c) != closing && parse_kind(p, c) != T_EOF {
        let at = c.at; let mutable = parse_accept(p, c, T_VAR);
        let token = parse_expect(p, c, T_IDENT, "expected parameter name");
        parse_duplicate(p, c, first, token); let param = parse_node(p, N_PARAM, token);
        if mutable { p.nodes[param].flags |= F_VAR; }
        if parse_accept(p, c, T_COLON) { let type_node = parse_type(p, c); p.nodes[param].left = type_node; }
        if defaults && parse_accept(p, c, T_ASSIGN) {
            if p.nodes[param].left < 0 { parse_error(p, c, "an untyped parameter cannot have a default"); }
            let value = parse_subexpr(p, c, false); p.nodes[param].right = value; default_seen = true;
        } else if default_seen { parse_error(p, c, "only trailing parameters may have defaults"); }
        parse_link(p, first, last, param);
        if c.at == at || !parse_accept(p, c, T_COMMA) { break; }
    }
    return first;
}
recursive fn parse_function_value(p: Program&, c: ParseCursor&) -> i64 {
    let token = parse_expect(p, c, T_LCURLY, "expected { in function value");
    var params: i64 = -1; var explicit_params = false;
    if parse_kind(p, c) == T_IDENT || parse_kind(p, c) == T_VAR {
        let saved = c; let count = p.nodes.len;
        c.tentative = true; c.failed = false;
        params = parse_parameters(p, c, T_FATARROW, false);
        if !c.failed && parse_accept(p, c, T_FATARROW) {
            explicit_params = true; c.tentative = saved.tentative; c.failed = saved.failed;
            // Duplicate names are checked again now that the prefix is committed.
            var a = params;
            while a >= 0 {
                var b = p.nodes[a].next;
                while b >= 0 {
                    if same_name(p, p.nodes[a].token, p.nodes[b].token) { parse_error(p, c, "duplicate parameter name"); }
                    b = p.nodes[b].next;
                }
                a = p.nodes[a].next;
            }
        } else { c = saved; p.nodes.resize(count); params = -1; }
    }
    let body = parse_node(p, N_BLOCK, token); parse_block_body(p, c, body);
    let id = parse_node(p, N_FUNCTION_VALUE, token); p.nodes[id].first = params; p.nodes[id].right = body;
    if explicit_params { p.nodes[id].flags |= F_EXPLICIT_PARAMS; }
    p.nodes[id].scope = c.namespace_token; return id;
}
recursive fn parse_function(p: Program&, c: ParseCursor&, nested: bool, inherited_extern: bool = false, library: i64 = -1) -> i64 {
    let start = c.at; var flags: i64 = 0; var symbol: i64 = -1;
    if inherited_extern { flags |= F_EXTERN; }
    if parse_checkfree(p, c) { flags |= F_CHECKFREE; parse_next(p, c); }
    if parse_accept(p, c, T_EXPORT) {
        flags |= F_EXPORT;
        if parse_kind(p, c) == T_STRLIT { symbol = parse_next(p, c); }
    }
    if parse_accept(p, c, T_EXTERN) {
        if inherited_extern { parse_error(p, c, "extern block members do not repeat extern"); }
        flags |= F_EXTERN;
        if parse_kind(p, c) == T_STRLIT { symbol = parse_next(p, c); }
    }
    if parse_checkfree(p, c) { flags |= F_CHECKFREE; parse_next(p, c); }
    if parse_accept(p, c, T_SIMD) { flags |= F_SIMD; }
    if parse_inline(p, c) { flags |= F_INLINE; parse_next(p, c); }
    if parse_accept(p, c, T_RECURSIVE) { flags |= F_RECURSIVE; }
    if parse_accept(p, c, T_THREADFN) { flags |= F_THREAD; }
    else { parse_expect(p, c, T_FN, "expected fn in function declaration"); }
    let saved_namespace = c.namespace_token; let name = parse_qualified(p, c, !nested);
    if nested && p.nodes[name].aux != 1 { parse_error(p, c, "nested functions cannot declare a namespace"); }
    let id = parse_node(p, N_FUNCTION, p.nodes[name].token); p.nodes[id].flags = flags;
    p.nodes[id].scope = c.namespace_token; p.nodes[id].integer = symbol;
    if library >= 0 { p.nodes[id].aux = library; }
    let generic = parse_generics(p, c); p.nodes[id].third = generic;
    parse_expect(p, c, T_LPAREN, "expected ( after function name");
    let params = parse_parameters(p, c, T_RPAREN, true); p.nodes[id].first = params;
    parse_expect(p, c, T_RPAREN, "expected ) after function parameters");
    if parse_accept(p, c, T_ARROW) {
        var first: i64 = -1; var last: i64 = -1;
        loop {
            let at = c.at; let type_node = parse_type(p, c); parse_link(p, first, last, type_node);
            if c.at == at || !parse_accept(p, c, T_COMMA) { break; }
        }
        p.nodes[id].left = first;
    }
    if (flags & F_EXTERN) != 0 {
        if parse_accept(p, c, T_ASSIGN) {
            if symbol >= 0 { parse_error(p, c, "extern function names its symbol twice"); }
            symbol = parse_expect(p, c, T_STRLIT, "extern symbol must be a string"); p.nodes[id].integer = symbol;
        }
        parse_expect(p, c, T_SEMI, "expected ; after extern signature");
    } else {
        if parse_kind(p, c) == T_ASSIGN { parse_error(p, c, "only extern functions take a symbol after their signature"); }
        let saved_function = c.function; c.function = id;
        let body = parse_block(p, c); p.nodes[id].right = body; c.function = saved_function;
    }
    if (flags & F_EXPORT) != 0 && (flags & F_EXTERN) != 0 { parse_error(p, c, "export fn cannot be extern"); }
    if nested && (flags & (F_EXTERN | F_EXPORT | F_THREAD)) != 0 { parse_error(p, c, "extern, export and thread_fn declarations require top level"); }
    if (flags & F_EXTERN) != 0 && (flags & (F_CHECKFREE | F_SIMD | F_INLINE)) != 0 { parse_error(p, c, "extern functions cannot be checkfree, simd or inline"); }
    if (flags & F_INLINE) != 0 && (flags & (F_EXPORT | F_SIMD | F_RECURSIVE | F_THREAD)) != 0 { parse_error(p, c, "inline conflicts with export, simd, recursive or thread_fn"); }
    if (flags & F_THREAD) != 0 {
        var param = params;
        while param >= 0 {
            if p.nodes[param].right >= 0 { parse_error(p, c, "thread_fn parameters cannot have defaults"); }
            param = p.nodes[param].next;
        }
    }
    c.namespace_token = saved_namespace;
    if c.at == start { parse_next(p, c); } return id;
}
recursive fn parse_variable(p: Program&, c: ParseCursor&, global: bool) -> i64 {
    var flags: i64 = 0;
    if parse_accept(p, c, T_REUSABLE) {
        flags |= F_REUSABLE;
        if parse_accept(p, c, T_LBRACKET) { parse_expect(p, c, T_RBRACKET, "expected ] after reusable["); flags |= F_REUSABLE_SLICES; }
    }
    if parse_accept(p, c, T_VAR) { flags |= F_VAR; }
    else if parse_accept(p, c, T_CONST) { flags |= F_CONST; }
    else { parse_expect(p, c, T_LET, "expected let, var or const"); }
    var first: i64 = -1; var last: i64 = -1; var names = 0;
    let saved_namespace = c.namespace_token;
    loop {
        let at = c.at; let name = parse_qualified(p, c, global);
        if !global && p.nodes[name].aux != 1 { parse_error(p, c, "local variables cannot declare a namespace"); }
        let binding = parse_node(p, N_BINDING, p.nodes[name].token); p.nodes[binding].scope = c.namespace_token;
        parse_duplicate(p, c, first, p.nodes[name].token); parse_link(p, first, last, binding); names++;
        if c.at == at || !parse_accept(p, c, T_COMMA) { break; }
    }
    let id = parse_node(p, N_VARIABLE, p.nodes[first].token); p.nodes[id].scope = c.namespace_token;
    p.nodes[id].flags = flags;
    if names > 1 { p.nodes[id].first = first; p.nodes[id].last = last; p.nodes[id].flags |= F_MULTI; }
    if parse_accept(p, c, T_COLON) { let type_node = parse_type(p, c); p.nodes[id].left = type_node; }
    let byref = parse_accept(p, c, T_DOTASSIGN);
    if byref { p.nodes[id].flags |= F_REFERENCE; }
    if byref || parse_accept(p, c, T_ASSIGN) {
        var initial: i64 = -1; var tail: i64 = -1;
        loop {
            let at = c.at; let value = parse_subexpr(p, c, false); parse_link(p, initial, tail, value);
            if c.at == at || !parse_accept(p, c, T_COMMA) { break; }
        }
        p.nodes[id].right = initial;
    }
    if global && names != 1 { parse_error(p, c, "global declarations declare a single name"); }
    if global && p.nodes[id].right < 0 && (flags & F_VAR) == 0 { parse_error(p, c, "let and const globals require an initializer"); }
    c.namespace_token = saved_namespace; return id;
}
recursive fn parse_fields(p: Program&, c: ParseCursor&, owner: i64) {
    while parse_kind(p, c) != T_RCURLY && parse_kind(p, c) != T_EOF {
        let at = c.at; var field: i64 = -1;
        if parse_accept(p, c, T_PAD) {
            field = parse_node(p, N_FIELD, at); p.nodes[field].flags |= F_PAD;
            if parse_kind(p, c) == T_INTLIT { let size = parse_next(p, c); p.nodes[field].integer = p.tokens[size].integer; }
        } else {
            let constq = parse_accept(p, c, T_CONST); let immutable = constq || parse_accept(p, c, T_LET);
            let name = parse_expect(p, c, T_IDENT, "expected field name");
            parse_duplicate(p, c, p.nodes[owner].first, name);
            parse_expect(p, c, T_COLON, "expected : after field name"); let type_node = parse_type(p, c);
            if constq { p.nodes[type_node].flags |= TF_CONST; }
            field = parse_node(p, N_FIELD, name); p.nodes[field].left = type_node;
            if immutable { p.nodes[field].flags |= F_CONST; }
            if parse_accept(p, c, T_ASSIGN) { let value = parse_subexpr(p, c, false); p.nodes[field].right = value; }
        }
        append_child(p, owner, field);
        if c.at == at { parse_error(p, c, "field declaration made no progress"); break; }
        if !parse_accept(p, c, T_COMMA) { break; }
    }
}
recursive fn parse_aggregate(p: Program&, c: ParseCursor&) -> i64 {
    let kind = parse_kind(p, c); parse_next(p, c);
    let saved_namespace = c.namespace_token; let name = parse_qualified(p, c, true);
    var node_kind = N_STRUCT; if kind == T_ENUM { node_kind = N_ENUM; }
    let id = parse_node(p, node_kind, p.nodes[name].token); p.nodes[id].scope = c.namespace_token;
    let generic = parse_generics(p, c); p.nodes[id].third = generic;
    parse_expect(p, c, T_LCURLY, "expected { in aggregate declaration");
    if kind == T_STRUCT { parse_fields(p, c, id); }
    else {
        while parse_kind(p, c) != T_RCURLY && parse_kind(p, c) != T_EOF {
            let at = c.at; let token = parse_expect(p, c, T_IDENT, "expected enum variant name");
            parse_duplicate(p, c, p.nodes[id].first, token); let variant = parse_node(p, N_VARIANT, token);
            if parse_accept(p, c, T_LCURLY) {
                p.nodes[variant].flags |= F_EXPLICIT_PARAMS; parse_fields(p, c, variant);
                parse_expect(p, c, T_RCURLY, "expected } after variant fields");
            }
            append_child(p, id, variant);
            if c.at == at || !parse_accept(p, c, T_COMMA) { break; }
        }
    }
    parse_expect(p, c, T_RCURLY, "expected } after aggregate declaration");
    c.namespace_token = saved_namespace; return id;
}
fn parse_assignment(kind: i64) -> bool {
    return kind == T_ASSIGN || kind == T_DOTASSIGN || kind >= T_PLUSEQ && kind <= T_XOREQ || kind == T_SHLEQ || kind == T_SHREQ;
}
fn parse_function_start(p: Program&, c: ParseCursor&) -> bool {
    let kind = parse_kind(p, c);
    return kind == T_FN || kind == T_RECURSIVE || kind == T_THREADFN || kind == T_EXTERN || kind == T_EXPORT || kind == T_SIMD || parse_inline(p, c) || parse_checkfree(p, c);
}
recursive fn parse_block(p: Program&, c: ParseCursor&) -> i64 {
    let token = parse_expect(p, c, T_LCURLY, "expected { before block"); let id = parse_node(p, N_BLOCK, token);
    if p.tokens[token].kind != T_LCURLY { return id; }
    parse_block_body(p, c, id); return id;
}
recursive fn parse_block_body(p: Program&, c: ParseCursor&, body_node: i64) {
    let statement = c.statement; let ended = c.ended; let restricted = c.no_record;
    c.statement = false; c.ended = false; c.no_record = false;
    while parse_kind(p, c) != T_EOF {
        if parse_accept(p, c, T_RCURLY) { c.statement = statement; c.ended = ended; c.no_record = restricted; return; }
        let at = c.at; let errors = p.diagnostics.len; var node: i64 = -1;
        let kind = parse_kind(p, c);
        if kind == T_CONST && parse_ahead(p, c) == T_FOR { node = parse_const_for(p, c, 0); }
        else if kind == T_LET || kind == T_VAR || kind == T_CONST || kind == T_REUSABLE {
            node = parse_variable(p, c, false); parse_expect(p, c, T_SEMI, "expected ; after variable declaration");
        } else if parse_function_start(p, c) { node = parse_function(p, c, true); }
        else if kind == T_GUARD {
            let token = parse_next(p, c); let condition = parse_subexpr(p, c, true); var no: i64 = -1;
            if parse_accept(p, c, T_ELSE) { no = parse_block(p, c); parse_accept(p, c, T_SEMI); }
            else { parse_expect(p, c, T_SEMI, "expected ; after guard condition"); }
            let rest = parse_node(p, N_BLOCK, token); parse_block_body(p, c, rest);
            node = parse_node(p, N_IF, token); p.nodes[node].left = condition; p.nodes[node].right = rest; p.nodes[node].third = no;
            if (p.nodes[rest].flags & F_TAIL) != 0 { p.nodes[node].flags |= F_TAIL; p.nodes[body_node].flags |= F_TAIL; }
            append_child(p, body_node, node); c.statement = statement; c.ended = ended; c.no_record = restricted; return;
        } else {
            c.statement = true; c.ended = false; node = parse_expr(p, c); c.statement = false;
            let expression_ended = c.ended; c.ended = false;
            if !expression_ended && parse_assignment(parse_kind(p, c)) {
                let token = parse_next(p, c); let right = parse_subexpr(p, c, false); let assign = parse_node(p, N_ASSIGN, token);
                p.nodes[assign].left = node; p.nodes[assign].right = right; p.nodes[assign].integer = p.tokens[token].kind; node = assign;
                parse_expect(p, c, T_SEMI, "expected ; after assignment");
            } else if !expression_ended && (parse_kind(p, c) == T_INC || parse_kind(p, c) == T_DEC) {
                let token = parse_next(p, c); let assign = parse_node(p, N_ASSIGN, token);
                p.nodes[assign].left = node; p.nodes[assign].integer = p.tokens[token].kind; node = assign;
                parse_expect(p, c, T_SEMI, "expected ; after increment");
            } else if !expression_ended && parse_kind(p, c) == T_COMMA {
                let assign = parse_node(p, N_MULTI_ASSIGN, c.at); append_child(p, assign, node);
                while parse_accept(p, c, T_COMMA) { let target = parse_subexpr(p, c, false); append_child(p, assign, target); }
                parse_expect(p, c, T_ASSIGN, "multiple assignment requires = and a call's results");
                let right = parse_subexpr(p, c, false); p.nodes[assign].right = right; p.nodes[assign].integer = T_ASSIGN; node = assign;
                parse_expect(p, c, T_SEMI, "expected ; after multiple assignment");
            } else if parse_accept(p, c, T_SEMI) {
                // Explicitly terminated expression statement.
            } else if parse_kind(p, c) == T_RCURLY {
                p.nodes[node].flags |= F_TAIL; p.nodes[body_node].flags |= F_TAIL;
                append_child(p, body_node, node); parse_next(p, c);
                c.statement = statement; c.ended = ended; c.no_record = restricted; return;
            } else if !expression_ended { parse_error(p, c, "expected ; after expression"); }
        }
        if node >= 0 { append_child(p, body_node, node); }
        if c.at == at {
            parse_error(p, c, "statement made no progress"); parse_next(p, c);
        } else if !c.tentative && p.diagnostics.len > errors {
            p.nodes[body_node].flags |= F_BROKEN;
            // Stop before a block close; its owner still consumes it.
            if parse_kind(p, c) != T_RCURLY { parse_resync(p, c, false); }
        }
    }
    parse_error(p, c, "expected } before end of file");
    c.statement = statement; c.ended = ended; c.no_record = restricted;
}
recursive fn parse_top(p: Program&, c: ParseCursor&) -> i64 {
    c.namespace_token = c.file_namespace;
    let token = c.at; let kind = parse_kind(p, c);
    if kind == T_NAMESPACE {
        parse_next(p, c);
        if c.file_namespace >= 0 { parse_error(p, c, "namespace declared twice in this file"); }
        if c.declaration_seen { parse_error(p, c, "namespace must precede all declarations"); }
        let name = parse_expect(p, c, T_IDENT, "expected namespace name");
        c.file_namespace = name; c.namespace_token = name;
        parse_expect(p, c, T_SEMI, "expected ; after namespace declaration"); return parse_node(p, N_NAMESPACE, name);
    }
    if kind == T_IMPORT {
        parse_next(p, c); let relative = parse_accept(p, c, T_DOT);
        let name = parse_expect(p, c, T_IDENT, "expected import name"); let id = parse_node(p, N_IMPORT, name);
        p.nodes[id].integer = name; var end = name;
        while parse_accept(p, c, T_DOT) { end = parse_expect(p, c, T_IDENT, "expected import path component"); }
        p.nodes[id].aux = end;
        if relative { p.nodes[id].flags |= F_REFERENCE; }
        if parse_word(p, c, "from") {
            if relative || end != name { parse_error(p, c, "a sourced import names one package"); }
            parse_next(p, c); let source = parse_expect(p, c, T_STRLIT, "expected package source string after from"); p.nodes[id].left = source;
        }
        parse_expect(p, c, T_SEMI, "expected ; after import"); return id;
    }
    c.declaration_seen = true;
    if kind == T_STRUCT || kind == T_ENUM { return parse_aggregate(p, c); }
    if kind == T_TYPE {
        parse_next(p, c); let name = parse_qualified(p, c, true); let id = parse_node(p, N_ALIAS, p.nodes[name].token);
        p.nodes[id].scope = c.namespace_token; parse_expect(p, c, T_ASSIGN, "expected = in type alias");
        let type_node = parse_type(p, c); p.nodes[id].left = type_node;
        parse_expect(p, c, T_SEMI, "expected ; after type alias"); return id;
    }
    if kind == T_EXTERN && (parse_ahead(p, c) == T_LCURLY || parse_ahead(p, c) == T_STRLIT && parse_ahead(p, c, 2) == T_LCURLY) {
        parse_next(p, c); let library = parse_expect(p, c, T_STRLIT, "extern block requires a library string");
        let id = parse_node(p, N_EXTERN, library); parse_expect(p, c, T_LCURLY, "expected { in extern block");
        while parse_kind(p, c) != T_RCURLY && parse_kind(p, c) != T_EOF {
            let at = c.at; let member = parse_function(p, c, false, true, library); append_child(p, id, member);
            if c.at == at { parse_error(p, c, "extern declaration made no progress"); parse_next(p, c); }
        }
        parse_expect(p, c, T_RCURLY, "expected } after extern block"); return id;
    }
    if parse_function_start(p, c) { return parse_function(p, c, false); }
    if kind == T_LET || kind == T_VAR || kind == T_CONST || kind == T_REUSABLE {
        let id = parse_variable(p, c, true); parse_expect(p, c, T_SEMI, "expected ; after global declaration"); return id;
    }
    parse_error(p, c, "expected top-level declaration"); parse_next(p, c); return parse_node(p, N_EMPTY, token);
}
fn parse_source(p: Program&, source_id: i64) -> i64 {
    if source_id < 0 || source_id >= p.sources.len { diagnose_at(p, 0, 0, 0, "invalid source ID"); return -1; }
    if p.sources[source_id].token_end <= p.sources[source_id].token_start { lex_source(p, source_id); }
    var c = ParseCursor { source: source_id, at: p.sources[source_id].token_start, end: p.sources[source_id].token_end };
    while c.at + 1 < c.end && p.tokens[c.at].kind < 0 { c.at++; }
    let root = parse_node(p, N_MODULE, c.at); p.sources[source_id].root = root;
    while parse_kind(p, c) != T_EOF {
        let at = c.at; c.failed = false;
        let declaration = parse_top(p, c); append_child(p, root, declaration);
        if c.at == at { parse_error(p, c, "declaration made no progress"); parse_next(p, c); }
        if c.failed && parse_kind(p, c) != T_EOF {
            p.nodes[declaration].flags |= F_BROKEN;
            if !parse_function_start(p, c) && parse_kind(p, c) != T_STRUCT && parse_kind(p, c) != T_ENUM && parse_kind(p, c) != T_TYPE && parse_kind(p, c) != T_IMPORT && parse_kind(p, c) != T_NAMESPACE && parse_kind(p, c) != T_LET && parse_kind(p, c) != T_VAR && parse_kind(p, c) != T_CONST {
                parse_resync(p, c, true);
            }
        }
    }
    return root;
}
