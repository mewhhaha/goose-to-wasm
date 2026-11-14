fn consume(a: i64[>..], b: i64[>..]) -> i64 { return a[0] + b[0] + 1; }
export fn tick(n: i64) -> i64 { return consume([n], [if n % 2 == 0 { return n + 1; } else { 0 }]); }
fn main() {}