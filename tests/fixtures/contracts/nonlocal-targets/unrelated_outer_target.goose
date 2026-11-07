fn outer(n: i64) -> i64 { target(n); return 0; }
fn target(n: i64) { walk(n); }
recursive fn walk(n: i64) { if n > 0 { middle(n); return; } return 21 from outer; }
recursive fn middle(n: i64) { walk(n - 1); }
fn main() { print(outer(3), outer(0)); }
