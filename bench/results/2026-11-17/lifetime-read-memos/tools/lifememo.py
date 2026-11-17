#!/usr/bin/env python3
"""lifememo.py FILE [STEPS]: apply the construct-read memos to a checker_lifetimes.goose, steps 1..STEPS (default all).
 1 leaf memo: a read offered from this activation or one nested in it, as far up as this frame
 2 a skipped entry is passed without reading its effect
 3 a read this chain of frames was offered in an earlier pass
 4 a shrink asks only cells whose type can hold a reference
 5 a summary this chain of frames replayed with every read offered is replayed by its other entries
 6 the same memo for the recording half of a construct read in validation
 7 growths and replacements, which discovery also only records, like construct reads"""
import sys
p = sys.argv[1]; steps = int(sys.argv[2]) if len(sys.argv) > 2 else 7; t = open(p).read()
def rep(old, new, count=1):
    global t
    assert t.count(old) == count, (old[:70], t.count(old)); t = t.replace(old, new)

# ---- 1
rep("""    replayed: i32 = -1, replayed_epoch: i32 = -1,
}""", """    replayed: i32 = -1, replayed_epoch: i32 = -1,
    // leaf: for a construct read (kind 3), what life_leaf names its node and
    // value by, or -1 before its first replay and after its sets change.
    leaf: i32 = -1,
}
// A construct read by what offering it depends on: its node and its value.
// Summaries of different frames hold the same read under different entries;
// they share a leaf.
struct LifeLeaf { kind: i64, node: i64, value: LifeValue, next: i64 = -1 }""")
rep("""    summaries: LifeSummary[>..]&,
""", """    summaries: LifeSummary[>..]&,
    // Construct reads offered (life_leaf): the leaves, their hash heads, and
    // for each the activation it was last offered from with the recursion
    // epoch then, as one number, and how far up the chain that offer went
    // (life_leaf_offered).
    leaves: LifeLeaf[>..]&, leaf_heads: i64[>..]&, leaf_stamps: i64[>..]&, leaf_floors: i32[>..]&,
""")
rep("""fn life_summary_seen(l: Lifetimes&, index: i64, effect: const LifeEffect&) {""", """inline fn life_mix(a: i64, b: i64) -> i64 {
    var h: u64 = 1469598103934665603;
    for part in [a, b] { h = (h ^ (part as! u64)) * 1099511628211; h ^= h >> 29; }
    return (h >> 1) as i64;
}
inline fn life_leaf_hash(kind: i64, node: i64, v: const LifeValue&) -> i64 {
    var h: u64 = 1469598103934665603;
    for part in [kind, node, v.type_id, v.place, v.refs, v.contents, v.self_pools, v.relative_roots, v.tuple, v.element_array, v.reached] { h = (h ^ (part as! u64)) * 1099511628211; h ^= h >> 29; }
    return (h >> 1) as i64;
}
// The leaf of a check-only effect: equal kinds, nodes and values, set for set by ID.
fn life_leaf(l: Lifetimes&, kind: i64, node: i64, v: const LifeValue&) -> i64 {
    if 2 * l.leaves.len >= l.leaf_heads.len {
        var size: i64 = 64; while size <= 2 * l.leaves.len { size <<= 1; }
        l.leaf_heads.clear(); l.leaf_heads.resize(size, -1);
        for index in 0..l.leaves.len {
            let slot = life_leaf_hash(l.leaves[index].kind, l.leaves[index].node, l.leaves[index].value) & (size - 1);
            l.leaves[index].next = l.leaf_heads[slot]; l.leaf_heads[slot] = index;
        }
    }
    let slot = life_leaf_hash(kind, node, v) & (l.leaf_heads.len - 1); var at = l.leaf_heads[slot];
    while at >= 0 {
        let leaf: const LifeLeaf& = l.leaves[at];
        if leaf.kind == kind && leaf.node == node && leaf.value.type_id == v.type_id && leaf.value.place == v.place && leaf.value.refs == v.refs && leaf.value.contents == v.contents &&
           leaf.value.self_pools == v.self_pools && leaf.value.relative_roots == v.relative_roots && leaf.value.tuple == v.tuple &&
           leaf.value.element_array == v.element_array && leaf.value.reached == v.reached { return at; }
        at = leaf.next;
    }
    let index = l.leaves.len;
    l.leaves.push(LifeLeaf { kind: kind, node: node, value: v, next: l.leaf_heads[slot] }); l.leaf_heads[slot] = index; l.leaf_stamps.push(-1); l.leaf_floors.push(0);
    return index;
}
// Whether the current activation has been offered this construct read, at
// this recursion epoch, with no place in a recursive frame of the chain.
//
// An offer of a construct read only adds it to the lists of the frames up
// the chain. The same read offered from the same activation again finds each
// as it left it (LifeSummary.replayed says so of an entry; this says it of
// the read, which many entries of many summaries are). An offer from an
// activation that began after the current one, while the current one was
// running, came up the chain towards the current frame, and reached it if no
// place of the read is in a frame between the two: frames take an offer up
// to the outermost one that holds a place of it, and no further. The floor
// kept with the stamp is the chain depth of the shallowest frame that took
// it. Class-keyed frames break the chain at an island's root, which takes
// its body's effects for every caller: with them only the same activation
// counts.
inline fn life_leaf_offered(l: Lifetimes&, leaf: i64) -> bool {
    let stamp = l.leaf_stamps[leaf]; let f: const LifeFrame& = l.frames[l.frame];
    if (stamp & 4294967295) != l.recursion_epoch { return false; }
    if (stamp >> 32) == f.activation { return true; }
    return l.class_frames == 0 && (stamp >> 32) > f.activation && f.chain >= l.leaf_floors[leaf] as i64;
}
// The current activation has offered the read with these places.
fn life_leaf_stamp(l: Lifetimes&, leaf: i64, offered: const LifeEffect&) {
    let f: const LifeFrame& = l.frames[l.frame]; let reach = life_effect_far(l, offered);
    var floor: i64 = 1; if reach.far != 9223372036854775807 { floor = f.chain - reach.far + 1; }
    if floor > 2147483647 { return; }
    l.leaf_stamps[leaf] = f.activation * 4294967296 + l.recursion_epoch; l.leaf_floors[leaf] = floor as i32;
}
fn life_summary_seen(l: Lifetimes&, index: i64, effect: const LifeEffect&) {""")
rep("""            l.summaries[previous].walked = walked; l.summaries[previous].replayed = -1;""", """            l.summaries[previous].walked = walked; l.summaries[previous].replayed = -1; l.summaries[previous].leaf = -1;""")
rep("""    while at >= 0 {
        var effect = l.effects[at]; let next = effect.next; var mapped = false;""", """    while at >= 0 {
        //FAST
        var effect = l.effects[at]; var next = effect.next; var mapped = false; var leaf = -1;""")
