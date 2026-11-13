import model;
import sources;
import checker;
import optimizer;
import codegen;
import codegen_c;
import os;

// Process execution is an OS service; compiler stages run in this program.
extern "libc.so.6" {
    fn driver_system(command: const u8&) -> i32 = "system";
}

struct DriverOptions {
    source_arg: i64 = -1, output_arg: i64 = -1, stdlib_arg: i64 = -1,
    stats_arg: i64 = -1, dependencies_arg: i64 = -1, cc_arg: i64 = -1,
    target: i64 = 0, optimization: i64 = 0, initial_pages: i64 = 16, maximum_pages: i64 = 256,
    check: bool = false, parse: bool = false, tokens: bool = false,
    dump: bool = false, dump_ir: bool = false, run: bool = false, debug: bool = false, library: bool = false, reachable_program: bool = false, expansion_limit: i64 = 100000,
    help: bool = false, version: bool = false, bad: bool = false,
}
fn driver_integer(out: u8[>..]&, value: i64) {
    var digits: u8[>..] = [];
    var n = value as! u64;
    if value < 0 { out.push('-'); n = (-(value + 1)) as u64 + 1; }
    loop {
        digits.push((n % 10) as u8 + '0'); n /= 10;
        if n == 0 { break; }
    }
    var i = digits.len;
    while i > 0 { i--; out.push(digits[i]); }
}
fn driver_json(out: u8[>..]&, text: const u8[:]) {
    out.push('"');
    for byte in text {
        if byte == '"' || byte == '\\' { out.push('\\'); out.push(byte); }
        else if byte == 10 { out.append("\\n"); }
        else if byte == 13 { out.append("\\r"); }
        else if byte == 9 { out.append("\\t"); }
        else if byte < 32 {
            out.append("\\u00"); out.push("0123456789abcdef"[byte >> 4]); out.push("0123456789abcdef"[byte & 15]);
        } else { out.push(byte); }
    }
    out.push('"');
}
fn driver_string_literal(out: u8[>..]&, text: const u8[:]) {
    out.push('"');
    for byte in text {
        if byte == '"' || byte == '\\' || byte == 39 { out.push('\\'); out.push(byte); }
        else if byte == 0 { out.append("\\0"); }
        else if byte == 10 { out.append("\\n"); }
        else if byte == 13 { out.append("\\r"); }
        else if byte == 9 { out.append("\\t"); }
        else if byte < 32 || byte == 127 {
            out.append("\\x"); out.push("0123456789abcdef"[byte >> 4]); out.push("0123456789abcdef"[byte & 15]);
        } else { out.push(byte); }
    }
    out.push('"');
}
fn driver_tokens(p: Program&) {
    var out: u8[>..] = [];
    for token in p.tokens {
        if token.kind == T_EOF { continue; }
        let spelling = p.text[token.start..token.end];
        if token.kind == T_IDENT { out.append("identifier "); out.append(spelling); }
        else if token.kind == T_INTLIT {
            out.append("integer literal "); driver_integer(out, token.integer);
            out.append(" ("); out.append(spelling); out.push(')');
        } else if token.kind == T_FLTLIT { out.append("float literal "); out.format(token.float_value); }
        else if token.kind == T_STRLIT {
            out.append("string literal "); driver_string_literal(out, p.text[token.text_start..token.text_start + token.text_len]);
        } else { out.append(spelling); }
        out.push('\n');
    }
    write_stdout(out);
}
fn driver_number(text: const u8[:]) -> i64, bool {
    var n: i64 = 0;
    if text.len == 0 { return 0, false; }
    for byte in text {
        if byte < '0' || byte > '9' { return 0, false; }
        if n > (9223372036854775807 - (byte - '0') as i64) / 10 { return 0, false; }
        n = n * 10 + (byte - '0') as i64;
    }
    return n, true;
}
fn driver_error(message: const u8[:]) { write_stderr("goose: "); write_stderr(message); write_stderr("\n"); }
// Paths compare in the normalized form sources are recorded in; an absolute
// spelling of a relative path is not recognized without a filesystem query.
fn driver_same_path(a: const u8[:], b: const u8[:]) -> bool {
    var left: u8[>..] = []; var right: u8[>..] = [];
    source_normalize(a, left); source_normalize(b, right);
    return same_bytes(left, right);
}
fn driver_source_path(p: Program&, path: const u8[:]) -> bool {
    for source in p.sources {
        if driver_same_path(path, p.text[source.path_start..source.path_start + source.path_len]) { return true; }
    }
    return false;
}
// Refuses an output that would replace a source, an embedded file or another
// output, before anything is written.
fn driver_outputs_distinct(p: Program&, output: const u8[:], stats: const u8[:], dependencies: const u8[:]) -> bool {
    if output.len > 0 && driver_source_path(p, output) { driver_error("output would overwrite a source file"); return false; }
    if stats.len > 0 && (driver_source_path(p, stats) || output.len > 0 && driver_same_path(stats, output)) {
        driver_error("statistics would overwrite a source file or the output"); return false;
    }
    if dependencies.len > 0 && (driver_source_path(p, dependencies) || output.len > 0 && driver_same_path(dependencies, output) ||
                                stats.len > 0 && driver_same_path(dependencies, stats)) {
        driver_error("dependency manifest would overwrite a source file or another output"); return false;
    }
    return true;
}
fn driver_options(o: DriverOptions&, arguments: u8[:][:]) {
    var at = 1;
    while at < arguments.len {
        let a = arguments[at]; at++;
        if same_bytes(a, "--help") || same_bytes(a, "-h") { o.help = true; }
        else if same_bytes(a, "--version") { o.version = true; }
        else if same_bytes(a, "--check") { o.check = true; }
        else if same_bytes(a, "--parse") { o.parse = true; }
        else if same_bytes(a, "--tokens") { o.tokens = true; }
        else if same_bytes(a, "--dump") { o.dump = true; }
        else if same_bytes(a, "--dump-ir") { o.dump_ir = true; }
        else if same_bytes(a, "--run") { o.run = true; }
        else if same_bytes(a, "--debug") { o.debug = true; }
        else if same_bytes(a, "--library") { o.library = true; }
        else if same_bytes(a, "--reachable-program") { o.reachable_program = true; }
        else if same_bytes(a, "--standalone") { /* C output is standalone. */ }
        else if same_bytes(a, "-O0") { o.optimization = 0; }
        else if same_bytes(a, "-O1") { o.optimization = 1; }
        else if same_bytes(a, "-O2") { o.optimization = 2; }
        else if same_bytes(a, "-o") || same_bytes(a, "--stdlib") || same_bytes(a, "--wasm-stats") ||
                same_bytes(a, "--wasm-deps") || same_bytes(a, "--cc") || same_bytes(a, "--target") ||
                same_bytes(a, "--wasm-initial-pages") || same_bytes(a, "--wasm-max-pages") || same_bytes(a, "--expansion-node-limit") {
            if at >= arguments.len { driver_error("missing option value"); o.bad = true; break; }
            let v = arguments[at]; at++;
            if same_bytes(a, "-o") { o.output_arg = at - 1; }
            else if same_bytes(a, "--stdlib") { o.stdlib_arg = at - 1; }
            else if same_bytes(a, "--wasm-stats") { o.stats_arg = at - 1; }
            else if same_bytes(a, "--wasm-deps") { o.dependencies_arg = at - 1; }
            else if same_bytes(a, "--cc") { o.cc_arg = at - 1; }
            else if same_bytes(a, "--target") {
                if same_bytes(v, "wasm-direct") { o.target = 0; }
                else if same_bytes(v, "native") || same_bytes(v, "c") { o.target = 1; }
                else { driver_error("target must be wasm-direct, native or c"); o.bad = true; }
            } else {
                let number, ok = driver_number(v);
                if !ok { driver_error("invalid page count"); o.bad = true; }
                else if same_bytes(a, "--expansion-node-limit") { o.expansion_limit = number; }
                else if same_bytes(a, "--wasm-initial-pages") { o.initial_pages = number; }
                else { o.maximum_pages = number; }
            }
        } else if a.len > 0 && a[0] == '-' { driver_error("unknown compiler option"); write_stderr(a); write_stderr("\n"); o.bad = true; }
        else if o.source_arg < 0 { o.source_arg = at - 1; }
        else { driver_error("only one root source is accepted"); o.bad = true; }
    }
    if o.initial_pages < 1 || o.maximum_pages < o.initial_pages || o.maximum_pages > 65536 {
        driver_error("invalid memory page limits"); o.bad = true;
    }
}
fn driver_diagnostics(p: Program&) {
    for d in p.diagnostics {
        var line: u8[>..] = [];
        if d.source >= 0 && d.source < p.sources.len {
            let s = p.sources[d.source]; line.append(p.text[s.path_start..s.path_start + s.path_len]);
        } else { line.append("<source>"); }
        line.push(':'); driver_integer(line, d.line); line.push(':'); driver_integer(line, d.column);
        line.append(": error: "); line.append(p.messages[d.message_start..d.message_start + d.message_len]); line.push('\n');
        write_stderr(line);
    }
}
fn driver_dependencies(p: Program&, path: const u8[:]) -> bool {
    var out: u8[>..] = []; out.push('[');
    for s, i in p.sources {
        if i > 0 { out.push(','); }
        out.append("{\"path\":"); driver_json(out, p.text[s.path_start..s.path_start + s.path_len]);
        out.append(",\"text\":"); driver_json(out, p.text[s.text_start..s.text_start + s.text_len]); out.push('}');
    }
    // Package probes and embedded resources are not yet a reusable cache proof.
    out.append(",{\"kind\":\"build\",\"path\":\"\",\"exists\":false,\"complete\":false}]\n");
    return write_file(path, out);
}
fn driver_ir_field(out: u8[>..]&, name: const u8[:], value: i64) {
    out.push(','); driver_json(out, name); out.push(':'); driver_integer(out, value);
}
fn driver_ir(p: Program&) {
    var out: u8[>..] = [];
    out.append("{\"pointer_bytes\":"); driver_integer(out, p.pointer_bytes);
    out.append(",\"sources\":[");
    for s, i in p.sources {
        if i > 0 { out.push(','); }
        driver_json(out, p.text[s.path_start..s.path_start + s.path_len]);
    }
    out.append("],\"tokens\":[");
    for t, i in p.tokens {
        if i > 0 { out.push(','); }
        out.append("{\"id\":"); driver_integer(out, i);
        driver_ir_field(out, "kind", t.kind); driver_ir_field(out, "source", t.source);
        driver_ir_field(out, "line", t.line); driver_ir_field(out, "column", t.column);
        out.append(",\"text\":"); driver_json(out, p.text[t.start..t.end]); out.push('}');
    }
    out.append("],\"nodes\":[");
    for n, i in p.nodes {
        if i > 0 { out.push(','); }
        out.append("{\"id\":"); driver_integer(out, i);
        driver_ir_field(out, "kind", n.kind); driver_ir_field(out, "token", n.token);
        driver_ir_field(out, "type_id", n.type_id); driver_ir_field(out, "symbol", n.symbol);
        driver_ir_field(out, "coerced_type", n.coerced_type);
        driver_ir_field(out, "left", n.left); driver_ir_field(out, "right", n.right);
        driver_ir_field(out, "third", n.third); driver_ir_field(out, "first", n.first);
        driver_ir_field(out, "next", n.next); driver_ir_field(out, "aux", n.aux);
        driver_ir_field(out, "integer", n.integer); driver_ir_field(out, "flags", n.flags);
        driver_ir_field(out, "origin", n.origin); driver_ir_field(out, "scope", n.scope);
        driver_ir_field(out, "captures", n.captures); out.push('}');
    }
    out.append("],\"types\":[");
    for t, i in p.types {
        if i > 0 { out.push(','); }
        out.append("{\"id\":"); driver_integer(out, i);
        driver_ir_field(out, "kind", t.kind); driver_ir_field(out, "element", t.element);
        driver_ir_field(out, "count", t.count); driver_ir_field(out, "array_kind", t.array_kind);
        driver_ir_field(out, "storage", t.storage); driver_ir_field(out, "size", t.size);
        driver_ir_field(out, "declaration", t.declaration); driver_ir_field(out, "first", t.first);
        driver_ir_field(out, "flags", t.flags); driver_ir_field(out, "pool", t.pool);
        driver_ir_field(out, "prefix", t.prefix); driver_ir_field(out, "tail", t.tail);
        driver_ir_field(out, "length_storage", t.length_storage); driver_ir_field(out, "padding", t.padding);
        driver_ir_field(out, "arguments", t.arguments); out.push('}');
    }
    out.append("],\"symbols\":[");
    for s, i in p.symbols {
        if i > 0 { out.push(','); }
        out.append("{\"id\":"); driver_integer(out, i);
        driver_ir_field(out, "node", s.node); driver_ir_field(out, "type_id", s.type_id);
        driver_ir_field(out, "owner", s.owner); driver_ir_field(out, "name_token", s.name_token);
        driver_ir_field(out, "scope", s.scope); driver_ir_field(out, "flags", s.flags); out.push('}');
    }
    out.append("]}\n"); write_stdout(out);
}
fn driver_stats(p: Program&, path: const u8[:], bytes: i64, parsing: i64, checking: i64, optimizing: i64, backend: i64) -> bool {
    var out: u8[>..] = []; var functions = 0;
    for symbol in p.symbols {
        if (symbol.flags & S_FUNCTION) != 0 && symbol.node >= 0 && (p.nodes[symbol.node].flags & F_REACHABLE) != 0 { functions++; }
    }
    out.append("{\"implementation\":\"goose\",\"backend\":");
    if p.pointer_bytes == 8 { driver_json(out, "native"); } else { driver_json(out, "direct"); }
    out.append(",\"functions\":"); driver_integer(out, functions);
    out.append(",\"module_bytes\":"); driver_integer(out, bytes);
    out.append(",\"source_files\":"); driver_integer(out, p.sources.len);
    out.append(",\"nodes\":"); driver_integer(out, p.nodes.len);
    out.append(",\"types\":"); driver_integer(out, p.types.len);
    out.append(",\"parse_ns\":"); driver_integer(out, parsing);
    out.append(",\"typecheck_ns\":"); driver_integer(out, checking);
    out.append(",\"lifetime_ns\":"); driver_integer(out, p.lifetime_ns);
    out.append(",\"optimize_ns\":"); driver_integer(out, optimizing);
    out.append(",\"backend_ns\":"); driver_integer(out, backend);
    // Each reached function's node ID (the N of native g_fnN), name and
    // declaration site, so a profile of emitted code can be read by name.
    out.append(",\"function_info\":[],\"function_names\":["); var first = true;
    for symbol in p.symbols {
        if (symbol.flags & S_FUNCTION) == 0 || symbol.node < 0 || (p.nodes[symbol.node].flags & F_REACHABLE) == 0 || symbol.name_token < 0 { continue; }
        let t = p.tokens[symbol.name_token]; let s = p.sources[t.source];
        if !first { out.push(','); } first = false;
        out.append("{\"id\":"); driver_integer(out, symbol.node);
        out.append(",\"name\":"); driver_json(out, p.text[t.start..t.end]);
        out.append(",\"source\":"); driver_json(out, p.text[s.path_start..s.path_start + s.path_len]);
        out.append(",\"line\":"); driver_integer(out, t.line); out.push('}');
    }
    out.append("],\"cache_complete\":false}\n");
    return write_file(path, out);
}
fn driver_quote(out: u8[>..]&, value: const u8[:]) {
    out.push(39);
    for byte in value {
        if byte == 39 { out.append("'\\''"); } else { out.push(byte); }
    }
    out.push(39);
}
fn driver_exec(command: u8[>..]&) -> i64 {
    command.push(0); let code = driver_system(command[0]) as i64;
    if code < 0 { return 1; }
    if (code & 127) != 0 { return 128 + (code & 127); }
    return (code >> 8) & 255;
}
fn driver_help() {
    write_stdout("Goose-written compiler (unverified rewrite)\nUsage: goose-selfhost source.goose --target wasm-direct|native -o output [-O0|-O1|-O2]\n  --check --parse --tokens --dump --debug --stdlib DIR --wasm-stats FILE --wasm-deps FILE\n  --reachable-program  Check only functions a root reaches, and the signatures of the rest.\n  --expansion-node-limit N  Total const for expansion size (default 100000).\n  --run  Build native C with --cc and execute, or execute Wasm with GOOSE_WASM_HOST.\n");
}
fn driver_main() -> i64 {
    // Every path lives in one byte table: each array holds its own storage region.
    var paths: u8[>..] = [];
    let arguments = args();
    var o = DriverOptions {}; driver_options(o, arguments);
    if o.help { driver_help(); return 0; }
    if o.version { write_stdout("Goose to Wasm (Goose implementation)\n"); return 0; }
    if o.bad { return 2; }
    if o.source_arg < 0 { driver_help(); return 2; }
    let source_start = paths.len; paths.append(arguments[o.source_arg]); let source_end = paths.len;
    let output_start = paths.len;
    if o.output_arg >= 0 { paths.append(arguments[o.output_arg]); }
    if paths.len == output_start {
        if o.target == 0 { paths.append("out.wasm"); } else { paths.append("out.c"); }
    }
    let output_end = paths.len;
    let stats_start = paths.len; if o.stats_arg >= 0 { paths.append(arguments[o.stats_arg]); } let stats_end = paths.len;
    let dependency_start = paths.len; if o.dependencies_arg >= 0 { paths.append(arguments[o.dependencies_arg]); } let dependency_end = paths.len;
    let stdlib_start = paths.len;
    if o.stdlib_arg >= 0 { paths.append(arguments[o.stdlib_arg]); }
    else if !env("GOOSE_STDLIB", paths) {
        resource_dir(paths); paths.append("stdlib");
    }
    let stdlib_end = paths.len;
    let cc_start = paths.len;
    if o.cc_arg >= 0 { paths.append(arguments[o.cc_arg]); }
    else { env("CC", paths); }
    if paths.len == cc_start { paths.append("cc"); }
    let cc_end = paths.len;
    var text: u8[>..] = []; var messages: u8[>..] = []; var sources: Source[>..] = [];
    var tokens: Token[>..] = []; var nodes: Node[>..] = []; var types: Type[>..] = [];
    var symbols: Symbol[>..] = []; var diagnostics: Diagnostic[>..] = [];
    var type_properties: i64[>..] = []; var builtin_symbols: i64[>..] = [];
    var type_buckets: TypeBucket[>..] = []; var type_links: TypeLink[>..] = []; var type_scan_marks: i64[>..] = []; var type_holds: i64[>..] = [];
    var p = Program { text: text, messages: messages, sources: sources, tokens: tokens,
                      nodes: nodes, types: types, symbols: symbols, diagnostics: diagnostics,
                      type_properties: type_properties, builtin_symbols: builtin_symbols,
                      type_buckets: type_buckets, type_links: type_links, type_scan_marks: type_scan_marks, type_holds: type_holds };
    p.optimization = o.optimization; p.debug = o.debug; p.library = o.library;
    p.check_only = o.check || o.parse; p.reachable_program = o.reachable_program; p.expansion_limit = o.expansion_limit;
    p.initial_pages = o.initial_pages; p.maximum_pages = o.maximum_pages;
    if o.target == 1 { p.pointer_bytes = 8; }
    initialize_types(p);
    let started = clock_ns(); load_sources(p, paths[source_start..source_end], paths[stdlib_start..stdlib_end], o.tokens); let parsed = clock_ns();
    if p.diagnostics.len > 0 { driver_diagnostics(p); return 1; }
    if o.tokens {
        driver_tokens(p);
        return 0;
    }
    if o.dump { let s = p.sources[0]; write_stdout(p.text[s.text_start..s.text_start + s.text_len]); return 0; }
    if o.parse {
        check_program(p, true);
        if p.diagnostics.len > 0 { driver_diagnostics(p); return 1; }
        return 0;
    }
    check_program(p); let checked = clock_ns();
    if o.dump_ir {
        driver_ir(p);
        if p.diagnostics.len > 0 { driver_diagnostics(p); return 1; }
        return 0;
    }
    if p.diagnostics.len > 0 { driver_diagnostics(p); return 1; }
    // Checking ends with the checker, as upstream `goose check` does; the
    // optimizer only prepares code generation and reports nothing.
    if o.check {
        if !driver_outputs_distinct(p, "", paths[stats_start..stats_end], "") { return 1; }
        if stats_end > stats_start && !driver_stats(p, paths[stats_start..stats_end], 0, parsed - started, checked - parsed, 0, 0) {
            driver_error("cannot write statistics"); return 1;
        }
        return 0;
    }
    optimize_program(p); let optimized = clock_ns();
    if p.diagnostics.len > 0 { driver_diagnostics(p); return 1; }
    var output: u8[>..] = [];
    if o.target == 0 { generate_wasm(p, output); } else { generate_c(p, output); }
    let generated = clock_ns();
    if p.diagnostics.len > 0 { driver_diagnostics(p); return 1; }
    if !driver_outputs_distinct(p, paths[output_start..output_end], paths[stats_start..stats_end], paths[dependency_start..dependency_end]) { return 1; }
    if !write_file(paths[output_start..output_end], output) { driver_error("cannot write output"); return 1; }
    if stats_end > stats_start && !driver_stats(p, paths[stats_start..stats_end], output.len, parsed - started, checked - parsed, optimized - checked, generated - optimized) {
        driver_error("cannot write statistics"); return 1;
    }
    if dependency_end > dependency_start && !driver_dependencies(p, paths[dependency_start..dependency_end]) { driver_error("cannot write dependency manifest"); return 1; }
    if !o.run { return 0; }
    var command: u8[>..] = [];
    if o.target == 1 {
        var binary: u8[>..] = []; binary.append(paths[output_start..output_end]); binary.append(".bin");
        driver_quote(command, paths[cc_start..cc_end]); command.append(" -std=gnu11 -O2 "); driver_quote(command, paths[output_start..output_end]);
        command.append(" -lm -ldl -pthread -o "); driver_quote(command, binary);
        let code = driver_exec(command); if code != 0 { return code; }
        command.clear(); driver_quote(command, binary);
    } else {
        var host: u8[>..] = [];
        if !env("GOOSE_WASM_HOST", host) { host.append("build/bin/goose-wasmtime"); }
        driver_quote(command, host); command.push(' '); driver_quote(command, paths[output_start..output_end]);
    }
    return driver_exec(command);
}
