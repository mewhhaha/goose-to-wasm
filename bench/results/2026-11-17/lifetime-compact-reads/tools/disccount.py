#!/usr/bin/env python3
"""disccount.py FILE: what discovery still does for construct reads (counters only)."""
import re, sys
p = sys.argv[1]; t = open(p).read()
def rep(old, new):
    global t
    assert t.count(old) == 1, (old[:60], t.count(old)); t = t.replace(old, new)
rep("fn life_effect_merge(", "var dbg_c: i64[32] = [0; 32];\nfn life_effect_merge(")
rep("""        if summary.places == effect.places && summary.refs == effect.value.refs && summary.contents == effect.value.contents && summary.place == effect.value.place {
            if walked >= 0""", """        if summary.places == effect.places && summary.refs == effect.value.refs && summary.contents == effect.value.contents && summary.place == effect.value.place {
            if effect.kind == 3 { dbg_c[0] += 1; }
            if walked >= 0""")
rep("""            life_summary_seen(l, previous, effect);
            if walked >= 0 && (summary.walked == (walked | 1) || summary.walked == walked) { return 2; }""", """            life_summary_seen(l, previous, effect); if effect.kind == 3 { dbg_c[1] += 1; }
            if walked >= 0 && (summary.walked == (walked | 1) || summary.walked == walked) { return 2; }""")
rep("""            if !life_equal(l, places, old_places) || !life_equal(l, refs, old_refs) || !life_equal(l, contents, old_contents) || !life_equal(l, value_places, old_place) { l.revision += 1; }""",
"""            if !life_equal(l, places, old_places) || !life_equal(l, refs, old_refs) || !life_equal(l, contents, old_contents) || !life_equal(l, value_places, old_place) { l.revision += 1; if effect.kind == 3 { dbg_c[2] += 1; } }
            else if effect.kind == 3 { dbg_c[3] += 1; }""")
rep("""                let merged = life_effect_merge(l, effect, frame, bucket, summary_key, outside, site);""", """                let merged = life_effect_merge(l, effect, frame, bucket, summary_key, outside, site);
                if effect.kind == 3 { if merged == 0 { dbg_c[4] += 1; } else if merged == 2 { dbg_c[5] += 1; } } else { dbg_c[6] += 1; }""")
rep("""            if s.replayed == into && s.replayed_epoch == epoch {
                if complete && s.kind == 3""", """            if s.replayed == into && s.replayed_epoch == epoch {
                if s.kind == 3 { dbg_c[8] += 1; } else { dbg_c[9] += 1; }
                if complete && s.kind == 3""")
rep("""            if s.kind == 3 && s.leaf >= 0 && life_leaf_offered(l, s.leaf as i64) { at = s.after; continue; }
        }
        if quick {""", """            if s.kind == 3 && s.leaf >= 0 && life_leaf_offered(l, s.leaf as i64) { dbg_c[10] += 1; at = s.after; continue; }
        }
        if quick {""")
rep("""        let remembered = memo && !mapped;""", """        let remembered = memo && !mapped; if l.discovery { if effect.kind == 3 { dbg_c[11] += 1; } else { dbg_c[12] += 1; } }""")
rep("""    let others = chain >= 0 && life_chain_replayed(l, chain) == version;""", """    let others = chain >= 0 && life_chain_replayed(l, chain) == version;
    if l.discovery && summary { dbg_c[13] += 1; if others { dbg_c[14] += 1; } }""")
a = t.index("fn check_lifetimes(p: Program&"); m = re.search(r"\n}\n", t[a:]); end = a + m.start()
t = t[:end] + '''
    print("COUNT kind-3 merges: same ids ", dbg_c[0], ", same lists ", dbg_c[1], ", joined and grew ", dbg_c[2], ", joined the same ", dbg_c[3], ", new ", dbg_c[4], ", settled ", dbg_c[5], "; other kinds merged ", dbg_c[6]);
    print("COUNT discovery replays ", dbg_c[13], ", of them others-only ", dbg_c[14], "; entries passed as replayed: reads ", dbg_c[8], " others ", dbg_c[9], "; reads passed by leaf ", dbg_c[10], "; entries gone through: reads ", dbg_c[11], " others ", dbg_c[12]);
    var dbg_keys: i64[>..] = []; var dbg_most = 0; var dbg_frames = 0; var dbg_big = 0;
    for f in l.frames { var n = 0; var at = f.first_summary; while at >= 0 { if l.summaries[at].kind == 3 { n += 1; } at = l.summaries[at].after; } if n > dbg_most { dbg_most = n; } if n > 0 { dbg_frames += 1; } if n > 1000 { dbg_big += 1; } }
    print("COUNT activations ", l.activations, ", frames with reads ", dbg_frames, ", most reads in one frame ", dbg_most, ", frames with over 1000 ", dbg_big, ", leaves ", l.leaves.len, ", summaries ", l.summaries.len);''' + t[end:]
open(p, 'w').write(t); print('applied')
