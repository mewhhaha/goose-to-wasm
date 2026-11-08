extern fn bench_input() -> i64;
recursive fn read() -> i64 { return bench_input(); }
inline fn helper(n: i64) -> i64 { return read() + n; }
recursive fn driver(n: i64) -> i64 { return helper(n); }
fn main() { print(driver(3)); }
