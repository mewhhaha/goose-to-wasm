// Import pristine parsed syntax into a request-owned Ast. This deliberately
// does not use Node::Clone, whose type/symbol/origin sharing is for checking
// specializations inside one Ast, not for crossing Ast ownership boundaries.
#pragma once
#include <stdexcept>

namespace goose {

struct ParsedSyntaxImporter {
    const Ast &from;
    Ast &to;
    int fileidx;
    unordered_map<const TypeExpr *, TypeExpr *> types;
    unordered_set<const TypeExpr *> filled_types;
    unordered_map<const TypeDetail *, TypeDetail *> details;
    unordered_map<const Node *, Node *> nodes;
    unordered_map<const SFunction *, SFunction *> functions;
    unordered_map<const SStruct *, SStruct *> structs;
    unordered_map<const SEnum *, SEnum *> enums;
    unordered_map<const SVariant *, SVariant *> variants;
    unordered_map<const SAlias *, SAlias *> aliases;

    static void Require(bool condition) {
        if (!condition) throw runtime_error("syntax importer requires a pristine parsed module");
    }

    Line Place(Line line) const {
        if (line.line) { Require(line.fileidx == 0); line.fileidx = fileidx; }
        return line;
    }

    string_view Text(string_view text) {
        if (text.empty()) return {};
        auto &old = *from.sources.at(0).second;
        auto address = reinterpret_cast<uintptr_t>(text.data());
        auto start = reinterpret_cast<uintptr_t>(old.data());
        if (address >= start && address - start <= old.size() &&
            text.size() <= old.size() - size_t(address - start))
            return string_view(to.sources.at(fileidx).second->data() + (address - start), text.size());
        return to.Intern(string(text));
    }

    template<typename T, typename F> T *Detail(const T *old, F fill) {
        if (!old) return nullptr;
        if (auto it = details.find(old); it != details.end()) return static_cast<T *>(it->second);
        auto n = new T(*old);
        to.typedetails.push_back(n); details.emplace(old, n);
        fill(*n);
        return n;
    }

    void TypeList(vector<TypeExpr *> &list) { for (auto &t : list) t = Type(t); }
    TypeExpr *Type(const TypeExpr *old) {
        if (!old) return nullptr;
        auto it = types.find(old);
        Require(it != types.end());
        auto n = it->second;
        if (!filled_types.insert(old).second) return n;
        *n = *old; n->line = Place(old->line);
        n->ix = Detail(old->ix, [&](TypeIndex &d) {
            Require(!d.arr); d.name = Text(d.name); d.ns = Text(d.ns);
        });
        switch (old->kind) {
            case TY_INT: case TY_FLT: case TY_BOOL: case TY_VOID: break;
            case TY_SLICE: n->sub = Type(old->sub); break;
            case TY_UNRESOLVED: case TY_GENERIC:
                n->named = Detail(old->named, [&](TypeName &d) {
                    d.name = Text(d.name); d.ns = Text(d.ns); d.expansionerror = Text(d.expansionerror);
                    TypeList(d.args);
                }); break;
            case TY_FN:
                n->fn = Detail(old->fn, [&](TypeFn &d) { TypeList(d.args); TypeList(d.rets); }); break;
            case TY_ARRAY:
                n->arr = Detail(old->arr, [&](TypeArray &d) {
                    d.sub = Type(d.sub); d.sizeexpr = Tree(d.sizeexpr);
                    Require(d.size == -1);
                }); break;
            case TY_REF:
                n->ref = Detail(old->ref, [&](TypeRef &d) {
                    Require(!d.pool); d.sub = Type(d.sub);
                    d.poolname = Text(d.poolname); d.poolns = Text(d.poolns);
                }); break;
            case TY_VARIANT:
                n->var = Detail(old->var, [&](TypeVariant &d) {
                    d.adt = Type(d.adt); d.name = Text(d.name);
                    if (d.variant) d.variant = variants.at(d.variant);
                }); break;
            case TY_STRUCT:
                n->struc = Detail(old->struc, [&](TypeStruct &d) {
                    Require(!d.inst); d.st = structs.at(d.st); TypeList(d.args);
                }); break;
            case TY_ENUM:
                n->enu = Detail(old->enu, [&](TypeEnum &d) {
                    Require(!d.inst); d.en = enums.at(d.en); TypeList(d.args);
                }); break;
        }
        return n;
    }

