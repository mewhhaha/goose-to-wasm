"""xcheck.py DIR: cross-check the indexed and summarized lookups of the lifetime
pass against the scans they replace. Edits DIR/checker_lifetimes.goose so that
- after the indexed frame searches of life_function, the linear searches run
  again and must name the same frame;
- life_reads_captures and life_reads_global also make the node-by-node walk
  and must agree with the body summaries.
A difference prints a LIFEXCHECK ... differ line on stderr; the last line
counts the checks made (searches, capture walks, global walks).
"""
import sys

f = sys.argv[1] + '/checker_lifetimes.goose'
s = open(f).read()


def rep(old, new):
    global s
    assert s.count(old) == 1, (old[:90], s.count(old))
    s = s.replace(old, new)


assert 'import os;' not in s
s = s.replace('import model;', 'import model;\nimport os;\nvar dbg_checks: i64 = 0; var dbg_captures: i64 = 0; var dbg_globals: i64 = 0;', 1)

rep("""    life_frames_reserve(l);
    let key = life_inputs_key(""", """    let dbg_before = target;
    life_frames_reserve(l);
    let key = life_inputs_key(""")

push = """    if target < 0 {
        target = l.frames.len;
        l.frames.push(LifeFrame { function_node: function_node, parent: l.frame, lexical: lexical, call: call, inputs: arguments, base: base, destination: destination, selected_result: selected_result, next_function: newest, home: l.frame, inputs_hash: key.hash, inputs_kinds: key.kinds, mixed_kinds: mixed });"""
rep(push, """    if dbg_before < 0 {
        var dbg_expected = -1; var dbg_i = l.function_frames[function_node];
        while dbg_i >= 0 {
            let frame = l.frames[dbg_i];
            if frame.lexical == lexical && frame.selected_result == selected_result && (!receiver_sensitive || life_equal(l, frame.destination, destination)) && life_arguments_equal(p, l, frame.inputs, arguments) { dbg_expected = dbg_i; break; }
            dbg_i = frame.next_function;
        }
        if dbg_expected < 0 && l.discovery {
            dbg_i = l.function_frames[function_node];
            while dbg_i >= 0 {
                let frame = l.frames[dbg_i];
                if !frame.active && frame.lexical == lexical && frame.home == l.frame && frame.call == call && frame.selected_result == selected_result && (!receiver_sensitive || life_equal(l, frame.destination, destination)) { dbg_expected = dbg_i; break; }
                dbg_i = frame.next_function;
            }
        }
        if dbg_expected != target { write_stderr("LIFEXCHECK frame searches differ\\n"); }
        dbg_checks += 1;
    }
""" + push)

walk = """        l.visit += 1; var dbg_work: i64[>..] = []; life_read_child(l, dbg_work, p.nodes[function_node].right); var dbg_at = 0;
        while dbg_at < dbg_work.len {
            let current = dbg_work[dbg_at]; dbg_at += 1; let n: const Node& = p.nodes[current];
            FOUND
            life_read_child(l, dbg_work, n.next);
            if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE || n.kind == N_IMPORT { continue; }
            for child in [n.first, n.left, n.right, n.third] { life_read_child(l, dbg_work, child); }
            if n.kind == N_CALL && n.symbol >= 0 && (p.symbols[n.symbol].flags & S_BUILTIN) == 0 {
                let callee = p.symbols[n.symbol].node;
                if callee >= 0 { life_read_child(l, dbg_work, p.nodes[callee].right); }
            }
        }
"""
captures = """    var reached: i64[>..] = [];
    let answer = life_body_walk(p, l, p.nodes[function_node].right, reached, true);
"""
rep(captures, captures + """    {
        var dbg_answer = false;
""" + walk.replace('FOUND', 'if n.kind == N_NAME && n.symbol >= 0 && n.symbol < p.symbols.len && (p.symbols[n.symbol].flags & S_CAPTURE) != 0 { dbg_answer = true; break; }') + """        if dbg_answer != answer { write_stderr("LIFEXCHECK capture reads differ\\n"); }
        dbg_captures += 1;
    }
""")
globals_ = """        l.global_read_list.resize(kept, 0);
        l.global_read_spans[function_node] = LifeSpan { first: first, count: kept - first };"""
rep(globals_, globals_ + """
        {
        var dbg_list: i64[>..] = [];
""" + walk.replace('FOUND', 'if n.kind == N_NAME && n.symbol >= 0 && n.symbol < p.symbols.len && (p.symbols[n.symbol].flags & S_GLOBAL) != 0 { dbg_list.push(n.symbol); }') + """        dbg_list.sort();
        var dbg_kept = 0;
        for index in 0..dbg_list.len { if index == 0 || dbg_list[index] != dbg_list[dbg_kept - 1] { dbg_list[dbg_kept] = dbg_list[index]; dbg_kept += 1; } }
        var dbg_same = dbg_kept == kept - first;
        if dbg_same { for index in 0..dbg_kept { if dbg_list[index] != l.global_read_list[first + index] { dbg_same = false; } } }
        if !dbg_same { write_stderr("LIFEXCHECK global reads differ\\n"); }
        dbg_globals += 1;
        }""")

rep("""    l.types_frozen = false;
    if p.diagnostics.len == 0 { life_export_provenance(p, l); life_refresh_named_results(p); }""", """    l.types_frozen = false;
    var dbg_out: u8[>..] = []; dbg_out.append("LIFEXCHECK checked");
    for dbg_count in [dbg_checks, dbg_captures, dbg_globals] {
        dbg_out.push(' '); var dbg_n = dbg_count; var dbg_d: u8[>..] = [];
        loop { dbg_d.push((dbg_n % 10) as u8 + '0'); dbg_n /= 10; if dbg_n == 0 { break; } }
        var dbg_k = dbg_d.len; while dbg_k > 0 { dbg_k -= 1; dbg_out.push(dbg_d[dbg_k]); }
    }
    dbg_out.push('\\n'); write_stderr(dbg_out);
    if p.diagnostics.len == 0 { life_export_provenance(p, l); life_refresh_named_results(p); }""")
open(f, 'w').write(s)
