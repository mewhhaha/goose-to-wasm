#pragma once
namespace goose::direct_wasm {

inline Location Function::TailHeaderLocation(const Location &owner) {
    if (!Compiler::RegionStruct(owner.storage_type)) return owner;
    auto layout = c.ControlLayout(owner.storage_type);
    return OffsetLocation(owner, layout.payload, c.TailType(owner.storage_type));
}

inline void Function::ConstructStructFromCaptured(TypeExpr *source_type, uint32_t source,
        const ConstructionDestination &destination, Line line) {
    Get(source);
    if (source_type->kind == TY_REF) { source_type = source_type->ref->sub; Load(source_type); }
    CheckRegionDestination(source_type, destination, line);
    auto value = Save(I32);
    auto layout = c.ControlLayout(source_type);
    // Prefix fields have fixed value semantics; never copy the embedded
    // owner descriptor, whose region belongs to the receiving object.
    if (layout.payload) {
        LocationAddress(destination.location); Get(value); code.I32Const(int32_t(layout.payload)); code.Copy();
    }
    auto source_tail = TailHeaderLocation({ source_type, AddressLocal { value } });
    LocationAddress(source_tail); auto tail = Save(I32);
    ConstructRegionFromCaptured(source_tail.storage_type, tail,
        { TailHeaderLocation(destination.location), destination.lifetime }, line);
}

inline void Function::ConstructStructInto(Node *node, const ConstructionDestination &destination) {
    auto type = destination.location.storage_type;
    auto layout = c.ControlLayout(type);
    auto line = node ? node->line : type->line;
    if (auto copy = Is<Call>(node); copy && copy->builtin == B_COPY) {
        ConstructStructInto(copy->FirstArg(), destination); return;
    }
    if (auto id = Is<Ident>(node); id && named_regions.count(id->vdef)) {
        auto &named = named_regions.at(id->vdef).location.storage;
        auto &receiving = destination.location.storage;
        auto left = get_if<Slot>(&named);
        auto right = get_if<Slot>(&receiving);
        auto same = left && right ? left->kind == right->kind && left->index == right->index
                    : !left && !right && get<AddressLocal>(named).index == get<AddressLocal>(receiving).index;
        if (same) return; // The complete named object already lives here.
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
    if (auto call = Is<Call>(node); call && call->builtin < 0 && call->spec &&
        call->spec->rets.size() == 1 && Compiler::RegionOwner(call->spec->rets[0])) {
        EmitCall(call, false, { destination }); code.Op(0x1a); return;
    }
    if (auto inlined = Is<InlineBlock>(node); inlined && inlined->spec &&
        inlined->spec->rets.size() == 1 && Compiler::RegionOwner(inlined->spec->rets[0])) {
        EmitInline(inlined, false, { destination }); code.Op(0x1a); return;
    }
    if (!node || Is<StructLit>(node)) {
        auto literal = Is<StructLit>(node);
        if (literal && literal->sinst != type->struc->inst)
            Fail(line, "owned struct literal has a different instantiation");
        if (layout.payload) {
            LocationAddress(destination.location); code.I32Const(0); code.I32Const(int32_t(layout.payload)); code.Fill();
        }
        auto inst = type->struc->inst;
        for (size_t i = 0; i < inst->ftypes.size(); i++) {
            auto field = OffsetLocation(destination.location, layout.fields[i], inst->ftypes[i]);
            auto init = literal ? literal->InitFor(int(i)) : nullptr;
            if (i + 1 == inst->ftypes.size()) ConstructRegionInto(init, { field, destination.lifetime });
            else if (init) ConstructInto(init, { field, destination.lifetime });
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
    ConstructStructFromCaptured(natural, source, destination, line);
}

} // namespace goose::direct_wasm
