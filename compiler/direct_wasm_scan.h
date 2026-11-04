#pragma once
namespace goose::direct_wasm {

inline bool Function::ByteScan(While *loop) {
    if (c.opts.debug || emitting_guarded_loop || (c.region_cursors && c.may_have_prefix_mappings) ||
        loop->body->tail || loop->body->stmts.size() != 2) return false;
    auto condition = Is<Binary>(loop->cond);
    auto choose = Is<IfExpr>(loop->body->stmts[0]);
    if (!condition || (condition->op != T_LT && condition->op != T_LTEQ) || !choose || choose->elseb ||
        choose->thenb->tail || choose->thenb->stmts.size() != 2) return false;
    auto predicate = Is<Binary>(choose->cond);
    auto remember = Is<Assign>(choose->thenb->stmts[0]);
    auto increment = Is<IncDec>(choose->thenb->stmts[1]);
    if (!predicate || predicate->op != T_EQ || !remember || remember->pointee || remember->op != T_ASSIGN ||
        !increment || increment->op != T_INC) return false;
    auto source = Is<Index>(predicate->left); auto value = Is<IntLit>(predicate->right);
    if (!source || !value) return false;
    auto plain = [](TypeExpr *type) { return IsIntT(type) && !type->ix && type->intstorage == IS_I64; };
    auto local = [&](Node *node) -> optional<Slot> {
        auto id = Is<Ident>(node);
        if (!id || !id->vdef || !plain(id->exprtype)) return {};
        auto def = Resolve(id->vdef); auto slot = Lookup(id->vdef, id->line);
        if (def->captured || def->reusable || addressed.count(def) || addressed.count(id->vdef) ||
            slot.kind != Slot::LOCAL || slot.type != id->exprtype) return {};
        return slot;
    };
    auto same = [&](Node *a, Node *b) {
        auto x = Is<Ident>(a), y = Is<Ident>(b);
        return x && y && x->vdef && y->vdef && Resolve(x->vdef) == Resolve(y->vdef);
    };
    auto cursor = Is<Ident>(condition->left);
    auto counter = local(cursor), last = local(remember->lval), count = local(increment->lval);
    if (!counter || !last || !count || !same(source->idx, cursor) || !plain(source->idx->exprtype) ||
        !same(remember->rhs, cursor) || !plain(remember->rhs->exprtype) || same(cursor, remember->lval) ||
        same(cursor, increment->lval) || same(remember->lval, increment->lval)) return false;
    int64_t step = 1;
    if (auto update = Is<Assign>(loop->body->stmts[1])) {
        if (update->pointee || !same(update->lval, cursor) || !plain(update->lval->exprtype) || update->op != T_PLUSEQ)
            return false;
        auto literal = Is<IntLit>(update->rhs);
        if (!literal || !plain(literal->exprtype)) return false;
        step = literal->val;
    } else {
        auto advance = Is<IncDec>(loop->body->stmts[1]);
        if (!advance || advance->op != T_INC || !same(advance->lval, cursor) || !plain(advance->lval->exprtype)) return false;
    }
    if (step != 1 && step != 2 && step != 4 && step != 8) return false;
    auto object = Is<Ident>(source->obj);
    if (!object || !object->vdef) return false;
    auto slot = Lookup(object->vdef, object->line); auto type = slot.type;
    if (type != object->exprtype) return false;
    TypeExpr *element = nullptr;
    if (type->kind == TY_SLICE) {
        auto def = Resolve(object->vdef);
        if (slot.kind != Slot::LOCAL || def->captured || def->reusable ||
            addressed.count(def) || addressed.count(object->vdef)) return false;
        element = type->sub;
    } else if (type->kind == TY_ARRAY && type->arr->akind == A_FIXED &&
               (slot.kind == Slot::FRAME || slot.kind == Slot::GLOBAL)) element = type->arr->sub;
    else return false;
    if (!IsIntT(element) || element->ix || (element->intstorage != IS_U8 && element->intstorage != IS_I8) ||
        source->exprtype != element || value->exprtype != element) return false;
    auto bound = condition->right;
    if (!plain(bound->exprtype)) return false;
    for (auto changed : { cursor, Is<Ident>(remember->lval), Is<Ident>(increment->lval) })
        if (same(bound, changed)) return false;
    if (!Is<IntLit>(bound) && !local(bound)) {
        auto length = Is<Dot>(bound);
        if (!length || length->member != B_LEN) return false;
        auto id = Is<Ident>(length->obj);
        if (!id || !id->vdef) return false;
        auto view = Lookup(id->vdef, id->line); auto def = Resolve(id->vdef);
        if (view.type != id->exprtype || view.kind != Slot::LOCAL || view.type->kind != TY_SLICE ||
            def->captured || def->reusable || addressed.count(def) || addressed.count(id->vdef)) return false;
    }
    auto finished = Begin(), scalar = Begin();
    emitting_guarded_loop = true;
    View(object); auto packed = Save(I64);
    Get(packed); code.Op(0xa7); auto pointer = Save(I32);
    Expr(bound); if (condition->op == T_LTEQ) { code.I64Const(1); code.Op(0x7c); }
    auto end = Save(I64);
    // Widened guards prove every byte of each vector readable, including lanes
    // skipped by the scalar stride. Invalid spans retain ordered scalar traps.
    Read(*counter); code.I64Const(0); code.Op(0x59);
    Read(*counter); Get(end); code.Op(0x54); code.Op(0x71);
    Get(end); Get(packed); code.I64Const(32); code.Op(0x88); code.Op(0x58); code.Op(0x71);
    Get(pointer); code.Op(0xad); Get(end); code.Op(0x7c);
    code.OpU(0x3f, 0); code.Op(0xad); code.I64Const(16); code.Op(0x86); code.Op(0x58); code.Op(0x71);
    code.Op(0x45); Br(scalar, true);
    for (int width : {32, 16}) {
        uint32_t lanes = 0;
        for (int lane = 0; lane < width; lane += int(step)) lanes |= uint32_t(1) << lane;
        auto group = [&]() { Read(*counter); code.I64Const(width); code.Op(0x7c); Get(end); code.Op(0x58); };
        group(); Begin(0x04); auto repeat = Begin(0x03);
        Get(pointer); Read(*counter); code.Op(0xa7); code.Op(0x6a); auto address = Save(I32);
        for (int offset = 0; offset < width; offset += 16) {
            Get(address); code.OpU(0xfd, 0x00); code.U(0); code.U(offset); // v128.load
            code.I32Const(int32_t(value->val)); code.OpU(0xfd, 0x0f); // i8x16.splat
            code.OpU(0xfd, 0x23); code.OpU(0xfd, 0x64); // i8x16.eq, i8x16.bitmask
            if (offset) { code.I32Const(16); code.Op(0x74); code.Op(0x72); }
        }
        code.I32Const(int32_t(lanes)); code.Op(0x71); auto mask = Save(I32);
        Read(*count); Get(mask); code.Op(0x69); code.Op(0xad); code.Op(0x7c); Write(*count);
        // The zero-mask candidate is unused; clz and raw arithmetic cannot trap.
        Read(*counter); code.I32Const(31); Get(mask); code.Op(0x67); code.Op(0x6b); code.Op(0xad); code.Op(0x7c);
        Read(*last); Get(mask); code.Op(0x1b); Write(*last);
        Read(*counter); code.I64Const(width); code.Op(0x7c); Write(*counter);
        // After the 32-byte groups, at most one 16-byte vector tail remains.
        if (width == 32) { group(); Br(repeat, true); }
        End(); End();
    }
    End(); Expr(loop); End();
    emitting_guarded_loop = false;
    return true;
}

} // namespace goose::direct_wasm
