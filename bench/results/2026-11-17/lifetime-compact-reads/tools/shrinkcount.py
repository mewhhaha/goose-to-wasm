#!/usr/bin/env python3
"""shrinkcount.py FILE: where a validation shrink check's time goes (on top of valcount.py)."""
import sys
p = sys.argv[1]; t = open(p).read()
def rep(old, new):
    global t
    assert t.count(old) == 1, (old[:60], t.count(old)); t = t.replace(old, new)
rep("var dbg_shrink_ns: i64 = 0;", "var dbg_s: i64[16] = [0; 16];\nvar dbg_shrink_ns: i64 = 0;")
rep("""    life_index_shrink(p, l, node, receiver);
    if !balanced { life_effect(l, LifeEffect { kind: 1, node: node, value: receiver, places: receiver.place }); }
    if l.discovery { return; }""", """    var dbg_t0 = clock_ns();
    life_index_shrink(p, l, node, receiver);
    dbg_s[0] += clock_ns() - dbg_t0; dbg_t0 = clock_ns();
    if !balanced { life_effect(l, LifeEffect { kind: 1, node: node, value: receiver, places: receiver.place }); }
    if l.discovery { return; }
    dbg_s[1] += clock_ns() - dbg_t0; dbg_s[8] += 1; dbg_t0 = clock_ns();""")
rep("""    var index = life_next_live(l, -1);
    while index >= 0 {
        // A cell whose type neither is a reference nor holds one points into""", """    dbg_s[2] += clock_ns() - dbg_t0; dbg_t0 = clock_ns(); var dbg_seen: i64[>..] = [];
    var index = life_next_live(l, -1);
    while index >= 0 {
        // A cell whose type neither is a reference nor holds one points into""")
rep("""        let value = LifeValue { type_id: cell_type, place: life_root_set(l, cell.root), refs: cell.live_refs, contents: l.roots[cell.root].live_contents };
        if life_points_into(p, l, value, receiver.place, receiver.type_id) && life_used_after(p, l, cell) {
            life_error(p, l, node, "array shrink invalidates a reference or holder that is used afterward");
        }
    }""", """        let value = LifeValue { type_id: cell_type, place: life_root_set(l, cell.root), refs: cell.live_refs, contents: l.roots[cell.root].live_contents };
        dbg_s[9] += 1; if life_is_ref(p, cell_type) { dbg_s[10] += 1; if value.refs == 0 { dbg_s[13] += 1; } }
        var dbg_dup = false; var dbg_k = 0;
        if life_is_ref(p, cell_type) { dbg_k = p.types[cell_type].element * 1000003 + value.refs; } else { dbg_k = -(cell_type * 1000003 + cell.root); }
        for old in dbg_seen { if old == dbg_k { dbg_dup = true; } }
        if dbg_dup { dbg_s[12] += 1; } else { dbg_seen.push(dbg_k); }
        let dbg_t1 = clock_ns();
        let dbg_into = life_points_into(p, l, value, receiver.place, receiver.type_id);
        dbg_s[4] += clock_ns() - dbg_t1; if dbg_into { dbg_s[11] += 1; }
        if dbg_into && life_used_after(p, l, cell) {
            life_error(p, l, node, "array shrink invalidates a reference or holder that is used afterward");
        }
    }
    dbg_s[3] += clock_ns() - dbg_t0;""")
rep("""    print("DBG validation ms",""", """    print("DBG shrink arrays", dbg_s[8], " ms: index types", dbg_s[0] / 1000000, " effect", dbg_s[1] / 1000000, " holds", dbg_s[2] / 1000000, " cells", dbg_s[3] / 1000000, " of it points_into", dbg_s[4] / 1000000);
    print("DBG shrink cells asked", dbg_s[9], " refs", dbg_s[10], " with no refs", dbg_s[13], " pointing into", dbg_s[11], " same pointee/refs or same root as an earlier cell of the check", dbg_s[12], " types", p.types.len);
    print("DBG validation ms",""")
open(p, 'w').write(t); print('applied')
