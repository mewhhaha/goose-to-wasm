fn bench_input() -> i64 { return 5; }
var neighbor: i64[>..] = [987654321];
recursive fn dive(n: i64) -> i64 {
    if n <= 0 { return 0; }
    let values: i64[1024] = [n; 1024];
    let previous = dive(n - 1);
    return previous + values[n % 1024];
}
fn main() { dive(bench_input()); }