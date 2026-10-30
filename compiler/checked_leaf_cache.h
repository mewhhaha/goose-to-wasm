// Cross-request semantic reuse for closed scalar expression functions. Entries
// contain no AST pointers, source views, or checked mutable compiler objects.
#pragma once
#include <stdexcept>

namespace goose {

namespace checked_leaf {
inline bool Scalar(const TypeExpr *t, bool allow_void = false) {
    return t && !t->ix && (t->kind == TY_BOOL || t->kind == TY_FLT ||
        (t->kind == TY_INT && t->intstorage != IS_VARINT) || (allow_void && t->kind == TY_VOID));
}
inline void Part(string &key, string_view value) {
    key += to_string(value.size()); key += ':'; key.append(value); key += ';';
}
inline void Number(string &key, int64_t value) { Part(key, to_string(value)); }
inline void TypeKey(string &key, const TypeExpr *t) {
    Number(key, t ? int(t->kind) : -1);
    if (!t) return;
    Number(key, t->kind == TY_INT ? int(t->intstorage) : t->kind == TY_FLT ? int(t->fltstorage) : 0);
    Number(key, t->cq); Number(key, t->aliasuse);
}
inline bool BinaryOperator(TType op) {
    switch (op) {
        case T_PLUS: case T_MINUS: case T_MUL: case T_DIV: case T_MOD:
        case T_BITAND: case T_BITOR: case T_XOR: case T_SHL: case T_SHR:
        case T_EQ: case T_NEQ: case T_LT: case T_GT: case T_LTEQ: case T_GTEQ:
        case T_ANDAND: case T_OROR: return true;
        default: return false;
    }
}

struct Source {
    static constexpr size_t MAX_NODES = 4096, MAX_TEXT = 65536, MAX_DEPTH = 128;
    string key;
    int fileidx = 0;
    vector<const Node *> nodes;
    unordered_map<const Node *, int> ordinals;
    struct Binding { const Call *syntax; SFunction *target; string contract; };
    vector<Binding> calls;
    bool caller = false;

