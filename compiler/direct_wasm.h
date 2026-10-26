// Direct Goose -> WebAssembly backend. Input is the upstream checker's
// specialized AST, after the ordinary Goose optimizer and bounds analysis.
// Include this header after the upstream frontend headers.
#pragma once
#include "wasm_binary.h"

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
    vector<DirectWasmFunctionInfo> function_info;
};

namespace direct_wasm {

struct Signature {
    vector<uint8_t> args, results;
    bool operator==(const Signature &) const = default;
};
struct Import { string module, name; uint32_t type; };
struct Layout { uint32_t size = 0, align = 1; vector<uint32_t> fields; };
struct Slot {
    enum Kind { LOCAL, FRAME, GLOBAL } kind = LOCAL;
    uint32_t index = 0;
    TypeExpr *type = nullptr;
};
struct Compiler;

struct Function {
    Compiler &c;
    FnSpec *spec;
    uint32_t index, sig;
    vector<uint8_t> params, locals;
    vector<TypeExpr *> results;
    vector<uint32_t> resultlocals;
    unordered_map<VarDef *, Slot> vars;
    unordered_set<VarDef *> addressed;
    vector<unordered_map<VarDef *, VarDef *>> aliases;
    uint32_t framebase = 0, framebytes = 0;
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
    };
    vector<Exit> exits;
    // A print may be abandoned by a return/break in an argument. Restore
    // only print scopes that the branch leaves; a loop inside an argument
    // must keep snapshots captured by its enclosing print alive.
    vector<pair<size_t, uint32_t>> printmarks;
    void UnwindPrints(size_t target) {
        for (auto [depth, mark] : printmarks) if (target < depth) {
            Get(mark); code.OpU(0x24, 0); return;
        }
    }
    set<uint32_t> dependencies;

