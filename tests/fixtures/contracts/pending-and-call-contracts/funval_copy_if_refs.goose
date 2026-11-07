fn each<F>(xs: i64[>..]&, ys: i64[>..]&, c: bool) { F(if c { xs } else { ys }); }
fn main() { var a: i64[>..] = [1, 2, 3]; var b: i64[>..] = [4, 5]; each(a, b, true) { v => print(v.len) }; }
