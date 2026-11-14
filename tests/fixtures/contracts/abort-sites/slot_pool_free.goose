// slot_pool's own abort reports where the program called the pool: free of
// an index past the pool's items, through a program function.
import slot_pool;

fn release(pool: slot_pool<i64>&, i: i64) {
    pool.free(i);
}

fn main() {
    var pool = slot_pool<i64> {};
    let a = pool.alloc_index(10);
    release(pool, a);
    print(pool.alloc_index(11));
    release(pool, 4);
    print("unreachable");
}
