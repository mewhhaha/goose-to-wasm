#pragma once
namespace goose::direct_wasm {

inline bool Function::FrameFreeLeaf() {
    if (!spec || c.effect_globals.count(spec) || !c.captures[spec].empty()) return false;
    auto scalar = [](TypeExpr *type) {
        return type && ((IsIntT(type) && !Compiler::Varint(type)) ||
                        type->kind == TY_FLT || type->kind == TY_BOOL);
    };
    auto plain = [&](TypeExpr *type) {
        return !type || type->kind == TY_VOID || scalar(type) ||
               (type->kind == TY_SLICE && scalar(type->sub));
    };
    auto binding = [&](VarDef *variable) {
        return !variable || (plain(variable->type) && !addressed.count(variable));
    };
    for (auto parameter : spec->params) if (!binding(parameter)) return false;
    for (auto result : results) if (!plain(result)) return false;
    // A call-free scalar/view body cannot acquire owners, expose its stack,
    // or initiate a nonlocal return. Numeric Wasm intrinsics are also leaves.
    function<bool(Node *)> local = [&](Node *node) {
        if (!node || Is<FnDecl>(node) || Is<StructDecl>(node) ||
            Is<EnumDecl>(node) || Is<AliasDecl>(node)) return true;
        if (!plain(node->exprtype)) return false;
        switch (node->nkind) {
            case NK_Ident:
                if (!binding(static_cast<Ident *>(node)->vdef)) return false;
                break;
            case NK_VarDecl:
                for (auto variable : static_cast<VarDecl *>(node)->defs)
                    if (!binding(variable)) return false;
                break;
            case NK_ForLoop: {
                auto loop = static_cast<ForLoop *>(node);
                if (loop->byref || !binding(loop->vdef) || !binding(loop->idxdef)) return false;
                break;
            }
            case NK_Return:
                if (static_cast<Return *>(node)->target != spec->sf) return false;
                break;
            case NK_Call: {
                auto call = static_cast<Call *>(node);
                if (call->builtin >= 0 || call->fvbody || !call->dispatch.empty() ||
                    !c.intrinsic_opcode.count(call->spec)) return false;
                break;
            }
            case NK_Dot:
                if (static_cast<Dot *>(node)->member != B_LEN) return false;
                break;
            case NK_Block: case NK_IfExpr: case NK_While: case NK_LoopExpr:
            case NK_RangeExpr: case NK_Break: case NK_Continue: case NK_IntLit:
            case NK_FltLit: case NK_BoolLit: case NK_Unary: case NK_Binary:
            case NK_AsCast: case NK_Index: case NK_Assign: case NK_IncDec: break;
            default: return false;
        }
        bool valid = true;
        node->Children([&](Node *child) { if (valid) valid = local(child); });
        return valid;
    };
    return local(spec->body);
}

inline bool Compiler::Leaf(FnSpec *spec) {
    if (!spec || spec->sf->isextern) return false;
    if (auto found = leaf_cache.find(spec); found != leaf_cache.end()) return found->second;
    Function probe(*this, spec, 0, 0);
    return probe.frame_free;
}

} // namespace goose::direct_wasm
