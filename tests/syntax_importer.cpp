// Use the actual frontend/checker/emitter definitions. The existing native
// build supplies its platform support and pinned third-party libraries.
#define main upstream_driver_main
#include "main.cpp"
#undef main
#include "parsed_module_cache.h"
#include <iostream>
using namespace goose;

void CheckErrors(const Ast &ast) {
    if (!ast.errors.empty()) throw runtime_error(ast.DiagnosticText(ast.errors.front(), true));
}

string SyntaxDump(const Ast &ast) {
    string result;
    for (auto n : ast.topdecls) n->Dump(result, 0);
    for (auto t : ast.alltypes) { t->Dump(result); result += '\n'; }
    return result;
}

unique_ptr<Ast> ImportSyntax(const Ast &original, const vector<unique_ptr<Ast>> &templates) {
    auto out = make_unique<Ast>();
    out->packages = original.packages; out->filepkg = original.filepkg;
    out->imports = original.imports;
    for (auto &[filename, text] : original.sources)
        out->sources.emplace_back(filename, make_unique<string>(*text));
    for (size_t i = 0; i < templates.size(); i++) ParsedSyntaxImporter(*templates[i], *out, int(i));
    // ParseProgram owns the import-graph initialization order. This independent
    // importer test restores that already-resolved order from the parsed input.
    vector<VarDecl *> globals;
    for (auto old : original.globals) {
        auto it = find_if(out->globals.begin(), out->globals.end(), [&](VarDecl *n) {
            return n->line.fileidx == old->line.fileidx && n->line.line == old->line.line &&
                   n->line.col == old->line.col && n->names == old->names;
        });
        assert(it != out->globals.end()); globals.push_back(*it);
    }
    out->globals = std::move(globals);
    assert(SyntaxDump(*out) == SyntaxDump(original));
    return out;
}

string Compile(Ast &ast, int level, bool emit) {
    ResolveTypeNames(ast); CheckErrors(ast);
    TypeCheckProgram(ast, false, false); CheckErrors(ast);
    Optimizer optimizer(ast, level);
    BCE bce(ast); bce.RunAll();
    if (!bce.checkfreefails.empty()) throw bce.CheckfreeError();
    DirectWasmOptions options; options.debug = level == 2;
    return emit ? CompileDirectWasm(ast, options).module : string();
}

void Test(const string &path, const string &stdlib, int level, bool emit) {
    Ast original;
    ParseProgram(original, path, {stdlib}, "", {}, true); CheckErrors(original);
    vector<unique_ptr<Ast>> templates;
    vector<string> dumps;
    for (size_t i = 0; i < original.sources.size(); i++) {
        auto ast = make_unique<Ast>();
        auto &[filename, text] = original.sources[i];
        ast->sources.emplace_back(filename, make_unique<string>(*text));
        ast->filepkg.push_back(0);
        ast->packages.push_back(original.packages[original.filepkg[i]]);
        Parser parser(*ast, ast->sources[0].first, ast->sources[0].second->c_str(), 0,
                      ast->sources[0].second->size());
        parser.ParseTop(); CheckErrors(*ast);
        dumps.push_back(SyntaxDump(*ast));
        templates.push_back(std::move(ast));
    }
    auto first = ImportSyntax(original, templates);
    auto first_module = Compile(*first, level, emit);
    for (size_t i = 0; i < templates.size(); i++) assert(SyntaxDump(*templates[i]) == dumps[i]);
    // The second import occurs after a full compilation of the first. Then
    // destroy every template before resolution/checking/emission: ASan must
    // catch any escaped syntax, type, symbol, origin, source, or interned view.
    auto second = ImportSyntax(original, templates);
    templates.clear(); dumps.clear();
    auto second_module = Compile(*second, level, emit);
    auto original_module = Compile(original, level, emit);
    assert(first_module == original_module && second_module == original_module);
}

unique_ptr<Ast> Input(const string &name, const string &text, bool fetched = false) {
    auto ast = make_unique<Ast>();
    ast->sources.emplace_back(name, make_unique<string>(text));
    ast->filepkg.push_back(0); ast->packages.push_back(Package {});
    if (fetched) ast->packages[0].cachekey = "fetched";
    return ast;
}

void TestCache() {
    auto text = string("extern \"bench_input\" fn input() -> i64; fn main() { print(3); }");
    ParsedModuleCache cache;
    string expected;
    for (int pass = 0; pass < 4; pass++) {
        auto fetched = pass == 2;
        auto ast = Input("context.goose", text, fetched);
        vector<Diagnostic> warnings;
        ast->sink = [&](const Diagnostic &d) { if (d.warning) warnings.push_back(d); };
        cache.BeginRequest();
        cache.Parse(*ast, ast->sources[0].first, *ast->sources[0].second, 0);
        CheckErrors(*ast);
        assert(warnings.size() == (fetched ? 0 : 1));
        assert(cache.cache_hits == (pass == 1 || pass == 3));
        auto module = Compile(*ast, 0, true);
        if (!pass) expected = module;
        assert(module == expected);
    }
    // Evict all templates after importing the final request, before checking.
    auto ast = Input("context.goose", text);
    cache.Parse(*ast, ast->sources[0].first, *ast->sources[0].second, 0);
    cache.Clear();
    assert(Compile(*ast, 0, true) == expected);

    // Oversized entries are imported correctly without retention. Repeated
    // small entries also respect both the storage estimate and file limit.
    ParsedModuleCache tiny(2048, 2), bounded(1024 * 1024, 2);
    for (int i = 0; i < 20; i++) {
        auto source = Input(cat("file", i), "fn main() { print(3); }");
        tiny.BeginRequest(); tiny.Parse(*source, source->sources[0].first, *source->sources[0].second, 0);
        assert(tiny.modules.empty() && tiny.estimated_bytes == 0 && tiny.bypassed_files == 1);
        assert(Compile(*source, 0, true) == expected);
        source = Input(cat("file", i), "fn main() { print(3); }");
        bounded.BeginRequest(); bounded.Parse(*source, source->sources[0].first, *source->sources[0].second, 0);
        assert(bounded.modules.size() <= 2 && bounded.estimated_bytes <= bounded.byte_limit);
    }
    assert(bounded.evictions > 0);
    cout << "PASS parsed cache context, eviction, and storage bounds\n" << flush;
}

int main(int argc, char **argv) {
    if (argc < 3) return 2;
    try {
        TestCache();
        bool emit = true;
        for (int i = 2; i < argc; i++) {
            string path = argv[i];
            if (path == "--frontend-only") { emit = false; continue; }
            for (int level : {0, 2}) Test(path, argv[1], level, emit);
            cout << "PASS syntax ownership " << path << '\n' << flush;
        }
    } catch (const CompileError &e) { cerr << e.msg << '\n'; return 1; }
      catch (const exception &e) { cerr << e.what() << '\n'; return 1; }
}
