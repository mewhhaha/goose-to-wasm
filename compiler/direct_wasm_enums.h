#pragma once
namespace goose::direct_wasm {

inline ConstructionDestination Function::PrepareEnumPayload(const ConstructionDestination &receiver,
        TypeExpr *variant, Line line) {
    auto type = receiver.location.storage_type;
    CheckRegionDestination(variant, receiver, line);
    auto ei = type->enu->inst;
    auto layout = c.EnumImageLayout(ei, line);
    auto vi = ei->en->VariantIndex(variant->var->variant);
    LocationAddress(receiver.location); auto header = Save(I32);
    // Commit the prefix before deriving a tail base. A base beyond the limit
    // would otherwise make unsigned remaining-capacity arithmetic wrap.
    code.I64Const(layout.size); ReserveRegion(header, Save(I64), c.ast.inttypes[IS_U8], line);
    Get(header); code.Mem(0x28, 2); auto base = Save(I32);
    Get(base); code.I32Const(vi); code.Mem(0x36, 2);
    Get(header); code.I32Const(int32_t(layout.size)); code.Mem(0x36, 2, 4);
    Get(base); code.I32Const(int32_t(layout.size)); code.Op(0x6a); PublishCursor(header, Save(I32));
    auto payload = OffsetLocation({ variant, AddressLocal { base } }, layout.payload, variant);
    ConstructionDestination destination { payload, receiver.lifetime, false,
        ConstructionDestination::EnumGuard { base, header, vi }, false, receiver.normal_result };
    if (Compiler::RegionVariant(variant)) {
        LocationAddress(TailHeaderLocation(payload)); auto tail = Save(I32);
        Get(tail); Get(base); code.I32Const(int32_t(layout.size)); code.Op(0x6a); code.Mem(0x36, 2);
        Get(tail); code.I32Const(0); code.Mem(0x36, 2, 4);
        Get(tail); Get(header); code.Mem(0x28, 2, 8); code.Mem(0x36, 2, 8);
        Get(tail); code.I32Const(0); code.Mem(0x36, 2, 12);
        Get(tail); code.I32Const(0); code.Mem(0x36, 2, 16);
        Get(tail); code.I32Const(0); code.Mem(0x36, 2, 20);
    }
    return destination;
}

inline void Function::FinishEnumPayload(const ConstructionDestination &receiver, TypeExpr *variant, Line line) {
    LocationAddress(receiver.location); auto header = Save(I32);
    auto layout = c.EnumImageLayout(receiver.location.storage_type->enu->inst, line);
    if (Compiler::RegionVariant(variant)) {
        Get(header); code.Mem(0x28, 2); auto base = Save(I32);
        auto payload = OffsetLocation({ variant, AddressLocal { base } }, layout.payload, variant);
        auto array = c.TailType(variant);
        LocationAddress(TailHeaderLocation(payload)); auto tail = Save(I32);
        Get(tail); code.Mem(0x28, 2); code.Op(0xad);
        if (Compiler::RuntimeLimited(array)) ReadArrayCapacity(tail); else ReadArrayLength(tail);
        code.Op(0xad); code.I64Const(c.FixedLayout(array->arr->sub).size); code.Op(0x7e); code.Op(0x7c);
        Get(base); code.Op(0xad); code.Op(0x7d);
    } else code.I64Const(layout.size);
    auto bytes = Save(I64);
    ReserveRegion(header, bytes, c.ast.inttypes[IS_U8], line);
    Get(header); Get(bytes); code.Op(0xa7); code.Mem(0x36, 2, 4);
    Get(header); code.Mem(0x28, 2); Get(bytes); code.Op(0xa7); code.Op(0x6a); PublishCursor(header, Save(I32));
}

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
    auto construct = [&](TypeExpr *variant, uint32_t source_payload) {
        auto payload = PrepareEnumPayload(destination, variant, line);
        if (Compiler::RegionVariant(variant)) ConstructRecordFromCaptured(variant, source_payload, payload, line);
        else {
            auto fields = c.RecordFields(variant);
            auto payload_layout = c.FixedLayout(variant);
            for (size_t i = 0; i < fields.size(); i++) {
                auto field = OffsetLocation({ variant, AddressLocal { source_payload } }, payload_layout.fields[i], fields[i]);
                ReadLocation(field, fields[i]);
                StoreCopy(OffsetLocation(payload.location, payload_layout.fields[i], fields[i]), CaptureStack(fields[i]));
            }
        }
        FinishEnumPayload(destination, variant, line);
    };
    if (source_type->kind == TY_VARIANT) { construct(source_type, value); return; }
    Get(value);
    if (Compiler::RegionEnum(source_type)) code.Mem(0x28, 2);
    else c.FixedLayout(source_type);
    auto base = Save(I32);
    Get(base); code.Mem(0x28, 2); auto tag = Save(I32);
    auto done = Begin();
    for (size_t vi = 0; vi < type->enu->inst->vftypes.size(); vi++) {
        Get(tag); code.I32Const(int32_t(vi)); code.Op(0x46); Begin(0x04);
        Get(base); code.I32Const(int32_t(layout.payload)); code.Op(0x6a); auto source_payload = Save(I32);
        construct(c.EnumVariantType(type->enu->inst, int(vi), line), source_payload);
        Br(done); End();
    }
    Abort(line, "invalid enum tag"); End();
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
    if (auto call = Is<Call>(node); call && call->builtin < 0 &&
        NaturalResults(call).size() == 1 && (Compiler::RegionEnum(NaturalResults(call)[0]) || Compiler::RegionVariant(NaturalResults(call)[0]))) {
        EmitCall(call, false, { destination }); code.Op(0x1a); return;
    }
    if (auto inlined = Is<InlineBlock>(node); inlined && inlined->spec &&
        inlined->spec->rets.size() == 1 && (Compiler::RegionEnum(inlined->spec->rets[0]) || Compiler::RegionVariant(inlined->spec->rets[0]))) {
        EmitInline(inlined, false, { destination }); code.Op(0x1a); return;
    }
    auto literal = Is<StructLit>(node);
    auto constant = Is<Dot>(node);
    if (!node || literal || (constant && constant->variantconst)) {
        auto variant = literal ? literal->variant : constant ? constant->variantconst : &ei->en->variants[0];
        auto actual = literal ? literal->einst : constant ? constant->einst : ei;
        if (actual != ei || !variant) Fail(line, "owned enum literal has a different instantiation");
        auto vi = ei->en->VariantIndex(variant);
        if (!ei->allfixed) {
            auto vt = c.EnumVariantType(ei, vi, line);
            auto payload_destination = PrepareEnumPayload(destination, vt, line);
            if (Compiler::RegionVariant(vt)) ConstructRecordInto(node, payload_destination);
            else {
                auto payload_layout = c.FixedLayout(vt);
                for (size_t i = 0; i < ei->vftypes[size_t(vi)].size(); i++) {
                    auto ft = ei->vftypes[size_t(vi)][i];
                    auto init = literal ? literal->InitFor(int(i)) : nullptr;
                    auto field = OffsetLocation(payload_destination.location, payload_layout.fields[i], ft);
                    if (init) ConstructInto(init, { field, destination.lifetime });
                    else {
                        LocationAddress(field); code.I32Const(0);
                        code.I32Const(int32_t(c.FixedLayout(ft).size)); code.Fill();
                    }
                }
            }
            FinishEnumPayload(destination, vt, line); return;
        }
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
        for (size_t i = 0; i < ei->vftypes[size_t(vi)].size(); i++) {
            auto ft = ei->vftypes[size_t(vi)][i];
            auto init = literal ? literal->InitFor(int(i)) : nullptr;
            optional<CapturedValue> value;
            if (init) value = CaptureBorrowed(init, ft);
            auto start = layout.payload + payload.fields[i];
            auto size = c.FixedLayout(ft).size;
            reserve(start + size);
            if (value) {
                Get(base); code.I32Const(int32_t(start)); code.Op(0x6a);
                auto place = Save(I32);
                StoreCopy({ ft, AddressLocal { place } }, *value);
            } else clear(start, size);
        }
        // Reserve the full fixed image without writing inactive fields: an
        // earlier named payload reference may still be read by a later result.
        reserve(layout.size);
        Get(header); code.I32Const(int32_t(layout.size)); code.Mem(0x36, 2, 4);
        Get(base); code.I32Const(int32_t(layout.size)); code.Op(0x6a); PublishCursor(header, Save(I32)); return;
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
