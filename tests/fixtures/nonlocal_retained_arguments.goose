recursive fn make(n: i64) -> i64[>..] { return [n, n + 1]; }
inline fn hold(owned: i64[>..], xs: const i64[:]) -> const i64[:] {
    if xs.len > 0 { return xs; } xs
}
fn use(xs: const i64[:], n: i64) -> i64 { xs.len + n }
fn leave(n: i64) -> i64 { if n > 0 { return 7 from target; } 0 }
fn target(n: i64) -> i64 { use(hold([9], make(n)), leave(n)) }
fn main() { print(target(0)); print(target(1)); }
