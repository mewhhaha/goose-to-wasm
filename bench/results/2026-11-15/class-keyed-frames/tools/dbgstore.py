"""dbgstore.py DIR: describe the first replayed stores that fail the depth check."""
import sys
f = sys.argv[1] + '/checker_lifetimes.goose'
s = open(f).read()
def rep(old, new, count=1):
    global s
    assert s.count(old) == count, (old[:90], s.count(old))
    s = s.replace(old, new)
s = s.replace('import model;', '''import model;
import os;
var dbg_stores: i64 = 0;
fn dbg_d(out: u8[>..]&, value: i64) {
    var n = value; if n < 0 { out.push('-'); n = -n; } var d: u8[>..] = [];
    loop { d.push((n % 10) as u8 + '0'); n /= 10; if n == 0 { break; } }
    var k = d.len; while k > 0 { k -= 1; out.push(d[k]); }
}
fn dbg_root(p: Program&, l: Lifetimes&, o: u8[>..]&, a: LifeAlt) {
    let r = l.roots[a.root]; o.append("r"); dbg_d(o, a.root as i64); if !a.exact { o.append("~"); }
    o.append("(d"); dbg_d(o, r.depth); o.append(" f"); dbg_d(o, r.frame);
    if r.class_frame >= 0 { o.append(" C"); dbg_d(o, r.class_frame); o.append("."); dbg_d(o, r.class_index); o.append("/"); dbg_d(o, l.frames[r.class_frame].class_base); }
    if r.temporary { o.append(" temp@"); if r.node >= 0 && p.nodes[r.node].token >= 0 { dbg_d(o, p.tokens[p.nodes[r.node].token].line); } }
    if r.symbol >= 0 && p.symbols[r.symbol].node >= 0 && p.nodes[p.symbols[r.symbol].node].token >= 0 { o.append(" sym@"); dbg_d(o, p.tokens[p.nodes[p.symbols[r.symbol].node].token].line); }
    if a.bound != 0 { o.append(" b"); dbg_d(o, a.bound as i64); } if a.from >= 0 { o.append(" from"); dbg_d(o, a.from as i64); }
    o.append(")");
}
fn dbg_alts(p: Program&, l: Lifetimes&, o: u8[>..]&, name: const u8[:], set: i64) {
    o.append(" "); o.append(name); o.append("={"); var at = l.sets[set].first; var n = 0;
    while at >= 0 && n < 6 { o.append(" "); dbg_root(p, l, o, l.alts[at]); at = l.alts[at].next; n += 1; }
    if at >= 0 { o.append(" ..."); dbg_d(o, l.sets[set].count); } o.append(" }");
}''', 1)
rep('''        var effect = l.effects[at]; let next = effect.next; var mapped = false;''', '''        var effect = l.effects[at]; let next = effect.next; var mapped = false; let dbg_original = effect;''')
rep('''                        if l.roots[source.root].depth > l.roots[alt.root].depth { life_scope_error(p, l, call, "stored reference does not outlive the storage that receives it"); }''',
    '''                        if l.roots[source.root].depth > l.roots[alt.root].depth {
                            if dbg_stores < 14 && call >= 0 {
                                dbg_stores += 1; var o: u8[>..] = []; o.append("DBGSTORE call@"); dbg_d(o, p.tokens[p.nodes[call].token].line); o.append(" callee@"); dbg_d(o, p.tokens[p.nodes[l.frames[frame].function_node].token].line);
                                o.append(" island="); dbg_d(o, l.island); o.append(" src="); dbg_root(p, l, o, source); o.append(" dst="); dbg_root(p, l, o, alt);
                                dbg_alts(p, l, o, "calleeplaces", dbg_original.places); dbg_alts(p, l, o, "calleevalue", dbg_original.value.contents); o.push(10 as u8); write_stderr(o);
                            }
                            life_scope_error(p, l, call, "stored reference does not outlive the storage that receives it");
                        }''')

rep("""            if l.roots[source.root].depth > owner.depth && !(class_read && owner.frame == 0) {
                life_scope_error(p, l, node, "stored reference does not outlive the storage that receives it");
            }""", """            if l.roots[source.root].depth > owner.depth && !(class_read && owner.frame == 0) {
                dbg_body += 1;
                if dbg_body % 97 == 1 && dbg_bodies < 12 { dbg_bodies += 1; var o: u8[>..] = []; o.append("DBGBODY line@"); dbg_d(o, p.tokens[p.nodes[node].token].line); o.append(" fn@"); if l.frame > 0 { dbg_d(o, p.tokens[p.nodes[l.frames[l.frame].function_node].token].line); } o.append(" frame="); dbg_d(o, l.frame); o.append(" island="); dbg_d(o, l.island); o.append(" src="); dbg_root(p, l, o, source); o.append(" dst="); dbg_root(p, l, o, d); if binding { o.append(" binding"); } o.push(10 as u8); write_stderr(o); }
                life_scope_error(p, l, node, "stored reference does not outlive the storage that receives it");
            }""")
rep("""            if !d.exact && owner.class_frame >= 0 && source.root != 0 && l.roots[source.root].depth > 0 && !(source.root == d.root && !source.exact) {
                life_scope_error(p, l, node, "stored reference does not outlive the storage that receives it");""", """            if !d.exact && owner.class_frame >= 0 && source.root != 0 && l.roots[source.root].depth > 0 && !(source.root == d.root && !source.exact) {
                dbg_strict += 1;
                if dbg_strict % 97 == 1 && dbg_stricts < 8 { dbg_stricts += 1; var o: u8[>..] = []; o.append("DBGSTRICT line@"); dbg_d(o, p.tokens[p.nodes[node].token].line); o.append(" island="); dbg_d(o, l.island); o.append(" src="); dbg_root(p, l, o, source); o.append(" dst="); dbg_root(p, l, o, d); o.push(10 as u8); write_stderr(o); }
                life_scope_error(p, l, node, "stored reference does not outlive the storage that receives it");""")
s = s.replace('var dbg_stores: i64 = 0;', 'var dbg_stores: i64 = 0; var dbg_body: i64 = 0; var dbg_bodies: i64 = 0; var dbg_strict: i64 = 0; var dbg_stricts: i64 = 0; var dbg_replays: i64 = 0;', 1)
s = s.replace('if dbg_stores < 14 && call >= 0 {', 'dbg_replays += 1; if dbg_replays % 197 == 1 && dbg_stores < 14 && call >= 0 {', 1)
rep("""    l.types_frozen = false;
    if p.diagnostics.len == 0 { life_export_provenance(p, l); life_refresh_named_results(p); }""", """    l.types_frozen = false;
    if p.diagnostics.len == 0 { life_export_provenance(p, l); life_refresh_named_results(p); }""")
rep("""            for failure in l.failures { life_error(p, l, failure.node, failure.message); }""", """            var dbg_o: u8[>..] = []; dbg_o.append("DBGCOUNT body="); dbg_d(dbg_o, dbg_body); dbg_o.append(" strict="); dbg_d(dbg_o, dbg_strict); dbg_o.append(" replay="); dbg_d(dbg_o, dbg_replays); dbg_o.push(10 as u8); write_stderr(dbg_o);
            for failure in l.failures { life_error(p, l, failure.node, failure.message); }""")
open(f, 'w').write(s)
