var a: i64[>..] = [1]; var b: i64[>..] = [2,3];
fn f(var p: i64[>..]&) -> i64 { p .= b; p.len }
fn main() { assert(f(a)==2); print("plain rebind ok"); }
