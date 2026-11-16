"""origins.py ERR SRC [n]: refused stores (DBGSTORE lines of a dbgstore2 +
dbgorigin build) counted by the statement that first made the store."""
import re, sys, collections
src = {}
for l in open(sys.argv[2]):
    a = l.split(); src[a[1]] = a[2]
top = int(sys.argv[3]) if len(sys.argv) > 3 else 25
c = collections.Counter(); files = collections.Counter(); total = 0
for line in open(sys.argv[1], errors='replace'):
    if not line.startswith('DBGSTORE'): continue
    total += 1
    m = re.search(r' store@(\S+)', line)
    o = m.group(1) if m else '(none)'
    mm = re.match(r'(s\d+):(\d+):(\d+)', o)
    if mm: o = '%s:%s:%s' % (src.get(mm.group(1), mm.group(1)), mm.group(2), mm.group(3)); files[src.get(mm.group(1), mm.group(1))] += 1
    c[o] += 1
print(total, 'refused stores,', len(c), 'distinct origins')
acc = 0
for k, v in c.most_common(top): acc += v; print('%5d %5.1f%%  %s' % (v, 100.0 * acc / max(total, 1), k))
print('by file:'); 
for k, v in files.most_common(8): print('%5d  %s' % (v, k))
