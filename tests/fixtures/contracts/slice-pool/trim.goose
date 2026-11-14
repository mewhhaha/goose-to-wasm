// slice_pool<u8>'s trim gives the complete pages inside free spans back to
// the OS, which reads them back as zeros, and keeps every live byte.
import slice_pool;

fn fill(s: u8[:], v: u8) { for i in s.len { s[i] = v; } }

fn all(s: u8[:], v: u8) -> bool {
    for b in s { if b != v { return false; } }
    return true;
}

fn main() {
    var pool = slice_pool<u8> {};
    print(pool.trim());
    let a = pool.alloc_slice(5000);
    let b = pool.alloc_slice(70000);
    let c = pool.alloc_slice(3000);
    fill(a, 1); fill(b, 2); fill(c, 3);
    print(pool.trim(), " ", all(b, 2));
    pool.free_slice(b);
    print(pool.trim(), " ", all(a, 1), " ", all(c, 3), " ", b[b.len / 2]);
    let d = pool.alloc_slice(70000);
    print(pool.items.range_index(d), " ", all(d, 0));
}