rep("""            if s.replayed == into && s.replayed_epoch == epoch { at = next; continue; }
            l.offer_count = 0; l.offer_recursive = false;""", """            if s.replayed == into && s.replayed_epoch == epoch { at = next; continue; }
            if effect.kind == 3 {
                leaf = s.leaf as i64; if leaf < 0 { leaf = life_leaf(l, effect.kind, effect.node, effect.value); l.summaries[at].leaf = leaf as i32; }
                if life_leaf_offered(l, leaf) { at = next; continue; }
            }
            l.offer_count = 0; l.offer_recursive = false;""")
rep("""        else if effect.kind == 3 { life_construct_read(p, l, effect.node, effect.value); }""", """        else if effect.kind == 3 { life_construct_read(p, l, effect.node, effect.value, leaf); }""")
rep("""fn life_construct_read(p: Program&, l: Lifetimes&, node: i64, value: LifeValue) {
    if l.reading_place > 0 { return; }
    var effect_places = value.place; if life_is_ref(p, value.type_id) { effect_places = value.refs; }
    var effect_type = value.type_id; if effect_type >= 0 && p.types[effect_type].kind == TY_REF { effect_type = p.types[effect_type].element; }
    if value.element_array != -1 || life_cached_size_class(p, l, effect_type) == 2 { life_effect(l, LifeEffect { kind: 3, node: node, value: value, places: effect_places }); }
    if l.discovery { return; }""", """// Offers an effect that discovery only records (a construct read; with
// LIFE_ONCE_ALL a growth or a replacement too), unless the current
// activation has been offered it (life_leaf_offered). known: its leaf, where
// the caller has looked it up and found it not offered (life_replay).
fn life_offer_once(l: Lifetimes&, offer: LifeEffect, known: i64) {
    if !(/*WHEN*/l.discovery && l.frame > 0 && l.activations < 1073741824) { life_effect(l, offer); return; }
    var leaf = known; var offered = false;
    if leaf < 0 { leaf = life_leaf(l, offer.kind, offer.node, offer.value); offered = life_leaf_offered(l, leaf); }
    //CHAIN
    if !offered {
        let offers = l.offer_count; let cyclic = l.offer_recursive; l.offer_recursive = false;
        life_effect(l, offer);
        if l.offer_count > offers && !l.offer_recursive { life_leaf_stamp(l, leaf, offer); /*RECORD*/ }
        if cyclic { l.offer_recursive = true; }
    }
}
fn life_construct_read(p: Program&, l: Lifetimes&, node: i64, value: LifeValue, known: i64 = -1) {
    if l.reading_place > 0 { return; }
    var effect_places = value.place; if life_is_ref(p, value.type_id) { effect_places = value.refs; }
    var effect_type = value.type_id; if effect_type >= 0 && p.types[effect_type].kind == TY_REF { effect_type = p.types[effect_type].element; }
    if value.element_array != -1 || life_cached_size_class(p, l, effect_type) == 2 { life_offer_once(l, LifeEffect { kind: 3, node: node, value: value, places: effect_places }, known); }
    if l.discovery { return; }""")
