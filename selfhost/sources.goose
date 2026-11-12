import model;
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
    let source = p.sources[source_id]; var token = call; token.kind = T_STRLIT;
    token.text_start = source.text_start; token.text_len = source.text_len;
    let token_id = p.tokens.len; p.tokens.push(token);
    return new_node(p, N_STRING, token_id);
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
    if source_blessed(p, n.integer) {
        diagnose(p, n.token, "blessed packages are not yet supported: remote package retrieval is not implemented"); return false;
    }
    var looked: u8[>..] = []; looked.append(out); out.clear();
    if stdlib.len > 0 {
        source_join(stdlib, name, out);
        if file_exists(out) { library = true; resolved_package = -1; return true; }
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
                if p.nodes[module].last == declaration { p.nodes[module].last = previous; }
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
    }
}
