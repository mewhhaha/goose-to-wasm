#!/usr/bin/env python3
"""stagetable.py: medians of the self-check rounds per build and blot2's time to its last frame count per build."""
import json, statistics, sys
W = '/home/user/goose-to-wasm/build/runs/'
rows = json.load(open(W + 'selfcheck-stages.json'))['rows']
by = {}
for r in rows: by.setdefault(r['compiler'], []).append(r)
print('%-10s %8s %8s %8s %8s %5s' % ('build', 'wall', 'user', 'life', 'rssMiB', 'n'))
for c, rs in by.items():
    assert all(r['exit'] == 0 for r in rs)
    print('%-10s %8.2f %8.2f %8.2f %8.1f %5d' % (c, statistics.median(r['wall_s'] for r in rs), statistics.median(r['user_s'] for r in rs),
          statistics.median(r['lifetime_s'] for r in rs), statistics.median(r['max_rss_mib'] for r in rs), len(rs)))
def load(path):
    out = []; t0 = None
    for line in open(path, errors='replace'):
        if not line.startswith('LIFEPROG'): continue
        parts = line.split(); tag = parts[1]
        try: d = {k: int(v) for k, v in (kv.split('=') for kv in parts[2:])}
        except Exception: continue
        if tag == 'pass_begin' and t0 is None: t0 = d['ms']
        d['tag'] = tag; d['s'] = (d['ms'] - t0) / 1000; out.append(d)
    return out
try:
    runs = {json.loads(l)['label']: json.loads(l) for l in open(W + 'blot2-stages.jsonl')}
except FileNotFoundError:
    runs = {}
for label, r in runs.items():
    prog = load(W + 'blot2-%s.txt' % label)
    marks = {d['frames']: d['s'] for d in prog if d['tag'] == 'frames'}
    last = prog[-1]
    print('%-10s wall %7.1f user %7.1f rss %7.1f MiB | to 20k %6.1f 40k %6.1f 60k %6.1f 80k %6.1f 93k %6.1f | last frames=%d effects=%d sets=%d alts=%d act=%d set_index=%d' % (
        label, r['wall_s'], r['user_s'], r['max_rss_mib'], marks.get(20000, -1), marks.get(40000, -1), marks.get(60000, -1), marks.get(80000, -1), marks.get(93000, -1),
        last['frames'], last['effects'], last['sets'], last['alts'], last['activations'], last.get('set_index', 0)))
