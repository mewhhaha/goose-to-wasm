reusable var a: i64[>..] = [1]; var b: i64[>..] = [2,3];
fn f(var p: i64[>..]&, first: bool) { p .= if first { &a } else { &b }; }
fn main() { f(a,false); }
