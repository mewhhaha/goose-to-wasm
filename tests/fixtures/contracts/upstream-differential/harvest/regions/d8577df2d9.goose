fn bench_input() -> i64 { return 5; }
var values: i64[>..] = [9]; var neighbor: i64[>..] = [987654321];
fn mutate<F>(xs: i64[>..]&) { xs = [F(); 4294967296]; }
fn target() -> i64 { mutate(values) { if bench_input() >= 0 { return 7; } 4 }; return 0; }
fn main() { print(target()); }