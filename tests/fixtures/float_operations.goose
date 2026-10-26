extern fn bench_input_f64() -> f64;
fn main() {
    let a = bench_input_f64();
    let b = bench_input_f64();
    print(a + b, " ", a - b, " ", a * b, " ", a / b);
    let x: f32 = a as! f32;
    let y: f32 = b as! f32;
    print(x + y, " ", x * y, " ", x / y);
    print(a < b, " ", a == b, " ", a != b);
}
