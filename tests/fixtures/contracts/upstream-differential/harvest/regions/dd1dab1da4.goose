fn bench_input() -> i64 { return 5; }
recursive fn make(n: i64) -> i64[>..] { return [n, n + 1]; }
fn keep(owned: i64[>..], view: const i64[:]) -> const i64[:] { owned.push(99); return view; }
inline fn relay(owned: i64[>..], view: const i64[:]) -> const i64[:] {
    let body_temporary = make(200).len; if body_temporary != 2 { abort("bad body temp"); } return view;
}
fn churn(a: i64[>..], b: i64[>..], c: i64[>..]) -> i64 {
    return a[bench_input() % 2] + b[bench_input() % 2] + c[bench_input() % 2];
}
fn observe(view: const i64[:], marker: i64) -> i64 { return view[0] + view[1] + marker; }
export fn tick(n: i64) -> i64 {
    let got = observe(relay([90], keep([80], make(n))), churn([900, 901], [910, 911], [920, 921]));
    return got - n - 2730;
}
fn main() {}