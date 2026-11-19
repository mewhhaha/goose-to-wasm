fn dbg_num(out: u8[>..]&, value: i64) {
    var digits: u8[>..] = [];
    var n = value as! u64;
    if value < 0 { out.push('-'); n = (-(value + 1)) as u64 + 1; }
    loop { digits.push((n % 10) as u8 + '0'); n /= 10; if n == 0 { break; } }
    var i = digits.len;
    while i > 0 { i -= 1; out.push(digits[i]); }
}
fn dbg_kv(out: u8[>..]&, key: const u8[:], value: i64) { out.append(" "); out.append(key); out.push('='); dbg_num(out, value); }
fn dbg_mix(h: u64, v: i64) -> u64 { var x = (h ^ (v as! u64)) * 1099511628211; x ^= x >> 29; return x; }
fn dbg_set(l: Lifetimes&, h: u64, set: i64) -> u64 {
    var x = dbg_mix(h, 77);
    if set < 0 || set >= l.sets.len { return x; }
    x = dbg_mix(x, l.sets[set].count);
    var at = l.sets[set].first;
    while at >= 0 {
        let a = l.alts[at];
        x = dbg_mix(x, a.root); x = dbg_mix(x, a.from); x = dbg_mix(x, a.target_type); x = dbg_mix(x, a.bound); x = dbg_mix(x, a.component);
        var flags = 0; if a.exact { flags += 1; } if a.slotread { flags += 2; } if a.byteview { flags += 4; }
        x = dbg_mix(x, flags); at = a.next;
    }
    return x;
}
recursive fn dbg_value(l: Lifetimes&, h: u64, v: LifeValue) -> u64 {
    var x = dbg_mix(h, v.type_id); x = dbg_set(l, x, v.place); x = dbg_set(l, x, v.refs); x = dbg_set(l, x, v.contents);
    x = dbg_set(l, x, v.self_pools); x = dbg_set(l, x, v.relative_roots); var at = v.tuple;
    while at >= 0 { x = dbg_mix(x, 91); x = dbg_value(l, x, l.items[at].value); at = l.items[at].next; }
    x = dbg_mix(x, 92); x = dbg_mix(x, v.reached); x = dbg_mix(x, v.element_array);
    return x;
}
fn dbg_entry(l: Lifetimes&, h: u64, effect: const LifeEffect&) -> u64 {
    var he = dbg_mix(h, effect.kind); he = dbg_mix(he, effect.node); he = dbg_value(l, he, effect.value); he = dbg_set(l, he, effect.places);
    he = dbg_mix(he, effect.cell); he = dbg_mix(he, effect.field);
    return he;
}
fn dbg_items(l: Lifetimes&, start: u64, items: i64) -> u64 {
    var x = start; var at = items;
    while at >= 0 { x = dbg_mix(x, 91); x = dbg_value(l, x, l.items[at].value); at = l.items[at].next; }
    return dbg_mix(x, 92);
}
fn dbg_proofs(p: Program&) {
    var h: u64 = 19;
    for sym in p.symbols { var id = sym.provenance; if id < 0 { h = dbg_mix(h,id); } while id >= 0 { h = dbg_mix(h,p.nodes[id].symbol); id = p.nodes[id].next; } h = dbg_mix(h, -99); }
    var out: u8[>..] = []; out.append("LIFEFP proofs"); dbg_kv(out, "hash", (h>>1) as! i64); out.push('\n'); write_stderr(out);
}
fn dbg_fingerprint(p: Program&, l: Lifetimes&, tag: const u8[:]) {
    var h: u64 = 1469598103934665603;
    h = dbg_mix(h, l.frames.len); h = dbg_mix(h, l.revision);
     h = dbg_mix(h, l.roots.len); h = dbg_mix(h, l.cells.len);
     h = dbg_mix(h, l.recursion_epoch); h = dbg_mix(h, p.diagnostics.len); h = dbg_mix(h, l.failures.len);
    var hr: u64 = 7;
    for root in l.roots { hr = dbg_mix(hr, root.symbol); hr = dbg_mix(hr, root.node); hr = dbg_set(l, hr, root.contents); hr = dbg_set(l, hr, root.live_contents); hr = dbg_mix(hr, root.depth); hr = dbg_mix(hr, root.frame); }
    var hc: u64 = 11;
    for cell in l.cells {
        hc = dbg_set(l, hc, cell.refs); hc = dbg_set(l, hc, cell.live_refs); hc = dbg_set(l, hc, cell.initial); hc = dbg_set(l, hc, cell.contents);
        var flags = 0; if cell.live { flags += 1; } if cell.committed { flags += 2; } if cell.growshrink { flags += 4; } if cell.initialized { flags += 8; }
        hc = dbg_set(l, hc, cell.initial); hc = dbg_mix(hc, cell.symbol); hc = dbg_mix(hc, cell.frame); hc = dbg_mix(hc, flags); hc = dbg_mix(hc, cell.depth); hc = dbg_mix(hc, cell.next_frame);
    }
    var hf: u64 = 13; var he: u64 = 17; var count = 0; var checked = 0;
    for frame in l.frames {
        hf = dbg_value(l, hf, frame.result); hf = dbg_set(l, hf, frame.destination); hf = dbg_items(l, hf, frame.inputs); hf = dbg_mix(hf, frame.parent);
        hf = dbg_mix(hf, frame.function_node); hf = dbg_mix(hf, frame.selected_result); hf = dbg_mix(hf, frame.cycle); if frame.validated { hf = dbg_mix(hf, 1); } if frame.recursive_call { hf = dbg_mix(hf, 2); } hf = dbg_items(l, hf, frame.capture_inputs);
        he = dbg_mix(he, 1001);
        var at = frame.first_summary; var read: i64 = -1; if l.compact { read = frame.first_read; }
        loop {
            while read >= 0 && (at < 0 || (l.summary_reads[read].before as i64) < at) {
                let leaf = l.leaves[l.summary_reads[read].leaf as i64]; read = l.summary_reads[read].next as i64;
                var places = leaf.value.place; if life_is_ref(p, leaf.value.type_id) { places = leaf.value.refs; }
                he = dbg_mix(he, 3); he = dbg_mix(he, leaf.node); he = dbg_value(l, he, leaf.value); he = dbg_set(l, he, places);
                he = dbg_mix(he, -1); he = dbg_mix(he, -1); count += 1;
            }
            if at < 0 { break; }
            he = dbg_entry(l, he, l.effects[at]); count += 1; at = l.effects[at].next;
        }
        he = dbg_mix(he, 1002); at = frame.first_effect;
        while at >= 0 { he = dbg_entry(l, he, l.effects[at]); checked += 1; at = l.effects[at].next; }
    }
    var hx: u64 = 41;
    var bad_exits = 0;

    var owners: i64[>..] = [];
    var seen_nodes: i64[>..] = [];
    while owners.len < l.exits.len { owners.push(-1); }
    while seen_nodes.len < p.nodes.len { seen_nodes.push(-1); }
    var linked = 0;
    for frame, owner in l.frames {
        var at = frame.first_exit;
        var limit = l.exits.len;
        while at >= 0 {
            if at >= limit || owners[at] >= 0 { bad_exits += 1; break; }
            let exit = l.exits[at];
            if exit.node < 0 || exit.node >= seen_nodes.len { bad_exits += 1; break; }
            if seen_nodes[exit.node] == owner { bad_exits += 1; break; }
            seen_nodes[exit.node] = owner;
            owners[at] = owner;
            linked += 1;
            limit = at;
            at = exit.next;
        }
        if at < -1 { bad_exits += 1; }
    }
    bad_exits += l.exits.len - linked;

    for exit, index in l.exits {
        let owner = owners[index];
        if owner < 0 || owner >= l.frames.len || exit.node < 0 || exit.node >= p.nodes.len { bad_exits += 1; }
        hx = dbg_mix(hx, owner);
        hx = dbg_mix(hx, exit.node);
        hx = dbg_mix(hx, exit.selected_result);
        hx = dbg_value(l, hx, exit.value);
        hx = dbg_mix(hx, exit.value.reached);
        hx = dbg_set(l, hx, exit.destination);
    }
    var out: u8[>..] = [];
    out.append("LIFEFP "); out.append(tag);
     dbg_kv(out, "frames", l.frames.len); dbg_kv(out, "summary", count); dbg_kv(out, "checked", checked); dbg_kv(out, "rev", l.revision);
    dbg_kv(out, "h", (h >> 1) as! i64); dbg_kv(out, "roots", (hr >> 1) as! i64); dbg_kv(out, "cells", (hc >> 1) as! i64); dbg_kv(out, "frames", (hf >> 1) as! i64);
    dbg_kv(out, "effects", (he >> 1) as! i64);
    dbg_kv(out, "exits", l.exits.len); dbg_kv(out, "exit_state", (hx >> 1) as! i64);
    dbg_kv(out, "bad_exits", bad_exits);
    out.push('\n'); write_stderr(out);
}
