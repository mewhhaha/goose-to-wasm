var a: i64[>..] = [1]; var b: i64[>..] = [2,3];
fn identity<T>(x: T) -> T { x }
fn f(var p: i64[>..]&) { p .= identity(&b); }
fn main() { f(a); print("contextual plain call ok"); }
