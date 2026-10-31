#pragma once
namespace goose::direct_wasm {

inline void Function::ReadEnumTag(uint32_t bytes) { code.Mem(bytes == 1 ? 0x2d : 0x2f, 0); }
inline void Function::WriteEnumTag(uint32_t bytes) { code.Mem(bytes == 1 ? 0x3a : 0x3b, 0); }

inline Location Function::EnumPayloadLocation(const Location &owner, TypeExpr *variant, Line line) {
    auto ei = owner.storage_type->enu->inst;
    LocationAddress(owner); auto header = Save(I32);
    Get(header); code.Mem(0x28, 2); code.I32Const(int32_t(c.EnumTagBytes(ei))); code.Op(0x6a);
    auto base = Save(I32);
    if (!Compiler::RegionVariant(variant)) return { variant, AddressLocal { base } };
    auto vi = ei->en->VariantIndex(variant->var->variant);
    auto view = OffsetLocation(owner, c.ControlLayout(owner.storage_type).fields.at(size_t(vi)), variant);
    LocationAddress(TailHeaderLocation(view)); auto tail = Save(I32);
    Get(tail); Get(header); code.Mem(0x28, 2, 8); code.Mem(0x36, 2, 8);
    // Seed this typed view only. It need not agree with the active tag: a
    // saved old payload reference can intentionally read replacement bytes.
    SetRecordImageAnchor(view, base, line);
    return view;
}

inline void Function::SetEnumImageAnchor(const Location &owner, uint32_t base, Line) {
    LocationAddress(owner); auto header = Save(I32);
    for (auto offset : { 0u, 16u }) { Get(header); Get(base); code.Mem(0x36, 2, offset); }
    for (auto offset : { 4u, 12u, 20u }) { Get(header); code.I32Const(0); code.Mem(0x36, 2, offset); }
    // Inactive views consume control bytes only. Their image bounds are
    // checked when accessed, never by reserving the largest alternative.
}

inline uint32_t Function::EnumImageBytes(const Location &owner, Line line) {
    auto ei = owner.storage_type->enu->inst;
    LocationAddress(owner); auto header = Save(I32);
    Get(header); code.Mem(0x28, 2); auto base = Save(I32);
    Get(base); code.Op(0xad); code.I64Const(c.EnumTagBytes(ei)); code.Op(0x7c); auto prefix_end = Save(I64);
    Get(prefix_end); Get(header); code.Mem(0x28, 2, 8); code.Op(0xad); code.Op(0x56);
    TrapIf(line, "enum image prefix exceeds data region");
    Get(prefix_end); code.Op(0xa7); EnsureMemory(Save(I32), line);
    Get(base); ReadEnumTag(c.EnumTagBytes(ei)); auto tag = Save(I32);
    auto bytes = Local(I64); auto done = Begin();
    for (size_t vi = 0; vi < ei->vftypes.size(); vi++) {
        Get(tag); code.I32Const(int32_t(vi)); code.Op(0x46); Begin(0x04);
        auto variant = c.EnumVariantType(ei, int(vi), line);
        if (Compiler::RegionVariant(variant)) {
            auto payload = EnumPayloadLocation(owner, variant, line);
            Get(RecordImageBytes(payload, line));
        } else code.I64Const(EmptyLayout(c.RecordFieldDefs(variant)) ? 0 : c.FixedLayout(variant).size);
        code.I64Const(c.EnumTagBytes(ei)); code.Op(0x7c); Set(bytes); Br(done); End();
    }
    Abort(line, "invalid enum tag"); End();
    ReserveRegion(header, bytes, c.ast.inttypes[IS_U8], line); return bytes;
}

inline void Function::DecodeEnumImage(const Location &owner, Line line) {
    auto bytes = EnumImageBytes(owner, line);
    LocationAddress(owner); Get(bytes); code.Op(0xa7); code.Mem(0x36, 2, 4);
}

inline void Function::FinishEnumImage(const Location &owner, uint32_t start, bool land, Line line) {
    LocationAddress(owner); auto header = Save(I32);
    if (land) {
        Get(header); code.Mem(0x28, 2); auto base = Save(I32);
        auto finish = RegionCursor(header);
        Get(start); Get(finish); code.Op(0x4b); TrapIf(line, "invalid enum image landing span");
        Get(finish); code.Op(0xad); Get(start); code.Op(0xad); code.Op(0x7d); auto bytes = Save(I64);
        Get(base); code.Op(0xad); Get(bytes); code.Op(0x7c); auto end = Save(I64);
        Get(end); Get(header); code.Mem(0x28, 2, 8); code.Op(0xad); code.Op(0x56); TrapIf(line, "data region exhausted");
        Get(end); code.Op(0xa7); EnsureMemory(Save(I32), line);
        Get(base); Get(start); Get(bytes); code.Op(0xa7); code.Copy();
        Get(end); code.Op(0xa7); PublishCursor(header, Save(I32));
    }
    DecodeEnumImage(owner, line);
}

inline void Function::LandEnumImage(const Location &owner, uint32_t start, uint32_t entry, Line line) {
    LocationAddress(owner); auto header = Save(I32);
    auto finish = RegionCursor(header);
    Get(header); code.Mem(0x28, 2, 8); auto limit = Save(I32);
    Get(limit); code.OpU(0x23, G_REGION_BYTES); code.Op(0x6b); auto region_base = Save(I32);
    Get(start); Get(region_base); code.Op(0x49);
    Get(entry); Get(region_base); code.Op(0x49); code.Op(0x72);
    Get(entry); Get(limit); code.Op(0x4b); code.Op(0x72);
    Get(start); Get(finish); code.Op(0x4b); code.Op(0x72);
    Get(finish); Get(limit); code.Op(0x4b); code.Op(0x72);
    TrapIf(line, "invalid nonlocal enum image span");
    Get(finish); code.Op(0xad); Get(start); code.Op(0xad); code.Op(0x7d); auto bytes = Save(I64);
    Get(entry); code.Op(0xad); Get(bytes); code.Op(0x7c); auto end = Save(I64);
    Get(end); Get(limit); code.Op(0xad); code.Op(0x56); TrapIf(line, "data region exhausted");
    Get(end); code.Op(0xa7); EnsureMemory(Save(I32), line);
    Get(entry); Get(start); Get(bytes); code.Op(0xa7); code.Copy();
    SetEnumImageAnchor(owner, entry, line); DecodeEnumImage(owner, line);
    Get(end); code.Op(0xa7); PublishCursor(header, Save(I32));
}

inline bool Function::ConstructNormalEnumImage(Node *value, const ConstructionDestination &destination) {
    if (!c.region_cursors || destination.escape_stage || !destination.normal_result) return false;
    auto type = destination.location.storage_type; auto line = value ? value->line : type->line;
    LocationAddress(destination.location); auto original = Save(I32); auto start = RegionCursor(original);
    auto layout = c.ControlLayout(type);
    Location stage { type, Slot { Slot::FRAME, FrameBytes(layout.size, layout.align), type } };
    LocationAddress(stage); auto header = Save(I32);
    Get(header); Get(original); code.Mem(0x28, 2, 8); code.Mem(0x36, 2, 8);
    SetEnumImageAnchor(stage, start, line);
    auto depth = cleanups.size(), private_depth = private_headers.size();
    RegisterEffectOwner(stage); private_headers.push_back({ stage, cleanups.size() });
    auto land = destination.construction->open > destination.open0;
    ConstructEnumInto(value, { stage, ConstructionDestination::Statement, false, destination.enum_guard,
                              true, false, {}, destination.construction, destination.open0 });
    FinishEnumImage(destination.location, start, land, line);
    CloseCleanups(depth); private_headers.resize(private_depth); return true;
}

inline ConstructionDestination Function::PrepareEnumPayload(const ConstructionDestination &receiver,
        TypeExpr *variant, Line line, bool tag) {
    CheckRegionDestination(variant, receiver, line);
    auto ei = receiver.location.storage_type->enu->inst;
    auto vi = ei->en->VariantIndex(variant->var->variant);
    LocationAddress(receiver.location); auto header = Save(I32);
    auto end = RegionCursor(header);
    if (tag) {
        code.I64Const(c.EnumTagBytes(ei)); auto top = ReserveImageBytes(header, Save(I64), line);
        Get(end); code.I32Const(vi); WriteEnumTag(c.EnumTagBytes(ei)); PublishCursor(header, top); end = top;
    }
    Get(header); code.Mem(0x28, 2); auto anchor = Save(I32);
    auto guard = ConstructionDestination::EnumGuard { anchor, header, vi, c.EnumTagBytes(ei) };
    if (!Compiler::RegionVariant(variant))
        return { { variant, AddressLocal { end } }, receiver.lifetime, false, guard, true, false, {}, receiver.construction, receiver.open0 };
    auto layout = c.ControlLayout(variant);
    Location payload { variant, Slot { Slot::FRAME, FrameBytes(layout.size, layout.align), variant } };
    LocationAddress(TailHeaderLocation(payload)); auto tail = Save(I32);
    Get(tail); code.I32Const(0); code.I32Const(int32_t(owner_control_bytes)); code.Fill();
    Get(tail); Get(header); code.Mem(0x28, 2, 8); code.Mem(0x36, 2, 8);
    SetRecordImageAnchor(payload, end, line);
    RegisterEffectOwner(payload); private_headers.push_back({ TailHeaderLocation(payload), cleanups.size() });
    return { payload, receiver.lifetime, false, guard, true, false, {}, receiver.construction, receiver.open0 };
}

inline void Function::FinishEnumPayload(const ConstructionDestination &receiver, TypeExpr *, Line line) {
    DecodeEnumImage(receiver.location, line);
}

inline void Function::AppendFixedEnumPayload(TypeExpr *variant, uint32_t value,
        const ConstructionDestination &destination, Line line) {
    auto bytes = EmptyLayout(c.RecordFieldDefs(variant)) ? 0 : c.FixedLayout(variant).size;
    LocationAddress(destination.location); auto header = Save(I32);
    code.I64Const(bytes); auto end = ReserveImageBytes(header, Save(I64), line);
    if (bytes) { Get(RegionCursor(header)); Get(value); code.I32Const(int32_t(bytes)); code.Copy(); }
    PublishCursor(header, end);
}

inline Function::PreparedEnumResults Function::PrepareEnumResults(const vector<TypeExpr *> &types,
        const ResultDestinations &receivers, Line line, bool tag) {
    PreparedEnumResults result { receivers, ResultDestinations(types.size()), vector<TypeExpr *>(types.size(), nullptr), vector<bool>(types.size()) };
    for (size_t i = 0; i < types.size(); i++) {
        auto variant = Compiler::VariantSource(types[i]);
        if (!variant || receivers.size() != types.size() || !receivers[i] ||
            !Compiler::RegionEnum(receivers[i]->location.storage_type)) continue;
        // Fixed tuple results are captured first and adapted by SetResults.
        if (types.size() > 1 && !Compiler::RegionVariant(types[i])) continue;
        result.receivers[i] = receivers[i]; result.variants[i] = variant;
        // GenForward opens adapted nonfixed tuple channels. Single calls
        // follow their enclosing ordinary/control construction scope instead.
        result.opened[i] = types.size() > 1 && Compiler::RegionVariant(types[i]);
        if (result.opened[i]) receivers[i]->construction->open++;
        // A never-returning argument can leave this node's final annotation
        // unadapted. NaturalResults alone does not authorize a tag write.
        result.producers[i] = PrepareEnumPayload(*receivers[i], variant, line, tag);
    }
    return result;
}

inline void Function::ApplyPreparedEnumResults(RegionResultPlan &plan, const PreparedEnumResults &prepared) {
    for (size_t i = 0; i < prepared.variants.size(); i++) if (prepared.variants[i]) {
        plan.values[i] = prepared.receivers[i]; plan.enum_payloads[i] = prepared.variants[i];
        if (!plan.producers[i] && Compiler::RegionVariant(prepared.variants[i])) plan.producers[i] = prepared.producers[i];
    }
}

inline void Function::ClosePreparedEnumResults(const PreparedEnumResults &prepared) {
    for (size_t i = 0; i < prepared.receivers.size(); i++)
        if (prepared.opened[i]) prepared.receivers[i]->construction->open--;
}

inline void Function::ConstructEnumFromCaptured(TypeExpr *source_type, uint32_t source,
        const ConstructionDestination &destination, Line line) {
    Get(source);
    if (source_type->kind == TY_REF) { source_type = source_type->ref->sub; Load(source_type); }
    CheckRegionDestination(source_type, destination, line);
    auto value = Save(I32);
    if (Compiler::RegionEnum(source_type)) {
        Location original { source_type, AddressLocal { value } };
        auto bytes = EnumImageBytes(original, line);
        Get(value); code.Mem(0x28, 2); auto base = Save(I32);
        LocationAddress(destination.location); auto header = Save(I32);
        auto end = ReserveImageBytes(header, bytes, line);
        Get(RegionCursor(header)); Get(base); Get(bytes); code.Op(0xa7); code.Copy();
        PublishCursor(header, end); DecodeEnumImage(destination.location, line); return;
    }
    if (!Compiler::RegionVariant(source_type)) {
        Get(value); value = CopyCaptured(CaptureStack(source_type)).value_local;
    }
    auto construct = [&](TypeExpr *variant, uint32_t source_payload) {
        auto payload = PrepareEnumPayload(destination, variant, line);
        if (Compiler::RegionVariant(variant)) ConstructRecordFromCaptured(variant, source_payload, payload, line);
        else AppendFixedEnumPayload(variant, source_payload, destination, line);
        FinishEnumPayload(destination, variant, line);
    };
    if (source_type->kind == TY_VARIANT) { construct(source_type, value); return; }
    auto ei = source_type->enu->inst;
    auto layout = c.FixedLayout(source_type);
    Get(value); ReadEnumTag(c.EnumTagBytes(ei)); auto tag = Save(I32); auto done = Begin();
    for (size_t vi = 0; vi < ei->vftypes.size(); vi++) {
        Get(tag); code.I32Const(int32_t(vi)); code.Op(0x46); Begin(0x04);
        Get(value); code.I32Const(int32_t(layout.payload)); code.Op(0x6a);
        construct(c.EnumVariantType(ei, int(vi), line), Save(I32)); Br(done); End();
    }
    Abort(line, "invalid enum tag"); End();
}

inline void Function::ConstructEnumInto(Node *node, const ConstructionDestination &destination) {
    auto type = destination.location.storage_type;
    auto ei = type->enu->inst;
    auto line = node ? node->line : type->line;
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
    if (ConstructNormalEnumImage(node, destination)) return;
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
        NaturalResults(call).size() == 1 && (Compiler::RegionEnum(NaturalResults(call)[0]) || NaturalResults(call)[0]->kind == TY_VARIANT ||
            (Compiler::RegionEnum(call->exprtype) && Compiler::VariantSource(NaturalResults(call)[0])))) {
        OpenConstruction open(destination);
        EmitCall(call, false, { destination }); code.Op(0x1a); return;
    }
    if (auto inlined = Is<InlineBlock>(node); inlined && inlined->spec &&
        inlined->spec->rets.size() == 1 && (Compiler::RegionEnum(inlined->spec->rets[0]) || inlined->spec->rets[0]->kind == TY_VARIANT ||
            (Compiler::RegionEnum(inlined->exprtype) && Compiler::VariantSource(inlined->spec->rets[0])))) {
        EmitInline(inlined, false, { destination }); code.Op(0x1a); return;
    }
    auto literal = Is<StructLit>(node);
    auto constant = Is<Dot>(node);
    if (!node || literal || (constant && constant->variantconst)) {
        auto variant = literal ? literal->variant : constant ? constant->variantconst : &ei->en->variants[0];
        auto actual = literal ? literal->einst : constant ? constant->einst : ei;
        if (actual != ei || !variant) Fail(line, "owned enum literal has a different instantiation");
        OpenConstruction open(destination);
        auto vi = ei->en->VariantIndex(variant);
        auto vt = c.EnumVariantType(ei, vi, line);
        auto payload = PrepareEnumPayload(destination, vt, line);
        if (Compiler::RegionVariant(vt)) ConstructRecordInto(node, payload);
        else {
            c.FixedLayout(vt);
            LocationAddress(destination.location); auto header = Save(I32);
            auto &fields = ei->vftypes[size_t(vi)];
            for (size_t i = 0; i < fields.size(); i++) {
                auto &definition = ei->en->variants[size_t(vi)].fields[i];
                if (definition.ispad) {
                    CommitImagePadding(header, uint64_t(max<int64_t>(0, definition.padsize)), line); continue;
                }
                auto ft = fields[i]; auto init = literal ? literal->InitFor(int(i)) : nullptr;
                optional<CapturedValue> value;
                if (init) value = CaptureBorrowed(init, ft);
                auto bytes = c.FixedLayout(ft).size;
                code.I64Const(bytes); auto end = ReserveImageBytes(header, Save(I64), line);
                Get(RegionCursor(header));
                if (value) { Get(value->value_local); Store(ft); }
                else { code.I32Const(0); code.I32Const(int32_t(bytes)); code.Fill(); }
                PublishCursor(header, end);
            }
        }
        FinishEnumPayload(destination, vt, line); return;
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
