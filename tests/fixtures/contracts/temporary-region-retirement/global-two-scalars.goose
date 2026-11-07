fn make(v: i64) -> i64[] { [v, v + 1, v + 2] }
let first = make(7).len;
let second = make(9).len;
fn main() { var total: i64 = 0; for i in 0..10000 { for value in make(1) { total += value; } } print(first + second, " ", total); }
