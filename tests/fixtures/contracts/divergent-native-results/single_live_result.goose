fn one(c: bool) -> i64 { if c { return 11; } else { 22 } }
fn two(n: i64) -> i64 { match n { 0 => { return 33; }, _ => 44 } }
fn main() { print(one(true), " ", one(false), " ", two(0), " ", two(1)); }
