"""Summarize the active guest counters, keeping fill and scalar traffic separate."""
import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('results', type=Path)
a = p.parse_args()
summary = {}
for mode in ('check', 'emit'):
    rec = json.loads((a.results/(mode+'.json')).read_text())
    rows = rec['active']
    def totals(part):
        return {label: sum(r[label] for r in part) for label in ('calls', 'bytes')}
    def grouped(part, key):
        groups = defaultdict(list)
        for row in part:
            groups[row[key]].append(row)
        return sorted(({key: k, **totals(v)} for k,v in groups.items()), key=lambda d:-d['bytes'])
    copies = [r for r in rows if r['kind'] == 'copy']
    life = [r for r in copies if r['function'].startswith('life_')]
    replay = [r for r in life if r['function'] == 'life_replay']
    relevant = {}
    for name, size in [('life_held_into', 210), ('life_depth', 565), ('life_class_candidates', 93)]:
        relevant[name] = [{'offset': hex(r['offset']), 'width': r['size'], 'calls':r['calls'], 'bytes':r['bytes']}
                          for r in rows if r['function'] == name and r['size'] == size and r['kind'] == 'copy']
    summary[mode] = {
        'memory_operations': grouped(rows, 'kind'),
        'copy_widths': grouped(copies, 'size'),
        'copy_top_functions': grouped(copies, 'function')[:20],
        'lifetime_copy': totals(life),
        'replay_copy': totals(replay),
        'replay_by_width': grouped(replay, 'size'),
        'replay_sites': sorted(({'offset':hex(r['offset']), 'width':r['size'], 'calls':r['calls'], 'bytes':r['bytes']}
                                for r in replay), key=lambda r:-r['bytes']),
        'selected_record_sites': relevant,
        'expected_emission': rec['expected_emission'],
    }
assert summary['check']['replay_sites'] == summary['emit']['replay_sites']
assert summary['check']['selected_record_sites'] == summary['emit']['selected_record_sites']
print(json.dumps(summary, indent=2))
