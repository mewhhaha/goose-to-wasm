#!/usr/bin/env python3
"""counters-after.py FILE: the counters of counters.py for the checker_lifetimes.goose with the memos in."""
import re, sys
p = sys.argv[1]; t = open(p).read()
def rep(old, new):
    global t
    assert t.count(old) == 1, (old[:60], t.count(old)); t = t.replace(old, new)
rep("fn life_effect_merge(", """var dbg_pass: i64[16] = [0; 16]; var dbg_m2: i64[16] = [0; 16]; var dbg_m1: i64[16] = [0; 16]; var dbg_m0: i64[16] = [0; 16];
var dbg_offered: i64 = 0; var dbg_known: i64 = 0; var dbg_val: i64 = 0; var dbg_shr: i64 = 0; var dbg_cells: i64 = 0; var dbg_held: i64 = 0; var dbg_alts: i64 = 0;
fn life_effect_merge(""")
rep("""                let merged = life_effect_merge(l, effect, frame, bucket, summary_key, outside, site);""", """                let merged = life_effect_merge(l, effect, frame, bucket, summary_key, outside, site);
                dbg_pass[l.pass] += 1;
                if effect.kind == 3 { if merged == 2 { dbg_m2[l.pass] += 1; } else if merged == 1 { dbg_m1[l.pass] += 1; } else { dbg_m0[l.pass] += 1; } }""")
rep("""    if !(l.discovery && l.frame > 0 && l.activations < 1073741824) { life_effect(l, offer); return; }""", """    if !(l.discovery && l.frame > 0 && l.activations < 1073741824) { dbg_val += 1; life_effect(l, offer); return; }""")
rep("""    if !offered {
        let offers = l.offer_count;""", """    if offered { dbg_known += 1; }
    if !offered {
        dbg_offered += 1;
        let offers = l.offer_count;""")
rep("""    if l.discovery { return; }
    var pool = l.sets[receiver.place].first;""", """    if l.discovery { return; }
    dbg_shr += 1;
    var pool = l.sets[receiver.place].first;""")
rep("""        let cell = l.cells[index]; let visible = life_visible(l, index); index = life_next_live(l, index);
        if !visible { continue; }""", """        let cell = l.cells[index]; let visible = life_visible(l, index); index = life_next_live(l, index); dbg_cells += 1;
        if !visible { continue; }""")
rep("""    var current = 0; var scanned: i64[>..] = [];""", """    var current = 0; var scanned: i64[>..] = []; dbg_held += 1;""")
rep("""                var alt = l.alts[ai]; ai = alt.next;
                if l.class_frames > 0 { alt = life_class_narrow(l, alt, held.root, t.element); }""", """                var alt = l.alts[ai]; ai = alt.next; dbg_alts += 1;
                if l.class_frames > 0 { alt = life_class_narrow(l, alt, held.root, t.element); }""")
a = t.index("fn check_lifetimes(p: Program&"); m = re.search(r"\n}\n", t[a:]); end = a + m.start()
t = t[:end] + '''
    for i in 1..9 { if dbg_pass[i] > 0 { print("COUNT pass ", i, ": merges ", dbg_pass[i], ", of construct reads: already there and sent on ", dbg_m2[i], ", already there ", dbg_m1[i], ", new ", dbg_m0[i]); } }
    var reads = 0; for s in l.summaries { if s.kind == 3 { reads += 1; } }
    print("COUNT entries ", l.summaries.len, ", construct reads ", reads, ", frames ", l.frames.len, ", distinct reads (leaves) ", l.leaves.len);
    print("COUNT construct reads in discovery: offered ", dbg_offered, ", found offered where they were made ", dbg_known, "; in validation ", dbg_val);
    print("COUNT chains of frames ", l.contexts.len, ", reads recorded for a chain ", l.chain_offer_count, ", summaries recorded for a chain ", l.chain_replay_count);
    print("COUNT shrink checks ", dbg_shr, ", live cells asked ", dbg_cells, ", holder walks ", dbg_held, ", alternatives looked at ", dbg_alts, ", reference types listed ", l.holder_refs.len);''' + t[end:]
open(p, 'w').write(t); print('applied')
