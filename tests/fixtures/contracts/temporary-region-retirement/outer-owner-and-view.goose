fn make(v: i64) -> i64[] { [v, v + 1, v + 2] }
fn main() { var keep: i64[] = make(7); let view: const i64[:] = keep; var total: i64 = 0; for i in 0..10000 { for value in make(1) { total += value; } } var saved: i64 = 0; for value in view { saved += value; } print(total, " ", saved); }
