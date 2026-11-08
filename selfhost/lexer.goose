import model;


inline fn lex_alpha(c: u8) -> bool {
    return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c == '_';
}
inline fn lex_digit(c: u8) -> bool { return c >= '0' && c <= '9'; }
fn lex_hex(c: u8) -> i64 {
    if lex_digit(c) { return c as i64 - 48; }
    if c >= 'a' && c <= 'f' { return c as i64 - 87; }
    if c >= 'A' && c <= 'F' { return c as i64 - 55; }
    return -1;
}
fn lex_equal(p: Program&, start: i64, end: i64, word: const u8[:]) -> bool {
    if end - start != word.len { return false; }
    for c, i in word { if p.text[start + i] != c { return false; } }
    return true;
}

fn lex_keyword(p: Program&, start: i64, end: i64) -> i64 {
    if end <= start { return T_IDENT; }
    if p.text[start] == 'i' {
        if lex_equal(p, start, end, "import") { return T_IMPORT; }
        if lex_equal(p, start, end, "if") { return T_IF; }
        if lex_equal(p, start, end, "in") { return T_IN; }
        if lex_equal(p, start, end, "i8") { return T_TI8; }
        if lex_equal(p, start, end, "i16") { return T_TI16; }
        if lex_equal(p, start, end, "i32") { return T_TI32; }
        if lex_equal(p, start, end, "i64") { return T_TI64; }
    }
    if p.text[start] == 'n' {
        if lex_equal(p, start, end, "namespace") { return T_NAMESPACE; }
        if lex_equal(p, start, end, "null") { return T_NULLLIT; }
    }
    if p.text[start] == 's' {
        if lex_equal(p, start, end, "struct") { return T_STRUCT; }
        if lex_equal(p, start, end, "simd") { return T_SIMD; }
        if lex_equal(p, start, end, "self") { return T_SELF; }
    }
    if p.text[start] == 'e' {
        if lex_equal(p, start, end, "enum") { return T_ENUM; }
        if lex_equal(p, start, end, "export") { return T_EXPORT; }
        if lex_equal(p, start, end, "extern") { return T_EXTERN; }
        if lex_equal(p, start, end, "else") { return T_ELSE; }
    }
    if p.text[start] == 't' {
        if lex_equal(p, start, end, "type") { return T_TYPE; }
        if lex_equal(p, start, end, "thread_fn") { return T_THREADFN; }
        if lex_equal(p, start, end, "true") { return T_TRUE; }
    }
    if p.text[start] == 'f' {
        if lex_equal(p, start, end, "fn") { return T_FN; }
        if lex_equal(p, start, end, "for") { return T_FOR; }
        if lex_equal(p, start, end, "false") { return T_FALSE; }
        if lex_equal(p, start, end, "f32") { return T_TF32; }
        if lex_equal(p, start, end, "f64") { return T_TF64; }
    }
    if p.text[start] == 'r' {
        if lex_equal(p, start, end, "recursive") { return T_RECURSIVE; }
        if lex_equal(p, start, end, "reusable") { return T_REUSABLE; }
        if lex_equal(p, start, end, "return") { return T_RETURN; }
    }
    if p.text[start] == 'l' {
        if lex_equal(p, start, end, "let") { return T_LET; }
        if lex_equal(p, start, end, "loop") { return T_LOOP; }
    }
    if p.text[start] == 'v' {
        if lex_equal(p, start, end, "var") { return T_VAR; }
        if lex_equal(p, start, end, "varint") { return T_TVARINT; }
    }
    if p.text[start] == 'c' {
        if lex_equal(p, start, end, "const") { return T_CONST; }
        if lex_equal(p, start, end, "continue") { return T_CONTINUE; }
    }
    if p.text[start] == 'p' {
        if lex_equal(p, start, end, "pad") { return T_PAD; }
    }
    if p.text[start] == 'w' {
        if lex_equal(p, start, end, "while") { return T_WHILE; }
    }
    if p.text[start] == 'b' {
        if lex_equal(p, start, end, "block") { return T_BLOCK; }
        if lex_equal(p, start, end, "break") { return T_BREAK; }
        if lex_equal(p, start, end, "bool") { return T_TBOOL; }
    }
    if p.text[start] == 'g' {
        if lex_equal(p, start, end, "guard") { return T_GUARD; }
    }
    if p.text[start] == 'm' {
        if lex_equal(p, start, end, "match") { return T_MATCH; }
    }
    if p.text[start] == 'a' {
        if lex_equal(p, start, end, "as") { return T_AS; }
    }
    if p.text[start] == 'u' {
        if lex_equal(p, start, end, "u8") { return T_TU8; }
        if lex_equal(p, start, end, "u16") { return T_TU16; }
        if lex_equal(p, start, end, "u32") { return T_TU32; }
        if lex_equal(p, start, end, "u64") { return T_TU64; }
    }
    return T_IDENT;
}

