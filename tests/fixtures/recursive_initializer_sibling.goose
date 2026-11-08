extern fn bench_input() -> i64;
recursive fn read(n: i64) -> i64 { return bench_input() + n; }
inline fn helper(n: i64) -> i64 {
    let a, b = 1, read(n);
    return a + b;
}
recursive fn driver(n: i64) -> i64 { return helper(n); }
fn main() { print(driver(3)); }
