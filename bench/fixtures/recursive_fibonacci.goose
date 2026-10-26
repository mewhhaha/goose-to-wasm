extern fn bench_input() -> i64;
extern fn bench_clock() -> i64;
extern fn bench_barrier(value: i64) -> i64;
extern fn bench_sink(value: i64);
recursive fn kernel(n: i64) -> i64 {
    if n < 2 { return n; }
    return kernel(n - 1) + kernel(n - 2);
}
fn main() {
    let input = bench_input();
    let warmups = bench_input();
    for warmup in warmups { bench_sink(kernel(bench_barrier(input))); }
    let started = bench_clock();
    let n = bench_barrier(input);
    let checksum = kernel(n);
    bench_sink(checksum);
    let elapsed = bench_clock() - started;
    print(checksum);
    print(elapsed);
}
