#!/usr/bin/env python3
"""readscount.py FILE: count what life_reads does (prints a COUNT line when the lifetime pass ends or fails)."""
import sys
p = sys.argv[1]; t = open(p).read()
def rep(old, new):
    global t
    assert t.count(old) == 1, (old[:60], t.count(old)); t = t.replace(old, new)
rep("\nfn life_reads_captured(", "\nvar dbg_q: i64[8] = [0; 8];\nfn life_reads_captured(")
rep("""        let body = l.bodies[reached[at]]; at += 1;
        var low = body.named; var high = body.named + body.named_count;""", """        let body = l.bodies[reached[at]]; at += 1; dbg_q[3] += 1;
        var low = body.named; var high = body.named + body.named_count;""")
rep("""fn life_reads(p: Program&, l: Lifetimes&, node: i64, symbol: i64) -> bool {
    if node < 0 { return false; }""", """fn life_reads(p: Program&, l: Lifetimes&, node: i64, symbol: i64) -> bool {
    if node < 0 { return false; }
    dbg_q[0] += 1;""")
rep("""    if (p.symbols[symbol].flags & S_CAPTURE) != 0 { answer = life_reads_captured(p, l, node, symbol); }""",
    """    if (p.symbols[symbol].flags & S_CAPTURE) != 0 { answer = life_reads_captured(p, l, node, symbol); dbg_q[1] += 1; if answer { dbg_q[2] += 1; } }""")
line = '''print("COUNT life_reads calls ", dbg_q[0], ", answers kept ", l.reads.len, ", of captured bindings ", dbg_q[1], " (yes: ", dbg_q[2], "), bodies gone through for them ", dbg_q[3], "; bodies scanned ", l.bodies.len, ", calls listed ", l.body_calls.len, ", captured bindings listed ", l.body_captures.len, ", nodes ", p.nodes.len);'''
rep("""            for failure in l.failures { life_error(p, l, failure.node, failure.message); }
            l.types_frozen = false;""", """            for failure in l.failures { life_error(p, l, failure.node, failure.message); }
            """ + line + """
            l.types_frozen = false;""")
rep("""    l.types_frozen = false;
    if p.diagnostics.len == 0 { life_export_provenance(p, l); life_refresh_named_results(p); }""", """    l.types_frozen = false;
    """ + line + """
    if p.diagnostics.len == 0 { life_export_provenance(p, l); life_refresh_named_results(p); }""")
open(p, 'w').write(t); print('applied')
