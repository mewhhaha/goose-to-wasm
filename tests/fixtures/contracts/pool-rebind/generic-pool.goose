reusable var a: i64[>..] = [1]; reusable var b: i64[>..] = [2,3];
fn identity<T>(r: T) -> T { r }
fn f(var p: i64[>..]&) -> i64 { p .= identity(&b); p.len }
fn main() { assert(f(a)==2); print("generic pool rebind ok"); }
