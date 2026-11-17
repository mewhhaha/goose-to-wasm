#!/usr/bin/env python3
"""compactreads.py FILE: hold a frame's construct reads compactly while no frame is class-keyed.

A discovery summary's construct reads (kind 3) are 94% of its entries, each a
170-byte effect and a 128-byte summary record. This keeps them as 32-byte
entries naming a leaf (LifeReadEntry), found through a small table per frame,
and turns them into ordinary entries when the first class-keyed frame is made.
The logical list of every frame (entries, order, contents) is unchanged.
"""
import sys
p = sys.argv[1]; t = open(p).read(); n = 0
def rep(old, new):
    global t, n
    assert t.count(old) == 1, (old[:70], t.count(old)); t = t.replace(old, new); n += 1

# ---- records
rep("""struct LifeLeaf { kind: i64, node: i64, value: LifeValue, next: i64 = -1 }""", """struct LifeLeaf { kind: i64, node: i64, value: LifeValue, next: i64 = -1 }
// A construct read in a frame's discovery summary while no frame is
// class-keyed (Lifetimes.compact): what a summary entry of kind 3 says, in a
// tenth of the room. key: its node and value type, which a merge matches
// (life_read_key). leaf: its node and value, the sets joined of every offer
// it took. seen: the last offer it took (LifeSummary.places and the rest);
// walked: as LifeSummary.walked. sent: the chain of frames
// (LifeFrame.context) in which its frame offered `seen` and the offer went
// all the way up with no place in a recursive frame, or -1 (life_read_offer).
// next: the frame's next read. before: the frame's last entry of another kind
// when this one was added, -1 for none: the frame's list is its other
// entries (first_summary) with each read after that one, and a replay goes
// through both in that order.
struct LifeReadEntry { key: i64, leaf: i32, seen: i32, walked: i32 = -1, sent: i32 = -1, next: i32 = -1, before: i32 = -1 }""")
rep("""reads_version: i64 = 0, chain: i64 = 0,""", """reads_version: i64 = 0, first_read: i64 = -1, last_read: i64 = -1, read_table: i64 = 0, read_cap: i64 = 0, read_count: i64 = 0, chain: i64 = 0,""")
rep("""    leaves: LifeLeaf[>..]&, leaf_heads: i64[>..]&, leaf_stamps: i64[>..]&, leaf_floors: i32[>..]&,""", """    leaves: LifeLeaf[>..]&, leaf_heads: i64[>..]&, leaf_stamps: i64[>..]&, leaf_floors: i32[>..]&,
    // The construct reads of the frames' summaries while `compact`, and the
    // frames' tables of them (LifeFrame.read_table, read_cap of read_slots:
    // an index into summary_reads or -1, by life_read_hash of the key).
    summary_reads: LifeReadEntry[>..]&, read_slots: i32[>..]&,""")
rep("""    island: i64 = 0, hold_floor: i64 = 0, future_floor: i64 = 0, class_frames: i64 = 0,""", """    // compact: summaries hold their construct reads in summary_reads; until
    // the first class-keyed frame (life_reads_materialize).
    compact: bool = true,
    island: i64 = 0, hold_floor: i64 = 0, future_floor: i64 = 0, class_frames: i64 = 0,""")
rep("""var leaf_floors: i32[>..] = [];""", """var leaf_floors: i32[>..] = [];
    var summary_reads: LifeReadEntry[>..] = []; var read_slots: i32[>..] = [];""")
rep("""leaf_floors: leaf_floors,""", """leaf_floors: leaf_floors, summary_reads: summary_reads, read_slots: read_slots,""")

