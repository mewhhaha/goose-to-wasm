import model;
import lexer;
import parser;
import os;

struct SourceRequest { start: i64, length: i64, token: i64 = -1 }

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
                  path: const u8[:], token: i64) {
    var normalized: u8[>..] = [];
    source_normalize(path, normalized);
    for request in seen {
        if same_bytes(p.text[request.start..request.start + request.length], normalized) { return; }
    }
    let start = p.text.len;
    p.text.append(normalized);
    let request = SourceRequest { start: start, length: normalized.len, token: token };
    pending.push(request); seen.push(request);
}
fn source_import_path(p: Program&, node: i64, directory: const u8[:], stdlib: const u8[:], out: u8[>..]&) -> bool {
    let n = p.nodes[node];
    var name: u8[>..] = [];
    for token in n.integer..n.aux + 1 {
        let t = p.tokens[token];
        if t.kind == T_DOT { name.push('/'); }
        else { name.append(p.text[t.start..t.end]); }
    }
    if n.left >= 0 {
        let t = p.tokens[n.left];
        var package: u8[>..] = [];
        package.append(p.text[t.text_start..t.text_start + t.text_len]);
        if !source_absolute(package) { out.append(directory); }
        out.append(package);
        if out.len > 0 && out[out.len - 1] != '/' { out.push('/'); }
        out.append(name); out.append(".goose");
        if file_exists(out) { return true; }
        out.clear();
        if !source_absolute(package) { out.append(directory); }
        out.append(package); out.append("/main.goose");
        if file_exists(out) { return true; }
        diagnose(p, n.token, "cannot resolve package entry; remote package retrieval is not implemented");
        return false;
    }
    out.append(directory); out.append(name); out.append(".goose");
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
fn load_sources(p: Program&, root: const u8[:], stdlib: const u8[:]) {
    var pending: SourceRequest[>..] = [];
    var seen: SourceRequest[>..] = [];
    source_request(p, pending, seen, root, -1);
    while pending.len > 0 {
        let request = pending.pop();
        var path: u8[>..] = [];
        path.append(p.text[request.start..request.start + request.length]);
        var contents: u8[>..] = [];
        if !read_file(path, contents) {
            diagnose(p, request.token, "cannot open source file"); continue;
        }
        let source_id = p.sources.len;
        let start = p.text.len;
        p.text.append(contents);
        p.sources.push(Source { path_start: request.start, path_len: request.length,
                               text_start: start, text_len: contents.len });
        lex_source(p, source_id);
        let module = parse_source(p, source_id);
        var directory: u8[>..] = [];
        source_directory(path, directory);
        var declaration = p.nodes[module].first;
        while declaration >= 0 {
            let next = p.nodes[declaration].next;
            if p.nodes[declaration].kind == N_IMPORT {
                var imported: u8[>..] = [];
                if source_import_path(p, declaration, directory, stdlib, imported) {
                    source_request(p, pending, seen, imported, p.nodes[declaration].token);
                }
            }
            declaration = next;
        }
    }
}