rep("""    var summaries: LifeSummary[>..] = []; var capture_reads: i64[>..] = [];""", """    var summaries: LifeSummary[>..] = []; var capture_reads: i64[>..] = [];
    var leaves: LifeLeaf[>..] = []; var leaf_heads: i64[>..] = []; var leaf_stamps: i64[>..] = []; var leaf_floors: i32[>..] = [];""")
rep("""summaries: summaries,""", """summaries: summaries, leaves: leaves, leaf_heads: leaf_heads, leaf_stamps: leaf_stamps, leaf_floors: leaf_floors,""")

# ---- 2
if steps >= 2:
    rep("""    leaf: i32 = -1,
}""", """    // after: the effect's next in its frame's list (LifeEffect.next), so that
    // a replay passes an entry it skips without reading the effect.
    leaf: i32 = -1, after: i64 = -1,
}""")
    rep("""                if last >= 0 { l.effects[last].next = index; }""", """                if last >= 0 { l.effects[last].next = index; l.summaries[last].after = index; }""")
    rep("""        //FAST
""", """        if plain {
            let s: const LifeSummary& = l.summaries[at];
            if s.replayed == into && s.replayed_epoch == epoch {
                //COMPLETE
                at = s.after; /*OTHER*/
                continue;
            }
            if s.kind == 3 && s.leaf >= 0 && life_leaf_offered(l, s.leaf as i64) { at = s.after; continue; }
        }
""")
    rep("""    let into = l.frames[l.frame].activation as i32; let epoch = l.recursion_epoch as i32;
    while at >= 0 {""", """    let into = l.frames[l.frame].activation as i32; let epoch = l.recursion_epoch as i32;
    let plain = memo && m.count == 0;
    //OTHERS
    while at >= 0 {""")
else:
    rep("        //FAST\n", "")

