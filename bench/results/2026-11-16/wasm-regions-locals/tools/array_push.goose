extern fn bench_input() -> i64;
extern fn bench_clock() -> i64;
extern fn bench_barrier(value: i64) -> i64;
extern fn bench_sink(value: i64);
// One growable array filled by push, then read back.
fn kernel(count: i64) -> i64 {
    var values: i64[>..] = [];
    for i in count { values.push(i * 3); }
    var sum: i64 = 0;
    for value in values { sum = (sum + value) % 1000000007; }
    return sum;
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
