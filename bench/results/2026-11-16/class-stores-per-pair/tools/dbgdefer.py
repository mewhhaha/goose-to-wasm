"""dbgdefer.py DIR (after dbgstore2.py DIR 1 and dbgorigin.py DIR): print where a
store of something class-rooted into shallower storage is first deferred:
in a body (DBGDEFER body) or by a call's mapping of a callee effect that had no
such pair (DBGDEFER map)."""
import sys
f = sys.argv[1] + '/checker_lifetimes.goose'
s = open(f).read()
def rep(old, new, count=1):
    global s
    assert s.count(old) == count, (old[:90], s.count(old))
    s = s.replace(old, new)
s = s.replace('import model;', '''import model;
var dbg_defer_nodes: i64[>..] = [];
fn dbg_defer(p: Program&, l: Lifetimes&, kind: i64, node: i64, source: LifeAlt, dst: LifeAlt, callee: i64, places: i64, contents: i64) {
    if !l.discovery { return; }
    for old in dbg_defer_nodes { if old == node * 2 + kind { return; } }
    dbg_defer_nodes.push(node * 2 + kind);
    var o: u8[>..] = []; if kind == 0 { o.append("DBGDEFER body at="); } else { o.append("DBGDEFER map at="); } dbg_at(p, o, node);
    o.append(" frame="); dbg_d(o, l.frame); o.append(" fn="); if l.frame > 0 { dbg_at(p, o, l.frames[l.frame].function_node); }
    o.append(" island="); dbg_d(o, l.island);
    if callee >= 0 { o.append(" callee="); dbg_d(o, callee); o.append("@"); dbg_at(p, o, l.frames[callee].function_node); }
    o.append(" src="); dbg_root(p, l, o, source); o.append(" dst="); dbg_root(p, l, o, dst);
    if places >= 0 { dbg_alts(p, l, o, "calleeplaces", places); dbg_alts(p, l, o, "calleevalue", contents); }
    o.push(10 as u8); write_stderr(o);
}''', 1)
rep('''            if l.roots[source.root].depth > owner.depth && !(class_read && owner.frame == 0) {''',
    '''            if l.roots[source.root].depth > owner.depth && class_read && owner.frame == 0 { dbg_defer(p, l, 0, node, source, d, -1, -1, -1); }
            if l.roots[source.root].depth > owner.depth && !(class_read && owner.frame == 0) {''')
rep('''                        if owner >= 0 && (l.roots[source.root].class_index >= l.frames[owner].class_base || !source.exact) { continue; }''',
    '''                        if owner >= 0 && (l.roots[source.root].class_index >= l.frames[owner].class_base || !source.exact) {
                            if l.roots[source.root].depth > l.roots[alt.root].depth {
                                var dbg_had = false; var dbg_pi = l.sets[dbg_original.places].first;
                                while dbg_pi >= 0 {
                                    let dbg_pd = l.roots[l.alts[dbg_pi].root].depth; dbg_pi = l.alts[dbg_pi].next;
                                    var dbg_vi = l.sets[dbg_original.value.contents].first;
                                    while dbg_vi >= 0 { if l.roots[l.alts[dbg_vi].root].depth > dbg_pd { dbg_had = true; } dbg_vi = l.alts[dbg_vi].next; }
                                }
                                if !dbg_had { dbg_defer(p, l, 1, call, source, alt, frame, dbg_original.places, dbg_original.value.contents); }
                            }
                            continue;
                        }''')
# Body stores of what one class's storage holds into class storage (kind 2).
rep("""            if l.roots[source.root].depth > owner.depth && class_read && owner.frame == 0 { dbg_defer(p, l, 0, node, source, d, -1, -1, -1); }""",
    """            if l.roots[source.root].depth > owner.depth && class_read && owner.frame == 0 { dbg_defer(p, l, 0, node, source, d, -1, -1, -1); }
            if owner.class_frame >= 0 && l.roots[source.root].class_frame >= 0 && source.root != 0 && (owner.class_parent >= 0 || owner.class_index >= l.frames[owner.class_frame].class_base || !d.exact) &&
               (l.roots[source.root].class_parent >= 0 || l.roots[source.root].class_index >= l.frames[l.roots[source.root].class_frame].class_base || !source.exact) { dbg_defer(p, l, 2, node, source, d, -1, -1, -1); }""")
s = s.replace('if kind == 0 { o.append("DBGDEFER body at="); } else {', 'if kind == 0 { o.append("DBGDEFER body at="); } else if kind == 2 { o.append("DBGDEFER perm at="); } else {')
s = s.replace('node * 2 + kind', 'node * 4 + kind')
rep("""            if l.roots[source.root].depth > owner.depth && class_read && owner.frame == 0 { dbg_defer(p, l, 0, node, source, d, -1, -1, -1); }
            if owner.class_frame >= 0""", """            if l.roots[source.root].depth > owner.depth && class_read && owner.frame == 0 { dbg_defer(p, l, 0, node, source, d, -1, -1, -1); }
            if owner.class_frame >= 0 && l.roots[source.root].class_frame >= 0 && source.root != d.root && source.exact && l.roots[source.root].depth > 0 && l.roots[source.root].class_parent < 0 && l.roots[source.root].class_index < l.frames[l.roots[source.root].class_frame].class_base { dbg_defer(p, l, 3, node, source, d, -1, -1, -1); }
            if owner.class_frame >= 0""")
s = s.replace('if kind == 0 { o.append("DBGDEFER body at="); } else if kind == 2 { o.append("DBGDEFER perm at="); } else {', 'if kind == 0 { o.append("DBGDEFER body at="); } else if kind == 2 { o.append("DBGDEFER perm at="); } else if kind == 3 { o.append("DBGDEFER argarg at="); } else {')
open(f, 'w').write(s)
