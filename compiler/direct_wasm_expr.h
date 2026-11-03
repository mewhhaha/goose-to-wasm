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
    if (auto call = Is<Call>(node); call && call->fvbody) {
        auto type = call->fvbody->exprtype;
        return type && type->kind != TY_VOID ? vector<TypeExpr *> { type } : vector<TypeExpr *> {};
    }
    if (auto call = Is<Call>(node); call && !call->dispatch.empty()) return call->dispatch.front()->rets;
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
    bool restore_regions = c.needs_regions && !frame_free && !ResourceFreeBlock(b);
    if (restore_regions) {
        code.OpU(0x23, G_REGION_NEXT);
        cleanups.push_back({ CleanupAction::RestoreRegionNext, Save(I32) });
    }
    for (size_t i = first_statement; i < b->stmts.size(); i++) {
        auto s = b->stmts[i];
        if (auto declaration = Is<VarDecl>(s)) Decl(declaration);
        else {
            auto scope = BeginTempScope(s);
            bool folded = false;
            if (i >= first_statement + 2) if (auto loop = Is<While>(s))
                folded = FoldPopcount(loop, Is<VarDecl>(b->stmts[i - 2]), Is<VarDecl>(b->stmts[i - 1]));
            if (!folded) Discard(s);
            EndTempScope(scope);
        }
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
    if (c.needs_regions && !frame_free) {
        if (!restore_regions && (cleanups.size() != cleanup_depth || private_headers.size() != private_depth || region_live != live))
            Fail(b->line, "internal: resource-free block changed ownership state");
        CloseCleanups(cleanup_depth); region_live = live;
    }
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
                auto destination = *destinations[i]; destination.normal_result = true;
                ConstructRegionInto(nodes[i], destination);
                LocationAddress(destinations[i]->location); Set(slots[i]);
            } else { To(nodes[i], types[i]); CaptureResult(types[i], slots[i]); }
        }
    } else if (nodes.size() == 1 && Values(nodes[0]).size() == types.size()) {
        auto vt = NaturalResults(nodes[0]);
        // A forwarded producer may itself be an escape target. Its entry
        // anchor belongs to this attempt, not to the outer receiving image.
        // Keep each image control private and capture every start before args.
        auto producers = destinations;
        vector<optional<uint32_t>> starts(types.size()), headers(types.size());
        vector<bool> lands(types.size());
        auto cleanup_depth = cleanups.size(), private_depth = private_headers.size();
        for (size_t i = 0; c.region_cursors && i < types.size(); i++) {
            if (destinations.size() != types.size() || !destinations[i]) continue;
            auto &destination = *destinations[i]; auto type = destination.location.storage_type;
            auto enumeration = Compiler::RegionEnum(type);
            auto source = vt[i]; if (source->kind == TY_REF) source = source->ref->sub;
            if (!Compiler::RegionOwner(vt[i]) && !(enumeration && (source->kind == TY_VARIANT || source->kind == TY_ENUM))) continue;
            auto record = Compiler::RegionRecord(type) && !Compiler::FrameStruct(type);
            auto array = Compiler::RegionArray(type) &&
                ((type->arr->akind == A_VAR && !destination.elements) || Compiler::RuntimeLimited(type));
            if (!record && !array && !enumeration) continue;
            LocationAddress(TailHeaderLocation(destination.location)); auto original = Save(I32);
            starts[i] = RegionCursor(original);
            lands[i] = destination.construction->open > destination.open0;
            auto layout = c.ControlLayout(type);
            Location stage { type, Slot { Slot::FRAME, FrameBytes(layout.size, layout.align), type } };
            LocationAddress(TailHeaderLocation(stage)); auto header = Save(I32); headers[i] = header;
            Get(header); code.I32Const(0); code.I32Const(int32_t(owner_control_bytes)); code.Fill();
            Get(header); Get(original); code.Mem(0x28, 2, 8); code.Mem(0x36, 2, 8);
            Get(header); Get(*starts[i]); code.Mem(0x36, 2);
            if (record) SetRecordImageAnchor(stage, *starts[i], l);
            if (enumeration) SetEnumImageAnchor(stage, *starts[i], l);
            auto publication = array ? Publication(destination) : optional<uint32_t>{};
            RegisterEffectOwner(stage, true, false, publication);
            private_headers.push_back({ TailHeaderLocation(stage), cleanups.size() });
            if (array) cleanups.push_back({ CleanupAction::CheckAbandonedRegion, original, type->arr->sub, l, destination.enum_guard });
            producers[i] = ConstructionDestination { stage, ConstructionDestination::Statement, destination.elements,
                destination.enum_guard, true, false, publication, destination.construction, destination.open0 };
        }
        ResultExpression(nodes[0], producers);
        vector<uint32_t> captured(types.size());
        for (size_t i = types.size(); i-- > 0;) captured[i] = Save(vt[i]);
        for (size_t i = 0; i < types.size(); i++) if (starts[i]) {
            auto &destination = *destinations[i]; auto type = destination.location.storage_type;
            if (Compiler::RegionEnum(type) && !Compiler::RegionOwner(vt[i]))
                ConstructRegionFromCaptured(vt[i], captured[i], *producers[i], l);
            if (Compiler::RegionEnum(type)) FinishEnumImage(destination.location, *starts[i], lands[i], l);
            else if (Compiler::RegionRecord(type)) FinishRecordImage(destination.location, *starts[i], lands[i], l);
            else {
                LocationAddress(destination.location); auto original = Save(I32);
                FinishArrayImage(original, *starts[i], *headers[i], type, lands[i], l);
            }
        }
        CloseCleanups(cleanup_depth); private_headers.resize(private_depth);
        for (size_t i = 0; i < types.size(); i++) {
            if (Compiler::RegionOwner(types[i])) {
                auto delivered_enum = starts[i] && Compiler::RegionEnum(destinations[i]->location.storage_type);
                if (!Compiler::RegionOwner(vt[i]) && !delivered_enum) ConstructRegionFromCaptured(vt[i], captured[i], *destinations[i], l);
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
        auto field_type = c.FieldType(t, dot->fieldidx);
        RecordFieldAddress(t, size_t(dot->fieldidx), n->line);
        if (c.region_cursors && !Compiler::RegionOwner(field_type)) CanonicalAddress(Compiler::Varint(field_type) ? 1 : c.FixedLayout(field_type).size);
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
        if (!n->isglobal && Compiler::WholeHeaderOwner(v->type) && named != named_regions.end() &&
            !ImageTargetDestination(named->second)) {
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
            if (!inline_named_regions.count(n->defs[i])) named->second.construction->open++;
            if (Compiler::WholeHeaderOwner(slots[i].type) && !ImageTargetDestination(named->second)) {
                prepared.destinations[i] = ConstructionDestination { place, named->second.lifetime, false, named->second.enum_guard, named->second.escape_stage, named->second.normal_result, named->second.publication, named->second.construction, named->second.open0 }; continue;
            }
            ShareRegion(place, named->second, n->defs[i]);
        }
        else AcquireRegion(place, n->line, n->isglobal ? optional<uint32_t>(c.global_regions.at(n->defs[i])) : nullopt);
        prepared.destinations[i] = ConstructionDestination { place, n->isglobal ? ConstructionDestination::Static : ConstructionDestination::Block };
        if (auto named = named_regions.find(n->defs[i]); named != named_regions.end())
            prepared.destinations[i]->construction = named->second.construction;
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
        if (!n->byref && (slots[i].kind == Slot::FRAME || slots[i].kind == Slot::GLOBAL) &&
            ConstructFreshInto(init, { slots[i].type, slots[i] })) continue;
        if (n->byref && init->exprtype->kind != TY_REF) Address(init);
        else To(init, slots[i].type);
        StoreCopy({ slots[i].type, slots[i] }, CaptureStack(slots[i].type));
    }
}
inline void Function::AssignNode(Assign *n) {
    auto place = PinPlace(n->lval, n->pointee);
    auto t = place.storage_type;
    if (Compiler::RegionOwner(t)) {
        if (c.region_cursors && (Compiler::GrowableArray(t) || Compiler::FrameStruct(t))) {
            LocationAddress(TailHeaderLocation(place)); auto header = Save(I32);
            Get(header); code.Mem(0x28, 2); PublishCursor(header, Save(I32));
        }
        if (Compiler::RegionEnum(t)) Fail(n->line, "whole variable-mode enum assignment is not supported");
        if (Compiler::RegionRecord(t)) {
            if (!Compiler::FrameStruct(t)) Fail(n->line, "whole variable-struct assignment is not supported");
            if (n->op != T_ASSIGN) Fail(n->line, "compound frame-object assignment is not supported");
            ConstructRecordInto(n->rhs, { place, ConstructionDestination::Existing }); return;
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
        if (auto cached = CachedLane(n->lval)) Read(*cached);
        else ReadLocation(place, t);
        if (n->op != T_MODEQ || !PowerOfTwoRemainder(n->rhs, t)) {
            To(n->rhs, t); BinaryOp(n->op, t, n->line);
        }
    } else To(n->rhs, t);
    if (c.Aggregate(t)) StoreCopy(place, CaptureStack(t));
    else {
        if (auto cached = CachedLane(n->lval)) {
            if (defer_lane_stores) { Write(*cached); return; }
            Tee(cached->index);
        }
        WriteLocation(place);
    }
}
inline void Function::IncNode(IncDec *n) {
    auto place = PinPlace(n->lval, true);
    auto t = place.storage_type;
    if (auto cached = CachedLane(n->lval)) Read(*cached);
    else ReadLocation(place, t);
    if (t->kind == TY_FLT) { if (IsF32(t)) code.F32Const(1); else code.F64Const(1); }
    else Const(t, 1);
    BinaryOp(n->op == T_INC ? T_PLUS : T_MINUS, t, n->line);
    if (auto cached = CachedLane(n->lval)) {
        if (defer_lane_stores) { Write(*cached); return; }
        Tee(cached->index);
    }
    WriteLocation(place);
}

inline bool Function::SelectAssignment(IfExpr *node) {
    if (node->flat || !node->elseb || !Values(node).empty()) return false;
    auto assignment = [](Node *arm) -> Assign * {
        if (auto block = Is<Block>(arm)) {
            if (block->tail || block->stmts.size() != 1) return nullptr;
            arm = block->stmts[0];
        }
        return Is<Assign>(arm);
    };
    auto yes = assignment(node->thenb), no = assignment(node->elseb);
    if (!yes || !no || yes->pointee || no->pointee) return false;
    auto left = Is<Ident>(yes->lval), right = Is<Ident>(no->lval);
    if (!left || !right || !left->vdef || !right->vdef) return false;
    auto target = Lookup(left->vdef, left->line);
    auto other = Lookup(right->vdef, right->line);
    if (target.kind != Slot::LOCAL || other.kind != Slot::LOCAL ||
        target.index != other.index || target.type != other.type) return false;
    auto scalar = [](TypeExpr *type) { return type && (IsIntT(type) || type->kind == TY_BOOL); };
    if (!scalar(target.type)) return false;
    auto operation = [&](TType op, TypeExpr *type) {
        switch (op) {
            case T_ASSIGN: case T_BITAND: case T_ANDEQ: case T_BITOR: case T_OREQ:
            case T_XOR: case T_XOREQ: case T_SHL: case T_SHLEQ: case T_SHR: case T_SHREQ:
            case T_EQ: case T_NEQ: case T_LT: case T_LTEQ: case T_GT: case T_GTEQ:
            case T_NOT: case T_BITNOT: return true;
            case T_PLUS: case T_PLUSEQ: case T_MINUS: case T_MINUSEQ: case T_MUL: case T_MULEQ:
                return !c.opts.debug || !IsIntT(type) || IsUnsigned(type->intstorage);
            default: return false;
        }
    };
    // Speculation never reads memory or invokes a potentially trapping or
    // effectful expression. Bound duplicated work independently in each arm.
    function<bool(Node *, int &)> pure = [&](Node *value, int &budget) {
        if (!value || !scalar(value->exprtype) || budget == 0) return false;
        budget--;
        if (Is<IntLit>(value) || Is<BoolLit>(value)) return true;
        if (auto id = Is<Ident>(value)) {
            if (!id->vdef) return false;
            auto slot = Lookup(id->vdef, id->line);
            return slot.kind == Slot::LOCAL && scalar(slot.type);
        }
        if (auto unary = Is<Unary>(value))
            return operation(unary->op, unary->child->exprtype) && pure(unary->child, budget);
        if (auto binary = Is<Binary>(value))
            return operation(binary->op, binary->left->exprtype) &&
                   pure(binary->left, budget) && pure(binary->right, budget);
        return false;
    };
    for (auto arm : { yes, no }) {
        if (!operation(arm->op, target.type)) return false;
        int budget = 12;
        if (arm->op != T_ASSIGN) budget -= 2;
        if (!pure(arm->rhs, budget)) return false;
    }
    Truth(node->cond); auto condition = Save(I32);
    for (auto arm : { yes, no }) {
        if (arm->op == T_ASSIGN) To(arm->rhs, target.type);
        else { Read(target); To(arm->rhs, target.type); BinaryOp(arm->op, target.type, arm->line); }
    }
    Get(condition); code.Op(0x1b); Write(target);
    return true;
}

inline void Function::AggregateLiteral(Node *n, const ConstructionDestination *receiving) {
    auto t = n->exprtype;
    if (!c.Aggregate(t)) Fail(n->line, "this array/struct literal requires unsupported variable-size storage");
    auto integer_literal = [](Node *node, TypeExpr *type) {
        return Is<IntLit>(node) && IsIntT(type) && !Compiler::Varint(type) &&
            IsIntT(node->exprtype) && node->exprtype->intstorage == type->intstorage;
    };
    ConstructionDestination destination;
    if (receiving) destination = *receiving;
    else destination = FreshDestination(t, ConstructionDestination::Statement);
    auto place = destination.location;
    LocationAddress(place); code.I32Const(0); code.I32Const(int32_t(c.Size(t).size)); code.Fill();
    if (auto a = Is<ArrayLit>(n)) {
        auto elem = t->arr->sub;
        auto stride = c.Size(elem).size;
        auto start = c.Size(t).payload;
        auto count = a->fillval ? static_cast<IntLit *>(a->fillcount)->val : int64_t(a->elems.size());
        if (t->arr->akind == A_LIMITED) {
            LocationAddress(place); code.I32Const(int32_t(count)); WriteStaticArrayLength(t);
        }
        if (a->fillval) {
            // Goose evaluates a fill value once, then copies it into each slot.
            To(a->fillval, elem);
            if (integer_literal(a->fillval, elem) && static_cast<IntLit *>(a->fillval)->val == 0) {
                code.Op(0x1a);
                if (!receiving) LocationAddress(place);
                return;
            }
            auto value = Save(elem);
            auto i = Local(I32); code.I32Const(0); Set(i);
            auto done = Begin(), loop = Begin(0x03);
            Get(i); code.I32Const(int32_t(count)); code.Op(0x4f); Br(done, true);
            LocationAddress(OffsetLocation(place, start, elem)); Get(i); code.I32Const(int32_t(stride)); code.Op(0x6c); code.Op(0x6a);
            Get(value); Store(elem);
            Get(i); code.I32Const(1); code.Op(0x6a); Set(i); Br(loop); End(); End();
        } else {
            bool can_skip_zero = true;
            for (size_t i = 0; i < a->elems.size(); i++) {
                bool literal = integer_literal(a->elems[i], elem);
                if (can_skip_zero && literal && static_cast<IntLit *>(a->elems[i])->val == 0) continue;
                auto field = OffsetLocation(place, start + uint32_t(i) * stride, elem);
                if (!ConstructFreshInto(a->elems[i], field))
                    ConstructInto(a->elems[i], { field, ConstructionDestination::Statement });
                if (!literal) can_skip_zero = false;
            }
        }
    } else if (auto s = Is<StructLit>(n)) {
        auto layout = c.Size(t);
        uint32_t payload = 0;
        if (s->einst) {
            auto vi = s->einst->en->VariantIndex(s->variant);
            if (t->kind == TY_ENUM) {
                payload = layout.payload;
                LocationAddress(place); code.I32Const(vi); WriteEnumTag(c.EnumTagBytes(s->einst));
            } else if (t->kind != TY_VARIANT) Fail(n->line, "unsupported variant construction");
            layout = c.Payload(s->einst, vi);
        } else if (!s->sinst) Fail(n->line, "struct type was not resolved");
        bool can_skip_zero = true;
        for (size_t fi = 0; fi < layout.fields.size(); fi++) {
            auto init = s->InitFor(int(fi));
            if (!init) continue;
            auto ft = s->einst ? s->einst->vftypes[size_t(s->einst->en->VariantIndex(s->variant))][size_t(fi)]
                               : s->sinst->ftypes[size_t(fi)];
            if (!ft) continue; // Padding retains a declaration index, not an initializer.
            bool literal = integer_literal(init, ft);
            if (can_skip_zero && literal && static_cast<IntLit *>(init)->val == 0) continue;
            auto field = OffsetLocation(place, payload + layout.fields[fi], ft);
            if (!ConstructFreshInto(init, field)) ConstructInto(init, { field, ConstructionDestination::Statement });
            if (!literal) can_skip_zero = false;
        }
    }
    if (!receiving) LocationAddress(place);
}

inline void Function::DefaultInto(Call *n, const ConstructionDestination &destination) {
    auto t = n->rettypes[0];
    auto place = destination.location;
    LocationAddress(place); code.I32Const(0); code.I32Const(int32_t(c.Size(t).size)); code.Fill();
    if (!n->defaultinit) return;
    if (t->kind == TY_ARRAY && t->arr->akind == A_FIXED) {
        auto i = Local(I32); code.I32Const(0); Set(i);
        auto done = Begin(), loop = Begin(0x03);
        Get(i); code.I32Const(int32_t(t->arr->size)); code.Op(0x4f); Br(done, true);
        auto scope = BeginTempScope(n->defaultinit);
        LocationAddress(place); Get(i); code.I32Const(int32_t(c.Size(t->arr->sub).size)); code.Op(0x6c); code.Op(0x6a);
        To(n->defaultinit, t->arr->sub); Store(t->arr->sub);
        EndTempScope(scope);
        Get(i); code.I32Const(1); code.Op(0x6a); Set(i); Br(loop); End(); End();
    } else if (t->kind != TY_ARRAY && !ConstructFreshInto(n->defaultinit, place))
        ConstructInto(n->defaultinit, destination);
}

inline void Function::StringInto(StrLit *n, const Location &place) {
    auto type = place.storage_type;
    auto off = c.Text(n->val);
    if (n->val.size() > uint64_t(type->arr->size)) Fail(n->line, "string exceeds its fixed-array destination");
    LocationAddress(place); code.I32Const(0); code.I32Const(int32_t(c.Size(type).size)); code.Fill();
    if (type->arr->akind == A_LIMITED) {
        LocationAddress(place); code.I32Const(int32_t(n->val.size())); WriteStaticArrayLength(type);
    }
    LocationAddress(OffsetLocation(place, c.Size(type).payload, type->arr->sub));
    code.I32Const(int32_t(off)); code.I32Const(int32_t(n->val.size())); code.Copy();
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
    if (Compiler::Varint(elem)) {
        if (n->lo || n->hi) Fail(n->line, "varint elements support whole slices only");
        Get(view); return;
    }
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

inline bool Function::FoldBitLoop(ForLoop *node) {
    auto count = Is<IntLit>(node->iter);
    if (node->iterkind != IK_COUNT || !count || count->val < 1 || count->val > 8 ||
        node->idxdef || node->byref || node->vdef->isvar || !IsIntT(node->vdef->type)) return false;
    Node *body = node->body->tail;
    if (!body && node->body->stmts.size() == 1) body = node->body->stmts[0];
    else if (!node->body->stmts.empty()) return false;
    auto branch = Is<IfExpr>(body);
    if (!branch || branch->flat || !branch->elseb || !Values(branch).empty()) return false;
    auto assignment = [](Node *arm) -> Assign * {
        if (auto block = Is<Block>(arm)) {
            if (block->tail || block->stmts.size() != 1) return nullptr;
            arm = block->stmts[0];
        }
        return Is<Assign>(arm);
    };
    auto yes = assignment(branch->thenb), no = assignment(branch->elseb);
    if (!yes || !no || yes->pointee || no->pointee) return false;
    auto id = Is<Ident>(yes->lval);
    if (!id || !id->vdef || Resolve(id->vdef) == Resolve(node->vdef)) return false;
    auto state = Lookup(id->vdef, id->line);
    if (state.kind != Slot::LOCAL || !IsIntT(state.type) || !IsUnsigned(state.type->intstorage)) return false;
    auto bits = IntBits(state.type->intstorage);
    if (bits != 32 && bits != 64) return false;
    auto same = [&](Node *value) {
        auto other = Is<Ident>(value);
        if (!other || !other->vdef || !IsIntT(value->exprtype) ||
            value->exprtype->intstorage != state.type->intstorage) return false;
        auto slot = Lookup(other->vdef, other->line);
        return slot.kind == Slot::LOCAL && slot.index == state.index && slot.type == state.type;
    };
    auto literal = [](Node *value, int64_t expected) {
        auto number = Is<IntLit>(value);
        return number && IsIntT(value->exprtype) && number->val == expected;
    };
    if (!same(no->lval)) return false;
    auto test = Is<Binary>(branch->cond);
    if (!test || (test->op != T_NEQ && test->op != T_EQ) || !literal(test->right, 0)) return false;
    auto mask = Is<Binary>(test->left);
    if (!mask || mask->op != T_BITAND || !same(mask->left) || !literal(mask->right, 1)) return false;
    if (test->op == T_EQ) swap(yes, no);
    if (yes->op != T_ASSIGN) return false;
    auto mix = Is<Binary>(yes->rhs);
    if (!mix || mix->op != T_XOR) return false;
    auto polynomial = Is<IntLit>(mix->right);
    if (!polynomial || !IsIntT(polynomial->exprtype) ||
        polynomial->exprtype->intstorage != state.type->intstorage) return false;
    auto shift = [&](Node *value) {
        auto binary = Is<Binary>(value);
        return binary && binary->op == T_SHR && same(binary->left) && literal(binary->right, 1);
    };
    if (!shift(mix->left) || !((no->op == T_SHREQ && literal(no->rhs, 1)) ||
        (no->op == T_ASSIGN && shift(no->rhs)))) return false;
    uint64_t width_mask = UINT64_MAX;
    if (bits == 32) width_mask = UINT32_MAX;
    auto poly = uint64_t(polynomial->val) & width_mask;
    vector<pair<int, uint64_t>> terms { { -1, 0 } };
    for (int bit = 0; bit < count->val; bit++) {
        uint64_t column = uint64_t(1) << bit;
        for (int iteration = 0; iteration < count->val; iteration++) {
            if (column & 1) column = (column >> 1) ^ poly;
            else column >>= 1;
        }
        column &= width_mask;
        if (column) terms.emplace_back(bit, column);
    }
    // The recurrence is linear in its low bits. Independent basis columns
    // replace the serial rounds; a balanced XOR tree combines them exactly.
    Read(state); auto original = Save(state.type);
    uint8_t xor_op = 0x73, shift_op = 0x76;
    if (bits == 64) { xor_op = 0x85; shift_op = 0x88; }
    function<void(size_t, size_t)> emit = [&](size_t begin, size_t end) {
        if (end - begin > 1) {
            auto middle = begin + (end - begin) / 2;
            emit(begin, middle); emit(middle, end); code.Op(xor_op); return;
        }
        auto [bit, column] = terms[begin];
        if (bit < 0) { Get(original); Const(state.type, count->val); code.Op(shift_op); return; }
        Const(state.type, bit_cast<int64_t>(column)); Const(state.type, 0); Get(original);
        if (bits == 64) code.Op(0xa7);
        code.I32Const(1 << bit); code.Op(0x71); code.Op(0x1b);
    };
    emit(0, terms.size()); Write(state);
    return true;
}

inline bool Function::UnrollCount(ForLoop *node, const Slot &binding, TypeExpr *counter_type) {
    auto count = Is<IntLit>(node->iter);
    if (node->iterkind != IK_COUNT || !count || count->val < 1 || count->val > 8 || node->idxdef ||
        binding.kind != Slot::LOCAL || node->vdef->isvar || !IsIntT(counter_type) ||
        !IsIntT(binding.type) || counter_type->intstorage != binding.type->intstorage) return false;
    auto scalar = [](TypeExpr *type) { return type && (IsIntT(type) || type->kind == TY_BOOL); };
    auto target = [&](Node *value) {
        auto id = Is<Ident>(value);
        if (!id || !id->vdef) return false;
        auto slot = Lookup(id->vdef, id->line);
        return slot.kind == Slot::LOCAL && scalar(slot.type);
    };
    // No declarations, calls, addresses or exits: all binder uses are
    // explicit, and each copy can use the normal balanced block cleanup.
    int budget = 32;
    bool uses_counter = false;
    function<bool(Node *)> simple = [&](Node *value) {
        if (!value) return true;
        if (budget-- == 0) return false;
        switch (value->nkind) {
            case NK_Block: case NK_IfExpr: break;
            case NK_Assign: {
                auto assign = static_cast<Assign *>(value);
                if (assign->pointee || assign->op == T_DOTASSIGN || !target(assign->lval)) return false;
                break;
            }
            case NK_IncDec:
                if (!target(static_cast<IncDec *>(value)->lval)) return false;
                break;
            case NK_Ident: {
                if (!scalar(value->exprtype) || !target(value)) return false;
                auto slot = Lookup(static_cast<Ident *>(value)->vdef, value->line);
                uses_counter |= slot.index == binding.index;
                break;
            }
            case NK_Unary:
                if (static_cast<Unary *>(value)->op == T_BITAND || !scalar(value->exprtype)) return false;
                break;
            case NK_IntLit: case NK_BoolLit: case NK_Binary:
                if (!scalar(value->exprtype)) return false;
                break;
            default: return false;
        }
        bool valid = true;
        value->Children([&](Node *child) { if (valid) valid = simple(child); });
        return valid;
    };
    if (!simple(node->body)) return false;
    for (int64_t iteration = 0; iteration < count->val; iteration++) {
        if (uses_counter) { Const(binding.type, iteration); Write(binding); }
        BlockInto(node->body, {}, {});
    }
    return true;
}

inline bool Function::UnrollRange(ForLoop *node, const Slot &binding, TypeExpr *counter_type) {
    if (node->iterkind != IK_RANGE || !IsIntT(counter_type) || counter_type->intstorage != IS_I64 ||
        binding.kind != Slot::LOCAL || !IsIntT(binding.type) || binding.type->intstorage != IS_I64 ||
        node->vdef->isvar || MayMaterialize(node->body)) return false;
    auto literal = [](Node *value) -> optional<int64_t> {
        if (!value || !IsIntT(value->exprtype) || value->exprtype->intstorage != IS_I64) return {};
        if (auto number = Is<IntLit>(value); number && !number->uns) return number->val;
        if (auto unary = Is<Unary>(value); unary && unary->op == T_MINUS) {
            auto number = Is<IntLit>(unary->child);
            if (number && !number->uns && number->val != INT64_MIN && IsIntT(number->exprtype) &&
                number->exprtype->intstorage == IS_I64) return -number->val;
        }
        return {};
    };
    auto bounds = [&](ForLoop *loop, int64_t &first, int64_t &count) {
        auto range = Is<RangeExpr>(loop->iter);
        if (loop->iterkind != IK_RANGE || !range || loop->byref || loop->vdef->isvar ||
            loop->vdef->captured || addressed.count(Resolve(loop->vdef)) ||
            !IsIntT(loop->vdef->type) || loop->vdef->type->intstorage != IS_I64 ||
            !IsIntT(range->exprtype) || range->exprtype->intstorage != IS_I64) return false;
        if (loop->idxdef && (loop->idxdef->isvar || loop->idxdef->captured ||
            addressed.count(Resolve(loop->idxdef)) || !IsIntT(loop->idxdef->type) ||
            loop->idxdef->type->intstorage != IS_I64)) return false;
        auto lo = literal(range->lo), hi = literal(range->hi);
        if (!lo || !hi || *hi <= *lo || uint64_t(*hi) - uint64_t(*lo) > 8) return false;
        first = *lo; count = int64_t(uint64_t(*hi) - uint64_t(*lo)); return true;
    };
    int64_t first, count;
    if (!bounds(node, first, count)) return false;
    auto scalar = [](TypeExpr *type) { return type && (IsIntT(type) || type->kind == TY_BOOL); };
    auto local = [&](VarDef *variable) {
        auto resolved = Resolve(variable);
        return !resolved->isglobal && !resolved->captured && !resolved->reusable && !addressed.count(resolved);
    };
    // Charge nested copies, not just the original tree. Calls, addresses and
    // owners stay on the normal path; indexed accesses retain their checks.
    int budget = 384;
    function<bool(Node *, int)> simple = [&](Node *value, int copies) {
        if (!value) return true;
        budget -= copies; if (budget < 0) return false;
        switch (value->nkind) {
            case NK_Block: case NK_IfExpr: case NK_Continue: break;
            case NK_ForLoop: {
                auto loop = static_cast<ForLoop *>(value); int64_t start, trips;
                if (!bounds(loop, start, trips)) return false;
                return simple(loop->body, copies * int(trips));
            }
            case NK_VarDecl: {
                auto decl = static_cast<VarDecl *>(value);
                if (decl->byref || decl->isglobal || decl->defs.size() != 1 ||
                    !local(decl->defs[0]) || !scalar(decl->defs[0]->type)) return false;
                break;
            }
            case NK_Ident: {
                auto id = static_cast<Ident *>(value);
                if (!id->vdef || !local(id->vdef)) return false;
                auto type = Resolve(id->vdef)->type;
                if (!scalar(type) && type->kind != TY_SLICE) return false;
                break;
            }
            case NK_Assign: {
                auto assign = static_cast<Assign *>(value);
                if (assign->pointee || assign->op == T_DOTASSIGN || !scalar(assign->lval->exprtype)) return false;
                break;
            }
            case NK_IncDec:
                if (!scalar(static_cast<IncDec *>(value)->lval->exprtype)) return false;
                break;
            case NK_Unary:
                if (static_cast<Unary *>(value)->op == T_BITAND || !scalar(value->exprtype)) return false;
                break;
            case NK_Break:
                if (static_cast<Break *>(value)->val) return false;
                break;
            case NK_Return:
                if (!spec || static_cast<Return *>(value)->target != spec->sf) return false;
                break;
            case NK_IntLit: case NK_BoolLit: case NK_Binary: case NK_AsCast: case NK_Index:
                if (!scalar(value->exprtype)) return false;
                break;
            default: return false;
        }
        bool valid = true;
        value->Children([&](Node *child) { if (valid) valid = simple(child, copies); });
        return valid;
    };
    if (!simple(node->body, int(count))) return false;
    optional<Slot> index;
    if (node->idxdef) { index = Bind(node->idxdef); if (index->kind != Slot::LOCAL) return false; }
    auto done = Begin();
    auto label_depth = labels.size(), exit_depth = exits.size(), cleanup_depth = cleanups.size();
    auto private_depth = private_headers.size(), temp_depth = temp_scopes.size();
    auto live = region_live;
    for (int64_t iteration = 0; iteration < count; iteration++) {
        constant_slots.emplace(binding.index, first + iteration);
        if (index) constant_slots.emplace(index->index, iteration);
        auto step = Begin(); PushExit({ done, nullptr, {}, {}, true, step });
        BlockInto(node->body, {}, {}); exits.pop_back(); End();
        if (labels.size() != label_depth || exits.size() != exit_depth || cleanups.size() != cleanup_depth ||
            private_headers.size() != private_depth || temp_scopes.size() != temp_depth || region_live != live)
            Fail(node->line, "internal: unrolled range iteration changed control or cleanup state");
        constant_slots.erase(binding.index);
        if (index) constant_slots.erase(index->index);
    }
    End(); return true;
}

inline bool Function::UnrollWhile(While *node) {
    if (node->body->tail || node->body->stmts.size() != 2 ||
        MayMaterialize(node->cond) || MayMaterialize(node->body)) return false;
    auto assignment = Is<Assign>(node->body->stmts[0]);
    auto change = Is<IncDec>(node->body->stmts[1]);
    if (!assignment || assignment->pointee || assignment->op != T_ASSIGN || !change) return false;
    auto counter = Is<Ident>(change->lval);
    if (!counter || !counter->vdef || !IsIntT(counter->exprtype) ||
        Lookup(counter->vdef, counter->line).kind != Slot::LOCAL) return false;
    auto scalar = [](TypeExpr *type) { return type && (IsIntT(type) || type->kind == TY_FLT); };
    for (auto value : { assignment->lval, assignment->rhs }) {
        auto index = Is<Index>(value);
        if (!index) return false;
        auto object = Is<Ident>(index->obj);
        if (!object || !object->vdef || !scalar(index->exprtype)) return false;
        auto slot = Lookup(object->vdef, object->line);
        if (slot.kind != Slot::LOCAL || slot.type->kind != TY_SLICE || !scalar(slot.type->sub)) return false;
    }
    int budget = 64;
    function<bool(Node *)> pure = [&](Node *value) {
        if (!value || budget-- == 0) return false;
        auto type = value->exprtype;
        if (!type || (!scalar(type) && type->kind != TY_BOOL && type->kind != TY_SLICE)) return false;
        if (type->kind == TY_SLICE && !scalar(type->sub)) return false;
        switch (value->nkind) {
            case NK_Ident: {
                auto id = static_cast<Ident *>(value);
                if (!id->vdef) return false;
                auto slot = Lookup(id->vdef, id->line);
                if (slot.kind != Slot::LOCAL || slot.type->kind != type->kind) return false;
                break;
            }
            case NK_Unary:
                if (static_cast<Unary *>(value)->op == T_BITAND) return false;
                break;
            case NK_Dot:
                if (static_cast<Dot *>(value)->member != B_LEN) return false;
                break;
            case NK_IntLit: case NK_FltLit: case NK_BoolLit: case NK_Index: case NK_AsCast: case NK_Binary:
                break;
            default: return false;
        }
        bool valid = true;
        value->Children([&](Node *child) { if (valid) valid = pure(child); });
        return valid;
    };
    return pure(node->cond) && pure(assignment->lval) && pure(assignment->rhs) && pure(change->lval);
}

inline bool Function::FillLoop(ForLoop *node) {
    // Avoid growing a long entrypoint for one-off preparation. Repeated work
    // and ordinary callable functions can amortize the guarded bulk path.
    if (!spec || (spec->sf == c.ast.MainFunction() &&
        none_of(exits.begin(), exits.end(), [](const Exit &exit) { return exit.continue_label.has_value(); }))) return false;
    if (c.region_cursors || node->iterkind != IK_COUNT || node->byref || node->idxdef ||
        node->vdef->isvar || !IsIntT(node->vdef->type) || node->vdef->type->intstorage != IS_I64 ||
        node->body->tail || node->body->stmts.size() != 1) return false;
    auto length = Is<Dot>(node->iter);
    if (!length || length->member != B_LEN) return false;
    auto source = Is<Ident>(length->obj);
    if (!source || !source->vdef || source->exprtype->kind != TY_SLICE) return false;
    auto view = Lookup(source->vdef, source->line);
    if (view.kind != Slot::LOCAL || view.type->kind != TY_SLICE) return false;
    auto elem = view.type->sub;
    if (!IsIntT(elem) || Compiler::Varint(elem) || elem->ix) return false;
    auto width = IntBits(elem->intstorage) / 8;
    if (width != 1 && width != 2 && width != 4 && width != 8) return false;
    auto assign = Is<Assign>(node->body->stmts[0]);
    if (!assign || assign->pointee || (assign->op != T_ASSIGN && assign->op != T_DOTASSIGN)) return false;
    auto index = Is<Index>(assign->lval);
    if (!index) return false;
    auto object = Is<Ident>(index->obj), position = Is<Ident>(index->idx);
    if (!object || !object->vdef || object->exprtype->kind != TY_SLICE || !position ||
        Resolve(position->vdef) != Resolve(node->vdef)) return false;
    auto target = Lookup(object->vdef, object->line);
    if (target.kind != Slot::LOCAL || target.index != view.index || target.type != view.type) return false;
    auto value = assign->rhs;
    if (!IsIntT(value->exprtype) || value->exprtype->intstorage != elem->intstorage) return false;
    if (width != 1) {
        auto zero = Is<IntLit>(value);
        if (!zero || zero->val != 0) return false;
    }
    if (auto id = Is<Ident>(value)) {
        if (!id->vdef) return false;
        auto slot = Lookup(id->vdef, id->line);
        if (slot.kind != Slot::LOCAL || !IsIntT(slot.type) || slot.type->intstorage != elem->intstorage) return false;
    } else if (!Is<IntLit>(value)) return false;
    if (Bind(node->vdef).kind != Slot::LOCAL) return false;
    Read(view); auto packed = Save(I64);
    Get(packed); code.Op(0xa7); auto pointer = Save(I32);
    Get(packed); code.I64Const(32); code.Op(0x88); auto count = Save(I64);
    // Packed lengths are u32, so widening before multiplying by at most eight
    // cannot overflow. The physical guard also proves the final i32 byte cast.
    Get(count); code.I64Const(width); code.Op(0x7e); auto bytes = Save(I64);
    // A bulk operation checks its whole range before writing. Keep the original
    // loop for invalid physical ranges so partial writes and traps stay ordered.
    Get(pointer); code.Op(0xad); Get(bytes); code.Op(0x7c);
    code.OpU(0x3f, 0); code.Op(0xad); code.I64Const(16); code.Op(0x86); code.Op(0x58);
    Begin(0x04);
    Get(pointer); To(value, elem); if (W(elem) == I64) code.Op(0xa7);
    Get(bytes); code.Op(0xa7); code.Fill();
    code.Op(0x05);
    return true;
}

inline bool Function::CopyLoop(ForLoop *node) {
    if (!spec || (spec->sf == c.ast.MainFunction() &&
        none_of(exits.begin(), exits.end(), [](const Exit &exit) { return exit.continue_label.has_value(); }))) return false;
    if (c.region_cursors || node->iterkind != IK_COUNT || node->byref || node->idxdef || node->vdef->isvar ||
        !IsIntT(node->vdef->type) || node->vdef->type->intstorage != IS_I64 ||
        !IsIntT(node->iter->exprtype) || node->iter->exprtype->intstorage != IS_I64 ||
        node->body->tail || node->body->stmts.size() != 1) return false;
    auto assign = Is<Assign>(node->body->stmts[0]);
    if (!assign || assign->pointee || assign->op != T_ASSIGN) return false;
    auto destination = Is<Index>(assign->lval), source = Is<Index>(assign->rhs);
    auto view = [&](Index *index) -> optional<Slot> {
        if (!index || !IsIntT(index->exprtype)) return {};
        auto object = Is<Ident>(index->obj), position = Is<Ident>(index->idx);
        if (!object || !object->vdef || object->exprtype->kind != TY_SLICE || !position || !position->vdef ||
            !IsIntT(position->exprtype) || position->exprtype->intstorage != IS_I64 ||
            Resolve(position->vdef) != Resolve(node->vdef)) return {};
        auto slot = Lookup(object->vdef, object->line);
        if (slot.kind != Slot::LOCAL || slot.type->kind != TY_SLICE || !IsIntT(slot.type->sub) ||
            Compiler::Varint(slot.type->sub) || slot.type->sub->ix || slot.type->sub->intstorage != index->exprtype->intstorage) return {};
        return slot;
    };
    auto target = view(destination), input = view(source);
    if (!target || !input || target->type->sub->intstorage != input->type->sub->intstorage) return false;
    auto width = IntBits(target->type->sub->intstorage) / 8;
    if (width != 1 && width != 2 && width != 4 && width != 8) return false;
    auto count_node = node->iter;
    if (auto length = Is<Dot>(count_node)) {
        if (length->member != B_LEN) return false;
        auto object = Is<Ident>(length->obj);
        if (!object || !object->vdef || object->exprtype->kind != TY_SLICE) return false;
        auto slot = Lookup(object->vdef, object->line);
        if (slot.kind != Slot::LOCAL || slot.type->kind != TY_SLICE) return false;
    } else {
        auto id = Is<Ident>(count_node);
        if (!id || !id->vdef) return false;
        auto slot = Lookup(id->vdef, id->line);
        if (slot.kind != Slot::LOCAL || !IsIntT(slot.type) || slot.type->intstorage != IS_I64) return false;
    }
    if (Bind(node->vdef).kind != Slot::LOCAL) return false;
    To(count_node, c.ast.inttypes[IS_I64]); auto count = Save(I64);
    Read(*target); auto dst_view = Save(I64); Read(*input); auto src_view = Save(I64);
    Get(dst_view); code.Op(0xa7); code.Op(0xad); auto dst = Save(I64);
    Get(src_view); code.Op(0xa7); code.Op(0xad); auto src = Save(I64);
    // Trial policy: keep short copies on the scalar path to avoid runtime
    // memory.copy overhead. Confirm the 64-byte minimum in both engines.
    Get(count); code.I64Const(64 / width); code.Op(0x5a);
    Get(count); Get(dst_view); code.I64Const(32); code.Op(0x88); code.Op(0x58); code.Op(0x71);
    Get(count); Get(src_view); code.I64Const(32); code.Op(0x88); code.Op(0x58); code.Op(0x71);
    auto bytes = Local(I64);
    // Only bounded nonnegative counts enter the physical-span proof.
    Begin(0x04, I32);
    Get(count); code.I64Const(width); code.Op(0x7e); Set(bytes);
    code.OpU(0x3f, 0); code.Op(0xad); code.I64Const(16); code.Op(0x86); auto end = Save(I64);
    Get(dst); Get(bytes); code.Op(0x7c); Get(end); code.Op(0x58);
    Get(src); Get(bytes); code.Op(0x7c); Get(end); code.Op(0x58); code.Op(0x71);
    // memory.copy is memmove; forward scalar copies agree only before the
    // source or after its whole span. Other overlaps retain scalar propagation.
    Get(dst); Get(src); code.Op(0x58);
    Get(dst); Get(src); Get(bytes); code.Op(0x7c); code.Op(0x5a); code.Op(0x72); code.Op(0x71);
    Else(); code.I32Const(0); End(); Begin(0x04);
    Get(dst); code.Op(0xa7); Get(src); code.Op(0xa7); Get(bytes); code.Op(0xa7); code.Copy();
    Else(); return true;
}

inline optional<Slot> Function::CachedLane(Node *node) {
    if (cached_lanes.empty()) return {};
    auto index = Is<Index>(node);
    if (!index) return {};
    auto found = cached_lanes.find(index);
    if (found == cached_lanes.end()) return {};
    return found->second[lane_value];
}

inline void Function::CacheLanes(ForLoop *node) {
    struct Array { Slot slot; vector<Index *> uses; bool valid = true; };
    vector<Array> arrays;
    unordered_set<VarDef *> declarations, lane_ids;
    auto is_lane = [&](Node *value) {
        auto mod = Is<Binary>(value);
        return mod && find(node->lanemods.begin(), node->lanemods.end(), mod) != node->lanemods.end();
    };
    function<void(Node *)> scan = [&](Node *value) {
        if (!value) return;
        if (auto decl = Is<VarDecl>(value)) {
            auto local = decl->defs[0];
            declarations.insert(Resolve(local));
            if (!local->isvar && local->type->kind == TY_INT && local->type->intstorage == IS_I64 &&
                decl->inits.size() == 1 && is_lane(decl->inits[0])) lane_ids.insert(Resolve(local));
        }
        if (auto index = Is<Index>(value)) {
            auto object = Is<Ident>(index->obj);
            if (object && object->vdef && IsIntT(index->exprtype)) {
                auto variable = Resolve(object->vdef);
                auto slot = Lookup(variable, object->line);
                auto type = slot.type;
                if (slot.kind == Slot::FRAME && type->kind == TY_ARRAY && type->arr->akind == A_FIXED &&
                    type->arr->size == node->stripk && IsIntT(type->arr->sub) &&
                    IntBits(type->arr->sub->intstorage) >= 32 && !variable->captured &&
                    !variable->reusable && !addressed.count(variable) && !addressed.count(object->vdef)) {
                    auto found = find_if(arrays.begin(), arrays.end(), [&](auto &array) {
                        return array.slot.index == slot.index && array.slot.type == type;
                    });
                    if (found == arrays.end()) { arrays.push_back({ slot, {} }); found = prev(arrays.end()); }
                    auto id = Is<Ident>(index->idx);
                    found->valid &= is_lane(index->idx) || (id && id->vdef &&
                        IsIntT(id->exprtype) && id->exprtype->intstorage == IS_I64 && lane_ids.count(Resolve(id->vdef)));
                    found->uses.push_back(index);
                }
            }
        }
        value->Children(scan);
    };
    scan(node->body);
    unordered_set<Index *> uses;
    int count = 0;
    for (auto &array : arrays) if (array.valid) {
        count += node->stripk;
        uses.insert(array.uses.begin(), array.uses.end());
    }
    if (!count || count > 8) return;
    // Cache reads only while every write is either a scalar local or one of
    // these array lanes. Write-through stores preserve aliases and traps.
    bool valid = true;
    function<void(Node *)> writes = [&](Node *value) {
        if (!value || !valid) return;
        Node *target = nullptr;
        if (auto assign = Is<Assign>(value)) target = assign->lval;
        if (auto inc = Is<IncDec>(value)) target = inc->lval;
        if (target) {
            if (auto id = Is<Ident>(target)) {
                if (!declarations.count(Resolve(id->vdef))) {
                    auto slot = Lookup(id->vdef, id->line);
                    valid = slot.kind == Slot::LOCAL && (IsIntT(slot.type) || slot.type->kind == TY_BOOL);
                }
            } else valid = uses.count(Is<Index>(target));
        }
        value->Children(writes);
    };
    writes(node->body);
    if (!valid) return;
    for (auto &array : arrays) if (array.valid) {
        auto elem = array.slot.type->arr->sub;
        vector<Slot> values;
        for (int lane = 0; lane < node->stripk; lane++) {
            auto place = OffsetLocation({ array.slot.type, array.slot }, lane * c.Size(elem).size, elem);
            ReadLocation(place, elem); values.push_back({ Slot::LOCAL, Save(elem), elem });
        }
        for (auto use : array.uses) cached_lanes.emplace(use, values);
    }
}

inline bool Function::StripSequence(ForLoop *node, const Slot &binding, const Slot &index,
                                    uint32_t view, uint32_t position, uint32_t limit, TypeExpr *elem) {
    auto width = node->stripk;
    if (c.needs_regions || c.region_cursors || width < 2 || width > 8 || node->lanemods.empty() ||
        !node->fixedlen || node->byref || binding.kind != Slot::LOCAL || index.kind != Slot::LOCAL ||
        node->vdef->isvar || node->idxdef->isvar || !IsIntT(index.type) || index.type->intstorage != IS_I64 ||
        !IsIntT(elem) || !IsIntT(binding.type) || elem->intstorage != binding.type->intstorage ||
        node->body->tail) return false;
    auto source = Is<Ident>(node->iter);
    if (!source || !source->vdef || source->exprtype->kind == TY_REF) return false;
    auto source_type = Lookup(source->vdef, source->line).type;
    if (source_type->kind != TY_SLICE &&
        !(source_type->kind == TY_ARRAY && source_type->arr->akind == A_FIXED)) return false;
    for (auto mod : node->lanemods) {
        auto counter = Is<Ident>(mod->left);
        auto divisor = Is<IntLit>(mod->right);
        if (mod->op != T_MOD || !counter || !counter->vdef ||
            Resolve(counter->vdef) != Resolve(node->idxdef) || !divisor || divisor->val != width ||
            divisor->uns || !IsIntT(mod->exprtype) || mod->exprtype->intstorage != IS_I64 ||
            !IsIntT(counter->exprtype) || counter->exprtype->intstorage != IS_I64 ||
            !IsIntT(divisor->exprtype) || divisor->exprtype->intstorage != IS_I64) return false;
    }
    auto scalar = [](TypeExpr *type) { return type && (IsIntT(type) || type->kind == TY_BOOL); };
    int budget = 128;
    function<bool(Node *)> simple = [&](Node *value) {
        if (!value) return true;
        if (budget-- == 0) return false;
        switch (value->nkind) {
            case NK_Block: break;
            case NK_VarDecl: {
                auto decl = static_cast<VarDecl *>(value);
                if (decl->byref || decl->isglobal || decl->defs.size() != 1) return false;
                auto local = decl->defs[0];
                if (!scalar(local->type) || local->captured || local->reusable || addressed.count(local)) return false;
                break;
            }
            case NK_Assign: {
                auto assign = static_cast<Assign *>(value);
                if (assign->pointee || assign->op == T_DOTASSIGN || !scalar(assign->lval->exprtype)) return false;
                break;
            }
            case NK_IncDec:
                if (!scalar(static_cast<IncDec *>(value)->lval->exprtype)) return false;
                break;
            case NK_Ident: {
                auto id = static_cast<Ident *>(value);
                if (!id->vdef) return false;
                auto type = Resolve(id->vdef)->type;
                if (!scalar(type) && type->kind != TY_SLICE &&
                    !(type->kind == TY_ARRAY && type->arr->akind == A_FIXED)) return false;
                break;
            }
            case NK_Unary:
                if (static_cast<Unary *>(value)->op == T_BITAND || !scalar(value->exprtype)) return false;
                break;
            case NK_IntLit: case NK_BoolLit: case NK_Binary: case NK_AsCast: case NK_Index:
                if (!scalar(value->exprtype)) return false;
                break;
            default: return false;
        }
        bool valid = true;
        value->Children([&](Node *child) { if (valid) valid = simple(child); });
        return valid;
    };
    if (!simple(node->body)) return false;
    auto previous_mods = lane_mods;
    auto previous_lane = lane_value;
    decltype(cached_lanes) previous_cache;
    previous_cache.swap(cached_lanes);
    CacheLanes(node);
    // Defer only private u32 lanes in a nontrapping body. Other memory
    // accesses could observe intermediate writes, including through aliases.
    bool deferred = !c.opts.debug && elem->intstorage == IS_U8 &&
        (width == 4 || width == 8) && !cached_lanes.empty();
    vector<pair<Slot, vector<Slot>>> arrays;
    for (auto &[use, values] : cached_lanes) {
        auto object = static_cast<Ident *>(use->obj);
        auto array = Lookup(object->vdef, object->line);
        deferred &= values[0].type->intstorage == IS_U32;
        if (none_of(arrays.begin(), arrays.end(), [&](auto &entry) { return entry.first.index == array.index; }))
            arrays.push_back({ array, values });
    }
    sort(arrays.begin(), arrays.end(), [](auto &a, auto &b) { return a.first.index < b.first.index; });
    function<void(Node *)> nontrapping = [&](Node *value) {
        if (!value || !deferred) return;
        if (auto use = Is<Index>(value)) deferred = cached_lanes.count(use);
        if (auto binary = Is<Binary>(value)) {
            if (binary->op == T_DIV || binary->op == T_MOD)
                deferred = find(node->lanemods.begin(), node->lanemods.end(), binary) != node->lanemods.end();
        }
        if (auto assign = Is<Assign>(value))
            deferred &= assign->op != T_DIVEQ && assign->op != T_MODEQ;
        if (auto cast = Is<AsCast>(value)) deferred &= !cast->totype->ix;
        if (auto unary = Is<Unary>(value))
            deferred &= unary->op == T_MINUS || unary->op == T_BITNOT || unary->op == T_NOT;
        value->Children(nontrapping);
    };
    nontrapping(node->body);
    // A straight-line u32 recurrence may update one private lane array. All
    // temporaries belong to this iteration; no ordinal or cross-lane values
    // escape. Match the checked AST directly, with no intermediate program.
    bool vectorized = deferred && arrays.size() == 1;
    vector<VarDef *> vector_ids;
    auto vector_id = [&](VarDef *id) { return find(vector_ids.begin(), vector_ids.end(), Resolve(id)) != vector_ids.end(); };
    unordered_set<Node *> lane_declarations;
    auto u32 = [](TypeExpr *type) { return IsIntT(type) && type->intstorage == IS_U32 && !type->ix; };
    function<bool(Node *)> vector_value = [&](Node *value) {
        if (auto id = Is<Ident>(value))
            return Resolve(id->vdef) == Resolve(node->vdef) || vector_id(id->vdef);
        if (!u32(value->exprtype)) return false;
        if (Is<IntLit>(value)) return true;
        if (auto index = Is<Index>(value)) return cached_lanes.count(index) != 0;
        if (auto cast = Is<AsCast>(value)) {
            auto from = cast->child->exprtype;
            return u32(cast->totype) && (u32(from) ||
                (IsIntT(from) && from->intstorage == IS_U8 && !from->ix)) && vector_value(cast->child);
        }
        auto binary = Is<Binary>(value);
        if (!binary || !u32(binary->left->exprtype) || !vector_value(binary->left)) return false;
        switch (binary->op) {
            case T_SHL: case T_SHR: return Is<IntLit>(binary->right) != nullptr;
            case T_PLUS: case T_MINUS: case T_MUL: case T_XOR: case T_BITAND: case T_BITOR:
                return vector_value(binary->right);
            default: return false;
        }
    };
    Assign *final_store = nullptr;
    if (!node->body->stmts.empty()) final_store = Is<Assign>(node->body->stmts.back());
    vectorized &= final_store && final_store->op == T_ASSIGN && cached_lanes.count(Is<Index>(final_store->lval));
    for (auto statement : node->body->stmts) {
        if (!vectorized) break;
        if (auto decl = Is<VarDecl>(statement)) {
            if (decl->inits.size() != 1) { vectorized = false; break; }
            auto variable = Resolve(decl->defs[0]);
            if (find(node->lanemods.begin(), node->lanemods.end(), Is<Binary>(decl->inits[0])) != node->lanemods.end()) {
                lane_declarations.insert(statement); continue;
            }
            vectorized = u32(variable->type) && vector_value(decl->inits[0]);
            vector_ids.push_back(variable);
        } else if (auto assign = Is<Assign>(statement)) {
            if (assign == final_store) vectorized = vector_value(assign->rhs);
            else {
                auto id = Is<Ident>(assign->lval);
                vectorized = assign->op == T_ASSIGN && id && vector_id(id->vdef) && vector_value(assign->rhs);
            }
        } else vectorized = false;
    }
    // Defer stores only when the complete SIMD proof succeeds. Other bodies
    // keep one ordered scalar loop with the existing write-through cache.
    deferred = vectorized;
    lane_mods = &node->lanemods;
    auto emit_lane = [&](int lane) {
        lane_value = lane;
        // Preserve each iteration's load, stores and possible traps in order.
        Get(view); code.Op(0xa7); Get(position); code.Op(0xa7);
        code.I32Const(int32_t(c.Size(elem).size)); code.Op(0x6c); code.Op(0x6a);
        Load(elem); Convert(elem, binding.type, node->line); Write(binding);
        Get(position); Write(index);
        BlockInto(node->body, {}, {});
        Get(position); code.I64Const(1); code.Op(0x7c); Set(position);
    };
    auto emit_tail = [&]() {
        auto done = Begin();
        for (int lane = 0; lane < width; lane++) {
            Get(position); Get(limit); code.Op(0x5a); Br(done, true);
            emit_lane(lane);
        }
        End();
    };
    auto emit_loop = [&]() {
        auto done = Begin(), again = Begin(0x03);
        Get(limit); Get(position); code.Op(0x7d); code.I64Const(width); code.Op(0x54); Br(done, true);
        for (int lane = 0; lane < width; lane++) emit_lane(lane);
        Br(again); End(); End(); emit_tail();
    };
    auto emit_vectors = [&]() {
        vector<uint32_t> states;
        auto &array = arrays[0].first;
        for (int group = 0; group < width / 4; group++) {
            SlotAddress(array); code.OpU(0xfd, 0); code.U(0); code.U(group * 16);
            states.push_back(Save(V128));
        }
        unordered_map<VarDef *, uint32_t> temporaries;
        for (auto id : vector_ids) temporaries.emplace(id, Local(V128));
        auto bytes = Local(V128);
        auto done = Begin(), again = Begin(0x03);
        Get(limit); Get(position); code.Op(0x7d); code.I64Const(width); code.Op(0x54); Br(done, true);
        for (int group = 0; group < width / 4; group++) {
            Get(view); code.Op(0xa7); Get(position); code.Op(0xa7); code.Op(0x6a);
            code.OpU(0xfd, 0x5c); code.U(0); code.U(group * 4); // v128.load32_zero
            code.OpU(0xfd, 0x89); code.OpU(0xfd, 0xa9); Set(bytes); // unsigned byte -> word -> dword
            function<void(Node *)> emit_value = [&](Node *value) {
                if (auto id = Is<Ident>(value)) {
                    if (Resolve(id->vdef) == Resolve(node->vdef)) Get(bytes);
                    else Get(temporaries.at(Resolve(id->vdef)));
                } else if (auto literal = Is<IntLit>(value)) {
                    code.I32Const(int32_t(literal->val)); code.OpU(0xfd, 0x11);
                } else if (Is<Index>(value)) Get(states[group]);
                else if (auto cast = Is<AsCast>(value)) emit_value(cast->child);
                else {
                    auto binary = static_cast<Binary *>(value);
                    emit_value(binary->left);
                    if (binary->op == T_SHL || binary->op == T_SHR) {
                        code.I32Const(int32_t(static_cast<IntLit *>(binary->right)->val) & 31);
                        if (binary->op == T_SHL) code.OpU(0xfd, 0xab);
                        else code.OpU(0xfd, 0xad);
                    } else {
                        emit_value(binary->right);
                        switch (binary->op) {
                            case T_PLUS: code.OpU(0xfd, 0xae); break;
                            case T_MINUS: code.OpU(0xfd, 0xb1); break;
                            case T_MUL: code.OpU(0xfd, 0xb5); break;
                            case T_XOR: code.OpU(0xfd, 0x51); break;
                            case T_BITAND: code.OpU(0xfd, 0x4e); break;
                            case T_BITOR: code.OpU(0xfd, 0x50); break;
                            default: break;
                        }
                    }
                }
            };
            for (auto statement : node->body->stmts) {
                if (lane_declarations.count(statement)) continue;
                if (auto decl = Is<VarDecl>(statement)) {
                    emit_value(decl->inits[0]); Set(temporaries.at(Resolve(decl->defs[0])));
                } else {
                    auto assign = static_cast<Assign *>(statement); emit_value(assign->rhs);
                    if (assign == final_store) Set(states[group]);
                    else Set(temporaries.at(Resolve(static_cast<Ident *>(assign->lval)->vdef)));
                }
            }
        }
        Get(position); code.I64Const(width); code.Op(0x7c); Set(position);
        Br(again); End(); End();
        // Scalar tails reuse the existing lane cache. Extract after the vector
        // loop, then flush through the same deferred-store path as scalar code.
        for (int lane = 0; lane < width; lane++) {
            Get(states[lane / 4]); code.OpU(0xfd, 0x1b); code.Byte(lane % 4);
            Write(arrays[0].second[lane]);
        }
        emit_tail();
    };
    if (deferred) {
        // Compute in i64 before narrowing addresses. Invalid or overlapping
        // views keep the original ordered loads and write-through stores.
        Get(view); code.Op(0xa7); code.Op(0xad); auto start = Save(I64);
        Get(start); Get(limit); code.I64Const(c.Size(elem).size); code.Op(0x7e); code.Op(0x7c);
        auto end = Save(I64);
        Get(end); code.OpU(0x3f, 0); code.Op(0xad); code.I64Const(16); code.Op(0x86); code.Op(0x58);
        for (auto &[array, values] : arrays) {
            SlotAddress(array); code.Op(0xad); auto address = Save(I64);
            Get(end); Get(address); code.Op(0x58);
            Get(start); Get(address); code.I64Const(c.Size(array.type).size); code.Op(0x7c); code.Op(0x5a);
            code.Op(0x72); code.Op(0x71);
        }
        if (vectorized) {
            Get(limit); code.I64Const(width); code.Op(0x5a); code.Op(0x71);
        }
        Begin(0x04);
        defer_lane_stores = true;
        if (vectorized) emit_vectors();
        else emit_loop();
        defer_lane_stores = false;
        for (auto &[array, values] : arrays) {
            for (int lane = 0; lane < width; lane++) {
                Read(values[lane]);
                Write({ Slot::FRAME, array.index + uint32_t(lane) * 4, values[lane].type });
            }
        }
        Else(); emit_loop(); End();
    } else {
        emit_loop();
    }
    lane_mods = previous_mods;
    lane_value = previous_lane;
    cached_lanes.swap(previous_cache);
    return true;
}

inline void Function::For(ForLoop *n) {
    if (FoldBitLoop(n)) return;
    auto bulk = FillLoop(n);
    if (!bulk) bulk = CopyLoop(n);
    auto binding = Bind(n->vdef);
    optional<Slot> indexbinding;
    if (n->idxdef) indexbinding = Bind(n->idxdef);
    auto range = Is<RangeExpr>(n->iter);
    bool numeric = n->iterkind == IK_RANGE || n->iterkind == IK_COUNT;
    auto ct = numeric ? (range ? range->exprtype : n->iter->exprtype) : c.ast.inttypes[IS_I64];
    if (numeric && UnrollCount(n, binding, ct)) return;
    if (numeric && UnrollRange(n, binding, ct)) return;
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
    if (numeric && ByteStencilLoop(n, binding, ct, lo, hi)) return;
    optional<uint32_t> encoded_cursor, encoded_base;
    if (!numeric && Compiler::Varint(elem)) {
        Get(view); code.Op(0xa7); encoded_cursor = Save(I32);
        Get(*encoded_cursor); encoded_base = Save(I32);
    }
    if (!numeric && indexbinding && StripSequence(n, binding, *indexbinding, view, lo, hi, elem)) return;
    optional<uint32_t> ordinal;
    if (indexbinding) { ordinal = Local(I64); code.I64Const(0); Set(*ordinal); }
    auto done = Begin(), again = Begin(0x03);
    if (!numeric && !n->fixedlen) {
        sequence(); Set(view); Get(view); code.I64Const(32); code.Op(0x88); Set(hi);
    }
    Get(lo); Get(hi); BinaryOp(T_GTEQ, ct, n->line); Br(done, true);
    if (numeric) { Get(lo); Convert(ct, binding.type, n->line); Write(binding); }
    else if (encoded_cursor) {
        if (!n->fixedlen) {
            Get(view); code.Op(0xa7); auto current_base = Save(I32);
            Get(current_base); Get(*encoded_base); code.Op(0x47); Begin(0x04);
            Get(WalkVarintElements(current_base, lo, EncodedReadLimit(current_base), n->line)); Set(*encoded_cursor);
            Get(current_base); Set(*encoded_base); End();
        }
        auto decoded = ReadVarintElement(*encoded_cursor, EncodedReadLimit(*encoded_cursor), n->line);
        // CheckFor represents variable elements as encoded references even
        // when the source loop omits '&'. Use its checked binding type.
        if (binding.type->kind == TY_REF) Get(*encoded_cursor);
        else { Get(decoded.first); Convert(c.ast.inttypes[IS_I64], binding.type, n->line); }
        Write(binding);
    } else {
        Get(view); code.Op(0xa7); Get(lo); code.Op(0xa7);
        code.I32Const(int32_t(c.Size(elem).size)); code.Op(0x6c); code.Op(0x6a);
        if (!n->byref || elem->kind == TY_REF) { Load(elem); Convert(elem, binding.type, n->line); }
        Write(binding);
    }
    if (indexbinding) { Get(*ordinal); Convert(c.ast.inttypes[IS_I64], indexbinding->type, n->line); Write(*indexbinding); }
    auto step = Begin(); PushExit({ done, nullptr, {}, {}, true, step });
    BlockInto(n->body, {}, {}); exits.pop_back(); End();
    if (encoded_cursor) {
        auto decoded = ReadVarintElement(*encoded_cursor, EncodedReadLimit(*encoded_cursor), n->line);
        Get(decoded.second); Set(*encoded_cursor);
    }
    // The counter's type is the range's type, not a narrowed loop binding.
    Get(lo); Const(ct, 1); code.Op(W(ct) == I64 ? 0x7c : 0x6a); Normalize(ct); Set(lo);
    if (ordinal) { Get(*ordinal); code.I64Const(1); code.Op(0x7c); Set(*ordinal); }
    Br(again); End(); End();
    if (bulk) End();
}

inline void Function::EmitCall(Call *n, bool adapt_result, const ResultDestinations &destinations, bool elements,
                               const vector<Node *> *arguments) {
    if (n->builtin >= 0) { Builtin(n, adapt_result); return; }
    auto args = n->ValueArgNodes();
    if (arguments) args = *arguments;
    if (n->fvbody) {
        EmitFunctionValue(n, adapt_result, destinations, elements);
        return;
    }
    if (!n->dispatch.empty()) { EmitDispatch(n, adapt_result, destinations); return; }
    auto sp = n->spec;
    if (!sp || (!c.function_index.count(sp) && !c.intrinsic_opcode.count(sp)))
        Fail(n->line, "call has no reachable concrete specialization");
    if (!elements && !n->defaultinit && !c.intrinsic_opcode.count(sp) && args.size() == 1 &&
        none_of(destinations.begin(), destinations.end(), [](const auto &destination) { return bool(destination); }) &&
        PopcountWrapper(sp) && c.Leaf(sp)) {
        auto parameter = sp->params[0]->type, result = sp->rets[0];
        // To includes the original formal-width normalization and evaluates
        // the argument once before replacing the complete private wrapper.
        To(args[0], parameter);
        if (W(parameter) == I64) code.Op(0x7b);
        else code.Op(0x69);
        Convert(parameter, result, n->line);
        if (adapt_result) {
            if (n->exprtype->kind == TY_VOID) code.Op(0x1a);
            else Convert(result, n->exprtype, n->line);
        }
        return;
    }
    auto receiving = destinations;
    if (receiving.empty() && adapt_result && sp->rets.size() == 1 && Compiler::VariantSource(sp->rets[0]) && Compiler::RegionEnum(n->exprtype))
        receiving = { TemporaryDestination(n->exprtype, n->line) };
    for (size_t i = 0; i < sp->rets.size(); i++) if (Compiler::RegionOwner(sp->rets[i])) {
        if (!receiving.empty()) {
            if (receiving.size() != sp->rets.size()) Fail(n->line, "owned call result channel arity mismatch");
            if (receiving[i]) CheckRegionDestination(sp->rets[i], *receiving[i], n->line);
        }
    }
    vector<VarDef *> ps; for (auto p : sp->params) if (p->type->kind != TY_FN) ps.push_back(p);
    if (args.size() != ps.size()) Fail(n->line, "function-value arguments must be eliminated by the Goose optimizer");
    auto prepared_enums = PrepareEnumResults(sp->rets, receiving, n->line, sp->rets.size() != 1 || Compiler::RegionEnum(n->exprtype));
    receiving = prepared_enums.producers;
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
    // Environments share the binding slot itself, including mutable reference
    // and slice bindings. Captured owners retain their caller-owned region.
    for (auto capture : c.captures[sp]) SlotAddress(Lookup(n->FreeVarArg(capture), n->line));
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
    if (!run && !sp->needs.empty() && VarintValueToRaw(sp->rets, receiving))
        Fail(n->line, "cancelable varint value results require qualified raw landing");
    auto plan = PlanRegionResults(sp->rets, receiving, n->line, run);
    ApplyPreparedEnumResults(plan, prepared_enums);
    if (run) {
        plan.producers[0]->elements = true;
        if (destinations.empty() || !destinations[0]) plan.values[0]->elements = true;
    }
    receiving = plan.producers;
    for (auto &destination : receiving) if (destination) RebaseEscapeStage(*destination);
    for (size_t i = 0; i < sp->rets.size(); i++) if (auto t = sp->rets[i]; c.Aggregate(t)) {
        if (Compiler::RegionOwner(t)) {
            LocationAddress(receiving[i]->location);
            if (c.region_cursors) Get(Publication(*receiving[i]));
        }
        else LocationAddress(FreshDestination(t, ConstructionDestination::Activation).location);
    }
    if (auto intrinsic = c.intrinsic_opcode.find(sp); intrinsic != c.intrinsic_opcode.end())
        code.Op(intrinsic->second);
    else {
        auto target = c.function_index.at(sp);
        if (run) target = c.run_index.at(sp);
        else target = c.ConstantTarget(n, target);
        RecordRegionCall(sp, n->line); CallIndex(target);
        if (!sp->sf->isextern && !c.Leaf(sp)) CheckPendingEffect(n->line);
    }
    // The frontend forbids results referring into a by-value parameter's
    // private owner. External references carried by its elements survive.
    // These balanced cleanup instructions preserve the Wasm call results.
    EndArgumentGroup(group, anonymous_serial != group.serial);
    PublishRegionResults(sp->rets, plan, n->line);
    ClosePreparedEnumResults(prepared_enums);
    if (adapt_result && sp->rets.size() == 1) {
        if (n->exprtype->kind == TY_VOID) code.Op(0x1a);
        else Convert(plan.enum_payloads[0] ? plan.values[0]->location.storage_type : sp->rets[0], n->exprtype, n->line);
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
            if (!nested) { Get(ptr); Get(len); CallIndex(Compiler::WRITE); return; }
            PrintText("\"");
            auto start = Local(I32), index = Local(I32);
            code.I32Const(0); Set(start); code.I32Const(0); Set(index);
            auto done = Begin(), loop = Begin(0x03);
            Get(index); Get(len); code.Op(0x4f); Br(done, true);
            Get(ptr); Get(index); code.Op(0x6a); code.Mem(0x2d); auto byte = Save(I32);
            for (auto [character, escape] : vector<pair<int32_t, string_view>> {
                { '"', "\\\"" }, { '\\', "\\\\" }, { '\n', "\\n" }, { '\r', "\\r" }, { '\t', "\\t" } }) {
                Get(byte); code.I32Const(character); code.Op(0x46); Begin(0x04);
                Get(ptr); Get(start); code.Op(0x6a); Get(index); Get(start); code.Op(0x6b); CallIndex(Compiler::WRITE);
                PrintText(escape); Get(index); code.I32Const(1); code.Op(0x6a); Set(start); End();
            }
            Get(index); code.I32Const(1); code.Op(0x6a); Set(index); Br(loop); End(); End();
            Get(ptr); Get(start); code.Op(0x6a); Get(len); Get(start); code.Op(0x6b); CallIndex(Compiler::WRITE);
            PrintText("\""); return;
        }
        PrintText("[");
        auto i = Local(I32); code.I32Const(0); Set(i);
        auto done = Begin(), loop = Begin(0x03);
        Get(i); Get(len); code.Op(0x4f); Br(done, true);
        Get(i); Begin(0x04); PrintText(", "); End();
        if (Compiler::Varint(elem)) {
            auto decoded = ReadVarintElement(ptr, EncodedReadLimit(ptr), line);
            Print(c.ast.inttypes[IS_I64], decoded.first, line, true);
            Get(decoded.second); Set(ptr);
        } else {
            Get(ptr); Get(i); code.I32Const(int32_t(c.Size(elem).size)); code.Op(0x6c); code.Op(0x6a); Load(elem);
            auto e = Save(elem); Print(elem, e, line, true);
        }
        Get(i); code.I32Const(1); code.Op(0x6a); Set(i); Br(loop); End(); End();
        PrintText("]"); return;
    }
    if ((t->kind == TY_STRUCT || t->kind == TY_VARIANT) && c.ClosedPrintable(t)) {
        auto fields = c.RecordFields(t); auto &definitions = c.RecordFieldDefs(t);
        if (t->kind == TY_VARIANT && definitions.empty()) {
            PrintText(string(t->var->adt->enu->inst->en->name) + "." + string(t->var->variant->name)); return;
        }
        string name;
        if (t->kind == TY_STRUCT) t->Dump(name); else name = t->var->variant->name;
        PrintText(name + " { "); bool first = true;
        for (size_t i = 0; i < fields.size(); i++) {
            if (definitions[i].ispad) continue;
            if (!first) PrintText(", ");
            first = false;
            Get(value); RecordFieldAddress(t, i, line); Load(fields[i]);
            Print(fields[i], Save(fields[i]), line, true);
        }
        PrintText(" }"); return;
    }
    if (t->kind == TY_ENUM && c.ClosedPrintable(t)) {
        auto ei = t->enu->inst;
        Get(value); ReadEnumTag(c.EnumTagBytes(ei)); auto tag = Save(I32); auto done = Begin();
        for (size_t i = 0; i < ei->vftypes.size(); i++) {
            Get(tag); code.I32Const(int32_t(i)); code.Op(0x46); Begin(0x04);
            auto variant = c.EnumVariantType(ei, int(i), line);
            Get(value); code.I32Const(int32_t(c.FixedLayout(t).payload)); code.Op(0x6a);
            Print(variant, Save(I32), line, nested); Br(done); End();
        }
        Abort(line, "invalid enum tag"); End(); return;
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
                if (Compiler::RegionRecord(t)) Fail(arg->line, Compiler::RegionVariant(t) ?
                    "variable-variant rendering is not supported" : "variable-struct rendering is not supported");
                if (Compiler::RegionEnum(t)) Fail(arg->line, "variable-mode enum rendering is not supported");
                if (Compiler::RegionArray(t)) {
                    Get(v); PackArrayView(t); v = Save(I64);
                    t = c.ast.SliceOf(t->arr->sub, arg->line);
                }
                if (c.Aggregate(t)) {
                    // A shallow byte copy would leave pointers into storage
                    // that later arguments can mutate. Refuse this rendering
                    // until recursive snapshots have an explicit contract.
                    if (!c.ClosedPrintable(t))
                        Fail(arg->line, "printing aggregates containing references or slices is not supported");
                    v = CopyCaptured({ t, v, CapturedValue::BorrowedFixed }).value_local;
                } else if (t->kind == TY_SLICE) {
                    auto elem = t->sub;
                    if (!Compiler::Varint(elem) && !c.ClosedPrintable(elem))
                        Fail(arg->line, "printing slices with indirect aggregate elements is not supported");
                    Get(v); code.I64Const(32); code.Op(0x88); code.Op(0xa7);
                    auto len = Save(I32);
                    uint32_t bytes;
                    if (Compiler::Varint(elem)) {
                        Get(v); code.Op(0xa7); auto base = Save(I32);
                        Get(len); code.Op(0xad); auto count = Save(I64);
                        Get(WalkVarintElements(base, count, EncodedReadLimit(base), arg->line));
                        Get(base); code.Op(0x6b); bytes = Save(I32);
                    } else {
                        Get(len); code.I32Const(int32_t(c.Size(elem).size)); code.Op(0x6c); bytes = Save(I32);
                    }
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
                ReadArrayCapacity(Save(I32)); code.Op(0xad);
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
            DefaultInto(n, destination);
            LocationAddress(destination.location); if (adapt_result) Convert(t, n->exprtype, n->line); return;
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
    if (requested.empty() && adapt_result && own.size() == 1 && Compiler::VariantSource(own[0]) && Compiler::RegionEnum(node->exprtype))
        requested = { TemporaryDestination(node->exprtype, node->line) };
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
    auto prepared_enums = PrepareEnumResults(own, requested, node->line, own.size() != 1 || Compiler::RegionEnum(node->exprtype));
    auto plan = PlanRegionResults(own, prepared_enums.producers, node->line, own.size() == 1 && own[0]->kind == TY_ARRAY && own[0]->arr->akind == A_VAR, true);
    ApplyPreparedEnumResults(plan, prepared_enums);
    auto &receiving = plan.producers;
    for (auto &destination : receiving) if (destination) {
        destination->open0 = destination->construction->open;
        destination->escape_stage = false;
    }
    vector<uint32_t> values;
    for (auto type : own) values.push_back(Local(type));
    auto named = BindNamedResults(node->body, node->sf, own, receiving, true);
    for (auto variable : named) {
        inline_named_regions.insert(variable); named_regions.at(variable).construction->open++;
    }
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
    for (auto variable : named) {
        named_regions.at(variable).construction->open--;
        inline_named_regions.erase(variable); named_regions.erase(variable);
    }
    for (auto value : values) Get(value);
    PublishRegionResults(own, plan, node->line);
    ClosePreparedEnumResults(prepared_enums);
    if (adapt_result && own.size() == 1 && types.size() == 1)
        Convert(plan.enum_payloads[0] ? plan.values[0]->location.storage_type : own[0], types[0], node->line);
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
            auto receiving = exits.back().destinations;
            BlockInto(static_cast<EarlyBlock *>(n)->body, ts, vs, receiving); exits.pop_back();
        }
        End(); return;
    }
    auto m = Is<MatchExpr>(n);
    if (!m) Fail(n->line, "internal: unsupported value control construct");
    auto t = m->scrutinee->exprtype;
    Expr(m->scrutinee);
    if (t->kind == TY_REF) { Load(t->ref->sub); t = t->ref->sub; }
    optional<uint32_t> base, enum_owner;
    if (t->kind == TY_ENUM) {
        W(t); if (Compiler::RegionEnum(t)) { enum_owner = Save(I32); Get(*enum_owner); code.Mem(0x28, 2); }
        base = Save(I32); Get(*base); ReadEnumTag(c.EnumTagBytes(t->enu->inst));
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
        auto owned_payload = arm.binder && Compiler::RegionVariant(arm.binder->type);
        auto scope = BeginTempScope(arm.body, owned_payload);
        if (arm.binder) {
            if (!base || (arm.pat.byref && !Compiler::RegionEnum(t)))
                Fail(n->line, "only variable-mode enum payloads bind by reference");
            auto slot = Bind(arm.binder);
            if (enum_owner) {
                auto variant = arm.binder->type;
                if (variant->kind == TY_REF) variant = variant->ref->sub;
                LocationAddress(EnumPayloadLocation({ t, AddressLocal { *enum_owner } }, variant, n->line));
            } else { Get(*base); code.I32Const(int32_t(c.Size(t).payload)); code.Op(0x6a); }
            if (owned_payload) {
                auto source = Save(I32); Location place { arm.binder->type, slot };
                AcquireRegion(place, n->line);
                private_headers.push_back({ TailHeaderLocation(place), cleanups.size() });
                ConstructRecordFromCaptured(arm.binder->type, source, { place, ConstructionDestination::Block }, n->line);
            } else if (arm.binder->type->kind == TY_VARIANT && EmptyLayout(c.RecordFieldDefs(arm.binder->type))) {
                code.Op(0x1a); // An empty alternative has no bytes to read behind the tag.
                LocationAddress({ arm.binder->type, slot }); code.I32Const(0); code.I32Const(1); code.Fill();
            } else Write(slot);
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
    if (lane_mods && n && n->nkind == NK_Binary &&
        find(lane_mods->begin(), lane_mods->end(), static_cast<Binary *>(n)) != lane_mods->end()) {
        Const(n->exprtype, lane_value); return;
    }
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
            auto x = static_cast<StrLit *>(n);
            if (n->exprtype->kind == TY_SLICE) {
                auto off = c.Text(x->val);
                code.I64Const(int64_t((uint64_t(x->val.size()) << 32) | off));
            }
            else if (n->exprtype->kind == TY_ARRAY) {
                auto dest = FreshDestination(n->exprtype, ConstructionDestination::Statement).location;
                StringInto(x, dest);
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
            if (b->op == T_MOD && PowerOfTwoRemainder(b->right, t)) {
                Convert(t, n->exprtype, n->line); return;
            }
            if (b->op == T_MOD && DynamicRemainder(b->right, t, n->line, b->nonneg)) {
                Convert(t, n->exprtype, n->line); return;
            }
            if (b->op == T_SHL || b->op == T_SHR) { Expr(b->right); Convert(b->right->exprtype, t, n->line); }
            else To(b->right, t);
            BinaryOp(b->op, t, n->line, b->nonneg);
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
                    ReadArrayCapacity(Save(I32)); code.Op(0xad);
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
                    LocationAddress(place); code.I32Const(d->einst->en->VariantIndex(d->variantconst)); WriteEnumTag(c.EnumTagBytes(d->einst));
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
            if (auto cached = CachedLane(n)) { Read(*cached); Convert(cached->type, n->exprtype, n->line); return; }
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
            auto i = static_cast<IfExpr *>(n);
            auto integer = n->exprtype;
            auto literal = [&](Node *arm) -> IntLit * {
                if (auto block = Is<Block>(arm)) {
                    if (!block->stmts.empty()) return nullptr;
                    arm = block->tail;
                }
                auto value = Is<IntLit>(arm);
                if (!value || value->exprtype != integer) return nullptr;
                return value;
            };
            if (IsIntT(integer) && !integer->ix && !Compiler::Varint(integer)) {
                auto yes = literal(i->thenb), no = literal(i->elseb);
                if (yes && no) {
                    Const(integer, yes->val); Const(integer, no->val);
                    Truth(i->cond); code.Op(0x1b); Normalize(integer); return;
                }
            }
            if (SelectAssignment(i)) return;
            auto ts = Values(n); vector<uint32_t> vs;
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
            auto w = static_cast<While *>(n);
            if (BoundedMerge(w)) return;
            auto unroll = UnrollWhile(w);
            auto descending = [&]() -> Binary * {
                if (!unroll) return nullptr;
                auto both = Is<Binary>(w->cond);
                if (!both || both->op != T_ANDAND) return nullptr;
                auto guard = Is<Binary>(both->left), compare = Is<Binary>(both->right);
                auto assignment = static_cast<Assign *>(w->body->stmts[0]);
                auto decrement = static_cast<IncDec *>(w->body->stmts[1]);
                auto counter = Is<Ident>(decrement->lval);
                if (!guard || guard->op != T_GT || !compare || compare->op != T_GT ||
                    decrement->op != T_DEC || !counter || !IsIntT(counter->exprtype) ||
                    counter->exprtype->intstorage != IS_I64) return nullptr;
                auto slot = Lookup(counter->vdef, counter->line);
                if (!IsIntT(slot.type) || slot.type->intstorage != IS_I64) return nullptr;
                auto literal = [](Node *value, int64_t expected) {
                    auto number = Is<IntLit>(value);
                    return number && IsIntT(value->exprtype) && number->val == expected;
                };
                auto same = [&](Node *left, Node *right) {
                    auto a = Is<Ident>(left), b = Is<Ident>(right);
                    return a && b && a->vdef && b->vdef && Resolve(a->vdef) == Resolve(b->vdef);
                };
                auto index_counter = [&](Node *value) {
                    return same(value, counter) && IsIntT(value->exprtype) && value->exprtype->intstorage == IS_I64;
                };
                auto target = static_cast<Index *>(assignment->lval), source = static_cast<Index *>(assignment->rhs);
                auto read = Is<Index>(compare->left);
                auto previous = [&](Index *index) {
                    if (!index) return false;
                    auto subtract = Is<Binary>(index->idx);
                    return subtract && subtract->op == T_MINUS && index_counter(subtract->left) && literal(subtract->right, 1);
                };
                if (!index_counter(guard->left) || !literal(guard->right, 0) || !index_counter(target->idx) ||
                    !previous(source) || !previous(read) || !same(target->obj, source->obj) || !same(source->obj, read->obj)) return nullptr;
                if (!Is<Ident>(compare->right) && !Is<IntLit>(compare->right)) return nullptr;
                return both;
            }();
            if (descending) {
                auto vectors = [&]() -> optional<pair<Slot, Slot>> {
                    if (c.region_cursors && c.may_have_prefix_mappings) return {};
                    auto assignment = static_cast<Assign *>(w->body->stmts[0]);
                    auto target = static_cast<Index *>(assignment->lval), source = static_cast<Index *>(assignment->rhs);
                    auto compare = static_cast<Binary *>(descending->right);
                    auto read = static_cast<Index *>(compare->left);
                    auto object = static_cast<Ident *>(source->obj), key = Is<Ident>(compare->right);
                    auto counter = static_cast<Ident *>(static_cast<IncDec *>(w->body->stmts[1])->lval);
                    auto private_id = [&](Ident *id) {
                        if (!id || !id->vdef) return false;
                        auto variable = Resolve(id->vdef);
                        return !variable->captured && !variable->reusable && !addressed.count(variable) && !addressed.count(id->vdef);
                    };
                    if (!private_id(object) || !private_id(key) || !private_id(counter)) return {};
                    auto view = Lookup(object->vdef, object->line), value = Lookup(key->vdef, key->line);
                    auto position = Lookup(counter->vdef, counter->line);
                    if (view.kind != Slot::LOCAL || view.type->kind != TY_SLICE || value.kind != Slot::LOCAL || position.kind != Slot::LOCAL) return {};
                    auto elem = view.type->sub;
                    if (!IsIntT(elem) || elem->ix || (elem->intstorage != IS_I32 && elem->intstorage != IS_U32) ||
                        target->exprtype != elem || source->exprtype != elem || read->exprtype != elem ||
                        key->exprtype != elem || value.type != elem) return {};
                    for (auto index : { target, source, read })
                        if (index->obj->exprtype->kind != TY_SLICE || index->obj->exprtype->sub != elem) return {};
                    auto i64 = [](TypeExpr *type) { return IsIntT(type) && !type->ix && type->intstorage == IS_I64; };
                    auto guard = static_cast<Binary *>(descending->left);
                    if (!i64(position.type) || !i64(counter->exprtype) || !i64(target->idx->exprtype) ||
                        !i64(guard->left->exprtype) || !i64(guard->right->exprtype)) return {};
                    for (auto index : { source, read }) {
                        auto subtract = static_cast<Binary *>(index->idx);
                        if (!i64(subtract->exprtype) || !i64(subtract->left->exprtype) || !i64(subtract->right->exprtype)) return {};
                    }
                    return pair { view, value };
                }();
                auto emit_vectors = [&]() {
                    if (!vectors) return;
                    constexpr int lanes = 8;
                    auto counter = static_cast<IncDec *>(w->body->stmts[1])->lval;
                    Expr(counter); code.I64Const(lanes); code.Op(0x59);
                    Expr(counter); Read(vectors->first); code.I64Const(32); code.Op(0x88); code.Op(0x54); code.Op(0x71); Begin(0x04);
                    // The logical proof bounds j before widening the complete
                    // initial span. Later chunks only move towards its base.
                    Read(vectors->first); code.Op(0xa7); code.Op(0xad); auto base = Save(I64);
                    Get(base); Expr(counter); code.I64Const(1); code.Op(0x7c); code.I64Const(4); code.Op(0x7e); code.Op(0x7c);
                    code.OpU(0x3f, 0); code.Op(0xad); code.I64Const(16); code.Op(0x86); code.Op(0x58); Begin(0x04);
                    Read(vectors->second); code.OpU(0xfd, 0x11); auto key = Save(V128);
                    auto stop = Begin(), repeat = Begin(0x03);
                    Expr(counter); code.I64Const(lanes); code.Op(0x53); Br(stop, true);
                    Get(base); Expr(counter); code.I64Const(lanes); code.Op(0x7d); code.I64Const(4); code.Op(0x7e); code.Op(0x7c); code.Op(0xa7);
                    auto chunk = Save(I32);
                    uint32_t values[lanes / 4];
                    for (int group = 0; group < lanes / 4; group++) {
                        Get(chunk); code.OpU(0xfd, 0x00); code.U(0); code.U(group * 16); values[group] = Save(V128);
                    }
                    for (int group = 0; group < lanes / 4; group++) {
                        Get(values[group]); Get(key);
                        if (vectors->second.type->intstorage == IS_I32) code.OpU(0xfd, 0x3b);
                        else code.OpU(0xfd, 0x3c);
                        if (group) code.OpU(0xfd, 0x4e);
                    }
                    code.OpU(0xfd, 0xa3); code.Op(0x45); Br(stop, true);
                    // Every lane will shift. The guarded source/destination span
                    // makes this overlapping store nontrapping and ordered-equivalent.
                    for (int group = lanes / 4 - 1; group >= 0; group--) {
                        Get(chunk); code.I32Const(4); code.Op(0x6a); Get(values[group]); code.OpU(0xfd, 0x0b); code.U(0); code.U(group * 16);
                    }
                    Expr(counter); code.I64Const(lanes); code.Op(0x7d); Write(Lookup(static_cast<Ident *>(counter)->vdef, counter->line)); Br(repeat);
                    End(); End(); End(); End();
                };
                auto done = Begin(), tail = Begin(), again = Begin(0x03);
                PushExit({ done, nullptr, {}, {}, true, again });
                auto counter = static_cast<IncDec *>(w->body->stmts[1])->lval;
                Expr(counter); code.I64Const(4); code.Op(0x53); Br(tail, true);
                auto label_depth = labels.size(), exit_depth = exits.size(), cleanup_depth = cleanups.size();
                auto private_depth = private_headers.size(), temp_depth = temp_scopes.size();
                auto live = region_live;
                auto iteration_start = code.data.size();
                Truth(descending->right); code.Op(0x45); Br(done, true);
                BlockInto(w->body, {}, {});
                if (labels.size() != label_depth || exits.size() != exit_depth || cleanups.size() != cleanup_depth ||
                    private_headers.size() != private_depth || temp_scopes.size() != temp_depth || region_live != live)
                    Fail(w->line, "internal: descending while iteration changed control or cleanup state");
                // The group guard proves j > 0 four times. Keep every read,
                // comparison, checked store and decrement in source order.
                auto iteration = code.data.substr(iteration_start);
                for (int copy = 1; copy < 4; copy++) code.Raw(iteration);
                emit_vectors();
                if (labels.size() != label_depth || exits.size() != exit_depth || cleanups.size() != cleanup_depth ||
                    private_headers.size() != private_depth || temp_scopes.size() != temp_depth || region_live != live)
                    Fail(w->line, "internal: descending SIMD changed control or cleanup state");
                exits.pop_back(); Br(again); End(); End();
                again = Begin(0x03); PushExit({ done, nullptr, {}, {}, true, again });
                Truth(descending->left); code.Op(0x45); Br(done, true);
                Truth(descending->right); code.Op(0x45); Br(done, true);
                BlockInto(w->body, {}, {});
                exits.pop_back(); Br(again); End(); End(); return;
            }
            auto done = Begin(), again = Begin(0x03);
            PushExit({ done, nullptr, {}, {}, true, again });
            auto label_depth = labels.size(), exit_depth = exits.size(), cleanup_depth = cleanups.size();
            auto private_depth = private_headers.size(), temp_depth = temp_scopes.size();
            auto live = region_live;
            auto iteration_start = code.data.size();
            if (unroll) {
                // Eligible conditions have no materialized temporaries. Branch
                // on each short-circuit guard instead of merging a bool value.
                function<void(Node *)> stop = [&](Node *condition) {
                    if (auto both = Is<Binary>(condition); both && both->op == T_ANDAND) {
                        stop(both->left); stop(both->right); return;
                    }
                    Truth(condition); code.Op(0x45); Br(done, true);
                };
                stop(w->cond);
            } else {
                auto scope = BeginTempScope(w->cond); Truth(w->cond); auto condition = Save(I32); EndTempScope(scope);
                Get(condition); code.Op(0x45); Br(done, true);
            }
            BlockInto(w->body, {}, {});
            if (unroll) {
                if (labels.size() != label_depth || exits.size() != exit_depth || cleanups.size() != cleanup_depth ||
                    private_headers.size() != private_depth || temp_scopes.size() != temp_depth || region_live != live)
                    Fail(w->line, "internal: unrolled while iteration changed control or cleanup state");
                // Balanced copies share the original locals and outer branch depths.
                auto iteration = code.data.substr(iteration_start);
                for (int copy = 1; copy < 4; copy++) code.Raw(iteration);
            }
            exits.pop_back();
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
            NonlocalReturn(r); return;
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
