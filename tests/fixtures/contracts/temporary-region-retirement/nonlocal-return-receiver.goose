fn make(v: i64) -> i64[] { [v, v + 1, v + 2] }
fn escape() -> i64[] { fn leave() { return [9, 10, 11] from escape; } for value in make(1) { leave(); } [0] }
fn main() { var total: i64 = 0; for i in 0..10000 { for value in escape() { total += value; } } print(total); }
