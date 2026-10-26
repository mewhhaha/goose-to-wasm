extern fn bench_input() -> i64;
extern fn bench_input_f64() -> f64;
fn main() {
    let count = bench_input();
    for i in count {
        let value = bench_input_f64();
        print(value, " ", value as! f32);
    }
}
