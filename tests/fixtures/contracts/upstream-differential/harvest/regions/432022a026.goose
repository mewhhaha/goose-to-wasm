fn make(n: i64) -> i64[>..] { return [n, n + 1]; }
export fn tick(n: i64) -> i64 { let values = make(n); return values[1]; }
fn main() {}