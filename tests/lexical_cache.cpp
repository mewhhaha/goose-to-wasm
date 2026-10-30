// Compare complete lexer behavior with cold scanning and retained transitions.
#include "includes.h"
#include "utils.h"
#include "lexer_cache.h"
#include "lexer.h"
#include <iostream>
using namespace goose;

string State(const Lexer &l) {
    auto offset = [&](const char *p) { return p ? int64_t(p - l.source) : -1; };
    return cat(int(l.tok), ":", offset(l.p), ":", offset(l.linestart), ":", l.line,
        ":", offset(l.prevend), ":", offset(l.prevendlinestart), ":", l.prevendline,
        ":", l.fileidx, ":", offset(l.attr.data()), ":", l.attr.size(), ":", l.ival,
        ":", l.iuns, ":", bit_cast<uint64_t>(l.fval), ":", l.sval.size(), ":", hash<string>{}(l.sval),
        ":", l.smultiline, ":", l.tokline, ":", offset(l.toklinestart), ":", l.scanning,
        ":", offset(l.doc.data()), ":", l.doc.size(), ":", l.curlies);
}

vector<string> Trace(const string &source, string_view filename, int fileidx, LexicalCache *cache) {
    string fresh_source = source; // Every run owns a different source allocation.
    LexicalCacheScope scope(cache);
    if (cache) cache->BeginRequest();
    Lexer lex(filename, fresh_source.c_str(), fileidx, fresh_source.size());
    vector<string> result;
    for (int step = 0; step < 10000; step++) {
        result.push_back(State(lex));
        auto saved = lex;
        result.push_back(cat("peek:", int(lex.PeekTok())));
        assert(State(lex) == State(saved));
        if (lex.tok == T_EOF) {
            lex.Next(); result.push_back(State(lex)); // Repeated EOF is stable.
            break;
        }
        try {
            lex.Next();
            auto next = State(lex);
            lex = saved; lex.Next();
            assert(State(lex) == next);
        } catch (CompileError &e) {
            result.push_back("error:" + e.msg + ":" + State(lex));
            try { lex.SkipBrokenToken(); }
            catch (CompileError &again) { result.push_back("recovery:" + again.msg); break; }
        }
    }
    return result;
}

