"""joinstats.py SELFHOST_COPY: on top of progress.py, attributes new
alternatives made by life_join to its call sites (diagnosis only). Each
`life_join(` call inside the named functions is wrapped."""
import re, sys
d = sys.argv[1]
f = d + '/checker_lifetimes.goose'
s = open(f).read()
names = []
helper = '''
fn dbg_join(l: Lifetimes&, a: i64, b: i64, site: i64) -> i64 {
    let before = l.alts.len; let result = life_join(l, a, b);
    dbg_jalts[site] += l.alts.len - before; dbg_jcalls[site] += 1;
    return result;
}
'''
def wrap_calls(fname):
    global s
    m = re.search(r'^(recursive )?fn ' + fname + r'\(', s, re.M)
    assert m, fname
    start = m.start(); end = s.index('\n}\n', start) + 3
    body = s[start:end]
    k = len(names); names.append(fname)
    n = body.count('life_join(l, ')
    assert n > 0, fname
    body = body.replace('life_join(l, ', 'dbg_join(l, %d, ' % k)
    s = s[:start] + body + s[end:]
for fn in ['life_effect_merge', 'life_add_contents', 'life_store', 'life_merge', 'life_function', 'life_readback', 'life_eval_body', 'life_build_add', 'life_export_provenance']:
    wrap_calls(fn)
# dbg_join(l, k, a, b) -> reorder args
s = re.sub(r'dbg_join\(l, (\d+), ', lambda m: 'dbg_join_at(l, %s, ' % m.group(1), s)
helper += '''fn dbg_join_at(l: Lifetimes&, site: i64, a: i64, b: i64) -> i64 { return dbg_join(l, a, b, site); }
'''
s = s.replace('\nfn check_lifetimes(', helper + '\nfn check_lifetimes(', 1)
n = len(names)
decl = 'var dbg_jalts: i64[%d] = [0; %d];\nvar dbg_jcalls: i64[%d] = [0; %d];\n' % (n, n, n, n)
s = s.replace('var dbg_next_frames: i64 = 1000;', 'var dbg_next_frames: i64 = 1000;\n' + decl, 1)
kv = ''.join('    dbg_kv(out, "j_%s", dbg_jalts[%d]); dbg_kv(out, "jc_%s", dbg_jcalls[%d]);\n' % (nm, i, nm, i) for i, nm in enumerate(names))
s = s.replace("    out.push('\\n'); write_stderr(out);\n}", kv + "    out.push('\\n'); write_stderr(out);\n}", 1)
open(f, 'w').write(s)
