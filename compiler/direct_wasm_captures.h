#pragma once
namespace goose::direct_wasm {

// Derive the emitted environment from the final checked/optimized tree, as the
// pinned C emitter does. Checker envreads is not an emitted free-variable list.
inline void Compiler::AnalyzeCaptures() {
    using Edge = pair<FnSpec *, Call *>;
    unordered_map<FnSpec *, vector<Edge>> calls;
    auto scan = [&](FnSpec *spec, const vector<Node *> &roots) {
        unordered_set<VarDef *> seen;
        set<pair<FnSpec *, Call *>> seen_calls;
        function<void(Node *)> walk = [&](Node *node) {
            if (!node || Is<FnDecl>(node) || Is<FunVal>(node) || Is<StructDecl>(node) ||
                Is<EnumDecl>(node) || Is<AliasDecl>(node)) return;
            if (auto id = Is<Ident>(node)) {
                auto v = id->vdef;
                if (v && v->type && v->type->kind != TY_FN && !v->isglobal &&
                    v->ownerspec != spec && seen.insert(v).second) captures[spec].push_back(v);
            }
            if (auto call = Is<Call>(node)) {
                auto edge = [&](FnSpec *callee) {
                    if (!callee || callee->sf->isextern || !reachable.count(callee) ||
                        (callee == spec && call->fvremap.empty())) return;
                    auto via = call->fvremap.empty() ? nullptr : call;
                    if (seen_calls.insert({ callee, via }).second) calls[spec].push_back({ callee, via });
                };
                if (!call->fvbody && call->builtin < 0) {
                    if (call->dispatch.empty()) edge(call->spec);
                    else for (auto arm : call->dispatch) edge(arm);
                }
                if (call->fvbody) walk(call->fvbody);
                for (auto arg : call->ValueArgNodes()) walk(arg);
                if (call->defaultinit) walk(call->defaultinit);
                return;
            }
            node->Children([&](Node *child) { walk(child); });
        };
        for (auto root : roots) walk(root);
    };
    for (auto spec : specs) scan(spec, { spec->body });
    vector<Node *> initializers;
    for (auto global : ast.globals) for (auto init : global->inits) initializers.push_back(init);
    scan(nullptr, initializers);
    vector<FnSpec *> callers = specs; callers.push_back(nullptr);
    for (bool changed = true; changed;) {
        changed = false;
        for (auto caller : callers) {
            auto &environment = captures[caller];
            unordered_set<VarDef *> seen(environment.begin(), environment.end());
            for (auto [callee, via] : calls[caller]) {
                // A remapped recursive edge may grow this same environment.
                auto source = captures[callee];
                for (auto capture : source) {
                    auto actual = via ? via->FreeVarArg(capture) : capture;
                    if (!actual->isglobal && actual->ownerspec != caller && seen.insert(actual).second) {
                        environment.push_back(actual); changed = true;
                    }
                }
            }
        }
    }
    for (auto caller : callers) {
        for (auto capture : captures[caller]) captured_storage.insert(capture);
        for (auto [callee, via] : calls[caller]) for (auto capture : captures[callee])
            captured_storage.insert(via ? via->FreeVarArg(capture) : capture);
    }
}

} // namespace goose::direct_wasm
