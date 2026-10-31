#pragma once
namespace goose::direct_wasm {

// Encoded storage and decoded values have different types and extents. The
// reader returns an i64 value and the address immediately after its byte image.
inline pair<uint32_t, uint32_t> Function::ReadVarint(uint32_t address, uint32_t limit, Line line) {
    Get(address); auto cursor = Save(I32);
    code.I64Const(0); auto value = Save(I64);
    code.I32Const(0); auto shift = Save(I32);
    auto done = Begin(), loop = Begin(0x03);
    Get(cursor); code.Op(0xad); Get(limit); code.Op(0x5a); TrapIf(line, "truncated varint image");
    Get(cursor); code.Mem(0x2d); auto byte = Save(I32);
    Get(shift); code.I32Const(63); code.Op(0x46);
    Get(byte); code.I32Const(0xfe); code.Op(0x71); code.I32Const(0); code.Op(0x47); code.Op(0x71);
    TrapIf(line, "varint image exceeds 64 bits");
    Get(value); Get(byte); code.I32Const(0x7f); code.Op(0x71); code.Op(0xad);
    Get(shift); code.Op(0xad); code.Op(0x86); code.Op(0x84); Set(value);
    Get(cursor); code.I32Const(1); code.Op(0x6a); Set(cursor);
    Get(byte); code.I32Const(0x80); code.Op(0x71); code.Op(0x45); Br(done, true);
    Get(shift); code.I32Const(7); code.Op(0x6a); Set(shift); Br(loop);
    End(); End();
    Get(value); code.I64Const(1); code.Op(0x88);
    code.I64Const(0); Get(value); code.I64Const(1); code.Op(0x83); code.Op(0x7d); code.Op(0x85);
    return { Save(I64), cursor };
}

inline void Function::AppendVarint(uint32_t header, uint32_t value, Line line) {
    Get(value); code.I64Const(1); code.Op(0x86);
    Get(value); code.I64Const(63); code.Op(0x87); code.Op(0x85); auto encoded = Save(I64);
    Get(encoded); auto remaining = Save(I64);
    code.I64Const(1); auto width = Save(I64);
    auto done = Begin(), size_loop = Begin(0x03);
    Get(remaining); code.I64Const(128); code.Op(0x54); Br(done, true);
    Get(remaining); code.I64Const(7); code.Op(0x88); Set(remaining);
    Get(width); code.I64Const(1); code.Op(0x7c); Set(width); Br(size_loop);
    End(); End();
    auto end = ReserveImageBytes(header, width, line);
    auto cursor = RegionCursor(header);
    Get(encoded); Set(remaining);
    done = Begin(); auto write_loop = Begin(0x03);
    Get(remaining); code.Op(0xa7); code.I32Const(0x7f); code.Op(0x71); auto byte = Save(I32);
    Get(remaining); code.I64Const(7); code.Op(0x88); Set(remaining);
    Get(remaining); code.I64Const(0); code.Op(0x52); Begin(0x04);
    Get(byte); code.I32Const(0x80); code.Op(0x72); Set(byte); End();
    Get(cursor); Get(byte); code.Mem(0x3a);
    Get(cursor); code.I32Const(1); code.Op(0x6a); Set(cursor);
    Get(remaining); code.Op(0x50); Br(done, true); Br(write_loop);
    End(); End(); PublishCursor(header, end);
}

inline uint32_t Function::WalkByteRecord(const Location &owner, optional<size_t> field, Line line) {
    LocationAddress(owner); auto header = Save(I32);
    auto cursor = RecordImageBase(owner, line);
    Get(header); code.Mem(0x28, 2, 8); code.Op(0xad); auto limit = Save(I64);
    Get(cursor); code.Op(0xad); Get(limit); code.OpU(0x23, G_REGION_BYTES); code.Op(0xad); code.Op(0x7d); code.Op(0x54);
    TrapIf(line, "invalid byte-record image anchor");
    auto &types = c.RecordFields(owner.storage_type);
    auto &definitions = c.RecordFieldDefs(owner.storage_type);
    for (size_t i = 0; i < types.size(); i++) {
        Get(cursor); auto start = Save(I32);
        if (Compiler::Varint(types[i])) {
            // Before any loads, map at most ten bytes within this region. A
            // sparse image can map bytes without advancing its physical cursor.
            Get(cursor); code.Op(0xad); code.I64Const(10); code.Op(0x7c); auto mapped = Save(I64);
            Get(mapped); Get(limit); code.Op(0x56); Begin(0x04); Get(limit); Set(mapped); End();
            Get(mapped); code.Op(0xa7); EnsureMemory(Save(I32), line);
            auto decoded = ReadVarint(start, limit, line); Get(decoded.second); Set(cursor);
        } else {
            auto bytes = definitions[i].ispad ? uint64_t(max<int64_t>(0, definitions[i].padsize)) : c.FixedLayout(types[i]).size;
            Get(cursor); code.Op(0xad); code.I64Const(int64_t(bytes)); code.Op(0x7c); auto end = Save(I64);
            Get(end); Get(limit); code.Op(0x56); TrapIf(line, "byte-record field exceeds data region");
            Get(end); code.Op(0xa7); auto top = Save(I32); EnsureMemory(top, line); Get(top); Set(cursor);
        }
        if (field && *field == i) return start;
    }
    return cursor;
}

} // namespace goose::direct_wasm
