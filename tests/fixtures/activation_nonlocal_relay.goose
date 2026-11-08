extern fn bench_input() -> i64;
recursive fn scalar_leaf(n: i64) -> i64 { return n * 3 + 1; }
recursive fn scalar_relay(n: i64) -> i64 { return scalar_leaf(n) + 2; }
recursive fn target(flag: bool) -> i64 {
    let scratch: i64[1024] = [7; 1024];
    recursive fn leave(take_exit: bool) -> i64 {
        if take_exit { return 41 from target; }
        return 1;
    }
    recursive fn relay(take_exit: bool) -> i64 { return leave(take_exit) + 1; }
    let saved = scratch[0];
    return relay(flag) + saved;
}
fn main() {
    let n = bench_input();
    var total = 0;
    for i in 10000 { total += target(n > 0); }
    print(total, " ", scalar_relay(n));
}
