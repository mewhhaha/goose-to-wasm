extern fn bench_input() -> i64;
inline fn hinted(n: i64) -> i64 { return n + 1; }
fn automatic(n: i64) -> i64 { return n + 2; }
inline fn separate(n: i64) -> i64 {
    recursive fn leave(take_exit: bool) -> i64 {
        if take_exit { return n from separate; }
        return 0;
    }
    return leave(n >= 0) + 10;
}
recursive fn driver(n: i64) -> i64 {
    return hinted(n) * 10000 + automatic(n) * 100 + separate(n);
}
fn main() { print(driver(bench_input())); }
