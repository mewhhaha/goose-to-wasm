extern fn bench_input() -> i64;
inline fn bridge(n: i64) -> i64 {
    if n == 0 { return 0; }
    return cycle(n - 1) + 1;
}
recursive fn cycle(n: i64) -> i64 { return bridge(n) + 2; }
fn main() { print(cycle(bench_input())); }
