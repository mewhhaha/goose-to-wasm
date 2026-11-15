#!/usr/bin/env python3
"""tabulate.py RUN...: seconds since discovery pass 1 began to reach each
5,000 frames, the last frame count, and the run's wall, CPU and peak RSS."""
import json, re, sys
W = '/home/jacobt/src/goose-to-wasm/.claude/worktrees/agent-a17bf72e44110d4f2/build/runs/'
rows = {}
for line in open(W + 'runs.jsonl'):
    d = json.loads(line); rows[d['label']] = d
for run in sys.argv[1:]:
    lines = [l for l in open(W + run + '.err') if l.startswith('LIFEPROG')]
    start = None; marks = []; last = None
    for l in lines:
        d = dict(re.findall(r'(\w+)=(\d+)', l))
        if start is None: start = int(d['ms'])
        last = d
        if l.split()[1] == 'frames' and int(d['frames']) % 5000 == 0:
            marks.append('%dk:%.0f' % (int(d['frames']) // 1000, (int(d['ms']) - start) / 1000))
    r = rows.get(run, {})
    print('%-12s %s | last pass %s frames %s alts %s sets %s effects %s | wall %s user %s rss %s MiB' % (
        run, ' '.join(marks), last['pass'], last['frames'], last['alts'], last['sets'], last['effects'],
        r.get('wall_s'), r.get('user_s'), r.get('max_rss_mib')))
