// Direct Goose -> WebAssembly backend. Input is the upstream checker's
// specialized AST, after the ordinary Goose optimizer and bounds analysis.
// Include this header after the upstream frontend headers.
#pragma once
#include "wasm_binary.h"
#include <variant>

namespace goose {

struct DirectWasmOptions {
    bool debug = false;
    uint32_t initial_pages = 16;
    uint32_t maximum_pages = 256;
};

struct DirectWasmFunctionInfo {
    string name;
    uint32_t index = 0;
    size_t code_bytes = 0;
    uint64_t body_hash = 0;
    vector<uint32_t> dependencies;
};

struct DirectWasmResult {
    string module;
    size_t functions = 0;
    size_t code_bytes = 0;
    uint32_t region_count = 0, region_bytes = 0, activation_bytes = 0;
    vector<DirectWasmFunctionInfo> function_info;
};

namespace direct_wasm {

struct Signature {
    vector<uint8_t> args, results;
    bool operator==(const Signature &) const = default;
};
struct Import { string module, name; uint32_t type; };
struct Layout { uint32_t size = 0, align = 1; vector<uint32_t> fields; uint32_t payload = 0; };
enum RuntimeGlobal { G_SCRATCH_TOP, G_REGION_NEXT, G_REGION_BASE, G_REGION_BYTES, G_REGION_COUNT, G_ACTIVATION_LIMIT };
struct Slot {
    enum Kind { LOCAL, FRAME, GLOBAL, ADDRESS } kind = LOCAL;
    uint32_t index = 0;
    TypeExpr *type = nullptr;
};
struct AddressLocal { uint32_t index; };
struct Location {
    TypeExpr *storage_type;
    variant<Slot, AddressLocal> storage;
};
struct CapturedValue {
    TypeExpr *type;
    uint32_t value_local;
    enum Form { Immediate, BorrowedFixed, CopiedFixed } form;
};
struct ConstructionDestination {
    Location location;
    enum Lifetime { Statement, Block, Activation, Caller, Static, Existing } lifetime;
    bool elements = false; // raw element run, without a value's length prefix contract
    struct EnumGuard { uint32_t image_base, owner_header; int32_t tag; };
    optional<EnumGuard> enum_guard;
};
using ResultDestinations = vector<optional<ConstructionDestination>>;
struct Compiler;

struct Function {
    Compiler &c;
    FnSpec *spec;
    uint32_t index, sig;
    bool element_run = false;
    vector<uint8_t> params, locals;
    vector<TypeExpr *> results;
    vector<uint32_t> resultlocals;
    // Each owned result receives storage in the caller's activation. The
    // ordinary Wasm result remains its address, so expression lowering uses
    // the same representation as an aggregate local or literal.
    vector<optional<uint32_t>> resultdestinations;
    unordered_map<VarDef *, Slot> vars;
    unordered_map<const VarDef *, ConstructionDestination> named_regions;
    unordered_set<VarDef *> addressed;
    vector<unordered_map<VarDef *, VarDef *>> aliases;
    uint32_t framebase = 0, framebytes = 0;
    uint32_t region_live = 0, region_peak = 0;
    Bytes code;
    vector<uint32_t> labels;
    uint32_t labelserial = 0;
    struct Exit {
        uint32_t label;
        SFunction *sf = nullptr;
        vector<TypeExpr *> types;
        vector<uint32_t> values;
        bool breakable = false;
        optional<uint32_t> continue_label;
        size_t cleanup_depth = 0;
        ResultDestinations destinations;
    };
    vector<Exit> exits;
    struct PrivateHeader { Location location; size_t cleanup_depth; bool temporary = false; };
    vector<PrivateHeader> private_headers;
    struct TempScope {
        size_t cleanup_depth, private_depth;
        uint32_t region_live;
        bool restores_regions;
    };
    vector<TempScope> temp_scopes;
    uint64_t anonymous_serial = 0;
    struct ArgumentGroup {
        size_t cleanup_depth;
        uint32_t region_live;
        uint64_t serial;
        bool active;
    };
    bool MayMaterialize(Node *);
    TempScope BeginTempScope(Node *, bool force = false);
    void EndTempScope(const TempScope &);
    ArgumentGroup BeginArgumentGroup(bool);
    void EndArgumentGroup(const ArgumentGroup &, bool);
    ConstructionDestination TemporaryDestination(TypeExpr *, Line);
    void Materialize(Node *, TypeExpr *, bool adapt_result = true);
    struct CleanupAction {
        enum Kind { RestoreScratchTop, RestoreRegionNext, CheckAbandonedRegion } kind;
        uint32_t saved_local;
        TypeExpr *element = nullptr;
        Line line {};
        optional<ConstructionDestination::EnumGuard> enum_guard;
    };
    vector<CleanupAction> cleanups;
    void PushExit(Exit target, const ResultDestinations &destinations = {}) {
        target.destinations = destinations;
        target.cleanup_depth = cleanups.size(); exits.push_back(std::move(target));
    }
    void EmitCleanups(size_t depth, bool abandoning = false) {
        for (auto i = cleanups.size(); i-- > depth;) {
            auto &action = cleanups[i];
            if (action.kind == CleanupAction::RestoreScratchTop) { Get(action.saved_local); code.OpU(0x24, 0); }
            else if (action.kind == CleanupAction::RestoreRegionNext) { Get(action.saved_local); code.OpU(0x24, G_REGION_NEXT); }
            else if (action.kind == CleanupAction::CheckAbandonedRegion && abandoning) {
                auto done = Begin();
                if (action.enum_guard) {
                    Get(action.enum_guard->image_base); code.Mem(0x28, 2);
                    code.I32Const(action.enum_guard->tag); code.Op(0x47); Br(done, true);
                }
                // A private header declared inside the exited scope dies
                // there, even if its data region belongs to a result.
                for (auto &header : private_headers) if (header.cleanup_depth > depth) {
                    Get(action.saved_local); LocationAddress(header.location); code.Op(0x46); Br(done, true);
                    if (action.enum_guard) {
                        Get(action.enum_guard->owner_header); LocationAddress(header.location); code.Op(0x46); Br(done, true);
                    }
                }
                Get(action.saved_local); code.Mem(0x28, 2, 4); code.Op(0xad); auto count = Save(I64);
                ReserveRegion(action.saved_local, count, action.element, action.line);
                End();
            }
        }
    }
    void CloseCleanups(size_t depth) {
        EmitCleanups(depth); cleanups.resize(depth);
    }
    void UnwindCleanups(size_t target) {
        EmitCleanups(exits.at(target).cleanup_depth, true);
    }
    set<uint32_t> dependencies;

