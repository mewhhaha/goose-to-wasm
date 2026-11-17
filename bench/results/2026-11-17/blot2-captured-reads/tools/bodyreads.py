#!/usr/bin/env python3
"""bodyreads.py FILE [check]: life_reads answers a captured binding from body to body.

life_reads walked every node the calls below a node reach, once for each new (node, captured binding) pair.
life_body already scans what a walk reaches without following calls, once per start node, and lists the nodes its
calls go on to. This adds the captured bindings each body names, and answers the question over bodies: the same
walk, with the same exception (no call into the function that owns the binding), a body at a time.
With `check`, both answers are computed and a line is printed where they differ (for testing).
"""
import sys
p = sys.argv[1]; check = len(sys.argv) > 2 and sys.argv[2] == 'check'; t = open(p).read(); n = 0
def rep(old, new):
    global t, n
    assert t.count(old) == 1, (old[:70], t.count(old)); t = t.replace(old, new); n += 1
rep("""// owners: the functions that own the captured bindings it names, a span of
// body_owners, each once.
struct LifeBody { start: i64, captures: bool = false, globals: i64 = 0, global_count: i64 = 0, calls: i64 = 0, call_count: i64 = 0, seen: i64 = 0, owners: i64 = 0, owner_count: i64 = 0 }""",
"""// owners: the functions that own the captured bindings it names, a span of
// body_owners, each once. named: those bindings themselves, a span of
// body_captures, sorted, each once.
struct LifeBody { start: i64, captures: bool = false, globals: i64 = 0, global_count: i64 = 0, calls: i64 = 0, call_count: i64 = 0, seen: i64 = 0, owners: i64 = 0, owner_count: i64 = 0, named: i64 = 0, named_count: i64 = 0 }""")
rep("""    body_owners: i64[>..]&, contained: i64[>..]&,""", """    body_owners: i64[>..]&, body_captures: i64[>..]&, contained: i64[>..]&,""")
rep("""var body_owners: i64[>..] = [];""", """var body_owners: i64[>..] = []; var body_captures: i64[>..] = [];""")
rep("""body_owners: body_owners, """, """body_owners: body_owners, body_captures: body_captures, """)
rep("""    var body = LifeBody { start: start, globals: l.body_globals.len, calls: l.body_calls.len, owners: l.body_owners.len };""",
    """    var body = LifeBody { start: start, globals: l.body_globals.len, calls: l.body_calls.len, owners: l.body_owners.len, named: l.body_captures.len };""")
rep("""                if !listed { l.body_owners.push(owner); }
            }""", """                if !listed { l.body_owners.push(owner); }
                l.body_captures.push(n.symbol);
            }""")
rep("""    l.body_calls.resize(kept, 0);
    body.global_count = l.body_globals.len - body.globals;""", """    l.body_calls.resize(kept, 0);
    // Each captured binding once, in order.
    l.body_captures[body.named..l.body_captures.len].sort();
    var named = body.named;
    for index in body.named..l.body_captures.len {
        if index == body.named || l.body_captures[index] != l.body_captures[named - 1] { l.body_captures[named] = l.body_captures[index]; named += 1; }
    }
    l.body_captures.resize(named, 0); body.named_count = named - body.named;
    body.global_count = l.body_globals.len - body.globals;""")
rep("""fn life_reads(p: Program&, l: Lifetimes&, node: i64, symbol: i64) -> bool {
    if node < 0 { return false; }""", """// life_reads for a captured binding, from body to body. Its walk over nodes
// goes on through every call but one into the function that owns the
// binding, and asks each node whether it names the binding. What the nodes
// of one stretch say, and which calls leave it, life_body has scanned once:
// the same bodies are reached here, each asked for the binding in the sorted
// list of those it names.
fn life_reads_captured(p: Program&, l: Lifetimes&, node: i64, symbol: i64) -> bool {
    let owner = p.symbols[symbol].owner; var barred: i64 = -1; if owner >= 0 { barred = p.nodes[owner].right; }
    l.body_walks += 1; let walk = l.body_walks;
    var reached: i64[>..] = []; let first = life_body(p, l, node); l.bodies[first].seen = walk; reached.push(first);
    var at = 0;
    while at < reached.len {
        let body = l.bodies[reached[at]]; at += 1;
        var low = body.named; var high = body.named + body.named_count;
        while low < high {
            let middle = (low + high) / 2; let value = l.body_captures[middle];
            if value == symbol { return true; }
            if value < symbol { low = middle + 1; } else { high = middle; }
        }
        for call in body.calls..body.calls + body.call_count {
            let target = l.body_calls[call];
            if target == barred { continue; }
            let next = life_body(p, l, target);
            if l.bodies[next].seen != walk { l.bodies[next].seen = walk; reached.push(next); }
        }
    }
    return false;
}
fn life_reads(p: Program&, l: Lifetimes&, node: i64, symbol: i64) -> bool {
    if node < 0 { return false; }""")
if check:
    rep("""    let index = l.reads.len; l.reads.push(LifeRead { node: node, symbol: symbol, answer: answer, next: l.read_heads[bucket] }); l.read_heads[bucket] = index;
    return answer;""", """    if (p.symbols[symbol].flags & S_CAPTURE) != 0 {
        dbg_reads_checked += 1;
        if life_reads_captured(p, l, node, symbol) != answer { print("READS-DIFFER node ", node, " symbol ", symbol, " walk says ", answer); }
    }
    let index = l.reads.len; l.reads.push(LifeRead { node: node, symbol: symbol, answer: answer, next: l.read_heads[bucket] }); l.read_heads[bucket] = index;
    return answer;""")
    rep("\nfn life_reads_captured(", "\nvar dbg_reads_checked: i64 = 0;\nfn life_reads_captured(")
    rep("""    l.types_frozen = false;
    if p.diagnostics.len == 0 { life_export_provenance(p, l); life_refresh_named_results(p); }""", """    l.types_frozen = false;
    print("READS-CHECKED ", dbg_reads_checked, " of ", l.reads.len, " answers");
    if p.diagnostics.len == 0 { life_export_provenance(p, l); life_refresh_named_results(p); }""")
    rep("""            for failure in l.failures { life_error(p, l, failure.node, failure.message); }
            l.types_frozen = false;""", """            for failure in l.failures { life_error(p, l, failure.node, failure.message); }
            print("READS-CHECKED ", dbg_reads_checked, " of ", l.reads.len, " answers");
            l.types_frozen = false;""")
else:
    rep("""    l.visit += 1; var work: i64[>..] = []; life_read_child(l, work, node); var at = 0; var answer = false;
    while at < work.len {""", """    var work: i64[>..] = []; var at = 0; var answer = false;
    if (p.symbols[symbol].flags & S_CAPTURE) != 0 { answer = life_reads_captured(p, l, node, symbol); }
    else { l.visit += 1; life_read_child(l, work, node); }
    while at < work.len {""")
open(p, 'w').write(t); print('applied', n)
