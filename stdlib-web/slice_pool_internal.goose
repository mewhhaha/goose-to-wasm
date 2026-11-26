namespace slice_pool_detail;

// Port of native/slice_pool.h, derived from the Apache-2.0 Goose runtime.
// A 512-byte node holds either 31 indices and counts or 20 keys, subtree
// maxima, and child indices. Node 0 terminates the chain of emptied nodes.
struct node { n: i64, link: i64, data: i64[62] }
struct tree { root: i64, height: i64, chain: i64 }

let LEAF_CAP = 31;
let FAN = 20;
let CHILD = 40;
let DEPTH = 24;
let MAX_COUNT = 9223372036854775807;
let PAGE = 4096;

struct path { h: i64, ids: i64[24], pos: i64[24] }

fn corrupt() {
    abort("slice pool span tree is corrupt");
}

inline fn span_sum(a: i64, b: i64) -> i64 {
    return ((a as! u64) + (b as! u64)) as! i64;
}

inline fn bad_num(nodes_len: i64, i: i64) -> bool {
    return i <= 0 || i >= nodes_len;
}

inline fn bad_in(nodes: node[>..]&, i: i64) -> bool {
    return bad_num(nodes.len, i) || nodes[i].n <= 0 || nodes[i].n > FAN;
}

inline fn bad_leaf(nodes: node[>..]&, i: i64) -> bool {
    return bad_num(nodes.len, i) || nodes[i].n < 0 || nodes[i].n > LEAF_CAP;
}

inline fn bad_h(h: i64) -> bool { return h < 0 || h >= DEPTH; }

fn new_node(nodes: node[>..]&, tree: tree&) -> i64 {
    let i = tree.chain;
    if i != 0 {
        if bad_num(nodes.len, i) { corrupt(); }
        tree.chain = nodes[i].link;
        return i;
    }
    let end = nodes.len;
    nodes.push(node { .. });
    return end;
}

fn drop_node(nodes: node[>..]&, tree: tree&, i: i64) {
    nodes[i].link = tree.chain;
    tree.chain = i;
}

fn open_leaf(leaf: node&, slot: i64) {
    if leaf.n < 0 || leaf.n >= LEAF_CAP || slot < 0 || slot > leaf.n { corrupt(); }
    var j = leaf.n;
    while j > slot {
        leaf.data[j] = leaf.data[j - 1];
        leaf.data[LEAF_CAP + j] = leaf.data[LEAF_CAP + j - 1];
        j -= 1;
    }
    leaf.n += 1;
}

fn close_leaf(leaf: node&, slot: i64) {
    if slot < 0 || slot >= leaf.n { corrupt(); }
    leaf.n -= 1;
    for j in slot..leaf.n {
        leaf.data[j] = leaf.data[j + 1];
        leaf.data[LEAF_CAP + j] = leaf.data[LEAF_CAP + j + 1];
    }
}

fn open_inner(inner: node&, slot: i64) {
    if inner.n < 0 || inner.n >= FAN || slot < 0 || slot > inner.n { corrupt(); }
    var j = inner.n;
    while j > slot {
        inner.data[j] = inner.data[j - 1];
        inner.data[FAN + j] = inner.data[FAN + j - 1];
        inner.data[CHILD + j] = inner.data[CHILD + j - 1];
        j -= 1;
    }
    inner.n += 1;
}

fn close_inner(inner: node&, slot: i64) {
    if inner.n > FAN || slot < 0 || slot >= inner.n { corrupt(); }
    inner.n -= 1;
    for j in slot..inner.n {
        inner.data[j] = inner.data[j + 1];
        inner.data[FAN + j] = inner.data[FAN + j + 1];
        inner.data[CHILD + j] = inner.data[CHILD + j + 1];
    }
}

// Stop scanning as soon as a count reaches the old maximum.
fn most(entry: node&, offset: i64, first: i64, var largest: i64, stop: i64) -> i64 {
    var k = first;
    while k < entry.n && largest < stop {
        let count = entry.data[offset + k];
        if count > largest { largest = count; }
        k += 1;
    }
    return largest;
}

