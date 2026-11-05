struct H { f: i64 }
fn f(x: H) -> i64 { x.f }
fn main() { let h = H { 3 }; print(h.f()); }
