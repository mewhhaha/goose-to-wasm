fn each<F>(xs: i64[>..]&, ys: i64[>..]&) { F(if true { xs } else { ys }); }
fn main() { var a: i64[>..] = [1, 2, 3]; var b: i64[>..] = [4, 5]; each(a, b) { v: i64[>..]& => print(v.len) }; }
