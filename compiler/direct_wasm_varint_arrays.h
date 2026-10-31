#pragma once
namespace goose::direct_wasm {

inline bool Function::VarintValueToRaw(const vector<TypeExpr *> &types, const ResultDestinations &receivers) const {
    for (size_t i = 0; i < types.size(); i++) {
        auto type = types[i];
        if (type->kind != TY_ARRAY || type->arr->akind != A_VAR || !Compiler::Varint(type->arr->sub)) continue;
        if (receivers.size() == types.size() && receivers[i] &&
            (receivers[i]->elements || Compiler::GrowableArray(receivers[i]->location.storage_type))) return true;
    }
    return false;
}

inline void Function::CheckNamedVarintReturns(Block *body, SFunction *target, size_t arity,
        size_t ordinal, const VarDef *candidate, string_view kind) {
    function<void(Node *)> validate = [&](Node *node) {
        if (!node) return;
        if (auto ret = Is<Return>(node); ret && ret->target == target && ret->vals.size() == arity) {
            auto id = Is<Ident>(ret->vals[ordinal]);
            if (!id || id->vdef != candidate || Compiler::GrowableArray(candidate->type))
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

inline void Function::VarintArrayBuiltin(Call *node, TypeExpr *type) {
    auto header = Save(I32); auto args = node->ArgNodes(); auto line = node->line;
    if (type->arr->akind != A_GROW)
        Fail(line, "varint growables support push, append and clear only");
    auto publish = [&](uint32_t added) {
        ReadArrayLength(header); code.Op(0xad); Get(added); code.Op(0x7c); auto count = Save(I64);
        Get(count); code.I64Const(UINT32_MAX); code.Op(0x56); TrapIf(line, "data region exhausted");
        Get(count); code.Op(0xa7); WriteArrayLength(header, Save(I32));
    };
    auto kind = BuiltinKind(node->builtin);
    if (kind == B_CLEAR) {
        Get(header); code.Mem(0x28, 2); PublishCursor(header, Save(I32));
        code.I32Const(0); WriteArrayLength(header, Save(I32)); return;
    }
    if (kind == B_PUSH) {
        auto address = RegionCursor(header);
        To(args[1], c.ast.inttypes[IS_I64]); auto value = Save(I64);
        ReadArrayLength(header); code.I32Const(-1); code.Op(0x46); TrapIf(line, "data region exhausted");
        AppendVarint(header, value, line);
        code.I64Const(1); publish(Save(I64));
        Get(address); Convert(node->rettypes.at(0), node->exprtype, line); return;
    }
    if (kind != B_APPEND) Fail(line, "varint growables support push, append and clear only");
    auto source = args[1];
    while (auto copy = Is<Call>(source)) {
        if (copy->builtin != B_COPY) break;
        source = copy->FirstArg();
    }
    auto natural = NaturalResults(source);
    auto source_type = natural.size() == 1 ? natural[0] : source->exprtype;
    auto borrowed = Is<Ident>(source) || Is<Index>(source) || Is<SliceExpr>(source) ||
                    (Is<Dot>(source) && Is<Dot>(source)->IsField()) ||
                    (source_type && (source_type->kind == TY_REF || source_type->kind == TY_SLICE));
    if (borrowed) {
        auto captured = CaptureSequence(source, true);
        auto element = captured.type->kind == TY_ARRAY ? captured.type->arr->sub : captured.type->sub;
        if (!Compiler::Varint(element)) Fail(line, "varint append requires matching encoded elements");
        Get(captured.view); code.I64Const(32); code.Op(0x88); auto count = Save(I64);
        Get(captured.view); code.Op(0xa7); CopyVarintElements(header, Save(I32), count, line);
        publish(count); return;
    }
    // A fresh producer writes raw elements into the existing receiver region.
    // Its private count commits only after it returns, while canceled bytes
    // remain in the receiver's physical suffix. No data lease is acquired.
    auto carrier = Compiler::RegionArray(source_type) && Compiler::Varint(source_type->arr->sub) ? source_type :
                   c.ast.ArrayOf(c.ast.inttypes[IS_VARINT], A_VAR, line);
    auto layout = c.ControlLayout(carrier);
    Location stage { carrier, Slot { Slot::FRAME, FrameBytes(layout.size, layout.align), carrier } };
    LocationAddress(stage); auto control = Save(I32);
    Get(control); code.I32Const(0); code.I32Const(int32_t(owner_control_bytes)); code.Fill();
    Get(control); Get(RegionCursor(header)); code.Mem(0x36, 2);
    Get(control); Get(header); code.Mem(0x28, 2, 8); code.Mem(0x36, 2, 8);
    auto depth = cleanups.size(), private_depth = private_headers.size();
    RegisterEffectOwner(stage); private_headers.push_back({ stage, cleanups.size() });
    code.I32Const(0); auto publication = Save(I32);
    ConstructRegionInto(source, { stage, ConstructionDestination::Statement, true, {}, false, false, publication });
    ReadArrayLength(control); code.Op(0xad); auto count = Save(I64);
    CloseCleanups(depth); private_headers.resize(private_depth);
    publish(count);
}

} // namespace goose::direct_wasm