fn fix(nodes: node[>..]&, p: path&, var level: i64, var before: i64, var after: i64) {
    while level > 0 {
        let inner: node& = nodes[p.ids[level - 1]];
        let child: node& = nodes[p.ids[level]];
        let k = p.pos[level - 1];
        let old_max = inner.data[FAN + k];
        let key = child.data[0];
        let offset = if level == p.h { LEAF_CAP } else { FAN };
        let new_max = if after >= old_max { after }
                      else if before < old_max { old_max }
                      else { most(child, offset, 0, 0, before) };
        if inner.data[k] == key && new_max == old_max { return; }
        inner.data[k] = key;
        inner.data[FAN + k] = new_max;
        before = old_max;
        after = new_max;
        level -= 1;
    }
}

// Find the predecessor of idx and record each child selected on the descent.
fn find(nodes: node[>..]&, tree: tree&, p: path&, idx: i64) -> i64 {
    p.h = tree.height;
    if bad_h(p.h) { corrupt(); }
    var i = tree.root;
    for level in p.h {
        if bad_in(nodes, i) { corrupt(); }
        let inner: node& = nodes[i];
        var k = 1;
        while k < inner.n && inner.data[k] <= idx { k += 1; }
        p.ids[level] = i;
        p.pos[level] = k - 1;
        i = inner.data[CHILD + k - 1];
    }
    p.ids[p.h] = i;
    if bad_leaf(nodes, i) { corrupt(); }
    let leaf: node& = nodes[i];
    var k = 0;
    while k < leaf.n && leaf.data[k] <= idx { k += 1; }
    p.pos[p.h] = k - 1;
    return k - 1;
}

fn new_root(nodes: node[>..]&, tree: tree&, left: i64, right: i64, leaves: bool) {
    let r = new_node(nodes, tree);
    let root: node& = nodes[r];
    let offset = if leaves { LEAF_CAP } else { FAN };
    root.n = 2;
    root.data[0] = nodes[left].data[0];
    root.data[FAN] = most(nodes[left], offset, 0, 0, MAX_COUNT);
    root.data[CHILD] = left;
    root.data[1] = nodes[right].data[0];
    root.data[FAN + 1] = most(nodes[right], offset, 0, 0, MAX_COUNT);
    root.data[CHILD + 1] = right;
    tree.root = r;
    tree.height += 1;
}

// Propagate a split upward until a parent has room or the root splits.
fn add_child(nodes: node[>..]&, tree: tree&, p: path&, var level: i64,
             var k: i64, var child: i64, var leaf: bool) {
    loop {
        let i = p.ids[level];
        let key = nodes[child].data[0];
        let offset = if leaf { LEAF_CAP } else { FAN };
        let max_count = most(nodes[child], offset, 0, 0, MAX_COUNT);
        var dst = i;
        var slot = k;
        var sibling = 0;
        if nodes[i].n == FAN {
            let half = FAN / 2;
            sibling = new_node(nodes, tree);
            if sibling == i { corrupt(); }
            let left: node& = nodes[i];
            let right: node& = nodes[sibling];
            right.n = left.n - half;
            for j in right.n {
                right.data[j] = left.data[half + j];
                right.data[FAN + j] = left.data[FAN + half + j];
                right.data[CHILD + j] = left.data[CHILD + half + j];
            }
            left.n = half;
            if k > half {
                dst = sibling;
                slot = k - half;
            }
        }
        let inner: node& = nodes[dst];
        open_inner(inner, slot);
        inner.data[slot] = key;
        inner.data[FAN + slot] = max_count;
        inner.data[CHILD + slot] = child;
        if sibling == 0 {
            fix(nodes, p, level, 0, max_count);
            return;
        }
        if level == 0 {
            new_root(nodes, tree, p.ids[0], sibling, false);
            return;
        }
        fix(nodes, p, level, MAX_COUNT, 0);
        child = sibling;
        leaf = false;
        level -= 1;
        k = p.pos[level] + 1;
    }
}

