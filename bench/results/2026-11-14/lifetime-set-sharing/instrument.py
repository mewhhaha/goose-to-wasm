"""Instrument a copy of checker_lifetimes.goose for equivalence checks and progress.

usage: instrument.py SELFHOST_COPY MODE (edits SELFHOST_COPY/checker_lifetimes.goose)
MODE fingerprint: at each discovery pass start, on failure, after discovery and
  after validation, print to stderr a hash of the analysis state: every set
  reachable from roots, cells, frames, effects, summaries, atoms, items, exits
  and the offer memo, by ID (LifeSet.vid where the source has it) with its
  ordered alternatives, plus table sizes and counters. A baseline and a
  candidate built from instrumented copies must print the same lines.
MODE progress: print table sizes and counters every 1,000 new frames and at
  pass boundaries (the frame counts in README.md).
Build the copy as bootstrap does (beside native/ and stdlib/: goose
selfhost/main.goose --stdlib stdlib --target native -O2 -o x.c, then clang)
and compare two builds with fpcompare.py.
"""
import sys, re
d, mode = sys.argv[1], sys.argv[2]
f = d + '/checker_lifetimes.goose'
s = open(f).read()

def rep(old, new, count=1):
    global s
    assert s.count(old) == count, (old[:100], s.count(old))
    s = s.replace(old, new)

s = s.replace('import model;', 'import model;\nimport os;', 1)

