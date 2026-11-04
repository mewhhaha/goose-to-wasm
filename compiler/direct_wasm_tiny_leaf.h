#pragma once
namespace goose::direct_wasm {

inline bool Function::TinyLeaf(Call *call, const vector<Node *> &args) {
    auto callee = call->spec;
    if (c.opts.debug || !callee || !callee->body || !callee->rets.empty() ||
        callee->sf->isextern || callee->sf->isexport || callee->sf->isrec || callee->incycle ||
        callee->sf->isthread || callee->sf->issimd || callee->lexparent ||
        !callee->needs.empty() || !c.captures[callee].empty() ||
        args.size() != callee->params.size() || !c.Leaf(callee)) return false;
    auto scalar = [](TypeExpr *type) {
        return type && ((IsIntT(type) && !type->ix && !Compiler::Varint(type)) ||
                        type->kind == TY_FLT || type->kind == TY_BOOL);
    };
    auto plain = [&](TypeExpr *type) {
        return scalar(type) || (type && type->kind == TY_SLICE && scalar(type->sub));
    };
    auto referenced = c.captured_storage;
    ScanAddressed(callee->body, referenced);
    unordered_set<VarDef *> bindings;
    auto bindable = [&](VarDef *variable) {
        return variable && variable->ownerspec == callee && plain(variable->type) &&
            !variable->captured && !variable->reusable && !referenced.count(variable);
    };
    for (auto parameter : callee->params) {
        if (!bindable(parameter)) return false;
        bindings.insert(parameter);
    }
    for (auto statement : callee->body->stmts) {
        if (auto declaration = Is<VarDecl>(statement)) {
            if (declaration->byref) return false;
            for (auto variable : declaration->defs) {
                if (!bindable(variable)) return false;
                bindings.insert(variable);
            }
        } else if (!Is<Assign>(statement)) return false;
    }
    if (callee->body->tail && (!Is<Assign>(callee->body->tail) ||
        callee->body->tail->exprtype->kind != TY_VOID)) return false;
    int budget = 40;
    function<bool(Node *)> safe = [&](Node *node) {
        if (!node) return true;
        if (--budget < 0) return false;
        switch (node->nkind) {
            case NK_Block: if (node != callee->body) return false; break;
            case NK_VarDecl: case NK_Assign: case NK_Index: case NK_Dot:
            case NK_IntLit: case NK_FltLit: case NK_BoolLit: case NK_Binary:
            case NK_Unary: case NK_AsCast: case NK_SliceExpr: break;
            case NK_Ident:
                if (!bindings.count(static_cast<Ident *>(node)->vdef)) return false;
                break;
            default: return false;
        }
        bool valid = true;
        node->Children([&](Node *child) { if (valid) valid = safe(child); });
        return valid;
    };
    if (!safe(callee->body) || MayMaterialize(callee->body)) return false;
    for (auto argument : args) if (MayMaterialize(argument)) return false;
    vector<uint32_t> values;
    for (size_t i = 0; i < args.size(); i++) {
        To(args[i], callee->params[i]->type);
        values.push_back(Save(callee->params[i]->type));
    }
    // No AST copying: each expansion gets fresh emitter bindings, while the
    // caller keeps ownership of its activation and argument lifetimes.
    decltype(vars) outer_vars;
    decltype(aliases) outer_aliases;
    vars.swap(outer_vars); aliases.swap(outer_aliases);
    for (size_t i = 0; i < values.size(); i++)
        vars.emplace(callee->params[i], Slot { Slot::LOCAL, values[i], callee->params[i]->type });
    auto frame0 = framebytes, live0 = region_live;
    auto clean0 = cleanups.size(), headers0 = private_headers.size();
    auto temps0 = temp_scopes.size(), owners0 = owner_entries.size();
    for (auto statement : callee->body->stmts) {
        if (auto declaration = Is<VarDecl>(statement)) Decl(declaration);
        else Discard(statement);
    }
    if (callee->body->tail) Discard(callee->body->tail);
    if (framebytes != frame0 || region_live != live0 || cleanups.size() != clean0 ||
        private_headers.size() != headers0 || temp_scopes.size() != temps0 || owner_entries.size() != owners0)
        Fail(call->line, "internal: tiny leaf expansion changed activation ownership");
    vars.swap(outer_vars); aliases.swap(outer_aliases);
    return true;
}

} // namespace goose::direct_wasm
