struct Inner { tag: u8, values: i64[>..] }
struct Middle { id: i64, inner: Inner }
struct Outer { tag: u16, middle: Middle }
recursive fn make(n: i64) -> Outer { var p = Outer { 1, Middle { n, Inner { 2, [n, n + 1] } } }; return p; }
recursive fn changed(p: Outer) -> Outer { p.middle.id += 10; p.middle.inner.values[0] += 20; return p; }
export fn tick(n: i64) -> i64 {
    let a = make(n); let b = copy(a); let c = changed(copy(a));
    let kept: const i64& = a.middle.id; b.middle.inner.values[0] += 100;
    if kept != n || a.middle.inner.values[0] != n || b.middle.inner.values[0] != n + 100 || c.middle.id != n + 10 || c.middle.inner.values[0] != n + 20 { abort("bad nested copy"); }
    for i in 100 { if make(i).middle.inner.values[1] != i + 1 { abort("bad nested temporary"); } }
    if kept != n || a.middle.inner.values[0] != n { abort("overwritten nested owner"); }
    return n + 1;
}
fn main() {}