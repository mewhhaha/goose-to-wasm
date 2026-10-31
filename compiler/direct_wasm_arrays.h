#pragma once
namespace goose::direct_wasm {

// Array addresses always name the owner, not the first element. Keep the
// target's header/padding details here so indexing, slices, casts and loops
// all observe the same current length.
inline void Function::PackArrayView(TypeExpr *t) {
    if (Compiler::RegionArray(t)) {
        c.HeaderLayout(t);
        auto header = Save(I32);
        Get(header); code.Mem(0x28, 2); code.Op(0xad);
        Get(header); code.Mem(0x28, 2, 4); code.Op(0xad); code.I64Const(32); code.Op(0x86); code.Op(0x84);
        return;
    }
    auto layout = c.Size(t);
    if (t->arr->akind == A_FIXED) {
        code.Op(0xad); code.I64Const(int64_t(uint64_t(t->arr->size) << 32)); code.Op(0x84);
    } else {
        auto base = Save(I32);
        Get(base); code.I32Const(int32_t(layout.payload)); code.Op(0x6a); code.Op(0xad);
        Get(base); code.Mem(0x28, 2); code.Op(0xad); code.I64Const(32); code.Op(0x86); code.Op(0x84);
    }
}

// A for loop walks a location, reloading reference/slice links and the current
// length. Calls and index expressions on that path run once at loop entry.
// Keep this recipe separate from Expr: replaying arbitrary source expressions
// would repeat their effects, while caching a view would miss slot replacement.
inline function<void()> Function::SequenceValue(Node *n, bool address) {
    if (auto id = Is<Ident>(n); id && id->vdef) {
        auto slot = Lookup(id->vdef, n->line);
        return [this, n, slot, address]() {
            if (address) {
                if (slot.type->kind == TY_REF && n->exprtype->kind != TY_REF) Read(slot);
                else SlotAddress(slot);
            } else if (n->exprtype->kind == TY_REF && slot.type->kind != TY_REF) SlotAddress(slot);
            else { Read(slot); Convert(slot.type, n->exprtype, n->line); }
        };
    }
    if (auto dot = Is<Dot>(n); dot && dot->IsField()) {
        auto parent = SequenceValue(dot->obj);
        auto t = dot->obj->exprtype; if (t->kind == TY_REF) t = t->ref->sub;
        auto field = c.FieldType(t, dot->fieldidx);
        auto off = c.Size(t).fields.at(size_t(dot->fieldidx));
        return [this, n, dot, parent, field, off, address]() {
            parent();
            if (dot->obj->exprtype->kind == TY_REF) Load(dot->obj->exprtype->ref->sub);
            if (off) { code.I32Const(int32_t(off)); code.Op(0x6a); }
            if (!address && (n->exprtype->kind != TY_REF || field->kind == TY_REF)) {
                Load(field); Convert(field, n->exprtype, n->line);
            }
        };
    }
    if (auto idx = Is<Index>(n)) {
        auto parent = SequenceValue(idx->obj);
        auto t = idx->obj->exprtype; if (t->kind == TY_REF) t = t->ref->sub;
        auto elem = t->kind == TY_ARRAY ? t->arr->sub : t->sub;
        auto view = [this, idx, parent, t]() {
            parent();
            if (idx->obj->exprtype->kind == TY_REF) Load(t);
            if (t->kind == TY_ARRAY) PackArrayView(t);
        };
        // Match the pinned emitter's IndexLoc: side-effecting index
        // expressions pin the containing view before evaluating the index.
        function<bool(Node *)> statements = [&](Node *x) {
            if (!x) return false;
            if (Is<Call>(x) || CodeGen::IsCtl(x) || Is<StrLit>(x)) return true;
            bool found = false; x->Children([&](Node *ch) { found |= statements(ch); }); return found;
        };
        function<void()> source = view;
        auto pinned = statements(idx->idx);
        if (pinned) {
            view(); auto captured = Save(I64);
            source = [this, captured]() { Get(captured); };
        }
        To(idx->idx, c.ast.inttypes[IS_U64]); auto pos = Save(I64);
        if (t->kind == TY_SLICE && !pinned) {
            // IndexLoc pins a slice's element pointer even for a pure
            // index. Its bounds still read the current slice length.
            view(); code.Op(0xa7); auto pointer = Save(I32);
            source = [this, view, pointer]() {
                Get(pointer); code.Op(0xad);
                view(); code.I64Const(32); code.Op(0x88); code.I64Const(32); code.Op(0x86); code.Op(0x84);
            };
        }
        return [this, n, idx, source, pos, elem, address]() {
            source(); auto current = Save(I64);
            if (!idx->nobc) {
                Get(pos); Get(current); code.I64Const(32); code.Op(0x88); code.Op(0x5a);
                TrapIf(n->line, "array index out of bounds");
            }
            Get(current); code.Op(0xa7); Get(pos); code.Op(0xa7);
            code.I32Const(int32_t(c.Size(elem).size)); code.Op(0x6c); code.Op(0x6a);
            if (!address && (n->exprtype->kind != TY_REF || elem->kind == TY_REF)) {
                Load(elem); Convert(elem, n->exprtype, n->line);
            }
        };
    }
    if (auto u = Is<Unary>(n); u && u->op == T_BITAND && n->exprtype->kind == TY_REF &&
        u->child->exprtype && u->child->exprtype->kind != TY_REF &&
        (Is<Ident>(u->child) || Is<Dot>(u->child) || Is<Index>(u->child)))
        return SequenceValue(u->child, true);
    if (address) { Address(n); auto saved = Save(I32); return [this, saved]() { Get(saved); }; }
    Expr(n); auto saved = Save(n->exprtype); return [this, saved]() { Get(saved); };
}

inline void Function::ArrayBuiltin(Call *n) {
    auto args = n->ArgNodes();
    auto t = Object(args[0]);
    auto kind = BuiltinKind(n->builtin);
    if (kind == B_INDEX_OF) {
        if (Compiler::RegionArray(t)) code.Mem(0x28, 2);
        else {
            auto layout = c.Size(t);
            if (layout.payload) { code.I32Const(int32_t(layout.payload)); code.Op(0x6a); }
        }
        auto start = Save(I32);
        Expr(args[1]); Get(start); code.Op(0x6b); code.Op(0xad);
        code.I64Const(c.Size(t->arr->sub).size); code.Op(0x80);
        Convert(c.ast.inttypes[IS_I64], n->exprtype, n->line); return;
    }
    auto region = Compiler::RegionArray(t);
    if (t->kind != TY_ARRAY || (t->arr->akind != A_LIMITED && !Compiler::GrowableArray(t)))
        Fail(n->line, "this array mutation is not supported without dynamic storage");
    auto layout = region ? c.HeaderLayout(t) : c.Size(t);
    auto base = Save(I32);
    auto elem = t->arr->sub;
    auto stride = c.Size(elem).size;
    auto length = [&]() { Get(base); code.Mem(0x28, 2, region ? 4 : 0); };
    auto write_length = [&](uint32_t len) { Get(base); Get(len); code.Mem(0x36, 2, region ? 4 : 0); };
    auto address = [&](uint32_t i) {
        Get(base);
        if (region) code.Mem(0x28, 2);
        else { code.I32Const(int32_t(layout.payload)); code.Op(0x6a); }
        Get(i); code.I32Const(int32_t(stride)); code.Op(0x6c); code.Op(0x6a);
    };
    if (kind == B_CLEAR) {
        Get(base); code.I32Const(0); code.Mem(0x36, 2, region ? 4 : 0); return;
    }
    if (kind == B_PUSH) {
        To(args[1], elem); auto value = Save(elem);
        // The value expression may have mutated the receiver. Load len only
        // after it finishes, retaining the receiver address evaluated first.
        length(); auto len = Save(I32);
        if (region) {
            Get(len); code.Op(0xad); code.I64Const(1); code.Op(0x7c);
            auto next = Save(I64); ReserveArray(base, next, t, n->line);
        } else {
            Get(len); code.I32Const(int32_t(t->arr->size)); code.Op(0x4f); TrapIf(n->line, "array capacity exceeded");
        }
        address(len); auto dest = Save(I32);
        Get(dest); Get(value); Store(elem);
        Get(len); code.I32Const(1); code.Op(0x6a); auto next = Save(I32); write_length(next);
        Get(dest);
        if (elem->kind == TY_REF) Load(elem); // Goose has no references to references.
        Convert(n->rettypes[0], n->exprtype, n->line); return;
    }
    if (kind == B_POP) {
        length(); auto len = Save(I32);
        Get(len); code.Op(0x45); TrapIf(n->line, "pop from empty array");
        Get(len); code.I32Const(1); code.Op(0x6b); auto next = Save(I32); write_length(next);
        address(next); Load(elem); Convert(elem, n->exprtype, n->line);
        // Pop produces an owned fixed value, even when consumed as an
        // iteration temporary before another expression refills this slot.
        if (c.Aggregate(n->exprtype)) {
            auto captured = CopyCaptured(CaptureStack(n->exprtype)); Get(captured.value_local);
        }
        return;
    }
    if (kind == B_APPEND) {
        ConstructionView(args[1], Compiler::GrowableArray(t)); auto view = Save(I64);
        Get(view); code.I64Const(32); code.Op(0x88); code.Op(0xa7); auto count = Save(I32);
        length(); auto len = Save(I32);
        // count <= cap-len avoids wrapping the sum. The source view is
        // captured before reloading len; memory.copy also handles overlap.
        if (region) {
            Get(count); code.Op(0xad); Get(len); code.Op(0xad); code.Op(0x7c);
            auto next = Save(I64); ReserveArray(base, next, t, n->line);
        } else {
            Get(count); code.I32Const(int32_t(t->arr->size)); Get(len); code.Op(0x6b); code.Op(0x4b);
            TrapIf(n->line, "array capacity exceeded");
        }
        address(len); Get(view); code.Op(0xa7); Get(count); code.I32Const(int32_t(stride)); code.Op(0x6c); code.Copy();
        Get(len); Get(count); code.Op(0x6a); auto next = Save(I32); write_length(next); return;
    }
    To(args[1], c.ast.inttypes[IS_U64]); auto count = Save(I64);
    optional<uint32_t> fill;
    if (args.size() > 2) { To(args[2], elem); fill = Save(elem); }
    length(); auto old = Save(I32);
    if (kind == B_POP_N) {
        Get(count); Get(old); code.Op(0xad); code.Op(0x56);
        TrapIf(n->line, "pop count out of bounds");
        Get(old); Get(count); code.Op(0xa7); code.Op(0x6b); auto next = Save(I32); write_length(next); return;
    }
    Get(count); code.I64Const(0); code.Op(0x53); TrapIf(n->line, "negative array resize");
    Get(count); Get(old); code.Op(0xad); code.Op(0x56); Begin(0x04);
    if (!fill) Abort(n->line, "array resize growth requires a fill value");
    else {
        if (region) ReserveArray(base, count, t, n->line);
        else { Get(count); code.I64Const(t->arr->size); code.Op(0x56); TrapIf(n->line, "array capacity exceeded"); }
        auto i = Local(I32); Get(old); Set(i);
        auto done = Begin(), loop = Begin(0x03);
        Get(i); Get(count); code.Op(0xa7); code.Op(0x4f); Br(done, true);
        address(i); Get(*fill); Store(elem);
        Get(i); code.I32Const(1); code.Op(0x6a); Set(i); Br(loop); End(); End();
    }
    End();
    Get(count); code.Op(0xa7); auto next = Save(I32); write_length(next);
}

} // namespace goose::direct_wasm
