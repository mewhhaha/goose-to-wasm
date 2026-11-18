import sys
from pathlib import Path
p=Path(sys.argv[1])/'selfhost/checker_lifetimes.goose'
src=p.read_text()
candidate=sys.argv[2]=='candidate'
helper="""
fn dbg_kills(l: Lifetimes&) -> u64 {
    var active: i64[>..] = [];
    BODY
    active.sort();
    var h: u64 = 31; var previous: i64 = -1;
    for key in active { if key != previous { h = dbg_mix(h, key); } previous = key; }
    return h;
}
""".replace('BODY', '''for root, index in l.roots {
        var at = root.first_kill;
        while at >= 0 { let kill = l.kills[at]; active.push(index * 4294967296 + kill.field); at = kill.next; }
    }''' if candidate else '''for kill in l.kills { if kill.active { active.push(kill.root * 4294967296 + kill.field); } }''')
src+=helper
k='dbg_kv(out, "bad_exits", bad_exits);'
assert src.count(k)==1
src=src.replace(k,k+' dbg_kv(out, "active_fields", (dbg_kills(l) >> 1) as! i64);')
if candidate:
    start=src.index('fn life_shrink_array('); stop=src.index('fn life_shrink(',start)
    fn=src[start:stop].replace('life_next_holder(l,','dbg_next_holder(p, l,')
    src=src[:start]+fn+src[stop:]
    src+="""
fn dbg_next_holder(p: Program&, l: Lifetimes&, after: i64) -> i64 {
    let found = life_next_holder(l, after);
    var actual = found;
    while actual >= 0 {
        let t = p.symbols[l.cells[actual].symbol].type_id;
        if life_is_ref(p, t) || life_holds(p, t) { break; }
        actual = life_next_holder(l, actual);
    }
    var expected = life_next_live(l, after);
    while expected >= 0 {
        let t = p.symbols[l.cells[expected].symbol].type_id;
        if life_is_ref(p, t) || life_holds(p, t) { break; }
        expected = life_next_live(l, expected);
    }
    if expected != actual { print("holder enumeration differs ", after, expected, actual); }
    return found;
}
"""
p.write_text(src)
