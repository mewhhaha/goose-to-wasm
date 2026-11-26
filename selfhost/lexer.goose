import model;


// Zero-collision FNV-1a keyword filter: ((h * 3005) as! u32) >> 25 maps all 46
// keywords to distinct slots; non-matching identifiers bypass lex_keyword.
let LEX_KW_HASH: u32[128] = [
    3378807160, 1303515621, 0, 1683726967, 0, 0, 0, 0,
    0, 0, 3943480674, 4414187, 1579491469, 1542339703, 2246981567, 0,
    3723446379, 2469985204, 0, 2901640080, 0, 1854009007, 188920568, 0,
    1996966820, 0, 0, 0, 2171383808, 0, 0, 2045647647,
    0, 0, 0, 0, 436337467, 3332055654, 0, 3183434736,
    0, 0, 0, 0, 735142254, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 184981848, 0,
    583776464, 0, 0, 0, 3365180733, 0, 0, 2116038550,
    288002260, 0, 0, 0, 0, 2424823223, 0, 0,
    0, 1094220446, 0, 0, 3402529440, 0, 0, 2317739966,
    1361572173, 0, 0, 1498807978, 0, 959999494, 4211608755, 231090382,
    1663232469, 0, 0, 2462236192, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 3331365182,
    0, 0, 3400004773, 2046486290, 0, 99841201, 0, 0,
    0, 0, 0, 0, 0, 0, 2977070660, 0,
    0, 0, 1453506779, 1716507092, 1349190650, 0, 2218221252, 3088651068,
];
// 2 starts an identifier, 1 is a digit, and both can continue a name.
let LEX_IDENT: u8[256] = [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0,
    0, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 0, 0, 0, 0, 2,
    0, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
    2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
];
// The high bit marks punctuation that can start a longer operator.
let LEX_PUNCT: u8[128] = [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 175, 0, 0, 0, 153, 177, 0, 5, 6, 151, 149, 11, 150, 144, 152,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 141, 12, 167, 164, 168, 14,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 8, 179, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 9, 178, 10, 48, 0,
];
let LEX_OP_EQUAL: u8[128] = [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 38, 0, 0, 0, 30, 31, 0, 0, 0, 28, 26, 0, 27, 18, 29,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 41, 37, 42, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 33, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 32, 0, 0, 0,
];
let LEX_OP_REPEAT: u8[128] = [
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 52, 0, 0, 0, 0, 34, 0, 35, 17, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 15, 0, 43, 0, 44, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 53, 0, 0, 0,
];

