import model;
import parallel;
import lexer;
import parser;
import os;

struct SourceRequest { start: i64, length: i64, token: i64 = -1, package: i64 = -1, source: i64 = -1, index: i64 = -1, library: bool = false }
struct SourcePackage { name: i64, start: i64, length: i64 }

fn source_directory(path: const u8[:], out: u8[>..]&) {
    var end = 0;
    for byte, i in path { if byte == '/' || byte == '\\' { end = i + 1; } }
    out.append(path[..end]);
}
fn source_absolute(path: const u8[:]) -> bool {
    if path.len == 0 { return false; }
    if path[0] == '/' || path[0] == '\\' { return true; }
    return path.len > 2 && path[1] == ':';
}
fn source_normalize(path: const u8[:], out: u8[>..]&) {
    var starts: i64[>..] = [];
    var sizes: i64[>..] = [];
    var at = 0;
    let absolute = source_absolute(path);
    let unc = path.len >= 2 && path[0] == '\\' && path[1] == '\\';
    while at < path.len {
        while at < path.len && (path[at] == '/' || path[at] == '\\') { at++; }
        let start = at;
        while at < path.len && path[at] != '/' && path[at] != '\\' { at++; }
        let length = at - start;
        if length == 0 || length == 1 && path[start] == '.' { continue; }
        if length == 2 && path[start] == '.' && path[start + 1] == '.' {
            if starts.len > 0 {
                let last = starts.len - 1;
                if (!unc || last >= 2) &&
                   (last > 0 || sizes[0] != 2 || path[starts[0] + 1] != ':') &&
                   (sizes[last] != 2 || path[starts[last]] != '.' || path[starts[last] + 1] != '.') {
                    starts.pop(); sizes.pop(); continue;
                }
            }
            if absolute { continue; }
        }
        starts.push(start); sizes.push(length);
    }
    let sep: u8 = if unc { '\\' } else { '/' };
    if unc { out.append("\\\\"); }
    else if absolute && (path[0] == '/' || path[0] == '\\') { out.push('/'); }
    for start, i in starts {
        if out.len > 0 && out[out.len - 1] != '/' && out[out.len - 1] != '\\' { out.push(sep); }
        out.append(path[start..start + sizes[i]]);
    }
    if out.len == 0 { out.append("."); }
}
fn source_request(p: Program&, pending: SourceRequest[>..]&, seen: SourceRequest[>..]&,
                  path: const u8[:], token: i64, package: i64 = -1, library: bool = false) {
    var normalized: u8[>..] = [];
    source_normalize(path, normalized);
    for request in seen {
        if same_bytes(p.text[request.start..request.start + request.length], normalized) {
            // A queued shared dependency must run before its new importer.
            if request.source == -1 { pending.push(request); }
            return;
        }
    }
    let start = p.text.len;
    p.text.append(normalized);
    let request = SourceRequest { start: start, length: normalized.len, token: token, package: package, index: seen.len, library: library };
    pending.push(request); seen.push(request);
}
fn source_package(p: Program&, packages: SourcePackage[>..]&, name: i64) -> i64 {
    for package, i in packages { if same_name(p, package.name, name) { return i; } }
    return -1;
}
recursive fn source_embed_literal(p: Program&, node: i64, depth: i64 = 0) -> i64 {
    if node < 0 || depth > 128 { return -1; }
    let n = p.nodes[node];
    if n.kind == N_STRING { return n.token; }
    if n.kind == N_CAST || n.kind == N_UNARY && n.integer == T_MUL { return source_embed_literal(p, n.left, depth + 1); }
    if n.kind != N_NAME || n.symbol < 0 { return -1; }
    let symbol = p.symbols[n.symbol];
    if (symbol.flags & S_GLOBAL) == 0 || (symbol.flags & S_MUTABLE) != 0 || symbol.node < 0 { return -1; }
    let declaration = p.nodes[symbol.node];
    if declaration.kind != N_VARIABLE { return -1; }
    return source_embed_literal(p, declaration.right, depth + 1);
}
fn source_embed_file(p: Program&, node: i64, argument: i64) -> i64 {
    let literal = source_embed_literal(p, argument);
    if literal < 0 { diagnose(p, p.nodes[argument].token, "embed_file requires a constant path string"); return -1; }
    let text = p.tokens[literal]; let call = p.tokens[p.nodes[node].token];
    var path: u8[>..] = [];
    let embedded = p.text[text.text_start..text.text_start + text.text_len];
    if !source_absolute(embedded) && call.source >= 0 {
        let source = p.sources[call.source]; source_directory(p.text[source.path_start..source.path_start + source.path_len], path);
    }
    path.append(embedded);
    var normalized: u8[>..] = []; source_normalize(path, normalized);
    var source_id = -1;
    for source, i in p.sources {
        if same_bytes(p.text[source.path_start..source.path_start + source.path_len], normalized) { source_id = i; break; }
    }
    if source_id < 0 {
        var contents: u8[>..] = [];
        if !read_file(normalized, contents) { diagnose(p, p.nodes[node].token, "cannot open embedded file"); return -1; }
        let path_start = p.text.len; p.text.append(normalized); let text_start = p.text.len; p.text.append(contents);
        source_id = p.sources.len;
        p.sources.push(Source { path_start: path_start, path_len: normalized.len, text_start: text_start, text_len: contents.len });
    }
    let source = p.sources[source_id]; var token = call; token.kind = T_STRLIT as i16;
    token.text_start = source.text_start as i32; token.text_len = source.text_len as i32;
    let token_id = p.tokens.len; p.tokens.push(token);
    return new_node(p, N_STRING, token_id);
}
fn source_shader_stage(name: const u8[:]) -> bool {
    return same_bytes(name, "vert") || same_bytes(name, "frag") || same_bytes(name, "comp");
}
fn source_embed_shader_blob(p: Program&, call_token: i64, stage: const u8[:], source_bytes: const u8[:]) -> i64 {
    let start = p.text.len;
    p.text.append("GWEB");
    p.text.push(0);
    p.text.append(stage);
    p.text.push(0);
    p.text.append(source_bytes);
    var token = p.tokens[call_token]; token.kind = T_STRLIT as i16; token.flags = 0;
    token.text_start = start as i32; token.text_len = (p.text.len - start) as i32;
    let token_id = p.tokens.len; p.tokens.push(token);
    return new_node(p, N_STRING, token_id);
}
fn source_embed_shader_file(p: Program&, node: i64, argument: i64) -> i64 {
    let literal = source_embed_literal(p, argument);
    if literal < 0 { diagnose(p, p.nodes[argument].token, "embed_shader requires a constant path string"); return -1; }
    let text = p.tokens[literal]; let call = p.tokens[p.nodes[node].token];
    var path: u8[>..] = [];
    let embedded = p.text[text.text_start..text.text_start + text.text_len];
    if !source_absolute(embedded) && call.source >= 0 {
        let source = p.sources[call.source]; source_directory(p.text[source.path_start..source.path_start + source.path_len], path);
    }
    path.append(embedded);
    var dot = -1;
    for byte, i in path { if byte == '.' { dot = i; } else if byte == '/' || byte == '\\' { dot = -1; } }
    var stage: u8[>..] = [];
    if dot >= 0 && dot + 1 < path.len { stage.append(path[dot + 1..]); }
    if !source_shader_stage(stage) {
        diagnose(p, p.nodes[argument].token, "embed_shader file extension must be .vert, .frag, or .comp"); return -1;
    }
    var normalized: u8[>..] = []; source_normalize(path, normalized);
    var contents: u8[>..] = [];
    if !read_file(normalized, contents) { diagnose(p, p.nodes[node].token, "cannot open embedded shader file"); return -1; }
    return source_embed_shader_blob(p, p.nodes[node].token, stage, contents);
}
fn source_embed_shader(p: Program&, node: i64) -> i64 {
    let first = p.nodes[node].first;
    if first < 0 { return -1; }
    let second = p.nodes[first].next;
    if second < 0 { return source_embed_shader_file(p, node, first); }
    let stage_lit = source_embed_literal(p, first);
    var stage: u8[>..] = [];
    if stage_lit >= 0 {
        let st = p.tokens[stage_lit];
        stage.append(p.text[st.text_start..st.text_start + st.text_len]);
    }
    if stage_lit < 0 || !source_shader_stage(stage) {
        diagnose(p, p.nodes[first].token, "embed_shader stage must be \"vert\", \"frag\", or \"comp\""); return -1;
    }
    var joined: u8[>..] = [];
    var part = second;
    var index = 0;
    while part >= 0 {
        let part_lit = source_embed_literal(p, part);
        if part_lit < 0 {
            diagnose(p, p.nodes[part].token, "embed_shader source parts must be constant strings"); return -1;
        }
        if index > 0 { joined.push('\n'); }
        let pt = p.tokens[part_lit];
        joined.append(p.text[pt.text_start..pt.text_start + pt.text_len]);
        part = p.nodes[part].next;
        index += 1;
    }
    return source_embed_shader_blob(p, p.nodes[node].token, stage, joined);
}
fn source_join(directory: const u8[:], module: const u8[:], out: u8[>..]&) {
    out.append(directory);
    if out.len > 0 && out[out.len - 1] != '/' && out[out.len - 1] != '\\' { out.push('/'); }
    out.append(module); out.append(".goose");
}
// Import path tokens from..to, dots spelled as directory separators.
fn source_import_name(p: Program&, from: i64, to: i64, out: u8[>..]&) {
    for token in from..to + 1 {
        let t = p.tokens[token];
        if t.kind == T_DOT { out.push('/'); } else { out.append(p.text[t.start..t.end]); }
    }
}
// Path sources only; a git source would need retrieval.
fn source_path_spelling(text: const u8[:]) -> bool {
    if source_absolute(text) { return true; }
    if text.len == 0 || text[0] != '.' { return false; }
    if text.len == 1 { return true; }
    if text[1] == '/' || text[1] == '\\' { return true; }
    return text[1] == '.' && (text.len == 2 || text[2] == '/' || text[2] == '\\');
}
// Upstream's blessed table: names a naked import loads from a remote package
// when neither a file of the importing package nor a declared package has them.
fn source_blessed(p: Program&, token: i64) -> bool {
    return token_is(p, token, "physics") || token_is(p, token, "gfx") || token_is(p, token, "audio") || token_is(p, token, "ui");
}
// `import a.b;` resolves from the importing file's package root: the root
// file's directory for the program, the library directory for its modules, a
// declared package's directory for that package's files. A file of that
// package wins; then a module of a package the root declared (`import pkg;`
// its pkg.goose, `import pkg.sub;` its sub.goose); then the standard library.
// `import .a.b;` resolves from the importing file's directory, and
// `import name from "source";` declares a package in the root file and is a
// requirement anywhere else.
fn source_import_path(p: Program&, node: i64, directory: const u8[:], root: const u8[:], stdlib: const u8[:],
                      packages: SourcePackage[>..]&, root_file: bool, current_package: i64,
                      resolved_package: i64&, out: u8[>..]&, library: bool&) -> bool {
    let n = p.nodes[node];
    var name: u8[>..] = [];
    source_import_name(p, n.integer, n.aux, name);
    if n.left >= 0 {
        let t = p.tokens[n.left];
        let source = p.text[t.text_start..t.text_start + t.text_len];
        if !source_path_spelling(source) {
            diagnose(p, n.token, "remote package sources are not yet supported; a package source must be a path"); return false;
        }
        var raw: u8[>..] = [];
        if !source_absolute(source) { raw.append(directory); }
        raw.append(source);
        var normalized: u8[>..] = []; source_normalize(raw, normalized);
        var index = source_package(p, packages, n.token);
        if root_file {
            if index >= 0 { diagnose(p, n.token, "the package is declared twice"); return false; }
            if !is_dir(normalized) { diagnose(p, n.token, "the package source is not a directory"); return false; }
            source_join(normalized, name, out);
            if !file_exists(out) { diagnose(p, n.token, "the package has no entry file named after it"); return false; }
            for package in packages {
                if same_bytes(normalized, p.text[package.start..package.start + package.length]) {
                    diagnose(p, n.token, "two packages have the same root; each package needs a directory of its own"); return false;
                }
            }
            let start = p.text.len; p.text.append(normalized);
            index = packages.len; packages.push(SourcePackage { name: n.token, start: start, length: normalized.len });
        } else {
            if index < 0 {
                if source_blessed(p, n.token) {
                    diagnose(p, n.token, "blessed packages are not yet supported: remote package retrieval is not implemented"); return false;
                }
                diagnose(p, n.token, "a package requirement must be declared by the root file: add the same import there"); return false;
            }
            let declared = packages[index];
            if !same_bytes(normalized, p.text[declared.start..declared.start + declared.length]) {
                diagnose(p, n.token, "required package is declared from a different source"); return false;
            }
            source_join(p.text[declared.start..declared.start + declared.length], name, out);
        }
        resolved_package = index; library = false;
        return true;
    }
    if (n.flags & F_REFERENCE) != 0 {
        source_join(directory, name, out);
        if file_exists(out) { return true; }
        diagnose(p, n.token, "cannot open relative import"); return false;
    }
    source_join(root, name, out);
    let local = file_exists(out);
    var package_index = source_package(p, packages, n.integer);
    // A package's own name, from inside it, is its own file.
    if package_index == current_package { package_index = -1; }
    if package_index >= 0 {
        if local { diagnose(p, n.token, "import is both a file of this package and a declared package's module"); return false; }
        var module: u8[>..] = [];
        if n.aux > n.integer { source_import_name(p, n.integer + 2, n.aux, module); }
        else { source_import_name(p, n.integer, n.integer, module); }
        let declared = packages[package_index]; out.clear();
        source_join(p.text[declared.start..declared.start + declared.length], module, out);
        resolved_package = package_index; library = false;
        if file_exists(out) { return true; }
        diagnose(p, n.token, "cannot open declared package module"); return false;
    }
    if local { return true; }
    var looked: u8[>..] = []; looked.append(out); out.clear();
    if stdlib.len > 0 {
        source_join(stdlib, name, out);
        if file_exists(out) { library = true; resolved_package = -1; return true; }
    }
    if source_blessed(p, n.integer) {
        diagnose(p, n.token, "blessed packages are not yet supported: remote package retrieval is not implemented"); return false;
    }
    var message: u8[>..] = [];
    message.append("cannot find the module ");
    for byte in name { if byte == '/' { message.push('.'); } else { message.push(byte); } }
    message.append(", looked for "); message.append(looked);
    if stdlib.len > 0 { message.append(" and "); message.append(out); }
    else { message.append("; pass --stdlib or set GOOSE_STDLIB"); }
    diagnose(p, n.token, message);
    return false;
}
let PARSE_SPMD_PENDING: i64 = 0;
let PARSE_SPMD_FALLBACK: i64 = 1;
let PARSE_SPMD_OK: i64 = 2;
let PARSE_PHASE_PARSE: i64 = 0;
let PARSE_PHASE_INSTALL: i64 = 1;
let PARSE_PHASE_ABORT: i64 = 2;
let PARSE_SPMD_MAX_FILES: i64 = 1024;
let PARSE_SPMD_IDENT_SLOTS: i64 = 16384;