fn insert(nodes: node[>..]&, tree: tree&, p: path&, k: i64, idx: i64, cnt: i64) {
    let i = p.ids[p.h];
    var dst = i;
    var slot = k;
    var sibling = 0;
    if nodes[i].n == LEAF_CAP {
        let half = LEAF_CAP / 2;
        sibling = new_node(nodes, tree);
        if sibling == i { corrupt(); }
        let left: node& = nodes[i];
        let right: node& = nodes[sibling];
        right.n = left.n - half;
        for j in right.n {
            right.data[j] = left.data[half + j];
            right.data[LEAF_CAP + j] = left.data[LEAF_CAP + half + j];
        }
        left.n = half;
        if k > half {
            dst = sibling;
            slot = k - half;
        }
    }
    let leaf: node& = nodes[dst];
    open_leaf(leaf, slot);
    leaf.data[slot] = idx;
    leaf.data[LEAF_CAP + slot] = cnt;
    if sibling == 0 {
        fix(nodes, p, p.h, 0, cnt);
    } else if p.h == 0 {
        new_root(nodes, tree, p.ids[0], sibling, true);
    } else {
        fix(nodes, p, p.h, MAX_COUNT, 0);
        add_child(nodes, tree, p, p.h - 1, p.pos[p.h - 1] + 1, sibling, true);
    }
}

fn remove(nodes: node[>..]&, tree: tree&, p: path&, k: i64) {
    let leaf: node& = nodes[p.ids[p.h]];
    let count = leaf.data[LEAF_CAP + k];
    close_leaf(leaf, k);
    if leaf.n > 0 || p.h == 0 {
        fix(nodes, p, p.h, count, 0);
        return;
    }
    drop_node(nodes, tree, p.ids[p.h]);
    var level = p.h - 1;
    loop {
        let inner: node& = nodes[p.ids[level]];
        let slot = p.pos[level];
        let old_max = inner.data[FAN + slot];
        close_inner(inner, slot);
        if inner.n > 0 {
            fix(nodes, p, level, old_max, 0);
            break;
        }
        if level == 0 { corrupt(); }
        drop_node(nodes, tree, p.ids[level]);
        level -= 1;
    }
    while tree.height > 0 {
        let r = tree.root;
        if bad_num(nodes.len, r) { corrupt(); }
        if nodes[r].n != 1 { break; }
        tree.root = nodes[r].data[CHILD];
        tree.height -= 1;
        drop_node(nodes, tree, r);
    }
}

fn take(nodes: node[>..]&, tree: tree&, p: path&, k: i64, cnt: i64) {
    let leaf: node& = nodes[p.ids[p.h]];
    let count = leaf.data[LEAF_CAP + k];
    if count <= cnt {
        remove(nodes, tree, p, k);
        return;
    }
    leaf.data[k] = span_sum(leaf.data[k], cnt);
    leaf.data[LEAF_CAP + k] = count - cnt;
    fix(nodes, p, p.h, count, count - cnt);
}

// A short free span at the end still contributes to an extending allocation.
fn take_tail(nodes: node[>..]&, tree: tree&, p: path&, length: i64, cnt: i64) -> i64 {
    var i = tree.root;
    for level in p.h {
        if bad_in(nodes, i) { corrupt(); }
        let k = nodes[i].n - 1;
        p.ids[level] = i;
        p.pos[level] = k;
        i = nodes[i].data[CHILD + k];
    }
    p.ids[p.h] = i;
    if bad_leaf(nodes, i) { corrupt(); }
    let k = nodes[i].n - 1;
    if k < 0 || span_sum(nodes[i].data[k], nodes[i].data[LEAF_CAP + k]) != length { return length; }
    let idx = nodes[i].data[k];
    take(nodes, tree, p, k, cnt);
    return idx;
}