    template<typename T> T *Tree(T *old) { return static_cast<T *>(Tree(static_cast<const Node *>(old))); }
    void TreeList(vector<Node *> &list) { for (auto &n : list) n = Tree(n); }
    void Names(vector<string_view> &list) { for (auto &s : list) s = Text(s); }
    void Generics(vector<GenericParam> &list) {
        for (auto &g : list) { g.name = Text(g.name); g.line = Place(g.line); g.bound = Type(g.bound); }
    }
    void Params(vector<Param> &list) {
        for (auto &p : list) {
            p.name = Text(p.name); p.line = Place(p.line);
            p.type = Type(p.type); p.defaultval = Tree(p.defaultval);
        }
    }
    void Fields(vector<Field> &list) {
        for (auto &f : list) {
            f.name = Text(f.name); f.line = Place(f.line); f.doc = Text(f.doc);
            f.type = Type(f.type); f.defaultval = Tree(f.defaultval);
        }
    }
    void Inits(vector<FieldInit> &list) {
        for (auto &f : list) {
            f.name = Text(f.name); f.val = Tree(f.val); f.accessorowner = Type(f.accessorowner);
        }
    }
    void Arms(vector<MatchArm> &list) {
        for (auto &a : list) {
            Require(a.variants.empty() && !a.binder && a.ranges.empty());
            a.pat.binder = Text(a.pat.binder);
            for (auto &p : a.pat.items) {
                p.lo = Tree(p.lo); p.hi = Tree(p.hi); p.variantowner = Type(p.variantowner);
            }
            a.body = Tree(a.body); a.expansion = Tree(a.expansion);
        }
    }

    template<typename T> T *Copy(const Node *old) {
        Require(!old->exprtype && !old->origin);
        auto n = to.New<T>(*static_cast<const T *>(old));
        nodes.emplace(old, n);
        n->line = Place(n->line); n->end = Place(n->end);
        n->origin = nullptr; n->expansiontrace = Text(n->expansiontrace);
        return n;
    }

