"""framestat.py DIR: make DIR/checker_lifetimes.goose print, when the lifetime
pass ends, how many frames it made, for how many functions, and the most for
one function: a LIFESTAT line on stderr."""
import sys
f = sys.argv[1] + '/checker_lifetimes.goose'
s = open(f).read()
def rep(old, new, count=1):
    global s
    assert s.count(old) == count, (old[:90], s.count(old))
    s = s.replace(old, new)
assert 'import os;' not in s
s = s.replace('import model;', '''import model;
import os;
fn dbg_stat(l: Lifetimes&) {
    var most = 0; var functions = 0;
    for head in l.function_frames {
        var count = 0; var at = head; while at >= 0 { count += 1; at = l.frames[at].next_function; }
        if count > 0 { functions += 1; } if count > most { most = count; }
    }
    var out: u8[>..] = []; out.append("LIFESTAT");
    for value in [l.frames.len - 1, functions, most] {
        out.push(' '); var n = value; var d: u8[>..] = [];
        loop { d.push((n % 10) as u8 + '0'); n /= 10; if n == 0 { break; } }
        var k = d.len; while k > 0 { k -= 1; out.push(d[k]); }
    }
    out.push('\\n'); write_stderr(out);
}''', 1)
rep("""            l.types_frozen = false;
            return;""", """            l.types_frozen = false; dbg_stat(l);
            return;""")
rep("""    l.types_frozen = false;
    if p.diagnostics.len == 0 { life_export_provenance(p, l); life_refresh_named_results(p); }""", """    l.types_frozen = false; dbg_stat(l);
    if p.diagnostics.len == 0 { life_export_provenance(p, l); life_refresh_named_results(p); }""")
open(f, 'w').write(s)
