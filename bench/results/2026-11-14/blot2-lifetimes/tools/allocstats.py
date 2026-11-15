"""allocstats.py SELFHOST_COPY: on top of progress.py, attributes new
alternatives (l.alts growth) to the function whose final build or join made
them (diagnosis only)."""
import re, sys
d = sys.argv[1]
f = d + '/checker_lifetimes.goose'
s = open(f).read()

names = []
def wrap(fname, pattern):
    global s
    m = re.search(r'^(recursive )?fn ' + fname + r'\(', s, re.M)
    assert m, fname
    start = m.start(); end = s.index('\n}\n', start) + 3
    body = s[start:end]
    n = body.count(pattern)
    assert n >= 1, (fname, pattern)
    expr = pattern[len('return '):-1]
    k = len(names); names.append(fname)
    body = body.replace(pattern, '{ let dbg_before = l.alts.len; let dbg_result = %s; dbg_alts[%d] += l.alts.len - dbg_before; dbg_calls[%d] += 1; return dbg_result; }' % (expr, k, k))
    s = s[:start] + body + s[end:]

for fname, pat in [('life_readback', 'return life_build_end(l, result);'),
                   ('life_contents', 'return life_build_end(l, result);'),
                   ('life_live_contents', 'return life_build_end(l, result);'),
                   ('life_interior', 'return life_build_end(l, out);'),
                   ('life_component', 'return life_build_end(l, out);'),
                   ('life_stored_roots', 'return life_build_end(l, contents);'),
                   ('life_parameter_roots', 'return life_build_end(l, result);'),
                   ('life_clear_reads', 'return life_build_end(l, result);'),
                   ('life_class_candidates', 'return life_build_end(l, result);')]:
    wrap(fname, pat)
# life_join: big and small paths
m = re.search(r'^fn life_join\(', s, re.M); start = m.start(); end = s.index('\n}\n', start) + 3
body = s[start:end]
k = len(names); names.append('life_join')
body = body.replace('fn life_join(l: Lifetimes&, a: i64, b: i64) -> i64 {', 'fn life_join(l: Lifetimes&, a: i64, b: i64) -> i64 { let dbg_before = l.alts.len; let dbg_result = life_join_inner(l, a, b); dbg_alts[%d] += l.alts.len - dbg_before; dbg_calls[%d] += 1; return dbg_result; }\nfn life_join_inner(l: Lifetimes&, a: i64, b: i64) -> i64 {' % (k, k), 1)
s = s[:start] + body + s[end:]
# life_bound
k = len(names); names.append('life_bound')
s = s.replace('    let result = life_build_end(l, build);\n    l.sets[sources].bound_depth = depth;', '    let dbg_before = l.alts.len; let result = life_build_end(l, build); dbg_alts[%d] += l.alts.len - dbg_before; dbg_calls[%d] += 1;\n    l.sets[sources].bound_depth = depth;' % (k, k), 1)
k = len(names); names.append('life_load_mutable')
s = s.replace('        out.contents = life_build_end(l, mutable);', '        { let dbg_before = l.alts.len; out.contents = life_build_end(l, mutable); dbg_alts[%d] += l.alts.len - dbg_before; dbg_calls[%d] += 1; }' % (k, k), 1)
k = len(names); names.append('life_load_slot')
s = s.replace('            out.contents = life_build_end(l, contents);', '            { let dbg_before = l.alts.len; out.contents = life_build_end(l, contents); dbg_alts[%d] += l.alts.len - dbg_before; dbg_calls[%d] += 1; }' % (k, k), 1)
k = len(names); names.append('life_single')
s = s.replace('    let set = life_new_set(l);\n    life_insert(l, set, wanted);', '    let set = life_new_set(l); dbg_alts[%d] += 1; dbg_calls[%d] += 1;\n    life_insert(l, set, wanted);' % (k, k), 1)
n = len(names)
decl = 'var dbg_alts: i64[%d] = [0; %d];\nvar dbg_calls: i64[%d] = [0; %d];\n' % (n, n, n, n)
s = s.replace('var dbg_next_frames: i64 = 1000;', 'var dbg_next_frames: i64 = 1000;\n' + decl, 1)
kv = ''.join('    dbg_kv(out, "a_%s", dbg_alts[%d]); dbg_kv(out, "c_%s", dbg_calls[%d]);\n' % (nm, i, nm, i) for i, nm in enumerate(names))
s = s.replace("    out.push('\\n'); write_stderr(out);\n}", kv + "    out.push('\\n'); write_stderr(out);\n}", 1)
open(f, 'w').write(s)
