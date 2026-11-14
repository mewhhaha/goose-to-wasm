// A span tree the program wrote wrong aborts in the slice pool externs, at
// the program's call into slice_pool: here a free span's node number edited
// past the nodes, reached through a program function.
import slice_pool;

fn take(pool: slice_pool<i64>&, n: i64) -> i64[:] {
    return pool.alloc_slice(n);
}

fn main() {
    var pool = slice_pool<i64> {};
    let a = take(pool, 2);
    let b = take(pool, 3);
    pool.free_slice(a);
    print(take(pool, 1).len, " ", b.len);
    pool.tree.root = 99;
    print(take(pool, 1).len);
    print("unreachable");
}
