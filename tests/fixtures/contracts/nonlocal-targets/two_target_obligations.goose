fn outer(n: i64) -> i64 { print(inner(n)); return 0; }
fn inner(n: i64) -> i64 { relay(n); return 1; }
fn relay(n: i64) { leaf(n); }
fn leaf(n: i64) { if n == 0 { return 11 from inner; } return 22 from outer; }
fn main() { print(outer(0)); print(outer(1)); }