struct ParseUniqueIdent {
    first_local_tok: i32 = 0, rel_start: i32 = 0, rel_end: i32 = 0,
    hash: u32 = 0, canonical: i32 = 0,
}
struct ParseImportRec {
    name_start: i32 = 0, name_len: i32 = 0, tok_offset: i32 = 0,
    relative: bool = false, resolved_path_start: i32 = 0, resolved_path_len: i32 = 0,
    resolved_library: bool = false,
}
fn gp_grow_parse_idents(arr: ParseUniqueIdent[>..]&, new_len: i64) {
    while arr.len < new_len { arr.push(ParseUniqueIdent {}); }
}
fn gp_grow_parse_imports(arr: ParseImportRec[>..]&, new_len: i64) {
    while arr.len < new_len { arr.push(ParseImportRec {}); }
}
struct ParseSpmdFile {
    path_start: i64 = 0, path_len: i64 = 0,
    raw_start: i64 = 0, raw_len: i64 = 0,
    library: bool = false,
    worker: i64 = 0,
    // Disjoint metadata slab ranges assigned before each parse round.
    ident_start: i64 = 0, ident_cap: i64 = 0,
    import_start: i64 = 0, import_cap: i64 = 0,
    import_bytes_start: i64 = 0, import_bytes_cap: i64 = 0,
    // Phase 1 worker outputs.
    w_text_start: i64 = 0, w_tok_off: i64 = 0, w_node_off: i64 = 0,
    status: i64 = PARSE_SPMD_PENDING, root: i64 = -1,
    tok_count: i64 = 0, node_count: i64 = 0, str_count: i64 = 0,
    ident_count: i64 = 0, import_count: i64 = 0,
    saw_inline_checkfree: bool = false,
    // Midpoint Phase 2 install targets in Program arrays.
    install_ok: bool = false, source_id: i64 = -1,
    p_text_base: i64 = 0, p_str_base: i64 = 0,
    p_tok_base: i64 = 0, p_node_base: i64 = 0,
}
struct ParseSpmdCtx {
    p: Program&,
    pending: SourceRequest[>..]&,
    seen: SourceRequest[>..]&,
    root_buf: const u8[>..]&,
    stdlib_buf: const u8[>..]&,
    raw_text: u8[>..]&,
    path_pool: u8[>..]&,
    files: ParseSpmdFile[>..]&,
    ident_slab: ParseUniqueIdent[>..]&,
    import_slab: ParseImportRec[>..]&,
    import_bytes: u8[>..]&,
    installed_sources: i64[>..]&,
    phase: i64&,
    round_start: i64&,
    round_end: i64&,
    last_source: i64&,
    participants: i64&,
}

