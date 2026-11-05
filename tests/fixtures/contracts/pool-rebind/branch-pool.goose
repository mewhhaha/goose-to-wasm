reusable var a: i64[>..] = [1]; reusable var b: i64[>..] = [2,3];
fn f(var p: i64[>..]&, q: i64[>..]&, r: i64[>..]&, first: bool) -> i64 { p .= if first { q } else { r }; p.len }
fn main() { assert(f(a,a,b,false)==2); print("branch pool rebind ok"); }
