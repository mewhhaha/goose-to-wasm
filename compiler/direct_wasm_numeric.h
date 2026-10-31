#pragma once
namespace goose::direct_wasm {

inline void Function::Normalize(TypeExpr *t) {
    if (!IsIntT(t)) return;
    switch (t->intstorage) {
        case IS_I8: code.Op(0xc0); break;
        case IS_I16: code.Op(0xc1); break;
        case IS_U8: code.I32Const(255); code.Op(0x71); break;
        case IS_U16: code.I32Const(65535); code.Op(0x71); break;
        default: break;
    }
}

inline void Function::Convert(TypeExpr *from, TypeExpr *to, Line l) {
    if (!from || !to || to->kind == TY_VOID) Fail(l, "internal conversion without a value type");
    if (from->kind == TY_REF && to->kind != TY_REF) {
        Load(from->ref->sub); Convert(from->ref->sub, to, l); return;
    }
    if (from->kind == TY_ARRAY && to->kind == TY_SLICE) {
        PackArrayView(from); return;
    }
    if (Compiler::RegionEnum(from) || Compiler::RegionEnum(to)) {
        if (c.Aggregate(from) && to->kind == TY_REF) { W(to); return; }
        auto ei = from->kind == TY_ENUM ? from->enu->inst :
                  from->kind == TY_VARIANT ? from->var->adt->enu->inst : nullptr;
        if (!ei || to->kind != TY_ENUM || ei != to->enu->inst)
            Fail(l, "variable-mode enum adaptation requires the same enum instantiation");
        c.EnumImageLayout(ei, l);
        if (Compiler::RegionEnum(from) && Compiler::RegionEnum(to)) return;
        if (Compiler::RegionEnum(from)) {
            c.FixedLayout(to); code.Mem(0x28, 2); return; // borrowed fixed image, not its control descriptor
        }
        auto source = Save(from);
        auto destination = TemporaryDestination(to, l);
        ConstructEnumFromCaptured(from, source, destination, l);
        LocationAddress(destination.location); return;
    }
    if (Compiler::RegionRecord(from) || Compiler::RegionRecord(to)) {
        if (Compiler::RegionRecord(from) && Compiler::RegionRecord(to) && Compiler::SameRecord(from, to)) {
            W(from); W(to); return; // borrowed object address; fixed-copy gates still reject it
        }
        if (c.Aggregate(from) && to->kind == TY_REF) { W(to); return; }
        Fail(l, "owned variable-record adaptation is not supported outside construction");
    }
    if (Compiler::RegionArray(from) && Compiler::RegionArray(to)) {
        if (from->arr->akind != to->arr->akind)
            Fail(l, "dynamic owner type adaptation is not supported outside construction");
        if (from->arr->akind == A_VAR && Compiler::LengthStorage(from) != Compiler::LengthStorage(to))
            Fail(l, "variable-array length adaptation is not supported outside owned construction");
        return; // borrowed header address; fixed-copy gates never accept it
    }
    if (to->kind == TY_ARRAY && to->arr->akind == A_LIMITED &&
        (from->kind == TY_SLICE || (from->kind == TY_ARRAY &&
         (from->arr->akind != A_LIMITED || from->arr->size != to->arr->size)))) {
        if (from->kind == TY_ARRAY) PackArrayView(from);
        auto view = Save(I64);
        auto dest = FreshDestination(to, ConstructionDestination::Statement).location;
        Get(view); code.I64Const(32); code.Op(0x88); auto count = Save(I64);
        Get(count); code.I64Const(to->arr->size); code.Op(0x56); TrapIf(l, "array capacity exceeded");
        LocationAddress(dest); code.I32Const(0); code.I32Const(int32_t(c.Size(to).size)); code.Fill();
        LocationAddress(dest); Get(count); code.Op(0xa7); code.Mem(0x36, 2);
        LocationAddress(OffsetLocation(dest, c.Size(to).payload, to->arr->sub)); Get(view); code.Op(0xa7);
        Get(count); code.Op(0xa7); code.I32Const(int32_t(c.Size(to->arr->sub).size)); code.Op(0x6c); code.Copy();
        LocationAddress(dest); return;
    }
    if (c.Aggregate(from) && to->kind == TY_REF) { W(to); return; }
    if (from->kind == TY_VARIANT && to->kind == TY_ENUM) {
        if (from->var->adt->enu->inst != to->enu->inst)
            Fail(l, "variant belongs to a different enum");
        auto source = CaptureStack(from);
        auto destination = FreshDestination(to, ConstructionDestination::Statement).location;
        auto layout = c.Size(to);
        LocationAddress(destination); code.I32Const(0); code.I32Const(int32_t(layout.size)); code.Fill();
        LocationAddress(destination);
        code.I32Const(to->enu->inst->en->VariantIndex(from->var->variant)); code.Mem(0x36, 2);
        StoreCopy(OffsetLocation(destination, layout.payload, from), source);
        LocationAddress(destination); return;
    }
    if (c.Aggregate(from) || c.Aggregate(to)) {
        if (from->kind != to->kind || c.Size(from).size != c.Size(to).size)
            Fail(l, "aggregate conversion is not supported");
        return;
    }
    if (from->kind == TY_SLICE || to->kind == TY_SLICE || from->kind == TY_REF || to->kind == TY_REF) {
        if (from->kind != to->kind) Fail(l, "reference/slice conversion is not supported");
        W(from); W(to); return;
    }
    auto f = W(from), t = W(to);
    auto u = IsIntT(from) && IsUnsigned(from->intstorage);
    if (f == I32 && t == I64) code.Op(u || from->kind == TY_BOOL ? 0xad : 0xac);
    else if (f == I64 && t == I32) code.Op(0xa7);
    else if (f == I32 && t == F32) code.Op(u ? 0xb3 : 0xb2);
    else if (f == I64 && t == F32) code.Op(u ? 0xb5 : 0xb4);
    else if (f == I32 && t == F64) code.Op(u ? 0xb8 : 0xb7);
    else if (f == I64 && t == F64) code.Op(u ? 0xba : 0xb9);
    else if (f == F32 && t == F64) code.Op(0xbb);
    else if (f == F64 && t == F32) code.Op(0xb6);
    else if ((f == F32 || f == F64) && (t == I32 || t == I64)) {
        FloatWrap(from); if (t == I32) code.Op(0xa7);
    } else if (f != t) Fail(l, "unsupported scalar conversion");
    Normalize(to);
}

// Float -> integer wraps modulo 2^64, including values beyond the range of
// Wasm's trapping conversions. Decode IEEE-754 directly: this has no libc or
// host dependency, and truncates before applying the modular shift.
inline void Function::FloatWrap(TypeExpr *from) {
    if (IsF32(from)) code.Op(0xbb);
    code.Op(0xbd); auto bits = Save(I64);
    Get(bits); code.I64Const(52); code.Op(0x88); code.I64Const(2047); code.Op(0x83);
    code.Op(0xa7); code.I32Const(1023); code.Op(0x6b); auto exp = Save(I32);
    Get(exp); code.I32Const(0); code.Op(0x48);
    Get(exp); code.I32Const(116); code.Op(0x4e); code.Op(0x72);
    Begin(0x04, I64); code.I64Const(0); Else();
    Get(bits); code.I64Const((INT64_C(1) << 52) - 1); code.Op(0x83);
    code.I64Const(INT64_C(1) << 52); code.Op(0x84); auto mantissa = Save(I64);
    Get(exp); code.I32Const(52); code.Op(0x48);
    Begin(0x04, I64);
    Get(mantissa); code.I32Const(52); Get(exp); code.Op(0x6b); code.Op(0xad); code.Op(0x88);
    Else(); Get(mantissa); Get(exp); code.I32Const(52); code.Op(0x6b); code.Op(0xad); code.Op(0x86);
    End(); auto value = Save(I64);
    Get(bits); code.I64Const(0); code.Op(0x53);
    Begin(0x04, I64); code.I64Const(0); Get(value); code.Op(0x7d); Else(); Get(value); End();
    End();
}

inline void Function::Cast(AsCast *n) {
    auto from = n->child->exprtype, to = n->totype;
    Expr(n->child);
    if (from->kind == TY_REF) { Load(from->ref->sub); from = from->ref->sub; }
    auto value = Save(from);
    if (to->kind == TY_INT && to->ix && !n->nobc) {
        // Index types check the source before narrowing, in release as well.
        if (!IsIntT(from)) Fail(n->line, "floating-point casts to index types are not supported");
        auto arr = Lookup(to->ix->arr, n->line);
        Read(arr); auto at = arr.type;
        if (at->kind == TY_REF) { Load(at->ref->sub); at = at->ref->sub; }
        if (at->kind == TY_ARRAY) { PackArrayView(at); code.I64Const(32); code.Op(0x88); }
        else if (at->kind == TY_SLICE) { code.I64Const(32); code.Op(0x88); }
        else Fail(n->line, "index type requires a fixed array or slice");
        auto len = Save(I64);
        Get(value); Convert(from, c.ast.inttypes[IS_U64], n->line); Get(len);
        code.Op(to->ix->upto ? 0x56 : 0x5a); TrapIf(n->line, "index type cast out of bounds");
    }
    if (to->kind == TY_INT && c.opts.debug && !n->unchecked) {
        auto target_unsigned = IsUnsigned(to->intstorage);
        auto bits = IntBits(to->intstorage);
        if (from->kind == TY_FLT) {
            Get(value); if (IsF32(from)) code.Op(0xbb); auto d = Save(F64);
            auto low = target_unsigned ? 0.0 : -ldexp(1.0, bits - 1);
            auto high = ldexp(1.0, target_unsigned ? bits : bits - 1);
            Get(d); code.F64Const(low); code.Op(0x66);
            Get(d); code.F64Const(high); code.Op(0x63); code.Op(0x71); code.Op(0x45);
            TrapIf(n->line, "float-to-integer conversion out of range");
            Get(d); code.Op(0x9d); Get(d); code.Op(0x62);
            TrapIf(n->line, "float-to-integer conversion changes the value");
        } else if (IsIntT(from)) {
            auto source_unsigned = IsUnsigned(from->intstorage);
            Get(value); Convert(from, c.ast.inttypes[source_unsigned ? IS_U64 : IS_I64], n->line);
            auto wide = Save(I64);
            if (!source_unsigned && target_unsigned) {
                Get(wide); code.I64Const(0); code.Op(0x53); TrapIf(n->line, "integer cast out of range");
            }
            if (!target_unsigned) {
                auto lo = IntRange(to->intstorage).first, hi = IntRange(to->intstorage).second;
                if (!source_unsigned) {
                    Get(wide); code.I64Const(lo); code.Op(0x53); TrapIf(n->line, "integer cast out of range");
                }
                Get(wide); code.I64Const(hi); code.Op(source_unsigned ? 0x56 : 0x55);
                TrapIf(n->line, "integer cast out of range");
            } else if (bits < 64) {
                Get(wide); code.I64Const(IntRange(to->intstorage).second); code.Op(0x56);
                TrapIf(n->line, "integer cast out of range");
            }
        }
    }
    Get(value); Convert(from, to, n->line); Convert(to, n->exprtype, n->line);
}

inline void Function::Truth(Node *n) {
    Expr(n); auto t = n->exprtype;
    if (t->kind == TY_REF && !t->ref->optional) { Load(t->ref->sub); t = t->ref->sub; }
    auto w = W(t);
    if (w == I32) { code.Op(0x45); code.Op(0x45); }
    else if (w == I64) { code.Op(0x50); code.Op(0x45); }
    else { Zero(w); code.Op(w == F32 ? 0x5c : 0x62); }
}

// C fmod/fmodf semantics, including the dividend's signed zero. Binary long
// division avoids an overflowing/rounded quotient. Accepted powers-of-two
// scalings are exact; each subtraction has scale <= remainder < 2*scale and
// is exact by Sterbenz's lemma, including gradual underflow. Both loops are
// bounded by the IEEE exponent range.
inline void Function::FloatRemainder(TypeExpr *t) {
    auto w = W(t);
    auto op = [&](uint8_t f32, uint8_t f64) { code.Op(w == F32 ? f32 : f64); };
    auto divisor = Save(w), dividend = Save(w);
    Get(dividend); op(0x8b, 0x99); auto remainder = Save(w);
    Get(divisor); op(0x8b, 0x99); auto bound = Save(w);
    Get(bound); Zero(w); op(0x5b, 0x61);
    Get(remainder);
    if (w == F32) code.F32Const(bit_cast<float>(UINT32_C(0x7f800000)));
    else code.F64Const(bit_cast<double>(UINT64_C(0x7ff0000000000000)));
    op(0x5b, 0x61); code.Op(0x72);
    Get(dividend); Get(dividend); op(0x5c, 0x62); code.Op(0x72);
    Get(divisor); Get(divisor); op(0x5c, 0x62); code.Op(0x72);
    Begin(0x04, w);
    Zero(w); Zero(w); op(0x95, 0xa3); // Invalid operands yield NaN, never a trap.
    Else();
    Get(remainder); Get(bound); op(0x5d, 0x63);
    Begin(0x04, w); Get(dividend); Else(); // Also handles finite % infinity.
    Get(bound); auto scale = Save(w);
    auto done = Begin(), up = Begin(0x03);
    Get(scale); Get(scale); op(0x92, 0xa0); auto twice = Save(w);
    Get(twice); Get(remainder); op(0x5e, 0x64); Br(done, true);
    // Test before assigning: an overflowing double must not enter scale.
    Get(twice); Set(scale); Br(up); End(); End();
    auto down = Begin(0x03);
    Get(remainder); Get(scale); op(0x60, 0x66); Begin(0x04);
    Get(remainder); Get(scale); op(0x93, 0xa1); Set(remainder); End();
    Get(scale);
    if (w == F32) code.F32Const(2); else code.F64Const(2);
    op(0x95, 0xa3); Set(scale);
    Get(scale); Get(bound); op(0x60, 0x66); Br(down, true); End();
    Get(remainder); Get(dividend); op(0x98, 0xa6);
    End(); End();
}

inline void Function::BinaryOp(TType op, TypeExpr *t, Line line) {
    switch (op) {
        case T_PLUSEQ: op = T_PLUS; break; case T_MINUSEQ: op = T_MINUS; break;
        case T_MULEQ: op = T_MUL; break; case T_DIVEQ: op = T_DIV; break;
        case T_MODEQ: op = T_MOD; break; case T_ANDEQ: op = T_BITAND; break;
        case T_OREQ: op = T_BITOR; break; case T_XOREQ: op = T_XOR; break;
        case T_SHLEQ: op = T_SHL; break; case T_SHREQ: op = T_SHR; break;
        case T_DOTEQ: op = T_EQ; break; case T_DOTNEQ: op = T_NEQ; break;
        default: break;
    }
    auto w = W(t);
    if (t->kind == TY_FLT) {
        if (op == T_MOD) { FloatRemainder(t); return; }
        auto f64 = w == F64;
        uint8_t byte = 0;
        switch (op) {
            case T_PLUS: byte = f64 ? 0xa0 : 0x92; break;
            case T_MINUS: byte = f64 ? 0xa1 : 0x93; break;
            case T_MUL: byte = f64 ? 0xa2 : 0x94; break;
            case T_DIV: byte = f64 ? 0xa3 : 0x95; break;
            case T_EQ: byte = f64 ? 0x61 : 0x5b; break;
            case T_NEQ: byte = f64 ? 0x62 : 0x5c; break;
            case T_LT: byte = f64 ? 0x63 : 0x5d; break;
            case T_GT: byte = f64 ? 0x64 : 0x5e; break;
            case T_LTEQ: byte = f64 ? 0x65 : 0x5f; break;
            case T_GTEQ: byte = f64 ? 0x66 : 0x60; break;
            default: Fail(line, "this floating-point operation is not supported");
        }
        code.Op(byte); return;
    }
    if (!IsIntT(t) && t->kind != TY_BOOL && t->kind != TY_REF) Fail(line, "aggregate arithmetic/comparison is not supported");
    auto wide = w == I64;
    auto u = !IsIntT(t) || IsUnsigned(t->intstorage);
    auto bits = IsIntT(t) ? IntBits(t->intstorage) : 32;
    uint8_t cmp = 0;
    switch (op) {
        case T_EQ: cmp = wide ? 0x51 : 0x46; break;
        case T_NEQ: cmp = wide ? 0x52 : 0x47; break;
        case T_LT: cmp = wide ? (u ? 0x54 : 0x53) : (u ? 0x49 : 0x48); break;
        case T_GT: cmp = wide ? (u ? 0x56 : 0x55) : (u ? 0x4b : 0x4a); break;
        case T_LTEQ: cmp = wide ? (u ? 0x58 : 0x57) : (u ? 0x4d : 0x4c); break;
        case T_GTEQ: cmp = wide ? (u ? 0x5a : 0x59) : (u ? 0x4f : 0x4e); break;
        default: break;
    }
    if (cmp) { code.Op(cmp); return; }
    if (op == T_SHL || op == T_SHR) {
        Const(t, bits - 1); code.Op(wide ? 0x83 : 0x71);
        code.Op(op == T_SHL ? (wide ? 0x86 : 0x74) : wide ? (u ? 0x88 : 0x87) : (u ? 0x76 : 0x75));
        Normalize(t); return;
    }
    auto checked = c.opts.debug && !u && (op == T_PLUS || op == T_MINUS || op == T_MUL);
    if (op == T_DIV || op == T_MOD || checked) {
        auto b = Save(w), a = Save(w);
        if (op == T_DIV || op == T_MOD) {
            Get(b); code.Op(wide ? 0x50 : 0x45); TrapIf(line, "division by zero");
        }
        if ((op == T_DIV && !u && wide) || (checked && op == T_MUL && wide)) {
            Get(a); code.I64Const(INT64_MIN); code.Op(0x51);
            Get(b); code.I64Const(-1); code.Op(0x51); code.Op(0x71);
            if (checked) {
                Get(b); code.I64Const(INT64_MIN); code.Op(0x51);
                Get(a); code.I64Const(-1); code.Op(0x51); code.Op(0x71); code.Op(0x72);
            }
            TrapIf(line, "signed integer overflow");
        }
        auto calc64 = !u && !wide;
        Get(a); if (calc64) code.Op(0xac);
        Get(b); if (calc64) code.Op(0xac);
        auto big = wide || calc64;
        uint8_t instr = op == T_PLUS ? (big ? 0x7c : 0x6a)
                      : op == T_MINUS ? (big ? 0x7d : 0x6b)
                      : op == T_MUL ? (big ? 0x7e : 0x6c)
                      : op == T_DIV ? (big ? (u ? 0x80 : 0x7f) : (u ? 0x6e : 0x6d))
                      : (big ? (u ? 0x82 : 0x81) : (u ? 0x70 : 0x6f));
        code.Op(instr); auto r = Save(big ? I64 : I32);
        if (op == T_MOD && !u) {
            Get(r); code.I64Const(0); code.Op(0x53); Begin(0x04);
            Get(r); Get(b); if (calc64) code.Op(0xac); auto divisor = Save(I64);
            Get(divisor); code.I64Const(0); code.Op(0x53); Begin(0x04, I64);
            code.I64Const(0); Get(divisor); code.Op(0x7d); Else(); Get(divisor); End();
            code.Op(0x7c); Set(r); End();
        }
        if (!u && calc64 && (checked || (op == T_DIV && c.opts.debug))) {
            auto range = IntRange(t->intstorage);
            Get(r); code.I64Const(range.first); code.Op(0x53);
            Get(r); code.I64Const(range.second); code.Op(0x55); code.Op(0x72);
            TrapIf(line, "signed integer overflow");
        }
        if (checked && wide) {
            if (op == T_PLUS || op == T_MINUS) {
                Get(a); Get(op == T_PLUS ? r : b); code.Op(0x85);
                Get(op == T_PLUS ? b : a); Get(r); code.Op(0x85); code.Op(0x83);
                code.I64Const(0); code.Op(0x53); TrapIf(line, "signed integer overflow");
            } else {
                Get(b); code.Op(0x50); code.Op(0x45); Begin(0x04);
                Get(r); Get(b); code.Op(0x7f); Get(a); code.Op(0x52);
                TrapIf(line, "signed integer overflow"); End();
            }
        }
        Get(r); if (calc64) code.Op(0xa7); Normalize(t); return;
    }
    uint8_t byte = 0;
    switch (op) {
        case T_PLUS: byte = wide ? 0x7c : 0x6a; break;
        case T_MINUS: byte = wide ? 0x7d : 0x6b; break;
        case T_MUL: byte = wide ? 0x7e : 0x6c; break;
        case T_BITAND: byte = wide ? 0x83 : 0x71; break;
        case T_BITOR: byte = wide ? 0x84 : 0x72; break;
        case T_XOR: byte = wide ? 0x85 : 0x73; break;
        default: Fail(line, "unsupported integer operator");
    }
    code.Op(byte); Normalize(t);
}

} // namespace goose::direct_wasm
