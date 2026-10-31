#pragma once
namespace goose::direct_wasm {

inline uint32_t Function::RecordImageBase(const Location &owner, Line line) {
    LocationAddress(TailHeaderLocation(owner)); auto header = Save(I32);
    Get(header); code.Mem(0x28, 2, 16); auto tail = Save(I32);
    auto prefix = c.RecordImageLayout(owner.storage_type).size;
    Get(tail); code.I32Const(int32_t(prefix)); code.Op(0x49);
    TrapIf(line, "invalid record image anchor");
    Get(tail); code.I32Const(int32_t(prefix)); code.Op(0x6b); return Save(I32);
}

inline void Function::RecordFieldAddress(TypeExpr *type, size_t field, Line line) {
    if (Compiler::RegionRecord(type) && !Compiler::FrameStruct(type) && field + 1 < c.RecordFields(type).size()) {
        auto control = Save(I32);
        auto base = RecordImageBase({ type, AddressLocal { control } }, line);
        auto offset = c.RecordImageLayout(type).fields.at(field);
        auto bytes = c.FixedLayout(c.RecordFields(type).at(field)).size;
        LocationAddress(TailHeaderLocation({ type, AddressLocal { control } })); auto header = Save(I32);
        Get(base); code.Op(0xad); code.I64Const(uint64_t(offset) + bytes); code.Op(0x7c); auto end = Save(I64);
        Get(end); Get(header); code.Mem(0x28, 2, 8); code.Op(0xad); code.Op(0x56);
        TrapIf(line, "record field exceeds data region");
        Get(end); code.Op(0xa7); EnsureMemory(Save(I32), line);
        Get(base); code.I32Const(int32_t(offset)); code.Op(0x6a); return;
    }
    auto offset = c.FieldOffset(type, field);
    if (offset) { code.I32Const(int32_t(offset)); code.Op(0x6a); }
}

inline void Function::SetRecordImageAnchor(const Location &owner, uint32_t base, Line line) {
    LocationAddress(TailHeaderLocation(owner)); auto header = Save(I32);
    Get(base); code.Op(0xad); code.I64Const(c.RecordImageLayout(owner.storage_type).size); code.Op(0x7c);
    auto tail = Save(I64);
    Get(tail); code.I64Const(UINT32_MAX); code.Op(0x56); TrapIf(line, "record image anchor exceeds wasm32 range");
    Get(tail); code.Op(0xa7); SetArrayImageAnchor(header, Save(I32), c.TailType(owner.storage_type));
}

inline void Function::DecodeRecordImage(const Location &owner, Line line) {
    LocationAddress(TailHeaderLocation(owner)); auto header = Save(I32);
    auto type = c.TailType(owner.storage_type);
    auto prefix = Compiler::RuntimeLimited(type) ? 8u : uint32_t(IntBits(Compiler::LengthStorage(type)) / 8);
    Get(header); code.Mem(0x28, 2, 16); code.Op(0xad); code.I64Const(prefix); code.Op(0x7c); auto end = Save(I64);
    Get(end); Get(header); code.Mem(0x28, 2, 8); code.Op(0xad); code.Op(0x56);
    TrapIf(line, "record image prefix exceeds data region");
    Get(end); code.Op(0xa7); EnsureMemory(Save(I32), line);
    ReadArrayBase(header); auto elements = Save(I32);
    Get(header); Get(elements); code.Mem(0x36, 2);
    ReadArrayLength(header); auto count = Save(I32);
    Get(header); Get(count); code.Mem(0x36, 2, 4);
    if (Compiler::RuntimeLimited(type)) {
        ReadArrayCapacity(header); auto capacity = Save(I32);
        Get(header); Get(capacity); code.Mem(0x36, 2, 12);
    }
    ValidateArrayImage(header, count, type->arr->sub, line);
}

inline uint32_t Function::RecordImageBytes(const Location &owner, Line line) {
    DecodeRecordImage(owner, line);
    auto base = RecordImageBase(owner, line);
    LocationAddress(TailHeaderLocation(owner)); auto header = Save(I32);
    auto tail = c.TailType(owner.storage_type);
    ReadArrayBase(header); code.Op(0xad);
    if (Compiler::RuntimeLimited(tail)) ReadArrayCapacity(header); else ReadArrayLength(header);
    code.Op(0xad); code.I64Const(c.FixedLayout(tail->arr->sub).size); code.Op(0x7e); code.Op(0x7c);
    Get(base); code.Op(0xad); code.Op(0x7d); return Save(I64);
}

inline uint32_t Function::ReserveImageBytes(uint32_t header, uint32_t count, Line line) {
    auto cursor = RegionCursor(header);
    Get(header); code.Mem(0x28, 2, 8); auto limit = Save(I32);
    Get(cursor); Get(limit); code.OpU(0x23, G_REGION_BYTES); code.Op(0x6b); code.Op(0x49);
    Get(cursor); Get(limit); code.Op(0x4b); code.Op(0x72); TrapIf(line, "data region exhausted");
    Get(cursor); code.Op(0xad); Get(count); code.Op(0x7c); auto end = Save(I64);
    Get(end); Get(limit); code.Op(0xad); code.Op(0x56); TrapIf(line, "data region exhausted");
    Get(end); code.Op(0xa7); auto top = Save(I32); EnsureMemory(top, line); return top;
}

inline void Function::ConstructRecordImageLiteral(Node *node, const ConstructionDestination &destination) {
    auto type = destination.location.storage_type;
    auto literal = Is<StructLit>(node);
    auto line = node ? node->line : type->line;
    LocationAddress(TailHeaderLocation(destination.location)); auto header = Save(I32);
    auto &fields = c.RecordFields(type);
    for (size_t i = 0; i < fields.size(); i++) {
        auto init = literal ? literal->InitFor(int(i)) : nullptr;
        if (i + 1 < fields.size()) {
            optional<CapturedValue> value;
            if (init) value = CaptureBorrowed(init, fields[i]);
            auto bytes = c.FixedLayout(fields[i]).size;
            code.I64Const(bytes); auto end = ReserveImageBytes(header, Save(I64), line);
            Get(RegionCursor(header));
            if (value) { Get(value->value_local); Store(fields[i]); }
            else { code.I32Const(0); code.I32Const(int32_t(bytes)); code.Fill(); }
            PublishCursor(header, end); continue;
        }
        auto child = fields[i]; auto layout = c.ControlLayout(child);
        Location producer { child, Slot { Slot::FRAME, FrameBytes(layout.size, layout.align), child } };
        LocationAddress(TailHeaderLocation(producer)); auto control = Save(I32);
        Get(control); code.I32Const(0); code.I32Const(int32_t(owner_control_bytes)); code.Fill();
        Get(control); Get(header); code.Mem(0x28, 2, 8); code.Mem(0x36, 2, 8);
        auto start = RegionCursor(header);
        Get(control); Get(start); code.Mem(0x36, 2);
        if (Compiler::RegionRecord(child)) SetRecordImageAnchor(producer, start, line);
        RegisterEffectOwner(producer);
        private_headers.push_back({ TailHeaderLocation(producer), cleanups.size() });
        ConstructRegionInto(init, { producer, destination.lifetime, false, destination.enum_guard, true, false, {}, destination.construction, destination.open0 });
    }
    DecodeRecordImage(destination.location, line);
}

inline bool Function::ConstructNormalRecordImage(Node *value, const ConstructionDestination &destination) {
    auto type = destination.location.storage_type;
    if (!c.region_cursors || destination.escape_stage || !Compiler::RegionRecord(type) || Compiler::FrameStruct(type) ||
        !destination.normal_result) return false;
    auto line = value ? value->line : type->line;
    auto original_base = RecordImageBase(destination.location, line);
    LocationAddress(TailHeaderLocation(destination.location)); auto original = Save(I32);
    auto start = RegionCursor(original);
    auto layout = c.ControlLayout(type);
    Location stage { type, Slot { Slot::FRAME, FrameBytes(layout.size, layout.align), type } };
    LocationAddress(TailHeaderLocation(stage)); auto header = Save(I32);
    Get(header); code.I32Const(0); code.I32Const(int32_t(owner_control_bytes)); code.Fill();
    Get(header); Get(original); code.Mem(0x28, 2, 8); code.Mem(0x36, 2, 8);
    SetRecordImageAnchor(stage, start, line);
    auto depth = cleanups.size(), private_index = private_headers.size();
    RegisterEffectOwner(stage); private_headers.push_back({ TailHeaderLocation(stage), cleanups.size() });
    auto land = destination.construction->open > destination.open0;
    ConstructRecordInto(value, { stage, ConstructionDestination::Statement, false, destination.enum_guard, true, false, {}, destination.construction, destination.open0 });
    if (land) {
        auto finish = RegionCursor(original);
        Get(finish); code.Op(0xad); Get(start); code.Op(0xad); code.Op(0x7d); auto bytes = Save(I64);
        Get(original_base); code.Op(0xad); Get(bytes); code.Op(0x7c); auto end = Save(I64);
        Get(end); Get(original); code.Mem(0x28, 2, 8); code.Op(0xad); code.Op(0x56); TrapIf(line, "data region exhausted");
        Get(end); code.Op(0xa7); EnsureMemory(Save(I32), line);
        Get(original_base); Get(start); Get(bytes); code.Op(0xa7); code.Copy();
        Get(end); code.Op(0xa7); PublishCursor(original, Save(I32));
    }
    DecodeRecordImage(destination.location, line);
    CloseCleanups(depth); private_headers.erase(private_headers.begin() + private_index); return true;
}

} // namespace goose::direct_wasm
