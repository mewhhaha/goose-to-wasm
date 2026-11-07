fn each<F>(xs: i64[>..]&) { F(xs); }
fn main() { var a: i64[>..] = [1, 2, 3]; each(a) { v => print(v.len) }; }
