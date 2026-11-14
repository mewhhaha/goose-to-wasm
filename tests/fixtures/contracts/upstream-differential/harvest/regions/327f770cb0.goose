fn bench_input() -> i64 { return 5; }
var first: i64[>..] = [];
var second: i64[>..] = [];
fn main() {
    let count = bench_input(); first.resize(count, 0); first[0] = 987654321;
    second.resize(count, 11); print(first, second);
}