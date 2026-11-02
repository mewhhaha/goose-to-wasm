#pragma once
namespace goose::direct_wasm {

inline optional<int64_t> Function::KnownInteger(Node *node, TypeExpr *type) {
    if (!type || !node || !node->exprtype || !IsIntT(type) || !IsIntT(node->exprtype) ||
        node->exprtype->intstorage != type->intstorage) return {};
    if (auto literal = Is<IntLit>(node)) return literal->val;
    if (auto id = Is<Ident>(node); id && id->vdef) {
        auto slot = Lookup(id->vdef, id->line);
        if (slot.kind == Slot::LOCAL && IsIntT(slot.type) && slot.type->intstorage == type->intstorage)
            if (auto found = constant_slots.find(slot.index); found != constant_slots.end()) return found->second;
    }
    return {};
}

inline const vector<uint32_t> &Compiler::ConstantDivisors(FnSpec *spec) {
    auto [cached, fresh] = constant_divisors.emplace(spec, vector<uint32_t>{});
    if (!fresh || !Leaf(spec)) return cached->second;
    unordered_set<VarDef *> candidates, written;
    int budget = 256;
    function<bool(Node *)> scan = [&](Node *node) {
        if (!node || Is<FnDecl>(node) || Is<StructDecl>(node) || Is<EnumDecl>(node) || Is<AliasDecl>(node)) return true;
        if (budget-- == 0) return false;
        if (auto binary = Is<Binary>(node); binary && binary->op == T_MOD &&
            IsIntT(binary->left->exprtype) && binary->left->exprtype->intstorage == IS_I64) {
            auto right = Is<Ident>(binary->right);
            if (right && right->vdef && IsIntT(right->exprtype) && right->exprtype->intstorage == IS_I64)
                candidates.insert(right->vdef);
        }
        Node *target = nullptr;
        if (auto assignment = Is<Assign>(node)) target = assignment->lval;
        if (auto change = Is<IncDec>(node)) target = change->lval;
        if (auto id = Is<Ident>(target); id && id->vdef) written.insert(id->vdef);
        if (auto loop = Is<ForLoop>(node)) { written.insert(loop->vdef); written.insert(loop->idxdef); }
        bool valid = true;
        node->Children([&](Node *child) { if (valid) valid = scan(child); });
        return valid;
    };
    if (!scan(spec->body)) return cached->second;
    for (uint32_t index = 0; index < spec->params.size(); index++) {
        auto parameter = spec->params[index];
        if (IsIntT(parameter->type) && parameter->type->intstorage == IS_I64 &&
            candidates.count(parameter) && !written.count(parameter)) cached->second.push_back(index);
    }
    return cached->second;
}

inline void Compiler::CollectConstants() {
    auto consider = [&](Call *call) {
        auto spec = call->spec;
        if (!spec || call->builtin >= 0 || call->fvbody || !call->dispatch.empty() ||
            constant_calls.count(call)) return;
        const auto &parameters = ConstantDivisors(spec);
        if (parameters.empty()) return;
        auto arguments = call->ValueArgNodes();
        if (arguments.size() != spec->params.size()) return;
        vector<pair<uint32_t, int64_t>> bindings;
        bool power_of_two = false;
        for (auto parameter : parameters) {
            auto literal = Is<IntLit>(arguments[parameter]);
            if (!literal || !IsIntT(literal->exprtype) || literal->exprtype->intstorage != IS_I64) continue;
            bindings.emplace_back(parameter, literal->val);
            if (literal->val > 0) {
                auto value = uint64_t(literal->val);
                if (!(value & (value - 1))) power_of_two = true;
            }
        }
        if (!power_of_two) return;
        size_t packs = 0;
        for (size_t index = 0; index < constant_clones.size(); index++) {
            const auto &clone = constant_clones[index];
            if (clone.spec != spec) continue;
            if (clone.bindings == bindings) { constant_calls.emplace(call, index); return; }
            packs++;
        }
        if (packs == 2) return;
        auto index = uint32_t(imports.size() + specs.size() + constant_clones.size());
        constant_calls.emplace(call, constant_clones.size());
        constant_clones.push_back({ spec, std::move(bindings), index });
    };
    function<void(Node *)> visit = [&](Node *node) {
        if (!node || Is<FnDecl>(node) || Is<FunVal>(node) || Is<StructDecl>(node) ||
            Is<EnumDecl>(node) || Is<AliasDecl>(node)) return;
        if (auto call = Is<Call>(node)) {
            consider(call);
            if (call->fvbody) visit(call->fvbody);
            if (call->defaultinit) visit(call->defaultinit);
            for (auto argument : call->ValueArgNodes()) visit(argument);
            return;
        }
        node->Children([&](Node *child) { visit(child); });
    };
    for (auto global : ast.globals) for (auto init : global->inits) visit(init);
    for (auto spec : specs) visit(spec->body);
}

inline uint32_t Compiler::ConstantTarget(Call *call, uint32_t fallback) {
    auto found = constant_calls.find(call);
    if (found == constant_calls.end()) return fallback;
    const auto &clone = constant_clones[found->second];
    if (clone.spec != call->spec || call->fvbody || !call->dispatch.empty()) return fallback;
    return clone.index;
}

} // namespace goose::direct_wasm
