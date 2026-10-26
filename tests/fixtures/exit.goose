extern fn bench_input() -> i64;
fn main() { print("before exit"); exit(bench_input()); }