inline fn lex_digit(c: u8) -> bool { return c >= '0' && c <= '9'; }
fn lex_hex(c: u8) -> i64 {
    if lex_digit(c) { return c as i64 - 48; }
    if c >= 'a' && c <= 'f' { return c as i64 - 87; }
    if c >= 'A' && c <= 'F' { return c as i64 - 55; }
    return -1;
}
fn lex_keyword(word: u8[:]) -> i64 {
    let n = word.len;
    if n < 2 || n > 9 || n == 7 { return T_IDENT; }
    let c0 = word[0];
    if n == 2 {
        let c1 = word[1];
        if c0 == 'i' {
            if c1 == 'f' { return T_IF; }
            if c1 == 'n' { return T_IN; }
            if c1 == '8' { return T_TI8; }
        } else if c0 == 'f' {
            if c1 == 'n' { return T_FN; }
        } else if c0 == 'a' {
            if c1 == 's' { return T_AS; }
        } else if c0 == 'u' {
            if c1 == '8' { return T_TU8; }
        }
        return T_IDENT;
    }
    if n == 3 {
        if c0 == 'i' {
            if same_bytes(word, "i64") { return T_TI64; }
            if same_bytes(word, "i32") { return T_TI32; }
            if same_bytes(word, "i16") { return T_TI16; }
        } else if c0 == 'l' {
            if same_bytes(word, "let") { return T_LET; }
        } else if c0 == 'v' {
            if same_bytes(word, "var") { return T_VAR; }
        } else if c0 == 'f' {
            if same_bytes(word, "for") { return T_FOR; }
            if same_bytes(word, "f64") { return T_TF64; }
            if same_bytes(word, "f32") { return T_TF32; }
        } else if c0 == 'u' {
            if same_bytes(word, "u64") { return T_TU64; }
            if same_bytes(word, "u32") { return T_TU32; }
            if same_bytes(word, "u16") { return T_TU16; }
        } else if c0 == 'p' {
            if same_bytes(word, "pad") { return T_PAD; }
        }
        return T_IDENT;
    }
    if n == 4 {
        if c0 == 'e' {
            if same_bytes(word, "else") { return T_ELSE; }
            if same_bytes(word, "enum") { return T_ENUM; }
        } else if c0 == 't' {
            if same_bytes(word, "true") { return T_TRUE; }
            if same_bytes(word, "type") { return T_TYPE; }
        } else if c0 == 'b' {
            if same_bytes(word, "bool") { return T_TBOOL; }
        } else if c0 == 'l' {
            if same_bytes(word, "loop") { return T_LOOP; }
        } else if c0 == 'n' {
            if same_bytes(word, "null") { return T_NULLLIT; }
        } else if c0 == 's' {
            if same_bytes(word, "self") { return T_SELF; }
            if same_bytes(word, "simd") { return T_SIMD; }
        }
        return T_IDENT;
    }
    if n == 5 {
        if c0 == 'f' { if same_bytes(word, "false") { return T_FALSE; } }
        else if c0 == 'c' { if same_bytes(word, "const") { return T_CONST; } }
        else if c0 == 'w' { if same_bytes(word, "while") { return T_WHILE; } }
        else if c0 == 'b' {
            if same_bytes(word, "break") { return T_BREAK; }
            if same_bytes(word, "block") { return T_BLOCK; }
        }
        else if c0 == 'm' { if same_bytes(word, "match") { return T_MATCH; } }
        else if c0 == 'g' { if same_bytes(word, "guard") { return T_GUARD; } }
        else if c0 == 'd' { if same_bytes(word, "defer") { return T_DEFER; } }
        return T_IDENT;
    }
    if n == 6 {
        if c0 == 'r' { if same_bytes(word, "return") { return T_RETURN; } }
        else if c0 == 's' { if same_bytes(word, "struct") { return T_STRUCT; } }
        else if c0 == 'i' { if same_bytes(word, "import") { return T_IMPORT; } }
        else if c0 == 'e' {
            if same_bytes(word, "export") { return T_EXPORT; }
            if same_bytes(word, "extern") { return T_EXTERN; }
        }
        else if c0 == 'v' { if same_bytes(word, "varint") { return T_TVARINT; } }
        return T_IDENT;
    }
    if n == 8 {
        if c0 == 'c' { if same_bytes(word, "continue") { return T_CONTINUE; } }
        else if c0 == 'r' { if same_bytes(word, "reusable") { return T_REUSABLE; } }
        return T_IDENT;
    }
    if c0 == 'r' { if same_bytes(word, "recursive") { return T_RECURSIVE; } }
    else if c0 == 'n' { if same_bytes(word, "namespace") { return T_NAMESPACE; } }
    else if c0 == 't' { if same_bytes(word, "thread_fn") { return T_THREADFN; } }
    return T_IDENT;
}

// skeleton: a library source whose top-level function bodies are skipped; braces,
// parens, declaration and pending track the declaration that owns the next body.
struct LexCursor { source: i64, at: i64, end: i64, line: i64 = 1,
                   skeleton: bool = false, braces: i64 = 0, parens: i64 = 0,
                   declaration: bool = true, pending: bool = false, intern_names: bool = true }
inline fn lex_peek(p: Program&, l: LexCursor&, ahead: i64 = 0) -> u8 {
    if l.at + ahead >= l.end { return 0; }
    return p.text[l.at + ahead];
}
inline fn lex_take(p: Program&, l: LexCursor&) -> u8 {
    let c = lex_peek(p, l);
    if l.at < l.end {
        l.at++;
        if c == '\n' { l.line++; }
    }
    return c;
}
fn lex_escape(p: Program&, l: LexCursor&, token: i64) -> i64 {
    if l.at >= l.end || lex_peek(p, l) == 10 {
        diagnose(p, token, "unterminated literal"); return -1;
    }
    let c = lex_take(p, l);
    if c != '\\' { return c as i64; }
    let e = lex_take(p, l);
    if e == 'n' { return 10; }
    if e == 'r' { return 13; }
    if e == 't' { return 9; }
    if e == '0' { return 0; }
    if e == '\\' || e == '"' || e == '\'' { return e as i64; }
    if e == 0 { diagnose(p, token, "unterminated literal"); return -1; }
    if e == 'x' {
        let a = lex_hex(lex_peek(p, l));
        let b = lex_hex(lex_peek(p, l, 1));
        if a >= 0 && b >= 0 { lex_take(p, l); lex_take(p, l); }
        if a >= 0 && b >= 0 { return a * 16 + b; }
        diagnose(p, token, "hexadecimal escape requires two digits");
        return 0;
    }
    diagnose(p, token, "unknown escape sequence");
    return e as i64;
}

