#pragma once
namespace goose::direct_wasm {

inline bool Function::ImageTargetDestination(const ConstructionDestination &destination) const {
    if (!spec || !c.effect_globals.count(spec) || !Compiler::ArrayImageEffectResult(destination.location.storage_type)) return false;
    optional<uint32_t> address;
    if (auto local = get_if<AddressLocal>(&destination.location.storage)) address = local->index;
    else if (auto slot = get_if<Slot>(&destination.location.storage); slot && slot->kind == Slot::ADDRESS) address = slot->index;
    if (!address) return false;
    for (size_t i = 0; i < resultdestinations.size(); i++)
        if (resultdestinations[i] && *resultdestinations[i] == *address && Compiler::ArrayImageEffectResult(results[i])) return true;
    return false;
}

inline bool Compiler::ArrayImageEffectResult(TypeExpr *type) {
    if (!type || type->kind != TY_ARRAY ||
        (!(type->arr->akind == A_VAR && LengthStorage(type) != IS_VARINT) && !RuntimeLimited(type))) return false;
    auto element = type->arr->sub;
    return element->kind == TY_BOOL || element->kind == TY_FLT || PackedIntegerImage(element);
}

inline bool Compiler::OwnedEffectResult(TypeExpr *type) {
    if (ArrayImageEffectResult(type)) return true;
    if (GrowableArray(type)) return true;
    if (!FrameStruct(type)) return false;
    ControlLayout(type); return GrowableArray(TailType(type));
}

inline vector<size_t> Compiler::OwnedEffectOrdinals(FnSpec *target) {
    vector<size_t> owned;
    for (size_t i = 0; i < target->rets.size(); i++) if (Class(target->rets[i]) != SC_FIXED) {
        if (!OwnedEffectResult(target->rets[i]))
            Fail(target->sf->line, "this owned nonlocal target requires additional staging and landing support");
        owned.push_back(i);
    }
    return owned;
}

inline bool Compiler::SameEffectType(TypeExpr *a, TypeExpr *b) {
    if (a == b) return true;
    if (!a || !b || a->kind != b->kind) return false;
    switch (a->kind) {
        case TY_INT: return a->intstorage == b->intstorage;
        case TY_FLT: return a->fltstorage == b->fltstorage;
        case TY_BOOL: case TY_VOID: return true;
        case TY_STRUCT: return SameRecord(a, b);
        case TY_VARIANT: return a->var->variant == b->var->variant && SameEffectType(a->var->adt, b->var->adt);
        case TY_ENUM: return a->enu->inst == b->enu->inst && a->enu->varmode == b->enu->varmode;
        case TY_REF: return a->ref->optional == b->ref->optional && a->ref->lenstorage == b->ref->lenstorage &&
                            SameEffectType(a->ref->sub, b->ref->sub);
        case TY_SLICE: return SameEffectType(a->sub, b->sub);
        case TY_ARRAY:
            if (a->arr->akind != b->arr->akind || !SameEffectType(a->arr->sub, b->arr->sub)) return false;
            if (a->arr->akind == A_FIXED || a->arr->akind == A_LIMITED) return a->arr->size == b->arr->size;
            return a->arr->akind != A_VAR || LengthStorage(a) == LengthStorage(b);
        default: return false;
    }
}

inline Layout Compiler::MailboxLayout(FnSpec *target) {
    if (auto found = mailboxes.find(target); found != mailboxes.end()) return found->second;
    auto owned = OwnedEffectOrdinals(target);
    if (owned.size() > (UINT32_MAX - 4) / 12) Fail(target->sf->line, "nonlocal mailbox is too large");
    Layout layout { 4 + uint32_t(owned.size()) * 12, owned.empty() ? 4u : 8u };
    if (!owned.empty()) region_cursors = true;
    size_t next_owned = 0;
    for (size_t i = 0; i < target->rets.size(); i++) {
        auto is_owned = next_owned < owned.size() && i == owned[next_owned];
        auto field = is_owned ? ControlLayout(target->rets[i]) : FixedLayout(target->rets[i]);
        if (is_owned) next_owned++;
        layout.size = Align(layout.size, field.align); layout.fields.push_back(layout.size);
        if (uint64_t(layout.size) + field.size > UINT32_MAX) Fail(target->sf->line, "nonlocal mailbox is too large");
        layout.size += field.size; layout.align = max(layout.align, field.align);
    }
    layout.size = Align(layout.size, layout.align); mailboxes[target] = layout; return layout;
}

inline void Compiler::AnalyzeEffects() {
    // Region image constructors use a physical cursor even without an
    // emitted nonlocal target. Scan has established all reachable owners.
    region_cursors |= needs_regions;
    unordered_set<FnSpec *> seen;
    for (auto spec : specs) {
        vector<SFunction *> local { spec->sf };
        function<void(Node *)> walk = [&](Node *node) {
            if (!node || Is<FnDecl>(node) || Is<FunVal>(node) || Is<StructDecl>(node) ||
                Is<EnumDecl>(node) || Is<AliasDecl>(node)) return;
            if (auto inlined = Is<InlineBlock>(node)) {
                local.push_back(inlined->sf); walk(inlined->body); local.pop_back(); return;
            }
            if (auto ret = Is<Return>(node); ret && ret->targetspec &&
                (!ret->from.empty() || (!local.empty() && local.back() != ret->target)))
                for (auto type : ret->targetspec->rets) if (RegionOwner(type)) region_cursors = true;
            if (auto ret = Is<Return>(node); ret &&
                find(local.begin(), local.end(), ret->target) == local.end()) {
                auto target = ret->targetspec;
                if (!target || !reachable.count(target)) Fail(ret->line, "nonlocal return has no emitted target activation");
                if (seen.insert(target).second) { MailboxLayout(target); effect_targets.push_back(target); }
            }
            RunChildren(node, [&](Node *child) { walk(child); });
        };
        walk(spec->body);
    }
    if (!Effects()) return;
    pending_effect = needs_regions ? 6 : 1; effect_frames = pending_effect + 1;
    cursor_global = effect_frames + 1;
    for (size_t i = 0; i < effect_targets.size(); i++) effect_globals[effect_targets[i]] = effect_frames + 1 + uint32_t(region_cursors) + uint32_t(i);
}

inline void Function::RegisterEffectOwner(const Location &owner, bool lexical, bool temporary,
        optional<uint32_t> publication, uint32_t prefix, bool frame) {
    if (!c.Effects()) return;
    auto offset = FrameBytes(c.region_cursors ? 40 : 16, 4);
    owner_entries.push_back({ offset, temporary });
    FrameAddress(offset + 4); LocationAddress(TailHeaderLocation(owner)); code.Mem(0x36, 2);
    FrameAddress(offset + 8); code.I32Const(1); code.Mem(0x36, 2);
    auto interior = Compiler::RegionEnum(owner.storage_type) ? c.EnumImageLayout(owner.storage_type->enu->inst, owner.storage_type->line).size : 0;
    FrameAddress(offset + 12); code.I32Const(int32_t(interior)); code.Mem(0x36, 2);
    if (c.region_cursors) {
        FrameAddress(offset + 36);
        if (publication) Get(*publication); else code.I32Const(0);
        code.Mem(0x36, 2);
        if (publication) {
            FrameAddress(offset + 16); LocationAddress(owner); code.Mem(0x36, 2);
            FrameAddress(offset + 20); Get(*publication); code.I32Const(-2); code.Op(0x71); code.Mem(0x36, 2);
            FrameAddress(offset + 24); code.I32Const(int32_t(prefix)); code.Mem(0x36, 2);
            FrameAddress(offset + 28); code.I32Const(int32_t(frame ? c.ControlLayout(owner.storage_type).payload : 0)); code.Mem(0x36, 2);
            FrameAddress(offset + 32); Get(*publication); code.I32Const(1); code.Op(0x71); code.Mem(0x36, 2);
        }
    }
    if (lexical) {
        auto depth = temporary ? temp_scopes.back().cleanup_depth + 1 : cleanups.size() + 1;
        cleanups.push_back({ CleanupAction::ClearOwner, offset, nullptr, {}, nullopt, depth });
    }
}

inline void Function::ClearEffectOwner(uint32_t offset) {
    if (c.region_cursors) { FrameAddress(offset + 36); code.I32Const(0); code.Mem(0x36, 2); }
    // Keep all dying-owner evidence until every abandoning check has run.
    code.OpU(0x23, c.pending_effect); code.Op(0x45); Begin(0x04);
    FrameAddress(offset + 8); code.I32Const(0); code.Mem(0x36, 2); End();
}

inline void Function::EnterEffectFrame() {
    if (!c.Effects()) return;
    code.OpU(0x23, c.effect_frames); Set(previous_effect_frame);
    FrameAddress(effect_frame); Get(previous_effect_frame); code.Mem(0x36, 2);
    FrameAddress(effect_frame + 4); Get(framebase); code.Mem(0x36, 2);
    FrameAddress(effect_frame + 8);
    if (owner_entries.empty()) code.I32Const(0); else FrameAddress(owner_entries.front().offset);
    code.Mem(0x36, 2);
    for (size_t i = 0; i < owner_entries.size(); i++) {
        auto offset = owner_entries[i].offset;
        FrameAddress(offset);
        if (i + 1 < owner_entries.size()) FrameAddress(owner_entries[i + 1].offset); else code.I32Const(0);
        code.Mem(0x36, 2);
        FrameAddress(offset + 8); code.I32Const(0); code.Mem(0x36, 2);
        if (c.region_cursors) { FrameAddress(offset + 36); code.I32Const(0); code.Mem(0x36, 2); }
    }
    FrameAddress(effect_frame); code.OpU(0x24, c.effect_frames);
    if (c.effect_globals.count(spec)) {
        auto global = c.effect_globals.at(spec);
        code.OpU(0x23, global); Set(previous_mailbox);
        FrameAddress(mailbox); Get(framebase); code.Mem(0x36, 2);
        auto owned = c.OwnedEffectOrdinals(spec);
        for (size_t k = 0; k < owned.size(); k++) {
            auto ordinal = owned[k]; auto metadata = mailbox + 4 + uint32_t(k) * 12;
            FrameAddress(metadata); Get(*resultdestinations[ordinal]); code.Mem(0x36, 2);
            LocationAddress(TailHeaderLocation({ spec->rets[ordinal], AddressLocal { *resultdestinations[ordinal] } }));
            auto header = Save(I32); auto base = RegionCursor(header);
            FrameAddress(metadata + 8); Get(base); code.Mem(0x36, 2);
            if (Compiler::ArrayImageEffectResult(spec->rets[ordinal]))
                SetArrayImageAnchor(header, base, spec->rets[ordinal]);
        }
        FrameAddress(mailbox); code.OpU(0x24, global);
    }
}

inline void Function::LeaveEffectFrame() {
    if (!c.Effects()) return;
    if (c.effect_globals.count(spec)) { Get(previous_mailbox); code.OpU(0x24, c.effect_globals.at(spec)); }
    Get(previous_effect_frame); code.OpU(0x24, c.effect_frames);
}

inline void Function::SkipDyingEffectOwner(uint32_t header,
        const optional<ConstructionDestination::EnumGuard> &guard, uint32_t done) {
    if (!c.Effects()) return;
    auto finished = Begin();
    code.OpU(0x23, c.pending_effect); code.Op(0x45); Br(finished, true);
    code.OpU(0x23, c.pending_effect); code.Mem(0x28, 2); auto target_frame = Save(I32);
    code.OpU(0x23, c.effect_frames); auto frame = Save(I32);
    auto frames = Begin(0x03);
    Get(frame); code.Op(0x45); Br(finished, true);
    Get(frame); code.Mem(0x28, 2, 4); Get(target_frame); code.Op(0x49); Br(finished, true);
    Get(frame); code.Mem(0x28, 2, 8); auto entry = Save(I32);
    auto entries_done = Begin(); auto entries = Begin(0x03);
    Get(entry); code.Op(0x45); Br(entries_done, true);
    Get(entry); code.Mem(0x28, 2, 8); Begin(0x04);
    Get(entry); code.Mem(0x28, 2, 4); auto registered = Save(I32);
    Get(header); Get(registered); code.Op(0x46); Br(done, true);
    if (guard) { Get(guard->owner_header); Get(registered); code.Op(0x46); Br(done, true); }
    Get(entry); code.Mem(0x28, 2, 12); auto interior = Save(I32);
    Get(interior); Begin(0x04);
    Get(registered); code.Mem(0x28, 2); auto base = Save(I32);
    Get(header); code.Op(0xad); Get(base); code.Op(0xad); code.Op(0x5a);
    Get(header); code.Op(0xad); code.I64Const(owner_control_bytes); code.Op(0x7c);
    Get(base); code.Op(0xad); Get(interior); code.Op(0xad); code.Op(0x7c); code.Op(0x58); code.Op(0x71);
    Br(done, true); End(); End();
    Get(entry); code.Mem(0x28, 2); Set(entry); Br(entries); End(); End();
    Get(frame); code.Mem(0x28, 2); Set(frame); Br(frames); End(); End();
}

inline void Function::PropagateEffect(Line line) {
    if (!spec) { Abort(line, "uncaught nonlocal return"); return; }
    EmitCleanups(0, true);
    LeaveEffectFrame(); Get(framebase); code.OpU(0x24, G_SCRATCH_TOP);
    for (auto type : results) Zero(W(type));
    code.Op(0x0f);
}

inline void Function::CheckPendingEffect(Line line) {
    if (!c.Effects()) return;
    code.OpU(0x23, c.pending_effect); Begin(0x04);
    if (c.effect_globals.count(spec)) {
        code.OpU(0x23, c.pending_effect); FrameAddress(mailbox); code.Op(0x46); Begin(0x04);
        auto layout = c.MailboxLayout(spec);
        if (!c.OwnedEffectOrdinals(spec).empty()) LandOwnedEffect();
        else for (size_t i = 0; i < results.size(); i++) {
                FrameAddress(mailbox + layout.fields[i]); Load(results[i]); Set(resultlocals[i]);
            }
        EmitCleanups(0, true);
        code.I32Const(0); code.OpU(0x24, c.pending_effect); Br(function_done); End();
    }
    PropagateEffect(line); End();
}

inline void Function::NonlocalReturn(Return *node) {
    auto target = node->targetspec;
    if (!target || !c.effect_globals.count(target)) Fail(node->line, "nonlocal return has no active mailbox contract");
    if (!c.OwnedEffectOrdinals(target).empty()) { NonlocalOwnedReturn(node); return; }
    code.OpU(0x23, c.effect_globals.at(target)); auto destination = Save(I32);
    Get(destination); code.Op(0x45); TrapIf(node->line, "nonlocal return target is not active");
    vector<uint32_t> values; for (auto type : target->rets) values.push_back(Local(type));
    SetResults(node->vals, target->rets, values, node->line);
    auto layout = c.MailboxLayout(target);
    for (size_t i = 0; i < values.size(); i++) {
        auto field = OffsetLocation({ target->rets[i], AddressLocal { destination } }, layout.fields[i], target->rets[i]);
        StoreCopy(field, { target->rets[i], values[i], c.Aggregate(target->rets[i]) ? CapturedValue::CopiedFixed : CapturedValue::Immediate });
    }
    Get(destination); code.OpU(0x24, c.pending_effect);
    CheckPendingEffect(node->line);
}

} // namespace goose::direct_wasm
