import model;

// Provenance is a property of an evaluated value, not of its syntax. All
// links are stable arena IDs; recursive visits borrow the arenas below.
// Binding bounds retain caller-storage depth without changing alias roots.
// Stored edges retain their pointee type: an array reference in one field
// must not become an element reference when another field is read.
// A root struct's fields are stored apart: component names the field node of
// the root owner whose storage this is, -1 the owner as a whole (upstream
// RootComponent identities). Contents stay with the owner.
struct LifeAlt { root: i64, exact: bool = true, from: i64 = -1, slotread: bool = false, byteview: bool = false, target_type: i64 = -1, bound: i64 = 0, next: i64 = -1, component: i64 = -1 }
struct LifeSet { first: i64 = -1, count: i64 = 0, bound_depth: i64 = -1, bound_result: i64 = 0 }
struct LifeRoot { symbol: i64 = -1, frame: i64 = -1, node: i64 = -1, type_id: i64 = -1, depth: i64 = 0, temporary: bool = false, contents: i64 = 0, live_contents: i64 = 0, atoms: i64 = -1, next_node: i64 = -1 }
// Element owner: -1 none, -2 inside elements with unknown owner, otherwise type ID.
struct LifeValue { type_id: i64 = -1, place: i64 = 0, refs: i64 = 0, contents: i64 = 0, self_pools: i64 = 0, relative_roots: i64 = 0, tuple: i64 = -1, element_array: i64 = -1 }
struct LifeItem { value: LifeValue, next: i64 = -1 }
struct LifeCell { symbol: i64, frame: i64, root: i64, parameter: bool = false, refs: i64 = 0, live_refs: i64 = 0, contents: i64 = 0, initial: i64 = 0, committed: bool = false, growshrink: bool = false, depth: i64 = 0, initialized: bool = false, live: bool = false, next_symbol: i64 = -1, next_frame: i64 = -1 }
struct LifeFrame { function_node: i64 = -1, parent: i64 = -1, lexical: i64 = 0, call: i64 = -1, inputs: i64 = -1, base: i64 = 0, active: bool = false, result: LifeValue = LifeValue {}, destination: i64 = 0, selected_result: i64 = -1, checked_revision: i64 = -1, next_function: i64 = -1, first_cell: i64 = -1, first_effect: i64 = -1, last_effect: i64 = -1, validated: bool = false, first_summary: i64 = -1, last_summary: i64 = -1, effect_epoch: i64 = 0, recursive_call: bool = false, home: i64 = -1, capture_inputs: i64 = -1, cycle: i64 = -1, activation: i64 = 0 }
struct LifeWalk { root: i64, type_id: i64 }
struct LifePair { owner: i64, pointee: i64, answer: bool, next: i64 = -1 }
struct LifeExit { node: i64, frame: i64, value: LifeValue, destination: i64 = 0, selected_result: i64 = -1 }
struct LifeFuture { node: i64, frame: i64, loop_scope: i64 = -1 }
struct LifeHold { value: LifeValue, node: i64, kind: i64 = 0, frame: i64 = 0 }
struct LifeTemp { frame: i64 }
struct LifeRead { node: i64, symbol: i64, answer: bool, next: i64 = -1 }
struct LifeKill { root: i64, field: i64, active: bool = true }
struct LifeAtom { set: i64, next: i64 = -1 }
// index_key, index_next and epoch: a validation-pass effect's hash, chain
// in effect_heads and its frame's effect_epoch when it was recorded.
struct LifeEffect { kind: i64, node: i64, value: LifeValue, places: i64 = 0, cell: i64 = -1, field: i64 = -1, next: i64 = -1, previous: i64 = -1, owner: i64 = -1, index_key: i64 = -1, index_next: i64 = -1, epoch: i64 = 0 }
struct LifeFailure { node: i64, message: const u8[:] }
// Per effect, for discovery merges: its summary key and the next effect in its
// summary_heads bucket, the fields a merge compares exactly (copies of the
// effect's own, which never change), and the sets last merged into it. Merging
// those same sets again changes nothing: an entry only grows, and a join with
// a subset returns the entry's own set.
struct LifeSummary {
    key: i64 = -1, next: i64 = -1, owner: i64 = -1, kind: i64 = 0, node: i64 = -1, type_id: i64 = -1, cell: i64 = -1, field: i64 = -1,
    places: i64 = -1, refs: i64 = -1, contents: i64 = -1, place: i64 = -1,
}
// A discovery effect offered up the frame chain, remembered by what the
// offer depends on: its current frame's activation (which fixes the chain of
// active frames above it), the recursion flags then, and every field a merge
// or insertion compares. Summary entries only grow, so the same offer again
// changes nothing.
struct LifeOffer {
    frame: i64 = -1, activation: i64 = -1, epoch: i64 = -1, kind: i64 = -1, node: i64 = -1, type_id: i64 = -1,
    cell: i64 = -1, field: i64 = -1, places: i64 = -1, refs: i64 = -1, contents: i64 = -1, place: i64 = -1,
}
struct Lifetimes {
    parents: const i64[:], depths: const i64[:], functions: const i64[:],
    roots: LifeRoot[>..]&, sets: LifeSet[>..]&, alts: LifeAlt[>..]&, cells: LifeCell[>..]&,
    frames: LifeFrame[>..]&, items: LifeItem[>..]&, pairs: LifePair[>..]&, pair_heads: i64[>..]&, exits: LifeExit[>..]&,
    futures: LifeFuture[>..]&, holds: LifeHold[>..]&, temps: LifeTemp[>..]&, reads: LifeRead[>..]&,
    kills: LifeKill[>..]&,
    size_classes: i64[>..]&, types_frozen: bool = false,
    atoms: LifeAtom[>..]&,
    failures: LifeFailure[>..]&, effects: LifeEffect[>..]&,
    symbol_cells: i64[:], node_roots: i64[:], function_frames: i64[:], visited: i64[:], summary_heads: i64[:],
    // Cached life_reads answers by (node, symbol), chained through reads.
    read_heads: i64[>..]&,
    // Per function node: 0 unknown, 1 its body reads no captured binding, 2 it may.
    capture_reads: i64[>..]&,
    // Per function node, the globals its body may read (life_reads_global):
    // a span of global_read_list, sorted; count -1 until computed.
    global_read_spans: LifeSet[>..]&, global_read_list: i64[>..]&,
    // Recent discovery offers (direct-mapped), the activation count, and how
    // many times a frame's recursion flag has been set.
    offers: LifeOffer[>..]&, activations: i64 = 0, recursion_epoch: i64 = 0,
    effect_heads: i64[>..]&, indexed_effects: i64 = 0,
    // Per effect, kept apart from the effects themselves so a bucket walk
    // stays in dense memory.
    summaries: LifeSummary[>..]&,
    visit: i64 = 0,
    frame: i64 = 0, scope: i64 = 0, revision: i64 = 0, discovery: bool = true,
    future_count: i64 = 0, hold_count: i64 = 0, temp_count: i64 = 0,
    reading_place: i64 = 0,
    conditional: i64 = 0,
    sequence_frame: i64 = -1,
    pass: i64 = 0,
}

// An order-independent hash of a set, equal for sets life_equal accepts.
fn life_set_hash(l: Lifetimes&, set: i64) -> i64 {
    var sum = 0; var at = l.sets[set].first;
    while at >= 0 {
        let alt = l.alts[at]; var h = alt.root * 1000003 + alt.from * 8191 + alt.target_type * 131 + alt.bound * 31 + alt.component * 17;
        if alt.exact { h += 1; } if alt.slotread { h += 2; } if alt.byteview { h += 4; }
        sum += h ^ (h >> 17); at = alt.next;
    }
    return sum;
}
fn life_same_effect(l: Lifetimes&, old: const LifeEffect&, effect: const LifeEffect&) -> bool {
    return old.kind == effect.kind && old.value.type_id == effect.value.type_id &&
       old.value.element_array == effect.value.element_array && old.field == effect.field && old.cell == effect.cell &&
       life_equal(l, old.places, effect.places) && life_equal(l, old.value.refs, effect.value.refs) && life_equal(l, old.value.contents, effect.value.contents);
}
// A place is local to the frames from its root's frame up the current
// chain: the chain position past which some place of the effect is not.
fn life_effect_far(l: Lifetimes&, effect: const LifeEffect&) -> i64 {
    var far = 0; var at = l.sets[effect.places].first;
    while at >= 0 {
        let root = l.alts[at].root;
        if root != 0 {
            let home = l.roots[root].frame; var inside = l.frame; var position = 0;
            while inside > 0 && inside != home { inside = l.frames[inside].parent; position += 1; }
            if inside <= 0 { return 9223372036854775807; }
            if position > far { far = position; }
        }
        at = l.alts[at].next;
    }
    return far;
}
// A recursive activation's own root reached through one of its parameters
// belongs to another activation.
fn life_effect_recursive(l: Lifetimes&, effect: const LifeEffect&, frame: i64) -> bool {
    var at = l.sets[effect.places].first;
    while at >= 0 {
        let root = l.alts[at].root;
        if root != 0 && l.roots[root].frame == frame {
            var ci = l.frames[frame].first_cell;
            while ci >= 0 {
                let cell = l.cells[ci];
                if cell.parameter && life_find(l, cell.refs, root) >= 0 { return true; }
                ci = cell.next_frame;
            }
        }
        at = l.alts[at].next;
    }
    return false;
}
// The fields a discovery merge compares exactly: frame, kind, node, type,
// cell and field.
fn life_summary_key(effect: const LifeEffect&, frame: i64) -> i64 {
    var h: u64 = 1469598103934665603;
    for part in [frame, effect.kind, effect.node, effect.value.type_id, effect.cell, effect.field] { h = (h ^ (part as! u64)) * 1099511628211; h ^= h >> 31; }
    return (h >> 1) as i64;
}
fn life_summary_seen(l: Lifetimes&, index: i64, effect: const LifeEffect&) {
    l.summaries[index].places = effect.places; l.summaries[index].refs = effect.value.refs;
    l.summaries[index].contents = effect.value.contents; l.summaries[index].place = effect.value.place;
}
// Discovery merges a frame's summary effects by site: whether one took it.
fn life_effect_merge(l: Lifetimes&, effect: const LifeEffect&, frame: i64, bucket: i64, key: i64) -> bool {
    var previous = l.summary_heads[bucket];
    while previous >= 0 {
        let summary: const LifeSummary& = l.summaries[previous]; let next = summary.next;
        if summary.key != key || summary.owner != frame || summary.kind != effect.kind || summary.node != effect.node || summary.type_id != effect.value.type_id || summary.cell != effect.cell || summary.field != effect.field {
            previous = next; continue;
        }
        if summary.places == effect.places && summary.refs == effect.value.refs && summary.contents == effect.value.contents && summary.place == effect.value.place { return true; }
        let old: const LifeEffect& = l.effects[previous];
        if effect.kind != 4 || life_equal(l, old.places, effect.places) {
            let old_places = old.places; let old_refs = old.value.refs; let old_contents = old.value.contents; let old_place = old.value.place;
            let places = life_join(l, old_places, effect.places);
            let refs = life_join(l, old_refs, effect.value.refs); let contents = life_join(l, old_contents, effect.value.contents);
            let value_places = life_join(l, old_place, effect.value.place);
            if !life_equal(l, places, old_places) || !life_equal(l, refs, old_refs) || !life_equal(l, contents, old_contents) || !life_equal(l, value_places, old_place) { l.revision += 1; }
            l.effects[previous].places = places; l.effects[previous].value.refs = refs; l.effects[previous].value.contents = contents; l.effects[previous].value.place = value_places;
            life_summary_seen(l, previous, effect);
            return true;
        }
        previous = next;
    }
    return false;
}
// Validation-pass effects that no other kind orders against are indexed by
// a hash of everything life_same_effect compares, and their frame.
inline fn life_index_bucket(l: Lifetimes&, key: i64) -> i64 { return (key ^ (key >> 21)) & (l.effect_heads.len - 1); }
// Two indexed effects per bucket at most, on average.
fn life_index_reserve(l: Lifetimes&) {
    if 2 * l.effect_heads.len > l.indexed_effects { return; }
    var size: i64 = 1024; while size <= l.indexed_effects { size <<= 1; }
    l.effect_heads.clear(); l.effect_heads.resize(size, -1);
    for index in 0..l.effects.len {
        let key = l.effects[index].index_key;
        if key >= 0 { let bucket = life_index_bucket(l, key); l.effects[index].index_next = l.effect_heads[bucket]; l.effect_heads[bucket] = index; }
    }
}
// Such an effect is redundant wherever an equal one is in the frame's
// current list: whether the bucket holds one.
fn life_effect_indexed(l: Lifetimes&, effect: const LifeEffect&, frame: i64, bucket: i64) -> bool {
    var probe = l.effect_heads[bucket];
    while probe >= 0 {
        let old: const LifeEffect& = l.effects[probe];
        if old.owner == frame && old.epoch == l.frames[frame].effect_epoch && life_same_effect(l, old, effect) { return true; }
        probe = old.index_next;
    }
    return false;
}
// An ordered effect is redundant only after an equal one with nothing it
// orders against in between.
fn life_effect_repeated(l: Lifetimes&, effect: const LifeEffect&, last: i64) -> bool {
    var previous = last;
    while previous >= 0 {
        let old: const LifeEffect& = l.effects[previous];
        if effect.kind == 1 && old.kind >= 4 { return false; }
        if effect.kind == 4 && (old.kind == 6 || old.kind == 7) && life_overlaps(l, old.places, effect.places) { return false; }
        if (effect.kind == 6 || effect.kind == 7) && old.kind == 4 && life_overlaps(l, old.places, effect.places) { return false; }
        if life_same_effect(l, old, effect) { return true; }
        previous = old.previous;
    }
    return false;
}
fn life_offer_slot(l: Lifetimes&, effect: const LifeEffect&) -> i64 {
    var h: u64 = 1469598103934665603;
    for part in [l.frame, effect.kind, effect.node, effect.value.type_id, effect.cell, effect.field, effect.places, effect.value.refs, effect.value.contents, effect.value.place] {
        h = (h ^ (part as! u64)) * 1099511628211; h ^= h >> 29;
    }
    return (h & ((l.offers.len - 1) as! u64)) as i64;
}
// Whether this discovery offer was already made in the current frame's
// activation; records it otherwise. Recursive frames are left out, as an
// offer to one depends on its cells.
fn life_offer_repeated(l: Lifetimes&, effect: const LifeEffect&) -> bool {
    var frame = l.frame;
    while frame > 0 { if l.frames[frame].recursive_call { return false; } frame = l.frames[frame].parent; }
    let slot = life_offer_slot(l, effect); let activation = l.frames[l.frame].activation;
    let o: const LifeOffer& = l.offers[slot];
    if o.frame == l.frame && o.activation == activation && o.epoch == l.recursion_epoch && o.kind == effect.kind && o.node == effect.node &&
       o.type_id == effect.value.type_id && o.cell == effect.cell && o.field == effect.field && o.places == effect.places &&
       o.refs == effect.value.refs && o.contents == effect.value.contents && o.place == effect.value.place { return true; }
    l.offers[slot] = LifeOffer { frame: l.frame, activation: activation, epoch: l.recursion_epoch, kind: effect.kind, node: effect.node, type_id: effect.value.type_id,
        cell: effect.cell, field: effect.field, places: effect.places, refs: effect.value.refs, contents: effect.value.contents, place: effect.value.place };
    return false;
}
fn life_effect(l: Lifetimes&, effect: LifeEffect) {
    if l.discovery && l.frame > 0 && life_offer_repeated(l, effect) { return; }
    let far = life_effect_far(l, effect);
    let ordered = effect.kind == 1 || effect.kind == 4 || effect.kind == 6 || effect.kind == 7;
    var indexed_key = -1;
    var frame = l.frame; var depth = 0;
    while frame > 0 {
        if !l.frames[frame].validated {
            var external = far > depth;
            if !external && l.frames[frame].recursive_call { external = life_effect_recursive(l, effect, frame); }
            var last = l.frames[frame].last_effect; if l.discovery { last = l.frames[frame].last_summary; }
            var bucket = 0; var summary_key = -1; var indexed = -1;
            if external && l.discovery {
                var key = frame * 1000003 + (effect.node + 1) * 97 + effect.kind * 17 + effect.cell + 1;
                if effect.kind == 4 && effect.places != 0 { key += l.alts[l.sets[effect.places].first].root * 31; }
                bucket = key % l.summary_heads.len; summary_key = life_summary_key(effect, frame);
                if life_effect_merge(l, effect, frame, bucket, summary_key) { external = false; }
            }
            if external && !l.discovery && !ordered {
                if indexed_key < 0 {
                    var key = effect.kind * 97 + effect.value.type_id * 131 + effect.value.element_array * 8191 + effect.field * 17 + effect.cell * 524287;
                    key += life_set_hash(l, effect.places) * 31 + life_set_hash(l, effect.value.refs) * 37 + life_set_hash(l, effect.value.contents) * 41;
                    indexed_key = key & 4611686018427387903;
                }
                life_index_reserve(l);
                indexed = indexed_key + frame * 1000003;
                if life_effect_indexed(l, effect, frame, life_index_bucket(l, indexed)) { external = false; }
            }
            if external && !l.discovery && ordered && life_effect_repeated(l, effect, last) { external = false; }
            if external {
                let index = l.effects.len; var entry = effect; entry.next = -1; entry.previous = last; entry.owner = frame;
                l.summaries.push(LifeSummary { key: summary_key, owner: frame, kind: entry.kind, node: entry.node, type_id: entry.value.type_id, cell: entry.cell, field: entry.field });
                if l.discovery { life_summary_seen(l, index, entry); l.summaries[index].next = l.summary_heads[bucket]; l.summary_heads[bucket] = index; }
                if indexed >= 0 {
                    let slot = life_index_bucket(l, indexed);
                    entry.index_key = indexed; entry.index_next = l.effect_heads[slot]; entry.epoch = l.frames[frame].effect_epoch;
                    l.effect_heads[slot] = index; l.indexed_effects += 1;
                }
                l.effects.push(entry);
                if last >= 0 { l.effects[last].next = index; }
                if l.discovery {
                    if last < 0 { l.frames[frame].first_summary = index; }
                    l.frames[frame].last_summary = index; l.revision += 1;
                } else {
                    if last < 0 { l.frames[frame].first_effect = index; }
                    l.frames[frame].last_effect = index;
                }
            }
        }
        frame = l.frames[frame].parent; depth += 1;
    }
}

