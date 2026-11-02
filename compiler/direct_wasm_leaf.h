#pragma once
namespace goose::direct_wasm {

inline bool Function::FrameFreeLeaf() {
    if (!spec) return false;
    if (auto cached = c.leaf_cache.find(spec); cached != c.leaf_cache.end()) return cached->second;
    auto reject = [&]() { c.leaf_cache[spec] = false; return false; };
    auto scalar = [](TypeExpr *type) {
        return type && ((IsIntT(type) && !Compiler::Varint(type)) ||
                        type->kind == TY_FLT || type->kind == TY_BOOL);
    };
    unordered_map<TypeExpr *, bool> fixed;
    unordered_set<TypeExpr *> active;
    function<bool(TypeExpr *)> numeric_data = [&](TypeExpr *type) {
        if (scalar(type)) return true;
        if (!type) return false;
        if (auto cached = fixed.find(type); cached != fixed.end()) return cached->second;
        if (!active.insert(type).second) return false;
        bool valid = false;
        if (type->kind == TY_ARRAY && type->arr->akind == A_FIXED && type->arr->size >= 0)
            valid = numeric_data(type->arr->sub);
        if (type->kind == TY_STRUCT && type->struc->inst && type->struc->inst->sclass == SC_FIXED) {
            valid = true;
            for (auto field : c.RecordFields(type)) if (field && !numeric_data(field)) { valid = false; break; }
        }
        active.erase(type); fixed[type] = valid; return valid;
    };
    auto plain = [&](TypeExpr *type) {
        if (!type || type->kind == TY_VOID || scalar(type)) return true;
        if (type->kind == TY_SLICE) return scalar(type->sub);
        return type->kind == TY_REF && !type->ref->optional && !type->ref->pool &&
               type->ref->lenstorage < 0 && numeric_data(type->ref->sub);
    };
    unordered_set<FnSpec *> seen;
    vector<FnSpec *> pending { spec };
    while (!pending.empty()) {
        auto member = pending.back(); pending.pop_back();
        if (!seen.insert(member).second) continue;
        if (seen.size() > 64) return reject();
        if (auto cached = c.leaf_cache.find(member); cached != c.leaf_cache.end()) {
            if (!cached->second) return reject();
            continue;
        }
        if (member->sf->isextern || c.effect_globals.count(member) || !c.captures[member].empty()) return reject();
        auto referenced = c.captured_storage; ScanAddressed(member->body, referenced);
        auto binding = [&](VarDef *variable) {
            return !variable || (plain(variable->type) && !referenced.count(variable));
        };
        for (auto parameter : member->params) if (!binding(parameter)) return reject();
        for (auto result : member->rets) if (!plain(result)) return reject();
        auto return_target = member->sf;
        function<bool(Node *)> local = [&](Node *node) {
            if (!node || Is<FnDecl>(node) || Is<StructDecl>(node) || Is<EnumDecl>(node) || Is<AliasDecl>(node)) return true;
            if (!plain(node->exprtype)) {
                if (!numeric_data(node->exprtype) ||
                    (!Is<Ident>(node) && !Is<Dot>(node) && !Is<Index>(node))) return false;
            }
            switch (node->nkind) {
                case NK_Ident:
                    if (!binding(static_cast<Ident *>(node)->vdef)) return false;
                    break;
                case NK_VarDecl:
                    for (auto variable : static_cast<VarDecl *>(node)->defs) if (!binding(variable)) return false;
                    break;
                case NK_ForLoop: {
                    auto loop = static_cast<ForLoop *>(node);
                    if (loop->byref || !binding(loop->vdef) || !binding(loop->idxdef)) return false;
                    break;
                }
                case NK_Return:
                    if (static_cast<Return *>(node)->target != return_target) return false;
                    break;
                case NK_InlineBlock: {
                    auto inlined = static_cast<InlineBlock *>(node);
                    if (!inlined->spec || !inlined->sf || !inlined->body || inlined->spec->sf != inlined->sf ||
                        inlined->sf->isextern || inlined->spec->lexparent || !c.captures[inlined->spec].empty() ||
                        (node->exprtype && node->exprtype->kind != TY_VOID && !scalar(node->exprtype))) return false;
                    for (auto parameter : inlined->spec->params) if (!scalar(parameter->type)) return false;
                    for (auto result : inlined->spec->rets) if (!scalar(result)) return false;
                    // Copied argument initializers belong to this occurrence.
                    // The original spec's body/cache is not a proof for them.
                    auto outer_target = return_target; return_target = inlined->sf;
                    auto valid = local(inlined->body); return_target = outer_target;
                    return valid;
                }
                case NK_Call: {
                    auto call = static_cast<Call *>(node);
                    if (call->builtin >= 0 || call->fvbody || call->defaultinit || !call->dispatch.empty() || !call->spec) return false;
                    if (!c.intrinsic_opcode.count(call->spec)) pending.push_back(call->spec);
                    for (auto argument : call->ValueArgNodes()) if (!local(argument)) return false;
                    return true;
                }
                case NK_Assign: {
                    auto assignment = static_cast<Assign *>(node);
                    auto target = assignment->lval->exprtype;
                    if (target->kind == TY_REF) target = target->ref->sub;
                    if (c.Aggregate(target) || c.Aggregate(assignment->rhs->exprtype)) return false;
                    break;
                }
                case NK_Dot: {
                    auto dot = static_cast<Dot *>(node);
                    if (dot->member != B_LEN && !dot->IsField()) return false;
                    break;
                }
                case NK_Unary:
                    if (static_cast<Unary *>(node)->op == T_BITAND) return false;
                    break;
                case NK_AsCast:
                    if (!scalar(node->exprtype) || !scalar(static_cast<AsCast *>(node)->totype)) return false;
                    break;
                case NK_Binary: {
                    auto binary = static_cast<Binary *>(node);
                    if (c.Aggregate(binary->left->exprtype) || c.Aggregate(binary->right->exprtype)) return false;
                    break;
                }
                case NK_Block: case NK_IfExpr: case NK_While: case NK_LoopExpr:
                case NK_RangeExpr: case NK_Break: case NK_Continue: case NK_IntLit:
                case NK_FltLit: case NK_BoolLit: case NK_Index: case NK_IncDec: break;
                default: return false;
            }
            bool valid = true;
            node->Children([&](Node *child) { if (valid) valid = local(child); });
            return valid;
        };
        if (!local(member->body)) return reject();
    }
    // A recursive back edge proves nothing on its own. Publish successes
    // only after every reachable member has passed the complete proof.
    for (auto member : seen) c.leaf_cache[member] = true;
    return true;
}

inline bool Compiler::Leaf(FnSpec *spec) {
    if (!spec || spec->sf->isextern) return false;
    if (auto found = leaf_cache.find(spec); found != leaf_cache.end()) return found->second;
    Function probe(*this, spec, 0, 0);
    return probe.frame_free;
}

} // namespace goose::direct_wasm
