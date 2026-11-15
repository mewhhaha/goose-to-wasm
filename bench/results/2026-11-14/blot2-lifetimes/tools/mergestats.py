"""mergestats.py SELFHOST_COPY: on top of progress.py, counts summary-merge chain walks (diagnosis only)."""
import sys
d = sys.argv[1]
f = d + '/checker_lifetimes.goose'
s = open(f).read()
def rep(old, new):
    global s
    assert s.count(old) == 1, (old[:100], s.count(old))
    s = s.replace(old, new)
s = s.replace('var dbg_next_frames: i64 = 1000;', '''var dbg_next_frames: i64 = 1000;
var m_calls: i64 = 0; var m_steps: i64 = 0; var m_match: i64 = 0; var m_max: i64 = 0; var m_kind_steps: i64[16] = [0; 16]; var m_kind_calls: i64[16] = [0; 16];
var m_same_key: i64 = 0;''', 1)
rep('''    out.push('\\n'); write_stderr(out);
}''', '''    dbg_kv(out, "m_calls", m_calls); dbg_kv(out, "m_steps", m_steps); dbg_kv(out, "m_match", m_match); dbg_kv(out, "m_max", m_max); dbg_kv(out, "m_same_key", m_same_key);
    for k in 0..10 { dbg_kv(out, "kc", m_kind_calls[k]); dbg_kv(out, "ks", m_kind_steps[k]); }
    out.push('\\n'); write_stderr(out);
}''')
rep('''    var previous = l.summary_heads[bucket];
    while previous >= 0 {
        let summary: const LifeSummary& = l.summaries[previous]; let next = summary.next;''', '''    var previous = l.summary_heads[bucket]; m_calls += 1; m_kind_calls[effect.kind] += 1; var steps = 0;
    while previous >= 0 {
        let summary: const LifeSummary& = l.summaries[previous]; let next = summary.next;
        m_steps += 1; steps += 1; m_kind_steps[effect.kind] += 1; if steps > m_max { m_max = steps; }
        if summary.key == key { m_same_key += 1; }''')
open(f, 'w').write(s)