fn life_error(p: Program&, l: Lifetimes&, node: i64, message: const u8[:]) {
    if l.discovery || node < 0 { return; }
    let token = p.nodes[node].token;
    if token < 0 { return; }
    for d in p.diagnostics {
        if d.source == p.tokens[token].source && d.start == p.tokens[token].start { return; }
    }
    diagnose(p, token, message);
}
fn life_scope_error(p: Program&, l: Lifetimes&, node: i64, message: const u8[:]) {
    if !l.discovery { life_error(p, l, node, message); return; }
    for failure in l.failures { if failure.node == node { return; } }
    l.failures.push(LifeFailure { node: node, message: message });
}
inline fn life_is_ref(p: Program&, ty: i64) -> bool {
    return ty >= 0 && (p.types[ty].kind == TY_REF || p.types[ty].kind == TY_SLICE);
}
fn life_plain_ref(p: Program&, ty: i64) -> bool {
    return ty >= 0 && (p.types[ty].kind == TY_SLICE || p.types[ty].kind == TY_REF && p.types[ty].length_storage < 0);
}
fn life_same(p: Program&, a: i64, b: i64) -> bool {
    if a == b { return true; }
    if a < 0 || b < 0 { return false; }
    let x: const Type& = p.types[a]; let y: const Type& = p.types[b];
    if x.kind != y.kind { return false; }
    if x.kind == TY_STRUCT || x.kind == TY_ENUM { return x.declaration == y.declaration; }
    if x.kind == TY_INT { return x.count == y.count && (x.flags & TF_UNSIGNED) == (y.flags & TF_UNSIGNED); }
    if x.kind == TY_FLOAT { return x.count == y.count; }
    if x.kind == TY_ARRAY { return x.array_kind == y.array_kind && x.element == y.element; }
    if x.kind == TY_REF || x.kind == TY_SLICE { return x.element == y.element; }
    return true;
}
fn life_pair_bucket(owner: i64, pointee: i64, count: i64) -> i64 {
    let a = owner ^ (owner >> 14) ^ (owner >> 28) ^ (owner >> 42) ^ (owner >> 56);
    let b = pointee ^ (pointee >> 14) ^ (pointee >> 28) ^ (pointee >> 42) ^ (pointee >> 56);
    return (a ^ b ^ ((b & 8191) << 1) ^ (b >> 13)) & (count - 1);
}
fn life_contains(p: Program&, l: Lifetimes&, owner: i64, pointee: i64) -> bool {
    if owner < 0 || pointee < 0 { return false; }
    // Two cached pairs per bucket at most, on average.
    if 2 * l.pair_heads.len <= l.pairs.len {
        var count: i64 = 16;
        while count < p.types.len || 2 * count <= l.pairs.len { count <<= 1; }
        l.pair_heads.clear(); l.pair_heads.resize(count, -1);
        for index in 0..l.pairs.len {
            let slot = life_pair_bucket(l.pairs[index].owner, l.pairs[index].pointee, count);
            l.pairs[index].next = l.pair_heads[slot]; l.pair_heads[slot] = index;
        }
    }
    let bucket = life_pair_bucket(owner, pointee, l.pair_heads.len);
    var pair = l.pair_heads[bucket];
    while pair >= 0 {
        let q = l.pairs[pair];
        if q.owner == owner && q.pointee == pointee { return q.answer; }
        pair = q.next;
    }
    var work: i64[>..] = [owner]; var at = 0; var answer = false;
    while at < work.len {
        let ty = work[at]; at += 1;
        if life_same(p, ty, pointee) { answer = true; break; }
        let t: const Type& = p.types[ty];
        if t.kind == TY_ARRAY && t.element >= 0 {
            var seen = false; for old in work { if old == t.element { seen = true; } }
            if !seen { work.push(t.element); }
        } else if t.kind == TY_STRUCT || t.kind == TY_ENUM || t.kind == TY_TUPLE {
            var field = t.first;
            while field >= 0 {
                let ft = p.nodes[field].type_id; var seen = ft < 0;
                for old in work { if old == ft { seen = true; } }
                if !seen { work.push(ft); }
                field = p.nodes[field].next;
            }
        }
    }
    let index = l.pairs.len;
    l.pairs.push(LifePair { owner: owner, pointee: pointee, answer: answer, next: l.pair_heads[bucket] });
    l.pair_heads[bucket] = index;
    return answer;
}
inline fn life_holds(p: Program&, ty: i64) -> bool {
    if ty < 0 { return false; }
    let t: const Type& = p.types[ty];
    if t.kind == TY_SLICE { return true; }
    if t.kind == TY_REF { return t.length_storage < 0; }
    if t.kind == TY_ARRAY || t.kind == TY_STRUCT || t.kind == TY_ENUM || t.kind == TY_TUPLE { return life_holds_walk(p, ty); }
    return false;
}
fn life_holds_walk(p: Program&, ty: i64) -> bool {
    if ty < 0 { return false; }
    while p.type_holds.len < p.types.len { p.type_holds.push(0); }
    if p.type_holds[ty] != 0 { return p.type_holds[ty] == 2; }
    let answer = life_holds_scan(p, ty);
    if answer { p.type_holds[ty] = 2; } else { p.type_holds[ty] = 1; }
    return answer;
}
fn life_holds_scan(p: Program&, ty: i64) -> bool {
    var work: i64[>..] = [ty]; var at = 0;
    while at < work.len {
        let t: const Type& = p.types[work[at]]; at += 1;
        if t.kind == TY_SLICE || t.kind == TY_REF && t.length_storage < 0 { return true; }
        if t.kind == TY_ARRAY && t.element >= 0 {
            var seen = false; for old in work { if old == t.element { seen = true; } }
            if !seen { work.push(t.element); }
        } else if t.kind == TY_STRUCT || t.kind == TY_ENUM || t.kind == TY_TUPLE {
            var field = t.first;
            while field >= 0 {
                let ft = p.nodes[field].type_id; var seen = ft < 0;
                for old in work { if old == ft { seen = true; } }
                if !seen { work.push(ft); }
                field = p.nodes[field].next;
            }
        }
    }
    return false;
}
fn life_find(l: Lifetimes&, set: i64, root: i64) -> i64 {
    var at = l.sets[set].first;
    while at >= 0 { if l.alts[at].root == root { return at; } at = l.alts[at].next; }
    return -1;
}
fn life_equal(l: Lifetimes&, a: i64, b: i64) -> bool {
    if a == b { return true; }
    if l.sets[a].count != l.sets[b].count { return false; }
    var at = l.sets[a].first;
    while at >= 0 {
        let x = l.alts[at]; let found = life_find(l, b, x.root);
        if found < 0 { return false; }
        let y = l.alts[found];
        if x.exact != y.exact || x.from != y.from || x.slotread != y.slotread || x.byteview != y.byteview || x.target_type != y.target_type || x.bound != y.bound || x.component != y.component { return false; }
        at = x.next;
    }
    return true;
}
fn life_insert(l: Lifetimes&, set: i64, alt: LifeAlt) {
    let old = life_find(l, set, alt.root);
    if old >= 0 {
        l.alts[old].exact = l.alts[old].exact && alt.exact;
        l.alts[old].slotread = l.alts[old].slotread && alt.slotread;
        l.alts[old].byteview = l.alts[old].byteview || alt.byteview;
        if alt.bound > l.alts[old].bound { l.alts[old].bound = alt.bound; }
        if l.alts[old].from != alt.from { l.alts[old].from = -1; }
        if l.alts[old].target_type != alt.target_type { l.alts[old].target_type = -1; }
        if l.alts[old].component != alt.component { l.alts[old].component = -1; }
        return;
    }
    let index = l.alts.len; var entry = alt; entry.next = l.sets[set].first;
    l.alts.push(entry); l.sets[set].first = index; l.sets[set].count += 1;
}
fn life_single(l: Lifetimes&, root: i64, exact: bool = true, from: i64 = -1, slotread: bool = false, byteview: bool = false, target_type: i64 = -1, bound: i64 = 0, component: i64 = -1) -> i64 {
    let ordinary = exact && from == -1 && !slotread && !byteview && target_type == -1 && bound == 0 && component == -1;
    var head = l.roots[root].atoms; var cached = -1;
    if head < -1 {
        cached = -2 - head;
        if ordinary { return l.atoms[cached].set; }
        head = l.atoms[cached].next;
    }
    var at = head;
    while at >= 0 {
        let entry = l.atoms[at]; let alt = l.alts[l.sets[entry.set].first];
        if alt.exact == exact && alt.from == from && alt.slotread == slotread && alt.byteview == byteview && alt.target_type == target_type && alt.bound == bound && alt.component == component { return entry.set; }
        at = entry.next;
    }
    let set = l.sets.len; l.sets.push(LifeSet {});
    life_insert(l, set, LifeAlt { root: root, exact: exact, from: from, slotread: slotread, byteview: byteview, target_type: target_type, bound: bound, component: component });
    let atom = l.atoms.len; l.atoms.push(LifeAtom { set: set, next: head });
    if ordinary { l.roots[root].atoms = -2 - atom; }
    else if cached >= 0 { l.atoms[cached].next = atom; }
    else { l.roots[root].atoms = atom; }
    return set;
}
inline fn life_root_set(l: Lifetimes&, root: i64) -> i64 {
    let head = l.roots[root].atoms;
    if head < -1 { return l.atoms[-2 - head].set; }
    return life_single(l, root);
}
fn life_interior(l: Lifetimes&, roots: i64) -> i64 {
    var out = 0; var at = l.sets[roots].first;
    while at >= 0 { let alt = l.alts[at]; out = life_join(l, out, life_single(l, alt.root, alt.exact, alt.from, false, alt.byteview, -1, alt.bound, alt.component)); at = alt.next; }
    return out;
}
// A field of a root owner is that owner's own component; any other field
// lies inside its container's storage.
fn life_component(l: Lifetimes&, places: i64, field: i64) -> i64 {
    var out = 0; var at = l.sets[places].first;
    while at >= 0 {
        let alt = l.alts[at]; var component = alt.component; if component < 0 { component = field; }
        out = life_join(l, out, life_single(l, alt.root, alt.exact, alt.from, false, alt.byteview, -1, alt.bound, component)); at = alt.next;
    }
    return out;
}

fn life_join(l: Lifetimes&, a: i64, b: i64) -> i64 {
    if b == 0 || life_equal(l, a, b) { return a; }
    if a == 0 { return b; }
    var subset = true; var probe = l.sets[b].first;
    while probe >= 0 {
        let incoming = l.alts[probe]; let existing = life_find(l, a, incoming.root);
        if existing < 0 { subset = false; break; }
        let old = l.alts[existing];
        if old.exact && !incoming.exact || old.slotread && !incoming.slotread ||
           !old.byteview && incoming.byteview || old.from >= 0 && old.from != incoming.from || old.target_type >= 0 && old.target_type != incoming.target_type || old.bound < incoming.bound ||
           old.component >= 0 && old.component != incoming.component { subset = false; break; }
        probe = incoming.next;
    }
    if subset { return a; }
    let set = l.sets.len; l.sets.push(LifeSet {});
    var at = l.sets[a].first;
    while at >= 0 { let alt = l.alts[at]; life_insert(l, set, alt); at = alt.next; }
    at = l.sets[b].first;
    while at >= 0 { let alt = l.alts[at]; life_insert(l, set, alt); at = alt.next; }
    return set;
}
fn life_depth(l: Lifetimes&, scope: i64) -> i64 {
    if l.frame == 0 {
        if scope >= 0 && scope < l.depths.len { return 2 * l.depths[scope]; }
        return 0;
    }
    let frame = l.frames[l.frame]; var declaration = 0;
    if frame.function_node >= 0 {
        var at = scope;
        while at > 0 && l.functions[at] == frame.function_node { declaration = l.depths[at]; at = l.parents[at]; }
    }
    if scope < 0 || scope >= l.depths.len { return frame.base; }
    return frame.base + 2 * (l.depths[scope] - declaration);
}
fn life_alt_depth(l: Lifetimes&, alt: LifeAlt) -> i64 {
    let depth = l.roots[alt.root].depth;
    if alt.bound > depth { return alt.bound; }
    return depth;
}
fn life_binding_depth(l: Lifetimes&, set: i64) -> i64 {
    var result = 0; var at = l.sets[set].first;
    while at >= 0 {
        let depth = life_alt_depth(l, l.alts[at]);
        if depth > result { result = depth; }
        at = l.alts[at].next;
    }
    return result;
}
fn life_set_depth(l: Lifetimes&, set: i64) -> i64 {
    var result = 0; var at = l.sets[set].first;
    while at >= 0 {
        let root = l.alts[at].root;
        if l.roots[root].depth > result { result = l.roots[root].depth; }
        at = l.alts[at].next;
    }
    return result;
}
fn life_frame_for(p: Program&, l: Lifetimes&, symbol: i64) -> i64 {
    if (p.symbols[symbol].flags & S_GLOBAL) != 0 || p.symbols[symbol].owner < 0 { return 0; }
    var frame = l.frame;
    while frame > 0 {
        if l.frames[frame].function_node == p.symbols[symbol].owner { return frame; }
        frame = l.frames[frame].parent;
    }
    return l.frame;
}
fn life_cell(p: Program&, l: Lifetimes&, symbol: i64) -> i64 {
    if symbol < 0 || symbol >= p.symbols.len { return -1; }
    let frame = life_frame_for(p, l, symbol);
    var found = l.symbol_cells[symbol];
    while found >= 0 { let cell = l.cells[found]; if cell.frame == frame { return found; } found = cell.next_symbol; }
    let saved = l.frame; l.frame = frame;
    let root = l.roots.len;
    var depth = life_depth(l, p.symbols[symbol].scope); if (p.symbols[symbol].flags & S_GLOBAL) != 0 { depth = 0; }
    l.roots.push(LifeRoot { symbol: symbol, frame: frame, type_id: p.symbols[symbol].type_id, depth: depth });
    l.frame = saved;
    let index = l.cells.len; l.cells.push(LifeCell { symbol: symbol, frame: frame, root: root, parameter: (p.symbols[symbol].flags & S_PARAMETER) != 0, next_symbol: l.symbol_cells[symbol], next_frame: l.frames[frame].first_cell });
    l.symbol_cells[symbol] = index; l.frames[frame].first_cell = index;
    return index;
}
fn life_note_temp(p: Program&, l: Lifetimes&, type_id: i64) {
    if l.discovery || life_cached_size_class(p, l, type_id) == 0 { return; }
    let value = LifeTemp { frame: l.frame };
    if l.temp_count == l.temps.len { l.temps.push(value); } else { l.temps[l.temp_count] = value; }
    l.temp_count += 1;
}
fn life_temporary(p: Program&, l: Lifetimes&, node: i64) -> i64 {
    var found = l.node_roots[node];
    while found >= 0 {
        let root = l.roots[found];
        if root.frame == l.frame { life_note_temp(p, l, root.type_id); return life_root_set(l, found); }
        found = root.next_node;
    }
    let root = l.roots.len;
    l.roots.push(LifeRoot { frame: l.frame, node: node, type_id: p.nodes[node].type_id, depth: life_depth(l, l.scope) + 1, temporary: true, next_node: l.node_roots[node] });
    l.node_roots[node] = root; life_note_temp(p, l, p.nodes[node].type_id);
    return life_root_set(l, root);
}

fn life_bound(l: Lifetimes&, sources: i64, depth: i64) -> i64 {
    if depth == 0 || sources == 0 { return sources; }
    if l.sets[sources].bound_depth == depth { return l.sets[sources].bound_result; }
    var result = 0; var at = l.sets[sources].first;
    while at >= 0 {
        var alt = l.alts[at]; if depth > alt.bound { alt.bound = depth; }
        result = life_join(l, result, life_single(l, alt.root, alt.exact, alt.from, alt.slotread, alt.byteview, alt.target_type, alt.bound, alt.component)); at = alt.next;
    }
    l.sets[sources].bound_depth = depth; l.sets[sources].bound_result = result;
    return result;
}
fn life_contents(l: Lifetimes&, places: i64) -> i64 {
    var result = 0; var at = l.sets[places].first;
    while at >= 0 { let alt = l.alts[at]; result = life_join(l, result, life_bound(l, l.roots[alt.root].contents, alt.bound)); at = alt.next; }
    return result;
}
fn life_live_contents(l: Lifetimes&, places: i64) -> i64 {
    var result = 0; var at = l.sets[places].first;
    while at >= 0 { let alt = l.alts[at]; result = life_join(l, result, life_bound(l, l.roots[alt.root].live_contents, alt.bound)); at = alt.next; }
    return result;
}
fn life_value_roots(p: Program&, value: LifeValue) -> i64 {
    if value.type_id >= 0 && p.types[value.type_id].kind == TY_REF && p.types[value.type_id].length_storage >= 0 { return 0; }
    if life_is_ref(p, value.type_id) { return value.refs; }
    return value.contents;
}
fn life_gs_contains(p: Program&, l: Lifetimes&, owner: i64, pointee: i64, byteview: bool) -> bool {
    if owner < 0 { return false; }
    var work: i64[>..] = [owner]; var at = 0;
    while at < work.len {
        let t: const Type& = p.types[work[at]]; at += 1;
        if t.kind == TY_ARRAY {
            if t.array_kind == A_GROWSHRINK && (byteview || life_contains(p, l, t.element, pointee)) { return true; }
            if t.element >= 0 {
                var seen = false; for old in work { if old == t.element { seen = true; } }
                if !seen { work.push(t.element); }
            }
        } else if t.kind == TY_STRUCT || t.kind == TY_ENUM {
            var field = t.first;
            while field >= 0 {
                let ft = p.nodes[field].type_id; var seen = ft < 0;
                for old in work { if old == ft { seen = true; } }
                if !seen { work.push(ft); }
                field = p.nodes[field].next;
            }
        }
    }
    return false;
}
// The storage an alternative names: a root owner's component, or its root.
inline fn life_alt_type(p: Program&, l: Lifetimes&, alt: LifeAlt) -> i64 {
    if alt.component >= 0 { return p.nodes[alt.component].type_id; }
    return l.roots[alt.root].type_id;
}
fn life_gs_value(p: Program&, l: Lifetimes&, value: LifeValue) -> bool {
    if value.type_id < 0 { return false; }
    let t: const Type& = p.types[value.type_id]; let sources = life_value_roots(p, value);
    var at = l.sets[sources].first;
    while at >= 0 {
        let alt = l.alts[at]; let root = l.roots[alt.root];
        let storage = life_alt_type(p, l, alt);
        if !alt.slotread && life_is_ref(p, value.type_id) && life_gs_contains(p, l, storage, t.element, alt.byteview) { return true; }
        if !alt.slotread && !life_is_ref(p, value.type_id) {
            // The holder's precise store record contains the roots; its
            // type says which of their elements its reference slots reach.
            var types: i64[>..] = [];
            if storage >= 0 { types.push(storage); }
            var index = 0;
            while index < types.len {
                let owner: const Type& = p.types[types[index]]; index += 1;
                if owner.kind == TY_ARRAY {
                    if owner.array_kind == A_GROWSHRINK && (alt.byteview || life_holder_views(p, l, value.type_id, owner.element)) { return true; }
                    if owner.element >= 0 { var seen = false; for old in types { if old == owner.element { seen = true; } } if !seen { types.push(owner.element); } }
                } else if owner.kind == TY_STRUCT || owner.kind == TY_ENUM {
                    var field = owner.first;
                    while field >= 0 { let ft = p.nodes[field].type_id; var seen = ft < 0; for old in types { if old == ft { seen = true; } } if !seen { types.push(ft); } field = p.nodes[field].next; }
                }
            }
        }
        if t.kind == TY_REF && t.element >= 0 && p.types[t.element].kind == TY_SLICE {
            var inner = l.sets[root.contents].first;
            while inner >= 0 {
                let view = l.alts[inner];
                if !view.slotread && life_gs_contains(p, l, life_alt_type(p, l, view), p.types[t.element].element, view.byteview) { return true; }
                inner = view.next;
            }
        }
        at = alt.next;
    }
    return false;
}
inline fn life_relative_storage(p: Program&, ty: i64, include_pool: bool = false) -> bool {
    if ty < 0 { return false; }
    let t: const Type& = p.types[ty];
    if t.kind == TY_REF { return t.length_storage >= 0 && (t.pool < 0 || include_pool); }
    if t.kind == TY_ARRAY || t.kind == TY_STRUCT || t.kind == TY_ENUM || t.kind == TY_TUPLE { return life_relative_storage_walk(p, ty, include_pool); }
    return false;
}
fn life_relative_storage_walk(p: Program&, ty: i64, include_pool: bool = false) -> bool {
    if ty < 0 { return false; }
    var work: i64[>..] = [ty]; var at = 0;
    while at < work.len {
        let t: const Type& = p.types[work[at]]; at += 1;
        if t.kind == TY_REF { if t.length_storage >= 0 && (t.pool < 0 || include_pool) { return true; } continue; }
        if t.kind == TY_ARRAY && t.element >= 0 { work.push(t.element); }
        if t.kind == TY_STRUCT || t.kind == TY_ENUM || t.kind == TY_TUPLE {
            var field = t.first;
            while field >= 0 {
                let ft = p.nodes[field].type_id; var seen = ft < 0; for old in work { if old == ft { seen = true; } }
                if !seen { work.push(ft); } field = p.nodes[field].next;
            }
        }
    }
    return false;
}

