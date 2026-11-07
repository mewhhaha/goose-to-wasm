const COUNT = 3;
fn main() { var total: i64 = 0; for i in 0..10000 { for value in [2; COUNT] { total += value; } } print(total); }
