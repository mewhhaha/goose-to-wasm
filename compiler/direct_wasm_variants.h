#pragma once
namespace goose::direct_wasm {

// Nominal values keep a target-specific layout: a 32-bit tag followed by a
// naturally aligned payload union. A bare variant contains only its payload.
// Dynamic payloads use owned descriptors and tagged deep copy/destruction.
// No byte-serialization or native C layout compatibility is implied.
inline Layout Compiler::VariantLayout(TypeExpr *owner, int vi) {
    auto ei = owner->enu->inst;
    if (!ei) Fail(owner->line, "enum specialization was not resolved");
    Layout result;
    const auto &fields = ei->en->variants.at(size_t(vi)).fields;
    const auto &types = ei->vftypes.at(size_t(vi));
    for (size_t i = 0; i < types.size(); i++) {
        if (fields[i].ispad) Fail(fields[i].line, "explicit variant padding is not supported");
        auto field = Size(types[i]);
        result.align = max(result.align, field.align);
        result.size = Align(result.size, field.align);
        result.fields.push_back(result.size);
        if (uint64_t(result.size) + field.size > uint64_t(opts.maximum_pages) * 65536)
            Fail(owner->line, "variant exceeds the configured linear-memory limit");
        result.size += field.size;
    }
    result.size = max<uint32_t>(1, Align(result.size, result.align));
    return result;
}

inline uint32_t Compiler::PayloadOffset(TypeExpr *owner) {
    auto ei = owner->enu->inst;
    if (!ei) Fail(owner->line, "enum specialization was not resolved");
    uint32_t alignment = 4;
    for (size_t i = 0; i < ei->vftypes.size(); i++)
        alignment = max(alignment, VariantLayout(owner, int(i)).align);
    return Align(4, alignment);
}

inline Layout Compiler::NominalLayout(TypeExpr *t) {
    if (t->kind == TY_VARIANT)
        return VariantLayout(t->var->adt, t->var->adt->enu->en->VariantIndex(t->var->variant));
    Layout result;
    auto payload = PayloadOffset(t);
    result.align = payload;
    uint32_t largest = 0;
    for (size_t i = 0; i < t->enu->inst->vftypes.size(); i++)
        largest = max(largest, VariantLayout(t, int(i)).size);
    if (uint64_t(payload) + largest > uint64_t(opts.maximum_pages) * 65536)
        Fail(t->line, "enum exceeds the configured linear-memory limit");
    result.size = Align(payload + largest, result.align);
    return result;
}

inline TypeExpr *Compiler::FieldType(TypeExpr *t, size_t index) {
    if (t->kind == TY_STRUCT) return t->struc->inst->ftypes.at(index);
    if (t->kind == TY_VARIANT) {
        auto owner = t->var->adt;
        auto vi = owner->enu->en->VariantIndex(t->var->variant);
        return owner->enu->inst->vftypes.at(size_t(vi)).at(index);
    }
    Fail(t->line, "this nominal value has no directly accessible fields");
}

inline bool Function::ConvertNominal(TypeExpr *from, TypeExpr *to, Line line) {
    if (to->kind != TY_ENUM || (from->kind != TY_ENUM && from->kind != TY_VARIANT)) return false;
    auto owner = from->kind == TY_ENUM ? from : from->var->adt;
    if (owner->enu->inst != to->enu->inst)
        Fail(line, "cannot convert between unrelated enum types");
    c.Size(to); c.Size(from);
    if (from->kind == TY_ENUM) return true;
    auto source = Save(I32), dest = Frame(to);
    auto vi = owner->enu->en->VariantIndex(from->var->variant);
    if (c.OwnsDynamic(to)) { FrameAddress(dest); auto at = Save(I32); DestroyOwned(to, at); }
    FrameAddress(dest); code.I32Const(0); code.I32Const(int32_t(c.Size(to).size)); code.Fill();
    FrameAddress(dest); code.I32Const(vi); code.Mem(0x36);
    // Empty payloads have a one-byte standalone representation, but no
    // semantic fields. The zeroed union is already a complete value.
    if (!from->var->variant->fields.empty()) {
        FrameAddress(dest + c.PayloadOffset(to)); Get(source);
        Store(from);
    }
    FrameAddress(dest);
    return true;
}

inline bool Function::ConstructNominal(Node *n) {
    auto t = n->exprtype;
    if (!t || (t->kind != TY_ENUM && t->kind != TY_VARIANT)) return false;
    auto literal = Is<StructLit>(n);
    auto constant = Is<Dot>(n);
    auto variant = literal ? literal->variant : constant ? constant->variantconst : nullptr;
    if (!variant) return false;
    auto owner = t->kind == TY_ENUM ? t : t->var->adt;
    auto vi = owner->enu->en->VariantIndex(variant);
    auto layout = c.VariantLayout(owner, vi);
    auto dest = Frame(t);
    if (c.OwnsDynamic(t)) { FrameAddress(dest); auto at = Save(I32); DestroyOwned(t, at); }
    FrameAddress(dest); code.I32Const(0); code.I32Const(int32_t(c.Size(t).size)); code.Fill();
    uint32_t payload = dest;
    if (t->kind == TY_ENUM) {
        FrameAddress(dest); code.I32Const(vi); code.Mem(0x36);
        payload += c.PayloadOffset(owner);
    }
    if (literal) for (size_t i = 0; i < literal->inits.size(); i++) {
        auto fi = i < literal->fieldindices.size() ? literal->fieldindices[i] : int(i);
        if (fi < 0 || size_t(fi) >= layout.fields.size()) Fail(n->line, "invalid variant initializer");
        auto ft = owner->enu->inst->vftypes.at(size_t(vi)).at(size_t(fi));
        FrameAddress(payload + layout.fields[size_t(fi)]); To(literal->inits[i].val, ft); Store(ft);
    }
    FrameAddress(dest);
    return true;
}

inline bool Function::MatchNominal(MatchExpr *n) {
    auto t = n->scrutinee->exprtype;
    if (t->kind == TY_REF) t = t->ref->sub;
    if (t->kind != TY_ENUM) return false;
    c.Size(t);
    Object(n->scrutinee); auto value = Save(I32);
    Get(value); code.Mem(0x28); auto tag = Save(I32);
    auto ts = Values(n); vector<uint32_t> values;
    for (auto type : ts) values.push_back(Local(type));
    auto done = Begin(); bool wildcard = false;
    for (auto &arm : n->arms) {
        bool any = arm.pat.kind == P_WILDCARD;
        if (!any) {
            bool first = true;
            for (auto variant : arm.variants) {
                Get(tag); code.I32Const(t->enu->en->VariantIndex(variant)); code.Op(0x46);
                if (!first) code.Op(0x72);
                first = false;
            }
            if (first) Fail(n->line, "enum match arm has no variants");
            Begin(0x04);
        }
        if (arm.binder) {
            auto binding = Bind(arm.binder);
            Get(value); code.I32Const(int32_t(c.PayloadOffset(t))); code.Op(0x6a);
            Write(binding);
        }
        if (ts.empty()) Discard(arm.body);
        else SetResults({ arm.body }, ts, values, arm.body->line);
        Br(done);
        if (!any) End(); else { wildcard = true; break; }
    }
    if (!wildcard) Abort(n->line, "invalid enum tag");
    End(); for (auto local : values) Get(local);
    return true;
}

inline bool Function::PrintNominal(TypeExpr *t, uint32_t value, Line line) {
    if (t->kind != TY_STRUCT && t->kind != TY_ENUM && t->kind != TY_VARIANT) return false;
    auto fields = [&](const vector<TypeExpr *> &types, const Layout &layout, uint32_t base) {
        for (size_t i = 0; i < types.size(); i++) {
            if (i) PrintText(", ");
            Get(value); code.I32Const(int32_t(base + layout.fields[i])); code.Op(0x6a); Load(types[i]);
            auto local = Save(types[i]); Print(types[i], local, line, true);
        }
    };
    if (t->kind == TY_STRUCT) {
        string name; t->Dump(name); PrintText(name + " { ");
        fields(t->struc->inst->ftypes, c.Size(t), 0); PrintText(" }"); return true;
    }
    auto owner = t->kind == TY_ENUM ? t : t->var->adt;
    auto variant = [&](int vi, uint32_t base) {
        auto &v = owner->enu->en->variants[size_t(vi)];
        if (v.fields.empty()) {
            PrintText(string(owner->enu->en->name) + "." + string(v.name));
        } else {
            PrintText(string(v.name) + " { ");
            fields(owner->enu->inst->vftypes[size_t(vi)], c.VariantLayout(owner, vi), base);
            PrintText(" }");
        }
    };
    if (t->kind == TY_VARIANT) {
        variant(owner->enu->en->VariantIndex(t->var->variant), 0); return true;
    }
    Get(value); code.Mem(0x28); auto tag = Save(I32);
    auto done = Begin();
    for (size_t i = 0; i < owner->enu->en->variants.size(); i++) {
        Get(tag); code.I32Const(int32_t(i)); code.Op(0x46); Begin(0x04);
        variant(int(i), c.PayloadOffset(owner)); Br(done); End();
    }
    Abort(line, "invalid enum tag"); End(); return true;
}

} // namespace goose::direct_wasm