fn life_fresh(p: Program&, node: i64) -> bool {
    var work: i64[>..] = [node]; var at = 0;
    while at < work.len {
        let current = work[at]; at += 1; if current < 0 { continue; }
        let n: const Node& = p.nodes[current];
        if n.type_id == TYPE_VOID || n.kind == N_ARRAY || n.kind == N_FILL || n.kind == N_RECORD || n.kind == N_NULL { continue; }
        if n.kind == N_BLOCK || n.kind == N_LOOP || n.kind == N_WHILE || n.kind == N_FOR {
            if n.kind == N_BLOCK && n.last >= 0 && (p.nodes[n.last].flags & F_TAIL) != 0 { work.push(n.last); }
            for branch in p.nodes { if branch.kind == N_BREAK && branch.symbol == current && branch.left >= 0 { work.push(branch.left); } }
            continue;
        }
        if n.kind == N_RESULT { work.push(n.left); continue; }
        if n.kind == N_IF { work.push(n.right); work.push(n.third); continue; }
        if n.kind == N_MATCH { var arm = n.first; while arm >= 0 { work.push(p.nodes[arm].right); arm = p.nodes[arm].next; } continue; }
        if n.kind == N_CALL && n.symbol >= 0 {
            let symbol: const Symbol& = p.symbols[n.symbol];
            if (symbol.flags & S_BUILTIN) != 0 && symbol.index == 14 { continue; }
            if (symbol.flags & (S_BUILTIN | S_EXTERN)) == 0 && !life_is_ref(p, n.type_id) { continue; }
        }
        return false;
    }
    return true;
}
fn life_named_keeps_links(p: Program&, l: Lifetimes&, ty: i64) -> bool {
    var heads: i64[>..] = []; var tail = ty;
    while tail >= 0 && p.types[tail].kind == TY_STRUCT && life_cached_size_class(p, l, tail) == 2 {
        var field = p.types[tail].first; if field < 0 { break; }
        while p.nodes[field].next >= 0 { heads.push(p.nodes[field].type_id); field = p.nodes[field].next; }
        tail = p.nodes[field].type_id;
    }
    if tail < 0 || p.types[tail].kind != TY_ARRAY && life_cached_size_class(p, l, tail) == 2 { return false; }
    var work: i64[>..] = [tail]; var pointees: i64[>..] = []; var at = 0;
    while at < work.len {
        let t: const Type& = p.types[work[at]]; at += 1;
        if t.kind == TY_REF { if t.length_storage >= 0 && t.pool < 0 { pointees.push(t.element); } continue; }
        if t.kind == TY_ARRAY && t.element >= 0 { work.push(t.element); }
        if t.kind == TY_STRUCT || t.kind == TY_ENUM || t.kind == TY_TUPLE {
            var field = t.first;
            while field >= 0 {
                let ft = p.nodes[field].type_id; var seen = ft < 0; for old in work { if old == ft { seen = true; } }
                if !seen { work.push(ft); } field = p.nodes[field].next;
            }
        }
    }
    for head in heads {
        if life_relative_storage(p, head) { return false; }
        for pointee in pointees { if life_contains(p, l, head, pointee) { return false; } }
    }
    return true;
}
fn life_relative_named(p: Program&, l: Lifetimes&, node: i64, ty: i64, target: i64) -> bool {
    if target <= 0 || p.nodes[node].kind != N_NAME || life_cached_size_class(p, l, ty) == 0 { return false; }
    let symbol = p.nodes[node].symbol; if symbol < 0 { return false; }
    let function_node = l.frames[target].function_node; if function_node < 0 { return false; }
    let f: const Node& = p.nodes[function_node]; let body: const Node& = p.nodes[f.right]; var top = false; var statement = body.first;
    while statement >= 0 {
        let n: const Node& = p.nodes[statement];
        if n.kind == N_VARIABLE && (n.first < 0 && n.symbol == symbol || n.first >= 0 && p.nodes[n.first].next < 0 && p.nodes[n.first].symbol == symbol) { top = true; }
        statement = n.next;
    }
    if !top || !life_named_keeps_links(p, l, p.symbols[symbol].type_id) { return false; }
    let ct: const Type& = p.types[p.symbols[symbol].type_id]; let rt: const Type& = p.types[ty];
    if !life_same(p, p.symbols[symbol].type_id, ty) && !((ct.array_kind == A_GROW || ct.array_kind == A_GROWSHRINK) && rt.kind == TY_ARRAY && rt.array_kind == A_VAR && life_same(p, ct.element, rt.element)) { return false; }
    var work: i64[>..] = [f.right]; var at = 0;
    while at < work.len {
        let n: const Node& = p.nodes[work[at]]; at += 1;
        if n.kind == N_RETURN && (n.symbol == f.symbol || n.symbol < 0) {
            if n.first < 0 || p.nodes[n.first].next >= 0 || p.nodes[n.first].kind != N_NAME || p.nodes[n.first].symbol != symbol { return false; }
        }
        var child = n.first; while child >= 0 { work.push(child); child = p.nodes[child].next; }
        for child in [n.left, n.right, n.third] { if child >= 0 { work.push(child); } }
    }
    return true;
}
fn life_copy(p: Program&, l: Lifetimes&, node: i64, ty: i64, target: i64 = -1) {
    if l.discovery || node < 0 || ty < 0 || life_is_ref(p, ty) || !life_relative_storage(p, ty) || life_fresh(p, node) { return; }
    if target >= 0 && life_relative_named(p, l, node, ty, target) { return; }
    life_error(p, l, node, "copying a value containing self-relative references is unsupported; construct it in its destination");
}

recursive fn life_receive(p: Program&, l: Lifetimes&, node: i64, value: LifeValue, expected: i64) {
    if l.discovery || expected < 0 { return; }
    if value.relative_roots != 0 && value.type_id >= 0 && p.types[value.type_id].kind == TY_ARRAY && p.types[expected].kind == TY_ARRAY {
        if p.types[value.type_id].array_kind != p.types[expected].array_kind || p.types[value.type_id].count != p.types[expected].count {
            life_error(p, l, node, "a result containing relative links to its destination cannot change representation");
        }
    }
    if value.tuple >= 0 && p.types[expected].kind == TY_TUPLE {
        var item = value.tuple; var component = p.types[expected].first;
        while item >= 0 && component >= 0 {
            life_receive(p, l, node, l.items[item].value, p.nodes[component].type_id);
            item = l.items[item].next; component = p.nodes[component].next;
        }
    } else if life_is_ref(p, value.type_id) && !life_is_ref(p, expected) && life_relative_storage(p, expected) {
        life_error(p, l, node, "copying a reference result containing self-relative links is unsupported; bind it by reference");
    }
}

fn life_one_array(p: Program&, l: Lifetimes&, owner: i64, element: i64) -> bool {
    if owner < 0 { return false; }
    var work: i64[>..] = [owner]; var at = 0; var count = 0;
    while at < work.len {
        let ty = work[at]; at += 1; let t: const Type& = p.types[ty];
        if life_same(p, ty, element) { return false; }
        if t.kind == TY_ARRAY {
            if life_same(p, t.element, element) { count += 1; if count > 1 { return false; } }
            else if life_contains(p, l, t.element, element) { return false; }
        } else if t.kind == TY_STRUCT || t.kind == TY_ENUM || t.kind == TY_TUPLE {
            var field = t.first;
            while field >= 0 { let ft = p.nodes[field].type_id; if ft >= 0 { work.push(ft); } field = p.nodes[field].next; }
        }
    }
    return count == 1;
}
fn life_size_class(p: Program&, ty: i64) -> i64 {
    if ty < 0 { return 0; }
    var work: i64[>..] = [ty]; var at = 0; var result = 0;
    while at < work.len {
        let t: const Type& = p.types[work[at]]; at += 1;
        if t.kind == TY_REF || t.kind == TY_SLICE { if t.kind == TY_REF && t.length_storage == 0 { result = 1; } continue; }
        if t.storage == 1 { result = 1; }
        if t.kind == TY_ARRAY {
            if t.array_kind == A_GROW || t.array_kind == A_GROWSHRINK { return 2; }
            if t.array_kind == A_VAR || t.array_kind == A_LIMITED && t.count < 0 { result = 1; }
            if t.element >= 0 {
                var seen = false; for old in work { if old == t.element { seen = true; } }
                if !seen { work.push(t.element); }
            }
        } else if t.kind == TY_STRUCT || t.kind == TY_ENUM {
            if t.kind == TY_ENUM { if (t.flags & F_VARIABLE_MODE) == 0 { continue; } result = 1; }
            var field = t.first;
            while field >= 0 {
                let ft = p.nodes[field].type_id; var seen = ft < 0;
                for old in work { if old == ft { seen = true; } }
                if !seen { work.push(ft); }
                field = p.nodes[field].next;
            }
        }
    }
    return result;
}
inline fn life_cached_size_class(p: Program&, l: Lifetimes&, ty: i64) -> i64 {
    if ty < 0 { return 0; }
    if !l.types_frozen || ty >= l.size_classes.len { return life_size_class(p, ty); }
    let cached = l.size_classes[ty];
    if cached >= 0 { return cached; }
    let result = life_size_class(p, ty); l.size_classes[ty] = result;
    return result;
}
fn life_push_future(l: Lifetimes&, node: i64, loop_scope: i64 = -1) {
    if node < 0 { return; }
    let entry = LifeFuture { node: node, frame: l.frame, loop_scope: loop_scope };
    if l.future_count == l.futures.len { l.futures.push(entry); } else { l.futures[l.future_count] = entry; }
    l.future_count += 1;
}
fn life_hold(l: Lifetimes&, value: LifeValue, node: i64, kind: i64 = 0) {
    let entry = LifeHold { value: value, node: node, kind: kind, frame: l.frame };
    if l.hold_count == l.holds.len { l.holds.push(entry); } else { l.holds[l.hold_count] = entry; }
    l.hold_count += 1;
}
inline fn life_read_child(l: Lifetimes&, work: i64[>..]&, node: i64) {
    if node < 0 || l.visited[node] == l.visit { return; }
    l.visited[node] = l.visit; work.push(node);
}
inline fn life_read_bucket(node: i64, symbol: i64, count: i64) -> i64 {
    var h = (node as! u64) * 11400714819323198485 ^ (symbol as! u64) * 14029467366897019727;
    h ^= h >> 29; return (h & ((count - 1) as! u64)) as i64;
}
fn life_reads(p: Program&, l: Lifetimes&, node: i64, symbol: i64) -> bool {
    if node < 0 { return false; }
    // Two cached answers per bucket at most, on average.
    if 2 * l.read_heads.len <= l.reads.len {
        var count: i64 = 1024; while 2 * count <= l.reads.len { count <<= 1; }
        l.read_heads.clear(); l.read_heads.resize(count, -1);
        for index in 0..l.reads.len {
            let slot = life_read_bucket(l.reads[index].node, l.reads[index].symbol, count);
            l.reads[index].next = l.read_heads[slot]; l.read_heads[slot] = index;
        }
    }
    let bucket = life_read_bucket(node, symbol, l.read_heads.len);
    var cached = l.read_heads[bucket];
    while cached >= 0 { let q: const LifeRead& = l.reads[cached]; if q.node == node && q.symbol == symbol { return q.answer; } cached = q.next; }
    l.visit += 1; var work: i64[>..] = []; life_read_child(l, work, node); var at = 0; var answer = false;
    while at < work.len {
        let current = work[at]; at += 1; let n: const Node& = p.nodes[current];
        if n.kind == N_NAME && n.symbol == symbol { answer = true; break; }
        life_read_child(l, work, n.next);
        if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE || n.kind == N_IMPORT { continue; }
        for child in [n.first, n.left, n.right, n.third] { life_read_child(l, work, child); }
        if n.kind == N_CALL && n.symbol >= 0 && (p.symbols[n.symbol].flags & S_BUILTIN) == 0 && (p.symbols[symbol].flags & (S_CAPTURE | S_GLOBAL)) != 0 {
            let function_node = p.symbols[n.symbol].node;
            if function_node >= 0 && function_node != p.symbols[symbol].owner { life_read_child(l, work, p.nodes[function_node].right); }
        }
    }
    let index = l.reads.len; l.reads.push(LifeRead { node: node, symbol: symbol, answer: answer, next: l.read_heads[bucket] }); l.read_heads[bucket] = index;
    return answer;
}

// Whether a function's body may read a captured binding: life_reads' walk,
// following every call, finds a name of one. A superset of what life_reads
// visits for any captured symbol, so false answers every such query.
fn life_reads_captures(p: Program&, l: Lifetimes&, function_node: i64) -> bool {
    while l.capture_reads.len < p.nodes.len { l.capture_reads.push(0); }
    if l.capture_reads[function_node] != 0 { return l.capture_reads[function_node] == 2; }
    l.visit += 1; var work: i64[>..] = []; life_read_child(l, work, p.nodes[function_node].right); var at = 0; var answer = false;
    while at < work.len {
        let current = work[at]; at += 1; let n: const Node& = p.nodes[current];
        if n.kind == N_NAME && n.symbol >= 0 && n.symbol < p.symbols.len && (p.symbols[n.symbol].flags & S_CAPTURE) != 0 { answer = true; break; }
        life_read_child(l, work, n.next);
        if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE || n.kind == N_IMPORT { continue; }
        for child in [n.first, n.left, n.right, n.third] { life_read_child(l, work, child); }
        if n.kind == N_CALL && n.symbol >= 0 && (p.symbols[n.symbol].flags & S_BUILTIN) == 0 {
            let callee = p.symbols[n.symbol].node;
            if callee >= 0 { life_read_child(l, work, p.nodes[callee].right); }
        }
    }
    if answer { l.capture_reads[function_node] = 2; } else { l.capture_reads[function_node] = 1; }
    return answer;
}
// Whether a function's body reads a global: life_reads of its body for that
// symbol. A global has no owner function, so life_reads follows every call
// the same way for each global; one walk per function collects them all.
fn life_reads_global(p: Program&, l: Lifetimes&, function_node: i64, symbol: i64) -> bool {
    while l.global_read_spans.len < p.nodes.len { l.global_read_spans.push(LifeSet { first: 0, count: -1 }); }
    if l.global_read_spans[function_node].count < 0 {
        let first = l.global_read_list.len;
        l.visit += 1; var work: i64[>..] = []; life_read_child(l, work, p.nodes[function_node].right); var at = 0;
        while at < work.len {
            let current = work[at]; at += 1; let n: const Node& = p.nodes[current];
            if n.kind == N_NAME && n.symbol >= 0 && n.symbol < p.symbols.len && (p.symbols[n.symbol].flags & S_GLOBAL) != 0 { l.global_read_list.push(n.symbol); }
            life_read_child(l, work, n.next);
            if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE || n.kind == N_IMPORT { continue; }
            for child in [n.first, n.left, n.right, n.third] { life_read_child(l, work, child); }
            if n.kind == N_CALL && n.symbol >= 0 && (p.symbols[n.symbol].flags & S_BUILTIN) == 0 {
                let callee = p.symbols[n.symbol].node;
                if callee >= 0 { life_read_child(l, work, p.nodes[callee].right); }
            }
        }
        l.global_read_list[first..l.global_read_list.len].sort();
        var kept = first;
        for index in first..l.global_read_list.len {
            if index == first || l.global_read_list[index] != l.global_read_list[kept - 1] { l.global_read_list[kept] = l.global_read_list[index]; kept += 1; }
        }
        l.global_read_list.resize(kept, 0);
        l.global_read_spans[function_node] = LifeSet { first: first, count: kept - first };
    }
    let span = l.global_read_spans[function_node];
    var low = span.first; var high = span.first + span.count;
    while low < high {
        let middle = (low + high) / 2; let value = l.global_read_list[middle];
        if value == symbol { return true; }
        if value < symbol { low = middle + 1; } else { high = middle; }
    }
    return false;
}
fn life_in_scope(l: Lifetimes&, scope: i64, parent: i64) -> bool {
    var at = scope;
    while at >= 0 { if at == parent { return true; } if at == 0 { break; } at = l.parents[at]; }
    return false;
}
fn life_used_after(p: Program&, l: Lifetimes&, cell: LifeCell) -> bool {
    for index in 0..l.future_count {
        let future = l.futures[index];
        if future.loop_scope >= 0 && p.symbols[cell.symbol].scope != future.loop_scope && life_in_scope(l, p.symbols[cell.symbol].scope, future.loop_scope) { continue; }
        let saved = l.frame; l.frame = future.frame;
        let frame = life_frame_for(p, l, cell.symbol); l.frame = saved;
        if frame == cell.frame && life_reads(p, l, future.node, cell.symbol) { return true; }
    }
    return false;
}
fn life_alias(l: Lifetimes&, a: LifeAlt, b: LifeAlt) -> bool {
    if a.root == 0 || b.root == 0 { return false; }
    // Two known components of one root owner are separate storage.
    if a.root == b.root { return !(a.exact && b.exact && a.component >= 0 && b.component >= 0 && a.component != b.component); }
    if !a.exact && l.roots[a.root].depth >= l.roots[b.root].depth { return true; }
    if !b.exact && l.roots[b.root].depth >= l.roots[a.root].depth { return true; }
    return false;
}
fn life_overlaps(l: Lifetimes&, a: i64, b: i64, slot_safe: bool = false) -> bool {
    var ai = l.sets[a].first;
    while ai >= 0 {
        let x = l.alts[ai]; var bi = l.sets[b].first;
        while bi >= 0 {
            let y = l.alts[bi];
            if !(slot_safe && x.slotread) && life_alias(l, x, y) { return true; }
            bi = y.next;
        }
        ai = x.next;
    }
    return false;
}
fn life_holder_views(p: Program&, l: Lifetimes&, holder: i64, element: i64) -> bool {
    if holder < 0 || element < 0 { return false; }
    var work: i64[>..] = [holder]; var at = 0;
    while at < work.len {
        let t: const Type& = p.types[work[at]]; at += 1;
        if t.kind == TY_REF || t.kind == TY_SLICE {
            // The holder's own slot; slots inside what it views are that
            // storage's, which storing the holder does not copy.
            if t.kind == TY_REF && t.length_storage >= 0 { continue; }
            if life_contains(p, l, element, t.element) { return true; }
        } else if t.kind == TY_ARRAY && t.element >= 0 {
            var seen = false; for old in work { if old == t.element { seen = true; } }
            if !seen { work.push(t.element); }
        } else if t.kind == TY_STRUCT || t.kind == TY_ENUM || t.kind == TY_TUPLE {
            var field = t.first;
            while field >= 0 {
                let ft = p.nodes[field].type_id; var seen = ft < 0;
                for old in work { if old == ft { seen = true; } }
                if !seen { work.push(ft); }
                field = p.nodes[field].next;
            }
        }
    }
    return false;
}
fn life_points_into(p: Program&, l: Lifetimes&, value: LifeValue, places: i64, array: i64) -> bool {
    if array < 0 || value.type_id < 0 { return false; }
    let t: const Type& = p.types[value.type_id]; let a: const Type& = p.types[array];
    let slot_safe = a.array_kind == A_GROWSHRINK;
    if life_is_ref(p, value.type_id) {
        if (life_has_bytes(l, value.refs) || life_contains(p, l, a.element, t.element)) && life_overlaps(l, value.refs, places, slot_safe) { return true; }
        if life_holds(p, t.element) && life_held_into(p, l, value.refs, t.element, places, a.element, slot_safe) { return true; }
    } else if life_holds(p, value.type_id) {
        if value.place != 0 { return life_held_into(p, l, value.place, value.type_id, places, a.element, slot_safe); }
        return life_overlaps(l, value.contents, places, slot_safe);
    }
    return false;
}
fn life_has_bytes(l: Lifetimes&, set: i64) -> bool {
    var at = l.sets[set].first;
    while at >= 0 { if l.alts[at].byteview { return true; } at = l.alts[at].next; }
    return false;
}
fn life_held_into(p: Program&, l: Lifetimes&, owners: i64, holder_type: i64, target: i64, element: i64, slot_safe: bool) -> bool {
    var work: LifeWalk[>..] = []; var at = l.sets[owners].first;
    while at >= 0 { let alt = l.alts[at]; work.push(LifeWalk { root: alt.root, type_id: holder_type }); at = alt.next; }
    var current = 0;
    while current < work.len {
        let held = work[current]; current += 1; if held.type_id < 0 { continue; }
        let root = l.roots[held.root]; var types: i64[>..] = [held.type_id]; var ti = 0;
        while ti < types.len {
            let ty = types[ti]; ti += 1; let t: const Type& = p.types[ty];
            if t.kind == TY_REF || t.kind == TY_SLICE {
                if t.kind == TY_REF && t.length_storage >= 0 { continue; }
                var ai = l.sets[root.live_contents].first;
                while ai >= 0 {
                    let alt = l.alts[ai]; ai = alt.next; let storage = l.roots[alt.root];
                    if !alt.byteview && (!life_contains(p, l, storage.type_id, t.element) || alt.target_type >= 0 && !life_same(p, alt.target_type, t.element)) { continue; }
                    if (alt.byteview || life_contains(p, l, element, t.element)) &&
                       life_overlaps(l, life_single(l, alt.root, alt.exact, alt.from, alt.slotread, alt.byteview, -1, alt.bound, alt.component), target, slot_safe) { return true; }
                    if life_holds(p, t.element) {
                        var seen = false; for old in work { if old.root == alt.root && old.type_id == t.element { seen = true; } }
                        if !seen { work.push(LifeWalk { root: alt.root, type_id: t.element }); }
                    }
                }
            } else if t.kind == TY_ARRAY && t.element >= 0 {
                var seen = false; for old in types { if old == t.element { seen = true; } }
                if !seen { types.push(t.element); }
            } else if t.kind == TY_STRUCT || t.kind == TY_ENUM || t.kind == TY_TUPLE {
                var field = t.first;
                while field >= 0 {
                    let ft = p.nodes[field].type_id; var seen = ft < 0;
                    if ty == held.type_id && life_same(p, root.type_id, held.type_id) {
                        for kill in l.kills { if kill.active && kill.root == held.root && kill.field == field { seen = true; } }
                    }
                    for old in types { if old == ft { seen = true; } }
                    if !seen { types.push(ft); } field = p.nodes[field].next;
                }
            }
        }
    }
    return false;
}

