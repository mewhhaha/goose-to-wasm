var calls: i64 = 0;
fn make() -> i64[] { calls += 1; [1, 2, 3] }
fn main() { var total: i64 = 0; for i in 0..10000 { for &value in make() { total += value; } } print(total, " ", calls); }