struct LexCursor { source: i64, at: i64, end: i64, line: i64 = 1, column: i64 = 1 }
inline fn lex_peek(p: Program&, l: LexCursor&, ahead: i64 = 0) -> u8 {
    if l.at + ahead >= l.end { return 0; }
    return p.text[l.at + ahead];
}
inline fn lex_take(p: Program&, l: LexCursor&) -> u8 {
    let c = lex_peek(p, l);
    if l.at < l.end {
        l.at++;
        l.column++;
        if c == '\n' { l.line++; l.column = 1; }
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

fn lex_source(p: Program&, source_id: i64) {
    if source_id < 0 || source_id >= p.sources.len { diagnose_at(p, 0, 0, 0, "invalid source ID"); return; }
    let source = p.sources[source_id];
    var l = LexCursor { source: source_id, at: source.text_start, end: source.text_start + source.text_len };
    p.sources[source_id].token_start = p.tokens.len;
    if lex_peek(p, l) == 239 && lex_peek(p, l, 1) == 187 && lex_peek(p, l, 2) == 191 {
        l.at += 3;
    }
    loop {
        let c = lex_peek(p, l);
        if c == ' ' || c == '\t' || c == '\r' || c == '\n' { lex_take(p, l); continue; }
        if c == '/' && lex_peek(p, l, 1) == '/' {
            while l.at < l.end && lex_peek(p, l) != '\n' { lex_take(p, l); }
            continue;
        }
        if c == '/' && lex_peek(p, l, 1) == '*' {
            let start = l.at;
            lex_take(p, l); lex_take(p, l);
            var depth = 1;
            while l.at < l.end && depth > 0 {
                if lex_peek(p, l) == '/' && lex_peek(p, l, 1) == '*' {
                    lex_take(p, l); lex_take(p, l); depth++;
                } else if lex_peek(p, l) == '*' && lex_peek(p, l, 1) == '/' {
                    lex_take(p, l); lex_take(p, l); depth--;
                } else { lex_take(p, l); }
            }
            if depth != 0 {
                let t = p.tokens.len;
                p.tokens.push(Token { kind: T_EOF, source: source_id, start: start, end: l.at, line: l.line, column: l.column });
                diagnose(p, t, "unterminated /* comment");
            }
            continue;
        }
        var t = Token { kind: T_EOF, source: source_id, start: l.at, end: l.at, line: l.line, column: l.column };
        let token_id = p.tokens.len;
        // Reserve the diagnostic's token before scanning a fallible literal.
        p.tokens.push(t);
        if l.at >= l.end {
            p.sources[source_id].token_end = p.tokens.len;
            return;
        }
        if c == 0 {
            lex_take(p, l);
            diagnose(p, token_id, "NUL byte is not valid source text");
            t.kind = -1;
        } else if lex_alpha(c) {
            lex_take(p, l);
            while lex_alpha(lex_peek(p, l)) || lex_digit(lex_peek(p, l)) { lex_take(p, l); }
            t.kind = lex_keyword(p, t.start, l.at);
        } else if lex_digit(c) {
            var radix: i64 = 10;
            if c == '0' && (lex_peek(p, l, 1) == 'x' || lex_peek(p, l, 1) == 'X') {
                radix = 16; lex_take(p, l); lex_take(p, l);
            }
            let digits_start = l.at;
            var bits: u64 = 0;
            var overflow = false;
            loop {
                let d = lex_hex(lex_peek(p, l));
                if d < 0 || d >= radix { break; }
                if bits > (0xffffffffffffffff - d as u64) / radix as u64 { overflow = true; }
                bits = bits * radix as u64 + d as u64;
                lex_take(p, l);
            }
            if digits_start == l.at { diagnose(p, token_id, "expected digits in number"); }
            t.kind = T_INTLIT;
            t.integer = bits as! i64;
            if bits > 0x7fffffffffffffff { t.flags = 1; }
            var floating = false;
            if lex_peek(p, l) == '.' && lex_hex(lex_peek(p, l, 1)) >= 0 && lex_hex(lex_peek(p, l, 1)) < radix {
                floating = true; lex_take(p, l);
                loop {
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
                while lex_digit(lex_peek(p, l)) { lex_take(p, l); }
            } else if radix == 16 && floating { diagnose(p, token_id, "hexadecimal float requires a binary exponent"); }
            if floating {
                t.kind = T_FLTLIT;
                t.float_value = lex_float(p.text[t.start..l.at], radix);
            }
            else if overflow { diagnose(p, token_id, "integer literal exceeds u64"); }
        } else if c == '"' || c == '\'' {
            let quote = lex_take(p, l);
            t.text_start = p.text.len;
            t.kind = T_STRLIT;
            if quote == '\'' {
                let value = lex_escape(p, l, token_id);
                t.kind = T_INTLIT;
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
            t.text_len = p.text.len - t.text_start;
        } else {
            t.kind = lex_punctuation(p, l);
            if t.kind == T_EOF { diagnose(p, token_id, "illegal character in source text"); t.kind = -1; }
        }
        t.end = l.at;
        p.tokens[token_id] = t;
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

fn lex_punctuation(p: Program&, l: LexCursor&) -> i64 {
    if lex_peek(p, l, 0) == 46 && lex_peek(p, l, 1) == 61 && lex_peek(p, l, 2) == 61 { lex_take(p, l); lex_take(p, l); lex_take(p, l); return T_DOTEQ; }
    if lex_peek(p, l, 0) == 46 && lex_peek(p, l, 1) == 33 && lex_peek(p, l, 2) == 61 { lex_take(p, l); lex_take(p, l); lex_take(p, l); return T_DOTNEQ; }
    if lex_peek(p, l, 0) == 60 && lex_peek(p, l, 1) == 60 && lex_peek(p, l, 2) == 61 { lex_take(p, l); lex_take(p, l); lex_take(p, l); return T_SHLEQ; }
    if lex_peek(p, l, 0) == 62 && lex_peek(p, l, 1) == 62 && lex_peek(p, l, 2) == 61 { lex_take(p, l); lex_take(p, l); lex_take(p, l); return T_SHREQ; }
    if lex_peek(p, l, 0) == 58 && lex_peek(p, l, 1) == 58 { lex_take(p, l); lex_take(p, l); return T_COLONCOLON; }
    if lex_peek(p, l, 0) == 46 && lex_peek(p, l, 1) == 46 { lex_take(p, l); lex_take(p, l); return T_DOTDOT; }
    if lex_peek(p, l, 0) == 46 && lex_peek(p, l, 1) == 61 { lex_take(p, l); lex_take(p, l); return T_DOTASSIGN; }
    if lex_peek(p, l, 0) == 43 && lex_peek(p, l, 1) == 61 { lex_take(p, l); lex_take(p, l); return T_PLUSEQ; }
    if lex_peek(p, l, 0) == 45 && lex_peek(p, l, 1) == 61 { lex_take(p, l); lex_take(p, l); return T_MINUSEQ; }
    if lex_peek(p, l, 0) == 42 && lex_peek(p, l, 1) == 61 { lex_take(p, l); lex_take(p, l); return T_MULEQ; }
    if lex_peek(p, l, 0) == 47 && lex_peek(p, l, 1) == 61 { lex_take(p, l); lex_take(p, l); return T_DIVEQ; }
    if lex_peek(p, l, 0) == 37 && lex_peek(p, l, 1) == 61 { lex_take(p, l); lex_take(p, l); return T_MODEQ; }
    if lex_peek(p, l, 0) == 38 && lex_peek(p, l, 1) == 61 { lex_take(p, l); lex_take(p, l); return T_ANDEQ; }
    if lex_peek(p, l, 0) == 124 && lex_peek(p, l, 1) == 61 { lex_take(p, l); lex_take(p, l); return T_OREQ; }
    if lex_peek(p, l, 0) == 94 && lex_peek(p, l, 1) == 61 { lex_take(p, l); lex_take(p, l); return T_XOREQ; }
    if lex_peek(p, l, 0) == 43 && lex_peek(p, l, 1) == 43 { lex_take(p, l); lex_take(p, l); return T_INC; }
    if lex_peek(p, l, 0) == 45 && lex_peek(p, l, 1) == 45 { lex_take(p, l); lex_take(p, l); return T_DEC; }
    if lex_peek(p, l, 0) == 61 && lex_peek(p, l, 1) == 61 { lex_take(p, l); lex_take(p, l); return T_EQ; }
    if lex_peek(p, l, 0) == 33 && lex_peek(p, l, 1) == 61 { lex_take(p, l); lex_take(p, l); return T_NEQ; }
    if lex_peek(p, l, 0) == 60 && lex_peek(p, l, 1) == 61 { lex_take(p, l); lex_take(p, l); return T_LTEQ; }
    if lex_peek(p, l, 0) == 62 && lex_peek(p, l, 1) == 61 { lex_take(p, l); lex_take(p, l); return T_GTEQ; }
    if lex_peek(p, l, 0) == 60 && lex_peek(p, l, 1) == 60 { lex_take(p, l); lex_take(p, l); return T_SHL; }
    if lex_peek(p, l, 0) == 62 && lex_peek(p, l, 1) == 62 { lex_take(p, l); lex_take(p, l); return T_SHR; }
    if lex_peek(p, l, 0) == 38 && lex_peek(p, l, 1) == 38 { lex_take(p, l); lex_take(p, l); return T_ANDAND; }
    if lex_peek(p, l, 0) == 124 && lex_peek(p, l, 1) == 124 { lex_take(p, l); lex_take(p, l); return T_OROR; }
    if lex_peek(p, l, 0) == 45 && lex_peek(p, l, 1) == 62 { lex_take(p, l); lex_take(p, l); return T_ARROW; }
    if lex_peek(p, l, 0) == 61 && lex_peek(p, l, 1) == 62 { lex_take(p, l); lex_take(p, l); return T_FATARROW; }
    if lex_peek(p, l, 0) == 40 { lex_take(p, l); return T_LPAREN; }
    if lex_peek(p, l, 0) == 41 { lex_take(p, l); return T_RPAREN; }
    if lex_peek(p, l, 0) == 91 { lex_take(p, l); return T_LBRACKET; }
    if lex_peek(p, l, 0) == 93 { lex_take(p, l); return T_RBRACKET; }
    if lex_peek(p, l, 0) == 123 { lex_take(p, l); return T_LCURLY; }
    if lex_peek(p, l, 0) == 125 { lex_take(p, l); return T_RCURLY; }
    if lex_peek(p, l, 0) == 44 { lex_take(p, l); return T_COMMA; }
    if lex_peek(p, l, 0) == 59 { lex_take(p, l); return T_SEMI; }
    if lex_peek(p, l, 0) == 58 { lex_take(p, l); return T_COLON; }
    if lex_peek(p, l, 0) == 63 { lex_take(p, l); return T_QUESTION; }
    if lex_peek(p, l, 0) == 46 { lex_take(p, l); return T_DOT; }
    if lex_peek(p, l, 0) == 43 { lex_take(p, l); return T_PLUS; }
    if lex_peek(p, l, 0) == 45 { lex_take(p, l); return T_MINUS; }
    if lex_peek(p, l, 0) == 42 { lex_take(p, l); return T_MUL; }
    if lex_peek(p, l, 0) == 47 { lex_take(p, l); return T_DIV; }
    if lex_peek(p, l, 0) == 37 { lex_take(p, l); return T_MOD; }
    if lex_peek(p, l, 0) == 61 { lex_take(p, l); return T_ASSIGN; }
    if lex_peek(p, l, 0) == 60 { lex_take(p, l); return T_LT; }
    if lex_peek(p, l, 0) == 62 { lex_take(p, l); return T_GT; }
    if lex_peek(p, l, 0) == 33 { lex_take(p, l); return T_NOT; }
    if lex_peek(p, l, 0) == 126 { lex_take(p, l); return T_BITNOT; }
    if lex_peek(p, l, 0) == 38 { lex_take(p, l); return T_BITAND; }
    if lex_peek(p, l, 0) == 124 { lex_take(p, l); return T_BITOR; }
    if lex_peek(p, l, 0) == 94 { lex_take(p, l); return T_XOR; }
    lex_take(p, l);
    return T_EOF;
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
fn lex_float(text: const u8[:], radix: i64) -> f64 {
    var numerator: u64[>..] = [0]; var denominator: u64[>..] = [1];
    var at = 0; if radix == 16 { at = 2; }
    var fraction = false; var fractional = 0; var significant = 0;
    while at < text.len {
        let byte = text[at];
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
            if exponent < 1000000 { exponent = exponent * 10 + text[at] as i64 - 48; }
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
