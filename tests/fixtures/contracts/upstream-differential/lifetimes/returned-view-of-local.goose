// A function returning a view of its argument keeps the argument's root, so
// returning that view of a local escapes the local (§9.2 Return).
fn view(xs: const i64[:]) -> const i64[:] { return xs; }
fn target() -> const i64[:] {
    var xs: i64[] = [7, 8];
    return view(xs[..]);
}
fn main() { print(target()); }