# ---- the table, the merge and the offer
rep("""fn life_effect(l: Lifetimes&, effect: LifeEffect) {""", """inline fn life_read_key(node: i64, type_id: i64) -> i64 { return node * 4294967296 + type_id + 1; }
inline fn life_read_hash(key: i64) -> i64 {
    var h: u64 = (key as! u64) * 1099511628211; h ^= h >> 29; h *= 1099511628211; h ^= h >> 31;
    return (h >> 1) as! i64;
}
// A frame's construct read of this key, or -1.
fn life_read_find(l: Lifetimes&, frame: i64, key: i64) -> i64 {
    let f: const LifeFrame& = l.frames[frame];
    if f.read_cap == 0 { return -1; }
    var slot = life_read_hash(key) & (f.read_cap - 1);
    loop {
        let index = l.read_slots[f.read_table + slot] as i64;
        if index < 0 { return -1; }
        if l.summary_reads[index].key == key { return index; }
        slot = (slot + 1) & (f.read_cap - 1);
    }
    return -1;
}
// Adds a construct read at the end of a frame's reads. Its table is kept at
// most half full; a larger one is made at the end of read_slots.
fn life_read_add(l: Lifetimes&, frame: i64, entry: LifeReadEntry) {
    if 2 * (l.frames[frame].read_count + 1) > l.frames[frame].read_cap {
        let old = l.frames[frame].read_table; let cap = l.frames[frame].read_cap;
        var size: i64 = 8; if cap > 0 { size = 2 * cap; }
        let table = l.read_slots.len; l.read_slots.resize(table + size, -1);
        for item in 0..cap {
            let index = l.read_slots[old + item];
            if index < 0 { continue; }
            var slot = life_read_hash(l.summary_reads[index as i64].key) & (size - 1);
            while l.read_slots[table + slot] >= 0 { slot = (slot + 1) & (size - 1); }
            l.read_slots[table + slot] = index;
        }
        l.frames[frame].read_table = table; l.frames[frame].read_cap = size;
    }
    let index = l.summary_reads.len; l.summary_reads.push(entry);
    let last = l.frames[frame].last_read;
    if last >= 0 { l.summary_reads[last].next = index as i32; } else { l.frames[frame].first_read = index; }
    l.frames[frame].last_read = index; l.frames[frame].read_count += 1;
    let cap = l.frames[frame].read_cap; let table = l.frames[frame].read_table;
    var slot = life_read_hash(entry.key) & (cap - 1);
    while l.read_slots[table + slot] >= 0 { slot = (slot + 1) & (cap - 1); }
    l.read_slots[table + slot] = index as i32;
}
// life_effect_merge for a construct read held by leaf: 0 if the frame had
// no read of the key and now has this one, 1 if it had one, 2 if it had one
// that already sent this offer's sets up the chain in this activation. An
// entry that last took other sets takes these joined in, and its leaf is then
// the one of the joined value.
fn life_read_merge(l: Lifetimes&, frame: i64, leaf: i64, key: i64, outside: bool) -> i64 {
    let walked = life_walked(l, frame, outside);
    let index = life_read_find(l, frame, key);
    if index < 0 {
        life_read_add(l, frame, LifeReadEntry { key: key, leaf: leaf as i32, seen: leaf as i32, walked: walked, before: l.frames[frame].last_summary as i32 });
        l.revision += 1; l.frames[frame].reads_version += 1;
        return 0;
    }
    let seen = l.summary_reads[index].seen as i64; var same = seen == leaf;
    if !same {
        let a = l.leaves[seen].value; let b = l.leaves[leaf].value;
        same = a.place == b.place && a.refs == b.refs && a.contents == b.contents ||
            life_same_list(l, a.place, b.place) && life_same_list(l, a.refs, b.refs) && life_same_list(l, a.contents, b.contents);
        if same { l.summary_reads[index].seen = leaf as i32; l.summary_reads[index].sent = -1; }
    }
    if same {
        if walked >= 0 && (l.summary_reads[index].walked == (walked | 1) || l.summary_reads[index].walked == walked) { return 2; }
        l.summary_reads[index].walked = walked;
        return 1;
    }
    let held = l.summary_reads[index].leaf as i64; var value = l.leaves[held].value; let offered = l.leaves[leaf].value;
    let refs = life_join(l, value.refs, offered.refs); let contents = life_join(l, value.contents, offered.contents);
    let place = life_join(l, value.place, offered.place);
    if !life_equal(l, refs, value.refs) || !life_equal(l, contents, value.contents) || !life_equal(l, place, value.place) { l.revision += 1; }
    value.refs = refs; value.contents = contents; value.place = place;
    let joined = life_leaf(l, 3, l.leaves[held].node, value);
    l.summary_reads[index].leaf = joined as i32; l.summary_reads[index].seen = leaf as i32; l.summary_reads[index].walked = walked; l.summary_reads[index].sent = -1;
    l.frames[frame].reads_version += 1;
    return 1;
}
// life_effect for a construct read in discovery while summaries hold their
// reads by leaf: the same walk up the chain, each frame that takes the
// effect as external taking it in its reads.
fn life_read_offer(l: Lifetimes&, leaf: i64, effect: const LifeEffect&) {
    l.offer_count += 1;
    let reach = life_effect_far(l, effect); let far = reach.far; let outside = far == 9223372036854775807;
    if reach.cyclic { l.offer_recursive = true; }
    let key = life_read_key(effect.node, effect.value.type_id);
    // The same frames in the same order are the same chain in every pass
    // and activation. An offer the offering frame's own entry last took, and
    // sent up this chain with no place in a recursive frame, went as far up
    // then as it would now; each frame took it, and keeps what it has taken.
    // Frames may have become recursive since: that matters only to an offer
    // with a place in one, which is asked of this offer as it is now.
    let context = l.frames[l.frame].context; var own: i64 = -1;
    let chained = !reach.cyclic && far > 0 && context >= 0 && context < 2147483647 && !l.frames[l.frame].validated;
    if chained {
        own = life_read_find(l, l.frame, key);
        if own >= 0 && l.summary_reads[own].seen as i64 == leaf && l.summary_reads[own].sent as i64 == context { return; }
    }
    var frame = l.frame; var depth = 0; let chain = l.frames[l.frame].chain; var settled = false;
    while frame > 0 {
        if settled && far > depth { frame = reach.home; depth = far; }
        if far <= depth {
            frame = life_nearest_recursive(l, frame);
            if frame <= 0 { break; }
            depth = chain - l.frames[frame].chain;
        }
        if !l.frames[frame].validated {
            var external = far > depth;
            if !external && l.frames[frame].recursive_call { external = life_effect_recursive(l, effect, frame); }
            if external {
                let merged = life_read_merge(l, frame, leaf, key, outside);
                if merged == 2 { if outside { break; } settled = true; }
            }
        }
        frame = l.frames[frame].parent; depth += 1;
    }
    if chained {
        if own < 0 { own = life_read_find(l, l.frame, key); }
        if own >= 0 && l.summary_reads[own].seen as i64 == leaf { l.summary_reads[own].sent = context as i32; }
    }
}
fn life_effect(l: Lifetimes&, effect: LifeEffect) {""")
rep("""    if !((l.discovery || l.class_frames == 0) && l.frame > 0 && l.activations < 1073741824) { life_effect(l, offer); return; }
    var leaf = known; var offered = false;
    if leaf < 0 { leaf = life_leaf(l, offer.kind, offer.node, offer.value); offered = life_leaf_offered(l, leaf); }
    var chain: i64 = -1; if l.discovery { chain = life_chain_key(l, leaf, 0); }
    if !offered && chain >= 0 && life_chain_offered(l, chain) && !life_effect_far(l, offer).cyclic { life_leaf_stamp(l, leaf, offer); offered = true; }
    if !offered {
        let offers = l.offer_count; let cyclic = l.offer_recursive; l.offer_recursive = false;
        life_effect(l, offer);
        if l.offer_count > offers && !l.offer_recursive { life_leaf_stamp(l, leaf, offer); if chain >= 0 { life_chain_record(l, chain); } }
        if cyclic { l.offer_recursive = true; }
    }""", """    // stamps: the activation's stamp on the leaf can say the offer was made.
    // compact: the summaries take the read by its leaf (life_read_offer).
    let stamps = (l.discovery || l.class_frames == 0) && l.frame > 0 && l.activations < 1073741824;
    let compact = l.compact && l.discovery && l.frame > 0;
    if !stamps && !compact { life_effect(l, offer); return; }
    var leaf = known; var offered = false;
    if leaf < 0 { leaf = life_leaf(l, offer.kind, offer.node, offer.value); offered = stamps && life_leaf_offered(l, leaf); }
    // (The reads held by leaf have the chain's memo of an offer in the
    // offering frame's entry: LifeReadEntry.sent.)
    var chain: i64 = -1; if l.discovery && stamps && !compact { chain = life_chain_key(l, leaf, 0); }
    if !offered && chain >= 0 && life_chain_offered(l, chain) && !life_effect_far(l, offer).cyclic { life_leaf_stamp(l, leaf, offer); offered = true; }
    if !offered {
        let offers = l.offer_count; let cyclic = l.offer_recursive; l.offer_recursive = false;
        if compact { life_read_offer(l, leaf, offer); } else { life_effect(l, offer); }
        if stamps && l.offer_count > offers && !l.offer_recursive { life_leaf_stamp(l, leaf, offer); if chain >= 0 { life_chain_record(l, chain); } }
        if cyclic { l.offer_recursive = true; }
    }""")

