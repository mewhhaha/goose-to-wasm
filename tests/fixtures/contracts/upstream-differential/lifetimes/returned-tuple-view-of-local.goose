// Each result is checked apart: the owned copy is free to leave, the view
// of the local is not.
fn two(xs: const i64[:]) -> i64[], const i64[:] { return xs, xs; }
fn target() -> i64[], const i64[:] {
    var xs: i64[] = [7, 8];
    return two(xs[..]);
}
fn main() { let a, b = target(); print(a, " ", b); }
