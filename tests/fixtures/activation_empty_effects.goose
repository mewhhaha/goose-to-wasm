extern fn bench_input() -> i64;

recursive fn scalar(n: i64) -> i64 { return n * 3 + 1; }
recursive fn recursive_scalar(n: i64) -> i64 {
    if n <= 0 { return 0; }
    return recursive_scalar(n - 1) + 1;
}
recursive fn owned(n: i64) -> i64 {
    var values: i64[>..] = [];
    for i in n + 1 { values.push(n + i); }
    return values[0] + values.len;
}
recursive fn fixed(n: i64) -> i64 {
    var values: u8[8192] = [0; 8192]; values[0] = n as u8;
    return values[0] as i64 + values[8191] as i64;
}
recursive fn empty_relay(n: i64) -> i64 {
    return scalar(n) + recursive_scalar(n) + owned(n) + fixed(n);
}
recursive fn borrowed_fill(out: i64[>..]&, n: i64) {
    out.push(n); out.append([n + 1, n + 2]);
}
recursive fn owner(n: i64) -> i64[>..] {
    var values: i64[>..] = []; borrowed_fill(values, n); return values;
}
recursive fn call_unknown(callback: fn(i64) -> i64, n: i64) -> i64 { return callback(n); }
recursive fn capture_outer(n: i64) -> i64 {
    let base = n + 2;
    recursive fn plus(value: i64) -> i64 { return base + value; }
    return call_unknown(plus, n);
}
enum Which { A, B }
recursive fn choose(which: Which.A, n: i64) -> i64 { return n + 10; }
recursive fn choose(which: Which.B, n: i64) -> i64 { return n + 20; }
recursive fn dispatch(n: i64) -> i64 {
    let which: Which = if n % 2 == 0 { Which.A } else { Which.B };
    return choose(which, n);
}
recursive fn call_extern() -> i64 { return bench_input(); }
recursive fn cloned(n: i64) -> i64 {
    var values: i64[>..] = [n]; let separate = copy(values); return separate[0];
}
recursive fn asserted(n: i64) -> i64 { assert(n > 0); return n; }
fn main() {
    let n = bench_input();
    if n <= 0 { print(asserted(n)); return; }
    var total = 0;
    for i in 10000 { total += empty_relay(n); }
    print(total); print(owner(n)); print(capture_outer(n)); print(dispatch(n));
    print(call_extern()); print(cloned(n)); print(asserted(n));
}
