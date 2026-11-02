#pragma once
namespace goose::direct_wasm {

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
