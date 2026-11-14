fn bench_input() -> i64 { return 5; }
recursive fn make(n: i64) -> i64[>..] { return [n, n + 1]; }
fn churn(a: i64[>..], b: i64[>..], c: i64[>..]) -> i64 {
    return a[bench_input() % 2] + b[bench_input() % 2] + c[bench_input() % 2];
}
fn observe(view: const i64[:], marker: i64) -> i64 { return view[0] + view[1] + marker; }
export fn tick(n: i64) -> i64 {
    let got = observe((block { var local: i64[>..] = [n, n + 1]; break copy(local); })[..], churn([900, 901], [910, 911], [920, 921]));
    return got - n - 2730;
}
fn main() {}