# ---- the replay
rep("""    if others { at = l.frames[frame].first_other; }
    var complete = chain >= 0 && !others;
    while at >= 0 {
        if plain {""", """    if others { at = l.frames[frame].first_other; }
    var complete = chain >= 0 && !others;
    // While summaries hold their construct reads by leaf, the list is the
    // other entries with each read after the one it names
    // (LifeReadEntry.before): entries are numbered as they are added, so a
    // read comes before the first other entry with a larger number.
    var read: i64 = -1; if summary && l.compact && !others { read = l.frames[frame].first_read; }
    var passed: i64 = -1; var open = false;
    loop {
        while read >= 0 && (at < 0 || (l.summary_reads[read].before as i64) < at) {
            let leaf = l.summary_reads[read].leaf as i64; read = l.summary_reads[read].next as i64;
            if (memo || quick) && life_leaf_offered(l, leaf) { continue; }
            if memo { l.offer_count = 0; l.offer_recursive = false; }
            var known: i64 = -1; if memo || quick { known = leaf; }
            let node = l.leaves[leaf].node; let value = l.leaves[leaf].value;
            life_construct_read(p, l, node, value, known);
            if complete && !life_leaf_offered(l, leaf) { complete = false; }
        }
        // A replay of a frame of the chain can add to the list it is going
        // through. The list ends at the entry that was its last when the
        // replay came to it; an entry with reads after it was not the last,
        // so what was added behind them follows.
        if at < 0 && passed >= 0 && open { at = l.effects[passed].next; open = false; }
        if at < 0 { break; }
        passed = at; open = read >= 0;
        if plain {""")

