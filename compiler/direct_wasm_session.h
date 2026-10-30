// Included after the upstream driver definitions. A request owns all source
// snapshots and its complete mutable Ast. No checked nodes escape the request.
#pragma once
#include <iostream>
#include <stdexcept>
namespace goose {

struct DirectCompileRequest {
    string source, stdlib;
    int optimization = 2;
    bool offline = false, lexical_cache = false, syntax_cache = false;
    bool checked_leaf_cache = false;
    bool checked_scalar_cache = false;
    DirectWasmOptions options;
    map<string, string> sources;
};
struct DirectCompileOutput { string module, dependencies, stats; vector<string> inputs; };

inline string DirectSessionPath(const string &path) {
    error_code error;
    auto resolved = filesystem::weakly_canonical(filesystem::absolute(path), error);
    if (error) throw runtime_error(cat("cannot resolve path: ", path));
    return PathKey(resolved.string());
}
inline bool DirectSessionSameFile(const string &a, const string &b) {
    auto left = filesystem::absolute(a);
    auto right = filesystem::absolute(b);
    if (left == right) return true;
    error_code error;
    auto same = filesystem::equivalent(a, b, error);
    if (!error && same) return true;
    left = filesystem::weakly_canonical(left, error);
    if (error) return false;
    right = filesystem::weakly_canonical(right, error);
    return !error && PathKey(left.string()) == PathKey(right.string());
}

inline DirectCompileOutput CompileDirectRequest(const DirectCompileRequest &request,
                                                const string &exe, string &diagnostics,
                                                LexicalCache *lexical = nullptr,
                                                ParsedModuleCache *syntax = nullptr,
                                                CheckedLeafCache *leaves = nullptr) {
    LexicalCacheScope cache_scope(lexical);
    ParsedModuleCacheScope syntax_scope(syntax);
    CheckedLeafCacheScope leaf_scope(leaves, request.checked_scalar_cache);
    DirectInputTrace input_trace;
    DirectInputTraceScope input_scope(&input_trace);
    if (lexical) lexical->BeginRequest();
    if (syntax) syntax->BeginRequest();
    if (leaves) leaves->BeginRequest();
    auto started = chrono::steady_clock::now();
    struct FetchMode {
        bool previous;
        FetchMode(bool offline) : previous(package_nofetch) { package_nofetch = offline; }
        ~FetchMode() { package_nofetch = previous; }
    } fetching(request.offline);
    Ast ast;
    ast.sink = [&](const Diagnostic &d) {
        diagnostics += (d.text.empty() ? ast.DiagnosticText(d, true) : d.text) + "\n";
    };
    SourceProvider sources = [&](const string &path) -> const string * {
        if (request.sources.empty()) return nullptr;
        auto it = request.sources.find(DirectSessionPath(path));
        if (it != request.sources.end()) return &it->second;
        for (auto &[name, text] : request.sources)
            if (DirectSessionSameFile(path, name)) return &text;
        return nullptr;
    };
    auto check = [&]() {
        if (!ast.errors.empty()) throw CompileError { "source contains errors" };
    };
    ParseProgram(ast, request.source, StdlibDirs(request.stdlib, exe), DirOf(exe), sources, true);
    auto parsed = chrono::steady_clock::now(); check();
    ResolveTypeNames(ast);
    auto resolved = chrono::steady_clock::now(); check();
    TypeCheckProgram(ast, false, false);
    auto checked = chrono::steady_clock::now(); check();
    Optimizer optimizer(ast, request.optimization);
    auto optimized = chrono::steady_clock::now();
    BCE bce(ast); bce.RunAll();
    if (!bce.checkfreefails.empty()) throw bce.CheckfreeError();
    auto bounded = chrono::steady_clock::now();
    auto compiled = CompileDirectWasm(ast, request.options);
    auto emitted = chrono::steady_clock::now();
    auto ns = [](auto a, auto b) -> int64_t {
        return chrono::duration_cast<chrono::nanoseconds>(b - a).count();
    };
    auto dependencies = DirectDependenciesJson(ast, input_trace);
    vector<string> inputs;
    for (auto &[path, text] : ast.sources) inputs.push_back(path);
    for (auto &input : input_trace.observations) inputs.push_back(input.path);
    JsonOut stats; stats.BeginObject();
    stats.Member("backend", "direct");
    stats.Member("functions", int64_t(compiled.functions));
    stats.Member("code_bytes", int64_t(compiled.code_bytes));
    stats.Member("module_bytes", int64_t(compiled.module.size()));
    stats.Member("backend_ns", ns(bounded, emitted));
    stats.Member("parse_ns", ns(started, parsed));
    stats.Member("resolve_ns", ns(parsed, resolved));
    stats.Member("typecheck_ns", ns(resolved, checked));
    stats.Member("optimize_ns", ns(checked, optimized));
    stats.Member("bce_ns", ns(optimized, bounded));
    stats.Member("frontend_ns", ns(started, bounded));
    stats.Member("source_files", int64_t(ast.sources.size()));
    stats.Member("specializations", int64_t(ast.fnspecs.size()));
    stats.Member("parsed_files", syntax ? syntax->parsed_files : int64_t(ast.sources.size()));
    stats.Member("parsed_cache_hits", syntax ? syntax->cache_hits : 0);
    stats.Member("parsed_syntax_reused", syntax && syntax->cache_hits > 0);
    stats.Member("syntax_cache_enabled", syntax != nullptr);
    stats.Member("semantic_reused", leaves && leaves->hits > 0);
    stats.Member("checked_leaf_cache_enabled", leaves && !request.checked_scalar_cache);
    stats.Member("checked_scalar_cache_enabled", leaves && request.checked_scalar_cache);
    stats.Member("checked_leaf_reused", leaves && leaves->leaf_hits > 0);
    stats.Member("checked_scalar_reused", leaves && request.checked_scalar_cache && leaves->hits > 0);
    if (leaves) {
        string prefix = request.checked_scalar_cache ? "checked_scalar_cache_" : "checked_leaf_cache_";
        stats.Member(prefix + "hits", leaves->hits);
        stats.Member(prefix + "misses", leaves->misses);
        stats.Member(prefix + "stored", leaves->stored);
        stats.Member(prefix + "refused", leaves->refused);
        stats.Member(prefix + "evictions", leaves->evictions);
        stats.Member(prefix + "entries", int64_t(leaves->entries.size()));
        stats.Member(prefix + "estimated_bytes", int64_t(leaves->estimated_bytes));
        if (request.checked_scalar_cache) {
            stats.Member("checked_scalar_leaf_hits", leaves->leaf_hits);
            stats.Member("checked_scalar_caller_hits", leaves->caller_hits);
        }
    }
    stats.Member("frontend_reused", false);
    if (syntax) {
        stats.Member("syntax_cache_files", int64_t(syntax->modules.size()));
        stats.Member("syntax_cache_estimated_bytes", int64_t(syntax->estimated_bytes));
        stats.Member("syntax_cache_evictions", syntax->evictions);
        stats.Member("syntax_cache_bypassed_files", syntax->bypassed_files);
    }
    stats.Member("overlay_files", int64_t(request.sources.size()));
    stats.Member("lexical_cache_enabled", lexical != nullptr);
    if (lexical) {
        stats.Member("scanned_source_files", lexical->scanned_files + lexical->bypassed_files);
        stats.Member("lexical_reused_files", lexical->reused_files);
        stats.Member("lexical_scanned_tokens", lexical->scanned_tokens);
        stats.Member("lexical_reused_tokens", lexical->reused_tokens);
        stats.Member("lexical_lookahead_hits", lexical->lookahead_hits);
        stats.Member("lexical_cache_evictions", lexical->evictions);
        stats.Member("lexical_cache_bypassed_files", lexical->bypassed_files);
        stats.Member("lexical_cache_files", int64_t(lexical->files.size()));
        stats.Member("lexical_cache_estimated_bytes", int64_t(lexical->accounted_bytes));
    }
    stats.Key("function_info"); stats.BeginArray();
    for (auto &f : compiled.function_info) {
        stats.BeginObject(); stats.Member("name", f.name); stats.Member("index", int64_t(f.index));
        stats.Member("code_bytes", int64_t(f.code_bytes)); stats.Member("body_hash", to_string(f.body_hash));
        stats.Key("dependencies"); stats.BeginArray();
        for (auto d : f.dependencies) stats.Int(d);
        stats.EndArray(); stats.EndObject();
    }
    stats.EndArray(); stats.EndObject();
    return { std::move(compiled.module), std::move(dependencies), std::move(stats.s), std::move(inputs) };
}

inline int RunDirectSession(const string &exe) {
    LexicalCache lexical;
    ParsedModuleCache syntax;
    CheckedLeafCache leaves;
    string line;
    while (getline(cin, line)) {
        string id = "null", diagnostics;
        JsonOut reply; reply.BeginObject();
        try {
            if (line.size() > 16 * 1024 * 1024) throw runtime_error("request exceeds 16 MiB");
            auto json = ParseJson(line);
            if (json.kind != Json::OBJECT) throw runtime_error("request must be an object");
            if (auto value = json.Get("id")) {
                if (value->kind == Json::STRING) { id.clear(); JsonQuote(id, value->str); }
                else if (value->kind == Json::NUMBER && isfinite(value->num) &&
                         floor(value->num) == value->num && fabs(value->num) <= 9007199254740991.0)
                    id = to_string(int64_t(value->num));
                else if (value->kind != Json::NUL) throw runtime_error("id must be a string, safe integer, or null");
            }
            DirectCompileRequest request;
            auto string_field = [&](const char *key, bool required = false) {
                auto value = json.Get(key);
                if (value && value->kind != Json::STRING) throw runtime_error(cat(key, " must be a string"));
                auto text = value ? value->str : string();
                if (required && text.empty()) throw runtime_error(cat(key, " is required"));
                if (text.find('\0') != string::npos) throw runtime_error("paths must not contain NUL bytes");
                return text;
            };
            auto integer = [&](const char *key, int fallback, int low, int high) {
                auto value = json.Get(key);
                if (!value) return fallback;
                if (value->kind != Json::NUMBER || !isfinite(value->num) || floor(value->num) != value->num ||
                    value->num < low || value->num > high) throw runtime_error(cat("invalid ", key));
                return int(value->num);
            };
            auto boolean = [&](const char *key) {
                auto value = json.Get(key);
                if (value && value->kind != Json::BOOL) throw runtime_error(cat(key, " must be a bool"));
                return value && value->b;
            };
            request.source = DirectSessionPath(string_field("source", true));
            if (!FileExists(request.source)) throw runtime_error("source file does not exist");
            auto output = string_field("output", true);
            request.stdlib = string_field("stdlib");
            request.optimization = integer("optimization", 2, 0, 2);
            request.options.initial_pages = uint32_t(integer("initial_pages", 16, 1, 32768));
            request.options.maximum_pages = uint32_t(integer("maximum_pages", 256, 1, 32768));
            request.options.debug = boolean("debug"); request.offline = boolean("offline");
            request.lexical_cache = boolean("lexical_cache");
            request.syntax_cache = boolean("syntax_cache");
            request.checked_leaf_cache = boolean("checked_leaf_cache");
            request.checked_scalar_cache = boolean("checked_scalar_cache");
            if (auto overlays = json.Get("sources")) {
                if (overlays->kind != Json::OBJECT) throw runtime_error("sources must be a path-to-text object");
                for (auto &[path, value] : overlays->obj) {
                    if (path.find('\0') != string::npos) throw runtime_error("paths must not contain NUL bytes");
                    if (value.kind != Json::STRING) throw runtime_error("source text must be a string");
                    if (!FileExists(path)) throw runtime_error("source overlays require existing files");
                    // ParseProgram removes one UTF-8 BOM, just as LoadSource
                    // does for disk inputs. Keep the overlay bytes intact here.
                    auto text = value.str;
                    for (auto &[name, previous] : request.sources)
                        if (DirectSessionSameFile(path, name)) throw runtime_error("duplicate source overlay path");
                    if (!request.sources.emplace(DirectSessionPath(path), std::move(text)).second)
                        throw runtime_error("duplicate source overlay path");
                }
            }
            DirectCompileOutput result;
            RunOnCompilerStack([&]() {
                result = CompileDirectRequest(request, exe, diagnostics,
                    request.lexical_cache ? &lexical : nullptr, request.syntax_cache ? &syntax : nullptr,
                    request.checked_leaf_cache || request.checked_scalar_cache ? &leaves : nullptr);
                return 0;
            });
            if (DirectSessionSameFile(output, exe)) throw runtime_error("output must not overwrite the compiler");
            for (auto &input : result.inputs)
                if (DirectSessionSameFile(output, input)) throw runtime_error("output must not overwrite a source input");
            for (auto &[input, text] : request.sources)
                if (DirectSessionSameFile(output, input)) throw runtime_error("output must not overwrite a source overlay");
            if (!WriteFileMakingDirs(output, result.module)) throw CompileError { "cannot write WebAssembly output" };
            reply.Key("id"); reply.Raw(id); reply.Member("ok", true);
            reply.Member("diagnostics", diagnostics);
            reply.Key("dependencies"); reply.Raw(result.dependencies);
            reply.Key("stats"); reply.Raw(result.stats);
        } catch (const CompileError &error) {
            if (diagnostics.find(error.msg) == string::npos) diagnostics += error.msg;
            reply.Key("id"); reply.Raw(id); reply.Member("ok", false); reply.Member("error", diagnostics);
        } catch (const exception &error) {
            reply.Key("id"); reply.Raw(id); reply.Member("ok", false); reply.Member("error", error.what());
        }
        reply.EndObject(); cout << reply.s << '\n' << flush;
    }
    return 0;
}

} // namespace goose
