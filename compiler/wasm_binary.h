// Small, deterministic WebAssembly binary writer. No assembler or C compiler
// participates in the direct backend. All integers in the format use LEB128.
#pragma once

namespace goose::direct_wasm {

enum : uint8_t { I32 = 0x7f, I64 = 0x7e, F32 = 0x7d, F64 = 0x7c, VOID = 0x40 };

struct Bytes {
    string data;
    void Byte(uint8_t x) { data.push_back(static_cast<char>(x)); }
    void U(uint64_t x) {
        do { auto b = uint8_t(x & 127); x >>= 7; Byte(b | (x ? 128 : 0)); } while (x);
    }
    void S(int64_t x) {
        for (;;) {
            auto b = uint8_t(x & 127);
            x >>= 7;
            bool done = (x == 0 && !(b & 64)) || (x == -1 && (b & 64));
            Byte(b | (done ? 0 : 128));
            if (done) return;
        }
    }
    void Raw(string_view s) { data.append(s); }
    void Name(string_view s) { U(s.size()); Raw(s); }
    void Section(uint8_t id, const Bytes &payload) {
        if (payload.data.empty()) return;
        Byte(id); U(payload.data.size()); Raw(payload.data);
    }
    void Op(uint8_t op) { Byte(op); }
    void OpU(uint8_t op, uint32_t arg) { Byte(op); U(arg); }
    void I32Const(int32_t x) { Byte(0x41); S(x); }
    void I64Const(int64_t x) { Byte(0x42); S(x); }
    void F32Const(float x) {
        Byte(0x43); auto bits = bit_cast<uint32_t>(x);
        for (int i = 0; i < 4; i++) Byte(uint8_t(bits >> (i * 8)));
    }
    void F64Const(double x) {
        Byte(0x44); auto bits = bit_cast<uint64_t>(x);
        for (int i = 0; i < 8; i++) Byte(uint8_t(bits >> (i * 8)));
    }
    void Mem(uint8_t op, uint32_t alignment = 0, uint32_t offset = 0) {
        Byte(op); U(alignment); U(offset);
    }
    void Copy() { Byte(0xfc); U(10); U(0); U(0); }
    void Fill() { Byte(0xfc); U(11); U(0); }
};

inline uint64_t BodyHash(string_view s) {
    uint64_t h = UINT64_C(14695981039346656037);
    for (unsigned char c : s) { h ^= c; h *= UINT64_C(1099511628211); }
    return h;
}

} // namespace goose::direct_wasm