fn life_same_path(p: Program&, left: i64, right: i64) -> bool {
    var a = left; var b = right;
    while a >= 0 && b >= 0 {
        if p.nodes[a].kind == N_UNARY && (p.nodes[a].integer == T_MUL || p.nodes[a].integer == T_BITAND) { a = p.nodes[a].left; continue; }
        if p.nodes[b].kind == N_UNARY && (p.nodes[b].integer == T_MUL || p.nodes[b].integer == T_BITAND) { b = p.nodes[b].left; continue; }
        let x: const Node& = p.nodes[a]; let y: const Node& = p.nodes[b];
        if x.kind == N_NAME && y.kind == N_NAME && x.symbol == y.symbol && x.symbol >= 0 {
            let symbol: const Symbol& = p.symbols[x.symbol];
            return !life_is_ref(p, symbol.type_id) || (symbol.flags & S_MUTABLE) == 0;
        }
        if x.kind != N_MEMBER || y.kind != N_MEMBER || x.symbol != y.symbol || life_is_ref(p, x.type_id) || life_is_ref(p, y.type_id) { return false; }
        a = x.left; b = y.left;
    }
    return false;
}
fn life_balanced(p: Program&, l: Lifetimes&, node: i64) -> bool {
    let n: const Node& = p.nodes[node]; if n.kind != N_CALL || n.symbol < 0 || p.symbols[n.symbol].index != 28 || n.first < 0 { return false; }
    let count = p.nodes[n.first].next;
    if count < 0 || p.nodes[count].kind != N_NAME || p.nodes[count].symbol < 0 { return false; }
    let symbol = p.nodes[count].symbol; let mark: const Symbol& = p.symbols[symbol];
    if (mark.flags & S_MUTABLE) != 0 || mark.owner != l.frames[l.frame].function_node || mark.node < 0 { return false; }
    let decl: const Node& = p.nodes[mark.node]; let initializer = decl.right;
    if initializer < 0 { return false; }
    let value: const Node& = p.nodes[initializer]; var path = -1;
    if value.kind == N_MEMBER && token_is(p, value.token, "len") { path = value.left; }
    if value.kind == N_CALL && value.symbol >= 0 && (p.symbols[value.symbol].flags & S_BUILTIN) != 0 && p.symbols[value.symbol].index == 21 { path = value.first; }
    if !life_same_path(p, n.first, path) { return false; }
    var work: i64[>..] = [p.nodes[l.frames[l.frame].function_node].right]; var at = 0;
    while at < work.len {
        let op: const Node& = p.nodes[work[at]]; at += 1;
        if op.left >= 0 && p.nodes[op.left].symbol == symbol && (op.kind == N_ASSIGN || op.kind == N_UNARY && op.integer == T_BITAND && op.type_id >= 0 && (p.types[op.type_id].flags & TF_CONST) == 0) { return false; }
        if op.kind == N_CALL && op.symbol >= 0 && (p.symbols[op.symbol].flags & S_BUILTIN) == 0 && p.symbols[op.symbol].node >= 0 {
            var argument = op.first; var parameter = p.nodes[p.symbols[op.symbol].node].first;
            while argument >= 0 && parameter >= 0 {
                let ty = p.nodes[parameter].type_id;
                if p.nodes[argument].kind == N_NAME && p.nodes[argument].symbol == symbol && ty >= 0 && p.types[ty].kind == TY_REF && (p.types[ty].flags & TF_CONST) == 0 { return false; }
                argument = p.nodes[argument].next; parameter = p.nodes[parameter].next;
            }
        }
        var child = op.first; while child >= 0 { work.push(child); child = p.nodes[child].next; }
        for child in [op.left, op.right, op.third] { if child >= 0 { work.push(child); } }
    }
    return true;
}

fn life_index_shrink(p: Program&, l: Lifetimes&, node: i64, receiver: LifeValue) {
    if l.discovery { return; }
    for t in p.types {
        if t.kind != TY_INT || t.index_type < 0 || t.pool < 0 { continue; }
        let owner: const Symbol& = p.symbols[t.pool]; let named = life_pool_places(p, l, t.pool);
        if named == 0 || !life_same(p, receiver.type_id, owner.type_id) { continue; }
        if life_overlaps(l, receiver.place, named) {
            life_error(p, l, node, "cannot shrink or replace this array: an index or bound type names it"); return;
        }
    }
}

fn life_shrink_array(p: Program&, l: Lifetimes&, node: i64, receiver: LifeValue, balanced: bool = false) {
    if receiver.type_id < 0 { return; }
    let array: const Type& = p.types[receiver.type_id];
    if array.kind != TY_ARRAY || array.array_kind == A_LIMITED { return; }
    life_index_shrink(p, l, node, receiver);
    if !balanced { life_effect(l, LifeEffect { kind: 1, node: node, value: receiver, places: receiver.place }); }
    if l.discovery { return; }
    var pool = l.sets[receiver.place].first;
    while pool >= 0 {
        let root = l.roots[l.alts[pool].root];
        if root.symbol >= 0 {
            let symbol: const Symbol& = p.symbols[root.symbol];
            if symbol.node >= 0 && (p.nodes[symbol.node].flags & F_REUSABLE) != 0 {
                life_error(p, l, node, "reusable pool storage cannot shrink: freed slots remain part of its freelist");
            }
        }
        pool = l.alts[pool].next;
    }
    for index in 0..l.hold_count {
        let hold = l.holds[index]; if balanced && hold.frame != l.frame { continue; } var conflict = false;
        if hold.kind == 7 {
            var ty = hold.value.type_id; var places = hold.value.place;
            if ty >= 0 && p.types[ty].kind == TY_REF { places = hold.value.refs; ty = p.types[ty].element; }
            conflict = life_points_into(p, l, hold.value, receiver.place, receiver.type_id);
            var walk = false;
            if ty >= 0 { walk = p.types[ty].kind == TY_ENUM && (p.types[ty].flags & F_VARIABLE_MODE) != 0 || p.types[ty].kind == TY_ARRAY && life_cached_size_class(p, l, ty) > 0; }
            if walk && (life_contains(p, l, array.element, ty) || life_contains(p, l, ty, receiver.type_id)) && life_overlaps(l, places, receiver.place) { conflict = true; }
        }
        else if hold.kind == 4 { conflict = life_contains(p, l, array.element, hold.value.type_id) && life_overlaps(l, hold.value.place, receiver.place); }
        else if hold.kind != 0 { conflict = life_overlaps(l, hold.value.place, receiver.place);
            if hold.kind == 3 { conflict = conflict || life_points_into(p, l, hold.value, receiver.place, receiver.type_id); }
        }
        else { conflict = life_points_into(p, l, hold.value, receiver.place, receiver.type_id); }
        if conflict { life_error(p, l, node, "array shrink invalidates a value still needed by the enclosing expression"); }
    }
    for cell in l.cells {
        if !cell.live || balanced && (cell.frame != l.frame || (p.symbols[cell.symbol].flags & S_PARAMETER) != 0) { continue; }
        let value = LifeValue { type_id: p.symbols[cell.symbol].type_id, place: life_root_set(l, cell.root), refs: cell.live_refs, contents: l.roots[cell.root].live_contents };
        if life_points_into(p, l, value, receiver.place, receiver.type_id) && life_used_after(p, l, cell) {
            life_error(p, l, node, "array shrink invalidates a reference or holder that is used afterward");
        }
    }
}
fn life_shrink(p: Program&, l: Lifetimes&, node: i64, receiver: LifeValue, balanced: bool = false) {
    if receiver.type_id < 0 { return; }
    var work: i64[>..] = [receiver.type_id]; var at = 0;
    while at < work.len {
        let ty = work[at]; at += 1; let t: const Type& = p.types[ty];
        if t.kind == TY_ARRAY { var value = receiver; value.type_id = ty; life_shrink_array(p, l, node, value, balanced); }
        else if t.kind == TY_STRUCT || t.kind == TY_ENUM {
            var field = t.first;
            while field >= 0 { let ft = p.nodes[field].type_id; if ft >= 0 && life_cached_size_class(p, l, ft) > 0 { work.push(ft); } field = p.nodes[field].next; }
        }
    }
}

fn life_replace(p: Program&, l: Lifetimes&, node: i64, receiver: LifeValue) {
    life_effect(l, LifeEffect { kind: 8, node: node, value: receiver, places: receiver.place });
    if l.discovery { return; }
    for index in 0..l.hold_count {
        let hold = l.holds[index]; if hold.kind != 7 { continue; }
        var ty = hold.value.type_id; var places = hold.value.place;
        if ty >= 0 && p.types[ty].kind == TY_REF { places = hold.value.refs; ty = p.types[ty].element; }
        var walk = false;
        if ty >= 0 { walk = p.types[ty].kind == TY_ENUM && (p.types[ty].flags & F_VARIABLE_MODE) != 0 || p.types[ty].kind == TY_ARRAY && life_cached_size_class(p, l, ty) > 0; }
        if walk && life_overlaps(l, places, receiver.place) && (life_contains(p, l, receiver.type_id, ty) || life_contains(p, l, ty, receiver.type_id)) {
            life_error(p, l, node, "whole assignment replaces a variable-size value while its parts are being rendered");
        }
    }
}

fn life_grow(p: Program&, l: Lifetimes&, node: i64, receiver: LifeValue) {
    life_effect(l, LifeEffect { kind: 2, node: node, value: receiver, places: receiver.place });
    if l.discovery { return; }
    for index in 0..l.hold_count {
        let hold = l.holds[index];
        if (hold.kind == 1 || hold.kind == 2) && life_overlaps(l, hold.value.place, receiver.place) {
            life_error(p, l, node, "array growth overlaps a value still under construction in its storage");
        }
    }
}
fn life_construct_read(p: Program&, l: Lifetimes&, node: i64, value: LifeValue) {
    if l.reading_place > 0 { return; }
    var effect_places = value.place; if life_is_ref(p, value.type_id) { effect_places = value.refs; }
    var effect_type = value.type_id; if effect_type >= 0 && p.types[effect_type].kind == TY_REF { effect_type = p.types[effect_type].element; }
    if value.element_array != -1 || life_cached_size_class(p, l, effect_type) == 2 { life_effect(l, LifeEffect { kind: 3, node: node, value: value, places: effect_places }); }
    if l.discovery { return; }
    var places = value.place;
    if value.type_id >= 0 && p.types[value.type_id].kind == TY_REF { places = value.refs; }
    for index in 0..l.hold_count {
        let hold = l.holds[index];
        var type_id = value.type_id;
        if type_id >= 0 && p.types[type_id].kind == TY_REF { type_id = p.types[type_id].element; }
        var element_read = value.element_array != -1;
        if value.element_array >= 0 && hold.value.type_id >= 0 && p.types[hold.value.type_id].kind == TY_ARRAY {
            element_read = life_same(p, value.element_array, hold.value.type_id) || life_contains(p, l, p.types[hold.value.type_id].element, value.element_array);
        }
        if hold.kind == 2 && life_overlaps(l, hold.value.place, places) &&
           (element_read || life_contains(p, l, type_id, hold.value.type_id) || life_cached_size_class(p, l, type_id) > 0 && life_contains(p, l, hold.value.type_id, type_id)) {
            life_error(p, l, node, "whole assignment reads storage while its replacement is being constructed");
        }
    }
}
fn life_coerce(p: Program&, l: Lifetimes&, value: LifeValue, expected: i64) -> LifeValue {
    var out = value;
    if expected < 0 || expected == TYPE_VOID { return out; }
    if value.type_id >= 0 && p.types[value.type_id].kind == TY_SLICE && p.types[expected].kind == TY_REF && p.types[expected].element >= 0 && p.types[p.types[expected].element].kind == TY_SLICE {
        out.refs = value.place; out.type_id = expected; return out;
    }
    if value.type_id >= 0 && p.types[value.type_id].kind == TY_REF && p.types[value.type_id].element >= 0 &&
       p.types[p.types[value.type_id].element].kind == TY_SLICE && p.types[expected].kind == TY_SLICE {
        out = life_load(p, l, expected, value.refs); return out;
    }
    if p.types[expected].kind == TY_SLICE && value.type_id >= 0 && p.types[value.type_id].kind == TY_REF && p.types[value.type_id].element >= 0 && p.types[p.types[value.type_id].element].kind == TY_ARRAY {
        out.refs = life_interior(l, value.refs);
    }
    if life_is_ref(p, expected) && !life_is_ref(p, value.type_id) {
        out.refs = value.place;
        if p.types[expected].kind == TY_SLICE { out.refs = life_interior(l, out.refs); }
    }
    if !life_is_ref(p, expected) && life_is_ref(p, value.type_id) { out.place = value.refs; out.refs = 0; }
    out.type_id = expected;
    return out;
}
fn life_candidates(p: Program&, l: Lifetimes&, pointee: i64, depth: i64, globals: bool) -> i64 {
    var out = 0;
    for cell in l.cells {
        let root = l.roots[cell.root];
        if !cell.live || root.depth > depth || globals && (p.symbols[cell.symbol].flags & S_GLOBAL) == 0 { continue; }
        if life_contains(p, l, root.type_id, pointee) { out = life_join(l, out, life_root_set(l, cell.root)); }
        if life_is_ref(p, root.type_id) && life_contains(p, l, p.types[root.type_id].element, pointee) {
            var at = l.sets[cell.refs].first;
            while at >= 0 {
                let alt = l.alts[at];
                if l.roots[alt.root].depth <= depth { out = life_join(l, out, life_single(l, alt.root, alt.exact, alt.from, false, false, -1, alt.bound)); }
                at = alt.next;
            }
        }
    }
    return out;
}
fn life_class_candidates(p: Program&, l: Lifetimes&, owner: i64, pointee: i64) -> i64 {
    var through_parameter = false; var ci = l.frames[l.frame].first_cell;
    while ci >= 0 {
        let cell = l.cells[ci];
        if cell.parameter && life_find(l, cell.refs, owner) >= 0 { through_parameter = true; break; }
        ci = cell.next_frame;
    }
    if !through_parameter { return 0; }
    var result = 0; ci = l.frames[l.frame].first_cell;
    while ci >= 0 {
        let cell = l.cells[ci]; let ty = p.symbols[cell.symbol].type_id;
        if cell.parameter && ty >= 0 && p.types[ty].kind == TY_REF && life_contains(p, l, p.types[ty].element, pointee) {
            var at = l.sets[cell.refs].first;
            while at >= 0 { let alt = l.alts[at]; if l.roots[alt.root].depth <= l.roots[owner].depth { result = life_join(l, result, life_single(l, alt.root, alt.exact, -1, false, false, -1, alt.bound, alt.component)); } at = alt.next; }
        }
        ci = cell.next_frame;
    }
    return result;
}

// The storage a pool or index type names: a global's root, or a named
// component of a global root owner.
fn life_pool_places(p: Program&, l: Lifetimes&, pool: i64) -> i64 {
    if pool < 0 || pool >= p.symbols.len { return 0; }
    let owner = p.symbols[pool].component_owner;
    if owner >= 0 {
        let cell = life_cell(p, l, owner); if cell < 0 || p.symbols[pool].component < 0 { return 0; }
        return life_component(l, life_root_set(l, l.cells[cell].root), p.symbols[pool].component);
    }
    let cell = life_cell(p, l, pool); if cell < 0 { return 0; }
    return life_root_set(l, l.cells[cell].root);
}
fn life_readback(p: Program&, l: Lifetimes&, type_id: i64, places: i64) -> i64 {
    if !life_is_ref(p, type_id) { return 0; }
    let t: const Type& = p.types[type_id];
    if t.kind == TY_REF && t.length_storage >= 0 {
        let pool = life_pool_places(p, l, t.pool); if pool != 0 { return pool; }
        return places;
    }
    var result = 0; var at = l.sets[places].first;
    while at >= 0 {
        let alt = l.alts[at]; let root = l.roots[alt.root];
        let global = root.symbol >= 0 && (p.symbols[root.symbol].flags & S_GLOBAL) != 0;
        var known = alt.exact && !global;
        var source = root.contents;
        if t.kind == TY_REF && t.element >= 0 && (p.types[t.element].kind == TY_ARRAY || p.types[t.element].kind == TY_STRUCT || p.types[t.element].kind == TY_ENUM) {
            source = life_join(l, source, life_class_candidates(p, l, alt.root, t.element));
        }
        if !known { source = life_candidates(p, l, t.element, root.depth, global); }
        var item = l.sets[source].first;
        while item >= 0 {
            let r = l.alts[item]; let owner = l.roots[r.root];
            if (r.target_type < 0 || life_same(p, r.target_type, t.element)) && (r.root == 0 || r.byteview || !r.exact || life_contains(p, l, owner.type_id, t.element)) {
                var slotread = true;
                if root.type_id >= 0 && life_is_ref(p, root.type_id) { slotread = r.slotread; }
                var bound = r.bound;
                // Caller storage bounds a read-back's lifetime, while the
                // actual referent remains available for alias/shrink checks.
                if alt.bound > bound { bound = alt.bound; }
                result = life_join(l, result, life_single(l, r.root, r.exact, alt.root, slotread, r.byteview, r.target_type, bound, r.component));
            }
            item = r.next;
        }
        at = alt.next;
    }
    return result;
}
fn life_load(p: Program&, l: Lifetimes&, type_id: i64, places: i64, slot: bool = false) -> LifeValue {
    var out = LifeValue { type_id: type_id, place: places };
    out.contents = life_contents(l, places); if !l.discovery { out.contents = life_live_contents(l, places); }
    if life_is_ref(p, type_id) { out.refs = life_readback(p, l, type_id, places); }
    if !life_holds(p, type_id) { out.contents = 0; }
    else if !life_is_ref(p, type_id) {
        var at = l.sets[places].first;
        while at >= 0 {
            let alt = l.alts[at]; let root = l.roots[alt.root];
            if root.symbol >= 0 && (p.symbols[root.symbol].flags & (S_GLOBAL | S_MUTABLE)) == (S_GLOBAL | S_MUTABLE) {
                out.contents = life_join(l, out.contents, life_single(l, alt.root, false, -1, slot, false, -1, alt.bound));
            }
            at = alt.next;
        }
        if slot {
            var contents = 0; at = l.sets[out.contents].first;
            while at >= 0 { let alt = l.alts[at]; contents = life_join(l, contents, life_single(l, alt.root, alt.exact, alt.from, true, alt.byteview, alt.target_type, alt.bound, alt.component)); at = alt.next; }
            out.contents = contents;
        }
    }
    return out;
}
fn life_add_contents(l: Lifetimes&, root: i64, sources: i64) {
    let next = life_join(l, l.roots[root].contents, sources);
    if !life_equal(l, next, l.roots[root].contents) { l.roots[root].contents = next; l.revision += 1; }
    if sources != 0 { life_effect(l, LifeEffect { kind: 4, node: -1, value: LifeValue { contents: sources }, places: life_root_set(l, root) }); }
    if !l.discovery {
        l.roots[root].live_contents = life_join(l, l.roots[root].live_contents, sources);
        if sources != 0 { for kill, index in l.kills { if kill.root == root { l.kills[index].active = false; } } }
    }
}
fn life_stored_roots(p: Program&, l: Lifetimes&, value: LifeValue) -> i64 {
    let sources = life_value_roots(p, value);
    if !life_is_ref(p, value.type_id) { return sources; }
    var contents = 0; var at = l.sets[sources].first;
    while at >= 0 {
        let alt = l.alts[at];
        contents = life_join(l, contents, life_single(l, alt.root, alt.exact, alt.from, alt.slotread, alt.byteview, p.types[value.type_id].element, alt.bound, alt.component));
        at = alt.next;
    }
    return contents;
}

fn life_cyclic(p: Program&, l: Lifetimes&, frame: i64) -> bool {
    return frame > 0 && (l.frames[frame].recursive_call || (p.nodes[l.frames[frame].function_node].flags & F_RECURSIVE) != 0);
}

// A pooled self offset constrains construction, not the lifetime of later
// reads or copies of that encoded value. Keep this proof on fresh values only.
fn life_self_destination(p: Program&, l: Lifetimes&, node: i64, places: i64, pools: i64) {
    var at = l.sets[pools].first;
    while at >= 0 {
        let pool = l.alts[at]; var inside = l.sets[places].count == 1;
        if inside { let place = l.alts[l.sets[places].first]; inside = pool.exact && place.exact && pool.root == place.root && pool.component == place.component; }
        if !inside { life_error(p, l, node, "pool-relative self must be constructed directly inside its named pool"); }
        at = pool.next;
    }
}

