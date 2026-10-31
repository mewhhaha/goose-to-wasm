#pragma once
namespace goose::direct_wasm {

// The same SCC bound as the pinned backend: recursive back edges retain no
// transient owners, and external callees start above the caller's live owners.
inline uint32_t Compiler::BoundRegions() {
    unordered_map<FnSpec *, uint32_t> index, low;
    unordered_map<FnSpec *, uint64_t> need;
    vector<FnSpec *> stack;
    unordered_set<FnSpec *> active;
    uint32_t next = 0;
    function<void(FnSpec *)> visit = [&](FnSpec *node) {
        index[node] = low[node] = next++;
        stack.push_back(node); active.insert(node);
        for (auto &call : region_calls[node]) {
            if (!index.count(call.callee)) { visit(call.callee); low[node] = min(low[node], low[call.callee]); }
            else if (active.count(call.callee)) low[node] = min(low[node], index[call.callee]);
        }
        if (low[node] != index[node]) return;
        vector<FnSpec *> component;
        for (;;) {
            auto member = stack.back(); stack.pop_back(); active.erase(member); component.push_back(member);
            if (member == node) break;
        }
        unordered_set<FnSpec *> members(component.begin(), component.end());
        uint64_t bound = 0;
        for (auto member : component) {
            bound = max(bound, uint64_t(region_own[member]));
            for (auto &call : region_calls[member]) {
                if (members.count(call.callee)) {
                    if (call.live) Fail(call.line, "internal: recursive call retains transient data regions");
                } else bound = max(bound, uint64_t(call.live) + need[call.callee]);
            }
        }
        for (auto member : component) need[member] = bound;
    };
    for (auto spec : specs) if (!index.count(spec)) visit(spec);
    if (!index.count(nullptr)) visit(nullptr);
    uint64_t peak = need[nullptr];
    for (auto spec : specs) if (spec->sf->isexport || spec->sf == ast.MainFunction()) peak = max(peak, need[spec]);
    peak += global_regions.size();
    if (peak > UINT32_MAX) Fail({}, "data-region count exceeds wasm32 limits");
    return uint32_t(peak);
}

inline void Function::RecordRegionCall(FnSpec *callee, Line line) {
    if (c.needs_regions && !callee->sf->isextern)
        c.region_calls[spec].push_back({ callee, region_live, line });
}

inline void Function::ActivationLimit(uint32_t top, Line line) {
    if (!c.needs_regions) return;
    Get(top); code.OpU(0x23, G_ACTIVATION_LIMIT); code.Op(0x4b);
    TrapIf(line, "activation/scratch arena exhausted");
}

// Capture physical source metadata before publishing any receiving header.
inline Function::CapturedSequence Function::CaptureSequence(Node *node, bool elements) {
    if (auto slice = Is<SliceExpr>(node)) {
        SliceView(slice); return { Save(I64), node->exprtype, {} };
    }
    if (auto call = Is<Call>(node); call && call->builtin == B_COPY) {
        return CaptureSequence(call->FirstArg(), elements);
    }
    TypeExpr *natural = node->exprtype;
    if (auto text = Is<StrLit>(node)) {
        auto address = c.Text(text->val);
        code.I64Const(int64_t((uint64_t(text->val.size()) << 32) | address));
        return { Save(I64), natural, {} };
    }
    if (Is<Ident>(node) || Is<Index>(node) || (Is<Dot>(node) && Is<Dot>(node)->IsField())) {
        auto place = PinPlace(node); natural = place.storage_type; ReadLocation(place, natural);
    } else if (auto inlined = Is<InlineBlock>(node)) {
        auto types = inlined->spec ? inlined->spec->rets : Values(node);
        if (types.size() != 1) Fail(node->line, "array construction requires one inline result");
        natural = types[0]; EmitInline(inlined, false, {}, elements);
    } else if (auto call = Is<Call>(node); call && call->builtin == B_DEFAULT) {
        natural = call->rettypes.at(0); EmitCall(call, false);
    } else if (auto call = Is<Call>(node); call && call->builtin < 0) {
        auto types = call->fvbody ? call->rettypes : call->spec ? call->spec->rets : vector<TypeExpr *> {};
        if (types.size() != 1) Fail(node->line, "array construction requires one source value");
        natural = types[0]; EmitCall(call, false, {}, elements);
    } else {
        if (Compiler::RegionArray(natural) && elements && !Compiler::RuntimeLimited(natural)) {
            auto temporary = TemporaryDestination(natural, node->line); temporary.elements = true;
            ConstructRegionInto(node, temporary); LocationAddress(temporary.location);
        } else if (Compiler::RegionArray(natural)) Materialize(node, natural, false);
        else Expr(node);
    }
    if (natural->kind == TY_REF) { natural = natural->ref->sub; Load(natural); }
    optional<uint32_t> capacity;
    if (Compiler::RuntimeLimited(natural)) {
        auto header = Save(I32);
        Get(header); code.Mem(0x28, 2, 12); capacity = Save(I32); Get(header);
    }
    if (natural->kind == TY_ARRAY) PackArrayView(natural);
    else if (natural->kind != TY_SLICE) Fail(node->line, "array construction requires an array or slice");
    return { Save(I64), natural, capacity };
}

inline void Function::ConstructionView(Node *node, bool elements) {
    auto source = CaptureSequence(node, elements); Get(source.view);
}

inline void Function::CheckRegionDestination(TypeExpr *type, const ConstructionDestination &destination, Line line) {
    auto target = destination.location.storage_type;
    if (!Compiler::RegionArray(target) ||
        c.FixedLayout(type->arr->sub).size != c.FixedLayout(target->arr->sub).size)
        Fail(line, "owned dynamic element adaptation is not supported at this destination");
}

inline Function::RegionResultPlan Function::PlanRegionResults(const vector<TypeExpr *> &types,
        const ResultDestinations &receivers, Line line, bool run, bool inlined) {
    RegionResultPlan plan { ResultDestinations(types.size()), ResultDestinations(types.size()), ResultDestinations(types.size()) };
    for (size_t i = 0; i < types.size(); i++) if (Compiler::RegionArray(types[i])) {
        if (!receivers.empty() && receivers.size() != types.size()) Fail(line, "owned result channel arity mismatch");
        // An empty ordinal can receive a fixed value after normal conversion.
        if (receivers.empty() || !receivers[i]) {
            plan.producers[i] = TemporaryDestination(types[i], line); plan.values[i] = plan.producers[i]; continue;
        }
        plan.values[i] = receivers[i];
        CheckRegionDestination(types[i], *receivers[i], line);
        auto receiving = receivers[i]->location.storage_type;
        auto reprefix = types[i]->arr->akind == A_VAR && receiving->arr->akind == A_VAR &&
                        Compiler::LengthStorage(types[i]) != Compiler::LengthStorage(receiving);
        auto capacity_adapter = Compiler::RuntimeLimited(types[i]) != Compiler::RuntimeLimited(receiving) &&
                                !(inlined && types[i]->arr->akind == A_VAR);
        if (capacity_adapter || (reprefix && !run)) {
            plan.producers[i] = TemporaryDestination(types[i], line); plan.copies[i] = receivers[i];
        } else plan.producers[i] = receivers[i];
    }
    return plan;
}

inline void Function::PublishRegionResults(const vector<TypeExpr *> &types, const RegionResultPlan &plan, Line line) {
    auto check = [&](size_t i) {
        if (!plan.values[i] || plan.values[i]->elements) return;
        auto &destination = *plan.values[i]; auto type = destination.location.storage_type;
        if (type->arr->akind != A_VAR) return;
        LocationAddress(destination.location); code.Mem(0x28, 2, 4); code.Op(0xad);
        CheckArrayLength(type, Save(I64), line);
    };
    if (none_of(plan.copies.begin(), plan.copies.end(), [](auto &destination) { return bool(destination); })) {
        for (size_t i = 0; i < types.size(); i++) check(i);
        return;
    }
    vector<uint32_t> values(types.size());
    for (size_t i = types.size(); i-- > 0;) values[i] = Save(types[i]);
    // Capture every natural result before adapting any ordinal.
    for (size_t i = 0; i < types.size(); i++) {
        if (plan.copies[i]) {
            ConstructRegionFromCaptured(types[i], values[i], *plan.copies[i], line);
            LocationAddress(plan.copies[i]->location); Set(values[i]);
        } else check(i);
    }
    for (auto value : values) Get(value);
}

inline vector<const VarDef *> Function::BindNamedResults(Block *body, SFunction *target,
        const vector<TypeExpr *> &types, const ResultDestinations &destinations, bool inlined) {
    vector<const VarDef *> added;
    for (size_t i = 0; i < types.size(); i++) {
        if (!Compiler::RegionArray(types[i]) || destinations.size() != types.size() || !destinations[i]) continue;
        auto candidate = goose::NamedResultOf(body, target, types.size(), i);
        if (!candidate || named_regions.count(candidate) || !Compiler::RegionArray(candidate->type)) continue;
        // The frontend requires identical array element types for this
        // construction. DetectNrvo also binds a growable local's elements
        // directly to a variable-array result; later results observe aliases.
        auto same_mode = candidate->type->arr->akind == types[i]->arr->akind;
        if (same_mode && types[i]->arr->akind == A_VAR)
            same_mode = Compiler::LengthStorage(candidate->type) == Compiler::LengthStorage(types[i]);
        auto grow_to_variable = Compiler::GrowableArray(candidate->type) && types[i]->arr->akind == A_VAR;
        if (!same_mode && !grow_to_variable) continue;
        if (inlined && !Compiler::GrowableArray(candidate->type)) {
            auto receiving = destinations[i]->location.storage_type;
            if (destinations[i]->elements || candidate->type->arr->akind != receiving->arr->akind) continue;
            if (receiving->arr->akind == A_VAR &&
                Compiler::LengthStorage(candidate->type) != Compiler::LengthStorage(receiving)) continue;
        } else if (inlined) {
            auto receiving = destinations[i]->location.storage_type;
            auto raw = destinations[i]->elements || Compiler::GrowableArray(receiving);
            if (raw ? (!Compiler::GrowableArray(receiving) && receiving->arr->akind != A_VAR)
                    : receiving->arr->akind != A_VAR) continue;
        }
        CheckRegionDestination(candidate->type, *destinations[i], candidate->line);
        named_regions.emplace(candidate, *destinations[i]); added.push_back(candidate);
    }
    return added;
}

inline void Function::ShareRegion(const Location &place, const ConstructionDestination &destination) {
    LocationAddress(place); auto local = Save(I32);
    LocationAddress(destination.location); auto result = Save(I32);
    for (uint32_t offset : { 0u, 8u }) {
        Get(local); Get(result); code.Mem(0x28, 2, offset); code.Mem(0x36, 2, offset);
    }
    Get(local); code.I32Const(0); code.Mem(0x36, 2, 4);
    Get(local); code.I32Const(0); code.Mem(0x36, 2, 12);
}

inline void Function::ConstructRegionFromCaptured(TypeExpr *source_type, uint32_t source,
        const ConstructionDestination &destination, Line line) {
    Get(source);
    if (source_type->kind == TY_REF) { source_type = source_type->ref->sub; Load(source_type); }
    TypeExpr *element;
    optional<uint32_t> capacity;
    if (Compiler::RuntimeLimited(source_type)) {
        auto header = Save(I32);
        Get(header); code.Mem(0x28, 2, 12); capacity = Save(I32); Get(header);
    }
    if (source_type->kind == TY_ARRAY) { element = source_type->arr->sub; PackArrayView(source_type); }
    else if (source_type->kind == TY_SLICE) element = source_type->sub;
    else Fail(line, "owned result adaptation requires an array or slice");
    if (c.FixedLayout(element).size != c.FixedLayout(destination.location.storage_type->arr->sub).size)
        Fail(line, "owned result element adaptation is not supported");
    auto view = Save(I64); ConstructRegionView(view, destination, line, capacity);
}

inline void Function::ConstructRegionView(uint32_t source, const ConstructionDestination &destination, Line line,
                                          optional<uint32_t> capacity) {
    auto element = destination.location.storage_type->arr->sub;
    LocationAddress(destination.location); auto header = Save(I32);
    Get(header); code.Mem(0x28, 2); auto base = Save(I32);
    Get(source); code.I64Const(32); code.Op(0x88); auto count = Save(I64);
    CheckArrayLength(destination.location.storage_type, count, line, destination.elements);
    if (Compiler::RuntimeLimited(destination.location.storage_type)) {
        if (destination.lifetime == ConstructionDestination::Existing) {
            Get(count); Get(header); code.Mem(0x28, 2, 12); code.Op(0xad); code.Op(0x56);
            TrapIf(line, "array capacity exceeded");
        } else {
            if (capacity) { Get(*capacity); code.Op(0xad); } else Get(count);
            auto cap = Save(I64); ReserveRegion(header, cap, element, line);
            Get(header); Get(cap); code.Op(0xa7); code.Mem(0x36, 2, 12);
        }
    }
    Get(header); code.I32Const(0); code.Mem(0x36, 2, 4);
    ReserveRegion(header, count, element, line);
    Get(base); Get(source); code.Op(0xa7); Get(count); code.Op(0xa7);
    code.I32Const(int32_t(c.Size(element).size)); code.Op(0x6c); code.Copy();
    Get(header); Get(count); code.Op(0xa7); code.Mem(0x36, 2, 4);
}

inline void Function::ConstructRegion(Node *node, const Location &place, optional<uint32_t> global_region) {
    AcquireRegion(place, node ? node->line : place.storage_type->line, global_region);
    ConstructRegionInto(node, { place, global_region ? ConstructionDestination::Static : ConstructionDestination::Block });
}

inline void Function::AcquireRegion(const Location &place, Line line, optional<uint32_t> global_region) {
    c.HeaderLayout(place.storage_type);
    LocationAddress(place); auto header = Save(I32);
    if (global_region) code.I32Const(int32_t(*global_region));
    else code.OpU(0x23, G_REGION_NEXT);
    auto region = Save(I32);
    Get(region); code.OpU(0x23, G_REGION_COUNT); code.Op(0x4f);
    TrapIf(line, "data-region count exhausted");
    if (!global_region) {
        Get(region); code.I32Const(1); code.Op(0x6a); code.OpU(0x24, G_REGION_NEXT);
        if (region_live == UINT32_MAX) Fail(line, "too many live data regions");
        region_peak = max(region_peak, ++region_live);
    }
    code.OpU(0x23, G_REGION_BASE); Get(region); code.OpU(0x23, G_REGION_BYTES); code.Op(0x6c); code.Op(0x6a);
    auto base = Save(I32);
    Get(header); Get(base); code.Mem(0x36, 2);
    Get(header); code.I32Const(0); code.Mem(0x36, 2, 4);
    Get(header); Get(base); code.OpU(0x23, G_REGION_BYTES); code.Op(0x6a); code.Mem(0x36, 2, 8);
    Get(header); code.I32Const(0); code.Mem(0x36, 2, 12);
}

inline void Function::ConstructRegionInto(Node *node, const ConstructionDestination &destination) {
    auto place = destination.location;
    auto type = place.storage_type;
    c.HeaderLayout(type);
    auto element = type->arr->sub;
    auto line = node ? node->line : type->line;
    if (auto literal = Is<ArrayLit>(node); literal && literal->capexpr) {
        if (!Compiler::RuntimeLimited(type)) {
            // A capacity literal keeps its natural range check, reservation
            // and effects even after an optimizer exposes it in another kind.
            auto natural = c.ast.ArrayOf(element, A_LIMITED, line);
            auto temporary = TemporaryDestination(natural, line);
            ConstructRegionInto(node, temporary);
            LocationAddress(temporary.location); auto source = Save(I32);
            ConstructRegionFromCaptured(natural, source, destination, line); return;
        }
        To(literal->capexpr, c.ast.inttypes[IS_I64]); auto capacity = Save(I64);
        Get(capacity); code.I64Const(0); code.Op(0x53);
        Get(capacity); code.I64Const(UINT32_MAX); code.Op(0x56); code.Op(0x72);
        TrapIf(line, "array capacity out of range");
        LocationAddress(place); auto header = Save(I32);
        ReserveRegion(header, capacity, element, line);
        Get(header); Get(capacity); code.Op(0xa7); code.Mem(0x36, 2, 12);
        Get(header); code.I32Const(0); code.Mem(0x36, 2, 4); return;
    }
    if (auto copy = Is<Call>(node); copy && copy->builtin == B_COPY) {
        ConstructRegionInto(copy->FirstArg(), destination); return;
    }
    if (auto id = Is<Ident>(node); id && named_regions.count(id->vdef)) {
        auto &named = named_regions.at(id->vdef).location.storage;
        auto &receiving = place.storage;
        auto left = get_if<Slot>(&named), right = get_if<Slot>(&receiving);
        auto same = left && right ? left->kind == right->kind && left->index == right->index
                    : !left && !right && get<AddressLocal>(named).index == get<AddressLocal>(receiving).index;
        if (same) {
            // Data already lives at this result. Its private header keeps
            // later growth from changing the length published here.
            LocationAddress(PinPlace(node)); code.Mem(0x28, 2, 4); code.Op(0xad); auto count = Save(I64);
            CheckArrayLength(type, count, line, destination.elements);
            LocationAddress(place); Get(count); code.Op(0xa7); code.Mem(0x36, 2, 4);
            if (Compiler::RuntimeLimited(type)) {
                LocationAddress(place);
                LocationAddress(PinPlace(node)); code.Mem(0x28, 2, 12); code.Mem(0x36, 2, 12);
            }
            return;
        }
    }
    if (auto block = Is<Block>(node)) {
        BlockInto(block, { type }, { Local(I32) }, { destination }); return;
    }
    if (auto conditional = Is<IfExpr>(node)) {
        vector<TypeExpr *> types { type }; vector<uint32_t> values { Local(I32) };
        ResultDestinations destinations { destination };
        Truth(conditional->cond); Begin(0x04);
        BlockInto(conditional->thenb, types, values, destinations);
        if (conditional->elseb) {
            Else();
            if (Values(conditional->elseb).empty()) Discard(conditional->elseb);
            else SetResults({ conditional->elseb }, types, values, line, destinations);
        }
        End(); return;
    }
    if (Is<LoopExpr>(node) || Is<EarlyBlock>(node) || Is<MatchExpr>(node)) {
        ControlValue(node, { type }, { Local(I32) }, { destination }); return;
    }
    if (auto call = Is<Call>(node); call && call->builtin < 0 && call->spec &&
        call->spec->rets.size() == 1 && Compiler::RegionArray(call->spec->rets[0])) {
        EmitCall(call, false, { destination }); code.Op(0x1a); return;
    }
    if (auto inlined = Is<InlineBlock>(node); inlined && inlined->spec &&
        inlined->spec->rets.size() == 1 && Compiler::RegionArray(inlined->spec->rets[0])) {
        EmitInline(inlined, false, { destination }); code.Op(0x1a); return;
    }
    LocationAddress(place); auto header = Save(I32);
    Get(header); code.Mem(0x28, 2); auto base = Save(I32);

    if (!node) {
        Get(header); code.I32Const(0); code.Mem(0x36, 2, 4);
        Get(header); code.I32Const(0); code.Mem(0x36, 2, 12);
        code.I64Const(0); auto count = Save(I64); ReserveRegion(header, count, element, line); return;
    }

    uint32_t count;
    auto cleanup_depth = cleanups.size();
    bool check_abandoned = false;
    if (auto array = Is<ArrayLit>(node)) {
        auto size = array->fillval ? static_cast<IntLit *>(array->fillcount)->val : int64_t(array->elems.size());
        code.I64Const(size); count = Save(I64);
        CheckArrayLength(type, count, line, destination.elements);
        Get(header); code.I32Const(size > UINT32_MAX ? -1 : int32_t(size)); code.Mem(0x36, 2, 4);
        if (Compiler::RuntimeLimited(type)) {
            Get(header); code.I32Const(size > UINT32_MAX ? -1 : int32_t(size)); code.Mem(0x36, 2, 12);
        }
        // Existing owners and callee result channels can survive an exit
        // during element evaluation. Commit/check the published extent on
        // that exit, while ordinary construction keeps its effect ordering.
        check_abandoned = destination.lifetime == ConstructionDestination::Existing ||
                          destination.lifetime == ConstructionDestination::Caller;
        if (check_abandoned) cleanups.push_back({ CleanupAction::CheckAbandonedRegion, header, element, line });
        if (array->fillval) {
            auto value = CaptureBorrowed(array->fillval, element);
            ReserveRegion(header, count, element, node->line);
            auto index = Local(I32); code.I32Const(0); Set(index);
            auto done = Begin(), loop = Begin(0x03);
            Get(index); Get(count); code.Op(0xa7); code.Op(0x4f); Br(done, true);
            Get(base); Get(index); code.I32Const(int32_t(c.Size(element).size)); code.Op(0x6c); code.Op(0x6a);
            Get(value.value_local); Store(element);
            Get(index); code.I32Const(1); code.Op(0x6a); Set(index); Br(loop); End(); End();
        } else {
            if (array->elems.empty()) ReserveRegion(header, count, element, node->line);
            for (size_t index = 0; index < array->elems.size(); index++) {
                auto value = CaptureBorrowed(array->elems[index], element);
                code.I64Const(int64_t(index + 1)); auto prefix = Save(I64);
                ReserveRegion(header, prefix, element, node->line);
                Get(base); code.I32Const(int32_t(index * c.Size(element).size)); code.Op(0x6a);
                Get(value.value_local); Store(element);
            }
        }
    } else {
        auto source = CaptureSequence(node);
        ConstructRegionView(source.view, destination, line, source.capacity); return;
    }
    Get(header); Get(count); code.Op(0xa7); code.Mem(0x36, 2, 4);
    if (check_abandoned) CloseCleanups(cleanup_depth);
}

// Validate the final length before multiplying or adding a pointer. All
// counts use i64 so negative or overflowing source counts cannot wrap in i32.
inline void Function::ReserveRegion(uint32_t header, uint32_t count, TypeExpr *element, Line line) {
    Get(header); code.Mem(0x28, 2, 8);
    Get(header); code.Mem(0x28, 2); code.Op(0x6b); code.Op(0xad);
    code.I64Const(c.FixedLayout(element).size); code.Op(0x80);
    auto capacity = Save(I64);
    Get(count); Get(capacity); code.Op(0x56); TrapIf(line, "data region exhausted");
    Get(header); code.Mem(0x28, 2); Get(count); code.Op(0xa7);
    code.I32Const(int32_t(c.Size(element).size)); code.Op(0x6c); code.Op(0x6a);
    auto top = Save(I32); EnsureMemory(top, line);
}

inline void Function::ReserveArray(uint32_t header, uint32_t count, TypeExpr *type, Line line) {
    if (Compiler::RuntimeLimited(type)) {
        Get(count); Get(header); code.Mem(0x28, 2, 12); code.Op(0xad); code.Op(0x56);
        TrapIf(line, "array capacity exceeded");
    }
    ReserveRegion(header, count, type->arr->sub, line);
}

inline void Function::CheckArrayLength(TypeExpr *type, uint32_t count, Line line, bool elements) {
    if (elements || type->kind != TY_ARRAY || type->arr->akind != A_VAR) return;
    auto bits = IntBits(Compiler::LengthStorage(type));
    if (bits >= 64) return;
    Get(count); code.I64Const(int64_t((UINT64_C(1) << bits) - 1)); code.Op(0x56);
    TrapIf(line, "array length exceeds storage range");
}

} // namespace goose::direct_wasm
