#!/usr/bin/env python3
"""holderfields.py FILE: (after holderrefs.py) a root with killed fields takes each remaining field's list."""
import sys
p = sys.argv[1]; t = open(p).read()
def rep(old, new, count=1):
    global t
    assert t.count(old) == count, (old[:70], t.count(old)); t = t.replace(old, new)
rep("""        if listed { life_holder_list(p, l, held.type_id); first = l.holder_starts[held.type_id]; count = l.holder_counts[held.type_id]; }
        else {""", """        let ht: const Type& = p.types[held.type_id];
        if listed { life_holder_list(p, l, held.type_id); first = l.holder_starts[held.type_id]; count = l.holder_counts[held.type_id]; }
        else if killed && l.types_frozen && (ht.kind == TY_STRUCT || ht.kind == TY_ENUM || ht.kind == TY_TUPLE) {
            // The fields no kill names, each with its own list. A type two
            // fields share is then asked twice, to the same answer.
            scanned.clear(); var field = ht.first;
            while field >= 0 {
                let ft = p.nodes[field].type_id; var skip = ft < 0;
                for kill in l.kills { if kill.active && kill.root == held.root && kill.field == field { skip = true; } }
                if !skip && ft < l.holder_starts.len {
                    life_holder_list(p, l, ft); let from = l.holder_starts[ft];
                    for item in 0..l.holder_counts[ft] { scanned.push(l.holder_refs[from + item]); }
                } else if !skip { life_holder_scan(p, l, ft, -1, scanned); }
                field = p.nodes[field].next;
            }
            count = scanned.len;
        } else {""")
open(p, 'w').write(t); print('applied')
