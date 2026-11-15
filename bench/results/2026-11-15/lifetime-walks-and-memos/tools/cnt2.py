"""cnt2.py DIR: counters for life_effect in the working-copy sources (after progress.py)."""
import sys
f=sys.argv[1]+'/checker_lifetimes.goose'
s=open(f).read()
def rep(old,new,count=1):
    global s
    assert s.count(old)==count,(old[:80],s.count(old))
    s=s.replace(old,new)
names=['eff_d','eff_v','chain_d','chain_v','merge_probe','merge_calls','stop2','rep_calls','rep_steps','idx_calls','idx_probe','offer_hit','new_d','new_v','outside_d','join_path','same_path','ident_path','key_mismatch','far_alts']
rep("var dbg_next_frames: i64 = 1000;", "var dbg_next_frames: i64 = 1000;\n"+"".join("var dbg_%s: i64 = 0;\n"%n for n in names))
rep("""    if l.discovery && l.frame > 0 && life_offer_repeated(l, effect) { return; }""", """    if l.discovery { dbg_eff_d += 1; } else { dbg_eff_v += 1; }
    if l.discovery && l.frame > 0 && life_offer_repeated(l, effect) { dbg_offer_hit += 1; return; }""")
rep("""    let ordered = effect.kind == 1 || effect.kind == 4 || effect.kind == 6 || effect.kind == 7;""", """    if l.discovery && outside { dbg_outside_d += 1; }
    let ordered = effect.kind == 1 || effect.kind == 4 || effect.kind == 6 || effect.kind == 7;""")
rep("""        if !l.frames[frame].validated {
            var external = far > depth;""", """        if l.discovery { dbg_chain_d += 1; } else { dbg_chain_v += 1; }
        if !l.frames[frame].validated {
            var external = far > depth;""")
rep("""    var previous = l.summary_heads[bucket];
    while previous >= 0 {
        let summary: const LifeSummary& = l.summaries[previous]; let next = summary.next;""", """    var previous = l.summary_heads[bucket]; dbg_merge_calls += 1;
    while previous >= 0 {
        dbg_merge_probe += 1;
        let summary: const LifeSummary& = l.summaries[previous]; let next = summary.next;""")
rep("""            previous = next; continue;
        }""", """            dbg_key_mismatch += 1; previous = next; continue;
        }""")
rep("""            if walked >= 0 && (summary.walked == (walked | 1) || summary.walked == walked) { return 2; }
            l.summaries[previous].walked = walked;
            return 1;
        }
        // The same lists""", """            dbg_ident_path += 1;
            if walked >= 0 && (summary.walked == (walked | 1) || summary.walked == walked) { dbg_stop2 += 1; return 2; }
            l.summaries[previous].walked = walked;
            return 1;
        }
        // The same lists""")
rep("""            life_summary_seen(l, previous, effect);
            if walked >= 0 && (summary.walked == (walked | 1) || summary.walked == walked) { return 2; }""", """            life_summary_seen(l, previous, effect); dbg_same_path += 1;
            if walked >= 0 && (summary.walked == (walked | 1) || summary.walked == walked) { dbg_stop2 += 1; return 2; }""")
rep("""            let old_places = old.places; let old_refs = old.value.refs;""", """            dbg_join_path += 1;
            let old_places = old.places; let old_refs = old.value.refs;""")
rep("""    var previous = last;
    while previous >= 0 {
        let old: const LifeEffect& = l.effects[previous];
        if effect.kind == 1 && old.kind >= 4 { return false; }""", """    var previous = last; dbg_rep_calls += 1;
    while previous >= 0 {
        dbg_rep_steps += 1;
        let old: const LifeEffect& = l.effects[previous];
        if effect.kind == 1 && old.kind >= 4 { return false; }""")
rep("""    var probe = l.effect_heads[bucket];
    while probe >= 0 {
        let old: const LifeEffect& = l.effects[probe];
        if old.owner == frame &&""", """    var probe = l.effect_heads[bucket]; dbg_idx_calls += 1;
    while probe >= 0 {
        dbg_idx_probe += 1;
        let old: const LifeEffect& = l.effects[probe];
        if old.owner == frame &&""")
rep("""                let index = l.effects.len; var entry = effect; entry.next = -1; entry.previous = last; entry.owner = frame;""", """                if l.discovery { dbg_new_d += 1; } else { dbg_new_v += 1; }
                let index = l.effects.len; var entry = effect; entry.next = -1; entry.previous = last; entry.owner = frame;""")
rep("""    dbg_kv(out, "reads", l.reads.len);""", "".join('    dbg_kv(out, "%s", dbg_%s);\n'%(n,n) for n in names)+"""    dbg_kv(out, "reads", l.reads.len);""")
open(f,'w').write(s)
