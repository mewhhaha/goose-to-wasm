#pragma once
namespace goose::direct_wasm {

inline void Function::EnsureMemory(uint32_t top, Line line) {
    Get(top); code.OpU(0x3f, 0); code.I32Const(16); code.Op(0x74); code.Op(0x4b);
    Begin(0x04);
    // ceil(top / 65536), without overflowing a 32-bit address near 4 GiB.
    Get(top); code.I32Const(16); code.Op(0x76);
    Get(top); code.I32Const(65535); code.Op(0x71); code.Op(0x45); code.Op(0x45); code.Op(0x6a);
    code.OpU(0x3f, 0); code.Op(0x6b); code.OpU(0x40, 0);
    code.I32Const(-1); code.Op(0x46); TrapIf(line, "linear memory exhausted");
    End();
}
inline void Function::Dynamic(uint32_t bytes, Line line) {
    code.OpU(0x23, 0); auto base = Save(I32);
    Get(base); Get(bytes); code.Op(0x6a); auto end = Save(I32);
    Get(end); Get(base); code.Op(0x49); TrapIf(line, "linear-memory allocation overflow");
    Get(end); code.I32Const(7); code.Op(0x6a); code.I32Const(-8); code.Op(0x71); auto aligned = Save(I32);
    Get(aligned); Get(end); code.Op(0x49); TrapIf(line, "linear-memory allocation overflow");
    ActivationLimit(aligned, line);
    EnsureMemory(aligned, line); Get(aligned); code.OpU(0x24, 0); Get(base);
}

inline string Function::Finish() {
    auto line = spec ? spec->sf->line : Line{};
    auto done = Begin();
    if (spec) {
        PushExit({ done, spec->sf, results, resultlocals, false, {} });
        // Aggregate parameters have value semantics. Address-taken scalar
        // parameters are spilled once so reads and references share storage.
        for (auto p : spec->params) {
            if (p->type->kind == TY_FN) continue;
            auto old = vars.at(p);
            if (c.Aggregate(p->type) || addressed.count(p)) {
                Slot slot { Slot::FRAME, Frame(p->type), p->type };
                StoreCopy({ p->type, slot }, { p->type, old.index,
                    c.Aggregate(p->type) ? CapturedValue::BorrowedFixed : CapturedValue::Immediate });
                vars[p] = slot;
            }
        }
        BlockInto(spec->body, results, resultlocals);
        exits.pop_back();
    } else {
        for (auto g : c.ast.globals) Decl(g);
        auto main = c.ast.MainFunction();
        if (!main || main->specs.empty()) Fail({}, "program needs a concrete main function");
        RecordRegionCall(main->specs[0], main->line);
        CallIndex(c.function_index.at(main->specs[0]));
    }
    End();
    c.region_own[spec] = region_peak;
    // Copy owned results while their source storage still belongs to this
    // activation. Returning a pointer into the released callee frame would
    // let the next sibling or recursive call overwrite the earlier value.
    for (size_t i = 0; i < resultdestinations.size(); i++) if (resultdestinations[i]) {
        StoreCopy({ results[i], AddressLocal { *resultdestinations[i] } },
                  { results[i], resultlocals[i], CapturedValue::BorrowedFixed });
        Get(*resultdestinations[i]); Set(resultlocals[i]);
    }
    Get(framebase); code.OpU(0x24, 0);
    for (auto r : resultlocals) Get(r);
    auto body = std::move(code.data); code.data.clear();
    // The fixed frame size is now known. Prepend reservation/checks before
    // any initializer or store; recursive calls get independent frames.
    code.OpU(0x23, 0); Set(framebase);
    if (framebytes) {
        framebytes = Compiler::Align(framebytes, 8);
        Get(framebase); code.I32Const(int32_t(framebytes)); code.Op(0x6a); auto top = Save(I32);
        Get(top); Get(framebase); code.Op(0x49); TrapIf(line, "activation frame overflow");
        ActivationLimit(top, line);
        EnsureMemory(top, line); Get(top); code.OpU(0x24, 0);
    }
    code.Raw(body); code.Op(0x0b);
    Bytes out;
    vector<pair<uint32_t, uint8_t>> groups;
    for (auto t : locals) {
        if (!groups.empty() && groups.back().second == t) groups.back().first++;
        else groups.emplace_back(1, t);
    }
    out.U(groups.size()); for (auto [count, type] : groups) { out.U(count); out.Byte(type); }
    out.Raw(code.data); return out.data;
}

inline DirectWasmResult Compiler::Compile() {
    if (!opts.initial_pages || opts.initial_pages > opts.maximum_pages || opts.maximum_pages > 65535)
        Fail({}, "linear memory requires 1 <= initial_pages <= maximum_pages <= 65535");
    AddImport("goose", "write", {{ I32, I32 }, {}});
    AddImport("goose", "print_i64", {{ I64 }, {}});
    AddImport("goose", "print_u64", {{ I64 }, {}});
    AddImport("goose", "print_f64", {{ F64 }, {}});
    AddImport("goose", "print_f32", {{ F32 }, {}});
    AddImport("goose", "print_bool", {{ I32 }, {}});
    AddImport("goose", "newline", {{}, {}});
    AddImport("goose", "abort", {{ I32, I32, I32 }, {}});
    AddImport("goose", "exit", {{ I32 }, {}});
    for (auto g : ast.globals) {
        for (auto v : g->defs) {
            W(v->type); auto layout = RegionArray(v->type) ? HeaderLayout(v->type) : Size(v->type);
            if (RegionArray(v->type)) {
                needs_regions = true;
                global_regions[v] = uint32_t(global_regions.size());
            }
            globals[v] = { Slot::GLOBAL, Data(layout.size, layout.align), v->type };
        }
        for (auto n : g->inits) Scan(n);
    }
    auto main = ast.MainFunction();
    if (!main || main->specs.empty()) Fail({}, "program needs a concrete main function");
    Reach(main->specs[0]);
    // Public scalar exports are useful from either V8 or Wasmtime. Their
    // global initializers still run only when the host calls _start.
    for (auto sf : ast.functions) if (sf->isexport)
        for (auto sp : sf->specs) if (!sp->failed && !sp->stale) Reach(sp);
    for (uint32_t i = 0; i < specs.size(); i++) function_index[specs[i]] = uint32_t(imports.size()) + i;
    auto startindex = uint32_t(imports.size() + specs.size());
    auto startsig = Sig({ {}, {} });
    DirectWasmResult result;
    vector<string> bodies;
    vector<uint32_t> ftypes;
    for (auto sp : specs) {
        Function f(*this, sp, function_index.at(sp), function_type.at(sp));
        auto body = f.Finish();
        string name = string(sp->sf->qname) + "#" + to_string(sp->id);
        result.function_info.push_back({ name, f.index, body.size(), BodyHash(body),
                                        vector<uint32_t>(f.dependencies.begin(), f.dependencies.end()) });
        result.code_bytes += body.size(); bodies.push_back(std::move(body)); ftypes.push_back(f.sig);
    }
    {
        Function f(*this, nullptr, startindex, startsig); auto body = f.Finish();
        result.function_info.push_back({ "_start", f.index, body.size(), BodyHash(body),
                                        vector<uint32_t>(f.dependencies.begin(), f.dependencies.end()) });
        result.code_bytes += body.size(); bodies.push_back(std::move(body)); ftypes.push_back(startsig);
    }
    result.functions = bodies.size();
    auto stackbase = Align(data_base + uint32_t(data.size()), 16);
    auto maximum_bytes = uint64_t(opts.maximum_pages) * 65536;
    if (stackbase > maximum_bytes) Fail({}, "static data exceeds linear memory");
    result.region_count = needs_regions ? BoundRegions() : 0;
    if (result.region_count) {
        result.region_bytes = uint32_t(((maximum_bytes - stackbase) / (uint64_t(result.region_count) + 1)) & ~UINT64_C(7));
        if (result.region_bytes < 8) Fail({}, "linear memory has no space for stable data regions");
    }
    auto activation_limit = uint32_t(maximum_bytes - uint64_t(result.region_count) * result.region_bytes);
    result.activation_bytes = activation_limit - stackbase;
    auto initial = max(opts.initial_pages, uint32_t((uint64_t(stackbase) + 65535u) / 65536u));
    if (initial > opts.maximum_pages) Fail({}, "static data leaves no room in linear memory");
    Bytes module; module.Raw(string_view("\0asm\1\0\0\0", 8));
    Bytes types; types.U(signatures.size());
    for (auto &s : signatures) {
        types.Byte(0x60); types.U(s.args.size()); for (auto x : s.args) types.Byte(x);
        types.U(s.results.size()); for (auto x : s.results) types.Byte(x);
    }
    module.Section(1, types);
    Bytes imp; imp.U(imports.size());
    for (auto &i : imports) { imp.Name(i.module); imp.Name(i.name); imp.Byte(0); imp.U(i.type); }
    module.Section(2, imp);
    Bytes funcs; funcs.U(ftypes.size()); for (auto t : ftypes) funcs.U(t); module.Section(3, funcs);
    Bytes memory; memory.U(1); memory.Byte(1); memory.U(initial); memory.U(opts.maximum_pages); module.Section(5, memory);
    Bytes gl; gl.U(needs_regions ? 6 : 1);
    auto global = [&](uint32_t value, bool mutable_) {
        gl.Byte(I32); gl.Byte(mutable_); gl.I32Const(int32_t(value)); gl.Op(0x0b);
    };
    global(stackbase, true);
    if (needs_regions) {
        global(uint32_t(global_regions.size()), true); global(activation_limit, false);
        global(result.region_bytes, false); global(result.region_count, false); global(activation_limit, false);
    }
    module.Section(6, gl);
    vector<pair<string, uint32_t>> exported;
    set<string> names { "memory", "_start" };
    for (auto sp : specs) if (sp->sf->isexport) {
        auto name = sp->sf->cname.empty() ? string(sp->sf->qname) : sp->sf->cname;
        if (!names.insert(name).second) Fail(sp->sf->line, "duplicate exported function name '" + name + "'");
        for (auto p : sp->params)
            if (p->type->kind != TY_INT && p->type->kind != TY_FLT && p->type->kind != TY_BOOL)
                Fail(sp->sf->line, "public exports currently accept numeric and bool values only");
        for (auto t : sp->rets)
            if (t->kind != TY_INT && t->kind != TY_FLT && t->kind != TY_BOOL)
                Fail(sp->sf->line, "public exports currently return numeric and bool values only");
        exported.emplace_back(name, function_index.at(sp));
    }
    Bytes ex; ex.U(2 + exported.size());
    ex.Name("memory"); ex.Byte(2); ex.U(0); ex.Name("_start"); ex.Byte(0); ex.U(startindex);
    for (auto &[name, idx] : exported) { ex.Name(name); ex.Byte(0); ex.U(idx); }
    module.Section(7, ex);
    Bytes codes; codes.U(bodies.size()); for (auto &b : bodies) { codes.U(b.size()); codes.Raw(b); } module.Section(10, codes);
    auto segments = SparseDataSegments(data, data_base);
    Bytes ds; ds.U(segments.size());
    for (auto &s : segments) {
        ds.U(0); ds.I32Const(int32_t(s.offset)); ds.Op(0x0b); ds.U(s.bytes.size()); ds.Raw(s.bytes);
    }
    module.Section(11, ds);
    Bytes debugnames; debugnames.Name("name");
    Bytes fnnames; fnnames.U(imports.size() + result.function_info.size());
    for (uint32_t i = 0; i < imports.size(); i++) { fnnames.U(i); fnnames.Name(imports[i].module + "." + imports[i].name); }
    for (auto &f : result.function_info) { fnnames.U(f.index); fnnames.Name(f.name); }
    debugnames.Byte(1); debugnames.U(fnnames.data.size()); debugnames.Raw(fnnames.data); module.Section(0, debugnames);
    Bytes producer; producer.Name("goose.direct");
    producer.Name("abi=1;memory=wasm32;slices=packed-ptr32-len32;features=bulk-memory,multi-value,sign-ext");
    module.Section(0, producer);
    if (needs_regions) {
        Bytes regions; regions.Name("goose.regions");
        regions.Raw(cat("{\"schema\":1,\"region_count\":", result.region_count,
                        ",\"global_regions\":", global_regions.size(), ",\"region_bytes\":", result.region_bytes,
                        ",\"activation_base\":", stackbase, ",\"activation_limit\":", activation_limit, "}"));
        module.Section(0, regions);
    }
    result.module = std::move(module.data); return result;
}

} // namespace goose::direct_wasm
