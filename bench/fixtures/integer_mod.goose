extern fn bench_input() -> i64;
extern fn bench_clock() -> i64;
extern fn bench_barrier(value: i64) -> i64;
extern fn bench_sink(value: i64);
fn kernel(count: i64) -> i64 {
    var value: i64 = 1;
    var checksum: i64 = 0;
    for i in count {
        value = (value * 48271) % 2147483647;
        checksum = (checksum + value) % 1000000007;
    }
    return checksum;
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
