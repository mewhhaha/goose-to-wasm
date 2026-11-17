#!/usr/bin/env python3
"""logicalfp.py SELFHOST_COPY MODE: instrument.py's state lines, with the effects hashed as lists.

instrument.py hashes the effect and summary arrays by index: every entry's
links and each frame's first and last entry. That fixes how entries are
stored. This variant hashes what the analysis reads instead: for each frame,
in order, its summary list and its validation list, each entry by kind, node,
value, places, cell and field, sets by their alternatives; and the roots,
cells, frames, items and counters as before. A source that holds construct
reads apart (summary_reads) is walked in the order its replay uses.
MODE: fingerprint or fpframes, as instrument.py.
"""
import subprocess, sys
from pathlib import Path
d, mode = sys.argv[1], sys.argv[2]
tool = next(up / 'bench/results/2026-11-14/blot2-lifetimes/tools/instrument.py' for up in Path(__file__).resolve().parents
            if (up / 'bench/results/2026-11-14/blot2-lifetimes/tools/instrument.py').exists())
subprocess.run([sys.executable, str(tool), d, mode], check=True, stdout=subprocess.DEVNULL)
f = d + '/checker_lifetimes.goose'; s = open(f).read()
a = s.index('fn dbg_fingerprint('); b = s.index('fn dbg_progress(')
compact = 'summary_reads' in s
reads = '''
            while read >= 0 && (at < 0 || (l.summary_reads[read].before as i64) < at) {
                let leaf = l.leaves[l.summary_reads[read].leaf as i64]; read = l.summary_reads[read].next as i64;
                var places = leaf.value.place; if life_is_ref(p, leaf.value.type_id) { places = leaf.value.refs; }
                he = dbg_mix(he, 3); he = dbg_mix(he, leaf.node); he = dbg_value(l, he, leaf.value); he = dbg_set(l, he, places);
                he = dbg_mix(he, -1); he = dbg_mix(he, -1); count += 1;
            }''' if compact else ''
first = 'var read: i64 = -1; if l.compact { read = frame.first_read; }' if compact else ''
body = '''fn dbg_entry(l: Lifetimes&, h: u64, effect: const LifeEffect&) -> u64 {
    var he = dbg_mix(h, effect.kind); he = dbg_mix(he, effect.node); he = dbg_value(l, he, effect.value); he = dbg_set(l, he, effect.places);
    he = dbg_mix(he, effect.cell); he = dbg_mix(he, effect.field);
    return he;
}
fn dbg_fingerprint(p: Program&, l: Lifetimes&, tag: const u8[:]) {
    var h: u64 = 1469598103934665603;
    h = dbg_mix(h, l.frames.len); h = dbg_mix(h, l.revision);
    h = dbg_mix(h, l.pass); h = dbg_mix(h, l.roots.len); h = dbg_mix(h, l.cells.len); h = dbg_mix(h, l.items.len);
    h = dbg_mix(h, l.activations); h = dbg_mix(h, l.recursion_epoch); h = dbg_mix(h, p.diagnostics.len); h = dbg_mix(h, l.failures.len);
    var hr: u64 = 7;
    for root in l.roots { hr = dbg_set(l, hr, root.contents); hr = dbg_set(l, hr, root.live_contents); hr = dbg_mix(hr, root.depth); hr = dbg_mix(hr, root.frame); }
    var hc: u64 = 11;
    for cell in l.cells {
        hc = dbg_set(l, hc, cell.refs); hc = dbg_set(l, hc, cell.live_refs); hc = dbg_set(l, hc, cell.initial); hc = dbg_set(l, hc, cell.contents);
        var flags = 0; if cell.live { flags += 1; } if cell.committed { flags += 2; } if cell.growshrink { flags += 4; } if cell.initialized { flags += 8; }
        hc = dbg_mix(hc, flags); hc = dbg_mix(hc, cell.depth); hc = dbg_mix(hc, cell.next_frame);
    }
    var hf: u64 = 13; var he: u64 = 17; var count = 0; var checked = 0;
    for frame in l.frames {
        hf = dbg_value(l, hf, frame.result); hf = dbg_set(l, hf, frame.destination); hf = dbg_mix(hf, frame.inputs); hf = dbg_mix(hf, frame.parent);
        hf = dbg_mix(hf, frame.checked_revision); hf = dbg_mix(hf, frame.cycle); hf = dbg_mix(hf, frame.activation); hf = dbg_mix(hf, frame.capture_inputs);
        he = dbg_mix(he, 1001);
        var at = frame.first_summary; FIRST
        loop {READS
            if at < 0 { break; }
            he = dbg_entry(l, he, l.effects[at]); count += 1; at = l.effects[at].next;
        }
        he = dbg_mix(he, 1002); at = frame.first_effect;
        while at >= 0 { he = dbg_entry(l, he, l.effects[at]); checked += 1; at = l.effects[at].next; }
    }
    var hi: u64 = 29;
    for item in l.items { hi = dbg_value(l, hi, item.value); hi = dbg_mix(hi, item.next); }
    for exit in l.exits { hi = dbg_value(l, hi, exit.value); hi = dbg_set(l, hi, exit.destination); }
    var out: u8[>..] = [];
    out.append("LIFEFP "); out.append(tag);
    dbg_kv(out, "pass", l.pass); dbg_kv(out, "frames", l.frames.len); dbg_kv(out, "summary", count); dbg_kv(out, "checked", checked); dbg_kv(out, "rev", l.revision);
    dbg_kv(out, "h", (h >> 1) as! i64); dbg_kv(out, "roots", (hr >> 1) as! i64); dbg_kv(out, "cells", (hc >> 1) as! i64); dbg_kv(out, "frames", (hf >> 1) as! i64);
    dbg_kv(out, "effects", (he >> 1) as! i64); dbg_kv(out, "items", (hi >> 1) as! i64);
    out.push('\\n'); write_stderr(out);
}
'''.replace('READS', reads).replace('FIRST', first)
s = s[:a] + body + s[b:]
open(f, 'w').write(s); print('logical fingerprint,', 'reads held apart' if compact else 'entries only')
