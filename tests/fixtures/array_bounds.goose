extern fn bench_input() -> i64;
fn main() {
    let values = [3, 5, 7];
    print(values[bench_input()]);
}
