"""bigsets.py DIR (after progress.py and setsites.py): describe the first large sets made."""
import sys
f = sys.argv[1] + '/checker_lifetimes.goose'
s = open(f).read()
def rep(old, new, count=1):
    global s
    assert s.count(old) == count, (old[:90], s.count(old))
    s = s.replace(old, new)
s = s.replace('import model;', 'import model;\nvar dbg_big: i64 = 0; var dbg_bigs: i64 = 0; var dbg_big_alts: i64 = 0;', 1)
rep('''    while dbg_site_alts.len < 64 { dbg_site_alts.push(0); dbg_site_sets.push(0); }''', '''    while dbg_site_alts.len < 64 { dbg_site_alts.push(0); dbg_site_sets.push(0); }
    if count >= 30 { dbg_bigs += 1; dbg_big_alts += count; }
    if count >= 30 && l.class_frames > 0 && dbg_big < 14 && dbg_bigs % 25000 == 1 {
        dbg_big += 1; var dbg_first = -1; var dbg_first_sym = -1; var dbg_first_temp = 0; var own = 0; var foreign_active = 0; var foreign_dead = 0; var own_locals = 0; var statics = 0; var named = 0; var classes = 0; var locals = 0; var temps = 0; var others = 0; var inexact = 0; var bounds = 0; var targets = 0; var slots = 0; var froms = 0;
        for item in start..l.scratch.len {
            let a = l.scratch[item]; let r = l.roots[a.root];
            if !a.exact { inexact += 1; } if a.bound != 0 { bounds += 1; } if a.target_type >= 0 { targets += 1; } if a.slotread { slots += 1; } if a.from >= 0 { froms += 1; }
            if a.root == 0 { statics += 1; } else if r.class_frame >= 0 { classes += 1; if r.class_frame == l.island { own += 1; } else if l.frames[r.class_frame].active { foreign_active += 1; } else { foreign_dead += 1; } } else if r.symbol >= 0 && r.frame == 0 { named += 1; } else if r.temporary { temps += 1; } else if r.frame > 0 { locals += 1; if l.frames[r.frame].island == l.island { own_locals += 1; } else if dbg_first < 0 { dbg_first = r.frame; dbg_first_sym = r.symbol; dbg_first_temp = 0; if r.temporary { dbg_first_temp = 1; } } } else { others += 1; }
        }
        var o: u8[>..] = []; o.append("DBGBIG site="); dbg_num(o, dbg_site); o.append(" count="); dbg_num(o, count); o.append(" frame0named="); dbg_num(o, named); o.append(" static="); dbg_num(o, statics); o.append(" class="); dbg_num(o, classes);
        o.append(" local="); dbg_num(o, locals); o.append(" temp="); dbg_num(o, temps); o.append(" other="); dbg_num(o, others); o.append(" inexact="); dbg_num(o, inexact); o.append(" bound="); dbg_num(o, bounds); o.append(" target="); dbg_num(o, targets); o.append(" slot="); dbg_num(o, slots); o.append(" from="); dbg_num(o, froms);
        o.append(" classown="); dbg_num(o, own); o.append(" foreign_active="); dbg_num(o, foreign_active); o.append(" foreign_dead="); dbg_num(o, foreign_dead); o.append(" own_locals="); dbg_num(o, own_locals); o.append(" island="); dbg_num(o, l.island); o.append(" frame="); dbg_num(o, l.frame); if dbg_first >= 0 { o.append(" first[frame="); dbg_num(o, dbg_first); o.append(" island="); dbg_num(o, l.frames[dbg_first].island); o.append(" active="); if l.frames[dbg_first].active { o.append("1"); } else { o.append("0"); } o.append(" classes="); dbg_num(o, l.frames[dbg_first].classes); o.append(" sym="); dbg_num(o, dbg_first_sym); o.append(" temp="); dbg_num(o, dbg_first_temp); o.append(" checked="); dbg_num(o, l.frames[dbg_first].checked_revision); o.append("] islandparent="); dbg_num(o, l.frames[l.island].parent); o.append(" parentclasses="); dbg_num(o, l.frames[l.frames[l.island].parent].classes); } o.append(" bigs="); dbg_num(o, dbg_bigs); o.push(10 as u8); write_stderr(o);
    }''')
open(f, 'w').write(s)
