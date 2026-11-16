"""dbgsite.py DIR (after progress.py and dbgstore2.py DIR 1, on a source with
runs/reached-type-variant.patch applied): tag each store effect with the code
path (1 a store statement, 2 a value built in a destination, 3 a call's result
put in a place, 0 anything else) and the node that first made it, through
every replay, and print both and the reached type with each refused store."""
import sys
f = sys.argv[1] + '/checker_lifetimes.goose'
s = open(f).read()
def rep(old, new, count=1):
    global s
    assert s.count(old) == count, (old[:80], s.count(old))
    s = s.replace(old, new)
s = s.replace('import model;', 'import model;\nvar dbg_origin: i64 = -1; var dbg_node: i64 = -1; var dbg_site: i64 = 0; var dbg_osite: i64 = -1; var dbg_reached: i64 = -2; var dbg_eff_site: i64 = -1;', 1)
rep("epoch: i64 = 0, walked: i8 = 0 }", "epoch: i64 = 0, walked: i8 = 0, origin: i64 = -1, osite: i64 = -1 }")
rep('''recursive fn life_eval(p: Program&, l: Lifetimes&, node: i64, destination: i64 = 0, selected_result: i64 = -1) -> LifeValue {''', '''recursive fn life_eval(p: Program&, l: Lifetimes&, node: i64, destination: i64 = 0, selected_result: i64 = -1) -> LifeValue {
    dbg_node = node;''')
rep("""        life_effect(l, LifeEffect { kind: 4, node: -1, value: LifeValue { type_id: type_id, contents: sources }, places: life_root_set(l, root) });""", """        var dbg_from = dbg_origin; if dbg_from < 0 { dbg_from = dbg_node; } var dbg_s = dbg_osite; if dbg_s < 0 { dbg_s = dbg_site; }
        life_effect(l, LifeEffect { kind: 4, node: -1, value: LifeValue { type_id: type_id, contents: sources }, places: life_root_set(l, root), origin: dbg_from, osite: dbg_s });""")
rep("""        life_add_contents(l, d.root, life_stored_roots(p, l, value), reached);""", """        dbg_site = 1; life_add_contents(l, d.root, life_stored_roots(p, l, value), reached); dbg_site = 0;""")
rep("""    while at >= 0 { let alt = l.alts[at]; life_add_contents(l, alt.root, out.contents, life_dest_reached(l, destination)); at = alt.next; }""", """    dbg_site = 2; while at >= 0 { let alt = l.alts[at]; life_add_contents(l, alt.root, out.contents, life_dest_reached(l, destination)); at = alt.next; } dbg_site = 0;""")
rep("""        while at >= 0 { let alt = l.alts[at]; life_add_contents(l, alt.root, contents, life_dest_reached(l, place)); at = alt.next; }""", """        dbg_site = 3; while at >= 0 { let alt = l.alts[at]; life_add_contents(l, alt.root, contents, life_dest_reached(l, place)); at = alt.next; } dbg_site = 0;""")
rep("""                if !refused { life_add_contents(l, alt.root, effect.value.contents, effect.value.type_id); }""", """                if !refused { dbg_origin = effect.origin; dbg_osite = effect.osite; life_add_contents(l, alt.root, effect.value.contents, effect.value.type_id); dbg_origin = -1; dbg_osite = -1; }""")
rep("dbg_store(p, l, 2, call, source, alt, frame, effect.node,", "dbg_reached = effect.value.type_id; dbg_eff_site = effect.osite; dbg_store(p, l, 2, call, source, alt, frame, effect.origin,")
rep('''    o.append(" island="); dbg_d(o, l.island);''', '''    o.append(" island="); dbg_d(o, l.island); o.append(" reached="); dbg_d(o, dbg_reached); o.append(" osite="); dbg_d(o, dbg_eff_site);''')
open(f, 'w').write(s)
