// A holder result is checked by the references it holds: its owned copy of
// the slice holds none, but its view field still points into the local.
struct Mixed { v: i64[], r: const i64[:] }
fn mixed(xs: const i64[:]) -> Mixed { return Mixed { v: xs, r: xs }; }
fn target() -> Mixed {
    var xs: i64[] = [7, 8];
    return mixed(xs[..]);
}
fn main() { let h = target(); print(h.v, " ", h.r); }
