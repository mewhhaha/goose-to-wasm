fn g(n: i64) -> i64 { left(n); right(n); 0 }
recursive fn left(n: i64) { bridge(n); }
recursive fn right(n: i64) { bridge(n); }
recursive fn bridge(n: i64) { if n > 0 { if n > 1 { left(n - 1); } else { right(n - 1); } return; } return 42 from g; }
fn main() { print(g(2)); }
