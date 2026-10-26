#pragma once
namespace goose::direct_wasm {

// Small AST-local optimizations. These do not depend on engine tiering or
// pattern-match a particular benchmark. Keep speculative expressions strictly
// narrower than the full language: no calls, memory loads, casts, division,
// allocation, or checked signed arithmetic may execute on an unchosen path.
inline bool PureIntegerOp(TType op, TypeExpr *type, bool debug) {
    if (!type || (!IsIntT(type) && type->kind != TY_BOOL)) return false;
    switch (op) {
        case T_BITAND: case T_BITOR: case T_XOR: case T_SHL: case T_SHR:
        case T_ANDEQ: case T_OREQ: case T_XOREQ: case T_SHLEQ: case T_SHREQ:
        case T_EQ: case T_NEQ: case T_LT: case T_GT: case T_LTEQ: case T_GTEQ:
            return true;
        case T_PLUS: case T_MINUS: case T_MUL:
        case T_PLUSEQ: case T_MINUSEQ: case T_MULEQ:
            return !debug || (IsIntT(type) && IsUnsigned(type->intstorage));
        default: return false;
    }
}

inline bool IntegerLocal(Function &fn, VarDef *var, VarDef *binder = nullptr, VarDef *index = nullptr) {
    var = fn.Resolve(var);
    if (!var || (!IsIntT(var->type) && var->type->kind != TY_BOOL)) return false;
    if (fn.addressed.count(var)) return false;
    if (var == binder || var == index) return true;
    auto slot = fn.vars.find(var);
    return slot != fn.vars.end() && slot->second.kind == Slot::LOCAL;
}

inline bool PureInteger(Function &fn, Node *node, int &budget,
                        VarDef *binder = nullptr, VarDef *index = nullptr) {
    if (!node || --budget < 0 || !node->exprtype ||
        (!IsIntT(node->exprtype) && node->exprtype->kind != TY_BOOL)) return false;
    if (Is<IntLit>(node) || Is<BoolLit>(node)) return true;
    if (auto id = Is<Ident>(node)) return IntegerLocal(fn, id->vdef, binder, index);
    if (auto un = Is<Unary>(node)) {
        if (un->op != T_NOT && un->op != T_BITNOT &&
            !(un->op == T_MINUS && PureIntegerOp(T_MINUS, un->exprtype, fn.c.opts.debug))) return false;
        return PureInteger(fn, un->child, budget, binder, index);
    }
    if (auto bin = Is<Binary>(node)) {
        if (!PureIntegerOp(bin->op, bin->left->exprtype, fn.c.opts.debug)) return false;
        return PureInteger(fn, bin->left, budget, binder, index) &&
               PureInteger(fn, bin->right, budget, binder, index);
    }
    return false;
}

inline Assign *SingleAssignment(Node *node) {
    if (auto block = Is<Block>(node)) {
        if (block->stmts.empty()) node = block->tail;
        else if (block->stmts.size() == 1 && !block->tail) node = block->stmts[0];
        else return nullptr;
    }
    return node ? Is<Assign>(node) : nullptr;
}

inline bool Function::TryConstantBinary(Binary *node) {
    auto rhs = Is<IntLit>(node->right);
    auto type = node->left->exprtype;
    if (type->kind == TY_REF) type = type->ref->sub;
    if (!rhs || !IsIntT(type)) return false;
    if (node->op == T_SHL || node->op == T_SHR) {
        // Emitting a literal in its operand width avoids an i64->i32 cast
        // that turns an immediate shift into a variable-count machine
        // instruction in a single-pass baseline compiler.
        auto wide = W(type) == I64;
        auto uns = IsUnsigned(type->intstorage);
        auto count = uint64_t(rhs->val) & uint64_t(IntBits(type->intstorage) - 1);
        To(node->left, type); Const(type, int64_t(count));
        code.Op(node->op == T_SHL ? (wide ? 0x86 : 0x74)
                                : wide ? (uns ? 0x88 : 0x87) : (uns ? 0x76 : 0x75));
        Normalize(type); Convert(type, node->exprtype, node->line); return true;
    }
    if (node->op != T_MOD && node->op != T_DIV) return false;
    auto uns = IsUnsigned(type->intstorage);
    // Only positive signed divisors; unsigned literals may use bit 63.
    if (!uns && (rhs->uns || rhs->val <= 0)) return false;
    auto divisor = uint64_t(rhs->val);
    if (!divisor || (divisor & (divisor - 1))) return false;
    auto bits = IntBits(type->intstorage);
    if (bits < 64 && divisor >= (UINT64_C(1) << bits)) return false;
    if (node->op == T_DIV && !uns && !node->nonneg) return false;
    To(node->left, type); // Preserve the only nonconstant operand's effects.
    if (node->op == T_MOD) {
        // Goose uses Euclidean modulo. For a positive power of two this is
        // the low-bit mask even when the signed dividend is negative/min.
        Const(type, int64_t(divisor - 1)); code.Op(W(type) == I64 ? 0x83 : 0x71);
    } else {
        unsigned shift = 0;
        for (auto n = divisor; n > 1; n >>= 1) ++shift;
        Const(type, shift); code.Op(W(type) == I64 ? 0x88 : 0x76);
    }
    Normalize(type); Convert(type, node->exprtype, node->line); return true;
}

inline bool Function::TrySelect(IfExpr *node) {
    if (c.opts.optimize_level < 2 || !Values(node).empty() || !node->elseb) return false;
    auto yes = SingleAssignment(node->thenb), no = SingleAssignment(node->elseb);
    if (!yes || !no || yes->pointee || no->pointee) return false;
    auto yi = Is<Ident>(yes->lval), ni = Is<Ident>(no->lval);
    if (!yi || !ni || Resolve(yi->vdef) != Resolve(ni->vdef) || !IntegerLocal(*this, yi->vdef)) return false;
    auto slot = Lookup(yi->vdef, node->line);
    auto valid = [&](Assign *assignment, int &budget) {
        if (assignment->op != T_ASSIGN && !PureIntegerOp(assignment->op, slot.type, c.opts.debug)) return false;
        return PureInteger(*this, assignment->rhs, budget);
    };
    int budget = 24;
    if (!valid(yes, budget) || !valid(no, budget)) return false;
    // Conditions may themselves have effects. Evaluate once before any
    // speculative read, so both candidates see the resulting local values.
    Truth(node->cond); auto condition = Save(I32);
    auto candidate = [&](Assign *assignment) {
        if (assignment->op != T_ASSIGN) Read(slot);
        To(assignment->rhs, slot.type);
        if (assignment->op != T_ASSIGN) BinaryOp(assignment->op, slot.type, assignment->line);
    };
    candidate(yes); candidate(no); Get(condition); code.Op(0x1b); Write(slot); return true;
}

inline bool SmallIntegerBody(Function &fn, Node *node, int &budget, VarDef *binder, VarDef *index) {
    if (!node || --budget < 0) return false;
    if (auto block = Is<Block>(node)) {
        for (auto stmt : block->stmts) if (!SmallIntegerBody(fn, stmt, budget, binder, index)) return false;
        return !block->tail || SmallIntegerBody(fn, block->tail, budget, binder, index);
    }
    if (auto assignment = Is<Assign>(node)) {
        auto id = Is<Ident>(assignment->lval);
        if (!id || assignment->pointee || !IntegerLocal(fn, id->vdef, binder, index)) return false;
        if (assignment->op != T_ASSIGN && !PureIntegerOp(assignment->op, id->vdef->type, fn.c.opts.debug)) return false;
        return PureInteger(fn, assignment->rhs, budget, binder, index);
    }
    if (auto inc = Is<IncDec>(node)) {
        auto id = Is<Ident>(inc->lval);
        return id && IntegerLocal(fn, id->vdef, binder, index) &&
               PureIntegerOp(T_PLUS, id->vdef->type, fn.c.opts.debug);
    }
    if (auto cond = Is<IfExpr>(node)) {
        return fn.Values(node).empty() && PureInteger(fn, cond->cond, budget, binder, index) &&
               SmallIntegerBody(fn, cond->thenb, budget, binder, index) &&
               (!cond->elseb || SmallIntegerBody(fn, cond->elseb, budget, binder, index));
    }
    if (auto stop = Is<Break>(node)) return stop->val == nullptr;
    if (Is<Continue>(node)) return true;
    // In particular: no declarations, address-taking, captures, calls, or
    // nested loops. Repeating a body cannot extend a temporary's lifetime
    // or multiply another loop's expansion.
    return false;
}

inline bool Function::TryUnroll(ForLoop *node) {
    if (c.opts.optimize_level < 2 || node->byref ||
        (node->iterkind != IK_COUNT && node->iterkind != IK_RANGE)) return false;
    auto range = Is<RangeExpr>(node->iter);
    auto lower = range ? Is<IntLit>(range->lo) : nullptr;
    auto upper = Is<IntLit>(range ? range->hi : node->iter);
    if (!upper || (range && !lower) || (lower && (lower->uns || lower->val < 0)) ||
        upper->uns || upper->val < 0) return false;
    auto lo = lower ? lower->val : 0, hi = upper->val;
    if (hi < lo || hi - lo > 8) return false;
    auto count = hi - lo;
    int budget = 40;
    if (!IntegerLocal(*this, node->vdef, node->vdef, node->idxdef) ||
        (node->idxdef && !IntegerLocal(*this, node->idxdef, node->vdef, node->idxdef)) ||
        !SmallIntegerBody(*this, node->body, budget, node->vdef, node->idxdef) ||
        (40 - budget) * count > 192) return false;
    auto binding = Bind(node->vdef);
    optional<Slot> ordinal;
    if (node->idxdef) ordinal = Bind(node->idxdef);
    auto countertype = range ? range->exprtype : node->iter->exprtype;
    auto done = Begin();
    for (int64_t i = 0; i < count; ++i) {
        Const(countertype, lo + i); Convert(countertype, binding.type, node->line); Write(binding);
        if (ordinal) { code.I64Const(i); Convert(c.ast.inttypes[IS_I64], ordinal->type, node->line); Write(*ordinal); }
        auto step = Begin(); exits.push_back({ done, nullptr, {}, {}, true, step });
        BlockInto(node->body, {}, {}); exits.pop_back(); End();
    }
    End(); return true;
}

inline bool Function::TryBulkFill(ForLoop *node) {
    if (c.opts.optimize_level < 2 || bulk_fill_disabled || node->byref || node->idxdef ||
        node->iterkind != IK_COUNT || !IsIntT(node->vdef->type) ||
        node->vdef->type->intstorage != IS_I64) return false;
    auto length = Is<Dot>(node->iter);
    if (!length || length->member != B_LEN) return false;
    auto source = Is<Ident>(length->obj);
    auto assignment = SingleAssignment(node->body);
    if (!source || !assignment ||
        (assignment->op != T_ASSIGN && assignment->op != T_DOTASSIGN)) return false;
    auto element = Is<Index>(assignment->lval);
    auto target = element ? Is<Ident>(element->obj) : nullptr;
    auto position = element ? Is<Ident>(element->idx) : nullptr;
    if (!target || !position || Resolve(source->vdef) != Resolve(target->vdef) ||
        Resolve(position->vdef) != Resolve(node->vdef)) return false;
    auto slice = Lookup(source->vdef, node->line);
    if (slice.kind != Slot::LOCAL || slice.type->kind != TY_SLICE) return false;
    auto byte = slice.type->sub;
    if (!IsIntT(byte) || IntBits(byte->intstorage) != 8) return false;
    auto literal = Is<IntLit>(assignment->rhs);
    auto scalar = Is<Ident>(assignment->rhs);
    if (!literal && (!scalar || Resolve(scalar->vdef) == Resolve(node->vdef) ||
                     !IntegerLocal(*this, scalar->vdef))) return false;
    if (!IsIntT(assignment->rhs->exprtype)) return false;
    // A packed slice can be a raw contiguous pointer or a tagged view over
    // stable chunks. Only the former admits Wasm's contiguous bulk operation.
    // The fallback reuses normal indexing, including its chunk translation.
    View(length->obj); auto view = Save(I64);
    Get(view); code.Op(0xa7); code.I32Const(INT32_MIN); code.Op(0x71); code.Op(0x45);
    Begin(0x04);
    Get(view); code.I64Const(32); code.Op(0x88); code.Op(0xa7); auto count = Save(I32);
    Get(count); Begin(0x04);
    Get(view); code.Op(0xa7); To(assignment->rhs, byte); Get(count); code.Fill();
    End();
    Else();
    bulk_fill_disabled = true;
    For(node);
    bulk_fill_disabled = false;
    End(); return true;
}

} // namespace goose::direct_wasm
