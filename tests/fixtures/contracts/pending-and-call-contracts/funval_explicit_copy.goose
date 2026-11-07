fn each<F>(xs: i64[>..]&, ys: i64[>..]&) { F(if true { copy(xs) } else { copy(ys) }); }
fn main() { var a: i64[>..] = [1, 2, 3]; var b: i64[>..] = [4, 5]; each(a, b) { v => print(v.len) }; }