fn source_spmd_resolve_import(file_path: const u8[:], file_library: bool,
                              root: const u8[:], stdlib: const u8[:],
                              name: const u8[:], relative: bool,
                              out: u8[>..]&, out_library: bool&) -> bool {
    out.clear();
    out_library = file_library;
    if relative {
        var dir: u8[>..] = [];
        source_directory(file_path, dir);
        source_join(dir, name, out);
        return file_exists(out);
    }
    var pkg_root: u8[>..] = [];
    if file_library { pkg_root.append(stdlib); }
    else { source_directory(root, pkg_root); }
    source_join(pkg_root, name, out);
    if file_exists(out) { return true; }
    out.clear();
    if stdlib.len > 0 {
        source_join(stdlib, name, out);
        if file_exists(out) { out_library = true; return true; }
    }
    return false;
}

fn source_spmd_add_file(ctx: const ParseSpmdCtx&, path: const u8[:], library: bool) -> bool {
    if ctx.files.len >= PARSE_SPMD_MAX_FILES { return false; }
    var path_copy: u8[>..] = [];
    path_copy.append(path);
    let raw_start = ctx.raw_text.len;
    if !read_file(path_copy, ctx.raw_text) {
        return false;
    }
    let raw_len = ctx.raw_text.len - raw_start;
    let p_start = ctx.path_pool.len;
    let p_len = path_copy.len;
    ctx.path_pool.append(path_copy);
    var ident_cap = raw_len / 20 + 256;
    if ident_cap > 12000 { ident_cap = 12000; }
    let ident_start = ctx.ident_slab.len;
    gp_grow_parse_idents(ctx.ident_slab, ident_start + ident_cap);
    let import_cap: i64 = 512;
    let import_start = ctx.import_slab.len;
    gp_grow_parse_imports(ctx.import_slab, import_start + import_cap);
    let import_bytes_cap: i64 = 16384;
    let import_bytes_start = ctx.import_bytes.len;
    gp_grow_u8(ctx.import_bytes, import_bytes_start + import_bytes_cap);
    ctx.files.push(ParseSpmdFile {
        path_start: p_start, path_len: p_len,
        raw_start: raw_start, raw_len: raw_len, library: library,
        ident_start: ident_start, ident_cap: ident_cap,
        import_start: import_start, import_cap: import_cap,
        import_bytes_start: import_bytes_start, import_bytes_cap: import_bytes_cap,
    });
    return true;
}

