fn target<T>(x: T, n: i64) -> T { walk(n); return x; }
recursive fn walk(n: i64) { if n == 0 { return 42 from target; } let z: i32 = 7; target(z, n - 1); }
fn main() { let a: i64 = 1; print(target(a, 1)); }
