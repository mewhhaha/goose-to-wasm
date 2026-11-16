"""dbgvia.py DIR (after dbgstore2.py): for each refused replayed store, print
which of the callee's own alternatives map, at this call, to the refused
source and to the destination (DBGVIA lines)."""
import sys
f = sys.argv[1] + '/checker_lifetimes.goose'
s = open(f).read()
old = "if l.roots[source.root].depth > l.roots[alt.root].depth { dbg_store(p, l, 2, call, source, alt, frame,"
assert s.count(old) == 1, s.count(old)
new = """if l.roots[source.root].depth > l.roots[alt.root].depth {
                            if l.discovery {
                                var dbg_seen = false; for failure in l.failures { if failure.node == call { dbg_seen = true; } }
                                if !dbg_seen {
                                    var dbg_v: u8[>..] = []; dbg_v.append("DBGVIA");
                                    var dbg_x = l.sets[dbg_original.value.contents].first;
                                    while dbg_x >= 0 {
                                        var dbg_a = l.alts[dbg_x]; dbg_x = dbg_a.next; dbg_a.next = -1;
                                        let dbg_m = life_map_set(p, l, life_alt_set(l, dbg_a), m); let dbg_hit = life_find(l, dbg_m, source.root as i64);
                                        if dbg_hit >= 0 && l.alts[dbg_hit].exact == source.exact { dbg_v.append(" value:"); dbg_root(p, l, dbg_v, dbg_a); }
                                    }
                                    dbg_x = l.sets[dbg_original.places].first;
                                    while dbg_x >= 0 {
                                        var dbg_a = l.alts[dbg_x]; dbg_x = dbg_a.next; dbg_a.next = -1;
                                        let dbg_m = life_map_set(p, l, life_alt_set(l, dbg_a), m, 1);
                                        if life_find(l, dbg_m, alt.root as i64) >= 0 { dbg_v.append(" place:"); dbg_root(p, l, dbg_v, dbg_a); }
                                    }
                                    dbg_v.push(10 as u8); write_stderr(dbg_v);
                                }
                            }
                            dbg_store(p, l, 2, call, source, alt, frame,"""
s = s.replace(old, new)
open(f, 'w').write(s)
