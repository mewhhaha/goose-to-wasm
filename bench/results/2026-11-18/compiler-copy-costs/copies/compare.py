"""Compare complete counts from two compiler revisions using the same fixed workload and args."""
import argparse
from collections import Counter
import json
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('before', type=Path)
p.add_argument('after', type=Path)
a = p.parse_args()

def copy_totals(rows):
    return {m: sum(r[m] for r in rows if r['kind'] == 'copy') for m in ('calls','bytes')}

def functions(rows):
    totals = Counter()
    for r in rows:
        if r['kind'] == 'copy':
            totals[r['function']] += r['bytes']
    return totals

def pairing(before, after):
    return dict(before=before, after=after, difference=after-before)

report = {}
for mode in ('check','emit'):
    before, after = [json.loads((d/(mode+'.json')).read_text()) for d in (a.before,a.after)]
    for key in ('workload','workload_archive_sha256','wasmtime','engine','exit_code','expected_emission','arguments'):
        assert before[key] == after[key], key
    left, right = before['active'], after['active']
    b, c = functions(left), functions(right)
    changed = sorted(b.keys() | c.keys(), key=lambda f:(-abs(c[f]-b[f]),f))
    delta = {}
    for field in ('bytes','calls'):
        delta[field] = pairing(copy_totals(left)[field],copy_totals(right)[field])
    report[mode] = {
        'revisions':[before['compiler'],after['compiler']],
        'workload':before['workload'], 'arguments':before['arguments'], 'expected_emission':after['expected_emission'],
        'memory_copy': delta,
        'lifetime_bytes':pairing(sum(x for f,x in b.items() if f.startswith('life_')),
                                 sum(x for f,x in c.items() if f.startswith('life_'))),
        'largest_changes':[{'function':f, **pairing(b[f],c[f])} for f in changed[:14]],
        'largest_remaining':[{'function':f, **pairing(b[f],size)} for f,size in c.most_common(12)],
        'replay_bytes':pairing(b['life_replay'],c['life_replay']),
    }
print(json.dumps(report,indent=2))
