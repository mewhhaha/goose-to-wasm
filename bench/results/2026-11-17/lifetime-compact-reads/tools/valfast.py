#!/usr/bin/env python3
"""valfast.py FILE [STEPS]: validation shortcuts in checker_lifetimes.goose; STEPS is a comma list, default 1,2,3.

1  the index types that name a pool are listed once, not found in all types at every shrink
2  within one shrink check, a question already asked of an earlier cell is not asked again (needs 1)
3  a replayed construct read the activation has been offered is passed without reading its effect
9  not kept: a construct read looks at a hold's kind before anything else
"""
import sys
p = sys.argv[1]; chosen = [int(x) for x in (sys.argv[2] if len(sys.argv) > 2 else "1,2,3").split(",")]
t = open(p).read(); n = 0
def rep(old, new):
    global t, n
    assert t.count(old) == 1, (old[:70], t.count(old)); t = t.replace(old, new); n += 1
if 9 in chosen:
    rep("""    for index in l.hold_floor..l.hold_count {
        let hold = l.holds[index];
        var type_id = value.type_id;""", """    for index in l.hold_floor..l.hold_count {
        // Only a value under construction is asked (kind 2): most holds are others.
        if l.holds[index].kind != 2 { continue; }
        let hold = l.holds[index];
        var type_id = value.type_id;""")
if 1 in chosen:
    rep("""    holder_starts: i64[>..]&, holder_counts: i64[>..]&, holder_refs: i64[>..]&,
    atoms:""", """    holder_starts: i64[>..]&, holder_counts: i64[>..]&, holder_refs: i64[>..]&,
    // The index and bound types that name a pool, listed when the types are
    // frozen (life_index_shrink).
    index_types: i64[>..]&,
    atoms:""")
    rep("""var holder_refs: i64[>..] = [];
""", """var holder_refs: i64[>..] = [];
    var index_types: i64[>..] = [];
""")
    rep("holder_refs: holder_refs, atoms: atoms,", "holder_refs: holder_refs, index_types: index_types, atoms: atoms,")
    rep("""    // Standalone argument synthesis is complete; evaluation only reads types.
    l.types_frozen = true;""", """    // Standalone argument synthesis is complete; evaluation only reads types.
    l.types_frozen = true;
    for t, id in p.types { if t.kind == TY_INT && t.index_type >= 0 && t.pool >= 0 { l.index_types.push(id); } }""")
    rep("""    if l.discovery { return; }
    for t in p.types {
        if t.kind != TY_INT || t.index_type < 0 || t.pool < 0 { continue; }
        let owner: const Symbol& = p.symbols[t.pool]; let named = life_pool_places(p, l, t.pool);""", """    if l.discovery { return; }
    var count = p.types.len; if l.types_frozen { count = l.index_types.len; }
    for item in 0..count {
        var id = item; if l.types_frozen { id = l.index_types[item]; }
        let t: const Type& = p.types[id];
        if t.kind != TY_INT || t.index_type < 0 || t.pool < 0 { continue; }
        let owner: const Symbol& = p.symbols[t.pool]; let named = life_pool_places(p, l, t.pool);""")
if 2 in chosen:
    rep("""struct LifeHold {""", """// A question a shrink check has asked of a live cell, and its answer
// (life_shrink_array): a reference's pointee type and what it refers to, or
// a holder's type, place and contents.
struct LifeAsked { a: i64, b: i64, c: i64, into: bool }
struct LifeHold {""")
    rep("""    index_types: i64[>..]&,
    atoms:""", """    index_types: i64[>..]&, asked: LifeAsked[>..]&,
    atoms:""")
    rep("""    var index_types: i64[>..] = [];
""", """    var index_types: i64[>..] = []; var asked: LifeAsked[>..] = [];
""")
    rep("index_types: index_types, atoms: atoms,", "index_types: index_types, asked: asked, atoms: atoms,")
    rep("""        let value = LifeValue { type_id: cell_type, place: life_root_set(l, cell.root), refs: cell.live_refs, contents: l.roots[cell.root].live_contents };
        if life_points_into(p, l, value, receiver.place, receiver.type_id) && life_used_after(p, l, cell) {""", """        let value = LifeValue { type_id: cell_type, place: life_root_set(l, cell.root), refs: cell.live_refs, contents: l.roots[cell.root].live_contents };
        // Whether a value points into the array depends on a reference's
        // pointee type and referents, or on a holder's type, place and
        // contents (life_points_into), and on nothing this loop changes.
        // Every frame up the stack has a cell for the same few references:
        // the answer for one is the answer for the next.
        var a = cell_type; var b = value.place; var c = value.contents;
        if life_is_ref(p, cell_type) { a = p.types[cell_type].element; b = value.refs; c = -2; }
        var into = false; var known = false;
        for old in l.asked { if old.a == a && old.b == b && old.c == c { known = true; into = old.into; break; } }
        if !known { into = life_points_into(p, l, value, receiver.place, receiver.type_id); if l.asked.len < 64 { l.asked.push(LifeAsked { a: a, b: b, c: c, into: into }); } }
        if into && life_used_after(p, l, cell) {""")
    rep("""    var index = life_next_live(l, -1);
    while index >= 0 {
        // A cell whose type neither is a reference nor holds one points into""", """    l.asked.clear();
    var index = life_next_live(l, -1);
    while index >= 0 {
        // A cell whose type neither is a reference nor holds one points into""")
if 3 in chosen:
    rep("""    if !(l.discovery && l.frame > 0 && l.activations < 1073741824) { life_effect(l, offer); return; }""", """    // In validation this is the recording of the effect in the frames'
    // effect lists, which have it from then on; what it is checked against
    // is looked at every time, by the caller.
    if !((l.discovery || l.class_frames == 0) && l.frame > 0 && l.activations < 1073741824) { life_effect(l, offer); return; }""")
    rep("""    let others = chain >= 0 && life_chain_replayed(l, chain) == version;""", """    let others = chain >= 0 && life_chain_replayed(l, chain) == version;
    // In validation a construct read does two things: it is recorded up the
    // chain, which the activation's stamp on its leaf says has been done,
    // and it is checked against the values under construction, of which
    // there are none here most of the time.
    var quick = !l.discovery && m.count == 0 && l.class_frames == 0 && l.frame > 0 && l.activations < 1073741824;
    if quick { for index in l.hold_floor..l.hold_count { if l.holds[index].kind == 2 { quick = false; } } }""")
    rep("""        var effect = l.effects[at]; var next = effect.next; if others { next = l.summaries[at].other; } var mapped = false; var leaf = -1;""", """        if quick {
            let s: const LifeSummary& = l.summaries[at];
            if s.kind == 3 && s.leaf >= 0 && life_leaf_offered(l, s.leaf as i64) { at = s.after; continue; }
        }
        var effect = l.effects[at]; var next = effect.next; if others { next = l.summaries[at].other; } var mapped = false; var leaf = -1;
        if quick && effect.kind == 3 && l.reading_place == 0 {
            leaf = l.summaries[at].leaf as i64; if leaf < 0 { leaf = life_leaf(l, effect.kind, effect.node, effect.value); l.summaries[at].leaf = leaf as i32; }
            if life_leaf_offered(l, leaf) { at = next; continue; }
        }""")
open(p, 'w').write(t); print('applied', n)