helpers = r'''
fn dbg_num(out: u8[>..]&, value: i64) {
    var digits: u8[>..] = [];
    var n = value as! u64;
    if value < 0 { out.push('-'); n = (-(value + 1)) as u64 + 1; }
    loop { digits.push((n % 10) as u8 + '0'); n /= 10; if n == 0 { break; } }
    var i = digits.len;
    while i > 0 { i -= 1; out.push(digits[i]); }
}
fn dbg_kv(out: u8[>..]&, key: const u8[:], value: i64) { out.append(" "); out.append(key); out.push('='); dbg_num(out, value); }
fn dbg_mix(h: u64, v: i64) -> u64 { var x = (h ^ (v as! u64)) * 1099511628211; x ^= x >> 29; return x; }
fn dbg_set(l: Lifetimes&, h: u64, set: i64) -> u64 {
    var x = dbg_mix(h, dbg_vid(l, set));
    if set < 0 || set >= l.sets.len { return x; }
    x = dbg_mix(x, l.sets[set].count);
    var at = l.sets[set].first;
    while at >= 0 {
        let a = l.alts[at];
        x = dbg_mix(x, a.root); x = dbg_mix(x, a.from); x = dbg_mix(x, a.target_type); x = dbg_mix(x, a.bound); x = dbg_mix(x, a.component);
        var flags = 0; if a.exact { flags += 1; } if a.slotread { flags += 2; } if a.byteview { flags += 4; }
        x = dbg_mix(x, flags); at = a.next;
    }
    return x;
}
fn dbg_value(l: Lifetimes&, h: u64, v: LifeValue) -> u64 {
    var x = dbg_mix(h, v.type_id); x = dbg_set(l, x, v.place); x = dbg_set(l, x, v.refs); x = dbg_set(l, x, v.contents);
    x = dbg_set(l, x, v.self_pools); x = dbg_set(l, x, v.relative_roots); x = dbg_mix(x, v.tuple); x = dbg_mix(x, v.element_array);
    return x;
}
fn dbg_fingerprint(p: Program&, l: Lifetimes&, tag: const u8[:]) {
    var h: u64 = 1469598103934665603;
    h = dbg_mix(h, DBG_SETS_LEN); h = dbg_mix(h, l.frames.len); h = dbg_mix(h, l.effects.len); h = dbg_mix(h, l.revision);
    h = dbg_mix(h, l.pass); h = dbg_mix(h, l.roots.len); h = dbg_mix(h, l.cells.len); h = dbg_mix(h, l.atoms.len); h = dbg_mix(h, l.items.len);
    h = dbg_mix(h, l.activations); h = dbg_mix(h, l.recursion_epoch); h = dbg_mix(h, p.diagnostics.len); h = dbg_mix(h, l.failures.len);
    var bound_sum: u64 = 0;
    for set, index in l.sets { if set.bound_depth != -1 { var b = dbg_mix(5, dbg_vid(l, index)); b = dbg_mix(b, set.bound_depth); b = dbg_mix(b, dbg_vid(l, set.bound_result)); bound_sum += b; } }
    h = dbg_mix(h, bound_sum as! i64);
    var hr: u64 = 7;
    for root in l.roots { hr = dbg_set(l, hr, root.contents); hr = dbg_set(l, hr, root.live_contents); hr = dbg_mix(hr, root.atoms); hr = dbg_mix(hr, root.depth); hr = dbg_mix(hr, root.frame); }
    var hc: u64 = 11;
    for cell in l.cells {
        hc = dbg_set(l, hc, cell.refs); hc = dbg_set(l, hc, cell.live_refs); hc = dbg_set(l, hc, cell.initial); hc = dbg_set(l, hc, cell.contents);
        var flags = 0; if cell.live { flags += 1; } if cell.committed { flags += 2; } if cell.growshrink { flags += 4; } if cell.initialized { flags += 8; }
        hc = dbg_mix(hc, flags); hc = dbg_mix(hc, cell.depth); hc = dbg_mix(hc, cell.next_frame);
    }
    var hf: u64 = 13;
    for frame in l.frames {
        hf = dbg_value(l, hf, frame.result); hf = dbg_set(l, hf, frame.destination); hf = dbg_mix(hf, frame.inputs); hf = dbg_mix(hf, frame.parent);
        hf = dbg_mix(hf, frame.first_summary); hf = dbg_mix(hf, frame.last_summary); hf = dbg_mix(hf, frame.first_effect); hf = dbg_mix(hf, frame.last_effect);
        hf = dbg_mix(hf, frame.checked_revision); hf = dbg_mix(hf, frame.cycle); hf = dbg_mix(hf, frame.activation); hf = dbg_mix(hf, frame.capture_inputs);
    }
    var he: u64 = 17;
    for effect in l.effects {
        he = dbg_mix(he, effect.kind); he = dbg_mix(he, effect.node); he = dbg_value(l, he, effect.value); he = dbg_set(l, he, effect.places);
        he = dbg_mix(he, effect.cell); he = dbg_mix(he, effect.field); he = dbg_mix(he, effect.next); he = dbg_mix(he, effect.previous); he = dbg_mix(he, effect.owner);
    }
    var hs: u64 = 19;
    for summary in l.summaries { hs = dbg_mix(hs, dbg_vid(l, summary.places)); hs = dbg_mix(hs, dbg_vid(l, summary.refs)); hs = dbg_mix(hs, dbg_vid(l, summary.contents)); hs = dbg_mix(hs, dbg_vid(l, summary.place)); hs = dbg_mix(hs, summary.next); }
    var ha: u64 = 23;
    for atom in l.atoms { ha = dbg_set(l, ha, atom.set); ha = dbg_mix(ha, atom.next); }
    var hi: u64 = 29;
    for item in l.items { hi = dbg_value(l, hi, item.value); hi = dbg_mix(hi, item.next); }
    for exit in l.exits { hi = dbg_value(l, hi, exit.value); hi = dbg_set(l, hi, exit.destination); }
    for offer in l.offers { hi = dbg_mix(hi, dbg_vid(l, offer.places)); hi = dbg_mix(hi, dbg_vid(l, offer.refs)); hi = dbg_mix(hi, dbg_vid(l, offer.contents)); hi = dbg_mix(hi, dbg_vid(l, offer.place)); hi = dbg_mix(hi, offer.activation); }
    var out: u8[>..] = [];
    out.append("LIFEFP "); out.append(tag);
    dbg_kv(out, "pass", l.pass); dbg_kv(out, "sets", DBG_SETS_LEN); dbg_kv(out, "frames", l.frames.len); dbg_kv(out, "effects", l.effects.len); dbg_kv(out, "rev", l.revision);
    dbg_kv(out, "h", (h >> 1) as! i64); dbg_kv(out, "roots", (hr >> 1) as! i64); dbg_kv(out, "cells", (hc >> 1) as! i64); dbg_kv(out, "frames", (hf >> 1) as! i64);
    dbg_kv(out, "effects", (he >> 1) as! i64); dbg_kv(out, "summaries", (hs >> 1) as! i64); dbg_kv(out, "atoms", (ha >> 1) as! i64); dbg_kv(out, "items", (hi >> 1) as! i64);
    out.push('\n'); write_stderr(out);
}
fn dbg_progress(p: Program&, l: Lifetimes&, tag: const u8[:]) {
    var out: u8[>..] = [];
    out.append("LIFEPROG "); out.append(tag);
    dbg_kv(out, "ms", clock_ns() / 1000000);
    dbg_kv(out, "pass", l.pass); dbg_kv(out, "rev", l.revision); dbg_kv(out, "frames", l.frames.len); dbg_kv(out, "effects", l.effects.len);
    dbg_kv(out, "sets", l.sets.len); dbg_kv(out, "alts", l.alts.len); dbg_kv(out, "cells", l.cells.len); dbg_kv(out, "roots", l.roots.len);
    dbg_kv(out, "atoms", l.atoms.len); dbg_kv(out, "items", l.items.len); dbg_kv(out, "summaries", l.summaries.len);
    out.push('\n'); write_stderr(out);
}
'''
if 'vid: i64 = 0' in s:
    helpers = helpers.replace('DBG_SETS_LEN', 'l.vids')
    helpers += '\nfn dbg_vid(l: Lifetimes&, set: i64) -> i64 { if set < 0 || set >= l.sets.len { return set; } return l.sets[set].vid; }\n'
