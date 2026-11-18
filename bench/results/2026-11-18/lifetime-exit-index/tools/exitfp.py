"""Extend the logical fingerprint with ordered exit identities and index checks."""
import sys
from pathlib import Path

path = Path(sys.argv[1]) / "checker_lifetimes.goose"
source = path.read_text()
old = "    for exit in l.exits { hi = dbg_value(l, hi, exit.value); hi = dbg_set(l, hi, exit.destination); }"
assert source.count(old) == 1
candidate = "    first_exit: i64 = -1," in source
verify_index = """
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
"""
new = """
    var hx: u64 = 41;
    var bad_exits = 0;
""" + (verify_index if candidate else "") + """
    for exit, index in l.exits {
        let owner = OWNER;
        if owner < 0 || owner >= l.frames.len || exit.node < 0 || exit.node >= p.nodes.len { bad_exits += 1; }
        hx = dbg_mix(hx, owner);
        hx = dbg_mix(hx, exit.node);
        hx = dbg_mix(hx, exit.selected_result);
        hx = dbg_value(l, hx, exit.value);
        hx = dbg_mix(hx, exit.value.reached);
        hx = dbg_set(l, hx, exit.destination);
    }
""".replace("OWNER", "owners[index]" if candidate else "exit.frame")
source = source.replace(old, new.rstrip())
marker = '    dbg_kv(out, "effects", (he >> 1) as! i64); dbg_kv(out, "items", (hi >> 1) as! i64);'
assert source.count(marker) == 1
source = source.replace(marker, marker + """
    dbg_kv(out, "exits", l.exits.len); dbg_kv(out, "exit_state", (hx >> 1) as! i64);
    dbg_kv(out, "bad_exits", bad_exits);""")
path.write_text(source)
