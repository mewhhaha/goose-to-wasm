// Included after the upstream parser. A cached Ast is never resolved, checked,
// optimized, or handed to an emitter. Only request-owned imports are mutated.
#pragma once
#include "parsed_module_clone.h"

namespace goose {

struct ParsedModule {
    Ast ast;
    vector<Import> imports;
    vector<Diagnostic> warnings;
    size_t estimated_bytes = 0;
    uint64_t touched = 0;
};

struct ParsedModuleCache {
    size_t byte_limit, file_limit, estimated_bytes = 0;
    uint64_t clock = 0;
    int64_t parsed_files = 0, cache_hits = 0, evictions = 0, bypassed_files = 0;
    map<pair<string, bool>, unique_ptr<ParsedModule>> modules;

    explicit ParsedModuleCache(size_t bytes = 64 * 1024 * 1024, size_t count = 128)
        : byte_limit(bytes), file_limit(count) {}

    void BeginRequest() { parsed_files = cache_hits = evictions = bypassed_files = 0; }
    void Clear() { modules.clear(); estimated_bytes = 0; }

    static bool Fetched(const Ast &ast, int fileidx) {
        auto pkg = ast.filepkg.at(fileidx);
        auto &p = ast.packages.at(pkg);
        return !p.cachekey.empty() || p.builtin >= 0;
    }

    static bool Collides(const Ast &source, Ast &destination) {
        auto type = [&](auto &symbols) {
            for (auto s : symbols)
                if (auto ns = destination.FindNS(s->ns); ns && ns->TypeNameExists(s->name)) return true;
            return false;
        };
        if (type(source.structs) || type(source.enums) || type(source.aliases)) return true;
        for (auto g : source.globals)
            if (auto ns = destination.FindNS(g->ns))
                for (auto name : g->names) if (ns->globalmap.count(name)) return true;
        return false;
    }

    static size_t Estimate(const ParsedModule &module) {
        auto &ast = module.ast;
        // A conservative estimate for pristine syntax, including node/detail
        // containers and child vectors. No checked products are retained.
        auto bytes = sizeof(ParsedModule) + ast.sources[0].second->size() * 16 +
                     ast.sources[0].first.capacity() * 2 + 4096;
        bytes += (ast.allnodes.size() + ast.typedetails.size() + ast.functions.size() +
                  ast.structs.size() + ast.enums.size() + ast.aliases.size()) * 1024;
        bytes += ast.alltypes.size() * 128;
        // Backtracked nodes remain allocated. Reading the string node itself
        // is safe; following its potentially abandoned syntax edges is not.
        for (auto n : ast.allnodes) if (auto s = Is<StrLit>(n)) bytes += s->val.capacity() + 32;
        for (auto &text : ast.interned) bytes += sizeof(string) + text.capacity() + 32;
        for (auto &i : module.imports) bytes += sizeof(Import) + i.path.capacity() + i.source.capacity() + 64;
        for (auto &d : module.warnings) bytes += sizeof(Diagnostic) + d.text.capacity() + d.message.capacity() + 64;
        return bytes;
    }

    void EvictOne() {
        auto oldest = modules.end();
        for (auto it = modules.begin(); it != modules.end(); ++it)
            if (oldest == modules.end() || it->second->touched < oldest->second->touched) oldest = it;
        if (oldest == modules.end()) return;
        estimated_bytes -= oldest->second->estimated_bytes;
        modules.erase(oldest); evictions++;
    }

    vector<Import> ParseFresh(Ast &ast, const string &filename, const string &source, int fileidx) {
        parsed_files++;
        Parser parser(ast, filename, source.c_str(), fileidx, source.size());
        parser.ParseTop();
        return std::move(parser.imports);
    }

    vector<Import> ImportInto(const ParsedModule &module, Ast &ast, int fileidx) {
        ParsedSyntaxImporter importer(module.ast, ast, fileidx);
        for (auto warning : module.warnings) {
            warning.where.fileidx = fileidx; warning.text.clear(); ast.Warn(std::move(warning));
        }
        auto imports = module.imports;
        for (auto &i : imports) {
            if (i.line.line) i.line.fileidx = fileidx;
            if (i.end.line) i.end.fileidx = fileidx;
        }
        return imports;
    }

    vector<Import> Parse(Ast &ast, const string &filename, const string &source, int fileidx) {
        ast.CheckCancel();
        auto fetched = Fetched(ast, fileidx);
        auto key = make_pair(filename, fetched);
        auto it = modules.find(key);
        if (it != modules.end()) {
            if (*it->second->ast.sources[0].second == source) {
                // The real parser sees accumulated namespaces. If a cached
                // declaration collides, let it produce the original recovery
                // behavior and diagnostic, rather than silently replacing it.
                if (Collides(it->second->ast, ast)) return ParseFresh(ast, filename, source, fileidx);
                it->second->touched = ++clock; cache_hits++;
                return ImportInto(*it->second, ast, fileidx);
            }
            estimated_bytes -= it->second->estimated_bytes;
            modules.erase(it);
        }
        if (!file_limit || source.size() > byte_limit / 16) {
            bypassed_files++; return ParseFresh(ast, filename, source, fileidx);
        }
        auto module = make_unique<ParsedModule>();
        module->ast.sources.emplace_back(filename, make_unique<string>(source));
        module->ast.filepkg.push_back(0);
        module->ast.packages.push_back(Package {});
        if (fetched) module->ast.packages[0].cachekey = "fetched";
        module->ast.cancel = ast.cancel;
        module->ast.sink = [&](const Diagnostic &d) { if (d.warning) module->warnings.push_back(d); };
        try {
            parsed_files++;
            Parser parser(module->ast, module->ast.sources[0].first, module->ast.sources[0].second->c_str(),
                          0, module->ast.sources[0].second->size());
            parser.ParseTop(); module->imports = std::move(parser.imports);
        } catch (const CompileError &) {
            // Candidate diagnostics were silent. Reparse into the real Ast to
            // preserve the original source indices and recovery/error order.
            return ParseFresh(ast, filename, source, fileidx);
        }
        module->ast.sink = {}; module->ast.cancel = nullptr;
        if (!module->ast.errors.empty() || Collides(module->ast, ast))
            return ParseFresh(ast, filename, source, fileidx);
        auto imports = ImportInto(*module, ast, fileidx);
        module->estimated_bytes = Estimate(*module);
        if (module->estimated_bytes > byte_limit) { bypassed_files++; return imports; }
        while (modules.size() >= file_limit || estimated_bytes > byte_limit - module->estimated_bytes) EvictOne();
        module->touched = ++clock;
        estimated_bytes += module->estimated_bytes;
        modules.emplace(std::move(key), std::move(module));
        return imports;
    }
};

inline thread_local ParsedModuleCache *active_parsed_cache = nullptr;
struct ParsedModuleCacheScope {
    ParsedModuleCache *previous;
    explicit ParsedModuleCacheScope(ParsedModuleCache *cache) : previous(active_parsed_cache) {
        active_parsed_cache = cache;
    }
    ~ParsedModuleCacheScope() { active_parsed_cache = previous; }
};

inline vector<Import> ParseDirectModule(Ast &ast, const string &filename, const string &source, int fileidx) {
    if (active_parsed_cache) return active_parsed_cache->Parse(ast, filename, source, fileidx);
    Parser parser(ast, filename, source.c_str(), fileidx, source.size());
    parser.ParseTop();
    return std::move(parser.imports);
}

}  // namespace goose