fn life_relative_store(p: Program&, l: Lifetimes&, node: i64, places: i64, value: LifeValue) {
    if value.type_id >= 0 && p.types[value.type_id].kind == TY_REF && p.types[value.type_id].length_storage >= 0 && value.refs != 0 {
        if p.types[value.type_id].pool < 0 && places == 0 { return; }
        var target = places;
        let pool = p.types[value.type_id].pool;
        let named = life_pool_places(p, l, pool); if named != 0 { target = named; }
        var same = l.sets[target].count == 1 && l.sets[value.refs].count == 1;
        if same {
            let a = l.alts[l.sets[target].first]; let b = l.alts[l.sets[value.refs].first];
            same = a.exact && b.exact && a.root == b.root && a.component == b.component;
        }
        if !same { life_error(p, l, node, "relative reference must point into the exact root that owns its destination"); }
    }
}

fn life_store(p: Program&, l: Lifetimes&, node: i64, places: i64, value: LifeValue, binding: bool = false, through: bool = false) {
    life_self_destination(p, l, node, places, value.self_pools);
    life_self_destination(p, l, node, places, value.relative_roots);
    var sources = life_value_roots(p, value);
    if binding && life_is_ref(p, value.type_id) { sources = value.refs; }
    if !binding {
        life_relative_store(p, l, node, places, value);
        if value.type_id >= 0 && p.types[value.type_id].kind == TY_REF && p.types[value.type_id].length_storage >= 0 {
            life_effect(l, LifeEffect { kind: 9, node: node, value: value, places: places });
        }
    }
    var destination = l.sets[places].first;
    while destination >= 0 {
        let d = l.alts[destination]; let owner = l.roots[d.root];
        let global = owner.symbol >= 0 && (p.symbols[owner.symbol].flags & S_GLOBAL) != 0;
        if (!binding || global || through) && life_gs_value(p, l, value) {
            life_error(p, l, node, "reference into grow-shrink elements cannot be stored in a field, element, or global");
        }
        var at = l.sets[sources].first;
        while at >= 0 {
            let source = l.alts[at];
            let source_frame = l.roots[source.root].frame;
            if life_cyclic(p, l, l.frame) && !(binding && owner.frame == l.frame) && source.root != 0 && source_frame > 0 &&
               (source_frame == l.frame || life_cyclic(p, l, source_frame)) {
                life_error(p, l, node, "reference stored by a recursive cycle must be rooted outside every recursive activation");
            }
            if l.roots[source.root].depth > owner.depth {
                life_scope_error(p, l, node, "stored reference does not outlive the storage that receives it");
            }
            at = source.next;
        }
        if binding && owner.symbol >= 0 && life_is_ref(p, p.symbols[owner.symbol].type_id) {
            let cell = life_cell(p, l, owner.symbol);
            if cell >= 0 {
                // Revisited declarations start a fresh destination binding;
                // the source's caller-storage constraint remains in sources.
                if p.nodes[node].kind == N_VARIABLE || p.nodes[node].kind == N_BINDING {
                    l.cells[cell].committed = false; l.cells[cell].initial = 0;
                }
                var added = false; at = l.sets[sources].first;
                while at >= 0 {
                    let source = l.alts[at]; let previous = life_find(l, l.cells[cell].initial, source.root);
                    if previous < 0 || source.bound != l.alts[previous].bound { added = true; }
                    at = source.next;
                }
                if sources != 0 && added {
                    let growshrink = life_gs_value(p, l, value);
                    if l.cells[cell].committed && !l.cells[cell].growshrink && growshrink { life_error(p, l, node, "reference binding cannot start pointing into grow-shrink elements after its first binding"); }
                    if !l.cells[cell].committed { l.cells[cell].growshrink = growshrink; }
                    let depth = life_binding_depth(l, sources);
                    if l.cells[cell].committed && depth != l.cells[cell].depth {
                        life_scope_error(p, l, node, "reference or slice binding changes its committed root lifetime depth");
                    }
                    if !l.cells[cell].committed { l.cells[cell].committed = true; l.cells[cell].depth = depth; l.cells[cell].initial = sources; }
                }
                let next = life_join(l, l.cells[cell].refs, sources);
                if !life_equal(l, next, l.cells[cell].refs) { l.cells[cell].refs = next; l.revision += 1; }
                life_effect(l, LifeEffect { kind: 5, node: node, value: LifeValue { refs: sources }, places: life_root_set(l, l.cells[cell].root), cell: cell });
                if !l.discovery {
                    l.cells[cell].live_refs = life_join(l, l.cells[cell].live_refs, sources);
                }
            }
        }
        life_add_contents(l, d.root, life_stored_roots(p, l, value));
        destination = d.next;
    }
}
fn life_item(l: Lifetimes&, first: i64, index: i64) -> LifeValue {
    var at = first; var i = 0;
    while at >= 0 { if i == index { return l.items[at].value; } at = l.items[at].next; i += 1; }
    return LifeValue {};
}
fn life_append(l: Lifetimes&, first: i64, value: LifeValue) -> i64 {
    let item = l.items.len; l.items.push(LifeItem { value: value });
    if first < 0 { return item; }
    var last = first; while l.items[last].next >= 0 { last = l.items[last].next; }
    l.items[last].next = item; return first;
}
fn life_control_destination(l: Lifetimes&, node: i64, destination: i64, selected_result: i64) {
    for exit, index in l.exits {
        if exit.node == node && exit.frame == l.frame { l.exits[index].destination = destination; l.exits[index].selected_result = selected_result; return; }
    }
    l.exits.push(LifeExit { node: node, frame: l.frame, value: LifeValue {}, destination: destination, selected_result: selected_result });
}
recursive fn life_merge(l: Lifetimes&, a: LifeValue, b: LifeValue) -> LifeValue {
    var out = a;
    if out.type_id < 0 { out.type_id = b.type_id; }
    out.refs = life_join(l, a.refs, b.refs); out.place = life_join(l, a.place, b.place);
    out.contents = life_join(l, a.contents, b.contents);
    out.self_pools = life_join(l, a.self_pools, b.self_pools);
    out.relative_roots = life_join(l, a.relative_roots, b.relative_roots);
    if b.tuple >= 0 {
        out.tuple = -1; var x = a.tuple; var y = b.tuple;
        while y >= 0 || x >= 0 {
            var av = LifeValue {}; var bv = LifeValue {};
            if x >= 0 { av = l.items[x].value; x = l.items[x].next; }
            if y >= 0 { bv = l.items[y].value; y = l.items[y].next; }
            out.tuple = life_append(l, out.tuple, life_merge(l, av, bv));
        }
    }
    return out;
}
fn life_branch(p: Program&, l: Lifetimes&, node: i64, value: LifeValue, depth: i64) {
    var at = l.sets[life_value_roots(p, value)].first;
    while at >= 0 {
        let root = l.roots[l.alts[at].root];
        var allowed = depth; if root.temporary { allowed += 1; }
        if root.depth > allowed { life_error(p, l, node, "control-flow value retains a reference into a scope that has ended"); }
        at = l.alts[at].next;
    }
}
recursive fn life_return_value(p: Program&, l: Lifetimes&, node: i64, value: LifeValue, target: i64) {
    var item = value.tuple;
    while item >= 0 { life_return_value(p, l, node, l.items[item].value, target); item = l.items[item].next; }
    var at = l.sets[life_value_roots(p, value)].first;
    while at >= 0 {
        let root = l.roots[l.alts[at].root];
        if root.depth >= l.frames[target].base && root.depth > 0 {
            life_scope_error(p, l, node, "returned reference points into this invocation's local or temporary storage");
        }
        at = l.alts[at].next;
    }
}
fn life_construct_value(p: Program&, l: Lifetimes&, node: i64, value: LifeValue, destination: i64) -> LifeValue {
    var out = value;
    if out.type_id < 0 { return out; }
    let kind = p.types[out.type_id].kind;
    if kind != TY_ARRAY && kind != TY_STRUCT && kind != TY_ENUM { return out; }
    out.place = destination; if out.place == 0 { out.place = life_temporary(p, l, node); }
    var at = l.sets[out.place].first;
    while at >= 0 { let alt = l.alts[at]; life_add_contents(l, alt.root, out.contents); at = alt.next; }
    return out;
}
fn life_arguments_equal(p: Program&, l: Lifetimes&, a: i64, b: i64) -> bool {
    var x = a; var y = b;
    while x >= 0 && y >= 0 {
        let av = l.items[x].value; let bv = l.items[y].value;
        if life_is_ref(p, av.type_id) && !life_equal(l, av.refs, bv.refs) { return false; }
        if !life_is_ref(p, av.type_id) && life_holds(p, av.type_id) && !life_equal(l, av.contents, bv.contents) { return false; }
        x = l.items[x].next; y = l.items[y].next;
    }
    return x == y;
}

fn life_root_class(p: Program&, l: Lifetimes&, a: LifeAlt, b: LifeAlt) -> bool {
    if a.exact != b.exact || a.slotread != b.slotread || a.byteview != b.byteview { return false; }
    let x = l.roots[a.root]; let y = l.roots[b.root];
    if a.root == 0 || b.root == 0 { return a.root == b.root; }
    if x.frame == 0 || y.frame == 0 { return a.root == b.root; }
    if x.temporary != y.temporary || !life_same(p, x.type_id, y.type_id) { return false; }
    if x.symbol >= 0 && (p.symbols[x.symbol].flags & S_CAPTURE) != 0 { return x.symbol == y.symbol; }
    if y.symbol >= 0 && (p.symbols[y.symbol].flags & S_CAPTURE) != 0 { return x.symbol == y.symbol; }
    return true;
}
fn life_class_sets_equal(p: Program&, l: Lifetimes&, a: i64, b: i64) -> bool {
    var ai = l.sets[a].first;
    while ai >= 0 {
        var found = false; var bi = l.sets[b].first;
        while bi >= 0 { if life_root_class(p, l, l.alts[ai], l.alts[bi]) { found = true; break; } bi = l.alts[bi].next; }
        if !found { return false; } ai = l.alts[ai].next;
    }
    var bi = l.sets[b].first;
    while bi >= 0 {
        var found = false; ai = l.sets[a].first;
        while ai >= 0 { if life_root_class(p, l, l.alts[ai], l.alts[bi]) { found = true; break; } ai = l.alts[ai].next; }
        if !found { return false; } bi = l.alts[bi].next;
    }
    return true;
}
fn life_root_relation(l: Lifetimes&, a: i64, b: i64) -> i64 {
    var shared = 0; var at = l.sets[a].first;
    while at >= 0 { if life_find(l, b, l.alts[at].root) >= 0 { shared += 1; } at = l.alts[at].next; }
    if shared == l.sets[a].count && shared == l.sets[b].count { return 2; }
    if shared > 0 { return 1; }
    return 0;
}
fn life_classes_equal(p: Program&, l: Lifetimes&, left: i64, right: i64) -> bool {
    var x = left; var y = right;
    while x >= 0 && y >= 0 {
        let a = life_value_roots(p, l.items[x].value); let b = life_value_roots(p, l.items[y].value);
        if !life_class_sets_equal(p, l, a, b) { return false; }
        var px = left; var py = right;
        while px != x && py != y {
            let ap = life_value_roots(p, l.items[px].value); let bp = life_value_roots(p, l.items[py].value);
            if life_root_relation(l, a, ap) != life_root_relation(l, b, bp) { return false; }
            if (life_set_depth(l, a) < life_set_depth(l, ap)) != (life_set_depth(l, b) < life_set_depth(l, bp)) ||
               (life_set_depth(l, a) == life_set_depth(l, ap)) != (life_set_depth(l, b) == life_set_depth(l, bp)) { return false; }
            px = l.items[px].next; py = l.items[py].next;
        }
        x = l.items[x].next; y = l.items[y].next;
    }
    return x == y;
}

fn life_clear_reads(l: Lifetimes&, roots: i64) -> i64 {
    var result = 0; var at = l.sets[roots].first;
    while at >= 0 { let alt = l.alts[at]; result = life_join(l, result, life_single(l, alt.root, alt.exact, -1, false, alt.byteview, alt.target_type, alt.bound, alt.component)); at = alt.next; }
    return result;
}
recursive fn life_cycle_value(l: Lifetimes&, value: LifeValue) -> LifeValue {
    var out = value; out.refs = life_clear_reads(l, value.refs); out.contents = life_clear_reads(l, value.contents); out.tuple = -1;
    var item = value.tuple;
    while item >= 0 { out.tuple = life_append(l, out.tuple, life_cycle_value(l, l.items[item].value)); item = l.items[item].next; }
    return out;
}

fn life_cycle_head(l: Lifetimes&, frame: i64) -> i64 {
    var head = frame;
    while head > 0 && l.frames[head].cycle >= 0 && l.frames[head].cycle != head { head = l.frames[head].cycle; }
    return head;
}
fn life_cycle_call(p: Program&, l: Lifetimes&, target: i64, call: i64, destination: i64) {
    var entry = -1; var at = l.frame; let target_head = life_cycle_head(l, target);
    while at > 0 {
        if at == target || l.frames[target].recursive_call && life_cycle_head(l, at) == target_head { entry = at; break; }
        at = l.frames[at].parent;
    }
    if entry >= 0 {
        var member = l.frame;
        while member > 0 {
            if !l.frames[member].recursive_call { l.frames[member].recursive_call = true; l.recursion_epoch += 1; l.revision += 1; }
            let a = life_cycle_head(l, member); let b = life_cycle_head(l, target);
            if a != b { if a < b { l.frames[b].cycle = a; } else { l.frames[a].cycle = b; } l.revision += 1; }
            if member == entry { break; } member = l.frames[member].parent;
        }
    }
    if l.discovery || l.frame <= 0 || !l.frames[target].recursive_call || life_cycle_head(l, l.frame) != life_cycle_head(l, target) { return; }
    var cell = l.frames[l.frame].first_cell;
    while cell >= 0 {
        let local = l.cells[cell];
        if local.live && life_cached_size_class(p, l, p.symbols[local.symbol].type_id) > 0 {
            life_error(p, l, call, "call into a recursive cycle keeps nonfixed local or parameter storage live across the call");
        }
        cell = local.next_frame;
    }
    for i in 0..l.temp_count {
        if l.temps[i].frame == l.frame { life_error(p, l, call, "call into a recursive cycle keeps a nonfixed temporary alive until the statement ends"); }
    }
    for i in 0..l.hold_count {
        if l.holds[i].frame == l.frame && l.holds[i].kind == 6 {
            life_error(p, l, call, "call into a recursive cycle occurs while a nonfixed value is under construction");
        }
    }
    if call >= 0 && life_cached_size_class(p, l, p.nodes[call].type_id) > 0 && life_equal(l, destination, l.frames[l.frame].destination) {
        let own: const Node& = p.nodes[l.frames[l.frame].function_node]; var expected = -1;
        if own.type_id >= 0 { expected = p.types[own.type_id].element; }
        var matches = life_same(p, expected, p.nodes[call].type_id);
        if expected >= 0 && p.types[expected].kind == TY_TUPLE {
            var part = p.types[expected].first;
            while part >= 0 { if life_same(p, p.nodes[part].type_id, p.nodes[call].type_id) { matches = true; } part = p.nodes[part].next; }
        }
        if !matches { life_error(p, l, call, "a recursive result converted to another nonfixed type needs temporary storage"); }
    }
    let fnnode: const Node& = p.nodes[l.frames[target].function_node];
    if fnnode.kind == N_FUNCTION && fnnode.left < 0 && fnnode.type_id >= 0 {
        let result = p.types[fnnode.type_id].element;
        if result >= 0 && p.types[result].kind == TY_REF {
            life_error(p, l, call, "a recursive cycle's reference result requires an explicit result type");
        }
    }
}

// The caller's storage bounds a parameter read unless this call owns a
// private view of the holder's known contents. Lexical/callback reach keeps
// possibly aliased holders on their storage class instead.
fn life_parameter_roots(p: Program&, l: Lifetimes&, sources: i64, type_id: i64, function_node: i64, lexical: i64) -> i64 {
    if type_id >= 0 && p.types[type_id].kind == TY_REF && p.types[type_id].element >= 0 && p.types[p.types[type_id].element].kind == TY_SLICE { return sources; }
    var reach = 0; var ci = l.frames[lexical].first_cell;
    while ci >= 0 {
        let cell = l.cells[ci]; if cell.live && l.roots[cell.root].depth > reach { reach = l.roots[cell.root].depth; }
        ci = cell.next_frame;
    }
    var view = false;
    if type_id >= 0 && p.types[type_id].kind == TY_REF && p.types[type_id].length_storage < 0 &&
       (p.nodes[function_node].flags & F_RECURSIVE) == 0 && l.sets[sources].count == 1 {
        let alt = l.alts[l.sets[sources].first]; let root = l.roots[alt.root]; let element = p.types[type_id].element;
        if root.depth > reach && (alt.exact || root.temporary) && element >= 0 {
            if life_holds(p, element) && !root.temporary && root.type_id >= 0 && !life_is_ref(p, root.type_id) && l.sets[root.contents].count == 1 {
                view = l.alts[l.sets[root.contents].first].exact;
            }
        }
    }
    if view { return sources; }
    var result = 0; var at = l.sets[sources].first;
    while at >= 0 {
        let alt = l.alts[at]; let depth = l.roots[alt.root].depth;
        result = life_join(l, result, life_bound(l, life_single(l, alt.root, alt.exact, alt.from, alt.slotread, alt.byteview, alt.target_type, alt.bound, alt.component), depth));
        at = alt.next;
    }
    return result;
}

