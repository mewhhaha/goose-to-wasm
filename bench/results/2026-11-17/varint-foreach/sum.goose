extern fn bench_input() -> i64;
extern fn bench_clock() -> i64;
recursive fn measure(xs: const varint[:]) -> i64 {
    var sum: i64 = 0;
    for x in xs { sum += x; }
    return sum;
}
fn main() {
    let count = bench_input();
    var xs: varint[>..] = [];
    for i in count { xs.push((i % 5 - 2) * 8193); }
    let started = bench_clock();
    let sum = measure(xs);
    let elapsed = bench_clock() - started;
    print(sum);
    print(elapsed);
}
