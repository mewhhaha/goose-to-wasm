extern fn bench_input() -> i64;
fn indexed(xs: i64[:], index: i64, v: i64) {
    var j = xs.len - 1;
    while j > 0 && xs[j - 1] > v { xs[index] = xs[j - 1]; j--; }
}
fn divided(xs: i64[:], divisor: i64, v: i64) {
    var j = xs.len - 1;
    while j > 0 && xs[j - 1] > v { xs[j / divisor] = xs[j - 1]; j--; }
}
fn main() {
    let mode = bench_input(); let value = bench_input(); let v = bench_input();
    var xs = [4, 5, 6]; print("before ", mode);
    if mode == 0 { indexed(xs[..], value, v); }
    else { divided(xs[..], value, v); }
    print("done");
}
