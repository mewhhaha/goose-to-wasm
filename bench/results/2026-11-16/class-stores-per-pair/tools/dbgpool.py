"""dbgpool.py DIR SOURCE LINE (after dbgstore2.py): where reference contents are
first stored into the global declared at SOURCE:LINE."""
import sys
f = sys.argv[1] + '/checker_lifetimes.goose'
src, line = sys.argv[2], sys.argv[3]
s = open(f).read()
def rep(old, new, count=1):
    global s
    assert s.count(old) == count, (old[:90], s.count(old))
    s = s.replace(old, new)
s = s.replace('import model;', 'import model;\nvar dbg_sym: i64 = -1; var dbg_node: i64 = -1; var dbg_store_node: i64 = -1; var dbg_pools: i64 = 0; var dbg_pending: i64 = 0;', 1)
rep('''fn life_add_contents(l: Lifetimes&, root: i64, sources: i64) {''', '''fn life_add_contents(l: Lifetimes&, root: i64, sources: i64) {
    if sources != 0 && dbg_sym >= 0 && l.roots[root].symbol == dbg_sym && l.island > 0 { dbg_pending = sources; }''')
rep('''recursive fn life_eval(p: Program&, l: Lifetimes&, node: i64, destination: i64 = 0, selected_result: i64 = -1) -> LifeValue {''', '''recursive fn life_eval(p: Program&, l: Lifetimes&, node: i64, destination: i64 = 0, selected_result: i64 = -1) -> LifeValue {
    dbg_node = node;''')
rep('''fn life_store(p: Program&, l: Lifetimes&, node: i64, places: i64, value: LifeValue, binding: bool = false, through: bool = false) {''', '''fn dbg_pool_show(p: Program&, l: Lifetimes&, node: i64, places: i64, value: LifeValue) {
    if dbg_pending == 0 { return; }
    let sources = dbg_pending; dbg_pending = 0;
    if dbg_pools >= 12 { return; }
    dbg_pools += 1;
    var o: u8[>..] = []; o.append("DBGPOOL store@"); dbg_at(p, o, node); o.append(" kind="); if node >= 0 { dbg_d(o, p.nodes[node].kind); } o.append(" frame="); dbg_d(o, l.frame); o.append(" fn="); if l.frame > 0 { dbg_at(p, o, l.frames[l.frame].function_node); } o.append(" island="); dbg_d(o, l.island);
    o.append(" valuetype="); dbg_d(o, value.type_id); dbg_alts(p, l, o, "places", places); dbg_alts(p, l, o, "refs", value.refs); dbg_alts(p, l, o, "contents", value.contents); dbg_alts(p, l, o, "added", sources); o.push(10 as u8); write_stderr(o);
}
fn life_store(p: Program&, l: Lifetimes&, node: i64, places: i64, value: LifeValue, binding: bool = false, through: bool = false) {
    dbg_pending = 0; defer dbg_pool_show(p, l, node, places, value);''')
rep('''fn check_lifetimes(p: Program&, scope_parent: const i64[:], scope_depth: const i64[:], scope_functions: const i64[:], pool_references: const i64[:]) {
    if p.diagnostics.len > 0 { return; }''', '''fn check_lifetimes(p: Program&, scope_parent: const i64[:], scope_depth: const i64[:], scope_functions: const i64[:], pool_references: const i64[:]) {
    if p.diagnostics.len > 0 { return; }
    for symbol, index in p.symbols { if symbol.node >= 0 && p.nodes[symbol.node].token >= 0 && p.tokens[p.nodes[symbol.node].token].line == LINE && p.sources[p.tokens[p.nodes[symbol.node].token].source].path_len > 0 && p.tokens[p.nodes[symbol.node].token].source == SRC && (symbol.flags & S_GLOBAL) != 0 { dbg_sym = index; } }'''.replace('LINE', line).replace('SRC', src))
open(f, 'w').write(s)
