"""viacats.py ERR: DBGVIA lines counted by the kind of callee alternative that
maps to the refused source, and to the destination."""
import re, sys, collections

def cat(name, desc):
    inexact = '~' in name
    d = int(re.search(r'd(\d+)', desc).group(1))
    if ' C' in desc:
        typed = ' parent' in desc
        base = re.search(r'C\d+\.(\d+)/(\d+)', desc)
        idx, b = int(base.group(1)), int(base.group(2))
        if idx < b: kind = 'argument class'
        elif typed: kind = 'typed storage class'
        elif idx < 2 * b: kind = 'storage class 1'
        else: kind = 'storage class 2'
        self = ' (read out of itself)' if re.search(r' from\d+', desc) else ''
        return '%s%s%s' % (kind, '~' if inexact else '', self)
    if 'sym@' in desc: return 'named root%s depth %d' % ('~' if inexact else '', d)
    return 'static or folded globals%s' % ('~' if inexact else '')

v = collections.Counter(); pl = collections.Counter(); both = collections.Counter(); n = 0
for line in open(sys.argv[1], errors='replace'):
    if not line.startswith('DBGVIA'): continue
    n += 1
    vs = sorted(set(cat(a, b) for a, b in re.findall(r' value:(r\d+~?)\(([^)]*)\)', line)))
    ps = sorted(set(cat(a, b) for a, b in re.findall(r' place:(r\d+~?)\(([^)]*)\)', line)))
    kv = ' + '.join(vs) or '(none)'; kp = ' + '.join(ps) or '(none)'
    v[kv] += 1; pl[kp] += 1; both[(kv, kp)] += 1
tt = collections.Counter()
for line in open(sys.argv[1], errors='replace'):
    if not line.startswith('DBGVIA'): continue
    for a, b in re.findall(r' value:(r\d+~?)\(([^)]*)\)', line):
        tt[(cat(a, b), 'target type known' if ' tt' in b else 'target type unknown')] += 1
print(n, 'refused stores')
print('callee source alternatives by whether their target type is known:')
for k, c in tt.most_common(12): print('%5d  %s, %s' % (c, k[0], k[1]))
print('callee alternative that maps to the refused source:')
for k, c in v.most_common(10): print('%5d  %s' % (c, k))
print('callee alternative that maps to the destination:')
for k, c in pl.most_common(10): print('%5d  %s' % (c, k))
print('pairs:')
for k, c in both.most_common(10): print('%5d  %s  ->  %s' % (c, k[0], k[1]))
