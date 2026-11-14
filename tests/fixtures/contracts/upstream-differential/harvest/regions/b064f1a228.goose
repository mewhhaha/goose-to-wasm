recursive fn make(n: i64) -> i64[] { return [n, n + 1]; }
recursive fn changed(values: i64[]) -> i64[u32] { values[0] += 10; return values; }
fn first(values: const i64[:]) -> i64 { return values[0]; }
export fn tick(n: i64) -> i64 {
    let a = make(n); let b = changed(copy(a));
    if a[0] != n || b[0] != n + 10 || b.len != 2 { abort("bad variable copy"); }
    for i in 100 { if first(make(i)) != i { abort("bad variable temporary"); } }
    return n + 1;
}
fn main() {}