// An underscore in a number separates two digits of its radix: 1_000, 0xFF_AA.
fn lex_separator(p: Program&, l: LexCursor&, token: i64, radix: i64) {
    let before = lex_hex(p.text[l.at - 1]); let after = lex_hex(lex_peek(p, l, 1));
    if before < 0 || before >= radix || after < 0 || after >= radix { diagnose(p, token, "invalid numeric separator"); }
    lex_take(p, l);
}

fn lex_source(p: Program&, source_id: i64, skeleton: bool = false, intern_names: bool = true) {
    if source_id < 0 || source_id >= p.sources.len { diagnose_at(p, 0, 0, 0, "invalid source ID"); return; }
    let source = p.sources[source_id];
    var l = LexCursor { source: source_id, at: source.text_start, end: source.text_start + source.text_len, skeleton: skeleton, intern_names: intern_names };
    p.sources[source_id].token_start = p.tokens.len;
    if lex_peek(p, l) == 239 && lex_peek(p, l, 1) == 187 && lex_peek(p, l, 2) == 191 {
        l.at += 3;
    }
    lex_tokens(p, l);
    p.sources[source_id].token_end = p.tokens.len;
}

// The offset of the brace closing a body whose text starts at `at`, or -1. Strings,
// characters and comments follow the token rules, so their braces do not count.
fn lex_skip_body(p: Program&, start: i64, end: i64) -> i64 {
    var depth = 1; var at = start;
    while at < end {
        let c = p.text[at];
        if c == '{' { depth++; at++; }
        else if c == '}' { depth--; if depth == 0 { return at; } at++; }
        else if c == '/' && at + 1 < end && p.text[at + 1] == '/' {
            while at < end && p.text[at] != '\n' { at++; }
        } else if c == '/' && at + 1 < end && p.text[at + 1] == '*' {
            var nested = 1; at += 2;
            while at < end && nested > 0 {
                if p.text[at] == '/' && at + 1 < end && p.text[at + 1] == '*' { nested++; at += 2; }
                else if p.text[at] == '*' && at + 1 < end && p.text[at + 1] == '/' { nested--; at += 2; }
                else { at++; }
            }
            if nested != 0 { return -1; }
        } else if c == '"' && at + 2 < end && p.text[at + 1] == '"' && p.text[at + 2] == '"' {
            at += 3;
            while at + 2 < end && !(p.text[at] == '"' && p.text[at + 1] == '"' && p.text[at + 2] == '"') { at++; }
            if at + 2 >= end { return -1; }
            at += 3;
        } else if c == '"' || c == '\'' {
            at++;
            while at < end && p.text[at] != c && p.text[at] != '\n' {
                if p.text[at] == '\\' { at += 2; } else { at++; }
            }
            if at >= end || p.text[at] != c { return -1; }
            at++;
        } else { at++; }
    }
    return -1;
}

