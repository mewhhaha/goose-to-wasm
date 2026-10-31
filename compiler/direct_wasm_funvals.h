#pragma once
namespace goose::direct_wasm {

// Equality of the concrete value representation and its length contract.
// Const qualification does not change either; nominal instances are checked.
inline bool SameFunctionValueType(TypeExpr *left, TypeExpr *right) {
    if (left == right) return true;
    if (!left || !right || left->kind != right->kind) return false;
    switch (left->kind) {
        case TY_INT: return left->intstorage == right->intstorage;
        case TY_FLT: return left->fltstorage == right->fltstorage;
        case TY_BOOL: case TY_VOID: return true;
        case TY_STRUCT: case TY_VARIANT: return Compiler::SameRecord(left, right);
        case TY_ENUM: return left->enu->inst == right->enu->inst && left->enu->varmode == right->enu->varmode;
        case TY_ARRAY: {
            auto &a = *left->arr, &b = *right->arr;
            if (a.akind != b.akind || !SameFunctionValueType(a.sub, b.sub)) return false;
            if (a.akind == A_VAR) return Compiler::LengthStorage(left) == Compiler::LengthStorage(right);
            if (a.akind == A_FIXED || a.akind == A_LIMITED) return a.size == b.size;
            return true;
        }
        case TY_SLICE: return SameFunctionValueType(left->sub, right->sub);
        case TY_REF: return left->ref->optional == right->ref->optional &&
            left->ref->lenstorage == right->ref->lenstorage && left->ref->pool == right->ref->pool &&
            SameFunctionValueType(left->ref->sub, right->ref->sub);
        default: return false;
    }
}

inline void Function::EmitFunctionValue(Call *node, bool adapt_result, const ResultDestinations &destinations, bool elements) {
    auto args = node->ValueArgNodes();
    if (args.size() != node->fvparams.size()) Fail(node->line, "function-value parameter mismatch");
    auto natural = NaturalResults(node);
    auto owns_parameters = false;
    for (auto parameter : node->fvparams) {
        if (c.Class(parameter->type) != SC_FIXED && !Compiler::RegionOwner(parameter->type))
            Fail(node->line, "unsupported owned function-value parameter layout");
        owns_parameters |= Compiler::RegionOwner(parameter->type);
    }
    for (auto result : natural) if (c.Class(result) != SC_FIXED && !Compiler::RegionOwner(result))
        Fail(node->line, "unsupported owned function-value result layout");

    // The pinned checker does not apply ordinary return-root checks to FV
    // tails. Its C emitter can release callback-owned storage before a later
    // argument uses a borrowed result. Refuse this slice until root proofs can
    // distinguish external holders from callback-owned storage.
    unordered_set<TypeExpr *> visited;
    function<bool(TypeExpr *)> holds = [&](TypeExpr *type) {
        if (!type) return false;
        if (!visited.insert(type).second) return false;
        if (IsRefOrSlice(type)) return true;
        if (type->kind == TY_ARRAY) return holds(type->arr->sub);
        if (type->kind == TY_STRUCT || type->kind == TY_VARIANT) {
            for (auto field : c.RecordFields(type)) if (holds(field)) return true;
        } else if (type->kind == TY_ENUM) {
            for (auto &fields : type->enu->inst->vftypes)
                for (auto field : fields) if (holds(field)) return true;
        }
        return false;
    };
    bool borrowed = false;
    for (auto result : natural) borrowed |= holds(result);
    if (borrowed) {
        vector<VarDef *> locals = node->fvparams;
        function<void(Node *)> collect = [&](Node *part) {
            if (!part || Is<FnDecl>(part) || Is<FunVal>(part) || Is<StructDecl>(part) ||
                Is<EnumDecl>(part) || Is<AliasDecl>(part)) return;
            if (auto declaration = Is<VarDecl>(part))
                locals.insert(locals.end(), declaration->defs.begin(), declaration->defs.end());
            if (auto loop = Is<ForLoop>(part)) {
                locals.push_back(loop->vdef);
                if (loop->idxdef) locals.push_back(loop->idxdef);
            }
            if (auto match = Is<MatchExpr>(part))
                for (auto &arm : match->arms) if (arm.binder) locals.push_back(arm.binder);
            if (auto call = Is<Call>(part); call && call->fvbody)
                locals.insert(locals.end(), call->fvparams.begin(), call->fvparams.end());
            RunChildren(part, [&](Node *child) { collect(child); });
        };
        collect(node->fvbody);
        for (auto local : locals) if (goose::MayReachLocal(node->fvbody->tail, local))
            Fail(node->line, "function-value result may borrow callback-local storage; a root proof is required");
    }

    // A callback produces a copy with its natural length contract. An exact
    // element-run request is forwarded as in the native append convention;
    // adaptation to another kind or length storage first builds a value.
    // Its receiving storage precedes argument evaluation, as in EmitFvCall.
    // Exact receivers avoid an unnecessary live region across recursive calls.
    RegionResultPlan plan { ResultDestinations(natural.size()), ResultDestinations(natural.size()),
                            ResultDestinations(natural.size()), vector<TypeExpr *>(natural.size(), nullptr) };
    if (!destinations.empty() && destinations.size() != natural.size())
        Fail(node->line, "function-value result channel arity mismatch");
    for (size_t i = 0; i < natural.size(); i++) if (Compiler::RegionOwner(natural[i])) {
        auto receiver = destinations.empty() ? optional<ConstructionDestination> {} : destinations[i];
        if (receiver) CheckRegionDestination(natural[i], *receiver, node->line);
        auto want = receiver ? receiver->location.storage_type : node->exprtype;
        auto run = Compiler::RegionArray(natural[i]) && !Compiler::RuntimeLimited(natural[i]) &&
                   SameFunctionValueType(natural[i], want) && (elements || (receiver && receiver->elements));
        if (receiver && SameFunctionValueType(natural[i], receiver->location.storage_type)) {
            plan.producers[i] = receiver; plan.producers[i]->elements = run; plan.values[i] = receiver;
        } else {
            plan.producers[i] = TemporaryDestination(natural[i], node->line);
            plan.producers[i]->elements = run;
            plan.values[i] = receiver ? receiver : plan.producers[i];
            if (receiver) plan.copies[i] = receiver;
        }
    }
    bool group_needed = owns_parameters;
    for (auto arg : args) group_needed |= MayMaterialize(arg);
    auto private_depth = private_headers.size();
    auto group = BeginArgumentGroup(group_needed);
    auto parameter_depth = cleanups.size() + 1;
    for (size_t i = 0; i < args.size(); i++) {
        auto slot = Bind(node->fvparams[i]);
        if (Compiler::RegionOwner(slot.type)) {
            Location place { slot.type, slot };
            AcquireRegion(place, args[i]->line);
            private_headers.push_back({ TailHeaderLocation(place), parameter_depth });
            ConstructRegionInto(args[i], { place, ConstructionDestination::Block });
        } else {
            To(args[i], slot.type);
            StoreCopy({ slot.type, slot }, CaptureStack(slot.type));
        }
    }
    unordered_map<VarDef *, VarDef *> remap;
    for (auto [from, to] : node->fvremap) remap[from] = to;
    aliases.push_back(std::move(remap));
    vector<uint32_t> values; for (auto type : natural) values.push_back(Local(type));
    auto retain_arguments = anonymous_serial != group.serial;
    // Do not bind named results: a callback's value is a copy of its tail.
    BlockInto(node->fvbody, natural, values, plan.producers);
    aliases.pop_back();
    EndArgumentGroup(group, retain_arguments);
    auto retained = private_depth;
    for (size_t i = private_depth; i < private_headers.size(); i++)
        if (private_headers[i].temporary) private_headers[retained++] = private_headers[i];
    private_headers.resize(retained);
    for (auto value : values) Get(value);
    PublishRegionResults(natural, plan, node->line);
    if (adapt_result && natural.size() == 1) {
        auto delivered = plan.values[0] ? plan.values[0]->location.storage_type : natural[0];
        if (node->exprtype->kind == TY_VOID) code.Op(0x1a);
        else if (Compiler::RegionOwner(node->exprtype) && !SameFunctionValueType(delivered, node->exprtype)) {
            auto source = Save(delivered);
            auto receiver = TemporaryDestination(node->exprtype, node->line);
            ConstructRegionFromCaptured(delivered, source, receiver, node->line);
            LocationAddress(receiver.location);
        } else Convert(delivered, node->exprtype, node->line);
    }
}

} // namespace goose::direct_wasm
