#pragma once
namespace goose::direct_wasm {

// This only decides whether a watermark may be needed. It never reserves a
// region or caches an expression's value; recursive calls remain unreserved.
inline bool Function::MayMaterialize(Node *node) {
    if (!node || Is<FnDecl>(node) || Is<FunVal>(node) || Is<StructDecl>(node) ||
        Is<EnumDecl>(node) || Is<AliasDecl>(node)) return false;
    auto type = node->exprtype;
    auto owned = Compiler::RegionArray(type) ||
        (type && type->kind == TY_REF && Compiler::RegionArray(type->ref->sub));
    if (auto call = Is<Call>(node)) {
        for (auto result : NaturalResults(node)) if (Compiler::RegionArray(result)) return true;
        if (owned) return true;
        for (auto arg : call->ValueArgNodes()) if (MayMaterialize(arg)) return true;
        return MayMaterialize(call->defaultinit) || MayMaterialize(call->fvbody);
    }
    if (auto inlined = Is<InlineBlock>(node); inlined && inlined->spec)
        for (auto result : inlined->spec->rets) if (Compiler::RegionArray(result)) return true;
    if (owned && (Is<ArrayLit>(node) || Is<StrLit>(node) || Is<Block>(node) ||
        Is<IfExpr>(node) || Is<MatchExpr>(node) || Is<EarlyBlock>(node) || Is<LoopExpr>(node))) return true;
    bool found = false;
    node->Children([&](Node *child) { if (!found) found = MayMaterialize(child); });
    return found;
}

inline Function::TempScope Function::BeginTempScope(Node *node) {
    TempScope scope { cleanups.size(), private_headers.size(), region_live, c.needs_regions && MayMaterialize(node) };
    if (scope.restores_regions) {
        code.OpU(0x23, G_REGION_NEXT);
        cleanups.push_back({ CleanupAction::RestoreRegionNext, Save(I32) });
    }
    temp_scopes.push_back(scope); return scope;
}

inline void Function::EndTempScope(const TempScope &scope) {
    assert(!temp_scopes.empty() && temp_scopes.back().cleanup_depth == scope.cleanup_depth);
    if (!scope.restores_regions && region_live != scope.region_live)
        Fail({}, "internal: a temporary scope changed regions without a watermark");
    CloseCleanups(scope.cleanup_depth);
    private_headers.resize(scope.private_depth);
    region_live = scope.region_live;
    temp_scopes.pop_back();
}

} // namespace goose::direct_wasm