// Follows top-level declarations of a library source. The first brace outside
// parentheses after a declaration's fn keyword opens its body, which is skipped.
fn lex_skeleton(p: Program&, l: LexCursor&, token: i64) {
    let kind = p.tokens[token].kind;
    if kind == T_LCURLY {
        if l.braces == 0 && l.parens == 0 && l.pending {
            l.pending = false;
            let close = lex_skip_body(p, l.at, l.end);
            if close >= 0 {
                p.tokens[token].kind = T_LAZY_BODY as u8; p.tokens[token].integer = close;
                while l.at < close {
                    if p.text[l.at] == '\n' { l.line++; }
                    l.at++;
                }
            }
        }
        l.braces++; l.declaration = false; return;
    }
    if kind == T_RCURLY {
        if l.braces > 0 { l.braces--; }
        if l.braces == 0 && l.parens == 0 { l.declaration = true; l.pending = false; }
        return;
    }
    if l.braces > 0 { return; }
    if kind == T_LPAREN || kind == T_LBRACKET { l.parens++; l.declaration = false; }
    else if kind == T_RPAREN || kind == T_RBRACKET { if l.parens > 0 { l.parens--; } }
    else if kind == T_SEMI { if l.parens == 0 { l.declaration = true; l.pending = false; } }
    else if kind == T_ASSIGN { if l.parens == 0 { l.pending = false; } l.declaration = false; }
    else if kind == T_FN || kind == T_THREADFN {
        if l.declaration && l.parens == 0 { l.pending = true; }
        l.declaration = false;
    } else if kind == T_EXPORT || kind == T_EXTERN || kind == T_SIMD || kind == T_RECURSIVE || kind == T_STRLIT { }
    else if kind == T_IDENT && (token_is(p, token, "inline") || token_is(p, token, "checkfree")) { }
    else { l.declaration = false; }
}

