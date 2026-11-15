"""coverage.py SELFHOST_COPY [dump]: after progress.py, also report on each
LIFEPROG line how many distinct functions have a frame (functions), the
deepest chain of frames an evaluation started under (depth_max) and the
current depth. With `dump`, at 30,000 and 90,000 frames also print LIFEDUMP
lines: frames per function in buckets, the 50 functions with the most frames,
and for the first twelve the arguments of six of their frames."""
import sys
d = sys.argv[1]; dump = len(sys.argv) > 2 and sys.argv[2] == 'dump'
f = d + '/checker_lifetimes.goose'
lines = open(f).read().split('\n')
out = []
for line in lines:
    if line.startswith('var dbg_next_frames: i64 = 1000;'):
        out.append(line); out.append('var dbg_functions: i64 = 0;\nvar dbg_depth_max: i64 = 0;\nvar dbg_evals: i64 = 0;'); continue
    if 'l.frames.push(LifeFrame { function_node: function_node' in line:
        out.append('        if l.function_frames[function_node] < 0 { dbg_functions += 1; }')
    if 'l.frames[target].active = true;' in line and 'temporary_base' in line:
        out.append('        dbg_evals += 1;\n        var dbg_d = 0; var dbg_f = previous_frame; while dbg_f > 0 { dbg_d += 1; dbg_f = l.frames[dbg_f].parent; }\n        if dbg_d > dbg_depth_max { dbg_depth_max = dbg_d; }')
    if line.strip().startswith('dbg_kv(out, "reads", l.reads.len);'):
        out.append('    dbg_kv(out, "functions", dbg_functions); dbg_kv(out, "depth_max", dbg_depth_max); dbg_kv(out, "evals", dbg_evals);\n    var dbg_cur = 0; var dbg_c = l.frame; while dbg_c > 0 { dbg_cur += 1; dbg_c = l.frames[dbg_c].parent; }\n    dbg_kv(out, "depth", dbg_cur);')
    if dump and 'dbg_progress(l, "frames");' in line:
        line = line.replace('dbg_progress(l, "frames");', 'dbg_progress(l, "frames"); if l.frames.len == 30000 || l.frames.len == 90000 { dbg_dump(p, l); }')
    out.append(line)
s = '\n'.join(out)
assert s.count('dbg_functions += 1') == 1 and s.count('dbg_evals += 1') == 1 and s.count('dbg_kv(out, "functions"') == 1
DUMP = r'''
fn dbg_fn_name(p: Program&, out: u8[>..]&, function_node: i64) {
    if function_node < 0 { out.append("<top>"); return; }
    let symbol = p.nodes[function_node].symbol;
    if symbol >= 0 && p.symbols[symbol].name_token >= 0 { out.append(token_text(p, p.symbols[symbol].name_token)); }
    else { out.append("<fn@"); dbg_num(out, function_node); out.push('>'); }
}
fn dbg_root(p: Program&, l: Lifetimes&, out: u8[>..]&, alt: LifeAlt) {
    let root = l.roots[alt.root];
    out.push('r'); dbg_num(out, alt.root); out.push(':');
    if alt.root == 0 { out.append("static"); }
    else if root.symbol >= 0 {
        if (p.symbols[root.symbol].flags & S_GLOBAL) != 0 { out.append("G."); } else { out.append("L."); }
        if p.symbols[root.symbol].name_token >= 0 { out.append(token_text(p, p.symbols[root.symbol].name_token)); }
    } else if root.temporary { out.append("tmp@"); dbg_num(out, root.node); }
    else { out.append("other"); }
    out.append("/f"); dbg_num(out, root.frame); out.append("/d"); dbg_num(out, root.depth);
    if !alt.exact { out.push('~'); } if alt.slotread { out.push('s'); } if alt.bound != 0 { out.append("/b"); dbg_num(out, alt.bound); }
}
fn dbg_set_text(p: Program&, l: Lifetimes&, out: u8[>..]&, set: i64) {
    out.push('{'); var at = l.sets[set].first; var shown = 0;
    while at >= 0 && shown < 6 { if shown > 0 { out.push(' '); } dbg_root(p, l, out, l.alts[at]); at = l.alts[at].next; shown += 1; }
    if at >= 0 { out.append(" ...+"); dbg_num(out, l.sets[set].count - shown); }
    out.push('}');
}
fn dbg_dump(p: Program&, l: Lifetimes&) {
    var counts: i64[>..] = []; counts.resize(p.nodes.len, 0);
    for frame, index in l.frames { if index > 0 && frame.function_node >= 0 { counts[frame.function_node] += 1; } }
    var buckets: i64[>..] = []; buckets.resize(8, 0); var bucket_frames: i64[>..] = []; bucket_frames.resize(8, 0);
    var order: i64[>..] = [];
    for count, node in counts {
        if count == 0 { continue; }
        var b = 0; var limit = 1; while count > limit && b < 7 { b += 1; limit *= 4; }
        buckets[b] += 1; bucket_frames[b] += count; order.push(count * 100000000 + node);
    }
    order.sort();
    var out: u8[>..] = [];
    out.append("LIFEDUMP frames="); dbg_num(out, l.frames.len); out.append(" functions="); dbg_num(out, order.len); out.push('\n');
    var limit = 1;
    for b in 0..8 { out.append("LIFEDUMP bucket <="); dbg_num(out, limit); out.append(" functions="); dbg_num(out, buckets[b]); out.append(" frames="); dbg_num(out, bucket_frames[b]); out.push('\n'); limit *= 4; }
    var rank = 0; var i = order.len;
    while i > 0 && rank < 50 {
        i -= 1; rank += 1; let node = order[i] % 100000000; let count = order[i] / 100000000;
        out.append("LIFEDUMP top "); dbg_num(out, count); out.push(' '); dbg_fn_name(p, out, node);
        var params = 0; var formal = p.nodes[node].first; while formal >= 0 { params += 1; formal = p.nodes[formal].next; }
        out.append(" params="); dbg_num(out, params); out.push('\n');
        if rank <= 12 {
            var shown = 0; var fi = l.function_frames[node];
            while fi >= 0 && shown < 6 {
                let frame = l.frames[fi]; shown += 1;
                out.append("LIFEDUMP   frame "); dbg_num(out, fi); out.append(" home="); dbg_num(out, frame.home); out.push('(');
                dbg_fn_name(p, out, l.frames[frame.home].function_node); out.append(") call="); dbg_num(out, frame.call); out.append(" lexical="); dbg_num(out, frame.lexical); out.append(" base="); dbg_num(out, frame.base);
                var item = frame.inputs; var ai = 0;
                while item >= 0 {
                    let value = l.items[item].value;
                    out.append(" | a"); dbg_num(out, ai); out.push(':');
                    if life_is_ref(p, value.type_id) { out.append("ref"); dbg_set_text(p, l, out, value.refs); }
                    else if life_holds(p, value.type_id) { out.append("holds"); dbg_set_text(p, l, out, value.contents); }
                    else { out.push('-'); }
                    item = l.items[item].next; ai += 1;
                }
                out.push('\n'); fi = frame.next_function;
            }
        }
    }
    write_stderr(out);
}
'''
if dump:
    assert s.count('dbg_dump(p, l);') == 1
    s = s.replace('\nfn check_lifetimes(', DUMP + '\nfn check_lifetimes(', 1)
open(f, 'w').write(s)
