#pragma once
namespace goose::direct_wasm {

// Variable-mode enums retain their language storage class. Their private
// control header owns an aligned tag/payload image in a stable data region.
inline void Function::ConstructEnumFromCaptured(TypeExpr *source_type, uint32_t source,
        const ConstructionDestination &destination, Line line) {
    Get(source);
    if (source_type->kind == TY_REF) { source_type = source_type->ref->sub; Load(source_type); }
    CheckRegionDestination(source_type, destination, line);
    auto value = Save(I32);
    auto type = destination.location.storage_type;
    auto layout = c.EnumImageLayout(type->enu->inst, line);
    LocationAddress(destination.location); auto header = Save(I32);
    code.I64Const(layout.size); auto count = Save(I64);
    ReserveRegion(header, count, c.ast.inttypes[IS_U8], line);
    Get(header); code.Mem(0x28, 2); auto base = Save(I32);
    if (source_type->kind == TY_VARIANT) {
        Get(base); code.I32Const(0); code.I32Const(int32_t(layout.size)); code.Fill();
        Get(base); code.I32Const(type->enu->inst->en->VariantIndex(source_type->var->variant)); code.Mem(0x36, 2);
        Get(base); code.I32Const(int32_t(layout.payload)); code.Op(0x6a); Get(value);
        code.I32Const(int32_t(c.FixedLayout(source_type).size)); code.Copy();
    } else {
        Get(base); Get(value);
        if (Compiler::RegionEnum(source_type)) code.Mem(0x28, 2);
        code.I32Const(int32_t(layout.size)); code.Copy();
    }
    Get(header); code.I32Const(int32_t(layout.size)); code.Mem(0x36, 2, 4);
}

inline void Function::ConstructEnumInto(Node *node, const ConstructionDestination &destination) {
    auto type = destination.location.storage_type;
    auto ei = type->enu->inst;
    auto line = node ? node->line : type->line;
    auto layout = c.EnumImageLayout(ei, line);
    if (auto copy = Is<Call>(node); copy && copy->builtin == B_COPY) {
        ConstructEnumInto(copy->FirstArg(), destination); return;
    }
    if (auto id = Is<Ident>(node); id && named_regions.count(id->vdef)) {
        auto &named = named_regions.at(id->vdef).location.storage;
        auto &receiving = destination.location.storage;
        auto left = get_if<Slot>(&named);
        auto right = get_if<Slot>(&receiving);
        if (left && right ? left->kind == right->kind && left->index == right->index :
            !left && !right && get<AddressLocal>(named).index == get<AddressLocal>(receiving).index)
            return; // Whole-image named construction already uses this owner.
    }
    if (auto block = Is<Block>(node)) {
        BlockInto(block, { type }, { Local(I32) }, { destination }); return;
    }
    if (auto conditional = Is<IfExpr>(node)) {
        vector<TypeExpr *> types { type }; vector<uint32_t> values { Local(I32) };
        ResultDestinations destinations { destination };
        Truth(conditional->cond); Begin(0x04);
        BlockInto(conditional->thenb, types, values, destinations);
        if (conditional->elseb) {
            Else();
            if (Values(conditional->elseb).empty()) Discard(conditional->elseb);
            else SetResults({ conditional->elseb }, types, values, line, destinations);
        }
        End(); return;
    }
    if (Is<LoopExpr>(node) || Is<EarlyBlock>(node) || Is<MatchExpr>(node)) {
        ControlValue(node, { type }, { Local(I32) }, { destination }); return;
    }
    if (auto call = Is<Call>(node); call && call->builtin == B_DEFAULT) {
        ConstructEnumInto(call->defaultinit, destination); return;
    }
    if (auto call = Is<Call>(node); call && call->builtin < 0 && call->spec &&
        call->spec->rets.size() == 1 && Compiler::RegionEnum(call->spec->rets[0])) {
        EmitCall(call, false, { destination }); code.Op(0x1a); return;
    }
    if (auto inlined = Is<InlineBlock>(node); inlined && inlined->spec &&
        inlined->spec->rets.size() == 1 && Compiler::RegionEnum(inlined->spec->rets[0])) {
        EmitInline(inlined, false, { destination }); code.Op(0x1a); return;
    }
    auto literal = Is<StructLit>(node);
    auto constant = Is<Dot>(node);
    if (!node || literal || (constant && constant->variantconst)) {
        auto variant = literal ? literal->variant : constant ? constant->variantconst : &ei->en->variants[0];
        auto actual = literal ? literal->einst : constant ? constant->einst : ei;
        if (actual != ei || !variant) Fail(line, "owned enum literal has a different instantiation");
        auto vi = ei->en->VariantIndex(variant);
        auto payload = c.Payload(ei, vi);
        LocationAddress(destination.location); auto header = Save(I32);
        Get(header); code.Mem(0x28, 2); auto base = Save(I32);
        auto reserve = [&](uint32_t bytes) {
            code.I64Const(bytes); ReserveRegion(header, Save(I64), c.ast.inttypes[IS_U8], line);
        };
        auto clear = [&](uint32_t offset, uint32_t bytes) {
            if (!bytes) return;
            Get(base); code.I32Const(int32_t(offset)); code.Op(0x6a);
            code.I32Const(0); code.I32Const(int32_t(bytes)); code.Fill();
        };
        reserve(4); Get(base); code.I32Const(vi); code.Mem(0x36, 2);
        uint32_t initialized = 4;
        for (size_t i = 0; i < ei->vftypes[size_t(vi)].size(); i++) {
            auto ft = ei->vftypes[size_t(vi)][i];
            auto init = literal ? literal->InitFor(int(i)) : nullptr;
            optional<CapturedValue> value;
            if (init) value = CaptureBorrowed(init, ft);
            auto start = layout.payload + payload.fields[i];
            auto size = c.FixedLayout(ft).size;
            reserve(start + size); clear(initialized, start - initialized);
            if (value) {
                Get(base); code.I32Const(int32_t(start)); code.Op(0x6a);
                auto place = Save(I32);
                StoreCopy({ ft, AddressLocal { place } }, *value);
            } else clear(start, size);
            initialized = start + size;
        }
        // Fully initialize the inactive union bytes so mode conversion and
        // owned copies can use the same bounded image layout.
        reserve(layout.size); clear(initialized, layout.size - initialized);
        Get(header); code.I32Const(int32_t(layout.size)); code.Mem(0x36, 2, 4); return;
    }
    auto natural = node->exprtype;
    if (Is<Ident>(node) || Is<Index>(node) || (Is<Dot>(node) && Is<Dot>(node)->IsField())) {
        auto place = PinPlace(node); natural = place.storage_type; ReadLocation(place, natural);
    } else if (auto call = Is<Call>(node); call && call->builtin < 0) {
        auto types = NaturalResults(node);
        if (types.size() != 1) Fail(line, "owned enum construction requires one source result");
        natural = types[0]; EmitCall(call, false);
    } else if (auto inlined = Is<InlineBlock>(node); inlined && inlined->spec) {
        if (inlined->spec->rets.size() != 1) Fail(line, "owned enum construction requires one inline result");
        natural = inlined->spec->rets[0]; EmitInline(inlined, false);
    } else Expr(node);
    ConstructEnumFromCaptured(natural, Save(natural), destination, line);
}

} // namespace goose::direct_wasm
