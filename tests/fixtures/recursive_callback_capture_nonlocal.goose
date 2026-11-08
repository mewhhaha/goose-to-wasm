extern fn bench_input() -> i64;
inline fn invoke<F>(n: i64) -> i64 {
    var owned: i64[>..] = [n, n + 1];
    let got = F(n);
    return got + owned[0] + owned[1];
}
recursive fn target(n: i64) -> i64 {
    var local = n * 10;
    let got = invoke(n) { x =>
        local += x;
        if x == 2 { return local + 100 from target; }
        local
    };
    if n <= 0 { return got; }
    return got + target(n - 1);
}
fn main() {
    let n = bench_input();
    var total = 0;
    for i in 1000 { total += target(n); }
    print(total, " ", target(1));
}
