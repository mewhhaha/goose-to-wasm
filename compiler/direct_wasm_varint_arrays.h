#pragma once
namespace goose::direct_wasm {

inline void Function::CheckNamedVarintReturns(Block *body, SFunction *target, size_t arity,
        size_t ordinal, const VarDef *candidate, string_view kind) {
    function<void(Node *)> validate = [&](Node *node) {
        if (!node) return;
        if (auto ret = Is<Return>(node); ret && ret->target == target && ret->vals.size() == arity) {
            auto id = Is<Ident>(ret->vals[ordinal]);
            if (!id || id->vdef != candidate)
                for (size_t j = ordinal + 1; j < ret->vals.size(); j++) {
                    if (goose::MayReachLocal(ret->vals[j], candidate))
                        Fail(ret->line, "observing a named varint " + string(kind) + " after replacement requires a bounded overlap proof");
                    function<void(Node *)> no_opaque_read = [&](Node *part) {
                        if (!part) return;
                        if (auto call = Is<Call>(part); call && call->builtin < 0 && !call->fvbody)
                            Fail(part->line, "calls after named varint " + string(kind) + " replacement require a bounded overlap proof");
                        RunChildren(part, no_opaque_read);
                    };
                    no_opaque_read(ret->vals[j]);
                }
        }
        RunChildren(node, validate);
    };
    validate(body);
}

// Views contain an encoded address and element count, with no fixed stride.
// Data-region bounds also apply to sparse images. Scratch snapshots are already
// mapped and use the current memory bound instead.
inline uint32_t Function::EncodedReadLimit(uint32_t address) {
    code.OpU(0x3f, 0); code.Op(0xad); code.I64Const(65536); code.Op(0x7e); auto limit = Save(I64);
    if (c.needs_regions) {
        Get(address); code.OpU(0x23, G_REGION_BASE); code.Op(0x4f);
        Get(address); code.Op(0xad); code.OpU(0x23, G_REGION_BASE); code.Op(0xad);
        code.OpU(0x23, G_REGION_BYTES); code.Op(0xad); code.OpU(0x23, G_REGION_COUNT); code.Op(0xad);
        code.Op(0x7e); code.Op(0x7c); code.Op(0x54); code.Op(0x71); Begin(0x04);
        Get(address); code.OpU(0x23, G_REGION_BASE); code.Op(0x6b);
        code.OpU(0x23, G_REGION_BYTES); code.Op(0x6e); code.I32Const(1); code.Op(0x6a);
        code.Op(0xad); code.OpU(0x23, G_REGION_BYTES); code.Op(0xad); code.Op(0x7e);
        code.OpU(0x23, G_REGION_BASE); code.Op(0xad); code.Op(0x7c); Set(limit); End();
    }
    return limit;
}

inline pair<uint32_t, uint32_t> Function::ReadVarintElement(uint32_t address, uint32_t limit, Line line) {
    Get(address); code.Op(0xad); code.I64Const(10); code.Op(0x7c); auto mapped = Save(I64);
    Get(mapped); Get(limit); code.Op(0x56); Begin(0x04); Get(limit); Set(mapped); End();
    Get(mapped); code.Op(0xa7); EnsureMemory(Save(I32), line);
    return ReadVarint(address, limit, line);
}

inline uint32_t Function::WalkVarintElements(uint32_t base, uint32_t count, uint32_t limit, Line line) {
    Get(base); auto cursor = Save(I32);
    code.I64Const(0); auto index = Save(I64);
    auto done = Begin(), loop = Begin(0x03);
    Get(index); Get(count); code.Op(0x5a); Br(done, true);
    auto element = ReadVarintElement(cursor, limit, line); Get(element.second); Set(cursor);
    Get(index); code.I64Const(1); code.Op(0x7c); Set(index); Br(loop); End(); End();
    return cursor;
}

inline void Function::CopyVarintElements(uint32_t header, uint32_t base, uint32_t count, Line line) {
    Get(base); auto cursor = Save(I32); auto limit = EncodedReadLimit(base);
    code.I64Const(0); auto index = Save(I64);
    auto done = Begin(), loop = Begin(0x03);
    Get(index); Get(count); code.Op(0x5a); Br(done, true);
    auto element = ReadVarintElement(cursor, limit, line);
    Get(element.second); code.Op(0xad); Get(cursor); code.Op(0xad); code.Op(0x7d); auto bytes = Save(I64);
    auto end = ReserveImageBytes(header, bytes, line);
    Get(RegionCursor(header)); Get(cursor); Get(bytes); code.Op(0xa7); code.Copy();
    PublishCursor(header, end); Get(element.second); Set(cursor);
    Get(index); code.I64Const(1); code.Op(0x7c); Set(index); Br(loop); End(); End();
}

} // namespace goose::direct_wasm
