fn bench_input() -> i64 { return 5; }
recursive fn make(n: i64) -> i64[>..] { return [n, n + 1]; }
struct Defaulted { value: i64 = make(1).len }
fn churn(a: i64[>..], b: i64[>..], c: i64[>..]) -> i64 {
    return a[bench_input() % 2] + b[bench_input() % 2] + c[bench_input() % 2];
}
export fn tick(n: i64) -> i64 {
    var remaining = 20;
    while make(remaining).len == 2 && remaining > 0 { remaining--; }
    var total = 0;
    for value in make(n) { make(200); churn([900, 901], [910, 911], [920, 921]); total += value; }
    let defaults = default<Defaulted[300]>();
    return total + defaults[299].value - n - 2;
}
fn main() {}