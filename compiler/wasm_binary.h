// Small, deterministic WebAssembly binary writer. No assembler or C compiler
// participates in the direct backend. All integers in the format use LEB128.
#pragma once

namespace goose::direct_wasm {

enum : uint8_t { I32 = 0x7f, I64 = 0x7e, F32 = 0x7d, F64 = 0x7c, V128 = 0x7b, VOID = 0x40 };

struct Bytes {
    string data;
    struct LocalOp { size_t start, end; uint32_t index; uint8_t op; };
    vector<LocalOp> local_ops;
    bool opaque = false;
    size_t local_set_at = 0, local_set_end = 0;
    uint32_t local_set_index = 0;
    void Byte(uint8_t x) { local_set_end = 0; data.push_back(static_cast<char>(x)); }
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
    void Raw(string_view s) { local_set_end = 0; opaque = true; data.append(s); }
    void Append(const Bytes &other) {
        local_set_end = 0;
        auto offset = data.size();
        data.append(other.data);
        opaque |= other.opaque;
        for (auto op : other.local_ops)
            local_ops.push_back({ offset + op.start, offset + op.end, op.index, op.op });
    }
    void Name(string_view s) { U(s.size()); Raw(s); }
    void Section(uint8_t id, const Bytes &payload) {
        if (payload.data.empty()) return;
        Byte(id); U(payload.data.size()); Raw(payload.data);
    }
    void Op(uint8_t op) { Byte(op); }
    void OpU(uint8_t op, uint32_t arg) {
        // Only complete instructions qualify: raw data and immediates can
        // contain the same bytes as local.set. Moving/clearing data is a barrier.
        if (op == 0x20 && local_set_end && local_set_end == data.size() && local_set_index == arg) {
            data[local_set_at] = 0x22;
            local_ops.back().op = 0x22;
            local_set_end = 0;
            return;
        }
        auto start = data.size();
        Byte(op); U(arg);
        if (op == 0x21) {
            local_set_at = start;
            local_set_end = data.size();
            local_set_index = arg;
        }
        if (op >= 0x20 && op <= 0x22) local_ops.push_back({ start, data.size(), arg, op });
    }
    // Called only after the whole function, including prologue and results,
    // is assembled. Unread tees disappear and unread sets become consuming drops;
    // only declared locals with ordinary reads need storage. Parameters stay put.
    bool CompactLocals(size_t parameter_count, vector<uint8_t> &locals) {
        if (opaque) return true;
        if (parameter_count > UINT32_MAX || locals.size() > UINT32_MAX - parameter_count) return false;
        auto count = parameter_count + locals.size();
        size_t end = 0;
        for (auto op : local_ops) {
            if (op.start < end || op.start >= op.end || op.end > data.size() ||
                op.end - op.start < 2 || op.index >= count || op.op < 0x20 || op.op > 0x22 ||
                uint8_t(data[op.start]) != op.op) return false;
            end = op.end;
        }
        vector<bool> read(count);
        for (auto op : local_ops) if (op.op == 0x20) read[op.index] = true;
        vector<uint32_t> remap(count);
        for (size_t i = 0; i < parameter_count; i++) remap[i] = uint32_t(i);
        vector<uint8_t> kept_locals;
        for (size_t i = 0; i < locals.size(); i++) if (read[parameter_count + i]) {
            remap[parameter_count + i] = uint32_t(parameter_count + kept_locals.size());
            kept_locals.push_back(locals[i]);
        }
        Bytes kept;
        kept.data.reserve(data.size());
        size_t start = 0;
        for (auto op : local_ops) {
            kept.data.append(data, start, op.start - start);
            if (read[op.index]) {
                auto at = kept.data.size();
                kept.Byte(op.op); kept.U(remap[op.index]);
                kept.local_ops.push_back({ at, kept.data.size(), remap[op.index], op.op });
            } else if (op.op == 0x21) kept.Op(0x1a);
            start = op.end;
        }
        kept.data.append(data, start, string::npos);
        *this = std::move(kept);
        locals = std::move(kept_locals);
        return true;
    }
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

struct DataSegment { uint32_t offset; string_view bytes; };

// Defined Wasm memory starts zeroed. Keep logical allocations and addresses
// intact, but serialize only initialized spans. Short zero gaps cost less than
// another active segment; cap fragmentation to bound engine startup overhead.
inline vector<DataSegment> SparseDataSegments(string_view data, uint32_t base) {
    vector<DataSegment> segments;
    size_t pos = 0;
    while ((pos = data.find_first_not_of('\0', pos)) != string_view::npos) {
        auto start = pos, end = pos + 1;
        if (segments.size() == 1023) {
            end = data.find_last_not_of('\0') + 1;
            segments.push_back({ base + uint32_t(start), data.substr(start, end - start) });
            break;
        }
        for (pos = end; pos < data.size(); pos++) {
            if (data[pos]) end = pos + 1;
            else if (pos - end >= 16) break;
        }
        segments.push_back({ base + uint32_t(start), data.substr(start, end - start) });
    }
    return segments;
}

struct OwnedDataSegment { uint32_t offset; string bytes; };

// Fragments borrow interned text. Reservations between them consume no host
// memory; materialize zero gaps only when serialization joins two spans.
inline vector<OwnedDataSegment> SparseDataSegments(const vector<DataSegment> &fragments) {
    vector<OwnedDataSegment> segments;
    for (auto &fragment : fragments) {
        for (auto &span : SparseDataSegments(fragment.bytes, fragment.offset)) {
            if (!segments.empty()) {
                auto &last = segments.back();
                auto end = uint64_t(last.offset) + last.bytes.size();
                auto gap = uint64_t(span.offset) - end;
                if (gap <= 16 || segments.size() == 1024) {
                    last.bytes.append(size_t(gap), '\0');
                    last.bytes.append(span.bytes);
                    continue;
                }
            }
            segments.push_back({ span.offset, string(span.bytes) });
        }
    }
    return segments;
}

} // namespace goose::direct_wasm
