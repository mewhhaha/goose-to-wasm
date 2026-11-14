fn bench_input() -> i64 { return 5; }
fn main() {
    var values: i64[>..] = [1]; var neighbor: i64[>..] = [987654321];
    loop { values = [if bench_input() >= 0 { break; } else { 1 }; 1000000]; }
    values[bench_input()] = 123;
}