else:
    helpers = helpers.replace('DBG_SETS_LEN', 'l.sets.len')
    helpers += '\nfn dbg_vid(l: Lifetimes&, set: i64) -> i64 { return set; }\n'
s = s.replace('\nfn check_lifetimes(', helpers + '\nfn check_lifetimes(', 1)
call = 'dbg_fingerprint' if mode == 'fingerprint' else 'dbg_progress'
rep("""    loop {
        l.pass += 1;
        let before = l.revision;""", """    loop {
        l.pass += 1;
        %s(p, l, "pass_begin");
        let before = l.revision;""" % call)
rep("""            for failure in l.failures { life_error(p, l, failure.node, failure.message); }
            l.types_frozen = false;
            return;""", """            for failure in l.failures { life_error(p, l, failure.node, failure.message); }
            %s(p, l, "failed");
            l.types_frozen = false;
            return;""" % call)
rep("""    l.discovery = false;
    for root, index in l.roots { l.roots[index].live_contents = root.contents; }""", """    %s(p, l, "discovered");
    l.discovery = false;
    for root, index in l.roots { l.roots[index].live_contents = root.contents; }""" % call)
rep("""    l.types_frozen = false;
    if p.diagnostics.len == 0 { life_export_provenance(p, l); life_refresh_named_results(p); }""", """    l.types_frozen = false;
    %s(p, l, "validated");
    if p.diagnostics.len == 0 { life_export_provenance(p, l); life_refresh_named_results(p); }""" % call)