# ---- ordinary entries from the first class-keyed frame on
rep("""fn life_class_new(p: Program&, l: Lifetimes&, function_node: i64, call: i64, selected_result: i64, receiver_sensitive: bool, c: const LifeClasses&) -> i64 {""", """// With class-keyed frames a summary's effects are merged by kind alone and
// mapped call by call (life_effect, life_replay), as ordinary entries. This
// makes every frame's list what it would have been: its other entries and
// its construct reads in the order they were added, each read an effect and
// a summary record with the entry's joined value, the sets it last took and
// its walk stamp.
fn life_reads_materialize(p: Program&, l: Lifetimes&) {
    l.compact = false;
    for frame in 0..l.frames.len {
        var read = l.frames[frame].first_read;
        if read < 0 { continue; }
        var at = l.frames[frame].first_summary; var last: i64 = -1;
        loop {
            while read >= 0 && (at < 0 || (l.summary_reads[read].before as i64) < at) {
                let entry = l.summary_reads[read]; read = entry.next as i64;
                let leaf = l.leaves[entry.leaf as i64]; let seen = l.leaves[entry.seen as i64].value;
                var places = leaf.value.place; if life_is_ref(p, leaf.value.type_id) { places = leaf.value.refs; }
                var seen_places = seen.place; if life_is_ref(p, leaf.value.type_id) { seen_places = seen.refs; }
                let index = l.effects.len;
                var effect = LifeEffect { kind: 3, node: leaf.node, value: leaf.value, places: places }; effect.previous = last; effect.owner = frame;
                let bucket = (frame * 1000003 + (leaf.node + 1) * 97 + 3 * 17 + effect.cell + 1) % l.summary_heads.len;
                l.summaries.push(LifeSummary { key: life_summary_key(effect, frame, leaf.node), next: l.summary_heads[bucket], owner: frame, kind: 3, node: leaf.node,
                    type_id: leaf.value.type_id, cell: effect.cell, field: effect.field, places: seen_places, refs: seen.refs, contents: seen.contents, place: seen.place,
                    walked: entry.walked, leaf: entry.leaf });
                l.summary_heads[bucket] = index; l.effects.push(effect);
                if last >= 0 { l.effects[last].next = index; l.summaries[last].after = index; } else { l.frames[frame].first_summary = index; }
                last = index;
            }
            if at < 0 { break; }
            let next = l.effects[at].next; l.effects[at].previous = last;
            if last >= 0 { l.effects[last].next = at; l.summaries[last].after = at; } else { l.frames[frame].first_summary = at; }
            last = at; at = next;
        }
        l.effects[last].next = -1; l.summaries[last].after = -1; l.frames[frame].last_summary = last;
        l.frames[frame].first_read = -1; l.frames[frame].last_read = -1; l.frames[frame].read_cap = 0; l.frames[frame].read_count = 0;
    }
    l.summary_reads.clear(); l.read_slots.clear();
}
fn life_class_new(p: Program&, l: Lifetimes&, function_node: i64, call: i64, selected_result: i64, receiver_sensitive: bool, c: const LifeClasses&) -> i64 {
    if l.compact { life_reads_materialize(p, l); }""")