recursive fn life_function(p: Program&, l: Lifetimes&, function_node: i64, call: i64, arguments: i64, destination: i64, selected_result: i64 = -1) -> LifeValue {
    if function_node < 0 || p.nodes[function_node].right < 0 { return LifeValue {}; }
    var lexical = 0;
    if p.nodes[function_node].symbol >= 0 {
        let owner = p.symbols[p.nodes[function_node].symbol].owner; var frame = l.frame;
        while frame > 0 { if l.frames[frame].function_node == owner { lexical = frame; break; } frame = l.frames[frame].parent; }
    }
    // A body that reads no captured binding, through any call, finds none in
    // an enclosing frame either.
    let reads_captures = life_reads_captures(p, l, function_node);
    var enclosing = l.frame; if p.nodes[function_node].captures < 0 && !reads_captures { enclosing = 0; }
    while enclosing > 0 {
        var captured = p.nodes[function_node].captures; var found = false;
        while captured >= 0 {
            let symbol = p.nodes[captured].symbol;
            if symbol >= 0 && p.symbols[symbol].owner == l.frames[enclosing].function_node { lexical = enclosing; found = true; break; }
            captured = p.nodes[captured].next;
        }
        if !found && reads_captures {
            var cell = l.frames[enclosing].first_cell;
            while cell >= 0 {
                let symbol = l.cells[cell].symbol;
                if p.symbols[symbol].owner != function_node && (p.symbols[symbol].flags & S_CAPTURE) != 0 && life_reads(p, l, p.nodes[function_node].right, symbol) { lexical = enclosing; found = true; break; }
                cell = l.cells[cell].next_frame;
            }
        }
        if found { break; }
        enclosing = l.frames[enclosing].parent;
    }
    var base = 2; var input = arguments;
    while input >= 0 {
        let value = l.items[input].value; let depth = life_set_depth(l, life_value_roots(p, value));
        if depth + 2 > base { base = depth + 2; }
        input = l.items[input].next;
    }
    var captured = l.frames[lexical].first_cell;
    while captured >= 0 { let cell = l.cells[captured]; if cell.live && l.roots[cell.root].depth + 2 > base { base = l.roots[cell.root].depth + 2; } captured = cell.next_frame; }
    let result_type = p.types[p.nodes[function_node].type_id].element;
    let receiver_sensitive = life_relative_storage(p, result_type, true);
    var target = -1; var active = l.frame;
    while active > 0 {
        if l.frames[active].function_node == function_node && l.frames[active].lexical == lexical && l.frames[active].selected_result == selected_result && (!receiver_sensitive || life_equal(l, l.frames[active].destination, destination)) && life_classes_equal(p, l, l.frames[active].inputs, arguments) { target = active; break; }
        active = l.frames[active].parent;
    }
    if target < 0 {
        var index = l.function_frames[function_node];
        while index >= 0 {
            let frame = l.frames[index];
            if frame.lexical == lexical && frame.selected_result == selected_result && (!receiver_sensitive || life_equal(l, frame.destination, destination)) && life_arguments_equal(p, l, frame.inputs, arguments) { target = index; break; }
            index = frame.next_function;
        }
    }
    if target < 0 && l.discovery {
        var index = l.function_frames[function_node];
        while index >= 0 {
            let frame = l.frames[index];
            if !frame.active && frame.lexical == lexical && frame.home == l.frame && frame.call == call && frame.selected_result == selected_result && (!receiver_sensitive || life_equal(l, frame.destination, destination)) { target = index; break; }
            index = frame.next_function;
        }
    }
    if target < 0 {
        target = l.frames.len;
        l.frames.push(LifeFrame { function_node: function_node, parent: l.frame, lexical: lexical, call: call, inputs: arguments, base: base, destination: destination, selected_result: selected_result, next_function: l.function_frames[function_node], home: l.frame });
        l.function_frames[function_node] = target;
    }
    life_cycle_call(p, l, target, call, destination);
    if !l.discovery && !l.frames[target].active {
        // An unchanged argument list does not make a captured binding stable.
        // Revalidate only when reference-bearing captured state has changed.
        var capture_inputs = -1; var enclosing = lexical;
        while enclosing >= 0 {
            var ci = l.frames[enclosing].first_cell;
            while ci >= 0 {
                let cell = l.cells[ci]; let symbol: const Symbol& = p.symbols[cell.symbol];
                if (symbol.flags & (S_CAPTURE | S_GLOBAL)) != 0 && (life_is_ref(p, symbol.type_id) || life_holds(p, symbol.type_id)) &&
                   ((symbol.flags & S_GLOBAL) != 0 && life_reads_global(p, l, function_node, cell.symbol) || (symbol.flags & S_GLOBAL) == 0 && life_reads(p, l, p.nodes[function_node].right, cell.symbol)) {
                    capture_inputs = life_append(l, capture_inputs, LifeValue { type_id: symbol.type_id, refs: cell.live_refs, contents: l.roots[cell.root].live_contents });
                }
                ci = cell.next_frame;
            }
            if enclosing == 0 { break; } enclosing = l.frames[enclosing].lexical;
        }
        if l.frames[target].validated && life_arguments_equal(p, l, l.frames[target].capture_inputs, capture_inputs) {
            life_replay(p, l, target); return l.frames[target].result;
        }
        l.frames[target].capture_inputs = capture_inputs;
        l.frames[target].validated = false; l.frames[target].first_effect = -1; l.frames[target].last_effect = -1; l.frames[target].effect_epoch += 1;
    }
    let previous_frame = l.frame; let previous_scope = l.scope;
    if !l.frames[target].active {
        l.frames[target].parent = previous_frame; l.frames[target].destination = destination;
        l.activations += 1; l.frames[target].activation = l.activations;
    }
    l.frame = target; l.scope = p.nodes[function_node].scope;
    var formal = p.nodes[function_node].first; var index = 0;
    while formal >= 0 {
        let symbol = p.nodes[formal].symbol; let cell = life_cell(p, l, symbol);
        if cell >= 0 {
            let value = life_coerce(p, l, life_item(l, arguments, index), p.nodes[formal].type_id);
            l.cells[cell].initialized = true;
            l.cells[cell].live = true;
            let roots = life_parameter_roots(p, l, life_value_roots(p, value), p.nodes[formal].type_id, function_node, lexical);
            if life_is_ref(p, p.nodes[formal].type_id) {
                let next = life_join(l, l.cells[cell].refs, roots);
                if !life_equal(l, next, l.cells[cell].refs) { l.cells[cell].refs = next; l.revision += 1; }
                if !l.discovery && !l.frames[target].active { l.cells[cell].live_refs = roots; }
            }
            life_add_contents(l, l.cells[cell].root, roots);
        }
        index += 1; formal = p.nodes[formal].next;
    }
    if l.discovery && !l.frames[target].active && l.frames[target].checked_revision == l.pass {
        l.frame = previous_frame; l.scope = previous_scope;
        life_replay(p, l, target, true); return l.frames[target].result;
    }
    if l.frames[target].active {
        // A backedge contributes the settled effects to its caller, including
        // effects discovered after that caller returned in an earlier round.
        l.frame = previous_frame; l.scope = previous_scope;
        life_replay(p, l, target, true); return life_cycle_value(l, l.frames[target].result);
    }
    if !l.frames[target].active {
        l.frames[target].active = true; let temporary_base = l.temp_count;
        life_eval(p, l, p.nodes[function_node].right, destination, selected_result);
        l.temp_count = temporary_base; l.frames[target].active = false;
        l.frames[target].checked_revision = l.pass;
        if !l.discovery { l.frames[target].validated = true; }
        var ci = l.frames[target].first_cell;
        while ci >= 0 { l.cells[ci].live = false; ci = l.cells[ci].next_frame; }
    }
    let result = l.frames[target].result;
    l.frame = previous_frame; l.scope = previous_scope;
    return result;
}

recursive fn life_call(p: Program&, l: Lifetimes&, node: i64, destination: i64, selected_result: i64) -> LifeValue {
    let n: const Node& = p.nodes[node]; var out = LifeValue { type_id: n.type_id };
    if n.symbol < 0 { return out; }
    let symbol: const Symbol& = p.symbols[n.symbol]; var builtin = -1;
    if (symbol.flags & S_BUILTIN) != 0 { builtin = symbol.index; }
    var arguments = -1; var argument = n.first; var parameter = -1;
    if builtin < 0 && symbol.node >= 0 { parameter = p.nodes[symbol.node].first; }
    var receiver = LifeValue {}; var index = 0; let holds = l.hold_count;
    if builtin == 0 || builtin == 1 { life_hold(l, LifeValue {}, node, 6); }
    while argument >= 0 {
        var target = 0;
        if index > 0 && (builtin == 24 || builtin == 25 || builtin == 30 || builtin == 31) {
            target = receiver.place;
            if receiver.type_id >= 0 && life_is_ref(p, p.types[receiver.type_id].element) { target = 0; }
        }
        let futures = l.future_count; life_push_future(l, p.nodes[argument].next);
        var value = life_eval(p, l, argument, target); l.future_count = futures;
        if parameter >= 0 {
            var expected = p.nodes[parameter].type_id;
            if (n.flags & F_DISPATCH) != 0 && index == n.aux {
                var arm = n.third;
                while arm >= 0 {
                    let fn_symbol = p.nodes[arm].symbol;
                    if fn_symbol >= 0 {
                        var formal = p.nodes[p.symbols[fn_symbol].node].first; var ordinal = 0;
                        while formal >= 0 && ordinal < index { formal = p.nodes[formal].next; ordinal += 1; }
                        if formal >= 0 {
                            let ty = p.nodes[formal].type_id;
                            life_receive(p, l, argument, value, ty); life_copy(p, l, argument, ty); life_note_temp(p, l, ty);
                            if life_is_ref(p, ty) { expected = ty; }
                        }
                    }
                    arm = p.nodes[arm].next;
                }
            } else {
                life_receive(p, l, argument, value, expected); life_copy(p, l, argument, expected);
                // A by-value nonfixed parameter owns a statement temporary,
                // including when its source is a fixed-size slice or literal.
                life_note_temp(p, l, expected);
            }
            value = life_coerce(p, l, value, expected); parameter = p.nodes[parameter].next;
        }
        if (builtin == 0 || builtin == 1 || builtin == 2 && index > 0) && !life_storage_path(p, argument) { life_copy(p, l, argument, value.type_id); }
        arguments = life_append(l, arguments, value);
        if index == 0 {
            receiver = value;
            if value.type_id >= 0 && p.types[value.type_id].kind == TY_REF { receiver = life_load(p, l, p.types[value.type_id].element, value.refs); }
            if receiver.type_id >= 0 {
                let element = p.types[receiver.type_id].element;
                var constructing = life_cached_size_class(p, l, element) > 0 || life_relative_storage(p, element, true);
                if builtin == 25 && p.nodes[argument].next >= 0 {
                    let source = p.nodes[argument].next; let kind = p.nodes[source].kind;
                    if kind != N_ARRAY && kind != N_FILL && life_fresh(p, source) { constructing = true; }
                }
                if (builtin == 24 || builtin == 25 || builtin == 30 || builtin == 31) && constructing { life_hold(l, receiver, node, 1); }
                if receiver.element_array != -1 && (builtin >= 24 || builtin == 2) || builtin == 16 { life_hold(l, receiver, argument, 3); }
            }
        }
        life_hold(l, value, argument);
        argument = p.nodes[argument].next; index += 1;
    }
    l.hold_count = holds;
    if builtin < 0 {
        if symbol.node >= 0 && (p.nodes[symbol.node].flags & F_FORMAT_RAW) != 0 { life_hold(l, life_item(l, arguments, 1), node, 7); }
        var place = destination; if place == 0 { place = life_temporary(p, l, node); }
        if (n.flags & F_DISPATCH) != 0 {
            var arm = n.third;
            while arm >= 0 {
                let fn_symbol = p.nodes[arm].symbol;
                if fn_symbol >= 0 {
                    var formal = p.nodes[p.symbols[fn_symbol].node].first; var actual = n.first; var index = 0;
                    while formal >= 0 && actual >= 0 {
                        life_receive(p, l, actual, life_item(l, arguments, index), p.nodes[formal].type_id);
                        life_copy(p, l, actual, p.nodes[formal].type_id);
                        formal = p.nodes[formal].next; actual = p.nodes[actual].next; index += 1;
                    }
                    out = life_merge(l, out, life_function(p, l, p.symbols[fn_symbol].node, node, arguments, place, selected_result));
                }
                arm = p.nodes[arm].next;
            }
        } else { out = life_function(p, l, symbol.node, node, arguments, place, selected_result); }
        life_self_destination(p, l, node, place, out.self_pools);
        life_self_destination(p, l, node, place, out.relative_roots);
        out.type_id = n.type_id;
        if !life_is_ref(p, n.type_id) { out.place = place; out.refs = 0; }
        var contents = out.contents;
        if n.type_id >= 0 && p.types[n.type_id].kind == TY_SLICE { out.place = place; contents = out.refs; }
        var at = l.sets[place].first;
        while at >= 0 { let alt = l.alts[at]; life_add_contents(l, alt.root, contents); at = alt.next; }
        l.hold_count = holds; return out;
    }
    if (builtin == 16 || builtin == 9) && n.first >= 0 && p.nodes[n.first].next >= 0 {
        var output = life_item(l, arguments, 1);
        if output.type_id >= 0 && p.types[output.type_id].kind == TY_REF { output = life_load(p, l, p.types[output.type_id].element, output.refs); }
        life_grow(p, l, node, output);
    }
    if builtin == 24 || builtin == 25 || builtin == 28 || builtin == 30 || builtin == 31 || builtin == 33 || builtin == 34 || builtin == 2 { life_grow(p, l, node, receiver); }
    if builtin == 26 || builtin == 27 || builtin == 28 || builtin == 29 {
        var balanced = false;
        if builtin == 28 && receiver.type_id >= 0 && p.types[receiver.type_id].array_kind == A_GROWSHRINK { balanced = life_balanced(p, l, node); }
        life_shrink(p, l, node, receiver, balanced);
    }
    if builtin == 34 || builtin == 35 {
        let run = life_item(l, arguments, 1);
        if l.sets[run.refs].count == 1 && receiver.place != 0 {
            let slice = l.alts[l.sets[run.refs].first]; let root = l.roots[slice.root];
            var separate = slice.exact && root.symbol >= 0 && (root.frame == l.frame || (p.symbols[root.symbol].flags & S_GLOBAL) != 0);
            var at = l.sets[receiver.place].first;
            while at >= 0 {
                let pool = l.alts[at]; let owner = l.roots[pool.root];
                if pool.root == slice.root && !(pool.component >= 0 && slice.component >= 0 && pool.component != slice.component) || owner.symbol < 0 || owner.frame != l.frame && (p.symbols[owner.symbol].flags & S_GLOBAL) == 0 { separate = false; }
                at = pool.next;
            }
            if separate { life_error(p, l, node, "slice pool operation receives a slice rooted in different owned storage"); }
        }
    }
    if (builtin == 33 || builtin == 34) && n.aux >= 0 && receiver.type_id >= 0 {
        let held = l.hold_count; life_hold(l, receiver, node, 1);
        let value = life_coerce(p, l, life_eval(p, l, n.aux, receiver.place), p.types[receiver.type_id].element);
        life_store(p, l, n.aux, receiver.place, value); l.hold_count = held;
    }
    if builtin == 23 && receiver.type_id >= 0 {
        let argument = life_item(l, arguments, 1); var same = l.sets[receiver.place].count == 1 && l.sets[argument.refs].count == 1;
        if same {
            let a = l.alts[l.sets[receiver.place].first]; let b = l.alts[l.sets[argument.refs].first];
            // A root owner's component is its own storage (upstream: index_of
            // must establish the particular array, not merely the owner).
            var owner_type = l.roots[a.root].type_id; if a.component >= 0 { owner_type = p.nodes[a.component].type_id; }
            same = a.exact && b.exact && a.root == b.root && a.component == b.component && life_one_array(p, l, owner_type, p.types[receiver.type_id].element);
        }
        if argument.refs != 0 && receiver.place != 0 && !same { life_error(p, l, node, "index_of requires an exact element root containing one array of this element type"); }
    }
    if builtin == 15 {
        out.contents = receiver.contents;
    } else if builtin == 17 {
        out.refs = receiver.place;
        if receiver.type_id >= 0 && p.types[receiver.type_id].kind == TY_SLICE { out.refs = receiver.refs; }
        var bytes = 0; var at = l.sets[out.refs].first;
        while at >= 0 { let alt = l.alts[at]; bytes = life_join(l, bytes, life_single(l, alt.root, alt.exact, alt.from, false, true, -1, alt.bound, alt.component)); at = alt.next; }
        out.refs = bytes;
    } else if builtin == 24 || builtin == 30 || builtin == 31 {
        var element = -1; if receiver.type_id >= 0 { element = p.types[receiver.type_id].element; }
        let value = life_coerce(p, l, life_item(l, arguments, 1), element);
        if n.first >= 0 { life_copy(p, l, p.nodes[n.first].next, element); }
        life_store(p, l, node, receiver.place, value);
        if life_is_ref(p, element) { out.refs = value.refs; }
        else { out.refs = receiver.place; }
        out.contents = value.contents;
    } else if builtin == 25 {
        var value = life_item(l, arguments, 1);
        var source = n.first; if source >= 0 { source = p.nodes[source].next; }
        if source >= 0 && p.nodes[source].kind != N_ARRAY && p.nodes[source].kind != N_FILL && receiver.type_id >= 0 &&
           life_relative_storage(p, p.types[receiver.type_id].element) {
            life_error(p, l, source, "append cannot copy elements containing self-relative references into another root");
        }
        if life_is_ref(p, value.type_id) {
            var source = value.place;
            if p.types[value.type_id].kind == TY_SLICE || p.types[value.type_id].kind == TY_REF { source = value.refs; }
            value.contents = life_contents(l, source); value.refs = 0; value.type_id = -1;
        }
        life_store(p, l, node, receiver.place, value);
    } else if builtin == 28 {
        var element = -1; if receiver.type_id >= 0 { element = p.types[receiver.type_id].element; }
        let fill = life_coerce(p, l, life_item(l, arguments, 2), element);
        life_store(p, l, node, receiver.place, fill);
    } else if builtin == 26 {
        var storage = n.type_id; if receiver.type_id >= 0 { storage = p.types[receiver.type_id].element; }
        out = life_load(p, l, storage, receiver.place, true); out.type_id = n.type_id;
    } else if builtin == 33 || builtin == 34 { out.refs = receiver.place; }
    if !life_is_ref(p, out.type_id) && out.type_id >= 0 && p.types[out.type_id].kind != TY_VOID {
        out.place = destination; if out.place == 0 { out.place = life_temporary(p, l, node); }
    }
    return out;
}

fn life_storage_path(p: Program&, node: i64) -> bool {
    var at = node;
    while at >= 0 {
        let n: const Node& = p.nodes[at];
        if n.kind == N_NAME { return true; }
        if n.kind == N_UNARY && n.integer == T_MUL { return true; }
        if n.kind != N_MEMBER && n.kind != N_INDEX { return false; }
        at = n.left;
    }
    return false;
}

recursive fn life_eval(p: Program&, l: Lifetimes&, node: i64, destination: i64 = 0, selected_result: i64 = -1) -> LifeValue {
    if node < 0 { return LifeValue {}; }
    let n: const Node& = p.nodes[node]; var out = LifeValue { type_id: n.type_id };
    if n.kind == N_NAME && n.symbol >= 0 && (p.symbols[n.symbol].flags & (S_FUNCTION | S_TYPE | S_BUILTIN)) == 0 {
        let cell = life_cell(p, l, n.symbol);
        out.place = life_root_set(l, l.cells[cell].root); out.refs = l.cells[cell].refs;
        if !l.discovery && (p.symbols[n.symbol].flags & (S_GLOBAL | S_MUTABLE)) != (S_GLOBAL | S_MUTABLE) { out.refs = l.cells[cell].live_refs; }
        out.contents = l.roots[l.cells[cell].root].contents;
        if !l.discovery { out.contents = l.roots[l.cells[cell].root].live_contents; }
        if n.type_id >= 0 && p.types[n.type_id].kind == TY_REF {
            out.contents = life_contents(l, out.refs); if !l.discovery { out.contents = life_live_contents(l, out.refs); }
        }
        if !life_holds(p, n.type_id) { out.contents = 0; }
        life_construct_read(p, l, node, out);
        return out;
    }
    if n.kind == N_STRING { out.place = life_root_set(l, 0); out.refs = out.place; return out; }
    if n.kind == N_INTEGER || n.kind == N_FLOAT || n.kind == N_NULL || n.kind == N_BOOL ||
       n.kind == N_EMPTY || n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE || n.kind == N_IMPORT { return out; }
    return life_eval_body(p, l, node, n, destination, selected_result);
}

