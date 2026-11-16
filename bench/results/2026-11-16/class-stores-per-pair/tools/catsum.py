"""catsum.py CATEGORIES.json: counts by how the diagnostics differ, with
sources whose diagnostics are the same line for line counted apart."""
import json, sys
g = json.load(open(sys.argv[1]))
same = 0; out = {}
for k, rows in g.items():
    n = 0
    for name, b, c in rows:
        if b == c: same += 1
        else: n += 1
    out[k] = n
print('identical diagnostics', same)
for k, v in out.items(): print(k, v)
print('differing diagnostics', sum(out.values()))
