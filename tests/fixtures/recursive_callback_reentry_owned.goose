extern fn bench_input() -> i64;
inline fn apply<F>(n: i64) -> i64[u8] { F(n) }
recursive fn descend(n: i64) -> i64[u8] {
    if n <= 0 { return [7, 8]; }
    return apply(n - 1) { x => descend(x) };
}
fn main() {
    let n = bench_input();
    var total = 0;
    for i in 1000 {
        let values = descend(n);
        total += values.len + values[0] + values[1];
    }
    print(total);
}
