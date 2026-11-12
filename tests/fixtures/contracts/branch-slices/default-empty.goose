// default<T[:]>() is an empty slice with no storage, so a branch may produce
// it where the other branch produces a borrowed slice.
fn pick(a: bool, xs: const i64[:]) -> i64 {
    let s = if a { xs } else { default<const i64[:]>() };
    return s.len;
}
fn pick_mutable(a: bool, xs: i64[:]) -> i64 {
    let s = if a { xs } else { default<i64[:]>() };
    return s.len;
}
fn main() {
    var v = [1, 2, 3];
    print(pick(true, v), " ", pick(false, v), " ", pick_mutable(true, v), " ", pick_mutable(false, v));
}