fn source_spmd_find_file(ctx: const ParseSpmdCtx&, normalized: const u8[:]) -> i64 {
    for f, i in ctx.files {
        if same_bytes(ctx.path_pool[f.path_start..f.path_start + f.path_len], normalized) { return i; }
    }
    return -1;
}

fn source_spmd_find_seen(p: Program&, seen: const SourceRequest[:], normalized: const u8[:]) -> i64 {
    for req, i in seen {
        if same_bytes(p.text[req.start..req.start + req.length], normalized) { return i; }
    }
    return -1;
}

fn source_spmd_assign_round(ctx: const ParseSpmdCtx&, r0: i64, r1: i64, workers: i64) {
    if workers <= 1 {
        for fi in r0..r1 { ctx.files[fi].worker = 0; }
        return;
    }
    var order: i64[>..] = [];
    for fi in r0..r1 { order.push(fi); }
    for i in 1..order.len {
        let key = order[i];
        let key_len = ctx.files[key].raw_len;
        var j = i - 1;
        while j >= 0 && ctx.files[order[j]].raw_len < key_len {
            order[j + 1] = order[j];
            j -= 1;
        }
        order[j + 1] = key;
    }
    var loads: i64[>..] = [];
    loads.resize(workers, 0);
    for fi in order {
        var best: i64 = 0;
        var best_load = loads[0];
        for w in 1..workers {
            if loads[w] < best_load { best = w; best_load = loads[w]; }
        }
        ctx.files[fi].worker = best;
        loads[best] += ctx.files[fi].raw_len + 4096;
    }
}

struct ParseIdentRep {
    canonical: i32 = 0,
    hash: u32 = 0,
    start: i64 = 0, length: i64 = 0,
}

fn source_spmd_seed_idents(p: Program&, reps: ParseIdentRep[>..]&) {
    for canonical in p.ident_table {
        if canonical == 0 { continue; }
        let tok: const Token& = p.tokens[canonical - 1];
        reps.push(ParseIdentRep { canonical: canonical, hash: tok.integer as u32,
                                  start: tok.start, length: tok.end - tok.start });
    }
}

// During the merge, table entries index the dense representative list.
// Newly assigned token ranges are still untouched until workers install them.
fn source_spmd_intern(text: const u8[:], table: i32[>..]&, reps: ParseIdentRep[>..]&, candidate: ParseIdentRep) -> i32 {
    if 2 * (reps.len + 1) > table.len {
        let size = if table.len > 0 { table.len * 2 } else { 16384 };
        var old_entries: i32[>..] = [];
        old_entries.append(table);
        table.clear();
        table.resize(size, 0);
        for entry in old_entries {
            if entry == 0 { continue; }
            var slot = (reps[entry - 1].hash as i64) & (size - 1);
            while table[slot] != 0 { slot = (slot + 1) & (size - 1); }
            table[slot] = entry;
        }
    }
    let mask = table.len - 1;
    var slot = (candidate.hash as i64) & mask;
    loop {
        let entry = table[slot];
        if entry == 0 {
            reps.push(candidate);
            table[slot] = reps.len as i32;
            return candidate.canonical;
        }
        let rep = reps[entry - 1];
        if rep.hash == candidate.hash && rep.length == candidate.length {
            if same_bytes(text[rep.start..rep.start + rep.length],
                          text[candidate.start..candidate.start + candidate.length]) { return rep.canonical; }
        }
        slot = (slot + 1) & mask;
    }
}

