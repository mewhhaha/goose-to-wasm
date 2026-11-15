"""rbstats.py SELFHOST_COPY: on top of progress.py, counts read-backs (diagnosis only)."""
import sys
d = sys.argv[1]
f = d + '/checker_lifetimes.goose'
s = open(f).read()

def rep(old, new):
    global s
    assert s.count(old) == 1, (old[:100], s.count(old))
    s = s.replace(old, new)

s = s.replace('var dbg_next_frames: i64 = 1000;', '''var dbg_next_frames: i64 = 1000;
var rb_calls: i64 = 0; var rb_allglobal: i64 = 0; var rb_alts: i64 = 0; var rb_known: i64 = 0; var rb_gscan: i64 = 0; var rb_lscan: i64 = 0;
var rb_gcand: i64 = 0; var rb_lcand: i64 = 0; var rb_out: i64 = 0; var rb_big: i64 = 0; var rb_bigalts: i64 = 0;''', 1)
rep('''    out.push('\\n'); write_stderr(out);
}''', '''    dbg_kv(out, "rb_calls", rb_calls); dbg_kv(out, "rb_allglobal", rb_allglobal); dbg_kv(out, "rb_alts", rb_alts); dbg_kv(out, "rb_known", rb_known);
    dbg_kv(out, "rb_gscan", rb_gscan); dbg_kv(out, "rb_gcand", rb_gcand); dbg_kv(out, "rb_lscan", rb_lscan); dbg_kv(out, "rb_lcand", rb_lcand);
    dbg_kv(out, "rb_out", rb_out); dbg_kv(out, "rb_big", rb_big); dbg_kv(out, "rb_bigalts", rb_bigalts);
    out.push('\\n'); write_stderr(out);
}''')
rep('''    var result = LifeBuild {}; var at = l.sets[places].first;
    while at >= 0 {
        let alt = l.alts[at]; let root = l.roots[alt.root];
        let global = root.symbol >= 0 && (p.symbols[root.symbol].flags & S_GLOBAL) != 0;''', '''    var result = LifeBuild {}; var at = l.sets[places].first;
    rb_calls += 1; rb_alts += l.sets[places].count; if l.sets[places].count >= 16 { rb_big += 1; rb_bigalts += l.sets[places].count; }
    var allglobal = true;
    while at >= 0 {
        let alt = l.alts[at]; let root = l.roots[alt.root];
        let global = root.symbol >= 0 && (p.symbols[root.symbol].flags & S_GLOBAL) != 0;
        if !global { allglobal = false; }''')
rep('''        if !known { var candidates = LifeBuild {}; life_candidates(p, l, t.element, root.depth, global, candidates); life_build_drop(l, candidates); }''',
    '''        if !known { var candidates = LifeBuild {}; life_candidates(p, l, t.element, root.depth, global, candidates); life_build_drop(l, candidates);
            if global { rb_gscan += 1; rb_gcand += l.scratch.len - start; } else { rb_lscan += 1; rb_lcand += l.scratch.len - start; } } else { rb_known += 1; }''')
rep('''        l.scratch.resize(start);
        at = alt.next;
    }
    return life_build_end(l, result);''', '''        l.scratch.resize(start);
        at = alt.next;
    }
    if allglobal { rb_allglobal += 1; }
    let rbset = life_build_end(l, result); rb_out += l.sets[rbset].count;
    return rbset;''')
open(f, 'w').write(s)
