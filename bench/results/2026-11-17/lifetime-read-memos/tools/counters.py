#!/usr/bin/env python3
"""counters.py FILE: add counters to the checker_lifetimes.goose of `ddbbe23` (before the memos) that print, at
the end of the lifetime pass: summary merges by discovery pass and by outcome, for construct reads (kind 3) and
in all; summary entries and how many are construct reads; where construct reads come from (replay or body,
discovery or validation); and what the shrink checks of validation walk. Build the copy as tools/stepbench.sh
builds its steps and run it with --check on selfhost/main.goose."""
import re, sys
p = sys.argv[1]; t = open(p).read()
def rep(old, new):
    global t
    assert t.count(old) == 1, (old[:60], t.count(old)); t = t.replace(old, new)
rep("fn life_effect_merge(", """var dbg_pass: i64[16] = [0; 16]; var dbg_m2: i64[16] = [0; 16]; var dbg_m1: i64[16] = [0; 16]; var dbg_m0: i64[16] = [0; 16];
var dbg_replaying: bool = false; var dbg_rd: i64 = 0; var dbg_dd: i64 = 0; var dbg_rv: i64 = 0; var dbg_dv: i64 = 0;
var dbg_shr: i64 = 0; var dbg_cells: i64 = 0; var dbg_held: i64 = 0; var dbg_alts: i64 = 0;
fn life_effect_merge(""")
rep("""                let merged = life_effect_merge(l, effect, frame, bucket, summary_key, outside, site);""", """                let merged = life_effect_merge(l, effect, frame, bucket, summary_key, outside, site);
                dbg_pass[l.pass] += 1;
                if effect.kind == 3 { if merged == 2 { dbg_m2[l.pass] += 1; } else if merged == 1 { dbg_m1[l.pass] += 1; } else { dbg_m0[l.pass] += 1; } }""")
rep("""    if value.element_array != -1 || life_cached_size_class(p, l, effect_type) == 2 { life_effect(l, LifeEffect { kind: 3, node: node, value: value, places: effect_places }); }""", """    if value.element_array != -1 || life_cached_size_class(p, l, effect_type) == 2 {
        if l.discovery { if dbg_replaying { dbg_rd += 1; } else { dbg_dd += 1; } } else { if dbg_replaying { dbg_rv += 1; } else { dbg_dv += 1; } }
        life_effect(l, LifeEffect { kind: 3, node: node, value: value, places: effect_places }); }""")
rep("""        else if effect.kind == 3 { life_construct_read(p, l, effect.node, effect.value); }""", """        else if effect.kind == 3 { dbg_replaying = true; life_construct_read(p, l, effect.node, effect.value); dbg_replaying = false; }""")
rep("""    if l.discovery { return; }
    var pool = l.sets[receiver.place].first;""", """    if l.discovery { return; }
    dbg_shr += 1;
    var pool = l.sets[receiver.place].first;""")
rep("""        let cell = l.cells[index]; let visible = life_visible(l, index); index = life_next_live(l, index);
        if !visible { continue; }""", """        let cell = l.cells[index]; let visible = life_visible(l, index); index = life_next_live(l, index); dbg_cells += 1;
        if !visible { continue; }""")
rep("""fn life_held_into(p: Program&, l: Lifetimes&, owners: i64, holder_type: i64, target: i64, element: i64, slot_safe: bool) -> bool {
    var work: LifeWalk[>..] = []; var at = l.sets[owners].first;""", """fn life_held_into(p: Program&, l: Lifetimes&, owners: i64, holder_type: i64, target: i64, element: i64, slot_safe: bool) -> bool {
    dbg_held += 1;
    var work: LifeWalk[>..] = []; var at = l.sets[owners].first;""")
rep("""                    var alt = l.alts[ai]; ai = alt.next;
                    if l.class_frames > 0 { alt = life_class_narrow(l, alt, held.root, t.element); }""", """                    var alt = l.alts[ai]; ai = alt.next; dbg_alts += 1;
                    if l.class_frames > 0 { alt = life_class_narrow(l, alt, held.root, t.element); }""")
a = t.index("fn check_lifetimes(p: Program&"); m = re.search(r"\n}\n", t[a:]); end = a + m.start()
t = t[:end] + '''
    for i in 1..9 { if dbg_pass[i] > 0 { print("COUNT pass ", i, ": merges ", dbg_pass[i], ", of construct reads: already there and sent on ", dbg_m2[i], ", already there ", dbg_m1[i], ", new ", dbg_m0[i]); } }
    var reads = 0; for s in l.summaries { if s.kind == 3 { reads += 1; } }
    print("COUNT entries ", l.summaries.len, ", construct reads ", reads, ", frames ", l.frames.len);
    print("COUNT construct reads offered: replayed in discovery ", dbg_rd, ", from a body in discovery ", dbg_dd, ", replayed in validation ", dbg_rv, ", from a body in validation ", dbg_dv);
    print("COUNT shrink checks ", dbg_shr, ", live cells asked ", dbg_cells, ", holder walks ", dbg_held, ", alternatives looked at ", dbg_alts);''' + t[end:]
open(p, 'w').write(t); print('applied')
