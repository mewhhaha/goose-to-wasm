// Arena IDs name immutable sets. Tuple slots are mutable, so hash their
// logical contents instead of using their IDs.
recursive fn trial_value(l: Lifetimes&, hash: u64, value: LifeValue) -> u64 {
    var h = dbg_mix(hash, value.type_id);
    h = dbg_mix(h, value.place);
    h = dbg_mix(h, value.refs);
    h = dbg_mix(h, value.contents);
    h = dbg_mix(h, value.self_pools);
    h = dbg_mix(h, value.relative_roots);
    h = dbg_mix(h, value.element_array);
    h = dbg_mix(h, value.reached);
    var at = value.tuple;
    while at >= 0 {
        h = trial_value(l, dbg_mix(h, 91), l.items[at].value);
        at = l.items[at].next;
    }
    return dbg_mix(h, 92);
}

fn trial_state(l: Lifetimes&, entered: i64) -> u64 {
    var h = dbg_mix(1469598103934665603, l.revision);
    h = dbg_mix(h, l.global_epoch);
    h = dbg_mix(h, l.recursion_epoch);
    for f in l.frames {
        h = trial_value(l, h, f.result);
        h = dbg_mix(h, f.parent);
        h = dbg_mix(h, f.destination);
        h = dbg_mix(h, f.context);
        h = dbg_mix(h, f.replay_version);
        h = dbg_mix(h, f.first_exit);
        h = dbg_mix(h, f.cycle);
    }
    for c in l.cells {
        h = dbg_mix(h, c.refs);
        h = dbg_mix(h, c.live_refs);
        h = dbg_mix(h, c.contents);
        h = dbg_mix(h, c.initial);
        h = dbg_mix(h, c.depth);
        var flags = 0;
        if c.initialized { flags |= 1; }
        if c.committed { flags |= 2; }
        if c.growshrink { flags |= 4; }
        // The existing function epilogue clears this activation's cells.
        if c.live && c.frame != entered { flags |= 8; }
        h = dbg_mix(h, flags);
    }
    for r in l.roots {
        h = dbg_mix(h, r.contents);
        h = dbg_mix(h, r.live_contents);
        h = dbg_mix(h, r.first_kill);
        h = dbg_mix(h, r.depth);
    }
    for exit in l.exits {
        h = dbg_mix(h, exit.node);
        h = dbg_mix(h, exit.destination);
        h = dbg_mix(h, exit.selected_result);
        h = dbg_mix(h, exit.next);
        h = trial_value(l, h, exit.value);
    }
    return h;
}
