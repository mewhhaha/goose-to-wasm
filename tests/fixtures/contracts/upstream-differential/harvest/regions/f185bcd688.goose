fn bench_input() -> i64 { return 5; }
var neighbor: i64[>..] = [987654321];
recursive fn target(depth: i64) -> i64[>..], i64[>..], i64 {
    if depth > 0 { return target(depth - 1); }
    recursive fn leave() { return [7], [8], 9 from target; }
    leave(); return [], [], 0;
}
fn main() { let left, right, n = target(bench_input()); print(n); }