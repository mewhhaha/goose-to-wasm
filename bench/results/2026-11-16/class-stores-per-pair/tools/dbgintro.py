"""dbgintro.py DIR (after dbgstore2.py DIR 1 and dbgwatch.py DIR): with DBG_WATCH=-9,T in
the environment, print where a store of an exact storage-class alternative of
target type T into global storage first appears: in a body, or at a call whose
callee's effect was not already such a store (DBGINTRO lines)."""
import sys
f = sys.argv[1] + '/checker_lifetimes.goose'
s = open(f).read()
def rep(old, new, count=1):
    global s
    assert s.count(old) == count, (old[:70], s.count(old))
    s = s.replace(old, new)
s = s.replace('import model;', '''import model;
fn dbg_intro_alt(l: Lifetimes&, x: LifeAlt) -> bool {
    if dbg_watch_place == -3 { dbg_watch_load(); }
    if dbg_watch_place != -9 || !x.exact || x.root == 0 || x.target_type as i64 != dbg_watch_value { return false; }
    let r = l.roots[x.root];
    return r.class_frame >= 0 && r.depth > 0 && (r.class_parent >= 0 || r.class_index >= l.frames[r.class_frame].class_base);
}
fn dbg_intro_set(l: Lifetimes&, set: i64) -> bool {
    var at = l.sets[set].first; while at >= 0 { if dbg_intro_alt(l, l.alts[at]) { return true; } at = l.alts[at].next; }
    return false;
}
fn dbg_global_root(l: Lifetimes&, root: i64) -> bool { return root == l.globals_root || l.roots[root].class_frame < 0 && l.roots[root].frame == 0 && l.roots[root].depth == 0 && l.roots[root].symbol >= 0; }''', 1)
rep("""        if l.discovery && dbg_watched(l, d.root as i64, life_stored_roots(p, l, value)) && dbg_watch_once(node * 2) {""",
"""        if l.discovery && dbg_global_root(l, d.root as i64) && dbg_intro_set(l, life_stored_roots(p, l, value)) && dbg_watch_once(node * 2) {
            var o: u8[>..] = []; o.append("DBGINTRO body at="); dbg_at(p, o, node); o.append(" frame="); dbg_d(o, l.frame); o.append(" fn="); if l.frame > 0 { dbg_at(p, o, l.frames[l.frame].function_node); }
            o.append(" place="); dbg_root(p, l, o, d); dbg_alts(p, l, o, "stored", life_stored_roots(p, l, value)); o.push(10 as u8); write_stderr(o);
        }
        if l.discovery && dbg_watched(l, d.root as i64, life_stored_roots(p, l, value)) && dbg_watch_once(node * 2) {""")
rep("""                if l.discovery && dbg_watched(l, alt.root as i64, landing) && dbg_watch_once(call * 2 + 1) {""",
"""                if l.discovery && dbg_global_root(l, alt.root as i64) && dbg_intro_set(l, landing) {
                    var dbg_gp = false; var dbg_pi = l.sets[dbg_original.places].first;
                    while dbg_pi >= 0 { if dbg_global_root(l, l.alts[dbg_pi].root as i64) { dbg_gp = true; } dbg_pi = l.alts[dbg_pi].next; }
                    if !(dbg_gp && dbg_intro_set(l, dbg_original.value.contents)) && dbg_watch_once(call * 2 + 1) {
                        var o: u8[>..] = []; o.append("DBGINTRO replay at="); dbg_at(p, o, call); o.append(" frame="); dbg_d(o, l.frame); o.append(" fn="); if l.frame > 0 { dbg_at(p, o, l.frames[l.frame].function_node); }
                        o.append(" callee="); dbg_d(o, frame); o.append("@"); dbg_at(p, o, l.frames[frame].function_node); o.append(" calleetype="); dbg_d(o, dbg_original.value.type_id);
                        o.append(" place="); dbg_root(p, l, o, alt); dbg_alts(p, l, o, "calleeplaces", dbg_original.places); dbg_alts(p, l, o, "calleevalue", dbg_original.value.contents); dbg_alts(p, l, o, "mapped", landing);
                        o.push(10 as u8); write_stderr(o);
                    }
                }
                if l.discovery && dbg_watched(l, alt.root as i64, landing) && dbg_watch_once(call * 2 + 1) {""")
open(f, 'w').write(s)
