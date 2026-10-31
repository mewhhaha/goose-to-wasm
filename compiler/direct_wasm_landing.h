#pragma once
namespace goose::direct_wasm {

inline uint32_t Function::CursorSlot(uint32_t header) {
    Get(header); code.Mem(0x28, 2, 8); code.OpU(0x23, G_REGION_BASE); code.Op(0x6b);
    code.OpU(0x23, G_REGION_BYTES); code.Op(0x6e); code.I32Const(1); code.Op(0x6b);
    code.I32Const(4); code.Op(0x6c); code.OpU(0x23, c.cursor_global); code.Op(0x6a);
    return Save(I32);
}

inline uint32_t Function::RegionCursor(uint32_t header) {
    Get(CursorSlot(header)); code.Mem(0x28, 2); return Save(I32);
}

inline void Function::PublishCursor(uint32_t header, uint32_t top) {
    if (!c.owned_effects) return;
    Get(CursorSlot(header)); Get(top); code.Mem(0x36, 2);
}

inline void Function::PublishArrayCursor(uint32_t header, TypeExpr *type, uint32_t count) {
    if (!c.owned_effects) return;
    Get(header); code.Mem(0x28, 2); Get(count); code.Op(0xa7);
    code.I32Const(int32_t(c.FixedLayout(type->arr->sub).size)); code.Op(0x6c); code.Op(0x6a);
    PublishCursor(header, Save(I32));
}

// Reserve physical suffix bytes independently of the logical array length.
// Landing can retain a suffix longer than the winning value's published len.
inline uint32_t Function::ReserveCursor(uint32_t header, uint32_t count, TypeExpr *element, Line line) {
    auto current = RegionCursor(header);
    Get(current); Get(header); code.Mem(0x28, 2); code.Op(0x49);
    Get(current); Get(header); code.Mem(0x28, 2, 8); code.Op(0x4b); code.Op(0x72);
    TrapIf(line, "data region exhausted");
    Get(header); code.Mem(0x28, 2, 8); code.Op(0xad); Get(current); code.Op(0xad); code.Op(0x7d);
    code.I64Const(c.FixedLayout(element).size); code.Op(0x80); auto available = Save(I64);
    Get(count); Get(available); code.Op(0x56); TrapIf(line, "data region exhausted");
    Get(current); code.Op(0xad); Get(count); code.I64Const(c.FixedLayout(element).size); code.Op(0x7e); code.Op(0x7c); code.Op(0xa7);
    auto top = Save(I32); EnsureMemory(top, line); return top;
}

inline void Function::RebaseEscapeStage(const ConstructionDestination &destination) {
    if (!destination.escape_stage) return;
    LocationAddress(TailHeaderLocation(destination.location)); auto header = Save(I32);
    auto cursor = RegionCursor(header);
    Get(header); Get(cursor); code.Mem(0x36, 2);
    PublishHeader(header, 0);
}

inline bool Function::ClosedEscapeProducer(FnSpec *root) {
    unordered_map<FnSpec *, bool> seen;
    unordered_set<TypeExpr *> visiting;
    function<bool(TypeExpr *)> holders = [&](TypeExpr *type) {
        if (!type || !visiting.insert(type).second) return false;
        if (IsRefOrSlice(type)) return true;
        if (type->kind == TY_ARRAY) return holders(type->arr->sub);
        if (type->kind == TY_STRUCT || type->kind == TY_VARIANT) {
            for (auto field : c.RecordFields(type)) if (holders(field)) return true;
        } else if (type->kind == TY_ENUM) {
            for (auto &fields : type->enu->inst->vftypes) for (auto field : fields) if (holders(field)) return true;
        }
        return false;
    };
    auto fixed_value = [&](TypeExpr *type) { visiting.clear(); return c.Class(type) == SC_FIXED && !holders(type); };
    function<bool(Node *)> uninterrupted = [&](Node *node) {
        if (!node) return true;
        if (auto call = Is<Call>(node)) {
            return call->builtin == B_COPY && uninterrupted(call->FirstArg());
        }
        if (Is<Block>(node) || Is<IfExpr>(node) || Is<MatchExpr>(node) || Is<EarlyBlock>(node) ||
            Is<LoopExpr>(node) || Is<Return>(node) || Is<Assign>(node) || Is<IncDec>(node) || Is<VarDecl>(node)) return false;
        bool valid = true;
        RunChildren(node, [&](Node *child) { valid &= uninterrupted(child); }); return valid;
    };
    function<bool(FnSpec *)> closed = [&](FnSpec *spec) {
        if (!spec || spec->sf->isextern) return false;
        if (auto known = seen.find(spec); known != seen.end()) return known->second;
        seen[spec] = true;
        for (auto p : spec->params) if (p->type->kind != TY_FN && !fixed_value(p->type)) return seen[spec] = false;
        for (auto capture : c.captures[spec]) if (!fixed_value(capture->type)) return seen[spec] = false;
        bool valid = true;
        function<void(Node *)> walk = [&](Node *node) {
            if (!node || !valid || Is<FnDecl>(node) || Is<FunVal>(node) || Is<StructDecl>(node) || Is<EnumDecl>(node) || Is<AliasDecl>(node)) return;
            if (auto id = Is<Ident>(node); id && id->vdef && id->vdef->isglobal && id->vdef->type->kind != TY_FN) {
                auto type = id->vdef->type;
                if (type->kind != TY_INT && type->kind != TY_FLT && type->kind != TY_BOOL) valid = false;
            }
            // A canceled external owned escape can leave a partial suffix in
            // the destination and still return normally. Such producers need
            // a stronger proof before they can occur inside a literal value.
            if (auto ret = Is<Return>(node); ret && ret->target != spec->sf && ret->targetspec &&
                c.effect_globals.count(ret->targetspec)) {
                for (auto type : ret->targetspec->rets) if (Compiler::RegionOwner(type))
                    for (auto value : ret->vals) valid &= uninterrupted(value);
            }
            if (auto call = Is<Call>(node); call && call->builtin < 0 && !call->fvbody) {
                if (call->dispatch.empty()) valid &= closed(call->spec);
                else for (auto arm : call->dispatch) valid &= closed(arm);
            }
            RunChildren(node, [&](Node *child) { walk(child); });
        };
        walk(spec->body); return seen[spec] = valid;
    };
    return closed(root);
}

inline bool Function::SafeEscapeRead(Node *node, bool pushes) {
    vector<SFunction *> local;
    function<bool(Node *, bool)> safe = [&](Node *part, bool allow_push) {
    if (!part) return true;
    if (auto inlined = Is<InlineBlock>(part)) {
        local.push_back(inlined->sf); auto valid = safe(inlined->body, false); local.pop_back(); return valid;
    }
    if (auto ret = Is<Return>(part)) {
        if (find(local.begin(), local.end(), ret->target) == local.end()) return false;
        for (auto value : ret->vals) if (!safe(value, false)) return false;
        return true;
    }
    if (Is<Assign>(part) || Is<IncDec>(part) || Is<Break>(part) || Is<Continue>(part)) return false;
    if (auto call = Is<Call>(part)) {
        if (call->fvbody || !call->dispatch.empty()) return false;
        auto args = call->ValueArgNodes();
        if (call->builtin == B_PUSH && allow_push)
            return args.size() == 2 && safe(args[0], false) && safe(args[1], false);
        if (call->builtin >= 0 && call->builtin != B_COPY && call->builtin != B_DEFAULT) return false;
        if (call->builtin < 0 && !ClosedEscapeProducer(call->spec)) return false;
        for (auto arg : args) if (!safe(arg, allow_push)) return false;
        return safe(call->defaultinit, false);
    }
    if (Is<FnDecl>(part) || Is<FunVal>(part) || Is<StructDecl>(part) || Is<EnumDecl>(part) || Is<AliasDecl>(part)) return false;
    bool valid = true;
    RunChildren(part, [&](Node *child) { valid &= safe(child, allow_push); }); return valid;
    };
    return safe(node, pushes);
}

inline void Function::LandArraySuffix(uint32_t original, uint32_t start, uint32_t length, TypeExpr *type, Line line, optional<uint32_t> landing_base) {
    if (landing_base) { Get(original); Get(*landing_base); code.Mem(0x36, 2); }
    auto finish = RegionCursor(original);
    Get(start); Get(original); code.Mem(0x28, 2); code.Op(0x49);
    Get(finish); Get(original); code.Mem(0x28, 2, 8); code.Op(0x4b); code.Op(0x72);
    TrapIf(line, "invalid nonlocal landing span");
    Get(start); Get(finish); code.Op(0x4b); TrapIf(line, "invalid nonlocal landing span");
    Get(finish); code.Op(0xad); Get(start); code.Op(0xad); code.Op(0x7d); auto bytes = Save(I64);
    Get(length); code.Op(0xad); code.I64Const(c.FixedLayout(type->arr->sub).size); code.Op(0x7e);
    Get(bytes); code.Op(0x56); TrapIf(line, "invalid nonlocal landing length");
    ReserveRegion(original, bytes, c.ast.inttypes[IS_U8], line);
    Get(original); code.Mem(0x28, 2); auto base = Save(I32);
    Get(base); Get(start); Get(bytes); code.Op(0xa7); code.Copy();
    Get(original); Get(length); code.Mem(0x36, 2, 4);
    PublishHeader(original, 4);
    Get(base); Get(bytes); code.Op(0xa7); code.Op(0x6a); PublishCursor(original, Save(I32));
}

inline bool Function::ConstructNormalOwnedResult(Node *value, const ConstructionDestination &destination) {
    auto type = destination.location.storage_type;
    if (!c.owned_effects || destination.escape_stage || !Compiler::RegionArray(type) || Compiler::RuntimeLimited(type) ||
        !destination.normal_result)
        return false;
    auto call = Is<Call>(value);
    auto forwarding = call && call->builtin < 0 && !call->fvbody && call->dispatch.empty() && call->spec &&
        call->spec->rets.size() == 1 && Compiler::RegionArray(call->spec->rets[0]) && !Compiler::RuntimeLimited(call->spec->rets[0]);
    if (spec && c.effect_globals.count(spec) && results.size() == 1 && Compiler::GrowableArray(results[0]) &&
        destination.lifetime == ConstructionDestination::Caller && !SafeEscapeRead(value, forwarding))
        Fail(value ? value->line : spec->sf->line, "owned escape target result construction needs a qualified producer");
    LocationAddress(destination.location); auto original = Save(I32);
    Get(original); code.Mem(0x28, 2); auto landing_base = Save(I32);
    auto publication = Publication(destination);
    auto land = destination.construction->open > destination.open0;
    auto start = RegionCursor(original);
    auto control = c.ControlLayout(type);
    Location stage { type, Slot { Slot::FRAME, FrameBytes(control.size, control.align), type } };
    LocationAddress(stage); auto header = Save(I32);
    Get(header); Get(start); code.Mem(0x36, 2);
    Get(header); code.I32Const(0); code.Mem(0x36, 2, 4);
    Get(header); Get(original); code.Mem(0x28, 2, 8); code.Mem(0x36, 2, 8);
    Get(header); code.I32Const(0); code.Mem(0x36, 2, 12);
    auto depth = cleanups.size(), private_index = private_headers.size();
    RegisterEffectOwner(stage, true, false, publication); private_headers.push_back({ stage, cleanups.size() });
    cleanups.push_back({ CleanupAction::CheckAbandonedRegion, original, type->arr->sub, value ? value->line : type->line, destination.enum_guard });
    ConstructRegionInto(value, { stage, ConstructionDestination::Statement, destination.elements, {}, true, false, publication, destination.construction, destination.open0 });
    Get(header); code.Mem(0x28, 2, 4); auto length = Save(I32);
    if (land)
        LandArraySuffix(original, start, length, type, value ? value->line : type->line, landing_base);
    else {
        Get(original); Get(length); code.Mem(0x36, 2, 4); PublishHeader(original, 4);
    }
    CloseCleanups(depth); private_headers.erase(private_headers.begin() + private_index);
    return true;
}

inline bool Function::ConstructNormalRecordResult(Node *value, const ConstructionDestination &destination) {
    auto type = destination.location.storage_type;
    if (!c.owned_effects || destination.escape_stage || !Compiler::RegionRecord(type) ||
        !destination.normal_result) return false;
    auto layout = c.ControlLayout(type);
    auto tail_type = c.TailType(type);
    LocationAddress(TailHeaderLocation(destination.location)); auto original = Save(I32);
    Get(original); code.Mem(0x28, 2); auto landing_base = Save(I32);
    auto publication = Publication(destination);
    auto land = destination.construction->open > destination.open0;
    auto start = RegionCursor(original);
    Location stage { type, Slot { Slot::FRAME, FrameBytes(layout.size, layout.align), type } };
    auto staged_tail = TailHeaderLocation(stage);
    LocationAddress(staged_tail); auto header = Save(I32);
    Get(header); Get(start); code.Mem(0x36, 2);
    Get(header); code.I32Const(0); code.Mem(0x36, 2, 4);
    Get(header); Get(original); code.Mem(0x28, 2, 8); code.Mem(0x36, 2, 8);
    Get(header); code.I32Const(0); code.Mem(0x36, 2, 12);
    auto depth = cleanups.size(), private_index = private_headers.size();
    RegisterEffectOwner(stage, true, false, publication, layout.payload, true);
    private_headers.push_back({ staged_tail, cleanups.size() });
    cleanups.push_back({ CleanupAction::CheckAbandonedRegion, original, tail_type->arr->sub, value ? value->line : type->line, destination.enum_guard });
    ConstructRecordInto(value, { stage, ConstructionDestination::Statement, false, destination.enum_guard, true, false, publication, destination.construction, destination.open0 });
    if (layout.payload) {
        LocationAddress(destination.location); CanonicalAddress(layout.payload);
        LocationAddress(stage); CanonicalAddress(layout.payload); code.I32Const(int32_t(layout.payload)); code.Copy();
    }
    Get(header); code.Mem(0x28, 2, 4); auto length = Save(I32);
    Get(header); code.Mem(0x28, 2); Get(start); code.Op(0x6b); Get(landing_base); code.Op(0x6a); auto final_base = Save(I32);
    if (land)
        LandArraySuffix(original, start, length, tail_type, value ? value->line : type->line, landing_base);
    else {
        Get(original); Get(length); code.Mem(0x36, 2, 4); PublishHeader(original, 4);
        Get(header); code.Mem(0x28, 2); Set(final_base);
    }
    if (Compiler::FrameStruct(type)) {
        Get(original); Get(final_base); code.Mem(0x36, 2); PublishHeader(original, 0);
    }
    if (Compiler::RuntimeLimited(tail_type)) {
        Get(original); Get(header); code.Mem(0x28, 2, 12); code.Mem(0x36, 2, 12);
    }
    CloseCleanups(depth); private_headers.erase(private_headers.begin() + private_index); return true;
}

inline void Function::NonlocalOwnedReturn(Return *node) {
    if (node->vals.size() != 1) Fail(node->line, "owned nonlocal return requires one source expression");
    auto value = node->vals[0]; auto target = node->targetspec;
    auto call = Is<Call>(value);
    bool forwarding = call && call->builtin < 0 && !call->fvbody && call->dispatch.empty() && call->spec &&
        call->spec->rets.size() == 1 && Compiler::RegionArray(call->spec->rets[0]) && !Compiler::RuntimeLimited(call->spec->rets[0]);
    if (!SafeEscapeRead(value, forwarding))
        Fail(node->line, "owned nonlocal source requires a pure read or a closed producer with qualified arguments");
    code.OpU(0x23, c.effect_globals.at(target)); auto destination = Save(I32);
    Get(destination); code.Op(0x45); TrapIf(node->line, "nonlocal return target is not active");
    Get(destination); code.Mem(0x28, 2, 4); auto original = Save(I32);
    auto start = RegionCursor(original);
    auto type = target->rets[0]; auto control = c.ControlLayout(type);
    Location stage { type, Slot { Slot::FRAME, FrameBytes(control.size, control.align), type } };
    LocationAddress(stage); auto header = Save(I32);
    Get(header); Get(start); code.Mem(0x36, 2);
    Get(header); code.I32Const(0); code.Mem(0x36, 2, 4);
    Get(header); Get(original); code.Mem(0x28, 2, 8); code.Mem(0x36, 2, 8);
    Get(header); code.I32Const(0); code.Mem(0x36, 2, 12);
    RegisterEffectOwner(stage);
    private_headers.push_back({ stage, cleanups.size() });
    code.I32Const(0); auto private_publication = Save(I32);
    ConstructRegionInto(value, { stage, ConstructionDestination::Statement, false, {}, true, false, private_publication });
    auto box = OffsetLocation({ type, AddressLocal { destination } }, c.MailboxLayout(target).fields[0], type);
    LocationAddress(box); Get(header); code.I32Const(16); code.Copy();
    Get(destination); Get(start); code.Mem(0x36, 2, 8);
    Get(destination); code.OpU(0x24, c.pending_effect); CheckPendingEffect(node->line);
}

inline void Function::LandOwnedEffect() {
    FrameAddress(mailbox + 4); code.Mem(0x28, 2); auto original = Save(I32);
    FrameAddress(mailbox + 8); code.Mem(0x28, 2); auto start = Save(I32);
    FrameAddress(mailbox + c.MailboxLayout(spec).fields[0] + 4); code.Mem(0x28, 2); auto length = Save(I32);
    LandArraySuffix(original, start, length, results[0], spec->sf->line);
    Get(original); Set(resultlocals[0]);
}

inline void Function::SkipReplacedEffectOwner(uint32_t header, uint32_t done) {
    if (!c.owned_effects) return;
    for (auto target : c.effect_targets) if (target->rets.size() == 1 && Compiler::GrowableArray(target->rets[0])) {
        auto next = Begin();
        code.OpU(0x23, c.effect_globals.at(target)); code.Op(0x45); Br(next, true);
        code.OpU(0x23, c.pending_effect); code.OpU(0x23, c.effect_globals.at(target)); code.Op(0x47); Br(next, true);
        code.OpU(0x23, c.pending_effect); code.Mem(0x28, 2, 4); Get(header); code.Op(0x46); Br(done, true); End();
    }
}

} // namespace goose::direct_wasm