if mode == 'progress' and 'fn life_build_step' in s:
    _a = s.index('struct Lifetimes {'); _b = s.index('\n}\n', _a)
    s = s[:_b] + '\n    __COUNTERS__' + s[_b:]
    rep("    __COUNTERS__\n}", """
    c_place: i64 = 0, c_mat: i64 = 0, c_mat_alts: i64 = 0, c_cand: i64 = 0, c_cand_alts: i64 = 0, c_rb: i64 = 0, c_rb_alts: i64 = 0,
    c_jbig: i64 = 0, c_jbig_alts: i64 = 0, c_jsmall: i64 = 0, c_single: i64 = 0, c_next_sets: i64 = 2000000, c_next_alts: i64 = 4000000,
    c_bound: i64 = 0, c_bound_alts: i64 = 0, c_clear: i64 = 0, c_clear_alts: i64 = 0, c_param: i64 = 0, c_param_alts: i64 = 0, c_stored: i64 = 0, c_stored_alts: i64 = 0,
    c_interior: i64 = 0, c_interior_alts: i64 = 0, c_contents: i64 = 0, c_contents_alts: i64 = 0, c_load: i64 = 0, c_load_alts: i64 = 0,
}""")
    rep("""    b.vid = l.vids; l.vids += 1; b.fresh = true; b.flipped = !b.flipped;""",
        """    b.vid = l.vids; l.vids += 1; b.fresh = true; b.flipped = !b.flipped; l.c_place += 1;""")
    if 'fn life_list_set' in s:
        rep("""        b.set = life_list_set(l, start, b.vid); b.fresh = false;""",
            """        b.set = life_list_set(l, start, b.vid); b.fresh = false; l.c_mat += 1; l.c_mat_alts += b.size;""")
        rep("""            l.sets.push(LifeSet { first: shared.first, count: count, index: shared.index, index_mask: shared.index_mask, vid: vid });""",
            """            l.sets.push(LifeSet { first: shared.first, count: count, index: shared.index, index_mask: shared.index_mask, vid: vid }); l.c_clear += 1; l.c_clear_alts += count;""")
        grow = """    if l.alts.len >= l.c_next_alts || l.sets.len >= l.c_next_sets {
        while l.alts.len >= l.c_next_alts { l.c_next_alts += 4000000; } while l.sets.len >= l.c_next_sets { l.c_next_sets += 2000000; }
        dbg_progress_l(l, "grow");
    }
"""
        for old in ("""    var next = -1; var at = l.scratch.len - 1;
    while at >= start {""", """    var next = -1;
    for item in start..l.scratch.len {"""):
            if old in s: rep(old, grow + old)
        rep("""        if !known { var candidates = LifeBuild {}; life_candidates(p, l, t.element, root.depth, global, candidates); life_build_drop(l, candidates); }""",
            """        if !known { var candidates = LifeBuild {}; life_candidates(p, l, t.element, root.depth, global, candidates); life_build_drop(l, candidates); l.c_cand += 1; l.c_cand_alts += l.scratch.len - start; }""")
    else:
        rep("""        b.set = l.sets.len; l.sets.push(LifeSet { first: next, count: b.size, vid: b.vid }); b.fresh = false;""",
            """        b.set = l.sets.len; l.sets.push(LifeSet { first: next, count: b.size, vid: b.vid }); b.fresh = false; l.c_mat += 1; l.c_mat_alts += b.size;""")
    rep("""        var build = LifeBuild { set: a }; life_build_open(l, build); life_build_step(l, build, b);""",
        """        l.c_jbig += 1; l.c_jbig_alts += l.sets[a].count + l.sets[b].count;
        var build = LifeBuild { set: a }; life_build_open(l, build); life_build_step(l, build, b);""")
    if """    let set = life_new_set(l);
    var at = l.sets[a].first;""" in s:
        rep("""    let set = life_new_set(l);
    var at = l.sets[a].first;""", """    let set = life_new_set(l); l.c_jsmall += 1;
    var at = l.sets[a].first;""")
    else:
        rep("""    let vid = l.vids; l.vids += 1; let start = l.scratch.len;""", """    let vid = l.vids; l.vids += 1; let start = l.scratch.len; l.c_jsmall += 1;""")
    if 'life_insert(l, set, wanted);' in s:
        rep("""    let set = life_new_set(l);
    life_insert(l, set, wanted);""", """    let set = life_new_set(l); l.c_single += 1;
    life_insert(l, set, wanted);""")
    else:
        rep("""    let set = life_new_set(l);
    life_insert(l, set, LifeAlt {""", """    let set = life_new_set(l); l.c_single += 1;
    life_insert(l, set, LifeAlt {""")
    def wrap(fname, counter, ret_pat):
        global s
        m = re.search(r'^(recursive )?fn ' + fname + r'\(', s, re.M)
        assert m, fname
        start = m.start(); end = s.index('\n}\n', start) + 3
        body = s[start:end]
        n = body.count(ret_pat)
        if n == 0: return
        body = body.replace(ret_pat, 'let dbg_result = %s; l.%s += 1; l.%s_alts += l.sets[dbg_result].count; return dbg_result;' % (ret_pat[len('return '):-1], counter, counter))
        s = s[:start] + body + s[end:]
    wrap('life_candidates', 'c_cand', 'return life_build_end(l, out);')
    wrap('life_readback', 'c_rb', 'return life_build_end(l, result);')
    wrap('life_parameter_roots', 'c_param', 'return life_build_end(l, result);')
    wrap('life_stored_roots', 'c_stored', 'return life_build_end(l, contents);')
    wrap('life_interior', 'c_interior', 'return life_build_end(l, out);')
    wrap('life_contents', 'c_contents', 'return life_build_end(l, result);')
    rep("""    let result = life_build_end(l, build);
    l.sets[sources].bound_depth = depth;""", """    let result = life_build_end(l, build); l.c_bound += 1; l.c_bound_alts += l.sets[result].count;
    l.sets[sources].bound_depth = depth;""")
    rep("""    dbg_kv(out, "atoms", l.atoms.len); dbg_kv(out, "items", l.items.len); dbg_kv(out, "summaries", l.summaries.len);
    out.push('\\n'); write_stderr(out);""", """    dbg_kv(out, "atoms", l.atoms.len); dbg_kv(out, "items", l.items.len); dbg_kv(out, "summaries", l.summaries.len);
    dbg_kv(out, "set_index", l.set_index.len); dbg_kv(out, "vids", l.vids); dbg_kv(out, "place", l.c_place); dbg_kv(out, "mat", l.c_mat); dbg_kv(out, "mat_alts", l.c_mat_alts);
    dbg_kv(out, "jbig", l.c_jbig); dbg_kv(out, "jbig_alts", l.c_jbig_alts); dbg_kv(out, "jsmall", l.c_jsmall); dbg_kv(out, "single", l.c_single);
    dbg_kv(out, "cand", l.c_cand); dbg_kv(out, "cand_alts", l.c_cand_alts); dbg_kv(out, "rb", l.c_rb); dbg_kv(out, "rb_alts", l.c_rb_alts);
    dbg_kv(out, "bound", l.c_bound); dbg_kv(out, "bound_alts", l.c_bound_alts); dbg_kv(out, "clear", l.c_clear); dbg_kv(out, "clear_alts", l.c_clear_alts);
    dbg_kv(out, "param", l.c_param); dbg_kv(out, "param_alts", l.c_param_alts); dbg_kv(out, "stored", l.c_stored); dbg_kv(out, "stored_alts", l.c_stored_alts);
    dbg_kv(out, "interior", l.c_interior); dbg_kv(out, "interior_alts", l.c_interior_alts); dbg_kv(out, "contents", l.c_contents); dbg_kv(out, "contents_alts", l.c_contents_alts);
    out.push('\\n'); write_stderr(out);""")
    if 'fn life_build_link' in s:
        rep("""fn life_build_link(l: Lifetimes&, index: i64, next: i64) -> i64 {""", """fn life_build_link(l: Lifetimes&, index: i64, next: i64) -> i64 {
    if l.alts.len >= l.c_next_alts || l.sets.len >= l.c_next_sets {
        while l.alts.len >= l.c_next_alts { l.c_next_alts += 4000000; } while l.sets.len >= l.c_next_sets { l.c_next_sets += 2000000; }
        dbg_progress_l(l, "grow");
    }""")
    s = s.replace('\nfn dbg_progress(', '''
fn dbg_progress_l(l: Lifetimes&, tag: const u8[:]) {
    var out: u8[>..] = [];
    out.append("LIFEPROG "); out.append(tag);
    dbg_kv(out, "ms", clock_ns() / 1000000); dbg_kv(out, "pass", l.pass); dbg_kv(out, "frames", l.frames.len); dbg_kv(out, "sets", l.sets.len); dbg_kv(out, "vids", l.vids); dbg_kv(out, "alts", l.alts.len);
    dbg_kv(out, "place", l.c_place); dbg_kv(out, "mat", l.c_mat); dbg_kv(out, "mat_alts", l.c_mat_alts); dbg_kv(out, "jbig", l.c_jbig); dbg_kv(out, "jbig_alts", l.c_jbig_alts);
    dbg_kv(out, "cand", l.c_cand); dbg_kv(out, "cand_alts", l.c_cand_alts); dbg_kv(out, "rb", l.c_rb); dbg_kv(out, "rb_alts", l.c_rb_alts);
    dbg_kv(out, "bound", l.c_bound); dbg_kv(out, "bound_alts", l.c_bound_alts); dbg_kv(out, "clear", l.c_clear); dbg_kv(out, "clear_alts", l.c_clear_alts);
    dbg_kv(out, "param", l.c_param); dbg_kv(out, "param_alts", l.c_param_alts); dbg_kv(out, "stored", l.c_stored); dbg_kv(out, "stored_alts", l.c_stored_alts);
    dbg_kv(out, "interior", l.c_interior); dbg_kv(out, "interior_alts", l.c_interior_alts); dbg_kv(out, "contents", l.c_contents); dbg_kv(out, "contents_alts", l.c_contents_alts);
    out.push('\\n'); write_stderr(out);
}
fn dbg_progress(''', 1)
if mode == 'progress':
    rep("""    if function_node < 0 || p.nodes[function_node].right < 0 { return LifeValue {}; }
    var lexical = 0;""", """    if function_node < 0 || p.nodes[function_node].right < 0 { return LifeValue {}; }
    if l.frames.len >= dbg_next_frames { dbg_next_frames += 1000; dbg_progress(p, l, "frames"); }
    var lexical = 0;""")
    s = s.replace('\nfn dbg_progress(', '\nvar dbg_next_frames: i64 = 1000;\nfn dbg_progress(', 1)
open(f, 'w').write(s)
