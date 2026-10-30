extern fn bench_input() -> i64;
extern fn bench_input_f64() -> f64;
var calls: i64 = 0;
fn left(x: f64) -> f64 { calls = calls * 10 + 1; x }
fn right(y: f64) -> f64 { calls = calls * 10 + 2; y }
fn main() {
    let count = bench_input();
    for i in count {
        let x = bench_input_f64();
        let y = bench_input_f64();
        let a = x as! f32;
        let b = y as! f32;
        var wide = x;
        var narrow = a;
        wide %= y;
        narrow %= b;
        calls = 0;
        print(left(x) % right(y), " ", a % b, " ", wide, " ", narrow, " ", calls);
    }
}
