fn each<F>(xs: i64&, ys: i64&) { F(if true { xs } else { ys }); }
fn main() { var a = 7; var b = 8; each(a, b) { v => print(v) }; print(a, " ", b); }
