extern fn bench_input() -> i64;
fn observed() -> bool { print("called"); return true; }
fn main() {
    let n = bench_input();
    print(n > 0 && observed());
    print(n <= 0 || observed());
    print(if n > 0 { n * 3 } else { -n });
}
