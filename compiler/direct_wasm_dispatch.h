#pragma once
namespace goose::direct_wasm {

inline void Function::EmitDispatch(Call *node, bool adapt_result, const ResultDestinations &destinations) {
    auto args = node->ValueArgNodes();
    auto first = node->dispatch.front();
    auto position = node->dispatcharg;
    if (position < 0 || size_t(position) >= args.size()) Fail(node->line, "invalid dispatch argument position");
    auto enum_type = args[size_t(position)]->exprtype;
    if (enum_type->kind == TY_REF) enum_type = enum_type->ref->sub;
    if (enum_type->kind != TY_ENUM || !enum_type->enu->inst ||
        node->dispatch.size() != enum_type->enu->inst->vftypes.size())
        Fail(node->line, "dispatch requires one checked arm per enum variant");
    auto ei = enum_type->enu->inst;
    auto variable = Compiler::RegionEnum(enum_type);
    auto layout = variable ? c.EnumImageLayout(ei, node->line) : c.FixedLayout(enum_type);
    auto parameters = [](FnSpec *spec) {
        vector<VarDef *> out;
        for (auto p : spec->params) if (p->type->kind != TY_FN) out.push_back(p);
        return out;
    };
    auto shared_types = parameters(first);
    if (shared_types.size() != args.size()) Fail(node->line, "dispatch parameter arity mismatch");
    bool whole_copy = false, owned_arguments = false;
    for (size_t vi = 0; vi < node->dispatch.size(); vi++) {
        auto arm = node->dispatch[vi]; auto params = parameters(arm);
        if (params.size() != args.size() || arm->rets.size() != first->rets.size())
            Fail(node->line, "dispatch arm signature mismatch");
        for (size_t i = 0; i < args.size(); i++) if (i != size_t(position)) {
            if (!SameFunctionValueType(params[i]->type, shared_types[i]->type))
                Fail(node->line, "dispatch arms disagree on a shared parameter");
            owned_arguments |= Compiler::RegionOwner(params[i]->type);
        }
        for (size_t i = 0; i < first->rets.size(); i++)
            if (!SameFunctionValueType(first->rets[i], arm->rets[i]))
                Fail(node->line, "dispatch arms disagree on a result type");
        auto payload = params[size_t(position)]->type;
        if (payload->kind == TY_REF) payload = payload->ref->sub;
        if (payload->kind != TY_VARIANT || payload->var->adt->enu->inst != ei ||
            ei->en->VariantIndex(payload->var->variant) != int(vi))
            Fail(node->line, "dispatch arm does not match its checked variant");
        if (!variable && params[size_t(position)]->type->kind == TY_REF)
            Fail(node->line, "fixed-mode dispatch payloads must pass by value");
        whole_copy |= params[size_t(position)]->type->kind != TY_REF && Compiler::RegionOwner(payload);
    }
    auto group = BeginArgumentGroup(owned_arguments || whole_copy);
    vector<uint32_t> shared(args.size()), payloads(node->dispatch.size());
    uint32_t original = 0, copied = 0, tag = 0;
    for (size_t i = 0; i < args.size(); i++) {
        if (i != size_t(position)) {
            auto type = shared_types[i]->type;
            if (Compiler::RegionOwner(type)) {
                auto control = c.ControlLayout(type);
                Location place { type, Slot { Slot::FRAME, FrameBytes(control.size, control.align), type } };
                AcquireRegion(place, args[i]->line);
                ConstructRegionInto(args[i], { place, ConstructionDestination::Statement });
                LocationAddress(place); shared[i] = Save(I32);
            } else {
                To(args[i], type);
                shared[i] = CopyCaptured(CaptureStack(type)).value_local;
            }
            continue;
        }
        To(args[i], enum_type);
        if (!variable) {
            auto value = CopyCaptured(CaptureStack(enum_type));
            original = copied = value.value_local;
            Get(original); code.Mem(0x28, 2); tag = Save(I32);
        } else {
            auto header = Save(I32);
            Get(header); code.Mem(0x28, 2); original = Save(I32);
            if (whole_copy) {
                auto control = c.ControlLayout(enum_type);
                Location place { enum_type, Slot { Slot::FRAME, FrameBytes(control.size, control.align), enum_type } };
                AcquireRegion(place, node->line);
                ConstructEnumFromCaptured(enum_type, header, { place, ConstructionDestination::Statement }, node->line);
                LocationAddress(place); code.Mem(0x28, 2); copied = Save(I32);
            } else {
                // Fixed payload snapshots need no data region, even when a
                // sibling arm takes a reference and enters a recursive cycle.
                for (size_t vi = 0; vi < node->dispatch.size(); vi++) {
                    auto type = parameters(node->dispatch[vi])[size_t(position)]->type;
                    if (type->kind == TY_REF) continue;
                    auto receiver = FreshDestination(type, ConstructionDestination::Activation);
                    LocationAddress(receiver.location); code.I32Const(0);
                    code.I32Const(int32_t(c.FixedLayout(type).size)); code.Fill();
                    Get(original); code.Mem(0x28, 2); code.I32Const(int32_t(vi)); code.Op(0x46); Begin(0x04);
                    auto payload = OffsetLocation({ type, AddressLocal { original } }, layout.payload, type);
                    LocationAddress(payload); StoreCopy(receiver.location, CaptureStack(type)); End();
                    LocationAddress(receiver.location); payloads[vi] = Save(I32);
                }
            }
        }
    }
    if (variable) { Get(original); code.Mem(0x28, 2); tag = Save(I32); }
    auto plan = PlanRegionResults(first->rets, destinations, node->line, false);
    vector<uint32_t> results, fixed_destinations(first->rets.size());
    for (size_t i = 0; i < first->rets.size(); i++) {
        auto type = first->rets[i]; results.push_back(Local(type));
        if (c.Aggregate(type) && !Compiler::RegionOwner(type)) {
            auto receiver = FreshDestination(type, ConstructionDestination::Activation);
            LocationAddress(receiver.location); fixed_destinations[i] = Save(I32);
        }
    }
    auto done = Begin();
    for (size_t vi = 0; vi < node->dispatch.size(); vi++) {
        auto arm = node->dispatch[vi]; auto params = parameters(arm);
        Get(tag); code.I32Const(int32_t(vi)); code.Op(0x46); Begin(0x04);
        for (size_t i = 0; i < args.size(); i++) {
            if (i != size_t(position)) Get(shared[i]);
            else if (params[i]->type->kind != TY_REF && c.RecordFields(params[i]->type).empty()) {
                auto empty = FreshDestination(params[i]->type, ConstructionDestination::Activation);
                LocationAddress(empty.location); code.I32Const(0); code.I32Const(int32_t(c.FixedLayout(params[i]->type).size)); code.Fill();
                LocationAddress(empty.location);
            }
            else if (variable && params[i]->type->kind != TY_REF && !whole_copy) Get(payloads[vi]);
            else {
                Get(params[i]->type->kind == TY_REF ? original : copied);
                code.I32Const(int32_t(layout.payload)); code.Op(0x6a);
            }
        }
        for (auto capture : c.captures[arm]) SlotAddress(Lookup(node->FreeVarArg(capture), node->line));
        for (size_t i = 0; i < first->rets.size(); i++) if (c.Aggregate(first->rets[i])) {
            if (Compiler::RegionOwner(first->rets[i])) LocationAddress(plan.producers[i]->location);
            else Get(fixed_destinations[i]);
        }
        RecordRegionCall(arm, node->line); CallIndex(c.function_index.at(arm));
        for (size_t i = results.size(); i-- > 0;) Set(results[i]);
        Br(done); End();
    }
    Abort(node->line, "invalid enum tag in dispatch"); End();
    EndArgumentGroup(group, anonymous_serial != group.serial);
    for (auto result : results) Get(result);
    PublishRegionResults(first->rets, plan, node->line);
    if (adapt_result && first->rets.size() == 1) {
        if (node->exprtype->kind == TY_VOID) code.Op(0x1a);
        else Convert(plan.enum_payloads[0] ? plan.values[0]->location.storage_type : first->rets[0], node->exprtype, node->line);
    }
}

} // namespace goose::direct_wasm