// Lexes l's range, then appends its end-of-file token.
fn lex_tokens(p: Program&, start: LexCursor) {
    var l = start;
    // Token IDs are stable across table growth and a one-byte spelling has
    // no ambiguity. Cache its canonical ID for the duration of this source.
    var short_names: i32[128] = [0; 128];
    let source_id = l.source;
    let raw: const u8[:] = p.text[..l.end];
    loop {
        if l.at >= raw.len {
            p.tokens.push(Token { start: l.at as i32, end: l.at as i32, line: l.line as i32,
                source: source_id as u16, kind: T_EOF as u8 });
            return;
        }
        let c = raw[l.at];
        if c == ' ' || c == '\t' || c == '\r' {
            var at = l.at + 1;
            while at < raw.len { let d = raw[at]; if d != ' ' && d != '\t' && d != '\r' { break; } at++; }
            l.at = at; continue;
        }
        if c == '\n' { l.at++; l.line++; continue; }
        if c == '/' && lex_peek(p, l, 1) == '/' {
            var at = l.at + 2;
            while at < raw.len && raw[at] != '\n' { at++; }
            l.at = at; continue;
        }
        if c == '/' && lex_peek(p, l, 1) == '*' {
            let start = l.at;
            lex_take(p, l); lex_take(p, l);
            var depth = 1;
            while l.at < raw.len && depth > 0 {
                if lex_peek(p, l) == '/' && lex_peek(p, l, 1) == '*' {
                    lex_take(p, l); lex_take(p, l); depth++;
                } else if lex_peek(p, l) == '*' && lex_peek(p, l, 1) == '/' {
                    lex_take(p, l); lex_take(p, l); depth--;
                } else { lex_take(p, l); }
            }
            if depth != 0 {
                let t = p.tokens.len;
                p.tokens.push(Token { start: start as i32, end: l.at as i32, line: l.line as i32,
                source: source_id as u16, kind: T_EOF as u8 });
                diagnose(p, t, "unterminated /* comment");
            }
            continue;
        }
        let ident = LEX_IDENT[c];
        if ident == 2 {
            let start = l.at;
            var h: u32 = (2166136261 ^ (c as u32)) * 16777619;
            var at = start + 1;
            while at < raw.len {
                let d = raw[at];
                if LEX_IDENT[d] == 0 { break; }
                h = (h ^ (d as u32)) * 16777619;
                at++;
            }
            var kw = T_IDENT;
            let kslot = (((h as u64 * 3005) as! u32) >> 25) as i64;
            if LEX_KW_HASH[kslot] == h { kw = lex_keyword(raw[start..at]); }
            l.at = at;
            let token_id = p.tokens.len;
            let hash: i64 = if kw == T_IDENT { h } else { 0 };
            let short = l.intern_names && at == start + 1;
            let canonical = if short { short_names[c] } else { 0 as i32 };
            p.tokens.push(Token { integer: hash, start: start as i32, end: at as i32,
                text_start: canonical, line: l.line as i32, source: source_id as u16, kind: kw as u8 });
            if kw == T_IDENT && l.intern_names && canonical == 0 {
                intern_ident(p, token_id, h);
                if short { short_names[c] = p.tokens[token_id].text_start; }
            }
            if l.skeleton { lex_skeleton(p, l, token_id); }
            continue;
        }
        if c != 0 && ident == 0 && c != '"' && c != '\'' {
            let start = l.at;
            var kind: i64 = if c < 128 { LEX_PUNCT[c] } else { 0 };
            l.at++;
            if kind >= 128 { kind = lex_operator(raw, l, c, kind - 128); }
            let token_id = p.tokens.len;
            let stored_kind = if kind == T_EOF { T_INVALID } else { kind };
            p.tokens.push(Token { start: start as i32, end: l.at as i32, line: l.line as i32,
                source: source_id as u16, kind: stored_kind as u8 });
            if kind == T_EOF { diagnose(p, token_id, "illegal character in source text"); }
            if l.skeleton { lex_skeleton(p, l, token_id); }
            continue;
        }
        if ident == 1 {
            let start = l.at; let line = l.line;
            var at = start + 1;
            var bits: u64 = (c - 48) as u64;
            var simple = true;
            if c == '0' && at < raw.len && (raw[at] == 'x' || raw[at] == 'X') { simple = false; }
            if simple {
                while at < raw.len {
                    let d = raw[at];
                    if d >= '0' && d <= '9' {
                        if at - start >= 18 { simple = false; break; }
                        bits = bits * 10 + (d - 48) as u64;
                        at++;
                    } else if d == '_' || d == 'e' || d == 'E' || d == '.' && at + 1 < raw.len && raw[at + 1] >= '0' && raw[at + 1] <= '9' {
                        simple = false; break;
                    } else {
                        break;
                    }
                }
            }
            if simple {
                l.at = at;
                let token_id = p.tokens.len;
                p.tokens.push(Token { integer: bits as! i64, start: start as i32, end: at as i32,
                line: line as i32, source: source_id as u16, kind: T_INTLIT as u8 });
                if l.skeleton { lex_skeleton(p, l, token_id); }
                continue;
            }
        }
        var t = Token { start: l.at as i32, end: l.at as i32, line: l.line as i32,
            source: source_id as u16, kind: T_EOF as u8 };
        let token_id = p.tokens.len;
        // Reserve the diagnostic's token before scanning a fallible literal.
        p.tokens.push(t);
        if c == 0 {
            lex_take(p, l);
            diagnose(p, token_id, "NUL byte is not valid source text");
            t.kind = T_INVALID as u8;
        } else if ident == 1 {
            var radix: i64 = 10;
            if c == '0' && (lex_peek(p, l, 1) == 'x' || lex_peek(p, l, 1) == 'X') {
                radix = 16; lex_take(p, l); lex_take(p, l);
            }
            let digits_start = l.at;
            var bits: u64 = 0;
            var overflow = false;
            loop {
                if lex_peek(p, l) == '_' { lex_separator(p, l, token_id, radix); continue; }
                let d = lex_hex(lex_peek(p, l));
                if d < 0 || d >= radix { break; }
                if bits > (0xffffffffffffffff - d as u64) / radix as u64 { overflow = true; }
                bits = bits * radix as u64 + d as u64;
                lex_take(p, l);
            }
            if digits_start == l.at { diagnose(p, token_id, "expected digits in number"); }
            t.kind = T_INTLIT as u8;
            t.integer = bits as! i64;
            if bits > 0x7fffffffffffffff { t.flags = 1; }
            var floating = false;
            if lex_peek(p, l) == '.' && lex_hex(lex_peek(p, l, 1)) >= 0 && lex_hex(lex_peek(p, l, 1)) < radix {
                floating = true; lex_take(p, l);
                loop {
                    if lex_peek(p, l) == '_' { lex_separator(p, l, token_id, radix); continue; }
                    let d = lex_hex(lex_peek(p, l));
                    if d < 0 || d >= radix { break; }
                    lex_take(p, l);
                }
            }
            let e = lex_peek(p, l);
            let after = lex_peek(p, l, 1);
            let after_sign = lex_peek(p, l, 2);
            var exponent = (e == 'e' || e == 'E') &&
                (lex_digit(after) || (after == '+' || after == '-') && lex_digit(after_sign));
            if radix == 16 { exponent = e == 'p' || e == 'P'; }
            if exponent {
                floating = true; lex_take(p, l);
                if lex_peek(p, l) == '-' { lex_take(p, l); }
                else if lex_peek(p, l) == '+' { lex_take(p, l); }
                if !lex_digit(lex_peek(p, l)) { diagnose(p, token_id, "expected exponent digits"); }
                while lex_digit(lex_peek(p, l)) || lex_peek(p, l) == '_' {
                    if lex_peek(p, l) == '_' { lex_separator(p, l, token_id, 10); } else { lex_take(p, l); }
                }
            } else if radix == 16 && floating { diagnose(p, token_id, "hexadecimal float requires a binary exponent"); }
            if floating {
                t.kind = T_FLTLIT as u8;
                set_token_float(t, lex_float(p.text[t.start..l.at], radix));
            }
            else if overflow { diagnose(p, token_id, "integer literal exceeds u64"); }
        } else {
            let quote = lex_take(p, l);
            t.text_start = p.text.len as i32;
            t.kind = T_STRLIT as u8;
            if quote == '\'' {
                let value = lex_escape(p, l, token_id);
                t.kind = T_INTLIT as u8;
                if value >= 0 { t.integer = value; }
                if lex_peek(p, l) == '\'' { lex_take(p, l); }
                else {
                    diagnose(p, token_id, "expected closing ' of character literal");
                    while l.at < l.end && lex_peek(p, l) != 10 && lex_peek(p, l) != '\'' { lex_take(p, l); }
                    if lex_peek(p, l) == '\'' { lex_take(p, l); }
                }
            } else if lex_peek(p, l) == '"' && lex_peek(p, l, 1) == '"' {
                lex_take(p, l); lex_take(p, l);
                lex_raw_string(p, l, token_id, t);
            } else {
                while l.at < l.end && lex_peek(p, l) != '"' && lex_peek(p, l) != 10 {
                    let value = lex_escape(p, l, token_id);
                    if value < 0 { break; }
                    p.text.push(value as u8);
                }
                if lex_peek(p, l) == '"' { lex_take(p, l); }
                else { diagnose(p, token_id, "unterminated string literal"); }
            }
            t.text_len = (p.text.len - t.text_start) as i32;
        }
        t.end = l.at as i32;
        p.tokens[token_id] = t;
        if l.skeleton { lex_skeleton(p, l, token_id); }
    }
}