# ---- 3
if steps >= 3:
    rep("""    leaves: LifeLeaf[>..]&, leaf_heads: i64[>..]&, leaf_stamps: i64[>..]&, leaf_floors: i32[>..]&,
""", """    leaves: LifeLeaf[>..]&, leaf_heads: i64[>..]&, leaf_stamps: i64[>..]&, leaf_floors: i32[>..]&,
    // Chains of frames by number (life_context: a frame and its parent's
    // chain), and the reads each chain has been offered (life_chain_offered),
    // an open-addressed set of chain, leaf and recursion epoch in one word.
    contexts: LifeContext[>..]&, context_heads: i64[>..]&, chain_offers: i64[>..]&, chain_offer_count: i64 = 0,
""")
    rep("""struct LifeLeaf { kind: i64, node: i64, value: LifeValue, next: i64 = -1 }""", """struct LifeLeaf { kind: i64, node: i64, value: LifeValue, next: i64 = -1 }
// A chain of active frames: a frame, and the chain its caller was in.
struct LifeContext { frame: i64, parent: i64, next: i64 = -1 }""")
    rep("""inline fn life_leaf_offered(l: Lifetimes&, leaf: i64) -> bool {""", """// The number of the chain of frames a frame is entered in: the same for the
// same frames in the same order, in whichever pass.
fn life_context(l: Lifetimes&, frame: i64, parent: i64) -> i64 {
    if l.class_frames > 0 || parent < 0 { return -1; }
    if 2 * l.contexts.len >= l.context_heads.len {
        var size: i64 = 64; while size <= 2 * l.contexts.len { size <<= 1; }
        l.context_heads.clear(); l.context_heads.resize(size, -1);
        for index in 0..l.contexts.len {
            let slot = life_mix(l.contexts[index].frame, l.contexts[index].parent) & (size - 1);
            l.contexts[index].next = l.context_heads[slot]; l.context_heads[slot] = index;
        }
    }
    let slot = life_mix(frame, parent) & (l.context_heads.len - 1);
    var at = l.context_heads[slot];
    while at >= 0 { if l.contexts[at].frame == frame && l.contexts[at].parent == parent { return at; } at = l.contexts[at].next; }
    let index = l.contexts.len; l.contexts.push(LifeContext { frame: frame, parent: parent, next: l.context_heads[slot] }); l.context_heads[slot] = index;
    return index;
}
// The chain of frames an offer is made in now, a number below 2^24 that
// names a read or a frame, and a recursion epoch, as one word; -1 where
// they do not fit or no chain is kept.
inline fn life_chain_key(l: Lifetimes&, item: i64, epoch: i64) -> i64 {
    let context = l.frames[l.frame].context;
    if context < 0 || context >= 16777216 || item >= 16777216 || epoch >= 32768 || l.class_frames > 0 { return -1; }
    return (context * 16777216 + item) * 32768 + epoch;
}
// Whether this chain of frames was offered the read before, with no place
// in a recursive frame: in this pass or an earlier one. The offer went as
// far up the same frames then as it would now, each took it into its
// summary, and a summary keeps what it has taken. Frames have become
// recursive since, perhaps, which matters to an offer only where one of its
// places is in such a frame (life_effect_recursive): the caller asks that
// of the offer as it is now.
fn life_chain_offered(l: Lifetimes&, key: i64) -> bool {
    if l.chain_offers.len == 0 { return false; }
    var slot = life_mix(key, 0) & (l.chain_offers.len - 1);
    loop {
        let held = l.chain_offers[slot];
        if held == key { return true; } if held < 0 { return false; }
        slot = (slot + 1) & (l.chain_offers.len - 1);
    }
    return false;
}
fn life_chain_record(l: Lifetimes&, key: i64) {
    if 2 * (l.chain_offer_count + 1) > l.chain_offers.len {
        var size: i64 = 256; while size < 4 * (l.chain_offer_count + 1) { size <<= 1; }
        var old: i64[>..] = []; old.append(l.chain_offers);
        l.chain_offers.clear(); l.chain_offers.resize(size, -1);
        for held in old {
            if held < 0 { continue; }
            var slot = life_mix(held, 0) & (size - 1);
            while l.chain_offers[slot] >= 0 { slot = (slot + 1) & (size - 1); }
            l.chain_offers[slot] = held;
        }
    }
    var slot = life_mix(key, 0) & (l.chain_offers.len - 1);
    while l.chain_offers[slot] >= 0 { if l.chain_offers[slot] == key { return; } slot = (slot + 1) & (l.chain_offers.len - 1); }
    l.chain_offers[slot] = key; l.chain_offer_count += 1;
}
inline fn life_leaf_offered(l: Lifetimes&, leaf: i64) -> bool {""")
    rep("""    //CHAIN
""", """    var chain: i64 = -1; if l.discovery { chain = life_chain_key(l, leaf, 0); }
    if !offered && chain >= 0 && life_chain_offered(l, chain) && !life_effect_far(l, offer).cyclic { life_leaf_stamp(l, leaf, offer); offered = true; }
""")
    rep("""/*RECORD*/""", """if chain >= 0 { life_chain_record(l, chain); }""")
    rep("""var leaf_floors: i32[>..] = [];""", """var leaf_floors: i32[>..] = [];
    // (Chain 0 is frame 0's, the globals'.)
    var contexts: LifeContext[>..] = [LifeContext { frame: 0, parent: -1 }]; var context_heads: i64[>..] = []; var chain_offers: i64[>..] = [];""")
    rep("""leaf_floors: leaf_floors,""", """leaf_floors: leaf_floors, contexts: contexts, context_heads: context_heads, chain_offers: chain_offers,""")
    rep("""activation: i64 = 0,""", """activation: i64 = 0, context: i64 = 0,""")
    rep("""        l.activations += 1; l.frames[target].activation = l.activations; l.frames[target].island = l.island;
    }""", """        l.activations += 1; l.frames[target].activation = l.activations; l.frames[target].island = l.island;
        l.frames[target].context = life_context(l, target, l.frames[previous_frame].context);
    }""")
    rep("""    l.activations += 1; l.frames[target].activation = l.activations; l.frames[target].map_base = sets;""", """    l.activations += 1; l.frames[target].activation = l.activations; l.frames[target].map_base = sets; l.frames[target].context = -1;""")