fn source_spmd_midpoint(ctx: const ParseSpmdCtx&, reps: ParseIdentRep[>..]&) {
    let r0 = ctx.round_start;
    let r1 = ctx.round_end;
    for fi in r0..r1 {
        if ctx.files[fi].status != PARSE_SPMD_OK {
            ctx.phase = PARSE_PHASE_ABORT;
            return;
        }
    }
    var resolved_buf: u8[>..] = [];
    var norm_buf: u8[>..] = [];
    var next_round_added = false;
    for fi in r0..r1 {
        let f_path_start = ctx.files[fi].path_start;
        let f_path_len = ctx.files[fi].path_len;
        let f_lib = ctx.files[fi].library;
        let imp_start = ctx.files[fi].import_start;
        let imp_count = ctx.files[fi].import_count;
        let ib_start = ctx.files[fi].import_bytes_start;
        for k in 0..imp_count {
            let rec = ctx.import_slab[imp_start + k];
            let ns = ib_start + (rec.name_start as i64);
            let name = ctx.import_bytes[ns..ns + (rec.name_len as i64)];
            var imp_lib = f_lib;
            if !source_spmd_resolve_import(ctx.path_pool[f_path_start..f_path_start + f_path_len], f_lib,
                                           ctx.root_buf[..], ctx.stdlib_buf[..], name, rec.relative, resolved_buf, imp_lib) {
                ctx.phase = PARSE_PHASE_ABORT;
                return;
            }
            norm_buf.clear();
            source_normalize(resolved_buf, norm_buf);
            let rp_start = ctx.path_pool.len;
            ctx.path_pool.append(norm_buf);
            ctx.import_slab[imp_start + k].resolved_path_start = rp_start as i32;
            ctx.import_slab[imp_start + k].resolved_path_len = norm_buf.len as i32;
            ctx.import_slab[imp_start + k].resolved_library = imp_lib;
            let seen_i = source_spmd_find_seen(ctx.p, ctx.seen, norm_buf);
            if seen_i >= 0 && ctx.seen[seen_i].source != -1 { continue; }
            if source_spmd_find_file(ctx, norm_buf) >= 0 { continue; }
            if !source_spmd_add_file(ctx, norm_buf, imp_lib) {
                ctx.phase = PARSE_PHASE_ABORT;
                return;
            }
            next_round_added = true;
        }
    }
    if next_round_added {
        ctx.round_start = r1;
        ctx.round_end = ctx.files.len;
        source_spmd_assign_round(ctx, r1, ctx.files.len, ctx.participants);
        ctx.phase = PARSE_PHASE_PARSE;
        return;
    }

    // Complete transitive closure is parsed and verified. Run the exact serial
    // DFS schedule to assign final Source, text, token, and node ranges.
    let p: Program& = ctx.p;
    var work: SourceRequest[>..] = [];
    work.append(ctx.pending);
    var tok_cursor = p.tokens.len;
    var node_cursor = p.nodes.len;
    var dfs_files: i64[>..] = [];
    while work.len > 0 {
        let request = work.pop();
        if request.source >= 0 {
            if ctx.last_source >= 0 { p.sources[ctx.last_source].next_decl = request.source; }
            else { p.first_decl_source = request.source; }
            ctx.last_source = request.source;
            continue;
        }
        if ctx.seen[request.index].source != -1 { continue; }
        let req_path = p.text[request.start..request.start + request.length];
        let fi = source_spmd_find_file(ctx, req_path);
        if fi < 0 {
            // Should never happen because closure is complete; keep defensive guard.
            ctx.phase = PARSE_PHASE_ABORT;
            return;
        }
        let source_id = p.sources.len;
        ctx.seen[request.index].source = source_id;
        let text_base = p.text.len;
        let raw_start = ctx.files[fi].raw_start;
        let raw_len = ctx.files[fi].raw_len;
        p.text.append(ctx.raw_text[raw_start..raw_start + raw_len]);
        let str_base = p.text.len;
        let str_count = ctx.files[fi].str_count;
        if str_count > 0 { gp_grow_u8(p.text, str_base + str_count); }
        let tok_base = tok_cursor;
        let tok_count = ctx.files[fi].tok_count;
        tok_cursor += tok_count;
        let node_base = node_cursor;
        let node_count = ctx.files[fi].node_count;
        node_cursor += node_count;
        let module = node_base + ctx.files[fi].root;
        p.sources.push(Source {
            path_start: request.start, path_len: request.length,
            text_start: text_base, text_len: raw_len,
            token_start: tok_base, token_end: tok_base + tok_count,
            root: module, library: request.library,
        });
        if ctx.files[fi].saw_inline_checkfree { p.saw_inline_checkfree = true; }
        ctx.files[fi].install_ok = true;
        ctx.files[fi].source_id = source_id;
        ctx.files[fi].p_text_base = text_base;
        ctx.files[fi].p_str_base = str_base;
        ctx.files[fi].p_tok_base = tok_base;
        ctx.files[fi].p_node_base = node_base;
        dfs_files.push(fi);
        ctx.installed_sources.push(source_id);

        work.push(SourceRequest { start: 0, length: 0, source: source_id });
        let imports_start = work.len;
        let imp_start = ctx.files[fi].import_start;
        let imp_count = ctx.files[fi].import_count;
        for k in 0..imp_count {
            let rec = ctx.import_slab[imp_start + k];
            let rps = rec.resolved_path_start as i64;
            let rp = ctx.path_pool[rps..rps + (rec.resolved_path_len as i64)];
            source_request(p, work, ctx.seen, rp, tok_base + rec.tok_offset as i64, -1, rec.resolved_library);
        }
        var left = imports_start; var right = work.len - 1;
        while left < right {
            let swap = work[left]; work[left] = work[right]; work[right] = swap;
            left += 1; right -= 1;
        }
    }

    // The seed list follows the existing table's slot order.
    let text: const u8[:] = p.text;
    let table = p.ident_table;
    var seed: i32 = 0;
    for i in 0..table.len {
        if table[i] != 0 {
            seed += 1;
            table[i] = seed;
        }
    }
    for fi in dfs_files {
        let f = ctx.files[fi];
        for u in f.ident_start..f.ident_start + f.ident_count {
            let entry = ctx.ident_slab[u];
            let candidate = ParseIdentRep {
                canonical: (f.p_tok_base + entry.first_local_tok as i64 + 1) as i32,
                hash: entry.hash, start: f.p_text_base + entry.rel_start as i64,
                length: (entry.rel_end - entry.rel_start) as i64,
            };
            let canonical = source_spmd_intern(text, table, reps, candidate);
            ctx.ident_slab[u].canonical = canonical;
        }
    }
    for i in 0..table.len {
        let entry = table[i];
        if entry != 0 { table[i] = reps[entry - 1].canonical; }
    }
    p.ident_count = reps.len;

    // Extend the final arrays without initializing their worker-owned ranges.
    gp_grow_tokens(p.tokens, tok_cursor);
    gp_grow_nodes(p.nodes, node_cursor);
    ctx.phase = PARSE_PHASE_INSTALL;
}

