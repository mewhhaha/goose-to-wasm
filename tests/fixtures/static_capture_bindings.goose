extern fn bench_input() -> i64;
var calls = 0;
fn grown<F>() -> i64[>..] { return F(); }
fn bindings(n: i64) -> i64, i64, i64, i64, i64 {
    var first = n; var second = n + 10;
    var route: i64& = first;
    var source = [n + 20, n + 30, n + 40];
    var view: i64[:] = source[..1];
    var total = 0;
    recursive fn redirect() -> i64, i64 {
        route .= second; view = source[1..]; total += 1;
        route += 100; view[0] += 200; return total, view.len;
    }
    let count, length = redirect();
    return first, second, route, view[0], count + length;
}
fn main() {
    let n = bench_input(); let a, b, c, d, e = bindings(n); print(a, " ", b, " ", c, " ", d, " ", e);
    let values = grown() { calls++; [n + 1, n + 2, n + 3] }; print(values, " ", calls);
    print(grown() { calls++; [4, 5, 6] }, " ", calls);
}
