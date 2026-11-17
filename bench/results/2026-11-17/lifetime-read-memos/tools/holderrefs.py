#!/usr/bin/env python3
"""holderrefs.py FILE: life_held_into takes the reference types inside a holder's type from a list made once a type."""
import sys
p = sys.argv[1]; t = open(p).read()
def rep(old, new, count=1):
    global t
    assert t.count(old) == count, (old[:70], t.count(old)); t = t.replace(old, new)
a = t.index("fn life_held_into(p: Program&, l: Lifetimes&, owners: i64, holder_type: i64, target: i64, element: i64, slot_safe: bool) -> bool {")
b = t.index("fn life_same_path(p: Program&, left: i64, right: i64) -> bool {")
old = t[a:b]
for must in ["var types: i64[>..] = [held.type_id]; var ti = 0;", "if !seen { types.push(ft); } field = p.nodes[field].next;", "if t.kind == TY_REF && t.length_storage >= 0 { continue; }"]:
    assert must in old, must
body_start = old.index("            if t.kind == TY_REF || t.kind == TY_SLICE {\n") + len("            if t.kind == TY_REF || t.kind == TY_SLICE {\n")
body_end = old.index("            } else if t.kind == TY_ARRAY && t.element >= 0 {")
body = old[body_start:body_end]
# The body was indented for the type walk; it now runs once a reference type.
body = "\n".join(line[4:] if line.startswith("    ") else line for line in body.split("\n"))
new = '''// The reference and slice types in a holder's own storage: its fields',
// variants' and elements', not what a reference leads to. With root >= 0,
// without the top-level fields that an active kill of that root names.
fn life_holder_scan(p: Program&, l: Lifetimes&, holder: i64, root: i64, out: i64[>..]&) {
    var types: i64[>..] = [holder]; var ti = 0;
    while ti < types.len {
        let ty = types[ti]; ti += 1; let t: const Type& = p.types[ty];
        if t.kind == TY_REF || t.kind == TY_SLICE { out.push(ty); }
        else if t.kind == TY_ARRAY && t.element >= 0 {
            var seen = false; for old in types { if old == t.element { seen = true; } }
            if !seen { types.push(t.element); }
        } else if t.kind == TY_STRUCT || t.kind == TY_ENUM || t.kind == TY_TUPLE {
            var field = t.first;
            while field >= 0 {
                let ft = p.nodes[field].type_id; var seen = ft < 0;
                if ty == holder && root >= 0 {
                    for kill in l.kills { if kill.active && kill.root == root && kill.field == field { seen = true; } }
                }
                for old in types { if old == ft { seen = true; } }
                if !seen { types.push(ft); } field = p.nodes[field].next;
            }
        }
    }
}
// Lists a type's reference and slice types in holder_refs, once.
fn life_holder_list(p: Program&, l: Lifetimes&, holder: i64) {
    if l.holder_starts[holder] >= 0 { return; }
    var found: i64[>..] = []; life_holder_scan(p, l, holder, -1, found);
    l.holder_starts[holder] = l.holder_refs.len; l.holder_counts[holder] = found.len; l.holder_refs.append(found);
}
fn life_held_into(p: Program&, l: Lifetimes&, owners: i64, holder_type: i64, target: i64, element: i64, slot_safe: bool) -> bool {
    var work: LifeWalk[>..] = []; var at = l.sets[owners].first;
    while at >= 0 { let alt = l.alts[at]; work.push(LifeWalk { root: alt.root, type_id: holder_type }); at = alt.next; }
    var current = 0; var scanned: i64[>..] = [];
    while current < work.len {
        let held = work[current]; current += 1; if held.type_id < 0 { continue; }
        let root = l.roots[held.root];
        // The reference types the holder's type has in it are the same every
        // time (holder_refs), unless a field of this root has been killed.
        var killed = false;
        if life_same(p, root.type_id, held.type_id) { for kill in l.kills { if kill.active && kill.root == held.root { killed = true; } } }
        var first = 0; var count = 0; let listed = !killed && l.types_frozen && held.type_id < l.holder_starts.len;
        if listed { life_holder_list(p, l, held.type_id); first = l.holder_starts[held.type_id]; count = l.holder_counts[held.type_id]; }
        else {
            scanned.clear(); var kill_root: i64 = -1; if killed { kill_root = held.root; }
            life_holder_scan(p, l, held.type_id, kill_root, scanned); count = scanned.len;
        }
        // Whether a held alternative is a byte view: 0 not looked yet, 1 none, 2 some.
        var bytes = 0;
        for item in 0..count {
            var ty = 0; if listed { ty = l.holder_refs[first + item]; } else { ty = scanned[item]; }
            let t: const Type& = p.types[ty];
''' + body + '''        }
    }
    return false;
}

'''
t = t[:a] + new + t[b:]
rep("""    size_classes: i64[>..]&, types_frozen: bool = false,""", """    size_classes: i64[>..]&, types_frozen: bool = false,
    // For a type, where its reference and slice types are in holder_refs
    // and how many (life_holder_scan), or -1 before they are listed.
    holder_starts: i64[>..]&, holder_counts: i64[>..]&, holder_refs: i64[>..]&,""")
rep("""    var size_classes: i64[>..] = []; size_classes.resize(p.types.len, -1);""", """    var size_classes: i64[>..] = []; size_classes.resize(p.types.len, -1);
    var holder_starts: i64[>..] = []; holder_starts.resize(p.types.len, -1); var holder_counts: i64[>..] = []; holder_counts.resize(p.types.len, 0); var holder_refs: i64[>..] = [];""")
rep("""size_classes: size_classes,""", """size_classes: size_classes, holder_starts: holder_starts, holder_counts: holder_counts, holder_refs: holder_refs,""")
open(p, 'w').write(t); print('applied')
