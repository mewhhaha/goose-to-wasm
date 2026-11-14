// A function returning a reference into its argument keeps the argument's
// root, so returning that reference into a local escapes the local.
fn first(xs: i64[]&) -> i64& { return xs[0]; }
fn target() -> i64& {
    var xs: i64[] = [7];
    return first(xs);
}
fn main() { print(target()); }
