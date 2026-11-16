"""storecats.py ERR: refused stores (DBGSTORE lines) by what is stored and where."""
import re, sys, collections
c = collections.Counter(); n = 0
def cat(name, desc):
    inexact = '~' in name; d = int(re.search(r'd(\d+)', desc).group(1))
    if ' C' in desc:
        typed = ' parent' in desc
        base = re.search(r'C\d+\.(\d+)/(\d+)', desc); idx, b = int(base.group(1)), int(base.group(2))
        kind = 'argument class' if idx < b else ('typed storage class' if typed else 'storage class')
        return '%s%s rank %d' % (kind, '~' if inexact else '', d // 2)
    if 'sym@' in desc: return 'named root%s depth %d' % ('~' if inexact else '', d)
    if 'temp@' in desc: return 'temporary depth %d' % d
    return 'folded globals%s' % ('~' if inexact else '')
for line in open(sys.argv[1], errors='replace'):
    if not line.startswith('DBGSTORE'): continue
    m = re.search(r' src=(r\d+~?)\(([^)]*)\) dst=(r\d+~?)\(([^)]*)\)', line)
    if not m: continue
    n += 1; c[(cat(m.group(1), m.group(2)), cat(m.group(3), m.group(4)))] += 1
print(n, 'refused stores')
for k, v in c.most_common(14): print('%5d  %-34s -> %s' % (v, k[0], k[1]))
