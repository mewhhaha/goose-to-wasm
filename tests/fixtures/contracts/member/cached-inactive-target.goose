fn a::deep() -> i64 { return 7 from outer; }
fn a::outer() -> i64 { a::deep() }
fn b::outer() -> i64 { a::deep() }
fn main() { print(a::outer()); print(b::outer()); }
