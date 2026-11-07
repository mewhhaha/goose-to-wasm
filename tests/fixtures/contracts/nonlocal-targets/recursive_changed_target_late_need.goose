fn target<T>(x: T, n: i64) -> T { walk(n); return x; }
recursive fn walk(n: i64) { if n > 0 { let z: i32 = 7; target(z, n - 1); return; } return 42 from target; }
fn main() { let a: i64 = 1; print(target(a, 1)); }
