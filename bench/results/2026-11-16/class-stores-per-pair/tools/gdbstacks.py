"""gdbstacks.py GDB_OUT STATS_JSON [depth]: aggregate sampled backtraces (bt
blocks from a gdb batch run breaking on a hook) by their Goose call chain."""
import sys, json, re, collections
out, stats = sys.argv[1], sys.argv[2]
depth = int(sys.argv[3]) if len(sys.argv) > 3 else 5
names = {'g_fn%d' % f['id']: f['name'] for f in json.load(open(stats))['function_names']}
stacks = []; cur = None
for line in open(out, errors='replace'):
    m = re.match(r'#(\d+)\s+(?:0x[0-9a-f]+ in )?(\S+) \(', line)
    if not m: continue
    if m.group(1) == '0': cur = []; stacks.append(cur)
    if cur is not None: cur.append(names.get(m.group(2), m.group(2)))
skip = {'dbg_newset', 'life_list_set', 'life_build_end', 'life_join', 'life_join_into', 'life_scratch_set', 'life_single'}
print('samples', len(stacks))
for d in (1, 2, depth):
    c = collections.Counter()
    for s in stacks:
        t = [f for f in s if f not in skip]
        # collapse direct recursion
        u = []
        for f in t:
            if not u or u[-1] != f: u.append(f)
        c[' <- '.join(u[:d])] += 1
    print('--- depth', d)
    for k, v in c.most_common(22 if d < depth else 30): print('%6.2f%% %6d %s' % (100.0 * v / max(len(stacks), 1), v, k))