fn gp_parse_spmd_dispatch(jobs: i64, ctx: const ParseSpmdCtx&, out: i64[:]) -> bool {
    gp_parse_spmd_range(ctx, out, 0, 1);
    return true;
}

fn gp_parse_spmd_range(ctx: const ParseSpmdCtx&, out: i64[:], worker_id: i64, worker_count: i64) {
    let _keep_out = out.len;
    var w_text: u8[>..] = []; var w_messages: u8[>..] = []; var w_sources: Source[>..] = [];
    var w_tokens: Token[>..] = []; var w_nodes: Node[>..] = []; var w_diagnostics: Diagnostic[>..] = [];
    var w_types: Type[>..] = []; var w_symbols: Symbol[>..] = [];
    var w_type_properties: i64[>..] = []; var w_builtin_symbols: i64[>..] = [];
    var w_type_buckets: TypeBucket[>..] = []; var w_type_links: TypeLink[>..] = [];
    var w_type_scan_marks: i64[>..] = []; var w_type_holds: i64[>..] = [];
    var w_inline_sites: InlineSite[>..] = []; var w_instantiation_stack: InstantiationSite[>..] = [];
    var w_region_profile: i64[>..] = []; var w_ident_table: i32[>..] = [];
    var local = Program {
        text: w_text, messages: w_messages, sources: w_sources, tokens: w_tokens, nodes: w_nodes,
        diagnostics: w_diagnostics, types: w_types, symbols: w_symbols,
        type_properties: w_type_properties, builtin_symbols: w_builtin_symbols,
        type_buckets: w_type_buckets, type_links: w_type_links,
        type_scan_marks: w_type_scan_marks, type_holds: w_type_holds,
        inline_sites: w_inline_sites, instantiation_stack: w_instantiation_stack,
        region_profile: w_region_profile, ident_table: w_ident_table,
    };
    var w_htab: i32[>..] = [];
    var imp_name: u8[>..] = [];
    var reps: ParseIdentRep[>..] = [];
    if worker_id == 0 { source_spmd_seed_idents(ctx.p, reps); }

    loop {
        let r0 = ctx.round_start;
        let r1 = ctx.round_end;
        for fi in r0..r1 {
            if worker_count > 1 && ctx.files[fi].worker != worker_id { continue; }
            let f = ctx.files[fi];
            let w_text_start = w_text.len;
            w_text.append(ctx.raw_text[f.raw_start..f.raw_start + f.raw_len]);
            let w_src = w_sources.len;
            w_sources.push(Source { text_start: w_text_start, text_len: f.raw_len, library: f.library });
            let w_tok_off = w_tokens.len;
            let w_node_off = w_nodes.len;
            local.saw_inline_checkfree = false;
            lex_source(local, w_src, f.library, false);
            var ok = w_diagnostics.len == 0;
            var root: i64 = -1;
            if ok {
                root = parse_source(local, w_src);
                ok = w_diagnostics.len == 0;
            }
            if !ok {
                w_diagnostics.clear();
                ctx.files[fi].status = PARSE_SPMD_FALLBACK;
                continue;
            }
            let w_str_off = w_text_start + f.raw_len;
            let str_count = w_text.len - w_str_off;
            let tok_count = w_tokens.len - w_tok_off;
            let node_count = w_nodes.len - w_node_off;

            // Collect top-level imports for midpoint closure resolution.
            var imp_count: i64 = 0;
            var ib_used: i64 = 0;
            var decl = w_nodes[root].first;
            while decl >= 0 {
                let dn = w_nodes[decl];
                if dn.kind == N_IMPORT {
                    if dn.left >= 0 || imp_count >= f.import_cap { ok = false; break; }
                    imp_name.clear();
                    source_import_name(local, dn.integer, dn.aux, imp_name);
                    if ib_used + imp_name.len > f.import_bytes_cap { ok = false; break; }
                    for bi in 0..imp_name.len { ctx.import_bytes[f.import_bytes_start + ib_used + bi] = imp_name[bi]; }
                    ctx.import_slab[f.import_start + imp_count] = ParseImportRec {
                        name_start: ib_used as i32, name_len: imp_name.len as i32,
                        tok_offset: (dn.token - w_tok_off) as i32,
                        relative: (dn.flags & F_REFERENCE) != 0,
                    };
                    ib_used += imp_name.len;
                    imp_count += 1;
                }
                decl = dn.next;
            }
            if !ok {
                ctx.files[fi].status = PARSE_SPMD_FALLBACK;
                continue;
            }

            // A slot packs the file's tag and its one-based unique index.
            // File indices are monotonic within the wave, even across rounds.
            let tag = ((fi + 1) * PARSE_SPMD_IDENT_SLOTS) as i32;
            if w_htab.len == 0 { w_htab.resize(PARSE_SPMD_IDENT_SLOTS, 0); }
            let table: i32[:] = w_htab;
            let idents: ParseUniqueIdent[:] = ctx.ident_slab[f.ident_start..f.ident_start + f.ident_cap];
            let tokens: Token[:] = w_tokens[w_tok_off..];
            let text: const u8[:] = w_text;
            var u_count: i64 = 0;
            for tk in 0..tokens.len {
                let tok: Token& = tokens[tk];
                if tok.kind != T_IDENT { continue; }
                let h = tok.integer as u32;
                let tstart = tok.start;
                let tend = tok.end;
                let tlen = tend - tstart;
                var slot = (h as i64) & (PARSE_SPMD_IDENT_SLOTS - 1);
                loop {
                    let entry = table[slot];
                    if entry <= tag {
                        if u_count >= idents.len { ok = false; break; }
                        idents[u_count] = ParseUniqueIdent {
                            first_local_tok: tk as i32,
                            rel_start: (tstart - w_text_start) as i32,
                            rel_end: (tend - w_text_start) as i32,
                            hash: h,
                        };
                        table[slot] = tag + u_count as i32 + 1;
                        tok.text_start = u_count as i32;
                        u_count += 1;
                        break;
                    }
                    let u = (entry - tag - 1) as i64;
                    let ent = idents[u];
                    if ent.hash == h && (ent.rel_end - ent.rel_start) as i64 == tlen {
                        let rs = w_text_start + ent.rel_start as i64;
                        // FNV-1a is injective for one-byte spellings.
                        if tlen == 1 || same_bytes(text[rs..rs + tlen], text[tstart..tend]) {
                            tok.text_start = u as i32;
                            break;
                        }
                    }
                    slot = (slot + 1) & (PARSE_SPMD_IDENT_SLOTS - 1);
                }
                if !ok { break; }
            }
            if !ok {
                ctx.files[fi].status = PARSE_SPMD_FALLBACK;
                continue;
            }
            ctx.files[fi].w_text_start = w_text_start;
            ctx.files[fi].w_tok_off = w_tok_off;
            ctx.files[fi].w_node_off = w_node_off;
            ctx.files[fi].root = root - w_node_off;
            ctx.files[fi].tok_count = tok_count;
            ctx.files[fi].node_count = node_count;
            ctx.files[fi].str_count = str_count;
            ctx.files[fi].ident_count = u_count;
            ctx.files[fi].import_count = imp_count;
            ctx.files[fi].saw_inline_checkfree = local.saw_inline_checkfree;
            ctx.files[fi].status = PARSE_SPMD_OK;
        }

        gp_barrier();
        if worker_id == 0 { source_spmd_midpoint(ctx, reps); }
        gp_barrier();

        if ctx.phase == PARSE_PHASE_INSTALL {
            // Phase 2: parallel relocation and copy directly into final Program slices.
            for f in ctx.files {
                if !f.install_ok || (worker_count > 1 && f.worker != worker_id) { continue; }
                let w_str_off = f.w_text_start + f.raw_len;
                let delta_text = f.p_text_base - f.w_text_start;
                let delta_str = f.p_str_base - w_str_off;
                let delta_tok = f.p_tok_base - f.w_tok_off;
                let delta_node = f.p_node_base - f.w_node_off;
                let str_count = f.str_count;
                if str_count > 0 {
                    let dst_str: u8[:] = ctx.p.text[f.p_str_base..f.p_str_base + str_count];
                    let src_str: const u8[:] = w_text[w_str_off..w_str_off + str_count];
                    dst_str.move_from(src_str);
                }
                let sid = f.source_id;
                let istart = f.ident_start;
                let str_split = w_str_off;
                let tok_count = f.tok_count;
                let dst_toks: Token[:] = ctx.p.tokens[f.p_tok_base..f.p_tok_base + tok_count];
                let src_toks: const Token[:] = w_tokens[f.w_tok_off..f.w_tok_off + tok_count];
                let ident_slice: const ParseUniqueIdent[:] = ctx.ident_slab[istart..istart + f.ident_count];
                for tok, ti in src_toks {
                    var dt = tok;
                    dt.source = sid as i32;
                    dt.start = (dt.start + delta_text) as i32;
                    dt.end = (dt.end + delta_text) as i32;
                    if dt.kind == T_IDENT {
                        dt.text_start = ident_slice[dt.text_start].canonical;
                    } else {
                        if dt.kind == T_LAZY_BODY { dt.integer += delta_text; }
                        if dt.text_start != 0 {
                            let delta = if dt.text_start < str_split { delta_text } else { delta_str };
                            dt.text_start = (dt.text_start + delta) as i32;
                        }
                    }
                    dst_toks[ti] = dt;
                }
                let node_count = f.node_count;
                let dst_nodes: Node[:] = ctx.p.nodes[f.p_node_base..f.p_node_base + node_count];
                let src_nodes: const Node[:] = w_nodes[f.w_node_off..f.w_node_off + node_count];
                for node, ni in src_nodes {
                    var dn = node;
                    parse_rebase_node(dn, delta_tok, delta_node);
                    dst_nodes[ni] = dn;
                }
            }
            // A negative grow length records dead native worker storage.
            if worker_id != 0 {
                gp_grow_tokens(w_tokens, -1);
                gp_grow_nodes(w_nodes, -1);
            }
            break;
        }
        if ctx.phase == PARSE_PHASE_ABORT { break; }
    }
}

