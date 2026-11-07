fn g<T>(x: T, n: i64) -> T { right(n); x }
recursive fn left(n: i64) { bridge(n); }
recursive fn right(n: i64) { bridge(n); }
recursive fn bridge(n: i64) { if n == 2 { left(n - 1); return; } if n == 1 { let z: i32 = 7; g(z, 0); return; } return 42 from g; }
fn main() { let x: i64 = 1; print(g(x, 2)); }
