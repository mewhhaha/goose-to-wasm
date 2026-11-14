fn bench_input() -> i64 { return 5; }
struct Inner { id: i64, values: i64[>..] }
struct Outer { tag: u8, inner: Inner }
recursive fn make(n: i64) -> Outer {
    var p = Outer { 1, Inner { 2, [3] } };
    p = Outer { 4, Inner { 5, [if n >= 0 { return Outer { 6, Inner { 7, [8] } }; } else { 9 }; 1000000] } };
    return p;
}
export fn tick(n: i64) -> i64 {
    let p = make(n); if p.tag != 6 || p.inner.id != 7 || p.inner.values.len != 1 || p.inner.values[0] != 8 { abort("bad nested early exit"); } return n + 1;
}
fn main() {}