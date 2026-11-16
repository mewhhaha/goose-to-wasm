"""dbgwhy.py DIR (after dbgstore2.py DIR 1): tally where a store into a class root is recorded without a reached type (DBGWHY site=1 body, 2 replay; extra=1 place not exact, 2 byte view)."""
import sys
f = sys.argv[1] + '/checker_lifetimes.goose'
s = open(f).read()
def rep(old, new, count=1):
    global s
    assert s.count(old) == count, (old[:70], s.count(old))
    s = s.replace(old, new)
s = s.replace('import model;', '''import model;
var dbg_why: i64 = 0; var dbg_why_node: i64 = -1; var dbg_why_seen: i64[>..] = []; var dbg_why_extra: i64 = 0;''', 1)
rep("""    if sources != 0 { life_effect(l, LifeEffect { kind: 4, node: -1, value: LifeValue { type_id: as_type, contents: sources }, places: life_root_set(l, root) }); }""",
"""    if sources != 0 && as_type < 0 && l.discovery && l.roots[root].class_frame >= 0 && l.roots[root].class_parent < 0 {
        var dbg_old = false; let dbg_key = dbg_why_node * 16 + dbg_why * 4 + dbg_why_extra; for o in dbg_why_seen { if o == dbg_key { dbg_old = true; } }
        if !dbg_old { dbg_why_seen.push(dbg_key);
            var o: u8[>..] = []; o.append("DBGWHY site="); dbg_d(o, dbg_why); o.append(" extra="); dbg_d(o, dbg_why_extra); o.append(" at="); dbg_at(p_dbg, o, dbg_why_node); o.append(" frame="); dbg_d(o, l.frame); o.append(" arg="); if l.roots[root].class_index < l.frames[l.roots[root].class_frame].class_base { o.append("1"); } else { o.append("0"); } o.push(10 as u8); write_stderr(o); }
    }
    if sources != 0 { life_effect(l, LifeEffect { kind: 4, node: -1, value: LifeValue { type_id: as_type, contents: sources }, places: life_root_set(l, root) }); }""")
rep("""        life_add_contents(l, d.root, life_stored_roots(p, l, value), d.exact, reached);""",
"""        dbg_why = 1; dbg_why_node = node; dbg_why_extra = 0; if !d.exact { dbg_why_extra = 1; } else if d.byteview { dbg_why_extra = 2; }
        life_add_contents(l, d.root, life_stored_roots(p, l, value), d.exact, reached);
        dbg_why = 0; dbg_why_node = -1;""")
rep("""                if !refused { life_add_contents(l, alt.root, landing, false, reached); }""",
"""                dbg_why = 2; dbg_why_node = call; dbg_why_extra = 0; if !alt.exact { dbg_why_extra = 1; } else if alt.byteview { dbg_why_extra = 2; }
                if !refused { life_add_contents(l, alt.root, landing, false, reached); }
                dbg_why = 0; dbg_why_node = -1;""")
# life_add_contents has no Program: print positions through a global copy of the token table is not at hand; print the node number instead
s = s.replace(' o.append(" at="); dbg_at(p_dbg, o, dbg_why_node);', ' o.append(" node="); dbg_d(o, dbg_why_node);')
open(f, 'w').write(s)
