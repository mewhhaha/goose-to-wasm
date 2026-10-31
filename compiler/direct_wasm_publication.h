#pragma once
namespace goose::direct_wasm {

// Bit zero follows the receiving channel: frame tails publish their data
// pointer as well as length; ordinary growable arrays publish length only.
inline uint32_t Function::Publication(const ConstructionDestination &destination) {
    auto type = destination.location.storage_type;
    if (destination.publication) {
        if (!Compiler::RegionArray(type)) return *destination.publication;
        // An array producer receives a length channel, even when its caller
        // embeds that channel in a frame whose constructor owns the base.
        Get(*destination.publication); code.I32Const(-2); code.Op(0x71); return Save(I32);
    }
    if (Compiler::GrowableArray(type) || Compiler::FrameStruct(type)) {
        LocationAddress(destination.location);
        if (Compiler::FrameStruct(type)) { code.I32Const(1); code.Op(0x72); }
    } else code.I32Const(0);
    return Save(I32);
}

inline optional<uint32_t> Function::TailPublication(const ConstructionDestination &destination) {
    return OffsetPublication(destination, c.ControlLayout(destination.location.storage_type).payload);
}

inline optional<uint32_t> Function::OffsetPublication(const ConstructionDestination &destination, uint32_t offset) {
    if (!c.owned_effects) return {};
    auto publication = Publication(destination);
    Get(publication); Begin(0x04, I32);
    Get(publication); code.I32Const(int32_t(offset)); code.Op(0x6a);
    Else(); code.I32Const(0); End(); return Save(I32);
}

inline void Function::CanonicalAddress(uint32_t bytes) {
    if (!c.owned_effects || !bytes) return;
    code.I32Const(int32_t(bytes)); CallIndex(c.prefix_helper);
}

inline void Function::PublishHeader(uint32_t header, uint32_t word) {
    if (!c.owned_effects) return;
    Get(header); code.I32Const(int32_t(word)); CallIndex(c.header_helper);
}

// Both helpers use only Wasm locals, so resolving a binding never allocates
// an activation or changes the active owner chain. Mappings expire on every
// construction exit independently of the dying-owner evidence used to unwind.
inline string Function::PublicationHelper(bool header) {
    auto frame = Local(I32), entry = Local(I32), source = Local(I32), target = Local(I32);
    auto finished = Begin(); auto restart = Begin(0x03);
    code.OpU(0x23, c.effect_frames); Set(frame);
    auto frames = Begin(0x03);
    Get(frame); code.Op(0x45); Br(finished, true);
    Get(frame); code.Mem(0x28, 2, 8); Set(entry);
    auto entries_done = Begin(); auto entries = Begin(0x03);
    Get(entry); code.Op(0x45); Br(entries_done, true);
    Get(entry); code.Mem(0x28, 2, 36); Begin(0x04);
    Get(entry); code.Mem(0x28, 2, 16); Set(source);
    Get(entry); code.Mem(0x28, 2, 20); Set(target);
    if (header) {
        Get(source); Get(entry); code.Mem(0x28, 2, 28); code.Op(0x6a); Set(source);
        Get(0); Get(source); code.Op(0x46);
        Get(1); code.I32Const(4); code.Op(0x46);
        Get(entry); code.Mem(0x28, 2, 32); code.Op(0x72); code.Op(0x71); Begin(0x04);
        Get(target); Get(entry); code.Mem(0x28, 2, 28); code.Op(0x6a); Set(target);
        Get(target); Get(1); code.Op(0x6a);
        Get(source); Get(1); code.Op(0x6a); code.Mem(0x28, 2); code.Mem(0x36, 2);
        Get(target); Set(0); Br(restart); End();
    } else {
        Get(0); Get(source); code.Op(0x4f);
        Get(0); code.Op(0xad); Get(1); code.Op(0xad); code.Op(0x7c);
        Get(source); code.Op(0xad); Get(entry); code.Mem(0x28, 2, 24); code.Op(0xad); code.Op(0x7c);
        code.Op(0x58); code.Op(0x71); Begin(0x04);
        Get(target); Get(0); Get(source); code.Op(0x6b); code.Op(0x6a); Set(0);
        Br(restart); End();
    }
    End();
    Get(entry); code.Mem(0x28, 2); Set(entry); Br(entries); End(); End();
    Get(frame); code.Mem(0x28, 2); Set(frame); Br(frames); End(); End(); End();
    if (!header) Get(0);
    code.Op(0x0b); return EncodeBody();
}

} // namespace goose::direct_wasm