else:
    rep("    //CHAIN\n", ""); rep(" /*RECORD*/", "")

# ---- 4
if steps >= 4:
    rep("""    var index = life_next_live(l, -1);
    while index >= 0 {
        let cell = l.cells[index]; let visible = life_visible(l, index); index = life_next_live(l, index);
        if !visible { continue; }
        if balanced && (cell.frame != l.frame || (p.symbols[cell.symbol].flags & S_PARAMETER) != 0) { continue; }
        let value = LifeValue { type_id: p.symbols[cell.symbol].type_id, place: life_root_set(l, cell.root), refs: cell.live_refs, contents: l.roots[cell.root].live_contents };""", """    var index = life_next_live(l, -1);
    while index >= 0 {
        // A cell whose type neither is a reference nor holds one points into
        // nothing (life_points_into): most live cells are numbers.
        let cell_type = p.symbols[l.cells[index].symbol].type_id;
        if !life_is_ref(p, cell_type) && !life_holds(p, cell_type) { index = life_next_live(l, index); continue; }
        let cell = l.cells[index]; let visible = life_visible(l, index); index = life_next_live(l, index);
        if !visible { continue; }
        if balanced && (cell.frame != l.frame || (p.symbols[cell.symbol].flags & S_PARAMETER) != 0) { continue; }
        let value = LifeValue { type_id: cell_type, place: life_root_set(l, cell.root), refs: cell.live_refs, contents: l.roots[cell.root].live_contents };""")