recursive fn life_eval_body(p: Program&, l: Lifetimes&, node: i64, n: const Node&, destination: i64, selected_result: i64) -> LifeValue {
    var out = LifeValue { type_id: n.type_id };
    if n.kind == N_UNARY {
        let value = life_eval(p, l, n.left);
        if n.integer == T_BITAND { out.refs = value.place; if value.type_id >= 0 && p.types[value.type_id].kind == TY_REF { out.refs = value.refs; } out.contents = value.contents; }
        else if n.integer == T_MUL { out = life_load(p, l, n.type_id, value.refs); }
        return out;
    }
    if n.kind == N_MEMBER || n.kind == N_INDEX || n.kind == N_SLICE {
        l.reading_place += 1; var base = life_eval(p, l, n.left); l.reading_place -= 1;
        var storage = n.type_id;
        if n.kind == N_MEMBER && n.symbol >= 0 { storage = p.nodes[n.symbol].type_id; }
        if n.kind == N_INDEX || n.kind == N_SLICE {
            var array = base.type_id; if array >= 0 && p.types[array].kind == TY_REF { array = p.types[array].element; }
            if array >= 0 && (p.types[array].kind == TY_ARRAY || p.types[array].kind == TY_SLICE) { storage = p.types[array].element; }
        }
        if !life_is_ref(p, base.type_id) && !life_storage_path(p, n.left) && life_relative_storage(p, storage) { life_copy(p, l, n.left, base.type_id); }
        if base.type_id >= 0 && p.types[base.type_id].kind == TY_REF && p.types[base.type_id].element >= 0 && p.types[p.types[base.type_id].element].kind == TY_SLICE { base = life_load(p, l, p.types[base.type_id].element, base.refs); }
        var places = base.place;
        if life_is_ref(p, base.type_id) { places = base.refs; }
        if n.kind != N_MEMBER {
            let held = l.hold_count; var region = base; region.place = places; life_hold(l, region, n.left, 3);
            life_eval(p, l, n.right); life_eval(p, l, n.third); l.hold_count = held;
        }
        var owner_type = base.type_id; if owner_type >= 0 && p.types[owner_type].kind == TY_REF { owner_type = p.types[owner_type].element; }
        if n.kind == N_MEMBER && n.symbol >= 0 && root_struct_type(p, owner_type) { places = life_component(l, places, n.symbol); }
        else { places = life_interior(l, places); }
        if n.kind == N_SLICE { out.refs = places; out.contents = life_contents(l, places); out.place = places; }
        else {
            out = life_load(p, l, storage, places, true); out.type_id = n.type_id;
        }
        out.element_array = base.element_array;
        if out.element_array < 0 && (n.kind == N_INDEX || n.kind == N_SLICE) {
            out.element_array = base.type_id;
            if out.element_array >= 0 && p.types[out.element_array].kind == TY_REF { out.element_array = p.types[out.element_array].element; }
            if out.element_array < 0 { out.element_array = -2; }
        }
        if l.sequence_frame == l.frame && n.kind != N_SLICE { life_hold(l, out, node, 4); }
        life_construct_read(p, l, node, out); return out;
    }
    if n.kind == N_RESULT {
        let producer = life_eval(p, l, n.left, destination, n.integer);
        out = life_item(l, producer.tuple, n.integer); out.type_id = n.type_id;
        return out;
    }
    if n.kind == N_CALL { return life_call(p, l, node, destination, selected_result); }
    if n.kind == N_CAST { return life_coerce(p, l, life_eval(p, l, n.left), n.type_id); }
    if n.kind == N_ARRAY || n.kind == N_FILL || n.kind == N_RECORD {
        if n.kind == N_ARRAY && n.first < 0 && (n.flags & F_DEFAULT) != 0 && n.type_id >= 0 && p.types[n.type_id].kind == TY_SLICE {
            out.place = life_root_set(l, 0); out.refs = out.place; return out;
        }
        out.place = destination; if out.place == 0 { out.place = life_temporary(p, l, node); }
        let held = l.hold_count; var child = n.first;
        if life_cached_size_class(p, l, n.type_id) > 0 { life_hold(l, out, node, 6); }
        let root_owner = n.kind == N_RECORD && root_struct_type(p, n.type_id);
        while child >= 0 {
            var value_node = child; var expected = -1;
            if n.kind == N_RECORD { value_node = p.nodes[child].right; expected = p.nodes[child].type_id; }
            else if n.type_id >= 0 { expected = p.types[n.type_id].element; }
            // A root owner's field is constructed in that field's own storage.
            var place = out.place; if root_owner && p.nodes[child].symbol >= 0 { place = life_component(l, out.place, p.nodes[child].symbol); }
            if value_node >= 0 && p.nodes[value_node].kind == N_SELF {
                let reference: const Type& = p.types[expected];
                if reference.pool >= 0 {
                    out.self_pools = life_join(l, out.self_pools, life_pool_places(p, l, reference.pool));
                    life_self_destination(p, l, value_node, place, out.self_pools);
                }
                // Relative readback derives the owner or named pool. The
                // encoded self offset holds no external reference alive.
                child = p.nodes[child].next; continue;
            }
            var target = place; if life_is_ref(p, expected) { target = 0; }
            let future = l.future_count; life_push_future(l, p.nodes[child].next);
            let value = life_coerce(p, l, life_eval(p, l, value_node, target), expected); l.future_count = future;
            life_hold(l, value, value_node);
            life_copy(p, l, value_node, expected);
            life_store(p, l, value_node, place, value);
            out.contents = life_join(l, out.contents, life_stored_roots(p, l, value));
            // A root owner's field was stored in its own component, where its
            // pool-relative and self-relative values were placed.
            if !root_owner { out.self_pools = life_join(l, out.self_pools, value.self_pools); out.relative_roots = life_join(l, out.relative_roots, value.relative_roots); }
            if !root_owner && expected >= 0 && p.types[expected].kind == TY_REF && p.types[expected].length_storage >= 0 && p.types[expected].pool < 0 {
                out.relative_roots = life_join(l, out.relative_roots, value.refs);
            }
            child = p.nodes[child].next;
        }
        if n.kind == N_FILL && n.first < 0 {
            let value = life_eval(p, l, n.left, out.place); life_store(p, l, node, out.place, value);
            out.contents = life_stored_roots(p, l, value); out.self_pools = value.self_pools; out.relative_roots = value.relative_roots; life_eval(p, l, n.right);
        }
        if life_is_ref(p, n.type_id) { out.refs = out.place; }
        l.hold_count = held; return out;
    }
    if n.kind == N_VARIABLE {
        var binding = n.first; if binding < 0 { binding = node; }
        var initializer = n.right; var index = 0; var aggregate = LifeValue {};
        if !l.discovery {
            var at = binding;
            while at >= 0 {
                let symbol = p.nodes[at].symbol;
                if symbol >= 0 && life_cached_size_class(p, l, p.symbols[symbol].type_id) > 0 { let cell = life_cell(p, l, symbol); l.cells[cell].live = true; }
                if n.first < 0 { break; } at = p.nodes[at].next;
            }
        }
        if n.first >= 0 && initializer >= 0 && p.nodes[initializer].next < 0 { aggregate = life_eval(p, l, initializer); }
        while binding >= 0 {
            let symbol = p.nodes[binding].symbol; let cell = life_cell(p, l, symbol);
            if cell >= 0 {
                if !l.discovery { l.cells[cell].live_refs = 0; l.roots[l.cells[cell].root].live_contents = 0; }
                let places = life_root_set(l, l.cells[cell].root); var value = aggregate;
                if aggregate.tuple >= 0 { value = life_item(l, aggregate.tuple, index); }
                else if initializer >= 0 {
                    var target = places; if life_is_ref(p, p.symbols[symbol].type_id) { target = 0; }
                    value = life_eval(p, l, initializer, target);
                }
                life_receive(p, l, initializer, value, p.symbols[symbol].type_id);
                value = life_coerce(p, l, value, p.symbols[symbol].type_id);
                if initializer >= 0 { life_copy(p, l, initializer, p.symbols[symbol].type_id); }
                if initializer >= 0 { life_store(p, l, node, places, value, true); }
                l.cells[cell].initialized = true;
                l.cells[cell].live = true;
            }
            if n.first < 0 { break; }
            binding = p.nodes[binding].next; index += 1;
            if initializer >= 0 && aggregate.tuple < 0 { initializer = p.nodes[initializer].next; }
        }
        return out;
    }
    if n.kind == N_ASSIGN {
        l.reading_place += 1; var target = life_eval(p, l, n.left); l.reading_place -= 1;
        var places = target.place; var ty = target.type_id;
        var binding = p.nodes[n.left].kind == N_NAME && life_is_ref(p, ty);
        let through = ty >= 0 && p.types[ty].kind == TY_REF && n.integer != T_DOTASSIGN;
        if ty >= 0 && p.types[ty].kind == TY_REF && n.integer != T_DOTASSIGN {
            places = target.refs; ty = p.types[ty].element; binding = life_is_ref(p, ty);
        }
        let held = l.hold_count; var receiver = target; receiver.type_id = ty; receiver.place = places;
        var kind = 3; let future = l.future_count; life_push_future(l, n.right);
        if life_cached_size_class(p, l, ty) == 2 || ty >= 0 && p.types[ty].kind == TY_ENUM && (p.types[ty].flags & F_VARIABLE_MODE) != 0 { life_replace(p, l, node, receiver); }
        if life_cached_size_class(p, l, ty) == 2 {
            life_shrink(p, l, node, receiver); kind = 2;
        }
        life_hold(l, receiver, n.left, kind);
        var destination = places; if life_is_ref(p, ty) { destination = 0; }
        let natural = life_eval(p, l, n.right, destination); life_receive(p, l, n.right, natural, ty);
        let value = life_coerce(p, l, natural, ty); l.hold_count = held; l.future_count = future;
        life_copy(p, l, n.right, ty);
        if !l.discovery && l.conditional == 0 && !binding && life_value_roots(p, value) == 0 {
            var at = l.sets[places].first;
            while at >= 0 {
                let alt = l.alts[at];
                if alt.exact {
                    if p.nodes[n.left].kind == N_NAME {
                        life_effect(l, LifeEffect { kind: 6, node: node, value: LifeValue {}, places: life_root_set(l, alt.root) });
                        l.roots[alt.root].live_contents = 0;
                    }
                    if p.nodes[n.left].kind == N_MEMBER && p.nodes[n.left].symbol >= 0 {
                        life_effect(l, LifeEffect { kind: 7, node: node, value: LifeValue {}, places: life_root_set(l, alt.root), field: p.nodes[n.left].symbol });
                        l.kills.push(LifeKill { root: alt.root, field: p.nodes[n.left].symbol });
                    }
                }
                at = alt.next;
            }
        }
        if n.right >= 0 {
            if binding && ty >= 0 && p.types[ty].kind == TY_REF && p.types[ty].length_storage >= 0 && p.types[ty].pool >= 0 {
                life_relative_store(p, l, node, places, value);
                life_effect(l, LifeEffect { kind: 9, node: node, value: value, places: places });
            }
            life_store(p, l, node, places, value, binding, through);
        }
        return out;
    }
    if n.kind == N_RETURN {
        let held = l.hold_count;
        var child = n.first; var result = LifeValue {}; var count = 0; var tuple = -1;
        var target_frame = l.frame;
        if n.symbol >= 0 && n.symbol < p.symbols.len {
            let target_function = p.symbols[n.symbol].node; var frame = l.frame;
            while frame > 0 {
                if l.frames[frame].function_node == target_function { target_frame = frame; break; }
                frame = l.frames[frame].parent;
            }
        }
        let function_node = l.frames[target_frame].function_node;
        var expected = -1; var component = -1;
        if function_node >= 0 && p.nodes[function_node].type_id >= 0 {
            expected = p.types[p.nodes[function_node].type_id].element;
            if expected >= 0 && p.types[expected].kind == TY_TUPLE { component = p.types[expected].first; }
        }
        while child >= 0 {
            var target_type = expected;
            if component >= 0 {
                let natural_type = p.nodes[child].type_id;
                if p.nodes[child].next < 0 && natural_type >= 0 && p.types[natural_type].kind == TY_TUPLE { component = -1; }
                else { target_type = p.nodes[component].type_id; component = p.nodes[component].next; }
            }
            var place = l.frames[target_frame].destination; var projected = -1;
            let selected = l.frames[target_frame].selected_result;
            if p.nodes[child].type_id >= 0 && p.types[p.nodes[child].type_id].kind == TY_TUPLE && p.nodes[child].next < 0 { projected = selected; }
            else if selected >= 0 && count != selected { place = life_temporary(p, l, child); }
            if life_is_ref(p, target_type) { place = 0; }
            let natural = life_eval(p, l, child, place, projected); life_receive(p, l, child, natural, target_type);
            let value = life_coerce(p, l, natural, target_type);
            if target_type >= 0 && p.types[target_type].kind == TY_REF && p.types[target_type].length_storage >= 0 { life_error(p, l, child, "function results are values and cannot have relative-reference storage types"); }
            life_copy(p, l, child, target_type, target_frame);
            life_return_value(p, l, child, value, target_frame); tuple = life_append(l, tuple, value); life_hold(l, value, child);
            result = value; count += 1; child = p.nodes[child].next;
        }
        if count > 1 { result = LifeValue { tuple: tuple }; }
        let old = l.frames[target_frame].result;
        let joined = life_merge(l, old, result);
        if !life_equal(l, old.refs, joined.refs) || !life_equal(l, old.contents, joined.contents) || !life_equal(l, old.self_pools, joined.self_pools) || !life_equal(l, old.relative_roots, joined.relative_roots) { l.revision += 1; }
        l.frames[target_frame].result = joined; l.hold_count = held;
        return out;
    }
    if n.kind == N_TUPLE {
        let held = l.hold_count; var child = n.first;
        while child >= 0 { let value = life_eval(p, l, child); out.tuple = life_append(l, out.tuple, value); life_hold(l, value, child); child = p.nodes[child].next; }
        l.hold_count = held; return out;
    }
    if n.kind == N_BLOCK {
        var receiving = destination;
        if (n.flags & F_EARLY) != 0 {
            if receiving == 0 && n.type_id >= 0 && (p.types[n.type_id].kind == TY_ARRAY || p.types[n.type_id].kind == TY_STRUCT || p.types[n.type_id].kind == TY_ENUM) { receiving = life_temporary(p, l, node); }
            life_control_destination(l, node, receiving, selected_result);
        }
        let saved = l.scope; if n.scope >= 0 { l.scope = n.scope; }
        let depth = life_depth(l, saved); var child = n.first;
        while child >= 0 {
            var target = 0; if child == n.last { target = receiving; }
            let futures = l.future_count; let temporary_base = l.temp_count; life_push_future(l, p.nodes[child].next);
            let value = life_eval(p, l, child, target, selected_result); l.future_count = futures; l.temp_count = temporary_base;
            if child == n.last && (p.nodes[child].flags & F_TAIL) != 0 { out = life_coerce(p, l, value, n.type_id); }
            child = p.nodes[child].next;
        }
        for exit in l.exits { if exit.node == node && exit.frame == l.frame { out = life_merge(l, out, life_coerce(p, l, exit.value, n.type_id)); } }
        life_branch(p, l, node, out, depth);
        var ci = l.frames[l.frame].first_cell;
        while ci >= 0 { let cell = l.cells[ci]; if n.scope >= 0 && life_in_scope(l, p.symbols[cell.symbol].scope, n.scope) { l.cells[ci].live = false; } ci = cell.next_frame; }
        l.scope = saved;
        return life_construct_value(p, l, node, out, receiving);
    }
    if n.kind == N_IF {
        let futures = l.future_count; life_push_future(l, n.right); life_push_future(l, n.third);
        life_eval(p, l, n.left); l.future_count = futures;
        l.conditional += 1;
        let a = life_coerce(p, l, life_eval(p, l, n.right, destination, selected_result), n.type_id);
        let b = life_coerce(p, l, life_eval(p, l, n.third, destination, selected_result), n.type_id);
        l.conditional -= 1;
        life_branch(p, l, node, a, life_depth(l, l.scope)); life_branch(p, l, node, b, life_depth(l, l.scope));
        out = life_merge(l, a, b); out.type_id = n.type_id; return life_construct_value(p, l, node, out, destination);
    }
    if n.kind == N_MATCH {
        let future = l.future_count; var branch = n.first;
        while branch >= 0 { life_push_future(l, p.nodes[branch].right); branch = p.nodes[branch].next; }
        var source = life_eval(p, l, n.left); l.future_count = future; var arm = n.first;
        if source.type_id >= 0 && p.types[source.type_id].kind == TY_REF {
            source = life_load(p, l, p.types[source.type_id].element, source.refs);
        }
        while arm >= 0 {
            let a: const Node& = p.nodes[arm]; let pattern: const Node& = p.nodes[a.left];
            if pattern.left >= 0 && p.nodes[pattern.left].symbol >= 0 {
                let symbol = p.nodes[pattern.left].symbol; let cell = life_cell(p, l, symbol);
                if !l.discovery { l.cells[cell].live_refs = 0; l.roots[l.cells[cell].root].live_contents = 0; }
                var value = source; value.type_id = p.symbols[symbol].type_id;
                if life_is_ref(p, value.type_id) { value.refs = source.place; }
                life_copy(p, l, n.left, p.symbols[symbol].type_id);
                life_store(p, l, pattern.left, life_root_set(l, l.cells[cell].root), value, true); l.cells[cell].initialized = true; l.cells[cell].live = true;
            }
            life_eval(p, l, a.third);
            let value = life_coerce(p, l, life_eval(p, l, a.right, destination, selected_result), n.type_id);
            life_branch(p, l, a.right, value, life_depth(l, l.scope)); out = life_merge(l, out, value);
            if pattern.left >= 0 && p.nodes[pattern.left].symbol >= 0 { let cell = life_cell(p, l, p.nodes[pattern.left].symbol); l.cells[cell].live = false; }
            arm = a.next;
        }
        out.type_id = n.type_id; return life_construct_value(p, l, node, out, destination);
    }
    if n.kind == N_FOR || n.kind == N_WHILE || n.kind == N_LOOP {
        var receiving = destination;
        if n.kind == N_LOOP {
            if receiving == 0 && n.type_id >= 0 && (p.types[n.type_id].kind == TY_ARRAY || p.types[n.type_id].kind == TY_STRUCT || p.types[n.type_id].kind == TY_ENUM) { receiving = life_temporary(p, l, node); }
            life_control_destination(l, node, receiving, selected_result);
        }
        // A for sequence belongs to the enclosing statement; its temporary
        // storage encloses the binder/body scope that the statement opens.
        let saved = l.scope; if n.kind != N_FOR && n.scope >= 0 { l.scope = n.scope; }
        let held = l.hold_count; let sequence = l.sequence_frame;
        if n.kind == N_FOR { l.sequence_frame = l.frame; }
        let future = l.future_count; life_push_future(l, n.right);
        let source = life_eval(p, l, n.left); l.sequence_frame = sequence; l.future_count = future;
        if n.kind == N_FOR {
            let sequence_node: const Node& = p.nodes[n.left];
            if (sequence_node.kind == N_ARRAY || sequence_node.kind == N_FILL) && life_cached_size_class(p, l, source.type_id) > 0 {
                life_error(p, l, n.left, "an array literal of variable-size elements requires a construction context before iteration");
            }
            if !life_is_ref(p, source.type_id) && !life_storage_path(p, n.left) { life_copy(p, l, n.left, source.type_id); }
            if n.scope >= 0 { l.scope = n.scope; }
            life_hold(l, source, n.left);
            var binding = n.first; var index = 0;
            while binding >= 0 {
                let symbol = p.nodes[binding].symbol; let cell = life_cell(p, l, symbol);
                if cell >= 0 {
                    var places = source.place; if life_is_ref(p, source.type_id) { places = source.refs; }
                    var source_type = source.type_id;
                    if source_type >= 0 && p.types[source_type].kind == TY_REF { source_type = p.types[source_type].element; }
                    var storage = p.symbols[symbol].type_id;
                    if index == 0 && source_type >= 0 && (p.types[source_type].kind == TY_ARRAY || p.types[source_type].kind == TY_SLICE) && p.types[source_type].element >= 0 && p.types[p.types[source_type].element].kind == TY_REF { storage = p.types[source_type].element; }
                    var value = life_load(p, l, storage, places, true); value.type_id = p.symbols[symbol].type_id;
                    if source_type >= 0 && p.symbols[symbol].type_id >= 0 && p.types[p.symbols[symbol].type_id].kind == TY_REF {
                        let element = p.types[source_type].element;
                        if !life_is_ref(p, element) || p.types[p.symbols[symbol].type_id].element == element { value.refs = life_interior(l, places); }
                    }
                    if index == 0 { life_copy(p, l, n.left, p.symbols[symbol].type_id); }
                    if index == 0 { life_store(p, l, binding, life_root_set(l, l.cells[cell].root), value, true); }
                    l.cells[cell].initialized = true;
                    l.cells[cell].live = true;
                }
                binding = p.nodes[binding].next; index += 1;
            }
        }
        if !l.discovery {
            for cell, index in l.cells {
                if cell.live && !life_in_scope(l, p.symbols[cell.symbol].scope, n.scope) {
                    l.cells[index].live_refs = cell.refs; l.roots[cell.root].live_contents = l.roots[cell.root].contents;
                }
            }
        }
        let futures = l.future_count; life_push_future(l, n.right, n.scope); life_push_future(l, n.left, n.scope);
        life_eval(p, l, n.right); l.future_count = futures;
        for exit in l.exits { if exit.node == node && exit.frame == l.frame { out = life_merge(l, out, exit.value); } }
        var ci = l.frames[l.frame].first_cell;
        while ci >= 0 { let cell = l.cells[ci]; if n.scope >= 0 && life_in_scope(l, p.symbols[cell.symbol].scope, n.scope) { l.cells[ci].live = false; } ci = cell.next_frame; }
        l.hold_count = held;
        l.scope = saved; life_branch(p, l, node, out, life_depth(l, saved)); return life_construct_value(p, l, node, out, receiving);
    }
    if n.kind == N_BREAK {
        var receiving = destination; var projected = selected_result;
        for exit in l.exits { if exit.node == n.symbol && exit.frame == l.frame { receiving = exit.destination; projected = exit.selected_result; break; } }
        let value = life_eval(p, l, n.left, receiving, projected); var found = false;
        for exit, index in l.exits {
            if exit.node == n.symbol && exit.frame == l.frame { l.exits[index].value = life_merge(l, exit.value, value); found = true; break; }
        }
        if !found { l.exits.push(LifeExit { node: n.symbol, frame: l.frame, value: value }); }
        return out;
    }
    if n.kind == N_EXPR_STMT || n.kind == N_GUARD { life_eval(p, l, n.left); return out; }
    // A defer body is evaluated where it is written (upstream CheckDefer):
    // what it reads is live there, which covers every exit of its block.
    if n.kind == N_DEFER { life_eval(p, l, n.right); return out; }
    if n.kind == N_BINARY || n.kind == N_RANGE {
        let held = l.hold_count; var value = life_eval(p, l, n.left); var ty = value.type_id;
        if ty >= 0 && p.types[ty].kind == TY_REF { value.place = value.refs; ty = p.types[ty].element; }
        if n.kind == N_BINARY && n.integer >= T_EQ && n.integer <= T_GTEQ && ty >= 0 && p.types[ty].kind == TY_ARRAY { life_hold(l, value, n.left, 3); }
        else { life_hold(l, value, n.left); }
        life_eval(p, l, n.right); l.hold_count = held; return out;
    }
    return out;
}

