"""dbgshrink.py DIR: make the shrink conflict of a live cell print what conflicts."""
import sys
f = sys.argv[1] + '/checker_lifetimes.goose'
s = open(f).read()
BASE = 'class_frame: i64' not in s
def rep(old, new):
    global s
    assert s.count(old) == 1, (old[:90], s.count(old))
    s = s.replace(old, new)
s = s.replace('import model;', '''import model;
import os;
fn dbg_n(out: u8[>..]&, value: i64) {
    var n = value; if n < 0 { out.push('-'); n = -n; } var d: u8[>..] = [];
    loop { d.push((n % 10) as u8 + '0'); n /= 10; if n == 0 { break; } }
    var k = d.len; while k > 0 { k -= 1; out.push(d[k]); }
}
fn dbg_set(l: Lifetimes&, out: u8[>..]&, name: const u8[:], set: i64) {
    out.append(" "); out.append(name); out.append("={");
    var at = l.sets[set].first;
    while at >= 0 {
        let a = l.alts[at]; out.append(" r"); dbg_n(out, a.root as i64); if !a.exact { out.append("~"); }
        out.append("/f"); dbg_n(out, l.roots[a.root].frame); out.append("/d"); dbg_n(out, l.roots[a.root].depth);
        if l.roots[a.root].class_frame >= 0 { out.append("/C"); dbg_n(out, l.roots[a.root].class_frame); out.append("."); dbg_n(out, l.roots[a.root].class_index); }
        if a.component >= 0 { out.append("/c"); dbg_n(out, a.component as i64); }
        at = a.next;
    }
    out.append(" }");
}
''', 1)
if BASE:
    s = s.replace('        if l.roots[a.root].class_frame >= 0 { out.append("/C"); dbg_n(out, l.roots[a.root].class_frame); out.append("."); dbg_n(out, l.roots[a.root].class_index); }\n', '')
    s = s.replace(' dbg.append(" island="); dbg_n(dbg, l.island);', '')
rep('''        if life_points_into(p, l, value, receiver.place, receiver.type_id) && life_used_after(p, l, cell) {''',
    '''        if life_points_into(p, l, value, receiver.place, receiver.type_id) && life_used_after(p, l, cell) {
            var dbg: u8[>..] = []; dbg.append("DBG shrink cell symbol="); dbg_n(dbg, cell.symbol); dbg.append(" line="); dbg_n(dbg, p.tokens[p.nodes[node].token].line);
            if p.symbols[cell.symbol].node >= 0 { dbg.append(" declline="); dbg_n(dbg, p.tokens[p.nodes[p.symbols[cell.symbol].node].token].line); dbg.append(" declcol="); dbg_n(dbg, p.tokens[p.nodes[p.symbols[cell.symbol].node].token].column); } dbg.append(" cellframe="); dbg_n(dbg, cell.frame); dbg.append(" frame="); dbg_n(dbg, l.frame); dbg.append(" island="); dbg_n(dbg, l.island);
            dbg_set(l, dbg, "place", receiver.place); dbg_set(l, dbg, "refs", value.refs); dbg_set(l, dbg, "contents", value.contents); dbg.push('\\n'); write_stderr(dbg);''')
if BASE:
    s = s.replace(' dbg.append(" island="); dbg_n(dbg, l.island);', '')
open(f, 'w').write(s)
