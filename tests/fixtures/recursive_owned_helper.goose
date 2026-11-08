extern fn bench_input() -> i64;
inline fn weight(n: i64) -> i64 {
    var values: i64[>..] = [n, n + 1];
    values.push(n + 2);
    return values[0] + values[1] + values[2];
}
recursive fn sum(n: i64) -> i64 {
    if n == 0 { return 0; }
    let value = weight(n);
    return value + sum(n - 1);
}
fn main() {
    let n = bench_input();
    var total = 0;
    for i in 1000 { total += sum(n); }
    print(total);
}
