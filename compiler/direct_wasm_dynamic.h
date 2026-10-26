// Owned dynamic storage for the direct target. Array elements live in stable
// page-aligned chunks; growing the pointer table never relocates an element.
// A tagged slice anchor is an actual element address with bit 31 set. The
// sparse page map recovers its owner and logical index, so slice values need
// neither a temporary descriptor nor a host allocation.
#pragma once
namespace goose::direct_wasm {

enum DynamicHelper : uint32_t { DH_ALLOC, DH_FREE, DH_ENSURE, DH_ADDRESS, DH_COUNT };
inline constexpr uint32_t DA_LEN = 0, DA_TABLE = 4, DA_CHUNKS = 8, DA_TABLECAP = 12;
inline constexpr uint32_t DA_STRIDE = 16, DA_CHUNKCAP = 20, DA_CHUNKBYTES = 24, DA_LIMIT = 28;
inline constexpr uint32_t DA_INLINE = 32, DA_SIZE = 64, DC_HEADER = 32, DH_PAGE = 4096;

inline vector<Signature> DynamicSignatures() {
    return { {{I32, I32}, {I32}}, {{I32}, {}},
             {{I32, I32, I32, I32}, {}}, {{I64, I32, I32, I32}, {I32}} };
}
inline string DynamicBody(Function &f) {
    f.code.Op(0x0b);
    Bytes result;
    vector<pair<uint32_t, uint8_t>> groups;
    for (auto type : f.locals) {
        if (!groups.empty() && groups.back().second == type) groups.back().first++;
        else groups.emplace_back(1, type);
    }
    result.U(groups.size());
    for (auto [count, type] : groups) { result.U(count); result.Byte(type); }
    result.Raw(f.code.data); return result.data;
}

inline vector<string> Compiler::DynamicBodies() {
    vector<string> bodies;
    auto signatures = DynamicSignatures();
    for (uint32_t which = 0; which < DH_COUNT; which++) {
        Function f(*this, nullptr, dynamic_runtime + which, dynamic_types[which]);
        f.params = signatures[which].args; f.locals.clear();
        auto &b = f.code;
        auto load = [&](uint32_t local, uint32_t off) { f.Get(local); b.Mem(0x28, 2, off); };
        auto store = [&](uint32_t local, uint32_t off, uint32_t value) {
            f.Get(local); f.Get(value); b.Mem(0x36, 2, off);
        };
        auto constant = [&](uint32_t local, uint32_t off, uint32_t value) {
            f.Get(local); b.I32Const(int32_t(value)); b.Mem(0x36, 2, off);
        };
        auto abort = [&](uint32_t line, string_view message) {
            b.I32Const(int32_t(Text(message))); b.I32Const(int32_t(message.size())); f.Get(line);
            f.CallIndex(ABORT); b.Op(0x00);
        };
        auto require = [&](uint32_t line, string_view message) {
            f.Begin(0x04); abort(line, message); f.End();
        };
        if (which == DH_ALLOC) {
            // Blocks and their sizes are multiples of 4 KiB. The address-
            // ordered free list coalesces, so replacing a repeatedly-used
            // buffer does not strand its previous capacities.
            f.Get(0); b.I32Const(int32_t(uint64_t(opts.maximum_pages) * 65536 - DH_PAGE)); b.Op(0x4b);
            require(1, "dynamic allocation exceeds the linear-memory limit");
            f.Get(0); b.I32Const(DH_PAGE - 1); b.Op(0x6a); b.I32Const(-int32_t(DH_PAGE)); b.Op(0x71);
            auto size = f.Save(I32);
            f.Get(size); b.Op(0x45); f.Begin(0x04); b.I32Const(DH_PAGE); f.Set(size); f.End();
            b.OpU(0x23, 2); auto cur = f.Save(I32);
            b.I32Const(0); auto prev = f.Save(I32), result = f.Local(I32);
            auto found = f.Begin(), search = f.Begin(0x03);
            f.Get(cur); b.Op(0x45); auto missing = f.Begin(0x04);
            b.OpU(0x23, 1); auto frontier = f.Save(I32);
            f.Get(frontier); f.Get(size); b.Op(0x49);
            require(1, "dynamic linear memory exhausted");
            f.Get(frontier); f.Get(size); b.Op(0x6b); auto next = f.Save(I32);
            f.Get(next); b.OpU(0x23, 0); b.Op(0x49);
            require(1, "dynamic linear memory exhausted");
            // The heap descends from the configured limit. Its addresses
            // remain stable even when the activation stack grows later.
            f.EnsureMemory(frontier, {});
            f.Get(next); b.OpU(0x24, 1); f.Get(next); f.Set(result); f.Br(found); f.End();
            (void)missing;
            load(cur, 0); auto available = f.Save(I32);
            f.Get(available); f.Get(size); b.Op(0x4f); f.Begin(0x04);
            load(cur, 4); auto successor = f.Save(I32);
            f.Get(available); f.Get(size); b.Op(0x4b); f.Begin(0x04);
            f.Get(cur); f.Get(size); b.Op(0x6a); auto rest = f.Save(I32);
            f.Get(rest); f.Get(available); f.Get(size); b.Op(0x6b); b.Mem(0x36, 2);
            store(rest, 4, successor); f.Get(rest); f.Set(successor); f.End();
            f.Get(prev); f.Begin(0x04); store(prev, 4, successor); f.Else();
            f.Get(successor); b.OpU(0x24, 2); f.End();
            f.Get(cur); f.Set(result); f.Br(found); f.End();
            f.Get(cur); f.Set(prev); load(cur, 4); f.Set(cur); f.Br(search); f.End(); f.End();
            store(result, 0, size); constant(result, 4, 0);
            f.Get(result); b.I32Const(8); b.Op(0x6a); b.I32Const(0);
            f.Get(size); b.I32Const(8); b.Op(0x6b); b.Fill();
            f.Get(result);
        } else if (which == DH_FREE) {
            auto done = f.Begin(); f.Get(0); b.Op(0x45); f.Br(done, true);
            b.OpU(0x23, 2); auto cur = f.Save(I32);
            b.I32Const(0); auto prev = f.Save(I32);
            auto inserted = f.Begin(), loop = f.Begin(0x03);
            f.Get(cur); b.Op(0x45); f.Br(inserted, true);
            f.Get(cur); f.Get(0); b.Op(0x4f); f.Br(inserted, true);
            f.Get(cur); f.Set(prev); load(cur, 4); f.Set(cur); f.Br(loop); f.End(); f.End();
            store(0, 4, cur);
            f.Get(prev); f.Begin(0x04); store(prev, 4, 0); f.Else();
            f.Get(0); b.OpU(0x24, 2); f.End();
            f.Get(cur); f.Begin(0x04);
            f.Get(0); load(0, 0); b.Op(0x6a); f.Get(cur); b.Op(0x46); f.Begin(0x04);
            f.Get(0); load(0, 0); load(cur, 0); b.Op(0x6a); b.Mem(0x36, 2);
            f.Get(0); load(cur, 4); b.Mem(0x36, 2, 4); f.End(); f.End();
            f.Get(prev); f.Begin(0x04);
            f.Get(prev); load(prev, 0); b.Op(0x6a); f.Get(0); b.Op(0x46); f.Begin(0x04);
            f.Get(prev); load(prev, 0); load(0, 0); b.Op(0x6a); b.Mem(0x36, 2);
            f.Get(prev); load(0, 4); b.Mem(0x36, 2, 4); f.Get(prev); f.Set(0); f.End(); f.End();
            f.Get(0); b.OpU(0x23, 1); b.Op(0x46); f.Begin(0x04);
            f.Get(0); load(0, 0); b.Op(0x6a); b.OpU(0x24, 1);
            load(0, 4); b.OpU(0x24, 2); f.End(); f.End();
        } else if (which == DH_ENSURE) {
            // (descriptor, minimum element count, element stride, source line)
            load(0, DA_STRIDE); b.Op(0x45); f.Begin(0x04);
            store(0, DA_STRIDE, 2);
            b.I32Const(DH_PAGE - DC_HEADER - 16); f.Get(2); b.Op(0x6e); auto capacity = f.Save(I32);
            f.Get(capacity); b.Op(0x45); f.Begin(0x04); b.I32Const(1); f.Set(capacity); f.End();
            store(0, DA_CHUNKCAP, capacity);
            f.Get(0); f.Get(capacity); f.Get(2); b.Op(0x6c);
            b.I32Const(DC_HEADER + 16 + DH_PAGE - 1); b.Op(0x6a);
            b.I32Const(-int32_t(DH_PAGE)); b.Op(0x71); b.Mem(0x36, 2, DA_CHUNKBYTES);
            f.Get(0); f.Get(0); b.I32Const(DA_INLINE); b.Op(0x6a); b.Mem(0x36, 2, DA_TABLE);
            constant(0, DA_TABLECAP, 8); f.End();
            load(0, DA_CHUNKCAP); auto cap = f.Save(I32);
            f.Get(1); f.Get(cap); b.Op(0x6e); auto needed = f.Save(I32);
            f.Get(1); f.Get(cap); b.Op(0x70); f.Begin(0x04);
            f.Get(needed); b.I32Const(1); b.Op(0x6a); f.Set(needed); f.End();
            f.Get(needed); b.Op(0x45); f.Begin(0x04); b.I32Const(1); f.Set(needed); f.End();
            f.Get(needed); load(0, DA_TABLECAP); b.Op(0x4b); f.Begin(0x04);
            load(0, DA_TABLECAP); auto tablecap = f.Save(I32);
            auto sized = f.Begin(), grow = f.Begin(0x03);
            f.Get(tablecap); f.Get(needed); b.Op(0x4f); f.Br(sized, true);
            f.Get(tablecap); b.I32Const(2); b.Op(0x6c); f.Set(tablecap); f.Br(grow); f.End(); f.End();
            f.Get(tablecap); b.I32Const(4); b.Op(0x6c); b.I32Const(DC_HEADER); b.Op(0x6a);
            f.Get(3); f.CallIndex(dynamic_runtime + DH_ALLOC); auto block = f.Save(I32);
            f.Get(block); b.I32Const(DC_HEADER); b.Op(0x6a); auto table = f.Save(I32);
            f.Get(table); load(0, DA_TABLE); load(0, DA_CHUNKS); b.I32Const(4); b.Op(0x6c); b.Copy();
            load(0, DA_TABLE); f.Get(0); b.I32Const(DA_INLINE); b.Op(0x6a); b.Op(0x47); f.Begin(0x04);
            load(0, DA_TABLE); b.I32Const(DC_HEADER); b.Op(0x6b); f.CallIndex(dynamic_runtime + DH_FREE); f.End();
            store(0, DA_TABLE, table); store(0, DA_TABLECAP, tablecap); f.End();
            auto ready = f.Begin(), add = f.Begin(0x03);
            load(0, DA_CHUNKS); auto count = f.Save(I32);
            f.Get(count); f.Get(needed); b.Op(0x4f); f.Br(ready, true);
            load(0, DA_CHUNKBYTES); f.Get(3); f.CallIndex(dynamic_runtime + DH_ALLOC); auto chunk = f.Save(I32);
            store(chunk, 8, 0); store(chunk, 16, 2); store(chunk, 20, cap);
            f.Get(chunk); f.Get(count); f.Get(cap); b.Op(0x6c); b.Mem(0x36, 2, 12);
            // Every physical page of a large-element chunk maps to its
            // first page. The 16-byte tail leaves one-past anchors inside
            // that same allocation even for an exactly full chunk.
            b.I32Const(0); auto page = f.Save(I32);
            auto mapped = f.Begin(), maploop = f.Begin(0x03);
            f.Get(page); load(0, DA_CHUNKBYTES); b.Op(0x4f); f.Br(mapped, true);
            b.I32Const(int32_t(dynamic_pages)); f.Get(chunk); f.Get(page); b.Op(0x6a);
            b.I32Const(12); b.Op(0x76); b.I32Const(4); b.Op(0x6c); b.Op(0x6a);
            f.Get(chunk); b.Mem(0x36, 2);
            f.Get(page); b.I32Const(DH_PAGE); b.Op(0x6a); f.Set(page); f.Br(maploop); f.End(); f.End();
            load(0, DA_TABLE); f.Get(count); b.I32Const(4); b.Op(0x6c); b.Op(0x6a); f.Get(chunk); b.Mem(0x36, 2);
            f.Get(0); f.Get(count); b.I32Const(1); b.Op(0x6a); b.Mem(0x36, 2, DA_CHUNKS);
            f.Br(add); f.End(); f.End();
        } else if (which == DH_ADDRESS) {
            // (packed view, element offset, stride, source line) -> raw ptr
            f.Get(0); b.Op(0xa7); auto anchor = f.Save(I32);
            f.Get(anchor); b.I32Const(0); b.Op(0x48); f.Begin(0x04, I32);
            f.Get(anchor); b.I32Const(INT32_MAX); b.Op(0x71); f.Set(anchor);
            b.I32Const(int32_t(dynamic_pages)); f.Get(anchor); b.I32Const(12); b.Op(0x76);
            b.I32Const(4); b.Op(0x6c); b.Op(0x6a); b.Mem(0x28, 2); auto chunk = f.Save(I32);
            f.Get(chunk); b.Op(0x45); require(3, "invalid dynamic slice anchor");
            load(chunk, 16); f.Get(2); b.Op(0x47); require(3, "dynamic slice element layout mismatch");
            load(chunk, 8); auto owner = f.Save(I32);
            f.Get(anchor); f.Get(chunk); b.Op(0x6b); b.I32Const(DC_HEADER); b.Op(0x6b);
            f.Get(2); b.Op(0x6e); load(chunk, 12); b.Op(0x6a); f.Get(1); b.Op(0x6a); auto position = f.Save(I32);
            load(owner, DA_CHUNKCAP); auto cap = f.Save(I32);
            f.Get(position); f.Get(cap); b.Op(0x6e); auto whichchunk = f.Save(I32);
            f.Get(position); f.Get(cap); b.Op(0x70); auto within = f.Save(I32);
            f.Get(whichchunk); load(owner, DA_CHUNKS); b.Op(0x46);
            f.Get(within); b.Op(0x45); b.Op(0x71); f.Begin(0x04);
            f.Get(whichchunk); b.I32Const(1); b.Op(0x6b); f.Set(whichchunk); f.Get(cap); f.Set(within); f.End();
            f.Get(whichchunk); load(owner, DA_CHUNKS); b.Op(0x4f); require(3, "dynamic slice address out of bounds");
            load(owner, DA_TABLE); f.Get(whichchunk); b.I32Const(4); b.Op(0x6c); b.Op(0x6a); b.Mem(0x28, 2);
            b.I32Const(DC_HEADER); b.Op(0x6a); f.Get(within); f.Get(2); b.Op(0x6c); b.Op(0x6a);
            f.Else(); f.Get(anchor); f.Get(1); f.Get(2); b.Op(0x6c); b.Op(0x6a); f.End();
        }
        bodies.push_back(DynamicBody(f));
    }
    return bodies;
}

inline bool Compiler::DynamicArray(TypeExpr *t) const {
    return t && t->kind == TY_ARRAY && t->arr->akind != A_FIXED;
}
inline bool Compiler::OwnsDynamic(TypeExpr *t) const {
    if (!t) return false;
    if (t->kind == TY_ARRAY) return DynamicArray(t) || OwnsDynamic(t->arr->sub);
    if (t->kind == TY_STRUCT && t->struc->inst)
        for (auto field : t->struc->inst->ftypes) if (OwnsDynamic(field)) return true;
    if (t->kind == TY_ENUM && t->enu->inst)
        for (auto &variant : t->enu->inst->vftypes)
            for (auto field : variant) if (OwnsDynamic(field)) return true;
    if (t->kind == TY_VARIANT) {
        auto owner = t->var->adt;
        auto vi = owner->enu->en->VariantIndex(t->var->variant);
        for (auto field : owner->enu->inst->vftypes[size_t(vi)]) if (OwnsDynamic(field)) return true;
    }
    return false;
}
inline void Function::HeapAllocate(uint32_t bytes, Line line) {
    Get(bytes); code.I32Const(line.line); CallIndex(c.dynamic_runtime + DH_ALLOC);
}
inline void Function::HeapFree(uint32_t block) { Get(block); CallIndex(c.dynamic_runtime + DH_FREE); }
inline void Function::ArrayEnsure(TypeExpr *t, uint32_t owner, uint32_t length, Line line) {
    auto stride = c.Size(t->arr->sub).size;
    Get(length); code.Op(0xad); code.I64Const(stride); code.Op(0x7e);
    code.I64Const(int64_t(uint64_t(c.opts.maximum_pages) * 65536 - DH_PAGE)); code.Op(0x56);
    TrapIf(line, "dynamic array exceeds the linear-memory limit");
    if (t->arr->akind == A_LIMITED) {
        Get(length);
        if (t->arr->size >= 0) code.I32Const(int32_t(t->arr->size));
        else { Get(owner); code.Mem(0x28, 2, DA_LIMIT); }
        code.Op(0x4b);
        TrapIf(line, "array capacity exceeded");
    } else if (t->arr->akind == A_VAR && t->arr->lenstorage >= 0 &&
               IntBits(IntStorage(t->arr->lenstorage)) < 32) {
        Get(length); code.I32Const(int32_t((UINT64_C(1) << IntBits(IntStorage(t->arr->lenstorage))) - 1)); code.Op(0x4b);
        TrapIf(line, "array length exceeds its storage range");
    }
    Get(owner); Get(length); code.I32Const(int32_t(stride)); code.I32Const(line.line);
    CallIndex(c.dynamic_runtime + DH_ENSURE);
}
inline void Function::ArrayValueView(TypeExpr *t) {
    if (!c.DynamicArray(t)) {
        c.Size(t); code.Op(0xad); code.I64Const(int64_t(uint64_t(t->arr->size) << 32)); code.Op(0x84); return;
    }
    auto owner = Save(I32);
    Get(owner); code.Mem(0x28, 2, DA_LEN); auto len = Save(I32);
    Get(owner); code.Mem(0x28, 2, DA_CHUNKS); code.Op(0x45); Begin(0x04);
    ArrayEnsure(t, owner, len, t->line); End();
    Get(owner); code.Mem(0x28, 2, DA_TABLE); code.Mem(0x28, 2);
    code.I32Const(DC_HEADER); code.Op(0x6a); code.I32Const(INT32_MIN); code.Op(0x72); code.Op(0xad);
    Get(len); code.Op(0xad); code.I64Const(32); code.Op(0x86); code.Op(0x84);
}
inline void Function::ViewAddress(uint32_t view, uint32_t position, TypeExpr *element, Line line) {
    Get(view); code.Op(0xa7); code.I32Const(0); code.Op(0x48); Begin(0x04, I32);
    Get(view); Get(position); code.I32Const(int32_t(c.Size(element).size)); code.I32Const(line.line);
    CallIndex(c.dynamic_runtime + DH_ADDRESS);
    Else(); Get(view); code.Op(0xa7); Get(position); code.I32Const(int32_t(c.Size(element).size));
    code.Op(0x6c); code.Op(0x6a); End();
}
inline void Function::ArrayAddress(uint32_t owner, uint32_t position, TypeExpr *element) {
    Get(owner); code.Mem(0x28, 2, DA_TABLE);
    Get(position); Get(owner); code.Mem(0x28, 2, DA_CHUNKCAP); code.Op(0x6e);
    code.I32Const(4); code.Op(0x6c); code.Op(0x6a); code.Mem(0x28, 2);
    code.I32Const(DC_HEADER); code.Op(0x6a);
    Get(position); Get(owner); code.Mem(0x28, 2, DA_CHUNKCAP); code.Op(0x70);
    code.I32Const(int32_t(c.Size(element).size)); code.Op(0x6c); code.Op(0x6a);
}

inline void Function::DestroyOwned(TypeExpr *t, uint32_t address) {
    if (!c.OwnsDynamic(t)) return;
    if (c.DynamicArray(t)) {
        auto elem = t->arr->sub;
        if (c.OwnsDynamic(elem)) {
            code.I32Const(0); auto i = Save(I32);
            auto done = Begin(), loop = Begin(0x03);
            Get(i); Get(address);
            if (t->arr->akind == A_LIMITED) {
                code.Mem(0x28, 2, DA_CHUNKS); Get(address); code.Mem(0x28, 2, DA_CHUNKCAP); code.Op(0x6c);
            } else code.Mem(0x28, 2, DA_LEN);
            code.Op(0x4f); Br(done, true);
            ArrayAddress(address, i, elem); auto at = Save(I32); DestroyOwned(elem, at);
            Get(i); code.I32Const(1); code.Op(0x6a); Set(i); Br(loop); End(); End();
        }
        Get(address); code.Mem(0x28, 2, DA_TABLE); auto table = Save(I32);
        code.I32Const(0); auto i = Save(I32);
        auto done = Begin(), loop = Begin(0x03);
        Get(i); Get(address); code.Mem(0x28, 2, DA_CHUNKS); code.Op(0x4f); Br(done, true);
        Get(table); Get(i); code.I32Const(4); code.Op(0x6c); code.Op(0x6a); code.Mem(0x28, 2); auto chunk = Save(I32);
        code.I32Const(int32_t(c.dynamic_pages)); Get(chunk); code.I32Const(12); code.Op(0x76);
        code.I32Const(4); code.Op(0x6c); code.Op(0x6a); code.I32Const(0);
        Get(chunk); code.Mem(0x28, 2); code.I32Const(10); code.Op(0x76); code.Fill();
        HeapFree(chunk);
        Get(i); code.I32Const(1); code.Op(0x6a); Set(i); Br(loop); End(); End();
        Get(table); Get(address); code.I32Const(DA_INLINE); code.Op(0x6a); code.Op(0x47);
        Get(table); code.Op(0x45); code.Op(0x45); code.Op(0x71); Begin(0x04);
        Get(table); code.I32Const(DC_HEADER); code.Op(0x6b); auto block = Save(I32); HeapFree(block); End();
        Get(address); code.I32Const(0); code.I32Const(DA_SIZE); code.Fill();
    } else if (t->kind == TY_ARRAY) {
        auto elem = t->arr->sub;
        code.I32Const(0); auto i = Save(I32);
        auto done = Begin(), loop = Begin(0x03);
        Get(i); code.I32Const(int32_t(t->arr->size)); code.Op(0x4f); Br(done, true);
        Get(address); Get(i); code.I32Const(int32_t(c.Size(elem).size)); code.Op(0x6c); code.Op(0x6a);
        auto at = Save(I32); DestroyOwned(elem, at);
        Get(i); code.I32Const(1); code.Op(0x6a); Set(i); Br(loop); End(); End();
    } else if (t->kind == TY_STRUCT || t->kind == TY_VARIANT) {
        auto layout = c.Size(t);
        for (size_t i = 0; i < layout.fields.size(); i++) {
            auto field = c.FieldType(t, i);
            if (!c.OwnsDynamic(field)) continue;
            Get(address); code.I32Const(int32_t(layout.fields[i])); code.Op(0x6a);
            auto at = Save(I32); DestroyOwned(field, at);
        }
    } else if (t->kind == TY_ENUM) {
        Get(address); code.Mem(0x28, 2); auto tag = Save(I32);
        auto done = Begin();
        for (size_t vi = 0; vi < t->enu->inst->vftypes.size(); vi++) {
            Get(tag); code.I32Const(int32_t(vi)); code.Op(0x46); Begin(0x04);
            auto layout = c.VariantLayout(t, int(vi));
            auto &types = t->enu->inst->vftypes[vi];
            for (size_t i = 0; i < types.size(); i++) if (c.OwnsDynamic(types[i])) {
                Get(address); code.I32Const(int32_t(c.PayloadOffset(t) + layout.fields[i])); code.Op(0x6a);
                auto at = Save(I32); DestroyOwned(types[i], at);
            }
            Br(done); End();
        }
        End(); Get(address); code.I32Const(0); code.I32Const(int32_t(c.Size(t).size)); code.Fill();
    }
}

inline void Function::StoreOwned(TypeExpr *t, bool assignment) {
    auto source = Save(I32), dest = Save(I32);
    Get(source); Get(dest); code.Op(0x47); Begin(0x04);
    if (c.DynamicArray(t)) {
        // Limited destinations keep their capacity on assignment. A fresh
        // construction receives the source's capacity (or the fixed type's).
        Get(source); code.Mem(0x28, 2, DA_LEN); auto length = Save(I32);
        uint32_t limit = 0;
        if (t->arr->akind == A_LIMITED) {
            if (t->arr->size >= 0) code.I32Const(int32_t(t->arr->size));
            else { Get(assignment ? dest : source); code.Mem(0x28, 2, DA_LIMIT); }
            limit = Save(I32);
            Get(length); Get(limit); code.Op(0x4b); TrapIf(t->line, "array capacity exceeded");
        }
        // Limited arrays retain every written slot, including slots past
        // their current length: old references/slices may still name them.
        // Only destruction of the owner can release those addresses.
        if (t->arr->akind != A_LIMITED || !assignment) DestroyOwned(t, dest);
        if (t->arr->akind == A_LIMITED) { Get(dest); Get(limit); code.Mem(0x36, 2, DA_LIMIT); }
        ArrayEnsure(t, dest, length, t->line);
        code.I32Const(0); auto i = Save(I32); auto elem = t->arr->sub;
        auto done = Begin(), loop = Begin(0x03);
        Get(i); Get(length); code.Op(0x4f); Br(done, true);
        ArrayAddress(dest, i, elem); ArrayAddress(source, i, elem); Load(elem);
        if (assignment && t->arr->akind == A_LIMITED && c.OwnsDynamic(elem)) StoreOwned(elem, true);
        else Store(elem);
        Get(i); code.I32Const(1); code.Op(0x6a); Set(i); Br(loop); End(); End();
        Get(dest); Get(length); code.Mem(0x36, 2, DA_LEN);
    } else if (t->kind == TY_ARRAY) {
        auto elem = t->arr->sub;
        auto layout = c.Size(elem);
        code.I32Const(0); auto i = Save(I32);
        auto done = Begin(), loop = Begin(0x03);
        Get(i); code.I32Const(int32_t(t->arr->size)); code.Op(0x4f); Br(done, true);
        Get(dest); Get(i); code.I32Const(int32_t(layout.size)); code.Op(0x6c); code.Op(0x6a);
        Get(source); Get(i); code.I32Const(int32_t(layout.size)); code.Op(0x6c); code.Op(0x6a); Load(elem);
        if (c.OwnsDynamic(elem)) StoreOwned(elem, assignment); else Store(elem);
        Get(i); code.I32Const(1); code.Op(0x6a); Set(i); Br(loop); End(); End();
    } else if (t->kind == TY_STRUCT || t->kind == TY_VARIANT) {
        auto layout = c.Size(t);
        for (size_t i = 0; i < layout.fields.size(); i++) {
            auto field = c.FieldType(t, i);
            auto off = layout.fields[i];
            Get(dest); code.I32Const(int32_t(off)); code.Op(0x6a);
            Get(source); code.I32Const(int32_t(off)); code.Op(0x6a); Load(field);
            if (c.OwnsDynamic(field)) StoreOwned(field, assignment); else Store(field);
        }
    } else if (t->kind == TY_ENUM) {
        DestroyOwned(t, dest);
        Get(source); code.Mem(0x28, 2); auto tag = Save(I32);
        Get(dest); Get(tag); code.Mem(0x36, 2);
        auto done = Begin();
        for (size_t vi = 0; vi < t->enu->inst->vftypes.size(); vi++) {
            Get(tag); code.I32Const(int32_t(vi)); code.Op(0x46); Begin(0x04);
            auto layout = c.VariantLayout(t, int(vi));
            auto &types = t->enu->inst->vftypes[vi];
            for (size_t i = 0; i < types.size(); i++) {
                auto offset = c.PayloadOffset(t) + layout.fields[i];
                Get(dest); code.I32Const(int32_t(offset)); code.Op(0x6a);
                Get(source); code.I32Const(int32_t(offset)); code.Op(0x6a); Load(types[i]); Store(types[i]);
            }
            Br(done); End();
        }
        Abort(t->line, "invalid enum tag"); End();
    } else Fail(t->line, "dynamic ownership in this value is not supported");
    End();
}

inline void Function::ArrayCopyView(TypeExpr *t, uint32_t owner, uint32_t view, Line line, bool append) {
    optional<uint32_t> snapshot;
    TypeExpr *snapshot_type = nullptr;
    if (append && t->arr->akind == A_LIMITED) {
        // A retained limited-array slice can extend past the current len.
        // Appending it may overlap the destination run in either direction.
        // Capture that run before writing, including owned nested values.
        auto original = view; view = Local(I64); Get(original); Set(view);
        snapshot_type = c.ast.ArrayOf(t->arr->sub, A_VAR, line);
        auto offset = Frame(snapshot_type); FrameAddress(offset); snapshot = Save(I32);
        DestroyOwned(snapshot_type, *snapshot);
        Get(view); code.Op(0xa7); code.I32Const(0); code.Op(0x48); Begin(0x04);
        code.I32Const(int32_t(c.dynamic_pages)); Get(view); code.Op(0xa7); code.I32Const(INT32_MAX); code.Op(0x71);
        code.I32Const(12); code.Op(0x76); code.I32Const(4); code.Op(0x6c); code.Op(0x6a); code.Mem(0x28, 2);
        code.Mem(0x28, 2, 8); Get(owner); code.Op(0x46); Begin(0x04);
        ArrayCopyView(snapshot_type, *snapshot, view, line);
        Get(*snapshot); ArrayValueView(snapshot_type); Set(view); End(); End();
    }
    Get(view); code.I64Const(32); code.Op(0x88); code.Op(0xa7); auto count = Save(I32);
    if (append) { Get(owner); code.Mem(0x28, 2, DA_LEN); } else code.I32Const(0);
    auto old = Save(I32);
    Get(old); code.Op(0xad); Get(count); code.Op(0xad); code.Op(0x7c);
    code.I64Const(INT32_MAX); code.Op(0x56); TrapIf(line, "dynamic array length overflow");
    Get(old); Get(count); code.Op(0x6a); auto length = Save(I32);
    if (c.DynamicArray(t)) ArrayEnsure(t, owner, length, line);
    else {
        Get(length); code.I32Const(int32_t(t->arr->size)); code.Op(0x47);
        TrapIf(line, "array construction length mismatch");
    }
    auto elem = t->arr->sub;
    code.I32Const(0); auto i = Save(I32);
    auto done = Begin(), loop = Begin(0x03);
    Get(i); Get(count); code.Op(0x4f); Br(done, true);
    Get(old); Get(i); code.Op(0x6a); auto at = Save(I32);
    if (c.DynamicArray(t)) ArrayAddress(owner, at, elem);
    else { Get(owner); Get(at); code.I32Const(int32_t(c.Size(elem).size)); code.Op(0x6c); code.Op(0x6a); }
    ViewAddress(view, i, elem, line); Load(elem);
    if (t->arr->akind == A_LIMITED && c.OwnsDynamic(elem)) StoreOwned(elem, true); else Store(elem);
    Get(i); code.I32Const(1); code.Op(0x6a); Set(i); Br(loop); End(); End();
    if (c.DynamicArray(t)) { Get(owner); Get(length); code.Mem(0x36, 2, DA_LEN); }
    if (snapshot) DestroyOwned(snapshot_type, *snapshot);
}

inline bool Function::ConvertArray(TypeExpr *from, TypeExpr *to, Line line) {
    if (from->kind == TY_ARRAY && to->kind == TY_SLICE) { ArrayValueView(from); return true; }
    if (to->kind != TY_ARRAY || (from->kind != TY_ARRAY && from->kind != TY_SLICE)) return false;
    if (!c.DynamicArray(from) && !c.DynamicArray(to)) return false;
    if (from->kind == TY_ARRAY && c.DynamicArray(from) && c.DynamicArray(to) &&
        from->arr->akind == to->arr->akind && from->arr->size == to->arr->size &&
        from->arr->lenstorage == to->arr->lenstorage) return true;
    if (from->kind == TY_ARRAY) ArrayValueView(from);
    auto view = Save(I64), off = Frame(to);
    FrameAddress(off); auto owner = Save(I32); DestroyOwned(to, owner);
    if (c.DynamicArray(to) && to->arr->akind == A_LIMITED) {
        Get(owner);
        if (to->arr->size >= 0) code.I32Const(int32_t(to->arr->size));
        else { Get(view); code.I64Const(32); code.Op(0x88); code.Op(0xa7); }
        code.Mem(0x36, 2, DA_LIMIT);
    }
    ArrayCopyView(to, owner, view, line); Get(owner); return true;
}

inline bool Function::DynamicLiteral(Node *n) {
    auto t = n->exprtype;
    if (!c.DynamicArray(t)) return false;
    auto off = Frame(t); FrameAddress(off); auto owner = Save(I32); DestroyOwned(t, owner);
    auto array = Is<ArrayLit>(n);
    auto str = Is<StrLit>(n);
    if (!array && !str) return false;
    uint32_t count;
    if (str) code.I32Const(int32_t(str->val.size()));
    else if (array->fillval) {
        To(array->fillcount, c.ast.inttypes[IS_U64]); auto wide = Save(I64);
        Get(wide); code.I64Const(INT32_MAX); code.Op(0x56); TrapIf(n->line, "array construction length overflow");
        Get(wide); code.Op(0xa7);
    } else code.I32Const(int32_t(array->elems.size()));
    count = Save(I32);
    if (t->arr->akind == A_LIMITED) {
        uint32_t capacity;
        if (array && array->capexpr) {
            To(array->capexpr, c.ast.inttypes[IS_U64]); auto wide = Save(I64);
            Get(wide); code.I64Const(INT32_MAX); code.Op(0x56); TrapIf(n->line, "array capacity exceeds the linear-memory limit");
            Get(wide); code.Op(0xa7);
        } else if (t->arr->size >= 0) code.I32Const(int32_t(t->arr->size));
        else Get(count);
        capacity = Save(I32); Get(owner); Get(capacity); code.Mem(0x36, 2, DA_LIMIT);
    }
    ArrayEnsure(t, owner, count, n->line);
    auto elem = t->arr->sub;
    if (str) {
        code.I64Const(int64_t((uint64_t(str->val.size()) << 32) | c.Text(str->val)));
        auto view = Save(I64); ArrayCopyView(t, owner, view, n->line);
    } else if (array->fillval) {
        To(array->fillval, elem); auto value = Save(elem);
        if (c.Aggregate(elem)) {
            auto snapshot = Frame(elem); FrameAddress(snapshot); Get(value); Store(elem);
            FrameAddress(snapshot); Set(value);
        }
        code.I32Const(0); auto i = Save(I32);
        auto done = Begin(), loop = Begin(0x03);
        Get(i); Get(count); code.Op(0x4f); Br(done, true);
        ArrayAddress(owner, i, elem); Get(value); Store(elem);
        Get(i); code.I32Const(1); code.Op(0x6a); Set(i); Br(loop); End(); End();
        Get(owner); Get(count); code.Mem(0x36, 2, DA_LEN);
    } else {
        for (size_t j = 0; j < array->elems.size(); j++) {
            code.I32Const(int32_t(j)); auto i = Save(I32);
            ArrayAddress(owner, i, elem); To(array->elems[j], elem); Store(elem);
            Get(owner); code.I32Const(int32_t(j + 1)); code.Mem(0x36, 2, DA_LEN);
        }
    }
    Get(owner); return true;
}

inline void Function::ArrayTruncate(TypeExpr *t, uint32_t owner, uint32_t length, Line line) {
    auto elem = t->arr->sub;
    Get(length); Get(owner); code.Mem(0x28, 2, DA_LEN); code.Op(0x4b);
    TrapIf(line, "pop count exceeds the array length");
    if (t->arr->akind == A_LIMITED) {
        Get(owner); Get(length); code.Mem(0x36, 2, DA_LEN); return;
    }
    if (c.OwnsDynamic(elem)) {
        Get(length); auto i = Save(I32);
        auto done = Begin(), loop = Begin(0x03);
        Get(i); Get(owner); code.Mem(0x28, 2, DA_LEN); code.Op(0x4f); Br(done, true);
        ArrayAddress(owner, i, elem); auto at = Save(I32); DestroyOwned(elem, at);
        Get(i); code.I32Const(1); code.Op(0x6a); Set(i); Br(loop); End(); End();
    }
    Get(owner); Get(length); code.Mem(0x36, 2, DA_LEN);
    // A clear returns all chunks immediately. Keeping the stable owner
    // descriptor preserves references to the array as a whole.
    Get(length); code.Op(0x45); Begin(0x04);
    Get(owner); code.Mem(0x28, 2, DA_LIMIT); auto limit = Save(I32);
    DestroyOwned(t, owner); Get(owner); Get(limit); code.Mem(0x36, 2, DA_LIMIT); End();
}

inline void Function::WriteView(uint32_t view, Line line) {
    Get(view); code.I64Const(32); code.Op(0x88); code.Op(0xa7); auto length = Save(I32);
    Get(view); code.Op(0xa7); code.I32Const(0); code.Op(0x48); Begin(0x04);
    code.I32Const(0); auto i = Save(I32);
    auto done = Begin(), loop = Begin(0x03);
    Get(i); Get(length); code.Op(0x4f); Br(done, true);
    ViewAddress(view, i, c.ast.inttypes[IS_U8], line); auto at = Save(I32);
    code.I32Const(int32_t(c.dynamic_pages)); Get(at); code.I32Const(12); code.Op(0x76);
    code.I32Const(4); code.Op(0x6c); code.Op(0x6a); code.Mem(0x28, 2); auto chunk = Save(I32);
    Get(chunk); code.I32Const(DC_HEADER); code.Op(0x6a); Get(chunk); code.Mem(0x28, 2, 20); code.Op(0x6a);
    Get(at); code.Op(0x6b); auto run = Save(I32);
    Get(run); Get(length); Get(i); code.Op(0x6b); code.Op(0x4b); Begin(0x04);
    Get(length); Get(i); code.Op(0x6b); Set(run); End();
    Get(at); Get(run); CallIndex(Compiler::WRITE);
    Get(i); Get(run); code.Op(0x6a); Set(i); Br(loop); End(); End();
    Else(); Get(view); code.Op(0xa7); Get(length); CallIndex(Compiler::WRITE); End();
}

inline void Function::FormatText(TypeExpr *target, uint32_t owner, string_view text, Line line) {
    code.I64Const(int64_t((uint64_t(text.size()) << 32) | c.Text(text)));
    auto view = Save(I64); ArrayCopyView(target, owner, view, line, true);
}
inline void Function::FormatNumber(TypeExpr *t, uint32_t value, TypeExpr *target, uint32_t owner, Line line) {
    auto offset = FrameBytes(64, 8);
    uint32_t ptr, length;
    if (t->kind == TY_FLT) {
        Get(value); FrameAddress(offset); code.I32Const(64);
        CallIndex(IsF32(t) ? Compiler::FORMAT_F32 : Compiler::FORMAT_F64);
        length = Save(I32); FrameAddress(offset); ptr = Save(I32);
        Get(length); code.I32Const(64); code.Op(0x4b); TrapIf(line, "host float formatter exceeded its buffer");
    } else {
        Get(value); Convert(t, c.ast.inttypes[IsUnsigned(t->intstorage) ? IS_U64 : IS_I64], line);
        auto number = Save(I64);
        if (IsUnsigned(t->intstorage)) code.I32Const(0);
        else { Get(number); code.I64Const(0); code.Op(0x53); }
        auto negative = Save(I32);
        Get(negative); Begin(0x04); code.I64Const(0); Get(number); code.Op(0x7d); Set(number); End();
        FrameAddress(offset + 64); ptr = Save(I32);
        auto loop = Begin(0x03);
        Get(ptr); code.I32Const(1); code.Op(0x6b); Tee(ptr);
        Get(number); code.I64Const(10); code.Op(0x82); code.Op(0xa7); code.I32Const('0'); code.Op(0x6a); code.Mem(0x3a);
        Get(number); code.I64Const(10); code.Op(0x80); Tee(number); code.Op(0x50); code.Op(0x45); Br(loop, true); End();
        Get(negative); Begin(0x04);
        Get(ptr); code.I32Const(1); code.Op(0x6b); Tee(ptr); code.I32Const('-'); code.Mem(0x3a); End();
        FrameAddress(offset + 64); Get(ptr); code.Op(0x6b); length = Save(I32);
    }
    Get(ptr); code.Op(0xad); Get(length); code.Op(0xad); code.I64Const(32); code.Op(0x86); code.Op(0x84);
    auto view = Save(I64); ArrayCopyView(target, owner, view, line, true);
}
inline void Function::FormatValue(TypeExpr *t, uint32_t value, TypeExpr *target, uint32_t owner,
                                   Line line, bool nested) {
    if (!rendering_types.insert(t).second)
        Fail(line, "rendering recursive reference types requires an explicit nonrecursive view");
    struct RenderScope {
        unordered_set<TypeExpr *> &types;
        TypeExpr *type;
        ~RenderScope() { types.erase(type); }
    } scope { rendering_types, t };
    if (t->kind == TY_REF) {
        if (t->ref->optional) Fail(line, "printing optional references is not supported; narrow the reference first");
        Get(value); Load(t->ref->sub); auto item = Save(t->ref->sub);
        FormatValue(t->ref->sub, item, target, owner, line, nested); return;
    }
    if (t->kind == TY_BOOL) {
        Get(value); Begin(0x04); FormatText(target, owner, "true", line);
        Else(); FormatText(target, owner, "false", line); End(); return;
    }
    if (t->kind == TY_INT || t->kind == TY_FLT) { FormatNumber(t, value, target, owner, line); return; }
    if (t->kind == TY_ARRAY || t->kind == TY_SLICE) {
        auto elem = t->kind == TY_ARRAY ? t->arr->sub : t->sub;
        Get(value); if (t->kind == TY_ARRAY) ArrayValueView(t); auto view = Save(I64);
        if (IsU8(elem) && !nested) { ArrayCopyView(target, owner, view, line, true); return; }
        FormatText(target, owner, IsU8(elem) ? "\"" : "[", line);
        Get(view); code.I64Const(32); code.Op(0x88); code.Op(0xa7); auto count = Save(I32);
        code.I32Const(0); auto i = Save(I32);
        auto done = Begin(), loop = Begin(0x03);
        Get(i); Get(count); code.Op(0x4f); Br(done, true);
        if (!IsU8(elem)) { Get(i); Begin(0x04); FormatText(target, owner, ", ", line); End(); }
        ViewAddress(view, i, elem, line); Load(elem); auto item = Save(elem);
        if (IsU8(elem)) {
            auto rendered = Begin();
            for (auto [ch, escape] : vector<pair<int, string_view>> {{'"', "\\\""}, {'\\', "\\\\"}, {'\n', "\\n"}, {'\r', "\\r"}, {'\t', "\\t"}}) {
                Get(item); code.I32Const(ch); code.Op(0x46); Begin(0x04);
                FormatText(target, owner, escape, line); Br(rendered); End();
            }
            auto one = FrameBytes(1, 1); FrameAddress(one); Get(item); code.Mem(0x3a);
            FrameAddress(one); code.Op(0xad); code.I64Const(INT64_C(1) << 32); code.Op(0x84);
            auto single = Save(I64); ArrayCopyView(target, owner, single, line, true); End();
        } else FormatValue(elem, item, target, owner, line, true);
        Get(i); code.I32Const(1); code.Op(0x6a); Set(i); Br(loop); End(); End();
        FormatText(target, owner, IsU8(elem) ? "\"" : "]", line); return;
    }
    auto fields = [&](const vector<TypeExpr *> &types, const Layout &layout, uint32_t base) {
        for (size_t i = 0; i < types.size(); i++) {
            if (i) FormatText(target, owner, ", ", line);
            Get(value); code.I32Const(int32_t(base + layout.fields[i])); code.Op(0x6a); Load(types[i]);
            auto item = Save(types[i]); FormatValue(types[i], item, target, owner, line, true);
        }
    };
    if (t->kind == TY_STRUCT) {
        string name; t->Dump(name); FormatText(target, owner, name + " { ", line);
        fields(t->struc->inst->ftypes, c.Size(t), 0); FormatText(target, owner, " }", line); return;
    }
    if (t->kind == TY_ENUM || t->kind == TY_VARIANT) {
        auto nominal = t->kind == TY_ENUM ? t : t->var->adt;
        auto variant = [&](int vi, uint32_t base) {
            auto &v = nominal->enu->en->variants[size_t(vi)];
            if (v.fields.empty()) FormatText(target, owner, string(nominal->enu->en->name) + "." + string(v.name), line);
            else {
                FormatText(target, owner, string(v.name) + " { ", line);
                fields(nominal->enu->inst->vftypes[size_t(vi)], c.VariantLayout(nominal, vi), base);
                FormatText(target, owner, " }", line);
            }
        };
        if (t->kind == TY_VARIANT) { variant(nominal->enu->en->VariantIndex(t->var->variant), 0); return; }
        Get(value); code.Mem(0x28); auto tag = Save(I32); auto done = Begin();
        for (size_t vi = 0; vi < nominal->enu->en->variants.size(); vi++) {
            Get(tag); code.I32Const(int32_t(vi)); code.Op(0x46); Begin(0x04);
            variant(int(vi), c.PayloadOffset(nominal)); Br(done); End();
        }
        Abort(line, "invalid enum tag"); End(); return;
    }
    Fail(line, "this value cannot yet be formatted by the direct backend");
}

inline bool Function::DynamicBuiltin(Call *n) {
    auto args = n->ArgNodes();
    auto kind = BuiltinKind(n->builtin);
    if (kind == B_STR || kind == B_FORMAT || kind == B_PRINT) {
        if (!n->fmtspecs.empty()) Fail(n->line, "custom formatters are not supported");
        TypeExpr *target = c.text_builder;
        uint32_t owner;
        size_t first = 0;
        if (kind == B_FORMAT) {
            target = Object(args[0]); owner = Save(I32); first = 1;
            if (!c.DynamicArray(target) || !IsU8(target->arr->sub)) Fail(n->line, "format needs a byte builder");
        } else {
            auto offset = Frame(target); FrameAddress(offset); owner = Save(I32); DestroyOwned(target, owner);
        }
        // Render each argument before evaluating the next one, exactly as
        // Goose does. Bytes already captured are independent of later
        // mutations; a nested print completes before this line is emitted.
        for (size_t i = first; i < args.size(); i++) {
            Expr(args[i]); auto value = Save(args[i]->exprtype);
            FormatValue(args[i]->exprtype, value, target, owner, args[i]->line);
        }
        if (kind == B_PRINT) {
            FormatText(target, owner, "\n", n->line); Get(owner); ArrayValueView(target); auto view = Save(I64);
            WriteView(view, n->line); DestroyOwned(target, owner);
        } else if (kind == B_STR) {
            Get(owner); Convert(target, n->exprtype, n->line);
        }
        return true;
    }
    if (kind == B_COPY && (c.DynamicArray(n->exprtype) || n->exprtype->kind == TY_SLICE)) {
        auto t = n->rettypes.empty() ? n->exprtype : n->rettypes[0];
        if (t->kind == TY_SLICE) t = c.ast.ArrayOf(t->sub, A_VAR, n->line);
        View(args[0]); auto view = Save(I64), offset = Frame(t);
        FrameAddress(offset); auto owner = Save(I32); DestroyOwned(t, owner);
        if (c.DynamicArray(t) && t->arr->akind == A_LIMITED) {
            Get(owner);
            if (t->arr->size >= 0) code.I32Const(int32_t(t->arr->size));
            else { Get(view); code.I64Const(32); code.Op(0x88); code.Op(0xa7); }
            code.Mem(0x36, 2, DA_LIMIT);
        }
        ArrayCopyView(t, owner, view, n->line); Get(owner); Convert(t, n->exprtype, n->line); return true;
    }
    if (kind == B_DEFAULT && c.DynamicArray(n->rettypes[0])) {
        auto t = n->rettypes[0];
        auto offset = Frame(t);
        FrameAddress(offset); auto owner = Save(I32); DestroyOwned(t, owner);
        if (t->arr->akind == A_LIMITED && t->arr->size >= 0) {
            Get(owner); code.I32Const(int32_t(t->arr->size)); code.Mem(0x36, 2, DA_LIMIT);
        }
        Get(owner); Convert(t, n->exprtype, n->line); return true;
    }
    if (kind != B_PUSH && kind != B_APPEND && kind != B_POP && kind != B_POP_N && kind != B_RESIZE &&
        kind != B_CLEAR && kind != B_CAP && kind != B_INDEX_OF) return false;
    auto t = Object(args[0]); auto owner = Save(I32);
    if (kind == B_INDEX_OF && t->kind == TY_ARRAY && !c.DynamicArray(t)) {
        Expr(args[1]); Get(owner); code.Op(0x6b); code.I32Const(int32_t(c.Size(t->arr->sub).size)); code.Op(0x6e); code.Op(0xad);
        Convert(c.ast.inttypes[IS_U64], n->exprtype, n->line); return true;
    }
    if (!c.DynamicArray(t)) Fail(n->line, "array operation requires owned dynamic storage");
    auto elem = t->arr->sub;
    if (kind == B_CAP) {
        if (t->arr->size >= 0) code.I32Const(int32_t(t->arr->size));
        else { Get(owner); code.Mem(0x28, 2, DA_LIMIT); }
        code.Op(0xad);
        Convert(c.ast.inttypes[IS_U64], n->exprtype, n->line); return true;
    }
    if (kind == B_INDEX_OF) {
        Expr(args[1]); auto at = Save(I32);
        code.I32Const(int32_t(c.dynamic_pages)); Get(at); code.I32Const(12); code.Op(0x76);
        code.I32Const(4); code.Op(0x6c); code.Op(0x6a); code.Mem(0x28, 2); auto chunk = Save(I32);
        Get(at); Get(chunk); code.Op(0x6b); code.I32Const(DC_HEADER); code.Op(0x6b);
        code.I32Const(int32_t(c.Size(elem).size)); code.Op(0x6e); Get(chunk); code.Mem(0x28, 2, 12); code.Op(0x6a); code.Op(0xad);
        Convert(c.ast.inttypes[IS_U64], n->exprtype, n->line); return true;
    }
    if (kind == B_APPEND) { View(args[1]); auto view = Save(I64); ArrayCopyView(t, owner, view, n->line, true); return true; }
    if (kind == B_CLEAR) { code.I32Const(0); auto zero = Save(I32); ArrayTruncate(t, owner, zero, n->line); return true; }
    if (kind == B_PUSH) {
        To(args[1], elem); auto value = Save(elem);
        Get(owner); code.Mem(0x28, 2, DA_LEN); auto old = Save(I32);
        Get(old); code.I32Const(1); code.Op(0x6a); auto length = Save(I32);
        Get(length); Get(old); code.Op(0x49); TrapIf(n->line, "dynamic array length overflow");
        ArrayEnsure(t, owner, length, n->line); ArrayAddress(owner, old, elem); auto at = Save(I32);
        Get(at); Get(value);
        if (t->arr->akind == A_LIMITED && c.OwnsDynamic(elem)) StoreOwned(elem, true); else Store(elem);
        Get(owner); Get(length); code.Mem(0x36, 2, DA_LEN);
        Get(at); Convert(n->rettypes[0], n->exprtype, n->line); return true;
    }
    if (kind == B_POP) {
        Get(owner); code.Mem(0x28, 2, DA_LEN); auto old = Save(I32);
        Get(old); code.Op(0x45); TrapIf(n->line, "pop from an empty array");
        Get(old); code.I32Const(1); code.Op(0x6b); auto length = Save(I32);
        ArrayAddress(owner, length, elem); Load(elem); auto value = Save(elem);
        if (c.Aggregate(elem)) {
            auto snapshot = Frame(elem); FrameAddress(snapshot); Get(value); Store(elem);
            FrameAddress(snapshot); Set(value);
        }
        ArrayTruncate(t, owner, length, n->line);
        Get(value); Convert(elem, n->exprtype, n->line); return true;
    }
    To(args[1], c.ast.inttypes[IS_U64]); auto wide = Save(I64);
    Get(wide); code.I64Const(INT32_MAX); code.Op(0x56);
    TrapIf(n->line, kind == B_RESIZE ? "resize length is negative or exceeds the linear-memory limit" : "pop count exceeds the array length");
    Get(wide); code.Op(0xa7); auto count = Save(I32);
    uint32_t fill = 0;
    if (kind == B_RESIZE && args.size() > 2) {
        To(args[2], elem); fill = Save(elem);
        if (c.Aggregate(elem)) {
            auto snapshot = Frame(elem); FrameAddress(snapshot); Get(fill); Store(elem); FrameAddress(snapshot); Set(fill);
        }
    }
    Get(owner); code.Mem(0x28, 2, DA_LEN); auto old = Save(I32);
    if (kind == B_POP_N) {
        Get(count); Get(old); code.Op(0x4b); TrapIf(n->line, "pop count exceeds the array length");
        Get(old); Get(count); code.Op(0x6b); auto length = Save(I32); ArrayTruncate(t, owner, length, n->line); return true;
    }
    Get(count); Get(old); code.Op(0x4b); Begin(0x04);
    if (args.size() < 3) Abort(n->line, "resize growth requires a fill value");
    else {
        ArrayEnsure(t, owner, count, n->line); Get(old); auto i = Save(I32);
        auto done = Begin(), loop = Begin(0x03);
        Get(i); Get(count); code.Op(0x4f); Br(done, true);
        ArrayAddress(owner, i, elem); Get(fill);
        if (t->arr->akind == A_LIMITED && c.OwnsDynamic(elem)) StoreOwned(elem, true); else Store(elem);
        Get(i); code.I32Const(1); code.Op(0x6a); Set(i); Br(loop); End(); End();
        Get(owner); Get(count); code.Mem(0x36, 2, DA_LEN);
    }
    Else(); ArrayTruncate(t, owner, count, n->line); End(); return true;
}

} // namespace goose::direct_wasm
