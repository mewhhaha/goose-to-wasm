fn make(v: i64) -> i64[] { [v, v + 1, v + 2] }
fn main() { var total: i64 = 0; var i: i64 = 0; while i < 10000 { i += 1; for value in make(1) { if value == 2 { continue; } total += value; if value == 3 { break; } } if i % 2 == 0 { continue; } for value in make(1) { total += value; } } print(total); }
