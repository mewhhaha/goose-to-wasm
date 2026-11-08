extern fn bench_input() -> i64;
recursive fn recur(n: i64) -> i64 {
    if n == 0 { return 0; }
    return recur(n - 1) + n;
}
recursive fn driver(n: i64) -> i64 { return recur(n) + 1; }
fn main() { print(driver(bench_input())); }
