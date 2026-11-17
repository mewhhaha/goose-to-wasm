#!/usr/bin/env python3
"""compactcount.py FILE: counters for the checker_lifetimes.goose with the reads held by leaf (prints COUNT lines)."""
import re, sys
p = sys.argv[1]; t = open(p).read()
def rep(old, new):
    global t
    assert t.count(old) == 1, (old[:60], t.count(old)); t = t.replace(old, new)
rep("fn life_read_merge(", "var dbg_r: i64[16] = [0; 16];\nfn life_read_merge(")
rep("""        l.revision += 1; l.frames[frame].reads_version += 1;
        return 0;""", """        l.revision += 1; l.frames[frame].reads_version += 1; dbg_r[0] += 1;
        return 0;""")
rep("""        if walked >= 0 && (l.summary_reads[index].walked == (walked | 1) || l.summary_reads[index].walked == walked) { return 2; }
        l.summary_reads[index].walked = walked;
        return 1;""", """        if walked >= 0 && (l.summary_reads[index].walked == (walked | 1) || l.summary_reads[index].walked == walked) { dbg_r[1] += 1; return 2; }
        l.summary_reads[index].walked = walked; dbg_r[2] += 1;
        return 1;""")
rep("""    if !life_equal(l, refs, value.refs) || !life_equal(l, contents, value.contents) || !life_equal(l, place, value.place) { l.revision += 1; }""",
    """    if !life_equal(l, refs, value.refs) || !life_equal(l, contents, value.contents) || !life_equal(l, place, value.place) { l.revision += 1; dbg_r[3] += 1; } else { dbg_r[4] += 1; }""")
rep("""        if own >= 0 && l.summary_reads[own].seen as i64 == leaf && l.summary_reads[own].sent as i64 == context { return; }""",
    """        if own >= 0 && l.summary_reads[own].seen as i64 == leaf && l.summary_reads[own].sent as i64 == context { dbg_r[6] += 1; return; }""")
rep("""fn life_read_offer(l: Lifetimes&, leaf: i64, effect: const LifeEffect&) {
    l.offer_count += 1;""", """fn life_read_offer(l: Lifetimes&, leaf: i64, effect: const LifeEffect&) {
    l.offer_count += 1; dbg_r[5] += 1;""")
rep("""    l.discovery = false;
    for root, index in l.roots { l.roots[index].live_contents = root.contents; }""", """    print("COUNT after discovery: entries of other kinds ", l.effects.len, ", construct reads ", l.summary_reads.len, ", table slots ", l.read_slots.len, ", leaves ", l.leaves.len, ", frames ", l.frames.len);
    print("COUNT construct reads offered to the summaries ", dbg_r[5], ", of them known to the chain from the offering frame's entry ", dbg_r[6]);
    print("COUNT merges: new ", dbg_r[0], ", there and sent on in this activation ", dbg_r[1], ", there ", dbg_r[2], ", joined and grew ", dbg_r[3], ", joined the same ", dbg_r[4]);
    l.discovery = false;
    for root, index in l.roots { l.roots[index].live_contents = root.contents; }""")
a = t.index("fn check_lifetimes(p: Program&"); m = re.search(r"\n}\n", t[a:]); end = a + m.start()
t = t[:end] + '''
    print("COUNT at the end: effect entries ", l.effects.len, " (170 bytes and a 128-byte summary record each), construct reads ", l.summary_reads.len, " (32 bytes each), table slots ", l.read_slots.len, " (4 bytes each)");''' + t[end:]
open(p, 'w').write(t); print('applied')