# ---- the set of reads offered to a chain is no longer read (LifeReadEntry.sent took its place)
def cut(start, end):
    global t, n
    a = t.index(start); b = t.index(end, a); assert t.count(start) == 1; t = t[:a] + t[b:]; n += 1
cut("// Whether this chain of frames was offered the read before, with no place", "// The reads_version a summary had when this chain of frames last replayed")
a = t.index("fn life_chain_record(l: Lifetimes&, key: i64) {"); b = t.index("\n}\n", a) + 3; t = t[:a] + t[b:]; n += 1
rep("""    // Chains of frames by number (life_context: a frame and its parent's
    // chain), and the reads each chain has been offered (life_chain_offered),
    // an open-addressed set of chain, leaf and recursion epoch in one word.
    contexts: LifeContext[>..]&, context_heads: i64[>..]&, chain_offers: i64[>..]&, chain_offer_count: i64 = 0,
    // For a chain of frames and a frame whose summary was replayed in it with
    // every construct read offered (life_replay): the summary's reads_version
    // then. Keys as in chain_offers, the frame in the read's place.""", """    // Chains of frames by number (life_context: a frame and its parent's chain).
    contexts: LifeContext[>..]&, context_heads: i64[>..]&,
    // For a chain of frames and a frame whose summary was replayed in it with
    // every construct read offered (life_replay): the summary's reads_version
    // then. An open-addressed map from chain, frame and recursion epoch in
    // one word (life_chain_key).""")
rep(""" var chain_offers: i64[>..] = [];""", "")
rep("""chain_offers: chain_offers, """, "")
rep("""    // (The reads held by leaf have the chain's memo of an offer in the
    // offering frame's entry: LifeReadEntry.sent.)
    var chain: i64 = -1; if l.discovery && stamps && !compact { chain = life_chain_key(l, leaf, 0); }
    if !offered && chain >= 0 && life_chain_offered(l, chain) && !life_effect_far(l, offer).cyclic { life_leaf_stamp(l, leaf, offer); offered = true; }
    if !offered {""", """    if !offered {""")
rep("""        if stamps && l.offer_count > offers && !l.offer_recursive { life_leaf_stamp(l, leaf, offer); if chain >= 0 { life_chain_record(l, chain); } }""",
    """        if stamps && l.offer_count > offers && !l.offer_recursive { life_leaf_stamp(l, leaf, offer); }""")
open(p, 'w').write(t); print('applied', n)
