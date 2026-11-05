reusable var a: i64[>..] = [1]; reusable[] var b: i64[>..] = [];
fn f(var p: i64[>..]&, q: i64[>..]&) { p .= q; }
fn main() { f(b,a); }