fn place(nodes: node[>..]&, tree: tree&, length: i64, cnt: i64) -> i64 {
    if cnt == 0 || nodes.len == 0 { return length; }
    var p = path { h: tree.height, .. };
    if bad_h(p.h) { corrupt(); }
    var before = default<i64[24]>();
    var i = tree.root;
    for level in p.h {
        if bad_in(nodes, i) { corrupt(); }
        let inner: node& = nodes[i];
        var k = 0;
        var largest = 0;
        while k < inner.n && inner.data[FAN + k] < cnt {
            let count = inner.data[FAN + k];
            if count > largest { largest = count; }
            k += 1;
        }
        if k == inner.n { return take_tail(nodes, tree, p, length, cnt); }
        p.ids[level] = i;
        p.pos[level] = k;
        before[level] = largest;
        i = inner.data[CHILD + k];
    }
    if bad_leaf(nodes, i) { corrupt(); }
    let leaf: node& = nodes[i];
    var k = 0;
    var largest = 0;
    while k < leaf.n && leaf.data[LEAF_CAP + k] < cnt {
        let count = leaf.data[LEAF_CAP + k];
        if count > largest { largest = count; }
        k += 1;
    }
    if k == leaf.n { return take_tail(nodes, tree, p, length, cnt); }
    before[p.h] = largest;
    p.ids[p.h] = i;
    p.pos[p.h] = k;
    let idx = leaf.data[k];
    var count = leaf.data[LEAF_CAP + k];
    var after = 0;
    var j = k;
    if count > cnt {
        after = count - cnt;
        leaf.data[k] = span_sum(idx, cnt);
        leaf.data[LEAF_CAP + k] = after;
        j += 1;
    } else if leaf.n > 1 || p.h == 0 {
        close_leaf(leaf, k);
    } else {
        remove(nodes, tree, p, k);
        return idx;
    }

    // Reuse the maxima of the siblings already scanned during first fit.
    var level = p.h;
    while level > 0 {
        let inner: node& = nodes[p.ids[level - 1]];
        let child: node& = nodes[p.ids[level]];
        let slot = p.pos[level - 1];
        let old_max = inner.data[FAN + slot];
        let key = child.data[0];
        var new_max = old_max;
        if count == old_max {
            let offset = if level == p.h { LEAF_CAP } else { FAN };
            let scanned = if before[level] > after { before[level] } else { after };
            new_max = most(child, offset, j, scanned, count);
        }
        if inner.data[slot] == key && new_max == old_max { break; }
        inner.data[slot] = key;
        inner.data[FAN + slot] = new_max;
        count = old_max;
        after = new_max;
        j = slot + 1;
        level -= 1;
    }
    return idx;
}

// A successor in a different leaf can touch the range only if its subtree's
// first key equals end. In that case q follows that subtree's left edge.
fn near(nodes: node[>..]&, tree: tree&, p: path&, q: path&, idx: i64, end: i64) -> i64, i64, bool {
    let k = find(nodes, tree, p, idx);
    if k + 1 < nodes[p.ids[p.h]].n { return k, k + 1, false; }
    var level = p.h - 1;
    while level >= 0 && p.pos[level] + 1 >= nodes[p.ids[level]].n { level -= 1; }
    if level < 0 || nodes[p.ids[level]].data[p.pos[level] + 1] != end { return k, -1, false; }

    q.h = p.h;
    for j in level + 1 {
        q.ids[j] = p.ids[j];
        q.pos[j] = p.pos[j];
    }
    q.pos[level] += 1;
    while level < q.h {
        let i = nodes[q.ids[level]].data[CHILD + q.pos[level]];
        level += 1;
        if (if level < q.h { bad_in(nodes, i) } else { bad_leaf(nodes, i) }) { corrupt(); }
        q.ids[level] = i;
        q.pos[level] = 0;
    }
    return k, 0, true;
}

fn release(nodes: node[>..]&, tree: tree&, p: path&, successor: path&,
           k: i64, next_slot: i64, idx: i64, cnt: i64) {
    let i = p.ids[p.h];
    let next_id = successor.ids[successor.h];
    let leaf: node& = nodes[i];
    let next_leaf: node& = nodes[next_id];
    let prev = k >= 0 && span_sum(leaf.data[k], leaf.data[LEAF_CAP + k]) == idx;
    let next = next_slot >= 0 && span_sum(idx, cnt) == next_leaf.data[next_slot];
    if prev {
        let count = leaf.data[LEAF_CAP + k];
        let next_count = if next { next_leaf.data[LEAF_CAP + next_slot] } else { 0 };
        let merged = span_sum(span_sum(count, cnt), next_count);
        leaf.data[LEAF_CAP + k] = merged;
        if next && next_id == i { close_leaf(leaf, next_slot); }
        fix(nodes, p, p.h, count, merged);
        if next && next_id != i { remove(nodes, tree, successor, next_slot); }
    } else if next {
        let count = next_leaf.data[LEAF_CAP + next_slot];
        let merged = span_sum(count, cnt);
        next_leaf.data[next_slot] = idx;
        next_leaf.data[LEAF_CAP + next_slot] = merged;
        fix(nodes, successor, successor.h, count, merged);
    } else {
        insert(nodes, tree, p, k + 1, idx, cnt);
    }
}

