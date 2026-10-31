#pragma once
namespace goose::direct_wasm {

inline vector<TypeExpr *> Function::Values(Node *n) {
    if (!n) return {};
    if (auto call = Is<Call>(n); call && call->rettypes.size() > 1) return call->rettypes;
    if (auto inlined = Is<InlineBlock>(n); inlined && inlined->spec && inlined->spec->rets.size() > 1)
        return inlined->spec->rets;
    if (!n->exprtype || n->exprtype->kind == TY_VOID) return {};
    return { n->exprtype };
}
inline vector<TypeExpr *> Function::NaturalResults(Node *node) {
    if (auto call = Is<Call>(node); call && call->builtin < 0 && !call->fvbody && call->spec)
        return call->spec->rets;
    if (auto call = Is<Call>(node); call && !call->rettypes.empty()) return call->rettypes;
    if (auto inlined = Is<InlineBlock>(node); inlined && inlined->spec) return inlined->spec->rets;
    return Values(node);
}
inline void Function::To(Node *n, TypeExpr *t) {
    auto values = Values(n);
    if (values.size() != 1) Fail(n ? n->line : Line{}, "expected one runtime value");
    if (t->kind == TY_REF && values[0]->kind != TY_REF) { Address(n); return; }
    Expr(n); Convert(values[0], t, n->line);
}
inline void Function::Discard(Node *n) {
    if (!n) return;
    Expr(n); for (size_t i = 0; i < Values(n).size(); i++) code.Op(0x1a);
}
inline void Function::BlockInto(Block *b, const vector<TypeExpr *> &types, const vector<uint32_t> &slots,
                                const ResultDestinations &destinations, size_t first_statement) {
    auto cleanup_depth = cleanups.size();
    auto private_depth = private_headers.size();
    auto live = region_live;
    if (c.needs_regions) {
        code.OpU(0x23, G_REGION_NEXT);
        cleanups.push_back({ CleanupAction::RestoreRegionNext, Save(I32) });
    }
    for (size_t i = first_statement; i < b->stmts.size(); i++) {
        auto s = b->stmts[i];
        if (auto declaration = Is<VarDecl>(s)) Decl(declaration);
        else { auto scope = BeginTempScope(s); Discard(s); EndTempScope(scope); }
    }
    if (b->tail) {
        auto scope = BeginTempScope(b->tail);
        // A function may end in a void-typed infinite loop whose nested
        // returns supply its results. The checker already proves that such
        // a tail cannot fall through; the loop itself produces no values.
        if (types.empty() || Values(b->tail).empty()) Discard(b->tail);
        else SetResults({ b->tail }, types, slots, b->line, destinations);
        EndTempScope(scope);
    }
    if (c.needs_regions) { CloseCleanups(cleanup_depth); region_live = live; }
    private_headers.resize(private_depth);
}
inline void Function::CaptureResult(TypeExpr *type, uint32_t slot) {
    // A later result expression can mutate the aggregate just evaluated.
    // Capture its value now, rather than retaining its address until the
    // epilogue. The same rule applies to returns from an inlined body and
    // value blocks; each static result site has its own activation storage.
    if (c.Aggregate(type)) {
        auto captured = CopyCaptured(CaptureStack(type)); Get(captured.value_local);
    }
    Set(slot);
}
inline void Function::SetResults(const vector<Node *> &nodes, const vector<TypeExpr *> &types,
                                 const vector<uint32_t> &slots, Line l, const ResultDestinations &destinations) {
    for (size_t i = 0; i < types.size(); i++) if (Compiler::RegionOwner(types[i]) &&
        (destinations.size() != types.size() || !destinations[i]))
        Fail(l, "owned dynamic result is not supported without a receiving destination");
    if (nodes.size() == types.size()) {
        for (size_t i = 0; i < nodes.size(); i++) {
            if (Compiler::RegionOwner(types[i])) {
                ConstructRegionInto(nodes[i], *destinations[i]);
                LocationAddress(destinations[i]->location); Set(slots[i]);
            } else { To(nodes[i], types[i]); CaptureResult(types[i], slots[i]); }
        }
    } else if (nodes.size() == 1 && Values(nodes[0]).size() == types.size()) {
        auto vt = NaturalResults(nodes[0]);
        ResultExpression(nodes[0], destinations);
        vector<uint32_t> captured(types.size());
        for (size_t i = types.size(); i-- > 0;) captured[i] = Save(vt[i]);
        for (size_t i = 0; i < types.size(); i++) {
            if (Compiler::RegionOwner(types[i])) {
                if (!Compiler::RegionOwner(vt[i])) ConstructRegionFromCaptured(vt[i], captured[i], *destinations[i], l);
                LocationAddress(destinations[i]->location); Set(slots[i]);
            } else { Get(captured[i]); Convert(vt[i], types[i], l); CaptureResult(types[i], slots[i]); }
        }
    } else Fail(l, "return arity is not supported by the direct backend");
}

inline void Function::ResultExpression(Node *node, const ResultDestinations &destinations) {
    if (auto call = Is<Call>(node)) EmitCall(call, false, destinations);
    else if (auto inlined = Is<InlineBlock>(node)) EmitInline(inlined, false, destinations);
    else {
        if (any_of(destinations.begin(), destinations.end(), [](auto &d) { return bool(d); }))
            Fail(node->line, "owned multi-result expression requires a supported producer");
        Expr(node);
    }
}

inline TypeExpr *Function::Object(Node *n) {
    Expr(n); auto t = n->exprtype;
    if (t->kind == TY_REF) { Load(t->ref->sub); t = t->ref->sub; }
    return t;
}
// Push a packed i64 (low 32 bits address, high 32 bits element count).
inline void Function::View(Node *n) {
    auto t = Object(n);
    if (t->kind == TY_SLICE) return;
    if (t->kind != TY_ARRAY) Fail(n->line, "expected an array or slice");
    PackArrayView(t);
}
inline void Function::Address(Node *n) {
    if (auto id = Is<Ident>(n)) {
        auto s = Lookup(id->vdef, n->line);
        if (s.type->kind == TY_REF && n->exprtype->kind != TY_REF) Read(s);
        else SlotAddress(s);
        return;
    }
    if (auto idx = Is<Index>(n)) {
        auto t = idx->obj->exprtype; if (t->kind == TY_REF) t = t->ref->sub;
        auto elem = t->kind == TY_ARRAY ? t->arr->sub : t->kind == TY_SLICE ? t->sub : nullptr;
        if (!elem) Fail(n->line, "indexing this type is not supported");
        View(idx->obj); auto view = Save(I64);
        To(idx->idx, c.ast.inttypes[IS_U64]); auto pos = Save(I64);
        if (!idx->nobc) {
            Get(pos); Get(view); code.I64Const(32); code.Op(0x88); code.Op(0x5a);
            TrapIf(n->line, "array index out of bounds");
        }
        Get(view); code.Op(0xa7); Get(pos); code.Op(0xa7);
        code.I32Const(int32_t(c.Size(elem).size)); code.Op(0x6c); code.Op(0x6a); return;
    }
    if (auto dot = Is<Dot>(n); dot && dot->IsField()) {
        auto t = Object(dot->obj);
        c.FieldType(t, dot->fieldidx);
        auto off = c.FieldOffset(t, size_t(dot->fieldidx));
        if (off) { code.I32Const(int32_t(off)); code.Op(0x6a); }
        return;
    }
    if (auto u = Is<Unary>(n); u && u->op == T_BITAND) { Address(u->child); return; }
    if (n->exprtype && n->exprtype->kind == TY_REF) { Expr(n); return; }
    if (n->exprtype && c.Aggregate(n->exprtype)) { Expr(n); return; }
    Fail(n->line, "this expression has no addressable direct representation");
}

inline Function::PreparedDecl Function::PrepareDecl(VarDecl *n) {
    PreparedDecl prepared;
    auto &slots = prepared.slots;
    for (auto v : n->defs) {
        if (v->type->kind == TY_FN) Fail(n->line, "runtime function values require inlining");
        // A runtime-limited named result is an image whose length/capacity
        // header itself lives at the receiving destination. Later result
        // expressions can mutate that same header, as in the native target.
        auto named = named_regions.find(v);
        if (!n->isglobal && Compiler::WholeHeaderOwner(v->type) && named != named_regions.end()) {
            LocationAddress(named->second.location);
            Slot slot { Slot::ADDRESS, Save(I32), v->type };
            vars[v] = slot; slots.push_back(slot); continue;
        }
        slots.push_back(n->isglobal ? Lookup(v, n->line) : Bind(v));
        if (!n->isglobal && Compiler::RegionOwner(v->type))
            private_headers.push_back({ TailHeaderLocation({ v->type, slots.back() }), cleanups.size() });
    }
    prepared.destinations.resize(slots.size());
    for (size_t i = 0; i < slots.size(); i++) if (Compiler::RegionOwner(slots[i].type)) {
        Location place { slots[i].type, slots[i] };
        if (auto named = named_regions.find(n->defs[i]); named != named_regions.end()) {
            if (Compiler::WholeHeaderOwner(slots[i].type)) {
                prepared.destinations[i] = ConstructionDestination { place, named->second.lifetime }; continue;
            }
            ShareRegion(place, named->second);
        }
        else AcquireRegion(place, n->line, n->isglobal ? optional<uint32_t>(c.global_regions.at(n->defs[i])) : nullopt);
        prepared.destinations[i] = ConstructionDestination { place, n->isglobal ? ConstructionDestination::Static : ConstructionDestination::Block };
    }
    return prepared;
}

inline void Function::Decl(VarDecl *n) {
    auto prepared = PrepareDecl(n);
    auto scope = BeginTempScope(n);
    InitializeDecl(n, prepared);
    EndTempScope(scope);
}

inline void Function::InitializeDecl(VarDecl *n, const PreparedDecl &prepared) {
    auto &slots = prepared.slots;
    auto &destinations = prepared.destinations;
    if (slots.size() > 1 && n->inits.size() == 1) {
        auto types = NaturalResults(n->inits[0]);
        if (types.size() != slots.size()) Fail(n->line, "multi-binding arity mismatch");
        ResultExpression(n->inits[0], destinations);
        vector<uint32_t> captured(types.size());
        for (size_t i = types.size(); i-- > 0;) captured[i] = Save(types[i]);
        for (size_t i = 0; i < slots.size(); i++) {
            if (Compiler::RegionOwner(slots[i].type)) {
                if (!Compiler::RegionOwner(types[i])) ConstructRegionFromCaptured(types[i], captured[i], *destinations[i], n->line);
                continue;
            }
            Get(captured[i]);
            Convert(types[i], slots[i].type, n->line);
            StoreCopy({ slots[i].type, slots[i] }, CaptureStack(slots[i].type));
        }
        return;
    }
    for (size_t i = 0; i < slots.size(); i++) {
        auto init = i < n->inits.size() ? n->inits[i] : nullptr;
        if (Compiler::RegionOwner(slots[i].type)) {
            ConstructRegionInto(init, *destinations[i]);
            continue;
        }
        if (!init) continue;
        if (n->byref && init->exprtype->kind != TY_REF) Address(init);
        else To(init, slots[i].type);
        StoreCopy({ slots[i].type, slots[i] }, CaptureStack(slots[i].type));
    }
}
inline void Function::AssignNode(Assign *n) {
    auto place = PinPlace(n->lval, n->pointee);
    auto t = place.storage_type;
    if (Compiler::RegionOwner(t)) {
        if (Compiler::RegionEnum(t)) Fail(n->line, "whole variable-mode enum assignment is not supported");
        if (Compiler::RegionStruct(t)) {
            if (!Compiler::FrameStruct(t)) Fail(n->line, "whole variable-struct assignment is not supported");
            if (n->op != T_ASSIGN) Fail(n->line, "compound frame-object assignment is not supported");
            ConstructStructInto(n->rhs, { place, ConstructionDestination::Existing }); return;
        }
        if (Compiler::RuntimeLimited(t)) {
            if (n->op != T_ASSIGN) Fail(n->line, "compound runtime-limited assignment is not supported");
            auto temporary = TemporaryDestination(t, n->line);
            ConstructRegionInto(n->rhs, temporary);
            LocationAddress(temporary.location); auto source = Save(I32);
            ConstructRegionFromCaptured(t, source, { place, ConstructionDestination::Existing }, n->line);
            return;
        }
        if (!Compiler::GrowableArray(t)) Fail(n->line, "whole variable-array assignment is not supported");
        if (n->op != T_ASSIGN && n->op != T_DOTASSIGN)
            Fail(n->line, "compound owned array assignment is not supported");
        // The frontend forbids RHS use of the owner under reconstruction.
        // Pin its header, preserve its region and let the producer publish
        // length at the same point as ordinary in-place construction.
        ConstructRegionInto(n->rhs, { place, ConstructionDestination::Existing }); return;
    }
    if (n->op != T_ASSIGN && n->op != T_DOTASSIGN) {
        if (c.Aggregate(t)) Fail(n->line, "elementwise aggregate assignment is not supported");
        ReadLocation(place, t);
        To(n->rhs, t); BinaryOp(n->op, t, n->line);
    } else To(n->rhs, t);
    StoreCopy(place, CaptureStack(t));
}
inline void Function::IncNode(IncDec *n) {
    auto place = PinPlace(n->lval, true);
    auto t = place.storage_type;
    ReadLocation(place, t);
    if (t->kind == TY_FLT) { if (IsF32(t)) code.F32Const(1); else code.F64Const(1); }
    else Const(t, 1);
    BinaryOp(n->op == T_INC ? T_PLUS : T_MINUS, t, n->line);
    StoreCopy(place, CaptureStack(t));
}

inline void Function::AggregateLiteral(Node *n) {
    auto t = n->exprtype;
    if (!c.Aggregate(t)) Fail(n->line, "this array/struct literal requires unsupported variable-size storage");
    auto destination = FreshDestination(t, ConstructionDestination::Statement);
    auto place = destination.location;
    LocationAddress(place); code.I32Const(0); code.I32Const(int32_t(c.Size(t).size)); code.Fill();
    if (auto a = Is<ArrayLit>(n)) {
        auto elem = t->arr->sub;
        auto stride = c.Size(elem).size;
        auto start = c.Size(t).payload;
        auto count = a->fillval ? static_cast<IntLit *>(a->fillcount)->val : int64_t(a->elems.size());
        if (t->arr->akind == A_LIMITED) {
            LocationAddress(place); code.I32Const(int32_t(count)); code.Mem(0x36, 2);
        }
        if (a->fillval) {
            // Goose evaluates a fill value once, then copies it into each slot.
            To(a->fillval, elem); auto value = Save(elem);
            auto i = Local(I32); code.I32Const(0); Set(i);
            auto done = Begin(), loop = Begin(0x03);
            Get(i); code.I32Const(int32_t(count)); code.Op(0x4f); Br(done, true);
            LocationAddress(OffsetLocation(place, start, elem)); Get(i); code.I32Const(int32_t(stride)); code.Op(0x6c); code.Op(0x6a);
            Get(value); Store(elem);
            Get(i); code.I32Const(1); code.Op(0x6a); Set(i); Br(loop); End(); End();
        } else {
            for (size_t i = 0; i < a->elems.size(); i++) {
                ConstructInto(a->elems[i], { OffsetLocation(place, start + uint32_t(i) * stride, elem), ConstructionDestination::Statement });
            }
        }
    } else if (auto s = Is<StructLit>(n)) {
        auto layout = c.Size(t);
        uint32_t payload = 0;
        if (s->einst) {
            auto vi = s->einst->en->VariantIndex(s->variant);
            if (t->kind == TY_ENUM) {
                payload = layout.payload;
                LocationAddress(place); code.I32Const(vi); code.Mem(0x36, 2);
            } else if (t->kind != TY_VARIANT) Fail(n->line, "unsupported variant construction");
            layout = c.Payload(s->einst, vi);
        } else if (!s->sinst) Fail(n->line, "struct type was not resolved");
        for (size_t i = 0; i < s->inits.size(); i++) {
            auto fi = i < s->fieldindices.size() ? s->fieldindices[i] : int(i);
            if (fi < 0 || size_t(fi) >= layout.fields.size()) Fail(n->line, "unsupported struct initializer");
            auto ft = s->einst ? s->einst->vftypes[size_t(s->einst->en->VariantIndex(s->variant))][size_t(fi)]
                               : s->sinst->ftypes[size_t(fi)];
            ConstructInto(s->inits[i].val, { OffsetLocation(place, payload + layout.fields[size_t(fi)], ft), ConstructionDestination::Statement });
        }
    }
    LocationAddress(place);
}

inline void Function::Slice(SliceExpr *n) {
    SliceView(n);
    if (n->exprtype->kind != TY_SLICE) {
        auto at = n->obj->exprtype; if (at->kind == TY_REF) at = at->ref->sub;
        auto elem = at->kind == TY_ARRAY ? at->arr->sub : at->sub;
        Convert(c.ast.SliceOf(elem, n->line), n->exprtype, n->line);
    }
}
inline void Function::SliceView(SliceExpr *n) {
    auto at = n->obj->exprtype; if (at->kind == TY_REF) at = at->ref->sub;
    auto elem = at->kind == TY_ARRAY ? at->arr->sub : at->kind == TY_SLICE ? at->sub : nullptr;
    if (!elem) Fail(n->line, "only slices of fixed-layout elements are supported");
    View(n->obj); auto view = Save(I64);
    Get(view); code.I64Const(32); code.Op(0x88); auto len = Save(I64);
    if (n->lo) {
        if (n->lo_from_end) Get(len);
        To(n->lo, c.ast.inttypes[IS_I64]); if (n->lo_from_end) code.Op(0x7d);
    } else code.I64Const(0);
    auto lo = Save(I64);
    if (n->hi) {
        if (n->hi_from_end) Get(len);
        To(n->hi, c.ast.inttypes[IS_I64]); if (n->hi_from_end) code.Op(0x7d);
    } else Get(len);
    auto hi = Save(I64);
    if (!n->nobc) {
        Get(lo); Get(hi); code.Op(0x56); Get(hi); Get(len); code.Op(0x56); code.Op(0x72);
        TrapIf(n->line, "slice bounds out of range");
    }
    Get(view); code.Op(0xa7); Get(lo); code.Op(0xa7);
    code.I32Const(int32_t(c.Size(elem).size)); code.Op(0x6c); code.Op(0x6a); code.Op(0xad);
    Get(hi); Get(lo); code.Op(0x7d); code.I64Const(32); code.Op(0x86); code.Op(0x84);
}

inline void Function::For(ForLoop *n) {
    auto binding = Bind(n->vdef);
    optional<Slot> indexbinding;
    if (n->idxdef) indexbinding = Bind(n->idxdef);
    auto range = Is<RangeExpr>(n->iter);
    bool numeric = n->iterkind == IK_RANGE || n->iterkind == IK_COUNT;
    auto ct = numeric ? (range ? range->exprtype : n->iter->exprtype) : c.ast.inttypes[IS_I64];
    uint32_t lo, hi, view = 0;
    TypeExpr *elem = nullptr;
    function<void()> sequence;
    if (numeric) {
        if (range) To(range->lo, ct); else Const(ct, 0);
        lo = Save(ct); To(range ? range->hi : n->iter, ct); hi = Save(ct);
    } else {
        auto at = n->iter->exprtype; if (at->kind == TY_REF) at = at->ref->sub;
        elem = at->kind == TY_ARRAY ? at->arr->sub : at->kind == TY_SLICE ? at->sub : nullptr;
        if (!elem) Fail(n->line, "this iteration source is not supported");
        auto value = SequenceValue(n->iter);
        sequence = [this, value, at, n]() {
            value();
            if (n->iter->exprtype->kind == TY_REF) Load(at);
            if (at->kind == TY_ARRAY) PackArrayView(at);
        };
        sequence(); view = Save(I64);
        code.I64Const(0); lo = Save(I64); Get(view); code.I64Const(32); code.Op(0x88); hi = Save(I64);
    }
    uint32_t ordinal = Local(I64); code.I64Const(0); Set(ordinal);
    auto done = Begin(), again = Begin(0x03);
    if (!numeric && !n->fixedlen) {
        sequence(); Set(view); Get(view); code.I64Const(32); code.Op(0x88); Set(hi);
    }
    Get(lo); Get(hi); BinaryOp(T_GTEQ, ct, n->line); Br(done, true);
    if (numeric) { Get(lo); Convert(ct, binding.type, n->line); Write(binding); }
    else {
        Get(view); code.Op(0xa7); Get(lo); code.Op(0xa7);
        code.I32Const(int32_t(c.Size(elem).size)); code.Op(0x6c); code.Op(0x6a);
        if (!n->byref || elem->kind == TY_REF) { Load(elem); Convert(elem, binding.type, n->line); }
        Write(binding);
    }
    if (indexbinding) { Get(ordinal); Convert(c.ast.inttypes[IS_I64], indexbinding->type, n->line); Write(*indexbinding); }
    auto step = Begin(); PushExit({ done, nullptr, {}, {}, true, step });
    BlockInto(n->body, {}, {}); exits.pop_back(); End();
    // The counter's type is the range's type, not a narrowed loop binding.
    Get(lo); Const(ct, 1); code.Op(W(ct) == I64 ? 0x7c : 0x6a); Normalize(ct); Set(lo);
    Get(ordinal); code.I64Const(1); code.Op(0x7c); Set(ordinal);
    Br(again); End(); End();
}

inline void Function::EmitCall(Call *n, bool adapt_result, const ResultDestinations &destinations, bool elements) {
    if (n->builtin >= 0) { Builtin(n, adapt_result); return; }
    auto args = n->ValueArgNodes();
    if (n->fvbody) {
        if (args.size() != n->fvparams.size()) Fail(n->line, "function-value parameter mismatch");
        for (auto parameter : n->fvparams) if (c.Class(parameter->type) != SC_FIXED)
            Fail(n->line, "owned dynamic function-value parameters are not supported without receiving lifetimes");
        for (auto result : n->rettypes) if (c.Class(result) != SC_FIXED)
            Fail(n->line, "owned dynamic function-value results are not supported without result channels");
        for (size_t i = 0; i < args.size(); i++) { auto s = Bind(n->fvparams[i]); To(args[i], s.type); Write(s); }
        unordered_map<VarDef *, VarDef *> remap;
        for (auto [a, b] : n->fvremap) remap[a] = b;
        aliases.push_back(std::move(remap));
        vector<uint32_t> vals; for (auto t : n->rettypes) vals.push_back(Local(t));
        BlockInto(n->fvbody, n->rettypes, vals);
        aliases.pop_back();
        for (auto x : vals) Get(x);
        if (adapt_result && n->rettypes.size() == 1) Convert(n->rettypes[0], n->exprtype, n->line);
        return;
    }
    auto sp = n->spec;
    if (!sp || (!c.function_index.count(sp) && !c.intrinsic_opcode.count(sp)))
        Fail(n->line, "call has no reachable concrete specialization");
    auto receiving = destinations;
    for (size_t i = 0; i < sp->rets.size(); i++) if (Compiler::RegionOwner(sp->rets[i])) {
        if (!receiving.empty()) {
            if (receiving.size() != sp->rets.size()) Fail(n->line, "owned call result channel arity mismatch");
            if (receiving[i]) CheckRegionDestination(sp->rets[i], *receiving[i], n->line);
        }
    }
    vector<VarDef *> ps; for (auto p : sp->params) if (p->type->kind != TY_FN) ps.push_back(p);
    if (args.size() != ps.size()) Fail(n->line, "function-value arguments must be eliminated by the Goose optimizer");
    auto owned_arguments = any_of(ps.begin(), ps.end(), [](VarDef *p) { return Compiler::RegionOwner(p->type); });
    auto group = BeginArgumentGroup(owned_arguments);
    for (size_t i = 0; i < args.size(); i++) {
        auto t = ps[i]->type;
        if (Compiler::RegionOwner(t)) {
            Location place { t, Slot { Slot::FRAME, FrameBytes(c.ControlLayout(t).size, c.ControlLayout(t).align), t } };
            AcquireRegion(place, args[i]->line);
            ConstructRegionInto(args[i], { place, ConstructionDestination::Statement });
            LocationAddress(place); continue;
        }
        To(args[i], t);
        // A later argument may mutate this value. Snapshot aggregates in
        // source order, before evaluating the next argument.
        if (c.Aggregate(t)) {
            auto captured = CopyCaptured(CaptureStack(t)); Get(captured.value_local);
        }
    }
    // Anonymous result storage is needed only after evaluating arguments.
    // Reserving it earlier would keep a region live across recursive arguments.
    bool run = false;
    if (c.run_index.count(sp)) {
        run = elements;
        if (!destinations.empty() && destinations[0]) {
            auto &destination = *destinations[0]; auto target = destination.location.storage_type;
            run |= destination.elements || Compiler::GrowableArray(target) ||
                (target->arr->akind == A_VAR && Compiler::LengthStorage(target) != Compiler::LengthStorage(sp->rets[0]));
        }
    }
    auto plan = PlanRegionResults(sp->rets, receiving, n->line, run);
    if (run) {
        plan.producers[0]->elements = true;
        if (destinations.empty() || !destinations[0]) plan.values[0]->elements = true;
    }
    receiving = plan.producers;
    for (size_t i = 0; i < sp->rets.size(); i++) if (auto t = sp->rets[i]; c.Aggregate(t)) {
        if (Compiler::RegionOwner(t)) LocationAddress(receiving[i]->location);
        else LocationAddress(FreshDestination(t, ConstructionDestination::Activation).location);
    }
    if (auto intrinsic = c.intrinsic_opcode.find(sp); intrinsic != c.intrinsic_opcode.end())
        code.Op(intrinsic->second);
    else { RecordRegionCall(sp, n->line); CallIndex(run ? c.run_index.at(sp) : c.function_index.at(sp)); }
    // The frontend forbids results referring into a by-value parameter's
    // private owner. External references carried by its elements survive.
    // These balanced cleanup instructions preserve the Wasm call results.
    EndArgumentGroup(group, anonymous_serial != group.serial);
    PublishRegionResults(sp->rets, plan, n->line);
    if (adapt_result && sp->rets.size() == 1) {
        if (n->exprtype->kind == TY_VOID) code.Op(0x1a);
        else Convert(sp->rets[0], n->exprtype, n->line);
    }
}

inline void Function::PrintText(string_view text) {
    code.I32Const(int32_t(c.Text(text))); code.I32Const(int32_t(text.size())); CallIndex(Compiler::WRITE);
}
inline void Function::Print(TypeExpr *t, uint32_t value, Line line, bool nested) {
    if (Compiler::RegionEnum(t)) Fail(line, "variable-mode enum rendering is not supported");
    if (t->kind == TY_REF) {
        if (t->ref->optional) Fail(line, "printing optional references is not supported");
        Get(value); Load(t->ref->sub); auto v = Save(t->ref->sub); Print(t->ref->sub, v, line, nested); return;
    }
    if (t->kind == TY_INT) {
        Get(value); Convert(t, c.ast.inttypes[IsUnsigned(t->intstorage) ? IS_U64 : IS_I64], line);
        CallIndex(IsUnsigned(t->intstorage) ? Compiler::PRINT_U64 : Compiler::PRINT_I64); return;
    }
    if (t->kind == TY_FLT) { Get(value); CallIndex(IsF32(t) ? Compiler::PRINT_F32 : Compiler::PRINT_F64); return; }
    if (t->kind == TY_BOOL) { Get(value); CallIndex(Compiler::PRINT_BOOL); return; }
    if (t->kind == TY_ARRAY || t->kind == TY_SLICE) {
        auto elem = t->kind == TY_ARRAY ? t->arr->sub : t->sub;
        uint32_t ptr, len;
        Get(value);
        if (t->kind == TY_SLICE) { code.Op(0xa7); ptr = Save(I32); Get(value); code.I64Const(32); code.Op(0x88); code.Op(0xa7); len = Save(I32); }
        else {
            PackArrayView(t); auto view = Save(I64);
            Get(view); code.Op(0xa7); ptr = Save(I32);
            Get(view); code.I64Const(32); code.Op(0x88); code.Op(0xa7); len = Save(I32);
        }
        if (IsU8(elem)) {
            if (nested) Fail(line, "quoted nested byte-array rendering is not supported");
            Get(ptr); Get(len); CallIndex(Compiler::WRITE); return;
        }
        PrintText("[");
        auto i = Local(I32); code.I32Const(0); Set(i);
        auto done = Begin(), loop = Begin(0x03);
        Get(i); Get(len); code.Op(0x4f); Br(done, true);
        Get(i); Begin(0x04); PrintText(", "); End();
        Get(ptr); Get(i); code.I32Const(int32_t(c.Size(elem).size)); code.Op(0x6c); code.Op(0x6a); Load(elem);
        auto e = Save(elem); Print(elem, e, line, true);
        Get(i); code.I32Const(1); code.Op(0x6a); Set(i); Br(loop); End(); End();
        PrintText("]"); return;
    }
    Fail(line, "this value cannot yet be rendered by the direct backend");
}

inline void Function::Builtin(Call *n, bool adapt_result) {
    auto args = n->ArgNodes();
    switch (BuiltinKind(n->builtin)) {
        case B_PRINT: {
            if (!n->fmtspecs.empty()) Fail(n->line, "custom formatters are not supported");
            code.OpU(0x23, 0); auto mark = Save(I32);
            auto cleanup_depth = cleanups.size();
            cleanups.push_back({ CleanupAction::RestoreScratchTop, mark });
            vector<pair<TypeExpr *, uint32_t>> captured;
            // Evaluate all arguments before output. Deep-copy slices and
            // aggregates so a later argument's writes cannot change an
            // already-rendered argument, and nested print calls finish first.
            for (auto arg : args) {
                auto t = arg->exprtype; Expr(arg);
                if (t->kind == TY_REF) {
                    if (t->ref->optional) Fail(arg->line, "printing optional references is not supported; narrow the reference first");
                    Load(t->ref->sub); t = t->ref->sub;
                }
                auto v = Save(t);
                if (Compiler::RegionStruct(t)) Fail(arg->line, "variable-struct rendering is not supported");
                if (Compiler::RegionEnum(t)) Fail(arg->line, "variable-mode enum rendering is not supported");
                if (Compiler::RegionArray(t)) {
                    Get(v); PackArrayView(t); v = Save(I64);
                    t = c.ast.SliceOf(t->arr->sub, arg->line);
                }
                if (c.Aggregate(t)) {
                    // A shallow byte copy would leave pointers into storage
                    // that later arguments can mutate. Refuse this rendering
                    // until recursive snapshots have an explicit contract.
                    function<bool(TypeExpr *)> indirect = [&](TypeExpr *x) {
                        if (x->kind == TY_REF || x->kind == TY_SLICE) return true;
                        if (x->kind == TY_ARRAY) return indirect(x->arr->sub);
                        if (x->kind == TY_STRUCT)
                            for (auto ft : x->struc->inst->ftypes) if (ft && indirect(ft)) return true;
                        return false;
                    };
                    if (indirect(t)) Fail(arg->line, "printing aggregates containing references or slices is not supported");
                    v = CopyCaptured({ t, v, CapturedValue::BorrowedFixed }).value_local;
                } else if (t->kind == TY_SLICE) {
                    auto elem = t->sub;
                    if (elem->kind == TY_SLICE || elem->kind == TY_REF || c.Aggregate(elem))
                        Fail(arg->line, "printing slices with indirect aggregate elements is not supported");
                    Get(v); code.I64Const(32); code.Op(0x88); code.Op(0xa7);
                    auto len = Save(I32);
                    Get(len); code.I32Const(int32_t(c.Size(elem).size)); code.Op(0x6c); auto bytes = Save(I32);
                    Dynamic(bytes, arg->line); auto dest = Save(I32);
                    Get(dest); Get(v); code.Op(0xa7); Get(bytes); code.Copy();
                    Get(dest); code.Op(0xad); Get(len); code.Op(0xad); code.I64Const(32); code.Op(0x86); code.Op(0x84); Set(v);
                }
                captured.emplace_back(t, v);
            }
            for (auto [t, v] : captured) Print(t, v, n->line);
            CallIndex(Compiler::NEWLINE); CloseCleanups(cleanup_depth); return;
        }
        case B_ASSERT: Truth(args[0]); code.Op(0x45); TrapIf(n->line, "assertion failed"); return;
        case B_ABORT: {
            View(args[0]); auto v = Save(I64); Get(v); code.Op(0xa7); Get(v); code.I64Const(32); code.Op(0x88); code.Op(0xa7);
            code.I32Const(n->line.line); CallIndex(Compiler::ABORT); code.Op(0x00); return;
        }
        case B_EXIT: To(args[0], c.ast.inttypes[IS_I32]); CallIndex(Compiler::EXIT); code.Op(0x00); return;
        case B_LEN: {
            View(args[0]); code.I64Const(32); code.Op(0x88); Convert(c.ast.inttypes[IS_I64], n->exprtype, n->line); return;
        }
        case B_CAP: {
            auto t = Object(args[0]);
            if (Compiler::RuntimeLimited(t)) {
                code.Mem(0x28, 2, 12); code.Op(0xad);
                Convert(c.ast.inttypes[IS_U64], n->exprtype, n->line); return;
            }
            c.Size(t); code.Op(0x1a);
            code.I64Const(t->arr->size); Convert(c.ast.inttypes[IS_I64], n->exprtype, n->line); return;
        }
        case B_INDEX_OF: case B_PUSH: case B_APPEND: case B_POP: case B_POP_N: case B_CLEAR: case B_RESIZE:
            ArrayBuiltin(n); return;
        case B_COPY: {
            auto own = NaturalResults(n);
            if (own.size() == 1 && Compiler::RegionOwner(own[0])) {
                Materialize(n, own[0], adapt_result); return;
            }
            if (n->exprtype->kind == TY_SLICE) Fail(n->line, "copying a slice requires owned dynamic storage");
            To(args[0], n->exprtype);
            if (c.Aggregate(n->exprtype)) {
                auto captured = CopyCaptured(CaptureStack(n->exprtype)); Get(captured.value_local);
            }
            return;
        }
        case B_DEFAULT: {
            auto t = n->rettypes[0];
            if (Compiler::RegionEnum(t)) { Materialize(n, t, adapt_result); return; }
            if (!c.Aggregate(t)) {
                Zero(W(t)); if (adapt_result) Convert(t, n->exprtype, n->line); return;
            }
            auto destination = FreshDestination(t, ConstructionDestination::Statement);
            auto place = destination.location;
            LocationAddress(place); code.I32Const(0); code.I32Const(int32_t(c.Size(t).size)); code.Fill();
            if (n->defaultinit) {
                if (t->kind == TY_ARRAY && t->arr->akind == A_FIXED) {
                    auto i = Local(I32); code.I32Const(0); Set(i);
                    auto done = Begin(), loop = Begin(0x03);
                    Get(i); code.I32Const(int32_t(t->arr->size)); code.Op(0x4f); Br(done, true);
                    auto scope = BeginTempScope(n->defaultinit);
                    LocationAddress(place); Get(i); code.I32Const(int32_t(c.Size(t->arr->sub).size)); code.Op(0x6c); code.Op(0x6a);
                    To(n->defaultinit, t->arr->sub); Store(t->arr->sub);
                    EndTempScope(scope);
                    Get(i); code.I32Const(1); code.Op(0x6a); Set(i); Br(loop); End(); End();
                } else if (t->kind != TY_ARRAY) ConstructInto(n->defaultinit, destination);
            }
            LocationAddress(place); if (adapt_result) Convert(t, n->exprtype, n->line); return;
        }
        default: Fail(n->line, "builtin '" + string(BuiltinByKind(n->builtin).name) + "' is not supported by the direct backend");
    }
}

inline void Function::EmitInline(InlineBlock *node, bool adapt_result, const ResultDestinations &destinations, bool elements) {
    auto types = Values(node);
    auto own = node->spec ? node->spec->rets : types;
    if (node->spec) for (auto parameter : node->spec->params)
        if (c.Class(parameter->type) != SC_FIXED && !Compiler::RegionOwner(parameter->type))
            Fail(node->line, "owned dynamic inline parameters are not supported without receiving lifetimes");
    for (size_t i = 0; i < own.size(); i++) if (c.Class(own[i]) != SC_FIXED) {
        if (!Compiler::RegionOwner(own[i]))
            Fail(node->line, "owned dynamic inline results are not supported without a receiving destination");
    }
    auto requested = destinations;
    if (requested.empty() && own.size() == 1 && own[0]->kind == TY_ARRAY && own[0]->arr->akind == A_VAR &&
        node->exprtype && node->exprtype->kind == TY_ARRAY && node->exprtype->arr->akind == A_LIMITED &&
        !Compiler::RuntimeLimited(node->exprtype)) {
        // A spliced body constructs as the fixed receiving array's kind.
        // Its region-backed staging header avoids imposing the callee's
        // unrelated narrow prefix before the fixed-capacity conversion.
        auto stage = c.ast.ArrayOf(own[0]->arr->sub, A_LIMITED, node->line);
        requested = { TemporaryDestination(stage, node->line) };
    }
    if (elements && requested.empty() && own.size() == 1 && Compiler::RegionArray(own[0]) && !Compiler::RuntimeLimited(own[0])) {
        auto temporary = TemporaryDestination(own[0], node->line); temporary.elements = true;
        requested = { temporary };
    }
    auto plan = PlanRegionResults(own, requested, node->line, own.size() == 1 && own[0]->kind == TY_ARRAY && own[0]->arr->akind == A_VAR, true);
    auto &receiving = plan.producers;
    vector<uint32_t> values;
    for (auto type : own) values.push_back(Local(type));
    auto named = BindNamedResults(node->body, node->sf, own, receiving, true);
    size_t prefix = 0;
    bool group_needed = false;
    for (auto statement : node->body->stmts) {
        auto declaration = Is<VarDecl>(statement);
        if (!declaration || !declaration->inline_arg) break;
        prefix++;
        for (auto variable : declaration->defs) if (Compiler::RegionOwner(variable->type)) group_needed = true;
        for (auto init : declaration->inits) if (MayMaterialize(init)) group_needed = true;
    }
    auto private_depth = private_headers.size();
    auto group = BeginArgumentGroup(group_needed);
    auto label = Begin(); PushExit({ label, node->sf, own, values, false, {} }, receiving);
    auto parameter_depth = cleanups.size() + 1;
    for (size_t i = 0; i < prefix; i++) {
        auto declaration = static_cast<VarDecl *>(node->body->stmts[i]);
        auto before = private_headers.size();
        auto prepared = PrepareDecl(declaration);
        for (size_t j = before; j < private_headers.size(); j++) private_headers[j].cleanup_depth = parameter_depth;
        InitializeDecl(declaration, prepared);
    }
    auto retain_arguments = anonymous_serial != group.serial;
    BlockInto(node->body, own, values, receiving, prefix); exits.pop_back(); End();
    EndArgumentGroup(group, retain_arguments);
    auto retained = private_depth;
    for (size_t i = private_depth; i < private_headers.size(); i++)
        if (private_headers[i].temporary) private_headers[retained++] = private_headers[i];
    private_headers.resize(retained);
    for (auto variable : named) named_regions.erase(variable);
    for (auto value : values) Get(value);
    PublishRegionResults(own, plan, node->line);
    if (adapt_result && own.size() == 1 && types.size() == 1) Convert(own[0], types[0], node->line);
    else if (adapt_result && types.empty()) for (size_t index = 0; index < own.size(); index++) code.Op(0x1a);
}

inline void Function::ControlValue(Node *n, const vector<TypeExpr *> &ts, const vector<uint32_t> &vs,
                                    const ResultDestinations &destinations) {
    if (Is<LoopExpr>(n) || Is<EarlyBlock>(n)) {
        auto done = Begin();
        if (auto loop = Is<LoopExpr>(n)) {
            auto again = Begin(0x03); PushExit({ done, nullptr, ts, vs, true, again }, destinations);
            BlockInto(loop->body, {}, {}); exits.pop_back(); Br(again); End();
        } else {
            PushExit({ done, nullptr, ts, vs, true, {} }, destinations);
            BlockInto(static_cast<EarlyBlock *>(n)->body, ts, vs, destinations); exits.pop_back();
        }
        End(); return;
    }
    auto m = Is<MatchExpr>(n);
    if (!m) Fail(n->line, "internal: unsupported value control construct");
    auto t = m->scrutinee->exprtype;
    Expr(m->scrutinee);
    if (t->kind == TY_REF) { Load(t->ref->sub); t = t->ref->sub; }
    optional<uint32_t> base;
    if (t->kind == TY_ENUM) {
        W(t); if (Compiler::RegionEnum(t)) code.Mem(0x28, 2);
        base = Save(I32); Get(*base); code.Mem(0x28, 2);
    }
    else if (t->kind != TY_INT && t->kind != TY_BOOL)
        Fail(n->line, "only integer, bool and fixed enum match are supported");
    auto value = Save(base ? uint8_t(I32) : W(t));
    auto done = Begin(); bool wildcard = false;
    for (auto &arm : m->arms) {
        bool any = arm.pat.kind == P_WILDCARD;
        if (!any) {
            bool first = true;
            if (base) for (auto variant : arm.variants) {
                Get(value); code.I32Const(t->enu->inst->en->VariantIndex(variant)); code.Op(0x46);
                if (!first) code.Op(0x72);
                first = false;
            }
            else for (auto range : arm.ranges) {
                Get(value); Const(t, range.lo); BinaryOp(T_GTEQ, t, n->line);
                Get(value); Const(t, range.hi); BinaryOp(T_LTEQ, t, n->line); code.Op(0x71);
                if (!first) code.Op(0x72);
                first = false;
            }
            if (first) Fail(n->line, "match pattern has no resolved alternatives");
            Begin(0x04);
        }
        auto scope = BeginTempScope(arm.body);
        if (arm.binder) {
            if (!base || (arm.pat.byref && !Compiler::RegionEnum(t)))
                Fail(n->line, "only variable-mode enum payloads bind by reference");
            auto slot = Bind(arm.binder);
            auto layout = Compiler::RegionEnum(t) ? c.EnumImageLayout(t->enu->inst, n->line) : c.Size(t);
            Get(*base); code.I32Const(int32_t(layout.payload)); code.Op(0x6a); Write(slot);
        }
        if (ts.empty() || Values(arm.body).empty()) Discard(arm.body);
        else SetResults({ arm.body }, ts, vs, arm.body->line, destinations);
        EndTempScope(scope);
        Br(done); if (!any) End(); else { wildcard = true; break; }
    }
    if (!wildcard) Abort(n->line, "non-exhaustive match");
    End();
}

inline void Function::Expr(Node *n) {
    if (!n) return;
    if (auto literal = Is<ArrayLit>(n); literal && literal->capexpr) {
        auto type = n->exprtype;
        auto element = type->kind == TY_ARRAY ? type->arr->sub : type->kind == TY_SLICE ? type->sub : nullptr;
        if (!element) Fail(n->line, "capacity literal has no array element type");
        Materialize(n, c.ast.ArrayOf(element, A_LIMITED, n->line)); return;
    }
    if (Compiler::RegionOwner(n->exprtype) && (Is<ArrayLit>(n) || Is<StrLit>(n) || Is<StructLit>(n) || Is<Block>(n) ||
        Is<IfExpr>(n) || Is<EarlyBlock>(n) || Is<LoopExpr>(n) || Is<MatchExpr>(n))) {
        Materialize(n, n->exprtype); return;
    }
    switch (n->nkind) {
        case NK_IntLit: { auto x = static_cast<IntLit *>(n); Const(n->exprtype, x->val); Normalize(n->exprtype); return; }
        case NK_FltLit: { auto x = static_cast<FltLit *>(n); if (IsF32(n->exprtype)) code.F32Const(float(x->val)); else code.F64Const(x->val); return; }
        case NK_BoolLit: code.I32Const(static_cast<BoolLit *>(n)->val ? 1 : 0); return;
        case NK_NullLit: W(n->exprtype); code.I32Const(0); return;
        case NK_StrLit: {
            auto x = static_cast<StrLit *>(n); auto off = c.Text(x->val);
            if (n->exprtype->kind == TY_SLICE) code.I64Const(int64_t((uint64_t(x->val.size()) << 32) | off));
            else if (n->exprtype->kind == TY_ARRAY) {
                auto size = c.Size(n->exprtype).size;
                if (x->val.size() > size) Fail(n->line, "string exceeds its fixed-array destination");
                auto dest = FreshDestination(n->exprtype, ConstructionDestination::Statement).location;
                LocationAddress(dest); code.I32Const(0); code.I32Const(int32_t(size)); code.Fill();
                if (n->exprtype->arr->akind == A_LIMITED) {
                    LocationAddress(dest); code.I32Const(int32_t(x->val.size())); code.Mem(0x36, 2);
                }
                LocationAddress(OffsetLocation(dest, c.Size(n->exprtype).payload, n->exprtype->arr->sub));
                code.I32Const(int32_t(off)); code.I32Const(int32_t(x->val.size())); code.Copy();
                LocationAddress(dest);
            }
            else Fail(n->line, "unsupported string representation");
            return;
        }
        case NK_Ident: {
            auto x = static_cast<Ident *>(n); if (!x->vdef) Fail(n->line, "function names are compile-time values only");
            auto s = Lookup(x->vdef, n->line);
            if (n->exprtype->kind == TY_REF && s.type->kind != TY_REF) SlotAddress(s);
            else { Read(s); Convert(s.type, n->exprtype, n->line); }
            return;
        }
        case NK_ArrayLit: case NK_StructLit: AggregateLiteral(n); return;
        case NK_Unary: {
            auto u = static_cast<Unary *>(n);
            if (u->op == T_BITAND) {
                if (n->exprtype->kind == TY_REF) ReferenceValue(PinPlace(u->child));
                else To(u->child, n->exprtype);
                return;
            }
            if (u->op == T_NOT) { Truth(u->child); code.Op(0x45); return; }
            auto t = u->child->exprtype; if (t->kind == TY_REF) t = t->ref->sub;
            if (u->op == T_MINUS && t->kind == TY_FLT) { To(u->child, t); code.Op(IsF32(t) ? 0x8c : 0x9a); }
            else if (u->op == T_MINUS) { Const(t, 0); To(u->child, t); BinaryOp(T_MINUS, t, n->line); }
            else if (u->op == T_BITNOT) { To(u->child, t); Const(t, -1); BinaryOp(T_XOR, t, n->line); }
            else Fail(n->line, "unsupported unary operator");
            Convert(t, n->exprtype, n->line); return;
        }
        case NK_Binary: {
            auto b = static_cast<Binary *>(n);
            if (b->op == T_ANDAND || b->op == T_OROR) {
                auto right = [&]() {
                    auto scope = BeginTempScope(b->right); Truth(b->right); auto value = Save(I32);
                    EndTempScope(scope); Get(value);
                };
                Truth(b->left); Begin(0x04, I32);
                if (b->op == T_ANDAND) right(); else code.I32Const(1);
                Else(); if (b->op == T_OROR) right(); else code.I32Const(0); End(); return;
            }
            if (b->op == T_DOTEQ || b->op == T_DOTNEQ ||
                ((b->op == T_EQ || b->op == T_NEQ) && (Is<NullLit>(b->left) || Is<NullLit>(b->right)))) {
                auto pointer = [&](Node *side) {
                    if (Is<NullLit>(side)) { code.I32Const(0); return; }
                    if (auto id = Is<Ident>(side); id && id->vdef && id->vdef->type->kind == TY_REF) {
                        Read(Lookup(id->vdef, side->line)); return;
                    }
                    if (side->exprtype->kind != TY_REF) Fail(side->line, "unsupported optional-reference comparison");
                    Expr(side);
                };
                pointer(b->left); pointer(b->right); code.Op(b->op == T_EQ || b->op == T_DOTEQ ? 0x46 : 0x47); return;
            }
            auto t = b->left->exprtype;
            if (t->kind == TY_REF && b->op != T_DOTEQ && b->op != T_DOTNEQ) t = t->ref->sub;
            To(b->left, t);
            if (b->op == T_SHL || b->op == T_SHR) { Expr(b->right); Convert(b->right->exprtype, t, n->line); }
            else To(b->right, t);
            BinaryOp(b->op, t, n->line);
            bool compare = b->op == T_EQ || b->op == T_NEQ || b->op == T_LT || b->op == T_GT || b->op == T_LTEQ || b->op == T_GTEQ || b->op == T_DOTEQ || b->op == T_DOTNEQ;
            if (!compare) Convert(t, n->exprtype, n->line);
            return;
        }
        case NK_Dot: {
            auto d = static_cast<Dot *>(n);
            if (d->member == B_LEN) { View(d->obj); code.I64Const(32); code.Op(0x88); Convert(c.ast.inttypes[IS_I64], n->exprtype, n->line); return; }
            if (d->member == B_CAP) {
                auto t = Object(d->obj);
                if (Compiler::RuntimeLimited(t)) {
                    code.Mem(0x28, 2, 12); code.Op(0xad);
                    Convert(c.ast.inttypes[IS_U64], n->exprtype, n->line); return;
                }
                c.Size(t); code.Op(0x1a);
                code.I64Const(t->arr->size); Convert(c.ast.inttypes[IS_I64], n->exprtype, n->line); return;
            }
            if (d->variantconst) {
                auto t = n->exprtype;
                if (Compiler::RegionEnum(t)) { Materialize(n, t); return; }
                auto place = FreshDestination(t, ConstructionDestination::Statement).location;
                LocationAddress(place); code.I32Const(0); code.I32Const(int32_t(c.Size(t).size)); code.Fill();
                if (t->kind == TY_ENUM) {
                    LocationAddress(place); code.I32Const(d->einst->en->VariantIndex(d->variantconst)); code.Mem(0x36, 2);
                }
                LocationAddress(place); return;
            }
            if (d->member >= 0) Fail(n->line, "this property is not supported");
            auto t = d->obj->exprtype; if (t->kind == TY_REF) t = t->ref->sub;
            auto ft = c.FieldType(t, d->fieldidx); Address(n);
            if (n->exprtype->kind != TY_REF || ft->kind == TY_REF) { Load(ft); Convert(ft, n->exprtype, n->line); }
            return;
        }
        case NK_Index: {
            auto x = static_cast<Index *>(n); auto t = x->obj->exprtype; if (t->kind == TY_REF) t = t->ref->sub;
            auto elem = t->kind == TY_ARRAY ? t->arr->sub : t->kind == TY_SLICE ? t->sub : nullptr;
            if (!elem) Fail(n->line, "unsupported indexed type");
            Address(n);
            if (n->exprtype->kind != TY_REF || elem->kind == TY_REF) { Load(elem); Convert(elem, n->exprtype, n->line); }
            return;
        }
        case NK_SliceExpr: Slice(static_cast<SliceExpr *>(n)); return;
        case NK_AsCast: Cast(static_cast<AsCast *>(n)); return;
        case NK_Call: EmitCall(static_cast<Call *>(n)); return;
        case NK_Block: {
            auto types = Values(n); vector<uint32_t> values;
            for (auto type : types) values.push_back(Local(type));
            BlockInto(static_cast<Block *>(n), types, values);
            for (auto value : values) Get(value);
            return;
        }
        case NK_IfExpr: {
            auto i = static_cast<IfExpr *>(n); auto ts = Values(n); vector<uint32_t> vs;
            for (auto t : ts) vs.push_back(Local(t));
            Truth(i->cond); Begin(0x04); BlockInto(i->thenb, ts, vs);
            if (i->elseb) {
                // A value-producing guard can return from its else branch.
                // That branch supplies the enclosing function's result and
                // never reaches the local result slot of this conditional.
                Else(); if (ts.empty() || Values(i->elseb).empty()) Discard(i->elseb);
                else { To(i->elseb, ts[0]); Set(vs[0]); }
            }
            End(); for (auto v : vs) Get(v); return;
        }
        case NK_InlineBlock: EmitInline(static_cast<InlineBlock *>(n)); return;
        case NK_EarlyBlock: case NK_LoopExpr: case NK_MatchExpr: {
            auto ts = Values(n); vector<uint32_t> vs; for (auto t : ts) vs.push_back(Local(t));
            ControlValue(n, ts, vs);
            for (auto v : vs) Get(v); return;
        }
        case NK_While: {
            auto w = static_cast<While *>(n); auto done = Begin(), again = Begin(0x03);
            PushExit({ done, nullptr, {}, {}, true, again });
            auto scope = BeginTempScope(w->cond); Truth(w->cond); auto condition = Save(I32); EndTempScope(scope);
            Get(condition); code.Op(0x45); Br(done, true);
            BlockInto(w->body, {}, {}); exits.pop_back();
            Br(again); End(); End(); return;
        }
        case NK_ForLoop: For(static_cast<ForLoop *>(n)); return;
        case NK_Return: {
            auto r = static_cast<Return *>(n);
            for (size_t j = exits.size(); j-- > 0;) {
                auto e = exits[j];
                if (e.sf && e.sf == r->target) {
                    SetResults(r->vals, e.types, e.values, n->line, e.destinations); UnwindCleanups(j); Br(e.label); return;
                }
            }
            Fail(n->line, "return from an out-of-line enclosing function is not supported");
        }
        case NK_Break: {
            auto b = static_cast<Break *>(n);
            for (size_t j = exits.size(); j-- > 0;) {
                auto e = exits[j]; if (!e.breakable) continue;
                if (b->val) SetResults({ b->val }, e.types, e.values, n->line, e.destinations);
                UnwindCleanups(j); Br(e.label); return;
            }
            Fail(n->line, "break has no direct control target");
        }
        case NK_Continue:
            for (size_t j = exits.size(); j-- > 0;) if (exits[j].continue_label) {
                UnwindCleanups(j); Br(*exits[j].continue_label); return;
            }
            Fail(n->line, "continue has no direct loop target");
        case NK_VarDecl: Decl(static_cast<VarDecl *>(n)); return;
        case NK_Assign: AssignNode(static_cast<Assign *>(n)); return;
        case NK_IncDec: IncNode(static_cast<IncDec *>(n)); return;
        case NK_FnDecl: case NK_StructDecl: case NK_EnumDecl: case NK_AliasDecl: return;
        default: Fail(n->line, "unsupported AST construct (kind " + to_string(int(n->nkind)) + ")");
    }
}

} // namespace goose::direct_wasm
