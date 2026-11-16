"""dbgstore2.py DIR [every]: count store errors by the check that first reports
each node (body depth, body strict, replay at a call), and describe a sample."""
import sys
f = sys.argv[1] + '/checker_lifetimes.goose'
every = sys.argv[2] if len(sys.argv) > 2 else '25'
s = open(f).read()
def rep(old, new, count=1):
    global s
    assert s.count(old) == count, (old[:90], s.count(old))
    s = s.replace(old, new)
if 'import os;' not in s: s = s.replace('import model;', 'import model;\nimport os;', 1)
s = s.replace('import model;', '''import model;
var dbg_kinds: i64[>..] = []; var dbg_shown: i64 = 0;
fn dbg_d(out: u8[>..]&, value: i64) {
    var n = value; if n < 0 { out.push('-'); n = -n; } var d: u8[>..] = [];
    loop { d.push((n % 10) as u8 + '0'); n /= 10; if n == 0 { break; } }
    var k = d.len; while k > 0 { k -= 1; out.push(d[k]); }
}
fn dbg_at(p: Program&, o: u8[>..]&, node: i64) {
    if node < 0 || p.nodes[node].token < 0 { o.append("?"); return; }
    let t = p.tokens[p.nodes[node].token]; o.append("s"); dbg_d(o, t.source); o.append(":"); dbg_d(o, t.line); o.append(":"); dbg_d(o, t.column);
}
fn dbg_root(p: Program&, l: Lifetimes&, o: u8[>..]&, a: LifeAlt) {
    let r = l.roots[a.root]; o.append("r"); dbg_d(o, a.root as i64); if !a.exact { o.append("~"); }
    o.append("(d"); dbg_d(o, r.depth); o.append(" f"); dbg_d(o, r.frame);
    if r.class_frame >= 0 { o.append(" C"); dbg_d(o, r.class_frame); o.append("."); dbg_d(o, r.class_index); o.append("/"); dbg_d(o, l.frames[r.class_frame].class_base); o.append(" lvl"); dbg_d(o, r.class_level); if r.class_parent >= 0 { o.append(" parent"); dbg_d(o, r.class_parent); o.append(" ty"); dbg_d(o, r.class_type); } }
    if r.temporary { o.append(" temp@"); dbg_at(p, o, r.node); }
    if r.symbol >= 0 { o.append(" sym@"); dbg_at(p, o, p.symbols[r.symbol].node); }
    if a.target_type >= 0 { o.append(" tt"); dbg_d(o, a.target_type as i64); }
    if a.bound != 0 { o.append(" b"); dbg_d(o, a.bound as i64); } if a.from >= 0 { o.append(" from"); dbg_d(o, a.from as i64); }
    o.append(")");
}
fn dbg_alts(p: Program&, l: Lifetimes&, o: u8[>..]&, name: const u8[:], set: i64) {
    o.append(" "); o.append(name); o.append("={"); var at = l.sets[set].first; var n = 0;
    while at >= 0 && n < 8 { o.append(" "); dbg_root(p, l, o, l.alts[at]); at = l.alts[at].next; n += 1; }
    if at >= 0 { o.append(" ..."); dbg_d(o, l.sets[set].count); } o.append(" }");
}
fn dbg_store(p: Program&, l: Lifetimes&, kind: i64, node: i64, source: LifeAlt, dst: LifeAlt, callee: i64, effect_node: i64, places: i64, contents: i64) {
    if !l.discovery { return; }
    for failure in l.failures { if failure.node == node { return; } }
    while dbg_kinds.len < 4 { dbg_kinds.push(0); }
    dbg_kinds[kind] += 1;
    if (dbg_kinds[0] + dbg_kinds[1] + dbg_kinds[2]) % EVERY != 1 { return; }
    var o: u8[>..] = []; o.append("DBGSTORE kind="); dbg_d(o, kind); o.append(" at="); dbg_at(p, o, node);
    o.append(" frame="); dbg_d(o, l.frame); o.append(" fn="); if l.frame > 0 { dbg_at(p, o, l.frames[l.frame].function_node); }
    o.append(" island="); dbg_d(o, l.island);
    if callee >= 0 { o.append(" callee="); dbg_d(o, callee); o.append("@"); dbg_at(p, o, l.frames[callee].function_node); o.append(" store@"); dbg_at(p, o, effect_node); o.append(" calleeclasses="); dbg_d(o, l.frames[callee].classes); }
    o.append(" src="); dbg_root(p, l, o, source); o.append(" dst="); dbg_root(p, l, o, dst);
    if places >= 0 { dbg_alts(p, l, o, "calleeplaces", places); dbg_alts(p, l, o, "calleevalue", contents); }
    o.push(10 as u8); write_stderr(o);
}'''.replace('EVERY', every), 1)
rep('''        var effect = l.effects[at]; let next = effect.next; var mapped = false;''', '''        var effect = l.effects[at]; let next = effect.next; var mapped = false; let dbg_original = effect;''')
rep('''                        if l.roots[source.root].depth > l.roots[alt.root].depth { life_scope_error(p, l, call, "stored reference does not outlive the storage that receives it"); refused = true; }''',
    '''                        if l.roots[source.root].depth > l.roots[alt.root].depth { dbg_store(p, l, 2, call, source, alt, frame, effect.node, dbg_original.places, dbg_original.value.contents); life_scope_error(p, l, call, "stored reference does not outlive the storage that receives it"); refused = true; }''')
rep("""            if l.roots[source.root].depth > owner.depth && !(class_read && owner.frame == 0) {
                life_scope_error(p, l, node, "stored reference does not outlive the storage that receives it");""", """            if l.roots[source.root].depth > owner.depth && !(class_read && owner.frame == 0) {
                dbg_store(p, l, 0, node, source, d, -1, -1, -1, -1);
                life_scope_error(p, l, node, "stored reference does not outlive the storage that receives it");""")
rep("""            if !d.exact && owner.class_frame >= 0 && source.root != 0 && l.roots[source.root].depth > 0 && !(source.root == d.root && !source.exact) {
                life_scope_error(p, l, node, "stored reference does not outlive the storage that receives it");""", """            if !d.exact && owner.class_frame >= 0 && source.root != 0 && l.roots[source.root].depth > 0 && !(source.root == d.root && !source.exact) {
                dbg_store(p, l, 1, node, source, d, -1, -1, -1, -1);
                life_scope_error(p, l, node, "stored reference does not outlive the storage that receives it");""")
rep("""            for failure in l.failures { life_error(p, l, failure.node, failure.message); }""", """            var dbg_o: u8[>..] = []; while dbg_kinds.len < 4 { dbg_kinds.push(0); } dbg_o.append("DBGCOUNT body="); dbg_d(dbg_o, dbg_kinds[0]); dbg_o.append(" strict="); dbg_d(dbg_o, dbg_kinds[1]); dbg_o.append(" replay="); dbg_d(dbg_o, dbg_kinds[2]); dbg_o.push(10 as u8); write_stderr(dbg_o);
            for src, si in p.sources { var so: u8[>..] = []; so.append("DBGSRC s"); dbg_d(so, si); so.append(" "); so.append(p.text[src.path_start..src.path_start + src.path_len]); so.push(10 as u8); write_stderr(so); }
            for failure in l.failures { life_error(p, l, failure.node, failure.message); }""")
open(f, 'w').write(s)
