import model;

// Provenance is a property of an evaluated value, not of its syntax. All
// links are stable arena IDs; recursive visits borrow the arenas below.
// Binding bounds retain caller-storage depth without changing alias roots.
// Stored edges retain their pointee type: an array reference in one field
// must not become an element reference when another field is read.
// A root struct's fields are stored apart: component names the field node of
// the root owner whose storage this is, -1 the owner as a whole (upstream
// RootComponent identities). Contents stay with the owner.
// Every field is an ID or a depth well inside 32 bits (next indexes alts,
// whose 2 GiB region holds fewer than 2^27 of them), so an alternative takes
// 27 bytes instead of 51, and the region holds 79.5 M instead of 42.1 M.
struct LifeAlt { root: i32, from: i32 = -1, target_type: i32 = -1, bound: i32 = 0, next: i32 = -1, component: i32 = -1, exact: bool = true, slotread: bool = false, byteview: bool = false }
// Every LifeSet is stored as a contiguous slice of l.alts[first..first+count],
// sorted ascending by root (with next links preserved for traversal).
// plain: the set without its class roots (life_strip), itself if it has
// none, once asked; -1 before. folded, lasting: likewise what life_fold and
// life_lasting make of it. interior caches the concrete interior projection.
struct LifeSet { first: i32 = -1, count: i32 = 0, bound_depth: i32 = -1, bound_result: i32 = 0, plain: i32 = -1, folded: i32 = -1, lasting: i32 = -1, interior: i32 = -1, slotread: i32 = -1, flags: u8 = 0 }
// Entries index global_read_list. The frame-zero capture head identifies the set of cells.
struct LifeCaptureSpan { first: i64 = 0, count: i64 = 0, head: i64 = -1 }
// What the nodes a walk reaches from `start` say without following calls
// (life_body): whether one names a captured binding, the globals they name
// (a span of body_globals, as found) and the nodes their calls go on to (a
// span of body_calls, sorted). seen: the life_body_walk that last reached it.
// owners: the functions that own the captured bindings it names, a span of
// body_owners, each once. named: those bindings themselves, a span of
// body_captures, sorted, each once. global_inputs caches the reachable frame-zero cells.
struct LifeBody { start: i64, captures: bool = false, globals: i64 = 0, global_count: i64 = 0, calls: i64 = 0, call_count: i64 = 0, seen: i64 = 0, owners: i64 = 0, owner_count: i64 = 0, named: i64 = 0, named_count: i64 = 0, global_inputs: LifeCaptureSpan = LifeCaptureSpan {}, trans_globals: i64 = 0, trans_global_count: i64 = -1 }
// class_frame, class_index: for a class root, the class-keyed frame it
// belongs to and its class there (life_classify, life_class_new);
// class_one: it stands for one root exactly at every call. map_serial,
// map_class: the classification that last gave this root a class, and the class.
// class_parent, class_type: for a storage class of one pointee type
// (life_class_typed), the class root whose storage it is of and the pointee;
// class_pointee: for an argument class, the type its parameters point at
// (the outermost, where one holds the others), or -2 where that is not one
// type: an exact reference to the class points into a value of that type.
// class_mask: for a storage class, the argument classes of its frame (a bit
// each, by index) that a reference read out as this class may be: those
// whose parameters' type can hold its pointee (life_class_candidates).
// class_next: the next such root of its frame; class_level: how many such
// classes deep it is. stored: for any class root, what its frame's body has
// stored through it; stored_next: the next class root of the frame that has
// been stored through, -1 at the last, -2 while this one has not. stores:
// what life_class_stores last found for it, as of the frame's stored_version.
// any_set: what life_class_any_set made of it for the call any_serial.
struct LifeRoot { symbol: i64 = -1, frame: i64 = -1, node: i64 = -1, type_id: i64 = -1, depth: i64 = 0, temporary: bool = false, contents: i64 = 0, live_contents: i64 = 0, atoms: i64 = -1, slotread_set: i32 = -1, next_node: i64 = -1, class_frame: i64 = -1, class_index: i64 = -1, class_one: bool = false, map_serial: i64 = 0, map_class: i64 = -1, class_parent: i64 = -1, class_type: i64 = -1, class_next: i64 = -1, class_level: i64 = 0, stored: i64 = 0, stored_next: i64 = -2, stores: i64 = 0, stores_version: i64 = -1, any_set: i64 = 0, any_serial: i64 = 0, class_pointee: i64 = -1, class_holder: i64 = -1, class_empty: bool = false, class_mask: i64 = 0, first_kill: i64 = -1, any_held: i64 = 0, any_held_serial: i64 = 0, last_atom_set: i32 = -1, param_frame: i64 = -1 }
// Element owner: -1 none, -2 inside elements with unknown owner, otherwise type ID.
// reached: of a reference argument, life_reached of its expression (the
// type of the storage it points into), for the stores a call makes through it.
struct LifeValue { type_id: i32 = -1, place: i32 = 0, refs: i32 = 0, contents: i32 = 0, self_pools: i32 = 0, relative_roots: i32 = 0, tuple: i32 = -1, element_array: i32 = -1, reached: i32 = -1, readonly: bool = false }
let LIFE_EMPTY_VALUE = LifeValue {};
struct LifeItem { value: LifeValue, next: i32 = -1 }
// live is set and cleared through life_set_live, which mirrors it in live_bits.
struct LifeCell { symbol: i32, frame: i32, root: i32, parameter: bool = false, refs: i32 = 0, live_refs: i32 = 0, contents: i32 = 0, initial: i32 = 0, committed: bool = false, readonly: bool = false, growshrink: bool = false, depth: i32 = 0, initialized: bool = false, live: bool = false, next_symbol: i32 = -1, next_frame: i32 = -1, next_capture_input: i32 = -1, next_parameter: i32 = -1, param_bound_root: i32 = -1 }
// first_other, last_other: discovery effects that need individual replay,
// in insertion order. replay_version changes whenever a replayable leaf
// is added or updated, invalidating a completed replay of this summary.
// chain: how many frames the parent chain holds, set at each activation.
// chain_recursive: the nearest recursive frame of that chain, from this
// frame up, or 0, as of recursion epoch chain_epoch (life_nearest_recursive).
// inputs_hash, inputs_kinds: life_inputs_key of inputs. mixed_kinds: an
// older frame of the function has other kinds. next_inputs, next_home: the
// next older frame in its input_heads and home_heads buckets.
// function_active: on the newest frame of a function, how many of the
// function's frames are active.
struct LifeFrame { store_read_pass: i64 = 0, store_reader: i64 = -1, function_node: i64 = -1, parent: i64 = -1, lexical: i64 = 0, call: i64 = -1, inputs: i64 = -1, base: i64 = 0, active: bool = false, result: LifeValue = LifeValue {}, live_result: LifeValue = LifeValue {}, slice_slots: bool = false, destination: i64 = 0, selected_result: i64 = -1, checked_revision: i64 = -1, next_function: i64 = -1, first_cell: i64 = -1, first_capture_input: i64 = -1, first_parameter: i64 = -1, first_effect: i64 = -1, last_effect: i64 = -1, validated: bool = false, first_summary: i64 = -1, last_summary: i64 = -1, effect_epoch: i64 = 0,
    // Validation can deduplicate a shrink only after the latest kind >= 4.
    // Stores and kills need only check intervening operations of the opposite kind.
    last_shrink_barrier: i64 = -1, last_shrink: i64 = -1, last_store: i64 = -1, last_kill: i64 = -1, recursive_call: bool = false, home: i64 = -1, capture_inputs: i64 = -1, cycle: i64 = -1, activation: i64 = 0, context: i64 = 0, first_other: i64 = -1, last_other: i64 = -1, replay_version: i64 = 0, first_read: i64 = -1, last_read: i64 = -1, read_table: i64 = 0, read_cap: i64 = 0, read_count: i64 = 0, chain: i64 = 0, chain_epoch: i64 = -1, chain_recursive: i64 = 0, inputs_hash: i64 = 0, inputs_kinds: i64 = 0, mixed_kinds: bool = false, next_inputs: i64 = -1, next_home: i64 = -1, function_active: i64 = 0,
    first_exit: i64 = -1, parameter_version: i64 = 0,
    // island: the class-keyed frame this frame last ran under, itself for
    // such a frame, 0 for none. For a class-keyed frame: classes, class_count:
    // its class roots, class_base of them for the arguments (the last of
    // those for the destination alone where result_class says so) and then
    // twice as many for what their storage holds, one and two reads in
    // (life_class_new); key, key_len, key_hash: its key in class_keys;
    // next_class: the next frame of its class_heads bucket; map_base: the sets
    // of the call it is being evaluated for (map_sets); assumptions: what its
    // body has asked of those sets (LifeAssume); class_destination: the set
    // its body builds a result in; discovered: evaluated in a discovery pass;
    // class_stored: what its body has stored of its class roots in storage
    // outside it (life_keep_outside). stored_first: the newest of its class
    // roots that its body has stored through (LifeRoot.stored_next);
    // stored_version: counts the changes to what was stored through them and
    // to the answers about them. map_serial: a number for the call it is being
    // evaluated for; assume_count: how many questions it has recorded;
    // all_stored, stored_count: everything stored through its class roots, and
    // through how many of them. typed_count: how many storage classes of one
    // pointee type it has.
    // quiet_pass (any frame): the discovery pass in which it was last evaluated
    // without a summary being kept (life_effect). typed_first: its newest
    // storage class of one pointee type (LifeRoot.class_next).
    island: i64 = 0, classes: i64 = -1, class_count: i64 = 0, class_base: i64 = 0, key: i64 = -1, key_len: i64 = 0, key_hash: i64 = 0, next_class: i64 = -1, map_base: i64 = -1, assumptions: i64 = -1, class_destination: i64 = 0, discovered: bool = false, result_class: i64 = -1, class_stored: i64 = 0, quiet_pass: i64 = -1, typed_first: i64 = -1, stored_first: i64 = -1, stored_version: i64 = 0, map_serial: i64 = 0, assume_count: i64 = 0, all_stored: i64 = 0, stored_count: i64 = 0, typed_count: i64 = 0, pod_typed_count: i64 = 0,
    dep_valid: bool = false, dep_in_rec: bool = false,
    dep_roots_first: i64 = 0, dep_roots_count: i64 = 0,
    dep_callees_first: i64 = 0, dep_callees_count: i64 = 0,
    dep_contents_stamp: i64 = 0, dep_global_epoch: i64 = 0, dep_rec_epoch: i64 = 0, dep_dest: i64 = 0,
    dep_clean_pass: i64 = -1, dep_dirty_pass: i64 = -1, dep_change_stamp: i64 = 0,
    dep_stored_ver: i64 = -1,
    validated_global_epoch: i64 = -1, summary_version: i64 = 0,
    noncautious_ver: i32 = 0, defer_base: i32 = 0, has_deep_assume: bool = false, has_gs_assume: bool = false, val_stores_only: bool = false, val_stores_shallow: bool = false }
// The live storage and killed fields are the two mutable inputs of a
// concrete holder reached during a shrink check.
struct LifeWalkRoot { root: i64 = 0, contents: i64 = 0, kills: i64 = -1 }
struct LifeWalkMemo {
    owners: i64 = -1, holder: i64 = -1, target: i64 = -1, element: i64 = -1,
    slot_safe: bool = false, first: i64 = 0, count: i64 = 0, epoch: i64 = -1,
    grow_epoch: i64 = -1, island_act: i64 = -1, global_only: bool = false,
}
struct LifeShrinkClean { place: i64 = -1, type_id: i64 = -1, epoch: i64 = -1, frame: i64 = -1, fhash: u64 = 0, all: bool = false }
struct LifeGlobalShrinkClean { place: i64 = -1, type_id: i64 = -1, epoch: i64 = -1, island_act: i64 = -1, frame: i64 = -1, fhash: u64 = 0, all: bool = false }
struct LifeOvSlot { gen: i32 = 0, root: i32 = -1, comp: i32 = -1, tt: i32 = -1, flags: u8 = 0, ans: bool = false }
struct LifeWalkElem { type_id: i32 = -1, flags: u8 = 0 }
struct LifeWalk { root: i64, type_id: i64 }
struct LifeWalkSlot { root: i32 = -1, type_id: i32 = -1, gen: i32 = 0 }

// Precomputed per-type, per-symbol and per-node bit flags (life_prepare_nodes).
let TF_L_REF: u8 = 1;
let TF_L_HOLDS: u8 = 2;
let TF_L_SC1: u8 = 4;
let TF_L_SC2: u8 = 8;
let TF_L_REL: u8 = 16;
let TF_L_REL_POOL: u8 = 32;
let TF_L_SCALAR: u8 = 64;
let TF_L_BYTES: u8 = 128;

let SF_ADDR_TAKEN: u8 = 1;
let SF_SCALAR_LOCAL: u8 = 2;

let NF_NEEDS_PLACE: u8 = 1;
let NF_IN_FOR_SEQ: u8 = 2;
let NF_HAS_EXIT: u8 = 4;
let NF_PURE_PLACE: u8 = 8;
let NF_INERT: u8 = 16;
let NF_MAY_SHRINK: u8 = 32;
let NF_FN_INERT: u8 = 64;
let NF_ANALYZED: u8 = 128;

// Per-node / per-function reachability of overlapping construction holds (life_prepare_nodes).
let FH_CONSTRUCT_READ: u8 = 1;
let FH_BUILD_HOLD: u8 = 2;
let FH_FORMAT_RAW: u8 = 4;
let FH_SC2_SITE: u8 = 8;
// What a class-keyed frame's body asked about the arguments its classes stand
// for, and the answer it was checked with (life_class_query): a later call
// shares the frame only where its own arguments answer the same.
// query 0: class `index` may point into grow-shrink elements that hold type
// `subject` (flag: as a byte view); 1: a holder of type `subject` rooted there
// may view such elements; 2: its storage has one array of element `subject`;
// 3: it may alias root `subject` (flag: named exactly); 4: it may alias class
// `subject`; 6: it is exactly root `subject`.
// frame: whose; the entries of all frames are found through assume_slots.
// open: 0 for an answer; while the answer is being worked out, how deep in
// nested questions that is (life_class_query); -1 where it was left open,
// to be asked again.
struct LifeAssume { frame: i32, query: i32, index: i32, subject: i32, next: i32 = -1, open: i32 = 0, ver: i32 = 0, flag: bool, answer: bool }
// A call's classes (life_classify): where its sets and sorted depths are in
// map_sets and map_depths, its key in key_scratch, and the key's hash.
// serial: of this classification.
struct LifeClasses { sets: i64 = 0, count: i64 = 0, depths: i64 = 0, depth_count: i64 = 0, key_len: i64 = 0, hash: i64 = 0, serial: i64 = 0 }
// How a class-keyed frame's roots read at one call: class root classes + k,
// for k below base, is the set map_sets[sets + k], or the root
// map_roots[sets + k] where that is not negative; the others are what the
// storage of those holds (life_class_set); a bound 2 * (r + 1) is the depth
// map_depths[depths + r]. serial: of the call, for map_memo.
struct LifeMap { classes: i64 = 0, count: i64 = 0, base: i64 = 1, sets: i64 = 0, depths: i64 = 0, depth_count: i64 = 0, serial: i64 = 0, frame: i64 = -1, start_epoch: i64 = 0, call_serial: i64 = 0 }
// What life_map_set made of a set for the call of this serial.
struct LifeRefers { holder: i64 = -1, pointee: i64 = -1, answer: bool = false }
struct LifeMapped { serial: i32 = -1, key: i32 = -1, result: i32 = 0, epoch: i32 = -1 }
struct LifeListSlot { key: i64 = -1, set: i32 = -1, count: i32 = 0 }
struct LifeAssumeSlot { meta: i32 = 0, index: i32 = -1, subject: i32 = -1, at: i32 = -1 }
struct LifeSummarySlot { key: i64 = -1, index: i32 = -1, frame: i32 = -1 }
struct LifeLeafSlot { key: i64 = -1, leaf: i32 = -1, node: i32 = -1 }
struct LifeTypedSlot { parent: i32 = -1, pointee: i32 = -1, root: i32 = -1 }
struct LifePairSlot { owner: i32 = -1, pointee_ans: i32 = 0 }
struct LifeCallSig {
    hash: i64 = 0, frame: i32 = -1, island: i32 = 0, base: i32 = 0, start: i32 = 0, active: bool = false, next: i32 = -1,
    checked_assumes: i32 = -1, checked_epoch: i64 = -1, checked_stamp: i64 = -1, checked_island_act: i64 = -1, checked_island_stored: i64 = -1, checked_discovery: bool = false,
    checked_roots_first: i32 = 0, checked_roots_count: i32 = 0,
    replayed_caller: i32 = -1, replayed_act: i32 = -1, replayed_sum_ver: i64 = -1, replayed_epoch: i64 = -1,
    replayed_glob: i64 = -1, replayed_cells: i64 = -1, replayed_rec: i32 = -1, replayed_rp: bool = false,
    val_caller: i32 = -1, val_act: i32 = -1, val_target_ep: i32 = -1, val_held_ep: i64 = -1, val_live_ep: i64 = -1, val_kill_ep: i64 = -1,
}
struct LifeHeldOwn { set: i32 = -1, result: i32 = 0, discovery: bool = false, stamp: i64 = 0, epoch: i64 = -1 }
struct LifeExit { node: i32, next: i32, value: LifeValue, destination: i32 = 0, selected_result: i32 = -1 }
struct LifeFuture { node: i64, frame: i64, scope: i64, loop_scope: i64 = -1, last: i64 = -1 }
struct LifeFutureExit { frame: i64 = -1, scope: i64 = -1, before: i64 = 0 }
struct LifeDefer { node: i32, scope: i32, frame: i32 }
struct LifeDeferTarget { node: i32, defer_mark: i32 }
struct LifeSpanSlot { start: i32 = -1, last: i32 = -1, body: i32 = -1 }
// A question a shrink check has asked of a live cell, and its answer
// (life_shrink_array): a reference's pointee type and what it refers to, or
// a holder's type, place and contents.
struct LifeAsked { a: i64, b: i64, c: i64, into: bool, next: i32 , all_global: bool = false }
struct LifeHold { value: LifeValue, node: i32, kind: i32 = 0, frame: i32 = 0 }
struct LifeTemp { frame: i64 }
struct LifeRead { node: i32, last: i32, symbol: i32, next: i32 = -1, answer: bool }
struct LifeKill { field: i64, next: i64, first: i64 = -1, count: i64 = 0 }
struct LifeAtom { set: i64, next: i64 = -1 }
// An atom_slots entry: an atom's hash, its one alternative and its set.
struct LifeAtomSlot { key: i64 = -1, alt: i32 = -1, set: i32 = -1 }
// What life_candidates reads of a cell, in index order: its root's depth and
// type, the type's element when it is a reference or slice (else -1), and
// whether its symbol is global. None of these change.
struct LifeCellKey { root: i32, depth: i32, type_id: i32, element: i32, global: bool }
// The candidates a global container's read-back finds for one pointee type
// (life_global_candidates): a span of candidate_alts, made at a global_epoch
// and for a depth and whether later global declarations are included.
struct LifeGlobalCandidates { epoch: i64 = -1, depth: i64 = 0, first: i64 = 0, count: i64 = 0, all_globals: bool = false }
// A join of two sets and its result (life_join).
struct LifeJoin { a: i32 = -1, b: i32 = -1, set: i32 = -1 }
// The contents of a set of places (life_contents) as of contents_stamp
// `stamp`: it holds while no root of the places has its contents changed
// after that (Lifetimes.root_stamps).
struct LifeContents { places: i64 = -1, stamp: i64 = 0, set: i64 = 0 }
// What life_load makes of a holder's contents and its places: `contents` is
// twice the contents set, plus one for a slot load.
struct LifeLoaded { contents: i64 = -1, places: i64 = -1, set: i64 = 0 }
// Read through a single exact local container in an ordinary frame.
struct LifeLocalRead { places: i64 = -1, type_id: i64 = -1, frame: i64 = -1, contents: i64 = -1, parameters: i64 = -1, result: i64 = 0 }
// What a read-back through global containers found (life_readback): it holds
// for its type and places while global_epoch stays at `epoch`.
struct LifeReadBack { type_id: i64 = -1, places: i64 = -1, epoch: i64 = -1, set: i64 = 0 }
// index_key, index_next and epoch: a validation-pass effect's hash, chain
// in effect_heads and its frame's effect_epoch when it was recorded.
// previous_barrier links stores to stores and kills to kills, newest first.
// walked: for an unordered effect, 1 once an equal effect has gone on from its
// frame up the chain, 2 if a place of one was outside every frame of the
// chain; as LifeSummary.walked, for the frame's current list.
struct LifeEffect { kind: i32, node: i32, value: LifeValue, places: i32 = 0, cell: i32 = -1, field: i32 = -1, next: i32 = -1, previous_barrier: i32 = -1, owner: i32 = -1, index_key: i64 = -1, index_next: i32 = -1, epoch: i32 = 0, walked: i8 = 0 }
struct LifeGlobalShrink { node: i64, place: i32, type_id: i32, frame: i64 }
struct LifeFailure { node: i64, kind: i64 }
// Per effect, for discovery merges: the next effect in its
// summary_heads bucket, the fields a merge compares exactly (copies of the
// effect's own, which never change), and the sets last merged into it. Merging
// those same sets again changes nothing: an entry only grows, and a join with
// a subset returns the entry's own set.
// walked: twice the owner's activation in which an offer of those last sets
// went on from this entry up the chain, plus one if a place of that offer
// was outside every frame of the chain. The chain above a frame is fixed for
// its activation. An offer with every place in a frame of the chain is taken
// by the frames below the outermost of those frames, and those of them above
// the owner are the same frames for the same sets later in the activation;
// an offer with a place outside the chain is taken by every frame. So the
// frames above have nothing more to take from the same sets (life_effect),
// unless one of them is recursive, which also takes by its cells.
// replayed: the activation of the frame this entry's effect was last
// replayed into (life_replay), at recursion epoch replayed_epoch, if every
// offer of that replay was one no recursive frame takes by its cells
// (Lifetimes.offer_recursive); -1 once the entry's sets change. The same
// sets replayed into that activation again change nothing.
struct LifeSummary {
    owner: i32 = -1, kind: i32 = 0, node: i32 = -1, type_id: i32 = -1, cell: i32 = -1, field: i32 = -1,
    places: i32 = -1, refs: i32 = -1, contents: i32 = -1, place: i32 = -1, walked: i32 = -1,
    replayed: i32 = -1, replayed_epoch: i32 = -1,
    // leaf: the interned kind, node and value of a replayable effect, or -1
    // before its first replay and after its sets change.
    // after: the effect's next in its frame's list (LifeEffect.next), so that
    // a replay passes an entry it skips without reading the effect.
    // other: the next summary entry that needs individual replay.
    leaf: i32 = -1, after: i32 = -1, other: i32 = -1,
}
// A construct read by what offering it depends on: its node and its value.
// Summaries of different frames hold the same read under different entries;
// they share a leaf.
struct LifeLeaf { kind: i32, node: i32, value: LifeValue }
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
// through both in that order. changed: the summary version that installed
// this leaf. A different last offer (seen) can leave the joined leaf intact.
struct LifeReadEntry { changed: i64, key: i64, leaf: i32, seen: i32, walked: i32 = -1, sent: i32 = -1, next: i32 = -1, before: i32 = -1 }
// A chain of active frames: a frame, and the chain its caller was in.
struct LifeChainReplay { key: i64 = -1, version: i32 = -1 }
struct LifeContext { frame: i64, parent: i64, next: i64 = -1 }
// A discovery effect offered up the frame chain, remembered by what the
// offer depends on: its current frame's activation (which fixes the chain of
// active frames above it), the recursion flags then, and every field a merge
// or insertion compares. Summary entries only grow, so the same offer again
// changes nothing.
struct LifeOffer {
    frame: i32 = -1, activation: i32 = -1, epoch: i32 = -1, kind: i32 = -1, node: i32 = -1, type_id: i32 = -1,
    cell: i32 = -1, field: i32 = -1, places: i32 = -1, refs: i32 = -1, contents: i32 = -1, place: i32 = -1,
}
struct LifeInexactRead { places: i32 = -1, type_id: i32 = -1, result: i32 = 0, version: i64 = -1 }
struct LifeFarMemo { places: i32 = -1, activation: i32 = -1, epoch: i32 = -1, home: i32 = 0, far: i64 = 0, cyclic: bool = false }
struct Lifetimes {
    parents: const i64[>..]&, depths: const i64[>..]&, functions: const i64[>..]&,
    roots: LifeRoot[>..]&, sets: LifeSet[>..]&, alts: LifeAlt[>..]&, cells: LifeCell[>..]&,
    held_walks: LifeWalkMemo[>..]&,
    frames: LifeFrame[>..]&, items: LifeItem[>..]&, pair_slots: LifePairSlot[>..]&, pair_count: i64 = 0, exits: LifeExit[>..]&,
    futures: LifeFuture[>..]&, holds: LifeHold[>..]&, temps: LifeTemp[>..]&, reads: LifeRead[>..]&,
    kills: LifeKill[>..]&,
    size_classes: i64[>..]&, types_frozen: bool = false,
    // For a type, where its reference and slice types are in holder_refs
    // and how many (life_holder_scan), or -1 before they are listed.
    holder_starts: i64[>..]&, holder_counts: i64[>..]&, holder_refs: i64[>..]&,
    // The index and bound types that name a pool, listed when the types are
    // frozen (life_index_shrink).
    index_types: i64[>..]&, asked: LifeAsked[>..]&,
    atoms: LifeAtom[>..]&,
    failures: LifeFailure[>..]&, effects: LifeEffect[>..]&,
    symbol_cells: i32[>..]&, node_roots: i32[>..]&, function_frames: i32[>..]&, visited: i32[>..]&, summary_slots: LifeSummarySlot[>..]&, summary_slot_count: i64 = 0,
    // Cached life_reads answers by (node, symbol), chained through reads.
    read_heads: i32[>..]&,
    // Per body start: 0 unknown, 1 no reachable capture, 2 a reachable capture.
    capture_reads: i8[>..]&,
    // Sorted cell IDs for the current global capture head. Spans live on the bodies.
    global_read_list: i64[>..]&,
    // The bodies scanned so far, by start node (open addressing in
    // body_slots), their spans, and the walks made over them.
    bodies: LifeBody[>..]&, body_slots: i64[>..]&, body_globals: i64[>..]&, body_calls: i64[>..]&, body_walks: i64 = 0,
    // Recent discovery offers (direct-mapped; grown by life_offer_repeated),
    // the offers recorded since it last grew, the activation count, and how
    // many times a frame's recursion flag has been set.
    offers: LifeOffer[>..]&, offers_recorded: i64 = 0, activations: i64 = 0, recursion_epoch: i64 = 0,
    // Since life_replay last cleared them: how many effects were offered, and
    // whether one had a place in a recursive frame of the chain, which such a
    // frame may take by its cells (life_effect_recursive) as they grow.
    offer_count: i64 = 0, offer_recursive: bool = false,
    effect_heads: i32[>..]&, indexed_effects: i64 = 0,
    // Per effect, kept apart from the effects themselves so a bucket walk
    // stays in dense memory.
    summaries: LifeSummary[>..]&,
    // Construct reads offered (life_leaf): the leaves, their hash heads, and
    // for each the activation it was last offered from with the recursion
    // epoch then, as one number, and how far up the chain that offer went
    // (life_leaf_offered).
    leaves: LifeLeaf[>..]&, leaf_slots: LifeLeafSlot[>..]&, leaf_stamps: i64[>..]&, leaf_floors: i32[>..]&,
    // The construct reads of the frames' summaries while `compact`, and the
    // frames' tables of them (LifeFrame.read_table, read_cap of read_slots:
    // an index into summary_reads or -1, by life_read_hash of the key).
    summary_reads: LifeReadEntry[>..]&, read_slots: i32[>..]&,
    // Chains of frames by number (life_context: a frame and its parent's chain).
    contexts: LifeContext[>..]&, context_heads: i32[>..]&,
    // For a chain of frames and a frame whose summary was replayed in it with
    // every replayable leaf offered (life_replay): the summary's replay_version
    // then. An open-addressed map from chain, frame and recursion epoch in
    // one word (life_chain_key).
    chain_replays: LifeChainReplay[>..]&, chain_replay_count: i64 = 0,
    // Open LifeBuild buffers and their root tables, as stacks.
    build_alts: LifeAlt[>..]&, build_slots: i64[>..]&,
    // Lists being made or read once (life_list_set, life_build_drop), as a
    // stack.
    scratch: LifeAlt[>..]&,
    // Lists made by joins and builds (life_list_set): open addressing storing
    // (key, set, count) inline in one 16-byte slot.
    list_slots: LifeListSlot[>..]&, list_count: i64 = 0,
    // Atoms by their alternative (life_single), open addressing.
    atom_slots: LifeAtomSlot[>..]&,
    // Per cell (life_candidates).
    cell_keys: LifeCellKey[>..]&,
    // (symbol, frame) to its cell and (node, frame) to its temporary root, by
    // open addressing over cell and root indexes; how many temporaries.
    cell_slots: i32[>..]&, temp_slots: i32[>..]&, temporaries: i64 = 0,
    // Recent life_contents answers, direct-mapped by the places set and grown
    // as joins are; how many times a root's contents have changed; and for
    // each root the count at its last change.
    contents_memo: LifeContents[>..]&, contents_recorded: i64 = 0, contents_stamp: i64 = 0, root_stamps: i64[>..]&,
    // Recent life_load results, direct-mapped.
    loaded: LifeLoaded[>..]&, loaded_recorded: i64 = 0,
    // The last life_gs_contains answer for each owner type, and what it was
    // asked: twice the pointee type, plus one for a byte view.
    gs_asked: i64[>..]&, gs_answer: bool[>..]&,
    // Recent read-backs through global containers, direct-mapped.
    local_reads: LifeLocalRead[>..]&, local_read_writes: i64 = 0, readbacks: LifeReadBack[>..]&, readbacks_recorded: i64 = 0,
    inexact_reads: LifeInexactRead[>..]&, inexact_read_writes: i64 = 0,
    cell_clock: i64 = 0, depth_clock: i64[>..]&, far_cache: LifeFarMemo[>..]&,
    // Per type and include_pool: life_relative_storage, 0 until asked, then 1 or 2.
    relative_storage: i64[>..]&,
    // The cells of frame 0 whose root is deeper than depth 0: a local of a
    // global's initializer. Only those count toward what frame 0 reaches
    // (life_reach); the globals themselves are at depth 0.
    deep_cells: i64[>..]&,
    // Frames by function, lexical frame, selected result and argument sets
    // (life_inputs_key), and by function, home frame and call: bucket heads
    // of chains through LifeFrame.next_inputs and next_home, newest first as
    // function_frames is.
    input_heads: i32[>..]&, home_heads: i32[>..]&,
    // Class tables of life_classes_cover, as a stack: alternative and hash.
    class_slots: i64[>..]&,
    // Recent joins of large sets, direct-mapped, and how many were recorded
    // since the table last grew. Sets never change and equal lists are one
    // set, so a join of the same two sets is the same set again.
    joins: LifeJoin[>..]&, joins_recorded: i64 = 0,
    // The global cells in index order; how many times one's liveness or refs
    // changed; and by pointee type, the candidates a global container's
    // read-back found, whose lists candidate_alts holds for candidate_epoch.
    // An inexact store may land outside the root that bounds it. Until it
    // is attributed to a specific holder, exact store records cannot
    // establish that another holder never took that reference.
    unknown_stores: bool = false,
    global_cells: i64[>..]&, global_epoch: i64 = 0, global_candidates: LifeGlobalCandidates[>..]&, candidate_alts: LifeAlt[>..]&, candidate_epoch: i64 = 0,
    // The last life_contains answer for each owner type, and its pointee.
    contains_pointee: i64[>..]&, contains_answer: bool[>..]&,
    // Live cells by index: bit c % 64 of live_bits[c / 64], and bit w % 64 of
    // live_words[w / 64] while live_bits[w] is not zero.
    live_bits: u64[>..]&, live_words: u64[>..]&, holder_bits: u64[>..]&,
    live_holder_bits: u64[>..]&, live_holder_words: u64[>..]&,
    walk_work: LifeWalk[>..]&, walk_scanned: i64[>..]&, walk_memo_roots: LifeWalkRoot[>..]&,
    walk_seen: LifeWalkSlot[>..]&, walk_seen_count: i64 = 0, walk_gen: i64 = 0, walk_elems: LifeWalkElem[>..]&, last_walk_global: bool = false,
    shrink_safe: LifeWalkSlot[>..]&, shrink_safe_count: i64 = 0, shrink_safe_gen: i64 = 0, shrink_safe_global: bool = true,
    global_shrinks: LifeGlobalShrink[>..]&,
    global_future_mark: i64[>..]&, future_global_gen: i64 = 0, last_future_nodes: i64[>..]&, last_future_lasts: i64[>..]&,
    shrink_clean: LifeShrinkClean[>..]&, global_shrink_clean: LifeGlobalShrinkClean[>..]&, shrink_ov: LifeOvSlot[>..]&,
    type_flags: u8[>..]&, sym_flags: u8[>..]&, node_flags: u8[>..]&, scope_has_cell: u8[>..]&, hold_flags: u8[>..]&,
    dep_roots: i64[>..]&, dep_callees: i64[>..]&, dep_callee_stamps: i64[>..]&,
    dep_root_stack: i64[>..]&, dep_callee_stack: i64[>..]&, dep_callee_stamp_stack: i64[>..]&,
    dep_root_mark: i64[>..]&, dep_callee_mark: i64[>..]&,
    clean_work: i64[>..]&, clean_gen: i64 = 0,
    dep_gen: i64 = 0, dep_root_floor: i64 = 0, dep_tainted: bool = false,
    global_refs_epoch: i64 = 0, global_live_count: i64 = 0,
    settled_global_epoch: i64 = -1, settled_global_refs: i64 = -1, settled_global_live: i64 = -1,
    cls_dep_tainted: bool = false, cls_min_back: i64 = 9223372036854775807, cls_child_rev: i64 = 0,
    live_epoch: i64 = 0, holder_grow_epoch: i64 = 0, global_live_epoch: i64 = 0,
    build_holds: i64 = 0, construct_holds: i64 = 0, format_holds: i64 = 0,
    nodes_prepared: bool = false, has_captures: bool = true,
    visit: i64 = 0,
    frame: i64 = 0, scope: i64 = 0, revision: i64 = 0, discovery: bool = true,
    future_count: i64 = 0, hold_count: i64 = 0, temp_count: i64 = 0,
    reading_place: i64 = 0,
    conditional: i64 = 0,
    sequence_path: i64 = -1,
    pass: i64 = 0,
    // Class-keyed frames (life_class_call). island: the one being evaluated,
    // or 0; hold_floor, future_floor: where its holds and futures begin.
    // class_frames: how many there are; class_list: their frames;
    // class_heads: buckets of their keys, held in class_keys.
    // map_sets, map_roots, map_depths: the classes of the calls in progress,
    // as stacks; key_scratch, class_scratch: a key and class depths in the
    // making. assumes: LifeAssume entries.
    // compact: summaries hold their construct reads in summary_reads; until
    // the first class-keyed frame (life_reads_materialize).
    omit_construct_reads: bool = false, compact: bool = true,
    future_exit: LifeFutureExit = LifeFutureExit {}, pending_defers: i64 = 0,
    island: i64 = 0, hold_floor: i64 = 0, future_floor: i64 = 0, class_frames: i64 = 0, classify_serial: i64 = 0,
    // How deep in nested class questions the pass is, and the shallowest open
    // question one of them met again (life_assume_open).
    query_depth: i64 = 0, query_cut: i64 = 4611686018427387904,
    // The call whose roots a question is being answered from (LifeRoot.any_serial).
    any_serial: i64 = 0,
    // The root that stands for some global storage (life_fold), or -1, and
    // for what pointee, as of what global_epoch, a global was last found to
    // hold grow-shrink elements of it (life_globals_gs).
    // dest_place, dest_reached: the destination an assignment or a builtin is
    // building its value in, and life_reached of it: what a literal's fields
    // or a call's result stored there reach (life_dest_reached).
    dest_place: i64 = 0, dest_reached: i64 = -1,
    globals_root: i64 = -1, globals_gs_key: i64 = -1, globals_gs_epoch: i64 = -1, globals_gs_answer: bool = false,
    class_list: i64[>..]&, class_heads: i64[>..]&, class_keys: i64[>..]&,
    map_sets: i64[>..]&, map_roots: i64[>..]&, map_depths: i64[>..]&,
    // map_types: beside map_roots, the pointee type the call's reference to that one root has, or -1.
    map_types: i64[>..]&, key_scratch: i64[>..]&, class_scratch: i64[>..]&, bound_scratch: i64[>..]&,
    assumes: LifeAssume[>..]&,
    // The assumes entries by frame and question, open addressing.
    assume_slots: LifeAssumeSlot[>..]&,
    // Recent life_map_set results, 2-way set-associative; held_epoch tracks mutations
    // to root contents, live_contents, class_stored, stored_version, and discovery.
    map_memo: LifeMapped[>..]&, map_memo_writes: i64 = 0, held_epoch: i64 = 0, type_work: i32[>..]&,
    call_sigs: LifeCallSig[>..]&, call_sig_heads: i32[>..]&, call_sig_data: i32[>..]&,
    // The owners of the captured bindings each body names (LifeBody.owners),
    // and per function node whether it is contained (life_contained): 0
    // unknown, 1 yes, 2 no.
    body_owners: i64[>..]&, body_captures: i64[>..]&, contained: i64[>..]&,
    // The storage classes of one pointee type, by parent and pointee (open
    // addressing over root indexes), and how many there are.
    typed_slots: LifeTypedSlot[>..]&, typed_count: i64 = 0,
    // Per type, the first type life_same takes it for (life_canon_types).
    type_canon: i64[>..]&,
    // Per such type, whether some global's own storage holds one inline
    // (life_global_types): 1 yes, 0 no.
    global_types: i8[>..]&,
    // Whether storage of one type holds a reference to a value of another
    // (life_refers), by the pair; and the sets life_referable has made, by
    // set and holding type.
    refers: LifeRefers[>..]&, referable: LifeLoaded[>..]&,
    free_item: i64 = -1,
    // During a quiet discovery round, a caller subscribes to a frame's
    // stores by replaying its summary. Earlier expansions need no wakeup.
    watch_stores: bool = false, store_changes: i64 = 0, store_wakes: LifeStoreWake[>..]&,
    global_capture_head: i64 = -1,
    full_reads: bool = false, need_full_reads: bool = false,
    live_contents_stamp: i64 = 0, root_live_stamps: i64[>..]&,
    chk_dep_roots: i32[>..]&, chk_dep_stack: i32[>..]&, chk_dep_recording: bool = false,
    chk_saw_unsealed: bool = false, in_class_check: bool = false, chk_dep_overflow: bool = false, chk_island: i64 = -1,
    held_own_memo: LifeHeldOwn[>..]&, held_own_recorded: i64 = 0,
    type_exact_canon: i32[>..]&,
    node_body: i32[>..]&, span_slots: LifeSpanSlot[>..]&, span_count: i64 = 0, body_work: i64[>..]&, body_reached: i64[>..]&,
    local_holder_bits: u64[>..]&, local_holder_words: u64[>..]&,
    contains_seen: i32[>..]&, contains_seen_gen: i32 = 0,
    outer_type_seen: i32[>..]&, outer_type_seen_gen: i32 = 0,
    closure_start: i32[>..]&, closure_count: i32[>..]&, closure_data: i32[>..]&,
    holder_ref_start: i32[>..]&, holder_ref_count: i32[>..]&, holder_ref_flags: u8[>..]&, holder_ref_elems: i32[>..]&,
    gs_start: i32[>..]&, gs_count: i32[>..]&, gs_elems: i32[>..]&,
    body_trans_globals: i64[>..]&,
    summary_l1: LifeSummarySlot[>..]&, assume_l1: LifeAssumeSlot[>..]&,
    val_kill_epoch: i64 = 0,
    defers: LifeDefer[>..]&, defer_targets: LifeDeferTarget[>..]&, defer_run: LifeDefer[>..]&, defer_floor: i64 = 0,
    bypass_memo: u8[>..]&,
}

fn life_same_effect(l: Lifetimes&, old: const LifeEffect&, effect: const LifeEffect&) -> bool {
    return old.kind == effect.kind && old.value.type_id == effect.value.type_id &&
       old.value.element_array == effect.value.element_array && old.field == effect.field && old.cell == effect.cell &&
       life_equal(l, old.places, effect.places) && life_equal(l, old.value.refs, effect.value.refs) && life_equal(l, old.value.contents, effect.value.contents);
}
// A place is local to the frames from its root's frame up the current
// chain: the chain position past which some place of the effect is not.
// The frames above the current one are the active ones with a smaller chain
// count, so a root's frame is on the chain, and how far up, without a walk.
// home: the frame at that position. cyclic: a place is in a recursive
// frame of the chain; with a place outside the chain every frame takes the
// effect as external, and none is asked about its cells.
struct LifeFar { far: i64, home: i64, cyclic: bool = false }
fn life_effect_far(l: Lifetimes&, places: i64) -> LifeFar {
    let pset: const LifeSet& = l.sets[places];
    var at = pset.first;
    if at < 0 { return LifeFar { far: 0, home: l.frame }; }
    if pset.count == 1 {
        let root = l.alts[at].root;
        if root == 0 { return LifeFar { far: 0, home: l.frame }; }
        let home = l.roots[root].frame;
        if l.frame <= 0 || home <= 0 { return LifeFar { far: 9223372036854775807, home: 0 }; }
        let h: const LifeFrame& = l.frames[home];
        if home == l.frame { return LifeFar { far: 0, home: l.frame, cyclic: h.recursive_call }; }
        let chain = l.frames[l.frame].chain;
        if !h.active || h.chain >= chain { return LifeFar { far: 9223372036854775807, home: 0 }; }
        return LifeFar { far: chain - h.chain, home: home, cyclic: h.recursive_call };
    }
    if l.frame <= 0 {
        while at >= 0 {
            if l.alts[at].root != 0 { return LifeFar { far: 9223372036854775807, home: 0 }; }
            at = l.alts[at].next;
        }
        return LifeFar { far: 0, home: l.frame };
    }
    let act = l.frames[l.frame].activation as i32;
    let ep = l.recursion_epoch as i32;
    let p32 = places as i32;
    var fslot: i64 = -1;
    if l.far_cache.len == 0 { l.far_cache.resize(1024, LifeFarMemo {}); }
    fslot = ((((places as! u64) * 2654435761 ^ ((act as i64) as! u64) * 2246822519) >> 8) & 1023) as i64;
    let fm: const LifeFarMemo& = l.far_cache[fslot];
    if fm.places == p32 && fm.activation == act && fm.epoch == ep {
        return LifeFar { far: fm.far, home: fm.home as i64, cyclic: fm.cyclic };
    }
    let cur = l.frame;
    let chain = l.frames[cur].chain;
    var min_chain = chain; var best_home = cur; var cyclic = false;
    while at >= 0 {
        let root = l.alts[at].root;
        if root != 0 {
            let home = l.roots[root].frame;
            if home <= 0 {
                l.far_cache[fslot] = LifeFarMemo { places: p32, activation: act, epoch: ep, home: 0, far: 9223372036854775807, cyclic: false };
                return LifeFar { far: 9223372036854775807, home: 0 };
            }
            let h: const LifeFrame& = l.frames[home];
            if home != cur {
                if !h.active || h.chain >= chain {
                    l.far_cache[fslot] = LifeFarMemo { places: p32, activation: act, epoch: ep, home: 0, far: 9223372036854775807, cyclic: false };
                    return LifeFar { far: 9223372036854775807, home: 0 };
                }
                if h.chain < min_chain { min_chain = h.chain; best_home = home; }
            }
            if h.recursive_call { cyclic = true; }
        }
        at = l.alts[at].next;
    }
    let far = chain - min_chain;
    l.far_cache[fslot] = LifeFarMemo { places: p32, activation: act, epoch: ep, home: best_home as i32, far: far, cyclic: cyclic };
    return LifeFar { far: far, home: best_home, cyclic: cyclic };
}
// A recursive activation's own root reached through one of its parameters
// belongs to another activation.
fn life_effect_recursive(l: Lifetimes&, places: i64, frame: i64) -> bool {
    var at = l.sets[places].first;
    while at >= 0 {
        let root = l.alts[at].root;
        if root != 0 && l.roots[root].frame == frame {
            var ci = l.frames[frame].first_parameter;
            while ci >= 0 {
                let cell: const LifeCell& = l.cells[ci];
                if life_find(l, cell.refs, root) >= 0 { return true; }
                ci = cell.next_parameter;
            }
        }
        at = l.alts[at].next;
    }
    return false;
}
inline fn life_hash_step(h: u64, part: i64) -> u64 {
    let x = (h ^ (part as! u64)) * 1099511628211;
    return x ^ (x >> 29);
}
inline fn life_tf_is_ref(p: Program&, l: Lifetimes&, ty: i64) -> bool {
    if ty < 0 { return false; }
    if l.nodes_prepared && ty < l.type_flags.len { return (l.type_flags[ty] & TF_L_REF) != 0; }
    return life_is_ref(p, ty);
}
inline fn life_tf_holds(p: Program&, l: Lifetimes&, ty: i64) -> bool {
    if ty < 0 { return false; }
    if l.nodes_prepared && ty < l.type_flags.len { return (l.type_flags[ty] & TF_L_HOLDS) != 0; }
    return life_holds(p, ty);
}
inline fn life_tf_rel(p: Program&, l: Lifetimes&, ty: i64) -> bool {
    if ty < 0 { return false; }
    if l.nodes_prepared && ty < l.type_flags.len { return (l.type_flags[ty] & TF_L_REL) != 0; }
    return life_relative_storage(p, ty);
}
inline fn life_mix(a: i64, b: i64) -> i64 {
    var h: u64 = 1469598103934665603;
    h = life_hash_step(h, a);
    h = life_hash_step(h, b);
    return (h >> 1) as i64;
}
inline fn life_leaf_hash(kind: i64, node: i64, v: const LifeValue&) -> i64 {
    let p1 = (((kind as! u32) as u64) << 32) | ((node as! u32) as u64);
    let p2 = (((v.type_id as! u32) as u64) << 32) | ((v.place as! u32) as u64);
    let p3 = (((v.refs as! u32) as u64) << 32) | ((v.contents as! u32) as u64);
    let p4 = (((v.self_pools as! u32) as u64) << 32) | ((v.relative_roots as! u32) as u64);
    let p5 = (((v.tuple as! u32) as u64) << 32) | ((v.element_array as! u32) as u64);
    let p6 = (((v.reached as! u32) as u64) << 1) | (if v.readonly { 1 as u64 } else { 0 as u64 });
    var h: u64 = p1 * 11400714819323198485 ^ p2 * 14029467366897019727 ^ p3 * 1609587929392839161 ^
        p4 * 9650029242287828579 ^ p5 * 2870177450012600261 ^ p6 * 12682985525061530331;
    h ^= h >> 29;
    return (h >> 1) as! i64;
}
// Replaying these effects during concrete discovery only records the
// operation in caller summaries. A shrink entry already names an array.
inline fn life_replayable_leaf(l: Lifetimes&, kind: i64) -> bool {
    return kind == 3 || l.compact && (kind == 1 || kind == 2 || kind == 8);
}
// The leaf of a check-only effect: equal kinds, nodes and values, set for set by ID.
fn life_leaf(l: Lifetimes&, kind: i64, node: i64, v: const LifeValue&) -> i64 {
    if 2 * (l.leaves.len + 1) > l.leaf_slots.len {
        var size: i64 = 128; while size <= 2 * (l.leaves.len + 1) { size <<= 1; }
        var old: LifeLeafSlot[>..] = []; old.append(l.leaf_slots);
        l.leaf_slots.clear(); l.leaf_slots.resize(size, LifeLeafSlot {});
        let nmask = size - 1;
        for e in old {
            if e.leaf < 0 { continue; }
            var s = e.key & nmask;
            while l.leaf_slots[s].leaf >= 0 { s = (s + 1) & nmask; }
            l.leaf_slots[s] = e;
        }
    }
    let key = life_leaf_hash(kind, node, v);
    let mask = l.leaf_slots.len - 1; var slot = key & mask; let node32 = node as i32; let kind32 = kind as i32;
    loop {
        let e = l.leaf_slots[slot];
        if e.leaf < 0 { break; }
        if e.key == key && e.node == node32 {
            let leaf: const LifeLeaf& = l.leaves[e.leaf as i64];
            if leaf.kind == kind32 && leaf.value.type_id == v.type_id && leaf.value.place == v.place && leaf.value.refs == v.refs && leaf.value.contents == v.contents &&
               leaf.value.self_pools == v.self_pools && leaf.value.relative_roots == v.relative_roots && leaf.value.tuple == v.tuple &&
               leaf.value.element_array == v.element_array && leaf.value.reached == v.reached && leaf.value.readonly == v.readonly { return e.leaf as i64; }
        }
        slot = (slot + 1) & mask;
    }
    let index = l.leaves.len;
    l.leaves.push(LifeLeaf { kind: kind32, node: node32, value: v });
    l.leaf_slots[slot] = LifeLeafSlot { key: key, leaf: index as i32, node: node32 };
    l.leaf_stamps.push(-1); l.leaf_floors.push(0);
    return index;
}
// A leaf's stamp records its activation and recursion epoch. A descendant
// can cover an ancestor when the ancestor received the offer and its roots
// still have the same reach after the descendant returns (life_leaf_stamp).
// Class-keyed frames only reuse an offer within the same activation.
// The number of the chain of frames a frame is entered in: the same for the
// same frames in the same order, in whichever pass.
fn life_context(l: Lifetimes&, frame: i64, parent: i64) -> i64 {
    if l.class_frames > 0 || parent < 0 { return -1; }
    if 2 * l.contexts.len >= l.context_heads.len {
        var size: i64 = 64; while size <= 2 * l.contexts.len { size <<= 1; }
        l.context_heads.clear(); l.context_heads.resize(size, -1);
        for index in 0..l.contexts.len {
            let slot = life_mix(l.contexts[index].frame, l.contexts[index].parent) & (size - 1);
            l.contexts[index].next = l.context_heads[slot] as i64; l.context_heads[slot] = index as i32;
        }
    }
    let slot = life_mix(frame, parent) & (l.context_heads.len - 1);
    var at = l.context_heads[slot] as i64;
    while at >= 0 { if l.contexts[at].frame == frame && l.contexts[at].parent == parent { return at; } at = l.contexts[at].next; }
    let index = l.contexts.len; l.contexts.push(LifeContext { frame: frame, parent: parent, next: l.context_heads[slot] as i64 }); l.context_heads[slot] = index as i32;
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
// The summary version this chain last replayed completely, or -1.
fn life_chain_replayed(l: Lifetimes&, key: i64) -> i64 {
    if l.chain_replays.len == 0 { return -1; }
    let mask = l.chain_replays.len - 1;
    var slot = life_mix(key, 1) & mask;
    loop {
        let entry: const LifeChainReplay& = l.chain_replays[slot];
        if entry.key == key { return entry.version as i64; }
        if entry.key < 0 { return -1; }
        slot = (slot + 1) & mask;
    }
    return -1;
}
fn life_chain_replay(l: Lifetimes&, key: i64, version: i64) {
    if 2 * (l.chain_replay_count + 1) > l.chain_replays.len {
        var size: i64 = 256; while size < 4 * (l.chain_replay_count + 1) { size <<= 1; }
        var old: LifeChainReplay[>..] = []; old.append(l.chain_replays);
        l.chain_replays.clear(); l.chain_replays.resize(size, LifeChainReplay {});
        for entry in old {
            if entry.key < 0 { continue; }
            var slot = life_mix(entry.key, 1) & (size - 1);
            while l.chain_replays[slot].key >= 0 { slot = (slot + 1) & (size - 1); }
            l.chain_replays[slot] = entry;
        }
    }
    let mask = l.chain_replays.len - 1;
    var slot = life_mix(key, 1) & mask;
    while l.chain_replays[slot].key >= 0 && l.chain_replays[slot].key != key { slot = (slot + 1) & mask; }
    if l.chain_replays[slot].key < 0 { l.chain_replay_count += 1; }
    l.chain_replays[slot] = LifeChainReplay { key: key, version: version as i32 };
}
inline fn life_leaf_offered_in(l: Lifetimes&, leaf: i64, activation: i64, epoch: i64, chain: i64) -> bool {
    let held = l.leaf_stamps[leaf];
    if (held & 4294967295) != epoch { return false; }
    let from = held >> 32;
    return from == activation || from > activation && chain >= l.leaf_floors[leaf] as i64;
}
inline fn life_leaf_offered(l: Lifetimes&, leaf: i64) -> bool {
    let f: const LifeFrame& = l.frames[l.frame];
    var chain: i64 = -1; if l.class_frames == 0 { chain = f.chain; }
    return life_leaf_offered_in(l, leaf, f.activation, l.recursion_epoch, chain);
}
// Record how far this activation offered the leaf up its caller chain.
fn life_leaf_stamp(l: Lifetimes&, leaf: i64, far: i64, places: i64) {
    let f: const LifeFrame& = l.frames[l.frame];
    var floor: i64 = 1; if far != 9223372036854775807 { floor = f.chain - far + 1; }
    // After returning to an ancestor, one of several local owners may have
    // left the call stack. An offer can then reach beyond its original floor.
    if far != 9223372036854775807 && far > 0 && l.sets[places].count > 1 { floor = f.chain + 1; }
    if floor > 2147483647 { return; }
    l.leaf_stamps[leaf] = f.activation * 4294967296 + l.recursion_epoch; l.leaf_floors[leaf] = floor as i32;
}
fn life_summary_seen(l: Lifetimes&, index: i64, effect: const LifeEffect&) {
    l.summaries[index].places = effect.places as i32; l.summaries[index].refs = effect.value.refs as i32;
    l.summaries[index].contents = effect.value.contents as i32; l.summaries[index].place = effect.value.place as i32;
}
// LifeSummary.walked for an offer going up from a frame now, or -1 where the
// activation count no longer fits its 32 bits and nothing is recorded.
inline fn life_walked(l: Lifetimes&, frame: i64, outside: bool) -> i32 {
    if l.activations >= 1073741824 { return -1; }
    var walked = (2 * l.frames[frame].activation) as i32; if outside { walked += 1; }
    return walked;
}
inline fn life_summary_base_hash(effect: const LifeEffect&, site: i64) -> u64 {
    var h: u64 = ((site + 1) as! u64) * 14029467366897019727 ^
        ((effect.kind as i64) as! u64) * 1609587929392839161 ^ (((effect.cell as i64) + 1) as! u64) * 9650029242287828579 ^
        (((effect.value.type_id as i64) + 1) as! u64) * 12682985525061530331 ^ (((effect.field as i64) + 2) as! u64) * 6364136223846793005;
    if site < -1 { h ^= 0x9e3779b97f4a7c15; }
    if effect.kind == 4 { h ^= ((effect.places as i64) as! u64) * 2870177450012600261; }
    return h;
}
inline fn life_summary_key(frame: i64, base_h: u64) -> i64 {
    var h: u64 = (frame as! u64) * 11400714819323198485 ^ base_h;
    h ^= h >> 29;
    return (h >> 1) as! i64;
}
fn life_summary_reserve(l: Lifetimes&) {
    if l.summary_slots.len > 2 * (l.summary_slot_count + 1) { return; }
    var size: i64 = 2048; while size <= 2 * (l.summary_slot_count + 1) { size <<= 1; }
    var old: LifeSummarySlot[>..] = []; old.append(l.summary_slots);
    l.summary_slots.clear(); l.summary_slots.resize(size, LifeSummarySlot {});
    let mask = size - 1;
    for entry in old {
        if entry.index < 0 { continue; }
        var slot = entry.key & mask;
        while l.summary_slots[slot].index >= 0 { slot = (slot + 1) & mask; }
        l.summary_slots[slot] = entry;
    }
}
inline fn life_summary_insert(l: Lifetimes&, key: i64, index: i64, frame: i64) {
    let mask = l.summary_slots.len - 1; var slot = key & mask;
    while l.summary_slots[slot].index >= 0 { slot = (slot + 1) & mask; }
    let ent = LifeSummarySlot { key: key, index: index as i32, frame: frame as i32 };
    l.summary_slots[slot] = ent;
    l.summary_l1[key & 2047] = ent;
    l.summary_slot_count += 1;
}
// Discovery merges a frame's summary effects by site: 0 if none took it, 1 if
// one did, 2 if one did that already sent these sets up the chain in this
// activation (LifeSummary.walked). outside: a place of the effect is outside
// every frame of the chain. On 0, writes the empty slot index into out_slot.
fn life_effect_merge(l: Lifetimes&, effect: const LifeEffect&, frame: i64, key: i64, outside: bool, site: i64, out_slot: i64&) -> i64 {
    let walked = life_walked(l, frame, outside);
    let frame32 = frame as i32; let site32 = site as i32;
    let l1_slot = key & 2047;
    let l1 = l.summary_l1[l1_slot];
    if l1.index >= 0 && l1.key == key && l1.frame == frame32 {
        let previous = l1.index as i64;
        let summary: const LifeSummary& = l.summaries[previous];
        if summary.node == site32 && summary.kind == effect.kind && summary.cell == effect.cell && summary.type_id == effect.value.type_id && summary.field == effect.field {
            if summary.places == effect.places && summary.refs == effect.value.refs && summary.contents == effect.value.contents && summary.place == effect.value.place {
                if walked >= 0 && (summary.walked == (walked | 1) || summary.walked == walked) { return 2; }
                l.summaries[previous].walked = walked;
                return 1;
            }
            let old: const LifeEffect& = l.effects[previous];
            if effect.kind != 4 || life_equal(l, old.places, effect.places) {
                let old_places = old.places; let old_refs = old.value.refs; let old_contents = old.value.contents; let old_place = old.value.place;
                let places = life_join(l, old_places, effect.places);
                let refs = life_join(l, old_refs, effect.value.refs); let contents = life_join(l, old_contents, effect.value.contents);
                let value_places = life_join(l, old_place, effect.value.place);
                if !life_equal(l, places, old_places) || !life_equal(l, refs, old_refs) || !life_equal(l, contents, old_contents) || !life_equal(l, value_places, old_place) {
                    l.revision += 1; l.frames[frame].summary_version += 1;
                    if l.watch_stores && effect.kind == 4 && effect.field == -1 && places == old_places && refs == old_refs && value_places == old_place {
                        if l.frames[frame].store_read_pass != l.pass { l.store_changes += 1; }
                        else if l.frames[frame].store_reader >= 0 {
                            l.store_changes += 1;
                            l.store_wakes.push(LifeStoreWake { summary: previous, context: l.frames[frame].store_reader });
                        }
                    }
                }
                l.effects[previous].places = places as i32; l.effects[previous].value.refs = refs as i32; l.effects[previous].value.contents = contents as i32; l.effects[previous].value.place = value_places as i32;
                life_summary_seen(l, previous, effect);
                l.summaries[previous].walked = walked; l.summaries[previous].replayed = -1; l.summaries[previous].leaf = -1;
                if life_replayable_leaf(l, effect.kind) { l.frames[frame].replay_version += 1; }
                return 1;
            }
        }
    }
    let mask = l.summary_slots.len - 1; var slot = key & mask;
    loop {
        let entry = l.summary_slots[slot];
        if entry.index < 0 { out_slot = slot; return 0; }
        if entry.key == key && entry.frame == frame32 {
            let previous = entry.index as i64;
            let summary: const LifeSummary& = l.summaries[previous];
            if summary.node == site32 && summary.kind == effect.kind && summary.cell == effect.cell && summary.type_id == effect.value.type_id && summary.field == effect.field {
                if summary.places == effect.places && summary.refs == effect.value.refs && summary.contents == effect.value.contents && summary.place == effect.value.place {
                    l.summary_l1[l1_slot] = entry;
                    if walked >= 0 && (summary.walked == (walked | 1) || summary.walked == walked) { return 2; }
                    l.summaries[previous].walked = walked;
                    return 1;
                }
                let old: const LifeEffect& = l.effects[previous];
                if effect.kind != 4 || life_equal(l, old.places, effect.places) {
                    l.summary_l1[l1_slot] = entry;
                    let old_places = old.places; let old_refs = old.value.refs; let old_contents = old.value.contents; let old_place = old.value.place;
                    let places = life_join(l, old_places, effect.places);
                    let refs = life_join(l, old_refs, effect.value.refs); let contents = life_join(l, old_contents, effect.value.contents);
                    let value_places = life_join(l, old_place, effect.value.place);
                    if !life_equal(l, places, old_places) || !life_equal(l, refs, old_refs) || !life_equal(l, contents, old_contents) || !life_equal(l, value_places, old_place) {
                        l.revision += 1; l.frames[frame].summary_version += 1;
                        if l.watch_stores && effect.kind == 4 && effect.field == -1 && places == old_places && refs == old_refs && value_places == old_place {
                            if l.frames[frame].store_read_pass != l.pass { l.store_changes += 1; }
                            else if l.frames[frame].store_reader >= 0 {
                                l.store_changes += 1;
                                l.store_wakes.push(LifeStoreWake { summary: previous, context: l.frames[frame].store_reader });
                            }
                        }
                    }
                    l.effects[previous].places = places as i32; l.effects[previous].value.refs = refs as i32; l.effects[previous].value.contents = contents as i32; l.effects[previous].value.place = value_places as i32;
                    life_summary_seen(l, previous, effect);
                    l.summaries[previous].walked = walked; l.summaries[previous].replayed = -1; l.summaries[previous].leaf = -1;
                    if life_replayable_leaf(l, effect.kind) { l.frames[frame].replay_version += 1; }
                    return 1;
                }
            }
        }
        slot = (slot + 1) & mask;
    }
    return 0;
}
// Validation-pass effects are indexed by
// a hash of everything life_same_effect compares, and their frame.
inline fn life_index_bucket(l: Lifetimes&, key: i64) -> i64 { return key & (l.effect_heads.len - 1); }
// Half an indexed effect per bucket at most, on average. Only frames on the
// current active call stack can still record/deduplicate validation effects,
// so sweeping expired frames keeps effect_heads small and cache-resident.
fn life_index_reserve(l: Lifetimes&) {
    if l.effect_heads.len > 2 * l.indexed_effects { return; }
    var live: i64 = 0;
    var f = l.frame;
    while f > 0 {
        if !l.frames[f].validated {
            let ep = l.frames[f].effect_epoch;
            var e = l.frames[f].first_effect;
            while e >= 0 {
                let ef: const LifeEffect& = l.effects[e];
                if ef.kind != 0 && ef.index_key >= 0 && ef.owner == f && ef.epoch == ep { live += 1; }
                e = ef.next as i64;
            }
        }
        let pf = l.frames[f].parent;
        if pf <= 0 || l.frames[pf].chain >= l.frames[f].chain { break; }
        f = pf;
    }
    var size: i64 = 2048; while size <= 4 * live { size <<= 1; }
    l.effect_heads.clear(); l.effect_heads.resize(size, -1);
    let mask = size - 1;
    f = l.frame;
    while f > 0 {
        if !l.frames[f].validated {
            let ep = l.frames[f].effect_epoch;
            var e = l.frames[f].first_effect;
            while e >= 0 {
                let ef: const LifeEffect& = l.effects[e];
                let nxt = ef.next as i64;
                if ef.kind != 0 && ef.index_key >= 0 && ef.owner == f && ef.epoch == ep {
                    let bucket = ef.index_key & mask;
                    l.effects[e].index_next = l.effect_heads[bucket];
                    l.effect_heads[bucket] = e as i32;
                }
                e = nxt;
            }
        }
        let pf = l.frames[f].parent;
        if pf <= 0 || l.frames[pf].chain >= l.frames[f].chain { break; }
        f = pf;
    }
    l.indexed_effects = live;
}
// Find the newest equal effect recorded in this validation of the frame. A
// store, shrink or kill can repeat only if no intervening operation orders
// against it. Only unordered effects can certify delivery to an ancestor.
fn life_barrier_overlaps(p: Program&, l: Lifetimes&, store_eff: const LifeEffect&, kill_eff: const LifeEffect&) -> bool {
    if l.sets[kill_eff.places].count == 1 {
        let ka = l.alts[l.sets[kill_eff.places].first];
        let kr = ka.root as i64;
        if ka.exact && !ka.byteview && kr != 0 && kr != l.globals_root && l.roots[kr].class_frame < 0 {
            if l.sets[store_eff.places].count == 1 && l.alts[l.sets[store_eff.places].first].root as i64 == l.globals_root {
                return false;
            }
            let sty = store_eff.value.type_id as i64;
            let kty = l.roots[kr].type_id;
            if sty >= 0 && kty >= 0 && !life_contains_memo(p, l, kty, sty) {
                return false;
            }
        }
    }
    return life_overlaps(p, l, store_eff.places, kill_eff.places);
}
fn life_effect_indexed(p: Program&, l: Lifetimes&, effect: const LifeEffect&, frame: i64, bucket: i64, outside: bool) -> i64 {
    let merge_unordered = l.class_frames > 0 && (effect.kind == 2 || effect.kind == 3);
    let ep = l.frames[frame].effect_epoch;
    if effect.kind == 4 {
        let can_merge = effect.field >= -1;
        var kill_floor: i64 = -1;
        var newest_match: i64 = -1;
        var scan = l.effect_heads[bucket] as i64;
        var checked = 0;
        var kt = l.frames[frame].last_kill;
        while scan >= 0 && checked < 64 {
            let old: const LifeEffect& = l.effects[scan];
            if old.kind != 0 && old.owner == frame && old.epoch == ep &&
               old.kind == 4 && old.field == effect.field && old.value.type_id == effect.value.type_id && old.cell == effect.cell &&
               life_equal(l, old.places, effect.places) && life_equal(l, old.value.refs, effect.value.refs) {
                while kt > scan {
                    let barrier: const LifeEffect& = l.effects[kt];
                    if barrier.kind != 0 && life_barrier_overlaps(p, l, effect, barrier) { kill_floor = kt; break; }
                    kt = barrier.previous_barrier;
                }
                if kill_floor > scan { break; }
                if newest_match < 0 { newest_match = scan; }
                if !can_merge || life_subset(l, effect.value.contents, old.value.contents) { return 1; }
                checked += 1;
            }
            scan = old.index_next;
        }
        if can_merge && newest_match >= 0 && newest_match > l.frames[frame].last_shrink {
            let joined = life_join(l, l.effects[newest_match].value.contents, effect.value.contents);
            l.effects[newest_match].value.contents = joined as i32;
            return 1;
        }
        return 0;
    }
    var found = l.effect_heads[bucket] as i64;
    while found >= 0 {
        let old: const LifeEffect& = l.effects[found];
        if old.kind != 0 && old.owner == frame && old.epoch == ep {
            if merge_unordered {
                if old.kind == effect.kind && old.value.type_id == effect.value.type_id && old.value.element_array == effect.value.element_array && old.field == effect.field && old.cell == effect.cell { break; }
            } else if life_same_effect(l, old, effect) { break; }
        }
        found = old.index_next;
    }
    if effect.kind == 1 {
        if found > l.frames[frame].last_shrink_barrier { return 1; }
        if found >= 0 && found > l.frames[frame].last_kill { l.effects[found].kind = 0; }
        return 0;
    }
    if effect.kind == 6 || effect.kind == 7 {
        if found < 0 { return 0; }
        var at = l.frames[frame].last_store;
        while at > found {
            let barrier: const LifeEffect& = l.effects[at];
            if barrier.kind != 0 && life_barrier_overlaps(p, l, barrier, effect) { return 0; }
            at = barrier.previous_barrier;
        }
        return 1;
    }
    if found < 0 { return 0; }
    if merge_unordered {
        let places = life_join(l, l.effects[found].places, effect.places);
        let refs = life_join(l, l.effects[found].value.refs, effect.value.refs);
        let place = life_join(l, l.effects[found].value.place, effect.value.place);
        if !life_equal(l, places, l.effects[found].places) || !life_equal(l, refs, l.effects[found].value.refs) || !life_equal(l, place, l.effects[found].value.place) {
            l.effects[found].places = places as i32;
            l.effects[found].value.refs = refs as i32;
            l.effects[found].value.place = place as i32;
            l.effects[found].walked = 1; if outside { l.effects[found].walked = 2; }
            return 1;
        }
    }
    let walked = l.effects[found].walked;
    if walked == 2 || walked == 1 && !outside { return 2; }
    l.effects[found].walked = 1; if outside { l.effects[found].walked = 2; }
    return 1;
}
// The nearest recursive frame of the chain from this frame up, or 0. The
// chain above a frame is fixed from its activation, which clears
// chain_epoch, and a frame becomes recursive only as recursion_epoch moves
// on, so an answer holds for its epoch, and for the frames passed on the way.
fn life_nearest_recursive_slow(l: Lifetimes&, frame: i64) -> i64 {
    var at = frame; var answer = 0;
    while at > 0 {
        let f: const LifeFrame& = l.frames[at];
        if f.recursive_call { answer = at; break; }
        if f.chain_epoch == l.recursion_epoch { answer = f.chain_recursive; break; }
        at = f.parent;
    }
    var fill = frame;
    while fill > 0 && fill != at {
        l.frames[fill].chain_epoch = l.recursion_epoch; l.frames[fill].chain_recursive = answer; fill = l.frames[fill].parent;
    }
    return answer;
}
inline fn life_nearest_recursive(l: Lifetimes&, frame: i64) -> i64 {
    if frame <= 0 { return 0; }
    let f: const LifeFrame& = l.frames[frame];
    if f.recursive_call { return frame; }
    if f.chain_epoch == l.recursion_epoch { return f.chain_recursive; }
    return life_nearest_recursive_slow(l, frame);
}
inline fn life_offer_slot(l: Lifetimes&, effect: const LifeEffect&, site: i64) -> i64 {
    let p1 = (((l.frame as! u32) as u64) << 32) | ((effect.kind as! u32) as u64);
    let p2 = (((site as! u32) as u64) << 32) | ((effect.value.type_id as! u32) as u64);
    let p3 = (((effect.cell as! u32) as u64) << 32) | ((effect.field as! u32) as u64);
    let p4 = (((effect.places as! u32) as u64) << 32) | ((effect.value.refs as! u32) as u64);
    let p5 = (((effect.value.contents as! u32) as u64) << 32) | ((effect.value.place as! u32) as u64);
    var h: u64 = p1 * 11400714819323198485 ^ p2 * 14029467366897019727 ^ p3 * 1609587929392839161 ^
        p4 * 9650029242287828579 ^ p5 * 2870177450012600261;
    h ^= h >> 29;
    return (h & ((l.offers.len - 1) as! u64)) as i64;
}
// Whether this discovery offer was already made in the current frame's
// activation; records it otherwise. Recursive frames are left out, as an
// offer to one depends on its cells.
fn life_offer_repeated(l: Lifetimes&, effect: const LifeEffect&, site: i64) -> bool {
    if l.activations >= 1073741824 || life_nearest_recursive(l, l.frame) > 0 { return false; }
    let slot = life_offer_slot(l, effect, site); let activation = l.frames[l.frame].activation as i32;
    let frame32 = l.frame as i32; let epoch32 = l.recursion_epoch as i32; let site32 = site as i32;
    let o: const LifeOffer& = l.offers[slot];
    if o.frame == frame32 && o.activation == activation && o.epoch == epoch32 && o.kind == effect.kind && o.node == site32 &&
       o.type_id == effect.value.type_id && o.cell == effect.cell && o.field == effect.field && o.places == effect.places &&
       o.refs == effect.value.refs && o.contents == effect.value.contents && o.place == effect.value.place { return true; }
    l.offers[slot] = LifeOffer { frame: frame32, activation: activation, epoch: epoch32, kind: effect.kind, node: site32, type_id: effect.value.type_id,
        cell: effect.cell, field: effect.field, places: effect.places, refs: effect.value.refs, contents: effect.value.contents, place: effect.value.place };
    l.offers_recorded++;
    if l.offers_recorded > 4 * l.offers.len && l.offers.len < 131072 { l.offers.resize(4 * l.offers.len, LifeOffer {}); l.offers_recorded = 0; }
    return false;
}
inline fn life_read_key(node: i64, type_id: i64) -> i64 { return node * 4294967296 + type_id + 1; }
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
fn life_read_merge(l: Lifetimes&, frame: i64, leaf: i64, key: i64, index: i64, outside: bool) -> i64 {
    let walked = life_walked(l, frame, outside);
    if index < 0 {
        l.frames[frame].replay_version += 1;
        life_read_add(l, frame, LifeReadEntry { changed: l.frames[frame].replay_version, key: key, leaf: leaf as i32, seen: leaf as i32, walked: walked, before: l.frames[frame].last_summary as i32 });
        l.revision += 1;
        return 0;
    }
    let seen = l.summary_reads[index].seen as i64; var same = seen == leaf;
    if !same {
        let a: const LifeValue& = l.leaves[seen].value; let b: const LifeValue& = l.leaves[leaf].value;
        same = a.place == b.place && a.refs == b.refs && a.contents == b.contents ||
            life_same_list(l, a.place, b.place) && life_same_list(l, a.refs, b.refs) && life_same_list(l, a.contents, b.contents);
        if same { l.summary_reads[index].seen = leaf as i32; l.summary_reads[index].sent = -1; }
    }
    if same {
        if walked >= 0 && (l.summary_reads[index].walked == (walked | 1) || l.summary_reads[index].walked == walked) { return 2; }
        l.summary_reads[index].walked = walked;
        return 1;
    }
    let held = l.summary_reads[index].leaf as i64; var value = l.leaves[held].value; let offered: const LifeValue& = l.leaves[leaf].value;
    let refs = life_join(l, value.refs, offered.refs); let contents = life_join(l, value.contents, offered.contents);
    let place = life_join(l, value.place, offered.place);
    if !life_equal(l, refs, value.refs) || !life_equal(l, contents, value.contents) || !life_equal(l, place, value.place) { l.revision += 1; }
    value.refs = refs as i32; value.contents = contents as i32; value.place = place as i32;
    let joined = life_leaf(l, 3, l.leaves[held].node, value);
    l.summary_reads[index].leaf = joined as i32; l.summary_reads[index].seen = leaf as i32; l.summary_reads[index].walked = walked; l.summary_reads[index].sent = -1;
    if joined != held {
        l.frames[frame].replay_version += 1; l.summary_reads[index].changed = l.frames[frame].replay_version;
    }
    return 1;
}
// life_effect for a construct read in discovery while summaries hold their
// reads by leaf: the same walk up the chain, each frame that takes the
// effect as external taking it in its reads.
fn life_read_offer(l: Lifetimes&, leaf: i64, places: i64, key: i64) -> i64 {
    l.offer_count += 1;
    if places == 0 { return 0; }
    let pset: const LifeSet& = l.sets[places];
    if pset.count == 1 {
        let root = l.alts[pset.first].root;
        if root == 0 { return 0; }
        let cur = l.frame;
        if cur > 0 {
            let home = l.roots[root].frame;
            if home == cur && !l.frames[cur].recursive_call { return 0; }
            var reach = LifeFar { far: 9223372036854775807, home: 0 };
            if home > 0 {
                let h: const LifeFrame& = l.frames[home];
                if home == cur {
                    reach = LifeFar { far: 0, home: cur, cyclic: h.recursive_call };
                } else {
                    let chain = l.frames[cur].chain;
                    if h.active && h.chain < chain {
                        reach = LifeFar { far: chain - h.chain, home: home, cyclic: h.recursive_call };
                    }
                }
            }
            return life_read_reach(l, leaf, places, key, reach);
        }
    }
    let reach = life_effect_far(l, places); return life_read_reach(l, leaf, places, key, reach);
}
fn life_read_reach(l: Lifetimes&, leaf: i64, places: i64, key: i64, reach: LifeFar) -> i64 {
    let far = reach.far; let outside = far == 9223372036854775807;
    if reach.cyclic { l.offer_recursive = true; }
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
        if own >= 0 && l.summary_reads[own].seen as i64 == leaf && l.summary_reads[own].sent as i64 == context { return far; }
    }
    var frame = l.frame; var depth = 0; let chain = l.frames[l.frame].chain; var settled = false;
    while frame > 0 {
        if settled && far > depth { frame = reach.home; depth = far; }
        if far <= depth {
            // No place belongs to a recursive frame that could take it by its cells.
            if !reach.cyclic { break; }
            frame = life_nearest_recursive(l, frame);
            if frame <= 0 { break; }
            depth = chain - l.frames[frame].chain;
        }
        if !l.frames[frame].validated {
            var external = far > depth;
            if !external && l.frames[frame].recursive_call { external = life_effect_recursive(l, places, frame); }
            if external {
                // The chain check already looked up the offering frame's entry.
                // A missed key is appended at summary_reads.len by life_read_merge.
                var index = own;
                if frame != l.frame || !chained { index = life_read_find(l, frame, key); }
                else if index < 0 { own = l.summary_reads.len; }
                let merged = life_read_merge(l, frame, leaf, key, index, outside);
                if merged == 2 { if outside { break; } settled = true; }
            }
        }
        frame = l.frames[frame].parent; depth += 1;
    }
    if chained {
        if own >= 0 && l.summary_reads[own].seen as i64 == leaf { l.summary_reads[own].sent = context as i32; }
    }
    return far;
}
// Returns the reach of the effect for the leaf's stamp, or -1 if the
// effect was handled without examining its places.
fn life_effect(p: Program&, l: Lifetimes&, effect: const LifeEffect&) -> i64 {
    // With class-keyed frames in use, a discovery summary is kept only where
    // it is read: by an island's root frame, which every call maps it from,
    // and by a recursive frame, whose back edges replay it. A frame outside
    // every island with no recursive frame above it is evaluated once a pass
    // and its effects have landed where they land; were it called again
    // where a summary is wanted, it is evaluated again (life_function).
    if l.discovery && l.class_frames > 0 && l.island == 0 && life_nearest_recursive(l, l.frame) == 0 { return -1; }
    if l.frame <= 0 { l.offer_count += 1; return 9223372036854775807; }
    if effect.places == 0 { l.offer_count += 1; return 0; }
    let pset: const LifeSet& = l.sets[effect.places];
    let pcount = pset.count;
    var single_root: i64 = -1;
    if pcount == 1 {
        single_root = l.alts[pset.first].root;
        if single_root == 0 || l.roots[single_root].frame == l.frame && !l.frames[l.frame].recursive_call {
            l.offer_count += 1;
            return 0;
        }
    }
    // A class frame merges shrink, grow, read and replace effects across source sites.
    var site: i64 = effect.node;
    if l.class_frames > 0 && (effect.kind == 1 || effect.kind == 2 || effect.kind == 3 || effect.kind == 8) { site = -2; }
    l.offer_count += 1;
    // A repeated offer is recorded only where no frame of the chain is recursive.
    if l.discovery && life_offer_repeated(l, effect, site) { return -1; }
    let chain = l.frames[l.frame].chain;
    var reach = LifeFar { far: 0, home: l.frame };
    if pcount == 1 {
        let home = l.roots[single_root].frame;
        if home <= 0 {
            reach = LifeFar { far: 9223372036854775807, home: 0 };
        } else {
            let h: const LifeFrame& = l.frames[home];
            if home == l.frame {
                reach = LifeFar { far: 0, home: l.frame, cyclic: h.recursive_call };
            } else if !h.active || h.chain >= chain {
                reach = LifeFar { far: 9223372036854775807, home: 0 };
            } else {
                reach = LifeFar { far: chain - h.chain, home: home, cyclic: h.recursive_call };
            }
        }
    } else {
        reach = life_effect_far(l, effect.places);
    }
    let far = reach.far; let outside = far == 9223372036854775807;
    if reach.cyclic { l.offer_recursive = true; }
    if far == 0 && !reach.cyclic { return 0; }
    var indexed_key = -1;
    var summary_base_h: u64 = 0; if l.discovery { summary_base_h = life_summary_base_hash(effect, site); }
    var frame = l.frame; var depth = 0;
    // settled: a frame below has already sent these sets up the chain in its
    // activation (LifeSummary.walked, LifeEffect.walked), so the frames they
    // are outside of have taken them.
    var settled = false;
    // A class-keyed frame takes its body's effects for every caller: nothing
    // goes past it (life_class_call replays them into each).
    let island = l.island; var island_chain = 0; if island > 0 { island_chain = l.frames[island].chain; }
    while frame > 0 {
        // The frames between a settled entry and the outermost frame that
        // holds a place have taken these sets. From that frame up, only a
        // recursive frame can take the effect, by its cells.
        if settled && far > depth { frame = reach.home; depth = far; }
        if far <= depth {
            // No place belongs to a recursive frame that could take it by its cells.
            if !reach.cyclic { break; }
            frame = life_nearest_recursive(l, frame);
            if frame <= 0 { break; }
            depth = chain - l.frames[frame].chain;
        }
        if island > 0 && l.frames[frame].chain < island_chain { break; }
        if island == 0 && l.discovery && l.class_frames > 0 && life_nearest_recursive(l, frame) == 0 { break; }
        if !l.frames[frame].validated {
            var external = far > depth;
            if !external && l.frames[frame].recursive_call { external = life_effect_recursive(l, effect.places, frame); }
            var last = l.frames[frame].last_effect; if l.discovery { last = l.frames[frame].last_summary; }
            var skey: i64 = 0; var sslot: i64 = -1; var indexed = -1;
            if external && l.discovery {
                if l.summary_slots.len <= 2 * (l.summary_slot_count + 1) { life_summary_reserve(l); }
                skey = life_summary_key(frame, summary_base_h);
                if last >= 0 {
                    let merged = life_effect_merge(l, effect, frame, skey, outside, site, sslot);
                    if merged == 2 { if outside { return far; } settled = true; }
                    if merged != 0 { external = false; }
                }
            }
            if external && !l.discovery {
                // A store to an exact single root clears all field kills on that root.
                // Any earlier kind-7 kill on that exact root with no intervening shrink
                // can never be observed and is marked dead before deduplication.
                if effect.kind == 4 && (effect.field <= -2 || !life_only_static(l, effect.value.contents)) &&
                   l.sets[effect.places].count == 1 && l.alts[l.sets[effect.places].first].exact {
                    let sfloor = l.frames[frame].last_shrink;
                    let eff_root = l.alts[l.sets[effect.places].first].root;
                    var kt = l.frames[frame].last_kill;
                    while kt > sfloor {
                        let ke: const LifeEffect& = l.effects[kt];
                        if ke.kind == 7 && l.sets[ke.places].count == 1 && l.alts[l.sets[ke.places].first].root == eff_root { l.effects[kt].kind = 0; }
                        kt = ke.previous_barrier;
                    }
                    while l.frames[frame].last_kill >= 0 && l.effects[l.frames[frame].last_kill].kind == 0 {
                        l.frames[frame].last_kill = l.effects[l.frames[frame].last_kill].previous_barrier;
                    }
                }
                if indexed_key < 0 {
                    let p1 = (((effect.kind as! u32) as u64) << 32) | ((effect.value.type_id as! u32) as u64);
                    let p2 = (((effect.value.element_array as! u32) as u64) << 32) | ((effect.field as! u32) as u64);
                    var kh: u64 = p1 * 11400714819323198485 ^ p2 * 14029467366897019727 ^ ((effect.cell as! u32) as u64) * 1609587929392839161;
                    if l.class_frames > 0 && (effect.kind == 2 || effect.kind == 3) {
                        // Merged per (frame, kind, type_id, element_array) across places.
                    } else if effect.kind == 4 {
                        let p3 = (((effect.places as! u32) as u64) << 32) | ((effect.value.refs as! u32) as u64);
                        kh ^= p3 * 9650029242287828579;
                    } else {
                        let p3 = (((effect.places as! u32) as u64) << 32) | ((effect.value.refs as! u32) as u64);
                        kh ^= p3 * 9650029242287828579 ^ ((effect.value.contents as! u32) as u64) * 2870177450012600261;
                    }
                    indexed_key = ((kh ^ (kh >> 29)) >> 1) as! i64;
                }
                if l.effect_heads.len <= 2 * l.indexed_effects { life_index_reserve(l); }
                var fk: u64 = (indexed_key as! u64) ^ ((frame as! u64) * 11400714819323198485);
                fk ^= fk >> 29;
                indexed = (fk >> 1) as! i64;
                if last >= 0 {
                    let found = life_effect_indexed(p, l, effect, frame, life_index_bucket(l, indexed), outside);
                    if found == 2 { if outside { return far; } settled = true; }
                    if found != 0 { external = false; }
                }
            }
            if external {
                let index = l.effects.len; var entry = effect; entry.next = -1; entry.owner = frame as i32;
                let need_summary = l.discovery || l.class_frames == 0;
                if need_summary {
                    if l.summaries.len < index { l.summaries.resize(index, LifeSummary {}); }
                    l.summaries.push(LifeSummary { owner: frame as i32, kind: entry.kind as i32, node: site as i32, type_id: entry.value.type_id as i32, cell: entry.cell as i32, field: entry.field as i32 });
                }
                if l.discovery {
                    life_summary_seen(l, index, entry);
                    if sslot >= 0 {
                        let ent = LifeSummarySlot { key: skey, index: index as i32, frame: frame as i32 };
                        l.summary_slots[sslot] = ent;
                        l.summary_l1[skey & 2047] = ent;
                        l.summary_slot_count += 1;
                    } else {
                        life_summary_insert(l, skey, index, frame);
                    }
                    l.summaries[index].walked = life_walked(l, frame, outside);
                }
                if indexed >= 0 {
                    let slot = life_index_bucket(l, indexed);
                    entry.index_key = indexed; entry.index_next = l.effect_heads[slot]; entry.epoch = l.frames[frame].effect_epoch as i32;
                    entry.walked = 1; if outside { entry.walked = 2; }
                    l.effect_heads[slot] = index as i32; l.indexed_effects += 1;
                }
                l.effects.push(entry);
                if last >= 0 { l.effects[last].next = index as i32; if need_summary && last < l.summaries.len { l.summaries[last].after = index as i32; } }
                if l.discovery {
                    if last < 0 { l.frames[frame].first_summary = index; }
                    l.frames[frame].last_summary = index; l.revision += 1; l.frames[frame].summary_version += 1;
                    if life_replayable_leaf(l, entry.kind) { l.frames[frame].replay_version += 1; }
                    else {
                        let before = l.frames[frame].last_other;
                        if before >= 0 { l.summaries[before].other = index as i32; } else { l.frames[frame].first_other = index; }
                        l.frames[frame].last_other = index;
                    }
                } else {
                    if last < 0 { l.frames[frame].first_effect = index; }
                    l.frames[frame].last_effect = index;
                    if entry.kind == 1 { l.frames[frame].last_shrink = index; }
                    if entry.kind >= 4 { l.frames[frame].last_shrink_barrier = index; }
                    if entry.kind == 4 {
                        l.effects[index].previous_barrier = l.frames[frame].last_store as i32;
                        l.frames[frame].last_store = index;
                    }
                    if entry.kind == 6 || entry.kind == 7 {
                        l.effects[index].previous_barrier = l.frames[frame].last_kill as i32;
                        l.frames[frame].last_kill = index;
                        l.val_kill_epoch += 1;
                    }
                }
            }
        }
        if frame == island { break; }
        frame = l.frames[frame].parent; depth += 1;
    }
    return far;
}

fn life_error(p: Program&, l: Lifetimes&, node: i64, message: const u8[:]) {
    if l.discovery || node < 0 { return; }
    let token = p.nodes[node].token;
    if token < 0 { return; }
    for d in p.diagnostics {
        if d.source == p.tokens[token].source && d.start == p.tokens[token].start { return; }
    }
    if l.frame <= 0 { diagnose(p, token, message); return; }
    var full: u8[>..] = []; full.append(message);
    var f = l.frame; var shown: i64 = 0;
    while f > 0 && shown < 8 {
        let fr: const LifeFrame& = l.frames[f];
        if fr.function_node >= 0 && fr.function_node < p.nodes.len {
            let ftok = p.nodes[fr.function_node].token;
            if ftok >= 0 && ftok < p.tokens.len {
                full.append("\n  in fn "); full.append(token_text(p, ftok));
                if fr.call >= 0 && fr.call < p.nodes.len && p.nodes[fr.call].token >= 0 {
                    full.append(" (called from "); format_token_location(p, p.nodes[fr.call].token, full); full.push(')');
                } else {
                    full.append(" ("); format_token_location(p, ftok, full); full.push(')');
                }
                shown += 1;
            }
        }
        f = fr.parent;
    }
    diagnose(p, token, full);
}
fn life_failure_message(kind: i64) -> const u8[:] {
    if kind == 0 { return "reference or slice binding changes its committed root lifetime depth\n  help: rebind a new variable or keep the target storage at the same lifetime depth (§5.1)"; }
    if kind == 1 { return "stored reference does not outlive the storage that receives it\n  help: store an owned copy or move the referenced storage to an outer scope that outlives the destination (§5.1)"; }
    return "returned reference points into this invocation's local or temporary storage\n  help: return an owned value or a reference derived from a caller-provided parameter (§5.1)";
}
fn life_scope_error(p: Program&, l: Lifetimes&, node: i64, kind: i64) {
    if !l.discovery { life_error(p, l, node, life_failure_message(kind)); return; }
    for failure in l.failures { if failure.node == node { return; } }
    l.failures.push(LifeFailure { node: node, kind: kind });
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
inline fn life_pair_bucket(owner: i64, pointee: i64, count: i64) -> i64 {
    var h: u64 = (owner as! u64) * 11400714819323198485 ^ (pointee as! u64) * 14029467366897019727;
    h ^= h >> 29;
    return (h & ((count - 1) as! u64)) as i64;
}
inline fn life_ecanon(l: Lifetimes&, ty: i64) -> i64 {
    if l.types_frozen && ty >= 0 && ty < l.type_exact_canon.len { return l.type_exact_canon[ty] as i64; }
    return ty;
}
fn life_contains_rehash(p: Program&, l: Lifetimes&) {
    var count: i64 = 128;
    while count < p.types.len || count <= 2 * (l.pair_count + 1) { count <<= 1; }
    var old: LifePairSlot[>..] = []; old.append(l.pair_slots);
    l.pair_slots.clear(); l.pair_slots.resize(count, LifePairSlot {});
    let nmask = count - 1;
    for entry in old {
        if entry.owner < 0 { continue; }
        var s = life_pair_bucket(entry.owner as i64, (entry.pointee_ans >> 1) as i64, count);
        while l.pair_slots[s].owner >= 0 { s = (s + 1) & nmask; }
        l.pair_slots[s] = entry;
    }
}
fn life_build_closure(p: Program&, l: Lifetimes&, co: i64) {
    l.contains_seen_gen += 1;
    let gen = l.contains_seen_gen;
    let wbase = l.type_work.len;
    l.contains_seen[co] = gen;
    l.type_work.push(co as i32);
    let start = l.closure_data.len;
    var at = wbase;
    while at < l.type_work.len {
        let ty = l.type_work[at] as i64; at += 1;
        l.closure_data.push(l.type_canon[ty] as i32);
        let t: const Type& = p.types[ty];
        if t.kind == TY_ARRAY && t.element >= 0 {
            let elem = l.type_exact_canon[t.element] as i64;
            if l.contains_seen[elem] != gen { l.contains_seen[elem] = gen; l.type_work.push(elem as i32); }
        } else if t.kind == TY_STRUCT || t.kind == TY_ENUM || t.kind == TY_TUPLE {
            var field = t.first;
            while field >= 0 {
                let ft = p.nodes[field].type_id;
                if ft >= 0 {
                    let fe = l.type_exact_canon[ft] as i64;
                    if l.contains_seen[fe] != gen { l.contains_seen[fe] = gen; l.type_work.push(fe as i32); }
                }
                field = p.nodes[field].next;
            }
        }
    }
    l.type_work.resize(wbase);
    l.closure_data[start..l.closure_data.len].sort();
    var kept = start;
    for i in start..l.closure_data.len {
        if i == start || l.closure_data[i] != l.closure_data[kept - 1] {
            l.closure_data[kept] = l.closure_data[i]; kept += 1;
        }
    }
    l.closure_data.resize(kept);
    l.closure_start[co] = start as i32;
    l.closure_count[co] = (kept - start) as i32;
}
fn life_contains_unfrozen(p: Program&, l: Lifetimes&, owner: i64, pointee: i64) -> bool {
    if 2 * (l.pair_count + 1) > l.pair_slots.len { life_contains_rehash(p, l); }
    let mask = l.pair_slots.len - 1;
    let owner32 = owner as i32; let pkey = (pointee << 1) as i32;
    var slot = life_pair_bucket(owner, pointee, l.pair_slots.len);
    loop {
        let entry = l.pair_slots[slot];
        if entry.owner < 0 { break; }
        if entry.owner == owner32 && (entry.pointee_ans & ~1) == pkey { return (entry.pointee_ans & 1) != 0; }
        slot = (slot + 1) & mask;
    }
    let base = l.type_work.len; l.type_work.push(owner as i32); var at = base; var answer = false;
    while at < l.type_work.len {
        let ty = l.type_work[at] as i64; at += 1;
        if life_same(p, ty, pointee) { answer = true; break; }
        let t: const Type& = p.types[ty];
        if t.kind == TY_ARRAY && t.element >= 0 {
            let elem = t.element as i32;
            var seen = false; for wi in base..l.type_work.len { if l.type_work[wi] == elem { seen = true; break; } }
            if !seen { l.type_work.push(elem); }
        } else if t.kind == TY_STRUCT || t.kind == TY_ENUM || t.kind == TY_TUPLE {
            var field = t.first;
            while field >= 0 {
                let ft = p.nodes[field].type_id; var seen = ft < 0;
                let ft32 = ft as i32;
                if !seen { for wi in base..l.type_work.len { if l.type_work[wi] == ft32 { seen = true; break; } } }
                if !seen { l.type_work.push(ft32); }
                field = p.nodes[field].next;
            }
        }
    }
    l.type_work.resize(base);
    var encoded = pkey; if answer { encoded |= 1; }
    l.pair_slots[slot] = LifePairSlot { owner: owner32, pointee_ans: encoded };
    l.pair_count += 1;
    return answer;
}
fn life_contains(p: Program&, l: Lifetimes&, raw_owner: i64, raw_pointee: i64) -> bool {
    if raw_owner < 0 || raw_pointee < 0 { return false; }
    if raw_owner == raw_pointee { return true; }
    if l.types_frozen && l.nodes_prepared {
        let co = l.type_exact_canon[raw_owner] as i64;
        let cp = l.type_exact_canon[raw_pointee] as i64;
        if co == cp { return true; }
        let target = l.type_canon[cp] as i32;
        if l.type_canon[co] as i32 == target { return true; }
        let okind = p.types[co].kind;
        if okind != TY_ARRAY && okind != TY_STRUCT && okind != TY_ENUM && okind != TY_TUPLE { return false; }
        let pt: const Type& = p.types[cp];
        if (pt.kind == TY_SLICE || pt.kind == TY_REF && pt.length_storage < 0) && (l.type_flags[co] & TF_L_HOLDS) == 0 { return false; }
        var cnt = l.closure_count[co] as i64;
        if cnt < 0 { life_build_closure(p, l, co); cnt = l.closure_count[co] as i64; }
        let start = l.closure_start[co] as i64;
        if cnt <= 8 {
            for i in start..start + cnt { if l.closure_data[i] == target { return true; } }
            return false;
        }
        var lo = start; var hi = start + cnt;
        while lo < hi {
            let mid = (lo + hi) >> 1;
            let v = l.closure_data[mid];
            if v == target { return true; }
            if v < target { lo = mid + 1; } else { hi = mid; }
        }
        return false;
    }
    let okind = p.types[raw_owner].kind;
    if okind != TY_ARRAY && okind != TY_STRUCT && okind != TY_ENUM && okind != TY_TUPLE { return life_same(p, raw_owner, raw_pointee); }
    return life_contains_unfrozen(p, l, raw_owner, raw_pointee);
}
// life_contains for the scans that ask about one pointee for many owners.
fn life_contains_memo(p: Program&, l: Lifetimes&, raw_owner: i64, raw_pointee: i64) -> bool {
    return life_contains(p, l, raw_owner, raw_pointee);
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
    let known = p.type_holds[ty] & 3;
    if known != 0 { return known == 2; }
    let answer = life_holds_scan(p, ty);
    if answer { p.type_holds[ty] |= 2; } else { p.type_holds[ty] |= 1; }
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
// Sets of LIFE_BIG or more alternatives are accumulated without intermediate
// copies (LifeBuild). Every set is stored sorted ascending by root in a
// contiguous span l.alts[first..first+count], searched directly by binary search.
let LIFE_BIG: i64 = 16;
inline fn life_root_hash(root: i64, mask: i64) -> i64 {
    var h: u64 = (root as! u64) * 1099511628211; h ^= h >> 29;
    return (h & (mask as! u64)) as i64;
}
fn life_find(l: Lifetimes&, set: i64, root: i64) -> i64 {
    let first = l.sets[set].first as i64;
    let count = l.sets[set].count as i64;
    if count == 0 { return -1; }
    if count < 8 {
        for i in 0..count { if l.alts[first + i].root == root { return first + i; } }
        return -1;
    }
    var lo = first; var hi = first + count;
    while lo < hi {
        let mid = lo + ((hi - lo) >> 1);
        let r = l.alts[mid].root as i64;
        if r == root { return mid; }
        if r < root { lo = mid + 1; } else { hi = mid; }
    }
    return -1;
}
// Every set (empty, singleton via life_single, or canonical root-sorted
// multi-element set via life_list_set) has a globally unique ID.
inline fn life_same_list(l: Lifetimes&, a: i64, b: i64) -> bool {
    return a == b;
}
inline fn life_equal(l: Lifetimes&, a: i64, b: i64) -> bool {
    return a == b;
}
// An alternative with another for the same root merged into it.
inline fn life_merged(old: const LifeAlt&, alt: const LifeAlt&) -> LifeAlt {
    var out = old;
    out.exact = old.exact && alt.exact;
    out.slotread = old.slotread && alt.slotread;
    out.byteview = old.byteview || alt.byteview;
    if alt.bound > old.bound { out.bound = alt.bound; }
    if old.from != alt.from { out.from = -1; }
    if old.target_type != alt.target_type { out.target_type = -1; }
    if old.component != alt.component { out.component = -1; }
    return out;
}
fn life_insert(l: Lifetimes&, set: i64, alt: const LifeAlt&) {
    let index = l.alts.len; var entry = alt; entry.next = -1;
    l.alts.push(entry); l.sets[set].first = index as i32; l.sets[set].count = 1;
    let rt: const LifeRoot& = l.roots[alt.root];
    var fl: u8 = 0;
    if rt.class_frame >= 0 { fl = 4; }
    else if rt.frame <= 0 { fl = 1; if alt.root > 0 { fl = 3; } }
    l.sets[set].flags = fl;
}
// Whether old, for the same root, already admits everything incoming does.
inline fn life_covers(old: const LifeAlt&, incoming: const LifeAlt&) -> bool {
    return !(old.exact && !incoming.exact || old.slotread && !incoming.slotread ||
       !old.byteview && incoming.byteview || old.from >= 0 && old.from != incoming.from || old.target_type >= 0 && old.target_type != incoming.target_type || old.bound < incoming.bound ||
       old.component >= 0 && old.component != incoming.component);
}
// Whether joining b into a returns a. Both sets are contiguous and sorted by root.
fn life_subset(l: Lifetimes&, b: i64, a: i64) -> bool {
    if b == a || b == 0 { return true; }
    let cb = l.sets[b].count as i64;
    if cb == 0 { return true; }
    let ca = l.sets[a].count as i64;
    if ca < cb { return false; }
    let fa = l.sets[a].first as i64; let fb = l.sets[b].first as i64;
    if cb * 4 < ca {
        var lo = fa; let hi_end = fa + ca;
        for i in 0..cb {
            let incoming: const LifeAlt& = l.alts[fb + i];
            let target = incoming.root as i64;
            var hi = hi_end;
            while lo < hi {
                let mid = lo + ((hi - lo) >> 1);
                if (l.alts[mid].root as i64) < target { lo = mid + 1; } else { hi = mid; }
            }
            if lo >= hi_end || (l.alts[lo].root as i64) != target || !life_covers(l.alts[lo], incoming) { return false; }
            lo += 1;
        }
        return true;
    }
    var ia = fa; let ea = fa + ca;
    var ib = fb; let eb = fb + cb;
    while ib < eb {
        let incoming: const LifeAlt& = l.alts[ib]; let target = incoming.root as i64;
        while ia < ea && (l.alts[ia].root as i64) < target { ia += 1; }
        if ia >= ea || (l.alts[ia].root as i64) != target || !life_covers(l.alts[ia], incoming) { return false; }
        ia += 1; ib += 1;
    }
    return true;
}

// Accumulating `out = life_join(l, out, x)` over many x copies all of out
// into a new set whenever x adds to it: an n-root result costs ~n^2/2
// alternatives. A LifeBuild yields what exactly those joins would (the
// alternatives and their list order) but makes only the last set.
// Below LIFE_BIG it joins as before. Past it, the list is kept in
// build_alts as a deque, and the set is made when the build ends. A
// join that adds lists the incoming new roots, last first, before out
// reversed: the deque's front holds pushes in reverse order and its back in
// order (side 0 or 1, kept in next), and flipped means the list reads it
// back to front. Builds nest as a stack: one is extended only after every
// build opened since has ended.
struct LifeBuild { set: i64 = 0, base: i64 = -1, size: i64 = 0, table: i64 = -1, mask: i64 = 0, flipped: bool = false, fresh: bool = false }
// A set as life_single makes one.
fn life_new_set(l: Lifetimes&) -> i64 {
    let set = l.sets.len; l.sets.push(LifeSet {});
    return set;
}
inline fn life_build_find_small(l: Lifetimes&, b: const LifeBuild&, root: i64) -> i64 {
    let end = b.base + b.size;
    for i in b.base..end { if l.build_alts[i].root == root { return i; } }
    return -1;
}
fn life_build_slot(l: Lifetimes&, b: const LifeBuild&, root: i64) -> i64 {
    var h = life_root_hash(root, b.mask);
    loop {
        let at = l.build_slots[b.table + h];
        if at < 0 || l.build_alts[at].root == root { return b.table + h; }
        h = (h + 1) & b.mask;
    }
    return -1;
}
fn life_build_rehash(l: Lifetimes&, b: LifeBuild&, size: i64) {
    l.build_slots.resize(b.table); l.build_slots.resize(b.table + size, -1); b.mask = size - 1;
    let end = b.base + b.size;
    for index in b.base..end { l.build_slots[life_build_slot(l, b, l.build_alts[index].root)] = index; }
}
fn life_build_promote(l: Lifetimes&, b: LifeBuild&) {
    b.table = l.build_slots.len;
    var size: i64 = 64; while size < 4 * b.size { size <<= 1; }
    life_build_rehash(l, b, size);
}
fn life_build_push(l: Lifetimes&, b: LifeBuild&, slot: i64, alt: LifeAlt, side: i64) {
    var entry = alt; entry.next = side as i32;
    l.build_slots[slot] = l.build_alts.len; l.build_alts.push(entry); b.size += 1;
    if 2 * b.size > b.mask + 1 { life_build_rehash(l, b, 2 * (b.mask + 1)); }
}
fn life_build_open(l: Lifetimes&, b: LifeBuild&) {
    b.base = l.build_alts.len; b.size = 0; b.table = -1; b.mask = 0; b.flipped = false; b.fresh = false;
    let first = l.sets[b.set].first as i64; let count = l.sets[b.set].count as i64;
    for i in 0..count { l.build_alts.push(l.alts[first + i]); }
    b.size = count;
    if b.size >= LIFE_BIG { life_build_promote(l, b); }
}
// out = life_join(l, out, set).
fn life_build_add(l: Lifetimes&, b: LifeBuild&, set: i64) {
    if b.base < 0 {
        if l.sets[b.set].count < LIFE_BIG { b.set = life_join(l, b.set, set); return; }
        if life_subset(l, set, b.set) { return; }
        life_build_open(l, b);
    }
    life_build_step(l, b, set);
}
// out = life_join(l, out, life_single(l, ...alt)), without making that
// single-alternative set: the same list and order, from the alternative.
fn life_build_add_alt(l: Lifetimes&, b: LifeBuild&, alt: LifeAlt) {
    if b.base < 0 {
        let count = l.sets[b.set].count;
        if count < LIFE_BIG {
            if b.set == 0 { b.set = life_alt_set(l, alt); return; }
            let existing = life_find(l, b.set, alt.root);
            if existing >= 0 && life_covers(l.alts[existing], alt) { return; }
            // Once frames are keyed by class the build is opened at its
            // second alternative: the sets in between are never read, and a
            // large program makes most of its alternatives in them.
            if count + 1 < LIFE_BIG && l.class_frames == 0 {
                let start = l.scratch.len; let first = l.sets[b.set].first as i64;
                for i in 0..count { l.scratch.push(l.alts[first + i]); }
                life_scratch_insert(l, start, alt);
                b.set = life_list_set(l, start); l.scratch.resize(start);
                return;
            }
        } else {
            let existing = life_find(l, b.set, alt.root);
            if existing >= 0 && life_covers(l.alts[existing], alt) { return; }
        }
        life_build_open(l, b);
    }
    if b.table < 0 {
        let existing = life_build_find_small(l, b, alt.root);
        if existing >= 0 {
            if life_covers(l.build_alts[existing], alt) { return; }
            b.fresh = true;
            l.build_alts[existing] = life_merged(l.build_alts[existing], alt);
            return;
        }
        b.fresh = true;
        l.build_alts.push(alt); b.size += 1;
        if b.size >= LIFE_BIG { life_build_promote(l, b); }
        return;
    }
    let slot = life_build_slot(l, b, alt.root); let existing = l.build_slots[slot];
    if existing >= 0 && life_covers(l.build_alts[existing], alt) { return; }
    b.fresh = true;
    if existing >= 0 { l.build_alts[existing] = life_merged(l.build_alts[existing], alt); }
    else { life_build_push(l, b, slot, alt, 0); }
}
// A set of one alternative, canonically interned via life_single.
inline fn life_alt_set(l: Lifetimes&, alt: const LifeAlt&) -> i64 {
    return life_single(l, alt.root as i64, alt.exact, alt.from as i64, alt.slotread, alt.byteview, alt.target_type as i64, alt.bound as i64, alt.component as i64);
}
// The same for an open build.
fn life_build_step(l: Lifetimes&, b: LifeBuild&, set: i64) {
    let first = l.sets[set].first as i64; let count = l.sets[set].count as i64;
    if count == 0 { return; }
    if b.table < 0 {
        for k in 0..count {
            let incoming: const LifeAlt& = l.alts[first + k];
            if b.table < 0 {
                let existing = life_build_find_small(l, b, incoming.root);
                if existing >= 0 {
                    if !life_covers(l.build_alts[existing], incoming) {
                        b.fresh = true;
                        l.build_alts[existing] = life_merged(l.build_alts[existing], incoming);
                    }
                } else {
                    b.fresh = true;
                    l.build_alts.push(incoming); b.size += 1;
                    if b.size >= LIFE_BIG { life_build_promote(l, b); }
                }
            } else {
                let slot = life_build_slot(l, b, incoming.root); let existing = l.build_slots[slot];
                if existing >= 0 {
                    if !life_covers(l.build_alts[existing], incoming) {
                        b.fresh = true;
                        l.build_alts[existing] = life_merged(l.build_alts[existing], incoming);
                    }
                } else {
                    b.fresh = true;
                    life_build_push(l, b, slot, incoming, 0);
                }
            }
        }
        return;
    }
    var i: i64 = 0;
    while i < count {
        let incoming: const LifeAlt& = l.alts[first + i]; let existing = l.build_slots[life_build_slot(l, b, incoming.root)];
        if existing < 0 || !life_covers(l.build_alts[existing], incoming) { break; }
        i += 1;
    }
    if i >= count { return; }
    b.fresh = true;
    for k in i..count {
        let incoming: const LifeAlt& = l.alts[first + k];
        let slot = life_build_slot(l, b, incoming.root); let existing = l.build_slots[slot];
        if existing >= 0 { l.build_alts[existing] = life_merged(l.build_alts[existing], incoming); }
        else { life_build_push(l, b, slot, incoming, 0); }
    }
}
// Appends an open build's elements to scratch (canonicalized in life_list_set).
fn life_build_order(l: Lifetimes&, b: const LifeBuild&, head_first: bool) {
    let end = b.base + b.size;
    for at in b.base..end { l.scratch.push(l.build_alts[at]); }
}
inline fn life_alt_same(a: const LifeAlt&, b: const LifeAlt&) -> bool {
    return a.root == b.root && a.exact == b.exact && a.from == b.from && a.slotread == b.slotread && a.byteview == b.byteview &&
       a.target_type == b.target_type && a.bound == b.bound && a.component == b.component;
}
// Sort scratch[start..] ascending by root in place; linear scan when already sorted.
fn life_scratch_sort(l: Lifetimes&, start: i64) {
    let end = l.scratch.len; let count = end - start;
    if count <= 1 { return; }
    var first = start + 1;
    while first < end && l.scratch[first].root >= l.scratch[first - 1].root { first += 1; }
    if first == end { return; }
    if count <= 32 || end - first <= 8 {
        for i in first..end {
            let key = l.scratch[i]; var j = i - 1;
            while j >= start && l.scratch[j].root > key.root { l.scratch[j + 1] = l.scratch[j]; j -= 1; }
            l.scratch[j + 1] = key;
        }
        return;
    }
    // Iterative median-of-3 quicksort with insertion-sort cutoff (zero allocations).
    var lo_stack: i64[64] = [0; 64]; var hi_stack: i64[64] = [0; 64];
    var sp: i64 = 0; var lo = start; var hi = end - 1;
    loop {
        if hi - lo <= 16 {
            for i in lo + 1..hi + 1 {
                let key = l.scratch[i]; var j = i - 1;
                while j >= lo && l.scratch[j].root > key.root { l.scratch[j + 1] = l.scratch[j]; j -= 1; }
                l.scratch[j + 1] = key;
            }
            if sp == 0 { return; }
            sp -= 1; lo = lo_stack[sp]; hi = hi_stack[sp];
            continue;
        }
        let mid = lo + ((hi - lo) >> 1);
        if l.scratch[mid].root < l.scratch[lo].root { let t = l.scratch[lo]; l.scratch[lo] = l.scratch[mid]; l.scratch[mid] = t; }
        if l.scratch[hi].root < l.scratch[lo].root { let t = l.scratch[lo]; l.scratch[lo] = l.scratch[hi]; l.scratch[hi] = t; }
        if l.scratch[hi].root < l.scratch[mid].root { let t = l.scratch[mid]; l.scratch[mid] = l.scratch[hi]; l.scratch[hi] = t; }
        let pivot = l.scratch[mid].root;
        var i = lo; var j = hi;
        loop {
            while l.scratch[i].root < pivot { i += 1; }
            while l.scratch[j].root > pivot { j -= 1; }
            if i >= j { break; }
            let t = l.scratch[i]; l.scratch[i] = l.scratch[j]; l.scratch[j] = t;
            i += 1; j -= 1;
        }
        if j - lo < hi - j {
            if j + 1 < hi { lo_stack[sp] = j + 1; hi_stack[sp] = hi; sp += 1; }
            hi = j;
        } else {
            if lo < j { lo_stack[sp] = lo; hi_stack[sp] = j; sp += 1; }
            lo = j + 1;
        }
    }
}
// Whether a canonical set equals sorted scratch[start..].
fn life_list_same(l: Lifetimes&, set: i64, start: i64) -> bool {
    let base = l.sets[set].first as i64; let count = l.sets[set].count as i64;
    if l.scratch.len - start != count { return false; }
    for i in 0..count {
        if !life_alt_same(l.alts[base + i], l.scratch[start + i]) { return false; }
    }
    return true;
}
fn life_list_rehash(l: Lifetimes&) {
    var size: i64 = 1024; while size <= 2 * (l.list_count + 1) { size <<= 1; }
    var old: LifeListSlot[>..] = []; old.append(l.list_slots);
    l.list_slots.clear(); l.list_slots.resize(size, LifeListSlot {});
    let mask = size - 1;
    for entry in old {
        if entry.set < 0 { continue; }
        var slot = entry.key & mask;
        while l.list_slots[slot].set >= 0 { slot = (slot + 1) & mask; }
        l.list_slots[slot] = entry;
    }
}
inline fn life_alt_hash_step(h: u64, a: const LifeAlt&) -> u64 {
    let p1 = (((a.root as! u32) as u64) | (((a.from as! u32) as u64) << 32));
    let p2 = (((a.target_type as! u32) as u64) | (((a.bound as! u32) as u64) << 32));
    var flags: u64 = 0; if a.exact { flags |= 1; } if a.slotread { flags |= 2; } if a.byteview { flags |= 4; }
    let p3 = (((a.component as! u32) as u64) | (flags << 32));
    var x = (h ^ p1) * 11400714819323198485;
    return (x ^ p2) * 14029467366897019727 ^ p3;
}
inline fn life_hash_finish(h: u64) -> i64 {
    var x = h ^ (h >> 29); x *= 1099511628211; x ^= x >> 31;
    return (x >> 1) as! i64;
}
// Canonical root-sorted set interned from scratch[start..].
fn life_list_set(l: Lifetimes&, start: i64, already_sorted: bool = false) -> i64 {
    let count = l.scratch.len - start;
    if count <= 0 { return 0; }
    if count == 1 { return life_alt_set(l, l.scratch[start]); }
    if !already_sorted {
        if count == 2 {
            if l.scratch[start].root > l.scratch[start + 1].root {
                let t = l.scratch[start]; l.scratch[start] = l.scratch[start + 1]; l.scratch[start + 1] = t;
            }
        } else { life_scratch_sort(l, start); }
    }
    var h: u64 = 1469598103934665603;
    for at in start..l.scratch.len { h = life_alt_hash_step(h, l.scratch[at]); }
    let key = life_hash_finish(h);
    if 2 * (l.list_count + 1) > l.list_slots.len { life_list_rehash(l); }
    let mask = l.list_slots.len - 1; var slot = key & mask; let count32 = count as i32;
    loop {
        let entry = l.list_slots[slot];
        if entry.set < 0 { break; }
        if entry.key == key && entry.count == count32 && life_list_same(l, entry.set as i64, start) { return entry.set as i64; }
        slot = (slot + 1) & mask;
    }
    let base = l.alts.len;
    var fl: u8 = 1;
    for i in 0..count {
        var entry = l.scratch[start + i];
        let rt: const LifeRoot& = l.roots[entry.root];
        if rt.class_frame >= 0 { fl = (fl & 6) | 4; }
        else if rt.frame > 0 { fl &= 6; }
        else if entry.root > 0 { fl |= 2; }
        if i + 1 < count { entry.next = (base + i + 1) as i32; } else { entry.next = -1; }
        l.alts.push(entry);
    }
    let index = l.sets.len; l.sets.push(LifeSet { first: base as i32, count: count32, flags: fl });
    l.list_slots[slot] = LifeListSlot { key: key, set: index as i32, count: count32 };
    l.list_count += 1;
    return index;
}
fn life_build_sort(l: Lifetimes&, start: i64) {
    let end = l.build_alts.len; let count = end - start;
    if count <= 1 { return; }
    var first = start + 1;
    while first < end && l.build_alts[first].root >= l.build_alts[first - 1].root { first += 1; }
    if first == end { return; }
    if count <= 32 || end - first <= 8 {
        for i in first..end {
            let key = l.build_alts[i]; var j = i - 1;
            while j >= start && l.build_alts[j].root > key.root { l.build_alts[j + 1] = l.build_alts[j]; j -= 1; }
            l.build_alts[j + 1] = key;
        }
        return;
    }
    var lo_stack: i64[64] = [0; 64]; var hi_stack: i64[64] = [0; 64];
    var sp: i64 = 0; var lo = start; var hi = end - 1;
    loop {
        if hi - lo <= 16 {
            for i in lo + 1..hi + 1 {
                let key = l.build_alts[i]; var j = i - 1;
                while j >= lo && l.build_alts[j].root > key.root { l.build_alts[j + 1] = l.build_alts[j]; j -= 1; }
                l.build_alts[j + 1] = key;
            }
            if sp == 0 { return; }
            sp -= 1; lo = lo_stack[sp]; hi = hi_stack[sp];
            continue;
        }
        let mid = lo + ((hi - lo) >> 1);
        if l.build_alts[mid].root < l.build_alts[lo].root { let t = l.build_alts[lo]; l.build_alts[lo] = l.build_alts[mid]; l.build_alts[mid] = t; }
        if l.build_alts[hi].root < l.build_alts[lo].root { let t = l.build_alts[lo]; l.build_alts[lo] = l.build_alts[hi]; l.build_alts[hi] = t; }
        if l.build_alts[hi].root < l.build_alts[mid].root { let t = l.build_alts[mid]; l.build_alts[mid] = l.build_alts[hi]; l.build_alts[hi] = t; }
        let pivot = l.build_alts[mid].root;
        var i = lo; var j = hi;
        loop {
            while l.build_alts[i].root < pivot { i += 1; }
            while l.build_alts[j].root > pivot { j -= 1; }
            if i >= j { break; }
            let t = l.build_alts[i]; l.build_alts[i] = l.build_alts[j]; l.build_alts[j] = t;
            i += 1; j -= 1;
        }
        if j - lo < hi - j {
            if j + 1 < hi { lo_stack[sp] = j + 1; hi_stack[sp] = hi; sp += 1; }
            hi = j;
        } else {
            if lo < j { lo_stack[sp] = lo; hi_stack[sp] = j; sp += 1; }
            lo = j + 1;
        }
    }
}
fn life_build_list_same(l: Lifetimes&, set: i64, start: i64) -> bool {
    let base = l.sets[set].first as i64; let count = l.sets[set].count as i64;
    if l.build_alts.len - start != count { return false; }
    for i in 0..count {
        if !life_alt_same(l.alts[base + i], l.build_alts[start + i]) { return false; }
    }
    return true;
}
fn life_build_list_set(l: Lifetimes&, start: i64) -> i64 {
    let count = l.build_alts.len - start;
    if count <= 0 { return 0; }
    if count == 1 { return life_alt_set(l, l.build_alts[start]); }
    if count == 2 {
        if l.build_alts[start].root > l.build_alts[start + 1].root {
            let t = l.build_alts[start]; l.build_alts[start] = l.build_alts[start + 1]; l.build_alts[start + 1] = t;
        }
    } else { life_build_sort(l, start); }
    var h: u64 = 1469598103934665603;
    for at in start..l.build_alts.len { h = life_alt_hash_step(h, l.build_alts[at]); }
    let key = life_hash_finish(h);
    if 2 * (l.list_count + 1) > l.list_slots.len { life_list_rehash(l); }
    let mask = l.list_slots.len - 1; var slot = key & mask; let count32 = count as i32;
    loop {
        let entry = l.list_slots[slot];
        if entry.set < 0 { break; }
        if entry.key == key && entry.count == count32 && life_build_list_same(l, entry.set as i64, start) { return entry.set as i64; }
        slot = (slot + 1) & mask;
    }
    let base = l.alts.len;
    var fl: u8 = 1;
    for i in 0..count {
        var entry = l.build_alts[start + i];
        let rt: const LifeRoot& = l.roots[entry.root];
        if rt.class_frame >= 0 { fl = (fl & 6) | 4; }
        else if rt.frame > 0 { fl &= 6; }
        else if entry.root > 0 { fl |= 2; }
        if i + 1 < count { entry.next = (base + i + 1) as i32; } else { entry.next = -1; }
        l.alts.push(entry);
    }
    let index = l.sets.len; l.sets.push(LifeSet { first: base as i32, count: count32, flags: fl });
    l.list_slots[slot] = LifeListSlot { key: key, set: index as i32, count: count32 };
    l.list_count += 1;
    return index;
}
// life_insert into the list scratch[start..], kept tail first.
fn life_scratch_insert(l: Lifetimes&, start: i64, alt: LifeAlt) {
    for at in start..l.scratch.len {
        if l.scratch[at].root == alt.root { l.scratch[at] = life_merged(l.scratch[at], alt); return; }
    }
    l.scratch.push(alt);
}
// The accumulated set.
fn life_build_end(l: Lifetimes&, b: LifeBuild&) -> i64 {
    if b.base < 0 { return b.set; }
    if b.fresh {
        b.set = life_build_list_set(l, b.base); b.fresh = false;
    }
    l.build_alts.resize(b.base);
    if b.table >= 0 { l.build_slots.resize(b.table); b.table = -1; }
    b.base = -1;
    return b.set;
}
// Appends the accumulated set's list, head first, to scratch and ends the
// build without making that set, for a caller that only reads the list once.
fn life_build_drop(l: Lifetimes&, b: LifeBuild&) {
    if b.base < 0 {
        let first = l.sets[b.set].first as i64; let count = l.sets[b.set].count as i64;
        for i in 0..count { l.scratch.push(l.alts[first + i]); }
        return;
    }
    life_build_order(l, b, true);
    l.build_alts.resize(b.base);
    if b.table >= 0 { l.build_slots.resize(b.table); b.table = -1; }
    b.base = -1;
}
fn life_single(l: Lifetimes&, root: i64, exact: bool = true, from: i64 = -1, slotread: bool = false, byteview: bool = false, target_type: i64 = -1, bound: i64 = 0, component: i64 = -1) -> i64 {
    let ordinary = exact && from == -1 && !slotread && !byteview && target_type == -1 && bound == 0 && component == -1;
    let plain_sr = exact && from == -1 && slotread && !byteview && target_type == -1 && bound == 0 && component == -1;
    if plain_sr && l.roots[root].slotread_set >= 0 { return l.roots[root].slotread_set as i64; }
    var head = l.roots[root].atoms; var cached = -1;
    if head < -1 {
        cached = -2 - head;
        if ordinary { return l.atoms[cached].set; }
        head = l.atoms[cached].next;
    }
    // A root's atoms hold distinct alternatives, so the one in its chain
    // that matches is the one atom_slots finds.
    let wanted = LifeAlt { root: root as i32, from: from as i32, target_type: target_type as i32, bound: bound as i32, component: component as i32, exact: exact, slotread: slotread, byteview: byteview };
    let la = l.roots[root].last_atom_set as i64;
    if la >= 0 && life_alt_same(l.alts[l.sets[la].first as i64], wanted) {
        if plain_sr { l.roots[root].slotread_set = la as i32; }
        return la;
    }
    if 2 * (l.atoms.len + 1) > l.atom_slots.len { life_atom_rehash(l); }
    let key = life_atom_hash(wanted); let mask = l.atom_slots.len - 1; var slot = key & mask;
    loop {
        let entry = l.atom_slots[slot];
        if entry.set < 0 { break; }
        if entry.key == key && life_alt_same(l.alts[entry.alt as i64], wanted) {
            if plain_sr { l.roots[root].slotread_set = entry.set; }
            else if !ordinary { l.roots[root].last_atom_set = entry.set; }
            return entry.set as i64;
        }
        slot = (slot + 1) & mask;
    }
    let set = life_new_set(l);
    life_insert(l, set, wanted);
    let atom = l.atoms.len; l.atoms.push(LifeAtom { set: set, next: head });
    l.atom_slots[slot] = LifeAtomSlot { key: key, alt: l.sets[set].first, set: set as i32 };
    if ordinary { l.roots[root].atoms = -2 - atom; }
    else if cached >= 0 { l.atoms[cached].next = atom; }
    else { l.roots[root].atoms = atom; }
    if plain_sr { l.roots[root].slotread_set = set as i32; }
    else if !ordinary { l.roots[root].last_atom_set = set as i32; }
    return set;
}
inline fn life_atom_hash(alt: const LifeAlt&) -> i64 {
    return life_hash_finish(life_alt_hash_step(1469598103934665603, alt));
}
fn life_atom_rehash(l: Lifetimes&) {
    var size: i64 = 1024; while size <= 2 * (l.atoms.len + 1) { size <<= 1; }
    l.atom_slots.clear(); l.atom_slots.resize(size, LifeAtomSlot {});
    for atom in l.atoms {
        let alt = l.sets[atom.set].first; let key = life_atom_hash(l.alts[alt as i64]); var slot = key & (size - 1);
        while l.atom_slots[slot].set >= 0 { slot = (slot + 1) & (size - 1); }
        l.atom_slots[slot] = LifeAtomSlot { key: key, alt: alt, set: atom.set as i32 };
    }
}
inline fn life_root_set(l: Lifetimes&, root: i64) -> i64 {
    let head = l.roots[root].atoms;
    if head < -1 { return l.atoms[-2 - head].set; }
    return life_single(l, root);
}
inline fn life_interior(l: Lifetimes&, roots: i64) -> i64 {
    if roots == 0 { return 0; }
    let cached = l.sets[roots].interior as i64;
    if cached >= 0 { return cached; }
    return life_interior_slow(l, roots);
}
fn life_interior_slow(l: Lifetimes&, roots: i64) -> i64 {
    let first = l.sets[roots].first as i64; let count = l.sets[roots].count as i64;
    if count <= 0 { return 0; }
    var unchanged = true;
    for i in 0..count {
        let a: const LifeAlt& = l.alts[first + i];
        if a.slotread || a.target_type >= 0 { unchanged = false; break; }
    }
    if unchanged { l.sets[roots].interior = roots as i32; return roots; }
    let start = l.scratch.len;
    for i in 0..count { var alt = l.alts[first + i]; alt.slotread = false; alt.target_type = -1; l.scratch.push(alt); }
    let result = life_list_set(l, start, true);
    l.scratch.resize(start);
    l.sets[roots].interior = result as i32;
    return result;
}
fn life_grow_only_interior(l: Lifetimes&, roots: i64) -> i64 {
    let first = l.sets[roots].first as i64; let count = l.sets[roots].count as i64;
    if count <= 0 { return 0; }
    var unchanged = true;
    for i in 0..count {
        let a: const LifeAlt& = l.alts[first + i];
        if !a.slotread || a.target_type >= 0 { unchanged = false; break; }
    }
    if unchanged { return roots; }
    let start = l.scratch.len;
    for i in 0..count { var alt = l.alts[first + i]; alt.slotread = true; alt.target_type = -1; l.scratch.push(alt); }
    let result = life_list_set(l, start, true);
    l.scratch.resize(start);
    return result;
}
fn life_member_interior(l: Lifetimes&, roots: i64) -> i64 {
    let first = l.sets[roots].first as i64; let count = l.sets[roots].count as i64;
    if count <= 0 { return 0; }
    var unchanged = true;
    for i in 0..count { if l.alts[first + i].target_type >= 0 { unchanged = false; break; } }
    if unchanged { return roots; }
    let start = l.scratch.len;
    for i in 0..count { var alt = l.alts[first + i]; alt.target_type = -1; l.scratch.push(alt); }
    let result = life_list_set(l, start, true);
    l.scratch.resize(start);
    return result;
}
fn life_mark_slotread(l: Lifetimes&, set: i64) -> i64 {
    if set == 0 { return 0; }
    let cached = l.sets[set].slotread as i64;
    if cached >= 0 { return cached; }
    let first = l.sets[set].first as i64; let count = l.sets[set].count as i64;
    var all = true;
    for i in 0..count { if !l.alts[first + i].slotread { all = false; break; } }
    if all { l.sets[set].slotread = set as i32; return set; }
    let start = l.scratch.len;
    for i in 0..count { var alt = l.alts[first + i]; alt.slotread = true; l.scratch.push(alt); }
    let result = life_list_set(l, start, true);
    l.scratch.resize(start);
    l.sets[set].slotread = result as i32;
    return result;
}
// A field of a root owner is that owner's own component; any other field
// lies inside its container's storage.
fn life_component(l: Lifetimes&, places: i64, field: i64) -> i64 {
    let first = l.sets[places].first as i64; let count = l.sets[places].count as i64;
    if count <= 0 { return 0; }
    let start = l.scratch.len;
    for i in 0..count {
        var alt = l.alts[first + i]; if alt.component < 0 { alt.component = field as i32; }
        alt.slotread = false; alt.target_type = -1; l.scratch.push(alt);
    }
    let result = life_list_set(l, start, true);
    l.scratch.resize(start);
    return result;
}

inline fn life_join(l: Lifetimes&, a: i64, b: i64) -> i64 {
    if b == 0 || a == b { return a; }
    return life_join_slow(l, a, b);
}
fn life_join_slow(l: Lifetimes&, a_in: i64, b_in: i64) -> i64 {
    if a_in == 0 { return b_in; }
    var a = a_in; var b = b_in;
    if a > b { let swap = a; a = b; b = swap; }
    let ca = l.sets[a].count as i64; let cb = l.sets[b].count as i64;
    if ca == 0 { return b; }
    if cb == 0 { return a; }
    if l.joins.len == 0 { l.joins.resize(1024, LifeJoin {}); }
    let a32 = a as i32; let b32 = b as i32;
    var h: u64 = (a as! u64) * 11400714819323198485 ^ (b as! u64) * 14029467366897019727; h ^= h >> 29;
    let slot = (h & ((l.joins.len - 1) as! u64)) as i64;
    let alt_slot = slot ^ 1;
    let j0 = l.joins[slot];
    if j0.a == a32 && j0.b == b32 { return j0.set as i64; }
    let j1 = l.joins[alt_slot];
    if j1.a == a32 && j1.b == b32 { return j1.set as i64; }
    // Fast subset check avoids touching l.scratch on the common no-op joins.
    var set: i64 = -1;
    if ca >= cb && life_subset(l, b, a) { set = a; }
    else if cb >= ca && life_subset(l, a, b) { set = b; }
    if set < 0 {
        // Single linear two-pointer merge of two root-sorted spans into l.scratch.
        let fa = l.sets[a].first as i64; let ea = fa + ca;
        let fb = l.sets[b].first as i64; let eb = fb + cb;
        let start = l.scratch.len;
        var ia = fa; var ib = fb;
        while ia < ea && ib < eb {
            let xa: const LifeAlt& = l.alts[ia]; let xb: const LifeAlt& = l.alts[ib];
            if xa.root < xb.root { l.scratch.push(xa); ia += 1; }
            else if xb.root < xa.root { l.scratch.push(xb); ib += 1; }
            else { l.scratch.push(life_merged(xa, xb)); ia += 1; ib += 1; }
        }
        while ia < ea { l.scratch.push(l.alts[ia]); ia += 1; }
        while ib < eb { l.scratch.push(l.alts[ib]); ib += 1; }
        set = life_list_set(l, start, true);
        l.scratch.resize(start);
    }
    if j0.a < 0 { l.joins[slot] = LifeJoin { a: a32, b: b32, set: set as i32 }; }
    else if j1.a < 0 { l.joins[alt_slot] = LifeJoin { a: a32, b: b32, set: set as i32 }; }
    else { l.joins[alt_slot] = j0; l.joins[slot] = LifeJoin { a: a32, b: b32, set: set as i32 }; }
    l.joins_recorded++;
    if l.joins_recorded > 4 * l.joins.len && l.joins.len < 1048576 { l.joins.resize(4 * l.joins.len, LifeJoin {}); l.joins_recorded = 0; }
    return set;
}
fn life_depth(l: Lifetimes&, scope: i64) -> i64 {
    if l.frame == 0 {
        if scope >= 0 && scope < l.depths.len { return 2 * l.depths[scope]; }
        return 0;
    }
    let frame: const LifeFrame& = l.frames[l.frame]; var declaration = 0;
    if frame.function_node >= 0 {
        var at = scope;
        while at > 0 && l.functions[at] == frame.function_node { declaration = l.depths[at]; at = l.parents[at]; }
    }
    if scope < 0 || scope >= l.depths.len { return frame.base; }
    return frame.base + 2 * (l.depths[scope] - declaration);
}
inline fn life_is_global_bound(l: Lifetimes&, a: LifeAlt) -> bool {
    return a.root as i64 == l.globals_root || !a.exact && a.root != 0 && l.roots[a.root].frame == 0 && l.roots[a.root].depth == 0 && l.roots[a.root].class_frame < 0;
}
fn life_alt_depth(l: Lifetimes&, alt: const LifeAlt&) -> i64 {
    let depth = l.roots[alt.root].depth;
    if l.island == 0 && alt.bound > depth { return alt.bound; }
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
        if frame == l.island { break; }
        frame = l.frames[frame].parent;
    }
    return l.frame;
}
inline fn life_frame_hash(id: i64, frame: i64, mask: i64) -> i64 {
    var h: u64 = (id as! u64) * 11400714819323198485 ^ (frame as! u64) * 14029467366897019727; h ^= h >> 29;
    return (h & (mask as! u64)) as i64;
}
// Room for one more cell at half load.
fn life_cell_reserve(l: Lifetimes&) {
    if 2 * (l.cells.len + 1) <= l.cell_slots.len { return; }
    var size: i64 = 64; while size < 4 * (l.cells.len + 1) { size <<= 1; }
    l.cell_slots.clear(); l.cell_slots.resize(size, -1);
    for index in 0..l.cells.len {
        let cell: const LifeCell& = l.cells[index];
        var slot = life_frame_hash(cell.symbol, cell.frame, size - 1);
        while l.cell_slots[slot] >= 0 { slot = (slot + 1) & (size - 1); }
        l.cell_slots[slot] = index as i32;
    }
}
fn life_cell(p: Program&, l: Lifetimes&, symbol: i64) -> i64 {
    if symbol < 0 || symbol >= p.symbols.len { return -1; }
    let head = l.symbol_cells[symbol] as i64;
    if head >= 0 {
        let s: const Symbol& = p.symbols[symbol];
        let f = l.cells[head].frame as i64;
        if s.owner >= 0 && l.frame > 0 && f == l.frame && l.frames[l.frame].function_node == s.owner { return head; }
        if f == 0 && (s.flags & S_GLOBAL) != 0 { return head; }
    }
    let frame = life_frame_for(p, l, symbol);
    // Most symbols live in a single frame or were most recently used in this one.
    if head >= 0 && l.cells[head].frame == frame { return head; }
    // A symbol has one cell in a frame; its cells in every frame are also
    // chained from symbol_cells.
    life_cell_reserve(l);
    let mask = l.cell_slots.len - 1; var slot = life_frame_hash(symbol, frame, mask);
    loop {
        let found = l.cell_slots[slot] as i64;
        if found < 0 { break; }
        if l.cells[found].symbol == symbol && l.cells[found].frame == frame { return found; }
        slot = (slot + 1) & mask;
    }
    let saved = l.frame; l.frame = frame;
    let root = l.roots.len;
    var depth = life_depth(l, p.symbols[symbol].scope); if (p.symbols[symbol].flags & S_GLOBAL) != 0 { depth = 0; }
    l.roots.push(LifeRoot { symbol: symbol, frame: frame, type_id: p.symbols[symbol].type_id, depth: depth });
    l.frame = saved;
    let index = l.cells.len; l.cells.push(LifeCell { symbol: symbol as i32, frame: frame as i32, root: root as i32, parameter: (p.symbols[symbol].flags & S_PARAMETER) != 0, next_symbol: l.symbol_cells[symbol], next_frame: l.frames[frame].first_cell as i32 });
    if l.cells[index].parameter {
        l.cells[index].next_parameter = l.frames[frame].first_parameter as i32;
        l.frames[frame].first_parameter = index;
    }
    let type_id = p.symbols[symbol].type_id; let reference = life_tf_is_ref(p, l, type_id);
    var element = -1; if reference { element = p.types[type_id].element; }
    if (index & 63) == 0 { l.holder_bits.push(0); }
    // Cells made before types freeze stay candidates for the regular type check.
    if !l.types_frozen || reference || life_tf_holds(p, l, type_id) {
        // Validation snapshots follow the same newest-first order as first_cell.
        // Before types freeze, keep every cell eligible for the later check.
        if !l.types_frozen || (p.symbols[symbol].flags & (S_CAPTURE | S_GLOBAL)) != 0 {
            l.cells[index].next_capture_input = l.frames[frame].first_capture_input as i32;
            l.frames[frame].first_capture_input = index;
        }
        let one: u64 = 1; l.holder_bits[index >> 6] |= one << (index & 63);
    }
    l.cell_keys.push(LifeCellKey { root: root as i32, depth: depth as i32, type_id: type_id as i32, element: element as i32, global: (p.symbols[symbol].flags & S_GLOBAL) != 0 });
    if (p.symbols[symbol].flags & S_GLOBAL) != 0 { l.global_cells.push(index); l.global_epoch += 1; }
    if frame == 0 && depth > 0 { l.deep_cells.push(index); }
    l.cell_slots[slot] = index as i32;
    l.symbol_cells[symbol] = index as i32; l.frames[frame].first_cell = index;
    return index;
}
// Whether the body being evaluated can reach a cell: inside a class-keyed
// frame, only the cells of that island and the globals.
inline fn life_visible(l: Lifetimes&, cell: i64) -> bool {
    return l.island == 0 || l.cell_keys[cell].global || l.frames[l.cells[cell].frame].island == l.island;
}
fn life_set_live(l: Lifetimes&, cell: i64, live: bool) {
    if l.cells[cell].live == live { return; }
    let ck: const LifeCellKey& = l.cell_keys[cell];
    if ck.global { l.global_epoch += 1; if live { l.global_live_count += 1; } else { l.global_live_count -= 1; } }
    if !l.discovery && l.cells[cell].frame == 0 { l.global_live_epoch += 1; }
    l.cell_clock += 1;
    let d = ck.depth as i64;
    if d >= 0 && d < 64 { l.depth_clock[d] = l.cell_clock; }
    l.cells[cell].live = live;
    let word = cell >> 6;
    while l.live_bits.len <= word { l.live_bits.push(0); l.live_holder_bits.push(0); l.local_holder_bits.push(0); }
    while 64 * l.live_words.len < l.live_bits.len { l.live_words.push(0); l.live_holder_words.push(0); l.local_holder_words.push(0); }
    let one: u64 = 1; let bit = one << (cell & 63); let group_bit = one << (word & 63);
    let is_holder = word < l.holder_bits.len && (l.holder_bits[word] & bit) != 0;
    if live {
        l.live_bits[word] |= bit; l.live_words[word >> 6] |= group_bit;
        if is_holder {
            l.live_holder_bits[word] |= bit; l.live_holder_words[word >> 6] |= group_bit;
            if !ck.global { l.local_holder_bits[word] |= bit; l.local_holder_words[word >> 6] |= group_bit; }
            if !l.discovery { l.holder_grow_epoch += 1; }
        }
    } else {
        l.live_bits[word] &= ~bit;
        if l.live_bits[word] == 0 { l.live_words[word >> 6] &= ~group_bit; }
        if is_holder {
            l.live_holder_bits[word] &= ~bit;
            if l.live_holder_bits[word] == 0 { l.live_holder_words[word >> 6] &= ~group_bit; }
            if !ck.global {
                l.local_holder_bits[word] &= ~bit;
                if l.local_holder_bits[word] == 0 { l.local_holder_words[word >> 6] &= ~group_bit; }
            }
        }
    }
}
inline fn life_set_live_contents(l: Lifetimes&, root: i64, value: i64) {
    if l.roots[root].live_contents != value {
        l.roots[root].live_contents = value;
        l.held_epoch += 1;
        l.live_epoch += 1;
        if l.root_live_stamps.len <= root { l.root_live_stamps.resize(root + 1, 0); }
        l.live_contents_stamp += 1;
        l.root_live_stamps[root] = l.live_contents_stamp;
        if value != 0 { l.holder_grow_epoch += 1; } else { l.val_kill_epoch += 1; }
        if l.roots[root].frame == 0 && l.roots[root].class_frame < 0 { l.global_live_epoch += 1; }
    }
}
inline fn life_set_live_refs(l: Lifetimes&, cell: i64, value: i64) {
    let old = l.cells[cell].live_refs as i64;
    if old != value {
        l.cells[cell].live_refs = value as i32;
        l.live_epoch += 1;
        if value != 0 { l.holder_grow_epoch += 1; }
        if old != 0 && (value == 0 || !life_subset(l, old, value)) { l.val_kill_epoch += 1; }
        if l.cells[cell].frame == 0 { l.global_live_epoch += 1; }
    }
}
inline fn life_clear_kills(l: Lifetimes&, root: i64) {
    if l.roots[root].first_kill != -1 {
        l.roots[root].first_kill = -1;
        l.live_epoch += 1;
        l.holder_grow_epoch += 1;
        if l.roots[root].frame == 0 && l.roots[root].class_frame < 0 { l.global_live_epoch += 1; }
    }
}
fn life_set_refs(l: Lifetimes&, cell: i64, refs: i64) {
    let r32 = refs as i32;
    if l.cells[cell].refs == r32 { return; }
    let ck: const LifeCellKey& = l.cell_keys[cell];
    if ck.global { l.global_epoch += 1; l.global_refs_epoch += 1; }
    if l.cells[cell].parameter { l.frames[l.cells[cell].frame].parameter_version += 1; }
    l.cells[cell].refs = r32;
    l.cell_clock += 1;
    let d = ck.depth as i64;
    if d >= 0 && d < 64 { l.depth_clock[d] = l.cell_clock; }
}
// The first live cell after cell `after` in index order, or -1.
fn life_next_live(l: Lifetimes&, after: i64) -> i64 {
    let cell = after + 1; var word = cell >> 6;
    if word >= l.live_bits.len { return -1; }
    var all: u64 = 0; all = ~all;
    let bits = l.live_bits[word] & (all << (cell & 63));
    if bits != 0 { return (word << 6) + ctz(bits); }
    word += 1; var group = word >> 6;
    if group >= l.live_words.len { return -1; }
    var words = l.live_words[group] & (all << (word & 63));
    loop {
        if words != 0 { let found = (group << 6) + ctz(words); return (found << 6) + ctz(l.live_bits[found]); }
        group += 1;
        if group >= l.live_words.len { return -1; }
        words = l.live_words[group];
    }
    return -1;
}
// Life cells that can hold a reference, among those currently live.
fn life_next_holder(l: Lifetimes&, after: i64) -> i64 {
    let cell = after + 1; var word = cell >> 6;
    if word >= l.live_holder_bits.len { return -1; }
    var all: u64 = 0; all = ~all;
    let bits = l.live_holder_bits[word] & (all << (cell & 63));
    if bits != 0 { return (word << 6) + ctz(bits); }
    word += 1; var group = word >> 6;
    if group >= l.live_holder_words.len { return -1; }
    var words = l.live_holder_words[group] & (all << (word & 63));
    loop {
        if words != 0 { let found = (group << 6) + ctz(words); return (found << 6) + ctz(l.live_holder_bits[found]); }
        group += 1;
        if group >= l.live_holder_words.len { return -1; }
        words = l.live_holder_words[group];
    }
    return -1;
}
fn life_next_local_holder(l: Lifetimes&, after: i64) -> i64 {
    let cell = after + 1; var word = cell >> 6;
    if word >= l.local_holder_bits.len { return -1; }
    var all: u64 = 0; all = ~all;
    let bits = l.local_holder_bits[word] & (all << (cell & 63));
    if bits != 0 { return (word << 6) + ctz(bits); }
    word += 1; var group = word >> 6;
    if group >= l.local_holder_words.len { return -1; }
    var words = l.local_holder_words[group] & (all << (word & 63));
    loop {
        if words != 0 { let found = (group << 6) + ctz(words); return (found << 6) + ctz(l.local_holder_bits[found]); }
        group += 1;
        if group >= l.local_holder_words.len { return -1; }
        words = l.local_holder_words[group];
    }
    return -1;
}
fn life_note_temp(p: Program&, l: Lifetimes&, type_id: i64) {
    if l.discovery || life_cached_size_class(p, l, type_id) == 0 { return; }
    let value = LifeTemp { frame: l.frame };
    if l.temp_count == l.temps.len { l.temps.push(value); } else { l.temps[l.temp_count] = value; }
    l.temp_count += 1;
}
fn life_temporary(p: Program&, l: Lifetimes&, node: i64) -> i64 {
    // A node has one temporary in a frame; its temporaries in every frame
    // are also chained from node_roots.
    if 2 * (l.temporaries + 1) > l.temp_slots.len {
        var size: i64 = 64; while size < 4 * (l.temporaries + 1) { size <<= 1; }
        l.temp_slots.clear(); l.temp_slots.resize(size, -1);
        for index in 0..l.roots.len {
            let root: const LifeRoot& = l.roots[index];
            if !root.temporary { continue; }
            var slot = life_frame_hash(root.node, root.frame, size - 1);
            while l.temp_slots[slot] >= 0 { slot = (slot + 1) & (size - 1); }
            l.temp_slots[slot] = index as i32;
        }
    }
    let mask = l.temp_slots.len - 1; var slot = life_frame_hash(node, l.frame, mask);
    loop {
        let found = l.temp_slots[slot] as i64;
        if found < 0 { break; }
        if l.roots[found].node == node && l.roots[found].frame == l.frame { life_note_temp(p, l, l.roots[found].type_id); return life_root_set(l, found); }
        slot = (slot + 1) & mask;
    }
    let root = l.roots.len;
    l.roots.push(LifeRoot { frame: l.frame, node: node, type_id: p.nodes[node].type_id, depth: life_depth(l, l.scope) + 1, temporary: true, next_node: l.node_roots[node] as i64 });
    l.temp_slots[slot] = root as i32; l.temporaries += 1;
    l.node_roots[node] = root as i32; life_note_temp(p, l, p.nodes[node].type_id);
    return life_root_set(l, root);
}

// Ordinary bound keys come from i32 alternatives. This distinct key adds
// each root's immutable lexical depth when binding a parameter.
let LIFE_PARAMETER_BOUND: i64 = -2;
fn life_bound(l: Lifetimes&, sources: i64, depth: i64) -> i64 {
    // With class-keyed frames in use no bound is added: a class root's rank
    // is what a read through a parameter is held to there, and the same
    // roots under every caller's depth were most of the sets a large
    // program made.
    if depth == 0 || sources == 0 || l.class_frames > 0 { return sources; }
    if l.sets[sources].bound_depth == depth { return l.sets[sources].bound_result; }
    let first = l.sets[sources].first as i64; let count = l.sets[sources].count as i64;
    let start = l.scratch.len;
    for i in 0..count {
        var alt = l.alts[first + i]; var bound = depth;
        if bound == LIFE_PARAMETER_BOUND { bound = l.roots[alt.root].depth; }
        if bound != 0 && bound > alt.bound { alt.bound = bound as i32; }
        l.scratch.push(alt);
    }
    let result = life_list_set(l, start, true);
    l.scratch.resize(start);
    l.sets[sources].bound_depth = depth as i32; l.sets[sources].bound_result = result as i32;
    return result;
}
inline fn life_push_dep_root(l: Lifetimes&, r: i64) {
    let n = l.dep_root_stack.len;
    if n <= l.dep_root_floor || l.dep_root_stack[n - 1] != r { l.dep_root_stack.push(r); }
}
inline fn life_note_places_read(l: Lifetimes&, places: i64) {
    if !l.discovery || l.frame <= 0 || places == 0 { return; }
    if l.island == 0 {
        var at = l.sets[places].first;
        while at >= 0 {
            life_push_dep_root(l, l.alts[at].root as i64);
            at = l.alts[at].next;
        }
    } else if (l.sets[places].flags & 2) != 0 {
        let first = l.sets[places].first as i64; let count = l.sets[places].count as i64;
        for i in 0..count {
            let r = l.alts[first + i].root as i64;
            if r > 0 && l.roots[r].frame <= 0 && l.roots[r].class_frame < 0 { life_push_dep_root(l, r); }
        }
    }
}
fn life_contents_plain(l: Lifetimes&, places: i64) -> i64 {
    // The joins below depend only on the places and on what each root holds,
    // and a list made again is the same set (life_list_set): an answer holds
    // until one of the roots' contents changes. A single place needs no join.
    let first = l.sets[places].first;
    if first < 0 { return 0; }
    if l.chk_dep_recording {
        let cnt = l.sets[places].count as i64;
        for ri in 0..cnt {
            let r = l.alts[(first as i64) + ri].root;
            if r != 0 { l.chk_dep_stack.push(r); }
        }
    }
    if l.discovery && l.frame > 0 { life_note_places_read(l, places); }
    if l.sets[places].count == 1 {
        let alt: const LifeAlt& = l.alts[first];
        let held = life_bound(l, l.roots[alt.root].contents, alt.bound);
        if held == 0 || l.sets[held].count != 0 { return held; }
        return 0;
    }
    if l.contents_memo.len == 0 { l.contents_memo.resize(64, LifeContents {}); }
    if l.root_stamps.len < l.roots.len { l.root_stamps.resize(l.roots.len, 0); }
    var h: u64 = (places as! u64) * 11400714819323198485; h ^= h >> 29;
    let slot = (h & ((l.contents_memo.len - 1) as! u64)) as i64;
    let memo = l.contents_memo[slot];
    if memo.places == places {
        var same = true; var at = l.sets[places].first;
        while at >= 0 { if l.root_stamps[l.alts[at].root] > memo.stamp { same = false; break; } at = l.alts[at].next; }
        if same { return memo.set; }
    }
    var result = LifeBuild {}; var at = l.sets[places].first;
    while at >= 0 { let alt = l.alts[at]; life_build_add(l, result, life_bound(l, l.roots[alt.root].contents, alt.bound)); at = alt.next; }
    let set = life_build_end(l, result);
    l.contents_memo[slot] = LifeContents { places: places, stamp: l.contents_stamp, set: set };
    // Entries keep their slots when the table grows, as joins do.
    l.contents_recorded++;
    if l.contents_recorded > 4 * l.contents_memo.len && l.contents_memo.len < 1048576 { l.contents_memo.resize(4 * l.contents_memo.len, LifeContents {}); l.contents_recorded = 0; }
    return set;
}
// What a frame's body has stored through its other class roots that may be
// the storage class root `root` stands for (upstream NoteSlotStore:
// "distinct parameter classes need not be disjoint"). Whether two may be is
// asked of the call (query 4).
let LIFE_STORED_ROOTS: i64 = 256;
fn life_class_stores(p: Program&, l: Lifetimes&, root: i64) -> i64 {
    let owner = l.roots[root].class_frame; var out = 0;
    if !l.frames[owner].active || l.roots[root].class_empty { return 0; }
    // Past LIFE_STORED_ROOTS class roots stored through, every one is taken
    // to be any other: asking of each pair costs more than it tells.
    if l.frames[owner].stored_count > LIFE_STORED_ROOTS { return l.frames[owner].all_stored; }
    if l.roots[root].stores_version == l.frames[owner].stored_version { return l.roots[root].stores; }
    let version = l.frames[owner].stored_version;
    var other = l.frames[owner].stored_first;
    while other >= 0 {
        if other != root && !(l.roots[root].class_one && l.roots[other].class_one) {
            var low = l.roots[root].class_index; var high = l.roots[other].class_index;
            if low > high { let swap = low; low = high; high = swap; }
            if life_class_query_roots(p, l, owner, low, 4, high, false) { out = life_join(l, out, l.roots[other].stored); }
        }
        other = l.roots[other].stored_next;
    }
    l.roots[root].stores = out; l.roots[root].stores_version = version;
    return out;
}
// What reading the places finds beyond what their roots hold themselves: a
// class root's storage also holds what the body stored through any class of
// its frame, and inside an island storage outside it (a global, static data)
// holds what the island stored of its class roots anywhere outside.
fn life_overlay(p: Program&, l: Lifetimes&, places: i64, held: i64) -> i64 {
    if (l.sets[places].flags & 6) == 0 { return held; }
    var out = held; var outside = false; var bound: i64 = 0; var all_typed = true; var at = l.sets[places].first;
    while at >= 0 {
        let alt = l.alts[at]; at = alt.next; let owner = l.roots[alt.root].class_frame;
        if owner >= 0 {
            if l.frames[owner].stored_first >= 0 {
                if l.chk_dep_recording && owner != l.chk_island { l.chk_dep_overflow = true; }
                out = life_join(l, out, life_class_stores(p, l, alt.root));
            }
        }
        else if alt.root != 0 && l.roots[alt.root].frame <= 0 {
            outside = true; if alt.bound > bound { bound = alt.bound; }
                if l.class_frames > 0 { bound = 0; }
            if !alt.exact || alt.byteview || alt.root == 0 || l.roots[alt.root].type_id < 0 || life_is_ref(p, l.roots[alt.root].type_id) { all_typed = false; }
        }
    }
    var extra = 0;
    if outside && l.island > 0 && l.frames[l.island].class_stored != 0 { extra = life_join(l, extra, life_bound(l, l.frames[l.island].class_stored, bound)); }
    if outside && l.globals_root >= 0 {
        if l.chk_dep_recording { l.chk_dep_stack.push(l.globals_root as i32); }
        if l.discovery && l.frame > 0 { life_push_dep_root(l, l.globals_root); }
        var landed = l.roots[l.globals_root].contents; if !l.discovery { landed = l.roots[l.globals_root].live_contents; }
        if landed != 0 { extra = life_join(l, extra, life_bound(l, landed, bound)); }
    }
    if extra != 0 {
        if all_typed {
            var prev_ty: i64 = -1;
            at = l.sets[places].first;
            while at >= 0 {
                let alt = l.alts[at]; at = alt.next;
                if l.roots[alt.root].class_frame < 0 && l.roots[alt.root].frame <= 0 {
                    let raw_ty = l.roots[alt.root].type_id;
                    let ty = if l.types_frozen && l.nodes_prepared && raw_ty >= 0 { l.type_exact_canon[raw_ty] as i64 } else { raw_ty };
                    if ty != prev_ty && life_tf_holds(p, l, ty) { prev_ty = ty; out = life_join(l, out, life_referable(p, l, extra, ty)); }
                }
            }
        } else {
            out = life_join(l, out, extra);
        }
    }
    return out;
}
fn life_contents(p: Program&, l: Lifetimes&, places: i64) -> i64 {
    let held = life_contents_plain(l, places);
    if l.class_frames == 0 { return held; }
    return life_fold(l, life_overlay(p, l, places, held));
}
// Every change of a root's contents goes through here (life_contents).
fn life_set_contents(l: Lifetimes&, root: i64, contents: i64) {
    if l.roots[root].contents != contents { l.held_epoch += 1; }
    l.roots[root].contents = contents;
    if l.root_stamps.len <= root { l.root_stamps.resize(root + 1, 0); }
    l.contents_stamp += 1; l.root_stamps[root] = l.contents_stamp;
}
fn life_live_contents(p: Program&, l: Lifetimes&, places: i64) -> i64 {
    let first = l.sets[places].first;
    if first < 0 { return 0; }
    if l.chk_dep_recording {
        let cnt = l.sets[places].count as i64;
        for ri in 0..cnt {
            let r = l.alts[(first as i64) + ri].root;
            if r != 0 { l.chk_dep_stack.push(r); }
        }
    }
    if l.sets[places].count == 1 {
        let alt: const LifeAlt& = l.alts[first];
        var held = life_bound(l, l.roots[alt.root].live_contents, alt.bound);
        if held != 0 && l.sets[held].count == 0 { held = 0; }
        if l.class_frames == 0 { return held; }
        return life_fold(l, life_overlay(p, l, places, held));
    }
    var result = LifeBuild {}; var at = first;
    while at >= 0 { let root = l.alts[at].root; let bound = l.alts[at].bound; at = l.alts[at].next; life_build_add(l, result, life_bound(l, l.roots[root].live_contents, bound)); }
    let held = life_build_end(l, result);
    if l.class_frames == 0 { return held; }
    return life_fold(l, life_overlay(p, l, places, held));
}
fn life_only_static(l: Lifetimes&, set: i64) -> bool {
    if set == 0 { return true; }
    let first = l.sets[set].first as i64; let count = l.sets[set].count as i64;
    for i in 0..count { if l.alts[first + i].root != 0 { return false; } }
    return true;
}
fn life_value_roots(p: Program&, value: const LifeValue&) -> i64 {
    if value.type_id >= 0 && p.types[value.type_id].kind == TY_REF && p.types[value.type_id].length_storage >= 0 { return 0; }
    if life_is_ref(p, value.type_id) { return value.refs; }
    return value.contents;
}
fn life_build_gs_elems(p: Program&, l: Lifetimes&, co: i64) {
    l.outer_type_seen_gen += 1;
    let gen = l.outer_type_seen_gen;
    let wbase = l.type_work.len;
    l.outer_type_seen[co] = gen;
    l.type_work.push(co as i32);
    let start = l.gs_elems.len;
    var at = wbase;
    while at < l.type_work.len {
        let t: const Type& = p.types[l.type_work[at] as i64]; at += 1;
        if t.kind == TY_ARRAY {
            if t.array_kind == A_GROWSHRINK {
                if t.element >= 0 { l.gs_elems.push(l.type_exact_canon[t.element]); }
                else { l.gs_elems.push(-1); }
            }
            if t.element >= 0 {
                let elem = l.type_exact_canon[t.element] as i64;
                if l.outer_type_seen[elem] != gen { l.outer_type_seen[elem] = gen; l.type_work.push(elem as i32); }
            }
        } else if t.kind == TY_STRUCT || t.kind == TY_ENUM {
            var field = t.first;
            while field >= 0 {
                let ft = p.nodes[field].type_id;
                if ft >= 0 {
                    let fe = l.type_exact_canon[ft] as i64;
                    if l.outer_type_seen[fe] != gen { l.outer_type_seen[fe] = gen; l.type_work.push(fe as i32); }
                }
                field = p.nodes[field].next;
            }
        }
    }
    l.type_work.resize(wbase);
    if l.gs_elems.len - start > 1 {
        l.gs_elems[start..l.gs_elems.len].sort();
        var kept = start;
        for i in start..l.gs_elems.len {
            if i == start || l.gs_elems[i] != l.gs_elems[kept - 1] { l.gs_elems[kept] = l.gs_elems[i]; kept += 1; }
        }
        l.gs_elems.resize(kept);
    }
    l.gs_start[co] = start as i32;
    l.gs_count[co] = (l.gs_elems.len - start) as i32;
}
fn life_gs_contains(p: Program&, l: Lifetimes&, raw_owner: i64, raw_pointee: i64, byteview: bool) -> bool {
    if raw_owner < 0 { return false; }
    if l.types_frozen && l.nodes_prepared {
        let co = l.type_exact_canon[raw_owner] as i64;
        var cnt = l.gs_count[co] as i64;
        if cnt < 0 { life_build_gs_elems(p, l, co); cnt = l.gs_count[co] as i64; }
        if cnt == 0 { return false; }
        if byteview { return true; }
        if raw_pointee < 0 { return false; }
        let start = l.gs_start[co] as i64;
        for i in start..start + cnt {
            let elem = l.gs_elems[i] as i64;
            if elem >= 0 && life_contains(p, l, elem, raw_pointee) { return true; }
        }
        return false;
    }
    return life_gs_contains_walk(p, l, raw_owner, raw_pointee, byteview);
}
fn life_gs_contains_walk(p: Program&, l: Lifetimes&, owner: i64, pointee: i64, byteview: bool) -> bool {
    let base = l.type_work.len; l.type_work.push(owner as i32); var at = base; var answer = false;
    while at < l.type_work.len {
        let t: const Type& = p.types[l.type_work[at] as i64]; at += 1;
        if t.kind == TY_ARRAY {
            if t.array_kind == A_GROWSHRINK && (byteview || life_contains(p, l, t.element, pointee)) { answer = true; break; }
            if t.element >= 0 {
                let elem = t.element as i32;
                var seen = false; for wi in base..l.type_work.len { if l.type_work[wi] == elem { seen = true; break; } }
                if !seen { l.type_work.push(elem); }
            }
        } else if t.kind == TY_STRUCT || t.kind == TY_ENUM {
            var field = t.first;
            while field >= 0 {
                let ft = p.nodes[field].type_id; var seen = ft < 0;
                let ft32 = ft as i32;
                if !seen { for wi in base..l.type_work.len { if l.type_work[wi] == ft32 { seen = true; break; } } }
                if !seen { l.type_work.push(ft32); }
                field = p.nodes[field].next;
            }
        }
    }
    l.type_work.resize(base);
    return answer;
}
// The storage an alternative names: a root owner's component, or its root.
inline fn life_alt_type(p: Program&, l: Lifetimes&, alt: const LifeAlt&) -> i64 {
    if alt.component >= 0 { return p.nodes[alt.component].type_id; }
    return l.roots[alt.root].type_id;
}
fn life_gs_value(p: Program&, l: Lifetimes&, value: const LifeValue&) -> bool {
    if value.type_id < 0 { return false; }
    let t: const Type& = p.types[value.type_id]; let sources = life_value_roots(p, value);
    var at = l.sets[sources].first;
    while at >= 0 {
        let alt = l.alts[at]; let root: const LifeRoot& = l.roots[alt.root];
        let storage = life_alt_type(p, l, alt);
        // What a class root stands for decides, not a type of its own.
        let class_root = l.class_frames > 0 && alt.component < 0 && root.class_frame >= 0;
        if alt.root == l.globals_root && !alt.slotread && life_is_ref(p, value.type_id) && life_globals_gs(p, l, t.element, alt.byteview) { return true; }
        if class_root && !alt.slotread {
            if life_is_ref(p, value.type_id) { if life_class_query(p, l, alt.root, 0, t.element, alt.byteview) { return true; } }
            else if life_class_query(p, l, alt.root, 1, value.type_id, alt.byteview) { return true; }
        }
        if !class_root && !alt.slotread && life_is_ref(p, value.type_id) && life_gs_contains(p, l, storage, t.element, alt.byteview) { return true; }
        if !class_root && !alt.slotread && !life_is_ref(p, value.type_id) {
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
            if l.discovery && l.frame > 0 {
                if l.island == 0 || alt.root > 0 && l.roots[alt.root].frame <= 0 && l.roots[alt.root].class_frame < 0 { life_push_dep_root(l, alt.root as i64); }
            }
            var inner = l.sets[root.contents].first;
            while inner >= 0 {
                let view = l.alts[inner];
                if !view.slotread && life_alt_gs(p, l, view, p.types[t.element].element) { return true; }
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
    while p.type_holds.len < p.types.len { p.type_holds.push(0); }
    var shift: i64 = 2; if include_pool { shift = 4; }
    let known = (p.type_holds[ty] >> shift) & 3;
    if known != 0 { return known == 2; }
    var work: i64[>..] = [ty]; var at = 0; var answer = false;
    while at < work.len {
        let cur = work[at]; at += 1;
        let ck = (p.type_holds[cur] >> shift) & 3;
        if ck != 0 { if ck == 2 { answer = true; break; } continue; }
        let t: const Type& = p.types[cur];
        if t.kind == TY_REF { if t.length_storage >= 0 && (t.pool < 0 || include_pool) { answer = true; break; } continue; }
        if t.kind == TY_ARRAY && t.element >= 0 {
            var seen = false; for old in work { if old == t.element { seen = true; break; } }
            if !seen { work.push(t.element); }
        }
        if t.kind == TY_STRUCT || t.kind == TY_ENUM || t.kind == TY_TUPLE {
            var field = t.first;
            while field >= 0 {
                let ft = p.nodes[field].type_id; var seen = ft < 0; for old in work { if old == ft { seen = true; break; } }
                if !seen { work.push(ft); } field = p.nodes[field].next;
            }
        }
    }
    if answer { p.type_holds[ty] |= 2 << shift; } else { p.type_holds[ty] |= 1 << shift; }
    return answer;
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
            // default and from_bytes build their value results at the receiver.
            if (symbol.flags & S_BUILTIN) != 0 && (symbol.index == 14 || symbol.index == 18) { continue; }
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
        if life_tf_rel(p, l, head) { return false; }
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
        if n.left >= 0 { work.push(n.left); }
        if n.right >= 0 { work.push(n.right); }
        if n.third >= 0 { work.push(n.third); }
    }
    return true;
}
inline fn life_copy(p: Program&, l: Lifetimes&, node: i64, ty: i64, target: i64 = -1) {
    if l.discovery || node < 0 || ty < 0 { return; }
    let tf = l.type_flags[ty];
    if (tf & TF_L_REF) != 0 || (tf & TF_L_REL) == 0 { return; }
    life_copy_slow(p, l, node, ty, target);
}
fn life_copy_slow(p: Program&, l: Lifetimes&, node: i64, ty: i64, target: i64) {
    if life_fresh(p, node) { return; }
    if target >= 0 && life_relative_named(p, l, node, ty, target) { return; }
    life_error(p, l, node, "copying a value containing self-relative references is unsupported; construct it in its destination");
}

inline fn life_receive(p: Program&, l: Lifetimes&, node: i64, value: const LifeValue&, expected: i64) {
    if l.discovery || expected < 0 { return; }
    if value.relative_roots == 0 && value.tuple < 0 && (l.type_flags[expected] & TF_L_REL) == 0 { return; }
    life_receive_slow(p, l, node, value, expected);
}
recursive fn life_receive_slow(p: Program&, l: Lifetimes&, node: i64, value: const LifeValue&, expected: i64) {
    if expected < 0 { return; }
    if value.relative_roots != 0 && value.type_id >= 0 && p.types[value.type_id].kind == TY_ARRAY && p.types[expected].kind == TY_ARRAY {
        if p.types[value.type_id].array_kind != p.types[expected].array_kind || p.types[value.type_id].count != p.types[expected].count {
            life_error(p, l, node, "a result containing relative links to its destination cannot change representation");
        }
    }
    if value.tuple >= 0 && p.types[expected].kind == TY_TUPLE {
        var item = value.tuple; var component = p.types[expected].first;
        while item >= 0 && component >= 0 {
            life_receive_slow(p, l, node, l.items[item].value, p.nodes[component].type_id);
            item = l.items[item].next; component = p.nodes[component].next;
        }
    } else if life_tf_is_ref(p, l, value.type_id) && !life_tf_is_ref(p, l, expected) && life_tf_rel(p, l, expected) {
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
fn life_push_future(l: Lifetimes&, node: i64, loop_scope: i64 = -1, last: i64 = -1) {
    // Only validation checks whether a later expression still uses a cell.
    if l.discovery || node < 0 { return; }
    let entry = LifeFuture { node: node, frame: l.frame, scope: l.scope, loop_scope: loop_scope, last: last };
    if l.future_count == l.futures.len { l.futures.push(entry); } else { l.futures[l.future_count] = entry; }
    l.future_count += 1;
}
fn life_hold(l: Lifetimes&, value: const LifeValue&, node: i64, kind: i64 = 0) {
    // Held operands are consulted when validating overlapping uses.
    if l.discovery { return; }
    // A kind-0 hold is only inspected by life_points_into, which is always false
    // for a value whose type is neither a reference/slice nor a reference holder.
    if kind == 0 && l.nodes_prepared && value.type_id >= 0 && value.type_id < l.type_flags.len &&
       (l.type_flags[value.type_id] & (TF_L_REF | TF_L_HOLDS)) == 0 { return; }
    if kind == 1 || kind == 2 { l.build_holds += 1; if kind == 2 { l.construct_holds += 1; } }
    else if kind == 7 { l.format_holds += 1; }
    let entry = LifeHold { value: value, node: node as i32, kind: kind as i32, frame: l.frame as i32 };
    if l.hold_count == l.holds.len { l.holds.push(entry); } else { l.holds[l.hold_count] = entry; }
    l.hold_count += 1;
}
inline fn life_pop_holds(l: Lifetimes&, target: i64) {
    while l.hold_count > target {
        l.hold_count -= 1;
        let k = l.holds[l.hold_count].kind;
        if k == 1 || k == 2 { l.build_holds -= 1; if k == 2 { l.construct_holds -= 1; } }
        else if k == 7 { l.format_holds -= 1; }
    }
}
inline fn life_read_child(l: Lifetimes&, work: i64[>..]&, node: i64) {
    if node < 0 || (l.visited[node] as i64) == l.visit { return; }
    l.visited[node] = l.visit as i32; work.push(node);
}
inline fn life_read_bucket(node: i64, symbol: i64, last: i64, count: i64) -> i64 {
    var h = (node as! u64) * 11400714819323198485 ^ (symbol as! u64) * 14029467366897019727 ^ (last as! u64) * 1099511628211;
    h ^= h >> 29; return (h & ((count - 1) as! u64)) as i64;
}
// life_reads for a captured binding, from body to body. Its walk over nodes
// goes on through every call but one into the function that owns the
// binding, and asks each node whether it names the binding. What the nodes
// of one stretch say, and which calls leave it, life_body has scanned once:
// the same bodies are reached here, each asked for the binding in the sorted
// list of those it names.
fn life_body_compute_trans_globals(p: Program&, l: Lifetimes&, b: i64) {
    if l.bodies[b].trans_global_count >= 0 { return; }
    let start = l.body_trans_globals.len;
    l.body_walks += 1; let walk = l.body_walks;
    let rbase = l.body_reached.len;
    l.bodies[b].seen = walk; l.body_reached.push(b);
    var at = rbase;
    while at < l.body_reached.len {
        let idx = l.body_reached[at]; at += 1;
        let body = l.bodies[idx];
        for g in body.globals..body.globals + body.global_count {
            let sym = l.body_globals[g];
            l.body_trans_globals.push(sym);
        }
        for call in body.calls..body.calls + body.call_count {
            let target = l.body_calls[call];
            let next = if target < l.node_body.len && l.node_body[target] >= 0 { l.node_body[target] as i64 } else { life_body_build(p, l, target) };
            if l.bodies[next].seen != walk {
                l.bodies[next].seen = walk;
                if l.bodies[next].trans_global_count >= 0 {
                    let ts = l.bodies[next].trans_globals; let te = ts + l.bodies[next].trans_global_count;
                    for g in ts..te { let sym = l.body_trans_globals[g]; l.body_trans_globals.push(sym); }
                } else if l.bodies[next].call_count == 0 {
                    let gs = l.bodies[next].globals; let ge = gs + l.bodies[next].global_count;
                    for g in gs..ge { let sym = l.body_globals[g]; l.body_trans_globals.push(sym); }
                } else {
                    l.body_reached.push(next);
                }
            }
        }
    }
    l.body_reached.resize(rbase);
    if l.body_trans_globals.len - start > 1 {
        l.body_trans_globals[start..l.body_trans_globals.len].sort();
        var kept = start;
        for i in start..l.body_trans_globals.len {
            if i == start || l.body_trans_globals[i] != l.body_trans_globals[kept - 1] {
                l.body_trans_globals[kept] = l.body_trans_globals[i]; kept += 1;
            }
        }
        l.body_trans_globals.resize(kept);
    }
    l.bodies[b].trans_globals = start;
    l.bodies[b].trans_global_count = l.body_trans_globals.len - start;
}
fn life_reads_captured(p: Program&, l: Lifetimes&, first: i64, symbol: i64) -> bool {
    let owner = p.symbols[symbol].owner; var barred: i64 = -1; if owner >= 0 { barred = p.nodes[owner].right; }
    l.body_walks += 1; let walk = l.body_walks;
    let rbase = l.body_reached.len;
    l.bodies[first].seen = walk; l.body_reached.push(first);
    var at = rbase; var found = false;
    while at < l.body_reached.len {
        let body = l.bodies[l.body_reached[at]]; at += 1;
        var low = body.named; var high = body.named + body.named_count;
        while low < high {
            let middle = (low + high) / 2; let value = l.body_captures[middle];
            if value == symbol { found = true; break; }
            if value < symbol { low = middle + 1; } else { high = middle; }
        }
        if found { break; }
        for call in body.calls..body.calls + body.call_count {
            let target = l.body_calls[call];
            if target == barred { continue; }
            let next = if target < l.node_body.len && l.node_body[target] >= 0 { l.node_body[target] as i64 } else { life_body_build(p, l, target) };
            if l.bodies[next].seen != walk { l.bodies[next].seen = walk; l.body_reached.push(next); }
        }
    }
    l.body_reached.resize(rbase);
    return found;
}
fn life_reads_global(p: Program&, l: Lifetimes&, first: i64, symbol: i64) -> bool {
    if l.bodies[first].call_count == 0 {
        var low = l.bodies[first].globals; var high = low + l.bodies[first].global_count;
        while low < high {
            let middle = (low + high) >> 1; let value = l.body_globals[middle];
            if value == symbol { return true; }
            if value < symbol { low = middle + 1; } else { high = middle; }
        }
        return false;
    }
    if l.bodies[first].trans_global_count < 0 { life_body_compute_trans_globals(p, l, first); }
    var low = l.bodies[first].trans_globals; var high = low + l.bodies[first].trans_global_count;
    while low < high {
        let middle = (low + high) >> 1; let value = l.body_trans_globals[middle];
        if value == symbol { return true; }
        if value < symbol { low = middle + 1; } else { high = middle; }
    }
    return false;
}
fn life_reads_rehash(l: Lifetimes&) {
    var count: i64 = 1024; while 2 * count <= l.reads.len { count <<= 1; }
    l.read_heads.clear(); l.read_heads.resize(count, -1);
    for index in 0..l.reads.len {
        let r: const LifeRead& = l.reads[index];
        let slot = life_read_bucket(r.node as i64, r.symbol as i64, r.last as i64, count);
        l.reads[index].next = l.read_heads[slot]; l.read_heads[slot] = index as i32;
    }
}
fn life_reads_miss(p: Program&, l: Lifetimes&, node: i64, symbol: i64, bucket: i64, last: i64 = -1) -> bool {
    var answer = false;
    if (p.symbols[symbol].flags & S_CAPTURE) != 0 { answer = life_reads_captured(p, l, life_body_span(p, l, node, last), symbol); }
    else if (p.symbols[symbol].flags & S_GLOBAL) != 0 { answer = life_reads_global(p, l, life_body_span(p, l, node, last), symbol); }
    else {
        if l.visited.len < p.nodes.len { l.visited.resize(p.nodes.len, 0); }
        l.visit += 1;
        let wbase = l.body_work.len;
        life_read_child(l, l.body_work, node);
        var at = wbase;
        while at < l.body_work.len {
            let current = l.body_work[at]; at += 1; let n: const Node& = p.nodes[current];
            if n.kind == N_NAME && n.symbol == symbol { answer = true; break; }
            if current != last { life_read_child(l, l.body_work, n.next); }
            if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE || n.kind == N_IMPORT { continue; }
            life_read_child(l, l.body_work, n.first);
            life_read_child(l, l.body_work, n.left);
            life_read_child(l, l.body_work, n.right);
            life_read_child(l, l.body_work, n.third);
        }
        l.body_work.resize(wbase);
    }
    let index = l.reads.len;
    l.reads.push(LifeRead { node: node as i32, last: last as i32, symbol: symbol as i32, next: l.read_heads[bucket], answer: answer });
    l.read_heads[bucket] = index as i32;
    return answer;
}
fn life_reads(p: Program&, l: Lifetimes&, node: i64, symbol: i64, last: i64 = -1) -> bool {
    if node < 0 { return false; }
    // Two cached answers per bucket at most, on average.
    if 2 * l.read_heads.len <= l.reads.len { life_reads_rehash(l); }
    let bucket = life_read_bucket(node, symbol, last, l.read_heads.len);
    let n32 = node as i32; let s32 = symbol as i32; let l32 = last as i32;
    var cached = l.read_heads[bucket] as i64;
    while cached >= 0 {
        let q: const LifeRead& = l.reads[cached];
        if q.node == n32 && q.symbol == s32 && q.last == l32 { return q.answer; }
        cached = q.next as i64;
    }
    return life_reads_miss(p, l, node, symbol, bucket, last);
}

// The walk life_reads makes from a node, following every call, reaches the
// nodes below it and those below the node of each called symbol, and so on.
// What the first part says is scanned once per start node, here; a walk then
// goes from body to body (life_body_walk) instead of over every node again.
fn life_body_build_one(p: Program&, l: Lifetimes&, start: i64, last: i64 = -1) -> i64 {
    let already = l.node_body[start] as i64;
    if last < 0 && already >= 0 { return already; }
    var body = LifeBody { start: start, globals: l.body_globals.len, calls: l.body_calls.len, owners: l.body_owners.len, named: l.body_captures.len };
    if l.visited.len < p.nodes.len { l.visited.resize(p.nodes.len, 0); }
    l.visit += 1;
    let wbase = l.body_work.len;
    life_read_child(l, l.body_work, start);
    var at = wbase;
    while at < l.body_work.len {
        let current = l.body_work[at]; at += 1;
        let cached = l.node_body[current] as i64;
        if last < 0 && cached >= 0 {
            let cb = l.bodies[cached];
            if cb.captures {
                body.captures = true;
                for oi in cb.owners..cb.owners + cb.owner_count {
                    let owner = l.body_owners[oi]; var listed = false;
                    for k in body.owners..l.body_owners.len { if l.body_owners[k] == owner { listed = true; break; } }
                    if !listed { l.body_owners.push(owner); }
                }
                for ci in cb.named..cb.named + cb.named_count { let v = l.body_captures[ci]; l.body_captures.push(v); }
            }
            for gi in cb.globals..cb.globals + cb.global_count { let v = l.body_globals[gi]; l.body_globals.push(v); }
            for ki in cb.calls..cb.calls + cb.call_count { let v = l.body_calls[ki]; l.body_calls.push(v); }
            continue;
        }
        let n: const Node& = p.nodes[current];
        if n.kind == N_NAME && n.symbol >= 0 && n.symbol < p.symbols.len {
            let flags = p.symbols[n.symbol].flags;
            if (flags & S_CAPTURE) != 0 {
                body.captures = true; let owner = p.symbols[n.symbol].owner; var listed = false;
                for k in body.owners..l.body_owners.len { if l.body_owners[k] == owner { listed = true; break; } }
                if !listed { l.body_owners.push(owner); }
                l.body_captures.push(n.symbol);
            }
            if (flags & S_GLOBAL) != 0 { l.body_globals.push(n.symbol); }
        }
        if current != last { life_read_child(l, l.body_work, n.next); }
        if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE || n.kind == N_IMPORT { continue; }
        life_read_child(l, l.body_work, n.first);
        life_read_child(l, l.body_work, n.left);
        life_read_child(l, l.body_work, n.right);
        life_read_child(l, l.body_work, n.third);
        if n.kind == N_CALL && n.symbol >= 0 && (p.symbols[n.symbol].flags & S_BUILTIN) == 0 {
            let callee = p.symbols[n.symbol].node;
            if callee >= 0 && p.nodes[callee].right >= 0 { l.body_calls.push(p.nodes[callee].right); }
        }
    }
    l.body_work.resize(wbase);
    // Each called node once.
    l.body_calls[body.calls..l.body_calls.len].sort();
    var kept = body.calls;
    for index in body.calls..l.body_calls.len {
        if index == body.calls || l.body_calls[index] != l.body_calls[kept - 1] { l.body_calls[kept] = l.body_calls[index]; kept += 1; }
    }
    l.body_calls.resize(kept, 0);
    // Each captured binding once, in order.
    l.body_captures[body.named..l.body_captures.len].sort();
    var named = body.named;
    for index in body.named..l.body_captures.len {
        if index == body.named || l.body_captures[index] != l.body_captures[named - 1] { l.body_captures[named] = l.body_captures[index]; named += 1; }
    }
    l.body_captures.resize(named, 0); body.named_count = named - body.named;
    // Each global once, in order (for binary search in life_reads_global).
    l.body_globals[body.globals..l.body_globals.len].sort();
    var gkept = body.globals;
    for index in body.globals..l.body_globals.len {
        if index == body.globals || l.body_globals[index] != l.body_globals[gkept - 1] { l.body_globals[gkept] = l.body_globals[index]; gkept += 1; }
    }
    l.body_globals.resize(gkept, 0);
    body.global_count = gkept - body.globals; body.call_count = kept - body.calls; body.owner_count = l.body_owners.len - body.owners;
    let index = l.bodies.len; l.bodies.push(body);
    if last < 0 { l.node_body[start] = index as i32; }
    return index;
}
fn life_body_build(p: Program&, l: Lifetimes&, start: i64) -> i64 {
    if l.node_body.len < p.nodes.len { l.node_body.resize(p.nodes.len, -1); }
    let known = l.node_body[start] as i64;
    if known >= 0 { return known; }
    let cbase = l.body_work.len;
    var cur = start;
    while cur >= 0 && l.node_body[cur] < 0 {
        l.body_work.push(cur);
        cur = p.nodes[cur].next;
    }
    let chain_len = l.body_work.len - cbase;
    if chain_len > 16 {
        var idx = chain_len - 16;
        while idx > 0 {
            let cp = l.body_work[cbase + idx];
            life_body_build_one(p, l, cp);
            idx -= 16;
        }
    }
    l.body_work.resize(cbase);
    return life_body_build_one(p, l, start);
}
inline fn life_span_hash(start: i64, last: i64, mask: i64) -> i64 {
    var h = (start as! u64) * 11400714819323198485 ^ (last as! u64) * 14029467366897019727;
    h ^= h >> 29; return (h & (mask as! u64)) as i64;
}
fn life_span_rehash(l: Lifetimes&) {
    var size: i64 = 256; while size <= 2 * (l.span_count + 1) { size <<= 1; }
    var old: LifeSpanSlot[>..] = []; old.append(l.span_slots);
    l.span_slots.clear(); l.span_slots.resize(size, LifeSpanSlot {});
    let mask = size - 1;
    for s in old {
        if s.start < 0 { continue; }
        var slot = life_span_hash(s.start as i64, s.last as i64, mask);
        while l.span_slots[slot].start >= 0 { slot = (slot + 1) & mask; }
        l.span_slots[slot] = s;
    }
}
fn life_body_span(p: Program&, l: Lifetimes&, start: i64, last: i64) -> i64 {
    if last < 0 { return life_body(p, l, start); }
    if l.node_body.len < p.nodes.len { l.node_body.resize(p.nodes.len, -1); }
    if 2 * (l.span_count + 1) >= l.span_slots.len { life_span_rehash(l); }
    let mask = l.span_slots.len - 1;
    let s32 = start as i32; let l32 = last as i32;
    var slot = life_span_hash(start, last, mask);
    loop {
        let e: const LifeSpanSlot& = l.span_slots[slot];
        if e.start < 0 { break; }
        if e.start == s32 && e.last == l32 { return e.body as i64; }
        slot = (slot + 1) & mask;
    }
    let body = life_body_build_one(p, l, start, last);
    l.span_slots[slot] = LifeSpanSlot { start: s32, last: l32, body: body as i32 };
    l.span_count += 1;
    return body;
}
inline fn life_body(p: Program&, l: Lifetimes&, start: i64) -> i64 {
    if start < l.node_body.len {
        let known = l.node_body[start] as i64;
        if known >= 0 { return known; }
    }
    return life_body_build(p, l, start);
}
// A full walk records every reachable body once. A capture query can reuse
// an earlier answer and stop as soon as it finds a captured binding.
fn life_body_walk(p: Program&, l: Lifetimes&, start: i64, captures: bool) -> bool {
    if start < 0 { return false; }
    l.body_walks += 1; let walk = l.body_walks;
    let rbase = l.body_reached.len;
    let first = life_body(p, l, start); l.bodies[first].seen = walk; l.body_reached.push(first);
    var at = rbase;
    while at < l.body_reached.len {
        let index = l.body_reached[at]; at += 1;
        if captures && l.bodies[index].captures { return true; }
        let calls = l.bodies[index].calls; let count = l.bodies[index].call_count;
        for call in calls..calls + count {
            let callee = l.body_calls[call];
            if captures {
                let known = l.capture_reads[callee];
                if known == 1 { continue; }
                if known == 2 { return true; }
            }
            let next = life_body(p, l, callee);
            if l.bodies[next].seen != walk { l.bodies[next].seen = walk; l.body_reached.push(next); }
        }
    }
    // An exhausted walk proves the same negative answer for every body it visited.
    if captures {
        for ri in rbase..l.body_reached.len { l.capture_reads[l.bodies[l.body_reached[ri]].start] = 1; }
    }
    return false;
}
// Whether a function's body may read a captured binding: life_reads' walk,
// following every call, finds a name of one. A superset of what life_reads
// visits for any captured symbol, so false answers every such query.
fn life_reads_captures(p: Program&, l: Lifetimes&, function_node: i64) -> bool {
    if l.nodes_prepared && !l.has_captures { return false; }
    let start = p.nodes[function_node].right; if start < 0 { return false; }
    if l.capture_reads.len < p.nodes.len { l.capture_reads.resize(p.nodes.len, 0); }
    if l.capture_reads[start] != 0 { return l.capture_reads[start] == 2; }
    let rbase = l.body_reached.len;
    let answer = life_body_walk(p, l, start, true);
    l.body_reached.resize(rbase);
    if answer { l.capture_reads[start] = 2; }
    return answer;
}
// Whether every captured binding a function's body names, through any call,
// is owned by a function that body reaches, itself included: the frames
// that hold those bindings are then made inside its own evaluation, and a
// class-keyed frame of it reaches no frame of its callers.
fn life_contained(p: Program&, l: Lifetimes&, function_node: i64) -> bool {
    if l.nodes_prepared && !l.has_captures { return true; }
    if l.contained.len < p.nodes.len { l.contained.resize(p.nodes.len, 0); }
    if l.contained[function_node] != 0 { return l.contained[function_node] == 1; }
    let rbase = l.body_reached.len;
    life_body_walk(p, l, p.nodes[function_node].right, false);
    let walk = l.body_walks; var answer = true;
    for ri in rbase..l.body_reached.len {
        let index = l.body_reached[ri];
        let first = l.bodies[index].owners; let count = l.bodies[index].owner_count;
        for at in first..first + count {
            let owner = l.body_owners[at];
            if owner < 0 || p.nodes[owner].right < 0 { answer = false; break; }
            let body = life_body(p, l, p.nodes[owner].right);
            if l.bodies[body].seen != walk { answer = false; break; }
        }
        if !answer { break; }
    }
    l.body_reached.resize(rbase);
    l.contained[function_node] = 2; if answer { l.contained[function_node] = 1; }
    return answer;
}
// Cache the frame-zero cells reachable through calls. Snapshot their current
// references each time, since their contents can change between validations.
fn life_global_capture_span(p: Program&, l: Lifetimes&, function_node: i64) -> LifeCaptureSpan {
    let head = l.frames[0].first_capture_input;
    if head < 0 { return LifeCaptureSpan { count: 0 }; }
    if head != l.global_capture_head {
        // Cells are prepended. A different head invalidates every span into this list.
        l.global_capture_head = head; l.global_read_list.clear();
    }
    let body_index = if p.nodes[function_node].right < l.node_body.len && l.node_body[p.nodes[function_node].right] >= 0 { l.node_body[p.nodes[function_node].right] as i64 } else { life_body_build(p, l, p.nodes[function_node].right) };
    let known = l.bodies[body_index].global_inputs;
    if known.head == head { return known; }
    let first = l.global_read_list.len;
    if l.bodies[body_index].call_count == 0 {
        let gs = l.bodies[body_index].globals; let ge = gs + l.bodies[body_index].global_count;
        for at in gs..ge {
            let symbol = l.body_globals[at]; let cell = l.symbol_cells[symbol] as i64;
            let ty = p.symbols[symbol].type_id;
            if cell >= 0 && (life_is_ref(p, ty) || life_holds(p, ty)) { l.global_read_list.push(cell); }
        }
    } else {
        if l.bodies[body_index].trans_global_count < 0 { life_body_compute_trans_globals(p, l, body_index); }
        let ts = l.bodies[body_index].trans_globals; let te = ts + l.bodies[body_index].trans_global_count;
        for at in ts..te {
            let symbol = l.body_trans_globals[at]; let cell = l.symbol_cells[symbol] as i64;
            let ty = p.symbols[symbol].type_id;
            if cell >= 0 && (life_is_ref(p, ty) || life_holds(p, ty)) { l.global_read_list.push(cell); }
        }
    }
    // A capture local to a global initializer also belongs to frame 0.
    if !l.nodes_prepared || l.has_captures {
        var cell = head;
        while cell >= 0 {
            let symbol = l.cells[cell].symbol; let s: const Symbol& = p.symbols[symbol];
            if (s.flags & (S_GLOBAL | S_CAPTURE)) == S_CAPTURE && (life_is_ref(p, s.type_id) || life_holds(p, s.type_id)) &&
                life_reads(p, l, p.nodes[function_node].right, symbol) { l.global_read_list.push(cell); }
            cell = l.cells[cell].next_capture_input;
        }
    }
    l.global_read_list[first..l.global_read_list.len].sort();
    var kept = first;
    for at in first..l.global_read_list.len {
        if at == first || l.global_read_list[at] != l.global_read_list[kept - 1] { l.global_read_list[kept] = l.global_read_list[at]; kept += 1; }
    }
    l.global_read_list.resize(kept);
    let span = LifeCaptureSpan { first: first, count: kept - first, head: head };
    l.bodies[body_index].global_inputs = span;
    return span;
}
fn life_in_scope(l: Lifetimes&, scope: i64, parent: i64) -> bool {
    if parent < 0 { return false; }
    // Each scope is appended after its parent.
    var at = scope;
    while at > parent { at = l.parents[at]; }
    return at == parent;
}
fn life_leave_scope(p: Program&, l: Lifetimes&, scope: i64) {
    if scope < 0 { return; }
    if l.nodes_prepared && scope < l.scope_has_cell.len && l.scope_has_cell[scope] == 0 { return; }
    var ci = l.frames[l.frame].first_cell;
    while ci >= 0 {
        let cell: const LifeCell& = l.cells[ci];
        if cell.live && life_in_scope(l, p.symbols[cell.symbol].scope, scope) { life_set_live(l, ci, false); }
        ci = cell.next_frame;
    }
}
fn life_future_reachable(l: Lifetimes&, index: i64, future: const LifeFuture&) -> bool {
    let exit = l.future_exit;
    if exit.frame < 0 || index >= exit.before { return true; }
    if future.frame != exit.frame {
        if exit.scope >= 0 { return true; }
        var f = l.frames[future.frame].parent;
        while f > 0 {
            if f == exit.frame { return false; }
            f = l.frames[f].parent;
        }
        return f != exit.frame;
    }
    if exit.scope < 0 { return false; }
    let scope = if future.loop_scope >= 0 { future.loop_scope } else { future.scope };
    return !life_in_scope(l, scope, exit.scope);
}
fn life_used_after(p: Program&, l: Lifetimes&, cell: const LifeCell&) -> bool {
    for index in l.future_floor..l.future_count {
        let future = l.futures[index];
        if !life_future_reachable(l, index, future) { continue; }
        if future.loop_scope >= 0 && p.symbols[cell.symbol].scope != future.loop_scope && life_in_scope(l, p.symbols[cell.symbol].scope, future.loop_scope) { continue; }
        let saved = l.frame; l.frame = future.frame;
        let frame = life_frame_for(p, l, cell.symbol); l.frame = saved;
        if frame == cell.frame && life_reads(p, l, future.node, cell.symbol, future.last) { return true; }
    }
    return false;
}
// ---- What a class root stands for ----
// A class-keyed frame's body is checked once for every call with its key
// (life_class_call). What the body needs to know of the arguments beyond the
// key is asked here, answered from the call the frame is being evaluated for,
// and kept with the frame: a later call shares the frame only if it answers
// every such question the same way, or the cautious answer takes over
// (life_class_check).
// The recorded answer: 1 or 0, or -1 for none.
inline fn life_assume_hash(frame: i64, query: i64, index: i64, subject: i64, flag: bool) -> i64 {
    var bit = 0; if flag { bit = 1; }
    var h: u64 = (frame as! u64) * 11400714819323198485 ^ ((query * 2 + bit) as! u64) * 14029467366897019727 ^
        (index as! u64) * 1609587929392839161 ^ (subject as! u64) * 9650029242287828579;
    h ^= h >> 29;
    return (h >> 1) as! i64;
}
inline fn life_assume_meta(frame: i64, query: i64, flag: bool, state: i64) -> i32 {
    var bit: i64 = 0; if flag { bit = 4; }
    return ((frame << 6) | (query << 3) | bit | state) as i32;
}
// The slot of assume_slots that holds this question, or the empty one it
// would take.
fn life_assume_rehash(l: Lifetimes&) {
    var size: i64 = 256; while size <= 3 * (l.assumes.len + 1) { size <<= 1; }
    var old: LifeAssumeSlot[>..] = []; old.append(l.assume_slots);
    l.assume_slots.clear(); l.assume_slots.resize(size, LifeAssumeSlot {});
    let nmask = size - 1;
    for e in old {
        if e.at < 0 { continue; }
        let ef = (e.meta as i64) >> 6;
        let eq = ((e.meta as i64) >> 3) & 7;
        let efl = (e.meta & 4) != 0;
        var slot = life_assume_hash(ef, eq, e.index as i64, e.subject as i64, efl) & nmask;
        while l.assume_slots[slot].at >= 0 { slot = (slot + 1) & nmask; }
        l.assume_slots[slot] = e;
    }
}
fn life_assume_slot(l: Lifetimes&, frame: i64, query: i64, index: i64, subject: i64, flag: bool, key: i64) -> i64 {
    if 3 * (l.assumes.len + 1) > l.assume_slots.len { life_assume_rehash(l); }
    let mask = l.assume_slots.len - 1; var slot = key & mask;
    let want_meta = life_assume_meta(frame, query, flag, 0);
    let i32v = index as i32; let s32 = subject as i32;
    loop {
        let e = l.assume_slots[slot];
        if e.at < 0 { break; }
        if (e.meta & ~3) == want_meta && e.index == i32v && e.subject == s32 { break; }
        slot = (slot + 1) & mask;
    }
    return slot;
}
fn life_assume_sync_slot(l: Lifetimes&, at: i64) {
    let a: const LifeAssume& = l.assumes[at];
    let frame = a.frame as i64; let query = a.query as i64; let index = a.index as i64; let subject = a.subject as i64;
    var state: i64 = 0;
    if a.open == 0 { if a.answer { state = 2; } else { state = 1; } }
    else if a.open < 0 { state = 3; }
    let want_meta = life_assume_meta(frame, query, a.flag, 0);
    let key = life_assume_hash(frame, query, index, subject, a.flag);
    let l1_slot = key & 2047;
    if state == 1 || state == 2 {
        l.assume_l1[l1_slot] = LifeAssumeSlot { meta: want_meta | (state as i32), index: a.index, subject: a.subject, at: at as i32 };
    } else if l.assume_l1[l1_slot].at == (at as i32) {
        l.assume_l1[l1_slot].at = -1;
    }
    let mask = l.assume_slots.len - 1; var slot = key & mask;
    loop {
        let e = l.assume_slots[slot];
        if e.at < 0 { return; }
        if (e.meta & ~3) == want_meta && e.index == a.index && e.subject == a.subject {
            l.assume_slots[slot].meta = want_meta | (state as i32);
            return;
        }
        slot = (slot + 1) & mask;
    }
}
// Single-probe lookup or open for a frame assumption:
// -1 known false, -2 known true, -3 open further up (query_cut updated),
// -4 limit reached (caller returns life_cautious), >= 0 opened assume index.
fn life_assume_probe(l: Lifetimes&, frame: i64, query: i64, index: i64, subject: i64, flag: bool) -> i64 {
    let key = life_assume_hash(frame, query, index, subject, flag);
    let l1_slot = key & 2047;
    let e1 = l.assume_l1[l1_slot];
    if e1.at >= 0 && (e1.meta & ~3) == life_assume_meta(frame, query, flag, 0) && e1.index == (index as i32) && e1.subject == (subject as i32) {
        let st1 = e1.meta & 3;
        if st1 == 2 { return -2; }
        if st1 == 1 { return -1; }
    }
    let slot = life_assume_slot(l, frame, query, index, subject, flag, key);
    let e = l.assume_slots[slot];
    var at = e.at as i64;
    if at >= 0 {
        let st = e.meta & 3;
        if st == 2 { l.assume_l1[l1_slot] = e; return -2; }
        if st == 1 { l.assume_l1[l1_slot] = e; return -1; }
        if st == 0 {
            let op = l.assumes[at].open as i64;
            if op > 0 { if op < l.query_cut { l.query_cut = op; } l.chk_saw_unsealed = true; return -3; }
        }
    }
    if l.frames[frame].assume_count >= LIFE_ASSUME_LIMIT { return -4; }
    l.query_depth += 1;
    let open_meta = life_assume_meta(frame, query, flag, 0);
    if at < 0 {
        at = l.assumes.len;
        l.assume_slots[slot] = LifeAssumeSlot { meta: open_meta, index: index as i32, subject: subject as i32, at: at as i32 };
        l.assumes.push(LifeAssume { frame: frame as i32, query: query as i32, index: index as i32, subject: subject as i32, next: -2, flag: flag, answer: false });
        l.frames[frame].assume_count += 1;
    } else {
        l.assume_slots[slot].meta = open_meta;
    }
    l.assumes[at].open = l.query_depth as i32; l.assumes[at].answer = false;
    return at;
}
fn life_assume_close(l: Lifetimes&, at: i64, answer: bool) {
    let depth = l.query_depth; l.query_depth -= 1;
    l.assumes[at].answer = answer; l.assumes[at].open = 0;
    if !answer && l.query_cut < depth { l.assumes[at].open = -1; l.chk_saw_unsealed = true; }
    if l.query_cut >= depth { l.query_cut = 4611686018427387904; }
    life_assume_sync_slot(l, at);
    if l.assumes[at].open == 0 && answer != life_cautious(l.assumes[at].query as i64) && l.assumes[at].next == -2 {
        let frame = l.assumes[at].frame as i64;
        l.assumes[at].next = l.frames[frame].assumptions as i32;
        l.frames[frame].assumptions = at;
        l.frames[frame].noncautious_ver += 1;
        l.assumes[at].ver = l.frames[frame].noncautious_ver;
        let q = l.assumes[at].query as i64;
        let base = l.frames[frame].class_base;
        if q < 3 {
            if (l.assumes[at].index as i64) >= base { l.frames[frame].has_gs_assume = true; }
        } else if (l.assumes[at].index as i64) >= base ||
                  ((q == 4 || q == 5) && (l.assumes[at].subject as i64) >= base) {
            l.frames[frame].has_deep_assume = true;
        }
    }
}
// What the storage of a set's exactly named roots holds now, as a read of
// it here would find (life_contents); a bound stays a bound, and static data
// holds nothing that is tracked.
inline fn life_kill_matches_root(p: Program&, l: Lifetimes&, root: i64, ty: i64) -> bool {
    if ty < 0 { return true; }
    let rt: const LifeRoot& = l.roots[root];
    if rt.class_frame < 0 { return rt.type_id < 0 || life_same(p, rt.type_id, ty); }
    if rt.class_parent >= 0 { return rt.class_type < 0 || life_same(p, rt.class_type, ty); }
    if rt.class_index < l.frames[rt.class_frame].class_base { return rt.class_pointee < 0 || life_same(p, rt.class_pointee, ty); }
    return true;
}
inline fn life_root_is_slot_container(p: Program&, l: Lifetimes&, root: i64) -> bool {
    let rt: const LifeRoot& = l.roots[root];
    if rt.class_frame < 0 { return rt.type_id >= 0 && (!life_is_ref(p, rt.type_id) || rt.frame == 0 && rt.symbol >= 0 && (p.symbols[rt.symbol].flags & S_GLOBAL) != 0); }
    if rt.class_parent >= 0 { return rt.class_type >= 0 && !life_is_ref(p, rt.class_type); }
    if rt.class_index < l.frames[rt.class_frame].class_base { return rt.class_pointee >= 0 && !life_is_ref(p, rt.class_pointee); }
    return true;
}
fn life_held(p: Program&, l: Lifetimes&, set: i64) -> i64 {
    if set == 0 { return 0; }
    let first = l.sets[set].first as i64; let count = l.sets[set].count as i64;
    if count <= 0 { return 0; }
    var plain = true; var all_slot = true; var any_slot = false;
    for hi in 0..count {
        let a: const LifeAlt& = l.alts[first + hi];
        if a.root == 0 || !a.exact { plain = false; all_slot = false; }
        else if life_root_is_slot_container(p, l, a.root as i64) { any_slot = true; }
        else { all_slot = false; }
    }
    if plain && !any_slot { if l.discovery { return life_contents(p, l, set); } return life_live_contents(p, l, set); }
    if plain && all_slot {
        let raw = if l.discovery { life_contents(p, l, set) } else { life_live_contents(p, l, set) };
        return life_mark_slotread(l, raw);
    }
    var out = LifeBuild {};
    for hi in 0..count {
        let a = l.alts[first + hi];
        if a.root == 0 { continue; }
        if a.exact {
            let place = life_single(l, a.root, true, -1, false, false, -1, a.bound);
            var c = if l.discovery { life_contents(p, l, place) } else { life_live_contents(p, l, place) };
            if life_root_is_slot_container(p, l, a.root as i64) { c = life_mark_slotread(l, c); }
            life_build_add(l, out, c);
        } else { life_build_add_alt(l, out, LifeAlt { root: a.root, bound: a.bound, exact: false, slotread: a.slotread || life_root_is_slot_container(p, l, a.root as i64), byteview: a.byteview }); }
    }
    return life_build_end(l, out);
}
// What a class root's storage holds is one class whatever the references
// point at, which a body that reads one field would then store or return as
// all of them. A read of one pointee type gets a storage class of its own
// instead: of the class root it reads out of and that pointee, made when
// first read. A call maps it to what its argument's storage holds of that
// pointee, picked as a read-back picks (life_typed_held). A read out of its
// own storage is such a class in turn, LIFE_CLASS_DEPTH deep at most (a loop
// that follows links would go on making them); past that its storage holds
// only something read out of itself.
let LIFE_CLASS_DEPTH: i64 = 2;
// One frame makes at most LIFE_TYPED_CLASSES reference-holding typed storage
// classes and at most LIFE_TYPED_CLASSES POD typed storage classes (dropping
// POD typed classes to LIFE_TYPED_FEW once the program passes LIFE_TYPED_PRESSURE
// alternatives). Past the limit a read keeps the class of everything the
// storage holds (life_class_typed returns -1).
let LIFE_TYPED_CLASSES: i64 = 256;
let LIFE_TYPED_FEW: i64 = 8;
let LIFE_TYPED_PRESSURE: i64 = 4000000;
inline fn life_typed_hash(parent: i64, pointee: i64, mask: i64) -> i64 {
    var h: u64 = (parent as! u64) * 11400714819323198485 ^ (pointee as! u64) * 14029467366897019727; h ^= h >> 29;
    return (h & (mask as! u64)) as i64;
}
fn life_typed_rehash(l: Lifetimes&) {
    var size: i64 = 128; while size <= 2 * (l.typed_count + 1) { size <<= 1; }
    var old: LifeTypedSlot[>..] = []; old.append(l.typed_slots);
    l.typed_slots.clear(); l.typed_slots.resize(size, LifeTypedSlot {});
    let nmask = size - 1;
    for e in old {
        if e.root < 0 { continue; }
        var slot = life_typed_hash(e.parent as i64, e.pointee as i64, nmask);
        while l.typed_slots[slot].root >= 0 { slot = (slot + 1) & nmask; }
        l.typed_slots[slot] = e;
    }
}
fn life_class_typed(l: Lifetimes&, parent: i64, pointee: i64) -> i64 {
    if 2 * (l.typed_count + 1) > l.typed_slots.len { life_typed_rehash(l); }
    let mask = l.typed_slots.len - 1; var slot = life_typed_hash(parent, pointee, mask);
    let p32 = parent as i32; let pt32 = pointee as i32;
    loop {
        let e = l.typed_slots[slot];
        if e.root < 0 { break; }
        if e.parent == p32 && e.pointee == pt32 { return e.root as i64; }
        slot = (slot + 1) & mask;
    }
    let frame = l.roots[parent].class_frame; let root = l.roots.len;
    let empty = l.nodes_prepared && pointee >= 0 && pointee < l.type_flags.len && (l.type_flags[pointee] & (TF_L_HOLDS | TF_L_BYTES)) == 0;
    if empty {
        var plim = LIFE_TYPED_CLASSES; if l.alts.len > LIFE_TYPED_PRESSURE { plim = LIFE_TYPED_FEW; }
        if l.frames[frame].pod_typed_count >= plim { return -1; }
        l.frames[frame].pod_typed_count += 1;
    } else {
        if l.frames[frame].typed_count >= LIFE_TYPED_CLASSES { return -1; }
        l.frames[frame].typed_count += 1;
    }
    l.roots.push(LifeRoot { frame: 0, depth: l.roots[parent].depth, class_frame: frame, class_index: root - l.frames[frame].classes, class_parent: parent, class_type: pointee, class_next: l.frames[frame].typed_first, class_level: l.roots[parent].class_level + 1, class_empty: empty });
    l.frames[frame].typed_first = root; l.typed_slots[slot] = LifeTypedSlot { parent: p32, pointee: pt32, root: root as i32 }; l.typed_count += 1;
    if !empty { let own = life_single(l, root, false, root); life_set_contents(l, root, own); life_set_live_contents(l, root, own); }
    return root;
}
// Whether an exact reference to a class root may be one to `pointee`: any
// may but one to an argument class whose parameters' type holds no such
// value (upstream's CanContain of a binding root's pointee).
fn life_build_holder_refs(p: Program&, l: Lifetimes&, co: i64) {
    l.outer_type_seen_gen += 1;
    let gen = l.outer_type_seen_gen;
    let wbase = l.type_work.len;
    l.outer_type_seen[co] = gen;
    l.type_work.push(co as i32);
    let start = l.holder_ref_elems.len;
    var flags: u8 = 0;
    var at = wbase;
    while at < l.type_work.len {
        let t: const Type& = p.types[l.type_work[at] as i64]; at += 1;
        if t.kind == TY_SLICE || t.kind == TY_REF {
            if t.kind == TY_REF && t.length_storage >= 0 {
                flags |= 1;
            } else if t.element < 0 {
                flags |= 3;
            } else {
                l.holder_ref_elems.push(l.type_exact_canon[t.element]);
            }
        } else if t.kind == TY_ARRAY && t.element >= 0 {
            let elem = l.type_exact_canon[t.element] as i64;
            if l.outer_type_seen[elem] != gen { l.outer_type_seen[elem] = gen; l.type_work.push(elem as i32); }
        } else if t.kind == TY_STRUCT || t.kind == TY_ENUM || t.kind == TY_TUPLE {
            var field = t.first;
            while field >= 0 {
                let ft = p.nodes[field].type_id;
                if ft >= 0 {
                    let fe = l.type_exact_canon[ft] as i64;
                    if l.outer_type_seen[fe] != gen { l.outer_type_seen[fe] = gen; l.type_work.push(fe as i32); }
                }
                field = p.nodes[field].next;
            }
        }
    }
    l.type_work.resize(wbase);
    if l.holder_ref_elems.len - start > 1 {
        l.holder_ref_elems[start..l.holder_ref_elems.len].sort();
        var kept = start;
        for i in start..l.holder_ref_elems.len {
            if i == start || l.holder_ref_elems[i] != l.holder_ref_elems[kept - 1] {
                l.holder_ref_elems[kept] = l.holder_ref_elems[i]; kept += 1;
            }
        }
        l.holder_ref_elems.resize(kept);
    }
    l.holder_ref_start[co] = start as i32;
    l.holder_ref_count[co] = (l.holder_ref_elems.len - start) as i32;
    l.holder_ref_flags[co] = flags;
}
fn life_holder_points(p: Program&, l: Lifetimes&, raw_holder: i64, raw_pointee: i64) -> bool {
    if raw_holder < 0 || raw_pointee < 0 { return true; }
    let frozen = l.types_frozen && l.nodes_prepared;
    let holder = if frozen { l.type_exact_canon[raw_holder] as i64 } else { raw_holder };
    let pointee = if frozen { l.type_exact_canon[raw_pointee] as i64 } else { raw_pointee };
    if frozen && (l.type_flags[holder] & TF_L_HOLDS) == 0 { return false; }
    if l.refers.len == 0 { l.refers.resize(65536, LifeRefers {}); }
    let key = 0 - 2 - pointee;
    var h: u64 = (holder as! u64) * 11400714819323198485 ^ (key as! u64) * 14029467366897019727; h ^= h >> 29;
    let memo = (h & ((l.refers.len - 1) as! u64)) as i64;
    let r0 = l.refers[memo];
    if r0.holder == holder && r0.pointee == key { return r0.answer; }
    let r1 = l.refers[memo ^ 1];
    if r1.holder == holder && r1.pointee == key { return r1.answer; }
    var answer = false;
    if frozen {
        var cnt = l.holder_ref_count[holder] as i64;
        if cnt < 0 { life_build_holder_refs(p, l, holder); cnt = l.holder_ref_count[holder] as i64; }
        if (l.holder_ref_flags[holder] & 2) != 0 {
            answer = true;
        } else {
            let start = l.holder_ref_start[holder] as i64;
            for i in start..start + cnt {
                if life_contains(p, l, l.holder_ref_elems[i] as i64, pointee) { answer = true; break; }
            }
        }
    } else {
        let base = l.type_work.len; l.type_work.push(holder as i32); var at = base;
        while at < l.type_work.len && !answer {
            let t: const Type& = p.types[l.type_work[at] as i64]; at += 1;
            if t.kind == TY_SLICE || t.kind == TY_REF {
                if t.kind == TY_REF && t.length_storage >= 0 { continue; }
                if t.element < 0 || life_contains(p, l, t.element, pointee) { answer = true; }
            } else if t.kind == TY_ARRAY && t.element >= 0 {
                let elem = t.element as i32;
                var seen = false; for wi in base..l.type_work.len { if l.type_work[wi] == elem { seen = true; break; } }
                if !seen { l.type_work.push(elem); }
            } else if t.kind == TY_STRUCT || t.kind == TY_ENUM || t.kind == TY_TUPLE {
                var field = t.first;
                while field >= 0 {
                    let ft = p.nodes[field].type_id; var seen = ft < 0;
                    let ft32 = ft as i32;
                    if !seen { for wi in base..l.type_work.len { if l.type_work[wi] == ft32 { seen = true; break; } } }
                    if !seen { l.type_work.push(ft32); }
                    field = p.nodes[field].next;
                }
            }
        }
        l.type_work.resize(base);
    }
    if r0.holder < 0 { l.refers[memo] = LifeRefers { holder: holder, pointee: key, answer: answer }; }
    else if r1.holder < 0 { l.refers[memo ^ 1] = LifeRefers { holder: holder, pointee: key, answer: answer }; }
    else { l.refers[memo ^ 1] = r0; l.refers[memo] = LifeRefers { holder: holder, pointee: key, answer: answer }; }
    return answer;
}
inline fn life_class_holds(p: Program&, l: Lifetimes&, root: i64, pointee: i64) -> bool {
    let owner = l.roots[root].class_frame;
    if owner < 0 { return false; }
    if l.roots[root].class_parent >= 0 { return pointee < 0 || life_contains_memo(p, l, l.roots[root].class_type, pointee); }
    let idx = l.roots[root].class_index; let base = l.frames[owner].class_base;
    if idx >= base && idx < 2 * base {
        let pt = l.roots[l.frames[owner].classes + idx - base].class_pointee;
        if pt >= 0 && pt != TYPE_U8 && p.types[pt].element != TYPE_U8 {
            return pointee < 0 || life_holder_points(p, l, pt, pointee);
        }
        return true;
    }
    let own = l.roots[root].class_pointee;
    if own >= 0 { return pointee < 0 || life_contains_memo(p, l, own, pointee); }
    let holder = l.roots[root].class_holder;
    if holder >= 0 { return pointee < 0 || life_holder_points(p, l, holder, pointee); }
    return true;
}
// An alternative found in a class root's storage, as a read of `pointee`
// takes it: the class of everything that storage holds becomes its storage
// class of that pointee, and "something read out of this" at the storage
// class `place` itself becomes the class of that, while classes go that deep.
fn life_class_narrow(p: Program&, l: Lifetimes&, alt: LifeAlt, place: i64, pointee: i64) -> LifeAlt {
    var out = alt; let owner = l.roots[alt.root].class_frame;
    if owner < 0 || pointee < 0 || !l.frames[owner].active { return out; }
    let own = l.roots[alt.root].class_index; let base = l.frames[owner].class_base;
    if alt.exact && l.roots[alt.root].class_parent < 0 && own >= base {
        if alt.byteview || life_class_holds(p, l, alt.root as i64, pointee) {
            let typed = life_class_typed(l, l.frames[owner].classes + own - base, pointee);
            if typed >= 0 { out.root = typed as i32; out.target_type = -1; }
        }
    } else if !alt.exact && alt.from == alt.root && (alt.root as i64) == place && own >= 2 * base && l.roots[alt.root].class_level < LIFE_CLASS_DEPTH {
        let typed = life_class_typed(l, place, pointee);
        if typed >= 0 { out.root = typed as i32; out.exact = true; out.from = -1; out.target_type = -1; }
    }
    return out;
}
// What the storage of a set's roots holds of references to `pointee`: the
// alternatives a read-back of that pointee would keep (life_readback).
fn life_typed_held(p: Program&, l: Lifetimes&, set: i64, pointee: i64) -> i64 {
    let held = life_held(p, l, set);
    if held == 0 { return 0; }
    let hfirst = l.sets[held].first as i64; let hcount = l.sets[held].count as i64;
    if hcount <= 0 { return 0; }
    let start = l.scratch.len; var dropped = false; var root_changed = false; var globals_ok: i64 = -1;
    for hi in 0..hcount {
        let r: const LifeAlt& = l.alts[hfirst + hi];
        var keep = (r.target_type < 0 || life_same(p, r.target_type as i64, pointee)) &&
            (r.root == 0 || r.byteview || !r.exact || life_class_holds(p, l, r.root as i64, pointee) || life_contains_memo(p, l, l.roots[r.root].type_id, pointee)) &&
            (r.root == 0 || r.byteview || r.exact || r.from != r.root || l.roots[r.root].class_frame < 0 || l.roots[r.root].class_parent < 0 || life_holder_points(p, l, l.roots[r.root].class_type, pointee));
        if keep && !r.byteview && life_is_global_bound(l, r) {
            if globals_ok < 0 { if life_globals_contain(p, l, pointee) { globals_ok = 1; } else { globals_ok = 0; } }
            if globals_ok == 0 { keep = false; }
        }
        if keep {
            var kept = r; kept.next = -1; var changed = false;
            // Where the storage is a class root's own (the call is made in an
            // island and passes its parameter on), what it holds of this
            // pointee is that island's storage class of the pointee, as a
            // read there would make it (life_readback).
            let owner = l.roots[r.root].class_frame;
            if owner >= 0 && l.frames[owner].active {
                let own = l.roots[r.root].class_index; let base = l.frames[owner].class_base;
                if r.exact && l.roots[r.root].class_parent < 0 && own >= base {
                    let typed = life_class_typed(l, l.frames[owner].classes + own - base, pointee);
                    if typed >= 0 { kept.root = typed as i32; kept.target_type = -1; changed = true; root_changed = true; }
                } else if !r.exact && r.from == r.root && l.roots[r.root].class_level < LIFE_CLASS_DEPTH && (own >= 2 * base) {
                    let typed = life_class_typed(l, r.root, pointee);
                    if typed >= 0 { kept.root = typed as i32; kept.exact = true; kept.from = -1; kept.target_type = -1; changed = true; root_changed = true; }
                }
            }
            // What a storage class holds, taken as this pointee, is a
            // reference to it (as a read of it is, life_readback).
            if kept.exact && kept.target_type < 0 && !kept.byteview && kept.root != 0 && l.roots[kept.root].class_frame >= 0 && l.roots[kept.root].class_parent < 0 &&
               l.roots[kept.root].class_index >= l.frames[l.roots[kept.root].class_frame].class_base { kept.target_type = pointee as i32; changed = true; }
            if !dropped && changed {
                dropped = true;
                for prev in 0..hi {
                    var pa = l.alts[hfirst + prev]; pa.next = -1;
                    l.scratch.push(pa);
                }
            }
            if dropped { l.scratch.push(kept); }
        } else if !dropped {
            dropped = true;
            for prev in 0..hi {
                var pa = l.alts[hfirst + prev]; pa.next = -1;
                l.scratch.push(pa);
            }
        }
    }
    if !dropped { return held; }
    if !root_changed {
        let res = life_list_set(l, start, true);
        l.scratch.resize(start);
        return res;
    }
    var out = LifeBuild {};
    for si in start..l.scratch.len { life_build_add_alt(l, out, l.scratch[si]); }
    l.scratch.resize(start);
    return life_build_end(l, out);
}
// What a storage class of one pointee type stands for at a call: what the
// storage of its parent class's roots holds of that pointee. serial: the
// call's, to keep the answer for it (map_memo), or -1.
inline fn life_map_memo_put(l: Lifetimes&, memo: i64, ks32: i32, key32: i32, res: i32, ep: i32, cur_ep: i32) {
    let alt = memo ^ 1;
    let e0 = l.map_memo[memo];
    if e0.serial == -1 || (e0.serial == ks32 && e0.key == key32) || (e0.epoch >= 0 && e0.epoch != cur_ep) {
        l.map_memo[memo] = LifeMapped { serial: ks32, key: key32, result: res, epoch: ep };
    } else {
        let e1 = l.map_memo[alt];
        if e1.serial == -1 || (e1.serial == ks32 && e1.key == key32) || (e1.epoch >= 0 && e1.epoch != cur_ep) {
            l.map_memo[alt] = LifeMapped { serial: ks32, key: key32, result: res, epoch: ep };
        } else {
            l.map_memo[alt] = e0;
            l.map_memo[memo] = LifeMapped { serial: ks32, key: key32, result: res, epoch: ep };
        }
    }
    l.map_memo_writes += 1;
    if l.map_memo_writes > 4 * l.map_memo.len && l.map_memo.len < 524288 {
        l.map_memo.resize(4 * l.map_memo.len, LifeMapped {});
        l.map_memo_writes = 0;
    }
}
recursive fn life_typed_set(p: Program&, l: Lifetimes&, classes: i64, base: i64, sets: i64, serial: i64, root: i64) -> i64 {
    var memo = -1;
    let key_set = (0 - 2 - root) as i32;
    let key_ser = serial as i32;
    let ep32 = l.held_epoch as i32;
    let can_cache = serial != -1 && l.held_epoch < 2147483647;
    if can_cache {
        if l.map_memo.len == 0 { l.map_memo.resize(16384, LifeMapped {}); }
        var mh: u64 = ((0 - 2 - root) as! u64) * 11400714819323198485 ^ (serial as! u64) * 14029467366897019727; mh ^= mh >> 29;
        memo = (mh & ((l.map_memo.len - 1) as! u64)) as i64;
        let e0 = l.map_memo[memo];
        if e0.serial == key_ser && e0.key == key_set && e0.epoch == ep32 { return e0.result as i64; }
        let e1 = l.map_memo[memo ^ 1];
        if e1.serial == key_ser && e1.key == key_set && e1.epoch == ep32 { return e1.result as i64; }
    }
    let parent = l.roots[root].class_parent; var of = 0;
    if l.roots[parent].class_parent < 0 { of = life_class_set(p, l, base, sets, parent - classes); }
    else { of = life_typed_set(p, l, classes, base, sets, serial, parent); }
    let set = life_typed_held(p, l, of, l.roots[root].class_type);
    if memo >= 0 && l.held_epoch < 2147483647 { life_map_memo_put(l, memo, key_ser, key_set, set as i32, l.held_epoch as i32, l.held_epoch as i32); }
    return set;
}
// What class `index` of a frame with `base` argument classes stands for at
// the call whose sets are at `sets`: an argument class is the call's set,
// the others what the storage of those holds, one read in per level.
// Everything reachable by reading out of the storage of a set's exactly
// named roots, one read or more: what something read deep out of that
// storage may be. Past LIFE_DEEP_ROOTS storages, the rest are bounds.
let LIFE_DEEP_ROOTS: i64 = 16;
// Storage reached as one pointee type holds only what that type holds a
// reference to (life_referable): a table of module references leads to
// modules, not to everything the storage class it lies in holds. first: the
// pointee type the alternatives of `set` are references to, or -1.
fn life_deep(p: Program&, l: Lifetimes&, set: i64, first: i64 = -1) -> i64 {
    var out = life_held(p, l, set); if first >= 0 { out = life_referable(p, l, out, first); }
    var visited: i64[>..] = []; var types: i64[>..] = []; var at = l.sets[set].first;
    while at >= 0 { visited.push(l.alts[at].root as i64); types.push(first); at = l.alts[at].next; }
    loop {
        var next = 0; var wide = false; at = l.sets[out].first;
        while at >= 0 {
            let a = l.alts[at]; at = a.next;
            if !a.exact || a.root == 0 { continue; }
            var points = a.target_type as i64; if points < 0 && l.roots[a.root].class_frame >= 0 && l.roots[a.root].class_parent >= 0 { points = l.roots[a.root].class_type; }
            var seen = -1; for old, index in visited { if old == a.root { seen = index; break; } }
            if seen >= 0 && (types[seen] < 0 || types[seen] == points) { continue; }
            // Seen as a reference to another type: everything it holds.
            if seen >= 0 { types[seen] = -1; points = -1; }
            else { visited.push(a.root as i64); types.push(points); if visited.len > LIFE_DEEP_ROOTS { wide = true; break; } }
            var part = life_held(p, l, life_single(l, a.root, true, -1, false, false, -1, a.bound));
            if points >= 0 { part = life_referable(p, l, part, points); }
            next = life_join(l, next, part);
        }
        if wide {
            // Too wide to follow: whatever the rest holds outlives it.
            var bounds = LifeBuild { set: out }; at = l.sets[out].first;
            while at >= 0 { let a = l.alts[at]; at = a.next; if a.exact && a.root != 0 { life_build_add_alt(l, bounds, LifeAlt { root: a.root, bound: a.bound, exact: false, byteview: a.byteview }); } }
            return life_build_end(l, bounds);
        }
        let grown = life_join(l, out, next);
        if life_equal(l, grown, out) { return out; }
        out = grown;
    }
    return out;
}
// What something read deep out of the storage of an argument class may be
// at the call whose sets are at `sets`, kept for the call as the storage
// classes are.
// (Something only reached from a storage class was read out of its storage
// at least once more: it is what that class's roots lead to, not those
// roots. Mapped from the argument's roots instead, it took in the storage
// class's own roots, and a store of it into that class made each hold
// itself.)
fn life_class_deep(p: Program&, l: Lifetimes&, base: i64, sets: i64, index: i64) -> i64 {
    let slot = sets + 2 * base + index;
    if l.map_sets[slot] < 0 { let deep = life_deep(p, l, life_class_set(p, l, base, sets, index)); l.map_sets[slot] = deep; }
    return l.map_sets[slot];
}
// A storage class is worked out when the call first needs it and kept for
// the call (its slot in map_sets is -1 before): what the storage held as
// the call began to be read; what the call's own effects store there since
// reaches the caller as those effects.
fn life_class_set(p: Program&, l: Lifetimes&, base: i64, sets: i64, index: i64) -> i64 {
    if l.map_sets[sets + index] >= 0 { return l.map_sets[sets + index]; }
    var below = l.map_sets[sets + index - base];
    if below < 0 { below = life_held(p, l, l.map_sets[sets + index - 2 * base]); l.map_sets[sets + index - base] = below; }
    let set = life_held(p, l, below); l.map_sets[sets + index] = set;
    return set;
}
// Queries 3, 4 and 6, of the call whose sets are at `sets`.
// life_held without what a read adds beyond the roots' own contents: for
// the questions of roots, which those additions ask in turn.
fn life_held_own(l: Lifetimes&, set: i64) -> i64 {
    if set == 0 { return 0; }
    let first = l.sets[set].first as i64; let count = l.sets[set].count as i64;
    if count <= 0 { return 0; }
    if count == 1 {
        let a = l.alts[first];
        if a.root == 0 { return 0; }
        if a.exact {
            if l.chk_dep_recording { l.chk_dep_stack.push(a.root); }
            if l.discovery {
                if l.frame > 0 && (l.island == 0 || l.roots[a.root].frame <= 0 && l.roots[a.root].class_frame < 0) { life_push_dep_root(l, a.root as i64); }
                let c = l.roots[a.root].contents;
                return life_fold(l, c);
            }
            let lc = l.roots[a.root].live_contents;
            return life_fold(l, lc);
        }
        return life_single(l, a.root as i64, false, -1, false, a.byteview);
    }
    var slot: i64 = -1;
    if l.class_frames > 0 {
        if l.held_own_memo.len == 0 { l.held_own_memo.resize(64, LifeHeldOwn {}); }
        var h: u64 = (set as! u64) * 11400714819323198485;
        if l.discovery { h ^= 14029467366897019727; }
        h ^= h >> 29;
        slot = (h & ((l.held_own_memo.len - 1) as! u64)) as i64;
        let memo = l.held_own_memo[slot];
        if memo.set == (set as i32) && memo.discovery == l.discovery {
            var same = memo.epoch == l.held_epoch;
            if !same {
                same = true;
                if l.discovery {
                    if l.root_stamps.len < l.roots.len { l.root_stamps.resize(l.roots.len, 0); }
                    for i in 0..count {
                        let a: const LifeAlt& = l.alts[first + i];
                        if a.root != 0 && a.exact && l.root_stamps[a.root] > memo.stamp { same = false; break; }
                    }
                } else {
                    if l.root_live_stamps.len < l.roots.len { l.root_live_stamps.resize(l.roots.len, 0); }
                    for i in 0..count {
                        let a: const LifeAlt& = l.alts[first + i];
                        if a.root != 0 && a.exact && l.root_live_stamps[a.root] > memo.stamp { same = false; break; }
                    }
                }
                if same { l.held_own_memo[slot].epoch = l.held_epoch; }
            }
            if same {
                if l.chk_dep_recording {
                    for i in 0..count {
                        let a: const LifeAlt& = l.alts[first + i];
                        if a.root != 0 && a.exact { l.chk_dep_stack.push(a.root); }
                    }
                }
                if l.discovery && l.frame > 0 && (l.island == 0 || (l.sets[set].flags & 2) != 0) {
                    for i in 0..count {
                        let a: const LifeAlt& = l.alts[first + i];
                        if a.root != 0 && a.exact && (l.island == 0 || l.roots[a.root].frame <= 0 && l.roots[a.root].class_frame < 0) {
                            life_push_dep_root(l, a.root as i64);
                        }
                    }
                }
                return memo.result as i64;
            }
        }
    }
    var out = LifeBuild {}; var prev_c: i64 = 0;
    for i in 0..count {
        let a = l.alts[first + i];
        if a.root == 0 { continue; }
        if a.exact {
            if l.chk_dep_recording { l.chk_dep_stack.push(a.root); }
            var c: i64 = 0;
            if l.discovery {
                if l.frame > 0 && (l.island == 0 || l.roots[a.root].frame <= 0 && l.roots[a.root].class_frame < 0) { life_push_dep_root(l, a.root as i64); }
                c = l.roots[a.root].contents;
            } else { c = l.roots[a.root].live_contents; }
            if c != 0 && c != prev_c { life_build_add(l, out, c); prev_c = c; }
        }
        else { life_build_add_alt(l, out, LifeAlt { root: a.root, exact: false, byteview: a.byteview }); }
    }
    let res = life_fold(l, life_build_end(l, out));
    if slot >= 0 {
        let cur_stamp: i64 = if l.discovery { l.contents_stamp } else { l.live_contents_stamp };
        l.held_own_memo[slot] = LifeHeldOwn { set: set as i32, result: res as i32, discovery: l.discovery, stamp: cur_stamp, epoch: l.held_epoch };
        l.held_own_recorded += 1;
        if l.held_own_recorded > 4 * l.held_own_memo.len && l.held_own_memo.len < 262144 {
            l.held_own_memo.resize(4 * l.held_own_memo.len, LifeHeldOwn {});
            l.held_own_recorded = 0;
        }
    }
    return res;
}
// One number for all the types life_same takes as one, for where no Program
// is at hand (the questions of roots): made when the first class-keyed frame
// is (life_class_new), by when types no longer change.
fn life_canon_types(p: Program&, l: Lifetimes&) {
    var size: i64 = 64; while size < 2 * p.types.len { size <<= 1; }
    var slots: i64[>..] = []; slots.resize(size, -1); l.type_canon.clear();
    for t, index in p.types {
        var a: i64 = 0; var b: i64 = 0;
        if t.kind == TY_STRUCT || t.kind == TY_ENUM { a = t.declaration; }
        else if t.kind == TY_INT { a = t.count; b = (t.flags & TF_UNSIGNED) as i64; }
        else if t.kind == TY_FLOAT { a = t.count; }
        else if t.kind == TY_ARRAY { a = t.array_kind; b = t.element; }
        else if t.kind == TY_REF || t.kind == TY_SLICE { a = t.element; }
        var h: u64 = 1469598103934665603;
        h = life_hash_step(h, t.kind as i64);
        h = life_hash_step(h, a);
        h = life_hash_step(h, b);
        var slot = ((h >> 1) as! i64) & (size - 1); var found = -1;
        loop {
            let other = slots[slot];
            if other < 0 { break; }
            if life_same(p, other, index) { found = other; break; }
            slot = (slot + 1) & (size - 1);
        }
        if found < 0 { slots[slot] = index; found = index; }
        l.type_canon.push(found);
    }
}
inline fn life_canon(l: Lifetimes&, type_id: i64) -> i64 {
    if type_id < 0 || type_id >= l.type_canon.len { return type_id; }
    return l.type_canon[type_id];
}
// What the globals' own storage holds inline, by type (upstream's candidates
// among the globals, RootCandidates): the folded alternative "something in
// global storage" (life_fold) has no type of its own, and stood for a
// reference of any type.
fn life_global_types(p: Program&, l: Lifetimes&) {
    if l.type_canon.len < p.types.len { life_canon_types(p, l); }
    l.global_types.clear(); l.global_types.resize(l.type_canon.len, 0 as i8);
    var work: i64[>..] = [];
    for symbol in p.symbols {
        if (symbol.flags & S_GLOBAL) == 0 || symbol.type_id < 0 { continue; }
        let ty = life_canon(l, symbol.type_id);
        if l.global_types[ty] == 0 { l.global_types[ty] = 1; work.push(ty); }
    }
    // Through arrays and fields; a reference or slice ends the walk.
    var at = 0;
    while at < work.len {
        let t: const Type& = p.types[work[at]]; at += 1;
        if t.kind == TY_ARRAY && t.element >= 0 {
            let e = life_canon(l, t.element);
            if l.global_types[e] == 0 { l.global_types[e] = 1; work.push(e); }
        } else if t.kind == TY_STRUCT || t.kind == TY_ENUM || t.kind == TY_TUPLE {
            var field = t.first;
            while field >= 0 {
                if p.nodes[field].type_id >= 0 {
                    let e = life_canon(l, p.nodes[field].type_id);
                    if l.global_types[e] == 0 { l.global_types[e] = 1; work.push(e); }
                }
                field = p.nodes[field].next;
            }
        }
    }
}
// Whether some global's own storage holds a `pointee` inline: what a
// reference to one that points into global storage points into. Bytes may
// be a view of anything.
fn life_globals_contain(p: Program&, l: Lifetimes&, pointee: i64) -> bool {
    if pointee < 0 || pointee == TYPE_U8 { return true; }
    if l.global_types.len < p.types.len { life_global_types(p, l); }
    return l.global_types[life_canon(l, pointee)] != 0;
}
// Whether storage of type `holder` holds, inline, a reference or slice that
// may point at a `pointee` or into one: one whose own pointee type lies in a
// `pointee` (a `Module&` slot holds no reference to an i64, though a Module
// holds an i64). within: `pointee` is only the type of something the stored
// reference points into (an argument class's parameters' type, which may be
// part of a larger value), so a slot whose pointee type holds one will do
// too. A relative reference points into its owner or pool, and is not
// judged here.
fn life_refers(p: Program&, l: Lifetimes&, raw_holder: i64, raw_pointee: i64, within: bool = false) -> bool {
    if raw_holder < 0 || raw_pointee < 0 { return true; }
    let frozen = l.types_frozen && l.nodes_prepared;
    let holder = if frozen { l.type_exact_canon[raw_holder] as i64 } else { raw_holder };
    let pointee = if frozen { l.type_exact_canon[raw_pointee] as i64 } else { raw_pointee };
    if l.refers.len == 0 { l.refers.resize(65536, LifeRefers {}); }
    var key = 2 * pointee; if within { key += 1; }
    var h: u64 = (holder as! u64) * 11400714819323198485 ^ (key as! u64) * 14029467366897019727; h ^= h >> 29;
    let memo = (h & ((l.refers.len - 1) as! u64)) as i64;
    let r0 = l.refers[memo];
    if r0.holder == holder && r0.pointee == key { return r0.answer; }
    let r1 = l.refers[memo ^ 1];
    if r1.holder == holder && r1.pointee == key { return r1.answer; }
    var answer = false;
    if frozen {
        var cnt = l.holder_ref_count[holder] as i64;
        if cnt < 0 { life_build_holder_refs(p, l, holder); cnt = l.holder_ref_count[holder] as i64; }
        if (l.holder_ref_flags[holder] & 1) != 0 {
            answer = true;
        } else {
            let start = l.holder_ref_start[holder] as i64;
            for i in start..start + cnt {
                let elem = l.holder_ref_elems[i] as i64;
                if life_contains(p, l, pointee, elem) || within && life_contains(p, l, elem, pointee) { answer = true; break; }
            }
        }
    } else {
        let base = l.type_work.len; l.type_work.push(holder as i32); var at = base;
        while at < l.type_work.len && !answer {
            let t: const Type& = p.types[l.type_work[at] as i64]; at += 1;
            if t.kind == TY_SLICE || t.kind == TY_REF {
                if t.kind == TY_REF && t.length_storage >= 0 || t.element < 0 || life_contains(p, l, pointee, t.element) || within && life_contains(p, l, t.element, pointee) { answer = true; }
            } else if t.kind == TY_ARRAY && t.element >= 0 {
                let elem = t.element as i32;
                var seen = false; for wi in base..l.type_work.len { if l.type_work[wi] == elem { seen = true; break; } }
                if !seen { l.type_work.push(elem); }
            } else if t.kind == TY_STRUCT || t.kind == TY_ENUM || t.kind == TY_TUPLE {
                var field = t.first;
                while field >= 0 {
                    let ft = p.nodes[field].type_id; var seen = ft < 0;
                    let ft32 = ft as i32;
                    if !seen { for wi in base..l.type_work.len { if l.type_work[wi] == ft32 { seen = true; break; } } }
                    if !seen { l.type_work.push(ft32); }
                    field = p.nodes[field].next;
                }
            }
        }
        l.type_work.resize(base);
    }
    if r0.holder < 0 { l.refers[memo] = LifeRefers { holder: holder, pointee: key, answer: answer }; }
    else if r1.holder < 0 { l.refers[memo ^ 1] = LifeRefers { holder: holder, pointee: key, answer: answer }; }
    else { l.refers[memo ^ 1] = r0; l.refers[memo] = LifeRefers { holder: holder, pointee: key, answer: answer }; }
    return answer;
}
// The type of the storage a store's place is, where one type says what it
// can hold: what the place was reached as, or a storage class's pointee, an
// argument class's parameters', a root's own. -1 else.
fn life_place_holds(p: Program&, l: Lifetimes&, x: LifeAlt) -> i64 {
    if x.byteview || x.root == 0 { return -1; }
    // (What a place was reached as holds of it whichever root it lies in.)
    if x.target_type >= 0 { return x.target_type as i64; }
    if !x.exact { return -1; }
    let owner = l.roots[x.root].class_frame;
    if owner < 0 { if life_is_ref(p, l.roots[x.root].type_id) { return -1; } return l.roots[x.root].type_id; }
    if l.roots[x.root].class_parent >= 0 { return l.roots[x.root].class_type; }
    if l.roots[x.root].class_index < l.frames[owner].class_base { return l.roots[x.root].class_pointee; }
    return -1;
}
// What of a stored set storage of type `holder` can take: a reference to a
// pointee lands only in storage that holds a reference to such a pointee.
// Mapped as "what the argument's storage holds" on both sides, a store put a
// reference to a counter into a table of module references. A reference
// whose pointee is not known, or a byte view, may land anywhere.
fn life_referable(p: Program&, l: Lifetimes&, set: i64, raw_holder: i64) -> i64 {
    if set == 0 || raw_holder < 0 { return set; }
    // Storage that holds no reference takes none, of whatever pointee.
    let frozen = l.types_frozen && l.nodes_prepared;
    let holder = if frozen { l.type_exact_canon[raw_holder] as i64 } else { raw_holder };
    if frozen { if (l.type_flags[holder] & TF_L_HOLDS) == 0 { return 0; } }
    else if !life_tf_holds(p, l, holder) { return 0; }
    if l.referable.len == 0 { l.referable.resize(65536, LifeLoaded {}); }
    var h: u64 = (set as! u64) * 11400714819323198485 ^ (holder as! u64) * 14029467366897019727; h ^= h >> 29;
    let memo = (h & ((l.referable.len - 1) as! u64)) as i64;
    let e0 = l.referable[memo];
    if e0.contents == set && e0.places == holder { return e0.set; }
    let e1 = l.referable[memo ^ 1];
    if e1.contents == set && e1.places == holder { return e1.set; }
    let first = l.sets[set].first as i64; let count = l.sets[set].count as i64;
    let start = l.scratch.len; var dropped = false;
    for i in 0..count {
        var x = l.alts[first + i]; x.next = -1;
        if !x.byteview && x.root != 0 {
            var points = x.target_type as i64; var within = false;
            if points < 0 && x.exact {
                let owner = l.roots[x.root].class_frame;
                if owner < 0 { if !life_is_ref(p, l.roots[x.root].type_id) { points = l.roots[x.root].type_id; } }
                else if l.roots[x.root].class_parent >= 0 { points = l.roots[x.root].class_type; }
                else if l.roots[x.root].class_index < l.frames[owner].class_base { points = l.roots[x.root].class_pointee; within = true; }
            }
            if points >= 0 && !life_refers(p, l, holder, points, within) { dropped = true; continue; }
        }
        l.scratch.push(x);
    }
    var result = set;
    if dropped { result = life_list_set(l, start, true); }
    l.scratch.resize(start);
    if e0.contents < 0 { l.referable[memo] = LifeLoaded { contents: set, places: holder, set: result }; }
    else if e1.contents < 0 { l.referable[memo ^ 1] = LifeLoaded { contents: set, places: holder, set: result }; }
    else { l.referable[memo ^ 1] = e0; l.referable[memo] = LifeLoaded { contents: set, places: holder, set: result }; }
    return result;
}
// A store's places as references to the type its destination was reached
// as (LifeEffect.value.type_id of a store): a call then lands the store
// only in what such a destination can lie in (life_map_onto).
fn life_reached_places(l: Lifetimes&, places: i64, reached: i64) -> i64 {
    if places == 0 { return 0; }
    let first = l.sets[places].first as i64; let count = l.sets[places].count as i64;
    var unchanged = true;
    for i in 0..count {
        let a: const LifeAlt& = l.alts[first + i];
        if !a.byteview && a.target_type < 0 { unchanged = false; break; }
    }
    if unchanged { return places; }
    let start = l.scratch.len;
    for i in 0..count {
        var x = l.alts[first + i]; x.next = -1;
        if !x.byteview && x.target_type < 0 { x.target_type = reached as i32; }
        l.scratch.push(x);
    }
    let result = life_list_set(l, start, true);
    l.scratch.resize(start);
    return result;
}
// What a class of a frame stands for at a call, for a question of roots: an
// argument class is the call's set; a storage class what the storage of its
// parent holds, of its pointee where it is of one.
recursive fn life_class_any_set(p: Program&, l: Lifetimes&, frame: i64, sets: i64, index: i64) -> i64 {
    let base = l.frames[frame].class_base;
    if index < base { return l.map_sets[sets + index]; }
    // Kept for the call the question is asked of.
    let at = l.frames[frame].classes + index;
    if l.any_serial > 0 && l.roots[at].any_serial == l.any_serial { return l.roots[at].any_set; }
    let serial = l.any_serial;
    let made = life_class_any_make(p, l, frame, sets, index);
    if serial > 0 { l.roots[at].any_serial = serial; l.roots[at].any_set = made; }
    return made;
}
recursive fn life_class_any_make(p: Program&, l: Lifetimes&, frame: i64, sets: i64, index: i64) -> i64 {
    let base = l.frames[frame].class_base;
    if index < 3 * base { return life_held_own(l, life_class_any_set(p, l, frame, sets, index - base)); }
    let classes = l.frames[frame].classes;
    let root = l.roots[classes + index];
    let parent_root = root.class_parent;
    let parent_idx = parent_root - classes;
    var held: i64 = 0;
    if parent_idx < 2 * base {
        held = life_class_any_set(p, l, frame, sets, parent_idx + base);
    } else if l.any_serial > 0 && l.roots[parent_root].any_held_serial == l.any_serial {
        held = l.roots[parent_root].any_held;
    } else {
        let serial = l.any_serial;
        held = life_held_own(l, life_class_any_set(p, l, frame, sets, parent_idx));
        if serial > 0 { l.roots[parent_root].any_held = held; l.roots[parent_root].any_held_serial = serial; }
    }
    if held == 0 { return 0; }
    let hfirst = l.sets[held].first as i64; let hcount = l.sets[held].count as i64;
    if hcount <= 0 { return 0; }
    let pointee = root.class_type;
    let start = l.scratch.len; var dropped = false; var root_changed = false; var globals_ok: i64 = -1;
    for hi in 0..hcount {
        let r = l.alts[hfirst + hi];
        var keep = (r.target_type < 0 || life_same(p, r.target_type as i64, pointee)) &&
            (r.root == 0 || r.byteview || !r.exact || life_class_holds(p, l, r.root as i64, pointee) || life_contains_memo(p, l, l.roots[r.root].type_id, pointee)) &&
            (r.root == 0 || r.byteview || r.exact || r.from != r.root || l.roots[r.root].class_frame < 0 || l.roots[r.root].class_parent < 0 || life_holder_points(p, l, l.roots[r.root].class_type, pointee));
        if keep && !r.byteview && life_is_global_bound(l, r) {
            if globals_ok < 0 { if life_globals_contain(p, l, pointee) { globals_ok = 1; } else { globals_ok = 0; } }
            if globals_ok == 0 { keep = false; }
        }
        if keep {
            var kept = life_class_narrow(p, l, r, -1, pointee);
            let ch = kept.root != r.root;
            if ch { root_changed = true; }
            kept.next = -1;
            if !dropped && ch {
                dropped = true;
                for prev in 0..hi {
                    var pa = l.alts[hfirst + prev]; pa.next = -1;
                    l.scratch.push(pa);
                }
            }
            if dropped { l.scratch.push(kept); }
        } else if !dropped {
            dropped = true;
            for prev in 0..hi {
                var pa = l.alts[hfirst + prev]; pa.next = -1;
                l.scratch.push(pa);
            }
        }
    }
    if !dropped { return held; }
    if !root_changed {
        let result = life_list_set(l, start, true);
        l.scratch.resize(start);
        return result;
    }
    var out = LifeBuild {};
    for si in start..l.scratch.len { life_build_add_alt(l, out, l.scratch[si]); }
    l.scratch.resize(start);
    return life_build_end(l, out);
}
recursive fn life_class_answer_roots(p: Program&, l: Lifetimes&, frame: i64, sets: i64, query: i64, index: i64, subject: i64, flag: bool) -> bool {
    let base = l.frames[frame].class_base;
    if index >= base && query == 6 { return false; }
    let set = life_class_any_set(p, l, frame, sets, index);
    if query == 5 || query == 7 {
        let source = if flag { life_held_own(l, set) } else { set };
        let other = if query == 5 { life_class_any_set(p, l, frame, sets, subject) } else { life_root_set(l, subject) };
        var si = l.sets[source].first;
        while si >= 0 {
            let view = l.alts[si]; si = view.next;
            var oi = l.sets[other].first;
            while oi >= 0 {
                let place = l.alts[oi]; oi = place.next;
                if life_shrink_alias(p, l, view, place) { return true; }
            }
        }
        return false;
    }
    if query == 4 {
        let other = life_class_any_set(p, l, frame, sets, subject);
        if set == 0 || other == 0 { return false; }
        let af = l.sets[set].first as i64; let ac = l.sets[set].count as i64;
        let bf = l.sets[other].first as i64; let bc = l.sets[other].count as i64;
        if ac <= 0 || bc <= 0 { return false; }
        if set == other {
            for i in 0..ac { if l.alts[af + i].root != 0 { return true; } }
            return false;
        }
        if ac == 1 && bc == 1 { return life_alias_deep(p, l, l.alts[af], l.alts[bf]); }
        // Sets are contiguous and sorted ascending by root: O(|A|+|B|) shared-root check first.
        var need_deep = false;
        var ia = 0; var ib = 0;
        while ia < ac && ib < bc {
            let x: const LifeAlt& = l.alts[af + ia];
            let y: const LifeAlt& = l.alts[bf + ib];
            if x.root == 0 { ia += 1; continue; }
            if y.root == 0 { ib += 1; continue; }
            if !need_deep && (!x.exact || !y.exact || l.roots[x.root].class_frame >= 0 || l.roots[y.root].class_frame >= 0) { need_deep = true; }
            if x.root == y.root {
                if !(x.exact && y.exact && x.component >= 0 && y.component >= 0 && x.component != y.component) { return true; }
                var jb = ib + 1;
                while jb < bc && l.alts[bf + jb].root == x.root {
                    let y2: const LifeAlt& = l.alts[bf + jb];
                    if !(x.exact && y2.exact && x.component >= 0 && y2.component >= 0 && x.component != y2.component) { return true; }
                    jb += 1;
                }
                ia += 1;
            } else if x.root < y.root { ia += 1; } else { ib += 1; }
        }
        if !need_deep {
            while ia < ac {
                let x: const LifeAlt& = l.alts[af + ia];
                if x.root != 0 && (!x.exact || l.roots[x.root].class_frame >= 0) { need_deep = true; break; }
                ia += 1;
            }
        }
        if !need_deep {
            while ib < bc {
                let y: const LifeAlt& = l.alts[bf + ib];
                if y.root != 0 && (!y.exact || l.roots[y.root].class_frame >= 0) { need_deep = true; break; }
                ib += 1;
            }
        }
        if !need_deep { return false; }
        for i in 0..ac {
            let x = l.alts[af + i];
            if x.root == 0 { continue; }
            for j in 0..bc {
                let y = l.alts[bf + j];
                if y.root == 0 || x.root == y.root { continue; }
                if life_alias_deep(p, l, x, y) { return true; }
            }
        }
        return false;
    }
    if query == 6 {
        if index >= base || l.sets[set].count != 1 { return false; }
        let a = l.alts[l.sets[set].first];
        if !a.exact || a.root == 0 { return false; }
        if a.root == subject { return l.map_roots[sets + index] >= 0 || a.component < 0; }
        let nested = l.roots[a.root].class_frame;
        if nested >= 0 && l.frames[nested].active { return life_class_query_roots(p, l, nested, l.roots[a.root].class_index, 6, subject, false); }
        return false;
    }
    let subj_alt = LifeAlt { root: subject as i32, exact: flag };
    var at = l.sets[set].first;
    while at >= 0 { let a = l.alts[at]; if life_alias_deep(p, l, a, subj_alt) { return true; } at = a.next; }
    return false;
}
recursive fn life_class_query_roots(p: Program&, l: Lifetimes&, frame: i64, index: i64, query: i64, subject: i64, flag: bool) -> bool {
    if l.in_class_check && frame != l.chk_island { l.chk_saw_unsealed = true; l.chk_dep_overflow = true; }
    let at = life_assume_probe(l, frame, query, index, subject, flag);
    if at < 0 {
        if at == -2 { return true; }
        if at == -4 || at == -3 && (query == 5 || query == 7) { return life_cautious(query); }
        return false;
    }
    // The call's roots are read as its caller reads them: in that island.
    let island = l.island; l.island = l.frames[l.frames[frame].parent].island;
    let serial = l.any_serial;
    if l.chk_dep_recording { l.classify_serial += 1; l.any_serial = l.classify_serial; }
    else { l.any_serial = l.frames[frame].map_serial; }
    let answer = life_class_answer_roots(p, l, frame, l.frames[frame].map_base, query, index, subject, flag);
    l.island = island; l.any_serial = serial;
    life_assume_close(l, at, answer);
    return answer;
}
// life_alias where either root may be a class root.
recursive fn life_alias_deep(p: Program&, l: Lifetimes&, a: LifeAlt, b: LifeAlt) -> bool {
    if a.root == 0 || b.root == 0 { return false; }
    if l.roots[a.root].param_frame >= 0 {
        if !l.frames[l.roots[a.root].param_frame].active || l.roots[a.root].depth < l.roots[b.root].depth { return false; }
        if a.target_type >= 0 && !a.byteview && b.exact && !b.byteview && l.roots[b.root].class_frame < 0 && l.roots[b.root].type_id >= 0 && !life_contains_memo(p, l, l.roots[b.root].type_id, a.target_type as i64) { return false; }
        return true;
    }
    if l.roots[b.root].param_frame >= 0 {
        if !l.frames[l.roots[b.root].param_frame].active || l.roots[b.root].depth < l.roots[a.root].depth { return false; }
        if b.target_type >= 0 && !b.byteview && a.exact && !a.byteview && l.roots[a.root].class_frame < 0 && l.roots[a.root].type_id >= 0 && !life_contains_memo(p, l, l.roots[a.root].type_id, b.target_type as i64) { return false; }
        return true;
    }
    if a.root == b.root { return !(a.exact && b.exact && a.component >= 0 && b.component >= 0 && a.component != b.component); }
    if life_is_global_bound(l, a) && !a.byteview && b.exact && !b.byteview && b.root != 0 {
        var bty = b.target_type as i64;
        if bty < 0 {
            if l.roots[b.root].class_frame < 0 { bty = l.roots[b.root].type_id; }
            else if l.roots[b.root].class_parent >= 0 { bty = l.roots[b.root].class_type; }
            else { bty = l.roots[b.root].class_pointee; }
        }
        if bty >= 0 && !life_globals_contain(p, l, bty) { return false; }
        if a.target_type >= 0 {
            if l.roots[b.root].class_frame < 0 {
                if l.roots[b.root].type_id >= 0 && !life_contains_memo(p, l, l.roots[b.root].type_id, a.target_type as i64) { return false; }
            } else if bty >= 0 && !life_contains_memo(p, l, bty, a.target_type as i64) && !life_contains_memo(p, l, a.target_type as i64, bty) {
                return false;
            }
        }
    }
    if life_is_global_bound(l, b) && !b.byteview && a.exact && !a.byteview && a.root != 0 {
        var aty = a.target_type as i64;
        if aty < 0 {
            if l.roots[a.root].class_frame < 0 { aty = l.roots[a.root].type_id; }
            else if l.roots[a.root].class_parent >= 0 { aty = l.roots[a.root].class_type; }
            else { aty = l.roots[a.root].class_pointee; }
        }
        if aty >= 0 && !life_globals_contain(p, l, aty) { return false; }
        if b.target_type >= 0 {
            if l.roots[a.root].class_frame < 0 {
                if l.roots[a.root].type_id >= 0 && !life_contains_memo(p, l, l.roots[a.root].type_id, b.target_type as i64) { return false; }
            } else if aty >= 0 && !life_contains_memo(p, l, aty, b.target_type as i64) && !life_contains_memo(p, l, b.target_type as i64, aty) {
                return false;
            }
        }
    }
    if !a.exact && l.roots[a.root].depth >= l.roots[b.root].depth { return true; }
    if !b.exact && l.roots[b.root].depth >= l.roots[a.root].depth { return true; }
    return life_class_alias(p, l, a, b);
}
inline fn life_mask_has(mask: i64, index: i64) -> bool {
    if mask == 0 { return false; }
    return mask == -1 || index < 62 && ((mask >> index) & 1) != 0;
}
// The places a store or a shrink through these places may land in: beside
// each storage class, the argument classes a reference read out as it may
// be (class_mask), exactly, as the read's value named them before.
fn life_place_candidates(l: Lifetimes&, places: i64) -> i64 {
    if l.island == 0 || places == 0 { return places; }
    var at = l.sets[places].first; var found = false;
    while at >= 0 { let a = l.alts[at]; at = a.next; if a.exact && l.roots[a.root].class_mask != 0 { found = true; break; } }
    if !found { return places; }
    var out = LifeBuild { set: places }; at = l.sets[places].first;
    while at >= 0 {
        let a = l.alts[at]; at = a.next; let mask = l.roots[a.root].class_mask; let owner = l.roots[a.root].class_frame;
        if !a.exact || mask == 0 || owner < 0 || !l.frames[owner].active { continue; }
        for index in 0..l.frames[owner].class_base {
            if life_mask_has(mask, index) { life_build_add_alt(l, out, LifeAlt { root: (l.frames[owner].classes + index) as i32 }); }
        }
    }
    return life_build_end(l, out);
}
// Two different roots that the depths do not decide, one a class root: two
// classes of one frame are asked of its call; a class and a root of no
// frame (a global, another frame's class) likewise. A class root never
// stands for storage of its own frame's body.
recursive fn life_class_alias(p: Program&, l: Lifetimes&, a: LifeAlt, b: LifeAlt) -> bool {
    var fa = l.roots[a.root].class_frame; if fa >= 0 && !l.frames[fa].active { fa = -1; }
    var fb = l.roots[b.root].class_frame; if fb >= 0 && !l.frames[fb].active { fb = -1; }
    // A by-value holder parameter whose views are not of one array exactly
    // only bounds those views inside the callee body (upstream RootArg::heldexact).
    if fa >= 0 && l.roots[a.root].class_index < l.frames[fa].class_base && !l.roots[a.root].class_one && l.roots[a.root].class_holder >= 0 &&
       l.roots[a.root].depth >= l.roots[b.root].depth { return true; }
    if fb >= 0 && l.roots[b.root].class_index < l.frames[fb].class_base && !l.roots[b.root].class_one && l.roots[b.root].class_holder >= 0 &&
       l.roots[b.root].depth >= l.roots[a.root].depth { return true; }
    if fa >= 0 && fa == fb {
        // A reference read out as a storage class may be to an argument
        // class whose type can hold its pointee (class_mask).
        let n = l.frames[fa].class_base; let ia = l.roots[a.root].class_index; let ib = l.roots[b.root].class_index;
        if ia < n && ib >= n && b.exact && life_mask_has(l.roots[b.root].class_mask, ia) { return true; }
        if ib < n && ia >= n && a.exact && life_mask_has(l.roots[a.root].class_mask, ib) { return true; }
        // Two classes that each stand for one root stand for different ones.
        if l.roots[a.root].class_one && l.roots[b.root].class_one { return false; }
        var low = l.roots[a.root].class_index; var high = l.roots[b.root].class_index;
        if low > high { let swap = low; low = high; high = swap; }
        return life_class_query_roots(p, l, fa, low, 4, high, false);
    }
    // One root that is not at depth 0 is no storage at depth 0.
    if fa >= 0 && l.roots[a.root].class_one && l.roots[a.root].depth > 0 && l.roots[b.root].depth == 0 { return false; }
    if fb >= 0 && l.roots[b.root].class_one && l.roots[b.root].depth > 0 && l.roots[a.root].depth == 0 { return false; }
    // (What some storage holds may be any global: asking of each global apart
    // made a question per storage class and global.)
    if fa >= 0 && l.roots[b.root].frame == 0 {
        if l.roots[a.root].class_index >= l.frames[fa].class_base {
            var aty = a.target_type as i64; if aty < 0 && l.roots[a.root].class_parent >= 0 { aty = l.roots[a.root].class_type; }
            if a.exact && !a.byteview && aty >= 0 {
                if b.exact && !b.byteview && l.roots[b.root].class_frame < 0 && l.roots[b.root].type_id >= 0 && !life_contains_memo(p, l, l.roots[b.root].type_id, aty) { return false; }
                if life_is_global_bound(l, b) && !b.byteview && !life_globals_contain(p, l, aty) { return false; }
            }
            return true;
        }
        return life_class_query_roots(p, l, fa, l.roots[a.root].class_index, 3, b.root, b.exact);
    }
    if fb >= 0 && l.roots[a.root].frame == 0 {
        if l.roots[b.root].class_index >= l.frames[fb].class_base {
            var bty = b.target_type as i64; if bty < 0 && l.roots[b.root].class_parent >= 0 { bty = l.roots[b.root].class_type; }
            if b.exact && !b.byteview && bty >= 0 {
                if a.exact && !a.byteview && l.roots[a.root].class_frame < 0 && l.roots[a.root].type_id >= 0 && !life_contains_memo(p, l, l.roots[a.root].type_id, bty) { return false; }
                if life_is_global_bound(l, a) && !a.byteview && !life_globals_contain(p, l, bty) { return false; }
            }
            return true;
        }
        return life_class_query_roots(p, l, fb, l.roots[b.root].class_index, 3, a.root, a.exact);
    }
    return false;
}
// Whether a holder of type `holder` kept in storage of type `storage` may
// view grow-shrink elements there (the type walk of life_gs_value).
fn life_gs_holder(p: Program&, l: Lifetimes&, storage: i64, holder: i64, byteview: bool) -> bool {
    var types: i64[>..] = []; if storage >= 0 { types.push(storage); }
    var index = 0;
    while index < types.len {
        let owner: const Type& = p.types[types[index]]; index += 1;
        if owner.kind == TY_ARRAY {
            if owner.array_kind == A_GROWSHRINK && (byteview || life_holder_views(p, l, holder, owner.element)) { return true; }
            if owner.element >= 0 { var seen = false; for old in types { if old == owner.element { seen = true; } } if !seen { types.push(owner.element); } }
        } else if owner.kind == TY_STRUCT || owner.kind == TY_ENUM {
            var field = owner.first;
            while field >= 0 { let ft = p.nodes[field].type_id; var seen = ft < 0; for old in types { if old == ft { seen = true; } } if !seen { types.push(ft); } field = p.nodes[field].next; }
        }
    }
    return false;
}
// Queries 0, 1 and 2, which read the types of the roots a class stands for.
recursive fn life_class_answer(p: Program&, l: Lifetimes&, frame: i64, sets: i64, query: i64, index: i64, subject: i64, flag: bool) -> bool {
    if query >= 3 { return life_class_answer_roots(p, l, frame, sets, query, index, subject, flag); }
    let base = l.frames[frame].class_base; var set = 0;
    if index < 3 * base { set = life_class_set(p, l, base, sets, index); }
    else { set = life_typed_set(p, l, l.frames[frame].classes, base, sets, -1, l.frames[frame].classes + index); }
    var q0_slot_safe = false;
    if query == 0 {
        let cr = l.frames[frame].classes + index;
        var cty: i64 = -1;
        if index < base { cty = l.roots[cr].class_pointee; }
        else if l.roots[cr].class_parent >= 0 { cty = l.roots[cr].class_type; }
        if cty >= 0 && !life_gs_contains(p, l, cty, subject, flag) { q0_slot_safe = true; }
    }
    var at = l.sets[set].first;
    while at >= 0 {
        let a = l.alts[at]; at = a.next;
        if a.root == 0 { continue; }
        if a.slotread && (query == 1 || query == 0 && q0_slot_safe && !a.byteview) { continue; }
        if a.component < 0 && l.roots[a.root].class_frame >= 0 {
            if life_class_query(p, l, a.root, query, subject, flag || a.byteview) { return true; }
            continue;
        }
        let storage = life_alt_type(p, l, a);
        if query == 0 && life_gs_contains(p, l, storage, subject, flag || a.byteview) { return true; }
        if query == 1 && life_gs_holder(p, l, storage, subject, flag || a.byteview) { return true; }
        if query == 2 && life_one_array(p, l, storage, subject) { return true; }
    }
    return false;
}
recursive fn life_class_query(p: Program&, l: Lifetimes&, root: i64, query: i64, subject: i64, flag: bool) -> bool {
    let frame = l.roots[root].class_frame; let index = l.roots[root].class_index;
    if !l.frames[frame].active { return false; }
    if l.in_class_check && frame != l.chk_island { l.chk_saw_unsealed = true; l.chk_dep_overflow = true; }
    let at = life_assume_probe(l, frame, query, index, subject, flag);
    if at < 0 {
        if at == -2 { return true; }
        if at == -4 { return life_cautious(query); }
        return false;
    }
    let island = l.island; l.island = l.frames[l.frames[frame].parent].island;
    let serial = l.any_serial;
    if l.chk_dep_recording { l.classify_serial += 1; l.any_serial = l.classify_serial; }
    else { l.any_serial = l.frames[frame].map_serial; }
    let answer = life_class_answer(p, l, frame, l.frames[frame].map_base, query, index, subject, flag);
    l.island = island; l.any_serial = serial;
    life_assume_close(l, at, answer);
    return answer;
}
// Whether a reference to `pointee` through this alternative may point into
// grow-shrink elements.
fn life_alt_gs(p: Program&, l: Lifetimes&, alt: LifeAlt, pointee: i64) -> bool {
    if l.class_frames > 0 && alt.component < 0 && l.roots[alt.root].class_frame >= 0 { return life_class_query(p, l, alt.root, 0, pointee, alt.byteview); }
    if alt.root == l.globals_root { return life_globals_gs(p, l, pointee, alt.byteview); }
    return life_gs_contains(p, l, life_alt_type(p, l, alt), pointee, alt.byteview);
}
// Whether two exact alternatives name the same storage: one root and
// component, or a class root that stands for exactly the other's root.
fn life_exact_same(p: Program&, l: Lifetimes&, a: LifeAlt, b: LifeAlt) -> bool {
    if !a.exact || !b.exact || a.component != b.component { return false; }
    if a.root == b.root { return true; }
    if l.class_frames == 0 { return false; }
    let fa = l.roots[a.root].class_frame; let fb = l.roots[b.root].class_frame;
    if fa >= 0 && l.frames[fa].active && fb < 0 { return life_class_query_roots(p, l, fa, l.roots[a.root].class_index, 6, b.root, false); }
    if fb >= 0 && l.frames[fb].active && fa < 0 { return life_class_query_roots(p, l, fb, l.roots[b.root].class_index, 6, a.root, false); }
    return false;
}
fn life_alias(p: Program&, l: Lifetimes&, a: LifeAlt, b: LifeAlt) -> bool {
    if a.root == 0 || b.root == 0 { return false; }
    if l.roots[a.root].param_frame >= 0 {
        if !l.frames[l.roots[a.root].param_frame].active || l.roots[a.root].depth < l.roots[b.root].depth { return false; }
        if a.target_type >= 0 && !a.byteview && b.exact && !b.byteview && l.roots[b.root].class_frame < 0 && l.roots[b.root].type_id >= 0 && !life_contains_memo(p, l, l.roots[b.root].type_id, a.target_type as i64) { return false; }
        return true;
    }
    if l.roots[b.root].param_frame >= 0 {
        if !l.frames[l.roots[b.root].param_frame].active || l.roots[b.root].depth < l.roots[a.root].depth { return false; }
        if b.target_type >= 0 && !b.byteview && a.exact && !a.byteview && l.roots[a.root].class_frame < 0 && l.roots[a.root].type_id >= 0 && !life_contains_memo(p, l, l.roots[a.root].type_id, b.target_type as i64) { return false; }
        return true;
    }
    // Two known components of one root owner are separate storage.
    if a.root == b.root { return !(a.exact && b.exact && a.component >= 0 && b.component >= 0 && a.component != b.component); }
    if life_is_global_bound(l, a) && !a.byteview && b.exact && !b.byteview && b.root != 0 {
        var bty = b.target_type as i64;
        if bty < 0 {
            if l.roots[b.root].class_frame < 0 { bty = l.roots[b.root].type_id; }
            else if l.roots[b.root].class_parent >= 0 { bty = l.roots[b.root].class_type; }
            else { bty = l.roots[b.root].class_pointee; }
        }
        if bty >= 0 && !life_globals_contain(p, l, bty) { return false; }
        if a.target_type >= 0 {
            if l.roots[b.root].class_frame < 0 {
                if l.roots[b.root].type_id >= 0 && !life_contains_memo(p, l, l.roots[b.root].type_id, a.target_type as i64) { return false; }
            } else if bty >= 0 && !life_contains_memo(p, l, bty, a.target_type as i64) && !life_contains_memo(p, l, a.target_type as i64, bty) {
                return false;
            }
        }
    }
    if life_is_global_bound(l, b) && !b.byteview && a.exact && !a.byteview && a.root != 0 {
        var aty = a.target_type as i64;
        if aty < 0 {
            if l.roots[a.root].class_frame < 0 { aty = l.roots[a.root].type_id; }
            else if l.roots[a.root].class_parent >= 0 { aty = l.roots[a.root].class_type; }
            else { aty = l.roots[a.root].class_pointee; }
        }
        if aty >= 0 && !life_globals_contain(p, l, aty) { return false; }
        if b.target_type >= 0 {
            if l.roots[a.root].class_frame < 0 {
                if l.roots[a.root].type_id >= 0 && !life_contains_memo(p, l, l.roots[a.root].type_id, b.target_type as i64) { return false; }
            } else if aty >= 0 && !life_contains_memo(p, l, aty, b.target_type as i64) && !life_contains_memo(p, l, b.target_type as i64, aty) {
                return false;
            }
        }
    }
    if !a.exact && l.roots[a.root].depth >= l.roots[b.root].depth { return true; }
    if !b.exact && l.roots[b.root].depth >= l.roots[a.root].depth { return true; }
    // What a class root stands for is asked of its frame's call.
    if l.class_frames > 0 && (l.roots[a.root].class_frame >= 0 || l.roots[b.root].class_frame >= 0) { return life_class_alias(p, l, a, b); }
    return false;
}
fn life_overlaps(p: Program&, l: Lifetimes&, a: i64, b: i64, slot_safe: bool = false) -> bool {
    var ai = l.sets[a].first;
    while ai >= 0 { let x = l.alts[ai]; if life_alt_overlaps(p, l, x, b, slot_safe) { return true; } ai = x.next; }
    return false;
}
// life_overlaps for a set of the one alternative x.
fn life_alt_overlaps(p: Program&, l: Lifetimes&, x: LifeAlt, b: i64, slot_safe: bool = false) -> bool {
    if slot_safe && x.slotread { return false; }
    var bi = l.sets[b].first;
    while bi >= 0 { let y = l.alts[bi]; if life_alias(p, l, x, y) { return true; } bi = y.next; }
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
inline fn life_walk_hash(root: i64, ty: i64, mask: i64) -> i64 {
    var h: u64 = (root as! u64) * 11400714819323198485 ^ (ty as! u64) * 14029467366897019727;
    h ^= h >> 29;
    return (h & (mask as! u64)) as i64;
}
fn life_walk_set_has(table: const LifeWalkSlot[>..]&, gen: i64, root: i64, ty: i64) -> bool {
    if table.len == 0 { return false; }
    let mask = table.len - 1; let g = gen as i32; let r32 = root as i32; let t32 = ty as i32;
    var slot = life_walk_hash(root, ty, mask);
    loop {
        let s: const LifeWalkSlot& = table[slot];
        if s.gen != g { return false; }
        if s.root == r32 && s.type_id == t32 { return true; }
        slot = (slot + 1) & mask;
    }
    return false;
}
fn life_walk_set_rehash(table: LifeWalkSlot[>..]&, count: i64, gen: i64) {
    var size: i64 = 256; while size < 4 * (count + 1) { size <<= 1; }
    var old: LifeWalkSlot[>..] = []; old.append(table);
    table.clear(); table.resize(size, LifeWalkSlot {});
    let g = gen as i32; let mask = size - 1;
    for s in old {
        if s.gen != g { continue; }
        var slot = life_walk_hash(s.root as i64, s.type_id as i64, mask);
        while table[slot].gen == g { slot = (slot + 1) & mask; }
        table[slot] = s;
    }
}
fn life_walk_set_add(table: LifeWalkSlot[>..]&, count: i64&, gen: i64, root: i64, ty: i64) -> bool {
    if 2 * (count + 1) >= table.len { life_walk_set_rehash(table, count, gen); }
    let mask = table.len - 1; let g = gen as i32; let r32 = root as i32; let t32 = ty as i32;
    var slot = life_walk_hash(root, ty, mask);
    loop {
        let s: const LifeWalkSlot& = table[slot];
        if s.gen != g {
            table[slot] = LifeWalkSlot { root: r32, type_id: t32, gen: g };
            count += 1;
            return true;
        }
        if s.root == r32 && s.type_id == t32 { return false; }
        slot = (slot + 1) & mask;
    }
    return false;
}
fn life_mark_future_globals(p: Program&, l: Lifetimes&) {
    var same = l.future_global_gen > 0;
    var matched: i64 = 0;
    if same {
        for idx in l.future_floor..l.future_count {
            let future: const LifeFuture& = l.futures[idx];
            if !life_future_reachable(l, idx, future) { continue; }
            if matched >= l.last_future_nodes.len || future.node != l.last_future_nodes[matched] || future.last != l.last_future_lasts[matched] {
                same = false; break;
            }
            matched += 1;
        }
        if same && matched == l.last_future_nodes.len { return; }
    }
    l.last_future_nodes.clear(); l.last_future_lasts.clear();
    if l.global_future_mark.len < p.symbols.len { l.global_future_mark.resize(p.symbols.len, 0); }
    l.body_walks += 1; let walk = l.body_walks;
    l.future_global_gen = walk;
    for idx in l.future_floor..l.future_count {
        let future: const LifeFuture& = l.futures[idx];
        if !life_future_reachable(l, idx, future) { continue; }
        let fn_n = future.node; let fn_last = future.last;
        l.last_future_nodes.push(fn_n); l.last_future_lasts.push(fn_last);
        if fn_n < 0 { continue; }
        let b = life_body_span(p, l, fn_n, fn_last);
        if l.bodies[b].call_count == 0 {
            let gs = l.bodies[b].globals; let ge = gs + l.bodies[b].global_count;
            for g in gs..ge { l.global_future_mark[l.body_globals[g]] = walk; }
        } else {
            if l.bodies[b].trans_global_count < 0 { life_body_compute_trans_globals(p, l, b); }
            let ts = l.bodies[b].trans_globals; let te = ts + l.bodies[b].trans_global_count;
            for g in ts..te { l.global_future_mark[l.body_trans_globals[g]] = walk; }
        }
    }
}
fn life_target_activation(l: Lifetimes&, target: i64) -> i64 {
    if l.class_frames == 0 { return 0; }
    var target_cf: i64 = -1;
    var ti = l.sets[target].first;
    while ti >= 0 {
        let cf = l.roots[l.alts[ti].root].class_frame;
        if cf >= 0 {
            if !l.frames[cf].active { return -1; }
            if target_cf < 0 { target_cf = cf; } else if target_cf != cf { return -1; }
        }
        ti = l.alts[ti].next;
    }
    if target_cf >= 0 { return l.frames[target_cf].activation; }
    return 0;
}
fn life_shrink_alt_overlaps(p: Program&, l: Lifetimes&, alt: LifeAlt, target: i64, slot_safe: bool, use_safe: bool) -> bool {
    if !slot_safe && (alt.from >= 0 || l.roots[alt.root].class_frame >= 0) { return life_read_overlaps_shrink(p, l, alt, target); }
    if !use_safe { return life_alt_overlaps(p, l, alt, target, slot_safe); }
    if slot_safe && alt.slotread { return false; }
    if l.shrink_ov.len == 0 { l.shrink_ov.resize(4096, LifeOvSlot {}); }
    var fl: u8 = 0;
    if alt.exact { fl |= 1; }
    if alt.byteview { fl |= 2; }
    var h: u64 = ((alt.root as i64) as! u64) * 11400714819323198485 ^ ((alt.component as i64) as! u64) * 14029467366897019727 ^ ((alt.target_type as i64) as! u64) * 1099511628211 ^ (fl as u64) * 2654435761;
    h ^= h >> 29;
    let slot = (h & ((l.shrink_ov.len - 1) as! u64)) as i64;
    let g = l.shrink_safe_gen as i32;
    let s: const LifeOvSlot& = l.shrink_ov[slot];
    if s.gen == g && s.root == alt.root && s.comp == alt.component && s.tt == alt.target_type && s.flags == fl {
        return s.ans;
    }
    let ans = life_alt_overlaps(p, l, alt, target, slot_safe);
    l.shrink_ov[slot] = LifeOvSlot { gen: g, root: alt.root, comp: alt.component, tt: alt.target_type, flags: fl, ans: ans };
    return ans;
}
// For a grow-only shrink, follow a read out of a parameter's class to
// its caller's store record. The alias mask is still used when deciding
// where an operation through a reference may land.
recursive fn life_shrink_alias(p: Program&, l: Lifetimes&, view: LifeAlt, place: LifeAlt) -> bool {
    if view.root == 0 || place.root == 0 { return false; }
    let owner = l.roots[view.root].class_frame;
    let index = l.roots[view.root].class_index;
    let other = l.roots[place.root].class_frame;
    if !l.unknown_stores && !view.byteview && owner >= 0 && l.frames[owner].active && index >= l.frames[owner].class_base &&
       (view.exact || view.from == view.root) && view.root != place.root && place.exact &&
       (other == owner || other < 0 && l.roots[place.root].frame == 0) {
        let extra_read = !view.exact;
        if other == owner {
            return life_class_query_roots(p, l, owner, index, 5, l.roots[place.root].class_index, extra_read);
        }
        return life_class_query_roots(p, l, owner, index, 7, place.root, extra_read);
    }
    if !life_alias(p, l, view, place) { return false; }
    if !l.unknown_stores && view.exact && !view.byteview && view.from > 0 {
        let holder = l.roots[view.from];
        if holder.class_frame < 0 && holder.contents != 0 {
            // A conservative local read candidate can only be the view
            // when something stored in the holder points into this array.
            var at = l.sets[holder.contents].first;
            while at >= 0 {
                let stored = l.alts[at]; at = stored.next;
                if life_alias(p, l, stored, place) { return true; }
            }
            return false;
        }
    }
    return true;
}
fn life_read_overlaps_shrink(p: Program&, l: Lifetimes&, view: LifeAlt, target: i64) -> bool {
    var at = l.sets[target].first;
    while at >= 0 {
        let place = l.alts[at]; at = place.next;
        if life_shrink_alias(p, l, view, place) { return true; }
    }
    return false;
}
fn life_ref_overlaps_array(p: Program&, l: Lifetimes&, refs: i64, places: i64, array: i64, element: i64, slot_safe: bool) -> bool {
    var ai = l.sets[refs].first;
    while ai >= 0 {
        let x = l.alts[ai]; ai = x.next;
        if slot_safe && x.slotread { continue; }
        if x.exact && !x.byteview && x.root != 0 {
            var tx: i64 = x.target_type as i64;
            if tx < 0 {
                let rt: const LifeRoot& = l.roots[x.root];
                if rt.class_frame < 0 {
                    let st = life_alt_type(p, l, x);
                    if st >= 0 && !life_is_ref(p, st) { tx = st; }
                } else if rt.class_parent >= 0 {
                    tx = rt.class_type;
                } else if rt.class_index < l.frames[rt.class_frame].class_base {
                    tx = rt.class_pointee;
                }
            }
            if tx >= 0 && !life_contains_memo(p, l, tx, array) && !life_contains_memo(p, l, element, tx) { continue; }
        }
        if slot_safe {
            if life_alt_overlaps(p, l, x, places, true) { return true; }
        } else if life_read_overlaps_shrink(p, l, x, places) { return true; }
    }
    return false;
}
fn life_points_into(p: Program&, l: Lifetimes&, value: const LifeValue&, places: i64, array: i64, use_safe: bool = false) -> bool {
    if array < 0 || value.type_id < 0 { return false; }
    let t: const Type& = p.types[value.type_id]; let a: const Type& = p.types[array];
    let slot_safe = a.array_kind == A_GROWSHRINK;
    if life_tf_is_ref(p, l, value.type_id) {
        if (life_has_bytes(l, value.refs) || life_contains_memo(p, l, a.element, t.element)) && life_ref_overlaps_array(p, l, value.refs, places, array, a.element, slot_safe) { return true; }
        if slot_safe {
            if t.kind == TY_REF && t.element >= 0 && p.types[t.element].kind == TY_SLICE && life_held_into(p, l, value.refs, t.element, places, a.element, slot_safe, use_safe) { return true; }
        } else if life_tf_holds(p, l, t.element) && life_held_into(p, l, value.refs, t.element, places, a.element, slot_safe, use_safe) { return true; }
    } else if life_tf_holds(p, l, value.type_id) {
        if slot_safe && t.kind != TY_TUPLE { return false; }
        if value.place != 0 { return life_held_into(p, l, value.place, value.type_id, places, a.element, slot_safe, use_safe); }
        return life_overlaps(p, l, value.contents, places, slot_safe);
    }
    return false;
}
fn life_has_bytes(l: Lifetimes&, set: i64) -> bool {
    var at = l.sets[set].first;
    while at >= 0 { if l.alts[at].byteview { return true; } at = l.alts[at].next; }
    return false;
}
fn life_field_killed(l: Lifetimes&, first: i64, field: i64) -> bool {
    var at = first;
    while at >= 0 {
        let kill: const LifeKill& = l.kills[at];
        if kill.field == field { return true; }
        at = kill.next;
    }
    return false;
}
fn life_kill_field(l: Lifetimes&, root: i64, field: i64) {
    let first = l.roots[root].first_kill;
    if life_field_killed(l, first, field) { return; }
    l.roots[root].first_kill = l.kills.len;
    l.kills.push(LifeKill { field: field, next: first });
    l.live_epoch += 1; l.val_kill_epoch += 1;
    if l.roots[root].frame == 0 && l.roots[root].class_frame < 0 { l.global_live_epoch += 1; }
}
// The reference and slice types in a holder's fields, variants and elements,
// excluding any top-level fields in this root's list of active kills.
fn life_holder_scan(p: Program&, l: Lifetimes&, holder: i64, first_kill: i64, out: i64[>..]&) {
    var types: i64[>..] = [holder]; var ti = 0;
    while ti < types.len {
        let ty = types[ti]; ti += 1; let t: const Type& = p.types[ty];
        if t.kind == TY_REF || t.kind == TY_SLICE { out.push(ty); }
        else if t.kind == TY_ARRAY && t.element >= 0 {
            var seen = false; for old in types { if old == t.element { seen = true; } }
            if !seen { types.push(t.element); }
        } else if t.kind == TY_STRUCT || t.kind == TY_ENUM || t.kind == TY_TUPLE {
            var field = t.first;
            while field >= 0 {
                let ft = p.nodes[field].type_id; var seen = ft < 0;
                if ty == holder && first_kill >= 0 && life_field_killed(l, first_kill, field) { seen = true; }
                for old in types { if old == ft { seen = true; } }
                if !seen { types.push(ft); } field = p.nodes[field].next;
            }
        }
    }
}
// Lists a type's reference and slice types in holder_refs, once.
fn life_holder_list(p: Program&, l: Lifetimes&, holder: i64) {
    if l.holder_starts[holder] >= 0 { return; }
    var found: i64[>..] = []; life_holder_scan(p, l, holder, -1, found);
    l.holder_starts[holder] = l.holder_refs.len; l.holder_counts[holder] = found.len; l.holder_refs.append(found);
}
fn life_held_into(p: Program&, l: Lifetimes&, owners: i64, holder_type: i64, target: i64, element: i64, slot_safe: bool, use_safe: bool = false, settled: bool = false) -> bool {
    l.last_walk_global = false;
    var slot: i64 = -1;
    let target_act = life_target_activation(l, target);
    let memo_ok = !settled && l.types_frozen && target_act >= 0;
    if memo_ok {
        if l.held_walks.len == 0 { l.held_walks.resize(65536, LifeWalkMemo {}); }
        var mh: u64 = (owners as! u64) * 11400714819323198485 ^ (holder_type as! u64) * 14029467366897019727 ^ (target as! u64) * 1099511628211 ^ (element as! u64) * 2654435761;
        mh ^= mh >> 29;
        slot = (mh & ((l.held_walks.len - 1) as! u64)) as i64;
        let memo: const LifeWalkMemo& = l.held_walks[slot];
        if memo.owners == owners && memo.holder == holder_type && memo.target == target && memo.element == element && memo.slot_safe == slot_safe {
            if l.class_frames > 0 {
                if memo.global_only {
                    if memo.epoch == l.global_live_epoch && memo.island_act == target_act { l.last_walk_global = true; return false; }
                } else if memo.epoch == l.live_epoch && memo.grow_epoch == l.holder_grow_epoch && memo.island_act == target_act {
                    return false;
                }
            } else {
                if memo.epoch == l.live_epoch { return false; }
                var valid = true;
                for i in 0..memo.count {
                    let saved: const LifeWalkRoot& = l.walk_memo_roots[memo.first + i];
                    let root: const LifeRoot& = l.roots[saved.root];
                    if root.live_contents != saved.contents || root.first_kill != saved.kills { valid = false; break; }
                }
                if valid { l.held_walks[slot].epoch = l.live_epoch; return false; }
            }
        }
    }
    l.walk_work.clear(); l.walk_gen += 1; l.walk_seen_count = 0;
    var skipped_safe = false; var all_global = true; var at = l.sets[owners].first;
    while at >= 0 {
        let alt = l.alts[at]; at = alt.next;
        let ar: const LifeRoot& = l.roots[alt.root];
        if ar.class_frame >= 0 || ar.frame != 0 { all_global = false; }
        if use_safe && life_walk_set_has(l.shrink_safe, l.shrink_safe_gen, alt.root as i64, holder_type) { skipped_safe = true; continue; }
        if life_walk_set_add(l.walk_seen, l.walk_seen_count, l.walk_gen, alt.root as i64, holder_type) {
            l.walk_work.push(LifeWalk { root: alt.root, type_id: holder_type });
        }
    }
    if l.walk_work.len == 0 {
        let eff_g = all_global && (!skipped_safe || l.shrink_safe_global);
        l.last_walk_global = eff_g;
        if slot >= 0 && l.class_frames > 0 {
            let memo: LifeWalkMemo& = l.held_walks[slot];
            memo.owners = owners; memo.holder = holder_type; memo.target = target;
            memo.element = element; memo.slot_safe = slot_safe;
            memo.global_only = eff_g;
            if eff_g { memo.epoch = l.global_live_epoch; } else { memo.epoch = l.live_epoch; }
            memo.grow_epoch = l.holder_grow_epoch; memo.island_act = target_act;
        }
        return false;
    }
    let in_class = l.class_frames > 0;
    var current = 0;
    while current < l.walk_work.len {
        let held = l.walk_work[current]; current += 1; if held.type_id < 0 { continue; }
        let root: const LifeRoot& = l.roots[held.root];
        let live_contents = if settled { root.contents } else { root.live_contents }; let class_frame = root.class_frame;
        if class_frame >= 0 || root.frame != 0 { all_global = false; }
        if live_contents == 0 && !(class_frame >= 0 && l.frames[class_frame].stored_first >= 0) { continue; }
        var first_kill: i64 = -1;
        if !settled && root.first_kill >= 0 && life_same(p, root.type_id, held.type_id) { first_kill = root.first_kill; }
        let listed = l.types_frozen && held.type_id < l.holder_starts.len && (first_kill < 0 || root.type_id == held.type_id);
        var first = 0; var count = 0;
        if listed && first_kill >= 0 {
            let kill: LifeKill& = l.kills[first_kill];
            if kill.first < 0 {
                l.walk_scanned.clear(); life_holder_scan(p, l, held.type_id, first_kill, l.walk_scanned);
                kill.first = l.holder_refs.len; kill.count = l.walk_scanned.len; l.holder_refs.append(l.walk_scanned);
            }
            first = kill.first; count = kill.count;
        } else if listed {
            life_holder_list(p, l, held.type_id);
            first = l.holder_starts[held.type_id]; count = l.holder_counts[held.type_id];
        } else {
            l.walk_scanned.clear(); life_holder_scan(p, l, held.type_id, first_kill, l.walk_scanned); count = l.walk_scanned.len;
        }
        l.walk_elems.clear();
        var any_reaches = false; var any_leads = false; var has_any_ref = false;
        for item in 0..count {
            var ty = 0; if listed { ty = l.holder_refs[first + item]; } else { ty = l.walk_scanned[item]; }
            let t: const Type& = p.types[ty];
            if t.kind == TY_REF && t.length_storage >= 0 { continue; }
            has_any_ref = true;
            let elem = t.element;
            var dup = false;
            for e in l.walk_elems { if (e.type_id as i64) == elem { dup = true; break; } }
            if dup { continue; }
            var fl: u8 = 0;
            if life_contains_memo(p, l, element, elem) { fl |= 1; any_reaches = true; }
            if life_tf_holds(p, l, elem) { fl |= 2; any_leads = true; }
            l.walk_elems.push(LifeWalkElem { type_id: elem as i32, flags: fl });
        }
        if !has_any_ref { continue; }
        var holding = live_contents;
        if class_frame >= 0 && l.frames[class_frame].stored_first >= 0 { holding = life_join(l, holding, life_class_stores(p, l, held.root)); }
        if !any_reaches && !any_leads && !life_has_bytes(l, holding) { continue; }
        var ai = l.sets[holding].first;
        while ai >= 0 {
            let orig = l.alts[ai]; ai = orig.next;
            let orig_cf = l.roots[orig.root].class_frame;
            if orig_cf < 0 {
                if l.roots[orig.root].frame != 0 { all_global = false; }
                let can_lead = any_leads && (settled || !in_class || l.roots[orig.root].live_contents != 0);
                if orig.byteview {
                    if life_shrink_alt_overlaps(p, l, orig, target, slot_safe, use_safe) { return true; }
                    if !can_lead { continue; }
                    for e in l.walk_elems {
                        if (e.flags & 2) == 0 { continue; }
                        let elem = e.type_id as i64;
                        if use_safe && life_walk_set_has(l.shrink_safe, l.shrink_safe_gen, orig.root as i64, elem) { skipped_safe = true; }
                        else if life_walk_set_add(l.walk_seen, l.walk_seen_count, l.walk_gen, orig.root as i64, elem) {
                            l.walk_work.push(LifeWalk { root: orig.root, type_id: elem });
                        }
                    }
                    continue;
                }
                if l.roots[orig.root].param_frame >= 0 {
                    if !l.frames[l.roots[orig.root].param_frame].active { skipped_safe = true; continue; }
                    if any_reaches && life_shrink_alt_overlaps(p, l, orig, target, slot_safe, use_safe) { return true; }
                    continue;
                }
                let stype = l.roots[orig.root].type_id;
                if stype < 0 { continue; }
                let orig_tt = orig.target_type as i64;
                var may_reach = any_reaches;
                if may_reach && orig_tt >= 0 && !life_contains_memo(p, l, element, orig_tt) { may_reach = false; }
                let overlaps = may_reach && life_shrink_alt_overlaps(p, l, orig, target, slot_safe, use_safe);
                if !overlaps && !can_lead { continue; }
                let gbound = life_is_global_bound(l, orig);
                for e in l.walk_elems {
                    let want_ov = overlaps && (e.flags & 1) != 0;
                    let want_ld = can_lead && (e.flags & 2) != 0;
                    if !want_ov && !want_ld { continue; }
                    let elem = e.type_id as i64;
                    if orig_tt >= 0 && !life_same(p, orig_tt, elem) { continue; }
                    if gbound && !life_globals_contain(p, l, elem) { continue; }
                    if !life_contains_memo(p, l, stype, elem) { continue; }
                    if want_ov { return true; }
                    if use_safe && life_walk_set_has(l.shrink_safe, l.shrink_safe_gen, orig.root as i64, elem) { skipped_safe = true; }
                    else if life_walk_set_add(l.walk_seen, l.walk_seen_count, l.walk_gen, orig.root as i64, elem) {
                        l.walk_work.push(LifeWalk { root: orig.root, type_id: elem });
                    }
                }
            } else {
                all_global = false;
                let orig_tt = orig.target_type as i64;
                let gbound = !orig.byteview && life_is_global_bound(l, orig);
                for e in l.walk_elems {
                    let reaches = (e.flags & 1) != 0;
                    let leads = (e.flags & 2) != 0;
                    if !orig.byteview && !reaches && !leads { continue; }
                    let elem = e.type_id as i64;
                    if !orig.byteview {
                        if orig_tt >= 0 && !life_same(p, orig_tt, elem) { continue; }
                        if orig.exact && orig.root != 0 && !life_class_holds(p, l, orig.root as i64, elem) { continue; }
                        if gbound && !life_globals_contain(p, l, elem) { continue; }
                    }
                    var alt = orig;
                    if in_class { alt = life_class_narrow(p, l, alt, held.root, elem); }
                    let storage: const LifeRoot& = l.roots[alt.root];
                    if !alt.byteview && storage.class_frame < 0 && !life_contains_memo(p, l, storage.type_id, elem) { continue; }
                    if (alt.byteview || reaches) && life_shrink_alt_overlaps(p, l, alt, target, slot_safe, use_safe) { return true; }
                    if leads && (settled || !in_class || storage.live_contents != 0 || storage.class_frame >= 0 && l.frames[storage.class_frame].stored_first >= 0) {
                        if use_safe && life_walk_set_has(l.shrink_safe, l.shrink_safe_gen, alt.root as i64, elem) { skipped_safe = true; }
                        else if life_walk_set_add(l.walk_seen, l.walk_seen_count, l.walk_gen, alt.root as i64, elem) {
                            l.walk_work.push(LifeWalk { root: alt.root, type_id: elem });
                        }
                    }
                }
            }
        }
    }
    let eff_global = all_global && (!skipped_safe || l.shrink_safe_global);
    if use_safe {
        if !eff_global { l.shrink_safe_global = false; }
        for item in l.walk_work { life_walk_set_add(l.shrink_safe, l.shrink_safe_count, l.shrink_safe_gen, item.root, item.type_id); }
    }
    l.last_walk_global = eff_global;
    if slot >= 0 {
        if in_class {
            let memo: LifeWalkMemo& = l.held_walks[slot];
            memo.owners = owners; memo.holder = holder_type; memo.target = target;
            memo.element = element; memo.slot_safe = slot_safe;
            memo.global_only = eff_global;
            if eff_global { memo.epoch = l.global_live_epoch; } else { memo.epoch = l.live_epoch; }
            memo.grow_epoch = l.holder_grow_epoch; memo.island_act = target_act;
        } else if !skipped_safe && l.walk_work.len <= 32 {
            if l.walk_memo_roots.len + l.walk_work.len > 65536 {
                l.walk_memo_roots.clear();
                for i in 0..l.held_walks.len { l.held_walks[i].owners = -1; }
            }
            let first = l.walk_memo_roots.len;
            for item in l.walk_work {
                let root: const LifeRoot& = l.roots[item.root];
                l.walk_memo_roots.push(LifeWalkRoot { root: item.root, contents: root.live_contents, kills: root.first_kill });
            }
            let memo: LifeWalkMemo& = l.held_walks[slot];
            memo.owners = owners; memo.holder = holder_type; memo.target = target;
            memo.element = element; memo.slot_safe = slot_safe;
            memo.first = first; memo.count = l.walk_work.len; memo.epoch = l.live_epoch; memo.global_only = false;
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
        if op.left >= 0 { work.push(op.left); }
        if op.right >= 0 { work.push(op.right); }
        if op.third >= 0 { work.push(op.third); }
    }
    return true;
}

fn life_index_shrink(p: Program&, l: Lifetimes&, node: i64, receiver: const LifeValue&) {
    if l.discovery { return; }
    var count = p.types.len; if l.types_frozen { count = l.index_types.len; }
    for item in 0..count {
        var id = item; if l.types_frozen { id = l.index_types[item]; }
        let t: const Type& = p.types[id];
        if t.kind != TY_INT || t.index_type < 0 || t.pool < 0 { continue; }
        let owner: const Symbol& = p.symbols[t.pool]; let named = life_pool_places(p, l, t.pool);
        if named == 0 || !life_same(p, receiver.type_id, owner.type_id) { continue; }
        if life_overlaps(p, l, receiver.place, named) {
            life_error(p, l, node, "cannot shrink or replace this array: an index or bound type names it"); return;
        }
    }
}

fn life_shrink_places(p: Program&, l: Lifetimes&, places: i64, array_type: i64) -> i64 {
    if places == 0 || array_type < 0 { return places; }
    let first = l.sets[places].first as i64; let count = l.sets[places].count as i64;
    var drop = false;
    for i in 0..count {
        let a = l.alts[first + i];
        if a.root == 0 { drop = true; break; }
        if !a.byteview {
            if life_is_global_bound(l, a) {
                if !life_globals_contain(p, l, array_type) { drop = true; break; }
                if a.target_type < 0 { drop = true; break; }
                if a.target_type >= 0 && !life_contains_memo(p, l, a.target_type as i64, array_type) && !life_contains_memo(p, l, array_type, a.target_type as i64) { drop = true; break; }
            }
            if a.exact {
                if a.target_type >= 0 && !life_contains_memo(p, l, a.target_type as i64, array_type) && !life_contains_memo(p, l, array_type, a.target_type as i64) { drop = true; break; }
                if l.roots[a.root].class_frame < 0 {
                    let st = life_alt_type(p, l, a);
                    if st >= 0 && !life_is_ref(p, st) && !life_contains_memo(p, l, st, array_type) { drop = true; break; }
                } else if !life_class_holds(p, l, a.root as i64, array_type) { drop = true; break; }
            }
        }
    }
    if !drop { return places; }
    let start = l.scratch.len;
    for i in 0..count {
        var a = l.alts[first + i];
        if a.root == 0 { continue; }
        if !a.byteview {
            if life_is_global_bound(l, a) {
                if !life_globals_contain(p, l, array_type) { continue; }
                if a.target_type >= 0 && !life_contains_memo(p, l, a.target_type as i64, array_type) && !life_contains_memo(p, l, array_type, a.target_type as i64) { continue; }
                if a.target_type < 0 { a.target_type = array_type as i32; }
            }
            if a.exact {
                if a.target_type >= 0 && !life_contains_memo(p, l, a.target_type as i64, array_type) && !life_contains_memo(p, l, array_type, a.target_type as i64) { continue; }
                if l.roots[a.root].class_frame < 0 {
                    let st = life_alt_type(p, l, a);
                    if st >= 0 && !life_is_ref(p, st) && !life_contains_memo(p, l, st, array_type) { continue; }
                } else if !life_class_holds(p, l, a.root as i64, array_type) { continue; }
            }
        }
        a.next = -1; l.scratch.push(a);
    }
    let result = life_list_set(l, start, true);
    l.scratch.resize(start);
    return result;
}
fn life_shrink_error(p: Program&, l: Lifetimes&, node: i64, symbol: i64) {
    var msg: u8[>..] = [];
    msg.append("array shrink invalidates a reference or holder that is used afterward");
    if symbol >= 0 && symbol < p.symbols.len && p.symbols[symbol].name_token >= 0 {
        msg.append(": `"); msg.append(token_text(p, p.symbols[symbol].name_token));
        msg.append("` (declared at "); format_token_location(p, p.symbols[symbol].name_token, msg); msg.push(')');
    }
    msg.append("\n  help: finish using or copy any references/slices into the array before shrinking or clearing it (§5.1)");
    life_error(p, l, node, msg);
}
// Judge these shrinks once every body has been evaluated. A discovered
// global store is relevant even if validation sees a kill before the shrink.
fn life_note_global_shrinks(p: Program&, l: Lifetimes&, node: i64, receiver: const LifeValue&) -> bool {
    var at = l.sets[receiver.place].first; var all_global = true;
    while at >= 0 {
        let alt = l.alts[at]; at = alt.next;
        let symbol = l.roots[alt.root].symbol;
        if !alt.exact || symbol < 0 || (p.symbols[symbol].flags & S_GLOBAL) == 0 {
            all_global = false;
            continue;
        }
        let place = life_alt_set(l, alt);
        var seen = false;
        for old in l.global_shrinks {
            if old.place == place && old.type_id == receiver.type_id { seen = true; break; }
        }
        if !seen {
            l.global_shrinks.push(LifeGlobalShrink { node: node, place: place as i32, type_id: receiver.type_id, frame: l.frame });
        }
    }
    return all_global;
}

fn life_check_global_shrink(p: Program&, l: Lifetimes&, shrink: LifeGlobalShrink) {
    let alt = l.alts[l.sets[shrink.place].first];
    let symbol = l.roots[alt.root].symbol;
    let node = shrink.node;
    let array = p.types[shrink.type_id];
    for index in l.global_cells {
        let cell = l.cells[index];
        if cell.symbol == symbol && alt.component < 0 { continue; }
        let ty = p.symbols[cell.symbol].type_id;
        if ty < 0 { continue; }
        let slot_safe = array.array_kind == A_GROWSHRINK;
        var into = false;
        if life_tf_is_ref(p, l, ty) && life_plain_ref(p, ty) {
            let element = p.types[ty].element;
            into = (life_has_bytes(l, cell.refs) || life_contains_memo(p, l, array.element, element)) &&
                life_ref_overlaps_array(p, l, cell.refs, shrink.place, shrink.type_id, array.element, slot_safe);
            if !into && !slot_safe && life_tf_holds(p, l, element) {
                into = life_held_into(p, l, cell.refs, element, shrink.place, array.element, false, false, true);
            }
        } else if !slot_safe && life_tf_holds(p, l, ty) && l.roots[cell.root].contents != 0 {
            into = life_held_into(p, l, life_root_set(l, cell.root), ty, shrink.place, array.element, false, false, true);
        }
        if into {
            var msg: u8[>..] = [];
            msg.append("cannot ");
            let token = p.nodes[node].token;
            if p.nodes[node].kind == N_ASSIGN { msg.append("assign "); }
            else { msg.append(token_text(p, token)); msg.push(' '); }
            msg.append(token_text(p, p.symbols[symbol].name_token));
            msg.append(": global "); msg.append(token_text(p, p.symbols[cell.symbol].name_token));
            msg.append(" may hold a reference into it (§5.1)");
            life_error(p, l, node, msg);
        }
    }
}
fn life_shrink_array(p: Program&, l: Lifetimes&, node: i64, given_receiver: const LifeValue&, balanced: bool = false) {
    if given_receiver.type_id < 0 { return; }
    let array: const Type& = p.types[given_receiver.type_id];
    if array.kind != TY_ARRAY || array.array_kind == A_LIMITED { return; }
    var receiver = given_receiver;
    receiver.place = life_shrink_places(p, l, given_receiver.place, given_receiver.type_id) as i32;
    if receiver.place == 0 { return; }
    if !l.types_frozen || l.index_types.len > 0 { life_index_shrink(p, l, node, receiver); }
    if !balanced { let eff = LifeEffect { kind: 1, node: node as i32, value: LifeValue { type_id: receiver.type_id, place: receiver.place }, places: receiver.place }; life_effect(p, l, eff); }
    if l.discovery { return; }
    var pool = l.sets[receiver.place].first;
    while array.array_kind == A_GROW && pool >= 0 {
        let pa = l.alts[pool];
        let root: const LifeRoot& = l.roots[pa.root];
        if root.symbol >= 0 {
            let symbol: const Symbol& = p.symbols[root.symbol];
            if symbol.node >= 0 && (p.nodes[symbol.node].flags & F_REUSABLE) != 0 &&
               (pa.byteview || life_same(p, symbol.type_id, receiver.type_id)) {
                life_error(p, l, node, "reusable pool storage cannot shrink: freed slots remain part of its freelist");
            }
        }
        pool = l.alts[pool].next;
    }
    for index in l.hold_floor..l.hold_count {
        let hold: const LifeHold& = l.holds[index]; if balanced && hold.frame != l.frame { continue; } var conflict = false;
        if hold.kind == 7 {
            var ty: i64 = hold.value.type_id; var places: i64 = hold.value.place;
            if ty >= 0 && p.types[ty].kind == TY_REF { places = hold.value.refs; ty = p.types[ty].element; }
            conflict = life_points_into(p, l, hold.value, receiver.place, receiver.type_id);
            var walk = false;
            if ty >= 0 { walk = p.types[ty].kind == TY_ENUM && (p.types[ty].flags & F_VARIABLE_MODE) != 0 || p.types[ty].kind == TY_ARRAY && life_cached_size_class(p, l, ty) > 0; }
            if walk && (life_contains(p, l, array.element, ty) || life_contains(p, l, ty, receiver.type_id)) && life_overlaps(p, l, places, receiver.place) { conflict = true; }
        }
        else if hold.kind == 4 { conflict = life_contains(p, l, array.element, hold.value.type_id) && life_overlaps(p, l, hold.value.place, receiver.place); }
        else if hold.kind != 0 { conflict = life_overlaps(p, l, hold.value.place, receiver.place);
            if hold.kind == 3 { conflict = conflict || life_points_into(p, l, hold.value, receiver.place, receiver.type_id); }
        }
        else { conflict = life_points_into(p, l, hold.value, receiver.place, receiver.type_id); }
        if conflict {
            life_error(p, l, node, "array shrink invalidates a value still needed by the enclosing expression");
        }
    }
    let checked_globals = life_note_global_shrinks(p, l, node, receiver);
    // If no live holder pointed into (receiver.place, receiver.type_id) at this
    // holder_grow_epoch, and no holder has become live or gained references/contents
    // since, no live holder can point into it now.
    if l.future_floor == l.future_count { return; }
    let cacheable = !balanced && l.types_frozen;
    var clean_slot: i64 = -1;
    var fhash: u64 = 1469598103934665603;
    if cacheable && l.class_frames > 0 {
        for fi in l.future_floor..l.future_count {
            let f: const LifeFuture& = l.futures[fi];
            if !life_future_reachable(l, fi, f) { continue; }
            fhash = life_hash_step(fhash, f.node);
            fhash = life_hash_step(fhash, f.last);
            fhash = life_hash_step(fhash, f.frame);
            fhash = life_hash_step(fhash, f.loop_scope);
        }
    }
    if cacheable {
        if l.shrink_clean.len == 0 { l.shrink_clean.resize(4096, LifeShrinkClean {}); }
        var sh: u64 = (receiver.place as! u64) * 11400714819323198485 ^ (receiver.type_id as! u64) * 14029467366897019727;
        sh ^= sh >> 29;
        clean_slot = (sh & ((l.shrink_clean.len - 1) as! u64)) as i64;
        let entry: const LifeShrinkClean& = l.shrink_clean[clean_slot];
        if entry.place == receiver.place && entry.type_id == receiver.type_id && entry.epoch == l.holder_grow_epoch &&
           (entry.all || l.class_frames > 0 && entry.frame == l.frame && entry.fhash == fhash) { return; }
    }
    l.asked.clear();
    var heads: i32[32] = [0; 32];
    var exact_local_shrink = false;
    if l.class_frames > 0 && l.sets[receiver.place].count == 1 {
        let sa = l.alts[l.sets[receiver.place].first];
        if sa.exact && sa.root != 0 && l.roots[sa.root].frame > 0 && l.roots[sa.root].depth > 0 && l.roots[sa.root].class_frame < 0 {
            exact_local_shrink = true;
        }
    }
    var gclean_slot: i64 = -1;
    var target_act: i64 = -1;
    var skip_globals = exact_local_shrink || checked_globals;
    if !skip_globals && cacheable && l.class_frames > 0 {
        target_act = life_target_activation(l, receiver.place);
        if target_act >= 0 {
            if l.global_shrink_clean.len == 0 { l.global_shrink_clean.resize(8192, LifeGlobalShrinkClean {}); }
            var gh: u64 = (receiver.place as! u64) * 11400714819323198485 ^ (receiver.type_id as! u64) * 14029467366897019727 ^ (target_act as! u64) * 1099511628211;
            gh ^= gh >> 29;
            gclean_slot = (gh & ((l.global_shrink_clean.len - 1) as! u64)) as i64;
            let ge: const LifeGlobalShrinkClean& = l.global_shrink_clean[gclean_slot];
            if ge.place == receiver.place && ge.type_id == receiver.type_id && ge.epoch == l.global_live_epoch && ge.island_act == target_act &&
               (ge.all || ge.frame == l.frame && ge.fhash == fhash) {
                skip_globals = true;
            }
        }
    }
    l.shrink_safe_gen += 1; l.shrink_safe_count = 0; l.shrink_safe_global = true;
    var marked_globals = false;
    var any_into = false; var all_checked = true;
    var any_glob_into = false; var all_glob_checked = true; var all_glob_walks_global = true;
    var index = if skip_globals { life_next_local_holder(l, -1) } else { life_next_holder(l, -1) };
    while index >= 0 {
        let candidate = index; index = if skip_globals { life_next_local_holder(l, index) } else { life_next_holder(l, index) };
        let is_glob = l.cell_keys[candidate].global;
        if skip_globals && is_glob { continue; }
        let symbol = l.cells[candidate].symbol;
        let cell_type = p.symbols[symbol].type_id;
        let reference = life_tf_is_ref(p, l, cell_type);
        if !reference && (array.array_kind == A_GROWSHRINK || !life_tf_holds(p, l, cell_type)) { continue; }
        if !life_visible(l, candidate) { continue; }
        if balanced && (l.cells[candidate].frame != l.frame || (p.symbols[symbol].flags & S_PARAMETER) != 0) { continue; }
        let root = l.cells[candidate].root;
        if reference && l.cells[candidate].live_refs == 0 { continue; }
        if !reference && l.roots[root].live_contents == 0 { continue; }
        if l.class_frames > 0 {
            if is_glob && (p.symbols[symbol].flags & S_CAPTURE) == 0 {
                if !marked_globals { life_mark_future_globals(p, l); marked_globals = true; }
                if l.global_future_mark[symbol] != l.future_global_gen { all_checked = false; all_glob_checked = false; continue; }
            } else if !life_used_after(p, l, l.cells[candidate]) { all_checked = false; continue; }
        }
        let place = life_root_set(l, root);
        var a = cell_type; var b = place; var c = -2;
        if reference { a = p.types[cell_type].element; b = l.cells[candidate].live_refs; }
        else { c = l.roots[root].live_contents; }
        var into = false; var known = false; var known_glob = false;
        let bucket = (a ^ (b << 1) ^ (b >> 4) ^ c) & 31;
        var at = heads[bucket];
        while at > 0 {
            let old: const LifeAsked& = l.asked[(at as i64) - 1];
            if old.a == a && old.b == b && old.c == c { known = true; into = old.into; known_glob = old.all_global; break; }
            at = old.next;
        }
        if !known {
            var value = LifeValue { type_id: cell_type as i32 };
            if reference { value.refs = b as i32; } else { value.place = b as i32; value.contents = c as i32; }
            l.last_walk_global = true;
            into = life_points_into(p, l, value, receiver.place, receiver.type_id, true);
            var this_glob = l.last_walk_global;
            if is_glob && reference && this_glob {
                var ri = l.sets[b].first;
                while ri >= 0 {
                    let rr = l.roots[l.alts[ri].root];
                    if rr.class_frame >= 0 || rr.frame != 0 { this_glob = false; break; }
                    ri = l.alts[ri].next;
                }
            }
            if is_glob && !this_glob { all_glob_walks_global = false; }
            if l.asked.len < 64 {
                l.asked.push(LifeAsked { a: a, b: b, c: c, into: into, next: heads[bucket], all_global: this_glob });
                heads[bucket] = l.asked.len as i32;
            }
        } else if is_glob && !known_glob {
            all_glob_walks_global = false;
        }
        if into {
            any_into = true;
            if is_glob { any_glob_into = true; }
            if l.class_frames > 0 || life_used_after(p, l, l.cells[candidate]) {
                life_shrink_error(p, l, node, symbol);
            }
        }
    }
    if gclean_slot >= 0 && !skip_globals && !any_glob_into && all_glob_walks_global {
        l.global_shrink_clean[gclean_slot] = LifeGlobalShrinkClean { place: receiver.place, type_id: receiver.type_id, epoch: l.global_live_epoch, island_act: target_act, frame: l.frame, fhash: fhash, all: all_glob_checked };
    }
    if cacheable && !any_into {
        l.shrink_clean[clean_slot] = LifeShrinkClean { place: receiver.place, type_id: receiver.type_id, epoch: l.holder_grow_epoch, frame: l.frame, fhash: fhash, all: all_checked && !skip_globals };
    }
}
fn life_shrink_agg(p: Program&, l: Lifetimes&, node: i64, receiver: const LifeValue&, balanced: bool) {
    var work: i64[>..] = [receiver.type_id]; var at = 0;
    while at < work.len {
        let ty = work[at]; at += 1; let t: const Type& = p.types[ty];
        if t.kind == TY_ARRAY { var value = receiver; value.type_id = ty as i32; life_shrink_array(p, l, node, value, balanced); }
        else if t.kind == TY_STRUCT || t.kind == TY_ENUM {
            var field = t.first;
            while field >= 0 { let ft = p.nodes[field].type_id; if ft >= 0 && life_cached_size_class(p, l, ft) > 0 { work.push(ft); } field = p.nodes[field].next; }
        }
    }
}
fn life_shrink(p: Program&, l: Lifetimes&, node: i64, given: const LifeValue&, balanced: bool = false) {
    var receiver = given; receiver.place = life_place_candidates(l, given.place) as i32;
    if receiver.type_id < 0 { return; }
    let kind = p.types[receiver.type_id].kind;
    if kind == TY_ARRAY { life_shrink_array(p, l, node, receiver, balanced); return; }
    if kind != TY_STRUCT && kind != TY_ENUM { return; }
    life_shrink_agg(p, l, node, receiver, balanced);
}

fn life_replace(p: Program&, l: Lifetimes&, node: i64, receiver: const LifeValue&) {
    if l.format_holds == 0 && l.nodes_prepared && !l.full_reads &&
       (l.frame <= 0 || l.frames[l.frame].function_node < 0 || (l.hold_flags[l.frames[l.frame].function_node] & FH_FORMAT_RAW) == 0) {
        return;
    }
    let eff = LifeEffect { kind: 8, node: node as i32, value: LifeValue { type_id: receiver.type_id, place: receiver.place }, places: receiver.place };
    life_effect(p, l, eff);
    if l.discovery { return; }
    for index in l.hold_floor..l.hold_count {
        let hold: const LifeHold& = l.holds[index]; if hold.kind != 7 { continue; }
        var ty: i64 = hold.value.type_id; var places: i64 = hold.value.place;
        if ty >= 0 && p.types[ty].kind == TY_REF { places = hold.value.refs; ty = p.types[ty].element; }
        var walk = false;
        if ty >= 0 { walk = p.types[ty].kind == TY_ENUM && (p.types[ty].flags & F_VARIABLE_MODE) != 0 || p.types[ty].kind == TY_ARRAY && life_cached_size_class(p, l, ty) > 0; }
        if walk && life_overlaps(p, l, places, receiver.place) && (life_contains(p, l, receiver.type_id, ty) || life_contains(p, l, ty, receiver.type_id)) {
            life_error(p, l, node, "whole assignment replaces a variable-size value while its parts are being rendered");
        }
    }
}

fn life_grow(p: Program&, l: Lifetimes&, node: i64, receiver: const LifeValue&, known: i64 = -1) {
    if l.build_holds == 0 && l.nodes_prepared && !l.full_reads &&
       (l.frame <= 0 || l.frames[l.frame].function_node < 0 || (l.hold_flags[l.frames[l.frame].function_node] & FH_BUILD_HOLD) == 0) {
        return;
    }
    if !l.discovery && l.build_holds == 0 && l.class_frames == 0 && l.frame > 0 && l.activations < 1073741824 {
        let eff = LifeEffect { kind: 2, node: node as i32, value: LifeValue { place: receiver.place }, places: receiver.place };
        life_offer_once(p, l, eff, known);
        return;
    }
    let eff = LifeEffect { kind: 2, node: node as i32, value: LifeValue { place: receiver.place }, places: receiver.place };
    life_effect(p, l, eff);
    if l.discovery || l.build_holds == 0 { return; }
    for index in l.hold_floor..l.hold_count {
        let hold: const LifeHold& = l.holds[index];
        if (hold.kind == 1 || hold.kind == 2) && life_overlaps(p, l, hold.value.place, receiver.place) {
            life_error(p, l, node, "array growth overlaps a value still under construction in its storage");
        }
    }
}
// Offer a discovery effect once per activation. A replay can pass a leaf
// that it has already looked up and found outstanding. Validation uses this
// shortcut only for recording construct reads, and checks each use separately.
fn life_offer_once(p: Program&, l: Lifetimes&, offer: const LifeEffect&, known: i64) {
    if l.discovery && l.class_frames > 0 && l.island == 0 && life_nearest_recursive(l, l.frame) == 0 { return; }
    // In validation this is the recording of the effect in the frames'
    // effect lists, which have it from then on; what it is checked against
    // is looked at every time, by the caller.
    // stamps: the activation's stamp on the leaf can say the offer was made.
    // compact: the summaries take the read by its leaf (life_read_offer).
    let stamps = (l.discovery || l.class_frames == 0) && l.frame > 0 && l.activations < 1073741824;
    let compact = offer.kind == 3 && l.compact && l.discovery && l.frame > 0;
    if !stamps && !compact { life_effect(p, l, offer); return; }
    var leaf = known; var offered = false;
    if leaf < 0 {
        var leaf_node: i64 = offer.node;
        if l.discovery && l.class_frames > 0 && (offer.kind == 1 || offer.kind == 2 || offer.kind == 3 || offer.kind == 8) { leaf_node = -2; }
        leaf = life_leaf(l, offer.kind, leaf_node, offer.value);
        offered = stamps && life_leaf_offered(l, leaf);
    }
    if !offered {
        let offers = l.offer_count; let cyclic = l.offer_recursive; l.offer_recursive = false;
        var far: i64 = 0;
        if compact { far = life_read_offer(l, leaf, offer.places, life_read_key(offer.node, offer.value.type_id)); } else { far = life_effect(p, l, offer); }
        if stamps && l.offer_count > offers && !l.offer_recursive {
            if far < 0 { far = life_effect_far(l, offer.places).far; }
            life_leaf_stamp(l, leaf, far, offer.places);
        }
        if cyclic { l.offer_recursive = true; }
    }
}
// Many walks omit construction reads. Test that before calling the checker.
inline fn life_construct_read(p: Program&, l: Lifetimes&, node: i64, value: const LifeValue&, known: i64 = -1) {
    if l.omit_construct_reads || l.reading_place > 0 { return; }
    life_check_construct_read(p, l, node, value, known);
}
fn life_construct_parameter(p: Program&, l: Lifetimes&, symbol: i64, places: i64) -> bool {
    let ty = p.symbols[symbol].type_id;
    if !life_plain_ref(p, ty) || p.types[ty].kind != TY_REF { return false; }
    if (p.symbols[symbol].flags & S_PARAMETER) != 0 { return true; }
    var cell = l.frames[l.frame].first_parameter;
    while cell >= 0 {
        let parameter = l.cells[cell];
        let formal = p.symbols[parameter.symbol].type_id;
        if life_plain_ref(p, formal) && p.types[formal].kind == TY_REF &&
           life_overlaps(p, l, places, parameter.live_refs) { return true; }
        cell = parameter.next_parameter;
    }
    return false;
}

fn life_check_construct_read(p: Program&, l: Lifetimes&, node: i64, value: const LifeValue&, known: i64) {
    var effect_places = value.place; if life_is_ref(p, value.type_id) { effect_places = value.refs; }
    var effect_type: i64 = value.type_id; if effect_type >= 0 && p.types[effect_type].kind == TY_REF { effect_type = p.types[effect_type].element; }
    if value.element_array != -1 || life_cached_size_class(p, l, effect_type) == 2 {
        var cr_val = LifeValue { type_id: value.type_id, place: value.place, element_array: value.element_array };
        if life_is_ref(p, value.type_id) { cr_val.refs = effect_places as i32; } else { cr_val.place = effect_places as i32; }
        let eff = LifeEffect { kind: 3, node: node as i32, value: cr_val, places: effect_places as i32 };
        life_offer_once(p, l, eff, known);
    }
    if l.discovery { return; }
    var places = value.place;
    if value.type_id >= 0 && p.types[value.type_id].kind == TY_REF { places = value.refs; }
    var type_id: i64 = value.type_id;
    if type_id >= 0 && p.types[type_id].kind == TY_REF { type_id = p.types[type_id].element; }
    for index in l.hold_floor..l.hold_count {
        let hold: const LifeHold& = l.holds[index]; if hold.kind != 2 { continue; }
        var element_read = value.element_array != -1;
        if value.element_array >= 0 && hold.value.type_id >= 0 && p.types[hold.value.type_id].kind == TY_ARRAY {
            element_read = life_same(p, value.element_array, hold.value.type_id) || life_contains(p, l, p.types[hold.value.type_id].element, value.element_array);
        }
        if !(element_read || life_contains(p, l, type_id, hold.value.type_id) ||
             life_cached_size_class(p, l, type_id) > 0 && life_contains(p, l, hold.value.type_id, type_id)) { continue; }
        let source = check_place_root(p, node);
        let target = check_place_root(p, hold.node);
        if l.frame > 0 && hold.frame == l.frame && source >= 0 && target >= 0 &&
           p.symbols[source].owner == l.frames[l.frame].function_node &&
           (p.symbols[target].flags & S_GLOBAL) != 0 && !life_plain_ref(p, p.symbols[target].type_id) &&
           life_construct_parameter(p, l, source, places) {
            var message: u8[>..] = [];
            let name = token_text(p, p.symbols[source].name_token);
            let owner = token_text(p, p.symbols[target].name_token);
            message.append("cannot use "); message.append(name);
            message.append(" in the value assigned to "); message.append(owner);
            message.append(": "); message.append(name); message.append(" may refer to "); message.append(owner);
            message.append(", and that value is built over the old contents of "); message.append(owner);
            message.append(" (§4.4); build it in a variable of its own, and assign copy() of that");
            life_error(p, l, node, message);
        }
        if life_overlaps(p, l, hold.value.place, places) {
            life_error(p, l, node, "whole assignment reads storage while its replacement is being constructed");
        }
    }
}
fn life_coerce(p: Program&, l: Lifetimes&, value: LifeValue, expected: i64) -> LifeValue {
    if expected < 0 || expected == TYPE_VOID || value.type_id == expected && value.contents == 0 { return value; }
    var out = value;
    let target: const Type& = p.types[expected];
    let target_kind = target.kind;
    // Equal types need no reference conversion, but copying can still drop contents.
    if value.type_id == expected {
        if target_kind != TY_REF && target_kind != TY_SLICE && !life_tf_holds(p, l, expected) { out.contents = 0; }
        return out;
    }
    var source_kind: i64 = -1;
    if value.type_id >= 0 { source_kind = p.types[value.type_id].kind; }
    if target_kind == TY_SLICE {
        if source_kind == TY_REF {
            let element = p.types[value.type_id].element;
            if element >= 0 {
                if p.types[element].kind == TY_SLICE {
                    out = life_load(p, l, expected, value.refs); return out;
                }
                if p.types[element].kind == TY_ARRAY {
                    if p.types[element].array_kind == A_GROW { out.refs = life_grow_only_interior(l, value.refs) as i32; }
                    else { out.refs = life_interior(l, value.refs) as i32; }
                }
            }
        } else if source_kind != TY_SLICE {
            if source_kind == TY_ARRAY && p.types[value.type_id].array_kind == A_GROW { out.refs = life_grow_only_interior(l, value.place) as i32; }
            else { out.refs = life_interior(l, value.place) as i32; }
        }
    } else if target_kind == TY_REF {
        if source_kind != TY_REF && source_kind != TY_SLICE { out.refs = value.place; }
        if source_kind == TY_SLICE && target.element >= 0 && p.types[target.element].kind == TY_SLICE { out.refs = value.place; }
    } else {
        if source_kind == TY_REF || source_kind == TY_SLICE { out.place = value.refs; out.refs = 0; }
        if !life_tf_holds(p, l, expected) { out.contents = 0; }
        else if source_kind == TY_REF && out.contents != 0 { out.contents = life_mark_slotread(l, out.contents) as i32; }
    }
    out.type_id = expected as i32;
    return out;
}
fn life_candidates(p: Program&, l: Lifetimes&, pointee: i64, depth: i64, globals: bool, out: LifeBuild&, all_globals: bool = false) {
    // The global list is in the same order as the ordinary live-cell scan.
    // A global var read in a function also includes later declarations.
    var listed = 0; var index = -1;
    if globals { while listed < l.global_cells.len && !all_globals && !l.cells[l.global_cells[listed]].live { listed += 1; } if listed < l.global_cells.len { index = l.global_cells[listed]; } }
    else { index = life_next_live(l, -1); }
    while index >= 0 {
        let key: const LifeCellKey& = l.cell_keys[index];
        if key.depth <= depth && (!globals || key.global) && (globals || life_visible(l, index)) {
            if life_contains_memo(p, l, key.type_id, pointee) { life_build_add(l, out, life_root_set(l, key.root)); }
            if key.element >= 0 && life_contains_memo(p, l, key.element, pointee) {
                var at = l.sets[l.cells[index].refs].first;
                while at >= 0 {
                    let alt = l.alts[at];
                    if l.roots[alt.root].depth <= depth { life_build_add_alt(l, out, LifeAlt { root: alt.root, from: alt.from, bound: alt.bound, exact: alt.exact }); }
                    at = alt.next;
                }
            }
        }
        if globals {
            listed += 1; while listed < l.global_cells.len && !all_globals && !l.cells[l.global_cells[listed]].live { listed += 1; }
            index = -1; if listed < l.global_cells.len { index = l.global_cells[listed]; }
        } else { index = life_next_live(l, index); }
    }
}
// The candidates life_build_drop would list for life_candidates over the
// global cells, appended to scratch. They change only with global_epoch.
fn life_global_candidates(p: Program&, l: Lifetimes&, pointee: i64, depth: i64, all_globals: bool = false) {
    while l.global_candidates.len <= pointee { l.global_candidates.push(LifeGlobalCandidates {}); }
    let memo = l.global_candidates[pointee];
    if memo.epoch == l.global_epoch && memo.depth == depth && memo.all_globals == all_globals {
        for at in memo.first..memo.first + memo.count { l.scratch.push(l.candidate_alts[at]); }
        return;
    }
    let start = l.scratch.len;
    var candidates = LifeBuild {}; life_candidates(p, l, pointee, depth, true, candidates, all_globals); life_build_drop(l, candidates);
    if l.candidate_epoch != l.global_epoch { l.candidate_alts.clear(); l.candidate_epoch = l.global_epoch; }
    let first = l.candidate_alts.len;
    for at in start..l.scratch.len { l.candidate_alts.push(l.scratch[at]); }
    l.global_candidates[pointee] = LifeGlobalCandidates { epoch: l.global_epoch, depth: depth, first: first, count: l.scratch.len - start, all_globals: all_globals };
}
fn life_class_candidates(p: Program&, l: Lifetimes&, owner: i64, pointee: i64) -> i64 {
    var through_parameter = false; var ci = l.frames[l.frame].first_parameter;
    while ci >= 0 {
        let cell: const LifeCell& = l.cells[ci];
        if life_find(l, cell.refs, owner) >= 0 { through_parameter = true; break; }
        ci = cell.next_parameter;
    }
    if !through_parameter { return 0; }
    var result = LifeBuild {}; ci = l.frames[l.frame].first_parameter;
    while ci >= 0 {
        let cell: const LifeCell& = l.cells[ci]; let ty = p.symbols[cell.symbol].type_id;
        if ty >= 0 && p.types[ty].kind == TY_REF && life_contains(p, l, p.types[ty].element, pointee) {
            var at = l.sets[cell.refs].first;
            while at >= 0 { let alt = l.alts[at]; if l.roots[alt.root].depth <= l.roots[owner].depth { life_build_add_alt(l, result, LifeAlt { root: alt.root, bound: alt.bound, component: alt.component, exact: alt.exact }); } at = alt.next; }
        }
        ci = cell.next_parameter;
    }
    return life_build_end(l, result);
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
// How many global roots a set names before they are taken as one.
let LIFE_GLOBAL_ALTS: i64 = 4;
// A reference read out of a global container may point into any global
// that can hold its pointee: thousands of roots in a large program, in set
// after set. Once class-keyed frames are in use, more than LIFE_GLOBAL_ALTS
// global roots in one set are one alternative instead: something in global
// storage (upstream's globals bound), which aliases every root at depth 0 as
// those alternatives together did, and is read back through as any global
// container is. Kept with the set, which never changes.
inline fn life_fold(l: Lifetimes&, set: i64) -> i64 {
    if l.class_frames == 0 || l.sets[set].count <= LIFE_GLOBAL_ALTS { return set; }
    if l.sets[set].folded >= 0 { return l.sets[set].folded; }
    return life_fold_slow(l, set);
}
fn life_fold_slow(l: Lifetimes&, set: i64) -> i64 {
    var globals = 0; var at = l.sets[set].first;
    while at >= 0 {
        let root: const LifeRoot& = l.roots[l.alts[at].root];
        // (A global's root: a named root of no frame, at depth 0.)
        if l.alts[at].root == l.globals_root || root.symbol >= 0 && root.frame == 0 && root.depth == 0 { globals += 1; }
        at = l.alts[at].next;
    }
    var result = set;
    if globals > LIFE_GLOBAL_ALTS {
        if l.globals_root < 0 { l.globals_root = l.roots.len; l.roots.push(LifeRoot { frame: 0 }); }
        let start = l.scratch.len; var all_slots = true; var any_bytes = false; var bound: i32 = 0; var first_g = true; var common_tt: i32 = -1; at = l.sets[set].first;
        while at >= 0 {
            let alt = l.alts[at]; at = alt.next; let root: const LifeRoot& = l.roots[alt.root];
            if alt.root == l.globals_root || root.symbol >= 0 && root.frame == 0 && root.depth == 0 {
                if alt.root != 0 && !alt.slotread { all_slots = false; } if alt.byteview { any_bytes = true; } if alt.bound > bound { bound = alt.bound; }
                if first_g { common_tt = alt.target_type; first_g = false; } else if common_tt != alt.target_type { common_tt = -1; }
            } else { var kept = alt; kept.next = -1; kept.bound = 0; l.scratch.push(kept); }
        }
        l.scratch.push(LifeAlt { root: l.globals_root as i32, target_type: common_tt, exact: false, slotread: all_slots, byteview: any_bytes });
        result = life_list_set(l, start, false);
        l.scratch.resize(start);
    }
    l.sets[set].folded = result as i32;
    return result;
}
// Whether some global holds grow-shrink elements a reference to `pointee`
// may point into: what the folded alternative stands for decides, as each
// global's own alternative did (life_gs_value).
fn life_globals_gs(p: Program&, l: Lifetimes&, pointee: i64, byteview: bool) -> bool {
    var key = 2 * pointee; if byteview { key += 1; }
    if l.globals_gs_key == key && l.globals_gs_epoch == l.global_epoch { return l.globals_gs_answer; }
    var answer = false;
    for ci in l.global_cells { if l.cells[ci].live && life_gs_contains(p, l, l.cell_keys[ci].type_id, pointee, byteview) { answer = true; break; } }
    l.globals_gs_key = key; l.globals_gs_epoch = l.global_epoch; l.globals_gs_answer = answer;
    return answer;
}
fn life_readback(p: Program&, l: Lifetimes&, type_id: i64, places: i64) -> i64 {
    if !life_is_ref(p, type_id) { return 0; }
    let t: const Type& = p.types[type_id];
    if t.kind == TY_REF && t.length_storage >= 0 {
        let pool = life_pool_places(p, l, t.pool); if pool != 0 { return pool; }
        return places;
    }
    if l.discovery && l.frame > 0 { life_note_places_read(l, places); }
    var slot: i64 = -1; var contents: i64 = -1;
    var islot: i64 = -1; var inexact_ver: i64 = -1;
    var single_local = false;
    if l.types_frozen && l.class_frames == 0 && t.element >= 0 && l.sets[places].count == 1 {
        let alt: const LifeAlt& = l.alts[l.sets[places].first];
        let root: const LifeRoot& = l.roots[alt.root];
        if alt.exact && root.frame > 0 {
            single_local = true;
            // For an exact local place, readback uses only this root's contents
            // and the current frame's parameter refs. Neither depends on liveness.
            if l.local_reads.len == 0 { l.local_reads.resize(256, LifeLocalRead {}); }
            slot = (places * 1000003 + type_id * 8191 + l.frame) & (l.local_reads.len - 1);
            contents = if !l.discovery && root.type_id >= 0 && p.types[root.type_id].kind == TY_SLICE { root.live_contents } else { root.contents };
            let hit: const LifeLocalRead& = l.local_reads[slot];
            if hit.places == places && hit.type_id == type_id && hit.frame == l.frame && hit.contents == contents && hit.parameters == l.frames[l.frame].parameter_version { return hit.result; }
        } else if !alt.exact && l.island == 0 && root.class_frame < 0 && root.depth >= 0 && root.depth < 64 &&
                  !(root.symbol >= 0 && (p.symbols[root.symbol].flags & S_GLOBAL) != 0 || alt.root == l.globals_root) {
            single_local = true;
            // An inexact local readback queries life_candidates over live cells at depth <= root.depth.
            var ver: i64 = 0; var d: i64 = 0;
            while d <= root.depth {
                let c = l.depth_clock[d];
                if c > ver { ver = c; }
                d += 1;
            }
            inexact_ver = ver;
            if l.inexact_reads.len == 0 { l.inexact_reads.resize(1024, LifeInexactRead {}); }
            var ih: u64 = (places as! u64) * 11400714819323198485 ^ (type_id as! u64) * 14029467366897019727;
            ih ^= ih >> 29;
            islot = (ih & ((l.inexact_reads.len - 1) as! u64)) as i64;
            let ihit: const LifeInexactRead& = l.inexact_reads[islot];
            if ihit.places == places as i32 && ihit.type_id == type_id as i32 && ihit.version == inexact_ver {
                if l.discovery { l.dep_tainted = true; if l.island > 0 { l.cls_dep_tainted = true; } }
                return ihit.result as i64;
            }
        }
    }
    // Every inexact global container at one depth has the same candidates,
    // which it adds read from itself (from), bounded by its own bound and slot-read
    // unless it holds a reference. A merge only ever admits more, so once two
    // such containers' candidates are in, each reads from no one container
    // and is bounded by both: a later one that is no more slot-read and no
    // deeper bound adds nothing a join would keep, and is skipped.
    // Where every place is a global container, the candidates are the global
    // cells', which change only with global_epoch, and the rest is the places
    // and types: the same read-back in the same epoch is the same list, and
    // so the same set (life_list_set).
    var remembered = !single_local && t.element >= 0; var probe = l.sets[places].first;
    while probe >= 0 && remembered {
        let symbol = l.roots[l.alts[probe].root].symbol;
        remembered = l.alts[probe].root == l.globals_root ||
                     t.kind != TY_SLICE && symbol >= 0 && (p.symbols[symbol].flags & S_GLOBAL) != 0;
        probe = l.alts[probe].next;
    }
    var memo = 0;
    if remembered {
        if l.readbacks.len == 0 { l.readbacks.resize(512, LifeReadBack {}); }
        var h: u64 = (type_id as! u64) * 11400714819323198485 ^ (places as! u64) * 14029467366897019727; h ^= h >> 29;
        memo = (h & ((l.readbacks.len - 1) as! u64)) as i64;
        let r: const LifeReadBack& = l.readbacks[memo];
        if r.type_id == type_id && r.places == places && r.epoch == l.global_epoch { return r.set; }
    }
    var global_reads = 0; var global_depth = 0; var global_holder = false; var global_bound: i64 = 0;
    var result = LifeBuild {}; var at = l.sets[places].first;
    while at >= 0 {
        let alt = l.alts[at];
        let root_symbol = l.roots[alt.root].symbol;
        let root_class_frame = l.roots[alt.root].class_frame;
        let root_type_id = l.roots[alt.root].type_id;
        let root_depth = l.roots[alt.root].depth;
        let global = root_symbol >= 0 && (p.symbols[root_symbol].flags & S_GLOBAL) != 0 || alt.root == l.globals_root;
        var root_contents = l.roots[alt.root].contents;
        let slot_type = if root_class_frame >= 0 { l.roots[alt.root].class_pointee } else { root_type_id };
        if !l.discovery && !global && t.kind == TY_SLICE && slot_type >= 0 && p.types[slot_type].kind == TY_SLICE {
            root_contents = l.roots[alt.root].live_contents;
        }
        // For global shrink reachability, a slice read from an exact
        // container follows its recorded stores. Plain reference slots retain
        // the global lifetime bound used for relative-reference proofs.
        let known = alt.exact && (!global || t.kind == TY_SLICE && alt.root != l.globals_root);
        // What some storage that outlives a class root holds is not looked
        // for among the body's own cells: it stays bounded by the class, and
        // the call maps it (upstream ReadBackRoot, a container from a caller).
        if !alt.exact && root_class_frame >= 0 && t.element >= 0 {
            var rb_b = alt.bound; if l.class_frames > 0 { rb_b = 0; }
            life_build_add_alt(l, result, LifeAlt { root: alt.root, bound: rb_b, exact: false, slotread: true });
            at = alt.next; continue;
        }
        let holder = root_type_id >= 0 && life_is_ref(p, root_type_id);
        let shared = !known && global && t.element >= 0;
        if shared && global_reads >= 2 && root_depth == global_depth && (!holder || global_holder) && alt.bound <= global_bound { at = alt.next; continue; }
        if shared && (global_reads == 0 || root_depth == global_depth) {
            global_reads += 1; global_depth = root_depth;
            if holder { global_holder = true; } if alt.bound > global_bound { global_bound = alt.bound; }
        }
        // The candidates are read once, here, and their set is not made.
        let start = l.scratch.len;
        if shared { life_global_candidates(p, l, t.element, root_depth); }
        else if !known { if l.discovery { l.dep_tainted = true; if l.island > 0 { l.cls_dep_tainted = true; } } var candidates = LifeBuild {}; life_candidates(p, l, t.element, root_depth, global, candidates); life_build_drop(l, candidates); }
        else {
            var source = root_contents;
            if global && l.class_frames > 0 { source = life_overlay(p, l, life_alt_set(l, alt), source); }
            if root_class_frame >= 0 && l.frames[root_class_frame].stored_first >= 0 { source = life_join(l, source, life_class_stores(p, l, alt.root)); }
            // A reference read out of storage reached through a parameter may
            // be to any argument whose type can hold its pointee. Out of an
            // ordinary root those arguments are alternatives of the value.
            // Out of a class root they are noted on the storage class the
            // value is (class_mask) and are no part of the value: the alias
            // rules and a store or shrink through the reference name them
            // from there (life_class_alias, life_place_candidates), and a
            // call the reference is passed to, or a store of it, sees only
            // what the storage holds, which each call maps to what its
            // argument's storage really holds. Upstream roots a read-out
            // reference at its container's class and names candidates
            // where a rule asks (RootCandidates, ShrinkTargets).
            var mask: i64 = 0;
            if t.kind == TY_REF && t.element >= 0 && (p.types[t.element].kind == TY_ARRAY || p.types[t.element].kind == TY_STRUCT || p.types[t.element].kind == TY_ENUM) {
                let candidates = life_class_candidates(p, l, alt.root, t.element); var noted = root_class_frame >= 0 && l.frames[root_class_frame].active;
                var ci = l.sets[candidates].first;
                while ci >= 0 && noted {
                    let c = l.alts[ci]; ci = c.next; let cr: const LifeRoot& = l.roots[c.root];
                    if cr.class_frame != root_class_frame || cr.class_parent >= 0 || cr.class_index >= l.frames[root_class_frame].class_base || !c.exact { noted = false; }
                    else if cr.class_index < 62 { mask |= 1 << cr.class_index; } else { mask = -1; }
                }
                if !noted { mask = 0; source = life_join(l, source, candidates); }
            }
            var item = l.sets[source].first;
            while item >= 0 {
                var r = l.alts[item]; item = r.next;
                // What a class root's storage holds, read as one pointee type.
                if l.class_frames > 0 && r.exact && t.element >= 0 && l.roots[r.root].class_frame >= 0 && l.roots[r.root].class_parent < 0 {
                    if !r.byteview && !life_class_holds(p, l, r.root as i64, t.element) { continue; }
                    let owner = l.roots[r.root].class_frame; let own = l.roots[r.root].class_index;
                    if l.frames[owner].active && own >= l.frames[owner].class_base {
                        let typed = life_class_typed(l, l.frames[owner].classes + own - l.frames[owner].class_base, t.element);
                        if typed >= 0 { r.root = typed as i32; r.target_type = -1; }
                    }
                } else if l.class_frames > 0 && !r.exact && t.element >= 0 && r.from == r.root && (r.root as i64) == (alt.root as i64) && l.roots[r.root].class_frame >= 0 && l.roots[r.root].class_level < LIFE_CLASS_DEPTH {
                    // The place is a storage class and this is what its own
                    // storage holds: the class of that for this pointee.
                    if l.frames[l.roots[r.root].class_frame].active {
                        let typed = life_class_typed(l, alt.root, t.element);
                        if typed >= 0 { r.root = typed as i32; r.exact = true; r.from = -1; r.target_type = -1; }
                    }
                }
                if mask != 0 && r.exact && l.roots[r.root].class_frame == root_class_frame && (l.roots[r.root].class_parent >= 0 || l.roots[r.root].class_index >= l.frames[root_class_frame].class_base) &&
                   (l.roots[r.root].class_mask | mask) != l.roots[r.root].class_mask {
                    l.roots[r.root].class_mask |= mask; l.revision += 1; l.frames[root_class_frame].stored_version += 1;
                }
                l.scratch.push(r);
            }
        }
        let end = l.scratch.len;
        var excluded = false; var kept = false;
        for item in start..end {
            let r = l.scratch[item];
            if r.root != 0 && l.roots[r.root].param_frame >= 0 && !l.frames[l.roots[r.root].param_frame].active { continue; }
            if (r.target_type < 0 || life_same(p, r.target_type, t.element)) && (r.root == 0 || r.byteview || !r.exact || l.roots[r.root].param_frame >= 0 || life_class_holds(p, l, r.root as i64, t.element) || life_contains_memo(p, l, l.roots[r.root].type_id, t.element)) &&
               (r.root == 0 || r.byteview || r.exact || r.from != r.root || l.roots[r.root].class_frame < 0 || l.roots[r.root].class_parent < 0 || life_holder_points(p, l, l.roots[r.root].class_type, t.element)) &&
               (!life_is_global_bound(l, r) || r.byteview || life_globals_contain(p, l, t.element)) {
                var is_ref_slot = !global && (root_type_id >= 0 && life_is_ref(p, root_type_id) ||
                    root_class_frame >= 0 && l.roots[alt.root].class_parent < 0 &&
                    l.roots[alt.root].class_index < l.frames[root_class_frame].class_base &&
                    l.roots[alt.root].class_pointee >= 0 && life_is_ref(p, l.roots[alt.root].class_pointee));
                var slotread = true;
                if is_ref_slot { slotread = r.slotread; }
                // A slot can hold no reference into grow-shrink elements.
                // Keep abstract classes and whole root owners as candidates:
                // each may stand for independent storage that can hold it.
                if !known && slotread && r.exact && l.roots[r.root].class_frame < 0 {
                    let storage = life_alt_type(p, l, r);
                    if !root_struct_type(p, storage) && life_gs_contains(p, l, storage, t.element, r.byteview) {
                        excluded = true; continue;
                    }
                }
                kept = true;
                var bound = r.bound;
                // Caller storage bounds a read-back's lifetime, while the
                // actual referent remains available for alias/shrink checks.
                if alt.bound > bound { bound = alt.bound; }
                // What a class's storage holds, read as one pointee, is a
                // reference to that pointee: a call maps it only to what the
                // argument's storage holds that such a value can lie in
                // (life_map_onto).
                var target = r.target_type;
                if target < 0 && r.exact && t.element >= 0 && (l.roots[r.root].param_frame >= 0 || l.roots[r.root].class_frame >= 0 && (l.roots[r.root].class_parent >= 0 || l.roots[r.root].class_index >= l.frames[l.roots[r.root].class_frame].class_base)) { target = t.element as i32; }
                life_build_add_alt(l, result, LifeAlt { root: r.root, from: alt.root, target_type: target, bound: bound, component: r.component, exact: r.exact, slotread: slotread, byteview: r.byteview });
            }
        }
        if excluded && !kept {
            life_build_add_alt(l, result, LifeAlt { root: alt.root, bound: alt.bound, exact: false, slotread: true });
        }
        l.scratch.resize(start);
        at = alt.next;
    }
    let set = life_fold(l, life_build_end(l, result));
    if slot >= 0 {
        // Grow on repeated misses. Small programs usually need only a few entries.
        if l.local_reads.len < 16384 {
            l.local_read_writes += 1;
            if l.local_read_writes >= 2 * l.local_reads.len {
                l.local_reads.resize(2 * l.local_reads.len, LifeLocalRead {});
                l.local_read_writes = 0;
                slot = (places * 1000003 + type_id * 8191 + l.frame) & (l.local_reads.len - 1);
            }
        }
        l.local_reads[slot] = LifeLocalRead { places: places, type_id: type_id, frame: l.frame, contents: contents, parameters: l.frames[l.frame].parameter_version, result: set };
    }
    if islot >= 0 {
        if l.inexact_reads.len < 16384 {
            l.inexact_read_writes += 1;
            if l.inexact_read_writes >= 2 * l.inexact_reads.len {
                l.inexact_reads.resize(2 * l.inexact_reads.len, LifeInexactRead {});
                l.inexact_read_writes = 0;
                var ih: u64 = (places as! u64) * 11400714819323198485 ^ (type_id as! u64) * 14029467366897019727;
                ih ^= ih >> 29;
                islot = (ih & ((l.inexact_reads.len - 1) as! u64)) as i64;
            }
        }
        l.inexact_reads[islot] = LifeInexactRead { places: places as i32, type_id: type_id as i32, result: set as i32, version: inexact_ver };
    }
    if remembered {
        l.readbacks[memo] = LifeReadBack { type_id: type_id, places: places, epoch: l.global_epoch, set: set };
        // Entries keep their slots when the table grows, as joins do.
        l.readbacks_recorded++;
        if l.readbacks_recorded > 4 * l.readbacks.len && l.readbacks.len < 1048576 { l.readbacks.resize(4 * l.readbacks.len, LifeReadBack {}); l.readbacks_recorded = 0; }
    }
    return set;
}
fn life_load(p: Program&, l: Lifetimes&, type_id: i64, places: i64, slot: bool = false) -> LifeValue {
    var out = LifeValue { type_id: type_id as i32, place: places as i32 };
    // Only a type that holds references keeps the contents, and validation
    // reads the live ones.
    let is_ref = life_tf_is_ref(p, l, type_id);
    let holds = life_tf_holds(p, l, type_id);
    if !holds && !is_ref { return out; }
    if holds && l.discovery {
        var use_live = false;
        if l.sets[places].count == 1 && l.frame > 0 && !l.frames[l.frame].recursive_call {
            let alt: const LifeAlt& = l.alts[l.sets[places].first];
            let rt: const LifeRoot& = l.roots[alt.root];
            if alt.exact && rt.frame == l.frame && rt.class_frame < 0 && rt.symbol >= 0 &&
               (p.symbols[rt.symbol].flags & (S_GLOBAL | S_PARAMETER | S_CAPTURE)) == 0 {
                use_live = true;
            }
        }
        if use_live {
            life_note_places_read(l, places);
            out.contents = life_live_contents(p, l, places) as i32;
        } else {
            out.contents = life_contents(p, l, places) as i32;
        }
    } else if holds { out.contents = life_live_contents(p, l, places) as i32; }
    if is_ref { out.refs = life_readback(p, l, type_id, places) as i32; }
    if !holds { out.contents = 0; }
    else if !is_ref {
        // What follows depends only on the two sets and on slot (a root's
        // symbol does not change), and a list made again is the same set.
        if l.loaded.len == 0 { l.loaded.resize(64, LifeLoaded {}); }
        var key = 2 * out.contents; if slot { key += 1; }
        var h: u64 = (key as! u64) * 11400714819323198485 ^ (places as! u64) * 14029467366897019727; h ^= h >> 29;
        let memo = (h & ((l.loaded.len - 1) as! u64)) as i64;
        if l.loaded[memo].contents == key && l.loaded[memo].places == places { out.contents = l.loaded[memo].set as i32; return out; }
        var mutable = LifeBuild { set: out.contents };
        var ai = l.sets[places].first;
        while ai >= 0 {
            let alt = l.alts[ai]; ai = alt.next;
            let root = l.roots[alt.root]; let symbol = root.symbol;
            if symbol < 0 || (p.symbols[symbol].flags & (S_GLOBAL | S_MUTABLE)) != (S_GLOBAL | S_MUTABLE) { continue; }
            if life_gs_contains(p, l, root.type_id, -1, true) {
                life_build_add_alt(l, mutable, LifeAlt { root: alt.root, bound: alt.bound, exact: false, slotread: slot });
            }
        }
        out.contents = life_fold(l, life_build_end(l, mutable)) as i32;
        if slot {
            var contents = LifeBuild {}; var at = l.sets[out.contents].first;
            while at >= 0 { var alt = l.alts[at]; at = alt.next; alt.slotread = true; life_build_add_alt(l, contents, alt); }
            out.contents = life_build_end(l, contents) as i32;
        }
        l.loaded[memo] = LifeLoaded { contents: key, places: places, set: out.contents };
        // Entries keep their slots when the table grows, as joins do.
        l.loaded_recorded++;
        if l.loaded_recorded > 4 * l.loaded.len && l.loaded.len < 1048576 { l.loaded.resize(4 * l.loaded.len, LifeLoaded {}); l.loaded_recorded = 0; }
    }
    return out;
}
// A set without its class roots. A set never changes and a class root stays
// one, so the answer is kept with the set.
fn life_strip(l: Lifetimes&, set: i64) -> i64 {
    if l.sets[set].plain >= 0 { return l.sets[set].plain; }
    let first = l.sets[set].first as i64; let count = l.sets[set].count as i64;
    var dropped = false;
    for i in 0..count { if l.roots[l.alts[first + i].root].class_frame >= 0 { dropped = true; break; } }
    if !dropped { l.sets[set].plain = set as i32; return set; }
    let start = l.scratch.len;
    for i in 0..count {
        let alt = l.alts[first + i];
        if l.roots[alt.root].class_frame >= 0 { continue; }
        l.scratch.push(alt);
    }
    let result = life_list_set(l, start, true);
    l.scratch.resize(start);
    l.sets[set].plain = result as i32;
    return result;
}
// Whether a set names a class root.
inline fn life_has_class(l: Lifetimes&, set: i64) -> bool { return life_strip(l, set) != set; }
// What an island stores of its class roots in storage outside it (a global,
// static data) stays with the island, in class_stored, which every read of
// such storage inside the island adds (life_contents, life_eval): no other
// frame may meet a class root of this one. Each call stores what the class
// roots stand for there instead (life_replay). Returns what the storage
// itself takes: the sources without class roots.
fn life_keep_outside(l: Lifetimes&, sources: i64) -> i64 {
    let stored = life_join(l, l.frames[l.island].class_stored, sources);
    if !life_equal(l, stored, l.frames[l.island].class_stored) { l.frames[l.island].class_stored = stored; l.frames[l.island].stored_version += 1; l.held_epoch += 1; l.revision += 1; }
    return life_strip(l, sources);
}
// A set without the roots below depth 0, kept with the set as life_strip's
// is. Storing one of those in a global is the error life_store reports; the
// global does not go on to hold a local of a frame that is gone, which with
// class-keyed frames every other island would read back.
fn life_lasting(l: Lifetimes&, set: i64) -> i64 {
    if l.sets[set].lasting >= 0 { return l.sets[set].lasting; }
    let first = l.sets[set].first as i64; let count = l.sets[set].count as i64;
    let start = l.scratch.len; var dropped = false;
    for i in 0..count {
        var alt = l.alts[first + i];
        if l.roots[alt.root].depth > 0 && l.roots[alt.root].class_frame < 0 { dropped = true; continue; }
        if alt.bound != 0 { alt.bound = 0; dropped = true; }
        l.scratch.push(alt);
    }
    var result = set;
    if dropped { result = life_list_set(l, start, true); }
    l.scratch.resize(start);
    l.sets[set].lasting = result as i32;
    return result;
}
// What of a stored set was read straight out of the storage of the one
// argument class root it is stored into (own), or the rest of it:
// `b.items = b.storage[..n]` puts back into b's storage what that storage
// held. Upstream records no store of a value read out of its own container
// (RecordStore), only that the container is filled again where something
// emptied it (DropKills). Kept as a store of the storage class, each call
// mapped it pair by pair as any other: every storage the argument might be
// took what every other held, which was most of what a large program's
// calls were refused for, and half of the pass's sets.
// Here such a store is on record without a set (life_own_effects): as what
// kind of reference went back in (LifeEffect.field: -2 one as the storage
// held it, -3 one into what such a reference points at, -4 a byte view, -5
// both) and to what type (value.type_id, or -1). A call applies that to
// what each storage the class is there holds itself (life_own_store).
fn life_own_reads(l: Lifetimes&, root: i64, set: i64, own: bool) -> i64 {
    let owner = l.roots[root].class_frame;
    if owner < 0 || set == 0 || l.roots[root].class_parent >= 0 || l.roots[root].class_index >= l.frames[owner].class_base { if own { return 0; } return set; }
    let first_cls = l.frames[owner].classes + l.frames[owner].class_base + l.roots[root].class_index;
    let first = l.sets[set].first as i64; let count = l.sets[set].count as i64;
    let start = l.scratch.len; var any = false;
    for i in 0..count {
        var x = l.alts[first + i]; x.next = -1;
        let read = x.exact && x.component < 0 && x.bound == 0 && (x.root as i64 == first_cls || l.roots[x.root].class_frame == owner && l.roots[x.root].class_parent == root);
        if read { any = true; }
        if read == own { l.scratch.push(x); }
    }
    var part = set;
    if !any { if own { part = 0; } }
    else { part = life_list_set(l, start, true); }
    l.scratch.resize(start);
    return part;
}
fn life_own_effects(p: Program&, l: Lifetimes&, root: i64, owned: i64) {
    let places = life_root_set(l, root); var at = l.sets[owned].first;
    while at >= 0 {
        let x = l.alts[at]; at = x.next;
        var code = -2; if !x.slotread { code -= 1; } if x.byteview { code -= 2; }
        var ty = x.target_type as i64;
        if l.roots[x.root].class_parent >= 0 {
            let ct = l.roots[x.root].class_type;
            if code == -2 && ct >= 0 && (x.target_type < 0 || !life_same(p, x.target_type as i64, ct)) { code = -6; }
            ty = ct;
        }
        if code == -2 { ty = -1; }
        let eff = LifeEffect { kind: 4, node: -1, value: LifeValue { type_id: ty as i32, refs: places as i32 }, places: places as i32, field: code as i32 };
        life_effect(p, l, eff);
    }
}
// A store of a storage's own back into it (life_own_reads), as one call
// lands it in a root the class is there: the root holds again what it held,
// as the kind of reference the store put back, where that is another kind.
fn life_own_store(p: Program&, l: Lifetimes&, root: i64, code: i64, ty: i64) {
    let places = life_root_set(l, root);
    if code < -2 {
        let held = life_held_own(l, places); var out = LifeBuild {}; var at = l.sets[held].first;
        while at >= 0 {
            var h = l.alts[at]; at = h.next; h.next = -1;
            if h.root == 0 { continue; }
            let owner = l.roots[h.root].class_frame;
            if ty >= 0 && h.exact && !h.byteview {
                var within = h.target_type as i64;
                if within < 0 {
                    if owner < 0 { within = l.roots[h.root].type_id; }
                    else if !life_class_holds(p, l, h.root as i64, ty) { continue; }
                }
                if within >= 0 && !life_contains_memo(p, l, within, ty) { continue; }
            }
            // In an island, what its own class root holds of one pointee
            // is that island's storage class of the pointee (life_typed_held).
            if ty >= 0 && owner >= 0 && l.frames[owner].active && h.exact && l.roots[h.root].class_parent < 0 && l.roots[h.root].class_index >= l.frames[owner].class_base {
                let typed = life_class_typed(l, l.frames[owner].classes + l.roots[h.root].class_index - l.frames[owner].class_base, ty);
                if typed >= 0 { h.root = typed as i32; }
            }
            if code == -3 || code == -5 { h.slotread = false; }
            if code == -4 || code == -5 { h.byteview = true; }
            h.target_type = -1; h.from = -1;
            life_build_add_alt(l, out, h);
        }
        let landing = life_build_end(l, out);
        let next = life_join(l, l.roots[root].contents, landing);
        if !life_equal(l, next, l.roots[root].contents) { life_set_contents(l, root, next); l.revision += 1; }
        if !l.discovery { life_set_live_contents(l, root, life_join(l, l.roots[root].live_contents, landing)); }
    }
    let eff = LifeEffect { kind: 4, node: -1, value: LifeValue { type_id: ty as i32, refs: places as i32 }, places: places as i32, field: code as i32 };
    life_effect(p, l, eff);
    if !l.discovery { life_clear_kills(l, root); }
}
// A class summary must distinguish rebinding a slice variable from storing
// a reference into storage that merely contains one.
let LIFE_STORE_SLICE_SLOT: i64 = 0;

// reached: the type the destination was reached as (the pointee of the
// reference the place was named through), or -1. It stays with a store into
// a storage class, which is every storage an argument's storage refers to:
// a call lands the store in those that such a destination can lie in. With
// only the root on record, `pushExit(self_.exits, module)` put a reference
// to `module` into everything `self_` refers to at the calls above it.
// exact: the store names the root's own storage (not storage only known to
// outlive it).
fn life_add_contents(p: Program&, l: Lifetimes&, root: i64, storing: i64, exact: bool = false, reached: i64 = -1, slice_slot: bool = false) {
    if root == 0 { return; }
    var sources = storing; var owned = 0;
    if exact && l.class_frames > 0 { owned = life_own_reads(l, root, storing, true); if owned != 0 { sources = life_own_reads(l, root, storing, false); } }
    var kept = storing;
    if l.class_frames > 0 && storing != 0 && l.roots[root].frame <= 0 && l.roots[root].class_frame < 0 && l.roots[root].depth == 0 {
        kept = life_lasting(l, kept);
        if life_has_class(l, kept) { if l.island > 0 { kept = life_keep_outside(l, kept); } else { kept = life_strip(l, kept); } }
    }
    let next = life_join(l, l.roots[root].contents, kept);
    if !life_equal(l, next, l.roots[root].contents) { life_set_contents(l, root, next); l.revision += 1; }
    var as_type: i64 = -1;
    if reached >= 0 && (l.roots[root].class_frame >= 0 && l.roots[root].class_parent < 0 || root == l.globals_root) { as_type = reached; }
    if sources != 0 {
        if l.frame > 0 && (l.roots[root].frame != l.frame || l.frames[l.frame].recursive_call) {
            var field: i64 = -1;
            if slice_slot { field = LIFE_STORE_SLICE_SLOT; }
            let eff = LifeEffect { kind: 4, node: -1, value: LifeValue { type_id: as_type as i32, contents: sources as i32 }, places: life_root_set(l, root) as i32, field: field as i32 };
            life_effect(p, l, eff);
        } else {
            l.offer_count += 1;
        }
    }
    if owned != 0 { life_own_effects(p, l, root, owned); }
    if !l.discovery {
        life_set_live_contents(l, root, life_join(l, l.roots[root].live_contents, kept));
        if !life_only_static(l, storing) { life_clear_kills(l, root); }
    } else if l.roots[root].class_frame < 0 && l.roots[root].frame > 0 {
        let joined = life_join(l, l.roots[root].live_contents, kept);
        l.roots[root].live_contents = joined;
    }
    // Classes need not be disjoint: what is stored through one is kept with
    // it, for the reads through any other that may be the same storage
    // (life_class_stores).
    let owner = l.roots[root].class_frame;
    if owner >= 0 && sources != 0 && l.frames[owner].active && l.roots[root].class_index != l.frames[owner].result_class {
        let held = life_join(l, l.roots[root].stored, sources);
        if !life_equal(l, held, l.roots[root].stored) {
            l.roots[root].stored = held; l.revision += 1; l.frames[owner].stored_version += 1; l.held_epoch += 1; if !l.discovery { l.holder_grow_epoch += 1; }
            let all_s = life_join(l, l.frames[owner].all_stored, sources);
            l.frames[owner].all_stored = all_s;
            if l.roots[root].stored_next == -2 { l.roots[root].stored_next = l.frames[owner].stored_first; l.frames[owner].stored_first = root; l.frames[owner].stored_count += 1; }
        }
    }
}
fn life_stored_roots(p: Program&, l: Lifetimes&, value: const LifeValue&) -> i64 {
    let sources = life_value_roots(p, value);
    if sources == 0 || !life_is_ref(p, value.type_id) { return sources; }
    let elem = p.types[value.type_id].element as i32;
    let first = l.sets[sources].first as i64; let count = l.sets[sources].count as i64;
    var unchanged = true;
    for i in 0..count { if l.alts[first + i].target_type != elem { unchanged = false; break; } }
    if unchanged { return sources; }
    let start = l.scratch.len;
    for i in 0..count { var alt = l.alts[first + i]; alt.target_type = elem; l.scratch.push(alt); }
    let result = life_list_set(l, start, true);
    l.scratch.resize(start);
    return result;
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
        if inside { let place = l.alts[l.sets[places].first]; inside = life_exact_same(p, l, pool, place); }
        if !inside { life_error(p, l, node, "pool-relative self must be constructed directly inside its named pool"); }
        at = pool.next;
    }
}

fn life_relative_store(p: Program&, l: Lifetimes&, node: i64, places: i64, value: const LifeValue&) {
    if value.type_id >= 0 && p.types[value.type_id].kind == TY_REF && p.types[value.type_id].length_storage >= 0 && value.refs != 0 {
        if p.types[value.type_id].pool < 0 && places == 0 { return; }
        var target = places;
        let pool = p.types[value.type_id].pool;
        let named = life_pool_places(p, l, pool); if named != 0 { target = named; }
        var same = l.sets[target].count == 1 && l.sets[value.refs].count == 1;
        if same {
            let a = l.alts[l.sets[target].first]; let b = l.alts[l.sets[value.refs].first];
            same = life_exact_same(p, l, a, b);
        }
        if !same { life_error(p, l, node, "relative reference must point into the exact root that owns its destination"); }
    }
}

// The type a store's destination is reached as: what the last reference or
// slice on the destination's path points at, which holds the slot by value
// (upstream Dest::reached). A use of a reference variable is a dereference
// node of it. -1 where the path names a variable's own storage.
// slot: the destination is the slot itself (a reference field rebound), not
// what a reference in it points at.
fn life_reached(p: Program&, destination: i64, slot: bool = false) -> i64 {
    var at = destination;
    while at >= 0 {
        let n: const Node& = p.nodes[at];
        if n.kind == N_UNARY && n.integer == T_MUL { return n.type_id; }
        if !slot && n.type_id >= 0 && p.types[n.type_id].kind == TY_REF && at == destination { return p.types[n.type_id].element; }
        if n.kind != N_MEMBER && n.kind != N_INDEX || n.left < 0 { return -1; }
        let base = p.nodes[n.left].type_id;
        if base >= 0 && (p.types[base].kind == TY_REF || p.types[base].kind == TY_SLICE) { return p.types[base].element; }
        at = n.left;
    }
    return -1;
}
inline fn life_dest_reached(l: Lifetimes&, place: i64) -> i64 {
    if place != 0 && place == l.dest_place { return l.dest_reached; }
    return -1;
}
fn life_bind(p: Program&, l: Lifetimes&, node: i64, cell: i64, value: const LifeValue&, sources: i64) {
    // Revisited declarations start a fresh destination binding;
    // the source's caller-storage constraint remains in sources.
    let nk = p.nodes[node].kind;
    let is_decl = nk == N_VARIABLE || nk == N_BINDING;
    if is_decl {
        l.cells[cell].committed = false; l.cells[cell].initial = 0;
    }
    if !l.discovery {
        if is_decl || l.conditional == 0 { l.cells[cell].readonly = value.readonly; }
        else if value.readonly { l.cells[cell].readonly = true; }
    }
    let mutable_sym = (p.symbols[l.cells[cell].symbol].flags & S_MUTABLE) != 0;
    if sources != 0 && (!is_decl || mutable_sym) {
        var added = is_decl;
        if !added {
            var at = l.sets[sources].first;
            while at >= 0 {
                let source: const LifeAlt& = l.alts[at]; let previous = life_find(l, l.cells[cell].initial, source.root);
                if previous < 0 || source.bound != l.alts[previous].bound { added = true; break; }
                at = source.next;
            }
        }
        if added {
            if !l.discovery {
                let growshrink = life_gs_value(p, l, value);
                if l.cells[cell].committed && !l.cells[cell].growshrink && growshrink { life_error(p, l, node, "reference binding cannot start pointing into grow-shrink elements after its first binding"); }
                if !l.cells[cell].committed { l.cells[cell].growshrink = growshrink; }
            }
            let depth = life_binding_depth(l, sources);
            if l.cells[cell].committed && depth != l.cells[cell].depth {
                life_scope_error(p, l, node, 0);
            }
            if !l.cells[cell].committed { l.cells[cell].committed = true; l.cells[cell].depth = depth as i32; l.cells[cell].initial = sources as i32; }
        }
    }
    var kept = sources;
    if l.class_frames > 0 && sources != 0 && l.cell_keys[cell].global {
        kept = life_lasting(l, kept);
        if life_has_class(l, kept) { if l.island > 0 { kept = life_keep_outside(l, kept); } else { kept = life_strip(l, kept); } }
    }
    let next = life_join(l, l.cells[cell].refs, kept);
    if !life_equal(l, next, l.cells[cell].refs) { life_set_refs(l, cell, next); l.revision += 1; }
    let bind_root = l.cells[cell].root;
    if l.frame > 0 && (l.roots[bind_root].frame != l.frame || l.frames[l.frame].recursive_call) {
        let eff = LifeEffect { kind: 5, node: node as i32, value: LifeValue { refs: sources as i32 }, places: life_root_set(l, bind_root) as i32, cell: cell as i32 };
        life_effect(p, l, eff);
    } else {
        l.offer_count += 1;
    }
    if !l.discovery || l.frame == 0 && l.cell_keys[cell].global {
        life_set_live_refs(l, cell, life_join(l, l.cells[cell].live_refs, kept));
    }
}

// A read through a class parameter is kept as a slot read even when its
// concrete container is hidden. A slice argument can itself be threaded,
// so its slot-read bit alone does not make its elements vary by activation.
fn life_cycle_destination(p: Program&, l: Lifetimes&, node: i64, dest: const LifeAlt&, path: i64) -> bool {
    if node < 0 || p.nodes[node].kind != N_ASSIGN || path < 0 || p.types[path].kind == TY_ARRAY { return false; }
    let root: const LifeRoot& = l.roots[dest.root];
    if !dest.exact || dest.from >= 0 || root.class_parent >= 0 ||
       root.class_frame >= 0 && root.class_index >= l.frames[root.class_frame].class_base { return true; }
    if !dest.slotread || root.class_frame < 0 { return false; }
    let target = check_place_root(p, p.nodes[node].left);
    if target < 0 { return false; }
    let ty = p.symbols[target].type_id;
    return ty >= 0 && p.types[ty].kind == TY_REF &&
           p.types[p.types[ty].element].kind != TY_ARRAY && p.types[p.types[ty].element].kind != TY_SLICE;
}

// path: life_reached of the destination's expression, where there is one.
fn life_store(p: Program&, l: Lifetimes&, node: i64, given: i64, value: const LifeValue&, binding: bool = false, through: bool = false, path: i64 = -1) {
    var sources = life_value_roots(p, value);
    let is_ref_val = life_tf_is_ref(p, l, value.type_id);
    if binding && is_ref_val { sources = value.refs; }
    let is_rel_ref = value.type_id >= 0 && p.types[value.type_id].kind == TY_REF && p.types[value.type_id].length_storage >= 0;
    if !binding && sources == 0 && value.self_pools == 0 && value.relative_roots == 0 && !is_rel_ref { return; }
    let places = life_place_candidates(l, given);
    if !l.discovery {
        if value.self_pools != 0 { life_self_destination(p, l, node, places, value.self_pools); }
        if value.relative_roots != 0 { life_self_destination(p, l, node, places, value.relative_roots); }
    }
    if !binding && is_rel_ref {
        if !l.discovery { life_relative_store(p, l, node, places, value); }
        let eff = LifeEffect { kind: 9, node: node as i32, value: value, places: places as i32 };
        life_effect(p, l, eff);
    }
    let stored = if sources != 0 || value.contents != 0 { life_stored_roots(p, l, value) } else { 0 };
    var destination = l.sets[places].first;
    while destination >= 0 {
        let d = l.alts[destination]; let owner: const LifeRoot& = l.roots[d.root];
        // (With class-keyed frames in use: static data takes no store. A
        // place that may be the empty default slice is one such.)
        if d.root == 0 && l.class_frames > 0 { destination = d.next; continue; }
        let global = owner.symbol >= 0 && (p.symbols[owner.symbol].flags & S_GLOBAL) != 0;
        if !l.discovery && (!binding || global || through) && life_gs_value(p, l, value) {
            life_error(p, l, node, "reference into grow-shrink elements cannot be stored in a field, element, or global\n  help: grow-shrink arrays (`T[>..<]`) may move or shrink elements; use a grow-only array (`T[>..]`), an index, or store a copy (§5.2)");
        }
        var at = l.sets[sources].first;
        while at >= 0 {
            let source = l.alts[at];
            if !l.discovery {
                let source_frame = l.roots[source.root].frame;
                if life_cyclic(p, l, l.frame) && !((binding || owner.temporary) && owner.frame == l.frame) && source.root != 0 && source_frame > 0 &&
                   (source_frame == l.frame || life_cyclic(p, l, source_frame)) {
                    life_error(p, l, node, "reference stored by a recursive cycle must be rooted outside every recursive activation");
                }
            }
            if !l.discovery && life_cyclic(p, l, l.frame) && source.root != 0 &&
               (l.roots[source.root].frame > 0 || l.roots[source.root].class_frame >= 0) &&
               !(binding && owner.frame == l.frame) && life_cycle_destination(p, l, node, d, path) {
                life_error(p, l, node, "references may only be passed down, not stored, inside a recursive cycle (§7.8)");
            }
            // What came straight out of a class's storage is whatever the
            // argument's storage holds: each call judges where it lands it.
            var class_read = false;
            if l.roots[source.root].class_frame >= 0 { class_read = l.roots[source.root].class_index >= l.frames[l.roots[source.root].class_frame].class_base || !source.exact && source.from == source.root; }
            if l.roots[source.root].depth > owner.depth && !(class_read && owner.frame == 0) {
                life_scope_error(p, l, node, 1);
            }
            // Storage known only to outlive a class root may be anything that
            // does: what it takes must outlive everything, or have come out
            // of that class's storage itself (upstream ShrinkTargets).
            if !d.exact && owner.class_frame >= 0 && source.root != 0 && l.roots[source.root].depth > 0 {
                var from_self = source.root == d.root && !source.exact;
                if !from_self {
                    var up = l.roots[source.root].class_parent;
                    while up >= 0 { if up == d.root { from_self = true; break; } up = l.roots[up].class_parent; }
                }
                if !from_self { life_scope_error(p, l, node, 1); }
            }
            at = source.next;
        }
        if binding && owner.symbol >= 0 && life_tf_is_ref(p, l, p.symbols[owner.symbol].type_id) {
            let cell = life_cell(p, l, owner.symbol);
            if cell >= 0 {
                life_bind(p, l, node, cell, value, sources);
            }
        }
        if stored != 0 {
            if !d.exact && owner.class_frame < 0 { l.unknown_stores = true; }
            var reached: i64 = -1; if !d.byteview { reached = d.target_type as i64; if reached < 0 { reached = path; } }
            let slice_slot = through && binding && d.exact && d.component < 0 && owner.class_frame >= 0 &&
                value.type_id >= 0 && p.types[value.type_id].kind == TY_SLICE;
            life_add_contents(p, l, d.root, stored, d.exact, reached, slice_slot);
        }
        destination = d.next;
    }
}
// Only call between root traversals, when the evaluator has returned and
// every surviving argument or tuple belongs to one of these arenas.
// Keep live item IDs stable: they also participate in the leaf hash.
fn life_keep_items(l: Lifetimes&, marked: u8[>..]&, pending: i64[>..]&, first: i64) {
    var at = first;
    loop {
        while at >= 0 && marked[at] == 0 {
            marked[at] = 1;
            let tuple = l.items[at].value.tuple;
            if tuple >= 0 { pending.push(tuple); }
            at = l.items[at].next;
        }
        if pending.len == 0 { return; }
        at = pending[pending.len - 1]; pending.pop();
    }
}
fn life_reclaim_items(l: Lifetimes&, standalone: const LifeStandalone[:]) {
    // The free list is ordered by index. While its head is in the first
    // half, fresh allocations can continue consuming the previous sweep.
    if l.items.len <= 65536 || l.free_item >= 0 && l.free_item < l.items.len / 2 { return; }
    var marked: u8[>..] = []; marked.resize(l.items.len, 0);
    var pending: i64[>..] = [];
    for root in standalone { life_keep_items(l, marked, pending, root.arguments); }
    for i in 0..l.frames.len {
        let frame: const LifeFrame& = l.frames[i];
        life_keep_items(l, marked, pending, frame.inputs);
        life_keep_items(l, marked, pending, frame.capture_inputs);
        life_keep_items(l, marked, pending, frame.result.tuple);
    }
    for i in 0..l.exits.len { life_keep_items(l, marked, pending, l.exits[i].value.tuple); }
    for i in 0..l.effects.len { life_keep_items(l, marked, pending, l.effects[i].value.tuple); }
    for i in 0..l.leaves.len { life_keep_items(l, marked, pending, l.leaves[i].value.tuple); }
    for i in 0..l.hold_count { life_keep_items(l, marked, pending, l.holds[i].value.tuple); }
    l.free_item = -1;
    var i = l.items.len;
    while i > 0 {
        i--;
        if marked[i] == 0 { l.items[i].next = l.free_item as i32; l.free_item = i; }
    }
}
fn life_mark_set(marked: u8[>..]&, set: i64) {
    if set > 0 && set < marked.len { marked[set] = 1; }
}
fn life_mark_value_sets(marked: u8[>..]&, value: const LifeValue&) {
    life_mark_set(marked, value.refs); life_mark_set(marked, value.contents);
    life_mark_set(marked, value.place); life_mark_set(marked, value.self_pools);
    life_mark_set(marked, value.relative_roots); life_mark_set(marked, value.element_array);
}
inline fn life_set_kept(marked: const u8[>..]&, set: i64) -> bool {
    return set <= 0 || (set < marked.len && marked[set] != 0);
}
// Compact l.alts in place between passes when unreachable discovery sets grow
// large. Live LifeSet IDs stay unchanged so no stored set IDs need rewriting,
// and live entries in memo tables are preserved across compaction.
fn life_reclaim_alts(l: Lifetimes&, standalone: const LifeStandalone[:]) {
    var marked: u8[>..] = []; marked.resize(l.sets.len, 0);
    var item_marked: u8[>..] = []; item_marked.resize(l.items.len, 0);
    var pending: i64[>..] = [];
    for root in standalone { life_keep_items(l, item_marked, pending, root.arguments); }
    for i in 0..l.roots.len {
        let r: const LifeRoot& = l.roots[i];
        life_mark_set(marked, r.contents); life_mark_set(marked, r.live_contents); life_mark_set(marked, r.stored);
        l.roots[i].any_set = 0; l.roots[i].any_serial = 0; l.roots[i].any_held = 0; l.roots[i].any_held_serial = 0; l.roots[i].last_atom_set = -1;
    }
    for i in 0..l.cells.len {
        let c: const LifeCell& = l.cells[i];
        life_mark_set(marked, c.refs); life_mark_set(marked, c.live_refs);
        life_mark_set(marked, c.contents); life_mark_set(marked, c.initial);
    }
    for i in 0..l.frames.len {
        let f: const LifeFrame& = l.frames[i];
        life_keep_items(l, item_marked, pending, f.inputs);
        life_keep_items(l, item_marked, pending, f.capture_inputs);
        life_keep_items(l, item_marked, pending, f.result.tuple);
        life_mark_value_sets(marked, f.result);
        life_mark_set(marked, f.destination); life_mark_set(marked, f.class_destination);
        life_mark_set(marked, f.class_stored); life_mark_set(marked, f.all_stored);
        life_mark_set(marked, f.dep_dest);
    }
    for i in 0..l.exits.len {
        life_keep_items(l, item_marked, pending, l.exits[i].value.tuple);
        life_mark_value_sets(marked, l.exits[i].value);
        life_mark_set(marked, l.exits[i].destination);
    }
    for i in 0..l.effects.len {
        life_keep_items(l, item_marked, pending, l.effects[i].value.tuple);
        life_mark_set(marked, l.effects[i].places);
        life_mark_value_sets(marked, l.effects[i].value);
    }
    for i in 0..l.leaves.len {
        life_keep_items(l, item_marked, pending, l.leaves[i].value.tuple);
        life_mark_value_sets(marked, l.leaves[i].value);
    }
    for i in 0..l.hold_count {
        life_keep_items(l, item_marked, pending, l.holds[i].value.tuple);
        life_mark_value_sets(marked, l.holds[i].value);
    }
    for i in 0..l.items.len {
        if item_marked[i] != 0 { life_mark_value_sets(marked, l.items[i].value); }
    }
    for i in 0..l.atoms.len { life_mark_set(marked, l.atoms[i].set); }
    for i in 0..l.roots.len {
        if !life_set_kept(marked, l.roots[i].stores) { l.roots[i].stores = 0; l.roots[i].stores_version = -1; }
    }
    // Clear dead set IDs from summary dedup caches while preserving live entries.
    for i in 0..l.summaries.len {
        let s: const LifeSummary& = l.summaries[i];
        if s.places > 0 && marked[s.places] == 0 { l.summaries[i].places = -1; }
        if s.refs > 0 && marked[s.refs] == 0 { l.summaries[i].refs = -1; }
        if s.contents > 0 && marked[s.contents] == 0 { l.summaries[i].contents = -1; }
        if s.place > 0 && marked[s.place] == 0 { l.summaries[i].place = -1; }
    }
    // Compact l.alts in place; live sets are in strictly increasing first order.
    var write: i64 = 0;
    for s in 1..l.sets.len {
        if marked[s] == 0 || l.sets[s].count <= 0 {
            l.sets[s].first = -1; l.sets[s].count = 0;
            l.sets[s].bound_depth = -1; l.sets[s].bound_result = 0;
            l.sets[s].plain = -1; l.sets[s].folded = -1; l.sets[s].lasting = -1; l.sets[s].interior = -1; l.sets[s].slotread = -1; l.sets[s].flags = 0;
            continue;
        }
        if !life_set_kept(marked, l.sets[s].bound_result) { l.sets[s].bound_depth = -1; l.sets[s].bound_result = 0; }
        if !life_set_kept(marked, l.sets[s].plain) { l.sets[s].plain = -1; }
        if !life_set_kept(marked, l.sets[s].folded) { l.sets[s].folded = -1; }
        if !life_set_kept(marked, l.sets[s].lasting) { l.sets[s].lasting = -1; }
        if !life_set_kept(marked, l.sets[s].interior) { l.sets[s].interior = -1; }
        if !life_set_kept(marked, l.sets[s].slotread) { l.sets[s].slotread = -1; }
        let old_first = l.sets[s].first as i64; let count = l.sets[s].count as i64;
        if write != old_first {
            for k in 0..count {
                var e = l.alts[old_first + k];
                if k + 1 < count { e.next = (write + k + 1) as i32; } else { e.next = -1; }
                l.alts[write + k] = e;
            }
            l.sets[s].first = write as i32;
        }
        write += count;
    }
    l.alts.resize(write);
    // Keep atom_slots pointing to compacted singleton alt indices.
    for i in 0..l.atom_slots.len {
        let set = l.atom_slots[i].set as i64;
        if set >= 0 { l.atom_slots[i].alt = l.sets[set].first; }
    }
    // Rebuild list_slots keeping only live canonical multi-sets.
    var live_lists: LifeListSlot[>..] = [];
    for i in 0..l.list_slots.len {
        let e = l.list_slots[i];
        let set = e.set as i64;
        if set > 0 && set < marked.len && marked[set] != 0 && l.sets[set].count >= 2 { live_lists.push(e); }
    }
    l.list_count = live_lists.len;
    var list_size: i64 = 1024; while list_size <= 2 * (l.list_count + 1) { list_size <<= 1; }
    l.list_slots.clear(); l.list_slots.resize(list_size, LifeListSlot {});
    let list_mask = list_size - 1;
    for entry in live_lists {
        var slot = entry.key & list_mask;
        while l.list_slots[slot].set >= 0 { slot = (slot + 1) & list_mask; }
        l.list_slots[slot] = entry;
    }
    // Evict only entries referencing compacted-away set IDs from memo caches.
    for i in 0..l.joins.len {
        let e: const LifeJoin& = l.joins[i];
        if e.a >= 0 && (!life_set_kept(marked, e.a) || !life_set_kept(marked, e.b) || !life_set_kept(marked, e.set)) { l.joins[i] = LifeJoin {}; }
    }
    for i in 0..l.contents_memo.len {
        let e: const LifeContents& = l.contents_memo[i];
        if e.places >= 0 && (!life_set_kept(marked, e.places) || !life_set_kept(marked, e.set)) { l.contents_memo[i] = LifeContents {}; }
    }
    for i in 0..l.held_own_memo.len {
        let e: const LifeHeldOwn& = l.held_own_memo[i];
        if e.set >= 0 && (!life_set_kept(marked, e.set) || !life_set_kept(marked, e.result)) { l.held_own_memo[i] = LifeHeldOwn {}; }
    }
    for i in 0..l.loaded.len {
        let e: const LifeLoaded& = l.loaded[i];
        if e.contents >= 0 && (!life_set_kept(marked, e.contents >> 1) || !life_set_kept(marked, e.places) || !life_set_kept(marked, e.set)) { l.loaded[i] = LifeLoaded {}; }
    }
    for i in 0..l.referable.len {
        let e: const LifeLoaded& = l.referable[i];
        if e.contents >= 0 && (!life_set_kept(marked, e.contents) || !life_set_kept(marked, e.set)) { l.referable[i] = LifeLoaded {}; }
    }
    for i in 0..l.local_reads.len {
        let e: const LifeLocalRead& = l.local_reads[i];
        if e.places >= 0 && (!life_set_kept(marked, e.places) || !life_set_kept(marked, e.contents) || !life_set_kept(marked, e.result)) { l.local_reads[i] = LifeLocalRead {}; }
    }
    for i in 0..l.readbacks.len {
        let e: const LifeReadBack& = l.readbacks[i];
        if e.places >= 0 && (!life_set_kept(marked, e.places) || !life_set_kept(marked, e.set)) { l.readbacks[i] = LifeReadBack {}; }
    }
    for i in 0..l.inexact_reads.len {
        let e: const LifeInexactRead& = l.inexact_reads[i];
        if e.places >= 0 && (!life_set_kept(marked, e.places) || !life_set_kept(marked, e.result)) { l.inexact_reads[i] = LifeInexactRead {}; }
    }
    for i in 0..l.far_cache.len {
        let e: const LifeFarMemo& = l.far_cache[i];
        if e.places >= 0 && !life_set_kept(marked, e.places) { l.far_cache[i] = LifeFarMemo {}; }
    }
    for i in 0..l.offers.len {
        let e: const LifeOffer& = l.offers[i];
        if e.frame >= 0 && (!life_set_kept(marked, e.places) || !life_set_kept(marked, e.refs) || !life_set_kept(marked, e.contents) || !life_set_kept(marked, e.place)) { l.offers[i] = LifeOffer {}; }
    }
    l.map_memo.clear();
    l.call_sigs.clear(); l.call_sig_heads.clear(); l.call_sig_data.clear(); l.chk_dep_roots.clear();
    l.held_walks.clear(); l.walk_memo_roots.clear();
    l.shrink_clean.clear(); l.global_shrink_clean.clear();
    l.asked.clear();
}
fn life_item(l: Lifetimes&, first: i64, index: i64) -> LifeValue {
    var at = first; var i = 0;
    while at >= 0 { if i == index { return l.items[at].value; } at = l.items[at].next; i += 1; }
    return LifeValue {};
}
// Items may be interleaved with those created by nested calls. Keep both ends
// while building a list; stored values need only its first item.
struct LifeItemList { first: i64 = -1, last: i64 = -1 }
inline fn life_append(l: Lifetimes&, list: LifeItemList&, value: const LifeValue&) {
    var item = l.free_item;
    if item < 0 { item = l.items.len; l.items.push(LifeItem { value: value }); }
    else { l.free_item = l.items[item].next; l.items[item] = LifeItem { value: value }; }
    if list.last >= 0 { l.items[list.last].next = item as i32; } else { list.first = item; }
    list.last = item;
}
// Each frame has at most one exit per target node. Entries survive replay.
fn life_find_exit(l: Lifetimes&, node: i64) -> i64 {
    var at = l.frames[l.frame].first_exit;
    while at >= 0 && l.exits[at].node != node { at = l.exits[at].next; }
    return at;
}
fn life_add_exit(l: Lifetimes&, node: i64, value: LifeValue, destination: i64 = 0, selected_result: i64 = -1) {
    let next = l.frames[l.frame].first_exit;
    let index = l.exits.len;
    l.exits.push(LifeExit { node: node as i32, next: next as i32, value: value, destination: destination as i32, selected_result: selected_result as i32 });
    l.frames[l.frame].first_exit = index;
}
fn life_control_destination(l: Lifetimes&, node: i64, destination: i64, selected_result: i64) {
    let index = life_find_exit(l, node);
    if index >= 0 {
        l.exits[index].destination = destination as i32;
        l.exits[index].selected_result = selected_result as i32;
        return;
    }
    life_add_exit(l, node, LifeValue {}, destination, selected_result);
}
recursive fn life_merge(l: Lifetimes&, a: LifeValue, b: LifeValue) -> LifeValue {
    var out = a;
    out.readonly = a.readonly || b.readonly;
    if out.type_id < 0 { out.type_id = b.type_id; }
    out.refs = life_join(l, a.refs, b.refs) as i32; out.place = life_join(l, a.place, b.place) as i32;
    out.contents = life_join(l, a.contents, b.contents) as i32;
    out.self_pools = life_join(l, a.self_pools, b.self_pools) as i32;
    out.relative_roots = life_join(l, a.relative_roots, b.relative_roots) as i32;
    if b.tuple >= 0 {
        var items = LifeItemList {}; var x = a.tuple; var y = b.tuple;
        while y >= 0 || x >= 0 {
            var av = LifeValue {}; var bv = LifeValue {};
            if x >= 0 { av = l.items[x].value; x = l.items[x].next; }
            if y >= 0 { bv = l.items[y].value; y = l.items[y].next; }
            let merged = life_merge(l, av, bv);
            life_append(l, items, merged);
        }
        out.tuple = items.first as i32;
    }
    return out;
}
fn life_branch(p: Program&, l: Lifetimes&, node: i64, value: const LifeValue&, depth: i64) {
    if l.discovery || (value.refs == 0 && value.contents == 0) { return; }
    var at = l.sets[life_value_roots(p, value)].first;
    while at >= 0 {
        let root: const LifeRoot& = l.roots[l.alts[at].root];
        var allowed = depth; if root.temporary { allowed += 1; }
        if root.depth > allowed { life_error(p, l, node, "control-flow value retains a reference into a scope that has ended"); }
        at = l.alts[at].next;
    }
}
recursive fn life_return_value(p: Program&, l: Lifetimes&, node: i64, value: LifeValue, target: i64) {
    var item = value.tuple;
    while item >= 0 { life_return_value(p, l, node, l.items[item].value, target); item = l.items[item].next; }
    if value.refs == 0 && value.contents == 0 { return; }
    var at = l.sets[life_value_roots(p, value)].first;
    while at >= 0 {
        let root: const LifeRoot& = l.roots[l.alts[at].root];
        if root.depth >= l.frames[target].base && root.depth > 0 {
            life_scope_error(p, l, node, 2);
        }
        at = l.alts[at].next;
    }
}
fn life_construct_value(p: Program&, l: Lifetimes&, node: i64, out: LifeValue&, destination: i64) {
    if out.type_id < 0 { return; }
    let kind = p.types[out.type_id].kind;
    if kind != TY_ARRAY && kind != TY_STRUCT && kind != TY_ENUM { return; }
    out.place = destination as i32; if out.place == 0 { out.place = life_temporary(p, l, node) as i32; }
    let dest_reached = life_dest_reached(l, out.place);
    var at = l.sets[out.place].first;
    while at >= 0 {
        let alt = l.alts[at];
        var reached: i64 = -1; if !alt.byteview { reached = alt.target_type as i64; if reached < 0 { reached = dest_reached; } }
        life_add_contents(p, l, alt.root, out.contents, false, reached);
        at = alt.next;
    }
}
fn life_arguments_equal(p: Program&, l: Lifetimes&, a: i64, b: i64) -> bool {
    var x = a; var y = b;
    while x >= 0 && y >= 0 {
        let av: const LifeValue& = l.items[x].value; let bv: const LifeValue& = l.items[y].value;
        if life_tf_is_ref(p, l, av.type_id) {
            if av.refs != bv.refs && !life_equal(l, av.refs, bv.refs) { return false; }
        } else if life_tf_holds(p, l, av.type_id) {
            if av.contents != bv.contents && !life_equal(l, av.contents, bv.contents) { return false; }
        }
        x = l.items[x].next; y = l.items[y].next;
    }
    return x == y;
}

fn life_root_class(p: Program&, l: Lifetimes&, a: const LifeAlt&, b: const LifeAlt&) -> bool {
    if a.exact != b.exact || a.slotread != b.slotread || a.byteview != b.byteview { return false; }
    let x: const LifeRoot& = l.roots[a.root]; let y: const LifeRoot& = l.roots[b.root];
    if a.root == 0 || b.root == 0 { return a.root == b.root; }
    if x.frame == 0 || y.frame == 0 { return a.root == b.root; }
    if x.temporary != y.temporary || !life_same(p, x.type_id, y.type_id) { return false; }
    if x.symbol >= 0 && (p.symbols[x.symbol].flags & S_CAPTURE) != 0 { return x.symbol == y.symbol; }
    if y.symbol >= 0 && (p.symbols[y.symbol].flags & S_CAPTURE) != 0 { return x.symbol == y.symbol; }
    return true;
}
// A hash of what life_root_class compares, so alternatives of one class
// hash alike: the flags, then a root that is static or in no frame by
// itself, or else whether it is a temporary, its type as life_same compares
// types, and its symbol where that is a captured binding.
fn life_class_hash(p: Program&, l: Lifetimes&, a: const LifeAlt&) -> i64 {
    var flags = 0; if a.exact { flags += 1; } if a.slotread { flags += 2; } if a.byteview { flags += 4; }
    let root: const LifeRoot& = l.roots[a.root]; var tag = 1; var x: i64 = a.root; var y: i64 = 0; var z: i64 = 0; var w: i64 = 0; var v: i64 = -1;
    if a.root != 0 && root.frame != 0 {
        tag = 2; x = 0; if root.temporary { x = 1; }
        let ty = root.type_id; y = -1;
        if ty >= 0 {
            let t: const Type& = p.types[ty]; y = t.kind + 1;
            if t.kind == TY_STRUCT || t.kind == TY_ENUM { z = t.declaration; }
            else if t.kind == TY_INT { z = t.count * 2 + (t.flags & TF_UNSIGNED); }
            else if t.kind == TY_FLOAT { z = t.count; }
            else if t.kind == TY_ARRAY { z = t.array_kind; w = t.element; }
            else if t.kind == TY_REF || t.kind == TY_SLICE { z = t.element; }
        }
        if root.symbol >= 0 && (p.symbols[root.symbol].flags & S_CAPTURE) != 0 { v = root.symbol; }
    }
    var h: u64 = 1469598103934665603;
    h = life_hash_step(h, flags);
    h = life_hash_step(h, tag);
    h = life_hash_step(h, x);
    h = life_hash_step(h, y);
    h = life_hash_step(h, z);
    h = life_hash_step(h, w);
    h = life_hash_step(h, v);
    return (h >> 1) as! i64;
}
// Whether every alternative of a has one of its class in b, as
// life_class_sets_equal asks it, through a table of b's class hashes.
fn life_classes_cover(p: Program&, l: Lifetimes&, a: i64, b: i64) -> bool {
    var size: i64 = 64; while size < 2 * l.sets[b].count { size <<= 1; }
    let table = l.class_slots.len; l.class_slots.resize(table + 2 * size, -1); let mask = size - 1;
    var bi = l.sets[b].first;
    while bi >= 0 {
        let key = life_class_hash(p, l, l.alts[bi]); var slot = key & mask;
        while l.class_slots[table + 2 * slot] >= 0 { slot = (slot + 1) & mask; }
        l.class_slots[table + 2 * slot] = bi; l.class_slots[table + 2 * slot + 1] = key; bi = l.alts[bi].next;
    }
    var covered = true; var ai = l.sets[a].first;
    while ai >= 0 && covered {
        let x: const LifeAlt& = l.alts[ai]; let key = life_class_hash(p, l, x); var slot = key & mask; var found = false;
        loop {
            let entry = l.class_slots[table + 2 * slot];
            if entry < 0 { break; }
            if l.class_slots[table + 2 * slot + 1] == key && life_root_class(p, l, x, l.alts[entry]) { found = true; break; }
            slot = (slot + 1) & mask;
        }
        if !found { covered = false; }
        ai = x.next;
    }
    l.class_slots.resize(table, -1);
    return covered;
}
fn life_class_sets_equal(p: Program&, l: Lifetimes&, a: i64, b: i64) -> bool {
    // life_root_class is an equivalence: equal hashes of its fields, then
    // the test itself, find what the scans below would.
    if a == b { return true; }
    if l.sets[a].count * l.sets[b].count > 256 { return life_classes_cover(p, l, a, b) && life_classes_cover(p, l, b, a); }
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
    if roots == 0 { return 0; }
    let first = l.sets[roots].first as i64; let count = l.sets[roots].count as i64;
    if count <= 0 { return 0; }
    var unchanged = true;
    for i in 0..count {
        let a: const LifeAlt& = l.alts[first + i];
        if a.from >= 0 || a.slotread { unchanged = false; break; }
    }
    if unchanged { return roots; }
    let start = l.scratch.len;
    for i in 0..count {
        var alt = l.alts[first + i]; alt.next = -1; alt.from = -1; alt.slotread = false;
        l.scratch.push(alt);
    }
    let res = life_list_set(l, start, true);
    l.scratch.resize(start);
    return res;
}
recursive fn life_cycle_value(l: Lifetimes&, value: LifeValue) -> LifeValue {
    var out = value; out.refs = life_clear_reads(l, value.refs) as i32; out.contents = life_clear_reads(l, value.contents) as i32; var items = LifeItemList {};
    var item = value.tuple;
    while item >= 0 { let cv = life_cycle_value(l, l.items[item].value); life_append(l, items, cv); item = l.items[item].next; }
    out.tuple = items.first as i32; return out;
}

fn life_cycle_head(l: Lifetimes&, frame: i64) -> i64 {
    var head = frame;
    while head > 0 && l.frames[head].cycle >= 0 && l.frames[head].cycle != head { head = l.frames[head].cycle; }
    return head;
}
fn life_cycle_call(p: Program&, l: Lifetimes&, target: i64, call: i64, destination: i64) {
    // Only an active callee or a member of a known cycle can close a cycle.
    if !l.frames[target].active && !l.frames[target].recursive_call { return; }
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
        let local: const LifeCell& = l.cells[cell];
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

// The deepest root of a frame's live cells, or 0. Frame 0 holds every
// global, at depth 0, so only its deep_cells are looked at.
fn life_reach(l: Lifetimes&, frame: i64) -> i64 {
    var reach = 0;
    if frame == 0 {
        for ci in l.deep_cells { if l.cells[ci].live && l.roots[l.cells[ci].root].depth > reach { reach = l.roots[l.cells[ci].root].depth; } }
        return reach;
    }
    var ci = l.frames[frame].first_cell;
    while ci >= 0 {
        let cell: const LifeCell& = l.cells[ci]; if cell.live && l.roots[cell.root].depth > reach { reach = l.roots[cell.root].depth; }
        ci = cell.next_frame;
    }
    return reach;
}
fn life_slice_slot_params(p: Program&, function_node: i64) -> bool {
    if (p.nodes[function_node].flags & F_RECURSIVE) != 0 { return false; }
    var formal = p.nodes[function_node].first;
    while formal >= 0 {
        let ty = p.nodes[formal].type_id;
        if ty >= 0 && p.types[ty].kind == TY_REF {
            let elem = p.types[ty].element;
            if elem >= 0 && p.types[elem].kind == TY_SLICE { return true; }
        }
        formal = p.nodes[formal].next;
    }
    return false;
}
fn life_input_depth(p: Program&, l: Lifetimes&, arguments: i64) -> i64 {
    var depth = 0; var item = arguments;
    while item >= 0 {
        let value: const LifeValue& = l.items[item].value;
        let incoming = life_set_depth(l, life_value_roots(p, value));
        if incoming > depth { depth = incoming; }
        item = l.items[item].next;
    }
    return depth;
}

// The caller's storage bounds a parameter read unless this call owns a
// private view of the holder's known contents. Lexical/callback reach keeps
// possibly aliased holders on their storage class instead. reach: life_reach
// of the lexical frame.
fn life_parameter_roots(p: Program&, l: Lifetimes&, sources: i64, type_id: i64, function_node: i64, reach: i64) -> i64 {
    if type_id >= 0 && p.types[type_id].kind == TY_REF && p.types[type_id].element >= 0 && p.types[p.types[type_id].element].kind == TY_SLICE { return sources; }
    if sources == 0 { return 0; }
    var view = false;
    if type_id >= 0 && p.types[type_id].kind == TY_REF && p.types[type_id].length_storage < 0 &&
       (p.nodes[function_node].flags & F_RECURSIVE) == 0 && l.sets[sources].count == 1 {
        let alt = l.alts[l.sets[sources].first]; let root: const LifeRoot& = l.roots[alt.root]; let element = p.types[type_id].element;
        if root.depth > reach && (alt.exact || root.temporary) && element >= 0 {
            if life_holds(p, element) && !root.temporary && (root.class_frame >= 0 || root.type_id >= 0 && !life_is_ref(p, root.type_id)) && l.sets[root.contents].count == 1 {
                view = l.alts[l.sets[root.contents].first].exact;
            }
        }
    }
    if view { return sources; }
    return life_bound(l, sources, LIFE_PARAMETER_BOUND);
}

// What life_arguments_equal compares of a frame's inputs, with the frame's
// lexical frame and selected result. kinds: per argument, two bits for
// whether that is its references, its contents or nothing, which its own
// type decides, under a leading 1; 0 for more arguments than fit. hash: of
// the sets compared, equal wherever life_arguments_equal holds between
// inputs of the same kinds.
struct LifeInputs { hash: i64, kinds: i64 }
fn life_inputs_key(p: Program&, l: Lifetimes&, arguments: i64, lexical: i64, selected_result: i64) -> LifeInputs {
    var h: u64 = 1469598103934665603; var kinds = 1; var count = 0; var input = arguments;
    h = life_hash_step(h, lexical); h = life_hash_step(h, selected_result);
    while input >= 0 {
        let v: const LifeValue& = l.items[input].value; var kind = 0; var part = 0;
        if life_tf_is_ref(p, l, v.type_id) { kind = 1; part = v.refs as i64; }
        else if life_tf_holds(p, l, v.type_id) { kind = 2; part = v.contents as i64; }
        count += 1; if count <= 30 { kinds = 4 * kinds + kind; }
        h = life_hash_step(h, part);
        input = l.items[input].next;
    }
    if count > 30 { kinds = 0; }
    return LifeInputs { hash: (h >> 1) as! i64, kinds: kinds };
}
inline fn life_inputs_bucket(l: Lifetimes&, function_node: i64, hash: i64) -> i64 {
    var h: u64 = (function_node as! u64) * 11400714819323198485 ^ (hash as! u64) * 14029467366897019727; h ^= h >> 29;
    return (h & ((l.input_heads.len - 1) as! u64)) as i64;
}
inline fn life_home_bucket(l: Lifetimes&, function_node: i64, home: i64, call: i64) -> i64 {
    var h: u64 = (function_node as! u64) * 11400714819323198485 ^ (home as! u64) * 14029467366897019727; h ^= h >> 29;
    h = (h ^ (call as! u64)) * 1099511628211; h ^= h >> 31;
    return (h & ((l.home_heads.len - 1) as! u64)) as i64;
}
// Links a frame into both indexes, as the newest of its buckets.
fn life_index_frame(l: Lifetimes&, index: i64) {
    let inputs = life_inputs_bucket(l, l.frames[index].function_node, l.frames[index].inputs_hash);
    l.frames[index].next_inputs = l.input_heads[inputs] as i64; l.input_heads[inputs] = index as i32;
    let home = life_home_bucket(l, l.frames[index].function_node, l.frames[index].home, l.frames[index].call);
    l.frames[index].next_home = l.home_heads[home] as i64; l.home_heads[home] = index as i32;
}
// Room for one more frame at two per bucket at most, on average. Relinking
// in index order keeps every chain newest first.
fn life_frames_reserve(l: Lifetimes&) {
    if l.frames.len < 2 * l.input_heads.len { return; }
    var size: i64 = 64; while 2 * size <= l.frames.len { size <<= 1; }
    l.input_heads.clear(); l.input_heads.resize(size, -1); l.home_heads.clear(); l.home_heads.resize(size, -1);
    for index in 1..l.frames.len { if l.frames[index].classes < 0 { life_index_frame(l, index); } }
}
// ---- Class-keyed frames ----
// A frame per set of argument roots follows every call path apart: a callee
// handed a caller's local is checked again for each frame of the caller, and
// a large program does not finish. Upstream Goose checks a function once per
// CLASS of arguments instead (its specializations, GetOrCreateSpec), and so
// does a call here once the program has made LIFE_CONCRETE_FRAMES frames:
// - life_classify gives each alternative of a reference or holder argument
//   a class: an exactly named root is one class wherever the call names it.
//   The key is each parameter's alternatives (class, flags, pointee type,
//   component, bound) and the classes' order by depth: ranks, with 0 kept
//   for depth 0. It does not depend on what any storage holds.
// - The frame's body sees one class root per class: storage of no frame, at
//   the class's rank. What that storage holds is a class root of its own, and
//   what that one's storage holds another; past those two reads it is only
//   "something that outlives it". The body is evaluated as an island: its
//   effects stop at it (life_effect), and it reaches no cell, hold or pending
//   read of its callers.
// - Each call then replays the frame's effects and takes its result with the
//   class roots mapped to the call's own roots (life_map_set): an argument
//   class is the argument's alternatives, a storage class what their storage
//   holds at that call (life_class_set). A store that lands in the call's
//   roots is checked against their depths there.
// - What the body must know beyond the key (may two classes alias, does one
//   point into grow-shrink elements) is asked of the call being evaluated and
//   kept as the frame's assumptions; a call that answers otherwise makes the
//   answer the cautious one, and the frame is checked again (life_class_check).
// Only a top-level function whose body reads no captured binding is keyed
// this way; the others keep a frame per set of roots, inside the island.
let LIFE_CONCRETE_FRAMES: i64 = 4096;

// The most alternatives of one set that get a class each, and the most
// classes of one call: past either, a set is one class as a whole. As
// upstream has it, only an argument of one alternative is told apart: a
// class per alternative made keys of dozens of classes on a large program,
// and a frame for each.
let LIFE_CLASS_ALTS: i64 = 1;
let LIFE_CLASS_LIMIT: i64 = 512;

// Appends one set to the key in key_scratch: its count and five numbers per
// alternative (class or -1 for static data, flags, pointee type, component,
// bound), or -1 and one such record for a set taken as one class. An exactly
// named root is one class wherever the call names it; any other alternative
// is a class of its own.
// reached: LifeValue.reached of the argument, or -1.
fn life_classify_set(l: Lifetimes&, c: LifeClasses&, set: i64, reached: i64 = -1) {
    let count = l.sets[set].count;
    if count > LIFE_CLASS_ALTS || (l.map_sets.len - c.sets) + count > LIFE_CLASS_LIMIT {
        var all_slots = true; var any_bytes = false; var bound: i64 = 0; var depth: i64 = 0; var at = l.sets[set].first;
        while at >= 0 {
            let alt = l.alts[at]; at = alt.next;
            if alt.root != 0 && !alt.slotread { all_slots = false; } if alt.byteview { any_bytes = true; }
            if l.roots[alt.root].depth > depth { depth = l.roots[alt.root].depth; }
        }
        var flags = 0; if all_slots { flags += 1; } if any_bytes { flags += 2; }
        bound = 0;
        let index = l.map_sets.len - c.sets; l.map_sets.push(set); l.map_roots.push(-1); l.map_types.push(reached); l.class_scratch.push(depth);
        l.key_scratch.push(-1); l.bound_scratch.push(l.key_scratch.len + 4);
        l.key_scratch.push(index); l.key_scratch.push(flags); l.key_scratch.push(-1); l.key_scratch.push(-1); l.key_scratch.push(bound);
        return;
    }
    l.key_scratch.push(count);
    var at = l.sets[set].first;
    while at >= 0 {
        let alt = l.alts[at]; at = alt.next;
        var flags = 0; if alt.slotread { flags += 1; } if alt.byteview { flags += 2; }
        var index = -1; var component = alt.component as i64; var bound = alt.bound as i64;
        if alt.root == 0 { if alt.exact { flags += 4; } bound = 0; }
        else {
            if alt.exact && (l.roots[alt.root].class_frame < 0 || l.roots[alt.root].class_one) { flags += 8; }
            let depth = l.roots[alt.root].depth; bound = 0;
            var as_type = alt.target_type as i64; if as_type < 0 { as_type = reached; }
            if alt.exact && l.roots[alt.root].map_serial == c.serial { index = l.roots[alt.root].map_class; if l.map_types[c.sets + index] != as_type { l.map_types[c.sets + index] = -1; } }
            else {
                index = l.map_sets.len - c.sets; l.class_scratch.push(depth);
                if alt.exact {
                    l.roots[alt.root].map_serial = c.serial; l.roots[alt.root].map_class = index;
                    l.map_sets.push(life_root_set(l, alt.root)); l.map_roots.push(alt.root); l.map_types.push(as_type);
                } else {
                    var own = alt; own.from = -1; own.next = -1; component = -1;
                    l.map_sets.push(life_alt_set(l, own)); l.map_roots.push(-1); l.map_types.push(as_type);
                }
            }
        }
        let key_tt = if alt.target_type >= 0 && l.types_frozen && l.nodes_prepared { l.type_exact_canon[alt.target_type] as i64 } else { alt.target_type as i64 };
        l.bound_scratch.push(l.key_scratch.len + 4);
        l.key_scratch.push(index); l.key_scratch.push(flags); l.key_scratch.push(key_tt); l.key_scratch.push(component); l.key_scratch.push(bound);
    }
}
// The rank code of a depth among a call's sorted depths: 0 for depth 0.
fn life_depth_code(l: Lifetimes&, depths: i64, count: i64, depth: i64) -> i64 {
    if depth <= 0 { return 0; }
    for rank in 0..count { if l.map_depths[depths + rank] == depth { return 2 * (rank + 1); } }
    return 0;
}
fn life_depth_note(l: Lifetimes&, depths: i64, depth: i64) {
    if depth <= 0 { return; }
    var at = depths; let end = l.map_depths.len;
    while at < end && l.map_depths[at] < depth { at += 1; }
    if at < end && l.map_depths[at] == depth { return; }
    l.map_depths.push(depth); var slot = l.map_depths.len - 1;
    while slot > at { l.map_depths[slot] = l.map_depths[slot - 1]; slot -= 1; }
    l.map_depths[at] = depth;
}
// Classifies a call: pushes its classes on map_sets and map_roots and its
// sorted depths on map_depths, and leaves its key in key_scratch: the
// function and selected result; for each parameter its kind (0 no roots, 1
// references, 2 a holder's contents) and set; for a receiver-sensitive
// result the destination likewise (kind 4); the class count and each
// class's depth code. Without a receiver-sensitive result, the last class is
// the destination's, deeper than every other.
fn life_classify(p: Program&, l: Lifetimes&, function_node: i64, arguments: i64, destination: i64, receiver_sensitive: bool, selected_result: i64) -> LifeClasses {
    l.classify_serial += 1;
    var c = LifeClasses { sets: l.map_sets.len, depths: l.map_depths.len, serial: l.classify_serial };
    l.key_scratch.clear(); l.class_scratch.clear(); l.bound_scratch.clear();
    l.key_scratch.push(function_node); l.key_scratch.push(selected_result);
    var input = arguments; var formal = p.nodes[function_node].first;
    while formal >= 0 {
        var value = LifeValue {};
        var reached: i64 = -1;
        if input >= 0 { reached = l.items[input].value.reached; value = life_coerce(p, l, l.items[input].value, p.nodes[formal].type_id); input = l.items[input].next; }
        let set = life_fold(l, life_value_roots(p, value)); var kind = 0;
        if set != 0 && l.sets[set].count > 0 { kind = 2; if life_is_ref(p, value.type_id) { kind = 1; } }
        l.key_scratch.push(kind); if kind != 0 { life_classify_set(l, c, set, reached); }
        formal = p.nodes[formal].next;
    }
    if receiver_sensitive {
        var kind = 4; if destination == 0 || l.sets[destination].count == 0 { kind = 0; }
        l.key_scratch.push(kind); if kind != 0 { life_classify_set(l, c, destination, life_dest_reached(l, destination)); }
    }
    else { l.map_sets.push(destination); l.map_roots.push(-1); l.map_types.push(life_dest_reached(l, destination)); l.class_scratch.push(-1); }
    // A call of no roots at all still has one class, which nothing names.
    if l.map_sets.len == c.sets { l.map_sets.push(0); l.map_roots.push(-1); l.map_types.push(-1); l.class_scratch.push(0); }
    c.count = l.map_sets.len - c.sets;
    for item in 0..4 * c.count { l.map_sets.push(-1); l.map_roots.push(-1); l.map_types.push(-1); }
    for item in 0..c.count { life_depth_note(l, c.depths, l.class_scratch[item]); }
    for slot in l.bound_scratch { life_depth_note(l, c.depths, l.key_scratch[slot]); }
    c.depth_count = l.map_depths.len - c.depths;
    for slot in l.bound_scratch { l.key_scratch[slot] = life_depth_code(l, c.depths, c.depth_count, l.key_scratch[slot]); }
    l.key_scratch.push(c.count);
    for item in 0..c.count {
        var code = 2 * (c.depth_count + 1); if l.class_scratch[item] >= 0 { code = life_depth_code(l, c.depths, c.depth_count, l.class_scratch[item]); }
        l.key_scratch.push(code);
    }
    c.key_len = l.key_scratch.len;
    var h: u64 = 1469598103934665603;
    for part in l.key_scratch { h = (h ^ (part as! u64)) * 1099511628211; h ^= h >> 29; }
    c.hash = (h >> 1) as! i64;
    return c;
}
// How many questions a frame records before the rest get the cautious
// answer: a body that reads hundreds of pointee types out of its arguments'
// storage would ask of every pair of them.
let LIFE_ASSUME_LIMIT: i64 = 65536;
// The cautious answer to a question: the classes may alias, the class may
// point into grow-shrink elements, it is not known to be one array or root.
inline fn life_cautious(query: i64) -> bool { return query != 2 && query != 6; }
// A frame serves every call with its key. Where a call (its sets at `sets`)
// answers a question the body asked otherwise than the body was checked
// with, the cautious answer takes its place for good and the body is checked
// again: answers only ever move that way, so this ends.
fn life_class_check(p: Program&, l: Lifetimes&, frame: i64, sets: i64, min_ver: i32 = 0) {
    let saved_in_chk = l.in_class_check; l.in_class_check = true;
    let saved_chk_island = l.chk_island; l.chk_island = l.island;
    let serial = l.any_serial; l.classify_serial += 1; l.any_serial = l.classify_serial;
    var prev: i64 = -1;
    var at = l.frames[frame].assumptions;
    while at >= 0 {
        let a = l.assumes[at]; let nxt = a.next as i64;
        if min_ver > 0 && a.ver <= min_ver { break; }
        let cautious = life_cautious(a.query as i64);
        if a.open == 0 && a.answer != cautious {
            if life_class_answer(p, l, frame, sets, a.query as i64, a.index as i64, a.subject as i64, a.flag) != a.answer {
                l.assumes[at].answer = cautious; life_assume_sync_slot(l, at); l.revision += 1; l.frames[frame].stored_version += 1; l.held_epoch += 1;
                l.frames[frame].dep_change_stamp += 1; l.frames[frame].dep_valid = false; l.frames[frame].dep_clean_pass = -1;
                if !l.frames[frame].active { l.frames[frame].validated = false; l.frames[frame].checked_revision = -1; }
                if prev >= 0 {
                    l.assumes[prev].next = nxt as i32; l.assumes[at].next = -2;
                } else if l.frames[frame].assumptions == at {
                    l.frames[frame].assumptions = nxt; l.assumes[at].next = -2;
                } else {
                    prev = at;
                }
                at = nxt; continue;
            }
            prev = at;
        } else if a.open == 0 && a.answer == cautious {
            if prev >= 0 {
                l.assumes[prev].next = nxt as i32; l.assumes[at].next = -2;
            } else if l.frames[frame].assumptions == at {
                l.frames[frame].assumptions = nxt; l.assumes[at].next = -2;
            } else {
                prev = at;
            }
            at = nxt; continue;
        } else {
            prev = at;
        }
        at = nxt;
    }
    l.any_serial = serial;
    l.chk_island = saved_chk_island;
    l.in_class_check = saved_in_chk;
}
// The frame with the key in key_scratch, or -1.
fn life_class_frame(l: Lifetimes&, c: const LifeClasses&) -> i64 {
    if l.class_heads.len == 0 { return -1; }
    var index = l.class_heads[c.hash & (l.class_heads.len - 1)];
    while index >= 0 {
        let frame: const LifeFrame& = l.frames[index];
        if frame.key_hash == c.hash && frame.key_len == c.key_len {
            var same = true; let key = frame.key;
            for item in 0..c.key_len { if l.class_keys[key + item] != l.key_scratch[item] { same = false; break; } }
            if same { return index; }
        }
        index = frame.next_class;
    }
    return -1;
}
// The set a key's record at `at` stands for in a frame whose class roots
// start at `classes`, and where the record ends.
struct LifeKeySet { set: i64, next: i64 }
fn life_key_set(l: Lifetimes&, at: i64, classes: i64) -> LifeKeySet {
    var count = l.class_keys[at]; var cursor = at + 1; if count < 0 { count = 1; }
    var out = LifeBuild {};
    for item in 0..count {
        let index = l.class_keys[cursor]; let flags = l.class_keys[cursor + 1];
        var alt = LifeAlt { root: 0, target_type: l.class_keys[cursor + 2] as i32, bound: l.class_keys[cursor + 4] as i32, component: l.class_keys[cursor + 3] as i32, exact: (flags & 4) != 0, slotread: (flags & 1) != 0, byteview: (flags & 2) != 0 };
        if index >= 0 { alt.root = (classes + index) as i32; alt.exact = true; if (flags & 8) != 0 { l.roots[classes + index].class_one = true; } }
        life_build_add_alt(l, out, alt); cursor += 5;
    }
    return LifeKeySet { set: life_build_end(l, out), next: cursor };
}
// Notes on each argument class of a parameter's set what the parameter
// points at (LifeRoot.class_pointee); pointee < 0 for a holder's contents or
// a destination, whose roots may be of any type.
fn life_class_points(p: Program&, l: Lifetimes&, set: i64, classes: i64, n: i64, pointee: i64, holder: i64 = -1) {
    var at = l.sets[set].first;
    while at >= 0 {
        let root = l.alts[at].root as i64; at = l.alts[at].next;
        if root < classes || root >= classes + n { continue; }
        let old = l.roots[root].class_pointee;
        if pointee < 0 || old == -2 { l.roots[root].class_pointee = -2; }
        else if old == -1 || life_contains(p, l, pointee, old) { l.roots[root].class_pointee = pointee; }
        else if !life_contains(p, l, old, pointee) { l.roots[root].class_pointee = -2; }
        let old_h = l.roots[root].class_holder;
        if holder < 0 || old_h == -2 { l.roots[root].class_holder = -2; }
        else if old_h == -1 || life_contains(p, l, holder, old_h) { l.roots[root].class_holder = holder; }
        else if !life_contains(p, l, old_h, holder) { l.roots[root].class_holder = -2; }
    }
}
// A new frame for the key in key_scratch: its class roots, the arguments
// its parameters are bound to, and the place its body builds a result in.
// After the classes of the arguments come, class for class, what their
// storage holds and what the storage of that holds; the last holds only
// something read out of itself, which a call maps one read further and
// anything beyond takes as a bound.
// With class-keyed frames a summary's effects are merged by kind alone and
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
                var effect = LifeEffect { kind: 3, node: leaf.node, value: leaf.value, places: places as i32 }; effect.owner = frame as i32;
                life_summary_reserve(l);
                let skey = life_summary_key(frame, life_summary_base_hash(effect, leaf.node));
                l.summaries.push(LifeSummary { owner: frame as i32, kind: 3, node: leaf.node as i32,
                    type_id: leaf.value.type_id as i32, cell: effect.cell as i32, field: effect.field as i32, places: seen_places as i32, refs: seen.refs as i32, contents: seen.contents as i32, place: seen.place as i32,
                    walked: entry.walked, leaf: entry.leaf });
                life_summary_insert(l, skey, index, frame); l.effects.push(effect);
                if last >= 0 { l.effects[last].next = index as i32; l.summaries[last].after = index as i32; } else { l.frames[frame].first_summary = index; }
                last = index;
            }
            if at < 0 { break; }
            let next = l.effects[at].next;
            if last >= 0 { l.effects[last].next = at as i32; l.summaries[last].after = at as i32; } else { l.frames[frame].first_summary = at; }
            last = at; at = next;
        }
        l.effects[last].next = -1; l.summaries[last].after = -1; l.frames[frame].last_summary = last;
        l.frames[frame].first_read = -1; l.frames[frame].last_read = -1; l.frames[frame].read_cap = 0; l.frames[frame].read_count = 0;
    }
    l.summary_reads.clear(); l.read_slots.clear();
}
fn life_class_new(p: Program&, l: Lifetimes&, function_node: i64, call: i64, selected_result: i64, receiver_sensitive: bool, c: const LifeClasses&) -> i64 {
    if l.compact { life_reads_materialize(p, l); }
    let target = l.frames.len; let newest = l.function_frames[function_node] as i64; let key = l.class_keys.len;
    if l.type_canon.len < p.types.len { life_canon_types(p, l); }
    for part in l.key_scratch { l.class_keys.push(part); }
    let classes = l.roots.len; let codes = key + c.key_len - c.count; var base = 2; let n = c.count;
    for level in 0..3 {
        for k in 0..n {
            let depth = l.class_keys[codes + k]; if depth + 2 > base { base = depth + 2; }
            l.roots.push(LifeRoot { frame: 0, depth: depth, class_frame: target, class_index: level * n + k });
        }
    }
    for k in 0..n {
        let one = life_root_set(l, classes + n + k); life_set_contents(l, classes + k, one); life_set_live_contents(l, classes + k, one);
        let two = life_root_set(l, classes + 2 * n + k); life_set_contents(l, classes + n + k, two); life_set_live_contents(l, classes + n + k, two);
        let rest = life_single(l, classes + 2 * n + k, false, classes + 2 * n + k); life_set_contents(l, classes + 2 * n + k, rest); life_set_live_contents(l, classes + 2 * n + k, rest);
    }
    var items = LifeItemList {}; var formal = p.nodes[function_node].first; var cursor = key + 2;
    while formal >= 0 {
        let kind = l.class_keys[cursor]; cursor += 1; var value = LifeValue { type_id: p.nodes[formal].type_id as i32 };
        if kind != 0 {
            let record = life_key_set(l, cursor, classes); cursor = record.next;
            if kind == 1 { value.refs = record.set as i32; } else { value.contents = record.set as i32; }
            var pointee = -1; var holder = -1; let ft = p.nodes[formal].type_id;
            if kind == 1 && ft >= 0 && life_is_ref(p, ft) { pointee = p.types[ft].element; }
            else if kind == 2 && ft >= 0 && life_tf_holds(p, l, ft) { holder = ft; }
            life_class_points(p, l, record.set, classes, n, pointee, holder);
        }
        life_append(l, items, value); formal = p.nodes[formal].next;
    }
    let inputs = items.first;
    // An argument class whose parameters point at a type that holds no
    // reference has storage that holds none: it has no storage class to be
    // stored into or read out of. (Bytes are left alone: they may be a view
    // of anything.)
    for k in 0..n {
        let pointee = l.roots[classes + k].class_pointee;
        if pointee >= 0 && !life_tf_holds(p, l, pointee) && pointee != TYPE_U8 && p.types[pointee].element != TYPE_U8 { life_set_contents(l, classes + k, 0); life_set_live_contents(l, classes + k, 0); }
    }
    var place = life_root_set(l, classes + n - 1); var result_class = n - 1;
    if receiver_sensitive {
        let kind = l.class_keys[cursor]; cursor += 1; place = 0; result_class = -1;
        if kind != 0 { let record = life_key_set(l, cursor, classes); cursor = record.next; place = record.set; life_class_points(p, l, place, classes, n, -1); }
    }
    l.frames.push(LifeFrame { function_node: function_node, parent: l.frame, lexical: 0, call: call, inputs: inputs, base: base, slice_slots: life_slice_slot_params(p, function_node), selected_result: selected_result, next_function: newest, home: l.frame,
        island: target, classes: classes, class_count: 3 * n, class_base: n, key: key, key_len: c.key_len, key_hash: c.hash, class_destination: place, result_class: result_class });
    if newest >= 0 { l.frames[target].function_active = l.frames[newest].function_active; l.frames[target].inputs_kinds = l.frames[newest].inputs_kinds; l.frames[target].mixed_kinds = l.frames[newest].mixed_kinds; }
    else { l.frames[target].mixed_kinds = true; }
    l.function_frames[function_node] = target as i32; l.class_frames += 1; l.class_list.push(target);
    if l.class_list.len > l.class_heads.len {
        var size: i64 = 64; while size < 2 * l.class_list.len { size <<= 1; }
        l.class_heads.clear(); l.class_heads.resize(size, -1);
        for index in l.class_list { let bucket = l.frames[index].key_hash & (size - 1); l.frames[index].next_class = l.class_heads[bucket]; l.class_heads[bucket] = index; }
    } else {
        let bucket = c.hash & (l.class_heads.len - 1); l.frames[target].next_class = l.class_heads[bucket]; l.class_heads[bucket] = target;
    }
    return target;
}
// Whether a root belongs to another island than the one being evaluated: a
// local or temporary of its frames, or one of its class roots. No such root
// means anything here.
inline fn life_elsewhere(l: Lifetimes&, root: i64) -> bool {
    let frame = l.roots[root].frame; let owner = l.roots[root].class_frame;
    return frame > 0 && l.frames[frame].island != l.island || owner >= 0 && owner != l.island;
}
// Adds to a build what alternative x of a class root becomes over the
// alternatives the class stands for (`source`). read: x was read out of the
// class's storage, and the alternatives are what that storage holds.
// want: where x is an exact reference to a `want` that a storage class
// holds, only what such a value can lie in is taken: what the argument's
// storage holds a reference to (or the root, or an argument class's
// parameters' type, where the reference's own type is not known) must hold
// one inline. -1: everything.
// place: x is a store's place at an argument class. It is reached as the
// call's reference reaches it; else as the argument's expression does
// (reached); else as the callee's store did (x's own type).
fn life_map_onto(p: Program&, l: Lifetimes&, out: LifeBuild&, source: i64, x: const LifeAlt&, bound: i64, read: bool, want: i64 = -1, place: bool = false, reached: i64 = -1) {
    let exact = x.exact || read;
    let sfirst = l.sets[source].first as i64; let scount = l.sets[source].count as i64;
    var globals_ok: i64 = -1;
    for si in 0..scount {
        let a: const LifeAlt& = l.alts[sfirst + si];
        if want >= 0 && a.exact && !a.byteview && a.root != 0 {
            var within = a.target_type as i64;
            if within < 0 {
                if l.roots[a.root].class_frame >= 0 {
                    if !life_class_holds(p, l, a.root as i64, want) { continue; }
                } else { within = l.roots[a.root].type_id; }
            }
            if within >= 0 && !life_contains_memo(p, l, within, want) { continue; }
        }
        if want >= 0 && !a.exact && !a.byteview && a.root != 0 {
            if a.target_type >= 0 && !life_contains_memo(p, l, a.target_type as i64, want) { continue; }
            if a.from == a.root && l.roots[a.root].class_frame >= 0 && l.roots[a.root].class_parent >= 0 && !life_holder_points(p, l, l.roots[a.root].class_type, want) { continue; }
        }
        if want >= 0 && !a.byteview && life_is_global_bound(l, a) {
            if globals_ok < 0 { if life_globals_contain(p, l, want) { globals_ok = 1; } else { globals_ok = 0; } }
            if globals_ok == 0 { continue; }
        }
        var slotread = x.slotread; if x.exact { slotread = a.slotread && x.slotread; }
        var target = x.target_type; if target < 0 { target = a.target_type; } else if want < 0 && a.target_type >= 0 && a.target_type != target { target = -1; }
        if place && x.exact && !a.byteview && !x.byteview { target = a.target_type; if target < 0 { target = reached as i32; } if target < 0 { target = x.target_type; } }
        var component: i32 = -1; if exact { component = a.component; if component < 0 && x.exact { component = x.component; } }
        var from: i32 = -1; if read && a.from == a.root && l.roots[a.root].class_frame >= 0 { from = a.from; }
        var mapped_alt = LifeAlt { root: a.root, from: from, target_type: target, bound: bound as i32, component: component, exact: a.exact && exact, slotread: slotread, byteview: a.byteview || x.byteview };
        if want >= 0 && !mapped_alt.byteview && mapped_alt.exact && mapped_alt.root != 0 && l.roots[mapped_alt.root].class_frame >= 0 && l.roots[mapped_alt.root].class_parent < 0 {
            let narrowed = life_class_narrow(p, l, mapped_alt, -1, want);
            if narrowed.root != mapped_alt.root { mapped_alt.root = narrowed.root; mapped_alt.target_type = want as i32; }
        }
        life_build_add_alt(l, out, mapped_alt);
    }
}
// A set of a class-keyed frame as one call reads it: each alternative at a
// class root becomes the call's own, and the rest stay. An argument class
// is the argument's alternatives; a storage class is what the storage of
// those holds now; an alternative read out of the last storage class is what
// that holds in turn; any other inexact one is a bound.
// The places of a set that can take a store of references: a root whose
// type holds none is not where a store through "whatever this argument's
// storage holds" lands (a pool of plain numbers the argument has a slice of,
// say). What is only known to be reached from a root, a class of the island,
// a byte view and the folded globals stay.
fn life_can_take(p: Program&, l: Lifetimes&, set: i64) -> i64 {
    if set == 0 { return set; }
    let first = l.sets[set].first as i64; let count = l.sets[set].count as i64;
    var dropped = false;
    for i in 0..count {
        let x: const LifeAlt& = l.alts[first + i]; let root: const LifeRoot& = l.roots[x.root];
        if x.exact && !x.byteview && x.root != 0 && (root.class_empty || root.class_frame >= 0 && root.class_parent >= 0 && root.class_type >= 0 && !life_tf_holds(p, l, root.class_type) || root.class_frame >= 0 && root.class_parent < 0 && root.class_pointee >= 0 && !life_tf_holds(p, l, root.class_pointee) || root.class_frame < 0 && root.type_id >= 0 && !life_tf_holds(p, l, root.type_id)) { dropped = true; break; }
    }
    if !dropped { return set; }
    let start = l.scratch.len;
    for i in 0..count {
        var x = l.alts[first + i]; let root: const LifeRoot& = l.roots[x.root];
        if x.exact && !x.byteview && x.root != 0 && (root.class_empty || root.class_frame >= 0 && root.class_parent >= 0 && root.class_type >= 0 && !life_tf_holds(p, l, root.class_type) || root.class_frame >= 0 && root.class_parent < 0 && root.class_pointee >= 0 && !life_tf_holds(p, l, root.class_pointee) || root.class_frame < 0 && root.type_id >= 0 && !life_tf_holds(p, l, root.type_id)) { continue; }
        x.next = -1; l.scratch.push(x);
    }
    let result = life_list_set(l, start, true);
    l.scratch.resize(start);
    return result;
}
// stored: 1 for the places of a store of references (life_can_take), else 0.
fn life_map_set(p: Program&, l: Lifetimes&, set: i64, m: const LifeMap&, stored: i64 = 0) -> i64 {
    if set == 0 || m.count == 0 || (l.sets[set].flags & 1) != 0 { return set; }
    if l.sets[set].count == 1 {
        let x = l.alts[l.sets[set].first as i64];
        let k = (x.root as i64) - m.classes;
        if k >= 0 && k < m.base && x.exact {
            let mr = l.map_roots[m.sets + k];
            if mr >= 0 {
                if stored != 0 && !x.byteview && mr != 0 {
                    let mrt: const LifeRoot& = l.roots[mr];
                    if mrt.class_empty || mrt.class_frame >= 0 && mrt.class_parent >= 0 && mrt.class_type >= 0 && !life_tf_holds(p, l, mrt.class_type) || mrt.class_frame >= 0 && mrt.class_parent < 0 && mrt.class_pointee >= 0 && !life_tf_holds(p, l, mrt.class_pointee) || mrt.class_frame < 0 && mrt.type_id >= 0 && !life_tf_holds(p, l, mrt.type_id) { return 0; }
                }
                var target = x.target_type as i64;
                if stored != 0 && l.map_types[m.sets + k] >= 0 { target = l.map_types[m.sets + k]; }
                return life_single(l, mr, true, -1, x.slotread, x.byteview, target, 0, x.component as i64);
            }
        }
    }
    if l.map_memo.len == 0 { l.map_memo.resize(16384, LifeMapped {}); }
    let key_serial = if l.held_epoch == m.start_epoch { m.serial } else { 0 - 1 - m.call_serial };
    let ks32 = key_serial as i32; let key32 = ((set << 2) | stored) as i32;
    let can_cache = set < 536870912 && l.held_epoch < 2147483647;
    var mh: u64 = (set as! u64) * 11400714819323198485 ^ (key_serial as! u64) * 14029467366897019727 ^ (stored as! u64) * 1609587929392839161; mh ^= mh >> 29;
    let memo = (mh & ((l.map_memo.len - 1) as! u64)) as i64;
    let cur_ep = l.held_epoch as i32;
    if can_cache {
        let e0 = l.map_memo[memo];
        if e0.serial == ks32 && e0.key == key32 && (e0.epoch < 0 || e0.epoch == cur_ep) { return e0.result as i64; }
        let e1 = l.map_memo[memo ^ 1];
        if e1.serial == ks32 && e1.key == key32 && (e1.epoch < 0 || e1.epoch == cur_ep) { return e1.result as i64; }
    }
    let first = l.sets[set].first as i64; let count = l.sets[set].count as i64;
    var found = false; let end = m.classes + m.count;
    for i in 0..count {
        let root = l.alts[first + i].root as i64;
        if root >= m.classes && root < end || life_elsewhere(l, root) { found = true; break; }
    }
    if !found {
        if can_cache && count >= 4 { life_map_memo_put(l, memo, ks32, key32, set as i32, -1, cur_ep); }
        return set;
    }
    // fresh: nothing below reads contents, which change as the call's effects land.
    var fresh = true; var whole: i64[16] = [0; 16]; var whole_len: i64 = 0;
    var out = LifeBuild {}; var at = l.sets[set].first;
    while at >= 0 {
        var x = l.alts[at]; at = x.next; let k = (x.root as i64) - m.classes;
        if k < 0 || k >= m.count {
            // A storage class of one pointee type: what the storage of its
            // parent class holds of that pointee at this call; read out of
            // in turn, what that holds; any deeper, what it leads to.
            if l.roots[x.root].class_frame == m.frame && l.roots[x.root].class_parent >= 0 {
                let cty = l.roots[x.root].class_type;
                if stored != 0 && x.exact && !x.byteview && cty >= 0 && !life_tf_holds(p, l, cty) { continue; }
                let ts_serial = if l.held_epoch == m.start_epoch { m.serial } else { 0 - 1 - m.call_serial };
                var held = life_typed_set(p, l, m.classes, m.base, m.sets, ts_serial, x.root); fresh = false;
                if !x.exact && x.from == x.root { held = life_referable(p, l, life_held(p, l, held), cty); }
                else if !x.exact { held = life_deep(p, l, held, cty); }
                var want: i64 = -1; if x.exact || stored != 0 && !x.byteview { want = x.target_type as i64; }
                if stored != 0 && x.exact && !x.byteview && x.target_type < 0 && cty >= 0 { x.target_type = cty as i32; }
                life_map_onto(p, l, out, held, x, 0, !x.exact, want);
                continue;
            }
            // A root of the callee's own island (a temporary a result was
            // in) is gone with the call.
            if life_elsewhere(l, x.root) { continue; }
            if (x.from as i64) >= m.classes && (x.from as i64) < end { x.from = -1; }
            x.next = -1; x.bound = 0; life_build_add_alt(l, out, x); continue;
        }
        let bound: i64 = 0;
        var read = !x.exact && x.from == x.root;
        var root: i64 = -1; var source = 0;
        if k < m.base { root = l.map_roots[m.sets + k]; source = l.map_sets[m.sets + k]; }
        else { source = life_class_set(p, l, m.base, m.sets, k); fresh = false; }
        if read { source = life_held(p, l, source); fresh = false; root = -1; }
        // Any other inexact alternative at a storage class was read deeper
        // out of it: whatever the argument's storage leads to.
        else if !x.exact && k >= m.base { source = life_class_deep(p, l, m.base, m.sets, k); read = true; fresh = false; }
        if root >= 0 {
            var component = x.component; if !x.exact { component = -1; }
            // A store's place is reached as the argument's reference reaches it.
            var target = x.target_type;
            if stored != 0 && x.exact && l.map_types[m.sets + k] >= 0 { target = l.map_types[m.sets + k] as i32; }
            life_build_add_alt(l, out, LifeAlt { root: root as i32, target_type: target, bound: bound as i32, component: component, exact: x.exact, slotread: x.slotread, byteview: x.byteview });
            continue;
        }
        // A plain reference to a large set is that set: joined whole below.
        if x.exact && x.slotread && !x.byteview && x.target_type < 0 && x.component < 0 && bound == 0 && l.sets[source].count >= LIFE_BIG {
            if whole_len < 16 { whole[whole_len] = source; whole_len += 1; continue; }
            life_build_add(l, out, source); continue;
        }
        var want: i64 = -1; if k >= m.base && (x.exact && !read || stored != 0 && !x.byteview) { want = x.target_type as i64; }
        if stored != 0 && k < m.base && x.exact && !x.byteview && x.target_type < 0 && l.roots[x.root].class_pointee >= 0 { x.target_type = l.roots[x.root].class_pointee as i32; }
        life_map_onto(p, l, out, source, x, bound, read, want, stored != 0 && k < m.base, l.map_types[m.sets + k]);
    }
    var result = life_build_end(l, out);
    for wi in 0..whole_len { result = life_join(l, whole[wi], result); }
    if stored != 0 { result = life_can_take(p, l, result); }
    result = life_fold(l, result);
    if can_cache && l.held_epoch < 2147483647 {
        if fresh {
            life_map_memo_put(l, memo, ks32, key32, result as i32, -1, l.held_epoch as i32);
        } else if l.held_epoch == m.start_epoch || key_serial < 0 {
            life_map_memo_put(l, memo, ks32, key32, result as i32, l.held_epoch as i32, l.held_epoch as i32);
        }
    }
    return result;
}
recursive fn life_map_value(p: Program&, l: Lifetimes&, value: LifeValue, m: const LifeMap&) -> LifeValue {
    var out = value;
    out.place = life_map_set(p, l, value.place, m) as i32; out.refs = life_map_set(p, l, value.refs, m) as i32; out.contents = life_map_set(p, l, value.contents, m) as i32;
    out.self_pools = life_map_set(p, l, value.self_pools, m) as i32; out.relative_roots = life_map_set(p, l, value.relative_roots, m) as i32;
    if value.tuple >= 0 {
        var items = LifeItemList {}; var item = value.tuple;
        while item >= 0 { let mv = life_map_value(p, l, l.items[item].value, m); life_append(l, items, mv); item = l.items[item].next; }
        out.tuple = items.first as i32;
    }
    return out;
}
// The argument class whose storage a class root belongs to: itself, or the
// one its storage classes hang off.
fn life_class_slot(l: Lifetimes&, root: i64) -> i64 {
    let owner = l.roots[root].class_frame; var top = root;
    while l.roots[top].class_parent >= 0 { top = l.roots[top].class_parent; }
    return (top - l.frames[owner].classes) % l.frames[owner].class_base;
}
// A stored set without what came out of the storage of the same argument
// that the one class root stored into belongs to: what that argument's
// storage holds (a storage class of it) or leads to (anything only reached
// from a class of it). Such a store moves references about within what one
// argument reaches.
fn life_unpermuted(l: Lifetimes&, places: i64, value: i64) -> i64 {
    if l.sets[places].count != 1 || value == 0 { return value; }
    let place = l.alts[l.sets[places].first].root as i64; let owner = l.roots[place].class_frame;
    if owner < 0 { return value; }
    let slot = life_class_slot(l, place);
    let first = l.sets[value].first as i64; let count = l.sets[value].count as i64;
    let start = l.scratch.len; var dropped = false;
    for i in 0..count {
        var x = l.alts[first + i];
        if x.root != 0 && l.roots[x.root].class_frame == owner && life_class_slot(l, x.root as i64) == slot &&
           !x.exact { dropped = true; continue; }
        x.next = -1; l.scratch.push(x);
    }
    var kept = value;
    if dropped { kept = life_list_set(l, start, true); }
    l.scratch.resize(start);
    return kept;
}
// The class-keyed frame of a function that is being evaluated, or -1.
fn life_class_active(l: Lifetimes&, function_node: i64, selected_result: i64) -> i64 {
    var at = l.function_frames[function_node] as i64;
    if at < 0 || l.frames[at].function_active == 0 { return -1; }
    while at >= 0 {
        if l.frames[at].classes >= 0 && l.frames[at].active && l.frames[at].selected_result == selected_result { return at; }
        at = l.frames[at].next_function;
    }
    return -1;
}
// Joins what a call passes into the classes of one record of a frame's key
// (map_sets from `sets`): each class of the record takes the whole set.
// Returns where the record ends.
fn life_set_has_nonstatic(l: Lifetimes&, set: i64) -> bool {
    var at = l.sets[set].first;
    while at >= 0 { if l.alts[at].root != 0 { return true; } at = l.alts[at].next; }
    return false;
}
fn life_remap_record(l: Lifetimes&, sets: i64, at: i64, set: i64, unkeyed: bool&) -> i64 {
    var count = l.class_keys[at]; var cursor = at + 1; if count < 0 { count = 1; }
    var mapped_any = false;
    for item in 0..count {
        let index = l.class_keys[cursor]; cursor += 5;
        if index >= 0 { mapped_any = true; let joined = life_join(l, l.map_sets[sets + index], set); l.map_sets[sets + index] = joined; }
    }
    if !mapped_any && life_set_has_nonstatic(l, set) { unkeyed = true; }
    return cursor;
}
recursive fn life_taint_unkeyed_holder(p: Program&, l: Lifetimes&, value: LifeValue, poison: i64) -> LifeValue {
    var out = value;
    if value.type_id >= 0 && !life_is_ref(p, value.type_id) && life_holds(p, value.type_id) {
        out.contents = life_join(l, out.contents, poison) as i32;
    }
    if value.tuple >= 0 {
        var items = LifeItemList {}; var item = value.tuple;
        while item >= 0 { let tv = life_taint_unkeyed_holder(p, l, l.items[item].value, poison); life_append(l, items, tv); item = l.items[item].next; }
        out.tuple = items.first as i32;
    }
    return out;
}
// A call to a function whose class-keyed frame is being evaluated comes back
// to that frame whatever it passes (upstream: a back edge reuses the spec in
// progress whatever its roots), so one frame of a function is open at a
// time. Where the call's key is not the frame's, its classes are read by
// position: a class a parameter names is whatever the call passes for that
// parameter. The frame's assumptions are then checked against that reading.
fn life_class_remap(p: Program&, l: Lifetimes&, target: i64, arguments: i64, destination: i64, receiver_sensitive: bool) -> bool {
    let sets = l.map_sets.len; let count = l.frames[target].class_base; let key = l.frames[target].key;
    let function_node = l.frames[target].function_node;
    for k in 0..count { l.map_sets.push(0); l.map_roots.push(-1); l.map_types.push(-1); }
    var unkeyed = false;
    var cursor = key + 2; var input = arguments; var formal = p.nodes[function_node].first;
    while formal >= 0 {
        var value = LifeValue {};
        if input >= 0 { value = life_coerce(p, l, l.items[input].value, p.nodes[formal].type_id); input = l.items[input].next; }
        let kind = l.class_keys[cursor]; cursor += 1;
        let arg_set = life_fold(l, life_value_roots(p, value));
        if kind != 0 { cursor = life_remap_record(l, sets, cursor, arg_set, unkeyed); }
        else if life_set_has_nonstatic(l, arg_set) { unkeyed = true; }
        formal = p.nodes[formal].next;
    }
    var dummy = false;
    if receiver_sensitive { let kind = l.class_keys[cursor]; cursor += 1; if kind != 0 { cursor = life_remap_record(l, sets, cursor, destination, dummy); } }
    else { l.map_sets[sets + count - 1] = destination; l.map_types[sets + count - 1] = life_dest_reached(l, destination); }
    for item in 0..4 * count { l.map_sets.push(-1); l.map_roots.push(-1); l.map_types.push(-1); }
    return unkeyed;
}
recursive fn life_value_same(l: Lifetimes&, a: LifeValue, b: LifeValue) -> bool {
    if a.type_id != b.type_id || a.place != b.place || a.refs != b.refs || a.contents != b.contents ||
       a.self_pools != b.self_pools || a.relative_roots != b.relative_roots ||
       a.element_array != b.element_array || a.reached != b.reached || a.readonly != b.readonly { return false; }
    if a.tuple == b.tuple { return true; }
    var ia = a.tuple as i64; var ib = b.tuple as i64;
    while ia >= 0 && ib >= 0 {
        if !life_value_same(l, l.items[ia].value, l.items[ib].value) { return false; }
        ia = l.items[ia].next as i64; ib = l.items[ib].next as i64;
    }
    return ia < 0 && ib < 0;
}
inline fn life_cls_global_ok(l: Lifetimes&, dep_ge: i64) -> bool {
    if dep_ge == l.global_epoch { return true; }
    return l.settled_global_epoch >= 0 && dep_ge == l.settled_global_epoch &&
        l.global_refs_epoch == l.settled_global_refs && l.global_live_count == l.settled_global_live;
}
fn life_class_frame_is_clean(l: Lifetimes&, frame: i64) -> bool {
    if l.frames[frame].dep_in_rec { return false; }
    if l.frames[frame].dep_clean_pass == l.pass { return true; }
    if l.frames[frame].dep_dirty_pass == l.pass { return false; }
    l.clean_gen += 1;
    let gen = l.clean_gen;
    l.clean_work.clear();
    l.clean_work.push(frame);
    while l.dep_callee_mark.len <= frame { l.dep_callee_mark.push(0); }
    l.dep_callee_mark[frame] = gen;
    var at = 0; var ok = true;
    while at < l.clean_work.len {
        let cur = l.clean_work[at]; at += 1;
        let f: const LifeFrame& = l.frames[cur];
        if !f.dep_in_rec && f.dep_clean_pass == l.pass { continue; }
        let rec_bit: i64 = if f.recursive_call { 1 } else { 0 };
        if f.dep_dirty_pass == l.pass || !f.dep_valid || f.active ||
           !life_cls_global_ok(l, f.dep_global_epoch) ||
           f.dep_rec_epoch != rec_bit || f.dep_stored_ver != f.stored_version {
            ok = false; break;
        }
        let stamp = f.dep_contents_stamp;
        let r_end = f.dep_roots_first + f.dep_roots_count;
        for i in f.dep_roots_first..r_end {
            let root = l.dep_roots[i];
            if root < l.root_stamps.len && l.root_stamps[root] > stamp { ok = false; break; }
        }
        if !ok { break; }
        let c_end = f.dep_callees_first + f.dep_callees_count;
        for i in f.dep_callees_first..c_end {
            let callee = l.dep_callees[i];
            if l.frames[callee].dep_change_stamp != l.dep_callee_stamps[i] { ok = false; break; }
            while l.dep_callee_mark.len <= callee { l.dep_callee_mark.push(0); }
            if l.dep_callee_mark[callee] != gen {
                l.dep_callee_mark[callee] = gen;
                l.clean_work.push(callee);
            }
        }
        if !ok { break; }
    }
    if ok {
        for cur in l.clean_work {
            if !l.frames[cur].dep_in_rec { l.frames[cur].dep_clean_pass = l.pass; }
        }
        return true;
    }
    l.frames[frame].dep_dirty_pass = l.pass;
    return false;
}
// One evaluation of a class-keyed frame's body, as an island.
recursive fn life_class_eval(p: Program&, l: Lifetimes&, target: i64, sets: i64) {
    let function_node = l.frames[target].function_node;
    let previous_frame = l.frame; let previous_scope = l.scope; let previous_island = l.island;
    let hold_floor = l.hold_floor; let future_floor = l.future_floor; let conditional = l.conditional;
    let defer_floor = l.defer_floor; let defers_len = l.defers.len; let defer_targets_len = l.defer_targets.len;
    let saved_pending_defers = l.pending_defers; let saved_defer_base = l.frames[target].defer_base;
    let build_holds = l.build_holds; let construct_holds = l.construct_holds; let format_holds = l.format_holds;
    let saved_omit_cr = l.omit_construct_reads;
    let reading_place = l.reading_place; let sequence_path = l.sequence_path;
    let map_base = l.frames[target].map_base;
    let track_cls = l.discovery;
    let was_discovered = l.frames[target].discovered;
    let saved_cls_tainted = l.cls_dep_tainted;
    let saved_min_back = l.cls_min_back;
    let saved_child_rev = l.cls_child_rev;
    let saved_r_floor = l.dep_root_floor;
    let r_start = l.dep_root_stack.len;
    let c_start = l.dep_callee_stack.len;
    let rev0 = l.revision;
    let sum0 = l.frames[target].summary_version;
    let stored0 = l.frames[target].stored_version;
    let assumes0 = l.frames[target].assume_count;
    let cs0 = l.frames[target].class_stored;
    let res0 = l.frames[target].result;
    let glob0 = l.global_epoch;
    let stamp0 = l.contents_stamp;
    let rec0: i64 = if l.frames[target].recursive_call { 1 } else { 0 };
    let fail0 = l.failures.len;
    if track_cls { l.cls_dep_tainted = false; l.cls_min_back = 9223372036854775807; l.cls_child_rev = 0; l.dep_root_floor = r_start; }
    l.frames[target].parent = previous_frame; l.frames[target].destination = l.frames[target].class_destination;
    l.frames[target].chain = l.frames[previous_frame].chain + 1; l.frames[target].chain_epoch = -1;
    l.activations += 1; l.frames[target].activation = l.activations; l.frames[target].map_base = sets; l.frames[target].context = -1;
    l.classify_serial += 1; l.frames[target].map_serial = l.classify_serial;
    l.frame = target; l.scope = p.nodes[function_node].scope; l.island = target;
    if !l.discovery { l.holder_grow_epoch += 1; }
    l.hold_floor = l.hold_count; l.future_floor = l.future_count; l.conditional = 0; l.reading_place = 0; l.sequence_path = -1;
    l.defer_floor = l.defers.len; l.pending_defers = 0; l.frames[target].defer_base = l.defers.len as i32;
    l.build_holds = 0; l.construct_holds = 0; l.format_holds = 0;
    if l.nodes_prepared { l.omit_construct_reads = !l.full_reads && (l.hold_flags[function_node] & FH_CONSTRUCT_READ) == 0; }
    let classes = l.frames[target].classes; let class_count = l.frames[target].class_count;
    if !l.discovery {
        let base = l.frames[target].class_base;
        for root in classes..classes + class_count {
            let ty = l.roots[root].class_pointee;
            let incoming = l.frames[target].slice_slots && root < classes + base && ty >= 0 && p.types[ty].kind == TY_SLICE;
            let contents = if incoming { life_root_set(l, root + base) } else { l.roots[root].contents };
            life_set_live_contents(l, root, contents);
        }
        l.frames[target].live_result = LIFE_EMPTY_VALUE;
        var typed = l.frames[target].typed_first;
        while typed >= 0 { life_set_live_contents(l, typed, l.roots[typed].contents); typed = l.roots[typed].class_next; }
    }
    var formal = p.nodes[function_node].first; var item = l.frames[target].inputs;
    while formal >= 0 {
        let symbol = p.nodes[formal].symbol;
        if !(l.nodes_prepared && symbol >= 0 && symbol < l.sym_flags.len && (l.sym_flags[symbol] & SF_SCALAR_LOCAL) != 0) {
            let cell = life_cell(p, l, symbol);
            if cell >= 0 {
                let value = life_item(l, item, 0);
                l.cells[cell].initialized = true;
                life_set_live(l, cell, true);
                let roots = life_parameter_roots(p, l, life_value_roots(p, value), p.nodes[formal].type_id, function_node, life_reach(l, target));
                if life_is_ref(p, p.nodes[formal].type_id) {
                    let next = life_join(l, l.cells[cell].refs, roots);
                    if !life_equal(l, next, l.cells[cell].refs) { life_set_refs(l, cell, next); l.revision += 1; }
                    if !l.discovery { life_set_live_refs(l, cell, roots); }
                }
                life_add_contents(p, l, l.cells[cell].root, roots);
            }
        }
        if item >= 0 { item = l.items[item].next; }
        formal = p.nodes[formal].next;
    }
    let body_rev0 = l.revision;
    let body_first_cell = l.frames[target].first_cell;
    let body_typed0 = l.frames[target].typed_first;
    l.frames[target].active = true; l.frames[l.function_frames[function_node] as i64].function_active += 1; let temporary_base = l.temp_count;
    life_eval(p, l, p.nodes[function_node].right, l.frames[target].class_destination, l.frames[target].selected_result);
    l.temp_count = temporary_base; l.frames[target].active = false; l.frames[l.function_frames[function_node] as i64].function_active -= 1;
    l.frames[target].checked_revision = l.pass;
    if l.discovery { l.frames[target].discovered = true; } else { l.frames[target].validated = true; l.frames[target].validated_global_epoch = l.global_live_epoch; life_compact_effects(l, target); }
    if track_cls {
        let my_chain = l.frames[target].chain;
        let child_min_back = l.cls_min_back;
        let child_tainted = l.cls_dep_tainted;
        let total_rev = l.revision - rev0;
        let own_rev = total_rev - l.cls_child_rev;
        let body_own_rev = (l.revision - body_rev0) - l.cls_child_rev;
        l.cls_child_rev = saved_child_rev + total_rev;
        let rec1: i64 = if l.frames[target].recursive_call { 1 } else { 0 };
        let res1 = l.frames[target].result;
        let meta_no_res = l.frames[target].summary_version != sum0 ||
            l.frames[target].stored_version != stored0 || l.frames[target].assume_count != assumes0 ||
            l.frames[target].class_stored != cs0 ||
            l.global_epoch != glob0 || rec1 != rec0 || l.failures.len != fail0;
        let own_changed = own_rev != 0 || meta_no_res || !life_value_same(l, res0, res1);
        if own_changed {
            l.frames[target].dep_change_stamp += 1;
        }
        var callee_mid_changed = false;
        for i in c_start..l.dep_callee_stack.len {
            let cs_val = l.dep_callee_stamp_stack[i];
            if cs_val >= 0 && l.frames[l.dep_callee_stack[i]].dep_change_stamp != cs_val {
                callee_mid_changed = true; break;
            }
        }
        let res_empty = res1.place == 0 && res1.refs == 0 && res1.contents == 0 &&
            res1.self_pools == 0 && res1.relative_roots == 0 && res1.tuple < 0 &&
            res1.element_array == -1 && res1.reached == -1 && !res1.readonly;
        let can_cert_p1 = !was_discovered && body_own_rev == 0 && !meta_no_res && rec1 == 0 && res_empty &&
            l.frames[target].first_cell == body_first_cell && l.frames[target].typed_first == body_typed0 &&
            l.frames[target].first_exit < 0;
        if ((!own_changed && was_discovered) || can_cert_p1) && !child_tainted && !callee_mid_changed {
            l.dep_gen += 1;
            var r_first = l.dep_roots.len;
            for i in r_start..l.dep_root_stack.len {
                let r = l.dep_root_stack[i];
                if l.dep_root_mark.len <= r { l.dep_root_mark.resize(r + 1, 0); }
                if l.dep_root_mark[r] != l.dep_gen { l.dep_root_mark[r] = l.dep_gen; l.dep_roots.push(r); }
            }
            let r_count = l.dep_roots.len - r_first;
            if r_count > 0 && r_count <= l.frames[target].dep_roots_count {
                let old_first = l.frames[target].dep_roots_first;
                for i in 0..r_count { l.dep_roots[old_first + i] = l.dep_roots[r_first + i]; }
                l.dep_roots.resize(r_first); r_first = old_first;
            }
            var c_first = l.dep_callees.len;
            for i in c_start..l.dep_callee_stack.len {
                let c = l.dep_callee_stack[i];
                if l.dep_callee_mark.len <= c { l.dep_callee_mark.resize(c + 1, 0); }
                if l.dep_callee_mark[c] != l.dep_gen {
                    l.dep_callee_mark[c] = l.dep_gen;
                    l.dep_callees.push(c);
                    l.dep_callee_stamps.push(l.frames[c].dep_change_stamp);
                }
            }
            let c_count = l.dep_callees.len - c_first;
            if c_count > 0 && c_count <= l.frames[target].dep_callees_count {
                let old_first = l.frames[target].dep_callees_first;
                for i in 0..c_count {
                    l.dep_callees[old_first + i] = l.dep_callees[c_first + i];
                    l.dep_callee_stamps[old_first + i] = l.dep_callee_stamps[c_first + i];
                }
                l.dep_callees.resize(c_first); l.dep_callee_stamps.resize(c_first); c_first = old_first;
            }
            l.frames[target].dep_valid = true;
            l.frames[target].dep_in_rec = child_min_back < my_chain;
            l.frames[target].dep_roots_first = r_first;
            l.frames[target].dep_roots_count = r_count;
            l.frames[target].dep_callees_first = c_first;
            l.frames[target].dep_callees_count = c_count;
            l.frames[target].dep_contents_stamp = stamp0;
            l.frames[target].dep_global_epoch = glob0;
            l.frames[target].dep_rec_epoch = rec0;
            l.frames[target].dep_stored_ver = stored0;
            l.frames[target].dep_clean_pass = -1;
            l.frames[target].dep_dirty_pass = -1;
        } else {
            l.frames[target].dep_valid = false;
            l.frames[target].dep_clean_pass = -1;
        }
        l.dep_root_stack.resize(r_start);
        l.dep_callee_stack.resize(c_start);
        l.dep_callee_stamp_stack.resize(c_start);
        l.dep_root_floor = saved_r_floor;
        l.cls_dep_tainted = saved_cls_tainted || child_tainted;
        if child_min_back < saved_min_back { l.cls_min_back = child_min_back; } else { l.cls_min_back = saved_min_back; }
    }
    var ci = l.frames[target].first_cell;
    while ci >= 0 { life_set_live(l, ci, false); ci = l.cells[ci].next_frame; }
    l.frames[target].map_base = map_base;
    l.frame = previous_frame; l.scope = previous_scope; l.island = previous_island;
    if !l.discovery { l.holder_grow_epoch += 1; }
    l.hold_floor = hold_floor; l.future_floor = future_floor; l.conditional = conditional; l.reading_place = reading_place; l.sequence_path = sequence_path;
    l.defers.resize(defers_len); l.defer_targets.resize(defer_targets_len);
    l.defer_floor = defer_floor; l.pending_defers = saved_pending_defers; l.frames[target].defer_base = saved_defer_base;
    l.build_holds = build_holds; l.construct_holds = construct_holds; l.format_holds = format_holds;
    l.omit_construct_reads = saved_omit_cr;
}
fn life_set_is_shallow_for(l: Lifetimes&, frame: i64, set: i64) -> bool {
    if set == 0 { return true; }
    let base = l.frames[frame].class_base;
    let first = l.sets[set].first as i64; let count = l.sets[set].count as i64;
    for i in 0..count {
        let a: const LifeAlt& = l.alts[first + i];
        let r: const LifeRoot& = l.roots[a.root];
        if r.class_frame == frame {
            if !a.exact || r.class_parent >= 0 || r.class_index >= base { return false; }
        }
    }
    return true;
}
fn life_compact_effects(l: Lifetimes&, frame: i64) {
    var prev: i64 = -1; var e = l.frames[frame].first_effect;
    var stores_only = true;
    var stores_shallow = l.frames[frame].classes >= 0;
    while e >= 0 {
        let nxt = l.effects[e].next as i64;
        let k = l.effects[e].kind;
        if k == 0 {
            if prev >= 0 { l.effects[prev].next = nxt as i32; } else { l.frames[frame].first_effect = nxt; }
        } else {
            if k != 4 && k != 5 { stores_only = false; stores_shallow = false; }
            else if stores_shallow {
                if k != 4 || l.effects[e].field < -1 ||
                   !life_set_is_shallow_for(l, frame, l.effects[e].places as i64) ||
                   !life_set_is_shallow_for(l, frame, l.effects[e].value.contents as i64) {
                    stores_shallow = false;
                }
            }
            prev = e;
        }
        e = nxt;
    }
    l.frames[frame].last_effect = prev;
    l.frames[frame].val_stores_only = stores_only;
    l.frames[frame].val_stores_shallow = stores_shallow;
}
fn life_reset_validation(frame: LifeFrame&) {
    frame.validated = false; frame.first_effect = -1; frame.last_effect = -1; frame.effect_epoch += 1;
    frame.last_shrink_barrier = -1; frame.last_shrink = -1; frame.last_store = -1; frame.last_kill = -1;
    frame.val_stores_only = false; frame.val_stores_shallow = false;
}
inline fn life_append_capture(p: Program&, l: Lifetimes&, items: LifeItemList&, cell: i64) {
    let c: const LifeCell& = l.cells[cell];
    let cv = LifeValue { type_id: p.symbols[c.symbol].type_id as i32, refs: c.live_refs as i32, contents: l.roots[c.root].live_contents as i32 };
    life_append(l, items, cv);
}
// Check whether a frame's recorded global capture inputs still match without
// allocating a fresh LifeItem list when they match.
fn life_global_captures_match(p: Program&, l: Lifetimes&, recorded: i64, span: LifeCaptureSpan) -> bool {
    var x = recorded; var at = span.first + span.count;
    while at > span.first {
        if x < 0 { return false; }
        at -= 1;
        let cell: const LifeCell& = l.cells[l.global_read_list[at]];
        let av: const LifeValue& = l.items[x].value;
        if life_is_ref(p, av.type_id) && !life_equal(l, av.refs, cell.live_refs) { return false; }
        if !life_is_ref(p, av.type_id) && life_tf_holds(p, l, av.type_id) && !life_equal(l, av.contents, l.roots[cell.root].live_contents) { return false; }
        x = l.items[x].next;
    }
    return x < 0;
}
fn life_capture_span_snapshot(p: Program&, l: Lifetimes&, span: LifeCaptureSpan) -> i64 {
    var items = LifeItemList {};
    var at = span.first + span.count;
    while at > span.first { at -= 1; life_append_capture(p, l, items, l.global_read_list[at]); }
    return items.first;
}
// Snapshot reference-bearing globals and captures in their lexical order.
fn life_capture_inputs(p: Program&, l: Lifetimes&, function_node: i64, lexical: i64) -> i64 {
    var items = LifeItemList {}; var enclosing = lexical;
    while enclosing > 0 {
        var ci = l.frames[enclosing].first_capture_input;
        while ci >= 0 {
            let cell: const LifeCell& = l.cells[ci]; let symbol: const Symbol& = p.symbols[cell.symbol];
            if (symbol.flags & S_CAPTURE) != 0 && (life_is_ref(p, symbol.type_id) || life_tf_holds(p, l, symbol.type_id)) &&
               life_reads(p, l, p.nodes[function_node].right, cell.symbol) {
                life_append_capture(p, l, items, ci);
            }
            ci = cell.next_capture_input;
        }
        enclosing = l.frames[enclosing].lexical;
    }
    if enclosing == 0 {
        let span = life_global_capture_span(p, l, function_node);
        // Frame capture lists are newest first. Cell IDs increase in creation order.
        var at = span.first + span.count;
        while at > span.first { at -= 1; life_append_capture(p, l, items, l.global_read_list[at]); }
    }
    return items.first;
}
// Interns a class-keyed call's mapping signature (callee, caller island,
// argument sets/roots/types, active state) so identical repeated calls share
// map_memo, class-check answers, and discovery replay state.
fn life_call_sig(l: Lifetimes&, target: i64, sets: i64, active: bool) -> i64 {
    let base = l.frames[target].class_base;
    let island = l.island;
    var h: u64 = (target as! u64) * 11400714819323198485 ^ (island as! u64) * 14029467366897019727 ^ (base as! u64) * 1609587929392839161;
    if active { h ^= 0x9e3779b97f4a7c15; }
    for k in 0..base {
        let s = l.map_sets[sets + k]; let r = l.map_roots[sets + k]; let t = l.map_types[sets + k];
        let mix = (s as! u64) * 11400714819323198485 ^ ((r + 1) as! u64) * 14029467366897019727 ^ ((t + 1) as! u64) * 9650029242287828579;
        h = (h ^ mix) * 1099511628211; h ^= h >> 29;
    }
    let hash = (h >> 1) as! i64;
    if 2 * (l.call_sigs.len + 1) > l.call_sig_heads.len {
        var size: i64 = 1024; while size <= 2 * (l.call_sigs.len + 1) { size <<= 1; }
        l.call_sig_heads.clear(); l.call_sig_heads.resize(size, -1);
        for idx in 0..l.call_sigs.len {
            let bucket = l.call_sigs[idx].hash & (size - 1);
            l.call_sigs[idx].next = l.call_sig_heads[bucket];
            l.call_sig_heads[bucket] = idx as i32;
        }
    }
    let bucket = hash & (l.call_sig_heads.len - 1);
    var at = l.call_sig_heads[bucket] as i64;
    while at >= 0 {
        let e: const LifeCallSig& = l.call_sigs[at];
        if e.hash == hash && (e.frame as i64) == target && (e.island as i64) == island && (e.base as i64) == base && e.active == active {
            var same = true; let st = e.start as i64;
            for k in 0..base {
                let off = st + 3 * k;
                if (l.call_sig_data[off] as i64) != l.map_sets[sets + k] ||
                   (l.call_sig_data[off + 1] as i64) != l.map_roots[sets + k] ||
                   (l.call_sig_data[off + 2] as i64) != l.map_types[sets + k] { same = false; break; }
            }
            if same { return at; }
        }
        at = e.next as i64;
    }
    let start = l.call_sig_data.len;
    for k in 0..base {
        l.call_sig_data.push(l.map_sets[sets + k] as i32);
        l.call_sig_data.push(l.map_roots[sets + k] as i32);
        l.call_sig_data.push(l.map_types[sets + k] as i32);
    }
    let id = l.call_sigs.len;
    l.call_sigs.push(LifeCallSig { hash: hash, frame: target as i32, island: island as i32, base: base as i32, start: start as i32, active: active, next: l.call_sig_heads[bucket] });
    l.call_sig_heads[bucket] = id as i32;
    return id;
}
// A call of a top-level function by the classes of its arguments.
recursive fn life_class_call(p: Program&, l: Lifetimes&, function_node: i64, call: i64, arguments: i64, destination: i64, selected_result: i64, receiver_sensitive: bool) -> LifeValue {
    let c = life_classify(p, l, function_node, arguments, destination, receiver_sensitive, selected_result);
    var target = life_class_frame(l, c); var depth_count = c.depth_count; var unkeyed_back = false;
    if target < 0 || !l.frames[target].active {
        let open = life_class_active(l, function_node, selected_result);
        if open >= 0 {
            target = open; depth_count = 0;
            l.map_sets.resize(c.sets); l.map_roots.resize(c.sets); l.map_types.resize(c.sets); l.map_depths.resize(c.depths);
            unkeyed_back = life_class_remap(p, l, target, arguments, destination, receiver_sensitive);
        }
    }
    var was_new = false;
    if target < 0 { target = life_class_new(p, l, function_node, call, selected_result, receiver_sensitive, c); was_new = true; }
    let back_edge = l.frames[target].active;
    let sig = life_call_sig(l, target, c.sets, back_edge);
    if !was_new && l.frames[target].assumptions >= 0 {
        let island_act: i64 = if l.island > 0 { l.frames[l.island].activation } else { 0 };
        let island_stored: i64 = if l.island > 0 { l.frames[l.island].stored_version } else { 0 };
        let tf: const LifeFrame& = l.frames[target];
        let cs: const LifeCallSig& = l.call_sigs[sig];
        let need_dep_roots = tf.has_gs_assume || tf.has_deep_assume;
        var base_hit = cs.checked_assumes >= 0 &&
                       (cs.checked_island_act == -2 || cs.checked_island_act == island_act) &&
                       cs.checked_island_stored == island_stored &&
                       (cs.checked_discovery == l.discovery || (!need_dep_roots && cs.checked_island_act == -2));
        if base_hit {
            if cs.checked_roots_count < 0 {
                base_hit = cs.checked_epoch == l.held_epoch;
            } else if need_dep_roots && cs.checked_epoch != l.held_epoch {
                let stamp = cs.checked_stamp;
                let rf = cs.checked_roots_first as i64;
                let re = rf + (cs.checked_roots_count as i64);
                if l.discovery {
                    for ri in rf..re {
                        let r = l.chk_dep_roots[ri] as i64;
                        if r < l.root_stamps.len && l.root_stamps[r] > stamp { base_hit = false; break; }
                    }
                } else {
                    for ri in rf..re {
                        let r = l.chk_dep_roots[ri] as i64;
                        if r < l.root_live_stamps.len && l.root_live_stamps[r] > stamp { base_hit = false; break; }
                    }
                }
            }
        }
        let hit = base_hit && cs.checked_assumes == tf.noncautious_ver;
        if base_hit && l.discovery && l.frame > 0 && cs.checked_roots_count > 0 {
            let rf = cs.checked_roots_first as i64;
            let re = rf + (cs.checked_roots_count as i64);
            for ri in rf..re {
                let r = l.chk_dep_roots[ri] as i64;
                if l.island == 0 || l.roots[r].frame <= 0 && l.roots[r].class_frame < 0 { life_push_dep_root(l, r); }
            }
        }
        if !hit {
            let incremental = base_hit && cs.checked_assumes < tf.noncautious_ver;
            let min_ver: i32 = if incremental { cs.checked_assumes } else { 0 };
            let prev_act = cs.checked_island_act;
            let prev_rf = cs.checked_roots_first as i64;
            let prev_rc = cs.checked_roots_count as i64;
            let before_epoch = l.held_epoch;
            let stamp0: i64 = if l.discovery { l.contents_stamp } else { l.live_contents_stamp };
            let record_roots = l.frames[target].has_gs_assume || l.frames[target].has_deep_assume;
            let saved_rec = l.chk_dep_recording;
            let chk_start = l.chk_dep_stack.len;
            if record_roots { l.chk_dep_recording = true; }
            l.chk_saw_unsealed = false; l.chk_dep_overflow = false;
            life_class_check(p, l, target, c.sets, min_ver);
            l.chk_dep_recording = saved_rec;
            if l.held_epoch == before_epoch {
                l.call_sigs[sig].checked_assumes = l.frames[target].noncautious_ver;
                l.call_sigs[sig].checked_epoch = l.held_epoch;
                l.call_sigs[sig].checked_stamp = stamp0;
                let act_indep = !back_edge && !l.chk_saw_unsealed && (!incremental || prev_act == -2);
                l.call_sigs[sig].checked_island_act = if act_indep { -2 } else { island_act };
                l.call_sigs[sig].checked_island_stored = island_stored;
                l.call_sigs[sig].checked_discovery = l.discovery;
                if l.chk_dep_overflow || (incremental && prev_rc < 0) {
                    l.call_sigs[sig].checked_roots_first = 0;
                    l.call_sigs[sig].checked_roots_count = -1;
                } else if record_roots {
                    l.dep_gen += 1;
                    let gen = l.dep_gen;
                    let r_first0 = l.chk_dep_roots.len;
                    var overflow = false;
                    if incremental && prev_rc > 0 {
                        for ri in prev_rf..prev_rf + prev_rc {
                            let r = l.chk_dep_roots[ri] as i64;
                            if l.dep_root_mark.len <= r { l.dep_root_mark.resize(r + 1, 0); }
                            if l.dep_root_mark[r] != gen {
                                l.dep_root_mark[r] = gen;
                                l.chk_dep_roots.push(r as i32);
                            }
                        }
                    }
                    for ci in chk_start..l.chk_dep_stack.len {
                        let r = l.chk_dep_stack[ci] as i64;
                        if l.dep_root_mark.len <= r { l.dep_root_mark.resize(r + 1, 0); }
                        if l.dep_root_mark[r] != gen {
                            l.dep_root_mark[r] = gen;
                            if l.chk_dep_roots.len - r_first0 >= 64 { overflow = true; break; }
                            l.chk_dep_roots.push(r as i32);
                        }
                    }
                    if overflow {
                        l.chk_dep_roots.resize(r_first0);
                        l.call_sigs[sig].checked_roots_first = 0;
                        l.call_sigs[sig].checked_roots_count = -1;
                    } else {
                        let r_count = l.chk_dep_roots.len - r_first0;
                        var rf = r_first0;
                        if r_count > 0 && prev_rc > 0 && r_count <= prev_rc {
                            for ri in 0..r_count { l.chk_dep_roots[prev_rf + ri] = l.chk_dep_roots[r_first0 + ri]; }
                            l.chk_dep_roots.resize(r_first0);
                            rf = prev_rf;
                        }
                        l.call_sigs[sig].checked_roots_first = rf as i32;
                        l.call_sigs[sig].checked_roots_count = r_count as i32;
                    }
                } else {
                    l.call_sigs[sig].checked_roots_first = 0;
                    l.call_sigs[sig].checked_roots_count = 0;
                }
            }
            l.chk_dep_stack.resize(chk_start);
        }
    }
    life_cycle_call(p, l, target, call, destination);
    if l.discovery && l.island > 0 && back_edge {
        let ch = l.frames[target].chain;
        if ch < l.cls_min_back { l.cls_min_back = ch; }
    }
    var evaluate = !back_edge;
    if evaluate && l.discovery && l.frames[target].checked_revision == l.pass { evaluate = false; }
    if evaluate && l.discovery && l.frames[target].dep_valid && life_class_frame_is_clean(l, target) {
        l.frames[target].checked_revision = l.pass;
        evaluate = false;
    }
    if evaluate && !l.discovery {
        // As for any frame: checked again only when a global it reads holds
        // other references than when it was last checked.
        if l.frames[target].validated && l.frames[target].validated_global_epoch == l.global_live_epoch {
            evaluate = false;
        } else if l.frames[0].first_capture_input < 0 {
            if l.frames[target].validated && l.frames[target].capture_inputs < 0 {
                l.frames[target].validated_global_epoch = l.global_live_epoch; evaluate = false;
            } else { l.frames[target].capture_inputs = -1; life_reset_validation(l.frames[target]); }
        } else if !l.frames[target].validated {
            let span = life_global_capture_span(p, l, function_node);
            if span.count == 0 { l.frames[target].capture_inputs = -1; }
            else { l.frames[target].capture_inputs = life_capture_span_snapshot(p, l, span); }
            life_reset_validation(l.frames[target]);
        } else {
            let span = life_global_capture_span(p, l, function_node);
            if span.count == 0 || l.frames[target].capture_inputs != -2 && life_global_captures_match(p, l, l.frames[target].capture_inputs, span) {
                if span.count == 0 { l.frames[target].capture_inputs = -1; }
                l.frames[target].validated_global_epoch = l.global_live_epoch; evaluate = false;
            } else {
                let snap = life_capture_span_snapshot(p, l, span);
                l.frames[target].capture_inputs = snap;
                life_reset_validation(l.frames[target]);
            }
        }
    }
    if evaluate && !l.discovery && !l.frames[target].discovered {
        // A key first met while validating: its body is settled here, as the
        // discovery passes would have settled it.
        let failures = l.failures.len; l.discovery = true; l.held_epoch += 1;
        loop {
            l.pass += 1; let before = l.revision;
            life_class_eval(p, l, target, c.sets);
            if l.revision == before { break; }
        }
        l.discovery = false; l.held_epoch += 1;
        for index in failures..l.failures.len { life_error(p, l, l.failures[index].node, life_failure_message(l.failures[index].kind)); }
        l.failures.resize(failures);
    }
    if evaluate { life_class_eval(p, l, target, c.sets); }
    if l.discovery && (l.island > 0 || l.frame > 0) {
        l.dep_callee_stack.push(target);
        l.dep_callee_stamp_stack.push(l.frames[target].dep_change_stamp);
    }
    let m = LifeMap { classes: l.frames[target].classes, count: l.frames[target].class_count, base: l.frames[target].class_base, sets: c.sets, depths: c.depths, depth_count: depth_count, serial: sig, frame: target, start_epoch: l.held_epoch, call_serial: c.serial };
    // Resolve a view of the incoming slice slot before any replayed store
    // can join another view into it.
    let entry_result = !l.discovery && !back_edge && l.frames[target].slice_slots && !l.frames[target].recursive_call;
    var result = LIFE_EMPTY_VALUE;
    if entry_result { result = life_map_value(p, l, l.frames[target].live_result, m); }
    let has_replay = if l.discovery || back_edge { l.frames[target].first_summary >= 0 || l.frames[target].first_read >= 0 } else { l.frames[target].first_effect >= 0 };
    if has_replay {
        let in_own_island = l.island > 0 && l.frame == l.island;
        let can_skip_replay = l.discovery && l.activations < 1073741824 && (in_own_island || !back_edge && life_nearest_recursive(l, l.frame) == 0);
        let can_skip_val = !l.discovery && !back_edge && l.frames[target].val_stores_only && l.activations < 1073741824;
        let shallow_val = can_skip_val && l.frames[target].val_stores_shallow;
        let rp = l.reading_place > 0;
        let caller_act = l.frames[l.frame].activation as i32;
        let replay_clk: i64 = if in_own_island { l.frames[l.frame].parameter_version } else { l.cell_clock };
        let skip_disc = can_skip_replay &&
             l.call_sigs[sig].replayed_caller == (l.frame as i32) &&
             l.call_sigs[sig].replayed_act == caller_act &&
             l.call_sigs[sig].replayed_sum_ver == l.frames[target].summary_version &&
             l.call_sigs[sig].replayed_epoch == l.held_epoch &&
             l.call_sigs[sig].replayed_glob == l.global_epoch &&
             l.call_sigs[sig].replayed_cells == replay_clk &&
             l.call_sigs[sig].replayed_rec == (l.recursion_epoch as i32) &&
             l.call_sigs[sig].replayed_rp == rp;
        let skip_val = can_skip_val &&
             l.call_sigs[sig].val_caller == (l.frame as i32) &&
             l.call_sigs[sig].val_act == caller_act &&
             l.call_sigs[sig].val_target_ep == (l.frames[target].effect_epoch as i32) &&
             l.call_sigs[sig].val_kill_ep == l.val_kill_epoch &&
             (shallow_val || l.call_sigs[sig].val_held_ep == l.held_epoch && l.call_sigs[sig].val_live_ep == l.live_epoch);
        if !skip_disc && !skip_val {
            let e0 = l.held_epoch; let g0 = l.global_epoch; let c0 = replay_clk;
            let sv0 = l.frames[target].summary_version;
            let le0 = l.live_epoch; let gle0 = l.global_live_epoch; let ke0 = l.val_kill_epoch;
            let te0 = l.frames[target].effect_epoch; let diag0 = p.diagnostics.len;
            let saved_rec = l.offer_recursive; l.offer_recursive = false;
            life_replay(p, l, target, l.discovery || back_edge, m, call);
            let hit_rec = l.offer_recursive;
            if saved_rec { l.offer_recursive = true; }
            let c1: i64 = if in_own_island { l.frames[l.frame].parameter_version } else { l.cell_clock };
            if can_skip_replay && (in_own_island || !hit_rec) &&
               l.held_epoch == e0 && l.global_epoch == g0 && c1 == c0 &&
               l.failures.len == 0 && l.frames[target].summary_version == sv0 {
                l.call_sigs[sig].replayed_caller = l.frame as i32;
                l.call_sigs[sig].replayed_act = caller_act;
                l.call_sigs[sig].replayed_sum_ver = sv0;
                l.call_sigs[sig].replayed_epoch = e0;
                l.call_sigs[sig].replayed_glob = g0;
                l.call_sigs[sig].replayed_cells = c0;
                l.call_sigs[sig].replayed_rec = l.recursion_epoch as i32;
                l.call_sigs[sig].replayed_rp = rp;
            } else if shallow_val && l.val_kill_epoch == ke0 &&
               p.diagnostics.len == diag0 && l.frames[target].effect_epoch == te0 {
                l.call_sigs[sig].val_caller = l.frame as i32;
                l.call_sigs[sig].val_act = caller_act;
                l.call_sigs[sig].val_target_ep = te0 as i32;
                l.call_sigs[sig].val_held_ep = -1;
                l.call_sigs[sig].val_live_ep = -1;
                l.call_sigs[sig].val_kill_ep = ke0;
            } else if can_skip_val && l.held_epoch == e0 && l.live_epoch == le0 &&
               l.global_live_epoch == gle0 && l.val_kill_epoch == ke0 &&
               p.diagnostics.len == diag0 && l.frames[target].effect_epoch == te0 {
                l.call_sigs[sig].val_caller = l.frame as i32;
                l.call_sigs[sig].val_act = caller_act;
                l.call_sigs[sig].val_target_ep = te0 as i32;
                l.call_sigs[sig].val_held_ep = e0;
                l.call_sigs[sig].val_live_ep = le0;
                l.call_sigs[sig].val_kill_ep = ke0;
            }
        }
    }
    if !entry_result {
        let raw = l.frames[target].result;
        result = raw;
        if raw.place != 0 || raw.refs != 0 || raw.contents != 0 || raw.self_pools != 0 || raw.relative_roots != 0 || raw.tuple >= 0 {
            result = life_map_value(p, l, raw, m);
        }
    }
    if back_edge {
        result = life_cycle_value(l, result);
        if unkeyed_back {
            let temp = life_temporary(p, l, call);
            let poison = life_single(l, l.alts[l.sets[temp].first].root as i64, false, -1, false);
            result = life_taint_unkeyed_holder(p, l, result, poison);
        }
    }
    l.map_sets.resize(c.sets); l.map_roots.resize(c.sets); l.map_types.resize(c.sets); l.map_depths.resize(c.depths);
    return result;
}
fn life_frame_is_clean(l: Lifetimes&, frame: i64) -> bool {
    if l.frames[frame].dep_clean_pass == l.pass { return true; }
    if l.frames[frame].dep_dirty_pass == l.pass { return false; }
    l.clean_gen += 1;
    let gen = l.clean_gen;
    l.clean_work.clear();
    l.clean_work.push(frame);
    while l.dep_callee_mark.len <= frame { l.dep_callee_mark.push(0); }
    l.dep_callee_mark[frame] = gen;
    var at = 0; var ok = true;
    while at < l.clean_work.len {
        let cur = l.clean_work[at]; at += 1;
        let f: const LifeFrame& = l.frames[cur];
        if f.classes >= 0 {
            if !f.dep_in_rec && f.dep_clean_pass == l.pass { continue; }
            let rec_bit: i64 = if f.recursive_call { 1 } else { 0 };
            if f.dep_dirty_pass == l.pass || !f.dep_valid || f.active ||
               !life_cls_global_ok(l, f.dep_global_epoch) ||
               f.dep_rec_epoch != rec_bit || f.dep_stored_ver != f.stored_version {
                ok = false; break;
            }
        } else {
            if f.dep_clean_pass == l.pass { continue; }
            if f.dep_dirty_pass == l.pass || !f.dep_valid || f.active || f.lexical != 0 ||
               (f.quiet_pass >= 0 && (l.island > 0 || f.dep_in_rec || life_nearest_recursive(l, l.frame) > 0)) ||
               f.dep_global_epoch != l.global_epoch || f.dep_rec_epoch != l.recursion_epoch {
                ok = false; break;
            }
        }
        let stamp = f.dep_contents_stamp;
        let r_end = f.dep_roots_first + f.dep_roots_count;
        for i in f.dep_roots_first..r_end {
            let root = l.dep_roots[i];
            if root < l.root_stamps.len && l.root_stamps[root] > stamp { ok = false; break; }
        }
        if !ok { break; }
        let c_end = f.dep_callees_first + f.dep_callees_count;
        let cur_concrete = f.classes < 0;
        for i in f.dep_callees_first..c_end {
            let callee = l.dep_callees[i];
            if cur_concrete && l.frames[callee].classes >= 0 && l.frames[callee].dep_in_rec { ok = false; break; }
            if l.frames[callee].dep_change_stamp != l.dep_callee_stamps[i] { ok = false; break; }
            while l.dep_callee_mark.len <= callee { l.dep_callee_mark.push(0); }
            if l.dep_callee_mark[callee] != gen {
                l.dep_callee_mark[callee] = gen;
                l.clean_work.push(callee);
            }
        }
        if !ok { break; }
    }
    if ok {
        for cur in l.clean_work {
            if l.frames[cur].classes < 0 || !l.frames[cur].dep_in_rec { l.frames[cur].dep_clean_pass = l.pass; }
        }
        return true;
    }
    l.frames[frame].dep_dirty_pass = l.pass;
    return false;
}

recursive fn life_function(p: Program&, l: Lifetimes&, function_node: i64, call: i64, arguments: i64, destination: i64, selected_result: i64 = -1) -> LifeValue {
    if function_node < 0 || p.nodes[function_node].right < 0 { return LifeValue {}; }
    var lexical = 0;
    if p.nodes[function_node].symbol >= 0 {
        // No frame is of function node -1, the owner of a top-level function.
        let owner = p.symbols[p.nodes[function_node].symbol].owner; var frame = l.frame; if owner < 0 { frame = 0; }
        while frame > 0 { if l.frames[frame].function_node == owner { lexical = frame; break; } if frame == l.island { break; } frame = l.frames[frame].parent; }
    }
    // A body that reads no captured binding, through any call, finds none in
    // an enclosing frame either.
    var reads_captures = false;
    if l.has_captures { reads_captures = life_reads_captures(p, l, function_node); }
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
        if enclosing == l.island { break; }
        enclosing = l.frames[enclosing].parent;
    }
    var reach = 0;
    if lexical != 0 || l.deep_cells.len > 0 { reach = life_reach(l, lexical); }
    let result_type = p.types[p.nodes[function_node].type_id].element;
    // Types do not change during evaluation, so the answer is kept per type.
    var receiver_sensitive = false;
    if result_type >= 0 {
        if l.nodes_prepared && result_type < l.type_flags.len {
            receiver_sensitive = (l.type_flags[result_type] & TF_L_REL_POOL) != 0;
        } else {
            while l.relative_storage.len <= result_type { l.relative_storage.push(0); }
            if l.relative_storage[result_type] == 0 || !l.types_frozen {
                l.relative_storage[result_type] = 1; if life_relative_storage(p, result_type, true) { l.relative_storage[result_type] = 2; }
            }
            receiver_sensitive = l.relative_storage[result_type] == 2;
        }
    }
    // Only an active frame of the function is on the chain.
    let newest = l.function_frames[function_node] as i64;
    var target = -1; var active = l.frame; if newest < 0 || l.frames[newest].function_active == 0 { active = 0; }
    while active > 0 {
        if l.frames[active].classes < 0 && l.frames[active].function_node == function_node && l.frames[active].lexical == lexical && l.frames[active].selected_result == selected_result && (!receiver_sensitive || life_equal(l, l.frames[active].destination, destination)) && life_classes_equal(p, l, l.frames[active].inputs, arguments) { target = active; break; }
        // An island reaches no frame of its callers.
        if active == l.island { break; }
        active = l.frames[active].parent;
    }
    // The newest frame of the function with these arguments, lexical frame
    // and selected result, made in the island being evaluated: a frame keeps
    // what its body read, which in an island includes that island's own
    // class roots, and those mean nothing in another. Where every frame of the function has inputs of
    // the kinds these arguments have, those frames are in one bucket of
    // input_heads, newest first; otherwise each frame is tried.
    var exact_match = false;
    if target < 0 && newest >= 0 {
        let nf: const LifeFrame& = l.frames[newest];
        if nf.classes < 0 && nf.island == l.island && nf.lexical == lexical && nf.selected_result == selected_result &&
           (!receiver_sensitive || life_equal(l, nf.destination, destination)) && life_arguments_equal(p, l, nf.inputs, arguments) {
            target = newest; exact_match = true;
        }
    }
    var key = LifeInputs { hash: 0, kinds: 0 }; var mixed = false;
    if target < 0 {
        if 2 * l.frames.len >= l.input_heads.len { life_frames_reserve(l); }
        key = life_inputs_key(p, l, arguments, lexical, selected_result);
        mixed = key.kinds == 0 || newest >= 0 && (l.frames[newest].mixed_kinds || l.frames[newest].inputs_kinds != key.kinds);
        // A class-keyed frame is in no index: the scan below passes it by.
        if l.class_frames > 0 && newest >= 0 && l.frames[newest].classes >= 0 && l.frames[newest].inputs_kinds == 0 { mixed = true; }
        if !mixed {
            var index = l.input_heads[life_inputs_bucket(l, function_node, key.hash)] as i64;
            while index >= 0 {
                let frame: const LifeFrame& = l.frames[index];
                if frame.function_node == function_node && frame.inputs_hash == key.hash && frame.island == l.island && frame.lexical == lexical && frame.selected_result == selected_result && (!receiver_sensitive || life_equal(l, frame.destination, destination)) && life_arguments_equal(p, l, frame.inputs, arguments) { target = index; exact_match = true; break; }
                index = frame.next_inputs;
            }
        }
        if target < 0 && mixed {
            var index = newest;
            while index >= 0 {
                let frame: const LifeFrame& = l.frames[index];
                if frame.classes < 0 && frame.island == l.island && frame.lexical == lexical && frame.selected_result == selected_result && (!receiver_sensitive || life_equal(l, frame.destination, destination)) && life_arguments_equal(p, l, frame.inputs, arguments) { target = index; exact_match = true; break; }
                index = frame.next_function;
            }
        }
        // A discovery frame had its depth fixed when first seen. If a
        // deeper argument root has since arrived, it must get a new frame.
        if target < 0 && l.discovery {
            let incoming_depth = life_input_depth(p, l, arguments);
            var index = l.home_heads[life_home_bucket(l, function_node, l.frame, call)] as i64;
            while index >= 0 {
                let frame: const LifeFrame& = l.frames[index];
                if frame.function_node == function_node && !frame.active && frame.lexical == lexical && frame.home == l.frame && frame.call == call && frame.base > incoming_depth && frame.selected_result == selected_result && (!receiver_sensitive || life_equal(l, frame.destination, destination)) { target = index; break; }
                index = frame.next_home;
            }
        }
    }
    // Past the first LIFE_CONCRETE_FRAMES frames, a top-level function that
    // reads no captured binding is checked by the classes of its arguments.
    if target < 0 && call >= 0 && lexical == 0 && l.frames.len > LIFE_CONCRETE_FRAMES && p.nodes[function_node].captures < 0 &&
       p.nodes[function_node].symbol >= 0 && p.symbols[p.nodes[function_node].symbol].owner < 0 && (!reads_captures || life_contained(p, l, function_node)) {
        return life_class_call(p, l, function_node, call, arguments, destination, selected_result, receiver_sensitive);
    }
    if target >= 0 && l.discovery && l.island > 0 && l.frames[target].island != l.island { l.cls_dep_tainted = true; }
    if target < 0 {
        let incoming_depth = life_input_depth(p, l, arguments);
        let base = 2 + (if incoming_depth > reach { incoming_depth } else { reach });
        target = l.frames.len;
        l.frames.push(LifeFrame { function_node: function_node, parent: l.frame, lexical: lexical, call: call, inputs: arguments, base: base, slice_slots: life_slice_slot_params(p, function_node), destination: destination, selected_result: selected_result, next_function: newest, home: l.frame, inputs_hash: key.hash, inputs_kinds: key.kinds, mixed_kinds: mixed, island: l.island });
        if newest >= 0 { l.frames[target].function_active = l.frames[newest].function_active; }
        l.function_frames[function_node] = target as i32; life_index_frame(l, target);
    }
    if l.discovery && l.island == 0 && l.frame > 0 { l.dep_callee_stack.push(target); l.dep_callee_stamp_stack.push(-1); }
    life_cycle_call(p, l, target, call, destination);
    if l.discovery && exact_match && lexical == 0 && !l.frames[target].active {
        let same_pass = l.frames[target].checked_revision == l.pass &&
            !(l.frames[target].quiet_pass == l.pass && (l.island > 0 || life_nearest_recursive(l, l.frame) > 0));
        var clean_skip = same_pass;
        let target_omit_cr = !l.full_reads && l.nodes_prepared && (l.hold_flags[function_node] & FH_CONSTRUCT_READ) == 0;
        if !clean_skip && l.island == 0 && target_omit_cr && l.frames[target].dep_valid &&
           l.frames[target].dep_dest == destination &&
           l.frames[target].dep_in_rec == (life_nearest_recursive(l, l.frame) > 0) &&
           !(l.frames[target].quiet_pass >= 0 && life_nearest_recursive(l, l.frame) > 0) &&
           life_frame_is_clean(l, target) {
            l.frames[target].checked_revision = l.pass;
            clean_skip = true;
        }
        if clean_skip {
            if l.frames[target].first_summary >= 0 || l.frames[target].first_read >= 0 { life_replay(p, l, target, true); }
            return l.frames[target].result;
        }
    }
    if !l.discovery && !l.frames[target].active {
        // An unchanged argument list does not make a captured binding stable.
        // Revalidate only when reference-bearing captured state has changed.
        if l.frames[target].slice_slots {
            // The slot's contents can differ between calls with the same
            // reference arguments, and are read before this call's stores.
            life_reset_validation(l.frames[target]);
        } else if lexical == 0 {
            if l.frames[target].validated && l.frames[target].validated_global_epoch == l.global_live_epoch {
                if l.frames[target].first_effect >= 0 { life_replay(p, l, target); }
                return l.frames[target].result;
            }
            if l.frames[0].first_capture_input < 0 {
                if l.frames[target].validated && l.frames[target].capture_inputs < 0 {
                    l.frames[target].validated_global_epoch = l.global_live_epoch;
                    if l.frames[target].first_effect >= 0 { life_replay(p, l, target); }
                    return l.frames[target].result;
                }
                l.frames[target].capture_inputs = -1;
                life_reset_validation(l.frames[target]);
            } else if !l.frames[target].validated {
                // First validation: defer capture snapshotting unless global_live_epoch later changes.
                l.frames[target].capture_inputs = -2;
                life_reset_validation(l.frames[target]);
            } else {
                let span = life_global_capture_span(p, l, function_node);
                if l.frames[target].validated && (span.count == 0 || l.frames[target].capture_inputs != -2 &&
                   life_global_captures_match(p, l, l.frames[target].capture_inputs, span)) {
                    if span.count == 0 { l.frames[target].capture_inputs = -1; }
                    l.frames[target].validated_global_epoch = l.global_live_epoch;
                    if l.frames[target].first_effect >= 0 { life_replay(p, l, target); }
                    return l.frames[target].result;
                }
                let snap = life_capture_span_snapshot(p, l, span);
                l.frames[target].capture_inputs = snap;
                life_reset_validation(l.frames[target]);
            }
        } else {
            let capture_inputs = life_capture_inputs(p, l, function_node, lexical);
            if l.frames[target].validated && life_arguments_equal(p, l, l.frames[target].capture_inputs, capture_inputs) {
                if l.frames[target].first_effect >= 0 { life_replay(p, l, target); }
                return l.frames[target].result;
            }
            l.frames[target].capture_inputs = capture_inputs;
            life_reset_validation(l.frames[target]);
        }
    }
    let previous_frame = l.frame; let previous_scope = l.scope;
    let dep_rev_before = l.revision;
    if !l.frames[target].active {
        l.frames[target].parent = previous_frame; l.frames[target].destination = destination;
        l.frames[target].chain = l.frames[previous_frame].chain + 1; l.frames[target].chain_epoch = -1;
        l.activations += 1; l.frames[target].activation = l.activations; l.frames[target].island = l.island;
        let ctx = life_context(l, target, l.frames[previous_frame].context);
        l.frames[target].context = ctx;
    }
    l.frame = target; l.scope = p.nodes[function_node].scope;
    var formal = p.nodes[function_node].first; var item = arguments;
    while formal >= 0 {
        let symbol = p.nodes[formal].symbol;
        if !(l.nodes_prepared && symbol >= 0 && symbol < l.sym_flags.len && (l.sym_flags[symbol] & SF_SCALAR_LOCAL) != 0) {
            let cell = life_cell(p, l, symbol);
            if cell >= 0 {
                let fty = p.nodes[formal].type_id;
                var val_roots: i64 = 0;
                if item >= 0 && l.items[item].value.type_id == fty && l.items[item].value.contents == 0 {
                    val_roots = life_value_roots(p, l.items[item].value);
                } else {
                    let value = life_coerce(p, l, life_item(l, item, 0), fty);
                    val_roots = life_value_roots(p, value);
                }
                l.cells[cell].initialized = true;
                life_set_live(l, cell, true);
                // Binding a parameter makes its cell live, which only counts
                // where the lexical frame is the one being entered.
                var formal_reach = reach; if lexical == target { formal_reach = life_reach(l, lexical); }
                var roots = life_parameter_roots(p, l, val_roots, fty, function_node, formal_reach);
                if life_tf_is_ref(p, l, fty) {
                    let next = life_join(l, l.cells[cell].refs, roots);
                    if !life_equal(l, next, l.cells[cell].refs) { life_set_refs(l, cell, next); l.revision += 1; }
                    if !l.discovery && !l.frames[target].active { life_set_live_refs(l, cell, roots); }
                } else if val_roots != 0 && life_tf_holds(p, l, fty) {
                    // A by-value holder parameter whose views are not of one
                    // array exactly (or in a recursive function) only bounds
                    // those views inside the callee body (upstream heldexact).
                    let first_alt = l.alts[l.sets[val_roots].first];
                    let is_rec = (p.nodes[function_node].flags & F_RECURSIVE) != 0 && (p.nodes[function_node].flags & F_FORMAT_RAW) == 0;
                    let held_exact = !is_rec && l.sets[val_roots].count == 1 && first_alt.exact &&
                        (l.roots[first_alt.root].class_frame < 0 || l.roots[first_alt.root].class_one);
                    if !held_exact {
                        var has_nonstatic = false; var max_depth: i64 = 0; var any_bytes = false;
                        var vi = l.sets[val_roots].first;
                        while vi >= 0 {
                            let va = l.alts[vi]; vi = va.next;
                            if va.root != 0 && (l.roots[va.root].param_frame < 0 || l.frames[l.roots[va.root].param_frame].active) {
                                has_nonstatic = true;
                                if l.roots[va.root].depth > max_depth { max_depth = l.roots[va.root].depth; }
                            }
                            if va.byteview { any_bytes = true; }
                        }
                        if has_nonstatic {
                            var pr = l.cells[cell].param_bound_root as i64;
                            if pr < 0 {
                                pr = l.roots.len;
                                l.roots.push(LifeRoot { frame: target, depth: max_depth, param_frame: target });
                                l.cells[cell].param_bound_root = pr as i32;
                            } else if max_depth > l.roots[pr].depth {
                                l.roots[pr].depth = max_depth;
                            }
                            roots = life_join(l, roots, life_single(l, pr, true, -1, false, any_bytes));
                        }
                    }
                }
                if roots != 0 { life_add_contents(p, l, l.cells[cell].root, roots); }
            }
        }
        if item >= 0 { item = l.items[item].next; }
        formal = p.nodes[formal].next;
    }
    // (Evaluated again where it kept no summary this pass and one is wanted now.)
    if l.discovery && !l.frames[target].active && l.frames[target].checked_revision == l.pass &&
       !(l.frames[target].quiet_pass == l.pass && (l.island > 0 || life_nearest_recursive(l, previous_frame) > 0)) {
        l.frame = previous_frame; l.scope = previous_scope;
        if l.frames[target].first_summary >= 0 || l.frames[target].first_read >= 0 { life_replay(p, l, target, true); }
        return l.frames[target].result;
    }
    if l.frames[target].active {
        // A backedge contributes the settled effects to its caller, including
        // effects discovered after that caller returned in an earlier round.
        l.frame = previous_frame; l.scope = previous_scope;
        if l.frames[target].first_summary >= 0 || l.frames[target].first_read >= 0 { life_replay(p, l, target, true); }
        return life_cycle_value(l, l.frames[target].result);
    }
    if !l.frames[target].active {
        let saved_omit_cr = l.omit_construct_reads;
        if l.nodes_prepared { l.omit_construct_reads = !l.full_reads && (l.hold_flags[function_node] & FH_CONSTRUCT_READ) == 0; }
        let track_deps = l.discovery && l.island == 0 && l.omit_construct_reads && lexical == 0;
        let saved_tainted = l.dep_tainted;
        let saved_r_floor = l.dep_root_floor;
        let r_start = l.dep_root_stack.len;
        let c_start = l.dep_callee_stack.len;
        let dep_contents0 = l.contents_stamp;
        let dep_global0 = l.global_epoch;
        let dep_rec0 = l.recursion_epoch;
        let dep_in_rec0 = life_nearest_recursive(l, previous_frame) > 0;
        if track_deps { l.dep_tainted = false; l.dep_root_floor = r_start; }
        l.frames[target].quiet_pass = -1;
        if l.discovery && l.class_frames > 0 && l.island == 0 && life_nearest_recursive(l, target) == 0 { l.frames[target].quiet_pass = l.pass; }
        let saved_defer_base = l.frames[target].defer_base;
        l.frames[target].defer_base = l.defers.len as i32;
        l.frames[target].active = true; l.frames[l.function_frames[function_node] as i64].function_active += 1; let temporary_base = l.temp_count;
        let body_node = p.nodes[function_node].right;
        if !l.discovery { l.frames[target].live_result = LIFE_EMPTY_VALUE; }
        if result_type == TYPE_VOID && destination == 0 && (body_node < 0 || (p.nodes[body_node].flags & F_EARLY) == 0) {
            life_eval_void(p, l, body_node);
        } else {
            life_eval(p, l, body_node, destination, selected_result);
        }
        l.temp_count = temporary_base; l.frames[target].active = false; l.frames[l.function_frames[function_node] as i64].function_active -= 1;
        l.frames[target].defer_base = saved_defer_base;
        l.frames[target].checked_revision = l.pass;
        if !l.discovery {
            l.frames[target].validated = true;
            if lexical == 0 { l.frames[target].validated_global_epoch = l.global_live_epoch; }
            life_compact_effects(l, target);
        }
        if l.discovery {
            if l.revision != dep_rev_before { l.frames[target].dep_change_stamp += 1; }
            if track_deps && !l.dep_tainted && l.island == 0 && l.omit_construct_reads &&
               l.revision == dep_rev_before && (l.frames[target].quiet_pass < 0 || l.class_frames > 0 && !dep_in_rec0) {
                l.dep_gen += 1;
                var r_first = l.dep_roots.len;
                for i in r_start..l.dep_root_stack.len {
                    let r = l.dep_root_stack[i];
                    if l.dep_root_mark.len <= r { l.dep_root_mark.resize(r + 1, 0); }
                    if l.dep_root_mark[r] != l.dep_gen { l.dep_root_mark[r] = l.dep_gen; l.dep_roots.push(r); }
                }
                let r_count = l.dep_roots.len - r_first;
                if r_count > 0 && r_count <= l.frames[target].dep_roots_count {
                    let old_first = l.frames[target].dep_roots_first;
                    for i in 0..r_count { l.dep_roots[old_first + i] = l.dep_roots[r_first + i]; }
                    l.dep_roots.resize(r_first); r_first = old_first;
                }
                var c_first = l.dep_callees.len;
                for i in c_start..l.dep_callee_stack.len {
                    let c = l.dep_callee_stack[i];
                    if l.dep_callee_mark.len <= c { l.dep_callee_mark.resize(c + 1, 0); }
                    if l.dep_callee_mark[c] != l.dep_gen {
                        l.dep_callee_mark[c] = l.dep_gen;
                        l.dep_callees.push(c);
                        l.dep_callee_stamps.push(l.frames[c].dep_change_stamp);
                    }
                }
                let c_count = l.dep_callees.len - c_first;
                if c_count > 0 && c_count <= l.frames[target].dep_callees_count {
                    let old_first = l.frames[target].dep_callees_first;
                    for i in 0..c_count {
                        l.dep_callees[old_first + i] = l.dep_callees[c_first + i];
                        l.dep_callee_stamps[old_first + i] = l.dep_callee_stamps[c_first + i];
                    }
                    l.dep_callees.resize(c_first); l.dep_callee_stamps.resize(c_first); c_first = old_first;
                }
                l.frames[target].dep_valid = true;
                l.frames[target].dep_in_rec = dep_in_rec0;
                l.frames[target].dep_roots_first = r_first;
                l.frames[target].dep_roots_count = r_count;
                l.frames[target].dep_callees_first = c_first;
                l.frames[target].dep_callees_count = c_count;
                l.frames[target].dep_contents_stamp = dep_contents0;
                l.frames[target].dep_global_epoch = dep_global0;
                l.frames[target].dep_rec_epoch = dep_rec0;
                l.frames[target].dep_dest = destination;
                l.frames[target].dep_clean_pass = -1;
                l.frames[target].dep_dirty_pass = -1;
            } else {
                l.frames[target].dep_valid = false;
            }
            l.dep_root_stack.resize(r_start);
            l.dep_callee_stack.resize(c_start);
            l.dep_callee_stamp_stack.resize(c_start);
            l.dep_root_floor = saved_r_floor;
            l.dep_tainted = saved_tainted;
        }
        var ci = l.frames[target].first_cell;
        while ci >= 0 { life_set_live(l, ci, false); ci = l.cells[ci].next_frame; }
        l.omit_construct_reads = saved_omit_cr;
    }
    let result = if !l.discovery && l.frames[target].slice_slots && !l.frames[target].recursive_call { l.frames[target].live_result } else { l.frames[target].result };
    l.frame = previous_frame; l.scope = previous_scope;
    return result;
}

recursive fn life_call(p: Program&, l: Lifetimes&, node: i64, destination: i64, selected_result: i64) -> LifeValue {
    let n: const Node& = p.nodes[node];
    var out = LIFE_EMPTY_VALUE;
    out.type_id = n.type_id as i32;
    if n.symbol < 0 { return out; }
    let symbol: const Symbol& = p.symbols[n.symbol]; var builtin = -1;
    if (symbol.flags & S_BUILTIN) != 0 { builtin = symbol.index; }
    // A direct call to a proven-inert user function only needs its non-inert
    // arguments evaluated and held across subsequent arguments.
    if builtin < 0 && (n.flags & F_DISPATCH) == 0 && symbol.node >= 0 &&
       (l.node_flags[symbol.node] & NF_FN_INERT) != 0 {
        let holds = l.hold_count; var argument = n.first; var formal = p.nodes[symbol.node].first;
        while argument >= 0 {
            if (l.node_flags[argument] & NF_INERT) == 0 {
                let futures = l.future_count;
                if !l.discovery && (l.node_flags[argument] & NF_MAY_SHRINK) != 0 { life_push_future(l, p.nodes[argument].next); }
                if l.discovery {
                    life_eval_void(p, l, argument);
                } else {
                    var value = life_eval(p, l, argument); l.future_count = futures;
                    if formal >= 0 {
                        let expected = p.nodes[formal].type_id;
                        if value.relative_roots != 0 { life_receive(p, l, argument, value, expected); }
                        if expected >= 0 && life_tf_is_ref(p, l, expected) { value = life_coerce(p, l, value, expected); }
                    }
                    life_hold(l, value, argument);
                }
            }
            if formal >= 0 { formal = p.nodes[formal].next; }
            argument = p.nodes[argument].next;
        }
        if !l.discovery { life_pop_holds(l, holds); }
        if destination != 0 { out.place = destination as i32; }
        else if (l.node_flags[node] & NF_NEEDS_PLACE) != 0 && n.type_id >= 0 && p.types[n.type_id].kind != TY_VOID {
            out.place = life_temporary(p, l, node) as i32;
        }
        return out;
    }
    var items = LifeItemList {}; var argument = n.first; var parameter = -1;
    if builtin < 0 && symbol.node >= 0 { parameter = p.nodes[symbol.node].first; }
    var receiver = LIFE_EMPTY_VALUE; var arg1 = LIFE_EMPTY_VALUE; var arg2 = LIFE_EMPTY_VALUE;
    var index = 0; let holds = l.hold_count;
    if !l.discovery && (builtin == 0 || builtin == 1) { let empty_val = LIFE_EMPTY_VALUE; life_hold(l, empty_val, node, 6); }
    while argument >= 0 {
        var target = 0;
        if index > 0 && (builtin == 24 || builtin == 25 || builtin == 30 || builtin == 31) {
            target = receiver.place;
            if receiver.type_id >= 0 && life_tf_is_ref(p, l, p.types[receiver.type_id].element) { target = 0; }
        }
        var value = LIFE_EMPTY_VALUE;
        let af = l.node_flags[argument];
        if target == 0 && (af & NF_INERT) != 0 {
            value.type_id = p.nodes[argument].type_id as i32;
        } else {
            let futures = l.future_count;
            if !l.discovery && (af & NF_MAY_SHRINK) != 0 {
                life_push_future(l, p.nodes[argument].next);
            }
            let outer_place = l.dest_place; let outer_reached = l.dest_reached;
            if target != 0 && l.class_frames > 0 { l.dest_place = target; l.dest_reached = life_reached(p, n.first); }
            value = life_eval(p, l, argument, target); l.future_count = futures;
            l.dest_place = outer_place; l.dest_reached = outer_reached;
        }
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
                            if !l.discovery { life_receive(p, l, argument, value, ty); life_copy(p, l, argument, ty); life_note_temp(p, l, ty); }
                            if life_tf_is_ref(p, l, ty) { expected = ty; }
                        }
                    }
                    arm = p.nodes[arm].next;
                }
            } else if !l.discovery && !(expected >= 0 && (l.type_flags[expected] & TF_L_SCALAR) != 0) {
                life_receive(p, l, argument, value, expected); life_copy(p, l, argument, expected);
                // A by-value nonfixed parameter owns a statement temporary,
                // including when its source is a fixed-size slice or literal.
                life_note_temp(p, l, expected);
            }
            if !(value.type_id == expected && value.contents == 0) {
                if expected >= 0 && (l.type_flags[expected] & TF_L_SCALAR) != 0 &&
                   value.contents == 0 && (value.type_id < 0 || !life_tf_is_ref(p, l, value.type_id)) {
                    value.type_id = expected as i32;
                } else {
                    value = life_coerce(p, l, value, expected);
                }
            }
            parameter = p.nodes[parameter].next;
            if l.class_frames > 0 && life_tf_is_ref(p, l, expected) { value.reached = life_reached(p, argument) as i32; }
        }
        if builtin >= 0 && (builtin == 0 || builtin == 1 || builtin == 2 && index > 0) && !life_storage_path(p, argument) { life_copy(p, l, argument, value.type_id); }
        if builtin < 0 {
            life_append(l, items, value);
        } else if index == 1 {
            arg1 = value;
        } else if index == 2 {
            arg2 = value;
        }
        if index == 0 && builtin >= 0 {
            receiver = value;
            if value.type_id >= 0 && p.types[value.type_id].kind == TY_REF { receiver = life_load(p, l, p.types[value.type_id].element, value.refs); }
            if !l.discovery && receiver.type_id >= 0 {
                if builtin == 24 || builtin == 25 || builtin == 30 || builtin == 31 {
                    let element = p.types[receiver.type_id].element;
                    var constructing = element >= 0 && (l.type_flags[element] & (TF_L_SC1 | TF_L_SC2 | TF_L_REL_POOL)) != 0;
                    if builtin == 25 && p.nodes[argument].next >= 0 {
                        let source = p.nodes[argument].next; let kind = p.nodes[source].kind;
                        if kind != N_ARRAY && kind != N_FILL && life_fresh(p, source) { constructing = true; }
                    }
                    if constructing { life_hold(l, receiver, node, 1); }
                }
                if receiver.element_array != -1 && (builtin >= 24 && builtin <= 37 || builtin == 2) || builtin == 16 || builtin == 40 { life_hold(l, receiver, argument, 3); }
            }
        }
        if !l.discovery { life_hold(l, value, argument); }
        argument = p.nodes[argument].next; index += 1;
    }
    if !l.discovery { life_pop_holds(l, holds); }
    let arguments = items.first;
    if builtin < 0 {
        if !l.discovery && symbol.node >= 0 && (p.nodes[symbol.node].flags & F_FORMAT_RAW) != 0 { let raw_arg = life_item(l, arguments, 1); life_hold(l, raw_arg, node, 7); }
        var place = destination;
        if place == 0 && n.type_id >= 0 {
            let rt: const Type& = p.types[n.type_id];
            if rt.kind != TY_VOID && !(rt.kind == TY_REF && rt.length_storage < 0) {
                let need_temp = (l.node_flags[node] & NF_NEEDS_PLACE) != 0 || (l.type_flags[n.type_id] & TF_L_SCALAR) == 0;
                if need_temp { place = life_temporary(p, l, node); }
            }
        }
        if (n.flags & F_DISPATCH) != 0 {
            var arm = n.third;
            while arm >= 0 {
                let fn_symbol = p.nodes[arm].symbol;
                if fn_symbol >= 0 {
                    var formal = p.nodes[p.symbols[fn_symbol].node].first; var actual = n.first; var item = arguments;
                    while formal >= 0 && actual >= 0 {
                        let arg_val = life_item(l, item, 0);
                        life_receive(p, l, actual, arg_val, p.nodes[formal].type_id);
                        life_copy(p, l, actual, p.nodes[formal].type_id);
                        formal = p.nodes[formal].next; actual = p.nodes[actual].next;
                        if item >= 0 { item = l.items[item].next; }
                    }
                    out = life_merge(l, out, life_function(p, l, p.symbols[fn_symbol].node, node, arguments, place, selected_result));
                }
                arm = p.nodes[arm].next;
            }
        } else {
            out = life_function(p, l, symbol.node, node, arguments, place, selected_result);
            if n.type_id >= 0 && life_tf_is_ref(p, l, n.type_id) && symbol.node >= 0 {
                let signature = p.nodes[symbol.node].type_id;
                if signature >= 0 {
                    let result = p.types[signature].element;
                    if result >= 0 && life_tf_is_ref(p, l, result) &&
                       (p.types[result].flags & TF_CONST) != 0 && (p.types[n.type_id].flags & TF_CONST) == 0 {
                        out.readonly = true;
                    }
                }
            }
        }
        if out.self_pools != 0 { life_self_destination(p, l, node, place, out.self_pools); }
        if out.relative_roots != 0 { life_self_destination(p, l, node, place, out.relative_roots); }
        out.type_id = n.type_id as i32;
        if !life_tf_is_ref(p, l, n.type_id) { out.place = place as i32; out.refs = 0; }
        var contents = out.contents;
        if n.type_id >= 0 && p.types[n.type_id].kind == TY_SLICE { out.place = place as i32; contents = out.refs; }
        if contents != 0 && place != 0 {
            let dest_reached = life_dest_reached(l, place);
            var at = l.sets[place].first;
            while at >= 0 {
                let alt = l.alts[at];
                var reached: i64 = -1; if !alt.byteview { reached = alt.target_type as i64; if reached < 0 { reached = dest_reached; } }
                life_add_contents(p, l, alt.root, contents, false, reached);
                at = alt.next;
            }
        }
        life_pop_holds(l, holds); return out;
    }
    if (builtin == 16 || builtin == 9) && n.first >= 0 && p.nodes[n.first].next >= 0 {
        var output = arg1;
        if output.type_id >= 0 && p.types[output.type_id].kind == TY_REF { output = life_load(p, l, p.types[output.type_id].element, output.refs); }
        life_grow(p, l, node, output);
    }
    if builtin == 24 || builtin == 25 || builtin == 28 || builtin == 30 || builtin == 31 || builtin == 33 || builtin == 34 || builtin == 2 { life_grow(p, l, node, receiver); }
    if builtin == 26 || builtin == 27 || builtin == 28 || builtin == 29 {
        var balanced = false;
        if builtin == 28 && receiver.type_id >= 0 && p.types[receiver.type_id].array_kind == A_GROWSHRINK { balanced = life_balanced(p, l, node); }
        life_shrink(p, l, node, receiver, balanced);
    }
    if !l.discovery && (builtin == 34 || builtin == 35) {
        let run = arg1;
        if l.sets[run.refs].count == 1 && receiver.place != 0 {
            let slice = l.alts[l.sets[run.refs].first]; let root: const LifeRoot& = l.roots[slice.root];
            var separate = slice.exact && root.symbol >= 0 && (root.frame == l.frame || (p.symbols[root.symbol].flags & S_GLOBAL) != 0);
            var at = l.sets[receiver.place].first;
            while at >= 0 {
                let pool = l.alts[at]; let owner: const LifeRoot& = l.roots[pool.root];
                if pool.root == slice.root && !(pool.component >= 0 && slice.component >= 0 && pool.component != slice.component) || owner.symbol < 0 || owner.frame != l.frame && (p.symbols[owner.symbol].flags & S_GLOBAL) == 0 { separate = false; }
                at = pool.next;
            }
            if separate { life_error(p, l, node, "slice pool operation receives a slice rooted in different owned storage"); }
        }
    }
    if (builtin == 33 || builtin == 34) && n.aux >= 0 && receiver.type_id >= 0 {
        let held = l.hold_count; life_hold(l, receiver, node, 1);
        let value = life_coerce(p, l, life_eval(p, l, n.aux, receiver.place), p.types[receiver.type_id].element);
        life_store(p, l, n.aux, receiver.place, value, false, false, life_reached(p, n.first)); life_pop_holds(l, held);
    }
    if !l.discovery && builtin == 23 && receiver.type_id >= 0 {
        let argument = arg1; var same = l.sets[receiver.place].count == 1 && l.sets[argument.refs].count == 1;
        if same {
            let a = l.alts[l.sets[receiver.place].first]; let b = l.alts[l.sets[argument.refs].first];
            // A root owner's component is its own storage (upstream: index_of
            // must establish the particular array, not merely the owner).
            var owner_type = l.roots[a.root].type_id; if a.component >= 0 { owner_type = p.nodes[a.component].type_id; }
            same = a.exact && b.exact && a.root == b.root && a.component == b.component;
            // A class root's storage is its argument's.
            if same && a.component < 0 && l.roots[a.root].class_frame >= 0 { same = life_class_query(p, l, a.root, 2, p.types[receiver.type_id].element, false); }
            else if same { same = life_one_array(p, l, owner_type, p.types[receiver.type_id].element); }
        }
        if argument.refs != 0 && receiver.place != 0 && !same { life_error(p, l, node, "index_of requires an exact element root containing one array of this element type"); }
    }
    if builtin == 15 {
        out.contents = receiver.contents;
    } else if builtin == 17 {
        out.refs = receiver.place;
        if receiver.type_id >= 0 && p.types[receiver.type_id].kind == TY_SLICE { out.refs = receiver.refs; }
        var bytes = LifeBuild {}; var at = l.sets[out.refs].first;
        while at >= 0 { var alt = l.alts[at]; at = alt.next; alt.slotread = false; alt.byteview = true; alt.target_type = -1; life_build_add_alt(l, bytes, alt); }
        out.refs = life_build_end(l, bytes) as i32;
    } else if builtin == 24 || builtin == 30 || builtin == 31 {
        var element = -1; if receiver.type_id >= 0 { element = p.types[receiver.type_id].element; }
        let value = life_coerce(p, l, arg1, element);
        if n.first >= 0 { life_copy(p, l, p.nodes[n.first].next, element); }
        life_store(p, l, node, receiver.place, value, false, false, life_reached(p, n.first));
        if life_tf_is_ref(p, l, element) { out.refs = value.refs; }
        else { out.refs = receiver.place; }
        out.contents = value.contents;
    } else if builtin == 25 {
        var value = arg1;
        var source = n.first; if source >= 0 { source = p.nodes[source].next; }
        if !l.discovery && source >= 0 && p.nodes[source].kind != N_ARRAY && p.nodes[source].kind != N_FILL && receiver.type_id >= 0 &&
           life_tf_rel(p, l, p.types[receiver.type_id].element) {
            life_error(p, l, source, "append cannot copy elements containing self-relative references into another root");
        }
        if life_tf_is_ref(p, l, value.type_id) {
            var source = value.place;
            if p.types[value.type_id].kind == TY_SLICE || p.types[value.type_id].kind == TY_REF { source = value.refs; }
            var sequence = value.type_id as i64;
            if p.types[sequence].kind == TY_REF { sequence = p.types[sequence].element; }
            let element = p.types[sequence].element;
            value.contents = life_referable(p, l, life_contents(p, l, source), element) as i32;
            value.refs = 0; value.type_id = -1;
        }
        life_store(p, l, node, receiver.place, value, false, false, life_reached(p, n.first));
    } else if builtin == 40 {
        // move_from stores the source's elements into the storage its
        // destination slice views.
        var value = arg1;
        if life_tf_is_ref(p, l, value.type_id) {
            var source = value.place;
            if p.types[value.type_id].kind == TY_SLICE || p.types[value.type_id].kind == TY_REF { source = value.refs; }
            var sequence = value.type_id as i64;
            if p.types[sequence].kind == TY_REF { sequence = p.types[sequence].element; }
            let element = p.types[sequence].element;
            value.contents = life_referable(p, l, life_contents(p, l, source), element) as i32;
            value.refs = 0; value.type_id = -1;
        }
        life_store(p, l, node, receiver.refs, value);
    } else if builtin == 28 {
        var element = -1; if receiver.type_id >= 0 { element = p.types[receiver.type_id].element; }
        let fill = life_coerce(p, l, arg2, element);
        life_store(p, l, node, receiver.place, fill, false, false, life_reached(p, n.first));
    } else if builtin == 26 {
        var storage = n.type_id; if receiver.type_id >= 0 { storage = p.types[receiver.type_id].element; }
        out = life_load(p, l, storage, receiver.place, true); out.type_id = n.type_id as i32;
    } else if builtin == 33 || builtin == 34 {
        if receiver.type_id >= 0 && p.types[receiver.type_id].array_kind == A_GROW { out.refs = life_grow_only_interior(l, receiver.place) as i32; }
        else { out.refs = receiver.place; }
    }
    if !life_tf_is_ref(p, l, out.type_id) && out.type_id >= 0 && p.types[out.type_id].kind != TY_VOID {
        out.place = destination as i32;
        if out.place == 0 {
            let need_temp = (l.node_flags[node] & NF_NEEDS_PLACE) != 0 || (l.type_flags[out.type_id] & TF_L_SCALAR) == 0;
            if need_temp { out.place = life_temporary(p, l, node) as i32; }
        }
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

// Void-returning evaluator for statements, conditions and discarded operands.
// Avoids materializing and copying 72-byte LifeValue structs on hot paths.
recursive fn life_eval_void(p: Program&, l: Lifetimes&, node: i64) {
    var cur = node;
    loop {
        if cur < 0 { return; }
        if (l.node_flags[cur] & NF_INERT) != 0 { return; }
        let k = p.nodes[cur].kind;
        if k == N_EXPR_STMT || k == N_GUARD || k == N_CAST { cur = p.nodes[cur].left; continue; }
        if k == N_DEFER { cur = p.nodes[cur].right; continue; }
        if k == N_UNARY && p.nodes[cur].integer != T_BITAND && p.nodes[cur].integer != T_MUL { cur = p.nodes[cur].left; continue; }
        break;
    }
    let n: const Node& = p.nodes[cur];
    let kind = n.kind;
    if kind == N_CALL {
        if n.symbol >= 0 && (n.flags & F_DISPATCH) == 0 {
            let sym: const Symbol& = p.symbols[n.symbol];
            if (sym.flags & S_BUILTIN) == 0 && sym.node >= 0 && (l.node_flags[sym.node] & NF_FN_INERT) != 0 {
                let holds = l.hold_count; var argument = n.first; var formal = p.nodes[sym.node].first;
                while argument >= 0 {
                    if (l.node_flags[argument] & NF_INERT) == 0 {
                        if l.discovery {
                            life_eval_void(p, l, argument);
                        } else {
                            let futures = l.future_count;
                            if (l.node_flags[argument] & NF_MAY_SHRINK) != 0 { life_push_future(l, p.nodes[argument].next); }
                            var value = life_eval(p, l, argument); l.future_count = futures;
                            if formal >= 0 {
                                let expected = p.nodes[formal].type_id;
                                if value.relative_roots != 0 { life_receive(p, l, argument, value, expected); }
                                if expected >= 0 && life_tf_is_ref(p, l, expected) { value = life_coerce(p, l, value, expected); }
                            }
                            life_hold(l, value, argument);
                        }
                    }
                    if formal >= 0 { formal = p.nodes[formal].next; }
                    argument = p.nodes[argument].next;
                }
                if !l.discovery { life_pop_holds(l, holds); }
                return;
            }
        }
        life_call(p, l, cur, 0, -1); return;
    }
    if kind == N_BLOCK && (n.flags & F_EARLY) == 0 && (n.type_id < 0 || n.type_id == TYPE_VOID) {
        let saved = l.scope; if n.scope >= 0 { l.scope = n.scope; }
        let disc = l.discovery;
        let defer_mark = l.defers.len;
        var child = n.first;
        while child >= 0 {
            if p.nodes[child].kind == N_DEFER {
                if p.nodes[child].right >= 0 {
                    l.defers.push(LifeDefer { node: child as i32, scope: l.scope as i32, frame: l.frame as i32 });
                    l.pending_defers = l.defers.len - l.defer_floor;
                }
                child = p.nodes[child].next; continue;
            }
            let cf = l.node_flags[child];
            if (cf & NF_INERT) == 0 {
                let temporary_base = l.temp_count;
                if disc {
                    life_eval_void(p, l, child);
                } else {
                    let futures = l.future_count;
                    let saved_exit = l.future_exit;
                    if (cf & NF_MAY_SHRINK) != 0 { life_block_future(p, l, child); }
                    life_eval_void(p, l, child);
                    l.future_count = futures;
                    l.future_exit = saved_exit;
                }
                l.temp_count = temporary_base;
            }
            child = p.nodes[child].next;
        }
        if l.defers.len > defer_mark { life_run_defers(p, l, defer_mark, true, -1, -2); }
        if n.scope >= 0 && l.scope_has_cell[n.scope] != 0 {
            life_leave_scope(p, l, n.scope);
        }
        l.scope = saved; return;
    }
    if kind == N_IF && (n.type_id < 0 || n.type_id == TYPE_VOID) {
        if n.left >= 0 && (l.node_flags[n.left] & NF_INERT) == 0 {
            if l.discovery {
                life_eval_void(p, l, n.left);
            } else {
                let futures = l.future_count;
                if (l.node_flags[n.left] & NF_MAY_SHRINK) != 0 {
                    life_push_future(l, n.right); life_push_future(l, n.third);
                }
                life_eval_void(p, l, n.left); l.future_count = futures;
            }
        }
        l.conditional += 1;
        if n.right >= 0 && (l.node_flags[n.right] & NF_INERT) == 0 { life_eval_void(p, l, n.right); }
        if n.third >= 0 && (l.node_flags[n.third] & NF_INERT) == 0 { life_eval_void(p, l, n.third); }
        l.conditional -= 1;
        return;
    }
    if kind == N_ASSIGN { life_eval_assign(p, l, cur, n); return; }
    if kind == N_VARIABLE { life_eval_variable(p, l, cur, n); return; }
    if kind == N_RETURN { life_eval_return(p, l, n); return; }
    if kind == N_BINARY || kind == N_RANGE { life_eval_binary(p, l, n); return; }
    if (kind == N_FOR || kind == N_WHILE || kind == N_LOOP) && (n.type_id < 0 || n.type_id == TYPE_VOID) {
        var dummy = LIFE_EMPTY_VALUE; dummy.type_id = n.type_id as i32;
        life_eval_loop(p, l, cur, n, 0, -1, dummy); return;
    }
    if kind == N_BREAK { life_eval_break(p, l, n, 0, -1); return; }
    if kind == N_CONTINUE {
        if n.symbol >= 0 && l.defers.len > l.defer_floor {
            let target_mark = life_defer_target_mark(l, n.symbol);
            if target_mark >= 0 { life_run_defers(p, l, target_mark, false, l.frame, p.nodes[n.symbol].scope, n.symbol); }
        }
        return;
    }
    if kind == N_INTEGER || kind == N_FLOAT || kind == N_NULL || kind == N_BOOL || kind == N_STRING ||
       kind == N_EMPTY || kind == N_FUNCTION || kind == N_FUNCTION_VALUE || kind == N_IMPORT { return; }
    life_eval(p, l, cur);
}

fn life_global_var_read(p: Program&, l: Lifetimes&, cell: i64, type_id: i64) -> i64 {
    let t: const Type& = p.types[type_id]; let root = l.cells[cell].root;
    if t.kind == TY_REF && t.length_storage >= 0 {
        return life_pool_places(p, l, t.pool);
    }
    if t.kind == TY_SLICE {
        // The recorded bindings cover calls and unreached bodies.
        if l.discovery && l.frame > 0 { l.dep_tainted = true; if l.island > 0 { l.cls_dep_tainted = true; } }
        return life_mark_slotread(l, l.cells[cell].refs);
    }
    // A body may run after any binding of this global. As with a reference
    // loaded from a global container, use the owners its type can point into.
    var at = l.sets[l.cells[cell].refs].first; var byteview = false;
    while at >= 0 {
        if l.alts[at].byteview { byteview = true; break; }
        at = l.alts[at].next;
    }
    let start = l.scratch.len;
    if !byteview { life_global_candidates(p, l, t.element, 0, true); }
    var result = LifeBuild {}; let end = l.scratch.len;
    for i in start..end {
        var owner = l.scratch[i];
        if owner.exact && life_gs_contains(p, l, life_alt_type(p, l, owner), t.element, false) { continue; }
        if owner.root == 0 && (t.flags & TF_CONST) == 0 { continue; }
        owner.from = root; owner.slotread = true;
        life_build_add_alt(l, result, owner);
    }
    if !byteview && (t.flags & TF_CONST) != 0 && life_same(p, t.element, TYPE_U8) {
        life_build_add(l, result, life_root_set(l, 0));
    }
    let refs = life_build_end(l, result); l.scratch.resize(start);
    if refs != 0 { return life_fold(l, refs); }
    // With no exact owners, use the global as a lifetime bound. Byte views
    // may reach storage of any type, subject to the same slot-read rule.
    return life_single(l, root, false, root, true, byteview, t.element);
}
recursive fn life_eval(p: Program&, l: Lifetimes&, node: i64, destination: i64 = 0, selected_result: i64 = -1) -> LifeValue {
    if node < 0 { return LifeValue {}; }
    let n: const Node& = p.nodes[node];
    var out = LIFE_EMPTY_VALUE;
    out.type_id = n.type_id as i32;
    if (l.node_flags[node] & NF_INERT) != 0 {
        if destination != 0 && n.kind == N_CALL { out.place = destination as i32; }
        return out;
    }
    let kind = n.kind;
    if kind == N_NAME && n.symbol >= 0 && (p.symbols[n.symbol].flags & (S_FUNCTION | S_TYPE | S_BUILTIN)) == 0 {
        if (l.sym_flags[n.symbol] & SF_SCALAR_LOCAL) != 0 { return out; }
        let cell = life_cell(p, l, n.symbol);
        let root = l.cells[cell].root;
        out.place = life_root_set(l, root) as i32;
        out.refs = l.cells[cell].refs as i32;
        out.readonly = l.cells[cell].readonly;
        let holds = life_tf_holds(p, l, n.type_id);
        if l.discovery {
            if holds {
                if l.frame > 0 && (l.island == 0 || root > 0 && l.roots[root].frame <= 0 && l.roots[root].class_frame < 0) { life_push_dep_root(l, root); }
                out.contents = l.roots[root].contents as i32;
            }
        } else {
            out.refs = l.cells[cell].live_refs;
            if holds { out.contents = l.roots[root].live_contents as i32; }
        }
        if l.cell_keys[cell].global && life_tf_is_ref(p, l, p.symbols[n.symbol].type_id) {
            let ty = p.symbols[n.symbol].type_id;
            if l.frame > 0 && (p.symbols[n.symbol].flags & S_MUTABLE) != 0 && (life_plain_ref(p, ty) || p.types[ty].pool >= 0) {
                out.refs = life_global_var_read(p, l, cell, ty) as i32;
            } else {
                if l.frame == 0 { out.refs = l.cells[cell].live_refs; }
                if life_plain_ref(p, ty) { out.refs = life_mark_slotread(l, out.refs) as i32; }
            }
        }
        if holds && n.type_id >= 0 && p.types[n.type_id].kind == TY_REF {
            if l.discovery { out.contents = life_contents(p, l, out.refs) as i32; } else { out.contents = life_live_contents(p, l, out.refs) as i32; }
        }
        if l.class_frames > 0 {
            out.refs = life_fold(l, out.refs) as i32; out.contents = life_fold(l, out.contents) as i32;
            // A global also holds what the island stored outside it.
            if l.island > 0 && l.cell_keys[cell].global && l.frames[l.island].class_stored != 0 {
                let cs = l.frames[l.island].class_stored;
                if life_tf_is_ref(p, l, n.type_id) { out.contents = life_join(l, out.contents, cs) as i32; }
                else if holds { out.contents = life_join(l, out.contents, life_referable(p, l, cs, n.type_id)) as i32; }
            }
        }
        if !holds { out.contents = 0; }
        life_construct_read(p, l, node, out);
        return out;
    }
    if kind == N_MEMBER || kind == N_INDEX || kind == N_SLICE { life_eval_access(p, l, node, n, out); return out; }
    if kind == N_CALL { return life_call(p, l, node, destination, selected_result); }
    if kind == N_UNARY { life_eval_unary(p, l, n, out); return out; }
    if kind == N_CAST { return life_coerce(p, l, life_eval(p, l, n.left), n.type_id); }
    if kind == N_STRING { out.place = life_root_set(l, 0) as i32; out.refs = out.place; return out; }
    if kind == N_INTEGER || kind == N_FLOAT || kind == N_NULL || kind == N_BOOL ||
       kind == N_EMPTY || kind == N_FUNCTION || kind == N_FUNCTION_VALUE || kind == N_IMPORT { return out; }
    if kind == N_ARRAY || kind == N_FILL || kind == N_RECORD { life_eval_aggregate(p, l, node, n, destination, out); return out; }
    if kind == N_RESULT { life_eval_result(p, l, n, destination, out); return out; }
    if kind == N_BLOCK { life_eval_block(p, l, node, n, destination, selected_result, out); return out; }
    if kind == N_IF { life_eval_if(p, l, node, n, destination, selected_result, out); return out; }
    if kind == N_FOR || kind == N_WHILE || kind == N_LOOP { life_eval_loop(p, l, node, n, destination, selected_result, out); return out; }
    if kind == N_MATCH { life_eval_match(p, l, node, n, destination, selected_result, out); return out; }
    if kind == N_VARIABLE { life_eval_variable(p, l, node, n); return out; }
    if kind == N_ASSIGN { life_eval_assign(p, l, node, n); return out; }
    if kind == N_RETURN { life_eval_return(p, l, n); return out; }
    if kind == N_TUPLE { life_eval_tuple(p, l, n, out); return out; }
    if kind == N_BREAK { life_eval_break(p, l, n, destination, selected_result); return out; }
    if kind == N_CONTINUE {
        if n.symbol >= 0 && l.defers.len > l.defer_floor {
            let target_mark = life_defer_target_mark(l, n.symbol);
            if target_mark >= 0 { life_run_defers(p, l, target_mark, false, l.frame, p.nodes[n.symbol].scope, n.symbol); }
        }
        return out;
    }
    if kind == N_EXPR_STMT || kind == N_GUARD { life_eval_void(p, l, n.left); return out; }
    // A defer body runs at the exits of its enclosing block (handled in
    // life_eval_void / life_eval_block via life_run_defers); fallback if
    // evaluated directly outside a block.
    if kind == N_DEFER { life_eval_void(p, l, n.right); return out; }
    if kind == N_BINARY || kind == N_RANGE { life_eval_binary(p, l, n); return out; }
    return out;
}

// Keep each handler's temporaries out of the recursive dispatcher.
// Value handlers write into the result initialized by life_eval.
recursive fn life_eval_unary(p: Program&, l: Lifetimes&, n: const Node&, out: LifeValue&) {
    if n.integer == T_BITAND {
        let value = life_eval(p, l, n.left);
        out.refs = value.place; if value.type_id >= 0 && p.types[value.type_id].kind == TY_REF { out.refs = value.refs; } out.contents = value.contents;
        out.readonly = value.readonly;
    } else if n.integer == T_MUL {
        let value = life_eval(p, l, n.left);
        out = life_load(p, l, n.type_id, value.refs);
        if !life_tf_is_ref(p, l, n.type_id) { out.readonly = value.readonly; }
    } else {
        life_eval_void(p, l, n.left);
    }
    return;
}

recursive fn life_eval_access(p: Program&, l: Lifetimes&, node: i64, n: const Node&, out: LifeValue&) {
    let sequence = l.sequence_path;
    let reread = sequence == node && n.kind != N_SLICE;
    if reread { l.sequence_path = life_for_path(p, n.left); }
    l.reading_place += 1; var base = life_eval(p, l, n.left); l.reading_place -= 1;
    l.sequence_path = sequence;
    var storage = n.type_id;
    if n.kind == N_MEMBER && n.symbol >= 0 { storage = p.nodes[n.symbol].type_id; }
    if n.kind == N_INDEX || n.kind == N_SLICE {
        var array: i64 = base.type_id; if array >= 0 && p.types[array].kind == TY_REF { array = p.types[array].element; }
        if array >= 0 && (p.types[array].kind == TY_ARRAY || p.types[array].kind == TY_SLICE) { storage = p.types[array].element; }
    }
    if !l.discovery && !life_tf_is_ref(p, l, base.type_id) && life_tf_rel(p, l, storage) && !life_storage_path(p, n.left) { life_copy(p, l, n.left, base.type_id); }
    if base.type_id >= 0 && p.types[base.type_id].kind == TY_REF && p.types[base.type_id].element >= 0 && p.types[p.types[base.type_id].element].kind == TY_SLICE { base = life_load(p, l, p.types[base.type_id].element, base.refs); }
    var places: i64 = base.place;
    if life_tf_is_ref(p, l, base.type_id) { places = base.refs; }
    if n.kind != N_MEMBER {
        let right_inert = n.right < 0 || (l.node_flags[n.right] & NF_INERT) != 0;
        let third_inert = n.third < 0 || (l.node_flags[n.third] & NF_INERT) != 0;
        if !right_inert || !third_inert {
            let held = l.hold_count;
            if !l.discovery { var region = base; region.place = places as i32; life_hold(l, region, n.left, 3); }
            if !right_inert { life_eval_void(p, l, n.right); }
            if !third_inert { life_eval_void(p, l, n.third); }
            if !l.discovery { life_pop_holds(l, held); }
        }
    }
    var owner_type: i64 = base.type_id; if owner_type >= 0 && p.types[owner_type].kind == TY_REF { owner_type = p.types[owner_type].element; }
    if n.kind == N_MEMBER && n.symbol >= 0 && root_struct_type(p, owner_type) { places = life_component(l, places, n.symbol); }
    else if n.kind == N_MEMBER { places = life_member_interior(l, places); }
    else if (n.kind == N_SLICE || n.kind == N_INDEX) && base.type_id >= 0 && p.types[base.type_id].kind == TY_SLICE { }
    else if (n.kind == N_SLICE || n.kind == N_INDEX) && owner_type >= 0 && p.types[owner_type].kind == TY_ARRAY && p.types[owner_type].array_kind == A_GROW { places = life_grow_only_interior(l, places); }
    else { places = life_interior(l, places); }
    if n.kind == N_SLICE { out.refs = places as i32; out.contents = life_contents(p, l, places) as i32; out.place = places as i32; }
    else if storage < 0 || (l.type_flags[storage] & (TF_L_REF | TF_L_HOLDS)) == 0 { out.place = places as i32; }
    else {
        out = life_load(p, l, storage, places, true); out.type_id = n.type_id as i32;
    }
    if base.readonly && (n.kind == N_SLICE || !life_tf_is_ref(p, l, storage)) { out.readonly = true; }
    out.element_array = base.element_array;
    if out.element_array < 0 && (n.kind == N_INDEX || n.kind == N_SLICE) {
        out.element_array = base.type_id;
        if out.element_array >= 0 && p.types[out.element_array].kind == TY_REF { out.element_array = p.types[out.element_array].element as i32; }
        if out.element_array < 0 { out.element_array = -2; }
    }
    // A field or element containing a reference or slice can be read again
    // on each iteration. Its slot stays live along the sequence's path.
    if reread && life_tf_is_ref(p, l, storage) { var slot = out; slot.type_id = storage as i32; life_hold(l, slot, node, 4); }
    life_construct_read(p, l, node, out); return;
}

recursive fn life_eval_result(p: Program&, l: Lifetimes&, n: const Node&, destination: i64, out: LifeValue&) {
    let producer = life_eval(p, l, n.left, destination, n.integer);
    out = life_item(l, producer.tuple, n.integer); out.type_id = n.type_id as i32;
    return;
}

recursive fn life_eval_aggregate(p: Program&, l: Lifetimes&, node: i64, n: const Node&, destination: i64, out: LifeValue&) {
    if n.kind == N_ARRAY && n.first < 0 && (n.flags & F_DEFAULT) != 0 && n.type_id >= 0 && p.types[n.type_id].kind == TY_SLICE {
        out.place = life_root_set(l, 0) as i32; out.refs = out.place; return;
    }
    out.place = destination as i32; if out.place == 0 { out.place = life_temporary(p, l, node) as i32; }
    let held = l.hold_count; var child = n.first;
    // Check the initializer even though a zero fill stores no elements.
    if n.kind == N_FILL && n.right >= 0 && p.nodes[n.right].kind == N_INTEGER && p.nodes[n.right].integer == 0 {
        let initializer = if child >= 0 { child } else { n.left };
        life_eval_void(p, l, initializer);
        if n.type_id >= 0 { life_copy(p, l, initializer, p.types[n.type_id].element); }
        return;
    }
    if life_cached_size_class(p, l, n.type_id) > 0 { life_hold(l, out, node, 6); }
    let root_owner = n.kind == N_RECORD && root_struct_type(p, n.type_id);
    while child >= 0 {
        var value_node = child; var expected = -1;
        if n.kind == N_RECORD { value_node = p.nodes[child].right; expected = p.nodes[child].type_id; }
        else if n.type_id >= 0 { expected = p.types[n.type_id].element; }
        if value_node >= 0 && l.nodes_prepared && value_node < l.node_flags.len && (l.node_flags[value_node] & NF_INERT) != 0 &&
           expected >= 0 && expected < l.type_flags.len && (l.type_flags[expected] & TF_L_SCALAR) != 0 {
            child = p.nodes[child].next; continue;
        }
        // A root owner's field is constructed in that field's own storage.
        var place: i64 = out.place; if root_owner && p.nodes[child].symbol >= 0 { place = life_component(l, out.place, p.nodes[child].symbol); }
        if value_node >= 0 && p.nodes[value_node].kind == N_SELF {
            let reference: const Type& = p.types[expected];
            if reference.pool >= 0 {
                out.self_pools = life_join(l, out.self_pools, life_pool_places(p, l, reference.pool)) as i32;
                life_self_destination(p, l, value_node, place, out.self_pools);
            }
            // Relative readback derives the owner or named pool. The
            // encoded self offset holds no external reference alive.
            child = p.nodes[child].next; continue;
        }
        var target = place; if life_is_ref(p, expected) { target = 0; }
        let future = l.future_count;
        if !l.discovery && (!l.nodes_prepared || value_node < 0 || value_node >= l.node_flags.len || (l.node_flags[value_node] & NF_MAY_SHRINK) != 0) {
            life_push_future(l, p.nodes[child].next);
        }
        let value = life_coerce(p, l, life_eval(p, l, value_node, target), expected); l.future_count = future;
        if !l.discovery { life_hold(l, value, value_node); }
        life_copy(p, l, value_node, expected);
        life_store(p, l, value_node, place, value, false, false, life_dest_reached(l, out.place));
        out.contents = life_join(l, out.contents, life_stored_roots(p, l, value)) as i32;
        // A root owner's field was stored in its own component, where its
        // pool-relative and self-relative values were placed.
        if !root_owner { out.self_pools = life_join(l, out.self_pools, value.self_pools) as i32; out.relative_roots = life_join(l, out.relative_roots, value.relative_roots) as i32; }
        if !root_owner && expected >= 0 && p.types[expected].kind == TY_REF && p.types[expected].length_storage >= 0 && p.types[expected].pool < 0 {
            out.relative_roots = life_join(l, out.relative_roots, value.refs) as i32;
        }
        child = p.nodes[child].next;
    }
    if n.kind == N_FILL && n.first < 0 {
        let value = life_eval(p, l, n.left, out.place); life_store(p, l, node, out.place, value, false, false, life_dest_reached(l, out.place));
        out.contents = life_stored_roots(p, l, value) as i32; out.self_pools = value.self_pools; out.relative_roots = value.relative_roots; life_eval_void(p, l, n.right);
    }
    if life_is_ref(p, n.type_id) { out.refs = out.place; }
    life_pop_holds(l, held); return;
}

recursive fn life_eval_variable(p: Program&, l: Lifetimes&, node: i64, n: const Node&) {
    if n.first < 0 && n.symbol >= 0 && l.nodes_prepared && n.symbol < l.sym_flags.len && (l.sym_flags[n.symbol] & SF_SCALAR_LOCAL) != 0 {
        life_eval_void(p, l, n.right);
        return;
    }
    var binding = n.first; if binding < 0 { binding = node; }
    var initializer = n.right; var index = 0; var aggregate = LifeValue {};
    if !l.discovery {
        var at = binding;
        while at >= 0 {
            let symbol = p.nodes[at].symbol;
            if symbol >= 0 && life_cached_size_class(p, l, p.symbols[symbol].type_id) > 0 { let cell = life_cell(p, l, symbol); life_set_live(l, cell, true); }
            if n.first < 0 { break; } at = p.nodes[at].next;
        }
    }
    if n.first >= 0 && initializer >= 0 && p.nodes[initializer].next < 0 { aggregate = life_eval(p, l, initializer); }
    while binding >= 0 {
        let symbol = p.nodes[binding].symbol;
        if l.nodes_prepared && symbol >= 0 && symbol < l.sym_flags.len && (l.sym_flags[symbol] & SF_SCALAR_LOCAL) != 0 {
            if aggregate.tuple < 0 && initializer >= 0 { life_eval_void(p, l, initializer); }
        } else {
            let cell = life_cell(p, l, symbol);
            if cell >= 0 {
                if !l.discovery || l.frame == 0 && l.cell_keys[cell].global { life_set_live_refs(l, cell, 0); }
                if !l.discovery { life_set_live_contents(l, l.cells[cell].root, 0); }
                else if l.roots[l.cells[cell].root].frame > 0 { l.roots[l.cells[cell].root].live_contents = 0; }
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
                life_set_live(l, cell, true);
            }
        }
        if n.first < 0 { break; }
        binding = p.nodes[binding].next; index += 1;
        if initializer >= 0 && aggregate.tuple < 0 { initializer = p.nodes[initializer].next; }
    }
}

// A field path in its owner's storage (including a frame prefix) survives
// shrinking its tail. Indexing and following other references can reach elements.
fn life_assignment_in_fields(p: Program&, l: Lifetimes&, node: i64) -> bool {
    var at = node;
    while p.nodes[at].kind == N_MEMBER {
        at = p.nodes[at].left;
        let base: const Node& = p.nodes[at];
        if base.kind == N_UNARY && base.integer == T_MUL && (base.flags & F_SYNTHETIC) != 0 { at = base.left; }
        let ty = p.nodes[at].type_id;
        if ty < 0 || p.types[ty].kind == TY_SLICE ||
           p.types[ty].kind == TY_REF && life_cached_size_class(p, l, p.types[ty].element) != 2 { return false; }
    }
    if p.nodes[at].kind != N_NAME { return false; }
    let ty = p.nodes[at].type_id;
    return ty >= 0 && p.types[ty].kind != TY_SLICE &&
           (p.types[ty].kind != TY_REF || life_cached_size_class(p, l, p.types[ty].element) == 2);
}

recursive fn life_eval_assign(p: Program&, l: Lifetimes&, node: i64, n: const Node&) {
    if n.left >= 0 && l.nodes_prepared {
        let ln: const Node& = p.nodes[n.left];
        if ln.kind == N_NAME && ln.symbol >= 0 && ln.symbol < l.sym_flags.len && (l.sym_flags[ln.symbol] & SF_SCALAR_LOCAL) != 0 {
            life_eval_void(p, l, n.right);
            return;
        }
    }
    l.reading_place += 1; var target = life_eval(p, l, n.left); l.reading_place -= 1;
    var places: i64 = target.place; var ty: i64 = target.type_id;
    var binding = p.nodes[n.left].kind == N_NAME && life_is_ref(p, ty);
    let through = ty >= 0 && p.types[ty].kind == TY_REF && n.integer != T_DOTASSIGN;
    if !l.discovery && target.readonly && (through || !binding) {
        life_error(p, l, node, "cannot write through this reference: non-writable provenance (§9.5)");
    }
    if ty >= 0 && p.types[ty].kind == TY_REF && n.integer != T_DOTASSIGN {
        places = target.refs; ty = p.types[ty].element; binding = life_is_ref(p, ty);
    }
    let held = l.hold_count; var receiver = target; receiver.type_id = ty as i32; receiver.place = places as i32;
    var kind = 3; let future = l.future_count;
    if !l.discovery && (!l.nodes_prepared || n.right < 0 || n.right >= l.node_flags.len || (l.node_flags[n.right] & NF_MAY_SHRINK) != 0) {
        life_push_future(l, n.right);
    }
    if life_cached_size_class(p, l, ty) == 2 || ty >= 0 && p.types[ty].kind == TY_ENUM && (p.types[ty].flags & F_VARIABLE_MODE) != 0 { life_replace(p, l, node, receiver); }
    if life_cached_size_class(p, l, ty) == 2 {
        if l.nodes_prepared && !l.full_reads && (l.hold_flags[node] & FH_SC2_SITE) == 0 { l.need_full_reads = true; }
        life_shrink(p, l, node, receiver); kind = 2;
    }
    if !l.discovery && (kind == 2 || through || !life_assignment_in_fields(p, l, n.left)) { life_hold(l, receiver, n.left, kind); }
    var destination = places; if life_is_ref(p, ty) { destination = 0; }
    let outer_place = l.dest_place; let outer_reached = l.dest_reached;
    if destination != 0 && l.class_frames > 0 { l.dest_place = destination; l.dest_reached = life_reached(p, n.left, true); if through { l.dest_reached = ty; } }
    let saved_omit_cr = l.omit_construct_reads;
    if kind == 2 { l.omit_construct_reads = false; }
    let natural = life_eval(p, l, n.right, destination); life_receive(p, l, n.right, natural, ty);
    l.omit_construct_reads = saved_omit_cr;
    l.dest_place = outer_place; l.dest_reached = outer_reached;
    let value = life_coerce(p, l, natural, ty); life_pop_holds(l, held); l.future_count = future;
    life_copy(p, l, n.right, ty);
    if !l.discovery && l.conditional == 0 && !binding && life_only_static(l, life_value_roots(p, value)) {
        let left_node: const Node& = p.nodes[n.left];
        if left_node.kind == N_NAME {
            if ty < 0 || life_is_ref(p, ty) || life_tf_holds(p, l, ty) {
                var at = l.sets[places].first;
                var kill_ty: i64 = -1; if through { kill_ty = ty; }
                while at >= 0 {
                    let alt = l.alts[at];
                    if alt.exact && !l.roots[alt.root].class_empty && life_kill_matches_root(p, l, alt.root as i64, kill_ty) {
                        let root_ty = l.roots[alt.root].type_id;
                        if l.roots[alt.root].class_frame >= 0 || root_ty < 0 || life_tf_holds(p, l, root_ty) {
                            var kv = LIFE_EMPTY_VALUE; kv.type_id = kill_ty as i32;
                            let eff = LifeEffect { kind: 6, node: node as i32, value: kv, places: life_root_set(l, alt.root) as i32 };
                            life_effect(p, l, eff);
                            life_set_live_contents(l, alt.root, 0);
                        }
                    }
                    at = alt.next;
                }
            }
        } else if left_node.kind == N_MEMBER && left_node.symbol >= 0 {
            let field_ty = p.nodes[left_node.symbol].type_id;
            if field_ty < 0 || life_is_ref(p, field_ty) || life_tf_holds(p, l, field_ty) {
                var at = l.sets[places].first;
                while at >= 0 {
                    let alt = l.alts[at];
                    if alt.exact && !l.roots[alt.root].class_empty {
                        let root_ty = l.roots[alt.root].type_id;
                        if l.roots[alt.root].class_frame >= 0 || root_ty < 0 || life_tf_holds(p, l, root_ty) {
                            let eff = LifeEffect { kind: 7, node: node as i32, value: LIFE_EMPTY_VALUE, places: life_root_set(l, alt.root) as i32, field: left_node.symbol as i32 };
                            life_effect(p, l, eff);
                            life_kill_field(l, alt.root, left_node.symbol);
                        }
                    }
                    at = alt.next;
                }
            }
        }
    }
    if n.right >= 0 {
        if binding && ty >= 0 && p.types[ty].kind == TY_REF && p.types[ty].length_storage >= 0 && p.types[ty].pool >= 0 {
            life_relative_store(p, l, node, places, value);
            let eff = LifeEffect { kind: 9, node: node as i32, value: value, places: places as i32 };
            life_effect(p, l, eff);
        }
        if !binding && l.nodes_prepared && ty >= 0 && ty < l.type_flags.len && (l.type_flags[ty] & TF_L_SCALAR) != 0 &&
           value.self_pools == 0 && value.relative_roots == 0 && value.refs == 0 && value.contents == 0 {
            return;
        }
        var path = life_reached(p, n.left, true); if through { path = ty; }
        life_store(p, l, node, places, value, binding, through, path);
    }
}

recursive fn life_eval_return(p: Program&, l: Lifetimes&, n: const Node&) {
    let held = l.hold_count;
    var child = n.first; var result = LifeValue {}; var count = 0; var items = LifeItemList {};
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
    let multi = child >= 0 && p.nodes[child].next >= 0;
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
        if life_tf_is_ref(p, l, target_type) { place = 0; }
        let natural = life_eval(p, l, child, place, projected);
        if !l.discovery { life_receive(p, l, child, natural, target_type); }
        let value = life_coerce(p, l, natural, target_type);
        if !l.discovery {
            if target_type >= 0 && p.types[target_type].kind == TY_REF && p.types[target_type].length_storage >= 0 { life_error(p, l, child, "function results are values and cannot have relative-reference storage types"); }
            life_copy(p, l, child, target_type, target_frame);
        }
        life_return_value(p, l, child, value, target_frame);
        if multi { life_append(l, items, value); }
        if !l.discovery { life_hold(l, value, child); }
        result = value; count += 1; child = p.nodes[child].next;
    }
    if count > 1 { result = LifeValue { tuple: items.first as i32 }; }
    if !l.discovery && l.frames[target_frame].slice_slots && !l.frames[target_frame].recursive_call {
        l.frames[target_frame].live_result = life_merge(l, l.frames[target_frame].live_result, result);
    }
    let old = l.frames[target_frame].result;
    let joined = life_merge(l, old, result);
    if old.readonly != joined.readonly || !life_equal(l, old.refs, joined.refs) || !life_equal(l, old.contents, joined.contents) || !life_equal(l, old.self_pools, joined.self_pools) || !life_equal(l, old.relative_roots, joined.relative_roots) { l.revision += 1; }
    l.frames[target_frame].result = joined;
    if l.defers.len > l.defer_floor {
        let mark = l.frames[target_frame].defer_base as i64;
        life_run_defers(p, l, mark, false, target_frame, -1);
    }
    life_pop_holds(l, held);
}

recursive fn life_eval_tuple(p: Program&, l: Lifetimes&, n: const Node&, out: LifeValue&) {
    var items = LifeItemList {};
    let held = l.hold_count; var child = n.first;
    while child >= 0 { let value = life_eval(p, l, child); life_append(l, items, value); life_hold(l, value, child); child = p.nodes[child].next; }
    out.tuple = items.first as i32; life_pop_holds(l, held); return;
}

// A jump in a nested loop's body has its own target. A jump in the
// enclosing block may bypass a later return or break.
recursive fn life_bypasses_exit(p: Program&, l: Lifetimes&, node: i64) -> bool {
    if node < 0 { return false; }
    if node < l.bypass_memo.len {
        let m = l.bypass_memo[node];
        if m != 0 { return m == 2; }
    } else {
        l.bypass_memo.resize(p.nodes.len, 0);
    }
    let n: const Node& = p.nodes[node];
    var ans = false;
    if n.kind == N_CONTINUE || n.kind == N_BREAK { ans = true; }
    else if n.kind != N_FUNCTION && n.kind != N_FUNCTION_VALUE && n.kind != N_IMPORT {
        if n.kind == N_FOR || n.kind == N_WHILE || n.kind == N_LOOP {
            ans = life_bypasses_exit(p, l, n.left);
        } else {
            var child = n.first;
            while child >= 0 {
                if life_bypasses_exit(p, l, child) { ans = true; break; }
                child = p.nodes[child].next;
            }
            if !ans {
                ans = life_bypasses_exit(p, l, n.left) || life_bypasses_exit(p, l, n.right) || life_bypasses_exit(p, l, n.third);
            }
        }
    }
    l.bypass_memo[node] = if ans { 2 } else { 1 };
    return ans;
}

fn life_push_active_defers(p: Program&, l: Lifetimes&, from: i64, to: i64) {
    if l.discovery { return; }
    var i = to - 1;
    while i >= from {
        let d = l.defers[i];
        let body = p.nodes[d.node].right;
        if body >= 0 {
            let entry = LifeFuture { node: body, frame: d.frame as i64, scope: d.scope as i64, loop_scope: -1, last: -1 };
            if l.future_count == l.futures.len { l.futures.push(entry); } else { l.futures[l.future_count] = entry; }
            l.future_count += 1;
        }
        i -= 1;
    }
}

fn life_defer_target_mark(l: Lifetimes&, target_node: i64) -> i64 {
    var i = l.defer_targets.len - 1;
    while i >= 0 {
        if (l.defer_targets[i].node as i64) == target_node { return l.defer_targets[i].defer_mark as i64; }
        i -= 1;
    }
    return -1;
}

recursive fn life_run_defers(p: Program&, l: Lifetimes&, mark: i64, pop: bool, exit_frame: i64, exit_scope: i64, continue_loop: i64 = -1) {
    var from = mark;
    if from < l.defer_floor { from = l.defer_floor; }
    let top = l.defers.len;
    if top <= from { return; }
    let run_start = l.defer_run.len;
    for i in from..top { l.defer_run.push(l.defers[i]); }
    let run_count = l.defer_run.len - run_start;
    l.defers.resize(from);
    l.pending_defers = l.defers.len - l.defer_floor;
    let saved_exit = l.future_exit;
    let saved_futures = l.future_count;
    let saved_frame = l.frame;
    let saved_scope = l.scope;
    let saved_temp = l.temp_count;
    if exit_frame >= 0 {
        l.future_exit = LifeFutureExit { frame: exit_frame, scope: exit_scope, before: saved_futures };
    }
    var k = run_count - 1;
    while k >= 0 {
        if !l.discovery {
            if continue_loop >= 0 {
                let ln: const Node& = p.nodes[continue_loop];
                l.frame = saved_frame; l.scope = saved_scope;
                life_push_future(l, ln.right, ln.scope);
                life_push_future(l, ln.left, ln.scope);
            }
            var r = k - 1;
            while r >= 0 {
                let rd = l.defer_run[run_start + r];
                let rbody = p.nodes[rd.node].right;
                if rbody >= 0 {
                    let entry = LifeFuture { node: rbody, frame: rd.frame as i64, scope: rd.scope as i64, loop_scope: -1, last: -1 };
                    if l.future_count == l.futures.len { l.futures.push(entry); } else { l.futures[l.future_count] = entry; }
                    l.future_count += 1;
                }
                r -= 1;
            }
            life_push_active_defers(p, l, l.defer_floor, from);
        }
        let d = l.defer_run[run_start + k];
        l.frame = d.frame as i64;
        l.scope = d.scope as i64;
        l.temp_count = saved_temp;
        life_eval_void(p, l, p.nodes[d.node].right);
        l.future_count = saved_futures;
        l.frame = saved_frame;
        l.scope = saved_scope;
        l.temp_count = saved_temp;
        k -= 1;
    }
    l.future_exit = saved_exit;
    if !pop {
        for i in 0..run_count { l.defers.push(l.defer_run[run_start + i]); }
    }
    l.defer_run.resize(run_start);
    l.pending_defers = l.defers.len - l.defer_floor;
}

fn life_block_future(p: Program&, l: Lifetimes&, child: i64) {
    if l.defers.len > l.defer_floor {
        life_push_active_defers(p, l, l.defer_floor, l.defers.len);
    }
    let next = p.nodes[child].next;
    if next < 0 { return; }
    var last: i64 = -1;
    // Recursive activations share a frame's future stack. Those caller
    // futures still apply when this activation returns.
    if l.pending_defers == 0 && !life_cyclic(p, l, l.frame) {
        var after = next;
        while after >= 0 && p.nodes[after].kind != N_RETURN && p.nodes[after].kind != N_BREAK {
            after = p.nodes[after].next;
        }
        if after >= 0 {
            let stmt: const Node& = p.nodes[after];
            var cut: i64 = -1;
            let fn_node = l.frames[l.frame].function_node;
            if stmt.kind == N_BREAK && stmt.symbol >= 0 { cut = p.nodes[stmt.symbol].scope; }
            let local_return = stmt.kind == N_RETURN && fn_node >= 0 && stmt.symbol == p.nodes[fn_node].symbol;
            if cut >= 0 || local_return {
                var prior = child;
                while prior != after && !life_bypasses_exit(p, l, prior) { prior = p.nodes[prior].next; }
                // Evaluate the exit operand too. A conditional jump in it
                // can still resume an enclosing loop.
                if prior == after && !life_bypasses_exit(p, l, stmt.first) && !life_bypasses_exit(p, l, stmt.left) {
                    l.future_exit = LifeFutureExit { frame: l.frame, scope: cut, before: l.future_count };
                    last = after;
                }
            }
        }
    }
    life_push_future(l, next, -1, last);
}

recursive fn life_eval_block(p: Program&, l: Lifetimes&, node: i64, n: const Node&, destination: i64, selected_result: i64, out: LifeValue&) {
    var receiving = destination;
    if (n.flags & F_EARLY) != 0 {
        if receiving == 0 && n.type_id >= 0 && (p.types[n.type_id].kind == TY_ARRAY || p.types[n.type_id].kind == TY_STRUCT || p.types[n.type_id].kind == TY_ENUM) { receiving = life_temporary(p, l, node); }
        life_control_destination(l, node, receiving, selected_result);
    }
    let saved = l.scope; if n.scope >= 0 { l.scope = n.scope; }
    let depth = life_depth(l, saved); var child = n.first;
    let defer_mark = l.defers.len;
    let target_mark = l.defer_targets.len;
    if (n.flags & F_EARLY) != 0 {
        l.defer_targets.push(LifeDeferTarget { node: node as i32, defer_mark: defer_mark as i32 });
    }
    while child >= 0 {
        if p.nodes[child].kind == N_DEFER {
            if p.nodes[child].right >= 0 {
                l.defers.push(LifeDefer { node: child as i32, scope: l.scope as i32, frame: l.frame as i32 });
                l.pending_defers = l.defers.len - l.defer_floor;
            }
            child = p.nodes[child].next; continue;
        }
        let is_tail = child == n.last && (p.nodes[child].flags & F_TAIL) != 0;
        if !is_tail && l.nodes_prepared && child < l.node_flags.len && (l.node_flags[child] & NF_INERT) != 0 {
            child = p.nodes[child].next; continue;
        }
        let futures = l.future_count; let temporary_base = l.temp_count;
        let saved_exit = l.future_exit;
        if !l.discovery && (!l.nodes_prepared || child >= l.node_flags.len || (l.node_flags[child] & NF_MAY_SHRINK) != 0) {
            life_block_future(p, l, child);
        }
        if is_tail {
            let value = life_eval(p, l, child, receiving, selected_result);
            out = life_coerce(p, l, value, n.type_id);
        } else {
            life_eval_void(p, l, child);
        }
        l.future_exit = saved_exit;
        l.future_count = futures; l.temp_count = temporary_base;
        child = p.nodes[child].next;
    }
    if l.defers.len > defer_mark {
        let held = l.hold_count;
        if !l.discovery && out.type_id >= 0 { life_hold(l, out, node); }
        life_run_defers(p, l, defer_mark, true, -1, -2);
        if !l.discovery { life_pop_holds(l, held); }
    }
    l.defer_targets.resize(target_mark);
    if !l.nodes_prepared || node >= l.node_flags.len || (l.node_flags[node] & NF_HAS_EXIT) != 0 {
        let exit = life_find_exit(l, node);
        if exit >= 0 { out = life_merge(l, out, life_coerce(p, l, l.exits[exit].value, n.type_id)); }
    }
    if !l.discovery && (out.refs != 0 || out.contents != 0) { life_branch(p, l, node, out, depth); }
    life_leave_scope(p, l, n.scope);
    l.scope = saved;
    if out.type_id >= 0 { life_construct_value(p, l, node, out, receiving); }
    return;
}

recursive fn life_eval_if(p: Program&, l: Lifetimes&, node: i64, n: const Node&, destination: i64, selected_result: i64, out: LifeValue&) {
    if n.left >= 0 && !(l.nodes_prepared && n.left < l.node_flags.len && (l.node_flags[n.left] & NF_INERT) != 0) {
        let futures = l.future_count;
        if !l.discovery && (!l.nodes_prepared || n.left >= l.node_flags.len || (l.node_flags[n.left] & NF_MAY_SHRINK) != 0) {
            life_push_future(l, n.right); life_push_future(l, n.third);
        }
        life_eval_void(p, l, n.left); l.future_count = futures;
    }
    l.conditional += 1;
    let a = life_coerce(p, l, life_eval(p, l, n.right, destination, selected_result), n.type_id);
    let b = life_coerce(p, l, life_eval(p, l, n.third, destination, selected_result), n.type_id);
    l.conditional -= 1;
    if !l.discovery && (a.refs != 0 || a.contents != 0 || b.refs != 0 || b.contents != 0) {
        let d = life_depth(l, l.scope);
        life_branch(p, l, node, a, d); life_branch(p, l, node, b, d);
    }
    out = life_merge(l, a, b); out.type_id = n.type_id as i32;
    if out.type_id >= 0 { life_construct_value(p, l, node, out, destination); }
    return;
}

recursive fn life_eval_match(p: Program&, l: Lifetimes&, node: i64, n: const Node&, destination: i64, selected_result: i64, out: LifeValue&) {
    let future = l.future_count;
    if !l.discovery && (!l.nodes_prepared || n.left < 0 || n.left >= l.node_flags.len || (l.node_flags[n.left] & NF_MAY_SHRINK) != 0) {
        var branch = n.first;
        while branch >= 0 { life_push_future(l, p.nodes[branch].right); branch = p.nodes[branch].next; }
    }
    var source = life_eval(p, l, n.left); l.future_count = future; var arm = n.first;
    if source.type_id >= 0 && p.types[source.type_id].kind == TY_REF {
        source = life_load(p, l, p.types[source.type_id].element, source.refs);
    }
    while arm >= 0 {
        let a: const Node& = p.nodes[arm]; let pattern: const Node& = p.nodes[a.left];
        var pat_cell: i64 = -1;
        if pattern.left >= 0 && p.nodes[pattern.left].symbol >= 0 {
            let symbol = p.nodes[pattern.left].symbol;
            if !(l.nodes_prepared && symbol < l.sym_flags.len && (l.sym_flags[symbol] & SF_SCALAR_LOCAL) != 0) {
                pat_cell = life_cell(p, l, symbol);
                if !l.discovery { life_set_live_refs(l, pat_cell, 0); life_set_live_contents(l, l.cells[pat_cell].root, 0); }
                else if l.roots[l.cells[pat_cell].root].frame > 0 { l.roots[l.cells[pat_cell].root].live_contents = 0; }
                var value = source; value.type_id = p.symbols[symbol].type_id as i32;
                if life_is_ref(p, value.type_id) { value.refs = source.place; }
                life_copy(p, l, n.left, p.symbols[symbol].type_id);
                life_store(p, l, pattern.left, life_root_set(l, l.cells[pat_cell].root), value, true); l.cells[pat_cell].initialized = true; life_set_live(l, pat_cell, true);
            }
        }
        life_eval_void(p, l, a.third);
        let value = life_coerce(p, l, life_eval(p, l, a.right, destination, selected_result), n.type_id);
        if !l.discovery && (value.refs != 0 || value.contents != 0) { life_branch(p, l, a.right, value, life_depth(l, l.scope)); }
        out = life_merge(l, out, value);
        if pat_cell >= 0 { life_set_live(l, pat_cell, false); }
        arm = a.next;
    }
    out.type_id = n.type_id as i32;
    if out.type_id >= 0 { life_construct_value(p, l, node, out, destination); }
    return;
}

fn life_for_path(p: Program&, node: i64) -> i64 {
    var at = node;
    while at >= 0 {
        let n: const Node& = p.nodes[at];
        if n.kind != N_UNARY || n.left < 0 { break; }
        if n.integer == T_MUL && (n.flags & F_SYNTHETIC) != 0 { at = n.left; continue; }
        if n.integer != T_BITAND { break; }
        let child: const Node& = p.nodes[n.left];
        if (child.kind != N_MEMBER && child.kind != N_INDEX) || child.type_id < 0 || p.types[child.type_id].kind == TY_REF { break; }
        at = n.left;
    }
    return at;
}

recursive fn life_eval_loop(p: Program&, l: Lifetimes&, node: i64, n: const Node&, destination: i64, selected_result: i64, out: LifeValue&) {
    var receiving = destination;
    if n.kind == N_LOOP {
        if receiving == 0 && n.type_id >= 0 && (p.types[n.type_id].kind == TY_ARRAY || p.types[n.type_id].kind == TY_STRUCT || p.types[n.type_id].kind == TY_ENUM) { receiving = life_temporary(p, l, node); }
        life_control_destination(l, node, receiving, selected_result);
    }
    // A for sequence belongs to the enclosing statement; its temporary
    // storage encloses the binder/body scope that the statement opens.
    let saved = l.scope; if n.kind != N_FOR && n.scope >= 0 { l.scope = n.scope; }
    let held = l.hold_count; let sequence = l.sequence_path;
    var range_fast = false;
    if n.kind == N_FOR && n.left >= 0 && p.nodes[n.left].kind == N_RANGE {
        range_fast = true;
        var b = n.first;
        while b >= 0 {
            let s = p.nodes[b].symbol;
            if s < 0 || (l.sym_flags[s] & SF_SCALAR_LOCAL) == 0 { range_fast = false; break; }
            b = p.nodes[b].next;
        }
    }
    if n.kind == N_FOR { l.sequence_path = life_for_path(p, n.left); }
    let future = l.future_count;
    if !l.discovery && (n.left < 0 || (l.node_flags[n.left] & NF_MAY_SHRINK) != 0) {
        life_push_future(l, n.right);
    }
    var source = LIFE_EMPTY_VALUE;
    if n.kind == N_FOR && !range_fast { source = life_eval(p, l, n.left); }
    else { life_eval_void(p, l, n.left); }
    l.sequence_path = sequence; l.future_count = future;
    if n.kind == N_FOR {
        if range_fast {
            if n.scope >= 0 { l.scope = n.scope; }
        } else {
            let sequence_node: const Node& = p.nodes[n.left];
            if !l.discovery && (sequence_node.kind == N_ARRAY || sequence_node.kind == N_FILL) && life_cached_size_class(p, l, source.type_id) > 0 {
                life_error(p, l, n.left, "an array literal of variable-size elements requires a construction context before iteration");
            }
            if !life_is_ref(p, source.type_id) && !life_storage_path(p, n.left) { life_copy(p, l, n.left, source.type_id); }
            if n.scope >= 0 { l.scope = n.scope; }
            if !l.discovery {
                life_hold(l, source, n.left);
                var sequence = source;
                if sequence.type_id >= 0 && p.types[sequence.type_id].kind == TY_REF {
                    sequence.type_id = p.types[sequence.type_id].element as i32;
                    sequence.place = sequence.refs;
                }
                if sequence.type_id >= 0 && p.types[sequence.type_id].kind == TY_ARRAY &&
                   life_cached_size_class(p, l, sequence.type_id) != 2 {
                    life_hold(l, sequence, n.left, 4);
                }
            }
            var binding = n.first; var index = 0;
            while binding >= 0 {
                let symbol = p.nodes[binding].symbol;
                if !(symbol >= 0 && (l.sym_flags[symbol] & SF_SCALAR_LOCAL) != 0) {
                    let cell = life_cell(p, l, symbol);
                    if cell >= 0 {
                        var places = source.place; if life_is_ref(p, source.type_id) { places = source.refs; }
                        var source_type: i64 = source.type_id;
                        if source_type >= 0 && p.types[source_type].kind == TY_REF { source_type = p.types[source_type].element; }
                        var storage = p.symbols[symbol].type_id;
                        if index == 0 && source_type >= 0 && (p.types[source_type].kind == TY_ARRAY || p.types[source_type].kind == TY_SLICE) && p.types[source_type].element >= 0 && p.types[p.types[source_type].element].kind == TY_REF { storage = p.types[source_type].element; }
                        var value = life_load(p, l, storage, places, true); value.type_id = p.symbols[symbol].type_id as i32;
                        if source_type >= 0 && p.symbols[symbol].type_id >= 0 && p.types[p.symbols[symbol].type_id].kind == TY_REF {
                            let element = p.types[source_type].element;
                            if !life_is_ref(p, element) || p.types[p.symbols[symbol].type_id].element == element {
                                if p.types[source_type].kind == TY_SLICE { value.refs = places as i32; }
                                else if p.types[source_type].kind == TY_ARRAY && p.types[source_type].array_kind == A_GROW { value.refs = life_grow_only_interior(l, places) as i32; }
                                else { value.refs = life_interior(l, places) as i32; }
                            }
                        }
                        if index == 0 { life_copy(p, l, n.left, p.symbols[symbol].type_id); }
                        if index == 0 { life_store(p, l, binding, life_root_set(l, l.cells[cell].root), value, true); }
                        l.cells[cell].initialized = true;
                        life_set_live(l, cell, true);
                    }
                }
                binding = p.nodes[binding].next; index += 1;
            }
        }
    }
    if !l.discovery {
        var index = life_next_holder(l, -1);
        while index >= 0 {
            let cell: const LifeCell& = l.cells[index];
            if life_visible(l, index) && !life_in_scope(l, p.symbols[cell.symbol].scope, n.scope) {
                life_set_live_refs(l, index, cell.refs); life_set_live_contents(l, cell.root, l.roots[cell.root].contents);
            }
            index = life_next_holder(l, index);
        }
        // The island's class roots are caller storage outside the loop.
        if l.island > 0 {
            let first = l.frames[l.island].classes;
            for root in first..first + l.frames[l.island].class_count { life_set_live_contents(l, root, l.roots[root].contents); }
            var typed = l.frames[l.island].typed_first;
            while typed >= 0 { life_set_live_contents(l, typed, l.roots[typed].contents); typed = l.roots[typed].class_next; }
        }
    } else {
        var index = life_next_holder(l, -1);
        while index >= 0 {
            let cell: const LifeCell& = l.cells[index];
            if life_visible(l, index) && !life_in_scope(l, p.symbols[cell.symbol].scope, n.scope) && l.roots[cell.root].frame > 0 {
                l.roots[cell.root].live_contents = l.roots[cell.root].contents;
            }
            index = life_next_holder(l, index);
        }
    }
    let futures = l.future_count;
    if !l.discovery && (n.right < 0 || (l.node_flags[n.right] & NF_MAY_SHRINK) != 0) {
        life_push_future(l, n.right, n.scope); life_push_future(l, n.left, n.scope);
    }
    let target_mark = l.defer_targets.len;
    l.defer_targets.push(LifeDeferTarget { node: node as i32, defer_mark: l.defers.len as i32 });
    life_eval_void(p, l, n.right); l.future_count = futures;
    l.defer_targets.resize(target_mark);
    if (l.node_flags[node] & NF_HAS_EXIT) != 0 {
        let exit = life_find_exit(l, node);
        if exit >= 0 { out = life_merge(l, out, l.exits[exit].value); }
    }
    if n.scope >= 0 && l.scope_has_cell[n.scope] != 0 { life_leave_scope(p, l, n.scope); }
    if !l.discovery { life_pop_holds(l, held); }
    l.scope = saved;
    if !l.discovery && (out.refs != 0 || out.contents != 0) { life_branch(p, l, node, out, life_depth(l, saved)); }
    if out.type_id >= 0 && out.type_id != TYPE_VOID { life_construct_value(p, l, node, out, receiving); }
    return;
}

recursive fn life_eval_break(p: Program&, l: Lifetimes&, n: const Node&, destination: i64, selected_result: i64) {
    let held = l.hold_count;
    if n.left >= 0 {
        var receiving = destination; var projected = selected_result;
        let before = life_find_exit(l, n.symbol);
        if before >= 0 { receiving = l.exits[before].destination; projected = l.exits[before].selected_result; }
        let value = life_eval(p, l, n.left, receiving, projected);
        let index = life_find_exit(l, n.symbol);
        if index >= 0 {
            let merged = life_merge(l, l.exits[index].value, value);
            l.exits[index].value = merged;
        } else { life_add_exit(l, n.symbol, value); }
        if !l.discovery { life_hold(l, value, n.left); }
    }
    if n.symbol >= 0 && l.defers.len > l.defer_floor {
        let target_mark = life_defer_target_mark(l, n.symbol);
        if target_mark >= 0 { life_run_defers(p, l, target_mark, false, l.frame, p.nodes[n.symbol].scope); }
    }
    if !l.discovery { life_pop_holds(l, held); }
}

recursive fn life_eval_binary(p: Program&, l: Lifetimes&, n: const Node&) {
    let left_inert = n.left < 0 || (l.node_flags[n.left] & NF_INERT) != 0;
    let right_inert = n.right < 0 || (l.node_flags[n.right] & NF_INERT) != 0;
    if left_inert && right_inert { return; }
    if right_inert { life_eval_void(p, l, n.left); return; }
    if l.discovery {
        if !left_inert { life_eval_void(p, l, n.left); }
        life_eval_void(p, l, n.right);
        return;
    }
    let held = l.hold_count;
    if !left_inert {
        var value = life_eval(p, l, n.left); var ty: i64 = value.type_id;
        if ty >= 0 && p.types[ty].kind == TY_REF { value.place = value.refs; ty = p.types[ty].element; }
        if n.kind == N_BINARY && n.integer >= T_EQ && n.integer <= T_GTEQ && ty >= 0 && p.types[ty].kind == TY_ARRAY { life_hold(l, value, n.left, 3); }
        else { life_hold(l, value, n.left); }
    }
    life_eval_void(p, l, n.right); life_pop_holds(l, held);
}

// m: for a class-keyed frame, how the call reads its class roots; an effect
// that names one is replayed as the call's own (life_map_set). call: the
// call's node, where a store that the arguments' depths forbid is reported.
fn life_replay(p: Program&, l: Lifetimes&, frame: i64, summary: bool = false, m: LifeMap = LifeMap {}, call: i64 = -1) {
    if l.watch_stores && summary {
        let context = l.frames[l.frame].context;
        if l.frames[frame].store_read_pass != l.pass {
            l.frames[frame].store_read_pass = l.pass; l.frames[frame].store_reader = context;
        } else if l.frames[frame].store_reader != context {
            // Several chains consumed the old summary. Use an ordinary pass
            // if it grows, keeping subscription storage bounded per frame.
            l.frames[frame].store_reader = -1;
        }
    }
    var at = l.frames[frame].first_effect; if summary { at = l.frames[frame].first_summary; }
    // A discovery replay only offers effects and joins into contents and
    // references, which only grow: an entry replayed into this activation
    // before, unchanged since, has nothing left to add (LifeSummary.replayed).
    // A mapped entry depends on its call as well, and is replayed each time.
    let memo = summary && l.discovery && l.frame > 0 && l.activations < 1073741824;
    let activation = l.frames[l.frame].activation; let replay_epoch = l.recursion_epoch;
    let into = activation as i32; let epoch = replay_epoch as i32;
    let plain = memo && m.count == 0;
    // A completed replay records that this chain received every replayable
    // leaf. Until one changes, only the other entries need to run again.
    let version = l.frames[frame].replay_version; var chain: i64 = -1; if plain && version >= 4 { chain = life_chain_key(l, frame, l.recursion_epoch); }
    var covered: i64 = -1; if chain >= 0 { covered = life_chain_replayed(l, chain); }
    let others = covered == version;
    // In validation a construct read does two things: it is recorded up the
    // chain, which the activation's stamp on its leaf says has been done,
    // and it is checked against the values under construction, of which
    // there are none here most of the time. The same holds for array growths
    // when no construction or replacement hold is active.
    let val_stamp = !l.discovery && m.count == 0 && l.class_frames == 0 && l.frame > 0 && l.activations < 1073741824;
    let quick = val_stamp && l.construct_holds == 0;
    let quick_grow = val_stamp && l.build_holds == 0;
    if others { at = l.frames[frame].first_other; }
    var complete = chain >= 0 && !others && !(l.omit_construct_reads && l.nodes_prepared && !l.full_reads &&
        l.frames[frame].function_node >= 0 && (l.hold_flags[l.frames[frame].function_node] & FH_CONSTRUCT_READ) != 0);
    let skip_grow = l.build_holds == 0 && l.nodes_prepared && !l.full_reads &&
        (l.frame <= 0 || l.frames[l.frame].function_node < 0 || (l.hold_flags[l.frames[l.frame].function_node] & FH_BUILD_HOLD) == 0);
    let skip_replace = l.format_holds == 0 && l.nodes_prepared && !l.full_reads &&
        (l.frame <= 0 || l.frames[l.frame].function_node < 0 || (l.hold_flags[l.frames[l.frame].function_node] & FH_FORMAT_RAW) == 0);
    // While summaries hold their construct reads by leaf, the list is the
    // other entries with each read after the one it names
    // (LifeReadEntry.before): entries are numbered as they are added, so a
    // read comes before the first other entry with a larger number.
    let direct = plain && l.types_frozen;
    // Replaying an effect keeps the caller's activation, recursive frames and chain.
    var stamp_chain: i64 = -1; if l.class_frames == 0 { stamp_chain = l.frames[l.frame].chain; }
    var prior_places: i64 = -1; var prior_reach = LifeFar { far: 0, home: 0 };
    var read: i64 = -1; if summary && l.compact && !others && !l.omit_construct_reads { read = l.frames[frame].first_read; }
    var passed: i64 = -1; var open = false;
    loop {
        while read >= 0 && (at < 0 || (l.summary_reads[read].before as i64) < at) {
            let entry = read; let item: const LifeReadEntry& = l.summary_reads[entry];
            read = item.next as i64;
            // This chain already received this leaf, even if another read changed.
            if item.changed <= covered { continue; }
            let leaf = item.leaf as i64;
            if (memo || quick) && life_leaf_offered_in(l, leaf, activation, replay_epoch, stamp_chain) { continue; }
            if memo { l.offer_count = 0; l.offer_recursive = false; }
            if direct {
                // A compact entry already passed the construct-read type check.
                // Merging keeps its site, type and element-array identity.
                if l.reading_place == 0 {
                    let value: const LifeValue& = l.leaves[leaf].value;
                    var places = value.place; if life_tf_is_ref(p, l, value.type_id) { places = value.refs; }
                    if prior_places != places { prior_places = places; prior_reach = life_effect_far(l, places); }
                    l.offer_count += 1;
                    var far = prior_reach.far;
                    if far > 0 || prior_reach.cyclic {
                        far = life_read_reach(l, leaf, places, l.summary_reads[entry].key, prior_reach);
                    }
                    if !l.offer_recursive { life_leaf_stamp(l, leaf, far, places); }
                }
            } else {
                var known: i64 = -1; if memo || quick { known = leaf; }
                let node = l.leaves[leaf].node; let value = l.leaves[leaf].value;
                life_construct_read(p, l, node, value, known);
            }
            if complete && !life_leaf_offered_in(l, leaf, activation, replay_epoch, stamp_chain) { complete = false; }
        }
        // A replay of a frame of the chain can add to the list it is going
        // through. The list ends at the entry that was its last when the
        // replay came to it; an entry with reads after it was not the last,
        // so what was added behind them follows.
        if at < 0 && passed >= 0 && open { at = l.effects[passed].next; open = false; }
        if at < 0 { break; }
        passed = at; open = read >= 0;
        if plain {
            let s: const LifeSummary& = l.summaries[at];
            if s.replayed == into && s.replayed_epoch == epoch {
                if complete && life_replayable_leaf(l, s.kind as i64) && (s.leaf < 0 || !life_leaf_offered_in(l, s.leaf as i64, activation, replay_epoch, stamp_chain)) { complete = false; }
                at = s.after as i64; if others { at = s.other as i64; }
                continue;
            }
            if life_replayable_leaf(l, s.kind as i64) && s.leaf >= 0 && life_leaf_offered_in(l, s.leaf as i64, activation, replay_epoch, stamp_chain) {
                at = s.after as i64; if others { at = s.other as i64; } continue;
            }
        }
        if quick || quick_grow {
            let s: const LifeSummary& = l.summaries[at];
            if (quick && s.kind == 3 || quick_grow && s.kind == 2) && s.leaf >= 0 && life_leaf_offered_in(l, s.leaf as i64, activation, replay_epoch, stamp_chain) { at = s.after as i64; continue; }
        }
        var next: i64 = l.effects[at].next; if others { next = l.summaries[at].other as i64; }
        if l.effects[at].kind == 0 { at = next; continue; }
        var leaf: i64 = -1;
        if m.count == 0 {
            let e_kind = l.effects[at].kind;
            if quick && e_kind == 3 && l.reading_place == 0 || quick_grow && e_kind == 2 {
                leaf = l.summaries[at].leaf as i64; if leaf < 0 { leaf = life_leaf(l, e_kind, l.effects[at].node, l.effects[at].value); l.summaries[at].leaf = leaf as i32; }
                if life_leaf_offered_in(l, leaf, activation, replay_epoch, stamp_chain) { at = next; continue; }
            }
            if memo {
                let s: const LifeSummary& = l.summaries[at];
                if s.replayed == into && s.replayed_epoch == epoch { at = next; continue; }
                if life_replayable_leaf(l, e_kind) {
                    leaf = s.leaf as i64; if leaf < 0 { leaf = life_leaf(l, e_kind, l.effects[at].node, l.effects[at].value); l.summaries[at].leaf = leaf as i32; }
                    if life_leaf_offered_in(l, leaf, activation, replay_epoch, stamp_chain) { at = next; continue; }
                }
                l.offer_count = 0; l.offer_recursive = false;
            }
            if e_kind == 4 && l.effects[at].field >= -1 {
                let e_places = l.effects[at].places; let e_contents = l.effects[at].value.contents; let e_field = l.effects[at].field; let e_type = l.effects[at].value.type_id as i64;
                var ai = l.sets[e_places].first;
                while ai >= 0 {
                    let alt = l.alts[ai];
                    if alt.root == 0 && l.class_frames > 0 { ai = alt.next; continue; }
                    var reached: i64 = -1; if !alt.byteview { reached = alt.target_type as i64; if reached < 0 { reached = e_type; } }
                    let slice_slot = e_field == LIFE_STORE_SLICE_SLOT && alt.exact && alt.component < 0;
                    life_add_contents(p, l, alt.root, e_contents, false, reached, slice_slot && l.roots[alt.root].class_frame >= 0);
                    ai = alt.next;
                }
                if memo && l.offer_count > 0 && !l.offer_recursive { l.summaries[at].replayed = into; l.summaries[at].replayed_epoch = epoch; }
                at = next; continue;
            }
        }
        var effect = l.effects[at]; var mapped = false;
        if effect.kind == 3 && (l.omit_construct_reads || l.reading_place > 0) { at = next; continue; }
        if effect.kind == 2 && skip_grow { at = next; continue; }
        if effect.kind == 8 && skip_replace { at = next; continue; }
        if l.discovery && l.class_frames > 0 && l.island == 0 && life_nearest_recursive(l, l.frame) == 0 &&
           (effect.kind == 1 || effect.kind == 2 || effect.kind == 3 || effect.kind == 8) { at = next; continue; }
        if m.count > 0 && (quick && effect.kind == 3 && l.reading_place == 0 || quick_grow && effect.kind == 2) {
            leaf = l.summaries[at].leaf as i64; if leaf < 0 { leaf = life_leaf(l, effect.kind, effect.node, effect.value); l.summaries[at].leaf = leaf as i32; }
            if life_leaf_offered_in(l, leaf, activation, replay_epoch, stamp_chain) { at = next; continue; }
        }
        if m.count > 0 && effect.kind == 4 && effect.field == -1 {
            // A store into a class root of what came out of the same
            // argument's storage moves references about within what that
            // argument reaches: a permutation, which stores nothing a call
            // could place. Upstream bounds everything an argument reaches by
            // the one class and records no store of a value read out of its
            // own destination. Mapped pair by pair, every root the argument
            // holds came to hold every other, and itself.
            effect.value.contents = life_unpermuted(l, effect.places, effect.value.contents) as i32;
            if effect.value.contents == 0 { at = next; continue; }
        }
        if m.count > 0 {
            var stored = 0; if effect.kind == 4 { stored = 1; }
            if effect.kind == 4 && effect.field >= -1 && effect.value.type_id >= 0 { effect.places = life_reached_places(l, effect.places, effect.value.type_id) as i32; }
            if (effect.kind == 1 || effect.kind == 2 || effect.kind == 8) && effect.value.type_id >= 0 {
                let same_place = effect.value.place == effect.places;
                effect.places = life_reached_places(l, effect.places, effect.value.type_id) as i32;
                if same_place { effect.value.place = effect.places; }
                else { effect.value.place = life_reached_places(l, effect.value.place, effect.value.type_id) as i32; }
            }
            let places = life_map_set(p, l, effect.places, m, stored); var value = effect.value;
            // (A store of a storage's own has no set to map: life_own_store.)
            if effect.kind == 4 && effect.field <= -2 { value.refs = places as i32; }
            else if effect.kind == 4 {
                if places == 0 { at = next; continue; }
                value.contents = life_map_set(p, l, effect.value.contents, m) as i32;
            } else if (effect.kind == 1 || effect.kind == 2 || effect.kind == 8) && value.place == effect.places &&
                      value.refs == 0 && value.contents == 0 && value.self_pools == 0 && value.relative_roots == 0 && value.tuple < 0 {
                value.place = places as i32;
            } else if effect.kind == 3 && value.contents == 0 && value.self_pools == 0 && value.relative_roots == 0 && value.tuple < 0 {
                if value.place == effect.places { value.place = places as i32; } else { value.place = life_map_set(p, l, value.place, m) as i32; }
                if value.refs == effect.places { value.refs = places as i32; } else { value.refs = life_map_set(p, l, value.refs, m) as i32; }
            } else { value = life_map_value(p, l, effect.value, m); }
            mapped = places != effect.places || value.place != effect.value.place || value.refs != effect.value.refs || value.contents != effect.value.contents ||
                value.self_pools != effect.value.self_pools || value.relative_roots != effect.value.relative_roots || value.tuple != effect.value.tuple;
            if mapped { effect.places = places as i32; effect.value = value; }
        }
        let remembered = memo && !mapped;
        if remembered && m.count > 0 {
            let s: const LifeSummary& = l.summaries[at];
            if s.replayed == into && s.replayed_epoch == epoch { at = next; continue; }
            if life_replayable_leaf(l, effect.kind) {
                leaf = s.leaf as i64; if leaf < 0 { leaf = life_leaf(l, effect.kind, effect.node, effect.value); l.summaries[at].leaf = leaf as i32; }
                if life_leaf_offered_in(l, leaf, activation, replay_epoch, stamp_chain) { at = next; continue; }
            }
            l.offer_count = 0; l.offer_recursive = false;
        }
        // Concrete discovery records these normalized array operations. The
        // validation pass below still checks holds and live references in order.
        if remembered && leaf >= 0 && effect.kind != 3 {
            let eff = LifeEffect { kind: effect.kind, node: effect.node, value: effect.value, places: effect.value.place };
            life_offer_once(p, l, eff, leaf);
        } else if effect.kind == 1 { life_shrink(p, l, effect.node, effect.value); }
        else if effect.kind == 2 { life_grow(p, l, effect.node, effect.value, leaf); }
        else if effect.kind == 3 { life_construct_read(p, l, effect.node, effect.value, leaf); }
        else if effect.kind == 8 { life_replace(p, l, effect.node, effect.value); }
        else if effect.kind == 9 { life_relative_store(p, l, effect.node, effect.places, effect.value); life_effect(p, l, effect); }
        else if effect.kind == 4 && effect.field <= -2 {
            var ai = l.sets[effect.places].first;
            while ai >= 0 { let alt = l.alts[ai]; ai = alt.next; if alt.root != 0 { life_own_store(p, l, alt.root as i64, effect.field, effect.value.type_id); } }
        } else if effect.kind == 4 {
            var ai = l.sets[effect.places].first;
            while ai >= 0 {
                let alt = l.alts[ai];
                if alt.root == 0 && l.class_frames > 0 { ai = alt.next; continue; }
                var refused = false; var landing: i64 = effect.value.contents;
                if mapped {
                    // Of what is stored, this storage takes what its type
                    // holds a reference to.
                    landing = life_referable(p, l, landing, life_place_holds(p, l, alt));
                    if landing == 0 { ai = alt.next; continue; }
                    // The body's check stood for the classes' ranks; where the
                    // store lands in this call, each stored root must outlive it.
                    var si = l.sets[landing].first;
                    while si >= 0 {
                        let source = l.alts[si]; si = source.next; let owner = l.roots[source.root].class_frame;
                        // What a class of the island being evaluated holds, or
                        // something only known to outlive one, is judged where
                        // that island's calls land it in turn.
                        if owner >= 0 && (l.roots[source.root].class_index >= l.frames[owner].class_base || !source.exact) { continue; }
                        if l.roots[source.root].depth > l.roots[alt.root].depth { life_scope_error(p, l, call, 1); refused = true; }
                    }
                }
                // A refused store is reported here, once: it does not land,
                // and so is not judged again at every call above this one.
                var reached: i64 = -1; if !alt.byteview { reached = alt.target_type as i64; if !mapped && reached < 0 { reached = effect.value.type_id as i64; } }
                if !refused {
                    if !alt.exact && l.roots[alt.root].class_frame < 0 { l.unknown_stores = true; }
                    let slice_slot = effect.field == LIFE_STORE_SLICE_SLOT && alt.exact && alt.component < 0;
                    let owner: const LifeRoot& = l.roots[alt.root];
                    if mapped && slice_slot && owner.symbol >= 0 && owner.type_id >= 0 && p.types[owner.type_id].kind == TY_SLICE {
                        // Select the cell of this particular activation.
                        var cell = l.symbol_cells[owner.symbol] as i64;
                        while cell >= 0 && l.cells[cell].root != alt.root { cell = l.cells[cell].next_symbol; }
                        if cell >= 0 {
                            let bv = LifeValue { type_id: owner.type_id as i32, refs: landing as i32 };
                            life_bind(p, l, call, cell, bv, landing);
                        }
                    }
                    life_add_contents(p, l, alt.root, landing, false, reached, slice_slot && owner.class_frame >= 0);
                }
                ai = alt.next;
            }
        } else if (effect.kind == 6 || effect.kind == 7) && mapped && (l.conditional != 0 || l.sets[effect.places].count != 1 || !l.alts[l.sets[effect.places].first].exact) {
            // A kill holds only where the class is one exactly named root.
        } else if effect.kind == 6 || effect.kind == 7 {
            var kill_places = LifeBuild {}; var keep_kill = false;
            var ki = l.sets[effect.places].first;
            while ki >= 0 {
                let ka = l.alts[ki]; ki = ka.next; let kr = ka.root as i64;
                if kr != 0 && !l.roots[kr].class_empty && (effect.kind != 6 || life_kill_matches_root(p, l, kr, effect.value.type_id as i64)) &&
                   (l.roots[kr].class_frame >= 0 || l.roots[kr].type_id < 0 || life_holds(p, l.roots[kr].type_id)) {
                    keep_kill = true;
                    life_build_add_alt(l, kill_places, LifeAlt { root: kr as i32 });
                }
            }
            let kp = life_build_end(l, kill_places);
            if keep_kill && kp != 0 {
                effect.places = kp as i32;
                life_effect(p, l, effect);
                var ai = l.sets[kp].first;
                while ai >= 0 {
                    let alt = l.alts[ai];
                    if effect.kind == 6 { life_set_live_contents(l, alt.root, 0); }
                    else { life_kill_field(l, alt.root, effect.field); }
                    ai = alt.next;
                }
            }
        } else {
            life_effect(p, l, effect);
            if effect.kind == 5 {
                var kept: i64 = effect.value.refs;
                if l.class_frames > 0 {
                    if kept != 0 && l.cell_keys[effect.cell].global {
                        kept = life_lasting(l, kept);
                        if life_has_class(l, kept) { if l.island > 0 { kept = life_keep_outside(l, kept); } else { kept = life_strip(l, kept); } }
                    }
                    let joined = life_join(l, l.cells[effect.cell].refs, kept);
                    if !life_equal(l, joined, l.cells[effect.cell].refs) { life_set_refs(l, effect.cell, joined); l.revision += 1; }
                }
                life_set_live_refs(l, effect.cell, life_join(l, l.cells[effect.cell].live_refs, kept));
            }
            else {
                var ai = l.sets[effect.places].first;
                while ai >= 0 {
                    let alt = l.alts[ai];
                    if effect.kind == 6 { life_set_live_contents(l, alt.root, 0); }
                    else if effect.kind == 7 { life_kill_field(l, alt.root, effect.field); }
                    ai = alt.next;
                }
            }
        }
        if remembered && l.offer_count > 0 && !l.offer_recursive { l.summaries[at].replayed = into; l.summaries[at].replayed_epoch = epoch; }
        if complete && life_replayable_leaf(l, effect.kind) && (leaf < 0 || !life_leaf_offered_in(l, leaf, activation, replay_epoch, stamp_chain)) { complete = false; }
        at = next;
    }
    if complete && l.frames[frame].replay_version == version { life_chain_replay(l, chain, version); }
}

// Persist the final root proof by Symbol ID so optimizer clones can carry it
// without retaining the analyzer's context arenas.
fn life_export_provenance(p: Program&, l: Lifetimes&) {
    for index in 0..p.symbols.len {
        let symbol: const Symbol& = p.symbols[index];
        if (symbol.flags & (S_PARAMETER | S_FUNCTION | S_BUILTIN | S_TYPE)) != 0 { continue; }
        if (symbol.flags & S_GLOBAL) != 0 {
            var static = (symbol.flags & S_MUTABLE) == 0; var ci = l.symbol_cells[index] as i64;
            if ci < 0 { static = false; }
            while ci >= 0 {
                let cell: const LifeCell& = l.cells[ci]; if !cell.initialized { static = false; }
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
        var proof = -2; var known = true; var ci = l.symbol_cells[index] as i64;
        if ci < 0 { known = false; }
        while ci >= 0 {
            let cell: const LifeCell& = l.cells[ci];
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

fn life_type_may_need_named_result(p: Program&, ty: i64) -> bool {
    if ty < 0 { return false; }
    let t: const Type& = p.types[ty];
    if t.kind == TY_ARRAY { return t.array_kind != A_FIXED || life_size_class(p, ty) > 0 || life_relative_storage(p, ty, false); }
    if t.kind == TY_STRUCT || t.kind == TY_ENUM { return life_size_class(p, ty) > 0 || life_relative_storage(p, ty, false); }
    if t.kind == TY_REF { return t.length_storage >= 0; }
    return false;
}
fn life_may_reach_local_with(p: Program&, node: i64, candidate: i64, work: i64[>..]&) -> bool {
    if (p.symbols[candidate].flags & S_CAPTURE) != 0 { return true; }
    work.clear(); work.push(node); var at = 0;
    while at < work.len {
        let current = work[at]; at += 1; if current < 0 { continue; }
        let n: const Node& = p.nodes[current];
        if n.kind == N_NAME && n.symbol >= 0 {
            if n.symbol == candidate { return true; }
            let symbol: const Symbol& = p.symbols[n.symbol];
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
        if n.left >= 0 { work.push(n.left); }
        if n.right >= 0 { work.push(n.right); }
        if n.third >= 0 { work.push(n.third); }
    }
    return false;
}
fn life_may_reach_local(p: Program&, node: i64, candidate: i64) -> bool {
    var work: i64[>..] = [];
    return life_may_reach_local_with(p, node, candidate, work);
}
fn life_named_results_into(p: Program&, function_node: i64, inline_body: bool, symbols: i64[>..]&, ordinals: i64[>..]&,
                           locals: i64[>..]&, returns: i64[>..]&, work: i64[>..]&, others: i64[>..]&, bound: i64[>..]&, reach_work: i64[>..]&) {
    let fn_node: const Node& = p.nodes[function_node];
    if fn_node.type_id < 0 { return; }
    var body_node = fn_node.right; var result_type = p.types[fn_node.type_id].element;
    if inline_body { body_node = function_node; result_type = fn_node.type_id; }
    if body_node < 0 || p.nodes[body_node].kind != N_BLOCK { return; }
    if result_type < 0 || p.types[result_type].kind == TY_VOID { return; }
    var results = 1; var any_needed = false;
    if p.types[result_type].kind == TY_TUPLE {
        results = 0; var item = p.types[result_type].first;
        while item >= 0 {
            if !any_needed && life_type_may_need_named_result(p, p.nodes[item].type_id) { any_needed = true; }
            results += 1; item = p.nodes[item].next;
        }
    } else {
        any_needed = life_type_may_need_named_result(p, result_type);
    }
    if !any_needed { return; }
    locals.clear(); var statement = p.nodes[body_node].first;
    while statement >= 0 {
        let n: const Node& = p.nodes[statement];
        if n.kind == N_VARIABLE && !(n.origin >= 0 && p.nodes[n.origin].kind == N_PARAM) {
            if n.first < 0 && n.symbol >= 0 { locals.push(n.symbol); }
            else if n.first >= 0 && p.nodes[n.first].next < 0 && p.nodes[n.first].symbol >= 0 { locals.push(p.nodes[n.first].symbol); }
        }
        statement = n.next;
    }
    if locals.len == 0 { return; }
    returns.clear(); work.clear(); work.push(body_node); var at = 0;
    while at < work.len {
        let current = work[at]; at += 1; let n: const Node& = p.nodes[current];
        if n.kind == N_FUNCTION || n.kind == N_STRUCT || n.kind == N_ENUM || n.kind == N_ALIAS || n.kind == N_IMPORT { continue; }
        if n.kind == N_FUNCTION_VALUE { if n.right >= 0 { work.push(n.right); } continue; }
        if !inline_body && n.kind == N_RETURN && n.symbol == fn_node.symbol || inline_body && n.kind == N_BREAK && n.symbol == function_node { returns.push(current); }
        var child = n.first; while child >= 0 { work.push(child); child = p.nodes[child].next; }
        if n.left >= 0 { work.push(n.left); }
        if n.right >= 0 { work.push(n.right); }
        if n.third >= 0 { work.push(n.third); }
    }
    bound.clear();
    var tuple_item = -1;
    if p.types[result_type].kind == TY_TUPLE { tuple_item = p.types[result_type].first; }
    let body_last = p.nodes[body_node].last;
    for ordinal in 0..results {
        var ord_ty = result_type;
        if tuple_item >= 0 { ord_ty = p.nodes[tuple_item].type_id; tuple_item = p.nodes[tuple_item].next; }
        if !life_type_may_need_named_result(p, ord_ty) { continue; }
        var candidate = -1; var blocked = false; others.clear();
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
        if results == 1 && body_last >= 0 && (p.nodes[body_last].flags & F_TAIL) != 0 && p.nodes[body_last].type_id != TYPE_VOID {
            let tail: const Node& = p.nodes[body_last]; var local = -1;
            if tail.kind == N_NAME { for symbol in locals { if symbol == tail.symbol { local = symbol; } } }
            if local < 0 { others.push(body_last); }
            else if candidate < 0 { candidate = local; }
            else if candidate != local { blocked = true; }
        }
        if candidate < 0 || blocked { continue; }
        for symbol in bound { if symbol == candidate { blocked = true; } }
        for value in others { if life_may_reach_local_with(p, value, candidate, reach_work) { blocked = true; } }
        if blocked { continue; }
        symbols.push(candidate); ordinals.push(ordinal); bound.push(candidate);
    }
}
fn life_refresh_named_results_for(p: Program&, inlined_blocks: const i64[:]) {
    var symbols: i64[>..] = []; var ordinals: i64[>..] = [];
    var locals: i64[>..] = []; var returns: i64[>..] = [];
    var work: i64[>..] = []; var others: i64[>..] = [];
    var bound: i64[>..] = []; var reach_work: i64[>..] = [];
    let sym_count = p.symbols.len;
    for s_id in 0..sym_count {
        let sym: const Symbol& = p.symbols[s_id];
        if (sym.flags & S_FUNCTION) == 0 || sym.node < 0 { continue; }
        let function_node = sym.node;
        let fn_n: const Node& = p.nodes[function_node];
        if fn_n.kind != N_FUNCTION || fn_n.symbol != s_id || fn_n.type_id < 0 || fn_n.right < 0 || (fn_n.flags & F_CHECKED) == 0 { continue; }
        p.nodes[function_node].named_results = -1;
        symbols.clear(); ordinals.clear();
        life_named_results_into(p, function_node, false, symbols, ordinals, locals, returns, work, others, bound, reach_work);
        for candidate, index in symbols {
            let binding = p.nodes.len;
            p.nodes.push(Node { kind: N_BINDING, next: p.nodes[function_node].named_results, symbol: candidate, integer: ordinals[index] });
            p.nodes[function_node].named_results = binding;
        }
    }
    for bi in 0..inlined_blocks.len {
        let function_node = inlined_blocks[bi];
        if function_node < 0 || function_node >= p.nodes.len { continue; }
        let fn_n: const Node& = p.nodes[function_node];
        if fn_n.kind != N_BLOCK || fn_n.type_id < 0 || (fn_n.flags & F_EARLY) == 0 { continue; }
        let origin = fn_n.origin;
        if origin < 0 || (p.nodes[origin].kind != N_FUNCTION && p.nodes[origin].kind != N_FUNCTION_VALUE) { continue; }
        p.nodes[function_node].named_results = -1;
        symbols.clear(); ordinals.clear();
        life_named_results_into(p, function_node, true, symbols, ordinals, locals, returns, work, others, bound, reach_work);
        for candidate, index in symbols {
            let binding = p.nodes.len;
            p.nodes.push(Node { kind: N_BINDING, next: p.nodes[function_node].named_results, symbol: candidate, integer: ordinals[index] });
            p.nodes[function_node].named_results = binding;
        }
    }
}
fn life_refresh_named_results(p: Program&) {
    let node_count = p.nodes.len;
    var symbols: i64[>..] = []; var ordinals: i64[>..] = [];
    var locals: i64[>..] = []; var returns: i64[>..] = [];
    var work: i64[>..] = []; var others: i64[>..] = [];
    var bound: i64[>..] = []; var reach_work: i64[>..] = [];
    for function_node in 0..node_count {
        let kind = p.nodes[function_node].kind;
        if kind != N_FUNCTION && kind != N_BLOCK { continue; }
        let flags = p.nodes[function_node].flags;
        let type_id = p.nodes[function_node].type_id;
        if type_id < 0 { continue; }
        var inline_body = false;
        if kind == N_BLOCK {
            if (flags & F_EARLY) == 0 { continue; }
            let origin = p.nodes[function_node].origin;
            if origin < 0 || (p.nodes[origin].kind != N_FUNCTION && p.nodes[origin].kind != N_FUNCTION_VALUE) { continue; }
            inline_body = true;
        } else {
            if p.nodes[function_node].right < 0 || (flags & F_CHECKED) == 0 { continue; }
        }
        p.nodes[function_node].named_results = -1;
        symbols.clear(); ordinals.clear();
        life_named_results_into(p, function_node, inline_body, symbols, ordinals, locals, returns, work, others, bound, reach_work);
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
    var locals: i64[>..] = []; var returns: i64[>..] = [];
    var work: i64[>..] = []; var others: i64[>..] = [];
    var bound: i64[>..] = []; var reach_work: i64[>..] = [];
    life_named_results_into(p, function_node, inline_body, symbols, ordinals, locals, returns, work, others, bound, reach_work);
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
    var items = LifeItemList {}; var formal = p.nodes[function_node].first;
    while formal >= 0 {
        let type_id = p.nodes[formal].type_id; var value = LifeValue { type_id: type_id as i32 };
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
            if named != 0 { if life_is_ref(p, type_id) { value.refs = named as i32; } else { value.contents = named as i32; } }
            else {
                let storage = life_standalone_type(p, type_id); root = l.roots.len;
                l.roots.push(LifeRoot { frame: 0, node: formal, type_id: storage });
                let contents = life_root_set(l, root); life_set_contents(l, root, contents); life_set_live_contents(l, root, contents);
                if life_is_ref(p, type_id) { value.refs = life_root_set(l, root) as i32; }
                else { value.contents = life_root_set(l, root) as i32; }
            }
        }
        life_append(l, items, value); formal = p.nodes[formal].next;
    }
    return items.first;
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

// Only assignment to size-class-2 storage can create a replacement hold.
fn life_has_replacement(p: Program&, l: Lifetimes&) -> bool {
    for index in 0..p.nodes.len {
        let n: const Node& = p.nodes[index];
        if n.kind != N_ASSIGN || n.left < 0 { continue; }
        let target: const Node& = p.nodes[n.left];
        if target.kind != N_NAME && target.kind != N_INDEX && target.kind != N_MEMBER && !(target.kind == N_UNARY && target.integer == T_MUL) { return true; }
        var ty = target.type_id;
        if ty >= 0 && p.types[ty].kind == TY_REF && n.integer != T_DOTASSIGN { ty = p.types[ty].element; }
        if life_cached_size_class(p, l, ty) == 2 { return true; }
    }
    return false;
}
// Stop at an analysis root if a class frame or a dynamic replacement needs
// the earlier read history. A full retry starts with fresh lifetime arenas.
fn life_check_roots(p: Program&, l: Lifetimes&, standalone: const LifeStandalone[:], omit_reads: bool) -> bool {
    for symbol in p.symbols {
        if (symbol.flags & S_GLOBAL) != 0 && symbol.node >= 0 && p.nodes[symbol.node].kind == N_VARIABLE {
            if l.nodes_prepared { l.omit_construct_reads = !l.full_reads && (l.hold_flags[symbol.node] & FH_CONSTRUCT_READ) == 0; }
            life_eval(p, l, symbol.node);
            if l.need_full_reads || omit_reads && !l.omit_construct_reads { return false; }
        }
    }
    if p.entry >= 0 {
        life_function(p, l, p.entry, -1, -1, 0);
        if l.need_full_reads { return false; }
    }
    for root in standalone {
        life_function(p, l, root.function_node, -1, root.arguments, 0);
        if l.need_full_reads { return false; }
    }
    return true;
}
// Sound whole-program fast path: if the entire checked program uses only fixed
// pure value types (scalars, fixed arrays, plain fixed structs), has no globals,
// captures, pools, recursive/thread/export/extern functions, references, slices,
// or non-value builtins, no lifetime error is possible and every local's
// provenance proof is static (-2).
recursive fn life_type_is_pure_value(p: Program&, state: u8[>..]&, id: i64) -> bool {
    if id < 0 || id >= state.len { return false; }
    let s = state[id];
    if s != 0 { return s == 2; }
    state[id] = 1;
    let t: const Type& = p.types[id];
    var ok = false;
    if t.kind == TY_VOID || t.kind == TY_BOOL || t.kind == TY_FLOAT { ok = true; }
    else if t.kind == TY_INT { ok = t.index_type < 0 && t.pool < 0 && t.storage == 0; }
    else if t.kind == TY_ARRAY {
        ok = t.array_kind == A_FIXED && t.length_storage < 0 && t.pool < 0 && t.storage == 0 &&
             life_type_is_pure_value(p, state, t.element);
    } else if t.kind == TY_STRUCT {
        if t.declaration >= 0 && (p.nodes[t.declaration].flags & (F_ROOT | F_VARIABLE_MODE)) == 0 &&
           t.tail < 0 && t.prefix < 0 && t.storage == 0 {
            ok = true;
            var field = t.first;
            while field >= 0 {
                let fn_node: const Node& = p.nodes[field];
                if (fn_node.flags & F_PAD) == 0 && !life_type_is_pure_value(p, state, fn_node.type_id) { ok = false; break; }
                field = fn_node.next;
            }
        }
    }
    state[id] = if ok { 2 } else { 1 };
    return ok;
}
fn life_try_pure_fast_path(p: Program&, pool_references: const i64[:]) -> bool {
    if pool_references.len > 0 { return false; }
    var state: u8[>..] = [];
    state.resize(p.types.len, 0);
    // Quick fail-fast over symbols (bails in <10 iterations on programs with globals/refs/slices).
    let node_count = p.nodes.len;
    for sym in p.symbols {
        let fl = sym.flags;
        if (fl & (S_GLOBAL | S_CAPTURE | S_EXTERN)) != 0 { return false; }
        if (fl & (S_TYPE | S_BUILTIN)) != 0 { continue; }
        if (fl & S_FUNCTION) != 0 {
            if sym.node >= 0 && sym.node < node_count {
                let fn_n: const Node& = p.nodes[sym.node];
                if (fn_n.flags & (F_CHECKED | F_GENERIC)) == F_CHECKED {
                    if sym.owner >= 0 || fn_n.captures >= 0 ||
                       (fn_n.flags & (F_RECURSIVE | F_THREAD | F_EXPORT | F_EXTERN | F_NONLOCAL)) != 0 { return false; }
                    if sym.type_id < 0 || p.types[sym.type_id].kind != TY_FN { return false; }
                    let ft: const Type& = p.types[sym.type_id];
                    if !life_type_is_pure_value(p, state, ft.element) { return false; }
                    var param = ft.first;
                    while param >= 0 {
                        if !life_type_is_pure_value(p, state, p.nodes[param].type_id) { return false; }
                        param = p.nodes[param].next;
                    }
                }
            }
            continue;
        }
        if sym.owner >= 0 && sym.owner < node_count && (p.nodes[sym.owner].flags & (F_CHECKED | F_GENERIC)) == F_CHECKED {
            if !life_type_is_pure_value(p, state, sym.type_id) { return false; }
            if sym.node >= 0 && sym.node < node_count &&
               (p.nodes[sym.node].flags & (F_REUSABLE | F_REUSABLE_SLICES | F_REFERENCE | F_REFERENCE_CONTEXT)) != 0 { return false; }
        }
    }
    let bad_flags = F_REUSABLE | F_REUSABLE_SLICES | F_REFERENCE | F_REFERENCE_CONTEXT | F_NONLOCAL | F_VARIABLE_MODE | F_ROOT | F_ARRAY_JOIN;
    for n in p.nodes {
        if (n.flags & bad_flags) != 0 { return false; }
        let k = n.kind;
        if k == N_DEFER || k == N_SLICE || k == N_FUNCTION_VALUE || k == N_EXTERN || k == N_SELF || k == N_RESULT { return false; }
        if k == N_UNARY && (n.integer == T_BITAND || n.integer == T_MUL) { return false; }
        if k == N_ASSIGN && n.integer == T_DOTASSIGN { return false; }
        if k == N_FUNCTION {
            if (n.flags & (F_CHECKED | F_GENERIC)) == F_CHECKED {
                if n.symbol < 0 || p.symbols[n.symbol].owner >= 0 ||
                   (n.flags & (F_RECURSIVE | F_THREAD | F_EXPORT | F_EXTERN)) != 0 { return false; }
            }
            continue;
        }
        if k == N_CALL {
            if n.symbol < 0 { return false; }
            let cs: const Symbol& = p.symbols[n.symbol];
            if (cs.flags & S_BUILTIN) != 0 {
                if cs.name_token < 0 || !same_bytes(token_text(p, cs.name_token), "print") { return false; }
            }
        }
        if n.type_id >= 0 && p.types[n.type_id].kind != TY_FN && !life_type_is_pure_value(p, state, n.type_id) { return false; }
        if n.coerced_type >= 0 && !life_type_is_pure_value(p, state, n.coerced_type) { return false; }
    }
    for index in 0..p.symbols.len {
        let flags = p.symbols[index].flags;
        if (flags & (S_PARAMETER | S_FUNCTION | S_BUILTIN | S_TYPE)) != 0 { continue; }
        p.symbols[index].provenance = -2;
    }
    return true;
}
fn check_lifetimes(p: Program&, scope_parent: const i64[>..]&, scope_depth: const i64[>..]&, scope_functions: const i64[>..]&, pool_references: const i64[:]) {
    if p.diagnostics.len > 0 { return; }
    if life_try_pure_fast_path(p, pool_references) { return; }
    let nodes = p.nodes.len; let types = p.types.len; let holds = p.type_holds.len;
    let messages = p.messages.len;
    if life_check_attempt(p, scope_parent, scope_depth, scope_functions, pool_references, false) { return; }
    // Standalone parameters append synthetic nodes and types. Discard them and
    // any diagnostics from this attempt before rebuilding full class summaries.
    p.nodes.resize(nodes); p.types.resize(types); p.type_holds.resize(holds);
    p.diagnostics.clear(); p.messages.resize(messages);
    life_check_attempt(p, scope_parent, scope_depth, scope_functions, pool_references, true);
}
// A concrete store summary is consumed only by replay. If the only facts
// that grew reached every caller this round, the next pass would observe
// the settled contents. Merge decisions pass the incoming offer up the
// chain; its owner's accumulated contents reach callers through replay.
// The ordinary revision counter does not count all
// returned tuple components, exits or per-cell binding state. Compare those
// pass-boundary inputs exactly before dispensing with the confirmation pass.
struct LifeStoreWake { summary: i64, context: i64 }
struct LifeRoundFrame { result: LifeValue, parent: i64, destination: i64, context: i64 }
struct LifeRoundCell { initial: i64, live_refs: i64, depth: i64, initialized: bool, committed: bool, growshrink: bool, live: bool }
struct LifeRoundRoot { live_contents: i64, first_kill: i64 }
struct LifeRound { frames: LifeRoundFrame[>..]&, cells: LifeRoundCell[>..]&, roots: LifeRoundRoot[>..]&, exits: LifeExit[>..]& }

// Unmapped store replay joins into the destination root, then offers the
// same contents up the caller chain. A productive root join would have
// added a separate revision and excluded this round. Check every ancestor, including ones
// which could ignore the store. A missing or narrower summary wakes the
// ordinary traversal in its original order.
fn life_store_delivered(l: Lifetimes&, wake: LifeStoreWake) -> bool {
    let e: const LifeEffect& = l.effects[wake.summary];
    if e.value.type_id != -1 || e.cell != -1 || e.node != -1 || l.sets[e.places].count != 1 { return false; }
    let root = l.alts[l.sets[e.places].first].root;
    if life_root_set(l, root) != e.places || !life_subset(l, e.value.contents, l.roots[root].contents) { return false; }
    let base_h = life_summary_base_hash(e, -1);
    let mask = l.summary_slots.len - 1;
    var context = wake.context;
    while context > 0 {
        let frame = l.contexts[context].frame;
        let skey = life_summary_key(frame, base_h);
        let frame32 = frame as i32;
        var slot = skey & mask;
        loop {
            let entry = l.summary_slots[slot];
            if entry.index < 0 { return false; }
            if entry.key == skey && entry.frame == frame32 {
                let at = entry.index as i64;
                let summary: const LifeSummary& = l.summaries[at];
                if summary.kind == 4 && summary.node == -1 && summary.type_id == -1 && summary.field == -1 && summary.cell == -1 && life_equal(l, l.effects[at].places, e.places) {
                    if !life_subset(l, e.value.contents, l.effects[at].value.contents) { return false; }
                    break;
                }
            }
            slot = (slot + 1) & mask;
        }
        context = l.contexts[context].parent;
    }
    return true;
}
fn life_round_cell(c: const LifeCell&) -> LifeRoundCell {
    return LifeRoundCell { initial: c.initial, live_refs: c.live_refs, depth: c.depth, initialized: c.initialized, committed: c.committed, growshrink: c.growshrink, live: c.live };
}
fn life_save_round(l: Lifetimes&, checkpoint: LifeRound&) {
    checkpoint.frames.clear(); checkpoint.cells.clear(); checkpoint.roots.clear(); checkpoint.exits.clear();
    for i in 0..l.frames.len {
        let f: const LifeFrame& = l.frames[i];
        checkpoint.frames.push(LifeRoundFrame { result: f.result, parent: f.parent, destination: f.destination, context: f.context });
    }
    for i in 0..l.cells.len { checkpoint.cells.push(life_round_cell(l.cells[i])); }
    for i in 0..l.roots.len {
        let r: const LifeRoot& = l.roots[i];
        checkpoint.roots.push(LifeRoundRoot { live_contents: r.live_contents, first_kill: r.first_kill });
    }
    for i in 0..l.exits.len { checkpoint.exits.push(l.exits[i]); }
}
recursive fn life_round_value(l: Lifetimes&, a: const LifeValue&, b: const LifeValue&) -> bool {
    if a.readonly != b.readonly { return false; }
    if a.type_id != b.type_id || a.place != b.place || a.refs != b.refs || a.contents != b.contents || a.self_pools != b.self_pools || a.relative_roots != b.relative_roots || a.element_array != b.element_array || a.reached != b.reached { return false; }
    var x = a.tuple; var y = b.tuple;
    while x != y {
        if x < 0 || y < 0 || !life_round_value(l, l.items[x].value, l.items[y].value) { return false; }
        x = l.items[x].next; y = l.items[y].next;
    }
    return true;
}
fn life_round_stable(l: Lifetimes&, checkpoint: const LifeRound&) -> bool {
    if l.frames.len != checkpoint.frames.len || l.cells.len != checkpoint.cells.len || l.roots.len != checkpoint.roots.len || l.exits.len != checkpoint.exits.len { return false; }
    for old, i in checkpoint.frames {
        let f: const LifeFrame& = l.frames[i];
        if f.parent != old.parent || f.destination != old.destination || f.context != old.context || !life_round_value(l, old.result, f.result) { return false; }
    }
    for old, i in checkpoint.cells {
        let c: const LifeCell& = l.cells[i];
        if c.initial != old.initial || c.live_refs != old.live_refs || c.depth != old.depth || c.initialized != old.initialized || c.committed != old.committed || c.growshrink != old.growshrink || c.live != old.live { return false; }
    }
    for old, i in checkpoint.roots {
        if l.roots[i].live_contents != old.live_contents || l.roots[i].first_kill != old.first_kill { return false; }
    }
    for old, i in checkpoint.exits {
        let e: const LifeExit& = l.exits[i];
        if e.destination != old.destination || e.selected_result != old.selected_result || !life_round_value(l, old.value, e.value) { return false; }
    }
    return true;
}

inline fn life_type_plain_ref_or_slice(p: Program&, ty: i64) -> bool {
    if ty < 0 { return false; }
    let t: const Type& = p.types[ty];
    return t.kind == TY_SLICE || t.kind == TY_REF && t.length_storage < 0;
}
inline fn life_type_is_ref(l: Lifetimes&, ty: i64) -> bool {
    return ty >= 0 && ty < l.type_flags.len && (l.type_flags[ty] & TF_L_REF) != 0;
}
inline fn life_type_is_scalar(l: Lifetimes&, ty: i64) -> bool {
    return ty >= 0 && ty < l.type_flags.len && (l.type_flags[ty] & TF_L_SCALAR) != 0;
}
inline fn life_type_void_or_scalar(p: Program&, l: Lifetimes&, ty: i64) -> bool {
    return ty < 0 || p.types[ty].kind == TY_VOID || life_type_is_scalar(l, ty);
}
fn life_queue_place(l: Lifetimes&, work: i64[>..]&, node: i64) {
    if node < 0 || node >= l.node_flags.len { return; }
    if (l.node_flags[node] & NF_NEEDS_PLACE) != 0 { return; }
    l.node_flags[node] |= NF_NEEDS_PLACE;
    work.push(node);
}
fn life_mark_for_seq_subtree(p: Program&, l: Lifetimes&, root: i64, work: i64[>..]&) {
    if root < 0 { return; }
    work.clear(); work.push(root); var at = 0;
    while at < work.len {
        let cur = work[at]; at += 1;
        if cur < 0 || cur >= l.node_flags.len || (l.node_flags[cur] & NF_IN_FOR_SEQ) != 0 { continue; }
        l.node_flags[cur] |= NF_IN_FOR_SEQ;
        let n: const Node& = p.nodes[cur];
        if n.kind == N_FUNCTION || n.kind == N_FUNCTION_VALUE || n.kind == N_STRUCT || n.kind == N_ENUM || n.kind == N_ALIAS || n.kind == N_IMPORT { continue; }
        var child = n.first; while child >= 0 { work.push(child); child = p.nodes[child].next; }
        if n.left >= 0 { work.push(n.left); }
        if n.right >= 0 { work.push(n.right); }
        if n.third >= 0 { work.push(n.third); }
    }
}
inline fn life_queue_hold(l: Lifetimes&, work: i64[>..]&, node: i64, bits: u8) {
    if node < 0 || node >= l.hold_flags.len { return; }
    if (l.hold_flags[node] & bits) == bits { return; }
    l.hold_flags[node] |= bits;
    work.push(node);
}
recursive fn life_analyze_candidate_fn(p: Program&, l: Lifetimes&, fn_id: i64, omit_reads: bool, fn_state: u8[>..]&, any_defer: bool = false) {
    if fn_state[fn_id] != 1 { return; }
    fn_state[fn_id] = 2;
    let body = p.nodes[fn_id].right;
    life_analyze_node(p, l, body, omit_reads, fn_state, false, any_defer);
    var body_inert = (l.node_flags[body] & NF_INERT) != 0;
    let fn_no_cr = omit_reads || (!l.full_reads && (l.hold_flags[fn_id] & FH_CONSTRUCT_READ) == 0);
    if !body_inert && fn_no_cr && p.nodes[body].kind == N_BLOCK {
        let bn: const Node& = p.nodes[body];
        if (bn.flags & F_EARLY) == 0 && (l.node_flags[body] & NF_HAS_EXIT) == 0 &&
           life_type_void_or_scalar(p, l, bn.type_id) &&
           (bn.scope < 0 || bn.scope >= l.scope_has_cell.len || (l.scope_has_cell[bn.scope] & 1) == 0) {
            body_inert = true; var child = bn.first;
            while child >= 0 {
                if (l.node_flags[child] & NF_INERT) == 0 { body_inert = false; break; }
                child = p.nodes[child].next;
            }
        }
    }
    if body_inert { l.node_flags[fn_id] |= NF_FN_INERT; }
    fn_state[fn_id] = 3;
}
recursive fn life_analyze_node(p: Program&, l: Lifetimes&, node: i64, omit_reads: bool, fn_state: u8[>..]&, has_defer: bool = false, any_defer: bool = false) {
    if node < 0 || node >= l.node_flags.len { return; }
    let cur_flags = l.node_flags[node];
    if (cur_flags & NF_ANALYZED) != 0 { return; }
    let needs_place = (cur_flags & NF_NEEDS_PLACE) != 0;
    let no_cr = omit_reads || (!l.full_reads && (l.hold_flags[node] & FH_CONSTRUCT_READ) == 0);
    let n: const Node& = p.nodes[node];
    let kind = n.kind;
    if kind == N_INTEGER || kind == N_FLOAT || kind == N_NULL || kind == N_BOOL || kind == N_EMPTY ||
       (kind == N_CONTINUE && !has_defer) || kind == N_FUNCTION || kind == N_FUNCTION_VALUE || kind == N_IMPORT ||
       kind == N_STRUCT || kind == N_ENUM || kind == N_ALIAS || kind == N_NAMESPACE {
        if !needs_place { l.node_flags[node] = cur_flags | NF_ANALYZED | NF_INERT; }
        else { l.node_flags[node] = cur_flags | NF_ANALYZED; }
        return;
    }
    l.node_flags[node] = cur_flags | NF_ANALYZED;
    if kind == N_CONTINUE {
        l.node_flags[node] = (cur_flags | NF_ANALYZED | NF_MAY_SHRINK) & ~NF_INERT;
        return;
    }
    if kind == N_STRING { return; }
    let in_seq = (cur_flags & NF_IN_FOR_SEQ) != 0;
    var pure_place = false;
    var may_shrink = false;
    var inert = false;
    if kind == N_NAME {
        pure_place = true;
        if n.symbol < 0 || n.symbol >= p.symbols.len || (p.symbols[n.symbol].flags & (S_FUNCTION | S_TYPE | S_BUILTIN)) != 0 {
            inert = true;
        } else if (l.sym_flags[n.symbol] & SF_SCALAR_LOCAL) != 0 {
            inert = !needs_place;
        } else if no_cr && !needs_place && life_type_is_scalar(l, n.type_id) {
            inert = true;
        }
    } else if kind == N_MEMBER || kind == N_INDEX {
        if n.left >= 0 { life_analyze_node(p, l, n.left, omit_reads, fn_state, has_defer, any_defer); if (l.node_flags[n.left] & NF_MAY_SHRINK) != 0 { may_shrink = true; } }
        if n.right >= 0 { life_analyze_node(p, l, n.right, omit_reads, fn_state, has_defer, any_defer); if (l.node_flags[n.right] & NF_MAY_SHRINK) != 0 { may_shrink = true; } }
        if n.third >= 0 { life_analyze_node(p, l, n.third, omit_reads, fn_state, has_defer, any_defer); if (l.node_flags[n.third] & NF_MAY_SHRINK) != 0 { may_shrink = true; } }
        var storage = n.type_id;
        if kind == N_MEMBER && n.symbol >= 0 { storage = p.nodes[n.symbol].type_id; }
        if kind == N_INDEX && n.left >= 0 {
            var arr = p.nodes[n.left].type_id;
            if arr >= 0 && p.types[arr].kind == TY_REF { arr = p.types[arr].element; }
            if arr >= 0 && (p.types[arr].kind == TY_ARRAY || p.types[arr].kind == TY_SLICE) { storage = p.types[arr].element; }
        }
        let no_copy = (storage >= 0 && storage < l.type_flags.len && (l.type_flags[storage] & TF_L_REL) == 0) ||
            (n.left >= 0 && life_storage_path(p, n.left));
        if !in_seq && no_copy && n.left >= 0 && (l.node_flags[n.left] & NF_PURE_PLACE) != 0 &&
           (n.right < 0 || (l.node_flags[n.right] & NF_INERT) != 0) &&
           (n.third < 0 || (l.node_flags[n.third] & NF_INERT) != 0) {
            pure_place = true;
            if no_cr && !needs_place && life_type_is_scalar(l, n.type_id) { inert = true; }
        }
    } else if kind == N_SLICE {
        if n.left >= 0 { life_analyze_node(p, l, n.left, omit_reads, fn_state, has_defer, any_defer); if (l.node_flags[n.left] & NF_MAY_SHRINK) != 0 { may_shrink = true; } }
        if n.right >= 0 { life_analyze_node(p, l, n.right, omit_reads, fn_state, has_defer, any_defer); if (l.node_flags[n.right] & NF_MAY_SHRINK) != 0 { may_shrink = true; } }
        if n.third >= 0 { life_analyze_node(p, l, n.third, omit_reads, fn_state, has_defer, any_defer); if (l.node_flags[n.third] & NF_MAY_SHRINK) != 0 { may_shrink = true; } }
    } else if kind == N_UNARY {
        if n.left >= 0 { life_analyze_node(p, l, n.left, omit_reads, fn_state, has_defer, any_defer); if (l.node_flags[n.left] & NF_MAY_SHRINK) != 0 { may_shrink = true; } }
        if n.integer == T_MUL {
            if !in_seq && n.left >= 0 && (l.node_flags[n.left] & NF_PURE_PLACE) != 0 {
                pure_place = true;
                if no_cr && !needs_place && life_type_is_scalar(l, n.type_id) { inert = true; }
            }
        } else if n.integer != T_BITAND {
            if !needs_place && life_type_is_scalar(l, n.type_id) && (n.left < 0 || (l.node_flags[n.left] & NF_INERT) != 0) {
                inert = true;
            }
        }
    } else if kind == N_CAST {
        if n.left >= 0 { life_analyze_node(p, l, n.left, omit_reads, fn_state, has_defer, any_defer); if (l.node_flags[n.left] & NF_MAY_SHRINK) != 0 { may_shrink = true; } }
        if !needs_place && life_type_is_scalar(l, n.type_id) && (n.left < 0 || (l.node_flags[n.left] & NF_INERT) != 0) {
            inert = true;
        }
    } else if kind == N_BINARY || kind == N_RANGE {
        if n.left >= 0 { life_analyze_node(p, l, n.left, omit_reads, fn_state, has_defer, any_defer); if (l.node_flags[n.left] & NF_MAY_SHRINK) != 0 { may_shrink = true; } }
        if n.right >= 0 { life_analyze_node(p, l, n.right, omit_reads, fn_state, has_defer, any_defer); if (l.node_flags[n.right] & NF_MAY_SHRINK) != 0 { may_shrink = true; } }
        if !needs_place && (n.left < 0 || (l.node_flags[n.left] & NF_INERT) != 0) &&
           (n.right < 0 || (l.node_flags[n.right] & NF_INERT) != 0) {
            inert = true;
        }
    } else if kind == N_EXPR_STMT || kind == N_GUARD {
        if n.left >= 0 { life_analyze_node(p, l, n.left, omit_reads, fn_state, has_defer, any_defer); if (l.node_flags[n.left] & NF_MAY_SHRINK) != 0 { may_shrink = true; } }
        if n.left < 0 || (l.node_flags[n.left] & NF_INERT) != 0 { inert = true; }
    } else if kind == N_DEFER {
        if n.right >= 0 { life_analyze_node(p, l, n.right, omit_reads, fn_state, has_defer, any_defer); if (l.node_flags[n.right] & NF_MAY_SHRINK) != 0 { may_shrink = true; } }
        else { inert = true; }
    } else if kind == N_VARIABLE {
        var init = n.right; var all_init_inert = true;
        while init >= 0 {
            life_analyze_node(p, l, init, omit_reads, fn_state, has_defer, any_defer);
            if (l.node_flags[init] & NF_MAY_SHRINK) != 0 { may_shrink = true; }
            if (l.node_flags[init] & NF_INERT) == 0 { all_init_inert = false; }
            if n.first < 0 { break; }
            init = p.nodes[init].next;
        }
        if all_init_inert {
            if n.first < 0 {
                if n.symbol >= 0 && (l.sym_flags[n.symbol] & SF_SCALAR_LOCAL) != 0 { inert = true; }
            } else {
                var all_scalar = true; var b = n.first;
                while b >= 0 {
                    let s = p.nodes[b].symbol;
                    if s < 0 || (l.sym_flags[s] & SF_SCALAR_LOCAL) == 0 { all_scalar = false; break; }
                    b = p.nodes[b].next;
                }
                if all_scalar { inert = true; }
            }
        }
    } else if kind == N_ASSIGN {
        if n.left >= 0 { life_analyze_node(p, l, n.left, omit_reads, fn_state, has_defer, any_defer); if (l.node_flags[n.left] & NF_MAY_SHRINK) != 0 { may_shrink = true; } }
        if n.right >= 0 { life_analyze_node(p, l, n.right, omit_reads, fn_state, has_defer, any_defer); if (l.node_flags[n.right] & NF_MAY_SHRINK) != 0 { may_shrink = true; } }
        if n.left >= 0 {
            let ln: const Node& = p.nodes[n.left];
            var ty = ln.type_id;
            if ty >= 0 && p.types[ty].kind == TY_REF && n.integer != T_DOTASSIGN { ty = p.types[ty].element; }
            if ty >= 0 && ty < l.type_flags.len && (l.type_flags[ty] & TF_L_SC2) != 0 ||
               ty >= 0 && p.types[ty].kind == TY_ENUM && (p.types[ty].flags & F_VARIABLE_MODE) != 0 {
                may_shrink = true;
            }
            let right_inert = n.right < 0 || (l.node_flags[n.right] & NF_INERT) != 0;
            if right_inert {
                if ln.kind == N_NAME && ln.symbol >= 0 && (l.sym_flags[ln.symbol] & SF_SCALAR_LOCAL) != 0 {
                    inert = true;
                } else if no_cr && !in_seq && (ln.kind == N_MEMBER || ln.kind == N_INDEX) &&
                          (l.node_flags[n.left] & NF_PURE_PLACE) != 0 && life_type_is_scalar(l, ln.type_id) {
                    inert = true;
                }
            }
        }
    } else if kind == N_CALL {
        var arg = n.first; var all_args_inert = true;
        while arg >= 0 {
            life_analyze_node(p, l, arg, omit_reads, fn_state, has_defer, any_defer);
            if (l.node_flags[arg] & NF_MAY_SHRINK) != 0 { may_shrink = true; }
            if (l.node_flags[arg] & NF_INERT) == 0 { all_args_inert = false; }
            arg = p.nodes[arg].next;
        }
        if n.aux >= 0 && n.symbol >= 0 && (p.symbols[n.symbol].flags & S_BUILTIN) != 0 {
            let b = p.symbols[n.symbol].index;
            if b == 33 || b == 34 {
                life_analyze_node(p, l, n.aux, omit_reads, fn_state, has_defer, any_defer);
                if (l.node_flags[n.aux] & NF_MAY_SHRINK) != 0 { may_shrink = true; }
            }
        }
        if n.symbol >= 0 {
            let sym: const Symbol& = p.symbols[n.symbol];
            if (sym.flags & S_BUILTIN) != 0 {
                let b = sym.index;
                if b == 26 || b == 27 || b == 28 || b == 29 { may_shrink = true; }
                if (b == 21 || b == 22) && !needs_place && !in_seq && n.first >= 0 && p.nodes[n.first].next < 0 {
                    if (l.node_flags[n.first] & NF_INERT) != 0 || no_cr && (l.node_flags[n.first] & NF_PURE_PLACE) != 0 {
                        inert = true;
                    }
                } else if (b == 3 || b == 4 || b == 5 || b == 6 || b == 38 || b == 39) &&
                          !needs_place && all_args_inert && life_type_void_or_scalar(p, l, n.type_id) {
                    inert = true;
                }
            } else {
                if (n.flags & F_DISPATCH) == 0 && sym.node >= 0 && sym.node < fn_state.len && fn_state[sym.node] == 1 {
                    life_analyze_candidate_fn(p, l, sym.node, omit_reads, fn_state, any_defer);
                }
                if (n.flags & F_DISPATCH) == 0 && sym.node >= 0 && sym.node < l.node_flags.len &&
                   (l.node_flags[sym.node] & NF_FN_INERT) != 0 {
                    if !needs_place && !may_shrink && life_type_void_or_scalar(p, l, n.type_id) {
                        if all_args_inert {
                            inert = true;
                        } else if no_cr && !in_seq {
                            var ok = true; var a = n.first; var f = p.nodes[sym.node].first;
                            while a >= 0 {
                                if (l.node_flags[a] & NF_INERT) == 0 {
                                    if f < 0 || !life_type_plain_ref_or_slice(p, p.nodes[f].type_id) ||
                                       ((l.node_flags[a] & NF_PURE_PLACE) == 0 && p.nodes[a].kind != N_STRING) {
                                        ok = false; break;
                                    }
                                }
                                if f >= 0 { f = p.nodes[f].next; }
                                a = p.nodes[a].next;
                            }
                            if ok { inert = true; }
                        }
                    }
                } else {
                    may_shrink = true;
                }
            }
        }
    } else if kind == N_BLOCK {
        var child = n.first; var all_inert = true;
        while child >= 0 {
            life_analyze_node(p, l, child, omit_reads, fn_state, has_defer, any_defer);
            if (l.node_flags[child] & NF_MAY_SHRINK) != 0 { may_shrink = true; }
            if (l.node_flags[child] & NF_INERT) == 0 { all_inert = false; }
            child = p.nodes[child].next;
        }
        if !needs_place && (n.flags & F_EARLY) == 0 && (l.node_flags[node] & NF_HAS_EXIT) == 0 &&
           all_inert && life_type_void_or_scalar(p, l, n.type_id) &&
           (n.scope < 0 || n.scope >= l.scope_has_cell.len || l.scope_has_cell[n.scope] == 0) {
            inert = true;
        }
    } else if kind == N_IF {
        if n.left >= 0 { life_analyze_node(p, l, n.left, omit_reads, fn_state, has_defer, any_defer); if (l.node_flags[n.left] & NF_MAY_SHRINK) != 0 { may_shrink = true; } }
        if n.right >= 0 { life_analyze_node(p, l, n.right, omit_reads, fn_state, has_defer, any_defer); if (l.node_flags[n.right] & NF_MAY_SHRINK) != 0 { may_shrink = true; } }
        if n.third >= 0 { life_analyze_node(p, l, n.third, omit_reads, fn_state, has_defer, any_defer); if (l.node_flags[n.third] & NF_MAY_SHRINK) != 0 { may_shrink = true; } }
        if !needs_place && life_type_void_or_scalar(p, l, n.type_id) &&
           (n.left < 0 || (l.node_flags[n.left] & NF_INERT) != 0) &&
           (n.right < 0 || (l.node_flags[n.right] & NF_INERT) != 0) &&
           (n.third < 0 || (l.node_flags[n.third] & NF_INERT) != 0) {
            inert = true;
        }
    } else if kind == N_MATCH {
        if n.left >= 0 { life_analyze_node(p, l, n.left, omit_reads, fn_state, has_defer, any_defer); if (l.node_flags[n.left] & NF_MAY_SHRINK) != 0 { may_shrink = true; } }
        var all_inert = n.left < 0 || (l.node_flags[n.left] & NF_INERT) != 0;
        var arm = n.first;
        while arm >= 0 {
            let a: const Node& = p.nodes[arm];
            if a.left >= 0 {
                let pat: const Node& = p.nodes[a.left];
                if pat.left >= 0 && p.nodes[pat.left].symbol >= 0 && p.nodes[pat.left].symbol < l.sym_flags.len {
                    if (l.sym_flags[p.nodes[pat.left].symbol] & SF_SCALAR_LOCAL) == 0 { all_inert = false; }
                }
            } else {
                all_inert = false;
            }
            if a.third >= 0 { life_analyze_node(p, l, a.third, omit_reads, fn_state, has_defer, any_defer); if (l.node_flags[a.third] & NF_MAY_SHRINK) != 0 { may_shrink = true; } if (l.node_flags[a.third] & NF_INERT) == 0 { all_inert = false; } }
            if a.right >= 0 { life_analyze_node(p, l, a.right, omit_reads, fn_state, has_defer, any_defer); if (l.node_flags[a.right] & NF_MAY_SHRINK) != 0 { may_shrink = true; } if (l.node_flags[a.right] & NF_INERT) == 0 { all_inert = false; } }
            arm = a.next;
        }
        if !needs_place && all_inert && life_type_void_or_scalar(p, l, n.type_id) { inert = true; }
    } else if kind == N_WHILE || kind == N_LOOP || kind == N_FOR {
        if n.left >= 0 { life_analyze_node(p, l, n.left, omit_reads, fn_state, has_defer, any_defer); if (l.node_flags[n.left] & NF_MAY_SHRINK) != 0 { may_shrink = true; } }
        if n.right >= 0 { life_analyze_node(p, l, n.right, omit_reads, fn_state, has_defer, any_defer); if (l.node_flags[n.right] & NF_MAY_SHRINK) != 0 { may_shrink = true; } }
        if !needs_place && (l.node_flags[node] & NF_HAS_EXIT) == 0 && life_type_void_or_scalar(p, l, n.type_id) &&
           (n.scope < 0 || n.scope >= l.scope_has_cell.len || l.scope_has_cell[n.scope] == 0) &&
           (n.left < 0 || (l.node_flags[n.left] & NF_INERT) != 0) &&
           (n.right < 0 || (l.node_flags[n.right] & NF_INERT) != 0) {
            if kind != N_FOR {
                inert = true;
            } else if n.left >= 0 && p.nodes[n.left].kind == N_RANGE {
                var all_scalar = true; var b = n.first;
                while b >= 0 {
                    let s = p.nodes[b].symbol;
                    if s < 0 || s >= l.sym_flags.len || (l.sym_flags[s] & SF_SCALAR_LOCAL) == 0 { all_scalar = false; break; }
                    b = p.nodes[b].next;
                }
                if all_scalar { inert = true; }
            }
        }
    } else if kind == N_RETURN {
        var child = n.first; var count = 0; var all_inert = true;
        while child >= 0 {
            life_analyze_node(p, l, child, omit_reads, fn_state, has_defer, any_defer);
            if (l.node_flags[child] & NF_MAY_SHRINK) != 0 { may_shrink = true; }
            if (l.node_flags[child] & NF_INERT) == 0 { all_inert = false; }
            count += 1; child = p.nodes[child].next;
        }
        let nonlocal_ret = any_defer && n.symbol >= 0 && n.symbol < p.symbols.len &&
            (n.scope < 0 || n.scope >= l.functions.len || l.functions[n.scope] != p.symbols[n.symbol].node);
        if has_defer || nonlocal_ret {
            may_shrink = true;
        } else if count == 0 {
            inert = true;
        } else if count == 1 && all_inert && n.symbol >= 0 && n.symbol < p.symbols.len {
            let fn_id = p.symbols[n.symbol].node;
            if fn_id >= 0 && p.nodes[fn_id].type_id >= 0 {
                let ret_ty = p.types[p.nodes[fn_id].type_id].element;
                if life_type_is_scalar(l, ret_ty) { inert = true; }
            }
        }
    } else if kind == N_BREAK {
        if has_defer { may_shrink = true; }
        if n.left < 0 {
            if !has_defer { inert = true; }
        } else {
            life_analyze_node(p, l, n.left, omit_reads, fn_state, has_defer, any_defer);
            if (l.node_flags[n.left] & NF_MAY_SHRINK) != 0 { may_shrink = true; }
        }
    } else if kind == N_TUPLE || kind == N_ARRAY || kind == N_FILL || kind == N_RECORD {
        var child = n.first;
        while child >= 0 {
            var v = child; if kind == N_RECORD { v = p.nodes[child].right; }
            if v >= 0 { life_analyze_node(p, l, v, omit_reads, fn_state, has_defer, any_defer); if (l.node_flags[v] & NF_MAY_SHRINK) != 0 { may_shrink = true; } }
            child = p.nodes[child].next;
        }
        if kind == N_FILL && n.first < 0 {
            if n.left >= 0 { life_analyze_node(p, l, n.left, omit_reads, fn_state, has_defer, any_defer); if (l.node_flags[n.left] & NF_MAY_SHRINK) != 0 { may_shrink = true; } }
            if n.right >= 0 { life_analyze_node(p, l, n.right, omit_reads, fn_state, has_defer, any_defer); if (l.node_flags[n.right] & NF_MAY_SHRINK) != 0 { may_shrink = true; } }
        }
    } else if kind == N_RESULT {
        if n.left >= 0 { life_analyze_node(p, l, n.left, omit_reads, fn_state, has_defer, any_defer); if (l.node_flags[n.left] & NF_MAY_SHRINK) != 0 { may_shrink = true; } }
    }
    var bits = l.node_flags[node] & ~(NF_PURE_PLACE | NF_MAY_SHRINK | NF_INERT);
    if pure_place { bits |= NF_PURE_PLACE; }
    if may_shrink { bits |= NF_MAY_SHRINK; }
    if inert { bits |= NF_INERT; }
    l.node_flags[node] = bits;
}
fn life_holds_fast(p: Program&, l: Lifetimes&, ty: i64) -> bool {
    if ty < 0 { return false; }
    let t0: const Type& = p.types[ty];
    if t0.kind == TY_SLICE { return true; }
    if t0.kind == TY_REF { return t0.length_storage < 0; }
    if t0.kind != TY_ARRAY && t0.kind != TY_STRUCT && t0.kind != TY_ENUM && t0.kind != TY_TUPLE { return false; }
    l.contains_seen_gen += 1;
    let gen = l.contains_seen_gen;
    let wbase = l.type_work.len;
    let co = l.type_exact_canon[ty] as i64;
    l.contains_seen[co] = gen;
    l.type_work.push(co as i32);
    var at = wbase; var answer = false;
    while at < l.type_work.len {
        let cur = l.type_work[at] as i64; at += 1;
        let t: const Type& = p.types[cur];
        if t.kind == TY_SLICE || t.kind == TY_REF && t.length_storage < 0 { answer = true; break; }
        if t.kind == TY_ARRAY && t.element >= 0 {
            let elem = l.type_exact_canon[t.element] as i64;
            if l.contains_seen[elem] != gen { l.contains_seen[elem] = gen; l.type_work.push(elem as i32); }
        } else if t.kind == TY_STRUCT || t.kind == TY_ENUM || t.kind == TY_TUPLE {
            var field = t.first;
            while field >= 0 {
                let ft = p.nodes[field].type_id;
                if ft >= 0 {
                    let fe = l.type_exact_canon[ft] as i64;
                    if l.contains_seen[fe] != gen { l.contains_seen[fe] = gen; l.type_work.push(fe as i32); }
                }
                field = p.nodes[field].next;
            }
        }
    }
    l.type_work.resize(wbase);
    return answer;
}
fn life_prepare_nodes(p: Program&, l: Lifetimes&, full: bool) -> bool {
    let type_count = p.types.len;
    if l.type_canon.len < type_count { life_canon_types(p, l); }
    l.type_exact_canon.clear(); l.type_exact_canon.resize(type_count, 0);
    var ec_size: i64 = 64; while ec_size < 2 * type_count { ec_size <<= 1; }
    var ec_slots: i32[>..] = []; ec_slots.resize(ec_size, -1);
    let ec_mask = ec_size - 1;
    for id in 0..type_count {
        let t: const Type& = p.types[id];
        let k = t.kind;
        if k != TY_VOID && k != TY_BOOL && k != TY_INT && k != TY_FLOAT &&
           k != TY_STRUCT && k != TY_ENUM && k != TY_ARRAY && k != TY_SLICE && k != TY_REF {
            l.type_exact_canon[id] = id as i32;
            continue;
        }
        var a: i64 = 0; var b: i64 = 0;
        if k == TY_STRUCT || k == TY_ENUM { a = t.declaration; b = t.first; }
        else if k == TY_INT { a = t.count; b = (t.flags & TF_UNSIGNED) as i64; }
        else if k == TY_FLOAT { a = t.count; }
        else if k == TY_ARRAY { a = t.array_kind; b = t.element; }
        else if k == TY_SLICE { a = t.element; }
        else if k == TY_REF { a = t.element; if t.length_storage >= 0 { b = 1; } }
        var eh: u64 = 1469598103934665603;
        eh = life_hash_step(eh, k as i64);
        eh = life_hash_step(eh, a);
        eh = life_hash_step(eh, b);
        var eslot = ((eh >> 1) as! i64) & ec_mask;
        var found: i64 = -1;
        loop {
            let other = ec_slots[eslot] as i64;
            if other < 0 { break; }
            let ot: const Type& = p.types[other];
            if ot.kind == k {
                var same = false;
                if k == TY_VOID || k == TY_BOOL { same = true; }
                else if k == TY_STRUCT || k == TY_ENUM { same = ot.declaration == t.declaration && ot.first == t.first; }
                else if k == TY_INT { same = ot.count == t.count && (ot.flags & TF_UNSIGNED) == (t.flags & TF_UNSIGNED); }
                else if k == TY_FLOAT { same = ot.count == t.count; }
                else if k == TY_ARRAY { same = ot.array_kind == t.array_kind && ot.element == t.element; }
                else if k == TY_SLICE { same = ot.element == t.element; }
                else if k == TY_REF { same = ot.element == t.element && (ot.length_storage >= 0) == (t.length_storage >= 0); }
                if same { found = other; break; }
            }
            eslot = (eslot + 1) & ec_mask;
        }
        if found < 0 { ec_slots[eslot] = id as i32; found = id; }
        l.type_exact_canon[id] = found as i32;
    }
    l.contains_seen.clear(); l.contains_seen.resize(type_count, 0); l.contains_seen_gen = 0;
    l.outer_type_seen.clear(); l.outer_type_seen.resize(type_count, 0); l.outer_type_seen_gen = 0;
    l.closure_start.clear(); l.closure_start.resize(type_count, 0);
    l.closure_count.clear(); l.closure_count.resize(type_count, -1);
    l.closure_data.clear();
    l.holder_ref_start.clear(); l.holder_ref_start.resize(type_count, 0);
    l.holder_ref_count.clear(); l.holder_ref_count.resize(type_count, -1);
    l.holder_ref_flags.clear(); l.holder_ref_flags.resize(type_count, 0);
    l.holder_ref_elems.clear();
    l.gs_start.clear(); l.gs_start.resize(type_count, 0);
    l.gs_count.clear(); l.gs_count.resize(type_count, -1);
    l.gs_elems.clear();
    l.type_flags.clear(); l.type_flags.resize(type_count, 0);
    for id in 0..type_count {
        let t: const Type& = p.types[id];
        let canon = l.type_exact_canon[id] as i64;
        var f: u8 = 0;
        let is_ref = life_is_ref(p, id);
        let holds = if canon < id { (l.type_flags[canon] & TF_L_HOLDS) != 0 } else { life_holds_fast(p, l, id) };
        let sc = life_cached_size_class(p, l, id);
        let rel = life_relative_storage(p, id, false);
        let rel_pool = life_relative_storage(p, id, true);
        if is_ref { f |= TF_L_REF; }
        if holds { f |= TF_L_HOLDS; }
        if sc == 1 { f |= TF_L_SC1; } else if sc == 2 { f |= TF_L_SC2; }
        if rel { f |= TF_L_REL; }
        if rel_pool { f |= TF_L_REL_POOL; }
        let var_enum = t.kind == TY_ENUM && (t.flags & F_VARIABLE_MODE) != 0;
        if !is_ref && !holds && sc == 0 && !rel_pool && !var_enum &&
           t.kind != TY_VOID && t.kind != TY_TUPLE && t.kind != TY_UNKNOWN && t.kind != TY_ARRAY &&
           !root_struct_type(p, id) {
            f |= TF_L_SCALAR;
        }
        if id == TYPE_U8 || t.element == TYPE_U8 { f |= TF_L_BYTES; }
        l.type_flags[id] = f;
    }
    let node_count = p.nodes.len;
    let sym_count = p.symbols.len;
    l.node_flags.clear(); l.node_flags.resize(node_count, 0);
    l.sym_flags.clear(); l.sym_flags.resize(sym_count, 0);
    l.hold_flags.clear(); l.hold_flags.resize(node_count, if full { FH_CONSTRUCT_READ | FH_BUILD_HOLD | FH_FORMAT_RAW | FH_SC2_SITE } else { 0 });
    var fn_has_nested: u8[>..] = []; fn_has_nested.resize(node_count, 0);
    var fn_has_defer: u8[>..] = []; fn_has_defer.resize(node_count, 0);
    var any_defer = false;
    var place_work: i64[>..] = [];
    var hold_work: i64[>..] = [];
    var seq_work: i64[>..] = [];
    var break_with_val: i64[>..] = [];
    var all_fns: i64[>..] = [];
    var has_cap = false;
    var has_replacement = full;
    for id in 0..node_count {
        let n: const Node& = p.nodes[id];
        let kind = n.kind;
        if n.captures >= 0 { has_cap = true; }
        if kind == N_DEFER {
            any_defer = true;
            let sc = if n.scope >= 0 { n.scope } else if n.right >= 0 { p.nodes[n.right].scope } else { -1 };
            if sc >= 0 && sc < l.functions.len && l.functions[sc] >= 0 && l.functions[sc] < node_count {
                fn_has_defer[l.functions[sc]] = 1;
            }
        }
        if (n.flags & F_REFERENCE_CONTEXT) != 0 || n.coerced_type >= 0 && life_type_is_ref(l, n.coerced_type) {
            life_queue_place(l, place_work, id);
        }
        if kind == N_BREAK {
            if n.left >= 0 && n.symbol >= 0 && n.symbol < node_count {
                l.node_flags[n.symbol] |= NF_HAS_EXIT;
                break_with_val.push(id);
            }
        } else if kind == N_FUNCTION || kind == N_FUNCTION_VALUE {
            if n.right >= 0 && (kind == N_FUNCTION_VALUE || (n.flags & F_CHECKED) != 0) { all_fns.push(id); }
            if n.symbol >= 0 && n.symbol < sym_count && p.symbols[n.symbol].owner >= 0 && p.symbols[n.symbol].owner < node_count {
                fn_has_nested[p.symbols[n.symbol].owner] = 1;
            }
            if n.scope >= 0 && n.scope < l.parents.len {
                let ps = l.parents[n.scope];
                if ps >= 0 && ps < l.functions.len && l.functions[ps] >= 0 && l.functions[ps] < node_count {
                    fn_has_nested[l.functions[ps]] = 1;
                }
            }
        } else if kind == N_UNARY && n.integer == T_BITAND {
            life_queue_place(l, place_work, n.left);
        } else if kind == N_SLICE {
            life_queue_place(l, place_work, n.left);
        } else if kind == N_FOR {
            if n.left >= 0 {
                if p.nodes[n.left].kind != N_RANGE { life_queue_place(l, place_work, n.left); }
                life_mark_for_seq_subtree(p, l, n.left, seq_work);
            }
        } else if kind == N_ASSIGN {
            if n.left >= 0 {
                let ln: const Node& = p.nodes[n.left];
                let simple_scalar_var = ln.kind == N_NAME && ln.symbol >= 0 && ln.symbol < sym_count &&
                    (p.symbols[ln.symbol].flags & (S_GLOBAL | S_FUNCTION | S_BUILTIN | S_TYPE | S_CAPTURE)) == 0 &&
                    life_type_is_scalar(l, p.symbols[ln.symbol].type_id);
                if !simple_scalar_var { life_queue_place(l, place_work, n.left); }
                var ty = ln.type_id;
                if ty >= 0 && p.types[ty].kind == TY_REF && n.integer != T_DOTASSIGN { ty = p.types[ty].element; }
                if ty >= 0 && life_type_is_ref(l, ty) { life_queue_place(l, place_work, n.right); }
                if !full {
                    let is_sc2_site = (ln.kind != N_NAME && ln.kind != N_INDEX && ln.kind != N_MEMBER && !(ln.kind == N_UNARY && ln.integer == T_MUL)) ||
                        ty < 0 || (ty < l.type_flags.len && (l.type_flags[ty] & TF_L_SC2) != 0);
                    if is_sc2_site {
                        has_replacement = true;
                        l.hold_flags[id] |= FH_SC2_SITE;
                        life_queue_hold(l, hold_work, n.right, FH_CONSTRUCT_READ | FH_BUILD_HOLD);
                    }
                }
            }
        } else if kind == N_BINARY && n.integer >= T_EQ && n.integer <= T_GTEQ {
            if n.left >= 0 {
                var lt = p.nodes[n.left].type_id;
                if lt >= 0 && p.types[lt].kind == TY_REF { lt = p.types[lt].element; }
                if lt >= 0 && p.types[lt].kind == TY_ARRAY { life_queue_place(l, place_work, n.left); }
            }
        } else if kind == N_CAST {
            if n.type_id >= 0 && life_type_is_ref(l, n.type_id) { life_queue_place(l, place_work, n.left); }
        } else if kind == N_MATCH {
            var arm = n.first;
            while arm >= 0 {
                if p.nodes[arm].left >= 0 {
                    let pat: const Node& = p.nodes[p.nodes[arm].left];
                    if pat.left >= 0 && p.nodes[pat.left].symbol >= 0 && p.nodes[pat.left].symbol < sym_count && life_type_is_ref(l, p.symbols[p.nodes[pat.left].symbol].type_id) {
                        life_queue_place(l, place_work, n.left); break;
                    }
                }
                arm = p.nodes[arm].next;
            }
        } else if kind == N_VARIABLE {
            var binding = n.first; if binding < 0 { binding = id; }
            var init = n.right;
            let single_init = n.first >= 0 && init >= 0 && p.nodes[init].next < 0;
            while binding >= 0 {
                let s = p.nodes[binding].symbol;
                if s >= 0 && s < sym_count && life_type_is_ref(l, p.symbols[s].type_id) && init >= 0 {
                    life_queue_place(l, place_work, init);
                }
                if n.first < 0 { break; }
                binding = p.nodes[binding].next;
                if init >= 0 && !single_init { init = p.nodes[init].next; }
            }
        } else if kind == N_RECORD || kind == N_ARRAY || kind == N_FILL {
            var child = n.first;
            while child >= 0 {
                var v = child; var expected = -1;
                if kind == N_RECORD { v = p.nodes[child].right; expected = p.nodes[child].type_id; }
                else if n.type_id >= 0 { expected = p.types[n.type_id].element; }
                if expected >= 0 && life_type_is_ref(l, expected) { life_queue_place(l, place_work, v); }
                child = p.nodes[child].next;
            }
            if kind == N_FILL && n.first < 0 && n.type_id >= 0 && life_type_is_ref(l, p.types[n.type_id].element) {
                life_queue_place(l, place_work, n.left);
            }
        } else if kind == N_RETURN {
            if n.symbol >= 0 && n.symbol < sym_count && p.symbols[n.symbol].node >= 0 {
                let fn_n: const Node& = p.nodes[p.symbols[n.symbol].node];
                if fn_n.type_id >= 0 {
                    let expected = p.types[fn_n.type_id].element;
                    var comp = -1;
                    if expected >= 0 && p.types[expected].kind == TY_TUPLE { comp = p.types[expected].first; }
                    var child = n.first;
                    while child >= 0 {
                        var tty = expected;
                        if comp >= 0 { tty = p.nodes[comp].type_id; comp = p.nodes[comp].next; }
                        if tty >= 0 && life_type_is_ref(l, tty) { life_queue_place(l, place_work, child); }
                        child = p.nodes[child].next;
                    }
                }
            }
        } else if kind == N_CALL && n.symbol >= 0 && n.symbol < sym_count {
            let sym: const Symbol& = p.symbols[n.symbol];
            if (sym.flags & S_BUILTIN) != 0 {
                let b = sym.index;
                if !full {
                    if (b == 24 || b == 25 || b == 30 || b == 31) && n.first >= 0 {
                        var ha = p.nodes[n.first].next;
                        while ha >= 0 { life_queue_hold(l, hold_work, ha, FH_BUILD_HOLD); ha = p.nodes[ha].next; }
                    }
                    if (b == 33 || b == 34) && n.aux >= 0 { life_queue_hold(l, hold_work, n.aux, FH_BUILD_HOLD); }
                }
                if b != 21 && b != 22 && b != 3 && b != 4 && b != 5 && b != 6 && b != 38 && b != 39 {
                    var arg = n.first;
                    while arg >= 0 { life_queue_place(l, place_work, arg); arg = p.nodes[arg].next; }
                }
            } else {
                let raw_fmt = sym.node >= 0 && (p.nodes[sym.node].flags & F_FORMAT_RAW) != 0;
                if !full && raw_fmt {
                    life_queue_hold(l, hold_work, sym.node, FH_FORMAT_RAW);
                    if (n.flags & F_DISPATCH) != 0 {
                        var arm = n.third;
                        while arm >= 0 {
                            let fs = p.nodes[arm].symbol;
                            if fs >= 0 && fs < sym_count { life_queue_hold(l, hold_work, p.symbols[fs].node, FH_FORMAT_RAW); }
                            arm = p.nodes[arm].next;
                        }
                    }
                }
                var arg = n.first; var formal = -1; var idx = 0;
                if sym.node >= 0 { formal = p.nodes[sym.node].first; }
                while arg >= 0 {
                    var need = raw_fmt;
                    if !need && (n.flags & F_DISPATCH) != 0 && idx == n.aux {
                        var arm = n.third;
                        while arm >= 0 {
                            let fs = p.nodes[arm].symbol;
                            if fs >= 0 && fs < sym_count && p.symbols[fs].node >= 0 {
                                var f = p.nodes[p.symbols[fs].node].first; var o = 0;
                                while f >= 0 && o < idx { f = p.nodes[f].next; o += 1; }
                                if f >= 0 && life_type_is_ref(l, p.nodes[f].type_id) { need = true; break; }
                            }
                            arm = p.nodes[arm].next;
                        }
                    } else if !need && formal >= 0 && life_type_is_ref(l, p.nodes[formal].type_id) {
                        need = true;
                    }
                    if need { life_queue_place(l, place_work, arg); }
                    if formal >= 0 { formal = p.nodes[formal].next; }
                    arg = p.nodes[arg].next; idx += 1;
                }
            }
        }
    }
    var pi = 0;
    while pi < place_work.len {
        let cur = place_work[pi]; pi += 1;
        let n: const Node& = p.nodes[cur];
        let kind = n.kind;
        if kind == N_NAME {
            if n.symbol >= 0 && n.symbol < sym_count { l.sym_flags[n.symbol] |= SF_ADDR_TAKEN; }
        } else if kind == N_MEMBER || kind == N_INDEX || kind == N_SLICE || kind == N_CAST || kind == N_RESULT {
            life_queue_place(l, place_work, n.left);
        } else if kind == N_UNARY && (n.integer == T_MUL || n.integer == T_BITAND) {
            life_queue_place(l, place_work, n.left);
        } else if kind == N_IF {
            life_queue_place(l, place_work, n.right);
            life_queue_place(l, place_work, n.third);
        } else if kind == N_BLOCK {
            if n.last >= 0 && (p.nodes[n.last].flags & F_TAIL) != 0 { life_queue_place(l, place_work, n.last); }
        } else if kind == N_MATCH {
            var arm = n.first;
            while arm >= 0 { life_queue_place(l, place_work, p.nodes[arm].right); arm = p.nodes[arm].next; }
        }
    }
    // Propagate NF_NEEDS_PLACE to N_BREAK values targeting any block/loop that needs place.
    var extra = false;
    for id in break_with_val {
        let n: const Node& = p.nodes[id];
        if (l.node_flags[n.symbol] & NF_NEEDS_PLACE) != 0 {
            life_queue_place(l, place_work, n.left); extra = true;
        }
    }
    if extra {
        while pi < place_work.len {
            let cur = place_work[pi]; pi += 1;
            let n: const Node& = p.nodes[cur];
            let kind = n.kind;
            if kind == N_NAME {
                if n.symbol >= 0 && n.symbol < sym_count { l.sym_flags[n.symbol] |= SF_ADDR_TAKEN; }
            } else if kind == N_MEMBER || kind == N_INDEX || kind == N_SLICE || kind == N_CAST || kind == N_RESULT {
                life_queue_place(l, place_work, n.left);
            } else if kind == N_UNARY && (n.integer == T_MUL || n.integer == T_BITAND) {
                life_queue_place(l, place_work, n.left);
            } else if kind == N_IF {
                life_queue_place(l, place_work, n.right);
                life_queue_place(l, place_work, n.third);
            } else if kind == N_BLOCK {
                if n.last >= 0 && (p.nodes[n.last].flags & F_TAIL) != 0 { life_queue_place(l, place_work, n.last); }
            } else if kind == N_MATCH {
                var arm = n.first;
                while arm >= 0 { life_queue_place(l, place_work, p.nodes[arm].right); arm = p.nodes[arm].next; }
            }
        }
    }
    // Classify scalar locals/parameters and mark scopes that contain any non-scalar cell.
    // Bit 1: contains a non-scalar local variable; bit 2: contains a non-scalar parameter.
    l.scope_has_cell.clear(); l.scope_has_cell.resize(l.parents.len, 0);
    for s in 0..sym_count {
        let sym: const Symbol& = p.symbols[s];
        if (sym.flags & S_CAPTURE) != 0 { has_cap = true; }
        if (sym.flags & (S_GLOBAL | S_FUNCTION | S_BUILTIN | S_TYPE)) != 0 { continue; }
        let owner = sym.owner;
        if (sym.flags & S_CAPTURE) == 0 && (l.sym_flags[s] & SF_ADDR_TAKEN) == 0 &&
           life_type_is_scalar(l, sym.type_id) && owner >= 0 && owner < node_count && fn_has_nested[owner] == 0 {
            l.sym_flags[s] |= SF_SCALAR_LOCAL;
        } else {
            var bit: u8 = 1; if (sym.flags & S_PARAMETER) != 0 { bit = 2; }
            var sc = sym.scope;
            while sc >= 0 && sc < l.scope_has_cell.len && (l.scope_has_cell[sc] & bit) == 0 {
                l.scope_has_cell[sc] |= bit;
                sc = l.parents[sc];
            }
        }
    }
    if !full {
        var hi = 0;
        while hi < hold_work.len {
            let cur = hold_work[hi]; hi += 1;
            let bits = l.hold_flags[cur] & (FH_CONSTRUCT_READ | FH_BUILD_HOLD | FH_FORMAT_RAW);
            if bits == 0 { continue; }
            let n: const Node& = p.nodes[cur];
            let kind = n.kind;
            if kind == N_FUNCTION || kind == N_FUNCTION_VALUE {
                life_queue_hold(l, hold_work, n.right, bits);
                continue;
            }
            if kind == N_STRUCT || kind == N_ENUM || kind == N_ALIAS || kind == N_IMPORT || kind == N_NAMESPACE { continue; }
            var child = n.first;
            while child >= 0 {
                if kind == N_RECORD {
                    life_queue_hold(l, hold_work, p.nodes[child].right, bits);
                } else if kind == N_MATCH {
                    life_queue_hold(l, hold_work, p.nodes[child].third, bits);
                    life_queue_hold(l, hold_work, p.nodes[child].right, bits);
                } else {
                    let ck = p.nodes[child].kind;
                    if ck != N_FUNCTION && ck != N_FUNCTION_VALUE { life_queue_hold(l, hold_work, child, bits); }
                }
                child = p.nodes[child].next;
            }
            if n.left >= 0 {
                let lk = p.nodes[n.left].kind;
                if lk != N_FUNCTION && lk != N_FUNCTION_VALUE { life_queue_hold(l, hold_work, n.left, bits); }
            }
            if n.right >= 0 {
                if kind == N_VARIABLE {
                    var init = n.right;
                    while init >= 0 {
                        let ik = p.nodes[init].kind;
                        if ik != N_FUNCTION && ik != N_FUNCTION_VALUE { life_queue_hold(l, hold_work, init, bits); }
                        if n.first < 0 { break; }
                        init = p.nodes[init].next;
                    }
                } else {
                    let rk = p.nodes[n.right].kind;
                    if rk != N_FUNCTION && rk != N_FUNCTION_VALUE { life_queue_hold(l, hold_work, n.right, bits); }
                }
            }
            if n.third >= 0 && !(kind == N_CALL && (n.flags & F_DISPATCH) != 0) {
                let tk = p.nodes[n.third].kind;
                if tk != N_FUNCTION && tk != N_FUNCTION_VALUE { life_queue_hold(l, hold_work, n.third, bits); }
            }
            if kind == N_CALL && n.symbol >= 0 && n.symbol < sym_count {
                let sym: const Symbol& = p.symbols[n.symbol];
                if (sym.flags & S_BUILTIN) != 0 {
                    let b = sym.index;
                    if (b == 33 || b == 34) && n.aux >= 0 { life_queue_hold(l, hold_work, n.aux, bits); }
                } else if (n.flags & F_DISPATCH) != 0 {
                    var arm = n.third;
                    while arm >= 0 {
                        let fs = p.nodes[arm].symbol;
                        if fs >= 0 && fs < sym_count { life_queue_hold(l, hold_work, p.symbols[fs].node, bits); }
                        arm = p.nodes[arm].next;
                    }
                } else if sym.node >= 0 {
                    life_queue_hold(l, hold_work, sym.node, bits);
                }
            }
        }
    }
    // Single-pass topological DFS for NF_FN_INERT across acyclic top-level helper
    // functions, followed by one visit over all remaining function bodies and globals.
    let omit_reads = !has_replacement;
    l.omit_construct_reads = omit_reads;
    var fn_state: u8[>..] = []; fn_state.resize(node_count, 0);
    var candidate_fns: i64[>..] = [];
    for id in all_fns {
        let n: const Node& = p.nodes[id];
        if n.kind != N_FUNCTION || (n.flags & (F_CHECKED | F_GENERIC | F_EXTERN | F_RECURSIVE | F_CAPTURE | F_FORMAT_RAW)) != F_CHECKED { continue; }
        if n.symbol < 0 || p.symbols[n.symbol].owner >= 0 || fn_has_nested[id] != 0 || fn_has_defer[id] != 0 { continue; }
        if n.type_id < 0 || !life_type_void_or_scalar(p, l, p.types[n.type_id].element) { continue; }
        let fn_no_cr = omit_reads || (!full && (l.hold_flags[id] & FH_CONSTRUCT_READ) == 0);
        var params_ok = true; var formal = n.first;
        while formal >= 0 {
            let fs = p.nodes[formal].symbol;
            if fs < 0 { params_ok = false; break; }
            let is_sc = (l.sym_flags[fs] & SF_SCALAR_LOCAL) != 0;
            let is_ref_ok = fn_no_cr && life_type_plain_ref_or_slice(p, p.nodes[formal].type_id);
            if !is_sc && !is_ref_ok { params_ok = false; break; }
            formal = p.nodes[formal].next;
        }
        if params_ok { candidate_fns.push(id); fn_state[id] = 1; }
    }
    l.has_captures = has_cap;
    for fn_id in candidate_fns {
        if fn_state[fn_id] == 1 { life_analyze_candidate_fn(p, l, fn_id, omit_reads, fn_state, any_defer); }
    }
    for id in all_fns {
        if fn_state[id] != 0 { continue; }
        life_analyze_node(p, l, p.nodes[id].right, omit_reads, fn_state, fn_has_defer[id] != 0, any_defer);
    }
    for s in 0..sym_count {
        let sym: const Symbol& = p.symbols[s];
        if (sym.flags & S_GLOBAL) != 0 && sym.node >= 0 && p.nodes[sym.node].kind == N_VARIABLE {
            life_analyze_node(p, l, sym.node, omit_reads, fn_state, false, any_defer);
        }
    }
    l.nodes_prepared = true;
    return omit_reads;
}

fn life_check_attempt(p: Program&, scope_parent: const i64[>..]&, scope_depth: const i64[>..]&, scope_functions: const i64[>..]&, pool_references: const i64[:], full: bool) -> bool {
    var roots: LifeRoot[>..] = [LifeRoot {}]; var sets: LifeSet[>..] = [LifeSet {}];
    var alts: LifeAlt[>..] = []; var cells: LifeCell[>..] = []; var frames: LifeFrame[>..] = [LifeFrame {}];
    var held_walks: LifeWalkMemo[>..] = [];
    var items: LifeItem[>..] = []; var pair_slots: LifePairSlot[>..] = []; var exits: LifeExit[>..] = [];
    var futures: LifeFuture[>..] = []; var holds: LifeHold[>..] = []; var temps: LifeTemp[>..] = []; var reads: LifeRead[>..] = []; var kills: LifeKill[>..] = []; var atoms: LifeAtom[>..] = []; var failures: LifeFailure[>..] = []; var effects: LifeEffect[>..] = [];
    var defers: LifeDefer[>..] = []; var defer_targets: LifeDeferTarget[>..] = []; var defer_run: LifeDefer[>..] = [];
    var bypass_memo: u8[>..] = [];
    var symbol_cells: i32[>..] = []; symbol_cells.resize(p.symbols.len, -1);
    var node_roots: i32[>..] = []; var function_frames: i32[>..] = []; var read_heads: i32[>..] = []; var visited: i32[>..] = []; var summary_slots: LifeSummarySlot[>..] = [];
    var effect_heads: i32[>..] = []; effect_heads.resize(2048, -1);
    node_roots.resize(p.nodes.len, -1); function_frames.resize(p.nodes.len, -1);
    summary_slots.resize(2048, LifeSummarySlot {});
    var summaries: LifeSummary[>..] = []; var capture_reads: i8[>..] = [];
    var leaves: LifeLeaf[>..] = []; var leaf_slots: LifeLeafSlot[>..] = []; var leaf_stamps: i64[>..] = []; var leaf_floors: i32[>..] = [];
    var summary_reads: LifeReadEntry[>..] = []; var read_slots: i32[>..] = [];
    // (Chain 0 is frame 0's, the globals'.)
    var contexts: LifeContext[>..] = [LifeContext { frame: 0, parent: -1 }]; var context_heads: i32[>..] = [];
    var chain_replays: LifeChainReplay[>..] = [];
    var offer_slots: i64 = 256; while offer_slots < 16384 && 16 * offer_slots < p.nodes.len { offer_slots *= 4; }
    var offers: LifeOffer[>..] = []; offers.resize(offer_slots, LifeOffer {});
    var global_read_list: i64[>..] = [];
    var bodies: LifeBody[>..] = []; var body_slots: i64[>..] = []; var body_globals: i64[>..] = []; var body_calls: i64[>..] = [];
    var size_classes: i64[>..] = []; size_classes.resize(p.types.len, -1);
    var holder_starts: i64[>..] = []; holder_starts.resize(p.types.len, -1); var holder_counts: i64[>..] = []; holder_counts.resize(p.types.len, 0); var holder_refs: i64[>..] = [];
    var index_types: i64[>..] = []; var asked: LifeAsked[>..] = [];
    var build_alts: LifeAlt[>..] = []; var build_slots: i64[>..] = []; var scratch: LifeAlt[>..] = [];
    var list_slots: LifeListSlot[>..] = []; var atom_slots: LifeAtomSlot[>..] = []; var cell_keys: LifeCellKey[>..] = [];
    var contains_pointee: i64[>..] = []; var contains_answer: bool[>..] = [];
    var live_bits: u64[>..] = []; var live_words: u64[>..] = []; var holder_bits: u64[>..] = [];
    var live_holder_bits: u64[>..] = []; var live_holder_words: u64[>..] = [];
    var walk_work: LifeWalk[>..] = []; var walk_scanned: i64[>..] = []; var walk_memo_roots: LifeWalkRoot[>..] = [];
    var walk_seen: LifeWalkSlot[>..] = []; var shrink_safe: LifeWalkSlot[>..] = []; var walk_elems: LifeWalkElem[>..] = [];
    var global_future_mark: i64[>..] = []; var last_future_nodes: i64[>..] = []; var last_future_lasts: i64[>..] = [];
    var global_shrinks: LifeGlobalShrink[>..] = [];
    var shrink_clean: LifeShrinkClean[>..] = []; var global_shrink_clean: LifeGlobalShrinkClean[>..] = []; var shrink_ov: LifeOvSlot[>..] = [];
    var type_flags: u8[>..] = []; var sym_flags: u8[>..] = []; var node_flags: u8[>..] = []; var scope_has_cell: u8[>..] = []; var hold_flags: u8[>..] = [];
    var root_live_stamps: i64[>..] = []; var chk_dep_roots: i32[>..] = []; var chk_dep_stack: i32[>..] = [];
    var held_own_memo: LifeHeldOwn[>..] = []; var type_exact_canon: i32[>..] = [];
    var node_body: i32[>..] = []; var span_slots: LifeSpanSlot[>..] = []; var body_work: i64[>..] = []; var body_reached: i64[>..] = [];
    var local_holder_bits: u64[>..] = []; var local_holder_words: u64[>..] = [];
    var contains_seen: i32[>..] = []; var outer_type_seen: i32[>..] = [];
    var closure_start: i32[>..] = []; var closure_count: i32[>..] = []; var closure_data: i32[>..] = [];
    var holder_ref_start: i32[>..] = []; var holder_ref_count: i32[>..] = []; var holder_ref_flags: u8[>..] = []; var holder_ref_elems: i32[>..] = [];
    var gs_start: i32[>..] = []; var gs_count: i32[>..] = []; var gs_elems: i32[>..] = [];
    var body_trans_globals: i64[>..] = [];
    var summary_l1: LifeSummarySlot[>..] = []; summary_l1.resize(2048, LifeSummarySlot {});
    var assume_l1: LifeAssumeSlot[>..] = []; assume_l1.resize(2048, LifeAssumeSlot {});
    var dep_roots: i64[>..] = []; var dep_callees: i64[>..] = []; var dep_callee_stamps: i64[>..] = [];
    var dep_root_stack: i64[>..] = []; var dep_callee_stack: i64[>..] = []; var dep_callee_stamp_stack: i64[>..] = [];
    var dep_root_mark: i64[>..] = []; var dep_callee_mark: i64[>..] = [];
    var clean_work: i64[>..] = [];
    var deep_cells: i64[>..] = []; var input_heads: i32[>..] = []; var home_heads: i32[>..] = [];
    var cell_slots: i32[>..] = []; var temp_slots: i32[>..] = []; var contents_memo: LifeContents[>..] = []; var root_stamps: i64[>..] = [];
    var loaded: LifeLoaded[>..] = []; var gs_asked: i64[>..] = []; var gs_answer: bool[>..] = []; var relative_storage: i64[>..] = [];
    var local_reads: LifeLocalRead[>..] = []; var readbacks: LifeReadBack[>..] = [];
    var inexact_reads: LifeInexactRead[>..] = [];
    var depth_clock: i64[>..] = []; depth_clock.resize(64, 0);
    var far_cache: LifeFarMemo[>..] = [];
    var class_list: i64[>..] = []; var class_heads: i64[>..] = []; var class_keys: i64[>..] = [];
    var map_sets: i64[>..] = []; var map_roots: i64[>..] = []; var map_types: i64[>..] = []; var map_depths: i64[>..] = []; var key_scratch: i64[>..] = []; var class_scratch: i64[>..] = []; var bound_scratch: i64[>..] = [];
    var assumes: LifeAssume[>..] = []; var assume_slots: LifeAssumeSlot[>..] = []; var map_memo: LifeMapped[>..] = []; var type_work: i32[>..] = []; var call_sigs: LifeCallSig[>..] = []; var call_sig_heads: i32[>..] = []; var call_sig_data: i32[>..] = []; var body_owners: i64[>..] = []; var body_captures: i64[>..] = []; var contained: i64[>..] = []; var typed_slots: LifeTypedSlot[>..] = []; var global_types: i8[>..] = []; var refers: LifeRefers[>..] = []; var referable: LifeLoaded[>..] = []; var type_canon: i64[>..] = [];
    var class_slots: i64[>..] = []; var joins: LifeJoin[>..] = []; var global_cells: i64[>..] = []; var global_candidates: LifeGlobalCandidates[>..] = []; var candidate_alts: LifeAlt[>..] = [];
    var store_wakes: LifeStoreWake[>..] = [];
    var l = Lifetimes { parents: scope_parent, depths: scope_depth, functions: scope_functions,
        roots: roots, sets: sets, alts: alts, cells: cells, frames: frames, items: items, pair_slots: pair_slots, held_walks: held_walks, exits: exits,
        futures: futures, holds: holds, temps: temps, reads: reads, kills: kills, size_classes: size_classes, holder_starts: holder_starts, holder_counts: holder_counts, holder_refs: holder_refs, index_types: index_types, asked: asked, atoms: atoms, failures: failures, effects: effects, symbol_cells: symbol_cells, node_roots: node_roots, function_frames: function_frames, read_heads: read_heads, visited: visited, summary_slots: summary_slots, effect_heads: effect_heads, summaries: summaries, leaves: leaves, leaf_slots: leaf_slots, leaf_stamps: leaf_stamps, leaf_floors: leaf_floors, summary_reads: summary_reads, read_slots: read_slots, contexts: contexts, context_heads: context_heads, chain_replays: chain_replays, capture_reads: capture_reads, offers: offers, global_read_list: global_read_list,
        bodies: bodies, body_slots: body_slots, body_globals: body_globals, body_calls: body_calls,
        build_alts: build_alts, build_slots: build_slots, scratch: scratch,
        list_slots: list_slots, atom_slots: atom_slots, cell_keys: cell_keys, contains_pointee: contains_pointee, contains_answer: contains_answer,
        deep_cells: deep_cells, input_heads: input_heads, home_heads: home_heads,
        cell_slots: cell_slots, temp_slots: temp_slots, contents_memo: contents_memo, root_stamps: root_stamps,
        loaded: loaded, gs_asked: gs_asked, gs_answer: gs_answer, relative_storage: relative_storage, local_reads: local_reads, readbacks: readbacks,
        inexact_reads: inexact_reads, depth_clock: depth_clock, far_cache: far_cache,
        live_bits: live_bits, live_words: live_words, holder_bits: holder_bits,
        live_holder_bits: live_holder_bits, live_holder_words: live_holder_words,
        walk_work: walk_work, walk_scanned: walk_scanned, walk_memo_roots: walk_memo_roots, shrink_clean: shrink_clean, global_shrink_clean: global_shrink_clean, shrink_ov: shrink_ov,
        walk_seen: walk_seen, walk_elems: walk_elems, shrink_safe: shrink_safe, global_shrinks: global_shrinks, global_future_mark: global_future_mark, last_future_nodes: last_future_nodes, last_future_lasts: last_future_lasts,
        type_flags: type_flags, sym_flags: sym_flags, node_flags: node_flags, scope_has_cell: scope_has_cell, hold_flags: hold_flags,
        dep_roots: dep_roots, dep_callees: dep_callees, dep_callee_stamps: dep_callee_stamps,
        dep_root_stack: dep_root_stack, dep_callee_stack: dep_callee_stack, dep_callee_stamp_stack: dep_callee_stamp_stack,
        dep_root_mark: dep_root_mark, dep_callee_mark: dep_callee_mark, clean_work: clean_work,
        class_slots: class_slots, joins: joins, global_cells: global_cells, global_candidates: global_candidates, candidate_alts: candidate_alts,
        class_list: class_list, class_heads: class_heads, class_keys: class_keys,
        map_sets: map_sets, map_roots: map_roots, map_types: map_types, map_depths: map_depths, key_scratch: key_scratch, class_scratch: class_scratch, bound_scratch: bound_scratch, assumes: assumes, assume_slots: assume_slots, map_memo: map_memo, type_work: type_work, call_sigs: call_sigs, call_sig_heads: call_sig_heads, call_sig_data: call_sig_data, body_owners: body_owners, body_captures: body_captures, contained: contained, typed_slots: typed_slots, type_canon: type_canon, global_types: global_types, refers: refers, referable: referable, store_wakes: store_wakes,
        full_reads: full, root_live_stamps: root_live_stamps, chk_dep_roots: chk_dep_roots, chk_dep_stack: chk_dep_stack,
        held_own_memo: held_own_memo, type_exact_canon: type_exact_canon,
        node_body: node_body, span_slots: span_slots, body_work: body_work, body_reached: body_reached,
        local_holder_bits: local_holder_bits, local_holder_words: local_holder_words,
        contains_seen: contains_seen, outer_type_seen: outer_type_seen,
        closure_start: closure_start, closure_count: closure_count, closure_data: closure_data,
        holder_ref_start: holder_ref_start, holder_ref_count: holder_ref_count, holder_ref_flags: holder_ref_flags, holder_ref_elems: holder_ref_elems,
        gs_start: gs_start, gs_count: gs_count, gs_elems: gs_elems,
        body_trans_globals: body_trans_globals, summary_l1: summary_l1, assume_l1: assume_l1,
        defers: defers, defer_targets: defer_targets, defer_run: defer_run, bypass_memo: bypass_memo };
    life_validate_pools(p, l, pool_references);
    if p.diagnostics.len > 0 { return true; }
    var standalone: LifeStandalone[>..] = []; let node_count = p.nodes.len;
    for s in 0..p.symbols.len {
        let sym: const Symbol& = p.symbols[s];
        if (sym.flags & S_FUNCTION) == 0 || sym.owner >= 0 || sym.node < 0 || sym.node >= node_count { continue; }
        let id = sym.node;
        if id == p.entry { continue; }
        let n: const Node& = p.nodes[id];
        if n.kind != N_FUNCTION || n.right < 0 || (n.flags & (F_CHECKED | F_GENERIC)) != F_CHECKED || n.symbol != s { continue; }
        // A reachable function is analyzed from its callers, except a thread
        // or an export, which the runtime or a host calls with arguments of
        // its own (upstream's export bodies are roots too).
        if (n.flags & F_REACHABLE) != 0 && (n.flags & (F_THREAD | F_EXPORT)) == 0 { continue; }
        standalone.push(LifeStandalone { function_node: id, arguments: life_standalone_arguments(p, l, id) });
    }
    while node_roots.len < p.nodes.len { node_roots.push(-1); function_frames.push(-1); }
    node_body.resize(p.nodes.len, -1);
    while size_classes.len < p.types.len { size_classes.push(-1); }
    // Standalone argument synthesis is complete; evaluation only reads types.
    l.types_frozen = true;
    let omit_reads = life_prepare_nodes(p, l, full);
    for id in 0..p.types.len {
        let t: const Type& = p.types[id];
        if t.kind == TY_INT && t.index_type >= 0 && t.pool >= 0 { l.index_types.push(id); }
    }
    var saved_frames: LifeRoundFrame[>..] = []; var saved_cells: LifeRoundCell[>..] = [];
    var saved_roots: LifeRoundRoot[>..] = []; var saved_exits: LifeExit[>..] = [];
    var checkpoint = LifeRound { frames: saved_frames, cells: saved_cells, roots: saved_roots, exits: saved_exits };
    // All equations only add alternatives or weaken exactness. A changed
    // invocation feeds its caller and loops on the following discovery pass.
    var reclaim_at: i64 = 28000000;
    loop {
        l.pass += 1;
        let before = l.revision; let frames_before = l.frames.len;
        l.store_changes = 0; store_wakes.clear();
        if l.watch_stores { life_save_round(l, checkpoint); }
        if !life_check_roots(p, l, standalone, omit_reads) { return false; }
        if l.failures.len > 0 {
            l.discovery = false;
            for failure in l.failures { life_error(p, l, failure.node, life_failure_message(failure.kind)); }
            l.types_frozen = false;
            return true;
        }
        let changes = l.revision - before;
        var settled = changes == 0;
        if l.watch_stores && changes == l.store_changes && changes > 0 {
            settled = life_round_stable(l, checkpoint);
            if settled { for wake in store_wakes { if !life_store_delivered(l, wake) { settled = false; break; } } }
        }
        if omit_reads { life_reclaim_items(l, standalone); }
        if !l.watch_stores && l.alts.len > reclaim_at {
            life_reclaim_alts(l, standalone);
            reclaim_at = l.alts.len + 20000000;
            if reclaim_at < 28000000 { reclaim_at = 28000000; }
            if reclaim_at > 44000000 { reclaim_at = 44000000; }
        }
        if settled { break; }
        l.watch_stores = omit_reads && l.class_frames == 0 && l.frames.len == frames_before && changes < frames_before;
    }
    l.settled_global_epoch = l.global_epoch; l.settled_global_refs = l.global_refs_epoch; l.settled_global_live = l.global_live_count;
    l.watch_stores = false; l.discovery = false; l.held_epoch += 1;
    if l.alts.len > 36000000 { life_reclaim_alts(l, standalone); }
    for index in 0..l.roots.len { l.roots[index].live_contents = l.roots[index].contents; }
    l.live_contents_stamp = 1;
    for index in 0..l.cells.len { life_set_live(l, index, false); }
    l.live_epoch += 1; l.holder_grow_epoch += 1; l.global_live_epoch = 1; l.held_epoch += 1;
    if !life_check_roots(p, l, standalone, omit_reads) { return false; }
    for shrink in global_shrinks {
        l.frame = shrink.frame;
        life_check_global_shrink(p, l, shrink);
    }
    l.frame = 0;
    l.types_frozen = false;
    if p.diagnostics.len == 0 { life_export_provenance(p, l); }
    return true;
}