# ---- 5
if steps >= 5:
    rep("""activation: i64 = 0, context: i64 = 0,""", """activation: i64 = 0, context: i64 = 0, first_other: i64 = -1, last_other: i64 = -1, reads_version: i64 = 0,""")
    rep("""// chain: how many frames the parent chain holds, set at each activation.""", """// first_other, last_other: the discovery summary's entries that are not
// construct reads, in order (LifeSummary.other). reads_version: how many
// times a construct read has been added to the summary or changed in it.
// chain: how many frames the parent chain holds, set at each activation.""")
    rep("""    leaf: i32 = -1, after: i64 = -1,
}""", """    // other: the next entry of the frame's summary that is not a construct read.
    leaf: i32 = -1, after: i64 = -1, other: i64 = -1,
}""")
    rep("""                if l.discovery {
                    if last < 0 { l.frames[frame].first_summary = index; }
                    l.frames[frame].last_summary = index; l.revision += 1;""", """                if l.discovery {
                    if last < 0 { l.frames[frame].first_summary = index; }
                    l.frames[frame].last_summary = index; l.revision += 1;
                    if entry.kind == 3 { l.frames[frame].reads_version += 1; }
                    else {
                        let before = l.frames[frame].last_other;
                        if before >= 0 { l.summaries[before].other = index; } else { l.frames[frame].first_other = index; }
                        l.frames[frame].last_other = index;
                    }""")
    rep("""l.summaries[previous].leaf = -1;""", """l.summaries[previous].leaf = -1;
            if effect.kind == 3 { l.frames[frame].reads_version += 1; }""")
    rep("""    contexts: LifeContext[>..]&, context_heads: i64[>..]&, chain_offers: i64[>..]&, chain_offer_count: i64 = 0,
""", """    contexts: LifeContext[>..]&, context_heads: i64[>..]&, chain_offers: i64[>..]&, chain_offer_count: i64 = 0,
    // For a chain of frames and a frame whose summary was replayed in it with
    // every construct read offered (life_replay): the summary's reads_version
    // then. Keys as in chain_offers, the frame in the read's place.
    chain_replays: i64[>..]&, chain_versions: i64[>..]&, chain_replay_count: i64 = 0,
""")
    rep("""fn life_chain_record(l: Lifetimes&, key: i64) {""", """// The reads_version a summary had when this chain of frames last replayed
// all its construct reads, or -1.
fn life_chain_replayed(l: Lifetimes&, key: i64) -> i64 {
    if l.chain_replays.len == 0 { return -1; }
    var slot = life_mix(key, 1) & (l.chain_replays.len - 1);
    loop {
        let held = l.chain_replays[slot];
        if held == key { return l.chain_versions[slot]; } if held < 0 { return -1; }
        slot = (slot + 1) & (l.chain_replays.len - 1);
    }
    return -1;
}
fn life_chain_replay(l: Lifetimes&, key: i64, version: i64) {
    if 2 * (l.chain_replay_count + 1) > l.chain_replays.len {
        var size: i64 = 256; while size < 4 * (l.chain_replay_count + 1) { size <<= 1; }
        var keys: i64[>..] = []; keys.append(l.chain_replays); var versions: i64[>..] = []; versions.append(l.chain_versions);
        l.chain_replays.clear(); l.chain_replays.resize(size, -1); l.chain_versions.clear(); l.chain_versions.resize(size, -1);
        for held, index in keys {
            if held < 0 { continue; }
            var slot = life_mix(held, 1) & (size - 1);
            while l.chain_replays[slot] >= 0 { slot = (slot + 1) & (size - 1); }
            l.chain_replays[slot] = held; l.chain_versions[slot] = versions[index];
        }
    }
    var slot = life_mix(key, 1) & (l.chain_replays.len - 1);
    while l.chain_replays[slot] >= 0 && l.chain_replays[slot] != key { slot = (slot + 1) & (l.chain_replays.len - 1); }
    if l.chain_replays[slot] < 0 { l.chain_replay_count += 1; }
    l.chain_replays[slot] = key; l.chain_versions[slot] = version;
}
fn life_chain_record(l: Lifetimes&, key: i64) {""")
    rep("""    //OTHERS
""", """    // Most of a summary is construct reads. A replay that found every one of
    // them offered, or offered the rest, says so for its chain of frames
    // (chain_replays). Until the summary gains or changes a read, a replay
    // in that chain again has only the other entries to go through, in the
    // same order: each frame of the chain took the reads then.
    let version = l.frames[frame].reads_version; var chain: i64 = -1; if plain { chain = life_chain_key(l, frame, l.recursion_epoch); }
    let others = chain >= 0 && life_chain_replayed(l, chain) == version;
    if others { at = l.frames[frame].first_other; }
    var complete = chain >= 0 && !others;
""")
    rep("""                //COMPLETE
                at = s.after; /*OTHER*/
""", """                if complete && s.kind == 3 && (s.leaf < 0 || !life_leaf_offered(l, s.leaf as i64)) { complete = false; }
                at = s.after; if others { at = s.other; }
""")
    rep("""        var effect = l.effects[at]; var next = effect.next; var mapped = false; var leaf = -1;""", """        var effect = l.effects[at]; var next = effect.next; if others { next = l.summaries[at].other; } var mapped = false; var leaf = -1;""")
    rep("""        if remembered && l.offer_count > 0 && !l.offer_recursive { l.summaries[at].replayed = into; l.summaries[at].replayed_epoch = epoch; }
        at = next;
    }""", """        if remembered && l.offer_count > 0 && !l.offer_recursive { l.summaries[at].replayed = into; l.summaries[at].replayed_epoch = epoch; }
        if complete && effect.kind == 3 && (leaf < 0 || !life_leaf_offered(l, leaf)) { complete = false; }
        at = next;
    }
    if complete && l.frames[frame].reads_version == version { life_chain_replay(l, chain, version); }""")
    rep("""var chain_offers: i64[>..] = [];""", """var chain_offers: i64[>..] = [];
    var chain_replays: i64[>..] = []; var chain_versions: i64[>..] = [];""")
    rep("""chain_offers: chain_offers,""", """chain_offers: chain_offers, chain_replays: chain_replays, chain_versions: chain_versions,""")
