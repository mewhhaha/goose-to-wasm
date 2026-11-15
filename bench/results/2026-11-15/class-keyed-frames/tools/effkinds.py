"""effkinds.py DIR (after progress.py): at each progress line every 3000 frames,
count summary effects by kind and by whose they are: an island's root frame, a
frame inside an island, or a frame outside any."""
import sys
f = sys.argv[1] + '/checker_lifetimes.goose'
s = open(f).read()
old = "    out.push('\\n'); write_stderr(out);\n}\n"
i = s.index('fn dbg_progress('); j = s.index(old, i)
add = '''    if l.frames.len % 3000 < 100 && l.frames.len > 4000 {
        var counts: i64[>..] = []; counts.resize(30, 0); var globals_only = 0;
        for e in l.effects {
            if e.owner < 0 || e.kind < 0 || e.kind > 9 { continue; }
            var who = 2; if l.frames[e.owner].classes >= 0 { who = 0; } else if l.frames[e.owner].island > 0 { who = 1; }
            counts[who * 10 + e.kind] += 1;
            if e.kind == 4 && e.places != 0 { let r = l.roots[l.alts[l.sets[e.places].first].root]; if r.frame <= 0 && r.class_frame < 0 { globals_only += 1; } }
        }
        out.append(" EFF root:"); for k in 0..10 { out.push(' '); dbg_num(out, counts[k]); }
        out.append(" inside:"); for k in 0..10 { out.push(' '); dbg_num(out, counts[10 + k]); }
        out.append(" outside:"); for k in 0..10 { out.push(' '); dbg_num(out, counts[20 + k]); }
        out.append(" store_into_global="); dbg_num(out, globals_only);
    }
'''
s = s[:j] + add + s[j:]
open(f, 'w').write(s)