    bool Walk(const Node *n, const SFunction &sf, size_t depth = 0) {
        if (!n) return true;
        if (depth > MAX_DEPTH || nodes.size() >= MAX_NODES || n->expansionbinding ||
            !n->expansiontrace.empty() || n->nftemp ||
            (n->line.line && n->line.fileidx != fileidx)) return false;
        if (ordinals.count(n)) return true;
        ordinals.emplace(n, int(nodes.size())); nodes.push_back(n);
        switch (n->nkind) {
            case NK_IntLit: {
                auto t = Is<IntLit>(n)->fixedtype;
                if (t && !Scalar(t)) return false;
                TypeKey(key, t); break;
            }
            case NK_FltLit: {
                auto t = Is<FltLit>(n)->fixedtype;
                if (t && !Scalar(t)) return false;
                TypeKey(key, t); break;
            }
            case NK_BoolLit: break;
            case NK_Ident: {
                auto id = Is<Ident>(n);
                if (id->name.find("::") != string_view::npos || !id->expansionerror.empty()) return false;
                if (none_of(sf.params.begin(), sf.params.end(), [&](auto &p) { return p.name == id->name; }))
                    return false;
                break;
            }
            case NK_Unary: {
                auto op = Is<Unary>(n)->op;
                if (op != T_MINUS && op != T_NOT && op != T_BITNOT) return false;
                break;
            }
            case NK_Binary: if (!BinaryOperator(Is<Binary>(n)->op)) return false; break;
            case NK_Block: {
                auto b = Is<Block>(n);
                if (b->brokenat >= 0 || b->expansionboundary) return false;
                break;
            }
            case NK_IfExpr: break;
            case NK_Return: if (!Is<Return>(n)->from.empty()) return false; break;
            // Explicit casts have deferred warning verdicts. Locals, calls,
            // globals, loops, references, and all other nodes recheck normally.
            default: return false;
        }
        auto ok = true;
        n->Children([&](Node *child) { if (!Walk(child, sf, depth + 1)) ok = false; });
        return ok;
    }
};

inline optional<Source> PrepareBase(const Ast &ast, const FnSpec *spec, bool walk_leaf) {
    auto sf = spec->sf;
    if (!sf || !sf->body || sf->broken || sf->brokensig || sf->isextern || sf->isnested ||
        sf->isthread || sf->isexport || sf->isrec || sf->issimd || sf->IsGeneric() ||
        !sf->has_rets || sf->rets.size() != 1 || !Scalar(sf->rets[0]) ||
        spec->body || spec->rounds || spec->lexparent || spec->isfunval ||
        !spec->litparams.empty() || !spec->bindings.empty() || !spec->fnvals.empty() ||
        !spec->narrowedenv.empty() || spec->argtypes.size() != sf->params.size() ||
        sf->line.line <= 0 || sf->end.line < sf->line.line ||
        sf->line.fileidx != sf->end.fileidx) return {};
    Source source; source.fileidx = sf->line.fileidx;
    if (source.fileidx < 0 || size_t(source.fileidx) >= ast.sources.size()) return {};
    Part(source.key, ast.sources[source.fileidx].first); Part(source.key, sf->qname);
    for (auto p : {sf->line.line, sf->line.col, sf->end.line, sf->end.col}) Number(source.key, p);
    TypeKey(source.key, sf->rets[0]);
    for (size_t i = 0; i < sf->params.size(); ++i) {
        auto &p = sf->params[i];
        if (p.defaultval || !Scalar(p.type) || !Scalar(spec->argtypes[i])) return {};
        Part(source.key, p.name); Number(source.key, p.isvar);
        TypeKey(source.key, p.type); TypeKey(source.key, spec->argtypes[i]);
    }
    if (walk_leaf && !source.Walk(sf->body, *sf)) return {};
    // Whole declaration lines are conservative exact key material. Keeping
    // locations in the key invalidates a declaration shifted by an edit.
    auto &text = *ast.sources[source.fileidx].second;
    size_t start = 0;
    for (int line = 1; line < sf->line.line; ++line) {
        auto next = text.find('\n', start);
        if (next == string::npos) return {};
        start = next + 1;
    }
    auto end = start;
    for (int line = sf->line.line; line <= sf->end.line; ++line) {
        auto next = text.find('\n', end);
        end = next == string::npos ? text.size() : next + 1;
    }
    if (end - start > Source::MAX_TEXT) return {};
    Part(source.key, string_view(text).substr(start, end - start));
    return source;
}
inline optional<Source> Prepare(const Ast &ast, const FnSpec *spec) { return PrepareBase(ast, spec, true); }

// This proof belongs to one request. It permits only straight-line i64
// callers, and revalidates their complete acyclic source graph before any
// cached body can cause dependent specializations to be checked.
struct GraphContext {
    const Ast *owner = nullptr;
    size_t function_count = 0, visited_nodes = 0;
    struct Memo { int state = 0; optional<Source> source; size_t height = 0; };
    unordered_map<SFunction *, Memo> memo;

