#pragma once
namespace goose::direct_wasm {

// This only decides whether a watermark may be needed. It never reserves a
// region or caches an expression's value; recursive calls remain unreserved.
inline bool Function::MayMaterialize(Node *node) {
    if (!node || Is<FnDecl>(node) || Is<FunVal>(node) || Is<StructDecl>(node) ||
        Is<EnumDecl>(node) || Is<AliasDecl>(node)) return false;
    if (auto literal = Is<ArrayLit>(node); literal && literal->capexpr) return true;
    if (auto assignment = Is<Assign>(node)) {
        auto target = assignment->lval->exprtype;
        if (target && target->kind == TY_REF) target = target->ref->sub;
        if (Compiler::RuntimeLimited(target)) return true;
    }
    auto type = node->exprtype;
    auto owned = Compiler::RegionOwner(type) ||
        (type && type->kind == TY_REF && Compiler::RegionOwner(type->ref->sub));
    if (auto call = Is<Call>(node)) {
        for (auto result : NaturalResults(node)) if (Compiler::RegionOwner(result)) return true;
        if (owned) return true;
        for (auto arg : call->ValueArgNodes()) if (MayMaterialize(arg)) return true;
        return MayMaterialize(call->defaultinit) || MayMaterialize(call->fvbody);
    }
    if (auto inlined = Is<InlineBlock>(node); inlined && inlined->spec)
        for (auto result : inlined->spec->rets) if (Compiler::RegionOwner(result)) return true;
    if (owned && (Is<ArrayLit>(node) || Is<StrLit>(node) || Is<StructLit>(node) || Is<Block>(node) ||
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

inline Function::ArgumentGroup Function::BeginArgumentGroup(bool active) {
    ArgumentGroup group { cleanups.size(), region_live, anonymous_serial, active };
    if (active) {
        code.OpU(0x23, G_REGION_NEXT);
        cleanups.push_back({ CleanupAction::RestoreRegionNext, Save(I32) });
    }
    return group;
}

inline void Function::EndArgumentGroup(const ArgumentGroup &group, bool retain) {
    if (!group.active) return;
    if (cleanups.size() != group.cleanup_depth + 1 || cleanups.back().kind != CleanupAction::RestoreRegionNext)
        Fail({}, "internal: unbalanced argument cleanup scope");
    if (retain) {
        if (temp_scopes.empty() || !temp_scopes.back().restores_regions)
            Fail({}, "anonymous arguments require a restoring temporary scope");
        // Their borrowed results can still be used by the enclosing statement.
        // Dropping only this action transfers release to that statement.
        cleanups.resize(group.cleanup_depth);
    } else {
        CloseCleanups(group.cleanup_depth); region_live = group.region_live;
    }
}

inline ConstructionDestination Function::TemporaryDestination(TypeExpr *type, Line line) {
    if (!Compiler::RegionOwner(type) || temp_scopes.empty() || !temp_scopes.back().restores_regions)
        Fail(line, "anonymous owned construction requires a supported temporary scope");
    Location place { type, Slot { Slot::FRAME, FrameBytes(c.ControlLayout(type).size, c.ControlLayout(type).align), type } };
    AcquireRegion(place, line);
    private_headers.push_back({ TailHeaderLocation(place), temp_scopes.back().cleanup_depth + 1, true });
    if (anonymous_serial == UINT64_MAX) Fail(line, "too many anonymous construction sites");
    anonymous_serial++;
    return { place, ConstructionDestination::Statement };
}

inline void Function::Materialize(Node *node, TypeExpr *type, bool adapt_result) {
    auto destination = TemporaryDestination(type, node->line);
    ConstructRegionInto(node, destination);
    LocationAddress(destination.location);
    if (!adapt_result) return;
    if (!node->exprtype) Fail(node->line, "anonymous result type was not resolved");
    if (node->exprtype->kind == TY_VOID) code.Op(0x1a);
    else Convert(type, node->exprtype, node->line);
}

} // namespace goose::direct_wasm
