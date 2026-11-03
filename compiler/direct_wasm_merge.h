#pragma once
namespace goose::direct_wasm {

inline bool Function::BoundedMerge(While *loop) {
    if (c.opts.debug || emitting_guarded_loop ||
        (c.region_cursors && c.may_have_prefix_mappings) || loop->body->tail || loop->body->stmts.size() != 2) return false;
    auto both = Is<Binary>(loop->cond);
    auto choose = Is<IfExpr>(loop->body->stmts[0]);
    auto advance = Is<IncDec>(loop->body->stmts[1]);
    if (!both || both->op != T_ANDAND || !choose || !choose->elseb || !advance || advance->op != T_INC) return false;
    auto compare = Is<Binary>(choose->cond);
    if (!compare || (compare->op != T_LT && compare->op != T_LTEQ && compare->op != T_GT && compare->op != T_GTEQ)) return false;
    auto plain_integer = [](TypeExpr *type) {
        return IsIntT(type) && !type->ix && type->intstorage == IS_I64;
    };
    auto local = [&](Node *node) -> optional<Slot> {
        auto id = Is<Ident>(node);
        if (!id || !id->vdef) return {};
        auto def = Resolve(id->vdef);
        if (def->captured || def->reusable || addressed.count(def) || addressed.count(id->vdef)) return {};
        auto slot = Lookup(id->vdef, id->line);
        if (slot.kind != Slot::LOCAL || slot.type != id->exprtype) return {};
        return slot;
    };
    auto same = [&](Node *a, Node *b) {
        auto x = Is<Ident>(a), y = Is<Ident>(b);
        return x && y && x->vdef && y->vdef && Resolve(x->vdef) == Resolve(y->vdef);
    };
    auto output = Is<Ident>(advance->lval);
    auto output_slot = local(output);
    if (!output_slot || !plain_integer(output_slot->type)) return false;
    struct Arm { Index *source, *target, *read; Ident *cursor; Binary *bound; Slot view; };
    auto arm = [&](Block *body, Node *value) -> optional<Arm> {
        if (!body || body->tail || body->stmts.size() != 2) return {};
        auto store = Is<Assign>(body->stmts[0]); auto step = Is<IncDec>(body->stmts[1]);
        auto source = Is<Index>(value);
        if (!store || store->pointee || store->op != T_ASSIGN || !step || step->op != T_INC || !source) return {};
        auto target = Is<Index>(store->lval), read = Is<Index>(store->rhs);
        auto cursor = Is<Ident>(step->lval);
        auto cursor_slot = local(cursor), view = local(source->obj);
        if (!target || !read || !cursor_slot || !plain_integer(cursor_slot->type) || !view || view->type->kind != TY_SLICE ||
            !same(source->obj, read->obj) || !same(source->idx, cursor) || !same(read->idx, cursor) || !same(target->idx, output)) return {};
        if (!plain_integer(source->idx->exprtype) || !plain_integer(read->idx->exprtype) || !plain_integer(target->idx->exprtype)) return {};
        Binary *bound = nullptr;
        for (auto condition : { both->left, both->right }) {
            auto test = Is<Binary>(condition);
            if (test && (test->op == T_LT || test->op == T_LTEQ) && same(test->left, cursor)) bound = test;
        }
        if (!bound || !plain_integer(bound->left->exprtype) || !plain_integer(bound->right->exprtype)) return {};
        if (auto end = local(bound->right)) {
            if (!plain_integer(end->type)) return {};
        } else {
            auto length = Is<Dot>(bound->right);
            if (!length || length->member != B_LEN) return {};
            auto end_view = local(length->obj);
            if (!end_view || end_view->type->kind != TY_SLICE) return {};
        }
        return Arm { source, target, read, cursor, bound, *view };
    };
    auto left = arm(choose->thenb, compare->left), right = arm(Is<Block>(choose->elseb), compare->right);
    if (!left || !right || left->bound == right->bound || same(left->cursor, right->cursor) ||
        same(left->cursor, output) || same(right->cursor, output) || !same(left->target->obj, right->target->obj)) return false;
    auto destination = local(left->target->obj);
    if (!destination || destination->type->kind != TY_SLICE) return false;
    auto element = destination->type->sub;
    if (!IsIntT(element) || element->ix || Compiler::Varint(element) ||
        (element->intstorage != IS_I32 && element->intstorage != IS_U32 &&
         element->intstorage != IS_I64 && element->intstorage != IS_U64)) return false;
    for (auto entry : { *left, *right }) {
        if (entry.view.type->sub != element || entry.source->exprtype != element ||
            entry.read->exprtype != element || entry.target->exprtype != element ||
            entry.source->obj->exprtype != entry.view.type || entry.read->obj->exprtype != entry.view.type ||
            entry.target->obj->exprtype != destination->type) return false;
        for (auto cursor : { left->cursor, right->cursor, output })
            if (same(entry.bound->right, cursor)) return false;
    }
    // All range expressions are stable locals/lengths. These raw widened guard
    // computations cannot trap, even for invalid inputs; false retains scalar order.
    auto width = c.Size(element).size;
    struct Range { uint32_t pointer, begin, end, count; };
    auto range = [&](const Arm &entry) {
        Read(entry.view); code.Op(0xa7); auto pointer = Save(I32);
        Expr(entry.cursor); auto begin = Save(I64);
        Expr(entry.bound->right);
        if (entry.bound->op == T_LTEQ) { code.I64Const(1); code.Op(0x7c); }
        auto end = Save(I64);
        Get(end); Get(begin); code.Op(0x7d); auto count = Save(I64);
        return Range { pointer, begin, end, count };
    };
    auto a = range(*left), b = range(*right);
    Read(*destination); auto packed = Save(I64);
    Get(packed); code.Op(0xa7); auto pointer = Save(I32);
    Get(packed); code.I64Const(32); code.Op(0x88); auto length = Save(I64);
    Expr(output); auto position = Save(I64);
    Get(a.count); Get(b.count); code.Op(0x7c); auto count = Save(I64);
    code.OpU(0x3f, 0); code.Op(0xad); code.I64Const(16); code.Op(0x86); auto memory = Save(I64);
    code.I32Const(1);
    for (auto entry : { pair { *left, a }, pair { *right, b } }) {
        auto &r = entry.second;
        Get(r.begin); code.I64Const(0); code.Op(0x59); code.Op(0x71);
        Get(r.begin); Get(r.end); code.Op(0x54); code.Op(0x71);
        Get(r.end); Read(entry.first.view); code.I64Const(32); code.Op(0x88); code.Op(0x58); code.Op(0x71);
        Get(r.pointer); code.Op(0xad); Get(r.end); code.I64Const(width); code.Op(0x7e); code.Op(0x7c);
        Get(memory); code.Op(0x58); code.Op(0x71);
    }
    Get(position); code.I64Const(0); code.Op(0x59); code.Op(0x71);
    Get(position); Get(length); code.Op(0x58); code.Op(0x71);
    Get(count); Get(length); Get(position); code.Op(0x7d); code.Op(0x58); code.Op(0x71);
    Get(pointer); code.Op(0xad); Get(position); Get(count); code.Op(0x7c); code.I64Const(width); code.Op(0x7e); code.Op(0x7c);
    Get(memory); code.Op(0x58); code.Op(0x71);
    Begin(0x04);
    emitting_guarded_loop = true;
    auto done = Begin(), repeat = Begin(0x03);
    Truth(loop->cond); code.Op(0x45); Br(done, true);
    auto address = [&](uint32_t base, Ident *cursor) {
        Get(base); Expr(cursor); code.Op(0xa7); code.I32Const(width); code.Op(0x6c); code.Op(0x6a);
    };
    // The comparison already reads both values, in this order. No write or
    // callback intervenes before the selected RHS reload in the scalar loop.
    address(a.pointer, left->cursor); Load(element); auto av = Save(W(element));
    address(b.pointer, right->cursor); Load(element); auto bv = Save(W(element));
    Get(av); Get(bv); BinaryOp(compare->op, element, compare->line); auto take_left = Save(I32);
    address(pointer, output); Get(av); Get(bv); Get(take_left); code.Op(0x1b); Store(element);
    for (auto entry : { pair { left->cursor, false }, pair { right->cursor, true } }) {
        auto slot = Lookup(entry.first->vdef, entry.first->line);
        Read(slot); Get(take_left); if (entry.second) code.Op(0x45);
        code.Op(0xad); code.Op(0x7c); Write(slot);
    }
    Read(*output_slot); code.I64Const(1); code.Op(0x7c); Write(*output_slot);
    Br(repeat); End(); End();
    Else(); Expr(loop); End();
    emitting_guarded_loop = false;
    return true;
}

} // namespace goose::direct_wasm
