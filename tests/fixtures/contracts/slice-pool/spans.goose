// std's slice_pool keeps its free spans in a span tree that the runtime's
// slice pool externs maintain through node[>..]& and tree& references:
// first fit, merging with both neighbours, growth in place and by moving,
// copies, and enough spans for inner levels, checked against a model.
import slice_pool;

fn at(pool: slice_pool<i64>&, s: i64[:]) -> i64 { pool.items.range_index(s) }

fn fill(s: i64[:], from: i64) { for i in s.len { s[i] = from + i; } }

fn basics() {
    var pool = slice_pool<i64> {};
    let a = pool.alloc_slice(3);
    let b = pool.alloc_slice(2);
    let c = pool.alloc_slice(4);
    fill(a, 10); fill(b, 20); fill(c, 30);
    pool.free_slice(a);
    pool.free_slice(c);
    let d = pool.alloc_slice(2);              // first fit: a's span
    print(at(pool, d), " ", d, " ", pool.items.len);
    pool.free_slice(b);                       // merges with what is left of a and with c
    let e = pool.alloc_slice(8);              // the merged span [2, 9)
    print(at(pool, e), " ", pool.items.len, " ", e.len);
    // Growth in place at the end, then by moving past a live run.
    let f = pool.realloc_slice(e, 10);
    print(at(pool, f), " ", pool.items.len);
    fill(f, 100);
    let g = pool.alloc_slice(1);
    let h = pool.realloc_slice(d, 5);         // d cannot grow in place: it moves
    print(at(pool, h), " ", h[0], " ", h[1], " ", h[4], " ", g.len);
    let k = pool.alloc_copy(f[3..6]);
    print(at(pool, k), " ", k);
    let shrunk = pool.realloc_slice(f, 2);    // frees the tail
    let m = pool.alloc_slice(3);              // reuses it
    print(at(pool, shrunk), " ", at(pool, m), " ", m);
    pool.recycle_all();
    let n = pool.alloc_slice(pool.items.len);
    print(at(pool, n), " ", n.len, " ", pool.items.len);
}

// Many small runs, every other one freed, make the tree grow inner levels;
// freeing the rest merges everything back into one span.
fn many() {
    var pool = slice_pool<i64> {};
    var runs: i64[:][>..] = [];
    for i in 400 { runs.push(pool.alloc_slice(1 + i % 3)); }
    for i in 200 { pool.free_slice(runs[2 * i]); }
    print(pool.tree.height > 0, " ", pool.nodes.len > 2);
    // Requests of 1 to 3 elements land in freed runs, first fit, never at the end.
    var total = 0;
    for i in 50 { let s = pool.alloc_slice(1 + i % 3); total += s.len; runs[2 * i] = s; }
    let end = pool.items.len;
    print(total, " ", end);
    for i in 200 { pool.free_slice(runs[2 * i + 1]); }
    for i in 50 { pool.free_slice(runs[2 * i]); }
    for i in 50..200 { pool.free_slice(runs[2 * i]); }
    let all = pool.alloc_slice(end);
    print(at(pool, all), " ", pool.items.len, " ", pool.tree.height);
}

fn main() {
    basics();
    many();
}
