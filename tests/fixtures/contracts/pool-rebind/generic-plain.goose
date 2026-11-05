reusable var a: i64[>..] = [1]; var b: i64[>..] = [2,3];
fn identity<T>(r: T) -> T { r }
fn f(var p: i64[>..]&) { p .= identity(&b); }
fn main() { f(a); }
