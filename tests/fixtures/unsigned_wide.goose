extern fn bench_input() -> i64;
fn main() {
    let a = bench_input() as! u64;
    let b = bench_input() as! u64;
    print(a, " ", b, " ", a / b, " ", a % b, " ", a >> 1, " ", a + 1);
}
