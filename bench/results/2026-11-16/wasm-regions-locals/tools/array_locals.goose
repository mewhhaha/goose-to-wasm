extern fn bench_input() -> i64;
extern fn bench_clock() -> i64;
extern fn bench_barrier(value: i64) -> i64;
extern fn bench_sink(value: i64);
// A function with a growable array of its own, called in a loop: every call
// takes a data region and gives it back.
fn pair(i: i64) -> i64 {
    var values: i64[>..] = [];
    values.push(i); values.push(i + 1);
    return values[0] + values[1];
}
fn kernel(count: i64) -> i64 {
    var sum: i64 = 0;
    for i in count { sum = (sum + pair(i)) % 1000000007; }
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
