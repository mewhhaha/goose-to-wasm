recursive fn sum(n: i64) -> i64 { if n == 0 { return 0; } return n + sum(n - 1); }
fn main() { print(sum(4)); }
