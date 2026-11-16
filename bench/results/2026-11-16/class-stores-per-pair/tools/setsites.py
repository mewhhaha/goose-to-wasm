"""setsites.py DIR: on top of progress.py, count the alternatives of new sets by
which function was making them (a site number set at entry, restored at exit
is too invasive: the last site entered is charged)."""
import sys, re
f = sys.argv[1] + '/checker_lifetimes.goose'
s = open(f).read()
sites = ['life_map_set', 'life_held', 'life_fold', 'life_readback', 'life_candidates', 'life_contents', 'life_classify_set', 'life_key_set', 'life_bound', 'life_load', 'life_strip', 'life_overlay', 'life_keep_outside', 'life_component', 'life_interior', 'life_parameter_roots', 'life_stored_roots', 'life_live_contents', 'life_class_candidates', 'life_clear_reads', 'life_held_own', 'life_class_any_make', 'life_class_stores', 'life_typed_held', 'life_typed_set', 'life_class_deep', 'life_class_set', 'life_held_into', 'life_class_check', 'life_class_narrow', 'life_lasting', 'life_elsewhere', 'life_class_remap']
s = s.replace('import model;', 'import model;\nvar dbg_site: i64 = 0; var dbg_site_alts: i64[>..] = []; var dbg_site_sets: i64[>..] = [];', 1)
for i, name in enumerate(sites, 1):
    pat = re.compile(r'((?:recursive |inline )?fn ' + name + r'\([^\n]*\{\n)')
    m = pat.search(s); assert m, name
    s = s[:m.end()] + '    dbg_site = %d;\n' % i + s[m.end():]
old = """    var next = -1;
    for item in start..l.scratch.len { var entry = l.scratch[item]; entry.next = next as i32; next = l.alts.len; l.alts.push(entry); }"""
assert s.count(old) == 1
s = s.replace(old, """    while dbg_site_alts.len < 64 { dbg_site_alts.push(0); dbg_site_sets.push(0); }
    dbg_site_alts[dbg_site] += count; dbg_site_sets[dbg_site] += 1;
""" + old)
old = """    out.push('\\n'); write_stderr(out);
}
"""
i = s.index('fn dbg_progress(')
j = s.index(old, i)
add = '    out.append(" sites:");\n    for alts, site in dbg_site_alts { if alts > 0 { out.push(\' \'); dbg_num(out, site); out.push(\'=\'); dbg_num(out, alts); out.push(\'/\'); dbg_num(out, dbg_site_sets[site]); } }\n'
s = s[:j] + add + s[j:]
joins = [
 ('            let places = life_join(l, old_places, effect.places);', 50),
 ('    out.refs = life_join(l, a.refs, b.refs); out.place = life_join(l, a.place, b.place);', 52),
 ('    let next = life_join(l, l.roots[root].contents, kept);', 49),
]
for pat, n in joins:
    assert s.count(pat) == 1, pat
    ind = pat[:len(pat) - len(pat.lstrip())]
    s = s.replace(pat, ind + 'dbg_site = %d; ' % n + pat.lstrip())
open(f, 'w').write(s)
print('49=add_contents 50=effect_merge 52=merge')
print('sites', ' '.join('%d=%s' % (i, n) for i, n in enumerate(sites, 1)))
