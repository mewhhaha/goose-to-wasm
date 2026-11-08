extern fn bench_input() -> i64;
fn outer(seed: i64, depth: i64) -> i64 {
    var count = seed;
    inline fn add(value: i64) -> i64 { count += value; return count; }
    recursive fn work(n: i64) -> i64 {
        if n == 0 { return add(1); }
        let before = add(n);
        let inner = work(n - 1);
        let after = add(-n);
        return before + inner + after;
    }
    let result = work(depth);
    return result * 100 + count;
}
fn main() {
    let n = bench_input();
    print(outer(5, n), " ", outer(0, n));
}
