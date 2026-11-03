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
    if (Compiler::RegionEnum(type)) return true;
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

inline bool Function::ResourceFreeBlock(Block *block) {
    auto scalar = [](TypeExpr *type) {
        return type && ((IsIntT(type) && !Compiler::Varint(type)) || type->kind == TY_FLT || type->kind == TY_BOOL);
    };
    auto plain = [&](TypeExpr *type) {
        return !type || type->kind == TY_VOID || scalar(type) || (type->kind == TY_SLICE && scalar(type->sub));
    };
    auto binding = [&](VarDef *variable) {
        return !variable || (plain(variable->type) && !variable->captured && !variable->reusable &&
            !addressed.count(Resolve(variable)));
    };
    auto borrowed_array = [&](Node *node) -> TypeExpr * {
        auto id = Is<Ident>(node);
        if (!id || !id->vdef) return nullptr;
        auto variable = Resolve(id->vdef);
        auto type = variable->type;
        if (type->kind != TY_ARRAY || !scalar(type->arr->sub) || variable->captured || variable->reusable) return nullptr;
        if (type == node->exprtype || (node->exprtype->kind == TY_SLICE && node->exprtype->sub == type->arr->sub)) return type;
        return nullptr;
    };
    int budget = 128;
    function<bool(Node *)> safe;
    auto view = [&](Node *node) {
        return borrowed_array(node) || (node && node->exprtype->kind == TY_SLICE && safe(node));
    };
    safe = [&](Node *node) {
        if (!node) return true;
        if (budget-- == 0 || !plain(node->exprtype)) return false;
        switch (node->nkind) {
            case NK_Call: {
                auto call = static_cast<Call *>(node);
                if (call->builtin >= 0 || call->fvbody || call->defaultinit || !call->dispatch.empty() || !call->spec ||
                    (!c.intrinsic_opcode.count(call->spec) && !c.Leaf(call->spec))) return false;
                auto arguments = call->ValueArgNodes();
                if (arguments.size() != call->spec->params.size()) return false;
                for (size_t i = 0; i < arguments.size(); i++) {
                    auto type = call->spec->params[i]->type;
                    auto argument = arguments[i];
                    if (!plain(type)) return false;
                    if (auto array = borrowed_array(argument); type->kind == TY_SLICE && array && array->arr->sub == type->sub) {
                        if (budget-- == 0) return false;
                        continue;
                    }
                    if (!safe(argument)) return false;
                }
                return true;
            }
            case NK_VarDecl: {
                auto decl = static_cast<VarDecl *>(node);
                if (decl->byref || decl->isglobal) return false;
                for (auto variable : decl->defs) if (!binding(variable)) return false;
                break;
            }
            case NK_Ident:
                return static_cast<Ident *>(node)->vdef && binding(static_cast<Ident *>(node)->vdef);
            case NK_ForLoop: {
                auto loop = static_cast<ForLoop *>(node);
                if (loop->byref || !binding(loop->vdef) || !binding(loop->idxdef)) return false;
                break;
            }
            case NK_Dot: {
                auto dot = static_cast<Dot *>(node);
                return dot->member == B_LEN && view(dot->obj);
            }
            case NK_Index: {
                auto index = static_cast<Index *>(node);
                return scalar(node->exprtype) && view(index->obj) && safe(index->idx);
            }
            case NK_Assign: {
                auto assign = static_cast<Assign *>(node);
                if (!plain(assign->lval->exprtype) || assign->op == T_DOTASSIGN || assign->pointee) return false;
                break;
            }
            case NK_Unary:
                if (static_cast<Unary *>(node)->op == T_BITAND) return false;
                break;
            case NK_AsCast:
                if (!scalar(node->exprtype) || !scalar(static_cast<AsCast *>(node)->totype) ||
                    (IsIntT(static_cast<AsCast *>(node)->totype) && static_cast<AsCast *>(node)->totype->ix)) return false;
                break;
            case NK_Block: case NK_IfExpr: case NK_While: case NK_RangeExpr:
            case NK_IntLit: case NK_FltLit: case NK_BoolLit: case NK_Binary: case NK_IncDec: break;
            default: return false;
        }
        bool valid = true;
        node->Children([&](Node *child) { if (valid) valid = safe(child); });
        return valid;
    };
    return safe(block);
}

inline Function::TempScope Function::BeginTempScope(Node *node, bool force) {
    TempScope scope { cleanups.size(), private_headers.size(), region_live, c.needs_regions && (force || MayMaterialize(node)) };
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
    if (cleanups.size() <= group.cleanup_depth || cleanups[group.cleanup_depth].kind != CleanupAction::RestoreRegionNext)
        Fail({}, "internal: unbalanced argument cleanup scope");
    for (size_t i = group.cleanup_depth + 1; i < cleanups.size(); i++)
        if (cleanups[i].kind != CleanupAction::ClearOwner) Fail({}, "internal: unbalanced argument owner scope");
    if (retain) {
        if (temp_scopes.empty() || !temp_scopes.back().restores_regions)
            Fail({}, "anonymous arguments require a restoring temporary scope");
        // Their borrowed results can still be used by the enclosing statement.
        // Dropping only this action transfers release to that statement.
        vector<CleanupAction> retained;
        for (size_t i = group.cleanup_depth + 1; i < cleanups.size(); i++) {
            auto action = cleanups[i];
            auto entry = find_if(owner_entries.begin(), owner_entries.end(), [&](auto &owner) { return owner.offset == action.saved_local; });
            if (entry != owner_entries.end() && entry->temporary) retained.push_back(action);
            else ClearEffectOwner(action.saved_local);
        }
        cleanups.resize(group.cleanup_depth);
        cleanups.insert(cleanups.end(), retained.begin(), retained.end());
    } else {
        CloseCleanups(group.cleanup_depth); region_live = group.region_live;
    }
}

inline ConstructionDestination Function::TemporaryDestination(TypeExpr *type, Line line) {
    if (!Compiler::RegionOwner(type) || temp_scopes.empty() || !temp_scopes.back().restores_regions)
        Fail(line, "anonymous owned construction requires a supported temporary scope");
    Location place { type, Slot { Slot::FRAME, FrameBytes(c.ControlLayout(type).size, c.ControlLayout(type).align), type } };
    AcquireRegion(place, line, {}, true);
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