fn release_run(nodes: node[>..]&, tree: tree&, idx: i64, cnt: i64) {
    if cnt <= 0 { return; }
    if nodes.len == 0 {
        nodes.push(node { .. });
        tree.chain = 0;
        tree.height = 0;
        tree.root = new_node(nodes, tree);
    }
    var p = path { .. };
    var q = path { .. };
    let k, next_slot, crosses_leaf = near(nodes, tree, p, q, idx, span_sum(idx, cnt));
    let successor: path& = if crosses_leaf { q } else { p };
    release(nodes, tree, p, successor, k, next_slot, idx, cnt);
}

fn regrow(nodes: node[>..]&, tree: tree&, length: i64, idx: i64, old: i64, cnt: i64) -> i64 {
    if nodes.len == 0 {
        release_run(nodes, tree, idx, old);
        return place(nodes, tree, length, cnt);
    }
    let end = span_sum(idx, old);
    var p = path { .. };
    var q = path { .. };
    let k, next_slot, crosses_leaf = near(nodes, tree, p, q, idx, end);
    let successor: path& = if crosses_leaf { q } else { p };
    if next_slot >= 0 {
        let leaf: node& = nodes[successor.ids[successor.h]];
        let count = leaf.data[LEAF_CAP + next_slot];
        let extra = cnt - old;
        if leaf.data[next_slot] == end && (count >= extra || span_sum(end, count) == length) {
            take(nodes, tree, successor, next_slot, extra);
            return idx;
        }
    }
    release(nodes, tree, p, successor, k, next_slot, idx, old);
    return place(nodes, tree, length, cnt);
}

fn trim_pages(nodes: node[>..]&, tree: tree&, items: u8[:], elem: i64) -> bool {
    if nodes.len == 0 || items.len <= 0 || elem <= 0 { return true; }
    let count = items.len / elem;
    var p = path { h: tree.height, .. };
    if bad_h(p.h) { corrupt(); }
    p.ids[0] = tree.root;
    if (if p.h > 0 { bad_in(nodes, p.ids[0]) } else { bad_leaf(nodes, p.ids[0]) }) { corrupt(); }

    var level = 0;
    var visits = 0;
    while level >= 0 {
        let entry: node& = nodes[p.ids[level]];
        if p.pos[level] == 0 {
            visits += 1;
            if visits >= nodes.len { corrupt(); }
        }
        if level == p.h {
            for k in entry.n {
                let idx = entry.data[k];
                let cnt = entry.data[LEAF_CAP + k];
                if idx < 0 || cnt <= 0 || idx > count || cnt > count - idx { corrupt(); }
                let lo = idx * elem;
                let hi = (idx + cnt) * elem;
                // Compare page numbers before multiplying, so rounding lo up
                // cannot overflow even at the largest representable length.
                let start_page = lo / PAGE + (if lo % PAGE == 0 { 0 } else { 1 });
                let end_page = hi / PAGE;
                if start_page < end_page {
                    let pages = items[start_page * PAGE..end_page * PAGE];
                    for byte in pages.len { pages[byte] = 0; }
                }
            }
            level -= 1;
        } else if p.pos[level] >= entry.n {
            level -= 1;
        } else {
            let i = entry.data[CHILD + p.pos[level]];
            p.pos[level] += 1;
            level += 1;
            if (if level < p.h { bad_in(nodes, i) } else { bad_leaf(nodes, i) }) { corrupt(); }
            p.ids[level] = i;
            p.pos[level] = 0;
        }
    }
    return true;
}
