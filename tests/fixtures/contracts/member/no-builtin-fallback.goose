struct n::T { v: i64 }
fn n::str(x: T, y: i64) -> i64 { x.v + y }
fn main() { let t = n::T { 3 }; print(t.str()); }