    static bool I64(const Ast &ast, const TypeExpr *t) { return t == ast.inttypes[IS_I64]; }
    static bool Signature(const Ast &ast, const SFunction &sf) {
        if (!sf.has_rets || sf.rets.size() != 1 || !I64(ast, sf.rets[0])) return false;
        for (auto &p : sf.params) if (p.defaultval || !I64(ast, p.type)) return false;
        return true;
    }
    static string Contract(const Ast &ast, const SFunction &sf) {
        string key;
        Part(key, ast.sources.at(size_t(sf.line.fileidx)).first); Part(key, sf.qname);
        Number(key, sf.line.line); Number(key, sf.line.col);
        Number(key, int64_t(sf.params.size())); Number(key, sf.checkfree); Number(key, sf.isinline);
        for (auto &p : sf.params) Number(key, p.isvar);
        return key;
    }
    bool Add(Source &source, const Node *n, size_t depth) {
        if (!n || depth > Source::MAX_DEPTH || source.nodes.size() >= Source::MAX_NODES ||
            ++visited_nodes > Source::MAX_NODES || n->nftemp || n->expansionbinding ||
            !n->expansiontrace.empty() || (n->line.line && n->line.fileidx != source.fileidx)) return false;
        if (!source.ordinals.count(n)) {
            source.ordinals.emplace(n, int(source.nodes.size())); source.nodes.push_back(n);
        }
        return true;
    }
    bool Parameter(const Ident *id, const SFunction &sf) const {
        return id && id->name.find("::") == string_view::npos && id->expansionerror.empty() &&
            any_of(sf.params.begin(), sf.params.end(), [&](auto &p) { return p.name == id->name; });
    }
    bool Expression(Ast &ast, Source &source, const SFunction &sf, const Node *n,
                    size_t depth, size_t call_depth) {
        if (!Add(source, n, depth)) return false;
        switch (n->nkind) {
            case NK_IntLit: return !Is<IntLit>(n)->fixedtype || I64(ast, Is<IntLit>(n)->fixedtype);
            case NK_Ident: return Parameter(Is<Ident>(n), sf);
            case NK_Unary: {
                auto u = Is<Unary>(n);
                return u->op == T_MINUS && Expression(ast, source, sf, u->child, depth + 1, call_depth);
            }
            case NK_Binary: {
                auto b = Is<Binary>(n);
                return (b->op == T_PLUS || b->op == T_MINUS || b->op == T_MUL) &&
                    Expression(ast, source, sf, b->left, depth + 1, call_depth) &&
                    Expression(ast, source, sf, b->right, depth + 1, call_depth);
            }
            case NK_Call: {
                auto c = Is<Call>(n); auto id = Is<Ident>(c->callee);
                if (!id || Parameter(id, sf) || !id->expansionerror.empty() ||
                    LookupBuiltin(GlobalLeaf(id->name)) || c->implicit || !c->tyargs.empty() || c->trailing ||
                    !Add(source, id, depth + 1)) return false;
                auto targets = ast.LookupFunctions(id->name, id->ns);
                if (targets.size() != 1 || c->args.size() != targets[0]->params.size()) return false;
                for (auto arg : c->args)
                    if (!Parameter(Is<Ident>(arg), sf) || !Add(source, arg, depth + 1)) return false;
                if (!Ready(ast, targets[0], call_depth + 1)) return false;
                auto contract = Contract(ast, *targets[0]); Part(source.key, contract);
                source.calls.push_back({c, targets[0], std::move(contract)});
                return true;
            }
            default: return false;
        }
    }
    bool Ready(Ast &ast, SFunction *sf, size_t depth = 0) {
        if (depth >= Source::MAX_DEPTH) return false;
        if (auto it = memo.find(sf); it != memo.end())
            return it->second.state == 2 && depth + it->second.height <= Source::MAX_DEPTH;
        if (memo.size() >= 256) return false;
        memo.emplace(sf, Memo {1, {}});
        FnSpec fake; fake.sf = sf;
        for (auto &p : sf->params) fake.argtypes.push_back(p.type);
        if (!Signature(ast, *sf)) { memo.at(sf).state = 3; return false; }
        if (auto leaf = Prepare(ast, &fake)) {
            visited_nodes += leaf->nodes.size();
            if (visited_nodes > Source::MAX_NODES) { memo.at(sf).state = 3; return false; }
            memo.at(sf) = {2, std::move(leaf), 1}; return true;
        }
        auto source = PrepareBase(ast, &fake, false);
        if (!source || !Add(*source, sf->body, 0)) { memo.at(sf).state = 3; return false; }
        auto body = sf->body;
        const Node *expression = nullptr;
        if (body->brokenat < 0 && !body->expansionboundary) {
            if (body->stmts.empty()) expression = body->tail;
            else if (!body->tail && body->stmts.size() == 1) {
                auto ret = Is<Return>(body->stmts[0]);
                if (ret && ret->from.empty() && ret->vals.size() == 1 && Add(*source, ret, 1))
                    expression = ret->vals[0];
            }
        }
        if (!expression || !Expression(ast, *source, *sf, expression, 2, depth) || source->calls.empty()) {
            memo.at(sf).state = 3; return false;
        }
        size_t height = 1;
        for (auto &binding : source->calls) height = max(height, memo.at(binding.target).height + 1);
        source->caller = true; source->key.insert(0, "scalar-call-v1;");
        memo.at(sf) = {2, std::move(source), height};
        return depth + height <= Source::MAX_DEPTH;
    }
    optional<Source> PrepareCaller(Ast &ast, const FnSpec *spec) {
        // Typechecking can add nested declarations. Never reuse an older
        // function-lookup proof after the declaration table has grown.
        if (owner != &ast || function_count != ast.functions.size()) {
            memo.clear(); visited_nodes = 0; owner = &ast; function_count = ast.functions.size();
        }
        if (!Signature(ast, *spec->sf) || !PrepareBase(ast, spec, false)) return {};
        for (auto t : spec->argtypes) if (!I64(ast, t)) return {};
        if (!Ready(ast, spec->sf)) return {};
        return memo.at(spec->sf).source;
    }
};

struct ScalarType {
    TypeKind kind;
    int storage = 0;
    bool cq = false, aliasuse = false;
    Line line;
};
struct FrozenNode {
    NodeKind kind;
    Line line, end;
    int type = -1, fixed = -1, cast_type = -1, cast_to = -1;
    int origin = -1, param = -1, op = 0;
    uint64_t bits = 0;
    bool uns = false, synth = false, litfloat = false, flexint = false, flat = false;
    bool unchecked = false, implicit = false;
    int call_result = -1, firstdefault = 0;
    string text, name, ns, contract;
    vector<int> children;
};
struct FrozenLeaf {
    vector<ScalarType> types;
    vector<FrozenNode> nodes;
    vector<int> params;
    int body = -1, result = -1;
    size_t bytes = 0;
    uint64_t touched = 0;
};

inline bool EmptyEffects(const FnSpec &s, bool allow_edges = false);

struct Freezer {
    const FnSpec &spec;
    const Source &source;
    FrozenLeaf leaf;
    unordered_map<const TypeExpr *, int> types;
    unordered_map<const Node *, int> nodes;

