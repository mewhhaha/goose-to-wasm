import model;
import sources;
import os;

// Sound content-addressed whole-build artifact cache (--cache-dir DIR).
// Uses only the existing compiler OS imports (read_file, write_file,
// file_exists, is_dir) to keep the portable Wasm64 import surface unchanged.

let CACHE_SHA256_K: u32[64] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

inline fn cache_rotr32(x: u32, n: u32) -> u32 {
    return (x >> n) | (x << (32 - n));
}

inline fn cache_add32(a: u32, b: u32) -> u32 {
    return (((a as u64) + (b as u64)) & 4294967295) as u32;
}

fn cache_sha256_block(h: u32[8]&, buf: const u8[:], base: i64) {
    var w: u32[64] = [0; 64];
    let chunk: const u8[:] = buf[base..base + 64];
    for i in 0..16 {
        let j = i * 4;
        w[i] = ((chunk[j] as u32) << 24) |
               ((chunk[j + 1] as u32) << 16) |
               ((chunk[j + 2] as u32) << 8) |
               (chunk[j + 3] as u32);
    }
    for i in 16..64 {
        let s0 = cache_rotr32(w[i - 15], 7) ^ cache_rotr32(w[i - 15], 18) ^ (w[i - 15] >> 3);
        let s1 = cache_rotr32(w[i - 2], 17) ^ cache_rotr32(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = cache_add32(cache_add32(w[i - 16], s0), cache_add32(w[i - 7], s1));
    }
    var a = h[0]; var b = h[1]; var c = h[2]; var d = h[3];
    var e = h[4]; var f = h[5]; var g = h[6]; var hh = h[7];
    for i in 0..64 {
        let s1 = cache_rotr32(e, 6) ^ cache_rotr32(e, 11) ^ cache_rotr32(e, 25);
        let ch = (e & f) ^ ((~e) & g);
        let t1 = cache_add32(cache_add32(cache_add32(hh, s1), ch), cache_add32(CACHE_SHA256_K[i], w[i]));
        let s0 = cache_rotr32(a, 2) ^ cache_rotr32(a, 13) ^ cache_rotr32(a, 22);
        let maj = (a & b) ^ (a & c) ^ (b & c);
        let t2 = cache_add32(s0, maj);
        hh = g; g = f; f = e; e = cache_add32(d, t1);
        d = c; c = b; b = a; a = cache_add32(t1, t2);
    }
    h[0] = cache_add32(h[0], a); h[1] = cache_add32(h[1], b);
    h[2] = cache_add32(h[2], c); h[3] = cache_add32(h[3], d);
    h[4] = cache_add32(h[4], e); h[5] = cache_add32(h[5], f);
    h[6] = cache_add32(h[6], g); h[7] = cache_add32(h[7], hh);
}

fn cache_sha256_hex(data: const u8[:], hex_out: u8[>..]&) {
    var h: u32[8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ];
    let full = (data.len / 64) * 64;
    var at: i64 = 0;
    while at < full {
        cache_sha256_block(h, data, at);
        at += 64;
    }
    var tail: u8[128] = [0; 128];
    let rem = data.len - full;
    for i in 0..rem { tail[i] = data[full + i]; }
    tail[rem] = 0x80;
    let total_len = if rem < 56 { 64 } else { 128 };
    let bit_len = (data.len as u64) * 8;
    for b in 0..8 {
        tail[total_len - 1 - b] = ((bit_len >> (b * 8)) & 255) as u8;
    }
    cache_sha256_block(h, tail[..], 0);
    if total_len == 128 { cache_sha256_block(h, tail[..], 64); }
    let digits = "0123456789abcdef";
    for word in h {
        var shift: u32 = 28;
        for _ in 0..8 {
            hex_out.push(digits[((word >> shift) & 15) as i64]);
            if shift >= 4 { shift -= 4; }
        }
    }
}

fn cache_compiler_identity(argv0: const u8[:], win: bool, hex_out: u8[>..]&) -> bool {
    var exe_bytes: u8[>..] = [];
    if !win && read_file("/proc/self/exe", exe_bytes) && exe_bytes.len > 0 {
        cache_sha256_hex(exe_bytes, hex_out);
        return true;
    }
    exe_bytes.clear();
    if argv0.len > 0 && read_file(argv0, exe_bytes) && exe_bytes.len > 0 {
        cache_sha256_hex(exe_bytes, hex_out);
        return true;
    }
    exe_bytes.clear();
    var rdir: u8[>..] = [];
    if resource_dir(rdir) && rdir.len > 0 {
        var cand: u8[>..] = [];
        cand.append(rdir);
        if win { cand.append("goosew.exe"); } else { cand.append("goosew"); }
        if read_file(cand, exe_bytes) && exe_bytes.len > 0 {
            cache_sha256_hex(exe_bytes, hex_out);
            return true;
        }
    }
    return false;
}

fn cache_append_int(out: u8[>..]&, value: i64) {
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

fn cache_append_field(out: u8[>..]&, tag: const u8[:], value: const u8[:]) {
    out.append(tag); out.push('='); cache_append_int(out, value.len); out.push(':');
    out.append(value); out.push('\n');
}

fn cache_append_int_field(out: u8[>..]&, tag: const u8[:], value: i64) {
    out.append(tag); out.push('='); cache_append_int(out, value); out.push('\n');
}

fn cache_build_key(compiler_hex: const u8[:], mode: i64, opt: i64, debug: bool, library: bool,
                   memory64: bool, bundled_host: bool, region_stats: bool, reachable_program: bool,
                   initial_pages: i64, maximum_pages: i64, expansion_limit: i64, stack_reserve: i64,
                   source_path: const u8[:], stdlib_path: const u8[:], profile_hex: const u8[:],
                   key_hex: u8[>..]&) {
    var raw: u8[>..] = [];
    raw.append("GOOSEW_CACHE_KEY_V1\n");
    cache_append_field(raw, "compiler", compiler_hex);
    cache_append_int_field(raw, "mode", mode);
    cache_append_int_field(raw, "opt", opt);
    cache_append_int_field(raw, "debug", if debug { 1 } else { 0 });
    cache_append_int_field(raw, "library", if library { 1 } else { 0 });
    cache_append_int_field(raw, "memory64", if memory64 { 1 } else { 0 });
    cache_append_int_field(raw, "bundled_host", if bundled_host { 1 } else { 0 });
    cache_append_int_field(raw, "region_stats", if region_stats { 1 } else { 0 });
    cache_append_int_field(raw, "reachable", if reachable_program { 1 } else { 0 });
    cache_append_int_field(raw, "init_pages", initial_pages);
    cache_append_int_field(raw, "max_pages", maximum_pages);
    cache_append_int_field(raw, "exp_limit", expansion_limit);
    cache_append_int_field(raw, "stack_res", stack_reserve);
    cache_append_field(raw, "source", source_path);
    cache_append_field(raw, "stdlib", stdlib_path);
    cache_append_field(raw, "profile", profile_hex);
    cache_sha256_hex(raw, key_hex);
}

fn cache_join_path(dir: const u8[:], prefix: const u8[:], hash: const u8[:], suffix: const u8[:], out: u8[>..]&) {
    out.clear();
    out.append(dir);
    if out.len > 0 && out[out.len - 1] != '/' && out[out.len - 1] != '\\' { out.push('/'); }
    out.append(prefix);
    out.append(hash);
    out.append(suffix);
}

fn cache_parse_uint(text: const u8[:], pos: i64&) -> i64, bool {
    let start = pos;
    var n: i64 = 0;
    while pos < text.len && text[pos] >= '0' && text[pos] <= '9' {
        let d = (text[pos] - '0') as i64;
        if n > (9223372036854775807 - d) / 10 { return 0, false; }
        n = n * 10 + d;
        pos += 1;
    }
    if pos == start { return 0, false; }
    return n, true;
}

fn cache_expect(text: const u8[:], pos: i64&, literal: const u8[:]) -> bool {
    if pos + literal.len > text.len { return false; }
    if !same_bytes(text[pos..pos + literal.len], literal) { return false; }
    pos += literal.len;
    return true;
}

fn cache_is_hex64(slice: const u8[:]) -> bool {
    if slice.len != 64 { return false; }
    for b in slice {
        let ok = (b >= '0' && b <= '9') || (b >= 'a' && b <= 'f');
        if !ok { return false; }
    }
    return true;
}

fn cache_same_norm_path(a: const u8[:], b: const u8[:]) -> bool {
    if a.len == 0 || b.len == 0 { return false; }
    var na: u8[>..] = []; var nb: u8[>..] = [];
    source_normalize(a, na); source_normalize(b, nb);
    return same_bytes(na, nb);
}

fn cache_write_hit_stats(stats_path: const u8[:], mode: i64, functions: i64, module_bytes: i64,
                         source_files: i64, nodes: i64, types: i64) -> bool {
    var out: u8[>..] = [];
    out.append("{\"implementation\":\"goose\",\"backend\":");
    if mode == 1 { out.append("\"native\""); } else { out.append("\"direct\""); }
    out.append(",\"functions\":"); cache_append_int(out, functions);
    out.append(",\"module_bytes\":"); cache_append_int(out, module_bytes);
    out.append(",\"source_files\":"); cache_append_int(out, source_files);
    out.append(",\"nodes\":"); cache_append_int(out, nodes);
    out.append(",\"types\":"); cache_append_int(out, types);
    out.append(",\"parse_ns\":0,\"typecheck_ns\":0,\"lifetime_ns\":0,\"optimize_ns\":0,\"backend_ns\":0");
    out.append(",\"function_info\":[],\"function_names\":[],\"cache_complete\":true,\"cache_hit\":true}\n");
    return write_file(stats_path, out);
}

// Returns 0 on cache miss, 1 on valid cache hit (outputs already written),
// -1 on collision or output write error (diagnostic already printed to stderr).
fn cache_try_hit(cache_dir: const u8[:], key_hex: const u8[:], expected_mode: i64,
                 output_path: const u8[:], stats_path: const u8[:]) -> i64 {
    if !is_dir(cache_dir) { return 0; }
    var mpath: u8[>..] = [];
    cache_join_path(cache_dir, "m_", key_hex, ".manifest", mpath);
    var mtext: u8[>..] = [];
    if !read_file(mpath, mtext) || mtext.len < 80 { return 0; }

    // Verify manifest integrity footer: "END <64-hex>\n"
    if mtext[mtext.len - 1] != '\n' { return 0; }
    let footer_start = mtext.len - 69;
    if footer_start <= 0 { return 0; }
    if !same_bytes(mtext[footer_start..footer_start + 4], "END ") { return 0; }
    let footer_hex = mtext[footer_start + 4..footer_start + 68];
    if !cache_is_hex64(footer_hex) { return 0; }
    var body_hex: u8[>..] = [];
    cache_sha256_hex(mtext[..footer_start], body_hex);
    if !same_bytes(body_hex, footer_hex) { return 0; }

    let body = mtext[..footer_start];
    var pos: i64 = 0;
    if !cache_expect(body, pos, "GOOSEW_CACHE_V1\nkey ") { return 0; }
    if pos + 65 > body.len { return 0; }
    if !same_bytes(body[pos..pos + 64], key_hex) || body[pos + 64] != '\n' { return 0; }
    pos += 65;

    if !cache_expect(body, pos, "mode ") { return 0; }
    let mode, ok_m = cache_parse_uint(body, pos);
    if !ok_m || mode != expected_mode || !cache_expect(body, pos, "\nblob ") { return 0; }
    if pos + 65 > body.len { return 0; }
    let blob_hex = body[pos..pos + 64];
    if !cache_is_hex64(blob_hex) || body[pos + 64] != ' ' { return 0; }
    pos += 65;
    let blob_len, ok_bl = cache_parse_uint(body, pos);
    if !ok_bl || !cache_expect(body, pos, "\nstats ") { return 0; }

    let s_fns, ok1 = cache_parse_uint(body, pos); if !ok1 || !cache_expect(body, pos, " ") { return 0; }
    let s_bytes, ok2 = cache_parse_uint(body, pos); if !ok2 || !cache_expect(body, pos, " ") { return 0; }
    let s_files, ok3 = cache_parse_uint(body, pos); if !ok3 || !cache_expect(body, pos, " ") { return 0; }
    let s_nodes, ok4 = cache_parse_uint(body, pos); if !ok4 || !cache_expect(body, pos, " ") { return 0; }
    let s_types, ok5 = cache_parse_uint(body, pos); if !ok5 || !cache_expect(body, pos, "\nentries ") { return 0; }

    let entry_count, ok_ec = cache_parse_uint(body, pos);
    if !ok_ec || !cache_expect(body, pos, "\n") { return 0; }

    if output_path.len > 0 && stats_path.len > 0 && cache_same_norm_path(output_path, stats_path) {
        write_stderr("goosew: statistics would overwrite a source file or another output\n");
        return -1;
    }

    var file_buf: u8[>..] = [];
    var file_hex: u8[>..] = [];
    for _ in 0..entry_count {
        if pos + 2 > body.len { return 0; }
        let kind = body[pos];
        if body[pos + 1] != ' ' { return 0; }
        pos += 2;
        if kind == 'F' {
            let flen, ok_fl = cache_parse_uint(body, pos);
            if !ok_fl || !cache_expect(body, pos, " ") || pos + 65 > body.len { return 0; }
            let fhex = body[pos..pos + 64];
            if !cache_is_hex64(fhex) || body[pos + 64] != ' ' { return 0; }
            pos += 65;
            let plen, ok_pl = cache_parse_uint(body, pos);
            if !ok_pl || !cache_expect(body, pos, "\n") || pos + plen + 1 > body.len { return 0; }
            let fpath = body[pos..pos + plen];
            pos += plen;
            if body[pos] != '\n' { return 0; }
            pos += 1;
            if output_path.len > 0 && cache_same_norm_path(output_path, fpath) {
                write_stderr("goosew: output would overwrite a source file\n");
                return -1;
            }
            if stats_path.len > 0 && cache_same_norm_path(stats_path, fpath) {
                write_stderr("goosew: statistics would overwrite a source file or another output\n");
                return -1;
            }
            file_buf.clear();
            if !read_file(fpath, file_buf) { return 0; }
            if file_buf.len != flen { return 0; }
            file_hex.clear();
            cache_sha256_hex(file_buf, file_hex);
            if !same_bytes(file_hex, fhex) { return 0; }
        } else if kind == 'A' {
            let plen, ok_pl = cache_parse_uint(body, pos);
            if !ok_pl || !cache_expect(body, pos, "\n") || pos + plen + 1 > body.len { return 0; }
            let apath = body[pos..pos + plen];
            pos += plen;
            if body[pos] != '\n' { return 0; }
            pos += 1;
            if output_path.len > 0 && cache_same_norm_path(output_path, apath) {
                write_stderr("goosew: output would overwrite a source file\n");
                return -1;
            }
            if stats_path.len > 0 && cache_same_norm_path(stats_path, apath) {
                write_stderr("goosew: statistics would overwrite a source file or another output\n");
                return -1;
            }
            if file_exists(apath) { return 0; }
        } else if kind == 'D' {
            let plen, ok_pl = cache_parse_uint(body, pos);
            if !ok_pl || !cache_expect(body, pos, "\n") || pos + plen + 1 > body.len { return 0; }
            let dpath = body[pos..pos + plen];
            pos += plen;
            if body[pos] != '\n' { return 0; }
            pos += 1;
            if !is_dir(dpath) { return 0; }
        } else {
            return 0;
        }
    }
    if pos != body.len { return 0; }

    if mode != 2 {
        var already_ok = false;
        if file_exists(output_path) {
            var existing: u8[>..] = [];
            if read_file(output_path, existing) && existing.len == blob_len {
                var ex_hex: u8[>..] = [];
                cache_sha256_hex(existing, ex_hex);
                if same_bytes(ex_hex, blob_hex) { already_ok = true; }
            }
        }
        if !already_ok {
            var bpath: u8[>..] = [];
            cache_join_path(cache_dir, "b_", blob_hex, ".bin", bpath);
            var blob: u8[>..] = [];
            if !read_file(bpath, blob) { return 0; }
            if blob.len != blob_len { return 0; }
            var actual_hex: u8[>..] = [];
            cache_sha256_hex(blob, actual_hex);
            if !same_bytes(actual_hex, blob_hex) { return 0; }
            if !write_file(output_path, blob) {
                write_stderr("goosew: cannot write output\n");
                return -1;
            }
        }
    }
    if stats_path.len > 0 {
        if !cache_write_hit_stats(stats_path, mode, s_fns, s_bytes, s_files, s_nodes, s_types) {
            write_stderr("goosew: cannot write statistics\n");
            return -1;
        }
    }
    return 1;
}

struct CacheEntryRec {
    kind: i64 = 0, // 0 = file, 1 = absent, 2 = dir
    path_start: i64 = 0, path_len: i64 = 0,
    file_len: i64 = 0,
    hex_start: i64 = 0,
}

fn cache_store_entry(p: Program&, cache_dir: const u8[:], key_hex: const u8[:], mode: i64,
                     output: const u8[:]) -> bool {
    if !is_dir(cache_dir) { return false; }

    var path_pool: u8[>..] = [];
    var hex_pool: u8[>..] = [];
    var entries: CacheEntryRec[>..] = [];
    var tmp_hex: u8[>..] = [];
    var verify_buf: u8[>..] = [];
    var verify_hex: u8[>..] = [];

    // 1. Collect all positive files from p.sources (sources + embed_file) and verify disk consistency.
    for s in p.sources {
        let spath = p.text[s.path_start..s.path_start + s.path_len];
        let sdata = p.text[s.text_start..s.text_start + s.text_len];
        tmp_hex.clear();
        cache_sha256_hex(sdata, tmp_hex);
        var dup = false;
        for e in entries {
            if e.kind == 0 && same_bytes(path_pool[e.path_start..e.path_start + e.path_len], spath) {
                if e.file_len != sdata.len || !same_bytes(hex_pool[e.hex_start..e.hex_start + 64], tmp_hex) {
                    return false;
                }
                dup = true; break;
            }
        }
        if dup { continue; }
        // Re-verify disk contents to prevent retaining a mid-build raced snapshot.
        verify_buf.clear();
        if !read_file(spath, verify_buf) || verify_buf.len != sdata.len { return false; }
        verify_hex.clear();
        cache_sha256_hex(verify_buf, verify_hex);
        if !same_bytes(verify_hex, tmp_hex) { return false; }
        let pstart = path_pool.len; path_pool.append(spath);
        let hstart = hex_pool.len; hex_pool.append(tmp_hex);
        entries.push(CacheEntryRec { kind: 0, path_start: pstart, path_len: spath.len, file_len: sdata.len, hex_start: hstart });
    }

    // 2. Collect recorded probes (embedded shader files, absent local import probes, package dirs).
    for pr in p.cache_probes {
        let ppath = p.cache_probe_text[pr.path_start..pr.path_start + pr.path_len];
        if pr.kind == CACHE_PROBE_FILE {
            let pdata = p.cache_probe_text[pr.data_start..pr.data_start + pr.data_len];
            tmp_hex.clear();
            cache_sha256_hex(pdata, tmp_hex);
            var dup = false;
            for e in entries {
                if same_bytes(path_pool[e.path_start..e.path_start + e.path_len], ppath) {
                    if e.kind == 1 { return false; } // conflicted with absent probe
                    if e.kind == 0 {
                        if e.file_len != pdata.len || !same_bytes(hex_pool[e.hex_start..e.hex_start + 64], tmp_hex) {
                            return false;
                        }
                        dup = true; break;
                    }
                }
            }
            if dup { continue; }
            verify_buf.clear();
            if !read_file(ppath, verify_buf) || verify_buf.len != pdata.len { return false; }
            verify_hex.clear();
            cache_sha256_hex(verify_buf, verify_hex);
            if !same_bytes(verify_hex, tmp_hex) { return false; }
            let pstart = path_pool.len; path_pool.append(ppath);
            let hstart = hex_pool.len; hex_pool.append(tmp_hex);
            entries.push(CacheEntryRec { kind: 0, path_start: pstart, path_len: ppath.len, file_len: pdata.len, hex_start: hstart });
        } else if pr.kind == CACHE_PROBE_ABSENT_FILE {
            var dup = false;
            for e in entries {
                if same_bytes(path_pool[e.path_start..e.path_start + e.path_len], ppath) {
                    if e.kind == 0 { return false; } // conflicted with positive file
                    if e.kind == 1 { dup = true; break; }
                }
            }
            if dup { continue; }
            if file_exists(ppath) { return false; }
            let pstart = path_pool.len; path_pool.append(ppath);
            entries.push(CacheEntryRec { kind: 1, path_start: pstart, path_len: ppath.len });
        } else if pr.kind == CACHE_PROBE_DIR {
            var dup = false;
            for e in entries {
                if e.kind == 2 && same_bytes(path_pool[e.path_start..e.path_start + e.path_len], ppath) {
                    dup = true; break;
                }
            }
            if dup { continue; }
            if !is_dir(ppath) { return false; }
            let pstart = path_pool.len; path_pool.append(ppath);
            entries.push(CacheEntryRec { kind: 2, path_start: pstart, path_len: ppath.len });
        }
    }

    // 3. Publish artifact blob first (if not --check).
    var blob_hex: u8[>..] = [];
    if mode == 2 {
        cache_sha256_hex("", blob_hex);
    } else {
        cache_sha256_hex(output, blob_hex);
        var bpath: u8[>..] = [];
        cache_join_path(cache_dir, "b_", blob_hex, ".bin", bpath);
        var need_blob = true;
        if file_exists(bpath) {
            verify_buf.clear();
            if read_file(bpath, verify_buf) && verify_buf.len == output.len {
                verify_hex.clear();
                cache_sha256_hex(verify_buf, verify_hex);
                if same_bytes(verify_hex, blob_hex) { need_blob = false; }
            }
        }
        if need_blob && !write_file(bpath, output) { return false; }
    }

    // 4. Build and write manifest with trailing SHA-256 footer.
    var functions: i64 = 0;
    for symbol in p.symbols {
        if (symbol.flags & S_FUNCTION) != 0 && symbol.node >= 0 && (p.nodes[symbol.node].flags & F_REACHABLE) != 0 {
            functions += 1;
        }
    }
    var mbody: u8[>..] = [];
    mbody.append("GOOSEW_CACHE_V1\nkey "); mbody.append(key_hex); mbody.push('\n');
    mbody.append("mode "); cache_append_int(mbody, mode); mbody.push('\n');
    mbody.append("blob "); mbody.append(blob_hex); mbody.push(' ');
    cache_append_int(mbody, if mode == 2 { 0 } else { output.len }); mbody.push('\n');
    mbody.append("stats ");
    cache_append_int(mbody, functions); mbody.push(' ');
    cache_append_int(mbody, if mode == 2 { 0 } else { output.len }); mbody.push(' ');
    cache_append_int(mbody, p.sources.len); mbody.push(' ');
    cache_append_int(mbody, p.nodes.len); mbody.push(' ');
    cache_append_int(mbody, p.types.len); mbody.push('\n');
    mbody.append("entries "); cache_append_int(mbody, entries.len); mbody.push('\n');
    for e in entries {
        let ep = path_pool[e.path_start..e.path_start + e.path_len];
        if e.kind == 0 {
            mbody.append("F "); cache_append_int(mbody, e.file_len); mbody.push(' ');
            mbody.append(hex_pool[e.hex_start..e.hex_start + 64]); mbody.push(' ');
            cache_append_int(mbody, ep.len); mbody.push('\n');
            mbody.append(ep); mbody.push('\n');
        } else if e.kind == 1 {
            mbody.append("A "); cache_append_int(mbody, ep.len); mbody.push('\n');
            mbody.append(ep); mbody.push('\n');
        } else {
            mbody.append("D "); cache_append_int(mbody, ep.len); mbody.push('\n');
            mbody.append(ep); mbody.push('\n');
        }
    }
    var mhex: u8[>..] = [];
    cache_sha256_hex(mbody, mhex);
    mbody.append("END "); mbody.append(mhex); mbody.push('\n');

    var mpath: u8[>..] = [];
    cache_join_path(cache_dir, "m_", key_hex, ".manifest", mpath);
    return write_file(mpath, mbody);
}
