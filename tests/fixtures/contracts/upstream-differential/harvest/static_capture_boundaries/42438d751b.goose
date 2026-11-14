recursive fn copy_view(xs: const i64[:]) -> i64[>..] { return xs; }
fn target() -> i64[>..] {
    var xs: i64[>..] = [7, 8];
    recursive fn leave() { return copy_view(xs[..]) from target; }
    leave(); return [];
}
fn main() { print(target()); }