// The closing delimiter supplies the exact byte margin of a multiline string.
// Decode by offsets: appending decoded bytes may move the text table.
fn lex_raw_string(p: Program&, l: LexCursor&, token: i64, t: Token&) {
    let begin = l.at;
    var first = begin;
    while first < l.end && (p.text[first] == 32 || p.text[first] == 9 || p.text[first] == 13) { first++; }
    if first >= l.end || p.text[first] != 10 {
        while l.at < l.end {
            if lex_peek(p, l) == 34 && lex_peek(p, l, 1) == 34 && lex_peek(p, l, 2) == 34 {
                lex_take(p, l); lex_take(p, l); lex_take(p, l); return;
            }
            if lex_peek(p, l) == 10 {
                diagnose(p, token, "a multi-line string's text starts on the line after its opening delimiter");
            }
            p.text.push(lex_take(p, l));
        }
        diagnose(p, token, "unterminated triple-quoted string"); return;
    }
    first++;
    t.flags |= 2;
    var close = first;
    while close + 2 < l.end && !(p.text[close] == 34 && p.text[close + 1] == 34 && p.text[close + 2] == 34) { close++; }
    if close + 2 >= l.end {
        while l.at < l.end { lex_take(p, l); }
        diagnose(p, token, "unterminated triple-quoted string"); return;
    }
    var margin = close;
    while margin > first && p.text[margin - 1] != 10 { margin--; }
    for i in margin..close {
        if p.text[i] != 32 && p.text[i] != 9 {
            diagnose_at(p, l.source, i, i + 1, "only indentation may come before a multiline string's closing delimiter"); break;
        }
    }
    var line = first;
    while line < margin {
        var end = line;
        while end < margin && p.text[end] != 10 { end++; }
        var text_end = end;
        if text_end > line && p.text[text_end - 1] == 13 { text_end--; }
        if line != first { p.text.push(10); }
        var content = line;
        var matches = true;
        for i in margin..close {
            if content >= text_end || p.text[content] != p.text[i] { matches = false; break; }
            content++;
        }
        if matches {
            for i in content..text_end { p.text.push(p.text[i]); }
        } else {
            for i in line..text_end {
                if p.text[i] != 32 && p.text[i] != 9 {
                    diagnose_at(p, l.source, content, content + 1, "a multiline string line must start with the indentation of its closing delimiter"); break;
                }
            }
        }
        line = end + 1;
    }
    while l.at < close + 3 { lex_take(p, l); }
}

