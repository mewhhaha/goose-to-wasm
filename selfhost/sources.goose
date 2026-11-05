import model;
import lexer;
import parser;
import os;

struct SourceRequest { start: i64, length: i64, token: i64 = -1, package: i64 = -1, source: i64 = -1, index: i64 = -1 }
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
    while at < path.len {
        while at < path.len && (path[at] == '/' || path[at] == '\\') { at++; }
        let start = at;
        while at < path.len && path[at] != '/' && path[at] != '\\' { at++; }
        let length = at - start;
        if length == 0 || length == 1 && path[start] == '.' { continue; }
        if length == 2 && path[start] == '.' && path[start + 1] == '.' {
            if starts.len > 0 {
                let last = starts.len - 1;
                if sizes[last] != 2 || path[starts[last]] != '.' || path[starts[last] + 1] != '.' {
                    starts.pop(); sizes.pop(); continue;
                }
            }
            if absolute { continue; }
        }
        starts.push(start); sizes.push(length);
    }
    if absolute && path[0] == '/' { out.push('/'); }
    for start, i in starts {
        if out.len > 0 && out[out.len - 1] != '/' { out.push('/'); }
        out.append(path[start..start + sizes[i]]);
    }
    if out.len == 0 { out.append("."); }
}
fn source_request(p: Program&, pending: SourceRequest[>..]&, seen: SourceRequest[>..]&,
                  path: const u8[:], token: i64, package: i64 = -1) {
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
    let request = SourceRequest { start: start, length: normalized.len, token: token, package: package, index: seen.len };
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
    let source = p.sources[source_id]; var token = call; token.kind = T_STRLIT;
    token.text_start = source.text_start; token.text_len = source.text_len;
    let token_id = p.tokens.len; p.tokens.push(token);
    return new_node(p, N_STRING, token_id);
}
fn source_package_entry(p: Program&, directory: const u8[:], module: const u8[:], out: u8[>..]&) -> bool {
    out.append(directory);
    if out.len > 0 && out[out.len - 1] != '/' { out.push('/'); }
    if module.len > 0 { out.append(module); out.append(".goose"); }
    else { out.append("main.goose"); }
    return file_exists(out);
}
fn source_import_path(p: Program&, node: i64, directory: const u8[:], stdlib: const u8[:],
                      packages: SourcePackage[>..]&, current_package: i64,
                      resolved_package: i64&, out: u8[>..]&) -> bool {
    let n = p.nodes[node];
    var name: u8[>..] = [];
    for token in n.integer..n.aux + 1 {
        let t = p.tokens[token];
        if t.kind == T_DOT { name.push('/'); }
        else { name.append(p.text[t.start..t.end]); }
    }
    if n.left >= 0 {
        let t = p.tokens[n.left];
        var raw: u8[>..] = [];
        let package = p.text[t.text_start..t.text_start + t.text_len];
        if !source_absolute(package) { raw.append(directory); }
        raw.append(package);
        var normalized: u8[>..] = []; source_normalize(raw, normalized);
        var index = source_package(p, packages, n.token);
        if current_package < 0 {
            if index >= 0 { diagnose(p, n.token, "package is declared twice"); return false; }
            let start = p.text.len; p.text.append(normalized);
            index = packages.len; packages.push(SourcePackage { name: n.token, start: start, length: normalized.len });
        } else {
            if index < 0 { diagnose(p, n.token, "package requirement is not declared by the root"); return false; }
            let declared = packages[index];
            if !same_bytes(normalized, p.text[declared.start..declared.start + declared.length]) {
                diagnose(p, n.token, "required package is declared from a different source"); return false;
            }
        }
        resolved_package = index;
        if source_package_entry(p, normalized, name, out) { return true; }
        out.clear();
        if source_package_entry(p, normalized, "", out) { return true; }
        diagnose(p, n.token, "cannot resolve package entry; remote package retrieval is not implemented");
        return false;
    }
    out.append(directory); out.append(name); out.append(".goose");
    let package_index = source_package(p, packages, n.token);
    if package_index >= 0 && (n.flags & F_REFERENCE) == 0 {
        if file_exists(out) { diagnose(p, n.token, "import is both a local file and a declared package module"); return false; }
        var module: u8[>..] = [];
        for token in n.integer + 2..n.aux + 1 {
            let t = p.tokens[token];
            if t.kind == T_DOT { module.push('/'); } else { module.append(p.text[t.start..t.end]); }
        }
        let declared = packages[package_index]; out.clear(); resolved_package = package_index;
        if source_package_entry(p, p.text[declared.start..declared.start + declared.length], module, out) { return true; }
        diagnose(p, n.token, "cannot open declared package module"); return false;
    }
    if file_exists(out) { return true; }
    if (n.flags & F_REFERENCE) != 0 {
        diagnose(p, n.token, "cannot open relative import"); return false;
    }
    out.clear();
    if stdlib.len > 0 {
        out.append(stdlib);
        if out[out.len - 1] != '/' { out.push('/'); }
        out.append(name); out.append(".goose");
        if file_exists(out) { return true; }
    }
    diagnose(p, n.token, "cannot resolve import; pass --stdlib or set GOOSE_STDLIB");
    return false;
}
fn load_sources(p: Program&, root: const u8[:], stdlib: const u8[:], tokens_only: bool = false) {
    var pending: SourceRequest[>..] = [];
    var seen: SourceRequest[>..] = [];
    var packages: SourcePackage[>..] = [];
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
                               text_start: start, text_len: contents.len });
        lex_source(p, source_id);
        if tokens_only { continue; }
        let module = parse_source(p, source_id);
        pending.push(SourceRequest { start: 0, length: 0, source: source_id });
        let imports_start = pending.len;
        var directory: u8[>..] = [];
        source_directory(path, directory);
        var declaration = p.nodes[module].first;
        var previous = -1;
        while declaration >= 0 {
            let next = p.nodes[declaration].next;
            let n = p.nodes[declaration];
            if source_id > 0 && n.kind == N_FUNCTION && token_is(p, n.token, "main") {
                if previous < 0 { p.nodes[module].first = next; }
                else { p.nodes[previous].next = next; }
                if p.nodes[module].last == declaration { p.nodes[module].last = previous; }
                declaration = next; continue;
            }
            if p.nodes[declaration].kind == N_IMPORT {
                var imported: u8[>..] = [];
                var package = request.package;
                if source_import_path(p, declaration, directory, stdlib, packages, request.package, package, imported) {
                    source_request(p, pending, seen, imported, p.nodes[declaration].token, package);
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
    }
}
