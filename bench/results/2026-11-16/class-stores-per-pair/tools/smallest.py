"""smallest.py ERR SRC BLOT2_SRC_DIR [n]: the refused calls of a dbgstore2 run
(DBGSTORE lines in ERR, DBGSRC lines in SRC) ranked by the size of the calling
function and the callee together, with the refused source and destination and
the callee's own place and value: where to cut a small reproduction from."""
import re, sys
src = {}
for l in open(sys.argv[2]):
    a = l.split(); src[a[1]] = a[2]
B = sys.argv[3].rstrip('/') + '/'
top = int(sys.argv[4]) if len(sys.argv) > 4 else 8
def size_of(f, line):
    try: lines = open(B + f).read().split('\n')
    except Exception: return 10 ** 9
    end = line
    while end < len(lines) and not re.match(r'(recursive )?fn |struct |reusable|var |let ', lines[end]): end += 1
    return sum(len(x) for x in lines[line - 1:end])
rows = []
for line in open(sys.argv[1], errors='replace'):
    if not line.startswith('DBGSTORE'): continue
    m = re.search(r' at=(s\d+):(\d+):(\d+) frame=\d+ fn=(s\d+):(\d+):\d+ island=\d+ callee=\d+@(s\d+):(\d+):', line)
    if not m: continue
    f = src.get(m.group(4)); cf = src.get(m.group(6))
    rows.append((size_of(f, int(m.group(5))) + size_of(cf, int(m.group(7))), f, int(m.group(5)), int(m.group(2)), int(m.group(3)), cf, int(m.group(7)), line))
rows.sort()
seen = set(); shown = 0
for r in rows:
    key = (r[1], r[2])
    if key in seen: continue
    seen.add(key); shown += 1
    print('--- caller %s:%d call at %d:%d -> callee %s:%d (%d characters together)' % (r[1], r[2], r[3], r[4], r[5], r[6], r[0]))
    m = re.search(r' src=(\S+\([^)]*\)) dst=(\S+\([^)]*\)) calleeplaces=(\{[^}]*\}) calleevalue=(\{[^}]*\})', r[7])
    if m:
        print('    source', m.group(1), ' destination', m.group(2))
        print('    callee places', m.group(3)[:240]); print('    callee value', m.group(4)[:480])
    if shown >= top: break