// The first operator byte has already been consumed. Look ahead only as
// far as needed to distinguish the two- and three-byte forms.
inline fn lex_operator(raw: const u8[:], l: LexCursor&, c: u8, single: i64) -> i64 {
    let at = l.at;
    if at >= raw.len { return single; }
    let d = raw[at];
    var kind: i64 = 0;
    if d == '=' { kind = LEX_OP_EQUAL[c]; }
    else if d == c { kind = LEX_OP_REPEAT[c]; }
    else if d == '>' && c == '-' { kind = T_ARROW; }
    else if d == '>' && c == '=' { kind = T_FATARROW; }
    if at + 1 < raw.len && (kind == T_DOTASSIGN || kind == T_SHL || kind == T_SHR || c == '.' && d == '!') {
        if raw[at + 1] == '=' {
            l.at += 2;
            if kind == T_SHL { return T_SHLEQ; }
            if kind == T_SHR { return T_SHREQ; }
            if kind == T_DOTASSIGN { return T_DOTEQ; }
            return T_DOTNEQ;
        }
    }
    if kind == 0 { return single; }
    l.at++;
    return kind;
}

// Base-2^32 integers keep conversion independent of the host libc. Division
// extracts 53 significant bits, then rounds the exact remainder to nearest/even.
fn lex_big_trim(a: u64[>..]&) { while a.len > 1 && a[a.len - 1] == 0 { a.pop(); } }
fn lex_big_mul(a: u64[>..]&, by: u64, add: u64 = 0) {
    var carry = add;
    for i in 0..a.len { let value = a[i] * by + carry; a[i] = value & 0xffffffff; carry = value >> 32; }
    if carry != 0 { a.push(carry); }
}
fn lex_big_shift(a: u64[>..]&, bits: i64) {
    if bits <= 0 { return; }
    let words = bits / 32; let remainder = bits % 32; let size = a.len;
    a.resize(size + words + 1, 0);
    var i = size;
    while i > 0 {
        i--; let value = a[i]; a[i] = 0;
        a[i + words] |= (value << remainder) & 0xffffffff;
        if remainder != 0 { a[i + words + 1] |= value >> (32 - remainder); }
    }
    lex_big_trim(a);
}
fn lex_big_half(a: u64[>..]&) {
    var i = a.len; var carry: u64 = 0;
    while i > 0 { i--; let value = a[i]; a[i] = (value >> 1) | carry; carry = (value & 1) << 31; }
    lex_big_trim(a);
}
fn lex_big_compare(a: const u64[:], b: const u64[:]) -> i64 {
    if a.len < b.len { return -1; } if a.len > b.len { return 1; }
    var i = a.len;
    while i > 0 { i--; if a[i] < b[i] { return -1; } if a[i] > b[i] { return 1; } }
    return 0;
}
fn lex_big_subtract(a: u64[>..]&, b: const u64[:]) {
    var borrow: i64 = 0;
    for i in 0..a.len {
        var part: i64 = 0; if i < b.len { part = b[i] as i64; }
        let value = a[i] as i64 - part - borrow;
        a[i] = (value as! u64) & 0xffffffff; borrow = 0;
        if value < 0 { borrow = 1; }
    }
    lex_big_trim(a);
}
fn lex_big_bits(a: const u64[:]) -> i64 {
    if a.len == 0 || a.len == 1 && a[0] == 0 { return 0; }
    var high = a[a.len - 1]; var bits = (a.len - 1) * 32;
    while high != 0 { bits++; high >>= 1; } return bits;
}
// The IR dump historically exposed the integer prefix of a float token.
fn lex_float_integer(text: const u8[:]) -> i64 {
    let hex = text.len >= 2 && text[0] == '0' && (text[1] == 'x' || text[1] == 'X');
    let radix: i64 = if hex { 16 } else { 10 };
    var bits: u64 = 0;
    for at in (if hex { 2 } else { 0 })..text.len {
        let byte = text[at];
        if byte == '_' { continue; }
        let digit = lex_hex(byte);
        if digit < 0 || digit >= radix { break; }
        bits = bits * (radix as u64) + (digit as u64);
    }
    return bits as! i64;
}
fn lex_float(text: const u8[:], radix: i64) -> f64 {
    var numerator: u64[>..] = [0]; var denominator: u64[>..] = [1];
    var at = 0; if radix == 16 { at = 2; }
    var fraction = false; var fractional = 0; var significant = 0;
    while at < text.len {
        let byte = text[at];
        if byte == '_' { at++; continue; }
        if byte == '.' { fraction = true; at++; continue; }
        let digit = lex_hex(byte); if digit < 0 || digit >= radix { break; }
        lex_big_mul(numerator, radix as u64, digit as u64);
        if significant != 0 || digit != 0 { significant++; }
        if fraction { fractional++; } at++;
    }
    if significant == 0 { return 0.0; }
    var exponent = 0;
    if at < text.len {
        at++; var negative = false;
        if at < text.len && (text[at] == '+' || text[at] == '-') { negative = text[at] == '-'; at++; }
        while at < text.len {
            if text[at] != '_' && exponent < 1000000 { exponent = exponent * 10 + text[at] as i64 - 48; }
            at++;
        }
        if negative { exponent = -exponent; }
    }
    if radix == 16 { exponent -= fractional * 4; }
    else { exponent -= fractional; }
    var order = significant + exponent;
    if radix == 16 { order = lex_big_bits(numerator) + exponent; }
    var too_large = order > 310; var too_small = order < -350;
    if radix == 16 { too_large = order > 1025; too_small = order < -1075; }
    if too_large { var infinite = 1e308; infinite *= infinite; return infinite; }
    if too_small { return 0.0; }
    if radix == 10 {
        if exponent >= 0 { for i in 0..exponent { lex_big_mul(numerator, 5); } }
        else { for i in 0..(0 - exponent) { lex_big_mul(denominator, 5); } }
    }
    if exponent >= 0 { lex_big_shift(numerator, exponent); }
    else { lex_big_shift(denominator, -exponent); }
    var binary_exponent = lex_big_bits(numerator) - lex_big_bits(denominator);
    var comparison: u64[>..] = [];
    if binary_exponent >= 0 {
        comparison.append(denominator); lex_big_shift(comparison, binary_exponent);
        if lex_big_compare(numerator, comparison) < 0 { binary_exponent--; }
    } else {
        comparison.append(numerator); lex_big_shift(comparison, -binary_exponent);
        if lex_big_compare(comparison, denominator) < 0 { binary_exponent--; }
    }
    if binary_exponent > 1023 { var infinite = 1e308; infinite *= infinite; return infinite; }
    var unit = binary_exponent - 52; if unit < -1074 { unit = -1074; }
    if unit < 0 { lex_big_shift(numerator, -unit); }
    else { lex_big_shift(denominator, unit); }
    var shift = lex_big_bits(numerator) - lex_big_bits(denominator);
    if shift < 0 { shift = 0; }
    comparison.clear(); comparison.append(denominator); lex_big_shift(comparison, shift);
    var rounded: u64 = 0;
    loop {
        if lex_big_compare(numerator, comparison) >= 0 {
            lex_big_subtract(numerator, comparison); rounded |= (1 as u64) << shift;
        }
        if shift == 0 { break; } shift--; lex_big_half(comparison);
    }
    lex_big_shift(numerator, 1);
    let remainder = lex_big_compare(numerator, denominator);
    if remainder > 0 || remainder == 0 && (rounded & 1) != 0 { rounded++; }
    var value = rounded as f64;
    // Scaling by powers of two is exact after the integer rounding above.
    while unit > 0 { value *= 2.0; unit--; }
    while unit < 0 { value *= 0.5; unit++; }
    return value;
}
