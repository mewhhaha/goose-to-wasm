fn pair() -> i64[], i64[] { return [1, 2], [7, 8]; }
fn main() { var total: i64 = 0; for i in 0..10000 { let a, b = pair(); for value in a { total += value; } for value in b { total += value; } } print(total); }
