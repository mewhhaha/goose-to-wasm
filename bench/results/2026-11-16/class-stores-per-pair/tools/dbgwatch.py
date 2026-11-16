"""dbgwatch.py DIR (after dbgstore2.py DIR 1): with DBG_WATCH=PLACE,VALUE in the
environment (root numbers as DBGSTORE prints them; PLACE -1 for any), print
every store that puts an alternative at root VALUE into root PLACE: a body
store with its node, or a call's replay with the callee, its effect's place and
the callee alternatives that became VALUE (DBGWATCH lines)."""
import sys
f = sys.argv[1] + '/checker_lifetimes.goose'
s = open(f).read()
def rep(old, new, count=1):
    global s
    assert s.count(old) == count, (old[:70], s.count(old))
    s = s.replace(old, new)
s = s.replace('import model;', '''import model;
var dbg_watch_place: i64 = -3; var dbg_watch_value: i64 = -3; var dbg_watch_seen: i64[>..] = [];
fn dbg_watch_load() {
    dbg_watch_place = -2; dbg_watch_value = -2;
    var text: u8[>..] = []; if !env("DBG_WATCH", text) { return; }
    var n: i64 = 0; var neg = false; var first = true;
    for ch in text {
        if ch == ',' { if neg { n = 0 - n; } dbg_watch_place = n; n = 0; neg = false; first = false; }
        else if ch == '-' { neg = true; }
        else { n = n * 10 + ((ch - '0') as i64); }
    }
    if neg { n = 0 - n; } if !first { dbg_watch_value = n; }
}
fn dbg_watched(l: Lifetimes&, root: i64, set: i64) -> bool {
    if dbg_watch_place == -3 { dbg_watch_load(); }
    if dbg_watch_value < 0 || dbg_watch_place != -1 && dbg_watch_place != root || set == 0 { return false; }
    var at = l.sets[set].first;
    while at >= 0 { if l.alts[at].root as i64 == dbg_watch_value { return true; } at = l.alts[at].next; }
    return false;
}
fn dbg_watch_once(key: i64) -> bool { for o in dbg_watch_seen { if o == key { return false; } } dbg_watch_seen.push(key); return true; }''', 1)
# body
rep("""        var reached: i64 = -1; if d.exact && !d.byteview { reached = d.target_type as i64; if reached < 0 { reached = path; } }""",
"""        var reached: i64 = -1; if d.exact && !d.byteview { reached = d.target_type as i64; if reached < 0 { reached = path; } }
        if l.discovery && dbg_watched(l, d.root as i64, life_stored_roots(p, l, value)) && dbg_watch_once(node * 2) {
            var o: u8[>..] = []; o.append("DBGWATCH body at="); dbg_at(p, o, node); o.append(" frame="); dbg_d(o, l.frame); o.append(" fn="); if l.frame > 0 { dbg_at(p, o, l.frames[l.frame].function_node); }
            o.append(" island="); dbg_d(o, l.island); o.append(" reached="); dbg_d(o, reached); o.append(" place="); dbg_root(p, l, o, d); dbg_alts(p, l, o, "stored", life_stored_roots(p, l, value)); o.push(10 as u8); write_stderr(o);
        }""")
# replay
rep("""                if !refused { life_add_contents(l, alt.root, landing, false, reached); }""",
"""                if l.discovery && dbg_watched(l, alt.root as i64, landing) && dbg_watch_once(call * 2 + 1) {
                    var o: u8[>..] = []; o.append("DBGWATCH replay at="); dbg_at(p, o, call); o.append(" frame="); dbg_d(o, l.frame); o.append(" fn="); if l.frame > 0 { dbg_at(p, o, l.frames[l.frame].function_node); }
                    o.append(" island="); dbg_d(o, l.island); o.append(" callee="); dbg_d(o, frame); o.append("@"); dbg_at(p, o, l.frames[frame].function_node);
                    o.append(" calleetype="); dbg_d(o, dbg_original.value.type_id); o.append(" field="); dbg_d(o, dbg_original.field); o.append(" place="); dbg_root(p, l, o, alt);
                    dbg_alts(p, l, o, "calleeplaces", dbg_original.places);
                    var dbg_x = l.sets[dbg_original.value.contents].first;
                    while dbg_x >= 0 {
                        var dbg_a = l.alts[dbg_x]; dbg_x = dbg_a.next; dbg_a.next = -1;
                        var dbg_m = life_alt_set(l, dbg_a); if m.count > 0 { dbg_m = life_map_set(p, l, dbg_m, m); }
                        if life_find(l, dbg_m, dbg_watch_value) >= 0 { o.append(" via:"); dbg_root(p, l, o, dbg_a); }
                    }
                    o.push(10 as u8); write_stderr(o);
                }
                if !refused { life_add_contents(l, alt.root, landing, false, reached); }""")
open(f, 'w').write(s)