    Node *Tree(const Node *old) {
        if (!old) return nullptr;
        if (auto it = nodes.find(old); it != nodes.end()) return it->second;
        #define COPY(kind) auto n = Copy<kind>(old)
        switch (old->nkind) {
            case NK_IntLit: { COPY(IntLit); n->text = Text(n->text); n->fixedtype = Type(n->fixedtype); return n; }
            case NK_FltLit: { COPY(FltLit); n->text = Text(n->text); n->fixedtype = Type(n->fixedtype); return n; }
            case NK_BoolLit: { COPY(BoolLit); return n; }
            case NK_StrLit: { COPY(StrLit); return n; }
            case NK_NullLit: { COPY(NullLit); return n; }
            case NK_SelfRef: { COPY(SelfRef); return n; }
            case NK_Ident: {
                COPY(Ident); Require(!n->vdef && !n->fnref);
                n->name = Text(n->name); n->ns = Text(n->ns); n->expansionerror = Text(n->expansionerror); return n;
            }
            case NK_ArrayLit: {
                COPY(ArrayLit); TreeList(n->elems); n->fillval = Tree(n->fillval);
                n->fillcount = Tree(n->fillcount); n->capexpr = Tree(n->capexpr); return n;
            }
            case NK_StructLit: {
                COPY(StructLit); Require(!n->sinst && !n->einst && !n->variant);
                n->type = Type(n->type); Inits(n->inits); return n;
            }
            case NK_Unary: { COPY(Unary); n->child = Tree(n->child); return n; }
            case NK_Binary: {
                COPY(Binary); Require(n->rightkills.empty());
                n->left = Tree(n->left); n->right = Tree(n->right); return n;
            }
            case NK_Dot: {
                COPY(Dot); Require(!n->variantconst && !n->einst);
                n->obj = Tree(n->obj); n->name = Text(n->name); n->ns = Text(n->ns);
                n->accessorowner = Type(n->accessorowner); return n;
            }
            case NK_Call: {
                COPY(Call); Require(!n->spec && n->dispatch.empty() && !n->fvbody && !n->defaultinit &&
                                    n->fvparams.empty() && n->rettypes.empty() && n->fvremap.empty() &&
                                    n->fmtspecs.empty() && n->fmtcontexts.empty() && !n->qtype && !n->shaderblob);
                n->callee = Tree(n->callee); TypeList(n->tyargs); TreeList(n->args);
                n->trailing = Tree(n->trailing); return n;
            }
            case NK_Index: { COPY(Index); n->obj = Tree(n->obj); n->idx = Tree(n->idx); return n; }
            case NK_SliceExpr: {
                COPY(SliceExpr); n->obj = Tree(n->obj); n->lo = Tree(n->lo); n->hi = Tree(n->hi); return n;
            }
            case NK_AsCast: {
                COPY(AsCast); Require(!n->totype); n->child = Tree(n->child); n->type = Type(n->type); return n;
            }
            case NK_RangeExpr: { COPY(RangeExpr); n->lo = Tree(n->lo); n->hi = Tree(n->hi); return n; }
            case NK_Block: { COPY(Block); TreeList(n->stmts); n->tail = Tree(n->tail); return n; }
            case NK_IfExpr: {
                COPY(IfExpr); n->cond = Tree(n->cond); n->thenb = Tree(n->thenb); n->elseb = Tree(n->elseb); return n;
            }
            case NK_MatchExpr: { COPY(MatchExpr); n->scrutinee = Tree(n->scrutinee); Arms(n->arms); return n; }
            case NK_EarlyBlock: { COPY(EarlyBlock); Require(n->breaks.empty()); n->body = Tree(n->body); return n; }
            case NK_While: {
                COPY(While); Require(n->hoistrefs.empty() && n->hoistfields.empty());
                n->cond = Tree(n->cond); n->body = Tree(n->body); return n;
            }
            case NK_LoopExpr: {
                COPY(LoopExpr); Require(n->hoistrefs.empty() && n->hoistfields.empty() && n->breaks.empty());
                n->body = Tree(n->body); return n;
            }
            case NK_ForLoop: {
                COPY(ForLoop); Require(!n->vdef && !n->idxdef && n->hoistrefs.empty() &&
                                      n->hoistfields.empty() && n->lanemods.empty());
                n->var = Text(n->var); n->idxvar = Text(n->idxvar);
                n->vartype = Type(n->vartype); n->idxtype = Type(n->idxtype);
                n->iter = Tree(n->iter); n->body = Tree(n->body); return n;
            }
            case NK_ConstFor: {
                COPY(ConstFor); Names(n->names); TypeList(n->types); TreeList(n->constants);
                n->body = Tree(n->body); Inits(n->inits); Arms(n->arms); return n;
            }
            case NK_Return: {
                COPY(Return); Require(!n->target && !n->targetspec);
                TreeList(n->vals); n->from = Text(n->from); n->ns = Text(n->ns); return n;
            }
            case NK_Break: { COPY(Break); n->val = Tree(n->val); return n; }
            case NK_Continue: { COPY(Continue); return n; }
            case NK_FunVal: { COPY(FunVal); Params(n->params); n->body = Tree(n->body); return n; }
            case NK_VarDecl: {
                COPY(VarDecl); Require(n->defs.empty());
                n->ns = Text(n->ns); n->doc = Text(n->doc); Names(n->names);
                n->type = Type(n->type); TreeList(n->inits); return n;
            }
            case NK_Assign: { COPY(Assign); n->lval = Tree(n->lval); n->rhs = Tree(n->rhs); return n; }
            case NK_IncDec: { COPY(IncDec); n->lval = Tree(n->lval); return n; }
            case NK_FnDecl: { COPY(FnDecl); n->sf = functions.at(n->sf); return n; }
            case NK_StructDecl: { COPY(StructDecl); n->st = structs.at(n->st); return n; }
            case NK_EnumDecl: { COPY(EnumDecl); n->en = enums.at(n->en); return n; }
            case NK_AliasDecl: { COPY(AliasDecl); n->al = aliases.at(n->al); return n; }
            case NK_InlineBlock: break; // Optimizer output is never pristine syntax.
        }
        #undef COPY
        throw runtime_error("syntax importer encountered a non-parser node");
    }

