#pragma once
namespace goose::direct_wasm {

inline uint32_t Function::ULEBWidth(uint32_t value) {
    Get(value); auto remaining = Save(I64);
    code.I32Const(1); auto width = Save(I32);
    auto done = Begin(), loop = Begin(0x03);
    Get(remaining); code.I64Const(128); code.Op(0x54); Br(done, true);
    Get(remaining); code.I64Const(7); code.Op(0x88); Set(remaining);
    Get(width); code.I32Const(1); code.Op(0x6a); Set(width); Br(loop); End(); End();
    return width;
}

inline void Function::WriteULEBAt(uint32_t address, uint32_t value) {
    Get(address); auto cursor = Save(I32); Get(value); auto remaining = Save(I64);
    auto done = Begin(), loop = Begin(0x03);
    Get(remaining); code.Op(0xa7); code.I32Const(127); code.Op(0x71); auto byte = Save(I32);
    Get(remaining); code.I64Const(7); code.Op(0x88); Set(remaining);
    Get(remaining); code.I64Const(0); code.Op(0x52); Begin(0x04);
    Get(byte); code.I32Const(128); code.Op(0x72); Set(byte); End();
    Get(cursor); Get(byte); code.Mem(0x3a);
    Get(cursor); code.I32Const(1); code.Op(0x6a); Set(cursor);
    Get(remaining); code.Op(0x50); Br(done, true); Br(loop); End(); End();
}

inline pair<uint32_t, uint32_t> Function::ReadULEBArray(uint32_t header, Line line) {
    Get(header); code.Mem(0x28, 2, 16); auto image = Save(I32);
    Get(header); code.Mem(0x28, 2, 8); code.Op(0xad); auto limit = Save(I64);
    Get(image); code.Op(0xad); code.I64Const(10); code.Op(0x7c); auto mapped = Save(I64);
    Get(mapped); Get(limit); code.Op(0x56); Begin(0x04); Get(limit); Set(mapped); End();
    Get(mapped); code.Op(0xa7); EnsureMemory(Save(I32), line);
    auto decoded = ReadULEB(image, limit, line);
    Get(decoded.first); code.I64Const(UINT32_MAX); code.Op(0x56);
    TrapIf(line, "array image length exceeds wasm32 range");
    Get(decoded.first); code.Op(0xa7); return { Save(I32), decoded.second };
}

inline void Function::ReserveULEBArrayPrefix(uint32_t header, uint32_t width, Line line) {
    auto image = RegionCursor(header);
    Get(width); code.Op(0xad); auto end = ReserveImageBytes(header, Save(I64), line);
    Get(header); Get(image); code.Mem(0x36, 2, 16);
    Get(header); Get(end); code.Mem(0x36, 2);
    Get(header); Get(width); code.Mem(0x36, 2, 12);
    Get(header); code.I32Const(int32_t(ArrayStorageMode::VarULEB)); code.Mem(0x36, 2, 20);
    Get(header); code.I32Const(0); code.Mem(0x36, 2, 4);
    PublishCursor(header, end); // Unknown reservations deliberately write no data.
}

inline void Function::InitializeKnownArrayImage(uint32_t header, const ConstructionDestination &destination,
        uint32_t count, Line line) {
    if (!Compiler::ULEBLength(destination.location.storage_type) || destination.elements) {
        InitializeArrayImage(header, destination, line); return;
    }
    auto width = ULEBWidth(count); ReserveULEBArrayPrefix(header, width, line);
    Get(header); code.Mem(0x28, 2, 16); WriteULEBAt(Save(I32), count);
    Get(header); Get(count); code.Op(0xa7); code.Mem(0x36, 2, 4);
}

inline void Function::PatchULEBArrayLength(uint32_t header, uint32_t count, Line line) {
    Get(count); code.Op(0xad); auto value = Save(I64); auto width = ULEBWidth(value);
    Get(header); code.Mem(0x28, 2, 12); auto old_width = Save(I32);
    Get(old_width); code.I32Const(1); code.Op(0x49);
    Get(old_width); code.I32Const(10); code.Op(0x4b); code.Op(0x72);
    TrapIf(line, "invalid ULEB construction prefix");
    Get(header); code.Mem(0x28, 2, 16); auto image = Save(I32);
    Get(image); Get(old_width); code.Op(0x6a); auto elements = Save(I32);
    auto finish = RegionCursor(header);
    Get(finish); Get(elements); code.Op(0x49); TrapIf(line, "invalid ULEB construction suffix");
    Get(finish); code.Op(0xad); Get(width); code.Op(0xad); code.Op(0x7c);
    Get(old_width); code.Op(0xad); code.Op(0x7d); auto end = Save(I64);
    Get(end); Get(header); code.Mem(0x28, 2, 8); code.Op(0xad); code.Op(0x56);
    TrapIf(line, "data region exhausted");
    Get(end); code.Op(0xa7); auto top = Save(I32); EnsureMemory(top, line);
    Get(image); Get(width); code.Op(0x6a); auto target = Save(I32);
    Get(target); Get(elements); Get(finish); Get(elements); code.Op(0x6b); code.Copy();
    WriteULEBAt(image, value);
    Get(header); Get(target); code.Mem(0x36, 2);
    // Keep the original reservation width: repeated named Grow returns patch
    // again from that original one-byte reservation, as the native producer does.
    PublishCursor(header, top);
}

} // namespace goose::direct_wasm