    Function(Compiler &, FnSpec *, uint32_t, uint32_t, bool element_run = false);
    [[noreturn]] void Fail(Line, const string &);
    uint8_t W(TypeExpr *);
    uint32_t Local(uint8_t t) { auto i = uint32_t(params.size() + locals.size()); locals.push_back(t); return i; }
    uint32_t Local(TypeExpr *t) { return Local(W(t)); }
    void Get(uint32_t i) { code.OpU(0x20, i); }
    void Set(uint32_t i) { code.OpU(0x21, i); }
    void Tee(uint32_t i) { code.OpU(0x22, i); }
    uint32_t Save(uint8_t t) { auto i = Local(t); Set(i); return i; }
    uint32_t Save(TypeExpr *t) { return Save(W(t)); }
    uint32_t Begin(uint8_t op = 0x02, uint8_t result = VOID) {
        code.Op(op); code.Byte(result); labels.push_back(++labelserial); return labelserial;
    }
    void End() { code.Op(0x0b); labels.pop_back(); }
    void Else() { code.Op(0x05); }
    void Br(uint32_t label, bool conditional = false) {
        for (size_t i = labels.size(); i-- > 0;)
            if (labels[i] == label) { code.OpU(conditional ? 0x0d : 0x0c, uint32_t(labels.size() - 1 - i)); return; }
        Fail({}, "internal branch target escaped its function");
    }
    void CallIndex(uint32_t i) { code.OpU(0x10, i); dependencies.insert(i); }
    void Zero(uint8_t t) {
        if (t == I32) code.I32Const(0); else if (t == I64) code.I64Const(0);
        else if (t == F32) code.F32Const(0); else if (t == F64) code.F64Const(0);
    }
    void Const(TypeExpr *t, int64_t n) {
        if (W(t) == I64) code.I64Const(n); else code.I32Const(int32_t(n));
    }
    void Abort(Line, string_view);
    void TrapIf(Line l, string_view msg) { Begin(0x04); Abort(l, msg); End(); }
    void Normalize(TypeExpr *);
    void Convert(TypeExpr *, TypeExpr *, Line);
    void Cast(AsCast *);
    void FloatWrap(TypeExpr *);
    void FloatRemainder(TypeExpr *);
    void Truth(Node *);
    void BinaryOp(TType, TypeExpr *, Line);
    uint32_t Frame(TypeExpr *);
    uint32_t FrameBytes(uint32_t n, uint32_t align = 8);
    void FrameAddress(uint32_t off) { Get(framebase); if (off) { code.I32Const(int32_t(off)); code.Op(0x6a); } }
    void SlotAddress(const Slot &s) {
        if (s.kind == Slot::FRAME) FrameAddress(s.index);
        else if (s.kind == Slot::GLOBAL) code.I32Const(int32_t(s.index));
        else if (s.kind == Slot::ADDRESS) Get(s.index);
        else Fail(s.type->line, "taking the address of this local is not supported");
    }
    VarDef *Resolve(VarDef *v) {
        for (auto i = aliases.rbegin(); i != aliases.rend(); ++i)
            if (auto f = i->find(v); f != i->end()) v = f->second;
        return v;
    }
    Slot Lookup(VarDef *, Line);
    Slot Bind(VarDef *);
    void Read(const Slot &);
    void Write(const Slot &);
    void Load(TypeExpr *);
    void Store(TypeExpr *);
    Location PinPlace(Node *, bool pointee = false);
    void LocationAddress(const Location &);
    Location OffsetLocation(const Location &, uint32_t, TypeExpr *);
    void ReadLocation(const Location &, TypeExpr *);
    void ReferenceValue(const Location &);
    CapturedValue CaptureStack(TypeExpr *);
    CapturedValue CaptureBorrowed(Node *, TypeExpr *);
    CapturedValue CopyCaptured(CapturedValue);
    void StoreCopy(const Location &, CapturedValue);
    ConstructionDestination FreshDestination(TypeExpr *, ConstructionDestination::Lifetime);
    void ConstructInto(Node *, const ConstructionDestination &);
    void Address(Node *);
    TypeExpr *Object(Node *);
    void PackArrayView(TypeExpr *);
    void View(Node *);
    void ArrayBuiltin(Call *);
    function<void()> SequenceValue(Node *, bool address = false);
    void Expr(Node *);
    void To(Node *, TypeExpr *);
    void Discard(Node *);
    void BlockInto(Block *, const vector<TypeExpr *> &, const vector<uint32_t> &, const ResultDestinations & = {}, size_t first_statement = 0);
    void CaptureResult(TypeExpr *, uint32_t);
    void SetResults(const vector<Node *> &, const vector<TypeExpr *> &, const vector<uint32_t> &, Line, const ResultDestinations & = {});
    vector<TypeExpr *> Values(Node *);
    vector<TypeExpr *> NaturalResults(Node *);
    void EmitCall(Call *, bool adapt_result = true, const ResultDestinations & = {}, bool elements = false);
    void EmitFunctionValue(Call *, bool, const ResultDestinations &, bool elements);
    void EmitDispatch(Call *, bool, const ResultDestinations &);
    void EmitInline(InlineBlock *, bool adapt_result = true, const ResultDestinations & = {}, bool elements = false);
    void ResultExpression(Node *, const ResultDestinations &);
    struct RegionResultPlan { ResultDestinations producers, copies, values; vector<TypeExpr *> enum_payloads; };
    RegionResultPlan PlanRegionResults(const vector<TypeExpr *> &, const ResultDestinations &, Line, bool run = false, bool inlined = false);
    void PublishRegionResults(const vector<TypeExpr *> &, const RegionResultPlan &, Line);
    void ControlValue(Node *, const vector<TypeExpr *> &, const vector<uint32_t> &, const ResultDestinations & = {});
    vector<const VarDef *> BindNamedResults(Block *, SFunction *, const vector<TypeExpr *> &, const ResultDestinations &, bool inlined = false);
    void RecordRegionCall(FnSpec *, Line);
    void ConstructRegion(Node *, const Location &, optional<uint32_t> global_region = {});
    void AcquireRegion(const Location &, Line, optional<uint32_t> = {});
    void ShareRegion(const Location &, const ConstructionDestination &);
    void ConstructRegionInto(Node *, const ConstructionDestination &);
    void ConstructRegionFromCaptured(TypeExpr *, uint32_t, const ConstructionDestination &, Line);
    Location TailHeaderLocation(const Location &);
    void ConstructRecordInto(Node *, const ConstructionDestination &);
    void ConstructRecordFromCaptured(TypeExpr *, uint32_t, const ConstructionDestination &, Line);
    void ConstructEnumInto(Node *, const ConstructionDestination &);
    void ConstructEnumFromCaptured(TypeExpr *, uint32_t, const ConstructionDestination &, Line);
    ConstructionDestination PrepareEnumPayload(const ConstructionDestination &, TypeExpr *, Line);
    void FinishEnumPayload(const ConstructionDestination &, TypeExpr *, Line);
    void ConstructRegionView(uint32_t, const ConstructionDestination &, Line, optional<uint32_t> capacity = {});
    void CheckRegionDestination(TypeExpr *, const ConstructionDestination &, Line);
    void ConstructionView(Node *, bool elements = false);
    struct CapturedSequence { uint32_t view; TypeExpr *type; optional<uint32_t> capacity; };
    CapturedSequence CaptureSequence(Node *, bool elements = false);
    void CheckArrayLength(TypeExpr *, uint32_t count, Line, bool elements = false);
    void ReserveRegion(uint32_t header, uint32_t count, TypeExpr *, Line);
    void ReserveArray(uint32_t header, uint32_t count, TypeExpr *, Line);
    void ActivationLimit(uint32_t, Line);
    void Builtin(Call *, bool adapt_result = true);
    void Print(TypeExpr *, uint32_t, Line, bool nested = false);
    void PrintText(string_view);
    void Decl(VarDecl *);
    struct PreparedDecl { vector<Slot> slots; ResultDestinations destinations; };
    PreparedDecl PrepareDecl(VarDecl *);
    void InitializeDecl(VarDecl *, const PreparedDecl &);
    void AssignNode(Assign *);
    void IncNode(IncDec *);
    void For(ForLoop *);
    void ScanAddresses(Node *);
    void AggregateLiteral(Node *);
    void Slice(SliceExpr *);
    void SliceView(SliceExpr *);
    void EnsureMemory(uint32_t, Line);
    void Dynamic(uint32_t, Line);
    string Finish();
};

struct Compiler {
    Ast &ast;
    DirectWasmOptions opts;
    vector<Signature> signatures;
    vector<Import> imports;
    vector<FnSpec *> specs;
    unordered_set<FnSpec *> reachable;
    unordered_map<FnSpec *, vector<VarDef *>> captures;
    unordered_set<VarDef *> captured_storage;
    unordered_map<FnSpec *, uint32_t> function_index;
    unordered_map<FnSpec *, uint32_t> function_type;
    unordered_map<FnSpec *, uint32_t> run_index;
    unordered_map<FnSpec *, uint8_t> intrinsic_opcode;
    unordered_map<VarDef *, Slot> globals;
    unordered_map<TypeExpr *, Layout> layouts;
    unordered_map<TypeExpr *, Layout> control_layouts;
    bool needs_regions = false;
    unordered_map<VarDef *, uint32_t> global_regions;
    struct RegionCall { FnSpec *callee; uint32_t live; Line line; };
    unordered_map<FnSpec *, vector<RegionCall>> region_calls;
    unordered_map<FnSpec *, uint32_t> region_own;
    uint32_t BoundRegions();
    // A payload can contain a sibling variant by value. Its layout must not
    // depend on computing the whole parent enum's union first.
    map<pair<EnumInst *, int>, Layout> payload_layouts;
    unordered_map<EnumInst *, Layout> enum_image_layouts;
    map<pair<EnumInst *, int>, TypeExpr *> enum_variant_types;
    map<string, uint32_t> strings;
    string data;
    static constexpr uint32_t data_base = 1024;
    enum Host : uint32_t { WRITE, PRINT_I64, PRINT_U64, PRINT_F64, PRINT_F32, PRINT_BOOL, NEWLINE, ABORT, EXIT };

