extern fn bench_input() -> i64;
fn main() {
    let a: i32 = bench_input() as! i32;
    let b: i32 = bench_input() as! i32;
    print(a / b, " ", a % b);
}
