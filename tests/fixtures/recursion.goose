extern fn bench_input() -> i64;
recursive fn fib(n: i64) -> i64 {
    if n < 2 { return n; }
    return fib(n - 1) + fib(n - 2);
}
fn twice(x) { x + x }
fn main() {
    let n = bench_input();
    print(fib(n), " ", twice(n));
}
