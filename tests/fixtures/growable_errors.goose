extern fn bench_input() -> i64;
fn main() {
    let mode = bench_input();
    var values: i64[>..<] = [1, 2];
    if mode == 0 { values.resize(-1); }
    if mode == 1 { values.pop_n(-1); }
    if mode == 2 { values.pop_n(3); }
    if mode == 3 { values.clear(); values.pop(); }
    if mode == 4 { values.clear(); values.resize(1); }
    if mode == 5 || mode == 6 { let index = bench_input(); print(values[index]); }
    if mode == 7 { let high = bench_input(); print(values[..high]); }
    print("unexpected success");
}
