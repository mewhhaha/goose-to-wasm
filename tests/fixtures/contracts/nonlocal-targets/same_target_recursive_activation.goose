recursive fn target(n: i64) -> i64 { walk(n); return 9; }
recursive fn walk(n: i64) { if n > 0 { target(n - 1); return; } return 42 from target; }
fn main() { print(target(0), target(2)); }
