"""dbgforeign2.py DIR (after progress.py and setsites.py): report the first sets
made that name a class root of an island other than the one being evaluated."""
import sys
f = sys.argv[1] + '/checker_lifetimes.goose'
s = open(f).read()
def rep(old, new, count=1):
    global s
    assert s.count(old) == count, (old[:90], s.count(old))
    s = s.replace(old, new)
s = s.replace('import model;', 'import model;\nvar dbg_quiet: i64 = 0; var dbg_made: i64 = 0; var dbg_local: i64 = 0; var dbg_quiet2: i64 = 0; var dbg_where2: i64 = 0;', 1)
rep('''    while dbg_site_alts.len < 32 { dbg_site_alts.push(0); dbg_site_sets.push(0); }''', '''    while dbg_site_alts.len < 32 { dbg_site_alts.push(0); dbg_site_sets.push(0); }
    if dbg_quiet == 0 && l.island > 0 && dbg_made < 10 {
        for item in start..l.scratch.len {
            let fr = l.roots[l.scratch[item].root].frame;
            if fr > 0 && l.frames[fr].island != l.island && dbg_local < 8 && dbg_quiet2 == 0 {
                dbg_local += 1; var o: u8[>..] = []; o.append("DBGLOCAL site="); dbg_num(o, dbg_site); o.append(" frame="); dbg_num(o, l.frame); o.append(" island="); dbg_num(o, l.island);
                o.append(" rootframe="); dbg_num(o, fr); o.append(" rootisland="); dbg_num(o, l.frames[fr].island); o.append(" rootactive="); if l.frames[fr].active { o.append("1"); } else { o.append("0"); }
                o.append(" rootframeclass="); dbg_num(o, l.frames[fr].classes); o.append(" count="); dbg_num(o, count); o.append(" where="); dbg_num(o, dbg_where2); o.push(10 as u8); write_stderr(o); break;
            }
            let cf = l.roots[l.scratch[item].root].class_frame;
            if cf >= 0 && cf != l.island && false {
                dbg_made += 1; var o: u8[>..] = []; o.append("DBGMADE site="); dbg_num(o, dbg_site); o.append(" frame="); dbg_num(o, l.frame); o.append(" island="); dbg_num(o, l.island);
                o.append(" alt=C"); dbg_num(o, cf); o.append("."); dbg_num(o, l.roots[l.scratch[item].root].class_index); o.append(" active="); if l.frames[cf].active { o.append("1"); } else { o.append("0"); }
                o.append(" count="); dbg_num(o, count); o.append(" altfn_line="); dbg_num(o, 0 - 1); o.append(" lframe_class="); dbg_num(o, l.frames[l.frame].classes); o.append(" islandparent="); dbg_num(o, l.frames[l.island].parent); o.append(" cf_parent="); dbg_num(o, l.frames[cf].parent); o.append(" pass="); dbg_num(o, l.pass); o.push(10 as u8); write_stderr(o); break;
            }
        }
    }''')
# quiet while a frame is being made or a call classified or mapped
rep('''    let target = l.frames.len; let newest = l.function_frames[function_node]; let key = l.class_keys.len;''', '''    dbg_quiet += 1;
    let target = l.frames.len; let newest = l.function_frames[function_node]; let key = l.class_keys.len;''')
rep('''        let bucket = c.hash & (l.class_heads.len - 1); l.frames[target].next_class = l.class_heads[bucket]; l.class_heads[bucket] = target;
    }
    return target;''', '''        let bucket = c.hash & (l.class_heads.len - 1); l.frames[target].next_class = l.class_heads[bucket]; l.class_heads[bucket] = target;
    }
    dbg_quiet -= 1;
    return target;''')
# quiet while a call's own roots are read for a question (caller terms on purpose)
rep('''    let island = l.island; l.island = l.frames[l.frames[frame].parent].island;''', '''    dbg_quiet2 += 1; let island = l.island; l.island = l.frames[l.frames[frame].parent].island;''', 2)
rep('''    l.island = island;
    life_assume_close(l, at, answer);''', '''    l.island = island; dbg_quiet2 -= 1;
    life_assume_close(l, at, answer);''', 2)
rep('''    life_replay(p, l, target, l.discovery || back_edge, m, call);''', '''    dbg_where2 = 1; life_replay(p, l, target, l.discovery || back_edge, m, call); dbg_where2 = 2;''')
open(f, 'w').write(s)
