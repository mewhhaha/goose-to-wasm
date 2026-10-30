// Compile with the actual checker/emitter; discard every producer allocation
// before importing, then discard every cache allocation before optimization.
#define main upstream_driver_main
#include "main.cpp"
#undef main
#include <iostream>
using namespace goose;

void Errors(const Ast &ast) {
    if (!ast.errors.empty()) throw runtime_error(ast.DiagnosticText(ast.errors.front(), true));
}
unique_ptr<Ast> Input(const string &text, bool reindex = false) {
    auto split = text.find("fn main()");
    assert(split != string::npos);
    auto ast = make_unique<Ast>(); ast->packages.push_back(Package {});
    ast->sources.emplace_back("main.goose", make_unique<string>(text.substr(split)));
    if (reindex) ast->sources.emplace_back("extra.goose", make_unique<string>("fn unused() {}"));
    ast->sources.emplace_back("leaves.goose", make_unique<string>(text.substr(0, split)));
    for (size_t i = 0; i < ast->sources.size(); ++i) {
        ast->filepkg.push_back(0);
        auto &[name, source] = ast->sources[i];
        Parser parser(*ast, name, source->c_str(), int(i), source->size()); parser.ParseTop();
    }
    Errors(*ast); ResolveTypeNames(*ast); Errors(*ast);
    return ast;
}
void Check(Ast &ast, CheckedLeafCache *cache) {
    CheckedLeafCacheScope scope(cache);
    if (cache) cache->BeginRequest();
    TypeCheckProgram(ast); Errors(ast);
}
string Emit(Ast &ast, int level, bool debug) {
    Optimizer optimizer(ast, level); BCE bce(ast); bce.RunAll();
    assert(bce.checkfreefails.empty());
    DirectWasmOptions options; options.debug = debug;
    return CompileDirectWasm(ast, options).module;
}
void Ownership(const string &text, int level, bool debug, bool reindex) {
    CheckedLeafCache cache;
    {
        auto producer = Input(text); Check(*producer, &cache);
        assert(cache.stored == 10 && cache.hits == 0);
        Emit(*producer, level, debug);
    }
    auto consumer = Input(text, reindex); Check(*consumer, &cache);
    assert(cache.hits == 10);
    cache.Clear(); assert(cache.entries.empty() && !cache.estimated_bytes);
    auto file = reindex ? 2 : 1;
    for (auto sf : consumer->functions) if (sf->line.fileidx == file) {
        for (auto spec : sf->specs) {
            for (auto p : spec->params) assert(p->ownerspec == spec && p->line.fileidx == file);
            function<void(Node *)> verify = [&](Node *n) {
                if (!n) return;
                if (n->line.line) assert(n->line.fileidx == file);
                if (n->origin && n->origin->line.line) assert(n->origin->line.fileidx == file);
                if (auto r = Is<Return>(n)) assert(r->target == sf && r->targetspec == spec);
                n->Children(verify);
            };
            verify(spec->body);
        }
    }
    auto fresh = Input(text, reindex); Check(*fresh, nullptr);
    assert(Emit(*consumer, level, debug) == Emit(*fresh, level, debug));
}
void Bounds(const string &text) {
    CheckedLeafCache tiny(64, 2), bounded(1024 * 1024, 2);
    auto input = Input(text); Check(*input, &tiny);
    assert(tiny.entries.empty() && !tiny.estimated_bytes && tiny.refused == 10);
    Check(*Input(text), &bounded);
    assert(bounded.entries.size() == 2 && bounded.evictions == 8);
    assert(bounded.estimated_bytes <= bounded.byte_limit);
    auto count = 0;
    for (auto &[key, leaf] : bounded.entries) { count += int(leaf.nodes.size()); assert(!key.empty()); }
    assert(count > 0);
}
int main(int argc, char **argv) {
    if (argc != 2) return 2;
    try {
        string text; assert(LoadSource(argv[1], text));
        for (int level : {0, 2}) for (bool debug : {false, true}) for (bool reindex : {false, true}) {
            Ownership(text, level, debug, reindex);
            cout << "PASS checked leaf ownership O" << level << " debug=" << debug << " reindex=" << reindex << '\n' << flush;
        }
        Bounds(text); cout << "PASS checked leaf bounded retention\n" << flush;
    } catch (const CompileError &e) { cerr << e.msg << '\n'; return 1; }
      catch (const exception &e) { cerr << e.what() << '\n'; return 1; }
}
