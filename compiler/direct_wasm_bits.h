#pragma once
namespace goose::direct_wasm {

inline bool PopcountWrapper(FnSpec *spec) {
    if (!spec || !spec->sf || spec->sf->isextern || spec->params.size() != 1 || spec->rets.size() != 1 ||
        !spec->body || !spec->needs.empty()) return false;
    auto body = spec->body;
    Node *returned = nullptr;
    if (body->stmts.size() == 3) returned = body->tail;
    else if (body->stmts.size() == 4 && !body->tail) returned = body->stmts[3];
    else return false;
    auto mask_init = Is<VarDecl>(body->stmts[0]), count_init = Is<VarDecl>(body->stmts[1]);
    auto loop = Is<While>(body->stmts[2]);
    if (!mask_init || !count_init || !loop || mask_init->byref || count_init->byref ||
        mask_init->isglobal || count_init->isglobal || mask_init->defs.size() != 1 || mask_init->inits.size() != 1 ||
        count_init->defs.size() != 1 || count_init->inits.size() != 1 || loop->body->tail || loop->body->stmts.size() != 2) return false;
    auto parameter = spec->params[0], mask = mask_init->defs[0], count = count_init->defs[0];
    if (parameter == mask || parameter == count || mask == count) return false;
    auto integer = [](TypeExpr *type) {
        return IsIntT(type) && !type->ix && !Compiler::Varint(type) && IntBits(type->intstorage) >= 8;
    };
    if (!integer(parameter->type) || !IsUnsigned(parameter->type->intstorage) || !integer(mask->type) ||
        !integer(count->type) || !integer(spec->rets[0]) || mask->type->intstorage != parameter->type->intstorage ||
        count->type->intstorage != spec->rets[0]->intstorage || mask->captured || count->captured) return false;
    auto same = [](Node *node, VarDef *variable) {
        auto id = Is<Ident>(node);
        return id && id->vdef == variable && IsIntT(id->exprtype) && id->exprtype->intstorage == variable->type->intstorage;
    };
    auto literal = [](Node *node, int64_t expected) {
        auto number = Is<IntLit>(node);
        return number && IsIntT(number->exprtype) && number->val == expected;
    };
    if (auto ret = Is<Return>(returned)) {
        if (ret->target != spec->sf || !ret->from.empty() || ret->vals.size() != 1) return false;
        returned = ret->vals[0];
    }
    if (!same(returned, count) || !same(mask_init->inits[0], parameter) || !literal(count_init->inits[0], 0)) return false;
    auto condition = Is<Binary>(loop->cond);
    auto clear = Is<Assign>(loop->body->stmts[0]); auto increment = Is<IncDec>(loop->body->stmts[1]);
    if (!condition || condition->op != T_NEQ || !same(condition->left, mask) || !literal(condition->right, 0) ||
        !clear || clear->pointee || clear->op != T_ANDEQ || !same(clear->lval, mask) ||
        !increment || increment->op != T_INC || !same(increment->lval, count)) return false;
    auto subtract = Is<Binary>(clear->rhs);
    return subtract && subtract->op == T_MINUS && same(subtract->left, mask) && literal(subtract->right, 1) &&
        IsIntT(subtract->exprtype) && subtract->exprtype->intstorage == mask->type->intstorage;
}

inline bool Function::FoldPopcount(While *loop, VarDecl *mask_init, VarDecl *count_init) {
    if (!mask_init || !count_init || mask_init->byref || count_init->byref ||
        mask_init->defs.size() != 1 || mask_init->inits.size() != 1 ||
        count_init->defs.size() != 1 || count_init->inits.size() != 1 ||
        loop->body->tail || loop->body->stmts.size() != 2) return false;
    auto literal = [](Node *value, int64_t expected) {
        auto number = Is<IntLit>(value);
        return number && IsIntT(value->exprtype) && number->val == expected;
    };
    if (!literal(count_init->inits[0], 0)) return false;
    auto mask = Lookup(mask_init->defs[0], mask_init->line);
    auto count = Lookup(count_init->defs[0], count_init->line);
    if (mask.kind != Slot::LOCAL || count.kind != Slot::LOCAL || mask.index == count.index ||
        !IsIntT(mask.type) || !IsIntT(count.type) || !IsUnsigned(mask.type->intstorage) ||
        Compiler::Varint(mask.type) || Compiler::Varint(count.type)) return false;
    auto width = IntBits(mask.type->intstorage);
    if ((width != 8 && width != 16 && width != 32 && width != 64) ||
        IntBits(count.type->intstorage) < 8) return false;
    auto same = [&](Node *value, const Slot &expected) {
        auto id = Is<Ident>(value);
        if (!id || !id->vdef || !IsIntT(value->exprtype) ||
            value->exprtype->intstorage != expected.type->intstorage) return false;
        auto slot = Lookup(id->vdef, id->line);
        return slot.kind == Slot::LOCAL && slot.index == expected.index && slot.type == expected.type;
    };
    auto condition = Is<Binary>(loop->cond);
    if (!condition || condition->op != T_NEQ || !same(condition->left, mask) ||
        !literal(condition->right, 0)) return false;
    auto clear = Is<Assign>(loop->body->stmts[0]);
    auto increment = Is<IncDec>(loop->body->stmts[1]);
    if (!clear || clear->pointee || clear->op != T_ANDEQ || !same(clear->lval, mask) ||
        !increment || increment->op != T_INC || !same(increment->lval, count)) return false;
    auto subtract = Is<Binary>(clear->rhs);
    if (!subtract || subtract->op != T_MINUS || !same(subtract->left, mask) ||
        !literal(subtract->right, 1) || !IsIntT(subtract->exprtype) ||
        subtract->exprtype->intstorage != mask.type->intstorage) return false;

    // Adjacent declarations normalize the private unsigned mask and start
    // count at zero. At most 64 increments fit every accepted counter, even
    // in debug mode; neither local can expose intermediate loop updates.
    Read(mask);
    if (W(mask.type) == I64) code.Op(0x7b);
    else code.Op(0x69);
    Convert(mask.type, count.type, loop->line); Write(count);
    Const(mask.type, 0); Write(mask);
    return true;
}

} // namespace goose::direct_wasm
