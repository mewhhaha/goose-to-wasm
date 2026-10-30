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
void Check(Ast &ast, CheckedLeafCache *cache, bool callers = false) {
    CheckedLeafCacheScope scope(cache, callers);
    if (cache) cache->BeginRequest();
    TypeCheckProgram(ast); Errors(ast);
}
string Emit(Ast &ast, int level, bool debug) {
    Optimizer optimizer(ast, level); BCE bce(ast); bce.RunAll();
    assert(bce.checkfreefails.empty());
    DirectWasmOptions options; options.debug = debug;
    return CompileDirectWasm(ast, options).module;
}
void Ownership(const string &text, int level, bool debug, bool reindex, bool callers = false) {
    CheckedLeafCache cache;
    {
        auto producer = Input(text); Check(*producer, &cache, callers);
        assert(cache.stored == (callers ? 8 : 10) && cache.hits == 0);
        Emit(*producer, level, debug);
    }
    auto consumer = Input(text, reindex); Check(*consumer, &cache, callers);
    assert(cache.hits == (callers ? 8 : 10));
    if (callers) assert(cache.caller_hits == 6);
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
                if (auto c = Is<Call>(n)) {
                    assert(c->spec && !c->spec->inprogress);
                    assert(find(consumer->fnspecs.begin(), consumer->fnspecs.end(), c->spec) != consumer->fnspecs.end());
                }
                n->Children(verify);
            };
            verify(spec->body);
        }
    }
    auto fresh = Input(text, reindex); Check(*fresh, nullptr);
    assert(Emit(*consumer, level, debug) == Emit(*fresh, level, debug));
}
void NestedEviction(int level, bool debug, bool reindex) {
    string text = "fn base(x: i64) -> i64 { x + 1 }\n"
                  "fn parent(x: i64) -> i64 { base(x) * 2 }\n"
                  "fn main() { print(parent(3)); }\n";
    CheckedLeafCache cache(1024 * 1024, 1);
    {
        auto producer = Input(text); Check(*producer, &cache, true);
        assert(cache.entries.size() == 1 && cache.stored == 2);
        Emit(*producer, level, debug);
    }
    text.replace(text.find("x + 1"), 5, "x + 10");
    auto consumer = Input(text, reindex); Check(*consumer, &cache, true);
    assert(cache.caller_hits == 1 && cache.misses == 1 && cache.evictions >= 1);
    cache.Clear();
    auto fresh = Input(text, reindex); Check(*fresh, nullptr);
    assert(Emit(*consumer, level, debug) == Emit(*fresh, level, debug));
}
void GraphDepth() {
    string text = "fn step0(x: i64) -> i64 { x + 1 }\n";
    for (int i = 1; i < 130; ++i)
        Append(text, "fn step", i, "(x: i64) -> i64 { step", i - 1, "(x) * 3 + ", i, " }\n");
    text += "fn main() { print(step129(3)); }\n";
    auto ast = Input(text);
    auto candidate = [&](int i) {
        FnSpec spec; spec.sf = ast->LookupFunctions(cat("step", i), "").at(0);
        spec.argtypes = {ast->inttypes[IS_I64]}; return spec;
    };
    auto root = candidate(129), suffix = candidate(100);
    checked_leaf::GraphContext cold, warm;
    assert(!cold.PrepareCaller(*ast, &root));
    assert(warm.PrepareCaller(*ast, &suffix));
    assert(!warm.PrepareCaller(*ast, &root));
    cout << "PASS scalar graph depth with cold and memoized suffixes\n" << flush;
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
    if (argc != 3) return 2;
    try {
        string text; assert(LoadSource(argv[1], text));
        for (int level : {0, 2}) for (bool debug : {false, true}) for (bool reindex : {false, true}) {
            Ownership(text, level, debug, reindex);
            cout << "PASS checked leaf ownership O" << level << " debug=" << debug << " reindex=" << reindex << '\n' << flush;
        }
        Bounds(text); cout << "PASS checked leaf bounded retention\n" << flush;
        assert(LoadSource(argv[2], text));
        for (int level : {0, 2}) for (bool debug : {false, true}) for (bool reindex : {false, true}) {
            Ownership(text, level, debug, reindex, true);
            cout << "PASS scalar caller ownership O" << level << " debug=" << debug << " reindex=" << reindex << '\n' << flush;
            NestedEviction(level, debug, reindex);
            cout << "PASS scalar nested eviction O" << level << " debug=" << debug << " reindex=" << reindex << '\n' << flush;
        }
        GraphDepth();
    } catch (const CompileError &e) { cerr << e.msg << '\n'; return 1; }
      catch (const exception &e) { cerr << e.what() << '\n'; return 1; }
}