    template<typename T> void Header(T &n) {
        n.name = Text(n.name); n.ns = Text(n.ns); n.qname = Text(n.qname); n.doc = Text(n.doc);
        n.line = Place(n.line); n.end = Place(n.end);
    }

    ParsedSyntaxImporter(const Ast &source, Ast &destination, int destination_file)
        : from(source), to(destination), fileidx(destination_file) {
        Require(from.sources.size() == 1 && from.errors.empty() && from.vardefs.empty() &&
                from.fnspecs.empty() && from.structinsts.empty() && from.enuminsts.empty() &&
                from.unknowntypes.empty());
        Require(*from.sources[0].second == *to.sources.at(fileidx).second);
        types.reserve(from.alltypes.size()); details.reserve(from.typedetails.size());
        nodes.reserve(from.allnodes.size()); filled_types.reserve(from.alltypes.size());
        functions.reserve(from.functions.size()); structs.reserve(from.structs.size());
        enums.reserve(from.enums.size()); aliases.reserve(from.aliases.size());
        // Allocate shells before following edges, preserving declaration and
        // type-vector order. Do not traverse allnodes/typedetails: tentative
        // parses retain orphan allocations whose edges can already be dead.
        for (auto old : from.functions) {
            Require(old->specs.empty()); auto n = new SFunction(*old);
            functions.emplace(old, n); to.functions.push_back(n);
        }
        for (auto old : from.structs) {
            Require(old->insts.empty()); auto n = new SStruct(*old);
            structs.emplace(old, n); to.structs.push_back(n);
        }
        for (auto old : from.enums) {
            Require(old->insts.empty()); auto n = new SEnum(*old);
            enums.emplace(old, n); to.enums.push_back(n);
            for (size_t i = 0; i < old->variants.size(); i++) variants.emplace(&old->variants[i], &n->variants[i]);
        }
        for (auto old : from.aliases) {
            auto n = new SAlias(*old); aliases.emplace(old, n); to.aliases.push_back(n);
        }
        for (int s = IS_I8; s <= IS_VARINT; s++) types.emplace(from.inttypes[s], to.inttypes[s]);
        for (int s = FS_F32; s <= FS_F64; s++) types.emplace(from.flttypes[s], to.flttypes[s]);
        types.emplace(from.booltype, to.booltype); types.emplace(from.voidtype, to.voidtype);
        for (auto &[old, n] : types) filled_types.insert(old);
        for (auto old : from.alltypes)
            if (!types.count(old)) types.emplace(old, to.NewType(old->kind, Place(old->line)));
        for (auto old : from.alltypes) Type(old);
        for (auto old : from.functions) {
            auto n = functions.at(old); Header(*n); Generics(n->generics); Params(n->params); TypeList(n->rets);
            n->outer = n->outer ? functions.at(n->outer) : nullptr; n->body = Tree(n->body);
        }
        for (auto old : from.structs) {
            auto n = structs.at(old); Header(*n); Generics(n->generics); Fields(n->fields);
        }
        for (auto old : from.enums) {
            auto n = enums.at(old); Header(*n); Generics(n->generics);
            for (auto &v : n->variants) { v.name = Text(v.name); v.line = Place(v.line); v.doc = Text(v.doc); Fields(v.fields); }
        }
        for (auto old : from.aliases) { auto n = aliases.at(old); Header(*n); n->type = Type(n->type); }
        for (auto old : from.topdecls) to.topdecls.push_back(Tree(old));
        for (auto old : from.globals) to.globals.push_back(Tree(old));
        // Registries use the destination file's role. An imported main has no
        // function-map entry even when its template was parsed at index zero.
        for (auto old : from.functions) {
            auto n = functions.at(old);
            if (!n->isnested && !(n->name == "main" && fileidx != 0)) to.NS(n->ns).functionmap[n->name].push_back(n);
        }
        for (auto old : from.structs) { auto n = structs.at(old); to.NS(n->ns).structmap[n->name] = n; }
        for (auto old : from.enums) { auto n = enums.at(old); to.NS(n->ns).enummap[n->name] = n; }
        for (auto old : from.aliases) { auto n = aliases.at(old); to.NS(n->ns).aliasmap[n->name] = n; }
        for (auto old : from.globals) { auto n = Tree(old); for (auto name : n->names) to.NS(n->ns).globalmap[name] = n; }
    }
};

}  // namespace goose
