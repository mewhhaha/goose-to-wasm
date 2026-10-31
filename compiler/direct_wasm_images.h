#pragma once
namespace goose::direct_wasm {

// Controls describe the physical form. An element-run specialization can have
// a Var natural type while receiving raw storage, so TypeExpr alone is not a
// sufficient recipe for reading its result.
inline void Function::ReadArrayBase(uint32_t header) {
    Get(header); code.Mem(0x28, 2, 20); auto mode = Save(I32);
    auto result = Local(I32); Get(header); code.Mem(0x28, 2); Set(result);
    for (auto [kind, width] : vector<pair<ArrayStorageMode, uint32_t>> {
        { ArrayStorageMode::VarU8, 1 }, { ArrayStorageMode::VarU16, 2 },
        { ArrayStorageMode::VarU32, 4 }, { ArrayStorageMode::VarU64, 8 },
        { ArrayStorageMode::RuntimeLimited, 8 } }) {
        Get(mode); code.I32Const(int32_t(kind)); code.Op(0x46); Begin(0x04);
        Get(header); code.Mem(0x28, 2, 16); code.I32Const(int32_t(width)); code.Op(0x6a); Set(result); End();
    }
    Get(result);
}

inline void Function::ValidateArrayImage(uint32_t header, uint32_t count, TypeExpr *element, Line line) {
    Get(header); code.Mem(0x28, 2, 20); Begin(0x04);
    ReadArrayBase(header); auto base = Save(I32);
    Get(base); Get(header); code.Mem(0x28, 2, 8); code.Op(0x4b);
    TrapIf(line, "array image exceeds data region");
    Get(count); code.Op(0xad); code.I64Const(c.FixedLayout(element).size); code.Op(0x7e);
    Get(header); code.Mem(0x28, 2, 8); code.Op(0xad); Get(base); code.Op(0xad); code.Op(0x7d);
    code.Op(0x56); TrapIf(line, "array image exceeds data region");
    Get(header); code.Mem(0x28, 2, 20); code.I32Const(int32_t(ArrayStorageMode::RuntimeLimited)); code.Op(0x46);
    Begin(0x04);
    ReadArrayCapacity(header); auto cap = Save(I32);
    Get(count); Get(cap); code.Op(0x4b); TrapIf(line, "array image length exceeds capacity");
    Get(cap); code.Op(0xad); code.I64Const(c.FixedLayout(element).size); code.Op(0x7e);
    Get(header); code.Mem(0x28, 2, 8); code.Op(0xad); Get(base); code.Op(0xad); code.Op(0x7d);
    code.Op(0x56); TrapIf(line, "array image capacity exceeds data region"); End(); End();
}

inline void Function::ReadArrayLength(uint32_t header) {
    Get(header); code.Mem(0x28, 2, 20); auto mode = Save(I32);
    auto result = Local(I32);
    Get(header); code.Mem(0x28, 2, 4); Set(result);
    for (auto [kind, opcode, offset] : vector<tuple<ArrayStorageMode, uint8_t, uint32_t>> {
        { ArrayStorageMode::VarU8, 0x2d, 0 }, { ArrayStorageMode::VarU16, 0x2f, 0 },
        { ArrayStorageMode::VarU32, 0x28, 0 }, { ArrayStorageMode::VarU64, 0x29, 0 },
        { ArrayStorageMode::RuntimeLimited, 0x28, 4 } }) {
        Get(mode); code.I32Const(int32_t(kind)); code.Op(0x46); Begin(0x04);
        Get(header); code.Mem(0x28, 2, 16); code.Mem(opcode, 0, offset);
        if (kind == ArrayStorageMode::VarU64) {
            auto count = Save(I64); Get(count); code.I64Const(UINT32_MAX); code.Op(0x56);
            TrapIf({}, "array image length exceeds wasm32 range"); Get(count); code.Op(0xa7);
        }
        Set(result); End();
    }
    Get(result);
}

inline void Function::ReadArrayCapacity(uint32_t header) {
    Get(header); code.Mem(0x28, 2, 20); code.I32Const(int32_t(ArrayStorageMode::RuntimeLimited)); code.Op(0x46);
    Begin(0x04, I32);
    Get(header); code.Mem(0x28, 2, 16); code.Mem(0x28, 0);
    Else(); Get(header); code.Mem(0x28, 2, 12); End();
}

inline void Function::WriteArrayLength(uint32_t header, uint32_t count) {
    Get(header); Get(count); code.Mem(0x36, 2, 4);
    Get(header); code.Mem(0x28, 2, 20); auto mode = Save(I32);
    for (auto [kind, opcode, offset] : vector<tuple<ArrayStorageMode, uint8_t, uint32_t>> {
        { ArrayStorageMode::VarU8, 0x3a, 0 }, { ArrayStorageMode::VarU16, 0x3b, 0 },
        { ArrayStorageMode::VarU32, 0x36, 0 }, { ArrayStorageMode::VarU64, 0x37, 0 },
        { ArrayStorageMode::RuntimeLimited, 0x36, 4 } }) {
        Get(mode); code.I32Const(int32_t(kind)); code.Op(0x46); Begin(0x04);
        Get(header); code.Mem(0x28, 2, 16); Get(count);
        if (kind == ArrayStorageMode::VarU64) code.Op(0xad);
        code.Mem(opcode, 0, offset); End();
    }
    PublishHeader(header, 4);
}

inline void Function::WriteArrayCapacity(uint32_t header, uint32_t count) {
    Get(header); Get(count); code.Mem(0x36, 2, 12);
    Get(header); code.Mem(0x28, 2, 20); code.I32Const(int32_t(ArrayStorageMode::RuntimeLimited)); code.Op(0x46);
    Begin(0x04); Get(header); code.Mem(0x28, 2, 16); Get(count); code.Mem(0x36, 0); End();
}

inline void Function::InitializeArrayImage(uint32_t header, const ConstructionDestination &destination, Line line) {
    auto type = destination.location.storage_type;
    ArrayStorageMode mode = ArrayStorageMode::RawElements;
    uint32_t prefix = 0;
    if (Compiler::RuntimeLimited(type)) { mode = ArrayStorageMode::RuntimeLimited; prefix = 8; }
    else if (type->arr->akind == A_VAR && !destination.elements) {
        auto bits = IntBits(Compiler::LengthStorage(type)); prefix = uint32_t(bits / 8);
        mode = bits == 8 ? ArrayStorageMode::VarU8 : bits == 16 ? ArrayStorageMode::VarU16 :
               bits == 32 ? ArrayStorageMode::VarU32 : ArrayStorageMode::VarU64;
    }
    // An existing limited receiver retains its prefix and pinned capacity.
    if (Compiler::RuntimeLimited(type) && destination.lifetime == ConstructionDestination::Existing) return;
    Get(header); code.I32Const(int32_t(mode)); code.Mem(0x36, 2, 20);
    if (!prefix) { Get(header); code.I32Const(0); code.Mem(0x36, 2, 16); return; }
    Get(header); code.Mem(0x28, 2); auto image = Save(I32);
    // A private raw stage starts at the committed cursor; ordinary receivers
    // start at their current value base. Prefix reservation precedes elements.
    if (c.region_cursors) { image = RegionCursor(header); }
    Get(image); code.Op(0xad); code.I64Const(prefix); code.Op(0x7c);
    Get(header); code.Mem(0x28, 2, 8); code.Op(0xad); code.Op(0x56); TrapIf(line, "data region exhausted");
    Get(image); code.I32Const(int32_t(prefix)); code.Op(0x6a); auto elements = Save(I32);
    EnsureMemory(elements, line);
    Get(header); Get(image); code.Mem(0x36, 2, 16);
    Get(header); Get(elements); code.Mem(0x36, 2);
    Get(image); code.I32Const(0); code.I32Const(int32_t(prefix)); code.Fill();
    PublishCursor(header, elements);
}

inline ConstructionDestination Function::RawArrayReceiver(const ConstructionDestination &destination, Line line) {
    LocationAddress(destination.location); auto receiving = Save(I32);
    InitializeArrayImage(receiving, destination, line);
    auto layout = c.ControlLayout(destination.location.storage_type);
    Location adapter { destination.location.storage_type, Slot { Slot::FRAME, FrameBytes(layout.size, layout.align), destination.location.storage_type } };
    LocationAddress(adapter); auto raw = Save(I32);
    Get(raw); Get(receiving); code.I32Const(int32_t(layout.size)); code.Copy();
    Get(raw); code.I32Const(0); code.Mem(0x36, 2, 16);
    Get(raw); code.I32Const(0); code.Mem(0x36, 2, 20);
    auto result = destination; result.location = adapter; result.elements = true;
    return result;
}

inline void Function::FinishRawArrayReceiver(const ConstructionDestination &source, const ConstructionDestination &destination, Line line) {
    LocationAddress(source.location); auto raw = Save(I32);
    ReadArrayLength(raw); code.Op(0xad); auto count = Save(I64);
    CheckArrayLength(destination.location.storage_type, count, line, destination.elements);
    LocationAddress(destination.location); auto header = Save(I32);
    Get(count); code.Op(0xa7); WriteArrayLength(header, Save(I32));
}

inline ConstructionDestination Function::ValueArrayReceiver(const ConstructionDestination &destination, TypeExpr *natural) {
    auto layout = c.ControlLayout(natural);
    Location adapter { natural, Slot { Slot::FRAME, FrameBytes(layout.size, layout.align), natural } };
    LocationAddress(destination.location); auto receiving = Save(I32);
    LocationAddress(adapter); auto value = Save(I32);
    Get(value); Get(receiving); code.I32Const(int32_t(layout.size)); code.Copy();
    Get(value); Get(RegionCursor(receiving)); code.Mem(0x36, 2);
    for (auto offset : { 4u, 12u, 16u, 20u }) { Get(value); code.I32Const(0); code.Mem(0x36, 2, offset); }
    auto result = destination; result.location = adapter; result.elements = false;
    code.I32Const(0); result.publication = Save(I32);
    return result;
}

inline void Function::FinishValueArrayReceiver(const ConstructionDestination &source,
        const ConstructionDestination &destination, Line line) {
    LocationAddress(source.location); auto value = Save(I32);
    LocationAddress(destination.location); auto receiving = Save(I32);
    ReadArrayLength(value); auto count = Save(I32);
    Get(count); code.Op(0xad); CheckArrayLength(destination.location.storage_type, Save(I64), line, destination.elements);
    Get(value); code.Mem(0x28, 2, 16); auto anchor = Save(I32);
    ReadArrayBase(value); auto elements = Save(I32);
    auto finish = RegionCursor(value);
    Get(elements); Get(finish); code.Op(0x4b); TrapIf(line, "invalid array image adaptation span");
    Get(finish); Get(elements); code.Op(0x6b); auto bytes = Save(I32);
    auto target = destination.location.storage_type;
    auto prefix = target->arr->akind == A_VAR && !destination.elements ? uint32_t(IntBits(Compiler::LengthStorage(target)) / 8) : 0u;
    Get(anchor); code.Op(0xad); code.I64Const(prefix); code.Op(0x7c); Get(bytes); code.Op(0xad); code.Op(0x7c);
    auto end = Save(I64);
    Get(end); Get(receiving); code.Mem(0x28, 2, 8); code.Op(0xad); code.Op(0x56); TrapIf(line, "data region exhausted");
    Get(end); code.Op(0xa7); EnsureMemory(Save(I32), line);
    Get(anchor); code.I32Const(int32_t(prefix)); code.Op(0x6a); auto target_elements = Save(I32);
    Get(target_elements); Get(elements); Get(bytes); code.Copy();
    if (prefix) {
        Get(receiving); Get(anchor); code.Mem(0x36, 2, 16);
        Get(receiving); Get(target_elements); code.Mem(0x36, 2);
        auto mode = prefix == 1 ? ArrayStorageMode::VarU8 : prefix == 2 ? ArrayStorageMode::VarU16 :
                    prefix == 4 ? ArrayStorageMode::VarU32 : ArrayStorageMode::VarU64;
        Get(receiving); code.I32Const(int32_t(mode)); code.Mem(0x36, 2, 20);
    } else {
        Get(receiving); code.I32Const(0); code.Mem(0x36, 2, 16);
        Get(receiving); code.I32Const(0); code.Mem(0x36, 2, 20);
    }
    WriteArrayLength(receiving, count);
    Get(end); code.Op(0xa7); PublishCursor(receiving, Save(I32));
}

// The receiving anchor and the start of this attempt are distinct. A suffix
// may begin with a canceled prefix or argument bytes. Landing copies all of it
// and then reads the receiving image; it never repairs that prefix from a
// successful producer's private count.
inline void Function::FinishArrayImage(uint32_t original, uint32_t start, uint32_t stage,
        TypeExpr *type, bool land, Line line) {
    if (land) {
        auto anchor = Local(I32);
        Get(original); code.Mem(0x28, 2, 20); Begin(0x04, I32);
        Get(original); code.Mem(0x28, 2, 16);
        Else(); Get(original); code.Mem(0x28, 2); End(); Set(anchor);
        auto finish = RegionCursor(original);
        Get(start); Get(anchor); code.Op(0x49);
        Get(start); Get(finish); code.Op(0x4b); code.Op(0x72);
        Get(finish); Get(original); code.Mem(0x28, 2, 8); code.Op(0x4b); code.Op(0x72);
        TrapIf(line, "invalid array image landing span");
        Get(finish); Get(start); code.Op(0x6b); auto bytes = Save(I32);
        Get(anchor); Get(start); Get(bytes); code.Copy();
        Get(original); Get(stage); code.Mem(0x28, 2, 20); code.Mem(0x36, 2, 20);
        Get(original); Get(anchor); code.Mem(0x36, 2, 16);
        Get(anchor); Get(bytes); code.Op(0x6a); PublishCursor(original, Save(I32));
    } else {
        // The first construction establishes the anchor. A later normal
        // return with no open construction leaves the original one intact.
        Get(original); code.Mem(0x28, 2, 20); code.Op(0x45); Begin(0x04);
        for (auto offset : { 0u, 4u, 12u, 16u, 20u }) {
            Get(original); Get(stage); code.Mem(0x28, 2, offset); code.Mem(0x36, 2, offset);
        }
        End();
    }
    ReadArrayBase(original); auto elements = Save(I32);
    Get(original); Get(elements); code.Mem(0x36, 2);
    ReadArrayLength(original); auto count = Save(I32);
    Get(original); Get(count); code.Mem(0x36, 2, 4);
    if (Compiler::RuntimeLimited(type)) {
        ReadArrayCapacity(original); auto capacity = Save(I32);
        Get(original); Get(capacity); code.Mem(0x36, 2, 12);
    }
    ValidateArrayImage(original, count, type->arr->sub, line);
}

inline void Function::SetArrayImageAnchor(uint32_t header, uint32_t anchor, TypeExpr *type) {
    auto prefix = Compiler::RuntimeLimited(type) ? 8u : uint32_t(IntBits(Compiler::LengthStorage(type)) / 8);
    auto mode = Compiler::RuntimeLimited(type) ? ArrayStorageMode::RuntimeLimited :
                prefix == 1 ? ArrayStorageMode::VarU8 : prefix == 2 ? ArrayStorageMode::VarU16 :
                prefix == 4 ? ArrayStorageMode::VarU32 : ArrayStorageMode::VarU64;
    Get(header); Get(anchor); code.Mem(0x36, 2, 16);
    Get(header); code.I32Const(int32_t(mode)); code.Mem(0x36, 2, 20);
    Get(header); Get(anchor); code.I32Const(int32_t(prefix)); code.Op(0x6a); code.Mem(0x36, 2);
    Get(header); code.I32Const(0); code.Mem(0x36, 2, 4);
    Get(header); code.I32Const(0); code.Mem(0x36, 2, 12);
}

inline void Function::LandArrayImage(uint32_t original, uint32_t start, uint32_t entry, TypeExpr *type, Line line) {
    auto finish = RegionCursor(original);
    Get(original); code.Mem(0x28, 2, 8); auto limit = Save(I32);
    Get(limit); code.OpU(0x23, G_REGION_BYTES); code.Op(0x6b); auto region_base = Save(I32);
    Get(start); Get(region_base); code.Op(0x49);
    Get(entry); Get(region_base); code.Op(0x49); code.Op(0x72);
    Get(start); Get(finish); code.Op(0x4b); code.Op(0x72);
    Get(finish); Get(limit); code.Op(0x4b); code.Op(0x72);
    TrapIf(line, "invalid nonlocal array image span");
    Get(finish); code.Op(0xad); Get(start); code.Op(0xad); code.Op(0x7d); auto bytes = Save(I64);
    Get(entry); code.Op(0xad); Get(bytes); code.Op(0x7c); auto end = Save(I64);
    Get(end); Get(limit); code.Op(0xad); code.Op(0x56); TrapIf(line, "data region exhausted");
    Get(end); code.Op(0xa7); EnsureMemory(Save(I32), line);
    Get(entry); Get(start); Get(bytes); code.Op(0xa7); code.Copy();
    SetArrayImageAnchor(original, entry, type);
    ReadArrayLength(original); auto count = Save(I32);
    Get(original); Get(count); code.Mem(0x36, 2, 4);
    if (Compiler::RuntimeLimited(type)) {
        ReadArrayCapacity(original); auto capacity = Save(I32);
        Get(original); Get(capacity); code.Mem(0x36, 2, 12);
    }
    // A canceled prefix may describe more than the committed suffix. Native
    // views retain that prefix; validate against the region, not suffix size.
    ValidateArrayImage(original, count, type->arr->sub, line);
    Get(end); code.Op(0xa7); PublishCursor(original, Save(I32));
}

} // namespace goose::direct_wasm