    Function(Compiler &, FnSpec *, uint32_t, uint32_t);
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
    void Truth(Node *);
    void BinaryOp(TType, TypeExpr *, Line);
    uint32_t Frame(TypeExpr *);
    uint32_t FrameBytes(uint32_t n, uint32_t align = 8);
    void FrameAddress(uint32_t off) { Get(framebase); if (off) { code.I32Const(int32_t(off)); code.Op(0x6a); } }
    void SlotAddress(const Slot &s) {
        if (s.kind == Slot::FRAME) FrameAddress(s.index);
        else if (s.kind == Slot::GLOBAL) code.I32Const(int32_t(s.index));
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
    void Address(Node *);
    TypeExpr *Object(Node *);
    void View(Node *);
    void Expr(Node *);
    void To(Node *, TypeExpr *);
    void Discard(Node *);
    void BlockInto(Block *, const vector<TypeExpr *> &, const vector<uint32_t> &);
    void SetResults(const vector<Node *> &, const vector<TypeExpr *> &, const vector<uint32_t> &, Line);
    vector<TypeExpr *> Values(Node *);
    void EmitCall(Call *);
    void Builtin(Call *);
    void Print(TypeExpr *, uint32_t, Line, bool nested = false);
    void PrintText(string_view);
    void Decl(VarDecl *);
    void AssignNode(Assign *);
    void IncNode(IncDec *);
    void For(ForLoop *);
    void ScanAddresses(Node *);
    void AggregateLiteral(Node *);
    void Slice(SliceExpr *);
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
    unordered_map<FnSpec *, uint32_t> function_index;
    unordered_map<FnSpec *, uint32_t> function_type;
    unordered_map<VarDef *, Slot> globals;
    unordered_map<TypeExpr *, Layout> layouts;
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
    bool Aggregate(TypeExpr *t) const { return t && (t->kind == TY_ARRAY || t->kind == TY_STRUCT); }
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
                Size(t->ref->sub); return I32;
            case TY_SLICE: Size(t->sub); return I64; // packed pointer + length
            case TY_ARRAY: case TY_STRUCT: Size(t); return I32;
            default: {
                string s; t->Dump(s);
                Fail(t->line, "unsupported runtime type " + s);
            }
        }
    }
    static uint32_t Align(uint32_t x, uint32_t n) { return (x + n - 1) & ~(n - 1); }
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
                if (t->arr->akind != A_FIXED)
                    Fail(t->line, "only fixed-size owned arrays are supported; resizable arrays require the C oracle target");
                if (t->arr->size < 0) Fail(t->line, "array length was not resolved");
                auto sub = Size(t->arr->sub);
                auto bytes = uint64_t(sub.size) * uint64_t(t->arr->size);
                if (bytes > uint64_t(opts.maximum_pages) * 65536)
                    Fail(t->line, "fixed array exceeds the configured linear-memory limit");
                r.size = uint32_t(max<uint64_t>(1, bytes)); r.align = sub.align;
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
    Signature FunctionSig(FnSpec *sp) {
        Signature s;
        for (auto p : sp->params) {
            if (p->type->kind == TY_FN) continue;
            s.args.push_back(W(p->type));
        }
        for (auto t : sp->rets) {
            if (Aggregate(t)) Fail(sp->sf->line, "returning owned arrays or structs from an out-of-line function is not yet supported");
            s.results.push_back(W(t));
        }
        return s;
    }
    void Reach(FnSpec *sp) {
        if (!sp || function_type.count(sp)) return;
        if (sp->sf->isthread) Fail(sp->sf->line, "threads are not supported by the direct host ABI");
        auto signature = FunctionSig(sp);
        if (sp->sf->isextern) {
            if (!sp->sf->dylib.empty()) Fail(sp->sf->line, "dynamic-library externs are not supported");
            for (auto p : sp->params)
                if (p->type->kind != TY_INT && p->type->kind != TY_FLT && p->type->kind != TY_BOOL)
                    Fail(sp->sf->line, "externs currently accept numeric and bool values only");
            for (auto t : sp->rets)
                if (t->kind != TY_INT && t->kind != TY_FLT && t->kind != TY_BOOL)
                    Fail(sp->sf->line, "externs currently return numeric and bool values only");
            auto name = sp->sf->cname.empty() ? string(sp->sf->qname) : sp->sf->cname;
            function_index[sp] = AddImport("env", name, signature);
            function_type[sp] = Sig(std::move(signature));
            return;
        }
        function_type[sp] = Sig(std::move(signature));
        specs.push_back(sp);
        Scan(sp->body);
    }
    void Scan(Node *n) {
        if (!n) return;
        if (Is<FnDecl>(n) || Is<StructDecl>(n) || Is<EnumDecl>(n) || Is<AliasDecl>(n) || Is<FunVal>(n)) return;
        if (auto call = Is<Call>(n)) {
            if (!call->dispatch.empty()) Fail(call->line, "runtime overload dispatch is not supported");
            if (call->fvbody) Scan(call->fvbody); else if (call->builtin < 0) Reach(call->spec);
            for (auto a : call->ValueArgNodes()) Scan(a);
            if (call->defaultinit) Scan(call->defaultinit);
            return;
        }
        n->Children([&](Node *ch) { Scan(ch); });
    }
    DirectWasmResult Compile();
};

inline Function::Function(Compiler &compiler, FnSpec *s, uint32_t i, uint32_t ty)
    : c(compiler), spec(s), index(i), sig(ty) {
    if (spec) {
        results = spec->rets;
        ScanAddresses(spec->body);
        for (auto p : spec->params) {
            if (p->type->kind == TY_FN) continue;
            vars[p] = { Slot::LOCAL, uint32_t(params.size()), p->type };
            params.push_back(W(p->type));
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
inline uint32_t Function::Frame(TypeExpr *t) { auto l = c.Size(t); return FrameBytes(l.size, l.align); }
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
    if (c.Aggregate(v->type) || addressed.count(v)) { s.kind = Slot::FRAME; s.index = Frame(v->type); }
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
    if (c.Aggregate(t)) { code.I32Const(int32_t(c.Size(t).size)); code.Copy(); return; }
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
        if (call->spec) {
            size_t ai = 0;
            for (auto p : call->spec->params) {
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
#include "direct_wasm_expr.h"
#include "direct_wasm_emit.h"

namespace goose {
inline DirectWasmResult CompileDirectWasm(Ast &ast, const DirectWasmOptions &options = {}) {
    return direct_wasm::Compiler(ast, options).Compile();
}
}
