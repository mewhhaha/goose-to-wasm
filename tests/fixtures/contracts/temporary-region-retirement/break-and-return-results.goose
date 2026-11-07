fn make(v: i64) -> i64[] { [v, v + 1, v + 2] }
fn choose(n: i64) -> i64[] { if n == 0 { return make(7); } loop { for ignored in make(1) {} break make(4); } }
fn main() { var total: i64 = 0; for i in 0..10000 { for value in choose(i % 2) { total += value; } } print(total); }
