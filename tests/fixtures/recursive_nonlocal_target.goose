extern fn bench_input() -> i64;
recursive fn target(n: i64) -> i64 {
    inline fn leave(value: i64) -> i64 {
        if value == 2 { return 700 + value from target; }
        return value;
    }
    if n == 0 { return leave(0); }
    let before = leave(n);
    let inner = target(n - 1);
    return before + inner;
}
fn main() { print(target(bench_input()), " ", target(1)); }
