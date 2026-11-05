fn f(x: i64) -> i64 { x + 1 }
fn apply<f>(x: i64) -> i64 { x.f() }
fn main() { print(apply<i64>(3)); }
