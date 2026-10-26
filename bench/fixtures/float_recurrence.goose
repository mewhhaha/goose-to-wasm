extern fn bench_input() -> i64;
extern fn bench_clock() -> i64;
extern fn bench_barrier(value: i64) -> i64;
extern fn bench_sink(value: i64);
fn kernel(count: i64) -> i64 {
    var value: f64 = 0.5;
    for i in count { value = (value * 1.0000001 + 0.000001) / 1.0000002; }
    return (value * 1000000.0) as! i64;
}
fn main() {
    let input = bench_input();
    let warmups = bench_input();
    for warmup in warmups { bench_sink(kernel(bench_barrier(input))); }
    let started = bench_clock();
    let count = bench_barrier(input);
    let checksum = kernel(count);
    bench_sink(checksum);
    let elapsed = bench_clock() - started;
    print(checksum);
    print(elapsed);
}
