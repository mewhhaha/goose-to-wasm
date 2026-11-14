fn bench_input() -> i64 { return 5; }
var values: i64[>..] = [1]; var neighbor: i64[>..] = [987654321];
fn reset() -> i64 { values = [if bench_input() >= 0 { return 7; } else { 1 }; 1000000]; return 0; }
fn main() { reset(); values[bench_input()] = 123; }