struct n::T { v: i64 }
fn n::f(x: T, y: i64) -> i64 { x.v + y }
fn main() { fn f(x: i64) -> i64 { x } let t = n::T { 3 }; print(t.f(2)); }
