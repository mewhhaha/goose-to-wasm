#pragma once
namespace goose::direct_wasm {

inline bool Function::GroupedStores(While *loop) {
    if (c.opts.debug || emitting_guarded_loop || (c.region_cursors && c.may_have_prefix_mappings) ||
        loop->body->tail || loop->body->stmts.size() != 2) return false;
    auto condition = Is<Binary>(loop->cond);
    auto store = Is<Assign>(loop->body->stmts[0]);
    if (!condition || (condition->op != T_LT && condition->op != T_LTEQ) ||
        !store || store->pointee || store->op != T_ASSIGN) return false;
    auto target = Is<Index>(store->lval); auto value = Is<IntLit>(store->rhs);
    if (!target || !value) return false;
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
    auto cursor = Is<Ident>(condition->left); auto counter = local(cursor);
    if (!counter || !same(target->idx, cursor) || !plain(target->idx->exprtype)) return false;
    Node *step = nullptr;
    if (auto update = Is<Assign>(loop->body->stmts[1])) {
        if (update->pointee || !same(update->lval, cursor) || !plain(update->lval->exprtype)) return false;
        if (update->op == T_PLUSEQ) step = update->rhs;
        else if (update->op == T_ASSIGN) {
            auto add = Is<Binary>(update->rhs);
            if (!add || add->op != T_PLUS || !plain(add->exprtype) ||
                !same(add->left, cursor) || !plain(add->left->exprtype)) return false;
            step = add->right;
        } else return false;
    } else {
        auto increment = Is<IncDec>(loop->body->stmts[1]);
        if (!increment || increment->op != T_INC || !same(increment->lval, cursor) ||
            !plain(increment->lval->exprtype)) return false;
    }
    if (step) {
        if (!plain(step->exprtype) || same(step, cursor)) return false;
        if (!Is<IntLit>(step) && !local(step)) return false;
    }
    auto object = Is<Ident>(target->obj);
    if (!object || !object->vdef) return false;
    auto slot = Lookup(object->vdef, object->line); auto type = slot.type;
    if (type != object->exprtype) return false;
    bool owner = false;
    TypeExpr *element = nullptr;
    if (type->kind == TY_SLICE) {
        auto def = Resolve(object->vdef);
        if (slot.kind != Slot::LOCAL || def->captured || def->reusable ||
            addressed.count(def) || addressed.count(object->vdef)) return false;
        element = type->sub;
    } else if (type->kind == TY_ARRAY && (slot.kind == Slot::FRAME || slot.kind == Slot::GLOBAL)) {
        owner = Compiler::RegionArray(type);
        if (owner) { if (!c.raw_array_images) return false; }
        else if (type->arr->akind != A_FIXED) return false;
        element = type->arr->sub;
    } else return false;
    if (!IsIntT(element) || element->ix || Compiler::Varint(element) ||
        target->exprtype != element || value->exprtype != element) return false;
    auto width = IntBits(element->intstorage) / 8;
    if (width != 1 && width != 2 && width != 4 && width != 8) return false;
    auto bound = condition->right;
    if (!plain(bound->exprtype) || same(bound, cursor)) return false;
    if (!Is<IntLit>(bound) && !local(bound)) {
        auto length = Is<Dot>(bound);
        if (!length || length->member != B_LEN) return false;
        auto id = Is<Ident>(length->obj);
        if (!id || !id->vdef) return false;
        auto view = Lookup(id->vdef, id->line);
        if (view.type != id->exprtype || view.kind != Slot::LOCAL || view.type->kind != TY_SLICE ||
            Resolve(id->vdef)->captured || Resolve(id->vdef)->reusable ||
            addressed.count(Resolve(id->vdef)) || addressed.count(id->vdef)) return false;
    }
    auto finished = Begin(), scalar = Begin();
    emitting_guarded_loop = true;
    // A raw owner view reads its header. Do this only when the original loop
    // would execute its first store, preserving zero-iteration trap behavior.
    Truth(loop->cond); code.Op(0x45); Br(finished, true);
    optional<uint32_t> header;
    if (owner) {
        Expr(object); header = Save(I32); Get(*header); PackArrayView(type);
    } else View(object);
    auto packed = Save(I64);
    Get(packed); code.Op(0xa7); auto pointer = Save(I32);
    Get(packed); code.I64Const(32); code.Op(0x88); auto length = Save(I64);
    Expr(bound); if (condition->op == T_LTEQ) { code.I64Const(1); code.Op(0x7c); }
    auto end = Save(I64);
    if (step) Expr(step); else code.I64Const(1);
    auto stride = Save(I64);
    Get(pointer); code.Op(0xad); Get(end); code.I64Const(width); code.Op(0x7e); code.Op(0x7c); auto extent = Save(I64);
    code.I32Const(1);
    Read(*counter); code.I64Const(0); code.Op(0x59); code.Op(0x71);
    Read(*counter); Get(end); code.Op(0x54); code.Op(0x71);
    Get(end); Get(length); code.Op(0x58); code.Op(0x71);
    Get(stride); code.I64Const(0); code.Op(0x55); code.Op(0x71);
    Get(stride); code.I64Const(UINT32_MAX); code.Op(0x58); code.Op(0x71);
    Get(extent); code.OpU(0x3f, 0); code.Op(0xad); code.I64Const(16); code.Op(0x86); code.Op(0x58); code.Op(0x71);
    if (header) {
        // Closed raw images read only this header; the store interval must not
        // mutate any of its control bytes before the original scalar tail.
        Get(extent); Get(*header); code.Op(0xad); code.Op(0x58);
        Get(pointer); code.Op(0xad); Read(*counter); code.I64Const(width); code.Op(0x7e); code.Op(0x7c);
        Get(*header); code.Op(0xad); code.I64Const(c.HeaderLayout(type).size); code.Op(0x7c); code.Op(0x5a);
        code.Op(0x72); code.Op(0x71);
    }
    code.Op(0x45); Br(scalar, true);
    Get(stride); code.I64Const(3); code.Op(0x7e); auto last = Save(I64);
    Get(stride); code.I64Const(4); code.Op(0x7e); auto advance = Save(I64);
    Get(stride); code.I64Const(width); code.Op(0x7e); code.Op(0xa7); auto bytes = Save(I32);
    auto group = [&]() { Read(*counter); Get(last); code.Op(0x7c); Get(end); code.Op(0x54); };
    group(); Begin(0x04); auto repeat = Begin(0x03);
    Get(pointer); Read(*counter); code.Op(0xa7); code.I32Const(width); code.Op(0x6c); code.Op(0x6a); auto address = Save(I32);
    for (int lane = 0; lane < 4; lane++) {
        Get(address);
        if (lane) { Get(bytes); code.I32Const(lane); code.Op(0x6c); code.Op(0x6a); }
        Const(element, value->val); Store(element);
    }
    Read(*counter); Get(advance); code.Op(0x7c); Write(*counter);
    group(); Br(repeat, true); End(); End();
    End(); Expr(loop); End();
    emitting_guarded_loop = false;
    return true;
}

} // namespace goose::direct_wasm
