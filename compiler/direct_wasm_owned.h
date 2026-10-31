#pragma once
namespace goose::direct_wasm {

inline Location Function::TailHeaderLocation(const Location &owner) {
    if (!Compiler::RegionRecord(owner.storage_type)) return owner;
    auto layout = c.ControlLayout(owner.storage_type);
    return OffsetLocation(owner, layout.payload, c.TailType(owner.storage_type));
}

inline void Function::ConstructRecordFromCaptured(TypeExpr *source_type, uint32_t source,
        const ConstructionDestination &destination, Line line) {
    Get(source);
    if (source_type->kind == TY_REF) { source_type = source_type->ref->sub; Load(source_type); }
    CheckRegionDestination(source_type, destination, line);
    auto value = Save(I32);
    if (!Compiler::FrameStruct(source_type)) {
        Location original { source_type, AddressLocal { value } };
        auto bytes = RecordImageBytes(original, line);
        auto source_base = RecordImageBase(original, line);
        LocationAddress(TailHeaderLocation(destination.location)); auto header = Save(I32);
        auto end = ReserveImageBytes(header, bytes, line);
        Get(RegionCursor(header)); Get(source_base); Get(bytes); code.Op(0xa7); code.Copy();
        PublishCursor(header, end); DecodeRecordImage(destination.location, line); return;
    }
    auto layout = c.ControlLayout(source_type);
    // Prefix fields have fixed value semantics; never copy the embedded
    // owner descriptor, whose region belongs to the receiving object.
    if (layout.payload) {
        LocationAddress(destination.location); CanonicalAddress(layout.payload); Get(value); CanonicalAddress(layout.payload); code.I32Const(int32_t(layout.payload)); code.Copy();
    }
    auto source_tail = TailHeaderLocation({ source_type, AddressLocal { value } });
    LocationAddress(source_tail); auto tail = Save(I32);
    ConstructRegionFromCaptured(source_tail.storage_type, tail,
        { TailHeaderLocation(destination.location), destination.lifetime, false, destination.enum_guard, destination.escape_stage, destination.normal_result, TailPublication(destination) }, line);
}

inline void Function::ConstructRecordInto(Node *node, const ConstructionDestination &destination) {
    auto type = destination.location.storage_type;
    auto layout = c.ControlLayout(type);
    auto line = node ? node->line : type->line;
    if (auto copy = Is<Call>(node); copy && copy->builtin == B_COPY) {
        ConstructRecordInto(copy->FirstArg(), destination); return;
    }
    if (auto id = Is<Ident>(node); id && named_regions.count(id->vdef)) {
        auto &named = named_regions.at(id->vdef).location.storage;
        auto &receiving = destination.location.storage;
        auto left = get_if<Slot>(&named);
        auto right = get_if<Slot>(&receiving);
        auto same = left && right ? left->kind == right->kind && left->index == right->index
                    : !left && !right && get<AddressLocal>(named).index == get<AddressLocal>(receiving).index;
        if (same) {
            if (Compiler::FrameStruct(type)) {
                auto source = PinPlace(node);
                if (layout.payload) {
                    LocationAddress(destination.location); CanonicalAddress(layout.payload); LocationAddress(source); CanonicalAddress(layout.payload);
                    code.I32Const(int32_t(layout.payload)); code.Copy();
                }
                // Frame-object prefixes and length are values at this return
                // position. Only the tail's element storage is shared.
                LocationAddress(TailHeaderLocation(destination.location)); auto receiving_tail = Save(I32);
                LocationAddress(TailHeaderLocation(source)); auto source_tail = Save(I32);
                for (uint32_t offset : { 0u, 4u }) {
                    Get(receiving_tail); Get(source_tail); code.Mem(0x28, 2, offset); code.Mem(0x36, 2, offset);
                    PublishHeader(receiving_tail, offset);
                }
            }
            return;
        }
    }
    if (ConstructNormalRecordImage(node, destination)) return;
    if (ConstructNormalRecordResult(node, destination)) return;
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
    if (auto call = Is<Call>(node); call && call->builtin < 0 &&
        NaturalResults(call).size() == 1 && Compiler::RegionOwner(NaturalResults(call)[0])) {
        OpenConstruction open(destination);
        EmitCall(call, false, { destination }); code.Op(0x1a); return;
    }
    if (auto inlined = Is<InlineBlock>(node); inlined && inlined->spec &&
        inlined->spec->rets.size() == 1 && Compiler::RegionOwner(inlined->spec->rets[0])) {
        EmitInline(inlined, false, { destination }); code.Op(0x1a); return;
    }
    OpenConstruction open(destination);
    if (!node || Is<StructLit>(node)) {
        auto literal = Is<StructLit>(node);
        if (literal && (type->kind == TY_STRUCT ? literal->sinst != type->struc->inst :
            literal->einst != type->var->adt->enu->inst || literal->variant != type->var->variant))
            Fail(line, "owned record literal has a different nominal type");
        if (!Compiler::FrameStruct(type)) { ConstructRecordImageLiteral(node, destination); return; }
        auto &fields = c.RecordFields(type);
        for (size_t i = 0; i < fields.size(); i++) {
            auto field = OffsetLocation(destination.location, layout.fields[i], fields[i]);
            auto init = literal ? literal->InitFor(int(i)) : nullptr;
            if (i + 1 == fields.size()) {
                if (Compiler::FrameStruct(type) && Compiler::RegionArray(fields[i])) {
                    LocationAddress(field); auto header = Save(I32);
                    if (c.region_cursors) {
                        auto base = RegionCursor(header);
                        Get(header); Get(base); code.Mem(0x36, 2);
                    }
                    Get(header); code.I32Const(0); code.Mem(0x36, 2, 4);
                    PublishHeader(header, 0); PublishHeader(header, 4);
                }
                ConstructRegionInto(init, { field, destination.lifetime, false, destination.enum_guard, false, false, OffsetPublication(destination, layout.fields[i]), destination.construction, destination.open0 });
            }
            else if (init) ConstructInto(init, { field, destination.lifetime });
            else {
                // Omitted optional fields become null when their position is
                // reached. An earlier initializer may exit before this write.
                LocationAddress(field); CanonicalAddress(c.FixedLayout(field.storage_type).size); code.I32Const(0);
                code.I32Const(int32_t(c.FixedLayout(field.storage_type).size)); code.Fill();
            }
        }
        return;
    }
    TypeExpr *natural = node->exprtype;
    if (Is<Ident>(node) || Is<Index>(node) || (Is<Dot>(node) && Is<Dot>(node)->IsField())) {
        auto place = PinPlace(node); natural = place.storage_type; ReadLocation(place, natural);
    } else if (auto call = Is<Call>(node); call && call->builtin < 0) {
        auto types = NaturalResults(node);
        if (types.size() != 1) Fail(line, "owned struct construction requires one source result");
        natural = types[0]; EmitCall(call, false);
    } else Expr(node);
    auto source = Save(natural);
    ConstructRecordFromCaptured(natural, source, destination, line);
}

} // namespace goose::direct_wasm
