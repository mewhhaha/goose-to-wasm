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

inline optional<Source> Prepare(const Ast &ast, const FnSpec *spec) {
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
    if (!source.Walk(sf->body, *sf)) return {};
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
    string text, name, ns;
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
    int Tree(const Node *n, size_t depth = 0) {
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
            default: Refuse();
        }
        if (n->nkind != NK_Block)
            n->Children([&](Node *child) { f.children.push_back(Tree(child, depth + 1)); });
        leaf.nodes[index] = std::move(f);
        return index;
    }
};

inline bool EmptyEffects(const FnSpec &s) {
    auto &r = s.record;
    if (s.inprogress || s.failed || s.incycle || s.cyclelink || s.prev || s.stale || s.storesout ||
        s.relnamedresult || s.rounds != 1 || !s.retsknown || s.rets.size() != 1 ||
        !Scalar(s.rets[0]) || !s.envreads.empty() || !s.envexits.empty() || !s.outerexits.empty() ||
        !s.litadapts.empty() || !s.litflows.empty() || !s.needs.empty() || !s.neededges.empty() ||
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
                x->vdef = spec.params.at(size_t(f.param)); n = x; break;
            }
            case NK_Unary: {
                auto x = ast.New<Unary>(l, TType(f.op), child(0));
                x->synth = f.synth; x->litfloat = f.litfloat; x->flexint = f.flexint; n = x; break;
            }
            case NK_Binary: {
                auto x = ast.New<Binary>(l, TType(f.op), child(0), child(1));
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
            default: throw runtime_error("invalid frozen leaf node");
        }
        n->exprtype = Type(f.type); n->end = Place(f.end);
        n->origin = f.origin < 0 ? nullptr : source.nodes.at(size_t(f.origin));
        nodes[size_t(index)] = n; return n;
    }
    void Run(size_t event, int depth) {
        for (size_t i = 0; i < leaf.params.size(); ++i) {
            auto &p = spec.sf->params.at(i);
            auto v = ast.NewVarDef(); v->name = p.name; v->type = Type(leaf.params[i]);
            v->line = p.line.line ? p.line : spec.sf->line; v->isvar = p.isvar; v->isparam = true;
            v->assigned = v->maybeassigned = true; v->ownerspec = &spec; v->depth = depth + 1;
            spec.params.push_back(v);
        }
        spec.rets = {Type(leaf.result)}; spec.retsknown = true;
        spec.record.retroots.resize(1); spec.record.eventstart = spec.record.eventend = event;
        spec.classroots.resize(1, nullptr); spec.rounds = 1;
        spec.body = static_cast<Block *>(Tree(leaf.body));
    }
};
} // namespace checked_leaf

struct CheckedLeafCache {
    size_t byte_limit, entry_limit, estimated_bytes = 0;
    uint64_t clock = 0;
    int64_t hits = 0, misses = 0, stored = 0, refused = 0, evictions = 0;
    map<string, checked_leaf::FrozenLeaf> entries;
    explicit CheckedLeafCache(size_t bytes = 16 * 1024 * 1024, size_t count = 256)
        : byte_limit(bytes), entry_limit(count) {}
    void BeginRequest() { hits = misses = stored = refused = evictions = 0; }
    void Clear() { entries.clear(); estimated_bytes = 0; }
    bool Restore(Ast &ast, FnSpec &spec, const checked_leaf::Source &source, size_t event, int depth) {
        auto it = entries.find(source.key);
        if (it == entries.end()) { misses++; return false; }
        auto &leaf = it->second;
        checked_leaf::Importer importer {ast, spec, source, leaf,
            vector<TypeExpr *>(leaf.types.size()), vector<Node *>(leaf.nodes.size())};
        importer.Run(event, depth); leaf.touched = ++clock; hits++; return true;
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
            leaf.bytes += n.text.capacity() + n.name.capacity() + n.ns.capacity() + n.children.capacity() * sizeof(int);
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
struct CheckedLeafCacheScope {
    CheckedLeafCache *previous;
    explicit CheckedLeafCacheScope(CheckedLeafCache *cache) : previous(active_checked_leaf_cache) {
        active_checked_leaf_cache = cache;
    }
    ~CheckedLeafCacheScope() { active_checked_leaf_cache = previous; }
};

} // namespace goose