fn life_replay(p: Program&, l: Lifetimes&, frame: i64, summary: bool = false) {
    var at = l.frames[frame].first_effect; if summary { at = l.frames[frame].first_summary; }
    while at >= 0 {
        let effect = l.effects[at];
        if effect.kind == 1 { life_shrink(p, l, effect.node, effect.value); }
        else if effect.kind == 2 { life_grow(p, l, effect.node, effect.value); }
        else if effect.kind == 3 { life_construct_read(p, l, effect.node, effect.value); }
        else if effect.kind == 8 { life_replace(p, l, effect.node, effect.value); }
        else if effect.kind == 9 { life_relative_store(p, l, effect.node, effect.places, effect.value); life_effect(l, effect); }
        else if effect.kind == 4 {
            var ai = l.sets[effect.places].first;
            while ai >= 0 { let alt = l.alts[ai]; life_add_contents(l, alt.root, effect.value.contents); ai = alt.next; }
        } else {
            life_effect(l, effect);
            if effect.kind == 5 { l.cells[effect.cell].live_refs = life_join(l, l.cells[effect.cell].live_refs, effect.value.refs); }
            else {
                var ai = l.sets[effect.places].first;
                while ai >= 0 {
                    let alt = l.alts[ai];
                    if effect.kind == 6 { l.roots[alt.root].live_contents = 0; }
                    else if effect.kind == 7 { l.kills.push(LifeKill { root: alt.root, field: effect.field }); }
                    ai = alt.next;
                }
            }
        }
        at = effect.next;
    }
}

// Persist the final root proof by Symbol ID so optimizer clones can carry it
// without retaining the analyzer's context arenas.
fn life_export_provenance(p: Program&, l: Lifetimes&) {
    for symbol, index in p.symbols {
        if (symbol.flags & (S_PARAMETER | S_FUNCTION | S_BUILTIN | S_TYPE)) != 0 { continue; }
        if (symbol.flags & S_GLOBAL) != 0 {
            var static = (symbol.flags & S_MUTABLE) == 0; var ci = l.symbol_cells[index];
            if ci < 0 { static = false; }
            while ci >= 0 {
                let cell = l.cells[ci]; if !cell.initialized { static = false; }
                var roots = l.roots[cell.root].contents;
                if life_is_ref(p, symbol.type_id) { roots = life_join(l, roots, cell.refs); }
                var at = l.sets[roots].first;
                while at >= 0 { let alt = l.alts[at]; if !alt.exact || alt.root != 0 { static = false; } at = alt.next; }
                ci = cell.next_symbol;
            }
            p.symbols[index].provenance = -1; if static { p.symbols[index].provenance = -2; }
            continue;
        }
        if !life_is_ref(p, symbol.type_id) && !life_holds(p, symbol.type_id) { p.symbols[index].provenance = -2; continue; }
        var proof = -2; var known = true; var ci = l.symbol_cells[index];
        if ci < 0 { known = false; }
        while ci >= 0 {
            let cell = l.cells[ci];
            if !cell.initialized || life_is_ref(p, symbol.type_id) && cell.refs == 0 { known = false; }
            var roots = l.roots[cell.root].contents;
            if life_is_ref(p, symbol.type_id) { roots = life_join(l, roots, cell.refs); }
            var at = l.sets[roots].first;
            while at >= 0 {
                let alt = l.alts[at]; let owner = l.roots[alt.root].symbol;
                if !alt.exact { known = false; }
                if owner >= 0 {
                    var seen = false; var entry = proof;
                    while entry >= 0 { if p.nodes[entry].symbol == owner { seen = true; break; } entry = p.nodes[entry].next; }
                    if !seen { let node = p.nodes.len; p.nodes.push(Node { kind: N_BINDING, next: proof, symbol: owner }); proof = node; }
                }
                at = alt.next;
            }
            ci = cell.next_symbol;
        }
        if !known { proof = -1; }
        p.symbols[index].provenance = proof;
    }
}

fn life_clone_provenance(p: Program&, old_symbols: const i64[:], new_symbols: const i64[:]) {
    for original, index in old_symbols {
        if index >= new_symbols.len || original < 0 || new_symbols[index] < 0 { continue; }
        let source = p.symbols[original].provenance; var proof = source;
        if source >= 0 {
            proof = -2; var at = source;
            while at >= 0 {
                var symbol = p.nodes[at].symbol;
                for old, mapped in old_symbols { if old == symbol && mapped < new_symbols.len { symbol = new_symbols[mapped]; break; } }
                let node = p.nodes.len; p.nodes.push(Node { kind: N_BINDING, next: proof, symbol: symbol }); proof = node;
                at = p.nodes[at].next;
            }
        }
        p.symbols[new_symbols[index]].provenance = proof;
    }
}

fn life_may_reach_local(p: Program&, node: i64, candidate: i64) -> bool {
    if (p.symbols[candidate].flags & S_CAPTURE) != 0 { return true; }
    var work: i64[>..] = [node]; var at = 0;
    while at < work.len {
        let current = work[at]; at += 1; if current < 0 { continue; }
        let n = p.nodes[current];
        if n.kind == N_NAME && n.symbol >= 0 {
            if n.symbol == candidate { return true; }
            let symbol = p.symbols[n.symbol];
            if (symbol.flags & (S_GLOBAL | S_PARAMETER | S_FUNCTION | S_BUILTIN | S_TYPE)) == 0 && (life_is_ref(p, symbol.type_id) || life_holds(p, symbol.type_id)) {
                var proof = symbol.provenance; if proof == -1 { return true; }
                while proof >= 0 { if p.nodes[proof].symbol == candidate { return true; } proof = p.nodes[proof].next; }
            }
        }
        if n.kind == N_FUNCTION || n.kind == N_STRUCT || n.kind == N_ENUM || n.kind == N_ALIAS || n.kind == N_IMPORT { continue; }
        if n.kind == N_FUNCTION_VALUE { if n.right >= 0 { work.push(n.right); } continue; }
        // A pattern reads nothing: an enum pattern's symbol names its variant node.
        if n.kind == N_ARM { if n.right >= 0 { work.push(n.right); } continue; }
        var child = n.first; while child >= 0 { work.push(child); child = p.nodes[child].next; }
        for child in [n.left, n.right, n.third] { if child >= 0 { work.push(child); } }
    }
    return false;
}
fn life_refresh_named_results(p: Program&) {
    let node_count = p.nodes.len;
    for function_node in 0..node_count {
        let fn_node = p.nodes[function_node];
        let inline_body = fn_node.kind == N_BLOCK && (fn_node.flags & F_EARLY) != 0 && fn_node.origin >= 0 && (p.nodes[fn_node.origin].kind == N_FUNCTION || p.nodes[fn_node.origin].kind == N_FUNCTION_VALUE);
        if !inline_body && (fn_node.kind != N_FUNCTION || fn_node.right < 0 || (fn_node.flags & F_CHECKED) == 0) { continue; }
        if fn_node.type_id < 0 { continue; }
        p.nodes[function_node].named_results = -1;
        var symbols: i64[>..] = []; var ordinals: i64[>..] = [];
        life_named_results_of(p, function_node, inline_body, symbols, ordinals);
        for candidate, index in symbols {
            let binding = p.nodes.len;
            p.nodes.push(Node { kind: N_BINDING, next: p.nodes[function_node].named_results, symbol: candidate, integer: ordinals[index] });
            p.nodes[function_node].named_results = binding;
        }
    }
}
// The locals a function, or an inlined body, returns by name (upstream
// NamedResultOf): each result ordinal's top-level local that every return
// hands back, which no other returned value may reach.
fn life_named_results_of(p: Program&, function_node: i64, inline_body: bool, symbols: i64[>..]&, ordinals: i64[>..]&) {
    let fn_node = p.nodes[function_node];
    if fn_node.type_id < 0 { return; }
    var body_node = fn_node.right; var result_type = p.types[fn_node.type_id].element;
    if inline_body { body_node = function_node; result_type = fn_node.type_id; }
    let body = p.nodes[body_node]; if body.kind != N_BLOCK { return; }
    if result_type < 0 || p.types[result_type].kind == TY_VOID { return; }
    var results = 1;
    if p.types[result_type].kind == TY_TUPLE { results = 0; var item = p.types[result_type].first; while item >= 0 { results += 1; item = p.nodes[item].next; } }
    var locals: i64[>..] = []; var statement = body.first;
    while statement >= 0 {
        let n = p.nodes[statement];
        if n.kind == N_VARIABLE && !(n.origin >= 0 && p.nodes[n.origin].kind == N_PARAM) {
            if n.first < 0 && n.symbol >= 0 { locals.push(n.symbol); }
            else if n.first >= 0 && p.nodes[n.first].next < 0 && p.nodes[n.first].symbol >= 0 { locals.push(p.nodes[n.first].symbol); }
        }
        statement = n.next;
    }
    if locals.len == 0 { return; }
    var returns: i64[>..] = []; var work: i64[>..] = [body_node]; var at = 0;
    while at < work.len {
        let current = work[at]; at += 1; let n = p.nodes[current];
        if n.kind == N_FUNCTION || n.kind == N_STRUCT || n.kind == N_ENUM || n.kind == N_ALIAS || n.kind == N_IMPORT { continue; }
        if n.kind == N_FUNCTION_VALUE { if n.right >= 0 { work.push(n.right); } continue; }
        if !inline_body && n.kind == N_RETURN && n.symbol == fn_node.symbol || inline_body && n.kind == N_BREAK && n.symbol == function_node { returns.push(current); }
        var child = n.first; while child >= 0 { work.push(child); child = p.nodes[child].next; }
        for child in [n.left, n.right, n.third] { if child >= 0 { work.push(child); } }
    }
    var bound: i64[>..] = [];
    for ordinal in 0..results {
        var candidate = -1; var blocked = false; var others: i64[>..] = [];
        for ret in returns {
            var count = 0; var value = -1; var child = p.nodes[ret].first;
            if p.nodes[ret].kind == N_BREAK {
                child = p.nodes[ret].left;
                if child >= 0 && results > 1 && p.nodes[child].kind == N_TUPLE && p.nodes[child].next < 0 { child = p.nodes[child].first; }
            }
            while child >= 0 { if count == ordinal { value = child; } count += 1; child = p.nodes[child].next; }
            if count != results { blocked = true; continue; }
            var local = -1;
            if value >= 0 && p.nodes[value].kind == N_NAME { for symbol in locals { if symbol == p.nodes[value].symbol { local = symbol; } } }
            if local < 0 { others.push(value); }
            else if candidate < 0 { candidate = local; }
            else if candidate != local { blocked = true; }
        }
        if results == 1 && body.last >= 0 && (p.nodes[body.last].flags & F_TAIL) != 0 && p.nodes[body.last].type_id != TYPE_VOID {
            let tail = p.nodes[body.last]; var local = -1;
            if tail.kind == N_NAME { for symbol in locals { if symbol == tail.symbol { local = symbol; } } }
            if local < 0 { others.push(body.last); }
            else if candidate < 0 { candidate = local; }
            else if candidate != local { blocked = true; }
        }
        if candidate < 0 || blocked { continue; }
        for symbol in bound { if symbol == candidate { blocked = true; } }
        for value in others { if life_may_reach_local(p, value, candidate) { blocked = true; } }
        if blocked { continue; }
        symbols.push(candidate); ordinals.push(ordinal); bound.push(candidate);
    }
}

struct LifeStandalone { function_node: i64, arguments: i64 }

fn life_standalone_type(p: Program&, type_id: i64) -> i64 {
    var work: i64[>..] = [type_id]; var at = 0; var first = -1; var last = -1;
    while at < work.len {
        let ty = work[at]; at += 1; if ty < 0 { continue; } let t = p.types[ty];
        if t.kind == TY_REF && t.length_storage >= 0 { continue; }
        var storage = ty;
        if t.kind == TY_REF { storage = t.element; }
        else if t.kind == TY_SLICE { storage = add_type(p, Type { kind: TY_ARRAY, element: t.element, array_kind: A_GROW }); }
        if at == 1 || t.kind == TY_REF || t.kind == TY_SLICE {
            let field = new_node(p, N_FIELD, -1); p.nodes[field].type_id = storage;
            if first < 0 { first = field; } else { p.nodes[last].next = field; } last = field;
        }
        if t.kind == TY_REF || t.kind == TY_SLICE || t.kind == TY_ARRAY {
            var seen = t.element < 0; for old in work { if old == t.element { seen = true; } }
            if !seen { work.push(t.element); }
        } else if t.kind == TY_STRUCT || t.kind == TY_ENUM || t.kind == TY_TUPLE {
            var child = t.first;
            while child >= 0 {
                let ft = p.nodes[child].type_id; var seen = ft < 0; for old in work { if old == ft { seen = true; } }
                if !seen { work.push(ft); } child = p.nodes[child].next;
            }
        }
    }
    return add_type(p, Type { kind: TY_TUPLE, first: first });
}

fn life_standalone_arguments(p: Program&, l: Lifetimes&, function_node: i64) -> i64 {
    var arguments = -1; var formal = p.nodes[function_node].first;
    while formal >= 0 {
        let type_id = p.nodes[formal].type_id; var value = LifeValue { type_id: type_id };
        if life_is_ref(p, type_id) || life_holds(p, type_id) {
            var pool = -1;
            if p.types[type_id].kind == TY_REF && p.types[type_id].length_storage < 0 {
                for t in p.types {
                    if t.kind != TY_REF || t.length_storage < 0 || t.pool < 0 { continue; }
                    // An owner of named components stands for its components
                    // (upstream poolowners).
                    var named = t.pool; let owner = p.symbols[t.pool].component_owner;
                    if owner >= 0 {
                        if !life_same(p, p.symbols[owner].type_id, p.types[type_id].element) { continue; }
                        named = owner;
                    } else {
                        let global = p.symbols[t.pool].type_id;
                        if global < 0 || p.types[global].kind != TY_ARRAY || p.types[global].array_kind != A_GROW ||
                           !life_same(p, p.types[global].element, p.types[type_id].element) { continue; }
                    }
                    if pool >= 0 && pool != named { pool = -2; break; } pool = named;
                }
            }
            var root = -1; var named = 0;
            if pool >= 0 { named = life_pool_places(p, l, pool); }
            if named != 0 { if life_is_ref(p, type_id) { value.refs = named; } else { value.contents = named; } }
            else {
                let storage = life_standalone_type(p, type_id); root = l.roots.len;
                l.roots.push(LifeRoot { frame: 0, node: formal, type_id: storage });
                let contents = life_root_set(l, root); l.roots[root].contents = contents; l.roots[root].live_contents = contents;
                if life_is_ref(p, type_id) { value.refs = life_root_set(l, root); }
                else { value.contents = life_root_set(l, root); }
            }
        }
        arguments = life_append(l, arguments, value); formal = p.nodes[formal].next;
    }
    return arguments;
}

fn life_validate_pools(p: Program&, l: Lifetimes&, references: const i64[:]) {
    for node in references {
        let t = p.types[p.nodes[node].type_id]; let owner = p.symbols[t.pool]; let ty = owner.type_id;
        if (owner.flags & (S_GLOBAL | S_MUTABLE)) != (S_GLOBAL | S_MUTABLE) || ty < 0 || p.types[ty].kind != TY_ARRAY || p.types[ty].array_kind != A_GROW {
            diagnose(p, p.nodes[node].token, "a relative reference pool must be a mutable grow-only global array");
        } else if !life_contains(p, l, ty, t.element) {
            diagnose(p, p.nodes[node].token, "a relative reference pool cannot contain its pointee type");
        }
    }
}

fn check_lifetimes(p: Program&, scope_parent: const i64[:], scope_depth: const i64[:], scope_functions: const i64[:], pool_references: const i64[:]) {
    if p.diagnostics.len > 0 { return; }
    var roots: LifeRoot[>..] = [LifeRoot {}]; var sets: LifeSet[>..] = [LifeSet {}];
    var alts: LifeAlt[>..] = []; var cells: LifeCell[>..] = []; var frames: LifeFrame[>..] = [LifeFrame {}];
    var items: LifeItem[>..] = []; var pairs: LifePair[>..] = []; var pair_heads: i64[>..] = []; var exits: LifeExit[>..] = [];
    var futures: LifeFuture[>..] = []; var holds: LifeHold[>..] = []; var temps: LifeTemp[>..] = []; var reads: LifeRead[>..] = []; var kills: LifeKill[>..] = []; var atoms: LifeAtom[>..] = []; var failures: LifeFailure[>..] = []; var effects: LifeEffect[>..] = [];
    var symbol_cells: i64[>..] = []; symbol_cells.resize(p.symbols.len, -1);
    var node_roots: i64[>..] = []; var function_frames: i64[>..] = []; var read_heads: i64[>..] = []; var visited: i64[>..] = []; var summary_heads: i64[>..] = [];
    var effect_heads: i64[>..] = []; effect_heads.resize(1024, -1);
    node_roots.resize(p.nodes.len, -1); function_frames.resize(p.nodes.len, -1);
    visited.resize(p.nodes.len, 0);
    summary_heads.resize(2 * p.nodes.len + 1, -1);
    var summaries: LifeSummary[>..] = []; var capture_reads: i64[>..] = [];
    var offers: LifeOffer[>..] = []; offers.resize(65536, LifeOffer {});
    var global_read_spans: LifeSet[>..] = []; var global_read_list: i64[>..] = [];
    var size_classes: i64[>..] = []; size_classes.resize(p.types.len, -1);
    var l = Lifetimes { parents: scope_parent, depths: scope_depth, functions: scope_functions,
        roots: roots, sets: sets, alts: alts, cells: cells, frames: frames, items: items, pairs: pairs, pair_heads: pair_heads, exits: exits,
        futures: futures, holds: holds, temps: temps, reads: reads, kills: kills, size_classes: size_classes, atoms: atoms, failures: failures, effects: effects, symbol_cells: symbol_cells, node_roots: node_roots, function_frames: function_frames, read_heads: read_heads, visited: visited, summary_heads: summary_heads, effect_heads: effect_heads, summaries: summaries, capture_reads: capture_reads, offers: offers, global_read_spans: global_read_spans, global_read_list: global_read_list };
    life_validate_pools(p, l, pool_references);
    if p.diagnostics.len > 0 { return; }
    var standalone: LifeStandalone[>..] = []; let node_count = p.nodes.len;
    for id in 0..node_count {
        let n = p.nodes[id];
        if n.kind != N_FUNCTION || n.right < 0 || (n.flags & (F_CHECKED | F_GENERIC)) != F_CHECKED || id == p.entry { continue; }
        if (n.flags & F_REACHABLE) != 0 && (n.flags & F_THREAD) == 0 { continue; }
        if n.symbol < 0 || p.symbols[n.symbol].owner >= 0 { continue; }
        standalone.push(LifeStandalone { function_node: id, arguments: life_standalone_arguments(p, l, id) });
    }
    while node_roots.len < p.nodes.len { node_roots.push(-1); function_frames.push(-1); visited.push(0); }
    while summary_heads.len < 2 * p.nodes.len + 1 { summary_heads.push(-1); }
    while size_classes.len < p.types.len { size_classes.push(-1); }
    // Standalone argument synthesis is complete; evaluation only reads types.
    l.types_frozen = true;
    // All equations only add alternatives or weaken exactness. A changed
    // invocation feeds its caller and loops on the following discovery pass.
    loop {
        l.pass += 1;
        let before = l.revision;
        for symbol in p.symbols {
            if (symbol.flags & S_GLOBAL) != 0 && symbol.node >= 0 && p.nodes[symbol.node].kind == N_VARIABLE {
                life_eval(p, l, symbol.node);
            }
        }
        if p.entry >= 0 { life_function(p, l, p.entry, -1, -1, 0); }
        for root in standalone { life_function(p, l, root.function_node, -1, root.arguments, 0); }
        if l.failures.len > 0 {
            l.discovery = false;
            for failure in l.failures { life_error(p, l, failure.node, failure.message); }
            l.types_frozen = false;
            return;
        }
        if l.revision == before { break; }
    }
    l.discovery = false;
    for root, index in l.roots { l.roots[index].live_contents = root.contents; }
    for cell, index in l.cells { l.cells[index].live = false; }
    for symbol in p.symbols {
        if (symbol.flags & S_GLOBAL) != 0 && symbol.node >= 0 && p.nodes[symbol.node].kind == N_VARIABLE { life_eval(p, l, symbol.node); }
    }
    if p.entry >= 0 { life_function(p, l, p.entry, -1, -1, 0); }
    for root in standalone { life_function(p, l, root.function_node, -1, root.arguments, 0); }
    l.types_frozen = false;
    if p.diagnostics.len == 0 { life_export_provenance(p, l); life_refresh_named_results(p); }
}
