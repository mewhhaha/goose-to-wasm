import sys, subprocess, bisect, collections
exe, out = sys.argv[1], sys.argv[2]
top = int(sys.argv[3]) if len(sys.argv) > 3 else 45
import json, os, re
names = {}
if os.path.exists(exe + '.stats.json'):
    for f in json.load(open(exe + '.stats.json'))['function_names']: names['g_fn%d' % f['id']] = f['name']
syms = []
for line in subprocess.run(['nm', '-n', '--defined-only', exe], capture_output=True, text=True).stdout.splitlines():
    parts = line.split()
    if len(parts) == 3 and parts[1] in 'tTwW': syms.append((int(parts[0], 16), parts[2]))
addrs = [a for a, _ in syms]
c = collections.Counter(); n = 0; pairs = collections.Counter(); triples = collections.Counter()
def name(v):
    if v == 0xffffffffffffffff: return '<outside>'
    i = bisect.bisect_right(addrs, v) - 1
    nm = syms[i][1] if i >= 0 else '<?>'
    return names.get(nm, nm)
import struct
data = open(out, 'rb').read()
for (v, c1, c2) in struct.iter_unpack('<QQQ', data[:len(data) // 24 * 24]):
    n += 1
    a, b, d = name(v), name(c1), name(c2)
    c[a] += 1; pairs[(a, b)] += 1; triples[(a, b, d)] += 1
print('samples', n)
life = sum(v for k, v in c.items() if 'life_' in k)
print('life_* %.1f%%' % (100.0 * life / max(n, 1)))
for k, v in c.most_common(top): print('%6.2f%% %8d %s' % (100.0 * v / n, v, k))

print('--- self <- caller')
for (a, b), v in pairs.most_common(top): print('%6.2f%% %8d %s <- %s' % (100.0 * v / n, v, a, b))
print('--- self <- caller <- caller2')
for (a, b, d), v in triples.most_common(top): print('%6.2f%% %8d %s <- %s <- %s' % (100.0 * v / n, v, a, b, d))