fn source_parse_wave_spmd(p: Program&, pending: SourceRequest[>..]&, seen: SourceRequest[>..]&,
                          root: const u8[:], stdlib: const u8[:], last_source: i64&) -> bool {
    var raw_text: u8[>..] = [];
    var path_pool: u8[>..] = [];
    var files: ParseSpmdFile[>..] = [];
    var ident_slab: ParseUniqueIdent[>..] = [];
    var import_slab: ParseImportRec[>..] = [];
    var import_bytes: u8[>..] = [];
    var installed_sources: i64[>..] = [];
    var phase: i64 = PARSE_PHASE_PARSE;
    var round_start: i64 = 0;
    var round_end: i64 = 0;
    var participants: i64 = p.jobs;
    if participants > 16 { participants = 16; }
    if !gp_native_available() { participants = 1; }
    var root_buf: u8[>..] = []; root_buf.append(root);
    var stdlib_buf: u8[>..] = []; stdlib_buf.append(stdlib);
    let ctx = ParseSpmdCtx {
        p: p, pending: pending, seen: seen, root_buf: root_buf, stdlib_buf: stdlib_buf,
        raw_text: raw_text, path_pool: path_pool, files: files,
        ident_slab: ident_slab, import_slab: import_slab, import_bytes: import_bytes,
        installed_sources: installed_sources,
        phase: phase, round_start: round_start, round_end: round_end, last_source: last_source,
        participants: participants,
    };
    var at = pending.len;
    while at > 0 {
        at--;
        let req = pending[at];
        if req.source >= 0 || seen[req.index].source != -1 { continue; }
        let path = p.text[req.start..req.start + req.length];
        if source_spmd_find_file(ctx, path) >= 0 { continue; }
        if !source_spmd_add_file(ctx, path, req.library) { return false; }
    }
    if files.len < 2 { return false; }
    round_end = files.len;
    source_spmd_assign_round(ctx, 0, round_end, participants);
    var worker_slots: i64[>..] = [];
    worker_slots.resize(participants, 0);
    gp_parse_spmd_dispatch(p.jobs, ctx, worker_slots[..]);
    if phase != PARSE_PHASE_INSTALL { return false; }
    pending.clear();
    // Strip any non-root fn main() declarations after parallel install.
    for sid in installed_sources {
        if sid <= 0 { continue; }
        let module = p.sources[sid].root;
        var decl = p.nodes[module].first;
        var prev = -1;
        while decl >= 0 {
            let next = p.nodes[decl].next;
            let n = p.nodes[decl];
            if n.kind == N_FUNCTION && token_is(p, n.token, "main") {
                if prev < 0 { p.nodes[module].first = next; }
                else { p.nodes[prev].next = next; }
                if p.nodes[module].last == decl { p.nodes[module].last = prev as i32; }
                decl = next;
                continue;
            }
            prev = decl;
            decl = next;
        }
    }
    return true;
}

