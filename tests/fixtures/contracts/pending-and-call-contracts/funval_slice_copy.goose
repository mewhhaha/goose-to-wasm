fn each<F>(xs: const u8[:], ys: const u8[:]) { F(if true { xs } else { ys }); }
fn main() { each("abc", "def") { v => print(v) }; }