    [[noreturn]] static void Refuse() { throw runtime_error("ineligible checked leaf"); }
    int Type(const TypeExpr *t) {
        if (!t) return -1;
        if (!Scalar(t, true) || (t->line.line && t->line.fileidx != source.fileidx)) Refuse();
        if (auto it = types.find(t); it != types.end()) return it->second;
        auto index = int(leaf.types.size()); types.emplace(t, index);
        leaf.types.push_back({t->kind, t->kind == TY_INT ? int(t->intstorage) :
            t->kind == TY_FLT ? int(t->fltstorage) : 0, t->cq, t->aliasuse, t->line});
        return index;
    }
    int Tree(const Node *n, size_t depth = 0, bool callee = false) {
        if (!n) return -1;
        if (depth > Source::MAX_DEPTH || leaf.nodes.size() >= Source::MAX_NODES ||
            n->nftemp || n->expansionbinding || !n->expansiontrace.empty() ||
            (n->line.line && n->line.fileidx != source.fileidx) ||
            (n->end.line && n->end.fileidx != source.fileidx)) Refuse();
        if (auto it = nodes.find(n); it != nodes.end()) return it->second;
        auto index = int(leaf.nodes.size()); nodes.emplace(n, index); leaf.nodes.emplace_back();
        FrozenNode f; f.kind = n->nkind; f.line = n->line; f.end = n->end; f.type = Type(n->exprtype);
        if (n->origin) {
            auto it = source.ordinals.find(n->origin);
            if (it == source.ordinals.end()) Refuse();
            f.origin = it->second;
        }
        switch (n->nkind) {
            case NK_IntLit: {
                auto x = Is<IntLit>(n); memcpy(&f.bits, &x->val, sizeof(f.bits));
                f.uns = x->uns; f.text = string(x->text); f.fixed = Type(x->fixedtype); break;
            }
            case NK_FltLit: {
                auto x = Is<FltLit>(n); memcpy(&f.bits, &x->val, sizeof(f.bits));
                f.text = string(x->text); f.fixed = Type(x->fixedtype); break;
            }
            case NK_BoolLit: f.bits = Is<BoolLit>(n)->val; break;
            case NK_Ident: {
                auto x = Is<Ident>(n);
                if (callee) {
                    if (x->vdef || x->fnref || !x->expansionerror.empty()) Refuse();
                    f.param = -2; f.name = string(x->name); f.ns = string(x->ns); break;
                }
                auto it = find(spec.params.begin(), spec.params.end(), x->vdef);
                if (it == spec.params.end() || x->fnref || !x->expansionerror.empty()) Refuse();
                f.param = int(it - spec.params.begin()); f.name = string(x->name); f.ns = string(x->ns); break;
            }
            case NK_Unary: {
                auto x = Is<Unary>(n);
                if (x->op != T_MINUS && x->op != T_NOT && x->op != T_BITNOT) Refuse();
                f.op = x->op; f.synth = x->synth; f.litfloat = x->litfloat; f.flexint = x->flexint; break;
            }
            case NK_Binary: {
                auto x = Is<Binary>(n);
                if (!BinaryOperator(x->op) || !x->rightkills.empty() || x->specidx || x->nonneg) Refuse();
                f.op = x->op; f.litfloat = x->litfloat; f.flexint = x->flexint; break;
            }
            case NK_Block: {
                auto x = Is<Block>(n);
                if (x->brokenat >= 0 || x->expansionboundary) Refuse();
                for (auto child : x->stmts) f.children.push_back(Tree(child, depth + 1));
                f.children.push_back(Tree(x->tail, depth + 1)); break;
            }
            case NK_IfExpr: f.flat = Is<IfExpr>(n)->flat; break;
            case NK_Return: {
                auto x = Is<Return>(n);
                if (!x->from.empty() || x->target != spec.sf || x->targetspec != &spec) Refuse();
                f.ns = string(x->ns); break;
            }
            case NK_AsCast: {
                auto x = Is<AsCast>(n);
                if (!x->implicit || x->nobc) Refuse();
                f.cast_type = Type(x->type); f.cast_to = Type(x->totype);
                f.unchecked = x->unchecked; f.implicit = x->implicit; break;
            }
            case NK_Call: {
                auto x = Is<Call>(n);
                auto binding = find_if(source.calls.begin(), source.calls.end(),
                    [&](auto &b) { return b.syntax == n->Origin(); });
                if (binding == source.calls.end() || !x->spec || x->spec->sf != binding->target ||
                    !EmptyEffects(*x->spec, true) || !x->dispatch.empty() || x->dispatcharg != -1 ||
                    x->builtin != -1 || x->fvbody || x->defaultinit || !x->fvparams.empty() ||
                    !x->fvremap.empty() || !x->fmtspecs.empty() || !x->fmtcontexts.empty() ||
                    !x->tyargs.empty() || x->trailing || x->implicit || x->ndefaults ||
                    x->poolcheck || x->qtype || x->shaderblob || x->rettypes.size() != 1) Refuse();
                f.contract = binding->contract; f.call_result = Type(x->rettypes[0]);
                f.firstdefault = x->firstdefault;
                f.children.push_back(Tree(x->callee, depth + 1, true));
                for (auto arg : x->args) f.children.push_back(Tree(arg, depth + 1));
                break;
            }
            default: Refuse();
        }
        if (n->nkind != NK_Block && n->nkind != NK_Call)
            n->Children([&](Node *child) { f.children.push_back(Tree(child, depth + 1)); });
        leaf.nodes[index] = std::move(f);
        return index;
    }
};

inline bool EmptyEffects(const FnSpec &s, bool allow_edges) {
    auto &r = s.record;
    if (s.inprogress || s.failed || s.incycle || s.cyclelink || s.prev || s.stale || s.storesout ||
        s.relnamedresult || s.rounds != 1 || !s.retsknown || s.rets.size() != 1 ||
        !Scalar(s.rets[0]) || !s.envreads.empty() || !s.envexits.empty() || !s.outerexits.empty() ||
        !s.litadapts.empty() || !s.litflows.empty() || !s.needs.empty() || (!allow_edges && !s.neededges.empty()) ||
        !s.cyclemembers.empty() || s.classroots.size() != 1 || s.classroots[0] ||
        !r.mayreturn || r.eventstart != r.eventend || !r.relativestores.empty() ||
        !r.reboundoptionals.empty() || !r.shrinkexternals.empty() || !r.shrinkparams.empty() ||
        !r.shrinkexternalbounds.empty() || !r.shrinkparambounds.empty() || !r.liveshrinks.empty() ||
        !r.growexternals.empty() || !r.growparams.empty() || !r.classevents.empty() ||
        !r.shrinkorders.empty() || r.retroots.size() != 1) return false;
    auto &rr = r.retroots[0];
    if (!rr.alts.alts.empty() || rr.alts.unknown || !rr.writable || rr.byteview || rr.freshview || rr.set)
        return false;
    for (auto v : s.params)
        if (!Scalar(v->type) || v->ownerspec != &s || !v->isparam || v->isglobal || v->captured ||
            v->unsized || v->nonneg || v->constlit || v->constflt || v->nonnegfrom || v->constfrom ||
            v->nonneguse || v->constuse || v->markof || v->narrowed || v->refrootknown ||
            !v->contents.alts.empty() || !v->ref.alts.empty() || v->heldslice || v->heldholder)
            return false;
    return true;
}

struct Importer {
    Ast &ast;
    FnSpec &spec;
    const Source &source;
    const FrozenLeaf &leaf;
    vector<TypeExpr *> types;
    vector<Node *> nodes;
    vector<pair<Call *, string>> calls;
    Line Place(Line l) const { if (l.line) l.fileidx = source.fileidx; return l; }
    TypeExpr *Type(int i) {
        if (i < 0) return nullptr;
        if (types.at(size_t(i))) return types[size_t(i)];
        auto &f = leaf.types.at(size_t(i));
        TypeExpr *t;
        if (!f.line.line && !f.cq && !f.aliasuse)
            t = f.kind == TY_INT ? ast.inttypes[f.storage] : f.kind == TY_FLT ? ast.flttypes[f.storage] :
                f.kind == TY_BOOL ? ast.booltype : ast.voidtype;
        else {
            t = ast.NewType(f.kind, Place(f.line)); t->cq = f.cq; t->aliasuse = f.aliasuse;
            if (f.kind == TY_INT) t->intstorage = IntStorage(f.storage);
            if (f.kind == TY_FLT) t->fltstorage = FltStorage(f.storage);
        }
        return types[size_t(i)] = t;
    }
    Node *Tree(int index) {
        if (index < 0) return nullptr;
        if (nodes.at(size_t(index))) return nodes[size_t(index)];
        auto &f = leaf.nodes.at(size_t(index)); auto l = Place(f.line);
        auto child = [&](size_t i) { return Tree(f.children.at(i)); };
        Node *n = nullptr;
        switch (f.kind) {
            case NK_IntLit: {
                int64_t bits; memcpy(&bits, &f.bits, sizeof(bits));
                auto x = ast.New<IntLit>(l, bits, ast.Intern(f.text), f.uns); x->fixedtype = Type(f.fixed); n = x; break;
            }
            case NK_FltLit: {
                double bits; memcpy(&bits, &f.bits, sizeof(bits));
                auto x = ast.New<FltLit>(l, bits, ast.Intern(f.text)); x->fixedtype = Type(f.fixed); n = x; break;
            }
            case NK_BoolLit: n = ast.New<BoolLit>(l, bool(f.bits)); break;
            case NK_Ident: {
                auto x = ast.New<Ident>(l, ast.Intern(f.name), ast.Intern(f.ns));
                if (f.param >= 0) x->vdef = spec.params.at(size_t(f.param));
                else if (f.param != -2) throw runtime_error("invalid frozen scalar identifier");
                n = x; break;
            }
            case NK_Unary: {
                auto x = ast.New<Unary>(l, TType(f.op), child(0));
                x->synth = f.synth; x->litfloat = f.litfloat; x->flexint = f.flexint; n = x; break;
            }
            case NK_Binary: {
                // Dependent calls must be ensured in source evaluation order.
                auto left = child(0), right = child(1);
                auto x = ast.New<Binary>(l, TType(f.op), left, right);
                x->litfloat = f.litfloat; x->flexint = f.flexint; n = x; break;
            }
            case NK_Block: {
                auto x = ast.New<Block>(l);
                for (size_t i = 0; i + 1 < f.children.size(); ++i) x->stmts.push_back(child(i));
                x->tail = child(f.children.size() - 1); n = x; break;
            }
            case NK_IfExpr: {
                auto x = ast.New<IfExpr>(l, child(0), static_cast<Block *>(child(1)),
                    f.children.size() > 2 ? child(2) : nullptr); x->flat = f.flat; n = x; break;
            }
            case NK_Return: {
                auto x = ast.New<Return>(l);
                for (auto i : f.children) x->vals.push_back(Tree(i));
                x->ns = ast.Intern(f.ns); x->target = spec.sf; x->targetspec = &spec; n = x; break;
            }
            case NK_AsCast: {
                auto x = ast.New<AsCast>(l, child(0), Type(f.cast_type), f.unchecked);
                x->implicit = f.implicit; x->totype = Type(f.cast_to); n = x; break;
            }
            case NK_Call: {
                auto x = ast.New<Call>(l, child(0));
                for (size_t i = 1; i < f.children.size(); ++i) x->args.push_back(child(i));
                x->firstdefault = f.firstdefault; x->rettypes = {Type(f.call_result)};
                calls.push_back({x, f.contract}); n = x; break;
            }
            default: throw runtime_error("invalid frozen leaf node");
        }
        n->exprtype = Type(f.type); n->end = Place(f.end);
        n->origin = f.origin < 0 ? nullptr : source.nodes.at(size_t(f.origin));
        nodes[size_t(index)] = n; return n;
    }
    void RunBody() {
        if (spec.params.size() != leaf.params.size() || spec.rets.size() != 1)
            throw runtime_error("scalar cache prologue mismatch");
        for (size_t i = 0; i < leaf.params.size(); ++i) {
            types.at(size_t(leaf.params[i])) = spec.params[i]->type;
        }
        types.at(size_t(leaf.result)) = spec.rets[0];
        spec.body = static_cast<Block *>(Tree(leaf.body));
        spec.record.retroots.resize(1);
    }
};
} // namespace checked_leaf

struct CheckedLeafCache {
    size_t byte_limit, entry_limit, estimated_bytes = 0;
    uint64_t clock = 0;
    int64_t hits = 0, leaf_hits = 0, caller_hits = 0, misses = 0, stored = 0, refused = 0, evictions = 0;
    map<string, checked_leaf::FrozenLeaf> entries;
    explicit CheckedLeafCache(size_t bytes = 16 * 1024 * 1024, size_t count = 256)
        : byte_limit(bytes), entry_limit(count) {}
    void BeginRequest() { hits = leaf_hits = caller_hits = misses = stored = refused = evictions = 0; }
    void Clear() { entries.clear(); estimated_bytes = 0; }
    template<typename F> bool RestoreBody(Ast &ast, FnSpec &spec, const checked_leaf::Source &source, F ensure) {
        auto it = entries.find(source.key);
        if (it == entries.end()) { misses++; return false; }
        vector<pair<Call *, string>> calls;
        {
            auto &leaf = it->second; leaf.touched = ++clock;
            checked_leaf::Importer importer {ast, spec, source, leaf,
                vector<TypeExpr *>(leaf.types.size()), vector<Node *>(leaf.nodes.size())};
            importer.RunBody(); calls = std::move(importer.calls);
        }
        // Import everything before dependent checks can evict this entry.
        // From here on, only request-owned allocations and strings are used.
        vector<SFunction *> targets;
        for (auto &[call, contract] : calls) {
            auto id = Is<Ident>(call->callee); auto found = ast.LookupFunctions(id->name, id->ns);
            if (found.size() != 1 || checked_leaf::GraphContext::Contract(ast, *found[0]) != contract) {
                spec.body = nullptr; return false;
            }
            targets.push_back(found[0]);
        }
        for (size_t i = 0; i < calls.size(); ++i)
            if (!ensure(calls[i].first, targets[i])) { spec.body = nullptr; return false; }
        hits++; if (source.caller) caller_hits++; else leaf_hits++;
        return true;
    }
    void Store(const FnSpec &spec, const checked_leaf::Source &source, bool diagnostics) {
        if (diagnostics || !entry_limit || !checked_leaf::EmptyEffects(spec)) { refused++; return; }
        if (entries.count(source.key)) return;
        checked_leaf::Freezer freezer {spec, source};
        try {
            for (auto p : spec.params) freezer.leaf.params.push_back(freezer.Type(p->type));
            freezer.leaf.result = freezer.Type(spec.rets[0]);
            freezer.leaf.body = freezer.Tree(spec.body);
        } catch (const runtime_error &) { refused++; return; }
        auto &leaf = freezer.leaf;
        leaf.bytes = sizeof(leaf) + source.key.capacity() + 512 +
            leaf.types.capacity() * sizeof(checked_leaf::ScalarType) + leaf.params.capacity() * sizeof(int) +
            leaf.nodes.capacity() * sizeof(checked_leaf::FrozenNode);
        for (auto &n : leaf.nodes)
            leaf.bytes += n.text.capacity() + n.name.capacity() + n.ns.capacity() + n.contract.capacity() +
                          n.children.capacity() * sizeof(int);
        if (leaf.bytes > byte_limit) { refused++; return; }
        while (entries.size() >= entry_limit || estimated_bytes > byte_limit - leaf.bytes) {
            auto oldest = entries.begin();
            for (auto it = entries.begin(); it != entries.end(); ++it)
                if (it->second.touched < oldest->second.touched) oldest = it;
            estimated_bytes -= oldest->second.bytes; entries.erase(oldest); evictions++;
        }
        leaf.touched = ++clock; estimated_bytes += leaf.bytes;
        entries.emplace(source.key, std::move(leaf)); stored++;
    }
};
inline thread_local CheckedLeafCache *active_checked_leaf_cache = nullptr;
inline thread_local checked_leaf::GraphContext *active_checked_scalar_graph = nullptr;
inline optional<checked_leaf::Source> PrepareCheckedScalar(Ast &ast, const FnSpec *spec) {
    if (!active_checked_leaf_cache) return {};
    if (auto leaf = checked_leaf::Prepare(ast, spec)) return leaf;
    return active_checked_scalar_graph ? active_checked_scalar_graph->PrepareCaller(ast, spec) :
                                        optional<checked_leaf::Source>();
}
struct CheckedLeafCacheScope {
    CheckedLeafCache *previous;
    checked_leaf::GraphContext *previous_graph;
    checked_leaf::GraphContext graph;
    explicit CheckedLeafCacheScope(CheckedLeafCache *cache, bool callers = false)
        : previous(active_checked_leaf_cache), previous_graph(active_checked_scalar_graph) {
        active_checked_leaf_cache = cache;
        active_checked_scalar_graph = cache && callers ? &graph : nullptr;
    }
    ~CheckedLeafCacheScope() { active_checked_leaf_cache = previous; active_checked_scalar_graph = previous_graph; }
};

} // namespace goose