    Compiler(Ast &a, const DirectWasmOptions &o) : ast(a), opts(o) {}
    [[noreturn]] void Fail(Line l, const string &msg) {
        Diagnostic d;
        d.where = LocOf(l);
        d.message = "wasm-direct: " + msg;
        d.text = ast.DiagnosticText(d, true);
        throw CompileError { d.text, { d } };
    }
    bool Aggregate(TypeExpr *t) const {
        return t && (t->kind == TY_ARRAY || t->kind == TY_STRUCT || t->kind == TY_ENUM || t->kind == TY_VARIANT);
    }
    const Layout &Payload(EnumInst *ei, int vi) {
        auto key = make_pair(ei, vi);
        if (auto it = payload_layouts.find(key); it != payload_layouts.end()) return it->second;
        Layout r;
        for (size_t i = 0; i < ei->vftypes.at(size_t(vi)).size(); i++) {
            auto &field = ei->en->variants.at(size_t(vi)).fields[i];
            if (field.ispad) Fail(field.line, "explicit variant padding is not supported");
            auto sub = Size(ei->vftypes[size_t(vi)][i]);
            // Variant fields are adjacent in the pinned image format. Each
            // field still uses its own current representation.
            r.fields.push_back(r.size);
            if (uint64_t(r.size) + sub.size > uint64_t(opts.maximum_pages) * 65536)
                Fail(field.line, "variant exceeds the configured linear-memory limit");
            r.size += sub.size;
        }
        r.size = max<uint32_t>(1, r.size);
        return payload_layouts.emplace(key, std::move(r)).first->second;
    }
    static bool PackedIntegerEnum(EnumInst *ei) {
        if (!ei || !ei->allfixed) return false;
        for (auto &fields : ei->vftypes) for (auto field : fields)
            if (!field || field->kind != TY_INT || field->intstorage == IS_VARINT) return false;
        return true;
    }
    const Layout &EnumImageLayout(EnumInst *ei, Line line) {
        if (!ei) Fail(line, "enum instantiation was not resolved");
        if (!ei->allfixed && ei->varclass != SC_VARIABLE)
            Fail(line, "resizable variable-mode enums are not supported");
        if (auto found = enum_image_layouts.find(ei); found != enum_image_layouts.end()) return found->second;
        Layout r; r.align = 4;
        uint32_t bytes = 0, alignment = 1, data_alignment = 1;
        for (size_t vi = 0; vi < ei->vftypes.size(); vi++) {
            auto vt = EnumVariantType(ei, int(vi), line);
            if (Class(vt) != SC_FIXED && !RegionVariant(vt))
                Fail(line, "variable enum payloads require one final nonresizable array tail");
            auto sub = RegionVariant(vt) ? ControlLayout(vt) : FixedLayout(vt);
            if (RegionVariant(vt)) data_alignment = max(data_alignment, FixedLayout(TailType(vt)->arr->sub).align);
            bytes = max(bytes, sub.size); alignment = max(alignment, sub.align);
        }
        r.align = max({ r.align, alignment, data_alignment }); r.payload = Align(4, alignment);
        auto size = (uint64_t(r.payload) + bytes + r.align - 1) & ~uint64_t(r.align - 1);
        if (size > uint64_t(opts.maximum_pages) * 65536)
            Fail(line, "enum exceeds the configured linear-memory limit");
        r.size = uint32_t(size);
        return enum_image_layouts.emplace(ei, std::move(r)).first->second;
    }
    TypeExpr *EnumVariantType(EnumInst *ei, int vi, Line line) {
        auto key = make_pair(ei, vi);
        if (auto found = enum_variant_types.find(key); found != enum_variant_types.end()) return found->second;
        auto adt = ast.EnumOf(ei->en, ei->args, false, line); adt->enu->inst = ei;
        auto &variant = ei->en->variants.at(size_t(vi));
        auto type = ast.VariantOf(adt, variant.name, &variant, line);
        enum_variant_types.emplace(key, type); return type;
    }
    TypeExpr *FieldType(TypeExpr *t, int field) {
        if (t->kind == TY_STRUCT) return t->struc->inst->ftypes.at(size_t(field));
        if (t->kind == TY_VARIANT) {
            auto ei = t->var->adt->enu->inst;
            return ei->vftypes.at(size_t(ei->en->VariantIndex(t->var->variant))).at(size_t(field));
        }
        Fail(t->line, "only fixed struct and variant fields are supported");
    }
    uint8_t W(TypeExpr *t) {
        if (!t || t->kind == TY_VOID) return VOID;
        switch (t->kind) {
            case TY_BOOL: return I32;
            case TY_INT:
                if (t->intstorage == IS_VARINT) Fail(t->line, "varint storage is not supported");
                return IntBits(t->intstorage) == 64 ? I64 : I32;
            case TY_FLT: return IsF32(t) ? F32 : F64;
            case TY_REF:
                if (t->ref->lenstorage >= 0 || t->ref->pool)
                    Fail(t->line, "relative and pool references are not supported");
                if (RegionOwner(t->ref->sub)) ControlLayout(t->ref->sub); else Size(t->ref->sub);
                return I32;
            case TY_SLICE: Size(t->sub); return I64; // packed pointer + length
            case TY_ARRAY:
                if (RegionArray(t)) HeaderLayout(t); else Size(t);
                return I32;
            case TY_STRUCT: if (RegionStruct(t)) ControlLayout(t); else Size(t); return I32;
            case TY_ENUM: if (RegionEnum(t)) ControlLayout(t); else Size(t); return I32;
            case TY_VARIANT: if (RegionVariant(t)) ControlLayout(t); else Size(t); return I32;
            default: {
                string s; t->Dump(s);
                Fail(t->line, "unsupported runtime type " + s);
            }
        }
    }
    static uint32_t Align(uint32_t x, uint32_t n) { return (x + n - 1) & ~(n - 1); }
    static bool GrowableArray(TypeExpr *t) {
        return t && t->kind == TY_ARRAY && (t->arr->akind == A_GROW || t->arr->akind == A_GROWSHRINK);
    }
    static bool RuntimeLimited(TypeExpr *t) {
        return t && t->kind == TY_ARRAY && t->arr->akind == A_LIMITED && t->arr->size < 0;
    }
    static bool RegionArray(TypeExpr *t) {
        return GrowableArray(t) || RuntimeLimited(t) || (t && t->kind == TY_ARRAY && t->arr->akind == A_VAR);
    }
    static bool FrameStruct(TypeExpr *t) {
        return t && t->kind == TY_STRUCT && t->struc->inst &&
               t->struc->inst->sclass == SC_RESIZABLE && t->struc->inst->frameobj;
    }
    static bool RegionStruct(TypeExpr *t) {
        return t && t->kind == TY_STRUCT && t->struc->inst &&
               (t->struc->inst->sclass == SC_VARIABLE || FrameStruct(t));
    }
    static bool RegionEnum(TypeExpr *t) { return t && t->kind == TY_ENUM && t->enu->varmode; }
    static bool RegionVariant(TypeExpr *t) {
        if (!t || t->kind != TY_VARIANT || !t->var->adt->enu->inst) return false;
        auto ei = t->var->adt->enu->inst;
        auto &fields = ei->vftypes.at(size_t(ei->en->VariantIndex(t->var->variant)));
        auto tail = fields.empty() ? nullptr : fields.back();
        return (RegionArray(tail) && !GrowableArray(tail)) || (RegionRecord(tail) && !FrameStruct(tail));
    }
    static bool RegionRecord(TypeExpr *t) { return RegionStruct(t) || RegionVariant(t); }
    static bool SameRecord(TypeExpr *left, TypeExpr *right) {
        if (!left || !right || left->kind != right->kind) return false;
        if (left->kind == TY_STRUCT) return left->struc->inst == right->struc->inst;
        return left->kind == TY_VARIANT && left->var->adt->enu->inst == right->var->adt->enu->inst &&
               left->var->variant == right->var->variant && left->var->adt->enu->varmode == right->var->adt->enu->varmode;
    }
    const vector<TypeExpr *> &RecordFields(TypeExpr *t) {
        if (t->kind == TY_STRUCT) return t->struc->inst->ftypes;
        auto ei = t->var->adt->enu->inst;
        return ei->vftypes.at(size_t(ei->en->VariantIndex(t->var->variant)));
    }
    const vector<Field> &RecordFieldDefs(TypeExpr *t) {
        if (t->kind == TY_STRUCT) return t->struc->inst->st->fields;
        auto ei = t->var->adt->enu->inst;
        return ei->en->variants.at(size_t(ei->en->VariantIndex(t->var->variant))).fields;
    }
    static bool RegionOwner(TypeExpr *t) { return RegionArray(t) || RegionRecord(t) || RegionEnum(t); }
    static bool WholeHeaderOwner(TypeExpr *t) { return RuntimeLimited(t) || RegionEnum(t) || (RegionRecord(t) && !FrameStruct(t)); }
    static IntStorage LengthStorage(TypeExpr *t) {
        return t->arr->lenstorage < 0 ? IS_U32 : IntStorage(t->arr->lenstorage);
    }
    Layout HeaderLayout(TypeExpr *t) {
        if (!RegionArray(t)) return FixedLayout(t);
        if (t->arr->akind == A_VAR && LengthStorage(t) == IS_VARINT)
            Fail(t->line, "varint variable-array length storage is not supported");
        FixedLayout(t->arr->sub);
        Layout header; header.size = 16; header.align = 4; return header;
    }
    const Layout &ControlLayout(TypeExpr *t) {
        if (auto found = control_layouts.find(t); found != control_layouts.end()) return found->second;
        Layout layout;
        if (RegionArray(t)) layout = HeaderLayout(t);
        else if (RegionEnum(t)) {
            EnumImageLayout(t->enu->inst, t->line);
            layout.size = 16; layout.align = 4;
        }
        else if (RegionRecord(t)) {
            auto &fields = RecordFields(t);
            auto &defs = RecordFieldDefs(t);
            auto tail = fields.empty() ? nullptr : fields.back();
            auto tail_array = tail && tail->kind == TY_ARRAY &&
                (FrameStruct(t) ? GrowableArray(tail) : (tail->arr->akind == A_VAR || RuntimeLimited(tail)));
            auto tail_struct = RegionRecord(tail) && FrameStruct(t) == FrameStruct(tail);
            if (!tail_array && !tail_struct)
                Fail(t->line, "owned structs require one final variable-array field, runtime-limited array field or nested single-tail owner");
            for (size_t i = 0; i < fields.size(); i++) {
                if (defs[i].ispad) Fail(t->line, "explicit record padding is not supported");
                auto field = i + 1 == fields.size() ? ControlLayout(fields[i]) : FixedLayout(fields[i]);
                layout.align = max(layout.align, field.align);
                layout.size = Align(layout.size, field.align); layout.fields.push_back(layout.size);
                if (uint64_t(layout.size) + field.size > uint64_t(opts.maximum_pages) * 65536)
                    Fail(t->line, "owned struct control storage exceeds linear memory");
                layout.size += field.size;
            }
            layout.payload = layout.fields.back() + (tail_struct ? ControlLayout(tail).payload : 0);
            layout.size = Align(layout.size, layout.align);
        } else return FixedLayout(t);
        return control_layouts.emplace(t, std::move(layout)).first->second;
    }
    TypeExpr *TailType(TypeExpr *t) {
        ControlLayout(t); return RegionRecord(t) ? TailType(RecordFields(t).back()) : t;
    }
    uint32_t FieldOffset(TypeExpr *t, size_t field) {
        return (RegionRecord(t) ? ControlLayout(t) : Size(t)).fields.at(field);
    }
    // The checker's physical size class is independent of a future runtime
    // descriptor's byte size. Only SC_FIXED values may use ordinary copies.
    SizeClass Class(TypeExpr *t) {
        switch (t->kind) {
            case TY_INT: return t->intstorage == IS_VARINT ? SC_VARIABLE : SC_FIXED;
            case TY_REF: return t->ref->lenstorage == IS_VARINT ? SC_VARIABLE : SC_FIXED;
            case TY_STRUCT:
                if (!t->struc->inst) Fail(t->line, "struct storage class was not resolved");
                return t->struc->inst->sclass;
            case TY_ENUM:
                if (!t->enu->inst) Fail(t->line, "enum storage class was not resolved");
                return t->enu->varmode ? t->enu->inst->varclass : SC_FIXED;
            case TY_ARRAY:
                if (t->arr->akind == A_FIXED) return SC_FIXED;
                if (t->arr->akind == A_VAR) return SC_VARIABLE;
                if (t->arr->akind == A_LIMITED) return t->arr->size >= 0 ? SC_FIXED : SC_VARIABLE;
                return SC_RESIZABLE;
            case TY_VARIANT: {
                auto ei = t->var->adt->enu->inst;
                auto vi = ei->en->VariantIndex(t->var->variant);
                auto result = SC_FIXED;
                for (auto field : ei->vftypes.at(size_t(vi))) if (field) result = max(result, Class(field));
                return result;
            }
            default: return SC_FIXED;
        }
    }
    const Layout &FixedLayout(TypeExpr *t) {
        auto &layout = Size(t); // preserve target refusals for unsupported types
        if (Class(t) != SC_FIXED) Fail(t->line, "nonfixed owned construction is not supported by the fixed-value copy path");
        return layout;
    }
    const Layout &Size(TypeExpr *t) {
        auto it = layouts.find(t); if (it != layouts.end()) return it->second;
        Layout r;
        switch (t->kind) {
            case TY_BOOL: r.size = r.align = 1; break;
            case TY_INT:
                if (t->intstorage == IS_VARINT) Fail(t->line, "varint storage is not supported");
                r.size = r.align = uint32_t(IntBits(t->intstorage) / 8); break;
            case TY_FLT: r.size = r.align = IsF32(t) ? 4 : 8; break;
            case TY_REF:
                if (t->ref->lenstorage >= 0 || t->ref->pool)
                    Fail(t->line, "relative and pool references are not supported");
                r.size = r.align = 4; break;
            case TY_SLICE: r.size = r.align = 8; break;
            case TY_ARRAY: {
                if (t->arr->akind != A_FIXED && t->arr->akind != A_LIMITED)
                    Fail(t->line, "this array kind is not supported without dynamic storage; use the C oracle target");
                if (t->arr->size < 0)
                    Fail(t->line, "construction-time array capacity is not supported without dynamic storage");
                auto sub = Size(t->arr->sub);
                if (t->arr->akind == A_LIMITED) {
                    r.payload = Align(4, sub.align);
                    r.align = max<uint32_t>(4, sub.align);
                } else r.align = sub.align;
                auto bytes = uint64_t(r.payload) + uint64_t(sub.size) * uint64_t(t->arr->size);
                if (bytes > uint64_t(opts.maximum_pages) * 65536)
                    Fail(t->line, "fixed array exceeds the configured linear-memory limit");
                r.size = max<uint32_t>(1, Align(uint32_t(bytes), r.align));
                break;
            }
            case TY_STRUCT: {
                auto si = t->struc->inst;
                if (!si || si->sclass != SC_FIXED) Fail(t->line, "only fixed-size structs are supported");
                for (size_t i = 0; i < si->ftypes.size(); i++) {
                    auto &f = si->st->fields[i];
                    if (f.ispad) Fail(f.line, "explicit struct padding is not supported");
                    auto sub = Size(si->ftypes[i]);
                    r.align = max(r.align, sub.align);
                    r.size = Align(r.size, sub.align);
                    r.fields.push_back(r.size);
                    if (uint64_t(r.size) + sub.size > uint64_t(opts.maximum_pages) * 65536)
                        Fail(t->line, "struct exceeds the configured linear-memory limit");
                    r.size += sub.size;
                }
                r.size = max<uint32_t>(1, Align(r.size, r.align)); break;
            }
            case TY_VARIANT: {
                auto ei = t->var->adt->enu->inst;
                if (!ei) Fail(t->line, "variant type was not resolved");
                r = Payload(ei, ei->en->VariantIndex(t->var->variant)); break;
            }
            case TY_ENUM: {
                auto ei = t->enu->inst;
                if (t->enu->varmode || !ei || !ei->allfixed)
                    Fail(t->line, "only fixed-mode enums with fixed-size payloads are supported");
                r = EnumImageLayout(ei, t->line); break;
            }
            default: { string s; t->Dump(s); Fail(t->line, "no direct layout for " + s); }
        }
        return layouts.emplace(t, std::move(r)).first->second;
    }
    uint32_t Data(uint32_t size, uint32_t align = 1) {
        auto off = Align(data_base + uint32_t(data.size()), align);
        if (uint64_t(off) + size > uint64_t(opts.maximum_pages) * 65536)
            Fail({}, "static data exceeds the configured linear-memory limit");
        data.resize(size_t(off - data_base) + size, '\0');
        return off;
    }
    uint32_t Text(string_view s) {
        auto it = strings.find(string(s)); if (it != strings.end()) return it->second;
        auto off = Data(uint32_t(max<size_t>(s.size(), 1)));
        data.replace(off - data_base, s.size(), s);
        strings.emplace(s, off); return off;
    }
    uint32_t Sig(Signature s) {
        for (uint32_t i = 0; i < signatures.size(); i++) if (signatures[i] == s) return i;
        signatures.push_back(std::move(s)); return uint32_t(signatures.size() - 1);
    }
    uint32_t AddImport(string module, string name, Signature s) {
        auto ty = Sig(std::move(s));
        for (uint32_t i = 0; i < imports.size(); i++)
            if (imports[i].module == module && imports[i].name == name) {
                if (imports[i].type != ty) Fail({}, "external symbol has conflicting signatures: " + name);
                return i;
            }
        imports.push_back({ std::move(module), std::move(name), ty });
        return uint32_t(imports.size() - 1);
    }
    void AnalyzeCaptures();
    Signature FunctionSig(FnSpec *sp) {
        Signature s;
        for (auto p : sp->params) {
            if (p->type->kind == TY_FN) continue;
            if (RegionOwner(p->type)) needs_regions = true;
            s.args.push_back(W(p->type));
        }
        for (auto capture : captures[sp]) {
            W(capture->type);
            if (RegionOwner(capture->type)) needs_regions = true;
            s.args.push_back(I32);
        }
        for (auto t : sp->rets) {
            if (RegionOwner(t)) {
                needs_regions = true;
            }
            if (Aggregate(t) && !sp->sf->isextern) s.args.push_back(I32);
            s.results.push_back(W(t));
        }
        return s;
    }
    // Only exact scalar C signatures with the runtime/libm semantics used
    // by the pinned standard library are intrinsics. In particular, Goose's
    // own abs body preserves negative zero; replacing that body with fabs
    // would change its result. User-defined bodies are never recognized by
    // their names, and a mismatching extern remains an ordinary host import.
    uint8_t Intrinsic(FnSpec *sp) {
        if (!sp->sf->isextern || sp->params.size() != 1 || sp->rets.size() != 1) return 0;
        auto from = sp->params[0]->type, to = sp->rets[0];
        auto name = sp->sf->cname.empty() ? string(sp->sf->qname) : sp->sf->cname;
        if (name == "gs_clz" && IsIntT(from) && from->intstorage == IS_U64 &&
            IsIntT(to) && to->intstorage == IS_I64) return 0x79;
        if (from->kind != TY_FLT || to->kind != TY_FLT || IsF32(from) != IsF32(to)) return 0;
        if (IsF32(from)) {
            if (name == "gs_sqrtf" || name == "sqrtf") return 0x91;
            if (name == "ceilf") return 0x8d;
            if (name == "floorf") return 0x8e;
            if (name == "truncf") return 0x8f;
            if (name == "fabsf") return 0x8b;
        } else {
            if (name == "gs_sqrt" || name == "sqrt") return 0x9f;
            if (name == "ceil") return 0x9b;
            if (name == "floor") return 0x9c;
            if (name == "trunc") return 0x9d;
            if (name == "fabs") return 0x99;
        }
        return 0;
    }
    void Reach(FnSpec *sp) {
        if (!sp || !reachable.insert(sp).second) return;
        if (sp->sf->isthread) Fail(sp->sf->line, "threads are not supported by the direct host ABI");
        if (sp->sf->isextern) {
            auto signature = FunctionSig(sp);
            if (!sp->sf->dylib.empty()) Fail(sp->sf->line, "dynamic-library externs are not supported");
            for (auto p : sp->params)
                if (p->type->kind != TY_INT && p->type->kind != TY_FLT && p->type->kind != TY_BOOL)
                    Fail(sp->sf->line, "externs currently accept numeric and bool values only");
            for (auto t : sp->rets)
                if (t->kind != TY_INT && t->kind != TY_FLT && t->kind != TY_BOOL)
                    Fail(sp->sf->line, "externs currently return numeric and bool values only");
            if (auto op = Intrinsic(sp)) {
                intrinsic_opcode[sp] = op;
                function_type[sp] = Sig(std::move(signature));
                return;
            }
            auto name = sp->sf->cname.empty() ? string(sp->sf->qname) : sp->sf->cname;
            function_index[sp] = AddImport("env", name, signature);
            function_type[sp] = Sig(std::move(signature));
            return;
        }
        specs.push_back(sp);
        Scan(sp->body);
    }
    void Scan(Node *n) {
        if (!n) return;
        if (auto literal = Is<ArrayLit>(n); literal && literal->capexpr) needs_regions = true;
        auto type = n->exprtype;
        if (RegionOwner(type) || (type && type->kind == TY_REF && RegionOwner(type->ref->sub))) needs_regions = true;
        if (auto inlined = Is<InlineBlock>(n); inlined && inlined->spec)
            for (auto result : inlined->spec->rets) if (RegionOwner(result)) needs_regions = true;
        if (auto declaration = Is<VarDecl>(n))
            for (auto variable : declaration->defs) if (RegionOwner(variable->type)) needs_regions = true;
        if (Is<FnDecl>(n) || Is<StructDecl>(n) || Is<EnumDecl>(n) || Is<AliasDecl>(n) || Is<FunVal>(n)) return;
        if (auto call = Is<Call>(n)) {
            if (call->fvbody) {
                for (auto parameter : call->fvparams) if (RegionOwner(parameter->type)) needs_regions = true;
                Scan(call->fvbody);
            } else if (!call->dispatch.empty()) {
                for (auto arm : call->dispatch) Reach(arm);
            } else if (call->builtin < 0) Reach(call->spec);
            for (auto a : call->ValueArgNodes()) Scan(a);
            if (call->defaultinit) Scan(call->defaultinit);
            return;
        }
        n->Children([&](Node *ch) { Scan(ch); });
    }
    DirectWasmResult Compile();
};

inline Function::Function(Compiler &compiler, FnSpec *s, uint32_t i, uint32_t ty, bool run)
    : c(compiler), spec(s), index(i), sig(ty), element_run(run) {
    addressed.insert(c.captured_storage.begin(), c.captured_storage.end());
    if (spec) {
        results = spec->rets;
        ScanAddresses(spec->body);
        for (auto p : spec->params) {
            if (p->type->kind == TY_FN) continue;
            // An owned dynamic argument has a private caller-constructed
            // header, rather than a descriptor copied into this frame.
            vars[p] = { Compiler::RegionOwner(p->type) ? Slot::ADDRESS : Slot::LOCAL,
                        uint32_t(params.size()), p->type };
            params.push_back(W(p->type));
        }
        for (auto capture : c.captures[spec]) {
            vars[capture] = { Slot::ADDRESS, uint32_t(params.size()), capture->type };
            params.push_back(I32);
        }
        for (auto t : results) {
            if (c.Aggregate(t)) {
                resultdestinations.push_back(uint32_t(params.size()));
                params.push_back(I32);
            } else resultdestinations.push_back(nullopt);
        }
    } else for (auto g : c.ast.globals) for (auto n : g->inits) ScanAddresses(n);
    framebase = Local(I32);
    for (auto t : results) resultlocals.push_back(Local(t));
}
inline void Function::Fail(Line l, const string &s) { c.Fail(l, s); }
inline uint8_t Function::W(TypeExpr *t) { return c.W(t); }
inline void Function::Abort(Line l, string_view msg) {
    auto p = c.Text(msg);
    code.I32Const(int32_t(p)); code.I32Const(int32_t(msg.size())); code.I32Const(l.line);
    CallIndex(Compiler::ABORT); code.Op(0x00);
}
inline uint32_t Function::FrameBytes(uint32_t n, uint32_t align) {
    auto off = Compiler::Align(framebytes, align);
    if (uint64_t(off) + n > uint64_t(c.opts.maximum_pages) * 65536)
        Fail(spec ? spec->sf->line : Line{}, "activation frame exceeds the linear-memory limit");
    framebytes = off + n; return off;
}
inline uint32_t Function::Frame(TypeExpr *t) { auto l = c.FixedLayout(t); return FrameBytes(l.size, l.align); }
inline Slot Function::Lookup(VarDef *v, Line l) {
    v = Resolve(v);
    if (auto it = vars.find(v); it != vars.end()) return it->second;
    if (auto it = c.globals.find(v); it != c.globals.end()) return it->second;
    Fail(l, "captured variable '" + string(v ? v->name : string_view("?")) +
            "' is not available in this activation; use an inline function or an explicit parameter");
}
inline Slot Function::Bind(VarDef *v) {
    if (auto i = vars.find(v); i != vars.end()) return i->second;
    if (v->reusable) Fail(v->line, "reusable storage is not supported");
    Slot s;
    s.type = v->type;
    if (Compiler::RegionOwner(v->type)) { auto layout = c.ControlLayout(v->type); s.kind = Slot::FRAME; s.index = FrameBytes(layout.size, layout.align); }
    else if (c.Aggregate(v->type) || addressed.count(v)) { s.kind = Slot::FRAME; s.index = Frame(v->type); }
    else { s.kind = Slot::LOCAL; s.index = Local(v->type); }
    return vars.emplace(v, s).first->second;
}
inline void Function::Load(TypeExpr *t) {
    if (c.Aggregate(t)) return; // aggregate values are addresses
    if (t->kind == TY_FLT) { code.Mem(IsF32(t) ? 0x2a : 0x2b); return; }
    if (t->kind == TY_SLICE) { code.Mem(0x29); return; }
    if (t->kind == TY_REF) { W(t); code.Mem(0x28); return; }
    if (t->kind == TY_BOOL) { code.Mem(0x2d); return; }
    if (!IsIntT(t)) Fail(t->line, "unsupported load type");
    auto bits = IntBits(t->intstorage);
    auto u = IsUnsigned(t->intstorage);
    code.Mem(bits == 8 ? (u ? 0x2d : 0x2c) : bits == 16 ? (u ? 0x2f : 0x2e) : bits == 32 ? 0x28 : 0x29);
}
inline void Function::Store(TypeExpr *t) {
    if (c.Aggregate(t)) { code.I32Const(int32_t(c.FixedLayout(t).size)); code.Copy(); return; }
    if (t->kind == TY_FLT) { code.Mem(IsF32(t) ? 0x38 : 0x39); return; }
    if (t->kind == TY_SLICE) { code.Mem(0x37); return; }
    if (t->kind == TY_REF) { W(t); code.Mem(0x36); return; }
    if (t->kind == TY_BOOL) { code.Mem(0x3a); return; }
    if (!IsIntT(t)) Fail(t->line, "unsupported store type");
    auto bits = IntBits(t->intstorage);
    code.Mem(bits == 8 ? 0x3a : bits == 16 ? 0x3b : bits == 32 ? 0x36 : 0x37);
}
inline void Function::Read(const Slot &s) {
    if (s.kind == Slot::LOCAL) Get(s.index); else { SlotAddress(s); Load(s.type); }
}
inline void Function::Write(const Slot &s) {
    if (s.kind == Slot::LOCAL) Set(s.index);
    else { auto v = Save(s.type); SlotAddress(s); Get(v); Store(s.type); }
}
inline void Function::ScanAddresses(Node *n) {
    if (!n || Is<FnDecl>(n) || Is<FunVal>(n)) return;
    if (auto id = Is<Ident>(n); id && id->vdef && n->exprtype &&
        n->exprtype->kind == TY_REF && id->vdef->type->kind != TY_REF)
        addressed.insert(id->vdef);
    if (auto u = Is<Unary>(n); u && u->op == T_BITAND)
        if (auto id = Is<Ident>(u->child); id && id->vdef && id->vdef->type->kind != TY_REF) addressed.insert(id->vdef);
    if (auto d = Is<VarDecl>(n); d && d->byref)
        for (auto x : d->inits) if (auto id = Is<Ident>(x); id && id->vdef) addressed.insert(id->vdef);
    if (auto call = Is<Call>(n)) {
        if (call->fvbody) ScanAddresses(call->fvbody);
        auto args = call->ValueArgNodes();
        auto signature = call->spec ? call->spec : call->dispatch.empty() ? nullptr : call->dispatch.front();
        if (signature) {
            size_t ai = 0;
            for (auto p : signature->params) {
                if (p->type->kind == TY_FN) continue;
                if (ai < args.size() && p->type->kind == TY_REF)
                    if (auto id = Is<Ident>(args[ai]); id && id->vdef && id->vdef->type->kind != TY_REF)
                        addressed.insert(id->vdef);
                ai++;
            }
        }
        for (auto a : args) ScanAddresses(a);
        if (call->defaultinit) ScanAddresses(call->defaultinit);
        return;
    }
    n->Children([&](Node *ch) { ScanAddresses(ch); });
}

} // namespace direct_wasm
} // namespace goose

#include "direct_wasm_numeric.h"
#include "direct_wasm_captures.h"
#include "direct_wasm_funvals.h"
#include "direct_wasm_dispatch.h"
#include "direct_wasm_storage.h"
#include "direct_wasm_owned.h"
#include "direct_wasm_enums.h"
#include "direct_wasm_regions.h"
#include "direct_wasm_temps.h"
#include "direct_wasm_arrays.h"
#include "direct_wasm_expr.h"
#include "direct_wasm_emit.h"

namespace goose {
inline DirectWasmResult CompileDirectWasm(Ast &ast, const DirectWasmOptions &options = {}) {
    return direct_wasm::Compiler(ast, options).Compile();
}
}
