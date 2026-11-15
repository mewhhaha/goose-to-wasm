"""dbgcycle.py DIR: report the chain when class queries nest 40 deep."""
import sys
f = sys.argv[1] + '/checker_lifetimes.goose'
s = open(f).read()
def rep(old, new, count=1):
    global s
    assert s.count(old) == count, (old[:90], s.count(old))
    s = s.replace(old, new)
if 'fn dbg_num(' not in s:
    s = s.replace('import model;', '''import model;
import os;
fn dbg_num(out: u8[>..]&, value: i64) {
    var n = value; if n < 0 { out.push('-'); n = -n; } var d: u8[>..] = [];
    loop { d.push((n % 10) as u8 + '0'); n /= 10; if n == 0 { break; } }
    var k = d.len; while k > 0 { k -= 1; out.push(d[k]); }
}''', 1)
s = s.replace('import model;', 'import model;\nvar dbg_depth: i64 = 0;', 1)
rep('''    let known = life_assumed(l, frame, query, index, subject, flag);
    if known >= 0 { return known == 1; }
    let answer = life_class_answer(p, l, frame, l.frames[frame].map_base, query, index, subject, flag);''', '''    let known = life_assumed(l, frame, query, index, subject, flag);
    if known >= 0 { return known == 1; }
    dbg_depth += 1;
    if dbg_depth > 40 && dbg_depth < 48 {
        var o: u8[>..] = []; o.append("DBGCYCLE depth="); dbg_num(o, dbg_depth); o.append(" root="); dbg_num(o, root); o.append(" frame="); dbg_num(o, frame); o.append(" index="); dbg_num(o, index); o.append(" base="); dbg_num(o, l.frames[frame].class_base);
        o.append(" query="); dbg_num(o, query); o.append(" subject="); dbg_num(o, subject); o.append(" mapbase="); dbg_num(o, l.frames[frame].map_base); o.append(" island="); dbg_num(o, l.island); o.append(" lframe="); dbg_num(o, l.frame);
        o.append(" set={"); var di = l.sets[life_class_set(l, l.frames[frame].class_base, l.frames[frame].map_base, index)].first;
        while di >= 0 { let a = l.alts[di]; o.append(" r"); dbg_num(o, a.root as i64); if !a.exact { o.append("~"); } if l.roots[a.root].class_frame >= 0 { o.append("/C"); dbg_num(o, l.roots[a.root].class_frame); o.append("."); dbg_num(o, l.roots[a.root].class_index); } di = a.next; }
        o.append(" } fnline="); dbg_num(o, p.tokens[p.nodes[l.frames[frame].function_node].token].line); o.push(10 as u8); write_stderr(o);
    }
    if dbg_depth > 60 { var dbg_zero: i64[>..] = []; let dbg_boom = dbg_zero[5]; }
    let answer = life_class_answer(p, l, frame, l.frames[frame].map_base, query, index, subject, flag);
    dbg_depth -= 1;''')
open(f, 'w').write(s)
