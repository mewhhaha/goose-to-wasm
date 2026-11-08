extern fn bench_input() -> i64;
var serial = 0;
inline fn mark(value: i64) -> i64 {
    let before = serial;
    serial += 1;
    return value + before;
}
recursive fn rotate(n: i64, a: i64, b: i64, c: i64) -> i64 {
    if n == 0 { return a * 100 + b * 10 + c; }
    return rotate(n - 1, mark(b), mark(c), mark(a + n));
}
fn main() {
    let result = rotate(bench_input(), 1, 2, 3);
    print(result, " ", serial);
}
