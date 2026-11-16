"""progress.py SELFHOST_COPY: prints table sizes every 1,000 new frames and at
pass boundaries (LIFEPROG lines on stderr). Only reads state; adds no
counters to the analysis."""
import sys
d = sys.argv[1]
f = d + '/checker_lifetimes.goose'
s = open(f).read()

def rep(old, new):
    global s
    assert s.count(old) == 1, (old[:100], s.count(old))
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
var dbg_next_frames: i64 = 1000;
fn dbg_progress(l: Lifetimes&, tag: const u8[:]) {
    var out: u8[>..] = [];
    out.append("LIFEPROG "); out.append(tag);
    dbg_kv(out, "ms", clock_ns() / 1000000);
    dbg_kv(out, "pass", l.pass); dbg_kv(out, "rev", l.revision); dbg_kv(out, "frames", l.frames.len); dbg_kv(out, "effects", l.effects.len);
    dbg_kv(out, "sets", l.sets.len); dbg_kv(out, "alts", l.alts.len); dbg_kv(out, "cells", l.cells.len); dbg_kv(out, "roots", l.roots.len);
    dbg_kv(out, "atoms", l.atoms.len); dbg_kv(out, "atom_slots", l.atom_slots.len); dbg_kv(out, "items", l.items.len); dbg_kv(out, "summaries", l.summaries.len);
    dbg_kv(out, "lists", l.list_sets.len); dbg_kv(out, "set_index", l.set_index.len); dbg_kv(out, "activations", l.activations);
    dbg_kv(out, "reads", l.reads.len); dbg_kv(out, "pairs", l.pairs.len); dbg_kv(out, "exits", l.exits.len); dbg_kv(out, "kills", l.kills.len);
    out.push('\n'); write_stderr(out);
}
'''
extra = ''
for field in ['global_epoch', 'candidate_alts.len', 'global_cells.len', 'readback_memo.len', 'class_frames', 'assumes.len', 'class_keys.len', 'map_sets.len']:
    if field.split('.')[0] + ':' in s:
        extra += '    dbg_kv(out, "%s", l.%s);\n' % (field.replace('.len', ''), field)
helpers = helpers.replace("    out.push('\\n'); write_stderr(out);\n}", extra + "    out.push('\\n'); write_stderr(out);\n}")
s = s.replace('\nfn check_lifetimes(', helpers + '\nfn check_lifetimes(', 1)
rep("""    loop {
        l.pass += 1;
        let before = l.revision;""", """    loop {
        l.pass += 1;
        dbg_progress(l, "pass_begin");
        let before = l.revision;""")
rep("""            for failure in l.failures { life_error(p, l, failure.node, failure.message); }
            l.types_frozen = false;
            return;""", """            for failure in l.failures { life_error(p, l, failure.node, failure.message); }
            dbg_progress(l, "failed");
            l.types_frozen = false;
            return;""")
rep("""    l.discovery = false;
    for root, index in l.roots { l.roots[index].live_contents = root.contents; }""", """    dbg_progress(l, "discovered");
    l.discovery = false;
    for root, index in l.roots { l.roots[index].live_contents = root.contents; }""")
rep("""    l.types_frozen = false;
    if p.diagnostics.len == 0 { life_export_provenance(p, l); life_refresh_named_results(p); }""", """    l.types_frozen = false;
    dbg_progress(l, "validated");
    if p.diagnostics.len == 0 { life_export_provenance(p, l); life_refresh_named_results(p); }""")
rep("""    if function_node < 0 || p.nodes[function_node].right < 0 { return LifeValue {}; }
    var lexical = 0;""", """    if function_node < 0 || p.nodes[function_node].right < 0 { return LifeValue {}; }
    if l.frames.len >= dbg_next_frames { dbg_next_frames += 1000; dbg_progress(l, "frames"); }
    var lexical = 0;""")
rep("""        l.activations += 1; l.frames[target].activation = l.activations;""",
    """        l.activations += 1; l.frames[target].activation = l.activations;
        if l.activations >= dbg_next_activations { dbg_next_activations += 200000; dbg_progress(l, "activations"); }""")
s = s.replace('var dbg_next_frames: i64 = 1000;', 'var dbg_next_frames: i64 = 1000;\nvar dbg_next_activations: i64 = 200000;', 1)
open(f, 'w').write(s)
