#pragma once
namespace goose::direct_wasm {

// A bounded proof for byte stencils. This temporary expression graph is never
// installed in the AST: a failed proof leaves the ordinary scalar loop intact.
struct ByteStencilProof {
    struct Value {
        enum Kind { Literal, Variable, Binary, Load, Not, Select } kind;
        int64_t number = 0;
        VarDef *variable = nullptr;
        TType op = T_PLUS;
        int left = -1, right = -1, third = -1;
    };
    Function &f;
    vector<Value> values;
    unordered_map<VarDef *, int> env;
    int budget = 512, helpers = 0;
    int store = -1, result = -1;
    SFunction *target = nullptr;
    TypeExpr *return_type = nullptr;
    bool helper = false;
    explicit ByteStencilProof(Function &function) : f(function) {}
    int Add(Value value) { values.push_back(value); return int(values.size() - 1); }
    int Literal(int64_t number) { Value value { Value::Literal }; value.number = number; return Add(value); }
    bool Private(VarDef *v) {
        return v && !v->isglobal && !v->captured && !v->reusable && !f.addressed.count(f.Resolve(v));
    }
    bool Scalar(TypeExpr *t) { return t && !t->ix && ((IsIntT(t) && t->intstorage == IS_I64) || t->kind == TY_BOOL); }
    bool Byte(TypeExpr *t) { return t && !t->ix && IsIntT(t) && t->intstorage == IS_U8; }
    bool View(TypeExpr *t) { return t && t->kind == TY_SLICE && Byte(t->sub); }
    bool Plain(TypeExpr *t) { return Scalar(t) || Byte(t) || View(t); }
    bool Same(TypeExpr *a, TypeExpr *b) { return Plain(a) && Plain(b) && SameFunctionValueType(a, b); }
    int Binary(TType op, int a, int b) {
        if (a < 0 || b < 0) return -1;
        if (values[a].kind == Value::Literal && values[b].kind == Value::Literal) {
            auto x = values[a].number, y = values[b].number;
            switch (op) {
                case T_PLUS: return Literal(bit_cast<int64_t>(uint64_t(x) + uint64_t(y)));
                case T_MINUS: return Literal(bit_cast<int64_t>(uint64_t(x) - uint64_t(y)));
                case T_MUL: return Literal(bit_cast<int64_t>(uint64_t(x) * uint64_t(y)));
                case T_EQ: return Literal(x == y);
                case T_NEQ: return Literal(x != y);
                case T_LT: return Literal(x < y);
                case T_LTEQ: return Literal(x <= y);
                case T_GT: return Literal(x > y);
                case T_GTEQ: return Literal(x >= y);
                case T_ANDAND: return Literal(x && y);
                case T_OROR: return Literal(x || y);
                default: return -1;
            }
        }
        if (op == T_PLUS && values[a].kind == Value::Literal && !values[a].number) return b;
        if (op == T_PLUS && values[b].kind == Value::Literal && !values[b].number) return a;
        Value value { Value::Binary }; value.op = op; value.left = a; value.right = b; return Add(value);
    }
    int Expr(Node *n) {
        if (!n || --budget < 0) return -1;
        if (auto literal = Is<IntLit>(n)) {
            if (literal->uns || !IsIntT(n->exprtype) || (!Scalar(n->exprtype) && !Byte(n->exprtype)) ||
                (Byte(n->exprtype) && (literal->val < 0 || literal->val > 255))) return -1;
            return Literal(literal->val);
        }
        if (auto literal = Is<BoolLit>(n)) {
            if (!n->exprtype || n->exprtype->kind != TY_BOOL) return -1;
            return Literal(literal->val);
        }
        if (auto id = Is<Ident>(n)) {
            if (!id->vdef || !Same(n->exprtype, id->vdef->type)) return -1;
            if (auto found = env.find(id->vdef); found != env.end()) return found->second;
            if (!Private(id->vdef)) return -1;
            auto v = f.Resolve(id->vdef);
            auto found = f.vars.find(v);
            if (found == f.vars.end() || found->second.kind != Slot::LOCAL || !Same(n->exprtype, found->second.type)) return -1;
            if (auto constant = f.constant_slots.find(found->second.index); constant != f.constant_slots.end())
                return Literal(constant->second);
            auto type = found->second.type;
            if (!Scalar(type) && !View(type)) return -1;
            Value value { Value::Variable }; value.variable = v; return Add(value);
        }
        if (auto binary = Is<goose::Binary>(n)) {
            if (!Scalar(n->exprtype) || !Plain(binary->left->exprtype) || !Plain(binary->right->exprtype)) return -1;
            auto left = binary->left->exprtype, right = binary->right->exprtype;
            auto wide = [&](TypeExpr *type) { return Scalar(type) && IsIntT(type); };
            switch (binary->op) {
                case T_PLUS: case T_MINUS: case T_MUL: case T_MOD:
                    if (!wide(left) || !wide(n->exprtype) || (!wide(right) && !Byte(right))) return -1;
                    break;
                case T_EQ: case T_NEQ: case T_LT: case T_LTEQ: case T_GT: case T_GTEQ:
                    if (n->exprtype->kind != TY_BOOL ||
                        (!Same(left, right) && !(wide(left) && Byte(right)))) return -1;
                    break;
                case T_ANDAND: case T_OROR:
                    if (left->kind != TY_BOOL || right->kind != TY_BOOL || n->exprtype->kind != TY_BOOL) return -1;
                    break;
                default: return -1;
            }
            auto a = Expr(binary->left), b = Expr(binary->right);
            return Binary(binary->op, a, b);
        }
        if (auto unary = Is<Unary>(n)) {
            if (!Scalar(n->exprtype) || !Same(n->exprtype, unary->child->exprtype)) return -1;
            auto a = Expr(unary->child); if (a < 0) return -1;
            if (unary->op == T_MINUS && IsIntT(n->exprtype)) return Binary(T_MINUS, Literal(0), a);
            if (unary->op != T_NOT || n->exprtype->kind != TY_BOOL) return -1;
            if (values[a].kind == Value::Literal) return Literal(!values[a].number);
            Value value { Value::Not }; value.left = a; return Add(value);
        }
        if (auto index = Is<Index>(n)) {
            auto type = index->obj->exprtype;
            bool byte_result = Byte(n->exprtype) || (Scalar(n->exprtype) && IsIntT(n->exprtype));
            if (!View(type) || !byte_result || !Scalar(index->idx->exprtype)) return -1;
            auto a = Expr(index->obj), b = Expr(index->idx);
            if (a < 0 || b < 0 || values[a].kind != Value::Variable) return -1;
            Value value { Value::Load }; value.left = a; value.right = b; return Add(value);
        }
        if (auto block = Is<goose::Block>(n)) {
            if (!block->stmts.empty()) return -1;
            return Expr(block->tail);
        }
        if (auto branch = Is<IfExpr>(n)) {
            if ((!Scalar(n->exprtype) && !Byte(n->exprtype)) || !branch->cond->exprtype ||
                branch->cond->exprtype->kind != TY_BOOL) return -1;
            auto condition = Expr(branch->cond), yes = Expr(branch->thenb), no = Expr(branch->elseb);
            if (condition < 0 || yes < 0 || no < 0) return -1;
            Value value { Value::Select }; value.left = condition; value.right = yes; value.third = no; return Add(value);
        }
        goose::Block *body = nullptr;
        SFunction *sf = nullptr;
        auto saved = env;
        if (auto call = Is<Call>(n)) {
            auto spec = call->spec;
            if (helpers || !spec || spec->lexparent || call->builtin >= 0 || call->fvbody || call->defaultinit ||
                !call->dispatch.empty() || !call->fvremap.empty() || !f.c.captures[spec].empty() || !f.c.Leaf(spec)) return -1;
            auto args = call->ValueArgNodes();
            if (args.size() != spec->params.size() || spec->rets.size() != 1 || !Scalar(spec->rets[0])) return -1;
            vector<int> actuals;
            for (size_t i = 0; i < args.size(); i++) {
                auto type = spec->params[i]->type;
                if ((!Scalar(type) && !View(type)) || !Same(type, args[i]->exprtype)) return -1;
                auto value = Expr(args[i]); if (value < 0) return -1; actuals.push_back(value);
            }
            if (helpers || !Same(n->exprtype, spec->rets[0])) return -1;
            for (size_t i = 0; i < actuals.size(); i++) env[spec->params[i]] = actuals[i];
            body = spec->body; sf = spec->sf;
        } else if (auto inlined = Is<InlineBlock>(n)) {
            auto spec = inlined->spec;
            if (helpers || !spec || spec->lexparent || !f.c.captures[spec].empty() || !Scalar(n->exprtype) ||
                spec->rets.size() != 1 || !Same(n->exprtype, spec->rets[0])) return -1;
            body = inlined->body; sf = inlined->sf;
        } else return -1;
        helpers++; helper = true; target = sf; return_type = n->exprtype;
        auto flow = Block(body);
        auto value = result;
        if (!flow && body->tail) value = Expr(body->tail);
        helper = false; target = nullptr; return_type = nullptr; result = -1; env = std::move(saved);
        if (flow < 0) return -1;
        return value;
    }
    // 0: fallthrough, 1: continue, 2: return, -1: proof failure.
    int Statement(Node *n) {
        if (!n || --budget < 0) return -1;
        if (auto declaration = Is<VarDecl>(n)) {
            if (declaration->byref || declaration->isglobal || declaration->defs.size() != 1 || declaration->inits.size() != 1 ||
                !Private(declaration->defs[0])) return -1;
            auto type = declaration->defs[0]->type;
            if ((!Scalar(type) && !(declaration->inline_arg && View(type))) ||
                !Same(type, declaration->inits[0]->exprtype)) return -1;
            auto value = Expr(declaration->inits[0]); if (value < 0) return -1;
            env[declaration->defs[0]] = value; return 0;
        }
        if (auto assignment = Is<Assign>(n)) {
            if (assignment->pointee) return -1;
            if (auto id = Is<Ident>(assignment->lval)) {
                auto found = env.find(id->vdef);
                if (found == env.end() || !Private(id->vdef) || !Scalar(id->exprtype)) return -1;
                auto previous = found->second;
                auto type = id->exprtype, from = assignment->rhs->exprtype;
                if (!Same(type, from) && !(Scalar(type) && IsIntT(type) && Byte(from))) return -1;
                auto rhs = Expr(assignment->rhs); if (rhs < 0) return -1;
                if (assignment->op == T_PLUSEQ) rhs = Binary(T_PLUS, previous, rhs);
                else if (assignment->op != T_ASSIGN) return -1;
                env[id->vdef] = rhs; return 0;
            }
            if (helper || store >= 0 || assignment->op != T_ASSIGN) return -1;
            store = Expr(assignment->lval); result = Expr(assignment->rhs);
            if (store < 0 || result < 0) return -1;
            return 0;
        }
        if (auto loop = Is<ForLoop>(n)) {
            if (!helper || loop->byref || loop->idxdef || !Private(loop->vdef) || !Scalar(loop->vdef->type)) return -1;
            int a = Literal(0), b = -1;
            if (auto range = Is<RangeExpr>(loop->iter)) { a = Expr(range->lo); b = Expr(range->hi); }
            else if (loop->iterkind == IK_COUNT) b = Expr(loop->iter);
            if (a < 0 || b < 0 || values[a].kind != Value::Literal || values[b].kind != Value::Literal) return -1;
            auto lo = values[a].number, hi = values[b].number;
            if (lo < -8 || hi > 8 || hi < lo || hi - lo > 8) return -1;
            for (auto i = lo; i < hi; i++) {
                env[loop->vdef] = Literal(i);
                auto flow = Block(loop->body); if (flow < 0 || flow == 2) return -1;
            }
            return 0;
        }
        if (auto branch = Is<IfExpr>(n)) {
            auto condition = Expr(branch->cond);
            if (condition < 0 || values[condition].kind != Value::Literal) return -1;
            if (values[condition].number) return Block(branch->thenb);
            if (!branch->elseb) return 0;
            if (auto block = Is<goose::Block>(branch->elseb)) return Block(block);
            return Statement(branch->elseb);
        }
        if (Is<Continue>(n) && helper) return 1;
        if (auto returned = Is<Return>(n)) {
            if (!helper || returned->target != target || returned->vals.size() != 1 ||
                !Same(return_type, returned->vals[0]->exprtype)) return -1;
            result = Expr(returned->vals[0]); if (result < 0) return -1;
            return 2;
        }
        return -1;
    }
    int Block(goose::Block *block) {
        if (!block) return -1;
        for (auto statement : block->stmts) { auto flow = Statement(statement); if (flow) return flow; }
        if (block->tail) return Statement(block->tail);
        return 0;
    }
};

inline bool Function::ByteStencilLoop(ForLoop *loop, const Slot &binding, TypeExpr *ct, uint32_t lo, uint32_t hi) {
    if (c.opts.debug || loop->iterkind != IK_COUNT || loop->byref || loop->idxdef || loop->vdef->isvar ||
        !IsIntT(ct) || ct->intstorage != IS_I64 || !IsIntT(binding.type) || binding.type->intstorage != IS_I64 || binding.type->ix || ct->ix ||
        binding.kind != Slot::LOCAL || (c.region_cursors && c.may_have_prefix_mappings)) return false;
    ByteStencilProof proof(*this);
    if (!proof.Private(loop->vdef)) return false;
    auto width = proof.Expr(loop->iter);
    if (width < 0 || (proof.values[width].kind != ByteStencilProof::Value::Variable && proof.values[width].kind != ByteStencilProof::Value::Literal)) return false;
    if (proof.Block(loop->body) || proof.store < 0 || proof.result < 0) return false;
    using V = ByteStencilProof::Value;
    auto &v = proof.values;
    auto variable = [&](int a, VarDef *id) { return a >= 0 && v[a].kind == V::Variable && v[a].variable == Resolve(id); };
    auto same = [&](int a, int b) {
        if (a < 0 || b < 0 || v[a].kind != v[b].kind) return false;
        if (v[a].kind == V::Variable) return v[a].variable == v[b].variable;
        return v[a].kind == V::Literal && v[a].number == v[b].number;
    };
    auto binary = [&](int a, TType op) { return a >= 0 && v[a].kind == V::Binary && v[a].op == op; };
    auto literal = [&](int a) { return a >= 0 && v[a].kind == V::Literal; };
    auto destination = proof.store;
    if (v[destination].kind != V::Load) return false;
    auto dst = v[v[destination].left].variable;
    auto dest_index = v[destination].right;
    if (!binary(dest_index, T_PLUS) || !variable(v[dest_index].right, loop->vdef)) return false;
    auto product = v[dest_index].left;
    if (!binary(product, T_MUL) || !same(v[product].right, width)) return false;
    auto row = v[product].left;
    if (v[row].kind != V::Variable || !proof.Scalar(v[row].variable->type)) return false;
    int height = -1;
    VarDef *src = nullptr;
    int min_dx = 0, max_dx = 0;
    map<int, pair<int, int>> loads;
    auto offset = [&](int value, VarDef *base, int &delta) {
        delta = 0;
        if (variable(value, base)) return true;
        if (!binary(value, T_PLUS) && !binary(value, T_MINUS)) return false;
        if (!variable(v[value].left, base) || !literal(v[value].right)) return false;
        auto number = v[v[value].right].number;
        if (number < -1024 || number > 1024) return false;
        delta = int(number);
        if (v[value].op == T_MINUS) delta = -delta;
        return true;
    };
    auto load = [&](int value) {
        if (loads.count(value)) return true;
        if (v[value].kind != V::Load) return false;
        auto object = v[v[value].left].variable;
        if (src && object != src) return false;
        src = object;
        auto index = v[value].right;
        if (!binary(index, T_PLUS)) return false;
        auto y = v[index].left, x = v[index].right;
        if (!binary(y, T_MUL) || !same(v[y].right, width)) return false;
        y = v[y].left;
        int dx = 0, dy = 0;
        if (variable(x, loop->vdef) && variable(y, v[row].variable)) {
            loads[value] = { 0, 0 }; return true;
        }
        if (!binary(x, T_MOD) || !same(v[x].right, width) ||
            !binary(y, T_MOD) || (v[v[y].right].kind != V::Variable && v[v[y].right].kind != V::Literal)) return false;
        auto h = v[y].right;
        if (height >= 0 && !same(h, height)) return false;
        height = h;
        if (!offset(v[x].left, loop->vdef, dx) || !offset(v[y].left, v[row].variable, dy)) return false;
        min_dx = min(min_dx, dx); max_dx = max(max_dx, dx);
        loads[value] = { dx, dy }; return true;
    };
    int validation_budget = 512;
    function<int(int)> numeric = [&](int value) {
        if (--validation_budget < 0) return -1;
        if (literal(value)) {
            auto number = v[value].number;
            if (number < 0 || number > 4080) return -1;
            return int(number);
        }
        if (v[value].kind == V::Load) { if (load(value)) return 255; return -1; }
        if (!binary(value, T_PLUS)) return -1;
        auto a = numeric(v[value].left); if (a < 0) return -1;
        auto b = numeric(v[value].right);
        if (b < 0 || a + b > 4080) return -1;
        return a + b;
    };
    function<bool(int)> predicate = [&](int value) {
        if (--validation_budget < 0) return false;
        if (literal(value)) return v[value].number == 0 || v[value].number == 1;
        if (v[value].kind == V::Not) return predicate(v[value].left);
        if (binary(value, T_ANDAND) || binary(value, T_OROR)) return predicate(v[value].left) && predicate(v[value].right);
        if (v[value].kind != V::Binary) return false;
        switch (v[value].op) {
            case T_EQ: case T_NEQ: case T_LT: case T_LTEQ: case T_GT: case T_GTEQ:
                return numeric(v[value].left) >= 0 && numeric(v[value].right) >= 0;
            default: return false;
        }
    };
    auto output = proof.result;
    if (v[output].kind != V::Select || !literal(v[output].right) || !literal(v[output].third) ||
        v[v[output].right].number < 0 || v[v[output].right].number > 255 ||
        v[v[output].third].number < 0 || v[v[output].third].number > 255 || !predicate(v[output].left) ||
        !src || height < 0 || src == dst) return false;
    // Declarations whose values do not reach the output still execute on
    // the scalar path. Prove their reads and remainders nontrapping too.
    for (size_t i = 0; i < v.size(); i++) {
        if (v[i].kind == V::Load && int(i) != destination && !load(int(i))) return false;
        if (binary(int(i), T_MOD)) {
            int delta = 0;
            bool horizontal = same(v[i].right, width) && offset(v[i].left, loop->vdef, delta);
            bool vertical = same(v[i].right, height) && offset(v[i].left, v[row].variable, delta);
            if (!horizontal && !vertical) return false;
        }
    }
    auto scalar_slot = [&](VarDef *id) {
        auto slot = Lookup(id, loop->line);
        return slot.kind == Slot::LOCAL && IsIntT(slot.type) && slot.type->intstorage == IS_I64;
    };
    if ((!literal(width) && !scalar_slot(v[width].variable)) ||
        (!literal(height) && !scalar_slot(v[height].variable)) || !scalar_slot(v[row].variable)) return false;
    auto src_slot = Lookup(src, loop->line), dst_slot = Lookup(dst, loop->line);
    if (src_slot.kind != Slot::LOCAL || dst_slot.kind != Slot::LOCAL || src_slot.type->kind != TY_SLICE || dst_slot.type->kind != TY_SLICE) return false;

    // Debug arithmetic retains its checked scalar evaluation above.
    // No loads, stores or divisions before the complete span proof. Invalid
    // views and overlap run the original loop, retaining ordered traps/writes.
    auto dimension = [&](int value) {
        if (!literal(value)) return Lookup(v[value].variable, loop->line);
        code.I64Const(v[value].number); return Slot { Slot::LOCAL, Save(I64), c.ast.inttypes[IS_I64] };
    };
    auto width_slot = dimension(width);
    auto height_slot = dimension(height);
    auto row_slot = Lookup(v[row].variable, loop->line);
    auto fast = Local(I32), total = Local(I64), source = Local(I64), dest = Local(I64);
    code.I32Const(0); Set(fast);
    Read(src_slot); code.Op(0xa7); code.Op(0xad); Set(source);
    Read(dst_slot); code.Op(0xa7); code.Op(0xad); Set(dest);
    auto positive32 = [&](const Slot &slot) {
        Read(slot); code.I64Const(0); code.Op(0x55);
        Read(slot); code.I64Const(UINT32_MAX); code.Op(0x58); code.Op(0x71);
    };
    positive32(width_slot); positive32(height_slot); code.Op(0x71);
    Read(row_slot); code.I64Const(0); code.Op(0x59); code.Op(0x71);
    Read(row_slot); Read(height_slot); code.Op(0x53); code.Op(0x71); Begin(0x04);
    Read(width_slot); Read(height_slot); code.Op(0x7e); Set(total);
    Get(total); code.I64Const(UINT32_MAX); code.Op(0x58);
    for (auto slot : { src_slot, dst_slot }) {
        Read(slot); code.I64Const(32); code.Op(0x88); Get(total); code.Op(0x5a); code.Op(0x71);
    }
    code.OpU(0x3f, 0); code.Op(0xad); code.I64Const(16); code.Op(0x86); auto memory_bytes = Save(I64);
    for (auto pointer : { source, dest }) {
        Get(pointer); Get(total); code.Op(0x7c); Get(memory_bytes); code.Op(0x58); code.Op(0x71);
    }
    Get(source); Get(total); code.Op(0x7c); Get(dest); code.Op(0x58);
    Get(dest); Get(total); code.Op(0x7c); Get(source); code.Op(0x58); code.Op(0x72); code.Op(0x71); Set(fast); End();
    unordered_map<int, uint32_t> rows;
    Get(fast); Begin(0x04);
    for (auto &[value, delta] : loads) {
        auto dy = delta.second;
        if (rows.count(dy)) continue;
        Read(row_slot); code.I64Const(dy); code.Op(0x7c);
        Read(height_slot); code.Op(0x81); auto wrapped = Save(I64);
        Get(wrapped); code.I64Const(0); code.Op(0x53); Begin(0x04);
        Get(wrapped); Read(height_slot); code.Op(0x7c); Set(wrapped); End();
        Get(wrapped); Read(width_slot); code.Op(0x7e); rows[dy] = Save(I64);
    }
    End();
    auto splat = [&](int64_t number) { code.I32Const(int32_t(number)); code.OpU(0xfd, 0x10); };
    unordered_map<int, uint32_t> vectors;
    function<void(int)> emit_number = [&](int value) {
        if (literal(value)) { splat(v[value].number); return; }
        if (auto found = vectors.find(value); found != vectors.end()) { Get(found->second); return; }
        if (v[value].kind == V::Load) {
            auto [dx, dy] = loads.at(value);
            Get(source); Get(rows.at(dy)); code.Op(0x7c); Get(lo); code.Op(0x7c);
            if (dx) { code.I64Const(dx); code.Op(0x7c); }
            code.Op(0xa7); code.OpU(0xfd, 0x02); code.U(0); code.U(0); // v128.load8x8_u
        } else {
            emit_number(v[value].left); emit_number(v[value].right); code.OpU(0xfd, 0x8e); // i16x8.add
        }
        auto slot = Save(V128); vectors[value] = slot; Get(slot);
    };
    function<void(int)> emit_predicate = [&](int value) {
        if (literal(value)) { if (v[value].number) splat(-1); else splat(0); return; }
        if (v[value].kind == V::Not) { emit_predicate(v[value].left); code.OpU(0xfd, 0x4d); return; }
        if (binary(value, T_ANDAND) || binary(value, T_OROR)) {
            emit_predicate(v[value].left); emit_predicate(v[value].right);
            if (v[value].op == T_ANDAND) code.OpU(0xfd, 0x4e); else code.OpU(0xfd, 0x50);
            return;
        }
        emit_number(v[value].left); emit_number(v[value].right);
        uint32_t opcode = 0x2d;
        switch (v[value].op) {
            case T_EQ: opcode = 0x2d; break;
            case T_NEQ: opcode = 0x2e; break;
            case T_LT: opcode = 0x2f; break;
            case T_GT: opcode = 0x31; break;
            case T_LTEQ: opcode = 0x33; break;
            case T_GTEQ: opcode = 0x35; break;
            default: break;
        }
        code.OpU(0xfd, opcode);
    };
    auto done = Begin(), again = Begin(0x03);
    Get(lo); Get(hi); code.Op(0x59); Br(done, true);
    Get(lo); Write(binding);
    Get(fast);
    Get(lo); code.I64Const(min_dx); code.Op(0x7c); code.I64Const(0); code.Op(0x59); code.Op(0x71);
    Get(lo); code.I64Const(7 + max_dx); code.Op(0x7c); Get(hi); code.Op(0x53); code.Op(0x71); Begin(0x04);
    Get(dest); Read(row_slot); Read(width_slot); code.Op(0x7e); code.Op(0x7c); Get(lo); code.Op(0x7c); code.Op(0xa7);
    splat(v[v[output].right].number); splat(v[v[output].third].number); emit_predicate(v[output].left);
    code.OpU(0xfd, 0x52); // v128.bitselect
    splat(0); code.OpU(0xfd, 0x66); // i8x16.narrow_i16x8_u
    code.OpU(0xfd, 0x1d); code.Byte(0); // i64x2.extract_lane 0
    code.Mem(0x37, 0); // low eight bytes
    Get(lo); code.I64Const(8); code.Op(0x7c); Set(lo); Br(again); End();
    auto step = Begin(); PushExit({ done, nullptr, {}, {}, true, step });
    BlockInto(loop->body, {}, {}); exits.pop_back(); End();
    Get(lo); code.I64Const(1); code.Op(0x7c); Set(lo); Br(again); End(); End();
    return true;
}
} // namespace goose::direct_wasm
