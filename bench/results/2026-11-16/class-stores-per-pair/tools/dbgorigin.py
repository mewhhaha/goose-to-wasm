"""dbgorigin.py DIR (after dbgstore2.py DIR 1): carry with each store effect the
node whose evaluation first made it, through every replay, and print it with
each refused store (DBGORIGIN lines)."""
import sys
f = sys.argv[1] + '/checker_lifetimes.goose'
s = open(f).read()
def rep(old, new, count=1):
    global s
    assert s.count(old) == count, (old[:90], s.count(old))
    s = s.replace(old, new)
s = s.replace('import model;', 'import model;\nvar dbg_origin: i64 = -1; var dbg_node: i64 = -1;', 1)
rep("epoch: i64 = 0, walked: i8 = 0 }", "epoch: i64 = 0, walked: i8 = 0, origin: i64 = -1 }")
rep('''recursive fn life_eval(p: Program&, l: Lifetimes&, node: i64, destination: i64 = 0, selected_result: i64 = -1) -> LifeValue {''', '''recursive fn life_eval(p: Program&, l: Lifetimes&, node: i64, destination: i64 = 0, selected_result: i64 = -1) -> LifeValue {
    dbg_node = node;''')
rep('''    if sources != 0 { life_effect(l, LifeEffect { kind: 4, node: -1, value: LifeValue { contents: sources }, places: life_root_set(l, root) }); }''',
    '''    if sources != 0 { var dbg_from = dbg_origin; if dbg_from < 0 { dbg_from = dbg_node; } life_effect(l, LifeEffect { kind: 4, node: -1, value: LifeValue { contents: sources }, places: life_root_set(l, root), origin: dbg_from }); }''')
rep('''                if !refused { life_add_contents(l, alt.root, effect.value.contents); }''', '''                if !refused { dbg_origin = effect.origin; life_add_contents(l, alt.root, effect.value.contents); dbg_origin = -1; }''')
rep('''dbg_store(p, l, 2, call, source, alt, frame, effect.node, dbg_original.places, dbg_original.value.contents);''', '''dbg_store(p, l, 2, call, source, alt, frame, effect.origin, dbg_original.places, dbg_original.value.contents);''')
open(f, 'w').write(s)