int main() {
    vector<string> corpus = {
        "// docs\r\n// next\r\nfn f(x: Vec<Vec<i64>>) { let x = 1 >> 2; }\r\n",
        "\"a\\0b\\xFF\\n\" '\\0' 18446744073709551615 0xffffffffffffffff 0x1.8p-3 2.5e3",
        "\"\"\"one line\"\"\" /* comment */ \"\"\"\r\n  a\r\n  b\r\n  \"\"\" {} // trailing",
        "fn bad() { \"bad\\q\"; }\nfn good() {}\n",
        "fn bad() { \"\"\"\n  bad\n    \"\"\"; }\nfn good() {}\n",
        "fn bad() { 0x; }\nfn good() {}\n",
        "fn bad() { /* unterminated",
        "fn bad() { \"unterminated\n }\nfn good() {}\n",
        "{}\n\t// docs\n/* blank */\n fn x() {}",
        string("fn f() {}\0ignored", 17),
    };
    LexicalCache cache;
    const char *tokens[] = {
        #define F(t, s) s,
        TOKENS_PUNCT TOKENS_KEYWORDS
        #undef F
        "0xffffffffffffffff", "0x1.8p-3", "4.3e+2", "18446744073709551616",
        "\"a\\0b\"", "\"bad\\q\"", "\"\"\"raw\"\"\"", "'\\xFF'", "0x", "identifier",
    };
    uint32_t random = 173;
    for (int trial = 0; trial < 128; trial++) {
        string text = "first "; // Constructor succeeds; later errors exercise recovery.
        for (int i = 0; i < 64; i++) {
            random = random * 1664525 + 1013904223;
            text += tokens[random % size(tokens)];
            text += i % 7 == 0 ? "\r\n// doc\r\n" : " ";
        }
        corpus.push_back(std::move(text));
    }
    for (auto &text : corpus) {
        auto expected = Trace(text, "first.goose", 3, nullptr);
        assert(Trace(text, "first.goose", 3, &cache) == expected);
        assert(Trace(text, "first.goose", 3, &cache) == expected);
        assert(cache.reused_tokens > 0);
        // Current request indices and filenames must appear in diagnostics.
        auto other = Trace(text, "other.goose", 91, nullptr);
        assert(Trace(text, "other.goose", 91, &cache) == other);
        auto reindexed = Trace(text, "first.goose", 5, nullptr);
        assert(Trace(text, "first.goose", 5, &cache) == reindexed);
    }
    // A recovery's incoming state is not a function of byte offset alone.
    string text = "a {\n b }";
    cache.BeginRequest();
    for (int guard = 0; guard < 3; guard++) {
        LexicalCacheScope scope(&cache);
        Lexer cached("guards", text.c_str()), cold = cached;
        auto ordinary = cached; ordinary.Next();
        if (guard == 0) cached.curlies = cold.curlies = 17;
        if (guard == 1) cached.line = cold.line = 44;
        if (guard == 2) cached.linestart = cold.linestart = text.c_str() + 1;
        { LexicalCacheScope disabled(nullptr); cold.Next(); }
        cached.Next(); assert(State(cold) == State(cached));
    }
    string shift = ">> x";
    cache.BeginRequest();
    {
        LexicalCacheScope scope(&cache);
        Lexer cached("shift", shift.c_str()), cold = cached;
        auto normal = cached; normal.Next();
        // Parsing nested generic arguments consumes >> as two > tokens.
        cached.tok = cold.tok = T_GT;
        { LexicalCacheScope disabled(nullptr); cold.Next(); }
        cached.Next(); assert(State(cold) == State(cached));
    }
    // Full-byte source identity includes data after the scanner's NUL sentinel.
    LexicalCache nul;
    Trace(string("x\0first", 7), "nul", 0, &nul);
    Trace(string("x\0other", 7), "nul", 0, &nul);
    assert(nul.reused_tokens == 0);

    LexicalCache bounded(4096, 2);
    for (int i = 0; i < 100; i++) {
        Trace("fn f() { 123 }", cat("file", i), i, &bounded);
        assert(bounded.accounted_bytes <= bounded.byte_limit && bounded.files.size() <= 2);
    }
    assert(bounded.evictions > 0);
    auto huge = string(5000, ' ');
    Trace(huge, "oversized", 0, &bounded);
    assert(bounded.bypassed_files == 1 && bounded.accounted_bytes <= 4096);

    LexicalCache pinned(4096, 1);
    pinned.BeginRequest();
    auto held = pinned.Attach("same", "old");
    auto bytes = pinned.accounted_bytes;
    assert(!pinned.Attach("same", "new"));
    assert(!pinned.Attach("other", "new"));
    assert(pinned.accounted_bytes == bytes);
    held.reset();
    assert(pinned.Attach("same", "new"));

    LexicalCache strings(4 * 1024 * 1024);
    string many = "\"" + string(128 * 1024, 's') + "\"";
    for (int i = 0; i < 2000; i++) many += " + 1";
    auto expected = Trace(many, "strings", 0, nullptr);
    assert(Trace(many, "strings", 0, &strings) == expected);
    assert(Trace(many, "strings", 0, &strings) == expected);
    size_t decoded_strings = 0;
    for (auto &[position, transition] : strings.files.at("strings")->transitions)
        decoded_strings += bool(transition.string_value);
    assert(decoded_strings == 1 && strings.scanned_tokens == 0);
    assert(strings.accounted_bytes < strings.byte_limit);
    cout << "lexer transitions, diagnostics, ownership, and cache bounds passed\n";
}
