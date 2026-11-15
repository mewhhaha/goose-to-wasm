"""livestats.py SELFHOST_COPY: on top of progress.py, every 5,000 frames
counts the sets reachable from the analysis state (roots, cells, frames,
effects, summaries, items, exits, atoms) and their alternatives, against all
sets and alternatives made (diagnosis only)."""
import sys
d = sys.argv[1]
f = d + '/checker_lifetimes.goose'
s = open(f).read()
helper = r'''
fn dbg_mark(l: Lifetimes&, seen: bool[>..]&, live: i64[>..]&, set: i64) {
    if set <= 0 || set >= l.sets.len || seen[set] { return; }
    seen[set] = true; live[0] += 1; live[1] += l.sets[set].count;
    if l.sets[set].count >= 16 { live[2] += 1; live[3] += l.sets[set].count; }
}
fn dbg_mark_value(l: Lifetimes&, seen: bool[>..]&, live: i64[>..]&, v: LifeValue) {
    dbg_mark(l, seen, live, v.place); dbg_mark(l, seen, live, v.refs); dbg_mark(l, seen, live, v.contents);
    dbg_mark(l, seen, live, v.self_pools); dbg_mark(l, seen, live, v.relative_roots);
}
fn dbg_live(l: Lifetimes&) {
    var seen: bool[>..] = []; seen.resize(l.sets.len, false);
    var live: i64[>..] = [0, 0, 0, 0];
    for root in l.roots { dbg_mark(l, seen, live, root.contents); dbg_mark(l, seen, live, root.live_contents); }
    for atom in l.atoms { dbg_mark(l, seen, live, atom.set); }
    for cell in l.cells { dbg_mark(l, seen, live, cell.refs); dbg_mark(l, seen, live, cell.live_refs); dbg_mark(l, seen, live, cell.initial); dbg_mark(l, seen, live, cell.contents); }
    for frame in l.frames { dbg_mark_value(l, seen, live, frame.result); dbg_mark(l, seen, live, frame.destination); }
    var effect_live: i64[>..] = [0, 0, 0, 0];
    for effect in l.effects { dbg_mark_value(l, seen, live, effect.value); dbg_mark(l, seen, live, effect.places); }
    for summary in l.summaries { dbg_mark(l, seen, live, summary.places); dbg_mark(l, seen, live, summary.refs); dbg_mark(l, seen, live, summary.contents); dbg_mark(l, seen, live, summary.place); }
    for item in l.items { dbg_mark_value(l, seen, live, item.value); }
    for exit in l.exits { dbg_mark_value(l, seen, live, exit.value); dbg_mark(l, seen, live, exit.destination); }
    var out: u8[>..] = [];
    out.append("LIFELIVE");
    dbg_kv(out, "frames", l.frames.len); dbg_kv(out, "sets", l.sets.len); dbg_kv(out, "alts", l.alts.len);
    dbg_kv(out, "live_sets", live[0]); dbg_kv(out, "live_alts", live[1]); dbg_kv(out, "live_big_sets", live[2]); dbg_kv(out, "live_big_alts", live[3]);
    out.push('\n'); write_stderr(out);
}
'''
s = s.replace('\nfn check_lifetimes(', helper + '\nfn check_lifetimes(', 1)
old = '    if l.frames.len >= dbg_next_frames { dbg_next_frames += 1000; dbg_progress(l, "frames"); }'
assert s.count(old) == 1
s = s.replace(old, old + '\n    if l.frames.len >= dbg_next_live { dbg_next_live += 5000; dbg_live(l); }')
s = s.replace('var dbg_next_frames: i64 = 1000;', 'var dbg_next_frames: i64 = 1000;\nvar dbg_next_live: i64 = 5000;', 1)
open(f, 'w').write(s)
