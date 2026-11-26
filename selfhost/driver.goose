import model;
import parallel;
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
    stats_arg: i64 = -1, dependencies_arg: i64 = -1, cc_arg: i64 = -1, profile_arg: i64 = -1,
    emit_runtime_arg: i64 = -1, header_arg: i64 = -1,
    region_stats: bool = false, bundled_host: bool = false,
    target: i64 = 0, target_set: bool = false, optimization: i64 = 0, jobs: i64 = 0, initial_pages: i64 = 16, maximum_pages: i64 = 256, memory64: bool = false,
    check: bool = false, parse: bool = false, tokens: bool = false,
    dump: bool = false, dump_ir: bool = false, run: bool = false, debug: bool = false, library: bool = false, shared: bool = false, standalone: bool = false, reachable_program: bool = false, expansion_limit: i64 = 100000, stack_reserve: i64 = 0,
    error_format: i64 = 0, color: i64 = 0,
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
    var i = 0;
    while i < text.len {
        let byte = text[i];
        if byte == '"' || byte == '\\' { out.push('\\'); out.push(byte); i++; }
        else if byte == 10 { out.append("\\n"); i++; }
        else if byte == 13 { out.append("\\r"); i++; }
        else if byte == 9 { out.append("\\t"); i++; }
        else if byte < 32 {
            out.append("\\u00"); out.push("0123456789abcdef"[byte >> 4]); out.push("0123456789abcdef"[byte & 15]); i++;
        } else if byte < 128 {
            out.push(byte); i++;
        } else if byte >= 0xc2 && byte <= 0xdf && i + 1 < text.len && (text[i + 1] & 0xc0) == 0x80 {
            out.push(byte); out.push(text[i + 1]); i += 2;
        } else if byte >= 0xe0 && byte <= 0xef && i + 2 < text.len &&
                  (text[i + 1] & 0xc0) == 0x80 && (text[i + 2] & 0xc0) == 0x80 &&
                  (byte != 0xe0 || text[i + 1] >= 0xa0) && (byte != 0xed || text[i + 1] <= 0x9f) {
            out.push(byte); out.push(text[i + 1]); out.push(text[i + 2]); i += 3;
        } else if byte >= 0xf0 && byte <= 0xf4 && i + 3 < text.len &&
                  (text[i + 1] & 0xc0) == 0x80 && (text[i + 2] & 0xc0) == 0x80 && (text[i + 3] & 0xc0) == 0x80 &&
                  (byte != 0xf0 || text[i + 1] >= 0x90) && (byte != 0xf4 || text[i + 1] <= 0x8f) {
            out.push(byte); out.push(text[i + 1]); out.push(text[i + 2]); out.push(text[i + 3]); i += 4;
        } else {
            out.append("\\u00"); out.push("0123456789abcdef"[byte >> 4]); out.push("0123456789abcdef"[byte & 15]); i++;
        }
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
// A size with an optional K, M, G or T suffix and an optional B after it, as
// upstream's --stack-reserve reads one.
fn driver_size(text: const u8[:]) -> i64, bool {
    var end = text.len;
    if end > 0 && (text[end - 1] == 'B' || text[end - 1] == 'b') { end -= 1; }
    if end == 0 { return 0, false; }
    var shift: i64 = 0; let suffix = text[end - 1];
    if suffix == 'K' || suffix == 'k' { shift = 10; } else if suffix == 'M' || suffix == 'm' { shift = 20; }
    else if suffix == 'G' || suffix == 'g' { shift = 30; } else if suffix == 'T' || suffix == 't' { shift = 40; }
    if shift != 0 { end -= 1; }
    if end == 0 || end > 18 { return 0, false; }
    let n, ok = driver_number(text[..end]);
    if !ok || n > (9223372036854775807 >> shift) { return 0, false; }
    return n << shift, true;
}
fn driver_error(message: const u8[:]) { write_stderr("goosew: "); write_stderr(message); write_stderr("\n"); }
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
fn driver_outputs_distinct(p: Program&, output: const u8[:], stats: const u8[:], dependencies: const u8[:], header: const u8[:] = "", runtime: const u8[:] = "", shared_tmp: const u8[:] = "", run_binary: const u8[:] = "") -> bool {
    if output.len > 0 && driver_source_path(p, output) { driver_error("output would overwrite a source file"); return false; }
    if runtime.len > 0 && (driver_source_path(p, runtime) || output.len > 0 && driver_same_path(runtime, output)) {
        driver_error("runtime output would overwrite a source file or the output"); return false;
    }
    if header.len > 0 && (driver_source_path(p, header) || output.len > 0 && driver_same_path(header, output) ||
                          runtime.len > 0 && driver_same_path(header, runtime)) {
        driver_error("header would overwrite a source file or another output"); return false;
    }
    if shared_tmp.len > 0 && (driver_source_path(p, shared_tmp) || output.len > 0 && driver_same_path(shared_tmp, output) ||
                              runtime.len > 0 && driver_same_path(shared_tmp, runtime) ||
                              header.len > 0 && driver_same_path(shared_tmp, header)) {
        driver_error("temporary C output would overwrite a source file or another output"); return false;
    }
    if run_binary.len > 0 && (driver_source_path(p, run_binary) || output.len > 0 && driver_same_path(run_binary, output) ||
                              runtime.len > 0 && driver_same_path(run_binary, runtime) ||
                              header.len > 0 && driver_same_path(run_binary, header)) {
        driver_error("temporary executable would overwrite a source file or another output"); return false;
    }
    if stats.len > 0 && (driver_source_path(p, stats) || output.len > 0 && driver_same_path(stats, output) ||
                         runtime.len > 0 && driver_same_path(stats, runtime) ||
                         header.len > 0 && driver_same_path(stats, header) ||
                         shared_tmp.len > 0 && driver_same_path(stats, shared_tmp) ||
                         run_binary.len > 0 && driver_same_path(stats, run_binary)) {
        driver_error("statistics would overwrite a source file or another output"); return false;
    }
    if dependencies.len > 0 && (driver_source_path(p, dependencies) || output.len > 0 && driver_same_path(dependencies, output) ||
                                runtime.len > 0 && driver_same_path(dependencies, runtime) ||
                                stats.len > 0 && driver_same_path(dependencies, stats) ||
                                header.len > 0 && driver_same_path(dependencies, header) ||
                                shared_tmp.len > 0 && driver_same_path(dependencies, shared_tmp) ||
                                run_binary.len > 0 && driver_same_path(dependencies, run_binary)) {
        driver_error("dependency manifest would overwrite a source file or another output"); return false;
    }
    return true;
}
fn driver_ends_with(text: const u8[:], suffix: const u8[:]) -> bool {
    if text.len < suffix.len { return false; }
    return same_bytes(text[text.len - suffix.len..], suffix);
}
fn driver_starts_with(text: const u8[:], prefix: const u8[:]) -> bool {
    if text.len < prefix.len { return false; }
    return same_bytes(text[0..prefix.len], prefix);
}
fn driver_set_error_format(o: DriverOptions&, v: const u8[:]) {
    if same_bytes(v, "text") { o.error_format = 0; }
    else if same_bytes(v, "json") { o.error_format = 1; }
    else { driver_error("--error-format must be text or json"); o.bad = true; }
}
fn driver_set_color(o: DriverOptions&, v: const u8[:]) {
    if same_bytes(v, "auto") { o.color = 0; }
    else if same_bytes(v, "always") { o.color = 1; }
    else if same_bytes(v, "never") { o.color = 2; }
    else { driver_error("--color must be auto, always or never"); o.bad = true; }
}
fn driver_set_jobs(o: DriverOptions&, v: const u8[:]) {
    if same_bytes(v, "auto") { o.jobs = 0; return; }
    let n, ok = driver_number(v);
    if !ok || n < 1 || n > 64 { driver_error("--jobs must be auto or a number from 1 to 64"); o.bad = true; return; }
    o.jobs = n;
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
        else if same_bytes(a, "--shared") { o.shared = true; }
        else if same_bytes(a, "--wasm-memory64") { o.memory64 = true; }
        else if same_bytes(a, "--wasm-bundled-host") { o.bundled_host = true; }
        else if same_bytes(a, "--wasm-region-stats") { o.region_stats = true; }
        else if same_bytes(a, "--reachable-program") { o.reachable_program = true; }
        else if same_bytes(a, "--standalone") { o.standalone = true; }
        else if same_bytes(a, "-O0") { o.optimization = 0; }
        else if same_bytes(a, "-O1") { o.optimization = 1; }
        else if same_bytes(a, "-O2") { o.optimization = 2; }
        else if driver_starts_with(a, "--error-format=") { driver_set_error_format(o, a[15..]); }
        else if driver_starts_with(a, "--color=") { driver_set_color(o, a[8..]); }
        else if driver_starts_with(a, "--jobs=") { driver_set_jobs(o, a[7..]); }
        else if driver_starts_with(a, "-j=") { driver_set_jobs(o, a[3..]); }
        else if same_bytes(a, "-o") || same_bytes(a, "--stdlib") || same_bytes(a, "--wasm-stats") ||
                same_bytes(a, "--wasm-deps") || same_bytes(a, "--cc") || same_bytes(a, "--target") || same_bytes(a, "--wasm-region-profile") ||
                same_bytes(a, "--wasm-initial-pages") || same_bytes(a, "--wasm-max-pages") || same_bytes(a, "--expansion-node-limit") ||
                same_bytes(a, "--stack-reserve") || same_bytes(a, "--emit-runtime") || same_bytes(a, "--header") ||
                same_bytes(a, "--error-format") || same_bytes(a, "--color") || same_bytes(a, "--jobs") || same_bytes(a, "-j") {
            if at >= arguments.len { driver_error("missing option value"); o.bad = true; break; }
            let v = arguments[at]; at++;
            if same_bytes(a, "-o") { o.output_arg = at - 1; }
            else if same_bytes(a, "--stdlib") { o.stdlib_arg = at - 1; }
            else if same_bytes(a, "--wasm-stats") { o.stats_arg = at - 1; }
            else if same_bytes(a, "--wasm-region-profile") { o.profile_arg = at - 1; }
            else if same_bytes(a, "--wasm-deps") { o.dependencies_arg = at - 1; }
            else if same_bytes(a, "--cc") { o.cc_arg = at - 1; }
            else if same_bytes(a, "--emit-runtime") { o.emit_runtime_arg = at - 1; }
            else if same_bytes(a, "--header") { o.header_arg = at - 1; }
            else if same_bytes(a, "--error-format") { driver_set_error_format(o, v); }
            else if same_bytes(a, "--color") { driver_set_color(o, v); }
            else if same_bytes(a, "--jobs") || same_bytes(a, "-j") { driver_set_jobs(o, v); }
            else if same_bytes(a, "--target") {
                o.target_set = true;
                if same_bytes(v, "wasm-direct") { o.target = 0; }
                else if same_bytes(v, "native") || same_bytes(v, "c") { o.target = 1; }
                else { driver_error("target must be wasm-direct, native or c"); o.bad = true; }
            } else if same_bytes(a, "--stack-reserve") {
                // A whole page at least, 64 KB being the largest a platform
                // uses, and at most the 2^48 bytes of goose_spec.md 10.4.
                let size, ok = driver_size(v);
                if !ok || size < 65536 || size > 281474976710656 {
                    driver_error("--stack-reserve takes a size from 64 KB to 256 TB (2^48, goose_spec.md 10.4), with an optional K, M, G or T suffix"); o.bad = true;
                } else { o.stack_reserve = size; }
            } else {
                let number, ok = driver_number(v);
                if !ok {
                    if same_bytes(a, "--expansion-node-limit") { driver_error("invalid expansion node limit"); }
                    else { driver_error("invalid page count"); }
                    o.bad = true;
                }
                else if same_bytes(a, "--expansion-node-limit") { o.expansion_limit = number; }
                else if same_bytes(a, "--wasm-initial-pages") { o.initial_pages = number; }
                else { o.maximum_pages = number; }
            }
        } else if a.len > 0 && a[0] == '-' { driver_error("unknown compiler option"); write_stderr(a); write_stderr("\n"); o.bad = true; }
        else if o.source_arg < 0 { o.source_arg = at - 1; }
        else { driver_error("only one root source is accepted"); o.bad = true; }
    }
    // --header and --shared target native C by default (upstream C-host interface).
    if o.header_arg >= 0 || o.shared {
        if !o.target_set { o.target = 1; }
        else if o.target != 1 { driver_error("--header and --shared require the native target"); o.bad = true; }
    }
    // A 64-bit memory may declare up to 2^32 pages (2^48 bytes); an engine
    // has its own cap, V8's being 262,144 pages.
    var page_limit = 65536; if o.memory64 && o.target == 0 { page_limit = 4294967296; }
    if o.initial_pages < 1 || o.maximum_pages < o.initial_pages || o.maximum_pages > page_limit {
        driver_error("invalid memory page limits"); o.bad = true;
    }
}
fn driver_ansi(out: u8[>..]&, color: bool, code: const u8[:]) {
    if !color { return; }
    out.push(27); out.push('['); out.append(code); out.push('m');
}
fn driver_use_color(o: const DriverOptions&) -> bool {
    if o.color == 1 { return true; }
    if o.color == 2 { return false; }
    var buf: u8[>..] = [];
    if env("NO_COLOR", buf) { return false; }
    buf.clear();
    if env("CLICOLOR_FORCE", buf) && buf.len > 0 && !same_bytes(buf, "0") { return true; }
    return false;
}
fn driver_diag_snippet(p: Program&, d: const Diagnostic&, out: u8[>..]&, color: bool) {
    if d.source < 0 || d.source >= p.sources.len { return; }
    let s: const Source& = p.sources[d.source];
    let text_start = s.text_start; let text_end = s.text_start + s.text_len;
    if text_end <= text_start || d.start < text_start || d.start > text_end { return; }
    if d.start == d.end && d.start == text_start && d.line == 1 && d.column == 1 { return; }
    var line_start = d.start;
    if line_start == text_end && line_start > text_start { line_start -= 1; }
    while line_start > text_start && p.text[line_start - 1] != 10 { line_start -= 1; }
    var line_end = d.start;
    if line_end > text_end { line_end = text_end; }
    while line_end < text_end && p.text[line_end] != 10 { line_end += 1; }
    if line_end > line_start && p.text[line_end - 1] == 13 { line_end -= 1; }
    if line_end <= line_start || line_end - line_start > 240 { return; }
    var num_buf: u8[>..] = []; driver_integer(num_buf, d.line);
    var gutter = num_buf.len; if gutter < 3 { gutter = 3; }
    driver_ansi(out, color, "1;34");
    out.push(' ');
    for pi in num_buf.len..gutter { out.push(' '); }
    out.append(num_buf); out.append(" | ");
    driver_ansi(out, color, "0");
    var caret_col: i64 = 0; var span_cols: i64 = 0;
    var span_end = d.end;
    if span_end <= d.start { span_end = d.start + 1; }
    if span_end > line_end { span_end = line_end; }
    for i in line_start..line_end {
        let ch = p.text[i];
        var width: i64 = 1;
        if ch == 9 { out.append("    "); width = 4; } else { out.push(ch); }
        if i < d.start { caret_col += width; }
        else if i < span_end { span_cols += width; }
    }
    out.push('\n');
    driver_ansi(out, color, "1;34");
    out.push(' ');
    for pi in 0..gutter { out.push(' '); }
    out.append(" | ");
    driver_ansi(out, color, "0");
    for ci in 0..caret_col { out.push(' '); }
    driver_ansi(out, color, "1;31");
    out.push('^');
    if span_cols > 1 {
        for si in 1..span_cols { out.push('~'); }
    }
    driver_ansi(out, color, "0");
    out.push('\n');
}
fn driver_diag_notes(out: u8[>..]&, tail: const u8[:], color: bool) {
    if !color { out.append(tail); out.push('\n'); return; }
    var pos: i64 = 0;
    while pos <= tail.len {
        var nl = pos;
        while nl < tail.len && tail[nl] != 10 { nl += 1; }
        let seg = tail[pos..nl];
        if driver_starts_with(seg, "  note:") {
            out.append("  "); driver_ansi(out, true, "1;36"); out.append("note:"); driver_ansi(out, true, "0");
            out.append(seg[7..]);
        } else if driver_starts_with(seg, "  help:") {
            out.append("  "); driver_ansi(out, true, "1;32"); out.append("help:"); driver_ansi(out, true, "0");
            out.append(seg[7..]);
        } else {
            out.append(seg);
        }
        out.push('\n');
        pos = nl + 1;
    }
}
fn driver_diagnostics_json(p: Program&) {
    var out: u8[>..] = [];
    out.push('[');
    for d, di in p.diagnostics {
        if di > 0 { out.push(','); }
        out.append("{\"severity\":");
        if d.severity == 0 { driver_json(out, "warning"); }
        else if d.severity == 2 { driver_json(out, "note"); }
        else { driver_json(out, "error"); }
        out.append(",\"file\":");
        var base: i64 = 0;
        if d.source >= 0 && d.source < p.sources.len {
            let s: const Source& = p.sources[d.source];
            driver_json(out, p.text[s.path_start..s.path_start + s.path_len]);
            base = s.text_start;
        } else { driver_json(out, "<source>"); }
        var rel_start = d.start - base; if rel_start < 0 { rel_start = 0; }
        var rel_end = d.end - base; if rel_end < rel_start { rel_end = rel_start; }
        out.append(",\"line\":"); driver_integer(out, d.line);
        out.append(",\"column\":"); driver_integer(out, d.column);
        out.append(",\"start\":"); driver_integer(out, rel_start);
        out.append(",\"end\":"); driver_integer(out, rel_end);
        let msg = p.messages[d.message_start..d.message_start + d.message_len];
        var split: i64 = -1;
        for i in 0..msg.len { if msg[i] == 10 { split = i; break; } }
        out.append(",\"message\":");
        if split >= 0 { driver_json(out, msg[0..split]); } else { driver_json(out, msg); }
        out.append(",\"notes\":[");
        if split >= 0 {
            var pos = split + 1;
            var ncount: i64 = 0;
            while pos <= msg.len {
                var nl = pos;
                while nl < msg.len && msg[nl] != 10 { nl += 1; }
                var line_start = pos;
                if line_start + 2 <= nl && msg[line_start] == ' ' && msg[line_start + 1] == ' ' { line_start += 2; }
                if nl > line_start {
                    if ncount > 0 { out.push(','); }
                    driver_json(out, msg[line_start..nl]);
                    ncount += 1;
                }
                pos = nl + 1;
            }
        }
        out.append("]}");
    }
    out.append("]\n");
    write_stderr(out);
}
fn driver_diagnostics(p: Program&, o: const DriverOptions&) {
    if o.error_format == 1 { driver_diagnostics_json(p); return; }
    let color = driver_use_color(o);
    for d in p.diagnostics {
        var line: u8[>..] = [];
        driver_ansi(line, color, "1");
        if d.source >= 0 && d.source < p.sources.len {
            let s: const Source& = p.sources[d.source]; line.append(p.text[s.path_start..s.path_start + s.path_len]);
        } else { line.append("<source>"); }
        line.push(':'); driver_integer(line, d.line); line.push(':'); driver_integer(line, d.column);
        line.append(": ");
        if d.severity == 0 {
            driver_ansi(line, color, "1;33");
            line.append("warning:");
        } else if d.severity == 2 {
            driver_ansi(line, color, "1;36");
            line.append("note:");
        } else {
            driver_ansi(line, color, "1;31");
            line.append("error:");
        }
        driver_ansi(line, color, "0");
        line.push(' ');
        let msg = p.messages[d.message_start..d.message_start + d.message_len];
        var split: i64 = -1;
        for i in 0..msg.len { if msg[i] == 10 { split = i; break; } }
        if split >= 0 {
            driver_ansi(line, color, "1");
            line.append(msg[0..split]);
            driver_ansi(line, color, "0");
            line.push('\n');
            driver_diag_snippet(p, d, line, color);
            driver_diag_notes(line, msg[split + 1..], color);
        } else {
            driver_ansi(line, color, "1");
            line.append(msg);
            driver_ansi(line, color, "0");
            line.push('\n');
            driver_diag_snippet(p, d, line, color);
        }
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
    if p.pointer_bytes == 8 && !p.wide { driver_json(out, "native"); } else { driver_json(out, "direct"); }
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
fn driver_is_windows() -> bool {
    var dir: u8[>..] = [];
    if resource_dir(dir) {
        if dir.len >= 2 && dir[1] == ':' { return true; }
        for ch in dir { if ch == '\\' { return true; } }
    }
    var os_name: u8[>..] = [];
    return env("OS", os_name) && same_bytes(os_name, "Windows_NT");
}
fn driver_is_macos(win: bool) -> bool {
    return !win && is_dir("/System/Library");
}
fn driver_link_flags(out: u8[>..]&, win: bool, mac: bool) {
    if win { out.append(" -lm"); }
    else if mac { out.append(" -lm -lpthread"); }
    else { out.append(" -lm -ldl -pthread"); }
}
fn driver_quote(out: u8[>..]&, value: const u8[:], win: bool = false) {
    if win {
        out.push('"');
        for byte in value {
            if byte == '"' { out.append("\\\""); } else { out.push(byte); }
        }
        out.push('"');
        return;
    }
    out.push(39);
    for byte in value {
        if byte == 39 { out.append("'\\''"); } else { out.push(byte); }
    }
    out.push(39);
}
// --run splits native C of this many bytes of program functions into a unit
// each (native/units.h), at most one per hardware thread; less stays whole.
let DRIVER_UNIT_BYTES: i64 = 2097152;
fn driver_units(output: const u8[:]) -> i64 {
    let mark = "\n#if G_IN_";
    var at = 0;
    while at + mark.len <= output.len && !same_bytes(output[at..at + mark.len], mark) { at++; }
    var units = (output.len - at) / DRIVER_UNIT_BYTES;
    let threads = hardware_threads();
    if units > threads { units = threads; }
    return units;
}
// One shell command: the runtime unit and every program unit compile at
// once, and link when all of them have.
fn driver_split_build(command: u8[>..]&, cc: const u8[:], source: const u8[:], binary: const u8[:], units: i64, mac: bool) {
    var objects: u8[>..] = [];
    for index in 0..units + 1 {
        let unit = index - 1;
        driver_quote(command, cc); command.append(" -std=gnu11 -O2 ");
        if unit < 0 { command.append("-DG_RUNTIME_UNIT"); }
        else { command.append("-DG_UNITS="); driver_integer(command, units); command.append(" -DG_UNIT="); driver_integer(command, unit); }
        command.append(" -c -x c "); driver_quote(command, source); command.append(" -x none -o ");
        var object: u8[>..] = []; object.append(binary); object.append(".unit");
        if unit < 0 { object.append("-runtime"); } else { driver_integer(object, unit); }
        object.append(".o"); driver_quote(command, object); objects.push(' '); driver_quote(objects, object);
        command.append(" & p"); driver_integer(command, index); command.append("=$!; ");
    }
    command.append("s=0; for p in");
    for index in 0..units + 1 { command.append(" $p"); driver_integer(command, index); }
    command.append("; do wait $p || s=1; done; [ $s = 0 ] && "); driver_quote(command, cc);
    command.append(" -std=gnu11 -O2"); command.append(objects); driver_link_flags(command, false, mac); command.append(" -o "); driver_quote(command, binary);
    command.append("; s=$?; rm -f"); command.append(objects); command.append("; exit $s");
}
fn driver_exec(command: u8[>..]&, win: bool = false) -> i64 {
    if win {
        // cmd.exe /c strips one leading and one trailing quote when the command starts with '"'.
        var wrapped: u8[>..] = []; wrapped.push('"'); wrapped.append(command); wrapped.push('"'); wrapped.push(0);
        let code = driver_system(wrapped[0]) as i64;
        if code < 0 { return 1; }
        return code;
    }
    command.push(0); let code = driver_system(command[0]) as i64;
    if code < 0 { return 1; }
    if (code & 127) != 0 { return 128 + (code & 127); }
    return (code >> 8) & 255;
}
let GOOSE_TO_WASM_VERSION = "v2026.4-3";
fn driver_help() {
    write_stdout("goose-to-wasm "); write_stdout(GOOSE_TO_WASM_VERSION); write_stdout(" — fast Goose compiler (direct WebAssembly & native C)\nUsage: goosew source.goose [--target wasm-direct|native|c] -o output [-O0|-O1|-O2]\n  --check --parse --tokens --dump --debug --stdlib DIR --wasm-stats FILE --wasm-deps FILE\n  --jobs N|auto, -j N       Worker thread count for parallel compilation (default auto).\n  --error-format text|json  Diagnostic output format (default text).\n  --color auto|always|never Colorize text diagnostics (default auto; respects NO_COLOR).\n  --emit-runtime FILE  Write the standalone native C runtime unit and exit.\n  --header FILE        Emit a C host header (goose_init, goose_exit, exports) and separate-runtime C.\n  --shared             Build or emit a C shared library with exported symbols.\n  --standalone         Embed the native C runtime even when emitting with --header.\n  --wasm-memory64      Target WebAssembly memory64.\n  --wasm-bundled-host  Target the bundled host implementations for recognized imports.\n  --reachable-program  Check only functions a root reaches, and the signatures of the rest.\n  --expansion-node-limit N  Total const for expansion size (default 100000).\n  --stack-reserve SIZE  Address space reserved per data stack in a native program, from 64K to 256T\n                        with a K, M, G or T suffix (default 2G).\n  --run                Build native C with --cc and execute, or execute Wasm with GOOSE_WASM_HOST.\n  --version            Print compiler version.\n");
}
fn driver_main() -> i64 {
    // Every path lives in one byte table: each array holds its own storage region.
    var paths: u8[>..] = [];
    let arguments = args();
    var o = DriverOptions {}; driver_options(o, arguments);
    if o.help { driver_help(); return 0; }
    if o.version { write_stdout("goose-to-wasm "); write_stdout(GOOSE_TO_WASM_VERSION); write_stdout(" (Goose v2026.4)\n"); return 0; }
    if o.bad { return 2; }
    if o.emit_runtime_arg >= 0 && o.source_arg < 0 {
        var runtime_out: u8[>..] = [];
        generate_c_runtime(runtime_out);
        if !write_file(arguments[o.emit_runtime_arg], runtime_out) { driver_error("cannot write runtime output"); return 1; }
        return 0;
    }
    if o.source_arg < 0 { driver_help(); return 2; }
    let source_start = paths.len; paths.append(arguments[o.source_arg]); let source_end = paths.len;
    let output_start = paths.len;
    if o.output_arg >= 0 { paths.append(arguments[o.output_arg]); }
    if paths.len == output_start {
        if o.target == 0 { paths.append("out.wasm"); } else { paths.append("out.c"); }
    }
    let output_end = paths.len;
    let header_start = paths.len; if o.header_arg >= 0 { paths.append(arguments[o.header_arg]); } let header_end = paths.len;
    let runtime_start = paths.len; if o.emit_runtime_arg >= 0 { paths.append(arguments[o.emit_runtime_arg]); } let runtime_end = paths.len;
    let stats_start = paths.len; if o.stats_arg >= 0 { paths.append(arguments[o.stats_arg]); } let stats_end = paths.len;
    let dependency_start = paths.len; if o.dependencies_arg >= 0 { paths.append(arguments[o.dependencies_arg]); } let dependency_end = paths.len;
    let stdlib_start = paths.len;
    if o.stdlib_arg >= 0 { paths.append(arguments[o.stdlib_arg]); }
    else if !env("GOOSE_STDLIB", paths) {
        resource_dir(paths); paths.append("stdlib");
    }
    let stdlib_end = paths.len;
    let win = driver_is_windows();
    let mac = driver_is_macos(win);
    let cc_start = paths.len;
    if o.cc_arg >= 0 { paths.append(arguments[o.cc_arg]); }
    else { env("CC", paths); }
    if paths.len == cc_start {
        if win { paths.append("clang"); } else { paths.append("cc"); }
    }
    let cc_end = paths.len;
    var text: u8[>..] = []; var messages: u8[>..] = []; var sources: Source[>..] = [];
    var tokens: Token[>..] = []; var nodes: Node[>..] = []; var types: Type[>..] = [];
    var symbols: Symbol[>..] = []; var diagnostics: Diagnostic[>..] = [];
    var type_properties: i64[>..] = []; var builtin_symbols: i64[>..] = [];
    var type_buckets: TypeBucket[>..] = []; var type_links: TypeLink[>..] = []; var type_scan_marks: i64[>..] = []; var type_holds: i64[>..] = [];
    var inline_sites: InlineSite[>..] = []; var instantiation_stack: InstantiationSite[>..] = []; var region_profile: i64[>..] = [];
    var ident_table: i32[>..] = [];
    // A region profile is lines of "index bytes", as a host writes them
    // (GOOSE_REGION_PROFILE): what each data region was seen to need.
    if o.profile_arg >= 0 {
        var profile_text: u8[>..] = [];
        if !read_file(arguments[o.profile_arg], profile_text) { driver_error("cannot read the region profile"); return 1; }
        var at = 0; var index: i64 = -1;
        while at < profile_text.len {
            while at < profile_text.len && (profile_text[at] < '0' || profile_text[at] > '9') { at++; }
            let start = at; while at < profile_text.len && profile_text[at] >= '0' && profile_text[at] <= '9' { at++; }
            if at == start { break; }
            let number, ok = driver_number(profile_text[start..at]);
            if !ok || number > 281474976710656 { driver_error("the region profile holds a number out of range"); return 1; }
            if index < 0 { index = number; continue; }
            if index > 1048576 { driver_error("the region profile holds a region index out of range"); return 1; }
            while region_profile.len <= index { region_profile.push(0); }
            region_profile[index] = number; index = -1;
        }
    }
    var p = Program { text: text, messages: messages, sources: sources, tokens: tokens,
                      nodes: nodes, types: types, symbols: symbols, diagnostics: diagnostics,
                      type_properties: type_properties, builtin_symbols: builtin_symbols,
                      type_buckets: type_buckets, type_links: type_links, type_scan_marks: type_scan_marks, type_holds: type_holds,
                      inline_sites: inline_sites, instantiation_stack: instantiation_stack, region_profile: region_profile, ident_table: ident_table };
    let link_shared = o.shared && !driver_ends_with(paths[output_start..output_end], ".c");
    p.optimization = o.optimization; p.jobs = gp_effective_jobs(o.jobs); p.debug = o.debug; p.library = o.library;
    p.c_host = o.header_arg >= 0 || o.shared; p.shared = o.shared;
    p.separate_runtime = o.header_arg >= 0 && !o.standalone && !link_shared;
    p.check_only = o.check || o.parse; p.reachable_program = o.reachable_program; p.expansion_limit = o.expansion_limit; p.stack_reserve = o.stack_reserve;
    p.initial_pages = o.initial_pages; p.maximum_pages = o.maximum_pages; p.region_stats = o.region_stats; p.bundled_host = o.bundled_host;
    if o.target == 1 { p.pointer_bytes = 8; }
    else if o.memory64 { p.pointer_bytes = 8; p.wide = true; p.control_bytes = 48; p.control_align = 8; }
    initialize_types(p);
    let started = clock_ns(); load_sources(p, paths[source_start..source_end], paths[stdlib_start..stdlib_end], o.tokens); let parsed = clock_ns();
    if p.diagnostics.len > 0 { driver_diagnostics(p, o); return 1; }
    if o.tokens {
        driver_tokens(p);
        return 0;
    }
    if o.dump { let s = p.sources[0]; write_stdout(p.text[s.text_start..s.text_start + s.text_len]); return 0; }
    if o.parse {
        check_program(p, true);
        if p.diagnostics.len > 0 { driver_diagnostics(p, o); return 1; }
        return 0;
    }
    check_program(p); let checked = clock_ns();
    if o.dump_ir {
        driver_ir(p);
        if p.diagnostics.len > 0 { driver_diagnostics(p, o); return 1; }
        return 0;
    }
    if p.diagnostics.len > 0 { driver_diagnostics(p, o); return 1; }
    // Checkfree promises are checked after bounds analysis, including in check mode.
    if o.check {
        if p.has_checked_checkfree { optimize_program(p); }
        if p.diagnostics.len > 0 { driver_diagnostics(p, o); return 1; }
        if !driver_outputs_distinct(p, "", paths[stats_start..stats_end], "") { return 1; }
        if stats_end > stats_start && !driver_stats(p, paths[stats_start..stats_end], 0, parsed - started, checked - parsed, 0, 0) {
            driver_error("cannot write statistics"); return 1;
        }
        return 0;
    }
    optimize_program(p); let optimized = clock_ns();
    if p.diagnostics.len > 0 { driver_diagnostics(p, o); return 1; }
    var output: u8[>..] = [];
    if o.target == 0 { generate_wasm(p, output); } else { generate_c(p, output); }
    let generated = clock_ns();
    if p.diagnostics.len > 0 { driver_diagnostics(p, o); return 1; }
    var c_path: u8[>..] = [];
    if link_shared { c_path.append(paths[output_start..output_end]); c_path.append(".goose.c"); }
    var run_binary: u8[>..] = [];
    if o.run && !link_shared && o.target == 1 {
        run_binary.append(paths[output_start..output_end]);
        if win { run_binary.append(".exe"); } else { run_binary.append(".bin"); }
    }
    if !driver_outputs_distinct(p, paths[output_start..output_end], paths[stats_start..stats_end], paths[dependency_start..dependency_end], paths[header_start..header_end], paths[runtime_start..runtime_end], c_path, run_binary) { return 1; }
    if runtime_end > runtime_start {
        var runtime_out: u8[>..] = [];
        generate_c_runtime(runtime_out);
        if !write_file(paths[runtime_start..runtime_end], runtime_out) { driver_error("cannot write runtime output"); return 1; }
    }
    if header_end > header_start {
        var header_out: u8[>..] = [];
        generate_c_header(p, header_out);
        if !write_file(paths[header_start..header_end], header_out) { driver_error("cannot write header output"); return 1; }
    }
    if link_shared {
        if !write_file(c_path, output) { driver_error("cannot write temporary C output"); return 1; }
        var shared_cmd: u8[>..] = [];
        driver_quote(shared_cmd, paths[cc_start..cc_end], win);
        shared_cmd.append(" -std=gnu11 -O2 -shared ");
        if !win { shared_cmd.append("-fPIC "); }
        shared_cmd.append("-x c ");
        driver_quote(shared_cmd, c_path, win);
        shared_cmd.append(" -x none");
        driver_link_flags(shared_cmd, win, mac);
        shared_cmd.append(" -o ");
        driver_quote(shared_cmd, paths[output_start..output_end], win);
        let code = driver_exec(shared_cmd, win);
        delete_file(c_path);
        if code != 0 { return code; }
    } else {
        if !write_file(paths[output_start..output_end], output) { driver_error("cannot write output"); return 1; }
    }
    if stats_end > stats_start && !driver_stats(p, paths[stats_start..stats_end], output.len, parsed - started, checked - parsed, optimized - checked, generated - optimized) {
        driver_error("cannot write statistics"); return 1;
    }
    if dependency_end > dependency_start && !driver_dependencies(p, paths[dependency_start..dependency_end]) { driver_error("cannot write dependency manifest"); return 1; }
    if !o.run || link_shared { return 0; }
    var command: u8[>..] = [];
    if o.target == 1 {
        let units = if win { 1 } else { driver_units(output) };
        if units > 1 { driver_split_build(command, paths[cc_start..cc_end], paths[output_start..output_end], run_binary, units, mac); }
        else {
            driver_quote(command, paths[cc_start..cc_end], win); command.append(" -std=gnu11 -O2 -x c ");
            driver_quote(command, paths[output_start..output_end], win);
            command.append(" -x none");
            driver_link_flags(command, win, mac); command.append(" -o "); driver_quote(command, run_binary, win);
        }
        let code = driver_exec(command, win); if code != 0 { return code; }
        command.clear();
        if win {
            driver_quote(command, run_binary, true);
        } else {
            var has_sep = false;
            for ch in run_binary { if ch == '/' { has_sep = true; break; } }
            if !has_sep {
                var exec_path: u8[>..] = []; exec_path.append("./"); exec_path.append(run_binary);
                driver_quote(command, exec_path);
            } else {
                driver_quote(command, run_binary);
            }
        }
    } else {
        var host: u8[>..] = [];
        if env("GOOSE_WASM_HOST", host) && host.len > 0 {
            driver_quote(command, host, win); command.push(' '); driver_quote(command, paths[output_start..output_end], win);
        } else if file_exists("build/bin/goose-wasmtime") {
            driver_quote(command, "build/bin/goose-wasmtime", win); command.push(' '); driver_quote(command, paths[output_start..output_end], win);
        } else if file_exists("host/rust/target/release/goose-wasmtime") {
            driver_quote(command, "host/rust/target/release/goose-wasmtime", win); command.push(' '); driver_quote(command, paths[output_start..output_end], win);
        } else if file_exists("scripts/run_wasm.mjs") {
            driver_quote(command, "node", win); command.push(' '); driver_quote(command, "scripts/run_wasm.mjs", win);
            command.push(' '); driver_quote(command, paths[output_start..output_end], win);
        } else {
            driver_error("no Wasm runner found for --run; set GOOSE_WASM_HOST or pass --target c --run");
            return 1;
        }
    }
    return driver_exec(command, win);
}
