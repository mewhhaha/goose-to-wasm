#pragma once
namespace goose::direct_wasm {

inline Location Function::PinPlace(Node *node, bool pointee) {
    optional<Location> place;
    if (auto id = Is<Ident>(node)) {
        auto slot = Lookup(id->vdef, node->line);
        place = Location { slot.type, slot };
    }
    if (!place) {
        auto type = node->exprtype;
        if (auto dot = Is<Dot>(node); dot && dot->IsField()) {
            auto object = dot->obj->exprtype;
            if (!object) Fail(node->line, "field owner type was not resolved");
            if (object->kind == TY_REF) object = object->ref->sub;
            type = c.FieldType(object, dot->fieldidx);
        } else if (auto index = Is<Index>(node)) {
            auto object = index->obj->exprtype;
            if (!object) Fail(node->line, "index owner type was not resolved");
            if (object->kind == TY_REF) object = object->ref->sub;
            type = object->kind == TY_ARRAY ? object->arr->sub : object->sub;
        } else if (type && type->kind == TY_REF) {
            Expr(node); return { type->ref->sub, AddressLocal { Save(I32) } };
        }
        if (!type) Fail(node->line, "location storage type was not resolved");
        Address(node); place = Location { type, AddressLocal { Save(I32) } };
    }
    if (pointee && place->storage_type->kind == TY_REF) {
        ReferenceValue(*place);
        return { place->storage_type->ref->sub, AddressLocal { Save(I32) } };
    }
    return *place;
}

inline void Function::LocationAddress(const Location &place) {
    if (auto slot = get_if<Slot>(&place.storage)) SlotAddress(*slot);
    else Get(get<AddressLocal>(place.storage).index);
}

inline Location Function::OffsetLocation(const Location &place, uint32_t offset, TypeExpr *type) {
    if (auto slot = get_if<Slot>(&place.storage);
        slot && (slot->kind == Slot::FRAME || slot->kind == Slot::GLOBAL))
        return { type, Slot { slot->kind, slot->index + offset, type } };
    LocationAddress(place);
    if (offset) { code.I32Const(int32_t(offset)); code.Op(0x6a); }
    return { type, AddressLocal { Save(I32) } };
}

inline void Function::ReadLocation(const Location &place, TypeExpr *wanted) {
    if (auto slot = get_if<Slot>(&place.storage)) Read(*slot);
    else { LocationAddress(place); Load(place.storage_type); }
    Convert(place.storage_type, wanted, wanted->line);
}

inline void Function::ReferenceValue(const Location &place) {
    if (place.storage_type->kind == TY_REF) ReadLocation(place, place.storage_type);
    else LocationAddress(place);
}

inline CapturedValue Function::CaptureStack(TypeExpr *type) {
    c.FixedLayout(type);
    return { type, Save(type), c.Aggregate(type) ? CapturedValue::BorrowedFixed : CapturedValue::Immediate };
}

inline CapturedValue Function::CaptureBorrowed(Node *node, TypeExpr *wanted) {
    To(node, wanted); return CaptureStack(wanted);
}

inline ConstructionDestination Function::FreshDestination(TypeExpr *type, ConstructionDestination::Lifetime lifetime) {
    c.FixedLayout(type);
    if (lifetime == ConstructionDestination::Caller || lifetime == ConstructionDestination::Static ||
        lifetime == ConstructionDestination::Existing)
        Fail(type->line, "a fresh activation destination cannot have caller or static lifetime");
    return { { type, Slot { Slot::FRAME, Frame(type), type } }, lifetime };
}

inline void Function::ConstructInto(Node *node, const ConstructionDestination &destination) {
    // Evaluate the whole value before writing. This is also safe for a
    // pinned assignment target when the RHS reads it or retargets an alias.
    StoreCopy(destination.location, CaptureBorrowed(node, destination.location.storage_type));
}

inline CapturedValue Function::CopyCaptured(CapturedValue value) {
    if (!c.Aggregate(value.type)) return value;
    auto destination = FreshDestination(value.type, ConstructionDestination::Activation);
    StoreCopy(destination.location, value);
    LocationAddress(destination.location);
    return { value.type, Save(value.type), CapturedValue::CopiedFixed };
}

inline void Function::StoreCopy(const Location &place, CapturedValue value) {
    c.FixedLayout(place.storage_type);
    Get(value.value_local); Convert(value.type, place.storage_type, place.storage_type->line);
    if (auto slot = get_if<Slot>(&place.storage)) Write(*slot);
    else {
        auto converted = Save(place.storage_type);
        LocationAddress(place); Get(converted); Store(place.storage_type);
    }
}

} // namespace goose::direct_wasm
