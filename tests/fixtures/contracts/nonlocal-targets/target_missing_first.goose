fn target(n: i64) -> i64 { walk(n); return 0; }
recursive fn walk(n: i64) { if n > 0 { middle(n); return; } return 42 from target; }
recursive fn middle(n: i64) { walk(n - 1); }
fn main() { middle(0); print(target(2)); }