fn load_sources(p: Program&, root: const u8[:], stdlib: const u8[:], tokens_only: bool = false) {
    var pending: SourceRequest[>..] = [];
    var seen: SourceRequest[>..] = [];
    var packages: SourcePackage[>..] = [];
    var parallel = p.jobs > 1 && !tokens_only;
    source_request(p, pending, seen, root, -1);
    p.first_decl_source = -1; var last_source = -1;
    while pending.len > 0 {
        let request = pending.pop();
        if request.source >= 0 {
            if last_source >= 0 { p.sources[last_source].next_decl = request.source; }
            else { p.first_decl_source = request.source; }
            last_source = request.source; continue;
        }
        if seen[request.index].source != -1 { continue; }
        var path: u8[>..] = [];
        path.append(p.text[request.start..request.start + request.length]);
        var contents: u8[>..] = [];
        if !read_file(path, contents) {
            seen[request.index].source = -2;
            diagnose(p, request.token, "cannot open source file"); continue;
        }
        let source_id = p.sources.len; seen[request.index].source = source_id;
        let start = p.text.len;
        p.text.append(contents);
        p.sources.push(Source { path_start: request.start, path_len: request.length,
                               text_start: start, text_len: contents.len, library: request.library });
        lex_source(p, source_id, request.library && !tokens_only);
        if tokens_only { continue; }
        let module = parse_source(p, source_id);
        pending.push(SourceRequest { start: 0, length: 0, source: source_id });
        let imports_start = pending.len;
        var directory: u8[>..] = [];
        source_directory(path, directory);
        var package_root: u8[>..] = [];
        if request.package >= 0 {
            let package = packages[request.package]; package_root.append(p.text[package.start..package.start + package.length]);
        } else if request.library { package_root.append(stdlib); }
        else { source_directory(root, package_root); }
        var declaration = p.nodes[module].first;
        var previous = -1;
        while declaration >= 0 {
            let next = p.nodes[declaration].next;
            let n = p.nodes[declaration];
            if source_id > 0 && n.kind == N_FUNCTION && token_is(p, n.token, "main") {
                if previous < 0 { p.nodes[module].first = next; }
                else { p.nodes[previous].next = next; }
                if p.nodes[module].last == declaration { p.nodes[module].last = previous as i32; }
                declaration = next; continue;
            }
            if p.nodes[declaration].kind == N_IMPORT {
                var imported: u8[>..] = [];
                var package = request.package; var library = request.library;
                if source_import_path(p, declaration, directory, package_root, stdlib, packages, source_id == 0,
                                      request.package, package, imported, library) {
                    source_request(p, pending, seen, imported, p.nodes[declaration].token, package, library);
                }
            }
            previous = declaration;
            declaration = next;
        }
        // The LIFO work list visits imports in written order, then appends
        // this source's postvisit marker to the declaration schedule.
        var left = imports_start; var right = pending.len - 1;
        while left < right {
            let swap = pending[left]; pending[left] = pending[right]; pending[right] = swap;
            left += 1; right -= 1;
        }
        if parallel && packages.len == 0 && p.diagnostics.len == 0 && pending.len - imports_start >= 2 {
            if !source_parse_wave_spmd(p, pending, seen, root, stdlib, last_source) { parallel = false; }
        }
    }
}