elif steps >= 2:
    rep("    //OTHERS\n", ""); rep("                //COMPLETE\n", ""); rep(" /*OTHER*/", "")

# ---- 6
if steps >= 6:
    rep("""    if !(/*WHEN*/l.discovery && l.frame > 0 && l.activations < 1073741824) { life_effect(l, offer); return; }""", """    // In validation this is the recording of the effect in the frames'
    // effect lists, which have it from then on; what it is checked against
    // is looked at every time, by the caller.
    if !((l.discovery || l.class_frames == 0) && l.frame > 0 && l.activations < 1073741824) { life_effect(l, offer); return; }""")
else:
    rep("/*WHEN*/", "")
# ---- 7: growths and replacements, which discovery also only records
if steps >= 7:
    rep("""fn life_replace(p: Program&, l: Lifetimes&, node: i64, receiver: LifeValue) {
    life_effect(l, LifeEffect { kind: 8, node: node, value: receiver, places: receiver.place });""", """fn life_replace(p: Program&, l: Lifetimes&, node: i64, receiver: LifeValue, known: i64 = -1) {
    life_offer_once(l, LifeEffect { kind: 8, node: node, value: receiver, places: receiver.place }, known);""")
    rep("""fn life_grow(p: Program&, l: Lifetimes&, node: i64, receiver: LifeValue) {
    life_effect(l, LifeEffect { kind: 2, node: node, value: receiver, places: receiver.place });""", """fn life_grow(p: Program&, l: Lifetimes&, node: i64, receiver: LifeValue, known: i64 = -1) {
    life_offer_once(l, LifeEffect { kind: 2, node: node, value: receiver, places: receiver.place }, known);""")
    rep("""            if effect.kind == 3 {
                leaf = s.leaf as i64;""", """            if effect.kind == 3 || effect.kind == 2 || effect.kind == 8 {
                leaf = s.leaf as i64;""")
    rep("""            if s.kind == 3 && s.leaf >= 0 && life_leaf_offered(l, s.leaf as i64) { at = s.after; continue; }""", """            if (s.kind == 3 || s.kind == 2 || s.kind == 8) && s.leaf >= 0 && life_leaf_offered(l, s.leaf as i64) { at = s.after; if others && s.kind != 3 { at = s.other; } continue; }""")
    rep("""        else if effect.kind == 2 { life_grow(p, l, effect.node, effect.value); }""", """        else if effect.kind == 2 { life_grow(p, l, effect.node, effect.value, leaf); }""")
    rep("""        else if effect.kind == 8 { life_replace(p, l, effect.node, effect.value); }""", """        else if effect.kind == 8 { life_replace(p, l, effect.node, effect.value, leaf); }""")
    rep("""l.summaries[previous].leaf = -1;""", """l.summaries[previous].leaf = -1;""")
open(p, 'w').write(t); print('applied', steps)
